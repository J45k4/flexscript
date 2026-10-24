#!/usr/bin/env python3
"""Independent extended/periodic BLE byte oracle on an owned local Netsim.

Host-only dependency: bumble[android]==0.0.236. No fixture enters the APK.
"""
import argparse,asyncio,json,signal,time,uuid
from pathlib import Path
from types import SimpleNamespace
from bumble.device import (Device,DeviceConfiguration,AdvertisingParameters,
    AdvertisingEventProperties,PeriodicAdvertisingParameters,PeriodicAdvertisingSync)
from bumble.hci import OwnAddressType,HCI_LE_Extended_Advertising_Report_Event
from bumble.transport import open_transport

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--transport',required=True);p.add_argument('--out',type=Path,required=True)
a=p.parse_args()
assert a.transport.startswith(('android-netsim:127.0.0.1:','android-netsim:localhost:')) and ',name=collie-test-' in a.transport
service=uuid.uuid4();wire_uuid=service.bytes[::-1]
def payload(seed,size):return bytes((seed+i*73)%256 for i in range(size))
ads={name:payload(seed,size) for name,seed,size in [('initial',0,96),('updated',129,150),('large',17,100),('scan_response',61,80),('scan_response_update',71,90),('event_limit',155,80)]}
periodic={name:payload(seed,size) for name,seed,size in [('initial',215,110),('updated',42,125)]}
manufacturers={str(0xF000+i):payload(7+i,110) for i in range(3)}
oversized_manufacturers={str(0xF000+i):payload(7+i,210) for i in range(3)}
peer_payload=payload(87,96)
def ad(kind,data):
 assert len(data)<=254
 return bytes([len(data)+1,kind])+data
peer_packet=ad(0x21,wire_uuid+peer_payload)
state=dict(ready=False,service=str(service),ads={k:v.hex() for k,v in ads.items()},
    periodic={k:v.hex() for k,v in periodic.items()},manufacturers={k:v.hex() for k,v in manufacturers.items()},
    oversized_manufacturers={k:v.hex() for k,v in oversized_manufacturers.items()},
    peer_packet=peer_packet.hex(),ad_seen={k:0 for k in ads},periodic_seen={k:0 for k in periodic},
    ad_metadata={},fragment_reports=0,periodic_sync_state='none',errors=[])
def save():
 a.out.parent.mkdir(parents=True,exist_ok=True)
 temp=a.out.with_suffix('.tmp');temp.write_text(json.dumps(state,indent=2)+'\n');temp.replace(a.out)
def fields(raw):
 result=[];at=0
 while at<len(raw):
  size=raw[at]
  if size==0 or at+1+size>len(raw):raise ValueError('Invalid complete AD field length')
  result.append((raw[at+1],raw[at+2:at+1+size]));at+=1+size
 return result
async def main():
 stop=asyncio.Event();loop=asyncio.get_running_loop();tasks=set();sync_started=False
 for sig in [signal.SIGTERM,signal.SIGINT]:loop.add_signal_handler(sig,stop.set)
 async with await open_transport(a.transport) as transport:
  config=DeviceConfiguration();config.name='Collie advertising-set oracle';config.classic_enabled=False;config.le_enabled=True
  device=Device.from_config_with_hci(config,transport.source,transport.sink)
  def periodic_received(report):
   if report.is_truncated:return
   try:rows=fields(report.data_bytes)
   except ValueError as e:state['errors'].append(str(e));save();return
   for name,data in periodic.items():
    if rows==[(0x21,wire_uuid+data)]:state['periodic_seen'][name]+=1;save()
  async def synchronize(address,sid):
   try:
    sync=await device.create_periodic_advertising_sync(address,sid,sync_timeout=5)
    def changed():state['periodic_sync_state']=sync.state.name;save()
    sync.on(sync.EVENT_STATE_CHANGE,changed);sync.on(sync.EVENT_PERIODIC_ADVERTISEMENT,periodic_received);changed()
   except Exception as e:state['errors'].append('periodic sync: '+str(e));save()
  def received(report):
   nonlocal sync_started
   if not report.is_complete or report.is_truncated:return
   try:rows=fields(report.data_bytes)
   except ValueError:return
   relevant=next((data for kind,data in rows if kind==0x21 and data.startswith(wire_uuid)),None)
   if relevant is None:return
   for name,data in ads.items():
    if relevant!=wire_uuid+data:continue
    expected=[(0x21,wire_uuid+data)]
    if name=='large':expected.extend((0xFF,int(key).to_bytes(2,'little')+value) for key,value in manufacturers.items())
    # Android may add a Flags AD field. Every content field must match exactly.
    actual=[row for row in rows if row[0]!=0x01]
    if sorted(actual)!=sorted(expected):continue
    state['ad_seen'][name]+=1
    state['ad_metadata'][name]=dict(address=str(report.address),sid=report.sid,legacy=report.is_legacy,
        scan_response=report.is_scan_response,primary_phy=report.primary_phy,secondary_phy=report.secondary_phy,bytes=len(report.data_bytes))
    if name=='initial' and not report.is_legacy and not sync_started:
     sync_started=True;task=asyncio.create_task(synchronize(report.address,report.sid));tasks.add(task);task.add_done_callback(tasks.discard)
    save()
  # Bumble's ordinary AdvertisementDataAccumulator combines scan responses but
  # does not reassemble extended HCI report fragments. Consume actual HCI reports
  # here and concatenate only DATA_INCOMPLETE_MORE_TO_COME -> DATA_COMPLETE.
  fragments={}
  def raw_received(report):
   if not isinstance(report,HCI_LE_Extended_Advertising_Report_Event.Report):return
   now=time.monotonic()
   for key,(_,at) in list(fragments.items()):
    if now-at>1:del fragments[key]
   flags=int(report.event_type);status=(flags>>5)&3
   key=(str(report.address),report.advertising_sid,flags&31)
   previous=fragments.pop(key,(b'',now))[0]
   if status==2 or len(previous)+len(report.data)>1650:return
   if status==1:
    if len(fragments)>=64:fragments.pop(next(iter(fragments)))
    fragments[key]=(previous+report.data,now);state['fragment_reports']+=1;return
   if status!=0:return
   received(SimpleNamespace(address=report.address,sid=report.advertising_sid,
       is_legacy=bool(flags&16),is_scan_response=bool(flags&8),is_complete=True,is_truncated=False,
       primary_phy=report.primary_phy,secondary_phy=report.secondary_phy,data_bytes=previous+report.data))
  device.host.on('advertising_report',raw_received)
  await device.power_on();await device.start_scanning(legacy=False,active=True,scanning_phys=[1])
  advert=await device.create_advertising_set(advertising_parameters=AdvertisingParameters(
      advertising_event_properties=AdvertisingEventProperties(is_connectable=False,is_scannable=False),
      own_address_type=OwnAddressType.PUBLIC,primary_advertising_interval_min=100,primary_advertising_interval_max=100,
      advertising_sid=9),advertising_data=peer_packet,
      periodic_advertising_parameters=PeriodicAdvertisingParameters(periodic_advertising_interval_min=100,periodic_advertising_interval_max=100),
      periodic_advertising_data=ad(0x21,wire_uuid+payload(103,80)))
  await advert.start_periodic()
  state.update(ready=True,address=str(device.public_address));save()
  try:await asyncio.wait_for(stop.wait(),900)
  except TimeoutError:pass
  finally:
   state['ready']=False;save()
   for task in tasks:task.cancel()
   await device.power_off()
asyncio.run(main())
