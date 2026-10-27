#!/usr/bin/env python3
"""Matched SDL/native presentation correctness before longer paired measurement.

Twenty-four samples per workload are correctness evidence only. Rendering is the
compiled production Collie UI; this script supplies no application code.
"""
import argparse,json,os,stat,struct,subprocess,zlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--benchmark',type=Path,required=True);p.add_argument('--session',type=Path,required=True);p.add_argument('--out',type=Path,required=True);p.add_argument('--scenes',nargs='+',choices=['scroll','selection','stream','navigation','typing'],default=['scroll','selection','stream','navigation']);p.add_argument('--replay-interval-ms',type=int,default=0);p.add_argument('--gpu-timing',action='store_true');p.add_argument('--gpu-present-timing',action='store_true');a=p.parse_args();assert 0<=a.replay_interval_ms<=1000
if a.gpu_present_timing:a.gpu_timing=True
session=json.loads(a.session.read_text());runtime=Path(session['XDG_RUNTIME_DIR']);assert runtime.name.startswith('fs-ime-') and runtime.stat().st_uid==os.getuid() and stat.S_IMODE(runtime.stat().st_mode)==0o700
assert '/' not in session['WAYLAND_DISPLAY'] and stat.S_ISSOCK((runtime/session['WAYLAND_DISPLAY']).stat().st_mode)
out=a.out.resolve();out.mkdir(parents=True,exist_ok=True);env=dict(os.environ,**session,SDL_VIDEODRIVER='wayland');env.pop('DISPLAY',None);env.pop('SDL_VIDEO_DRIVER',None)
def png(raw,width,height,target):
    assert len(raw)==width*height*4
    def chunk(tag,data):return struct.pack('>I',len(data))+tag+data+struct.pack('>I',zlib.crc32(tag+data)&0xffffffff)
    scan=b''.join(b'\0'+raw[y*width*4:(y+1)*width*4] for y in range(height))
    target.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',width,height,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(scan))+chunk(b'IEND',b''))
rows=[]
for scene in a.scenes:
    pair=[]
    for backend in ['sdl2','wayland']:
        prefix=out/f'{scene}-{backend}';result=prefix.with_suffix('.result.json');capture=prefix.with_suffix('.rgba');request=prefix.with_suffix('.request.json')
        request.write_text(json.dumps(dict(scene=scene,samples=24,presentation_feedback=True,replay_interval_ns=a.replay_interval_ms*1000000,gpu_timing=a.gpu_timing,gpu_present_timing=a.gpu_present_timing,output=str(result),capture=str(capture))))
        r=subprocess.run([str(a.benchmark.resolve()),str(request)],env=dict(env,FLEX_GUI_BACKEND=backend),cwd=ROOT,capture_output=True,timeout=30)
        prefix.with_suffix('.stderr.log').write_bytes(r.stderr);assert r.returncode==0,(scene,backend,r.returncode,r.stdout,r.stderr[-3000:])
        row=json.loads(result.read_text());assert row['backend']==backend and row['video_driver']=='wayland' and row['inline_preview'] and row['gpu_renderer'] and row['presentation_feedback'],row
        assert not any(x in row['gpu_renderer'].lower() for x in ['llvmpipe','softpipe','software']),row
        assert bool(row.get('gpu_timing_enabled'))==a.gpu_timing,'GPU diagnostic mode differs'
        assert bool(row.get('gpu_present_timing_enabled'))==a.gpu_present_timing,'GPU present diagnostic mode differs'
        if a.gpu_timing:
            assert row['gpu_timing_instrumented'] and row['gpu_timer_bits']==64 and row['gpu_query_result_reads']==(96 if a.gpu_present_timing else 48) and len(row['gpu_timestamps'])==len(row['gpu_timeline_elapsed_ns'])==24
            assert all(v['end_ns']>=v['start_ns']>=0 and elapsed==v['end_ns']-v['start_ns'] for v,elapsed in zip(row['gpu_timestamps'],row['gpu_timeline_elapsed_ns'])),'GPU query result missing or inconsistent'
            if a.gpu_present_timing:
                assert row.get('gpu_present_final_flush') and all(len(row[k])==24 for k in ['gpu_present_timestamps','gpu_present_timeline_elapsed_ns','gpu_client_timeline_elapsed_ns','gpu_boundary_gap_ns']), 'GPU present phases missing'
                assert all(draw['end_ns']<=present['start_ns']<=present['end_ns'] and after==present['end_ns']-present['start_ns'] and gap==present['start_ns']-draw['end_ns'] and total==present['end_ns']-draw['start_ns'] and total==before+gap+after for draw,present,before,after,gap,total in zip(row['gpu_timestamps'],row['gpu_present_timestamps'],row['gpu_timeline_elapsed_ns'],row['gpu_present_timeline_elapsed_ns'],row['gpu_boundary_gap_ns'],row['gpu_client_timeline_elapsed_ns'])), 'GPU draw/present intervals differ'
        assert len(row['cpu_before_present_ns'])==len(row['cpu_present_ns'])==len(row['cpu_cleanup_ns'])==24,row
        assert all(total==draw+present+cleanup for total,draw,present,cleanup in zip(row['cpu_work_ns'],row['cpu_before_present_ns'],row['cpu_present_ns'],row['cpu_cleanup_ns'])),row
        assert len(row['presentation_records'])==24 and row['presented_updates']==24 and row['discarded_updates']==0 and row['counters'][7]==24,row
        assert [r['tag'] for r in row['presentation_records']]==list(range(1,25)),row
        assert all(r['status']==1 and r['received_ns']>=r['presented_ns']>=r['submit_ns']>=r['origin_ns'] for r in row['presentation_records']),row
        if a.replay_interval_ms:
            origins=row['scheduled_arrival_ns'];assert row['replay_interval_ns']==a.replay_interval_ms*1000000 and len(origins)==len(row['arrival_to_dispatch_ns'])==len(row['dispatch_to_presentation_ns'])==24
            assert all(b-x==row['replay_interval_ns'] for x,b in zip(origins,origins[1:])) and all(r['origin_ns']==origin and latency==wait+after and wait>=0 and after>=0 for r,origin,latency,wait,after in zip(row['presentation_records'],origins,row['input_update_to_presentation_ns'],row['arrival_to_dispatch_ns'],row['dispatch_to_presentation_ns'])),'Scheduled latency excludes waiting or retimes arrivals'
        if backend=='wayland':assert row['sdl_loaded'] is False,row
        if scene=='selection':assert row['selection_text'] and '#' not in row['selection_text'] and row['selection_caret']!=row['selection_anchor'],row
        if scene=='typing':assert row['typing_verified_updates']==24 and row['typing_cycle']=='ä中👋 -> ä中 -> ä -> empty' and row['typing_final_draft']=='' and row['typing_caret']==0,row
        png(capture.read_bytes(),row['pixel_width'],row['pixel_height'],prefix.with_suffix('.png'));pair.append(row);rows.append(row)
    assert all(pair[0][k]==pair[1][k] for k in ['width','height','pixel_width','pixel_height','gpu_renderer','presentation_clock_id']),('Mismatched comparison',scene,[(r['width'],r['height'],r['pixel_width'],r['pixel_height'],r['gpu_renderer']) for r in pair])
    print('PASS matched SDL/native',scene,': same viewport, pixels, GPU, inline preview and 24 compositor presentation outcomes',flush=True)
(out/'report.json').write_text(json.dumps(dict(correctness_only=True,performance_acceptance=False,rows=rows),indent=2)+'\n')
