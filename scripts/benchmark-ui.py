#!/usr/bin/env python3
"""Record/compare actual Collie UI backend workloads on an isolated display.

The executable is built by the Flexscript production UI lowering path. This
Python test harness only orchestrates processes, records metadata and statistics.
It never supplies application rendering/windowing code or substitutes SDL's
software renderer for an accelerated baseline. Presentation return is explicitly
not compositor feedback; this report alone cannot pass all migration gates.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import random
import resource
import statistics
import subprocess
import time

ROOT=Path(__file__).resolve().parents[1]
PRIMARY_SCENES=['scroll','selection','stream','navigation']
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--baseline',type=Path,required=True)
p.add_argument('--candidate',type=Path)
p.add_argument('--out',type=Path,default=ROOT/'build/migration/performance')
p.add_argument('--runs',type=int,default=7)
p.add_argument('--samples',type=int,default=160)
p.add_argument('--cpu',type=int,default=3)
p.add_argument('--presentation-feedback',action='store_true',help='Require compositor feedback on both backends, with identical frame-callback pacing')
p.add_argument('--scenes',nargs='+',choices=PRIMARY_SCENES+['typing'],default=PRIMARY_SCENES,help='Typing is an additional latency workload, never a replacement in the four-workload CPU aggregate')
p.add_argument('--replay-interval-ms',type=int,default=0,help='Schedule replay arrivals independently of frame callbacks; include any dispatch delay in presentation latency')
p.add_argument('--gpu-timing',action='store_true',help='Diagnostic GPU timeline queries; deliberately drains deferred batches and cannot qualify CPU/latency gates')
p.add_argument('--gpu-present-timing',action='store_true',help='Diagnostic draw and present-call GPU intervals with an explicit final glFlush; implies --gpu-timing')
p.add_argument('--allow-software',action='store_true',help='Correctness/CPU development only; never a GPU performance acceptance run')
a=p.parse_args();assert a.runs>=7 and a.samples*a.runs>=1000 and len(set(a.scenes))==len(a.scenes) and 0<=a.replay_interval_ms<=1000
if a.gpu_present_timing:a.gpu_timing=True
assert not a.replay_interval_ms or a.presentation_feedback,'Scheduled arrivals require a presentation clock'
out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
available=os.sched_getaffinity(0);cpu=a.cpu if a.cpu in available else min(available)
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def percent(values,q):
    v=sorted(values);i=(len(v)-1)*q;lo=int(i);hi=min(lo+1,len(v)-1)
    return v[lo]+(v[hi]-v[lo])*(i-lo)
def summary(v):return dict(median_ns=statistics.median(v),p95_ns=percent(v,.95),p99_ns=percent(v,.99),samples=len(v))
def host_snapshot():
    # Boundary snapshots only: no sampling worker runs beside timed UI work.
    # These describe a run, not the cause of a particular frame's outlier.
    result=dict(monotonic_ns=time.monotonic_ns())
    for name,path in [('cpu_stat','/proc/stat'),('interrupts','/proc/interrupts'),('softirqs','/proc/softirqs')]:
        try:
            lines=Path(path).read_text().splitlines()
            if name=='cpu_stat':result[name]=[int(x) for x in next(line for line in lines if line.startswith(f'cpu{cpu} ')).split()[1:]]
            else:
                index=lines[0].split().index(f'CPU{cpu}')
                result[name]={parts[0].rstrip(':'):int(parts[index+1]) for line in lines[1:] if len(parts:=line.split())>index+1 and parts[index+1].isdigit()}
        except (OSError,IndexError,ValueError,StopIteration) as error:result[name]=dict(unavailable=type(error).__name__)
    for name,path in [('current_frequency_khz',f'/sys/devices/system/cpu/cpu{cpu}/cpufreq/scaling_cur_freq'),('governor',f'/sys/devices/system/cpu/cpu{cpu}/cpufreq/scaling_governor'),('thread_siblings',f'/sys/devices/system/cpu/cpu{cpu}/topology/thread_siblings_list'),('cpu_pressure','/proc/pressure/cpu')]:
        try:result[name]=Path(path).read_text().strip()
        except OSError as error:result[name]=dict(unavailable=type(error).__name__)
    return result
def child_usage():
    usage=resource.getrusage(resource.RUSAGE_CHILDREN)
    return {name:getattr(usage,name) for name in ['ru_utime','ru_stime','ru_minflt','ru_majflt','ru_nvcsw','ru_nivcsw']}
def run_context(before,after,usage_before,usage_after):
    deltas={}
    for name in ['interrupts','softirqs']:
        left=before[name];right=after[name]
        if isinstance(left,dict) and isinstance(right,dict) and 'unavailable' not in left and 'unavailable' not in right:deltas[name]={key:right[key]-left[key] for key in left.keys()&right.keys()}
    if isinstance(before['cpu_stat'],list) and isinstance(after['cpu_stat'],list):deltas['cpu_stat']=[b-a for a,b in zip(before['cpu_stat'],after['cpu_stat'])]
    return dict(before=before,after=after,deltas=deltas,child_usage_delta={k:usage_after[k]-usage_before[k] for k in usage_before},scope='selected CPU and child-process run boundaries only; no per-frame interruption/frequency attribution')
def fonts():
    result=[]
    for pattern in ['sans-serif','monospace','sans-serif:charset=4e2d','sans-serif:charset=1f44b']:
        path=Path(subprocess.check_output(['fc-match','-f','%{file}',pattern],text=True))
        result.append(dict(pattern=pattern,file=str(path),sha256=digest(path)))
    return result
def sources():
    # Include new files: git diff alone omits untracked implementation modules.
    paths=subprocess.check_output(['git','ls-files','--cached','--others','--exclude-standard','-z'],cwd=ROOT).decode().split('\0')
    return {path:digest(ROOT/path) for path in sorted(set(paths)) if path and Path(path).suffix in {'.flex','.py','.c','.h','.md'} and (ROOT/path).is_file()}
env=dict(os.environ);env.pop('DISPLAY',None)
assert env.get('WAYLAND_DISPLAY') and env.get('XDG_RUNTIME_DIR'),'Select a private Wayland compositor explicitly'
env['SDL_VIDEODRIVER']='wayland';env.pop('FLEX_GUI_BACKEND',None)
backends=[('sdl',a.baseline.resolve())]
if a.candidate:backends.append(('native',a.candidate.resolve()))
metadata=dict(platform=platform.platform(),cpu=cpu,cpu_model=next((s.split(':',1)[1].strip() for s in Path('/proc/cpuinfo').read_text().splitlines() if s.startswith('model name')),''),
              revision=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
              working_tree_sha256=hashlib.sha256(subprocess.check_output(['git','diff'],cwd=ROOT)).hexdigest(),fonts=fonts(),
              source_sha256=sources(),
              executables={name:dict(path=str(path),sha256=digest(path)) for name,path in backends},
              video_driver='wayland',runs=a.runs,samples_per_run=a.samples,scenes=a.scenes,replay_interval_ns=a.replay_interval_ms*1000000,gpu_timing_instrumented=a.gpu_timing,gpu_present_timing_instrumented=a.gpu_present_timing,
              timing_boundary='thread active CPU from update/input dispatch through present submission and arena cleanup; blocked wall time excluded by thread CPU clock; before-present/present/cleanup CPU and swap wall time recorded separately',
              acceptance_complete=False,software_allowed=a.allow_software,presentation_feedback_requested=a.presentation_feedback,render_environment={k:env.get(k) for k in ['SDL_VIDEO_WAYLAND_SCALE_TO_DISPLAY','SDL_VIDEO_HIGHDPI_DISABLED','SDL_RENDER_DRIVER','SDL_VIDEO_DRIVER','SDL_VIDEODRIVER','LD_LIBRARY_PATH','XDG_DATA_DIRS']},presentation_hardware_verified=False)
all_rows=[]
for scene in a.scenes:
    for run in range(a.runs):
        order=list(backends)
        if run%2:order.reverse()
        for name,executable in order:
            prefix=out/f'{scene}-{run}-{name}';request=prefix.with_suffix('.request.json');result_path=prefix.with_suffix('.result.json')
            config=dict(scene=scene,samples=a.samples,output=str(result_path),presentation_feedback=a.presentation_feedback,replay_interval_ns=a.replay_interval_ms*1000000,gpu_timing=a.gpu_timing,gpu_present_timing=a.gpu_present_timing)
            if run==0:config['capture']=str(prefix.with_suffix('.rgba'))
            request.write_text(json.dumps(config))
            run_env=dict(env,FLEX_GUI_BACKEND='sdl2' if name=='sdl' else 'wayland')
            host_before=host_snapshot();usage_before=child_usage();started=time.monotonic();process=subprocess.Popen(['taskset','-c',str(cpu),str(executable),str(request)],cwd=ROOT,env=run_env,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
            try:stdout,stderr=process.communicate(timeout=120)
            except subprocess.TimeoutExpired:process.kill();stdout,stderr=process.communicate();raise AssertionError((scene,name,'timed out',stderr.decode(errors='replace')))
            usage_after=child_usage();host_after=host_snapshot()
            prefix.with_suffix('.stderr.log').write_bytes(stderr)
            assert process.returncode==0,(scene,name,process.returncode,stdout,stderr)
            result=json.loads(result_path.read_text());assert result['video_driver']=='wayland',result
            assert not result.get('trace_mode'),'A diagnostic trace binary cannot provide qualification timings'
            assert bool(result.get('gpu_timing_enabled'))==a.gpu_timing,'GPU instrumentation differs from the requested measurement mode'
            assert bool(result.get('gpu_present_timing_enabled'))==a.gpu_present_timing,'GPU present instrumentation differs from the requested mode'
            if a.gpu_timing:
                assert result.get('gpu_timing_instrumented') and result['gpu_timer_bits']==64 and result['gpu_query_result_reads']==a.samples*(4 if a.gpu_present_timing else 2),'GPU query precision or result ownership differs'
                assert len(result['gpu_timestamps'])==len(result['gpu_timeline_elapsed_ns'])==len(result['frame_gate_wait_ns'])==a.samples
                assert all(v['start_ns']>=0 and v['end_ns']>=v['start_ns'] and elapsed==v['end_ns']-v['start_ns'] for v,elapsed in zip(result['gpu_timestamps'],result['gpu_timeline_elapsed_ns'])),'GPU query records are incomplete or inconsistent'
                if a.gpu_present_timing:
                    assert result.get('gpu_present_final_flush') and all(len(result[k])==a.samples for k in ['gpu_present_timestamps','gpu_present_timeline_elapsed_ns','gpu_client_timeline_elapsed_ns','gpu_boundary_gap_ns']), 'GPU present records are incomplete'
                    assert all(draw['end_ns']<=present['start_ns']<=present['end_ns'] and after==present['end_ns']-present['start_ns'] and gap==present['start_ns']-draw['end_ns'] and total==present['end_ns']-draw['start_ns'] and total==before+gap+after for draw,present,before,after,gap,total in zip(result['gpu_timestamps'],result['gpu_present_timestamps'],result['gpu_timeline_elapsed_ns'],result['gpu_present_timeline_elapsed_ns'],result['gpu_boundary_gap_ns'],result['gpu_client_timeline_elapsed_ns'])), 'GPU draw/present phases are inconsistent'
            assert result['backend']==('sdl2' if name=='sdl' else 'wayland'),result
            if name=='native':assert result.get('sdl_loaded') is False,'Native process maps must exclude SDL and SDL_ttf'
            if name=='sdl' and not a.allow_software:assert result['renderer_flags']&2,'SDL baseline must use an accelerated renderer'
            assert result['counters'][7]==a.samples,(scene,name,'present count differs',result['counters'])
            assert result.get('inline_preview') and result.get('gpu_renderer') and len(result.get('cpu_present_ns',[]))==a.samples,'Rebuild both fixtures with preview/GPU verification'
            if not a.allow_software:assert not any(x in result['gpu_renderer'].lower() for x in ['llvmpipe','softpipe','software']),'Software client GPU is not a hardware baseline'
            if scene=='typing':assert result.get('typing_verified_updates')==a.samples and result.get('typing_cycle')=='ä中👋 -> ä中 -> ä -> empty','Typing must verify every Unicode edit and model echo'
            if a.presentation_feedback:
                assert result.get('presentation_feedback') and len(result['presentation_records'])==a.samples and result['presented_updates']+result['discarded_updates']==a.samples,result
                assert result['discarded_updates']==0,'A paired frame was not presented'
                assert [r['tag'] for r in result['presentation_records']]==list(range(1,a.samples+1)),result
                assert result.get('replay_interval_ns',0)==config['replay_interval_ns'],'Replay schedule differs'
                if a.replay_interval_ms:
                    origins=result['scheduled_arrival_ns'];waits=result['arrival_to_dispatch_ns'];dispatch=result['dispatch_to_presentation_ns']
                    assert len(origins)==len(waits)==len(dispatch)==a.samples and all(b-x==config['replay_interval_ns'] for x,b in zip(origins,origins[1:])),'Scheduled arrivals were dropped or retimed'
                    assert all(r['origin_ns']==origin and latency==wait+after and wait>=0 and after>=0 for r,origin,latency,wait,after in zip(result['presentation_records'],origins,result['input_update_to_presentation_ns'],waits,dispatch)),'Scheduled latency excludes dispatch waiting'
            mate=next((r for r in all_rows if r['scene']==scene and r['run']==run and r['backend']!=name),None)
            if mate:
                assert all(result[k]==mate[k] for k in ['width','height','pixel_width','pixel_height','gpu_renderer']),'Backend viewport/resolution/GPU differs'
                if a.presentation_feedback:assert result['presentation_clock_id']==mate['presentation_clock_id'],'Backend presentation clocks differ'
            row=dict(scene=scene,run=run,backend=name,elapsed_seconds=time.monotonic()-started,host_run_context=run_context(host_before,host_after,usage_before,usage_after),**{k:v for k,v in result.items() if k not in ('scene','backend')})
            all_rows.append(row)
            print(f"{scene} {run+1}/{a.runs} {name}: CPU median {statistics.median(result['cpu_work_ns'])/1e6:.3f} ms, p95 {percent(result['cpu_work_ns'],.95)/1e6:.3f} ms, renderer={result['renderer']}",flush=True)
            # Preserve progress if a later workload fails; failed/partial output
            # never has an acceptance verdict.
            (out/'report.json').write_text(json.dumps(dict(**metadata,rows=all_rows),indent=2)+'\n')
summary_rows=[]
for scene in a.scenes:
    row=dict(scene=scene,backends={})
    for name,_ in backends:
        runs=[r for r in all_rows if r['scene']==scene and r['backend']==name]
        row['backends'][name]={key:summary([v for r in runs for v in r[key]]) for key in ['cpu_work_ns','cpu_before_present_ns','cpu_present_ns','cpu_cleanup_ns','wall_work_ns','present_return_ns']}
        row['backends'][name]['first_frame_ns']=summary([r['first_frame_ns'] for r in runs])
        row['backends'][name]['process_cpu_per_update_ns']=summary([r['process_cpu_interval_ns']/a.samples for r in runs])
        row['backends'][name]['thread_cpu_per_update_ns']=summary([r['thread_cpu_interval_ns']/a.samples for r in runs])
        if a.gpu_timing:
            for key in ['gpu_timeline_elapsed_ns','frame_gate_wait_ns']:row['backends'][name][key]=summary([v for r in runs for v in r[key]])
            if a.gpu_present_timing:
                for key in ['gpu_present_timeline_elapsed_ns','gpu_client_timeline_elapsed_ns','gpu_boundary_gap_ns']:row['backends'][name][key]=summary([v for r in runs for v in r[key]])
            row['backends'][name]['gpu_timing_boundary']=runs[0]['gpu_timing_boundary']
        if a.presentation_feedback:
            row['backends'][name]['input_update_to_presentation_ns']=summary([v for r in runs for v in r['input_update_to_presentation_ns']])
            intervals=[b['presented_ns']-x['presented_ns'] for r in runs for x,b in zip(r['presentation_records'],r['presentation_records'][1:])]
            row['backends'][name]['presentation_intervals_ns']=summary(intervals)
            row['backends'][name]['presentation_flags']=sorted({v['flags'] for r in runs for v in r['presentation_records']})
            row['backends'][name]['refresh_predictions_ns']=sorted({v['refresh_ns'] for r in runs for v in r['presentation_records']})
            row['backends'][name]['cadence_basis']='compositor timestamps; zero refresh/sequence is unknown, not a passed missed-refresh gate'
            if a.replay_interval_ms:
                for key in ['arrival_to_dispatch_ns','dispatch_to_presentation_ns']:row['backends'][name][key]=summary([v for r in runs for v in r[key]])
    if a.candidate:
        left=row['backends']['sdl']['cpu_work_ns'];right=row['backends']['native']['cpu_work_ns']
        row['cpu_speedup']={key:left[key]/right[key] for key in ['median_ns','p95_ns']}
        pairs=[]
        for run in range(a.runs):
            baseline=next(r for r in all_rows if r['scene']==scene and r['run']==run and r['backend']=='sdl')
            native=next(r for r in all_rows if r['scene']==scene and r['run']==run and r['backend']=='native')
            b=summary(baseline['cpu_work_ns']);n=summary(native['cpu_work_ns'])
            pairs.append({key:b[key]/n[key] for key in ['median_ns','p95_ns']})
        row['paired_cpu_speedups']=pairs
        if a.presentation_feedback:
            row['presentation_p95_speedup']=row['backends']['sdl']['input_update_to_presentation_ns']['p95_ns']/row['backends']['native']['input_update_to_presentation_ns']['p95_ns']
            # Keep paired runs as the independent units. A positive difference
            # means native took longer; a headless refresh floor is still not
            # permission to label a confidently positive difference as a tie.
            deltas=[]
            for run in range(a.runs):
                baseline=next(r for r in all_rows if r['scene']==scene and r['run']==run and r['backend']=='sdl')
                native=next(r for r in all_rows if r['scene']==scene and r['run']==run and r['backend']=='native')
                deltas.append(percent(native['input_update_to_presentation_ns'],.95)-percent(baseline['input_update_to_presentation_ns'],.95))
            rng=random.Random(20261027);estimates=[statistics.mean(rng.choices(deltas,k=len(deltas))) for _ in range(10000)]
            row['paired_presentation_p95_difference_ns']=dict(native_minus_sdl_by_run=deltas,mean_ns=statistics.mean(deltas),bootstrap_95_low=percent(estimates,.025),bootstrap_95_high=percent(estimates,.975),boundary='fixed scheduled replay arrival including dispatch waiting' if a.replay_interval_ms else 'normalized replay/update dispatch; not physical input or hardware scanout')
    summary_rows.append(row)
report=dict(**metadata,rows=all_rows,summary=summary_rows)
if a.candidate:
    primary=[r for r in summary_rows if r['scene'] in PRIMARY_SCENES]
    complete_primary=len(primary)==len(PRIMARY_SCENES)
    report['cpu_speedup_geomean']={key:math.exp(sum(math.log(r['cpu_speedup'][key]) for r in primary)/len(primary)) for key in ['median_ns','p95_ns']} if complete_primary else None
    improved=[r['scene'] for r in primary if all(v>1 for v in r['cpu_speedup'].values())]
    report['individually_improved_workloads']=improved
    report['cpu_point_gate_pass']=complete_primary and all(v>=1.25 for v in report['cpu_speedup_geomean'].values()) and all(all(v>=1/1.05 for v in r['cpu_speedup'].values()) for r in primary) and len(improved)>=3 and {'scroll','selection'}.issubset(improved)
    # Resample entire paired runs, preserving each run's correlated frames.
    # This is run-to-run uncertainty, not a frame-wise pseudo-replicated CI.
    rng=random.Random(20261026);intervals={}
    for key in ['median_ns','p95_ns'] if complete_primary else []:
        estimates=[]
        for _ in range(10000):
            case_logs=[]
            for row in primary:
                ratios=[p[key] for p in row['paired_cpu_speedups']]
                case_logs.append(sum(math.log(rng.choice(ratios)) for _ in ratios)/len(ratios))
            estimates.append(math.exp(sum(case_logs)/len(case_logs)))
        intervals[key]=dict(paired_geomean=math.exp(sum(math.log(p[key]) for row in primary for p in row['paired_cpu_speedups'])/(len(primary)*a.runs)),bootstrap_95_low=percent(estimates,.025),bootstrap_95_high=percent(estimates,.975))
    report['paired_run_uncertainty']=intervals
    report['cpu_gate_pass']=bool(report['cpu_point_gate_pass'] and all(v['bootstrap_95_low']>=1.25 for v in intervals.values())) if complete_primary else None
    if not complete_primary:report['cpu_gate_unavailable_reason']='All four primary workloads are required; extra typing samples do not change that aggregate.'
    if a.gpu_timing:
        report['cpu_gate_pass']=None
        report['cpu_gate_unavailable_reason']='GPU query instrumentation drains deferred renderer batches; CPU and latency values are diagnostic, not release qualification.'
    # The full verdict additionally requires image/input equivalence, per-case
    # real feedback, idle, memory and lifecycle evidence. CPU gate is provisional.
(out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
print('Saved',out/'report.json','(full migration acceptance remains unproven)')
