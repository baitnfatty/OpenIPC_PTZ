#!/bin/bash
BIN=/mnt/c/tftp/_stock_backup_20260501.bin-0.extracted/squashfs-root/opt/ch/mainctrl

echo "=== file info ==="
file "$BIN"

echo ""
echo "=== readelf summary ==="
readelf -h "$BIN" 2>/dev/null | head -15

echo ""
echo "=== Symbols (if present) ==="
readelf -s "$BIN" 2>/dev/null | grep -iE 'gpio_init|GetResetGpioPort|GetLedBrGpioPort|gpio_write|gpiopwm|ttl|ptz_control' | head -30

echo ""
echo "=== Strings: gpio commands with offsets ==="
strings -td "$BIN" | grep -E '/sys/class/gpio/gpio[0-9]+/(value|direction)|/sys/class/gpio/(export|unexport)|gpio%d' | head -30

echo ""
echo "=== Strings: AEBELL context ==="
strings -td "$BIN" | grep -iE 'AEBELL|AE.*BELL|au.*expo' | head -20

echo ""
echo "=== Strings: ioctl-related ==="
strings -td "$BIN" | grep -iE 'ioctl|IOCTL|gpiopwm|reset.*port|PWM|0x40|0x80' | head -30

echo ""
echo "=== Bytes near gpiopwm offset ==="
GPIOPWM_OFFSET=$(strings -td "$BIN" | grep -E '/dev/gpiopwm$' | head -1 | awk '{print $1}')
echo "gpiopwm string at offset: $GPIOPWM_OFFSET"

echo ""
echo "=== Strings: PTZ/HK32F/lens/AF related ==="
strings "$BIN" | grep -iE 'HK32|hk32|lens|af.flag|af_data|af_init|ptz.*reset|UART2|uart2' | sort -u | head -30

echo ""
echo "=== Disassemble GetResetGpioPort if present ==="
objdump -d "$BIN" 2>/dev/null | awk '/<GetResetGpioPort>:/{flag=1} flag{print; if(/^$/)exit}' | head -50

echo ""
echo "=== Disassemble gpio_init if present ==="
objdump -d "$BIN" 2>/dev/null | awk '/<gpio_init>:/{flag=1} flag{print; if(/^$/)exit}' | head -80

echo ""
echo "=== ioctl call sites in disassembly ==="
objdump -d "$BIN" 2>/dev/null | grep -B1 -A2 'bl.*<ioctl' | head -40
