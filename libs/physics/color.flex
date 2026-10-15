// Greedy coloring prevents two concurrent contacts from writing one dynamic
// body. Static/kinematic bodies are read-only and may be shared by a color.
// More than 64 colors requests the existing serial solver on the device.
import "layout.flex";
fn ph_color(w) {
    store64(w+232,0);
    let colors=0;
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
        store64(group+216,color);
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
