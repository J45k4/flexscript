#!/usr/bin/env python3
"""Independent UART-word/QMP peer for original ESP32 and S3 frontend images."""
import argparse,hashlib,json,re,selectors,socket,struct,subprocess,tempfile,time
from pathlib import Path
MAGIC=b'FLEXIO01'
INPUT=struct.pack('<QQ',0x123456789abcdef0,0x8877665544332211)
EXPECTED=MAGIC+struct.pack('<QQ',0x123456789abcdef9,0x778899aabbccddee)
def main():
    p=argparse.ArgumentParser();p.add_argument('--qemu',required=True);p.add_argument('--image',type=Path,required=True);p.add_argument('--report',type=Path,required=True);p.add_argument('--pass-marker',action='store_true');a=p.parse_args()
    expected=EXPECTED+(b'FLEXPASS' if a.pass_marker else b'')
    payload=a.image.read_bytes();assert payload[0]==233 and payload[1]==2
    chip=payload[12];assert chip in (0,9);machine='esp32' if chip==0 else 'esp32s3'
    state=struct.unpack_from('<I',payload,32+struct.unpack_from('<I',payload,28)[0])[0];assert state in (0x3ffb0000,0x3ffc0000,0x3fcb0000,0x3fcc0000,0x3fca8000)
    data=bytearray(b'\xff'*4194304);offset=4096 if chip==0 else 0;data[offset:offset+len(payload)]=payload
    with tempfile.TemporaryDirectory(prefix='flexscript-frontend-uart-') as tmp:
        flash=Path(tmp)/'flash.bin';flash.write_bytes(data);host,child=socket.socketpair();host.setblocking(False)
        proc=subprocess.Popen([a.qemu,'-M',machine,'-display','none','-monitor','none','-qmp','stdio','-chardev',f'socket,id=uart,fd={child.fileno()}','-serial','chardev:uart','-drive',f'file={flash},if=mtd,format=raw','-nic','none','-no-reboot'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,pass_fds=(child.fileno(),));child.close()
        select=selectors.DefaultSelector();select.register(proc.stdout,selectors.EVENT_READ);buffer=b'';serial=bytearray();sent=0;next_send=0;done=False
        def line():
            nonlocal buffer
            end=time.monotonic()+5
            while b'\n' not in buffer:
                assert proc.poll() is None,('QEMU startup/exit',proc.returncode,proc.stderr.read().decode(errors='replace'))
                assert select.select(max(0,end-time.monotonic())),'QMP timeout'
                buffer+=proc.stdout.read1(65536)
            item,buffer=buffer.split(b'\n',1);return json.loads(item)
        def command(name,args=None):
            item={'execute':name}
            if args:item['arguments']=args
            proc.stdin.write(json.dumps(item).encode()+b'\n');proc.stdin.flush()
            while True:
                reply=line();assert 'error' not in reply,reply
                if 'return' in reply:return reply['return']
        def pump():
            while True:
                try:chunk=host.recv(65536)
                except BlockingIOError:break
                if not chunk:break
                serial.extend(chunk)
        try:
            assert 'QMP' in line();command('qmp_capabilities');end=time.monotonic()+15
            chunks=[INPUT[:3],INPUT[3:8],INPUT[8:11],INPUT[11:]]
            while time.monotonic()<end:
                pump()
                if MAGIC in serial and sent<len(chunks) and time.monotonic()>=next_send:
                    assert host.send(chunks[sent])==len(chunks[sent]);sent+=1;next_send=time.monotonic()+.03
                text=command('human-monitor-command',{'command-line':f'xp /3wx {state+4:#x}'})
                words=re.findall(r'0x([0-9a-fA-F]{8})(?=\s|$)',text)
                if len(words)>=3 and int(words[-3],16) in (0x444f4e45,0x54524150):
                    assert [int(x,16) for x in words[-3:]]==[0x444f4e45,0,0],(text,serial.hex());done=True;break
                time.sleep(.01)
            assert done,('completion timeout',serial.hex());command('quit');proc.wait(timeout=5);pump()
            at=serial.find(MAGIC);assert sent==4 and at>=0 and bytes(serial[at:])==expected,(sent,serial.hex(),expected.hex())
            assert flash.read_bytes()==data,'UART frontend firmware modified flash'
        finally:
            if proc.poll() is None:proc.terminate()
            try:proc.wait(timeout=5)
            except subprocess.TimeoutExpired:proc.kill();proc.wait(timeout=5)
            host.close();select.close();proc.stdin.close();proc.stdout.close();proc.stderr.close()
    report={'chip':machine,'state_base':hex(state),'image_sha256':hashlib.sha256(payload).hexdigest(),'input_hex':INPUT.hex(),'expected_hex':expected.hex(),'chunks':[3,5,3,5],'uart_payload_exact':True,'main_return':0,'flash_unchanged':True}
    a.report.write_text(json.dumps(report,indent=2)+'\n');print('PASS: '+machine+' frontend UART words, partial RX, full64-bit values, checked state and write return')
if __name__=='__main__':main()
