import "fixtures.flex";
fn pt_contacts(w) {
    let i=0;
    while i<load64(w+8) {
        ph_cache_body(ph_body(w,i));
        i=i+1;
    }
    i=0;
    while i<load64(w+16) {
        ph_cache_shape(w,ph_shape(w,i));
        i=i+1;
    }
    return ph_collide(w);
}
fn pt_geometry(w) {
    ph_world_init(w,16,24,256,4);
    let a=pt_box(w,0,0,0,0,100,100,100);
    let b=ph_sphere_body(w,1,pt_float(105,1000),0,0,1065353216,pt_float(1,100));
    h_assert(pt_contacts(w) && load64(w+24)==1,"box/sphere face contact");
    let c=ph_contact(w,0);
    h_assert(pt_near(load64(c+64),pt_float(5,1000),pt_float(1,100000)),"box/sphere penetration");
    h_assert(pt_near(load64(c+40),1065353216,pt_float(1,100000)),"box/sphere normal");
    ph_vset(ph_body(w,b)+8,0,0,0);
    pt_contacts(w);
    h_assert(load64(w+24)==1 && pt_near(load64(c+64),pt_float(11,100),pt_float(1,100000)),"sphere contained in box");
    ph_world_init(w,16,24,256,4);
    a=pt_box(w,1,0,0,20,105,12,2);
    b=pt_box(w,1,50,-50,20,105,12,2);
    ph_body_quaternion(w,a,0,0,pt_float(382683,1000000),pt_float(923880,1000000));
    ph_body_quaternion(w,b,0,0,pt_float(382683,1000000),pt_float(923880,1000000));
    pt_contacts(w);
    h_assert(!load64(w+24),"OBB SAT rejects overlapping AABBs");
    ph_world_init(w,16,24,256,4);
    pt_box(w,0,330,0,5,125,155,5);
    pt_box(w,1,330,0,10,105,12,2);
    pt_contacts(w);
    h_assert(load64(w+24)==4,"equivalent cross axes must preserve face manifold");
    let i=0;
    while i<4 {
        c=ph_contact(w,i);
        h_assert(!ph_lt(pt_float(121,10000),ph_abs(load64(c+24))),"face contact outside incident box");
        h_assert(pt_near(load64(c+56),1065353216,pt_float(1,100000)),"flat face normal");
        i=i+1;
    }
    return 0;
}
// Color ranges must cover each manifold exactly once, preserve canonical
// order and never schedule two writers for a dynamic body concurrently.
fn pt_color_ranges() {
    let w=ph_world(72,1,512,1);let i=0;
    while i<72 {let dynamic=i<8;let mass=0;if dynamic {mass=1065353216;}ph_body_add(w,dynamic,0,0,0,mass,mass,mass,mass);i=i+1;}
    let contacts=0;let a=0;
    while a<8 {let b=a+1;while b<12 {let point=0;while point<2 {let c=ph_contact(w,contacts);store64(c,a);store64(c+8,b);store64(c+16,gpu_f32_from_i64(point));contacts=contacts+1;point=point+1;}b=b+1;}a=a+1;}
    store64(w+24,contacts);store64(ph_scratch(w)+16000,0x12345678);store64(ph_scratch(w)+16352,0x3bf8e8e7);ph_order(w);let colors=ph_color(w);h_assert(colors>1 && colors<64,"fixture must exercise several parallel colors");
    let seen=h_zero(h_take(512*8),512*8);let writers=h_take(72*8);let visited=0;let color=0;let end=0;
    while color<colors {h_zero(writers,72*8);let first=ph_color_begin(w,color);h_assert(first==end,"color ranges must be contiguous");end=ph_color_end(w,color);let previous=-1;i=first;
        while i<end {let group=ph_color_group(w,i);let id=(group-ph_contact(w,0))/256;h_assert(id>previous && id<load64(w+232),"color range lost canonical manifold order");previous=id;h_assert(!load64(seen+id*8),"color range duplicated a manifold");store64(seen+id*8,1);h_assert((load64(group+216)&4294967295)==color,"manifold is in the wrong color range");let k=0;while k<2 {let body=load64(ph_order_contact(w,load64(group+200))+k*8);if load64(ph_body(w,body)+112) {h_assert(!load64(writers+body*8),"same-color dynamic body write conflict");store64(writers+body*8,1);}k=k+1;}visited=visited+1;i=i+1;}
        color=color+1;
    }
    h_assert(visited==load64(w+232) && end==visited,"color ranges omitted a manifold");h_assert(load64(ph_scratch(w)+16000)==0x12345678 && load64(ph_scratch(w)+16352)==0x3bf8e8e7,"color ranges overwrote diagnostic/options scratch");
    // A dynamic star with 65 static neighbors must retain serial fallback.
    i=0;while i<65 {let c=ph_contact(w,i);store64(c,0);store64(c+8,7+i);i=i+1;}store64(w+24,65);ph_order(w);h_assert(ph_color(w)==-1,"dense color overflow must retain serial solver fallback");ph_world_close(w);return 0;
}
fn main(argc,argv) {
    h_environment(argc,argv);
    let w=ph_world(16,24,256,4);
    let scene=0;
    while scene<15 {
        pt_scene(w,scene);
        let steps=500;
        if scene==0 || scene==5 {
            steps=50;
        }
        h_assert(ph_advance(w,steps),"physics advance failed");
        pt_validate(w,scene,steps);
        h_print(1,h_cat(h_int(scene)," pass\n"));
        scene=scene+1;
    }
    pt_geometry(w);
    pt_color_ranges();
    pt_scene(w,6);
    ph_advance(w,50);
    let held=load64(ph_body(w,2)+24);
    store64(ph_joint(w,0)+16,0);
    ph_advance(w,10);
    h_assert(ph_lt(load64(ph_body(w,2)+24),held) && ph_lt(load64(ph_body(w,2)+80),0),"released weld falls under gravity");
    ph_world_init(w,16,24,256,4);
    pt_box(w,1,0,0,100,50,30,20);
    store64(w+144,0x7fc00000);
    h_assert(!ph_advance(w,1) && load64(w+192)==2 && !load64(w+176),"nonfinite state stops CPU world");
    // Overflow is explicit and never writes past the allocated contact arena.
    ph_world_close(w);
    w=ph_world(4,4,1,0);
    pt_box(w,0,0,0,-25,500,400,25);
    pt_box(w,1,0,0,19,50,30,20);
    h_assert(!ph_advance(w,1) && load64(w+192)==1 && load64(w+24)==1,"bounded contact overflow");
    ph_world_close(w);
    h_print(1,"portable rigid-body checks pass\n");
    return 0;
}
