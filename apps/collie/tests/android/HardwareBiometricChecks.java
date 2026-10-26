package org.flexscript.collie;

import android.app.KeyguardManager;
import android.hardware.biometrics.BiometricManager;
import android.os.*;
import java.io.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicReference;
import org.json.*;

/** Actual SDK metadata plus explicitly controlled queue/cancellation fixtures. */
public final class HardwareBiometricChecks {
    final MainActivity host;final File root;final VmHardware.Context context;final JSONArray checks=new JSONArray();int sequence;
    HardwareBiometricChecks(MainActivity host,File root){this.host=host;this.root=root;context=new VmHardware.Context(host,root);}
    public static JSONObject run(MainActivity host,File root)throws Exception{return new HardwareBiometricChecks(host,root).run();}
    public static JSONObject runLive(MainActivity host,File root)throws Exception{return new HardwareBiometricChecks(host,root).live();}
    public static JSONObject runLate(MainActivity host,File root)throws Exception{return new HardwareBiometricChecks(host,root).late();}
    void check(boolean value,String label)throws Exception{if(!value)throw new IOException(label);checks.put(label);}
    JSONObject vm(String source)throws Exception{
        source="fn fail(n){let e=db_error();db_io(0,2,e,db_len(e));return n;}"+source.replaceAll("return ([1-9][0-9]*);","return fail($1);");
        JSONObject result=host.engineAt(root,3,new JSONObject().put("config",host.workerConfig(root,0)).put("call_id","biometric-check-"+(++sequence)).put("history",new JSONArray()).put("source",source));
        if(!result.optString("state").equals("continue")||result.optInt("exit_code")!=0)throw new IOException("Biometric scenario "+sequence+": "+result+" source="+source);return result;
    }
    static String quote(String text){return JSONObject.quote(text).replace("\\/","/");}
    void ui(Runnable action)throws Exception{CountDownLatch done=new CountDownLatch(1);AtomicReference<Throwable> error=new AtomicReference<>();host.runOnUiThread(()->{try{action.run();}catch(Throwable value){error.set(value);}finally{done.countDown();}});if(!done.await(4,TimeUnit.SECONDS))throw new IOException("Biometric UI fixture timed out");if(error.get()!=null)throw new IOException(error.get());}
    String open()throws Exception{return vm("fn main(){let h=biometric_auth(\"Collie lifecycle fixture\",\"\",\"\",15,1,30000);if !h{return 1;}db_io(0,1,db_word(h),db_bytes(h));return 0;}").getString("stdout");}
    HardwareBiometrics.Auth requested(String id)throws Exception{HardwareBiometrics.Auth auth=VmHardware.handle(context,id,HardwareBiometrics.Auth.class);long end=SystemClock.elapsedRealtime()+4000;while(SystemClock.elapsedRealtime()<end&&!((JSONObject)auth.info()).getBoolean("sdk_requested"))Thread.sleep(10);check(((JSONObject)auth.info()).getBoolean("sdk_requested")&&((JSONObject)auth.info()).getString("state").equals("pending"),"the lifecycle fixture has an actual pending Android authenticate request");return auth;}
    void released()throws Exception{long end=SystemClock.elapsedRealtime()+4000;while(SystemClock.elapsedRealtime()<end&&HardwareBiometrics.info(context,15).getBoolean("prompt_busy"))Thread.sleep(10);check(!HardwareBiometrics.info(context,15).getBoolean("prompt_busy"),"the actual terminal SDK callback releases the prompt lease after local teardown");}
    JSONObject live()throws Exception{
        if(Build.VERSION.SDK_INT<30||host.getSystemService(BiometricManager.class).canAuthenticate(15)!=0)throw new IOException("Live lifecycle checks require an enrolled strong biometric fixture");
        String id=open();HardwareBiometrics.Auth auth=requested(id);CountDownLatch entered=new CountDownLatch(1),release=new CountDownLatch(1);AtomicReference<Throwable> error=new AtomicReference<>();
        File foreign=new File(root,"biometric-foreign");if(!new File(foreign,"files").mkdirs())throw new IOException("Cannot create ownership fixture");
        try{
            JSONObject denied=host.engineAt(foreign,3,new JSONObject().put("config",host.workerConfig(foreign,0)).put("source","fn main(){if device_info("+quote(id)+") || biometric_cancel("+quote(id)+"){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"stale_handle\"){return 2;}return 0;}").put("history",new JSONArray()));
            check(denied.optString("state").equals("continue")&&denied.optInt("exit_code")==0,"a different actual VM workspace cannot inspect or cancel the authentication handle");
            HardwareSensors.events().post(()->{entered.countDown();try{if(!release.await(6,TimeUnit.SECONDS))throw new IOException("controlled SDK callback queue timed out");}catch(Throwable value){error.set(value);}});
            check(entered.await(2,TimeUnit.SECONDS),"the actual SDK callback executor is held during local close");
            vm("fn main(){if device_close("+quote(id)+")!=1{return 1;}if device_info("+quote(id)+"){return 2;}if biometric_auth(\"Overlap\",\"\",\"\",15,1,30000){return 3;}if !worker_equal(db_word(db_at(device_error(),0)),\"busy\"){return 4;}return 0;}");
            check(auth.closed&&!auth.confirmed,"local close invalidates the handle while the prompt lease remains held for its actual queued SDK terminal callback");
        }finally{release.countDown();VmHardware.closeWorkspace(foreign);try{VmHardware.close(context,id);}catch(Exception ignored){}}
        released();if(error.get()!=null)throw new IOException(error.get());
        id=open();auth=requested(id);final String live=id;ExecutorService executor=Executors.newSingleThreadExecutor();Future<JSONObject> running=null;java.lang.reflect.Method save=MainActivity.class.getDeclaredMethod("savePermission",String.class,Object.class);save.setAccessible(true);
        try{
            running=executor.submit(()->host.engineAt(root,3,new JSONObject().put("config",host.workerConfig(root,0)).put("source","fn main(){let i=0;while i<10000{device_wait("+quote(live)+",1000);i=i+1;}return 1;}").put("history",new JSONArray())));
            java.lang.reflect.Field active=VmHardware.class.getDeclaredField("active");active.setAccessible(true);boolean waiting=false;long end=SystemClock.elapsedRealtime()+4000;
            while(SystemClock.elapsedRealtime()<end&&!waiting){Object operation=active.get(null);if(operation!=null){java.lang.reflect.Field io=operation.getClass().getDeclaredField("cancelIO");io.setAccessible(true);waiting=io.get(operation)!=null;}if(!waiting){if(running.isDone())throw new IOException("VM exited before biometric revocation: "+running.get());Thread.sleep(10);}}
            check(waiting,"the actual VM is waiting in authentication I/O before the grant changes");
            ui(()->{try{save.invoke(host,"biometrics",false);}catch(Exception value){throw new RuntimeException(value);}});
            JSONObject stopped=running.get(4,TimeUnit.SECONDS);check(stopped.optString("state").equals("error")&&stopped.optString("stderr").toLowerCase(java.util.Locale.ROOT).contains("cancel"),"the actual permission-save path cancels the running VM on biometric revocation");
            check(auth.closed&&!host.workerConfig(root,0).getJSONObject("permissions").optBoolean("biometrics"),"biometric revocation closes the pending SDK request and updates future policy");
            vm("fn main(){if biometric_info(15){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"permission_denied\"){return 2;}return 0;}");check(true,"a subsequent program cannot reopen biometrics after revocation");released();
        }finally{if(running!=null&&!running.isDone()){VmHardware.cancel();running.cancel(true);}executor.shutdownNow();VmHardware.closeWorkspace(root);ui(()->{try{save.invoke(host,"biometrics",true);}catch(Exception value){throw new RuntimeException(value);}});}
        return new JSONObject().put("ok",true).put("checks",checks).put("physical_authentication_verified",false);
    }
    JSONObject late()throws Exception{
        if(Build.VERSION.SDK_INT<30||host.getSystemService(BiometricManager.class).canAuthenticate(15)!=0)throw new IOException("Late SDK success requires an enrolled fixture");
        CountDownLatch entered=new CountDownLatch(1),release=new CountDownLatch(1);AtomicReference<Throwable> error=new AtomicReference<>();String id=null;
        try{
            HardwareSensors.events().post(()->{entered.countDown();try{if(!release.await(15,TimeUnit.SECONDS))throw new IOException("late-success callback hold timed out");}catch(Throwable value){error.set(value);}});
            check(entered.await(2,TimeUnit.SECONDS),"the actual SDK callback/deadline executor is held for the late-success fixture");
            String title="Collie delayed "+java.util.UUID.randomUUID().toString().substring(0,8);
            id=vm("fn main(){let h=biometric_auth("+quote(title)+",\"\",\"\",15,1,10000);if !h{return 1;}db_io(0,1,db_word(h),db_bytes(h));return 0;}").getString("stdout");
            HardwareBiometrics.Auth auth=requested(id);
            MainActivity.atomic(new File(root,"biometric-late-ready.json"),new JSONObject().put("title",title).toString());
            File touched=new File(root,"biometric-late-touched.json");
            while(SystemClock.elapsedRealtime()<auth.deadlineElapsed&&!touched.isFile())Thread.sleep(10);
            check(touched.isFile()&&SystemClock.elapsedRealtime()<auth.deadlineElapsed,"the host delivered the owned virtual finger while the actual system prompt was still within its deadline");
            while(SystemClock.elapsedRealtime()<=auth.deadlineElapsed+50)Thread.sleep(10);
            release.countDown();released();if(error.get()!=null)throw new IOException(error.get());
            vm("fn main(){let h="+quote(id)+";let info=device_info(h);if !db_word(device_field(info,\"late_success_rejected\")) || !db_word(device_field(info,\"sdk_terminal\")) || db_word(device_field(info,\"authenticated\")) || !worker_equal(db_word(device_field(info,\"state\")),\"error\"){return 1;}let timeout=0;let i=0;while i<8{let e=device_wait(h,0);if db_kind(e)==5{let event=device_field(e,\"event\");let code=device_field(e,\"code\");if db_kind(event)==2 && worker_equal(db_word(event),\"authenticated\"){return 2;}if db_kind(code)==2 && worker_equal(db_word(code),\"timeout\"){timeout=1;}}i=i+1;}if !timeout{return 3;}return 0;}");
            check(true,"an actual successful SDK callback delayed past the deadline is rejected, reports timeout, emits no authenticated event and releases its lease");
        }finally{release.countDown();if(id!=null)try{VmHardware.close(context,id);}catch(Exception ignored){}new File(root,"biometric-late-ready.json").delete();new File(root,"biometric-late-touched.json").delete();}
        return new JSONObject().put("ok",true).put("checks",checks).put("physical_authentication_verified",false);
    }
    JSONObject run()throws Exception{
        if(Build.VERSION.SDK_INT<30)throw new IOException("This SDK comparison fixture requires Android11+");
        BiometricManager manager=host.getSystemService(BiometricManager.class);KeyguardManager keys=host.getSystemService(KeyguardManager.class);
        int[] masks=Build.VERSION.SDK_INT>=36?new int[]{15,255,32768,32783,33023,65551,98559}:new int[]{15,255,32768,32783,33023};
        for(int mask:masks){int actual=manager.canAuthenticate(mask);vm("fn main(){let info=biometric_info("+mask+");if !info || !db_word(device_field(info,\"status_known\")) || db_word(device_field(info,\"authentication_status\"))!="+actual+" || db_word(device_field(info,\"device_secure\"))!="+(keys.isDeviceSecure()?1:0)+"{return 1;}return 0;}");}
        check(true,"VM availability and credential configuration match independent Android SDK queries for all supported authenticator masks");
        vm("fn main(){if biometric_info(0)||biometric_info(1)||biometric_info(16)||biometric_info(65536)||biometric_info(98560){return 1;}if biometric_auth(\"\",\"\",\"\",255,1,30000)||biometric_auth(\"Test\",\"\",\"\",255,2,30000)||biometric_auth(\"Test\",\"\",\"\",255,1,499){return 2;}if !worker_equal(db_word(db_at(device_error(),0)),\"invalid_argument\"){return 3;}return 0;}");
        check(true,"invalid strength masks, empty titles, confirmation flags and deadlines fail before system UI");
        queued(false);queued(true);
        return new JSONObject().put("ok",true).put("checks",checks).put("physical_authentication_verified",false);
    }
    void queued(boolean timeout)throws Exception{
        CountDownLatch entered=new CountDownLatch(1),release=new CountDownLatch(1),eventsEntered=new CountDownLatch(1),eventsRelease=new CountDownLatch(1);AtomicReference<Throwable> error=new AtomicReference<>();
        host.runOnUiThread(()->{entered.countDown();try{if(!release.await(6,TimeUnit.SECONDS))throw new IOException("controlled main-queue fixture timed out");}catch(Throwable value){error.set(value);}});
        String id=null;
        try{
            check(entered.await(2,TimeUnit.SECONDS),"the controlled UI queue fixture is actually holding the main thread");
            if(timeout){HardwareSensors.events().post(()->{eventsEntered.countDown();try{if(!eventsRelease.await(6,TimeUnit.SECONDS))throw new IOException("controlled event queue timed out");}catch(Throwable value){error.set(value);}});check(eventsEntered.await(2,TimeUnit.SECONDS),"the actual SDK callback/deadline queue is independently blocked for the timeout fixture");}
            String cancel=timeout?"":"if db_word(biometric_cancel(db_word(h)))!=1{return 3;}";
            JSONObject opened=vm("fn main(){let h=biometric_auth(\"Queued fixture\",\"\",\"\",255,1,"+(timeout?500:4000)+");if !h{return 1;}if biometric_auth(\"Overlap\",\"\",\"\",255,1,4000){return 2;}if !worker_equal(db_word(db_at(device_error(),0)),\"busy\"){return 4;}"+cancel+"db_io(0,1,db_word(h),db_bytes(h));return 0;}");id=opened.getString("stdout");HardwareBiometrics.Auth auth=VmHardware.handle(context,id,HardwareBiometrics.Auth.class);
            if(timeout){long end=SystemClock.elapsedRealtime()+3000;while(SystemClock.elapsedRealtime()<end&&!((JSONObject)auth.info()).getString("state").equals("error"))Thread.sleep(10);check(((JSONObject)auth.info()).getString("state").equals("error")&&!auth.requested,"elapsed-time timeout checking works even when both the main/start queue and scheduled deadline/callback queue are blocked");}
            else check(auth.info() instanceof JSONObject&&!auth.requested&&((JSONObject)auth.info()).getString("state").equals("cancelling"),"pre-start cancellation rejects overlapping prompts and does not start SDK authentication");
            release.countDown();eventsRelease.countDown();long end=SystemClock.elapsedRealtime()+3000;while(SystemClock.elapsedRealtime()<end&&!((JSONObject)auth.info()).getBoolean("sdk_terminal"))Thread.sleep(10);
            JSONObject state=(JSONObject)auth.info();check(state.getBoolean("sdk_terminal")&&!state.getBoolean("sdk_requested")&&!state.getBoolean("authenticated"),"releasing the main queue confirms local teardown without a late SDK prompt or invented successful callback");
            if(error.get()!=null)throw new IOException(error.get());
            vm("fn main(){let info=biometric_info(255);if db_word(device_field(info,\"prompt_busy\")){return 1;}return 0;}");check(true,"confirmed pre-start teardown frees the single prompt lease for later authentication");
        }finally{release.countDown();eventsRelease.countDown();if(id!=null)try{VmHardware.close(context,id);}catch(Exception ignored){}}
    }
}
