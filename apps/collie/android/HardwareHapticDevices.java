package org.flexscript.collie;

import android.content.Context;
import android.os.*;
import java.util.HashSet;
import org.json.*;

/** Public actuator IDs and parallel graphs, sharing the app-wide playback lease. */
final class HardwareHapticDevices {
    static boolean supports(String op){return op.equals("haptic_actuators")||op.equals("haptic_actuator_info")||op.equals("haptic_actuator_frequency_profile")||op.equals("haptic_actuator_frequency_response")||op.equals("haptic_actuator_frequency_range")||op.equals("haptic_render");}
    static Object call(VmHardware.Context c,String op,JSONArray a)throws Exception{if(Build.VERSION.SDK_INT<31)throw new VmHardware.Failure("unsupported_operation","Actuator selection and parallel effects require Android12+.");return Api31.call(c,op,a);}
    static final class Api31 {
        static VibratorManager manager(VmHardware.Context c)throws Exception{VibratorManager m=(VibratorManager)c.host.getApplicationContext().getSystemService(Context.VIBRATOR_MANAGER_SERVICE);if(m==null)throw new VmHardware.Failure("unsupported","Android exposes no vibrator manager.");return m;}
        static Vibrator selected(VibratorManager manager,int[] ids,int id)throws Exception{boolean found=false;for(int value:ids)if(value==id)found=true;if(!found)throw new VmHardware.Failure("invalid_argument","Select an actuator ID from the actual Android inventory.");Vibrator v=manager.getVibrator(id);if(!v.hasVibrator()||v.getId()!=id)throw new VmHardware.Failure("disconnected","The selected actuator is no longer available.");return v;}
        static Object call(VmHardware.Context c,String op,JSONArray a)throws Exception{
            VibratorManager manager=manager(c);int[] ids=manager.getVibratorIds();
            if(op.equals("haptic_actuators")){int offset=VmHardware.integer(a,0,0,Integer.MAX_VALUE),limit=VmHardware.integer(a,1,1,16);JSONArray rows=new JSONArray();for(int i=offset;i<ids.length&&i-offset<limit;i++){Vibrator v=manager.getVibrator(ids[i]);rows.put(VmHardware.object("id",ids[i],"present",v.hasVibrator(),"amplitude_control",v.hasAmplitudeControl()));}return VmHardware.object("actuators",rows,"offset",offset,"count",ids.length,"next",offset<ids.length?offset+rows.length():offset,"complete",offset>=ids.length||rows.length()==ids.length-offset,"maximum_targets",8);}
            if(op.equals("haptic_render"))return render(c,manager,ids,a);
            int id=VmHardware.integer(a,0,Integer.MIN_VALUE,Integer.MAX_VALUE);Vibrator v=selected(manager,ids,id);
            if(op.equals("haptic_actuator_info"))return VmHardware.object("id",v.getId(),"haptics",HardwareHaptics.metadata(v,"haptic_info"),"effects",HardwareHaptics.metadata(v,"haptic_effects"),"primitives",HardwareHaptics.metadata(v,"haptic_primitives"),"envelope",HardwareHapticEnvelope.call(c,v,"haptic_envelope_info",new JSONArray()));
            JSONArray args=new JSONArray();for(int i=1;i<a.length();i++)args.put(a.get(i));String query=op.equals("haptic_actuator_frequency_profile")?"haptic_frequency_profile":op.equals("haptic_actuator_frequency_response")?"haptic_frequency_response":"haptic_frequency_range";return HardwareHapticEnvelope.call(c,v,query,args);
        }
        static HardwareHaptics.Prepared effect(Vibrator sdk,JSONArray record,int limit)throws Exception{
            String type=record.getString(0),op;int fields;boolean wall;
            switch(type){case "one_shot":op="haptic_play";fields=3;wall=false;break;case "waveform":op="haptic_waveform";fields=3;wall=false;break;case "predefined":op="haptic_effect";fields=2;wall=true;break;case "composition":op="haptic_compose";fields=2;wall=true;break;case "basic_envelope":op="haptic_envelope_basic";fields=3;wall=true;break;case "waveform_envelope":op="haptic_envelope_waveform";fields=3;wall=true;break;default:throw new VmHardware.Failure("invalid_argument","Unknown haptic effect record; use the portable haptic factories.");}
            if(record.length()!=fields)throw new VmHardware.Failure("invalid_argument","Haptic effect record has the wrong number of fields.");JSONArray args=new JSONArray();for(int i=1;i<fields;i++)args.put(record.get(i));if(wall)args.put(limit);return HardwareHaptics.prepare(sdk,op,args);
        }
        static Object render(VmHardware.Context c,VibratorManager manager,int[] ids,JSONArray a)throws Exception{
            int limit=VmHardware.integer(a,1,1,2000);JSONArray targets=a.getJSONArray(0);if(targets.length()<1||targets.length()>8)throw new VmHardware.Failure("invalid_argument","Render1..8 distinct actuator targets.");
            int[] selected=new int[targets.length()];Vibrator[] sdk=new Vibrator[targets.length()];HashSet<Integer> unique=new HashSet<>();
            for(int i=0;i<selected.length;i++){JSONArray target=targets.getJSONArray(i);if(target.length()!=2)throw new VmHardware.Failure("invalid_argument","A target is[actuator_id,effect_record].");selected[i]=VmHardware.integer(target,0,Integer.MIN_VALUE,Integer.MAX_VALUE);if(!unique.add(selected[i]))throw new VmHardware.Failure("invalid_argument","An actuator may appear only once in a parallel graph.");sdk[i]=selected(manager,ids,selected[i]);}
            HardwareHaptics.Prepared[] prepared=new HardwareHaptics.Prepared[selected.length];for(int i=0;i<selected.length;i++)prepared[i]=effect(sdk[i],targets.getJSONArray(i).getJSONArray(1),limit);
            CombinedVibration.ParallelCombination builder=CombinedVibration.startParallel();for(int i=0;i<selected.length;i++)builder.addVibrator(selected[i],prepared[i].effect);Parallel playback=new Parallel(manager,builder.combine());
            JSONObject requested=VmHardware.object("type","parallel","targets",targets,"target_count",targets.length(),"common_duration_limit_ms",limit);return VmHardware.add(new HardwareHaptics.Haptic(c,null,null,requested,limit,playback));
        }
        static final class Parallel implements HardwareHaptics.Playback {
            final VibratorManager manager;final CombinedVibration effect;
            Parallel(VibratorManager manager,CombinedVibration effect){this.manager=manager;this.effect=effect;}
            public void play(){manager.vibrate(effect);}
            public void cancel(){manager.cancel();}
        }
    }
}
