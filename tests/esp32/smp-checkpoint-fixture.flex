global pc_output=0;
global pc_work=0;
global pc_checks=0;
global pc_case=0;
fn pc_fill(p,n,value) {let i=0;while i<n {store8(p+i,value);i=i+1;}return 0;}
fn pc_value(p,n,value) {let i=0;while i<n {if load8(p+i)!=value {return 0;}i=i+1;}return 1;}
fn pc_drive(row) {
    let op=load64(row);let sequence=load64(row+8);let revision=load64(row+16);let n=load64(row+24);let variant=load64(row+48);let key=row+112;let scope=row+128;let input=row+144;let out=pc_output+16;let capacity=1408;let work=pc_work+16;let work_capacity=112;if op==1 {work_capacity=ck_seal_work(n);if work_capacity<0 {work_capacity=1504;}}
    if variant==1 {key=0;}if variant==2 {scope=0;}if variant==3 {input=0;}if variant==4 {out=0;}if variant==5 {work=0;}if variant==6 {if op==1 {capacity=ck_size(n)-1;}else {capacity=n-65;}}if variant==7 {work_capacity=work_capacity-1;}if variant==8 {work_capacity=9223372036854775807;}if variant==9 {key=scope;}if variant==10 {key=input;}if variant==11 {scope=input;}if variant==12 {scope=input+32;}if variant==13 {out=input;}if variant==14 {out=key;}if variant==15 {work=out;}if variant==16 {work=input;}if variant==17 {capacity=9223372036854775807;}
    if op==1 {return ck_seal(key,scope,sequence,revision,input,n,out,capacity,work,work_capacity);}if op==2 {return ck_open(key,scope,sequence,revision,input,n,out,capacity,work,work_capacity);}return -1000;
}
fn pc_bad(row,field,actual,expected) {pc_report(pc_case,load64(row),field,actual,expected);return 8;}
fn pc_run(data,size) {
    if size<16 || !nb_equal(data,"SMPENV01",8) {return 1;}let count=load64(data+8);if count<1 || count>65535 {return 2;}pc_output=alloc(1440);pc_work=alloc(1536);let at=16;let i=0;
    while i<count {pc_case=i+1;if at>size-144 {return 3;}let row=data+at;let actual=load64(row+88);let output=load64(row+80);let wipe=load64(row+72);if actual<0 || output<0 || output>1408 || wipe<0 || wipe>1504 || actual>size-at-144 || output>size-at-144-actual || load64(row+104) {return 4;}let expected=row+144+actual;
        pc_fill(pc_output,1440,165);pc_fill(pc_work,1536,165);pc_fill(pc_work+16,1504,90);pc_before(load64(row+40),load64(row+32));let result=pc_drive(row);pc_checks=pc_checks+1;
        if result!=load64(row+56) {return pc_bad(row,0,result,load64(row+56));}if pc_calls()!=load64(row+64) {return pc_bad(row,1,pc_calls(),load64(row+64));}
        if !pc_value(pc_work+16,wipe,0) || !pc_value(pc_work+16+wipe,1504-wipe,90) {return pc_bad(row,2,0,wipe);}if !nb_equal(pc_output+16,expected,output) {let at=0;while at<output && load8(pc_output+16+at)==load8(expected+at) {at=at+1;}return pc_bad(row,16+at,load8(pc_output+16+at),load8(expected+at));}
        if !pc_value(pc_output+16+output,1408-output,165) {return pc_bad(row,3,0,1);}if !pc_backend_clean() {return pc_bad(row,4,0,1);}if !pc_ps_clean() {return pc_bad(row,5,0,1);}
        if !pc_value(pc_output,16,165) || !pc_value(pc_output+1424,16,165) || !pc_value(pc_work,16,165) || !pc_value(pc_work+1520,16,165) {return pc_bad(row,6,0,1);}let sum=0;let j=0;while j<32+actual {sum=sum+(j+1)*load8(row+112+j);j=j+1;}if sum!=load64(row+96) {return pc_bad(row,7,sum,load64(row+96));}
        at=at+144+actual+output;i=i+1;
    }if at!=size {return 5;}return 0;
}
