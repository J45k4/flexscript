package org.flexscript.collie;

import android.app.Service;
import android.content.Intent;
import android.os.*;

/** Debug-only separate-process peer. It relays constructed SDK messages, never NFC radio I/O. */
public final class HardwareHcePeerFixture extends Service {
    public IBinder onBind(Intent intent){
        // Each unique bind Intent owns its own relay. Old SDK responses cannot
        // be delivered to a later test's receiver after its token is replaced.
        final Messenger[] relay=new Messenger[1];
        Handler handler=new Handler(Looper.getMainLooper(),message->{
            try{if(message.what==100&&relay[0]==null){relay[0]=message.replyTo;relay[0].send(Message.obtain(null,100));}
                else if(message.what==101&&relay[0]!=null){
                    // Cross the separate-process boundary before delivering a
                    // constructed polling-frame message to the actual SDK service.
                    Messenger destination=message.replyTo;Message polling=Message.obtain(message);
                    polling.what=4;polling.replyTo=relay[0];destination.send(polling);
                }
                else if(relay[0]!=null)relay[0].send(Message.obtain(message));
            }catch(RemoteException ignored){}return true;
        });
        return new Messenger(handler).getBinder();
    }
}
