package org.flexscript.collie;

import android.bluetooth.*;
import android.content.*;
import android.os.Build;
import android.os.SystemClock;
import java.io.*;
import java.util.UUID;
import java.util.concurrent.*;
import org.json.*;

/** Debug-only independent SDK observations of real link/radio loss. */
public final class HardwareBluetoothLossChecks {
    final MainActivity host;final File root;final boolean radio;
    final JSONArray events=new JSONArray();final CountDownLatch acl=new CountDownLatch(1),off=new CountDownLatch(1);
    HardwareBluetoothLossChecks(MainActivity host,File root,boolean radio){this.host=host;this.root=root;this.radio=radio;}
    public static JSONObject run(MainActivity host,File root)throws Exception{return new HardwareBluetoothLossChecks(host,root,false).run();}
    public static JSONObject runRadio(MainActivity host,File root)throws Exception{return new HardwareBluetoothLossChecks(host,root,true).run();}
    JSONObject vm(String source)throws Exception{return HardwareBluetoothDeadlineChecks.vm(host,root,source);}
    void waitGo(String token,String address)throws Exception {
        File go=new File(root,"bluetooth-loss-go.json");long until=SystemClock.elapsedRealtime()+40000;
        while(SystemClock.elapsedRealtime()<until){
            if(go.isFile()){
                JSONObject value=new JSONObject(MainActivity.read(new FileInputStream(go),4096));
                if(!value.getString("token").equals(token)||!value.getString("address").equals(address)||!value.getString("mode").equals(radio?"radio-off":"peer-forget"))
                    throw new IOException("The read-start handshake does not match this owned socket.");
                return;
            }
            Thread.sleep(10);
        }
        throw new IOException("The host did not arm this owned Bluetooth loss check.");
    }
    JSONObject run()throws Exception {
        if(!host.ownsPermissionRequest(root))throw new IOException("Select the owned loss-fixture workspace.");
        String id=vm("fn main(){let h=state_get(\"ri-stream\");db_io(0,1,db_word(h),db_bytes(h));return 0;}").getString("stdout");
        VmHardware.Context context=new VmHardware.Context(host,root);
        HardwareBluetooth.Stream stream=VmHardware.handle(context,id,HardwareBluetooth.Stream.class);
        BluetoothDevice peer=stream.socket.getRemoteDevice();String address=peer.getAddress(),mode=radio?"radio-off":"peer-forget",token=UUID.randomUUID().toString();
        BluetoothAdapter adapter=HardwareBluetooth.adapter(context);
        if(!stream.socket.isConnected()||!adapter.isEnabled()||peer.getBondState()!=BluetoothDevice.BOND_BONDED)
            throw new IOException("A real connected/bonded SDK peer is required before loss.");
        for(String name:new String[]{"bluetooth-loss-go.json","bluetooth-loss-prepared.json","bluetooth-loss-ready.json"})
            if(new File(root,name).exists())throw new IOException("Loss-check handshake files must be new.");
        Context app=host.getApplicationContext();
        BroadcastReceiver receiver=new BroadcastReceiver(){public void onReceive(Context ignored,Intent intent){
            try{
                String action=intent.getAction();JSONObject event=new JSONObject().put("action",action).put("elapsed_ms",SystemClock.elapsedRealtime());
                if(BluetoothAdapter.ACTION_STATE_CHANGED.equals(action)){
                    int state=intent.getIntExtra(BluetoothAdapter.EXTRA_STATE,-1);event.put("state",state);
                    synchronized(events){if(events.length()<16)events.put(event);}
                    if(state==BluetoothAdapter.STATE_OFF)off.countDown();
                }else{
                    BluetoothDevice actual=intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE);
                    if(actual==null||!address.equals(actual.getAddress()))return;
                    event.put("address",actual.getAddress()).put("transport",intent.getIntExtra(BluetoothDevice.EXTRA_TRANSPORT,BluetoothDevice.TRANSPORT_AUTO));
                    if(BluetoothDevice.ACTION_BOND_STATE_CHANGED.equals(action))event.put("bond_state",intent.getIntExtra(BluetoothDevice.EXTRA_BOND_STATE,-1));
                    synchronized(events){if(events.length()<16)events.put(event);}
                    if(BluetoothDevice.ACTION_ACL_DISCONNECTED.equals(action)&&intent.getIntExtra(BluetoothDevice.EXTRA_TRANSPORT,BluetoothDevice.TRANSPORT_AUTO)!=BluetoothDevice.TRANSPORT_LE)acl.countDown();
                }
            }catch(Exception error){synchronized(events){events.put("callback_error: "+MainActivity.safe(error));}}
        }};
        IntentFilter filter=new IntentFilter();filter.addAction(BluetoothAdapter.ACTION_STATE_CHANGED);filter.addAction(BluetoothDevice.ACTION_ACL_DISCONNECTED);filter.addAction(BluetoothDevice.ACTION_BOND_STATE_CHANGED);
        if(Build.VERSION.SDK_INT>=33)app.registerReceiver(receiver,filter,null,HardwareSensors.events(),Context.RECEIVER_EXPORTED);else app.registerReceiver(receiver,filter,null,HardwareSensors.events());
        ExecutorService observer=Executors.newSingleThreadExecutor();Future<JSONArray> blocked=null;
        try {
            MainActivity.atomic(new File(root,"bluetooth-loss-prepared.json"),new JSONObject().put("token",token).put("mode",mode).put("address",address).toString());
            // The host can navigate to the verified peer detail page before the
            // bounded read starts. Opening Settings must not terminate this VM.
            waitGo(token,address);
            blocked=observer.submit(()->{
                JSONArray stack=HardwareBluetoothIoChecks.blockedRead();
                MainActivity.atomic(new File(root,"bluetooth-loss-ready.json"),new JSONObject().put("token",token).put("mode",mode).put("address",address).put("read_stack",stack).put("elapsed_ms",SystemClock.elapsedRealtime()).toString());
                return stack;
            });
            long start=SystemClock.elapsedRealtime();
            JSONObject observation=vm("fn main(){let h=db_word(state_get(\"ri-stream\"));let v=device_read(h,1,8000);let e=device_error();if db_count(e){let c=db_word(db_at(e,0));if !worker_equal(c,\"disconnected\")&&!worker_equal(c,\"bluetooth_disabled\"){let m=db_error();db_io(0,2,m,db_len(m));return 1;}db_io(0,1,c,db_len(c));}else{if db_kind(v)!=0{return 2;}db_io(0,1,\"eof\",3);}return 0;}");
            long readElapsed=SystemClock.elapsedRealtime()-start;JSONArray stack=blocked.get(2,TimeUnit.SECONDS);
            if(!(radio?off:acl).await(10,TimeUnit.SECONDS))throw new IOException("No independent actual SDK "+(radio?"radio OFF":"peer ACL disconnect")+" event.");
            if(stream.socket.isConnected()||stream.registered||!stream.state.equals("error"))throw new IOException("The failed SDK stream/receiver was not released.");
            if(radio){if(adapter.getState()!=BluetoothAdapter.STATE_OFF)throw new IOException("The actual Android radio did not stay OFF.");}
            else if(!adapter.isEnabled()||peer.getBondState()!=BluetoothDevice.BOND_NONE)throw new IOException("The exact peer was not forgotten while the radio stayed on.");
            HardwareBluetoothIoChecks.ioIdle();
            JSONObject result=new JSONObject().put("ok",true).put("mode",mode).put("address",address).put("read_elapsed_ms",readElapsed)
                .put("actual_blocked_sdk_read_stack",stack).put("observation",observation).put("actual_socket_disconnected",true)
                .put("receiver_unregistered",true).put("actual_io_executor_idle",true).put("actual_acl_disconnect_observed",acl.getCount()==0)
                .put("actual_radio_off_observed",off.getCount()==0).put("physical_radio_verified",false);
            synchronized(events){result.put("independent_sdk_events",new JSONArray(events.toString()));}return result;
        } finally {
            if(blocked!=null)blocked.cancel(true);observer.shutdownNow();
            app.unregisterReceiver(receiver);
            if(!stream.closed)VmHardware.close(context,id);
            if(!observer.awaitTermination(5,TimeUnit.SECONDS))throw new IOException("The owned read observer did not stop.");
        }
    }
}
