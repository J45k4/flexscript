#!/usr/bin/env python3
"""Decode real emitted Xtensa instructions, exercise independent UART states.

GNU objdump supplies ISA decoding. The small executor below models registers,
PS and documented FIFO-count/state fields; it is not part of firmware.
"""
import argparse,copy,json,re,struct,subprocess,tempfile
from pathlib import Path
MASK=2**32-1
WORD=0x8877665544332211

def instructions(objdump,path):
    text=subprocess.check_output([objdump,'-d',str(path)],text=True);result={}
    for line in text.splitlines():
        m=re.match(r'^\s*([0-9a-f]+):\s+[0-9a-f]+\s+(\S+)\s*(.*?)\s*$',line)
        if m:result[int(m[1],16)]=(m[2],[part.strip() for part in m[3].split(',')])
    return result

def start(code,reading):
    shift='0' if reading else '16'
    for pc,(name,args) in code.items():
        if name=='extui' and args[:3]==['a6','a6',shift]:
            first=pc-6
            if reading and code.get(pc-9,('',[]))[0]=='rsil':first=pc-9
            return first
    raise AssertionError('UART status sequence not found')

def execute(code,reading,classic,state,initial_ps):
    pc=start(code,reading);entry=pc;r=[0]*16;r[8]=0x3ff40000 if classic else 0x60000000;r[2]=0 if reading else WORD&MASK;r[3]=0 if reading else WORD>>32
    ps=initial_ps;count=0;polls=0;last=0;output=bytearray();wanted=WORD.to_bytes(8,'little');empty_loops=0
    def register(name):assert re.fullmatch(r'a(?:[0-9]|1[0-5])',name),name;return int(name[1:])
    def value(name):return r[register(name)]
    def number(text):return int(text.split()[0],0)
    for step in range(3000):
        assert pc in code,('unknown PC',hex(pc));name,args=code[pc];next_pc=pc+3
        if name in ('memw','rsync'):pass
        elif name=='rsil':dest=register(args[0]);r[dest]=ps;ps=(ps&~15)|number(args[1])
        elif name=='wsr.ps':ps=value(args[0])
        elif name=='movi':r[register(args[0])]=number(args[1])&MASK
        elif name=='extui':r[register(args[0])]=(value(args[1])>>number(args[2]))&((1<<number(args[3]))-1)
        elif name=='slli':r[register(args[0])]=(value(args[1])<<number(args[2]))&MASK
        elif name=='or':
            r[register(args[0])]=value(args[1])|value(args[2])
            if reading and count==8:
                assert r[2]|(r[3]<<32)==WORD and ps==initial_ps,(hex(r[2]|(r[3]<<32)),hex(ps),hex(initial_ps))
                return empty_loops
        elif name=='l32i':
            address=value(args[1])+number(args[2]);dest=register(args[0]);polls+=int(address==r[8]+28)
            if address==r[8]+28:
                if reading:last=((state<<8) if classic else 0)|(1 if polls>3 else 0)
                else:
                    busy=127 if count<8 and polls<=3 else 0
                    tx_state=state if count<8 or polls<=3 else 0
                    last=(busy<<16)|((tx_state<<24) if classic else 0)
                r[dest]=last
            elif address==r[8]:
                assert reading and polls>3 and count<8,('empty FIFO read',state,polls,count)
                assert not classic or ps&15==15,('unmasked FIFO read',hex(ps))
                r[dest]=wanted[count];count+=1;polls=0
            else:raise AssertionError(('unexpected read',hex(address)))
        elif name=='s32i':
            assert not reading and value(args[1])+number(args[2])==r[8]
            assert polls>3,('write while FIFO full',state,polls,count,hex(pc),last,r[6],r[9])
            output.append(value(args[0])&255);count+=1;polls=0
        elif name in ('beq','bne','bltu','bgeu'):
            a,b=value(args[0]),value(args[1]);take={'beq':a==b,'bne':a!=b,'bltu':a<b,'bgeu':a>=b}[name]
            if take:
                next_pc=number(args[2])
                if not reading and count==8 and name=='beq':
                    assert output==wanted and (not classic or last==0) and r[2]|(r[3]<<32)==WORD
                    assert ps==initial_ps;return empty_loops
        elif name=='j':
            next_pc=number(args[0])
            if next_pc<=pc:
                if reading:assert ps==initial_ps,('PS not restored while polling',hex(ps),hex(initial_ps));empty_loops+=1
        else:raise AssertionError(('unexpected instruction',name,args,hex(pc)))
        pc=next_pc
    raise AssertionError(('UART loop did not progress',reading,classic,state,count,polls,hex(pc),hex(entry)))

def main():
    p=argparse.ArgumentParser();p.add_argument('--compiler',required=True);p.add_argument('--objdump',required=True);p.add_argument('--report',type=Path,required=True);a=p.parse_args();checks=0;artifacts={}
    with tempfile.TemporaryDirectory(prefix='flexscript-word-uart-model-') as tmp:
        root=Path(tmp)
        for classic,target in ((True,'esp32-elf'),(False,'esp32s3-elf')):
            for reading in (True,False):
                source=root/'word.seta';elf=root/'word.elf'
                source.write_text('plugin esp32.uart v1 {} fn main()->i32{return '+('read_word()' if reading else 'write_word(-8613303245920329199)')+'}')
                subprocess.run([a.compiler,'--target',target,str(source),'-o',str(elf)],check=True,capture_output=True)
                code=instructions(a.objdump,elf);artifacts[target+('-rx' if reading else '-tx')]=len(code)
                for state in range(16 if reading and classic else 15 if classic else 1):
                    for ps in (0,5,0x40020):execute(code,reading,classic,state,ps);checks+=1
                if classic and reading:
                    # The independent executor must detect each historic fault.
                    bad=copy.deepcopy(code)
                    for pc,(name,args) in bad.items():
                        if name=='extui' and args[:3]==['a6','a6','0']:args[3]='10'
                    try:execute(bad,True,True,1,0)
                    except AssertionError:checks+=1
                    else:raise AssertionError('wide classic RX mask control escaped')
                    bad=copy.deepcopy(code)
                    for pc,(name,args) in list(bad.items()):
                        if name=='rsil':bad[pc]=('memw',[])
                    try:execute(bad,True,True,0,0)
                    except AssertionError:checks+=1
                    else:raise AssertionError('unmasked FIFO control escaped')
    report={'checks':checks,'scope':'actual emitted Xtensa instructions decoded by GNU;16 classic RX states,15 TX states,3 saved PS values, empty/full polling, exact8-byte values,2 broken-instruction controls','primary':'https://github.com/espressif/esp-idf/blob/v5.5.1/components/soc/esp32/register/soc/uart_reg.h','artifacts_instruction_counts':artifacts}
    a.report.write_text(json.dumps(report,indent=2)+'\n');print(f'PASS: UART emitter independent register/PS model: {checks} checks')
if __name__=='__main__':main()
