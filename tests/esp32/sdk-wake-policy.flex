import "../../lib/platform/esp32-sdk-task-select.flex";
import "../../scripts/lib/host.flex";
global wh_checks=0;
fn wh_check(ok) {wh_checks=wh_checks+1;h_assert(ok,"wake hint reference mismatch or state corruption");return 0;}
fn main(argc,argv) {
    h_environment(argc,argv);h_assert(argc==2,"requires vectors");let data=h_read(load64(argv+8));let size=h_file_size;h_assert(size>=8,"vectors header");let cases=load64(data);let at=8;let index=0;let tasks=alloc(8*640);let objects=alloc(8*32);
    while index<cases {
        h_assert(at+40<=size,"case header");let n=load64(data+at);let current=load64(data+at+8);let target=load64(data+at+16);let kind=load64(data+at+24);let expected=load64(data+at+32);at=at+40;h_assert(n>=1 && n<=8 && current>=0 && current<n && target>=0 && target<n && at+n*48<=size,"case bounds");let start=at;let i=0;
        while i<n {let t=tasks+i*640;let o=objects+i*32;let j=0;while j<640 {store8(t+j,0);j=j+1;}j=0;while j<32 {store8(o+j,0);j=j+1;}
            let row=data+at;store64(t,0x123456789abcdef);store64(t+504,0x7fedcba987654321);store64(t+624,100+i);store64(t+632,99);store64(t+536,tasks+((i+1)%n)*640);store64(t+552,load64(row));store64(t+544,load64(row+8));store64(t+560,load64(row+16));store64(t+592,load64(row+24));store64(t+600,o);
            let owner=load64(row+32);if owner>=0 && owner<n {store64(o,tasks+owner*640);}else if owner== -2 {store64(o,0x123456);}at=at+48;i=i+1;
        }
        wh_check(esp_sdk_task_wake_hint(tasks+current*640,objects+target*32,kind)==expected);i=0;
        while i<n {let row=data+start+i*48;let t=tasks+i*640;wh_check(load64(t+624)==100+i && load64(t)==0x123456789abcdef && load64(t+504)==0x7fedcba987654321);wh_check(load64(t+552)==load64(row) && load64(t+544)==load64(row+8) && load64(t+560)==load64(row+16) && load64(t+592)==load64(row+24) && load64(t+600)==objects+i*32);i=i+1;}
        wh_check(!esp_sdk_task_wake_hint(0,objects,kind) && !esp_sdk_task_wake_hint(tasks,0,kind));index=index+1;
    }h_assert(at==size,"exact vector length");h_print(1,h_cat3("Wake hint: ",h_int(wh_checks)," checks\n"));return 0;
}
