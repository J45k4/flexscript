#!/usr/bin/env python3
"""Verify the16 silicon sequence observations andexplicit interruption recovery.

Accepts one recovered partial batch plus completed bounded batches. Verifies
all UART/image identities,stage outcomes andfull-flash integrity. This doesnot
claim that a native emulator already implements the captured behavior.
"""
import argparse,hashlib,json,re
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--manifest',type=Path,required=True);p.add_argument('--partial',type=Path,required=True);p.add_argument('--batch',type=Path,action='append',required=True);p.add_argument('--report',type=Path,required=True)
a=p.parse_args();sha=lambda b:hashlib.sha256(b).hexdigest();md5='285e47b19f9f05300915213a70e68d1c';manifest=json.loads(a.manifest.read_text());expected={(c['bus'],c['mode']):c for c in manifest};assert len(expected)==16;seen={};proof=[]
def digest_log(p):return any(int(s,16)==int(md5,16) for s in re.findall(rb'0x([0-9a-fA-F]{1,32})(?![0-9a-fA-F])',p.read_bytes()))
for directory,partial in [(a.partial,True)]+[(p,False) for p in a.batch]:
 d=json.loads((directory/'physical.json').read_text());assert d['before_matches'] and d['ram_only'] and not d['flash_write_requested'] and d['expected_full_flash_MD5']==md5;assert digest_log(directory/'before.log')
 if partial:
  recovery=json.loads((directory/'interruption-recovery.json').read_text());subset=json.loads((directory/'recovered-partial-batch.json').read_text());assert not d['pass'] and recovery['flash_unchanged'] and recovery['final_reset'] and subset['verified_subset'] and subset['full4MiB_unchanged'] and subset['final_reset'];assert digest_log(directory/'interruption-checksum.log');assert [(c['bus'],c['mode']) for c in d['cases']]==[(0,m) for m in range(8)]+[(1,0)];assert all(c['final_reset'] for c in d['cases'][:-1])
 else:
  assert d['pass'] and d['after_matches'] and d['final_reset'] and len(d['cases'])==d['selection']['count']<=4;assert all(c['final_reset'] for c in d['cases']);assert digest_log(directory/'after.log')
 proof.append({'directory':str(directory),'recovered_partial':partial,'full4MiB_unchanged':True,'final_reset':True})
 for case in d['cases']:
  key=(case['bus'],case['mode']);assert key in expected and key not in seen;item=expected[key];image=(a.manifest.parent/item['elf']).read_bytes();assert sha(image)==item['sha256']==case['sha256'];data=(directory/f'bus{key[0]}-mode{key[1]}.uart').read_bytes();assert sha(data)==case['UART_sha256'];text=data.decode();assert text==case['UART'] and ' FAIL' not in text and text.startswith(f'CACHE SEQ START {key[0]:016x} MODE {key[1]:016x}\r\n')
  fields=[(label,int(mmu,16),int(ctrl,16),int(cfg,16)) for label,mmu,ctrl,cfg in re.findall(r'([A-Z ]+) MMU ([0-9a-f]{16}) CTRL ([0-9a-f]{16}) CFG ([0-9a-f]{16})\r\n',text)];states={label:(mmu,ctrl,cfg) for label,mmu,ctrl,cfg in fields};assert states['FIRST READ ARMED']==(0,0x28,0x8ee) and states['FIRST READ DONE']==(1,0x28,0x8ee)
  mode=key[1];positive=mode in (0,1,4,7);assert case['completed']==positive and case['armed_second_read'];before=0 if mode in (4,7) else 1;cfg=0x28ee if mode==4 else 0x8ee;assert states['SECOND READ ARMED']==(before,0x28,cfg)
  if positive:
   assert states['SECOND READ DONE']==(0 if mode==4 else 1,0x28,cfg);assert text.endswith(f'CACHE SEQ COMPLETE {key[0]:016x} MODE {mode:016x}\r\n')
  else:assert 'SECOND READ DONE' not in text and 'CACHE SEQ COMPLETE' not in text and text.endswith(f'SECOND READ ARMED MMU {before:016x} CTRL 0000000000000028 CFG {cfg:016x}\r\n')
  if mode==6:assert states['CACHED VALID READ DONE']==(1,0x28,0x8ee)
  if mode==7:assert states['FRESH VALID READ DONE']==(0,0x28,0x8ee)
  seen[key]={'bus':key[0],'mode':mode,'completed':positive,'image_sha256':item['sha256'],'UART_sha256':sha(data),'after_cleanup_verified':True}
assert len(seen)==16
r={'observations_verified':True,'emulator_implemented':False,'scope_complete':False,'cases':[seen[k] for k in sorted(seen)],'completed':8,'stalled_before_retirement':8,'cleanup':proof,'findings':{'same_word_and_within_line_complete':True,'new_line_invalid_lookup_stalls_with_error_set':True,'flush_does_not_clear_error':True,'held_clear_suppresses_error_andallows_fill':True,'pulsed_clear_reexposes_error':True,'valid_hit_does_not_clear_MMU_error':True,'fresh_valid_lookup_clears_error_andallows_next_invalid_fill':True},'cache_geometry_reference':{'URL':'https://documentation.espressif.com/esp32_technical_reference_manual_en.pdf','version':'5.8','section':'3.3.4 Cache,page71','block_bytes':32,'ways':2},'limits':'CPU0 read-only RAM code onoriginalECO3;actual IRQ-handler delivery,invalid instruction fetch,CPU1,cache replacement/capacity modes andcycle timing remainunverified. Eight cases intentionally stop atblocked reads;these are observations rather than firmware completions. Interrupted firstbatch remainsmarked incomplete withseparate verifiedchecksum/reset recovery.'};a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(r,indent=2)+'\n');print('PASS:16 physicalsequences/8 completions/8 blockedreads;allflashguards andresets verified')
