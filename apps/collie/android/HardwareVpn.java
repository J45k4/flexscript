package org.flexscript.collie;

import android.content.Intent;
import android.net.*;
import android.os.ParcelFileDescriptor;
import android.system.*;
import java.io.*;
import java.net.*;
import java.util.*;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import org.json.*;

/** User-approved TUN resources. Encryption and peer protocols are not implemented here. */
final class HardwareVpn {
    private static final Object LOCK=new Object();
    private static Request pending;
    private static Tun active;
    static boolean supports(String op){return op.equals("vpn_status")||op.equals("vpn_open")||op.equals("vpn_protect")||op.equals("vpn_underlying");}
    static void capabilities(VmHardware.Context c,JSONArray out)throws Exception{out.put(VmHardware.capability("vpn_packet_transport",true,true,"vpn"));}
    static InetAddress address(String text)throws Exception{InetAddress address=null;if(text.matches("[0-9.]{1,15}"))address=Os.inet_pton(OsConstants.AF_INET,text);else if(text.matches("[0-9a-fA-F:]{2,45}"))address=Os.inet_pton(OsConstants.AF_INET6,text);if(address==null)throw new VmHardware.Failure("invalid_argument","VPN addresses must be numeric IPv4 or IPv6, without DNS names or scope IDs.");return address;}
    static JSONArray array(JSONArray args,int index,int max)throws Exception{Object value=args.get(index);if(!(value instanceof JSONArray)||((JSONArray)value).length()>max)throw new VmHardware.Failure("invalid_argument","Expected bounded VPN list argument "+index+".");return (JSONArray)value;}
    static Network physical(VmHardware.Context c,String selector)throws Exception{
        if(!selector.equals("default")){Network selected=HardwareNetwork.network(c,selector);NetworkCapabilities caps=HardwareNetwork.manager(c).getNetworkCapabilities(selected);if(caps==null||caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN))throw new VmHardware.Failure("invalid_argument","Choose a non-VPN underlying network.");return selected;}
        ConnectivityManager manager=HardwareNetwork.manager(c);Network selected=manager.getActiveNetwork();NetworkCapabilities caps=selected==null?null:manager.getNetworkCapabilities(selected);if(caps!=null&&!caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN))return selected;
        Network fallback=null;for(Network candidate:manager.getAllNetworks()){caps=manager.getNetworkCapabilities(candidate);if(caps!=null&&!caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)){if(caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)&&caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED))return candidate;if(fallback==null)fallback=candidate;}}
        if(fallback==null)throw new VmHardware.Failure("network_unavailable","No non-VPN underlying network is available.");return fallback;
    }
    static URLConnection modelConnection(URL url)throws Exception{Tun tun;synchronized(LOCK){tun=active;}if(tun==null||tun.closed)return url.openConnection();return physical(tun.context,"default").openConnection(url);}
    static final class Prefix {final InetAddress address;final int length;Prefix(InetAddress address,int length){this.address=address;this.length=length;}}
    static List<Prefix> prefixes(JSONArray rows,boolean routes)throws Exception{
        List<Prefix> values=new ArrayList<>();for(int i=0;i<rows.length();i++){Object item=rows.get(i);if(!(item instanceof JSONArray)||((JSONArray)item).length()!=2)throw new VmHardware.Failure("invalid_argument","VPN prefixes must be [numeric_address,prefix_length] pairs.");JSONArray row=(JSONArray)item;InetAddress address=address(VmHardware.text(row,0,45));int bits=address instanceof Inet4Address?32:128;int length=VmHardware.integer(row,1,0,bits);if(!routes&&(address.isAnyLocalAddress()||address.isMulticastAddress()))throw new VmHardware.Failure("invalid_argument","VPN interface addresses must be unicast addresses.");if(routes&&!new IpPrefix(address,length).getAddress().equals(address))throw new VmHardware.Failure("invalid_argument","VPN routes must use a network prefix with zero host bits.");values.add(new Prefix(address,length));}return values;
    }
    static final class Config {
        final String name;final int mtu;final List<Prefix> addresses,routes;final List<InetAddress> dns=new ArrayList<>();final List<String> apps=new ArrayList<>();final boolean all,exclude;final Network network;
        Config(VmHardware.Context c,JSONArray args)throws Exception{
            name=VmHardware.text(args,0,64);if(name.trim().isEmpty())throw new VmHardware.Failure("invalid_argument","VPN session name cannot be empty.");addresses=prefixes(array(args,1,16),false);routes=prefixes(array(args,2,32),true);if(addresses.isEmpty()||routes.isEmpty())throw new VmHardware.Failure("invalid_argument","VPN requires at least one interface address and route.");mtu=VmHardware.integer(args,4,576,32768);for(Prefix prefix:addresses)if(prefix.address instanceof Inet6Address&&mtu<1280)throw new VmHardware.Failure("invalid_argument","IPv6 VPN interfaces require MTU at least 1280.");JSONArray servers=array(args,3,8);for(int i=0;i<servers.length();i++)dns.add(address(VmHardware.text(servers,i,45)));
            JSONArray packages=array(args,5,64);all=packages.length()==1&&"*".equals(packages.opt(0));boolean denied=false,allowed=false;Set<String> unique=new HashSet<>();if(!all)for(int i=0;i<packages.length();i++){String app=VmHardware.text(packages,i,256);boolean negated=app.startsWith("!");if(negated){denied=true;app=app.substring(1);}else allowed=true;if(!app.matches("[A-Za-z0-9_]+(\\.[A-Za-z0-9_]+)*")||!unique.add(app))throw new VmHardware.Failure("invalid_argument","VPN apps must be unique package names, !package exclusions, or the sole entry *.");c.host.getPackageManager().getApplicationInfo(app,0);apps.add(app);}if(denied&&allowed)throw new VmHardware.Failure("invalid_argument","VPN app allow and exclude lists cannot be mixed.");exclude=denied;if(!all&&apps.isEmpty())apps.add(c.host.getPackageName());network=physical(c,VmHardware.text(args,6,128));
        }
    }
    static final class Request extends VmHardware.Handle {
        final VmHardware.Context context;final Config config;final String token=UUID.randomUUID().toString();final CountDownLatch ready=new CountDownLatch(1);volatile Exception error;Tun result;
        Request(VmHardware.Context c,Config config){super(c,"vpn","vpn_starting");context=c;this.config=config;}
        synchronized boolean result(Tun value,Exception error){if(closed)return false;result=value;this.error=error;ready.countDown();return true;}
        synchronized Tun take(){Tun value=result;result=null;return value;}
        public void close()throws IOException{Tun value;synchronized(this){if(closed)return;super.close();value=result;result=null;ready.countDown();}try{if(value!=null)value.close();}finally{synchronized(LOCK){if(pending==this)pending=null;}}}
    }
    static Request request(String token){synchronized(LOCK){return pending!=null&&pending.token.equals(token)&&!pending.closed?pending:null;}}
    static void publish(Request request,Tun tun)throws Exception{synchronized(LOCK){if(pending!=request||request.closed)throw new VmHardware.Failure("cancelled","VPN creation was cancelled.");active=tun;}}
    static void released(Tun tun){synchronized(LOCK){if(active==tun)active=null;}}
    static final class Tun extends VmHardware.Handle {
        final VmHardware.Context context;final Config config;final ParcelFileDescriptor descriptor;final CollieVpnService service;final int startId;volatile Network underlying;
        Tun(Request request,ParcelFileDescriptor descriptor,CollieVpnService service,int startId){super(request.context,"vpn","vpn_tun");context=request.context;config=request.config;this.descriptor=descriptor;this.service=service;this.startId=startId;underlying=config.network;}
        void ready(int event,int timeout)throws Exception{check();StructPollfd poll=new StructPollfd();poll.fd=descriptor.getFileDescriptor();poll.events=(short)event;if(Os.poll(new StructPollfd[]{poll},timeout)==0)throw new VmHardware.Failure("timeout","No VPN packet I/O was ready before the deadline.");check();if((poll.revents&(OsConstants.POLLERR|OsConstants.POLLHUP|OsConstants.POLLNVAL))!=0){close();throw new VmHardware.Failure("disconnected","VPN interface disconnected.");}}
        Object read(int limit,int timeout)throws Exception{if(limit<config.mtu)throw new VmHardware.Failure("invalid_argument","VPN reads must provide at least the configured MTU to avoid truncating packets.");ready(OsConstants.POLLIN,timeout);byte[] data=new byte[config.mtu];int n=Os.read(descriptor.getFileDescriptor(),data,0,data.length);return n==0?JSONObject.NULL:VmHardware.bytes(Arrays.copyOf(data,n));}
        Object write(byte[] data)throws Exception{if(data.length<1||data.length>config.mtu)throw new VmHardware.Failure("invalid_argument","VPN packets must contain 1..MTU bytes.");ready(OsConstants.POLLOUT,8000);return Os.write(descriptor.getFileDescriptor(),data,0,data.length);}
        Object info()throws Exception{check();JSONArray addresses=new JSONArray(),routes=new JSONArray(),dns=new JSONArray(),apps=new JSONArray();for(Prefix prefix:config.addresses)addresses.put(prefix.address.getHostAddress()+"/"+prefix.length);for(Prefix prefix:config.routes)routes.put(prefix.address.getHostAddress()+"/"+prefix.length);for(InetAddress address:config.dns)dns.put(address.getHostAddress());for(String app:config.apps)apps.put(app);return VmHardware.object("kind",kind,"name",config.name,"mtu",config.mtu,"addresses",addresses,"routes",routes,"dns",dns,"apps",apps,"all_apps",config.all,"exclude_apps",config.exclude,"underlying",HardwareNetwork.id(underlying),"encrypted",false);}
        Object underlying(Network network)throws Exception{check();if(!service.setUnderlyingNetworks(new Network[]{network}))throw new VmHardware.Failure("unavailable","Android rejected the underlying VPN network.");underlying=network;return 1;}
        Object protect(VmHardware.Handle socket)throws Exception{check();boolean result;if(socket instanceof HardwareNetwork.Tcp)result=service.protect(((HardwareNetwork.Tcp)socket).socket);else if(socket instanceof HardwareNetwork.Udp)result=service.protect(((HardwareNetwork.Udp)socket).socket);else{FileDescriptor fd;if(socket instanceof HardwareNetwork.AcceptedTcp)fd=((HardwareNetwork.AcceptedTcp)socket).fd;else if(socket instanceof HardwareNetwork.Listener)fd=((HardwareNetwork.Listener)socket).fd;else throw new VmHardware.Failure("wrong_handle","VPN protection requires a TCP/UDP socket or TCP listener.");try(ParcelFileDescriptor duplicate=ParcelFileDescriptor.dup(fd)){result=service.protect(duplicate.getFd());}}if(!result)throw new VmHardware.Failure("unavailable","Android could not protect this tunnel transport socket.");return 1;}
        public void close()throws IOException{synchronized(this){if(closed)return;super.close();}try{descriptor.close();}finally{released(this);service.stopSession(this);}}
    }
    static Object call(VmHardware.Context c,String op,JSONArray args)throws Exception{
        if(op.equals("vpn_status")){boolean prepared=VpnService.prepare(c.host)==null;synchronized(LOCK){return VmHardware.object("prepared",prepared,"active",active!=null&&!active.closed,"owned",active!=null&&!active.closed&&active.root.equals(c.root),"starting",pending!=null);}}
        if(op.equals("vpn_open")){
            Config config;try{config=new Config(c,args);}catch(android.content.pm.PackageManager.NameNotFoundException error){throw new VmHardware.Failure("invalid_argument","VPN app package is not installed or visible to Collie.");}
            synchronized(LOCK){if(pending!=null||active!=null&&!active.closed)throw new VmHardware.Failure("busy","Collie already has a VPN session; close it before creating another.");}
            if(VpnService.prepare(c.host)!=null)throw new VmHardware.Consent(VmHardware.object("type","vpn"));if(!c.host.hardwareVisible)throw new VmHardware.Failure("foreground_required","Start a VPN while Collie is visible.");Request request=new Request(c,config);synchronized(LOCK){if(pending!=null||active!=null&&!active.closed)throw new VmHardware.Failure("busy","Another VPN session is starting.");pending=request;}
            VmHardware.blocking(request);try{c.host.startForegroundService(new Intent(c.host,CollieVpnService.class).setAction(CollieVpnService.START).putExtra("token",request.token));if(!request.ready.await(8,TimeUnit.SECONDS))throw new VmHardware.Failure("timeout","Android VPN service did not become ready.");VmHardware.check();request.check();if(request.error!=null)throw request.error;Tun tun=request.take();if(tun==null)throw new VmHardware.Failure("cancelled","VPN creation did not produce a live interface.");return VmHardware.add(tun);}finally{request.close();VmHardware.unblocking();}
        }
        Tun tun=VmHardware.handle(c,VmHardware.text(args,0,128),Tun.class);tun.access(c);if(op.equals("vpn_underlying"))return tun.underlying(physical(c,VmHardware.text(args,1,128)));if(op.equals("vpn_protect")){VmHardware.Handle socket=VmHardware.handle(c,VmHardware.text(args,1,128));socket.access(c);return tun.protect(socket);}throw new VmHardware.Failure("unsupported_operation","Unknown VPN operation.");
    }
}
