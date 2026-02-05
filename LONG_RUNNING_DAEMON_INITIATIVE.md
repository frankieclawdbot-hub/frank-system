# Long-Running Daemon Initiative

**Status:** 📋 Planning Phase  
**Initiated:** 2026-02-05 18:45 UTC  
**Driver:** Tyson (via observation of rate limiting issues)

**Evolution History:** See `memory/2026-02-05.md` (search: "long-running daemon initiative")

---

## Problem Statement

Current systems spawn Franklins (subagents) repeatedly for continuous tasks:
- **Polling Reporter:** Spawns per status check
- **Background Indexer:** Cron triggers + spawn
- **Consciousness Layers:** 8 separate spawns (if enabled)

**Result:** 566+ Franklin spawns, 1667+ tool calls, Google Flash rate limits hit

**Root Cause:** Spawn-on-demand pattern creates exponential API usage

---

## Solution Pattern

**MemoryJudge Model:** Spawn ONCE, run continuously

```
Before:          After:
Task → Spawn     Startup → Spawn
Work → Die       While true:
Task → Spawn       Wait for work
Work → Die         Process
...                Sleep
                   Repeat
```

**Key Components:**
1. **Long-running daemon** (bash script with `while true`)
2. **Work queue** (file-based IPC like `/tmp/system-inbox/`)
3. **Same work logic** (just don't exit after task)
4. **Graceful shutdown** (signal handling)

---

## Systems to Convert

- [ ] **Priority 1: Polling Reporter** — Spawn per check → Long-running with schedule
- [ ] **Priority 2: Background Indexer** — Cron + spawn → File watcher daemon
- [ ] **Priority 3: Consciousness Layers** — 8 separate spawns → 1 orchestrator daemon
- [ ] **Priority 4: Heartbeat Checks** — Spawn per check → Long-running with timer
- [ ] **Priority 5: Rate Limit Manager** — Already daemon? → Verify/optimize if needed

---

## Implementation Template

```bash
#!/bin/bash
# long-running-<system>.sh

DAEMON_NAME="<system>-daemon"
INBOX="/tmp/<system>-inbox"
QUEUE="/root/clawd/<system>-queue.jsonl"
LOG="/tmp/<system>-daemon.log"
PID_FILE="/tmp/<system>-daemon.pid"

# Config
WORK_INTERVAL="<seconds>"

daemon_main() {
    log_info "Starting $DAEMON_NAME (PID: $$)"
    echo $$ > "$PID_FILE"
    
    while [[ "$shutdown_requested" == "false" ]]; do
        # Check for work
        if [[ -f "$INBOX"/task-*.json ]]; then
            process_work
        fi
        
        # Or check on interval
        sleep "$WORK_INTERVAL"
    done
}

process_work() {
    # Same logic as before, just don't exit
    for task in "$INBOX"/task-*.json; do
        [[ -f "$task" ]] || continue
        
        # Do the work
        result=$(do_work "$task")
        
        # Write result
        echo "$result" >> "$QUEUE"
        
        # Clean up
        rm -f "$task"
    done
}

# Signal handling
handle_shutdown() {
    shutdown_requested=true
}
trap 'handle_shutdown' TERM INT

# Start
daemon_main
```

---

## Success Metrics

| Metric | Before | Target | Measurement |
|--------|--------|--------|-------------|
| Franklin spawns/day | 566+ | < 10 | `grep -c "spawn" logs/` |
| API calls/day | 1667+ | < 100 | Session JSONL analysis |
| Rate limit hits | Daily | Zero | Google error logs |
| Resource usage | High | Low | `ps aux` monitoring |

---

## Phase 1: Polling Reporter (Priority 1)

**Current:** Spawns Franklin every X minutes for status check  
**Target:** Long-running daemon, checks on timer, no spawn

**Phase 1 Tasks:**

- [ ] Analyze current `polling-reporter.sh` spawn logic
- [ ] Create `polling-reporter-daemon.sh` with `while true` loop
- [ ] Replace `sessions_spawn` calls with direct bash functions
- [ ] Implement status file output (JSON format)
- [ ] Add signal handling for graceful shutdown
- [ ] Create `polling-reporter-controller.sh` (start/stop/status)
- [ ] Test daemon startup and shutdown
- [ ] Verify status file updates correctly
- [ ] Monitor API call reduction
- [ ] Update documentation

**Estimated effort:** 2-3 hours  
**Risk:** Low (read-only monitoring)

---

## Phase 2: Background Indexer (Priority 2)

**Current:** Cron triggers script that spawns Franklin  
**Target:** File watcher daemon (like MemoryJudge)

**Implementation sketch:**
1. Merge indexer logic into daemon
2. Watch `/root/.openclaw/agents/main/sessions/` for changes
3. Process inline (no spawn)
4. Use existing `memory-embed.py` for vectorization

**Estimated effort:** 3-4 hours  
**Risk:** Medium (touches core memory system)

---

## Phase 3: Consciousness Layers (Priority 3)

**Current:** 8 separate layer scripts, each spawns independently  
**Target:** Single orchestrator daemon with 8 worker threads/processes

**Implementation sketch:**
1. Create `consciousness-orchestrator.sh`
2. Each layer runs as function, not separate spawn
3. Named pipes for inter-layer communication
4. Accumulator pattern (already designed in ADR-009)

**Estimated effort:** 6-8 hours  
**Risk:** High (complex system, currently disabled)

---

## Decision: Scope for Now

**Phase 1 only (Polling Reporter):**
- ✅ Addresses immediate rate limiting
- ✅ Low risk
- ✅ Quick win
- ✅ Pattern proof-of-concept

**Phases 2-3 deferred:**
- Background indexer working well enough
- Consciousness layers already disabled
- Focus on stability over optimization

**Revisit when:**
- Rate limits persist after Phase 1
- Background indexer causes issues
- Consciousness layers re-enabled

---

## Files to Create

- [ ] `polling-reporter-daemon.sh` — Long-running status checker
- [ ] `polling-reporter-controller.sh` — Start/stop/status commands
- [ ] `docs/polling-reporter-migration.md` — Implementation notes

---

## References

- **MemoryJudge Pattern:** `memory-judge-franklin.sh` (working example)
- **Rate Limit Context:** `memory/2026-02-05.md#rate-limit-analysis`
- **Session Analysis:** `/root/.openclaw/agents/main/sessions/dc55f2cc*.jsonl`

---

*Last Updated: 2026-02-05 18:45 UTC - Initiative created, Phase 1 scoped*
