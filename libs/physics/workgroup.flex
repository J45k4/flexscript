// One workgroup owns an arena for the duration of this call. All 64 lanes
// must call together, including fault paths. Applications may run device-side
// control before/after each step without duplicating the numerical pipeline.
import "solver-register.flex";
// Optional diagnostic buffer: seven cumulative wall-clock stage durations,
// completed steps, summed contacts/manifolds/colors and maximum contact count.
// The caller owns/zeros 128 bytes per world; no profiling readback is required.
fn ph_profile_stamp(profile,stage,begin,lane) {
    if profile && !lane {let now=gpu_clock();store64(profile+stage*8,load64(profile+stage*8)+now-begin);return now;}
    return begin;
}
// Compact eligible pairs before narrow phase, filling waves with useful
// work. Sixteen checks/lane bounds each chunk to 1,024 packed pairs. GPU
// narrow phase uses lane-private scratch, leaving arena scratch 0..8207 free.
fn ph_collide_group(w,t,lane) {
    let count=load64(w+16);let rows=(count+63)>>6;let maximum=rows*(count-1)-rows*(rows-1)*32;let rounds=(maximum+15)>>4;
    let queue=ph_scratch(w);let counter=queue+8192;let a=lane;let b=a+1;let round=0;let total=0;
    while round<rounds {
        if !lane {store64(counter,0);}gpu_barrier();let check=0;
        while check<16 {
            if b>=count {a=a+64;b=a+1;}
            if a<count && b<count {
                let first=ph_shape(w,a);let second=ph_shape(w,b);let eligible=load64(first)!=load64(second) && (load64(ph_body(w,load64(first))+112) || load64(ph_body(w,load64(second))+112));
                let k=0;while k<3 {if ph_lt(load64(first+216+k*8),load64(second+192+k*8)) || ph_lt(load64(second+216+k*8),load64(first+192+k*8)) {eligible=0;}k=k+1;}
                if eligible {let slot=gpu_device_add64(counter,1);store64(queue+slot*8,(a<<32)|b);}b=b+1;
            }
            check=check+1;
        }
        gpu_barrier();let candidates=load64(counter);if !lane {total=total+candidates;}let i=lane;
        while i<candidates {let pair=load64(queue+i*8);ph_collide_pair(w,ph_shape(w,pair>>32),ph_shape(w,pair&4294967295),t);i=i+64;}
        gpu_barrier();if load64(w+192) {return 0;}round=round+1;
    }
    if !lane {store64(queue+8200,total);}return 1;
}
fn ph_step_group(w,t,lane) {return ph_step_group_profile(w,t,lane,0);}
// These begin/end stages also support a grid-wide narrow phase. Separate
// dispatches are the global synchronization boundary; no inter-block spin wait.
fn ph_step_group_profile(w,t,lane,profile) {
    if !ph_step_begin_group(w,t,lane,profile) {return 0;}
    ph_collide_group(w,t,lane);
    return ph_step_end_group(w,t,lane,profile);
}
fn ph_step_begin_group(w,t,lane,profile) {
    let begin=0;if profile && !lane {begin=gpu_clock();}
    if !lane {
        store64(w+216,1);
    }
    gpu_barrier();
    if load64(w+192) {
        return 0;
    }
    let i=lane;
    while i<load64(w+24) {
        ph_warm_save_at(w,i);
        i=i+64;
    }
    gpu_barrier();
    if !lane {
        store64(w+240,load64(w+24));
    }
    gpu_barrier();
    begin=ph_profile_stamp(profile,0,begin,lane);
    i=lane;
    while i<load64(w+8) {
        let b=ph_body(w,i);
        ph_cache_body(b);
        ph_forces_at(w,b,t);
        i=i+64;
    }
    gpu_barrier();
    i=lane;
    while i<load64(w+16) {
        ph_cache_shape_at(w,ph_shape(w,i),t);
        i=i+64;
    }
    if !lane {
        store64(w+24,0);
    }
    gpu_barrier();
    begin=ph_profile_stamp(profile,1,begin,lane);
    if profile && !lane {store64(profile+104,begin);}
    return 1;
}
fn ph_step_end_group(w,t,lane,profile) {
    let begin=0;if profile && !lane {begin=load64(profile+104);}
    gpu_barrier();
    if load64(w+192) {
        if !lane {
            if load64(w+24)>load64(w+56) {
                store64(w+24,load64(w+56));
            }
        }
        gpu_barrier();
        return 0;
    }
    begin=ph_profile_stamp(profile,2,begin,lane);
    let i=lane;
    while i<load64(w+24) {
        ph_contact_prepare_at(w,ph_contact(w,i),t);
        i=i+64;
    }
    ph_order_group(w,lane);
    if !lane {store64(w+224,ph_color(w));}
    gpu_barrier();
    begin=ph_profile_stamp(profile,3,begin,lane);
    let warm_colors=load64(w+224);
    if warm_colors<0 {
        if !lane {
            i=0;
            while i<load64(w+24) {
                ph_contact_warm_at(w,ph_order_contact(w,i),t);
                i=i+1;
            }
        }
        gpu_barrier();
    }
    else {
        let warm_color=0;
        while warm_color<warm_colors {
            i=ph_color_begin(w,warm_color)+lane;
            while i<ph_color_end(w,warm_color) {ph_group_warm_at(w,ph_color_group(w,i),t);i=i+64;}
            gpu_barrier();
            warm_color=warm_color+1;
        }
    }
    begin=ph_profile_stamp(profile,4,begin,lane);
    let iteration=0;
    while iteration<load64(w+168) {
        let colors=load64(w+224);
        if colors<0 {
            if !lane {
                i=0;
                while i<load64(w+24) {
                    ph_contact_solve_at(w,ph_order_contact(w,i),t);
                    i=i+1;
                }
            }
            gpu_barrier();
        }
        else {
            let color=0;
            while color<colors {
                i=ph_color_begin(w,color)+lane;
                while i<ph_color_end(w,color) {ph_group_solve_at(w,ph_color_group(w,i),t);i=i+64;}
                gpu_barrier();
                color=color+1;
            }
        }
        if !lane {
            i=0;
            while i<load64(w+32) {
                ph_weld_solve_at(w,ph_joint(w,i),t);
                i=i+1;
            }
        }
        gpu_barrier();
        iteration=iteration+1;
    }
    begin=ph_profile_stamp(profile,5,begin,lane);
    i=lane;
    while i<load64(w+8) {
        ph_integrate_at(w,ph_body(w,i),t);
        i=i+64;
    }
    gpu_barrier();
    if !lane && !load64(w+192) {
        store64(w+176,load64(w+176)+1);
        store64(w+184,ph_add(load64(w+184),load64(w+120)));
    }
    gpu_barrier();
    ph_profile_stamp(profile,6,begin,lane);
    if profile && !lane {
        store64(profile+56,load64(profile+56)+1);store64(profile+64,load64(profile+64)+load64(w+24));
        store64(profile+72,load64(profile+72)+load64(w+232));store64(profile+112,load64(profile+112)+load64(ph_scratch(w)+8200));let colors=load64(w+224);if colors>=0 {store64(profile+80,load64(profile+80)+colors);}else {store64(profile+96,load64(profile+96)+1);}
        if load64(w+24)>load64(profile+88) {store64(profile+88,load64(w+24));}
    }
    return !load64(w+192);
}

// Optional 64 KiB working set. All width lanes must enter together;
// the original ph_step_end_group and batch adapter remain available.

fn ph_step_end_group_local(w,t,lane,profile,local) {
    return ph_step_end_group_spread(w,t,lane,profile,local,64);
}

fn ph_step_end_group_spread(w,t,lane,profile,local,width) {
    let begin=0;
    if profile && !lane {
        begin=load64(profile+104);
    }
    gpu_barrier();
    if load64(w+192) {
        if !lane {
            if load64(w+24)>load64(w+56) {
                store64(w+24,load64(w+56));
            }
        }
        gpu_barrier();
        return 0;
    }
    begin=ph_profile_stamp(profile,2,begin,lane);
    let i=lane;
    while i<load64(w+24) {
        ph_contact_prepare_at(w,ph_contact(w,i),t);
        i=i+width;
    }
    let order_padded=1;
    while order_padded<load64(w+24) {
        order_padded=order_padded*2;
    }
    if local && order_padded*8<=65536 {
        ph_order_shared_width(w,lane,width);
    }
    else {
        ph_order_group_width(w,lane,width);
    }
    let color_padded=1;
    while color_padded<load64(w+24) {
        color_padded=color_padded*2;
    }
    if local && color_padded*8+load64(w+24)*8+load64(w+8)*16+1024<=65536 {
        ph_color_shared(w,lane,width,color_padded);
    }
    else if !lane {
        store64(w+224,ph_color(w));
    }
    gpu_barrier();
    begin=ph_profile_stamp(profile,3,begin,lane);
    let warm_colors=load64(w+224);
    if warm_colors<0 {
        if !lane {
            i=0;
            while i<load64(w+24) {
                ph_contact_warm_at(w,ph_order_contact(w,i),t);
                i=i+1;
            }
        }
        gpu_barrier();
    }
    else {
        let warm_color=0;
        while warm_color<warm_colors {
            i=ph_color_begin(w,warm_color)+lane;
            while i<ph_color_end(w,warm_color) {
                ph_group_warm_at(w,ph_color_group(w,i),t);
                i=i+width;
            }
            gpu_barrier();
            warm_color=warm_color+1;
        }
    }
    begin=ph_profile_stamp(profile,4,begin,lane);
    let padded=1;
    while padded<load64(w+24) {
        padded=padded*2;
    }
    let contact_base=padded*8;
    let group_base=contact_base+load64(w+24)*104;
    let cached_contacts=local && load64(w+224)>=0 && group_base+load64(w+232)*8<=65536;
    if cached_contacts {
        ph_contact_cache_begin(w,lane,contact_base,group_base,width);
    }
    let cached_welds=load64(w+32)<=124;
    if cached_welds && !lane {
        i=0;
        while i<load64(w+32) {
            ph_weld_prepare_at(w,ph_joint(w,i),t+512+i*128,t);
            i=i+1;
        }
    }
    gpu_barrier();
    let iteration=0;
    while iteration<load64(w+168) {
        let colors=load64(w+224);
        if colors<0 {
            if !lane {
                i=0;
                while i<load64(w+24) {
                    ph_contact_solve_register_at(w,ph_order_contact(w,i),t);
                    i=i+1;
                }
            }
            gpu_barrier();
        }
        else {
            let color=0;
            while color<colors {
                let active=32;
                if width==128 {
                    active=16;
                }
                else if width==256 {
                    active=8;
                }
                else if width==512 {
                    active=4;
                }
                else if width==1024 {
                    active=2;
                }
                if (lane&31)<active {
                    i=ph_color_begin(w,color)+(lane>>5)*active+(lane&31);
                    while i<ph_color_end(w,color) {
                        if cached_contacts {
                            ph_group_solve_local(w,i,t,contact_base,group_base);
                        }
                        else {
                            ph_group_solve_register(w,ph_color_group(w,i),t);
                        }
                        i=i+64;
                    }
                }
                gpu_barrier();
                color=color+1;
            }
        }
        if !lane {
            i=0;
            while i<load64(w+32) {
                if cached_welds {
                    ph_weld_solve_prepared(w,ph_joint(w,i),t+512+i*128,t);
                }
                else {
                    ph_weld_solve_at(w,ph_joint(w,i),t);
                }
                i=i+1;
            }
        }
        gpu_barrier();
        iteration=iteration+1;
    }
    if cached_contacts {
        ph_contact_cache_end(w,lane,contact_base,width);
    }
    begin=ph_profile_stamp(profile,5,begin,lane);
    i=lane;
    while i<load64(w+8) {
        ph_integrate_at(w,ph_body(w,i),t);
        i=i+width;
    }
    gpu_barrier();
    if !lane && !load64(w+192) {
        store64(w+176,load64(w+176)+1);
        store64(w+184,ph_add(load64(w+184),load64(w+120)));
    }
    gpu_barrier();
    ph_profile_stamp(profile,6,begin,lane);
    if profile && !lane {
        store64(profile+56,load64(profile+56)+1);
        store64(profile+64,load64(profile+64)+load64(w+24));
        store64(profile+72,load64(profile+72)+load64(w+232));
        store64(profile+112,load64(profile+112)+load64(ph_scratch(w)+8200));
        let colors=load64(w+224);
        if colors>=0 {
            store64(profile+80,load64(profile+80)+colors);
        }
        else {
            store64(profile+96,load64(profile+96)+1);
        }
        if load64(w+24)>load64(profile+88) {
            store64(profile+88,load64(w+24));
        }
    }
    return !load64(w+192);
}
