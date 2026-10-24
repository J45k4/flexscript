package org.flexscript.collie;

import android.content.*;
import android.hardware.ConsumerIrManager;
import android.os.*;
import java.io.IOException;
import org.json.*;

/** Battery/thermal service data and supported haptic/IR actuators. */
final class HardwareStatus {
    static boolean supports(String op){return op.startsWith("battery_")||op.startsWith("thermal_")||op.startsWith("haptic_")||op.startsWith("ir_");}
    private static Context app(VmHardware.Context c){return c.host.getApplicationContext();}
    private static BatteryManager battery(VmHardware.Context c){return (BatteryManager)app(c).getSystemService(Context.BATTERY_SERVICE);}
    private static PowerManager power(VmHardware.Context c){return (PowerManager)app(c).getSystemService(Context.POWER_SERVICE);}
    private static Vibrator vibrator(VmHardware.Context c){return (Vibrator)app(c).getSystemService(Context.VIBRATOR_SERVICE);}
    private static ConsumerIrManager infrared(VmHardware.Context c){return (ConsumerIrManager)app(c).getSystemService(Context.CONSUMER_IR_SERVICE);}
    private static Object property(BatteryManager b,int key){int value=b.getIntProperty(key);return value==Integer.MIN_VALUE?JSONObject.NULL:value;}
    static Object batteryInfo(VmHardware.Context c)throws Exception{
        Intent state=app(c).registerReceiver(null,new IntentFilter(Intent.ACTION_BATTERY_CHANGED));BatteryManager b=battery(c);
        if(state==null)throw new VmHardware.Failure("unavailable","Battery status is unavailable.");
        return VmHardware.object("level",state.getIntExtra(BatteryManager.EXTRA_LEVEL,-1),"scale",state.getIntExtra(BatteryManager.EXTRA_SCALE,-1),"status",state.getIntExtra(BatteryManager.EXTRA_STATUS,-1),"plugged",state.getIntExtra(BatteryManager.EXTRA_PLUGGED,0),"health",state.getIntExtra(BatteryManager.EXTRA_HEALTH,-1),"present",state.getBooleanExtra(BatteryManager.EXTRA_PRESENT,false),"voltage_mv",state.hasExtra(BatteryManager.EXTRA_VOLTAGE)?state.getIntExtra(BatteryManager.EXTRA_VOLTAGE,0):JSONObject.NULL,"temperature_c",state.hasExtra(BatteryManager.EXTRA_TEMPERATURE)?VmHardware.real(state.getIntExtra(BatteryManager.EXTRA_TEMPERATURE,0)/10.0):JSONObject.NULL,"charging",b.isCharging(),"current_ua",property(b,BatteryManager.BATTERY_PROPERTY_CURRENT_NOW),"average_current_ua",property(b,BatteryManager.BATTERY_PROPERTY_CURRENT_AVERAGE),"charge_uah",property(b,BatteryManager.BATTERY_PROPERTY_CHARGE_COUNTER));
    }
    static final class BatteryWatch extends VmHardware.Handle {
        final Context app;final BroadcastReceiver receiver;
        BatteryWatch(VmHardware.Context c)throws Exception{
            super(c,"device_status","battery");app=app(c);receiver=new BroadcastReceiver(){public void onReceive(Context unused,Intent intent){try{emit(VmHardware.object("event","battery","value",batteryInfo(c)));}catch(Exception ignored){}}};
            if(Build.VERSION.SDK_INT>=33)app.registerReceiver(receiver,new IntentFilter(Intent.ACTION_BATTERY_CHANGED),Context.RECEIVER_NOT_EXPORTED);else app.registerReceiver(receiver,new IntentFilter(Intent.ACTION_BATTERY_CHANGED));
            emit(VmHardware.object("event","battery","value",batteryInfo(c)));
        }
        public synchronized void close()throws IOException{if(closed)return;super.close();app.unregisterReceiver(receiver);}
    }
    static final class ThermalWatch extends VmHardware.Handle {
        final PowerManager power;final PowerManager.OnThermalStatusChangedListener listener;
        ThermalWatch(VmHardware.Context c)throws Exception{
            super(c,"device_status","thermal");power=power(c);listener=status->{try{emit(VmHardware.object("event","thermal","status",status));}catch(Exception ignored){}};
            power.addThermalStatusListener(command->HardwareSensors.events().post(command),listener);emit(VmHardware.object("event","thermal","status",power.getCurrentThermalStatus()));
        }
        public synchronized void close()throws IOException{if(closed)return;super.close();power.removeThermalStatusListener(listener);}
    }
    static final class Haptic extends VmHardware.Handle {
        final Vibrator vibrator;
        Haptic(VmHardware.Context c,VibrationEffect effect)throws Exception{super(c,"haptics","haptic");vibrator=vibrator(c);vibrator.vibrate(effect);}
        public synchronized void close()throws IOException{if(closed)return;super.close();vibrator.cancel();}
    }
    static void capabilities(VmHardware.Context c,JSONArray out)throws Exception{
        out.put(VmHardware.capability("battery",true,true,"device_status"));out.put(VmHardware.capability("thermal",Build.VERSION.SDK_INT>=29,Build.VERSION.SDK_INT>=29,"device_status"));
        Vibrator v=vibrator(c);out.put(VmHardware.capability("haptics",v!=null&&v.hasVibrator(),v!=null&&v.hasVibrator(),"haptics"));ConsumerIrManager ir=infrared(c);out.put(VmHardware.capability("infrared",ir!=null&&ir.hasIrEmitter(),ir!=null&&ir.hasIrEmitter(),"infrared"));
    }
    static Object call(VmHardware.Context c,String op,JSONArray a)throws Exception{
        switch(op){
        case "battery_info":return batteryInfo(c);
        case "battery_watch":return VmHardware.add(new BatteryWatch(c));
        case "thermal_info":{
            if(Build.VERSION.SDK_INT<29)throw new VmHardware.Failure("unsupported","Thermal status needs Android 10 or newer.");int forecast=VmHardware.integer(a,0,0,60);Object headroom=JSONObject.NULL;
            if(Build.VERSION.SDK_INT>=30){float value=power(c).getThermalHeadroom(forecast);if(!Float.isNaN(value))headroom=VmHardware.real(value);}
            return VmHardware.object("status",power(c).getCurrentThermalStatus(),"headroom",headroom,"forecast_seconds",forecast);
        }
        case "thermal_watch":if(Build.VERSION.SDK_INT<29)throw new VmHardware.Failure("unsupported","Thermal events need Android 10 or newer.");return VmHardware.add(new ThermalWatch(c));
        case "haptic_info":{Vibrator v=vibrator(c);return VmHardware.object("present",v!=null&&v.hasVibrator(),"amplitude_control",v!=null&&v.hasAmplitudeControl());}
        case "haptic_play":{
            Vibrator v=vibrator(c);if(v==null||!v.hasVibrator())throw new VmHardware.Failure("unsupported","This device has no vibration actuator.");
            return VmHardware.add(new Haptic(c,VibrationEffect.createOneShot(VmHardware.integer(a,0,1,2000),VmHardware.integer(a,1,-1,255))));
        }
        case "haptic_waveform":{
            Vibrator v=vibrator(c);if(v==null||!v.hasVibrator())throw new VmHardware.Failure("unsupported","This device has no vibration actuator.");
            JSONArray pattern=a.getJSONArray(0),amplitudes=a.getJSONArray(1);if(pattern.length()<1||pattern.length()>64||pattern.length()!=amplitudes.length())throw new VmHardware.Failure("invalid_argument","Use 1..64 matching timing and amplitude values.");
            long[] timing=new long[pattern.length()];int[] strength=new int[pattern.length()];long total=0;
            for(int i=0;i<timing.length;i++){timing[i]=VmHardware.integer(pattern,i,0,2000);strength[i]=VmHardware.integer(amplitudes,i,-1,255);total+=timing[i];}if(total<1||total>2000)throw new VmHardware.Failure("invalid_argument","Vibration patterns must last 1..2000 ms.");
            return VmHardware.add(new Haptic(c,VibrationEffect.createWaveform(timing,strength,-1)));
        }
        case "ir_info":{
            ConsumerIrManager ir=infrared(c);boolean present=ir!=null&&ir.hasIrEmitter();JSONArray ranges=new JSONArray();if(present){ConsumerIrManager.CarrierFrequencyRange[] list=ir.getCarrierFrequencies();if(list!=null)for(ConsumerIrManager.CarrierFrequencyRange range:list)ranges.put(VmHardware.object("minimum_hz",range.getMinFrequency(),"maximum_hz",range.getMaxFrequency()));}return VmHardware.object("present",present,"carrier_ranges",ranges);
        }
        case "ir_transmit":{
            ConsumerIrManager ir=infrared(c);if(ir==null||!ir.hasIrEmitter())throw new VmHardware.Failure("unsupported","This device has no consumer infrared emitter.");int frequency=VmHardware.integer(a,0,1,1000000);JSONArray pattern=a.getJSONArray(1);if(pattern.length()<1||pattern.length()>1024)throw new VmHardware.Failure("invalid_argument","IR patterns require 1..1024 pulse durations.");int[] pulses=new int[pattern.length()];long total=0;for(int i=0;i<pulses.length;i++){pulses[i]=VmHardware.integer(pattern,i,1,1999999);total+=pulses[i];}if(total>=2000000)throw new VmHardware.Failure("invalid_argument","IR patterns must be shorter than 2 seconds.");ir.transmit(frequency,pulses);return 1;
        }
        default:throw new VmHardware.Failure("unsupported_operation","Unknown device status operation.");
        }
    }
}
