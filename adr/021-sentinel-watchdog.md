# ADR-021: Sentinel Watchdog Architecture

## Status
✅ **IMPLEMENTED** - Sentinel Watchdog v1.0 operational

**Implementation Date:** 2026-02-05  
**Last Updated:** 2026-02-05

## Context

The Clawdbot system relies on multiple critical background services:
- **Gateway**: Core API and orchestration
- **Polling Reporter**: Franklin status monitoring and completion reporting
- **Session Indexer**: Memory and vector search maintenance

These services can fail silently:
- Process exits unexpectedly (OOM, errors, killed)
- Logic hangs (infinite loops, blocked I/O)
- Resource exhaustion (file descriptors, memory)

Without monitoring, failures go undetected until a user notices missing functionality (e.g., "Why didn't my Franklin report back?").

### The Polling Reporter Failure

The immediate catalyst was chronic failure of the Polling Reporter Daemon:
- Would run for hours then stop logging cycles
- Process remained but internal loop died
- No automatic recovery mechanism
- Required manual restart investigation

A general-purpose watchdog was needed, not just a Polling Reporter fix.

## Decision

**Implement a Sentinel Watchdog service that monitors critical Clawdbot services via configurable health checks, performs automatic self-healing restarts on failure, and notifies the system of recovery actions.**

### Core Principles

1. **External Watchdog**: Sentinel runs outside the services it monitors
2. **Configuration-Driven**: Service definitions in JSON, not hardcoded
3. **Self-Healing**: Automatic restart on failure detection
4. **Observability**: All actions logged, notifications on critical events
5. **Non-Intrusive**: Health checks must not disrupt service operation

---

## Architecture

### 1.1 Components

```
┌─────────────────────────────────────────────────────────────┐
│                  SENTINEL WATCHDOG                          │
│                                                             │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │   Config    │    │   Monitor   │    │   Heal      │     │
│  │  (JSON)     │───→│  (Checks)   │───→│ (Restart)   │     │
│  └─────────────┘    └──────┬──────┘    └──────┬──────┘     │
│                            │                    │           │
│                            ↓                    ↓           │
│                      ┌─────────────┐    ┌─────────────┐     │
│                      │   Logger    │    │   Notify    │     │
│                      │  (Actions)  │    │ (Telegram)  │     │
│                      └─────────────┘    └─────────────┘     │
└────────────────────────────┬────────────────────────────────┘
                             │
         ┌───────────────────┼───────────────────┐
         │                   │                   │
         ↓                   ↓                   ↓
   ┌────────────┐     ┌────────────┐     ┌────────────┐
   │  Gateway   │     │   Polling  │     │   Other    │
   │            │     │  Reporter  │     │  Services  │
   └────────────┘     └────────────┘     └────────────┘
```

### 1.2 Files

| File | Purpose |
|------|---------|
| `/usr/local/bin/clawdbot-sentinel.sh` | Core monitoring and healing script |
| `/etc/clawdbot/sentinel.json` | Service configuration manifest |
| `/var/log/clawdbot-sentinel.log` | Action and status logs |

---

## Configuration

### 2.1 Service Definition

```json
{
  "version": "1.0",
  "services": [
    {
      "name": "service-name",
      "check_command": "command to verify health (exit 0 = healthy)",
      "restart_command": "command to restart service"
    }
  ]
}
```

### 2.2 Current Services

| Service | Check Command | Restart Command |
|---------|---------------|-----------------|
| `clawdbot-gateway` | `curl -s http://127.0.0.1:18789/status \| grep -q 'html'` | `clawdbot gateway restart` |
| `polling-reporter-daemon` | `/root/clawd/polling-reporter-daemon.sh status \| grep -q 'RUNNING'` | `/root/clawd/polling-reporter-daemon.sh restart` |

---

## Implementation

### 3.1 Monitoring Cycle

1. Read configuration from `/etc/clawdbot/sentinel.json`
2. For each service:
   - Execute `check_command`
   - If exit code ≠ 0: service is DOWN
   - Execute `restart_command`
   - Wait 10 seconds
   - Re-execute `check_command` to verify recovery
3. Log all actions to `/var/log/clawdbot-sentinel.log`

### 3.2 Error Handling

- **Config parse failure**: Exit with error, log FATAL
- **Check command failure**: Log FAILURE, attempt restart
- **Restart command failure**: Log ERROR
- **Post-restart check failure**: Log FAILURE

### 3.3 Notification (Future)

Telegram notifications on:
- Successful recovery: "✅ Service X restarted and healthy"
- Failed recovery: "🔥 Service X failed to recover after restart"
- Restart command failure: "⚠️ Failed to execute restart for X"

---

## Known Limitations

### 4.1 Gateway Restart

The `clawdbot gateway restart` command fails because it requires `systemctl --user` which is unavailable in the current environment. The Sentinel detects this as a restart failure but the Gateway usually auto-recovers via process supervision.

**Workaround:** Manual Gateway restart if needed, or implement alternative restart mechanism.

### 4.2 Kimi Code Franklin Spawning

Franklins requested with `model: "kimi-code"` silently fall back to Flash due to Gateway ignoring the User-Agent header configuration. This is a separate Gateway bug, not a Sentinel issue.

**Impact:** Sentinel cannot monitor Kimi Code API health directly. Monitors downstream services only.

---

## Future Enhancements

- [ ] Systemd timer or cron integration for periodic execution
- [ ] Telegram notification integration
- [ ] Metrics export (Prometheus/Grafana)
- [ ] Web dashboard for status visibility
- [ ] Health check caching to reduce API load
- [ ] Exponential backoff for restart attempts

---

## References

- Sentinel Script: `/usr/local/bin/clawdbot-sentinel.sh`
- Configuration: `/etc/clawdbot/sentinel.json`
- Logs: `/var/log/clawdbot-sentinel.log`
- Related: ADR-010 (Stability Sentinel for consciousness cascade)

---

*Last verified: 2026-02-05 - Sentinel operational, monitoring Gateway and Polling Reporter*
