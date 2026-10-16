import "lib/build.flex";
import "../emulator/backends/software.flex";
fn bx_now() {let t=h_take(16);h_assert(syscall(228,1,t,0,0,0,0)==0,"clock_gettime");return load64(t)*1000000000+load64(t+8);}
fn bx_median(a,b,c) {if (a<=b && b<=c) || (c<=b && b<=a) {return b;}if (a<=c && c<=b) || (b<=c && c<=a) {return c;}return a;}
// Pin this benchmark process to one permitted CPU so native and emulated
// samples cannot migrate between cores with different performance.
fn bx_pin() {
    let mask=h_take(128);let i=0;while i<128 {store8(mask+i,0);i=i+1;}
    let bytes=syscall(204,0,128,mask,0,0,0);h_assert(bytes>0,"sched_getaffinity");let cpu=0;
    while cpu<bytes*8 && !(load8(mask+cpu/8)&(1<<(cpu%8))) {cpu=cpu+1;}h_assert(cpu<bytes*8,"permitted CPU");
    i=0;while i<128 {store8(mask+i,0);i=i+1;}store8(mask+cpu/8,1<<(cpu%8));h_assert(syscall(203,0,128,mask,0,0,0)==0,"sched_setaffinity");return cpu;
}
fn main(argc,argv) {
    h_environment(argc,argv);let cpu=bx_pin();let count=h_number(b_option(argc,argv,"--iterations","2000000"));h_assert(count>=1000 && count<=100000000,"iterations must be 1000..100000000");
    let report_path=b_option(argc,argv,"--report",0);let v=softvm_create(1048576);h_assert(v,"software VM");let c=load64(v+64);let ram=load64(v+24);let run=load64(v+40);
    // Identical arithmetic/branch instruction stream on hardware and guest.
    // Only the final instruction differs: native RET versus guest HLT.
    let native=alloc(4096);h_assert(native>0,"native benchmark allocation");let hex="b90000000031c031d24801d04883c2014883e90175f3c3";
    let i=0;while i<23 {let a=load8(hex+i*2);let b=load8(hex+i*2+1);if a>=97 {a=a-87;}else {a=a-48;}if b>=97 {b=b-87;}else {b=b-48;}store8(native+i,a*16+b);i=i+1;}kvm_put32(native+1,count);kvm_copy(ram+0x1000,native,23);store8(ram+0x1016,0xf4);
    h_assert(syscall(10,native,4096,5,0,0,0)==0,"native benchmark RX protection");
    let expected=count*(count-1)/2;let steps=count*4+4;let report=j_object();j_set(report,"host_cpu",j_int(cpu));j_set(report,"iterations",j_int(count));j_set(report,"guest_steps",j_int(steps));
    let names=h_args("native","interpreter","jit",0,0,0);let results=j_object();let mode=0;let native_ns=0;let interpreter_ns=0;let jit_ns=0;
    while mode<3 {
        let samples=h_vec();let sample=0;let jit_steps=0;let blocks=0;
        while sample<3 {
            x86_jit_enabled=mode==2;x86_start(c,0x1000,32,0,0);store64(c+144,64);
            let start=bx_now();
            if !mode {let repeat=0;while repeat<100 {h_assert(ffi_call(native,0,0,0,0,0,0)==expected,"native result");repeat=repeat+1;}}
            else {h_assert(x86_run(c,run,steps+1)==5 && load64(c)==expected && load64(c+312)==steps,"guest result and instruction count");}
            let elapsed=bx_now()-start;if !mode {elapsed=elapsed/100;}h_add(samples,elapsed);jit_steps=load64(c+1008);blocks=load64(c+1016);sample=sample+1;
        }
        let elapsed=bx_median(h_at(samples,0),h_at(samples,1),h_at(samples,2));if mode==0 {native_ns=elapsed;}else if mode==1 {interpreter_ns=elapsed;}else {jit_ns=elapsed;}let result=j_object();j_set(result,"elapsed_ns",j_int(elapsed));j_set(result,"jit_steps",j_int(jit_steps));j_set(result,"jit_blocks",j_int(blocks));j_set(results,h_at(names,mode),result);
        h_print(1,h_cat3(h_at(names,mode),": ",h_cat(h_int(elapsed)," ns median\n")));mode=mode+1;
    }
    h_print(1,h_cat3("JIT: ",h_int(interpreter_ns/jit_ns),h_cat3("x interpreter speed; ",h_int(native_ns*100/jit_ns),"% native throughput (integer loop only)\n")));
    j_set(report,"results",results);j_set(report,"timing",j_string("one permitted host CPU; median of three execution-only samples; native samples average 100 runs; same integer loop, RET versus HLT; one vCPU; not a full-system or KVM benchmark"));
    if report_path {j_save(report_path,report);}softvm_close(v);syscall(11,native,4096,0,0,0,0);return 0;
}
