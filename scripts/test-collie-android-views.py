#!/usr/bin/env python3
"""Exercise workspace text/image views on an installed debug Collie APK.

Requires an explicit device. --live verifies actual model file reading and vision;
--picker also imports a synthetic image using Android's real document picker.
All test sessions/files are removed and the original conversation is restored.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess
import time
import xml.etree.ElementTree as ET
import zlib

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--serial',required=True)
p.add_argument('--out',type=Path,default=Path('build/android-collie'))
p.add_argument('--adb',default='/opt/android-sdk/platform-tools/adb')
p.add_argument('--live',action='store_true')
p.add_argument('--picker',action='store_true')
p.add_argument('--media',action='store_true',help='Exercise Gallery/Camera; capture synthetic photos only on emulator devices')
p.add_argument('--media-only',action='store_true',help='Run targeted photo/camera checks after seeding a private workspace')
args=p.parse_args();args.media=args.media or args.media_only;out=args.out.resolve()/'views'/args.serial;out.mkdir(parents=True,exist_ok=True)
pkg='org.flexscript.collie';checks=[];requests=[]

def adb(*command,data=b'',check=True):
    r=subprocess.run([args.adb,'-s',args.serial,*map(str,command)],input=data,capture_output=True,timeout=40)
    if check and r.returncode:raise RuntimeError((command,r.stdout[:300],r.stderr[:300]))
    return r.stdout

def saved(session):return json.loads(adb('exec-out','run-as',pkg,'cat','files/workspaces/'+session+'/session.json'))
for _ in range(30):
    try:
        prefs=ET.fromstring(adb('exec-out','run-as',pkg,'cat','shared_prefs/MainActivity.xml',check=False));break
    except ET.ParseError:time.sleep(.5)
else:raise AssertionError('App has not initialized its first conversation')
original=next(n.text for n in prefs if n.get('name')=='session');before=saved(original)
sid='views-check-'+str(time.time_ns());filename='collie-views-'+str(time.time_ns())+'.png'

def put(path,data):
    assert re.fullmatch(r'[A-Za-z0-9/._-]+',path)
    adb('shell','run-as',pkg,'sh','-c',"'cat > "+path+"'",data=data)

def case(name,request):
    request.setdefault('initial_permissions',dict.fromkeys(['internet','files_read','files_write','db_read','db_write','history','workers'],True))
    requests.append(name);request.setdefault('session',sid);path='files/test/'+name
    # Kill only between fixture operations, after a previous result is saved.
    # This also makes recovery deterministic if the model transport times out.
    adb('shell','am','force-stop',pkg)
    adb('shell','run-as',pkg,'mkdir','-p','files/test')
    put(path+'.json',json.dumps(request).encode());adb('shell','run-as',pkg,'rm','-f',path+'.result.json')
    adb('shell','am','start','-n',pkg+'/.MainActivity','--es','test_case',name)
    until=time.monotonic()+180
    while time.monotonic()<until:
        raw=adb('exec-out','run-as',pkg,'cat',path+'.result.json',check=False)
        if raw.lstrip().startswith(b'{'):
            r=json.loads(raw);time.sleep(.5)
            (out/(name+'.json')).write_text(json.dumps(r,indent=2)+'\n')
            assert r.get('ok'),r
            return r
        time.sleep(.5)
    raise AssertionError('Timed out '+name)

def execute(name,source):return case(name,dict(source=source))['observation']
def tree(name='ui'):
    # uiautomator can return success without writing a hierarchy during transitions.
    # Never reuse a previous screen's coordinates.
    for _ in range(3):
        adb('shell','rm','-f','/data/local/tmp/collie-views.xml')
        adb('shell','uiautomator','dump','/data/local/tmp/collie-views.xml',check=False)
        raw=adb('exec-out','cat','/data/local/tmp/collie-views.xml',check=False)
        if raw.lstrip().startswith(b'<?xml'):
            (out/(name+'.xml')).write_bytes(raw);return ET.fromstring(raw)
        time.sleep(.5)
    raise AssertionError('Cannot get fresh UI hierarchy')
def external(name):
    for _ in range(5):
        root=tree(name)
        if any(n.get('package') not in (None,'org.flexscript.collie','com.android.systemui') for n in root.iter('node')):return root
        time.sleep(.5)
    raise AssertionError('External '+name+' screen did not open')
size=re.findall(rb'(\d+)x(\d+)',adb('shell','wm','size'))[-1];width,height=map(int,size)
def find(root,label,reverse=False):
    nodes=list(root.iter('node'))
    if reverse:nodes.reverse()
    return next((n for n in nodes if n.get('content-desc')==label or n.get('text')==label),None)
def tap(label,reverse=False):
    for _ in range(5):
        node=find(tree(),label,reverse)
        if node is not None:
            a,b,c,d=map(int,re.findall(r'\d+',node.get('bounds')))
            adb('shell','input','tap',(a+c)//2,(b+d)//2);time.sleep(.25);return
        horizontal=next((n for n in tree().iter('node') if n.get('class')=='android.widget.HorizontalScrollView'),None)
        if horizontal is not None and label.startswith(('Remove attachment:','Open attached image:')):
            a,b,c,d=map(int,re.findall(r'\d+',horizontal.get('bounds')))
            # Keep gestures inside the control: Android's edge gesture means
            # Back and can close the activity instead of scrolling attachments.
            inset=(c-a)//4
            adb('shell','input','swipe',c-inset,(b+d)//2,a+inset,(b+d)//2,250)
        else:adb('shell','input','swipe',width//2,int(height*.78),width//2,int(height*.35),250)
    tree('missing-control');shot('missing-control')
    raise AssertionError('Control not found: '+label)
def shot(name):(out/(name+'.png')).write_bytes(adb('exec-out','screencap','-p'))
def passed(name):checks.append(name);print('PASS',name,flush=True)

def fixture():
    # Independent pixels: a red circle, blue square, and a label not in the prompt.
    w,h=720,500;rgb=bytearray(b'\xff\xff\xff'*(w*h))
    def pixel(x,y,color):rgb[(y*w+x)*3:(y*w+x)*3+3]=bytes(color)
    for y in range(65,246):
        for x in range(65,246):
            if (x-155)**2+(y-155)**2<=90**2:pixel(x,y,(225,25,45))
        for x in range(430,621):pixel(x,y,(25,70,230))
    font={
        'K':['10001','10010','10100','11000','10100','10010','10001'],
        'I':['11111','00100','00100','00100','00100','00100','11111'],
        'T':['11111','00100','00100','00100','00100','00100','00100'],
        'E':['11111','10000','10000','11110','10000','10000','11111'],
        '-':['00000','00000','00000','11111','00000','00000','00000'],
        '5':['11111','10000','10000','11110','00001','00001','11110'],
        '7':['11111','00001','00010','00100','01000','01000','01000'],
        '2':['11110','00001','00001','00110','01000','10000','11111'],
        '1':['00100','01100','00100','00100','00100','00100','01110']}
    for i,ch in enumerate('KITE-5721'):
        for y,row in enumerate(font[ch]):
            for x,on in enumerate(row):
                if on=='1':
                    for dy in range(8):
                        for dx in range(8):pixel(100+i*48+x*8+dx,350+y*8+dy,(0,0,0))
    def chunk(kind,data):return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
    scan=b''.join(b'\0'+rgb[y*w*3:(y+1)*w*3] for y in range(h))
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(scan))+chunk(b'IEND',b'')

png=fixture();(out/'sample.png').write_bytes(png)
text_upload=b'The attached document marker is NOVA-8136.\n'
(out/'attachment.txt').write_bytes(text_upload)
workspace='files/workspaces/'+sid+'/files/'
imported='/sample.png'
try:
    text='The marker is ORBIT-6049.\nThis is a real workspace document.'
    r=execute('views_seed','fn main(){return fs_write("memo.txt",db_text('+json.dumps(text)+'))-1;}')
    assert r['exit_code']==0,r
    put(workspace+'sample.png',png)
    r=execute('views_preview','fn main(){if !view_file("memo.txt") {return 1;}if !view_image("sample.png") {let e=db_error();db_io(0,2,e,db_len(e));return 2;}return 0;}')
    assert r['exit_code']==0 and r['views'][0]['text']==text and r['views'][1]['width']==720,r
    image=r['views'][1];imagepath='files/workspaces/'+sid+'/previews/'+image['image_id']+'.jpg'
    snapshot=adb('exec-out','run-as',pkg,'cat',imagepath)
    passed('Native VM returns bounded text views and decoded image snapshot metadata')

    if not args.media_only:
        root=tree('collapsed_activity')
        assert find(root,'Expand thinking') is not None and find(root,'Show VM result') is None
        tap('Expand thinking',True);tap('Show VM result',True);tap('Open file: memo.txt');root=tree('text_view')
        assert any('ORBIT-6049' in n.get('text','') for n in root.iter('node'));shot('text_view');tap('Close preview')
        tap('Open image: sample.png');root=tree('image_view')
        assert find(root,'Full image: sample.png') is not None;shot('image_view');tap('Close preview')
        passed('Text preview opens selectable document; image preview opens a full-screen image')

        r=execute('views_replace','fn main(){return fs_write("sample.png",db_text("replaced"))-1;}');assert r['exit_code']==0
        assert adb('exec-out','run-as',pkg,'cat',imagepath)==snapshot
        r=execute('views_bad_image','fn main(){if view_image("sample.png") {return 1;}let e=db_error();db_io(0,1,e,db_len(e));return 0;}')
        assert r['exit_code']==0 and 'Supported images' in r['stdout'],r
        put(workspace+'sample.png',png)
        passed('Image snapshots survive source replacement; invalid images fail without crashing')

        tap('Menu');tap('Permissions');tap('Deny Read workspace files')
        tap('Back to conversation')
        r=execute('views_denied','fn main(){view_image("sample.png");let e=db_error();db_io(0,1,e,db_len(e));return 0;}')
        assert r['stdout']=='Permission denied: files_read' and not r.get('views'),r
        tap('Menu');tap('Permissions');tap('Allow Read workspace files');tap('Back to conversation')
        assert saved(sid)['permissions']['files_read']
        passed('Read workspace files Allow/Deny choices govern actual image viewing')

        if args.picker:
            put(workspace+filename,b'keep-original')
            adb('push',out/'sample.png','/sdcard/Download/'+filename)
            unsent=saved(sid)['messages']
            tap('Attach file');tap('Files');root=tree('picker')
            if find(root,filename) is None:
                tap('Show roots');tap('Downloads')
            tap(filename)
            until=time.monotonic()+30
            while time.monotonic()<until:
                state=saved(sid)
                if any(c.get('path')=='/import-1-'+filename for c in state.get('pending_attachments',[])):break
                time.sleep(.3)
            else:raise AssertionError('Import did not complete')
            imported='/import-1-'+filename
            assert adb('exec-out','run-as',pkg,'cat',workspace+filename)==b'keep-original'
            assert adb('exec-out','run-as',pkg,'cat',workspace+imported[1:])==png
            assert state['messages']==unsent,'Selecting an attachment sent model context early'
            tap('Open attached image: '+imported);assert find(tree(),'Full image: '+imported) is not None
            tap('Close preview');shot('attachment_draft')
            case('views_draft_resume',dict(resume_only=True))
            assert find(tree(),'Remove attachment: '+imported) is not None
            tap('Remove attachment: '+imported)
            until=time.monotonic()+15
            while time.monotonic()<until:
                state=saved(sid)
                if not state.get('pending_attachments'):break
                time.sleep(.3)
            else:raise AssertionError('Attachment removal did not complete')
            assert state['messages']==unsent
            assert adb('exec-out','run-as',pkg,'cat',workspace+imported[1:],check=False)!=png
            tap('Attach file');tap('Files');root=tree('picker')
            if find(root,filename) is None:
                tap('Show roots');tap('Downloads')
            tap(filename)
            until=time.monotonic()+30
            while time.monotonic()<until:
                state=saved(sid)
                if state.get('pending_attachments'):break
                time.sleep(.3)
            else:raise AssertionError('Reattachment did not complete')
            assert state['messages']==unsent and state['pending_attachments'][0]['path']==imported
            adb('push',out/'attachment.txt','/sdcard/Download/'+filename+'.txt')
            tap('Attach file');tap('Files');root=tree('picker')
            if find(root,filename+'.txt') is None:
                tap('Show roots');tap('Downloads')
            tap(filename+'.txt')
            until=time.monotonic()+30
            while time.monotonic()<until:
                state=saved(sid)
                if len(state.get('pending_attachments',[]))==2:break
                time.sleep(.3)
            else:raise AssertionError('Text attachment did not complete')
            assert state['messages']==unsent
            assert state['pending_attachments'][1]['path']=='/'+filename+'.txt'
            assert adb('exec-out','run-as',pkg,'cat',workspace+filename+'.txt')==text_upload
            assert find(tree(),'Send message').get('enabled')=='true','Attachments alone must enable Send'
            shot('attachment_draft')
            passed('Composer + stages image and text files without sending; previews, removal, restart persistence and Send enabled without text verified')

    if args.media:
        pending=saved(sid).get('pending_attachments',[])
        tap('Attach file');root=tree('attachment_menu')
        assert all(find(root,label) is not None for label in ('Gallery','Camera','Files'))
        if args.serial.startswith('emulator-'):
            gallery_path='/sdcard/Pictures/'+filename
            adb('push',out/'sample.png',gallery_path)
            adb('shell','am','broadcast','-a','android.intent.action.MEDIA_SCANNER_SCAN_FILE','-d','file://'+gallery_path)
        tap('Gallery');root=external('gallery_picker');shot('gallery_picker')
        if args.serial.startswith('emulator-'):
            photos=[n for n in root.iter('node') if 'Photo taken' in n.get('content-desc','')]
            assert photos,'No scanned photo in system picker'
            a,b,c,d=map(int,re.findall(r'\d+',photos[0].get('bounds')))
            adb('shell','input','tap',(a+c)//2,(b+d)//2)
            until=time.monotonic()+30
            while time.monotonic()<until:
                current=saved(sid).get('pending_attachments',[])
                if len(current)==len(pending)+1:break
                time.sleep(.3)
            else:raise AssertionError('Gallery import did not complete')
            selected=current[-1];assert selected['image_id']==image['image_id'],selected
            tap('Open attached image: '+selected['path']);shot('gallery_preview');tap('Close preview')
            tap('Remove attachment: '+selected['path'])
            until=time.monotonic()+15
            while time.monotonic()<until:
                if saved(sid).get('pending_attachments',[])==pending:break
                time.sleep(.3)
            else:raise AssertionError('Gallery attachment removal failed')
        else:
            # Never select an unknown personal photo or capture the user's surroundings.
            adb('shell','input','keyevent',4);time.sleep(.5)
        tap('Attach file');tap('Camera');root=external('camera');shot('camera')
        assert any(n.get('package','').endswith(('camera','Camera')) or '.camera' in n.get('package','') for n in root.iter('node')),'Camera app did not open'
        if args.serial.startswith('emulator-'):
            tap('Shutter');time.sleep(2);root=tree('camera_review');shot('camera_review')
            # AOSP camera asks for confirmation after intent capture.
            if find(root,'Done') is not None:tap('Done')
            elif find(root,'OK') is not None:tap('OK')
            until=time.monotonic()+30
            while time.monotonic()<until:
                current=saved(sid).get('pending_attachments',[])
                if len(current)==len(pending)+1:break
                time.sleep(.3)
            else:raise AssertionError('Camera capture did not attach')
            captured=current[-1];assert captured['path'].startswith('/Camera-') and captured.get('image_id'),captured
            assert max(captured['width'],captured['height'])<=1536 and captured['file_bytes']<=524288
            tap('Open attached image: '+captured['path']);shot('camera_preview');tap('Close preview')
            tap('Remove attachment: '+captured['path'])
        else:
            adb('shell','input','keyevent',4);time.sleep(.5)
        until=time.monotonic()+15
        while time.monotonic()<until:
            if saved(sid).get('pending_attachments',[])==pending:break
            time.sleep(.3)
        else:raise AssertionError('Camera cancellation/removal changed draft')
        assert ET.fromstring(adb('exec-out','run-as',pkg,'cat','shared_prefs/MainActivity.xml')).find("string[@name='camera_file']") is None
        cache=adb('exec-out','run-as',pkg,'ls','cache/camera',check=False).strip();assert not cache,cache
        passed('Gallery and Camera open from +; emulator imports selected pixels and a real synthetic camera capture; private output cleaned')

    if args.live:
        r=case('views_live_file',dict(prompt='Inspect /memo.txt using view_file and tell me its marker. Do not guess; use its actual view result.'))
        answer=r['messages'][-1].get('content','');assert 'ORBIT-6049' in answer,answer
        passed('Live agent reads actual file-view content through the sole Flexscript tool')
        if args.picker:
            previous=len(saved(sid)['messages'])
            tap('Message Collie')
            adb('shell','input','text','Describe%sthe%sattached%simage,%sread%sits%sexact%slabel,%sand%sgive%sthe%smarker%sfrom%sthe%sattached%stext%sfile.')
            tap('Send message')
            until=time.monotonic()+180
            while time.monotonic()<until:
                state=saved(sid)
                if len(state['messages'])>previous and state['messages'][-1].get('role')=='assistant':break
                time.sleep(1)
            else:raise AssertionError('Chat attachment response timed out')
            r=state
            assert not state.get('pending_attachments')
            user=next(c for c in reversed(state['cards']) if c.get('kind')=='user')
            assert user['text']=='Describe the attached image, read its exact label, and give the marker from the attached text file.' and user['attachments'][0]['path']==imported and len(user['attachments'])==2,user
            assert 'NOVA-8136' in r['messages'][-1].get('content',''),r['messages'][-1]
            assert any(m.get('type')=='custom_tool_call' and 'view_file' in m.get('input','') for m in r['messages'][previous:])
            shot('attachment_sent')
        else:
            r=case('views_live_image',dict(prompt='Use view_image to inspect '+imported+'. Describe the colored shapes and read the exact visible label. Do not guess; wait for actual image input.'))
        answer=r['messages'][-1].get('content','');print('VISION ANSWER',answer,flush=True)
        assert 'KITE-5721' in answer and 'red' in answer.lower() and 'blue' in answer.lower(),answer
        assert any(m.get('type')=='custom_tool_call' and 'view_image' in m.get('input','') for m in r['messages'])
        assert 'data:image/' not in json.dumps(saved(sid))
        passed('Live model sees image pixels and reads hidden fixture label; saved history contains no base64')
finally:
    if args.media:adb('shell','input','keyevent',4)
    case('views_restore',dict(session=original,resume_only=True))
    after=saved(original);assert after['messages']==before['messages'] and after['cards']==before['cards']
    assert after.get('permissions')==before.get('permissions')
    assert after.get('pending_attachments',[])==before.get('pending_attachments',[])
    for name in requests:adb('shell','run-as',pkg,'rm','-f','files/test/'+name+'.json','files/test/'+name+'.result.json')
    assert sid!=original;adb('shell','run-as',pkg,'rm','-rf','files/workspaces/'+sid)
    if args.picker:adb('shell','rm','-f','/sdcard/Download/'+filename,'/sdcard/Download/'+filename+'.txt')
    if args.media and args.serial.startswith('emulator-'):
        adb('shell','rm','-f','/sdcard/Pictures/'+filename)
        adb('shell','am','broadcast','-a','android.intent.action.MEDIA_SCANNER_SCAN_FILE','-d','file:///sdcard/Pictures/'+filename)
    adb('shell','am','force-stop',pkg);adb('shell','am','start','-n',pkg+'/.MainActivity')
passed('Original conversation and grants preserved; temporary files and test session removed')
report=dict(checks=checks,count=len(checks),android_serial=args.serial,live_model=args.live,picker=args.picker,media=args.media,
    apk_sha256=hashlib.sha256((args.out/'collie.apk').read_bytes()).hexdigest())
(out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
