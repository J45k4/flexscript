package org.flexscript.collie;

import android.graphics.*;
import android.hardware.camera2.*;
import android.hardware.camera2.params.*;
import android.media.*;
import android.os.*;
import android.util.Size;
import java.io.*;
import java.util.*;
import org.json.*;

/** Independent public profile inventory and real MediaRecorder/container checks. */
final class HardwareCameraVideoProfileChecks {
    final HardwareCameraChecks t;final HardwareCamera.Camera camera;final String handle;final JSONObject facts;
    HardwareCameraVideoProfileChecks(HardwareCameraChecks t,String h,HardwareCamera.Camera c){this.t=t;handle=h;camera=c;facts=t.encoderProfiles;}
    static void run(HardwareCameraChecks t,String h,HardwareCamera.Camera c)throws Exception{new HardwareCameraVideoProfileChecks(t,h,c).run();}
    static String q(String s){return HardwareCameraChecks.q(s);}
    static boolean validQuality(int q){return q<=13||q>=1000&&q<=1013||q>=2000&&q<=2008;}
    JSONObject video(EncoderProfiles.VideoProfile p,int index)throws Exception{return VmHardware.object("index",index,"codec",p.getCodec(),"mime",p.getMediaType(),"width",p.getWidth(),"height",p.getHeight(),"fps",p.getFrameRate(),"bitrate",p.getBitrate(),"profile",p.getProfile(),"hdr_format",p.getHdrFormat(),"bit_depth",p.getBitDepth(),"chroma_subsampling",p.getChromaSubsampling());}
    JSONObject audio(EncoderProfiles.AudioProfile p,int index)throws Exception{return VmHardware.object("index",index,"codec",p.getCodec(),"mime",p.getMediaType(),"sample_rate",p.getSampleRate(),"channels",p.getChannels(),"bitrate",p.getBitrate(),"profile",p.getProfile());}
    void run()throws Exception{
        JSONArray qualities=new JSONArray();int videos=0,audios=0,hdr=0;
        for(int quality=0;quality<=2008;quality++)if(validQuality(quality)){
            EncoderProfiles p=CamcorderProfile.getAll(camera.cameraId,quality);
            if(p!=null){qualities.put(VmHardware.object("quality",quality,"video_profiles",p.getVideoProfiles().size(),"audio_profiles",p.getAudioProfiles().size(),"duration_seconds",p.getDefaultDurationSeconds(),"file_format",p.getRecommendedFileFormat()));videos+=p.getVideoProfiles().size();audios+=p.getAudioProfiles().size();for(EncoderProfiles.VideoProfile v:p.getVideoProfiles())if(v.getHdrFormat()!=0)hdr++;}
            for(int kind=0;kind<2;kind++){
                int total=p==null?0:kind==0?p.getVideoProfiles().size():p.getAudioProfiles().size();
                for(int offset=0;offset<=total;offset+=2){int end=Math.min(total,offset+2);JSONArray rows=new JSONArray();for(int i=offset;i<end;i++)rows.put(kind==0?video(p.getVideoProfiles().get(i),i):audio(p.getAudioProfiles().get(i),i));
                    JSONObject expected=VmHardware.object("profiles",rows,"total",total,"next",end<total?end:-1,"quality",quality,"kind",kind,"available",p!=null,"duration_seconds",p==null?JSONObject.NULL:p.getDefaultDurationSeconds(),"file_format",p==null?JSONObject.NULL:p.getRecommendedFileFormat(),"hdr_fields_api",true);
                    t.wirePage("camera_video_profiles("+q(camera.cameraId)+","+quality+","+kind+","+offset+",2)",expected);if(total==0)break;
                }
            }
        }
        for(int offset=0;offset<=qualities.length();offset+=3){int end=Math.min(qualities.length(),offset+3);JSONArray rows=new JSONArray();for(int i=offset;i<end;i++)rows.put(qualities.get(i));t.wirePage("camera_video_qualities("+q(camera.cameraId)+","+offset+",3)",VmHardware.object("qualities",rows,"total",qualities.length(),"next",end<qualities.length()?end:-1));}
        facts.put("qualities",qualities.length()).put("video_profiles",videos).put("audio_profiles",audios).put("hdr_profiles",hdr).put("inventory_verified",true).put("hdr_record_verified",false).put("physical_accuracy_verified",false);
        t.check(true,"every actual SDK recommended quality/video/audio profile crosses bounded VM pages with exact codec/MIME/rate/size/profile/HDR fields and EOF");
        int slots=HardwareCameraVideo.SLOTS.availablePermits(),generation=camera.generation;
        t.vm("fn main(){if camera_video_profiles("+q(camera.cameraId)+",999,0,0,1)||camera_video_profiles("+q(camera.cameraId)+",0,2,0,1)||camera_video_profiles("+q(camera.cameraId)+",0,0,-1,1)||camera_video_profiles("+q(camera.cameraId)+",0,0,0,17){return 1;}let o=camera_video_profile_options(0,127,10000,16777216,1,0,-1);if camera_video_start("+q(handle)+",o,db_list()){return 2;}o=camera_video_profile_options(2000,0,10000,16777216,1,0,-1);if camera_video_start("+q(handle)+",o,db_list()){return 3;}if !worker_equal(db_word(db_at(device_error(),0)),\"unsupported_operation\"){return 4;}return 0;}");
        t.check(slots==HardwareCameraVideo.SLOTS.availablePermits()&&camera.video==null&&camera.generation==generation,"bad profile pages, absent indices and unimplemented high-speed mode fail before recorder allocation or camera mutation");
        Choice normal=choose(false,false);if(normal==null)throw new IOException("No actual supported regular SDR profile for this camera fixture");
        t.vm("fn main(){let o=camera_video_audio_profile_options("+normal.quality+","+normal.index+",0,10000,16777216,1,0,-1);if camera_video_start("+q(handle)+",o,db_list()){return 1;}o=camera_video_profile_options("+normal.quality+","+normal.index+",10000,16777216,2,0,-1);if camera_video_start("+q(handle)+",o,db_list()){return 2;}return 0;}");
        t.check(slots==HardwareCameraVideo.SLOTS.availablePermits()&&camera.video==null&&camera.generation==generation,"silent recording rejects an audio-only option and mismatched HDR encoding/source before SDK preparation");
        record(normal,false);Choice high=choose(true,false);if(high!=null)record(high,false);
    }
    static final class Choice {int quality,index,audioIndex=-1,color=-1;long range=1,useCase;EncoderProfiles profiles;EncoderProfiles.VideoProfile video;}
    Choice choose(boolean hdr,boolean sound)throws Exception{
        Choice best=null;List<Size> sizes=Arrays.asList(camera.ch.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP).getOutputSizes(MediaRecorder.class));DynamicRangeProfiles dynamic=camera.ch.get(CameraCharacteristics.REQUEST_AVAILABLE_DYNAMIC_RANGE_PROFILES);
        for(int quality=0;quality<=13;quality++){EncoderProfiles p=CamcorderProfile.getAll(camera.cameraId,quality);if(p==null||sound&&p.getAudioProfiles().isEmpty())continue;
            for(int index=0;index<p.getVideoProfiles().size();index++){EncoderProfiles.VideoProfile v=p.getVideoProfiles().get(index);if((v.getHdrFormat()!=0)!=hdr||v.getFrameRate()>120||v.getBitrate()>50000000||!sizes.contains(new Size(v.getWidth(),v.getHeight())))continue;
                long range=1;if(hdr){range=v.getHdrFormat()==1?2:v.getHdrFormat()==2?4:v.getHdrFormat()==3?8:0;if(range==0||dynamic==null||!dynamic.getSupportedProfiles().contains(range))continue;}
                // Prefer AVC for a useful independently reported profile, then
                // minimize actual SDK geometry. This never alters its values.
                if(best!=null){boolean avc=v.getMediaType().equals("video/avc"),old=best.video.getMediaType().equals("video/avc");if(!avc&&old||avc==old&&(long)v.getWidth()*v.getHeight()>=(long)best.video.getWidth()*best.video.getHeight())continue;}
                Choice c=new Choice();c.quality=quality;c.index=index;c.video=v;c.profiles=p;c.range=range;c.audioIndex=sound?0:-1;
                long[] uses=camera.ch.get(CameraCharacteristics.SCALER_AVAILABLE_STREAM_USE_CASES);if(uses!=null)for(long value:uses)if(value==CameraMetadata.SCALER_AVAILABLE_STREAM_USE_CASES_VIDEO_RECORD)c.useCase=value;
                ColorSpaceProfiles colors=camera.ch.get(CameraCharacteristics.REQUEST_AVAILABLE_COLOR_SPACE_PROFILES);if(colors!=null)for(ColorSpace.Named named:colors.getSupportedColorSpaces(ImageFormat.PRIVATE))if(colors.getSupportedDynamicRangeProfiles(named,ImageFormat.PRIVATE).contains(range)&&(c.color<0||named.ordinal()<c.color))c.color=named.ordinal();
                best=c;
            }
        }return best;
    }
    void record(Choice chosen,boolean sound)throws Exception{
        String options=sound?"camera_video_audio_profile_options("+chosen.quality+","+chosen.index+","+chosen.audioIndex+",10000,16777216,"+chosen.range+","+chosen.useCase+","+chosen.color+")":"camera_video_profile_options("+chosen.quality+","+chosen.index+",10000,16777216,"+chosen.range+","+chosen.useCase+","+chosen.color+")";
        String id=t.vm("fn main(){let h="+(sound?"camera_video_audio_start":"camera_video_start")+"("+q(handle)+","+options+",db_list());if !h{return 1;}state_set(\"video\",h);db_io(0,1,db_word(h),db_bytes(h));return 0;}").getString("stdout");
        HardwareCameraVideo.Video owned=VmHardware.handle(t.context,id,HardwareCameraVideo.Video.class);
        try{
            t.vm("fn main(){let i=0;while i<30{let d=device_info("+q(id)+");if worker_equal(db_word(device_field(d,\"state\")),\"recording\"){return 0;}let e=device_wait("+q(id)+",1000);i=i+1;}return 1;}");
            t.check(owned.configuration!=null&&owned.configuration.getDynamicRangeProfile()==chosen.range&&owned.configuration.getStreamUseCase()==chosen.useCase&&camera.configurationColorSpace==chosen.color,"the actual recorder session retains the exact SDK-selected dynamic range, video stream use case and explicit session color space");
            t.wirePage("device_field(device_info("+q(id)+"),\"encoder_profile_requested\")",video(chosen.video,chosen.index));
            if(sound)t.wirePage("device_field(device_info("+q(id)+"),\"audio_profile_requested\")",audio(chosen.profiles.getAudioProfiles().get(chosen.audioIndex),chosen.audioIndex));
            Thread.sleep(1800);t.vm("fn main(){camera_video_stop("+q(id)+");let i=0;while i<30{let d=device_info("+q(id)+");if worker_equal(db_word(device_field(d,\"state\")),\"stopped\"){return 0;}if worker_equal(db_word(device_field(d,\"state\")),\"error\"){let e=device_field(d,\"error\");db_io(0,2,db_word(e),db_bytes(e));return 1;}device_wait("+q(id)+",1000);i=i+1;}return 2;}");
            MediaExtractor extractor=new MediaExtractor();try{extractor.setDataSource(owned.file.getAbsolutePath());boolean found=false;for(int i=0;i<extractor.getTrackCount();i++){MediaFormat f=extractor.getTrackFormat(i);String mime=f.getString(MediaFormat.KEY_MIME);if(mime.startsWith("video/")){found=true;t.check(mime.equals(chosen.video.getMediaType()),"the independent actual container MIME matches the chosen SDK encoder profile rather than a default substituted codec");if(f.containsKey(MediaFormat.KEY_PROFILE))facts.put(sound?"audio_record_video_profile":chosen.range==1?"sdr_container_profile":"hdr_container_profile",f.getInteger(MediaFormat.KEY_PROFILE));if(chosen.range!=1){t.check(f.getInteger(MediaFormat.KEY_COLOR_STANDARD)==MediaFormat.COLOR_STANDARD_BT2020&&f.getInteger(MediaFormat.KEY_COLOR_TRANSFER)==(chosen.range==2?MediaFormat.COLOR_TRANSFER_HLG:MediaFormat.COLOR_TRANSFER_ST2084),"the finalized actual HDR video track independently reports BT2020 and its requested HLG/PQ transfer");facts.put("hdr_record_verified",true);}}else if(sound&&mime.startsWith("audio/")){EncoderProfiles.AudioProfile p=chosen.profiles.getAudioProfiles().get(chosen.audioIndex);t.check(mime.equals(p.getMediaType())&&f.getInteger(MediaFormat.KEY_SAMPLE_RATE)==p.getSampleRate()&&f.getInteger(MediaFormat.KEY_CHANNEL_COUNT)==p.getChannels(),"the independently extracted actual audio track matches the selected recommended SDK codec, sample rate and channels");}}if(!found)throw new IOException("No actual encoded video track");}finally{extractor.release();}
            facts.put(sound?"audio_profile_record_verified":chosen.range==1?"sdr_profile_record_verified":"hdr_profile_record_verified",true);
            t.video();
        }finally{if(!owned.closed)VmHardware.close(t.context,id);}
    }
    static void audio(HardwareCameraChecks t,String handle,HardwareCamera.Camera camera)throws Exception{HardwareCameraVideoProfileChecks test=new HardwareCameraVideoProfileChecks(t,handle,camera);Choice chosen=test.choose(false,true);if(chosen==null)throw new IOException("No SDK audio/video profile for the recording fixture");test.record(chosen,true);}
}
