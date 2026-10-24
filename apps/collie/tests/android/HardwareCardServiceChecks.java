package org.flexscript.collie;

import android.app.ActivityManager;
import android.content.*;
import android.content.pm.*;
import android.os.*;
import java.io.*;
import java.util.*;
import java.util.concurrent.*;
import org.json.*;

/** Constructed Messenger inputs to the real separate-process service/VM, never RF. */
final class HardwareCardServiceChecks {
    final HardwareHceChecks test;final MainActivity host;final File root;final VmHardware.Context context;String fixture;boolean hidden;
    HardwareCardServiceChecks(HardwareHceChecks test){this.test=test;host=test.host;root=test.root;context=test.context;}
    static void run(HardwareHceChecks t)throws Exception{new HardwareCardServiceChecks(t).run();}
    static String q(String s){return JSONObject.quote(s).replace("\\/","/");}
    JSONObject record(String source,Object state)throws Exception{return VmHardware.object("version",1,"id",fixture,"root",root.getCanonicalPath(),"category",0,"aids",new JSONArray().put("F0434F4C4C494501"),"source",source,"saved_state",state,"timeout_ms",5000,"state","ready","revision",0,"registration_acknowledged",false,"handler_compiled",false);}
    void replace(String source,Object state)throws Exception{HardwareHceBackground.locked(host,(f,r)->{if(r==null||!fixture.equals(r.getString("id")))throw new IOException("Card fixture ownership changed");r.put("source",source).put("saved_state",state).put("revision",r.getLong("revision")+1);HardwareHceBackground.store(f,r);return null;});}
    JSONObject current()throws Exception{JSONObject r=HardwareHceBackground.snapshot(host);if(r==null||!fixture.equals(r.getString("id")))throw new IOException("Card fixture disappeared");return r;}
    int process(){for(ActivityManager.RunningAppProcessInfo p:host.getSystemService(ActivityManager.class).getRunningAppProcesses())if(p.processName.equals(host.getPackageName()+":hce_background")&&p.uid==android.os.Process.myUid())return p.pid;return -1;}
    final class Peer implements AutoCloseable {
        final BlockingQueue<Message> replies=new ArrayBlockingQueue<>(8);final CountDownLatch connected=new CountDownLatch(1);Messenger service;boolean bound;
        // New SDKs also emit latency acknowledgements(5/7). They are not
        // response APDUs or notifyUnhandled, and never count as an exchange.
        final Messenger receiver=new Messenger(new Handler(Looper.getMainLooper(),m->{if(m.what==1||m.what==3)replies.offer(Message.obtain(m));return true;}));
        final ServiceConnection connection=new ServiceConnection(){public void onServiceConnected(ComponentName n,IBinder b){service=new Messenger(b);connected.countDown();}public void onServiceDisconnected(ComponentName n){}};
        Peer()throws Exception{test.ui(()->{bound=host.bindService(new Intent().setComponent(HardwareHceBackground.component(host,0)),connection,android.content.Context.BIND_AUTO_CREATE);});if(!bound||!connected.await(10,TimeUnit.SECONDS))throw new IOException("Background card service did not bind");}
        void send(int what,byte[] bytes)throws Exception{Message m=Message.obtain(null,what);m.replyTo=receiver;if(bytes!=null){Bundle data=new Bundle();data.putByteArray("data",bytes);m.setData(data);}service.send(m);}
        Message receive(int what)throws Exception{long end=SystemClock.elapsedRealtime()+8000;while(SystemClock.elapsedRealtime()<end){Message m=replies.poll(100,TimeUnit.MILLISECONDS);if(m!=null){if(m.what!=what)throw new IOException("Unexpected card response "+m.what+" expected "+what+": "+current());return m;}}throw new IOException("Background card callback timed out: "+current());}
        byte[] command(byte[] bytes)throws Exception{send(0,bytes);byte[] response=receive(1).getData().getByteArray("data");if(response==null)throw new IOException("No SDK response bytes");return response;}
        public void close()throws Exception{try{send(2,null);}catch(RemoteException disconnected){}finally{if(bound)test.ui(()->host.unbindService(connection));}}
    }
    void foreground()throws Exception{test.ui(()->host.startActivity(new Intent(host,MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP|Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)));test.until(()->host.hardwareResumed);hidden=false;}
    void run()throws Exception{
        if(HardwareHceBackground.owned(host))throw new IOException("Refusing to overwrite an existing durable card profile.");
        fixture="card-"+UUID.randomUUID();Object previous=host.workerConfig(root,0).getJSONObject("permissions").get("nfc");
        String counter="fn main(){let n=db_word(card_state());let b=alloc(3);store8(b,n);store8(b+1,144);store8(b+2,0);return db_word(card_reply(db_blob(b,3),db_int(n+1)))-1;}";
        try{
            for(int mode=0;mode<2;mode++){ServiceInfo info=host.getPackageManager().getServiceInfo(HardwareHceBackground.component(host,mode),PackageManager.MATCH_DISABLED_COMPONENTS|PackageManager.GET_META_DATA);test.check(info.exported&&"android.permission.BIND_NFC_SERVICE".equals(info.permission)&&info.processName.equals(host.getPackageName()+":hce_background")&&host.getPackageManager().getComponentEnabledSetting(HardwareHceBackground.component(host,mode))==PackageManager.COMPONENT_ENABLED_STATE_DEFAULT,"background card category"+mode+" is default-disabled, protected by BIND_NFC_SERVICE and assigned to a separate Android process");}
            if(!HardwareHce.supported(host,HardwareNfc.optional(context),0)){
                test.vm("fn main(){let a=db_list();db_add(a,db_text(\"F0434F4C4C494501\"));if hce_background_install(0,a,"+q(counter)+",db_int(7),5000){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"unsupported\"){return 2;}return 0;}");
                test.check(!HardwareHceBackground.owned(host),"actual missing NFC support rejects background installation before a durable owner or enabled component is created");
            }
            // This fixture intentionally constructs a ready record without any
            // SDK routing acknowledgement, on the actual NFC-less emulator.
            HardwareHceBackground.locked(host,(f,r)->{if(r!=null)throw new IOException("Unexpected durable card owner");HardwareHceBackground.store(f,record(counter,7));return null;});
            host.getPackageManager().setComponentEnabledSetting(HardwareHceBackground.component(host,0),PackageManager.COMPONENT_ENABLED_STATE_ENABLED,PackageManager.DONT_KILL_APP);
            int pid;
            try(Peer peer=new Peer()){
                pid=process();test.check(pid>0&&pid!=android.os.Process.myPid(),"Android starts the actual protected card service in a different process from the Activity");
                byte[] response=peer.command(new byte[]{0,(byte)164,4,0});test.check(Arrays.equals(response,new byte[]{7,(byte)144,0})&&current().getInt("saved_state")==8&&current().getString("last_submission").equals("sdk_returned"),"a constructed APDU invokes the actual separate-process native VM, returns exact SDK Messenger bytes and durably advances guest state");
                test.vm("fn main(){if db_word(hce_background_state())!=8{return 1;}let s=hce_background_status();if !db_word(device_field(s,\"owned\"))||db_word(device_field(s,\"registration_acknowledged\"))||!db_word(device_field(s,\"handler_compiled\")){return 2;}return 0;}");
                test.check(true,"the agent VM reads the durable callback state and reports actual compilation separately from the fixture's absent routing acknowledgement");
                test.ui(()->host.startActivity(new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)));test.until(()->!host.hardwareVisible);hidden=true;
                response=peer.command(new byte[]{0,(byte)164,4,0});test.check(Arrays.equals(response,new byte[]{8,(byte)144,0})&&current().getInt("saved_state")==9,"the actual Android service continues executing Flexscript and saving state after Activity onPause/onStop");foreground();
                test.check(current().optBoolean("channel_active"),"the actual service callback retains a live channel lease independently of saved guest state");
                android.os.Process.killProcess(pid);test.until(()->process()!=pid);
                test.check(current().optBoolean("channel_active")&&current().getInt("saved_state")==9,"actual process death leaves the durable channel marker and guest state intact until an SDK instance/recovery observation settles ownership");
            }
            // Kill only the owned, same-UID callback process. The foreground
            // harness remains alive; no VM offsets/OS handles are restored.
            try(Peer peer=new Peer()){
                test.check(process()>0&&process()!=pid,"Android cold-starts a new card-service process after the owned callback process is killed");
                test.check(!current().optBoolean("channel_active"),"a real replacement service instance settles the dead instance's marker without restoring a stale channel");
                test.check(Arrays.equals(peer.command(new byte[]{0,(byte)164,4,0}),new byte[]{9,(byte)144,0})&&current().getInt("saved_state")==10,"a fresh native process loads the registered source and saved guest state without reopening the Activity or restoring native handles");
                File other=new File(root,"card-foreign");new File(other,"files").mkdirs();test.vm(other,"fn main(){if db_word(device_field(hce_background_status(),\"owned\"))||hce_background_state()||hce_background_remove("+q(fixture)+"){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"stale_registration\"){return 2;}return 0;}");
                test.check(true,"another actual VM workspace cannot inspect callback state or remove the durable registration");
                String full="fn main(){card_reply_begin(65538);let i=0;while i<65538{let n=65538-i;if n>32768{n=32768;}let p=card_command(i,n);if db_word(card_reply_write(i,db_at(p,0)))!=n{return 1;}i=i+n;}return db_word(card_commit(card_state()))-1;}";
                replace(full,10);byte[] command=new byte[65544];for(int i=0;i<command.length;i++)command[i]=(byte)((i*17+3)&255);
                byte[] response=peer.command(command);test.check(Arrays.equals(response,Arrays.copyOf(command,65538)),"every byte of a constructed extended65544-byte command and65538-byte reply crosses the actual separate-process service, VM and SDK Messenger");
                replace("fn main(){card_reply(db_blob(\"xx\",2),db_int(999));return 1;}",10);long revision=current().getLong("revision");peer.send(0,new byte[]{0,(byte)164,4,0});peer.receive(3);
                test.check(current().getLong("revision")==revision&&current().getInt("saved_state")==10&&current().optString("last_error").contains("exit 1"),"a failing actual callback publishes neither its staged reply nor its staged state, reports the real exit code and invokes SDK notifyUnhandled");
                replace("fn main(){let r=db_request(\"fs_write\");db_add(r,db_text(\"escape\"));db_add(r,db_text(\"no\"));if db_rpc(r){return 1;}return db_word(card_reply(db_blob(\"ok\",2),db_int(11)))-1;}",10);
                test.check(Arrays.equals(peer.command(new byte[]{0,(byte)164,4,0}),new byte[]{'o','k'})&&!new File(root,"files/escape").exists(),"raw callback capability frames cannot reach host files in the actual Android service process");
                replace("fn main(){while 1{}return 0;}",11);HardwareHceBackground.change(host,fixture,(f,r)->{r.put("timeout_ms",100);HardwareHceBackground.store(f,r);return null;});revision=current().getLong("revision");long start=SystemClock.elapsedRealtime();peer.send(0,new byte[]{0,(byte)164,4,0});peer.receive(3);
                test.check(SystemClock.elapsedRealtime()-start<2000&&current().getLong("revision")==revision&&current().getInt("saved_state")==11&&current().optString("last_submission").equals("deadline_expired"),"the actual100ms transaction timer cancels callback work and reports SDK notifyUnhandled without committing reply/state");
                test.check(peer.replies.poll(250,TimeUnit.MILLISECONDS)==null&&current().getLong("revision")==revision,"late completion after the actual callback deadline cannot publish a response or overwrite saved state");
                replace(counter,11);HardwareHceBackground.change(host,fixture,(f,r)->{r.put("timeout_ms",5000).put("state","registering").put("startup_instance",HardwareHceBackground.INSTANCE).put("startup_deadline_elapsed_ms",SystemClock.elapsedRealtime()-1);HardwareHceBackground.store(f,r);return null;});
                test.vm("fn main(){if !worker_equal(db_word(device_field(hce_background_status(),\"state\")),\"recovery_required\"){return 1;}return 0;}");
                test.check(current().getString("state").equals("recovery_required"),"getter-driven startup expiry retains durable ownership without inventing an SDK registration acknowledgement");
                HardwareHceBackground.change(host,fixture,(f,r)->{r.put("state","ready").put("registration_attempted",true);HardwareHceBackground.store(f,r);return null;});
                if(!HardwareHce.supported(host,HardwareNfc.optional(context),0)){
                    test.vm("fn main(){return db_word(hce_background_remove("+q(fixture)+"))-1;}");test.until(()->{try{return current().getString("state").equals("cleanup_error");}catch(Exception error){throw new RuntimeException(error);}});
                    test.check(HardwareHceBackground.owned(host)&&!current().getString("last_error").isEmpty(),"a constructed uncertain SDK attempt retains ownership when the actual adapter cannot verify registration cleanup");
                    HardwareHceBackground.change(host,fixture,(f,r)->{r.put("state","ready").put("registration_attempted",false);HardwareHceBackground.store(f,r);return null;});
                }
                test.ui(()->{try{host.savePermission("nfc",false);}catch(Exception error){throw new RuntimeException(error);}});
                test.until(()->{try{JSONObject r=HardwareHceBackground.snapshot(host);return r==null||r.getString("state").equals("awaiting_deactivation");}catch(Exception e){throw new RuntimeException(e);}});
                if(HardwareHceBackground.owned(host)){test.check(current().optBoolean("channel_active")&&current().optBoolean("routes_removed"),"local NFC removal retains ownership after SDK route/component cleanup while its actual service channel remains active");peer.send(2,null);}
                test.until(()->{try{return !HardwareHceBackground.owned(host);}catch(Exception e){throw new RuntimeException(e);}});
                test.check(host.getPackageManager().getComponentEnabledSetting(HardwareHceBackground.component(host,0))==PackageManager.COMPONENT_ENABLED_STATE_DEFAULT,"NFC Deny persists removal, performs actual component cleanup and releases the constructed background registration");
            }
        }finally{
            if(hidden)foreground();
            HardwareHceBackground.locked(host,(f,r)->{if(r!=null&&fixture.equals(r.getString("id")))f.delete();return null;});
            for(int mode=0;mode<2;mode++)host.getPackageManager().setComponentEnabledSetting(HardwareHceBackground.component(host,mode),PackageManager.COMPONENT_ENABLED_STATE_DEFAULT,PackageManager.DONT_KILL_APP);
            test.ui(()->{try{host.savePermission("nfc",previous);}catch(Exception error){throw new RuntimeException(error);}});
        }
    }
}
