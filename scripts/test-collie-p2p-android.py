#!/usr/bin/env python3
"""Wi-Fi Direct through Flexscript/VM/JNI on two isolated headless emulators."""
import argparse,hashlib,json,re,subprocess,time,uuid,xml.etree.ElementTree as ET
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);p.add_argument('--serial',default='emulator-5580');p.add_argument('--peer',default='emulator-5582');p.add_argument('--services-only',action='store_true');p.add_argument('--query-all',action='store_true');p.add_argument('--adb',default='/opt/android-sdk/platform-tools/adb');a=p.parse_args();assert a.serial.startswith('emulator-') and a.peer.startswith('emulator-') and a.serial!=a.peer
out=a.out.resolve();pkg='org.flexscript.collie';prefix='p2p-hw-'+uuid.uuid4().hex[:8];devices=[a.serial,a.peer];names={s:[] for s in devices};sessions={s:prefix+'-'+str(i) for i,s in enumerate(devices)};checks=[];original={};before={};granted={};flags={};location={};wifi={}
permissions=['android.permission.NEARBY_WIFI_DEVICES','android.permission.ACCESS_COARSE_LOCATION','android.permission.ACCESS_FINE_LOCATION']
def adb(s,*args,data=None,check=True):
 r=subprocess.run([a.adb,'-s',s,*map(str,args)],input=data,capture_output=True,timeout=45)
 if check:assert r.returncode==0,(s,args,r.stdout[:400],r.stderr[:400])
 return r.stdout
def read(s,path):
 try:return json.loads(adb(s,'exec-out','run-as',pkg,'cat',path,check=False))
 except ValueError:return None
def wait(test,seconds=90):
 end=time.monotonic()+seconds
 while time.monotonic()<end:
  value=test()
  if value:return value
  time.sleep(.2)
 raise AssertionError('P2P fixture timed out')
def start(s,**case):
 name=prefix+'-'+uuid.uuid4().hex[:8];names[s].append(name);case=dict(session=sessions[s],hardware_preserve_handles=True,**case)
 adb(s,'shell','run-as',pkg,'sh','-c',"'umask 077; cat > files/test/"+name+".json'",data=json.dumps(case).encode());adb(s,'shell','am','start','-n',pkg+'/.MainActivity','--es','test_case',name);return name
PRINT='fn emit(v){db_io(0,1,db_word(v),db_bytes(v));}fn number(n){let p=alloc(32);let i=32;while n>=10{i=i-1;store8(p+i,48+n%10);n=n/10;}i=i-1;store8(p+i,48+n);db_io(0,1,p+i,32-i);}'
def source(text):return 'fn fail(n){let e=db_error();db_io(0,2,e,db_len(e));return n;}'+PRINT+re.sub(r'return ([1-9][0-9]*);',r'return fail(\1);',text)
def result(s,name):
 r=wait(lambda:read(s,'files/test/'+name+'.result.json'));assert r['ok'],r;return r

def observation(r):
 if 'observation' in r:o=r['observation']
 else:o=next(json.loads(m['output']) for m in r['messages'] if m.get('type')=='custom_tool_call_output')
 assert o['state']=='continue' and o['exit_code']==0,o
 return o

def vm(s,text):return observation(result(s,start(s,source=source(text))))
def passed(text):checks.append(text);print('PASS',text,flush=True)
def tree(s):
 adb(s,'shell','uiautomator','dump','/data/local/tmp/collie-p2p.xml');return ET.fromstring(adb(s,'exec-out','cat','/data/local/tmp/collie-p2p.xml'))
def tap(s,node):
 x,y,z,w=map(int,re.findall(r'\d+',node.get('bounds')));adb(s,'shell','input','tap',(x+z)//2,(y+w)//2)
def button(s,label=None,suffix=None):
 root=tree(s);node=next((n for n in root.iter('node') if label and label in [n.get('text'),n.get('content-desc')] or suffix and n.get('resource-id','').endswith(suffix)),None);assert node is not None,ET.tostring(root).decode();tap(s,node)
def pending(s,key,phase):
 def check():
  saved=read(s,'files/workspaces/'+sessions[s]+'/session.json') or {};return saved if saved.get('phase')==phase and (saved.get('pending_execution') or {}).get('signal',{}).get('key')==key else None
 return wait(check)
def conversation(text):
 token=uuid.uuid4().hex;return [{'type':'response.completed','response':{'status':'completed','output':[{'type':'custom_tool_call','call_id':'call_'+token,'id':'ctc_'+token,'name':'flexscript','input':source(text)}]}},{'type':'response.completed','response':{'status':'completed','output':[{'type':'message','role':'assistant','content':[{'type':'output_text','text':'P2P check finished'}]}]}}]
def host_peer(s):
 o=vm(s,'fn main(){let h=state_get("p2p");let page=p2p_peers(db_word(h),0,16);if !page{return 1;}let peers=device_field(page,"peers");if db_count(peers)>1{return 2;}if db_count(peers)==1{let peer=db_at(peers,0);if db_word(device_field(peer,"group_owner")){return 0;}state_set("target",device_field(peer,"id"));emit(device_field(peer,"name"));}return 0;}')
 return o['stdout']
for s in devices:
 adb(s,'shell','run-as',pkg,'mkdir','-p','files/test');prefs=ET.fromstring(adb(s,'exec-out','run-as',pkg,'cat','shared_prefs/MainActivity.xml'));original[s]=next(n.text for n in prefs if n.get('name')=='session');before[s]=read(s,'files/workspaces/'+original[s]+'/session.json') or {'messages':[],'permissions':{}};state=adb(s,'shell','dumpsys','package',pkg).decode();granted[s]={v:bool(re.search(re.escape(v)+r': granted=true',state)) for v in permissions};flags[s]={v:((re.search(re.escape(v)+r': granted=\w+, flags=\[([^]]*)\]',state) or [None,''])[1]) for v in permissions};location[s]=adb(s,'shell','cmd','location','is-location-enabled').decode().strip();wifi[s]='Wifi is enabled' in adb(s,'shell','cmd','wifi','status').decode()
try:
 for s in devices:
  adb(s,'shell','am','force-stop',pkg);adb(s,'shell','cmd','location','set-location-enabled','true');adb(s,'shell','cmd','wifi','set-wifi-enabled','disabled')
 for s in devices:
  wait(lambda:'curState=P2pDisabledState' in adb(s,'shell','dumpsys','wifip2p').decode())
  adb(s,'shell','cmd','wifi','set-wifi-enabled','enabled')
 s=a.serial;adb(s,'shell','am','force-stop',pkg)
 for permission in reversed(permissions):adb(s,'shell','pm','revoke',pkg,permission,check=False);adb(s,'shell','pm','clear-permission-flags',pkg,permission,'user-set','user-fixed')
 name=start(s,prompt='Open virtual Wi-Fi Direct',initial_permissions={'db_read':True,'db_write':True},responses=conversation('fn main(){let h=p2p_open();if !h{return 1;}return state_set("p2p",h)-1;}'))
 pending(s,'wifi','permission');button(s,label='Allow requested access');pending(s,'location','permission');button(s,label='Allow requested access');pending(s,'wifi','platform_permission');button(s,suffix='permission_allow_button');pending(s,'location','platform_permission');button(s,suffix='permission_allow_foreground_only_button');observation(result(s,name))
 passed('P2P open checkpoints both Collie grants and yields for actual Android Nearby and precise Location dialogs')
 for permission in permissions:adb(a.peer,'shell','pm','grant',pkg,permission)
 observation(result(a.peer,start(a.peer,source=source('fn main(){let h=p2p_open();if !h{return 1;}return state_set("p2p",h)-1;}'),initial_permissions={'wifi':True,'location':True,'db_read':True,'db_write':True})))
 for s in devices:
  vm(s,'fn main(){let h=state_get("p2p");let info=device_info(db_word(h));if !info{return 1;}if p2p_open(){return 2;}let e=device_error();if db_count(e)!=2 || !worker_equal(db_word(db_at(e,0)),"busy"){return 3;}let p=p2p_peers(db_word(h),0,16);if !p || db_kind(device_field(p,"peers"))!=5{return 4;}if p2p_group_credentials(db_word(h)){return 5;}return 0;}')
 passed('both actual Android P2P channels initialize, page typed peers and reject a second active channel without disturbing the first')
 vm(a.serial,'fn main(){let h=state_get("p2p");let i=0;while i<100{let e=device_wait(db_word(h),0);if !e{return 1;}i=i+1;}return 0;}')
 passed('100 hardware polls complete in one native invocation under the unchanged memory cap')
 if not a.services_only:
  for s in devices:vm(s,'fn main(){return db_word(p2p_discover(db_word(state_get("p2p"))))-1;}')
  for s in devices:wait(lambda:host_peer(s))
  passed('the two emulators discover each other through real P2P radios and channel-scoped peer IDs')
  # Configured owner group: verify metadata/secret separation, then remove it.
  vm(a.peer,'fn main(){let h=state_get("p2p");if !p2p_group_create_config(db_word(h),"DIRECT-CF-Collie","collie-peer-test",1){return 1;}return 0;}')
  def owner_ready():
   return vm(a.peer,'fn main(){let g=p2p_group(db_word(state_get("p2p")));if db_kind(g)==5 && db_word(device_field(g,"interface_up")){let c=p2p_group_credentials(db_word(state_get("p2p")));if !worker_equal(db_word(device_field(c,"password")),"collie-peer-test"){return 1;}if db_kind(device_field(g,"password"))!=0{return 2;}emit(device_field(g,"interface"));}return 0;}')['stdout']
  wait(owner_ready);passed('Android creates an ephemeral configured P2P group with a real interface and exposes its passphrase only via the owner-credentials call')
  vm(a.peer,'fn main(){return db_word(p2p_group_remove(db_word(state_get("p2p"))))-1;}')
  wait(lambda:vm(a.peer,'fn main(){let g=p2p_group(db_word(state_get("p2p")));if db_kind(g)==0{db_io(0,1,"gone",4);}return 0;}')['stdout'])
  for s in devices:vm(s,'fn main(){return db_word(p2p_discover(db_word(state_get("p2p"))))-1;}')
  for s in devices:wait(lambda:host_peer(s))
  vm(a.serial,'fn main(){let h=state_get("p2p");if !p2p_connect(db_word(h),db_word(state_get("target")),"pbc","",0){return 1;}return 0;}')
  # Accept only the virtual partner's Android-owned P2P invitation.
  trace=[];end=time.monotonic()+70
  while time.monotonic()<end:
   info=vm(a.serial,'fn main(){let c=p2p_connection(db_word(state_get("p2p")));if db_word(device_field(c,"formed")){emit(device_field(c,"owner_address"));}return 0;}')['stdout']
   if info:break
   for device in devices:
    root=tree(device);trace.append({'serial':device,'texts':[(n.get('package'),n.get('text')) for n in root.iter('node') if n.get('text')]});trace=trace[-30:]
    button_node=next((n for n in root.iter('node') if n.get('text','').lower() in ['accept','connect','allow','ok'] and n.get('package') in ['android','com.android.wifi.dialog','com.google.android.wifi.dialog','com.android.settings']),None)
    if button_node is not None:(out/'p2p-invitation.png').write_bytes(adb(device,'exec-out','screencap','-p'));tap(device,button_node)
   (out/'p2p-negotiation-ui.json').write_text(json.dumps(trace,indent=2)+'\n')
   time.sleep(.2)
  else:raise AssertionError('The real P2P group negotiation did not complete')
  owner_ip=info
  vm(a.peer,'fn main(){let h=state_get("p2p");let g=p2p_group_attach(db_word(h));if !g{return 1;}if p2p_group_credentials(db_word(h)){return 2;}let e=device_error();if db_count(e)!=2 || !worker_equal(db_word(db_at(e,0)),"not_owned"){return 3;}if p2p_group_remove(db_word(h)){return 4;}return 0;}')
  passed('PBC pairing forms a real group; explicit incoming-group attach grants data access without removal rights or credentials')
  # Separate setup and blocking programs keep real OS sockets across VM calls.
  port=int(vm(a.peer,'fn main(){let h=p2p_tcp_listen(db_word(state_get("p2p")),0,4);if !h{return 1;}state_set("listen",h);number(db_word(device_field(device_info(db_word(h)),"port")));return 0;}')['stdout'])
  server=start(a.peer,source=source('fn main(){let s=p2p_tcp_accept(db_word(state_get("listen")),8000);if !s{return 1;}let at=0;while at<32768{let bytes=device_read(db_word(s),32768-at,4000);if db_kind(bytes)!=3 || !db_bytes(bytes){return 2;}let i=0;while i<db_bytes(bytes){if load8(db_word(bytes)+i)!=(at+i)%256{return 3;}i=i+1;}if db_word(device_write(db_word(s),bytes))!=db_bytes(bytes){return 4;}at=at+db_bytes(bytes);}device_close(db_word(s));return 0;}'))
  vm(a.serial,'fn main(){let s=p2p_tcp_connect(db_word(state_get("p2p")),"'+owner_ip+'",'+str(port)+',4000);if !s{return 1;}let p=alloc(32768);let i=0;while i<32768{store8(p+i,i%256);i=i+1;}if db_word(device_write(db_word(s),db_blob(p,32768)))!=32768{return 2;}let at=0;while at<32768{let b=device_read(db_word(s),32768-at,4000);if db_kind(b)!=3 || !db_bytes(b){return 3;}i=0;while i<db_bytes(b){if load8(db_word(b)+i)!=(at+i)%256{return 4;}i=i+1;}at=at+db_bytes(b);}return device_close(db_word(s))-1;}');observation(result(a.peer,server))
  passed('32KiB of TCP data crosses the real P2P interface and two Flexscript VMs with every byte independently checked in both directions')
  port=int(vm(a.peer,'fn main(){let h=p2p_udp_open(db_word(state_get("p2p")),0);if !h{return 1;}state_set("udp",h);number(db_word(device_field(device_info(db_word(h)),"port")));return 0;}')['stdout'])
  server=start(a.peer,source=source('fn main(){let h=state_get("udp");let r=p2p_udp_receive(db_word(h),32768,8000);if !r{return 1;}let b=device_field(r,"data");if db_bytes(b)!=32768 || db_word(device_field(r,"truncated")){return 2;}let i=0;while i<32768{if load8(db_word(b)+i)!=i%256{return 3;}i=i+1;}if db_word(p2p_udp_send(db_word(h),db_word(device_field(r,"address")),db_word(device_field(r,"port")),b))!=32768{return 4;}return 0;}'))
  vm(a.serial,'fn main(){let h=p2p_udp_open(db_word(state_get("p2p")),0);if !h{return 1;}state_set("udp",h);let p=alloc(32768);let i=0;while i<32768{store8(p+i,i%256);i=i+1;}if db_word(p2p_udp_send(db_word(h),"'+owner_ip+'",'+str(port)+',db_blob(p,32768)))!=32768{return 2;}let r=p2p_udp_receive(db_word(h),32768,8000);let b=device_field(r,"data");if db_bytes(b)!=32768 || db_word(device_field(r,"truncated")){return 3;}i=0;while i<32768{if load8(db_word(b)+i)!=i%256{return 4;}i=i+1;}if p2p_udp_send(db_word(h),"203.0.113.1",1234,db_text("no")){return 5;}let e=device_error();if db_count(e)!=2 || !worker_equal(db_word(db_at(e,0)),"outside_group"){return 6;}return 0;}');observation(result(a.peer,server))
  passed('32KiB UDP round trips preserve source metadata and all binary values; traffic outside the P2P subnet is rejected')
  vm(a.serial,'fn main(){return db_word(p2p_group_remove(db_word(state_get("p2p"))))-1;}')
  for s in devices:
   wait(lambda:vm(s,'fn main(){let c=p2p_connection(db_word(state_get("p2p")));if !db_word(device_field(c,"formed")){db_io(0,1,"gone",4);}return 0;}')['stdout'])
   vm(s,'fn main(){if device_info(db_word(state_get("udp"))){return 1;}let e=device_error();if db_count(e)!=2 || !worker_equal(db_word(db_at(e,0)),"stale_handle"){return 2;}return 0;}')
 # Publish before initiating discovery so the virtual peers advertise a fresh service update.
 typ='_cf'+uuid.uuid4().hex[:8]+'._tcp';instance='collie-'+uuid.uuid4().hex[:8];browse_type='' if a.query_all else typ
 vm(a.peer,'fn main(){let attrs=db_list();let row=db_list();db_add(row,db_text("vm"));db_add(row,db_text("flexscript"));db_add(attrs,row);let h=p2p_dns_sd_publish(db_word(state_get("p2p")),"'+instance+'","'+typ+'",attrs);if !h{return 1;}state_set("dns_ad",h);if p2p_dns_sd_publish(db_word(state_get("p2p")),"'+instance+'","'+typ+'",attrs){return 2;}let e=device_error();if db_count(e)!=2 || !worker_equal(db_word(db_at(e,0)),"busy"){return 3;}return 0;}')
 vm(a.peer,'fn main(){return db_word(p2p_discover(db_word(state_get("p2p"))))-1;}')
 vm(a.serial,'fn main(){let h=p2p_dns_sd_browse(db_word(state_get("p2p")),"'+browse_type+'");if !h{return 1;}state_set("dns_query",h);if p2p_dns_sd_browse(db_word(state_get("p2p")),"'+browse_type+'"){return 2;}let e=device_error();if db_count(e)!=2 || !worker_equal(db_word(db_at(e,0)),"busy"){return 3;}let txt=p2p_dns_sd_txt(db_word(state_get("p2p")),"'+instance+'","'+typ+'");if !txt{return 4;}state_set("dns_txt_query",txt);return db_word(p2p_service_discover(db_word(state_get("p2p"))))-1;}')
 vm(a.serial,'fn main(){let h=state_get("p2p");let seen=0;let i=0;while i<80 && seen!=3{let e=device_wait(db_word(h),1000);if db_kind(e)==5{let kind=device_field(e,"event");emit(kind);db_io(0,1," ",1);emit(device_field(e,"instance"));emit(device_field(e,"domain"));emit(device_field(e,"message"));db_io(0,1,"\\n",1);if worker_equal(db_word(kind),"dns_service") && worker_equal(db_word(device_field(e,"instance")),"'+instance+'"){seen=seen|1;}if worker_equal(db_word(kind),"dns_txt") && worker_equal(db_word(device_field(e,"domain")),"'+instance+'.'+typ+'.local."){let attrs=device_field(e,"attributes");if worker_equal(db_word(device_field(attrs,"vm")),"flexscript"){seen=seen|2;}}}i=i+1;}if seen!=3{return 1;}return 0;}')
 passed('real cross-emulator DNS-SD returns the published service and TXT through copied VM events; duplicate leases cannot remove the original registration')
 for s in devices:vm(s,'fn main(){return device_close(db_word(state_get("p2p")))-1;}')
 passed('parent closure releases discovery and service resources')
 r=result(a.serial,start(a.serial,hardware_tests=True,hardware_revocation_tests=True))
 for check in r['hardware']['checks']:passed(check)
except Exception as failure:
 (out/'p2p-last-failure.json').write_text(json.dumps(dict(error=str(failure),services_only=a.services_only,query_all=a.query_all,apk_sha256=hashlib.sha256((out/'collie.apk').read_bytes()).hexdigest()),indent=2)+'\n')
 raise
finally:
 for s in devices:
  adb(s,'shell','am','force-stop',pkg)
  for permission in reversed(permissions):
   if not granted[s][permission]:adb(s,'shell','pm','revoke',pkg,permission,check=False)
  for permission in permissions:
   if granted[s][permission]:adb(s,'shell','pm','grant',pkg,permission)
  for permission in permissions:
   adb(s,'shell','pm','clear-permission-flags',pkg,permission,'user-set','user-fixed');restore=[name for name,flag in [('user-set','USER_SET'),('user-fixed','USER_FIXED')] if flag in [v.strip() for v in flags[s][permission].split('|')]]
   if restore:adb(s,'shell','pm','set-permission-flags',pkg,permission,*restore)
  adb(s,'shell','cmd','location','set-location-enabled',location[s]);adb(s,'shell','cmd','wifi','set-wifi-enabled','enabled' if wifi[s] else 'disabled');adb(s,'shell','am','force-stop',pkg)
  name=prefix+'-restore';names[s].append(name);case=dict(session=original[s],resume_only=True,initial_permissions=None);adb(s,'shell','run-as',pkg,'sh','-c',"'cat > files/test/"+name+".json'",data=json.dumps(case).encode());adb(s,'shell','am','start','-n',pkg+'/.MainActivity','--es','test_case',name);result(s,name)
  after=read(s,'files/workspaces/'+original[s]+'/session.json');assert before[s]['messages']==after['messages']
  for key,value in before[s].get('permissions',{}).items():assert after['permissions'][key]==value
  adb(s,'shell','run-as',pkg,'rm','-rf','files/workspaces/'+sessions[s])
  for name in names[s]:adb(s,'shell','run-as',pkg,'rm','-f','files/test/'+name+'.json','files/test/'+name+'.result.json')
passed('both original conversations and grants preserved; temporary workspaces removed')
report=dict(count=len(checks),checks=checks,serial=a.serial,peer=a.peer,services_only=a.services_only,query_all=a.query_all,apk_sha256=hashlib.sha256((out/'collie.apk').read_bytes()).hexdigest());(out/('p2p-services-android-report.json' if a.services_only else 'p2p-android-report.json')).write_text(json.dumps(report,indent=2)+'\n');print(len(checks),'Android P2P groups passed')
