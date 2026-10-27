package androidx.core.uwb.backend.fixture;

import android.content.*;
import android.database.Cursor;
import android.net.Uri;
import android.os.*;
import org.json.*;

/** Signature protected fixture controls, absent from the Collie APK. */
public final class UwbProtocolControl extends ContentProvider {
    public boolean onCreate(){return true;}
    public Bundle call(String method,String arg,Bundle extras){getContext().enforceCallingPermission("org.flexscript.collie.uwbfixture.CONTROL","Fixture controller only");try{
        if(method.equals("configure")){synchronized(UwbProtocolFixture.CLIENTS){UwbProtocolFixture.mode=arg;}}
        else if(method.equals("release"))UwbProtocolFixture.client(Integer.parseInt(arg)).release.countDown();
        else if(method.equals("emit"))UwbProtocolFixture.client(extras.getInt("client")).emit(arg);
        else if(method.equals("die"))new Handler(Looper.getMainLooper()).postDelayed(()->android.os.Process.killProcess(android.os.Process.myPid()),100);
        else if(!method.equals("snapshot"))throw new IllegalArgumentException("Unknown fixture command");
        JSONArray clients=new JSONArray();JSONObject value;
        synchronized(UwbProtocolFixture.CLIENTS){for(UwbProtocolFixture.Client c:UwbProtocolFixture.CLIENTS)clients.put(c.info());value=new JSONObject().put("clients",clients).put("binds",UwbProtocolFixture.binds).put("unbinds",UwbProtocolFixture.unbinds).put("constructed_protocol_provider",true).put("physical_ranging_verified",false);}
        Bundle out=new Bundle();out.putString("json",value.toString());return out;
    }catch(Exception e){throw new IllegalStateException(e);}}
    public Cursor query(Uri u,String[] p,String s,String[] a,String o){return null;}
    public String getType(Uri u){return null;}public Uri insert(Uri u,ContentValues v){throw new UnsupportedOperationException();}
    public int delete(Uri u,String s,String[] a){throw new UnsupportedOperationException();}public int update(Uri u,ContentValues v,String s,String[] a){throw new UnsupportedOperationException();}
}
