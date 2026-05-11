#!/bin/bash
ROOT=/mnt/c/tftp/_stock_backup_20260501.bin-0.extracted/squashfs-root/opt/ch
for f in comm_server media_server hik_server ex_server ac18pro_server mainctrl; do
  if [ -f "$ROOT/$f" ]; then
    echo "=== $f ==="
    strings "$ROOT/$f" 2>/dev/null | grep -iE 'ttyAMA|ttyS[0-9]|VISCA|baud|cfset.speed|/dev/tty|B9600|B4800|B2400|B19200|B38400|B57600|B115200' | sort -u | head -40
    echo ""
  fi
done

echo "=== rcS / init scripts ==="
find /mnt/c/tftp/_stock_backup_20260501.bin-0.extracted/squashfs-root/ -maxdepth 4 -name "rcS*" -type f 2>/dev/null
echo ""
echo "=== Find any 'stty' invocations in scripts ==="
grep -rE 'stty|9600|4800|19200|baud' /mnt/c/tftp/_stock_backup_20260501.bin-0.extracted/squashfs-root/etc/ /mnt/c/tftp/_stock_backup_20260501.bin-0.extracted/squashfs-root/opt/ch/*.sh 2>/dev/null | head -20
