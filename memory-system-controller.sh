#!/bin/bash
#
# memory-system-controller.sh - Hybrid: Keyword + AI Judgment
#
# This script coordinates between:
# 1. Background indexer (detects new content, extracts chunks)
# 2. Main agent (spawns Franklin judges when needed)
# 3. Queue processor (embeds judged entries)
#

set -e

WORKSPACE="/root/clawd"
MEMORY_DIR="$WORKSPACE/memory"
CHUNK_DIR="/tmp/memory-chunks-ai"
QUEUE_FILE="$MEMORY_DIR/importance-queue.jsonl"
MARKER_DIR="/tmp/memory-markers"
LOG_FILE="/tmp/memory-system.log"

mkdir -p "$CHUNK_DIR" "$MARKER_DIR" "$MEMORY_DIR"
touch "$QUEUE_FILE"

log() { echo "[$(date '+%H:%M:%S')] $*" >> "$LOG_FILE"; echo "$*" >&2; }

# Check for markers that need Franklin judgment
check_markers() {
    local markers=$(find "$MARKER_DIR" -name "*.marker" -type f 2>/dev/null | wc -l)
    echo "$markers"
}

# Create marker for chunk that needs Franklin judgment
create_marker() {
    local chunk_file="$1"
    local marker_file="$MARKER_DIR/$(basename "$chunk_file" .json).marker"
    echo "$chunk_file" > "$marker_file"
    log "Created marker: $(basename "$marker_file")"
}

# Process markers (called by main agent, not background indexer)
process_markers() {
    local processed=0
    
    for marker in "$MARKER_DIR"/*.marker; do
        [[ -f "$marker" ]] || continue
        
        local chunk_file=$(cat "$marker" 2>/dev/null)
        if [[ -f "$chunk_file" ]]; then
            log "Processing marker: $(basename "$marker")"
            
            # Write Franklin task
            local task_file="$MARKER_DIR/task-$(basename "$chunk_file" .json).txt"
            cat > "$task_file" << EOF
You are MemoryJudge. Read $chunk_file (JSON messages).

Judge each message:
- Substantive? (>50 chars, not trivial)
- Meaningful? (decision, discovery, feeling, philosophy)
- Importance: 1-10

Write importance >= 6 to $QUEUE_FILE as JSON lines:
{"timestamp":"ISO8601","category":"decision|discovery|...","importance":8,"text":"...","hash":"md5","source":"franklin"}

Be selective. Capture what matters.
EOF
            
            # Note: Main agent (Frank) will spawn Franklin when sees this
            log "Task ready for Franklin: $(basename "$chunk_file")"
            ((processed++))
            
            # Remove marker (main agent will handle actual spawning)
            rm -f "$marker"
        else
            rm -f "$marker"
        fi
    done
    
    echo "$processed"
}

# Embed from queue
embed_queue() {
    if [[ ! -s "$QUEUE_FILE" ]]; then
        return 0
    fi
    
    local count=$(wc -l < "$QUEUE_FILE")
    log "Embedding $count entries from queue..."
    
    local embedded=0
    while IFS= read -r entry; do
        [[ -z "$entry" ]] && continue
        
        local text=$(echo "$entry" | jq -r '.text // empty')
        local category=$(echo "$entry" | jq -r '.category // "outcome"')
        
        if [[ -n "$text" ]]; then
            if python3 "$WORKSPACE/memory-embed.py" --add "$text" --category "$category" --source "memory-judge" 2>/dev/null; then
                ((embedded++))
            fi
        fi
    done < "$QUEUE_FILE"
    
    > "$QUEUE_FILE"
    log "Embedded $embedded entries"
}

# Main agent check (called periodically by Frank)
main_agent_check() {
    log "Frank checking for memory tasks..."
    
    local markers=$(check_markers)
    if [[ $markers -gt 0 ]]; then
        log "Found $markers chunks needing Franklin judgment"
        log "Frank should spawn Franklin judges now"
        # Return marker count for Frank to handle
        echo "$markers"
    else
        echo "0"
    fi
    
    # Always embed from queue
    embed_queue
}

# Status
show_status() {
    echo "=== Memory System Status ==="
    echo "Markers waiting: $(check_markers)"
    echo "Queue entries: $(wc -l < "$QUEUE_FILE" 2>/dev/null || echo 0)"
    echo "Chunk files: $(ls "$CHUNK_DIR"/*.json 2>/dev/null | wc -l)"
    echo "Last log:"
    tail -5 "$LOG_FILE" 2>/dev/null
}

case "${1:-}" in
    --marker)
        create_marker "$2"
        ;;
    --check)
        main_agent_check
        ;;
    --embed)
        embed_queue
        ;;
    --status)
        show_status
        ;;
    *)
        echo "Usage: $0 {--marker <chunk_file>|--check|--embed|--status}"
        exit 1
        ;;
esac
