# ADR-022: Polling Reporter Daemon

## Status
✅ **IMPLEMENTED & STABILIZED** - Polling Reporter v1.0 operational

**Implementation Date:** 2026-02-05  
**Last Updated:** 2026-02-05  
**Root Cause Fix Applied:** 2026-02-05

## Context

The Clawdbot system spawns Franklin sub-agents to perform background tasks (Git backups, code reviews, architecture design). These tasks run asynchronously and can take minutes to hours. The main agent (Frank) needs to know when they complete to report results to the user.

### The Communication Problem

Without a back-channel:
- Frank spawns a Franklin
- Franklin works silently in background
- User asks "Where's my result?"
- Frank has no idea if task is running, stalled, or complete
- Manual investigation required (check logs, process lists)

A **polling-based reporting mechanism** was needed to:
- Periodically check status of all active Franklins
- Detect completions (success/failure)
- Alert Frank to new results
- Maintain audit trail of all background activity

## Decision

**Implement a Polling Reporter Daemon that runs continuous 10-second cycles to monitor all active Franklin sessions, detect completions, and queue results for the main agent to process.**

### Core Principles

1. **Continuous Polling**: Never stop checking while system is running
2. **Non-Intrusive**: Read-only monitoring, doesn't affect Franklin execution
3. **Persistent**: Survive temporary disruptions, resume automatically
4. **Observable**: Log all cycles and detections for debugging
5. **Decoupled**: Frank consumes results at own pace, no blocking

---

## Architecture

### 1.1 Components

```
┌─────────────────────────────────────────────────────────────┐
│                POLLING REPORTER DAEMON                      │
│                                                             │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │  Session    │    │   Detect    │    │    Queue    │     │
│  │   Query     │───→│ Completion  │───→│   Result    │     │
│  │ (clawdbot)  │    │  (State Δ)  │    │  (Alert)    │     │
│  └─────────────┘    └─────────────┘    └──────┬──────┘     │
│                                               │             │
│  ┌─────────────┐    ┌─────────────┐          │             │
│  │   Logger    │←───│   10s Loop  │          │             │
│  │  (Cycles)   │    │  (Sleep)    │          │             │
│  └─────────────┘    └─────────────┘          │             │
└───────────────────────────────────────────────┼─────────────┘
                                                │
                      ┌─────────────────────────┘
                      ↓
              ┌──────────────┐
              │ Frank (Main) │
              │  (Consumes   │
              │   Results)   │
              └──────────────┘
```

### 1.2 Files

| File | Purpose |
|------|---------|
| `/root/clawd/polling-reporter-daemon.sh` | Daemon control script (start/stop/status) |
| `/root/clawd/scripts/run-polling-logic.sh` | Core polling logic implementation |
| `/root/clawd/logs/polling-reporter-daemon.log` | Cycle execution logs |

---

## Implementation

### 2.1 Polling Cycle

```bash
Every 10 seconds:
  1. Query active sessions via `clawdbot sessions list`
  2. Parse session list for subagents (Franklins)
  3. Check registry for completed tasks
  4. Detect state changes:
     - Stalled (>30 min no update)
     - Blocked (waiting for resource)
     - Completed (finished, needs review)
     - Failed (error/timeout)
  5. Log metrics and status
  6. Update orchestrator with report
  7. Sleep 10 seconds
```

### 2.2 Detection Logic

| State | Detection Criteria | Action |
|-------|-------------------|--------|
| **Stalled** | No update >30 min | Log warning, add to alert queue |
| **Blocked** | Status = blocked/waiting | Log warning, trigger escalation |
| **Completed** | Status = completed, not reviewed | Add to review queue |
| **Failed** | Status = failed/timeout/error | Log error, add to alert queue |

### 2.3 Output Format

```
[2026-02-05T06:16:17Z] Reporter cycle complete: 
  4 sessions, 
  0 stalled, 
  0 blocked, 
  0 completed, 
  0 failed
```

---

## Chronic Failure & Root Cause Fix

### 3.1 The Problem

The Polling Reporter experienced **chronic silent failures**:
- Would run for hours then stop logging cycles
- Process remained alive (PID existed) but internal loop died
- No error logged, no crash detected
- Required manual restart to restore functionality

### 3.2 Root Cause Analysis

**Primary Issue:** The daemon script used `set -euo pipefail` (strict error handling) in the polling logic sub-script. Any command failure (e.g., `clawdbot sessions list` hanging, `jq` parse error) would immediately exit the script with non-zero status.

**Secondary Issue:** The daemon wrapper's background process was started with:
```bash
(
    trap "" SIGHUP SIGINT SIGTERM  # Ignore all signals!
    while true; do
        # polling logic
    done
) &
```

This `trap` line prevented the process from responding to `SIGTERM`, making it unkillable by the `stop` function and masking the real failure.

### 3.3 Fix Applied

**Fix 1:** Remove strict error handling from polling logic script
- Removed `set -euo pipefail`
- Added `|| true` to critical commands
- Ensures single failures don't crash entire daemon

**Fix 2:** Remove signal trap from daemon wrapper
- Removed `trap "" SIGHUP SIGINT SIGTERM`
- Allows clean shutdown via `kill SIGTERM`
- Enables proper process management

**Result:** Daemon now survives transient command failures and responds correctly to shutdown signals.

---

## Integration with Sentinel

The Polling Reporter is **monitored by the Sentinel Watchdog** (ADR-021):

| Check | Command |
|-------|---------|
| Health | `/root/clawd/polling-reporter-daemon.sh status \| grep -q 'RUNNING'` |
| Restart | `/root/clawd/polling-reporter-daemon.sh restart` |
| Interval | 10 seconds |

If the Polling Reporter fails, Sentinel detects within 10-20 seconds and auto-restarts it.

---

## Known Limitations

### 4.1 Detection Lag

There is a **10-30 second delay** between Franklin completion and Frank being notified:
- Polling cycle runs every 10 seconds
- May miss completions between cycles
- Additional delay if Frank is processing other messages

**Mitigation:** Acceptable for background tasks; real-time needs require different mechanism.

### 4.2 No Real-Time Push

The Polling Reporter is **pull-based**, not push-based. Frank must actively check for results or wait for the poller to announce.

**Future Enhancement:** Webhook or signal-based notification for true real-time.

### 4.3 Kimi Code Task Completion

Franklins using Kimi Code silently fall back to Flash (see ADR-021, Known Limitations). The Polling Reporter detects session completion but the model used may differ from what was requested.

**Impact:** Task completes but potentially on wrong model; cost implications.

---

## Testing

### 5.1 Verification Steps

1. Start daemon: `/root/clawd/polling-reporter-daemon.sh start`
2. Spawn test Franklin: `sessions_spawn{...}`
3. Monitor logs: `tail -f /root/clawd/logs/polling-reporter-daemon.log`
4. Verify cycle completes with session count increment
5. Wait for Franklin completion
6. Verify poller detects completion and alerts Frank

### 5.2 Current Status

```
✅ Daemon: RUNNING (PID: 1845341)
✅ Cycles: Completing every 10 seconds consistently
✅ Detection: Successfully identifying active sessions
✅ Recovery: Sentinel auto-restart verified
```

---

## References

- Daemon Script: `/root/clawd/polling-reporter-daemon.sh`
- Polling Logic: `/root/clawd/scripts/run-polling-logic.sh`
- Logs: `/root/clawd/logs/polling-reporter-daemon.log`
- Sentinel Monitoring: ADR-021
- Related: ADR-009 (Franklin Architecture)

---

*Last verified: 2026-02-05 - Polling Reporter stable, 10s cycles operational*
