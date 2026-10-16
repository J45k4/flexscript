/* Independent host oracle, built with unmodified official ESP-IDF v5.5.1
 * headers. These declarations and C bitfields are never firmware code. */
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include "spi_struct.h"
#include "i2c_struct.h"
#include "spi_reg.h"
#include "i2c_reg.h"
#include "rtc_io_reg.h"
#include "gpio_sig_map.h"
#define __ASSEMBLER__
#include "dport_reg.h"
int main(void) {
 spi_dev_t spi={0};i2c_dev_t i2c={0};
 uint64_t v[160]={REG_SPI_BASE(2),REG_SPI_BASE(3),offsetof(spi_dev_t,clock),offsetof(spi_dev_t,user),offsetof(spi_dev_t,mosi_dlen),offsetof(spi_dev_t,miso_dlen),offsetof(spi_dev_t,pin),offsetof(spi_dev_t,slave),offsetof(spi_dev_t,data_buf),SPI_USR,SPI_TRANS_DONE,DPORT_SPI2_CLK_EN,DPORT_SPI3_CLK_EN,REG_I2C_BASE(0),REG_I2C_BASE(1),offsetof(i2c_dev_t,ctr),offsetof(i2c_dev_t,status_reg),offsetof(i2c_dev_t,timeout),offsetof(i2c_dev_t,fifo_conf),offsetof(i2c_dev_t,fifo_data),offsetof(i2c_dev_t,int_raw),offsetof(i2c_dev_t,int_clr),offsetof(i2c_dev_t,int_ena),offsetof(i2c_dev_t,sda_hold),offsetof(i2c_dev_t,sda_sample),offsetof(i2c_dev_t,scl_high_period),offsetof(i2c_dev_t,scl_start_hold),offsetof(i2c_dev_t,scl_rstart_setup),offsetof(i2c_dev_t,scl_stop_setup),offsetof(i2c_dev_t,scl_stop_hold),offsetof(i2c_dev_t,scl_filter_cfg),offsetof(i2c_dev_t,sda_filter_cfg),offsetof(i2c_dev_t,command),I2C_TX_FIFO_RST|I2C_RX_FIFO_RST,I2C_TRANS_START,I2C_ARBITRATION_LOST_INT_RAW,I2C_ACK_ERR_INT_RAW,I2C_TIME_OUT_INT_RAW,I2C_TRANS_COMPLETE_INT_RAW,DPORT_I2C_EXT0_CLK_EN,DPORT_I2C_EXT1_CLK_EN,HSPICLK_OUT_IDX,HSPID_OUT_IDX,HSPIQ_IN_IDX,VSPICLK_OUT_IDX,VSPID_OUT_IDX,VSPIQ_IN_IDX,I2CEXT0_SCL_OUT_IDX,I2CEXT0_SDA_OUT_IDX,I2CEXT1_SCL_OUT_IDX,I2CEXT1_SDA_OUT_IDX};
 for(unsigned mode=0;mode<4;mode++){spi.user.val=0;spi.user.doutdin=1;spi.user.ck_out_edge=(mode&1)^(mode>>1);v[51+mode]=spi.user.val;spi.pin.val=0;spi.pin.cs0_dis=spi.pin.cs1_dis=spi.pin.cs2_dis=1;spi.pin.ck_idle_edge=mode>>1;v[55+mode]=spi.pin.val;}
 i2c.ctr.ms_mode=i2c.ctr.clk_en=i2c.ctr.sda_force_out=i2c.ctr.scl_force_out=1;v[59]=i2c.ctr.val;
 i2c.command[0].op_code=0;v[60]=i2c.command[0].val;i2c.command[0].op_code=1;i2c.command[0].byte_num=3;i2c.command[0].ack_en=1;v[61]=i2c.command[0].val;
 i2c.command[0].val=0;i2c.command[0].op_code=2;i2c.command[0].byte_num=2;v[62]=i2c.command[0].val;i2c.command[0].byte_num=1;i2c.command[0].ack_val=1;v[63]=i2c.command[0].val;
 i2c.command[0].val=0;i2c.command[0].op_code=3;v[64]=i2c.command[0].val;i2c.command[0].op_code=4;v[65]=i2c.command[0].val;
 i2c.command[0].val=0;i2c.command[0].ack_en=1;v[66]=i2c.command[0].val;i2c.status_reg.rx_fifo_cnt=63;v[67]=i2c.status_reg.val;i2c.command[0].val=0;i2c.command[0].done=1;v[68]=i2c.command[0].val;
 v[69]=I2C_DATA_APB_REG(0);v[70]=I2C_DATA_APB_REG(1);
 v[71]=0;v[72]=RTC_IO_TOUCH_PAD1_REG;v[73]=RTC_IO_TOUCH_PAD1_RUE_M;v[74]=RTC_IO_TOUCH_PAD1_RDE_M;
 v[75]=2;v[76]=RTC_IO_TOUCH_PAD2_REG;v[77]=RTC_IO_TOUCH_PAD2_RUE_M;v[78]=RTC_IO_TOUCH_PAD2_RDE_M;
 v[79]=4;v[80]=RTC_IO_TOUCH_PAD0_REG;v[81]=RTC_IO_TOUCH_PAD0_RUE_M;v[82]=RTC_IO_TOUCH_PAD0_RDE_M;
 v[83]=12;v[84]=RTC_IO_TOUCH_PAD5_REG;v[85]=RTC_IO_TOUCH_PAD5_RUE_M;v[86]=RTC_IO_TOUCH_PAD5_RDE_M;
 v[87]=13;v[88]=RTC_IO_TOUCH_PAD4_REG;v[89]=RTC_IO_TOUCH_PAD4_RUE_M;v[90]=RTC_IO_TOUCH_PAD4_RDE_M;
 v[91]=14;v[92]=RTC_IO_TOUCH_PAD6_REG;v[93]=RTC_IO_TOUCH_PAD6_RUE_M;v[94]=RTC_IO_TOUCH_PAD6_RDE_M;
 v[95]=15;v[96]=RTC_IO_TOUCH_PAD3_REG;v[97]=RTC_IO_TOUCH_PAD3_RUE_M;v[98]=RTC_IO_TOUCH_PAD3_RDE_M;
 v[99]=25;v[100]=RTC_IO_PAD_DAC1_REG;v[101]=RTC_IO_PDAC1_RUE_M;v[102]=RTC_IO_PDAC1_RDE_M;
 v[103]=26;v[104]=RTC_IO_PAD_DAC2_REG;v[105]=RTC_IO_PDAC2_RUE_M;v[106]=RTC_IO_PDAC2_RDE_M;
 v[107]=27;v[108]=RTC_IO_TOUCH_PAD7_REG;v[109]=RTC_IO_TOUCH_PAD7_RUE_M;v[110]=RTC_IO_TOUCH_PAD7_RDE_M;
 v[111]=32;v[112]=RTC_IO_XTAL_32K_PAD_REG;v[113]=RTC_IO_X32P_RUE_M;v[114]=RTC_IO_X32P_RDE_M;
 v[115]=33;v[116]=RTC_IO_XTAL_32K_PAD_REG;v[117]=RTC_IO_X32N_RUE_M;v[118]=RTC_IO_X32N_RDE_M;
 v[119]=RTC_IO_ADC_PAD_REG;v[120]=RTC_IO_SENSOR_PADS_REG;
 uint64_t header[2]={UINT64_C(0x4255535245470004),121};
 return fwrite(header,sizeof header,1,stdout)!=1 || fwrite(v,8,121,stdout)!=121;
}
