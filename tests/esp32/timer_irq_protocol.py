"""GNU timer priority vectors and raw architectural observations."""
import re,struct
from elf32_symbols import elf32_symbols,elf32_mapped
ROWS=20
HEAD=('CC0','CCEND','BEFOREPS','AFTERPS','PENDING','INTEN','COUNT','VBASE','TRIGGER','RESUME','MARKER','PHASE','CAUSE','FINALCAUSE','BASEPS','SELECTOR')
EVENT=('LEVEL','CC','PS','EPS','EPC','PENDING','INTEN','CAUSE','MARKER','VBASE','COMPARE','ACKPENDING','PHASE','NESTED','RETCC','TAG')
WORDS=HEAD+tuple(f'E{i}_{k}' for i in range(3) for k in EVENT)
IDS=('CASE','REPEAT')
ORDERS=((1,),(3,),(5,),(1,),(3,),(5,),(5,3,1),(3,5),(5,3),(5,3,1))
def const(reg,n):
 if n==0x70000000:return [f'movi {reg},7',f'slli {reg},{reg},28']
 if n==0x5449:return [f'movi {reg},0x544',f'slli {reg},{reg},4',f'addi {reg},{reg},9']
 if n in (0x20000000,0x30000000):return [f'movi {reg},{n>>28}',f'slli {reg},{reg},28']
 if n in (64,32768,65536):return [f'movi {reg},1',f'slli {reg},{reg},{n.bit_length()-1}']
 if n in (0x18000,0x18040):
  return [f'movi {reg},3',f'slli {reg},{reg},15']+([f'addi {reg},{reg},64'] if n==0x18040 else [])
 return [f'movi {reg},{n}']
def generate_blocks():
 out=[];table=[]
 for case in range(10):
  label=f'ti_case_{case}';table.append(label);mask=[64,32768,65536][case%3] if case<6 else (0x18040 if case in (6,9) else 0x18000)
  selected=[case%3] if case<6 else ([0,1,2] if case in (6,9) else ([1] if case==7 else [1,2]))
  wait=3<=case<6
  out += ['.section .text.'+label+',"ax"','.balign 4','.global '+label,label+':',*const('a5',mask),'wsr a5,intenable','rsync',f'movi a5,ti_gate_{case}','s32i a5,a3,32',f'movi a5,ti_after_{case}','s32i a5,a3,36','movi a10,0','l32i a7,a3,56']
  if wait:
   out += ['movi a5,15','or a5,a7,a5','wsr a5,ps','rsync','rsr a8,ccount','addi a9,a8,127']
  else:out += const('a9',0x20000000)
  for timer in selected:out += [f'wsr a9,ccompare{timer}']
  out += ['rsync']
  if not wait:out += ['wsr a9,ccount','esync']
  # Keep the pending condition settled before PS gate;WAITI instead arms ahead.
  if not wait:out += ['nop']*8
  if case==8:out += ['movi a5,16','or a7,a7,a5']
  if case==9:out += ['movi a5,3','or a7,a7,a5']
  out += ['s32i a7,a3,8','.begin no-transform',f'.global ti_start_{case}',f'ti_start_{case}:','rsr a8,ccount','s32i a8,a3,0',f'.global ti_gate_{case}',f'ti_gate_{case}:',('waiti 0' if wait else 'wsr a7,ps'),f'.global ti_after_{case}',f'ti_after_{case}:',*['addi a10,a10,1']*32,'.end no-transform']
  if case in (8,9):
   out += ['movi a5,1','s32i a5,a3,44','l32i a7,a3,56','.begin no-transform',f'.global ti_release_{case}',f'ti_release_{case}:','wsr a7,ps',*['addi a10,a10,1']*32,'.end no-transform']
  out += ['movi a5,0','wsr a5,intenable','rsil a7,15','s32i a7,a3,12','rsr a5,interrupt','s32i a5,a3,16','rsr a5,intenable','s32i a5,a3,20','s32i a10,a3,40','rsr a5,exccause','s32i a5,a3,52','rsr a5,ccount','s32i a5,a3,4','j ti_done']
 out+=['.section .rodata.ti_table,"a"','.balign 4','.global ti_table','ti_table:']+['.word '+n for n in table]
 out+=['.section .text.ti_vectors,"ax"','.balign 1024','.global ti_vectors','ti_vectors:']
 for offset,level in [(0x1c0,3),(0x240,5),(0x300,1),(0x340,1)]:
  out += [f'.space {offset}-(.-ti_vectors)','.begin no-transform','rsr a6,ccount',f'j ti_handler_{level}','.end no-transform']
 for timer,level in enumerate((1,3,5)):
  name=f'ti_handler_{level}'
  out += ['.section .text.'+name+',"ax"','.balign 4','.global '+name,name+':','l32i a7,a3,24','movi a5,3',f'bltu a7,a5,.Lti_record_{level}','j ti_fail',f'.Lti_record_{level}:','slli a4,a7,6','addi a4,a4,64','add a4,a3,a4','addi a7,a7,1','s32i a7,a3,24','s32i a6,a4,4',f'movi a5,{level}','s32i a5,a4,0','rsr a5,ps','s32i a5,a4,8']
  out += (['l32i a5,a3,56'] if level==1 else [f'rsr a5,eps{level}'])+['s32i a5,a4,12',f'rsr a5,epc{level}','s32i a5,a4,16','rsr a5,interrupt','s32i a5,a4,20','rsr a5,intenable','s32i a5,a4,24','rsr a5,exccause','s32i a5,a4,28','s32i a10,a4,32','rsr a5,vecbase','s32i a5,a4,36',f'rsr a5,ccompare{timer}','s32i a5,a4,40',*const('a5',0x70000000),f'wsr a5,ccompare{timer}','rsync','rsr a5,interrupt','s32i a5,a4,44','l32i a5,a3,44','s32i a5,a4,48']
  if level==3:
   out += ['l32i a5,a3,60','movi a6,7','bne a5,a6,.Lti_no_nested',*const('a6',0x30000000),'wsr a6,ccompare2','rsync','.begin no-transform','.global ti_nested_trigger','ti_nested_trigger:','wsr a6,ccount','esync','.global ti_nested_resume','ti_nested_resume:','.end no-transform','addi a4,a3,64','movi a5,1','s32i a5,a4,52','.Lti_no_nested:']
  out += ['rsr a5,ccount','s32i a5,a4,56',*const('a5',0x5449),'s32i a5,a4,60','.begin no-transform',f'.global ti_return_{level}',f'ti_return_{level}:',('rfe' if level==1 else f'rfi {level}'),'.end no-transform']
 return out

def op3(image,pc):return int.from_bytes(elf32_mapped(image,pc,3),'little')
def j_target(image,pc):
 op=op3(image,pc);assert op&63==6;d=op>>6
 if d&131072:d-=262144
 return pc+4+d

def layout(image):
 s=elf32_symbols(image);assert s['ti_vectors']%1024==0
 assert elf32_mapped(image,s['ti_mask_cpu'],6)==bytes.fromhex('50e413102000')
 for offset,level in [(0x1c0,3),(0x240,5),(0x300,1),(0x340,1)]:
  assert op3(image,s['ti_vectors']+offset)==0x03ea60
  assert j_target(image,s['ti_vectors']+offset+3)==s[f'ti_handler_{level}']
 for level in (1,3,5):assert op3(image,s[f'ti_return_{level}'])==(0x003000 if level==1 else 0x003010|(level<<8))
 for case in range(10):
  assert struct.unpack('<I',elf32_mapped(image,s['ti_table']+case*4,4))[0]==s[f'ti_case_{case}']
  gate=s[f'ti_gate_{case}'];assert op3(image,gate)==(0x007000 if 3<=case<6 else 0x13e670)
  assert s[f'ti_after_{case}']==gate+3
 return s

def header(data,clock):
 m=re.findall(rb'TIMIRQ START CLOCK ([0-9a-f]{16}) SOURCE ([0-9a-f]{16}) PERIOD ([0-9a-f]{16}) DIV ([0-9a-f]{16}) ROMTICKS ([0-9a-f]{16})\r\n',data)
 assert len(m)==1 and tuple(int(v,16) for v in m[0])==((40,0,0,0,13) if clock==40 else (160,1,1,0,160))

def validate(rows,image):
 s=layout(image);assert len(rows)==ROWS
 for i,row in enumerate(rows):
  case=i//2;assert (row['CASE'],row['REPEAT'])==(case,i%2)
  assert all(0<=row[k]<=0xffffffff for k in WORDS)
  assert row['SELECTOR']==case and row['VBASE']==s['ti_vectors'] and row['TRIGGER']==s[f'ti_gate_{case}'] and row['RESUME']==s[f'ti_after_{case}']
  assert row['COUNT']<=3
  # Structural capture proof only;measured order/context is audited separately.
  for event in range(row['COUNT']):assert row[f'E{event}_TAG']==0x5449 and row[f'E{event}_LEVEL'] in (1,3,5)
  for event in range(row['COUNT'],3):assert all(row[f'E{event}_{k}']==0 for k in EVENT)
 return rows

def parse_ram(raw,image):
 assert len(raw)==ROWS*256
 return validate([dict(zip(IDS,(i//2,i%2)),**dict(zip(WORDS,struct.unpack_from('<64I',raw,i*256)))) for i in range(ROWS)],image)

def parse(data,image,clock):
 header(data,clock);assert b' FAIL' not in data and data.count(f'TIMIRQ COMPLETE CLOCK {clock:016x}\r\n'.encode())==1
 rows=[]
 for line in data.splitlines():
  if not line.startswith(b'TIMIRQ CASE '):continue
  v=line.decode().split();assert len(v)==1+2*(len(IDS)+len(WORDS)) and v[1::2]==list(IDS+WORDS)
  assert all(re.fullmatch('[0-9a-f]{16}',x) for x in v[2::2]);rows.append(dict(zip(IDS+WORDS,[int(x,16) for x in v[2::2]])))
 return validate(rows,image)


def audit(rows,image):
 """Check observed context/ack/order against configured timer sources and GNU PCs."""
 rows=validate(rows,image);symbols=layout(image)
 for row in rows:
  case=row['CASE'];order=ORDERS[case];base=row['BASEPS'];assert row['COUNT']==len(order)
  assert row['AFTERPS']==base and row['PENDING']==row['INTEN']==0
  assert row['MARKER']==(64 if case in (8,9) else 32)
  pending=(1<<[6,15,16][case%3]) if case<6 else (0x18040 if case in (6,9) else (32768 if case==7 else 0x18000))
  for i,level in enumerate(order):
   key=lambda k:f'E{i}_{k}'
   assert row[key('LEVEL')]==level and row[key('PS')]==(base|16|(level if level>1 else 0))
   eps=base
   if case==7 and i==1:eps=base|19
   elif case==8 and i==0:eps=base|16
   elif case==9 and i==0:eps=base|3
   assert row[key('EPS')]==eps and row[key('VBASE')]==row['VBASE']
   if case==7 and i==1:pending=65536
   assert row[key('PENDING')]==pending
   bit={1:64,3:32768,5:65536}[level];pending &= ~bit
   assert row[key('ACKPENDING')]==pending
   expected_marker=32 if case in (8,9) and i>0 else 0
   assert row[key('MARKER')]==expected_marker and row[key('PHASE')]==(1 if expected_marker else 0)
   assert row[key('NESTED')]==(1 if case==7 and i==0 else 0)
   epc=row['RESUME']
   if case==7 and i==1:epc=symbols['ti_nested_trigger']+3
   elif case in (8,9) and i>0:epc=symbols[f'ti_release_{case}']+3
   assert row[key('EPC')]==epc
   assert row[key('CAUSE')]==(4 if level==1 else row['CAUSE'])
 return rows
