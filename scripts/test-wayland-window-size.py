#!/usr/bin/env python3
"""Fixed-size native window checks using only an explicitly private Sway IPC."""
import argparse,json,os,re,signal,stat,subprocess,time
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--binary',type=Path,required=True);p.add_argument('--session',type=Path,required=True);p.add_argument('--swaymsg',type=Path,required=True);p.add_argument('--out',type=Path,required=True);a=p.parse_args()
session=json.loads(a.session.read_text());runtime=Path(session['XDG_RUNTIME_DIR']);assert runtime.name.startswith('fs-ime-') and runtime.stat().st_uid==os.getuid() and stat.S_IMODE(runtime.stat().st_mode)==0o700
assert Path(session['SWAYSOCK']).is_relative_to(runtime) and stat.S_ISSOCK(Path(session['SWAYSOCK']).stat().st_mode)
env=dict(os.environ,**session);env.pop('DISPLAY',None);out=a.out.resolve();out.mkdir(parents=True,exist_ok=True);checkpoint=out/'checkpoint.json';ack=out/'ack';checkpoint.unlink(missing_ok=True)
for path in out.glob('ack.*'):path.unlink()
def ipc(*args):return json.loads(subprocess.check_output([str(a.swaymsg.resolve()),'-s',session['SWAYSOCK'],'-r',*args],env=env,timeout=3))
def walk(node):
    yield node
    for child in node.get('nodes',[])+node.get('floating_nodes',[]):yield from walk(child)
def window():return next((node for node in walk(ipc('-t','get_tree')) if node.get('app_id')=='org.flexscript.Collie'),None)
assert all(x['success'] for x in ipc('for_window [app_id="org.flexscript.Collie"] floating enable'))
observations=[]
with (out/'client.stdout.log').open('wb') as stdout,(out/'client.stderr.log').open('wb') as stderr:
    app=subprocess.Popen([str(a.binary.resolve()),str(checkpoint),str(ack),str(out/'capture-'),str(out/'result.json'),'--size-only'],cwd=ROOT,env=dict(env,WAYLAND_DEBUG='1'),stdout=stdout,stderr=stderr,start_new_session=True)
    try:
        for step in range(9):
            until=time.monotonic()+10;client=None
            while time.monotonic()<until and app.poll() is None:
                try:client=json.loads(checkpoint.read_text())
                except (FileNotFoundError,json.JSONDecodeError):pass
                if client and client['step']==step:break
                time.sleep(.01)
            assert client and client['step']==step and app.poll() is None,('Size fixture failed',step,app.poll(),client)
            until=time.monotonic()+3;node=None;okay=False
            while time.monotonic()<until:
                node=window()
                if step==0:okay=node is None and client['presents']==0
                elif node:
                    okay=node['name']==client['title'] and (node['window_rect']['width'],node['window_rect']['height'])==(client['width'],client['height'])
                    if step==3:okay=okay and node['fullscreen_mode']==1
                    else:
                        okay=okay and node['fullscreen_mode']==0
                        if step==7:okay=okay and node['type']=='con' and client['state']&480!=0
                        else:okay=okay and (client['width'],client['height'])==((640,420) if step in [1,6] else (400,260) if step==8 else (800,500))
                if okay:break
                time.sleep(.02)
            assert okay,('Independent Sway geometry differs',step,client,node)
            peer=None;pixels=None
            if step in [1,2]:
                result=ipc('[app_id="org.flexscript.Collie"] resize set width 1000 px height 700 px');assert all(x['success'] for x in result),result
                # IPC rect/window_rect describe the layout container; geometry
                # is the original natural size. Neither proves current pixels
                # after a forced IPC resize. Ask the app to repaint, then verify
                # actual composed corner positions in a private output capture.
                probe=Path(str(ack)+'.'+str(step)+'.probe');probe.write_text('paint');until=time.monotonic()+3;live=None
                while time.monotonic()<until:
                    try:live=json.loads(Path(str(probe)+'.json').read_text())
                    except (FileNotFoundError,json.JSONDecodeError):pass
                    if live:break
                    time.sleep(.01)
                assert live and (live['width'],live['height'])==(client['width'],client['height']),('Fixed client resized on peer configure',step,live)
                time.sleep(.1);peer=window();capture=out/f'peer-{step}.png';subprocess.run(['grim','-o','HEADLESS-1',str(capture)],env=env,check=True,capture_output=True,timeout=3)
                image=Image.open(capture).convert('RGB');get_pixels=getattr(image,'get_flattened_data',image.getdata);data=list(get_pixels());boxes=[]
                for color in [(224,80,64),(64,208,112)]:
                    points=[(i%image.width,i//image.width) for i,pixel in enumerate(data) if pixel==color];assert points,('Composed marker missing',step,color)
                    boxes.append([min(x for x,y in points),min(y for x,y in points),max(x for x,y in points)+1,max(y for x,y in points)+1])
                red,green=boxes;scale=live['pixel_width']/live['width'];assert abs((green[0]-red[0])-(live['width']-32)*scale)<=1 and abs((green[1]-red[1])-(live['height']-32)*scale)<=1,('Composed fixed content was stretched',step,boxes,live)
                assert all(abs((box[2]-box[0])-32*scale)<=1 and abs((box[3]-box[1])-32*scale)<=1 for box in boxes),(step,boxes,scale)
                pixels=dict(live=live,red=red,green=green)
            if step==6:
                assert all(x['success'] for x in ipc('[app_id="org.flexscript.Collie"] floating disable'))
                peer=window();probe=Path(str(ack)+'.'+str(step)+'.probe');temporary=Path(str(probe)+'.tmp');temporary.write_text(json.dumps(dict(width=peer['window_rect']['width'],height=peer['window_rect']['height'])));temporary.replace(probe);until=time.monotonic()+3;live=None
                while time.monotonic()<until:
                    try:live=json.loads(Path(str(probe)+'.json').read_text())
                    except (FileNotFoundError,json.JSONDecodeError):pass
                    if live:break
                    time.sleep(.01)
                peer=window();assert live and live['state']&480!=0 and peer['type']=='con' and (live['width'],live['height'])==(peer['window_rect']['width'],peer['window_rect']['height']),('Tiled protocol/configure bounds differ',live,peer)
                pixels=dict(tiled_probe=live)
            if step==7:assert all(x['success'] for x in ipc('[app_id="org.flexscript.Collie"] floating enable'))
            observations.append(dict(client=client,compositor=node,independent_resize=peer,composed_pixels=pixels));(out/'observations.json').write_text(json.dumps(observations,indent=2)+'\n');Path(str(ack)+'.'+str(step)).write_text('ack')
        app.wait(timeout=5);assert app.returncode==0,app.returncode
        wire=(out/'client.stderr.log').read_text();offered=int(re.search(r'global\(\d+, \"xdg_wm_base\", (\d+)\)',wire)[1]);assert all(row['client']['xdg_version']==min(6,offered) for row in observations),offered
    finally:
        if app.poll() is None:os.killpg(app.pid,signal.SIGTERM);app.wait(timeout=5)
print('PASS private Sway: hidden readback, fixed composed pixels under independent resize, client resize, fullscreen/remap, tiled constraints/preferred restore and retained textures/text')
