#!/bin/bash
#
# polling-reporter-daemon.sh - Long-Running Session Monitor
# 
# MemoryJudge Pattern: Spawn once, run continuously, no Franklin spawns
# Checks session status every 10 seconds via direct file parsing
#

set -uo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================
DAEMON_NAME="polling-reporter"
VERSION="2.0.0-no-spawn"
PID_FILE="/tmp/polling-reporter-daemon.pid"
LOG_FILE="/root/clawd/logs/polling-reporter-daemon.log"
STATUS_FILE="/root/clawd/logs/polling-reporter-status.json"

CHECK_INTERVAL=10  # seconds
STALL_THRESHOLD=1800  # 30 minutes in seconds

# ============================================================================
# LOGGING
# ============================================================================

log_info() {
    local message="$1"
    echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $message" | tee -a "$LOG_FILE"
}

log_cycle() {
    local sessions="$1"
    local stalled="$2"
    local blocked="$3"
    local completed="$4"
    local failed="$5"
    
    echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] Reporter cycle complete: $sessions sessions, $stalled stalled, $blocked blocked, $completed completed, $failed failed" | tee -a "$LOG_FILE"
}

# ============================================================================
# SESSION MONITORING (NO SPAWNS - direct file parsing)
# ============================================================================

get_active_sessions() {
    # Count active session files directly (no CLI spawn)
    local count=0
    if [[ -d "/root/.openclaw/agents/main/sessions" ]]; then
        count=$(find /root/.openclaw/agents/main/sessions -name "*.jsonl" -mmin -60 2>/dev/null | wc -l)
    fi
    echo "$count"
}

check_session_health() {
    local session_file="$1"
    local now=$(date +%s)
    local last_modified=$(stat -c %Y "$session_file" 2>/dev/null || echo "$now")
    local age=$((now - last_modified))
    
    if [[ $age -gt $STALL_THRESHOLD ]]; then
        echo "stalled"
    else
        echo "active"
    fi
}

analyze_sessions() {
    local total=0
    local stalled=0
    local blocked=0
    local completed=0
    local failed=0
    
    # Check session files directly
    for session_file in /root/.openclaw/agents/main/sessions/*.jsonl; do
        [[ -f "$session_file" ]] || continue
        
        total=$((total + 1))
        
        # Check modification time for staleness
        local status
        status=$(check_session_health "$session_file")
        
        if [[ "$status" == "stalled" ]]; then
            stalled=$((stalled + 1))
        fi
        
        # Parse last few lines for completion/failure indicators
        # Using grep directly on file (no spawn)
        if tail -20 "$session_file" 2>/dev/null | grep -q '"role":"assistant".*completion\|completed\|success'; then
            completed=$((completed + 1))
        elif tail -20 "$session_file" 2>/dev/null | grep -q 'error\|failed\|timeout'; then
            failed=$((failed + 1))
        fi
    done
    
    # Output results
    jq -n \
        --argjson total "$total" \
        --argjson stalled "$stalled" \
        --argjson blocked "$blocked" \
        --argjson completed "$completed" \
        --argjson failed "$failed" \
        '{
            timestamp: now | todate,
            sessions: $total,
            stalled: $stalled,
            blocked: $blocked,
            completed: $completed,
            failed: $failed
        }'
}

# ============================================================================
# MAIN DAEMON LOOP
# ============================================================================

shutdown_requested=false

handle_shutdown() {
    log_info "Shutdown signal received, stopping daemon..."
    shutdown_requested=true
}

trap 'handle_shutdown' TERM INT
trap '' HUP

daemon_main() {
    log_info "Starting $DAEMON_NAME v$VERSION (PID: $$)"
    log_info "Mode: Long-running daemon, no Franklin spawns"
    log_info "Check interval: ${CHECK_INTERVAL}s, Stall threshold: ${STALL_THRESHOLD}s"
    
    # Write PID
    echo $$ > "$PID_FILE"
    
    # Ensure log directory exists
    mkdir -p "$(dirname "$LOG_FILE")"
    mkdir -p "$(dirname "$STATUS_FILE")"
    
    while [[ "$shutdown_requested" == "false" ]]; do
        local cycle_start=$(date +%s)
        
        # Analyze sessions (NO SPAWNS - all bash/file operations)
        local report
        report=$(analyze_sessions)
        
        # Log cycle results
        local total stalled blocked completed failed
        total=$(echo "$report" | jq -r '.sessions')
        stalled=$(echo "$report" | jq -r '.stalled')
        blocked=$(echo "$report" | jq -r '.blocked')
        completed=$(echo "$report" | jq -r '.completed')
        failed=$(echo "$report" | jq -r '.failed')
        
        log_cycle "$total" "$stalled" "$blocked" "$completed" "$failed"
        
        # Write status file for other processes to read
        echo "$report" > "$STATUS_FILE"
        
        # Calculate sleep time
        local cycle_end=$(date +%s)
        local elapsed=$((cycle_end - cycle_start))
        local remaining=$((CHECK_INTERVAL - elapsed))
        
        if [[ $remaining -gt 0 && "$shutdown_requested" == "false" ]]; then
            sleep $remaining
        fi
    done
    
    log_info "Daemon stopped"
    rm -f "$PID_FILE"
}

# ============================================================================
# CONTROL COMMANDS
# ============================================================================

cmd_start() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "Daemon already running (PID: $pid)"
            exit 0
        fi
    fi
    
    echo "Starting Polling Reporter Daemon..."
    
    # Double-fork to daemonize properly
    (
        # First fork
        exec 0<&-  # Close stdin
        exec 1>/dev/null  # Redirect stdout
        exec 2>/dev/null  # Redirect stderr
        
        # Second fork - daemon process
        daemon_main &
        DAEMON_PID=$!
        
        # Write PID file
        echo $DAEMON_PID > "$PID_FILE"
    ) &
    
    sleep 1
    
    # Verify it started
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "Daemon started (PID: $pid)"
        else
            echo "Daemon failed to start"
            rm -f "$PID_FILE"
            exit 1
        fi
    fi
}

cmd_stop() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        echo "Stopping daemon (PID: $pid)..."
        kill "$pid" 2>/dev/null
        rm -f "$PID_FILE"
        echo "Daemon stopped"
    else
        echo "Daemon not running"
    fi
}

cmd_status() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "RUNNING (PID: $pid)"
            if [[ -f "$STATUS_FILE" ]]; then
                cat "$STATUS_FILE"
            fi
            exit 0
        else
            echo "STOPPED (stale PID file)"
            rm -f "$PID_FILE"
            exit 1
        fi
    else
        echo "STOPPED"
        exit 1
    fi
}

# ============================================================================
# ENTRY POINT
# ============================================================================

case "${1:-}" in
    start)
        cmd_start
        ;;
    stop)
        cmd_stop
        ;;
    status)
        cmd_status
        ;;
    restart)
        cmd_stop
        sleep 2
        cmd_start
        ;;
    *)
        echo "Usage: $0 {start|stop|status|restart}"
        echo ""
        echo "Long-running session monitor - no Franklin spawns"
        echo "Logs to: $LOG_FILE"
        echo "Status: $STATUS_FILE"
        exit 1
        ;;
esac
