package org.flexscript.collie;

import android.Manifest;
import android.bluetooth.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.os.Build;
import java.io.IOException;
import java.util.*;
import org.json.*;

/** Owned Android GATT connections; protocol decisions and CCCD values belong to Flexscript. */
final class HardwareGattClient {
    static boolean supports(String op){return op.equals("ble_connect")||op.startsWith("ble_gatt_");}
    static void capabilities(VmHardware.Context c,JSONArray out)throws Exception{
        BluetoothManager manager=c.host.getSystemService(BluetoothManager.class);BluetoothAdapter adapter=manager==null?null:manager.getAdapter();boolean supported=adapter!=null&&c.host.getPackageManager().hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE);
        boolean permission=Build.VERSION.SDK_INT<31||c.host.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT)==PackageManager.PERMISSION_GRANTED;
        out.put(VmHardware.object("id","bluetooth_le_gatt_client","implemented",true,"supported",supported,"available",supported&&permission&&adapter.isEnabled(),"permission","bluetooth","runtime_permission_required",supported&&!permission));
    }
    static byte[] snapshot(byte[] value){return value==null||value.length>512?value:Arrays.copyOf(value,value.length);}
    static final class Client extends VmHardware.Handle {
        final VmHardware.Context context;
        final Context app;
        final String address;
        final int operationTimeout;
        final BroadcastReceiver radio;
        final BluetoothGattCallback callback;
        BluetoothGatt gatt;
        boolean registered,discovered,mtuObserved;
        String state="pending",pending="",pendingAttribute="";
        int pendingId=-1,lastId=-1,mtu=23,revision;
        Runnable operationDeadline;
        JSONObject lastResult;
        final LinkedHashMap<String,Object> attributes=new LinkedHashMap<>();
        final IdentityHashMap<Object,String> ids=new IdentityHashMap<>();
        final Map<String,JSONObject> records=new HashMap<>();
        final Map<String,List<String>> children=new HashMap<>();
        final Runnable connectDeadline=()->fail("timeout",-1,"Android did not connect the BLE GATT client before its deadline.");

        Client(VmHardware.Context c,String address,int operationTimeout){
            super(c,"bluetooth","bluetooth_le_gatt_client");context=c;app=c.host.getApplicationContext();this.address=address;this.operationTimeout=operationTimeout;
            radio=new BroadcastReceiver(){public void onReceive(Context ignored,Intent intent){if(intent.getIntExtra(BluetoothAdapter.EXTRA_STATE,-1)!=BluetoothAdapter.STATE_ON)fail("bluetooth_disabled",-1,"Android Bluetooth was turned off.");}};
            callback=new BluetoothGattCallback(){
                public void onConnectionStateChange(BluetoothGatt source,int status,int next){connection(source,status,next);}
                public void onServicesDiscovered(BluetoothGatt source,int status){services(source,status);}
                public void onServiceChanged(BluetoothGatt source){changed(source);}
                public void onCharacteristicRead(BluetoothGatt source,BluetoothGattCharacteristic item,byte[] value,int status){read(source,item,snapshot(value),status);}
                public void onCharacteristicRead(BluetoothGatt source,BluetoothGattCharacteristic item,int status){if(Build.VERSION.SDK_INT<33)read(source,item,snapshot(item.getValue()),status);}
                public void onDescriptorRead(BluetoothGatt source,BluetoothGattDescriptor item,int status,byte[] value){read(source,item,snapshot(value),status);}
                public void onDescriptorRead(BluetoothGatt source,BluetoothGattDescriptor item,int status){if(Build.VERSION.SDK_INT<33)read(source,item,snapshot(item.getValue()),status);}
                public void onCharacteristicWrite(BluetoothGatt source,BluetoothGattCharacteristic item,int status){written(source,item,status);}
                public void onDescriptorWrite(BluetoothGatt source,BluetoothGattDescriptor item,int status){written(source,item,status);}
                public void onCharacteristicChanged(BluetoothGatt source,BluetoothGattCharacteristic item,byte[] value){notification(source,item,snapshot(value));}
                public void onCharacteristicChanged(BluetoothGatt source,BluetoothGattCharacteristic item){if(Build.VERSION.SDK_INT<33)notification(source,item,snapshot(item.getValue()));}
                public void onMtuChanged(BluetoothGatt source,int value,int status){diagnostic(source,"mtu",status,"mtu",value);}
                public void onReadRemoteRssi(BluetoothGatt source,int rssi,int status){diagnostic(source,"rssi",status,"rssi_dbm",rssi);}
                public void onPhyRead(BluetoothGatt source,int tx,int rx,int status){diagnostic(source,"phy_read",status,"tx_phy",tx,"rx_phy",rx);}
                public void onPhyUpdate(BluetoothGatt source,int tx,int rx,int status){diagnostic(source,"phy",status,"tx_phy",tx,"rx_phy",rx);}
            };
        }
        synchronized void start(BluetoothAdapter adapter,int timeout)throws Exception{
            IntentFilter filter=new IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED);
            if(Build.VERSION.SDK_INT>=33)app.registerReceiver(radio,filter,null,HardwareSensors.events(),Context.RECEIVER_EXPORTED);else app.registerReceiver(radio,filter,null,HardwareSensors.events());registered=true;
            gatt=adapter.getRemoteDevice(address).connectGatt(app,false,callback,BluetoothDevice.TRANSPORT_LE,BluetoothDevice.PHY_LE_1M_MASK,HardwareSensors.events());
            if(gatt==null)throw new VmHardware.Failure("unavailable","Android refused to allocate a BLE GATT client.");
            HardwareSensors.events().postDelayed(connectDeadline,timeout);
        }
        boolean current(BluetoothGatt source){return !closed&&source==gatt;}
        void connected()throws Exception{check();if(!state.equals("connected")||gatt==null)throw new VmHardware.Failure(state.equals("pending")?"not_ready":"disconnected","Wait for the GATT connected event, or open a new connection.");}
        void clearAttributes(){attributes.clear();ids.clear();records.clear();children.clear();children.put("",new ArrayList<>());discovered=false;revision++;}
        void clearPending(){if(operationDeadline!=null)HardwareSensors.events().removeCallbacks(operationDeadline);operationDeadline=null;pending="";pendingAttribute="";pendingId=-1;}
        void release(){
            HardwareSensors.events().removeCallbacks(connectDeadline);clearPending();clearAttributes();
            if(registered){registered=false;try{app.unregisterReceiver(radio);}catch(RuntimeException ignored){}}
            BluetoothGatt closing=gatt;gatt=null;if(closing!=null){try{closing.disconnect();}catch(RuntimeException ignored){}try{closing.close();}catch(RuntimeException ignored){}}
        }
        synchronized void fail(String code,int status,String message){
            if(closed||state.equals("error"))return;
            try{lastResult=VmHardware.object("event","error","code",code,"status",status,"message",message,"id",pendingId,"operation",pending);emit(lastResult);}catch(Exception ignored){}
            state="error";release();
        }
        synchronized void connection(BluetoothGatt source,int status,int next){
            if(!current(source))return;
            if(status!=BluetoothGatt.GATT_SUCCESS||next==BluetoothProfile.STATE_DISCONNECTED){fail("disconnected",status,"The BLE GATT connection ended.");return;}
            if(next==BluetoothProfile.STATE_CONNECTED&&state.equals("pending")){state="connected";HardwareSensors.events().removeCallbacks(connectDeadline);HardwareBle.event(this,"connected","address",address);}
        }
        void begin(String operation,String attribute,int id)throws Exception{
            connected();if(!pending.isEmpty())throw new VmHardware.Failure("busy","Wait for the outstanding GATT operation before starting another.");
            if(id<=lastId)throw new VmHardware.Failure("invalid_argument","GATT request IDs must strictly increase within a connection.");
            lastId=id;pendingId=id;pending=operation;pendingAttribute=attribute;
            operationDeadline=()->{synchronized(Client.this){if(pendingId==id&&!pending.isEmpty())fail("timeout",-1,"The GATT operation timed out; its connection was closed to discard late callbacks.");}};
            HardwareSensors.events().postDelayed(operationDeadline,operationTimeout);
        }
        void accepted(boolean value)throws Exception{if(!value){String operation=pending;clearPending();throw new VmHardware.Failure("platform_error","Android refused to start GATT "+operation+".");}}
        void accepted(int status)throws Exception{if(status!=0){String operation=pending;clearPending();throw new VmHardware.Failure("platform_error","Android refused to start GATT "+operation+" (status "+status+").");}}
        String attributeId(Object value)throws Exception{String id=ids.get(value);if(id==null)throw new VmHardware.Failure("stale_attribute","The GATT attribute is not in the current discovered database.");return id;}
        Object attribute(String id)throws Exception{connected();Object value=attributes.get(id);if(value==null)throw new VmHardware.Failure("stale_attribute","Rediscover services and use an attribute ID owned by this connection.");return value;}
        boolean response(BluetoothGatt source,String operation,Object value){
            if(!current(source))return false;
            if(!pending.equals(operation)||(value!=null&&!pendingAttribute.equals(ids.get(value)))){fail("callback_mismatch",-1,"A GATT callback did not match the outstanding owned request.");return false;}
            return true;
        }
        void complete(JSONObject result){lastResult=result;clearPending();emit(result);}
        String add(Object value,String parent,String kind,String uuid,Object... metadata)throws Exception{
            if(attributes.size()>=4096)throw new VmHardware.Failure("resource_limit","The discovered GATT database exceeds 4096 attributes.");
            String id="gatt-"+UUID.randomUUID();attributes.put(id,value);ids.put(value,id);children.computeIfAbsent(parent,key->new ArrayList<>()).add(id);children.put(id,new ArrayList<>());
            JSONObject row=VmHardware.object("id",id,"parent",parent,"kind",kind,"uuid",uuid,"revision",revision);for(int i=0;i<metadata.length;i+=2)row.put((String)metadata[i],metadata[i+1]);records.put(id,row);return id;
        }
        synchronized void services(BluetoothGatt source,int status){
            if(!response(source,"discover",null))return;
            try{
                if(status==BluetoothGatt.GATT_SUCCESS){
                    for(BluetoothGattService service:source.getServices()){
                        String parent=add(service,"","service",service.getUuid().toString(),"instance",service.getInstanceId(),"type",service.getType());
                        for(BluetoothGattCharacteristic item:service.getCharacteristics()){
                            String id=add(item,parent,"characteristic",item.getUuid().toString(),"instance",item.getInstanceId(),"properties",item.getProperties(),"permissions",item.getPermissions());
                            for(BluetoothGattDescriptor descriptor:item.getDescriptors())add(descriptor,id,"descriptor",descriptor.getUuid().toString(),"permissions",descriptor.getPermissions());
                        }
                    }
                    discovered=true;
                }
                complete(VmHardware.object("event","services","id",pendingId,"status",status,"revision",revision,"services",children.get("").size(),"attributes",attributes.size()));
            }catch(Exception error){fail(error instanceof VmHardware.Failure?((VmHardware.Failure)error).code:"callback_failed",-1,MainActivity.safe(error));}
        }
        synchronized void changed(BluetoothGatt source){if(!current(source))return;if(!pending.isEmpty()){fail("services_changed",-1,"The remote GATT database changed during a request; reconnect before using it.");return;}clearAttributes();HardwareBle.event(this,"services_changed","revision",revision);}
        synchronized void read(BluetoothGatt source,Object item,byte[] value,int status){
            if(!response(source,"read",item))return;
            try{if(value!=null&&value.length>512)throw new VmHardware.Failure("size_limit","The GATT value exceeds the 512-byte attribute limit.");complete(VmHardware.object("event","read","id",pendingId,"attribute",pendingAttribute,"status",status,"value",status==0&&value!=null?VmHardware.bytes(Arrays.copyOf(value,value.length)):JSONObject.NULL));}
            catch(Exception error){fail("callback_failed",-1,MainActivity.safe(error));}
        }
        synchronized void written(BluetoothGatt source,Object item,int status){if(!response(source,"write",item))return;try{complete(VmHardware.object("event","write","id",pendingId,"attribute",pendingAttribute,"status",status));}catch(Exception error){fail("callback_failed",-1,MainActivity.safe(error));}}
        synchronized void notification(BluetoothGatt source,BluetoothGattCharacteristic item,byte[] value){
            if(!current(source)||!state.equals("connected"))return;
            try{String id=ids.get(item);if(id==null)return;if(value==null||value.length>512)throw new VmHardware.Failure("size_limit","The GATT notification must contain an actual value of at most 512 bytes.");HardwareBle.event(this,"notification","attribute",id,"revision",revision,"value",VmHardware.bytes(value==null?new byte[0]:Arrays.copyOf(value,value.length)));}catch(Exception error){fail("callback_failed",-1,MainActivity.safe(error));}
        }
        synchronized void diagnostic(BluetoothGatt source,String kind,int status,Object... fields){
            if(!current(source))return;
            if(kind.equals("mtu")&&status==0){mtu=(Integer)fields[1];mtuObserved=true;}
            try{boolean match=pending.equals(kind);JSONObject event=VmHardware.object("event",kind,"id",match?pendingId:-1,"status",status);for(int i=0;i<fields.length;i+=2)event.put((String)fields[i],fields[i+1]);if(match)complete(event);else emit(event);}catch(Exception error){fail("callback_failed",-1,MainActivity.safe(error));}
        }
        public void access(VmHardware.Context c)throws Exception{check();HardwareBluetooth.connectPermission(c);}
        public synchronized Object info()throws Exception{check();return VmHardware.object("kind",kind,"state",state,"address",address,"mtu",mtu,"mtu_observed",mtuObserved,"last_request_id",lastId,"revision",revision,"discovered",discovered,"attributes",attributes.size(),"pending_id",pendingId,"pending_operation",pending,"last_result",lastResult==null?JSONObject.NULL:lastResult);}
        synchronized Object items(String parent,int offset,int limit)throws Exception{
            connected();if(!discovered)throw new VmHardware.Failure("not_ready","Wait for successful GATT service discovery before listing attributes.");
            if(!parent.isEmpty()&&!(attribute(parent) instanceof BluetoothGattService)&&!(attribute(parent) instanceof BluetoothGattCharacteristic))throw new VmHardware.Failure("wrong_attribute","List children of a service or characteristic, or use an empty parent for services.");
            List<String> rows=children.get(parent);JSONArray out=new JSONArray();for(int i=offset;i<Math.min(offset+limit,rows.size());i++)out.put(records.get(rows.get(i)));return VmHardware.object("items",out,"next",offset+out.length()<rows.size()?offset+out.length():-1,"total",rows.size(),"revision",revision);
        }
        synchronized int discover(int id)throws Exception{begin("discover","",id);clearAttributes();try{accepted(gatt.discoverServices());return 1;}catch(VmHardware.Failure error){throw error;}catch(Exception error){fail("platform_error",-1,MainActivity.safe(error));throw error;}}
        synchronized int read(String id,int request)throws Exception{
            Object item=attribute(id);if(!(item instanceof BluetoothGattCharacteristic)&&!(item instanceof BluetoothGattDescriptor))throw new VmHardware.Failure("wrong_attribute","Read a GATT characteristic or descriptor.");
            begin("read",id,request);try{accepted(item instanceof BluetoothGattCharacteristic?gatt.readCharacteristic((BluetoothGattCharacteristic)item):gatt.readDescriptor((BluetoothGattDescriptor)item));return 1;}catch(VmHardware.Failure error){throw error;}catch(Exception error){fail("platform_error",-1,MainActivity.safe(error));throw error;}
        }
        synchronized int write(String id,byte[] bytes,int type,int request)throws Exception{
            Object item=attribute(id);if(bytes.length>512)throw new VmHardware.Failure("size_limit","A GATT attribute value is at most 512 bytes.");
            if(!(item instanceof BluetoothGattCharacteristic)&&!(item instanceof BluetoothGattDescriptor))throw new VmHardware.Failure("wrong_attribute","Write a GATT characteristic or descriptor.");
            if(type!=1&&type!=2&&type!=4||item instanceof BluetoothGattDescriptor&&type!=2)throw new VmHardware.Failure("invalid_argument","Use write type1 no-response,2 acknowledged,4 signed; descriptors require2.");
            if(type==1&&bytes.length>mtu-3||type==4&&bytes.length>mtu-15)throw new VmHardware.Failure("size_limit","This no-response/signed write exceeds the negotiated ATT MTU payload.");
            begin("write",id,request);
            try{
                if(item instanceof BluetoothGattCharacteristic){BluetoothGattCharacteristic c=(BluetoothGattCharacteristic)item;if(Build.VERSION.SDK_INT>=33)accepted(gatt.writeCharacteristic(c,Arrays.copyOf(bytes,bytes.length),type));else{c.setWriteType(type);c.setValue(Arrays.copyOf(bytes,bytes.length));accepted(gatt.writeCharacteristic(c));}}
                else{BluetoothGattDescriptor d=(BluetoothGattDescriptor)item;if(Build.VERSION.SDK_INT>=33)accepted(gatt.writeDescriptor(d,Arrays.copyOf(bytes,bytes.length)));else{d.setValue(Arrays.copyOf(bytes,bytes.length));accepted(gatt.writeDescriptor(d));}}
                return 1;
            }catch(VmHardware.Failure error){throw error;}catch(Exception error){fail("platform_error",-1,MainActivity.safe(error));throw error;}
        }
        synchronized int localNotify(String id,boolean enabled)throws Exception{Object item=attribute(id);if(!(item instanceof BluetoothGattCharacteristic))throw new VmHardware.Failure("wrong_attribute","Local notification routing requires a characteristic.");if(!pending.isEmpty())throw new VmHardware.Failure("busy","Wait for the outstanding GATT operation before changing notification routing.");if(!gatt.setCharacteristicNotification((BluetoothGattCharacteristic)item,enabled))throw new VmHardware.Failure("platform_error","Android refused local GATT notification routing.");return 1;}
        synchronized int request(String operation,int value,int tx,int rx,int options,int id)throws Exception{
            begin(operation,"",id);
            try{if(operation.equals("mtu"))accepted(gatt.requestMtu(value));else if(operation.equals("rssi"))accepted(gatt.readRemoteRssi());else if(operation.equals("phy_read"))gatt.readPhy();else gatt.setPreferredPhy(tx,rx,options);return 1;}
            catch(VmHardware.Failure error){throw error;}catch(Exception error){fail("platform_error",-1,MainActivity.safe(error));throw error;}
        }
        synchronized int priority(int priority)throws Exception{connected();if(!pending.isEmpty())throw new VmHardware.Failure("busy","Wait for the outstanding GATT operation before changing connection priority.");if(!gatt.requestConnectionPriority(priority))throw new VmHardware.Failure("platform_error","Android refused the connection priority request.");return 1;}
        public synchronized void close()throws IOException{if(closed)return;super.close();release();lastResult=null;}
    }
    static Object call(VmHardware.Context c,String op,JSONArray a)throws Exception{
        if(op.equals("ble_connect")){
            String address=HardwareBluetooth.address(VmHardware.text(a,0,17));int timeout=VmHardware.integer(a,1,1000,120000),operations=VmHardware.integer(a,2,1000,120000);
            BluetoothAdapter adapter=HardwareBle.adapter(c);HardwareBluetooth.connectPermission(c);HardwareBle.enabled(adapter);HardwareBle.visible(c);
            Client client=new Client(c,address,operations);try{client.start(adapter,timeout);return VmHardware.add(client);}catch(Exception error){client.close();throw error;}
        }
        Client client=VmHardware.handle(c,VmHardware.text(a,0,128),Client.class);client.access(c);
        if(op.equals("ble_gatt_items"))return client.items(VmHardware.text(a,1,128),VmHardware.integer(a,2,0,4096),VmHardware.integer(a,3,1,16));
        if(op.equals("ble_gatt_discover"))return client.discover(VmHardware.integer(a,1,0,Integer.MAX_VALUE));
        if(op.equals("ble_gatt_read"))return client.read(VmHardware.text(a,1,128),VmHardware.integer(a,2,0,Integer.MAX_VALUE));
        if(op.equals("ble_gatt_write"))return client.write(VmHardware.text(a,1,128),VmHardware.data(a.get(2)),VmHardware.integer(a,3,1,4),VmHardware.integer(a,4,0,Integer.MAX_VALUE));
        if(op.equals("ble_gatt_local_notify"))return client.localNotify(VmHardware.text(a,1,128),VmHardware.integer(a,2,0,1)==1);
        if(op.equals("ble_gatt_mtu"))return client.request("mtu",VmHardware.integer(a,1,23,517),0,0,0,VmHardware.integer(a,2,0,Integer.MAX_VALUE));
        if(op.equals("ble_gatt_rssi"))return client.request("rssi",0,0,0,0,VmHardware.integer(a,1,0,Integer.MAX_VALUE));
        if(op.equals("ble_gatt_phy_read"))return client.request("phy_read",0,0,0,0,VmHardware.integer(a,1,0,Integer.MAX_VALUE));
        if(op.equals("ble_gatt_phy"))return client.request("phy",0,VmHardware.integer(a,1,1,7),VmHardware.integer(a,2,1,7),VmHardware.integer(a,3,0,2),VmHardware.integer(a,4,0,Integer.MAX_VALUE));
        if(op.equals("ble_gatt_priority"))return client.priority(VmHardware.integer(a,1,0,2));
        throw new VmHardware.Failure("unsupported_operation","Unknown BLE GATT client operation.");
    }
}
