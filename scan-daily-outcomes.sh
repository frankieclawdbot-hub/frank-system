#!/bin/bash

################################################################################
# scan-daily-outcomes.sh
#
# PURPOSE: Passive keyword scanning for important outcomes in daily files
# Automatically detects and captures important conversations without manual intervention
#
# USAGE:
#   scan-daily-outcomes.sh [FILE] [--dry-run] [--verbose]
#
# EXAMPLES:
#   # Scan today's daily file
#   scan-daily-outcomes.sh
#
#   # Scan specific file
#   scan-daily-outcomes.sh /root/clawd/memory/2026-02-05.md
#
#   # Dry run (show what would be captured)
#   scan-daily-outcomes.sh --dry-run
#
# PATTERNS DETECTED:
# - "We decided to..."
# - "Fixed [issue]: ..."
# - "Discovered that..."
# - "Problem: ... Solution: ..."
# - "✅ IMPLEMENTED"
# - Section headers with keywords (Decision, Discovery, etc.)
#
################################################################################

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

WORKSPACE="${WORKSPACE:-/root/clawd}"
MEMORY_DIR="$WORKSPACE/memory"
CAPTURE_SCRIPT="$WORKSPACE/capture-memory-outcome.sh"
LOG_FILE="/tmp/scan-daily-outcomes.log"

# Defaults
DAILY_FILE="${1:-$MEMORY_DIR/$(date -u '+%Y-%m-%d').md}"
DRY_RUN=false
VERBOSE=false

# Patterns for outcome detection
DECISION_PATTERNS=(
    "we decided"
    "decided to"
    "decision:"
    "we chose"
    "agreed to"
    "will use"
)

IMPLEMENTATION_PATTERNS=(
    "implemented"
    "deployed"
    "set up"
    "configured"
    "created"
    "built"
    "✅"
)

DISCOVERY_PATTERNS=(
    "discovered"
    "found that"
    "realized"
    "turns out"
    "learned that"
    "noticed"
)

ISSUE_PATTERNS=(
    "problem:"
    "issue:"
    "error:"
    "⚠️"
    "broken"
    "not working"
)

RESOLUTION_PATTERNS=(
    "solution:"
    "fixed"
    "resolved"
    "working now"
    "✓"
)

LESSON_PATTERNS=(
    "lesson"
    "learned"
    "pattern:"
    "insight"
    "takeaway"
)

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

# Check if string matches any pattern in array
matches_pattern() {
    local text="$1"
    shift
    local patterns=("$@")

    # Convert to lowercase for matching
    local text_lower=$(echo "$text" | tr '[:upper:]' '[:lower:]')

    for pattern in "${patterns[@]}"; do
        if [[ "$text_lower" =~ $(echo "$pattern" | tr '[:upper:]' '[:lower:]') ]]; then
            log_debug "  Matched pattern: $pattern"
            return 0
        fi
    done
    return 1
}

# Classify outcome type based on content
classify_outcome_type() {
    local content="$1"

    if matches_pattern "$content" "${DECISION_PATTERNS[@]}"; then
        echo "decision"
    elif matches_pattern "$content" "${IMPLEMENTATION_PATTERNS[@]}"; then
        echo "implementation"
    elif matches_pattern "$content" "${DISCOVERY_PATTERNS[@]}"; then
        echo "discovery"
    elif matches_pattern "$content" "${ISSUE_PATTERNS[@]}"; then
        echo "issue"
    elif matches_pattern "$content" "${RESOLUTION_PATTERNS[@]}"; then
        echo "resolution"
    elif matches_pattern "$content" "${LESSON_PATTERNS[@]}"; then
        echo "lesson"
    else
        echo "event"
    fi
}

# Determine importance from content
classify_importance() {
    local content="$1"

    if [[ "$content" =~ (CRITICAL|critical|!!!) ]]; then
        echo "critical"
    elif [[ "$content" =~ (IMPORTANT|important|important|KEY|key) ]]; then
        echo "important"
    else
        echo "reference"
    fi
}

# Extract section context (text between headers)
extract_section_context() {
    local file="$1"
    local start_line="$2"
    local end_line="$3"

    sed -n "${start_line},${end_line}p" "$file"
}

# ============================================================================
# OUTCOME DETECTION
# ============================================================================

scan_for_outcomes() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        log_error "File not found: $file"
        return 1
    fi

    log_info "Scanning: $file"

    local outcomes_found=0
    local line_num=0
    local in_section=false
    local current_section=""
    local section_start=0

    while IFS= read -r line; do
        ((line_num++))

        # Track sections (H2 headers)
        if [[ $line =~ ^##[^#] ]]; then
            current_section="${line//## /}"
            section_start="$line_num"
            in_section=true
            log_debug "Section: $current_section (line $line_num)"
            continue
        fi

        # Skip lines that are too short
        if [[ ${#line} -lt 20 ]]; then
            continue
        fi

        # Check for outcome patterns in line content
        local outcome_type=""
        local is_important=false

        # Skip already-captured outcomes (marked with HTML comments)
        if [[ $line =~ <!--.*hash:.*--> ]]; then
            log_debug "Skipping already-captured line: ${line:0:50}..."
            continue
        fi

        # Look for outcome keywords
        if matches_pattern "$line" "${DECISION_PATTERNS[@]}"; then
            outcome_type="decision"
            is_important=true
        elif matches_pattern "$line" "${IMPLEMENTATION_PATTERNS[@]}"; then
            outcome_type="implementation"
        elif matches_pattern "$line" "${DISCOVERY_PATTERNS[@]}"; then
            outcome_type="discovery"
            is_important=true
        elif matches_pattern "$line" "${ISSUE_PATTERNS[@]}" && matches_pattern "$line" "${RESOLUTION_PATTERNS[@]}"; then
            outcome_type="resolution"
        fi

        # If we found an outcome, capture context
        if [[ -n "$outcome_type" ]]; then
            log_info "✓ Found $outcome_type at line $line_num: ${line:0:60}..."

            # Extract title (first sentence or line)
            local title=$(echo "$line" | sed 's/^[^a-zA-Z0-9]*//' | cut -c1-80)

            # Extract full context (include surrounding lines for richness)
            local context_start=$(( line_num > 5 ? line_num - 5 : 1 ))
            local context_end=$(( line_num < $(wc -l < "$file") - 5 ? line_num + 10 : $(wc -l < "$file") ))
            local context=$(extract_section_context "$file" "$context_start" "$context_end")

            # Determine importance
            local importance=$(classify_importance "$line")
            if [[ "$is_important" == "true" ]]; then
                importance="important"
            fi

            # Generate hash for deduplication
            local content_hash=$(echo "$line" | md5sum | cut -d' ' -f1 | cut -c1-12)

            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "DRY RUN: Would capture:"
                log_info "  Type: $outcome_type"
                log_info "  Title: $title"
                log_info "  Importance: $importance"
                log_info "  Hash: $content_hash"
            else
                # Capture using the main capture script
                log_debug "Calling capture script..."

                if "$CAPTURE_SCRIPT" \
                    --type "$outcome_type" \
                    --title "$title" \
                    --context "$context" \
                    --importance "$importance" \
                    --source "scan-daily-outcomes" \
                    --date "$(date -u '+%Y-%m-%d')" 2>&1 | tee -a "$LOG_FILE"
                then
                    ((outcomes_found++))
                    log_info "✓ Captured outcome $outcomes_found"

                    # Add hash comment to prevent re-scanning (append to file)
                    echo "<!-- hash: $content_hash -->" >> "$file"
                else
                    log_error "Failed to capture outcome"
                fi
            fi
        fi
    done < "$file"

    log_info "Scan complete: Found $outcomes_found outcomes"
    return 0
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    log_info "Starting daily outcomes scanner"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=true
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
            -*)
                log_error "Unknown option: $1"
                exit 1
                ;;
            *)
                DAILY_FILE="$1"
                shift
                ;;
        esac
    done

    log_debug "Daily file: $DAILY_FILE"
    log_debug "Dry run: $DRY_RUN"

    # Scan for outcomes
    if scan_for_outcomes "$DAILY_FILE"; then
        log_info "✓ Scan completed successfully"
        exit 0
    else
        log_error "✗ Scan failed"
        exit 1
    fi
}

print_usage() {
    cat << 'EOF'
Usage: scan-daily-outcomes.sh [FILE] [OPTIONS]

Passive scanner for important conversation outcomes in daily memory files.
Automatically detects and captures:
  - Decisions (decided, chose, agreed)
  - Implementations (deployed, configured, created)
  - Discoveries (found, realized, learned)
  - Issues & Resolutions (problem/solution)
  - Lessons learned

OPTIONS:
  FILE              Daily file to scan (default: today's)
  --dry-run         Show what would be captured without writing
  --verbose         Show detailed debug output
  --help            Show this help

EXAMPLES:
  # Scan today's file
  scan-daily-outcomes.sh

  # Scan specific date
  scan-daily-outcomes.sh /root/clawd/memory/2026-02-05.md

  # Preview what would be captured
  scan-daily-outcomes.sh --dry-run

  # Verbose scanning
  scan-daily-outcomes.sh --verbose
EOF
}

main "$@"
