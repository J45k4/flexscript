// Register contact arithmetic and an optional bounded GPU working set.
import "solver.flex";

fn ph_impulse_angular(rx,ry,rz,jx,jy,jz,ix,iy,iz) {
    let x=ph_sub(ph_mul(ry,jz),ph_mul(rz,jy));
    let y=ph_sub(ph_mul(rz,jx),ph_mul(rx,jz));
    let z=ph_sub(ph_mul(rx,jy),ph_mul(ry,jx));
    return ph_dot(ix,iy,iz,x,y,z);
}

fn ph_impulse_pair(v,w,j,angular,sign,mass) {
    if !mass {
        return v|(w<<32);
    }
    return ph_add(v,ph_mul(j,ph_mul(sign,mass)))|(ph_add(w,ph_mul(angular,sign))<<32);
}

fn ph_contact_slot(offset) {
    if offset<16 {
        return offset>>3;
    }
    if offset<64 {
        return 2+((offset-40)>>3);
    }
    if offset<184 {
        return 5+((offset-72)>>3);
    }
    if offset==184 {
        return 19;
    }
    if offset<248 {
        return 21+((offset-224)>>3);
    }
    return 24;
}

fn ph_local_u32(base,slot) {
    let value=gpu_shared_load64(base+(slot>>1)*8);
    if slot&1 {
        return (value>>32)&4294967295;
    }
    return value&4294967295;
}

fn ph_local_put32(base,slot,value) {
    let address=base+(slot>>1)*8;
    let word=gpu_shared_load64(address);
    if slot&1 {
        gpu_shared_store64(address,(word&4294967295)|(value<<32));
    }
    else {
        gpu_shared_store64(address,(word&0xffffffff00000000)|value);
    }
    return value;
}

fn ph_contact_read(c,offset) {
    if c>=0 {
        return load64(c+offset);
    }
    let base=c&0x7fffffffffffffff;
    let slot=ph_contact_slot(offset);
    let value=ph_local_u32(base,slot);
    if offset==184 || offset==248 {
        value=value|(ph_local_u32(base,slot+1)<<32);
    }
    return value;
}

fn ph_contact_write(c,offset,value) {
    if c>=0 {
        return store64(c+offset,value);
    }
    return ph_local_put32(c&0x7fffffffffffffff,ph_contact_slot(offset),value);
}

fn ph_contact_solve_register_core(w,c,t,a,b) {
    let am=load64(a+112);
    let avx=load64(a+64);
    let avy=load64(a+72);
    let avz=load64(a+80);
    let awx=load64(a+88);
    let awy=load64(a+96);
    let awz=load64(a+104);
    let arx=ph_contact_read(c,104);
    let ary=ph_contact_read(c,112);
    let arz=ph_contact_read(c,120);
    let bm=load64(b+112);
    let bvx=load64(b+64);
    let bvy=load64(b+72);
    let bvz=load64(b+80);
    let bwx=load64(b+88);
    let bwy=load64(b+96);
    let bwz=load64(b+104);
    let brx=ph_contact_read(c,128);
    let bry=ph_contact_read(c,136);
    let brz=ph_contact_read(c,144);
    let nx=ph_contact_read(c,40);
    let ny=ph_contact_read(c,48);
    let nz=ph_contact_read(c,56);
    let vx=ph_sub(ph_add(bvx,ph_sub(ph_mul(bwy,brz),ph_mul(bwz,bry))),ph_add(avx,ph_sub(ph_mul(awy,arz),ph_mul(awz,ary))));
    let vy=ph_sub(ph_add(bvy,ph_sub(ph_mul(bwz,brx),ph_mul(bwx,brz))),ph_add(avy,ph_sub(ph_mul(awz,arx),ph_mul(awx,arz))));
    let vz=ph_sub(ph_add(bvz,ph_sub(ph_mul(bwx,bry),ph_mul(bwy,brx))),ph_add(avz,ph_sub(ph_mul(awx,ary),ph_mul(awy,arx))));
    let vn=ph_dot(vx,vy,vz,nx,ny,nz);
    let lambda=ph_mul(ph_sub(ph_contact_read(c,176),vn),ph_contact_read(c,152));
    let old=ph_contact_read(c,72);
    let total=ph_max(0,ph_add(old,lambda));
    ph_contact_write(c,72,total);
    let change=ph_sub(total,old);
    let jx=ph_mul(nx,change);
    let jy=ph_mul(ny,change);
    let jz=ph_mul(nz,change);
    let pair=0;
    pair=ph_impulse_pair(avx,awx,jx,ph_impulse_angular(arx,ary,arz,jx,jy,jz,load64(a+328),load64(a+352),load64(a+376)),0xbf800000,am);
    avx=pair&4294967295;
    awx=(pair>>32)&4294967295;
    pair=ph_impulse_pair(avy,awy,jy,ph_impulse_angular(arx,ary,arz,jx,jy,jz,load64(a+336),load64(a+360),load64(a+384)),0xbf800000,am);
    avy=pair&4294967295;
    awy=(pair>>32)&4294967295;
    pair=ph_impulse_pair(avz,awz,jz,ph_impulse_angular(arx,ary,arz,jx,jy,jz,load64(a+344),load64(a+368),load64(a+392)),0xbf800000,am);
    avz=pair&4294967295;
    awz=(pair>>32)&4294967295;
    pair=ph_impulse_pair(bvx,bwx,jx,ph_impulse_angular(brx,bry,brz,jx,jy,jz,load64(b+328),load64(b+352),load64(b+376)),1065353216,bm);
    bvx=pair&4294967295;
    bwx=(pair>>32)&4294967295;
    pair=ph_impulse_pair(bvy,bwy,jy,ph_impulse_angular(brx,bry,brz,jx,jy,jz,load64(b+336),load64(b+360),load64(b+384)),1065353216,bm);
    bvy=pair&4294967295;
    bwy=(pair>>32)&4294967295;
    pair=ph_impulse_pair(bvz,bwz,jz,ph_impulse_angular(brx,bry,brz,jx,jy,jz,load64(b+344),load64(b+368),load64(b+392)),1065353216,bm);
    bvz=pair&4294967295;
    bwz=(pair>>32)&4294967295;
    vx=ph_sub(ph_add(bvx,ph_sub(ph_mul(bwy,brz),ph_mul(bwz,bry))),ph_add(avx,ph_sub(ph_mul(awy,arz),ph_mul(awz,ary))));
    vy=ph_sub(ph_add(bvy,ph_sub(ph_mul(bwz,brx),ph_mul(bwx,brz))),ph_add(avy,ph_sub(ph_mul(awz,arx),ph_mul(awx,arz))));
    vz=ph_sub(ph_add(bvz,ph_sub(ph_mul(bwx,bry),ph_mul(bwy,brx))),ph_add(avz,ph_sub(ph_mul(awx,ary),ph_mul(awy,arx))));
    vn=ph_dot(vx,vy,vz,nx,ny,nz);
    let normal=ph_neg(vn);
    vx=ph_add(vx,ph_mul(nx,normal));
    vy=ph_add(vy,ph_mul(ny,normal));
    vz=ph_add(vz,ph_mul(nz,normal));
    let speed2=ph_dot(vx,vy,vz,vx,vy,vz);
    if ph_lt(0x2b8cbccc,speed2) {
        let ux=ph_contact_read(c,224);
        let uy=ph_contact_read(c,232);
        let uz=ph_contact_read(c,240);
        let tx=ph_sub(ph_mul(ny,uz),ph_mul(nz,uy));
        let ty=ph_sub(ph_mul(nz,ux),ph_mul(nx,uz));
        let tz=ph_sub(ph_mul(nx,uy),ph_mul(ny,ux));
        let tangent_x=ph_dot(vx,vy,vz,ux,uy,uz);
        let tangent_y=ph_dot(vx,vy,vz,tx,ty,tz);
        let xx=ph_contact_read(c,184)&4294967295;
        let yy=(ph_contact_read(c,184)>>32)&4294967295;
        let xy=ph_contact_read(c,248)&4294967295;
        let inverse=(ph_contact_read(c,248)>>32)&4294967295;
        let dx=ph_mul(ph_sub(ph_mul(xy,tangent_y),ph_mul(yy,tangent_x)),inverse);
        let dy=ph_mul(ph_sub(ph_mul(xy,tangent_x),ph_mul(xx,tangent_y)),inverse);
        let ox=ph_contact_read(c,80);
        let oy=ph_contact_read(c,88);
        let oz=ph_contact_read(c,96);
        let cx=ph_add(ph_add(ox,ph_mul(ux,dx)),ph_mul(tx,dy));
        let cy=ph_add(ph_add(oy,ph_mul(uy,dx)),ph_mul(ty,dy));
        let cz=ph_add(ph_add(oz,ph_mul(uz,dx)),ph_mul(tz,dy));
        let length2=ph_dot(cx,cy,cz,cx,cy,cz);
        let limit=ph_mul(total,load64(w+152));
        if ph_lt(ph_mul(limit,limit),length2) {
            let scale=ph_mul(limit,ph_rsqrt(length2));
            cx=ph_mul(cx,scale);
            cy=ph_mul(cy,scale);
            cz=ph_mul(cz,scale);
        }
        let ex=ph_sub(cx,ox);
        let ey=ph_sub(cy,oy);
        let ez=ph_sub(cz,oz);
        dx=ph_dot(ex,ey,ez,ux,uy,uz);
        dy=ph_dot(ex,ey,ez,tx,ty,tz);
        let curvature=ph_add(ph_add(ph_mul(xx,ph_mul(dx,dx)),ph_mul(yy,ph_mul(dy,dy))),ph_mul(ph_add(xy,xy),ph_mul(dx,dy)));
        let energy=ph_add(ph_add(ph_mul(tangent_x,dx),ph_mul(tangent_y,dy)),ph_mul(1056964608,curvature));
        if ph_lt(0,energy) {
            let gradient=ph_neg(ph_rcp(ph_add(xx,yy)));
            cx=ph_add(ox,ph_mul(vx,gradient));
            cy=ph_add(oy,ph_mul(vy,gradient));
            cz=ph_add(oz,ph_mul(vz,gradient));
            length2=ph_dot(cx,cy,cz,cx,cy,cz);
            if ph_lt(ph_mul(limit,limit),length2) {
                let scale=ph_mul(limit,ph_rsqrt(length2));
                cx=ph_mul(cx,scale);
                cy=ph_mul(cy,scale);
                cz=ph_mul(cz,scale);
            }
        }
        jx=ph_sub(cx,ox);
        jy=ph_sub(cy,oy);
        jz=ph_sub(cz,oz);
        ph_contact_write(c,80,cx);
        ph_contact_write(c,88,cy);
        ph_contact_write(c,96,cz);
        pair=ph_impulse_pair(avx,awx,jx,ph_impulse_angular(arx,ary,arz,jx,jy,jz,load64(a+328),load64(a+352),load64(a+376)),0xbf800000,am);
        avx=pair&4294967295;
        awx=(pair>>32)&4294967295;
        pair=ph_impulse_pair(avy,awy,jy,ph_impulse_angular(arx,ary,arz,jx,jy,jz,load64(a+336),load64(a+360),load64(a+384)),0xbf800000,am);
        avy=pair&4294967295;
        awy=(pair>>32)&4294967295;
        pair=ph_impulse_pair(avz,awz,jz,ph_impulse_angular(arx,ary,arz,jx,jy,jz,load64(a+344),load64(a+368),load64(a+392)),0xbf800000,am);
        avz=pair&4294967295;
        awz=(pair>>32)&4294967295;
        pair=ph_impulse_pair(bvx,bwx,jx,ph_impulse_angular(brx,bry,brz,jx,jy,jz,load64(b+328),load64(b+352),load64(b+376)),1065353216,bm);
        bvx=pair&4294967295;
        bwx=(pair>>32)&4294967295;
        pair=ph_impulse_pair(bvy,bwy,jy,ph_impulse_angular(brx,bry,brz,jx,jy,jz,load64(b+336),load64(b+360),load64(b+384)),1065353216,bm);
        bvy=pair&4294967295;
        bwy=(pair>>32)&4294967295;
        pair=ph_impulse_pair(bvz,bwz,jz,ph_impulse_angular(brx,bry,brz,jx,jy,jz,load64(b+344),load64(b+368),load64(b+392)),1065353216,bm);
        bvz=pair&4294967295;
        bwz=(pair>>32)&4294967295;
    }
    let apx=load64(a+192);
    let apy=load64(a+200);
    let apz=load64(a+208);
    let aqx=load64(a+216);
    let aqy=load64(a+224);
    let aqz=load64(a+232);
    let bpx=load64(b+192);
    let bpy=load64(b+200);
    let bpz=load64(b+208);
    let bqx=load64(b+216);
    let bqy=load64(b+224);
    let bqz=load64(b+232);
    vx=ph_sub(ph_add(bpx,ph_sub(ph_mul(bqy,brz),ph_mul(bqz,bry))),ph_add(apx,ph_sub(ph_mul(aqy,arz),ph_mul(aqz,ary))));
    vy=ph_sub(ph_add(bpy,ph_sub(ph_mul(bqz,brx),ph_mul(bqx,brz))),ph_add(apy,ph_sub(ph_mul(aqz,arx),ph_mul(aqx,arz))));
    vz=ph_sub(ph_add(bpz,ph_sub(ph_mul(bqx,bry),ph_mul(bqy,brx))),ph_add(apz,ph_sub(ph_mul(aqx,ary),ph_mul(aqy,arx))));
    let pv=ph_dot(vx,vy,vz,nx,ny,nz);
    let pl=ph_mul(ph_sub(ph_contact_read(c,168),pv),ph_contact_read(c,152));
    let pp=ph_contact_read(c,160);
    let pt=ph_max(0,ph_add(pp,pl));
    ph_contact_write(c,160,pt);
    let pd=ph_sub(pt,pp);
    jx=ph_mul(nx,pd);
    jy=ph_mul(ny,pd);
    jz=ph_mul(nz,pd);
    pair=ph_impulse_pair(apx,aqx,jx,ph_impulse_angular(arx,ary,arz,jx,jy,jz,load64(a+328),load64(a+352),load64(a+376)),0xbf800000,am);
    apx=pair&4294967295;
    aqx=(pair>>32)&4294967295;
    pair=ph_impulse_pair(apy,aqy,jy,ph_impulse_angular(arx,ary,arz,jx,jy,jz,load64(a+336),load64(a+360),load64(a+384)),0xbf800000,am);
    apy=pair&4294967295;
    aqy=(pair>>32)&4294967295;
    pair=ph_impulse_pair(apz,aqz,jz,ph_impulse_angular(arx,ary,arz,jx,jy,jz,load64(a+344),load64(a+368),load64(a+392)),0xbf800000,am);
    apz=pair&4294967295;
    aqz=(pair>>32)&4294967295;
    pair=ph_impulse_pair(bpx,bqx,jx,ph_impulse_angular(brx,bry,brz,jx,jy,jz,load64(b+328),load64(b+352),load64(b+376)),1065353216,bm);
    bpx=pair&4294967295;
    bqx=(pair>>32)&4294967295;
    pair=ph_impulse_pair(bpy,bqy,jy,ph_impulse_angular(brx,bry,brz,jx,jy,jz,load64(b+336),load64(b+360),load64(b+384)),1065353216,bm);
    bpy=pair&4294967295;
    bqy=(pair>>32)&4294967295;
    pair=ph_impulse_pair(bpz,bqz,jz,ph_impulse_angular(brx,bry,brz,jx,jy,jz,load64(b+344),load64(b+368),load64(b+392)),1065353216,bm);
    bpz=pair&4294967295;
    bqz=(pair>>32)&4294967295;
    if am {
        store64(a+64,avx);
        store64(a+72,avy);
        store64(a+80,avz);
        store64(a+88,awx);
        store64(a+96,awy);
        store64(a+104,awz);
        store64(a+192,apx);
        store64(a+200,apy);
        store64(a+208,apz);
        store64(a+216,aqx);
        store64(a+224,aqy);
        store64(a+232,aqz);
    }
    if bm {
        store64(b+64,bvx);
        store64(b+72,bvy);
        store64(b+80,bvz);
        store64(b+88,bwx);
        store64(b+96,bwy);
        store64(b+104,bwz);
        store64(b+192,bpx);
        store64(b+200,bpy);
        store64(b+208,bpz);
        store64(b+216,bqx);
        store64(b+224,bqy);
        store64(b+232,bqz);
    }
    return 0;
}

fn ph_weld_prepare_at(w,joint,cache,t) {
    if !load64(joint+16) {
        return 0;
    }
    let a=ph_body(w,load64(joint));
    let b=ph_body(w,load64(joint+8));
    ph_rotate(cache,a+256,joint+24);
    ph_vadd(t+240,a+8,cache);
    ph_vsub(t+240,b+8,t+240);
    let gain=ph_div(load64(w+208),load64(w+120));
    let i=0;
    while i<3 {
        ph_vset(t+264,0,0,0);
        store64(t+264+i*8,1065353216);
        store64(cache+24+i*8,ph_neg(ph_mul(load64(t+240+i*8),gain)));
        store64(cache+48+i*8,ph_rcp(ph_add(ph_mass(a,cache,t+264,t),load64(b+112))));
        i=i+1;
    }
    ph_qmul(t+288,a+32,joint+48);
    i=0;
    while i<3 {
        store64(t+320+i*8,ph_neg(load64(t+288+i*8)));
        i=i+1;
    }
    store64(t+344,load64(t+312));
    ph_qmul(t+352,b+32,t+320);
    let sign=1073741824;
    if ph_lt(load64(t+376),0) {
        sign=0xc0000000;
    }
    i=0;
    while i<3 {
        store64(cache+72+i*8,ph_mul(ph_mul(load64(t+352+i*8),sign),gain));
        store64(cache+96+i*8,ph_rcp(ph_add(load64(a+328+(i*3+i)*8),load64(b+328+(i*3+i)*8))));
        i=i+1;
    }
    return 0;
}

fn ph_weld_solve_prepared(w,joint,cache,t) {
    if !load64(joint+16) {
        return 0;
    }
    let a=ph_body(w,load64(joint));
    let b=ph_body(w,load64(joint+8));
    ph_vcopy(t+192,cache);
    ph_vset(t+216,0,0,0);
    let i=0;
    while i<3 {
        ph_vset(t+264,0,0,0);
        store64(t+264+i*8,1065353216);
        ph_relative(t+96,a,b,t+192,t+216,t);
        let target=load64(cache+24+i*8);
        let lambda=ph_mul(ph_sub(target,load64(t+96+i*8)),load64(cache+48+i*8));
        ph_scale(t+120,t+264,lambda);
        ph_impulse(a,t+192,t+120,0xbf800000,t);
        ph_impulse(b,t+216,t+120,1065353216,t);
        i=i+1;
    }
    i=0;
    while i<3 {
        let error=load64(cache+72+i*8);
        let relative=ph_sub(load64(b+88+i*8),load64(a+88+i*8));
        let lambda=ph_mul(ph_neg(ph_add(error,relative)),load64(cache+96+i*8));
        ph_vset(t+120,0,0,0);
        store64(t+120+i*8,lambda);
        ph_angular_impulse(a,t+120,0xbf800000,t);
        ph_angular_impulse(b,t+120,1065353216,t);
        i=i+1;
    }
    return 0;
}

fn ph_contact_cache_begin(w,lane,base,groups,width) {
    let i=lane;
    while i<load64(w+24) {
        let c=ph_contact(w,i);
        let at=base+i*104;
        let k=0;
        // Each worker owns a complete cache record, including paired words.
        k=0;
        while k<13 {
            gpu_shared_store64(at+k*8,0);
            k=k+1;
        }
        let x=load64(c);
        let y=load64(c+8);
        gpu_shared_store64(at,x|(y<<32));
        k=0;
        while k<3 {
            let slot=2+k;
            ph_local_put32(at,slot,load64(c+40+k*8));
            k=k+1;
        }
        k=0;
        while k<14 {
            ph_local_put32(at,5+k,load64(c+72+k*8));
            k=k+1;
        }
        gpu_shared_store64(at+19/2*8,(gpu_shared_load64(at+19/2*8)&4294967295)|((load64(c+184)&4294967295)<<32));
        ph_local_put32(at,20,load64(c+184)>>32);
        k=0;
        while k<3 {
            ph_local_put32(at,21+k,load64(c+224+k*8));
            k=k+1;
        }
        gpu_shared_store64(at+96,load64(c+248));
        i=i+width;
    }
    i=lane;
    while i<load64(w+232) {
        let g=ph_color_group(w,i);
        gpu_shared_store64(groups+i*8,load64(g+200)|(load64(g+208)<<32));
        i=i+width;
    }
    gpu_barrier();
    return 0;
}

fn ph_group_solve_local(w,index,t,base,groups) {
    let range=gpu_shared_load64(groups+index*8);
    let k=range&4294967295;
    let end=range>>32;
    let first=0x8000000000000000|(base+gpu_shared_load64(k*8)*104);
    let a=ph_body(w,ph_contact_read(first,0));
    let b=ph_body(w,ph_contact_read(first,8));
    while k<end {
        let c=0x8000000000000000|(base+gpu_shared_load64(k*8)*104);
        ph_contact_solve_register_core(w,c,t,a,b);
        k=k+1;
    }
    return 0;
}

fn ph_contact_cache_end(w,lane,base,width) {
    gpu_barrier();
    let i=lane;
    while i<load64(w+24) {
        let c=ph_contact(w,i);
        let local=0x8000000000000000|(base+i*104);
        store64(c+72,ph_contact_read(local,72));
        store64(c+80,ph_contact_read(local,80));
        store64(c+88,ph_contact_read(local,88));
        store64(c+96,ph_contact_read(local,96));
        store64(c+160,ph_contact_read(local,160));
        i=i+width;
    }
    gpu_barrier();
    return 0;
}

fn ph_contact_solve_register_at(w,c,t) {
    return ph_contact_solve_register_core(w,c,t,ph_body(w,load64(c)),ph_body(w,load64(c+8)));
}

fn ph_group_solve_register(w,group,t) {
    let k=load64(group+200);
    while k<load64(group+208) {
        ph_contact_solve_register_at(w,ph_order_contact(w,k),t);
        k=k+1;
    }
    return 0;
}
