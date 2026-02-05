#!/bin/bash
#
# memory-judge-indexer.sh - Long-Running MemoryJudge for Background Indexer
#
# MemoryJudge Pattern: Spawn ONCE at startup, process chunks continuously
# Waits for chunks in /tmp/indexer-inbox/, judges importance, writes to queue
#

set -uo pipefail

INBOX="/tmp/indexer-inbox"
QUEUE="/root/clawd/memory/importance-queue.jsonl"
LOG="/tmp/memory-judge-indexer.log"
PID_FILE="/tmp/memory-judge-indexer.pid"

# Judgment thresholds
MIN_LENGTH=50
IMPORTANCE_THRESHOLD=5

# Categories
DECISION_KEYWORDS="decided|decision|determined|concluded|agreed|committed"
DISCOVERY_KEYWORDS="discovered|found|realized|learned|insight|understood"
IMPLEMENTATION_KEYWORDS="implemented|built|created|fixed|solved|deployed"
ISSUE_KEYWORDS="issue|problem|bug|error|blocker|failed|broken"
SUCCESS_KEYWORDS="success|achieved|accomplished|resolved|completed"
FEELING_KEYWORDS="excited|feel|feeling|passionate|wonder|meaningful"
PHILOSOPHY_KEYWORDS="philosophy|journey|growth|becoming|purpose|meaning"
SENTIMENT_KEYWORDS="amazing|wonderful|incredible|brilliant|love|thank|appreciate|proud|impressed|grateful"
ACKNOWLEDGMENT_KEYWORDS="exactly|yes|agree|right|perfect|great|excellent|well done|good job|nicely done"

mkdir -p "$INBOX"
touch "$QUEUE"

log() {
    echo "[$(date '+%H:%M:%S')] $*" >> "$LOG"
    echo "[MemoryJudge-Indexer] $*" >&2
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

# Process a single message
process_message() {
    local msg="$1"
    local text=$(echo "$msg" | jq -r '.text // empty')
    [[ -z "$text" ]] && return
    
    local len=${#text}
    local lower=$(echo "$text" | tr '[:upper:]' '[:lower:]')
    local category=""
    local importance=$IMPORTANCE_THRESHOLD
    
    # Handle short messages (<50 chars) - check for sentiment/acknowledgment
    if [[ $len -lt $MIN_LENGTH ]]; then
        if echo "$lower" | grep -Eq "($SENTIMENT_KEYWORDS)"; then
            category="sentiment"
            importance=6
        elif echo "$lower" | grep -Eq "($ACKNOWLEDGMENT_KEYWORDS)"; then
            category="acknowledgment"
            importance=5
        else
            return  # Skip short messages without sentiment
        fi
    else
        # Long messages: full category detection
        category=$(detect_category "$text")
        importance=$(calculate_importance "$text" "$category")
    fi
    
    # Only write if importance >= threshold
    if [[ $importance -ge $IMPORTANCE_THRESHOLD ]]; then
        local hash=$(echo "$text" | md5sum | head -c 16)
        local ts=$(date -Iseconds)
        
        echo "{\"timestamp\":\"$ts\",\"category\":\"$category\",\"importance\":$importance,\"text\":$(echo "$text" | jq -Rs .),\"hash\":\"$hash\",\"source\":\"memory-judge-indexer\"}" >> "$QUEUE"
        echo "captured:$category:$importance"
    fi
}

# Process a chunk file
process_chunk() {
    local chunk_file="$1"
    local count=0
    local captured=0
    
    log "Processing: $(basename "$chunk_file")"
    
    # Process each message in chunk
    while IFS= read -r msg; do
        [[ -z "$msg" ]] && continue
        
        local result=$(process_message "$msg")
        ((count++))
        
        if [[ "$result" == captured* ]]; then
            ((captured++))
            local cat=$(echo "$result" | cut -d: -f2)
            local imp=$(echo "$result" | cut -d: -f3)
            log "  Captured: $cat (importance: $imp)"
        fi
    done < <(jq -c '.[]' "$chunk_file" 2>/dev/null)
    
    # Remove processed chunk
    rm -f "$chunk_file"
    log "Processed $count messages, captured $captured"
    
    return $captured
}

# Main daemon loop
daemon_loop() {
    log "MemoryJudge Indexer starting (PID: $$)"
    log "Inbox: $INBOX"
    log "Queue: $QUEUE"
    log "Threshold: importance >= $IMPORTANCE_THRESHOLD"
    echo $$ > "$PID_FILE"
    
    local cycles=0
    local total_captured=0
    
    while [[ "${shutdown_requested:-false}" == "false" ]]; do
        local found=0
        
        # Check for chunks
        for chunk in "$INBOX"/chunk-*.json; do
            [[ -f "$chunk" ]] || continue
            
            local captured
            process_chunk "$chunk"
            captured=$?
            total_captured=$((total_captured + captured))
            ((found++))
        done
        
        ((cycles++))
        
        # Log heartbeat every 60 cycles (5 min)
        if [[ $((cycles % 60)) -eq 0 ]]; then
            log "Heartbeat: $cycles cycles, $total_captured entries captured"
        fi
        
        # Sleep 5 seconds
        sleep 5
    done
    
    log "Shutdown requested, stopping"
    rm -f "$PID_FILE"
}

# Signal handling
shutdown_requested=false
trap 'shutdown_requested=true; log "SIGTERM received"' TERM
trap 'shutdown_requested=true; log "SIGINT received"' INT

# CLI
case "${1:-}" in
    --daemon)
        daemon_loop
        ;;
    --start)
        if [[ -f "$PID_FILE" ]] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
            log "Already running (PID: $(cat "$PID_FILE"))"
            exit 0
        fi
        nohup "$0" --daemon > /dev/null 2>&1 &
        sleep 1
        if [[ -f "$PID_FILE" ]]; then
            log "Started (PID: $(cat "$PID_FILE"))"
        else
            log "Failed to start"
            exit 1
        fi
        ;;
    --stop)
        if [[ -f "$PID_FILE" ]]; then
            kill $(cat "$PID_FILE") 2>/dev/null
            rm -f "$PID_FILE"
            log "Stopped"
        else
            log "Not running"
        fi
        ;;
    --status)
        if [[ -f "$PID_FILE" ]] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
            echo "RUNNING (PID: $(cat "$PID_FILE"))"
            echo "Queue entries: $(wc -l < "$QUEUE" 2>/dev/null || echo 0)"
        else
            echo "STOPPED"
            exit 1
        fi
        ;;
    *)
        echo "Usage: $0 {--start|--stop|--status|--daemon}"
        echo ""
        echo "Long-running MemoryJudge for background indexing"
        echo "Watches $INBOX for chunks, judges importance, writes to queue"
        exit 1
        ;;
esac
