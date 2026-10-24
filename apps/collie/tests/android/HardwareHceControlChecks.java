package org.flexscript.collie;

import android.content.pm.PackageManager;
import android.os.SystemClock;
import android.util.AtomicFile;
import java.io.*;
import java.util.*;
import java.util.concurrent.*;
import org.json.*;

/** Negative SDK paths and explicitly constructed routing intents on an NFC-less emulator.
 * No fake adapter or successful SDK mutation is installed or inferred. */
public final class HardwareHceControlChecks {
    final HardwareHceChecks base;final MainActivity host;final File root;boolean controlsVerified;
    HardwareHceControlChecks(MainActivity host,File root){this.host=host;this.root=root;base=new HardwareHceChecks(host,root);}
    public static JSONObject run(MainActivity host,File root)throws Exception{
        HardwareHceControlChecks t=new HardwareHceControlChecks(host,root);t.absent();t.validation();t.deadlines();t.queuedClose();t.history();t.revoke();t.executorRecovery();t.journalFormat();t.controlsVerified=true;return t.report();
    }
    public static JSONObject runOrphan(MainActivity host,File root)throws Exception{return new HardwareHceControlChecks(host,root).orphan();}
    public static JSONObject runRecovered(MainActivity host,File root)throws Exception{return new HardwareHceControlChecks(host,root).recovered();}
    public static JSONObject runRestore(MainActivity host,File root)throws Exception{HardwareHceControlChecks t=new HardwareHceControlChecks(host,root);t.restore();return t.report();}
    void check(boolean ok,String text)throws Exception{base.check(ok,text);MainActivity.atomic(new File(root,"hce-control-progress.json"),base.checks.toString());}
    void absent()throws Exception{base.ready();check(!HardwareHce.supported(host,HardwareNfc.optional(base.context),0),"this control fixture independently confirms actual ISO-DEP adapter absence; it cannot prove successful NFC mutations");}
    JSONObject report()throws Exception{return base.report().put("control_negative_paths_verified",controlsVerified).put("actual_component_binding_verified",controlsVerified).put("control_sdk_success_verified",false).put("filter_registration_verified",false).put("observe_mode_effect_verified",false);}
    static String q(String text){return HardwareHceChecks.q(text);}
    JSONObject vm(String text)throws Exception{return base.vm("fn same(v,k,s){let x=device_field(v,k);return db_kind(x)==2 && worker_equal(db_word(x),s);}"+text);}
    HardwareHceControls.Request request(HardwareHceChecks.Peer p,String expression)throws Exception{
        String id=vm("fn main(){let r="+expression+";if !r{return 1;}db_io(0,1,db_word(r),db_bytes(r));return 0;}").getString("stdout");
        synchronized(p.session){HardwareHceControls.Request r=p.session.controls.results.get(id);if(r==null)throw new IOException("Control receipt was not retained");return r;}
    }
    void settled(HardwareHceChecks.Peer p,HardwareHceControls.Request r)throws Exception{base.until(()->{synchronized(p.session){return r.done;}});}
    static final class Gate implements AutoCloseable {
        final CountDownLatch entered=new CountDownLatch(1),release=new CountDownLatch(1);
        Gate(boolean sdk)throws Exception{Runnable block=()->{entered.countDown();try{release.await(30,TimeUnit.SECONDS);}catch(InterruptedException e){Thread.currentThread().interrupt();}};if(sdk)HardwareHce.SDK.execute(block);else HardwareSensors.events().post(block);if(!entered.await(5,TimeUnit.SECONDS))throw new IOException("NFC executor gate did not enter");}
        public void close(){release.countDown();}
    }
    void validation()throws Exception{
        try(HardwareHceChecks.Peer p=base.new Peer(0,5000)){
            String h=q(p.handle);
            String[] invalid={"hce_polling_register("+h+",0,\"A\",0,1000)","hce_polling_register("+h+",0,\"ABC\",0,1000)","hce_polling_register("+h+",0,\"GG\",0,1000)","hce_polling_register("+h+",1,\"?AA\",0,1000)","hce_polling_register("+h+",1,\"AA[0]\",0,1000)","hce_polling_register("+h+",1,\"AA**\",0,1000)","hce_polling_register("+h+",2,\"AABB\",0,1000)","hce_polling_register("+h+",0,\"AABB\",2,1000)","hce_polling_register("+h+",0,\"AABB\",0,0)","hce_polling_register("+h+",0,\"AABB\",0,8001)","hce_observe("+h+",2,1000)"};
            for(String expression:invalid)vm("fn main(){if "+expression+"{return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"invalid_argument\"){return 2;}return 0;}");
            check(p.session.controls.pending==null&&p.session.controls.filters.isEmpty(),"all eleven malformed filter/flag/deadline cases fail through the actual VM before queueing a control or owning a filter");
            vm("fn main(){if hce_polling_remove("+h+",0,\"AABB\",1000){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"unknown_filter\"){return 2;}return 0;}");check(true,"a VM cannot remove a polling filter it does not own");
            for(String expression:new String[]{"hce_polling_register("+h+",0,\"aabb\",0,1000)","hce_polling_register("+h+",1,\"aabb.*\",1,1000)","hce_observe("+h+",1,1000)","hce_observe("+h+",0,1000)"}){
                HardwareHceControls.Request r=request(p,expression);settled(p,r);
                vm("fn main(){let r=hce_control_result("+h+","+q(r.id)+");if !same(r,\"state\",\"error\")||!same(r,\"code\",\"unsupported\")||!db_word(device_field(r,\"worker_done\"))||!db_word(device_field(r,\"sdk_not_submitted\"))||db_word(device_field(r,\"sdk_call_started\"))||db_word(device_field(r,\"sdk_call_returned\"))||db_kind(device_field(r,\"sdk_boolean\"))!=0||!same(device_field(r,\"operation_error\"),\"code\",\"unsupported\"){return 1;}return 0;}");
            }
            check(p.session.controls.filters.isEmpty(),"exact/pattern registration and observe enable/disable report the real missing adapter, with no SDK mutation return or fabricated successful effect");
            check(!HardwareHceControls.exists(HardwareHceControls.journal(host))||HardwareHceControls.read(HardwareHceControls.journal(host)).length()==0,"unsupported controls neither leave filter reservations nor create routing intents");
            File foreign=new File(root,"control-foreign");new File(foreign,"files").mkdirs();base.vm(foreign,"fn main(){if hce_polling_filters("+h+"){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"stale_handle\"){return 2;}return 0;}");check(true,"a different actual VM workspace cannot list or control the session's filters");
            synchronized(p.session){for(int i=0;i<16;i++){HardwareHceControls.Entry e=new HardwareHceControls.Entry(0,0,String.format(Locale.ROOT,"AABB%02X",i),p.session.controls.lease,false);p.session.controls.filters.put(e.key(),e);}}
            vm("fn main(){if db_count(hce_polling_filters("+h+"))!=16{return 1;}if hce_polling_register("+h+",0,\"CCDD\",0,1000){return 2;}if !worker_equal(db_word(db_at(device_error(),0)),\"resource_limit\"){return 3;}return 0;}");check(true,"sixteen explicitly constructed unsent filter intents reserve capacity; the seventeenth VM request is rejected before SDK work");
        }
        try(HardwareHceChecks.Peer p=base.new Peer(2,5000)){vm("fn main(){if hce_observe("+q(p.handle)+",1,1000){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"unsupported_operation\"){return 2;}return 0;}");check(true,"the real NFC-F handle type cannot be used for ISO-DEP observe/filter controls");}
    }
    void deadlines()throws Exception{
        try(HardwareHceChecks.Peer p=base.new Peer(0,5000);Gate timers=new Gate(false)){
            HardwareHceControls.Request r;
            try(Gate sdk=new Gate(true)){r=request(p,"hce_polling_register("+q(p.handle)+",0,\"aabb\",1,50)");Thread.sleep(90);}
            settled(p,r);
            check(r.expired&&r.state.equals("timeout")&&r.notSubmitted&&!r.sent&&!r.returned&&r.accepted==null,"the SDK submission worker enforces elapsed expiry before the blocked timer handler runs, without any status getter or SDK mutation");
            check(p.session.controls.filters.isEmpty()&&p.session.controls.pending==null,"worker-confirmed expiry rolls back the unsent filter reservation and frees the pending slot");
        }
        try(HardwareHceChecks.Peer p=base.new Peer(0,5000);Gate timers=new Gate(false);Gate sdk=new Gate(true)){
            HardwareHceControls.Request r=request(p,"hce_observe("+q(p.handle)+",1,50)");Thread.sleep(90);
            vm("fn main(){let r=hce_control_result("+q(p.handle)+","+q(r.id)+");if !same(r,\"state\",\"timeout\")||!db_word(device_field(r,\"expired\"))||db_word(device_field(r,\"worker_done\"))||db_word(device_field(r,\"sdk_not_submitted\")){return 1;}if hce_observe("+q(p.handle)+",0,1000){return 2;}if !worker_equal(db_word(db_at(device_error(),0)),\"busy\"){return 3;}return 0;}");
            check(true,"getter-driven expiry retains the unresolved pending slot until its actual queued worker settles");
        }
    }
    void queuedClose()throws Exception{
        try(HardwareHceChecks.Peer p=base.new Peer(0,5000)){
            HardwareHceControls.Request r;
            try(Gate sdk=new Gate(true)){
                r=request(p,"hce_polling_register("+q(p.handle)+",1,\"aabb.*\",1,5000)");
                vm("fn main(){let a=hce_polling_filters("+q(p.handle)+");if db_count(a)!=1||!same(db_at(a,0),\"filter\",\"AABB.*\")||db_word(device_field(db_at(a,0),\"sdk_registration_attempted\")){return 1;}if hce_observe("+q(p.handle)+",0,1000){return 2;}if !worker_equal(db_word(db_at(device_error(),0)),\"busy\"){return 3;}return 0;}");
                long start=SystemClock.elapsedRealtime();base.ui(()->{try{p.session.shutdown();}catch(Exception e){throw new RuntimeException(e);}});
                check(SystemClock.elapsedRealtime()-start<1000&&!p.session.released&&!r.done,"real UI-thread shutdown returns while SDK work is queued and retains the lease until worker/cleanup settlement");
            }
            settled(p,r);base.until(()->{synchronized(p.session){return p.session.released;}});
            check(r.state.equals("cancelled")&&r.notSubmitted&&!r.sent&&!r.returned&&p.session.controls.filters.isEmpty(),"queued close cancels the control before mutation, releases its local filter intent and eventually releases the owned lease");
        }
    }
    void history()throws Exception{
        try(HardwareHceChecks.Peer p=base.new Peer(0,5000)){
            p.session.events.clear();ArrayList<String> ids=new ArrayList<>();String h=q(p.handle);
            for(int i=0;i<70;i++){HardwareHceControls.Request r=request(p,"hce_observe("+h+",1,5000)");settled(p,r);if(r.sent||r.returned||!r.code.equals("unsupported"))throw new IOException("Unexpected SDK effect in negative history fixture");ids.add(r.id);}
            vm("fn main(){if hce_control_result("+h+","+q(ids.get(0))+"){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"stale_request\"){return 2;}let info=device_field(device_info("+h+"),\"controls\");if db_word(device_field(info,\"retained_results\"))!=16{return 3;}let e=device_wait("+h+",0);if !same(e,\"event\",\"overflow\")||db_word(device_field(e,\"dropped\"))!=12{return 4;}return 0;}");
            // Exercise the complete queue without raising a guest program's fuel.
            for(int offset=0;offset<127;offset+=16){int count=Math.min(16,127-offset);boolean last=offset+count==127;
                vm("fn main(){let e=db_null();let i=0;while i<"+count+"{e=device_wait("+h+",0);if !same(e,\"event\",\"hce_control\"){return 1;}i=i+1;}"+(last?"let r=device_field(e,\"result\");if !same(e,\"phase\",\"completed\")||!same(r,\"id\","+q(ids.get(69))+")||!same(r,\"code\",\"unsupported\"){return 2;}":"")+"return 0;}");
            }
            check(true,"seventy actual VM control attempts retain16 typed results and128 events, report12 losses and preserve the final real unsupported result");
            try(Gate sdk=new Gate(true)){
                for(int i=0;i<8;i++)HardwareHce.SDK.execute(()->{});
                vm("fn main(){if hce_observe("+h+",1,10){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"busy\"){return 2;}if !hce_control_result("+h+","+q(ids.get(54))+"){return 3;}return 0;}");Thread.sleep(40);
                check(p.session.controls.results.size()==16&&p.session.controls.pending==null&&p.session.events.isEmpty(),"executor rejection preserves all retained results, consumes no pending slot and emits no phantom queued/timeout event");
                long start=SystemClock.elapsedRealtime();base.ui(()->{try{p.session.shutdown();}catch(Exception e){throw new RuntimeException(e);}});
                check(SystemClock.elapsedRealtime()-start<1000&&p.session.cleanupSubmissionWaiting&&!p.session.released,"real UI-thread shutdown tolerates a full SDK executor and retains the lease while retrying only unsubmitted cleanup");
            }
        }
    }
    void revoke()throws Exception{
        try(HardwareHceChecks.Peer p=base.new Peer(0,5000)){
            java.lang.reflect.Method save=MainActivity.class.getDeclaredMethod("savePermission",String.class,Object.class);save.setAccessible(true);HardwareHceControls.Request r;
            try(Gate sdk=new Gate(true)){
                r=request(p,"hce_polling_register("+q(p.handle)+",0,\"AABB\",0,5000)");
                base.ui(()->{try{save.invoke(host,"nfc",false);}catch(Exception e){throw new RuntimeException(e);}});
                check(p.session.closed&&!p.session.released&&!r.sent,"actual UI-thread NFC Deny closes the owner while preserving its unresolved queued control lease");
            }finally{base.ui(()->{try{save.invoke(host,"nfc",true);}catch(Exception e){throw new RuntimeException(e);}});}
            settled(p,r);check(r.state.equals("cancelled")&&r.notSubmitted&&!r.sent,"the queued worker observes real revocation and performs no SDK mutation");
        }
    }
    void journalFormat()throws Exception{
        File file=new File(root,"control-format.json");JSONArray rows=new JSONArray();String lease="hce-lease-"+UUID.randomUUID();
        for(int i=0;i<16;i++)rows.put(new HardwareHceControls.Entry(i%2,i%2,i%2==0?String.format(Locale.ROOT,"AABB%02X",i):String.format(Locale.ROOT,"AABB%02X.*",i),lease,false).record());
        HardwareHceControls.write(file,rows);check(HardwareHceControls.read(file).toString().equals(rows.toString()),"sixteen explicitly constructed exact/pattern ownership records round-trip through the actual AtomicFile commit/readback path");
        File bad=new File(root,"control-directory.json");bad.mkdir();new File(bad,"keep").createNewFile();boolean failed=false;try{HardwareHceControls.write(bad,rows);}catch(Exception expected){failed=true;}check(failed,"a failed AtomicFile commit/rename cannot be treated as a verified routing journal");
        for(String text:new String[]{"{\"version\":2,\"entries\":[]}","{\"version\":1.0,\"entries\":[]}","{\"version\":1,\"entries\":[{\"mode\":2,\"kind\":0,\"filter\":\"AABB\",\"lease\":\""+lease+"\"}]}","{\"version\":1,\"entries\":["+rows.getJSONObject(0)+","+rows.getJSONObject(0)+"]}"}){
            MainActivity.atomic(file,text);failed=false;try{HardwareHceControls.read(file);}catch(VmHardware.Failure expected){failed=expected.code.equals("recovery_required");}check(failed&&MainActivity.read(new AtomicFile(file).openRead(),32768).equals(text),"malformed/versioned/duplicate ownership data is retained with a typed recovery error");
        }
        check(!HardwareHceControls.exists(HardwareHceControls.journal(host))||HardwareHceControls.read(HardwareHceControls.journal(host)).length()==0,"isolated journal-format fixtures never alter the production routing journal");
    }
    void executorRecovery()throws Exception{
        base.ready();
        HardwareHce.Session startup=new HardwareHce.Session(base.context,HardwareNfc.optional(base.context),0,1000,new ArrayList<>(Arrays.asList("F0434F4C4C494500")),"","");
        try(Gate sdk=new Gate(true)){
            for(int i=0;i<8;i++)HardwareHce.SDK.execute(()->{});
            synchronized(HardwareNfc.LEASE){HardwareHce.owner=startup;}
            try{boolean busy=false;try{startup.start();}catch(VmHardware.Failure error){busy=error.code.equals("busy");}check(busy&&!startup.starting&&!startup.registrationAttempted,"an explicitly constructed startup rejected by the real full executor clears starting without claiming SDK registration");}
            finally{base.ui(()->{try{startup.close();}catch(Exception error){throw new RuntimeException(error);}});}
        }
        base.until(()->{synchronized(startup){return startup.released;}});check(true,"rejected startup eventually releases its constructed lease after actual queued cleanup completes");
        base.ready();
        try(Gate sdk=new Gate(true)){
            for(int i=0;i<8;i++)HardwareHce.SDK.execute(()->{});
            synchronized(HardwareNfc.LEASE){HardwareHce.recovered=false;}
            HardwareHce.recoverAsync(host);
            synchronized(HardwareNfc.LEASE){check(!HardwareHce.recovering&&!HardwareHce.recovered&&HardwareHce.recoveryError.contains("executor"),"actual SDK queue rejection leaves recovery pending without a stuck recovering flag or a discarded ownership record");}
        }
        base.until(()->HardwareHce.SDK.getQueue().isEmpty());HardwareHce.recoverAsync(host);base.ready();
        check(true,"a later explicit recovery succeeds after the real SDK queue drains");
    }
    File marker(){return new File(root,"control-recovery.json");}
    JSONObject orphan()throws Exception{
        absent();File journal=HardwareHceControls.journal(host);JSONObject baseline;
        synchronized(HardwareHceControls.JOURNAL_LOCK){if(HardwareHceControls.read(journal).length()!=0)throw new IOException("Preserve preexisting routing intents; orphan fixture requires an empty journal");boolean exists=HardwareHceControls.exists(journal);baseline=VmHardware.object("existed",exists,"original",exists?MainActivity.read(new AtomicFile(journal).openRead(),32768):"","lease","hce-lease-"+UUID.randomUUID());MainActivity.atomic(marker(),baseline.toString());}
        HardwareHceControls.Entry entry=new HardwareHceControls.Entry(0,0,"F0434F4C4C494500",baseline.getString("lease"),false);HardwareHceControls.remember(host,entry);HardwareHce.enabled(host,0,true);
        check(HardwareHceControls.read(journal).length()==1,"the process-death fixture records one explicitly constructed unsent routing intent before enabling its private service; no NFC registration is claimed");return report();
    }
    JSONObject recovered()throws Exception{
        base.until(()->{synchronized(HardwareNfc.LEASE){return !HardwareHce.recovering&&!HardwareHce.recovered&&!HardwareHce.recoveryError.isEmpty();}});
        JSONObject baseline=new JSONObject(MainActivity.read(new FileInputStream(marker()),32768));JSONArray rows=HardwareHceControls.read(HardwareHceControls.journal(host));
        check(rows.length()==1&&rows.getJSONObject(0).getString("lease").equals(baseline.getString("lease")),"actual process restart retains the constructed intent when the real public NFC adapter cannot perform cleanup");
        check(!HardwareHce.recovered&&HardwareHce.recoveryError.contains("retained"),"unavailable SDK cleanup remains a visible recovery error rather than a fabricated clean state");
        for(int mode=0;mode<3;mode++)check(host.getPackageManager().getComponentEnabledSetting(HardwareHce.component(host,mode))==PackageManager.COMPONENT_ENABLED_STATE_DEFAULT,"recovery failure still disables the private service component"+mode);
        restore();check(true,"only the constructed routing intent is removed, the exact original journal state is restored and fresh actual recovery completes");return report();
    }
    void restore()throws Exception{
        if(!marker().exists())return;
        JSONObject baseline=new JSONObject(MainActivity.read(new FileInputStream(marker()),32768));File journal=HardwareHceControls.journal(host);
        synchronized(HardwareHceControls.JOURNAL_LOCK){JSONArray rows=HardwareHceControls.read(journal);if(rows.length()!=1||!rows.getJSONObject(0).getString("lease").equals(baseline.getString("lease")))throw new IOException("Routing journal changed independently; retained fixture backup for explicit recovery");if(baseline.getBoolean("existed"))MainActivity.atomic(journal,baseline.getString("original"));else new AtomicFile(journal).delete();}
        synchronized(HardwareNfc.LEASE){HardwareHce.recovered=false;}HardwareHce.recoverAsync(host);base.ready();
        if(baseline.getBoolean("existed")){if(!MainActivity.read(new AtomicFile(journal).openRead(),32768).equals(baseline.getString("original")))throw new IOException("Original journal did not restore exactly");}else if(HardwareHceControls.exists(journal))throw new IOException("Fixture journal was not removed");
        if(!marker().delete())throw new IOException("Could not remove the restored fixture marker");
    }
}
