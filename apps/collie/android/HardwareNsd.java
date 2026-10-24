package org.flexscript.collie;

import android.content.Context;
import android.net.Network;
import android.net.nsd.*;
import android.os.Build;
import java.io.IOException;
import java.net.InetAddress;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import org.json.*;

/** Android DNS-SD objects and callbacks; no native pointers or arbitrary dispatch. */
final class HardwareNsd {
    static NsdManager manager(VmHardware.Context c)throws Exception{NsdManager manager=(NsdManager)c.host.getSystemService(Context.NSD_SERVICE);if(manager==null)throw new VmHardware.Failure("unsupported","Android network service discovery is unavailable.");return manager;}
    static String type(JSONArray args,int index)throws Exception{String type=VmHardware.text(args,index,64);if(!type.matches("_[A-Za-z0-9-]{1,15}\\._(tcp|udp)\\.?"))throw new VmHardware.Failure("invalid_argument","Use a DNS-SD type such as _http._tcp. with a service label of at most 15 characters.");return type.endsWith(".")?type:type+".";}
    static Network network(VmHardware.Context c,String selector)throws Exception{if(Build.VERSION.SDK_INT<33){if(!selector.equals("default"))throw new VmHardware.Failure("unsupported","Per-network DNS-SD requires Android 13 or newer.");return null;}return HardwareNetwork.network(c,selector);}
    static JSONObject basic(NsdServiceInfo info)throws Exception{return VmHardware.object("name",info.getServiceName(),"type",info.getServiceType(),"port",info.getPort(),"network",Build.VERSION.SDK_INT>=33&&info.getNetwork()!=null?HardwareNetwork.id(info.getNetwork()):JSONObject.NULL);}
    static JSONObject resolved(NsdServiceInfo info)throws Exception{
        JSONObject result=basic(info);JSONArray addresses=new JSONArray();if(Build.VERSION.SDK_INT>=34){for(InetAddress address:info.getHostAddresses())addresses.put(address.getHostAddress());}else if(info.getHost()!=null)addresses.put(info.getHost().getHostAddress());result.put("addresses",addresses);
        JSONArray attributes=new JSONArray();int total=0;for(Map.Entry<String,byte[]> entry:info.getAttributes().entrySet()){byte[] bytes=entry.getValue();total+=entry.getKey().getBytes(StandardCharsets.UTF_8).length+(bytes==null?0:bytes.length);if(attributes.length()>=128||total>16384)throw new VmHardware.Failure("size_limit","Resolved DNS-SD attributes exceed 16 KiB or 128 entries.");attributes.put(new JSONArray().put(entry.getKey()).put(bytes==null?JSONObject.NULL:VmHardware.bytes(bytes)));}result.put("attributes",attributes);return result;
    }
    static boolean supports(String op){switch(op){case "nsd_browse":case "nsd_register":case "nsd_services":case "nsd_resolve":case "nsd_watch_service":return true;default:return false;}}
    static void capabilities(VmHardware.Context c,JSONArray out)throws Exception{boolean supported=c.host.getSystemService(Context.NSD_SERVICE)!=null;out.put(VmHardware.capability("dns_sd",supported,supported,"network"));out.put(VmHardware.capability("dns_sd_selected_network",supported&&Build.VERSION.SDK_INT>=33,supported&&Build.VERSION.SDK_INT>=33,"network"));out.put(VmHardware.capability("dns_sd_service_updates",supported&&Build.VERSION.SDK_INT>=34,supported&&Build.VERSION.SDK_INT>=34,"network"));}
    static JSONObject failure(String operation,int code){try{return VmHardware.object("event","error","operation",operation,"android_code",code);}catch(Exception ignored){return new JSONObject();}}
    static final class Browser extends VmHardware.Handle implements NsdManager.DiscoveryListener {
        final NsdManager manager;final Network network;final String serviceType;final LinkedHashMap<String,NsdServiceInfo> services=new LinkedHashMap<>();final List<ServiceWatch> watches=new ArrayList<>();volatile boolean active=true;
        Browser(VmHardware.Context c,String type,Network network)throws Exception{super(c,"network","dns_sd_browser");manager=manager(c);this.network=network;serviceType=type;try{if(Build.VERSION.SDK_INT>=33)manager.discoverServices(type,NsdManager.PROTOCOL_DNS_SD,network,command->HardwareSensors.events().post(command),this);else manager.discoverServices(type,NsdManager.PROTOCOL_DNS_SD,this);}catch(Exception error){active=false;throw error;}}
        public void onDiscoveryStarted(String type){if(closed){stop();return;}try{emit(VmHardware.object("event","started","type",type));}catch(Exception ignored){}}
        public void onStartDiscoveryFailed(String type,int error){active=false;emit(failure("browse",error));}
        public void onDiscoveryStopped(String type){active=false;try{emit(VmHardware.object("event","stopped","type",type));}catch(Exception ignored){}}
        public void onStopDiscoveryFailed(String type,int error){emit(failure("stop_browse",error));}
        private String existing(NsdServiceInfo info){for(Map.Entry<String,NsdServiceInfo> entry:services.entrySet()){NsdServiceInfo old=entry.getValue();if(Objects.equals(info.getServiceName(),old.getServiceName())&&Objects.equals(info.getServiceType(),old.getServiceType())&&(Build.VERSION.SDK_INT<33||Objects.equals(info.getNetwork(),old.getNetwork())))return entry.getKey();}return null;}
        public synchronized void onServiceFound(NsdServiceInfo info){if(closed)return;try{String id=existing(info);if(id==null){if(services.size()>=128){String oldest=services.keySet().iterator().next();services.remove(oldest);emit(VmHardware.object("event","inventory_overflow","evicted",oldest));}id="service-"+UUID.randomUUID();}services.put(id,info);emit(VmHardware.object("event","found","id",id,"service",basic(info)));}catch(Exception ignored){}}
        public synchronized void onServiceLost(NsdServiceInfo info){String id=existing(info);if(id!=null){services.remove(id);try{emit(VmHardware.object("event","lost","id",id,"service",basic(info)));}catch(Exception ignored){}}}
        synchronized NsdServiceInfo service(String id)throws Exception{check();NsdServiceInfo info=services.get(id);if(info==null)throw new VmHardware.Failure("stale_service","Unknown, lost or evicted service for this browser.");return info;}
        synchronized Object page(int offset,int limit)throws Exception{check();List<Map.Entry<String,NsdServiceInfo>> values=new ArrayList<>(services.entrySet());int end=Math.min(values.size(),offset+limit);JSONArray out=new JSONArray();for(int i=offset;i<end;i++){Map.Entry<String,NsdServiceInfo> entry=values.get(i);out.put(VmHardware.object("id",entry.getKey(),"service",basic(entry.getValue())));}return VmHardware.object("services",out,"next",end<values.size()?end:-1,"total",values.size());}
        Object info()throws Exception{check();return VmHardware.object("kind",kind,"type",serviceType,"network",network==null?JSONObject.NULL:HardwareNetwork.id(network),"active",active,"cached_services",services.size());}
        synchronized String watch(VmHardware.Context c,String id)throws Exception{check();watches.removeIf(watch->watch.closed);ServiceWatch watch=new ServiceWatch(c,this,service(id));watches.add(watch);try{return VmHardware.add(watch);}catch(Exception error){watches.remove(watch);throw error;}}
        private void stop(){if(active)try{manager.stopServiceDiscovery(this);}catch(IllegalArgumentException ignored){}}
        public void close()throws IOException{List<ServiceWatch> closing;synchronized(this){if(closed)return;super.close();closing=new ArrayList<>(watches);watches.clear();services.clear();}stop();for(ServiceWatch watch:closing)watch.close();}
    }
    static final class Registration extends VmHardware.Handle implements NsdManager.RegistrationListener {
        final NsdManager manager;volatile NsdServiceInfo service;volatile boolean registered,active=true;
        Registration(VmHardware.Context c,NsdServiceInfo info)throws Exception{super(c,"network","dns_sd_registration");manager=manager(c);service=info;try{if(Build.VERSION.SDK_INT>=33)manager.registerService(info,NsdManager.PROTOCOL_DNS_SD,command->HardwareSensors.events().post(command),this);else manager.registerService(info,NsdManager.PROTOCOL_DNS_SD,this);}catch(Exception error){active=false;throw error;}}
        public void onServiceRegistered(NsdServiceInfo info){registered=true;service=info;if(closed){unregister();return;}try{emit(VmHardware.object("event","registered","service",basic(info)));}catch(Exception ignored){}}
        public void onRegistrationFailed(NsdServiceInfo info,int code){active=false;emit(failure("register",code));}
        public void onServiceUnregistered(NsdServiceInfo info){active=false;registered=false;try{emit(VmHardware.object("event","unregistered"));}catch(Exception ignored){}}
        public void onUnregistrationFailed(NsdServiceInfo info,int code){emit(failure("unregister",code));}
        Object info()throws Exception{check();return VmHardware.object("kind",kind,"registered",registered,"active",active,"service",basic(service));}
        private void unregister(){if(active)try{manager.unregisterService(this);}catch(IllegalArgumentException ignored){}}
        public void close()throws IOException{synchronized(this){if(closed)return;super.close();}unregister();}
    }
    static final class Resolution extends VmHardware.Handle implements NsdManager.ResolveListener {
        final NsdManager manager;final CountDownLatch ready=new CountDownLatch(1);volatile NsdServiceInfo result;volatile int error=-1;volatile boolean finished;
        Resolution(VmHardware.Context c,NsdServiceInfo service)throws Exception{super(c,"network","dns_sd_resolution");manager=manager(c);if(Build.VERSION.SDK_INT>=33)manager.resolveService(service,command->HardwareSensors.events().post(command),this);else manager.resolveService(service,this);}
        public void onServiceResolved(NsdServiceInfo info){if(!closed)result=info;finished=true;ready.countDown();}
        public void onResolveFailed(NsdServiceInfo info,int code){error=code;finished=true;ready.countDown();}
        public void onResolutionStopped(NsdServiceInfo info){finished=true;ready.countDown();}
        public void close()throws IOException{synchronized(this){if(closed)return;super.close();}if(!finished&&Build.VERSION.SDK_INT>=34)try{manager.stopServiceResolution(this);}catch(IllegalArgumentException ignored){}ready.countDown();}
    }
    static final class ServiceWatch extends VmHardware.Handle implements NsdManager.ServiceInfoCallback {
        final NsdManager manager;final Browser parent;final String name,type;
        ServiceWatch(VmHardware.Context c,Browser parent,NsdServiceInfo info)throws Exception{super(c,"network","dns_sd_service");manager=manager(c);this.parent=parent;name=info.getServiceName();type=info.getServiceType();manager.registerServiceInfoCallback(info,command->HardwareSensors.events().post(command),this);}
        void access(VmHardware.Context c)throws Exception{super.access(c);parent.check();}
        public void onServiceInfoCallbackRegistrationFailed(int error){emit(failure("watch_service",error));}
        public void onServiceUpdated(NsdServiceInfo info){try{emit(VmHardware.object("event","updated","service",resolved(info)));}catch(Exception error){try{emit(VmHardware.object("event","error","code","size_limit","message",MainActivity.safe(error)));}catch(Exception ignored){}}}
        public void onServiceLost(){try{emit(VmHardware.object("event","lost","name",name,"type",type));}catch(Exception ignored){}}
        public void onServiceInfoCallbackUnregistered(){}
        public void close()throws IOException{synchronized(this){if(closed)return;super.close();}try{manager.unregisterServiceInfoCallback(this);}catch(IllegalArgumentException ignored){}}
    }
    static Object call(VmHardware.Context c,String op,JSONArray args)throws Exception{
        if(op.equals("nsd_browse"))return VmHardware.add(new Browser(c,type(args,0),network(c,VmHardware.text(args,1,128))));
        if(op.equals("nsd_register")){
            String name=VmHardware.text(args,0,63);if(name.isEmpty()||name.getBytes(StandardCharsets.UTF_8).length>63)throw new VmHardware.Failure("invalid_argument","DNS-SD instance name must contain 1..63 UTF-8 bytes.");String type=type(args,1);int port=VmHardware.integer(args,2,1,65535);Object attributes=args.get(3);if(!(attributes instanceof JSONArray))throw new VmHardware.Failure("invalid_argument","DNS-SD attributes must be a list of [key,text/blob] pairs.");NsdServiceInfo info=new NsdServiceInfo();info.setServiceName(name);info.setServiceType(type);info.setPort(port);int total=0;Set<String> keys=new HashSet<>();JSONArray rows=(JSONArray)attributes;
            for(int i=0;i<rows.length();i++){Object value=rows.get(i);if(!(value instanceof JSONArray)||((JSONArray)value).length()!=2)throw new VmHardware.Failure("invalid_argument","Invalid DNS-SD attribute pair.");JSONArray row=(JSONArray)value;String key=VmHardware.text(row,0,32);if(!key.matches("[A-Za-z0-9_-]{1,32}")||!keys.add(key.toLowerCase(Locale.ROOT)))throw new VmHardware.Failure("invalid_argument","DNS-SD attribute keys must be unique ASCII tokens of 1..32 characters.");if(!(row.get(1) instanceof String))throw new VmHardware.Failure("invalid_argument","Android TXT advertising accepts UTF-8 text values; encode binary values as base64 text.");String text=VmHardware.text(row,1,1300);byte[] data=text.getBytes(StandardCharsets.UTF_8);int bytes=key.length()+1+data.length;if(bytes>255||(total+=bytes+1)>1300)throw new VmHardware.Failure("size_limit","Each TXT entry must fit 255 bytes and all attributes must fit 1300 bytes.");info.setAttribute(key,text);}
            Network network=network(c,VmHardware.text(args,4,128));if(Build.VERSION.SDK_INT>=33)info.setNetwork(network);return VmHardware.add(new Registration(c,info));
        }
        Browser browser=VmHardware.handle(c,VmHardware.text(args,0,128),Browser.class);browser.access(c);
        if(op.equals("nsd_services"))return browser.page(VmHardware.integer(args,1,0,100000),VmHardware.integer(args,2,1,32));String id=VmHardware.text(args,1,128);
        if(op.equals("nsd_watch_service")){if(Build.VERSION.SDK_INT<34)throw new VmHardware.Failure("unsupported","DNS-SD service updates require Android 14 or newer.");return browser.watch(c,id);}
        NsdServiceInfo service=browser.service(id);Resolution resolution=new Resolution(c,service);VmHardware.blocking(resolution);
        try{if(!resolution.ready.await(8,TimeUnit.SECONDS))throw new VmHardware.Failure("timeout","DNS-SD resolution did not finish within eight seconds.");VmHardware.check();resolution.check();browser.check();if(resolution.result==null)throw new VmHardware.Failure("resolve_failed","Android DNS-SD resolve error "+resolution.error+".");return resolved(resolution.result);}finally{resolution.close();VmHardware.unblocking();}
    }
}
