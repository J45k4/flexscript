package org.flexscript.collie;

import android.content.*;
import android.content.pm.PackageManager;
import android.app.ActivityManager;
import android.nfc.NfcAdapter;
import android.nfc.cardemulation.CardEmulation;
import android.os.SystemClock;
import android.util.AtomicFile;
import java.io.*;
import java.nio.channels.FileLock;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.RejectedExecutionException;
import org.json.*;

/** Durable SDK routing/ownership transport. APDU behavior runs in the separate VM process. */
final class HardwareHceBackground {
    static final Object FILES=new Object();
    static final String INSTANCE=UUID.randomUUID().toString();
    interface Locked<T>{T run(AtomicFile file,JSONObject record)throws Exception;}
    static <T>T locked(android.content.Context context,Locked<T> action)throws Exception{
        synchronized(FILES){try(RandomAccessFile guard=new RandomAccessFile(new File(context.getFilesDir(),"hce-background.lock"),"rw");FileLock held=guard.getChannel().lock()){
            AtomicFile file=new AtomicFile(new File(context.getFilesDir(),"hce-background.json"));JSONObject record=null;
            try(FileInputStream input=file.openRead()){record=new JSONObject(read(input,524288));}catch(FileNotFoundException absent){}
            if(record!=null)validate(context,record);return action.run(file,record);
        }}
    }
    static String read(InputStream input,int limit)throws Exception{ByteArrayOutputStream out=new ByteArrayOutputStream();byte[] b=new byte[4096];int n;while((n=input.read(b))!=-1){if(n>limit-out.size())throw new IOException("Card callback record exceeds its storage bound.");out.write(b,0,n);}return out.toString("UTF-8");}
    static void store(AtomicFile file,JSONObject record)throws Exception{
        byte[] bytes=record.toString().getBytes(StandardCharsets.UTF_8);if(bytes.length>524288)throw new IOException("Card callback record exceeds its storage bound.");
        FileOutputStream output=null;try{output=file.startWrite();output.write(bytes);file.finishWrite(output);}catch(Exception error){if(output!=null)file.failWrite(output);throw error;}
    }
    static void validate(android.content.Context app,JSONObject r)throws Exception{
        File base=new File(app.getFilesDir(),"workspaces").getCanonicalFile(),root=new File(r.getString("root")).getCanonicalFile();
        if(r.getInt("version")!=1||!root.getParentFile().equals(base)||!root.getName().matches("[A-Za-z0-9-]{1,80}")||!r.getString("id").matches("card-[0-9a-f-]{36}")||r.getInt("category")<0||r.getInt("category")>1||r.getString("source").length()>32768||r.getInt("timeout_ms")<100||r.getInt("timeout_ms")>5000)throw new IOException("Invalid background card ownership record; retain it for explicit recovery.");
        HardwareHce.aids(r.getJSONArray("aids"));r.getString("state");r.getLong("revision");r.get("saved_state");
    }
    static boolean authorized(JSONObject r){
        // Read a fresh atomic snapshot on every command/commit, not cached
        // cross-process SharedPreferences or a stale foreground configuration.
        try{File saved=new File(r.getString("root"),"session.json");try(FileInputStream input=new AtomicFile(saved).openRead()){JSONObject s=new JSONObject(read(input,8388608));return Boolean.TRUE.equals(s.getJSONObject("permissions").opt("nfc"));}}catch(Exception unavailable){return false;}
    }
    static ComponentName component(android.content.Context c,int category){return new ComponentName(c.getPackageName(),c.getPackageName()+"."+(category==0?"CollieHceBackgroundService":"CollieHceBackgroundPaymentService"));}
    static boolean owned(android.content.Context c){try{return locked(c,(f,r)->r!=null);}catch(Exception uncertain){return true;}}
    static JSONObject snapshot(android.content.Context c)throws Exception{return locked(c,(f,r)->r==null?null:new JSONObject(r.toString()));}
    static JSONObject status(VmHardware.Context c)throws Exception{
        return locked(c.host,(f,r)->{if(r==null||!c.root.getCanonicalPath().equals(r.getString("root")))return VmHardware.object("owned",false);
            if(r.getString("state").equals("registering")&&(!INSTANCE.equals(r.optString("startup_instance"))||SystemClock.elapsedRealtime()>=r.optLong("startup_deadline_elapsed_ms"))){r.put("state","recovery_required").put("last_error","Registration startup expired or its process ended; explicitly remove and inspect actual SDK cleanup before reinstalling.");store(f,r);}
            return VmHardware.object("owned",true,"id",r.getString("id"),"state",r.getString("state"),"category",r.getInt("category"),"aids",r.getJSONArray("aids"),"channel_active",r.optBoolean("channel_active"),"routes_removed",r.optBoolean("routes_removed"),"registration_attempted",r.optBoolean("registration_attempted"),"registration_acknowledged",r.optBoolean("registration_acknowledged"),"handler_compiled",r.optBoolean("handler_compiled"),"revision",r.getLong("revision"),"last_submission",r.optString("last_submission","none"),"last_error",r.optString("last_error",""),"peer_receipt_verified",false);});
    }
    static void change(android.content.Context c,String id,Locked<Void> action)throws Exception{locked(c,(f,r)->{if(r!=null&&id.equals(r.getString("id")))action.run(f,r);return null;});}
    static void submit(android.content.Context c,String id,boolean remove)throws Exception{
        try{HardwareHce.SDK.execute(()->{try{if(remove)cleanup(c,id);else register(c,id);}catch(Exception error){try{change(c,id,(f,r)->{r.put("state",remove?"cleanup_error":"error").put("last_error",MainActivity.safe(error));store(f,r);return null;});}catch(Exception ignored){}}});}
        catch(RejectedExecutionException error){throw new VmHardware.Failure("busy","NFC SDK executor is full; durable ownership is retained for explicit removal.");}
    }
    static void readyToRegister(android.content.Context c,String id)throws Exception{
        locked(c,(f,r)->{if(r==null||!id.equals(r.getString("id"))||!r.getString("state").equals("registering")||!INSTANCE.equals(r.optString("startup_instance"))||SystemClock.elapsedRealtime()>=r.getLong("startup_deadline_elapsed_ms")||!authorized(r))throw new VmHardware.Failure("cancelled","Background card registration was removed, expired or its NFC permission changed.");return null;});
    }
    static void register(android.content.Context c,String id)throws Exception{
        JSONObject r=snapshot(c);if(r==null||!id.equals(r.getString("id")))return;int category=r.getInt("category");ComponentName name=component(c,category);
        readyToRegister(c,id);NfcAdapter adapter=NfcAdapter.getDefaultAdapter(c);if(!HardwareHce.supported(c,adapter,0)||!adapter.isEnabled())throw new VmHardware.Failure("unsupported","An enabled ISO-DEP HCE adapter is required.");
        c.getPackageManager().setComponentEnabledSetting(name,PackageManager.COMPONENT_ENABLED_STATE_ENABLED,PackageManager.DONT_KILL_APP);
        CardEmulation sdk=CardEmulation.getInstance(adapter);ArrayList<String> aids=HardwareHce.aids(r.getJSONArray("aids"));
        for(String aid:aids)if(aid.endsWith("*")&&!sdk.supportsAidPrefixRegistration())throw new VmHardware.Failure("unsupported_operation","Android does not support AID prefixes.");
        change(c,id,(f,current)->{if(!current.getString("state").equals("registering")||!authorized(current))throw new VmHardware.Failure("cancelled","Registration ended before submission.");current.put("registration_attempted",true);store(f,current);return null;});
        long deadline=SystemClock.elapsedRealtime()+3000;boolean accepted=false;
        while(!accepted){readyToRegister(c,id);accepted=sdk.registerAidsForService(name,HardwareHce.category(category),aids);if(!accepted){if(SystemClock.elapsedRealtime()>=deadline)throw new VmHardware.Failure("routing_denied","Android rejected background AID registration.");Thread.sleep(50);}}
        change(c,id,(f,current)->{if(!current.getString("state").equals("registering")||SystemClock.elapsedRealtime()>=current.getLong("startup_deadline_elapsed_ms")||!authorized(current))throw new VmHardware.Failure("cancelled","Registration ended before its SDK acknowledgement.");current.put("state","ready").put("registration_acknowledged",true);store(f,current);return null;});
        // No Activity preference or wallet/default change: Android owns routing.
    }
    static void cleanup(android.content.Context c,String id)throws Exception{
        JSONObject r=snapshot(c);if(r==null||!id.equals(r.getString("id")))return;int category=r.getInt("category");ComponentName name=component(c,category);String error="";
        try{NfcAdapter adapter=NfcAdapter.getDefaultAdapter(c);if(HardwareHce.supported(c,adapter,0)){CardEmulation sdk=CardEmulation.getInstance(adapter);if(sdk.getAidsForService(name,HardwareHce.category(category))!=null&&!sdk.removeAidsForService(name,HardwareHce.category(category)))throw new IOException("Android did not remove the background AID registration.");}else if(r.optBoolean("registration_attempted")||r.optBoolean("registration_acknowledged"))throw new IOException("NFC adapter unavailable; retain registration ownership until SDK cleanup can be checked.");}catch(Exception failure){error=MainActivity.safe(failure);}
        try{c.getPackageManager().setComponentEnabledSetting(name,PackageManager.COMPONENT_ENABLED_STATE_DEFAULT,PackageManager.DONT_KILL_APP);}catch(Exception failure){error=MainActivity.safe(failure);}
        final String failed=error;change(c,id,(f,current)->{if(failed.isEmpty()){
                current.put("routes_removed",true);
                if(current.optBoolean("channel_active")&&!processEnded(c,current.optInt("channel_pid",-1))){current.put("state","awaiting_deactivation");store(f,current);}
                else erase(f);
            }else{current.put("state","cleanup_error").put("last_error",failed);store(f,current);}return null;});
    }
    static void erase(AtomicFile file)throws Exception{file.delete();if(file.getBaseFile().exists())throw new IOException("Could not remove the durable card ownership record.");}
    static boolean processEnded(android.content.Context c,int pid){
        if(pid<=0)return false;ActivityManager manager=c.getSystemService(ActivityManager.class);if(manager==null)return false;
        List<ActivityManager.RunningAppProcessInfo> processes=manager.getRunningAppProcesses();if(processes==null)return false;
        for(ActivityManager.RunningAppProcessInfo process:processes)if(process.pid==pid&&process.uid==android.os.Process.myUid()&&process.processName.equals(c.getPackageName()+":hce_background"))return false;return true;
    }
    static void terminal(android.content.Context c,int category,String instance)throws Exception{
        locked(c,(f,r)->{if(r!=null&&r.getInt("category")==category&&instance.equals(r.optString("channel_instance"))){r.put("channel_active",false);if(r.getString("state").equals("awaiting_deactivation")&&r.optBoolean("routes_removed"))erase(f);else store(f,r);}return null;});
    }
    static void revoke(android.content.Context c,File root)throws Exception{
        String id=locked(c,(f,r)->{if(r==null||root!=null&&!root.getCanonicalPath().equals(r.getString("root")))return null;r.put("state","removing");store(f,r);return r.getString("id");});
        if(id!=null)submit(c.getApplicationContext(),id,true);
    }
    static Object call(VmHardware.Context c,String op,JSONArray a)throws Exception{
        if(op.equals("hce_background_status"))return status(c);
        if(op.equals("hce_background_state"))return locked(c.host,(f,r)->{if(r==null||!c.root.getCanonicalPath().equals(r.getString("root")))throw new VmHardware.Failure("stale_registration","No background card is owned by this conversation.");return r.get("saved_state");});
        if(op.equals("hce_background_remove")){String id=VmHardware.text(a,0,80);locked(c.host,(f,r)->{if(r==null||!id.equals(r.getString("id"))||!c.root.getCanonicalPath().equals(r.getString("root")))throw new VmHardware.Failure("stale_registration","Unknown background card registration for this conversation.");r.put("state","removing");store(f,r);return null;});submit(c.host.getApplicationContext(),id,true);return 1;}
        int category=VmHardware.integer(a,0,0,1),timeout=VmHardware.integer(a,4,100,5000);ArrayList<String> aids=HardwareHce.aids(a.get(1));String source=VmHardware.text(a,2,32768);if(source.trim().isEmpty())throw new VmHardware.Failure("invalid_argument","Install a complete Flexscript callback program.");
        HardwareHce.visible(c);NfcAdapter adapter=HardwareNfc.optional(c);if(!HardwareHce.supported(c.host,adapter,0))throw new VmHardware.Failure("unsupported","Android has no ISO-DEP host card emulation adapter.");if(!adapter.isEnabled())throw new VmHardware.Failure("nfc_disabled","Enable NFC before installing a background card.");
        JSONObject record=VmHardware.object("version",1,"id","card-"+UUID.randomUUID(),"root",c.root.getCanonicalPath(),"category",category,"aids",new JSONArray(aids),"source",source,"saved_state",a.get(3),"timeout_ms",timeout,"state","registering","revision",0,"registration_acknowledged",false,"handler_compiled",false,"startup_instance",INSTANCE,"startup_deadline_elapsed_ms",SystemClock.elapsedRealtime()+10000);
        synchronized(HardwareNfc.LEASE){if(HardwareHce.owner!=null||HardwareNfc.readerOwned())throw new VmHardware.Failure("busy","Close the live NFC reader/card lease first.");locked(c.host,(f,r)->{if(r!=null)throw new VmHardware.Failure("busy","Remove the existing durable background card and wait for actual SDK cleanup first.");if(!authorized(record))throw new VmHardware.Failure("permission_denied","Save an explicit NFC Allow choice before installing a durable callback.");store(f,record);return null;});}
        submit(c.host.getApplicationContext(),record.getString("id"),false);return record.getString("id");
    }
}
