#!/usr/bin/env python3
"""Observe actual S3 vendor startup with unmodified stock QEMU.

An observed PHY-ready wait is a hardware/model verification gate, not successful
Wi-Fi initialization. The input flash is copied; no physical device is accessed.
"""
import argparse,hashlib,json,os,re,select,shutil,subprocess,time
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

def main():
    p=argparse.ArgumentParser(description=__doc__)
    for k in ['qemu','flash','work']:p.add_argument('--'+k,required=True)
    p.add_argument('--samples',type=int,default=4);p.add_argument('--interval',type=float,default=.5)
    a=p.parse_args();assert 1<=a.samples<=16 and 0<a.interval<=30
    qemu=Path(a.qemu).resolve();flash=Path(a.flash).resolve();w=Path(a.work).resolve()
    w.mkdir(parents=True,exist_ok=True);assert not (w/'report.json').exists(),'choose a fresh work directory'
    assert flash.stat().st_size in [2<<20,4<<20,8<<20,16<<20]
    image=w/'flash.bin';assert image!=flash;shutil.copyfile(flash,image);before=sha(flash)
    report=dict(input_flash=str(flash),input_flash_sha256=before,qemu_sha256=sha(qemu),
        source_sha256=sha(__file__),physical_hardware=False,emulator_changes=False,
        vendor_initialization_completed=False,observed_expected_gate=False,samples=[])
    with (w/'stderr.log').open('wb') as errors:
        command=[qemu,'-M','esp32s3','-S','-display','none','-monitor','none','-qmp','stdio',
            '-serial','file:'+str(w/'uart.log'),'-drive','file='+str(image).replace(',',',,')+',if=mtd,format=raw',
            '-nic','none','-no-reboot','-d','unimp,guest_errors','-D',w/'mmio.log']
        child=subprocess.Popen(list(map(str,command)),stdin=subprocess.PIPE,stdout=subprocess.PIPE,
            stderr=errors,bufsize=0);report['process_pid']=child.pid
        qmp=QMP(child.stdout,child.stdin)
        try:
            qmp.request('qmp_capabilities')
            (w/'mtree.txt').write_text(qmp.request('human-monitor-command',{'command-line':'info mtree'}))
            qmp.request('cont')
            for i in range(a.samples):
                time.sleep(a.interval)
                report['samples'].append(dict(index=i,status=qmp.request('query-status'),
                    registers=qmp.request('human-monitor-command',{'command-line':'info registers'}),
                    memory=qmp.request('human-monitor-command',{'command-line':'xp /4wx 0x6000e048'})))
            qmp.request('quit');assert child.wait(timeout=5)==0
            uart=(w/'uart.log').read_text(errors='replace')
            report['observed_expected_gate']=('S3 WIFI: entering actual vendor initialization' in uart and
                all(row['status']['running'] and 'PC=40036a44' in row['registers'] and
                    re.search(r'0x00000000\s+0x00000000\s+0x00000000\s+0x00000000',row['memory'])
                    for row in report['samples']))
            assert report['observed_expected_gate'],'actual startup did not reach the expected gate; inspect retained samples'
        except BaseException as exc:
            report['error']=str(exc);raise
        finally:
            if child.poll() is None:child.terminate();child.wait(timeout=5)
            report['process_exit_code']=child.returncode;report['input_preserved']=sha(flash)==before
            (w/'qmp.json').write_text(json.dumps(qmp.events,indent=2)+'\n')
            (w/'report.json').write_text(json.dumps(report,indent=2)+'\n')
            child.stdin.close();child.stdout.close()
    print(f'Observed actual vendor PHY-ready gate in {len(report["samples"])} samples;QEMU pid{child.pid} terminal exit{child.returncode}. Wi-Fi initialization remains unverified.')

if __name__=='__main__':main()
