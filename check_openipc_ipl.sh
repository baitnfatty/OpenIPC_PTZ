#!/bin/bash
echo "=== Compare BOOT/IPL sections: stock vs OpenIPC ==="
echo ""
echo "--- Stock IPL strings (offset 0x0-0x20000) ---"
dd if=/mnt/c/tftp/stock_backup_20260501.bin of=/tmp/stock_ipl.bin bs=1 count=131072 2>/dev/null
strings /tmp/stock_ipl.bin | grep -iE 'anjvision|MC800S|autoupdate|SDMMC|update|sd.*card' | sort -u | head -10

echo ""
echo "--- OpenIPC IPL strings (offset 0x0-0x20000) ---"
dd if=/mnt/c/tftp/openipc-ssc338q-ultimate-16mb.bin of=/tmp/openipc_ipl.bin bs=1 count=131072 2>/dev/null
strings /tmp/openipc_ipl.bin | grep -iE 'anjvision|MC800S|autoupdate|SDMMC|update|sd.*card|usb|tftp|fastboot|reboot' | sort -u | head -20

echo ""
echo "--- OpenIPC U-Boot section (offset 0x20000-0x40000) ---"
dd if=/mnt/c/tftp/openipc-ssc338q-ultimate-16mb.bin of=/tmp/openipc_uboot.bin bs=1 skip=131072 count=131072 2>/dev/null
strings /tmp/openipc_uboot.bin | grep -iE 'autoupdate|MC800S|baudrate|bootcmd|tftp|loadfile|fatload|mmc|sdcard' | sort -u | head -20

echo ""
echo "--- Compare first 100 bytes of BOOT section (binary diff) ---"
echo "Stock first 64 bytes:"
xxd -l 64 /tmp/stock_ipl.bin
echo "OpenIPC first 64 bytes:"
xxd -l 64 /tmp/openipc_ipl.bin

echo ""
echo "--- Are IPLs identical? ---"
md5sum /tmp/stock_ipl.bin /tmp/openipc_ipl.bin
