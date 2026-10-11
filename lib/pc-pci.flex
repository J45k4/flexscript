// PCI configuration mechanism #1, optionally exposing one minimal host bridge.
// 272-byte state: address latch, bridge enable, 256-byte configuration image.
// The caller validates the I/O buffer's count * width bytes before dispatch.
// Returns 1 for handled ports and 0 for an unsupported port/width.
fn pc_pci_init(s,bridge) {
    let i=0;while i<272 {store8(s+i,0);i=i+1;}store64(s+8,bridge);
    if bridge {store64(s+16,0x12378086);store64(s+24,0x06000002);}return 0;
}
fn pc_pci_io(state,port,width,out,data,count) {
    if width!=1 && width!=2 && width!=4 {return 0;}
    if !((port==0xcf8 && width==4) || (port==0xcfb && width==1) || (port>=0xcfc && port+width<=0xd00)) {return 0;}
    let i=0;while i<count {
        let p=data+i*width;
        let address=load64(state);let present=load64(state+8) && (address&0xffffff00)==0x80000000;
        let offset=(address&252)+port-0xcfc;
        if out {
            if port==0xcf8 {let value=0;let j=0;while j<4 {value=value|(load8(p+j)<<(j*8));j=j+1;}store64(state,value&0xfffffffc);}
            else if port==0xcfb {store64(state,(load64(state)&0xffffff)|(load8(p)<<24));}
            else if present {let j=0;while j<width {let at=offset+j;if at==4 {store8(state+16+at,load8(p+j)&7);}else if at==5 {store8(state+16+at,0);}j=j+1;}}
        }else {
            let value=-1;if port==0xcf8 {value=load64(state);}
            else if port==0xcfb {value=load64(state)>>24;}
            else if present {value=0;let j=0;while j<width {value=value|(load8(state+16+offset+j)<<(j*8));j=j+1;}}
            let j=0;while j<width {store8(p+j,value>>(j*8));j=j+1;}
        }i=i+1;
    }return 1;
}
