#!/usr/bin/env python3
"""Decode actual machine-code RMT runs without labeling them physical tests."""
import argparse,hashlib,importlib.util,json
from pathlib import Path

def require(ok,why):
 if not ok:raise AssertionError(why)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def module(path):
 spec=importlib.util.spec_from_file_location(path.stem,path);result=importlib.util.module_from_spec(spec);spec.loader.exec_module(result);return result

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--kind',choices=['legacy','blocks','spi'],required=True);p.add_argument('--uart',type=Path,required=True);p.add_argument('--elf',type=Path,required=True);p.add_argument('--runner',type=Path,required=True);p.add_argument('--emulation-report',type=Path,required=True);p.add_argument('--physical-capture',type=Path);p.add_argument('--report',type=Path,required=True);a=p.parse_args();root=Path(__file__).resolve().parents[2];run=json.loads(a.emulation_report.read_text());uart=a.uart.read_bytes()
 require(run['exit_code']==0 and not run['application_failure_seen'] and run['physical_hardware_verified'] is False,'incomplete emulator execution');require(run['image_sha256']==sha(a.elf) and run['runner_sha256']==sha(a.runner) and run['uart_sha256']==sha(a.uart),'emulated artifact identity');report={'pass':True,'physical_hardware_verified':False,'machine_code_executed':True,'rmt_model_implemented':True,'image_sha256':sha(a.elf),'runner_sha256':sha(a.runner),'uart_sha256':sha(a.uart),'uart_bytes':len(uart),'kind':a.kind}
 if a.kind=='blocks':
  decoder=module(root/'tests/esp32/rmt-blocks-reference.py');report.update(decoder.decode_uart(uart));report['physical_hardware_verified']=False
 else:
  require(a.physical_capture,'saved physical capture required');physical=json.loads((a.physical_capture/'physical.json').read_text());require(physical['pass'] and physical['ram_only'] and not physical['flash_write_requested'] and physical['flash_unchanged'] and physical['stages'][-1]=='physical-final-reset','physical cleanup proof');require(physical['image_sha256']==sha(a.physical_capture/'peer.elf')==sha(a.elf),'emulated image differs from physical image');saved=(a.physical_capture/'physical-uart.bin').read_bytes();require(physical['uart'].encode()==saved,'physical transcript identity')
  if a.kind=='legacy':
   require(uart==saved and uart.count(b'RMT MATRIX PASS CHANNEL ')==8 and b'SIGNAL CASES 0000000000000050\r\nPEER PASS\r\n' in uart,'legacy physical/emulator transcript mismatch');report.update({'cases':80,'channels':8,'byte_identical_to_previous_physical_uart':True})
  else:
   decoder=module(root/'tests/esp32/spi-waveform-reference.py');frames=decoder.parse_uart(uart,64);_,physical_frames,_=decoder.read_capture(a.physical_capture,64);decoded=[decoder.decode_frame(f,2) for f in frames];observed=[decoder.decode_frame(f,2) for f in physical_frames];clock_failures=[];cs_failures=[]
   for em,ph,ed,pd in zip(frames,physical_frames,decoded,observed):
    idx=em['meta'][0];require(em['meta'][:21]==ph['meta'][:21],f'frame{idx}: register configuration differs')
    def edges(frame,parsed):
     trace=parsed['channels']['R0']['segments'];start=parsed['cs_start'];end=parsed['cs_end'];return [(t-start,v) for t,_,v in trace if start<t<end]+[(trace[-1][1]-start,frame['meta'][21])]
    ee=edges(em,ed);pe=edges(ph,pd)
    if len(ee)!=len(pe) or any(a[1]!=b[1] or abs(a[0]-b[0])>2 for a,b in zip(ee,pe)):clock_failures.append({'frame':idx,'reason':'clock-edge trace differs'})
    e_duration=ed['cs_end']-ed['cs_start'];p_duration=pd['cs_end']-pd['cs_start']
    if abs(e_duration-p_duration)>2:cs_failures.append({'frame':idx,'emulated_RMT_ticks':e_duration,'physical_RMT_ticks':p_duration})
   report.update({'pass':not clock_failures and not cs_failures,'combined_SPI_RMT_firmware_executed':True,'cases':64,'bits_checked':sum(d['bits_checked'] for d in decoded),'clock_edges_checked':sum(d['clock_edges_checked'] for d in decoded),'clock_and_payload_verified':not clock_failures,'full_CS_timing_verified':not cs_failures,'clock_failures':clock_failures,'CS_failures':cs_failures,'physical_model_complete':False})
 a.report.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report));return 0 if report['pass'] else 1
if __name__=='__main__':raise SystemExit(main())
