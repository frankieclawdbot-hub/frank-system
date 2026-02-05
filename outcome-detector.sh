#!/bin/bash

################################################################################
# outcome-detector.sh - Passive Detection of Important Conversation Outcomes
#
# PURPOSE:
#   Identifies important conversation outcomes (decisions, discoveries, issues)
#   from session logs or message streams without manual tagging.
#
# DETECTION CATEGORIES:
#   - Decision: chosen/decided/determined/choose
#   - Discovery: discovered/found/realized/insight
#   - Implementation: implemented/deployed/fixed/solved/built
#   - Issue: bug/error/problem/blocker/stuck/failed
#   - Lesson: lesson/pattern/principle/rule
#   - Architecture: architecture/design/system/refactor
#   - Critical: CRITICAL/!!!/urgent/blocker
#
# USAGE:
#   outcome-detector.sh --stdin                  # Read from stdin
#   outcome-detector.sh --file /path/to/log      # Read from file
#   outcome-detector.sh --channel webchat        # Monitor OpenClaw channel
#   outcome-detector.sh --date 2026-02-05        # Search today's logs
#   outcome-detector.sh --test                   # Run with test data
#
# OUTPUT:
#   JSON with: { text, category, importance, timestamp, context }
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
SCRIPT_DIR="$WORKSPACE"
LOG_FILE="${OUTCOME_LOG:-/tmp/outcome-detector.log}"

# Keywords organized by category
declare -A KEYWORDS=(
    [decision]="decided|decision|determined|choose|selected|selected|committed"
    [discovery]="discovered|found|realized|learned|insight|identified|uncovered"
    [implementation]="implemented|deployed|fixed|solved|built|created|integrated"
    [issue]="bug|error|issue|problem|blocker|blocked|stuck|failed|failure"
    [lesson]="lesson|pattern|principle|rule|understand|recognize|notice"
    [architecture]="architecture|design|system|refactor|structure|framework"
    [critical]="CRITICAL|!!!|urgent|blocker|critical"
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
    echo "[INFO] $msg" | tee -a "$LOG_FILE"
}

log_error() {
    local msg="$1"
    echo "[ERROR] $msg" >&2 | tee -a "$LOG_FILE"
}

# ============================================================================
# OUTCOME DETECTION
# ============================================================================

detect_category() {
    local text="$1"
    
    # Check critical first (highest priority)
    if echo "$text" | grep -iE "${KEYWORDS[critical]}" > /dev/null; then
        echo "critical"
        return
    fi
    
    # Check other categories in order of importance
    for category in decision architecture issue implementation discovery lesson; do
        if echo "$text" | grep -iE "${KEYWORDS[$category]}" > /dev/null; then
            echo "$category"
            return
        fi
    done
    
    echo "reference"
}

determine_importance() {
    local category="$1"
    local text="$2"
    
    case "$category" in
        critical|decision|architecture|issue)
            echo "important"
            ;;
        implementation|discovery)
            if echo "$text" | grep -iE "IMPORTANT|KEY|SIGNIFICANT" > /dev/null; then
                echo "important"
            else
                echo "reference"
            fi
            ;;
        *)
            echo "reference"
            ;;
    esac
}

extract_context_lines() {
    local text="$1"
    local max_sentences=5
    
    # Take up to max_sentences (period-delimited)
    echo "$text" | sed -E "s/([.!?])/\1\n/g" | head -n "$max_sentences" | tr -d '\n' | sed 's/  */ /g'
}

# ============================================================================
# OUTPUT FORMATTING
# ============================================================================

format_json_output() {
    local text="$1"
    local category="$2"
    local importance="$3"
    local timestamp="$4"
    
    # Escape JSON special characters
    local escaped_text
    escaped_text=$(echo "$text" | jq -R .)
    
    cat <<EOF
{
  "text": $escaped_text,
  "category": "$category",
  "importance": "$importance",
  "timestamp": "$timestamp",
  "source": "outcome-detector",
  "version": "1.0"
}
EOF
}

# ============================================================================
# INPUT PROCESSING
# ============================================================================

process_stdin() {
    local timestamp
    timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    
    local text
    text=$(cat)
    
    if [[ -z "$text" ]]; then
        log_error "No input provided"
        return 1
    fi
    
    log_debug "Processing stdin: ${text:0:50}..."
    
    local category
    category=$(detect_category "$text")
    
    local importance
    importance=$(determine_importance "$category" "$text")
    
    # Only output if something important was detected
    if [[ "$category" != "reference" ]] || [[ "$importance" == "important" ]]; then
        format_json_output "$text" "$category" "$importance" "$timestamp"
    else
        log_debug "Not significant enough to capture (category=$category, importance=$importance)"
    fi
}

process_file() {
    local filepath="$1"
    
    if [[ ! -f "$filepath" ]]; then
        log_error "File not found: $filepath"
        return 1
    fi
    
    log_info "Processing file: $filepath"
    
    local timestamp
    timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    
    local line_num=0
    local outcome_count=0
    
    while IFS= read -r line; do
        ((line_num++))
        
        # Skip empty lines and comments
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^# ]] && continue
        
        # Skip lines that are too short to be meaningful
        [[ ${#line} -lt 20 ]] && continue
        
        local category
        category=$(detect_category "$line")
        
        if [[ "$category" != "reference" ]]; then
            local importance
            importance=$(determine_importance "$category" "$line")
            
            format_json_output "$line" "$category" "$importance" "$timestamp"
            echo "---OUTCOME_SEPARATOR---"
            
            ((outcome_count++))
        fi
    done < "$filepath"
    
    log_info "Processed $filepath: Found $outcome_count outcomes from $line_num lines"
}

process_date_logs() {
    local date="$1"
    
    # Look for daily memory file
    local daily_file="$WORKSPACE/memory/$date.md"
    
    if [[ -f "$daily_file" ]]; then
        log_info "Found daily file: $daily_file"
        process_file "$daily_file"
    else
        log_error "No daily file found for date: $date"
        return 1
    fi
}

# ============================================================================
# TEST MODE
# ============================================================================

run_tests() {
    log_info "Running outcome detector tests..."
    
    echo "---TEST 1: Decision detection---"
    echo "We decided to implement a reverse proxy for security." | process_stdin
    
    echo ""
    echo "---TEST 2: Issue detection---"
    echo "Found a bug in the authentication system that blocks production deployment." | process_stdin
    
    echo ""
    echo "---TEST 3: Discovery---"
    echo "Discovered that the consolidation script is completely stubbed and doing nothing." | process_stdin
    
    echo ""
    echo "---TEST 4: Critical event---"
    echo "CRITICAL: Dashboard API is down, all routes returning 404." | process_stdin
    
    echo ""
    echo "---TEST 5: Architecture decision---"
    echo "Designed autonomous director architecture with PM Kanban integration." | process_stdin
    
    log_info "Tests complete"
}

# ============================================================================
# HELP
# ============================================================================

print_help() {
    cat << 'EOF'
usage: outcome-detector.sh [OPTIONS]

Passively detects important conversation outcomes (decisions, discoveries, issues)
from logs or message streams.

OPTIONS:
  --stdin              Read from standard input (one line or paragraph)
  --file PATH          Process specific log file
  --date YYYY-MM-DD    Process daily memory file for date
  --test               Run with test data
  --debug              Enable debug output
  --help               Show this help

DETECTION CATEGORIES:
  - decision:      "decided", "determined", "chose"
  - discovery:     "found", "realized", "learned"
  - implementation: "implemented", "fixed", "deployed"
  - issue:         "bug", "error", "blocker"
  - lesson:        "lesson", "pattern", "principle"
  - architecture:  "architecture", "design", "system"
  - critical:      "CRITICAL", "urgent"

OUTPUT:
  JSON with text, category, importance, timestamp

EXAMPLES:
  # Detect outcome from stdin
  echo "We decided to use nginx" | outcome-detector.sh --stdin

  # Process a log file
  outcome-detector.sh --file /path/to/conversation.log

  # Process today's memory
  outcome-detector.sh --date 2026-02-05

  # Run tests
  outcome-detector.sh --test

EOF
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    local mode="stdin"
    local input_file=""
    local input_date=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --stdin)
                mode="stdin"
                shift
                ;;
            --file)
                mode="file"
                input_file="$2"
                shift 2
                ;;
            --date)
                mode="date"
                input_date="$2"
                shift 2
                ;;
            --test)
                mode="test"
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
    
    # Execute requested mode
    case "$mode" in
        stdin)
            process_stdin
            ;;
        file)
            process_file "$input_file"
            ;;
        date)
            process_date_logs "$input_date"
            ;;
        test)
            run_tests
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
