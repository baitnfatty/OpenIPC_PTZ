#!/bin/bash
ROOT=/mnt/c/tftp/_stock_backup_20260501.bin-0.extracted/squashfs-root

echo "=== mainctrl shared library deps ==="
readelf -d "$ROOT/opt/ch/mainctrl" 2>/dev/null | grep NEEDED

echo ""
echo "=== Find which lib exports gpio_init / GetResetGpioPort ==="
for lib in $(find $ROOT -name "*.so*" -type f 2>/dev/null); do
  if readelf -s "$lib" 2>/dev/null | grep -qE 'gpio_init|GetResetGpioPort|gpio_write|GetLedBrGpioPort'; then
    echo "*** FOUND IN: $lib"
    readelf -s "$lib" 2>/dev/null | grep -E 'gpio_init|GetResetGpioPort|gpio_write|GetLedBrGpioPort|gpio_export|gpio_unexport' | head -10
    echo ""
  fi
done

echo "=== Search for gpio_init in any binary ==="
grep -lr "GetResetGpioPort" "$ROOT" 2>/dev/null | head -10

echo ""
echo "=== motor PWM strings ==="
strings "$ROOT/opt/ch/mainctrl" 2>/dev/null | grep -iE 'pwm|step|motor|light' | sort -u | head -30
