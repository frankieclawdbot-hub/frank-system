#!/bin/bash
#
# background-indexer-v2-fixed.sh - Smart Batched Franklin Capture (Fixed)
#

set -e

WORKSPACE="${WORKSPACE:-/root/clawd}"
SESSIONS_DIR="/root/.openclaw/agents/main/sessions"
MEMORY_DIR="$WORKSPACE/memory"
CHUNK_DIR="/tmp/memory-chunks-v2"
QUEUE_FILE="$MEMORY_DIR/importance-queue.jsonl"
STATE_FILE="$WORKSPACE/.memory-capture-state-v2.json"
LOG_FILE="/tmp/background-indexer-v2-fixed.log"

MIN_MESSAGES=5
MAX_WAIT_SECONDS=300
FRANKLIN_FAILURES=0

mkdir -p "$CHUNK_DIR" "$MEMORY_DIR"
touch "$QUEUE_FILE"

log() { echo "[$(date '+%H:%M:%S')] $*" >> "$LOG_FILE"; echo "[$(date '+%H:%M:%S')] $*" >&2; }

# Simple state management
init_state() {
    if [[ ! -f "$STATE_FILE" ]]; then
        echo '{"session_files":{},"total_processed":0}' > "$STATE_FILE"
    fi
}

get_last_line() {
    local file=$(basename "$1")
    jq -r ".session_files[\"$file\"].last_line // 0" "$STATE_FILE" 2>/dev/null || echo 0
}

set_last_line() {
    local file=$(basename "$1")
    local line="$2"
    local tmp="$STATE_FILE.tmp"
    jq ".session_files[\"$file\"] = {\"last_line\":$line,\"last_check\":\"$(date -Iseconds)\"}" "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

# Extract messages using jq (not bash loops)
extract_messages() {
    local session_file="$1"
    local chunk_file="$2"
    local last_line=$(get_last_line "$session_file")
    local total_lines=$(wc -l < "$session_file")
    local new_lines=$((total_lines - last_line))
    
    if [[ $new_lines -le 0 ]]; then
        echo 0
        return
    fi
    
    log "Extracting $new_lines new lines from $(basename "$session_file")"
    
    # Use tail + jq to extract (much faster than bash while loop)
    tail -n "$new_lines" "$session_file" | \
        jq -c 'select(.type == "message") | {role: .message.role, text: (.message.content[]? | select(.type=="text") | .text), timestamp: .timestamp, source: input_filename}' 2>/dev/null | \
        jq -s '.' > "$chunk_file" 2>/dev/null
    
    local count=$(jq 'length' "$chunk_file" 2>/dev/null || echo 0)
    
    # Update state
    set_last_line "$session_file" "$total_lines"
    
    echo "$count"
}

# Queue chunk for MemoryJudge (long-running daemon pattern)
queue_for_judgment() {
    local chunk_file="$1"
    local chunk_name=$(basename "$chunk_file")
    local inbox="/tmp/memory-inbox"
    
    mkdir -p "$inbox"
    
    # Move chunk to inbox for long-running MemoryJudge to process
    local inbox_file="$inbox/chunk-$chunk_name"
    mv "$chunk_file" "$inbox_file"
    
    log "Queued $chunk_name for judgment (inbox: $inbox_file)"
    return 0
}

# Keyword-based fallback extraction
keyword_extract() {
    local chunk_file="$1"
    local queue_file="$2"
    local keywords="decided|discovered|implemented|fixed|issue|success|excited|philosophy|meaningful|journey|wonder|growth"
    
    log "Running keyword-based extraction..."
    
    local count=0
    jq -c '.[]' "$chunk_file" 2>/dev/null | while read msg; do
        local text=$(echo "$msg" | jq -r '.text // empty' | tr '[:upper:]' '[:lower:]')
        [[ -z "$text" ]] && continue
        [[ ${#text} -lt 40 ]] && continue
        
        if echo "$text" | grep -Eq "($keywords)"; then
            local hash=$(echo "$text" | md5sum | head -c 16)
            local ts=$(date -Iseconds)
            echo "{\"timestamp\":\"$ts\",\"category\":\"outcome\",\"importance\":7,\"text\":$(echo "$msg" | jq -r '.text' | jq -Rs .),\"hash\":\"$hash\",\"source\":\"keyword-fallback\"}" >> "$queue_file"
            ((count++))
        fi
    done
    
    log "Keyword extraction: $count entries"
}

# Main cycle
run_cycle() {
    log "Starting capture cycle..."
    init_state
    
    local total_new=0
    local chunk_files=()
    
    # Find session files with new content
    for session_file in "$SESSIONS_DIR"/*.jsonl; do
        [[ -f "$session_file" ]] || continue
        [[ "$session_file" == *".deleted."* ]] && continue
        
        local last_line=$(get_last_line "$session_file")
        local total_lines=$(wc -l < "$session_file")
        local new_lines=$((total_lines - last_line))
        
        if [[ $new_lines -ge $MIN_MESSAGES ]]; then
            local chunk_file="$CHUNK_DIR/chunk-$(basename "$session_file" .jsonl)-$(date +%s).json"
            local extracted=$(extract_messages "$session_file" "$chunk_file")
            
            if [[ $extracted -gt 0 ]]; then
                log "  Extracted $extracted messages"
                chunk_files+=("$chunk_file")
                total_new=$((total_new + extracted))
            fi
        fi
    done
    
    # Process chunks (queue for long-running MemoryJudge)
    if [[ ${#chunk_files[@]} -gt 0 ]]; then
        log "Queuing ${#chunk_files[@]} chunk files for judgment..."
        
        for chunk_file in "${chunk_files[@]}"; do
            queue_for_judgment "$chunk_file"
        done
        
        log "Chunks queued. Long-running MemoryJudge will process them."
    fi
    
    # Embed from queue
    if [[ -s "$QUEUE_FILE" ]]; then
        local queue_count=$(wc -l < "$QUEUE_FILE")
        log "Embedding $queue_count entries from queue..."
        
        # Simple embedding loop
        local embedded=0
        while IFS= read -r entry; do
            [[ -z "$entry" ]] && continue
            
            local text=$(echo "$entry" | jq -r '.text // empty')
            local category=$(echo "$entry" | jq -r '.category // "outcome"')
            
            if [[ -n "$text" ]]; then
                # Call memory-embed.py
                if python3 "$WORKSPACE/memory-embed.py" --add "$text" --category "$category" --source "auto-capture" 2>/dev/null; then
                    ((embedded++))
                fi
            fi
        done < "$QUEUE_FILE"
        
        # Clear queue
        > "$QUEUE_FILE"
        log "Embedded $embedded entries"
    fi
    
    log "Cycle complete"
}

# Daemon mode
daemon_loop() {
    log "Starting smart capture daemon"
    while true; do
        run_cycle 2>&1 | tee -a "$LOG_FILE" || true
        sleep 60
    done
}

# CLI
case "${1:-}" in
    --start)
        [[ -f "/tmp/background-indexer-v2-fixed.pid" ]] && kill $(cat "/tmp/background-indexer-v2-fixed.pid") 2>/dev/null || true
        nohup "$0" --daemon-loop > /dev/null 2>&1 &
        echo $! > "/tmp/background-indexer-v2-fixed.pid"
        log "Daemon started (PID: $!)"
        ;;
    --stop)
        [[ -f "/tmp/background-indexer-v2-fixed.pid" ]] && kill $(cat "/tmp/background-indexer-v2-fixed.pid") 2>/dev/null && log "Daemon stopped"
        rm -f "/tmp/background-indexer-v2-fixed.pid"
        ;;
    --status)
        if [[ -f "/tmp/background-indexer-v2-fixed.pid" ]] && kill -0 $(cat "/tmp/background-indexer-v2-fixed.pid") 2>/dev/null; then
            echo "✅ Running (PID: $(cat "/tmp/background-indexer-v2-fixed.pid"))"
            tail -5 "$LOG_FILE"
        else
            echo "❌ Not running"
        fi
        ;;
    --daemon-loop)
        daemon_loop
        ;;
    --once)
        run_cycle
        ;;
    *)
        echo "Usage: $0 {--start|--stop|--status|--once}"
        exit 1
        ;;
esac
