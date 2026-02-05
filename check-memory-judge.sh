#!/bin/bash
# Quick status check

PID=$(cat /tmp/memory-judge.pid 2>/dev/null)
if [[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null; then
    echo "✅ MemoryJudge running (PID: $PID)"
    echo ""
    echo "Recent log:"
    tail -5 /tmp/memory-judge.log 2>/dev/null
    echo ""
    echo "Queue entries: $(wc -l < /root/clawd/memory/importance-queue.jsonl 2>/dev/null || echo 0)"
else
    echo "❌ Not running"
fi
