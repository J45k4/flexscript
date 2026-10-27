package org.flexscript.collie;

import android.os.*;
import java.util.concurrent.*;
import org.json.*;

/** Real VM repeat requests, independent public graphs and actual service probes. */
public final class HardwareHapticRepeatChecks {
    final HardwareHapticChecks h;
    static final String TIMES="db_add(db_add(db_add(db_list(),db_int(80)),db_int(120)),db_int(120))",AMPS="db_add(db_add(db_add(db_list(),db_int(30)),db_int(0)),db_int(180))",LOOP="haptic_loop("+TIMES+","+AMPS+",1)";
    HardwareHapticRepeatChecks(HardwareHapticChecks h){this.h=h;}
    static void run(HardwareHapticChecks h,Vibrator sdk)throws Exception{new HardwareHapticRepeatChecks(h).run(sdk);}
    static VibrationEffect loop(){return VibrationEffect.createWaveform(new long[]{80,120,120},new int[]{30,0,180},1);}
    void reject(String expression,String error)throws Exception{h.vm("fn main(){if "+expression+"{return 1;}if !worker_equal(db_word(db_at(device_error(),0)),"+HardwareHapticChecks.q(error)+"){return 2;}return 0;}");}
    void run(Vibrator sdk)throws Exception{
        h.vm("fn main(){if haptic_submit(haptic_once(10,128),100){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"permission_denied\"){return 2;}return 0;}",false);
        h.check(!HardwareHaptics.busy(),"generic effect submission retains the Haptics denial before SDK playback or lease acquisition");
        for(String record:new String[]{"haptic_loop("+TIMES+","+AMPS+",-1)","haptic_loop("+TIMES+","+AMPS+",3)","haptic_loop(db_add(db_add(db_list(),db_int(20)),db_int(0)),db_add(db_add(db_list(),db_int(128)),db_int(0)),1)","haptic_loop("+TIMES+",db_list(),0)","db_add(haptic_repeating(haptic_once(10,128)),db_int(0))","haptic_repeating(haptic_repeating(haptic_once(10,128)))","haptic_repeating_after(haptic_once(10,128),"+LOOP+")","haptic_repeating_after("+LOOP+",haptic_once(10,128))"})reject("haptic_submit("+record+",1800)","invalid_argument");
        reject("haptic_submit(haptic_once(10,128),0)","invalid_argument");reject("haptic_submit(haptic_once(10,128),2001)","invalid_argument");
        h.check(!HardwareHaptics.busy(),"out-of-range loop indices, zero-duration suffixes, mismatched arrays, malformed/nested repeats and invalid common limits reject before playback");h.probe("idle","",0);
        verify("haptic_once(1500,128)",VibrationEffect.createOneShot(1500,128),false);
        verify(LOOP,loop(),true);
        if(Build.VERSION.SDK_INT>=36){verify("haptic_repeating(haptic_once(120,128))",Api36.repeat(),true);verify("haptic_repeating_after(haptic_once(80,32),haptic_pattern("+TIMES+","+AMPS+"))",Api36.after(),true);if(sdk.areAllPrimitivesSupported(1))verify("haptic_repeating(haptic_composition(db_add(db_list(),haptic_primitive(1,db_int(1),250))))",Api36.primitive(),true);}
        else{reject("haptic_submit(haptic_repeating(haptic_once(120,128)),1800)","unsupported_operation");reject("haptic_submit(haptic_repeating_after(haptic_once(80,32),haptic_once(120,128)),1800)","unsupported_operation");h.check(!HardwareHaptics.busy(),"older SDK rejects both arbitrary-repeat constructors without rendering a finite or waveform substitute");h.probe("idle","",0);}
        deadline();ownership();
    }
    void verify(String record,VibrationEffect expected,boolean repeat)throws Exception{
        String name=h.open(h.root,"haptic_submit("+record+",1800)");HardwareHaptics.Haptic owned=h.handle(h.context,name);
        try{h.check(owned.effect.equals(expected)&&owned.submitted&&owned.duration==1800,"direct "+record.split("\\(",2)[0]+" reaches an independent identical SDK effect under its explicit common wall limit");h.vm("fn main(){let r=device_field(device_info("+HardwareHapticChecks.q(name)+"),\"requested\");if !worker_equal(db_word(device_field(r,\"type\")),\"effect\")||db_word(device_field(r,\"common_duration_limit_ms\"))!=1800{return 1;}let requested=device_field(r,\"effect\");let supplied="+record+";let a=db_encode(requested);let bytes=alloc(a);db_copy(bytes,db_wire,a);let b=db_encode(supplied);if a!=b{return 2;}let i=0;while i<a{if load8(bytes+i)!=load8(db_wire+i){return 3;}i=i+1;}return 0;}");h.probe("targeted",expected.toString(),0);if(repeat){Thread.sleep(450);h.probe("targeted",expected.toString(),0);h.check(!owned.released,"actual repeat remains running beyond its finite source pattern before explicit close");}}
        finally{h.close(h.context,name,owned);}h.probe("idle","",0);
    }
    void deadline()throws Exception{
        CountDownLatch entered=new CountDownLatch(1),release=new CountDownLatch(1),exited=new CountDownLatch(1);HardwareSensors.events().post(()->{entered.countDown();try{release.await(20,TimeUnit.SECONDS);}catch(InterruptedException e){Thread.currentThread().interrupt();}finally{exited.countDown();}});if(!entered.await(5,TimeUnit.SECONDS))throw new java.io.IOException("Repeat deadline blocker did not enter");String name=null;HardwareHaptics.Haptic owned=null;
        try{name=h.open(h.root,"haptic_submit("+LOOP+",1400)");owned=h.handle(h.context,name);Thread.sleep(450);h.probe("targeted",loop().toString(),0);h.released(owned);h.check(owned.cancelReturned&&owned.stopReason.equals("wall_deadline")&&exited.getCount()==1,"an actual infinite SDK waveform is cancelled by its independent1400ms wall deadline without further VM access while the shared Handler remains blocked");h.probe("idle","",0);}
        finally{release.countDown();if(name!=null&&owned!=null)h.close(h.context,name,owned);}
    }
    void ownership()throws Exception{
        String name=h.open(h.root,"haptic_submit("+LOOP+",1800)");HardwareHaptics.Haptic owned=h.handle(h.context,name);
        try{h.probe("targeted",loop().toString(),0);h.vm(h.other,"fn main(){if haptic_submit(haptic_once(100,128),100){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"busy\"){return 2;}if device_close("+HardwareHapticChecks.q(name)+"){return 3;}if !worker_equal(db_word(db_at(device_error(),0)),\"stale_handle\"){return 4;}return 0;}",true);h.main(()->VmHardware.revoke(h.root,"haptics"));h.released(owned);h.check(owned.closed&&owned.cancelReturned,"repeating playback excludes a foreign workspace, rejects foreign close and is cancelled by actual grant revocation");h.probe("idle","",0);}
        finally{if(!owned.closed)h.close(h.context,name,owned);}
        String next=h.open(h.other,"haptic_submit("+LOOP+",1800)");HardwareHaptics.Haptic newer=h.handle(h.foreign,next);try{h.main(owned::close);h.probe("targeted",loop().toString(),0);h.check(!newer.released,"stale repeat cleanup cannot cancel a newer workspace repeat using the same actual SDK actuator");}finally{h.close(h.foreign,next,newer);}h.probe("idle","",0);
    }
    static final class Api36 {
        static VibrationEffect repeat(){return VibrationEffect.createRepeatingEffect(VibrationEffect.createOneShot(120,128));}
        static VibrationEffect after(){return VibrationEffect.createRepeatingEffect(VibrationEffect.createOneShot(80,32),VibrationEffect.createWaveform(new long[]{80,120,120},new int[]{30,0,180},-1));}
        static VibrationEffect primitive(){return VibrationEffect.createRepeatingEffect(VibrationEffect.startComposition().addPrimitive(1,1,250).compose());}
    }
}
