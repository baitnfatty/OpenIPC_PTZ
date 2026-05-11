#!/bin/bash
echo "=== /sys/bus/usb/devices ==="
ls /sys/bus/usb/devices/ 2>&1 | head -20

echo ""
echo "=== Find CH341 by VID 1a86 ==="
for d in /sys/bus/usb/devices/*/idVendor; do
  v=$(cat "$d" 2>/dev/null)
  if [ "$v" = "1a86" ]; then
    dir=$(dirname "$d")
    echo "Found at $dir"
    echo "  idVendor:  $(cat $dir/idVendor 2>/dev/null)"
    echo "  idProduct: $(cat $dir/idProduct 2>/dev/null)"
    echo "  product:   $(cat $dir/product 2>/dev/null)"
  fi
done

echo ""
echo "=== /dev/bus/usb tree ==="
ls -la /dev/bus/usb/ 2>&1 | head -10
for d in /dev/bus/usb/*/; do
  ls -la "$d" 2>/dev/null
done

echo ""
echo "=== flashrom ch341a_spi probe (non-interactive sudo) ==="
sudo -n flashrom -p ch341a_spi 2>&1 | head -20
