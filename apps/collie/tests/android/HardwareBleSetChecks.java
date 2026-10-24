package org.flexscript.collie;

import android.os.SystemClock;
import java.io.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicReference;
import java.util.function.BooleanSupplier;
import org.json.*;

/** Delays delivery of real SDK callbacks; never fabricates advertising results. */
public final class HardwareBleSetChecks {
    final MainActivity host;final File root;final VmHardware.Context context;
    final JSONArray checks=new JSONArray();int sequence;
    static final String OPTIONS="ble_set_options(0,0,0,0,0,1,1,160,-7,1)";
    HardwareBleSetChecks(MainActivity h,File r){host=h;root=r;context=new VmHardware.Context(h,r);}
    public static JSONObject run(MainActivity h,File r)throws Exception{
        HardwareBleSetChecks t=new HardwareBleSetChecks(h,r);
        try{t.queuedEnable();t.queuedDeadlines();t.startupDeadline();t.requestDeadline();t.startupClose();t.polledTimeouts();t.queuedStarts();t.history();t.liveRevoke();return t.report();}finally{VmHardware.closeWorkspace(r);}
    }
    public static JSONObject runStartupDeadline(MainActivity h,File r)throws Exception{
        HardwareBleSetChecks t=new HardwareBleSetChecks(h,r);
        try{t.startupDeadline();return t.report();}finally{VmHardware.closeWorkspace(r);}
    }
    public static JSONObject runRequestDeadline(MainActivity h,File r)throws Exception{
        HardwareBleSetChecks t=new HardwareBleSetChecks(h,r);
        try{t.requestDeadline();return t.report();}finally{VmHardware.closeWorkspace(r);}
    }
    public static JSONObject runHidden(MainActivity h,File r)throws Exception{
        HardwareBleSetChecks t=new HardwareBleSetChecks(h,r);
        try{t.hidden();return t.report();}finally{VmHardware.closeWorkspace(r);}
    }
    void check(boolean value,String label)throws Exception{if(!value)throw new IOException(label);checks.put(label);MainActivity.atomic(new File(root,"ble-lifecycle-progress.json"),checks.toString());}
    static String q(String text){return JSONObject.quote(text).replace("\\/","/");}
    JSONObject vm(String source)throws Exception{return vm(root,source);}
    JSONObject vm(File workspace,String source)throws Exception{
        String helpers="fn same(v,k,s){let x=device_field(v,k);if db_kind(x)!=2{return 0;}return worker_equal(db_word(x),s);}fn fail(n){let e=db_error();db_io(0,2,e,db_len(e));return n;}";
        JSONObject o=host.engineAt(workspace,3,new JSONObject().put("config",host.workerConfig(workspace,0)).put("source",helpers+source.replaceAll("return ([1-9][0-9]*);","return fail($1);")).put("call_id","ble-lifecycle-"+(++sequence)).put("history",new JSONArray()));
        if(!o.optString("state").equals("continue")||o.optInt("exit_code")!=0)throw new IOException("BLE lifecycle program "+sequence+": "+o);
        return o;
    }
    String state(String key)throws Exception{return vm("fn main(){let v=state_get("+q(key)+");if db_kind(v)!=2{return 1;}db_io(0,1,db_word(v),db_bytes(v));return 0;}").getString("stdout");}
    String data(String phase)throws Exception{
        String service=state("ble_lifecycle_service"),hex=state("ble_lifecycle_"+phase);
        if(!hex.matches("[0-9a-f]{2,512}")||hex.length()%2!=0)throw new IOException("Invalid owned BLE fixture bytes");
        StringBuilder source=new StringBuilder("let b=alloc("+(hex.length()/2)+");");
        for(int i=0;i<hex.length()/2;i++)source.append("store8(b+").append(i).append(',').append(Integer.parseInt(hex.substring(i*2,i*2+2),16)).append(");");
        return source+"let services=db_list();db_add(services,ble_ad_service("+q(service)+",db_blob(b,"+(hex.length()/2)+")));let data=ble_set_data_value(db_list(),services,db_list(),db_list(),0,0);";
    }
    String open(String phase,int timeout)throws Exception{return vm("fn main(){"+data(phase)+"let h=ble_set_open("+OPTIONS+",data,db_null(),db_null(),db_null(),0,0,"+timeout+");if !h{return 1;}db_io(0,1,db_word(h),db_bytes(h));return 0;}").getString("stdout");}
    HardwareBleSets.SetHandle handle(String id)throws Exception{return VmHardware.handle(context,id,HardwareBleSets.SetHandle.class);}
    void until(BooleanSupplier ready)throws Exception{long end=SystemClock.elapsedRealtime()+10000;while(!ready.getAsBoolean()){if(SystemClock.elapsedRealtime()>=end)throw new IOException("Actual BLE SDK lifecycle callback timed out");Thread.sleep(10);}}
    static boolean ready(HardwareBleSets.SetHandle h){synchronized(h){return h.state.equals("ready");}}
    static boolean started(HardwareBleSets.SetHandle h){synchronized(h){return h.startCallback;}}
    static boolean returned(HardwareBleSets.SetHandle h){synchronized(h){return h.requested&&h.inFlight==0;}}
    static boolean released(HardwareBleSets.SetHandle h){synchronized(h){return h.released;}}
    static boolean result(HardwareBleSets.SetHandle h,HardwareBleSets.Request r){synchronized(h){return r.callback;}}
    void ui(Runnable action)throws Exception{
        CountDownLatch done=new CountDownLatch(1);AtomicReference<Throwable> error=new AtomicReference<>();
        host.runOnUiThread(()->{try{action.run();}catch(Throwable e){error.set(e);}finally{done.countDown();}});
        if(!done.await(5,TimeUnit.SECONDS))throw new IOException("BLE fixture UI action blocked");
        if(error.get()!=null)throw new IOException(error.get());
    }
    void close(String id,HardwareBleSets.SetHandle set)throws Exception{vm("fn main(){return device_close("+q(id)+")-1;}");until(()->released(set));}
    HardwareBleSets.Request submit(String id,HardwareBleSets.SetHandle set,String bytes)throws Exception{
        String token=vm("fn main(){"+bytes+"let r=ble_set_data("+q(id)+",0,data);if !r{return 1;}db_io(0,1,db_word(r),db_bytes(r));return 0;}").getString("stdout");
        synchronized(set){HardwareBleSets.Request r=set.requests.get(token);if(r==null)throw new IOException("SDK request token was not retained");return r;}
    }
    void awaitSuccess(HardwareBleSets.SetHandle set,HardwareBleSets.Request r)throws Exception{
        until(()->result(set,r));synchronized(set){if(r.expired||r.status==null||r.status!=0||!r.state.equals("complete"))throw new IOException("Actual SDK operation was not successful: "+r.info());}
    }
    JSONObject report()throws Exception{return new JSONObject().put("ok",true).put("checks",checks).put("synthetic_sdk_callbacks",false).put("physical_devices_verified",false);}
    static final class Gate implements AutoCloseable {
        final CountDownLatch entered=new CountDownLatch(1),release=new CountDownLatch(1);
        Gate()throws Exception{
            HardwareSensors.events().post(()->{entered.countDown();try{release.await(30,TimeUnit.SECONDS);}catch(InterruptedException e){Thread.currentThread().interrupt();}});
            if(!entered.await(5,TimeUnit.SECONDS))throw new IOException("Could not delay actual BLE SDK delivery");
        }
        public void close(){release.countDown();}
    }
    static final class SdkGate implements AutoCloseable {
        final CountDownLatch entered=new CountDownLatch(2),release=new CountDownLatch(1);
        SdkGate()throws Exception{
            for(int i=0;i<2;i++)HardwareBleSets.SDK.execute(()->{entered.countDown();try{release.await(30,TimeUnit.SECONDS);}catch(InterruptedException e){Thread.currentThread().interrupt();}});
            if(!entered.await(5,TimeUnit.SECONDS))throw new IOException("Could not delay SDK submission workers");
        }
        public void close(){release.countDown();}
    }
    void startupDeadline()throws Exception{
        String id;HardwareBleSets.SetHandle set;
        try(Gate gate=new Gate()){
            id=open("startup_timeout",500);set=handle(id);until(()->returned(set));Thread.sleep(650);
            check(!started(set),"the real SDK startup callback remains queued until the fixture releases its handler");
            // Do not call info/access/expire: the callback itself must enforce time.
        }
        until(()->started(set));
        synchronized(set){check(set.stopping&&!set.state.equals("ready")&&set.error.contains("deadline"),"late SDK startup must retain its elapsed timeout without a VM status read");}
        until(()->released(set));
        check(set.terminalCallback&&set.localClean,"late actual startup is followed by genuine SDK stop/local cleanup before releasing its lease");
        vm("fn main(){let d=device_info("+q(id)+");if !db_word(device_field(d,\"startup_deadline_expired\"))||!db_word(device_field(d,\"sdk_start_callback\"))||!db_word(device_field(d,\"lease_released\")){return 1;}return device_close("+q(id)+")-1;}");
        check(true,"the VM distinguishes actual late start status from its already elapsed startup deadline");
    }
    void queuedEnable()throws Exception{
        String id=open("operation_before",5000);HardwareBleSets.SetHandle set=handle(id);until(()->ready(set));HardwareBleSets.Request request;
        try(SdkGate gate=new SdkGate()){
            String token=vm("fn main(){let r=ble_set_enable("+q(id)+",0,0,0);if !r{return 1;}db_io(0,1,db_word(r),db_bytes(r));return 0;}").getString("stdout");
            synchronized(set){request=set.requests.get(token);}check(request!=null&&request.state.equals("queued"),"the VM enable request is queued before its SDK call");
            // A distinct, genuine public SDK action produces a real callback.
            // It must not acknowledge the VM request that has not been sent.
            set.sdk.enableAdvertising(false,0,0);
            until(()->{synchronized(set){return Boolean.FALSE.equals(set.enabled);}});
            synchronized(set){check(!request.callback&&!request.returned&&request.state.equals("queued")&&set.pending==request,"a real SDK event must not complete a VM request before its SDK submission");}
        }
        awaitSuccess(set,request);
        check(request.sent&&!request.notSubmitted,"after SDK workers resume the actual VM disable call receives its own real completion");close(id,set);
    }
    void queuedDeadlines()throws Exception{
        String id;HardwareBleSets.SetHandle set;
        try(Gate callbacks=new Gate();SdkGate sdk=new SdkGate()){
            id=open("queued_expired",500);set=handle(id);Thread.sleep(650);sdk.close();
            until(()->released(set));
            check(set.startupExpired&&set.noRegistration&&!set.requested&&!set.startCallback,"a startup whose deadline elapses before SDK submission is cancelled locally even while its timer/callback handler is blocked");
        }
        vm("fn main(){return device_close("+q(id)+")-1;}");
        String active=open("operation_before",500);HardwareBleSets.SetHandle running=handle(active);until(()->ready(running));HardwareBleSets.Request request;
        String replacement=data("queued_expired");
        try(Gate callbacks=new Gate();SdkGate sdk=new SdkGate()){
            request=submit(active,running,replacement);Thread.sleep(650);sdk.close();
            until(()->{synchronized(running){return request.notSubmitted;}});
            check(request.expired&&!request.sent&&!request.returned&&!request.callback&&request.status==null&&running.pending==null,"an expired queued update is skipped before Android and releases only its locally confirmed slot without fabricating a callback");
            vm("fn main(){let r=ble_set_request("+q(active)+","+q(request.id)+");if !same(r,\"state\",\"timeout\")||!db_word(device_field(r,\"sdk_not_submitted\"))||db_word(device_field(r,\"sdk_call_started\"))||db_word(device_field(r,\"sdk_callback\"))||db_kind(device_field(r,\"status\"))!=0{return 1;}return 0;}");
            check(true,"the VM can distinguish a known unsent timeout from an ambiguous SDK operation");
        }
        awaitSuccess(running,submit(active,running,data("after_timeout")));
        check(true,"after local confirmation a fresh SDK update succeeds without waiting for an impossible callback");close(active,running);
    }
    void requestDeadline()throws Exception{
        String id=open("operation_before",500);HardwareBleSets.SetHandle set=handle(id);until(()->ready(set));
        String token;HardwareBleSets.Request request;
        try(Gate gate=new Gate()){
            token=vm("fn main(){"+data("operation_after")+"let r=ble_set_data("+q(id)+",0,data);if !r{return 1;}db_io(0,1,db_word(r),db_bytes(r));return 0;}").getString("stdout");
            synchronized(set){request=set.requests.get(token);}check(request!=null,"the submitted data operation has an owned request token");
            until(()->{synchronized(set){return request.returned;}});Thread.sleep(650);
            check(!result(set,request),"the SDK call returns while its genuine operation callback is deliberately queued");
            // No request/info getter is allowed to mask callback-before-timer order.
        }
        until(()->result(set,request));
        synchronized(set){check(request.expired&&request.state.equals("timeout")&&request.status!=null&&request.status==0&&set.pending==null,"late SDK request callback must retain its elapsed timeout without a VM result read");}
        vm("fn main(){let r=ble_set_request("+q(id)+","+q(token)+");if !same(r,\"state\",\"timeout\")||!db_word(device_field(r,\"sdk_callback\"))||!db_word(device_field(r,\"deadline_expired\"))||db_word(device_field(r,\"status\"))!=0{return 1;}return 0;}");
        check(true,"the VM preserves timeout together with the late real success callback instead of inventing on-time completion");
        vm("fn main(){return device_close("+q(id)+")-1;}");until(()->released(set));
    }
    void startupClose()throws Exception{
        String id;HardwareBleSets.SetHandle set;
        try(Gate gate=new Gate()){
            id=open("startup_close",5000);set=handle(id);until(()->returned(set));Thread.sleep(350);
            long at=SystemClock.elapsedRealtime();ui(()->{try{VmHardware.close(context,id);}catch(Exception e){throw new RuntimeException(e);}});
            check(SystemClock.elapsedRealtime()-at<2000&&set.closed&&!released(set),"actual UI-thread close returns while a real startup callback is still delayed, without releasing its SDK lease");
            until(()->{synchronized(set){return set.stopReturned;}});
            synchronized(HardwareBleSets.POOL){check(HardwareBleSets.OWNED.contains(set),"SDK stop-call return alone cannot release a set whose real callback delivery is blocked");}
        }
        until(()->released(set));
        check(set.startCallback&&set.terminalCallback&&set.localClean&&set.events.isEmpty()&&!ready(set),"actual delayed startup/stop callbacks finish cleanup without reviving a locally closed handle or emitting late success");
        vm("fn main(){if device_info("+q(id)+"){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"stale_handle\"){return 2;}return 0;}");
    }
    void polledTimeouts()throws Exception{
        String id;HardwareBleSets.SetHandle set;
        try(Gate gate=new Gate()){
            id=open("startup_timeout",500);set=handle(id);until(()->returned(set));Thread.sleep(650);
            vm("fn main(){let d=device_info("+q(id)+");if !db_word(device_field(d,\"startup_deadline_expired\"))||db_word(device_field(d,\"sdk_start_callback\"))||db_word(device_field(d,\"lease_released\")){return 1;}return 0;}");
            check(set.startupExpired&&!set.released,"a VM status read also enforces the startup deadline while both SDK callbacks and the timer queue are blocked");
        }
        until(()->released(set));vm("fn main(){return device_close("+q(id)+")-1;}");
        String active=open("operation_before",500);HardwareBleSets.SetHandle running=handle(active);until(()->ready(running));HardwareBleSets.Request request;
        String after=data("after_timeout");
        try(Gate gate=new Gate()){
            request=submit(active,running,after);until(()->{synchronized(running){return request.returned;}});Thread.sleep(650);
            vm("fn main(){let r=ble_set_request("+q(active)+","+q(request.id)+");if !same(r,\"state\",\"timeout\")||!db_word(device_field(r,\"deadline_expired\"))||db_word(device_field(r,\"sdk_callback\")){return 1;}"+after+"if ble_set_data("+q(active)+",0,data){return 2;}if !worker_equal(db_word(db_at(device_error(),0)),\"busy\"){return 3;}return 0;}");
            check(request.expired&&running.pending==request,"an expired operation keeps its slot until the genuine callback; a second VM update fails busy before SDK submission");
        }
        until(()->result(running,request));
        synchronized(running){check(request.state.equals("timeout")&&request.status!=null&&request.status==0&&running.pending==null,"actual late data success clears only its pending slot while preserving the timed-out result");}
        awaitSuccess(running,submit(active,running,data("operation_after")));
        check(true,"a subsequent SDK update succeeds only after the delayed real callback resolves ambiguity");close(active,running);
    }
    void queuedStarts()throws Exception{
        java.util.ArrayList<HardwareBleSets.SetHandle> sets=new java.util.ArrayList<>();java.util.ArrayList<String> ids=new java.util.ArrayList<>();
        String bytes=data("queued_close");
        try(SdkGate gate=new SdkGate()){
            for(int i=0;i<8;i++){
                String id=vm("fn main(){"+bytes+"let h=ble_set_open("+OPTIONS+",data,db_null(),db_null(),db_null(),0,0,30000);if !h{return 1;}db_io(0,1,db_word(h),db_bytes(h));return 0;}").getString("stdout");
                ids.add(id);sets.add(handle(id));
            }
            vm("fn main(){if ble_set_open("+OPTIONS+",ble_ad_empty(),db_null(),db_null(),db_null(),0,0,30000){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"resource_limit\"){return 2;}return 0;}");
            check(sets.stream().allMatch(s->!s.requested&&!s.startCallback),"eight queued startups reserve the bounded quota before any SDK registration, and the ninth is denied");
            long at=SystemClock.elapsedRealtime();ui(()->{try{for(String id:ids)VmHardware.close(context,id);}catch(Exception e){throw new RuntimeException(e);}});
            check(SystemClock.elapsedRealtime()-at<2000&&sets.stream().noneMatch(HardwareBleSetChecks::released),"UI-thread close of eight queued startups returns before SDK workers resume and retains their reservations");
        }
        for(HardwareBleSets.SetHandle s:sets)until(()->released(s));
        check(sets.stream().allMatch(s->s.noRegistration&&!s.requested&&!s.startCallback&&s.closed&&s.events.isEmpty()),"resumed SDK workers cancel all eight locally closed startups without registering or fabricating terminal callbacks");
        String id=open("operation_before",5000);HardwareBleSets.SetHandle set=handle(id);until(()->ready(set));HardwareBleSets.Request pending;
        String replacement=data("queued_close");
        try(SdkGate gate=new SdkGate()){
            pending=submit(id,set,replacement);check(pending.state.equals("queued")&&!pending.returned,"an update can remain queued before its actual SDK call");
            ui(()->{try{VmHardware.close(context,id);}catch(Exception e){throw new RuntimeException(e);}});check(!released(set),"closing a queued update retains ownership until submission cancellation and actual SDK stop finish");
        }
        until(()->released(set));
        check(pending.state.equals("cancelled")&&!pending.returned&&!pending.callback&&set.terminalCallback,"a closed queued update never calls the SDK or invents an operation result; its actual set still receives terminal teardown");
    }
    void history()throws Exception{
        String id=open("operation_before",5000);HardwareBleSets.SetHandle set=handle(id);until(()->ready(set));
        File foreign=new File(root,"foreign-ble");if(!new File(foreign,"files").mkdirs())throw new IOException("Cannot create owned workspace isolation fixture");
        vm(foreign,"fn main(){if device_info("+q(id)+"){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"stale_handle\"){return 2;}return 0;}");
        check(true,"another actual VM workspace cannot inspect or update the live owned advertising set");
        String bytes=data("operation_after");HardwareBleSets.Request first=null,last=null;
        for(int i=0;i<VmHardware.MAX_EVENTS+4;i++){HardwareBleSets.Request r=submit(id,set,bytes);awaitSuccess(set,r);if(first==null)first=r;last=r;}
        check(set.requests.size()==16&&set.events.size()==VmHardware.MAX_EVENTS,"actual SDK data callbacks retain only sixteen request records and the bounded128-event queue under sustained updates");
        vm("fn main(){if ble_set_request("+q(id)+","+q(first.id)+"){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"stale_request\"){return 2;}let r=ble_set_request("+q(id)+","+q(last.id)+");if !same(r,\"state\",\"complete\")||!db_word(device_field(r,\"sdk_callback\")){return 3;}let e=device_wait("+q(id)+",0);if !same(e,\"event\",\"overflow\")||db_word(device_field(e,\"dropped\"))<=0||!same(device_field(e,\"next\"),\"event\",\"request_result\"){return 4;}return 0;}");
        check(true,"evicted request IDs fail stale_request and real event overflow reports loss while preserving the next actual callback");close(id,set);
    }
    void liveRevoke()throws Exception{
        String id=open("live_revoke",5000);HardwareBleSets.SetHandle set=handle(id);until(()->ready(set));Thread.sleep(350);
        java.lang.reflect.Method save=MainActivity.class.getDeclaredMethod("savePermission",String.class,Object.class);save.setAccessible(true);
        ExecutorService executor=Executors.newSingleThreadExecutor();Future<JSONObject> running=null;
        try(Gate gate=new Gate()){
            running=executor.submit(()->host.engineAt(root,3,new JSONObject().put("config",host.workerConfig(root,0)).put("source","fn main(){let i=0;while i<10000{device_wait("+q(id)+",1000);i=i+1;}return 1;}").put("history",new JSONArray())));
            java.lang.reflect.Field active=VmHardware.class.getDeclaredField("active");active.setAccessible(true);
            until(()->{try{Object op=active.get(null);if(op==null)return false;java.lang.reflect.Field io=op.getClass().getDeclaredField("cancelIO");io.setAccessible(true);return io.get(op)!=null;}catch(Exception e){throw new RuntimeException(e);}});
            long at=SystemClock.elapsedRealtime();ui(()->{try{save.invoke(host,"bluetooth",false);}catch(Exception e){throw new RuntimeException(e);}});
            JSONObject stopped=running.get(4,TimeUnit.SECONDS);
            check(SystemClock.elapsedRealtime()-at<4000&&stopped.optString("state").equals("error")&&stopped.optString("stderr").toLowerCase(java.util.Locale.ROOT).contains("cancel"),"the real UI-thread Bluetooth revocation cancels an already-running VM wait without waiting for delayed SDK callbacks");
            check(set.closed&&!released(set)&&!host.workerConfig(root,0).getJSONObject("permissions").optBoolean("bluetooth"),"live revocation persists Deny, invalidates its actual advertising handle and retains uncertain cleanup ownership");
            vm("fn main(){if ble_info(){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"permission_denied\"){return 2;}return 0;}");
            check(true,"subsequent Bluetooth calls remain denied by the actual saved conversation policy after live revocation");
        }finally{
            if(running!=null&&!running.isDone()){VmHardware.cancel();running.cancel(true);}executor.shutdownNow();
            ui(()->{try{save.invoke(host,"bluetooth",true);}catch(Exception e){throw new RuntimeException(e);}});
        }
        until(()->released(set));check(set.terminalCallback&&set.localClean&&set.events.isEmpty(),"the genuine queued SDK stop callback releases a revoked set without reviving it or publishing late results");
    }
    void hidden()throws Exception{
        String id=open("background_before",5000);HardwareBleSets.SetHandle set=handle(id);until(()->ready(set));
        ui(()->host.startActivity(new android.content.Intent(android.content.Intent.ACTION_MAIN).addCategory(android.content.Intent.CATEGORY_HOME).addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)));
        until(()->!host.hardwareVisible);
        awaitSuccess(set,submit(id,set,data("background_update")));Thread.sleep(350);
        check(!host.hardwareVisible&&!set.closed&&Boolean.TRUE.equals(set.enabled),"actual Activity onStop preserves an existing set and its real SDK data update completes while Collie is hidden");
        String background=vm("fn main(){"+data("background_start")+"let h=ble_set_open("+OPTIONS+",data,db_null(),ble_periodic_options(0,80),data,0,0,5000);if !h{return 1;}db_io(0,1,db_word(h),db_bytes(h));return 0;}").getString("stdout");
        HardwareBleSets.SetHandle bg=handle(background);until(()->ready(bg));
        String token=vm("fn main(){let r=ble_set_periodic_enable("+q(background)+",1);if !r{return 1;}db_io(0,1,db_word(r),db_bytes(r));return 0;}").getString("stdout");
        HardwareBleSets.Request enabled;synchronized(bg){enabled=bg.requests.get(token);}awaitSuccess(bg,enabled);
        check(!host.hardwareVisible&&bg.startCallback&&Boolean.TRUE.equals(bg.periodicEnabled),"with existing approvals a genuinely hidden Activity starts another real extended/periodic SDK set without a foreground exemption");
        MainActivity.atomic(new File(root,"ble-background-peer-waiting"),"ready");
        long until=SystemClock.elapsedRealtime()+10000;
        while(!new File(root,"ble-background-peer-ack").isFile()){
            if(SystemClock.elapsedRealtime()>=until)throw new IOException("Independent background advertising/periodic acknowledgement timed out");Thread.sleep(20);
        }
        check(!host.hardwareVisible,"the independent peer verifies the new advertising and periodic bytes before the Activity returns to foreground");
        close(background,bg);close(id,set);check(set.terminalCallback&&bg.terminalCallback,"both existing and newly created sets perform actual SDK shutdown while their Activity remains hidden");
        ui(()->{try{host.savePermission("bluetooth",false);}catch(Exception e){throw new RuntimeException(e);}});
        try{
            vm("fn main(){"+data("blocked_reopen")+"if ble_set_open("+OPTIONS+",data,db_null(),db_null(),db_null(),0,0,5000){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"permission_denied\"){return 2;}return 0;}");
            check(!host.hardwareVisible,"a hidden caller with Collie Bluetooth denied is still blocked before Android registration");
        }finally{ui(()->{try{host.savePermission("bluetooth",true);}catch(Exception e){throw new RuntimeException(e);}});}
        // The external emulator driver restores the Activity. An ordinary
        // background app must not bypass Android's Activity-launch restrictions.
    }
}
