#!/bin/bash
ROOT=/mnt/c/tftp/_stock_backup_20260501.bin-0.extracted/squashfs-root

echo "=== mc800s config ==="
cat "$ROOT/opt/ch/config.default.mc800s.xml" 2>/dev/null | head -200

echo ""
echo "=== other config files in opt/ch ==="
ls "$ROOT/opt/ch/" | grep -iE 'config|xml|ptz|baud|rate' | head -20

echo ""
echo "=== Search all xml files for baudrate ==="
grep -riE 'baud|9600|4800|19200|38400|2400|115200|57600|protocol' "$ROOT/opt/ch/" --include='*.xml' 2>/dev/null | head -30

echo ""
echo "=== Strings that look like config keys in comm_server ==="
strings "$ROOT/opt/ch/comm_server" | grep -iE 'baud|protocol|VISCA|pelco|address' | sort -u | head -40
