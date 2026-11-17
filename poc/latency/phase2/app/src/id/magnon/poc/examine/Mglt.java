package id.magnon.poc.examine;

import android.os.SystemClock;
import android.util.Log;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.util.concurrent.ConcurrentHashMap;

/**
 * poc-phase2: marker MGLT v1 per flow. Dikirim forwarder lewat socket UDP protected ke reflector (echo) 10.99.9.20:9000,
 * sehingga Zeek (S1-U dalam GTP-U dan SGi) bisa membaca t_ue tanpa mengubah payload TCP/TLS app.
 *
 * Layout (network byte order), 60 B:
 *  0 magic "MGLT" | 4 ver=1 | 5 flags | 6 hdr_len=60 | 8 flow_id u32 | 12 seq u32 (per flow)
 * 16 t_ue_ns u64 (epoch UTC ns, jam emulator) | 24 t_ue_mono_us u32 | 28 crc32c(byte 0..27)
 * --- ekstensi flow (flags bit5) ---
 * 32 ext_type=1 | 33 proto (6/17) | 34 event (1 syn,2 est,3 data,4 fin,5 udp) | 35 rsv
 * 36 orig_src ip | 40 orig_sport u16 | 42 orig_dst ip | 46 orig_dport u16 | 48 app_segs u32 | 52 app_bytes u32 | 56 app_uid u32
 * flags: bit0 dir (0=UL; echo memantulkan apa adanya) | bit2 clock-synced (0: belum chrony) | bit5 flow-ext
 */
final class Mglt {
    static final int LEN = 60, EV_SYN = 1, EV_EST = 2, EV_DATA = 3, EV_FIN = 4, EV_UDP = 5;
    static final String[] EVN = { "?", "syn", "est", "data", "fin", "udp" };
    private static final int[] T = new int[256];
    static {
        for (int i = 0; i < 256; i++) { int c = i; for (int k = 0; k < 8; k++) c = (c & 1) != 0 ? (c >>> 1) ^ 0x82F63B78 : c >>> 1; T[i] = c; }
    }
    static int crc32c(byte[] b, int off, int len) {
        int c = 0xFFFFFFFF;
        for (int i = 0; i < len; i++) c = T[(c ^ b[off + i]) & 0xff] ^ (c >>> 8);
        return ~c;
    }

    private final String tag;
    private final DatagramSocket s;
    private final ConcurrentHashMap<Long, long[]> sent = new ConcurrentHashMap<>(); // key fid<<32|seq -> {mono_ns, t_ue_ns}
    private final long epochBaseNs; // t_ue_ns = epochBaseNs + elapsedRealtimeNanos()
    private volatile boolean running = true;
    long tx, rx;

    Mglt(String tag, DatagramSocket protectedSock, String host, int port) throws Exception {
        this.tag = tag; this.s = protectedSock;
        s.connect(new InetSocketAddress(InetAddress.getByName(host), port));
        // basis epoch presisi sub-ms: tunggu pergantian milidetik currentTimeMillis lalu ambil elapsedRealtimeNanos
        long m0 = System.currentTimeMillis(), m1;
        while ((m1 = System.currentTimeMillis()) == m0) { }
        epochBaseNs = m1 * 1_000_000L - SystemClock.elapsedRealtimeNanos();
        new Thread(this::rxLoop, "mglt-rx").start();
        Log.i(tag, "mglt ready -> " + host + ":" + port + " local=" + s.getLocalSocketAddress() + " epochBaseNs=" + epochBaseNs);
    }

    long nowNs() { return epochBaseNs + SystemClock.elapsedRealtimeNanos(); }

    private static void p16(byte[] b, int o, int v) { b[o] = (byte) (v >> 8); b[o + 1] = (byte) v; }
    private static void p32(byte[] b, int o, long v) { p16(b, o, (int) (v >> 16)); p16(b, o + 2, (int) v); }
    private static long g32(byte[] b, int o) { return ((b[o] & 255L) << 24) | ((b[o + 1] & 255L) << 16) | ((b[o + 2] & 255L) << 8) | (b[o + 3] & 255L); }

    /** Kirim satu marker. Dipanggil dari thread forwarder; tidak memblokir lama (UDP). */
    void mark(int flowId, long seq, int event, int proto, byte[] src, int sport, byte[] dst, int dport, long segs, long bytes, int uid) {
        if (!running) return;
        byte[] b = new byte[LEN];
        long mono = SystemClock.elapsedRealtimeNanos(), tUe = epochBaseNs + mono;
        b[0] = 'M'; b[1] = 'G'; b[2] = 'L'; b[3] = 'T'; b[4] = 1; b[5] = 0x20; p16(b, 6, LEN);
        p32(b, 8, flowId & 0xffffffffL); p32(b, 12, seq);
        p32(b, 16, tUe >>> 32); p32(b, 20, tUe); p32(b, 24, (mono / 1000) & 0xffffffffL);
        p32(b, 28, crc32c(b, 0, 28) & 0xffffffffL);
        b[32] = 1; b[33] = (byte) proto; b[34] = (byte) event;
        System.arraycopy(src, 0, b, 36, 4); p16(b, 40, sport); System.arraycopy(dst, 0, b, 42, 4); p16(b, 46, dport);
        p32(b, 48, segs); p32(b, 52, bytes); p32(b, 56, uid & 0xffffffffL);
        long key = ((flowId & 0xffffffffL) << 32) | (seq & 0xffffffffL);
        sent.put(key, new long[] { mono, tUe });
        try { s.send(new DatagramPacket(b, LEN)); tx++; }
        catch (Exception e) { Log.w(tag, "mglt send: " + e); return; }
        Log.i(tag, String.format("mglt tx fid=%08x seq=%d ev=%s t_ue_ns=%d dst=%s:%d proto=%d segs=%d bytes=%d uid=%d",
                flowId, seq, EVN[event], tUe, ip(dst), dport, proto, segs, bytes, uid));
    }

    private void rxLoop() {
        byte[] b = new byte[1500];
        while (running) {
            try {
                DatagramPacket dp = new DatagramPacket(b, b.length);
                s.receive(dp);
                long now = SystemClock.elapsedRealtimeNanos();
                if (dp.getLength() < 32 || b[0] != 'M' || b[1] != 'G' || b[2] != 'L' || b[3] != 'T') continue;
                boolean crcOk = (crc32c(b, 0, 28) & 0xffffffffL) == g32(b, 28);
                long fid = g32(b, 8), seq = g32(b, 12);
                long[] st = sent.remove((fid << 32) | seq);
                rx++;
                Log.i(tag, String.format("mglt echo fid=%08x seq=%d rtt_ms=%s crc_ok=%b t_rx_ns=%d", fid, seq,
                        st == null ? "?" : String.format("%.3f", (now - st[0]) / 1e6), crcOk, epochBaseNs + now));
            } catch (java.net.SocketTimeoutException e) { /* idle */ }
            catch (Exception e) { if (running) Log.i(tag, "mglt rx end: " + e); break; }
        }
    }

    void close() { running = false; s.close(); Log.i(tag, "mglt closed tx=" + tx + " rx=" + rx); }

    static String ip(byte[] a) { return (a[0] & 255) + "." + (a[1] & 255) + "." + (a[2] & 255) + "." + (a[3] & 255); }
}
