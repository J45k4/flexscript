// The proof allocator models the successful RW mapping at the admitted extent.
// The protection status is supplied by the publication model.
requires output_size>=5 && output_size<=67108864;
requires observed>=1 && observed<=output_size-4;
requires target>=0 && target<output_size;
requires readable_bytes(output,output_size);
requires readable_bytes(output+observed,4);
requires ((jit_rel32_bits(output+observed)<<32)>>32)==target-observed-4;
requires vm_jit_bytes>=0 && vm_jit_bytes<=16777216;
requires index>=0 && index<18432;
requires writable_bytes(vm_jit_cache+index*32,16);
requires readable_bytes(vm_jit_cache+index*32+16,16);
requires disjoint_bytes(vm_jit_cache+index*32,16,vm_jit_cache+index*32+16,16);
modifies output,output_size,vm_mode,vm_jit_bytes,vm_jit_compilations,bytes(vm_jit_cache+index*32,16);
ensures output==bytecode && output_size==bytecode_size && vm_mode==1;
ensures result==0 || result>0 && protection>=0;
ensures result==0 || load64(vm_jit_cache+index*32)==result;
ensures result==0 || fresh_bytes(result,((old(output_size)+4095)/4096)*4096);
ensures result==0 || readable_bytes(result+observed,4);
ensures result==0 || jit_rel32_bits(result+observed)==old(jit_rel32_bits(output+observed));
ensures result==0 || result+observed+4+((jit_rel32_bits(result+observed)<<32)>>32)==result+target;
fn jit_allocate_and_publish_displacement(index,bytecode,bytecode_size,protection,observed,target) {
    let image_size=output_size;
    ghost let staged=jit_rel32_bits(output+observed);
    let cache=vm_jit_cache+index*32;
    let bytes=vm_jit_admitted_publication_extent(image_size,vm_jit_bytes);
    if bytes {
        proof {
            assert image_size<=bytes && bytes<=1048576;
        }
        let mapped=jit_allocate_image_for_publication(output,image_size,bytes,observed,cache);
        if mapped>0 {
            proof {
                assert fresh_bytes(mapped,image_size);
                assert writable_bytes(mapped,image_size);
                assert jit_rel32_bits(output+observed)==staged;
            }
            let published=jit_publish_relocated_displacement(index,bytecode,bytecode_size,mapped,protection,observed,target);
            if published {
                proof {
                    assert published==mapped;
                    assert load64(cache)==mapped;
                    assert fresh_bytes(mapped,bytes);
                    assert readable_bytes(mapped+observed,4);
                    assert jit_rel32_bits(mapped+observed)==staged;
                }
                return mapped;
            }
            return 0;
        }
    }
PRODUCTION_PUBLICATION_RESTORE
    return 0;
}

// Allocation model for the admitted staging image and an existing cache record.
requires size>=5 && size<=extent && extent<=1048576;
requires site>=1 && site<=size-4;
requires readable_bytes(staging,size);
requires writable_bytes(cache,16);
requires readable_bytes(cache+16,16);
requires disjoint_bytes(cache,16,cache+16,16);
modifies nothing;
ensures result<0 || result>0;
ensures result<0 || fresh_bytes(result,extent);
ensures result<0 || fresh_bytes(result,size);
ensures result<0 || writable_bytes(result,size);
ensures result<0 || readable_bytes(result+site,4);
ensures result<0 || disjoint_bytes(staging,size,result,size);
ensures result<0 || disjoint_bytes(result,size,cache,16);
ensures result<0 || disjoint_bytes(result+site,4,cache,16);
ensures result<0 || disjoint_bytes(result,size,cache+16,16);
fn jit_allocate_image_for_publication(staging,size,extent,site,cache) {
    let mapped=alloc(extent);
    if mapped>0 {
        proof {
            assert writable_bytes(mapped,extent);
            assert extent-size>=0;
            assert fresh_bytes(mapped,extent);
            assert fresh_bytes(mapped,size);
            assert disjoint_bytes(staging,size,mapped,extent);
            assert disjoint_bytes(cache,16,mapped,extent);
            assert disjoint_bytes(cache+16,16,mapped,extent);
            jit_image_region_prefix(mapped,extent,size,staging,size);
            jit_image_region_prefix(mapped,extent,size,cache,16);
            jit_image_region_prefix(mapped,extent,size,cache+16,16);
            jit_displacement_inside_mapping(mapped,size,site);
            jit_displacement_outside_cache(mapped,size,site,cache);
        }
    }
    return mapped;
}

requires size>=5 && size<=extent && extent<=1048576;
requires writable_bytes(mapped,extent);
requires readable_bytes(kept,length);
requires disjoint_bytes(kept,length,mapped,extent);
ensures writable_bytes(mapped,size);
ensures disjoint_bytes(kept,length,mapped,size);
ensures disjoint_bytes(mapped,size,kept,length);
lemma fn jit_image_region_prefix(mapped,extent,size,kept,length) {
    assert writable_bytes(mapped,size);
}

requires size>=5 && size<=1048576;
requires site>=1 && site<=size-4;
requires writable_bytes(base,size);
ensures writable_bytes(base+site,4);
ensures readable_bytes(base+site,4);
lemma fn jit_displacement_inside_mapping(base,size,site) {
    assert site+4<=size;
    assert (base+site)-base==site;
}

requires size>=5 && size<=1048576;
requires site>=1 && site<=size-4;
requires writable_bytes(mapped,size);
requires writable_bytes(mapped+site,4);
requires writable_bytes(cache,16);
requires disjoint_bytes(mapped,size,cache,16);
ensures disjoint_bytes(mapped+site,4,cache,16);
lemma fn jit_displacement_outside_cache(mapped,size,site,cache) {}
