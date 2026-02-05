# ADR-011-Update: Intelligent Memory Capture via Franklin Inference

**Date:** 2026-02-05 16:55 UTC  
**Status:** PLANNING — Blockers Identified  
**Author:** Tyson & Frank

---

## Problem Statement

Current keyword-based capture:
- ✅ Captures decisions, implementations, issues (action-oriented)
- ❌ Misses esoteric conversations, feelings, philosophical moments
- ❌ Rigid — can't adapt to conversation nuance

Attempted solution (Franklin-based capture):
- ❌ Failed: No CLI access to session history from spawned agents
- ❌ Failed: Rate limits (429 errors) on Franklin spawning
- ❌ Failed: Session context access issues

**Required:** Intelligent inference to determine importance, not just keyword matching.

---

## Target Architecture

```
┌─────────────────────────────────────────────────────────────┐
│              INTELLIGENT MEMORY CAPTURE                     │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  OpenClaw Session (conversation happens)                    │
│       ↓ (writes transcript)                                 │
│  /root/.openclaw/agents/main/sessions/*.jsonl              │
│       ↓ (file change detected)                              │
│  Background Indexer (bash daemon)                           │
│       ↓ (every 2-5 minutes, spawn)                          │
│  MemoryJudge Franklin (flash model)                         │
│       ↓ (uses sessions_history tool)                        │
│  Reads recent conversation                                  │
│       ↓ (AI inference)                                      │
│  Decides: Important / Not Important                         │
│       ↓ (if important)                                      │
│  Categorizes: decision / insight / feeling / philosophy     │
│       ↓ (writes)                                            │
│  Importance Queue (JSON file)                               │
│       ↓ (file change detected)                              │
│  Background Indexer (embeds)                                │
│       ↓                                                     │
│  Vector DB (searchable)                                     │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Required Components

### 1. MemoryJudge Franklin
**Purpose:** AI-based importance detection and categorization

**Inputs:**
- Recent session history (via `sessions_history` tool)
- Last processed timestamp (for incremental processing)

**Outputs:**
- JSON entries: `{text, category, importance_score, timestamp, hash}`
- Written to `/root/clawd/memory/importance-queue.jsonl`

**Model:** flash (google/gemini-flash-latest)
- Fast enough for background processing
- Cheap enough to run every 2-5 minutes
- Smart enough for nuance detection

**Logic:**
```
Read recent messages → 
For each message:
  - Is this substantive? (>50 chars, not just "okay")
  - Is this meaningful? (decision, insight, feeling, philosophy, learning)
  - What category? (decision, discovery, implementation, issue, feeling, philosophy)
  - Importance score: 1-10
  
If importance >= 6:
  Write to queue with full context
```

### 2. Modified Background Indexer
**Changes:**
- Watch for `importance-queue.jsonl` changes
- Embed entries from queue (not raw sessions)
- Deduplication via hash
- Clean up processed entries

### 3. Queue File Format
```jsonl
{"timestamp": "2026-02-05T16:55:00Z", "category": "philosophy", "importance": 8, "text": "I'm excited about what we're building...", "hash": "abc123", "source": "session:xyz.jsonl"}
{"timestamp": "2026-02-05T16:56:00Z", "category": "decision", "importance": 9, "text": "We decided to use Franklin inference...", "hash": "def456", "source": "session:xyz.jsonl"}
```

---

## Current Blockers

| Blocker | Impact | Potential Solutions |
|---------|--------|---------------------|
| **1. Franklin Session Access** | Spawned Franklins can't access parent session history via CLI | A) Use `sessions_history` tool within Franklin (if available)<br>B) Pass recent transcript content to Franklin via stdin/file<br>C) Give Franklin session key via environment variable |
| **2. Rate Limits (429)** | Gemini Flash rate limiting on spawn | A) Add exponential backoff between spawns<br>B) Use local model (ollama/Llama 3.2)<br>C) Batch processing (run every 10 min instead of 2 min)<br>D) Use kimi-code model instead of flash |
| **3. Franklin Spawning Reliability** | Spawns sometimes fail or hang | A) Add spawn timeout and retry logic<br>B) Use `sessions_spawn` with explicit timeout<br>C) Health check + auto-restart for capture subsystem<br>D) Fallback to keyword-based if Franklin fails 3x |
| **4. Context Window in Franklin** | Long sessions exceed Franklin context | A) Only pass last N messages (e.g., last 20)<br>B) Pass messages since last capture timestamp<br>C) Truncate long messages before sending to Franklin |
| **5. Cost** | Running Franklin every 2-5 min adds up | A) Batch processing (every 10 min)<br>B) Only spawn if session has new content<br>C) Use local model (ollama)<br>D) Keyword pre-filter (only Franklin-process messages with *some* signal) |

---

## Recommended Approach

### Phase 1: Fix Session Access (Immediate)
**Test:** Can a spawned Franklin use `sessions_history` tool successfully?

```bash
# Test spawn with session access
openclaw sessions_spawn --task "
Use the sessions_history tool to get the last 5 messages from session 'agent:main:main'.
Report back the message count and first message timestamp.
" --model flash --timeout 30
```

**If works:** Proceed to Phase 2  
**If fails:** Pass transcript content via file instead

### Phase 2: Simple Franklin Implementation
**Goal:** Basic importance detection working

1. Modify background-indexer to spawn Franklin every 5 minutes
2. Franklin reads recent session content
3. Franklin writes important entries to `importance-queue.jsonl`
4. Indexer embeds from queue

**Model:** flash (google/gemini-flash-latest) — cheap, fast  
**Frequency:** Every 5 minutes (not 2 min — reduces rate limits)  
**Fallback:** If Franklin fails 3x in a row, fall back to keyword-based

### Phase 3: Hardening
**Goal:** Production reliability

1. Add exponential backoff for spawn retries
2. Add health checks
3. Add cost monitoring
4. Optimize frequency based on actual usage
5. Consider local model (ollama) for zero-cost operation

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Franklin consistently fails | Fallback to keyword-based (already implemented) |
| Cost too high | Switch to local model (ollama/Llama 3.2) |
| Rate limits persist | Reduce frequency to 10 min, add batching |
| Session access never works | Pass transcript via file (simpler architecture) |
| AI makes bad importance judgments | Human feedback loop — you can flag false positives/negatives |

---

## Success Criteria

**Minimum Viable:**
- [ ] Franklin can access session history (or workaround implemented)
- [ ] Franklin spawns reliably (90%+ success rate)
- [ ] Captures 80% of important moments (decisions, insights, feelings)
- [ ] False positive rate < 30% (don't capture "okay", "thanks", etc.)

**Production Ready:**
- [ ] 99%+ spawn reliability
- [ ] Rate limit handling (no 429s)
- [ ] Automatic fallback to keyword-based
- [ ] Cost <$0.50/day for capture

---

## Decision

**Proceed with Phase 1:** Test if Franklin can access session history via `sessions_history` tool.

**If yes:** Build Franklin-based intelligent capture.  
**If no:** Implement file-passing workaround (background indexer writes recent transcript to file, Franklin reads and judges).

**Timeline:**
- Phase 1 test: 5 minutes
- Phase 2 implementation: 1 hour
- Phase 3 hardening: This week

---

## Blocker Resolution: Immediate Action Required

**Test:** Can spawned Franklin access session history?

I will spawn a test Franklin now to verify session access. This determines architecture path.
