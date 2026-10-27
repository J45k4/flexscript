#!/usr/bin/env python3
"""Controlled localhost HID host. Vendor reports are observed here, never sent to a desktop."""
import argparse,asyncio,json,signal,uuid
from pathlib import Path
from bumble.device import Device,DeviceConfiguration
from bumble.core import PhysicalTransport
from bumble.hid import Host,Message
from bumble.transport import open_transport
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--transport',required=True);p.add_argument('--out',type=Path,required=True);p.add_argument('--scenario',choices=['reports','controls','lifecycle'],default='reports');p.add_argument('--command',type=Path);p.add_argument('--secure-reconnect',action='store_true');p.add_argument('--host-reconnect',action='store_true');a=p.parse_args();assert not(a.secure_reconnect and a.host_reconnect);assert a.scenario=='reports' or a.command
assert a.transport.startswith(('android-netsim:127.0.0.1:','android-netsim:localhost:')) and ',name=collie-test-' in a.transport
state=dict(ready=False,error=None,checks=[],phase='starting',connections=0,closed_channels=0,done=False)
def save():
 a.out.parent.mkdir(parents=True,exist_ok=True);temp=a.out.with_suffix('.tmp');temp.write_text(json.dumps(state,indent=2)+'\n');temp.replace(a.out)
def passed(text):state['checks'].append(text);save()
async def wait(test,seconds=40):
 end=asyncio.get_running_loop().time()+seconds
 while asyncio.get_running_loop().time()<end:
  if test():return
  await asyncio.sleep(.05)
 raise TimeoutError(state['phase'])
async def main():
 stop=asyncio.Event();loop=asyncio.get_running_loop()
 for sig in [signal.SIGTERM,signal.SIGINT]:loop.add_signal_handler(sig,stop.set)
 async with await open_transport(a.transport) as transport:
  config=DeviceConfiguration();config.name='Collie HID test peer '+uuid.uuid4().hex[:8];config.classic_enabled=True;config.le_enabled=False
  device=Device.from_config_with_hci(config,transport.source,transport.sink);host=Host(device);controls=asyncio.Queue();interrupts=asyncio.Queue();security_tasks=[]
  state['peer_requests_reconnect_security']=a.secure_reconnect;state['peer_initiates_reconnect']=a.host_reconnect
  if a.scenario=='lifecycle':
   # Metadata only: never serialize packet payloads, keys or report values.
   receive=device.host.on_hci_event_packet;send=device.host.send_hci_packet
   def trace(direction,packet):
    item=dict(direction=direction,name=getattr(packet,'name',type(packet).__name__),phase=state['phase'])
    for key in ['connection_handle','status','error_code','opcode','command_opcode']:
     value=getattr(packet,key,None)
     if isinstance(value,int):item[key]=int(value)
    state.setdefault('hci_trace',[]).append(item);state['hci_trace']=state['hci_trace'][-240:]
   def traced_receive(packet):trace('receive',packet);receive(packet)
   def traced_send(packet):trace('send',packet);send(packet)
   device.host.on_hci_event_packet=traced_receive;device.host.send_hci_packet=traced_send
  host.on(host.EVENT_CONTROL_DATA,lambda value:controls.put_nowait(bytes(value)))
  host.on(host.EVENT_HANDSHAKE,lambda value:controls.put_nowait(bytes([int(value)])))
  host.on(host.EVENT_INTERRUPT_DATA,lambda value:interrupts.put_nowait(bytes(value)))
  def connected(connection):
   state['acl_connected']=True;state.setdefault('acl_peers',[]).append(str(connection.peer_address));save()
   link=dict(peer=str(connection.peer_address),encrypted=connection.is_encrypted,role=int(connection.role));state.setdefault('acl_links',[]).append(link)
   def encrypted():link['encrypted']=connection.is_encrypted;state['encrypted']=connection.is_encrypted;save()
   connection.on(connection.EVENT_CONNECTION_ENCRYPTION_CHANGE,encrypted)
   connection.on(connection.EVENT_DISCONNECTION,lambda reason:(state.setdefault('acl_disconnections',[]).append(int(reason)),save()))
   connection.on(connection.EVENT_CONNECTION_ENCRYPTION_FAILURE,lambda error:(state.setdefault('encryption_failures',[]).append(str(error)),save()))
   if a.secure_reconnect and len(state['acl_peers'])>1:
    async def secure():
     try:
      await asyncio.wait_for(connection.authenticate(),10)
      await asyncio.wait_for(connection.encrypt(),10)
      assert connection.is_encrypted
      link['host_security_completed']=True;save()
     except Exception as error:state['error']='Actual peer reconnect security failed: '+repr(error);save()
    security_tasks.append(asyncio.create_task(secure()))
  device.on(device.EVENT_CONNECTION,connected)
  original_open=host.on_l2cap_channel_open;original_close=host.on_l2cap_channel_close
  opened_channels={};closed_channels=set()
  def record_open(channel):
   assert channel.state==channel.State.OPEN and channel.connection.is_encrypted
   if id(channel) in opened_channels:return
   opened_channels[id(channel)]=channel;state.setdefault('channel_opens',[]).append(dict(psm=channel.psm,handle=channel.connection.handle,encrypted=channel.connection.is_encrypted))
   if host.l2cap_ctrl_channel and host.l2cap_intr_channel:state['connections']+=1
   save()
  def opened(channel):
   original_open(channel);record_open(channel)
  def closed(channel):
   original_close(channel)
   if id(channel) in opened_channels and id(channel) not in closed_channels:
    closed_channels.add(id(channel));state['closed_channels']+=1;save()
  host.on_l2cap_channel_open=opened;host.on_l2cap_channel_close=closed
  async def control(operation,expected):
   assert controls.empty(),('unexpected prior control packet',await controls.get())
   operation();got=await asyncio.wait_for(controls.get(),8);assert got==expected,(got.hex(),expected.hex())
  async def exchange():
   state['phase']='waiting_channels';save();await wait(lambda:state['connections']>=1,120)
   passed('Android opens actual HID control and interrupt L2CAP channels to the explicitly paired virtual host')
   state['phase']='get_report';save();initial=bytes(i%256 for i in range(510));await control(lambda:host.get_report(3,1,0),b'\xa3\x01'+initial)
   passed('GET_REPORT returns all510 VM-owned bytes through the real HID control channel, including zero/high-bit data')
   await control(lambda:host.get_report(3,2,0),b'\x02')
   passed('an invalid report ID receives the VM-selected actual HID error handshake2')
   state['phase']='set_report';save();value=bytes((i*7+13)%256 for i in range(510));await control(lambda:host.set_report(2,b'\x01'+value),b'\x00');await control(lambda:host.get_report(2,1,0),b'\xa2\x01'+value)
   passed('SET_REPORT is explicitly acknowledged by Flexscript and its510-byte value is read back from VM state')
   state['phase']='interrupt';save();value=bytes((i*11+17)%256 for i in range(510));host.send_pdu_on_intr(b'\xa2\x01'+value);got=await asyncio.wait_for(interrupts.get(),8);assert got==b'\xa1\x01'+value,(len(got),got[:20].hex())
   await control(lambda:host.get_report(2,1,0),b'\xa2\x01'+value)
   passed('510-byte output reports reach Flexscript through interrupt callbacks and return as independently verified input reports')
   state['phase']='protocol';save();await control(lambda:host.set_protocol(0),b'\x00');await control(host.get_protocol,b'\xa0\x00');await control(lambda:host.set_protocol(1),b'\x00');await control(host.get_protocol,b'\xa0\x01')
   passed('Android performs actual boot/report protocol handshakes and reports the resulting protocol over the control channel')
   state['phase']='disconnect_ready';save();await wait(lambda:state['closed_channels']>=2)
   passed('explicit VM HID disconnect closes both real host channels')
   state['phase']='waiting_reconnect';save();await wait(lambda:state['connections']>=2)
   await control(lambda:host.get_report(2,1,0),b'\xa2\x01'+value)
   passed('a fresh HID peer connection serves the VM-persisted report value after explicit disconnect')
   state['phase']='unplug';save();host.send_pdu_on_ctrl(b'\x15');await wait(lambda:state['closed_channels']>=4)
   passed('host virtual-cable unplug causes Android to close both actual HID channels')
   state['done']=True;state['phase']='done';save()
  async def command(phase):
   def observed():
    try:return json.loads(a.command.read_text()).get('phase')==phase
    except (FileNotFoundError,ValueError):return False
   await wait(observed,25)
  async def controls_exchange():
   state['phase']='waiting_timeout_channels';save();await wait(lambda:state['connections']>=1,120)
   began=loop.time();host.get_report(3,1,0);state['phase']='timeout_request_sent';save()
   await wait(lambda:state['closed_channels']>=2,12);state['timeout_close_ms']=round((loop.time()-began)*1000);save()
   passed('an unanswered real GET_REPORT retires both host channels within the configured bounded deadline')
   state['phase']='waiting_overlap_channels';save();await wait(lambda:state['connections']>=2)
   state['timeout_responses']=[]
   while not controls.empty():state['timeout_responses'].append(controls.get_nowait().hex())
   assert all(not bytes.fromhex(value)[0]&0xf0==0xa0 for value in state['timeout_responses']),state
   host.get_report(3,1,0);state['phase']='overlap_first_sent';save();await command('overlap_first_observed')
   began=loop.time();host.get_report(3,1,0);state['phase']='overlap_second_sent';save()
   await wait(lambda:state['closed_channels']>=4,12);state['overlap_close_ms']=round((loop.time()-began)*1000);save()
   state['overlap_responses']=[]
   while not controls.empty():state['overlap_responses'].append(controls.get_nowait().hex())
   assert all(not bytes.fromhex(value)[0]&0xf0==0xa0 for value in state['overlap_responses']),state
   passed('two actual overlapping GET_REPORT packets close the ambiguous registration instead of receiving a guessed reply')
   state['phase']='waiting_fresh_channels';save();await wait(lambda:state['connections']>=3)
   await control(lambda:host.get_report(3,1,0),b'\xa3\x01safe')
   passed('a fresh registration returns only its own report bytes after both failed generations')
   state['phase']='fresh_report_received';save();await command('fresh_survived');await wait(lambda:state['closed_channels']>=6)
   passed('closing the final fresh registration tears down both actual host channels')
   state['done']=True;state['phase']='done';save()
  async def host_reconnect(label):
   await command(label+'_connect_requested')
   if host.connection is None:await device.connect(state['acl_peers'][0],transport=PhysicalTransport.BR_EDR)
   connection=host.connection;assert connection is not None
   if not connection.is_encrypted:
    await asyncio.wait_for(connection.authenticate(),10);await asyncio.wait_for(connection.encrypt(),10)
   assert connection.is_encrypted
   for name in ['control','interrupt']:
    attribute='l2cap_'+('ctrl' if name=='control' else 'intr')+'_channel'
    if getattr(host,attribute) is None:
     await getattr(host,'connect_'+name+'_channel')();channel=getattr(host,attribute)
     assert channel is not None and channel.state==channel.State.OPEN
     channel.on(channel.EVENT_CLOSE,lambda value=channel:closed(value));record_open(channel)
     state.setdefault('peer_opened_channels',[]).append(dict(stage=label,channel=name))
   assert host.l2cap_ctrl_channel is not None and host.l2cap_intr_channel is not None;save()
  async def lifecycle_exchange():
   for index,label in enumerate(['radio','collie_revoke','runtime_revoke']):
    state['phase']='waiting_'+label+'_channels';save()
    if index>0 and a.host_reconnect:await host_reconnect(label)
    await wait(lambda:state['connections']>=index+1,120 if index==0 else 40)
    host.get_report(3,1,0);state['phase']=label+'_request_sent';save();await command(label+'_started')
    marker=json.loads(a.command.read_text());assert marker['phase']==label+'_started';began=marker['at']
    await wait(lambda:state['closed_channels']>=2*(index+1),20)
    delay=round((loop.time()-began)*1000);assert 0<=delay<=10000,(label,delay)
    replies=[]
    while not controls.empty():replies.append(controls.get_nowait().hex())
    assert all((bytes.fromhex(value)[0]&0xf0)!=0xa0 for value in replies),(label,replies)
    state[label+'_close_ms']=delay;state[label+'_responses']=replies;save()
    passed('actual '+label+' closes both pending HID channels without returning report data')
   state['phase']='waiting_fresh_channels';save()
   if a.host_reconnect:await host_reconnect('fresh')
   await wait(lambda:state['connections']>=4)
   await control(lambda:host.get_report(3,1,0),b'\xa3\x01safe')
   passed('a fresh encrypted registration returns only its own report after radio and both permission revocations')
   state['phase']='fresh_report_received';save();await wait(lambda:state['closed_channels']>=8)
   assert len(opened_channels)==8 and all(channel.state==channel.State.CLOSED for channel in opened_channels.values())
   state['all_opened_channels_closed']=True
   passed('final close tears down both fresh channels after all three actual lifecycle transitions')
   state['done']=True;state['phase']='done';save()
  await device.power_on();await device.set_discoverable(True);await device.set_connectable(True);state.update(ready=True,address=str(device.public_address),name=config.name);save()
  flow=exchange
  if a.scenario=='controls':flow=controls_exchange
  elif a.scenario=='lifecycle':flow=lifecycle_exchange
  task=asyncio.create_task(flow())
  try:
   done,_=await asyncio.wait([task,asyncio.create_task(stop.wait())],timeout=300,return_when=asyncio.FIRST_COMPLETED)
   if task in done:await task;await asyncio.wait_for(stop.wait(),120)
  except Exception as error:state['error']=repr(error);save();raise
  finally:
   task.cancel()
   for pending in security_tasks:pending.cancel()
   await asyncio.gather(task,*security_tasks,return_exceptions=True);state['ready']=False;save();await device.power_off()
asyncio.run(main())
