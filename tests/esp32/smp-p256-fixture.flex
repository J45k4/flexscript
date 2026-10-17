global pv_output=0;
global pv_work=0;
global pv_checks=0;
global pv_case=0;
global pv_mode=0;
fn pv_fill(p,n,value) {let i=0;while i<n {store8(p+i,value);i=i+1;}return 0;}
fn pv_value(p,n,value) {let i=0;while i<n {if load8(p+i)!=value {return 0;}i=i+1;}return 1;}
fn pv_u32(p) {return load8(p)|(load8(p+1)<<8)|(load8(p+2)<<16)|(load8(p+3)<<24);}
fn pv_put32(p,value) {store8(p,value);store8(p+1,value>>8);store8(p+2,value>>16);store8(p+3,value>>24);return 0;}
fn pv_i32(v) {if v>=2147483648 {return v-4294967296;}return v;}
fn pv_drive(row) {
    let op=load64(row);let variant=load64(row+56);let private=row+128;let peer=private+32;let out=pv_output+16;let work=pv_work+16;let cap=256;
    if variant==1 {private=0;}if variant==2 {peer=0;}if variant==3 {out=0;}if variant==4 {work=0;}if variant==5 {cap=255;}if variant==6 {cap=9223372036854775807;}if variant==7 {private=work;}if variant==8 {peer=work;}if variant==9 {out=work;}
    if variant==10 || variant==11 {nb_copy(pv_output+16,row+128,96);private=pv_output+16;peer=private+32;if variant==11 {out=peer;}}if variant==12 {private=peer;}
    if op==1 {return p256_validate(peer,work,cap);}if op==2 {return p256_public(private,out,work,cap);}if op==3 {return p256_shared(private,peer,out,work,cap);}if op==4 {return p256_keypair(out,work,cap);}return -1000;
}
fn pv_bad(row,field,actual,expected) {pv_report(pv_case,load64(row),field,actual,expected);return 8;}
fn pv_run(data,size) {
    if size<16 || !nb_equal(data,"SMPP2561",8) {return 1;}let count=load64(data+8);if count<1 || count>65535 || size!=16+count*448 {return 2;}if !pv_output {pv_output=alloc(128);}if !pv_work {pv_work=alloc(288);}let i=0;
    while i<count {let row=data+16+i*448;pv_case=i+1;pv_fill(pv_output,128,165);pv_fill(pv_work,288,165);pv_fill(pv_work+16,256,90);pv_mode=load64(row+112);pv_before(row);let r=pv_drive(row);pv_after();pv_checks=pv_checks+1;
        if r!=load64(row+8) {return pv_bad(row,0,r,load64(row+8));}if pv_calls()!=load64(row+72) {return pv_bad(row,1,pv_calls(),load64(row+72));}if pv_rng_calls()!=load64(row+80) {return pv_bad(row,2,pv_rng_calls(),load64(row+80));}
        let wipe=load64(row+88);if wipe!=0 && wipe!=256 {return 3;}if !pv_value(pv_work+16,wipe,0) || !pv_value(pv_work+16+wipe,256-wipe,90) {return pv_bad(row,3,0,wipe);}
        if !nb_equal(pv_output+16,row+352,96) {let j=0;while j<96 && load8(pv_output+16+j)==load8(row+352+j) {j=j+1;}return pv_bad(row,100+j,load8(pv_output+16+j),load8(row+352+j));}
        if !pv_value(pv_output,16,165) || !pv_value(pv_output+112,16,165) || !pv_value(pv_work,16,165) || !pv_value(pv_work+272,16,165) {return pv_bad(row,4,0,1);}if !pv_clean() {return pv_bad(row,5,0,1);}if !pv_ps_clean() {return pv_bad(row,6,0,1);}
        let sum=0;let j=0;while j<224 {sum=sum+(j+1)*load8(row+128+j);j=j+1;}if sum!=load64(row+104) {return pv_bad(row,7,sum,load64(row+104));}i=i+1;
    }return 0;
}
