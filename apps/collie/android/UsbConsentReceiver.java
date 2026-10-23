package org.flexscript.collie;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/** Private, explicit immutable PendingIntent callback. Actual USB grants are rechecked. */
public final class UsbConsentReceiver extends BroadcastReceiver {
    @Override public void onReceive(Context context,Intent intent){
        if(intent!=null&&"org.flexscript.collie.USB_PERMISSION".equals(intent.getAction())){
            String token=intent.getStringExtra("token");if(token!=null)HardwareConsent.usbResult(token);
        }
    }
}
