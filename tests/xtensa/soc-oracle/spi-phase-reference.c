#include "spi-metadata.h"
static void describe_phases(void){
 describe();v(SPI_USR_COMMAND);v(SPI_USR_ADDR);v(SPI_USR_DUMMY);v(SPI_USR_DUMMY_IDLE);v(SPI_USR_COMMAND_BITLEN_S);v(SPI_USR_COMMAND_BITLEN_V);v(SPI_USR_ADDR_BITLEN_S);v(SPI_USR_ADDR_BITLEN_V);v(SPI_USR_DUMMY_CYCLELEN_V);v(offsetof(spi_dev_t,user1));v(offsetof(spi_dev_t,user2));v(offsetof(spi_dev_t,addr));
#if S3
 v(0);v(SPI_CS_SETUP);v(SPI_CS_HOLD);v(SPI_CS_SETUP_TIME_S);v(SPI_CS_SETUP_TIME_V);v(SPI_CS_HOLD_TIME_S);v(SPI_CS_HOLD_TIME_V);
#else
 v(offsetof(spi_dev_t,slv_wr_status));v(SPI_CS_SETUP);v(SPI_CS_HOLD);v(SPI_SETUP_TIME_S);v(SPI_SETUP_TIME_V);v(SPI_HOLD_TIME_S);v(SPI_HOLD_TIME_V);
#endif
 /* Reset field values are those specified in the pinned spi_reg.h comments.
    C bitfields provide the independent offsets/packing, including reserved
    flash-only defaults and the S3 slave segment magic value. */
 spi_dev_t reset={0};reset.clock.clk_equ_sysclk=1;reset.clock.clkcnt_n=3;reset.clock.clkcnt_h=1;reset.clock.clkcnt_l=3;reset.user.usr_command=1;reset.user1.usr_addr_bitlen=23;reset.user1.usr_dummy_cyclelen=7;reset.user2.usr_command_bitlen=7;
#if S3
 reset.ctrl.wp_pol=1;reset.ctrl.hold_pol=1;reset.ctrl.d_pol=1;reset.ctrl.q_pol=1;reset.user.cs_setup=1;reset.user.cs_hold=1;reset.user1.cs_hold_time=1;reset.user1.mst_wfull_err_end_en=1;reset.user2.mst_rempty_err_end_en=1;reset.misc.cs1_dis=1;reset.misc.cs2_dis=1;reset.misc.cs3_dis=1;reset.misc.cs4_dis=1;reset.misc.cs5_dis=1;reset.slave.dma_seg_magic_value=10;
#else
 reset.ctrl.fcs_crc_en=1;reset.ctrl.fastrd_mode=1;reset.ctrl.resandres=1;reset.ctrl.wp=1;reset.ctrl2.setup_time=1;reset.ctrl2.hold_time=1;reset.user.ck_i_edge=1;reset.pin.cs1_dis=1;reset.pin.cs2_dis=1;/* Rev3 silicon reset probe reads reserved PIN[4:3]=3; named SDK defaults alone omit these bits. */reset.pin.reserved3=3;reset.slave.trans_inten=1;
#endif
 v(reset.ctrl.val);v(reset.user.val);v(reset.user1.val);v(reset.user2.val);v(reset.clock.val);
#if S3
 v(reset.misc.val);v(reset.slave.val);v(0);v(offsetof(spi_dev_t,clk_gate));
#else
 v(reset.pin.val);v(reset.slave.val);v(reset.ctrl2.val);v(0);
#endif
}
static uint32_t swap32(uint32_t x){return (x>>24)|((x>>8)&0xff00)|((x<<8)&0xff0000)|(x<<24);}

#if !S3
static uint64_t swap64(uint64_t x){return (uint64_t)swap32(x)<<32|swap32(x>>32);}

#endif
static unsigned bitpos(unsigned bit,unsigned lsb){return lsb?bit%8:7-bit%8;}
int main(void){
 describe_phases();uint64_t header[4]={UINT64_C(0x5350495048410001),nm,512,4480};
 if(fwrite(header,sizeof header,1,stdout)!=1 || fwrite(meta,8,nm,stdout)!=nm)return 1;
 for(unsigned bus=2;bus<=3;bus++)for(unsigned mode=0;mode<4;mode++)for(unsigned order=0;order<4;order++)for(unsigned scenario=0;scenario<16;scenario++){
  unsigned seed=bus*19+mode*7+order*11+scenario*13,txbits=0,rxbits=0,cmdlen=0,addrlen=0,dummy=0,half=1,dummyidle=0;
  switch(scenario){
  case 0:cmdlen=1;break;
  case 1:cmdlen=16;break;
  case 2:addrlen=S3?32:64;break;
  case 3:cmdlen=8;addrlen=24;dummy=8;rxbits=17;break;
  case 4:cmdlen=9;addrlen=15;txbits=63;break;
  case 5:cmdlen=3;addrlen=8;txbits=9;rxbits=17;break;
  case 6:cmdlen=16;addrlen=S3?32:64;txbits=256;rxbits=256;break;
  case 7:dummy=256;rxbits=512;break;
  case 8:cmdlen=4;dummy=1;txbits=8;break;
  case 9:cmdlen=2;addrlen=7;txbits=31;rxbits=31;half=0;break;
  case 10:txbits=65;rxbits=40;half=0;break;
  case 11:cmdlen=16;addrlen=S3?32:64;break;
  case 12:dummy=256;dummyidle=1;break;
  case 13:txbits=1;rxbits=1;break;
  case 14:cmdlen=8;addrlen=32;dummy=1;rxbits=256;break;
  case 15:cmdlen=1;addrlen=1;txbits=511;break;
  }
  if(S3 && txbits && rxbits)rxbits=txbits;
  unsigned txlsb=order&1,rxlsb=order>>1,txhigh=txbits && txbits<=256 && (seed&1),rxhigh=rxbits && rxbits<=256 && (seed&2);
  unsigned setup=half?(scenario%4):0,hold=(scenario+mode)%4,pre=1+seed%3,n=4+seed%5,h=1+seed%(n-1),ratio=S3 && (seed&1)?2:1;
  uint16_t command=(uint16_t)(seed*257)^0x96a5;uint64_t address=UINT64_C(0x96a5c371e24b5d0f)^((uint64_t)seed*UINT64_C(0x01030507090b0d0f));
  spi_dev_t hw={0};hw.ctrl.wr_bit_order=txlsb;hw.ctrl.rd_bit_order=rxlsb;hw.user.doutdin=!half;hw.user.usr_command=cmdlen!=0;hw.user.usr_addr=addrlen!=0;hw.user.usr_dummy=dummy!=0;hw.user.usr_dummy_idle=dummyidle;hw.user.usr_mosi=txbits!=0;hw.user.usr_miso=rxbits!=0;hw.user.usr_mosi_highpart=txhigh!=0;hw.user.usr_miso_highpart=rxhigh!=0;hw.user.ck_out_edge=(mode&1)^(mode>>1);hw.user.cs_setup=setup!=0;hw.user.cs_hold=hold!=0;
  if(cmdlen){hw.user2.usr_command_bitlen=cmdlen-1;hw.user2.usr_command_value=txlsb?command:swap32((uint32_t)command<<(32-cmdlen));}
  if(addrlen){hw.user1.usr_addr_bitlen=addrlen-1;
#if S3
   hw.addr=txlsb?swap32(address):(uint32_t)address<<(32-addrlen);
#else
   if(txlsb){uint64_t swapped=swap64(address);hw.addr=swapped>>32;hw.slv_wr_status=swapped;}
   else if(addrlen>32){hw.addr=address>>(addrlen-32);hw.slv_wr_status=address<<(64-addrlen);}else{hw.addr=address<<(32-addrlen);}
#endif
  }
  if(dummy)hw.user1.usr_dummy_cyclelen=dummy-1;
  hw.clock.clkdiv_pre=pre-1;hw.clock.clkcnt_n=n-1;hw.clock.clkcnt_h=h-1;hw.clock.clkcnt_l=n-1;
  uint64_t f[32]={bus,mode,txlsb,rxlsb,txbits,rxbits,cmdlen,addrlen,dummy,half,txhigh!=0,rxhigh!=0,hw.user2.usr_command_value,hw.addr,0,hw.user.val,hw.user1.val,hw.user2.val,hw.clock.val,0,hw.ctrl.val,0,ratio==2?3:7,0,setup,hold,pre*h*ratio,pre*(n-h)*ratio,scenario,dummyidle,0,0};
#if S3
  hw.user1.cs_setup_time=setup?setup-1:0;hw.user1.cs_hold_time=hold;hw.misc.val=62|((mode>>1)<<29);f[16]=hw.user1.val;f[19]=hw.misc.val;
#else
  hw.ctrl2.setup_time=setup?setup-1:0;hw.ctrl2.hold_time=hold;hw.pin.val=6|((mode>>1)<<29);f[14]=hw.slv_wr_status;f[19]=hw.pin.val;f[21]=hw.ctrl2.val;
#endif
  unsigned prefix=cmdlen+addrlen+dummy,data=half?txbits+rxbits:(txbits>rxbits?txbits:rxbits),cycles=prefix+data;f[23]=cycles;
  /* Original rev3 event-marker capture: CS and engine DONE have distinct
     delays. CTRL1's reset five gives six DONE periods; raw low byte52 gives
     one, independently of command phase enable or USER.CS_HOLD. */
  f[30]=S3?hold:((hw.user2.usr_command_value&255)==0x52?1:6);
  f[31]=hold<f[30]?hold:f[30];
  uint8_t tx[64],rx[64],incoming[64],edges[4096]={0};
  for(unsigned i=0;i<64;i++){tx[i]=(i*37+seed)^0x96;incoming[i]=(i*53+seed*3)^0x69;}
  for(unsigned i=0;i<64;i++)rx[i]=tx[(i+(rxhigh?32:0))%64];
  if(!S3)memset(rx,0,(rxbits+7)/8); /* Original rev3 byte-padding capture, not a vendor-default assumption. */
  for(unsigned i=0;i<rxbits;i++){unsigned shift=bitpos(i,rxlsb),mask=1u<<shift;rx[i/8]=(rx[i/8]&~mask)|(incoming[i/8]&mask);}
  for(unsigned cycle=0;cycle<cycles;cycle++){
   unsigned valid=0,mosi=0,read_start=prefix+(half?txbits:0);int data_index=(int)cycle-prefix,receive=(int)cycle-read_start;int in_dummy=cycle>=cmdlen+addrlen && cycle<prefix;
   /* Expected wire bits are taken directly from the logical command/address,
      independently of the HAL-compatible register packing above. */
   if(cycle<cmdlen){valid=1;mosi=(command>>(txlsb?cycle:cmdlen-1-cycle))&1;}
   else if(cycle<cmdlen+addrlen){unsigned b=cycle-cmdlen;valid=1;mosi=(address>>(txlsb?b:addrlen-1-b))&1;}
   else if(data_index>=0 && (unsigned)data_index<txbits){valid=1;unsigned b=data_index;mosi=(tx[(txhigh?32:0)+b/8]>>bitpos(b,txlsb))&1;}
   for(unsigned trail=0;trail<2;trail++){
    unsigned selected=trail==(mode&1),capture=selected && receive>=0 && (unsigned)receive<rxbits;
    unsigned miso=(seed+cycle*13+trail*7)&1;
    if(receive>=0 && (unsigned)receive<rxbits){unsigned b=receive;unsigned want=(incoming[b/8]>>bitpos(b,rxlsb))&1;miso=selected?want:!want;}
    unsigned clk=(mode>>1)^!trail;if(in_dummy && dummyidle)clk=mode>>1;
    edges[cycle*2+trail]=clk|(mosi<<1)|(capture<<2)|(valid<<3)|(miso<<4);
   }
  }
  if(fwrite(f,sizeof f,1,stdout)!=1 || fwrite(tx,64,1,stdout)!=1 || fwrite(rx,64,1,stdout)!=1 || fwrite(edges,4096,1,stdout)!=1)return 1;
 }
 return 0;
}
