"""Independent GNU CCOUNT frame and linked-instruction validation."""
import re,struct
from elf32_symbols import elf32_symbols,elf32_mapped
from cpu_controlflow_oracle import control_layout,EXECUTED,STRIDES
COUNTS=(0,1,2,4,8,16,32)
PATTERNS=('nop','addi','rsr-ccount','wsr-ps','wsr-sar','rsync','wsr-ps-rsync','wsr-sar-rsync','rsil0','memw','s32i','l32i')
# GNU encodings for the explicit operands in cycle-oracle/measure.S.
BYTES=tuple(bytes.fromhex(v) for v in ('f02000','72c701','b0ea03','60e613','600313','102000','60e613102000','600313102000','b06000','c02000','726208','722208'))
FOLLOWER_PATTERNS=('ps-nop','ps-nop2','ps-nop3','ps-rsync-nop','sar-nop','sar-nop-rsync','sar-nop2-rsync','rsil-nop','rsil-rsync','rsil-nop2','ps-rsil','ps-rsr-ps')
FOLLOWER_BYTES=tuple(bytes.fromhex(v) for v in ('60e613f02000','60e613f02000f02000','60e613f02000f02000f02000','60e613102000f02000','600313f02000','600313f02000102000','600313f02000f02000102000','b06000f02000','b06000102000','b06000f02000f02000','60e613b06000','60e613b0e603'))


def pattern_set(image):
 value=elf32_symbols(image).get('cc_pattern_set',0)
 assert value in (0,1,2), 'unknown GNU pattern-set tag'
 return value


def pattern_bytes(image):
 return FOLLOWER_BYTES if pattern_set(image) else BYTES


KEYS=('PATTERN','COUNT','ALIGN','MASK','BLOCK','STOP','START','END','DELTA','PS','AFTERPS','VALUE','MEMORY','INTEN')
MARKER=b'CCOST COMPLETE CLOCK '

def layout(image):
 if pattern_set(image)==2:return control_layout(image)
 symbols=elf32_symbols(image);result={}
 for kind,pattern in enumerate(pattern_bytes(image)):
  for count in COUNTS:
   firsts=[]
   for align in range(4):
    begin=symbols[f'cc_begin_{kind}_{count}_{align}'];end=symbols[f'cc_end_{kind}_{count}_{align}']
    assert end-begin==3+count*len(pattern),('GNU block length',kind,count,align)
    assert elf32_mapped(image,begin,end-begin+3)==bytes.fromhex('80ea03')+pattern*count+bytes.fromhex('90ea03'),('GNU instruction bytes',kind,count,align)
    result[kind,count,align]=(begin,end);firsts.append((begin+3)&3)
   assert set(firsts)=={0,1,2,3}
 return result

def parse(data,image,clock,one_cycle=False):
 symbols=layout(image)
 start=f'CCOST START CLOCK {clock:016x} SOURCE '.encode();at=data.find(start)
 assert at>=0 and data.count(start)==1 and b' FAIL' not in data
 data=data[at:]
 header=re.match(rb'CCOST START CLOCK ([0-9a-f]{16}) SOURCE ([0-9a-f]{16}) PERIOD ([0-9a-f]{16}) DIV ([0-9a-f]{16}) ROMTICKS ([0-9a-f]{16})\r\n',data)
 assert header
 values=tuple(int(v,16) for v in header.groups())
 assert values==((40,0,0,0,13) if clock==40 else (160,1,1,0,160))
 assert data.endswith(MARKER+f'{clock:016x}\r\n'.encode())
 rows=re.findall(('CCOST '+' '.join(k+r' ([0-9a-f]{16})' for k in KEYS)+r'\r\n').encode(),data)
 wanted=[(kind,count,align,mask) for kind in range(12) for count in COUNTS for align in range(4) for mask in (0,15)]
 assert len(rows)==len(wanted)==672
 return validate([{k:int(v,16) for k,v in zip(KEYS,raw)} for raw in rows],symbols,one_cycle,pattern_set(image))


def parse_ram(data,image,one_cycle=False):
 assert len(data)==672*40
 identities=[(kind,count,align,mask) for kind in range(12) for count in COUNTS for align in range(4) for mask in (0,15)]
 rows=[dict(zip(KEYS,identity+words)) for identity,words in zip(identities,struct.iter_unpack('<10I',data))]
 return validate(rows,layout(image),one_cycle,pattern_set(image))


def validate(rows,symbols,one_cycle=False,set_id=0):
 wanted=[(kind,count,align,mask) for kind in range(12) for count in COUNTS for align in range(4) for mask in (0,15)]
 assert len(rows)==len(wanted)==672
 result=[]
 for f,identity in zip(rows,wanted):
  kind,count,align,mask=identity
  assert tuple(f[k] for k in ('PATTERN','COUNT','ALIGN','MASK'))==identity
  assert (f['BLOCK'],f['STOP'])==symbols[kind,count,align]
  assert f['START']<=0xffffffff and f['END']<=0xffffffff
  assert 0<f['DELTA']<1000000 and f['DELTA']==((f['END']-f['START'])&0xffffffff)
  assert f['PS']<=0xffffffff and (f['PS']&15)==mask and not (f['PS']&16)
  changes_level=(kind in (7,8,9,10) if set_id==1 else kind==8) if set_id!=2 else False
  after_mask=0 if changes_level and count else mask
  assert f['AFTERPS']==((f['PS']&~15)|after_mask) and f['INTEN']==0
  value=(count if kind>=8 else 0) if set_id==2 else (0 if set_id else (count if kind==1 else (0x12345678 if kind==11 and count else 0)))
  assert f['VALUE']==value
  assert f['MEMORY']==(0 if not set_id and kind==10 and count else 0x12345678)
  if one_cycle:assert f['DELTA']==1+count*(EXECUTED[kind] if set_id==2 else len((FOLLOWER_BYTES if set_id else BYTES)[kind])//3)
  result.append(f)
 return result


def validate_timing(rows,image,profile):
 """Check only the two measured GNU families, independently of CPU code."""
 assert profile in ('functional','lx6'), 'unknown CPU timing profile'
 family=pattern_set(image)
 for row in rows:
  kind,count=row['PATTERN'],row['COUNT']
  expected=1+count*(EXECUTED[kind] if family==2 else len((FOLLOWER_BYTES if family else BYTES)[kind])//3)
  if profile=='lx6':
   if family==2:
    expected=1
    for i in range(count):
     pc=row['BLOCK']+3+i*STRIDES[kind]
     if kind in (3,5,7):expected+=1
     elif kind>=8:expected+=9+bool((pc+3)&2)
     else:expected+=4+bool((pc+STRIDES[kind])&2)
   elif family:
    expected=1+5*count
    if kind==4:expected=1+2*count
    if kind in (7,8):expected=3*count if count else 1
    if kind==9:expected=1+3*count
    if kind in (10,11):expected=1+6*count
   else:
    expected=1+count
    if kind in (3,6,7):expected=1+5*count
    if kind==8 and count:expected=3*count-1
  assert row['DELTA']==expected, ('CPU timing',profile,family,kind,count,row['DELTA'],expected)
 return rows
