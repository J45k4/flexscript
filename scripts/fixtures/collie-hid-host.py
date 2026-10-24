#!/usr/bin/env python3
"""Controlled localhost HID host. Vendor reports are observed here, never sent to a desktop."""
import argparse,asyncio,json,signal,uuid
from pathlib import Path
from bumble.device import Device,DeviceConfiguration
from bumble.hid import Host,Message
from bumble.transport import open_transport
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--transport',required=True);p.add_argument('--out',type=Path,required=True);a=p.parse_args()
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
  device=Device.from_config_with_hci(config,transport.source,transport.sink);host=Host(device);controls=asyncio.Queue();interrupts=asyncio.Queue()
  host.on(host.EVENT_CONTROL_DATA,lambda value:controls.put_nowait(bytes(value)))
  host.on(host.EVENT_HANDSHAKE,lambda value:controls.put_nowait(bytes([int(value)])))
  host.on(host.EVENT_INTERRUPT_DATA,lambda value:interrupts.put_nowait(bytes(value)))
  def connected(connection):
   state['acl_connected']=True;save()
   connection.on(connection.EVENT_CONNECTION_ENCRYPTION_CHANGE,lambda:(state.update(encrypted=connection.is_encrypted),save()))
  device.on(device.EVENT_CONNECTION,connected)
  original_open=host.on_l2cap_channel_open;original_close=host.on_l2cap_channel_close
  def opened(channel):
   original_open(channel)
   if host.l2cap_ctrl_channel and host.l2cap_intr_channel:state['connections']+=1;save()
  def closed(channel):original_close(channel);state['closed_channels']+=1;save()
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
  await device.power_on();await device.set_discoverable(True);await device.set_connectable(True);state.update(ready=True,address=str(device.public_address),name=config.name);save()
  task=asyncio.create_task(exchange())
  try:
   done,_=await asyncio.wait([task,asyncio.create_task(stop.wait())],timeout=300,return_when=asyncio.FIRST_COMPLETED)
   if task in done:await task;await asyncio.wait_for(stop.wait(),120)
  except Exception as error:state['error']=repr(error);save();raise
  finally:
   task.cancel();await asyncio.gather(task,return_exceptions=True);state['ready']=False;save();await device.power_off()
asyncio.run(main())
