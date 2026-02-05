# MEMORY.md - Long-Term Memory (Lean)

**Note:** Extended memory has been migrated to knowledge/MEMORY.md
Use `memory-search.sh` or spawn-with-context.sh to access full knowledge base.

## Critical Entries (Always Loaded)



## Model Cost Policy (2026-02-05)

**Decision:** Anthropic models (Claude) are too expensive for routine use.
- **Cost incurred:** $15 in a single day from Opus usage
- **Status:** DISABLED for all agents including Franklin spawns
- **Preferred models:**
  1. **Kimi K2.5** (moonshot/kimi-k2.5) — default, very cheap
  2. **Kimi Code** (kimi-code/kimi-for-coding) — reasoning tasks
  3. **Gemini Flash** (google/gemini-flash-latest) — fast, cheap
  4. **Gemini Pro** (google/gemini-3-pro-preview) — complex tasks

**Fallback chain:** Kimi K2 → Kimi Code → Gemini Flash → Gemini Pro

---

## Memory System — Current State

**Current ADR:** `adr/023-continuity-first-memory-system.md` (quick reference)  
**Evolution History:** `memory/2026-02-05.md` (full narrative)  
**Search:** `memory_search "memory system"`

**Status:** ✅ Live and capturing (long-running Franklin daemon)

**Quick Summary:**
- **Capture:** Background indexer watches session JSONL → chunks → Franklin daemon
- **Judgment:** Hybrid thresholds (sentiment, acknowledgment, substantive decisions)
- **Storage:** Vector DB (LanceDB) with semantic search
- **Threshold:** Importance ≥ 5 (captures relationship moments + decisions)

**For full evolution:** See `memory/2026-02-05.md` or search `memory_search "memory system evolution"`

---

## CRITICAL: Memory System Input + Consolidation Fixed (2026-02-05)

**The Problems:** 
1. Proxy discussion disappeared—no mechanism to capture live conversations
2. Consolidation script reduced rich context to one-line fragments during daily archival
3. Memory system lost information at two critical points: at input and at consolidation

**The Fixes:**

### Input Layer (NEW)
Created `session-memory-bridge.sh` to:
- Poll OpenClow session history in real-time
- Detect important outcomes (decisions, discoveries, implementations, issues)
- Write to memory/YYYY-MM-DD.md with **FULL CONTEXT** (entire conversations, not fragments)
- Trigger background indexer immediately (indexed within 30s)
- Deduplicate via MD5 hash

### Consolidation Layer (IMPROVED)
Created `consolidate-memory-improved.sh` to:
- **Preserve bridge entries intact** (transfer to MEMORY.md as-is, full context)
- **Enhanced consolidation for traditional entries** (capture blocks of context, not just bullets)
- **Never reduce rich discussions to one-liners** (the core problem of old script)
- **Dual-mode handling** (bridge entries get preservation, traditional entries get enhancement)
- **Compatible with new memory pipeline** (works with session-memory-bridge.sh output)

**Result:** 
- Conversations captured in real-time with full context ✅
- No fragmentation during daily consolidation ✅
- Complete information pipeline: capture → index → search ✅
- Proxy discussion (and all others) preserved with full context ✅

**Documentation:** 
- `/root/clawd/MEMORY_SYSTEM_AUDIT.md` — Input layer analysis
- `/root/clawd/CONSOLIDATION_STRATEGY.md` — Consolidation strategy & context preservation

---

## CRITICAL: Franklin Spawning Configuration (2026-02-03)

**The Problem:** Franklin subagent spawning broke during this session. Hours of debugging.

**The Solution:** Configuration must use correct schema:
```json
{
  "agents": {
    "list": [
      {
        "id": "main",
        "default": true,
        "subagents": {
          "allowAgents": ["franklin"]
        }
      }

---

## Accessing Full Memory

```bash
# Search for specific topics
/root/clawd/memory-search.sh "query"

# Spawn Franklin with relevant context
/root/clawd/spawn-with-context.sh "Task" --context "query"

# Browse full knowledge base
cat /root/clawd/knowledge/MEMORY.md
```

### [2026-02-05] Telegram connectivity issues at session start

- **Category:** Ups and Downs of Today
- **Importance:** reference
- **Added:** 2026-02-05 08:00:01
- **Source:** consolidate-memory.sh
<!-- hash: db0c0e852ef9b854fc34d601bd2304db -->

### [2026-02-05] Franklin spawning broken (took debugging to fix)

- **Category:** Ups and Downs of Today
- **Importance:** reference
- **Added:** 2026-02-05 08:00:01
- **Source:** consolidate-memory.sh
<!-- hash: eba0df5aaa2e3061bc85cf4a2543e0a7 -->
