package id.magnon.poc.examine;

import android.app.Activity;
import android.content.Intent;
import android.net.VpnService;
import android.os.Bundle;
import android.util.Log;
import android.widget.TextView;

/** Start/stop VPN. adb: am start -n id.magnon.poc.examine/.MainActivity [--es cmd stop] */
public class MainActivity extends Activity {
    private TextView tv;
    private Intent pending;

    @Override protected void onCreate(Bundle b) {
        super.onCreate(b);
        tv = new TextView(this);
        tv.setTextSize(16);
        tv.setPadding(32, 64, 32, 32);
        setContentView(tv);
        handle(getIntent());
    }

    @Override protected void onNewIntent(Intent i) { super.onNewIntent(i); handle(i); }

    private void handle(Intent i) {
        String cmd = i != null ? i.getStringExtra("cmd") : null;
        Log.i(ExamineVpnService.TAG, "MainActivity cmd=" + cmd);
        if ("stop".equals(cmd)) {
            ExamineVpnService svc = ExamineVpnService.instance;
            if (svc != null) svc.stopVpn("MainActivity");
            else Log.i(ExamineVpnService.TAG, "stop: service tidak berjalan");
            tv.setText("Magnon PoC Examine\nVPN: stop requested");
            return;
        }
        pending = i;
        Intent p = VpnService.prepare(this);
        if (p != null) { tv.setText("Magnon PoC Examine\nmeminta izin VPN..."); startActivityForResult(p, 1); }
        else onActivityResult(1, RESULT_OK, null);
    }

    @Override protected void onActivityResult(int req, int res, Intent d) {
        if (res == RESULT_OK) {
            Intent si = new Intent(this, ExamineVpnService.class).setAction(ExamineVpnService.ACTION_START);
            if (pending != null && pending.getStringExtra("apps") != null) si.putExtra("apps", pending.getStringExtra("apps"));
            if (pending != null && pending.getStringExtra("dns") != null) si.putExtra("dns", pending.getStringExtra("dns"));
            startService(si);
            tv.setText("Magnon PoC Examine v" + ExamineVpnService.VERSION + " (mode examine)\nVPN dummy: START\nroute 0.0.0.0/0, MTU 1400, DNS via forwarder\nallowed app: " + getPackageName()
                    + " + com.android.chrome\nmarker MGLT v1 -> " + ExamineVpnService.MARK_HOST + ":" + ExamineVpnService.MARK_PORT
                    + "\nlog tag: " + ExamineVpnService.TAG);
        } else {
            Log.w(ExamineVpnService.TAG, "vpn consent denied");
            tv.setText("Izin VPN ditolak");
        }
    }
}
