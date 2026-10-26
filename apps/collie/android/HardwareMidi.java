package org.flexscript.collie;

import android.Manifest;
import android.content.Context;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothManager;
import android.bluetooth.BluetoothDevice;
import android.content.pm.PackageManager;
import android.media.midi.*;
import android.os.Build;
import java.io.IOException;
import java.util.*;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import org.json.*;

/** MIDI framework devices and ports. Callbacks copy data into bounded queues. */
final class HardwareMidi {
    static MidiManager manager(VmHardware.Context c)throws Exception{MidiManager manager=(MidiManager)c.host.getSystemService(Context.MIDI_SERVICE);if(manager==null)throw new VmHardware.Failure("unsupported","Android MIDI service is unavailable.");return manager;}
    static String id(MidiDeviceInfo device){return "midi-"+device.getId();}
    static List<MidiDeviceInfo> devices(VmHardware.Context c)throws Exception{MidiManager manager=manager(c);TreeMap<Integer,MidiDeviceInfo> devices=new TreeMap<>();if(Build.VERSION.SDK_INT>=33){for(int transport:new int[]{MidiManager.TRANSPORT_MIDI_BYTE_STREAM,MidiManager.TRANSPORT_UNIVERSAL_MIDI_PACKETS})for(MidiDeviceInfo info:manager.getDevicesForTransport(transport))devices.put(info.getId(),info);}else for(MidiDeviceInfo info:manager.getDevices())devices.put(info.getId(),info);return new ArrayList<>(devices.values());}
    static MidiDeviceInfo device(VmHardware.Context c,String id)throws Exception{for(MidiDeviceInfo device:devices(c))if(id(device).equals(id))return device;throw new VmHardware.Failure("disconnected","Selected MIDI device is unavailable.");}
    static int protocol(MidiDeviceInfo device){return Build.VERSION.SDK_INT>=33?device.getDefaultProtocol():-1;}
    static String property(MidiDeviceInfo device,String key){Object value=device.getProperties().get(key);return value instanceof String?((String)value).substring(0,Math.min(256,((String)value).length())):"";}
    static JSONObject info(MidiDeviceInfo device)throws Exception{return VmHardware.object("id",id(device),"type",device.getType(),"name",property(device,MidiDeviceInfo.PROPERTY_NAME),"manufacturer",property(device,MidiDeviceInfo.PROPERTY_MANUFACTURER),"product",property(device,MidiDeviceInfo.PROPERTY_PRODUCT),"version",property(device,MidiDeviceInfo.PROPERTY_VERSION),"inputs",device.getInputPortCount(),"outputs",device.getOutputPortCount(),"private",device.isPrivate(),"protocol",protocol(device),"transport",protocol(device)<0?"bytes":"ump");}
    interface Listener {void added(MidiDeviceInfo device);void removed(MidiDeviceInfo device);void status(MidiDeviceStatus status);}
    static List<MidiManager.DeviceCallback> watch(VmHardware.Context c,Listener listener)throws Exception{
        MidiManager manager=manager(c);List<MidiManager.DeviceCallback> callbacks=new ArrayList<>();
        try{for(int transport=1;transport<=(Build.VERSION.SDK_INT>=33?2:1);transport++){
            MidiManager.DeviceCallback callback=new MidiManager.DeviceCallback(){public void onDeviceAdded(MidiDeviceInfo device){listener.added(device);}public void onDeviceRemoved(MidiDeviceInfo device){listener.removed(device);}public void onDeviceStatusChanged(MidiDeviceStatus status){listener.status(status);}};
            if(Build.VERSION.SDK_INT>=33)manager.registerDeviceCallback(transport,command->HardwareSensors.events().post(command),callback);else manager.registerDeviceCallback(callback,HardwareSensors.events());callbacks.add(callback);
        }return callbacks;}catch(Exception error){for(MidiManager.DeviceCallback callback:callbacks)manager.unregisterDeviceCallback(callback);throw error;}
    }
    static void unwatch(MidiManager manager,List<MidiManager.DeviceCallback> callbacks){if(callbacks!=null)for(MidiManager.DeviceCallback callback:callbacks)try{manager.unregisterDeviceCallback(callback);}catch(RuntimeException ignored){}}
    static JSONObject status(MidiDeviceStatus state)throws Exception{MidiDeviceInfo device=state.getDeviceInfo();int inputs=0,outputs=0;for(int i=0;i<device.getInputPortCount();i++)if(state.isInputPortOpen(i))inputs++;for(int i=0;i<device.getOutputPortCount();i++)outputs+=state.getOutputPortOpenCount(i);return VmHardware.object("event","status","device",id(device),"inputs_open",inputs,"output_connections",outputs);}
    static boolean supports(String op){switch(op){case "midi_list":case "midi_info":case "midi_ports":case "midi_watch":case "midi_open":case "midi_bluetooth_open":case "midi_port_open":case "midi_send":case "midi_flush":return true;default:return false;}}
    static void capabilities(VmHardware.Context c,JSONArray out)throws Exception{boolean supported=c.host.getPackageManager().hasSystemFeature(PackageManager.FEATURE_MIDI);out.put(VmHardware.capability("midi",supported,supported,"midi"));out.put(VmHardware.capability("midi_ump",supported&&Build.VERSION.SDK_INT>=33,supported&&Build.VERSION.SDK_INT>=33,"midi"));}
    static final class Watch extends VmHardware.Handle implements Listener {
        final MidiManager manager;List<MidiManager.DeviceCallback> callbacks;
        Watch(VmHardware.Context c)throws Exception{super(c,"midi","midi_events");manager=manager(c);callbacks=watch(c,this);emit(VmHardware.object("event","ready"));}
        private void event(String kind,MidiDeviceInfo device){try{emit(VmHardware.object("event",kind,"device",HardwareMidi.info(device)));}catch(Exception ignored){}}
        public void added(MidiDeviceInfo device){event("added",device);}public void removed(MidiDeviceInfo device){event("removed",device);}public void status(MidiDeviceStatus status){try{emit(HardwareMidi.status(status));}catch(Exception ignored){}}
        public synchronized void close()throws IOException{if(closed)return;super.close();unwatch(manager,callbacks);}
    }
    static final class Opening extends VmHardware.Handle {
        final CountDownLatch ready=new CountDownLatch(1);MidiDevice device;
        Opening(VmHardware.Context c){super(c,"midi","midi_opening");}
        synchronized void result(MidiDevice result){if(closed){if(result!=null)try{result.close();}catch(Exception ignored){}}else device=result;ready.countDown();}
        synchronized MidiDevice take(){MidiDevice result=device;device=null;closed=true;return result;}
        public synchronized void close()throws IOException{if(closed)return;super.close();if(device!=null){device.close();device=null;}ready.countDown();}
    }
    static final class Device extends VmHardware.Handle implements Listener {
        final VmHardware.Context context;final MidiDevice device;final MidiManager manager;final List<Port> ports=new ArrayList<>();List<MidiManager.DeviceCallback> callbacks;
        Device(VmHardware.Context c,MidiDevice device)throws Exception{super(c,"midi","midi_device");context=c;this.device=device;manager=manager(c);try{callbacks=watch(c,this);if(closed){unwatch(manager,callbacks);throw new VmHardware.Failure("disconnected","MIDI device disconnected while opening.");}}catch(Exception error){device.close();throw error;}}
        void access(VmHardware.Context c)throws Exception{super.access(c);try{device(c,id(device.getInfo()));}catch(Exception error){close();throw error;}if(device.getInfo().getType()==MidiDeviceInfo.TYPE_BLUETOOTH&&Build.VERSION.SDK_INT>=31&&c.host.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT)!=PackageManager.PERMISSION_GRANTED){close();throw new VmHardware.Failure("permission_revoked","Bluetooth MIDI permission was revoked.");}}
        Object info()throws Exception{check();return HardwareMidi.info(device.getInfo()).put("kind",kind);}
        public void added(MidiDeviceInfo ignored){}public void removed(MidiDeviceInfo removed){if(removed.getId()==device.getInfo().getId())try{close();}catch(Exception ignored){}}public void status(MidiDeviceStatus status){if(status.getDeviceInfo().getId()==device.getInfo().getId())try{emit(HardwareMidi.status(status));}catch(Exception ignored){}}
        synchronized String port(VmHardware.Context c,String direction,int number)throws Exception{check();ports.removeIf(port->port.closed);Port port=new Port(c,this,direction,number);ports.add(port);try{return VmHardware.add(port);}catch(Exception error){ports.remove(port);port.close();throw error;}}
        public void close()throws IOException{List<Port> closing;synchronized(this){if(closed)return;super.close();closing=new ArrayList<>(ports);ports.clear();}unwatch(manager,callbacks);IOException failure=null;for(Port port:closing)try{port.close();}catch(Exception error){if(failure==null)failure=error instanceof IOException?(IOException)error:new IOException(error);}try{device.close();}catch(Exception error){if(failure==null)failure=error instanceof IOException?(IOException)error:new IOException(error);}if(failure!=null)throw failure;}
    }
    static final class Port extends VmHardware.Handle {
        final Device parent;final int number;final String direction;final MidiInputPort sending;final MidiOutputPort receiving;final MidiReceiver receiver;
        Port(VmHardware.Context c,Device parent,String direction,int number)throws Exception{
            super(c,"midi",direction.equals("send")?"midi_send":"midi_receive");this.parent=parent;this.number=number;this.direction=direction;
            if(direction.equals("send")){if(number>=parent.device.getInfo().getInputPortCount())throw new VmHardware.Failure("invalid_argument","No such MIDI input port.");sending=parent.device.openInputPort(number);receiving=null;receiver=null;if(sending==null)throw new VmHardware.Failure("busy","MIDI input port is already in use or unavailable.");}
            else if(direction.equals("receive")){if(number>=parent.device.getInfo().getOutputPortCount())throw new VmHardware.Failure("invalid_argument","No such MIDI output port.");sending=null;receiving=parent.device.openOutputPort(number);if(receiving==null)throw new VmHardware.Failure("unavailable","MIDI output port could not be opened.");receiver=new MidiReceiver(VmHardware.MAX_BYTES){public void onSend(byte[] bytes,int offset,int count,long timestamp)throws IOException{try{int at=0;while(at<count){int size=Math.min(VmHardware.MAX_BYTES,count-at);emit(VmHardware.object("event","message","timestamp_ns",timestamp,"data",VmHardware.bytes(Arrays.copyOfRange(bytes,offset+at,offset+at+size))));at+=size;}}catch(Exception error){throw new IOException(error);}}public void onFlush()throws IOException{try{emit(VmHardware.object("event","flush"));}catch(Exception error){throw new IOException(error);}}};try{receiving.connect(receiver);}catch(Exception error){receiving.close();throw error;}}
            else throw new VmHardware.Failure("invalid_argument","MIDI direction must be send (device input) or receive (device output).");
        }
        void access(VmHardware.Context c)throws Exception{super.access(c);parent.access(c);}
        Object info()throws Exception{check();return VmHardware.object("kind",kind,"device",id(parent.device.getInfo()),"port",number,"direction",direction,"transport",protocol(parent.device.getInfo())<0?"bytes":"ump");}
        Object send(byte[] data,long timestamp)throws Exception{check();if(sending==null)throw new VmHardware.Failure("wrong_direction","MIDI send requires a send port.");if(protocol(parent.device.getInfo())>=0&&data.length%4!=0)throw new VmHardware.Failure("invalid_argument","UMP data must consist of complete 32-bit words.");if(protocol(parent.device.getInfo())>=0){int at=0;while(at<data.length){VmHardware.check();int count=Math.min(1008,data.length-at);sending.send(data,at,count,timestamp);at+=count;}}else sending.send(data,0,data.length,timestamp);return data.length;}
        Object write(byte[] data)throws Exception{return send(data,0);}
        Object flush()throws Exception{if(sending==null)throw new VmHardware.Failure("wrong_direction","Flush requires a MIDI send port.");sending.flush();return 1;}
        public void close()throws IOException{synchronized(this){if(closed)return;super.close();}if(receiving!=null){try{receiving.disconnect(receiver);}finally{receiving.close();}}if(sending!=null)sending.close();}
    }
    static Object call(VmHardware.Context c,String op,JSONArray args)throws Exception{
        if(op.equals("midi_list")){int offset=VmHardware.integer(args,0,0,100000),limit=VmHardware.integer(args,1,1,32);List<MidiDeviceInfo> list=devices(c);int end=Math.min(list.size(),offset+limit);JSONArray out=new JSONArray();for(int i=offset;i<end;i++)out.put(info(list.get(i)));return VmHardware.object("devices",out,"next",end<list.size()?end:-1,"total",list.size());}
        if(op.equals("midi_info"))return info(device(c,VmHardware.text(args,0,128)));
        if(op.equals("midi_ports")){MidiDeviceInfo device=device(c,VmHardware.text(args,0,128));int offset=VmHardware.integer(args,1,0,100000),limit=VmHardware.integer(args,2,1,32);MidiDeviceInfo.PortInfo[] ports=device.getPorts();int end=Math.min(ports.length,offset+limit);JSONArray out=new JSONArray();for(int i=offset;i<end;i++){MidiDeviceInfo.PortInfo port=ports[i];out.put(VmHardware.object("direction",port.getType()==MidiDeviceInfo.PortInfo.TYPE_INPUT?"input":"output","number",port.getPortNumber(),"name",port.getName()));}return VmHardware.object("ports",out,"next",end<ports.length?end:-1,"total",ports.length);}
        if(op.equals("midi_watch"))return VmHardware.add(new Watch(c));
        if(op.equals("midi_open")||op.equals("midi_bluetooth_open")){
            MidiDeviceInfo info=null;BluetoothDevice bluetooth=null;
            if(op.equals("midi_bluetooth_open")){String address=VmHardware.text(args,0,17);if(!BluetoothAdapter.checkBluetoothAddress(address))throw new VmHardware.Failure("invalid_argument","Bluetooth MIDI address must be a colon-separated uppercase MAC address.");if(Build.VERSION.SDK_INT>=31)VmHardware.require(c,Manifest.permission.BLUETOOTH_CONNECT);BluetoothManager bluetoothManager=(BluetoothManager)c.host.getSystemService(Context.BLUETOOTH_SERVICE);BluetoothAdapter adapter=bluetoothManager==null?null:bluetoothManager.getAdapter();if(adapter==null||!adapter.isEnabled())throw new VmHardware.Failure("unavailable","Bluetooth is unavailable or disabled.");bluetooth=adapter.getRemoteDevice(address);}
            else{info=device(c,VmHardware.text(args,0,128));if(info.getType()==MidiDeviceInfo.TYPE_BLUETOOTH&&Build.VERSION.SDK_INT>=31)VmHardware.require(c,Manifest.permission.BLUETOOTH_CONNECT);}
            Opening opening=new Opening(c);VmHardware.blocking(opening);try{if(bluetooth==null)manager(c).openDevice(info,opening::result,HardwareSensors.events());else manager(c).openBluetoothDevice(bluetooth,opening::result,HardwareSensors.events());if(!opening.ready.await(8,TimeUnit.SECONDS))throw new VmHardware.Failure("timeout","Android did not finish opening the MIDI device.");VmHardware.check();opening.check();MidiDevice opened=opening.take();if(opened==null)throw new VmHardware.Failure("unavailable","Android could not open this MIDI device.");return VmHardware.add(new Device(c,opened));}finally{opening.close();VmHardware.unblocking();}
        }
        if(op.equals("midi_port_open")){Device device=VmHardware.handle(c,VmHardware.text(args,0,128),Device.class);device.access(c);return device.port(c,VmHardware.text(args,1,16),VmHardware.integer(args,2,0,65535));}
        Port port=VmHardware.handle(c,VmHardware.text(args,0,128),Port.class);port.access(c);VmHardware.blocking(port);try{if(op.equals("midi_send"))return port.send(VmHardware.data(args.get(1)),VmHardware.longInteger(args,2,0,System.nanoTime()+60000000000L));if(op.equals("midi_flush"))return port.flush();throw new VmHardware.Failure("unsupported_operation","Unknown MIDI operation.");}finally{VmHardware.unblocking();}
    }
}
