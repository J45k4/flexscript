/* Independent minimal HCI controller/ABI oracle; never production firmware. */
typedef unsigned char u8;
typedef unsigned int u32;
void *memset(void *pointer,int value,u32 size){volatile u8 *out=pointer;for(u32 i=0;i<size;i++)out[i]=(u8)value;return pointer;}
typedef u32 (*callback8)(u32,u32,u32,u32,u32,u32,u32,u32);
u32 test_ble_receive=0,test_ble_ready=0,test_ble_count=0,test_ble_bad=0;
u32 test_ble_shared=0,test_ble_flow=1,test_ble_complete=1;
u32 test_ble_ops[128];
u8 test_ble_params[128][32];
u32 test_ble_sizes[128];
u32 test_ble_acl_count=0,test_ble_acl_size=0;
u8 test_ble_acl[1032];
u32 test_ble_acl_log_size=0;
u8 test_ble_acl_log[4096];
static void receive(u8 *p,u32 n){if(test_ble_receive)((callback8)test_ble_receive)((u32)p,n,0,0,0,0,0,0);}
static void ready(void){if(test_ble_ready)((callback8)test_ble_ready)(0,0,0,0,0,0,0,0);}
u32 API_vhci_host_check_send_available(void){return 1;}
void API_vhci_host_send_packet(u8 *p,u32 n){
    if(n<4){test_ble_bad++;ready();return;}
    if(p[0]==2){
        test_ble_acl_count++;test_ble_acl_size=n;
        u32 at=test_ble_acl_log_size;
        if(at+2+n<=sizeof(test_ble_acl_log)){
            test_ble_acl_log[at++]=(u8)n;test_ble_acl_log[at++]=(u8)(n>>8);
            for(u32 i=0;i<n;i++)test_ble_acl_log[at++]=p[i];
            test_ble_acl_log_size=at;
        }else test_ble_bad++;
        for(u32 i=0;i<n && i<1032;i++)test_ble_acl[i]=p[i];
        if(test_ble_complete){u8 done[8]={4,0x13,5,1,p[1],(u8)(p[2]&15),1,0};receive(done,8);}
        ready();return;
    }
    u32 op=p[1]|((u32)p[2]<<8),slot=test_ble_count++;
    if(slot>=128){test_ble_bad++;ready();return;}
    test_ble_ops[slot]=op;test_ble_sizes[slot]=n-4;
    for(u32 i=0;i<n-4 && i<32;i++)test_ble_params[slot][i]=p[4+i];
    if(p[0]!=1 || p[3]+4!=n)test_ble_bad++;
    if(op==0x0c35){if(n!=9 || p[4]!=1)test_ble_bad++;ready();return;}
    u8 reply[32]={4,14,4,1,(u8)op,(u8)(op>>8),0};u32 size=7;
    switch(op){
    case 0x0c03: if(n!=4)test_ble_bad++;break;
    case 0x0c01:
        if(n!=12 || p[4]!=0x90 || p[5]!=0xe0 || p[6]!=4 || p[7]!=2 || p[8] || p[9]!=0x80 || p[10] || p[11]!=0x20)test_ble_bad++;break;
    case 0x2001:
        if(n!=12 || p[4]!=0x7d || p[5]!=2)test_ble_bad++;break;
    case 0x2002:
        reply[2]=7;size=10;reply[7]=test_ble_shared?0:27;reply[8]=0;reply[9]=test_ble_shared?0:2;break;
    case 0x1005:
        reply[2]=11;size=14;reply[7]=64;reply[8]=0;reply[9]=0;reply[10]=3;reply[11]=0;break;
    case 0x1009:
        reply[2]=10;size=13;for(u32 i=0;i<6;i++)reply[7+i]=i+1;break;
    case 0x0c33:
        if(n!=11 || p[4] || p[5]!=4 || p[6] || p[7]!=4 || p[8] || p[9] || p[10])test_ble_bad++;
        if(!test_ble_flow)reply[6]=1;break;
    case 0x0c31:
        if(n!=5 || p[4]!=1 || !test_ble_flow)test_ble_bad++;break;
    case 0x2006:
        if(n!=19 || p[8] || p[9] || p[10] || p[17]!=7 || p[18])test_ble_bad++;break;
    case 0x2008:case 0x2009:if(n!=36 || p[4]>31)test_ble_bad++;break;
    case 0x200a:if(n!=5 || p[4]>1)test_ble_bad++;break;
    case 0x200d:
        if(n!=29 || p[4]!=160 || p[5] || p[6]!=80 || p[7] || p[8] || p[16])test_ble_bad++;
        reply[1]=15;reply[3]=0;reply[4]=1;reply[5]=(u8)op;reply[6]=(u8)(op>>8);break;
    case 0x0406:case 0x2013:
        if(n!=(op==0x0406?7:18))test_ble_bad++;
        reply[1]=15;reply[3]=0;reply[4]=1;reply[5]=(u8)op;reply[6]=(u8)(op>>8);break;
    case 0x200e:break;
    case 0x201b:if(n!=6)test_ble_bad++;break;
    case 0x2020:if(n!=18)test_ble_bad++;break;
    case 0x2021:if(n!=7 || p[6]!=0x3b)test_ble_bad++;break;
    default:reply[6]=1;break;
    }
    receive(reply,size);ready();
}
