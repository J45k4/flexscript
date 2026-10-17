#!/usr/bin/env python3
"""Validate read-only ECO3 silicon observations;this is not emulator proof.

Requires original flash bytes only to verify the expected private page hashes.
No device access,downloads,or flash modification is performed here.
"""
import argparse,hashlib,json,re
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
for name in ('observe','detail','irq','observe-elf','detail-elf','irq-elf','backup','report'):p.add_argument('--'+name,type=Path,required=True)
p.add_argument('--backup-sha256',required=True);a=p.parse_args()
sha=lambda b:hashlib.sha256(b).hexdigest()
backup=a.backup.read_bytes();assert len(backup)==4194304 and sha(backup)==a.backup_sha256,'backup hash'
md5=hashlib.md5(backup).hexdigest();proof={};texts={}
for name in ('observe','detail','irq'):
 directory=getattr(a,name);d=json.loads((directory/'physical.json').read_text());data=(directory/'uart.bin').read_bytes();elf=getattr(a,name+'_elf').read_bytes()
 assert all(d[k] for k in ('pass','ram_only','flash_before_matches','flash_after_matches','final_reset')),name+' incomplete physical verification'
 assert not d['flash_write_requested'] and d['expected_full_flash_MD5']==md5,name+' flash contract'
 assert d['ELF_sha256']==sha(elf) and d['UART_sha256']==sha(data),name+' artifact mismatch'
 assert d['stages']==['before','RAM-load','after','final-reset'],name+' stage mismatch'
 text=data.decode();assert ' FAIL' not in text;proof[name]={'ELF_sha256':sha(elf),'UART_sha256':sha(data),'full4MiB_unchanged':True,'final_reset':True};texts[name]=text
word=lambda page:int.from_bytes(backup[page*65536+0x1234:page*65536+0x1238],'little')
h=r'([0-9a-f]{16})'
pattern=r'CACHE BEGIN '+h+r' MODE '+h+r' TRAP '+h+r' BEFORE0 '+h+r' BEFORE3 '+h+r'\r\nCACHE OBS '+h+r' DBG0 '+h+r' DBG3 '+h+r' PENDING '+h+r'\r\n'
observations=[[int(v,16) for v in m] for m in re.findall(pattern,texts['observe'])];assert len(observations)==16
for i,row in enumerate(observations):
 bus,mode,trap,before0,before3,value,debug0,debug3,pending=row;assert (bus,trap,mode)==(i//8,(i//4)%2,i%4)
 assert value==(word(1) if mode==0 else word(0) if mode==1 else 0xbad00bad),'observed data behavior'
 assert debug0==(0 if mode==0 else 1),'observed MMU status'
assert texts['observe'].endswith('PASS: cache access observation,16 read cases\r\n')
pattern=r'MMU DETAIL BUS '+h+r' ENTRY '+h+r' PAGE WORD OK '+h+r' DBG0 '+h+r' DBG3 '+h+r'\r\n'
detail=[[int(v,16) for v in m] for m in re.findall(pattern,texts['detail'])];assert len(detail)==12
for i,(bus,entry,ok,debug0,debug3) in enumerate(detail):assert (bus,entry,ok,debug0)==(i//6,(i//3%2)*256+i%3,1,i//3%2)
assert re.findall(r'CLEAR BEFORE0 '+h+r' AFTER0 '+h,texts['detail'])==[('0000000000000001','0000000000000001')]*2
pattern=r'DISABLED BUS '+h+r' VALUE '+h+r' CTRL '+h+r' CFG '+h+r' DBG0 '+h+r' DBG3 '+h+r' ENABLES '+h+r' PENDING OFF '+h+r' AFTER ENABLE3 '+h+r' AFTER ENABLE MASK '+h
settled=[[int(v,16) for v in m] for m in re.findall(pattern,texts['detail'])];assert len(settled)==2
for bus,value,ctrl,cfg,db0,db3,mask,off,after,after_mask in settled:
 expected=(1<<7)|(1<<15)|(1<<21)|((1<<19)*bus);assert value==0xbad00bad and not(ctrl&8) and db0==1 and db3==(0x400|(0x4000*bus));assert mask==after_mask==expected and off==0 and after==db3,'settled MMU/disabled IRQ mapping'
assert texts['detail'].endswith('PASS: cache detail,12 page words and28-bit enable scans\r\n')
pattern=r'IRQ BASE PRO0 '+h+r' PRO3 '+h+r' APP0 '+h+r' APP3 '+h+r' ENABLES '+h
base=re.findall(pattern,texts['irq']);assert len(base)==1;assert [int(v,16) for v in base[0]]==[0,1,1,0,1<<7]
pattern=r'IRQ DISABLED BUS '+h+r' PRO0 '+h+r' PRO3 '+h+r' APP0 '+h+r' APP3 '+h+r' ENABLES '+h+r' AFTER ENABLE MASK '+h
irq=[[int(v,16) for v in m] for m in re.findall(pattern,texts['irq'])];assert len(irq)==2
for bus,pro0,pro3,app0,app3,mask,after in irq:
 expected=(1<<7)|(1<<15)|((1<<19)*bus);assert [pro0,pro3,app0,app3]==[0,0x401|(0x4000*bus),1,0] and mask==after==expected,'GNU settled IRQ mapping'
assert texts['irq'].endswith('PASS: GNU cache reads and5 settled28-bit IRQ scans\r\n')
r={'observations_verified':True,'emulator_implemented':False,'scope_complete':False,'chip':'original ESP32 ECO3','physical':proof,'read_observations':16,'primed_page_word_cases':12,'GNU_settled_enable_scans':5,'detail_settled_enable_scans':4,'disabled_data_fill':'0xbad00bad','invalid_MMU_bit':8,'invalid_MMU_pages_verified':[0,1,2],'MMU_status_bit':0,'MMU_enable_bits':{'PRO':21,'APP':7},'disabled_data_status_bits':{'DROM':10,'IROM_data':14},'disabled_data_enable_bits':{'DROM':15,'IROM_data':19},'observed_clear_behavior':'Valid lookup clears PRO MMU error;CTRL1 bit13 pulse did not. EN0 masks pending IRQ;cache re-enable retains disabled-access flags. APP MMU flag was already set in RAM-download baseline.','remaining':'Repeated invalid-MMU accesses without a valid lookup can stall;cache-line/fill behavior,actual IRQ handler delivery,instruction fetch andCPU1 behavior remain required before full T293 parity. Earlier scans without settling are diagnostics,not register-contract evidence.'}
a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(r,indent=2)+'\n');print('PASS:16 data observations,12 page words,9 settled enable scans;all full4MiB unchanged/reset')
