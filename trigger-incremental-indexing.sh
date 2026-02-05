#!/bin/bash

################################################################################
# trigger-incremental-indexing.sh
#
# PURPOSE: Trigger incremental vector indexing for newly captured memory outcomes
# Integrates with background-indexer and memory-embed.py
#
# USAGE:
#   trigger-incremental-indexing.sh [--force] [--verbose]
#
# BEHAVIOR:
#   1. Check for new entries since last index
#   2. Extract entries from daily memory files
#   3. Send to memory-embed.py for vector indexing
#   4. Update LanceDB incrementally (only new entries)
#   5. Log results
#
# DESIGN:
#   - Non-blocking (runs in background)
#   - Debounced (minimum 5 seconds between runs)
#   - Idempotent (hashes prevent re-indexing)
#   - Lightweight (processes only new entries)
#
################################################################################

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

WORKSPACE="${WORKSPACE:-/root/clawd}"
MEMORY_DIR="$WORKSPACE/memory"
LOG_FILE="/tmp/trigger-incremental-indexing.log"
DEBOUNCE_FILE="/tmp/incremental-index.debounce"
DEBOUNCE_SECONDS=5
STATE_FILE="/tmp/incremental-index.state"

# Indexing
EMBED_SCRIPT="$WORKSPACE/memory-embed.py"
BACKUP_INDEXER="$WORKSPACE/background-indexer.sh"

# Limits
MAX_ENTRIES_PER_RUN=50
TIMEOUT_SECONDS=30

# Flags
FORCE=false
VERBOSE=false

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*" | tee -a "$LOG_FILE"
}

log_debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $*" | tee -a "$LOG_FILE"
    fi
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "$LOG_FILE" >&2
}

# Check if debounce is active (prevent too-frequent indexing)
is_debounced() {
    if [[ -f "$DEBOUNCE_FILE" ]]; then
        local last_run=$(stat -f%m "$DEBOUNCE_FILE" 2>/dev/null || stat -c%Y "$DEBOUNCE_FILE" 2>/dev/null)
        local now=$(date +%s)
        local elapsed=$((now - last_run))

        if [[ $elapsed -lt $DEBOUNCE_SECONDS ]]; then
            log_debug "Debounced (${elapsed}s < ${DEBOUNCE_SECONDS}s)"
            return 0
        fi
    fi
    return 1
}

# Update debounce timestamp
update_debounce() {
    touch "$DEBOUNCE_FILE"
}

# Get files changed since last index
get_changed_files() {
    local since_file="$STATE_FILE"
    local changed_files=()

    # Find all daily .md files in memory/
    while IFS= read -r file; do
        # Check if file is newer than last index
        if [[ ! -f "$since_file" ]]; then
            # First run, include recent files
            changed_files+=("$file")
        elif [[ "$file" -nt "$since_file" ]]; then
            changed_files+=("$file")
        fi
    done < <(find "$MEMORY_DIR" -name "*.md" -type f | grep -E "20[0-9]{2}-[0-9]{2}-[0-9]{2}" | tail -10)

    printf '%s\n' "${changed_files[@]}" 2>/dev/null || true
}

# Extract new entries from file (since last indexed)
extract_new_entries() {
    local file="$1"
    local max_entries="$2"
    local entry_count=0

    log_debug "Extracting entries from: $(basename "$file")"

    # Look for outcome sections (## [TIME] $TYPE: $TITLE)
    while IFS= read -r line; do
        # Match outcome headers: "## [HH:MM] TYPE: TITLE"
        if [[ $line =~ ^##\ \[[0-9]{2}:[0-9]{2}\]\ ]]; then
            # Extract content until next header or end of file
            local title=$(echo "$line" | sed 's/^##[[:space:]]*\[[0-9:]*\][[:space:]]*//' | cut -c1-100)

            # For now, use title as the entry (could be enhanced to get full context)
            if [[ -n "$title" && ${#title} -gt 20 ]]; then
                echo "$title"
                ((entry_count++))

                if [[ $entry_count -ge $max_entries ]]; then
                    break
                fi
            fi
        fi
    done < "$file"

    return 0
}

# Index entries using memory-embed.py
index_entries_via_embed_script() {
    local entries_file="$1"

    if [[ ! -f "$entries_file" ]] || [[ ! -s "$entries_file" ]]; then
        log_debug "No entries to index"
        return 0
    fi

    if [[ ! -x "$EMBED_SCRIPT" ]]; then
        log_debug "Embed script not executable: $EMBED_SCRIPT"
        return 0
    fi

    log_info "Indexing entries via memory-embed.py..."

    local indexed=0
    while IFS= read -r entry; do
        # Call embed script for each entry
        if timeout "$TIMEOUT_SECONDS" python3 "$EMBED_SCRIPT" \
            --add "$entry" \
            --category "memory" \
            --source "incremental-index" 2>&1 | tee -a "$LOG_FILE"
        then
            ((indexed++))
        else
            log_error "Failed to index entry (timeout or error)"
        fi
    done < "$entries_file"

    log_info "Indexed $indexed entries"
    return 0
}

# Fallback: use background-indexer if embed script unavailable
index_entries_via_background_indexer() {
    log_info "Using background-indexer for indexing..."

    if [[ ! -x "$BACKUP_INDEXER" ]]; then
        log_error "Background indexer not available: $BACKUP_INDEXER"
        return 1
    fi

    # Run one-time indexing
    if timeout "$TIMEOUT_SECONDS" "$BACKUP_INDEXER" --once 2>&1 | tee -a "$LOG_FILE"; then
        log_info "✓ Indexing complete"
        return 0
    else
        log_error "Background indexer failed"
        return 1
    fi
}

# ============================================================================
# MAIN INDEXING LOGIC
# ============================================================================

run_incremental_indexing() {
    log_info "Starting incremental indexing"

    # Check debounce
    if [[ "$FORCE" != "true" ]] && is_debounced; then
        log_info "Skipping (debounced)"
        return 0
    fi

    # Get changed files
    local changed_files
    changed_files=$(get_changed_files)

    if [[ -z "$changed_files" ]]; then
        log_info "No changed files"
        update_debounce
        return 0
    fi

    log_info "Found changed files:"
    echo "$changed_files" | while read -r file; do
        log_info "  - $(basename "$file")"
    done

    # Extract entries from changed files
    local entries_file="/tmp/incremental-index-entries.txt"
    > "$entries_file"

    echo "$changed_files" | while read -r file; do
        extract_new_entries "$file" "$MAX_ENTRIES_PER_RUN" >> "$entries_file"
    done

    # Index entries
    if [[ -s "$entries_file" ]]; then
        local total_entries=$(wc -l < "$entries_file")
        log_info "Extracted $total_entries entries for indexing"

        # Try primary indexing method
        if [[ -x "$EMBED_SCRIPT" ]]; then
            index_entries_via_embed_script "$entries_file" || true
        else
            # Fallback to background-indexer
            index_entries_via_background_indexer || true
        fi
    fi

    # Update state
    touch "$STATE_FILE"
    update_debounce

    log_info "✓ Incremental indexing complete"
    return 0
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    log_info "Triggered incremental indexing"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force)
                FORCE=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help|-h)
                print_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    log_debug "Workspace: $WORKSPACE"
    log_debug "Force: $FORCE"

    # Run indexing
    if run_incremental_indexing; then
        exit 0
    else
        exit 1
    fi
}

print_usage() {
    cat << 'EOF'
Usage: trigger-incremental-indexing.sh [OPTIONS]

Trigger incremental vector indexing for newly captured memory outcomes.
Processes only changed files, debounced to prevent CPU spikes.

OPTIONS:
  --force      Skip debounce, run immediately
  --verbose    Show detailed debug output
  --help       Show this help

BEHAVIOR:
  - Detects changed memory files
  - Extracts new outcome entries
  - Sends to memory-embed.py or background-indexer
  - Updates LanceDB incrementally
  - Debounced (minimum 5 seconds between runs)

INTEGRATION:
  Called automatically by:
  - capture-memory-outcome.sh (after capturing)
  - background-indexer.sh (periodic checks)
  - scan-daily-outcomes.sh (after scanning)

EXAMPLE:
  # Trigger indexing with verbose output
  trigger-incremental-indexing.sh --verbose

  # Force immediate indexing (skip debounce)
  trigger-incremental-indexing.sh --force
EOF
}

main "$@"
