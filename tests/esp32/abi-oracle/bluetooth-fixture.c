/* Independent fake VHCI controller for ABI/ownership tests only. */
typedef unsigned char u8;
typedef unsigned int u32;
u32 test_vhci_available=1;
u32 test_vhci_count=0;
u32 test_vhci_size=0;
u32 test_vhci_pointer=0;
struct {u32 before;u8 bytes[1032];u32 after;} test_vhci_record={0x13572468,{0},0x24681357};
u32 API_vhci_host_check_send_available(void){return test_vhci_available;}
void API_vhci_host_send_packet(u8 *p,u32 n){
    test_vhci_pointer=(u32)p;test_vhci_size=n;test_vhci_count++;
    for(u32 i=0;i<n && i<1032;i++)test_vhci_record.bytes[i]=p[i];
}
