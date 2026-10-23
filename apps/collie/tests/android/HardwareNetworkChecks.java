package org.flexscript.collie;

import android.net.Network;
import java.io.*;
import java.net.*;
import java.security.*;
import java.security.spec.X509EncodedKeySpec;
import javax.crypto.*;
import javax.crypto.spec.GCMParameterSpec;
import java.util.*;
import java.util.concurrent.*;
import org.json.*;

/** Real local sockets through the actual compiler/VM/JNI/Android hardware path. */
public final class HardwareNetworkChecks {
    private final MainActivity host;private final File root;private final JSONArray checks=new JSONArray();
    private int sequence;
    private HardwareNetworkChecks(MainActivity host,File root){this.host=host;this.root=root;}
    private void check(boolean value,String name)throws Exception{if(!value)throw new IOException(name);checks.put(name);}
    private JSONObject vm(String source)throws Exception{
        source="fn hardware_test_fail(n){let e=db_error();db_io(0,2,e,db_len(e));return n;}"+source.replaceAll("return ([1-9][0-9]*);","return hardware_test_fail($1);");
        JSONObject result=host.engineAt(root,3,new JSONObject().put("config",host.workerConfig(root,0)).put("call_id","hardware-check-"+(++sequence)).put("history",new JSONArray()).put("source",source));
        if(!result.optString("state").equals("continue") || result.optInt("exit_code")!=0)throw new IOException("Hardware scenario "+sequence+": "+result.toString()+" source="+source);return result;
    }
    private static String quoted(String text){return JSONObject.quote(text).replace("\\/","/");}
    private static final String PRINT="fn emit(v){db_io(0,1,db_word(v),db_bytes(v));}fn number(n){let b=alloc(32);let i=32;while n>=10{i=i-1;store8(b+i,48+n%10);n=n/10;}i=i-1;store8(b+i,48+n);db_io(0,1,b+i,32-i);}";
    private static final String HEX="fn hex(v){let digits=\"0123456789abcdef\";let b=alloc(db_bytes(v)*2+1);let i=0;while i<db_bytes(v){let n=load8(db_word(v)+i);store8(b+i*2,load8(digits+(n>>4)));store8(b+i*2+1,load8(digits+(n&15)));i=i+1;}db_io(0,1,b,db_bytes(v)*2);}";
    private static byte[] unhex(String text){byte[] out=new byte[text.length()/2];for(int i=0;i<out.length;i++)out[i]=(byte)Integer.parseInt(text.substring(i*2,i*2+2),16);return out;}
    private void keystore(VmHardware.Context context,File other)throws Exception{
        String prefix=HardwareKeystore.prefix(context);KeyStore store=HardwareKeystore.store();
        try{
            for(String kind:new String[]{"ec_p256","rsa2048"}){
                String alias="fixture-"+kind;
                JSONObject result=vm(HEX+"fn main(){let info=key_generate("+quoted(alias)+","+quoted(kind)+",\"any\");if !info || db_word(device_field(info,\"private_exportable\")){return 1;}let sig=key_sign("+quoted(alias)+",db_text(\"collie-keystore\"));if !sig || !db_word(key_verify("+quoted(alias)+",db_text(\"collie-keystore\"),sig)) || db_word(key_verify("+quoted(alias)+",db_text(\"changed\"),sig)){return 2;}hex(sig);db_io(0,1,\" \",1);hex(key_public("+quoted(alias)+"));if key_generate("+quoted(alias)+","+quoted(kind)+",\"any\"){return 3;}let e=device_error();if !worker_equal(db_word(db_at(e,0)),\"already_exists\"){return 4;}return 0;}");
                String[] data=result.getString("stdout").split(" ");String algorithm=kind.equals("ec_p256")?"EC":"RSA";PublicKey publicKey=KeyFactory.getInstance(algorithm).generatePublic(new X509EncodedKeySpec(unhex(data[1])));Signature verify=Signature.getInstance(algorithm.equals("EC")?"SHA256withECDSA":"SHA256withRSA");verify.initVerify(publicKey);verify.update("collie-keystore".getBytes("UTF-8"));check(verify.verify(unhex(data[0])),"Android Keystore "+kind+" signs from Flexscript; independent JCA verification accepts the exported public key and signature");
            }
            JSONObject hmac=vm(HEX+"fn main(){let info=key_generate(\"fixture-hmac\",\"hmac_sha256\",\"any\");if !info{return 1;}let sig=key_sign(\"fixture-hmac\",db_text(\"collie-keystore\"));if db_bytes(sig)!=32 || !db_word(key_verify(\"fixture-hmac\",db_text(\"collie-keystore\"),sig)) || db_word(key_verify(\"fixture-hmac\",db_text(\"changed\"),sig)){return 2;}hex(sig);if key_public(\"fixture-hmac\"){return 3;}let e=device_error();if !worker_equal(db_word(db_at(e,0)),\"wrong_key_type\"){return 4;}return 0;}");
            Mac mac=Mac.getInstance("HmacSHA256");mac.init(store.getKey(prefix+"fixture-hmac",null));check(MessageDigest.isEqual(mac.doFinal("collie-keystore".getBytes("UTF-8")),unhex(hmac.getString("stdout"))),"HMAC-SHA256 matches independent Android crypto and never exports secret key material");
            JSONObject aes=vm(HEX+"fn main(){if !key_generate(\"fixture-aes\",\"aes256\",\"any\"){return 1;}let p=alloc(256);let i=0;while i<256{store8(p+i,i);i=i+1;}let box=key_encrypt(\"fixture-aes\",db_blob(p,256),db_text(\"metadata\"));if !box{return 2;}let nonce=device_field(box,\"nonce\");let data=device_field(box,\"ciphertext\");let clear=key_decrypt(\"fixture-aes\",nonce,data,db_text(\"metadata\"));if db_bytes(clear)!=256{return 3;}i=0;while i<256{if load8(db_word(clear)+i)!=i{return 4;}i=i+1;}hex(nonce);db_io(0,1,\" \",1);hex(data);store8(db_word(data),load8(db_word(data))^1);if key_decrypt(\"fixture-aes\",nonce,data,db_text(\"metadata\")){return 5;}let e=device_error();if !worker_equal(db_word(db_at(e,0)),\"authentication_failed\"){return 6;}return 0;}");
            String[] sealed=aes.getString("stdout").split(" ");Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding");cipher.init(Cipher.DECRYPT_MODE,store.getKey(prefix+"fixture-aes",null),new GCMParameterSpec(128,unhex(sealed[0])));cipher.updateAAD("metadata".getBytes("UTF-8"));byte[] clear=cipher.doFinal(unhex(sealed[1]));boolean correct=clear.length==256;for(int i=0;i<clear.length;i++)correct&=(clear[i]&255)==i;check(correct,"AES-GCM preserves every binary byte, authenticates additional data and rejects modified ciphertext");
            JSONObject config=host.workerConfig(other,0);config.put("permissions",new JSONObject().put("keystore",true));JSONObject isolated=host.engineAt(other,3,new JSONObject().put("config",config).put("call_id","foreign-key").put("history",new JSONArray()).put("source","fn main(){if key_info(\"fixture-ec_p256\"){return 1;}let e=device_error();if !worker_equal(db_word(db_at(e,0)),\"not_found\"){return 2;}return 0;}"));
            check(isolated.optInt("exit_code",-1)==0,"keystore aliases are isolated between workspaces even when both have keystore permission");
            vm("fn main(){let p=alloc(32768);let i=0;while i<32768{store8(p+i,i%256);i=i+1;}let data=db_blob(p,32768);let sig=key_sign(\"fixture-hmac\",data);if !sig || !db_word(key_verify(\"fixture-hmac\",data,sig)){return 1;}let box=key_encrypt(\"fixture-aes\",db_blob(p,32752),db_blob(\"\",0));if !box{return 2;}let nonce=device_field(box,\"nonce\");let cipher=device_field(box,\"ciphertext\");if db_bytes(cipher)!=32768{return 3;}let clear=key_decrypt(\"fixture-aes\",nonce,cipher,db_blob(\"\",0));if db_bytes(clear)!=32752{return 4;}i=0;while i<32752{if load8(db_word(clear)+i)!=i%256{return 5;}i=i+1;}let other=key_encrypt(\"fixture-aes\",db_text(\"second\"),db_blob(\"\",0));if !other{return 6;}let next=device_field(other,\"nonce\");i=0;let same=1;while i<12{if load8(db_word(nonce)+i)!=load8(db_word(next)+i){same=0;}i=i+1;}if same{return 7;}return 0;}");
            check(store.getKey(prefix+"fixture-aes",null).getEncoded()==null&&store.getKey(prefix+"fixture-hmac",null).getEncoded()==null&&store.getKey(prefix+"fixture-ec_p256",null).getEncoded()==null&&store.getKey(prefix+"fixture-rsa2048",null).getEncoded()==null,"full-size messages work, AES-GCM creates fresh nonces, and Android exposes no encoded private or secret key bytes");
            vm("fn main(){let info=key_generate(\"fixture-required\",\"ec_p256\",\"hardware\");if info{if !db_word(device_field(info,\"inside_secure_hardware\")){return 1;}key_delete(\"fixture-required\");}else{let e=device_error();if !worker_equal(db_word(db_at(e,0)),\"hardware_unavailable\"){return 2;}if key_info(\"fixture-required\"){return 3;}}return 0;}");
            if(!host.getPackageManager().hasSystemFeature(android.content.pm.PackageManager.FEATURE_STRONGBOX_KEYSTORE))vm("fn main(){if key_generate(\"fixture-strongbox\",\"ec_p256\",\"strongbox\"){return 1;}let e=device_error();if !worker_equal(db_word(db_at(e,0)),\"unsupported\"){return 2;}if key_info(\"fixture-strongbox\"){return 3;}return 0;}");
            check(true,"required hardware backing is checked against Android metadata and absent StrongBox never silently falls back");
            vm("fn main(){let list=key_list(0,32);if db_count(device_field(list,\"aliases\"))!=4{return 1;}if key_generate(\"../escape\",\"aes256\",\"any\"){return 2;}let e=device_error();if !worker_equal(db_word(db_at(e,0)),\"invalid_argument\"){return 3;}if !db_word(key_delete(\"fixture-hmac\")) || db_word(key_delete(\"fixture-hmac\")){return 4;}return 0;}");
            check(true,"scoped key inventory, alias validation, duplicate protection and explicit deletion use Android Keystore");
        }finally{for(String alias:new String[]{"fixture-ec_p256","fixture-rsa2048","fixture-hmac","fixture-aes","fixture-required","fixture-strongbox"})store.deleteEntry(prefix+alias);}
    }
    public static JSONObject run(MainActivity host,File root)throws Exception{return new HardwareNetworkChecks(host,root).run();}
    public static JSONObject runMicrophone(MainActivity host,File root)throws Exception{return new HardwareNetworkChecks(host,root).microphone();}
    public static JSONObject runVpn(MainActivity host,File root)throws Exception{return new HardwareNetworkChecks(host,root).vpn();}
    public static JSONObject runCellular(MainActivity host,File root)throws Exception{return new HardwareNetworkChecks(host,root).cellular();}
    public static JSONObject runWifi(MainActivity host,File root)throws Exception{return new HardwareNetworkChecks(host,root).wifi();}
    public static JSONObject runWifiRequest(MainActivity host,File root)throws Exception{return new HardwareNetworkChecks(host,root).wifiRequest();}
    public static JSONObject runWifiRecovery(MainActivity host,File root)throws Exception{return new HardwareNetworkChecks(host,root).wifiRecovery();}
    public static JSONObject runRevocation(MainActivity host,File root)throws Exception{return new HardwareNetworkChecks(host,root).revocation();}
    public static JSONObject runAware(MainActivity host,File root)throws Exception{return new HardwareNetworkChecks(host,root).aware();}
    public static JSONObject runBluetooth(MainActivity host,File root)throws Exception{return new HardwareNetworkChecks(host,root).bluetooth();}
    private JSONObject bluetooth()throws Exception{
        android.bluetooth.BluetoothAdapter adapter=HardwareBluetooth.adapter(new VmHardware.Context(host,root));check(adapter.isEnabled(),"the test emulator provides an enabled real Android Bluetooth adapter");
        JSONObject info=vm(PRINT+"fn main(){let info=bt_info();if !info || !db_word(device_field(info,\"enabled\")) || db_kind(device_field(info,\"address\"))!=0{return 1;}emit(device_field(info,\"name\"));return 0;}");
        check(info.getString("stdout").equals(adapter.getName()),"Bluetooth VM metadata matches Android and does not export the local hardware MAC");
        vm("fn main(){let h=bt_watch();if !h{return 1;}let e=device_wait(db_word(h),1000);if !worker_equal(db_word(device_field(e,\"event\")),\"adapter\"){return 2;}if !db_word(device_field(device_field(e,\"value\"),\"enabled\")){return 3;}return device_close(db_word(h))-1;}");
        check(true,"adapter snapshots and copied state events cross the actual Bluetooth SDK/VM bridge");
        vm("fn main(){let list=bt_bonded(0,16);if !list || db_word(device_field(list,\"total\"))!="+adapter.getBondedDevices().size()+"{return 1;}let d=bt_device(\"02:00:00:00:00:01\");if !d{return 2;}let info=device_info(db_word(d));if !worker_equal(db_word(device_field(info,\"address\")),\"02:00:00:00:00:01\"){return 3;}let ids=bt_uuids(db_word(d),0);if !ids || db_word(device_field(ids,\"requested\")){return 4;}return device_close(db_word(d))-1;}");
        check(true,"bonded inventory matches Android; explicit device and cached UUID handles perform no pairing or remote connection");
        vm("fn main(){if bt_device(\"invalid\"){return 1;}let e=device_error();if !worker_equal(db_word(db_at(e,0)),\"invalid_argument\"){return 2;}if bt_scan(0) || bt_request_discoverable(0) || bt_request_discoverable(301) || bt_rfcomm_listen(\"fixture\",\"1101\",1){return 3;}e=device_error();if !worker_equal(db_word(db_at(e,0)),\"invalid_argument\"){return 4;}return 0;}");
        check(true,"invalid Bluetooth addresses, discovery durations and noncanonical service UUIDs fail before radio operations");
        String service=UUID.randomUUID().toString();
        try{
            vm("fn main(){let h=bt_rfcomm_listen(\"Collie emulator fixture\","+quoted(service)+",1);if !h{return 1;}state_set(\"bt_listener\",h);if bt_rfcomm_listen(\"duplicate\","+quoted(service)+",1){return 2;}let e=device_error();if !worker_equal(db_word(db_at(e,0)),\"busy\"){return 3;}let info=device_info(db_word(h));if !db_word(device_field(info,\"secure\")) || !worker_equal(db_word(device_field(info,\"uuid\")),"+quoted(service)+"){return 4;}return 0;}");
            check(true,"Android registers a real secure RFCOMM SDP listener and rejecting duplicate UUIDs preserves its owner");
            vm("fn main(){if bt_rfcomm_accept(db_word(state_get(\"bt_listener\")),150){return 1;}let e=device_error();if !worker_equal(db_word(db_at(e,0)),\"timeout\"){return 2;}if !device_info(db_word(state_get(\"bt_listener\"))){return 3;}return 0;}");
            check(true,"a real BluetoothServerSocket accept deadline reports timeout and preserves the listener for another accept");
            JSONObject handle=vm(PRINT+"fn main(){emit(state_get(\"bt_listener\"));return 0;}");File other=new File(root,"foreign-fixture");if(!other.isDirectory()&&!other.mkdirs())throw new IOException("Cannot create foreign Bluetooth fixture workspace.");JSONObject config=host.workerConfig(other,0);config.put("permissions",new JSONObject().put("bluetooth",true));
            JSONObject foreign=host.engineAt(other,3,new JSONObject().put("config",config).put("call_id","foreign-bluetooth").put("history",new JSONArray()).put("source","fn main(){if device_info("+quoted(handle.getString("stdout"))+"){return 1;}let e=device_error();if !worker_equal(db_word(db_at(e,0)),\"stale_handle\"){return 2;}return 0;}"));
            if(foreign.optInt("exit_code",-1)!=0)throw new IOException("Foreign Bluetooth VM: "+foreign);check(true,"an RFCOMM listener cannot be read or accepted from another conversation");
            VmHardware.revoke(root,"bluetooth");
            vm("fn main(){if device_info(db_word(state_get(\"bt_listener\"))){return 1;}let e=device_error();if !worker_equal(db_word(db_at(e,0)),\"stale_handle\"){return 2;}let h=bt_rfcomm_listen(\"Collie reopened fixture\","+quoted(service)+",1);if !h{return 3;}return device_close(db_word(h))-1;}");
            check(true,"revoking Bluetooth invalidates handles and releases the real SDP registration so the same UUID can be reopened");
        }finally{VmHardware.closeWorkspace(root);}
        return new JSONObject().put("ok",true).put("checks",checks).put("count",checks.length());
    }
    private JSONObject aware()throws Exception{
        check(!host.getPackageManager().hasSystemFeature(android.content.pm.PackageManager.FEATURE_WIFI_AWARE),"the headless Aware fixture confirms this emulator lacks NAN hardware");
        vm("fn main(){let info=aware_info();if !info || db_word(device_field(info,\"supported\")) || db_word(device_field(info,\"available\")){return 1;}let caps=hardware_capabilities();let i=0;let found=0;while i<db_count(caps){let c=db_at(caps,i);if worker_equal(db_word(device_field(c,\"id\")),\"wifi_aware\"){if !db_word(device_field(c,\"implemented\")) || db_word(device_field(c,\"supported\")) || db_word(device_field(c,\"available\")){return 2;}found=found+1;}i=i+1;}if found!=1{return 3;}return 0;}");
        check(true,"Aware metadata distinguishes implemented bindings from the actual absence of Android NAN support");
        vm("fn main(){if aware_open(){return 1;}let e=device_error();if !worker_equal(db_word(db_at(e,0)),\"unsupported\"){return 2;}if aware_watch(){return 3;}e=device_error();if !worker_equal(db_word(db_at(e,0)),\"unsupported\"){return 4;}return 0;}");
        check(true,"unsupported Aware attach/watch operations return structured platform errors instead of synthetic sessions or peers");
        try{
            vm("fn main(){let watch=wifi_watch();if !watch{return 1;}state_set(\"aware_wrong_type\",watch);if aware_publish(db_word(watch),\"collie\",db_blob(\"\",0),db_list(),0,0,0){return 2;}let e=device_error();if !worker_equal(db_word(db_at(e,0)),\"wrong_handle\"){return 3;}if aware_rtt(db_word(watch),db_list(),0){return 4;}e=device_error();if !worker_equal(db_word(db_at(e,0)),\"wrong_handle\"){return 5;}if aware_network(db_word(watch),\"peer-missing\",\"open\",db_blob(\"\",0),0,0,-1,1000){return 6;}e=device_error();if !worker_equal(db_word(db_at(e,0)),\"wrong_handle\"){return 7;}return device_close(db_word(watch))-1;}");
            check(true,"real handles of another adapter cannot be used to publish Aware services, open data paths or request peer ranging");
        }finally{VmHardware.closeWorkspace(root);}
        JSONObject reference=vm("fn main(){let api=hardware_api();if !api{return 1;}db_io(0,1,db_word(api),db_bytes(api));return 0;}");String api=reference.getString("stdout");
        check(api.contains("aware_publish(")&&api.contains("aware_network(")&&api.contains("aware_rtt(")&&api.contains("Wi-Fi RTT:")&&!api.contains("Aware and RTT APIs are not implemented"),"the VM's generated API reference exposes the real Aware/RTT functions and their asynchronous contracts");
        return new JSONObject().put("ok",true).put("checks",checks).put("count",checks.length());
    }
    private JSONObject revocation()throws Exception{
        java.lang.reflect.Field registryField=VmHardware.class.getDeclaredField("HANDLES");registryField.setAccessible(true);
        @SuppressWarnings("unchecked") Map<String,VmHardware.Handle> registry=(Map<String,VmHardware.Handle>)registryField.get(null);
        java.lang.reflect.Method save=MainActivity.class.getDeclaredMethod("savePermission",String.class,Object.class);save.setAccessible(true);
        java.lang.reflect.Method cancel=MainActivity.class.getDeclaredMethod("nativeCancel");cancel.setAccessible(true);
        ExecutorService execution=Executors.newSingleThreadExecutor();Future<JSONObject> running=null;boolean revoked=false;
        try{
            JSONObject config=host.workerConfig(root,0);check(config.getJSONObject("permissions").optBoolean("wifi"),"the live-revocation fixture starts with Wi-Fi allowed");
            running=execution.submit(()->host.engineAt(root,3,new JSONObject().put("config",config).put("call_id","live-revocation").put("history",new JSONArray()).put("source","fn main(){let h=wifi_watch();if !h{return 1;}let i=0;while i<10000{device_wait(db_word(h),1000);i=i+1;}return 2;}")));
            VmHardware.Handle observed=null;long until=System.nanoTime()+10000000000L;
            while(observed==null&&System.nanoTime()<until){synchronized(registry){for(VmHardware.Handle h:registry.values())if(h.root.equals(root)&&h.kind.equals("wifi_state")&&!h.closed){observed=h;break;}}if(observed==null){if(running.isDone())throw new IOException("The hardware loop exited before revocation: "+running.get());Thread.sleep(10);}}
            check(observed!=null,"a running VM actually opens an Android Wi-Fi watcher before its grant changes");
            CountDownLatch changed=new CountDownLatch(1);java.util.concurrent.atomic.AtomicReference<Throwable> failure=new java.util.concurrent.atomic.AtomicReference<>();
            host.runOnUiThread(()->{try{save.invoke(host,"wifi",false);}catch(Throwable error){failure.set(error);}finally{changed.countDown();}});if(!changed.await(4,TimeUnit.SECONDS))throw new IOException("UI permission update blocked on the running VM.");if(failure.get()!=null)throw new IOException(failure.get());revoked=true;
            JSONObject stopped=running.get(4,TimeUnit.SECONDS);check(stopped.optString("state").equals("error")&&stopped.optString("stderr").toLowerCase(Locale.ROOT).contains("cancel"),"revoking a grant stops the already-running native program instead of letting it reuse its configuration snapshot");
            check(observed.closed&&!host.workerConfig(root,0).getJSONObject("permissions").optBoolean("wifi"),"revocation closes the real handle and publishes the updated policy to subsequent execution");
            vm("fn main(){if wifi_watch(){return 1;}let e=device_error();if db_count(e)!=2 || !worker_equal(db_word(db_at(e,0)),\"permission_denied\"){return 2;}return 0;}");
            check(true,"a later program receives structured permission_denied and cannot reopen the revoked device");
        }finally{
            if(running!=null&&!running.isDone()){cancel.invoke(null);VmHardware.cancel();running.cancel(true);}execution.shutdownNow();VmHardware.closeWorkspace(root);
            if(revoked){CountDownLatch restored=new CountDownLatch(1);host.runOnUiThread(()->{try{save.invoke(host,"wifi",true);}catch(Exception ignored){}finally{restored.countDown();}});if(!restored.await(4,TimeUnit.SECONDS))throw new IOException("Test permission restoration timed out.");}
        }
        return new JSONObject().put("ok",true).put("checks",checks).put("count",checks.length());
    }
    private JSONObject wifi()throws Exception{
        android.net.wifi.WifiManager wm=host.getSystemService(android.net.wifi.WifiManager.class);
        try{
            vm("fn main(){let info=wifi_info();if !db_word(device_field(info,\"enabled\")){return 1;}let h=wifi_watch();if !h{return 2;}let e=device_wait(db_word(h),1000);if db_kind(e)!=5{return 3;}return device_close(db_word(h))-1;}");
            check(true,"Wi-Fi state/features and a bounded state watcher use the actual Android WifiManager");
            android.net.wifi.WifiInfo connection=wm.getConnectionInfo();JSONObject result=vm(PRINT+"fn main(){let info=wifi_connection();if db_kind(info)!=5{return 1;}emit(device_field(info,\"ssid\"));return 0;}");
            check(result.getString("stdout").equals(connection.getSSID()),"location-authorized primary Wi-Fi identity matches Android without exporting the device MAC");
            List<android.net.wifi.ScanResult> expected=wm.getScanResults();check(!expected.isEmpty(),"the emulator's virtual access point appears in Android scan results");
            vm("fn main(){let h=wifi_scan(0);if !h{return 1;}let e=device_wait(db_word(h),1000);if !worker_equal(db_word(device_field(e,\"source\")),\"cached\"){return 2;}let page=wifi_scan_page(db_word(h),0,16);if db_word(device_field(page,\"total\"))!="+Math.min(expected.size(),128)+"{return 3;}let list=device_field(page,\"access_points\");let i=0;let found=0;while i<db_count(list){let ap=db_at(list,i);if worker_equal(db_word(device_field(ap,\"bssid\")),"+quoted(expected.get(0).BSSID)+"){if db_word(device_field(ap,\"timestamp_us\"))<=0 || db_kind(device_field(ap,\"ssid_bytes\"))!=3{return 4;}found=1;}i=i+1;}if !found{return 5;}state_set(\"wifi_scan\",h);return 0;}");
            check(true,"cached scan snapshots preserve AP identity, raw SSID bytes and timestamps through typed bounded paging");
            vm("fn main(){let h=wifi_scan(1);if !h{let e=device_error();if db_count(e)!=2 || !worker_equal(db_word(db_at(e,0)),\"scan_throttled\"){return 1;}return 0;}let seen=0;let i=0;while i<20 && !seen{let e=device_wait(db_word(h),1000);if db_kind(e)==5 && worker_equal(db_word(device_field(e,\"event\")),\"scan\"){seen=1;}i=i+1;}if !seen{return 2;}let page=wifi_scan_page(db_word(h),0,16);if db_count(device_field(page,\"access_points\"))<1{return 3;}return device_close(db_word(h))-1;}");
            check(true,"requested Wi-Fi scans complete through Android scan broadcasts or report the platform throttle explicitly");
            vm("fn main(){if wifi_request(\"\",\"open\",\"\",\"\",0,1000){return 1;}let e=device_error();if db_count(e)!=2 || !worker_equal(db_word(db_at(e,0)),\"invalid_argument\"){return 2;}if wifi_request(\"test\",\"wpa2\",\"short\",\"\",0,1000){return 3;}if wifi_request(\"test\",\"open\",\"\",\"ff:ff:ff:ff:ff:ff\",0,1000){return 4;}if wifi_scan_page(db_word(state_get(\"wifi_scan\")),0,0){return 5;}return 0;}");
            check(true,"invalid SSIDs, passwords, BSSIDs and page limits fail before Nearby consent or connection requests");
            boolean rtt=host.getPackageManager().hasSystemFeature(android.content.pm.PackageManager.FEATURE_WIFI_RTT);
            vm("fn main(){let info=wifi_rtt_info();if db_word(device_field(info,\"supported\"))!="+(rtt?1:0)+"{return 1;}let caps=hardware_capabilities();let i=0;let found=0;while i<db_count(caps){let row=db_at(caps,i);if worker_equal(db_word(device_field(row,\"id\")),\"wifi_rtt\"){if !db_word(device_field(row,\"implemented\")) || db_word(device_field(row,\"supported\"))!="+(rtt?1:0)+"{return 2;}found=found+1;}i=i+1;}if found!=1{return 3;}return 0;}");
            check(true,"RTT capability metadata matches the actual Android hardware feature without claiming an available radio");
            vm("fn main(){let scan=db_word(state_get(\"wifi_scan\"));let targets=db_list();if wifi_rtt_range(scan,targets,0){return 1;}let e=device_error();if !worker_equal(db_word(db_at(e,0)),\"invalid_argument\"){return 2;}db_add(targets,db_text("+quoted(expected.get(0).BSSID)+"));db_add(targets,db_text("+quoted(expected.get(0).BSSID)+"));if wifi_rtt_range(scan,targets,0){return 3;}e=device_error();if !worker_equal(db_word(db_at(e,0)),\"invalid_argument\"){return 4;}return 0;}");
            check(true,"RTT rejects empty and duplicate targets before issuing a radio request, using the VM's real scan snapshot");
            if(!rtt){
                vm("fn main(){if wifi_rtt_watch(){return 1;}let e=device_error();if !worker_equal(db_word(db_at(e,0)),\"unsupported\"){return 2;}let targets=db_list();db_add(targets,db_text("+quoted(expected.get(0).BSSID)+"));if wifi_rtt_range(db_word(state_get(\"wifi_scan\")),targets,0){return 3;}e=device_error();if !worker_equal(db_word(db_at(e,0)),\"unsupported\"){return 4;}return 0;}");
                check(true,"an Android device without RTT returns structured unsupported for subscriptions and actual AP ranging instead of invented distances");
            }
            for(String key:new String[]{"wifi","location"}){
                JSONObject config=host.workerConfig(root,0);config.getJSONObject("permissions").put(key,false);
                JSONObject denied=host.engineAt(root,3,new JSONObject().put("config",config).put("call_id","wifi-deny-"+key).put("history",new JSONArray()).put("source","fn main(){if device_info(db_word(state_get(\"wifi_scan\"))){return 1;}let e=device_error();if db_count(e)!=2 || !worker_equal(db_word(db_at(e,0)),\"permission_denied\"){return 2;}return 0;}"));
                check(denied.optInt("exit_code",-1)==0,"scan snapshot handles enforce the "+key+" grant after creation");
            }
            VmHardware.revoke(root,"location");vm("fn main(){if device_info(db_word(state_get(\"wifi_scan\"))){return 1;}let e=device_error();if db_count(e)!=2 || !worker_equal(db_word(db_at(e,0)),\"stale_handle\"){return 2;}return 0;}");
            check(true,"revoking Location destroys Wi-Fi scan snapshots instead of leaving readable cached identities");
            String ssid="Collie-fixture-"+UUID.randomUUID().toString().substring(0,8);
            vm("fn main(){let h=wifi_suggest("+quoted(ssid)+",\"wpa2\",\"collie-test-key\",0,1,0);if !h{return 1;}let info=device_info(db_word(h));if db_kind(device_field(info,\"password\"))!=0 || db_word(device_field(info,\"autojoin\")){return 2;}state_set(\"wifi_suggestion\",h);let count=0;let i=0;while i<5 && !count{let e=device_wait(db_word(h),1000);if db_kind(e)==5{count=1;}i=i+1;}return 0;}");
            check(wm.getNetworkSuggestions().stream().anyMatch(s->ssid.equals(s.getSsid())&&!s.isInitialAutojoinEnabled()),"a VM suggestion is actually installed in Android with autojoin disabled and no credential echo");
            VmHardware.revoke(root,"wifi");check(wm.getNetworkSuggestions().stream().noneMatch(s->ssid.equals(s.getSsid())),"revoking Wi-Fi removes the suggestion from Android as well as invalidating the VM handle");
            JSONObject journal=new JSONObject(MainActivity.read(new FileInputStream(new File(host.getFilesDir(),"wifi-leases.json")),32768));check(journal.length()==0,"successful Wi-Fi suggestion removal clears its private crash-recovery journal");
        }finally{VmHardware.closeWorkspace(root);}
        return new JSONObject().put("ok",true).put("checks",checks).put("count",checks.length());
    }
    private JSONObject wifiRequest()throws Exception{
        VmHardware.Context context=new VmHardware.Context(host,root);Network network=HardwareNetwork.network(context,"wifi");android.net.LinkProperties properties=HardwareNetwork.manager(context).getLinkProperties(network);InetAddress local=null;for(android.net.LinkAddress address:properties.getLinkAddresses())if(address.getAddress() instanceof Inet4Address)local=address.getAddress();check(local!=null,"the approved virtual Wi-Fi connection has an IPv4 transport");
        try(ServerSocket server=new ServerSocket()){
            server.bind(new InetSocketAddress(local,0));server.setSoTimeout(8000);ExecutorService worker=Executors.newSingleThreadExecutor();Future<?> peer=worker.submit(()->{try(Socket client=server.accept()){byte[] bytes=new byte[512];new DataInputStream(client.getInputStream()).readFully(bytes);client.getOutputStream().write(bytes);}catch(Exception error){throw new RuntimeException(error);}});
            try{
                vm("fn main(){let h=state_get(\"wifi_request\");let info=device_info(db_word(h));if !worker_equal(db_word(device_field(info,\"state\")),\"available\"){return 1;}let n=device_field(info,\"network\");let socket=net_tcp_connect(db_word(n),"+quoted(local.getHostAddress())+","+server.getLocalPort()+",2000);if !socket{return 2;}let p=alloc(512);let i=0;while i<512{store8(p+i,i%256);i=i+1;}if db_word(device_write(db_word(socket),db_blob(p,512)))!=512{return 3;}let at=0;while at<512{let bytes=device_read(db_word(socket),512-at,2000);if !bytes || db_kind(bytes)!=3{return 4;}i=0;while i<db_bytes(bytes){if load8(db_word(bytes)+i)!=(at+i)%256{return 5;}i=i+1;}at=at+db_bytes(bytes);}device_close(db_word(socket));return device_close(db_word(h))-1;}");peer.get(4,TimeUnit.SECONDS);
                check(true,"the Android-approved WifiNetworkSpecifier lease yields a selector usable by VM TCP with all256 byte values");
            }finally{worker.shutdownNow();VmHardware.closeWorkspace(root);}
        }
        return new JSONObject().put("ok",true).put("checks",checks).put("count",checks.length());
    }
    private JSONObject wifiRecovery()throws Exception{
        android.net.wifi.WifiManager manager=host.getSystemService(android.net.wifi.WifiManager.class);
        long until=System.nanoTime()+8000000000L;while(manager.getNetworkSuggestions().stream().anyMatch(s->s.getSsid()!=null&&s.getSsid().startsWith("Collie-crash-"))&&System.nanoTime()<until)Thread.sleep(20);
        check(manager.getNetworkSuggestions().stream().noneMatch(s->s.getSsid()!=null&&s.getSsid().startsWith("Collie-crash-")),"process restart removes the orphan suggestion from the actual Android network store");
        File file=new File(host.getFilesDir(),"wifi-leases.json");check(!file.exists()||new JSONObject(MainActivity.read(new FileInputStream(file),32768)).length()==0,"process restart clears the recovery journal without recreating the old VM handle");
        return new JSONObject().put("ok",true).put("checks",checks).put("count",checks.length());
    }
    private JSONObject cellular()throws Exception{
        try{
            android.telephony.SubscriptionManager subscriptions=host.getSystemService(android.telephony.SubscriptionManager.class);
            List<android.telephony.SubscriptionInfo> active=subscriptions.getActiveSubscriptionInfoList();check(active!=null&&!active.isEmpty(),"the test emulator exposes an actual active Android subscription");
            int id=active.get(0).getSubscriptionId();android.telephony.TelephonyManager tm=host.getSystemService(android.telephony.TelephonyManager.class).createForSubscriptionId(id);
            JSONObject r=vm(PRINT+"fn main(){let page=cellular_subscriptions(0,16);let list=device_field(page,\"subscriptions\");if db_count(list)!="+active.size()+"{return 1;}let item=db_at(list,0);number(db_word(device_field(item,\"id\")));if db_kind(device_field(item,\"iccid\"))!=0 || db_kind(device_field(item,\"number\"))!=0{return 2;}return 0;}");
            check(r.getString("stdout").equals(Integer.toString(id)),"subscription inventory matches Android's visible active list without exporting ICCID or phone numbers");
            r=vm(PRINT+"fn main(){let info=cellular_info("+id+");if !info || db_kind(device_field(info,\"signal\"))!=5{return 1;}let signal=device_field(info,\"signal\");if db_count(device_field(signal,\"measurements\"))<1{return 2;}emit(device_field(info,\"operator\"));return 0;}");
            check(r.getString("stdout").equals(tm.getNetworkOperator()),"SIM/radio/operator and typed signal metrics cross the Flexscript VM and match Android TelephonyManager");
            vm("fn main(){let w=cellular_watch_subscriptions();if !w{return 1;}let e=device_wait(db_word(w),1000);if db_kind(e)!=5{return 2;}device_close(db_word(w));let r=cellular_watch("+id+");if !r{return 3;}let seen=0;let i=0;while i<5 && !seen{e=device_wait(db_word(r),1000);if db_kind(e)==5 && worker_equal(db_word(device_field(e,\"event\")),\"signal\"){seen=1;}i=i+1;}if !seen{return 4;}return device_close(db_word(r))-1;}");
            check(true,"Android subscription and radio callback registrations feed copied events and unregister on close");
            vm("fn main(){if cellular_subscriptions(0,0){return 1;}if cellular_cells(-1,2){return 2;}let e=device_error();if !worker_equal(db_word(db_at(e,0)),\"invalid_argument\"){return 3;}if cellular_info(2147483000){return 4;}e=device_error();if !worker_equal(db_word(db_at(e,0)),\"disconnected\"){return 5;}return 0;}");
            check(true,"invalid paging/refresh modes and inactive subscription IDs return structured errors before registering resources");
            List<android.telephony.CellInfo> original=tm.getAllCellInfo();check(original!=null&&!original.isEmpty(),"the emulator modem supplies real Android CellInfo records");
            long nci=-1;for(android.telephony.CellInfo cell:original)if(cell instanceof android.telephony.CellInfoNr)nci=((android.telephony.CellIdentityNr)((android.telephony.CellInfoNr)cell).getCellIdentity()).getNci();
            vm("fn main(){let h=cellular_cells("+id+",0);if !h{return 1;}let e=device_wait(db_word(h),1000);if !worker_equal(db_word(device_field(e,\"source\")),\"cached\"){return 2;}let page=cellular_cell_page(db_word(h),0,8);if db_word(device_field(page,\"total\"))!="+original.size()+"{return 3;}let cells=device_field(page,\"cells\");let i=0;let found=0;while i<db_count(cells){let cell=db_at(cells,i);if worker_equal(db_word(device_field(cell,\"type\")),\"nr\"){if db_word(device_field(device_field(cell,\"identity\"),\"nci\"))!="+nci+"{return 4;}found=1;}if db_word(device_field(cell,\"timestamp_ns\"))<=0{return 5;}i=i+1;}if !found{return 6;}state_set(\"cell_snapshot\",h);return 0;}");
            check(true,"cached cell snapshots preserve exact NR cell identity, typed signal data, timestamps and bounded paging through the VM");
            vm("fn main(){let h=cellular_cells("+id+",1);if !h{return 1;}let seen=0;let i=0;while i<8 && !seen{let e=device_wait(db_word(h),1000);if db_kind(e)==5 && worker_equal(db_word(device_field(e,\"event\")),\"cells\"){seen=1;}i=i+1;}if !seen{return 2;}let page=cellular_cell_page(db_word(h),0,8);if db_count(device_field(page,\"cells\"))<1{return 3;}return device_close(db_word(h))-1;}");
            check(true,"explicit cell refresh reaches Android requestCellInfoUpdate and completes through the asynchronous snapshot event");
            vm("fn main(){let s=cellular_service("+id+");if db_kind(device_field(s,\"state\"))!=1{return 1;}let h=cellular_watch_service("+id+");if !h{return 2;}let seen=0;let i=0;while i<5 && !seen{let e=device_wait(db_word(h),1000);if db_kind(e)==5 && worker_equal(db_word(device_field(e,\"event\")),\"service\"){seen=1;}i=i+1;}if !seen{return 3;}return device_close(db_word(h))-1;}");
            check(true,"service state snapshots and actual TelephonyCallback service events require the extra location permission");
            for(String key:new String[]{"cellular","location"}){
                JSONObject config=host.workerConfig(root,0);config.getJSONObject("permissions").put(key,false);
                JSONObject denied=host.engineAt(root,3,new JSONObject().put("config",config).put("call_id","cell-deny-"+key).put("history",new JSONArray()).put("source","fn main(){if device_info(db_word(state_get(\"cell_snapshot\"))){return 1;}let e=device_error();if db_count(e)!=2 || !worker_equal(db_word(db_at(e,0)),\"permission_denied\"){return 2;}return 0;}"));
                check(denied.optInt("exit_code",-1)==0,"live cell snapshot handles enforce the "+key+" grant on every operation");
            }
            VmHardware.revoke(root,"location");vm("fn main(){if device_info(db_word(state_get(\"cell_snapshot\"))){return 1;}let e=device_error();if !worker_equal(db_word(db_at(e,0)),\"stale_handle\"){return 2;}let h=cellular_cells("+id+",0);if !h{return 3;}state_set(\"cell_snapshot\",h);return 0;}");
            VmHardware.revoke(root,"cellular");vm("fn main(){if device_info(db_word(state_get(\"cell_snapshot\"))){return 1;}let e=device_error();if !worker_equal(db_word(db_at(e,0)),\"stale_handle\"){return 2;}return 0;}");
            check(true,"revoking either cell-data grant destroys the snapshot and prevents stale handle reuse");
        }finally{VmHardware.closeWorkspace(root);}
        return new JSONObject().put("ok",true).put("checks",checks).put("count",checks.length());
    }
    private static String vpnOpen(String selector){return "let addresses=db_list();let address=db_list();db_add(address,db_text(\"10.253.0.1\"));db_add(address,db_int(24));db_add(addresses,address);let routes=db_list();let route=db_list();db_add(route,db_text(\"0.0.0.0\"));db_add(route,db_int(0));db_add(routes,route);let vpn=vpn_open(\"Private emulator test\",addresses,routes,db_list(),1500,db_list(),"+quoted(selector)+");if !vpn{return 1;}";}
    private JSONObject vpn()throws Exception{
        VmHardware.Context context=new VmHardware.Context(host,root);Network physical=HardwareVpn.physical(context,"default");String selector=HardwareNetwork.id(physical);InetAddress local=HardwareNetwork.local(context,physical);
        try{
            vm("fn main(){let tcp=net_tcp_open("+quoted(selector)+");let udp=net_udp_open("+quoted(selector)+",0);if !tcp || !udp{return 2;}state_set(\"protected_tcp\",tcp);state_set(\"protected_udp\",udp);"+vpnOpen(selector)+"state_set(\"vpn\",vpn);let info=device_info(db_word(vpn));if db_word(device_field(info,\"mtu\"))!=1500 || db_word(device_field(info,\"encrypted\")) || db_count(device_field(info,\"apps\"))!=1{return 3;}let status=vpn_status();if !db_word(device_field(status,\"active\")) || !db_word(device_field(status,\"owned\")){return 4;}if !vpn_protect(db_word(vpn),db_word(tcp)) || !vpn_protect(db_word(vpn),db_word(udp)) || !vpn_underlying(db_word(vpn),"+quoted(selector)+"){return 5;}if device_read(db_word(vpn),100,1){return 6;}let e=device_error();if !worker_equal(db_word(db_at(e,0)),\"invalid_argument\"){return 7;}return 0;}");
            check(true,"Android establishes a foreground TUN, scopes default routing to Collie, protects TCP/UDP handles and validates packet buffer sizes");
            try(DatagramSocket client=new DatagramSocket(new InetSocketAddress(InetAddress.getByName("10.253.0.1"),0))){
                client.setSoTimeout(5000);byte[] original=new byte[512];for(int i=0;i<original.length;i++)original[i]=(byte)i;
                java.util.concurrent.atomic.AtomicBoolean finished=new java.util.concurrent.atomic.AtomicBoolean();ExecutorService sender=Executors.newSingleThreadExecutor();Future<?> sending=sender.submit(()->{try{for(int i=0;i<30&&!finished.get();i++){client.send(new DatagramPacket(original,original.length,InetAddress.getByName("10.253.0.2"),42621));Thread.sleep(100);}}catch(Exception error){if(!finished.get())throw new RuntimeException(error);}});
                try{
                vm(HEX+"fn main(){let vpn=state_get(\"vpn\");let packet=0;let attempts=0;while attempts<16 && !packet{let candidate=device_read(db_word(vpn),1500,1000);if db_kind(candidate)==3 && db_bytes(candidate)>=28{let p=db_word(candidate);let shown=db_bytes(candidate);if shown>64{shown=64;}hex(db_blob(p,shown));db_io(0,1,\"\\n\",1);let header=(load8(p)&15)*4;if (load8(p)>>4)==4 && header>=20 && load8(p+9)==17 && db_bytes(candidate)==header+8+512 && ((load8(p+header+2)<<8)|load8(p+header+3))==42621{packet=candidate;}}attempts=attempts+1;}if !packet{return 1;}let p=db_word(packet);let n=db_bytes(packet);let header=(load8(p)&15)*4;let i=0;while i<512{if load8(p+header+8+i)!=i%256{return 3;}i=i+1;}i=0;while i<4{let a=load8(p+12+i);store8(p+12+i,load8(p+16+i));store8(p+16+i,a);i=i+1;}i=0;while i<2{let a=load8(p+header+i);store8(p+header+i,load8(p+header+2+i));store8(p+header+2+i,a);i=i+1;}store8(p+header+6,0);store8(p+header+7,0);store8(p+10,0);store8(p+11,0);let sum=0;i=0;while i<header{sum=sum+(load8(p+i)<<8)+load8(p+i+1);i=i+2;}while sum>>16{sum=(sum&65535)+(sum>>16);}sum=(~sum)&65535;store8(p+10,sum>>8);store8(p+11,sum&255);if db_word(device_write(db_word(vpn),packet))!=n{return 4;}return 0;}");
                byte[] received=new byte[512];DatagramPacket reply=new DatagramPacket(received,received.length);client.receive(reply);check(reply.getLength()==512&&Arrays.equals(original,received)&&reply.getAddress().equals(InetAddress.getByName("10.253.0.2")),"real kernel UDP packets traverse TUN into Flexscript and a Flexscript-built IP reply returns all 256 binary byte values");
                }finally{finished.set(true);sending.cancel(true);sender.shutdownNow();}
            }
            try(ServerSocket server=new ServerSocket()){
                server.bind(new InetSocketAddress(local,0));server.setSoTimeout(8000);ExecutorService worker=Executors.newSingleThreadExecutor();Future<?> echo=worker.submit(()->{try(Socket client=server.accept()){client.setSoTimeout(4000);int b=client.getInputStream().read();client.getOutputStream().write(b);}catch(Exception error){throw new RuntimeException(error);}});
                try{vm("fn main(){let tcp=state_get(\"protected_tcp\");if !net_tcp_dial(db_word(tcp),"+quoted(local.getHostAddress())+","+server.getLocalPort()+",2000){return 1;}device_write(db_word(tcp),db_text(\"x\"));let bytes=device_read(db_word(tcp),1,2000);if db_bytes(bytes)!=1 || load8(db_word(bytes))!=120{return 2;}return device_close(db_word(tcp))-1;}");echo.get(4,TimeUnit.SECONDS);}finally{worker.shutdownNow();}
            }
            check(true,"a protected TCP socket is dialed after VPN establishment and communicates over its selected physical network");
            try(ServerSocket server=new ServerSocket()){
                server.bind(new InetSocketAddress(local,0));server.setSoTimeout(8000);ExecutorService worker=Executors.newSingleThreadExecutor();Future<?> peer=worker.submit(()->{try(Socket client=server.accept()){BufferedReader reader=new BufferedReader(new InputStreamReader(client.getInputStream(),"UTF-8"));while(!reader.readLine().isEmpty()){}client.getOutputStream().write("HTTP/1.1 200 OK\r\nContent-Length: 11\r\nConnection: close\r\n\r\noutside-vpn".getBytes("UTF-8"));}catch(Exception error){throw new RuntimeException(error);}});
                try{java.net.HttpURLConnection connection=(java.net.HttpURLConnection)HardwareVpn.modelConnection(new URL("http://"+local.getHostAddress()+":"+server.getLocalPort()+"/"));connection.setConnectTimeout(2000);connection.setReadTimeout(2000);try{ByteArrayOutputStream bytes=new ByteArrayOutputStream();InputStream input=connection.getInputStream();int b;while((b=input.read())!=-1)bytes.write(b);check(bytes.toString("UTF-8").equals("outside-vpn"),"default model transport selects an underlying network outside Collie's own full-route VPN");}finally{connection.disconnect();}peer.get(4,TimeUnit.SECONDS);}finally{worker.shutdownNow();}
            }
            vm("fn main(){let vpn=state_get(\"vpn\");if !device_close(db_word(vpn)){return 1;}let status=vpn_status();if db_word(device_field(status,\"active\")){return 2;}device_close(db_word(state_get(\"protected_udp\")));return 0;}");
            check(true,"closing the VM VPN handle tears down its interface and clears the active lease");
        }finally{VmHardware.closeWorkspace(root);}
        return new JSONObject().put("ok",true).put("checks",checks).put("count",checks.length());
    }
    private JSONObject microphone()throws Exception{
        try{
            vm("fn main(){let h=audio_input_open(\"default\",16000,1);if !h{return 1;}let info=device_info(db_word(h));if db_word(device_field(info,\"channels\"))!=1{return 2;}let bytes=device_read(db_word(h),4096,2000);if !bytes || db_bytes(bytes)<2 || db_bytes(bytes)%2{return 3;}if !audio_control(db_word(h),\"pause\"){return 4;}if device_read(db_word(h),64,100){return 5;}let e=device_error();if !worker_equal(db_word(db_at(e,0)),\"not_running\"){return 6;}if !audio_control(db_word(h),\"start\"){return 7;}state_set(\"microphone\",h);return 0;}");
            check(true,"microphone PCM capture, format metadata and pause/restart work through AudioRecord");
            host.runOnUiThread(()->host.moveTaskToBack(true));long until=System.nanoTime()+5000000000L;while(host.hardwareVisible&&System.nanoTime()<until)Thread.sleep(20);check(!host.hardwareVisible,"Android actually moves Collie out of the foreground");
            vm("fn main(){let h=state_get(\"microphone\");if device_info(db_word(h)){return 1;}let e=device_error();if !worker_equal(db_word(db_at(e,0)),\"stale_handle\"){return 2;}if audio_input_open(\"default\",16000,1){return 3;}e=device_error();if !worker_equal(db_word(db_at(e,0)),\"foreground_required\"){return 4;}return 0;}");
            check(true,"hiding Collie closes microphone handles and prevents background capture without a foreground service");
        }finally{VmHardware.closeWorkspace(root);host.runOnUiThread(()->host.startActivity(new android.content.Intent(host,MainActivity.class).addFlags(android.content.Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)));long until=System.nanoTime()+5000000000L;while(!host.hardwareVisible&&System.nanoTime()<until)Thread.sleep(20);}
        return new JSONObject().put("ok",true).put("checks",checks).put("count",checks.length());
    }
    private void audioMidi()throws Exception{
        vm("fn main(){if midi_bluetooth_open(\"invalid\"){return 1;}let e=device_error();if !worker_equal(db_word(db_at(e,0)),\"invalid_argument\"){return 2;}return 0;}");
        check(true,"invalid Bluetooth MIDI addresses fail before Bluetooth runtime consent or radio access");
        vm("fn main(){let page=audio_devices(0,16);if !page || db_kind(device_field(page,\"devices\"))!=5{return 1;}let watch=audio_watch();if !watch{return 2;}let e=device_wait(db_word(watch),1000);if db_kind(e)!=5{return 3;}device_close(db_word(watch));let h=audio_output_open(\"default\",16000,1);if !h{return 4;}if !audio_volume(db_word(h),0){return 5;}let p=alloc(3200);let i=0;while i<3200{store8(p+i,0);i=i+1;}let n=device_write(db_word(h),db_blob(p,3200));if !n || db_word(n)<2 || db_word(n)%2{return 6;}let info=device_info(db_word(h));if !worker_equal(db_word(device_field(info,\"encoding\")),\"pcm_s16le\"){return 7;}if !audio_control(db_word(h),\"pause\") || !audio_control(db_word(h),\"flush\") || !audio_route(db_word(h),\"default\") || !audio_control(db_word(h),\"start\"){return 8;}if device_write(db_word(h),db_blob(\"x\",1)){return 9;}let error=device_error();if !worker_equal(db_word(db_at(error,0)),\"invalid_argument\"){return 10;}return device_close(db_word(h))-1;}");
        check(true,"audio inventory/events, silent PCM playback, volume, routing, pause/flush/restart and frame validation use Android media services");
        vm("fn main(){let list=midi_list(0,32);if !list{return 1;}let devices=device_field(list,\"devices\");let id=0;let i=0;while i<db_count(devices){let d=db_at(devices,i);if worker_equal(db_word(device_field(d,\"name\")),\"Collie MIDI test loopback\"){id=device_field(d,\"id\");}i=i+1;}if !id{return 2;}let ports=midi_ports(db_word(id),0,32);if db_count(device_field(ports,\"ports\"))!=2{return 3;}let watch=midi_watch();if !watch{return 4;}let device=midi_open(db_word(id));if !device{return 5;}let input=midi_port_open(db_word(device),\"receive\",0);let output=midi_port_open(db_word(device),\"send\",0);if !input || !output{return 6;}let busy=midi_port_open(db_word(device),\"send\",0);if busy{return 7;}let e=device_error();if !worker_equal(db_word(db_at(e,0)),\"busy\"){return 8;}let p=alloc(32768);i=0;while i<32768{store8(p+i,i%256);i=i+1;}if db_word(midi_send(db_word(output),db_blob(p,32768),123456789))!=32768{return 9;}let at=0;i=0;while at<32768 && i<128{let event=device_wait(db_word(input),1000);if db_kind(event)==5 && worker_equal(db_word(device_field(event,\"event\")),\"message\"){let bytes=device_field(event,\"data\");let j=0;while j<db_bytes(bytes){if load8(db_word(bytes)+j)!=(at+j)%256{return 10;}j=j+1;}at=at+db_bytes(bytes);if db_word(device_field(event,\"timestamp_ns\"))!=123456789{return 11;}}i=i+1;}if at!=32768{return 12;}if !midi_flush(db_word(output)){return 13;}let flushed=0;i=0;while i<5 && !flushed{let event=device_wait(db_word(input),1000);if db_kind(event)==5 && worker_equal(db_word(device_field(event,\"event\")),\"flush\"){flushed=1;}i=i+1;}if !flushed{return 14;}device_close(db_word(device));if device_info(db_word(input)){return 15;}e=device_error();if !worker_equal(db_word(db_at(e,0)),\"stale_handle\"){return 16;}device_close(db_word(watch));return 0;}");
        check(true,"32 KiB MIDI loopback preserves binary bytes/timestamps through the Android service, enforces exclusive input ports and closes child ports");
    }
    private void nsd(VmHardware.Context context,Network network,InetAddress local)throws Exception{
        String type="_cf"+UUID.randomUUID().toString().substring(0,8)+"._tcp.",name="collie-"+UUID.randomUUID().toString().substring(0,8),selector=HardwareNetwork.id(network);
        try(ServerSocket server=new ServerSocket()){
            server.bind(new InetSocketAddress(local,0));server.setSoTimeout(20000);ExecutorService worker=Executors.newSingleThreadExecutor();Future<?> echo=worker.submit(()->{try(Socket client=server.accept()){client.setSoTimeout(4000);byte[] data=new byte[5];new DataInputStream(client.getInputStream()).readFully(data);client.getOutputStream().write(data);}catch(Exception error){throw new RuntimeException(error);}});
            try{
                vm("fn main(){let attributes=db_list();let row=db_list();db_add(row,db_text(\"vm\"));db_add(row,db_text(\"flexscript\"));db_add(attributes,row);let registration=nsd_register("+quoted(name)+","+quoted(type)+","+server.getLocalPort()+",attributes,"+quoted(selector)+");if !registration{return 1;}state_set(\"nsd_registration\",registration);let browser=nsd_browse("+quoted(type)+","+quoted(selector)+");if !browser{return 2;}state_set(\"nsd_browser\",browser);let i=0;let id=0;while i<12 && !id{let event=device_wait(db_word(browser),1000);if db_kind(event)==5 && worker_equal(db_word(device_field(event,\"event\")),\"found\"){let service=device_field(event,\"service\");if worker_equal(db_word(device_field(service,\"name\")),"+quoted(name)+"){id=device_field(event,\"id\");}}i=i+1;}if !id{return 3;}state_set(\"nsd_service\",id);let resolved=nsd_resolve(db_word(browser),db_word(id));if !resolved || db_word(device_field(resolved,\"port\"))!="+server.getLocalPort()+"{return 4;}let txt=device_field(resolved,\"attributes\");let value=device_field(txt,\"vm\");if db_kind(value)!=3 || !worker_equal(db_word(value),\"flexscript\"){return 5;}let addresses=device_field(resolved,\"addresses\");i=0;let found=0;while i<db_count(addresses){if worker_equal(db_word(db_at(addresses,i)),"+quoted(local.getHostAddress())+"){found=1;}i=i+1;}if !found{return 6;}let socket=net_tcp_connect("+quoted(selector)+","+quoted(local.getHostAddress())+","+server.getLocalPort()+",2000);if !socket{return 7;}device_write(db_word(socket),db_text(\"hello\"));let data=device_read(db_word(socket),5,2000);if db_bytes(data)!=5 || !worker_equal(db_word(data),\"hello\"){return 8;}device_close(db_word(socket));return 0;}");echo.get(4,TimeUnit.SECONDS);
                check(true,"DNS-SD advertises and discovers a unique local service on the selected Android Network, resolves binary TXT/address metadata and reaches its TCP endpoint");
                vm("fn main(){let browser=state_get(\"nsd_browser\");let id=state_get(\"nsd_service\");let page=nsd_services(db_word(browser),0,32);if db_count(device_field(page,\"services\"))<1{return 1;}let watch=nsd_watch_service(db_word(browser),db_word(id));if !watch{return 2;}let updated=0;let i=0;while i<8 && !updated{let event=device_wait(db_word(watch),1000);if db_kind(event)==5 && worker_equal(db_word(device_field(event,\"event\")),\"updated\"){updated=1;}i=i+1;}if !updated{return 3;}device_close(db_word(browser));if device_info(db_word(watch)){return 4;}let error=device_error();if !worker_equal(db_word(db_at(error,0)),\"stale_handle\"){return 5;}return device_close(db_word(state_get(\"nsd_registration\")))-1;}");
                check(true,"DNS-SD service update callbacks, scoped inventory and parent/child cleanup use Android NsdManager");
            }finally{worker.shutdownNow();}
        }
        vm("fn main(){if nsd_browse(\"invalid\",\"default\"){return 1;}let e=device_error();if !worker_equal(db_word(db_at(e,0)),\"invalid_argument\"){return 2;}let browser=nsd_browse("+quoted(type)+",\"default\");if !browser{return 3;}if nsd_resolve(db_word(browser),\"service-foreign\"){return 4;}e=device_error();if !worker_equal(db_word(db_at(e,0)),\"stale_service\"){return 5;}return device_close(db_word(browser))-1;}");
        check(true,"DNS-SD rejects malformed types and unknown service IDs without resolving arbitrary host names");
    }
    private JSONObject run()throws Exception{
        VmHardware.Context context=new VmHardware.Context(host,root);Network network=HardwareNetwork.network(context,"default");InetAddress local=HardwareNetwork.local(context,network);String selector=HardwareNetwork.id(network),address=local.getHostAddress();
        vm("fn main(){let c=hardware_capabilities();if !c || db_count(c)<5{return 1;}let n=net_list();if !n || db_count(n)<1{return 2;}let i=net_info("+quoted(selector)+");if db_kind(device_field(i,\"addresses\"))!=5{return 3;}let ips=net_resolve("+quoted(selector)+","+quoted(address)+");if db_count(ips)<1{return 4;}return 0;}");
        check(true,"network inventory, explicit ID selection, link metadata and resolver use actual Android networks");
        try(ServerSocket server=new ServerSocket()){
            server.bind(new InetSocketAddress(local,0));ExecutorService worker=Executors.newSingleThreadExecutor();
            Future<?> echo=worker.submit(()->{try(Socket client=server.accept()){byte[] bytes=new byte[256];new DataInputStream(client.getInputStream()).readFully(bytes);client.getOutputStream().write(bytes);}catch(Exception error){throw new RuntimeException(error);}});
            try{
                vm("fn main(){let h=net_tcp_connect("+quoted(selector)+","+quoted(address)+","+server.getLocalPort()+",2000);if !h{return 1;}let b=alloc(256);let i=0;while i<256{store8(b+i,i);i=i+1;}if db_word(device_write(db_word(h),db_blob(b,256)))!=256{return 2;}let at=0;while at<256{let v=device_read(db_word(h),256-at,2000);if db_kind(v)!=3 || !db_bytes(v){return 3;}i=0;while i<db_bytes(v){if load8(db_word(v)+i)!=(at+i)%256{return 4;}i=i+1;}at=at+db_bytes(v);}if !device_close(db_word(h)){return 5;}return 0;}");echo.get(4,TimeUnit.SECONDS);
            }finally{worker.shutdownNow();}
        }
        check(true,"TCP connect/write/read/close preserves all 256 binary byte values across the VM bridge");
        try(DatagramSocket echo=new DatagramSocket(new InetSocketAddress(local,0))){
            echo.setSoTimeout(4000);ExecutorService worker=Executors.newSingleThreadExecutor();
            Future<?> job=worker.submit(()->{try{byte[] bytes=new byte[1024];DatagramPacket packet=new DatagramPacket(bytes,bytes.length);echo.receive(packet);echo.send(new DatagramPacket(packet.getData(),packet.getLength(),packet.getAddress(),packet.getPort()));}catch(Exception error){throw new RuntimeException(error);}});
            try{
                vm("fn main(){let h=net_udp_open("+quoted(selector)+",0);if !h{return 1;}let b=alloc(4);store8(b,0);store8(b+1,255);store8(b+2,128);store8(b+3,42);if db_word(net_udp_send(db_word(h),"+quoted(address)+","+echo.getLocalPort()+",db_blob(b,4)))!=4{return 2;}let r=net_udp_receive(db_word(h),1024,2000);let v=device_field(r,\"data\");if db_bytes(v)!=4 || load8(db_word(v))!=0 || load8(db_word(v)+1)!=255 || load8(db_word(v)+2)!=128 || load8(db_word(v)+3)!=42{return 3;}return device_close(db_word(h))-1;}");job.get(4,TimeUnit.SECONDS);
            }finally{worker.shutdownNow();}
        }
        check(true,"UDP datagrams retain source metadata and binary payloads on the selected network");
        try(ServerSocket server=new ServerSocket()){
            server.bind(new InetSocketAddress(local,0));ExecutorService worker=Executors.newSingleThreadExecutor();
            Future<?> job=worker.submit(()->{try(Socket client=server.accept()){client.setSoTimeout(4000);BufferedReader reader=new BufferedReader(new InputStreamReader(client.getInputStream(),"UTF-8"));String line;while((line=reader.readLine())!=null && !line.isEmpty()){if(line.toLowerCase(Locale.ROOT).startsWith("authorization:") && !line.trim().equalsIgnoreCase("authorization:"))throw new IOException("Unexpected authorization header.");}client.getOutputStream().write("HTTP/1.1 200 OK\r\nContent-Length: 11\r\nConnection: close\r\n\r\nhardware-ok".getBytes("UTF-8"));}catch(Exception error){throw new RuntimeException(error);}});
            try{
                vm("fn main(){let r=net_http("+quoted(selector)+","+quoted("http://"+address+":"+server.getLocalPort()+"/status")+",2000);if !r || db_word(device_field(r,\"status\"))!=200{return 1;}let body=device_field(r,\"body\");if db_bytes(body)!=11 || !worker_equal(db_word(body),\"hardware-ok\"){return 2;}return 0;}");job.get(4,TimeUnit.SECONDS);
            }finally{worker.shutdownNow();}
        }
        check(true,"HTTP device requests use the selected Network and return bounded binary bodies without model credentials");
        JSONObject opened=vm(PRINT+"fn main(){let h=net_tcp_listen("+quoted(selector)+",0,4);if !h{return 1;}state_set(\"listener\",h);let info=device_info(db_word(h));number(db_word(device_field(info,\"port\")));return 0;}");int port=Integer.parseInt(opened.getString("stdout"));
        try(Socket client=new Socket(local,port)){
            client.setSoTimeout(4000);client.getOutputStream().write(new byte[]{17,42});
            vm("fn main(){let server=state_get(\"listener\");let client=net_tcp_accept(db_word(server),2000);if !client{return 1;}let bytes=device_read(db_word(client),2,2000);if db_bytes(bytes)!=2 || load8(db_word(bytes))!=17 || load8(db_word(bytes)+1)!=42{return 2;}device_write(db_word(client),db_text(\"reply\"));device_close(db_word(client));return device_close(db_word(server))-1;}");
            byte[] reply=new byte[5];new DataInputStream(client.getInputStream()).readFully(reply);check(Arrays.equals(reply,"reply".getBytes("UTF-8")),"TCP listener/accept binds the selected interface and survives ordinary VM program boundaries");
        }
        vm("fn main(){let w=net_watch();if !w{return 1;}let event=device_wait(db_word(w),1000);if db_kind(event)!=5 || db_kind(device_field(event,\"event\"))!=2{return 2;}return device_close(db_word(w))-1;}");
        check(true,"Android connectivity callbacks feed a bounded event handle without guest callbacks");
        vm("fn main(){let h=net_udp_open("+quoted(selector)+",0);if !h{return 1;}state_set(\"owned\",h);return 0;}");
        File other=new File(root.getParentFile(),root.getName()+"-foreign");new File(other,"files").mkdirs();
        String foreign=new JSONObject(host.engineAt(root,3,new JSONObject().put("config",host.workerConfig(root,0)).put("call_id","export-handle").put("history",new JSONArray()).put("source",PRINT+"fn main(){emit(state_get(\"owned\"));return 0;}" )).toString()).getString("stdout");
        JSONObject denied=host.engineAt(other,3,new JSONObject().put("config",host.workerConfig(other,0)).put("call_id","foreign-handle").put("history",new JSONArray()).put("source","fn main(){if device_info("+quoted(foreign)+"){return 1;}let e=device_error();if db_count(e)!=2 || !worker_equal(db_word(db_at(e,0)),\"stale_handle\"){return 2;}return 0;}"));
        check(denied.getInt("exit_code")==0,"opaque handles cannot be used from another workspace");
        VmHardware.revoke(root,"network");
        vm("fn main(){let h=state_get(\"owned\");if device_info(db_word(h)){return 1;}let e=device_error();if !worker_equal(db_word(db_at(e,0)),\"stale_handle\"){return 2;}return 0;}");
        check(true,"revocation closes network resources and reports structured stale-handle errors");
        vm("fn main(){let r=net_tcp_connect(\"default\",\"127.0.0.1\",70000,100);if r{return 1;}let e=device_error();if !worker_equal(db_word(db_at(e,0)),\"invalid_argument\"){return 2;}return 0;}");
        check(true,"invalid port arguments are rejected before opening a connection");
        vm("fn main(){let info=battery_info();if !info || db_kind(device_field(info,\"level\"))!=1{return 1;}let h=battery_watch();if !h{return 2;}let e=device_wait(db_word(h),1000);if db_kind(e)!=5{return 3;}return device_close(db_word(h))-1;}");
        check(true,"battery status and sticky broadcast events cross the real VM bridge");
        vm("fn main(){let info=thermal_info(0);if !info || db_kind(device_field(info,\"status\"))!=1{return 1;}let h=thermal_watch();if !h{return 2;}let e=device_wait(db_word(h),1000);if db_kind(e)!=5{return 3;}return device_close(db_word(h))-1;}");
        check(true,"thermal status and listener resources use Android PowerManager");
        vm("fn main(){let page=sensor_list();let list=device_field(page,\"sensors\");let i=0;let chosen=0;while i<db_count(list){let s=db_at(list,i);if db_word(device_field(s,\"type\"))==1{chosen=s;}i=i+1;}if !chosen{return 1;}let id=device_field(chosen,\"id\");let h=sensor_open(db_word(id),20000);if !h{return 2;}i=0;while i<5{let e=device_wait(db_word(h),1000);if db_kind(e)==5 && worker_equal(db_word(device_field(e,\"event\")),\"sample\"){let values=device_field(e,\"values\");if db_count(values)<3 || db_kind(db_at(values,0))!=4{return 3;}return device_close(db_word(h))-1;}i=i+1;}return 4;}");
        check(true,"accelerometer callbacks preserve timestamps and floating-point sensor values");
        vm("fn main(){let ir=ir_info();if !ir{return 1;}let h=haptic_info();if !h{return 2;}return 0;}");
        check(true,"actuator inventory reports actual vibration and infrared availability without emitting output");
        vm("fn main(){let page=usb_list(0,16);if !page || db_kind(device_field(page,\"devices\"))!=5 || db_kind(device_field(page,\"total\"))!=1{return 1;}let a=usb_accessories();if db_kind(a)!=5{return 2;}let w=usb_watch();if !w{return 3;}let e=device_wait(db_word(w),1000);if db_kind(e)!=5 || !worker_equal(db_word(device_field(e,\"event\")),\"ready\"){return 4;}return device_close(db_word(w))-1;}");
        check(true,"USB inventory, accessory inventory and attach/detach subscription use Android UsbManager");
        vm("fn main(){if usb_list(0,0){return 1;}let e=device_error();if !worker_equal(db_word(db_at(e,0)),\"invalid_argument\"){return 2;}if usb_open(\"usb-nonexistent\"){return 3;}e=device_error();if !worker_equal(db_word(db_at(e,0)),\"disconnected\"){return 4;}let h=net_udp_open(\"default\",0);if !h{return 5;}if usb_descriptors(db_word(h)){return 6;}e=device_error();if !worker_equal(db_word(db_at(e,0)),\"wrong_handle\"){return 7;}return device_close(db_word(h))-1;}");
        check(true,"USB invalid ranges, absent devices and foreign handle types return structured errors without device I/O");
        vm("fn main(){let p=serial_port(\"unknown\",1,0,0,0);if serial_open(\"not-opened\",p,0){return 1;}let e=device_error();if !worker_equal(db_word(db_at(e,0)),\"unsupported_driver\"){return 2;}if db_word(serial_ftdi_divisor(115200))!=26 || db_word(serial_ch_divisor(115200))!=0xcc03{return 3;}let api=hardware_api();if !api || db_bytes(api)<1000{return 4;}return 0;}");
        check(true,"the Android guest preloads the Flexscript serial drivers and rejects invalid protocols before USB access");
        keystore(context,other);
        audioMidi();
        nsd(context,network,local);
        VmHardware.closeWorkspace(root);return new JSONObject().put("ok",true).put("checks",checks).put("count",checks.length());
    }
}
