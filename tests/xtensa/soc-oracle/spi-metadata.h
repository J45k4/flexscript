#include <stdint.h>
#include <stdio.h>
#include <stddef.h>
#include <string.h>
#include "spi_struct.h"
#include "spi_reg.h"
#include "gpio_sig_map.h"
#include "gpio_reg.h"
#include "io_mux_reg.h"
#include "interrupts.h"
#if S3
#include "system_reg.h"
#else
#include "dport_reg.h"
#endif
static uint64_t meta[128];static unsigned nm;
static void v(uint64_t x){meta[nm++]=x;}
static void describe(void){
 v(S3?9:0);v(DR_REG_SPI2_BASE);v(DR_REG_SPI3_BASE);
#if S3
 v(SYSTEM_PERIP_CLK_EN0_REG);v(SYSTEM_PERIP_RST_EN0_REG);v(SYSTEM_SPI2_CLK_EN);v(SYSTEM_SPI3_CLK_EN);
#else
 v(DPORT_PERIP_CLK_EN_REG);v(DPORT_PERIP_RST_EN_REG);v(DPORT_SPI2_CLK_EN);v(DPORT_SPI3_CLK_EN);
#endif
 v(offsetof(spi_dev_t,user));v(offsetof(spi_dev_t,clock));
#if S3
 v(offsetof(spi_dev_t,misc));
#else
 v(offsetof(spi_dev_t,pin));
#endif
 v(offsetof(spi_dev_t,data_buf));v(offsetof(spi_dev_t,slave));
#if S3
 v(offsetof(spi_dev_t,ms_dlen));v(offsetof(spi_dev_t,ms_dlen));v(SPI_USR);v(SPI_UPDATE);v(SPI_TRANS_DONE_INT_RAW);v(offsetof(spi_dev_t,dma_int_ena));v(offsetof(spi_dev_t,dma_int_raw));v(offsetof(spi_dev_t,dma_int_clr));
#else
 v(offsetof(spi_dev_t,mosi_dlen));v(offsetof(spi_dev_t,miso_dlen));v(SPI_USR);v(0);v(SPI_TRANS_DONE);v(offsetof(spi_dev_t,slave));v(offsetof(spi_dev_t,slave));v(offsetof(spi_dev_t,slave));
#endif
 v(ETS_SPI2_INTR_SOURCE);v(ETS_SPI3_INTR_SOURCE);
#if S3
 v(FSPICLK_OUT_IDX);v(FSPID_OUT_IDX);v(FSPIQ_IN_IDX);v(FSPICS0_OUT_IDX);v(SPI3_CLK_OUT_IDX);v(SPI3_D_OUT_IDX);v(SPI3_Q_IN_IDX);v(SPI3_CS0_OUT_IDX);
#else
 v(HSPICLK_OUT_IDX);v(HSPID_OUT_IDX);v(HSPIQ_IN_IDX);v(HSPICS0_OUT_IDX);v(VSPICLK_OUT_IDX);v(VSPID_OUT_IDX);v(VSPIQ_IN_IDX);v(VSPICS0_OUT_IDX);
#endif
 v(1u<<SPI_WR_BIT_ORDER_S);v(1u<<SPI_RD_BIT_ORDER_S);v(SPI_CK_OUT_EDGE);v(SPI_CK_IDLE_EDGE);v(SPI_USR_MOSI);v(SPI_USR_MISO);v(SPI_DOUTDIN);v(SPI_USR_MOSI_HIGHPART);v(SPI_USR_MISO_HIGHPART);v(SPI_CLKDIV_PRE_V);v(SPI_CLK_EQU_SYSCLK);v(GPIO_FUNC0_OUT_SEL_CFG_REG);v(GPIO_FUNC0_IN_SEL_CFG_REG);v(IO_MUX_GPIO18_REG);v(IO_MUX_GPIO21_REG);v(IO_MUX_GPIO19_REG);v(IO_MUX_GPIO4_REG);v((S3?1:2)<<12|FUN_IE);v(GPIO_ENABLE_W1TS_REG);v(GPIO_ENABLE_W1TC_REG);
#if S3
 v(DR_REG_INTERRUPT_BASE);v(63);
#else
 v(DPORT_PRO_MAC_INTR_MAP_REG);v(7);
#endif
 v(DR_REG_GPIO_BASE);v(SPI_SLAVE_MODE);
}
