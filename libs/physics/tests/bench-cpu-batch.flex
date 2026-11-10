// Diagnostic only: six balanced pairs, identical scenes and solver work.
import "../cpu-batch.flex";
import "fixtures.flex";
fn bench_equal(a,b,bytes) {
    let i=0;while i<bytes {if load64(a+i)!=load64(b+i) {return 0;}i=i+8;}return 1;
}
fn main(argc,argv) {
    h_environment(argc,argv);
    let count=30;let steps=2000;let workers=3;
    let stride=ph_world_bytes(16,24,256,4);
    let serial=alloc(count*stride);let batch=alloc(count*stride);
    let pair=0;
    while pair<6 {
        let i=0;while i<count {pt_scene(serial+i*stride,i%15);pt_scene(batch+i*stride,i%15);i=i+1;}
        let serial_ms=0;let batch_ms=0;let arm=0;
        while arm<2 {
            let start=net_now();
            if (arm+pair)%2 {
                h_assert(ph_cpu_batch_advance(batch,count,stride,steps,workers,120000)==1,"batch benchmark fault");
                batch_ms=net_now()-start;
            }
            else {
                i=0;while i<count {h_assert(ph_advance(serial+i*stride,steps),"serial benchmark fault");i=i+1;}
                serial_ms=net_now()-start;
            }
            arm=arm+1;
        }
        i=0;
        while i<count {
            let a=serial+i*stride;let b=batch+i*stride;
            h_assert(bench_equal(a,b,load64(a+104)) && bench_equal(a+stride-32,b+stride-32,32),"benchmark physical state mismatch");i=i+1;
        }
        h_print(1,h_cat3("serial_ms=",h_int(serial_ms)," batch_ms="));h_print(1,h_cat(h_int(batch_ms)," physical_parity=exact\n"));
        pair=pair+1;
    }
    syscall(11,serial,count*stride,0,0,0,0);syscall(11,batch,count*stride,0,0,0,0);
    return 0;
}
