package org.flexscript.collie;

import android.content.Context;
import android.os.*;
import java.io.IOException;
import java.util.concurrent.*;
import org.json.*;

/** One owned app-vibrator token, retained through real SDK cancellation. */
final class HardwareHaptics {
    static final Object LOCK=new Object();
    static Haptic owner;
    static final ExecutorService CLEANUP=new ThreadPoolExecutor(1,1,0,TimeUnit.SECONDS,new ArrayBlockingQueue<Runnable>(1),task->{Thread t=new Thread(task,"collie-haptic-close");t.setDaemon(true);return t;});
    // One app-wide owner bounds this queue to its deadline and cleanup retry.
    static final ScheduledThreadPoolExecutor TIMERS=timers();
    static ScheduledThreadPoolExecutor timers(){ScheduledThreadPoolExecutor pool=new ScheduledThreadPoolExecutor(1,task->{Thread t=new Thread(task,"collie-haptic-deadline");t.setDaemon(true);return t;});pool.setRemoveOnCancelPolicy(true);return pool;}
    static final int[] EFFECTS={0,1,2,5},PRIMITIVES={1,2,3,4,5,6,7,8};
    static Vibrator vibrator(VmHardware.Context c){return (Vibrator)c.host.getApplicationContext().getSystemService(Context.VIBRATOR_SERVICE);}
    static void visible(VmHardware.Context c)throws Exception{if(!c.host.hardwareVisible)throw new VmHardware.Failure("foreground_required","Haptic playback requires a visible Collie Activity.");}
    static Vibrator present(VmHardware.Context c)throws Exception{return present(vibrator(c));}
    static Vibrator present(Vibrator v)throws Exception{if(v==null||!v.hasVibrator())throw new VmHardware.Failure("unsupported","This device has no vibration actuator.");return v;}
    static boolean busy(){synchronized(LOCK){return owner!=null;}}
    static void hidden(){Haptic h;synchronized(LOCK){h=owner;}if(h!=null)h.close();}
    static Object info(VmHardware.Context c)throws Exception{return info(vibrator(c));}
    static Object info(Vibrator v)throws Exception{return VmHardware.object("present",v!=null&&v.hasVibrator(),"amplitude_control",v!=null&&v.hasAmplitudeControl(),"predefined_api",Build.VERSION.SDK_INT>=29,"support_api",Build.VERSION.SDK_INT>=30,"primitive_duration_api",Build.VERSION.SDK_INT>=31,"individual_primitive_support_known",Build.VERSION.SDK_INT>=31,"foreground_required",true,"busy",busy(),"maximum_duration_ms",2000);}
    interface Playback {void play();void cancel();}
    static final class Prepared {
        final VibrationEffect effect;final JSONObject requested;final int duration;
        Prepared(VibrationEffect effect,JSONObject requested,int duration){this.effect=effect;this.requested=requested;this.duration=duration;}
    }
    static double scale(Object value)throws Exception{double n;if(value instanceof JSONObject&&((JSONObject)value).length()==1&&((JSONObject)value).has("$real"))n=Double.longBitsToDouble(VmHardware.longInteger(new JSONArray().put(((JSONObject)value).get("$real")),0,Long.MIN_VALUE,Long.MAX_VALUE));else if(value instanceof Integer||value instanceof Long)n=((Number)value).doubleValue();else throw new VmHardware.Failure("invalid_argument","Primitive scale uses a typed integer or real.");if(!Double.isFinite(n)||n<0||n>1)throw new VmHardware.Failure("invalid_argument","Primitive scale must be finite and0..1.");return n;}
    static final class Haptic extends VmHardware.Handle {
        final Vibrator sdk;final VibrationEffect effect;final Playback playback;final JSONObject requested;final int duration;final Runnable timer=this::expired,retry=()->requestStop("cleanup_retry");
        ScheduledFuture<?> deadlineTask,retryTask;
        boolean starting=true,attempted,submitted,stopRequested,cancelQueued,cancelReturned,released;long deadline,stopAt;String state="starting",error="",stopReason="";
        Haptic(VmHardware.Context c,Vibrator v,VibrationEffect effect,JSONObject requested,int duration)throws Exception{
            this(c,v,effect,requested,duration,null);
        }
        Haptic(VmHardware.Context c,Vibrator v,VibrationEffect effect,JSONObject requested,int duration,Playback playback)throws Exception{
            super(c,"haptics","haptic");sdk=v;this.effect=effect;this.playback=playback;this.requested=requested;this.duration=duration;visible(c);synchronized(LOCK){if(owner!=null)throw new VmHardware.Failure("busy","The app vibrator is owned or awaiting SDK cancellation. Close/wait for its current handle.");owner=this;}
            VmHardware.blocking(this);try{VmHardware.check();visible(c);synchronized(this){if(closed||stopRequested)throw new VmHardware.Failure("cancelled","Haptic startup was cancelled.");attempted=true;}if(playback==null)sdk.vibrate(effect);else playback.play();synchronized(this){submitted=true;deadline=SystemClock.elapsedRealtime()+duration;state="submitted";try{event("submitted");}catch(Exception ignored){}}visible(c);}
            catch(Exception failure){synchronized(this){error=MainActivity.safe(failure);stopRequested=true;stopReason="startup_failed";}throw failure;}
            finally{synchronized(this){starting=false;if(closed||stopRequested)queueStop();else try{deadlineTask=TIMERS.schedule(timer,Math.max(0,deadline-SystemClock.elapsedRealtime()),TimeUnit.MILLISECONDS);}catch(RejectedExecutionException failure){error=MainActivity.safe(failure);requestStop("deadline_unavailable");}}VmHardware.unblocking();}
        }
        synchronized void event(String name)throws Exception{emit(VmHardware.object("event",name,"sdk_vibrate_returned",submitted,"sdk_cancel_returned",cancelReturned,"lease_released",released,"reason",stopReason,"error",error));}
        synchronized void expired(){if(!released&&submitted&&!stopRequested&&SystemClock.elapsedRealtime()>=deadline)requestStop("wall_deadline");else if(stopRequested&&!released&&!cancelQueued&&!starting)queueStop();}
        synchronized void cancelDeadline(){if(deadlineTask!=null){deadlineTask.cancel(false);deadlineTask=null;}}
        synchronized void cancelRetry(){if(retryTask!=null){retryTask.cancel(false);retryTask=null;}}
        synchronized void retryLater(){cancelRetry();try{retryTask=TIMERS.schedule(retry,250,TimeUnit.MILLISECONDS);}catch(RejectedExecutionException failure){error=MainActivity.safe(failure);state="cleanup_error";}}
        synchronized void requestStop(String reason){if(released)return;if(!stopRequested){stopReason=reason;stopAt=SystemClock.elapsedRealtime();}stopRequested=true;state="stopping";cancelDeadline();if(!starting)queueStop();}
        synchronized void queueStop(){if(released||cancelQueued||starting)return;cancelQueued=true;try{CLEANUP.execute(this::cancelSdk);cancelRetry();}catch(RejectedExecutionException failure){cancelQueued=false;error=MainActivity.safe(failure);retryLater();}}
        void cancelSdk(){
            try{if(attempted){if(playback==null)sdk.cancel();else playback.cancel();}}catch(Exception failure){synchronized(this){cancelQueued=false;error=MainActivity.safe(failure);state="cleanup_error";try{event("cleanup_error");}catch(Exception ignored){}retryLater();}return;}
            synchronized(this){cancelDeadline();cancelRetry();cancelReturned=attempted;released=true;cancelQueued=false;state="stopped";error="";synchronized(LOCK){if(owner==this)owner=null;}try{event("stopped");}catch(Exception ignored){}}
        }
        void access(VmHardware.Context c)throws Exception{super.access(c);expired();}
        synchronized Object info()throws Exception{check();expired();return VmHardware.object("kind",kind,"state",state,"requested",requested,"duration_limit_ms",duration,"sdk_vibrate_called",attempted,"sdk_vibrate_returned",submitted,"sdk_cancel_returned",cancelReturned,"lease_released",released,"wall_deadline_elapsed_ms",deadline==0?JSONObject.NULL:deadline,"stop_requested_elapsed_ms",stopAt==0?JSONObject.NULL:stopAt,"stop_reason",stopReason,"error",error);}
        Object next(int timeout)throws Exception{expired();int wait=timeout;synchronized(this){if(submitted&&!stopRequested)wait=(int)Math.min(timeout,Math.max(0,deadline-SystemClock.elapsedRealtime()));}Object value=super.next(wait);expired();return value;}
        public synchronized void close(){if(!closed)try{super.close();}catch(IOException impossible){throw new IllegalStateException(impossible);}requestStop("closed");}
    }
    static Object start(VmHardware.Context c,Vibrator sdk,VibrationEffect effect,JSONObject requested,int duration)throws Exception{return VmHardware.add(new Haptic(c,sdk,effect,requested,duration));}
    static Object call(VmHardware.Context c,String op,JSONArray a)throws Exception{
        if(HardwareHapticDevices.supports(op))return HardwareHapticDevices.call(c,op,a);
        if(op.startsWith("haptic_envelope_")||op.startsWith("haptic_frequency_"))return HardwareHapticEnvelope.call(c,op,a);
        if(op.equals("haptic_info"))return info(c);Vibrator sdk=present(c);
        if(op.equals("haptic_effects")||op.equals("haptic_primitives"))return metadata(sdk,op);
        Prepared p=prepare(sdk,op,a);return start(c,sdk,p.effect,p.requested,p.duration);
    }
    static Object metadata(Vibrator sdk,String op)throws Exception{
        if(op.equals("haptic_info"))return info(sdk);present(sdk);
        if(op.equals("haptic_effects")){JSONArray rows=new JSONArray();int[] support=Build.VERSION.SDK_INT>=30?Api30.effects(sdk):null;for(int i=0;i<EFFECTS.length;i++)rows.put(VmHardware.object("id",EFFECTS[i],"native_support",support==null?JSONObject.NULL:support[i]));return VmHardware.object("effects",rows,"play_api",Build.VERSION.SDK_INT>=29,"support_api",Build.VERSION.SDK_INT>=30);}
        if(op.equals("haptic_primitives")){JSONArray rows=new JSONArray();boolean[] support=Build.VERSION.SDK_INT>=30?Api30.primitives(sdk):null;int[] duration=Build.VERSION.SDK_INT>=31?Api31.durations(sdk):null;for(int i=0;i<PRIMITIVES.length;i++)rows.put(VmHardware.object("id",PRIMITIVES[i],"supported",support==null?JSONObject.NULL:support[i],"duration_ms",duration==null?JSONObject.NULL:duration[i]));return VmHardware.object("primitives",rows,"composition_api",Build.VERSION.SDK_INT>=30,"individual_support_known",Build.VERSION.SDK_INT>=31,"duration_api",Build.VERSION.SDK_INT>=31);}
        throw new VmHardware.Failure("unsupported_operation","Unknown haptic metadata operation.");
    }
    static Prepared prepare(Vibrator sdk,String op,JSONArray a)throws Exception{
        if(op.equals("haptic_envelope_basic")||op.equals("haptic_envelope_waveform"))return HardwareHapticEnvelope.prepare(sdk,op,a);
        if(op.equals("haptic_play")){int duration=VmHardware.integer(a,0,1,2000),amplitude=VmHardware.integer(a,1,-1,255);return new Prepared(VibrationEffect.createOneShot(duration,amplitude),VmHardware.object("type","one_shot","duration_ms",duration,"amplitude",amplitude),duration);}
        if(op.equals("haptic_waveform")){JSONArray times=a.getJSONArray(0),amplitudes=a.getJSONArray(1);if(times.length()<1||times.length()>64||times.length()!=amplitudes.length())throw new VmHardware.Failure("invalid_argument","Use1..64 matching timing/amplitude values.");long[] timing=new long[times.length()];int[] values=new int[times.length()];int total=0;for(int i=0;i<timing.length;i++){timing[i]=VmHardware.integer(times,i,0,2000);values[i]=VmHardware.integer(amplitudes,i,-1,255);total+=timing[i];}if(total<1||total>2000)throw new VmHardware.Failure("invalid_argument","Waveforms must last1..2000ms.");return new Prepared(VibrationEffect.createWaveform(timing,values,-1),VmHardware.object("type","waveform","timings",times,"amplitudes",amplitudes),total);}
        int limit=VmHardware.integer(a,1,1,2000);
        if(op.equals("haptic_effect")){if(Build.VERSION.SDK_INT<29)throw new VmHardware.Failure("unsupported_operation","Predefined effects require Android10+.");int id=VmHardware.integer(a,0,0,5);if(id==3||id==4)throw new VmHardware.Failure("invalid_argument","Choose public effect0click/1double-click/2tick/5heavy-click.");return new Prepared(Api29.effect(id),VmHardware.object("type","predefined","effect",id),limit);}
        if(!op.equals("haptic_compose"))throw new VmHardware.Failure("unsupported_operation","Unknown haptic operation.");if(Build.VERSION.SDK_INT<30)throw new VmHardware.Failure("unsupported_operation","Primitive composition requires Android11+.");
        JSONArray steps=a.getJSONArray(0);if(steps.length()<1||steps.length()>32)throw new VmHardware.Failure("invalid_argument","Composition requires1..32 primitives.");return new Prepared(Api30.compose(sdk,steps),VmHardware.object("type","composition","steps",steps),limit);
    }
    static final class Api29 {static VibrationEffect effect(int id){return VibrationEffect.createPredefined(id);}}
    static final class Api30 {
        static int[] effects(Vibrator v){return v.areEffectsSupported(EFFECTS);}
        static boolean[] primitives(Vibrator v){return v.arePrimitivesSupported(PRIMITIVES);}
        static VibrationEffect compose(Vibrator sdk,JSONArray steps)throws Exception{VibrationEffect.Composition result=VibrationEffect.startComposition();int[] ids=new int[steps.length()];int total=0;for(int i=0;i<ids.length;i++){JSONArray row=steps.getJSONArray(i);if(row.length()!=3)throw new VmHardware.Failure("invalid_argument","A primitive is[id,typed scale,delay_ms].");ids[i]=VmHardware.integer(row,0,1,8);float amount=(float)scale(row.get(1));int delay=VmHardware.integer(row,2,0,2000);total+=delay;if(total>2000)throw new VmHardware.Failure("invalid_argument","Composition delays exceed2000ms.");result.addPrimitive(ids[i],amount,delay);}if(!sdk.areAllPrimitivesSupported(ids))throw new VmHardware.Failure("unsupported_combination","At least one requested primitive is unsupported; no fallback composition is substituted.");return result.compose();}
    }
    static final class Api31 {static int[] durations(Vibrator v){return v.getPrimitiveDurations(PRIMITIVES);}}
}
