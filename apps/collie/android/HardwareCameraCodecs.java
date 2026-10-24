package org.flexscript.collie;

import android.media.*;
import android.os.Build;
import android.util.Range;
import java.util.*;
import org.json.*;

/** Public encoder capability snapshots and requested MediaRecorder profile/level. */
final class HardwareCameraCodecs {
    static boolean supports(String op){return op.equals("camera_video_codecs")||op.equals("camera_video_codec_profiles")||op.equals("camera_video_codec_info")||op.equals("camera_video_codec_support");}
    static String mime(int codec){return codec==1?"video/avc":codec==2?"video/hevc":"video/av01";}
    static List<MediaCodecInfo> encoders(String mime)throws Exception{
        MediaCodecInfo[] infos=new MediaCodecList(MediaCodecList.REGULAR_CODECS).getCodecInfos();if(infos.length>1024)throw new VmHardware.Failure("size_limit","Android returned more than1024 codecs.");
        List<MediaCodecInfo> rows=new ArrayList<>();for(MediaCodecInfo info:infos)if(info.isEncoder())for(String type:info.getSupportedTypes())if(type.equalsIgnoreCase(mime)){if(info.getName().length()>256)throw new VmHardware.Failure("size_limit","Android returned an oversized codec name.");rows.add(info);break;}
        if(rows.size()>128)throw new VmHardware.Failure("size_limit","Android returned more than128 encoders for this format.");return rows;
    }
    static MediaCodecInfo find(List<MediaCodecInfo> rows,String name)throws Exception{for(MediaCodecInfo info:rows)if(info.getName().equals(name))return info;throw new VmHardware.Failure("unsupported_codec","That exact regular encoder name/format is absent from Android's current inventory.");}
    static JSONObject range(Range<? extends Number> value)throws Exception{return VmHardware.object("min",number(value.getLower()),"max",number(value.getUpper()));}
    static Object number(Number value)throws Exception{return value instanceof Double||value instanceof Float?VmHardware.real(value.doubleValue()):value;}
    static JSONObject row(MediaCodecInfo info,String mime)throws Exception{
        MediaCodecInfo.CodecCapabilities cap=info.getCapabilitiesForType(mime);if(cap.profileLevels.length>128)throw new VmHardware.Failure("size_limit","Android returned more than128 profile/level entries.");
        JSONObject row=VmHardware.object("name",info.getName(),"mime",mime,"profile_levels",cap.profileLevels.length,"surface_input",surface(cap));
        if(Build.VERSION.SDK_INT>=29)Api29.fields(row,info);else row.put("canonical_name",JSONObject.NULL).put("alias",JSONObject.NULL).put("hardware_accelerated",JSONObject.NULL).put("software_only",JSONObject.NULL).put("vendor",JSONObject.NULL);return row;
    }
    static boolean surface(MediaCodecInfo.CodecCapabilities cap){for(int color:cap.colorFormats)if(color==MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)return true;return false;}
    static Object call(VmHardware.Context c,String op,JSONArray a)throws Exception{
        int codec=VmHardware.integer(a,0,1,3);String mime=mime(codec);List<MediaCodecInfo> infos=encoders(mime);
        if(op.equals("camera_video_codecs")){int offset=VmHardware.integer(a,1,0,128),limit=VmHardware.integer(a,2,1,16),end=Math.min(infos.size(),offset+limit);JSONArray rows=new JSONArray();for(int i=offset;i<end;i++)rows.put(row(infos.get(i),mime));return HardwareCamera.page("codecs",rows,end,infos.size()).put("codec",codec).put("mime",mime);}
        MediaCodecInfo info=find(infos,VmHardware.text(a,1,256));MediaCodecInfo.CodecCapabilities cap=info.getCapabilitiesForType(mime);
        if(op.equals("camera_video_codec_profiles")){if(cap.profileLevels.length>128)throw new VmHardware.Failure("size_limit","Android returned more than128 profile/level entries.");int offset=VmHardware.integer(a,2,0,128),limit=VmHardware.integer(a,3,1,16),end=Math.min(cap.profileLevels.length,offset+limit);JSONArray rows=new JSONArray();for(int i=offset;i<end;i++)rows.put(VmHardware.object("profile",cap.profileLevels[i].profile,"level",cap.profileLevels[i].level));return HardwareCamera.page("profiles",rows,end,cap.profileLevels.length).put("name",info.getName()).put("mime",mime);}
        if(op.equals("camera_video_codec_support")){int width=VmHardware.integer(a,2,1,32768),height=VmHardware.integer(a,3,1,32768),fps=VmHardware.integer(a,4,1,960),bitrate=VmHardware.integer(a,5,1,50000000);MediaFormat format=MediaFormat.createVideoFormat(mime,width,height);format.setInteger(MediaFormat.KEY_FRAME_RATE,fps);format.setInteger(MediaFormat.KEY_BIT_RATE,bitrate);format.setInteger(MediaFormat.KEY_COLOR_FORMAT,MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface);return VmHardware.object("name",info.getName(),"mime",mime,"supported",cap.isFormatSupported(format));}
        MediaCodecInfo.VideoCapabilities video=cap.getVideoCapabilities();MediaCodecInfo.EncoderCapabilities encoder=cap.getEncoderCapabilities();if(video==null||encoder==null)throw new VmHardware.Failure("invalid_response","Android omitted encoder/video capabilities for its video encoder.");
        return row(info,mime).put("bitrate",range(video.getBitrateRange())).put("width",range(video.getSupportedWidths())).put("height",range(video.getSupportedHeights())).put("frame_rates",range(video.getSupportedFrameRates())).put("width_alignment",video.getWidthAlignment()).put("height_alignment",video.getHeightAlignment()).put("complexity",range(encoder.getComplexityRange())).put("quality",range(encoder.getQualityRange())).put("cq",encoder.isBitrateModeSupported(MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CQ)).put("vbr",encoder.isBitrateModeSupported(MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_VBR)).put("cbr",encoder.isBitrateModeSupported(MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CBR));
    }
    static final class Encoding {
        final JSONArray base;final int profile,level;
        Encoding(JSONArray raw)throws Exception{if(raw.length()==4){if(!VmHardware.text(raw,0,32).equals("video_encoding"))throw new VmHardware.Failure("invalid_argument","Unknown video encoding record.");base=CameraValues.list(raw.get(1),3,9);profile=VmHardware.integer(raw,2,1,Integer.MAX_VALUE);level=VmHardware.integer(raw,3,1,Integer.MAX_VALUE);}else{base=raw;profile=level=0;}}
        void validate(int codec)throws Exception{if(profile!=0&&codec==0)throw new VmHardware.Failure("invalid_argument","Explicit profile/level requires an explicit encoder, not DEFAULT.");}
        void apply(MediaRecorder recorder){if(profile!=0)recorder.setVideoEncodingProfileLevel(profile,level);}
        Object requested()throws Exception{return profile==0?JSONObject.NULL:VmHardware.object("profile",profile,"level",level);}
    }
    static final class Api29 {static void fields(JSONObject row,MediaCodecInfo info)throws Exception{row.put("canonical_name",info.getCanonicalName()).put("alias",info.isAlias()).put("hardware_accelerated",info.isHardwareAccelerated()).put("software_only",info.isSoftwareOnly()).put("vendor",info.isVendor());}}
}
