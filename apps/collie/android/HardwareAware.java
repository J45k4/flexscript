package org.flexscript.collie;

import android.Manifest;
import android.content.*;
import android.content.pm.PackageManager;
import android.location.LocationManager;
import android.net.*;
import android.net.wifi.aware.*;
import android.net.wifi.rtt.RangingRequest;
import android.os.Build;
import android.os.SystemClock;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.*;
import org.json.*;

/** Android Aware sessions, opaque peers and network leases. No guest protocol logic. */
final class HardwareAware {
    static boolean supports(String op){return op.startsWith("aware_");}
    private static Context app(VmHardware.Context c){return c.host.getApplicationContext();}
    private static boolean supported(VmHardware.Context c){return app(c).getPackageManager().hasSystemFeature(PackageManager.FEATURE_WIFI_AWARE);}
    private static WifiAwareManager manager(VmHardware.Context c)throws Exception{
        if(!supported(c))throw new VmHardware.Failure("unsupported","This Android device does not support Wi-Fi Aware.");
        WifiAwareManager manager=app(c).getSystemService(WifiAwareManager.class);
        if(manager==null)throw new VmHardware.Failure("unavailable","The Android Wi-Fi Aware service is unavailable.");return manager;
    }
    private static void permission(VmHardware.Context c)throws Exception{
        if(Build.VERSION.SDK_INT>=33)try{VmHardware.require(c,Manifest.permission.NEARBY_WIFI_DEVICES);}catch(VmHardware.Consent consent){consent.request.put("key","wifi");throw consent;}
        try{VmHardware.require(c,Manifest.permission.ACCESS_COARSE_LOCATION,Manifest.permission.ACCESS_FINE_LOCATION);}catch(VmHardware.Consent consent){consent.request.put("key","location");throw consent;}
        LocationManager lm=app(c).getSystemService(LocationManager.class);
        if(lm==null||!(Build.VERSION.SDK_INT>=28?lm.isLocationEnabled():lm.isProviderEnabled(LocationManager.GPS_PROVIDER)||lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)))throw new VmHardware.Failure("location_disabled","Turn on Android Location before Wi-Fi Aware discovery or ranging.");
    }
    private static void visible(VmHardware.Context c)throws Exception{if(!c.host.hardwareVisible)throw new VmHardware.Failure("foreground_required","Start this Wi-Fi Aware operation while Collie is visible.");}
    static void capabilities(VmHardware.Context c,JSONArray out)throws Exception{
        boolean supported=supported(c),available=supported&&manager(c).isAvailable();
        out.put(VmHardware.object("id","wifi_aware","implemented",true,"supported",supported,"available",available,"permission","wifi","also","location"));
    }
    static JSONObject info(VmHardware.Context c)throws Exception{
        boolean supported=supported(c);JSONObject result=VmHardware.object("supported",supported,"available",supported&&manager(c).isAvailable());if(!supported)return result;
        WifiAwareManager manager=manager(c);Characteristics limits=manager.getCharacteristics();
        if(limits!=null){result.put("service_name_max",limits.getMaxServiceNameLength()).put("service_info_max",limits.getMaxServiceSpecificInfoLength()).put("match_filter_max",limits.getMaxMatchFilterLength());if(Build.VERSION.SDK_INT>=31)result.put("cipher_suites",limits.getSupportedCipherSuites());if(Build.VERSION.SDK_INT>=33)result.put("instant_mode",limits.isInstantCommunicationModeSupported());if(Build.VERSION.SDK_INT>=34)result.put("pairing",limits.isAwarePairingSupported());}
        if(Build.VERSION.SDK_INT>=31){AwareResources free=manager.getAvailableAwareResources();if(free!=null)result.put("free_publish_sessions",free.getAvailablePublishSessionsCount()).put("free_subscribe_sessions",free.getAvailableSubscribeSessionsCount()).put("free_data_paths",free.getAvailableDataPathsCount());}
        return result;
    }
    private static void register(Context app,BroadcastReceiver receiver){IntentFilter filter=new IntentFilter(WifiAwareManager.ACTION_WIFI_AWARE_STATE_CHANGED);if(Build.VERSION.SDK_INT>=33)app.registerReceiver(receiver,filter,Context.RECEIVER_NOT_EXPORTED);else app.registerReceiver(receiver,filter);}
    private static void closeAll(Collection<? extends VmHardware.Handle> handles){for(VmHardware.Handle handle:handles)try{handle.close();}catch(Exception ignored){}}
    private static void event(VmHardware.Handle handle,String type,Object... fields){try{Object[] row=new Object[fields.length+2];row[0]="event";row[1]=type;System.arraycopy(fields,0,row,2,fields.length);handle.emit(VmHardware.object(row));}catch(Exception ignored){}}
    static final class Watch extends VmHardware.Handle {
        final VmHardware.Context context;final BroadcastReceiver receiver;boolean registered;
        Watch(VmHardware.Context c){super(c,"wifi","aware_state");context=c;receiver=new BroadcastReceiver(){public void onReceive(Context ignored,Intent intent){try{event(Watch.this,"availability","available",manager(c).isAvailable());}catch(Exception error){event(Watch.this,"error","code","platform_error","message",MainActivity.safe(error));}}};}
        void start()throws Exception{register(app(context),receiver);registered=true;event(this,"availability","available",manager(context).isAvailable());}
        public Object info()throws Exception{check();return HardwareAware.info(context);}
        public synchronized void close()throws IOException{if(closed)return;super.close();if(registered){registered=false;app(context).unregisterReceiver(receiver);}}
    }
    static final class Attachment extends VmHardware.Handle {
        final VmHardware.Context context;final Set<Discovery> children=new HashSet<>();final BroadcastReceiver receiver;
        WifiAwareSession session;String state="pending";boolean registered;
        final Runnable deadline=()->terminate("timeout","Android did not attach Wi-Fi Aware within15 seconds.");
        Attachment(VmHardware.Context c){super(c,"wifi","aware_attachment","location");context=c;receiver=new BroadcastReceiver(){public void onReceive(Context ignored,Intent intent){terminate("session_disrupted","Android Wi-Fi Aware availability changed; reopen the attachment.");}};}
        void start()throws Exception{
            register(app(context),receiver);registered=true;HardwareSensors.events().postDelayed(deadline,15000);
            manager(context).attach(new AttachCallback(){
                public void onAttached(WifiAwareSession value){synchronized(Attachment.this){if(closed||!state.equals("pending")){value.close();return;}session=value;state="attached";HardwareSensors.events().removeCallbacks(deadline);event(Attachment.this,"attached");}}
                public void onAttachFailed(){terminate("attach_failed","Android could not attach Wi-Fi Aware.");}
                public void onAwareSessionTerminated(){terminate("session_terminated","Android terminated the Wi-Fi Aware attachment.");}
            },HardwareSensors.events());
        }
        synchronized WifiAwareSession active()throws Exception{check();if(session==null||!state.equals("attached"))throw new VmHardware.Failure(state.equals("pending")?"not_ready":"disconnected","Wait for attached, or reopen the terminated Aware attachment.");return session;}
        synchronized void add(Discovery child)throws Exception{active();children.add(child);}
        synchronized void detach(Discovery child){children.remove(child);}
        void terminate(String code,String message){List<Discovery> closing;WifiAwareSession sdk;synchronized(this){if(closed||state.equals("terminated"))return;state="terminated";HardwareSensors.events().removeCallbacks(deadline);closing=new ArrayList<>(children);children.clear();sdk=session;session=null;if(registered){registered=false;app(context).unregisterReceiver(receiver);}event(this,"error","code",code,"message",message);}closeAll(closing);if(sdk!=null)sdk.close();}
        public void access(VmHardware.Context c)throws Exception{check();permission(c);}
        public synchronized Object info()throws Exception{check();return VmHardware.object("kind",kind,"state",state,"children",children.size());}
        public void close()throws IOException{List<Discovery> closing;WifiAwareSession sdk;synchronized(this){if(closed)return;super.close();HardwareSensors.events().removeCallbacks(deadline);closing=new ArrayList<>(children);children.clear();sdk=session;session=null;if(registered){registered=false;app(context).unregisterReceiver(receiver);}}closeAll(closing);if(sdk!=null)sdk.close();}
    }
    static final class Peer {final String id="peer-"+UUID.randomUUID();final PeerHandle sdk;long seen;Peer(PeerHandle sdk){this.sdk=sdk;seen=SystemClock.elapsedRealtime();}}
    static final class Discovery extends VmHardware.Handle {
        final Attachment parent;final boolean publish;final Set<VmHardware.Handle> children=new HashSet<>();
        final LinkedHashMap<PeerHandle,Peer> peers=new LinkedHashMap<>();final Map<Integer,Runnable> messages=new HashMap<>();
        final DiscoverySessionCallback callback;DiscoverySession session;String state="pending";boolean updating;int lastMessage=-1;long revision;
        final Runnable deadline=()->terminate("timeout","Android did not start/update the Aware discovery session within15 seconds.");
        Discovery(Attachment parent,boolean publish){super(parent.context,"wifi",publish?"aware_publish":"aware_subscribe","location");this.parent=parent;this.publish=publish;callback=new DiscoverySessionCallback(){
            public void onPublishStarted(PublishDiscoverySession value){started(value);}
            public void onSubscribeStarted(SubscribeDiscoverySession value){started(value);}
            public void onSessionConfigUpdated(){synchronized(Discovery.this){if(closed||!state.equals("active")||!updating)return;updating=false;revision++;HardwareSensors.events().removeCallbacks(deadline);event(Discovery.this,"updated","revision",revision);}}
            public void onSessionConfigFailed(){boolean initial;synchronized(Discovery.this){initial=state.equals("pending");if(!initial&&updating){updating=false;HardwareSensors.events().removeCallbacks(deadline);event(Discovery.this,"update_failed");}}if(initial)terminate("config_failed","Android rejected the Aware discovery configuration.");}
            public void onSessionTerminated(){terminate("session_terminated","Android terminated the Aware discovery session.");}
            public void onServiceDiscovered(PeerHandle peer,byte[] info,List<byte[]> filters){discovered(peer,info,filters,null);}
            public void onServiceDiscoveredWithinRange(PeerHandle peer,byte[] info,List<byte[]> filters,int distance){discovered(peer,info,filters,distance);}
            public void onServiceDiscovered(ServiceDiscoveryInfo info){discovered(info.getPeerHandle(),info.getServiceSpecificInfo(),info.getMatchFilters(),null);}
            public void onServiceDiscoveredWithinRange(ServiceDiscoveryInfo info,int distance){discovered(info.getPeerHandle(),info.getServiceSpecificInfo(),info.getMatchFilters(),distance);}
            public void onServiceLost(PeerHandle peer,int reason){lost(peer,reason);}
            public void onMessageReceived(PeerHandle value,byte[] bytes){try{String peer=intern(value).id;int size=bytes==null?0:bytes.length;event(Discovery.this,"message","peer",peer,"data",VmHardware.bytes(bytes==null?new byte[0]:Arrays.copyOf(bytes,Math.min(size,VmHardware.MAX_BYTES))),"truncated",size>VmHardware.MAX_BYTES);}catch(Exception error){callbackError(error);}}
            public void onMessageSendSucceeded(int id){sent(id,true);}
            public void onMessageSendFailed(int id){sent(id,false);}
        };}
        void start(Object config)throws Exception{parent.add(this);HardwareSensors.events().postDelayed(deadline,15000);WifiAwareSession sdk=parent.active();if(publish)sdk.publish((PublishConfig)config,callback,HardwareSensors.events());else sdk.subscribe((SubscribeConfig)config,callback,HardwareSensors.events());}
        synchronized void started(DiscoverySession value){if(closed||!state.equals("pending")){value.close();return;}try{parent.active();}catch(Exception error){value.close();return;}session=value;state="active";HardwareSensors.events().removeCallbacks(deadline);event(this,"started","publish",publish);}
        synchronized DiscoverySession active()throws Exception{check();parent.active();if(session==null||!state.equals("active"))throw new VmHardware.Failure(state.equals("pending")?"not_ready":"disconnected","Wait for started, or reopen the terminated Aware discovery session.");return session;}
        synchronized void own(VmHardware.Handle child)throws Exception{active();children.add(child);}
        synchronized void detach(VmHardware.Handle child){children.remove(child);}
        synchronized Peer intern(PeerHandle sdk)throws Exception{active();if(sdk==null)throw new VmHardware.Failure("invalid_response","Android returned no Aware peer.");Peer peer=peers.get(sdk);if(peer==null){if(peers.size()>=128)throw new VmHardware.Failure("resource_limit","The discovery session has128 peers; reopen it before admitting more peers.");peer=new Peer(sdk);peers.put(sdk,peer);}peer.seen=SystemClock.elapsedRealtime();return peer;}
        synchronized Peer peer(String id)throws Exception{active();for(Peer peer:peers.values())if(peer.id.equals(id))return peer;throw new VmHardware.Failure("disconnected","This Aware peer ID is no longer present in this discovery session.");}
        synchronized Object page(int offset,int limit)throws Exception{active();JSONArray result=new JSONArray();List<Peer> values=new ArrayList<>(peers.values());for(int i=offset;i<Math.min(values.size(),offset+limit);i++)result.put(VmHardware.object("id",values.get(i).id,"seen_ms",values.get(i).seen));return VmHardware.object("peers",result,"total",peers.size(),"next",offset+result.length()<peers.size()?offset+result.length():-1);}
        void callbackError(Exception error){event(this,"error","code",error instanceof VmHardware.Failure?((VmHardware.Failure)error).code:"callback_failed","message",MainActivity.safe(error));}
        void discovered(PeerHandle sdk,byte[] data,List<byte[]> filters,Integer distance){try{String peer=intern(sdk).id;JSONArray rows=new JSONArray();int total=0;boolean truncated=false;if(filters!=null)for(byte[] value:filters){if(rows.length()==32||total+value.length>4096){truncated=true;break;}total+=value.length;rows.put(VmHardware.bytes(value));}int size=data==null?0:data.length;event(this,"service","peer",peer,"info",VmHardware.bytes(data==null?new byte[0]:Arrays.copyOf(data,Math.min(size,4096))),"info_truncated",size>4096,"filters",rows,"filters_truncated",truncated,"distance_mm",distance==null?JSONObject.NULL:distance);}catch(Exception error){callbackError(error);}}
        void lost(PeerHandle sdk,int reason){Peer gone;List<VmHardware.Handle> closing=new ArrayList<>();synchronized(this){gone=peers.remove(sdk);if(gone==null)return;for(VmHardware.Handle h:children)if(h instanceof NetworkLease&&((NetworkLease)h).peer.equals(gone.id)||h instanceof AwareRange&&((AwareRange)h).peers.containsKey(sdk))closing.add(h);event(this,"service_lost","peer",gone.id,"reason",reason);}closeAll(closing);}
        void send(String id,int messageId,byte[] bytes)throws Exception{
            synchronized(this){DiscoverySession sdk=active();if(messageId<=lastMessage)throw new VmHardware.Failure("invalid_argument","Message IDs must increase monotonically within a discovery session.");if(messages.size()>=32)throw new VmHardware.Failure("busy","At most32 Aware messages may await acknowledgement.");lastMessage=messageId;Runnable deadline=()->sent(messageId,false);messages.put(messageId,deadline);HardwareSensors.events().postDelayed(deadline,10000);try{sdk.sendMessage(peer(id).sdk,messageId,bytes);}catch(Exception error){messages.remove(messageId);HardwareSensors.events().removeCallbacks(deadline);throw error;}}
        }
        synchronized void sent(int id,boolean ok){Runnable deadline=messages.remove(id);if(deadline==null||closed)return;HardwareSensors.events().removeCallbacks(deadline);event(this,ok?"message_sent":"message_failed","id",id);}
        void update(Object config)throws Exception{synchronized(this){DiscoverySession sdk=active();if(updating)throw new VmHardware.Failure("busy","Wait for the prior discovery update to finish.");updating=true;HardwareSensors.events().postDelayed(deadline,15000);try{if(publish)((PublishDiscoverySession)sdk).updatePublish((PublishConfig)config);else((SubscribeDiscoverySession)sdk).updateSubscribe((SubscribeConfig)config);}catch(Exception error){updating=false;HardwareSensors.events().removeCallbacks(deadline);throw error;}}}
        void terminate(String code,String message){List<VmHardware.Handle> closing;DiscoverySession sdk;synchronized(this){if(closed||state.equals("terminated"))return;state="terminated";updating=false;HardwareSensors.events().removeCallbacks(deadline);for(Runnable pending:messages.values())HardwareSensors.events().removeCallbacks(pending);messages.clear();peers.clear();closing=new ArrayList<>(children);children.clear();sdk=session;session=null;event(this,"error","code",code,"message",message);}closeAll(closing);if(sdk!=null)sdk.close();}
        public void access(VmHardware.Context c)throws Exception{check();parent.access(c);}
        public synchronized Object info()throws Exception{check();return VmHardware.object("kind",kind,"state",state,"updating",updating,"revision",revision,"peers",peers.size(),"last_message_id",lastMessage,"pending_messages",messages.size(),"children",children.size());}
        public void close()throws IOException{List<VmHardware.Handle> closing;DiscoverySession sdk;synchronized(this){if(closed)return;super.close();HardwareSensors.events().removeCallbacks(deadline);for(Runnable pending:messages.values())HardwareSensors.events().removeCallbacks(pending);messages.clear();peers.clear();closing=new ArrayList<>(children);children.clear();sdk=session;session=null;}parent.detach(this);closeAll(closing);if(sdk!=null)sdk.close();}
    }
    static final class NetworkLease extends VmHardware.Handle {
        final Discovery parent;final String peer;final ConnectivityManager manager;final NetworkRequest request;final ConnectivityManager.NetworkCallback callback;final int timeout;
        boolean registered;Network network;String state="pending";JSONObject remote;
        NetworkLease(Discovery parent,String peer,NetworkSpecifier specifier,int timeout){super(parent.parent.context,"wifi","aware_network","location");this.parent=parent;this.peer=peer;this.timeout=timeout;manager=HardwareNetwork.manager(parent.parent.context);request=new NetworkRequest.Builder().addTransportType(NetworkCapabilities.TRANSPORT_WIFI_AWARE).removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET).setNetworkSpecifier(specifier).build();callback=new ConnectivityManager.NetworkCallback(){
            public void onAvailable(Network value){synchronized(NetworkLease.this){if(closed)return;network=value;state="available";event(NetworkLease.this,"available","network",HardwareNetwork.id(value),"peer",peer);}}
            public void onCapabilitiesChanged(Network value,NetworkCapabilities caps){synchronized(NetworkLease.this){if(closed)return;try{if(Build.VERSION.SDK_INT>=29&&caps.getTransportInfo() instanceof WifiAwareNetworkInfo){WifiAwareNetworkInfo info=(WifiAwareNetworkInfo)caps.getTransportInfo();remote=VmHardware.object("address",info.getPeerIpv6Addr()==null?JSONObject.NULL:info.getPeerIpv6Addr().getHostAddress(),"port",info.getPort(),"protocol",info.getTransportProtocol());event(NetworkLease.this,"peer_info","network",HardwareNetwork.id(value),"remote",remote);}}catch(Exception error){event(NetworkLease.this,"error","code","invalid_response","message",MainActivity.safe(error));}}}
            public void onLost(Network value){synchronized(NetworkLease.this){if(closed)return;if(value.equals(network)){network=null;remote=null;state="lost";}event(NetworkLease.this,"lost","network",HardwareNetwork.id(value));}}
            public void onUnavailable(){synchronized(NetworkLease.this){if(closed)return;state="unavailable";event(NetworkLease.this,"unavailable");}}
        };}
        synchronized void start()throws Exception{parent.own(this);manager.requestNetwork(request,callback,HardwareSensors.events(),timeout);registered=true;}
        public void access(VmHardware.Context c)throws Exception{check();parent.access(c);}
        public synchronized Object info()throws Exception{check();return VmHardware.object("kind",kind,"state",state,"peer",peer,"network",network==null?JSONObject.NULL:HardwareNetwork.id(network),"remote",remote==null?JSONObject.NULL:remote,"model_route_changed",false);}
        public synchronized void close()throws IOException{if(closed)return;super.close();parent.detach(this);network=null;remote=null;if(registered){registered=false;try{manager.unregisterNetworkCallback(callback);}catch(IllegalArgumentException ignored){}}}
    }
    static final class AwareRange extends HardwareRtt.Range {
        final Discovery parent;final Map<PeerHandle,String> peers;
        AwareRange(Discovery parent,RangingRequest request,Map<PeerHandle,String> peers){super(parent.parent.context,request,peers);this.parent=parent;this.peers=peers;}
        public void access(VmHardware.Context c)throws Exception{parent.access(c);super.access(c);}
        public synchronized void close()throws IOException{if(closed)return;super.close();parent.detach(this);}
    }
    static Object config(VmHardware.Context c,JSONArray a,boolean publish)throws Exception{
        String name=VmHardware.text(a,1,255);if(name.isEmpty()||name.getBytes(StandardCharsets.UTF_8).length>255)throw new VmHardware.Failure("invalid_argument","Aware service names require1..255 UTF-8 bytes.");
        for(int i=0;i<name.length();i++)if(name.charAt(i)<128&&!Character.isLetterOrDigit(name.charAt(i))&&"-.".indexOf(name.charAt(i))<0)throw new VmHardware.Failure("invalid_argument","Aware service names use ASCII letters, digits, hyphens, periods or non-ASCII UTF-8.");
        byte[] info=VmHardware.data(a.get(2));if(info.length>4096)throw new VmHardware.Failure("size_limit","Service information is limited to4096 bytes.");JSONArray raw=a.getJSONArray(3);if(raw.length()>32)throw new VmHardware.Failure("size_limit","At most32 Aware match filters are allowed.");List<byte[]> filters=new ArrayList<>();int size=0;for(int i=0;i<raw.length();i++){byte[] bytes=VmHardware.data(raw.get(i));if(bytes.length>255||(size+=bytes.length+1)>4096)throw new VmHardware.Failure("size_limit","Each match filter is at most255 bytes and total encoded length is at most4096 bytes.");filters.add(bytes);}
        int type=VmHardware.integer(a,4,0,1),ttl=VmHardware.integer(a,5,0,86400);Characteristics limits=manager(c).getCharacteristics();if(limits!=null&&(name.getBytes(StandardCharsets.UTF_8).length>limits.getMaxServiceNameLength()||info.length>limits.getMaxServiceSpecificInfoLength()||size>limits.getMaxMatchFilterLength()))throw new VmHardware.Failure("size_limit","The configuration exceeds this device's reported Aware limits.");
        if(publish){boolean ranging=VmHardware.integer(a,6,0,1)==1;PublishConfig.Builder b=new PublishConfig.Builder().setServiceName(name).setServiceSpecificInfo(info).setMatchFilter(filters).setPublishType(type).setTtlSec(ttl).setTerminateNotificationEnabled(true);if(ranging&&Build.VERSION.SDK_INT<28)throw new VmHardware.Failure("unsupported","Aware ranging requires Android9 or newer.");if(Build.VERSION.SDK_INT>=28)b.setRangingEnabled(ranging);return b.build();}
        int min=VmHardware.integer(a,6,-1,Integer.MAX_VALUE),max=VmHardware.integer(a,7,-1,Integer.MAX_VALUE);if(min>=0&&max>=0&&min>max)throw new VmHardware.Failure("invalid_argument","Minimum ranging distance cannot exceed maximum distance.");SubscribeConfig.Builder b=new SubscribeConfig.Builder().setServiceName(name).setServiceSpecificInfo(info).setMatchFilter(filters).setSubscribeType(type).setTtlSec(ttl).setTerminateNotificationEnabled(true);if((min>=0||max>=0)&&Build.VERSION.SDK_INT<28)throw new VmHardware.Failure("unsupported","Aware ranging filters require Android9 or newer.");if(min>=0)b.setMinDistanceMm(min);if(max>=0)b.setMaxDistanceMm(max);return b.build();
    }
    static NetworkSpecifier specifier(Discovery discovery,Peer peer,JSONArray a)throws Exception{
        String security=VmHardware.text(a,2,16);byte[] key=VmHardware.data(a.get(3));int cipher=VmHardware.integer(a,4,0,2),port=VmHardware.integer(a,5,0,65535),protocol=VmHardware.integer(a,6,-1,255);
        if(!Arrays.asList("open","passphrase","pmk").contains(security)||security.equals("open")&&key.length!=0||security.equals("pmk")&&key.length!=32||security.equals("passphrase")&&(key.length<8||key.length>63))throw new VmHardware.Failure("invalid_argument","Use open with an empty key, passphrase with8..63 UTF-8 bytes, or pmk with32 binary bytes.");
        if((port!=0||protocol!=-1)&&(!discovery.publish||security.equals("open")))throw new VmHardware.Failure("invalid_argument","Only a secured publisher may advertise port/protocol metadata.");
        if(cipher!=0&&(Build.VERSION.SDK_INT<33||security.equals("open")))throw new VmHardware.Failure("unsupported","Explicit Aware data-path ciphers require a secure link on Android13 or newer.");
        String passphrase="";if(security.equals("passphrase"))try{passphrase=StandardCharsets.UTF_8.newDecoder().onMalformedInput(java.nio.charset.CodingErrorAction.REPORT).onUnmappableCharacter(java.nio.charset.CodingErrorAction.REPORT).decode(java.nio.ByteBuffer.wrap(key)).toString();}catch(java.nio.charset.CharacterCodingException error){throw new VmHardware.Failure("invalid_argument","Aware passphrases must be valid UTF-8.");}
        DiscoverySession session=discovery.active();
        if(Build.VERSION.SDK_INT<29){if(cipher!=0||port!=0||protocol!=-1||security.equals("pmk"))throw new VmHardware.Failure("unsupported","PMK and port/protocol data-path configuration require Android10 or newer.");return security.equals("open")?session.createNetworkSpecifierOpen(peer.sdk):session.createNetworkSpecifierPassphrase(peer.sdk,passphrase);}
        WifiAwareNetworkSpecifier.Builder builder=new WifiAwareNetworkSpecifier.Builder(session,peer.sdk);
        if(cipher!=0){Characteristics limits=manager(discovery.parent.context).getCharacteristics();if(limits==null||(limits.getSupportedCipherSuites()&cipher)==0)throw new VmHardware.Failure("unsupported","The requested Aware cipher is not supported by this device.");WifiAwareDataPathSecurityConfig.Builder config=new WifiAwareDataPathSecurityConfig.Builder(cipher);if(security.equals("pmk"))config.setPmk(key);else config.setPskPassphrase(passphrase);builder.setDataPathSecurityConfig(config.build());}
        else if(security.equals("pmk"))builder.setPmk(key);else if(security.equals("passphrase"))builder.setPskPassphrase(passphrase);
        if(port!=0)builder.setPort(port);if(protocol!=-1)builder.setTransportProtocol(protocol);return builder.build();
    }
    static Object call(VmHardware.Context c,String op,JSONArray a)throws Exception{
        if(op.equals("aware_info"))return info(c);
        if(op.equals("aware_watch")){manager(c);Watch watch=new Watch(c);try{watch.start();return VmHardware.add(watch);}catch(Exception error){watch.close();throw error;}}
        if(op.equals("aware_open")){WifiAwareManager manager=manager(c);visible(c);permission(c);if(!manager.isAvailable())throw new VmHardware.Failure("unavailable","Android reports Wi-Fi Aware is temporarily unavailable.");Attachment attachment=new Attachment(c);try{attachment.start();return VmHardware.add(attachment);}catch(Exception error){attachment.close();throw error;}}
        if(op.equals("aware_publish")||op.equals("aware_subscribe")){Attachment parent=VmHardware.handle(c,VmHardware.text(a,0,128),Attachment.class);parent.access(c);visible(c);boolean publish=op.equals("aware_publish");Object config=config(c,a,publish);Discovery child=new Discovery(parent,publish);try{child.start(config);return VmHardware.add(child);}catch(Exception error){child.close();throw error;}}
        Discovery discovery=VmHardware.handle(c,VmHardware.text(a,0,128),Discovery.class);discovery.access(c);
        switch(op){
            case "aware_publish_update":case "aware_subscribe_update":{boolean publish=op.equals("aware_publish_update");if(publish!=discovery.publish)throw new VmHardware.Failure("wrong_handle","This update requires the corresponding publish/subscribe session.");visible(c);discovery.update(config(c,a,publish));return 1;}
            case "aware_peers":return discovery.page(VmHardware.integer(a,1,0,128),VmHardware.integer(a,2,1,16));
            case "aware_send":{byte[] data=VmHardware.data(a.get(3));Characteristics limits=manager(c).getCharacteristics();if(data.length>4096||limits!=null&&data.length>limits.getMaxServiceSpecificInfoLength())throw new VmHardware.Failure("size_limit","The message exceeds this device's Aware frame limit; use a data path for larger payloads.");discovery.send(VmHardware.text(a,1,128),VmHardware.integer(a,2,0,Integer.MAX_VALUE),data);return 1;}
            case "aware_network":{visible(c);Peer peer=discovery.peer(VmHardware.text(a,1,128));NetworkSpecifier specifier=specifier(discovery,peer,a);int timeout=VmHardware.integer(a,7,1000,120000);NetworkLease lease=new NetworkLease(discovery,peer.id,specifier,timeout);try{lease.start();return VmHardware.add(lease);}catch(Exception error){lease.close();throw error;}}
            case "aware_rtt":{HardwareRtt.ready(c);JSONArray ids=a.getJSONArray(1);int burst=VmHardware.integer(a,2,0,31);if(ids.length()==0||ids.length()>RangingRequest.getMaxPeers())throw new VmHardware.Failure("invalid_argument","Select1..max_peers Aware peers from this discovery session.");Map<PeerHandle,String> peers=new HashMap<>();RangingRequest.Builder request=new RangingRequest.Builder();for(int i=0;i<ids.length();i++){Peer peer=discovery.peer(VmHardware.text(ids,i,128));if(peers.put(peer.sdk,peer.id)!=null)throw new VmHardware.Failure("invalid_argument","Aware ranging peers must be distinct.");request.addWifiAwarePeer(peer.sdk);}HardwareRtt.burst(request,burst);AwareRange range=new AwareRange(discovery,request.build(),peers);try{discovery.own(range);range.start();return VmHardware.add(range);}catch(Exception error){range.close();throw error;}}
            default:throw new VmHardware.Failure("unsupported_operation","Unknown Wi-Fi Aware operation.");
        }
    }
}
