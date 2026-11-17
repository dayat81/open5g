package id.magnon.poc.examine;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.util.Log;
import android.widget.TextView;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.Socket;

/**
 * Traffic generator (target app; same UID as the VPN allowed app, sockets NOT protected
 * so they enter tun0). adb: am start -n id.magnon.poc.examine/.GenActivity
 *   --es host 10.99.9.20 --ei tcpPort 5201 --ei tcpCount 3 --ei udpPort 9000 --ei udpCount 5
 */
public class GenActivity extends Activity {
    static final String TAG = "MAGNON_GEN";
    private TextView tv;
    private final StringBuilder sb = new StringBuilder();

    @Override protected void onCreate(Bundle b) {
        super.onCreate(b);
        tv = new TextView(this);
        tv.setTextSize(14);
        tv.setPadding(32, 64, 32, 32);
        setContentView(tv);
        run(getIntent());
    }

    @Override protected void onNewIntent(Intent i) { super.onNewIntent(i); run(i); }

    private void out(String s) {
        Log.i(TAG, s);
        runOnUiThread(() -> { sb.append(s).append('\n'); tv.setText("Magnon PoC traffic generator\n" + sb); });
    }

    private void run(Intent i) {
        final String host = str(i, "host", "10.99.9.20");
        final int tcpPort = i.getIntExtra("tcpPort", 5201), tcpCount = i.getIntExtra("tcpCount", 3);
        final int udpPort = i.getIntExtra("udpPort", 9000), udpCount = i.getIntExtra("udpCount", 5);
        new Thread(() -> {
            for (int n = 1; n <= tcpCount; n++) {
                long t0 = System.nanoTime();
                try (Socket s = new Socket()) {
                    s.connect(new InetSocketAddress(host, tcpPort), 5000);
                    long tc = System.nanoTime();
                    s.setSoTimeout(3000);
                    OutputStream os = s.getOutputStream();
                    // 37-byte iperf3-style cookie (server replies with a state byte)
                    byte[] cookie = String.format("magnonpocexamine%021d", System.currentTimeMillis()).getBytes();
                    os.write(cookie, 0, 36); os.write(0); os.flush();
                    InputStream is = s.getInputStream();
                    int r = -2;
                    try { r = is.read(); } catch (Exception e) { r = -3; }
                    long tr = System.nanoTime();
                    out(String.format("tcp#%d %s:%d connect=%.1fms firstbyte=%d after=%.1fms local=%s",
                            n, host, tcpPort, (tc - t0) / 1e6, r, (tr - tc) / 1e6, s.getLocalSocketAddress()));
                } catch (Exception e) {
                    out("tcp#" + n + " error " + e);
                }
                sleep(1500); // beri waktu iperf3 -s reset antar sesi
            }
            try (DatagramSocket ds = new DatagramSocket()) {
                InetAddress a = InetAddress.getByName(host);
                for (int n = 1; n <= udpCount; n++) {
                    byte[] p = String.format("MAGNON-POC seq=%d ts=%d", n, System.currentTimeMillis()).getBytes();
                    long t0 = System.nanoTime();
                    ds.send(new DatagramPacket(p, p.length, a, udpPort));
                    String rep;
                    try {
                        ds.setSoTimeout(2000);
                        byte[] rb = new byte[1500];
                        DatagramPacket rp = new DatagramPacket(rb, rb.length);
                        ds.receive(rp);
                        String echo = new String(rb, 0, rp.getLength());
                        rep = String.format("echo_from=%s len=%d rtt=%.1fms match=%b", rp.getSocketAddress(), rp.getLength(),
                                (System.nanoTime() - t0) / 1e6, echo.equals(new String(p)));
                    } catch (java.net.SocketTimeoutException e) { rep = "no_echo(2s)"; }
                    out(String.format("udp#%d -> %s:%d len=%d local=%s %s", n, host, udpPort, p.length, ds.getLocalSocketAddress(), rep));
                    sleep(200);
                }
            } catch (Exception e) {
                out("udp error " + e);
            }
            out("done");
        }, "gen").start();
    }

    private static String str(Intent i, String k, String d) { String v = i.getStringExtra(k); return v != null ? v : d; }
    private static void sleep(long ms) { try { Thread.sleep(ms); } catch (InterruptedException ignored) {} }
}
