package org.flexscript.collie;

import android.os.SystemClock;
import android.view.*;
import java.io.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicReference;
import org.json.*;

/** SDK-constructed event fixtures are distinct from actual OS-delivered input. */
public final class HardwareInputChecks {
    final MainActivity host;final File root;final VmHardware.Context context;final JSONArray checks=new JSONArray();int sequence;
    HardwareInputChecks(MainActivity host,File root){this.host=host;this.root=root;context=new VmHardware.Context(host,root);}
    public static JSONObject run(MainActivity host,File root)throws Exception{return new HardwareInputChecks(host,root).run();}
    void check(boolean okay,String label)throws Exception{if(!okay)throw new IOException(label);checks.put(label);}
    JSONObject vm(File workspace,String source)throws Exception{
        source="fn fixture_fail(n){let e=db_error();db_io(0,2,e,db_len(e));return n;}"+source.replaceAll("return ([1-9][0-9]*);","return fixture_fail($1);");
        JSONObject value=host.engineAt(workspace,3,new JSONObject().put("config",host.workerConfig(workspace,0)).put("source",source).put("call_id","input-check-"+(++sequence)).put("history",new JSONArray()));
        if(!value.optString("state").equals("continue")||value.optInt("exit_code")!=0)throw new IOException("Input scenario "+sequence+": "+value+" source="+source);return value;
    }
    JSONObject vm(String source)throws Exception{return vm(root,source);}
    static String quote(String text){return JSONObject.quote(text).replace("\\/","/");}
    void ui(Runnable action)throws Exception{CountDownLatch done=new CountDownLatch(1);AtomicReference<Throwable> error=new AtomicReference<>();host.runOnUiThread(()->{try{action.run();}catch(Throwable value){error.set(value);}finally{done.countDown();}});if(!done.await(4,TimeUnit.SECONDS))throw new IOException("Input UI fixture timed out");if(error.get()!=null)throw new IOException(error.get());}
    String open(int selected,int mask,int history)throws Exception{return vm("fn main(){let axes=db_list();db_add(axes,db_int(0));db_add(axes,db_int(1));db_add(axes,db_int(2));db_add(axes,db_int(25));let h=input_watch("+selected+","+mask+",axes,"+history+");if !h{return 1;}db_io(0,1,db_word(h),db_bytes(h));return 0;}").getString("stdout");}
    static MotionEvent.PointerCoords coordinates(float x,float y,float pressure,float tilt){MotionEvent.PointerCoords c=new MotionEvent.PointerCoords();c.x=x;c.y=y;c.pressure=pressure;c.setAxisValue(MotionEvent.AXIS_TILT,tilt);return c;}
    static MotionEvent motion(int device,long down,long time,MotionEvent.PointerCoords[] coords){MotionEvent.PointerProperties[] props=new MotionEvent.PointerProperties[coords.length];for(int i=0;i<props.length;i++){props[i]=new MotionEvent.PointerProperties();props[i].id=i==0?7:11;props[i].toolType=i==0?MotionEvent.TOOL_TYPE_FINGER:MotionEvent.TOOL_TYPE_STYLUS;}return MotionEvent.obtain(down,time,MotionEvent.ACTION_MOVE,coords.length,props,coords,0,0,1,1,device,0,InputDevice.SOURCE_TOUCHSCREEN,0);}
    JSONObject run()throws Exception{
        int[] ids=HardwareInput.manager(context).getInputDeviceIds();int chosen=-1;for(int id:ids)if(id>=0){chosen=id;break;}check(chosen>=0,"the independent Android InputManager provides a nonnegative device ID for scoped filtering (device-1 means all)");final int deviceId=chosen;
        String history=open(-1,1,1);File other=new File(root,"input-foreign");if(!new File(other,"files").mkdirs())throw new IOException("Cannot create input ownership fixture workspace");
        try{
            vm(other,"fn main(){if device_info("+quote(history)+"){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"stale_handle\"){return 2;}return 0;}");
            check(true,"a different actual VM workspace cannot inspect the input handle");
            long now=SystemClock.uptimeMillis(),down=now-100;MotionEvent e=motion(deviceId,down,now-80,new MotionEvent.PointerCoords[]{coordinates(10.25f,20.5f,.625f,.25f),coordinates(-2.5f,512.125f,.75f,.5f)});
            for(int i=1;i<=4;i++)e.addBatch(now-80+i*20,new MotionEvent.PointerCoords[]{coordinates(10.25f+i,20.5f,.625f,.25f),coordinates(-2.5f-i,512.125f,.75f,.5f)},KeyEvent.META_SHIFT_ON);
            check(e.getHistorySize()==4&&e.getPointerCount()==2,"the SDK-constructed motion fixture contains four historical samples and two distinct pointer IDs/tools");
            ui(()->HardwareInput.motion(host,e,1));e.recycle();
            vm("fn equal(v,n){return db_kind(v)==4 && db_word(v)==n;}fn main(){let h="+quote(history)+";let i=0;while i<2{let e=device_wait(h,0);if db_kind(e)!=5 || db_word(device_field(e,\"historical\"))!=1-i || db_word(device_field(e,\"history_omitted\"))!=3 || db_word(device_field(e,\"down_time_ms\"))!="+down+" || db_word(device_field(e,\"event_time_ms\"))!="+(now-20)+"+i*20{return 1;}let p=device_field(e,\"pointers\");if db_count(p)!=2 || db_word(db_at(db_at(p,0),0))!=7 || db_word(db_at(db_at(p,1),0))!=11 || db_word(db_at(db_at(p,0),1))!=1 || db_word(db_at(db_at(p,1),1))!=2{return 2;}let a=db_at(db_at(p,0),2);let b=db_at(db_at(p,1),2);if !equal(db_at(a,0),4623648704937590784+i*562949953421312) || !equal(db_at(b,0),-4605493568939753472+i*1125899906842624) || !equal(db_at(a,2),4603804719079489536) || !equal(db_at(b,3),4602678819172646912){return 3;}i=i+1;}if db_kind(device_wait(h,0))!=0{return 4;}return 0;}");
            check(true,"copied SDK history survives MotionEvent recycling and crosses the actual VM with pointer identity, tools, fractional axis bits, timestamps and omission counts");
        }finally{VmHardware.closeWorkspace(other);VmHardware.close(context,history);}
        String selected=open(deviceId,1,0);
        try{
            long now=SystemClock.uptimeMillis();MotionEvent match=motion(deviceId,now,now,new MotionEvent.PointerCoords[]{coordinates(1,2,1,0)}),foreign=motion(Integer.MAX_VALUE,now,now,new MotionEvent.PointerCoords[]{coordinates(3,4,1,0)});
            ui(()->{HardwareInput.motion(host,foreign,1);HardwareInput.motion(host,match,4);HardwareInput.motion(host,match,1);});foreign.recycle();match.recycle();
            vm("fn main(){let h="+quote(selected)+";let e=device_wait(h,0);if db_word(device_field(e,\"device_id\"))!="+deviceId+"{return 1;}if db_kind(device_wait(h,0))!=0{return 2;}return 0;}");check(true,"a selected real-device subscription filters other IDs and unrequested event categories in the SDK-constructed fixture");
        }finally{VmHardware.close(context,selected);}
        String overflow=open(-1,1,0);
        try{
            long now=SystemClock.uptimeMillis();MotionEvent e=motion(deviceId,now,now,new MotionEvent.PointerCoords[]{coordinates(1,2,1,0)});ui(()->{for(int i=0;i<150;i++)HardwareInput.motion(host,e,1);});e.recycle();
            vm("fn main(){let h="+quote(overflow)+";if db_word(device_field(device_info(h),\"queued_events\"))!=128{return 1;}let e=device_wait(h,0);if !worker_equal(db_word(device_field(e,\"event\")),\"overflow\") || db_word(device_field(e,\"dropped\"))!=22 || db_count(device_field(device_field(e,\"next\"),\"pointers\"))!=1{return 2;}return 0;}");
            check(true,"a150-event SDK-constructed burst remains bounded to128 and reports22 dropped samples with the next actual value through the VM");
        }finally{VmHardware.close(context,overflow);}
        String keys=open(-1,2,0);
        try{
            StringBuilder characters=new StringBuilder();for(int i=0;i<4095;i++)characters.append('a');characters.append("\ud83d\ude80");KeyEvent e=new KeyEvent(SystemClock.uptimeMillis(),characters.toString(),deviceId,0);ui(()->HardwareInput.key(host,e));
            vm("fn main(){let e=device_wait("+quote(keys)+",0);let t=device_field(e,\"characters\");if db_bytes(t)!=4095 || !db_word(device_field(e,\"characters_truncated\")) || db_word(device_field(e,\"action\"))!=2{return 1;}let i=0;while i<4095{if load8(db_word(t)+i)!=97{return 2;}i=i+1;}return 0;}");
            check(true,"SDK-constructed legacy key text is bounded and explicitly marked truncated without splitting a Unicode surrogate pair");
        }finally{VmHardware.close(context,keys);}
        revoke();
        return new JSONObject().put("ok",true).put("checks",checks).put("physical_devices_verified",false).put("constructed_motion_fixture",true);
    }
    void revoke()throws Exception{
        String id=open(-1,8,0);HardwareInput.Watch watched=VmHardware.handle(context,id,HardwareInput.Watch.class);java.lang.reflect.Method save=MainActivity.class.getDeclaredMethod("savePermission",String.class,Object.class);save.setAccessible(true);ExecutorService executor=Executors.newSingleThreadExecutor();Future<JSONObject> running=null;
        try{
            running=executor.submit(()->host.engineAt(root,3,new JSONObject().put("config",host.workerConfig(root,0)).put("source","fn main(){let h="+quote(id)+";let i=0;while i<10000{device_wait(h,1000);i=i+1;}return 1;}").put("history",new JSONArray())));
            // Observe an actual blocking hardware operation before changing policy.
            java.lang.reflect.Field active=VmHardware.class.getDeclaredField("active");active.setAccessible(true);boolean waiting=false;long end=System.nanoTime()+TimeUnit.SECONDS.toNanos(10);
            while(System.nanoTime()<end&&!waiting){Object operation=active.get(null);if(operation!=null){java.lang.reflect.Field io=operation.getClass().getDeclaredField("cancelIO");io.setAccessible(true);waiting=io.get(operation)!=null;}if(!waiting){if(running.isDone())throw new IOException("Input VM exited before live revocation: "+running.get());Thread.sleep(10);}}
            check(waiting,"the actual VM is waiting in hardware I/O before the Input grant changes");
            ui(()->{try{save.invoke(host,"input",false);}catch(Exception error){throw new RuntimeException(error);}});
            JSONObject stopped=running.get(4,TimeUnit.SECONDS);check(stopped.optString("state").equals("error")&&stopped.optString("stderr").toLowerCase(java.util.Locale.ROOT).contains("cancel"),"changing Input to Deny on the real UI thread cancels an already-running VM program");
            check(watched.closed&&!host.workerConfig(root,0).getJSONObject("permissions").optBoolean("input"),"Input revocation closes the actual SDK listener and updates subsequent policy");
            vm("fn main(){if input_devices(0,16){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"permission_denied\"){return 2;}return 0;}");check(true,"a later VM cannot reopen Input after revocation");
        }finally{if(running!=null&&!running.isDone()){VmHardware.cancel();running.cancel(true);}executor.shutdownNow();VmHardware.closeWorkspace(root);ui(()->{try{save.invoke(host,"input",true);}catch(Exception error){throw new RuntimeException(error);}});}
    }
}
