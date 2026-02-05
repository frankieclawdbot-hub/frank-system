#!/bin/bash
#
# memory-stream.sh - Ultra-simple real-time memory capture
#
# PURPOSE:
#   Detect important conversation outcomes and append to stream.log
#   Background indexer watches stream.log and embeds immediately
#
# DESIGN:
#   - Detects keywords indicating important outcomes
#   - Appends to memory/stream.log with timestamp and full context
#   - Background indexer picks up changes automatically
#   - Minimal complexity, maximum reliability
#
# USAGE:
#   memory-stream.sh --daemon              # Start monitoring
#   memory-stream.sh --once                # Capture current session once
#   memory-stream.sh --test                # Dry run, show what would capture
#   memory-stream.sh --stop                # Stop daemon
#

set -euo pipefail

WORKSPACE="${WORKSPACE:-/root/clawd}"
MEMORY_DIR="$WORKSPACE/memory"
STREAM_FILE="$MEMORY_DIR/stream.log"
PID_FILE="/tmp/memory-stream.pid"
LOG_FILE="/tmp/memory-stream.log"

# Keywords that indicate important outcomes
DECISION_KEYWORDS="decided|decision|determined|choose|selected|committed|concluded"
DISCOVERY_KEYWORDS="discovered|found|realized|learned|insight|identified|pattern"
IMPLEMENTATION_KEYWORDS="implemented|deployed|fixed|solved|built|created|integrated"
ISSUE_KEYWORDS="issue|problem|bug|error|blocker|blocked|broken|failed|failure"
SUCCESS_KEYWORDS="success|succeeded|working|resolved|completed|achieved"
ALL_KEYWORDS="$DECISION_KEYWORDS|$DISCOVERY_KEYWORDS|$IMPLEMENTATION_KEYWORDS|$ISSUE_KEYWORDS|$SUCCESS_KEYWORDS"

# Ensure directories exist
mkdir -p "$MEMORY_DIR"
mkdir -p "$(dirname "$LOG_FILE")"

# Create stream file if doesn't exist
if [[ ! -f "$STREAM_FILE" ]]; then
    echo "# Memory Stream - $(date +%Y-%m-%d)" > "$STREAM_FILE"
    echo "# Auto-captured important conversation outcomes" >> "$STREAM_FILE"
    echo "" >> "$STREAM_FILE"
fi

log() {
    echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Get recent session messages
get_session_content() {
    # Use sessions_history to get recent messages
    local content=$(openclaw sessions_history agent:main:main --limit 30 --format text 2>/dev/null || echo "")
    echo "$content"
}

# Check if text contains important keywords
is_important() {
    local text="$1"
    local lower=$(echo "$text" | tr '[:upper:]' '[:lower:]')
    
    if echo "$lower" | grep -Eq "($ALL_KEYWORDS)"; then
        return 0
    fi
    return 1
}

# Get category from text
get_category() {
    local text="$1"
    local lower=$(echo "$text" | tr '[:upper:]' '[:lower:]')
    
    if echo "$lower" | grep -Eq "($DECISION_KEYWORDS)"; then echo "decision"
    elif echo "$lower" | grep -Eq "($DISCOVERY_KEYWORDS)"; then echo "discovery"
    elif echo "$lower" | grep -Eq "($IMPLEMENTATION_KEYWORDS)"; then echo "implementation"
    elif echo "$lower" | grep -Eq "($ISSUE_KEYWORDS)"; then echo "issue"
    elif echo "$lower" | grep -Eq "($SUCCESS_KEYWORDS)"; then echo "success"
    else echo "outcome"
    fi
}

# Generate hash for deduplication
get_hash() {
    echo -n "$1" | md5sum | cut -d' ' -f1
}

# Check if entry already exists
is_duplicate() {
    local hash="$1"
    grep -q "hash:$hash" "$STREAM_FILE" 2>/dev/null && return 0
    return 1
}

# Append entry to stream
append_to_stream() {
    local text="$1"
    local category="$2"
    local hash=$(get_hash "$text")
    
    # Skip if duplicate
    if is_duplicate "$hash"; then
        log "Skip: duplicate (hash:${hash:0:8})"
        return 0
    fi
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S UTC')
    
    # Append to stream file
    {
        echo ""
        echo "---"
        echo "[$timestamp] [$category]"
        echo "$text"
        echo "hash:$hash"
    } >> "$STREAM_FILE"
    
    log "Captured: $category (hash:${hash:0:8})"
}

# Main capture function
capture_cycle() {
    log "Running capture cycle..."
    
    local content=$(get_session_content)
    if [[ -z "$content" ]]; then
        log "No session content available"
        return 0
    fi
    
    local captured=0
    
    # Process each line/paragraph
    echo "$content" | while IFS= read -r line; do
        if [[ -z "$line" ]] || [[ ${#line} -lt 20 ]]; then
            continue
        fi
        
        if is_important "$line"; then
            local category=$(get_category "$line")
            append_to_stream "$line" "$category" && ((captured++))
        fi
    done
    
    log "Cycle complete: captured $captured entries"
}

# Daemon mode
daemon_loop() {
    log "Starting memory-stream daemon (interval: 60s)"
    while true; do
        capture_cycle 2>/dev/null || true
        sleep 60
    done
}

# CLI
start_daemon() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            log "Daemon already running (PID: $pid)"
            return 0
        fi
    fi
    
    nohup "$0" --daemon-loop > /dev/null 2>&1 &
    local new_pid=$!
    echo "$new_pid" > "$PID_FILE"
    log "Daemon started (PID: $new_pid)"
}

stop_daemon() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        kill "$pid" 2>/dev/null && log "Daemon stopped (PID: $pid)"
        rm -f "$PID_FILE"
    fi
}

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
    --once)
        capture_cycle
        ;;
    --test)
        echo "TEST MODE: Would capture from session history"
        local content=$(get_session_content)
        echo "Session content length: ${#content} chars"
        echo ""
        echo "Checking for important outcomes..."
        
        echo "$content" | while IFS= read -r line; do
            if [[ -n "$line" ]] && [[ ${#line} -gt 20 ]] && is_important "$line"; then
                local cat=$(get_category "$line")
                echo "[$cat] ${line:0:80}..."
            fi
        done
        ;;
    *)
        echo "Usage: $0 {--daemon|--stop|--once|--test}"
        echo ""
        echo "Commands:"
        echo "  --daemon  Start as background daemon (polls every 60s)"
        echo "  --stop    Stop the daemon"
        echo "  --once    Run capture once"
        echo "  --test    Dry run, show what would be captured"
        exit 1
        ;;
esac
