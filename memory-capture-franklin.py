#!/usr/bin/env python3
#
# memory-capture-franklin.py - Captures session outcomes to stream.log
#
# Usage: python3 memory-capture-franklin.py
# Called by background-indexer every 2-5 minutes
#

import sys
import os
import json
import hashlib
import subprocess
from datetime import datetime

WORKSPACE = "/root/clawd"
STREAM_FILE = os.path.join(WORKSPACE, "memory", "stream.log")
STATE_FILE = os.path.join(WORKSPACE, ".memory-capture-state")

def log(msg):
    print(f"[{datetime.now().strftime('%H:%M:%S')}] {msg}", file=sys.stderr)

def run_openclaw(*args):
    """Run openclaw CLI command"""
    try:
        result = subprocess.run(
            ["openclaw"] + list(args),
            capture_output=True,
            text=True,
            timeout=15
        )
        return result.returncode == 0, result.stdout, result.stderr
    except Exception as e:
        return False, "", str(e)

def get_recent_messages():
    """Get recent messages from main session"""
    # Get list of sessions first
    success, stdout, stderr = run_openclaw("sessions_list", "--limit", "5", "--format", "json")
    
    if not success:
        log(f"Failed to list sessions: {stderr}")
        return []
    
    try:
        data = json.loads(stdout)
        sessions = data.get("sessions", [])
        
        # Find main session
        main_session = None
        for s in sessions:
            if s.get("key") == "agent:main:main" or "main" in s.get("key", ""):
                main_session = s
                break
        
        if not main_session:
            log("Main session not found")
            return []
        
        # Get history for main session
        session_key = main_session.get("key")
        success, stdout, stderr = run_openclaw(
            "sessions_history", session_key, 
            "--limit", "10", 
            "--format", "json"
        )
        
        if not success:
            log(f"Failed to get history: {stderr}")
            return []
        
        data = json.loads(stdout)
        return data.get("messages", [])
        
    except Exception as e:
        log(f"Error parsing sessions: {e}")
        return []

def extract_text_content(msg):
    """Extract text from message content"""
    content = msg.get("content", [])
    if isinstance(content, list):
        texts = []
        for item in content:
            if isinstance(item, dict) and item.get("type") == "text":
                texts.append(item.get("text", ""))
        return " ".join(texts).strip()
    elif isinstance(content, str):
        return content.strip()
    return ""

def is_important(text):
    """Check if text contains important keywords"""
    keywords = [
        "decided", "decision", "determined", "choose", "selected", "committed",
        "discovered", "found", "realized", "learned", "insight", "identified",
        "implemented", "built", "created", "fixed", "solved", "completed",
        "issue", "problem", "bug", "error", "blocker", "blocked",
        "success", "succeeded", "working", "resolved", "achieved"
    ]
    text_lower = text.lower()
    return any(kw in text_lower for kw in keywords) and len(text) > 40

def get_category(text):
    """Determine category from text"""
    text_lower = text.lower()
    if any(kw in text_lower for kw in ["decided", "decision", "determined"]):
        return "decision"
    elif any(kw in text_lower for kw in ["discovered", "found", "realized", "insight"]):
        return "discovery"
    elif any(kw in text_lower for kw in ["implemented", "built", "created", "fixed"]):
        return "implementation"
    elif any(kw in text_lower for kw in ["issue", "problem", "bug", "error", "blocker"]):
        return "issue"
    elif any(kw in text_lower for kw in ["success", "succeeded", "resolved", "completed"]):
        return "success"
    return "outcome"

def get_hash(text):
    return hashlib.md5(text.encode()).hexdigest()[:16]

def already_captured(hash_val):
    if not os.path.exists(STREAM_FILE):
        return False
    try:
        with open(STREAM_FILE, 'r') as f:
            return f"hash:{hash_val}" in f.read()
    except:
        return False

def append_to_stream(text, category):
    hash_val = get_hash(text)
    
    if already_captured(hash_val):
        return False
    
    os.makedirs(os.path.dirname(STREAM_FILE), exist_ok=True)
    
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')
    
    with open(STREAM_FILE, 'a') as f:
        f.write(f"\n---\n")
        f.write(f"[{timestamp}] [{category}]\n")
        f.write(f"{text}\n")
        f.write(f"hash:{hash_val}\n")
    
    return True

def main():
    log("MemoryCapture Franklin starting...")
    
    messages = get_recent_messages()
    if not messages:
        log("No messages found")
        return
    
    log(f"Found {len(messages)} messages to analyze")
    
    captured = 0
    for msg in messages:
        text = extract_text_content(msg)
        if not text:
            continue
        
        if is_important(text):
            category = get_category(text)
            if append_to_stream(text, category):
                log(f"Captured: {category}")
                captured += 1
    
    log(f"Complete: captured {captured} entries")

if __name__ == "__main__":
    main()
