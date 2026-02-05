# consolidate-memory.sh Modification Guide

**Purpose:** Modify consolidation to preserve full context instead of reducing to one-liners  
**Status:** Ready for implementation  
**Impact:** Critical (fixes context destruction)

---

## Current Problem

The existing `consolidate-memory.sh` script destroys context:

```bash
# Input from memory/2026-02-05.md
## [15:32] 🔷 decision: Use Kimi K2.5 as default model

Analysis showed:
- Anthropic Claude Opus: expensive (~$15/day)
- Kimi K2.5: cheap and effective (~$1/day)
- Decision: Switch to Kimi K2.5 for routine tasks

# Output in MEMORY.md
### [2026-02-05] Use Kimi K2.5 as default model

- **Category:** decision
- **Importance:** important
- **Added:** 2026-02-05 15:32:29
- **Source:** consolidate-memory.sh
<!-- hash: abc123... -->
```

**Loss:** Full analysis → Single-line fragment  
**Result:** Vector index receives poor data → Search returns unhelpful results

---

## Solution Design

### Key Changes

1. **Recognize new outcome format** from `capture-memory-outcome.sh`
   - Outcome entries have structure: `## [HH:MM] EMOJI TYPE: TITLE`
   - Full context comes in sections below
   - Preserve all of it

2. **Preserve context sections** during consolidation
   - Capture everything between outcome header and next header
   - Store in MEMORY.md with structure intact
   - Don't extract and reduce to fragments

3. **Support both formats** for backwards compatibility
   - Old format (bullet points): Extract as before
   - New format (capture outcomes): Preserve structure

---

## Implementation Strategy

### Step 1: Recognize Outcome Entries

Add function to detect new outcome format:

```bash
# Add to consolidate-memory.sh

is_outcome_entry() {
    local line="$1"
    # Pattern: ## [HH:MM] EMOJI TYPE: TITLE
    if [[ $line =~ ^##\ \[[0-9]{2}:[0-9]{2}\]\ [^\ ]+ ]]; then
        return 0
    fi
    return 1
}

extract_outcome_type() {
    local line="$1"
    # Extract type from "## [15:32] 🔷 decision: Title"
    echo "$line" | sed -E 's/.*[🔷⚙️🔍⚠️✅💡]\ ([a-z]+):.*/\1/'
}
```

### Step 2: Capture Full Context for Outcomes

Replace the current bullet-point extraction with context-aware extraction:

```bash
# Instead of:
consolidate_daily_notes() {
    # Old: extract only bullet points
    while IFS= read -r line; do
        if [[ $line =~ ^-\ (.+) ]]; then
            # Add to memory (one-liner)
        fi
    done < "$DAILY_FILE"
}

# Use:
consolidate_daily_notes() {
    local in_outcome=false
    local outcome_lines=()
    local line_num=0
    
    while IFS= read -r line; do
        ((line_num++))
        
        # Check if this is a new outcome
        if is_outcome_entry "$line"; then
            # If we had a previous outcome, process it
            if [[ ${#outcome_lines[@]} -gt 0 ]]; then
                process_outcome_section "${outcome_lines[@]}"
                outcome_lines=()
            fi
            
            # Start capturing new outcome
            outcome_lines+=("$line")
            in_outcome=true
        elif [[ $in_outcome == true && $line =~ ^## ]]; then
            # New section, outcome ended
            process_outcome_section "${outcome_lines[@]}"
            outcome_lines=()
            in_outcome=false
        elif [[ $in_outcome == true ]]; then
            # Accumulate outcome lines
            outcome_lines+=("$line")
        fi
    done < "$DAILY_FILE"
    
    # Process final outcome if exists
    if [[ ${#outcome_lines[@]} -gt 0 ]]; then
        process_outcome_section "${outcome_lines[@]}"
    fi
}

# New function: Preserve full outcome context
process_outcome_section() {
    local lines=("$@")
    local first_line="${lines[0]}"
    
    # Extract title and type
    local title=$(echo "$first_line" | sed 's/.*: //')
    local type=$(extract_outcome_type "$first_line")
    
    # Get importance from content
    local content="${lines[*]}"
    local importance=$(get_importance_level "$content")
    
    # Build rich entry (preserving all context)
    local entry=$(cat << EOF

### [$DATE] $type: $title

**Importance:** $importance  
**Type:** $type  
**Added:** $(date '+%Y-%m-%d %H:%M:%S')  
**Source:** consolidate-memory.sh (from capture)

#### Full Context

$(printf '%s\n' "${lines[@]}" | sed '1d')

---

EOF
)
    
    # Add to MEMORY.md (preserves context!)
    safe_append "$WORKSPACE/MEMORY.md" "$entry"
}
```

### Step 3: Keep Old Format Support

For backwards compatibility with old-style bullet points:

```bash
# Keep this logic for non-outcome entries
is_bullet_point() {
    local line="$1"
    [[ $line =~ ^-\ (.+) ]]
}

has_important_keywords() {
    local text="$1"
    local keywords="decision|lesson|bug|fixed|completed|issue|problem|resolved|critical|important|error|failure|success|pattern|insight"
    [[ $text =~ $keywords ]]
}

# Old function remains unchanged
add_to_memory_legacy() {
    # Original one-liner logic for bullet points
    # (unchanged for backwards compatibility)
}

# New consolidate that handles both formats
consolidate_daily_notes() {
    # First pass: process new outcome entries
    consolidate_outcome_entries
    
    # Second pass: process legacy bullet points (for backwards compat)
    consolidate_legacy_entries
}
```

### Step 4: Update add_to_memory Function

The existing `add_to_memory` function can be retired for new entries:

```bash
# Mark as legacy
add_to_memory_legacy() {
    # This function used for bullet points only
    # New entries handled by process_outcome_section
}

# Keep signature for compatibility
add_to_memory() {
    # Delegate to legacy function
    add_to_memory_legacy "$@"
}
```

---

## Complete Implementation

Here's the minimal change set for `consolidate-memory.sh`:

### Change 1: Add Outcome Detection Functions

Insert after utility functions section:

```bash
# ============================================================================
# OUTCOME ENTRY DETECTION (Phase 1b: New capture format support)
# ============================================================================

is_outcome_entry() {
    local line="$1"
    # Pattern: ## [HH:MM] TYPE: TITLE
    # Examples:
    # ## [15:32] decision: Use Kimi K2.5
    # ## [14:30] 🔷 implementation: Set up proxy
    if [[ $line =~ ^##\ \[[0-9]{2}:[0-9]{2}\] ]]; then
        return 0
    fi
    return 1
}

extract_outcome_type() {
    local line="$1"
    # Extract type from header
    # Handle both formats:
    # "## [15:32] decision: Title" → "decision"
    # "## [15:32] 🔷 decision: Title" → "decision"
    echo "$line" | \
        sed -E 's/.*\[.*\][[:space:]]+([🔷⚙️🔍⚠️✅💡])[[:space:]]+//' | \
        sed -E 's/^([a-z]+):.*/\1/'
}

process_outcome_section() {
    local DAILY_FILE="$1"
    local start_line="$2"
    local end_line="$3"
    
    # Extract lines for this outcome
    local outcome_text=$(sed -n "${start_line},${end_line}p" "$DAILY_FILE")
    
    # Get first line (header)
    local header=$(echo "$outcome_text" | head -1)
    
    # Extract metadata
    local title=$(echo "$header" | sed -E 's/.*[a-z]+:[[:space:]]*//')
    local type=$(extract_outcome_type "$header")
    local importance=$(get_importance_level "$outcome_text")
    
    # Generate entry hash
    local entry_hash=$(echo "$title|$type" | md5sum | cut -d' ' -f1)
    
    # Check for duplicates
    if grep -q "<!-- hash: $entry_hash -->" "$WORKSPACE/MEMORY.md" 2>/dev/null; then
        log_debug "Outcome already in MEMORY (hash: ${entry_hash:0:8}...), skipping"
        return
    fi
    
    # Build entry with full context preserved
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local entry=$(cat << EOF

### [$TARGET_DATE] $type: $title

**Importance:** $importance  
**Type:** $type  
**Added:** $timestamp  
**Source:** consolidate-memory.sh  

#### Full Context

$outcome_text

---
<!-- hash: $entry_hash -->

EOF
)
    
    # Append to MEMORY.md
    if [[ "$TEST_MODE" == false ]]; then
        safe_append "$WORKSPACE/MEMORY.md" "$entry"
    else
        log_debug "TEST MODE: Would add outcome to MEMORY.md: $title"
    fi
}

```

### Change 2: Modify consolidate_daily_notes Function

Replace the existing parsing logic:

```bash
consolidate_daily_notes() {
    log_header "Consolidating Daily Notes"
    
    # ... (keep existing validation) ...
    
    # NEW: Process outcome entries (from capture-memory-outcome.sh)
    local in_outcome=false
    local outcome_start=0
    local line_num=0
    local current_section=""
    
    while IFS= read -r line; do
        ((line_num++))
        
        # Track sections
        if [[ $line =~ ^##\ [^#] ]]; then
            # Check if this was an outcome section
            if [[ "$in_outcome" == "true" && "$outcome_start" -gt 0 ]]; then
                # End of previous outcome, process it
                process_outcome_section "$DAILY_FILE" "$outcome_start" "$((line_num - 1))"
            fi
            
            # Check if this is a new outcome
            if is_outcome_entry "$line"; then
                in_outcome=true
                outcome_start="$line_num"
            else
                current_section="${line//## /}"
                in_outcome=false
            fi
        fi
        
        # OLD: Also process bullet points (for backwards compat)
        if [[ $line =~ ^-\ (.+) ]]; then
            local bullet_text="${BASH_REMATCH[1]}"
            
            # Only extract if not in outcome section
            if [[ "$in_outcome" == "false" ]] && has_important_keywords "$line"; then
                add_to_memory_legacy "$TARGET_DATE" "$bullet_text" "$current_section"
                log_debug "Found legacy entry: $bullet_text"
            fi
        fi
    done < "$DAILY_FILE"
    
    # Process final outcome if exists
    if [[ "$in_outcome" == "true" && "$outcome_start" -gt 0 ]]; then
        local total_lines=$(wc -l < "$DAILY_FILE")
        process_outcome_section "$DAILY_FILE" "$outcome_start" "$total_lines"
    fi
}
```

---

## Testing the Modification

### Before & After Test

```bash
# Create test daily file with new outcome format
cat > /tmp/test-outcome.md << 'EOF'
# 2026-02-05 - Daily Notes

## [15:32] 🔷 decision: Use Kimi K2.5 as default model

**Analysis:** Compared Claude Opus ($15/day), Kimi K2.5 (<$1/day), Gemini Flash
**Decision:** Switch to Kimi K2.5 for cost efficiency
**Status:** Implemented in .clawd-models.yml

## [14:30] ⚙️ implementation: Configure SOCKS5 proxy

Set up proxy authentication with credentials in URL format.
Tested with multiple endpoints: ✅

## [16:00] 💡 lesson: SOCKS5 requires explicit credentials

When setting up SOCKS5 proxies, credentials must be in URL:
socks5://username:password@host:port

EOF

# Copy current consolidation script as backup
cp /root/clawd/consolidate-memory.sh /tmp/consolidate-memory-backup.sh

# Test with MODIFIED version
# (after applying the changes above)
TEST_MODE=true /root/clawd/consolidate-memory.sh 2026-02-05

# Compare output
echo "=== OLD VERSION (one-liners) ==="
TEST_MODE=true /tmp/consolidate-memory-backup.sh 2026-02-05 | grep "Would add"

echo "=== NEW VERSION (full context) ==="
TEST_MODE=true /root/clawd/consolidate-memory.sh 2026-02-05 | grep "Would add"
```

### Validation Checklist

- [ ] Outcome entries recognized correctly
- [ ] Full context preserved (not reduced)
- [ ] MEMORY.md entries contain all context sections
- [ ] Backwards compatibility: old bullet points still work
- [ ] Deduplication: hash prevents re-processing
- [ ] Performance: consolidation still completes in <10 seconds

---

## Integration with Full Pipeline

### Before Deploy

1. Backup current `consolidate-memory.sh`:
   ```bash
   cp /root/clawd/consolidate-memory.sh /root/clawd/consolidate-memory.sh.backup
   ```

2. Apply modifications (either manually or via patch)

3. Test on past date:
   ```bash
   /root/clawd/consolidate-memory.sh 2026-02-04 --test
   ```

4. Verify output looks correct (context preserved)

5. Deploy to cron (will run automatically at 10:00 UTC)

### After Deploy

1. Monitor `/tmp/consolidate-memory.log` for errors
2. Check `/root/clawd/MEMORY.md` for context preservation
3. Test vector search on new entries
4. Verify no one-liner reduction happening

---

## Backwards Compatibility

The modification maintains full backwards compatibility:

- ✅ Old daily file format (bullet points) still works
- ✅ Existing MEMORY.md entries untouched
- ✅ Vector indexing unchanged
- ✅ Consolidation script signature unchanged
- ✅ Can toggle between old/new behavior for testing

---

## Performance Impact

- **Memory processing:** Minimal overhead (slightly faster, fewer extractions)
- **File I/O:** Same (reading daily file once)
- **Consolidation time:** ~5-10 seconds (unchanged)
- **Storage:** Slightly larger (full context stored, vs fragments)
  - Estimate: 50-100 bytes per outcome (worth the semantic value)

---

## Deployment Checklist

- [ ] Apply modifications to `consolidate-memory.sh`
- [ ] Test on past date with `--test` flag
- [ ] Verify context preservation in TEST output
- [ ] Backup original script
- [ ] Deploy to cron or trigger manually
- [ ] Monitor logs for 24 hours
- [ ] Verify new entries in MEMORY.md have full context
- [ ] Test vector search on new outcomes

---

## Summary

This modification transforms `consolidate-memory.sh` from:
```
Context destroyer: Entry → Extract bullet → One-liner ✗
```

To:
```
Context preserver: Entry → Preserve structure → Full context ✓
```

**Result:** Vector index receives high-quality entries → Search actually works

---

## Next Steps

1. Review this design with main agent
2. Apply modifications (can be done gradually)
3. Test end-to-end
4. Deploy to production
5. Monitor memory quality improvements
