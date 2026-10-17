"""Independent already-pending timer/GPIO WAITI experiment."""
import re,struct
from elf32_symbols import elf32_symbols,elf32_mapped
ROWS=64
MASKS=(64,32768,65536,2,66,32770,65538,98370)
LEVELS=(1,3,5,1,1,3,5,5)
IDS=('SOURCE','GATE','ALIGN','REPEAT')
WORDS=('SELECTOR','MASK','PS','PENDING','COUNT','MARKER','GATEPC','STREAMPC','IRQCC','IRQPS','EPS','EPC','IRQPENDING','ACKPENDING','RETCC','LEVEL','T0','T1','PREPENDING','ENABLED','GPIOPRE','GPIOIRQ','GPIOACK','CAUSE0','CAUSE1','FINALMARKER','RESETPC','RESERVED0','RESERVED1','RESERVED2','RESERVED3','RESERVED4')
def identities():return [(s,g,a,n) for s in range(8) for g in range(2) for a in range(2) for n in range(2)]
def generate_blocks():
 out=[];table=[]
 for selector,(source,gate,align,repeat) in enumerate(identities()[::2]):
  mask=MASKS[source];name=f'pw_case_{selector}';table.append(name)
  out+=['.section .text.'+name+',"ax"','.balign 4','.global '+name,name+':',f'movi a5,{mask}','s32i a5,a3,4','s32i a5,a3,76','movi a5,0']
  for timer,bit in enumerate((64,32768,65536)):
   if mask&bit:out+=[f'wsr a5,ccompare{timer}']
  out+=['movi a9,0',f'.global pw_reset_{selector}',f'pw_reset_{selector}:','wsr a9,ccount','esync']
  if mask&2:out+=['movi a5,1','slli a5,a5,19','movi a6,0x3ff44048','s32i a5,a6,0','memw']
  out+=['rsr a5,interrupt','s32i a5,a3,72','movi a6,0x3ff44044','l32i a5,a6,0','s32i a5,a3,80',f'movi a5,{mask}','wsr a5,intenable','rsync',f'movi a5,pw_gate_{selector}','s32i a5,a3,24',f'movi a5,pw_stream_{selector}','s32i a5,a3,28',f'movi a5,pw_reset_{selector}','s32i a5,a3,104','l32i a7,a3,8','movi a10,0',*['nop']*8,'.begin no-transform',f'j .Lpw_aligned_{selector}','.balign 16',f'.Lpw_aligned_{selector}:']
  if align:out+=['nop.n']
  out+=['rsr a4,ccount',f'.global pw_gate_{selector}',f'pw_gate_{selector}:',('waiti 0' if gate==0 else 'wsr a7,ps'),f'.global pw_stream_{selector}',f'pw_stream_{selector}:','rsync']+['addi a10,a10,1']*160+['.end no-transform','rsr a2,ccount','s32i a4,a3,64','s32i a2,a3,68','s32i a10,a3,100','movi a5,0','wsr a5,intenable','rsil a5,15','s32i a5,a3,8','rsr a5,interrupt','s32i a5,a3,12','rsr a5,exccause','s32i a5,a3,96','j pw_done']
 out+=['.section .rodata.pw_table,"a"','.balign 4','.global pw_table','pw_table:']+['.word '+x for x in table]
 out+=['.section .text.pw_vectors,"ax"','.balign 1024','.global pw_vectors','pw_vectors:']
 for offset,level in [(0x1c0,3),(0x240,5),(0x300,1),(0x340,1)]:out += [f'.space {offset}-(.-pw_vectors)','.begin no-transform','rsr a6,ccount',f'j pw_handler_{level}','.end no-transform']
 for level in (1,3,5):
  out+=['.section .text.pw_handler_'+str(level)+',"ax"','.balign 4',f'.global pw_handler_{level}',f'pw_handler_{level}:','s32i a6,a3,32','rsr a5,ps','s32i a5,a3,36']
  out+=(['l32i a5,a3,8'] if level==1 else [f'rsr a5,eps{level}'])+['s32i a5,a3,40',f'rsr a5,epc{level}','s32i a5,a3,44','rsr a5,interrupt','s32i a5,a3,48','s32i a10,a3,20','movi a5,1','s32i a5,a3,16',f'movi a5,{level}','s32i a5,a3,60','movi a6,0x3ff44044','l32i a5,a6,0','s32i a5,a3,84','movi a5,7','slli a5,a5,28','wsr a5,ccompare0','wsr a5,ccompare1','wsr a5,ccompare2','rsync','movi a5,1','slli a5,a5,19','movi a6,0x3ff4404c','s32i a5,a6,0','memw','movi a6,0x3ff44044','l32i a5,a6,0','s32i a5,a3,88','rsr a5,interrupt','s32i a5,a3,52','rsr a5,ccount','s32i a5,a3,56','.begin no-transform',f'.global pw_return_{level}',f'pw_return_{level}:',('rfe' if level==1 else f'rfi {level}'),'.end no-transform']
 return out

def op3(image,pc):return int.from_bytes(elf32_mapped(image,pc,3),'little')
def j_target(image,pc):
 op=op3(image,pc);assert op&63==6;d=op>>6
 if d&131072:d-=262144
 return pc+4+d

def layout(image):
 s=elf32_symbols(image);assert s['pw_vectors']%1024==0 and elf32_mapped(image,s['pw_mask_cpu'],6)==bytes.fromhex('50e413102000')
 for offset,level in [(0x1c0,3),(0x240,5),(0x300,1),(0x340,1)]:assert op3(image,s['pw_vectors']+offset)==0x03ea60 and j_target(image,s['pw_vectors']+offset+3)==s[f'pw_handler_{level}']
 for level in (1,3,5):assert op3(image,s[f'pw_return_{level}'])==(0x003000 if level==1 else 0x003010|(level<<8))
 for selector,(source,gate,align,repeat) in enumerate(identities()[::2]):
  at=s[f'pw_gate_{selector}'];stream=s[f'pw_stream_{selector}'];assert at%16==3+align*2 and op3(image,at-3)==0x03ea40
  assert struct.unpack('<I',elf32_mapped(image,s['pw_table']+selector*4,4))[0]==s[f'pw_case_{selector}']
  assert op3(image,s[f'pw_reset_{selector}'])==0x13ea90 and op3(image,s[f'pw_reset_{selector}']+3)==0x002020
  assert op3(image,at)==(0x007000 if gate==0 else 0x13e670) and stream==at+3
  assert op3(image,stream)==0x002010 and elf32_mapped(image,stream+3,480)==bytes.fromhex('a2ca01')*160
 return s

def header(data,clock):
 m=re.findall(rb'PENDING START CLOCK ([0-9a-f]{16}) SOURCE ([0-9a-f]{16}) PERIOD ([0-9a-f]{16}) DIV ([0-9a-f]{16}) ROMTICKS ([0-9a-f]{16})\r\n',data)
 assert len(m)==1 and tuple(int(v,16) for v in m[0])==((40,0,0,0,13) if clock==40 else (160,1,1,0,160))

def validate(rows,image):
 s=layout(image);assert len(rows)==ROWS
 for i,(row,identity) in enumerate(zip(rows,identities())):
  source,gate,align,repeat=identity;mask=MASKS[source];assert tuple(row[k] for k in IDS)==identity and all(0<=row[k]<=0xffffffff for k in WORDS)
  assert row['SELECTOR']==i//2 and row['MASK']==row['ENABLED']==mask
  assert row['GATEPC']==s[f'pw_gate_{i//2}'] and row['STREAMPC']==s[f'pw_stream_{i//2}'] and row['RESETPC']==s[f'pw_reset_{i//2}']
  assert row['COUNT']==1 and row['LEVEL']==LEVELS[source] and row['MARKER']<160 and row['FINALMARKER']==160
  assert row['IRQPENDING']==mask and row['PREPENDING'] in (mask,mask&~2) and row['ACKPENDING']==row['PENDING']==0
  assert row['GPIOPRE']==row['GPIOIRQ']==((1<<19) if mask&2 else 0) and row['GPIOACK']==0
  assert row['EPC']==row['STREAMPC']+(3+row['MARKER']*3 if row['MARKER'] else 0)
 return rows

def parse_ram(raw,image):
 assert len(raw)==ROWS*128
 return validate([dict(zip(IDS,identities()[i]),**dict(zip(WORDS,struct.unpack_from('<32I',raw,i*128)))) for i in range(ROWS)],image)

def parse(data,image,clock):
 header(data,clock);assert b' FAIL' not in data and data.count(f'PENDING COMPLETE CLOCK {clock:016x}\r\n'.encode())==1;rows=[]
 for line in data.splitlines():
  if not line.startswith(b'PENDING SOURCE '):continue
  v=line.decode().split();assert len(v)==1+2*(len(IDS)+len(WORDS)) and v[1::2]==list(IDS+WORDS)
  assert all(re.fullmatch('[0-9a-f]{16}',x) for x in v[2::2]);rows.append(dict(zip(IDS+WORDS,[int(x,16) for x in v[2::2]])))
 return validate(rows,image)
