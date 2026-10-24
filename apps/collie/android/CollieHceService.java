package org.flexscript.collie;

import android.nfc.cardemulation.HostApduService;
import android.os.Bundle;

/** Android's ISO-DEP service. Command bytes go only to the currently owned VM lease. */
public class CollieHceService extends HostApduService implements HardwareHce.Endpoint {
    HardwareHce.Session session;
    int mode(){return 0;}
    public void onCreate(){super.onCreate();HardwareHce.serviceCreated(this,mode());}
    public byte[] processCommandApdu(byte[] command,Bundle extras){
        if(session==null)session=HardwareHce.current(mode());
        if(session==null||!session.incoming(command,this))return new byte[]{0x6f,0};
        return null;
    }
    public void response(byte[] bytes){sendResponseApdu(bytes);}
    public void unhandled(){notifyUnhandled();}
    public void onDeactivated(int reason){HardwareHce.Session s=session;session=null;if(s!=null)s.deactivated(this,reason,false);}
    public void onDestroy(){HardwareHce.Session s=session;session=null;if(s!=null)s.deactivated(this,-1,true);super.onDestroy();}
}
