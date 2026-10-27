package org.flexscript.collie;

import android.Manifest;
import android.hardware.camera2.*;
import android.os.Build;
import java.io.IOException;
import org.json.*;

/** Owned public torch requests; global SDK observations are not invented LED measurements. */
final class HardwareCameraTorch {
    static final class Torch extends VmHardware.Handle {
        final VmHardware.Context context;final CameraManager manager;final String cameraId;final int strength;
        boolean starting,registered,accepted,seenOn,lost,cleanupQueued,cleanupReturned;String cleanupError="";
        Torch(VmHardware.Context c,String id,int strength)throws Exception{super(c,"camera","camera_torch");context=c;manager=HardwareCamera.manager(c);cameraId=id;this.strength=strength;}
        final CameraManager.TorchCallback callback=new CameraManager.TorchCallback(){
            public void onTorchModeChanged(String id,boolean enabled){if(!id.equals(cameraId))return;try{synchronized(Torch.this){if(closed)return;if(enabled)seenOn=true;else if(seenOn)lost=true;emit(VmHardware.object("event","torch","enabled",enabled,"sdk_callback",true,"ownership_lost",lost));}}catch(Exception ignored){}}
            public void onTorchModeUnavailable(String id){if(!id.equals(cameraId))return;try{synchronized(Torch.this){if(closed)return;if(accepted)lost=true;emit(VmHardware.object("event","torch_unavailable","sdk_callback",true));}}catch(Exception ignored){}}
            public void onTorchStrengthLevelChanged(String id,int level){if(!id.equals(cameraId))return;try{emit(VmHardware.object("event","torch_strength","level",level,"sdk_callback",true));}catch(Exception ignored){}}
        };
        void start()throws Exception{synchronized(this){check();starting=true;}try{manager.registerTorchCallback(callback,HardwareCamera.events());synchronized(this){registered=true;check();}HardwareCamera.captureAccess(context);if(strength==0)manager.setTorchMode(cameraId,true);else manager.turnOnTorchWithStrengthLevel(cameraId,strength);synchronized(this){accepted=true;}}finally{synchronized(this){starting=false;if(closed)cleanup();}}}
        void access(VmHardware.Context c)throws Exception{super.access(c);try{HardwareCamera.captureAccess(c);}catch(Exception e){close();throw e;}}
        synchronized Object info()throws Exception{check();return VmHardware.object("kind",kind,"camera",cameraId,"requested_strength",strength,"sdk_request_returned",accepted,"sdk_on_observed",seenOn,"ownership_lost",lost,"cleanup_returned",cleanupReturned,"cleanup_error",cleanupError);}
        synchronized void cleanup(){if(starting||cleanupQueued)return;cleanupQueued=true;boolean disable=accepted&&!lost;HardwareCamera.CLEANUP.execute(()->{try{if(disable)manager.setTorchMode(cameraId,false);if(registered)manager.unregisterTorchCallback(callback);synchronized(Torch.this){cleanupReturned=true;}HardwareCamera.release(cameraId,this);}catch(Exception e){synchronized(Torch.this){cleanupError=MainActivity.safe(e);}}});}
        public synchronized void close()throws IOException{if(closed)return;super.close();cleanup();}
    }
    static Object open(VmHardware.Context c,String id,CameraCharacteristics ch,int strength)throws Exception{
        if(!Boolean.TRUE.equals(ch.get(CameraCharacteristics.FLASH_INFO_AVAILABLE)))throw new VmHardware.Failure("unsupported","This camera does not advertise a flash/torch unit.");
        if(strength>0){if(Build.VERSION.SDK_INT<33)throw new VmHardware.Failure("unsupported_operation","Torch strength requires Android13+.");Integer maximum=ch.get(CameraCharacteristics.FLASH_INFO_STRENGTH_MAXIMUM_LEVEL);if(maximum==null||maximum<=1)throw new VmHardware.Failure("unsupported_operation","This camera does not advertise adjustable torch strength.");if(strength>maximum)throw new VmHardware.Failure("invalid_argument","Torch strength exceeds the SDK maximum.");}
        VmHardware.require(c,Manifest.permission.CAMERA);HardwareCamera.captureAccess(c);Torch torch=new Torch(c,id,strength);HardwareCamera.reserve(id,torch);VmHardware.blocking(torch);try{String handle=VmHardware.add(torch);torch.start();return handle;}catch(Exception e){torch.close();throw e;}finally{VmHardware.unblocking();}
    }
}
