package org.flexscript.collie;

import android.Manifest;
import android.app.KeyguardManager;
import android.content.pm.PackageManager;
import android.hardware.biometrics.*;
import android.os.*;
import java.io.IOException;
import java.util.concurrent.Executor;
import org.json.*;

/** System-owned authentication UI and copied SDK results, never biometric templates. */
final class HardwareBiometrics {
    private static final Object LOCK=new Object();private static Auth owner;
    private static final Executor CALLBACKS=task->HardwareSensors.events().post(task);
    static boolean supports(String op){return op.startsWith("biometric_");}
    static int mask(JSONArray a,int at)throws Exception{
        int value=VmHardware.integer(a,at,1,98559),base=value&~65536;
        if(base!=15&&base!=255&&base!=32768&&base!=32783&&base!=33023)throw new VmHardware.Failure("invalid_argument","Use strong15, weak255, credential32768, or biometric|credential; optionally Identity Check65536 on Android16+.");
        if((value&65536)!=0&&Build.VERSION.SDK_INT<36)throw new VmHardware.Failure("unsupported_operation","Identity Check requires Android16 or newer.");
        return value;
    }
    static void permission(VmHardware.Context c)throws Exception{if(c.host.checkSelfPermission(Manifest.permission.USE_BIOMETRIC)!=PackageManager.PERMISSION_GRANTED)throw new VmHardware.Failure("permission_denied","Android's USE_BIOMETRIC manifest permission is unavailable.");}
    static Object status(VmHardware.Context c,int mask){
        if(Build.VERSION.SDK_INT<29)return JSONObject.NULL;BiometricManager manager=c.host.getSystemService(BiometricManager.class);if(manager==null)return JSONObject.NULL;
        if(Build.VERSION.SDK_INT>=30)return manager.canAuthenticate(mask);return mask==255?manager.canAuthenticate():JSONObject.NULL;
    }
    static JSONObject info(VmHardware.Context c,int mask)throws Exception{
        PackageManager pm=c.host.getPackageManager();KeyguardManager keyguard=c.host.getSystemService(KeyguardManager.class);Object value=status(c,mask);boolean busy;synchronized(LOCK){busy=owner!=null;}
        return VmHardware.object("api_supported",Build.VERSION.SDK_INT>=28,"sdk",Build.VERSION.SDK_INT,"authenticators",mask,"mask_supported",Build.VERSION.SDK_INT>=30||((Build.VERSION.SDK_INT>=28&&mask==255)||(Build.VERSION.SDK_INT==29&&mask==33023)),"status_known",value!=JSONObject.NULL,"authentication_status",value,"device_secure",keyguard!=null&&keyguard.isDeviceSecure(),"fingerprint_feature",pm.hasSystemFeature(PackageManager.FEATURE_FINGERPRINT),"face_feature",pm.hasSystemFeature(PackageManager.FEATURE_FACE),"iris_feature",pm.hasSystemFeature(PackageManager.FEATURE_IRIS),"prompt_busy",busy,"start_foreground_required",true);
    }
    static void capabilities(VmHardware.Context c,JSONArray out)throws Exception{
        JSONObject data=info(c,255);PackageManager pm=c.host.getPackageManager();boolean api=Build.VERSION.SDK_INT>=28,hardware=data.getBoolean("fingerprint_feature")||data.getBoolean("face_feature")||data.getBoolean("iris_feature")||(Build.VERSION.SDK_INT>=29&&pm.hasSystemFeature(PackageManager.FEATURE_SECURE_LOCK_SCREEN));Object credential=Build.VERSION.SDK_INT>=30?status(c,32768):JSONObject.NULL;boolean available=(data.optInt("authentication_status",-1)==0)||(credential instanceof Integer&&((Integer)credential)==0);
        out.put(VmHardware.object("id","biometric_authentication","implemented",true,"supported",api&&hardware,"available",api&&available&&c.host.hardwareVisible&&!data.getBoolean("prompt_busy"),"permission","biometrics","prompt_busy",data.getBoolean("prompt_busy"),"start_foreground_required",true,"weak_status",data.get("authentication_status"),"credential_status",credential));
    }
    static void release(Auth a){if(owner==a)owner=null;}
    static final class Auth extends VmHardware.Handle {
        final VmHardware.Context context;final String title,subtitle,description;final int mask,confirmation,timeout;final CancellationSignal cancel=new CancellationSignal();
        String state="pending";long deadlineElapsed;boolean requested,confirmed,cancelRequested,rejectedSuccess;JSONObject lastResult;
        final Runnable deadline=this::expired;
        void expired(){synchronized(LOCK){if(state.equals("pending")||state.equals("cancelling")){state="error";event("error","code","timeout","message","System authentication did not complete before its deadline.");cancelRequested=true;context.host.runOnUiThread(this::cancelOnUi);}}}
        Auth(VmHardware.Context c,String title,String subtitle,String description,int mask,int confirmation,int timeout){super(c,"biometrics","biometric_auth");context=c;this.title=title;this.subtitle=subtitle;this.description=description;this.mask=mask;this.confirmation=confirmation;this.timeout=timeout;}
        void event(String name,Object... values){try{Object[] fields=new Object[values.length+2];fields[0]="event";fields[1]=name;System.arraycopy(values,0,fields,2,values.length);lastResult=VmHardware.object(fields);emit(lastResult);}catch(Exception ignored){}}
        void finish(String next,String event,Object... values){synchronized(LOCK){confirmed=true;HardwareSensors.events().removeCallbacks(deadline);if(!closed&&(state.equals("pending")||state.equals("cancelling"))){state=next;event(event,values);}release(this);}}
        void start()throws Exception{synchronized(LOCK){check();deadlineElapsed=SystemClock.elapsedRealtime()+timeout;HardwareSensors.events().postDelayed(deadline,timeout);context.host.runOnUiThread(this::startOnUi);}}
        void startOnUi(){
            synchronized(LOCK){if(deadlineElapsed>0&&SystemClock.elapsedRealtime()>=deadlineElapsed&&state.equals("pending"))expired();if(closed||!state.equals("pending")){finish("cancelled","cancelled","reason","before_start","sdk_callback",false);return;}}
            BiometricPrompt prompt;
            try{
                if(!context.host.hardwareVisible)throw new VmHardware.Failure("foreground_required","Keep Collie visible when starting system authentication.");
                BiometricPrompt.Builder builder=new BiometricPrompt.Builder(context.host).setTitle(title);if(!subtitle.isEmpty())builder.setSubtitle(subtitle);if(!description.isEmpty())builder.setDescription(description);
                if(Build.VERSION.SDK_INT>=30)builder.setAllowedAuthenticators(mask);else if((mask&32768)!=0)builder.setDeviceCredentialAllowed(true);
                if(Build.VERSION.SDK_INT>=29)builder.setConfirmationRequired(confirmation==1);
                if((mask&32768)==0)builder.setNegativeButton(context.host.getString(android.R.string.cancel),CALLBACKS,(dialog,which)->finish("cancelled","cancelled","reason","negative_button","sdk_callback",true));
                prompt=builder.build();
            }catch(Exception error){finish("error","error","code",error instanceof VmHardware.Failure?((VmHardware.Failure)error).code:"invalid_argument","message",MainActivity.safe(error),"sdk_callback",false);return;}
            // Start/cancel both run on the main queue. A pre-start close cannot
            // cancel the signal before authenticate and strand its callback lease.
            synchronized(LOCK){if(deadlineElapsed>0&&SystemClock.elapsedRealtime()>=deadlineElapsed&&state.equals("pending"))expired();if(closed||!state.equals("pending")){finish("cancelled","cancelled","reason","before_start","sdk_callback",false);return;}requested=true;}
            try{
                prompt.authenticate(cancel,CALLBACKS,new BiometricPrompt.AuthenticationCallback(){
                    public void onAuthenticationSucceeded(BiometricPrompt.AuthenticationResult result){synchronized(LOCK){if(deadlineElapsed>0&&SystemClock.elapsedRealtime()>=deadlineElapsed&&state.equals("pending"))expired();if(result==null){finish("error","error","code","invalid_response","sdk_callback",true);return;}if(cancelRequested||!state.equals("pending")){rejectedSuccess=true;finish("cancelled","cancelled","reason","cancelled_before_callback","sdk_callback",true);return;}finish("authenticated","authenticated","authentication_type",Build.VERSION.SDK_INT>=30?result.getAuthenticationType():JSONObject.NULL,"completed_elapsed_ms",SystemClock.elapsedRealtime(),"sdk_callback",true);}}
                    public void onAuthenticationError(int code,CharSequence message){String next=code==BiometricPrompt.BIOMETRIC_ERROR_CANCELED||code==BiometricPrompt.BIOMETRIC_ERROR_USER_CANCELED?"cancelled":"error";finish(next,"error","code","sdk_error","sdk_code",code,"message",bounded(message),"sdk_callback",true);}
                    public void onAuthenticationFailed(){synchronized(LOCK){if(!closed&&state.equals("pending"))event("not_recognized","sdk_callback",true);}}
                    public void onAuthenticationHelp(int code,CharSequence message){synchronized(LOCK){if(!closed&&state.equals("pending"))event("help","sdk_code",code,"message",bounded(message),"sdk_callback",true);}}
                });
                synchronized(LOCK){if(!closed&&state.equals("pending"))event("requested","authenticators",mask);}
            }catch(Exception error){finish("error","error","code",error instanceof SecurityException?"permission_denied":"platform_error","message",MainActivity.safe(error),"sdk_callback",false);cancelOnUi();}
        }
        void cancelOnUi(){boolean started;synchronized(LOCK){started=requested;if(!started){finish("cancelled","cancelled","reason","before_start","sdk_callback",false);}}if(started)cancel.cancel();}
        int requestCancel()throws Exception{synchronized(LOCK){check();if(!state.equals("pending"))return 0;cancelRequested=true;state="cancelling";event("cancellation_requested");context.host.runOnUiThread(this::cancelOnUi);return 1;}}
        public Object info()throws Exception{synchronized(LOCK){check();if(deadlineElapsed>0&&SystemClock.elapsedRealtime()>=deadlineElapsed&&(state.equals("pending")||state.equals("cancelling")))expired();return VmHardware.object("kind",kind,"state",state,"authenticators",mask,"authenticated",state.equals("authenticated"),"sdk_requested",requested,"sdk_terminal",confirmed,"late_success_rejected",rejectedSuccess,"cleanup_pending",requested&&!confirmed&&!state.equals("pending"),"last_result",lastResult==null?JSONObject.NULL:lastResult);}}
        public void close()throws IOException{synchronized(LOCK){if(closed)return;super.close();state="closed";cancelRequested=true;HardwareSensors.events().removeCallbacks(deadline);context.host.runOnUiThread(this::cancelOnUi);}}
    }
    static String bounded(CharSequence value){if(value==null)return "";String text=value.toString();return text.length()>2048?text.substring(0,2048):text;}
    static Object call(VmHardware.Context c,String op,JSONArray a)throws Exception{
        if(op.equals("biometric_info")){int mask=mask(a,0);if(Build.VERSION.SDK_INT>=28)permission(c);return info(c,mask);}
        if(op.equals("biometric_cancel"))return VmHardware.handle(c,VmHardware.text(a,0,128),Auth.class).requestCancel();
        if(!op.equals("biometric_auth"))throw new VmHardware.Failure("unsupported_operation","Unknown biometric operation.");
        String title=VmHardware.text(a,0,200),subtitle=VmHardware.text(a,1,400),description=VmHardware.text(a,2,2000);int mask=mask(a,3),confirmation=VmHardware.integer(a,4,0,1),timeout=VmHardware.integer(a,5,500,120000);
        if(title.trim().isEmpty())throw new VmHardware.Failure("invalid_argument","System authentication requires a nonempty title.");
        if(Build.VERSION.SDK_INT<28)throw new VmHardware.Failure("unsupported","System BiometricPrompt requires Android9 or newer.");
        if(Build.VERSION.SDK_INT<30&&mask!=255&&!(Build.VERSION.SDK_INT==29&&mask==33023))throw new VmHardware.Failure("unsupported_operation","Before Android11 only default weak255, or Android10 weak|credential33023, can be requested without downgrading strength.");
        if(Build.VERSION.SDK_INT<29&&confirmation!=1)throw new VmHardware.Failure("unsupported_operation","Configurable confirmation requires Android10 or newer.");permission(c);
        if(!c.host.hardwareVisible)throw new VmHardware.Failure("foreground_required","Keep Collie visible when starting system authentication.");Auth auth;
        synchronized(LOCK){if(owner!=null)throw new VmHardware.Failure("busy","A system authentication request is active or awaiting its actual terminal callback.");auth=new Auth(c,title,subtitle,description,mask,confirmation,timeout);owner=auth;}
        VmHardware.blocking(auth);try{String id=VmHardware.add(auth);auth.start();return id;}catch(Exception error){auth.close();throw error;}finally{VmHardware.unblocking();}
    }
}
