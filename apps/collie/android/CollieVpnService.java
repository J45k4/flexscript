package org.flexscript.collie;

import android.app.*;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.net.*;
import android.os.*;
import java.io.IOException;

/** Foreground lifecycle and Android TUN establishment, only for a live VM request. */
public final class CollieVpnService extends VpnService {
    static final String START="org.flexscript.collie.VPN_START",STOP="org.flexscript.collie.VPN_STOP";
    private static final int NOTIFICATION=7401;
    private volatile HardwareVpn.Tun session;
    @Override public int onStartCommand(Intent intent,int flags,int startId){
        if(intent!=null&&STOP.equals(intent.getAction())){closeSession();stopSelf(startId);return START_NOT_STICKY;}
        HardwareVpn.Request request=intent==null||!START.equals(intent.getAction())?null:HardwareVpn.request(intent.getStringExtra("token"));
        if(request==null){if(session==null)stopSelf(startId);return START_NOT_STICKY;}
        HardwareVpn.Tun tun=null;
        try{
            if(!request.context.host.hardwareVisible)throw new VmHardware.Failure("foreground_required","Collie must remain visible while creating the VPN.");request.check();HardwareVpn.Config config=request.config;Builder builder=new Builder().setSession(config.name).setMtu(config.mtu).setBlocking(false).setUnderlyingNetworks(new Network[]{config.network});
            for(HardwareVpn.Prefix prefix:config.addresses)builder.addAddress(prefix.address,prefix.length);for(HardwareVpn.Prefix prefix:config.routes)builder.addRoute(prefix.address,prefix.length);for(java.net.InetAddress server:config.dns)builder.addDnsServer(server);
            if(!config.all)for(String app:config.apps){if(config.exclude)builder.addDisallowedApplication(app);else builder.addAllowedApplication(app);}
            builder.setConfigureIntent(PendingIntent.getActivity(this,7402,new Intent(this,MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),PendingIntent.FLAG_IMMUTABLE|PendingIntent.FLAG_UPDATE_CURRENT));
            ParcelFileDescriptor descriptor=builder.establish();if(descriptor==null)throw new VmHardware.Failure("permission_revoked","Android VPN approval was revoked before establishment.");tun=new HardwareVpn.Tun(request,descriptor,this,startId);session=tun;HardwareVpn.publish(request,tun);notifyForeground(config.name);
            if(!request.result(tun,null)){tun.close();return START_NOT_STICKY;}
        }catch(Exception error){if(tun!=null)try{tun.close();}catch(Exception ignored){}request.result(null,error);if(session==null||session==tun)stopSelf(startId);}
        return START_NOT_STICKY;
    }
    private void notifyForeground(String name){
        NotificationManager manager=(NotificationManager)getSystemService(NOTIFICATION_SERVICE);NotificationChannel channel=new NotificationChannel("collie-vpn","Collie VPN routing",NotificationManager.IMPORTANCE_LOW);manager.createNotificationChannel(channel);
        PendingIntent stop=PendingIntent.getService(this,7403,new Intent(this,CollieVpnService.class).setAction(STOP),PendingIntent.FLAG_IMMUTABLE|PendingIntent.FLAG_UPDATE_CURRENT);
        PendingIntent open=PendingIntent.getActivity(this,7402,new Intent(this,MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),PendingIntent.FLAG_IMMUTABLE|PendingIntent.FLAG_UPDATE_CURRENT);
        Notification notification=new Notification.Builder(this,"collie-vpn").setSmallIcon(android.R.drawable.stat_sys_upload).setContentTitle("Collie VPN routing").setContentText(name).setContentIntent(open).setOngoing(true).addAction(new Notification.Action.Builder(null,"Disconnect",stop).build()).build();
        if(Build.VERSION.SDK_INT>=34)startForeground(NOTIFICATION,notification,ServiceInfo.FOREGROUND_SERVICE_TYPE_SYSTEM_EXEMPTED);else startForeground(NOTIFICATION,notification);
    }
    void stopSession(HardwareVpn.Tun tun){new Handler(Looper.getMainLooper()).post(()->{if(session==tun){session=null;stopForeground(STOP_FOREGROUND_REMOVE);stopSelf(tun.startId);}});}
    private void closeSession(){HardwareVpn.Tun tun=session;session=null;if(tun!=null)try{tun.close();}catch(IOException ignored){}stopForeground(STOP_FOREGROUND_REMOVE);}
    @Override public void onRevoke(){closeSession();stopSelf();super.onRevoke();}
    @Override public void onDestroy(){closeSession();super.onDestroy();}
}
