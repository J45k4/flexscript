#!/usr/bin/env python3
"""Primary C6 PMU state/default/voltage policy; C3 C-peer execution, C6 execution is opt-in."""
import argparse,hashlib,json,re,shutil,struct,subprocess
from pathlib import Path

def generate(w,ref):
 primary=ref/'pmu-primary';base=ref;research=primary;d=w/'oracle';inc=d/'include';(inc/'soc').mkdir(parents=True,exist_ok=True);(inc/'hal').mkdir(exist_ok=True)
 for folder in [base/'components/soc/esp32c6/include/soc',base/'components/soc/esp32c6/register/soc']:
  for f in folder.glob('*.h'):shutil.copy2(f,inc/'soc'/f.name)
 shutil.copy2(base/'osi-primary/idf/components/soc/esp32c6/register/soc/efuse_reg.h',inc/'soc/efuse_reg.h');shutil.copy2(base/'osi-primary/idf/components/soc/esp32c6/include/soc/efuse_defs.h',inc/'soc/efuse_defs.h');shutil.copy2(primary/'components/soc/esp32c6/register/soc/pmu_struct.h',inc/'soc/pmu_struct.h');shutil.copy2(research/'components/soc/esp32c6/include/soc/pmu_icg_mapping.h',inc/'soc/pmu_icg_mapping.h');shutil.copy2(primary/'components/hal/include/hal/pmu_types.h',inc/'hal/pmu_types.h');(inc/'esp_assert.h').write_text('#pragma once\n');(inc/'esp_bit_defs.h').write_text('#pragma once\n#define BIT(n) (1U<<(n))\n#define BIT64(n) (1ULL<<(n))\n');(inc/'sdkconfig.h').write_text('#define CONFIG_IDF_TARGET_ESP32C6 1\n')
 param=(primary/'components/esp_hw_support/port/esp32c6/private_include/pmu_param.h').read_text().split('/* Following software configuration')[0];param=param.replace('#include <stdlib.h>','').replace('#include <esp_types.h>','').replace('#include "hal/pmu_hal.h"','#include "hal/pmu_types.h"');(inc/'pmu_param.h').write_text(param)
 original=(research/'components/esp_hw_support/port/esp32c6/pmu_param.c').read_text();macros=[];lines=original.splitlines();i=0
 while i<len(lines):
  if lines[i].startswith('#define PMU_'):
   chunk=[lines[i]]
   while lines[i].endswith('\\'):i+=1;chunk.append(lines[i])
   macros.append('\n'.join(chunk))
  i+=1
 structs=dict((name,body) for body,name in re.findall(r'typedef union\s*\{(.*?)\n\}\s*(\w+);',(inc/'soc/pmu_struct.h').read_text(),re.S));helpers=[]
 for name in ['pmu_hp_dig_power_reg_t','pmu_hp_clk_power_reg_t','pmu_hp_xtal_reg_t','pmu_hp_icg_modem_reg_t','pmu_hp_sysclk_reg_t','pmu_hp_sys_cntl_reg_t','pmu_hp_bias_reg_t','pmu_hp_regulator0_reg_t','pmu_hp_regulator1_reg_t','pmu_hp_backup_reg_t','pmu_lp_dig_power_reg_t','pmu_lp_clk_power_reg_t','pmu_lp_xtal_reg_t','pmu_lp_bias_reg_t','pmu_lp_regulator0_reg_t','pmu_lp_regulator1_reg_t']:
  body=structs[name];parts=re.findall(r'struct\s*\{(.*?)\n\s*\};',body,re.S);assert parts,name;branches=[]
  for j,part in enumerate(parts):
   fields=[(n,int(width)) for n,width in re.findall(r'uint32_t\s+(\w+)\s*:\s*(\d+)',part) if not n.startswith('reserved') and n not in ['lp_dbias_vol','hp_dbias_vol','dbias_sel','dbias_init']];branches.append('if(mode=='+str(j)+'){'+''.join('v.'+n+'='+str((1<<width)-1)+'u;' for n,width in fields)+'}')
  helpers.append('static uint32_t mask_'+name+'(int mode){'+name+' v={0};'+''.join(branches)+'return v.val;}')
 enum=re.search(r'typedef enum \{([^}]*PMU_HP_ICG_MODEM_CODE_SLEEP[^}]*)\}\s*pmu_hp_icg_modem_mode_t;', (primary/'components/esp_hw_support/include/esp_private/esp_pmu.h').read_text(),re.S)[0]
 heads=[enum,'#include <stddef.h>','#include "soc/efuse_reg.h"','#include "pmu_param.h"','#include "soc/pmu_icg_mapping.h"','#include "soc/clk_tree_defs.h"',*macros,*helpers]
 hp=[('dig_power','power','dig_power','pmu_hp_dig_power_reg_t'),('clk_power','power','clk_power','pmu_hp_clk_power_reg_t'),('xtal','power','xtal','pmu_hp_xtal_reg_t'),('icg_func','clock','icg_func',None),('icg_apb','clock','icg_apb',None),('icg_modem','clock','icg_modem','pmu_hp_icg_modem_reg_t'),('sysclk','clock','sysclk','pmu_hp_sysclk_reg_t'),('syscntl','digital','syscntl','pmu_hp_sys_cntl_reg_t'),('bias','analog','bias','pmu_hp_bias_reg_t'),('regulator0','analog','regulator0','pmu_hp_regulator0_reg_t'),('regulator1','analog','regulator1','pmu_hp_regulator1_reg_t'),('backup','retention','retention','pmu_hp_backup_reg_t'),('backup_clk','retention','backup_clk',None)]
 for name,typ in [('power','power'),('clock','clock'),('digital','digital'),('analog','analog'),('retention','retention')]:heads.append('static const pmu_hp_system_'+typ+'_param_t hp_'+name+'[]={PMU_HP_ACTIVE_'+name.upper()+'_CONFIG_DEFAULT(),PMU_HP_MODEM_'+name.upper()+'_CONFIG_DEFAULT(),PMU_HP_SLEEP_'+name.upper()+'_CONFIG_DEFAULT()};')
 for name in ['power','analog']:heads.append('static const pmu_lp_system_'+name+'_param_t lp_'+name+'[]={PMU_LP_ACTIVE_'+name.upper()+'_CONFIG_DEFAULT(),PMU_LP_SLEEP_'+name.upper()+'_CONFIG_DEFAULT()};')
 rows=[]
 for mode in range(3):
  for member,group,field,typ in hp:
   mask='mask_'+typ+'('+str(mode if typ=='pmu_hp_backup_reg_t' else 0)+')' if typ else '0xffffffffu';value='hp_'+group+'['+str(mode)+'].'+field+('.val' if typ else '')
   if field=='regulator0' and mode<2:value='(('+value+'&~PMU_HP_ACTIVE_HP_REGULATOR_DBIAS_M)|((uint32_t)h<<PMU_HP_ACTIVE_HP_REGULATOR_DBIAS_S))'
   rows.append(('DR_REG_PMU_BASE+offsetof(pmu_dev_t,hp_sys['+str(mode)+'].'+member+')',mask,value))
 for mode in range(2):
  for member,group,field,typ in [('dig_power','power','dig_power','pmu_lp_dig_power_reg_t'),('clk_power','power','clk_power','pmu_lp_clk_power_reg_t'),('regulator0','analog','regulator0','pmu_lp_regulator0_reg_t'),('regulator1','analog','regulator1','pmu_lp_regulator1_reg_t')]:
   mask='mask_'+typ+'(0)';value='lp_'+group+'['+str(mode)+'].'+field+'.val'
   if field=='regulator0' and not mode:value='(('+value+'&~PMU_HP_SLEEP_LP_REGULATOR_DBIAS_M)|((uint32_t)l<<PMU_HP_SLEEP_LP_REGULATOR_DBIAS_S))'
   rows.append(('DR_REG_PMU_BASE+offsetof(pmu_dev_t,lp_sys['+str(mode)+'].'+member+')',mask,value))
 rows.extend([('DR_REG_PMU_BASE+offsetof(pmu_dev_t,lp_sys[1].xtal)','mask_pmu_lp_xtal_reg_t(0)','lp_power[1].xtal.val'),('DR_REG_PMU_BASE+offsetof(pmu_dev_t,lp_sys[1].bias)','mask_pmu_lp_bias_reg_t(0)','lp_analog[1].bias.val')]);assert len(rows)==49
 heads.append('uint32_t c6_pmu_row(uint32_t row,uint32_t field,uint32_t h,uint32_t l){uint32_t address=0,mask=0,value=0;switch(row){'+''.join('case '+str(i)+':address='+a+';mask='+m+';value='+v+';break;' for i,(a,m,v) in enumerate(rows))+'default:return 0xffffffea;}if(field==0)return address;if(field==1)return mask;return value&mask;}')
 start=original.index('uint32_t get_act_hp_dbias(void)');biasbody=original[start:];heads.append('static uint32_t fake_version,fake_raw;\n#define ESP_HW_LOGD(...)\nuint32_t efuse_hal_blk_version(void){return fake_version;}\nuint32_t efuse_ll_get_active_hp_dbias(void){return fake_raw;}\nuint32_t efuse_ll_get_active_lp_dbias(void){return fake_raw;}\n'+biasbody+'\nuint32_t c6_pmu_bias(uint32_t version,uint32_t raw,uint32_t lp){fake_version=version;fake_raw=raw;return lp?get_act_lp_dbias():get_act_hp_dbias();}')
 heads.append('''#ifdef HOST_ORACLE
 #include <stdio.h>
 int main(void){uint64_t n=31*31*49;fwrite(&n,8,1,stdout);for(uint32_t h=1;h<=31;h++)for(uint32_t l=1;l<=31;l++)for(uint32_t row=0;row<49;row++){uint64_t v[6]={h,l,row,c6_pmu_row(row,0,h,l),c6_pmu_row(row,1,h,l),c6_pmu_row(row,2,h,l)};fwrite(v,sizeof v,1,stdout);}for(uint32_t version=0;version<=307;version++)for(uint32_t raw=0;raw<32;raw++)for(uint32_t lp=0;lp<2;lp++){uint64_t v[4]={version,raw,lp,c6_pmu_bias(version,raw,lp)};fwrite(v,sizeof v,1,stdout);}uint64_t meta[8]={EFUSE_RD_MAC_SPI_SYS_3_REG,EFUSE_RD_MAC_SPI_SYS_2_REG,EFUSE_BLK_VERSION_MAJOR_S,EFUSE_BLK_VERSION_MINOR_S,EFUSE_BLK_VERSION_MINOR_V,EFUSE_ACTIVE_HP_DBIAS_S,EFUSE_ACTIVE_LP_DBIAS_S,EFUSE_ACTIVE_HP_DBIAS_V};fwrite(meta,sizeof meta,1,stdout);return ferror(stdout);}
 #endif
 ''')
 (d/'peer.c').write_text('\n'.join(heads)+'\n');print('primary C types/defaults/bias functions emitted')
 return d/"peer.c",inc

def main():
 p=argparse.ArgumentParser();p.add_argument('--compiler',required=True,type=Path);p.add_argument('--reference',required=True,type=Path);p.add_argument('--work',required=True,type=Path);p.add_argument('--qemu',required=True,type=Path);p.add_argument('--source-root',type=Path);p.add_argument('--execute-c6',action='store_true');p.add_argument('--qemu-c6',type=Path);a=p.parse_args();root=(a.source_root or Path(__file__).resolve().parents[2]).resolve();w=a.work.resolve();w.mkdir(parents=True,exist_ok=True);ref=a.reference.resolve();c=a.compiler.resolve()
 for row in json.loads((ref/'pmu-primary/provenance.json').read_text()):assert hashlib.sha256((ref/'pmu-primary'/row['path']).read_bytes()).hexdigest()==row['sha256']
 def run(args):
  r=subprocess.run(list(map(str,args)),cwd=root,capture_output=True,timeout=60);assert r.returncode==0,(args,r.stdout,r.stderr);return r
 peer,inc=generate(w,ref);host=w/'oracle/peer';run(['cc','-DHOST_ORACLE','-std=c11','-Wno-cpp','-I',inc,peer,'-o',host]);expected=w/'expected.bin';expected.write_bytes(run([host]).stdout);model=(root/'tests/esp32/riscv-pmu-state-model.flex').read_text().replace('../../scripts/',str(root/'scripts')+'/').replace('../../lib/',str(root/'lib')+'/');port=root/'lib/platform/esp32c6-radio-pmu-data.flex'
 def model_case(tag,text):
  source=w/(tag+'.flex');source.write_text(text);binary=w/tag;run(['nice','-n','19',c,source,'-o',binary]);r=subprocess.run([binary,expected],capture_output=True,timeout=10);(w/(tag+'.stdout')).write_bytes(r.stdout);(w/(tag+'.stderr')).write_bytes(r.stderr);return r
 good=model_case('model',model);assert good.returncode==0,good.stderr;checks=struct.unpack('<Q',good.stdout)[0];controls=[];original=port.read_text()
 for tag,old,new in [('wrong-modem-functional-clock','if field==3{return 0x100000;}','if field==3{return 0x200;}'),('wrong-active-backup-mask','0x63f3dcf0','0xffffffff'),('wrong-LP-address','0x600b009c','0x600b00b4'),('uncalibrated-HP','(hp_bias<<27)','(25<<27)'),('missing-bias-offset','let result=raw+2;','let result=raw;'),('missing-bias-saturation','if result>31{return 31;}',''),('zero-bias-treated-as-fused','if version>=3 && raw','if version>=3')]:
  assert old in original,tag;f=w/(tag+'-port.flex');f.write_text(original.replace(old,new));adapter=root/'lib/platform/esp32c6-radio-pmu.flex';wrapper=w/(tag+'-adapter.flex');wrapper.write_text(adapter.read_text().replace('"esp32c6-radio-pmu-data.flex"','"'+str(f)+'"'));r=model_case(tag,model.replace(str(adapter),str(wrapper)));assert r.returncode!=0,tag;controls.append(dict(name=tag,detected=True,result=r.returncode))
 adapter=root/'lib/platform/esp32c6-radio-pmu.flex'
 for tag,old,new in [('wrong-eFuse-version-shift','version>>30','version>>29'),('wrong-LP-bias-field','low_power*5','low_power*4'),('missing-chip-guard',' || rv_hal_chip!=13','')]:
  original=adapter.read_text();assert old in original;f=w/(tag+'-adapter.flex');f.write_text(original.replace(old,new).replace('"esp32c6-radio-pmu-data.flex"','"'+str(port)+'"'));r=model_case(tag,model.replace(str(adapter),str(f)));assert r.returncode!=0,tag;controls.append(dict(name=tag,detected=True,result=r.returncode))
 obj=w/'peer.o';run(['clang','--target=riscv32','-march=rv32imc_zicsr_zifencei','-mabi=ilp32','-Os','-ffreestanding','-fno-builtin','-fno-stack-protector','-msmall-data-limit=0','-I',inc,'-c',peer,'-o',obj]);linker=w/'linker';run([c,root/'scripts/esp32-link.flex','-o',linker]);cases=[]
 for chip in [3,6]:
  text=(root/'tests/esp32/riscv-pmu-state.flex').read_text().replace('esp32c3',f'esp32c{chip}').replace('../../lib/',str(root/'lib')+'/');source=w/f'c{chip}.flex';source.write_text(text);fw=w/f'c{chip}.elf';linked=w/f'c{chip}-linked.elf';image=w/f'c{chip}.bin';report=w/f'c{chip}.json';run([c,'--target',f'esp32c{chip}-elf',source,'-o',fw]);run([linker,'--ld','ld.lld','--firmware',fw,'--object',obj,'--output',linked,'--image',image]);args=['python3',root/'tests/esp32/riscv-rom-peer.py','--qemu',(a.qemu_c6 or a.qemu) if chip==6 and a.execute_c6 else a.qemu,'--image',image,'--elf',linked,'--report',report]
  if chip==6 and not a.execute_c6:args+=['--validate-only']
  run(args);row=json.loads(report.read_text());row.update(pure_C6_policy_only=True,PMU_register_access=False,native_C6_eFuse_read_path=chip==6 and row['ROM_boot'],factory_eFuse_values_verified=False);cases.append(row)
 report=dict(pass_all=True,checks=checks,PMU_register_rows=49,calibration_versions=308,all_5bit_biases=True,detected_defects=controls,C3_ROM_boots=sum(x.get('machine')=='esp32c3' and x['ROM_boot'] for x in cases),C6_package_checks=sum(not x['ROM_boot'] for x in cases),C6_ROM_boots=sum(x.get('machine')=='esp32c6' and x['ROM_boot'] for x in cases),cases=cases,actual_PMU_initialization=False,full_C6_power_clock_startup=False,physical_hardware=False,compiler_sha256=hashlib.sha256(c.read_bytes()).hexdigest());(w/'report.json').write_text(json.dumps(report,indent=2)+'\n');print('PASS:',checks,'C6 PMU policy checks;',len(controls),'defects;',report['C3_ROM_boots'],'C3 boots,',report['C6_ROM_boots'],'C6 policy boots,',report['C6_package_checks'],'C6 packages; no PMU operation',flush=True)
if __name__=='__main__':main()
