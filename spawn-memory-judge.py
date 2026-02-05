#!/usr/bin/env python3
#
# spawn-memory-judge.py - Spawn Franklin via OpenClaw Gateway API
#

import sys
import json
import subprocess
import os
import time

GATEWAY_URL = "http://localhost:18789"
GATEWAY_TOKEN = "f2af82fa15a646da131431324695ee996c822cb569655641"

def spawn_franklin(chunk_file, queue_file):
    """Spawn a MemoryJudge Franklin via gateway API"""
    
    task = f"""You are the MemoryJudge. Review conversation messages and identify important moments.

Read: {chunk_file} (JSON array of messages)

For each message, determine:
1. Is it substantive? (>50 chars, not just 'okay', 'thanks', etc.)
2. Is it meaningful? Categories: decision, discovery, implementation, issue, success, feeling, philosophy
3. Importance: 1-10 (10 = critical, 1 = trivial)

Write ONLY important messages (importance >= 6) to: {queue_file}

Format (one JSON object per line):
{{"timestamp":"ISO8601","category":"decision|discovery|implementation|issue|success|feeling|philosophy","importance":8,"text":"message text","hash":"md5-hash","source":"franklin-judgment"}}

Be selective. Capture moments that matter."""

    # Try using openclaw agent command
    try:
        result = subprocess.run(
            ["openclaw", "agent", "--task", task, "--model", "haiku"],
            capture_output=True,
            text=True,
            timeout=60
        )
        
        if result.returncode == 0:
            return True, "Franklin completed"
        else:
            return False, f"Agent failed: {result.stderr}"
    except Exception as e:
        return False, str(e)

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: spawn-memory-judge.py <chunk_file> <queue_file>")
        sys.exit(1)
    
    chunk_file = sys.argv[1]
    queue_file = sys.argv[2]
    
    success, message = spawn_franklin(chunk_file, queue_file)
    print(message)
    sys.exit(0 if success else 1)
