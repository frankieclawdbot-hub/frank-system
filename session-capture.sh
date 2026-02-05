#!/bin/bash
#
# session-capture.sh - Real-time Session Outcome Capture
#
# PURPOSE: 
#   Passively captures important conversation outcomes and writes them to daily
#   memory files with full context preserved. Complements background indexer by
#   providing the INPUT it needs.
#
# DESIGN:
#   - Watches the main session transcript (JSONL format)
#   - Detects important outcomes (decisions, discoveries, implementations, issues)
#   - Extracts full context (not fragments)
#   - Appends to memory/YYYY-MM-DD.md with metadata
#   - Triggers background indexing via file modification
#   - Runs in background, completely passive
#
# INTEGRATION:
#   - Called from sleep protocol or startup
#   - Can be run continuously as daemon
#   - Safe to run multiple times (deduplication via hash)
#
# USAGE:
#   session-capture.sh --start              # Start as daemon
#   session-capture.sh --once               # Run once (capture current state)
#   session-capture.sh --status             # Check daemon status
#   session-capture.sh --stop               # Stop daemon
#   session-capture.sh --test               # Dry run with verbose output
#

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

WORKSPACE="${WORKSPACE:-/root/clawd}"
SESSIONS_DIR="${WORKSPACE}"
SESSION_KEY="${SESSION_KEY:-agent:main:main}"
MEMORY_DIR="${WORKSPACE}/memory"
CAPTURE_STATE_FILE="/tmp/session-capture.state"
PID_FILE="/tmp/session-capture.pid"
LOG_FILE="/tmp/session-capture.log"

TEST_MODE=false
if [[ "${1:-}" == "--test" ]]; then
  TEST_MODE=true
  LOG_FILE="/dev/stdout"
fi

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ============================================================================
# LOGGING
# ============================================================================

log_info() {
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$timestamp] [INFO] $*" | tee -a "$LOG_FILE"
}

log_warn() {
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$timestamp] [WARN] $*" | tee -a "$LOG_FILE"
}

log_error() {
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$timestamp] [ERROR] $*" | tee -a "$LOG_FILE"
}

# ============================================================================
# DAEMON LIFECYCLE
# ============================================================================

is_running() {
  if [[ -f "$PID_FILE" ]]; then
    local pid=$(cat "$PID_FILE" 2>/dev/null || echo "")
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
    rm -f "$PID_FILE"
  fi
  return 1
}

start_daemon() {
  if is_running; then
    log_warn "Daemon already running (PID: $(cat "$PID_FILE"))"
    return 0
  fi
  
  # Start in background
  nohup bash "$0" --once-loop > /dev/null 2>&1 &
  local daemon_pid=$!
  echo "$daemon_pid" > "$PID_FILE"
  log_info "Daemon started (PID: $daemon_pid)"
}

stop_daemon() {
  if [[ -f "$PID_FILE" ]]; then
    local pid=$(cat "$PID_FILE")
    if kill "$pid" 2>/dev/null; then
      log_info "Daemon stopped (PID: $pid)"
      rm -f "$PID_FILE"
    fi
  fi
}

status_daemon() {
  if is_running; then
    echo -e "${GREEN}✓${NC} Session capture daemon running (PID: $(cat "$PID_FILE"))"
    tail -5 "$LOG_FILE"
  else
    echo -e "${RED}✗${NC} Session capture daemon not running"
  fi
}

# ============================================================================
# IMPORTANT KEYWORDS & DETECTION
# ============================================================================

# These keywords indicate important conversation outcomes
IMPORTANT_KEYWORDS=(
  "decision"
  "decided"
  "discovered"
  "discovery"
  "fixed"
  "resolved"
  "completed"
  "implemented"
  "implemented"
  "created"
  "built"
  "designed"
  "learned"
  "lesson"
  "issue"
  "problem"
  "blocker"
  "blocked"
  "error"
  "bug"
  "pattern"
  "insight"
  "broke"
  "broken"
  "failure"
  "failed"
  "critical"
  "important"
  "success"
  "workaround"
  "disabled"
  "removed"
  "added"
  "changed"
  "modified"
)

is_important_message() {
  local text="$1"
  local text_lower=$(echo "$text" | tr '[:upper:]' '[:lower:]')
  
  for keyword in "${IMPORTANT_KEYWORDS[@]}"; do
    if [[ $text_lower =~ $keyword ]]; then
      return 0
    fi
  done
  return 1
}

get_importance_level() {
  local text="$1"
  local text_lower=$(echo "$text" | tr '[:upper:]' '[:lower:]')
  
  if [[ $text_lower =~ (critical|blocker|blocked|error|bug|broken|failure) ]]; then
    echo "critical"
  elif [[ $text_lower =~ (decision|decided|important|insight|pattern|success) ]]; then
    echo "important"
  else
    echo "reference"
  fi
}

# ============================================================================
# SESSION TRANSCRIPT PROCESSING
# ============================================================================

# Find the main session transcript file
get_session_transcript() {
  # Look for pattern: SESSION_ID.jsonl
  local transcript_path="${SESSIONS_DIR}/5a6335ef-7dc9-479e-bb74-89da394dbb93.jsonl"
  
  if [[ -f "$transcript_path" ]]; then
    echo "$transcript_path"
  else
    # Fallback search
    find "${SESSIONS_DIR}" -maxdepth 1 -name "*main*" -type f 2>/dev/null | head -1 || echo ""
  fi
}

# Extract important messages from transcript since last capture
get_new_important_messages() {
  local transcript="$1"
  local last_line="${2:-0}"
  
  if [[ ! -f "$transcript" ]]; then
    return
  fi
  
  # Skip to line number, extract messages, filter for importance
  tail -n +$((last_line + 1)) "$transcript" 2>/dev/null | while IFS= read -r line; do
    # Parse JSONL (message field)
    if [[ -n "$line" ]]; then
      # Extract the message content and metadata
      local message=$(echo "$line" | jq -r '.message // ""' 2>/dev/null || echo "")
      local sender=$(echo "$line" | jq -r '.sender // "unknown"' 2>/dev/null || echo "unknown")
      local timestamp=$(echo "$line" | jq -r '.timestamp // ""' 2>/dev/null || echo "")
      
      # Only capture user (Tyson) and assistant (Frank) important messages
      if [[ "$message" != "" ]] && is_important_message "$message"; then
        echo "$message"
        echo "SENDER=$sender"
        echo "TIMESTAMP=$timestamp"
        echo "---"
      fi
    fi
  done
}

# ============================================================================
# MEMORY FILE OPERATIONS
# ============================================================================

# Get today's memory file
get_today_memory_file() {
  local today=$(date +%Y-%m-%d)
  echo "${MEMORY_DIR}/${today}.md"
}

# Create memory file if it doesn't exist
ensure_memory_file() {
  local memfile="$1"
  if [[ ! -f "$memfile" ]]; then
    mkdir -p "$(dirname "$memfile")"
    {
      echo "# $(date +%Y-%m-%d) - Session Notes"
      echo ""
      echo "## Important Outcomes"
      echo ""
    } > "$memfile"
    log_info "Created new memory file: $memfile"
  fi
}

# Generate hash for deduplication
entry_hash() {
  local text="$1"
  echo -n "$text" | md5sum | awk '{print $1}'
}

# Check if entry already captured
is_entry_captured() {
  local hash="$1"
  local memfile="$2"
  grep -q "<!-- hash: $hash -->" "$memfile" 2>/dev/null || return 1
}

# Append important message to memory file
append_to_memory() {
  local memfile="$1"
  local message="$2"
  local importance="$3"
  local sender="$4"
  
  local hash=$(entry_hash "$message")
  
  # Deduplication check
  if is_entry_captured "$hash" "$memfile"; then
    log_warn "Entry already captured (hash: $hash)"
    return 0
  fi
  
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  
  # Format entry with full context
  {
    echo ""
    echo "### [$timestamp] $sender - ${importance^}"
    echo ""
    echo "$message"
    echo ""
    echo "<!-- hash: $hash -->"
  } >> "$memfile"
  
  log_info "Appended entry to memory (importance: $importance, hash: ${hash:0:8})"
}

# ============================================================================
# MAIN CAPTURE LOOP
# ============================================================================

capture_once() {
  log_info "=== Running capture cycle ==="
  
  local transcript=$(get_session_transcript)
  if [[ -z "$transcript" || ! -f "$transcript" ]]; then
    log_warn "Session transcript not found: $transcript"
    return 1
  fi
  
  # Load state (line count we've processed)
  local last_line=0
  if [[ -f "$CAPTURE_STATE_FILE" ]]; then
    last_line=$(cat "$CAPTURE_STATE_FILE" 2>/dev/null || echo "0")
  fi
  
  local memfile=$(get_today_memory_file)
  ensure_memory_file "$memfile"
  
  # Process new messages
  local count=0
  get_new_important_messages "$transcript" "$last_line" | while IFS= read -r line; do
    if [[ "$line" == "---" ]]; then
      continue
    elif [[ "$line" == SENDER=* ]]; then
      sender="${line#SENDER=}"
    elif [[ "$line" == TIMESTAMP=* ]]; then
      timestamp="${line#TIMESTAMP=}"
    else
      # This is the message content
      if [[ -n "$line" ]]; then
        importance=$(get_importance_level "$line")
        append_to_memory "$memfile" "$line" "$importance" "${sender:-unknown}"
        ((count++))
      fi
    fi
  done
  
  # Update state: save line count
  wc -l < "$transcript" > "$CAPTURE_STATE_FILE"
  
  log_info "Capture cycle complete: $count entries processed"
  
  # Trigger background indexer if we captured anything
  if [[ $count -gt 0 ]]; then
    if command -v touch &> /dev/null; then
      touch "$memfile"  # Update modification time to trigger indexer
      log_info "Triggered background indexer via file modification"
    fi
  fi
}

capture_loop() {
  log_info "Starting continuous capture loop (interval: 60s)"
  while true; do
    capture_once || true
    sleep 60
  done
}

# ============================================================================
# CLI
# ============================================================================

case "${1:-}" in
  --start)
    start_daemon
    ;;
  --stop)
    stop_daemon
    ;;
  --status)
    status_daemon
    ;;
  --once)
    capture_once
    ;;
  --once-loop)
    capture_loop
    ;;
  --test)
    TEST_MODE=true
    capture_once
    ;;
  *)
    echo "Usage: $0 {--start|--stop|--status|--once|--test}"
    echo ""
    echo "Commands:"
    echo "  --start   Start as background daemon"
    echo "  --stop    Stop the daemon"
    echo "  --status  Check daemon status"
    echo "  --once    Run capture once"
    echo "  --test    Run once with verbose output"
    exit 1
    ;;
esac
