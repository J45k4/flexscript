// Greedy coloring prevents two concurrent contacts from writing one dynamic
// body. Static/kinematic bodies are read-only and may be shared by a color.
// More than 64 colors requests the existing serial solver on the device.
import "layout.flex";
// Scratch is reused only after narrow phase, during contact solving. The
// prefix ranges and packed permutation preserve canonical order within a color.
fn ph_color_begin(w,color) {return load64(ph_scratch(w)+14848+color*8);}
fn ph_color_end(w,color) {return load64(ph_scratch(w)+15360+color*8);}
fn ph_color_group(w,index) {return ph_contact(w,load64(ph_contact(w,index)+216)>>32);}
fn ph_color(w) {
    store64(w+232,0);
    let colors=0;let clear=0;while clear<64 {store64(ph_scratch(w)+15360+clear*8,0);clear=clear+1;}
    let i=0;
    while i<load64(w+8) {
        store64(ph_body(w,i)+400,0);
        i=i+1;
    }
    i=0;
    let groups=0;
    while i<load64(w+24) {
        let c=ph_order_contact(w,i);
        let a=ph_body(w,load64(c));
        let b=ph_body(w,load64(c+8));
        let used=0;
        if load64(a+112) {
            used=load64(a+400);
        }
        if load64(b+112) {
            used=used|load64(b+400);
        }
        let color=0;
        while color<64 && ((used>>color)&1) {
            color=color+1;
        }
        if color==64 {
            return -1;
        }
        let start=i;
        i=i+1;
        while i<load64(w+24) && load64(ph_order_contact(w,i))==load64(c) && load64(ph_order_contact(w,i)+8)==load64(c+8) {
            i=i+1;
        }
        let group=ph_contact(w,groups);
        store64(group+200,start);
        store64(group+208,i);
        store64(group+216,color);let counter=ph_scratch(w)+15360+color*8;store64(counter,load64(counter)+1);
        groups=groups+1;
        let bit=1<<color;
        if load64(a+112) {
            store64(a+400,load64(a+400)|bit);
        }
        if load64(b+112) {
            store64(b+400,load64(b+400)|bit);
        }
        if color>=colors {
            colors=color+1;
        }
    }
    store64(w+232,groups);
    let color=0;let first=0;
    while color<colors {let cursor=ph_scratch(w)+15360+color*8;let count=load64(cursor);store64(ph_scratch(w)+14848+color*8,first);store64(cursor,first);first=first+count;color=color+1;}
    i=0;
    while i<groups {color=load64(ph_contact(w,i)+216)&4294967295;let cursor=ph_scratch(w)+15360+color*8;let slot=ph_contact(w,load64(cursor))+216;store64(slot,(load64(slot)&4294967295)|(i<<32));store64(cursor,load64(cursor)+1);i=i+1;}
    return colors;
}
fn ph_order_contact(w,i) {
    return ph_contact(w,load64(ph_contact(w,i)+192));
}
fn ph_order_less(w,ai,bi) {
    let a=ph_contact(w,ai);
    let b=ph_contact(w,bi);
    let k=0;
    while k<2 {
        let x=load64(a+k*8);
        let y=load64(b+k*8);
        if x!=y {
            return x<y;
        }
        k=k+1;
    }
    k=2;
    while k<9 {
        let x=load64(a+k*8);
        let y=load64(b+k*8);
        if ph_lt(x,y) {
            return 1;
        }
        if ph_lt(y,x) {
            return 0;
        }
        k=k+1;
    }
    return 0;
}
fn ph_order_swap(w,a,b) {
    let pa=ph_contact(w,a)+192;
    let pb=ph_contact(w,b)+192;
    let value=load64(pa);
    store64(pa,load64(pb));
    store64(pb,value);
    return 0;
}
fn ph_order_sift(w,root,count) {
    while root*2+1<count {
        let child=root*2+1;
        if child+1<count && ph_order_less(w,load64(ph_contact(w,child)+192),load64(ph_contact(w,child+1)+192)) {
            child=child+1;
        }
        if !ph_order_less(w,load64(ph_contact(w,root)+192),load64(ph_contact(w,child)+192)) {
            return 0;
        }
        ph_order_swap(w,root,child);
        root=child;
    }
    return 0;
}
// Sort an index permutation rather than copying contact records. Canonical
// contact order makes coloring independent of GPU atomic reservation order.
fn ph_order(w) {
    let count=load64(w+24);
    let i=0;
    while i<count {
        store64(ph_contact(w,i)+192,i);
        i=i+1;
    }
    i=count/2-1;
    while i>=0 {
        ph_order_sift(w,i,count);
        i=i-1;
    }
    i=count-1;
    while i>0 {
        ph_order_swap(w,0,i);
        ph_order_sift(w,0,i);
        i=i-1;
    }
    return 0;
}

// Parallel canonical index sorting for one 64-lane group. Invalid padding is
// represented by -1, greater than every valid contact. Arenas whose capacity
// cannot hold the next power of two retain the serial heap sort.
fn ph_order_index_less(w,a,b) {
    if a<0 {return 0;}if b<0 {return 1;}return ph_order_less(w,a,b);
}
fn ph_order_group(w,lane) {
    let count=load64(w+24);let padded=1;while padded<count {padded=padded*2;}
    if padded>load64(w+56) {if !lane {ph_order(w);}gpu_barrier();return 0;}
    let i=lane;while i<padded {let value=i;if i>=count {value=-1;}store64(ph_contact(w,i)+192,value);i=i+64;}gpu_barrier();
    let size=2;
    while size<=padded {
        let distance=size>>1;
        while distance {
            i=lane;
            while i<padded {
                let other=i^distance;
                if other>i {
                    let a=load64(ph_contact(w,i)+192);let b=load64(ph_contact(w,other)+192);let swap=0;
                    if !(i&size) {swap=ph_order_index_less(w,b,a);}else {swap=ph_order_index_less(w,a,b);}
                    if swap {store64(ph_contact(w,i)+192,b);store64(ph_contact(w,other)+192,a);}
                }
                i=i+64;
            }
            gpu_barrier();distance=distance>>1;
        }
        size=size*2;
    }
    return 1;
}

fn ph_order_shared(w,lane) {
    return ph_order_shared_width(w,lane,64);
}

fn ph_order_shared_width(w,lane,width) {
    let count=load64(w+24);
    let padded=1;
    while padded<count {
        padded=padded*2;
    }
    let i=lane;
    while i<padded {
        let value=i;
        if i>=count {
            value=-1;
        }
        gpu_shared_store64(i*8,value);
        i=i+width;
    }
    gpu_shared_barrier();
    let size=2;
    while size<=padded {
        let distance=size>>1;
        while distance {
            i=lane;
            while i<padded {
                let other=i^distance;
                if other>i {
                    let a=gpu_shared_load64(i*8);
                    let b=gpu_shared_load64(other*8);
                    let swap=0;
                    if !(i&size) {
                        swap=ph_order_index_less(w,b,a);
                    }
                    else {
                        swap=ph_order_index_less(w,a,b);
                    }
                    if swap {
                        gpu_shared_store64(i*8,b);
                        gpu_shared_store64(other*8,a);
                    }
                }
                i=i+width;
            }
            gpu_shared_barrier();
            distance=distance>>1;
        }
        size=size*2;
    }
    i=lane;
    while i<count {
        store64(ph_contact(w,i)+192,gpu_shared_load64(i*8));
        i=i+width;
    }
    gpu_barrier();
    return 1;
}

fn ph_color_shared_serial(w,pairs,flags,masks,counts,cursors) {
    store64(w+232,0);
    let colors=0;
    let i=0;
    let groups=0;
    while i<load64(w+24) {
        let pair=gpu_shared_load64(pairs+gpu_shared_load64(i*8)*8);
        let a=pair>>32;
        let b=pair&4294967295;
        let used=0;
        if gpu_shared_load64(flags+a*8) {
            used=gpu_shared_load64(masks+a*8);
        }
        if gpu_shared_load64(flags+b*8) {
            used=used|gpu_shared_load64(masks+b*8);
        }
        let color=0;
        while color<64 && ((used>>color)&1) {
            color=color+1;
        }
        if color==64 {
            return -1;
        }
        let start=i;
        i=i+1;
        while i<load64(w+24) && gpu_shared_load64(pairs+gpu_shared_load64(i*8)*8)==pair {
            i=i+1;
        }
        let group=ph_contact(w,groups);
        store64(group+200,start);
        store64(group+208,i);
        store64(group+216,color);
        groups=groups+1;
        gpu_shared_store64(counts+color*8,gpu_shared_load64(counts+color*8)+1);
        let bit=1<<color;
        if gpu_shared_load64(flags+a*8) {
            gpu_shared_store64(masks+a*8,gpu_shared_load64(masks+a*8)|bit);
        }
        if gpu_shared_load64(flags+b*8) {
            gpu_shared_store64(masks+b*8,gpu_shared_load64(masks+b*8)|bit);
        }
        if color>=colors {
            colors=color+1;
        }
    }
    store64(w+232,groups);
    let color=0;
    let first=0;
    while color<colors {
        let count=gpu_shared_load64(counts+color*8);
        store64(ph_scratch(w)+14848+color*8,first);
        gpu_shared_store64(cursors+color*8,first);
        first=first+count;
        store64(ph_scratch(w)+15360+color*8,first);
        color=color+1;
    }
    i=0;
    while i<groups {
        color=load64(ph_contact(w,i)+216)&4294967295;
        let slot=gpu_shared_load64(cursors+color*8);
        let word=ph_contact(w,slot)+216;
        store64(word,(load64(word)&4294967295)|(i<<32));
        gpu_shared_store64(cursors+color*8,slot+1);
        i=i+1;
    }
    return colors;
}

fn ph_color_shared(w,lane,width,padded) {
    let pairs=padded*8;
    let flags=pairs+load64(w+24)*8;
    let masks=flags+load64(w+8)*8;
    let counts=masks+load64(w+8)*8;
    let cursors=counts+512;
    let i=lane;
    while i<load64(w+24) {
        let c=ph_contact(w,i);
        gpu_shared_store64(pairs+i*8,(load64(c)<<32)|load64(c+8));
        i=i+width;
    }
    i=lane;
    while i<load64(w+8) {
        gpu_shared_store64(flags+i*8,load64(ph_body(w,i)+112)!=0);
        gpu_shared_store64(masks+i*8,0);
        i=i+width;
    }
    if lane<64 {
        gpu_shared_store64(counts+lane*8,0);
        store64(ph_scratch(w)+15360+lane*8,0);
    }
    gpu_shared_barrier();
    if !lane {
        store64(w+224,ph_color_shared_serial(w,pairs,flags,masks,counts,cursors));
    }
    gpu_shared_barrier();
    i=lane;
    while i<load64(w+8) {
        store64(ph_body(w,i)+400,gpu_shared_load64(masks+i*8));
        i=i+width;
    }
    gpu_barrier();
    return load64(w+224);
}

fn ph_order_group_width(w,lane,width) {
    let count=load64(w+24);
    let padded=1;
    while padded<count {
        padded=padded*2;
    }
    if padded>load64(w+56) {
        if !lane {
            ph_order(w);
        }
        gpu_barrier();
        return 0;
    }
    let i=lane;
    while i<padded {
        let value=i;
        if i>=count {
            value=-1;
        }
        store64(ph_contact(w,i)+192,value);
        i=i+width;
    }
    gpu_barrier();
    let size=2;
    while size<=padded {
        let distance=size>>1;
        while distance {
            i=lane;
            while i<padded {
                let other=i^distance;
                if other>i {
                    let a=load64(ph_contact(w,i)+192);
                    let b=load64(ph_contact(w,other)+192);
                    let swap=0;
                    if !(i&size) {
                        swap=ph_order_index_less(w,b,a);
                    }
                    else {
                        swap=ph_order_index_less(w,a,b);
                    }
                    if swap {
                        store64(ph_contact(w,i)+192,b);
                        store64(ph_contact(w,other)+192,a);
                    }
                }
                i=i+width;
            }
            gpu_barrier();
            distance=distance>>1;
        }
        size=size*2;
    }
    return 1;
}
