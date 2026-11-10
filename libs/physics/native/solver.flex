import "collision.flex";
import "../color.flex";
// Native x86-64 host experiment. Each color has disjoint dynamic bodies;
// one worker handles odd groups while the parent handles even groups.
// Barriers preserve the existing order between colors and iterations.
global par_pid2=0; global par_ctl=0; global par_world=0; global par_pid=0; global par_timeout=0; global par_status=0; global par_dispatch_count=0;
global phase_library=0; global phase_kernel=0;global phase_integrate_kernel=0;global phase_setup_kernel=0;
global pc_prepare=0;global pc_step=0;global pc_finish=0;global pc_abort=0;global pc_reset=0;global pc_stats=0;
global parameter_begin=0;global parameter_step=0;global parameter_finish=0;global parameter_abort=0;global parameter_reset=0;global parameter_stats=0;global par_parameter_dispatch_count=0;
global par_collision_enabled=1;global par_collision_dispatch_count=0;
global nk_iterations_step=0;global nk_iterations_resume=0;global nk_weld_sync=0;global nk_pipeline_ready=0;global nk_iteration_step=0;global nk_finish=0;global nk_schedule_init=0;global nk_schedule_prepare=0;global nk_range=0; global nk_library=0; global nk_contact=0; global nk_group=0;

global par_pid3=0;global par_pid4=0;global par_pid5=0;
fn par_extra_check(){
 if par_pid3>0 && syscall(61,par_pid3,par_status,1,0,0,0)==par_pid3 {par_pid3=0;return 0;}
 if par_pid4>0 && syscall(61,par_pid4,par_status,1,0,0,0)==par_pid4 {par_pid4=0;return 0;}
 if par_pid5>0 && syscall(61,par_pid5,par_status,1,0,0,0)==par_pid5 {par_pid5=0;return 0;}
 return 1;
}
fn par_extra_wake(){return syscall(202,par_ctl+96,1,3,0,0,0);}
fn par_extra_publish(epoch){store64(par_ctl+96,epoch);par_extra_wake();return 1;}
fn par_extra_wait(epoch){
 return par_wait(par_ctl+128,epoch) && par_wait(par_ctl+192,epoch) && par_wait(par_ctl+256,epoch);
}
fn par_extra_worker(parent,lane){
 let completed=par_ctl+128+(lane-3)*64;let ready=completed+8;let request=par_ctl+96;
 let empty=alloc(8);store64(empty,0);syscall(14,2,empty,0,8,0,0);
 syscall(157,1,15,0,0,0,0);if syscall(110,0,0,0,0,0,0)!=parent {syscall(60,4,0,0,0,0,0);}
 let fd=3;while fd<1024 {syscall(3,fd,0,0,0,0,0);fd=fd+1;}
 store64(ready,1);par_wake(ready);let seen=0;
 while 1 {
  let spin=0;while load64(request)==seen && spin<10000 {spin=spin+1;}
  if load64(request)==seen {par_wait_sys(request,seen);}
  let epoch=load64(request);
  if epoch!=seen {
   seen=epoch;if load64(par_ctl+40) {syscall(60,0,0,0,0,0,0);}
   let mode=load64(par_ctl+80);if mode<1 || mode>4 {store64(par_ctl+88,1);syscall(60,7,0,0,0,0,0);}
   let function=nk_iteration_step;if mode==2 {function=pc_step;}if mode==3 {function=nk_iterations_step;}if mode==4 {function=parameter_step;}
   let result=2;while result>=2 {
    if load64(par_ctl+40) {syscall(60,0,0,0,0,0,0);}
    result=ffi_call(function,par_world,lane,epoch,0,0,0);
   }
   if !result {store64(par_ctl+88,1);}
   store64(completed,seen);par_wake(completed);
  }
 }
 return 0;
}

fn par_wait_sys(address,expected) {return syscall(202,address,0,expected,par_timeout,0,0);}
fn par_wake(address) {return syscall(202,address,1,2,0,0,0);}
fn par_worker(parent,lane) {
    let completed=par_ctl+8;let ready=par_ctl+48;if lane==2 {completed=par_ctl+64;ready=par_ctl+72;}
    let empty=alloc(8);store64(empty,0);syscall(14,2,empty,0,8,0,0);
    syscall(157,1,15,0,0,0,0);if syscall(110,0,0,0,0,0,0)!=parent {syscall(60,4,0,0,0,0,0);}
    let fd=3;while fd<1024 {syscall(3,fd,0,0,0,0,0);fd=fd+1;}
    let t=alloc(4096);if !t {syscall(60,5,0,0,0,0,0);}
    store64(ready,1);par_wake(ready);let seen=0;
    while 1 {
        let spin=0;while load64(par_ctl)==seen && spin<10000 {spin=spin+1;}
        if load64(par_ctl)==seen {par_wait_sys(par_ctl,seen);}
        let epoch=load64(par_ctl);
        if epoch!=seen {
            seen=epoch;if load64(par_ctl+40) {syscall(60,0,0,0,0,0,0);}
            let i=load64(par_ctl+24)+lane;let end=load64(par_ctl+32);
            let mode=load64(par_ctl+80);
            if mode {
                let function=nk_iteration_step;if mode==2 {function=pc_step;}if mode==3 {function=nk_iterations_step;}if mode==4 {function=parameter_step;}
                let result=2;while result>=2 {if load64(par_ctl+40) {syscall(60,0,0,0,0,0,0);}result=ffi_call(function,par_world,lane,epoch,0,0,0);}
                if !result {store64(par_ctl+88,1);}
            }else{ph_range_solve(par_world,i,end,t,3);}
            store64(completed,seen);par_wake(completed);
        }
    }return 0;
}
fn par_wait(address,want) {
    let attempts=0;
    while load64(address)!=want {
        if !ph_native_poll() { return 0; }
        let spin=0;while load64(address)!=want && spin<10000 {spin=spin+1;}
        if load64(address)!=want {
            if par_pid>0 && syscall(61,par_pid,par_status,1,0,0,0)==par_pid {par_pid=0;return 0;}
            if par_pid2>0 && syscall(61,par_pid2,par_status,1,0,0,0)==par_pid2 {par_pid2=0;return 0;}
            if !par_extra_check() {return 0;}
            let current=load64(address);if current!=want {par_wait_sys(address,current);attempts=attempts+1;}
            if attempts>400 {return 0;}
        }
    }return 1;
}
fn par_reap(pid) {
    if pid<=0 {return 0;}
    let tries=0;let done=0;
    while tries<200 && !done {if syscall(61,pid,par_status,1,0,0,0)==pid {done=1;}else {syscall(7,0,0,5,0,0,0);tries=tries+1;}}
    if !done {syscall(62,pid,9,0,0,0,0);syscall(61,pid,par_status,0,0,0,0);}
    return 0;
}
fn par_stop() {
    if par_ctl {store64(par_ctl+40,1);store64(par_ctl,load64(par_ctl)+1);par_wake(par_ctl);store64(par_ctl+96,load64(par_ctl+96)+1);par_extra_wake();}
    par_reap(par_pid);par_reap(par_pid2);par_reap(par_pid3);par_reap(par_pid4);par_reap(par_pid5);par_pid=0;par_pid2=0;par_pid3=0;par_pid4=0;par_pid5=0;par_world=0;
    if par_ctl {syscall(11,par_ctl,4096,0,0,0,0);par_ctl=0;}if pc_reset {ffi_call(pc_reset,0,0,0,0,0,0);}if parameter_reset {ffi_call(parameter_reset,0,0,0,0,0,0);}return 0;
}
fn par_start(w) {
    if !nk_init() || !phase_init() {return 0;}
    if par_ctl || par_pid || par_pid2 || par_pid3 || par_pid4 || par_pid5 || !w {return 0;}
    ffi_call(pc_reset,0,0,0,0,0,0);ffi_call(parameter_reset,0,0,0,0,0,0);par_collision_dispatch_count=0;par_parameter_dispatch_count=0;
    let configure=ffi_symbol(phase_library,"native_parallel_lanes");if !configure || !ffi_call(configure,6,0,0,0,0,0) {return 0;}
    par_ctl=syscall(9,0,4096,3,33,-1,0);if par_ctl<0 {par_ctl=0;return 0;}
    par_timeout=alloc(16);par_status=alloc(8);if !par_timeout || !par_status {par_stop();return 0;}
    store64(par_timeout,0);store64(par_timeout+8,5000000);par_world=w;par_dispatch_count=0;
    let parent=syscall(39,0,0,0,0,0,0);par_pid=syscall(57,0,0,0,0,0,0);
    if !par_pid {par_worker(parent,1);syscall(60,6,0,0,0,0,0);}
    if par_pid<0 {par_pid=0;par_stop();return 0;}
    if !par_wait(par_ctl+48,1) {par_stop();return 0;}
    par_pid2=syscall(57,0,0,0,0,0,0);
    if !par_pid2 {par_worker(parent,2);syscall(60,6,0,0,0,0,0);}
    if par_pid2<0 {par_pid2=0;par_stop();return 0;}
    if !par_wait(par_ctl+72,1) {par_stop();return 0;}
    par_pid3=syscall(57,0,0,0,0,0,0);
    if !par_pid3 {par_extra_worker(parent,3);syscall(60,6,0,0,0,0,0);}
    if par_pid3<0 {par_pid3=0;par_stop();return 0;}
    if !par_wait(par_ctl+136,1) {par_stop();return 0;}
    par_pid4=syscall(57,0,0,0,0,0,0);
    if !par_pid4 {par_extra_worker(parent,4);syscall(60,6,0,0,0,0,0);}
    if par_pid4<0 {par_pid4=0;par_stop();return 0;}
    if !par_wait(par_ctl+200,1) {par_stop();return 0;}
    par_pid5=syscall(57,0,0,0,0,0,0);
    if !par_pid5 {par_extra_worker(parent,5);syscall(60,6,0,0,0,0,0);}
    if par_pid5<0 {par_pid5=0;par_stop();return 0;}
    if !par_wait(par_ctl+264,1) {par_stop();return 0;}return 1;
}
fn par_groups(w,begin,end) {
    store64(par_ctl+80,0);
    store64(par_ctl+24,begin);store64(par_ctl+32,end);let epoch=load64(par_ctl)+1;store64(par_ctl,epoch);par_wake(par_ctl);
    ph_range_solve(w,begin,end,ph_scratch(w)+2048,3);
    if !par_wait(par_ctl+8,epoch) || !par_wait(par_ctl+64,epoch) {return 0;}par_dispatch_count=par_dispatch_count+1;return 1;
}
fn par_iteration(w) {
    if par_pid3<=0 || par_pid4<=0 || par_pid5<=0 || !par_extra_check() {return 0;}
    store64(par_ctl+80,1);store64(par_ctl+88,0);
    let epoch=load64(par_ctl)+1;store64(par_ctl,epoch);par_wake(par_ctl);par_extra_publish(epoch);
    let started=ph_native_now();let result=3;
    while result>=2 {
        if !ph_native_poll() || load64(par_ctl+88) {return 0;}
        result=ffi_call(nk_iteration_step,w,0,epoch,0,0,0);
        if !result {return 0;}
        if result==2 {
            if ph_native_now()-started>2000 {return 0;}
            if par_pid>0 && syscall(61,par_pid,par_status,1,0,0,0)==par_pid {par_pid=0;return 0;}
            if par_pid2>0 && syscall(61,par_pid2,par_status,1,0,0,0)==par_pid2 {par_pid2=0;return 0;}
            if !par_extra_check() {return 0;}
        }
    }
    if !par_wait(par_ctl+8,epoch) || !par_wait(par_ctl+64,epoch) || !par_extra_wait(epoch) {return 0;}
    par_dispatch_count=par_dispatch_count+1;return !load64(par_ctl+88);
}
fn par_iterations(w) {
    if par_pid3<=0 || par_pid4<=0 || par_pid5<=0 || !par_extra_check() {return 0;}
    store64(par_ctl+80,3);store64(par_ctl+88,0);
    let epoch=load64(par_ctl)+1;store64(par_ctl,epoch);par_wake(par_ctl);par_extra_publish(epoch);
    let started=ph_native_now();let result=3;
    while result>=2 {
        if !ph_native_poll() || load64(par_ctl+88) {return 0;}
        result=ffi_call(nk_iterations_step,w,0,epoch,0,0,0);
        if !result {return 0;}
        if result==4 {
            if !ffi_call(nk_weld_sync,w,0,0,0,0,0) {return 0;}
            let joint=0;while joint<load64(w+32) {ph_weld_solve(w,ph_joint(w,joint));joint=joint+1;}
            if !ffi_call(nk_weld_sync,w,1,0,0,0,0) || !ffi_call(nk_iterations_resume,w,epoch,0,0,0,0) {return 0;}
        }
        if result==2 || result==4 {
            if ph_native_now()-started>2000 {return 0;}
            if par_pid>0 && syscall(61,par_pid,par_status,1,0,0,0)==par_pid {par_pid=0;return 0;}
            if par_pid2>0 && syscall(61,par_pid2,par_status,1,0,0,0)==par_pid2 {par_pid2=0;return 0;}
            if !par_extra_check() {return 0;}
        }
    }
    if !par_wait(par_ctl+8,epoch) || !par_wait(par_ctl+64,epoch) || !par_extra_wait(epoch) {return 0;}
    par_dispatch_count=par_dispatch_count+1;return !load64(par_ctl+88);
}
// Keep inner-loop vector intermediates in registers on all compiler targets.
fn ph_point_component_mode(b,r,axis,offset) {
    let u=ph_next_axis(axis);
    let v=ph_prev_axis(axis);
    return ph_add(load64(b+64+offset+axis*8),ph_sub(ph_mul(load64(b+88+offset+u*8),load64(r+v*8)),ph_mul(load64(b+88+offset+v*8),load64(r+u*8))));
}
fn ph_point_component(b,r,axis) {return ph_point_component_mode(b,r,axis,0);}
fn ph_point_velocity(out,b,r,t) {
    return ph_vset(out,ph_point_component(b,r,0),ph_point_component(b,r,1),ph_point_component(b,r,2));
}
fn ph_mass(b,r,axis,t) {
    if !load64(b+112) {
        return 0;
    }
    let x=ph_sub(ph_mul(load64(r+8),load64(axis+16)),ph_mul(load64(r+16),load64(axis+8)));
    let y=ph_sub(ph_mul(load64(r+16),load64(axis)),ph_mul(load64(r),load64(axis+16)));
    let z=ph_sub(ph_mul(load64(r),load64(axis+8)),ph_mul(load64(r+8),load64(axis)));
    let ix=ph_dot(load64(b+328),load64(b+352),load64(b+376),x,y,z);
    let iy=ph_dot(load64(b+336),load64(b+360),load64(b+384),x,y,z);
    let iz=ph_dot(load64(b+344),load64(b+368),load64(b+392),x,y,z);
    return ph_add(load64(b+112),ph_dot(x,y,z,ix,iy,iz));
}
fn ph_mass_cross(b,r,u,v) {
    if !load64(b+112) {return 0;}
    let ax=ph_sub(ph_mul(load64(r+8),load64(u+16)),ph_mul(load64(r+16),load64(u+8)));
    let ay=ph_sub(ph_mul(load64(r+16),load64(u)),ph_mul(load64(r),load64(u+16)));
    let az=ph_sub(ph_mul(load64(r),load64(u+8)),ph_mul(load64(r+8),load64(u)));
    let bx=ph_sub(ph_mul(load64(r+8),load64(v+16)),ph_mul(load64(r+16),load64(v+8)));
    let by=ph_sub(ph_mul(load64(r+16),load64(v)),ph_mul(load64(r),load64(v+16)));
    let bz=ph_sub(ph_mul(load64(r),load64(v+8)),ph_mul(load64(r+8),load64(v)));
    let ix=ph_dot(load64(b+328),load64(b+352),load64(b+376),bx,by,bz);
    let iy=ph_dot(load64(b+336),load64(b+360),load64(b+384),bx,by,bz);
    let iz=ph_dot(load64(b+344),load64(b+368),load64(b+392),bx,by,bz);
    return ph_add(ph_mul(load64(b+112),ph_vdot(u,v)),ph_dot(ax,ay,az,ix,iy,iz));
}
fn ph_impulse_mode(b,r,impulse,sign,t,offset) {
    if !load64(b+112) {
        return 0;
    }
    let jx=load64(impulse);
    let jy=load64(impulse+8);
    let jz=load64(impulse+16);
    let x=ph_sub(ph_mul(load64(r+8),jz),ph_mul(load64(r+16),jy));
    let y=ph_sub(ph_mul(load64(r+16),jx),ph_mul(load64(r),jz));
    let z=ph_sub(ph_mul(load64(r),jy),ph_mul(load64(r+8),jx));
    let ix=ph_dot(load64(b+328),load64(b+352),load64(b+376),x,y,z);
    let iy=ph_dot(load64(b+336),load64(b+360),load64(b+384),x,y,z);
    let iz=ph_dot(load64(b+344),load64(b+368),load64(b+392),x,y,z);
    ph_mad(b+64+offset,b+64+offset,impulse,ph_mul(sign,load64(b+112)));
    store64(b+88+offset,ph_add(load64(b+88+offset),ph_mul(ix,sign)));
    store64(b+96+offset,ph_add(load64(b+96+offset),ph_mul(iy,sign)));
    store64(b+104+offset,ph_add(load64(b+104+offset),ph_mul(iz,sign)));
    return 0;
}
fn ph_impulse(b,r,impulse,sign,t) {return ph_impulse_mode(b,r,impulse,sign,t,0);}
fn ph_relative_mode(out,a,b,ra,rb,t,offset) {
    let x=ph_sub(ph_add(load64(b+64+offset),ph_sub(ph_mul(load64(b+96+offset),load64(rb+16)),ph_mul(load64(b+104+offset),load64(rb+8)))),ph_add(load64(a+64+offset),ph_sub(ph_mul(load64(a+96+offset),load64(ra+16)),ph_mul(load64(a+104+offset),load64(ra+8)))));
    let y=ph_sub(ph_add(load64(b+72+offset),ph_sub(ph_mul(load64(b+104+offset),load64(rb+0)),ph_mul(load64(b+88+offset),load64(rb+16)))),ph_add(load64(a+72+offset),ph_sub(ph_mul(load64(a+104+offset),load64(ra+0)),ph_mul(load64(a+88+offset),load64(ra+16)))));
    let z=ph_sub(ph_add(load64(b+80+offset),ph_sub(ph_mul(load64(b+88+offset),load64(rb+8)),ph_mul(load64(b+96+offset),load64(rb+0)))),ph_add(load64(a+80+offset),ph_sub(ph_mul(load64(a+88+offset),load64(ra+8)),ph_mul(load64(a+96+offset),load64(ra+0)))));
    return ph_vset(out,x,y,z);
}
fn ph_relative(out,a,b,ra,rb,t) {return ph_relative_mode(out,a,b,ra,rb,t,0);}
fn ph_contact_prepare_at(w,c,t) {
    let a=ph_body(w,load64(c));
    let b=ph_body(w,load64(c+8));
    ph_vsub(c+104,c+16,a+8);
    ph_vsub(c+128,c+16,b+8);
    let mass=ph_add(ph_mass(a,c+104,c+40,t),ph_mass(b,c+128,c+40,t));
    store64(c+152,ph_rcp(mass));
    ph_relative(t+96,a,b,c+104,c+128,t);
    let vn=ph_vdot(t+96,c+40);
    let bounce=0;
    if ph_lt(vn,0xbf000000) {
        bounce=ph_mul(ph_neg(vn),load64(w+160));
    }
    let depth=ph_max(0,ph_sub(load64(c+64),load64(w+200)));
    let bias=ph_mul(ph_div(depth,load64(w+120)),load64(w+208));
    // Stabilization has its own impulse/velocity channel; repairing an
    // overlap must not launch a body with new kinetic energy.
    store64(c+160,0);
    store64(c+168,ph_min(bias,1073741824));
    // A separated support corner permits approach through its gap over this
    // timestep. It receives no normal impulse unless that motion would cross
    // the plane; it must not be treated as an already touching constraint.
    if ph_lt(load64(c+64),0) {bounce=ph_div(load64(c+64),load64(w+120));}
    store64(c+176,bounce);
    // Cache a fixed orthonormal tangent frame and its 2x2 effective mass.
    // Pack the four matrix words into two reserved 64-bit cache fields.
    let axis=0;if ph_lt(ph_abs(load64(c+48)),ph_abs(load64(c+40))) {axis=1;}
    if ph_lt(ph_abs(load64(c+56)),ph_abs(load64(c+40+axis*8))) {axis=2;}
    ph_vset(t,0,0,0);store64(t+axis*8,1065353216);ph_cross(c+224,c+40,t);ph_normalize(c+224,c+224);ph_cross(t+24,c+40,c+224);
    let xx=ph_add(ph_mass(a,c+104,c+224,t),ph_mass(b,c+128,c+224,t));
    let yy=ph_add(ph_mass(a,c+104,t+24,t),ph_mass(b,c+128,t+24,t));
    let xy=ph_add(ph_mass_cross(a,c+104,c+224,t+24),ph_mass_cross(b,c+128,c+224,t+24));
    let floor=ph_add(load64(a+112),load64(b+112));
    let inverse=ph_rcp(ph_max(ph_mul(floor,floor),ph_sub(ph_mul(xx,yy),ph_mul(xy,xy))));
    store64(c+184,xx|(yy<<32));store64(c+248,xy|(inverse<<32));
    return 0;
}
fn reference_ph_contact_solve_at(w,c,t) {
    let a=ph_body(w,load64(c));
    let b=ph_body(w,load64(c+8));
    ph_relative(t+96,a,b,c+104,c+128,t);
    let vn=ph_vdot(t+96,c+40);
    let lambda=ph_mul(ph_sub(load64(c+176),vn),load64(c+152));
    let old=load64(c+72);
    let total=ph_max(0,ph_add(old,lambda));
    store64(c+72,total);
    ph_scale(t+120,c+40,ph_sub(total,old));
    ph_impulse(a,c+104,t+120,0xbf800000,t);
    ph_impulse(b,c+128,t+120,1065353216,t);
    ph_relative(t+96,a,b,c+104,c+128,t);
    vn=ph_vdot(t+96,c+40);
    ph_mad(t+144,t+96,c+40,ph_neg(vn));
    let speed2=ph_vdot(t+144,t+144);
    if ph_lt(0x2b8cbccc,speed2) {
        ph_cross(t+192,c+40,c+224);
        let vx=ph_vdot(t+144,c+224);let vy=ph_vdot(t+144,t+192);
        let xx=load64(c+184)&4294967295;let yy=(load64(c+184)>>32)&4294967295;
        let xy=load64(c+248)&4294967295;let inverse=(load64(c+248)>>32)&4294967295;
        let dx=ph_mul(ph_sub(ph_mul(xy,vy),ph_mul(yy,vx)),inverse);
        let dy=ph_mul(ph_sub(ph_mul(xy,vx),ph_mul(xx,vy)),inverse);
        ph_mad(t+168,c+80,c+224,dx);ph_mad(t+168,t+168,t+192,dy);
        let length2=ph_vdot(t+168,t+168);let limit=ph_mul(total,load64(w+152));
        if ph_lt(ph_mul(limit,limit),length2) {ph_scale(t+168,t+168,ph_mul(limit,ph_rsqrt(length2)));}
        ph_vsub(t+216,t+168,c+80);dx=ph_vdot(t+216,c+224);dy=ph_vdot(t+216,t+192);
        let curvature=ph_add(ph_add(ph_mul(xx,ph_mul(dx,dx)),ph_mul(yy,ph_mul(dy,dy))),ph_mul(ph_add(xy,xy),ph_mul(dx,dy)));
        let energy=ph_add(ph_add(ph_mul(vx,dx),ph_mul(vy,dy)),ph_mul(1056964608,curvature));
        if ph_lt(0,energy) {
            // Euclidean cone projection of a Newton step can add energy for
            // anisotropic inertia. A trace-bounded gradient step is safe
            // when the prior impulse lies in the current friction disk.
            ph_mad(t+168,c+80,t+144,ph_neg(ph_rcp(ph_add(xx,yy))));length2=ph_vdot(t+168,t+168);
            if ph_lt(ph_mul(limit,limit),length2) {ph_scale(t+168,t+168,ph_mul(limit,ph_rsqrt(length2)));}
        }
        ph_vsub(t+120,t+168,c+80);
        ph_vcopy(c+80,t+168);
        ph_impulse(a,c+104,t+120,0xbf800000,t);
        ph_impulse(b,c+128,t+120,1065353216,t);
    }
    ph_contact_position_at(w,c,t);
    return 0;
}
fn ph_contact_position_at(w,c,t) {
    let a=ph_body(w,load64(c));let b=ph_body(w,load64(c+8));
    ph_relative_mode(t+96,a,b,c+104,c+128,t,128);
    let velocity=ph_vdot(t+96,c+40);
    let lambda=ph_mul(ph_sub(load64(c+168),velocity),load64(c+152));
    let previous=load64(c+160);let total=ph_max(0,ph_add(previous,lambda));
    store64(c+160,total);
    ph_scale(t+120,c+40,ph_sub(total,previous));
    ph_impulse_mode(a,c+104,t+120,0xbf800000,t,128);
    ph_impulse_mode(b,c+128,t+120,1065353216,t,128);
    return 0;
}
fn ph_angular_impulse(b,impulse,sign,t) {
    if !load64(b+112) {
        return 0;
    }
    ph_rotate(t,b+328,impulse);
    ph_mad(b+88,b+88,t,sign);
    return 0;
}
fn ph_weld_solve_at(w,joint,t) {
    if !load64(joint+16) {
        return 0;
    }
    let a=ph_body(w,load64(joint));
    let b=ph_body(w,load64(joint+8));
    ph_rotate(t+192,a+256,joint+24);
    ph_vset(t+216,0,0,0);
    ph_vadd(t+240,a+8,t+192);
    ph_vsub(t+240,b+8,t+240);
    let gain=ph_div(load64(w+208),load64(w+120));
    let i=0;
    while i<3 {
        ph_vset(t+264,0,0,0);
        store64(t+264+i*8,1065353216);
        ph_relative(t+96,a,b,t+192,t+216,t);
        let target=ph_neg(ph_mul(load64(t+240+i*8),gain));
        let mass=ph_add(ph_mass(a,t+192,t+264,t),load64(b+112));
        let lambda=ph_div(ph_sub(target,load64(t+96+i*8)),mass);
        ph_scale(t+120,t+264,lambda);
        ph_impulse(a,t+192,t+120,0xbf800000,t);
        ph_impulse(b,t+216,t+120,1065353216,t);
        i=i+1;
    }
    ph_qmul(t+288,a+32,joint+48);
    i=0;
    while i<3 {
        store64(t+320+i*8,ph_neg(load64(t+288+i*8)));
        i=i+1;
    }
    store64(t+344,load64(t+312));
    ph_qmul(t+352,b+32,t+320);
    let sign=1073741824;
    if ph_lt(load64(t+376),0) {
        sign=0xc0000000;
    }
    i=0;
    while i<3 {
        let error=ph_mul(ph_mul(load64(t+352+i*8),sign),gain);
        let relative=ph_sub(load64(b+88+i*8),load64(a+88+i*8));
        let mass=ph_add(load64(a+328+(i*3+i)*8),load64(b+328+(i*3+i)*8));
        let lambda=ph_div(ph_neg(ph_add(error,relative)),mass);
        ph_vset(t+120,0,0,0);
        store64(t+120+i*8,lambda);
        ph_angular_impulse(a,t+120,0xbf800000,t);
        ph_angular_impulse(b,t+120,1065353216,t);
        i=i+1;
    }
    return 0;
}
fn ph_forces_at(w,b,t) {
    ph_vset(b+192,0,0,0);
    ph_vset(b+216,0,0,0);
    if load64(b)!=1 {
        return 0;
    }
    let dt=load64(w+120);
    let i=0;
    while i<3 {
        let acceleration=ph_add(load64(w+128+i*8),ph_mul(load64(b+144+i*8),load64(b+112)));
        store64(b+64+i*8,ph_add(load64(b+64+i*8),ph_mul(dt,acceleration)));
        i=i+1;
    }
    // Euler rigid-body equation in the principal-inertia frame, including gyro.
    ph_unrotate(t,b+256,b+88);
    i=0;
    while i<3 {
        store64(t+24+i*8,ph_div(load64(t+i*8),load64(b+120+i*8)));
        i=i+1;
    }
    ph_cross(t+48,t,t+24);
    ph_rotate(t+72,b+256,t+48);
    ph_vsub(t+96,b+168,t+72);
    ph_rotate(t+120,b+328,t+96);
    ph_mad(b+88,b+88,t+120,dt);
    return 0;
}
fn ph_integrate_at(w,b,t) {
    if !load64(b) {
        return 1;
    }
    let dt=load64(w+120);
    ph_vadd(t,b+64,b+192);
    ph_mad(b+8,b+8,t,dt);
    ph_vadd(t,b+88,b+216);
    store64(t+24,0);
    ph_qmul(t+32,t,b+32);
    let halfdt=ph_mul(dt,1056964608);
    let i=0;
    while i<4 {
        store64(b+32+i*8,ph_add(load64(b+32+i*8),ph_mul(load64(t+32+i*8),halfdt)));
        i=i+1;
    }
    if !ph_qnorm(b+32) {
        return ph_fault(w,2);
    }
    i=0;
    while i<13 {
        if !ph_finite(load64(b+8+i*8)) {
            return ph_fault(w,2);
        }
        i=i+1;
    }
    return 1;
}
// Cache the prior canonical manifold order before contact emission overwrites
// the contact arena. Cache storage is part of the relocatable world in VRAM.
fn ph_warm_save_at(w,index) {
    let from=ph_order_contact(w,index);
    let to=w+load64(w+248)+index*128;
    let k=0;
    while k<13 {
        store64(to+k*8,load64(from+k*8));
        k=k+1;
    }
    store64(to+104,0);
    return 0;
}
fn ph_warm_find(w,c) {
    let count=load64(w+240);
    let base=w+load64(w+248);
    let a=load64(c);
    let b=load64(c+8);
    let low=0;
    let high=count;
    while low<high {
        let middle=(low+high)>>1;
        let p=base+middle*128;
        if load64(p)<a || (load64(p)==a && load64(p+8)<b) {
            low=middle+1;
        }
        else {
            high=middle;
        }
    }
    let best=0;
    let nearest=0x358637bd;
    while low<count {
        let p=base+low*128;
        if load64(p)!=a || load64(p+8)!=b {
            return best;
        }
        let x=ph_sub(load64(c+16),load64(p+16));
        let y=ph_sub(load64(c+24),load64(p+24));
        let z=ph_sub(load64(c+32),load64(p+32));
        let distance=ph_dot(x,y,z,x,y,z);
        if !load64(p+104) && ph_lt(distance,nearest) && ph_lt(0x3f733333,ph_vdot(c+40,p+40)) {
            nearest=distance;
            best=p;
        }
        low=low+1;
    }
    return best;
}
fn ph_contact_warm_at(w,c,t) {
    let previous=ph_warm_find(w,c);
    if !previous {
        return 0;
    }
    store64(previous+104,1);
    // A modest decay tolerates changing manifolds; the iterative solve can
    // remove excess normal/tangent impulse using its accumulated bounds.
    let impulse=ph_mul(load64(previous+72),0x3f4ccccd);
    store64(c+72,impulse);
    ph_scale(c+80,previous+80,0x3f4ccccd);
    // The cached tangent is projected into this frame's contact plane.
    ph_mad(c+80,c+80,c+40,ph_neg(ph_vdot(c+80,c+40)));
    ph_mad(t+120,c+80,c+40,impulse);
    ph_impulse(ph_body(w,load64(c)),c+104,t+120,0xbf800000,t);
    ph_impulse(ph_body(w,load64(c+8)),c+128,t+120,1065353216,t);
    return 0;
}
fn ph_group_warm_at(w,group,t) {
    let k=load64(group+200);
    while k<load64(group+208) {
        ph_contact_warm_at(w,ph_order_contact(w,k),t);
        k=k+1;
    }
    return 0;
}
fn ph_step(w) {
    if !phase_init() {return ph_fault(w,2);}
    if !nk_init() {return ph_fault(w,2);}
    store64(w+216,0);
    if load64(w+192) {
        return 0;
    }
    if !ffi_call(phase_setup_kernel,w,0,0,0,0,0) {return ph_fault(w,2);}
    let i=0;
    if !par_collision(w) {
        return 0;
    }
    let prepared=par_parameters(w);if prepared==-2 {return ph_fault(w,2);}
    let colors=0;if prepared {colors=prepared-2;}else {colors=phase_run(w,1);}
    if par_pid>0 && w==par_world {ffi_call(nk_schedule_prepare,w,0,0,0,0,0);}
    let use_dag=0;if par_pid>0 && w==par_world {use_dag=ffi_call(nk_pipeline_ready,w,0,0,0,0,0);}
    let iteration=0;
    if use_dag && load64(w+168) && load64(w+168)<=4096 {if !par_iterations(w) {return ph_fault(w,2);}iteration=load64(w+168);}
    while iteration<load64(w+168) {
        if !ph_native_poll() { return 0; }
        if colors<0 {
            i=0;
            while i<load64(w+24) {
                ph_contact_solve(w,ph_order_contact(w,i));
                i=i+1;
            }
        }
        else if use_dag {if !par_iteration(w) {return ph_fault(w,2);}}
        else {
            let color=0;
            while color<colors {
                i=ph_color_begin(w,color);let end=ph_color_end(w,color);
                if par_pid>0 && w==par_world && end-i>=12 {
                    if !par_groups(w,i,end) {return ph_fault(w,2);}
                } else {
                    ph_range_solve(w,i,end,ph_scratch(w)+2048,1);
                }
                color=color+1;
            }
        }
        if load64(w+32) && !ffi_call(nk_weld_sync,w,0,0,0,0,0) {return ph_fault(w,2);}
        i=0;
        while i<load64(w+32) {
            ph_weld_solve(w,ph_joint(w,i));
            i=i+1;
        }
        if load64(w+32) && !ffi_call(nk_weld_sync,w,1,0,0,0,0) {return ph_fault(w,2);}
        iteration=iteration+1;
    }
    ffi_call(nk_finish,w,0,0,0,0,0);
    if !ffi_call(phase_integrate_kernel,w,0,0,0,0,0) {return 0;}
    store64(w+176,load64(w+176)+1);
    store64(w+184,ph_add(load64(w+184),load64(w+120)));
    return 1;
}
fn ph_advance(w,steps) {
    let i=0;
    while i<steps {
        if !ph_step(w) {
            return 0;
        }
        i=i+1;
    }
    return 1;
}
fn ph_contact_prepare(w,c) {
    return ph_contact_prepare_at(w,c,ph_scratch(w)+2048);
}
fn ph_contact_solve(w,c) {
    return ph_contact_solve_at(w,c,ph_scratch(w)+2048);
}
fn ph_weld_solve(w,joint) {
    return ph_weld_solve_at(w,joint,ph_scratch(w)+2048);
}
fn ph_forces(w,b) {
    return ph_forces_at(w,b,ph_scratch(w)+2048);
}
fn ph_integrate(w,b) {
    return ph_integrate_at(w,b,ph_scratch(w)+2048);
}
fn reference_ph_group_solve_at(w,group,t) {
    let k=load64(group+200);
    while k<load64(group+208) {
        ph_contact_solve_at(w,ph_order_contact(w,k),t);
        k=k+1;
    }
    return 0;
}

fn nk_init() {
    if nk_contact && nk_group && nk_range {return 1;}
    if !nk_library {nk_library=ffi_open("@BUILD@/contact.so");}
    if !nk_library {return 0;}
    nk_contact=ffi_symbol(nk_library,"native_contact");
    nk_group=ffi_symbol(nk_library,"native_group");
    nk_range=ffi_symbol(nk_library,"native_range");
    nk_weld_sync=ffi_symbol(nk_library,"native_weld_sync");if !nk_weld_sync {return 0;}
    nk_pipeline_ready=ffi_symbol(nk_library,"native_pipeline_ready");nk_iteration_step=ffi_symbol(nk_library,"native_iteration_step");nk_iterations_step=ffi_symbol(nk_library,"native_iterations_step");nk_iterations_resume=ffi_symbol(nk_library,"native_iterations_resume");if !nk_iterations_step || !nk_iterations_resume {return 0;}
    if !nk_pipeline_ready || !nk_iteration_step {return 0;}
    nk_finish=ffi_symbol(nk_library,"native_finish");if !nk_finish {return 0;}
    nk_schedule_init=ffi_symbol(nk_library,"native_schedule_init");nk_schedule_prepare=ffi_symbol(nk_library,"native_schedule_prepare");
    if !nk_schedule_init || !nk_schedule_prepare {return 0;}
    ffi_call(nk_schedule_init,0,0,0,0,0,0);return nk_contact && nk_group && nk_range;
}
fn ph_contact_solve_at(w,c,t) {
    if !nk_init() {return ph_fault(w,2);}
    return ffi_call(nk_contact,w,c,t,0,0,0);
}
fn ph_group_solve_at(w,g,t) {
    if !nk_init() {return ph_fault(w,2);}
    return ffi_call(nk_group,w,g,t,0,0,0);
}

fn phase_init() {
 if phase_kernel {return 1;}
 phase_library=ffi_open("@BUILD@/phases.so");if !phase_library {return 0;}
 let abi=ffi_symbol(phase_library,"flex_kernel_abi");let arity=ffi_symbol(phase_library,"flex_kernel_arity");
 if !abi || !arity {return 0;} if ffi_call(abi,0,0,0,0,0,0)!=1 || ffi_call(arity,0,0,0,0,0,0)!=2 {return 0;}
 let init=ffi_symbol(phase_library,"native_collision_init");
 pc_prepare=ffi_symbol(phase_library,"native_collision_prepare");pc_step=ffi_symbol(phase_library,"native_collision_step");
 pc_finish=ffi_symbol(phase_library,"native_collision_finish");pc_abort=ffi_symbol(phase_library,"native_collision_abort");
 pc_reset=ffi_symbol(phase_library,"native_collision_reset");pc_stats=ffi_symbol(phase_library,"native_collision_stats");
 if !init || !pc_prepare || !pc_step || !pc_finish || !pc_abort || !pc_reset || !pc_stats {return 0;}
 ffi_call(init,0,0,0,0,0,0);
 phase_setup_kernel=ffi_symbol(phase_library,"native_setup");if !phase_setup_kernel {return 0;}
 phase_integrate_kernel=ffi_symbol(phase_library,"native_integrate_all");if !phase_integrate_kernel {return 0;}
 let parameter_init=ffi_symbol(phase_library,"native_parameters_init");
 parameter_begin=ffi_symbol(phase_library,"native_parameters_begin");parameter_step=ffi_symbol(phase_library,"native_parameters_step");parameter_finish=ffi_symbol(phase_library,"native_parameters_finish");parameter_abort=ffi_symbol(phase_library,"native_parameters_abort");parameter_reset=ffi_symbol(phase_library,"native_parameters_reset");parameter_stats=ffi_symbol(phase_library,"native_parameters_stats");
 if !parameter_init || !parameter_begin || !parameter_step || !parameter_finish || !parameter_abort || !parameter_reset || !parameter_stats || !ffi_call(parameter_init,0,0,0,0,0,0) {return 0;}
 phase_kernel=ffi_symbol(phase_library,"flex_kernel");return phase_kernel!=0;
}
fn phase_run(w,mode) {return ffi_call(phase_kernel,w,mode,0,0,0,0);}

fn ph_range_solve(w,begin,end,t,stride){return ffi_call(nk_range,w,begin,end,t,stride,0);}

fn par_collision_peer_check(started) {
    let now=ph_native_now();
    if now<0 || !ph_native_poll() || load64(par_ctl+88) || now-started>2000 {return 0;}
    if par_pid>0 && syscall(61,par_pid,par_status,1,0,0,0)==par_pid {par_pid=0;return 0;}
    if par_pid2>0 && syscall(61,par_pid2,par_status,1,0,0,0)==par_pid2 {par_pid2=0;return 0;}
    if !par_extra_check() {return 0;}return par_pid>0 && par_pid2>0 && par_pid3>0 && par_pid4>0 && par_pid5>0;
}
fn par_collision_wait(address,epoch,started) {
    while load64(address)!=epoch {
        if !par_collision_peer_check(started) {return 0;}
        let current=load64(address);if current!=epoch {par_wait_sys(address,current);}
    }
    return 1;
}
fn par_collision(w) {
    if !par_collision_enabled || par_pid<=0 || w!=par_world {return phase_run(w,0);}
    if par_pid2<=0 || par_pid3<=0 || par_pid4<=0 || par_pid5<=0 {return ph_fault(w,2);}
    let epoch=load64(par_ctl)+1;
    if !ffi_call(pc_prepare,w,epoch,0,0,0,0) {return phase_run(w,0);}
    store64(par_ctl+80,2);store64(par_ctl+88,0);
    let started=ph_native_now();if started<0 {ffi_call(pc_abort,w,epoch,0,0,0,0);return ph_fault(w,2);}
    store64(par_ctl,epoch);par_wake(par_ctl);par_extra_publish(epoch);
    par_collision_dispatch_count=par_collision_dispatch_count+1;
    let result=3;
    while result>=2 {
        if !par_collision_peer_check(started) {
            ffi_call(pc_abort,w,epoch,0,0,0,0);return ph_fault(w,2);
        }
        result=ffi_call(pc_step,w,0,epoch,0,0,0);
        if !result {ffi_call(pc_abort,w,epoch,0,0,0,0);return ph_fault(w,2);}
    }
    if !par_collision_wait(par_ctl+8,epoch,started) || !par_collision_wait(par_ctl+64,epoch,started) || !par_collision_wait(par_ctl+128,epoch,started) || !par_collision_wait(par_ctl+192,epoch,started) || !par_collision_wait(par_ctl+256,epoch,started) || !par_collision_peer_check(started) {
        ffi_call(pc_abort,w,epoch,0,0,0,0);return ph_fault(w,2);
    }
    result=ffi_call(pc_finish,w,epoch,0,0,0,0);
    if !result && !load64(w+192) {return ph_fault(w,2);}
    return result;
}

fn par_parameters(w) {
    if par_pid<=0 || w!=par_world || load64(w+24)<128 {return 0;}
    if par_pid2<=0 || par_pid3<=0 || par_pid4<=0 || par_pid5<=0 {return -2;}
    let epoch=load64(par_ctl)+1;
    if !ffi_call(parameter_begin,w,epoch,0,0,0,0) {return 0;}
    store64(par_ctl+80,4);store64(par_ctl+88,0);
    let started=ph_native_now();if started<0 {ffi_call(parameter_abort,w,epoch,0,0,0,0);return -2;}
    store64(par_ctl,epoch);par_wake(par_ctl);par_extra_publish(epoch);par_parameter_dispatch_count=par_parameter_dispatch_count+1;
    let result=3;
    while result>=2 {
        if !par_collision_peer_check(started) {ffi_call(parameter_abort,w,epoch,0,0,0,0);return -2;}
        result=ffi_call(parameter_step,w,0,epoch,0,0,0);
        if !result {ffi_call(parameter_abort,w,epoch,0,0,0,0);return -2;}
    }
    if !par_collision_wait(par_ctl+8,epoch,started) || !par_collision_wait(par_ctl+64,epoch,started) || !par_collision_wait(par_ctl+128,epoch,started) || !par_collision_wait(par_ctl+192,epoch,started) || !par_collision_wait(par_ctl+256,epoch,started) || !par_collision_peer_check(started) {ffi_call(parameter_abort,w,epoch,0,0,0,0);return -2;}
    result=ffi_call(parameter_finish,w,epoch,0,0,0,0);if !result {ffi_call(parameter_abort,w,epoch,0,0,0,0);return -2;}return result;
}
