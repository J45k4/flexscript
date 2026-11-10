import "../soft-chain.flex";
fn sc_number(n,d) { return gpu_f32_pack(f64_div(f64_from_i64(n), f64_from_i64(d))); }
fn main(argc,argv) {
    h_environment(argc,argv);
    let w = ph_world(8,8,128,0); store64(w + 144, 0);
    let ids = alloc(24); let i = 0;
    while i < 3 { let kind = 1; if i != 1 { kind = 0; }
        let id = ph_sphere_body(w, kind, sc_number((i - 1) * 40,1000), 0, sc_number(100,1000), sc_number(10,1000), sc_number(5,1000));
        store64(ids + i * 8, id); i = i + 1;
    }
    let chain = sc_chain(w, ids, 3, sc_number(20,1), sc_number(2,1), sc_number(1,10));
    let mid = ph_body(w,load64(ids + 8)); store64(mid + 16, sc_number(20,1000)); store64(mid + 144,sc_number(1,100));
    let initial = load64(mid + 16); i = 0;
    while i < 2000 { h_assert(sc_step(chain), "spring dynamics fault"); i = i + 1; }
    h_assert(ph_lt(ph_abs(load64(mid + 16)), ph_mul(initial, sc_number(1,2))), "bent chain failed to restore toward rest");
    h_assert(load64(mid + 144)==sc_number(1,100) && !load64(mid + 152) && !load64(mid + 160), "external force changed during spring step");
    sc_close(chain); ph_world_close(w);
    w = ph_world(8,8,128,0); ph_box_body(w,0,0,0,sc_number(-5,1000),0,sc_number(1,1),sc_number(1,1),sc_number(5,1000));
    i = 0; while i < 3 { let id = ph_sphere_body(w,1,sc_number((i-1)*40,1000),0,sc_number(100,1000),sc_number(10,1000),sc_number(5,1000)); store64(ids+i*8,id); i=i+1; }
    chain = sc_chain(w,ids,3,sc_number(20,1),sc_number(2,1),sc_number(1,10));
    i = 0; while i < 500 { h_assert(sc_step(chain), "falling chain dynamics fault"); i=i+1; }
    i = 0; while i < 3 { let b = ph_body(w,load64(ids+i*8)); h_assert(!ph_lt(load64(b+24),sc_number(4,1000)), "chain particle penetrated floor"); i=i+1; }
    h_assert(load64(w+24)>0, "chain has no floor contacts"); sc_close(chain); ph_world_close(w);
    w = ph_world(8,8,128,0); store64(w+144,0); let group = alloc(16); let j=0;
    while j<2 { i=0; while i<3 { let id=ph_sphere_body(w,1,sc_number((i-1)*40,1000),sc_number(j*80,1000),sc_number(100,1000),sc_number(10,1000),sc_number(5,1000)); store64(ids+i*8,id); i=i+1; }
        let c=sc_chain(w,ids,3,sc_number(20,1),sc_number(2,1),sc_number(1,10)); store64(group+j*8,c);
        let middle=ph_body(w,load64(ids+8)); store64(middle+16,sc_number(j*80+20,1000)); j=j+1;
    }
    i=0; while i<100 { h_assert(sc_step_group(group,2), "group step failed"); i=i+1; }
    h_assert(load64(w+176)==100,"group must advance world only once per step");
    h_assert(ph_lt(load64(ph_body(w,1)+16),sc_number(20,1000)) && ph_lt(load64(ph_body(w,4)+16),sc_number(100,1000)),"both chains must respond");
    let first = load64(group); let second = load64(group+8);
    let duplicate = sc_chain(w,load64(first+24),3,sc_number(20,1),sc_number(2,1),sc_number(1,10));
    let guarded = ph_body(w,0); store64(guarded+144,sc_number(1,100)); let before = load64(guarded+8);
    store64(group+8,duplicate);
    h_assert(!sc_step_group(group,2),"group must reject overlapping particles");
    h_assert(load64(w+176)==100 && load64(guarded+8)==before && load64(guarded+144)==sc_number(1,100) && !load64(w+192),"shared-particle rejection changed world");
    store64(group+8,second); sc_close(duplicate);
    ph_settings(w,sc_number(1,100),12,sc_number(8,10),0);
    h_assert(!sc_step_group(group,2) && load64(w+176)==100,"unstable changed timestep must be rejected before advancing");
    ph_settings(w,sc_number(2,1000),12,sc_number(8,10),0);
    let b1 = ph_body(w,1); let b2 = ph_body(w,2); i=0;
    while i<3 { store64(b2+8+i*8,load64(b1+8+i*8)); i=i+1; }
    h_assert(!sc_step_group(group,2) && load64(w+192)==2 && load64(w+176)==100,"coincident spring must fault without advancing");
    h_assert(load64(guarded+144)==sc_number(1,100),"fault must restore saved external force");
    sc_close(load64(group)); sc_close(load64(group+8)); syscall(11,group,16,0,0,0,0); ph_world_close(w);
    w=ph_world(4,4,128,0); i=0;
    while i<3 { let id=ph_sphere_body(w,1,sc_number((i-1)*40,1000),0,sc_number(100,1000),sc_number(10,1000),sc_number(5,1000)); store64(ids+i*8,id); i=i+1; }
    chain=sc_chain(w,ids,3,sc_number(20,1),sc_number(2,1),sc_number(1,10));
    let b=ph_body(w,0); store64(b+144,sc_number(2,100)); store64(ph_body(w,2)+8,0x7fc00000);
    h_assert(!sc_step(chain) && load64(w+192)==2 && !load64(w+176),"nonfinite spring must fault without advancing");
    h_assert(load64(b+144)==sc_number(2,100),"nonfinite failure must restore external force");
    sc_close(chain); ph_world_close(w); syscall(11,ids,24,0,0,0,0); h_print(1,"soft chain bending, contact, and rejection checks pass\n"); return 0;
}
