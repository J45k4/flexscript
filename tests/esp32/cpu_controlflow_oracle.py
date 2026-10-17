"""Independent GNU control-flow fixtures and linked target validation."""
from elf32_symbols import elf32_symbols,elf32_mapped

CONTROL_PATTERNS=('j-next','j-skip','beqz-taken','beqz-not-taken','bnez-taken','bnez-not-taken','beq-taken','bne-not-taken','call0-ret','callx0-ret','call0-ret.n','callx0-ret.n')
COUNTS=(0,1,2,4,8,16,32)
STRIDES=(3,6,6,3,6,3,6,3,3,3,3,3)
EXECUTED=(1,1,1,1,1,1,1,1,3,3,3,3)

def signed(value,bits):return value-(1<<bits) if value&(1<<(bits-1)) else value

def control_target_literal(image,pc):
 op=int.from_bytes(elf32_mapped(image,pc,3),'little')
 assert op&255==0xd1, 'GNU call target must use L32R a13'
 return ((pc+3)&~3)+((op>>8)-65536)*4

def generate_control_blocks():
 lines=['.global cc_pattern_set','.set cc_pattern_set,2'];table=[]
 for kind in range(12):
  for count in COUNTS:
   for align in range(4):
    suffix=f'{kind}_{count}_{align}';begin='cc_begin_'+suffix;end='cc_end_'+suffix;block='cc_block_'+suffix
    leaf='cc_fast_leaf' if kind>=10 else 'cc_full_leaf'
    lines += [block+':',f' movi a10,{begin}',' s32i a10,a2,16',f' movi a10,{end}',' s32i a10,a2,20','.global cc_target_'+suffix,'cc_target_'+suffix+':',f' movi a13,{leaf}','.begin no-transform',f' j .Lcc_aligned_{suffix}','.balign 16',f'.Lcc_aligned_{suffix}:']
    if align&1:lines.append(' nop.n')
    if align&2:lines.append(' nop')
    lines += ['.global '+begin,begin+':',' rsr a8,ccount']
    for repeat in range(count):
     target=f'.Lcc_next_{suffix}_{repeat}'
     if kind in (0,1):lines.append(' j '+target)
     elif kind==2:lines.append(' beqz a7,'+target)
     elif kind==3:lines.append(' beqz a12,'+target)
     elif kind==4:lines.append(' bnez a12,'+target)
     elif kind==5:lines.append(' bnez a7,'+target)
     elif kind==6:lines.append(' beq a7,a7,'+target)
     elif kind==7:lines.append(' bne a7,a7,'+target)
     elif kind in (8,10):lines.append(' call0 '+leaf)
     else:lines.append(' callx0 a13')
     if kind in (1,2,4,6):lines.append(' nop')
     lines.append(target+':')
    lines += ['.global '+end,end+':',' rsr a9,ccount',' j cc_done','.end no-transform'];table.append(' .word '+block)
 lines += ['.section .rodata.cc_table,"a"','.balign 4','cc_table:',*table]
 for name,ret in (('cc_full_leaf','ret'),('cc_fast_leaf','ret.n')):
  lines += ['.section .text.'+name+',"ax"','.balign 4','.global '+name,name+':','.begin no-transform',' addi a7,a7,1',' '+ret,'.end no-transform','.global '+name+'_end',name+'_end:']
 return lines

def control_layout(image):
 symbols=elf32_symbols(image);result={}
 for leaf,expected in (('cc_full_leaf','72c701800000'),('cc_fast_leaf','72c7010df0')):
  begin,end=symbols[leaf],symbols[leaf+'_end'];assert end-begin==len(bytes.fromhex(expected))
  assert elf32_mapped(image,begin,end-begin)==bytes.fromhex(expected), ('GNU leaf bytes',leaf)
 for kind in range(12):
  for count in COUNTS:
   firsts=[]
   for align in range(4):
    suffix=f'{kind}_{count}_{align}';begin=symbols['cc_begin_'+suffix];end=symbols['cc_end_'+suffix]
    assert end-begin==3+count*STRIDES[kind],('GNU branch block length',kind,count,align)
    assert elf32_mapped(image,begin,3)==bytes.fromhex('80ea03') and elf32_mapped(image,end,3)==bytes.fromhex('90ea03')
    leaf=symbols['cc_fast_leaf' if kind>=10 else 'cc_full_leaf']
    literal=control_target_literal(image,symbols['cc_target_'+suffix])
    assert int.from_bytes(elf32_mapped(image,literal,4),'little')==leaf,('GNU indirect target',kind,count,align)
    for repeat in range(count):
     pc=begin+3+repeat*STRIDES[kind];op=int.from_bytes(elf32_mapped(image,pc,3),'little');target=pc+STRIDES[kind]
     if kind in (0,1):assert op&63==6 and pc+4+signed(op>>6,18)==target,('GNU J target',kind,pc)
     elif kind in (2,3,4,5):
      assert op&255==(0x16 if kind in (2,3) else 0x56)
      assert (op>>8)&15==(7 if kind in (2,5) else 12)
      assert pc+4+signed(op>>12,12)==target
     elif kind in (6,7):
      assert op&65535==(0x1777 if kind==6 else 0x9777)
      assert pc+4+signed(op>>16,8)==target
     elif kind in (8,10):assert op&63==5 and (pc&~3)+4+signed(op>>6,18)*4==leaf,('GNU CALL0 target',kind,pc)
     else:assert op==0x000dc0,('GNU CALLX0 operand',kind,pc)
     if STRIDES[kind]==6:assert elf32_mapped(image,pc+3,3)==bytes.fromhex('f02000'),('GNU skipped NOP',kind,pc)
    result[kind,count,align]=(begin,end);firsts.append((begin+3)&3)
   assert set(firsts)=={0,1,2,3}
 return result
