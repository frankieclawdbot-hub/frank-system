#!/bin/bash
#
# memory-capture-franklin.sh - Franklin that captures important session outcomes
#
# PURPOSE:
#   Spawned by background-indexer to capture important conversation outcomes
#   Has access to OpenClaw tools (sessions_history, etc.)
#   Writes to stream.log, then exits
#
# USAGE:
#   memory-capture-franklin.sh              # Run once, capture recent outcomes
#   memory-capture-franklin.sh --test       # Dry run
#

set -euo pipefail

WORKSPACE="${WORKSPACE:-/root/clawd}"
STREAM_FILE="$WORKSPACE/memory/stream.log"
STATE_FILE="$WORKSPACE/.memory-capture-state"

# Ensure stream file exists
mkdir -p "$(dirname "$STREAM_FILE")"
if [[ ! -f "$STREAM_FILE" ]]; then
    echo "# Memory Stream - $(date +%Y-%m-%d)" > "$STREAM_FILE"
    echo "# Auto-captured important conversation outcomes" >> "$STREAM_FILE"
    echo "" >> "$STREAM_FILE"
fi

# Keywords for importance detection
DECISION_KEYWORDS="decided|decision|determined|choose|selected|committed|concluded|agreed"
DISCOVERY_KEYWORDS="discovered|found|realized|learned|insight|identified|pattern|understood"
IMPLEMENTATION_KEYWORDS="implemented|built|created|fixed|solved|deployed|integrated|completed"
ISSUE_KEYWORDS="issue|problem|bug|error|blocker|blocked|broken|failed|failure"
SUCCESS_KEYWORDS="success|succeeded|working|resolved|achieved|accomplished"
ALL_KEYWORDS="$DECISION_KEYWORDS|$DISCOVERY_KEYWORDS|$IMPLEMENTATION_KEYWORDS|$ISSUE_KEYWORDS|$SUCCESS_KEYWORDS"

log() {
    echo "[$(date '+%H:%M:%S')] $*" >&2
}

# Check if text is important
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

# Check if already captured
is_duplicate() {
    local hash="$1"
    grep -q "hash:$hash" "$STREAM_FILE" 2>/dev/null && return 0
    return 1
}

# Get last processed message ID (for incremental capture)
get_last_processed() {
    if [[ -f "$STATE_FILE" ]]; then
        cat "$STATE_FILE"
    else
        echo "0"
    fi
}

# Save last processed
save_state() {
    echo "$1" > "$STATE_FILE"
}

# Main capture logic
capture_outcomes() {
    log "MemoryCapture Franklin starting..."
    
    # Use the Franklin session to get history (this is the key - we have session access)
    # Since we're running as a Franklin, we can access the parent session
    # For now, we'll use a simple approach: check recent activity in stream.log itself
    
    # Alternative: Look at recent files or use available tools
    # The parent session's transcript is in /root/.openclaw/agents/main/sessions/
    
    local last_processed=$(get_last_processed)
    local captured=0
    
    # Try to get session content from available sources
    # Method 1: Check if there's recent activity we can detect
    # Method 2: Use environment/session context if available
    
    # For this implementation, we'll use a marker-based approach
    # The parent session can write markers that we detect
    
    # Check for recent important activity by looking at file timestamps
    # and any marker files
    
    local marker_file="$WORKSPACE/.memory-capture-marker"
    if [[ -f "$marker_file" ]]; then
        local marker_content=$(cat "$marker_file" 2>/dev/null || echo "")
        if [[ -n "$marker_content" ]]; then
            # Process the marked content
            while IFS= read -r line; do
                if [[ -n "$line" ]] && is_important "$line"; then
                    local category=$(get_category "$line")
                    local hash=$(get_hash "$line")
                    
                    if ! is_duplicate "$hash"; then
                        local timestamp=$(date '+%Y-%m-%d %H:%M:%S UTC')
                        {
                            echo ""
                            echo "---"
                            echo "[$timestamp] [$category]"
                            echo "$line"
                            echo "hash:$hash"
                        } >> "$STREAM_FILE"
                        ((captured++))
                        log "Captured: $category (hash:${hash:0:8})"
                    fi
                fi
            done <<< "$marker_content"
            
            # Clear marker after processing
            > "$marker_file"
        fi
    fi
    
    log "Capture complete: $captured entries"
    save_state "$(date +%s)"
}

# Test mode
test_mode() {
    echo "MemoryCapture Franklin - TEST MODE"
    echo ""
    echo "Would capture from session markers"
    echo "Keywords: $ALL_KEYWORDS"
    echo ""
    echo "Stream file: $STREAM_FILE"
    echo "State file: $STATE_FILE"
}

# Main
case "${1:-}" in
    --test)
        test_mode
        ;;
    *)
        capture_outcomes
        ;;
esac
