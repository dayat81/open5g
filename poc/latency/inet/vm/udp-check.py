# poc-inet: cek UDP keluar (read-only): DNS UDP ke 8.8.8.8 (resolver mini, tanpa resolv.conf) + QUIC UDP 443 (version negotiation)
import socket, os, time, struct, sys
def dns(server, name):
    q = struct.pack(">HHHHHH", 0x1234, 0x0100, 1, 0, 0, 0) + b"".join(bytes([len(p)]) + p.encode() for p in name.split(".")) + b"\0" + struct.pack(">HH", 1, 1)
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.settimeout(4); t = time.time()
    try:
        s.sendto(q, (server, 53)); d, _ = s.recvfrom(2000); ms = (time.time() - t) * 1000
        an = struct.unpack(">H", d[6:8])[0]; i = len(q); ips = []
        for _ in range(an):
            i += 2 if d[i] & 0xc0 == 0xc0 else d.index(b"\0", i) + 1 - i
            typ, cls, ttl, rl = struct.unpack(">HHIH", d[i:i + 10]); i += 10
            if typ == 1 and rl == 4: ips.append(socket.inet_ntoa(d[i:i + 4]))
            i += rl
        print("DNS UDP @%s %s -> %s (%.0f ms)" % (server, name, ",".join(ips), ms)); return ips
    except Exception as e: print("DNS UDP @%s %s FAIL %s" % (server, name, e)); return []
for h in ("www.google.com", "cloudflare-quic.com", "www.youtube.com"):
    ips = dns("8.8.8.8", h)
    if not ips: continue
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.settimeout(4)
    pkt = bytes([0xc0]) + bytes.fromhex("1a1a1a1a") + bytes([8]) + os.urandom(8) + bytes([0]) + os.urandom(1200)
    try:
        t = time.time(); s.sendto(pkt, (ips[0], 443)); d, a = s.recvfrom(2000)
        print("QUIC UDP443 %s %s reply %d B dari %s:%d (%.0f ms) local=%s" % (h, ips[0], len(d), a[0], a[1], (time.time() - t) * 1000, s.getsockname()))
    except Exception as e: print("QUIC UDP443", h, ips[0], "FAIL", e)
