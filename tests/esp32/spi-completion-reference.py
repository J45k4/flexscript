#!/usr/bin/env python3
"""Decode SPI CS and software completion markers from a saved capture.

R3 marks observed TRANS_DONE and R4 marks observed USR clear. Polling and GPIO
calls add latency: this functional test permits0..50 RX ticks (50us) after the
expected event, strictly less than the100us clock period. It does not measure
the interrupt-controller or calibrated electrical propagation latency.
"""
import argparse,hashlib,importlib.util,json
from pathlib import Path

def require(ok,why):
 if not ok:raise AssertionError(why)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--capture',type=Path,required=True);p.add_argument('--report',type=Path,required=True)
 p.add_argument('--emulated-uart',type=Path);p.add_argument('--emulation-report',type=Path);p.add_argument('--runner',type=Path)
 a=p.parse_args();root=Path(__file__).resolve().parents[2];path=root/'tests/esp32/spi-waveform-reference.py';spec=importlib.util.spec_from_file_location('wire',path);wire=importlib.util.module_from_spec(spec);spec.loader.exec_module(wire)
 physical,frames,uart=wire.read_capture(a.capture,32);emulated=bool(a.emulated_uart)
 if emulated:
  require(a.emulation_report and a.runner,'emulation identity required');run=json.loads(a.emulation_report.read_text());uart=a.emulated_uart.read_bytes()
  require(run['exit_code']==0 and not run['application_failure_seen'] and run['physical_hardware_verified'] is False,'incomplete emulator run')
  require(run['runner_sha256']==sha(a.runner) and run['image_sha256']==sha(a.capture/'peer.elf') and run['uart_sha256']==sha(a.emulated_uart),'emulated artifact identity')
  frames=wire.parse_uart(uart,32)
 extra={};idx=-1
 for line in uart.splitlines():
  f=line.split()
  if not f:continue
  if f[0]==b'SW':idx=int(f[1],16);extra[idx]={}
  elif f[0] in (b'R3',b'R4'):
   tag=f[0].decode();require(idx>=0 and tag not in extra[idx] and len(f)==int(f[1],16)+2,'completion capture shape')
   trace,marker=wire.segments([int(x,16) for x in f[2:]]);require(len(trace)==2 and [x[2] for x in trace]==[1,0],'completion marker transition sequence');extra[idx][tag]={'trace':trace,'marker':marker}
 require(set(extra)==set(range(32)),'completion frame count');rows=[]
 for i,frame in enumerate(frames):
  m=frame['meta'];hold=[0,1,3,15][(i//2)&3];command=0x52+(i&1)
  require((m[0],m[1],m[2],m[3],m[5],m[6],m[7],m[18])==(i,2+i//16,(i//8)&1,0,16,15,17,hold),'completion fixture case identity')
  require(frame['raw_command_readback'][1]==0xf0000000|command,'command register identity');dec=wire.decode_frame(frame,2);period=dec['period_rmt_ticks'];require(period==100,'completion probe period')
  delay=1 if command==0x52 else 6;require(abs(dec['observed_hold_cycles']-min(hold,delay))<=.02,'CS release timing')
  require(set(extra[i])=={'R3','R4'},'missing completion markers');edge=dec['cs_start']+(2+48+delay)*period
  markers=[]
  for tag in ['R3','R4']:
   channel=extra[i][tag];require(abs(channel['marker']-frame['channels']['R0']['marker'])<=2,'completion synchronization marker')
   at=channel['trace'][-1][1];require(0<=at-edge<=50,f'frame{i} {tag}: completion event/latency {at-edge} outside0..50ticks');markers.append(at)
  require(0<=markers[1]-markers[0]<=50,'USR observation follows TRANS_DONE with bounded software latency')
  rows.append({'case':i,'bus':m[1],'mode':m[2],'command_raw':command,'configured_hold':hold,'CS_hold_periods':dec['observed_hold_cycles'],'completion_delay_periods':delay,'TRANS_DONE_poll_latency_ticks':markers[0]-edge,'USR_poll_latency_ticks':markers[1]-edge})
 report={'pass':True,'scope_complete':False,'cases':32,'physical_hardware_verified':not emulated,'saved_physical_capture_compared':True,'machine_code_executed':emulated,'image_sha256':physical['image_sha256'],'uart_sha256':hashlib.sha256(uart).hexdigest(),'software_latency_bound_RMT_ticks':50,'measurements':rows,'limitations':['GPIO markers include polling/function overhead; exact interrupt and electrical timing is not measured.','Original ESP32 rev3, half-duplex writes, modes0/1 and reset CTRL1 delay only.']}
 a.report.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({k:report[k] for k in ['pass','cases','physical_hardware_verified','machine_code_executed']}));return 0
if __name__=='__main__':raise SystemExit(main())
