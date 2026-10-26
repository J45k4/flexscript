#!/usr/bin/env python3
"""Local Netsim BLE advertiser/observer with independent raw AD byte oracles.

Host dependency: bumble[android]==0.0.236. Nothing is packaged in the APK.
"""
import argparse,asyncio,json,signal,uuid
from pathlib import Path
from bumble.device import Device,DeviceConfiguration,AdvertisingType
from bumble.hci import OwnAddressType
from bumble.transport import open_transport

p=argparse.ArgumentParser(description=__doc__);p.add_argument('--transport',required=True);p.add_argument('--out',type=Path,required=True);a=p.parse_args()
assert a.transport.startswith(('android-netsim:127.0.0.1:','android-netsim:localhost:')) and ',name=collie-test-' in a.transport
service=uuid.uuid4();service_bytes=service.bytes[::-1];peer_payload=b'\x00\xff\x5a\x81';android_payload=b'\xff\x00\x81\x5a'
packet=b'\x02\x01\x06'+bytes([17+len(peer_payload),0x21])+service_bytes+peer_payload
state=dict(ready=False,service=str(service),packet=packet.hex(),android_payload=android_payload.hex(),seen=0)
def save():
 a.out.parent.mkdir(parents=True,exist_ok=True);temp=a.out.with_suffix('.tmp');temp.write_text(json.dumps(state,indent=2)+'\n');temp.replace(a.out)
def fields(raw):
 at=0
 while at<len(raw):
  size=raw[at]
  if not size:return
  if at+1+size>len(raw):return
  yield raw[at+1],raw[at+2:at+1+size];at+=1+size
async def main():
 stop=asyncio.Event();loop=asyncio.get_running_loop()
 for sig in [signal.SIGTERM,signal.SIGINT]:loop.add_signal_handler(sig,stop.set)
 async with await open_transport(a.transport) as transport:
  config=DeviceConfiguration();config.name='Collie BLE fixture';config.classic_enabled=False;config.le_enabled=True
  device=Device.from_config_with_hci(config,transport.source,transport.sink)
  def received(advertisement):
   if any(kind==0x21 and data==service_bytes+android_payload for kind,data in fields(advertisement.data_bytes)):
    state['seen']+=1;state['seen_address']=str(advertisement.address);save()
  device.on(device.EVENT_ADVERTISEMENT,received)
  await device.power_on();await device.start_scanning(active=False,scanning_phys=[1])
  await device.start_advertising(advertising_type=AdvertisingType.UNDIRECTED_SCANNABLE,own_address_type=OwnAddressType.PUBLIC,advertising_data=packet,scan_response_data=b'',advertising_interval_min=100,advertising_interval_max=100)
  state.update(ready=True,address=str(device.public_address));save()
  try:await asyncio.wait_for(stop.wait(),300)
  except TimeoutError:pass
  finally:
   state['ready']=False;save();await device.power_off()
asyncio.run(main())
