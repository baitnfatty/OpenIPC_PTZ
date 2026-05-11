#!/bin/bash
LIB=/mnt/c/tftp/_stock_backup_20260501.bin-0.extracted/squashfs-root/opt/ch/libtools.so

echo "=== GetResetGpioPort disassembly ==="
objdump -d "$LIB" 2>/dev/null | awk '/<GetResetGpioPort>:/{flag=1} flag{print; if(/^$/ && NR>1)exit}' | head -50

echo ""
echo "=== GetLedBrGpioPort disassembly ==="
objdump -d "$LIB" 2>/dev/null | awk '/<GetLedBrGpioPort>:/{flag=1} flag{print; if(/^$/ && NR>1)exit}' | head -40

echo ""
echo "=== gpio_init disassembly (first 100 lines) ==="
objdump -d "$LIB" 2>/dev/null | awk '/<gpio_init>:/{flag=1} flag{print; if(/^$/ && NR>1)exit}' | head -100

echo ""
echo "=== gpio_write disassembly ==="
objdump -d "$LIB" 2>/dev/null | awk '/<gpio_write>:/{flag=1} flag{print; if(/^$/ && NR>1)exit}' | head -30

echo ""
echo "=== libtools.so strings (gpio/lens/reset/ttl/AF) ==="
strings -td "$LIB" 2>/dev/null | grep -iE 'gpio[0-9]+|reset|ttl|/dev/|lens|af.flag|af_data|focus' | sort -u | head -40

echo ""
echo "=== libtools function exports ==="
readelf -s "$LIB" 2>/dev/null | grep -E 'GLOBAL.*FUNC' | grep -v ' UND ' | head -50
