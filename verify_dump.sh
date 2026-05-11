#!/bin/bash
DUMP=/mnt/c/tftp/openipcbkup.bin
OPENIPC_REF=/mnt/c/tftp/openipc-ssc338q-ultimate-16mb.bin

echo "=== File info ==="
ls -la "$DUMP"
echo "Expected: 16777216 bytes"

echo ""
echo "=== First 64 bytes (should start with IPL_ magic) ==="
xxd -l 64 "$DUMP"

echo ""
echo "=== MD5 hashes ==="
md5sum "$DUMP" "$OPENIPC_REF" 2>/dev/null

echo ""
echo "=== Compare IPL sections (first 128KB) ==="
dd if="$DUMP" of=/tmp/dump_ipl.bin bs=1 count=131072 2>/dev/null
dd if="$OPENIPC_REF" of=/tmp/ref_ipl.bin bs=1 count=131072 2>/dev/null
md5sum /tmp/dump_ipl.bin /tmp/ref_ipl.bin

echo ""
echo "=== Compare BOOT+UBOOT+KERNEL+SYSTEM (first 0xF60000 = 16,121,856 bytes) ==="
echo "(DATA partition 0xF60000-0x1000000 will differ — runtime config / settings)"
dd if="$DUMP" of=/tmp/dump_main.bin bs=4096 count=3936 2>/dev/null
dd if="$OPENIPC_REF" of=/tmp/ref_main.bin bs=4096 count=3936 2>/dev/null
md5sum /tmp/dump_main.bin /tmp/ref_main.bin

echo ""
echo "=== Read error check: count solid 0xFF and 0x00 16-byte lines ==="
TOTAL=$(xxd "$DUMP" | wc -l)
ALLFF=$(xxd "$DUMP" | awk '/^[0-9a-f]+: ffff ffff ffff ffff ffff ffff ffff ffff/' | wc -l)
ALLZERO=$(xxd "$DUMP" | awk '/^[0-9a-f]+: 0000 0000 0000 0000 0000 0000 0000 0000/' | wc -l)
echo "Total lines: $TOTAL"
echo "All-0xFF lines: $ALLFF (typical for unprogrammed flash regions)"
echo "All-zero lines: $ALLZERO"

echo ""
echo "=== Hex around DATA partition start (offset 0xF60000) ==="
xxd -s 0xF60000 -l 64 "$DUMP"
