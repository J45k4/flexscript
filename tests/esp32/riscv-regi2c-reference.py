#!/usr/bin/env python3
"""Pinned C6 internal analog-I2C MMIO model; no C6 CPU or analog-hardware proof."""
import argparse,hashlib,json,re,shutil,struct,subprocess
from pathlib import Path
C='''#include <stdint.h>
#include <stdio.h>
#include "esp_bit_defs.h"
#include "soc/i2c_ana_mst_reg.h"
#include "modem/modem_lpcon_reg.h"
int main(void){uint64_t v[16]={DR_REG_I2C_ANA_MST_BASE,I2C_ANA_MST_I2C0_CTRL_REG,I2C_ANA_MST_I2C1_CTRL_REG,I2C_ANA_MST_ANA_CONF1_REG,I2C_ANA_MST_ANA_CONF2_REG,MODEM_LPCON_CLK_CONF_REG,MODEM_LPCON_I2C_MST_CLK_CONF_REG,I2C_ANA_MST_I2C0_BUSY,I2C_ANA_MST_ANA_CONF1_M,0,0,0,MODEM_LPCON_CLK_I2C_MST_EN,MODEM_LPCON_CLK_I2C_MST_SEL_160M,0,0};return fwrite(v,sizeof v,1,stdout)!=1;}
'''
def main():
 p=argparse.ArgumentParser();p.add_argument('--compiler',required=True,type=Path);p.add_argument('--source-root',type=Path);p.add_argument('--reference',required=True,type=Path);p.add_argument('--work',required=True,type=Path);p.add_argument('--no-controls',action='store_true');a=p.parse_args();root=(a.source_root or Path(__file__).resolve().parents[2]).resolve();ref=a.reference.resolve();primary=ref/'regi2c-primary';w=a.work.resolve();w.mkdir(parents=True,exist_ok=True)
 for row in json.loads((primary/'provenance.json').read_text()):assert hashlib.sha256((primary/row['path']).read_bytes()).hexdigest()==row['sha256']
 inc=w/'include';(inc/'soc').mkdir(parents=True,exist_ok=True);(inc/'modem').mkdir(exist_ok=True)
 for folder in [ref/'components/soc/esp32c6/include/soc',ref/'components/soc/esp32c6/register/soc']:
  for f in folder.glob('*.h'):shutil.copy2(f,inc/'soc'/f.name)
 for f in (ref/'osi-primary/idf/components/soc/esp32c6/include/modem').glob('*.h'):shutil.copy2(f,inc/'modem'/f.name)
 shutil.copy2(primary/'i2c_ana_mst_reg.h',inc/'soc/i2c_ana_mst_reg.h');(inc/'esp_assert.h').write_text('#pragma once\n');(inc/'esp_bit_defs.h').write_text('#pragma once\n#define BIT(n) (1U<<(n))\n#define BIT64(n) (1ULL<<(n))\n');src=w/'oracle.c';src.write_text(C);exe=w/'oracle';subprocess.run(['cc','-std=c11','-Wno-cpp','-I',str(inc),str(src),'-o',str(exe)],check=True);values=list(struct.unpack('<16Q',subprocess.check_output([exe])))
 def shift(file,name):return int(re.search(r'pub fn '+name+r'\(&mut self\).*?::new\(self, (\d+)\)',(primary/'pac/i2c_ana_mst'/file).read_text(),re.S)[1])
 values[9]=shift('i2c_ctrl.rs','slave_reg_addr');values[10]=shift('i2c_ctrl.rs','data');values[11]=shift('i2c_ctrl.rs','read_write');assert values[7]==1<<25 and values[8]==0xffffff
 masters=(primary/'hal-c6-regi2c.rs').read_text()
 for name,field in [('BIAS','bias'),('BBPLL','bbpll'),('ULP_CAL','ulp_cal'),('SAR_I2C','sar_i2c'),('DIG_REG','dig_reg')]:
  block=int(re.search(r'master: REGI2C_'+name+r'\((0x[0-9a-f]+), 0\)',masters)[1],16);values.extend([block,shift('ana_conf1.rs',field+'_rd'),shift('ana_conf2.rs',field+'_mst_sel')])
 expected=w/'expected.bin';expected.write_bytes(struct.pack('<'+'Q'*len(values),*values));model=(root/'tests/esp32/riscv-regi2c-model.flex').read_text().replace('../../scripts/',str(root/'scripts')+'/').replace('../../lib/',str(root/'lib')+'/');port=root/'lib/platform/esp32c6-radio-regi2c.flex'
 def execute(tag,text):
  source=w/(tag+'.flex');source.write_text(text);binary=w/tag;r=subprocess.run(['nice','-n','19',str(a.compiler.resolve()),str(source),'-o',str(binary)],capture_output=True,timeout=60);assert r.returncode==0,(tag,r.stdout,r.stderr);r=subprocess.run([binary,expected],capture_output=True,timeout=10);(w/(tag+'.stdout')).write_bytes(r.stdout);(w/(tag+'.stderr')).write_bytes(r.stderr);return r
 good=execute('canonical',model);assert good.returncode==0,good.stderr;checks=struct.unpack('<Q',good.stdout)[0];controls=[]
 mutations=[('wrong-master', 'if esp32_load32(0x600af820)&(1<<(bit+2))','if !(esp32_load32(0x600af820)&(1<<(bit+2)))'),('wrong-regulator-select','if block==0x6d{return 10;}','if block==0x6d{return 9;}'),('wrong-data-shift','value<<16','value<<8'),('missing-ADC-guard',' || esp_adc_busy',''),('lost-fault-lease','esp_radio_regi2c_fault=1;','esp_radio_c6_regi2c_restore();'),('ignore-other-master','|esp32_load32(0x600af804)',''),('wrong-clock-restore','0x600af018,4,esp_radio_regi2c_clock','0x600af018,8,esp_radio_regi2c_clock'),('premature-recovery','if !result{esp_radio_c6_regi2c_restore();}','esp_radio_c6_regi2c_restore();'),('missing-field-bound','if data>mask{return -22;}','')]
 mutations.extend([("foreign-busy-source-switched", " esp_reg_update(0x600af018,4,4);\n // ANA_CONF1", " esp_reg_update(0x600af018,4,4);esp_reg_update(0x600af010,1,1);\n // ANA_CONF1"), ("saved-source-lost", "0x600af010,1,esp_radio_regi2c_source", "0x600af010,1,0")])
 if not a.no_controls:
  original=port.read_text()
  for tag,old,new in mutations:
   assert old in original,tag;mutant=w/(tag+'-port.flex');mutant.write_text(original.replace(old,new).replace('"esp32-analog-state.flex"','"'+str(root/'lib/platform/esp32-analog-state.flex')+'"'));r=execute(tag,model.replace(str(port),str(mutant)));assert r.returncode!=0,tag;controls.append(dict(name=tag,detected=True,result=r.returncode))
 report=dict(pass_all=True,checks=checks,blocks=5,masters=2,byte_patterns=256,field_extents=36,detected_defects=controls,primary_header_and_PAC_contract=True,CPU_execution=False,C6_ROM_execution=False,physical_hardware=False,PMU_startup_complete=False,compiler_sha256=hashlib.sha256(a.compiler.read_bytes()).hexdigest());(w/'report.json').write_text(json.dumps(report,indent=2)+'\n');print('PASS:',checks,'C6 analog-I2C model checks;',len(controls),'defects detected',flush=True)
if __name__=='__main__':main()
