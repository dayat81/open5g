##! poc-phase2: MGLT v1 marker reader (tanpa plugin C++).
##! Membaca payload UDP (default port 9000, arah UL dan echo DL) yang diawali magic "MGLT",
##! baik di dalam GTP-U (S1-U, decap otomatis Zeek) maupun polos (SGi). Menulis mglt.log.
##! Layout: lihat app/src/.../Mglt.java (32 B inti + 28 B ekstensi flow).

module MGLT;

export {
    redef enum Log::ID += { LOG };

    ## Port UDP reflector tempat marker dikirim.
    const ports: set[port] = { 9000/udp } &redef;
    ## Peta VLAN mirror0 -> segmen (tap-map.csv lab5g-vm).
    const vlan_seg: table[int] of string = {
        [101] = "s1mme", [102] = "s1u", [104] = "s11", [105] = "s5s8", [106] = "pfcp",
        [107] = "s6a", [108] = "gx", [109] = "sgi", [110] = "mgmt", [112] = "sgs",
    } &redef;
    ## Subnet IP luar tunnel -> segmen (untuk paket inner GTP-U yang tidak membawa VLAN di record conn).
    const subnet_seg: table[subnet] of string = {
        [10.99.2.0/24] = "s1u", [10.99.5.0/24] = "s5s8",
    } &redef;

    type Info: record {
        ts:            time     &log;   ##< ts_zeek: waktu tangkap paket marker (jam probe/VM)
        uid:           string   &log;   ##< uid koneksi marker (inner)
        tunnel_uid:    string   &log &optional;  ##< uid koneksi GTP-U luar (S1-U)
        tunnel_outer:  string   &log &optional;  ##< IP luar src>dst paket ini (dari frame mentah)
        teid:          count    &log &optional;  ##< GTP-U TEID paket ini
        vlan:          int      &log &optional;
        seg:           string   &log &optional;  ##< s1u / sgi / ...
        dir:           string   &log;   ##< UL (UE->reflector) / DL (echo)
        mk_src:        string   &log;   ##< src:port marker (setelah SNAT UE)
        mk_dst:        string   &log;
        flow_id:       string   &log;
        seq:           count    &log;
        evt:           string   &log &optional;  ##< syn/est/data/fin/udp
        t_ue:          time     &log;   ##< t_ue_ns dari app (jam emulator)
        one_way_raw:   interval &log;   ##< ts - t_ue (belum koreksi skew; untuk DL = sejak kirim UE)
        t_ue_mono_us:  count    &log;
        flags:         count    &log;
        crc_ok:        bool     &log;
        orig_proto:    string   &log &optional;
        orig_src:      string   &log &optional;  ##< 5-tuple asli flow app di tun0
        orig_dst:      addr     &log &optional;
        orig_dport:    count    &log &optional;
        app_segs:      count    &log &optional;
        app_bytes:     count    &log &optional;
        app_uid:       count    &log &optional;
    };
    global log_mglt: event(rec: Info);
}

redef udp_content_delivery_ports_orig += { [9000/udp] = T };
redef udp_content_delivery_ports_resp += { [9000/udp] = T };
redef udp_content_delivery_ports_use_resp = T;   # arah echo (DL) dicocokkan dgn port reflector, bukan port UE

global crc_tab: vector of count = vector();
global evn: table[count] of string = { [1] = "syn", [2] = "est", [3] = "data", [4] = "fin", [5] = "udp" };

function build_crc_tab()
    {
    local i = 0;
    while ( i < 256 )
        {
        local c = i;
        local k = 0;
        while ( k < 8 )
            {
            if ( c % 2 == 1 )
                c = (c / 2) ^ 0x82F63B78;
            else
                c = c / 2;
            ++k;
            }
        crc_tab += c;
        ++i;
        }
    }

function crc32c(s: string): count
    {
    local c = 0xFFFFFFFF;
    local b = 0;
    local i = 0;
    local n = |s|;
    while ( i < n )
        {
        b = bytestring_to_count(s[i], F);
        c = crc_tab[(c ^ b) % 256] ^ (c / 256);
        ++i;
        }
    return c ^ 0xFFFFFFFF;
    }

event zeek_init() &priority=5
    {
    build_crc_tab();
    Log::create_stream(MGLT::LOG, [$columns=Info, $ev=log_mglt, $path="mglt"]);
    }

function u(s: string, off: count, len: count): count
    {
    return bytestring_to_count(s[off:off+len], F);
    }

function ip4(s: string, off: count): addr
    {
    return count_to_v4_addr(u(s, off, 4));
    }

event udp_contents(c: connection, is_orig: bool, contents: string)
    {
    if ( |contents| < 32 || contents[0:4] != "MGLT" )
        return;
    if ( c$id$resp_p !in ports )
        return;
    local tns = u(contents, 16, 8);
    local tue = double_to_time((tns / 1000000000) * 1.0 + (tns % 1000000000) / 1e9);
    local now = network_time();
    local r = Info($ts=now, $uid=c$uid, $dir=is_orig ? "UL" : "DL",
                   $mk_src=fmt("%s:%d", c$id$orig_h, port_to_count(c$id$orig_p)),
                   $mk_dst=fmt("%s:%d", c$id$resp_h, port_to_count(c$id$resp_p)),
                   $flow_id=fmt("%08x", u(contents, 8, 4)), $seq=u(contents, 12, 4),
                   $t_ue=tue, $one_way_raw=now - tue, $t_ue_mono_us=u(contents, 24, 4),
                   $flags=u(contents, 5, 1), $crc_ok=(crc32c(contents[0:28]) == u(contents, 28, 4)));
    # Per paket: baca frame mentah (Ethernet [+802.1Q] + IPv4 [+UDP/2152 GTP-U]) supaya segmen/VLAN tidak tertukar
    # walau inner 5-tuple yang sama lewat S1-U dan S5/S8 (record conn Zeek bisa berbagi satu koneksi inner).
    local pk = get_current_packet();
    local d = pk$data;
    if ( |d| >= 34 )
        {
        local off = 12;
        local et = u(d, 12, 2);
        if ( et == 0x8100 || et == 0x88a8 )
            {
            r$vlan = u(d, 14, 2) % 4096;
            off = 16;
            et = u(d, 16, 2);
            }
        local ipo = off + 2;
        if ( et == 0x0800 && |d| >= ipo + 28 )
            {
            local ihl = (u(d, ipo, 1) % 16) * 4;
            local uo = ipo + ihl;
            if ( u(d, ipo + 9, 1) == 17 && u(d, uo + 2, 2) == 2152 && |d| >= uo + 16 )
                {
                r$tunnel_outer = fmt("%s>%s", ip4(d, ipo + 12), ip4(d, ipo + 16));
                r$teid = u(d, uo + 12, 4);
                }
            }
        }
    if ( c?$tunnel && |c$tunnel| > 0 && c$tunnel[|c$tunnel| - 1]?$uid )
        r$tunnel_uid = c$tunnel[|c$tunnel| - 1]$uid;
    if ( r?$vlan && r$vlan in vlan_seg )
        r$seg = vlan_seg[r$vlan] + (r?$teid ? "(gtp)" : "");
    if ( |contents| >= 60 && u(contents, 32, 1) == 1 )
        {
        local ev = u(contents, 34, 1);
        r$evt = ev in evn ? evn[ev] : fmt("%d", ev);
        local pr = u(contents, 33, 1);
        r$orig_proto = pr == 6 ? "tcp" : (pr == 17 ? "udp" : fmt("%d", pr));
        r$orig_src = fmt("%s:%d", ip4(contents, 36), u(contents, 40, 2));
        r$orig_dst = ip4(contents, 42);
        r$orig_dport = u(contents, 46, 2);
        r$app_segs = u(contents, 48, 4);
        r$app_bytes = u(contents, 52, 4);
        r$app_uid = u(contents, 56, 4);
        }
    Log::write(MGLT::LOG, r);
    }
