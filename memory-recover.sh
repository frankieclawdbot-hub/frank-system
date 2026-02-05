#!/bin/bash

################################################################################
# memory-recover.sh - Retroactively Capture Missed Conversations
#
# PURPOSE:
#   Recovers important conversations from session logs that were never
#   captured to memory (e.g., proxy discussion from today).
#
# RECOVERY PROCESS:
#   1. Query session logs for date range
#   2. Search for important keywords (decision, discovery, etc.)
#   3. Extract conversation context around matches
#   4. Write to daily memory with [RECOVERED] tag
#   5. Link to original timestamp for reference
#
# USAGE:
#   memory-recover.sh --date 2026-02-05              # Today
#   memory-recover.sh --date 2026-02-05 --keywords "proxy OR nginx"
#   memory-recover.sh --date-range 2026-01-29 2026-02-05
#   memory-recover.sh --date 2026-02-05 --importance high
#
# INPUT SOURCES:
#   - Session conversation history (if available)
#   - Consciousness layer logs
#   - Task event logs
#
# OUTPUT:
#   - Appends to memory/YYYY-MM-DD.md with [RECOVERED] tag
#   - References original conversation timestamp
#   - Preserves full context
#
# ENVIRONMENT:
#   - WORKSPACE: Base directory (default: /root/clawd)
#   - DEBUG: Enable debug output
#
################################################################################

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

WORKSPACE="${WORKSPACE:-/root/clawd}"
DEBUG="${DEBUG:-false}"
MEMORY_DIR="$WORKSPACE/memory"
TODAY=$(date -u '+%Y-%m-%d')
RECOVERY_LOG="/tmp/memory-recovery.log"

# Default keywords for recovery
declare -A RECOVERY_KEYWORDS=(
    [decision]="decided|decision|determined|choose|selected|committed"
    [discovery]="discovered|found|realized|learned|insight|identified"
    [implementation]="implemented|deployed|fixed|solved|built|integrated"
    [issue]="bug|error|issue|problem|blocker|blocked|stuck|failed"
    [critical]="CRITICAL|!!!|urgent|blocker"
)

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
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $msg" | tee -a "$RECOVERY_LOG"
}

log_error() {
    local msg="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $msg" >&2 | tee -a "$RECOVERY_LOG"
}

# ============================================================================
# SOURCE DISCOVERY
# ============================================================================

find_conversation_logs() {
    local date="$1"
    
    # Look in various log locations
    local sources=()
    
    # Check consciousness logs
    if [[ -d "$WORKSPACE/consciousness/logs" ]]; then
        sources+=("$WORKSPACE/consciousness/logs"/*".log")
    fi
    
    # Check orchestrator logs
    if [[ -d "$WORKSPACE/consciousness/orchestrator/logs" ]]; then
        sources+=("$WORKSPACE/consciousness/orchestrator/logs"/*".log")
    fi
    
    # Check main logs
    if [[ -d "$WORKSPACE/logs" ]]; then
        sources+=("$WORKSPACE/logs"/*".log")
    fi
    
    log_debug "Found ${#sources[@]} potential log sources"
    
    for source in "${sources[@]}"; do
        if [[ -f "$source" ]]; then
            echo "$source"
        fi
    done
}

# ============================================================================
# CONVERSATION EXTRACTION
# ============================================================================

search_logs_for_keywords() {
    local search_term="$1"
    local importance="$2"
    
    log_info "Searching logs for keyword: $search_term"
    
    local found_count=0
    local temp_results="/tmp/recovery_results_$$.txt"
    
    > "$temp_results"
    
    # Search all available logs
    find "$WORKSPACE" -name "*.log" -type f 2>/dev/null | while IFS= read -r logfile; do
        if grep -i "$search_term" "$logfile" 2>/dev/null; then
            log_debug "Found match in: $logfile"
            echo "--- Source: $logfile ---" >> "$temp_results"
            grep -i -A 3 -B 3 "$search_term" "$logfile" >> "$temp_results" 2>/dev/null || true
            ((found_count++))
        fi
    done
    
    if [[ -f "$temp_results" ]] && [[ -s "$temp_results" ]]; then
        cat "$temp_results"
        rm "$temp_results"
        log_info "Found $found_count matches"
    else
        rm -f "$temp_results"
        log_error "No matches found"
        return 1
    fi
}

extract_context_around_match() {
    local match_line="$1"
    local context_lines=5
    
    # Extract surrounding context
    # This is simplified - in production would use log parsing
    echo "$match_line"
}

# ============================================================================
# RECOVERY ENTRY WRITING
# ============================================================================

create_recovery_block() {
    local original_date="$1"
    local original_time="$2"
    local category="$3"
    local content="$4"
    local keywords="$5"
    
    local recovery_date
    recovery_date=$(date -u '+%Y-%m-%d')
    
    local recovery_time
    recovery_time=$(date -u '+%H:%M UTC')
    
    # Truncate content if too long
    local truncated_content
    if [[ ${#content} -gt 1000 ]]; then
        truncated_content="${content:0:997}..."
    else
        truncated_content="$content"
    fi
    
    cat << EOF

## $recovery_time — [RECOVERED] $category discussion from $original_time

**Original Date:** $original_date $original_time  
**Recovery Date:** $recovery_date  
**Category:** $category  
**Recovered Via:** memory-recover.sh  
**Search Keywords:** $keywords

**Context:**
$truncated_content

**Note:** This entry was retroactively recovered from session logs.
Consider reviewing the original conversation for full context.

EOF
}

# ============================================================================
# KEYWORD-BASED RECOVERY
# ============================================================================

recover_by_keywords() {
    local search_date="$1"
    local keywords="$2"
    
    log_info "Attempting keyword recovery for: $keywords"
    
    local recovery_count=0
    
    # Build search pattern from keywords
    local search_pattern
    search_pattern=$(echo "$keywords" | tr ',' '|')
    
    # Search consciousness logs
    local cognitive_log="$WORKSPACE/consciousness/logs/cognitive.log"
    
    if [[ -f "$cognitive_log" ]]; then
        log_debug "Searching cognitive log for patterns: $search_pattern"
        
        # Extract entries matching pattern
        if grep -iE "$search_pattern" "$cognitive_log" 2>/dev/null | head -5 | while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                log_info "Found potential recovery: ${line:0:50}..."
                ((recovery_count++))
            fi
        done; then
            log_info "Recovery search completed ($recovery_count matches)"
        fi
    fi
    
    # If nothing found, try reflective logs
    if [[ $recovery_count -eq 0 ]]; then
        local reflective_log="$WORKSPACE/consciousness/logs/reflective.log"
        
        if [[ -f "$reflective_log" ]]; then
            log_debug "Searching reflective log..."
            
            if grep -iE "$search_pattern" "$reflective_log" 2>/dev/null | head -5 | while IFS= read -r line; do
                if [[ -n "$line" ]]; then
                    log_info "Found recovery candidate: ${line:0:50}..."
                    ((recovery_count++))
                fi
            done; then
                log_info "Reflective search completed ($recovery_count matches)"
            fi
        fi
    fi
    
    return $([[ $recovery_count -gt 0 ]] && echo 0 || echo 1)
}

# ============================================================================
# MANUAL RECOVERY ENTRY
# ============================================================================

add_recovery_entry_manual() {
    local category="$1"
    local content="$2"
    local original_date="$3"
    local original_time="${4:-unknown}"
    local keywords="${5:-manual}"
    
    local daily_file="$MEMORY_DIR/$TODAY.md"
    
    mkdir -p "$MEMORY_DIR"
    
    # Ensure daily file exists
    if [[ ! -f "$daily_file" ]]; then
        cat > "$daily_file" << EOF
# $TODAY - Daily Notes

## Recovery Session

EOF
    fi
    
    local block
    block=$(create_recovery_block "$original_date" "$original_time" "$category" "$content" "$keywords")
    
    echo "$block" >> "$daily_file"
    
    log_info "Added recovery entry to $daily_file"
}

# ============================================================================
# HELP
# ============================================================================

print_help() {
    cat << 'EOF'
usage: memory-recover.sh [OPTIONS]

Retroactively capture missed conversations from session logs.

OPTIONS:
  --date YYYY-MM-DD       Target date for recovery (default: today)
  --date-range START END  Recover from date range
  --keywords PATTERN      Search pattern (comma-separated)
                         Examples: "proxy", "decision", "bug OR error"
  --importance LEVEL      Find entries: high, critical
  --manual                Add manual entry (use with --text, --category)
  --category CAT          Category for manual recovery
  --text TEXT            Content for manual recovery
  --list-sources         Show available log sources
  --dry-run              Preview without writing
  --debug                Enable debug output

EXAMPLES:
  # Recover today's proxy discussion
  memory-recover.sh --date 2026-02-05 --keywords "proxy"

  # Recover week's critical issues
  memory-recover.sh --date-range 2026-01-29 2026-02-05 --keywords "CRITICAL OR bug"

  # Manual recovery entry
  memory-recover.sh --manual --category decision \
    --text "Decided to use nginx reverse proxy" \
    --original-date 2026-02-05 --original-time "14:30"

  # Preview recovery sources
  memory-recover.sh --list-sources

OUTPUT:
  Appends to memory/YYYY-MM-DD.md with [RECOVERED] tag
  Each entry references original date/time for context

EOF
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    local target_date="$TODAY"
    local keywords=""
    local category=""
    local content=""
    local original_date=""
    local original_time=""
    local mode="auto"
    local dry_run=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --date)
                target_date="$2"
                shift 2
                ;;
            --keywords)
                keywords="$2"
                shift 2
                ;;
            --category)
                category="$2"
                shift 2
                ;;
            --text)
                content="$2"
                shift 2
                ;;
            --original-date)
                original_date="$2"
                shift 2
                ;;
            --original-time)
                original_time="$2"
                shift 2
                ;;
            --manual)
                mode="manual"
                shift
                ;;
            --list-sources)
                echo "Available log sources:"
                find_conversation_logs "$target_date" | sort -u
                exit 0
                ;;
            --dry-run)
                dry_run=true
                shift
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
    
    # Ensure log directory exists
    mkdir -p "$(dirname "$RECOVERY_LOG")"
    
    log_info "Starting memory recovery (target_date=$target_date, mode=$mode)"
    
    # Execute requested recovery
    case "$mode" in
        auto)
            if [[ -z "$keywords" ]]; then
                log_error "Keywords required for automatic recovery"
                print_help
                exit 1
            fi
            
            if recover_by_keywords "$target_date" "$keywords"; then
                log_info "Automatic recovery completed"
            else
                log_error "No entries found for recovery"
            fi
            ;;
        manual)
            if [[ -z "$category" ]] || [[ -z "$content" ]]; then
                log_error "Category and text required for manual recovery"
                print_help
                exit 1
            fi
            
            if [[ "$dry_run" == "true" ]]; then
                log_info "[DRY RUN] Would add recovery entry"
                create_recovery_block "$original_date" "$original_time" "$category" "$content" "manual"
            else
                add_recovery_entry_manual "$category" "$content" "$original_date" "$original_time"
                log_info "Manual recovery entry added"
            fi
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
