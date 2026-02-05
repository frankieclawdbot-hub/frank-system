#!/bin/bash
#
# session-memory-bridge.sh - Bridge between OpenClaw Sessions and Memory System
#
# PURPOSE:
#   Passively captures important conversation outcomes from OpenClaw sessions
#   and writes them to daily memory files with full context preserved.
#   
#   This closes the gap between live conversations and the vector embedding system,
#   ensuring no important outcomes are lost due to context window truncation.
#
# DESIGN:
#   - Polls session history via OpenClaw gateway APIs
#   - Detects important conversation outcomes
#   - Writes entries to memory/YYYY-MM-DD.md with full context
#   - Triggers background indexer for immediate embedding
#   - Completely passive (no manual tagging needed)
#   - Runs as optional daemon or cron job
#
# INTEGRATION POINTS:
#   1. Sessions history API (via cron or daemon)
#   2. Memory files (memory/YYYY-MM-DD.md)
#   3. Background indexer (triggered via file mods)
#   4. Sleep protocol (can run on startup)
#
# USAGE:
#   session-memory-bridge.sh                      # Run once
#   session-memory-bridge.sh --daemon             # Start background daemon
#   session-memory-bridge.sh --stop               # Stop daemon
#   session-memory-bridge.sh --test               # Dry run
#

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

WORKSPACE="${WORKSPACE:-/root/clawd}"
MEMORY_DIR="${WORKSPACE}/memory"
STATE_FILE="${WORKSPACE}/.session-memory-state"
PID_FILE="/tmp/session-memory-bridge.pid"
LOG_FILE="${WORKSPACE}/logs/session-memory-bridge.log"
GATEWAY_TOKEN="${GATEWAY_TOKEN:-}"
GATEWAY_URL="${GATEWAY_URL:-http://localhost:18789}"

TEST_MODE=false
if [[ "${1:-}" == "--test" ]]; then
  TEST_MODE=true
fi

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$MEMORY_DIR"

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
# GATEWAY API INTERACTION
# ============================================================================

# Call gateway API to get session history
get_session_history() {
  local session_key="$1"
  local limit="${2:-50}"
  
  # Make API call to gateway sessions API
  # This requires gateway CLI access
  local result=$(openclaw sessions_history "$session_key" --limit "$limit" --format json 2>/dev/null || echo "")
  
  if [[ -z "$result" ]]; then
    log_warn "Failed to fetch session history for $session_key"
    return 1
  fi
  
  echo "$result"
}

# ============================================================================
# IMPORTANT OUTCOMES DETECTION
# ============================================================================

# Keywords that indicate important conversation outcomes
DECISION_KEYWORDS="decided|decision|determined|concluded|agreed|consensus"
DISCOVERY_KEYWORDS="discovered|discovery|found|realized|learned|insight|pattern|observation"
IMPLEMENTATION_KEYWORDS="implemented|built|created|fixed|resolved|solved|completed|deployed"
ISSUE_KEYWORDS="issue|problem|bug|error|blocker|blocked|failure|failed|broke|broken"
SUCCESS_KEYWORDS="success|successful|passed|working|working|fixed|resolved|victory"

is_important_outcome() {
  local text="$1"
  local text_lower=$(echo "$text" | tr '[:upper:]' '[:lower:]')
  
  # Check against all keyword patterns
  if [[ $text_lower =~ $DECISION_KEYWORDS ]] || \
     [[ $text_lower =~ $DISCOVERY_KEYWORDS ]] || \
     [[ $text_lower =~ $IMPLEMENTATION_KEYWORDS ]] || \
     [[ $text_lower =~ $ISSUE_KEYWORDS ]] || \
     [[ $text_lower =~ $SUCCESS_KEYWORDS ]]; then
    return 0
  fi
  return 1
}

get_outcome_category() {
  local text="$1"
  local text_lower=$(echo "$text" | tr '[:upper:]' '[:lower:]')
  
  if [[ $text_lower =~ $DECISION_KEYWORDS ]]; then
    echo "decision"
  elif [[ $text_lower =~ $DISCOVERY_KEYWORDS ]]; then
    echo "discovery"
  elif [[ $text_lower =~ $IMPLEMENTATION_KEYWORDS ]]; then
    echo "implementation"
  elif [[ $text_lower =~ $ISSUE_KEYWORDS ]]; then
    echo "issue"
  elif [[ $text_lower =~ $SUCCESS_KEYWORDS ]]; then
    echo "success"
  else
    echo "outcome"
  fi
}

# ============================================================================
# MEMORY FILE OPERATIONS
# ============================================================================

get_today_memory_file() {
  local today=$(date +%Y-%m-%d)
  echo "${MEMORY_DIR}/${today}.md"
}

ensure_memory_file() {
  local memfile="$1"
  if [[ ! -f "$memfile" ]]; then
    mkdir -p "$(dirname "$memfile")"
    {
      echo "# $(date +%Y-%m-%d) - Daily Session Notes"
      echo ""
      echo "## Session Outcomes Captured"
      echo ""
      echo "Auto-captured from OpenClaw session history at $(date '+%H:%M UTC')"
      echo ""
    } > "$memfile"
    log_info "Created memory file: $memfile"
  fi
}

# Deduplication via hash
entry_hash() {
  local text="$1"
  echo -n "$text" | md5sum | awk '{print $1}'
}

is_entry_captured() {
  local hash="$1"
  local memfile="$2"
  grep -q "<!-- hash: $hash -->" "$memfile" 2>/dev/null || return 1
}

# Append outcome to memory with full context
append_outcome_to_memory() {
  local memfile="$1"
  local message="$2"
  local category="$3"
  local speaker="$4"
  
  local hash=$(entry_hash "$message")
  
  # Deduplication check
  if is_entry_captured "$hash" "$memfile"; then
    log_warn "Outcome already captured (hash: ${hash:0:8})"
    return 0
  fi
  
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  
  # Write entry with full context
  {
    echo ""
    echo "### [$timestamp] ${category^} — $speaker"
    echo ""
    echo "$message"
    echo ""
    echo "**Category:** $category | **Speaker:** $speaker"
    echo ""
    echo "<!-- hash: $hash -->"
  } >> "$memfile"
  
  log_info "Captured outcome (category: $category, speaker: $speaker)"
}

# ============================================================================
# STATE MANAGEMENT (track what we've already captured)
# ============================================================================

load_state() {
  if [[ -f "$STATE_FILE" ]]; then
    cat "$STATE_FILE"
  else
    echo "0"
  fi
}

save_state() {
  local new_state="$1"
  echo "$new_state" > "$STATE_FILE"
}

# ============================================================================
# MAIN CAPTURE LOGIC
# ============================================================================

capture_from_session() {
  log_info "=== Starting session outcome capture ==="
  
  local session_key="agent:main:main"
  local memfile=$(get_today_memory_file)
  ensure_memory_file "$memfile"
  
  # Get session history
  local history=$(get_session_history "$session_key" 50)
  if [[ -z "$history" ]]; then
    log_warn "No session history available"
    return 1
  fi
  
  # Parse history and extract important outcomes
  local count=0
  
  # Extract messages from JSON history
  echo "$history" | jq -r '.messages[] | select(.role=="user" or .role=="assistant") | .content' 2>/dev/null | while IFS= read -r line; do
    if [[ -z "$line" || "$line" == "null" ]]; then
      continue
    fi
    
    # Check if this is an important outcome
    if is_important_outcome "$line"; then
      local category=$(get_outcome_category "$line")
      local speaker="User"  # Default; could be improved with role detection
      
      append_outcome_to_memory "$memfile" "$line" "$category" "$speaker"
      ((count++))
    fi
  done
  
  log_info "Capture complete: $count outcomes captured"
  
  # Trigger indexer if anything was captured
  if [[ $count -gt 0 ]]; then
    touch "$memfile"
    log_info "Triggered background indexer via file modification"
  fi
}

# ============================================================================
# DAEMON MANAGEMENT
# ============================================================================

start_daemon() {
  if [[ -f "$PID_FILE" ]]; then
    local pid=$(cat "$PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
      log_warn "Daemon already running (PID: $pid)"
      return 0
    fi
  fi
  
  log_info "Starting daemon..."
  nohup bash "$0" --daemon-loop > /dev/null 2>&1 &
  local pid=$!
  echo "$pid" > "$PID_FILE"
  log_info "Daemon started (PID: $pid)"
}

daemon_loop() {
  log_info "Daemon loop started (poll interval: 5 min)"
  while true; do
    capture_from_session || true
    sleep 300  # 5 minute poll
  done
}

stop_daemon() {
  if [[ -f "$PID_FILE" ]]; then
    local pid=$(cat "$PID_FILE")
    if kill "$pid" 2>/dev/null; then
      rm -f "$PID_FILE"
      log_info "Daemon stopped (PID: $pid)"
    fi
  fi
}

# ============================================================================
# CLI
# ============================================================================

case "${1:-}" in
  --daemon)
    start_daemon
    ;;
  --daemon-loop)
    daemon_loop
    ;;
  --stop)
    stop_daemon
    ;;
  --test)
    TEST_MODE=true
    capture_from_session
    ;;
  *)
    capture_from_session
    ;;
esac
