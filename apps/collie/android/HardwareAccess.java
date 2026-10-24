package org.flexscript.collie;

import android.content.pm.ApplicationInfo;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Process;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;
import org.json.JSONArray;

/** Read-only SDK facts. Neither permission metadata nor UID proves hardware access. */
final class HardwareAccess {
    private static final String[] PERMISSIONS={
        "MANAGE_USB", "NETWORK_SETTINGS", "NETWORK_STACK", "TETHER_PRIVILEGED",
        "MODIFY_PHONE_STATE", "READ_PRIVILEGED_PHONE_STATE", "BLUETOOTH_PRIVILEGED",
        "NFC_PRIVILEGED", "INJECT_EVENTS", "WRITE_SECURE_SETTINGS", "DEVICE_POWER",
        "REBOOT", "MOUNT_UNMOUNT_FILESYSTEMS", "DUMP", "HARDWARE_TEST",
        "MANAGE_SENSOR_PRIVACY", "MANAGE_WIFI_NETWORK_SELECTION"
    };
    @SuppressWarnings("deprecation")
    static Object info(VmHardware.Context context)throws Exception {
        VmHardware.check();
        PackageManager manager=context.host.getPackageManager();
        ApplicationInfo app=context.host.getApplicationInfo();
        PackageInfo pkg=manager.getPackageInfo(context.host.getPackageName(),PackageManager.GET_PERMISSIONS);
        Set<String> requested=new HashSet<>();
        if(pkg.requestedPermissions!=null)requested.addAll(Arrays.asList(pkg.requestedPermissions));
        JSONArray permissions=new JSONArray();
        for(String suffix:PERMISSIONS){
            String name="android.permission."+suffix;
            boolean granted=context.host.checkSelfPermission(name)==PackageManager.PERMISSION_GRANTED;
            Object protection=org.json.JSONObject.NULL;boolean defined=true;
            try{protection=manager.getPermissionInfo(name,0).protectionLevel;}
            catch(PackageManager.NameNotFoundException missing){defined=false;}
            permissions.put(VmHardware.object("name",name,"defined",defined,"requested",requested.contains(name),
                "granted",granted,"protection_level",protection));
        }
        VmHardware.check();
        return VmHardware.object("sdk",Build.VERSION.SDK_INT,"target_sdk",app.targetSdkVersion,"uid",Process.myUid(),
            "system_app",(app.flags&ApplicationInfo.FLAG_SYSTEM)!=0,
            "updated_system_app",(app.flags&ApplicationInfo.FLAG_UPDATED_SYSTEM_APP)!=0,
            "debuggable",(app.flags&ApplicationInfo.FLAG_DEBUGGABLE)!=0,"permissions",permissions);
    }
}
