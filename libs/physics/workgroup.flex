// One workgroup owns an arena for the duration of this call. All 64 lanes
// must call together, including fault paths. Applications may run device-side
// control before/after each step without duplicating the numerical pipeline.
import "solver.flex";
fn ph_step_group(w,t,lane) {
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
    i=lane;
    while i<load64(w+16) {
        let j=i+1;
        while j<load64(w+16) {
            ph_collide_pair(w,ph_shape(w,i),ph_shape(w,j),t);
            j=j+1;
        }
        i=i+64;
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
    i=lane;
    while i<load64(w+24) {
        ph_contact_prepare_at(w,ph_contact(w,i),t);
        i=i+64;
    }
    if !lane {
        ph_order(w);
        store64(w+224,ph_color(w));
    }
    gpu_barrier();
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
            i=lane;
            while i<load64(w+232) {
                let group=ph_contact(w,i);
                if load64(group+216)==warm_color {
                    ph_group_warm_at(w,group,t);
                }
                i=i+64;
            }
            gpu_barrier();
            warm_color=warm_color+1;
        }
    }
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
                i=lane;
                while i<load64(w+232) {
                    let group=ph_contact(w,i);
                    if load64(group+216)==color {
                        ph_group_solve_at(w,group,t);
                    }
                    i=i+64;
                }
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
    return !load64(w+192);
}
