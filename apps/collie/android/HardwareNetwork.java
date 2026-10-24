package org.flexscript.collie;

import android.content.Context;
import android.net.*;
import android.system.Os;
import android.system.OsConstants;
import android.system.ErrnoException;
import android.system.StructTimeval;
import java.io.*;
import java.net.*;
import java.util.*;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import org.json.*;

/** Android network objects and socket I/O only; protocols remain guest code. */
final class HardwareNetwork {
    static final class ModelRoute implements Closeable {
        final ConnectivityManager manager;final ConnectivityManager.NetworkCallback callback;
        final CountDownLatch ready=new CountDownLatch(1);final String selector;volatile Network selected;volatile boolean closed;
        ModelRoute(MainActivity host,String selector)throws Exception{
            this.selector=selector;manager=(ConnectivityManager)host.getSystemService(Context.CONNECTIVITY_SERVICE);
            if(selector.equals("default")){callback=null;ready.countDown();return;}
            int transport=transport(selector);
            callback=new ConnectivityManager.NetworkCallback(){public void onAvailable(Network network){selected=network;ready.countDown();}public void onLost(Network network){if(network.equals(selected))selected=null;}public void onUnavailable(){ready.countDown();}};
            manager.requestNetwork(new NetworkRequest.Builder().addTransportType(transport).addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET).build(),callback);
        }
        URLConnection open(URL url)throws Exception{
            if(closed)throw new IOException("Model network selection changed.");
            if(selector.equals("default"))return HardwareVpn.modelConnection(url);
            if(selected==null)ready.await(8,TimeUnit.SECONDS);Network network=selected;
            if(network==null || closed)throw new IOException("Selected model network is unavailable: "+selector);
            return network.openConnection(url);
        }
        public void close(){if(closed)return;closed=true;if(callback!=null)try{manager.unregisterNetworkCallback(callback);}catch(IllegalArgumentException ignored){}ready.countDown();}
    }
    static boolean supports(String op) { return op.startsWith("net_"); }
    static ConnectivityManager manager(VmHardware.Context c) { return (ConnectivityManager)c.host.getSystemService(Context.CONNECTIVITY_SERVICE); }
    static String id(Network n) { return "net-"+Long.toUnsignedString(n.getNetworkHandle()); }
    static int transport(String name) throws Exception {
        switch(name){case "wifi":return NetworkCapabilities.TRANSPORT_WIFI;case "ethernet":return NetworkCapabilities.TRANSPORT_ETHERNET;case "cellular":return NetworkCapabilities.TRANSPORT_CELLULAR;case "vpn":return NetworkCapabilities.TRANSPORT_VPN;default:throw new VmHardware.Failure("invalid_argument","Use wifi, ethernet, cellular, vpn, default, or a net_list ID.");}
    }
    static Network network(VmHardware.Context c,String selector) throws Exception {
        ConnectivityManager cm=manager(c);Network selected=null;
        if(selector.equals("default") || selector.length()==0)selected=cm.getActiveNetwork();
        else {
            int kind=selector.startsWith("net-")?-1:transport(selector);
            for(Network n:cm.getAllNetworks()) {
                NetworkCapabilities caps=cm.getNetworkCapabilities(n);
                if((kind<0 && id(n).equals(selector)) || (kind>=0 && caps!=null && caps.hasTransport(kind) && (kind==NetworkCapabilities.TRANSPORT_VPN || !caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)))) { selected=n;break; }
            }
        }
        if(selected==null)throw new VmHardware.Failure("network_unavailable","The selected network is unavailable; net_request can retain a supported transport.");return selected;
    }
    static JSONArray addresses(Collection<? extends InetAddress> values) { JSONArray result=new JSONArray();for(InetAddress v:values)result.put(v.getHostAddress());return result; }
    static Object info(VmHardware.Context c,Network n) throws Exception {
        ConnectivityManager cm=manager(c);NetworkCapabilities caps=cm.getNetworkCapabilities(n);LinkProperties link=cm.getLinkProperties(n);
        if(caps==null || link==null)throw new VmHardware.Failure("disconnected","Network disconnected.");
        JSONArray transports=new JSONArray();for(String name:new String[]{"wifi","ethernet","cellular","vpn"})if(caps.hasTransport(transport(name)))transports.put(name);
        JSONArray ips=new JSONArray();for(LinkAddress a:link.getLinkAddresses())ips.put(a.toString());
        JSONArray routes=new JSONArray();for(RouteInfo r:link.getRoutes())routes.put(VmHardware.object("destination",r.getDestination().toString(),"gateway",r.getGateway()==null?JSONObject.NULL:r.getGateway().getHostAddress(),"interface",r.getInterface()));
        return VmHardware.object("id",id(n),"transports",transports,"interface",link.getInterfaceName()==null?JSONObject.NULL:link.getInterfaceName(),"addresses",ips,"routes",routes,"dns",addresses(link.getDnsServers()),"internet",caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET),"validated",caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED),"metered",!caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED),"default",n.equals(cm.getActiveNetwork()),"mtu",link.getMtu());
    }
    static void capabilities(VmHardware.Context c,JSONArray out) throws Exception {
        out.put(VmHardware.capability("network_inventory",true,true,"network"));
        out.put(VmHardware.capability("network_selection",true,true,"network"));
        out.put(VmHardware.capability("network_tcp",true,true,"network"));
        out.put(VmHardware.capability("network_udp",true,true,"network"));
        out.put(VmHardware.capability("network_http",true,true,"network"));
    }
    static final class Watch extends VmHardware.Handle {
        final ConnectivityManager cm;
        final ConnectivityManager.NetworkCallback callback;
        Watch(VmHardware.Context c,boolean retain,String kind) throws Exception {
            super(c,"network",retain?"network_request":"network_watch");cm=manager(c);
            callback=new ConnectivityManager.NetworkCallback(){
                public void onAvailable(Network n){emit(event("available",n));}
                public void onLost(Network n){emit(event("lost",n));}
                public void onUnavailable(){emit(VmHardwareObject("event","unavailable"));}
                public void onCapabilitiesChanged(Network n,NetworkCapabilities caps){emit(event("changed",n));}
                public void onLinkPropertiesChanged(Network n,LinkProperties link){emit(event("link_changed",n));}
            };
            NetworkRequest.Builder builder=new NetworkRequest.Builder();
            if(retain){builder.addTransportType(transport(kind));if(kind.equals("cellular"))builder.addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET);else builder.removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET);cm.requestNetwork(builder.build(),callback);}
            else cm.registerNetworkCallback(builder.removeCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN).build(),callback);
        }
        private JSONObject event(String type,Network n){return VmHardwareObject("event",type,"network",id(n));}
        public void close() throws IOException { if(closed)return;super.close();try{cm.unregisterNetworkCallback(callback);}catch(IllegalArgumentException ignored){} }
    }
    private static JSONObject VmHardwareObject(Object... fields) { try{return VmHardware.object(fields);}catch(JSONException impossible){throw new IllegalStateException(impossible);} }
    static final class Tcp extends VmHardware.Handle {
        final Socket socket;
        final Network network;
        Tcp(VmHardware.Context c,Socket s,Network n){super(c,"network","tcp");socket=s;network=n;}
        Object read(int limit,int timeout) throws Exception {
            check();if(!socket.isConnected())throw new VmHardware.Failure("not_connected","Dial this TCP socket before reading.");socket.setSoTimeout(timeout);byte[] bytes=new byte[limit];int n=socket.getInputStream().read(bytes);return n<0?JSONObject.NULL:VmHardware.bytes(Arrays.copyOf(bytes,n));
        }
        Object write(byte[] bytes) throws Exception { check();if(!socket.isConnected())throw new VmHardware.Failure("not_connected","Dial this TCP socket before writing.");socket.getOutputStream().write(bytes);return bytes.length; }
        Object info() throws Exception { check();return VmHardware.object("kind",kind,"network",id(network),"connected",socket.isConnected(),"local",socket.getLocalSocketAddress()==null?JSONObject.NULL:socket.getLocalSocketAddress().toString(),"remote",socket.getRemoteSocketAddress()==null?JSONObject.NULL:socket.getRemoteSocketAddress().toString()); }
        public void close() throws IOException { super.close();socket.close(); }
    }
    static final class AcceptedTcp extends VmHardware.Handle {
        final FileDescriptor fd;final Network network;
        AcceptedTcp(VmHardware.Context c,FileDescriptor fd,Network n){super(c,"network","tcp");this.fd=fd;network=n;}
        Object read(int limit,int timeout)throws Exception{
            check();Os.setsockoptTimeval(fd,OsConstants.SOL_SOCKET,OsConstants.SO_RCVTIMEO,StructTimeval.fromMillis(timeout));byte[] data=new byte[limit];
            try{int size=Os.read(fd,data,0,data.length);return size==0?JSONObject.NULL:VmHardware.bytes(Arrays.copyOf(data,size));}
            catch(ErrnoException error){if(error.errno==OsConstants.EAGAIN)throw new SocketTimeoutException("TCP receive timed out.");throw error;}
        }
        Object write(byte[] data)throws Exception{
            check();Os.setsockoptTimeval(fd,OsConstants.SOL_SOCKET,OsConstants.SO_SNDTIMEO,StructTimeval.fromMillis(8000));int at=0;
            while(at<data.length){VmHardware.check();int size=Os.write(fd,data,at,data.length-at);if(size<=0)throw new EOFException("Socket closed during write.");at+=size;}return at;
        }
        Object info()throws Exception{check();return VmHardware.object("kind",kind,"network",id(network),"local",Os.getsockname(fd).toString(),"remote",Os.getpeername(fd).toString());}
        public synchronized void close()throws IOException{if(closed)return;super.close();try{Os.shutdown(fd,OsConstants.SHUT_RDWR);}catch(Exception ignored){}try{Os.close(fd);}catch(Exception error){throw new IOException(error);}}
    }
    static final class Listener extends VmHardware.Handle {
        final FileDescriptor fd;final Network network;
        Listener(VmHardware.Context c,Network n,int port,int backlog)throws Exception{
            super(c,"network","tcp_listener");network=n;InetAddress local=local(c,n);fd=Os.socket(local instanceof Inet4Address?OsConstants.AF_INET:OsConstants.AF_INET6,OsConstants.SOCK_STREAM,0);
            try{n.bindSocket(fd);Os.bind(fd,local,port);Os.listen(fd,backlog);}catch(Exception error){Os.close(fd);throw error;}
        }
        Object info()throws Exception{check();InetSocketAddress address=(InetSocketAddress)Os.getsockname(fd);return VmHardware.object("kind",kind,"network",id(network),"port",address.getPort(),"address",address.getAddress().getHostAddress());}
        public synchronized void close()throws IOException{if(closed)return;super.close();try{Os.shutdown(fd,OsConstants.SHUT_RDWR);}catch(Exception ignored){}try{Os.close(fd);}catch(Exception error){throw new IOException(error);}}
    }
    static InetAddress local(VmHardware.Context c,Network n) throws Exception {
        LinkProperties properties=manager(c).getLinkProperties(n);if(properties!=null){
            for(LinkAddress a:properties.getLinkAddresses())if(a.getAddress() instanceof Inet4Address)return a.getAddress();
            for(LinkAddress a:properties.getLinkAddresses())if(!a.getAddress().isLinkLocalAddress())return a.getAddress();
        }throw new VmHardware.Failure("network_unavailable","Selected network has no usable local address.");
    }
    static final class Udp extends VmHardware.Handle {
        final DatagramSocket socket;final Network network;
        Udp(VmHardware.Context c,Network n,int port) throws Exception {
            super(c,"network","udp");network=n;socket=new DatagramSocket(null);
            try { n.bindSocket(socket);socket.bind(new InetSocketAddress(local(c,n),port)); }catch(Exception error){socket.close();throw error;}
        }
        Object info() throws Exception { check();return VmHardware.object("kind",kind,"network",id(network),"port",socket.getLocalPort(),"address",socket.getLocalAddress().getHostAddress()); }
        public void close() throws IOException { super.close();socket.close(); }
    }
    static Object call(VmHardware.Context c,String op,JSONArray a) throws Exception {
        switch(op){
        case "net_list":{JSONArray out=new JSONArray();for(Network n:manager(c).getAllNetworks())try{out.put(info(c,n));}catch(VmHardware.Failure ignored){}return out;}
        case "net_info":return info(c,network(c,VmHardware.text(a,0,128)));
        case "net_watch":return VmHardware.add(new Watch(c,false,""));
        case "net_request":return VmHardware.add(new Watch(c,true,VmHardware.text(a,0,16)));
        case "net_resolve":return addresses(Arrays.asList(network(c,VmHardware.text(a,0,128)).getAllByName(VmHardware.text(a,1,253))));
        case "net_tcp_open":{Network network=network(c,VmHardware.text(a,0,128));return VmHardware.add(new Tcp(c,network.getSocketFactory().createSocket(),network));}
        case "net_tcp_dial":{
            Tcp handle=VmHardware.handle(c,VmHardware.text(a,0,128),Tcp.class);String host=VmHardware.text(a,1,253);int port=VmHardware.integer(a,2,1,65535),timeout=VmHardware.integer(a,3,1,8000);if(handle.socket.isConnected())throw new VmHardware.Failure("already_connected","This TCP socket is already connected.");VmHardware.blocking(handle);try{handle.socket.connect(new InetSocketAddress(handle.network.getByName(host),port),timeout);handle.socket.setTcpNoDelay(true);return 1;}catch(Exception error){handle.close();throw error;}finally{VmHardware.unblocking();}
        }
        case "net_tcp_connect":{
            Network n=network(c,VmHardware.text(a,0,128));String host=VmHardware.text(a,1,253);int port=VmHardware.integer(a,2,1,65535),timeout=VmHardware.integer(a,3,1,8000);
            Socket socket=n.getSocketFactory().createSocket();Tcp handle=new Tcp(c,socket,n);VmHardware.blocking(handle);
            try{socket.connect(new InetSocketAddress(n.getByName(host),port),timeout);socket.setTcpNoDelay(true);return VmHardware.add(handle);}catch(Exception error){handle.close();throw error;}finally{VmHardware.unblocking();}
        }
        case "net_tcp_listen":return VmHardware.add(new Listener(c,network(c,VmHardware.text(a,0,128)),VmHardware.integer(a,1,0,65535),VmHardware.integer(a,2,1,32)));
        case "net_tcp_accept":{
            Listener server=VmHardware.handle(c,VmHardware.text(a,0,128),Listener.class);Os.setsockoptTimeval(server.fd,OsConstants.SOL_SOCKET,OsConstants.SO_RCVTIMEO,StructTimeval.fromMillis(VmHardware.integer(a,1,1,8000)));VmHardware.blocking(server);
            try{return VmHardware.add(new AcceptedTcp(c,Os.accept(server.fd,null),server.network));}catch(ErrnoException error){if(error.errno==OsConstants.EAGAIN)throw new SocketTimeoutException("TCP accept timed out.");throw error;}finally{VmHardware.unblocking();}
        }
        case "net_udp_open":return VmHardware.add(new Udp(c,network(c,VmHardware.text(a,0,128)),VmHardware.integer(a,1,0,65535)));
        case "net_udp_send":{
            Udp h=VmHardware.handle(c,VmHardware.text(a,0,128),Udp.class);byte[] bytes=VmHardware.data(a.get(3));InetAddress address=h.network.getByName(VmHardware.text(a,1,253));int port=VmHardware.integer(a,2,1,65535);h.socket.send(new DatagramPacket(bytes,bytes.length,address,port));return bytes.length;
        }
        case "net_udp_receive":{
            Udp h=VmHardware.handle(c,VmHardware.text(a,0,128),Udp.class);byte[] bytes=new byte[VmHardware.integer(a,1,1,VmHardware.MAX_BYTES)];h.socket.setSoTimeout(VmHardware.integer(a,2,1,8000));DatagramPacket packet=new DatagramPacket(bytes,bytes.length);VmHardware.blocking(h);
            try{h.socket.receive(packet);return VmHardware.object("address",packet.getAddress().getHostAddress(),"port",packet.getPort(),"data",VmHardware.bytes(Arrays.copyOf(bytes,packet.getLength())));}finally{VmHardware.unblocking();}
        }
        case "net_http":return http(c,network(c,VmHardware.text(a,0,128)),VmHardware.text(a,1,4096),VmHardware.integer(a,2,1,8000));
        default:throw new VmHardware.Failure("unsupported_operation","Unknown network operation.");
        }
    }
    static Object http(VmHardware.Context c,Network n,String url,int timeout) throws Exception {
        URI uri=new URI(url);if(!("https".equalsIgnoreCase(uri.getScheme()) || "http".equalsIgnoreCase(uri.getScheme())) || uri.getHost()==null || uri.getRawUserInfo()!=null || uri.getFragment()!=null)throw new VmHardware.Failure("invalid_argument","Use an absolute HTTP(S) URL without credentials or a fragment.");
        HttpURLConnection connection=(HttpURLConnection)n.openConnection(uri.toURL(),java.net.Proxy.NO_PROXY);connection.setConnectTimeout(timeout);connection.setReadTimeout(timeout);connection.setInstanceFollowRedirects(false);connection.setUseCaches(false);connection.setRequestProperty("Authorization","");connection.setRequestProperty("Cookie","");connection.setRequestProperty("Accept-Encoding","identity");
        VmHardware.Handle pending=new VmHardware.Handle(c,"network","http_request"){public void close()throws IOException{super.close();connection.disconnect();}};VmHardware.blocking(pending);
        try{
            int status=connection.getResponseCode();InputStream stream=status>=400?connection.getErrorStream():connection.getInputStream();ByteArrayOutputStream bytes=new ByteArrayOutputStream();
            if(stream!=null)try(InputStream in=stream){byte[] buffer=new byte[4096];while(bytes.size()<=VmHardware.MAX_BYTES){VmHardware.check();int size=in.read(buffer,0,Math.min(buffer.length,VmHardware.MAX_BYTES+1-bytes.size()));if(size<0)break;bytes.write(buffer,0,size);}}
            byte[] body=bytes.toByteArray();return VmHardware.object("status",status,"network",id(n),"url",url,"body",VmHardware.bytes(Arrays.copyOf(body,Math.min(body.length,VmHardware.MAX_BYTES))),"truncated",body.length>VmHardware.MAX_BYTES);
        }finally{VmHardware.unblocking();connection.disconnect();}
    }
}
