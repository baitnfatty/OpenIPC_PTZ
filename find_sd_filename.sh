#!/bin/bash
# Find the exact SD card update filename pattern

# Re-extract IPL section
dd if=/mnt/c/tftp/stock_backup_20260501.bin of=/tmp/ipl.bin bs=1 count=131072 2>/dev/null

echo "=== All strings in IPL containing autoupdate / MC800S / sd / mmc ==="
strings /tmp/ipl.bin | grep -iE 'autoupdate|MC800S|update|/sd|mmc|/mnt|fat32|tftp|recovery' | sort -u

echo ""
echo "=== Bytes around MC800S2_V0 (with context) ==="
offset=$(strings -td /tmp/ipl.bin | grep -E 'MC800S2_V0|anjvision_autoupdate' | head -1 | awk '{print $1}')
if [ -n "$offset" ]; then
  echo "Found at offset: $offset"
  echo "256 bytes before + 256 after:"
  start=$((offset - 256))
  if [ $start -lt 0 ]; then start=0; fi
  dd if=/tmp/ipl.bin bs=1 skip=$start count=512 2>/dev/null | xxd
fi

echo ""
echo "=== Search SYSTEM partition for SD card update strings ==="
ROOT=/mnt/c/tftp/_stock_backup_20260501.bin-0.extracted/squashfs-root
grep -rEh 'MC800S2_V0|anjvision_autoupdate|sd.*update|sd.*upgrade|/mnt/mmc.*upgrade|update_image|firmware\.bin|burn.*ipl|burn.*flash' "$ROOT" 2>/dev/null | sort -u | head -30

echo ""
echo "=== Search U-Boot env section for autoupdate ==="
dd if=/mnt/c/tftp/stock_backup_20260501.bin of=/tmp/uboot.bin bs=1 skip=131072 count=131072 2>/dev/null
strings /tmp/uboot.bin | grep -iE 'autoupdate|MC800S|update|recovery|sd|mmc|tftp' | sort -u | head -30
