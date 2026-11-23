// Nonnegative native patch32 and one selected kind-2 JIT relocation row.

requires vm_mode==0;
requires at>=0 && at<=67108860;
requires writable_bytes(output+at,4);
modifies bytes(output+at,4);
ensures result==0;
ensures load8(output+at)==(value&255);
ensures load8(output+at+1)==((value>>8)&255);
ensures load8(output+at+2)==((value>>16)&255);
ensures load8(output+at+3)==((value>>24)&255);
fn patch32(at, value) {
    if vm_mode {return -1;}
    // Recorded branches return negative handles. Existing relative-fixup
    // callers still yield the absolute target through at+4+value.
    if at<0 {return -1;}
    let i = 0;
    invariant i>=0 && i<=4;
    invariant i<1 || load8(output+at)==(value&255);
    invariant i<2 || load8(output+at+1)==((value>>8)&255);
    invariant i<3 || load8(output+at+2)==((value>>16)&255);
    invariant i<4 || load8(output+at+3)==((value>>24)&255);
    decreases 4-i;
    while i < 4 {
        proof {
            patch32_contains_byte(output+at,output+at+i,i);
        }
        store8(output + at + i, value >> (i * 8));
        i = i + 1;
    }
    return 0;
}

requires vm_mode==0;
requires i==row && row>=0 && row<32768;
requires site>=2 && site<=67108860;
requires division>=site+4 && division<=67108864;
requires output+site>=2 && output+site<=9223372036854775803;
requires readable_bytes(vm_jit_errors+row*16,16);
requires load64(vm_jit_errors+row*16)==site;
requires load64(vm_jit_errors+row*16+8)==2;
requires writable_bytes(output+site,4);
requires readable_bytes(output+site-2,2);
requires load8(output+site-2)==15 && load8(output+site-1)==132;
requires disjoint_bytes(output+site,4,vm_jit_errors+row*16,16);
requires disjoint_bytes(output+site,4,output+site-2,2);
modifies bytes(output+site,4);
ensures result==row+1;
// Use the entry offset so applying the summary keeps the patch address stable.
ensures load64(vm_jit_errors+row*16)==old(site);
ensures load64(vm_jit_errors+row*16+8)==2;
ensures load8(output+site-2)==15 && load8(output+site-1)==132;
ensures load8(output+site)==((division-site-4)&255);
ensures load8(output+site+1)==(((division-site-4)>>8)&255);
ensures load8(output+site+2)==(((division-site-4)>>16)&255);
ensures load8(output+site+3)==(((division-site-4)>>24)&255);
ensures (load8(output+site+3)&128)==0;
ensures site+4+(load8(output+site)|(load8(output+site+1)<<8)|(load8(output+site+2)<<16)|(load8(output+site+3)<<24))==division;
fn vm_jit_patch_division_record(i,row,site,failure,fuel,division,bounds,timeout) {
    // Production record loads and error target selection.
    proof {
        assert at==site;
        assert kind==2;
        assert target==division;
        assert target-at-4>=0 && target-at-4<=67108864;
    }
    patch32(at,target-at-4);i=i+1;
    proof {
        assert load64(vm_jit_errors+row*16)==site;
        assert load64(vm_jit_errors+row*16+8)==2;
        assert load8(output+site-2)==15;
        assert load8(output+site-1)==132;
        x86_forward_rel32_displacement(site,division);
        let b0=load8(output+site);
        let b1=load8(output+site+1);
        let b2=load8(output+site+2);
        let b3=load8(output+site+3);
        let decoded=b0|(b1<<8)|(b2<<16)|(b3<<24);
        x86_forward_rel32_bytes(division-site-4,b0,b1,b2,b3);
        x86_forward_rel32_landing(site,division,decoded,division-site-4);
    }
    return i;
}

requires index>=0 && index<4;
requires address==base+index;
ensures address-base>=0 && address-base<=3;
lemma fn patch32_contains_byte(base,address,index) {
    if index==0 {
        assert address==base;
        assert address-base==0;
        return 0;
    }
    if index==1 {
        assert address==base+1;
        assert address-base==1;
        return 0;
    }
    if index==2 {
        assert address==base+2;
        assert address-base==2;
        return 0;
    }
    assert index==3;
    assert address==base+3;
    assert address-base==3;
}

requires at>=0 && at<=67108860;
requires target>=at+4 && target<=67108864;
ensures target-at-4>=0 && target-at-4<=67108864;
ensures at+4+(target-at-4)==target;
lemma fn x86_forward_rel32_displacement(at,target) {
    assert target-at>=4 && target-at<=67108864;
}

requires value>=0 && value<=67108864;
requires b0==(value&255);
requires b1==((value>>8)&255);
requires b2==((value>>16)&255);
requires b3==((value>>24)&255);
ensures (b3&128)==0;
ensures (b0|(b1<<8)|(b2<<16)|(b3<<24))==value;
lemma fn x86_forward_rel32_bytes(value,b0,b1,b2,b3) {
    assert (value&0xffffffff)==value;
}

requires decoded==offset;
requires site+4+offset==target;
ensures site+4+decoded==target;
lemma fn x86_forward_rel32_landing(site,target,decoded,offset) {}
