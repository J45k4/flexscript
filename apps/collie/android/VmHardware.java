package org.flexscript.collie;

import android.Manifest;
import android.content.pm.PackageManager;
import android.os.Build;
import android.util.Base64;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.*;
import org.json.*;

/** Bounded Android transport, resources and callbacks. Guest policy is Flexscript. */
final class VmHardware {
    static final int MAX_BYTES=32768, MAX_HANDLES=32, MAX_EVENTS=128;
    static final class Failure extends IOException {
        final String code;
        Failure(String code,String message) { super(message);this.code=code; }
    }
    static final class Consent extends Exception {
        final JSONObject request;
        Consent(JSONObject request) { this.request=request; }
    }
    static final class Context {
        final MainActivity host;
        final File root;
        Context(MainActivity host,File root) { this.host=host;this.root=root; }
    }
    static abstract class Handle implements Closeable {
        final File root;
        final String permission,kind,also;
        final ArrayBlockingQueue<Object> events=new ArrayBlockingQueue<>(MAX_EVENTS);
        volatile boolean closed;
        private int dropped;
        Handle(Context context,String permission,String kind) { this(context,permission,kind,""); }
        Handle(Context context,String permission,String kind,String also) { this.root=context.root;this.permission=permission;this.kind=kind;this.also=also; }
        synchronized void emit(Object value) {
            if (closed) return;
            if (!events.offer(value)) { events.poll();events.offer(value);dropped++; }
        }
        Object next(int timeout) throws Exception {
            check();Object event=events.poll(timeout,TimeUnit.MILLISECONDS);check();
            synchronized(this) { if(dropped>0) { int lost=dropped;dropped=0;return object("event","overflow","dropped",lost,"next",event==null?JSONObject.NULL:event); } }
            return event==null?JSONObject.NULL:event;
        }
        void access(Context context)throws Exception { check(); }
        void check() throws Failure { if(closed) throw new Failure("disconnected","Device handle is closed or disconnected."); }
        Object info() throws Exception { check();return object("kind",kind,"permission",permission,"queued_events",events.size()); }
        Object read(int limit,int timeout) throws Exception { throw new Failure("unsupported_operation","This handle does not provide byte reads."); }
        Object write(byte[] bytes) throws Exception { throw new Failure("unsupported_operation","This handle does not provide byte writes."); }
        void cancelIO() { try { close(); } catch(Exception ignored) {} }
        public void close() throws IOException { closed=true;events.clear(); }
    }
    private static final ThreadLocal<Context> CURRENT=new ThreadLocal<>();
    private static final Map<String,Handle> HANDLES=new LinkedHashMap<>();
    private static final class Operation {
        volatile boolean cancelled;
        volatile Runnable cancelIO;
        void cancel(){cancelled=true;Runnable action=cancelIO;if(action!=null)action.run();}
    }
    private static final ThreadLocal<Operation> OPERATION=new ThreadLocal<>();
    private static final ExecutorService IO=new ThreadPoolExecutor(0,2,30,TimeUnit.SECONDS,new SynchronousQueue<Runnable>(),task->{Thread thread=new Thread(task,"collie-hardware-io");thread.setDaemon(true);return thread;});
    private static volatile Operation active;
    private static volatile boolean cancelled;
    static void begin(MainActivity host,File root) { CURRENT.set(new Context(host,root)); }
    static void end() { CURRENT.remove(); }
    static void startProgram() { cancelled=false; }
    static void cancel() { cancelled=true;Operation operation=active;if(operation!=null)operation.cancel(); }
    static void check() throws Failure { Operation operation=OPERATION.get();if(cancelled || (operation!=null && operation.cancelled) || Thread.currentThread().isInterrupted()) throw new Failure("cancelled","Hardware operation cancelled."); }
    static void blocking(Handle handle) { Operation operation=OPERATION.get();if(operation!=null){operation.cancelIO=handle::cancelIO;if(operation.cancelled)handle.cancelIO();} }
    static void unblocking() { Operation operation=OPERATION.get();if(operation!=null)operation.cancelIO=null; }
    static String add(Handle handle) throws Exception {
        try {
            check();handle.check();
            synchronized(HANDLES) {
                // Recheck while publishing. Lifecycle cleanup uses this same
                // lock, so a newly opened resource cannot miss onStop cleanup.
                check();handle.check();HANDLES.entrySet().removeIf(entry->entry.getValue().closed);
                int count=0;for(Handle other:HANDLES.values())if(other.root.equals(handle.root))count++;
                if(count>=MAX_HANDLES)throw new Failure("resource_limit","At most 32 device handles may be open in one conversation.");
                String id="device-"+UUID.randomUUID().toString();HANDLES.put(id,handle);return id;
            }
        }catch(Exception error){try{handle.close();}catch(Exception ignored){}throw error;}
    }
    static Handle handle(Context context,String id) throws Failure {
        synchronized(HANDLES) {
            Handle handle=HANDLES.get(id);
            if(handle==null || !handle.root.equals(context.root)) throw new Failure("stale_handle","Unknown device handle for this workspace. Reopen after a restart or conversation change.");
            handle.check();return handle;
        }
    }
    static <T extends Handle> T handle(Context context,String id,Class<T> type) throws Failure {
        Handle handle=handle(context,id);if(!type.isInstance(handle)) throw new Failure("wrong_handle","This operation requires a different kind of device handle.");return type.cast(handle);
    }
    static void close(Context context,String id) throws Exception {
        Handle handle;
        synchronized(HANDLES) { handle=handle(context,id);HANDLES.remove(id); }
        handle.close();
    }
    static void closeWorkspace(File root) { closeMatching(root,null); }
    static void revoke(File root,String permission) { closeMatching(root,permission); }
    static void appHidden(){HardwareInput.hidden();closeKind("input_events");HardwareNfc.hidden();closeKind("nfc_reader");closeKind("nfc_technology");HardwareHid.hidden();closeKind("bluetooth_hid_device");closeMatching(null,"microphone");closeMatching(null,"camera");closeMatching(null,"screen_capture");}
    private static void closeKind(String kind) {
        List<Handle> closing=new ArrayList<>();
        synchronized(HANDLES){Iterator<Map.Entry<String,Handle>> it=HANDLES.entrySet().iterator();while(it.hasNext()){Handle h=it.next().getValue();if(h.kind.equals(kind)){closing.add(h);it.remove();}}}
        for(Handle h:closing)try{h.close();}catch(Exception ignored){}
    }
    private static void closeMatching(File root,String permission) {
        List<Handle> closing=new ArrayList<>();
        synchronized(HANDLES) {
            Iterator<Map.Entry<String,Handle>> it=HANDLES.entrySet().iterator();
            while(it.hasNext()) { Handle h=it.next().getValue();if((root==null || h.root.equals(root)) && (permission==null || (permission.equals(h.permission)||permission.equals(h.also)))) { closing.add(h);it.remove(); } }
        }
        for(Handle h:closing) try { h.close(); } catch(Exception ignored) {}
    }
    static JSONObject object(Object... fields) throws JSONException {
        JSONObject value=new JSONObject();for(int i=0;i<fields.length;i+=2)value.put((String)fields[i],fields[i+1]);return value;
    }
    static JSONObject bytes(byte[] value) throws Exception {
        if(value.length>MAX_BYTES) throw new Failure("size_limit","Binary result exceeds 32 KiB.");
        return object("$bytes",Base64.encodeToString(value,Base64.NO_WRAP));
    }
    static JSONObject real(double value) throws Exception {
        return object("$real",Double.doubleToRawLongBits(value));
    }
    static byte[] data(Object value) throws Exception {
        byte[] bytes;
        if(value instanceof String) bytes=((String)value).getBytes(StandardCharsets.UTF_8);
        else if(value instanceof JSONObject && ((JSONObject)value).length()==1 && ((JSONObject)value).has("$bytes")) {
            String encoded=((JSONObject)value).getString("$bytes");if(encoded.length()>43692)throw new Failure("size_limit","Binary input exceeds 32 KiB.");
            try { bytes=Base64.decode(encoded,Base64.NO_WRAP); } catch(IllegalArgumentException error) { throw new Failure("invalid_argument","Invalid base64 byte value."); }
        } else throw new Failure("invalid_argument","Expected text or a binary blob.");
        if(bytes.length>MAX_BYTES) throw new Failure("size_limit","Binary input exceeds 32 KiB.");return bytes;
    }
    static String text(JSONArray args,int index,int limit) throws Exception {
        Object value=args.get(index);if(!(value instanceof String) || ((String)value).length()>limit || ((String)value).indexOf('\0')>=0) throw new Failure("invalid_argument","Expected bounded text argument "+index+".");return (String)value;
    }
    static int integer(JSONArray args,int index,int min,int max) throws Exception {
        return (int)longInteger(args,index,min,max);
    }
    static long longInteger(JSONArray args,int index,long min,long max) throws Exception {
        Object value=args.get(index);if(!(value instanceof Integer || value instanceof Long))throw new Failure("invalid_argument","Expected integer argument "+index+".");
        long number=((Number)value).longValue();if(number<min || number>max)throw new Failure("invalid_argument","Integer argument "+index+" is out of range.");return number;
    }
    static void require(Context context,String... permissions) throws Exception {
        JSONArray missing=new JSONArray();
        if(Build.VERSION.SDK_INT>=23)for(String permission:permissions)if(context.host.checkSelfPermission(permission)!=PackageManager.PERMISSION_GRANTED)missing.put(permission);
        if(missing.length()>0) throw new Consent(object("type","runtime","permissions",missing));
    }
    static void requireAny(Context context,String... permissions)throws Exception{
        for(String permission:permissions)if(context.host.checkSelfPermission(permission)==PackageManager.PERMISSION_GRANTED)return;
        JSONArray missing=new JSONArray();for(String permission:permissions)missing.put(permission);throw new Consent(object("type","runtime","permissions",missing,"any",true));
    }
    static Object capability(String id,boolean supported,boolean available,String permission) throws Exception {
        return object("id",id,"implemented",true,"supported",supported,"available",available,"permission",permission);
    }
    static byte[] call(byte[] input) {
        Context context=CURRENT.get();Operation operation=new Operation();Future<byte[]> future=null;
        try {
            check();if(context==null)throw new Failure("platform_unavailable","Android hardware context is unavailable.");
            active=operation;
            future=IO.submit(()->{OPERATION.set(operation);try{return perform(context,input);}finally{OPERATION.remove();}});
            return future.get(9,TimeUnit.SECONDS);
        } catch(Exception error) {
            operation.cancel();
            String code=error instanceof TimeoutException?"timeout":error instanceof RejectedExecutionException?"busy":error instanceof InterruptedException || error instanceof CancellationException?"cancelled":"platform_error";
            try{return encode(object("error",object("code",code,"message",code.equals("timeout")?"Hardware operation exceeded 9 seconds; completion may be uncertain.":MainActivity.safe(error))));}catch(Exception ignored){return fallback();}
        } finally { if(future!=null)future.cancel(true);if(active==operation)active=null; }
    }
    private static byte[] perform(Context context,byte[] input) {
        try {
            check();
            if(input.length>65536)throw new Failure("size_limit","Hardware request exceeds 64 KiB.");
            JSONObject request=new JSONObject(new String(input,StandardCharsets.UTF_8));String op=request.getString("operation");JSONArray args=request.getJSONArray("args");Object value;
            if("permission".equals(request.optString("phase"))) {
                value=object("permission",handle(context,text(args,0,128)).permission,"also",handle(context,text(args,0,128)).also);
            } else if(op.equals("hardware_capabilities")) {
                JSONArray caps=new JSONArray();HardwareNetwork.capabilities(context,caps);HardwareSensors.capabilities(context,caps);HardwareStatus.capabilities(context,caps);HardwareLocation.capabilities(context,caps);HardwareUsb.capabilities(context,caps);HardwareKeystore.capabilities(context,caps);HardwareAudio.capabilities(context,caps);HardwareMidi.capabilities(context,caps);HardwareNsd.capabilities(context,caps);HardwareVpn.capabilities(context,caps);HardwareCellular.capabilities(context,caps);HardwareWifi.capabilities(context,caps);HardwareP2p.capabilities(context,caps);HardwareRtt.capabilities(context,caps);HardwareAware.capabilities(context,caps);HardwareBluetooth.capabilities(context,caps);HardwareBle.capabilities(context,caps);HardwareGattClient.capabilities(context,caps);HardwareGattServer.capabilities(context,caps);HardwareHid.capabilities(context,caps);HardwareNfc.capabilities(context,caps);HardwareSecureElement.capabilities(context,caps);HardwareInput.capabilities(context,caps);HardwareBiometrics.capabilities(context,caps);HardwareUwb.capabilities(context,caps);HardwareDocuments.capabilities(context,caps);value=caps;
            } else if(op.equals("device_close")) { close(context,text(args,0,128));value=1; }
            else if(op.equals("device_info")) { Handle h=handle(context,text(args,0,128));h.access(context);blocking(h);try{value=h.info();}finally{unblocking();} }
            else if(op.equals("device_wait")) {
                Handle h=handle(context,text(args,0,128));h.access(context);blocking(h);try{value=h.next(integer(args,1,0,1000));}finally{unblocking();}
            } else if(op.equals("device_read")) {
                Handle h=handle(context,text(args,0,128));h.access(context);blocking(h);try{value=h.read(integer(args,1,1,MAX_BYTES),integer(args,2,1,8000));}finally{unblocking();}
            } else if(op.equals("device_write")) {
                Handle h=handle(context,text(args,0,128));h.access(context);blocking(h);try{value=h.write(data(args.get(1)));}finally{unblocking();}
            } else if(HardwareDocuments.supports(op)) value=HardwareDocuments.call(context,op,args);
            else if(HardwareUwb.supports(op)) value=HardwareUwb.call(context,op,args);
            else if(HardwareBiometrics.supports(op)) value=HardwareBiometrics.call(context,op,args);
            else if(HardwareInput.supports(op)) value=HardwareInput.call(context,op,args);
            else if(HardwareNfc.supports(op)) value=HardwareNfc.call(context,op,args);
            else if(HardwareSecureElement.supports(op)) value=HardwareSecureElement.call(context,op,args);
            else if(HardwareHid.supports(op)) value=HardwareHid.call(context,op,args);
            else if(HardwareGattServer.supports(op)) value=HardwareGattServer.call(context,op,args);
            else if(HardwareGattClient.supports(op)) value=HardwareGattClient.call(context,op,args);
            else if(HardwareBle.supports(op)) value=HardwareBle.call(context,op,args);
            else if(HardwareBluetooth.supports(op)) value=HardwareBluetooth.call(context,op,args);
            else if(HardwareAware.supports(op)) value=HardwareAware.call(context,op,args);
            else if(HardwareRtt.supports(op)) value=HardwareRtt.call(context,op,args);
            else if(HardwareP2p.supports(op)) value=HardwareP2p.call(context,op,args);
            else if(HardwareWifi.supports(op)) value=HardwareWifi.call(context,op,args);
            else if(HardwareCellular.supports(op)) value=HardwareCellular.call(context,op,args);
            else if(HardwareVpn.supports(op)) value=HardwareVpn.call(context,op,args);
            else if(HardwareNsd.supports(op)) value=HardwareNsd.call(context,op,args);
            else if(HardwareAudio.supports(op)) value=HardwareAudio.call(context,op,args);
            else if(HardwareMidi.supports(op)) value=HardwareMidi.call(context,op,args);
            else if(HardwareKeystore.supports(op)) value=HardwareKeystore.call(context,op,args);
            else if(HardwareUsb.supports(op)) value=HardwareUsb.call(context,op,args);
            else if(HardwareLocation.supports(op)) value=HardwareLocation.call(context,op,args);
            else if(HardwareSensors.supports(op)) value=HardwareSensors.call(context,op,args);
            else if(HardwareStatus.supports(op)) value=HardwareStatus.call(context,op,args);
            else if(HardwareNetwork.supports(op)) value=HardwareNetwork.call(context,op,args);
            else throw new Failure("unsupported_operation","Unknown Android hardware operation: "+op);
            check();return encode(object("value",value));
        } catch(Consent consent) {
            try{return encode(object("consent",consent.request));}catch(Exception ignored){return fallback();}
        } catch(Exception error) {
            String code=error instanceof Failure?((Failure)error).code:error instanceof SecurityException?"permission_denied":error instanceof java.net.SocketTimeoutException?"timeout":error instanceof IllegalArgumentException || error instanceof JSONException?"invalid_argument":"platform_error";
            try{return encode(object("error",object("code",code,"message",MainActivity.safe(error))));}catch(Exception ignored){return fallback();}
        }
    }
    private static byte[] encode(JSONObject value) throws Exception {
        byte[] bytes=value.toString().getBytes(StandardCharsets.UTF_8);if(bytes.length>65536)throw new Failure("size_limit","Hardware response exceeds 64 KiB; request a smaller result.");return bytes;
    }
    private static byte[] fallback(){return "{\"error\":{\"code\":\"platform_error\",\"message\":\"Hardware bridge failed.\"}}".getBytes(StandardCharsets.UTF_8);}
}
