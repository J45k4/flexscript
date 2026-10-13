#!/usr/bin/env python3
"""Offline checkpoint, model-selection, resume and pinned-download checks."""
import argparse
import json
import os
import fcntl
from pathlib import Path
import subprocess
import re
import struct
import sys
import tempfile
import termios

from importlib.util import module_from_spec, spec_from_file_location

ROOT = Path(__file__).resolve().parent.parent
spec = spec_from_file_location('llm_tui_tests', ROOT / 'scripts/test-llm-tui.py')
tui = module_from_spec(spec)
spec.loader.exec_module(tui)


def checkpoint(directory, model):
    directory.mkdir()
    config = dict(architectures=['Qwen3ForCausalLM'], head_dim=128,
                  rope_theta=1000000, num_key_value_heads=8,
                  attention_dropout=0.0, initializer_range=0.02, rms_norm_eps=1e-6)
    config.update(dict(hidden_size=2560, num_hidden_layers=36,
                       intermediate_size=9728, num_attention_heads=32) if model == 'qwen3-4b'
                  else dict(hidden_size=2048, num_hidden_layers=28,
                            intermediate_size=6144, num_attention_heads=16))
    (directory / 'config.json').write_text(json.dumps(config))
    (directory / 'tokenizer.json').write_text('{}')
    shards = [f'model-{i:05d}-of-00003.safetensors' for i in range(1, 4)]
    (directory / 'model.safetensors.index.json').write_text(json.dumps(
        dict(weight_map={f'weight{i}': name for i, name in enumerate(shards)})))
    for name in shards:
        (directory / name).write_bytes(b'fixture')
    return shards


def catalog_tests(compiler, binary, directory):
    source = directory / 'catalog.flex'
    source.write_text('import ' + json.dumps(str(ROOT / 'libs/ml/llm/models.flex')) + ';\n' + '''
fn main(argc,argv) {
    h_environment(argc,argv);let directory=load64(argv+8);let id=qm_detect(directory);
    if id {h_print(1,id);}h_print(1,"\\n");h_print(1,h_int(qm_ready(directory)));return 0;
}
''')
    probe = directory / 'catalog'
    subprocess.run([compiler, source, '-o', probe], cwd=ROOT, check=True)
    for model in ['qwen3-1.7b', 'qwen3-4b']:
        path = directory / model
        shards = checkpoint(path, model)
        def result():
            return subprocess.check_output([probe, path], cwd=ROOT).decode()
        assert result() == model + '\n1'
        (path / shards[-1]).unlink()
        assert result() == model + '\n0', 'missing final shard reported ready'
        (path / shards[-1]).write_bytes(b'fixture')
    bad = subprocess.run([binary, '--model', 'qwen3-1.7b', '--checkpoint',
                          directory / 'qwen3-4b'], cwd=ROOT, capture_output=True)
    assert bad.returncode and b'does not match' in bad.stderr
    bad = subprocess.run([binary, '--model', 'unsupported'], cwd=ROOT, capture_output=True)
    assert bad.returncode and b'supported models' in bad.stderr


def selection_tests(binary, directory):
    history = directory / 'sessions'
    terminal = tui.Terminal(binary, history, ['--demo', '1', '--model', 'qwen3-4b',
        '--checkpoint', str(directory / 'qwen3-4b'), '--thinking', 'on'])
    try:
        terminal.wait('Model ready')
        assert b'Qwen3-4B' in terminal.output
        terminal.send('hello\r')
        terminal.send('/model qwen3-1.7b\r')
        terminal.wait('Finished: limit')
        assert all(s['model'] == 'qwen3-4b' for s in tui.sessions(history)), 'model changed during generation'
        four = next(s for s in tui.sessions(history) if s['messages'])
        assert four['model'] == 'qwen3-4b' and four['thinking'] == 1
        assert '<think>' in four['messages'][-1]['content']
        terminal.send('/model qwen3-1.7b\r')
        terminal.wait('Model ready')
        terminal.send('second\r')
        terminal.wait('Finished: limit')
        smaller = next(s for s in tui.sessions(history) if s['model'] == 'qwen3-1.7b')
        assert smaller['id'] != four['id']
        assert smaller['messages'][0]['content'] == 'second'
        terminal.send('/resume ' + four['id'] + '\r')
        terminal.wait('Resumed saved conversation')
        assert b'Qwen3-4B' in terminal.output[terminal.last_send_offset:]
        terminal.send('/models\r')
        terminal.wait('qwen3-4b | downloaded')
        assert str(directory / 'qwen3-4b').encode() in terminal.output[terminal.last_send_offset:]
        terminal.send('\x1b/thinking off\r')
        terminal.wait('Thinking off')
        terminal.close()
        resumed = json.loads((history / (four['id'] + '.json')).read_text())
        assert resumed['model'] == 'qwen3-4b' and resumed['thinking'] == 0
        assert resumed['messages'] == four['messages']
    finally:
        if terminal.process.poll() is None:
            terminal.process.kill()
            terminal.process.wait()
    # A model explicitly selected on the CLI overrides another model's env default.
    env = dict(os.environ, QWEN_CHECKPOINT=str(directory / 'qwen3-1.7b'))
    terminal = tui.Terminal(binary, directory / 'env-sessions', [
        '--demo', '1', '--model', 'qwen3-4b', '--no-warmup', '1'], env=env)
    try:
        terminal.wait('Qwen3-4B')
        terminal.close()
    finally:
        if terminal.process.poll() is None:
            terminal.process.kill()
            terminal.process.wait()
    # An explicit checkpoint also identifies the model without --model.
    terminal = tui.Terminal(binary, directory / 'detected-sessions', [
        '--demo', '1', '--checkpoint', str(directory / 'qwen3-4b'), '--no-warmup', '1'])
    try:
        terminal.wait('Qwen3-4B')
        terminal.close()
    finally:
        if terminal.process.poll() is None:
            terminal.process.kill()
            terminal.process.wait()


def download_tests(binary, directory):
    bins = directory / 'bin'
    bins.mkdir()
    curl = bins / 'curl'
    curl.write_text('#!' + sys.executable + '''
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
with open(os.environ['MODEL_DOWNLOAD_LOG'], 'a') as log:
    log.write(json.dumps(args) + '\\n')
Path(args[args.index('--output') + 1]).write_bytes(b'fixture')
''')
    curl.chmod(0o755)
    for model in ['qwen3-1.7b', 'qwen3-4b']:
        log = directory / (model + '.jsonl')
        destination = directory / ('download-' + model)
        env = dict(os.environ, PATH=str(bins) + ':' + os.environ['PATH'], MODEL_DOWNLOAD_LOG=str(log))
        command = [binary, '--download-worker', '1', '--model', model,
                   '--checkpoint', destination]
        run = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, check=True)
        events = [json.loads(line) for line in run.stdout.splitlines()]
        manifest = json.loads((ROOT / 'libs/ml/examples' / (model + '.model.json')).read_text())['checkpoint']
        assert events[-1]['event'] == 'downloaded'
        assert events[-2]['completed'] == len(manifest['files'])
        calls = [json.loads(line) for line in log.read_text().splitlines()]
        assert [Path(call[-1]).name for call in calls] == manifest['files']
        assert all(f"/{manifest['repo']}/resolve/{manifest['revision']}/" in call[-1] for call in calls)
        subprocess.run(command, cwd=ROOT, env=env, capture_output=True, check=True)
        assert len(log.read_text().splitlines()) == len(calls), 'downloaded files fetched again'


def picker_tests(binary, directory):
    terminal = tui.Terminal(binary, directory / 'picker-sessions', [
        '--demo', '1', '--checkpoint', str(directory / 'qwen3-1.7b')])
    def frame():
        return terminal.output[terminal.output.rfind(b'\x1b[1;1H'):]
    def click(model):
        matches = list(re.finditer(rb'\x1b\[(\d+);1H\x1b\[2K(?:\x1b\[[0-9;]*m)*[ >]*'
                                  + re.escape(model.encode()), frame()))
        assert matches, frame()
        row = int(matches[-1][1])
        terminal.send(f'\x1b[<0;4;{row}M')
        terminal.pump(.1)
        terminal.send(f'\x1b[<0;4;{row}m')
    try:
        terminal.wait('Model ready')
        # The preview selects via arrows and Enter without submitting /models.
        terminal.send('/models')
        terminal.wait('qwen3-4b | downloaded')
        terminal.send('\x1b[B')
        assert b'\x1b[1;7m> qwen3-4b' in frame(), 'focused model not highlighted'
        terminal.send('\r')
        terminal.wait('Model ready')
        assert b'Qwen3-4B' in frame() and b'Tab: /models' not in frame()
        assert all(not s['messages'] for s in tui.sessions(directory / 'picker-sessions'))
        # A submitted panel accepts keyboard activation as well.
        terminal.send('/models\r')
        terminal.wait('Enter select')
        terminal.send('\x1b[A\r')
        terminal.wait('Model ready')
        assert b'Qwen3-1.7B' in frame()
        # Click from the preview; the pending command clears after selection.
        terminal.send('/models')
        terminal.wait('qwen3-4b | downloaded')
        click('qwen3-4b')
        terminal.wait('Model ready')
        assert b'Qwen3-4B' in frame() and b'Tab: /models' not in frame()
        # Wrapped choice rows retain correct click targets after resize.
        terminal.send('/models\r')
        terminal.wait('Enter select')
        fcntl.ioctl(terminal.slave, termios.TIOCSWINSZ, struct.pack('HHHH', 12, 24, 0, 0))
        terminal.pump(.2)
        click('qwen3-1.7b')
        terminal.wait('Model ready')
        fcntl.ioctl(terminal.slave, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
        terminal.pump(.2)
        assert b'Qwen3-1.7B' in frame()
        terminal.close()
    finally:
        if terminal.process.poll() is None:
            terminal.process.kill()
            terminal.process.wait()
    print('Model picker: keyboard and mouse activation, preview clearing and wrapped rows passed.')


def gpu_tests(binary, checkpoint_path):
    with tempfile.TemporaryDirectory(prefix='llm-4b-gpu-', dir=ROOT / 'build') as temp:
        history = Path(temp)
        extra = ['--model', 'qwen3-4b', '--backend', 'rdna',
                 '--context', 'auto', '--max-tokens', '512']
        if checkpoint_path:
            extra += ['--checkpoint', str(checkpoint_path)]
        terminal = tui.Terminal(binary, history, extra)
        try:
            terminal.wait('Model ready', timeout=120)
            assert b'Qwen3-4B' in terminal.output
            terminal.send('My name is Alex. Reply with my name only.\r')
            terminal.wait('Finished: eos', timeout=60)
            saved = next(s for s in tui.sessions(history) if s['messages'])
            assert saved['model'] == 'qwen3-4b'
            assert 'Alex' in saved['messages'][-1]['content']
            terminal.send('What is my name? Reply with the name only.\r')
            terminal.wait('Finished: eos', timeout=60)
            saved = json.loads((history / (saved['id'] + '.json')).read_text())
            assert len(saved['messages']) == 4 and 'Alex' in saved['messages'][-1]['content']
            terminal.send('/thinking on\r')
            terminal.wait('Thinking on')
            terminal.send('What is 2 + 3? Keep your reasoning brief.\r')
            terminal.wait('[+] Thinking', timeout=60)
            terminal.wait('Finished:', timeout=60)
            saved = json.loads((history / (saved['id'] + '.json')).read_text())
            assert saved['thinking'] == 1 and '<think>' in saved['messages'][-1]['content']
            terminal.close()
        finally:
            if terminal.process.poll() is None:
                terminal.process.kill()
                terminal.process.wait()
    print('Qwen3-4B GPU: direct RDNA, automatic context, multi-turn recall and thinking passed.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', default='build/flex-llm')
    parser.add_argument('--binary', default='build/llm-chat')
    parser.add_argument('--gpu', action='store_true', help='also run original Qwen3-4B on direct RDNA')
    parser.add_argument('--checkpoint', type=Path)
    args = parser.parse_args()
    binary = str((ROOT / args.binary).resolve())
    with tempfile.TemporaryDirectory(prefix='llm-models-', dir=ROOT / 'build') as temp:
        directory = Path(temp)
        catalog_tests(args.compiler, binary, directory)
        selection_tests(binary, directory)
        picker_tests(binary, directory)
        download_tests(binary, directory)
    print('Models: checkpoint detection/all shards, selection, session resume, thinking and pinned downloads passed.')
    if args.gpu:
        gpu_tests(binary, args.checkpoint)


if __name__ == '__main__':
    main()
