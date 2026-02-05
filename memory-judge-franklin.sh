#!/bin/bash
#
# memory-judge-franklin.sh - Long-running MemoryJudge daemon
#
# Spawns ONCE at startup, runs continuously
# Watches /tmp/memory-inbox/ for chunk files
# Judges importance, writes to queue
#

set -e

INBOX="/tmp/memory-inbox"
QUEUE="/root/clawd/memory/importance-queue.jsonl"
LOG="/tmp/memory-judge.log"
PID_FILE="/tmp/memory-judge.pid"

# CALIBRATION: Threshold lowered to 5 (2026-02-05)
# Reason: Length filter (50 chars) already excludes trivial responses.
# Threshold 5 captures more nuance (feelings, philosophy) without noise.
# Previous threshold 6 was filtering meaningful 50-100 char messages.

# Categories
DECISION_KEYWORDS="decided|decision|determined|concluded|agreed|committed"
DISCOVERY_KEYWORDS="discovered|found|realized|learned|insight|understood"
IMPLEMENTATION_KEYWORDS="implemented|built|created|fixed|solved|deployed"
ISSUE_KEYWORDS="issue|problem|bug|error|blocker|failed|broken"
SUCCESS_KEYWORDS="success|achieved|accomplished|resolved|completed"
FEELING_KEYWORDS="excited|feel|feeling|passionate|wonder|meaningful"
PHILOSOPHY_KEYWORDS="philosophy|journey|growth|becoming|purpose|meaning"

# Short messages with sentiment/emotion keywords get captured even if <50 chars
SENTIMENT_KEYWORDS="amazing|wonderful|incredible|brilliant|love|thank|appreciate|proud|impressed|grateful|excited" 
ACKNOWLEDGMENT_KEYWORDS="exactly|yes|agree|right|perfect|great|excellent|well done|good job|nicely done"

mkdir -p "$INBOX"
touch "$QUEUE"

log() {
    echo "[$(date '+%H:%M:%S')] $*" >> "$LOG"
    echo "[MemoryJudge] $*" >&2
}

# Detect category from text
detect_category() {
    local text="$1"
    local lower=$(echo "$text" | tr '[:upper:]' '[:lower:]')
    
    if echo "$lower" | grep -Eq "($DECISION_KEYWORDS)"; then echo "decision"
    elif echo "$lower" | grep -Eq "($DISCOVERY_KEYWORDS)"; then echo "discovery"
    elif echo "$lower" | grep -Eq "($IMPLEMENTATION_KEYWORDS)"; then echo "implementation"
    elif echo "$lower" | grep -Eq "($ISSUE_KEYWORDS)"; then echo "issue"
    elif echo "$lower" | grep -Eq "($SUCCESS_KEYWORDS)"; then echo "success"
    elif echo "$lower" | grep -Eq "($FEELING_KEYWORDS)"; then echo "feeling"
    elif echo "$lower" | grep -Eq "($PHILOSOPHY_KEYWORDS)"; then echo "philosophy"
    else echo "outcome"
    fi
}

# Calculate importance score (1-10)
calculate_importance() {
    local text="$1"
    local category="$2"
    local score=5
    local lower=$(echo "$text" | tr '[:upper:]' '[:lower:]')
    
    # Base score by category
    case "$category" in
        decision) score=8 ;;
        discovery) score=7 ;;
        implementation) score=7 ;;
        issue) score=8 ;;
        success) score=7 ;;
        feeling) score=6 ;;
        philosophy) score=7 ;;
        *) score=5 ;;
    esac
    
    # Adjust by length (substantive = higher)
    local len=${#text}
    if [[ $len -gt 200 ]]; then ((score+=1)); fi
    if [[ $len -gt 500 ]]; then ((score+=1)); fi
    if [[ $len -lt 100 ]]; then ((score-=1)); fi
    
    # Cap at 10
    [[ $score -gt 10 ]] && score=10
    [[ $score -lt 1 ]] && score=1
    
    echo "$score"
}

# Process a chunk file
process_chunk() {
    local chunk_file="$1"
    local count=0
    
    log "Processing: $(basename "$chunk_file")"
    
    # Create temp file for entries
    local tmp_entries="/tmp/memory-judge-entries-$$.tmp"
    > "$tmp_entries"
    
    # Read and judge each message
    while IFS= read -r msg; do
        local text=$(echo "$msg" | jq -r '.text // empty')
        [[ -z "$text" ]] && continue
        
        local len=${#text}
        local category=""
        local importance=5
        local lower=$(echo "$text" | tr '[:upper:]' '[:lower:]')
        
        # Handle short messages (<50 chars) - check for sentiment/acknowledgment
        if [[ $len -lt 50 ]]; then
            if echo "$lower" | grep -Eq "($SENTIMENT_KEYWORDS)"; then
                category="sentiment"
                importance=6
            elif echo "$lower" | grep -Eq "($ACKNOWLEDGMENT_KEYWORDS)"; then
                category="acknowledgment"
                importance=5
            else
                continue  # Skip short messages without sentiment
            fi
        else
            # Long messages: full category detection
            category=$(detect_category "$text")
            importance=$(calculate_importance "$text" "$category")
        fi
        
        # Only write if importance >= 5
        if [[ $importance -ge 5 ]]; then
            local hash=$(echo "$text" | md5sum | head -c 16)
            local ts=$(date -Iseconds)
            
            echo "{\"timestamp\":\"$ts\",\"category\":\"$category\",\"importance\":$importance,\"text\":$(echo "$text" | jq -Rs .),\"hash\":\"$hash\",\"source\":\"memory-judge\"}" >> "$tmp_entries"
            ((count++))
        fi
    done < <(jq -c '.[]' "$chunk_file" 2>/dev/null)
    
    # Append to queue if we have entries
    if [[ -s "$tmp_entries" ]]; then
        cat "$tmp_entries" >> "$QUEUE"
        while IFS= read -r entry; do
            local cat=$(echo "$entry" | jq -r '.category')
            local imp=$(echo "$entry" | jq -r '.importance')
            log "  Captured: $cat (importance: $imp)"
        done < "$tmp_entries"
    fi
    
    rm -f "$tmp_entries"
    
    # Remove processed chunk
    rm -f "$chunk_file"
    log "Processed: $count entries"
}

# Main loop
main_loop() {
    log "MemoryJudge Franklin daemon started (PID: $$)"
    echo $$ > "$PID_FILE"
    
    local cycles=0
    
    while true; do
        # Check for chunks
        local found=0
        for chunk in "$INBOX"/chunk-*.json; do
            [[ -f "$chunk" ]] || continue
            process_chunk "$chunk"
            ((found++))
        done
        
        ((cycles++))
        
        # Log heartbeat every 60 cycles (5 min)
        if [[ $((cycles % 60)) -eq 0 ]]; then
            log "Heartbeat: $cycles cycles, $(ls "$INBOX"/chunk-*.json 2>/dev/null | wc -l) chunks waiting"
        fi
        
        # Sleep 5 seconds
        sleep 5
    done
}

# CLI
case "${1:-}" in
    --start)
        if [[ -f "$PID_FILE" ]] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
            log "Already running (PID: $(cat "$PID_FILE"))"
            exit 0
        fi
        nohup "$0" --daemon > /dev/null 2>&1 &
        sleep 1
        if [[ -f "$PID_FILE" ]]; then
            log "Started (PID: $(cat "$PID_FILE"))"
        fi
        ;;
    --stop)
        if [[ -f "$PID_FILE" ]]; then
            kill $(cat "$PID_FILE") 2>/dev/null && log "Stopped"
            rm -f "$PID_FILE"
        fi
        ;;
    --status)
        if [[ -f "$PID_FILE" ]] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
            echo "✅ MemoryJudge running (PID: $(cat "$PID_FILE"))"
            tail -3 "$LOG" 2>/dev/null
        else
            echo "❌ Not running"
        fi
        ;;
    --daemon)
        main_loop
        ;;
    --test)
        log "Testing chunk processing..."
        # Create test chunk
        test_chunk="$INBOX/test-chunk.json"
        echo '[{"role":"user","text":"I decided to implement the new system today","timestamp":'$(date +%s)'}]' > "$test_chunk"
        process_chunk "$test_chunk"
        echo "Test complete. Check queue: $QUEUE"
        ;;
    *)
        echo "Usage: $0 {--start|--stop|--status|--test}"
        exit 1
        ;;
esac
