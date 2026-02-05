#!/bin/bash

################################################################################
# consolidate-memory-improved.sh - IMPROVED Daily Memory Consolidation
#
# PURPOSE: Daily memory consolidation with context preservation
# 
# IMPROVEMENTS OVER ORIGINAL:
#   1. Recognizes bridge-written entries (multi-paragraph) and preserves them
#   2. Captures full context blocks (not just single-line bullets)
#   3. Never reduces rich discussions to one-liners
#   4. Backward compatible with traditional bullet-point format
#   5. Deduplicates intelligently
#
# KEY INSIGHT:
#   - Bridge-written entries from session-memory-bridge.sh are already consolidated
#   - Don't re-parse them, just move them to MEMORY.md as-is
#   - Only apply extraction logic to raw bullet points
#   - This prevents context loss during consolidation
#
# USAGE:
#   consolidate-memory-improved.sh                  # Run for today
#   consolidate-memory-improved.sh 2026-02-05      # Run for specific date
#   consolidate-memory-improved.sh --test 2026-02-05
#
################################################################################

set -euo pipefail

WORKSPACE="/root/clawd"
MEMORY_DIR="$WORKSPACE/memory"
ARCHIVE_DIR="$MEMORY_DIR/archive"
LOG_FILE="/tmp/consolidate-memory-improved.log"
LOCK_FILE="/tmp/consolidate-memory-improved.lock"

TARGET_DATE="${1:-$(date +%Y-%m-%d)}"
DAILY_FILE="$MEMORY_DIR/$TARGET_DATE.md"

TEST_MODE=false
if [[ "${1:-}" == "--test" ]] || [[ "${2:-}" == "--test" ]]; then
  TEST_MODE=true
  TARGET_DATE="${2:-$(date +%Y-%m-%d)}"
  DAILY_FILE="$MEMORY_DIR/$TARGET_DATE.md"
fi

# ============================================================================
# LOGGING
# ============================================================================

log_info() {
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$timestamp] [INFO] $*" | tee -a "$LOG_FILE"
}

log_warn() {
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$timestamp] [WARN] $*" | tee -a "$LOG_FILE"
}

log_error() {
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$timestamp] [ERROR] $*" | tee -a "$LOG_FILE"
}

log_debug() {
  if [[ "$TEST_MODE" == true ]]; then
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [DEBUG] $*"
  fi
}

# ============================================================================
# ENTRY TYPE DETECTION
# ============================================================================

# Detect if an entry is bridge-written (multi-paragraph with metadata)
# Format: ### [timestamp] speaker - category ... <!-- hash: ... -->
is_bridge_entry() {
  local entry="$1"
  # Check for bridge entry markers
  if echo "$entry" | grep -q "^### \[.*\] .* - (decision|discovery|implementation|issue|success)" && \
     echo "$entry" | grep -q "<!-- hash: [a-f0-9]\{32\} -->"; then
    return 0
  fi
  return 1
}

# Extract hash from entry (for deduplication)
extract_hash() {
  local entry="$1"
  echo "$entry" | grep -oP "<!-- hash: \K[a-f0-9]{32}" || echo ""
}

# Check if hash already exists in memory
hash_exists_in_memory() {
  local hash="$1"
  local memory_file="$WORKSPACE/MEMORY.md"
  grep -q "<!-- hash: $hash -->" "$memory_file" 2>/dev/null || return 1
}

# ============================================================================
# ENTRY PRESERVATION (for bridge entries)
# ============================================================================

# Transfer bridge entry to MEMORY.md as-is (preserve full context)
preserve_bridge_entry() {
  local entry="$1"
  local memory_file="$WORKSPACE/MEMORY.md"
  
  local hash=$(extract_hash "$entry")
  if [[ -z "$hash" ]]; then
    log_warn "Bridge entry has no hash, skipping"
    return 1
  fi
  
  # Check if already in memory
  if hash_exists_in_memory "$hash"; then
    log_debug "Bridge entry already in memory (hash: ${hash:0:8}), skipping"
    return 0
  fi
  
  # Append to MEMORY.md with full context intact
  if [[ "$TEST_MODE" == false ]]; then
    echo "" >> "$memory_file"
    echo "$entry" >> "$memory_file"
  else
    log_debug "TEST MODE: Would preserve bridge entry (hash: ${hash:0:8})"
  fi
  
  return 0
}

# ============================================================================
# ENHANCED CONTEXT CAPTURE (for traditional entries)
# ============================================================================

# Extract a full context block: from a header through the next header or entry delimiter
# This captures not just the header, but all prose, bullets, code, etc. underneath
extract_context_block() {
  local start_line="$1"
  local file="$2"
  
  # Read from start_line through next section header or end
  local in_block=false
  local block=""
  local line_num=0
  
  while IFS= read -r line; do
    line_num=$((line_num + 1))
    
    if [[ $line_num -lt $start_line ]]; then
      continue
    fi
    
    # Stop at next section header (##)
    if [[ $line =~ ^##\ [^#] ]] && [[ $in_block == true ]]; then
      break
    fi
    
    # Stop at our delimiter
    if [[ "$line" == "---" ]] && [[ -n "$block" ]]; then
      break
    fi
    
    in_block=true
    block+="$line"$'\n'
  done < "$file"
  
  echo "$block"
}

# Extract importance from a block of text
get_importance() {
  local text="$1"
  local lower=$(echo "$text" | tr '[:upper:]' '[:lower:]')
  
  if [[ $lower =~ (critical|blocker|blocked|error|bug|broken|failure) ]]; then
    echo "critical"
  elif [[ $lower =~ (decision|decided|important|insight|success|implemented) ]]; then
    echo "important"
  else
    echo "reference"
  fi
}

# Extract category from context (look for section headers or keywords)
get_category() {
  local text="$1"
  local lower=$(echo "$text" | tr '[:upper:]' '[:lower:]')
  
  if [[ $lower =~ decision ]]; then echo "decision"
  elif [[ $lower =~ discovery ]]; then echo "discovery"
  elif [[ $lower =~ (implemented|built|created|fixed) ]]; then echo "implementation"
  elif [[ $lower =~ (issue|problem|bug|error) ]]; then echo "issue"
  elif [[ $lower =~ (success|success|worked|passed) ]]; then echo "success"
  else echo "outcome"
  fi
}

# Create a consolidated entry from a rich context block
create_consolidated_entry() {
  local date="$1"
  local block="$2"
  
  local importance=$(get_importance "$block")
  local category=$(get_category "$block")
  local hash=$(echo "$block" | md5sum | awk '{print $1}')
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  
  # Create entry preserving the block structure
  local entry=$(cat << EOF

### [$date] ${category^} — ${importance^}

$block

**Category:** $category | **Importance:** $importance | **Consolidated:** $timestamp
<!-- hash: $hash -->

EOF
)
  
  echo "$entry"
}

# ============================================================================
# MAIN CONSOLIDATION
# ============================================================================

consolidate_improved() {
  log_info "=== Starting improved consolidation for $TARGET_DATE ==="
  
  if [[ ! -f "$DAILY_FILE" ]]; then
    log_warn "Daily file not found: $DAILY_FILE"
    return 0
  fi
  
  local memory_file="$WORKSPACE/MEMORY.md"
  mkdir -p "$(dirname "$memory_file")"
  
  if [[ ! -f "$memory_file" ]]; then
    cat > "$memory_file" << 'EOF'
# MEMORY.md - Long-Term Memory

Consolidated from daily notes and session capture.

EOF
  fi
  
  local entries_processed=0
  local bridge_entries_preserved=0
  local context_blocks_consolidated=0
  
  # Strategy: Read entire daily file, identify and handle different entry types
  local full_content=$(cat "$DAILY_FILE")
  
  # Split by bridge-entry markers (### [timestamp])
  while IFS= read -r -d '' entry; do
    if [[ -z "$entry" ]]; then
      continue
    fi
    
    entries_processed=$((entries_processed + 1))
    
    # Check if this is a bridge-written entry
    if is_bridge_entry "$entry"; then
      log_debug "Found bridge entry: $(echo "$entry" | head -1)"
      preserve_bridge_entry "$entry" && bridge_entries_preserved=$((bridge_entries_preserved + 1))
    else
      # Traditional entry: extract full context block and consolidate
      log_debug "Found traditional entry: $(echo "$entry" | head -1)"
      local consolidated=$(create_consolidated_entry "$TARGET_DATE" "$entry")
      if [[ "$TEST_MODE" == false ]]; then
        echo "" >> "$memory_file"
        echo "$consolidated" >> "$memory_file"
      fi
      context_blocks_consolidated=$((context_blocks_consolidated + 1))
    fi
  done < <(
    # Split file into entries (delimited by ### headers or ---)
    awk 'BEGIN {entry=""} 
         /^###/ {if (entry) print entry; entry=$0; next}
         /^---/ {if (entry) print entry; entry=""; next}
         {entry=entry "\n" $0}
         END {if (entry) print entry}' "$DAILY_FILE" | \
    awk 'BEGIN {RS=""; ORS="\0"} {print}'
  )
  
  log_info "Consolidation complete:"
  log_info "  - Entries processed: $entries_processed"
  log_info "  - Bridge entries preserved: $bridge_entries_preserved"
  log_info "  - Context blocks consolidated: $context_blocks_consolidated"
  
  # Archive the daily file
  if [[ "$TEST_MODE" == false ]]; then
    mkdir -p "$ARCHIVE_DIR"
    mv "$DAILY_FILE" "$ARCHIVE_DIR/${TARGET_DATE}.md"
    log_info "Archived daily file: $ARCHIVE_DIR/${TARGET_DATE}.md"
  fi
}

# ============================================================================
# MAIN
# ============================================================================

consolidate_improved
