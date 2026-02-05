#!/bin/bash

################################################################################
# capture-memory-outcome.sh
#
# PURPOSE: Passive memory capture for important conversation outcomes
# Writes full-context entries to daily memory file (not one-liners)
# Triggers incremental vector indexing automatically
#
# USAGE:
#   capture-memory-outcome.sh \
#     --type TYPE \
#     --title TITLE \
#     --context CONTEXT_TEXT \
#     [--tags TAG1,TAG2] \
#     [--date DATE] \
#     [--importance critical|important|reference] \
#     [--source SOURCE]
#
# TYPES: decision, implementation, discovery, lesson, issue, resolution
#
# EXAMPLE:
#   capture-memory-outcome.sh \
#     --type "decision" \
#     --title "Use Kimi K2.5 as default model" \
#     --context "$(cat context.txt)" \
#     --tags "cost-optimization,model-selection" \
#     --importance "important"
#
# DESIGN PRINCIPLES:
# 1. Write FULL CONTEXT (not fragments)
# 2. Preserve semantic value end-to-end
# 3. Automatic vector indexing
# 4. Non-disruptive (backwards compatible)
#
################################################################################

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

WORKSPACE="${WORKSPACE:-/root/clawd}"
MEMORY_DIR="$WORKSPACE/memory"
LOG_FILE="/tmp/capture-memory-outcome.log"

# Defaults
TYPE=""
TITLE=""
CONTEXT=""
TAGS=""
DATE="${1:-$(date -u '+%Y-%m-%d')}"
IMPORTANCE="reference"
SOURCE="capture-memory-outcome"

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "$LOG_FILE" >&2
}

log_debug() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $*" | tee -a "$LOG_FILE"
    fi
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type)
                TYPE="$2"
                shift 2
                ;;
            --title)
                TITLE="$2"
                shift 2
                ;;
            --context)
                CONTEXT="$2"
                shift 2
                ;;
            --tags)
                TAGS="$2"
                shift 2
                ;;
            --date)
                DATE="$2"
                shift 2
                ;;
            --importance)
                IMPORTANCE="$2"
                shift 2
                ;;
            --source)
                SOURCE="$2"
                shift 2
                ;;
            --debug)
                DEBUG=1
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done
}

print_usage() {
    cat << 'EOF'
Usage: capture-memory-outcome.sh [OPTIONS]

OPTIONS:
  --type TYPE                Type of outcome (decision|implementation|discovery|lesson|issue|resolution)
  --title TITLE              Short title/headline
  --context CONTEXT          Full context (can be multiline)
  --tags TAG1,TAG2,...       Comma-separated tags
  --date DATE                Date (YYYY-MM-DD, default: today)
  --importance LEVEL         Level (critical|important|reference, default: reference)
  --source SOURCE            Source identifier (default: capture-memory-outcome)
  --debug                    Enable debug output

EXAMPLES:
  # Decision with full context
  capture-memory-outcome.sh \
    --type decision \
    --title "Chose Kimi K2.5 as default model" \
    --importance important \
    --context "Analysis of cost vs quality showed..."

  # Implementation
  capture-memory-outcome.sh \
    --type implementation \
    --title "Set up SOCKS5 proxy authentication" \
    --context "$(cat proxy-setup-notes.txt)"

  # Issue with resolution
  capture-memory-outcome.sh \
    --type issue \
    --title "TLS handshake failing through proxy" \
    --context "... problem description ... solution ..."
EOF
}

# Validate required fields
validate_input() {
    if [[ -z "$TYPE" ]]; then
        log_error "Missing required: --type"
        return 1
    fi
    if [[ -z "$TITLE" ]]; then
        log_error "Missing required: --title"
        return 1
    fi
    if [[ -z "$CONTEXT" ]]; then
        log_error "Missing required: --context"
        return 1
    fi

    # Validate type
    case "$TYPE" in
        decision|implementation|discovery|lesson|issue|resolution)
            ;;
        *)
            log_error "Invalid type: $TYPE (must be decision|implementation|discovery|lesson|issue|resolution)"
            return 1
            ;;
    esac

    # Validate importance
    case "$IMPORTANCE" in
        critical|important|reference)
            ;;
        *)
            log_error "Invalid importance: $IMPORTANCE (must be critical|important|reference)"
            return 1
            ;;
    esac

    return 0
}

# Validate date format
validate_date() {
    if [[ ! $DATE =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        log_error "Invalid date format: $DATE (expected YYYY-MM-DD)"
        return 1
    fi
    return 0
}

# Generate unique entry ID
generate_entry_id() {
    local text="$TITLE|$TYPE|$DATE|$(date '+%s')"
    echo "$text" | md5sum | cut -d' ' -f1 | cut -c1-12
}

# Format tags for markdown
format_tags() {
    local tags="$1"
    if [[ -z "$tags" ]]; then
        echo ""
    else
        # Convert comma-separated to markdown hashtags
        echo "$tags" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed 's/^/#/' | tr '\n' ' '
    fi
}

# ============================================================================
# CORE CAPTURE LOGIC
# ============================================================================

# Create or append to daily memory file
capture_to_daily_file() {
    local daily_file="$MEMORY_DIR/$DATE.md"
    local entry_id=$(generate_entry_id)
    local timestamp=$(date -u '+%H:%M UTC')
    local formatted_tags=$(format_tags "$TAGS")

    log_debug "Writing to: $daily_file"
    log_debug "Entry ID: $entry_id"

    # Ensure memory directory exists
    mkdir -p "$MEMORY_DIR"

    # Create daily file header if doesn't exist
    if [[ ! -f "$daily_file" ]]; then
        cat > "$daily_file" << EOF
# $DATE - Daily Notes

## Captured Outcomes

EOF
        log_debug "Created daily file: $daily_file"
    fi

    # Build entry with type emoji
    local type_emoji=""
    case "$TYPE" in
        decision) type_emoji="🔷" ;;
        implementation) type_emoji="⚙️" ;;
        discovery) type_emoji="🔍" ;;
        lesson) type_emoji="💡" ;;
        issue) type_emoji="⚠️" ;;
        resolution) type_emoji="✅" ;;
        *) type_emoji="📝" ;;
    esac

    # Build importance indicator
    local importance_marker=""
    case "$IMPORTANCE" in
        critical) importance_marker="[CRITICAL]" ;;
        important) importance_marker="[IMPORTANT]" ;;
        *) importance_marker="" ;;
    esac

    # Format entry (preserve full context)
    local entry=$(cat << EOF

## [$timestamp] $type_emoji $importance_marker $TYPE: $TITLE

**Date:** $DATE  
**Time:** $timestamp  
**Type:** $TYPE  
**Importance:** $IMPORTANCE  
**ID:** $entry_id  
**Source:** $SOURCE  
**Tags:** $formatted_tags

### Captured Content

$CONTEXT

---

EOF
)

    # Append to daily file
    echo "$entry" >> "$daily_file"

    log_info "✓ Captured outcome: $TITLE (ID: $entry_id)"
    log_debug "File: $daily_file"

    # Return entry ID for tracking
    echo "$entry_id"
}

# ============================================================================
# VECTOR INDEXING
# ============================================================================

trigger_incremental_indexing() {
    log_info "Triggering incremental vector indexing..."

    if [[ ! -x "$WORKSPACE/trigger-incremental-indexing.sh" ]]; then
        log_debug "Incremental indexing script not found, skipping"
        return 0
    fi

    # Trigger indexing in background (non-blocking)
    if "$WORKSPACE/trigger-incremental-indexing.sh" 2>&1 | tee -a "$LOG_FILE" &
    then
        log_info "✓ Vector indexing triggered (background)"
    else
        log_error "Failed to trigger indexing (non-fatal)"
    fi
}

# ============================================================================
# LOGGING & TRACKING
# ============================================================================

log_capture_event() {
    local entry_id="$1"
    local log_json=$(cat << EOF
{
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "entry_id": "$entry_id",
  "type": "$TYPE",
  "title": "$TITLE",
  "importance": "$IMPORTANCE",
  "date": "$DATE",
  "tags": "$TAGS",
  "source": "$SOURCE"
}
EOF
)

    # Append to capture log
    local capture_log="$WORKSPACE/logs/memory-captures.jsonl"
    mkdir -p "$(dirname "$capture_log")"
    echo "$log_json" >> "$capture_log"

    log_debug "Logged to: $capture_log"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    log_info "Starting memory outcome capture"

    # Parse arguments
    parse_args "$@"

    # Validate
    if ! validate_input; then
        print_usage
        exit 1
    fi

    if ! validate_date; then
        exit 1
    fi

    log_debug "Type: $TYPE"
    log_debug "Title: $TITLE"
    log_debug "Date: $DATE"
    log_debug "Importance: $IMPORTANCE"
    log_debug "Tags: $TAGS"

    # Capture to daily file
    local entry_id
    entry_id=$(capture_to_daily_file)

    # Log the capture event
    log_capture_event "$entry_id"

    # Trigger vector indexing
    trigger_incremental_indexing

    log_info "✓ Memory outcome captured successfully"
    log_info "Entry ID: $entry_id"
    log_info "Daily file: $MEMORY_DIR/$DATE.md"

    exit 0
}

# Handle help
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    print_usage
    exit 0
fi

# Run
main "$@"
