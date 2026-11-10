#!/usr/bin/env python3
"""Bounded native-library parity and worker-lifecycle integration tests."""
import argparse,ctypes,importlib.util,os,select,signal,subprocess,tempfile,time,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('native_physics_build',ROOT/'libs/physics/native/build.py')
backend=importlib.util.module_from_spec(spec);spec.loader.exec_module(backend)

FIXTURE=r'''
fn np_equal(a,b,bytes){let i=0;while i<bytes{if load64(a+i)!=load64(b+i){return 0;}i=i+8;}return 1;}
fn np_check(a,b){return np_equal(a,b,load64(a+104)) && np_equal(a+load64(a+112)-32,b+load64(b+112)-32,32);}
fn np_no_children(){let status=alloc(8);let result=syscall(61,-1,status,1,0,0,0);syscall(11,status,8,0,0,0,0);h_assert(result==-10,"native backend leaked a child");return 1;}
fn main(argc,argv){
 h_environment(argc,argv);
 let a=ph_native_world(16,24,256,4);let b=ph_native_world(16,24,256,4);h_assert(a && b,"shared native worlds");
 if argc>1 {
  pt_scene(b,12);h_assert(ph_native_start(b),"native worker startup");h_print(1,"NATIVE_READY\n");
  if h_equal(load64(argv+8),"--parent-death"){while 1{syscall(7,0,0,1000,0,0,0);}}
  syscall(7,0,0,250,0,0,0);h_assert(!ph_step(b) && load64(b+192)==2,"dead helper must fault the original step");
  ph_native_stop();np_no_children();ph_native_close(a);ph_native_close(b);h_print(1,"NATIVE_FAILURE_PASS\n");return 0;
 }
 let scene=0;
 while scene<15 {
  pt_scene(a,scene);pt_scene(b,scene);h_assert(ph_native_start(b),"native worker startup");
  let step=0;
  while step<100 {
   h_assert(ph_step(a) && ph_step(b),"native fixture step failed");
   h_assert(np_check(a,b),"serial/six active world parity");step=step+1;
  }
  ph_native_stop();np_no_children();h_assert(ph_advance(a,10) && ph_advance(b,10) && np_check(a,b),"warm resume after stopping workers");scene=scene+1;
 }
 ph_native_close(a);ph_native_close(b);np_no_children();h_print(1,"NATIVE_PARITY_PASS 15 scenes 1500 steps\n");return 0;
}
'''

class NativeRuntime(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp=tempfile.TemporaryDirectory(prefix='flex-physics-native-');cls.folder=Path(cls.temp.name)
        bundle=backend.build(output_root=cls.folder/'bundles',clang=OPTIONS.clang,workers=OPTIONS.workers)
        fixtures=(ROOT/'libs/physics/tests/fixtures.flex').read_text()
        assert fixtures.startswith('import "../physics.flex";\n')
        source='import "'+str(bundle/'physics.flex')+'";\n'+fixtures.split('\n',1)[1]+FIXTURE
        path=cls.folder/'fixture.flex';path.write_text(source);cls.binary=cls.folder/'sim-soft-flexscript-native'
        result=subprocess.run([str(OPTIONS.compiler),str(path),'-o',str(cls.binary)],capture_output=True,text=True,timeout=120)
        if result.returncode:raise RuntimeError(result.stdout+result.stderr)
        if ctypes.CDLL(None).prctl(36,1,0,0,0):raise RuntimeError('test subreaper setup failed')
    @classmethod
    def tearDownClass(cls):cls.temp.cleanup()
    def launch(self,mode=None):
        parent=os.getpid()
        def setup():
            if ctypes.CDLL(None).prctl(1,signal.SIGKILL,0,0,0) or os.getppid()!=parent:os._exit(90)
        process=subprocess.Popen([str(self.binary),*([mode] if mode else [])],stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True,preexec_fn=setup)
        self.addCleanup(self.finish,process);return process
    def finish(self,process):
        if process.poll() is None:
            os.killpg(process.pid,signal.SIGKILL);process.wait(timeout=5)
        process.stdout.close();process.stderr.close()
    def ready(self,process):
        if not select.select([process.stdout],[],[],10)[0]:self.fail('native startup timeout')
        self.assertEqual(process.stdout.readline(),b'NATIVE_READY\n')
        deadline=time.monotonic()+5
        while time.monotonic()<deadline:
            path=Path('/proc',str(process.pid),'task',str(process.pid),'children')
            children=[int(x) for x in path.read_text().split()]
            if len(children)==OPTIONS.workers-1:return children
            time.sleep(.01)
        self.fail('native backend did not create requested helpers')
    def test_fifteen_scenes_every_step_and_resume(self):
        process=self.launch();out,err=process.communicate(timeout=90)
        self.assertEqual(process.returncode,0,err.decode());self.assertIn(b'NATIVE_PARITY_PASS 15 scenes 1500 steps',out)
    def test_worker_death_propagates_and_reaps(self):
        process=self.launch('--worker-failure');children=self.ready(process);fd=os.pidfd_open(children[0])
        try:signal.pidfd_send_signal(fd,signal.SIGKILL)
        finally:os.close(fd)
        out,err=process.communicate(timeout=10)
        self.assertEqual(process.returncode,0,err.decode());self.assertIn(b'NATIVE_FAILURE_PASS',out)
    def test_parent_death_stops_all_helpers(self):
        process=self.launch('--parent-death');children=self.ready(process);handles=[os.pidfd_open(pid) for pid in children]
        try:
            parent=os.pidfd_open(process.pid)
            try:signal.pidfd_send_signal(parent,signal.SIGKILL)
            finally:os.close(parent)
            process.wait(timeout=5)
            for pid,fd in zip(children,handles):
                self.assertTrue(select.select([fd],[],[],5)[0],'helper survived parent death')
                os.waitpid(pid,0)
        finally:
            for fd in handles:
                try:
                    if not select.select([fd],[],[],0)[0]:signal.pidfd_send_signal(fd,signal.SIGKILL)
                finally:os.close(fd)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--compiler',required=True,type=Path);parser.add_argument('--clang',type=Path);parser.add_argument('--workers',type=int,choices=(3,6),default=6)
    OPTIONS=parser.parse_args();unittest.main(argv=['test-physics-native'],verbosity=2)
