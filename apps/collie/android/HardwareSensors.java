package org.flexscript.collie;

import android.Manifest;
import android.content.Context;
import android.hardware.*;
import android.os.*;
import java.io.IOException;
import java.util.*;
import org.json.*;

/** SensorService listeners become bounded event streams, never guest callbacks. */
final class HardwareSensors {
    private static HandlerThread thread;
    static synchronized Handler events(){if(thread==null){thread=new HandlerThread("collie-hardware-events");thread.setDaemon(true);thread.start();}return new Handler(thread.getLooper());}
    static SensorManager manager(VmHardware.Context c){return (SensorManager)c.host.getApplicationContext().getSystemService(Context.SENSOR_SERVICE);}
    static boolean supports(String op){return op.equals("sensor_list")||op.equals("sensor_info")||op.equals("sensor_open");}
    static String id(Sensor s){return "sensor-"+s.getId()+"-"+s.getType()+"-"+Integer.toHexString((s.getName()+s.getVendor()).hashCode());}
    static java.util.List<Sensor> sensors(VmHardware.Context c){
        SensorManager manager=manager(c);TreeMap<String,Sensor> values=new TreeMap<>();for(Sensor sensor:manager.getSensorList(Sensor.TYPE_ALL))values.put(id(sensor),sensor);
        if(manager.isDynamicSensorDiscoverySupported())for(Sensor sensor:manager.getDynamicSensorList(Sensor.TYPE_ALL))values.put(id(sensor),sensor);
        return new ArrayList<>(values.values());
    }
    static Sensor sensor(VmHardware.Context c,String id)throws Exception{for(Sensor s:sensors(c))if(id(s).equals(id))return s;throw new VmHardware.Failure("unavailable","Selected sensor is unavailable.");}
    static Object info(Sensor s)throws Exception{return VmHardware.object("id",id(s),"type",s.getType(),"string_type",s.getStringType(),"name",s.getName(),"vendor",s.getVendor(),"version",s.getVersion(),"maximum_range",VmHardware.real(s.getMaximumRange()),"resolution",VmHardware.real(s.getResolution()),"power_ma",VmHardware.real(s.getPower()),"minimum_delay_us",s.getMinDelay(),"maximum_delay_us",s.getMaxDelay(),"reporting_mode",s.getReportingMode(),"wake_up",s.isWakeUpSensor(),"dynamic",s.isDynamicSensor());}
    static void capabilities(VmHardware.Context c,JSONArray out)throws Exception{boolean present=!sensors(c).isEmpty();out.put(VmHardware.capability("sensors",present,present,"sensors"));}
    static void permission(VmHardware.Context c,Sensor s)throws Exception{
        if(Build.VERSION.SDK_INT>=29 && (s.getType()==Sensor.TYPE_STEP_COUNTER||s.getType()==Sensor.TYPE_STEP_DETECTOR))VmHardware.require(c,Manifest.permission.ACTIVITY_RECOGNITION);
        if(s.getType()==Sensor.TYPE_HEART_RATE || s.getType()==Sensor.TYPE_HEART_BEAT)VmHardware.require(c,Build.VERSION.SDK_INT>=36?"android.permission.health.READ_HEART_RATE":Manifest.permission.BODY_SENSORS);
    }
    static boolean granted(VmHardware.Context c,Sensor s){
        String required=null;if(Build.VERSION.SDK_INT>=29 && (s.getType()==Sensor.TYPE_STEP_COUNTER||s.getType()==Sensor.TYPE_STEP_DETECTOR))required=Manifest.permission.ACTIVITY_RECOGNITION;
        if(s.getType()==Sensor.TYPE_HEART_RATE||s.getType()==Sensor.TYPE_HEART_BEAT)required=Build.VERSION.SDK_INT>=36?"android.permission.health.READ_HEART_RATE":Manifest.permission.BODY_SENSORS;
        return required==null || c.host.checkSelfPermission(required)==android.content.pm.PackageManager.PERMISSION_GRANTED;
    }
    private static Object sample(Sensor sensor,long timestamp,int accuracy,float[] values)throws Exception{
        JSONArray data=new JSONArray();for(float value:values)data.put(VmHardware.real(value));return VmHardware.object("event","sample","sensor",id(sensor),"timestamp_ns",timestamp,"accuracy",accuracy,"values",data);
    }
    static final class Subscription extends VmHardware.Handle implements SensorEventListener {
        final SensorManager manager;final Sensor sensor;
        Subscription(VmHardware.Context c,Sensor s,int period)throws Exception{
            super(c,"sensors","sensor");manager=manager(c);sensor=s;
            if(!manager.registerListener(this,s,period,events()))throw new VmHardware.Failure("unavailable","Android refused this sensor subscription.");
        }
        public void onSensorChanged(SensorEvent event){try{emit(sample(event.sensor,event.timestamp,event.accuracy,event.values));}catch(Exception error){emit(error(error));}}
        public void onAccuracyChanged(Sensor sensor,int accuracy){try{emit(VmHardware.object("event","accuracy","sensor",id(sensor),"accuracy",accuracy));}catch(Exception ignored){}}
        void access(VmHardware.Context c)throws Exception{super.access(c);if(!granted(c,sensor)){close();throw new VmHardware.Failure("permission_revoked","Sensor permission was revoked. Reopen the sensor after granting access.");}}
        Object info()throws Exception{check();return HardwareSensors.info(sensor);}
        public synchronized void close()throws IOException{if(closed)return;super.close();manager.unregisterListener(this);}
    }
    static final class Trigger extends VmHardware.Handle {
        final SensorManager manager;final Sensor sensor;final TriggerEventListener listener;
        Trigger(VmHardware.Context c,Sensor sensor)throws Exception{
            super(c,"sensors","sensor_trigger");manager=manager(c);this.sensor=sensor;
            listener=new TriggerEventListener(){public void onTrigger(TriggerEvent event){try{emit(sample(event.sensor,event.timestamp,0,event.values));}catch(Exception error){emit(error(error));}}};
            if(!manager.requestTriggerSensor(listener,sensor))throw new VmHardware.Failure("unavailable","Android refused this trigger sensor.");
        }
        void access(VmHardware.Context c)throws Exception{super.access(c);if(!granted(c,sensor)){close();throw new VmHardware.Failure("permission_revoked","Sensor permission was revoked. Reopen the sensor after granting access.");}}
        Object info()throws Exception{check();return HardwareSensors.info(sensor);}
        public synchronized void close()throws IOException{if(closed)return;super.close();manager.cancelTriggerSensor(listener,sensor);}
    }
    private static JSONObject error(Exception e){try{return VmHardware.object("event","error","message",MainActivity.safe(e));}catch(Exception impossible){return new JSONObject();}}
    static Object call(VmHardware.Context c,String op,JSONArray args)throws Exception{
        if(op.equals("sensor_list")){
            if(args.length()!=0 && args.length()!=2)throw new VmHardware.Failure("invalid_argument","Use no sensor-list arguments or an offset and page limit.");
            int offset=args.length()==0?0:VmHardware.integer(args,0,0,100000),limit=args.length()==0?16:VmHardware.integer(args,1,1,32);java.util.List<Sensor> list=sensors(c);JSONArray out=new JSONArray();int end=Math.min(list.size(),offset+limit);for(int i=offset;i<end;i++)out.put(info(list.get(i)));return VmHardware.object("sensors",out,"next",end<list.size()?end:-1,"total",list.size());
        }
        Sensor sensor=sensor(c,VmHardware.text(args,0,128));if(op.equals("sensor_info"))return info(sensor);
        permission(c,sensor);int period=VmHardware.integer(args,1,5000,1000000);
        return VmHardware.add(sensor.getReportingMode()==Sensor.REPORTING_MODE_ONE_SHOT?new Trigger(c,sensor):new Subscription(c,sensor,period));
    }
}
