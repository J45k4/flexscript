#!/usr/bin/env python3
"""Native Linux CPU batch parity and process lifetime integration tests."""
import argparse
import ctypes
import os
from pathlib import Path
import select
import signal
import subprocess
import tempfile
import time
import unittest

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--compiler',default=str(ROOT/'build/flex'))
options,unittest_args=parser.parse_known_args()

def identity(pid):
    try:
        data=Path('/proc',str(pid),'stat').read_text()
    except FileNotFoundError:
        return None
    fields=data[data.rfind(')')+2:].split()
    return dict(pid=pid,state=fields[0],ppid=int(fields[1]),start=int(fields[19]))

class CpuBatch(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory=tempfile.TemporaryDirectory(prefix='flex-physics-cpu-batch-')
        cls.addClassCleanup(cls.directory.cleanup)
        cls.binary=Path(cls.directory.name)/'sim-soft-cpu-batch-tests'
        subprocess.run([options.compiler,'libs/physics/tests/cpu-batch.flex','-o',str(cls.binary)],cwd=ROOT,check=True,capture_output=True,timeout=120)
        cls.libc=ctypes.CDLL(None,use_errno=True)
        previous=ctypes.c_int()
        if cls.libc.prctl(37,ctypes.byref(previous),0,0,0)!=0:raise OSError(ctypes.get_errno(),'get subreaper')
        cls.old_subreaper=previous.value
        if cls.libc.prctl(36,1,0,0,0)!=0:raise OSError(ctypes.get_errno(),'set subreaper')
        cls.addClassCleanup(cls.libc.prctl,36,cls.old_subreaper,0,0,0)

    def wait_worker(self,pid):
        end=time.monotonic()+10
        while time.monotonic()<end:
            result,status=os.waitpid(pid,os.WNOHANG)
            if result:return result,status
            time.sleep(.01)
        self.fail('worker did not terminate within ten seconds')

    def test_every_step_parity_faults_timeouts_and_cleanup(self):
        completed=subprocess.run([str(self.binary)],cwd=ROOT,capture_output=True,text=True,timeout=120)
        self.assertEqual(completed.returncode,0,completed.stdout+completed.stderr)
        self.assertIn('CPU batch checks pass',completed.stdout)
        self.assertEqual(completed.stderr,'')

    def start_pool(self,mode):
        parent=os.getpid()
        def setup():
            if self.libc.prctl(1,signal.SIGKILL,0,0,0)!=0 or os.getppid()!=parent:os._exit(90)
        child=subprocess.Popen([str(self.binary),mode],cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True,preexec_fn=setup)
        handles=[]
        try:
            self.assertTrue(select.select([child.stdout],[],[],10)[0],'parent readiness timeout')
            self.assertEqual(child.stdout.readline().strip(),'BATCH_PARENT_READY')
            end=time.monotonic()+10
            while time.monotonic()<end:
                path=Path('/proc',str(child.pid),'task',str(child.pid),'children')
                pids=[int(v) for v in path.read_text().split()] if path.exists() else []
                if len(pids)==2:
                    states=[identity(pid) for pid in pids]
                    if all(s and s['ppid']==child.pid and s['state']!='Z' for s in states):
                        for state in states:handles.append((state,os.pidfd_open(state['pid'])))
                        return child,handles
                if child.poll() is not None:break
                time.sleep(.01)
            self.fail('two live batch workers did not start')
        except BaseException:
            self.cleanup_pool(child,handles)
            raise

    def cleanup_pool(self,child,handles):
        if child.poll() is None:child.kill()
        child.wait(timeout=10)
        for state,fd in handles:
            try:signal.pidfd_send_signal(fd,signal.SIGKILL)
            except ProcessLookupError:pass
            try:self.wait_worker(state['pid'])
            except ChildProcessError:pass
            os.close(fd)
        if child.stdout:child.stdout.close()
        if child.stderr:child.stderr.close()

    def test_worker_death_leaves_input_unchanged_and_reaps_other_worker(self):
        child,handles=self.start_pool('--worker-failure')
        try:
            signal.pidfd_send_signal(handles[0][1],signal.SIGKILL)
            out,err=child.communicate(timeout=10)
            self.assertEqual(child.returncode,0,out+err)
            self.assertIn('CPU batch worker failure checks pass',out)
            self.assertEqual(err,'')
            for state,_ in handles:
                current=identity(state['pid'])
                self.assertTrue(current is None or current['start']!=state['start'])
        finally:self.cleanup_pool(child,handles)

    def test_parent_death_kills_and_reaps_both_workers(self):
        child,handles=self.start_pool('--parent-death')
        try:
            child.kill();self.assertEqual(child.wait(timeout=10),-signal.SIGKILL)
            for state,_ in handles:
                pid,status=self.wait_worker(state['pid'])
                self.assertEqual(pid,state['pid'])
                self.assertTrue(os.WIFSIGNALED(status))
                self.assertEqual(os.WTERMSIG(status),signal.SIGKILL)
                self.assertIsNone(identity(pid))
        finally:self.cleanup_pool(child,handles)

if __name__=='__main__':unittest.main(argv=[__file__,*unittest_args],verbosity=2)
