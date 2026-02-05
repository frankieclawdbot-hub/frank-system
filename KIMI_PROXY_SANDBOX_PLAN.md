# Kimi Proxy Testing - Sandbox Approach

**Objective:** Test proxy configuration for kimi/kimi-code Franklin spawning without risking main OpenClaw instance.

**Approach:** Separate workspace on same server (Option 2)

---

## Why This Approach

| Requirement | How Workspace Delivers |
|-------------|------------------------|
| Zero cost | Same VPS, just different directory |
| Isolated | Separate config, separate port |
| Recoverable | Delete sandbox/, start fresh |
| Observable | Direct file access, immediate debugging |
| Fast setup | Minutes, not hours |

---

## Architecture

```
Hostinger VPS
├── /root/clawd/              ← Main OpenClaw (production)
│   ├── .openclaw/openclaw.json  (port 18789)
│   └── [existing daemons running]
│
└── /root/clawd-sandbox/      ← Sandbox OpenClaw (testing)
    ├── .openclaw/openclaw.json  (port 18790)
    └── [isolated testing]
```

---

## Setup Steps

1. **Create sandbox directory**
   ```bash
   mkdir -p /root/clawd-sandbox
   cd /root/clawd-sandbox
   ```

2. **Copy OpenClaw config**
   ```bash
   cp -r /root/.openclaw /root/clawd-sandbox/
   ```

3. **Modify sandbox config**
   - Change gateway port: 18789 → 18790
   - Add proxy configuration for kimi/kimi-code
   - Keep other settings identical for comparison

4. **Test proxy setup**
   - Start sandbox OpenClaw on port 18790
   - Spawn Franklin with moonshot/kimi-k2.5
   - Spawn Franklin with kimi-code/kimi-for-coding
   - Document results

5. **Iterate**
   - If proxy fails: stop, modify config, restart
   - If proxy works: document exact config, apply to main

---

## Success Criteria

| Test | Expected Result |
|------|-----------------|
| moonshot/kimi-k2.5 Franklin | ✅ Spawns successfully |
| kimi-code/kimi-for-coding Franklin | ✅ Spawns successfully |
| haiku Franklin (baseline) | ✅ Spawns successfully |

---

## Rollback Plan

If sandbox testing breaks or gets corrupted:
```bash
rm -rf /root/clawd-sandbox/
# Main OpenClaw unaffected
```

---

## Integration Strategy

Once working config found:
1. Document exact proxy settings
2. Apply to `/root/.openclaw/openclaw.json`
3. Restart main OpenClaw
4. Test in production
5. Update MEMORY.md with working configuration

---

**Started:** 2026-02-05 19:50 UTC  
**Status:** In progress
