import "../../lib/platform/esp32-sdk-task-select.flex";
import "../../scripts/lib/host.flex";
global sp_case=0;
global sp_checks=0;
fn sp_assert(ok,slot) {sp_checks=sp_checks+1;if !ok {h_print(2,h_cat3("Priority policy case ",h_int(sp_case),h_cat3(" slot ",h_int(slot)," failed\n")));syscall(60,1,0,0,0,0,0);}return 0;}
fn main(argc,argv) {
    h_environment(argc,argv);h_assert(argc==2,"requires reference vectors");let data=h_read(load64(argv+8));let size=h_file_size;h_assert(size>=8,"vector header");let cases=load64(data);let at=8;
    let tasks=alloc(8*640);let objects=alloc(8*32);
    while sp_case<cases {
        h_assert(at+32<=size,"case header");let count=load64(data+at);let current=load64(data+at+8);let now=load64(data+at+16);let expected=load64(data+at+24);at=at+32;
        h_assert(count>=1 && count<=8 && current>=0 && current<count && at+count*96<=size,"bounded case");let start=at;let i=0;
        while i<count {
            let t=tasks+i*640;let object=objects+i*32;let row=data+at;let j=0;while j<640 {store8(t+j,0);j=j+1;}j=0;while j<32 {store8(object+j,0);j=j+1;}
            store64(t,0x123456789abcdef);store64(t+504,0x7fedcba987654321);store64(t+632,0x23456789abcdef);store64(t+624,31);
            store64(t+536,tasks+((i+1)%count)*640);store64(t+552,load64(row));store64(t+544,load64(row+8));store64(t+560,load64(row+16));store64(t+592,load64(row+24));
            let word=load64(row+32);if load64(row+24)==2 {if word<0 {word=0;}else if word<count {word=tasks+word*640;}else {word=0x123456;}}
            store64(object,word);store64(object+8,load64(row+40));store64(object+24,load64(row+48));store64(t+608,load64(row+56));store64(t+616,load64(row+64));if load64(row+72) {store64(t+600,object);}
            i=i+1;at=at+96;
        }
        let chosen=esp_sdk_task_choose(tasks+current*640,now);let index= -1;if chosen {index=(chosen-tasks)/640;}sp_assert(index==expected,0);i=0;
        while i<count {let t=tasks+i*640;let row=data+start+i*96;sp_assert(load64(t+624)==load64(row+80),1+i*16);sp_assert(esp_sdk_task_ready(t,now)==load64(row+88),2+i*16);
            sp_assert(load64(t+552)==load64(row) && load64(t+544)==load64(row+8) && load64(t+560)==load64(row+16),3+i*16);
            sp_assert(load64(t+592)==load64(row+24) && load64(t+608)==load64(row+56) && load64(t+616)==load64(row+64),4+i*16);
            sp_assert(load64(t)==0x123456789abcdef && load64(t+504)==0x7fedcba987654321 && load64(t+632)==0x23456789abcdef,5+i*16);i=i+1;
        }sp_case=sp_case+1;
    }h_assert(at==size,"exact vector length");h_print(1,h_cat3("Priority policy: ",h_int(sp_checks),h_cat3(" checks across ",h_int(cases)," independent cases\n")));return 0;
}
