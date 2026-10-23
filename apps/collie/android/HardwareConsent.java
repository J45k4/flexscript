package org.flexscript.collie;

import android.content.pm.PackageManager;
import android.app.PendingIntent;
import android.content.Intent;
import android.net.Uri;
import java.io.IOException;
import java.util.ArrayDeque;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import org.json.*;

/** Android permission-dialog lifecycle. Called only after the VM has yielded. */
final class HardwareConsent {
    private final MainActivity host;
    private final ArrayDeque<Pending> queue=new ArrayDeque<>();
    private int sequence=2000;
    private static final Map<String,HardwareConsent> USB_REQUESTS=new HashMap<>();
    private static final class Pending {
        final PlatformTask task;final JSONObject signal;
        final CountDownLatch ready=new CountDownLatch(1);
        int code;boolean abandoned;String token;PendingIntent callback;String[] permissions;volatile Exception error;
        Pending(PlatformTask task,JSONObject signal){this.task=task;this.signal=signal;}
    }
    HardwareConsent(MainActivity host){this.host=host;}
    void await(PlatformTask task,JSONObject signal)throws Exception{
        Pending pending=new Pending(task,new JSONObject(signal.toString()));
        host.runOnUiThread(()->{queue.add(pending);show();});
        try{
            while(!pending.ready.await(200,TimeUnit.MILLISECONDS)){
                task.check();if(!host.ownsPermissionRequest(task.root))throw new IOException("Android permission request belongs to a closed conversation.");
            }
            task.check();if(pending.error!=null)throw pending.error;
        }finally{host.runOnUiThread(()->{if(pending.code!=0 && queue.peek()==pending){pending.abandoned=true;}else queue.remove(pending);show();});}
    }
    private void show(){
        Pending pending=queue.peek();if(pending==null || pending.code!=0)return;
        try{
            pending.task.check();if(!host.ownsPermissionRequest(pending.task.root))throw new IOException("Conversation closed.");
            JSONObject request=pending.signal.getJSONObject("request");
            String type=request.getString("type");
            if(type.equals("vpn")){
                Intent intent=android.net.VpnService.prepare(host);if(intent==null){complete(pending);return;}
                pending.code=++sequence;host.startActivityForResult(intent,pending.code);return;
            }
            if(type.equals("usb_device")||type.equals("usb_accessory")){
                if(HardwareUsb.permitted(host,request)){complete(pending);return;}
                pending.code=++sequence;pending.token=UUID.randomUUID().toString();USB_REQUESTS.put(pending.token,this);
                Intent intent=new Intent(host,UsbConsentReceiver.class).setAction("org.flexscript.collie.USB_PERMISSION").setData(Uri.parse("collie-usb-consent:"+pending.token)).putExtra("token",pending.token);
                pending.callback=PendingIntent.getBroadcast(host,pending.code,intent,PendingIntent.FLAG_IMMUTABLE|PendingIntent.FLAG_ONE_SHOT);
                HardwareUsb.request(host,request,pending.callback);return;
            }
            if(!type.equals("runtime"))throw new IOException("Unsupported Android consent type.");
            JSONArray values=request.getJSONArray("permissions");ArrayDeque<String> missing=new ArrayDeque<>();
            if(request.optBoolean("any")){for(int i=0;i<values.length();i++)if(host.checkSelfPermission(values.getString(i))==PackageManager.PERMISSION_GRANTED){queue.remove();pending.ready.countDown();show();return;}}
            for(int i=0;i<values.length();i++){String permission=values.getString(i);if(host.checkSelfPermission(permission)!=PackageManager.PERMISSION_GRANTED)missing.add(permission);}
            if(missing.isEmpty()){queue.remove();pending.ready.countDown();show();return;}
            if(missing.contains("android.permission.ACCESS_FINE_LOCATION") && !missing.contains("android.permission.ACCESS_COARSE_LOCATION"))missing.add("android.permission.ACCESS_COARSE_LOCATION");
            pending.permissions=missing.toArray(new String[0]);pending.code=++sequence;host.requestPermissions(pending.permissions,pending.code);
        }catch(Exception error){pending.error=error;complete(pending);}
    }
    private void complete(Pending pending){if(pending.token!=null)USB_REQUESTS.remove(pending.token);if(pending.callback!=null)pending.callback.cancel();queue.remove(pending);pending.ready.countDown();show();}
    static void usbResult(String token){HardwareConsent consent=USB_REQUESTS.get(token);if(consent!=null)consent.usbCompleted(token);}
    private void usbCompleted(String token){
        Pending pending=queue.peek();if(pending==null||!token.equals(pending.token))return;
        try{if(!pending.abandoned){pending.task.check();if(!host.ownsPermissionRequest(pending.task.root))throw new IOException("Conversation closed.");if(!HardwareUsb.permitted(host,pending.signal.getJSONObject("request")))host.savePermission(pending.signal.getString("key"),false);}}
        catch(Exception error){pending.error=error;}
        complete(pending);
    }
    void close(){for(Pending pending:queue){pending.error=new IOException("Android permission request cancelled because the activity closed.");if(pending.token!=null)USB_REQUESTS.remove(pending.token);if(pending.callback!=null)pending.callback.cancel();pending.ready.countDown();}queue.clear();}
    boolean activityResult(int code,int resultCode){
        Pending pending=queue.peek();if(pending==null||pending.code!=code||!pending.signal.optJSONObject("request").optString("type").equals("vpn"))return false;
        try{if(!pending.abandoned){pending.task.check();if(!host.ownsPermissionRequest(pending.task.root))throw new IOException("Conversation closed.");if(resultCode!=android.app.Activity.RESULT_OK||android.net.VpnService.prepare(host)!=null)host.savePermission(pending.signal.getString("key"),false);}}
        catch(Exception error){pending.error=error;}
        complete(pending);return true;
    }
    void result(int code,String[] permissions,int[] results){
        Pending pending=queue.peek();if(pending==null || pending.code!=code)return;
        try{
            if(pending.abandoned){complete(pending);return;}
            pending.task.check();if(!host.ownsPermissionRequest(pending.task.root))throw new IOException("Conversation closed.");
            boolean any=pending.signal.getJSONObject("request").optBoolean("any");boolean granted=!any && results.length==pending.permissions.length;
            for(String permission:pending.permissions){boolean allowed=host.checkSelfPermission(permission)==PackageManager.PERMISSION_GRANTED;if(any){if(allowed)granted=true;}else if(!allowed)granted=false;}
            // A declined OS request becomes a remembered Collie denial. The VM
            // resumes and receives the ordinary denied-call error, without loops.
            if(!granted)host.savePermission(pending.signal.getString("key"),false);
        }catch(Exception error){pending.error=error;}
        complete(pending);
    }
}
