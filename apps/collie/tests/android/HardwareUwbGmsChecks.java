package org.flexscript.collie;

import android.os.SystemClock;
import com.google.android.gms.common.api.ApiException;
import com.google.android.gms.common.api.Status;
import com.google.android.gms.nearby.uwb.RangingCapabilities;
import com.google.android.gms.nearby.uwb.RangingParameters;
import java.util.Collections;
import com.google.android.gms.tasks.TaskCompletionSource;
import java.io.*;
import java.util.concurrent.atomic.AtomicInteger;
import org.json.*;

/** Real provider metadata and explicitly constructed public SDK Task race fixtures.
 * Task fixtures never invoke a ranging mutation or assert radio behavior. */
public final class HardwareUwbGmsChecks {
    final MainActivity host;final File root;final VmHardware.Context context;final JSONArray checks=new JSONArray();int sequence;
    HardwareUwbGmsChecks(MainActivity host,File root){this.host=host;this.root=root;context=new VmHardware.Context(host,root);}
    public static JSONObject run(MainActivity host,File root)throws Exception{return new HardwareUwbGmsChecks(host,root).run();}
    void check(boolean value,String text)throws Exception{if(!value)throw new IOException(text);checks.put(text);}
    static String q(String text){return JSONObject.quote(text).replace("\\/","/");}
    JSONObject vm(String source)throws Exception{
        JSONObject result=host.engineAt(root,3,new JSONObject().put("config",host.workerConfig(root,0)).put("source",source).put("call_id","uwb-gms-check-"+(++sequence)).put("history",new JSONArray()));
        if(!result.optString("state").equals("continue")||result.optInt("exit_code")!=0)throw new IOException("GMS UWB VM: "+result+" source="+source);
        return result;
    }
    HardwareUwbGms.Watch watch()throws Exception{
        if(!HardwareUwb.WATCHES.tryAcquire())throw new IOException("No fixture observer lease");
        try{return new HardwareUwbGms.Watch(context);}catch(Exception e){HardwareUwb.WATCHES.release();throw e;}
    }
    void watchDeadline()throws Exception{
        int before=HardwareUwb.WATCHES.availablePermits();HardwareUwbGms.Watch w=watch();String id=VmHardware.add(w);
        TaskCompletionSource<RangingCapabilities> source=new TaskCompletionSource<>();
        synchronized(w){w.preparing=true;w.settled=false;w.expires=SystemClock.elapsedRealtime()-1;}
        source.getTask().addOnCompleteListener(HardwareUwbGms.CALLBACK,w::prepared);
        try{
            vm("fn main(){let h="+q(id)+";let i=device_info(h);if !db_word(device_field(i,\"startup_deadline_expired\")) || !db_word(device_field(i,\"preparing\")){return 1;}if db_word(device_field(i,\"subscription_submitted\")) || db_word(device_field(i,\"lease_released\")){return 2;}let e=device_wait(h,100);if !worker_equal(db_word(device_field(e,\"event\")),\"error\"){return 3;}return 0;}");
            check(HardwareUwb.WATCHES.availablePermits()==before-1,"constructed pending capability Task: the actual VM observes startup timeout and retains the observer lease before Task settlement");
            source.setException(new ApiException(new Status(42000,"constructed late SDK Task failure")));
            JSONObject info=(JSONObject)w.info();
            check(info.getBoolean("startup_deadline_expired")&&info.getJSONObject("error").getString("code").equals("timeout")&&info.getJSONObject("operation_error").getInt("sdk_status")==42000,"constructed late public SDK Task error preserves the primary timeout and the actual Task exception separately");
            check(!w.submitted&&w.released&&HardwareUwb.WATCHES.availablePermits()==before,"constructed expired preparation never subscribes; only actual Task settlement releases its lease");
        }finally{if(!source.getTask().isComplete())source.setException(new IOException("fixture cleanup"));VmHardware.close(context,id);}
    }
    void watchClose()throws Exception{
        int before=HardwareUwb.WATCHES.availablePermits();HardwareUwbGms.Watch w=watch();TaskCompletionSource<RangingCapabilities> source=new TaskCompletionSource<>();
        synchronized(w){w.preparing=true;w.settled=false;w.expires=SystemClock.elapsedRealtime()+10000;}
        source.getTask().addOnCompleteListener(HardwareUwbGms.CALLBACK,w::prepared);
        try{w.close();check(!w.released&&HardwareUwb.WATCHES.availablePermits()==before-1,"constructed close-during-preflight retains the SDK Task and observer capacity");source.setException(new IOException("constructed preflight failure"));w.close();check(w.released&&!w.submitted&&HardwareUwb.WATCHES.availablePermits()==before,"constructed preflight settlement after close releases exactly once without subscribing");}
        finally{if(!source.getTask().isComplete())source.setException(new IOException("fixture cleanup"));w.close();}
        w.start();check(w.released&&!w.preparing&&!w.submitted&&HardwareUwb.WATCHES.availablePermits()==before,"close-before-start prevents SDK work from escaping an already released observer lease");
    }
    void requestDeadline()throws Exception{
        int before=HardwareUwb.SESSIONS.availablePermits();check(HardwareUwb.SESSIONS.tryAcquire(),"constructed session Task fixture obtains its bounded session lease");
        HardwareUwbGms.Range r;try{r=new HardwareUwbGms.Range(context,1,1000);}catch(Exception e){HardwareUwb.SESSIONS.release();throw e;}
        TaskCompletionSource<Void> source=new TaskCompletionSource<>();AtomicInteger accepted=new AtomicInteger();
        try{
            String id=r.invoke("fixture",10,source::getTask,()->{},()->accepted.incrementAndGet());
            HardwareUwbGms.Request request=r.requests.get(id);
            long deadline=SystemClock.elapsedRealtime()+2000;boolean expired=false;
            while(SystemClock.elapsedRealtime()<deadline){synchronized(r){expired=request.expired;}if(expired)break;Thread.sleep(5);}
            check(expired,"constructed unresolved Task reaches the real scheduled request deadline");
            AtomicInteger invoked=new AtomicInteger();
            try{r.invoke("busy-fixture",1000,()->{invoked.incrementAndGet();return source.getTask();},()->{},()->{});throw new IOException("Second mutation admitted before settlement");}
            catch(VmHardware.Failure expected){check(expected.code.equals("busy")&&invoked.get()==0,"a real expired but unsettled Task blocks a second invocation before any SDK call");}
            r.close();check(!r.released&&r.pending==request&&!request.complete,"constructed unresolved mutation Task holds session capacity after close and timeout");
            source.setException(new ApiException(new Status(42000,"constructed late mutation failure")));
            JSONObject info=request.info();check(info.getBoolean("deadline_expired")&&info.getBoolean("task_complete")&&!info.getBoolean("task_success")&&info.getJSONObject("error").getInt("sdk_status")==42000&&accepted.get()==0,"constructed late mutation failure reports real Task completion separately from deadline and never runs acceptance");
            check(r.released&&r.pending==null&&HardwareUwb.SESSIONS.availablePermits()==before,"constructed settled Task permits pre-start cleanup exactly once without calling a radio mutation");
            r.prepare();check(r.released&&!r.preparing&&r.preparationSettled&&HardwareUwb.SESSIONS.availablePermits()==before,"close-before-prepare prevents SDK work after session capacity has been released");
        }finally{if(!source.getTask().isComplete())source.setException(new IOException("fixture cleanup"));r.close();}
    }
    void parameters()throws Exception{
        JSONArray row=new JSONArray().put("12345678-1234-1234-1234-123456789abc").put(4294967295L).put(1).put(VmHardware.bytes(new byte[]{1,2})).put(VmHardware.bytes(new byte[]{3,4})).put(9).put(10).put(1).put(2).put(VmHardware.bytes(new byte[8])).put(-1).put(VmHardware.bytes(new byte[0]));
        HardwareUwbGms.Peer peer=new HardwareUwbGms.Peer(row);
        RangingParameters actual=HardwareUwbGms.parameters(peer,Collections.singletonList(peer),0,1,0,20000);
        check(!peer.subSet&&actual.getSubSessionId()==0&&actual.getSessionId()==-1,"constructed public SDK builder accepts the guest unset sub-session sentinel while preserving unsigned32-bit session bits");
        row.put(2,7).put(9,VmHardware.bytes(new byte[16])).put(10,4294967295L).put(11,VmHardware.bytes(new byte[16]));peer=new HardwareUwbGms.Peer(row);
        actual=HardwareUwbGms.parameters(peer,Collections.singletonList(peer),0,1,0,20000);
        check(peer.subSet&&actual.getSubSessionId()==-1,"constructed public SDK builder distinguishes explicit unsignedFFFFFFFF sub-session from the guest unset sentinel");
        try{HardwareUwbGms.parameters(peer,Collections.singletonList(peer),0,1,0,0);throw new IOException("Non-default disabled proximity bounds accepted");}
        catch(IllegalArgumentException expected){check(true,"constructed SDK notification builder rejects invalid provider-specific default bounds before any radio call");}
    }
    JSONObject run()throws Exception{
        int actualStatus=HardwareUwbGms.status(context);JSONObject actual=(JSONObject)HardwareUwbGms.info(context);
        check(actual.getInt("gms_status")==actualStatus&&actual.getBoolean("feature")==HardwareUwb.feature(context),"provider metadata agrees with an independent actual Google Play services status and Android feature query");
        vm("fn main(){let v=uwb_backend_info(2);if !v || !worker_equal(db_word(device_field(v,\"backend\")),\"play_services\"){return 1;}if db_word(device_field(v,\"gms_status\"))!="+actualStatus+"{return 2;}if !db_word(device_field(v,\"legacy_gms_binding_implemented\")) || db_word(device_field(v,\"legacy_aosp_binding_implemented\")){return 3;}return 0;}");
        check(true,"the actual VM loads the pinned public SDK and reports its real provider status and binding boundaries");
        vm("fn main(){if uwb_backend_info(3){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"invalid_argument\"){return 2;}if uwb_prepare(2,1000){return 3;}if !worker_equal(db_word(db_at(device_error(),0)),\"invalid_argument\"){return 4;}if uwb_start(\"device-unknown\",db_list(),db_list()){return 5;}if !worker_equal(db_word(db_at(device_error(),0)),\"stale_handle\"){return 6;}return 0;}");
        check(true,"invalid backend/role and stale session fail through the actual VM before SDK mutation or runtime consent");
        if(!HardwareUwb.feature(context)){
            vm("fn main(){if uwb_prepare(1,1000) || uwb_backend_watch(2){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"unsupported\"){return 2;}return 0;}");
            check(true,"actual missing UWB hardware is unsupported before Android runtime consent rather than an unimplemented adapter");
        }
        parameters();watchDeadline();watchClose();requestDeadline();
        return new JSONObject().put("ok",true).put("checks",checks).put("actual_provider",actual).put("constructed_task_fixtures",true).put("ranging_io_verified",false).put("physical_devices_verified",false);
    }
}
