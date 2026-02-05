#!/bin/bash
#
# memory-status.sh - Check continuity system status
#

echo "═══════════════════════════════════════════════════════════"
echo "       Memory Continuity System Status"
echo "═══════════════════════════════════════════════════════════"
echo ""

# Check background indexer
echo "🔄 Background Indexer:"
if /root/clawd/background-indexer.sh --status 2>&1 | grep -q "RUNNING"; then
    echo "  ✅ Running"
else
    echo "  ❌ Not running"
fi
echo ""

# Check memory stream
echo "📝 Memory Stream:"
if [[ -f /tmp/memory-stream.pid ]] && kill -0 $(cat /tmp/memory-stream.pid) 2>/dev/null; then
    echo "  ✅ Running (PID: $(cat /tmp/memory-stream.pid))"
else
    echo "  ❌ Not running"
fi
echo ""

# Check stream file
echo "📄 Stream File:"
if [[ -f /root/clawd/memory/stream.log ]]; then
    local entries=$(grep -c "^---$" /root/clawd/memory/stream.log 2>/dev/null || echo 0)
    local size=$(stat -c%s /root/clawd/memory/stream.log 2>/dev/null | numfmt --to=iec 2>/dev/null || stat -f%z /root/clawd/memory/stream.log 2>/dev/null | numfmt --to=iec 2>/dev/null || echo "unknown")
    echo "  ✅ Exists"
    echo "  📊 Entries: $entries"
    echo "  📦 Size: $size"
else
    echo "  ❌ Not created yet"
fi
echo ""

# Check consciousness layers (should be disabled)
echo "🧠 Consciousness Layers:"
if ps aux | grep -E "(sensory|emotional|cognitive|somatic).sh" | grep -v grep > /dev/null; then
    echo "  ⚠️  Some layers running (should be disabled)"
else
    echo "  ✅ Disabled (as intended)"
fi
echo ""

# Check vector DB
echo "🔍 Vector Database:"
if [[ -f /root/clawd/lancedb/memory.db ]]; then
    local db_size=$(stat -c%s /root/clawd/lancedb/memory.db 2>/dev/null | numfmt --to=iec 2>/dev/null || stat -f%z /root/clawd/lancedb/memory.db 2>/dev/null | numfmt --to=iec 2>/dev/null || echo "unknown")
    echo "  ✅ Exists"
    echo "  📦 Size: $db_size"
else
    echo "  ⚠️  Not found"
fi
echo ""

echo "═══════════════════════════════════════════════════════════"
echo "Quick commands:"
echo "  memory-stream.sh --test    # Test capture"
echo "  memory-stream.sh --stop    # Stop capture"
echo "  background-indexer.sh --stop  # Stop indexer"
echo "  memory-search.sh <query>   # Search memory"
echo "═══════════════════════════════════════════════════════════"
