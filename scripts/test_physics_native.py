"""Portable guards for the optional native CPU physics library."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
ROOT=Path(__file__).resolve().parents[1]
SPEC=importlib.util.spec_from_file_location('physics_native_build',ROOT/'libs/physics/native/build.py')
build=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(build)

class NativePhysics(unittest.TestCase):
    def test_source_qualification_and_no_application_dependencies(self):
        q=build.validate_sources();self.assertEqual(set(q['libraries_sha256']),{'contact.so','phases.so'})
        for name in ['solver.flex','collision.flex']:
            text=(build.HERE/name).read_text()
            self.assertNotIn('rb_solver_poll',text);self.assertNotIn('pl_now',text)
            self.assertNotIn('ptroboband',text);self.assertNotIn('workdir',text)
        self.assertIn(ROOT/'libs/physics/math.flex',build.sources())
    def test_hook_binding_is_symbol_only_and_preserves_poll_sites(self):
        original=(build.HERE/'solver.flex').read_text()
        text=build.solver_source('/bundle','/collision','/color','host_poll','host_now',workers=6)
        self.assertEqual(text.count('host_poll()'),original.count('ph_native_poll()'))
        self.assertEqual(text.count('host_now()'),original.count('ph_native_now()'))
        self.assertIn('ffi_open("/bundle/contact.so")',text)
        for hook in ['invalid()', 'x;return 1', '']:
            with self.assertRaises(ValueError):build.solver_source('/bundle',poll=hook)
    def test_source_binding_default_matches_three_worker_build_default(self):
        default=build.solver_source('/bundle')
        self.assertEqual(default,build.solver_source('/bundle',workers=3))
        self.assertNotEqual(default,build.solver_source('/bundle',workers=6))
        self.assertNotIn('global par_pid3=0;',default)

    def test_compiler_drift_rejected_before_rewriting(self):
        with self.assertRaisesRegex(ValueError,'compiler assembly'):build.assembly('different compiler output')
    def test_missing_and_escaping_artifacts_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp);manifest=folder/'manifest.json'
            p=dict(schema='flexscript.native-physics.v1',workers=6,artifacts_sha256={})
            manifest.write_text(json.dumps(p))
            with self.assertRaisesRegex(ValueError,'required artifacts'):build.verify(folder)
            for name in ['contact.so','phases.so','physics.flex','solver.flex']:(folder/name).write_bytes(b'fixture')
            p['artifacts_sha256']={name:build.sha(folder/name) for name in ['contact.so','phases.so','physics.flex','solver.flex']}
            p['artifacts_sha256']['../escape']='invalid';manifest.write_text(json.dumps(p))
            with self.assertRaisesRegex(ValueError,'artifact changed'):build.verify(folder)

if __name__=='__main__':unittest.main(verbosity=2)
