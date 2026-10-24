package org.flexscript.collie;

import android.app.*;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.net.Uri;
import android.os.*;
import java.util.concurrent.FutureTask;
import java.util.concurrent.TimeUnit;

/** The OS foreground lifetime for one explicitly approved projection. */
public final class CollieProjectionService extends Service {
    static final String START="org.flexscript.collie.PROJECTION_START", STOP="org.flexscript.collie.PROJECTION_STOP";
    static final int NOTIFICATION=7404;
    private HardwareScreenCapture.Session session;
    private int latestStart;
    private boolean finishing;
    @Override public IBinder onBind(Intent intent){return null;}
    @Override public int onStartCommand(Intent intent,int flags,int startId){
        latestStart=startId;
        String token=intent==null?null:intent.getStringExtra("token");
        if(intent!=null&&STOP.equals(intent.getAction())){
            if(session!=null&&session.nonce.equals(token))try{session.shutdown(false);}catch(Exception ignored){}
            if(session==null)stopSelf(startId);
            return START_NOT_STICKY;
        }
        HardwareScreenCapture.Session requested=intent==null||!START.equals(intent.getAction())?null:HardwareScreenCapture.serviceRequest(token);
        if(requested==null){if(session==null)stopSelf(startId);return START_NOT_STICKY;}
        if(session!=null){if(session==requested&&!finishing)return START_NOT_STICKY;requested.serviceFailed(new VmHardware.Failure("busy","Another projection service is finishing."));return START_NOT_STICKY;}
        session=requested;requested.attachService(this,startId);
        try{foreground(false);requested.fromService(this,startId);}
        catch(Exception error){requested.serviceFailed(error);finish(requested);}
        return START_NOT_STICKY;
    }
    private void foreground(boolean microphone){
        NotificationManager manager=getSystemService(NotificationManager.class);
        manager.createNotificationChannel(new NotificationChannel("collie-projection","Collie screen capture",NotificationManager.IMPORTANCE_LOW));
        Intent stopIntent=new Intent(this,CollieProjectionService.class).setAction(STOP).setData(Uri.parse("collie-projection:"+session.nonce)).putExtra("token",session.nonce);
        PendingIntent stop=PendingIntent.getService(this,7405,stopIntent,PendingIntent.FLAG_IMMUTABLE|PendingIntent.FLAG_UPDATE_CURRENT);
        PendingIntent open=PendingIntent.getActivity(this,7406,new Intent(this,MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),PendingIntent.FLAG_IMMUTABLE|PendingIntent.FLAG_UPDATE_CURRENT);
        Notification notification=new Notification.Builder(this,"collie-projection").setSmallIcon(android.R.drawable.stat_sys_upload).setContentTitle("Collie screen capture").setContentText(microphone?"Sharing your selected screen or app with microphone":"Sharing your selected screen or app").setContentIntent(open).setOngoing(true).addAction(new Notification.Action.Builder(null,"Stop",stop).build()).build();
        if(Build.VERSION.SDK_INT>=29){int type=ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION;if(microphone&&Build.VERSION.SDK_INT>=30)type|=ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE;startForeground(NOTIFICATION,notification,type);}else startForeground(NOTIFICATION,notification);
    }
    void microphone(HardwareScreenCapture.Session expected,boolean enabled)throws Exception{
        FutureTask<Void> task=new FutureTask<>(()->{if(session!=expected||finishing)throw new VmHardware.Failure("disconnected","The projection foreground service has ended.");foreground(enabled);return null;});
        if(Looper.myLooper()==Looper.getMainLooper())task.run();else HardwareScreenCapture.MAIN.post(task);
        try{task.get(3,TimeUnit.SECONDS);}catch(Exception error){task.cancel(false);throw error;}
    }
    void finish(HardwareScreenCapture.Session expected){HardwareScreenCapture.MAIN.post(()->{if(session==expected&&!finishing){finishing=true;stopForeground(STOP_FOREGROUND_REMOVE);stopSelf(latestStart);}});}
    @Override public void onDestroy(){HardwareScreenCapture.Session current=session;session=null;stopForeground(STOP_FOREGROUND_REMOVE);if(current!=null)current.serviceGone(this);super.onDestroy();}
}
