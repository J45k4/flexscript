// Diagnostic only: thin cuboids, no wristband pad cylinders. One event-timed
// 100 ms sample after 1 s settling; no CPU, MuJoCo or end-to-end speed claim.
import "fixtures.flex";
import "../hip.flex";
fn main(argc,argv) {
    h_environment(argc,argv);
    h_assert(argc==2,"usage: physics-benchmark KERNEL");
    let context=hip_context_device(0);
    h_assert(context,hip_error());
    let module=hip_module(h_read(load64(argv+8)));
    h_assert(module,hip_error());
    let counts=h_args(3,50,100,0,0,0);
    let j=0;
    while j<h_count(counts) {
        let count=h_at(counts,j);
        let w=ph_world(128,256,4096,4);
        pt_box(w,0,0,0,-25,500,400,25);
        let i=0;
        while i<count {
            let b=pt_box(w,1,(i*37%151)-75,(i*61%151)-75,50+i*9,105,12,2);
            let q=pt_float(382683,1000000);
            if i%2 {
                q=ph_neg(q);
            }
            ph_body_quaternion(w,b,0,0,q,pt_float(923880,1000000));
            i=i+1;
        }
        let device=ph_device_create(module,w,1,load64(w+112));
        let start=hip_event();
        let end=hip_event();
        ph_hip_check(hip_event_record(start,0));
        ph_hip_check(ph_device_advance(device,500));
        ph_hip_check(hip_event_record(end,0));
        ph_hip_check(hip_event_wait(end));
        let settling=hip_event_elapsed_f32(start,end);
        ph_hip_check(ph_device_read(device,w));
        h_assert(!load64(w+192),"benchmark physics fault");
        ph_hip_check(hip_event_record(start,0));
        ph_hip_check(ph_device_advance(device,50));
        ph_hip_check(hip_event_record(end,0));
        ph_hip_check(hip_event_wait(end));
        let elapsed=hip_event_elapsed_f32(start,end);
        ph_hip_check(ph_device_read(device,w));
        h_assert(!load64(w+192),"benchmark physics fault");
        let minz=0x7f7fffff;
        let maxz=0;
        let maxspeed=0;
        i=1;
        while i<=count {
            let b=ph_body(w,i);
            minz=ph_min(minz,load64(b+24));
            maxz=ph_max(maxz,load64(b+24));
            maxspeed=ph_max(maxspeed,ph_sqrt(ph_vdot(b+64,b+64)));
            i=i+1;
        }
        h_print(1,h_cat3(h_int(count)," boxes: settle_us=",h_int(f64_to_i64_trunc(f64_mul(gpu_f32_unpack(settling),f64_from_i64(1000))))));
        h_print(1,h_cat(" tick_us=",h_int(f64_to_i64_trunc(f64_mul(gpu_f32_unpack(elapsed),f64_from_i64(1000))))));
        h_print(1,h_cat(" contacts=",h_int(load64(w+24))));
        h_print(1,h_cat(" min_z_um=",h_int(f64_to_i64_trunc(f64_mul(gpu_f32_unpack(minz),f64_from_i64(1000000))))));
        h_print(1,h_cat(" max_z_um=",h_int(f64_to_i64_trunc(f64_mul(gpu_f32_unpack(maxz),f64_from_i64(1000000))))));
        h_print(1,h_cat(" max_speed_um_s=",h_int(f64_to_i64_trunc(f64_mul(gpu_f32_unpack(maxspeed),f64_from_i64(1000000))))));
        h_print(1,"\n");
        hip_event_close(start);
        hip_event_close(end);
        ph_device_close(device);
        ph_world_close(w);
        j=j+1;
    }
    hip_unload(module);
    hip_close(context);
    return 0;
}
