package id.magnon.poc.examine;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.util.Log;

/** adb: am broadcast -n id.magnon.poc.examine/.StopReceiver */
public class StopReceiver extends BroadcastReceiver {
    @Override public void onReceive(Context c, Intent i) {
        ExamineVpnService svc = ExamineVpnService.instance;
        if (svc != null) svc.stopVpn("broadcast");
        else Log.i(ExamineVpnService.TAG, "stop broadcast: service tidak berjalan");
    }
}
