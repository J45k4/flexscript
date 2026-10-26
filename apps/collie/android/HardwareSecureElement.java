package org.flexscript.collie;

import android.content.pm.PackageManager;
import android.os.Build;
import android.se.omapi.*;
import java.io.IOException;
import java.util.*;
import java.util.concurrent.*;
import org.json.*;

/** OMAPI SDK objects/APDU transport. Android's applet access controls remain authoritative. */
final class HardwareSecureElement {
    private static final Semaphore SERVICES=new Semaphore(8);
    private static final ExecutorService CLEANUP=new ThreadPoolExecutor(2,2,30,TimeUnit.SECONDS,new ArrayBlockingQueue<Runnable>(8),task->{Thread t=new Thread(task,"collie-se-cleanup");t.setDaemon(true);return t;});
    private static volatile boolean observed;
    static boolean supports(String op){return op.startsWith("se_");}
    static void capabilities(VmHardware.Context c,JSONArray out)throws Exception{PackageManager pm=c.host.getPackageManager();boolean api=Build.VERSION.SDK_INT>=28;out.put(VmHardware.object("id","secure_element_omapi","implemented",true,"supported",!api?false:observed?true:JSONObject.NULL,"support_known",!api||observed,"available",api&&observed&&SERVICES.availablePermits()>0,"permission","secure_element","ese_feature",api&&pm.hasSystemFeature(PackageManager.FEATURE_SE_OMAPI_ESE),"uicc_feature",api&&pm.hasSystemFeature(PackageManager.FEATURE_SE_OMAPI_UICC),"sd_feature",api&&pm.hasSystemFeature(PackageManager.FEATURE_SE_OMAPI_SD)));}
    interface Work{void run()throws Exception;}
    static final class ReaderRef{final String id="se-reader-"+UUID.randomUUID();final Reader sdk;ReaderRef(Reader reader){sdk=reader;}}
    static final class Service extends VmHardware.Handle {
        final VmHardware.Context context;final LinkedHashMap<String,ReaderRef> readers=new LinkedHashMap<>();final Set<SessionHandle> sessions=new LinkedHashSet<>();final Set<ChannelHandle> channels=new LinkedHashSet<>();final ArrayDeque<Work> cleanup=new ArrayDeque<>();
        SEService sdk;boolean opening=true,connectedEarly,cleanupRunning,shutdownDone,released;int inFlight;String state="pending",cleanupError="";JSONObject lastResult;
        final Runnable deadline=()->{synchronized(Service.this){if(state.equals("pending"))fail("timeout","Android's OMAPI service did not connect before its deadline.");}};
        Service(VmHardware.Context c){super(c,"secure_element","secure_element_service");context=c;}
        void start(int timeout)throws Exception{
            HardwareSensors.events().postDelayed(deadline,timeout);SEService value;
            try{value=new SEService(context.host.getApplicationContext(),task->HardwareSensors.events().post(task),this::connected);}
            catch(Exception error){synchronized(this){opening=false;shutdownDone=true;releaseSlot();}throw error;}
            synchronized(this){opening=false;sdk=value;if(closed||state.equals("error")){queueShutdown();}else if(connectedEarly||value.isConnected())connected();}
        }
        synchronized void connected(){if(sdk==null){connectedEarly=true;return;}if(closed||state.equals("error"))return;if(!sdk.isConnected())return;observed=true;state="connected";HardwareSensors.events().removeCallbacks(deadline);try{lastResult=VmHardware.object("event","connected","version",sdk.getVersion());emit(lastResult);}catch(Exception error){fail("callback_failed",MainActivity.safe(error));}}
        synchronized void ready()throws Exception{check();if(state.equals("connected")&&sdk!=null&&!sdk.isConnected()){fail("service_disconnected","Android disconnected the OMAPI service.");throw new VmHardware.Failure("disconnected","The OMAPI service disconnected; reopen it.");}if(!state.equals("connected")||sdk==null||!sdk.isConnected())throw new VmHardware.Failure("not_ready","Wait for an actual OMAPI connected event, or reopen after service loss.");}
        synchronized void begin()throws Exception{ready();inFlight++;}
        synchronized void end(){inFlight--;releaseSlot();}
        synchronized void fail(String code,String message){if(closed||state.equals("error"))return;state="error";try{lastResult=VmHardware.object("event","error","code",code,"message",message);emit(lastResult);}catch(Exception ignored){}retire();}
        synchronized void post(Work work){cleanup.add(work);if(cleanupRunning)return;cleanupRunning=true;CLEANUP.execute(()->{while(true){Work next;synchronized(Service.this){next=cleanup.poll();if(next==null){cleanupRunning=false;releaseSlot();return;}}try{next.run();}catch(Exception error){synchronized(Service.this){cleanupError=MainActivity.safe(error);try{emit(VmHardware.object("event","cleanup_error","message",cleanupError));}catch(Exception ignored){}}}}});}
        void releaseSlot(){if(!released&&(closed||state.equals("error"))&&!opening&&shutdownDone&&!cleanupRunning&&cleanup.isEmpty()&&inFlight==0){released=true;SERVICES.release();}}
        void queueShutdown(){SEService value=sdk;if(value==null)return;sdk=null;post(()->{value.shutdown();synchronized(Service.this){shutdownDone=true;}});}
        void retire(){HardwareSensors.events().removeCallbacks(deadline);for(SessionHandle session:new ArrayList<>(sessions))session.close();if(!opening){if(sdk!=null)queueShutdown();else if(cleanup.isEmpty()&&!cleanupRunning)shutdownDone=true;}releaseSlot();}
        public synchronized Object info()throws Exception{check();return VmHardware.object("kind",kind,"state",state,"sdk_connected",sdk!=null&&sdk.isConnected(),"owned_sessions",sessions.size(),"owned_channels",channels.size(),"operations_in_flight",inFlight,"cleanup_pending",cleanupRunning||!cleanup.isEmpty(),"cleanup_error",cleanupError,"last_result",lastResult==null?JSONObject.NULL:lastResult);}
        synchronized ReaderRef reader(String id)throws Exception{ready();ReaderRef value=readers.get(id);if(value==null)throw new VmHardware.Failure("stale_reader","Use a reader ID enumerated by this OMAPI service.");return value;}
        ReaderRef remember(Reader value)throws Exception{synchronized(this){ready();for(ReaderRef ref:readers.values())if(ref.sdk.getName().equals(value.getName()))return ref;if(readers.size()>=32)throw new VmHardware.Failure("resource_limit","At most32 OMAPI readers may be owned by one service.");ReaderRef ref=new ReaderRef(value);readers.put(ref.id,ref);return ref;}}
        Object page(SEService service,int offset,int limit)throws Exception{Reader[] values=service.getReaders();if(values.length>32)throw new VmHardware.Failure("resource_limit","Android returned more than32 OMAPI readers.");List<ReaderRef> rows=new ArrayList<>();for(Reader value:values)rows.add(remember(value));JSONArray result=new JSONArray();for(int i=offset;i<Math.min(offset+limit,rows.size());i++){ReaderRef ref=rows.get(i);result.put(VmHardware.object("id",ref.id,"name",ref.sdk.getName(),"present",ref.sdk.isSecureElementPresent()));}return VmHardware.object("readers",result,"total",rows.size(),"next",offset+result.length()<rows.size()?offset+result.length():-1);}
        public synchronized void close(){if(closed)return;state="closed";superClose();retire();readers.clear();}
        private void superClose(){try{super.close();}catch(IOException ignored){}}
        public void cancelIO(){close();}
    }
    static abstract class Child extends VmHardware.Handle {
        final Service root;
        Child(Service root,String kind){super(root.context,"secure_element",kind);this.root=root;}
        public void access(VmHardware.Context context)throws Exception{check();root.ready();}
        public void cancelIO(){root.close();}
    }
    static final class SessionHandle extends Child {
        final ReaderRef reader;final Set<ChannelHandle> channels=new LinkedHashSet<>();Session sdk;boolean closeQueued;
        SessionHandle(Service root,ReaderRef reader){super(root,"secure_element_session");this.reader=reader;}
        void created(Session value){synchronized(root){sdk=value;if(closed||root.closed||root.state.equals("error"))queueClose();}}
        void queueClose(){if(closeQueued||sdk==null)return;closeQueued=true;Session value=sdk;root.post(()->{value.close();synchronized(root){root.sessions.remove(this);for(ChannelHandle child:new ArrayList<>(channels)){root.channels.remove(child);child.closeLocally();}channels.clear();}});}
        void ready()throws Exception{access(root.context);if(sdk==null||sdk.isClosed())throw new VmHardware.Failure("disconnected","This OMAPI session is closed.");}
        public Object info()throws Exception{root.begin();try{ready();return VmHardware.object("kind",kind,"reader",reader.id,"sdk_closed",sdk.isClosed(),"atr",blob(sdk.getATR()));}finally{root.end();}}
        public void close(){synchronized(root){if(closed)return;try{super.close();}catch(IOException ignored){}for(ChannelHandle child:new ArrayList<>(channels))child.closeLocally();queueClose();}}
    }
    static final class ChannelHandle extends Child {
        final SessionHandle session;Channel sdk;boolean closeQueued,exchanging;byte[] command,response;int written,responseId;
        ChannelHandle(SessionHandle session){super(session.root,"secure_element_channel");this.session=session;}
        void created(Channel value){synchronized(root){sdk=value;if(closed||session.closed||root.closed||root.state.equals("error"))queueClose();}}
        void ready()throws Exception{access(root.context);if(session.closed||sdk==null||!sdk.isOpen())throw new VmHardware.Failure("disconnected","This OMAPI channel is closed.");}
        public Object info()throws Exception{root.begin();try{ready();return VmHardware.object("kind",kind,"reader",session.reader.id,"basic",sdk.isBasicChannel(),"sdk_open",sdk.isOpen(),"select_response",blob(sdk.getSelectResponse()));}finally{root.end();}}
        void closeLocally(){synchronized(this){if(closed)return;try{super.close();}catch(IOException ignored){}if(command!=null)Arrays.fill(command,(byte)0);if(response!=null)Arrays.fill(response,(byte)0);command=null;response=null;}}
        synchronized int command(int bytes)throws Exception{check();if(exchanging)throw new VmHardware.Failure("busy","A channel APDU is already in flight.");if(command!=null)Arrays.fill(command,(byte)0);command=new byte[bytes];written=0;return 1;}
        synchronized int append(int offset,byte[] bytes)throws Exception{check();if(exchanging)throw new VmHardware.Failure("busy","A channel APDU is already in flight.");if(command==null||offset!=written||bytes.length>command.length-written)throw new VmHardware.Failure("invalid_argument","Fill an allocated APDU command sequentially without gaps or overflow.");System.arraycopy(bytes,0,command,written,bytes.length);written+=bytes.length;return bytes.length;}
        synchronized byte[] take()throws Exception{check();if(exchanging)throw new VmHardware.Failure("busy","A channel APDU is already in flight.");if(command==null||written!=command.length)throw new VmHardware.Failure("incomplete_command","Fill the entire staged APDU before sending.");byte[] value=command;command=null;written=0;return value;}
        boolean selectNext()throws Exception{
            synchronized(this){check();if(exchanging)throw new VmHardware.Failure("busy","Only one APDU or applet selection may be in flight per channel.");exchanging=true;}
            try{boolean selected=sdk.selectNext();ready();return selected;}finally{synchronized(this){exchanging=false;}}
        }
        Object exchange(byte[] value)throws Exception{
            synchronized(this){check();if(exchanging)throw new VmHardware.Failure("busy","Only one APDU may be in flight per channel.");if(responseId==Integer.MAX_VALUE)throw new VmHardware.Failure("resource_limit","Reopen this channel after exhausting response IDs.");if(value==null)value=take();exchanging=true;responseId++;if(response!=null)Arrays.fill(response,(byte)0);response=null;}
            try{byte[] result=sdk.transmit(value);ready();if(result==null||result.length<2||result.length>65538)throw new VmHardware.Failure("size_limit","Android returned an invalid or oversized extended APDU response.");synchronized(this){check();response=result.clone();return page(responseId,0,VmHardware.MAX_BYTES);}}
            finally{Arrays.fill(value,(byte)0);synchronized(this){exchanging=false;}}
        }
        synchronized Object page(int id,int offset,int limit)throws Exception{check();if(response==null||id!=responseId)throw new VmHardware.Failure("stale_response","Use the response ID returned by this channel's most recent successful APDU.");if(offset>response.length)throw new VmHardware.Failure("invalid_argument","APDU response offset exceeds its actual size.");int end=Math.min(response.length,offset+limit);return VmHardware.object("id",responseId,"value",blob(Arrays.copyOfRange(response,offset,end)),"total",response.length,"next",end<response.length?end:-1,"status_word",((response[response.length-2]&255)<<8)|(response[response.length-1]&255));}
        void queueClose(){if(closeQueued||sdk==null)return;closeQueued=true;Channel value=sdk;root.post(()->{value.close();synchronized(root){root.channels.remove(this);session.channels.remove(this);}});}
        public void close(){synchronized(root){closeLocally();queueClose();}}
    }
    static Object blob(byte[] bytes)throws Exception{return bytes==null?JSONObject.NULL:VmHardware.bytes(bytes.clone());}
    static VmHardware.Failure error(Exception error){String code=error instanceof SecurityException?"access_denied":error instanceof NoSuchElementException?"applet_not_found":error instanceof UnsupportedOperationException?"unsupported_operation":error instanceof IllegalArgumentException?"invalid_argument":error instanceof IllegalStateException?"disconnected":error instanceof IOException?"io_error":"platform_error";return new VmHardware.Failure(code,MainActivity.safe(error)+(error instanceof IOException?" APDU completion may be uncertain; do not automatically replay a write.":""));}
    static Object call(VmHardware.Context context,String op,JSONArray a)throws Exception{
        if(Build.VERSION.SDK_INT<28)throw new VmHardware.Failure("unsupported","The public OMAPI API requires Android9 or newer.");
        if(op.equals("se_open")){int timeout=VmHardware.integer(a,0,500,30000);if(!SERVICES.tryAcquire())throw new VmHardware.Failure("busy","Eight OMAPI services are active or awaiting confirmed SDK teardown.");Service root=new Service(context);VmHardware.blocking(root);try{root.start(timeout);return VmHardware.add(root);}catch(Exception error){root.close();throw error(error);}finally{VmHardware.unblocking();}}
        VmHardware.Handle base=VmHardware.handle(context,VmHardware.text(a,0,128));Service root=base instanceof Service?(Service)base:base instanceof Child?((Child)base).root:null;if(root==null)throw new VmHardware.Failure("wrong_handle","Use an OMAPI service, session or channel handle.");base.access(context);SEService service;synchronized(root){root.begin();service=root.sdk;}VmHardware.blocking(root);
        try{
            if(op.equals("se_readers")){if(!(base instanceof Service))throw new VmHardware.Failure("wrong_handle","Enumerate readers on an OMAPI service.");return root.page(service,VmHardware.integer(a,1,0,32),VmHardware.integer(a,2,1,16));}
            if(op.equals("se_uicc")){if(!(base instanceof Service))throw new VmHardware.Failure("wrong_handle","Select UICC readers on an OMAPI service.");if(Build.VERSION.SDK_INT<30)throw new VmHardware.Failure("unsupported_operation","UICC slot selection requires Android11 or newer.");ReaderRef ref=root.remember(service.getUiccReader(VmHardware.integer(a,1,1,Integer.MAX_VALUE)));return VmHardware.object("id",ref.id,"name",ref.sdk.getName(),"present",ref.sdk.isSecureElementPresent());}
            if(op.equals("se_session")){if(!(base instanceof Service))throw new VmHardware.Failure("wrong_handle","Open a session from an OMAPI service and its reader ID.");ReaderRef reader=root.reader(VmHardware.text(a,1,128));SessionHandle session; synchronized(root){if(root.sessions.size()>=16)throw new VmHardware.Failure("resource_limit","At most16 sessions may be active or awaiting cleanup on this service.");session=new SessionHandle(root,reader);root.sessions.add(session);}try{Session sdk=reader.sdk.openSession();if(sdk==null)throw new VmHardware.Failure("unavailable","Android returned no OMAPI session.");session.created(sdk);session.ready();return VmHardware.add(session);}catch(Exception error){session.close();synchronized(root){if(session.sdk==null)root.sessions.remove(session);}throw error;}}
            if(op.equals("se_channel")){if(!(base instanceof SessionHandle))throw new VmHardware.Failure("wrong_handle","Open a channel on an OMAPI session.");SessionHandle session=(SessionHandle)base;byte[] aid=VmHardware.data(a.get(1));boolean basic=VmHardware.integer(a,2,0,1)==1;byte p2=(byte)VmHardware.integer(a,3,0,255);if(aid.length!=0&&(aid.length<5||aid.length>16))throw new VmHardware.Failure("invalid_argument","An applet AID is empty for the default applet or5..16 bytes.");session.ready();ChannelHandle channel;synchronized(root){if(root.channels.size()>=32)throw new VmHardware.Failure("resource_limit","At most32 channels may be active or awaiting cleanup on this service.");channel=new ChannelHandle(session);root.channels.add(channel);session.channels.add(channel);}try{Channel sdk=basic?session.sdk.openBasicChannel(aid.length==0?null:aid,p2):session.sdk.openLogicalChannel(aid.length==0?null:aid,p2);if(sdk==null)throw new VmHardware.Failure("channel_unavailable","The secure element did not allocate a channel.");channel.created(sdk);channel.ready();return VmHardware.add(channel);}catch(Exception error){channel.close();synchronized(root){if(channel.sdk==null){root.channels.remove(channel);session.channels.remove(channel);}}throw error;}}
            if(!(base instanceof ChannelHandle))throw new VmHardware.Failure("wrong_handle","Use an OMAPI channel for APDU I/O.");ChannelHandle channel=(ChannelHandle)base;channel.ready();if(op.equals("se_select_response"))return blob(channel.sdk.getSelectResponse());if(op.equals("se_select_next"))return channel.selectNext();if(op.equals("se_command"))return channel.command(VmHardware.integer(a,1,4,65544));if(op.equals("se_command_write"))return channel.append(VmHardware.integer(a,1,0,65544),VmHardware.data(a.get(2)));if(op.equals("se_response"))return channel.page(VmHardware.integer(a,1,1,Integer.MAX_VALUE),VmHardware.integer(a,2,0,65538),VmHardware.integer(a,3,1,VmHardware.MAX_BYTES));if(op.equals("se_send"))return channel.exchange(null);if(op.equals("se_transmit")){byte[] command=VmHardware.data(a.get(1));if(command.length<4)throw new VmHardware.Failure("invalid_argument","An APDU command requires at least4 bytes.");return channel.exchange(command);}throw new VmHardware.Failure("unsupported_operation","Unknown OMAPI channel operation.");
        }catch(VmHardware.Failure failure){throw failure;}catch(Exception failure){if(failure instanceof IOException||failure instanceof IllegalStateException){if(base instanceof Child)((Child)base).close();}throw error(failure);}
        finally{VmHardware.unblocking();root.end();}
    }
}
