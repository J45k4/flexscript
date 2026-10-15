#!/usr/bin/env python3
"""Independent QEMU restart/media oracle for the real native flash backend."""
import argparse
import hashlib
import importlib.util
import json
import re
import selectors
import socket
import subprocess
import tempfile
import time
from pathlib import Path

START=0x3e0000
SIZE=8192

def digest(data):
    return hashlib.sha256(data).hexdigest()

class Guest:
    def __init__(self,qemu,flash,uart,command=None):
        self.socket=None;self.command_byte=command;self.serial_data=bytearray();self.sent=False
        serial_args=['-serial','file:'+str(uart)];fds=()
        if command:
            self.socket,child=socket.socketpair();self.socket.setblocking(False)
            serial_args=['-chardev',f'socket,id=uart,fd={child.fileno()}','-serial','chardev:uart'];fds=(child.fileno(),)
        self.proc=subprocess.Popen([qemu,'-M','esp32','-display','none','-monitor','none',
            '-qmp','stdio',*serial_args,'-drive',f'file={flash},if=mtd,format=raw',
            '-nic','none','-no-reboot'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,pass_fds=fds)
        if command:child.close()
        self.selector=selectors.DefaultSelector()
        self.selector.register(self.proc.stdout,selectors.EVENT_READ)
        self.buffer=b''
        self.uart=uart
        self.line(5)
        self.command('qmp_capabilities')

    def line(self,timeout):
        end=time.monotonic()+timeout
        while b'\n' not in self.buffer:
            assert self.proc.poll() is None,'guest stopped before reply'
            ready=self.selector.select(max(0,end-time.monotonic()))
            assert ready,'QMP observation timeout'
            self.buffer+=self.proc.stdout.read1(65536)
        line,self.buffer=self.buffer.split(b'\n',1)
        return json.loads(line)

    def command(self,name,arguments=None):
        cmd={'execute':name}
        if arguments:cmd['arguments']=arguments
        self.proc.stdin.write(json.dumps(cmd).encode()+b'\n');self.proc.stdin.flush()
        while True:
            reply=self.line(5)
            assert 'error' not in reply,reply
            if 'return' in reply:return reply['return']

    def pump_serial(self):
        if self.socket is None:return
        while True:
            try:data=self.socket.recv(65536)
            except BlockingIOError:break
            if not data:break
            self.serial_data.extend(data)
        self.uart.write_bytes(self.serial_data)
        if not self.sent and b'SETTINGS PROBE READY' in self.serial_data:
            self.socket.sendall(self.command_byte);self.sent=True

    def finish(self):
        end=time.monotonic()+20
        while time.monotonic()<end:
            self.pump_serial()
            reply=self.command('human-monitor-command',{'command-line':'xp /3wx 0x3ffb0004'})
            words=re.findall(r'0x([0-9a-fA-F]{8})(?=\s|$)',reply)
            if len(words)>=3 and int(words[-3],16)==0x444f4e45:
                self.pump_serial()
                assert all(int(x,16)==0 for x in words[-2:]),(reply,self.uart.read_text())
                return self.uart.read_text()
            time.sleep(.02)
        raise AssertionError('guest completion timeout: '+self.uart.read_text())

    def close(self):
        try:
            if self.proc.poll() is None:
                self.command('quit')
        finally:
            try:self.proc.wait(timeout=5)
            except subprocess.TimeoutExpired:self.proc.kill();self.proc.wait(timeout=5)
            self.pump_serial()
            if self.socket is not None:self.socket.close()
            self.selector.close()
            self.proc.stdin.close();self.proc.stdout.close();self.proc.stderr.close()

def main():
    p=argparse.ArgumentParser()
    p.add_argument('--qemu',required=True)
    p.add_argument('--image',type=Path,required=True)
    p.add_argument('--report',type=Path,required=True)
    p.add_argument('--serial-gate',action='store_true')
    args=p.parse_args()
    spec=importlib.util.spec_from_file_location('settings_reference',Path(__file__).with_name('settings-vectors.py'))
    reference=importlib.util.module_from_spec(spec);spec.loader.exec_module(reference)
    payload=args.image.read_bytes()
    before=bytearray(b'\xff'*0x400000);before[4096:4096+len(payload)]=payload
    immutable=digest(before[:START]+before[START+SIZE:])
    boots=[]
    with tempfile.TemporaryDirectory(prefix='flexscript-settings-reboot-') as tmp:
        root=Path(tmp);flash=root/'flash.bin';flash.write_bytes(before)
        for boot in range(1,5):
            uart=root/f'uart-{boot}.log';guest=Guest(args.qemu,str(flash),uart,(b'F' if boot==1 else b'R') if args.serial_gate else None)
            try:serial=guest.finish()
            finally:guest.close()
            disk=flash.read_bytes()
            assert digest(disk[:START]+disk[START+SIZE:])==immutable
            code,snapshot=reference.expected_mount(disk[START:START+SIZE]);assert code==0
            count=1 if boot==1 else 2
            expected_payload=bytes((i*29+16+count)&255 for i in range(600))
            assert snapshot[1]=={b'count':(1,bytes([count])),b'message':(33,b'settings survive reboot'),b'payload':(66,expected_payload)}
            if boot==1:
                assert 'SETTINGS COMMITTED 1' in serial
                if args.serial_gate:assert 'PASS: cached original ESP32 flash' in serial and 'FLASH RESULT 0000000000000000' in serial
            elif boot==2:assert 'SETTINGS RECOVERED 0000000000000001' in serial and 'SETTINGS COMMITTED 2' in serial
            else:assert 'SETTINGS RECOVERED 0000000000000002' in serial and 'SETTINGS INTERRUPTED BEFORE MARKER' in serial
            if boot>=3:
                banks=disk[START:START+SIZE]
                assert reference.bank_parse(banks[:4096]) is not None and reference.bank_parse(banks[4096:]) is None
            boots.append({'boot':boot,'generation':snapshot[0],'count':count,'uart':serial})
    report={'serial_gated_raw_and_settings_probe':args.serial_gate,'boots':boots,'protected_flash_sha256':immutable,'scope':'real flash-controller/backend and cached native settings in QEMU; process restarts between committed and interrupted transactions'}
    args.report.write_text(json.dumps(report,indent=2)+'\n')
    print('Settings backend:4 independent ROM boots,600-byte values, two durable transactions and interrupted-bank recovery passed')

if __name__=='__main__':main()
