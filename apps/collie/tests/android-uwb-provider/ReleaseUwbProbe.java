package androidx.core.uwb.backend.fixture;

import android.app.*;
import android.content.*;
import android.content.pm.ApplicationInfo;
import android.os.Bundle;
import java.io.File;
import java.lang.reflect.*;
import org.json.JSONObject;

/** Same-certificate instrumentation verifies the installed non-debug production policy. */
public final class ReleaseUwbProbe extends Instrumentation {
    public void onCreate(Bundle args){super.onCreate(args);start();}
    public void onStart(){Bundle result=new Bundle();try{
        Context target=getTargetContext();if((target.getApplicationInfo().flags&ApplicationInfo.FLAG_DEBUGGABLE)!=0)throw new AssertionError("Expected non-debug Collie APK");
        Activity host=startActivitySync(new Intent().setClassName(target,"org.flexscript.collie.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        ClassLoader loader=target.getClassLoader();Class<?> context=Class.forName("org.flexscript.collie.VmHardware$Context",true,loader);Constructor<?> constructor=context.getDeclaredConstructor(host.getClass(),File.class);constructor.setAccessible(true);Object c=constructor.newInstance(host,new File(target.getFilesDir(),"uwb-release-probe"));Class<?> adapter=Class.forName("org.flexscript.collie.HardwareUwbAosp",true,loader);Method base=adapter.getDeclaredMethod("base",context);base.setAccessible(true);JSONObject actual=(JSONObject)base.invoke(null,c);
        if(!actual.getBoolean("provider_present")||actual.getBoolean("provider_usable")||actual.getJSONObject("provider").getBoolean("debug_signature_fixture"))throw new AssertionError(actual.toString());
        Method require=adapter.getDeclaredMethod("require",context);require.setAccessible(true);boolean rejected=false;try{require.invoke(null,c);}catch(InvocationTargetException e){Field code=e.getCause().getClass().getDeclaredField("code");code.setAccessible(true);rejected="untrusted_provider".equals(code.get(e.getCause()));}if(!rejected)throw new AssertionError("Release accepted a user-installed fixture or failed for an unrelated reason");
        try{Class.forName("org.flexscript.collie.HardwareUwbAospChecks",false,loader);throw new AssertionError("Debug checks packaged in release");}catch(ClassNotFoundException expected){}
        result.putString("result","PASS installed non-debug Collie rejects the same-signature user provider before binding or runtime consent; debug checks absent");result.putString("provider",actual.toString());finish(Activity.RESULT_OK,result);
    }catch(Throwable e){result.putString("error",e.toString());finish(Activity.RESULT_CANCELED,result);}}
}
