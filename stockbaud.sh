#!/bin/bash
ROOT=/mnt/c/tftp/_stock_backup_20260501.bin-0.extracted/squashfs-root

echo "=== comm_server: all baud-ish numbers (decimal + hex constants) ==="
strings -d "$ROOT/opt/ch/comm_server" 2>/dev/null | grep -iE 'baudrate|^[BD][0-9]+$|baud.*rate|115200|57600|38400|19200|9600|4800|2400|1200|600|9c40|2580|1c20|960|0e10' | sort -u | head -40

echo ""
echo "=== comm_server: protocol mentions ==="
strings "$ROOT/opt/ch/comm_server" 2>/dev/null | grep -iE 'pelco|visca|protocol|tem.r|0x81|0x88' | sort -u | head -20

echo ""
echo "=== comm_server: /dev/tty references in context ==="
strings -n 6 "$ROOT/opt/ch/comm_server" 2>/dev/null | grep -B2 -A2 'ttyS\|ttyAMA' | head -50

echo ""
echo "=== Look for hex baud constants in comm_server (binary scan) ==="
xxd "$ROOT/opt/ch/comm_server" | grep -iE '0960|0e10|2580|9c40|1c20|c200' | head -10

echo ""
echo "=== Stock config XML file - any other PTZ-related fields ==="
grep -E 'PTZ|baud|Com|Protocol|Address' "$ROOT/opt/ch/config.default.mc800s.xml" | head -20
