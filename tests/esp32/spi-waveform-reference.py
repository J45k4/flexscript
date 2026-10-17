#!/usr/bin/env python3
"""Decode an existing RMT capture and compare SPI pin traces; never open a board.
The capture uses three receivers synchronized by the same marker pulse.
"""
import argparse,hashlib,json,re,struct,subprocess
from pathlib import Path
class CheckError(AssertionError):pass
def require(ok,message):
 if not ok:raise CheckError(message)
def segments(words):
 result=[];time=0;ended=False
 for wi,word in enumerate(words):
  for hi,half in enumerate((word&65535,word>>16)):
   duration=half&32767;level=half>>15
   if not duration:
    require(wi==len(words)-1 and hi==1,'unexpected RMT terminator');ended=True;break
   result.append((time,time+duration,level));time+=duration
  if ended:break
 require(result and result[0][2]==1 and 500<=result[0][1]<=2000,'missing full synchronization pulse')
 origin=result[0][1];return [(a-origin,b-origin,v) for a,b,v in result],origin

def parse_uart(data,expected_cases):
 frames=[];raw_readbacks=[];delay_readbacks=[]
 for line in data.splitlines():
  fields=line.split()
  if not fields:continue
  tag=fields[0].decode()
  if tag=='SW':
   require(len(fields)==25,'capture metadata shape');meta=[int(x,16) for x in fields[1:]];require(meta[0]==len(frames),'frame order');frames.append({'meta':meta,'channels':{}})
  elif tag=='RT':
   require(len(fields)==5,'delay register readback shape');values=[int(x,16) for x in fields[1:]];require(values[0]==len(delay_readbacks) and all(0<=x<=0xffffffff for x in values[1:]),'delay register readback order/width');delay_readbacks.append(values)
  elif tag=='CR':
   require(len(fields)==5,'raw command readback shape');values=[int(x,16) for x in fields[1:]];require(values[0]==len(raw_readbacks),'raw command readback order');raw_readbacks.append(values)
  elif tag in ('R0','R1','R2'):
   require(frames and tag not in frames[-1]['channels'],'duplicate/out-of-order RMT channel');count=int(fields[1],16);words=[int(x,16) for x in fields[2:]];require(count==len(words) and 1<=count<(192 if tag=='R0' else 64),'incomplete/overflowed RMT capture');segs,marker=segments(words);frames[-1]['channels'][tag]={'words':words,'segments':segs,'marker':marker}
 require(len(frames)==expected_cases and b'PASS: SPI waveform capture\r\n' in data,'incomplete frame matrix')
 if raw_readbacks:
  require(len(raw_readbacks)==len(frames),'incomplete raw command register readbacks')
  for frame,raw in zip(frames,raw_readbacks):
   m=frame['meta'];require(raw[0]==m[0] and raw[2:]==m[19:21] and 0<=raw[1]<=0xffffffff and not raw[1]&~0xf000ffff,'raw register identity')
   length=((raw[1]>>28)&15)+1;enabled=bool(m[19]&(1<<31));require(m[5]==(length if enabled else 0),'raw command length/phase flag')
   logical=0
   for i in range(m[5]):
    shift=(i&~7)+(i&7 if m[3] else 7-(i&7));bit=(raw[1]>>shift)&1
    logical|=bit<<(i if m[3] else m[5]-1-i)
   require(m[10]==logical,'raw command bits differ from logical metadata');frame['raw_command_readback']=raw
 if delay_readbacks:
  require(len(delay_readbacks)==len(frames) and len(raw_readbacks)==len(frames),'incomplete delay register readbacks')
  for frame,raw in zip(frames,delay_readbacks):
   require(raw[0]==frame['meta'][0],'delay readback frame');frame['delay_register_readback']=raw
 return frames

def read_capture(directory,expected_cases):
 physical=json.loads((directory/'physical.json').read_text());data=(directory/'physical-uart.bin').read_bytes();sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
 require(physical['pass'] and physical['ram_only'] and not physical['flash_write_requested'] and physical['flash_unchanged'] and physical['stages'][-1]=='physical-final-reset','incomplete RAM-only capture cleanup');require(physical['uart'].encode()==data,'capture/report mismatch');require(physical['image_sha256']==sha(directory/'peer.elf'),'capture image mismatch')
 return physical,parse_uart(data,expected_cases),data

def level_at(segs,time,final_level):
 for start,end,level in segs:
  if start<=time<end:return level
 require(time>=segs[-1][1],'sample precedes capture');return final_level

def decode_frame(frame,tolerance):
 m=frame['meta'];idx,bus,mode,order,profile,cmdlen,addrlen,bits,dummy,dummyidle,cmd,addr,d0,d1,pre,n,high,setup,hold,user,ctrl2,endclk,enddata,endcs=m;channels=frame['channels'];require(set(channels)=={'R0','R1','R2'},'missing RMT channel');require(max(c['marker'] for c in channels.values())-min(c['marker'] for c in channels.values())<=2,'marker disagreement')
 cpol=mode>>1;cpha=mode&1;require(endclk==cpol and endcs==1,'final clock/CS state');cs=channels['R2']['segments'];require(len(cs)==4 and [v for a,b,v in cs]==[1,0,1,0],'unexpected CS edge sequence');start,end,_=cs[-1]
 clock=channels['R0']['segments'];events=[(a,v) for a,b,v in clock if start<a<end];require(clock[-1][2]!=cpol,'missing complete final clock interval');events.append((clock[-1][1],cpol));require(events and events[0][1]==1-cpol,'first clock polarity');first=events[0][0]
 period=pre*n/80;active=pre*(high if not cpol else n-high)/80;idle=period-active;cycles=cmdlen+addrlen+dummy+bits;expected=[]
 for cycle in range(cycles):
  if dummyidle and cmdlen+addrlen<=cycle<cmdlen+addrlen+dummy:continue
  expected.extend([(first+cycle*period,1-cpol),(first+cycle*period+active,cpol)])
 require(len(events)==len(expected),f'frame{idx}: clock-edge count {len(events)} != {len(expected)}')
 for i,((time,value),(want,pol)) in enumerate(zip(events,expected)):
  require(value==pol and abs(time-want)<=tolerance,f'frame{idx}: clock edge{i} {time,value} != {want,pol}')
 logical=[(cmd>>(i if order else cmdlen-1-i))&1 for i in range(cmdlen)]
 logical += [(addr>>(i if order else addrlen-1-i))&1 for i in range(addrlen)]
 logical += [None]*dummy;data=d0.to_bytes(4,'little')+d1.to_bytes(4,'little');logical += [(data[i//8]>>(i%8 if order else 7-i%8))&1 for i in range(bits)]
 wire=channels['R1']['segments'];bit_checks=0;transition_checks=0;last=None
 for i,want in enumerate(logical):
  if want is None:last=None;continue
  sample=first+i*period+(active if cpha else 0);actual=level_at(wire,sample,enddata);require(actual==want,f'frame{idx}: bit{i} {actual} != {want}');bit_checks+=1
  if last is not None and last!=want:
   when=first+i*period if cpha else first+(i-1)*period+active
   matches=[a for a,b,v in wire if abs(a-when)<=tolerance and v==want];
   if wire[-1][2]!=enddata and enddata==want and abs(wire[-1][1]-when)<=tolerance:matches.append(wire[-1][1])
   require(matches,f'frame{idx}: data transition at bit{i} not at {when}');transition_checks+=1
  last=want
 observed_hold=(end-start)/period-setup-cycles
 return {'id':idx,'bus':bus,'mode':mode,'order':order,'profile':profile,'bits_checked':bit_checks,'data_transitions_checked':transition_checks,'clock_edges_checked':len(events),'cs_start':start,'cs_end':end,'first_clock':first,'last_clock':events[-1][0],'period_rmt_ticks':period,'first_clock_after_cs':first-start,'hold_field':hold,'observed_hold_cycles':observed_hold,'channels':channels,'logical':logical,'active':active,'idle':idle}

def model_frames(data,count):
 require(len(data)>=16 and struct.unpack_from('<2Q',data)==(0x53574556454e5401,count),'model output header');at=16;result=[]
 for i in range(count):
  idx,n=struct.unpack_from('<2Q',data,at);at+=16;require(idx==i and 1<=n<=1024 and at+n*32<=len(data),'model event shape');events=[struct.unpack_from('<4Q',data,at+j*32) for j in range(n)];at+=n*32;result.append(events)
 require(at==len(data),'extra model output');return result

def compare_model(frame,decoded,events,tolerance):
 m=frame['meta'];idx=m[0];start=decoded['cs_start'];end=decoded['cs_end'];factor=80;result={}
 # Check each signal independently. An unresolved CS-duration mismatch must
 # remain a failure without hiding whether every clock edge and data bit agrees.
 def check_component(name,check):
  try:check();result[name]={'pass':True}
  except CheckError as e:result[name]={'pass':False,'failure':str(e)}
 def cs_duration():
  require(events[0][0]==0 and events[0][3]==0 and events[-1][3]==1,'model CS endpoints');require(abs(events[-1][0]/factor-(end-start))<=tolerance,f'frame{idx}: model CS duration {events[-1][0]/factor} != {end-start}')
 def clock_edges():
  physical=decoded['channels']['R0']['segments'];physical_edges=[(a,v) for a,b,v in physical if start<a<end]+[(physical[-1][1],m[21])];emulated=[];before=m[2]>>1
  for tick,clock,data,cs in events:
   if clock!=before:emulated.append((start+tick/factor,clock));before=clock
  require(len(emulated)==len(physical_edges),f'frame{idx}: model clock count')
  for i,(a,b) in enumerate(zip(emulated,physical_edges)):
   require(a[1]==b[1] and abs(a[0]-b[0])<=tolerance,f'frame{idx}: model clock edge{i} {a} != {b}')
 def data_bits():
  for i,want in enumerate(decoded['logical']):
   if want is None:continue
   when=decoded['first_clock']+i*decoded['period_rmt_ticks']+(decoded['active'] if m[2]&1 else 0);tick=(when-start)*factor;value=events[0][2]
   for event in events:
    if event[0]>tick:break
    value=event[2]
   require(value==want,f'frame{idx}: model wire bit{i} {value} != {want}')
 for name,check in [('cs_duration',cs_duration),('clock_edges',clock_edges),('data_bits',data_bits)]:check_component(name,check)
 return {'id':idx,'pass':all(v['pass'] for v in result.values()),'components':result}

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--capture',type=Path,required=True);p.add_argument('--compiler',type=Path);p.add_argument('--reference',type=Path);p.add_argument('--work',type=Path);p.add_argument('--report',type=Path);p.add_argument('--expected-cases',type=int,default=64);p.add_argument('--tolerance',type=int,default=2);p.add_argument('--model',type=Path);p.add_argument('--cc',default='cc');a=p.parse_args();root=Path(__file__).resolve().parents[2];directory=a.capture.resolve();physical,frames,capture=read_capture(directory,a.expected_cases);decoded=[decode_frame(f,a.tolerance) for f in frames];require(a.tolerance>=0 and a.tolerance<=2,'unsupported measurement tolerance')
 report={'pass':True,'scope':'physical RMT wire decode','cases':len(frames),'bits':sum(d['bits_checked'] for d in decoded),'clock_edges':sum(d['clock_edges_checked'] for d in decoded),'data_transitions':sum(d['data_transitions_checked'] for d in decoded),'physical_flash_unchanged':True,'rmt_model_exercised':False,'capture_firmware_emulated':False,'model_verified':False,'capture_sha256':hashlib.sha256(capture).hexdigest(),'image_sha256':physical['image_sha256'],'measurements':[{k:v for k,v in d.items() if k not in ['channels','logical']} for d in decoded]}
 if a.compiler:
  require(a.reference and a.work,'model comparison needs --reference and --work');compiler=a.compiler.resolve();work=a.work.resolve();work.mkdir(parents=True,exist_ok=True);refs=a.reference.resolve();headers={}
  for source in json.loads((root/'tests/xtensa/soc-oracle/sources.json').read_text()):
   parts=source['path'].split('/');name=source.get('chip',parts[1])+'/'+parts[-1];blob=(refs/name).read_bytes();require(hashlib.sha256(blob).hexdigest()==source['sha256'],name+' reference hash');headers[name]=source['sha256']
  def run(args,label,input=None):
   q=subprocess.run([str(x) for x in args],cwd=root,input=input,capture_output=True);(work/(label+'.log')).write_bytes(q.stderr);require(q.returncode==0,(label,q.returncode,q.stderr[-2000:]));return q.stdout
  raw=all('raw_command_readback' in f for f in frames);timers=all('delay_register_readback' in f for f in frames);width=32 if timers else 28 if raw else 24;input=struct.pack('<3Q',0x5357524547000001,len(frames),width)+b''.join(struct.pack('<'+str(width)+'Q',*(f['meta']+(f['raw_command_readback'] if raw else [])+(f['delay_register_readback'] if timers else []))) for f in frames);program=work/'register-reference';run([a.cc,'-O2','-std=gnu11','-Wall','-Wextra','-Werror','-DS3=0','-I'+str(root/'tests/xtensa/soc-oracle'),'-I'+str(refs/'esp32'),root/'tests/esp32/spi-waveform-oracle/registers.c','-o',program],'c-build');packet=run([program],'c-registers',input);reference=work/'registers.bin';reference.write_bytes(packet)
  model=(a.model or root/'emulator/esp32/board.flex').resolve();source=(root/'tests/xtensa/spi-waveform-model.flex').read_text().replace('"../../emulator/esp32/board.flex"',json.dumps(str(model))).replace('"../../scripts/lib/host.flex"',json.dumps(str(root/'scripts/lib/host.flex')));fixture=work/'model.flex';fixture.write_text(source);binary=work/'model';run([compiler,fixture,'-o',binary],'model-build');trace=run([binary,reference],'model');(work/'model.bin').write_bytes(trace);all_events=model_frames(trace,len(frames));failures=[]
  comparisons=[compare_model(frame,measurement,events,a.tolerance) for frame,measurement,events in zip(frames,decoded,all_events)]
  failures=[v['failure'] for row in comparisons for v in row['components'].values() if not v['pass']]
  counts={name:sum(row['components'][name]['pass'] for row in comparisons) for name in ['cs_duration','clock_edges','data_bits']}
  report.update({'pass':not failures,'scope':'physical RMT decode and independent C-packed SPI model pins','model_verified':not failures,'model_failures':failures,'model_comparisons':comparisons,'model_matched_cases':sum(row['pass'] for row in comparisons),'model_component_matched_cases':counts,'reference_headers':headers,'compiler_sha256':hashlib.sha256(compiler.read_bytes()).hexdigest(),'model_program_sha256':hashlib.sha256(binary.read_bytes()).hexdigest()})
 if a.report:a.report.write_text(json.dumps(report,indent=2)+'\n')
 print(json.dumps({k:report[k] for k in ['pass','cases','bits','clock_edges','data_transitions','model_verified']}));return 0 if report['pass'] else 1
if __name__=='__main__':raise SystemExit(main())
