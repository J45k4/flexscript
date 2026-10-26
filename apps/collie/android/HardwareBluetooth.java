package org.flexscript.collie;

import android.Manifest;
import android.bluetooth.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.location.LocationManager;
import android.os.Build;
import android.os.ParcelUuid;
import android.os.SystemClock;
import java.io.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;
import org.json.*;

/** Android Classic Bluetooth objects and bounded I/O; guest protocols remain Flexscript. */
final class HardwareBluetooth {
    static boolean supports(String op){return op.startsWith("bt_");}
    private static final Object DISCOVERY=new Object(),LISTENERS=new Object();
    private static Scan discovery;private static final Map<UUID,Listener> listeners=new HashMap<>();
    private static final ExecutorService CONNECT=new ThreadPoolExecutor(0,2,30,TimeUnit.SECONDS,new SynchronousQueue<Runnable>(),task->{Thread thread=new Thread(task,"collie-bluetooth-connect");thread.setDaemon(true);return thread;});
    private static Context app(VmHardware.Context c){return c.host.getApplicationContext();}
    static BluetoothAdapter adapter(VmHardware.Context c)throws Exception{BluetoothManager manager=app(c).getSystemService(BluetoothManager.class);BluetoothAdapter value=manager==null?null:manager.getAdapter();if(value==null||!app(c).getPackageManager().hasSystemFeature(PackageManager.FEATURE_BLUETOOTH))throw new VmHardware.Failure("unsupported","This Android device has no Classic Bluetooth adapter.");return value;}
    static void connectPermission(VmHardware.Context c)throws Exception{if(Build.VERSION.SDK_INT>=31)VmHardware.require(c,Manifest.permission.BLUETOOTH_CONNECT);}
    private static void scanPermission(VmHardware.Context c)throws Exception{
        connectPermission(c);if(Build.VERSION.SDK_INT>=31)VmHardware.require(c,Manifest.permission.BLUETOOTH_SCAN);
        try{VmHardware.require(c,Manifest.permission.ACCESS_COARSE_LOCATION,Manifest.permission.ACCESS_FINE_LOCATION);}catch(VmHardware.Consent consent){consent.request.put("key","location");throw consent;}
        LocationManager manager=app(c).getSystemService(LocationManager.class);if(manager==null||!(Build.VERSION.SDK_INT>=28?manager.isLocationEnabled():manager.isProviderEnabled(LocationManager.GPS_PROVIDER)||manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)))throw new VmHardware.Failure("location_disabled","Turn on Android Location before Bluetooth discovery.");
    }
    private static void visible(VmHardware.Context c)throws Exception{if(!c.host.hardwareVisible)throw new VmHardware.Failure("foreground_required","Start this Bluetooth operation while Collie is visible.");}
    private static void enabled(BluetoothAdapter adapter)throws Exception{if(!adapter.isEnabled())throw new VmHardware.Failure("bluetooth_disabled","Turn on Bluetooth in Android settings, or call bt_request_enable().");}
    private static String text(String value,int limit){return value==null?"":value.substring(0,Math.min(limit,value.length()));}
    static String address(String value)throws Exception{value=value.toUpperCase(Locale.ROOT);if(!BluetoothAdapter.checkBluetoothAddress(value))throw new VmHardware.Failure("invalid_argument","Use a Bluetooth address containing six colon-separated hexadecimal bytes.");return value;}
    private static UUID uuid(String value)throws Exception{try{UUID id=UUID.fromString(value);if(!id.toString().equalsIgnoreCase(value))throw new IllegalArgumentException();return id;}catch(IllegalArgumentException error){throw new VmHardware.Failure("invalid_argument","Use a canonical128-bit Bluetooth service UUID.");}}
    private static void register(Context app,BroadcastReceiver receiver,String... actions){IntentFilter filter=new IntentFilter();for(String action:actions)filter.addAction(action);if(Build.VERSION.SDK_INT>=33)app.registerReceiver(receiver,filter,null,HardwareSensors.events(),Context.RECEIVER_EXPORTED);else app.registerReceiver(receiver,filter,null,HardwareSensors.events());}
    private static void event(VmHardware.Handle handle,String type,Object... fields){try{Object[] row=new Object[fields.length+2];row[0]="event";row[1]=type;System.arraycopy(fields,0,row,2,fields.length);handle.emit(VmHardware.object(row));}catch(Exception ignored){}}
    static void capabilities(VmHardware.Context c,JSONArray out)throws Exception{
        BluetoothManager manager=app(c).getSystemService(BluetoothManager.class);BluetoothAdapter adapter=manager==null?null:manager.getAdapter();boolean supported=adapter!=null&&app(c).getPackageManager().hasSystemFeature(PackageManager.FEATURE_BLUETOOTH);boolean permitted=Build.VERSION.SDK_INT<31||c.host.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT)==PackageManager.PERMISSION_GRANTED;
        out.put(VmHardware.object("id","bluetooth_classic","implemented",true,"supported",supported,"available",supported&&permitted&&adapter.isEnabled(),"permission","bluetooth","runtime_permission_required",supported&&!permitted));
    }
    private static boolean scanGranted(VmHardware.Context c){return Build.VERSION.SDK_INT<31||c.host.checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN)==PackageManager.PERMISSION_GRANTED;}
    static JSONObject info(VmHardware.Context c,BluetoothAdapter adapter)throws Exception{boolean scan=scanGranted(c);return VmHardware.object("state",adapter.getState(),"enabled",adapter.isEnabled(),"name",text(adapter.getName(),256),"scan_mode",scan?adapter.getScanMode():JSONObject.NULL,"discovering",scan?adapter.isDiscovering():JSONObject.NULL,"scan_permission_granted",scan,"multiple_advertisement",adapter.isMultipleAdvertisementSupported(),"le_extended_advertisement",adapter.isLeExtendedAdvertisingSupported());}
    private static JSONObject device(BluetoothDevice device)throws Exception{
        BluetoothClass type=device.getBluetoothClass();return VmHardware.object("address",device.getAddress(),"name",text(device.getName(),256),"type",device.getType(),"bond_state",device.getBondState(),"class",type==null?JSONObject.NULL:type.getDeviceClass(),"major_class",type==null?JSONObject.NULL:type.getMajorDeviceClass());
    }
    static final class Watch extends VmHardware.Handle {
        final VmHardware.Context context;final BroadcastReceiver receiver;boolean registered;
        Watch(VmHardware.Context c){super(c,"bluetooth","bluetooth_state");context=c;receiver=new BroadcastReceiver(){public void onReceive(Context ignored,Intent intent){if(closed)return;try{event(Watch.this,"adapter","value",HardwareBluetooth.info(c,adapter(c)));}catch(Exception error){event(Watch.this,"error","code","platform_error","message",MainActivity.safe(error));}}};}
        void start()throws Exception{register(app(context),receiver,BluetoothAdapter.ACTION_STATE_CHANGED,BluetoothAdapter.ACTION_SCAN_MODE_CHANGED,BluetoothAdapter.ACTION_LOCAL_NAME_CHANGED);registered=true;event(this,"adapter","value",HardwareBluetooth.info(context,adapter(context)));}
        public void access(VmHardware.Context c)throws Exception{check();connectPermission(c);}
        public Object info()throws Exception{check();return HardwareBluetooth.info(context,adapter(context));}
        public synchronized void close()throws IOException{if(closed)return;super.close();if(registered){registered=false;app(context).unregisterReceiver(receiver);}}
    }
    static final class Device extends VmHardware.Handle {
        final VmHardware.Context context;final BluetoothDevice device;final BroadcastReceiver receiver;boolean registered;
        Device(VmHardware.Context c,BluetoothDevice device){super(c,"bluetooth","bluetooth_device");context=c;this.device=device;receiver=new BroadcastReceiver(){public void onReceive(Context ignored,Intent intent){if(closed)return;BluetoothDevice value=intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE);if(value==null||!value.getAddress().equals(device.getAddress()))return;try{String action=intent.getAction();if(BluetoothDevice.ACTION_UUID.equals(action))event(Device.this,"uuids","value",uuids(false));else event(Device.this,BluetoothDevice.ACTION_BOND_STATE_CHANGED.equals(action)?"bond":"device","value",HardwareBluetooth.device(value));}catch(Exception error){event(Device.this,"error","code","platform_error","message",MainActivity.safe(error));}}};}
        void start(){register(app(context),receiver,BluetoothDevice.ACTION_BOND_STATE_CHANGED,BluetoothDevice.ACTION_UUID,BluetoothDevice.ACTION_NAME_CHANGED,BluetoothDevice.ACTION_CLASS_CHANGED);registered=true;}
        Object uuids(boolean requested)throws Exception{ParcelUuid[] values=device.getUuids();JSONArray rows=new JSONArray();if(values!=null)for(int i=0;i<Math.min(values.length,64);i++)rows.put(values[i].getUuid().toString());return VmHardware.object("uuids",rows,"requested",requested,"truncated",values!=null&&values.length>rows.length());}
        public void access(VmHardware.Context c)throws Exception{check();connectPermission(c);}
        public Object info()throws Exception{check();return HardwareBluetooth.device(device);}
        public synchronized void close()throws IOException{if(closed)return;super.close();if(registered){registered=false;app(context).unregisterReceiver(receiver);}}
    }
    static final class Scan extends VmHardware.Handle {
        final VmHardware.Context context;final BluetoothAdapter adapter;final BroadcastReceiver receiver;final LinkedHashMap<String,JSONObject> peers=new LinkedHashMap<>();
        boolean registered,started;String state="pending";int omitted;
        final Runnable deadline=()->finish("deadline");
        Scan(VmHardware.Context c,BluetoothAdapter adapter){super(c,"bluetooth","bluetooth_scan","location");context=c;this.adapter=adapter;receiver=new BroadcastReceiver(){public void onReceive(Context ignored,Intent intent){if(closed)return;String action=intent.getAction();try{if(BluetoothAdapter.ACTION_DISCOVERY_FINISHED.equals(action)){finish("complete");return;}if(BluetoothAdapter.ACTION_STATE_CHANGED.equals(action)&&intent.getIntExtra(BluetoothAdapter.EXTRA_STATE,-1)!=BluetoothAdapter.STATE_ON){finish("bluetooth_disabled");return;}if(!BluetoothDevice.ACTION_FOUND.equals(action))return;BluetoothDevice device=intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE);if(device==null)return;JSONObject value=HardwareBluetooth.device(device);value.put("rssi_dbm",(int)intent.getShortExtra(BluetoothDevice.EXTRA_RSSI,Short.MIN_VALUE));synchronized(Scan.this){if(closed||!state.equals("discovering"))return;if(!peers.containsKey(device.getAddress())&&peers.size()>=128){omitted++;return;}peers.put(device.getAddress(),value);}event(Scan.this,"found","device",value);}catch(Exception error){event(Scan.this,"error","code","callback_failed","message",MainActivity.safe(error));}}};}
        synchronized void start(int duration)throws Exception{synchronized(DISCOVERY){if(discovery!=null||adapter.isDiscovering())throw new VmHardware.Failure("busy","Bluetooth discovery is already active; wait or close the Collie scan that owns it.");discovery=this;}register(app(context),receiver,BluetoothDevice.ACTION_FOUND,BluetoothAdapter.ACTION_DISCOVERY_FINISHED,BluetoothAdapter.ACTION_STATE_CHANGED);registered=true;synchronized(this){if(!adapter.startDiscovery())throw new VmHardware.Failure("unavailable","Android refused to start Bluetooth discovery.");started=true;state="discovering";HardwareSensors.events().postDelayed(deadline,duration);}event(this,"started");}
        void finish(String reason){boolean stop;synchronized(this){if(closed||state.equals("complete"))return;state="complete";stop=started&&!reason.equals("complete");started=false;HardwareSensors.events().removeCallbacks(deadline);if(registered){registered=false;app(context).unregisterReceiver(receiver);}event(this,"finished","reason",reason,"total",peers.size(),"omitted",omitted);}synchronized(DISCOVERY){if(discovery==this){if(stop)try{adapter.cancelDiscovery();}catch(Exception ignored){}discovery=null;}}}
        public void access(VmHardware.Context c)throws Exception{check();scanPermission(c);}
        public synchronized Object info()throws Exception{check();return VmHardware.object("kind",kind,"state",state,"total",peers.size(),"omitted",omitted);}
        synchronized Object page(int offset,int limit)throws Exception{check();JSONArray rows=new JSONArray();List<JSONObject> values=new ArrayList<>(peers.values());for(int i=offset;i<Math.min(values.size(),offset+limit);i++)rows.put(values.get(i));return VmHardware.object("devices",rows,"total",peers.size(),"omitted",omitted,"next",offset+rows.length()<peers.size()?offset+rows.length():-1);}
        public void close()throws IOException{finish("closed");synchronized(this){if(closed)return;super.close();peers.clear();}}
    }
    // A sensor/SDK callback may occupy the shared Handler. Byte-I/O deadlines
    // must still close sockets, including when both bounded VM I/O jobs block.
    private static final ScheduledThreadPoolExecutor BYTE_TIMERS=byteTimers();
    private static ScheduledThreadPoolExecutor byteTimers(){
        ScheduledThreadPoolExecutor pool=new ScheduledThreadPoolExecutor(2,task->{Thread thread=new Thread(task,"collie-bluetooth-byte-deadline");thread.setDaemon(true);return thread;});
        pool.setRemoveOnCancelPolicy(true);pool.setKeepAliveTime(30,TimeUnit.SECONDS);pool.allowCoreThreadTimeOut(true);return pool;
    }
    /** Only an actual blocking operation is cancelled; timeouts close byte streams. */
    private static final class Deadline implements AutoCloseable {
        final AtomicInteger state=new AtomicInteger();final Runnable stop;final long until;final ScheduledFuture<?> timer;
        Deadline(VmHardware.Handle handle,int timeout){until=SystemClock.elapsedRealtime()+timeout;stop=()->{if(state.compareAndSet(0,1))try{handle.close();}catch(Exception ignored){}};timer=BYTE_TIMERS.schedule(stop,timeout,TimeUnit.MILLISECONDS);}
        void completed()throws Exception{
            // Reject late data even if the deadline executor itself was delayed.
            if(SystemClock.elapsedRealtime()>=until)stop.run();
            if(!state.compareAndSet(0,2)&&state.get()==1)throw new VmHardware.Failure("timeout","Bluetooth byte I/O timed out; the socket was closed to prevent late consumption.");
        }
        boolean expired(){return state.get()==1;}
        public void close(){state.compareAndSet(0,2);timer.cancel(false);}
    }
    static final class Stream extends VmHardware.Handle {
        final VmHardware.Context context;final BluetoothSocket socket;final BroadcastReceiver receiver;boolean registered;volatile String state;volatile Future<?> connecting;
        final Runnable deadline=()->{synchronized(Stream.this){if(state.equals("pending"))fail("timeout","Android did not connect the RFCOMM socket within the requested deadline.");}};
        Stream(VmHardware.Context c,BluetoothSocket socket,boolean connected){super(c,"bluetooth","bluetooth_rfcomm");context=c;this.socket=socket;state=connected?"connected":"pending";receiver=new BroadcastReceiver(){public void onReceive(Context ignored,Intent intent){if(closed)return;if(BluetoothAdapter.ACTION_STATE_CHANGED.equals(intent.getAction())){if(intent.getIntExtra(BluetoothAdapter.EXTRA_STATE,-1)!=BluetoothAdapter.STATE_ON)fail("bluetooth_disabled","Android Bluetooth was turned off.");return;}BluetoothDevice device=intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE);if(device!=null&&device.getAddress().equals(socket.getRemoteDevice().getAddress())&&intent.getIntExtra(BluetoothDevice.EXTRA_TRANSPORT,BluetoothDevice.TRANSPORT_AUTO)!=BluetoothDevice.TRANSPORT_LE)fail("disconnected","The Classic Bluetooth peer disconnected.");}};}
        synchronized void watch(){register(app(context),receiver,BluetoothDevice.ACTION_ACL_DISCONNECTED,BluetoothAdapter.ACTION_STATE_CHANGED);registered=true;}
        void connect(int timeout)throws Exception{watch();HardwareSensors.events().postDelayed(deadline,timeout);try{connecting=CONNECT.submit(()->{try{socket.connect();synchronized(Stream.this){if(closed||!state.equals("pending")){try{socket.close();}catch(Exception ignored){}return;}state="connected";HardwareSensors.events().removeCallbacks(deadline);event(Stream.this,"connected","address",socket.getRemoteDevice().getAddress());}}catch(Exception error){fail("connect_failed",MainActivity.safe(error));}});}catch(RejectedExecutionException error){throw new VmHardware.Failure("busy","At most two RFCOMM connections may be pending in Collie.");}}
        void fail(String code,String message){synchronized(this){if(closed||state.equals("error"))return;state="error";HardwareSensors.events().removeCallbacks(deadline);if(registered){registered=false;app(context).unregisterReceiver(receiver);}event(this,"error","code",code,"message",message);}try{socket.close();}catch(Exception ignored){}}
        void connected()throws Exception{check();if(!state.equals("connected"))throw new VmHardware.Failure(state.equals("pending")?"not_ready":"disconnected","Wait for connected, or reopen the failed RFCOMM socket.");}
        public void access(VmHardware.Context c)throws Exception{check();connectPermission(c);}
        public Object read(int limit,int timeout)throws Exception{connected();try(Deadline deadline=new Deadline(this,timeout)){try{byte[] bytes=new byte[limit];int n=socket.getInputStream().read(bytes);deadline.completed();if(n<0){fail("disconnected","The RFCOMM input reached EOF.");return JSONObject.NULL;}return VmHardware.bytes(Arrays.copyOf(bytes,n));}catch(IOException error){if(deadline.expired())throw new VmHardware.Failure("timeout","Bluetooth read timed out and closed its socket.");VmHardware.check();fail("disconnected",MainActivity.safe(error));throw new VmHardware.Failure("disconnected",MainActivity.safe(error));}}}
        public Object write(byte[] bytes)throws Exception{connected();try(Deadline deadline=new Deadline(this,8000)){try{socket.getOutputStream().write(bytes);deadline.completed();return bytes.length;}catch(IOException error){if(deadline.expired())throw new VmHardware.Failure("timeout","Bluetooth write timed out and closed its socket; completion may be uncertain.");VmHardware.check();fail("disconnected",MainActivity.safe(error));throw new VmHardware.Failure("disconnected",MainActivity.safe(error));}}}
        public synchronized Object info()throws Exception{check();return VmHardware.object("kind",kind,"state",state,"address",socket.getRemoteDevice().getAddress(),"connected",state.equals("connected")&&socket.isConnected(),"connection_type",socket.getConnectionType(),"receive_packet_size",socket.getMaxReceivePacketSize(),"transmit_packet_size",socket.getMaxTransmitPacketSize());}
        public void close()throws IOException{synchronized(this){if(closed)return;super.close();HardwareSensors.events().removeCallbacks(deadline);if(registered){registered=false;app(context).unregisterReceiver(receiver);}}try{socket.close();}finally{Future<?> pending=connecting;if(pending!=null)pending.cancel(true);}}
    }
    static final class Listener extends VmHardware.Handle {
        final VmHardware.Context context;final UUID uuid;final boolean secure;final BroadcastReceiver receiver;BluetoothServerSocket socket;boolean registered;
        Listener(VmHardware.Context c,UUID uuid,boolean secure){super(c,"bluetooth","bluetooth_rfcomm_listener");context=c;this.uuid=uuid;this.secure=secure;receiver=new BroadcastReceiver(){public void onReceive(Context ignored,Intent intent){if(closed)return;if(intent.getIntExtra(BluetoothAdapter.EXTRA_STATE,-1)!=BluetoothAdapter.STATE_ON)try{close();}catch(Exception ignoredError){}}};}
        synchronized void start(String name)throws Exception{synchronized(LISTENERS){if(listeners.containsKey(uuid))throw new VmHardware.Failure("busy","This RFCOMM service UUID already has a Collie listener.");listeners.put(uuid,this);}BluetoothAdapter adapter=adapter(context);socket=secure?adapter.listenUsingRfcommWithServiceRecord(name,uuid):adapter.listenUsingInsecureRfcommWithServiceRecord(name,uuid);register(app(context),receiver,BluetoothAdapter.ACTION_STATE_CHANGED);registered=true;}
        public void access(VmHardware.Context c)throws Exception{check();connectPermission(c);}
        synchronized BluetoothServerSocket active()throws Exception{check();if(socket==null)throw new VmHardware.Failure("disconnected","The RFCOMM listener is closed.");return socket;}
        public Object info()throws Exception{check();return VmHardware.object("kind",kind,"uuid",uuid.toString(),"secure",secure);}
        public void close()throws IOException{BluetoothServerSocket closing;synchronized(this){if(closed)return;super.close();closing=socket;socket=null;if(registered){registered=false;app(context).unregisterReceiver(receiver);}}synchronized(LISTENERS){if(listeners.get(uuid)==this)listeners.remove(uuid);}if(closing!=null)closing.close();}
    }
    static Object call(VmHardware.Context c,String op,JSONArray a)throws Exception{
        if(op.equals("bt_info")||op.equals("bt_watch")||op.equals("bt_bonded")||op.equals("bt_device")||op.equals("bt_request_enable")||op.equals("bt_request_discoverable")||op.equals("bt_scan")||op.equals("bt_rfcomm_listen")){
            // Validate caller data before asking Android for Nearby access.
            String address=op.equals("bt_device")?address(VmHardware.text(a,0,17)):null;
            UUID service=op.equals("bt_rfcomm_listen")?uuid(VmHardware.text(a,1,36)):null;
            if(op.equals("bt_request_discoverable"))VmHardware.integer(a,0,1,300);
            int duration=op.equals("bt_scan")?VmHardware.integer(a,0,1000,30000):0;
            int offset=op.equals("bt_bonded")?VmHardware.integer(a,0,0,65535):0,limit=op.equals("bt_bonded")?VmHardware.integer(a,1,1,16):0;
            String name=op.equals("bt_rfcomm_listen")?VmHardware.text(a,0,128):"";if(op.equals("bt_rfcomm_listen")&&name.isEmpty())throw new VmHardware.Failure("invalid_argument","RFCOMM service name cannot be empty.");
            int secure=op.equals("bt_rfcomm_listen")?VmHardware.integer(a,2,0,1):1;
            BluetoothAdapter adapter=adapter(c);connectPermission(c);
            if(op.equals("bt_info"))return info(c,adapter);
            if(op.equals("bt_watch")){Watch watch=new Watch(c);try{watch.start();return VmHardware.add(watch);}catch(Exception error){watch.close();throw error;}}
            if(op.equals("bt_request_enable")){visible(c);if(!adapter.isEnabled())throw new VmHardware.Consent(VmHardware.object("type","bluetooth_enable"));return info(c,adapter);}
            if(op.equals("bt_request_discoverable")){visible(c);enabled(adapter);if(Build.VERSION.SDK_INT>=31)VmHardware.require(c,Manifest.permission.BLUETOOTH_ADVERTISE,Manifest.permission.BLUETOOTH_SCAN);if(adapter.getScanMode()!=BluetoothAdapter.SCAN_MODE_CONNECTABLE_DISCOVERABLE)throw new VmHardware.Consent(VmHardware.object("type","bluetooth_discoverable","seconds",VmHardware.integer(a,0,1,300)));return info(c,adapter);}
            if(op.equals("bt_bonded")){List<BluetoothDevice> devices=new ArrayList<>(adapter.getBondedDevices());devices.sort(Comparator.comparing(BluetoothDevice::getAddress));JSONArray rows=new JSONArray();for(int i=offset;i<Math.min(devices.size(),offset+limit);i++)rows.put(device(devices.get(i)));return VmHardware.object("devices",rows,"total",devices.size(),"next",offset+rows.length()<devices.size()?offset+rows.length():-1);}
            if(op.equals("bt_device")){Device device=new Device(c,adapter.getRemoteDevice(address));try{device.start();return VmHardware.add(device);}catch(Exception error){device.close();throw error;}}
            enabled(adapter);visible(c);
            if(op.equals("bt_scan")){scanPermission(c);Scan scan=new Scan(c,adapter);try{scan.start(duration);return VmHardware.add(scan);}catch(Exception error){scan.close();throw error;}}
            Listener listener=new Listener(c,service,secure==1);try{listener.start(name);return VmHardware.add(listener);}catch(Exception error){listener.close();throw error;}
        }
        if(op.equals("bt_scan_page")){Scan scan=VmHardware.handle(c,VmHardware.text(a,0,128),Scan.class);scan.access(c);return scan.page(VmHardware.integer(a,1,0,128),VmHardware.integer(a,2,1,16));}
        if(op.equals("bt_rfcomm_accept")){Listener listener=VmHardware.handle(c,VmHardware.text(a,0,128),Listener.class);listener.access(c);int timeout=VmHardware.integer(a,1,1,8000);long started=SystemClock.elapsedRealtime();VmHardware.blocking(listener);BluetoothSocket socket=null;try{try{socket=listener.active().accept(timeout);}catch(IOException error){VmHardware.check();listener.check();if(SystemClock.elapsedRealtime()-started>=timeout)throw new VmHardware.Failure("timeout","No RFCOMM peer connected before the accept deadline.");throw error;}Stream child=new Stream(c,socket,true);try{child.watch();return VmHardware.add(child);}catch(Exception error){child.close();throw error;}}finally{VmHardware.unblocking();}}
        Device device=VmHardware.handle(c,VmHardware.text(a,0,128),Device.class);device.access(c);
        if(op.equals("bt_bond")){visible(c);enabled(adapter(c));if(device.device.getBondState()!=BluetoothDevice.BOND_NONE)return 1;if(!device.device.createBond())throw new VmHardware.Failure("unavailable","Android refused to begin pairing; pairing confirmation stays in Android's UI.");return 1;}
        if(op.equals("bt_uuids")){boolean refresh=VmHardware.integer(a,1,0,1)==1;if(refresh){enabled(adapter(c));if(!device.device.fetchUuidsWithSdp())throw new VmHardware.Failure("unavailable","Android refused the service UUID refresh.");}return device.uuids(refresh);}
        if(op.equals("bt_rfcomm_connect")){UUID uuid=uuid(VmHardware.text(a,1,36));boolean secure=VmHardware.integer(a,2,0,1)==1;int timeout=VmHardware.integer(a,3,1000,120000);visible(c);BluetoothAdapter adapter=adapter(c);enabled(adapter);if(scanGranted(c)&&adapter.isDiscovering())throw new VmHardware.Failure("busy","Finish Bluetooth discovery before connecting RFCOMM.");Stream stream=new Stream(c,secure?device.device.createRfcommSocketToServiceRecord(uuid):device.device.createInsecureRfcommSocketToServiceRecord(uuid),false);try{stream.connect(timeout);return VmHardware.add(stream);}catch(Exception error){stream.close();throw error;}}
        throw new VmHardware.Failure("unsupported_operation","Unknown Classic Bluetooth operation.");
    }
}
