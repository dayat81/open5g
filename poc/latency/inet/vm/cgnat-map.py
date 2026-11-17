#!/usr/bin/env python3
# poc-inet CGNAT: log mapping NAT44 (jalan di netns l5g-server, root). Dengar event ctnetlink (NEW/DESTROY) langsung dari kernel
# (tanpa paket conntrack; /proc/net/nf_conntrack tidak ada di kernel VM). Hanya flow UE 10.45/16 yg di-SNAT ke 100.64/10.
# JSON per baris: ts, ev NEW/END, proto, ue ip:port, pub ip:port, dst ip:port (+ pkts/bytes bila nf_conntrack_acct=1). Rotasi 5 MB x3.
import sys, os, socket, struct, json, time
OUT = sys.argv[1]; MAXB = 5 * 1024 * 1024
NETLINK_NETFILTER = 12; GROUPS = (1 << 0) | (1 << 2)          # NFNLGRP_CONNTRACK_NEW, NFNLGRP_CONNTRACK_DESTROY
def attrs(b):
    d = {}; i = 0
    while i + 4 <= len(b):
        ln, ty = struct.unpack_from("HH", b, i)
        if ln < 4: break
        d[ty & 0x3fff] = b[i + 4:i + ln]; i += (ln + 3) & ~3
    return d
def tup(b):
    t = attrs(b); ip = attrs(t.get(1, b"")); pr = attrs(t.get(2, b""))
    if 1 not in ip or 2 not in ip: return None
    g = lambda k: struct.unpack(">H", pr[k])[0] if k in pr else 0
    return socket.inet_ntoa(ip[1]), socket.inet_ntoa(ip[2]), pr.get(1, b"\0")[0], g(2), g(3)
def cnt(b):
    c = attrs(b); return (struct.unpack(">Q", c[1])[0] if 1 in c else None, struct.unpack(">Q", c[2])[0] if 2 in c else None)
def rot():
    if os.path.exists(OUT) and os.path.getsize(OUT) > MAXB:
        for i in (2, 1):
            if os.path.exists(f"{OUT}.{i}"): os.replace(f"{OUT}.{i}", f"{OUT}.{i+1}")
        os.replace(OUT, OUT + ".1")
s = socket.socket(socket.AF_NETLINK, socket.SOCK_RAW, NETLINK_NETFILTER)
s.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4 << 20); s.bind((0, GROUPS))
P = {6: "tcp", 17: "udp", 1: "icmp"}; first = {}
while True:
    try: data = s.recv(1 << 16)
    except OSError as e:          # ENOBUFS: event hilang saat burst -> catat dan lanjut
        rot(); open(OUT, "a").write(json.dumps({"ts": round(time.time(), 3), "ev": "LOST", "err": str(e)}) + "\n"); continue
    i = 0; out = []
    while i + 16 <= len(data):
        ln, ty, fl, sq, pid = struct.unpack_from("IHHII", data, i)
        if ln < 16: break
        msg = ty & 0xff
        if ty >> 8 == 1 and msg in (0, 2):
            a = attrs(data[i + 20:i + ln]); o = tup(a.get(1, b"")); r = tup(a.get(2, b""))
            if o and r and o[0].startswith("10.45.") and r[1].startswith("100.64."):
                k = (o[2], o[0], o[3], o[1], o[4]); now = time.time()
                e = {"ts": round(now, 3), "ev": "NEW" if msg == 0 else "END", "proto": P.get(o[2], o[2]),
                     "ue": f"{o[0]}:{o[3]}", "pub": f"{r[1]}:{r[4]}", "dst": f"{o[1]}:{o[4]}"}
                if msg == 0: first[k] = now
                else:
                    e["dur_s"] = round(now - first.pop(k, now), 1)
                    if 9 in a: e["pkts_o"], e["bytes_o"] = cnt(a[9])
                    if 10 in a: e["pkts_r"], e["bytes_r"] = cnt(a[10])
                out.append(e)
        i += (ln + 3) & ~3
    if out:
        rot()
        with open(OUT, "a") as fh:
            for e in out: fh.write(json.dumps(e) + "\n")
