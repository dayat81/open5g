package id.magnon.poc.examine;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.content.Intent;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.net.VpnService;
import android.os.ParcelFileDescriptor;
import android.os.SystemClock;
import android.util.Log;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.util.Random;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Dummy VPN meniru mode "examine" magnon-app (branch cursor/examine-underlying-physical-848e):
 * TUN hanya untuk app yang diizinkan, forwarder userspace di level koneksi (bukan relay paket mentah):
 *  - UDP: DatagramSocket protect()+bindSocket(underlying) per flow, balasan dibungkus ulang ke TUN.
 *  - TCP: state machine kecil (terminasi TCP di TUN, Socket protect()+bindSocket ke tujuan asli).
 * Setiap paket dicatat ke logcat tag MAGNON_EXAMINE (fondasi stempel waktu per paket).
 */
public class ExamineVpnService extends VpnService {
    static final String TAG = "MAGNON_EXAMINE";
    static final String ACTION_START = "id.magnon.poc.examine.START";
    static final String ACTION_STOP = "id.magnon.poc.examine.STOP";
    static final int MTU = 1400, MSS = MTU - 40;
    static final String TUN_ADDR = "10.111.0.2";

    private volatile ParcelFileDescriptor tun;
    private volatile OutputStream tunOut;
    private volatile Network underlying;
    private volatile boolean bindOk = true;
    private String allowedStr = "";
    static volatile ExamineVpnService instance;
    private Thread loop;
    private final ConcurrentHashMap<String, TcpFlow> tcp = new ConcurrentHashMap<>();
    private final ConcurrentHashMap<String, UdpFlow> udp = new ConcurrentHashMap<>();
    private final Random rnd = new Random();
    // poc-phase2: marker MGLT + allowed apps + full route
    static final String VERSION = "0.7-poc";
    static final String MARK_HOST = "10.99.9.20"; static final int MARK_PORT = 9000, MARK_EVERY = 10;
    private volatile Mglt mglt;
    private String[] apps = { "com.android.chrome" };
    private String dns = "10.99.9.20";
    // Proxy global Android emulator (settings global http_proxy, socat magen -> bukan jalur lab). Forwarder men-terminasi
    // CONNECT ke proxy ini dan menyambung langsung ke tujuan asli lewat jalur UE ("de-proxy"); TLS Chrome tidak diubah.
    private String proxyHost = "172.26.0.1"; private int proxyPort = 8080; private boolean deproxy = true;
    private final ConcurrentHashMap<String, Boolean> quicDropped = new ConcurrentHashMap<>();

    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent != null && ACTION_STOP.equals(intent.getAction())) { stopVpn("intent"); return START_NOT_STICKY; }
        instance = this;
        if (intent != null && intent.getStringExtra("apps") != null) apps = intent.getStringExtra("apps").split(",");
        if (intent != null && intent.getStringExtra("dns") != null) dns = intent.getStringExtra("dns");
        if (intent != null && intent.getStringExtra("deproxy") != null) deproxy = !"off".equals(intent.getStringExtra("deproxy"));
        if (tun == null) start();
        return START_STICKY;
    }

    /** Dipanggil dari StopReceiver / MainActivity (tidak bergantung startService dari background). */
    void stopVpn(String why) {
        Log.i(TAG, "stop requested: " + why);
        shutdown();
        stopSelf();
        instance = null;
    }

    @Override public void onRevoke() { shutdown(); super.onRevoke(); }
    @Override public void onDestroy() { shutdown(); super.onDestroy(); }

    private void start() {
        NotificationManager nm = getSystemService(NotificationManager.class);
        nm.createNotificationChannel(new NotificationChannel("vpn", "VPN", NotificationManager.IMPORTANCE_LOW));
        Notification n = new Notification.Builder(this, "vpn").setContentTitle("Magnon PoC Examine")
                .setContentText("dummy VPN aktif").setSmallIcon(android.R.drawable.ic_lock_lock).build();
        startForeground(1, n);
        underlying = findUnderlying();
        try {
            Builder b = new Builder().setSession("magnon-poc-examine").setMtu(MTU)
                    .addAddress(TUN_ADDR, 32).addRoute("0.0.0.0", 0).addDnsServer(dns).setBlocking(true)
                    .addAllowedApplication(getPackageName());
            StringBuilder al = new StringBuilder(getPackageName());
            for (String a : apps) {
                try { b.addAllowedApplication(a.trim()); al.append(',').append(a.trim()); }
                catch (android.content.pm.PackageManager.NameNotFoundException e) { Log.w(TAG, "allowed app tidak ada: " + a); }
            }
            allowedStr = al.toString();
            tun = b.establish();
        } catch (Exception e) { Log.e(TAG, "establish failed", e); stopSelf(); return; }
        if (tun == null) { Log.e(TAG, "establish returned null (no consent?)"); stopSelf(); return; }
        tunOut = new FileOutputStream(tun.getFileDescriptor());
        Log.i(TAG, "VPN up v" + VERSION + " tun=" + TUN_ADDR + "/32 route=0.0.0.0/0 dns=" + dns + " mtu=" + MTU + " allowed=" + allowedStr
                + " underlying=" + underlying);
        new Thread(() -> {
            try {
                DatagramSocket ms = new DatagramSocket();
                protectAndBind(ms);
                mglt = new Mglt(TAG, ms, MARK_HOST, MARK_PORT);
            } catch (Exception e) { Log.e(TAG, "mglt init failed", e); }
        }, "mglt-init").start();
        final ParcelFileDescriptor myTun = tun;
        final FileInputStream in = new FileInputStream(myTun.getFileDescriptor());
        loop = new Thread(() -> {
            byte[] buf = new byte[32767];
            android.system.StructPollfd[] pf = { new android.system.StructPollfd() };
            pf[0].fd = myTun.getFileDescriptor(); pf[0].events = (short) android.system.OsConstants.POLLIN;
            while (tun == myTun) {
                int len;
                try {
                    // poll 200 ms supaya stop() bisa menutup fd (read blocking menahan tun0 tetap hidup)
                    if (android.system.Os.poll(pf, 200) <= 0) continue;
                    len = in.read(buf);
                } catch (Exception e) { break; }
                if (len <= 0) continue;
                try { onPacket(buf, len); } catch (Exception e) { Log.w(TAG, "pkt err", e); }
            }
            try { myTun.close(); } catch (Exception ignored) {}
            Log.i(TAG, "tun loop exit, tun fd closed");
        }, "tun-loop");
        loop.start();
    }

    private Network findUnderlying() {
        ConnectivityManager cm = getSystemService(ConnectivityManager.class);
        for (Network nw : cm.getAllNetworks()) {
            NetworkCapabilities c = cm.getNetworkCapabilities(nw);
            if (c != null && !c.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
                    && c.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) return nw;
        }
        return null;
    }

    private synchronized void shutdown() {
        ParcelFileDescriptor t = tun;
        tun = null;
        Mglt m = mglt; mglt = null; if (m != null) m.close();
        for (TcpFlow f : tcp.values()) f.close();
        for (UdpFlow f : udp.values()) f.close();
        tcp.clear(); udp.clear();
        if (t != null) Log.i(TAG, "VPN down (fd ditutup oleh tun-loop)");
        stopForeground(true);
    }

    // ---------------------------------------------------------------- logging
    private static String ip(byte[] b, int o) { return (b[o] & 255) + "." + (b[o + 1] & 255) + "." + (b[o + 2] & 255) + "." + (b[o + 3] & 255); }
    private static int u16(byte[] b, int o) { return ((b[o] & 255) << 8) | (b[o + 1] & 255); }
    private static long u32(byte[] b, int o) { return ((long) u16(b, o) << 16) | u16(b, o + 2); }

    private void logPkt(String dir, byte[] p, int len) {
        int ihl = (p[0] & 15) * 4, proto = p[9] & 255;
        String pr = proto == 6 ? "tcp" : proto == 17 ? "udp" : proto == 1 ? "icmp" : ("p" + proto);
        StringBuilder s = new StringBuilder(128);
        s.append("ts=").append(System.currentTimeMillis()).append(" mono_ns=").append(SystemClock.elapsedRealtimeNanos())
         .append(" dir=").append(dir).append(" proto=").append(pr).append(" src=").append(ip(p, 12));
        if (proto == 6 || proto == 17) s.append(':').append(u16(p, ihl));
        s.append(" dst=").append(ip(p, 16));
        if (proto == 6 || proto == 17) s.append(':').append(u16(p, ihl + 2));
        s.append(" len=").append(len);
        if (proto == 6) {
            int fl = p[ihl + 13] & 255, dl = len - ihl - ((p[ihl + 12] >> 4) & 15) * 4;
            s.append(" flags=").append(tcpFlags(fl)).append(" seq=").append(u32(p, ihl + 4)).append(" ack=").append(u32(p, ihl + 8)).append(" plen=").append(dl);
        } else if (proto == 17) s.append(" plen=").append(len - ihl - 8);
        Log.i(TAG, s.toString());
    }

    private static String tcpFlags(int f) {
        StringBuilder s = new StringBuilder();
        if ((f & 2) != 0) s.append('S'); if ((f & 16) != 0) s.append('A'); if ((f & 8) != 0) s.append('P');
        if ((f & 1) != 0) s.append('F'); if ((f & 4) != 0) s.append('R');
        return s.toString();
    }

    // ---------------------------------------------------------------- packet out to TUN
    private void writeTun(byte[] p, int len) {
        OutputStream o = tunOut;
        if (o == null || tun == null) return;
        logPkt("net->app", p, len);
        synchronized (this) { try { o.write(p, 0, len); } catch (Exception e) { Log.w(TAG, "tun write: " + e); } }
    }

    private static int csum(byte[] b, int off, int len, long sum) {
        for (int i = 0; i < len - 1; i += 2) sum += u16(b, off + i);
        if ((len & 1) != 0) sum += (b[off + len - 1] & 255) << 8;
        while ((sum >> 16) != 0) sum = (sum & 0xffff) + (sum >> 16);
        return (int) (~sum & 0xffff);
    }

    private static void put16(byte[] b, int o, int v) { b[o] = (byte) (v >> 8); b[o + 1] = (byte) v; }
    private static void put32(byte[] b, int o, long v) { put16(b, o, (int) (v >> 16)); put16(b, o + 2, (int) v); }

    /** Build IPv4 + L4 packet. l4 already contains header+payload with checksum field zero. */
    private static byte[] ipv4(byte[] src, byte[] dst, int proto, byte[] l4, int l4len, int csOff) {
        byte[] p = new byte[20 + l4len];
        p[0] = 0x45; put16(p, 2, p.length); put16(p, 6, 0x4000); p[8] = 64; p[9] = (byte) proto;
        System.arraycopy(src, 0, p, 12, 4); System.arraycopy(dst, 0, p, 16, 4);
        put16(p, 10, csum(p, 0, 20, 0));
        System.arraycopy(l4, 0, p, 20, l4len);
        long ps = u16(src, 0) + u16(src, 2) + u16(dst, 0) + u16(dst, 2) + proto + l4len;
        int c = csum(p, 20, l4len, ps);
        if (proto == 17 && c == 0) c = 0xffff;
        put16(p, 20 + csOff, c);
        return p;
    }

    // ---------------------------------------------------------------- dispatch
    private void onPacket(byte[] p, int len) throws Exception {
        if ((p[0] >> 4) != 4) return; // IPv4 only (route is v4-only)
        logPkt("app->net", p, len);
        int ihl = (p[0] & 15) * 4, proto = p[9] & 255;
        int tot = Math.min(u16(p, 2), len);
        if (proto == 17) onUdp(p, ihl, tot);
        else if (proto == 6) onTcp(p, ihl, tot);
        else Log.i(TAG, "drop proto=" + proto + " (examine forwarder: tcp/udp only)");
    }

    private void protectAndBind(Object sock) throws Exception {
        boolean ok = sock instanceof Socket ? protect((Socket) sock) : protect((DatagramSocket) sock);
        if (!ok) throw new IllegalStateException("protect() failed");
        Network u = underlying;
        if (u != null && bindOk) {
            try {
                if (sock instanceof Socket) u.bindSocket((Socket) sock); else u.bindSocket((DatagramSocket) sock);
            } catch (Exception e) {
                // Mis. EPERM bila netd menolak bind dari uid VPN ke network fisik; protect() saja sudah cukup bypass tun0.
                bindOk = false;
                Log.w(TAG, "bindSocket(underlying=" + u + ") gagal, lanjut dengan protect() saja: " + e.getMessage());
            }
        }
    }

    // ---------------------------------------------------------------- UDP
    private final class UdpFlow {
        final byte[] appIp, dstIp; final int appPort, dstPort; final String key; DatagramSocket s;
        UdpFlow(String key, byte[] appIp, int appPort, byte[] dstIp, int dstPort) {
            this.key = key; this.appIp = appIp; this.appPort = appPort; this.dstIp = dstIp; this.dstPort = dstPort;
        }
        void open() throws Exception {
            s = new DatagramSocket();
            protectAndBind(s);
            s.connect(new InetSocketAddress(InetAddress.getByAddress(dstIp), dstPort));
            s.setSoTimeout(30000);
            new Thread(this::rx, "udp-" + key).start();
        }
        void rx() {
            byte[] b = new byte[MTU];
            while (tun != null) {
                try {
                    DatagramPacket dp = new DatagramPacket(b, b.length);
                    s.receive(dp);
                    int n = dp.getLength();
                    byte[] l4 = new byte[8 + n];
                    put16(l4, 0, dstPort); put16(l4, 2, appPort); put16(l4, 4, 8 + n);
                    System.arraycopy(b, 0, l4, 8, n);
                    byte[] pk = ipv4(dstIp, appIp, 17, l4, l4.length, 6);
                    writeTun(pk, pk.length);
                } catch (java.net.SocketTimeoutException e) { break; }
                catch (Exception e) { Log.i(TAG, "udp " + key + " rx end: " + e); break; }
            }
            close();
        }
        void close() { udp.remove(key); if (s != null) s.close(); }
    }

    private void onUdp(byte[] p, int ihl, int tot) {
        byte[] src = java.util.Arrays.copyOfRange(p, 12, 16), dst = java.util.Arrays.copyOfRange(p, 16, 20);
        int sp = u16(p, ihl), dp = u16(p, ihl + 2);
        String key = ip(p, 12) + ":" + sp + ">" + ip(p, 16) + ":" + dp;
        UdpFlow f = udp.get(key);
        if (dp == 443 && !isPrivate(dst)) { // QUIC: jalur internet lab TCP-only (SOCKS) -> drop cepat agar Chrome fallback ke TCP/TLS
            if (quicDropped.putIfAbsent(key, true) == null) Log.i(TAG, "drop quic " + key + " (fallback TCP)");
            return;
        }
        try {
            if (f == null) {
                f = new UdpFlow(key, src, sp, dst, dp); f.open(); udp.put(key, f);
                int uid = ownerUid(17, src, sp, dst, dp);
                Log.i(TAG, "udp flow open " + key + " uid=" + uid + " pkg=" + pkg(uid));
                Mglt m = mglt;
                if (m != null && !(dp == MARK_PORT && MARK_HOST.equals(ip(p, 16)))) m.mark(rnd.nextInt(), 0, Mglt.EV_UDP, 17, src, sp, dst, dp, 1, tot - ihl - 8, uid);
            }
            f.s.send(new DatagramPacket(p, ihl + 8, tot - ihl - 8));
        } catch (Exception e) { Log.w(TAG, "udp " + key + " send: " + e); }
    }

    // ---------------------------------------------------------------- TCP
    private final class TcpFlow {
        final byte[] appIp, dstIp; final int appPort, dstPort; final String key;
        Socket s; java.nio.channels.SocketChannel ch; long mySeq, myAck; boolean finSent, finRecv, closed;
        // poc-phase2: flow control net->app (window app, tanpa wscale karena SYN-ACK kita hanya MSS) + marker MGLT
        long appAck = -1; int appWnd = 65535; final int flowId = rnd.nextInt(); long mseq, segs, bytes; int uid = -1;
        void mark(int ev) { Mglt m = mglt; if (m != null) m.mark(flowId, mseq++, ev, 6, appIp, appPort,
                realIp != null ? realIp : dstIp, realIp != null ? realPort : dstPort, segs, bytes, uid); }
        // de-proxy: flow app -> proxy global; header CONNECT ditampung lalu socket ke tujuan asli (realIp:realPort)
        boolean dp; volatile boolean upReady; byte[] realIp; int realPort; String realHost;
        final java.io.ByteArrayOutputStream hdr = new java.io.ByteArrayOutputStream();
        void deproxyConnect() {
            new Thread(() -> {
                String req = new String(hdr.toByteArray(), java.nio.charset.StandardCharsets.ISO_8859_1);
                String line = req.substring(0, Math.max(0, req.indexOf("\r\n")));
                try {
                    ch = java.nio.channels.SocketChannel.open(); s = ch.socket(); protectAndBind(s); s.setTcpNoDelay(true);
                    byte[] reply = null;
                    if (line.startsWith("CONNECT ")) {
                        String hp = line.split(" ")[1]; int c = hp.lastIndexOf(':');
                        realHost = hp.substring(0, c); realPort = Integer.parseInt(hp.substring(c + 1));
                        InetAddress a = InetAddress.getByName(realHost); // DNS lewat VPN (10.99.9.20 -> jalur UE)
                        realIp = a.getAddress();
                        mark(Mglt.EV_SYN);
                        s.connect(new InetSocketAddress(a, realPort), 8000);
                        reply = "HTTP/1.1 200 Connection established\r\n\r\n".getBytes();
                    } else { // bukan CONNECT (HTTP polos): teruskan apa adanya ke proxy asli
                        s.connect(new InetSocketAddress(InetAddress.getByAddress(dstIp), dstPort), 8000);
                        java.nio.ByteBuffer wb = java.nio.ByteBuffer.wrap(hdr.toByteArray()); while (wb.hasRemaining()) ch.write(wb);
                    }
                    uid = ownerUid(6, appIp, appPort, dstIp, dstPort);
                    Log.i(TAG, "tcp deproxy " + key + " req=\"" + line + "\" -> " + (realIp != null ? Mglt.ip(realIp) + ":" + realPort : "proxy-asli")
                            + " via " + s.getLocalSocketAddress() + " uid=" + uid + " pkg=" + pkg(uid) + String.format(" fid=%08x", flowId));
                    synchronized (this) { if (reply != null) { send(0x18, reply, 0, reply.length, false); mySeq = (mySeq + reply.length) & 0xffffffffL; } upReady = true; }
                    if (realIp != null) mark(Mglt.EV_EST);
                    rx();
                } catch (Exception e) {
                    Log.i(TAG, "tcp deproxy " + key + " gagal req=\"" + line + "\": " + e);
                    synchronized (this) { byte[] r = "HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n".getBytes();
                        send(0x18, r, 0, r.length, false); mySeq = (mySeq + r.length) & 0xffffffffL; send(0x11, null, 0, 0, false); mySeq += 1; finSent = true; }
                    close();
                }
            }, "tcpdp-" + key).start();
        }
        TcpFlow(String key, byte[] appIp, int appPort, byte[] dstIp, int dstPort) {
            this.key = key; this.appIp = appIp; this.appPort = appPort; this.dstIp = dstIp; this.dstPort = dstPort;
        }
        void send(int flags, byte[] data, int off, int n, boolean syn) {
            int hl = syn ? 24 : 20;
            byte[] l4 = new byte[hl + n];
            put16(l4, 0, dstPort); put16(l4, 2, appPort); put32(l4, 4, mySeq); put32(l4, 8, myAck);
            l4[12] = (byte) ((hl / 4) << 4); l4[13] = (byte) flags; put16(l4, 14, 65535);
            if (syn) { l4[20] = 2; l4[21] = 4; put16(l4, 22, MSS); }
            if (n > 0) System.arraycopy(data, off, l4, hl, n);
            byte[] pk = ipv4(dstIp, appIp, 6, l4, l4.length, 16);
            writeTun(pk, pk.length);
        }
        void connectAsync(long appSeq) {
            new Thread(() -> {
                try {
                    // Socket() di Android baru punya fd saat connect -> protect() gagal; SocketChannel langsung punya fd.
                    // Stream adaptor SocketChannel berbagi blockingLock (read blocking menahan write) -> pakai ch.read/ch.write langsung.
                    ch = java.nio.channels.SocketChannel.open();
                    s = ch.socket();
                    protectAndBind(s);
                    s.setTcpNoDelay(true);
                    s.connect(new InetSocketAddress(InetAddress.getByAddress(dstIp), dstPort), 5000);
                    synchronized (this) { send(0x12, null, 0, 0, true); mySeq += 1; }
                    uid = ownerUid(6, appIp, appPort, dstIp, dstPort);
                    Log.i(TAG, "tcp flow open " + key + " via " + s.getLocalSocketAddress() + " uid=" + uid + " pkg=" + pkg(uid)
                            + String.format(" fid=%08x", flowId));
                    mark(Mglt.EV_EST);
                    rx();
                } catch (Exception e) {
                    Log.i(TAG, "tcp " + key + " connect failed: " + e);
                    synchronized (this) { send(0x14, null, 0, 0, false); }
                    close();
                }
            }, "tcp-" + key).start();
        }
        void rx() {
            byte[] b = new byte[MSS];
            java.nio.ByteBuffer bb = java.nio.ByteBuffer.wrap(b);
            try {
                int n;
                while (true) {
                    bb.clear();
                    n = ch.read(bb);
                    if (n <= 0) break;
                    synchronized (this) {
                        // tunggu window app (data in-flight ke app <= window) agar segmen tidak dibuang kernel app
                        long t0 = System.currentTimeMillis();
                        while (!closed && appAck >= 0 && ((mySeq - appAck) & 0xffffffffL) + n > Math.max(appWnd, MSS)
                                && System.currentTimeMillis() - t0 < 10000) wait(50);
                        if (closed) return; send(0x18, b, 0, n, false); mySeq = (mySeq + n) & 0xffffffffL; }
                }
                synchronized (this) { if (!closed && !finSent) { send(0x11, null, 0, 0, false); mySeq += 1; finSent = true; } }
                if (finRecv) close();
            } catch (Exception e) {
                if (!closed) { synchronized (this) { send(0x14, null, 0, 0, false); } Log.i(TAG, "tcp " + key + " rx: " + e); close(); }
            }
        }
        synchronized void onSegment(int flags, long seq, long ack, int wnd, byte[] p, int off, int n) throws Exception {
            if ((flags & 4) != 0) { Log.i(TAG, "tcp " + key + " RST from app"); close(); return; }
            if ((flags & 16) != 0) { appAck = ack; appWnd = wnd; notifyAll(); }
            if (dp && !upReady) { // fase header proxy
                if (n > 0 && seq == myAck && hdr.size() < 8192) {
                    boolean had = hdr.toString("ISO-8859-1").contains("\r\n\r\n");
                    hdr.write(p, off, n); myAck = (myAck + n) & 0xffffffffL; send(0x10, null, 0, 0, false);
                    if (!had && hdr.toString("ISO-8859-1").contains("\r\n\r\n")) deproxyConnect();
                } else if (n > 0) send(0x10, null, 0, 0, false);
                if ((flags & 1) != 0) { send(0x14, null, 0, 0, false); close(); }
                return;
            }
            if (s == null || !s.isConnected()) return; // still connecting
            if (n > 0) {
                if (seq == myAck) {
                    java.nio.ByteBuffer wb = java.nio.ByteBuffer.wrap(p, off, n);
                    while (wb.hasRemaining()) ch.write(wb); myAck = (myAck + n) & 0xffffffffL; send(0x10, null, 0, 0, false);
                    segs++; bytes += n; if (segs == 1 || segs % MARK_EVERY == 0) mark(Mglt.EV_DATA); }
                else { send(0x10, null, 0, 0, false); return; } // dup / out-of-order -> re-ACK
            }
            if ((flags & 1) != 0 && !finRecv && ((seq + n) & 0xffffffffL) == myAck) {
                myAck = (myAck + 1) & 0xffffffffL; finRecv = true; mark(Mglt.EV_FIN);
                try { s.shutdownOutput(); } catch (Exception ignored) {}
                send(0x10, null, 0, 0, false);
                if (finSent) close();
            } else if ((flags & 1) != 0 && finRecv) send(0x10, null, 0, 0, false);
        }
        void close() {
            closed = true; tcp.remove(key); synchronized (this) { notifyAll(); }
            try { if (s != null) s.close(); } catch (Exception ignored) {}
        }
    }

    private void onTcp(byte[] p, int ihl, int tot) throws Exception {
        int sp = u16(p, ihl), dp = u16(p, ihl + 2), flags = p[ihl + 13] & 255;
        long seq = u32(p, ihl + 4);
        int doff = ((p[ihl + 12] >> 4) & 15) * 4, n = tot - ihl - doff;
        String key = ip(p, 12) + ":" + sp + ">" + ip(p, 16) + ":" + dp;
        TcpFlow f = tcp.get(key);
        if ((flags & 0x12) == 0x02) { // pure SYN
            if (f != null) return; // retransmitted SYN while connecting
            f = new TcpFlow(key, java.util.Arrays.copyOfRange(p, 12, 16), sp, java.util.Arrays.copyOfRange(p, 16, 20), dp);
            f.mySeq = rnd.nextInt() & 0xffffffffL; f.myAck = (seq + 1) & 0xffffffffL;
            tcp.put(key, f);
            if (deproxy && dp == proxyPort && proxyHost.equals(ip(p, 16))) {
                f.dp = true;
                synchronized (f) { f.send(0x12, null, 0, 0, true); f.mySeq += 1; }
                return;
            }
            f.mark(Mglt.EV_SYN);
            f.connectAsync(seq);
            return;
        }
        if (f == null) {
            if ((flags & 4) == 0) { // unknown flow -> RST
                TcpFlow t = new TcpFlow(key, java.util.Arrays.copyOfRange(p, 12, 16), sp, java.util.Arrays.copyOfRange(p, 16, 20), dp);
                t.mySeq = u32(p, ihl + 8); t.myAck = (seq + n) & 0xffffffffL; t.send(0x14, null, 0, 0, false);
            }
            return;
        }
        f.onSegment(flags, seq, u32(p, ihl + 8), u16(p, ihl + 14), p, ihl + doff, n);
    }

    // ---------------------------------------------------------------- poc-phase2 helpers
    private static boolean isPrivate(byte[] a) {
        int x = a[0] & 255, y = a[1] & 255;
        return x == 10 || x == 127 || (x == 172 && y >= 16 && y < 32) || (x == 192 && y == 168) || (x == 100 && y >= 64 && y < 128) || x >= 224;
    }

    private int ownerUid(int proto, byte[] src, int sp, byte[] dst, int dp) {
        try {
            ConnectivityManager cm = getSystemService(ConnectivityManager.class);
            return cm.getConnectionOwnerUid(proto, new InetSocketAddress(InetAddress.getByAddress(src), sp),
                    new InetSocketAddress(InetAddress.getByAddress(dst), dp));
        } catch (Exception e) { return -1; }
    }

    private String pkg(int uid) {
        if (uid < 0) return "?";
        String[] p = getPackageManager().getPackagesForUid(uid);
        return p != null && p.length > 0 ? p[0] : ("uid" + uid);
    }
}
