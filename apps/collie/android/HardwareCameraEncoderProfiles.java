package org.flexscript.collie;

import android.graphics.ImageFormat;
import android.hardware.camera2.params.OutputConfiguration;
import android.media.*;
import android.os.Build;
import java.util.*;
import org.json.*;

/** Public recommended encoder profiles, not constructed or reflectively selected codecs. */
final class HardwareCameraEncoderProfiles {
    static boolean supports(String op){return op.equals("camera_video_qualities")||op.equals("camera_video_profiles");}
    static int quality(JSONArray a,int at)throws Exception{int q=VmHardware.integer(a,at,0,2008);if(!(q<=13||q>=1000&&q<=1013||q>=2000&&q<=2008))throw new VmHardware.Failure("invalid_argument","Choose a public CamcorderProfile QUALITY value.");return q;}
    static Object call(VmHardware.Context c,String op,JSONArray a)throws Exception{
        String id=VmHardware.text(a,0,128);HardwareCamera.characteristics(c,id);
        if(Build.VERSION.SDK_INT<31)throw new VmHardware.Failure("unsupported_operation","Recommended EncoderProfiles require Android12+.");
        if(op.equals("camera_video_qualities"))return Api31.qualities(id,VmHardware.integer(a,1,0,128),VmHardware.integer(a,2,1,16));
        return Api31.profiles(id,quality(a,1),VmHardware.integer(a,2,0,1),VmHardware.integer(a,3,0,128),VmHardware.integer(a,4,1,16));
    }
    static final class Selection {
        final int quality,index,audioIndex,width,height,fps,bitrate,duration,format,colorSpace;final long limit,dynamicRange,useCase;final Object video,audio;
        Selection(HardwareCamera.Camera camera,JSONArray row,boolean sound)throws Exception{
            if(Build.VERSION.SDK_INT<31)throw new VmHardware.Failure("unsupported_operation","Recommended EncoderProfiles require Android12+.");
            CameraValues.list(row,8,9);if(!VmHardware.text(row,0,32).equals("encoder_profile"))throw new VmHardware.Failure("invalid_argument","Unknown camera video option record.");
            quality=quality(row,1);if(quality>=1000)throw new VmHardware.Failure("unsupported_operation","Time-lapse and constrained high-speed capture need separate session/rate controls; no regular recording is substituted.");
            index=VmHardware.integer(row,2,0,127);duration=VmHardware.integer(row,3,500,120000);limit=VmHardware.longInteger(row,4,65536,64L*1024*1024);dynamicRange=VmHardware.longInteger(row,5,0,Long.MAX_VALUE);useCase=VmHardware.longInteger(row,6,0,Long.MAX_VALUE);colorSpace=HardwareCameraOutput.color(row,7);
            if(!sound&&row.length()==9)throw new VmHardware.Failure("invalid_argument","An explicit audio profile requires camera_video_audio_start.");audioIndex=sound?(row.length()==9?VmHardware.integer(row,8,0,127):0):-1;
            EncoderProfiles profiles=Api31.read(camera.cameraId,quality);if(profiles==null||index>=profiles.getVideoProfiles().size())throw new VmHardware.Failure("unsupported_profile","That recommended video profile is absent.");
            EncoderProfiles.VideoProfile p=profiles.getVideoProfiles().get(index);video=p;width=p.getWidth();height=p.getHeight();fps=p.getFrameRate();bitrate=p.getBitrate();format=profiles.getRecommendedFileFormat();
            if(width<1||width>32768||height<1||height>32768||fps<1||fps>120||bitrate<64000||bitrate>50000000)throw new VmHardware.Failure("resource_limit","The exact SDK profile exceeds the bounded recorder dimensions/frame-rate/bitrate; no smaller profile is substituted.");
            if(sound){if(audioIndex>=profiles.getAudioProfiles().size())throw new VmHardware.Failure("unsupported_profile","That recommended audio profile is absent.");audio=profiles.getAudioProfiles().get(audioIndex);}else audio=null;
            HardwareCameraOutput.validateProfile(camera.ch,dynamicRange,useCase);HardwareCameraOutput.validateColor(camera.ch,ImageFormat.PRIVATE,actualProfile(),colorSpace);
            if(Build.VERSION.SDK_INT>=33)Api33.match(p,actualProfile());
        }
        long actualProfile(){return dynamicRange==0?1:dynamicRange;}
        void apply(MediaRecorder recorder){Api31.apply(recorder,video,audio);}
        Object requested()throws Exception{return Api31.video((EncoderProfiles.VideoProfile)video,index);}
        Object requestedAudio()throws Exception{return audio==null?JSONObject.NULL:Api31.audio((EncoderProfiles.AudioProfile)audio,audioIndex);}
        void configure(OutputConfiguration output){HardwareCameraOutput.apply(output,dynamicRange,useCase);}
    }
    static final class Api31 {
        static EncoderProfiles read(String id,int quality)throws Exception{EncoderProfiles p=CamcorderProfile.getAll(id,quality);if(p!=null&&(p.getVideoProfiles().size()>128||p.getAudioProfiles().size()>128))throw new VmHardware.Failure("size_limit","Android returned more than128 encoder profiles.");return p;}
        static Object qualities(String id,int offset,int limit)throws Exception{
            JSONArray all=new JSONArray();for(int q=0;q<=2008;q++){if(!(q<=13||q>=1000&&q<=1013||q>=2000&&q<=2008))continue;EncoderProfiles p=read(id,q);if(p!=null)all.put(VmHardware.object("quality",q,"video_profiles",p.getVideoProfiles().size(),"audio_profiles",p.getAudioProfiles().size(),"duration_seconds",p.getDefaultDurationSeconds(),"file_format",p.getRecommendedFileFormat()));}
            JSONArray rows=new JSONArray();int end=Math.min(all.length(),offset+limit);for(int i=offset;i<end;i++)rows.put(all.get(i));return HardwareCamera.page("qualities",rows,end,all.length());
        }
        static Object profiles(String id,int quality,int kind,int offset,int limit)throws Exception{
            EncoderProfiles p=read(id,quality);int total=p==null?0:kind==0?p.getVideoProfiles().size():p.getAudioProfiles().size();int end=Math.min(total,offset+limit);JSONArray rows=new JSONArray();for(int i=offset;i<end;i++)rows.put(kind==0?video(p.getVideoProfiles().get(i),i):audio(p.getAudioProfiles().get(i),i));
            return HardwareCamera.page("profiles",rows,end,total).put("quality",quality).put("kind",kind).put("available",p!=null).put("duration_seconds",p==null?JSONObject.NULL:p.getDefaultDurationSeconds()).put("file_format",p==null?JSONObject.NULL:p.getRecommendedFileFormat()).put("hdr_fields_api",Build.VERSION.SDK_INT>=33);
        }
        static JSONObject video(EncoderProfiles.VideoProfile p,int index)throws Exception{JSONObject r=VmHardware.object("index",index,"codec",p.getCodec(),"mime",p.getMediaType(),"width",p.getWidth(),"height",p.getHeight(),"fps",p.getFrameRate(),"bitrate",p.getBitrate(),"profile",p.getProfile());if(Build.VERSION.SDK_INT>=33)Api33.fields(r,p);else r.put("hdr_format",JSONObject.NULL).put("bit_depth",JSONObject.NULL).put("chroma_subsampling",JSONObject.NULL);return r;}
        static JSONObject audio(EncoderProfiles.AudioProfile p,int index)throws Exception{return VmHardware.object("index",index,"codec",p.getCodec(),"mime",p.getMediaType(),"sample_rate",p.getSampleRate(),"channels",p.getChannels(),"bitrate",p.getBitrate(),"profile",p.getProfile());}
        static void apply(MediaRecorder recorder,Object video,Object audio){recorder.setVideoProfile((EncoderProfiles.VideoProfile)video);if(audio!=null)recorder.setAudioProfile((EncoderProfiles.AudioProfile)audio);}
    }
    static final class Api33 {
        static void fields(JSONObject row,EncoderProfiles.VideoProfile p)throws Exception{row.put("hdr_format",p.getHdrFormat()).put("bit_depth",p.getBitDepth()).put("chroma_subsampling",p.getChromaSubsampling());}
        static void match(EncoderProfiles.VideoProfile p,long range)throws Exception{
            int hdr=p.getHdrFormat(),bits=p.getBitDepth();boolean valid=hdr==0&&range==1||hdr==1&&range==2||hdr==2&&range==4||hdr==3&&range==8;
            if(hdr==4)valid=bits==10&&(range==16||range==32||range==64||range==128)||bits==8&&(range==256||range==512||range==1024||range==2048);
            if(!valid)throw new VmHardware.Failure("unsupported_combination","The camera dynamic range does not match the actual SDK encoder profile's HDR format/bit depth.");
        }
    }
}
