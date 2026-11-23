// Normal execution of the ordinary branch transfer after metering/clock.
// Intel SDM volume 2 entries TEST, Jcc and JMP. RIP is an image offset.
global branch_rip=0;
global branch_rax=0;
global branch_rsp=0;
global branch_flags=0;

spec fn jit_low_byte_even(value) {
    return !((value^(value>>1)^(value>>2)^(value>>3)^(value>>4)^(value>>5)^(value>>6)^(value>>7))&1);
}

ensures (result&1)==0 && (result&2048)==0;
ensures ((result&128)!=0)==(value<0);
ensures ((result&64)!=0)==(value==0);
ensures ((result&4)!=0)==jit_low_byte_even(value);
ensures (result&16)==(undefined_auxiliary&16);
ensures (result&(~0x8d5))==(prior&(~0x8d5));
fn jit_test_rax_flags(value,prior,undefined_auxiliary) {
    let tested=value&value;
    let folded=tested^(tested>>4);
    folded=folded^(folded>>2);
    folded=folded^(folded>>1);
    return (prior&(~0x8d5))|((tested<0)*128)|((tested==0)*64)|
           ((!(folded&1))*4)|(undefined_auxiliary&16);
}

requires readable_bytes(address,4);
spec fn jit_branch_signed_displacement(address) {
    let bits=load8(address)|(load8(address+1)<<8)|(load8(address+2)<<16)|(load8(address+3)<<24);
    return (bits<<32)>>32;
}

requires size>=6 && size<=67108864;
requires site>=1 && site<=size-5;
requires (op==10 || op==11 || op==12);
requires op==10 || site>=5;
requires target>=0 && target<size;
requires branch_rip==site-1-4*(op!=10);
requires readable_bytes(code,size);
requires readable_bytes(code+site-1,1);
requires op==10 || readable_bytes(code+site-5,5);
requires readable_bytes(code+site,4);
requires load8(code+site-1)==(233*(op==10)+132*(op==11)+133*(op==12));
requires op==10 || load8(code+site-2)==15;
requires op==10 || load8(code+site-3)==192;
requires op==10 || load8(code+site-4)==133;
requires op==10 || load8(code+site-5)==72;
requires jit_branch_signed_displacement(code+site)==target-site-4;
modifies branch_rip,branch_flags;
ensures branch_rax==old(branch_rax) && branch_rsp==old(branch_rsp);
ensures branch_rip>=0 && branch_rip<size;
ensures op!=10 || branch_rip==target;
ensures op!=11 || (old(branch_rax)==0 && branch_rip==target) || (old(branch_rax)!=0 && branch_rip==site+4);
ensures op!=12 || (old(branch_rax)!=0 && branch_rip==target) || (old(branch_rax)==0 && branch_rip==site+4);
ensures op!=10 || branch_flags==old(branch_flags);
ensures op==10 || ((branch_flags&64)!=0)==(old(branch_rax)==0);
fn jit_model_branch_transfer(code,size,site,target,op,undefined_auxiliary) {
    let opcode=load8(code+site-1);
    let relative=jit_read_branch_displacement(code+site);
    let following=site+4;
    proof {jit_branch_transfer_destination(site,target,size,relative);}
    if opcode==233 {
        branch_rip=following+relative;
        proof {jit_branch_successor_bounds(branch_rip,following,target,size);}
        return 0;
    }
    proof {assert branch_rip==site-5;}
    branch_flags=jit_test_rax_flags(branch_rax,branch_flags,undefined_auxiliary);
    branch_rip=branch_rip+3;
    proof {assert branch_rip==site-2;}
    let zero=(branch_flags&64)!=0;
    branch_rip=following;
    if (opcode==132 && zero) || (opcode==133 && !zero) {
        branch_rip=following+relative;
    }
    proof {jit_branch_successor_bounds(branch_rip,following,target,size);}
    return 0;
}

requires readable_bytes(address,4);
ensures result==jit_branch_signed_displacement(address);
fn jit_read_branch_displacement(address) {
    let bits=load8(address)|(load8(address+1)<<8)|(load8(address+2)<<16)|(load8(address+3)<<24);
    return (bits<<32)>>32;
}

requires size>=6 && size<=67108864;
requires site>=1 && site<=size-5;
requires target>=0 && target<size;
requires relative==target-site-4;
ensures site+4>=5 && site+4<size;
ensures site+4+relative==target;
lemma fn jit_branch_transfer_destination(site,target,size,relative) {
    assert site+4>=5 && site+4<size;
    jit_branch_relative_range(site,target,size);
    jit_merged_branch_landing(site,target,relative,target-site-4);
}


BRANCH_RELATIVE_RANGE

requires target>=0 && target<size && following>=0 && following<size;
requires ip==target || ip==following;
ensures ip>=0 && ip<size;
lemma fn jit_branch_successor_bounds(ip,following,target,size) {}

BRANCH_RELATIVE_LANDING


requires op==10 || op==11 || op==12;
modifies nothing;
ensures op!=10 || result==arg;
ensures op!=11 || (acc==0 && result==arg) || (acc!=0 && result==following);
ensures op!=12 || (acc!=0 && result==arg) || (acc==0 && result==following);
fn jit_vm_branch_after_fetch(op,arg,following,acc) {
    let vm_pc=following;
    let vm_acc=acc;
PRODUCTION_VM_BRANCH_CASES
    return vm_pc;
}
