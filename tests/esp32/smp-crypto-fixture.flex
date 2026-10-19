global st_case=0;
global st_checks=0;
global st_error=0;
global st_null= -1;
fn st_zero(p,n) {let i=0;while i<n {if load8(p+i) {return 0;}i=i+1;}return 1;}
fn st_fill(p,n,value) {let i=0;while i<n {store8(p+i,value);i=i+1;}return 0;}
fn st_check(ok) {st_checks=st_checks+1;if !ok && !st_error {st_error=st_checks;st_report(st_case,st_checks);}return ok;}
fn st_arity(kind) {if kind==0 {return 1;}if kind==1 || kind==8 {return 3;}if kind==2 {return 5;}if kind==3 {return 7;}if kind==4 {return 4;}if kind==7 {return 6;}return 2;}
fn st_drive(row,out,work,capacity) {
    let kind=load64(row);let a=row+32;let b=row+64;let c=row+96;let d=row+128;let e=row+160;let f=row+192;let g=row+224;
    if st_null==0 {a=0;}else if st_null==1 {b=0;}else if st_null==2 {c=0;}else if st_null==3 {d=0;}else if st_null==4 {e=0;}else if st_null==5 {f=0;}else if st_null==6 {g=0;}
    if kind==0 {return smp_cmac(a,row+256,load64(row+8),out,work,capacity);}
    if kind==1 {return smp_f4(a,b,c,load64(row+16),out,work,capacity);}
    if kind==2 {return smp_f5(a,b,c,d,e,out,work,capacity);}
    if kind==3 {return smp_f6(a,b,c,d,e,f,g,out,work,capacity);}
    if kind==4 {return smp_g2(a,b,c,d,out,work,capacity);}
    if kind==5 {return smp_h6(a,b,out,work,capacity);}
    if kind==6 {return smp_h7(a,b,out,work,capacity);}
    if kind==7 {return smp_c1(a,b,c,d,e,f,out,work,capacity);}
    if kind==8 {return smp_s1(a,b,c,out,work,capacity);}
    if kind==9 {return smp_ah(a,b,out,work,capacity);}return smp_e(a,b,out,work,capacity);
}
fn st_scratch(guard,used) {
    let i=0;while i<544 {let byte=165;if i>=16 && i<16+used {byte=0;}else if i>=16+used && i<528 {byte=90;}if load8(guard+i)!=byte {return 0;}i=i+1;}return 1;
}
fn st_outside(guard,size) {let i=0;while i<64 {if (i<16 || i>=16+size) && load8(guard+i)!=165 {return 0;}i=i+1;}return 1;}
fn st_run(records,count) {
    let output=alloc(64);let scratch=alloc(544);let copy=alloc(832);let i=0;
    while i<count {let row=records+i*832;st_case=i+1;let n=load64(row+800);let used=512;if !load64(row) {used=96;}
        st_fill(output,64,165);st_fill(scratch,544,165);st_fill(scratch+16,512,90);
        let r=st_drive(row,output+16,scratch+16,512);
        if !st_check(!r && st_backend_clean()) || !st_check(nb_equal(output+16,row+768,n)) || !st_check(st_outside(output,n) && st_scratch(scratch,used)) {return 1;}
        nb_copy(copy,row,832);st_fill(scratch,544,165);st_fill(scratch+16,512,90);r=st_drive(copy,copy+32,scratch+16,512);
        if !st_check(!r && nb_equal(copy+32,row+768,n) && st_backend_clean()) || !st_check(st_scratch(scratch,used)) {return 2;}
        let j=0;let same=1;while j<832 {if (j<32 || j>=32+n) && load8(copy+j)!=load8(row+j) {same=0;}j=j+1;}if !st_check(same) {return 3;}
        i=i+1;
    }return 0;
}

fn st_value(p,n,value) {let i=0;while i<n {if load8(p+i)!=value {return 0;}i=i+1;}return 1;}

fn st_large(records) {
    let count=load64(records);let at=records+8;let output=alloc(64);let scratch=alloc(544);let i=0;
    while i<count {let size=load64(at);st_case=1000+i;st_fill(output,64,165);st_fill(scratch,544,165);st_fill(scratch+16,512,90);
        if !st_check(!smp_cmac(at+8,at+40,size,output+16,scratch+16,512) && nb_equal(output+16,at+24,16) && st_outside(output,16) && st_scratch(scratch,96) && st_backend_clean()) {return 1;}
        at=at+40+size;i=i+1;}return 0;
}
