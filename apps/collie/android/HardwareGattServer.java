package org.flexscript.collie;

import android.Manifest;
import android.bluetooth.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.os.Build;
import java.io.IOException;
import java.util.*;
import org.json.*;

/** Android GATT service objects and request transport; values/transactions live in Flexscript. */
final class HardwareGattServer {
    static boolean supports(String op){return op.startsWith("ble_server_");}
    static void capabilities(VmHardware.Context c,JSONArray out)throws Exception{
        BluetoothManager manager=c.host.getSystemService(BluetoothManager.class);BluetoothAdapter adapter=manager==null?null:manager.getAdapter();boolean supported=adapter!=null&&c.host.getPackageManager().hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE);
        boolean permitted=Build.VERSION.SDK_INT<31||c.host.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT)==PackageManager.PERMISSION_GRANTED;
        out.put(VmHardware.object("id","bluetooth_le_gatt_server","implemented",true,"supported",supported,"available",supported&&permitted&&adapter.isEnabled(),"permission","bluetooth","runtime_permission_required",supported&&!permitted));
    }
    static UUID uuid(String value)throws Exception{android.os.ParcelUuid id=HardwareBle.uuid(value);if(id==null)throw new VmHardware.Failure("invalid_argument","A GATT service/attribute UUID cannot be empty.");return id.getUuid();}
    static JSONArray list(Object value,int limit)throws Exception{if(!(value instanceof JSONArray)||((JSONArray)value).length()>limit)throw new VmHardware.Failure("invalid_argument","GATT definitions require bounded typed lists.");return (JSONArray)value;}
    static int permissions(JSONArray row,int index)throws Exception{int value=VmHardware.integer(row,index,0,503);if((value&~503)!=0)throw new VmHardware.Failure("invalid_argument","Use Android GATT permission flags (read1/2/4,write16/32/64/128/256).");return value;}
    static final class Node {
        final String id="gatt-local-"+UUID.randomUUID(),parent,kind;final Object sdk;final UUID uuid;boolean active;
        Node(Object sdk,String parent,String kind,UUID uuid){this.sdk=sdk;this.parent=parent;this.kind=kind;this.uuid=uuid;}
        JSONObject info()throws Exception{JSONObject row=VmHardware.object("id",id,"parent",parent,"kind",kind,"uuid",uuid.toString(),"active",active);if(sdk instanceof BluetoothGattService)row.put("type",((BluetoothGattService)sdk).getType());if(sdk instanceof BluetoothGattCharacteristic)row.put("properties",((BluetoothGattCharacteristic)sdk).getProperties()).put("permissions",((BluetoothGattCharacteristic)sdk).getPermissions());if(sdk instanceof BluetoothGattDescriptor)row.put("permissions",((BluetoothGattDescriptor)sdk).getPermissions());return row;}
    }
    static final class Peer {
        final String id="gatt-peer-"+UUID.randomUUID();final BluetoothDevice sdk;int mtu=23,lastId=-1,pendingId=-1;boolean mtuObserved,closing,confirm;String operation="",attribute="";Runnable deadline;JSONObject lastResult;
        Peer(BluetoothDevice sdk){this.sdk=sdk;}
        JSONObject info()throws Exception{return VmHardware.object("id",id,"address",sdk.getAddress(),"state",closing?"closing":"connected","mtu",mtu,"mtu_observed",mtuObserved,"last_request_id",lastId,"pending_id",pendingId,"pending_operation",operation,"last_result",lastResult==null?JSONObject.NULL:lastResult);}
    }
    static final class Request {
        final String token="gatt-request-"+UUID.randomUUID();final Peer peer;final int sdkId,offset;final JSONObject event;Runnable deadline;
        Request(Peer peer,int sdkId,int offset,JSONObject event){this.peer=peer;this.sdkId=sdkId;this.offset=offset;this.event=event;}
    }
    static final class Server extends VmHardware.Handle {
        final VmHardware.Context context;final Context app;final int timeout;final BroadcastReceiver radio;final BluetoothGattServerCallback callback;
        BluetoothGattServer gatt;boolean registered;String state="opening",adding="";long expired;
        JSONObject lastResult;
        final LinkedHashMap<String,Node> nodes=new LinkedHashMap<>();final IdentityHashMap<Object,Node> identities=new IdentityHashMap<>();
        final LinkedHashMap<String,Peer> peers=new LinkedHashMap<>();final LinkedHashMap<String,Request> requests=new LinkedHashMap<>();
        final Runnable addDeadline=()->{synchronized(Server.this){if(!adding.isEmpty())fail("timeout","Android did not register the GATT service before its deadline.");}};
        Server(VmHardware.Context c,int timeout){
            super(c,"bluetooth","bluetooth_le_gatt_server");context=c;app=c.host.getApplicationContext();this.timeout=timeout;
            radio=new BroadcastReceiver(){public void onReceive(Context ignored,Intent intent){if(intent.getIntExtra(BluetoothAdapter.EXTRA_STATE,-1)!=BluetoothAdapter.STATE_ON)fail("bluetooth_disabled","Android Bluetooth was turned off.");}};
            callback=new BluetoothGattServerCallback(){
                public void onServiceAdded(int status,BluetoothGattService service){added(status,service);}
                public void onConnectionStateChange(BluetoothDevice device,int status,int next){connection(device,status,next);}
                public void onCharacteristicReadRequest(BluetoothDevice device,int id,int offset,BluetoothGattCharacteristic item){request(device,id,item,"read",offset,false,true,false,null);}
                public void onDescriptorReadRequest(BluetoothDevice device,int id,int offset,BluetoothGattDescriptor item){request(device,id,item,"read",offset,false,true,false,null);}
                public void onCharacteristicWriteRequest(BluetoothDevice device,int id,BluetoothGattCharacteristic item,boolean prepared,boolean response,int offset,byte[] value){request(device,id,item,"write",offset,prepared,response,false,HardwareGattClient.snapshot(value));}
                public void onDescriptorWriteRequest(BluetoothDevice device,int id,BluetoothGattDescriptor item,boolean prepared,boolean response,int offset,byte[] value){request(device,id,item,"write",offset,prepared,response,false,HardwareGattClient.snapshot(value));}
                public void onExecuteWrite(BluetoothDevice device,int id,boolean execute){request(device,id,null,"execute",0,false,true,execute,null);}
                public void onMtuChanged(BluetoothDevice device,int mtu){mtu(device,mtu);}
                public void onNotificationSent(BluetoothDevice device,int status){completed(device,"notify",status);}
                public void onPhyRead(BluetoothDevice device,int tx,int rx,int status){completed(device,"phy_read",status,"tx_phy",tx,"rx_phy",rx);}
                public void onPhyUpdate(BluetoothDevice device,int tx,int rx,int status){completed(device,"phy",status,"tx_phy",tx,"rx_phy",rx);}
            };
        }
        void start()throws Exception{
            synchronized(this){check();IntentFilter filter=new IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED);if(Build.VERSION.SDK_INT>=33)app.registerReceiver(radio,filter,null,HardwareSensors.events(),Context.RECEIVER_EXPORTED);else app.registerReceiver(radio,filter,null,HardwareSensors.events());registered=true;}
            BluetoothGattServer opened=app.getSystemService(BluetoothManager.class).openGattServer(app,callback);
            synchronized(this){if(closed||state.equals("error")){if(opened!=null)opened.close();throw new VmHardware.Failure("cancelled","The GATT server closed while Android was opening it.");}if(opened==null)throw new VmHardware.Failure("unavailable","Android refused to open a GATT server.");gatt=opened;state="open";HardwareBle.event(this,"ready");}
        }
        void open()throws Exception{check();if(!state.equals("open")||gatt==null)throw new VmHardware.Failure("disconnected","The GATT server is not open.");}
        void clearPeer(Peer peer){if(peer.deadline!=null)HardwareSensors.events().removeCallbacks(peer.deadline);peer.deadline=null;peer.operation="";peer.pendingId=-1;peer.attribute="";}
        void release(){
            HardwareSensors.events().removeCallbacks(addDeadline);for(Request request:requests.values()){HardwareSensors.events().removeCallbacks(request.deadline);reply(request.peer.sdk,request.sdkId,14,0,new byte[0]);}requests.clear();
            BluetoothGattServer closing=gatt;gatt=null;for(Peer peer:peers.values())clearPeer(peer);peers.clear();nodes.clear();identities.clear();adding="";
            if(registered){registered=false;try{app.unregisterReceiver(radio);}catch(RuntimeException ignored){}}if(closing!=null)try{closing.close();}catch(RuntimeException ignored){}
        }
        synchronized void fail(String code,String message){if(closed||state.equals("error"))return;state="error";try{lastResult=VmHardware.object("event","error","code",code,"message",message);emit(lastResult);}catch(Exception ignored){}release();}
        public void access(VmHardware.Context c)throws Exception{check();HardwareBluetooth.connectPermission(c);}
        public synchronized Object info()throws Exception{check();return VmHardware.object("kind",kind,"state",state,"attributes",nodes.size(),"peers",peers.size(),"pending_requests",requests.size(),"pending_service",adding,"expired_requests",expired,"last_result",lastResult==null?JSONObject.NULL:lastResult);}
        Node node(String id)throws Exception{open();Node value=nodes.get(id);if(value==null)throw new VmHardware.Failure("stale_attribute","Use a local attribute ID owned by this GATT server.");return value;}
        Peer peer(String id)throws Exception{open();for(Peer peer:peers.values())if(peer.id.equals(id)){if(peer.closing)throw new VmHardware.Failure("disconnected","The GATT peer is disconnecting.");return peer;}throw new VmHardware.Failure("stale_peer","Use a connected peer ID owned by this GATT server.");}
        Node add(Object sdk,String parent,String kind,UUID uuid){Node node=new Node(sdk,parent,kind,uuid);nodes.put(node.id,node);identities.put(sdk,node);return node;}
        void removeNodes(String service){Set<String> removing=new HashSet<>();removing.add(service);boolean more=true;while(more){more=false;for(Node value:nodes.values())if(removing.contains(value.parent)&&removing.add(value.id))more=true;}for(String id:removing){Node value=nodes.remove(id);if(value!=null)identities.remove(value.sdk);}}
        synchronized String service(UUID uuid,int type,JSONArray definitions)throws Exception{
            open();if(!adding.isEmpty())throw new VmHardware.Failure("busy","Wait for service_added before registering another service.");
            int count=0;for(Node n:nodes.values())if(n.kind.equals("service"))count++;if(count>=32)throw new VmHardware.Failure("resource_limit","At most 32 services may be owned by one GATT server.");
            BluetoothGattService service=new BluetoothGattService(uuid,type);List<BluetoothGattCharacteristic> chars=new ArrayList<>();int size=1;
            for(int i=0;i<definitions.length();i++){
                JSONArray row=list(definitions.get(i),4);if(row.length()!=4)throw new VmHardware.Failure("invalid_argument","A characteristic definition is [uuid,properties,permissions,descriptors].");
                BluetoothGattCharacteristic item=new BluetoothGattCharacteristic(uuid(VmHardware.text(row,0,36)),VmHardware.integer(row,1,0,255),permissions(row,2));JSONArray descriptors=list(row.get(3),16);size++;
                for(int j=0;j<descriptors.length();j++){JSONArray d=list(descriptors.get(j),2);if(d.length()!=2)throw new VmHardware.Failure("invalid_argument","A descriptor definition is [uuid,permissions].");item.addDescriptor(new BluetoothGattDescriptor(uuid(VmHardware.text(d,0,36)),permissions(d,1)));size++;}
                service.addCharacteristic(item);chars.add(item);
            }
            if(nodes.size()+size>4096)throw new VmHardware.Failure("resource_limit","This GATT server would exceed 4096 local attributes.");
            Node root=add(service,"","service",uuid);for(BluetoothGattCharacteristic item:chars){Node parent=add(item,root.id,"characteristic",item.getUuid());for(BluetoothGattDescriptor d:item.getDescriptors())add(d,parent.id,"descriptor",d.getUuid());}
            adding=root.id;HardwareSensors.events().postDelayed(addDeadline,15000);
            try{if(!gatt.addService(service)){removeNodes(root.id);adding="";HardwareSensors.events().removeCallbacks(addDeadline);throw new VmHardware.Failure("platform_error","Android refused to register this GATT service.");}return root.id;}
            catch(VmHardware.Failure error){throw error;}catch(Exception error){fail("platform_error",MainActivity.safe(error));throw error;}
        }
        synchronized void added(int status,BluetoothGattService service){
            if(closed||!state.equals("open"))return;
            Node root=identities.get(service);if(root==null||!root.id.equals(adding)){fail("callback_mismatch","Android returned an unexpected GATT service registration.");return;}
            HardwareSensors.events().removeCallbacks(addDeadline);adding="";
            if(status==0){root.active=true;for(Node n:nodes.values())if(n.parent.equals(root.id)){n.active=true;for(Node d:nodes.values())if(d.parent.equals(n.id))d.active=true;}}else removeNodes(root.id);
            try{lastResult=VmHardware.object("event","service_added","service",root.id,"status",status);emit(lastResult);}catch(Exception error){fail("callback_failed",MainActivity.safe(error));}
        }
        synchronized int remove(String id)throws Exception{Node node=node(id);if(!(node.sdk instanceof BluetoothGattService))throw new VmHardware.Failure("wrong_attribute","Remove a service ID, not a characteristic or descriptor.");if(!adding.isEmpty()||!requests.isEmpty())throw new VmHardware.Failure("busy","Finish service registration and unanswered ATT requests before removing services.");for(Peer peer:peers.values())if(!peer.operation.isEmpty())throw new VmHardware.Failure("busy","Wait for outstanding peer operations before removing a service.");if(!gatt.removeService((BluetoothGattService)node.sdk))throw new VmHardware.Failure("platform_error","Android refused to remove the service.");removeNodes(id);HardwareBle.event(this,"service_removed","service",id);return 1;}
        synchronized Object items(String parent,int offset,int limit)throws Exception{open();if(!parent.isEmpty()){Node node=node(parent);if(node.kind.equals("descriptor"))throw new VmHardware.Failure("wrong_attribute","List services or the children of a service/characteristic.");}List<Node> rows=new ArrayList<>();for(Node node:nodes.values())if(node.parent.equals(parent))rows.add(node);JSONArray out=new JSONArray();for(int i=offset;i<Math.min(offset+limit,rows.size());i++)out.put(rows.get(i).info());return VmHardware.object("items",out,"total",rows.size(),"next",offset+out.length()<rows.size()?offset+out.length():-1);}
        synchronized void connection(BluetoothDevice device,int status,int next){
            if(closed||state.equals("error"))return;String address=device.getAddress();Peer peer=peers.get(address);
            if(status!=0||next==BluetoothProfile.STATE_DISCONNECTED){if(peer==null)return;if(!peer.operation.isEmpty()){fail("disconnected","A GATT peer disconnected during an outgoing operation; close the registration to discard ambiguous late callbacks.");return;}peers.remove(address);clearPeer(peer);List<String> remove=new ArrayList<>();for(Request request:requests.values())if(request.peer==peer){HardwareSensors.events().removeCallbacks(request.deadline);remove.add(request.token);}for(String token:remove)requests.remove(token);HardwareBle.event(this,"disconnected","peer",peer.id,"address",address,"status",status);return;}
            if(next==BluetoothProfile.STATE_CONNECTED){if(peer!=null)return;if(peers.size()>=32){if(gatt!=null)try{gatt.cancelConnection(device);}catch(RuntimeException error){fail("platform_error",MainActivity.safe(error));return;}HardwareBle.event(this,"error","code","resource_limit","message","The GATT server already has 32 peers.");return;}peer=new Peer(device);peers.put(address,peer);HardwareBle.event(this,"connected","peer",peer.id,"address",address);}
        }
        synchronized void mtu(BluetoothDevice device,int mtu){if(closed||!state.equals("open"))return;Peer peer=peers.get(device.getAddress());if(peer==null||peer.closing)return;if(mtu<23||mtu>517){fail("callback_failed","Android reported an invalid ATT MTU.");return;}peer.mtu=mtu;peer.mtuObserved=true;HardwareBle.event(this,"mtu","peer",peer.id,"mtu",mtu);}
        boolean reply(BluetoothDevice device,int id,int status,int offset,byte[] value){try{return gatt!=null&&gatt.sendResponse(device,id,status,offset,value);}catch(RuntimeException error){return false;}}
        synchronized void request(BluetoothDevice device,int id,Object sdk,String kind,int offset,boolean prepared,boolean response,boolean execute,byte[] value){
            if(closed||!state.equals("open"))return;
            Peer peer=peers.get(device.getAddress());Node node=sdk==null?null:identities.get(sdk);
            if(peer==null||peer.closing||sdk!=null&&(node==null||!node.active)){if(response&&!reply(device,id,6,0,new byte[0]))fail("platform_error","Android refused an unknown-attribute/peer error response.");return;}
            if(value!=null&&value.length>512||kind.equals("write")&&value==null){if(response&&!reply(device,id,13,0,new byte[0]))fail("platform_error","Android refused an invalid-length response.");HardwareBle.event(this,"request_rejected","peer",peer.id,"code","size_limit");return;}
            if(response&&requests.size()>=128){if(!reply(device,id,17,0,new byte[0]))fail("platform_error","Android refused a resource-limit response.");HardwareBle.event(this,"request_rejected","peer",peer.id,"code","resource_limit");return;}
            try{
                JSONObject event=VmHardware.object("event","request","kind",kind,"peer",peer.id,"attribute",node==null?JSONObject.NULL:node.id,"offset",offset,"prepared",prepared,"response_needed",response,"execute",execute,"value",value==null?JSONObject.NULL:VmHardware.bytes(Arrays.copyOf(value,value.length)));
                if(response){Request request=new Request(peer,id,offset,event);event.put("token",request.token);request.deadline=()->expire(request);requests.put(request.token,request);HardwareSensors.events().postDelayed(request.deadline,timeout);}else event.put("token",JSONObject.NULL);
                emit(event);
            }catch(Exception error){fail("callback_failed",MainActivity.safe(error));}
        }
        synchronized void expire(Request request){if(closed||requests.remove(request.token)!=request)return;expired++;boolean sent=reply(request.peer.sdk,request.sdkId,14,0,new byte[0]);HardwareBle.event(this,"request_expired","token",request.token,"peer",request.peer.id,"status",14,"response_accepted",sent);if(!sent)fail("platform_error","Android refused an ATT timeout response.");}
        synchronized int respond(String token,int status,int offset,byte[] value)throws Exception{open();if(value.length>512)throw new VmHardware.Failure("size_limit","An ATT response is at most 512 bytes.");Request request=requests.get(token);if(request==null)throw new VmHardware.Failure("stale_request","The ATT request expired, was answered, or belongs to another server.");if(request.peer.closing||peers.get(request.peer.sdk.getAddress())!=request.peer)throw new VmHardware.Failure("stale_peer","The ATT request's peer is no longer connected.");requests.remove(token);HardwareSensors.events().removeCallbacks(request.deadline);if(!reply(request.peer.sdk,request.sdkId,status,offset,Arrays.copyOf(value,value.length))){fail("platform_error","Android refused to send the ATT response.");throw new VmHardware.Failure("platform_error","Android refused to send the ATT response.");}return 1;}
        synchronized Object pending(int offset,int limit)throws Exception{open();List<Request> rows=new ArrayList<>(requests.values());JSONArray out=new JSONArray();for(int i=offset;i<Math.min(offset+limit,rows.size());i++)out.put(rows.get(i).event);return VmHardware.object("requests",out,"total",rows.size(),"next",offset+out.length()<rows.size()?offset+out.length():-1);}
        synchronized Object peerPage(int offset,int limit)throws Exception{open();List<Peer> rows=new ArrayList<>(peers.values());JSONArray out=new JSONArray();for(int i=offset;i<Math.min(offset+limit,rows.size());i++)out.put(rows.get(i).info());return VmHardware.object("peers",out,"total",rows.size(),"next",offset+out.length()<rows.size()?offset+out.length():-1);}
        void begin(Peer peer,String operation,String attribute,int id)throws Exception{if(!peer.operation.isEmpty())throw new VmHardware.Failure("busy","Wait for this peer's outstanding outgoing operation.");if(id<=peer.lastId)throw new VmHardware.Failure("invalid_argument","Outgoing GATT server request IDs must strictly increase per peer.");peer.lastId=id;peer.pendingId=id;peer.operation=operation;peer.attribute=attribute;peer.deadline=()->{synchronized(Server.this){if(peer.pendingId==id&&!peer.operation.isEmpty())fail("timeout","A GATT peer operation timed out; its server registration was closed to discard late callbacks.");}};HardwareSensors.events().postDelayed(peer.deadline,timeout);}
        synchronized int notify(String peerId,String attribute,byte[] value,boolean confirm,int id)throws Exception{
            Peer peer=peer(peerId);Node node=node(attribute);if(!node.active||!(node.sdk instanceof BluetoothGattCharacteristic))throw new VmHardware.Failure("wrong_attribute","Notify an active local characteristic.");int flag=confirm?BluetoothGattCharacteristic.PROPERTY_INDICATE:BluetoothGattCharacteristic.PROPERTY_NOTIFY;if((((BluetoothGattCharacteristic)node.sdk).getProperties()&flag)==0)throw new VmHardware.Failure("invalid_argument","This characteristic does not declare the selected notification/indication property.");if(value.length>512||value.length>peer.mtu-3)throw new VmHardware.Failure("size_limit","A notification/indication must fit the peer's observed MTU minus three (max512 bytes).");begin(peer,"notify",attribute,id);peer.confirm=confirm;
            try{boolean accepted;if(Build.VERSION.SDK_INT>=33)accepted=gatt.notifyCharacteristicChanged(peer.sdk,(BluetoothGattCharacteristic)node.sdk,confirm,Arrays.copyOf(value,value.length))==0;else{((BluetoothGattCharacteristic)node.sdk).setValue(Arrays.copyOf(value,value.length));accepted=gatt.notifyCharacteristicChanged(peer.sdk,(BluetoothGattCharacteristic)node.sdk,confirm);}if(!accepted){clearPeer(peer);throw new VmHardware.Failure("platform_error","Android refused the GATT update.");}return 1;}catch(VmHardware.Failure error){throw error;}catch(Exception error){fail("platform_error",MainActivity.safe(error));throw error;}
        }
        synchronized int phy(String id,String operation,int tx,int rx,int options,int request)throws Exception{Peer peer=peer(id);begin(peer,operation,"",request);try{if(operation.equals("phy_read"))gatt.readPhy(peer.sdk);else gatt.setPreferredPhy(peer.sdk,tx,rx,options);return 1;}catch(Exception error){fail("platform_error",MainActivity.safe(error));throw error;}}
        synchronized void completed(BluetoothDevice device,String operation,int status,Object... fields){if(closed||!state.equals("open"))return;Peer peer=peers.get(device.getAddress());if(peer==null||peer.closing)return;boolean match=peer.operation.equals(operation);if(!match&&operation.equals("notify")){fail("callback_mismatch","An outgoing GATT update completed without its owned request.");return;}try{JSONObject event=VmHardware.object("event",operation.equals("notify")?"notification_sent":operation,"peer",peer.id,"id",match?peer.pendingId:-1,"status",status);if(operation.equals("notify"))event.put("attribute",peer.attribute).put("confirm",peer.confirm);for(int i=0;i<fields.length;i+=2)event.put((String)fields[i],fields[i+1]);if(match){peer.lastResult=event;clearPeer(peer);}emit(event);}catch(Exception error){fail("callback_failed",MainActivity.safe(error));}}
        synchronized int disconnect(String id)throws Exception{Peer peer=peer(id);if(!peer.operation.isEmpty()){fail("cancelled","The peer closed during an outgoing operation; its registration was closed to discard late callbacks.");return 1;}peer.closing=true;try{gatt.cancelConnection(peer.sdk);return 1;}catch(RuntimeException error){fail("platform_error",MainActivity.safe(error));throw error;}}
        public synchronized void close()throws IOException{if(closed)return;super.close();release();lastResult=null;}
    }
    static Object call(VmHardware.Context c,String op,JSONArray a)throws Exception{
        if(op.equals("ble_server_open")){int timeout=VmHardware.integer(a,0,1000,25000);HardwareBle.adapter(c);HardwareBluetooth.connectPermission(c);HardwareBle.enabled(HardwareBle.adapter(c));HardwareBle.visible(c);Server server=new Server(c,timeout);VmHardware.blocking(server);try{server.start();return VmHardware.add(server);}catch(Exception error){server.close();throw error;}finally{VmHardware.unblocking();}}
        Server server=VmHardware.handle(c,VmHardware.text(a,0,128),Server.class);server.access(c);
        if(op.equals("ble_server_add"))return server.service(uuid(VmHardware.text(a,1,36)),VmHardware.integer(a,2,0,1),list(a.get(3),128));
        if(op.equals("ble_server_items"))return server.items(VmHardware.text(a,1,128),VmHardware.integer(a,2,0,4096),VmHardware.integer(a,3,1,16));
        if(op.equals("ble_server_remove"))return server.remove(VmHardware.text(a,1,128));
        if(op.equals("ble_server_peers"))return server.peerPage(VmHardware.integer(a,1,0,32),VmHardware.integer(a,2,1,16));
        if(op.equals("ble_server_requests"))return server.pending(VmHardware.integer(a,1,0,128),VmHardware.integer(a,2,1,16));
        if(op.equals("ble_server_respond"))return server.respond(VmHardware.text(a,1,128),VmHardware.integer(a,2,0,255),VmHardware.integer(a,3,0,512),VmHardware.data(a.get(4)));
        if(op.equals("ble_server_notify"))return server.notify(VmHardware.text(a,1,128),VmHardware.text(a,2,128),VmHardware.data(a.get(3)),VmHardware.integer(a,4,0,1)==1,VmHardware.integer(a,5,0,Integer.MAX_VALUE));
        if(op.equals("ble_server_disconnect"))return server.disconnect(VmHardware.text(a,1,128));
        if(op.equals("ble_server_phy_read"))return server.phy(VmHardware.text(a,1,128),"phy_read",0,0,0,VmHardware.integer(a,2,0,Integer.MAX_VALUE));
        if(op.equals("ble_server_phy"))return server.phy(VmHardware.text(a,1,128),"phy",VmHardware.integer(a,2,1,7),VmHardware.integer(a,3,1,7),VmHardware.integer(a,4,0,2),VmHardware.integer(a,5,0,Integer.MAX_VALUE));
        throw new VmHardware.Failure("unsupported_operation","Unknown BLE GATT server operation.");
    }
}
