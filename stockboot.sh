#!/bin/bash
ROOT=/mnt/c/tftp/_stock_backup_20260501.bin-0.extracted/squashfs-root

echo "=== rcS init script ==="
cat "$ROOT/etc/init.d/rcS" 2>/dev/null | head -100

echo ""
echo "=== rcS.default ==="
cat "$ROOT/opt/ch/rcS.default" 2>/dev/null | head -100

echo ""
echo "=== loadko script ==="
cat "$ROOT/opt/ch/loadko" 2>/dev/null | head -50

echo ""
echo "=== profile ==="
cat "$ROOT/opt/ch/profile" 2>/dev/null | head -30

echo ""
echo "=== Search for af.flag and af-related strings in comm_server ==="
strings "$ROOT/opt/ch/comm_server" 2>/dev/null | grep -iE 'af.*flag|af.*data|focus|noaj|TTL|tem.r|54.65|0x54' | sort -u | head -20

echo ""
echo "=== Anything in /init or startup ==="
ls "$ROOT/" | head -20
test -f "$ROOT/init" && cat "$ROOT/init"
test -f "$ROOT/linuxrc" && file "$ROOT/linuxrc"
