package org.flexscript.collie;

import android.os.SystemClock;
import java.io.File;
import java.io.IOException;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import org.json.JSONArray;
import org.json.JSONObject;

/** Debug-only oracle over the real accepted SDK socket and actual VM. */
public final class HardwareBluetoothDeadlineChecks {
    static JSONObject vm(MainActivity host,File root,String source)throws Exception {
        JSONObject result=host.engineAt(root,3,new JSONObject().put("config",host.workerConfig(root,0))
            .put("source",source).put("call_id","bluetooth-deadline").put("history",new JSONArray()));
        if(!result.optString("state").equals("continue")||result.optInt("exit_code")!=0)
            throw new IOException("Bluetooth deadline VM: "+result);
        return result;
    }
    public static JSONObject run(MainActivity host,File root)throws Exception {
        String id=vm(host,root,"fn main(){let h=state_get(\"ri-stream\");db_io(0,1,db_word(h),db_bytes(h));return 0;}").getString("stdout");
        VmHardware.Context context=new VmHardware.Context(host,root);
        HardwareBluetooth.Stream stream=VmHardware.handle(context,id,HardwareBluetooth.Stream.class);
        if(!stream.socket.isConnected())throw new IOException("The peer must be connected before the deadline check.");
        CountDownLatch entered=new CountDownLatch(1),release=new CountDownLatch(1),done=new CountDownLatch(1);
        HardwareSensors.events().post(()->{entered.countDown();try{release.await(4,TimeUnit.SECONDS);}catch(InterruptedException e){Thread.currentThread().interrupt();}finally{done.countDown();}});
        try {
            if(!entered.await(2,TimeUnit.SECONDS))throw new IOException("The actual hardware callback Handler did not enter the owned blocker.");
            long start=SystemClock.elapsedRealtime();
            JSONObject result=vm(host,root,"fn main(){let h=db_word(state_get(\"ri-stream\"));if device_read(h,1,100){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"timeout\"){let e=db_error();db_io(0,2,e,db_len(e));return 2;}if device_info(h){return 3;}return 0;}");
            long elapsed=SystemClock.elapsedRealtime()-start;
            boolean handlerHeld=done.getCount()==1,closed=stream.closed&&!stream.socket.isConnected()&&!stream.registered;
            return new JSONObject().put("ok",elapsed>=60&&elapsed<700&&handlerHeld&&closed)
                .put("requested_timeout_ms",100).put("elapsed_ms",elapsed).put("maximum_ms",700)
                .put("callback_handler_still_held",handlerHeld).put("actual_socket_closed",closed)
                .put("observation",result).put("physical_radio_verified",false);
        } finally {
            release.countDown();
            if(!done.await(2,TimeUnit.SECONDS))throw new IOException("The owned callback blocker did not leave.");
        }
    }
}
