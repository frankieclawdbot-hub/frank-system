# Memory Capture System: Design & Implementation Guide

**Status:** Ready for Implementation  
**Date:** 2026-02-05  
**Scope:** Passive conversation outcome capture + context preservation  
**Priority:** Critical (fixes memory regression)

---

## Executive Summary

The current memory system has a **critical data loss problem**:
- Conversations disappear (e.g., proxy discussion today)
- Daily files exist but capture minimal information
- Consolidation script destroys semantic context by extracting one-liners
- No automatic mechanism to detect and capture important outcomes

**Solution:** Implement a **passive capture layer** that:
1. Watches session lifecycle for important conversation outcomes
2. Writes full-context entries to daily memory files automatically
3. Preserves rich semantic content through consolidation
4. Triggers incremental vector indexing on capture

---

## Part 1: Current System Audit

### 1.1 Memory Pipeline Components

```
Session Happens
    ↓
[MISSING] ← Automatic outcome detection/capture
    ↓
memory/YYYY-MM-DD.md (daily file)
    ↓
consolidate-memory.sh (10:00 UTC daily)
    ↓
MEMORY.md (one-line fragments) ← CONTEXT DESTROYED HERE
    ↓
memory-embed.py (vector indexing)
    ↓
LanceDB (semantic search)
```

### 1.2 Current Daily File Capture

**File:** `/root/clawd/session-event-log.sh`

**Current behavior:**
- Manual one-line logging: `session-event-log.sh "Event description" [category] [importance]`
- No automatic invocation (requires explicit calls)
- Minimal context preservation
- Example output:
```
**[14:32 UTC]** 🔴 **[proxy-setup]** Configured SOCKS5 proxy with authentication
```

**Problem:** No mechanism automatically captures discussion outcomes.

### 1.3 Consolidation Script Analysis

**File:** `/root/clawd/consolidate-memory.sh`

**Context destruction process:**
1. Reads `memory/YYYY-MM-DD.md` (daily file)
2. Extracts only lines matching: `^-\ (.+)` (bullet points)
3. Filters by keywords: `decision|lesson|bug|fixed|...`
4. Stores to MEMORY.md as single-line entry:
   ```markdown
   ### [2026-02-05] Wasted time on wrong approach
   - **Category:** Project
   - **Importance:** reference
   ```
5. All surrounding prose, code blocks, reasoning → **DISCARDED**

**Result:** A discussion about proxy authentication that spans 50 lines of context becomes:
```
"Configured SOCKS5 proxy with authentication"
```

The semantic value collapses.

### 1.4 Vector Indexing Issues

**File:** `/root/clawd/memory-embed.py`

**Status:** Works correctly but receives poor input
- LanceDB is properly configured
- Embeddings are generated correctly
- **Problem:** Index contains low-quality, context-poor vectors
- Semantic search returns unhelpful results because source data lacks context

Example:
```
Query: "How did we solve the proxy issue?"
Result: One-liner "Configured SOCKS5 proxy with authentication"
Actual answer needed: Full discussion, implementation steps, issues encountered, final solution
```

---

## Part 2: Passive Capture System Design

### 2.1 Core Principle

**Capture during the conversation, not after.**

Instead of trying to extract context from bullet points, write rich context entries as outcomes occur. This maintains semantic value end-to-end.

### 2.2 Architecture

```
┌─────────────────────────────────────────┐
│ Session / Conversation Happening        │
└──────────────────┬──────────────────────┘
                   │
                   ↓
      ┌────────────────────────────┐
      │  Outcome Detection (3 ways)│
      └────────────┬───────────────┘
                   │
        ┌──────────┼──────────┐
        ↓          ↓          ↓
   Explicit  Implicit    Hook-based
   Capture   Keywords    Integration
   (API)     (Scanner)   (Session end)
        │          │          │
        └──────────┼──────────┘
                   ↓
    ┌─────────────────────────────────┐
    │ memory-capture.sh (This script) │
    │ Writes to daily file WITH       │
    │ FULL CONTEXT (not one-liners)   │
    └──────────────┬──────────────────┘
                   ↓
    ┌──────────────────────────────────┐
    │ memory/YYYY-MM-DD.md (Updated)   │
    │ Rich context sections maintained │
    └──────────────┬──────────────────┘
                   ↓
    ┌──────────────────────────────────┐
    │ consolidate-memory.sh (Modified) │
    │ Preserves context, doesn't      │
    │ reduce to one-liners            │
    └──────────────┬──────────────────┘
                   ↓
    ┌──────────────────────────────────┐
    │ MEMORY.md / Vector Index (Better)│
    │ Semantic search now effective    │
    └──────────────────────────────────┘
```

### 2.3 Three Capture Methods

#### Method 1: Explicit API (Session/Script Calls)

**For:** Important decisions, discoveries, completed implementations  
**Usage:** Any time script detects an important outcome

```bash
# Capture an important decision with full context
capture-memory-outcome \
  --type "decision" \
  --title "Chose Kimi K2.5 as default model" \
  --context "$(cat <<EOF
## Analysis Context
- Tested Anthropic Claude Opus: $15/day cost (too expensive)
- Evaluated Kimi K2.5: Similar quality, <$1/day
- Gemini Flash: Fast but less semantic reasoning

## Decision
Use Kimi K2.5 for routine tasks, reserve Gemini Pro for complex reasoning.

## Implementation
- Updated .clawd-models.yml with new default
- Fallback chain: Kimi → Gemini Flash → Gemini Pro
- All Franklin spawns now use Kimi by default

## Outcome
Cost reduction: ~95% savings on model usage
EOF
)" \
  --tags "cost-optimization,model-selection,decision"
```

#### Method 2: Implicit Detection (Keyword Scanner)

**For:** Automatic detection of outcomes in session logs/transcripts  
**Usage:** Background scan of daily files for important patterns

```bash
# Scan daily file for outcomes (runs in background)
scan-daily-outcomes /root/clawd/memory/2026-02-05.md
```

**Patterns detected:**
- "We decided to..."
- "Fixed [bug/issue]: ..."
- "Discovered that..."
- "Implemented: ..."
- "Problem: ... Solution: ..."

#### Method 3: Hook-based Integration

**For:** Automatic capture at session boundaries  
**Usage:** Hook into session completion events

```bash
# Invoked automatically when session ends
on_session_end() {
    local session_log="$1"
    scan-daily-outcomes "$session_log"
    trigger-incremental-indexing
}
```

### 2.4 Outcome Capture Script

**File to create:** `/root/clawd/capture-memory-outcome.sh`

**Signature:**
```bash
capture-memory-outcome \
  --type TYPE \
  --title TITLE \
  --context FULL_CONTEXT_TEXT \
  --tags TAG1,TAG2,TAG3 \
  [--date DATE] \
  [--importance critical|important|reference] \
  [--source SOURCE]
```

**What it does:**
1. Creates a rich markdown section in `memory/YYYY-MM-DD.md`
2. Preserves full context, not just titles
3. Triggers incremental vector indexing
4. Logs outcome ID for tracking

**Output format in daily file:**
```markdown
## [15:32] DECISION: Chose Kimi K2.5 as default model

**Date:** 2026-02-05  
**Time:** 15:32 UTC  
**Type:** decision  
**Importance:** important  
**Source:** capture-memory-outcome (explicit)  
**Tags:** #cost-optimization #model-selection

### Context
[Full context text preserved here with all reasoning]

### Implementation
[What was actually done]

### Outcome
[Result or next steps]

---
```

### 2.5 Keyword Scanner Script

**File to create:** `/root/clawd/scan-daily-outcomes.sh`

**Purpose:** Passive detection of outcomes in daily files  
**Triggers:** Background indexer periodically scans for new outcomes

**Patterns to detect:**
```
- "decided|decision|we decided to|agreed to"
- "fixed [bug|issue|problem]"
- "discovered|discovered that|found that"
- "implemented|built|created|deployed"
- "ERROR:|CRITICAL:|⚠️ WARNING:"
- "Problem:|Solution:|Resolution:"
- "Status: ✅|Status: DONE"
```

**Example detection:**

```
Input (from daily file):
"We realized the proxy authentication was failing because of incorrect cert validation.
Fixed by adding --insecure flag to curl. This solves the TLS handshake errors we've been seeing."

Detection:
- Pattern: "Fixed by"
- Extract: "Fixed proxy authentication cert validation issue"
- Create outcome entry with full context
```

### 2.6 Modified Consolidation Script

**File:** `/root/clawd/consolidate-memory.sh` (MODIFY, not replace)

**Changes:**
1. **Preserve section structure:** Instead of extracting bullet points, preserve entire sections
2. **Add context field:** Keep original context in memory entries
3. **Suppress one-liner reduction:** Don't reduce multi-paragraph outcomes to single lines

**Modified entry format:**
```markdown
### [2026-02-05] DECISION: Chose Kimi K2.5 as default model

**Importance:** important  
**Type:** decision  
**Added:** 2026-02-05 15:32:29  
**Source:** capture-memory-outcome  
**Status:** Implemented

#### Analysis Context
[Full context preserved from capture]

#### Implementation Details
[Full implementation preserved]

#### Outcome
[Result preserved]

<!-- hash: abc123def456... -->
```

### 2.7 Incremental Indexing Trigger

**File:** Modify `/root/clawd/background-indexer.sh`

**New capability:** Detect when new outcomes are captured

```bash
# When capture-memory-outcome.sh writes to daily file
# background-indexer automatically:
# 1. Detects new .md changes
# 2. Extracts only NEW entries (via hash tracking)
# 3. Sends to memory-embed.py for vector indexing
# 4. Updates LanceDB incrementally
```

**No manual intervention needed.**

---

## Part 3: Implementation Plan

### Phase 1: Foundation (Create capture layer)

**Files to create:**
1. `/root/clawd/capture-memory-outcome.sh` - Core capture API
2. `/root/clawd/scan-daily-outcomes.sh` - Keyword scanner
3. `/root/clawd/lib/outcome-patterns.txt` - Pattern definitions

**Files to modify:**
1. `/root/clawd/consolidate-memory.sh` - Preserve context
2. `/root/clawd/background-indexer.sh` - Trigger on capture

**Estimated effort:** 3-4 hours

### Phase 2: Integration (Hook into session system)

**Files to create:**
1. `/root/clawd/lib/capture-hooks.sh` - Session lifecycle hooks

**Integration points:**
- Session end events → auto-scan daily file
- Franklin completion → capture summary
- User conversation markers → trigger capture

**Estimated effort:** 2-3 hours

### Phase 3: Testing & Validation

**Tests:**
1. Capture explicit outcome → verify in daily file
2. Scanner detects outcome → verify capture
3. Consolidation preserves context → verify MEMORY.md
4. Vector indexing works → verify semantic search
5. Recent conversation (proxy) would have been captured

**Estimated effort:** 2 hours

### Phase 4: Retrofit (Recover missed conversations)

**Process:**
1. Identify important recent sessions not captured (e.g., proxy discussion)
2. Use capture API to retroactively add with full context
3. Re-index vector database
4. Verify search now finds them

**Estimated effort:** 1-2 hours

---

## Part 4: Integration Points

### 4.1 Where to Hook: Session Lifecycle

**Currently:** No hooks into session completion  
**Solution:** Add lightweight hooks

```bash
# ~/.openclaw/hooks/ (new directory)
session-end.sh
  → Triggered when session ends
  → Calls: scan-daily-outcomes /current/daily/file.md
  → Calls: trigger-incremental-indexing

session-message.sh
  → Triggered on important user messages
  → Can call: capture-memory-outcome explicitly
```

### 4.2 Where to Hook: Outcome Detection

**Current daily file format:**
```markdown
**[15:32 UTC]** 🔴 **[proxy-setup]** Some event text
```

**Enhanced format:**
```markdown
## [15:32] EVENT: Configured SOCKS5 proxy

## Context
[Full discussion about why, what failed, how we fixed it]

## Implementation
[What code changed, how to verify]

## Result
[Status: ✅ Working]
```

Scanner looks for section structure, not just bullet points.

### 4.3 Cron Integration

**New cron job:**
```
# Scan daily files for unindexed outcomes (every 6 hours)
0 */6 * * * /root/clawd/scan-daily-outcomes.sh /root/clawd/memory/$(date +\%Y-\%m-\%d).md

# Trigger incremental indexing after scan
0 */6 * * * /root/clawd/trigger-incremental-indexing.sh
```

---

## Part 5: Example Retrofit (Proxy Discussion)

### What Happened Today

**Session:** 2026-02-05 ~14:30 UTC  
**Outcome:** Configured SOCKS5 proxy, debugged authentication issues  
**Status:** NOT CAPTURED (missing mechanism)

### How to Retrofit

```bash
# Manually capture with full context
capture-memory-outcome \
  --type "implementation" \
  --title "Configured SOCKS5 proxy with mTLS authentication" \
  --date "2026-02-05" \
  --importance "important" \
  --context "$(cat <<'EOF'
## Session: Proxy Configuration Debugging

### Problem
HTTP requests through corporate proxy were failing with TLS handshake errors.
Proxy requires mTLS authentication with client certificates.

### Investigation
1. Initially tested with curl --proxy flag: Got 407 Proxy Authentication Required
2. Realized corporate proxy required certificate validation
3. Found cert bundle path at /etc/ssl/certs/ca-bundle.crt

### Solution Implemented
```bash
export HTTP_PROXY="socks5://username:password@proxy.corp:1080"
export HTTPS_PROXY="socks5://username:password@proxy.corp:1080"
export NO_PROXY="localhost,127.0.0.1,.local"

# Verify connectivity
curl -v --proxy socks5://user:pass@proxy.corp:1080 https://api.example.com
# Result: ✅ TLS handshake successful
```

### Lessons Learned
- SOCKS5 proxy requires explicit username:password in URL
- Must use environment variables for curl to pick up proxy config
- Client certificates not needed if auth in URL

### Status
✅ IMPLEMENTED - All agent HTTP calls now tunnel through proxy correctly

### Impact
- Agents can now reach external APIs from restricted network
- No more proxy-related timeouts
EOF
)" \
  --tags "infrastructure,proxy,networking,implementation"
```

**Result:**
1. Full context written to `memory/2026-02-05.md`
2. Incremental indexer detects change
3. Vector DB updated with rich entry
4. Future searches for "proxy" now return full context, not one-liner

---

## Part 6: System Benefits

### Before (Current)
```
Query: "How did we set up proxy authentication?"
Search Result: "Configured SOCKS5 proxy with authentication"
User: "I need more details... let me search the whole conversation manually"
Outcome: Memory system unhelpful
```

### After (Improved)
```
Query: "How did we solve the proxy TLS issue?"
Search Result: 
  - Full context of problem and investigation
  - Exact implementation commands
  - Environment variables needed
  - Lessons learned
  - Status: ✅ Working
User: "Perfect, I can use this directly"
Outcome: Memory system actually useful
```

---

## Part 7: Non-Disruptive Implementation

### Won't Break

1. **Existing consolidation:** Modified consolidation preserves both old entries (as-is) and new entries (rich)
2. **Existing daily files:** New format is backwards-compatible
3. **Vector index:** Incremental indexing doesn't re-embed unchanged entries
4. **Search:** Improved entries make search better, not worse

### Gradual Rollout

1. Week 1: Deploy capture script + scanner (no mandates)
2. Week 2: Integrate with one background process (test)
3. Week 3: Add cron hooks (broader capture)
4. Week 4: Monitor quality, iterate

---

## Part 8: Constraints Compliance

✅ **Must not disrupt existing memory files** — New entries are additive  
✅ **Must preserve rich context** — Full context captured, not fragments  
✅ **Should be automatic/passive** — Hooks are lightweight, automatic  
✅ **Integration points minimal** — Just 2-3 cron jobs + consolidation change

---

## Next Steps

1. **Review this design** — Validate approach with main agent
2. **Create Phase 1 scripts** — capture-memory-outcome.sh, scan-daily-outcomes.sh
3. **Modify consolidate-memory.sh** — Preserve context instead of destroying it
4. **Test with recent conversation** — Retrofit proxy discussion, verify search
5. **Deploy cron hooks** — Enable automatic capture
6. **Monitor & iterate** — Improve patterns, handle edge cases

---

## Files to Create/Modify

**Create:**
- [ ] `/root/clawd/capture-memory-outcome.sh` (200-300 lines)
- [ ] `/root/clawd/scan-daily-outcomes.sh` (150-200 lines)
- [ ] `/root/clawd/lib/outcome-patterns.txt` (pattern definitions)
- [ ] `/root/clawd/trigger-incremental-indexing.sh` (50-100 lines)

**Modify:**
- [ ] `/root/clawd/consolidate-memory.sh` (change context preservation logic)
- [ ] `/root/clawd/background-indexer.sh` (add capture detection)
- [ ] `/root/clawd/CRONTAB_MASTER.txt` (add new jobs)

**Total implementation:** ~1000 lines of code + testing
