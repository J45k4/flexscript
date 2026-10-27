package org.flexscript.collie;

import android.os.SystemClock;
import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.lang.reflect.Method;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicReference;
import org.json.*;

/** Debug-only checks using the real UI actions, VM and connected SDK socket. */
public final class HardwareBluetoothIoChecks {
    final MainActivity host;
    final File root;
    HardwareBluetoothIoChecks(MainActivity host,File root){this.host=host;this.root=root;}
    public static JSONObject run(MainActivity host,File root)throws Exception{return new HardwareBluetoothIoChecks(host,root).run(false);}
    public static JSONObject runRevoke(MainActivity host,File root)throws Exception{return new HardwareBluetoothIoChecks(host,root).run(true);}
    interface Action { void run()throws Exception; }
    void main(Action action)throws Exception {
        CountDownLatch done=new CountDownLatch(1);AtomicReference<Throwable> error=new AtomicReference<>();
        host.runOnUiThread(()->{try{action.run();}catch(Throwable failure){error.set(failure);}finally{done.countDown();}});
        if(!done.await(4,TimeUnit.SECONDS))throw new IOException("The real Bluetooth UI action did not return.");
        if(error.get()!=null)throw new IOException(error.get());
    }
    JSONObject execute(String source)throws Exception {
        return host.engineAt(root,3,new JSONObject().put("config",host.workerConfig(root,0))
            .put("source",source).put("call_id","bluetooth-blocked-io").put("history",new JSONArray()));
    }
    JSONObject success(String source)throws Exception {
        JSONObject result=execute(source);
        if(!result.optString("state").equals("continue")||result.optInt("exit_code")!=0)
            throw new IOException("Bluetooth I/O VM: "+result);
        return result;
    }
    static JSONArray blockedRead()throws Exception {
        long until=SystemClock.elapsedRealtime()+3000;
        while(SystemClock.elapsedRealtime()<until){
            for(Map.Entry<Thread,StackTraceElement[]> entry:Thread.getAllStackTraces().entrySet()){
                if(!entry.getKey().getName().equals("collie-hardware-io"))continue;
                boolean adapter=false,sdk=false,nativeRead=false;JSONArray frames=new JSONArray();
                for(StackTraceElement frame:entry.getValue()){
                    frames.put(frame.toString());
                    if(frame.getClassName().equals("org.flexscript.collie.HardwareBluetooth$Stream")&&frame.getMethodName().equals("read"))adapter=true;
                    if(frame.getClassName().equals("android.bluetooth.BluetoothSocket")&&frame.getMethodName().equals("read"))sdk=true;
                    if(frame.getClassName().equals("android.net.LocalSocketImpl")&&frame.isNativeMethod()&&frame.getMethodName().contains("read"))nativeRead=true;
                }
                if(adapter&&sdk&&nativeRead)return frames;
            }
            Thread.sleep(5);
        }
        throw new IOException("No actual Bluetooth/LocalSocket native read was observed before the action.");
    }
    static void ioIdle()throws Exception {
        java.lang.reflect.Field field=VmHardware.class.getDeclaredField("IO");field.setAccessible(true);
        ThreadPoolExecutor pool=(ThreadPoolExecutor)field.get(null);long until=SystemClock.elapsedRealtime()+2000;
        while(SystemClock.elapsedRealtime()<until){if(pool.getActiveCount()==0&&pool.getQueue().isEmpty())return;Thread.sleep(5);}
        throw new IOException("The actual hardware-I/O job remained active/queued after socket cancellation.");
    }
    JSONObject run(boolean revoke)throws Exception {
        if(!host.ownsPermissionRequest(root)||!host.workerConfig(root,0).getJSONObject("permissions").getBoolean("bluetooth"))
            throw new IOException("The selected fixture workspace must start with Bluetooth allowed.");
        String id=success("fn main(){let h=state_get(\"ri-stream\");db_io(0,1,db_word(h),db_bytes(h));return 0;}").getString("stdout");
        VmHardware.Context context=new VmHardware.Context(host,root);
        HardwareBluetooth.Stream stream=VmHardware.handle(context,id,HardwareBluetooth.Stream.class);
        if(!stream.socket.isConnected())throw new IOException("Connect the actual SDK peer before checking blocked I/O.");
        ExecutorService control=Executors.newSingleThreadExecutor();AtomicLong started=new AtomicLong();
        Future<JSONArray> action=control.submit(()->{
            JSONArray stack=blockedRead();started.set(SystemClock.elapsedRealtime());
            main(()->{if(revoke)host.savePermission("bluetooth",false);else{Method stop=MainActivity.class.getDeclaredMethod("cancel");stop.setAccessible(true);stop.invoke(host);}});
            return stack;
        });
        try {
            // Run on the normal turn thread: the actual Stop action checks that
            // nativeThread is turnThread before cancelling native execution.
            JSONObject stopped=execute("fn main(){let h=db_word(state_get(\"ri-stream\"));device_read(h,1,8000);db_io(0,1,\"continued\",9);return 1;}");
            JSONArray stack=action.get(2,TimeUnit.SECONDS);long elapsed=SystemClock.elapsedRealtime()-started.get();
            if(!stopped.optString("state").equals("error")||!stopped.optString("stderr").toLowerCase(Locale.ROOT).contains("cancel")||!stopped.optString("stdout").isEmpty())
                throw new IOException("The actual UI action did not cancel the blocked native program: "+stopped);
            if(elapsed<0||elapsed>=1500||!stream.closed||stream.socket.isConnected()||stream.registered)
                throw new IOException("Cancelled Bluetooth SDK socket/receiver was not released promptly: "+elapsed+" ms");
            boolean denied=false,persisted=false;
            if(revoke){
                JSONObject session=new JSONObject(MainActivity.read(new FileInputStream(new File(root,"session.json")),4*1024*1024));
                persisted=!session.getJSONObject("permissions").getBoolean("bluetooth");
                denied=!host.workerConfig(root,0).getJSONObject("permissions").getBoolean("bluetooth");
                if(!persisted||!denied)throw new IOException("Bluetooth revocation did not persist/publish its real policy.");
                success("fn main(){if bt_info(){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"permission_denied\"){return 2;}return 0;}");
            }else{
                success("fn main(){if device_info(db_word(state_get(\"ri-stream\"))){return 1;}let e=db_word(db_at(device_error(),0));if !worker_equal(e,\"disconnected\")&&!worker_equal(e,\"stale_handle\"){return 2;}return 0;}");
                success("fn main(){if !bt_info(){return 1;}return 0;}");
            }
            ioIdle();
            return new JSONObject().put("ok",true).put("action",revoke?"revoke":"cancel").put("elapsed_ms",elapsed)
                .put("actual_blocked_sdk_read_stack",stack).put("actual_socket_closed",true).put("receiver_unregistered",true)
                .put("native_cancelled_observation",stopped).put("denied_policy_persisted",persisted)
                .put("later_program_denied",denied).put("actual_io_executor_idle",true).put("physical_radio_verified",false);
        } finally {
            action.cancel(true);control.shutdownNow();
            if(!control.awaitTermination(5,TimeUnit.SECONDS))throw new IOException("The owned Bluetooth action controller did not stop.");
            if(revoke)main(()->host.savePermission("bluetooth",true));
        }
    }
}
