package org.flexscript.collie;

import android.content.Context;
import android.nfc.NfcAdapter;
import android.nfc.cardemulation.CardEmulation;
import android.os.Build;
import android.os.SystemClock;
import android.util.AtomicFile;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.RejectedExecutionException;
import java.util.regex.Pattern;
import org.json.*;

/** Public SDK mutations and their owned routing journal; no guest policy here. */
final class HardwareHceControls {
    static final int MAX_FILTERS=16, MAX_RESULTS=16, MAX_FILTER_TEXT=512, JOURNAL_BYTES=32768;
    static final Object JOURNAL_LOCK=new Object();
    final HardwareHce.Session session;
    final String lease="hce-lease-"+UUID.randomUUID();
    final LinkedHashMap<String,Entry> filters=new LinkedHashMap<>();
    final LinkedHashMap<String,Request> results=new LinkedHashMap<>();
    Request pending;

    HardwareHceControls(HardwareHce.Session session){this.session=session;}
    static String filter(int kind,String text)throws Exception {
        String value=text.toUpperCase(Locale.ROOT);
        if(value.length()<2||value.length()>MAX_FILTER_TEXT)throw new VmHardware.Failure("invalid_argument","Use a polling filter of2..512 characters.");
        if(kind==0){if((value.length()&1)!=0||!value.matches("[0-9A-F]+"))throw new VmHardware.Failure("invalid_argument","Exact polling filters must contain complete hexadecimal bytes.");}
        else if(kind==1){if(!value.matches("[0-9A-F]{2,}[0-9A-F.?*]*"))throw new VmHardware.Failure("invalid_argument","Pattern filters start with a literal byte and contain only hexadecimal digits and . ? * operators.");Pattern.compile(value);}
        else throw new VmHardware.Failure("invalid_argument","Polling filter kind is0 exact or1 pattern.");
        return value;
    }
    static final class Entry {
        final int mode,kind;final String filter,lease;final boolean automatic;
        boolean attempted;Boolean accepted;
        Entry(int mode,int kind,String filter,String lease,boolean automatic){this.mode=mode;this.kind=kind;this.filter=filter;this.lease=lease;this.automatic=automatic;}
        String key(){return kind+":"+filter;}
        JSONObject record()throws Exception{return VmHardware.object("mode",mode,"kind",kind,"filter",filter,"lease",lease);}
        JSONObject value()throws Exception{return VmHardware.object("kind",kind,"filter",filter,"auto_transact_requested",automatic,"sdk_registration_attempted",attempted,"last_sdk_boolean",accepted==null?JSONObject.NULL:accepted);}
    }
    static final class Request {
        final String id="hce-control-"+UUID.randomUUID(),operation;
        final long expires;final Entry entry,previous;final boolean enabled;
        String state="queued",code="",error="",cleanupError="";boolean sent,returned,done,expired,notSubmitted,journaled;Boolean accepted;
        JSONObject operationError;
        Runnable timer;
        Request(String operation,Entry entry,Entry previous,boolean enabled,int timeout){this.operation=operation;this.entry=entry;this.previous=previous;this.enabled=enabled;expires=SystemClock.elapsedRealtime()+timeout;}
        JSONObject value()throws Exception{return VmHardware.object("id",id,"operation",operation,"arguments",entry==null?VmHardware.object("enabled",enabled):VmHardware.object("kind",entry.kind,"filter",entry.filter,"auto_transact_requested",entry.automatic),"state",state,"deadline_elapsed_ms",expires,"expired",expired,"worker_done",done,"sdk_call_started",sent,"sdk_call_returned",returned,"sdk_boolean",accepted==null?JSONObject.NULL:accepted,"sdk_not_submitted",notSubmitted,"code",code,"message",error,"cleanup_error",cleanupError,"operation_error",operationError==null?JSONObject.NULL:operationError);}
    }

    static File journal(Context context){return new File(context.getApplicationContext().getFilesDir(),"hce-polling-leases.json");}
    static boolean exists(File file){return file.exists()||new File(file.getPath()+".bak").exists();}
    // File overloads keep format/atomic-I/O checks independent of any NFC adapter.
    static JSONArray read(File file)throws Exception {
        if(!exists(file))return new JSONArray();
        try {
            JSONObject data=new JSONObject(MainActivity.read(new AtomicFile(file).openRead(),JOURNAL_BYTES));
            if(!(data.get("version") instanceof Integer)||data.getInt("version")!=1)throw new IOException("Unknown NFC polling journal version.");
            JSONArray rows=data.getJSONArray("entries");if(rows.length()>MAX_FILTERS)throw new IOException("Too many NFC polling journal entries.");
            HashSet<String> keys=new HashSet<>();
            for(int i=0;i<rows.length();i++){
                JSONObject row=rows.getJSONObject(i);int mode=number(row,"mode",0,1),kind=number(row,"kind",0,1);
                String text=row.getString("filter"),lease=row.getString("lease");
                if(!filter(kind,text).equals(text)||!lease.matches("hce-lease-[0-9a-fA-F-]{36}")||!keys.add(mode+":"+kind+":"+text))throw new IOException("Invalid or duplicate NFC polling ownership entry.");
            }
            return rows;
        }catch(Exception error){throw new VmHardware.Failure("recovery_required","Cannot read the NFC polling ownership journal: "+MainActivity.safe(error));}
    }
    static int number(JSONObject row,String key,int min,int max)throws Exception{return VmHardware.integer(new JSONArray().put(row.get(key)),0,min,max);}
    static void write(File file,JSONArray rows)throws Exception {
        String text=VmHardware.object("version",1,"entries",rows).toString();
        if(text.getBytes(StandardCharsets.UTF_8).length>JOURNAL_BYTES)throw new VmHardware.Failure("resource_limit","NFC polling ownership journal exceeds32KiB.");
        AtomicFile atomic=new AtomicFile(file);FileOutputStream stream=null;
        try{
            stream=atomic.startWrite();stream.write(text.getBytes(StandardCharsets.UTF_8));
            stream.getFD().sync();atomic.finishWrite(stream);stream=null;
            // AtomicFile may log a failed rename instead of throwing. Never
            // mutate SDK routing until the committed record reads back exactly.
            if(!text.equals(MainActivity.read(atomic.openRead(),JOURNAL_BYTES)))throw new IOException("NFC polling journal commit did not verify.");
        }catch(Exception error){if(stream!=null)atomic.failWrite(stream);throw error;}
    }
    static boolean matches(JSONObject row,Entry e)throws Exception{return row.getInt("mode")==e.mode&&row.getInt("kind")==e.kind&&row.getString("filter").equals(e.filter);}
    static void remember(Context context,Entry entry)throws Exception {
        synchronized(JOURNAL_LOCK){File file=journal(context);JSONArray rows=read(file);
            for(int i=0;i<rows.length();i++){JSONObject row=rows.getJSONObject(i);if(matches(row,entry)){if(!row.getString("lease").equals(entry.lease))throw new VmHardware.Failure("recovery_required","That polling filter still belongs to a different NFC lease.");return;}}
            if(rows.length()>=MAX_FILTERS)throw new VmHardware.Failure("resource_limit","At most16 polling filters may be owned by Collie.");
            rows.put(entry.record());write(file,rows);
        }
    }
    static void forget(Context context,Entry entry)throws Exception {
        synchronized(JOURNAL_LOCK){File file=journal(context);JSONArray rows=read(file),keep=new JSONArray();
            for(int i=0;i<rows.length();i++){JSONObject row=rows.getJSONObject(i);if(!(matches(row,entry)&&row.getString("lease").equals(entry.lease)))keep.put(row);}
            if(keep.length()!=rows.length())write(file,keep);
        }
    }
    static void recover(Context context,NfcAdapter adapter,int mode,String lease)throws Exception {
        JSONArray owned=new JSONArray();synchronized(JOURNAL_LOCK){JSONArray rows=read(journal(context));for(int i=0;i<rows.length();i++){JSONObject row=rows.getJSONObject(i);if(row.getInt("mode")==mode&&(lease==null||row.getString("lease").equals(lease)))owned.put(row);}}
        if(owned.length()==0)return;
        if(Build.VERSION.SDK_INT<35||!HardwareHce.supported(context,adapter,mode))throw new VmHardware.Failure("recovery_required","NFC polling cleanup is pending because its public adapter/API is unavailable; ownership records were retained.");
        // A crashed or previously failed cleanup may have disabled the component.
        // Re-enable only this private owned service while removing its filters.
        HardwareHce.enabled(context,mode,true);CardEmulation sdk=CardEmulation.getInstance(adapter);
        long end=SystemClock.elapsedRealtime()+3000;String failure="";
        for(int i=0;i<owned.length();i++){
            JSONObject row=owned.getJSONObject(i);Entry entry=new Entry(mode,row.getInt("kind"),row.getString("filter"),row.getString("lease"),false);
            try {
                boolean removed=Api35.remove(sdk,context,entry);
                // Removal is idempotent. Allow the actual package/component cache
                // to catch up, without replaying an uncertain registration.
                while(!removed&&SystemClock.elapsedRealtime()<end){Thread.sleep(50);removed=Api35.remove(sdk,context,entry);}
                if(!removed)throw new IOException("Android did not remove an owned polling filter.");
                forget(context,entry);
            }catch(Exception error){failure=MainActivity.safe(error);}
        }
        if(!failure.isEmpty())throw new VmHardware.Failure("cleanup_failed",failure);
    }

    boolean busy(){return pending!=null;}
    void expire(Request r){synchronized(session){if(!r.done&&!r.expired&&SystemClock.elapsedRealtime()>=r.expires){r.expired=true;r.state="timeout";r.code="timeout";r.error="NFC control exceeded its elapsed deadline; attempted SDK effects remain uncertain.";event(r,"timeout");}}}
    void event(Request r,String phase){try{session.event("hce_control","phase",phase,"result",r.value());}catch(Exception ignored){}}
    void admission()throws Exception {
        if(session.mode==2||Build.VERSION.SDK_INT<35)throw new VmHardware.Failure("unsupported_operation","Polling filters and observe control require ISO-DEP HCE on Android15+.");
        if(!session.accepts())throw new VmHardware.Failure("not_ready","Wait for the owned HCE session to become ready.");
        if(pending!=null)throw new VmHardware.Failure("busy","Wait for the pending NFC control worker to settle.");
    }
    String request(String operation,int kind,String text,boolean flag,int timeout)throws Exception {
        synchronized(session){admission();Entry entry=null,previous=null;
            if(!operation.equals("observe")){
                String normalized=filter(kind,text),key=kind+":"+normalized;previous=filters.get(key);
                if(operation.equals("remove")){if(previous==null)throw new VmHardware.Failure("unknown_filter","Only filters owned by this HCE session may be removed.");entry=previous;}
                else{if(previous==null&&filters.size()>=MAX_FILTERS)throw new VmHardware.Failure("resource_limit","At most16 polling filters may be owned by one HCE session.");entry=new Entry(session.mode,kind,normalized,lease,flag);filters.put(key,entry);}
            }
            Request r=new Request(operation,entry,previous,flag,timeout);pending=r;results.put(r.id,r);
            r.timer=()->expire(r);android.os.Handler handler=HardwareSensors.events();handler.postDelayed(r.timer,timeout);
            try{HardwareHce.SDK.execute(()->execute(r));}catch(RejectedExecutionException error){r.done=true;handler.removeCallbacks(r.timer);pending=null;results.remove(r.id);rollback(r);throw new VmHardware.Failure("busy","NFC SDK executor is full; no control was submitted.");}
            while(results.size()>MAX_RESULTS)results.remove(results.keySet().iterator().next());
            event(r,"queued");return r.id;
        }
    }
    void rollback(Request r){if(r.operation.equals("register")){if(r.previous==null)filters.remove(r.entry.key());else filters.put(r.entry.key(),r.previous);}}
    boolean beforeCall(Request r){synchronized(session){expire(r);if(r.expired)return false;if(!session.accepts()){r.code="cancelled";r.error="The HCE owner stopped before SDK submission.";r.state="cancelled";return false;}return true;}}
    void execute(Request r){
        try {
            if(!beforeCall(r))return;
            HardwareHce.visible(session.context);
            if(!HardwareHce.supported(session.context.host,session.adapter,session.mode))throw new VmHardware.Failure("unsupported","Android has no ISO-DEP host card emulation adapter.");
            if(!session.adapter.isEnabled())throw new VmHardware.Failure("nfc_disabled","Enable NFC before submitting HCE controls.");
            if(session.apdu==null)throw new VmHardware.Failure("not_ready","The real SDK registration is not ready.");
            if(r.operation.equals("observe")&&!Api35.observeSupported(session.adapter))throw new VmHardware.Failure("unsupported_operation","This NFC controller does not support observe mode.");
            if(!beforeCall(r))return;
            if(r.operation.equals("register")){r.journaled=true;remember(session.context.host,r.entry);}
            // Journal I/O and SDK capability getters can themselves take time.
            // Recheck cancellation/deadline immediately before the mutation.
            synchronized(session){if(!beforeCall(r))return;r.sent=true;r.state="submitted";if(r.entry!=null)r.entry.attempted=true;}
            boolean accepted=r.operation.equals("observe")?Api35.observe(session.adapter,r.enabled):r.operation.equals("remove")?Api35.remove(session.apdu,session.context.host,r.entry):Api35.register(session.apdu,session.context.host,r.entry);
            synchronized(session){r.returned=true;r.accepted=accepted;if(r.entry!=null)r.entry.accepted=accepted;expire(r);}
            if(accepted&&r.operation.equals("remove")){forget(session.context.host,r.entry);synchronized(session){filters.remove(r.entry.key());}}
        }catch(Exception error){synchronized(session){
            String code=error instanceof VmHardware.Failure?((VmHardware.Failure)error).code:error instanceof SecurityException?"permission_denied":error instanceof UnsupportedOperationException?"unsupported_operation":error instanceof IllegalArgumentException?"invalid_argument":"platform_error",message=MainActivity.safe(error);
            try{r.operationError=VmHardware.object("code",code,"message",message);}catch(Exception ignored){}
            expire(r);if(!r.expired){r.code=code;r.error=message;}
            // Preserve a real removal return separately from failed durable
            // bookkeeping, including when the original deadline already expired.
            if(r.returned&&Boolean.TRUE.equals(r.accepted)&&r.operation.equals("remove"))r.cleanupError=message;
        }}
        finally{
            if(!r.sent&&r.operation.equals("register")&&r.previous==null&&r.journaled)try{forget(session.context.host,r.entry);}catch(Exception error){synchronized(session){r.cleanupError=MainActivity.safe(error);if(!r.expired){r.code="cleanup_failed";r.error=r.cleanupError;}}}
            synchronized(session){
                expire(r);r.notSubmitted=!r.sent;
                if(!r.sent&&r.operation.equals("register")&&r.cleanupError.isEmpty())rollback(r);
                r.done=true;HardwareSensors.events().removeCallbacks(r.timer);if(pending==r)pending=null;
                if(!r.expired){if(!r.code.isEmpty())r.state=r.code.equals("cancelled")?"cancelled":"error";else r.state=Boolean.TRUE.equals(r.accepted)?"returned":r.returned?"rejected":"cancelled";}
                if(!r.cleanupError.isEmpty()||r.code.equals("recovery_required")){session.state="error";session.event("error","code","recovery_required","message","The NFC routing journal is unresolved; cleanup must finish before further controls.");}
                event(r,"completed");if(session.stopping())session.cleanup();session.release();
            }
        }
    }
    JSONObject result(String id)throws Exception{synchronized(session){Request r=results.get(id);if(r==null)throw new VmHardware.Failure("stale_request","Unknown or evicted NFC control result for this session.");expire(r);return r.value();}}
    JSONArray filters()throws Exception{synchronized(session){JSONArray rows=new JSONArray();for(Entry entry:filters.values())rows.put(entry.value());return rows;}}
    JSONObject info()throws Exception{synchronized(session){if(pending!=null)expire(pending);return VmHardware.object("pending",pending==null?JSONObject.NULL:pending.value(),"retained_results",results.size(),"owned_filter_intents",filters.size(),"maximum_results",MAX_RESULTS,"maximum_filters",MAX_FILTERS);}}
    void cleanup()throws Exception{recover(session.context.host,session.adapter,session.mode,lease);synchronized(session){filters.clear();}}

    private static final class Api35 {
        static boolean observeSupported(NfcAdapter adapter){return adapter.isObserveModeSupported();}
        static boolean observe(NfcAdapter adapter,boolean enabled){return adapter.setObserveModeEnabled(enabled);}
        static boolean register(CardEmulation sdk,Context context,Entry e){return e.kind==0?sdk.registerPollingLoopFilterForService(HardwareHce.component(context,e.mode),e.filter,e.automatic):sdk.registerPollingLoopPatternFilterForService(HardwareHce.component(context,e.mode),e.filter,e.automatic);}
        static boolean remove(CardEmulation sdk,Context context,Entry e){return e.kind==0?sdk.removePollingLoopFilterForService(HardwareHce.component(context,e.mode),e.filter):sdk.removePollingLoopPatternFilterForService(HardwareHce.component(context,e.mode),e.filter);}
    }
}
