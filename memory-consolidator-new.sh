#!/bin/bash

################################################################################
# memory-consolidator.sh - Consolidate Daily Notes into Long-Term Memory
#
# PURPOSE:
#   Parses daily memory files (memory/YYYY-MM-DD.md) and consolidates
#   important entries into MEMORY.md with full context preserved.
#
# PROCESS:
#   1. Read memory/YYYY-MM-DD.md files (specified or recent)
#   2. Extract entries with importance metadata
#   3. Create rich memory blocks in MEMORY.md (NOT one-liners)
#   4. Trigger background indexer to vectorize
#   5. Log results
#
# USAGE:
#   memory-consolidator.sh --today              # Consolidate today's notes
#   memory-consolidator.sh --date 2026-02-04    # Consolidate specific date
#   memory-consolidator.sh --date-range ...     # Consolidate date range
#   memory-consolidator.sh --dry-run             # Preview without writing
#
# OUTPUT:
#   - Updates MEMORY.md with rich entries
#   - Calls background-indexer.sh --once
#   - Logs results to consolidation log
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
MEMORY_FILE="$WORKSPACE/MEMORY.md"
LOG_FILE="${CONSOLIDATE_LOG:-/tmp/memory-consolidation.log}"
DRY_RUN=false

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
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $msg" | tee -a "$LOG_FILE"
}

log_error() {
    local msg="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $msg" >&2 | tee -a "$LOG_FILE"
}

# ============================================================================
# ENTRY EXTRACTION
# ============================================================================

extract_entries_from_daily_file() {
    local date="$1"
    local filepath="$MEMORY_DIR/$date.md"
    
    if [[ ! -f "$filepath" ]]; then
        log_debug "No daily file found: $filepath"
        return 0
    fi
    
    log_info "Extracting entries from: $filepath"
    
    local in_outcome_block=false
    local current_block=""
    local line_num=0
    local entry_count=0
    
    while IFS= read -r line; do
        ((line_num++))
        
        # Detect outcome blocks (start with ## HH:MM UTC)
        if [[ "$line" =~ ^##\ [0-9]{2}:[0-9]{2}\ UTC ]]; then
            # Process previous block if exists
            if [[ -n "$current_block" ]]; then
                process_outcome_block "$current_block"
                ((entry_count++))
            fi
            
            # Start new block
            in_outcome_block=true
            current_block="$line"
        elif [[ "$in_outcome_block" == "true" ]]; then
            # Continue accumulating block until next ## or empty section
            if [[ "$line" =~ ^##\ [0-9]{2}:[0-9]{2}\ UTC ]] || [[ "$line" =~ ^#[^#] ]]; then
                # New section, process accumulated block
                if [[ -n "$current_block" ]]; then
                    process_outcome_block "$current_block"
                    ((entry_count++))
                fi
                current_block="$line"
            else
                # Add to current block
                current_block="$current_block"$'\n'"$line"
            fi
        fi
    done < "$filepath"
    
    # Process last block
    if [[ -n "$current_block" ]]; then
        process_outcome_block "$current_block"
        ((entry_count++))
    fi
    
    log_info "Extracted $entry_count entries from $date"
}

process_outcome_block() {
    local block="$1"
    
    # Skip if block is too small
    if [[ ${#block} -lt 50 ]]; then
        log_debug "Block too small, skipping: ${block:0:30}..."
        return
    fi
    
    # Extract title (first line after ##)
    local title
    title=$(echo "$block" | head -n 1 | sed 's/^##[^-]*— //;s/^##[^A-Za-z]*//;s/[[:space:]]*$//')
    
    # Extract category
    local category=""
    if echo "$block" | grep -i "**Category:**" > /dev/null; then
        category=$(echo "$block" | grep -i "**Category:**" | sed 's/.***Category:[[:space:]]*//;s/[[:space:]]*$//')
    fi
    
    # Extract importance
    local importance=""
    if echo "$block" | grep -i "**Importance:**" > /dev/null; then
        importance=$(echo "$block" | grep -i "**Importance:**" | sed 's/.***Importance:[[:space:]]*//;s/[[:space:]]*$//')
    fi
    
    # Skip if no category or low importance
    if [[ -z "$category" ]] || [[ "$category" == "reference" ]]; then
        log_debug "Skipping low-importance entry: $title"
        return
    fi
    
    # Add to memory file
    add_to_memory "$title" "$block" "$category" "$importance"
}

# ============================================================================
# MEMORY FILE UPDATES
# ============================================================================

ensure_memory_file() {
    if [[ ! -f "$MEMORY_FILE" ]]; then
        cat > "$MEMORY_FILE" << 'EOF'
# MEMORY.md - Long-Term Knowledge Base

Consolidated entries from daily sessions with full context.

Format:
- **Date**: When entry was added to memory
- **Category**: Type of entry (decision, discovery, implementation, issue, lesson, architecture)
- **Importance**: critical, important, or reference
- **Details**: Full context, reasoning, and background

---

EOF
        log_info "Created new MEMORY.md"
    fi
}

entry_already_exists() {
    local title="$1"
    
    # Check if title already exists in MEMORY.md (avoid duplicates)
    if grep -F "## \[" "$MEMORY_FILE" | grep -iF "$title" > /dev/null 2>&1; then
        log_debug "Entry already exists: $title"
        return 0
    fi
    
    return 1
}

add_to_memory() {
    local title="$1"
    local full_block="$2"
    local category="$3"
    local importance="$4"
    
    # Check for duplicates
    if entry_already_exists "$title"; then
        return
    fi
    
    log_debug "Adding to MEMORY.md: $title"
    
    local date
    date=$(date -u '+%Y-%m-%d')
    
    local entry="

## [$date] $title

**Category:** $category  
**Importance:** $importance  
**Added:** $(date -u '+%Y-%m-%d %H:%M:%S')

**Details:**
$full_block

---
"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        echo "$entry" >> "$MEMORY_FILE"
        log_info "Added entry to MEMORY.md: $title"
    else
        log_info "[DRY RUN] Would add entry: $title"
    fi
}

# ============================================================================
# INDEXING
# ============================================================================

trigger_incremental_indexing() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would trigger background indexer"
        return
    fi
    
    log_info "Triggering incremental indexing..."
    
    # Check if background indexer exists
    if [[ ! -f "$WORKSPACE/background-indexer.sh" ]]; then
        log_error "background-indexer.sh not found, skipping indexing"
        return 1
    fi
    
    # Run one indexing cycle
    if bash "$WORKSPACE/background-indexer.sh" --once 2>&1 | tee -a "$LOG_FILE"; then
        log_info "Incremental indexing completed"
    else
        log_error "Incremental indexing failed"
        return 1
    fi
}

# ============================================================================
# MAIN CONSOLIDATION
# ============================================================================

consolidate_date() {
    local date="$1"
    
    log_info "Consolidating date: $date"
    ensure_memory_file
    extract_entries_from_daily_file "$date"
}

consolidate_date_range() {
    local start_date="$1"
    local end_date="$2"
    
    log_info "Consolidating range: $start_date to $end_date"
    
    # Convert to seconds for comparison
    local current_sec
    local end_sec
    
    current_sec=$(date -d "$start_date" +%s 2>/dev/null || date -jf "%Y-%m-%d" "$start_date" +%s)
    end_sec=$(date -d "$end_date" +%s 2>/dev/null || date -jf "%Y-%m-%d" "$end_date" +%s)
    
    ensure_memory_file
    
    while [[ $current_sec -le $end_sec ]]; do
        local current_date
        current_date=$(date -d "@$current_sec" +%Y-%m-%d 2>/dev/null || date -jf "%s" "$current_sec" +%Y-%m-%d)
        
        extract_entries_from_daily_file "$current_date"
        
        # Increment by 1 day
        current_sec=$((current_sec + 86400))
    done
}

consolidate_recent() {
    local days="${1:-7}"
    
    log_info "Consolidating last $days days"
    
    ensure_memory_file
    
    for ((i=0; i<$days; i++)); do
        local date
        date=$(date -u -d "$i days ago" +%Y-%m-%d 2>/dev/null || date -jv-${i}d +%Y-%m-%d)
        
        extract_entries_from_daily_file "$date"
    done
}

# ============================================================================
# HELP
# ============================================================================

print_help() {
    cat << 'EOF'
usage: memory-consolidator.sh [OPTIONS]

Consolidate daily memory notes into long-term MEMORY.md.

OPTIONS:
  --today             Consolidate today's notes only
  --date YYYY-MM-DD   Consolidate specific date
  --date-range START END
                      Consolidate date range (inclusive)
  --recent N          Consolidate last N days (default: 7)
  --dry-run           Preview without writing to files
  --force             Force re-indexing even if entries exist
  --debug             Enable debug output

EXAMPLES:
  # Consolidate today's notes
  memory-consolidator.sh --today

  # Consolidate specific date
  memory-consolidator.sh --date 2026-02-04

  # Consolidate week
  memory-consolidator.sh --date-range 2026-01-29 2026-02-05

  # Preview changes
  memory-consolidator.sh --today --dry-run

OUTPUT:
  - Updates MEMORY.md with important entries
  - Triggers incremental indexing
  - Logs to /tmp/memory-consolidation.log

EOF
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    local mode="recent"
    local param1=""
    local param2=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --today)
                mode="today"
                shift
                ;;
            --date)
                mode="single"
                param1="$2"
                shift 2
                ;;
            --date-range)
                mode="range"
                param1="$2"
                param2="$3"
                shift 3
                ;;
            --recent)
                mode="recent"
                param1="${2:-7}"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
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
    mkdir -p "$(dirname "$LOG_FILE")"
    
    log_info "Starting memory consolidation (mode=$mode, dry_run=$DRY_RUN)"
    
    # Execute requested consolidation
    case "$mode" in
        today)
            consolidate_date "$(date -u '+%Y-%m-%d')"
            ;;
        single)
            consolidate_date "$param1"
            ;;
        range)
            consolidate_date_range "$param1" "$param2"
            ;;
        recent)
            consolidate_recent "$param1"
            ;;
        *)
            log_error "Unknown mode: $mode"
            exit 1
            ;;
    esac
    
    # Trigger indexing (unless dry-run)
    if [[ "$DRY_RUN" == "false" ]]; then
        trigger_incremental_indexing
    fi
    
    log_info "Consolidation complete"
}

# ============================================================================
# ENTRY POINT
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
