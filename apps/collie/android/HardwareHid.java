package org.flexscript.collie;

import android.Manifest;
import android.bluetooth.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.os.Build;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.*;
import org.json.*;

/** Public Classic HID device SDK transport. Descriptors, reports and policy belong to Flexscript. */
final class HardwareHid {
    private static final Object LEASE=new Object();
    private static Endpoint owner;
    private static volatile boolean profileObserved;
    // Android16 HID_DEV_MTU_SIZE is512. The public proxy exposes no peer MTU.
    private static int reportLimit(int id){return id==0?511:510;}
    static boolean supports(String op){return op.startsWith("hid_");}
    static void capabilities(VmHardware.Context c,JSONArray out)throws Exception{
        BluetoothManager manager=c.host.getSystemService(BluetoothManager.class);BluetoothAdapter adapter=manager==null?null:manager.getAdapter();
        boolean possible=Build.VERSION.SDK_INT>=28&&adapter!=null&&c.host.getPackageManager().hasSystemFeature(PackageManager.FEATURE_BLUETOOTH);
        boolean granted=Build.VERSION.SDK_INT<31||c.host.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT)==PackageManager.PERMISSION_GRANTED,busy;
        synchronized(LEASE){busy=owner!=null;}
        out.put(VmHardware.object("id","bluetooth_hid_device","implemented",true,"supported",!possible?false:profileObserved?true:JSONObject.NULL,"support_known",!possible||profileObserved,"available",possible&&profileObserved&&granted&&adapter.isEnabled()&&c.host.hardwareVisible&&!busy,"permission","bluetooth","runtime_permission_required",possible&&!granted,"registration_busy",busy,"foreground_required",true,"mtu_known",false,"report_limit_no_id",511,"report_limit_with_id",510));
    }
    static void hidden(){Endpoint value;synchronized(LEASE){value=owner;}if(value!=null)try{value.close();}catch(IOException ignored){}}
    private static boolean owns(Endpoint value){synchronized(LEASE){return owner==value;}}
    private static void relinquish(Endpoint value){synchronized(LEASE){if(owner==value)owner=null;}}
    private static void visible(VmHardware.Context c)throws Exception{if(!c.host.hardwareVisible)throw new VmHardware.Failure("foreground_required","Keep Collie visible while using Bluetooth HID.");}
    private static String label(JSONArray args,int index)throws Exception{String text=VmHardware.text(args,index,50);if(text.isEmpty()||text.getBytes(StandardCharsets.UTF_8).length>50||text.indexOf('\0')>=0)throw new VmHardware.Failure("invalid_argument","HID name, description and provider require 1..50 UTF-8 bytes without NUL.");return text;}
    private static BluetoothHidDeviceAppQosSettings qos(Object value)throws Exception{
        if(!(value instanceof JSONArray))throw new VmHardware.Failure("invalid_argument","HID QoS is an empty list for defaults, or [service,rate,bucket,peak,latency,variation].");
        JSONArray row=(JSONArray)value;if(row.length()==0)return null;if(row.length()!=6)throw new VmHardware.Failure("invalid_argument","HID QoS requires six integers.");
        return new BluetoothHidDeviceAppQosSettings(VmHardware.integer(row,0,0,2),(int)VmHardware.longInteger(row,1,-1,4294967295L),(int)VmHardware.longInteger(row,2,-1,4294967295L),(int)VmHardware.longInteger(row,3,-1,4294967295L),(int)VmHardware.longInteger(row,4,-1,4294967295L),(int)VmHardware.longInteger(row,5,-1,4294967295L));
    }
    static final class Peer {
        final String id="hid-peer-"+UUID.randomUUID();final BluetoothDevice sdk;int state,protocol=1;Runnable deadline;
        Peer(BluetoothDevice device,int state){sdk=device;this.state=state;}
        JSONObject info()throws Exception{return VmHardware.object("id",id,"address",sdk.getAddress(),"state",state,"protocol",protocol);}
    }
    static final class Request {
        final String token="hid-request-"+UUID.randomUUID(),kind;final Peer peer;final int type,id,buffer;final JSONObject event;Runnable deadline;
        Request(Peer peer,String kind,int type,int id,int buffer,JSONObject event){this.peer=peer;this.kind=kind;this.type=type;this.id=id;this.buffer=buffer;this.event=event;}
    }
    static final class Endpoint extends VmHardware.Handle {
        final VmHardware.Context context;final Context app;final BluetoothAdapter adapter;final BluetoothHidDeviceAppSdpSettings sdp;final BluetoothHidDeviceAppQosSettings incoming,outgoing;final int timeout;
        final BluetoothProfile.ServiceListener listener;final BluetoothHidDevice.Callback callback;final BroadcastReceiver radio;
        final LinkedHashMap<String,Peer> peers=new LinkedHashMap<>();final LinkedHashMap<String,Request> requests=new LinkedHashMap<>();
        BluetoothHidDevice proxy;boolean watching,registrationSent,retiring,teardownConfirmed;String state="pending";JSONObject lastResult;
        final Runnable deadline=()->{synchronized(Endpoint.this){if(state.equals("pending")||state.equals("registering"))fail("timeout","Android did not register the HID application before its deadline.");}};
        final Runnable retireDeadline=()->{synchronized(Endpoint.this){if(retiring&&!teardownConfirmed){event("cleanup_unconfirmed","message","Android did not confirm HID unregistration; a new Collie HID registration remains blocked until confirmation or app restart.");closeProxy();}}};
        Endpoint(VmHardware.Context c,BluetoothAdapter adapter,BluetoothHidDeviceAppSdpSettings sdp,BluetoothHidDeviceAppQosSettings in,BluetoothHidDeviceAppQosSettings out,int timeout){
            super(c,"bluetooth","bluetooth_hid_device");context=c;app=c.host.getApplicationContext();this.adapter=adapter;this.sdp=sdp;incoming=in;outgoing=out;this.timeout=timeout;
            radio=new BroadcastReceiver(){public void onReceive(Context ignored,Intent intent){if(intent.getIntExtra(BluetoothAdapter.EXTRA_STATE,-1)!=BluetoothAdapter.STATE_ON){synchronized(Endpoint.this){fail("bluetooth_disabled","Android Bluetooth was turned off.");finishRetire();}}}};
            listener=new BluetoothProfile.ServiceListener(){public void onServiceConnected(int profile,BluetoothProfile service){attached(profile,service);}public void onServiceDisconnected(int profile){synchronized(Endpoint.this){if(profile!=BluetoothProfile.HID_DEVICE)return;fail("service_disconnected","Android's HID profile service disconnected.");finishRetire();}}};
            callback=new BluetoothHidDevice.Callback(){
                public void onAppStatusChanged(BluetoothDevice plugged,boolean registered){registration(plugged,registered);}
                public void onConnectionStateChanged(BluetoothDevice device,int next){connection(device,next);}
                public void onGetReport(BluetoothDevice device,byte type,byte id,int buffer){request(device,"get_report",type&255,id&255,buffer,null);}
                public void onSetReport(BluetoothDevice device,byte type,byte id,byte[] bytes){request(device,"set_report",type&255,id&255,0,snapshot(bytes));}
                public void onInterruptData(BluetoothDevice device,byte id,byte[] bytes){interrupt(device,id&255,snapshot(bytes));}
                public void onSetProtocol(BluetoothDevice device,byte protocol){protocol(device,protocol&255);}
                public void onVirtualCableUnplug(BluetoothDevice device){synchronized(Endpoint.this){if(closed||retiring)return;Peer peer=device==null?null:peers.get(device.getAddress());event("virtual_cable_unplug","peer",peer==null?JSONObject.NULL:peer.id,"address",device==null?JSONObject.NULL:device.getAddress());}}
            };
        }
        byte[] snapshot(byte[] bytes){return bytes==null?null:Arrays.copyOf(bytes,Math.min(bytes.length,513));}
        void event(String name,Object... values){try{Object[] fields=new Object[values.length+2];fields[0]="event";fields[1]=name;System.arraycopy(values,0,fields,2,values.length);lastResult=VmHardware.object(fields);emit(lastResult);}catch(Exception ignored){}}
        void start()throws Exception{
            synchronized(this){check();IntentFilter filter=new IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED);if(Build.VERSION.SDK_INT>=33)app.registerReceiver(radio,filter,null,HardwareSensors.events(),Context.RECEIVER_EXPORTED);else app.registerReceiver(radio,filter,null,HardwareSensors.events());watching=true;HardwareSensors.events().postDelayed(deadline,timeout);}
            if(!adapter.getProfileProxy(app,listener,BluetoothProfile.HID_DEVICE))throw new VmHardware.Failure("unavailable","Android refused to request a HID device profile proxy.");
        }
        synchronized void attached(int profile,BluetoothProfile service){
            if(profile!=BluetoothProfile.HID_DEVICE||!(service instanceof BluetoothHidDevice)){fail("callback_mismatch","Android returned a different Bluetooth profile.");return;}
            if(closed||retiring||!owns(this)){adapter.closeProfileProxy(profile,service);return;}
            if(proxy!=null){if(proxy!=service)adapter.closeProfileProxy(profile,service);return;}
            proxy=(BluetoothHidDevice)service;profileObserved=true;
            try{visible(context);state="registering";registrationSent=true;if(!proxy.registerApp(sdp,incoming,outgoing,task->HardwareSensors.events().post(task),callback)){registrationSent=false;fail("registration_rejected","Android refused the HID registration command.");}}
            catch(Exception error){fail("platform_error",MainActivity.safe(error));}
        }
        synchronized void registration(BluetoothDevice plugged,boolean registered){
            if(!owns(this))return;
            if(!registered){registrationSent=false;if(!closed&&!retiring)fail("unregistered","Android unregistered the HID application or rejected registration.");finishRetire();return;}
            if(closed||retiring){try{if(proxy!=null)proxy.unregisterApp();}catch(RuntimeException ignored){}return;}
            if(!context.host.hardwareVisible){fail("foreground_required","Android HID registration requires the foreground app.");return;}
            state="registered";HardwareSensors.events().removeCallbacks(deadline);event("registered","plugged_address",plugged==null?JSONObject.NULL:plugged.getAddress());
            try{for(BluetoothDevice device:proxy.getConnectedDevices())connection(device,BluetoothProfile.STATE_CONNECTED);}catch(RuntimeException error){fail("platform_error",MainActivity.safe(error));}
        }
        void closeProxy(){BluetoothHidDevice value=proxy;proxy=null;if(value!=null)try{adapter.closeProfileProxy(BluetoothProfile.HID_DEVICE,value);}catch(RuntimeException ignored){}}
        void finishRetire(){HardwareSensors.events().removeCallbacks(retireDeadline);registrationSent=false;teardownConfirmed=true;closeProxy();relinquish(this);}
        void retire(){
            if(retiring)return;retiring=true;HardwareSensors.events().removeCallbacks(deadline);
            for(Peer peer:peers.values())if(peer.deadline!=null)HardwareSensors.events().removeCallbacks(peer.deadline);for(Request r:requests.values())HardwareSensors.events().removeCallbacks(r.deadline);peers.clear();requests.clear();
            if(watching){watching=false;try{app.unregisterReceiver(radio);}catch(RuntimeException ignored){}}
            if(proxy!=null&&registrationSent){HardwareSensors.events().postDelayed(retireDeadline,10000);try{proxy.unregisterApp();}catch(RuntimeException ignored){}return;}
            finishRetire();
        }
        synchronized void fail(String code,String message){if(closed||retiring)return;state="error";event("error","code",code,"message",message);retire();}
        public void access(VmHardware.Context c)throws Exception{check();HardwareBluetooth.connectPermission(c);}
        void ready()throws Exception{check();visible(context);if(!state.equals("registered")||retiring||proxy==null)throw new VmHardware.Failure("not_ready","Wait for an actual HID registered event before operating the endpoint.");}
        public synchronized Object info()throws Exception{check();return VmHardware.object("kind",kind,"state",state,"peers",peers.size(),"pending_requests",requests.size(),"foreground_required",true,"teardown_confirmed",teardownConfirmed,"last_result",lastResult==null?JSONObject.NULL:lastResult);}
        Peer peer(String id)throws Exception{ready();for(Peer value:peers.values())if(value.id.equals(id))return value;throw new VmHardware.Failure("stale_peer","Use a live peer ID owned by this HID endpoint.");}
        Peer connected(String id)throws Exception{Peer value=peer(id);if(value.state!=BluetoothProfile.STATE_CONNECTED)throw new VmHardware.Failure("disconnected","Wait for the HID peer to be connected.");return value;}
        synchronized String connect(BluetoothDevice device)throws Exception{
            ready();if(device.getBondState()!=BluetoothDevice.BOND_BONDED)throw new VmHardware.Failure("not_paired","Pair the explicit Bluetooth device with Android before opening its HID connection.");
            if(!peers.isEmpty())throw new VmHardware.Failure("busy","Disconnect the current HID peer before connecting another host.");Peer value=new Peer(device,BluetoothProfile.STATE_CONNECTING);peers.put(device.getAddress(),value);arm(value);
            try{if(!proxy.connect(device)){peers.remove(device.getAddress());HardwareSensors.events().removeCallbacks(value.deadline);throw new VmHardware.Failure("platform_error","Android refused the HID connection command.");}return value.id;}catch(VmHardware.Failure error){throw error;}catch(RuntimeException error){fail("platform_error",MainActivity.safe(error));throw error;}
        }
        void arm(Peer value){if(value.deadline!=null)HardwareSensors.events().removeCallbacks(value.deadline);value.deadline=()->{synchronized(Endpoint.this){if(peers.get(value.sdk.getAddress())==value&&(value.state==BluetoothProfile.STATE_CONNECTING||value.state==BluetoothProfile.STATE_DISCONNECTING))fail("timeout","Android HID connection state did not complete before its deadline.");}};HardwareSensors.events().postDelayed(value.deadline,timeout);}
        synchronized void connection(BluetoothDevice device,int next){
            if(closed||retiring||!state.equals("registered"))return;if(device==null){fail("callback_mismatch","Android omitted the HID callback peer.");return;}Peer value=peers.get(device.getAddress());
            if(next==BluetoothProfile.STATE_DISCONNECTED){if(value==null)return;if(value.deadline!=null)HardwareSensors.events().removeCallbacks(value.deadline);peers.remove(device.getAddress());for(Request r:new ArrayList<>(requests.values()))if(r.peer==value){HardwareSensors.events().removeCallbacks(r.deadline);requests.remove(r.token);}event("disconnected","peer",value.id,"address",device.getAddress(),"state",next);return;}
            if(next!=BluetoothProfile.STATE_CONNECTING&&next!=BluetoothProfile.STATE_CONNECTED&&next!=BluetoothProfile.STATE_DISCONNECTING){fail("callback_failed","Android reported an invalid HID connection state.");return;}
            if(value==null){if(peers.size()>=8){fail("resource_limit","Android reported more than eight HID peers.");return;}value=new Peer(device,next);peers.put(device.getAddress(),value);}value.state=next;
            if(next==BluetoothProfile.STATE_CONNECTED){if(value.deadline!=null)HardwareSensors.events().removeCallbacks(value.deadline);value.deadline=null;}else arm(value);
            event(next==BluetoothProfile.STATE_CONNECTED?"connected":"connection_state","peer",value.id,"address",device.getAddress(),"state",next);
        }
        synchronized Object peers(int offset,int limit)throws Exception{ready();List<Peer> rows=new ArrayList<>(peers.values());JSONArray result=new JSONArray();for(int i=offset;i<Math.min(offset+limit,rows.size());i++)result.put(rows.get(i).info());return VmHardware.object("peers",result,"total",rows.size(),"next",offset+result.length()<rows.size()?offset+result.length():-1);}
        synchronized void request(BluetoothDevice device,String kind,int type,int id,int buffer,byte[] bytes){
            if(closed||retiring||!state.equals("registered"))return;if(device==null){fail("callback_mismatch","Android omitted the HID callback peer.");return;}Peer value=peers.get(device.getAddress());if(value==null||value.state!=BluetoothProfile.STATE_CONNECTED){fail("callback_mismatch","Android delivered a HID control request without its connected peer.");return;}
            if(type<1||type>3||buffer<0||buffer>65535||kind.equals("set_report")&&(bytes==null||bytes.length>reportLimit(id))){fail("size_limit","Android delivered an invalid or oversized HID control request.");return;}
            for(Request r:requests.values())if(r.peer==value){fail("callback_mismatch","The HID peer sent overlapping control transactions without request IDs.");return;}
            try{JSONObject event=VmHardware.object("event","request","kind",kind,"peer",value.id,"report_type",type,"report_id",id,"buffer_size",buffer,"value",bytes==null?JSONObject.NULL:VmHardware.bytes(bytes));Request r=new Request(value,kind,type,id,buffer,event);event.put("token",r.token);r.deadline=()->{synchronized(Endpoint.this){if(requests.get(r.token)==r){try{if(proxy!=null)proxy.reportError(value.sdk,BluetoothHidDevice.ERROR_RSP_NOT_READY);}catch(RuntimeException ignored){}fail("timeout","A HID control request expired; the registration closed to discard ambiguous late replies.");}}};requests.put(r.token,r);HardwareSensors.events().postDelayed(r.deadline,timeout);emit(event);}catch(Exception error){fail("callback_failed",MainActivity.safe(error));}
        }
        synchronized void interrupt(BluetoothDevice device,int id,byte[] bytes){if(closed||retiring||!state.equals("registered"))return;if(device==null){fail("callback_mismatch","Android omitted the HID callback peer.");return;}Peer value=peers.get(device.getAddress());if(value==null||value.state!=BluetoothProfile.STATE_CONNECTED)return;if(bytes==null||bytes.length>reportLimit(id)){fail("size_limit","Android delivered an oversized HID output report.");return;}try{event("output_report","peer",value.id,"report_type",2,"report_id",id,"value",VmHardware.bytes(bytes));}catch(Exception error){fail("callback_failed",MainActivity.safe(error));}}
        synchronized void protocol(BluetoothDevice device,int mode){if(closed||retiring)return;if(device==null){fail("callback_mismatch","Android omitted the HID protocol peer.");return;}Peer value=peers.get(device.getAddress());if(value==null)return;if(mode!=0&&mode!=1){fail("callback_failed","Android delivered an invalid HID protocol mode.");return;}value.protocol=mode;event("protocol","peer",value.id,"protocol",mode);}
        synchronized Object pending(int offset,int limit)throws Exception{ready();List<Request> rows=new ArrayList<>(requests.values());JSONArray result=new JSONArray();for(int i=offset;i<Math.min(offset+limit,rows.size());i++)result.put(rows.get(i).event);return VmHardware.object("requests",result,"total",rows.size(),"next",offset+result.length()<rows.size()?offset+result.length():-1);}
        synchronized int respond(String token,byte[] bytes,int error,boolean data)throws Exception{
            ready();Request r=requests.get(token);if(r==null)throw new VmHardware.Failure("stale_request","This HID request expired, was answered, or belongs to another endpoint.");
            if(data&&!r.kind.equals("get_report"))throw new VmHardware.Failure("wrong_request","Use hid_error(token,0) to acknowledge SET_REPORT; hid_reply answers GET_REPORT.");if(bytes.length>reportLimit(r.id))throw new VmHardware.Failure("size_limit","HID response exceeds the 512-byte transport bound including its header/report ID.");
            if(!data&&error>4&&error!=14)throw new VmHardware.Failure("invalid_argument","HID error codes are0,1,2,3,4,14.");if(!data&&error==0&&r.kind.equals("get_report"))throw new VmHardware.Failure("wrong_request","A successful GET_REPORT requires report bytes through hid_reply.");
            requests.remove(token);HardwareSensors.events().removeCallbacks(r.deadline);
            try{boolean accepted=data?proxy.replyReport(r.peer.sdk,(byte)r.type,(byte)r.id,Arrays.copyOf(bytes,bytes.length)):proxy.reportError(r.peer.sdk,(byte)error);if(!accepted){fail("platform_error","Android refused the HID response command.");throw new VmHardware.Failure("platform_error","Android refused the HID response command.");}return 1;}catch(VmHardware.Failure failure){throw failure;}catch(RuntimeException failure){fail("platform_error",MainActivity.safe(failure));throw failure;}
        }
        synchronized int send(String id,int report,byte[] bytes)throws Exception{Peer value=connected(id);if(bytes.length>reportLimit(report))throw new VmHardware.Failure("size_limit","HID report exceeds the 512-byte transport bound including its header/report ID.");if(!proxy.sendReport(value.sdk,report,Arrays.copyOf(bytes,bytes.length)))throw new VmHardware.Failure("platform_error","Android refused the HID input-report command.");return 1;}
        synchronized int disconnect(String id)throws Exception{Peer value=connected(id);for(Request r:requests.values())if(r.peer==value)throw new VmHardware.Failure("busy","Answer the peer's pending HID control request before disconnecting.");if(!proxy.disconnect(value.sdk))throw new VmHardware.Failure("platform_error","Android refused the HID disconnect command.");value.state=BluetoothProfile.STATE_DISCONNECTING;arm(value);return 1;}
        public synchronized void close()throws IOException{if(closed)return;state="closed";super.close();retire();}
    }
    static Object call(VmHardware.Context c,String op,JSONArray a)throws Exception{
        if(Build.VERSION.SDK_INT<28)throw new VmHardware.Failure("unsupported","Android's public HID device API requires Android9 or newer.");
        if(op.equals("hid_open")){
            String name=label(a,0),description=label(a,1),provider=label(a,2);int subclass=VmHardware.integer(a,3,0,255),timeout=VmHardware.integer(a,7,1000,25000);byte[] descriptor=VmHardware.data(a.get(4));if(descriptor.length<1||descriptor.length>2048)throw new VmHardware.Failure("size_limit","A HID report descriptor requires1..2048 bytes.");BluetoothHidDeviceAppQosSettings in=qos(a.get(5)),out=qos(a.get(6));
            BluetoothAdapter adapter=HardwareBluetooth.adapter(c);HardwareBluetooth.connectPermission(c);visible(c);if(!adapter.isEnabled())throw new VmHardware.Failure("bluetooth_disabled","Turn on Bluetooth before registering HID.");Endpoint endpoint;
            synchronized(LEASE){if(owner!=null)throw new VmHardware.Failure("busy","Only one Collie HID registration may be active or awaiting confirmed teardown.");endpoint=new Endpoint(c,adapter,new BluetoothHidDeviceAppSdpSettings(name,description,provider,(byte)subclass,descriptor),in,out,timeout);owner=endpoint;}
            VmHardware.blocking(endpoint);try{endpoint.start();return VmHardware.add(endpoint);}catch(Exception error){endpoint.close();throw error;}finally{VmHardware.unblocking();}
        }
        Endpoint endpoint=VmHardware.handle(c,VmHardware.text(a,0,128),Endpoint.class);endpoint.access(c);
        if(op.equals("hid_connect")){HardwareBluetooth.Device peer=VmHardware.handle(c,VmHardware.text(a,1,128),HardwareBluetooth.Device.class);peer.access(c);return endpoint.connect(peer.device);}
        if(op.equals("hid_peers"))return endpoint.peers(VmHardware.integer(a,1,0,8),VmHardware.integer(a,2,1,8));
        if(op.equals("hid_requests"))return endpoint.pending(VmHardware.integer(a,1,0,8),VmHardware.integer(a,2,1,8));
        if(op.equals("hid_reply"))return endpoint.respond(VmHardware.text(a,1,128),VmHardware.data(a.get(2)),0,true);
        if(op.equals("hid_error"))return endpoint.respond(VmHardware.text(a,1,128),new byte[0],VmHardware.integer(a,2,0,14),false);
        if(op.equals("hid_send"))return endpoint.send(VmHardware.text(a,1,128),VmHardware.integer(a,2,0,255),VmHardware.data(a.get(3)));
        if(op.equals("hid_disconnect"))return endpoint.disconnect(VmHardware.text(a,1,128));
        throw new VmHardware.Failure("unsupported_operation","Unknown HID device operation.");
    }
}
