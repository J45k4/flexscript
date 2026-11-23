// Exact millimetre lengths at six decimal places.
// Lengths here can exceed the geometry engine's coordinate range.
fn pcd_length(value,limit) {
    if j_kind(value)==1 {
        let n=j_value(value);
        if n<0 || n>limit {return -1;}
        return n*1000000;
    }
    if j_kind(value)!=6 {return -1;}
    let raw=j_value(value);let i=0;let n=0;
    while load8(raw+i)>=48 && load8(raw+i)<=57 {
        n=n*10+load8(raw+i)-48;i=i+1;
        if n>limit || i>7 {return -1;}
    }
    if !i || load8(raw+i)!=46 {return -1;}
    i=i+1;n=n*1000000;let factor=100000;
    while load8(raw+i)>=48 && load8(raw+i)<=57 {
        let digit=load8(raw+i)-48;
        if !factor && digit {return -1;}
        n=n+digit*factor;factor=factor/10;i=i+1;
    }
    if load8(raw+i) || n>limit*1000000 {return -1;}
    return n;
}
