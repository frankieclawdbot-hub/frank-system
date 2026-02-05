#!/bin/bash

################################################################################
# memory-writer.sh - Write Important Outcomes to Daily Memory
#
# PURPOSE:
#   Takes detected outcomes (from outcome-detector.sh or manual input) and
#   appends them to the daily memory file with full context preservation.
#
# INPUT:
#   - JSON from outcome-detector.sh via stdin, OR
#   - Manual parameters (text, category, importance)
#
# OUTPUT:
#   - Appends to memory/YYYY-MM-DD.md with structured format
#   - Maintains full context, not one-liners
#   - Metadata included (category, importance, timestamp)
#
# USAGE:
#   # From outcome detector (piped JSON)
#   echo "..." | outcome-detector.sh | memory-writer.sh --json
#
#   # Manual entry
#   memory-writer.sh --text "Decision made" --category decision --importance important
#
#   # Batch from file
#   memory-writer.sh --file outcomes.jsonl
#
# ENVIRONMENT:
#   - WORKSPACE: Base directory (default: /root/clawd)
#   - DEBUG: Enable debug output (true/false)
#
################################################################################

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

WORKSPACE="${WORKSPACE:-/root/clawd}"
DEBUG="${DEBUG:-false}"
MEMORY_DIR="$WORKSPACE/memory"
DATE=$(date -u '+%Y-%m-%d')
TIMESTAMP=$(date -u '+%H:%M UTC')
DAILY_FILE="$MEMORY_DIR/$DATE.md"

# ============================================================================
# LOGGING
# ============================================================================

log_debug() {
    local msg="$1"
    if [[ "$DEBUG" == "true" ]]; then
        echo "[DEBUG] $msg" >&2
    fi
}

log_info() {
    local msg="$1"
    echo "✓ $msg" >&2
}

log_error() {
    local msg="$1"
    echo "✗ $msg" >&2
}

# ============================================================================
# FILE INITIALIZATION
# ============================================================================

ensure_daily_file() {
    mkdir -p "$MEMORY_DIR"
    
    if [[ ! -f "$DAILY_FILE" ]]; then
        cat > "$DAILY_FILE" << EOF
# $DATE - Daily Notes

EOF
        log_debug "Created daily file: $DAILY_FILE"
    fi
}

# ============================================================================
# OUTCOME FORMATTING
# ============================================================================

format_outcome_block() {
    local text="$1"
    local category="$2"
    local importance="$3"
    
    # Extract title from first sentence
    local title
    title=$(echo "$text" | sed -E 's/^([^.!?]*[.!?]).*/\1/' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # Truncate title if too long
    if [[ ${#title} -gt 100 ]]; then
        title="${title:0:97}..."
    fi
    
    # Map category to emoji
    local icon=""
    case "$category" in
        critical) icon="🔴" ;;
        decision) icon="🔹" ;;
        discovery) icon="💡" ;;
        implementation) icon="✅" ;;
        issue) icon="⚠️" ;;
        lesson) icon="📚" ;;
        architecture) icon="🏗️" ;;
        *) icon="📝" ;;
    esac
    
    # Format block
    cat << EOF

## $TIMESTAMP — $icon $title

**Category:** $category  
**Importance:** $importance

**Details:**
$text

EOF
}

# ============================================================================
# INPUT PROCESSING
# ============================================================================

write_from_json() {
    local json="$1"
    
    # Validate JSON before processing
    if ! echo "$json" | jq . > /dev/null 2>&1; then
        log_debug "Skipping invalid JSON: ${json:0:50}..."
        return 0
    fi
    
    # Extract fields from JSON
    local text
    local category
    local importance
    
    text=$(echo "$json" | jq -r '.text // empty' 2>/dev/null || echo "")
    category=$(echo "$json" | jq -r '.category // "reference"' 2>/dev/null || echo "reference")
    importance=$(echo "$json" | jq -r '.importance // "reference"' 2>/dev/null || echo "reference")
    
    if [[ -z "$text" ]]; then
        log_error "Invalid JSON: missing 'text' field"
        return 1
    fi
    
    write_outcome "$text" "$category" "$importance"
}

write_outcome() {
    local text="$1"
    local category="${2:-reference}"
    local importance="${3:-reference}"
    
    log_debug "Writing outcome: category=$category, importance=$importance"
    log_debug "Text: ${text:0:50}..."
    
    local block
    block=$(format_outcome_block "$text" "$category" "$importance")
    
    # Append to daily file
    echo "$block" >> "$DAILY_FILE"
    
    log_info "Written to $DAILY_FILE"
    
    # Return outcome in JSON for chaining
    cat << EOF
{
  "written": true,
  "file": "$DAILY_FILE",
  "category": "$category",
  "timestamp": "$TIMESTAMP"
}
EOF
}

write_from_stdin_json() {
    local json
    json=$(cat)
    
    if [[ -z "$json" ]]; then
        log_error "No JSON input provided"
        return 1
    fi
    
    log_debug "Processing JSON from stdin"
    
    # Try to extract as single-line JSON first
    if echo "$json" | jq . > /dev/null 2>&1; then
        write_from_json "$json"
    else
        # Multi-line JSON - collapse to single line
        local collapsed
        collapsed=$(echo "$json" | tr '\n' ' ' | sed 's/  */ /g')
        
        if echo "$collapsed" | jq . > /dev/null 2>&1; then
            write_from_json "$collapsed"
        else
            log_error "Invalid JSON input"
            return 1
        fi
    fi
}

write_from_file() {
    local filepath="$1"
    
    if [[ ! -f "$filepath" ]]; then
        log_error "File not found: $filepath"
        return 1
    fi
    
    log_info "Processing outcomes from $filepath"
    
    local outcome_count=0
    
    while IFS= read -r json; do
        [[ -z "$json" ]] && continue
        [[ "$json" =~ ^---.*---$ ]] && continue
        
        if write_from_json "$json" > /dev/null 2>&1; then
            ((outcome_count++))
        fi
    done < "$filepath"
    
    log_info "Wrote $outcome_count outcomes from $filepath"
}

# ============================================================================
# BATCH PROCESSING
# ============================================================================

process_stdin_stream() {
    # Read outcome-detector output stream (one JSON per line, separated by ---)
    local accumulated=""
    
    while IFS= read -r line; do
        if [[ "$line" == "---OUTCOME_SEPARATOR---" ]]; then
            # Process accumulated outcome
            if [[ -n "$accumulated" ]]; then
                write_from_json "$accumulated"
            fi
            accumulated=""
        else
            accumulated="$line"
        fi
    done
    
    # Process last outcome
    if [[ -n "$accumulated" ]]; then
        write_from_json "$accumulated"
    fi
}

# ============================================================================
# HELP
# ============================================================================

print_help() {
    cat << 'EOF'
usage: memory-writer.sh [OPTIONS]

Write detected conversation outcomes to daily memory file with full context.

INPUT MODES:
  --json              Read JSON from stdin (single outcome)
  --stream            Read outcome-detector stream from stdin
  --file PATH         Read JSONL outcomes from file
  --text TEXT         Manual entry (use with --category, --importance)

OPTIONS:
  --category CAT      Category: decision, discovery, implementation, issue, lesson, architecture
  --importance IMP    Importance: critical, important, reference (default: reference)
  --date YYYY-MM-DD   Use specific date (default: today)

EXAMPLES:
  # From outcome detector
  echo "..." | outcome-detector.sh | memory-writer.sh --stream

  # Single JSON outcome
  echo '{"text":"...", "category":"decision", "importance":"important"}' | memory-writer.sh --json

  # Manual entry
  memory-writer.sh --text "Decision made" --category decision --importance important

  # From file
  memory-writer.sh --file outcomes.jsonl

OUTPUT:
  Appends to memory/YYYY-MM-DD.md
  Returns JSON confirmation with file path and timestamp

EOF
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    local mode="stream"
    local text=""
    local category="reference"
    local importance="reference"
    local input_file=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                mode="json"
                shift
                ;;
            --stream)
                mode="stream"
                shift
                ;;
            --file)
                mode="file"
                input_file="$2"
                shift 2
                ;;
            --text)
                mode="manual"
                text="$2"
                shift 2
                ;;
            --category)
                category="$2"
                shift 2
                ;;
            --importance)
                importance="$2"
                shift 2
                ;;
            --date)
                DATE="$2"
                DAILY_FILE="$MEMORY_DIR/$DATE.md"
                shift 2
                ;;
            --debug)
                DEBUG=true
                shift
                ;;
            --help)
                print_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                print_help
                exit 1
                ;;
        esac
    done
    
    # Initialize daily file
    ensure_daily_file
    
    # Execute requested mode
    case "$mode" in
        json)
            write_from_stdin_json
            ;;
        stream)
            process_stdin_stream
            ;;
        file)
            write_from_file "$input_file"
            ;;
        manual)
            if [[ -z "$text" ]]; then
                log_error "Text required for manual mode (--text)"
                exit 1
            fi
            write_outcome "$text" "$category" "$importance"
            ;;
        *)
            log_error "Unknown mode: $mode"
            exit 1
            ;;
    esac
}

# ============================================================================
# ENTRY POINT
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
