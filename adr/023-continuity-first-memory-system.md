# ADR-023: Continuity-First Memory System

**Status:** ✅ Accepted & Implemented  
**Date:** 2026-02-05  
**Author:** Tyson & Frank  
**Replaces/Supersedes:** Complex multi-layer approaches in ADR-007, ADR-008

**Evolution History:** See `memory/2026-02-05.md` and search `memory_search "memory system evolution"`

---

## Context

The memory system had become over-engineered with multiple overlapping, non-integrated components:

1. **ADR-001/002:** Semantic search + background indexer (file-based, not running)
2. **ADR-003:** Sleep protocol consolidation (daily, fragments context)  
3. **ADR-008:** Consciousness layers (8 parallel processing layers, not running)
4. **Session-memory-bridge:** Attempted real-time capture (over-complex, 400+ lines)
5. **Consolidation scripts:** Multiple competing implementations

**Problems observed:**
- Proxy discussion with Tyson disappeared completely from memory
- No working real-time capture mechanism
- Background indexer existed but wasn't running
- Consciousness layers (sensory, emotional, etc.) built but disabled
- Daily consolidation reduced rich discussions to one-line fragments
- System complexity exceeded actual functionality

**Root cause:** We built infrastructure (layers, managers, orchestrators) before ensuring the basic capture-to-search pipeline actually worked.

---

## Current Architecture

**Strip the memory system to essentials:**

1. **One capture mechanism:** Background indexer watches session JSONL files directly
2. **One indexing mechanism:** Long-running Franklin daemon with AI judgment
3. **One search mechanism:** Vector DB (LanceDB) with semantic search
4. **One fallback:** Keyword-based extraction (reliable if Franklin fails)
5. **Disable non-essential systems:** Consciousness layers dormant (not deleted)

**Key insight:** Session transcripts are already written to disk at `/root/.openclaw/agents/main/sessions/*.jsonl`. Instead of building a complex capture layer, just parse these files directly.

**Priority:** Continuity first (don't lose important conversations), elegance second.

---

### Data Flow

```
Conversation (happens naturally)
    ↓ (OpenClaw writes JSONL transcript)
/root/.openclaw/agents/main/sessions/*.jsonl
    ↓ (Background indexer detects new lines)
Extract chunks → /tmp/memory-inbox/
    ↓ (Franklin already running, instant response)
MemoryJudge Franklin (continuous daemon)
    ↓ (AI judgment with hybrid thresholds)
Category + Importance score (1-10, threshold ≥ 5)
    ↓ (if importance ≥ 5)
/root/clawd/memory/importance-queue.jsonl
    ↓ (Background indexer embeds)
lancedb/memory.db (vector embeddings)
    ↓
memory_search (semantic retrieval)
```

---

## Components

### 1. Background Indexer (`background-indexer.sh`)
- **Purpose:** Orchestrate capture pipeline
- **Method:**
  - File watcher on sessions/ directory
  - Track processed lines per session file (state file)
  - Accumulate new lines until threshold (10 messages OR 5 min)
  - Write chunk files to `/tmp/memory-inbox/`
  - Embed from importance-queue.jsonl
- **State tracking:** `/root/clawd/.memory-capture-state.json`

### 2. MemoryJudge Franklin (`memory-judge-franklin.sh`)
- **Purpose:** AI-based importance detection and categorization
- **Model:** haiku (anthropic/claude-haiku-4-5) — fast, cheap, reliable
- **Input:** Chunk files in `/tmp/memory-inbox/`
- **Output:** `/root/clawd/memory/importance-queue.jsonl`
- **Categories:** decision, discovery, implementation, issue, success, feeling, philosophy, sentiment, acknowledgment
- **Key improvement:** Spawned ONCE at startup (not per-batch), continuous `while true` loop

### 3. memory-embed.py (existing)
- **Purpose:** Generate vector embeddings
- **Input:** Entries from importance-queue.jsonl
- **Output:** `lancedb/memory.db`

### 4. memory-search.sh (existing)
- **Purpose:** Semantic search over vector DB
- **Method:** Query embedding → cosine similarity → ranked results

### 5. Fallback: Keyword-Based Extraction
- **Trigger:** If Franklin daemon fails
- **Method:** Direct keyword matching on session JSONL
- **Keywords:** decided, discovered, implemented, fixed, issue, success, excited, philosophy, meaningful
- **Automatic recovery:** Try Franklin again after 30 minutes

---

## Calibration & Thresholds

### Hybrid Threshold System

| Message Type | Length | Logic | Example |
|--------------|--------|-------|---------|
| **Trivial** | <50 chars | Skip if no sentiment/acknowledgment keywords | "ok", "hmm" |
| **Sentiment** | <50 chars | Capture if sentiment detected (imp:6) | "You're amazing Frank!" |
| **Acknowledgment** | <50 chars | Capture if acknowledgment detected (imp:5) | "Exactly right!" |
| **Substantive** | ≥50 chars | Full category detection (imp:5-10) | "I decided to..." |

**Keyword Sets:**
```bash
# Sentiment keywords (capture short positive messages)
SENTIMENT="amazing|wonderful|incredible|brilliant|love|thank|appreciate|proud|impressed|grateful|excited"

# Acknowledgment keywords (capture agreement/praise)
ACKNOWLEDGMENT="exactly|yes|agree|right|perfect|great|excellent|well done|good job|nicely done"
```

**Importance Threshold:** ≥ 5  
**Rationale:** Length filter already excludes trivial responses. Lower threshold captures feelings, philosophy, relationship moments without adding noise.

**Result:** Relationship moments preserved, substantive content prioritized, noise filtered.

---

## Files

| File | Purpose | Status |
|------|---------|--------|
| `background-indexer.sh` | Orchestrate capture pipeline | ✅ Active |
| `memory-judge-franklin.sh` | AI importance detection daemon | ✅ Active |
| `importance-queue.jsonl` | Staging file for important entries | ✅ Active |
| `memory-embed.py` | Vector generation | ✅ Active |
| `memory-search.sh` | Semantic search | ✅ Active |
| `lancedb/memory.db` | Vector storage | ✅ Active |
| `.memory-capture-state.json` | State tracking | ✅ Active |

---

## Consequences

**Positive:**
- ✅ Real-time capture (session JSONL written immediately)
- ✅ Immediate indexing (30s debounce after file write)
- ✅ Full context preservation (no fragmentation)
- ✅ Simple to debug (2 components, clear data flow)
- ✅ Actually running (not theoretical)
- ✅ Low resource usage (bash/grep, no AI)
- ✅ Completely passive (no human or AI attention needed)
- ✅ Hybrid thresholds capture sentiment & acknowledgment

**Trade-offs:**
- ⚠️ Vector DB grows indefinitely (no automatic pruning yet)
- ⚠️ Keyword detection is dumber than full AI classification

**Mitigations:**
- Log rotation can be added later when needed
- Weekly archival script can be built if daily consolidation needed

---

## Alternatives Considered

1. **Fix and run consciousness layers** — Rejected: Overkill for memory continuity problem
2. **Use session-memory-bridge.sh** — Rejected: Too complex (400+ lines)
3. **Direct DB writes (bypass log file)** — Rejected: Couples capture to DB, harder to debug
4. **Keep daily consolidation as primary** — Rejected: Loses data if context truncates before 3:30 AM
5. **Do nothing (current state)** — Rejected: Proxy discussion already lost, unacceptable

---

## Future Enhancements

- [ ] Automatic pruning of old vector entries
- [ ] Fine-tune importance model based on feedback
- [ ] Multi-category weighting (prioritize certain categories)
- [ ] Re-enable consciousness layers if needed for other use cases

---

## ADR Convention (Meta)

**This ADR demonstrates a lightweight documentation pattern:**

| Document | Purpose | Content |
|----------|---------|---------|
| **ADR** | Current state reference | Architecture, components, thresholds — what's true NOW |
| **Memory files** | Evolution narrative | How decisions were made, what was tried, what failed, what succeeded |
| **Links** | Bidirectional | ADR points to memory dates; memory files reference ADR |

**Why this pattern:**
- **ADRs stay lean** — Quick to read, easy to maintain
- **Evolution is searchable** — Full context in memory files, indexed by vector DB
- **No duplication** — Single source of truth for each type of information
- **Scales naturally** — New ADRs follow same pattern; evolution accumulates in dated files

**For future ADRs:** Follow this structure. Current state in ADR, evolution in `memory/YYYY-MM-DD.md`.

---

*See `memory/2026-02-05.md` for full evolution narrative including: initial implementation → long-running Franklin → hybrid threshold calibration*
