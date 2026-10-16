"""Independent constant-counter natural timer expiry experiment."""
import re,struct
from elf32_symbols import elf32_symbols,elf32_mapped
ROWS=108
WORDS=('SELECTOR','TARGET','PS','PENDING','COUNT','MARKER','RESETPC','STREAMPC','IRQCC','IRQPS','EPS','EPC','IRQPENDING','ACKPENDING','RETCC','LEVEL','T0','T1',*(f'P{i}' for i in range(11)),'CAUSE0','CAUSE1','READBACK')
IDS=('TIMER','MODE','DISTANCE','ALIGN','REPEAT')
DISTANCES=(32,64,128)
def identities():return [(t,m,d,a,n) for t in range(3) for m in range(3) for d in DISTANCES for a in range(2) for n in range(2)]
def generate_blocks():
 out=[];table=[];selector=0
 for timer in range(3):
  for mode in range(3):
   for target in DISTANCES:
    for align in range(2):
     name=f'ex_case_{selector}';table.append(name)
     out+=['.section .text.'+name+',"ax"','.balign 4','.global '+name,name+':',f'movi a5,{target}',f'wsr a5,ccompare{timer}','s32i a5,a3,4',f'rsr a5,ccompare{timer}','s32i a5,a3,124']
     out += (['movi a5,0'] if mode==2 else ['movi a5,1',f'slli a5,a5,{[6,15,16][timer]}'])+['wsr a5,intenable','rsync',f'movi a5,ex_reset_{selector}','s32i a5,a3,24',f'movi a5,ex_stream_{selector}','s32i a5,a3,28','movi a10,0','movi a9,0','l32i a7,a3,8','wsr a7,ps','rsync',*['nop']*8,'.begin no-transform',f'j .Lex_aligned_{selector}','.balign 16',f'.Lex_aligned_{selector}:']
     if align:out+=['nop.n']
     out+=[f'.global ex_reset_{selector}',f'ex_reset_{selector}:','wsr a9,ccount','esync',f'.global ex_slot_{selector}',f'ex_slot_{selector}:',('waiti 0' if mode==1 else 'nop'),f'.global ex_stream_{selector}',f'ex_stream_{selector}:']
     if mode==2:
      out+=['nop']*(target-8)
      out += [f'.global ex_trace_{selector}',f'ex_trace_{selector}:','rsr a4,ccount']+[f'rsr a{reg},interrupt' for reg in range(5,16)]+['rsr a2,ccount','.end no-transform','s32i a4,a3,64','s32i a2,a3,68']+[f's32i a{reg},a3,{72+(reg-5)*4}' for reg in range(5,16)]
     else:out += ['addi a10,a10,1']*160+['.end no-transform','s32i a10,a3,112']
     out += ['movi a5,0','wsr a5,intenable','rsil a5,15','s32i a5,a3,8','rsr a5,interrupt','s32i a5,a3,12','rsr a5,exccause','s32i a5,a3,120','j ex_done'];selector+=1
 out+=['.section .rodata.ex_table,"a"','.balign 4','.global ex_table','ex_table:']+['.word '+x for x in table]
 out+=['.section .text.ex_vectors,"ax"','.balign 1024','.global ex_vectors','ex_vectors:']
 for offset,level in [(0x1c0,3),(0x240,5),(0x300,1),(0x340,1)]:
  out += [f'.space {offset}-(.-ex_vectors)','.begin no-transform','rsr a6,ccount',f'j ex_handler_{level}','.end no-transform']
 for timer,level in enumerate((1,3,5)):
  out+=['.section .text.ex_handler_'+str(level)+',"ax"','.balign 4',f'.global ex_handler_{level}',f'ex_handler_{level}:','s32i a6,a3,32','rsr a5,ps','s32i a5,a3,36']
  out += (['l32i a5,a3,8'] if level==1 else [f'rsr a5,eps{level}'])+['s32i a5,a3,40',f'rsr a5,epc{level}','s32i a5,a3,44','rsr a5,interrupt','s32i a5,a3,48','s32i a10,a3,20','movi a5,1','s32i a5,a3,16',f'movi a5,{level}','s32i a5,a3,60','movi a5,7','slli a5,a5,28',f'wsr a5,ccompare{timer}','rsync','rsr a5,interrupt','s32i a5,a3,52','rsr a5,ccount','s32i a5,a3,56','.begin no-transform',f'.global ex_return_{level}',f'ex_return_{level}:',('rfe' if level==1 else f'rfi {level}'),'.end no-transform']
 return out

def op3(image,pc):return int.from_bytes(elf32_mapped(image,pc,3),'little')
def j_target(image,pc):
 op=op3(image,pc);assert op&63==6;d=op>>6
 if d&131072:d-=262144
 return pc+4+d

def layout(image):
 s=elf32_symbols(image);assert s['ex_vectors']%1024==0 and elf32_mapped(image,s['ex_mask_cpu'],6)==bytes.fromhex('50e413102000')
 for offset,level in [(0x1c0,3),(0x240,5),(0x300,1),(0x340,1)]:assert op3(image,s['ex_vectors']+offset)==0x03ea60 and j_target(image,s['ex_vectors']+offset+3)==s[f'ex_handler_{level}']
 for level in (1,3,5):assert op3(image,s[f'ex_return_{level}'])==(0x003000 if level==1 else 0x003010|(level<<8))
 for selector,(timer,mode,target,align,repeat) in enumerate(identities()[::2]):
  reset=s[f'ex_reset_{selector}'];slot=s[f'ex_slot_{selector}'];stream=s[f'ex_stream_{selector}'];assert reset%16==align*2
  assert struct.unpack('<I',elf32_mapped(image,s['ex_table']+selector*4,4))[0]==s[f'ex_case_{selector}']
  assert op3(image,reset)==0x13ea90 and op3(image,reset+3)==0x002020 and slot==reset+6 and stream==slot+3
  assert op3(image,slot)==(0x007000 if mode==1 else 0x0020f0)
  if mode<2:assert elf32_mapped(image,stream,480)==bytes.fromhex('a2ca01')*160
  else:
   trace=s[f'ex_trace_{selector}'];assert elf32_mapped(image,stream,(target-8)*3)==bytes.fromhex('f02000')*(target-8)
   assert trace==stream+(target-8)*3 and op3(image,trace)==0x03ea40
   assert elf32_mapped(image,trace+3,33)==b''.join(bytes([reg<<4,226,3]) for reg in range(5,16))
 return s

def header(data,clock):
 m=re.findall(rb'EXPIRY START CLOCK ([0-9a-f]{16}) SOURCE ([0-9a-f]{16}) PERIOD ([0-9a-f]{16}) DIV ([0-9a-f]{16}) ROMTICKS ([0-9a-f]{16})\r\n',data)
 assert len(m)==1 and tuple(int(v,16) for v in m[0])==((40,0,0,0,13) if clock==40 else (160,1,1,0,160))

def validate(rows,image):
 s=layout(image);assert len(rows)==ROWS
 for i,(row,identity) in enumerate(zip(rows,identities())):
  timer,mode,target,align,repeat=identity;assert tuple(row[k] for k in IDS)==identity
  assert all(0<=row[k]<=0xffffffff for k in WORDS)
  assert row['SELECTOR']==i//2 and row['TARGET']==row['READBACK']==target
  assert row['RESETPC']==s[f'ex_reset_{i//2}'] and row['STREAMPC']==s[f'ex_stream_{i//2}']
  if mode<2:
   assert row['COUNT']==1 and row['LEVEL']==(1,3,5)[timer] and row['MARKER']<160 and row['ACKPENDING']==row['PENDING']==0 and row['P10']==160
   assert row['IRQPENDING']==(64,32768,65536)[timer]
   assert row['EPC']==row['STREAMPC']+(row['MARKER']*3 if mode==0 else 0)
   if mode==1:assert row['MARKER']==0
  else:
   assert row['COUNT']==row['MARKER']==0 and all(row[k]==0 for k in WORDS[8:16])
   assert row['PENDING']==(64,32768,65536)[timer]
 return rows

def parse_ram(raw,image):
 assert len(raw)==ROWS*128
 return validate([dict(zip(IDS,identities()[i]),**dict(zip(WORDS,struct.unpack_from('<32I',raw,i*128)))) for i in range(ROWS)],image)

def parse(data,image,clock):
 header(data,clock);assert b' FAIL' not in data and data.count(f'EXPIRY COMPLETE CLOCK {clock:016x}\r\n'.encode())==1
 rows=[]
 for line in data.splitlines():
  if not line.startswith(b'EXPIRY TIMER '):continue
  v=line.decode().split();assert len(v)==1+2*(len(IDS)+len(WORDS)) and v[1::2]==list(IDS+WORDS)
  assert all(re.fullmatch('[0-9a-f]{16}',x) for x in v[2::2]);rows.append(dict(zip(IDS+WORDS,[int(x,16) for x in v[2::2]])))
 return validate(rows,image)


def audit(rows,image):
 """Measured source traces and architectural relations,with counters unmodified."""
 rows=validate(rows,image)
 for row in rows:
  timer=row['TIMER'];mode=row['MODE'];target=row['TARGET'];bit=(64,32768,65536)[timer];level=(1,3,5)[timer]
  if mode<2:
   assert row['IRQCC']==target+(8 if mode==0 else 9)
   assert row['MARKER']==(target-2 if mode==0 else 0)
   assert row['IRQPS']==(row['PS']|16|(level if level>1 else 0)) and row['EPS']==row['PS']
  else:
   assert row['T0']==target-5 and row['T1']==target+7
   assert [row[f'P{i}'] for i in range(11)]==[0]*5+[bit]*6
 return rows
