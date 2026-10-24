package org.flexscript.collie;

import android.nfc.cardemulation.HostNfcFService;
import android.os.Bundle;

/** Android NFC-F service; protocol responses remain opaque guest bytes. */
public final class CollieHceFService extends HostNfcFService implements HardwareHce.Endpoint {
    HardwareHce.Session session;
    public void onCreate(){super.onCreate();HardwareHce.serviceCreated(this,2);}
    public byte[] processNfcFPacket(byte[] command,Bundle extras){
        if(session==null)session=HardwareHce.current(2);
        if(session!=null)session.incoming(command,this);
        return null;
    }
    public void response(byte[] bytes){sendResponsePacket(bytes);}
    public void unhandled(){throw new UnsupportedOperationException("NFC-F has no public notifyUnhandled method.");}
    public void onDeactivated(int reason){HardwareHce.Session s=session;session=null;if(s!=null)s.deactivated(this,reason,false);}
    public void onDestroy(){HardwareHce.Session s=session;session=null;if(s!=null)s.deactivated(this,-1,true);super.onDestroy();}
}
