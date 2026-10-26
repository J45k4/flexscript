#!/usr/bin/env python3
"""Verify session discovery without creating any graphical windows."""
import argparse
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tests/collie/reference_host'))
from launch import display_environment

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--out',type=Path,default=ROOT/'build/collie-desktop')
a=p.parse_args();out=a.out.resolve()
with tempfile.TemporaryDirectory(prefix='launch-',dir=out) as directory:
    runtime=Path(directory)
    env={'XDG_RUNTIME_DIR':str(runtime),'XDG_SESSION_TYPE':'tty'}
    def native(environment,args=()):
        result=subprocess.run([str(out/'collie'),'--display-environment',*args],env=environment,capture_output=True,timeout=10)
        assert result.returncode==0,(result.returncode,result.stderr)
        import json
        return json.loads(result.stdout)
    keys={'XDG_RUNTIME_DIR','WAYLAND_DISPLAY','DISPLAY','XDG_SESSION_TYPE','SDL_VIDEODRIVER','SDL_VIDEO_DRIVER'}
    def compare(environment,args=()):
        expected={key:value for key,value in display_environment(environment,list(args)).items() if key in keys}
        assert native(environment,args)==expected,(environment,args,native(environment,args),expected)
    compare(env)
    assert display_environment(env,[])==env
    (runtime/'wayland-99').write_text('not a socket')
    assert display_environment(env,[])==env
    with socket.socket(socket.AF_UNIX) as one, socket.socket(socket.AF_UNIX) as two:
        one.bind(str(runtime/'wayland-1'))
        detected=display_environment(env,[])
        assert detected['WAYLAND_DISPLAY']=='wayland-1' and detected['XDG_SESSION_TYPE']=='wayland'
        assert 'WAYLAND_DISPLAY' not in env
        compare(env)
        for extra in ({'DISPLAY':':99'},{'WAYLAND_DISPLAY':'chosen-session'}, {'SDL_VIDEODRIVER':'dummy'},
                      {'SDL_VIDEO_DRIVER':'offscreen'},{'COLLIE_HEADLESS':'1'}):
            explicit=dict(env,**extra)
            assert display_environment(explicit,[])==explicit
            compare(explicit)
        assert display_environment(env,['--hidden'])==env
        compare(env,['--hidden'])
        assert display_environment(env,[],uid=os.getuid()+1)==env
        two.bind(str(runtime/'wayland-2'))
        compare(env)
        assert display_environment(env,[])==env
    clean={key:value for key,value in os.environ.items() if key not in ('DISPLAY','WAYLAND_DISPLAY','SDL_VIDEO_DRIVER')}
    clean.update(SDL_VIDEODRIVER='dummy',COLLIE_HEADLESS='1')
    result=subprocess.run([str(out/'collie'),'--video-diagnostics'],env=clean,capture_output=True,timeout=10)
    assert result.returncode==0 and b'Selected backend: dummy' in result.stderr,(result.returncode,result.stderr)
    clean['SDL_VIDEODRIVER']='collie-invalid-backend'
    result=subprocess.run([str(out/'collie'),'--video-diagnostics'],env=clean,capture_output=True,timeout=10)
    assert result.returncode and b'SDL_VIDEODRIVER=collie-invalid-backend' in result.stderr
    assert b'SDL initialization failed:' in result.stderr
print('PASS own unique session discovery, explicit backend/session preservation, ambiguity refusal, headless isolation and native no-window diagnostics')
