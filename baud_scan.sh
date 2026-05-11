#!/bin/bash
# Comprehensive baud-rate scan of stock firmware

ROOT=/mnt/c/tftp/_stock_backup_20260501.bin-0.extracted
SQROOT=$ROOT/squashfs-root

echo "=========================================="
echo "1. All baud-rate-like decimal numbers in any binary or config"
echo "=========================================="
# Search in ALL binaries and config files for baud-rate strings
for f in $(find $SQROOT/opt/ch/ $SQROOT/etc/ $SQROOT/config/ -type f \( -name "*.so*" -o -name "*.xml" -o -name "*.cfg" -o -name "*.conf" -o -name "*.flag" -o -executable \) 2>/dev/null); do
  hits=$(strings "$f" 2>/dev/null | grep -wE '1200|2400|4800|9600|14400|19200|28800|38400|57600|76800|115200|230400|460800|921600' | sort -u | head -5)
  if [ -n "$hits" ]; then
    echo "--- $f ---"
    echo "$hits" | head -5
  fi
done

echo ""
echo "=========================================="
echo "2. Check for B<baud> termios constants in binaries (hex little-endian)"
echo "=========================================="
# B9600=0xd, B4800=0xc, B2400=0xb, B1200=0x9, B19200=0xe, B38400=0xf
# B57600=0x1001, B115200=0x1002, B230400=0x1003, B460800=0x1004, B500000=0x1005
# B921600=0x1007, B1500000=0x1008, B2000000=0x1009
echo "(Looking for cfsetospeed call sites — context only)"
for bin in $SQROOT/opt/ch/mainctrl $SQROOT/opt/ch/comm_server $SQROOT/opt/ch/libtools.so $SQROOT/opt/ch/media_server $SQROOT/opt/ch/web_server $SQROOT/opt/ch/comm_server; do
  if [ -f "$bin" ]; then
    name=$(basename "$bin")
    echo "--- $name ---"
    arm-linux-gnueabihf-objdump -d "$bin" 2>/dev/null | grep -B2 -A2 'cfsetospeed\|cfsetispeed' | head -20
  fi
done

echo ""
echo "=========================================="
echo "3. Bootargs / cmdline references in all binaries"
echo "=========================================="
for f in $(find $SQROOT/opt/ch/ -maxdepth 2 -type f -executable 2>/dev/null); do
  hits=$(strings "$f" 2>/dev/null | grep -iE 'console=tty|bootargs|cmdline|tty.*[0-9]{4,7}' | head -3)
  if [ -n "$hits" ]; then
    echo "--- $(basename $f) ---"
    echo "$hits"
  fi
done

echo ""
echo "=========================================="
echo "4. Any reference to specific tty device with speed settings in init scripts"
echo "=========================================="
grep -rE 'getty|stty|console|baudrate|baud.rate|setserial' $SQROOT/etc/ $SQROOT/opt/ch/*.sh 2>/dev/null | head -20

echo ""
echo "=========================================="
echo "5. Check the U-Boot partition for its console baud"
echo "=========================================="
# U-Boot is at offset 0x20000-0x40000 in the stock backup
UBOOT_FILE=$ROOT/_stock_backup_20260501.bin-0.extracted.uboot 2>/dev/null
# Try to extract U-Boot section
if [ ! -f "$UBOOT_FILE" ]; then
  dd if=/mnt/c/tftp/stock_backup_20260501.bin of=/tmp/uboot_section.bin bs=1 skip=131072 count=131072 2>/dev/null
  UBOOT_FILE=/tmp/uboot_section.bin
fi
if [ -f "$UBOOT_FILE" ]; then
  echo "U-Boot section size: $(stat -c %s $UBOOT_FILE)"
  echo "Strings with baud:"
  strings "$UBOOT_FILE" | grep -iE 'baud|console=|115200|921600|230400|460800|9600|38400|57600' | sort -u | head -20
  echo ""
  echo "All baud-like numbers found:"
  strings "$UBOOT_FILE" | grep -wE '9600|19200|38400|57600|115200|230400|460800|921600' | sort -u | head -20
fi

echo ""
echo "=========================================="
echo "6. Kernel image baud references"
echo "=========================================="
KERNEL_FILE=/mnt/c/tftp/stock_dts_work/kernel.bin
if [ -f "$KERNEL_FILE" ]; then
  echo "Kernel size: $(stat -c %s $KERNEL_FILE)"
  strings "$KERNEL_FILE" | grep -iE 'console=tty|baudrate|earlycon' | sort -u | head -10
fi

echo ""
echo "=========================================="
echo "7. Search ENTIRE stock filesystem for tty/baud strings"
echo "=========================================="
grep -rEho 'tty[A-Z]*[0-9]+,[0-9]+' $SQROOT 2>/dev/null | sort -u | head -20

echo ""
echo "=========================================="
echo "8. DTS — bootargs or chosen node baud"
echo "=========================================="
grep -E 'bootargs|console|baud|chosen' /mnt/c/tftp/stock_dts_work/stock.dts 2>/dev/null | head -20

echo ""
echo "=========================================="
echo "9. Python script: extract baud from cfsetispeed/cfsetospeed call context"
echo "=========================================="
# Look for what's loaded into r0 (after fd) before the cfsetospeed PLT call
for bin in $SQROOT/opt/ch/mainctrl $SQROOT/opt/ch/comm_server $SQROOT/opt/ch/libtools.so; do
  name=$(basename "$bin")
  echo "--- $name cfsetospeed call sites with r0 context ---"
  arm-linux-gnueabihf-objdump -d "$bin" 2>/dev/null | grep -B 6 'cfsetospeed' | head -40
  echo ""
done
