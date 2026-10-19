#!/usr/bin/env python3
"""Observe an owned QEMU test VM; capture/rearm its Timer3 after a stall."""
import argparse, hashlib, json, socket, subprocess, time, os, sys
from pathlib import Path
p=argparse.ArgumentParser()
for key in ['qemu','image','elf','work']:p.add_argument('--'+key,type=Path,required=True)
p.add_argument('--runs',type=int,default=12)
p.add_argument('--repair-startup',action='store_true',help='temporarily boost only the owned VM main task to finish peer construction')
p.add_argument('--contention',action='store_true',help='bounded child-only contention on one CPU')
a=p.parse_args();assert all(x.is_file() for x in [a.qemu,a.image,a.elf]),"missing input";w=a.work.resolve();w.mkdir(parents=True,exist_ok=True)
if (w/'report.json').exists():raise RuntimeError('use fresh work directory')
def sha(p):
    with open(p,'rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
class RemoteMemory:
    # Use only the standard RSP memory packets, avoiding target register layouts.
    def __init__(self,port):
        self.socket=socket.create_connection(('127.0.0.1',port),timeout=5);self.trace=[]
    def packet(self,message):
        data=message.encode();self.socket.sendall(b'$'+data+b'#'+f'{sum(data)&255:02x}'.encode())
        while True:
            byte=self.socket.recv(1)
            if not byte:raise RuntimeError('RSP closed')
            if byte!=b'$':continue
            data=bytearray()
            while True:
                byte=self.socket.recv(1)
                if byte==b'#':break
                if not byte:raise RuntimeError('RSP truncated')
                data+=byte
            checksum=self.socket.recv(2)
            while len(checksum)<2:checksum+=self.socket.recv(2-len(checksum))
            assert sum(data)&255==int(checksum,16),'RSP checksum'
            self.socket.sendall(b'+');decoded=bytearray();i=0
            while i<len(data):
                if data[i]==42:
                    i+=1;decoded.extend(decoded[-1:]*(data[i]-29))
                elif data[i]==125:
                    i+=1;decoded.append(data[i]^32)
                else:decoded.append(data[i])
                i+=1
            reply=decoded.decode();self.trace.append(dict(command=message,reply=reply))
            if message!='?' and reply[:1] in ('T','S'):continue
            return reply
    def read(self,address,length):
        result=bytes.fromhex(self.packet(f'm{address:x},{length:x}'));assert len(result)==length;return result
    def word(self,address):return int.from_bytes(self.read(address,4),'little')
    def write(self,address,value):
        assert self.packet(f'M{address:x},4:{value.to_bytes(4,"little").hex()}')=='OK'
    def close(self):self.socket.close()
records=[]
for i in range(a.runs):
    d=w/f'r{i:02}';d.mkdir();flash=d/'flash.bin';flash.write_bytes(b'\xff'*4194304)
    with flash.open('r+b') as f:f.seek(4096);f.write(a.image.read_bytes())
    initial=sha(flash);uart=d/'uart.log';qpath=d/'q'
    with socket.socket() as probe:probe.bind(('127.0.0.1',0));port=probe.getsockname()[1]
    args=[str(a.qemu.resolve()),'-M','esp32','-display','none','-monitor','none','-qmp',f'unix:{qpath},server=on,wait=off','-gdb',f'tcp:127.0.0.1:{port}','-serial',f'file:{uart}','-drive',f'file={flash},if=mtd,format=raw','-nic','none','-no-reboot']
    q=None;reader=None;proc=None;load=[];trace=[];record={'index':i,'contention':a.contention}
    cpu=min(os.sched_getaffinity(0))
    def stop_load():
        for child in load:
            if child.poll() is None:child.terminate()
        for child in load:child.wait(timeout=3)
    with (d/'stderr.log').open('wb') as err:
        try:
            if a.contention:
                for worker in range(2):
                    load.append(subprocess.Popen([sys.executable,'-c',f'import os,time;os.sched_setaffinity(0,{{{cpu}}});end=time.monotonic()+50\nwhile time.monotonic()<end: pass'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL))
            proc=subprocess.Popen(args,preexec_fn=(lambda:os.sched_setaffinity(0,{cpu})) if a.contention else None,stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=err)
            until=time.monotonic()+5
            while not qpath.exists() and time.monotonic()<until:
                if proc.poll() is not None:raise RuntimeError('QEMU launch failure')
                time.sleep(.01)
            q=socket.socket(socket.AF_UNIX);q.settimeout(5);q.connect(str(qpath));reader=q.makefile('rb');trace.append(json.loads(reader.readline()))
            def cmd(name,arguments=None):
                value={'execute':name}
                if arguments is not None:value['arguments']=arguments
                q.sendall((json.dumps(value)+'\n').encode())
                while True:
                    result=json.loads(reader.readline());trace.append(result)
                    if 'return' in result:return result['return']
                    if 'error' in result:raise RuntimeError(result)
            def finished():
                return uart.exists() and b'PASS:' in uart.read_bytes()
            cmd('qmp_capabilities');until=time.monotonic()+2
            while not finished() and time.monotonic()<until:time.sleep(.02)
            record['completed_initially']=finished()
            stop_load()
            if a.contention and not finished():
                until=time.monotonic()+1
                while not finished() and time.monotonic()<until:time.sleep(.02)
                record['completed_after_load_removed']=finished()
            if not finished():
                cmd('stop');(d/'registers.log').write_text(cmd('human-monitor-command',{'command-line':'info registers'}))
                remote=RemoteMemory(port)
                try:
                    remote.packet('?');before=[remote.word(0x3ff60024+j*4) for j in range(9)];remote.write(0x3ff60030,0x80000000)
                    words=[remote.word(0x3ff60024+j*4) for j in range(9)];counter=words[1]|words[2]<<32;alarm=words[4]|words[5]<<32
                    enable=[remote.word(0x3ff60098+j*4) for j in range(4)];route=remote.word(0x3ff00150)
                    (d/'timer.bin').write_bytes(b''.join(x.to_bytes(4,'little') for x in words));(d/'state.bin').write_bytes(remote.read(0x3ffb0000,1024))
                    output=subprocess.check_output(['nm','-n',str(a.elf.resolve())],text=True);symbols={line.split()[2]:int(line.split()[0],16) for line in output.splitlines() if len(line.split())==3}
                    current=remote.word(symbols['esp_sdk_current']);task=current;tasks=[]
                    for step in range(3):
                        tasks.append(dict(address=task,data=remote.read(task,640).hex()));task=remote.word(task+536)
                        if task==current:break
                    state=remote.word(symbols['pt_state']);snapshot=dict(before_latch=before,timer=words,group=enable,route=route,tasks=tasks,round_state=remote.read(state,32).hex(),ticks=int.from_bytes(remote.read(symbols['esp_sdk_preempt_ticks'],8),'little'),switches=int.from_bytes(remote.read(symbols['esp_sdk_preempt_switches'],8),'little'))
                    (d/'snapshot.json').write_text(json.dumps(snapshot,indent=2)+'\n');record.update(timer_words=words,counter=counter,alarm=alarm,alarm_in_past=counter>alarm,group=enable,route=route)
                    if a.repair_startup:
                        main=remote.word(symbols['esp_sdk_tasks']);priority=remote.word(main+552)
                        assert len(tasks)==2 and priority==0 and snapshot['switches']==1,'not the startup starvation signature'
                        remote.write(main+552,5)
                    else:
                        target=counter+50000;remote.write(0x3ff60034,target&0xffffffff);remote.write(0x3ff60038,target>>32);remote.write(0x3ff60024,words[0]|1024)
                finally:
                    (d/'rsp.json').write_text(json.dumps(remote.trace,indent=2)+'\n');remote.close()
                if a.repair_startup:
                    cmd('cont');time.sleep(.05);cmd('stop');remote=RemoteMemory(port)
                    try:
                        remote.packet('?');record['ticks_after_priority_boost']=int.from_bytes(remote.read(symbols['esp_sdk_preempt_ticks'],8),'little');remote.write(main+552,priority)
                    finally:
                        (d/'startup-repair-rsp.json').write_text(json.dumps(remote.trace,indent=2)+'\n');remote.close()
                cmd('cont');until=time.monotonic()+2
                while not finished() and time.monotonic()<until:time.sleep(.02)
                record['completed_after_startup_repair' if a.repair_startup else 'completed_after_single_rearm']=finished()
            cmd('quit');proc.wait(timeout=5)
        finally:
            stop_load()
            if proc and proc.poll() is None:
                proc.terminate()
                try:proc.wait(timeout=3)
                except subprocess.TimeoutExpired:proc.kill();proc.wait()
            if reader:reader.close()
            if q:q.close()
            (d/'qmp.json').write_text(json.dumps(trace,indent=2)+'\n')
    record['flash_unchanged']=sha(flash)==initial;record['UART_sha256']=sha(uart);records.append(record)
    print(json.dumps(record),flush=True)
    (w/'report.json').write_text(json.dumps(dict(runs=records,image_sha256=sha(a.image),elf_sha256=sha(a.elf),qemu_sha256=sha(a.qemu),physical_hardware=False,emulator_changes=False),indent=2)+'\n')
