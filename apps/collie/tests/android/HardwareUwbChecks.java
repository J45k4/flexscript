package org.flexscript.collie;

import android.ranging.*;
import android.ranging.raw.*;
import android.ranging.uwb.*;
import android.os.Parcel;
import java.io.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicReference;
import org.json.*;

/** Independent actual SDK capability oracle. Builder fixtures do not prove RF I/O. */
public final class HardwareUwbChecks {
    final MainActivity host;final File root;final VmHardware.Context context;final JSONArray checks=new JSONArray();int sequence;
    HardwareUwbChecks(MainActivity host,File root){this.host=host;this.root=root;context=new VmHardware.Context(host,root);}
    public static JSONObject run(MainActivity host,File root)throws Exception{return new HardwareUwbChecks(host,root).run();}
    public static JSONObject runLifecycle(MainActivity host,File root)throws Exception{return new HardwareUwbChecks(host,root).lifecycle();}
    void check(boolean okay,String text)throws Exception{if(!okay)throw new IOException(text);checks.put(text);}
    JSONObject vm(File workspace,String source)throws Exception{JSONObject value=host.engineAt(workspace,3,new JSONObject().put("config",host.workerConfig(workspace,0)).put("source",source).put("call_id","uwb-check-"+(++sequence)).put("history",new JSONArray()));if(!value.optString("state").equals("continue")||value.optInt("exit_code")!=0)throw new IOException("UWB VM fixture: "+value+" source="+source);return value;}
    JSONObject vm(String source)throws Exception{return vm(root,source);}
    static String q(String text){return JSONObject.quote(text).replace("\\/","/");}
    int observerSlots()throws Exception{JSONArray values=new JSONArray();HardwareUwb.capabilities(context,values);return values.getJSONObject(0).getInt("observer_slots_available");}
    void capacity()throws Exception{
        long end=android.os.SystemClock.elapsedRealtime()+3000;while(observerSlots()!=8&&android.os.SystemClock.elapsedRealtime()<end)Thread.sleep(10);check(observerSlots()==8,"prior actual SDK observer cleanup has released all eight slots");
        ArrayList<String> ids=new ArrayList<>();
        try{for(int i=0;i<8;i++)ids.add(vm("fn main(){let h=uwb_watch();if !h{return 1;}db_io(0,1,db_word(h),db_bytes(h));return 0;}").getString("stdout"));
            vm("fn main(){if uwb_watch(){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"resource_limit\"){return 2;}return 0;}");check(true,"eight real SDK capability registrations enforce the observer limit without opening an extra resource");
            VmHardware.close(context,ids.remove(0));end=android.os.SystemClock.elapsedRealtime()+3000;while(observerSlots()==0&&android.os.SystemClock.elapsedRealtime()<end)Thread.sleep(10);check(observerSlots()>0,"actual SDK unregistration releases capacity for another observer");
            ids.add(vm("fn main(){let h=uwb_watch();if !h{return 1;}db_io(0,1,db_word(h),db_bytes(h));return 0;}").getString("stdout"));check(true,"a fresh actual SDK observer opens after confirmed cleanup");
        }finally{for(String id:ids)try{VmHardware.close(context,id);}catch(Exception ignored){}}
    }
    void ui(Runnable action)throws Exception{CountDownLatch done=new CountDownLatch(1);AtomicReference<Throwable> error=new AtomicReference<>();host.runOnUiThread(()->{try{action.run();}catch(Throwable value){error.set(value);}finally{done.countDown();}});if(!done.await(4,TimeUnit.SECONDS))throw new IOException("UWB UI fixture timed out");if(error.get()!=null)throw new IOException(error.get());}
    String open(int timeout)throws Exception{int session=java.util.concurrent.ThreadLocalRandom.current().nextInt(1,Integer.MAX_VALUE);return vm("fn main(){let peers=db_list();db_add(peers,uwb_peer(\"12345678-1234-1234-1234-123456789abc\","+session+",1,db_blob(\"AB\",2),db_blob(\"CD\",2),9,10,1,2,db_blob(\"00000000\",8),-1,db_blob(\"\",0)));let h=uwb_range(0,peers,uwb_options(0,0,0,1,0,0,"+timeout+"));if !h{return 1;}db_io(0,1,db_word(h),db_bytes(h));return 0;}").getString("stdout");}
    HardwareUwb.Api36.Range opened(String id)throws Exception{HardwareUwb.Api36.Range range=VmHardware.handle(context,id,HardwareUwb.Api36.Range.class);long end=android.os.SystemClock.elapsedRealtime()+4000;while(android.os.SystemClock.elapsedRealtime()<end&&((JSONObject)range.info()).getString("state").equals("pending"))Thread.sleep(10);check(((JSONObject)range.info()).getString("state").equals("opened"),"the lifecycle fixture receives an actual SDK opened callback");return range;}
    void terminal(HardwareUwb.Api36.Range range)throws Exception{long end=android.os.SystemClock.elapsedRealtime()+4000;while(android.os.SystemClock.elapsedRealtime()<end){synchronized(range){if(range.terminal){check(range.released,"an actual terminal SDK callback releases the UWB session lease");return;}}Thread.sleep(10);}throw new IOException("SDK UWB teardown did not confirm");}
    JSONObject lifecycle()throws Exception{
        // A real SDK object has been created, but no radio request committed yet.
        // Reproduce preemption across that boundary without inventing callbacks.
        JSONArray expiredPeer=new JSONArray().put("12345678-1234-1234-1234-123456789abc").put(123).put(1).put(VmHardware.bytes(new byte[]{1,2})).put(VmHardware.bytes(new byte[]{3,4})).put(9).put(10).put(1).put(2).put(VmHardware.bytes(new byte[8])).put(-1).put(VmHardware.bytes(new byte[0]));
        RawRangingDevice device=HardwareUwb.Api36.peer(expiredPeer);LinkedHashMap<UUID,RawRangingDevice> definitions=new LinkedHashMap<>();definitions.put(device.getRangingDevice().getUuid(),device);
        HardwareUwb.Api36.Range preStart=HardwareUwb.Api36.range(context,0,definitions,HardwareUwb.Api36.options(new JSONArray().put(0).put(0).put(0).put(1).put(0).put(0).put(500)),500);
        try{RangingSession sdk=preStart.manager.createRangingSession(Runnable::run,new RangingSession.Callback(){public void onOpened(){throw new AssertionError("no start");}public void onOpenFailed(int reason){throw new AssertionError("no start");}public void onClosed(int reason){throw new AssertionError("no start");}public void onStarted(RangingDevice peer,int technology){throw new AssertionError("no start");}public void onStopped(RangingDevice peer,int technology){throw new AssertionError("no start");}public void onResults(RangingDevice peer,RangingData data){throw new AssertionError("no start");}});
            synchronized(preStart){preStart.starting=true;preStart.deadlineElapsed=android.os.SystemClock.elapsedRealtime()-1;check(!preStart.commit(sdk)&&!preStart.requested,"expiry between actual SDK object creation and request commitment prevents a late radio start");check(preStart.terminal&&preStart.released&&preStart.state.equals("error"),"confirmed absence of an SDK start releases the expired request lease without a fabricated SDK callback");}
        }finally{preStart.close();}
        String id=open(10000);HardwareUwb.Api36.Range range=opened(id);File foreign=new File(root,"uwb-live-foreign");new File(foreign,"files").mkdirs();
        try{vm(foreign,"fn main(){if device_info("+q(id)+") || uwb_stop("+q(id)+"){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"stale_handle\"){return 2;}return 0;}");check(true,"a different actual VM workspace cannot inspect or stop a live UWB session");
            vm("fn main(){if uwb_remove("+q(id)+",\"87654321-1234-1234-1234-123456789abc\"){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"unknown_peer\"){return 2;}if uwb_interval("+q(id)+",256){return 3;}return 0;}");check(true,"unknown peers and out-of-range interval skip counts fail without changing the SDK session");
        }finally{VmHardware.closeWorkspace(foreign);VmHardware.close(context,id);}terminal(range);
        id=open(10000);range=opened(id);final String closing=id;CountDownLatch cleanupEntered=new CountDownLatch(2),cleanupRelease=new CountDownLatch(1);AtomicReference<Throwable> cleanupFailure=new AtomicReference<>();
        java.lang.reflect.Field field=HardwareUwb.class.getDeclaredField("CLEANUP");field.setAccessible(true);ExecutorService cleanup=(ExecutorService)field.get(null);
        try{for(int i=0;i<2;i++)cleanup.execute(()->{cleanupEntered.countDown();try{if(!cleanupRelease.await(6,TimeUnit.SECONDS))throw new IOException("controlled cleanup hold timed out");}catch(Throwable value){cleanupFailure.set(value);}});check(cleanupEntered.await(2,TimeUnit.SECONDS),"both actual bounded SDK cleanup workers are held for the close fixture");
            ui(()->{try{VmHardware.close(context,closing);}catch(Exception value){throw new RuntimeException(value);}});synchronized(range){check(range.closed&&!range.terminal&&!range.released,"local UWB close returns on the real UI thread while SDK cleanup is queued and its lease remains held");}
            cleanupRelease.countDown();terminal(range);if(cleanupFailure.get()!=null)throw new IOException(cleanupFailure.get());
        }finally{cleanupRelease.countDown();try{VmHardware.close(context,id);}catch(Exception ignored){}}
        // Hold the real SDK executor, not a fabricated callback, through expiry.
        CountDownLatch entered=new CountDownLatch(1),release=new CountDownLatch(1);AtomicReference<Throwable> error=new AtomicReference<>();String delayed=null;
        try{HardwareSensors.events().post(()->{entered.countDown();try{if(!release.await(6,TimeUnit.SECONDS))throw new IOException("UWB controlled callback hold timed out");}catch(Throwable value){error.set(value);}});check(entered.await(2,TimeUnit.SECONDS),"the actual UWB SDK callback/deadline executor is held for the expiry fixture");
            delayed=open(500);HardwareUwb.Api36.Range late=VmHardware.handle(context,delayed,HardwareUwb.Api36.Range.class);Thread.sleep(650);
            JSONObject info=(JSONObject)late.info();check(info.getString("state").equals("error")&&info.getBoolean("sdk_requested")&&!info.getBoolean("sdk_terminal"),"elapsed-time expiry rejects a pending SDK session even while its scheduled callback/deadline executor is blocked");
            release.countDown();terminal(late);if(error.get()!=null)throw new IOException(error.get());
            vm("fn main(){let h="+q(delayed)+";let i=0;let timeout=0;while i<12{let e=device_wait(h,0);if db_kind(e)==5{let n=device_field(e,\"event\");let c=device_field(e,\"code\");if db_kind(n)==2 && worker_equal(db_word(n),\"opened\"){return 1;}if db_kind(c)==2 && worker_equal(db_word(c),\"timeout\"){timeout=1;}}i=i+1;}if !timeout{return 2;}return 0;}");check(true,"a delayed actual SDK opened callback is not accepted after expiry and the actual SDK terminal callback frees its lease");
        }finally{release.countDown();if(delayed!=null)try{VmHardware.close(context,delayed);}catch(Exception ignored){}}
        id=open(10000);range=opened(id);final String live=id;ExecutorService executor=Executors.newSingleThreadExecutor();Future<JSONObject> running=null;java.lang.reflect.Method save=MainActivity.class.getDeclaredMethod("savePermission",String.class,Object.class);save.setAccessible(true);
        try{running=executor.submit(()->host.engineAt(root,3,new JSONObject().put("config",host.workerConfig(root,0)).put("source","fn main(){let i=0;while i<10000{device_wait("+q(live)+",1000);i=i+1;}return 1;}").put("history",new JSONArray())));
            java.lang.reflect.Field active=VmHardware.class.getDeclaredField("active");active.setAccessible(true);boolean waiting=false;long end=android.os.SystemClock.elapsedRealtime()+4000;
            while(android.os.SystemClock.elapsedRealtime()<end&&!waiting){Object operation=active.get(null);if(operation!=null){java.lang.reflect.Field io=operation.getClass().getDeclaredField("cancelIO");io.setAccessible(true);waiting=io.get(operation)!=null;}if(!waiting){if(running.isDone())throw new IOException("VM exited before UWB revocation: "+running.get());Thread.sleep(10);}}
            check(waiting,"the actual VM is blocked in UWB I/O before the grant changes");ui(()->{try{save.invoke(host,"uwb",false);}catch(Exception value){throw new RuntimeException(value);}});
            JSONObject stopped=running.get(4,TimeUnit.SECONDS);check(stopped.optString("state").equals("error")&&stopped.optString("stderr").toLowerCase(java.util.Locale.ROOT).contains("cancel"),"the actual UI permission-save path cancels the running UWB VM");check(range.closed&&!host.workerConfig(root,0).getJSONObject("permissions").optBoolean("uwb"),"UWB revocation invalidates the SDK handle and updates subsequent policy");
            terminal(range);vm("fn main(){if uwb_info(){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"permission_denied\"){return 2;}return 0;}");check(true,"a later program cannot reopen UWB after revocation");
        }finally{if(running!=null&&!running.isDone()){VmHardware.cancel();running.cancel(true);}executor.shutdownNow();VmHardware.closeWorkspace(root);ui(()->{try{save.invoke(host,"uwb",true);}catch(Exception value){throw new RuntimeException(value);}});}
        return new JSONObject().put("ok",true).put("checks",checks).put("ranging_io_verified",false).put("physical_devices_verified",false);
    }
    JSONObject run()throws Exception{
        RangingManager one=HardwareUwb.Api36.manager(context),two=HardwareUwb.Api36.manager(context);
        check(one!=two&&one!=host.getSystemService(RangingManager.class),"actual SDK managers have independent context service caches instead of the app-global session map");
        AtomicReference<RangingCapabilities> actual=new AtomicReference<>();CountDownLatch arrived=new CountDownLatch(1);RangingManager.RangingCapabilitiesCallback callback=caps->{actual.set(caps);arrived.countDown();};
        try{one.registerCapabilitiesCallback(Runnable::run,callback);check(arrived.await(3,TimeUnit.SECONDS),"an independent actual SDK capability callback arrives without RANGING runtime consent");}finally{one.unregisterCapabilitiesCallback(callback);}
        Integer availability=actual.get().getTechnologyAvailability().get(RangingManager.UWB);if(availability==null)throw new IOException("The SDK omitted UWB technology availability");
        vm("fn main(){let info=uwb_info();if !info{return 1;}let snap=device_field(info,\"snapshot\");if !db_word(device_field(snap,\"availability_known\")) || db_word(device_field(snap,\"availability\"))!="+availability+"{return 2;}return 0;}");
        check(true,"the actual VM capability snapshot agrees with an independent Android UWB availability query");
        UwbRangingCapabilities caps=actual.get().getUwbCapabilities();if(caps!=null){String source="fn main(){let s=device_field(uwb_info(),\"snapshot\");";String[] names={"channels","config_ids","notification_configs","preamble_indexes","update_rates","slot_durations"};List<List<Integer>> values=Arrays.asList(caps.getSupportedChannels(),caps.getSupportedConfigIds(),caps.getSupportedNotificationConfigurations(),caps.getSupportedPreambleIndexes(),caps.getSupportedRangingUpdateRates(),caps.getSupportedSlotDurations());for(int j=0;j<names.length;j++){source+="let v"+j+"=device_field(s,"+q(names[j])+");if db_count(v"+j+")!="+values.get(j).size()+"{return 3;}";for(int i=0;i<values.get(j).size();i++)source+="if db_word(db_at(v"+j+","+i+"))!="+values.get(j).get(i)+"{return 4;}";}source+="return 0;}";vm(source);check(true,"VM UWB channels, profiles, notifications, preambles, rates and slots match the independent SDK lists exactly");}
        vm("fn main(){let empty=db_list();if uwb_range(2,empty,empty)||uwb_range(0,empty,empty)||uwb_range(1,empty,uwb_options(0,0,0,1,0,0,30000)){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"invalid_argument\"){return 2;}return 0;}");
        check(true,"invalid roles, empty peer sets and malformed options fail before Android runtime consent or radio I/O");
        String id=vm("fn main(){let h=uwb_watch();if !h{return 1;}db_io(0,1,db_word(h),db_bytes(h));return 0;}").getString("stdout");File foreign=new File(root,"uwb-foreign");new File(foreign,"files").mkdirs();
        try{
            vm("fn main(){let e=device_wait("+q(id)+",1000);if !worker_equal(db_word(device_field(e,\"event\")),\"capabilities\") || !db_word(device_field(e,\"sdk_callback\")){return 1;}let s=device_field(e,\"uwb\");if db_word(device_field(s,\"availability\"))!="+availability+"{return 2;}return 0;}");check(true,"the SDK observer delivers its actual copied capability event through the VM");
            vm(foreign,"fn main(){if device_info("+q(id)+"){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"stale_handle\"){return 2;}return 0;}");check(true,"a different actual VM workspace cannot inspect the UWB observer");
        }finally{VmHardware.closeWorkspace(foreign);VmHardware.close(context,id);}
        // These construct public SDK values only; no successful ranging callback is invented.
        JSONArray row=new JSONArray().put("12345678-1234-1234-1234-123456789abc").put(4294967295L).put(3).put(VmHardware.bytes(new byte[]{0,1})).put(VmHardware.bytes(new byte[]{(byte)255,2})).put(9).put(10).put(2).put(1).put(VmHardware.bytes(new byte[16])).put(2147483648L).put(VmHardware.bytes(new byte[32]));
        RawRangingDevice peer=HardwareUwb.Api36.peer(row);UwbRangingParams params=peer.getUwbRangingParams();check(params.getSessionId()==-1&&params.getSubSessionId()==Integer.MIN_VALUE&&params.getConfigId()==3&&params.getComplexChannel().getChannel()==9&&params.getComplexChannel().getPreambleIndex()==10&&params.getSessionKeyInfo().length==16&&params.getSubSessionKeyInfo().length==32&&params.getRangingUpdateRate()==2&&params.getSlotDuration()==1&&Arrays.equals(params.getPeerAddress().getAddressBytes(),new byte[]{(byte)255,2}),"SDK builder fixtures retain unsigned32-bit IDs, binary addresses/keys, channels, profiles, update rate and slot duration");
        Parcel parcel=Parcel.obtain();RangingMeasurement sample;try{parcel.writeDouble(3.25);parcel.writeInt(2);parcel.writeDouble(Double.NaN);parcel.writeDouble(Double.NaN);parcel.setDataPosition(0);sample=RangingMeasurement.CREATOR.createFromParcel(parcel);}finally{parcel.recycle();}
        VmHardware.Handle fixture=new VmHardware.Handle(context,"uwb","uwb_measurement_fixture"){public Object info()throws Exception{check();return VmHardware.object("measurement",HardwareUwb.Api36.measurement(sample));}};String fixtureId=VmHardware.add(fixture);
        try{vm("fn main(){let m=device_field(device_info("+q(fixtureId)+"),\"measurement\");let v=device_field(m,\"value\");if db_kind(v)!=4 || db_word(v)!=4614500768194494464 || db_word(device_field(m,\"confidence\"))!=2{return 1;}return 0;}");check(true,"a clearly constructed SDK Parcelable fixture preserves fractional binary64 measurement bits and confidence through the actual VM transport, independently of RF");}finally{VmHardware.close(context,fixtureId);}
        capacity();
        return new JSONObject().put("ok",true).put("checks",checks).put("ranging_io_verified",false).put("physical_devices_verified",false).put("sdk_availability",availability).put("sdk_snapshot",HardwareUwb.Api36.snapshot(actual.get()));
    }
}
