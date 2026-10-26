package org.flexscript.collie;

import android.graphics.*;
import android.media.*;
import android.os.SystemClock;
import android.view.*;
import java.io.*;
import java.nio.ByteBuffer;
import java.util.concurrent.*;
import java.util.zip.Adler32;
import org.json.*;

/** Debug-only independent pixel/container validation; never fabricates projection callbacks. */
public final class HardwareScreenChecks {
    final MainActivity host;final File root;final VmHardware.Context context;final JSONArray checks=new JSONArray();
    HardwareScreenChecks(MainActivity h,File r){host=h;root=r;context=new VmHardware.Context(h,r);}
    public static JSONObject run(MainActivity host,File root)throws Exception{return new HardwareScreenChecks(host,root).overlay();}
    public static JSONObject runFrame(MainActivity host,File root)throws Exception{return new HardwareScreenChecks(host,root).frame();}
    public static JSONObject runVideo(MainActivity host,File root)throws Exception{return new HardwareScreenChecks(host,root).video();}
    public static JSONObject runBackground(MainActivity host,File root)throws Exception{return new HardwareScreenChecks(host,root).background();}
    void check(boolean ok,String label)throws Exception{if(!ok)throw new IOException(label);checks.put(label);}
    static String q(String s){return JSONObject.quote(s).replace("\\/","/");}
    JSONObject vm(String source)throws Exception{JSONObject o=host.engineAt(root,3,new JSONObject().put("config",host.workerConfig(root,0)).put("source",source).put("call_id","screen-fixture").put("history",new JSONArray()));if(!o.optString("state").equals("continue")||o.optInt("exit_code")!=0)throw new IOException("Screen fixture: "+o);return o;}
    String state(String name)throws Exception{return vm("fn main(){let v=state_get("+q(name)+");db_io(0,1,db_word(v),db_bytes(v));return 0;}").getString("stdout");}
    JSONObject report()throws Exception{return new JSONObject().put("ok",true).put("checks",checks).put("physical_devices_verified",false);}
    JSONObject overlay()throws Exception{
        CountDownLatch ready=new CountDownLatch(1);host.runOnUiThread(()->{View pattern=new View(host){protected void onDraw(Canvas c){c.drawColor(Color.RED);Paint p=new Paint();p.setColor(Color.GREEN);c.drawRect(0,getHeight()/2,getWidth(),getHeight(),p);}};host.addContentView(pattern,new ViewGroup.LayoutParams(-1,-1));ready.countDown();});if(!ready.await(5,TimeUnit.SECONDS))throw new IOException("Pattern UI timeout");check(true,"owned debug Activity displays an independent solid red/green test pattern");return report();
    }
    JSONObject frame()throws Exception{
        String id=state("screen");HardwareScreenCapture.Session s=VmHardware.handle(context,id,HardwareScreenCapture.Session.class);s.pause(false);overlay();
        long deadline=SystemClock.elapsedRealtime()+7000;boolean pattern=false;while(!pattern&&SystemClock.elapsedRealtime()<deadline){synchronized(s){for(HardwareScreenCapture.Frame candidate:s.frames.values())if(pattern(candidate)){pattern=true;break;}}if(!pattern)Thread.sleep(30);}
        check(pattern,"actual SDK callbacks deliver the newly drawn owned test pattern before pixels are inspected");s.pause(true);Thread.sleep(150);
        HardwareScreenCapture.Frame f=null;synchronized(s){for(HardwareScreenCapture.Frame candidate:s.frames.values())if(pattern(candidate))f=candidate;}
        if(f==null)throw new IOException("No retained test-pattern frame after surface pause");String fid=f.id;
        check(f.width>0&&f.height>0&&f.format==PixelFormat.RGBA_8888&&f.timestamp>0,"actual SDK ImageReader produced timestamped RGBA pixels from the consented display");
        File foreign=new File(root,"foreign-screen");if(!new File(foreign,"files").mkdirs())throw new IOException("Cannot create owned workspace fixture");
        try{VmHardware.handle(new VmHardware.Context(host,foreign),id);throw new IOException("Projection handle crossed workspace boundary");}catch(VmHardware.Failure expected){check(expected.code.equals("stale_handle"),"a foreign workspace cannot resolve the live projection or its frame capabilities");}
        int reds=0,greens=0;Adler32 checksum=new Adler32();int length;
        synchronized(f){ByteBuffer bytes=f.planes[0].duplicate();length=bytes.remaining();byte[] page=new byte[4096];while(bytes.hasRemaining()){int n=Math.min(page.length,bytes.remaining());bytes.get(page,0,n);checksum.update(page,0,n);}ByteBuffer b=f.planes[0].duplicate();for(int y=0;y<f.height;y+=2)for(int x=0;x<f.width;x+=2){int at=y*f.rows[0]+x*f.pixels[0];if(at+2>=b.limit())continue;int r=b.get(at)&255,g=b.get(at+1)&255,blue=b.get(at+2)&255;if(r>240&&g<15&&blue<15)reds++;if(g>240&&r<15&&blue<15)greens++;}}
        check(reds>f.width*f.height/100&&greens>f.width*f.height/100,"captured pixels contain both independently drawn red and green regions, rather than an empty or unrelated frame");
        for(int offset=0;offset<length;offset+=16384){int count=Math.min(16384,length-offset);Adler32 pageSum=new Adler32();synchronized(f){ByteBuffer page=f.planes[0].duplicate();page.position(offset);byte[] bytes=new byte[count];page.get(bytes);pageSum.update(bytes);}
            vm("fn main(){let p=screen_frame_read("+q(id)+","+q(fid)+",0,"+offset+",16384);if !p{return 1;}let v=device_field(p,\"value\");if db_bytes(v)!="+count+"||db_word(device_field(p,\"total\"))!="+length+"{return 2;}let a=1;let b=0;let i=0;while i<db_bytes(v){a=(a+load8(db_word(v)+i))%65521;b=(b+a)%65521;i=i+1;}if ((b<<16)|a)!="+pageSum.getValue()+"{return 3;}return 0;}");
        }
        vm("fn main(){let p=screen_frame_read("+q(id)+","+q(fid)+",0,"+length+",32);if db_bytes(device_field(p,\"value\"))||db_word(device_field(p,\"next\"))!=-1{return 1;}return 0;}");
        check(true,"every actual plane byte crosses bounded VM pages with exact independent Adler32, length and EOF validation");
        vm("fn main(){if screen_frame_read("+q(id)+","+q(fid)+",0,"+(length+1)+",1)||screen_frame_read("+q(id)+","+q(fid)+",3,0,1){return 1;}if !screen_frame_close("+q(id)+","+q(fid)+"){return 2;}if screen_frame_info("+q(id)+","+q(fid)+"){return 3;}if !worker_equal(db_word(db_at(device_error(),0)),\"stale_frame\"){return 4;}return 0;}");check(true,"plane/offset bounds and explicit frame close are enforced by the actual VM transport");return report();
    }
    static boolean pattern(HardwareScreenCapture.Frame f){synchronized(f){if(f.closed||f.planes==null)return false;ByteBuffer b=f.planes[0].duplicate();int red=0,green=0;for(int y=0;y<f.height;y+=4)for(int x=0;x<f.width;x+=4){int at=y*f.rows[0]+x*f.pixels[0];if(at+2>=b.limit())continue;int r=b.get(at)&255,g=b.get(at+1)&255,blue=b.get(at+2)&255;if(r>240&&g<15&&blue<15)red++;if(g>240&&r<15&&blue<15)green++;}return red>f.width*f.height/1600&&green>f.width*f.height/1600;}}
    JSONObject background()throws Exception{
        String id=state("screen");HardwareScreenCapture.Session s=VmHardware.handle(context,id,HardwareScreenCapture.Session.class);s.clearFrames();
        CountDownLatch ready=new CountDownLatch(1);host.runOnUiThread(()->{host.moveTaskToBack(true);ready.countDown();});if(!ready.await(5,TimeUnit.SECONDS))throw new IOException("Background fixture UI timeout");
        long end=SystemClock.elapsedRealtime()+5000;while(host.hardwareVisible&&SystemClock.elapsedRealtime()<end)Thread.sleep(20);
        check(!host.hardwareVisible,"the actual Activity onStop completed while the projection foreground service remains owned");
        vm("fn main(){let h="+q(id)+";let i=0;while i<20{let p=screen_frames(h,0,2);if db_count(device_field(p,\"frames\")){return 0;}device_wait(h,500);i=i+1;}return 1;}");
        synchronized(s){check(!s.closed&&s.state.equals("capturing")&&s.service!=null&&!s.serviceStopped&&!s.frames.isEmpty(),"real ImageReader callbacks and bounded VM frame reads continue while the Activity is hidden");}
        return report();
    }
    JSONObject video()throws Exception{
        String id=state("screen_video");HardwareScreenVideo.Video v=VmHardware.handle(context,id,HardwareScreenVideo.Video.class);check(v.released&&v.state.equals("stopped")&&v.file.length()>0,"the actual screen recorder stopped, released its SDK objects and finalized nonempty MP4 bytes");
        MediaExtractor extractor=new MediaExtractor();int videos=0,audio=0,samples=0;try{extractor.setDataSource(v.file.getAbsolutePath());for(int i=0;i<extractor.getTrackCount();i++){MediaFormat f=extractor.getTrackFormat(i);String mime=f.getString(MediaFormat.KEY_MIME);if(mime.startsWith("video/")){videos++;check(f.getInteger(MediaFormat.KEY_WIDTH)==v.options.width&&f.getInteger(MediaFormat.KEY_HEIGHT)==v.options.height,"independent MediaExtractor confirms the actual recorded dimensions");extractor.selectTrack(i);ByteBuffer b=ByteBuffer.allocate(2*1024*1024);long prior=-1;while(samples<500){int n=extractor.readSampleData(b,0);if(n<0)break;long t=extractor.getSampleTime();if(t<prior)throw new IOException("Nonmonotonic screen sample timestamps");prior=t;samples++;if(!extractor.advance())break;}extractor.unselectTrack(i);}else if(mime.startsWith("audio/"))audio++;}}finally{extractor.release();}
        check(videos==1&&samples>0&&audio==(v.audio?1:0),"the independent parser finds real video samples with exactly the requested presence/absence of microphone audio");
        Adler32 checksum=new Adler32();long length=0;try(InputStream in=new FileInputStream(v.file)){byte[] b=new byte[4096];for(int n;(n=in.read(b))!=-1;){checksum.update(b,0,n);length+=n;}}
        vm("fn main(){let h="+q(id)+";screen_video_seek(h,0);let a=1;let b=0;let count=0;let done=0;while !done{let v=device_read(h,32768,1000);if db_kind(v)==0{done=1;}else{if db_kind(v)!=3{return 1;}let i=0;while i<db_bytes(v){a=(a+load8(db_word(v)+i))%65521;b=(b+a)%65521;i=i+1;}count=count+db_bytes(v);}}if count!="+length+"||((b<<16)|a)!="+checksum.getValue()+"{return 2;}if screen_video_seek(h,"+(length+1)+")||device_write(h,db_text(\"no\")){return 3;}return 0;}");check(true,"every finalized screen MP4 byte matches independent file length/checksum through VM read, seek, EOF and write rejection");return report();
    }
}
