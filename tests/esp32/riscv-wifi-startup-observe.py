#!/usr/bin/env python3
"""Observe the real pinned C3 PHY status wait in unmodified stock QEMU.
No RF/startup-success or physical-hardware claim; never writes MMIO to unblock it.
"""
import argparse,hashlib,json,os,re,select,struct,subprocess,time
from pathlib import Path

def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()

class QMP:
    def __init__(self,reader,writer):
        self.reader=reader;self.writer=writer;self.pending=b'';self.serial=0;self.events=[]

    def line(self,deadline):
        while b'\n' not in self.pending:
            remaining=deadline-time.monotonic()
            if remaining<=0:raise TimeoutError('QMP observation timed out')
            if not select.select([self.reader],[],[],remaining)[0]:continue
            block=os.read(self.reader.fileno(),65536)
            if not block:raise EOFError('QMP closed')
            self.pending+=block
        line,self.pending=self.pending.split(b'\n',1)
        return json.loads(line)

    def request(self,command,args=None):
        self.serial+=1;row=dict(execute=command,id=self.serial)
        if args is not None:row['arguments']=args
        self.writer.write(json.dumps(row).encode()+b'\n');self.writer.flush()
        deadline=time.monotonic()+5
        while True:
            reply=self.line(deadline);self.events.append(reply)
            if reply.get('id')==self.serial:
                if 'error' in reply:raise RuntimeError(reply['error'])
                return reply.get('return')

def function(data,name):
 at=struct.unpack_from('<I',data,32)[0];count=struct.unpack_from('<H',data,48)[0];rows=[struct.unpack_from('<10I',data,at+i*40) for i in range(count)]
 for sym in rows:
  if sym[1]!=2:continue
  strings=rows[sym[6]];strings=data[strings[4]:strings[4]+strings[5]]
  for p in range(sym[4],sym[4]+sym[5],16):
   n,value,size,info,other,section=struct.unpack_from('<IIIBBH',data,p)
   if strings[n:].split(b'\0',1)[0].decode()!=name:continue
   row=rows[section];offset=row[4]+value-row[3];return value,data[offset:offset+size]
 raise AssertionError('missing pinned PHY function '+name)

def main():
 p=argparse.ArgumentParser();p.add_argument('--qemu',required=True,type=Path);p.add_argument('--image',required=True,type=Path);p.add_argument('--elf',required=True,type=Path);p.add_argument('--work',required=True,type=Path);a=p.parse_args();w=a.work.resolve();w.mkdir(parents=True,exist_ok=True);assert not (w/'report.json').exists();qemu=a.qemu.resolve();image=a.image.resolve();elf=a.elf.resolve();before=sha(image);data=elf.read_bytes();base,code=function(data,'ram_pkdet_vol_start');pattern=bytes.fromhex('bc4ae1839d8be39dc7fe');offset=code.find(pattern);assert offset>=0 and code.count(pattern)==1;gate=base+offset;raw=image.read_bytes();assert len(raw)<=0x400000;flash=w/'flash.bin';flash.write_bytes(raw+b'\xff'*(0x400000-len(raw)));report=dict(physical_hardware=False,emulator_changes=False,WiFi_initialization_completed=False,real_vendor_initializer_entered=False,C3_startup_observation_boots=1,observed_PHY_wait=False,PHY_function='ram_pkdet_vol_start',PHY_wait_PC=gate,PHY_status_address=0x6000e050,required_status_mask=7<<24,required_status_value=7<<24,samples=[],image_sha256=before,elf_sha256=sha(elf),qemu_sha256=sha(qemu))
 with (w/'stderr.log').open('wb') as errors:
  child=subprocess.Popen([str(qemu),'-M','esp32c3','-S','-icount','3','-display','none','-monitor','none','-qmp','stdio','-serial','file:'+str(w/'uart.log'),'-drive','file='+str(flash)+',if=mtd,format=raw','-nic','none','-no-reboot'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=errors,bufsize=0);qmp=QMP(child.stdout,child.stdin)
  try:
   qmp.request('qmp_capabilities');(w/'mtree.txt').write_text(qmp.request('human-monitor-command',{'command-line':'info mtree'}));qmp.request('cont');time.sleep(.3)
   for i in range(4):
    time.sleep(.15);status=qmp.request('query-status');regs=qmp.request('human-monitor-command',{'command-line':'info registers'});memory=qmp.request('human-monitor-command',{'command-line':'xp /2wx 0x6000e050'});pc=int(re.search(r'\bpc\s+([0-9a-fA-F]+)',regs)[1],16);words=re.findall(r'0x([0-9a-fA-F]{8})(?=\s|$)',memory);report['samples'].append(dict(index=i,status=status,PC=pc,registers=regs,memory=memory,PHY_status=int(words[-2],16)))
   uart=(w/'uart.log').read_text(errors='replace');report['real_vendor_initializer_entered']='C3 WIFI: entering actual vendor initialization' in uart and 'pp rom version: 9387209' in uart and 'net80211 rom version: 9387209' in uart
   report['observed_PHY_wait']=report['real_vendor_initializer_entered'] and 'initializer returned' not in uart and all(x['status']['running'] and gate<=x['PC']<=gate+6 and x['PHY_status']&(7<<24)!=7<<24 for x in report['samples']);assert report['observed_PHY_wait'],'unexpected startup state; inspect retained QMP/UART evidence';qmp.request('quit');assert child.wait(timeout=5)==0
  except BaseException as e:report['error']=str(e);raise
  finally:
   if child.poll() is None:child.terminate();child.wait(timeout=5)
   report['process_exit_code']=child.returncode;report['input_image_preserved']=sha(image)==before;(w/'qmp.json').write_text(json.dumps(qmp.events,indent=2)+'\n');(w/'report.json').write_text(json.dumps(report,indent=2)+'\n');child.stdin.close();child.stdout.close()
 print('Observed real C3 vendor PHY wait at',hex(gate),'in four samples; Wi-Fi initialization remains unverified',flush=True)
if __name__=='__main__':main()
