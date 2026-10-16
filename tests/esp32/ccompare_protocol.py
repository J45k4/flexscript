"""Independent GNU comparator experiment layout and raw captures."""
import re,struct
from elf32_symbols import elf32_symbols,elf32_mapped
ROWS=24
WORDS=('CC0','C0','C1','C2','P0','PCLEAN','TARGET','CCPRE','PPRE','CCPOST','PPOST','PINTCLR','PREWRITE','PALLCLR','CCEND','READBACK')
IDS=('TIMER','MODE','REPEAT')
def generate_blocks():
 result=[];names=[]
 for timer in range(3):
  for mode in range(4):
   name=f'ct_block_{timer}_{mode}';names.append(name)
   b=['.section .text.'+name+',"ax"','.balign 4','.global '+name,name+':']
   if mode==0:b+=['rsr a8,ccount','addi a9,a8,64']
   elif mode==1:b+=['movi a8,-32','wsr a8,ccount','esync','movi a9,16']
   else:b+=['movi a8,0x1000','wsr a8,ccount','esync','movi a9,'+('0x1080' if mode==2 else '0x1100')]
   b+=[f'wsr a9,ccompare{timer}','rsync','s32i a9,a3,24',f'rsr a10,ccompare{timer}','s32i a10,a3,60','rsr a10,ccount','s32i a10,a3,28','rsr a10,interrupt','s32i a10,a3,32']
   if mode>=2:b+=['movi a8,0x1100','wsr a8,ccount','esync']
   b+=['nop']*80
   b+=['rsr a10,ccount','s32i a10,a3,36','rsr a10,interrupt','s32i a10,a3,40','movi a11,1',f'slli a11,a11,{[6,15,16][timer]}','wsr a11,intclear','rsync','rsr a10,interrupt','s32i a10,a3,44',f'wsr a9,ccompare{timer}','rsync','rsr a10,interrupt','s32i a10,a3,48','movi a10,0x70000000','wsr a10,ccompare0','wsr a10,ccompare1','wsr a10,ccompare2','rsync','rsr a10,interrupt','s32i a10,a3,52','rsr a10,ccount','s32i a10,a3,56','j ct_restore']
   b += ['.global '+name+'_end',name+'_end:']
   b=[part for line in b for part in ({'movi a8,0x1000':['movi a8,1','slli a8,a8,12'],'movi a9,0x1080':['movi a9,264','slli a9,a9,4'],'movi a9,0x1100':['movi a9,272','slli a9,a9,4'],'movi a8,0x1100':['movi a8,272','slli a8,a8,4'],'movi a10,0x70000000':['movi a10,7','slli a10,a10,28']}.get(line,[line]))]
   result+=['.begin no-transform',*b,'.end no-transform']
 result+=['.section .rodata.ct_table,"a"','.balign 4','.global ct_table','ct_table:']+['.word '+n for n in names]
 return result

def layout(image):
 syms=elf32_symbols(image);assert all(k in syms for k in ('ct_measure','ct_mask_cpu','ct_restore','ct_ready_snapshot','ct_table'))
 assert elf32_mapped(image,syms['ct_mask_cpu'],6)==bytes.fromhex('50e413102000')
 for timer in range(3):
  for mode in range(4):
   i=timer*4+mode;name=f'ct_block_{timer}_{mode}';assert struct.unpack('<I',elf32_mapped(image,syms['ct_table']+i*4,4))[0]==syms[name]
   # Required selected-register writer,reader and clearing experiment in each block.
   code=elf32_mapped(image,syms[name],syms[name+'_end']-syms[name])
   assert bytes([0x90,240+timer,0x13]) in code and bytes([0xa0,240+timer,0x03]) in code
   assert bytes.fromhex('b0e313102000') in code
 return syms

def header(data,clock):
 matches=re.findall(rb'CCMP START CLOCK ([0-9a-f]{16}) SOURCE ([0-9a-f]{16}) PERIOD ([0-9a-f]{16}) DIV ([0-9a-f]{16}) ROMTICKS ([0-9a-f]{16})\r\n',data)
 assert len(matches)==1 and tuple(int(v,16) for v in matches[0])==((40,0,0,0,13) if clock==40 else (160,1,1,0,160))

def validate(rows):
 assert len(rows)==ROWS
 for i,row in enumerate(rows):
  assert tuple(row[k] for k in IDS)==(i//8,(i//2)%4,i%2)
  assert all(0<=row[k]<=0xffffffff for k in WORDS)
  assert row['READBACK']==row['TARGET']
  assert ((row['CCPOST']-row['CCPRE'])&0xffffffff)<1024 if row['MODE']<2 else row['CCPOST']>=0x1100
 return rows

def parse_ram(raw,image):
 layout(image);assert len(raw)==ROWS*64
 return validate([dict(zip(IDS,(i//8,(i//2)%4,i%2)),**dict(zip(WORDS,struct.unpack_from('<16I',raw,i*64)))) for i in range(ROWS)])

def parse(data,image,clock):
 layout(image);header(data,clock);assert b' FAIL' not in data
 assert data.count(f'CCMP COMPLETE CLOCK {clock:016x}\r\n'.encode())==1
 rows=[]
 for line in data.splitlines():
  if not line.startswith(b'CCMP TIMER '):continue
  tokens=line.decode().split();assert len(tokens)==1+2*(len(IDS)+len(WORDS))
  assert tokens[1::2]==list(IDS+WORDS)
  assert all(re.fullmatch('[0-9a-f]{16}',v) for v in tokens[2::2])
  rows.append(dict(zip(IDS+WORDS,[int(v,16) for v in tokens[2::2]])))
 return validate(rows)
