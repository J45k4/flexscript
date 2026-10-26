// Independent unzip interoperability and malformed-archive checks for the
// native ZIP transport used by Android packaging and SDK dependency handling.
import "lib/zip.flex";
fn main(argc,argv){
    h_environment(argc,argv);
    if argc==3&&h_equal(load64(argv+8),"--reject"){let archive=az_open(load64(argv+16));let entries=load64(archive+16);let i=0;while i<h_count(entries){az_data(h_at(entries,i));i=i+1;}return 0;}
    let root=h_temp();let path=h_join(root,"sample.zip");let data=h_take(32791);let i=0;while i<32791{store8(data+i,(i*73+i/251)&255);i=i+1;}
    let entries=h_vec();h_add(entries,az_new("stored.bin",data,32791,0));h_add(entries,az_new("assets/🐾.bin",data,32791,1));h_add(entries,az_new("empty",data,0,1));az_write(path,entries);
    h_ok(h_args("unzip","-t",path,0,0,0));let actual=h_ok(h_args("unzip","-p",path,"assets/🐾.bin",0,0));h_assert(h_size(load64(actual+16))==32791&&h_bytes(h_out(actual),data,32791),"Independent unzip changed binary payload");
    let archive=az_open(path);let e=az_find(archive,"stored.bin");h_assert(h_bytes(az_data(e),data,32791),"Stored ZIP roundtrip changed bytes");e=az_find(archive,"assets/🐾.bin");h_assert(h_bytes(az_data(e),data,32791),"Deflated ZIP roundtrip changed bytes");h_assert(load64(az_find(archive,"empty")+24)==0,"Empty compressed member changed size");az_data(az_find(archive,"empty"));
    h_print(1,"PASS native ZIP stored/deflated/empty/UTF-8 members interoperate with independent unzip\n");
    let executable=h_real(load64(argv));let bad=h_join(root,"corrupt.zip");let original=h_read(path);let n=h_file_size;let copy=h_take(n);h_copy(copy,original,n);let member=az_find(archive,"stored.bin");let offset=load64(member+40)-load64(archive);store8(copy+offset+17,load8(copy+offset+17)^1);h_save_bytes(bad,copy,n,420);h_check(h_run(h_args(executable,"--reject",bad,0,0,0)),1,0);
    h_copy(copy,original,n);let raw=load64(archive);let central=az_u32(raw+n-6);h_assert(central>0&&central+46<n&&az_u32(raw+central)==0x02014b50,"Missing test central directory");store8(copy+central+46,47);h_save_bytes(bad,copy,n,420);h_check(h_run(h_args(executable,"--reject",bad,0,0,0)),1,0);
    h_save_bytes(bad,original,21,420);h_check(h_run(h_args(executable,"--reject",bad,0,0,0)),1,0);
    h_assert(!az_name("../outside")&&!az_name("/absolute")&&!az_name("a/../b")&&!az_name("a\\b")&&az_name("META-INF/NOTICE.txt"),"ZIP member path validation failed");
    h_print(1,"PASS malformed/truncated ZIP paths and actual payload CRC corruption are rejected\n");h_remove(root);return 0;
}
