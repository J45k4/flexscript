package org.flexscript.collie;

import android.os.*;
import android.os.vibrator.VibratorEnvelopeEffectInfo;
import android.os.vibrator.VibratorFrequencyProfile;
import android.util.Range;
import android.util.SparseArray;
import org.json.*;

/** Public SDK envelope builders and copied frequency metadata. No fallback effects. */
final class HardwareHapticEnvelope {
    static float number(Object value,boolean positive)throws Exception{
        double n;
        if(value instanceof JSONObject&&((JSONObject)value).length()==1&&((JSONObject)value).has("$real"))n=Double.longBitsToDouble(VmHardware.longInteger(new JSONArray().put(((JSONObject)value).get("$real")),0,Long.MIN_VALUE,Long.MAX_VALUE));
        else if(value instanceof Integer||value instanceof Long)n=((Number)value).doubleValue();
        else throw new VmHardware.Failure("invalid_argument","Use a typed integer or real for haptic measurements.");
        float f=(float)n;
        if(!Double.isFinite(n)||n<0||!Float.isFinite(f)||(positive&&f<=0)||(n>0&&f==0))throw new VmHardware.Failure("invalid_argument","Haptic measurements must be finite, nonnegative and representable by the public SDK; frequency must be positive.");
        return f;
    }
    static Object known(float value)throws Exception{return Float.isNaN(value)?JSONObject.NULL:VmHardware.real(value);}
    static Object call(VmHardware.Context c,String op,JSONArray a)throws Exception{
        return call(c,HardwareHaptics.vibrator(c),op,a);
    }
    static HardwareHaptics.Prepared prepare(Vibrator sdk,String op,JSONArray a)throws Exception{if(Build.VERSION.SDK_INT<36)throw new VmHardware.Failure("unsupported_operation","Envelope effects require Android16+.");return Api36.prepare(sdk,op,a);}
    static Object call(VmHardware.Context c,Vibrator v,String op,JSONArray a)throws Exception{
        if(op.equals("haptic_envelope_info")){
            boolean present=v!=null&&v.hasVibrator();
            return VmHardware.object("present",present,"resonance_api",Build.VERSION.SDK_INT>=34,"resonant_frequency_hz",present&&Build.VERSION.SDK_INT>=34?Api34.resonance(v):JSONObject.NULL,"q_factor",present&&Build.VERSION.SDK_INT>=34?Api34.q(v):JSONObject.NULL,"envelope_api",Build.VERSION.SDK_INT>=36,"envelopes_supported",present&&Build.VERSION.SDK_INT>=36?Api36.supported(v):JSONObject.NULL,"envelope_limits",present&&Build.VERSION.SDK_INT>=36?Api36.limits(v):JSONObject.NULL,"frequency_profile",present&&Build.VERSION.SDK_INT>=36?Api36.profile(v):JSONObject.NULL,"maximum_points",32,"maximum_duration_ms",2000);
        }
        if(Build.VERSION.SDK_INT<36)throw new VmHardware.Failure("unsupported_operation","Envelope effects and frequency profiles require Android16+.");
        return Api36.call(c,HardwareHaptics.present(v),op,a);
    }
    static final class Api34 {
        static Object resonance(Vibrator v)throws Exception{return known(v.getResonantFrequency());}
        static Object q(Vibrator v)throws Exception{return known(v.getQFactor());}
    }
    static final class Api36 {
        static boolean supported(Vibrator v){return v.areEnvelopeEffectsSupported();}
        static Object limits(Vibrator v)throws Exception{VibratorEnvelopeEffectInfo e=v.getEnvelopeEffectInfo();return e==null?JSONObject.NULL:VmHardware.object("maximum_size",e.getMaxSize(),"minimum_point_duration_ms",e.getMinControlPointDurationMillis(),"maximum_point_duration_ms",e.getMaxControlPointDurationMillis(),"maximum_duration_ms",e.getMaxDurationMillis());}
        static Object profile(Vibrator v)throws Exception{VibratorFrequencyProfile f=v.getFrequencyProfile();return f==null?JSONObject.NULL:VmHardware.object("minimum_frequency_hz",VmHardware.real(f.getMinFrequencyHz()),"maximum_frequency_hz",VmHardware.real(f.getMaxFrequencyHz()),"maximum_acceleration_g",VmHardware.real(f.getMaxOutputAccelerationGs()),"count",f.getFrequenciesOutputAcceleration().size());}
        static VibratorFrequencyProfile frequency(Vibrator v)throws Exception{VibratorFrequencyProfile f=v.getFrequencyProfile();if(f==null)throw new VmHardware.Failure("unsupported_combination","This vibrator exposes no frequency profile.");return f;}
        static float hz(Object value,VibratorFrequencyProfile f)throws Exception{float n=number(value,true);if(n<f.getMinFrequencyHz()||n>f.getMaxFrequencyHz())throw new VmHardware.Failure("unsupported_combination","Requested frequency is outside the actual SDK profile; no fallback is substituted.");return n;}
        static Object call(VmHardware.Context c,Vibrator v,String op,JSONArray a)throws Exception{
            if(op.equals("haptic_frequency_profile")){
                int offset=VmHardware.integer(a,0,0,Integer.MAX_VALUE),limit=VmHardware.integer(a,1,1,16);SparseArray<Float> values=frequency(v).getFrequenciesOutputAcceleration();JSONArray rows=new JSONArray();int count=values.size();for(int i=offset;i<count&&i-offset<limit;i++)rows.put(VmHardware.object("frequency_hz",values.keyAt(i),"maximum_acceleration_g",VmHardware.real(values.valueAt(i))));return VmHardware.object("points",rows,"offset",offset,"count",count,"next",offset<count?offset+rows.length():offset,"complete",offset>=count||rows.length()==count-offset);
            }
            if(op.equals("haptic_frequency_response")){float value=number(a.get(0),true);return VmHardware.object("requested_frequency_hz",a.get(0),"sdk_frequency_hz",VmHardware.real(value),"output_acceleration_g",VmHardware.real(frequency(v).getOutputAccelerationGs(value)));}
            if(op.equals("haptic_frequency_range")){float value=number(a.get(0),false);Range<Float> r=frequency(v).getFrequencyRange(value);return VmHardware.object("requested_minimum_acceleration_g",a.get(0),"sdk_minimum_acceleration_g",VmHardware.real(value),"range",r==null?JSONObject.NULL:VmHardware.object("minimum_hz",VmHardware.real(r.getLower()),"maximum_hz",VmHardware.real(r.getUpper())));}
            HardwareHaptics.Prepared p=prepare(v,op,a);return HardwareHaptics.start(c,v,p.effect,p.requested,p.duration);
        }
        static HardwareHaptics.Prepared prepare(Vibrator v,String op,JSONArray a)throws Exception{
            boolean basic=op.equals("haptic_envelope_basic");if(!basic&&!op.equals("haptic_envelope_waveform"))throw new VmHardware.Failure("unsupported_operation","Unknown envelope operation.");
            int limit=VmHardware.integer(a,2,1,2000);JSONArray points=a.getJSONArray(1);if(points.length()<1||points.length()>32)throw new VmHardware.Failure("invalid_argument","Use1..32 envelope points.");
            if(!v.areEnvelopeEffectsSupported())throw new VmHardware.Failure("unsupported_combination","This vibrator does not support public envelope effects.");
            VibratorEnvelopeEffectInfo bounds=v.getEnvelopeEffectInfo();if(bounds==null)throw new VmHardware.Failure("unsupported_combination","The SDK exposes no envelope limits.");
            VibratorFrequencyProfile f=basic?null:frequency(v);float initial=basic?(float)HardwareHaptics.scale(a.get(0)):hz(a.get(0),f);VibrationEffect.BasicEnvelopeBuilder b=basic?new VibrationEffect.BasicEnvelopeBuilder().setInitialSharpness(initial):null;VibrationEffect.WaveformEnvelopeBuilder w=basic?null:new VibrationEffect.WaveformEnvelopeBuilder().setInitialFrequencyHz(initial);int total=0;
            for(int i=0;i<points.length();i++){
                JSONArray row=points.getJSONArray(i);if(row.length()!=3)throw new VmHardware.Failure("invalid_argument","An envelope point is[typed strength,typed sharpness/frequency,duration_ms].");float strength=(float)HardwareHaptics.scale(row.get(0)),target=basic?(float)HardwareHaptics.scale(row.get(1)):hz(row.get(1),f);int duration=VmHardware.integer(row,2,1,2000);total+=duration;
                if(total>2000)throw new VmHardware.Failure("invalid_argument","Envelope points exceed2000ms.");
                if(duration<bounds.getMinControlPointDurationMillis()||duration>bounds.getMaxControlPointDurationMillis()||total>bounds.getMaxDurationMillis())throw new VmHardware.Failure("unsupported_combination","Envelope timing exceeds the actual SDK limits.");
                if(basic){if(i==points.length()-1&&HardwareHaptics.scale(row.get(0))!=0)throw new VmHardware.Failure("invalid_argument","A basic envelope must end at zero intensity.");b.addControlPoint(strength,target,duration);}else w.addControlPoint(strength,target,duration);
            }
            VibrationEffect effect=basic?b.build():w.build();return new HardwareHaptics.Prepared(effect,VmHardware.object("type",basic?"basic_envelope":"waveform_envelope","initial",a.get(0),"points",points,"requested_duration_ms",total),limit);
        }
    }
}
