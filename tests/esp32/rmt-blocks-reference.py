#!/usr/bin/env python3
"""Verify saved GPIO21-to-GPIO25 RMT block captures; never opens hardware.

The diagnostic source emits pulse lengths independently of the RMT driver.
Only complete, successful RAM-only captures with unchanged flash and reset
cleanup are accepted. The verifier permits0..32us of added software overhead per
pulse interval at the configured1MHz RX clock; this is a functional memory
boundary test, not a calibrated timing measurement.
"""
import argparse,hashlib,json
from pathlib import Path

def require(ok,why):
 if not ok:raise AssertionError(why)

def decode_uart(uart):
 rows=[]
 for line in uart.splitlines():
  fields=line.split()
  if fields and fields[0]==b'RB':
   require(len(fields)==6 and (not rows or 'words' in rows[-1]),'capture metadata order');values=[int(x,16) for x in fields[1:]];rows.append({'case':values[0],'channel':values[1],'blocks':values[2],'pulses':values[3],'count':values[4]})
  elif fields and fields[0]==b'WORDS':
   require(rows and 'words' not in rows[-1],'capture words order');rows[-1]['words']=[int(x,16) for x in fields[1:]]
 require(len(rows)==36 and b'PASS: RMT block capture,36 reservations\r\n' in uart and b'RMT BLOCK FAIL' not in uart,'incomplete hardware matrix')
 intervals=0;words=0
 for case,(row,(channel,blocks)) in enumerate(zip(rows,((channel,blocks) for channel in range(8) for blocks in range(1,9-channel)))):
  require((row['case'],row['channel'],row['blocks'])==(case,channel,blocks),'case/reservation order')
  pulses=blocks*64-8;require(row['pulses']==row['count']==len(row['words'])==pulses,'incomplete/full memory capture')
  for i,word in enumerate(row['words']):
   require(0<=word<=0xffffffff,'symbol width');high=word&32767;low=(word>>16)&32767
   require(word&32768 and not word&0x80000000 and 80+(i&7)*10<=high<=112+(i&7)*10,'high pulse pattern')
   if i<pulses-1:
    require(120+((i>>3)&7)*10<=low<=152+((i>>3)&7)*10,'low pulse pattern');intervals+=1
   else:require(low==0,'missing idle terminator')
   intervals+=1
  words+=pulses
 return {'pass':True,'reservations':len(rows),'symbols':words,'interval_checks':intervals,'scope':'original ESP32 contiguous RMT RX memory, GPIO21-to-GPIO25 pulses','limitations':['GPIO timing includes software overhead; this is not calibrated timing or a full RMT emulator.']}

def verify(capture):
 physical=json.loads((capture/'physical.json').read_text());uart=(capture/'physical-uart.bin').read_bytes();image=(capture/'peer.elf').read_bytes()
 require(physical['pass'] and physical['ram_only'] and not physical['flash_write_requested'] and physical['flash_unchanged'] and physical['stages'][-1]=='physical-final-reset','incomplete RAM-only capture cleanup')
 require(physical['image_sha256']==hashlib.sha256(image).hexdigest() and physical['uart'].encode()==uart,'capture/image/report mismatch')
 report=decode_uart(uart);report.update({'ram_only':True,'flash_unchanged':True,'final_reset':True,'image_sha256':hashlib.sha256(image).hexdigest(),'uart_sha256':hashlib.sha256(uart).hexdigest()});return report

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--capture',type=Path,required=True);p.add_argument('--report',type=Path);a=p.parse_args();report=verify(a.capture)
 if a.report:a.report.write_text(json.dumps(report,indent=2)+'\n')
 print(json.dumps(report));return 0
if __name__=='__main__':raise SystemExit(main())
