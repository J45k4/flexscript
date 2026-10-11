import "../../lib/pc-pci.flex";
fn expect(value) {if !value {syscall(60,1,0,0,0,0,0);}return 0;}
fn main() {
    let state=alloc(272);let data=alloc(16);pc_pci_init(state,0);
    expect(pc_pci_io(state,0xcf8,4,0,data,1) && !load64(data));
    store64(data,0x80001003);expect(pc_pci_io(state,0xcf8,4,1,data,1));
    store64(data,0);expect(pc_pci_io(state,0xcf8,4,0,data,1) && load64(data)==0x80001000);
    expect(pc_pci_io(state,0xcfc,2,0,data,2) && (load64(data)&0xffffffff)==0xffffffff);
    expect(pc_pci_io(state,0xcff,1,1,data,1) && load64(state)==0x80001000);
    store64(data,0);expect(!pc_pci_io(state,0xcfd,4,0,data,1) && !load64(data));
    expect(!pc_pci_io(state,0xcf8,2,0,data,1));expect(!pc_pci_io(state,0xcfc,3,0,data,1));expect(!pc_pci_io(state,0x3f8,1,0,data,1));
    store8(data,1);expect(pc_pci_io(state,0xcfb,1,1,data,1) && load64(state)==0x01001000);
    store8(data,0);expect(pc_pci_io(state,0xcfb,1,0,data,1) && load8(data)==1);
    pc_pci_init(state,1);store64(data,0x80000000);expect(pc_pci_io(state,0xcf8,4,1,data,1));expect(pc_pci_io(state,0xcfc,4,0,data,1) && (load64(data)&0xffffffff)==0x12378086);
    store64(data,-1);expect(pc_pci_io(state,0xcfc,4,1,data,1));expect(pc_pci_io(state,0xcfc,4,0,data,1) && (load64(data)&0xffffffff)==0x12378086);
    store64(data,0x80000008);pc_pci_io(state,0xcf8,4,1,data,1);expect(pc_pci_io(state,0xcfe,2,0,data,1) && (load64(data)&65535)==0x600);
    store64(data,0x80000004);pc_pci_io(state,0xcf8,4,1,data,1);store64(data,-1);pc_pci_io(state,0xcfc,4,1,data,1);expect(pc_pci_io(state,0xcfc,4,0,data,1) && (load64(data)&0xffffffff)==7);
    store64(data,0x80010000);pc_pci_io(state,0xcf8,4,1,data,1);expect(pc_pci_io(state,0xcfc,4,0,data,1) && (load64(data)&0xffffffff)==0xffffffff);
    store64(data,0);pc_pci_io(state,0xcf8,4,1,data,1);expect(pc_pci_io(state,0xcfc,4,0,data,1) && (load64(data)&0xffffffff)==0xffffffff);
    syscall(11,state,272,0,0,0,0);syscall(11,data,16,0,0,0,0);return 0;
}
