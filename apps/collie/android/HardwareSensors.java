package org.flexscript.collie;

import android.Manifest;
import android.content.Context;
import android.hardware.*;
import android.os.*;
import java.io.IOException;
import java.util.*;
import java.util.concurrent.*;
import org.json.*;

/** SensorService listeners become bounded event streams, never guest callbacks. */
final class HardwareSensors {
    private static HandlerThread thread;
    private static Handler handler;
    private static final ScheduledThreadPoolExecutor TIMERS=timers();
    private static ScheduledThreadPoolExecutor timers(){ScheduledThreadPoolExecutor pool=new ScheduledThreadPoolExecutor(1,task->{Thread t=new Thread(task,"collie-sensor-deadline");t.setDaemon(true);return t;});pool.setRemoveOnCancelPolicy(true);pool.setKeepAliveTime(30,TimeUnit.SECONDS);pool.allowCoreThreadTimeOut(true);return pool;}
    static synchronized Handler events(){if(thread==null){thread=new HandlerThread("collie-hardware-events");thread.setDaemon(true);thread.start();handler=new Handler(thread.getLooper());}return handler;}
    static SensorManager manager(VmHardware.Context c){return (SensorManager)c.host.getApplicationContext().getSystemService(Context.SENSOR_SERVICE);}
    static boolean supports(String op){switch(op){case "sensor_list":case "sensor_info":case "sensor_open":case "sensor_batch_open":case "sensor_configure":case "sensor_flush":case "sensor_watch":return true;default:return false;}}
    static String id(Sensor s){return "sensor-"+s.getId()+"-"+s.getType()+"-"+Integer.toHexString((s.getName()+s.getVendor()).hashCode());}
    static java.util.List<Sensor> sensors(VmHardware.Context c){
        SensorManager manager=manager(c);TreeMap<String,Sensor> values=new TreeMap<>();for(Sensor sensor:manager.getSensorList(Sensor.TYPE_ALL))values.put(id(sensor),sensor);
        if(manager.isDynamicSensorDiscoverySupported())for(Sensor sensor:manager.getDynamicSensorList(Sensor.TYPE_ALL))values.put(id(sensor),sensor);
        return new ArrayList<>(values.values());
    }
    static Sensor sensor(VmHardware.Context c,String id)throws Exception{for(Sensor s:sensors(c))if(id(s).equals(id))return s;throw new VmHardware.Failure("unavailable","Selected sensor is unavailable.");}
    static Object info(Sensor s)throws Exception{return VmHardware.object("id",id(s),"type",s.getType(),"string_type",s.getStringType(),"name",s.getName(),"vendor",s.getVendor(),"version",s.getVersion(),"maximum_range",VmHardware.real(s.getMaximumRange()),"resolution",VmHardware.real(s.getResolution()),"power_ma",VmHardware.real(s.getPower()),"minimum_delay_us",s.getMinDelay(),"maximum_delay_us",s.getMaxDelay(),"reporting_mode",s.getReportingMode(),"wake_up",s.isWakeUpSensor(),"dynamic",s.isDynamicSensor(),"fifo_max_events",s.getFifoMaxEventCount(),"fifo_reserved_events",s.getFifoReservedEventCount(),"additional_info_supported",s.isAdditionalInfoSupported(),"direct_report_max_rate",s.getHighestDirectReportRateLevel(),"direct_memory_file_supported",s.isDirectChannelTypeSupported(SensorDirectChannel.TYPE_MEMORY_FILE),"direct_hardware_buffer_supported",s.isDirectChannelTypeSupported(SensorDirectChannel.TYPE_HARDWARE_BUFFER));}
    static void capabilities(VmHardware.Context c,JSONArray out)throws Exception{boolean present=!sensors(c).isEmpty();out.put(VmHardware.object("id","sensors","implemented",true,"supported",present,"available",present,"permission","sensors","batching_api",true,"flush_api",true,"dynamic_discovery_supported",manager(c).isDynamicSensorDiscoverySupported()));}
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
        if(values==null||values.length>64)throw new VmHardware.Failure("size_limit","Sensor sample exceeds64 values or has no payload.");
        JSONArray data=new JSONArray();for(float value:values)data.put(VmHardware.real(value));return VmHardware.object("event","sample","sensor",id(sensor),"timestamp_ns",timestamp,"accuracy",accuracy,"values",data);
    }
    static final class Subscription extends VmHardware.Handle {
        final SensorManager manager;final Sensor sensor;final SensorManager.DynamicSensorCallback dynamic;Listener callback;
        int period,latency;long configuration,sequence,pending,flushDeadline,lastCompleted;ScheduledFuture<?> timeout;
        final class Listener extends SensorEventCallback {
            final long revision;
            Listener(long revision){this.revision=revision;}
            boolean current(Sensor source){return !closed&&callback==this&&source!=null&&id(sensor).equals(id(source));}
            void publish(JSONObject value)throws Exception{emit(value.put("configuration",revision));}
            public void onSensorChanged(SensorEvent event){synchronized(Subscription.this){if(!current(event.sensor))return;try{publish((JSONObject)sample(event.sensor,event.timestamp,event.accuracy,event.values));}catch(Exception error){emit(error(error));}}}
            public void onAccuracyChanged(Sensor source,int accuracy){synchronized(Subscription.this){if(!current(source))return;try{publish(VmHardware.object("event","accuracy","sensor",id(source),"accuracy",accuracy));}catch(Exception ignored){}}}
            public void onFlushCompleted(Sensor source){completed(this,source);}
            public void onSensorAdditionalInfo(SensorAdditionalInfo frame){synchronized(Subscription.this){if(!current(frame.sensor))return;try{JSONArray ints=null,floats=null;if(frame.intValues!=null){if(frame.intValues.length>64)throw new VmHardware.Failure("size_limit","Sensor additional integer frame exceeds64 values.");ints=new JSONArray();for(int value:frame.intValues)ints.put(value);}if(frame.floatValues!=null){if(frame.floatValues.length>64)throw new VmHardware.Failure("size_limit","Sensor additional float frame exceeds64 values.");floats=new JSONArray();for(float value:frame.floatValues)floats.put(VmHardware.real(value));}publish(VmHardware.object("event","additional_info","sensor",id(frame.sensor),"type",frame.type,"serial",frame.serial,"int_values",ints==null?JSONObject.NULL:ints,"float_values",floats==null?JSONObject.NULL:floats));}catch(Exception error){emit(error(error));}}}
        }
        Subscription(VmHardware.Context c,Sensor s,int period,int latency)throws Exception{
            super(c,"sensors","sensor");manager=manager(c);sensor=s;
            dynamic=s.isDynamicSensor()?new SensorManager.DynamicSensorCallback(){public void onDynamicSensorDisconnected(Sensor removed){if(id(sensor).equals(id(removed)))try{close();}catch(IOException ignored){}}}:null;
            try{configure(period,latency);if(dynamic!=null)manager.registerDynamicSensorCallback(dynamic,events());}catch(Exception error){close();throw error;}
        }
        synchronized void configure(int period,int latency)throws Exception{
            check();if(pending!=0)throw new VmHardware.Failure("busy","Wait for the pending sensor flush before reconfiguring.");
            Listener old=callback;callback=null;
            try{if(old!=null)manager.unregisterListener(old);}catch(Exception error){callback=old;close();throw error;}
            callback=new Listener(++configuration);
            try{if(!manager.registerListener(callback,sensor,period,latency,events()))throw new VmHardware.Failure("unavailable","Android refused the sensor configuration; reopen the subscription.");this.period=period;this.latency=latency;}catch(Exception error){close();throw error;}
        }
        synchronized long flush(int milliseconds)throws Exception{
            check();if(pending!=0)throw new VmHardware.Failure("busy","Only one flush may be pending for this sensor listener.");long request=++sequence;pending=request;flushDeadline=SystemClock.elapsedRealtime()+milliseconds;
            try{timeout=TIMERS.schedule(()->expire(request),milliseconds,TimeUnit.MILLISECONDS);if(!manager.flush(callback))throw new VmHardware.Failure("unavailable","Android did not initiate the sensor flush.");return request;}catch(Exception error){close();throw error;}
        }
        synchronized void expire(long request){if(closed||pending!=request)return;try{close();}catch(IOException ignored){}}
        synchronized void completed(Listener listener,Sensor source){if(closed||pending==0||callback!=listener||!id(sensor).equals(id(source)))return;if(SystemClock.elapsedRealtime()>=flushDeadline){expire(pending);return;}long request=pending;pending=0;lastCompleted=request;if(timeout!=null)timeout.cancel(false);timeout=null;try{emit(VmHardware.object("event","flush_complete","sensor",id(source),"request",request,"configuration",listener.revision));}catch(Exception error){emit(error(error));}}
        void access(VmHardware.Context c)throws Exception{super.access(c);if(!granted(c,sensor)){close();throw new VmHardware.Failure("permission_revoked","Sensor permission was revoked. Reopen the sensor after granting access.");}}
        synchronized Object info()throws Exception{check();return ((JSONObject)HardwareSensors.info(sensor)).put("kind",kind).put("period_us",period).put("max_report_latency_us",latency).put("configuration",configuration).put("flush_pending",pending==0?JSONObject.NULL:pending).put("last_flush_completed",lastCompleted==0?JSONObject.NULL:lastCompleted);}
        public synchronized void close()throws IOException{if(closed)return;super.close();pending=0;if(timeout!=null)timeout.cancel(false);timeout=null;Listener old=callback;callback=null;try{if(old!=null)manager.unregisterListener(old);}finally{if(dynamic!=null)manager.unregisterDynamicSensorCallback(dynamic);}}
    }
    static final class Watch extends VmHardware.Handle {
        final SensorManager manager;final SensorManager.DynamicSensorCallback callback;
        Watch(VmHardware.Context c)throws Exception{super(c,"sensors","sensor_devices");manager=manager(c);if(!manager.isDynamicSensorDiscoverySupported())throw new VmHardware.Failure("unsupported_operation","Android reports no dynamic sensor discovery support.");callback=new SensorManager.DynamicSensorCallback(){public void onDynamicSensorConnected(Sensor sensor){event("connected",sensor);}public void onDynamicSensorDisconnected(Sensor sensor){event("disconnected",sensor);}};try{manager.registerDynamicSensorCallback(callback,events());}catch(Exception error){manager.unregisterDynamicSensorCallback(callback);throw error;}}
        void event(String type,Sensor sensor){try{emit(VmHardware.object("event",type,"sensor",HardwareSensors.info(sensor)));}catch(Exception error){emit(error(error));}}
        public synchronized void close()throws IOException{if(closed)return;super.close();manager.unregisterDynamicSensorCallback(callback);}
    }
    static final class Trigger extends VmHardware.Handle {
        final SensorManager manager;final Sensor sensor;final TriggerEventListener listener;final SensorManager.DynamicSensorCallback dynamic;volatile boolean armed=true;
        Trigger(VmHardware.Context c,Sensor sensor)throws Exception{
            super(c,"sensors","sensor_trigger");manager=manager(c);this.sensor=sensor;
            listener=new TriggerEventListener(){public void onTrigger(TriggerEvent event){synchronized(Trigger.this){if(closed||!armed)return;armed=false;try{emit(sample(event.sensor,event.timestamp,0,event.values));}catch(Exception error){emit(error(error));}}}};
            dynamic=sensor.isDynamicSensor()?new SensorManager.DynamicSensorCallback(){public void onDynamicSensorDisconnected(Sensor removed){if(id(sensor).equals(id(removed)))try{close();}catch(IOException ignored){}}}:null;
            try{if(!manager.requestTriggerSensor(listener,sensor))throw new VmHardware.Failure("unavailable","Android refused this trigger sensor.");if(dynamic!=null)manager.registerDynamicSensorCallback(dynamic,events());}catch(Exception error){close();throw error;}
        }
        void access(VmHardware.Context c)throws Exception{super.access(c);if(!granted(c,sensor)){close();throw new VmHardware.Failure("permission_revoked","Sensor permission was revoked. Reopen the sensor after granting access.");}}
        Object info()throws Exception{check();return ((JSONObject)HardwareSensors.info(sensor)).put("kind",kind).put("armed",armed);}
        public synchronized void close()throws IOException{if(closed)return;super.close();armed=false;try{manager.cancelTriggerSensor(listener,sensor);}finally{if(dynamic!=null)manager.unregisterDynamicSensorCallback(dynamic);}}
    }
    private static JSONObject error(Exception e){try{return VmHardware.object("event","error","message",MainActivity.safe(e));}catch(Exception impossible){return new JSONObject();}}
    static Object call(VmHardware.Context c,String op,JSONArray args)throws Exception{
        if(op.equals("sensor_list")){
            if(args.length()!=0 && args.length()!=2)throw new VmHardware.Failure("invalid_argument","Use no sensor-list arguments or an offset and page limit.");
            int offset=args.length()==0?0:VmHardware.integer(args,0,0,100000),limit=args.length()==0?16:VmHardware.integer(args,1,1,32);java.util.List<Sensor> list=sensors(c);JSONArray out=new JSONArray();int end=Math.min(list.size(),offset+limit);for(int i=offset;i<end;i++)out.put(info(list.get(i)));return VmHardware.object("sensors",out,"next",end<list.size()?end:-1,"total",list.size());
        }
        if(op.equals("sensor_watch"))return VmHardware.add(new Watch(c));
        if(op.equals("sensor_configure")||op.equals("sensor_flush")){Subscription owned=VmHardware.handle(c,VmHardware.text(args,0,128),Subscription.class);owned.access(c);VmHardware.blocking(owned);try{if(op.equals("sensor_flush"))return owned.flush(VmHardware.integer(args,1,1,8000));owned.configure(VmHardware.integer(args,1,5000,1000000),VmHardware.integer(args,2,0,60000000));return 1;}finally{VmHardware.unblocking();}}
        Sensor sensor=sensor(c,VmHardware.text(args,0,128));if(op.equals("sensor_info"))return info(sensor);
        int period=VmHardware.integer(args,1,5000,1000000),latency=op.equals("sensor_batch_open")?VmHardware.integer(args,2,0,60000000):0;boolean trigger=sensor.getReportingMode()==Sensor.REPORTING_MODE_ONE_SHOT;if(trigger&&latency!=0)throw new VmHardware.Failure("unsupported_operation","One-shot trigger sensors cannot batch reports.");permission(c,sensor);
        return VmHardware.add(trigger?new Trigger(c,sensor):new Subscription(c,sensor,period,latency));
    }
}
