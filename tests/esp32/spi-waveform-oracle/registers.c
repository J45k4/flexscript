#include "spi-metadata.h"
#include <stdlib.h>
static uint32_t swap32(uint32_t x){return (x>>24)|((x>>8)&0xff00)|((x<<8)&0xff0000)|(x<<24);}
static uint64_t swap64(uint64_t x){return (uint64_t)swap32(x)<<32|swap32(x>>32);}
int main(void){
 uint64_t input[3];if(fread(input,sizeof input,1,stdin)!=1 || input[0]!=UINT64_C(0x5357524547000001) || input[1]<1 || input[1]>4096 || (input[2]!=24 && input[2]!=28 && input[2]!=32))return 1;
 describe();v(IO_MUX_GPIO25_REG);uint64_t header[4]={UINT64_C(0x53574d4f444c0001),nm,input[1],30};if(fwrite(header,sizeof header,1,stdout)!=1 || fwrite(meta,8,nm,stdout)!=nm)return 2;
 for(unsigned i=0;i<input[1];i++){
  uint64_t m[24];if(fread(m,sizeof m,1,stdin)!=1 || m[0]!=i || m[1]<2 || m[1]>3 || m[2]>3 || m[3]>1 || (input[2]==24 && m[5]<1) || m[5]>16 || m[6]<1 || m[6]>64 || m[7]<1 || m[7]>64 || m[8]>256 || m[9]>1 || m[14]<1 || m[14]>8192 || m[15]<2 || m[15]>64 || m[16]<1 || m[16]>=m[15] || m[17]>16 || m[18]>15)return 3;
  spi_dev_t hw={0};hw.ctrl.wr_bit_order=m[3];hw.ctrl2.setup_time=m[17]?m[17]-1:0;hw.ctrl2.hold_time=m[18];hw.clock.clkdiv_pre=m[14]-1;hw.clock.clkcnt_n=m[15]-1;hw.clock.clkcnt_h=m[16]-1;hw.clock.clkcnt_l=m[15]-1;
  hw.user.usr_command=m[5]!=0;hw.user.usr_addr=1;hw.user.usr_dummy=m[8]!=0;hw.user.usr_dummy_idle=m[9];hw.user.usr_mosi=1;hw.user.ck_out_edge=(m[2]&1)^(m[2]>>1);hw.user.cs_setup=m[17]!=0;hw.user.cs_hold=(m[19]&SPI_CS_HOLD)!=0;
  hw.user1.usr_addr_bitlen=m[6]-1;hw.user1.usr_dummy_cyclelen=m[8]?m[8]-1:0;if(m[5]){hw.user2.usr_command_bitlen=m[5]-1;hw.user2.usr_command_value=m[3]?m[10]:swap32((uint32_t)m[10]<<(32-m[5]));}
  if(input[2]>=28){
   uint64_t raw[4];if(fread(raw,sizeof raw,1,stdin)!=1 || raw[0]!=m[0] || raw[2]!=m[19] || raw[3]!=m[20] || (raw[1]&~UINT64_C(0xf000ffff)))return 6;
   hw.user2.usr_command_bitlen=(raw[1]>>28)&15;hw.user2.usr_command_value=raw[1]&65535;
   if(hw.user2.val!=raw[1] || (m[5] && (uint64_t)(hw.user2.usr_command_bitlen+1)!=m[5]))return 7;
  }
  hw.ctrl1.cs_hold_delay=5;hw.ctrl1.cs_hold_delay_res=4095;
  hw.ext0.t_pp_ena=1;hw.ext0.t_pp_shift=10;hw.ext0.t_pp_time=80;
  hw.ext1.t_erase_ena=1;hw.ext1.t_erase_shift=15;
  if(input[2]==32){
   uint64_t delay[4];if(fread(delay,sizeof delay,1,stdin)!=1 || delay[0]!=m[0] || delay[1]>UINT32_MAX || delay[2]>UINT32_MAX || delay[3]>UINT32_MAX)return 8;
   hw.ctrl1.cs_hold_delay=delay[1]>>28;hw.ctrl1.cs_hold_delay_res=(delay[1]>>16)&4095;
   hw.ext0.t_pp_ena=delay[2]>>31;hw.ext0.t_pp_shift=(delay[2]>>16)&15;hw.ext0.t_pp_time=delay[2]&4095;
   hw.ext1.t_erase_ena=delay[3]>>31;hw.ext1.t_erase_shift=(delay[3]>>16)&15;hw.ext1.t_erase_time=delay[3]&4095;
   if(hw.ctrl1.val!=delay[1] || hw.ext0.val!=delay[2] || hw.ext1.val!=delay[3])return 9;
  }
  uint64_t address=m[11];if(m[3]){address=swap64(address);hw.addr=address>>32;hw.slv_wr_status=address;}else if(m[6]>32){hw.addr=address>>(m[6]-32);hw.slv_wr_status=address<<(64-m[6]);}else{hw.addr=address<<(32-m[6]);}
  hw.mosi_dlen.usr_mosi_dbitlen=m[7]-1;hw.pin.cs1_dis=1;hw.pin.cs2_dis=1;hw.pin.ck_idle_edge=m[2]>>1;
  if(hw.user.val!=m[19] || hw.ctrl2.val!=m[20])return 4;
  uint64_t o[30]={m[0],m[1],m[2],m[3],m[5],m[6],m[7],m[8],m[9],m[14],m[15],m[16],m[17],m[18],m[10],hw.addr,hw.slv_wr_status,hw.ctrl.val,hw.ctrl2.val,hw.clock.val,hw.user.val,hw.user1.val,hw.user2.val,hw.pin.val,m[12],m[13],hw.mosi_dlen.val,hw.ctrl1.val,hw.ext0.val,hw.ext1.val};
  if(fwrite(o,sizeof o,1,stdout)!=1)return 5;
 }
 return fgetc(stdin)!=EOF;
}
