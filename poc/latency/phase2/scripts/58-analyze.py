#!/usr/bin/env python3
"""poc-phase2: analisis run (jalan di box/magen, python3 stdlib).
Masukan: results/run-*/ (mglt.log, logcat-magnon.txt, precheck.txt, zeek-live-extract.txt, magen-emu-br-marker.pcap opsional)
Keluaran: summary.txt + mglt-joined.csv
one_way_corr = (ts_zeek - off_vm) - (t_ue - off_emu)   dgn off_* = jam_remote - jam_magen (55-skew.sh)."""
import json, re, sys, os, statistics as st, collections, struct
D = sys.argv[1]
pre = open(os.path.join(D, 'precheck.txt')).read()
vm = [float(x) for x in re.findall(r'VM_minus_magen offset_s=(-?[\d.]+)', pre)]
emu = [float(x) for x in re.findall(r'EMU_minus_magen offset_s=(-?[\d.]+)', pre)]
off_vm, off_emu = st.mean(vm), st.mean(emu)
rtt_vm = [float(x) for x in re.findall(r'VM_minus_magen .*best_rtt_ms=([\d.]+)', pre)]
rtt_emu = [float(x) for x in re.findall(r'EMU_minus_magen .*best_rtt_ms=([\d.]+)', pre)]
out = []
P = lambda *a: out.append(' '.join(str(x) for x in a))
P(f"skew: VM-magen={vm} -> {off_vm:.4f}s (±{max(rtt_vm)/2:.1f} ms)  EMU-magen={emu} -> {off_emu:.4f}s (±{max(rtt_emu)/2:.1f} ms)")
P(f"koreksi one_way = raw - off_vm + off_emu = raw + {(-off_vm + off_emu):.4f} s")
# logcat
lc = open(os.path.join(D, 'logcat-magnon.txt'), errors='replace').read().splitlines()
tx = {}; rtt = {}; flows = []
for l in lc:
    m = re.search(r'mglt tx fid=(\w+) seq=(\d+) ev=(\w+) t_ue_ns=(\d+) dst=([\d.]+):(\d+)', l)
    if m: tx[(m[1], int(m[2]))] = (m[3], int(m[4]), m[5], int(m[6]))
    m = re.search(r'mglt echo fid=(\w+) seq=(\d+) rtt_ms=([\d.?]+)', l)
    if m and m[3] != '?': rtt[(m[1], int(m[2]))] = float(m[3])
    if 'tcp deproxy' in l or 'tcp flow open' in l or 'udp flow open' in l or 'drop quic' in l: flows.append(l.split('MAGNON_EXAMINE: ')[-1])
P(f"logcat: mglt tx={len(tx)} echo={len(rtt)} flows={len(flows)}")
if rtt:
    v = sorted(rtt.values()); P(f"RTT marker app (UE->reflector->UE): n={len(v)} min={v[0]:.1f} p50={st.median(v):.1f} p90={v[int(len(v)*0.9)-1]:.1f} max={v[-1]:.1f} ms")
# mglt.log dedupe (mirror ingress+egress -> duplikat): ambil ts pertama per (fid,seq,dir,seg)
rows = [json.loads(l) for l in open(os.path.join(D, 'mglt.log')) if l.startswith('{')]
# hanya marker milik run ini (fid,seq ada di logcat tx); file mglt rotasi lama bisa ikut ter-cat
rows = [r for r in rows if (r['flow_id'], r['seq']) in tx] if tx else rows
first = {}
for r in rows:
    k = (r['flow_id'], r['seq'], r['dir'], r.get('seg', '?'))
    if k not in first or r['ts'] < first[k]['ts']: first[k] = r
P(f"mglt.log: baris={len(rows)} unik(fid,seq,dir,seg)={len(first)} crc_ok={sum(r['crc_ok'] for r in rows)}/{len(rows)}")
corr = -off_vm + off_emu
by = collections.defaultdict(list)
for k, r in first.items():
    by[(r['dir'], r.get('seg', '?'))].append(r['one_way_raw'] + corr)
for k in sorted(by):
    v = sorted(by[k]); ms = [x * 1000 for x in v]
    P(f"  {k[0]:2} {k[1]:10} n={len(v):3}  one_way_corr ms: min={ms[0]:.1f} p50={st.median(ms):.1f} p90={ms[max(0,int(len(ms)*0.9)-1)]:.1f} max={ms[-1]:.1f}  (raw p50={(st.median(v)-corr):.4f}s)")
# per-marker breakdown UL s1u -> sgi (beda jam sama: VM) dan UL sgi -> DL sgi (reflector)
seg_ts = collections.defaultdict(dict)
for (fid, seq, d, sg), r in first.items(): seg_ts[(fid, seq)][(d, sg)] = r['ts']
d1 = [ (v[('UL','sgi')] - v[('UL','s1u(gtp)')])*1000 for v in seg_ts.values() if ('UL','sgi') in v and ('UL','s1u(gtp)') in v]
d2 = [ (v[('DL','s1u(gtp)')] - v[('DL','sgi')])*1000 for v in seg_ts.values() if ('DL','sgi') in v and ('DL','s1u(gtp)') in v]
d3 = [ (v[('DL','sgi')] - v[('UL','sgi')])*1000 for v in seg_ts.values() if ('DL','sgi') in v and ('UL','sgi') in v]
for name, v in (('UL S1-U->SGi (core, jam VM saja)', d1), ('DL SGi->S1-U (core)', d2), ('reflector turnaround di SGi', d3)):
    if v: P(f"  {name}: n={len(v)} p50={st.median(v):.3f} ms max={max(v):.3f} ms")
# join flows app dengan zeek-live ssl/conn (dst ip:port)
zl = open(os.path.join(D, 'zeek-live-extract.txt'), errors='replace').read().splitlines()
ssl = {}; conn = collections.defaultdict(list)
for l in zl:
    if not l.startswith('{'): continue
    j = json.loads(l)
    if 'server_name' in j or 'version' in j: ssl[(j['id.resp_h'], j['id.resp_p'])] = j.get('server_name')
    elif j.get('proto') == 'tcp': conn[(j['id.resp_h'], j['id.resp_p'])].append(j)
P("korelasi marker (orig_dst) <-> zeek-live (resp_h:resp_p, dalam tunnel GTP dari UE):")
dsts = collections.Counter((r.get('orig_dst'), r.get('orig_dport')) for r in first.values() if r['dir'] == 'UL' and r.get('orig_dport') not in (None,))
for (ip, pt), n in dsts.most_common(15):
    c = conn.get((ip, pt), [])
    tp = sorted({t for x in c for t in x.get('tunnel_parents', [])})
    P(f"  {ip}:{pt} marker={n} sni={ssl.get((ip, pt))} zeek_conn={len(c)} tap={sorted({str(x.get('_tap_id')) for x in c})} tunnel_parents={tp[:2]}")
P("flow app (logcat):"); [P('  ' + f) for f in flows[:40]]
# CSV
with open(os.path.join(D, 'mglt-joined.csv'), 'w') as f:
    f.write('flow_id,seq,evt,dir,seg,ts_zeek,t_ue,one_way_raw_s,one_way_corr_ms,app_rtt_ms,orig_dst,orig_dport,teid\n')
    for (fid, seq, d, sg), r in sorted(first.items(), key=lambda x: x[1]['ts']):
        f.write(f"{fid},{seq},{r.get('evt')},{d},{sg},{r['ts']:.6f},{r['t_ue']:.6f},{r['one_way_raw']:.6f},{(r['one_way_raw']+corr)*1000:.2f},{rtt.get((fid,seq),'')},{r.get('orig_dst')},{r.get('orig_dport')},{r.get('teid','')}\n")
open(os.path.join(D, 'summary.txt'), 'w').write('\n'.join(out) + '\n')
print('\n'.join(out))
# --- dekomposisi via pcap bridge emulator di magen (jam magen): emu -> magen-br -> S1-U
pc = os.path.join(D, 'magen-emu-br-marker.pcap')
if os.path.exists(pc) and os.path.getsize(pc) > 24:
    b = open(pc, 'rb').read(); le = b[:4] in (b'\xd4\xc3\xb2\xa1', b'\x4d\x3c\xb2\xa1'); ns = b[:4] in (b'\x4d\x3c\xb2\xa1', b'\xa1\xb2\x3c\x4d')
    E = '<' if le else '>'; o = 24; br = {}
    while o + 16 <= len(b):
        s_, us, cl, _ = struct.unpack(E + 'IIII', b[o:o+16]); pk = b[o+16:o+16+cl]; o += 16 + cl
        t = s_ + us / (1e9 if ns else 1e6); i = pk.find(b'MGLT')
        if i < 0 or len(pk) < i + 32: continue
        fid = pk[i+8:i+12].hex(); seq = struct.unpack('>I', pk[i+12:i+16])[0]
        dport = struct.unpack('>H', pk[i-6:i-4])[0]
        d = 'UL' if dport == 9000 else 'DL'
        br.setdefault((fid, seq, d), t)
    a1 = []; a2 = []; a3 = []; a4 = []
    for (fid, seq, d), t in br.items():
        x = tx.get((fid, seq))
        if d == 'UL' and x: a1.append((t - (x[1] / 1e9 - off_emu)) * 1000)
        r = first.get((fid, seq, d, 's1u(gtp)'))
        if r and d == 'UL': a2.append(((r['ts'] - off_vm) - t) * 1000)
        if r and d == 'DL': a3.append((t - (r['ts'] - off_vm)) * 1000)
    P(f"dekomposisi (pcap magen br-emu, n_ul={sum(1 for k in br if k[2]=='UL')} n_dl={sum(1 for k in br if k[2]=='DL')}):")
    for name, v in (('UL app(t_ue) -> magen br-emu [skew EMU ±]', a1), ('UL magen br-emu -> S1-U [skew VM ±2-3ms]', a2), ('DL S1-U -> magen br-emu [skew VM]', a3)):
        if v: v = sorted(v); P(f"  {name}: n={len(v)} min={v[0]:.1f} p50={st.median(v):.1f} max={v[-1]:.1f} ms")
    open(os.path.join(D, 'summary.txt'), 'w').write('\n'.join(out) + '\n'); print('\n'.join(out[-4:]))
