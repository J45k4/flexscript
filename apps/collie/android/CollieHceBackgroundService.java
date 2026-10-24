package org.flexscript.collie;

import android.nfc.cardemulation.HostApduService;
import android.os.*;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.*;
import org.json.*;

/** System-bound ISO-DEP endpoint. Its VM has a process separate from the Activity. */
public class CollieHceBackgroundService extends HostApduService {
    static{System.loadLibrary("collie");}
    private static native long nativeCall(long op,ByteBuffer input,long size,ByteBuffer output,ByteBuffer root);
    private static native void nativeCancel();
    private static native void nativeBegin();
    private static final Object ENGINE=new Object();
    private static final Object RUNNING=new Object();
    private static CollieHceBackgroundService running;
    final Handler main=new Handler(Looper.getMainLooper());
    final ThreadPoolExecutor worker=new ThreadPoolExecutor(1,1,30,TimeUnit.SECONDS,new ArrayBlockingQueue<Runnable>(1));
    volatile long generation;boolean destroyed;
    final String instance=UUID.randomUUID().toString();
    int category(){return 0;}
    public void onCreate(){super.onCreate();try{HardwareHceBackground.locked(this,(f,r)->{if(r!=null&&r.getInt("category")==category()){
        // Android creates one instance of this fixed component. A new actual
        // instance proves the old instance ended, even after process death
        // prevented its onDestroy callback.
        r.put("channel_active",false).put("channel_instance",instance).put("channel_pid",android.os.Process.myPid());
        if(r.getString("state").equals("awaiting_deactivation")&&r.optBoolean("routes_removed"))HardwareHceBackground.erase(f);else HardwareHceBackground.store(f,r);
    }return null;});}catch(Exception unavailable){}}
    static ByteBuffer buffer(byte[] bytes,boolean nul){ByteBuffer b=ByteBuffer.allocateDirect(bytes.length+(nul?1:0));b.put(bytes);if(nul)b.put((byte)0);b.rewind();return b;}
    void cancelOwned(){synchronized(RUNNING){if(running==this)nativeCancel();}}
    void expired(JSONObject profile,long token){
        if(destroyed||generation!=token)return;generation++;cancelOwned();
        try{HardwareHceBackground.change(this,profile.getString("id"),(f,r)->{if(r.getString("state").equals("ready")&&r.getLong("revision")==profile.getLong("revision")){r.put("last_submission","deadline_expired").put("last_error","Card transaction deadline expired before reply submission.");HardwareHceBackground.store(f,r);}return null;});}catch(Exception ignored){}
        notifyUnhandled();
    }
    JSONObject execute(JSONObject profile,byte[] command,long token,long deadline)throws Exception{
        JSONArray parts=new JSONArray();for(int i=0;i<command.length;i+=32768)parts.put(VmHardware.bytes(Arrays.copyOfRange(command,i,Math.min(command.length,i+32768))));
        JSONObject request=new JSONObject().put("source",profile.getString("source")).put("input",parts).put("saved_state",profile.get("saved_state"));
        byte[] input=request.toString().getBytes(StandardCharsets.UTF_8);ByteBuffer output=ByteBuffer.allocateDirect(8*1024*1024);
        synchronized(ENGINE){synchronized(RUNNING){if(generation!=token||SystemClock.elapsedRealtime()>=deadline)throw new java.io.IOException("Card callback expired before execution.");running=this;nativeBegin();}
            try{long n=nativeCall(10,buffer(input,true),input.length,output,buffer(profile.getString("root").getBytes(StandardCharsets.UTF_8),true));if(n<0||n>output.capacity())throw new java.io.IOException("Card callback engine failed: "+n);byte[] bytes=new byte[(int)n];output.get(bytes);return new JSONObject(new String(bytes,StandardCharsets.UTF_8));}
            finally{synchronized(RUNNING){if(running==this)running=null;}}
        }
    }
    public byte[] processCommandApdu(byte[] command,Bundle extras){
        long received=SystemClock.elapsedRealtime(),token=++generation;cancelOwned();worker.getQueue().clear();main.removeCallbacksAndMessages(null);
        if(destroyed||command==null||command.length<4||command.length>65544)return new byte[]{0x6f,0};
        try{
            JSONObject profile=HardwareHceBackground.snapshot(this);
            if(profile==null||profile.getInt("category")!=category())return new byte[]{0x6f,0};
            HardwareHceBackground.change(this,profile.getString("id"),(f,r)->{r.put("channel_active",true).put("channel_instance",instance).put("channel_pid",android.os.Process.myPid());HardwareHceBackground.store(f,r);return null;});
            if(!profile.getString("state").equals("ready")||!HardwareHceBackground.authorized(profile))return new byte[]{0x6f,0};
            byte[] copy=command.clone();long deadline=received+profile.getInt("timeout_ms");
            Runnable expired=()->expired(profile,token);
            main.postDelayed(expired,Math.max(0,deadline-SystemClock.elapsedRealtime()));
            worker.execute(()->{
                if(generation!=token||SystemClock.elapsedRealtime()>=deadline)return;
                JSONObject result=null;Exception failure=null;
                try{result=execute(profile,copy,token,deadline);}catch(Exception error){failure=error;}
                JSONObject observation=result;Exception error=failure;
                main.post(()->{if(destroyed||generation!=token)return;if(SystemClock.elapsedRealtime()>=deadline){expired(profile,token);return;}main.removeCallbacks(expired);
                    boolean[] submitted={false};
                    try{if(error!=null)throw error;if(!observation.optBoolean("ok")){String detail=observation.optString("error",observation.optString("stderr",""));if(detail.isEmpty())detail="No complete reply was committed.";throw new java.io.IOException("Card handler failed (exit "+observation.optInt("exit_code",-1)+"): "+detail);}
                        JSONArray chunks=observation.getJSONArray("response");java.io.ByteArrayOutputStream bytes=new java.io.ByteArrayOutputStream();for(int i=0;i<chunks.length();i++){byte[] part=VmHardware.data(chunks.get(i));if(part.length>65538-bytes.size())throw new java.io.IOException("Oversized card reply.");bytes.write(part);}byte[] reply=bytes.toByteArray();if(reply.length<2)throw new java.io.IOException("Short card reply.");
                        HardwareHceBackground.locked(this,(file,current)->{
                            if(current==null||!current.getString("id").equals(profile.getString("id"))||!current.getString("state").equals("ready")||current.getLong("revision")!=profile.getLong("revision")||!HardwareHceBackground.authorized(current)||generation!=token||SystemClock.elapsedRealtime()>=deadline)return null;
                            // State is durable before SDK submission. A crash or
                            // link loss can leave peer receipt unknown; never
                            // replay a previous response on a later command.
                            current.put("saved_state",observation.get("saved_state")).put("revision",current.getLong("revision")+1).put("handler_compiled",true).put("last_submission","prepared").put("last_error","");HardwareHceBackground.store(file,current);
                            if(generation!=token||SystemClock.elapsedRealtime()>=deadline){current.put("last_submission","expired_after_state_commit");HardwareHceBackground.store(file,current);if(generation==token)notifyUnhandled();return null;}
                            submitted[0]=true;try{sendResponseApdu(reply);current.put("last_submission","sdk_returned");}catch(Exception send){current.put("last_submission","send_failed").put("last_error",send.toString());}
                            HardwareHceBackground.store(file,current);return null;
                        });
                    }catch(Exception failed){try{HardwareHceBackground.change(this,profile.getString("id"),(f,r)->{r.put("last_error",failed.toString());HardwareHceBackground.store(f,r);return null;});}catch(Exception ignored){}if(generation==token&&!submitted[0])notifyUnhandled();}
                });
            });return null;
        }catch(Exception error){return new byte[]{0x6f,0};}
    }
    public void onDeactivated(int reason){generation++;cancelOwned();worker.getQueue().clear();main.removeCallbacksAndMessages(null);try{HardwareHceBackground.terminal(this,category(),instance);}catch(Exception ignored){}}
    public void onDestroy(){destroyed=true;generation++;cancelOwned();worker.shutdownNow();main.removeCallbacksAndMessages(null);try{HardwareHceBackground.terminal(this,category(),instance);}catch(Exception ignored){}super.onDestroy();}
}
