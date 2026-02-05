#!/bin/bash
#
# ADR-011-Update-2: Long-Running MemoryJudge Franklin Daemon
#
# New Approach: Spawn once, run continuously, wait for work
#

## Concept

Instead of spawning a Franklin for every judgment batch, spawn ONE Franklin at system startup that runs continuously:

```
System Startup
    ↓
Spawn MemoryJudge Franklin (daemon mode)
    ↓
Franklin runs wait loop:
    while true:
        - Check /tmp/memory-inbox/ for chunk files
        - If chunk found:
            - Read JSON messages
            - Judge importance/category
            - Write important entries to queue
            - Delete chunk file
        - Sleep 5 seconds
    ↓
Background indexer (when new content detected):
    - Extract messages to chunk file
    - Move chunk to /tmp/memory-inbox/
    ↓
Franklin (already running):
    - Immediately processes chunk
    - No spawn overhead
```

## Advantages

1. **No spawning overhead** — Franklin already running
2. **No rate limits** — Not constantly spawning new sessions
3. **Maintains context** — Can learn from previous judgments
4. **Fast response** — No wait for spawn + initialization
5. **Simple IPC** — Just file-based communication

## Implementation

### 1. MemoryJudge Franklin Script

`/root/clawd/memory-judge-franklin.sh`:
```bash
#!/bin/bash
# MemoryJudge Franklin - Long-running daemon

INBOX="/tmp/memory-inbox"
QUEUE="/root/clawd/memory/importance-queue.jsonl"
LOG="/tmp/memory-judge.log"

mkdir -p "$INBOX"

echo "[$$] MemoryJudge Franklin started" >> "$LOG"

while true; do
    # Check for chunks
    for chunk in "$INBOX"/chunk-*.json; do
        [[ -f "$chunk" ]] || continue
        
        echo "[$$] Processing: $(basename "$chunk")" >> "$LOG"
        
        # Read and judge messages
        jq -c '.[]' "$chunk" | while read msg; do
            text=$(echo "$msg" | jq -r '.text // empty')
            [[ ${#text} -lt 50 ]] && continue
            
            # AI judgment happens here
            # For now, use simple heuristics
            # In full version, this would call model API
            
            importance=7
            category="outcome"
            
            # Write to queue
            hash=$(echo "$text" | md5sum | head -c 16)
            ts=$(date -Iseconds)
            echo "{\"timestamp\":\"$ts\",\"category\":\"$category\",\"importance\":$importance,\"text\":$(echo "$text" | jq -Rs .),\"hash\":\"$hash\",\"source\":\"memory-judge\"}" >> "$QUEUE"
        done
        
        # Remove processed chunk
        rm -f "$chunk"
        echo "[$$] Processed: $(basename "$chunk")" >> "$LOG"
    done
    
    sleep 5
done
```

### 2. Startup Integration

Add to sleep protocol or startup:
```bash
# Start MemoryJudge Franklin if not running
if ! pgrep -f "memory-judge-franklin" > /dev/null; then
    nohup /root/clawd/memory-judge-franklin.sh > /dev/null 2>&1 &
fi
```

### 3. Modified Background Indexer

Instead of spawning Franklin, just write chunk to inbox:
```bash
# In background-indexer-v2.sh:
# OLD: spawn_franklin "$chunk_file" "$QUEUE_FILE"
# NEW:
mv "$chunk_file" "$INBOX/"
# Franklin (already running) will pick it up
```

## Key Question

**Can a Franklin actually run a continuous loop?**

Options:
1. **Bash script Franklin** — Can definitely run `while true` loop
2. **Agent-based Franklin** — Depends if agent tool session stays open
3. **Hybrid** — Spawn bash script that runs loop, not agent turn

## Recommended: Bash Script Franklin

Spawn a bash script (not an agent turn) that runs the wait loop:

```bash
openclaw agent --task "Run /root/clawd/memory-judge-franklin.sh and keep it running" --model haiku
```

Or even simpler: Just run the script directly via background indexer startup:

```bash
# In background-indexer startup:
nohup bash -c 'while true; do /root/clawd/judge-chunks.sh; sleep 5; done' &
```

## Benefits Over Per-Batch Spawning

| Aspect | Per-Batch Spawn | Long-Running Franklin |
|--------|-----------------|----------------------|
| Spawn overhead | High (every 5 min) | Once at startup |
| Rate limits | Risk of 429s | No risk |
| Response time | 5-10 seconds | Instant (file already there) |
| Context retention | None | Can learn patterns |
| Complexity | Higher | Lower |
| Reliability | Lower (spawn failures) | Higher (just a loop) |

## Decision

**Recommended:** Implement long-running bash script Franklin.

Simple, reliable, fast. Just a continuous loop watching for chunks.

## Implementation Plan

1. Create `memory-judge-franklin.sh` (wait loop)
2. Modify background indexer to write chunks to inbox
3. Start Franklin at system boot
4. Monitor via log file

## Status

**READY TO IMPLEMENT**

This solves all the spawning issues elegantly.
