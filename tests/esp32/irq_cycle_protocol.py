"""GNU software-IRQ7 fixtures and raw entry/return observation validation."""
import re,struct
from elf32_symbols import elf32_symbols,elf32_mapped
ROWS=384
WORDS=('START','IRQCC','RETCC','END','BEFOREPS','IRQPS','EPC','RESUME','INTEN','PENDING','SEEN','VBASE','TRIGGER','AFTERPS','AFTERPENDING','AFTERINTEN')
IDS=('PROFILE','GATE','TALIGN','RALIGN','REPEAT')
KEYS=IDS+WORDS

def has_marker(image):
 tag=elf32_symbols(image)['iq_family_tag'];assert tag in (0x49525131,0x49525132)
 return tag==0x49525132

def record_words(image):return WORDS+('FOLLOWER',) if has_marker(image) else WORDS

def identities():return [(p,g,t,r,n) for p in range(4) for g in range(3) for t in range(4) for r in range(4) for n in range(2)]

def generate_blocks(marker=False):
 lines=['.global iq_family_tag','.set iq_family_tag,'+('0x49525132' if marker else '0x49525131')];table=[]
 for profile in range(4):
  for gate in range(3):
   for trigger_align in range(4):
    for resume_align in range(4):
     suffix=f'{profile}_{gate}_{trigger_align}_{resume_align}';begin='iq_begin_'+suffix;trigger='iq_trigger_'+suffix;resume='iq_resume_'+suffix;tail='iq_tail_'+suffix;block='iq_block_'+suffix
     lines += [block+':',f' movi a6,iq_vectors_{profile}',' wsr a6,vecbase',' rsync',' s32i a6,a3,44',f' movi a7,{trigger}',' s32i a7,a3,48',f' movi a7,{resume}',' s32i a7,a3,28']
     if marker:lines+=['.begin no-transform','.global iq_marker_zero_'+suffix,'iq_marker_zero_'+suffix+':',' movi a10,0','.end no-transform']
     if gate==1:lines+=[' movi a5,15',' or a5,a4,a5',' wsr a5,ps']
     else:lines+=[' wsr a4,ps']
     if gate in (0,1):lines+=[' wsr a11,intenable']
     if gate in (1,2):lines+=[' wsr a11,intset']
     lines+=[' rsync',*[' nop']*8,' rsr a6,ps',' s32i a6,a3,16',' movi a7,0',' s32i a7,a3,40','.begin no-transform',f' j .Liq_aligned_{suffix}','.balign 16',f'.Liq_aligned_{suffix}:']
     if trigger_align&1:lines+=[' nop.n']
     if trigger_align&2:lines+=[' nop']
     lines+=['.global '+begin,begin+':',' rsr a8,ccount','.global '+trigger,trigger+':',(' wsr a11,intset',' wsr a4,ps',' wsr a11,intenable')[gate],*([' addi a10,a10,1'] if marker else [' nop'])*16,'.global '+tail,tail+':',' j iq_timeout','.balign 16']
     if resume_align&1:lines+=[' nop.n']
     if resume_align&2:lines+=[' nop']
     lines+=['.global '+resume,resume+':',' rsr a9,ccount','.end no-transform',' s32i a8,a3,0',' s32i a12,a3,8',' s32i a9,a3,12',' rsr a6,ps',' s32i a6,a3,52',' rsr a6,interrupt',' s32i a6,a3,56',' rsr a6,intenable',' s32i a6,a3,60',' j iq_done'];table+=[' .word '+block]
 lines+=['.section .rodata.iq_table,"a"','.balign 4','iq_table:',*table]
 for profile in range(4):
  lines+=['.section .text.iq_vectors_'+str(profile)+',"ax"','.balign 1024','.global iq_vectors_'+str(profile),'iq_vectors_'+str(profile)+':','.space 0x300','.begin no-transform']
  for level in (0x300,0x340):
   if level==0x340:lines+=['.space 0x340-(.-iq_vectors_'+str(profile)+')']
   if profile==0:lines+=[' rsr a6,ccount',' j iq_cleanup']
   else:lines+=[' j iq_handler_'+str(profile)]
  if profile:
   lines+=['.space '+('0x402' if profile==3 else '0x400')+'-(.-iq_vectors_'+str(profile)+')','.global iq_handler_'+str(profile),'iq_handler_'+str(profile)+':']
   if profile==2:
    lines+=[' addi a1,a1,-80',' s32i a0,a1,0']
    lines += [f' s32i a{reg},a1,{4*reg}' for reg in range(2,16)]
   lines+=['.global iq_counter_'+str(profile),'iq_counter_'+str(profile)+':',' rsr a6,ccount',' j iq_cleanup']
  lines+=['.end no-transform']
 lines+=['.section .text.iq_cleanup,"ax"','.balign 4','.global iq_cleanup','iq_cleanup:',' s32i a6,a3,4',' rsr a6,ps',' s32i a6,a3,20',' rsr a6,epc1',' s32i a6,a3,24',' rsr a6,intenable',' s32i a6,a3,32',' rsr a6,interrupt',' s32i a6,a3,36',' l32i a6,a3,40',' addi a6,a6,1',' s32i a6,a3,40',' wsr a11,intclear',' l32i a6,a3,28',' wsr a6,epc1',' rsync',*[' nop']*8,' rsr a6,vecbase',' movi a7,iq_vectors_2',' bne a6,a7,.Liq_no_restore']
 if marker:
  at=lines.index('iq_cleanup:')+2;lines[at:at]=['.begin no-transform','.global iq_marker_capture','iq_marker_capture:',' s32i a10,a3,64','.end no-transform']
 lines += [f' l32i a{reg},a1,{4*reg}' for reg in range(2,16)]
 lines+=[' l32i a0,a1,0',' addi a1,a1,80','.Liq_no_restore:','.begin no-transform','.global iq_return_stamp','iq_return_stamp:',' rsr a12,ccount','.global iq_rfe','iq_rfe:',' rfe','.end no-transform']
 return lines

def op3(image,pc):return int.from_bytes(elf32_mapped(image,pc,3),'little')
def j_target(image,pc):
 op=op3(image,pc);assert op&63==6;delta=op>>6
 if delta&131072:delta-=262144
 return pc+4+delta

def layout(image):
 symbols=elf32_symbols(image);marker=has_marker(image);result={}
 if marker:assert op3(image,symbols['iq_marker_capture'])==0x1063a2
 assert elf32_mapped(image,symbols['iq_return_stamp'],6)==bytes.fromhex('c0ea03003000')
 for profile in range(4):
  vector=symbols[f'iq_vectors_{profile}'];assert vector%1024==0
  for offset in (0x300,0x340):
   if profile==0:
    assert op3(image,vector+offset)==0x03ea60 and j_target(image,vector+offset+3)==symbols['iq_cleanup']
   else:assert j_target(image,vector+offset)==symbols[f'iq_handler_{profile}']
  if profile:
   handler=symbols[f'iq_handler_{profile}'];counter=symbols[f'iq_counter_{profile}'];assert handler-vector==(0x402 if profile==3 else 0x400)
   if profile==2:
    assert op3(image,handler)==0xb0c112
    registers=[0,*range(2,16)]
    for i,reg in enumerate(registers):assert op3(image,handler+3+i*3)==((reg<<16)|0x6102|(reg<<4))
   assert counter-handler==(48 if profile==2 else 0) and op3(image,counter)==0x03ea60
  taligns=[];raligns=[]
  for gate in range(3):
   for ta in range(4):
    for ra in range(4):
     suffix=f'{profile}_{gate}_{ta}_{ra}';begin=symbols['iq_begin_'+suffix];trigger=symbols['iq_trigger_'+suffix];resume=symbols['iq_resume_'+suffix];tail=symbols['iq_tail_'+suffix]
     assert trigger==begin+3 and tail==trigger+51
     assert op3(image,begin)==0x03ea80 and op3(image,trigger)==(0x13e2b0,0x13e640,0x13e4b0)[gate]
     assert elf32_mapped(image,trigger+3,48)==bytes.fromhex('a2ca01' if marker else 'f02000')*16 and j_target(image,tail)==symbols['iq_timeout']
     if marker:assert op3(image,symbols['iq_marker_zero_'+suffix])==0x00a0a2
     assert op3(image,resume)==0x03ea90
     result[profile,gate,ta,ra]=(vector,begin,trigger,tail,resume);taligns.append(trigger&3);raligns.append(resume&3)
  assert set(taligns)==set(raligns)=={0,1,2,3}
 return result

def validate(rows,image):
 locations=layout(image);wanted=identities();assert len(rows)==len(wanted)==ROWS
 for row,identity in zip(rows,wanted):
  assert tuple(row[k] for k in IDS)==identity
  profile,gate,ta,ra,repeat=identity;vector,begin,trigger,tail,resume=locations[profile,gate,ta,ra]
  assert row['VBASE']==vector and row['TRIGGER']==trigger and row['RESUME']==resume
  assert trigger<=row['EPC']<=tail and (row['EPC']-trigger)%3==0
  assert (row['BEFOREPS']&31)==(15 if gate==1 else 0)
  assert row['IRQPS']==((row['BEFOREPS']&~15)|16) and row['AFTERPS']==(row['BEFOREPS']&~15)
  assert row['INTEN']==row['AFTERINTEN']==128 and row['PENDING']&128 and not row['AFTERPENDING']&128 and row['SEEN']==1
  if has_marker(image):assert 0<=row['FOLLOWER']<=16
  assert all(0<=row[k]<=0xffffffff for k in record_words(image)), 'word outside32bit range'
  for start,end in (('START','IRQCC'),('IRQCC','RETCC'),('RETCC','END')):assert 0<((row[end]-row[start])&0xffffffff)<1000000
 for previous,current in zip(rows,rows[1:]):assert 0<((current['START']-previous['END'])&0xffffffff)<0x80000000, 'nonchronological IRQ records'
 return rows

def parse_ram(data,image):
 words=record_words(image);size=len(words)*4;assert len(data)==ROWS*size
 return validate([dict(zip(IDS+words,identity+values)) for identity,values in zip(identities(),struct.iter_unpack('<'+str(len(words))+'I',data))],image)

def header(data,clock):
 match=re.fullmatch(rb'IRQC START CLOCK ([0-9a-f]{16}) SOURCE ([0-9a-f]{16}) PERIOD ([0-9a-f]{16}) DIV ([0-9a-f]{16}) ROMTICKS ([0-9a-f]{16})\r\n',data);assert match
 assert tuple(int(v,16) for v in match.groups())==((40,0,0,0,13) if clock==40 else (160,1,1,0,160))

def parse(data,image,clock):
 marker=f'IRQC START CLOCK {clock:016x} SOURCE '.encode();at=data.find(marker);assert at>=0 and data.count(marker)==1 and b' FAIL' not in data
 data=data[at:];first=data.index(b'\r\n')+2;header(data[:first],clock)
 assert data.endswith(f'IRQC COMPLETE CLOCK {clock:016x}\r\n'.encode())
 pattern=('IRQC '+' '.join(k+r' ([0-9a-f]{16})' for k in IDS+record_words(image))+r'\r\n').encode();matches=re.findall(pattern,data);assert len(matches)==ROWS
 return validate([{k:int(v,16) for k,v in zip(IDS+record_words(image),raw)} for raw in matches],image)
