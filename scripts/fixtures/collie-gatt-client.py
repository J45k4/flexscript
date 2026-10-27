#!/usr/bin/env python3
"""Local Netsim client that independently exercises a Flexscript-owned GATT server."""
import argparse,asyncio,json,uuid
from pathlib import Path
from bumble import att
from bumble.core import UUID
from bumble.device import Device,DeviceConfiguration,Peer
from bumble.hci import OwnAddressType
from bumble.transport import open_transport
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--transport',required=True);p.add_argument('--config',type=Path,required=True);p.add_argument('--out',type=Path,required=True);a=p.parse_args()
assert a.transport.startswith(('android-netsim:127.0.0.1:','android-netsim:localhost:')) and ',name=collie-test-' in a.transport
config=json.loads(a.config.read_text());ids={key:UUID(str(uuid.UUID(config[key]))) for key in ['service','characteristic','descriptor','slow','control']}
state=dict(ready=False,done=False,error=None,checks=[],phase='starting',advertisements=0)
def save():
 a.out.parent.mkdir(parents=True,exist_ok=True);temp=a.out.with_suffix('.tmp');temp.write_text(json.dumps(state,indent=2)+'\n');temp.replace(a.out)
def passed(text):state['checks'].append(text);save()
def fields(raw):
 at=0
 while at<len(raw):
  size=raw[at]
  if not size or at+size>=len(raw):return
  yield raw[at+1],raw[at+2:at+size+1];at+=size+1
async def main():
 async with await open_transport(a.transport) as transport:
  cfg=DeviceConfiguration();cfg.name='Collie server test client';cfg.classic_enabled=False;cfg.le_enabled=True
  device=Device.from_config_with_hci(cfg,transport.source,transport.sink);target=asyncio.get_running_loop().create_future()
  def advertisement(value):
   state['advertisements']+=1;state['last_advertisement']=value.data_bytes.hex();save()
   wanted=uuid.UUID(config['service']).bytes[::-1]
   if any(kind in [6,7] and wanted in [data[i:i+16] for i in range(0,len(data),16)] for kind,data in fields(value.data_bytes)) and not target.done():target.set_result(value.address)
  device.on(device.EVENT_ADVERTISEMENT,advertisement);await device.power_on();state.update(ready=True,address=str(device.public_address));save()
  connection=None
  try:
   state['phase']='scanning';save();await device.start_scanning(active=False,scanning_phys=[1]);address=await asyncio.wait_for(target,25);state.update(phase='connecting',target=str(address));save();await device.stop_scanning()
   connection=await device.connect(address,own_address_type=OwnAddressType.PUBLIC,timeout=15);peer=Peer(connection);state['phase']='discovering';save()
   await peer.discover_services();service=next(s for s in peer.services if s.uuid==ids['service']);chars=await service.discover_characteristics()
   pair=[c for c in chars if c.uuid==ids['characteristic']];assert len(pair)==2 and pair[0].handle!=pair[1].handle
   primary=next(c for c in pair if c.properties&8);duplicate=next(c for c in pair if not c.properties&8);slow=next(c for c in chars if c.uuid==ids['slow']);control=next(c for c in chars if c.uuid==ids['control'])
   passed('Android registers real services and distinct duplicate-UUID characteristic handles')
   initial=bytes(i%256 for i in range(512));assert await primary.read_value()==initial;assert await duplicate.read_value()==b'second'
   passed('512-byte reads span real ATT Read Blob requests before MTU negotiation and keep duplicate values separate')
   await primary.discover_descriptors();descriptor=primary.get_descriptor(ids['descriptor']);assert descriptor is not None
   assert await descriptor.read_value()==b'\x00\xff\x81\x5a';await descriptor.write_value(b'new\x00\xff',with_response=True);assert await descriptor.read_value()==b'new\x00\xff'
   passed('custom descriptor reads/writes carry zero and high-bit bytes through Flexscript-owned values')
   prepared=bytes((i*7+13)%256 for i in range(512));await peer.gatt_client.write_long_value(primary.handle,prepared);assert await primary.read_value()==prepared
   passed('prepared-write fragments are echoed and the actual execute request commits the complete VM-owned 512-byte value')
   fragment=b'cancelled';response=await peer.gatt_client.send_request(att.ATT_Prepare_Write_Request(attribute_handle=primary.handle,value_offset=0,part_attribute_value=fragment))
   assert response.op_code==att.Opcode.ATT_PREPARE_WRITE_RESPONSE and response.value_offset==0 and response.part_attribute_value==fragment,response
   response=await peer.gatt_client.send_request(att.ATT_Execute_Write_Request(flags=0));assert response.op_code==att.Opcode.ATT_EXECUTE_WRITE_RESPONSE;assert await primary.read_value()==prepared
   passed('cancelled prepared writes leave the previously committed VM value intact')
   response=await peer.gatt_client.send_request(att.ATT_Prepare_Write_Request(attribute_handle=primary.handle,value_offset=510,part_attribute_value=b'overflow'))
   assert response.op_code==att.Opcode.ATT_ERROR_RESPONSE and response.error_code==13,response
   await peer.gatt_client.send_request(att.ATT_Execute_Write_Request(flags=0))
   passed('Flexscript rejects an out-of-range prepared fragment with the actual ATT invalid-length error')
   try:await slow.read_value();raise AssertionError('the intentionally unanswered read succeeded')
   except att.ATT_Error as error:assert error.error_code==14,error
   assert await primary.read_value()==prepared
   passed('an unanswered read expires with actual ATT Unlikely Error14 and the server continues serving subsequent reads')
   assert await peer.request_mtu(517)==517
   received=asyncio.Queue()
   def update(value):received.put_nowait(bytes(value))
   for prefer_notify,value in [(True,bytes(255-i%256 for i in range(512))),(False,bytes((i*11+7)%256 for i in range(512)))]:
    await primary.subscribe(update,prefer_notify=prefer_notify);await primary.write_value(value,with_response=True);assert await asyncio.wait_for(received.get(),8)==value
    assert await primary.read_value()==value;await primary.unsubscribe(update,force=True)
    passed('the VM sends a verified 512-byte '+('notification' if prefer_notify else 'indication')+' after a real CCCD write and acknowledged value update')
   no_response=bytes((i*17+3)%256 for i in range(512));await primary.write_value(no_response,with_response=False)
   for _ in range(10):
    if await primary.read_value()==no_response:break
    await asyncio.sleep(.1)
   else:raise AssertionError('no-response write did not reach VM state')
   passed('no-response writes reach Flexscript without an invented response token or ATT reply')
   for _ in range(20):
    if (await control.read_value())[0]>=2:break
    await asyncio.sleep(.1)
   else:raise AssertionError('SDK notification completions were not observed by the VM')
   await control.write_value(b'STOP',with_response=True);await connection.disconnect();connection=None
   passed('notification completions are observed and the client disconnects after the VM acknowledges stop')
   state['done']=True;save()
  except Exception as error:state['error']=repr(error);save();raise
  finally:
   if connection is not None:
    try:await connection.disconnect()
    except Exception:pass
   state['ready']=False;save();await device.power_off()
asyncio.run(main())
