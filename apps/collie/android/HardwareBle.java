package org.flexscript.collie;

import android.Manifest;
import android.bluetooth.*;
import android.bluetooth.le.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.location.LocationManager;
import android.os.Build;
import android.os.ParcelUuid;
import java.io.IOException;
import java.util.*;
import org.json.*;

/** SDK BLE discovery/advertisement transport. AD payloads remain guest bytes. */
final class HardwareBle {
    static boolean supports(String op){return op.equals("ble_info")||op.equals("ble_scan")||op.equals("ble_scan_page")||op.equals("ble_advertise");}
    static BluetoothAdapter adapter(VmHardware.Context c)throws Exception{BluetoothManager manager=c.host.getSystemService(BluetoothManager.class);BluetoothAdapter adapter=manager==null?null:manager.getAdapter();if(adapter==null||!c.host.getPackageManager().hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE))throw new VmHardware.Failure("unsupported","This Android device has no BLE adapter.");return adapter;}
    static void enabled(BluetoothAdapter adapter)throws Exception{if(!adapter.isEnabled())throw new VmHardware.Failure("bluetooth_disabled","Turn on Bluetooth before BLE operations.");}
    static void visible(VmHardware.Context c)throws Exception{if(!c.host.hardwareVisible)throw new VmHardware.Failure("foreground_required","Start this BLE operation while Collie is visible.");}
    static ParcelUuid uuid(String text)throws Exception{if(text.isEmpty())return null;try{UUID value=UUID.fromString(text);if(!value.toString().equalsIgnoreCase(text))throw new IllegalArgumentException();return new ParcelUuid(value);}catch(IllegalArgumentException error){throw new VmHardware.Failure("invalid_argument","Use an empty or canonical 128-bit BLE UUID.");}}
    static void scanPermission(VmHardware.Context c)throws Exception{
        HardwareBluetooth.connectPermission(c);if(Build.VERSION.SDK_INT>=31)VmHardware.require(c,Manifest.permission.BLUETOOTH_SCAN);
        try{VmHardware.require(c,Manifest.permission.ACCESS_COARSE_LOCATION,Manifest.permission.ACCESS_FINE_LOCATION);}catch(VmHardware.Consent consent){consent.request.put("key","location");throw consent;}
        LocationManager manager=c.host.getSystemService(LocationManager.class);if(manager==null||!(Build.VERSION.SDK_INT>=28?manager.isLocationEnabled():manager.isProviderEnabled(LocationManager.GPS_PROVIDER)||manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)))throw new VmHardware.Failure("location_disabled","Turn on Android Location before BLE discovery.");
    }
    static void capabilities(VmHardware.Context c,JSONArray out)throws Exception{
        BluetoothManager manager=c.host.getSystemService(BluetoothManager.class);BluetoothAdapter adapter=manager==null?null:manager.getAdapter();boolean supported=adapter!=null&&c.host.getPackageManager().hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE);boolean permitted=Build.VERSION.SDK_INT<31||c.host.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT)==PackageManager.PERMISSION_GRANTED;
        boolean on=supported&&permitted&&adapter.isEnabled(),scan=Build.VERSION.SDK_INT<31||c.host.checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN)==PackageManager.PERMISSION_GRANTED,advertise=Build.VERSION.SDK_INT<31||c.host.checkSelfPermission(Manifest.permission.BLUETOOTH_ADVERTISE)==PackageManager.PERMISSION_GRANTED,location=c.host.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION)==PackageManager.PERMISSION_GRANTED;
        LocationManager lm=c.host.getSystemService(LocationManager.class);boolean locationOn=lm!=null&&(Build.VERSION.SDK_INT>=28?lm.isLocationEnabled():lm.isProviderEnabled(LocationManager.GPS_PROVIDER)||lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER));
        out.put(VmHardware.object("id","bluetooth_le_scan","implemented",true,"supported",supported,"available",on&&scan&&location&&locationOn,"permission","bluetooth","also","location","runtime_permission_required",!permitted||!scan||!location,"location_enabled",locationOn));
        Object advertising=!supported?false:on?adapter.isMultipleAdvertisementSupported():JSONObject.NULL;out.put(VmHardware.object("id","bluetooth_le_advertise","implemented",true,"supported",advertising,"support_known",!supported||on,"available",Boolean.TRUE.equals(advertising)&&on&&advertise,"permission","bluetooth","runtime_permission_required",!permitted||!advertise));
    }
    static void event(VmHardware.Handle handle,String type,Object... fields){try{Object[] values=new Object[fields.length+2];values[0]="event";values[1]=type;System.arraycopy(fields,0,values,2,fields.length);handle.emit(VmHardware.object(values));}catch(Exception ignored){}}
    static abstract class Radio extends VmHardware.Handle {
        final VmHardware.Context context;final Context app;boolean registered;String state="pending";final BroadcastReceiver receiver;
        Radio(VmHardware.Context c,String kind,String also){super(c,"bluetooth",kind,also);context=c;app=c.host.getApplicationContext();receiver=new BroadcastReceiver(){public void onReceive(Context ignored,Intent intent){if(intent.getIntExtra(BluetoothAdapter.EXTRA_STATE,-1)!=BluetoothAdapter.STATE_ON)finish("bluetooth_disabled");}};}
        synchronized void watch(){IntentFilter filter=new IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED);if(Build.VERSION.SDK_INT>=33)app.registerReceiver(receiver,filter,null,HardwareSensors.events(),Context.RECEIVER_EXPORTED);else app.registerReceiver(receiver,filter,null,HardwareSensors.events());registered=true;}
        abstract void stopSdk();
        abstract void cancelDeadline();
        synchronized void finish(String reason){if(closed||state.equals("complete")||state.equals("error"))return;state="complete";cancelDeadline();try{stopSdk();}finally{if(registered){registered=false;app.unregisterReceiver(receiver);}}event(this,"finished","reason",reason);}
        synchronized void failure(int code){if(closed||state.equals("complete")||state.equals("error"))return;state="error";cancelDeadline();try{stopSdk();}finally{if(registered){registered=false;app.unregisterReceiver(receiver);}}event(this,"error","code","platform_error","status",code);}
        public void access(VmHardware.Context c)throws Exception{check();HardwareBluetooth.connectPermission(c);}
        public synchronized Object info()throws Exception{check();return VmHardware.object("kind",kind,"state",state);}
        public synchronized void close()throws IOException{if(closed)return;try{finish("closed");}finally{super.close();}}
    }
    static final class Scan extends Radio {
        final BluetoothLeScanner scanner;final ScanCallback callback;final LinkedHashMap<String,JSONObject> peers=new LinkedHashMap<>();boolean started;int omitted;
        final Runnable deadline=()->finish("deadline");
        Scan(VmHardware.Context c,BluetoothLeScanner scanner){super(c,"bluetooth_le_scan","location");this.scanner=scanner;callback=new ScanCallback(){public void onScanFailed(int error){failure(error);}public void onScanResult(int kind,ScanResult result){found(result);}public void onBatchScanResults(List<ScanResult> results){for(ScanResult result:results)found(result);}};}
        synchronized void start(List<ScanFilter> filters,int mode,int duration)throws Exception{watch();state="scanning";started=true;scanner.startScan(filters,new ScanSettings.Builder().setScanMode(mode).setReportDelay(0).setLegacy(false).setPhy(ScanSettings.PHY_LE_ALL_SUPPORTED).build(),callback);HardwareSensors.events().postDelayed(deadline,duration);}
        synchronized void found(ScanResult result){if(closed||!state.equals("scanning"))return;try{String address=result.getDevice().getAddress();int sid=result.getAdvertisingSid();String key=address+"/"+sid;if(!peers.containsKey(key)&&peers.size()>=128){omitted++;return;}ScanRecord record=result.getScanRecord();byte[] raw=record==null?new byte[0]:record.getBytes();if(raw==null)raw=new byte[0];boolean truncated=raw.length>VmHardware.MAX_BYTES;JSONObject value=VmHardware.object("address",address,"sid",sid,"rssi_dbm",result.getRssi(),"timestamp_ns",result.getTimestampNanos(),"connectable",result.isConnectable(),"legacy",result.isLegacy(),"data_status",result.getDataStatus(),"primary_phy",result.getPrimaryPhy(),"secondary_phy",result.getSecondaryPhy(),"periodic_interval",result.getPeriodicAdvertisingInterval(),"tx_power_dbm",result.getTxPower(),"data",VmHardware.bytes(Arrays.copyOf(raw,Math.min(raw.length,VmHardware.MAX_BYTES))),"truncated",truncated);peers.put(key,value);event(this,"found","value",value);}catch(Exception error){event(this,"error","code","callback_failed","message",MainActivity.safe(error));}}
        public void access(VmHardware.Context c)throws Exception{check();scanPermission(c);}
        void cancelDeadline(){HardwareSensors.events().removeCallbacks(deadline);}
        void stopSdk(){if(started){started=false;try{scanner.stopScan(callback);}catch(RuntimeException ignored){}}}
        public synchronized Object info()throws Exception{return ((JSONObject)super.info()).put("total",peers.size()).put("omitted",omitted);}
        synchronized Object page(int offset,int limit)throws Exception{check();JSONArray out=new JSONArray();List<JSONObject> values=new ArrayList<>(peers.values());for(int i=offset;i<Math.min(offset+limit,values.size());i++)out.put(values.get(i));return VmHardware.object("devices",out,"total",values.size(),"omitted",omitted,"next",offset+out.length()<values.size()?offset+out.length():-1);}
        public synchronized void close()throws IOException{try{super.close();}finally{peers.clear();}}
    }
    static final class Advertisement extends Radio {
        final BluetoothLeAdvertiser advertiser;final AdvertiseCallback callback;boolean requested;
        final Runnable deadline=()->finish("deadline");
        Advertisement(VmHardware.Context c,BluetoothLeAdvertiser advertiser){super(c,"bluetooth_le_advertise","");this.advertiser=advertiser;callback=new AdvertiseCallback(){public void onStartFailure(int code){failure(code);}public void onStartSuccess(AdvertiseSettings settings){synchronized(Advertisement.this){if(closed||!state.equals("pending")){try{advertiser.stopAdvertising(callback);}catch(RuntimeException ignored){}return;}state="advertising";event(Advertisement.this,"started","connectable",settings.isConnectable(),"mode",settings.getMode(),"power",settings.getTxPowerLevel());}}};}
        synchronized void start(AdvertiseSettings settings,AdvertiseData data,int duration)throws Exception{watch();requested=true;advertiser.startAdvertising(settings,data,callback);if(duration>0)HardwareSensors.events().postDelayed(deadline,duration);}
        public void access(VmHardware.Context c)throws Exception{super.access(c);if(Build.VERSION.SDK_INT>=31)VmHardware.require(c,Manifest.permission.BLUETOOTH_ADVERTISE);}
        void cancelDeadline(){HardwareSensors.events().removeCallbacks(deadline);}
        void stopSdk(){if(requested){requested=false;try{advertiser.stopAdvertising(callback);}catch(RuntimeException ignored){}}}
    }
    static Object call(VmHardware.Context c,String op,JSONArray a)throws Exception{
        if(op.equals("ble_scan_page")){Scan scan=VmHardware.handle(c,VmHardware.text(a,0,128),Scan.class);scan.access(c);return scan.page(VmHardware.integer(a,1,0,128),VmHardware.integer(a,2,1,16));}
        ParcelUuid service=(op.equals("ble_scan")||op.equals("ble_advertise"))?uuid(VmHardware.text(a,0,36)):null;
        String address=op.equals("ble_scan")?VmHardware.text(a,1,17):"";if(!address.isEmpty())address=HardwareBluetooth.address(address);
        int duration=op.equals("ble_scan")?VmHardware.integer(a,2,1000,30000):op.equals("ble_advertise")?VmHardware.integer(a,7,0,180000):0;
        int mode=op.equals("ble_scan")?VmHardware.integer(a,3,0,2):op.equals("ble_advertise")?VmHardware.integer(a,6,0,2):0;
        AdvertiseData data=null;AdvertiseSettings settings=null;
        if(op.equals("ble_advertise")){byte[] serviceData=VmHardware.data(a.get(1)),manufacturerData=VmHardware.data(a.get(3));int manufacturer=VmHardware.integer(a,2,-1,65535),connectable=VmHardware.integer(a,4,0,1),power=VmHardware.integer(a,5,0,3);if(service==null&&serviceData.length>0||manufacturer<0&&manufacturerData.length>0)throw new VmHardware.Failure("invalid_argument","BLE data requires a service UUID or manufacturer ID.");if(serviceData.length>27||manufacturerData.length>27)throw new VmHardware.Failure("size_limit","Legacy BLE advertisement data is limited by the 31-byte radio packet; each data field must be at most 27 bytes.");AdvertiseData.Builder builder=new AdvertiseData.Builder().setIncludeDeviceName(false).setIncludeTxPowerLevel(false);if(service!=null){if(serviceData.length==0)builder.addServiceUuid(service);else builder.addServiceData(service,serviceData);}if(manufacturer>=0)builder.addManufacturerData(manufacturer,manufacturerData);data=builder.build();settings=new AdvertiseSettings.Builder().setAdvertiseMode(mode).setConnectable(connectable==1).setTxPowerLevel(power).setTimeout(0).build();}
        BluetoothAdapter adapter=adapter(c);HardwareBluetooth.connectPermission(c);
        if(op.equals("ble_info"))return VmHardware.object("enabled",adapter.isEnabled(),"multiple_advertisement",adapter.isMultipleAdvertisementSupported(),"extended_advertisement",adapter.isLeExtendedAdvertisingSupported(),"periodic_advertisement",adapter.isLePeriodicAdvertisingSupported(),"phy_2m",adapter.isLe2MPhySupported(),"phy_coded",adapter.isLeCodedPhySupported(),"max_advertising_data",adapter.getLeMaximumAdvertisingDataLength());
        enabled(adapter);visible(c);
        if(op.equals("ble_scan")){scanPermission(c);BluetoothLeScanner scanner=adapter.getBluetoothLeScanner();if(scanner==null)throw new VmHardware.Failure("unavailable","Android's BLE scanner is unavailable.");List<ScanFilter> filters=new ArrayList<>();if(service!=null||!address.isEmpty()){ScanFilter.Builder filter=new ScanFilter.Builder();if(service!=null)filter.setServiceUuid(service);if(!address.isEmpty())filter.setDeviceAddress(address);filters.add(filter.build());if(service!=null){ScanFilter.Builder dataFilter=new ScanFilter.Builder().setServiceData(service,new byte[0]);if(!address.isEmpty())dataFilter.setDeviceAddress(address);filters.add(dataFilter.build());}}Scan scan=new Scan(c,scanner);try{scan.start(filters,mode,duration);return VmHardware.add(scan);}catch(Exception error){scan.close();throw error;}}
        if(op.equals("ble_advertise")){if(Build.VERSION.SDK_INT>=31)VmHardware.require(c,Manifest.permission.BLUETOOTH_ADVERTISE);BluetoothLeAdvertiser advertiser=adapter.getBluetoothLeAdvertiser();if(advertiser==null)throw new VmHardware.Failure("unsupported","Android's BLE advertiser is unavailable.");Advertisement handle=new Advertisement(c,advertiser);try{handle.start(settings,data,duration);return VmHardware.add(handle);}catch(Exception error){handle.close();throw error;}}
        throw new VmHardware.Failure("unsupported_operation","Unknown BLE operation.");
    }
}
