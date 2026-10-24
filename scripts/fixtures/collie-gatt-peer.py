#!/usr/bin/env python3
"""Controlled local Netsim GATT server with byte/status/notification oracles."""
import argparse,asyncio,json,signal,uuid
from pathlib import Path
from bumble import att
from bumble.core import UUID
from bumble.device import Device,DeviceConfiguration,AdvertisingType
from bumble.gatt import Service,Characteristic,CharacteristicValue,Descriptor
from bumble.hci import OwnAddressType
from bumble.transport import open_transport
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--transport',required=True);p.add_argument('--out',type=Path,required=True);a=p.parse_args()
assert a.transport.startswith(('android-netsim:127.0.0.1:','android-netsim:localhost:')) and ',name=collie-test-' in a.transport
state=dict(ready=False,connected=False,closed=False,writes=0,notifications=0,indications=0,notify=False,indicate=False,denied=0,slow_started=False,slow_returned=False,error=None)
for key in ['service','characteristic','descriptor','denied_characteristic','slow_characteristic']:state[key]=str(uuid.uuid4())
payload=bytes(i%256 for i in range(512))
def save():
 a.out.parent.mkdir(parents=True,exist_ok=True);temp=a.out.with_suffix('.tmp');temp.write_text(json.dumps(state,indent=2)+'\n');temp.replace(a.out)
async def main():
 stop=asyncio.Event();loop=asyncio.get_running_loop()
 for sig in [signal.SIGTERM,signal.SIGINT]:loop.add_signal_handler(sig,stop.set)
 async with await open_transport(a.transport) as transport:
  config=DeviceConfiguration();config.name='Collie GATT fixture';config.classic_enabled=False;config.le_enabled=True
  device=Device.from_config_with_hci(config,transport.source,transport.sink);device.gatt_server.max_mtu=517
  async def written(connection,value):
   if value!=payload:state['error']='GATT write differs from the 512-byte oracle';save();return
   state['writes']+=1;save()
   if state['notify']:
    await device.notify_subscribers(characteristic,payload);state['notifications']+=1;save()
   if state['indicate']:
    await device.indicate_subscribers(characteristic,payload);state['indications']+=1;save()
  descriptor=Descriptor(UUID(state['descriptor']),att.Attribute.READABLE|att.Attribute.WRITEABLE,b'\x00\xff\x81\x5a')
  characteristic=Characteristic(state['characteristic'],Characteristic.READ|Characteristic.WRITE|Characteristic.WRITE_WITHOUT_RESPONSE|Characteristic.NOTIFY|Characteristic.INDICATE,att.Attribute.READABLE|att.Attribute.WRITEABLE,CharacteristicValue(read=lambda connection:payload,write=written),[descriptor])
  def subscription(bearer,notify,indicate):state.update(notify=notify,indicate=indicate);save()
  characteristic.on(characteristic.EVENT_SUBSCRIPTION,subscription)
  duplicate=Characteristic(state['characteristic'],Characteristic.READ,att.Attribute.READABLE,b'duplicate')
  def denied(connection):state['denied']+=1;save();raise att.ATT_Error(att.ErrorCode.INSUFFICIENT_AUTHORIZATION)
  async def slow(connection):
   state['slow_started']=True;save();await asyncio.sleep(6);state['slow_returned']=True;save();return b'late response'
  reject=Characteristic(state['denied_characteristic'],Characteristic.READ,att.Attribute.READABLE,CharacteristicValue(read=denied))
  delay=Characteristic(state['slow_characteristic'],Characteristic.READ,att.Attribute.READABLE,CharacteristicValue(read=slow))
  device.add_service(Service(state['service'],[characteristic,duplicate,reject,delay]))
  def connected(connection):
   state['connected']=True;save()
   def disconnected(reason):state['closed']=True;save()
   connection.on(connection.EVENT_DISCONNECTION,disconnected)
  device.on(device.EVENT_CONNECTION,connected)
  await device.power_on()
  packet=b'\x02\x01\x06'+bytes([17,7])+uuid.UUID(state['service']).bytes[::-1]
  await device.start_advertising(advertising_type=AdvertisingType.UNDIRECTED_CONNECTABLE_SCANNABLE,own_address_type=OwnAddressType.PUBLIC,advertising_data=packet,scan_response_data=b'')
  state.update(ready=True,address=str(device.public_address));save()
  try:await asyncio.wait_for(stop.wait(),600)
  except TimeoutError:pass
  finally:state['ready']=False;save();await device.power_off()
asyncio.run(main())
