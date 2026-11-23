// The proof gate inserts the guarded production branch loop and native patch32.
global output=0;
global output_size=0;
global vm_mode=0;
global vm_jit_branches=0;
global vm_jit_branch_count=0;
global vm_jit_map=0;

requires vm_mode==0;
requires output_size>=0 && output_size<=67108864;
requires writable_bytes(output,output_size);
requires vm_jit_branch_count<0 || vm_jit_branch_count>8192 || readable_bytes(vm_jit_branches,vm_jit_branch_count*16);
requires map_count<1 || map_count>8192 || readable_bytes(vm_jit_map,map_count*8);
modifies bytes(output,output_size);
ensures result==0 || result==1;
ensures result==0 || (vm_jit_branch_count>=0 && vm_jit_branch_count<=8192 && map_count>=1 && map_count<=8192);
PRODUCTION_BRANCH_LOOP

PATCH32_PROFILE

requires index>=0 && index<count && count<=8192;
requires readable_bytes(base,count*16);
ensures readable_bytes(base+index*16,16);
ensures index+1<=count;
ensures count-(index+1)>=0 && count-(index+1)<count-index;
lemma fn jit_branch_record_step(base,index,count) {
    assert index<=8191;
    assert index+1<=count;
    assert index*16>=0 && index*16<=count*16-16;
    assert count-(index+1)+1==count-index;
}

requires index>=1 && index<count && count<=8192;
requires readable_bytes(base,count*8);
ensures readable_bytes(base+index*8,8);
lemma fn jit_branch_map_slot(base,index,count) {
    assert index<=8191;
    assert index*8>=0 && index*8<=count*8-8;
}

requires offset>=1 && offset<=size-4 && size<=67108864;
requires writable_bytes(base,size);
ensures offset+4>=0 && offset+4<=size;
ensures writable_bytes(base+offset,4);
lemma fn jit_branch_patch_span(base,size,offset) {
    assert offset<=67108860;
    assert offset<=size-4;
    assert offset+4>=0 && offset+4<=size;
    assert writable_bytes(base+offset,4);
}

requires size>=5 && size<=67108864;
requires site>=1 && site<=size-4;
requires target>=0 && target<size;
ensures target-site-4>=-67108864 && target-site-4<=67108864;
ensures site+4+(target-site-4)==target;
lemma fn jit_branch_relative_range(site,target,size) {
    assert site+4>=5 && site+4<=size;
    assert target<=67108863;
}

requires value>=-67108864 && value<=67108864;
requires b0==(value&255);
requires b1==((value>>8)&255);
requires b2==((value>>16)&255);
requires b3==((value>>24)&255);
ensures (((b0|(b1<<8)|(b2<<16)|(b3<<24))<<32)>>32)==value;
lemma fn jit_branch_signed_bytes(value,b0,b1,b2,b3) {
    let decoded=b0|(b1<<8)|(b2<<16)|(b3<<24);
    assert decoded==(value&4294967295);
    assert (decoded<<32)==(value<<32);
    assert (value<<32)>>32==value;
}
