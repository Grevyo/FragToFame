"""Tiny client for the reference game's -netconport remote console.
usage: netcon.py <seconds_to_listen> <until_marker or -> <outfile or -> <command> [<command> ...]
"""
import socket
import sys
import time

listen = float(sys.argv[1])
until = sys.argv[2]
out = sys.argv[3]
cmds = sys.argv[4:]

s = socket.create_connection(("127.0.0.1", 2121), timeout=5)
s.settimeout(0.2)
for c in cmds:
    s.sendall((c + "\n").encode())
    time.sleep(0.15)
buf = b""
end = time.time() + listen
while time.time() < end:
    try:
        d = s.recv(65536)
        if not d:
            break
        buf += d
        if until != "-" and until.encode() in buf:
            time.sleep(0.3)
            try:
                buf += s.recv(65536)
            except OSError:
                pass
            break
    except socket.timeout:
        pass
s.close()
text = buf.decode("utf-8", "replace")
if out != "-":
    with open(out, "a", encoding="utf-8") as f:
        f.write(text)
    lines = text.splitlines()
    print(f"{len(lines)} lines -> {out}")
    for line in lines:
        if not line.startswith("F2F ") and line.strip():
            print(line)
else:
    print(text)
