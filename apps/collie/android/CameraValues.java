package org.flexscript.collie;

import android.graphics.*;
import android.hardware.camera2.params.*;
import android.location.Location;
import android.os.Build;
import android.util.*;
import java.util.*;
import org.json.*;

/** Bounded public Camera2 value transport, never a host reflection/method bridge. */
final class CameraValues {
    static JSONArray list(Object value,int min,int max)throws Exception{if(!(value instanceof JSONArray)||((JSONArray)value).length()<min||((JSONArray)value).length()>max)throw new VmHardware.Failure("invalid_argument","Expected a bounded camera value list.");return (JSONArray)value;}
    static long integer(Object value,long min,long max)throws Exception{return VmHardware.longInteger(new JSONArray().put(value),0,min,max);}
    static double number(Object value)throws Exception{
        double n;if(value instanceof JSONObject&&((JSONObject)value).length()==1&&((JSONObject)value).has("$real"))n=Double.longBitsToDouble(integer(((JSONObject)value).get("$real"),Long.MIN_VALUE,Long.MAX_VALUE));
        else if(value instanceof Integer||value instanceof Long)n=((Number)value).doubleValue();else throw new VmHardware.Failure("invalid_argument","Camera real values use db_real bits or an integer.");
        if(!Double.isFinite(n))throw new VmHardware.Failure("invalid_argument","Camera values must be finite.");return n;
    }
    static float floating(Object v)throws Exception{float f=(float)number(v);if(!Float.isFinite(f))throw new VmHardware.Failure("invalid_argument","Camera float value exceeds finite binary32.");return f;}
    static Rational rational(Object value)throws Exception{JSONArray a=list(value,2,2);int n=(int)integer(a.get(0),Integer.MIN_VALUE,Integer.MAX_VALUE),d=(int)integer(a.get(1),Integer.MIN_VALUE,Integer.MAX_VALUE);if(d==0)throw new VmHardware.Failure("invalid_argument","Camera rational denominator cannot be zero.");return new Rational(n,d);}
    static float[] floats(Object value,int max)throws Exception{JSONArray a=list(value,0,max);float[] out=new float[a.length()];for(int i=0;i<out.length;i++)out[i]=floating(a.get(i));return out;}
    static final class Setting {final Class<?> type;final Object value;Setting(Class<?> type,Object value){this.type=type;this.value=value;}}
    static Setting decode(String type,Object value)throws Exception{
        switch(type){
        case "int":return new Setting(Integer.class,(int)integer(value,Integer.MIN_VALUE,Integer.MAX_VALUE));
        case "long":return new Setting(Long.class,integer(value,Long.MIN_VALUE,Long.MAX_VALUE));
        case "float":return new Setting(Float.class,floating(value));
        case "double":return new Setting(Double.class,number(value));
        case "byte":return new Setting(Byte.class,(byte)integer(value,-128,127));
        case "text":return new Setting(String.class,VmHardware.text(new JSONArray().put(value),0,1024));
        case "bool":return new Setting(Boolean.class,integer(value,0,1)==1);
        case "byte_array":return new Setting(byte[].class,VmHardware.data(value));
        case "int_array":{JSONArray a=list(value,0,1024);int[] out=new int[a.length()];for(int i=0;i<out.length;i++)out[i]=(int)integer(a.get(i),Integer.MIN_VALUE,Integer.MAX_VALUE);return new Setting(int[].class,out);}
        case "long_array":{JSONArray a=list(value,0,1024);long[] out=new long[a.length()];for(int i=0;i<out.length;i++)out[i]=integer(a.get(i),Long.MIN_VALUE,Long.MAX_VALUE);return new Setting(long[].class,out);}
        case "float_array":return new Setting(float[].class,floats(value,1024));
        case "double_array":{JSONArray a=list(value,0,1024);double[] out=new double[a.length()];for(int i=0;i<out.length;i++)out[i]=number(a.get(i));return new Setting(double[].class,out);}
        case "rational":return new Setting(Rational.class,rational(value));
        case "rational_array":{JSONArray a=list(value,0,1024);Rational[] out=new Rational[a.length()];for(int i=0;i<out.length;i++)out[i]=rational(a.get(i));return new Setting(Rational[].class,out);}
        case "rect":{JSONArray a=list(value,4,4);return new Setting(Rect.class,new Rect((int)integer(a.get(0),Integer.MIN_VALUE,Integer.MAX_VALUE),(int)integer(a.get(1),Integer.MIN_VALUE,Integer.MAX_VALUE),(int)integer(a.get(2),Integer.MIN_VALUE,Integer.MAX_VALUE),(int)integer(a.get(3),Integer.MIN_VALUE,Integer.MAX_VALUE)));}
        case "size":{JSONArray a=list(value,2,2);return new Setting(Size.class,new Size((int)integer(a.get(0),0,Integer.MAX_VALUE),(int)integer(a.get(1),0,Integer.MAX_VALUE)));}
        case "int_range":{JSONArray a=list(value,2,2);return new Setting(Range.class,new Range<Integer>((int)integer(a.get(0),Integer.MIN_VALUE,Integer.MAX_VALUE),(int)integer(a.get(1),Integer.MIN_VALUE,Integer.MAX_VALUE)));}
        case "metering":{JSONArray a=list(value,0,16);MeteringRectangle[] out=new MeteringRectangle[a.length()];for(int i=0;i<out.length;i++){JSONArray r=list(a.get(i),5,5);out[i]=new MeteringRectangle((int)integer(r.get(0),0,Integer.MAX_VALUE),(int)integer(r.get(1),0,Integer.MAX_VALUE),(int)integer(r.get(2),0,Integer.MAX_VALUE),(int)integer(r.get(3),0,Integer.MAX_VALUE),(int)integer(r.get(4),0,1000));}return new Setting(MeteringRectangle[].class,out);}
        case "location":{JSONArray a=list(value,5,5);double lat=number(a.get(0)),lon=number(a.get(1));if(lat < -90||lat>90||lon < -180||lon>180)throw new VmHardware.Failure("invalid_argument","Geotag coordinates exceed latitude/longitude ranges.");Location l=new Location(VmHardware.text(a,4,64));l.setLatitude(lat);l.setLongitude(lon);if(a.get(2)!=JSONObject.NULL)l.setAltitude(number(a.get(2)));l.setTime(integer(a.get(3),0,Long.MAX_VALUE));return new Setting(Location.class,l);}
        case "rggb":{JSONArray a=list(value,4,4);return new Setting(RggbChannelVector.class,new RggbChannelVector(floating(a.get(0)),floating(a.get(1)),floating(a.get(2)),floating(a.get(3))));}
        case "color_transform":{JSONArray a=list(value,9,9);Rational[] out=new Rational[9];for(int i=0;i<9;i++)out[i]=rational(a.get(i));return new Setting(ColorSpaceTransform.class,new ColorSpaceTransform(out));}
        case "tonemap":{JSONArray a=list(value,3,3);return new Setting(TonemapCurve.class,new TonemapCurve(floats(a.get(0),512),floats(a.get(1),512),floats(a.get(2),512)));}
        default:throw new VmHardware.Failure("unsupported_value_type","Camera setting type is not implemented: "+type);
        }
    }
    static Object encode(Object v,int depth)throws Exception{
        if(v==null)return JSONObject.NULL;if(depth>8)throw new VmHardware.Failure("size_limit","Nested camera metadata exceeds eight levels.");
        if(v instanceof Boolean||v instanceof Byte||v instanceof Short||v instanceof Integer||v instanceof Long)return v;
        if(v instanceof Float||v instanceof Double){double n=((Number)v).doubleValue();if(!Double.isFinite(n))return VmHardware.object("non_finite",Double.isNaN(n)?"nan":n>0?"positive_infinity":"negative_infinity");return VmHardware.real(n);}
        if(v instanceof String){String s=(String)v;if(s.length()>1024||s.indexOf('\0')>=0)throw new VmHardware.Failure("size_limit","Camera text metadata exceeds its bounded field size.");return s;}
        if(v instanceof Pair){Pair<?,?> p=(Pair<?,?>)v;return new JSONArray().put(encode(p.first,depth+1)).put(encode(p.second,depth+1));}
        Object profile=CameraProfileValues.encode(v,depth);if(profile!=null)return profile;
        if(v instanceof Rect){Rect r=(Rect)v;return new JSONArray().put(r.left).put(r.top).put(r.right).put(r.bottom);}
        if(v instanceof Size){Size s=(Size)v;return new JSONArray().put(s.getWidth()).put(s.getHeight());}
        if(v instanceof SizeF){SizeF s=(SizeF)v;return new JSONArray().put(VmHardware.real(s.getWidth())).put(VmHardware.real(s.getHeight()));}
        if(v instanceof Point){Point p=(Point)v;return new JSONArray().put(p.x).put(p.y);}
        if(v instanceof PointF){PointF p=(PointF)v;return new JSONArray().put(VmHardware.real(p.x)).put(VmHardware.real(p.y));}
        if(v instanceof Rational){Rational r=(Rational)v;return new JSONArray().put(r.getNumerator()).put(r.getDenominator());}
        if(v instanceof Range){Range<?> r=(Range<?>)v;return new JSONArray().put(encode(r.getLower(),depth+1)).put(encode(r.getUpper(),depth+1));}
        if(v instanceof RggbChannelVector){RggbChannelVector c=(RggbChannelVector)v;JSONArray a=new JSONArray();for(int i=0;i<4;i++)a.put(VmHardware.real(c.getComponent(i)));return a;}
        if(v instanceof ColorSpaceTransform){ColorSpaceTransform c=(ColorSpaceTransform)v;JSONArray a=new JSONArray();for(int row=0;row<3;row++)for(int col=0;col<3;col++)a.put(encode(c.getElement(col,row),depth+1));return a;}
        if(v instanceof BlackLevelPattern){BlackLevelPattern p=(BlackLevelPattern)v;return new JSONArray().put(p.getOffsetForIndex(0,0)).put(p.getOffsetForIndex(1,0)).put(p.getOffsetForIndex(0,1)).put(p.getOffsetForIndex(1,1));}
        if(v instanceof MeteringRectangle){MeteringRectangle r=(MeteringRectangle)v;return VmHardware.object("rect",encode(r.getRect(),depth+1),"weight",r.getMeteringWeight());}
        if(v instanceof Face){Face f=(Face)v;return VmHardware.object("id",f.getId(),"bounds",encode(f.getBounds(),depth+1),"score",f.getScore(),"left_eye",encode(f.getLeftEyePosition(),depth+1),"right_eye",encode(f.getRightEyePosition(),depth+1),"mouth",encode(f.getMouthPosition(),depth+1));}
        if(v instanceof TonemapCurve){TonemapCurve c=(TonemapCurve)v;JSONArray a=new JSONArray();for(int i=0;i<3;i++){int n=c.getPointCount(i);if(n>256)throw new VmHardware.Failure("size_limit","Tonemap curve exceeds256 points.");float[] p=new float[n*2];c.copyColorCurve(i,p,0);a.put(array(p,0,p.length,depth+1));}return a;}
        if(v instanceof StreamConfigurationMap)return VmHardware.object("sdk_type","stream_configuration_map","use","camera_formats/camera_output_sizes");
        if(v instanceof LensShadingMap){LensShadingMap m=(LensShadingMap)v;return VmHardware.object("sdk_type","lens_shading_map","columns",m.getColumnCount(),"rows",m.getRowCount(),"gain_count",m.getGainFactorCount(),"use","paged camera_value");}
        if(v instanceof Location){Location l=(Location)v;return VmHardware.object("provider",encode(l.getProvider(),depth+1),"latitude",VmHardware.real(l.getLatitude()),"longitude",VmHardware.real(l.getLongitude()),"altitude",l.hasAltitude()?VmHardware.real(l.getAltitude()):JSONObject.NULL,"time_ms",l.getTime());}
        if(Build.VERSION.SDK_INT>=28&&v instanceof OisSample){OisSample s=(OisSample)v;return VmHardware.object("timestamp_ns",s.getTimestamp(),"x_shift",VmHardware.real(s.getXshift()),"y_shift",VmHardware.real(s.getYshift()));}
        if(length(v)>=0){int n=length(v);if(n>1024)throw new VmHardware.Failure("size_limit","Nested metadata arrays exceed1024 values; use a paged top-level key.");return array(v,0,n,depth+1);}
        return VmHardware.object("unsupported_sdk_type",v.getClass().getName());
    }
    static int length(Object a){if(a instanceof int[])return ((int[])a).length;if(a instanceof long[])return ((long[])a).length;if(a instanceof float[])return ((float[])a).length;if(a instanceof double[])return ((double[])a).length;if(a instanceof byte[])return ((byte[])a).length;if(a instanceof boolean[])return ((boolean[])a).length;if(a instanceof Object[])return ((Object[])a).length;if(a instanceof LensShadingMap)return ((LensShadingMap)a).getGainFactorCount();return -1;}
    static Object at(Object a,int i){if(a instanceof int[])return ((int[])a)[i];if(a instanceof long[])return ((long[])a)[i];if(a instanceof float[])return ((float[])a)[i];if(a instanceof double[])return ((double[])a)[i];if(a instanceof byte[])return ((byte[])a)[i];if(a instanceof boolean[])return ((boolean[])a)[i];if(a instanceof Object[])return ((Object[])a)[i];LensShadingMap m=(LensShadingMap)a;int p=i/4;return m.getGainFactor(i%4,p%m.getColumnCount(),p/m.getColumnCount());}
    static JSONArray array(Object a,int start,int end,int depth)throws Exception{JSONArray out=new JSONArray();for(int i=start;i<end;i++)out.put(encode(at(a,i),depth));return out;}
    static JSONObject page(Object value,int offset,int limit)throws Exception{if(offset<0||offset>1000000||limit<1||limit>32)throw new VmHardware.Failure("invalid_argument","Camera metadata pages use offset0..1000000 and limit1..32.");JSONObject profiles=CameraProfileValues.page(value,offset,limit);if(profiles!=null)return profiles;int count=length(value);if(count<0){if(offset!=0)throw new VmHardware.Failure("invalid_argument","Scalar camera metadata uses offset0.");return VmHardware.object("value",encode(value,0),"array",false,"total",value==null?0:1,"next",-1);}int end=Math.min(count,offset+limit);return VmHardware.object("value",array(value,offset,end,0),"array",true,"total",count,"next",end<count?end:-1);}
}
