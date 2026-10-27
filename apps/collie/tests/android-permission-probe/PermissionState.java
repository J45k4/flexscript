package org.flexscript.collie.test;

import java.lang.reflect.Method;

/** Shell-only emulator fixture. Changes one precision-choice flag for Collie,
 * never a grant, another permission, another package or a global setting.
 * Not compiled into Collie. The driver independently checks every grant/flag.
 * AOSP contract: frameworks/base/core/java/android/permission/IPermissionManager.aidl
 */
public final class PermissionState {
    public static void main(String[] args) throws Exception {
        if (args.length != 1 || !(args[0].equals("0") || args[0].equals("1")))
            throw new IllegalArgumentException("Expected selected-location-accuracy 0 or 1");
        Class<?> process = Class.forName("android.os.Process");
        int uid = (Integer) process.getMethod("myUid").invoke(null);
        String emulator = (String) Class.forName("android.os.SystemProperties")
                .getMethod("get", String.class).invoke(null, "ro.kernel.qemu");
        if (uid != 2000 || !emulator.equals("1"))
            throw new SecurityException("Owned emulator shell only");
        Class<?> binderType = Class.forName("android.os.IBinder");
        Object binder = Class.forName("android.os.ServiceManager")
                .getMethod("getService", String.class).invoke(null, "permissionmgr");
        Object manager = Class.forName("android.permission.IPermissionManager$Stub")
                .getMethod("asInterface", binderType).invoke(null, binder);
        Class<?> api = Class.forName("android.permission.IPermissionManager");
        Method get = api.getMethod("getPermissionFlags", String.class, String.class,
                String.class, int.class);
        Method update = api.getMethod("updatePermissionFlags", String.class, String.class,
                int.class, int.class, boolean.class, String.class, int.class);
        String device = (String) Class.forName("android.companion.virtual.VirtualDeviceManager")
                .getField("PERSISTENT_DEVICE_ID_DEFAULT").get(null);
        int mask = (Integer) Class.forName("android.content.pm.PackageManager")
                .getField("FLAG_PERMISSION_SELECTED_LOCATION_ACCURACY").get(null);
        if (mask != 524288) throw new IllegalStateException("Unexpected SDK flag definition");
        String pkg = "org.flexscript.collie", permission = "android.permission.ACCESS_FINE_LOCATION";
        int before = (Integer) get.invoke(manager, pkg, permission, device, 0);
        int wanted = args[0].equals("1") ? mask : 0;
        update.invoke(manager, pkg, permission, mask, wanted, true, device, 0);
        int after = (Integer) get.invoke(manager, pkg, permission, device, 0);
        if ((after & mask) != wanted || (after & ~mask) != (before & ~mask))
            throw new IllegalStateException("Permission flag readback differs");
        System.out.println("{\"before\":" + before + ",\"after\":" + after
                + ",\"selected\":" + (wanted != 0) + "}");
    }
}
