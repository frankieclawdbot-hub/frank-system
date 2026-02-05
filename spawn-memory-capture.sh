#!/bin/bash
#
# spawn-memory-capture.sh - Spawn Franklin to capture session outcomes
#
# Called by background-indexer every 2-5 minutes
#

set -euo pipefail

WORKSPACE="${WORKSPACE:-/root/clawd}"
MARKER_FILE="$WORKSPACE/.capture-marker"

echo "[$(date '+%H:%M:%S')] Spawning MemoryCapture Franklin..."

# Spawn the Franklin with a simple task
openclaw agent --local --task "
You are the MemoryCapture Franklin. Do exactly this:

1. Use the sessions_history tool to get recent messages from session 'agent:main:main' (limit: 10)
2. For each message, if it contains important keywords (decided, discovered, implemented, fixed, issue, success) AND is longer than 40 characters:
   - Determine category (decision/discovery/implementation/issue/success)
   - Generate MD5 hash of the text (first 16 chars)
   - Append to /root/clawd/memory/stream.log in this format:

---
[timestamp] [category]
Full text
hash:md5hash

3. Only capture messages that don't already exist in stream.log (check for hash)
4. Report how many entries you captured

Keywords by category:
- decision: decided, decision, determined, choose, selected, committed
- discovery: discovered, found, realized, learned, insight, identified  
- implementation: implemented, built, created, fixed, solved, deployed
- issue: issue, problem, bug, error, blocker, blocked, broken, failed
- success: success, succeeded, working, resolved, achieved

Be concise. Capture only substantial outcomes, not every message." 2>&1 | tail -20

echo "[$(date '+%H:%M:%S')] Franklin capture complete"
