#!/usr/bin/env python3
"""Primary-header radio/PHY policy model. No CPU, calibration or RF proof."""
import argparse,hashlib,json,re,shutil,struct,subprocess
from pathlib import Path
C=r'''
#include <stdint.h>
#include <stdio.h>
#include "esp_bit_defs.h"
#include "soc/efuse_reg.h"
#ifdef C6
#include "soc/interrupt_matrix_reg.h"
#include "soc/lpperi_reg.h"
#include "soc/lp_aon_reg.h"
#include "modem/modem_syscon_reg.h"
#include "modem/modem_lpcon_reg.h"
#else
#include "soc/interrupt_core0_reg.h"
#include "soc/apb_ctrl_reg.h"
#include "soc/rtc_cntl_reg.h"
#endif
#define CONFIG_ESP32_PHY_MAX_TX_POWER 20
#define CONFIG_ESP_PHY_MAX_TX_POWER 20
#define limit(v,l,h) ((v)<(l)?(l):((v)>(h)?(h):(v)))
static const unsigned char init[128]={INIT_BYTES};
int main(void){uint64_t v[32]={0};
#ifdef C6
v[0]=0x40810000;v[1]=13;v[21]=DR_REG_INTMTX_BASE;v[2]=INTMTX_CORE0_INT_STATUS_REG_0_REG;v[3]=LPPERI_RNG_DATA_REG;v[4]=LP_AON_STORE1_REG;v[5]=MODEM_SYSCON_CLK_CONF1_REG;v[6]=MODEM_SYSCON_CLK_FE_APB_EN|MODEM_SYSCON_CLK_FE_CAL_160M_EN|MODEM_SYSCON_CLK_FE_160M_EN|MODEM_SYSCON_CLK_FE_80M_EN;v[7]=MODEM_LPCON_CLK_CONF_REG;v[8]=MODEM_LPCON_CLK_I2C_MST_EN;v[9]=MODEM_LPCON_I2C_MST_CLK_CONF_REG;v[10]=MODEM_LPCON_CLK_I2C_MST_SEL_160M;v[11]=MODEM_SYSCON_CLK_CONF_REG;v[12]=MODEM_SYSCON_CLK_MODEM_SEC_APB_EN;v[13]=0x601ff;
#else
v[0]=0x3fc90000;v[1]=5;v[21]=DR_REG_INTERRUPT_CORE0_BASE;v[2]=INTERRUPT_CORE0_INTR_STATUS_0_REG;v[3]=APB_CTRL_RND_DATA_REG;v[4]=RTC_CNTL_STORE1_REG;v[5]=APB_CTRL_WIFI_CLK_EN_REG;v[6]=0x78078f;v[14]=RTC_CNTL_DIG_ISO_REG;v[15]=RTC_CNTL_WIFI_FORCE_ISO|RTC_CNTL_BT_FORCE_ISO;v[16]=RTC_CNTL_DIG_PWC_REG;v[17]=RTC_CNTL_WIFI_FORCE_PD|RTC_CNTL_BT_FORCE_PD;v[18]=APB_CTRL_WIFI_RST_EN_REG;
#endif
v[19]=EFUSE_RD_MAC_SPI_SYS_0_REG;v[20]=EFUSE_RD_MAC_SPI_SYS_1_REG;return fwrite(v,sizeof v,1,stdout)!=1||fwrite(init,sizeof init,1,stdout)!=1;}
'''
F=r'''
global esp_radio_isr=0;global esp_radio_isr_arg=0;global esp_radio_irq_count=0;global seeded=0;global cfg=0;global regs=0;global writes=0;global checks=0;global ps=0x1888;global cycles=500;global last_read=0;global calibration=0;global wakes=0;global backups=0;global restores=0;global closes=0;global rx=0;
fn cv(i){return load64(cfg+i*8);}
fn check(ok){checks=checks+1;if !ok{h_print(2,h_cat3("radio platform check ",h_int(checks)," failed\n"));syscall(60,1,0,0,0,0,0);}return 0;}
fn esp32_state(){return cv(0);}
fn esp32_irq_save(){let old=ps;ps=ps&~8;return old;}
fn esp32_irq_restore(value){ps=value;return 0;}
fn esp32_cycles(){cycles=cycles+13;return cycles;}
fn esp32_load32(address){last_read=address;if address>=cv(0)&&address<cv(0)+229376{let n=0;let i=0;while i<4{n=n|(load8(address+i)<<(i*8));i=i+1;}return n;}let i=writes;while i{i=i-1;if load64(regs+i*16)==address{return load64(regs+i*16+8);}}return 0xa5a5a5a5;}
fn esp32_store32(address,value){if address>=cv(0)&&address<cv(0)+229376{let i=0;while i<4{store8(address+i,value>>(i*8));i=i+1;}return 0;}check(!(ps&8));check(writes<256);store64(regs+writes*16,address);store64(regs+writes*16+8,value&4294967295);writes=writes+1;return 0;}
fn esp32_external(name){if h_equal(name,"phy_init_param_set"){return 1;}if h_equal(name,"phy_bbpll_en_usb"){return 2;}if h_equal(name,"register_chipv7_phy"){return 3;}if h_equal(name,"phy_wakeup_init"){return 4;}if h_equal(name,"phy_dig_reg_backup"){return 5;}if h_equal(name,"phy_close_rf"){return 6;}if h_equal(name,"phy_xpd_tsens"){return 7;}check(h_equal(name,"phy_wifi_enable_set"));return 8;}
fn esp32_call32(function,a,b,c,d,e,f,g,h){if function==77{check(a==0x12345678&&!b&&!c&&!d&&!e&&!f&&!g&&!h&&!(ps&8));return 0;}check(function>0&&function<=8&&!(ps&8)&&!d&&!e&&!f&&!g&&!h);if function==1||function==2{check(a==1&&!b&&!c);return 0;}
 if function==3{check(a==esp_radio_phy_init_data&&b==esp_radio_phy_cal&&c==2&&!esp_radio_phy_refs);check((esp32_load32(cv(5))&cv(6))==cv(6));if cv(1)==13{check((esp32_load32(cv(11))&cv(12))==cv(12)&&(esp32_load32(cv(5))&cv(13))==cv(13));}let i=0;while i<128{check(load8(a+i)==load8(cfg+256+i));i=i+1;}i=0;while i<1904{check(!load8(b+i));store8(b+i,(i*37+19)&255);i=i+1;}calibration=calibration+1;return 17;}
 if function==4{check(!a&&!b&&!c&&esp_radio_phy_calibrated);check((esp32_load32(cv(5))&cv(6))==cv(6));wakes=wakes+1;return 0;}
 if function==5{check(cv(1)==5&&b==esp_radio_phy_backup&&!c);let i=0;while i<84{if a{store8(b+i,(i*23+5)&255);}else{check(load8(b+i)==((i*23+5)&255));}i=i+1;}if a{backups=backups+1;}else{restores=restores+1;}return 0;}
 if function==6{check(!a&&!b&&!c&&!esp_radio_phy_refs);closes=closes+1;return 0;}if function==7{check(!a&&!b&&!c);return 0;}check(!b&&!c&&(a==0||a==1));rx=a;return 0;
}
fn esp_irq_matrix(){return cv(21);}
fn seed(address,value){store64(regs+writes*16,address);store64(regs+writes*16+8,value);writes=writes+1;seeded=seeded+1;return 0;}
fn main(argc,argv){h_environment(argc,argv);cfg=h_read(load64(argv+8));regs=alloc(8192);rv_hal_state=cv(0);rv_hal_ram_top=cv(0)+229376;rv_hal_data_size=32768;check(rv_hal_chip==cv(1));check(syscall(9,cv(0),262144,3,1048610,-1,0)==cv(0));esp32_store32(cv(0)+20,cv(0)+180224);check(!esp_sdk_heap_init(esp_sdk_heap_min(),131072));let baseline=esp_sdk_heap_free();
 check(esp_radio_cb_slowclk_cal(0,0,0,0,0,0,0,0)==(0xa5a5a5a5>>7)&&last_read==cv(4));check(esp_radio_random_word()==0xa5a5a5a5&&last_read==cv(3));let before_cycles=cycles;esp_radio_random_word();check(cycles-before_cycles>=128);
 seed(cv(19),0x789abcde);seed(cv(20),0xbeef1234);let mac=cv(0)+256;let kind=0;while kind<3{let i=0;while i<8{store8(mac+i,165);i=i+1;}check(!esp_radio_cb_read_mac(mac+1,kind,0,0,0,0,0,0)&&load8(mac)==165&&load8(mac+7)==165);let expected=0x1234789abcde;expected=expected+kind;i=0;while i<6{check(load8(mac+1+i)==((expected>>(40-i*8))&255));i=i+1;}kind=kind+1;}check(esp_radio_cb_read_mac(0,0,0,0,0,0,0,0)==-1&&esp_radio_cb_read_mac(mac,3,0,0,0,0,0,0)==-1);
 check(esp_radio_hardware_init()==-16&&writes==seeded&&!esp_radio_hw_ready);esp_radio_owner=1;esp_adc_busy=1;check(esp_radio_hardware_init()==-16&&!esp_radio_hw_ready&&writes==seeded);esp_adc_busy=0;
 if cv(1)==5{check(!esp_radio_hardware_init()&&esp_radio_hw_ready&&ps==0x1888);check(esp32_load32(cv(14))==(0xa5a5a5a5&~cv(15)));check(esp32_load32(cv(16))==(0xa5a5a5a5&~cv(17)));check(esp32_load32(cv(5))==((0xa5a5a5a5&~0x1020)|0x00fb9fcf));}
 else{check(esp_radio_hardware_init()==-95&&writes==seeded&&!esp_radio_hw_ready);esp_radio_hw_ready=1;}
 let before_reset=writes;check(!esp_radio_cb_wifi_reset(0,0,0,0,0,0,0,0));if cv(1)==5{check(writes==before_reset+2&&esp32_load32(cv(18))==(0xa5a5a5a5&~4));}else{check(writes==before_reset);}check(!esp_radio_cb_wifi_clock_on(0,0,0,0,0,0,0,0)&&!esp_radio_cb_wifi_clock_off(0,0,0,0,0,0,0,0));
 let before=writes;check(esp_radio_hardware_init()==-16&&writes==before);esp_adc_busy=1;check(esp_radio_phy_enable()==-16&&writes==before&&esp_sdk_heap_free()==baseline);esp_adc_busy=0;esp32_store32(cv(0)+16,1);check(esp_radio_phy_enable()==-16&&writes==before);esp32_store32(cv(0)+16,0);
 let failure=0;let limit=2;if cv(1)==5{limit=3;}while failure<limit{let remaining=96;if failure==1{remaining=2000;}if failure==2{remaining=2160;}let held=esp_sdk_malloc(baseline-remaining);check(held>0);let free=esp_sdk_heap_free();check(esp_radio_phy_buffers_init()==-12&&!esp_radio_phy_cal&&!esp_radio_phy_init_data&&!esp_radio_phy_backup&&esp_sdk_heap_free()==free);check(!esp_sdk_free(held)&&esp_sdk_heap_free()==baseline);failure=failure+1;}
 let old_cal_conf1=esp32_load32(cv(5))&cv(13);check(!esp_radio_phy_enable()&&esp_radio_phy_refs==1&&esp_radio_phy_clock_refs==1&&esp_radio_phy_calibrated&&esp_radio_phy_result==17&&calibration==1&&ps==0x1888);check((esp32_load32(cv(5))&cv(6))==cv(6));if cv(1)==13{check((esp32_load32(cv(7))&cv(8))==cv(8)&&(esp32_load32(cv(9))&cv(10))==cv(10));check((esp32_load32(cv(11))&cv(12))==(0xa5a5a5a5&cv(12))&&(esp32_load32(cv(5))&cv(13))==old_cal_conf1);}
 check(!esp_radio_phy_enable()&&esp_radio_phy_refs==2&&esp_radio_phy_clock_refs==2&&calibration==1);check(esp_radio_phy_release_buffers()==-16&&esp_radio_hardware_deinit()==-16);check(!esp_radio_phy_disable()&&esp_radio_phy_refs==1&&!closes);check(!esp_radio_phy_disable()&&!esp_radio_phy_refs&&!esp_radio_phy_clock_refs&&closes==1);check(!(esp32_load32(cv(5))&cv(6)));
 check(!esp_radio_phy_enable()&&wakes==1&&calibration==1&&esp_radio_phy_refs==1);if cv(1)==5{check(backups==1&&restores==1&&!esp_radio_phy_backup_valid);}check(!esp_radio_cb_phy_on(0,0,0,0,0,0,0,0)&&rx==1&&esp_radio_phy_refs==2);check(!esp_radio_cb_phy_off(0,0,0,0,0,0,0,0)&&!rx&&esp_radio_phy_refs==1);check(!esp_radio_phy_disable()&&!esp_radio_phy_refs&&!esp_radio_phy_clock_refs&&closes==2);check(!esp_radio_phy_release_buffers()&&esp_sdk_heap_free()==baseline&&!esp_radio_phy_cal&&!esp_radio_phy_init_data&&!esp_radio_phy_backup);
 if cv(1)==5{seed(cv(5),esp32_load32(cv(5))^0x80000000);seed(cv(14),esp32_load32(cv(14))^1);seed(cv(16),esp32_load32(cv(16))^1);check(!esp_radio_hardware_deinit()&&!esp_radio_hw_ready&&ps==0x1888);check(esp32_load32(cv(5))==(0xa5a5a5a5^0x80000000)&&esp32_load32(cv(14))==(0xa5a5a5a5^1)&&esp32_load32(cv(16))==(0xa5a5a5a5^1));}check(esp_radio_irq_status()==cv(2));esp_radio_owner=1;esp_radio_isr=77;esp_radio_isr_arg=0x12345678;seed(esp_radio_route(0),1);seed(esp_radio_route(2),1);seed(cv(2),1);check(!esp_radio_irq(0)&&esp_radio_irq_count==1);check(!esp_radio_irq(2)&&esp_radio_irq_count==1);seed(cv(2),5);check(!esp_radio_irq(2)&&esp_radio_irq_count==2);check(!esp_radio_irq(1)&&esp_radio_irq_count==2);seed(cv(2),0);check(!esp_radio_irq(0)&&esp_radio_irq_count==2);seed(cv(2),1);seed(esp_radio_route(0),0);check(!esp_radio_irq(0)&&esp_radio_irq_count==2);seed(esp_radio_route(0),1);esp_radio_owner=0;check(!esp_radio_irq(0)&&esp_radio_irq_count==2);esp_radio_owner=1;esp_radio_isr=0;check(!esp_radio_irq(0)&&esp_radio_irq_count==2&&ps==0x1888);
 let out=alloc(16);store64(out,checks);store64(out+8,writes-seeded);return syscall(1,1,out,16,0,0,0)!=16;
}
'''
def main():
 p=argparse.ArgumentParser();p.add_argument('--compiler',required=True,type=Path);p.add_argument('--source-root',type=Path);p.add_argument('--reference',required=True,type=Path);p.add_argument('--work',required=True,type=Path);a=p.parse_args();root=(a.source_root or Path(__file__).resolve().parents[2]).resolve();ref=a.reference.resolve();w=a.work.resolve();w.mkdir(parents=True,exist_ok=True);cases=[]
 for chip in [3,6]:
  d=w/f'c{chip}';inc=d/'include';(inc/'soc').mkdir(parents=True,exist_ok=True);(inc/'modem').mkdir(exist_ok=True)
  for folder in [ref/f'components/soc/esp32c{chip}/include/soc',ref/f'components/soc/esp32c{chip}/register/soc',ref/f'osi-primary/idf/components/soc/esp32c{chip}/include/soc',ref/f'osi-primary/idf/components/soc/esp32c{chip}/register/soc']:
   for f in folder.glob('*.h'):shutil.copy2(f,inc/'soc'/f.name)
  for f in (ref/f'osi-primary/idf/components/soc/esp32c{chip}/include/modem').glob('*.h'):shutil.copy2(f,inc/'modem'/f.name)
  (inc/'esp_assert.h').write_text('#pragma once\n');(inc/'esp_bit_defs.h').write_text('#pragma once\n#define BIT(n) (1U<<(n))\n#define BIT64(n) (1ULL<<(n))\n');params=re.search(r'params: \[(.*?)\n    \]',(ref/f'osi-primary/hal/esp-phy/src/phy_init_data/phy_init_data_esp32c{chip}.rs').read_text(),re.S)[1];source=d/'oracle.c';source.write_text(C.replace('INIT_BYTES',params));oracle=d/'oracle';cmd=['cc','-std=c11','-Wno-cpp','-I',inc,source,'-o',oracle]
  if chip==6:cmd.insert(1,'-DC6')
  subprocess.run(list(map(str,cmd)),check=True);expected=d/'expected.bin';expected.write_bytes(subprocess.check_output([oracle]));model=d/'model.flex';adapter=(root/'lib/platform/esp32-riscv-radio-irq.flex').read_text();selected=re.search(r'fn esp_radio_irq_status\(\).*?\n}',adapter,re.S)[0];selected=selected[:selected.index('// The native handler')] if '// The native handler' in selected else selected;route=re.search(r'fn esp_radio_route\(source\).*', (root/'lib/platform/esp32-riscv-radio-lifecycle.flex').read_text())[0];model.write_text(''.join(f'import "{root}/{name}.flex";\n' for name in ['scripts/lib/build',f'lib/platform/esp32c{chip}','lib/platform/esp32-sdk-heap','lib/platform/esp32-radio-os-state','lib/platform/esp32-riscv-radio-hardware','lib/platform/esp32-riscv-radio-phy'])+F+'\n'+selected+'\n'+route+'\n');binary=d/'model';subprocess.run(['nice','-n','19',str(a.compiler.resolve()),str(model),'-o',str(binary)],check=True);checks,writes=struct.unpack('<QQ',subprocess.check_output([binary,expected],timeout=60));cases.append(dict(chip=chip,checks=checks,MMIO_writes=writes,IRQ_selector_and_dispatch_extracted_from_production=True,C6_hardware_ready_injected_for_policy_model=chip==6,CPU_execution=False,real_vendor_PHY_execution=False,physical_hardware=False));print(chip,checks,'radio/PHY policy checks')
 (w/'report.json').write_text(json.dumps(dict(pass_all=True,cases=cases,C6_base_clock_init_implemented=False,physical_hardware=False,real_calibration_or_RF_verified=False),indent=2)+'\n')
if __name__=='__main__':main()
