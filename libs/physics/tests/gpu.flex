import "fixtures.flex";
import "../hip.flex";
fn pt_compare_world(w,reference,scene) {
    let b=0;
    while b<load64(w+8) {
        let k=0;
        while k<13 {
            let a=load64(ph_body(w,b)+8+k*8);
            let expected=load64(ph_body(reference,b)+8+k*8);
            h_assert(pt_near(a,expected,pt_float(1,1000)),h_cat3("CPU/GPU state diverged scene=",h_int(scene),h_cat3(" body=",h_int(b),h_cat3(" field=",h_int(k),h_cat3(" actual_bits=",h_int(a),h_cat(" expected_bits=",h_int(expected)))))));
            k=k+1;
        }
        b=b+1;
    }
    return 0;
}
// Put the only eligible contact at the end of partial 64-lane rows. This
// independently catches dropped final-row pairs and candidate queue bounds.
fn pt_pair_boundaries(module) {
    let stride=ph_world_bytes(130,130,32,0);let worlds=alloc(stride*6);let reference=alloc(stride*6);let scene=0;
    while scene<6 {
        let count=64+scene;if scene>=3 {count=125+scene;}let w=worlds+scene*stride;ph_world_init(w,130,130,32,0);let i=0;
        while i<count {let kind=0;let mass=0;let x=pt_float(-(i+1)*2,1);if i>=count-2 {kind=1;mass=1065353216;x=pt_float((i-count+2)*15,1000);}ph_sphere_body(w,kind,x,0,1065353216,mass,pt_float(1,100));i=i+1;}
        scene=scene+1;
    }
    h_copy(reference,worlds,stride*6);let device=ph_device_create(module,worlds,6,stride);ph_hip_check(ph_device_advance(device,2));ph_hip_check(ph_device_read(device,worlds));
    scene=0;while scene<6 {let w=worlds+scene*stride;let expected=reference+scene*stride;h_assert(ph_advance(expected,2),"boundary CPU oracle fault");h_assert(!load64(w+192) && load64(w+176)==2 && load64(w+24)==1 && load64(expected+24)==1,"candidate batch lost the final eligible pair");let count=load64(w+8);h_assert(ph_lt(load64(ph_body(w,count-2)+8),0),"boundary spheres did not physically separate");let body=count-2;while body<count {let k=0;while k<13 {h_assert(pt_near(load64(ph_body(w,body)+8+k*8),load64(ph_body(expected,body)+8+k*8),pt_float(1,1000000)),"boundary trajectory differs from all-pairs oracle");k=k+1;}body=body+1;}scene=scene+1;}
    ph_device_close(device);syscall(11,worlds,stride*6,0,0,0,0);syscall(11,reference,stride*6,0,0,0,0);return 0;
}
fn main(argc,argv) {
    h_environment(argc,argv);
    h_assert(argc==2,"usage: physics-gpu KERNEL");
    let context=hip_context_device(0);
    h_assert(context,hip_error());
    let module=hip_module(h_read(load64(argv+8)));
    h_assert(module,hip_error());
    let stride=ph_world_bytes(16,24,256,4);
    let worlds=alloc(stride*15);
    let reference=alloc(stride*15);
    let i=0;
    while i<15 {
        pt_scene(worlds+i*stride,i);
        i=i+1;
    }
    h_copy(reference,worlds,stride*15);
    let device=ph_device_create(module,worlds,15,stride);
    // A complete 1000 ms trajectory (500 steps) in ONE device dispatch. No
    // model/state download occurs until all integration steps have finished.
    ph_hip_check(ph_device_advance(device,500));
    ph_hip_check(ph_device_read(device,worlds));
    i=0;
    while i<15 {
        let w=worlds+i*stride;
        pt_validate(w,i,500);
        h_assert(ph_advance(reference+i*stride,500),"CPU reference failed");
        pt_compare_world(w,reference+i*stride,i);
        i=i+1;
    }
    // Reuse VRAM without uploading initial state again; all worlds continue.
    ph_hip_check(ph_device_advance(device,1));
    ph_hip_check(ph_device_read(device,worlds));
    i=0;
    while i<15 {
        h_assert(load64(worlds+i*stride+176)==501,"GPU world did not resume in VRAM");
        h_assert(ph_advance(reference+i*stride,1),"CPU reference continuation failed");
        pt_compare_world(worlds+i*stride,reference+i*stride,i);
        i=i+1;
    }
    ph_device_close(device);
    // The warm-start cache is relocatable too: resume the downloaded pad stack
    // on CPU and compare the continuation to a purely CPU reference.
    h_assert(ph_advance(worlds+12*stride,1) && ph_advance(reference+12*stride,1),"cached stack cannot resume on CPU");
    pt_compare_world(worlds+12*stride,reference+12*stride,12);
    pt_validate(worlds+12*stride,12,502);
    h_assert(ph_advance(worlds,1) && load64(worlds+176)==502 && !load64(worlds+216),"GPU state cannot resume on CPU");
    // Every work item exits fault paths together; guard bytes catch overflow.
    ph_world_init(worlds,16,24,256,4);
    pt_box(worlds,0,0,0,-25,500,400,25);
    pt_box(worlds,1,0,0,19,50,30,20);
    store64(worlds+56,1);
    let guard=ph_contact(worlds,1);
    i=0;
    while i<32 {
        store64(guard+i*8,0x123456789abcdef0);
        i=i+1;
    }
    device=ph_device_create(module,worlds,1,stride);
    ph_hip_check(ph_device_advance(device,1));
    ph_hip_check(ph_device_read(device,worlds));
    h_assert(load64(worlds+192)==1 && load64(worlds+24)==1 && !load64(worlds+176),"GPU bounded contact fault");
    i=0;
    while i<32 {
        h_assert(load64(guard+i*8)==0x123456789abcdef0,"GPU contact overflow overwrote guard");
        i=i+1;
    }
    ph_hip_check(ph_device_advance(device,3));
    ph_hip_check(ph_device_read(device,worlds));
    h_assert(!load64(worlds+176),"faulted GPU world advanced");
    ph_device_close(device);
    ph_world_init(worlds,16,24,256,4);
    pt_box(worlds,1,0,0,100,50,30,20);
    store64(worlds+144,0x7fc00000);
    device=ph_device_create(module,worlds,1,stride);
    ph_hip_check(ph_device_advance(device,2));
    ph_hip_check(ph_device_read(device,worlds));
    h_assert(load64(worlds+192)==2 && !load64(worlds+176),"GPU nonfinite fault");
    ph_device_close(device);
    pt_pair_boundaries(module);
    ph_hip_check(hip_unload(module));
    ph_hip_check(hip_close(context));
    syscall(11,worlds,stride*15,0,0,0,0);
    syscall(11,reference,stride*15,0,0,0,0);
    h_print(1,"GPU-resident batch and CPU parity checks pass\n");
    return 0;
}
