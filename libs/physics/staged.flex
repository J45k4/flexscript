// Portable single-world collision stages. The host supplies a queue with
// 32 + shape_count*(shape_count-1)/2*8 bytes, and private 16KiB scratch per
// collision worker. Queue metadata: count, next job, caller active flag, spare.
// Call the builder with one 64-lane group after ph_step_begin_group. Dispatch
// ph_collide_queue_grid across any number of workers, then ph_step_end_group
// in one 64-lane group. Dispatch boundaries provide global visibility.
import "workgroup.flex";
fn ph_pair_queue_group(w,queue,lane,workers) {
    if !lane {store64(queue,0);store64(queue+8,workers);}gpu_barrier();
    let count=load64(w+16);let a=lane;
    while a<count {
        let first=ph_shape(w,a);let b=a+1;
        while b<count {
            let second=ph_shape(w,b);let eligible=load64(first)!=load64(second) && (load64(ph_body(w,load64(first))+112) || load64(ph_body(w,load64(second))+112));
            let k=0;while k<3 {if ph_lt(load64(first+216+k*8),load64(second+192+k*8)) || ph_lt(load64(second+216+k*8),load64(first+192+k*8)) {eligible=0;}k=k+1;}
            if eligible {let slot=gpu_device_add64(queue,1);store64(queue+32+slot*8,(a<<32)|b);}b=b+1;
        }
        a=a+64;
    }
    gpu_barrier();if !lane {store64(ph_scratch(w)+8200,load64(queue));}return 1;
}
fn ph_collide_queue_grid(w,t,queue,index) {
    let count=load64(queue);let i=index;
    while i<count {
        let pair=load64(queue+32+i*8);ph_collide_pair(w,ph_shape(w,pair>>32),ph_shape(w,pair&4294967295),t);
        i=gpu_device_add64(queue+8,1);
    }
    return 0;
}

fn ph_pair_queue_bucket(w,queue,t,lane,workers) {
    let count=load64(w+16);
    if count>480 {
        return ph_pair_queue_group(w,queue,lane,workers);
    }
    let c=0;
    while c<36 {
        gpu_shared_store64((c*64+lane)*8,0);
        c=c+1;
    }
    gpu_shared_barrier();
    let own=0;
    let a=lane;
    while a<count {
        let first=ph_shape(w,a);
        let b=a+1;
        let ma=load64(ph_body(w,load64(first))+112);
        while b<count {
            let second=ph_shape(w,b);
            let mb=load64(ph_body(w,load64(second))+112);
            let eligible=load64(first)!=load64(second) && (ma || mb);
            let k=0;
            while k<3 {
                if ph_lt(load64(first+216+k*8),load64(second+192+k*8)) || ph_lt(load64(second+216+k*8),load64(first+192+k*8)) {
                    eligible=0;
                }
                k=k+1;
            }
            if eligible {
                let kind=(load64(first+8)-1)*3+load64(second+8)-1+9*((!ma)+2*(!mb));
                store64(t+own*8,(kind<<32)|(a<<16)|b);
                own=own+1;
                let counter=(kind*64+lane)*8;
                gpu_shared_store64(counter,gpu_shared_load64(counter)+1);
            }
            b=b+1;
        }
        a=a+64;
    }
    gpu_shared_barrier();
    if lane<36 {
        let prefix=0;
        let i=0;
        while i<64 {
            let at=(lane*64+i)*8;
            let size=gpu_shared_load64(at);
            gpu_shared_store64(at,prefix);
            prefix=prefix+size;
            i=i+1;
        }
        gpu_shared_store64(18432+lane*8,prefix);
    }
    gpu_shared_barrier();
    if !lane {
        let total=0;
        c=0;
        while c<36 {
            let size=gpu_shared_load64(18432+c*8);
            gpu_shared_store64(18720+c*8,total);
            total=total+size;
            c=c+1;
        }
        store64(queue,total);
        store64(queue+8,workers);
        store64(ph_scratch(w)+8200,total);
    }
    gpu_shared_barrier();
    let i=0;
    while i<own {
        let pair=load64(t+i*8);
        let kind=pair>>32;
        let counter=(kind*64+lane)*8;
        let position=gpu_shared_load64(counter);
        let slot=gpu_shared_load64(18720+kind*8)+position;
        store64(queue+32+slot*8,((pair>>16&65535)<<32)|(pair&65535));
        gpu_shared_store64(counter,position+1);
        i=i+1;
    }
    gpu_barrier();
    return 1;
}
