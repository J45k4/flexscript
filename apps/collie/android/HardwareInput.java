package org.flexscript.collie;

import android.hardware.input.InputManager;
import android.os.Build;
import android.view.*;
import java.io.IOException;
import java.util.*;
import java.util.concurrent.CopyOnWriteArrayList;
import org.json.*;

/** Public input inventory and copied events delivered to Collie's own Activity. */
final class HardwareInput {
    private static final Object LOCK=new Object();
    private static final CopyOnWriteArrayList<Watch> WATCHES=new CopyOnWriteArrayList<>();
    static boolean supports(String op){return op.startsWith("input_");}
    static InputManager manager(VmHardware.Context c)throws Exception{InputManager value=c.host.getSystemService(InputManager.class);if(value==null)throw new VmHardware.Failure("unsupported","Android's input service is unavailable.");return value;}
    static void visible(VmHardware.Context c)throws Exception{if(!c.host.hardwareVisible)throw new VmHardware.Failure("foreground_required","Input subscriptions require Collie to remain visible.");}
    static void capabilities(VmHardware.Context c,JSONArray out)throws Exception{boolean present=c.host.getSystemService(InputManager.class)!=null;out.put(VmHardware.object("id","input","implemented",true,"supported",present,"available",present&&c.host.hardwareVisible,"permission","input","foreground_required",true,"scope","collie_activity"));}
    static InputDevice device(InputManager manager,int id)throws Exception{InputDevice value=manager.getInputDevice(id);if(value==null)throw new VmHardware.Failure("disconnected","The selected Android input device is absent; enumerate again.");return value;}
    static JSONObject info(InputDevice d)throws Exception{return VmHardware.object("id",d.getId(),"name",d.getName(),"descriptor",d.getDescriptor(),"vendor_id",d.getVendorId(),"product_id",d.getProductId(),"sources",d.getSources(),"keyboard_type",d.getKeyboardType(),"virtual",d.isVirtual(),"external",Build.VERSION.SDK_INT>=29?d.isExternal():JSONObject.NULL,"controller_number",d.getControllerNumber(),"microphone",d.hasMicrophone(),"motion_ranges",d.getMotionRanges().size());}
    static final class Watch extends VmHardware.Handle implements InputManager.InputDeviceListener {
        final VmHardware.Context context;final InputManager manager;final int selected,mask,history;final int[] axes;boolean listening;
        Watch(VmHardware.Context c,InputManager m,int selected,int mask,int[] axes,int history){super(c,"input","input_events");context=c;manager=m;this.selected=selected;this.mask=mask;this.axes=axes;this.history=history;}
        void start()throws Exception{synchronized(LOCK){visible(context);if(WATCHES.size()>=8)throw new VmHardware.Failure("resource_limit","At most eight input subscriptions may be active in Collie.");WATCHES.add(this);try{if((mask&8)!=0||selected!=-1){manager.registerInputDeviceListener(this,HardwareSensors.events());listening=true;}check();visible(context);}catch(Exception error){close();throw error;}}}
        boolean accepts(MainActivity host,int device,int bit){return !closed&&context.host==host&&host.hardwareVisible&&(mask&bit)!=0&&(selected==-1||selected==device);}
        void changed(String event,int id){if(!accepts(context.host,id,8))return;try{emit(VmHardware.object("event",event,"device_id",id));}catch(Exception ignored){}}
        public void onInputDeviceAdded(int id){changed("device_added",id);}
        public void onInputDeviceChanged(int id){changed("device_changed",id);}
        public void onInputDeviceRemoved(int id){changed("device_removed",id);if(id==selected)try{close();}catch(IOException ignored){}}
        public void access(VmHardware.Context c)throws Exception{check();visible(c);}
        public Object info()throws Exception{check();JSONArray values=new JSONArray();for(int axis:axes)values.put(axis);return VmHardware.object("kind",kind,"device_id",selected,"mask",mask,"axes",values,"history_limit",history,"scope","collie_activity","queued_events",events.size());}
        void key(KeyEvent e){try{String text=e.getCharacters();boolean truncated=text!=null&&text.length()>4096;if(truncated){int end=Character.isHighSurrogate(text.charAt(4095))?4095:4096;text=text.substring(0,end);}emit(VmHardware.object("event","key","device_id",e.getDeviceId(),"source",e.getSource(),"event_time_ms",e.getEventTime(),"down_time_ms",e.getDownTime(),"action",e.getAction(),"key_code",e.getKeyCode(),"scan_code",e.getScanCode(),"repeat_count",e.getRepeatCount(),"meta_state",e.getMetaState(),"flags",e.getFlags(),"unicode",e.getUnicodeChar(),"characters_truncated",truncated,"characters",text==null?JSONObject.NULL:text));}catch(Exception error){failed(error);}}
        void motion(MotionEvent e,int bit){try{int count=e.getHistorySize(),first=Math.max(0,count-history);for(int h=first;h<count;h++)emit(sample(e,bit,h));emit(sample(e,bit,-1));}catch(Exception error){failed(error);}}
        Object sample(MotionEvent e,int bit,int historical)throws Exception{
            JSONArray pointers=new JSONArray();int total=e.getPointerCount();for(int p=0;p<Math.min(total,32);p++){JSONArray values=new JSONArray();for(int axis:axes)values.put(VmHardware.real(historical<0?e.getAxisValue(axis,p):e.getHistoricalAxisValue(axis,p,historical)));pointers.put(new JSONArray().put(e.getPointerId(p)).put(e.getToolType(p)).put(values));}
            return VmHardware.object("event",bit==1?"touch":"motion","device_id",e.getDeviceId(),"source",e.getSource(),"event_time_ms",historical<0?e.getEventTime():e.getHistoricalEventTime(historical),"down_time_ms",e.getDownTime(),"historical",historical>=0,"history_omitted",Math.max(0,e.getHistorySize()-history),"action",e.getActionMasked(),"action_index",e.getActionIndex(),"buttons",e.getButtonState(),"action_button",historical<0?e.getActionButton():0,"meta_state",e.getMetaState(),"flags",e.getFlags(),"classification",Build.VERSION.SDK_INT>=29?e.getClassification():JSONObject.NULL,"pointers",pointers,"pointers_omitted",Math.max(0,total-32));
        }
        void failed(Exception error){try{emit(VmHardware.object("event","error","code","input_event_failed","message",MainActivity.safe(error)));}catch(Exception ignored){}}
        public void close()throws IOException{synchronized(LOCK){if(closed)return;super.close();WATCHES.remove(this);if(listening){listening=false;manager.unregisterInputDeviceListener(this);}}}
    }
    static void hidden(){synchronized(LOCK){for(Watch watch:WATCHES)try{watch.close();}catch(IOException ignored){}}}
    static void key(MainActivity host,KeyEvent event){for(Watch watch:WATCHES)if(watch.accepts(host,event.getDeviceId(),2))watch.key(event);}
    static void motion(MainActivity host,MotionEvent event,int bit){for(Watch watch:WATCHES)if(watch.accepts(host,event.getDeviceId(),bit))watch.motion(event,bit);}
    static Object call(VmHardware.Context c,String op,JSONArray a)throws Exception{
        InputManager manager=manager(c);
        if(op.equals("input_devices")){int offset=VmHardware.integer(a,0,0,65536),limit=VmHardware.integer(a,1,1,16);int[] ids=manager.getInputDeviceIds();if(ids.length>65536)throw new VmHardware.Failure("resource_limit","Android returned too many input devices.");Arrays.sort(ids);JSONArray rows=new JSONArray();for(int i=offset;i<Math.min(ids.length,offset+limit);i++){InputDevice value=manager.getInputDevice(ids[i]);if(value!=null)rows.put(info(value));}return VmHardware.object("devices",rows,"total",ids.length,"next",offset+limit<ids.length?offset+limit:-1);}
        int id=VmHardware.integer(a,0,-1,Integer.MAX_VALUE);
        if(op.equals("input_watch")){int mask=VmHardware.integer(a,1,1,15),history=VmHardware.integer(a,3,0,8);JSONArray values=a.getJSONArray(2);if(values.length()>16)throw new VmHardware.Failure("invalid_argument","Request at most16 distinct Android motion axes.");int[] axes=new int[values.length()];Set<Integer> seen=new HashSet<>();for(int i=0;i<axes.length;i++){axes[i]=VmHardware.integer(values,i,0,63);if(!seen.add(axes[i]))throw new VmHardware.Failure("invalid_argument","Motion axes must be distinct.");}if(id!=-1)device(manager,id);Watch watch=new Watch(c,manager,id,mask,axes,history);try{watch.start();return VmHardware.add(watch);}catch(Exception error){watch.close();throw error;}}
        InputDevice device=device(manager,id);if(op.equals("input_info"))return info(device);
        if(op.equals("input_ranges")){int offset=VmHardware.integer(a,1,0,65536),limit=VmHardware.integer(a,2,1,16);List<InputDevice.MotionRange> values=device.getMotionRanges();JSONArray rows=new JSONArray();for(int i=offset;i<Math.min(values.size(),offset+limit);i++){InputDevice.MotionRange r=values.get(i);rows.put(VmHardware.object("axis",r.getAxis(),"source",r.getSource(),"minimum",VmHardware.real(r.getMin()),"maximum",VmHardware.real(r.getMax()),"flat",VmHardware.real(r.getFlat()),"fuzz",VmHardware.real(r.getFuzz()),"resolution",VmHardware.real(r.getResolution())));}return VmHardware.object("ranges",rows,"total",values.size(),"next",offset+limit<values.size()?offset+limit:-1);}
        if(op.equals("input_has_keys")){JSONArray values=a.getJSONArray(1);if(values.length()<1||values.length()>128)throw new VmHardware.Failure("invalid_argument","Query1..128 Android key codes.");int[] codes=new int[values.length()];for(int i=0;i<codes.length;i++)codes[i]=VmHardware.integer(values,i,0,KeyEvent.getMaxKeyCode());boolean[] present=device.hasKeys(codes);JSONArray result=new JSONArray();for(boolean value:present)result.put(value);return result;}
        throw new VmHardware.Failure("unsupported_operation","Unknown input operation.");
    }
}
