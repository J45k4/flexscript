#!/usr/bin/env python3
"""PTY integration tests; --gpu also validates the resident Qwen3 worker."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import pty
import re
import select
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import time

ROOT = Path(__file__).resolve().parent.parent


class Terminal:
    def __init__(self, binary, directory, extra=(), env=None):
        self.master, self.slave = pty.openpty()
        fcntl.ioctl(self.slave, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
        self.original = termios.tcgetattr(self.slave)
        self.output = b''
        self.last_send_offset = 0
        self.process = subprocess.Popen(
            [str(binary), '--history-dir', str(directory), *extra], cwd=ROOT,
            stdin=self.slave, stdout=self.slave, stderr=self.slave,
            env=env, start_new_session=True,
        )

    def pump(self, seconds=.1):
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            if select.select([self.master], [], [], .01)[0]:
                try:
                    self.output += os.read(self.master, 65536)
                except OSError:
                    return

    def send(self, text):
        self.last_send_offset = len(self.output)
        os.write(self.master, text.encode() if isinstance(text, str) else text)
        self.pump(.08)

    def wait(self, text, timeout=8):
        start = self.last_send_offset
        # Include already received updates, since a short operation can finish in send().
        end = time.monotonic() + timeout
        while text.encode() not in self.output[start:]:
            self.pump(.05)
            assert self.process.poll() is None, self.output[-2000:].decode(errors='replace')
            assert time.monotonic() < end, f'Terminal did not show {text!r}: {self.output[-1000:]!r}'

    def close(self, keys='\x15/quit\r', sig=None):
        if self.process.poll() is None:
            if sig:
                os.kill(self.process.pid, sig)
            elif keys:
                self.send(keys)
            self.pump(.2)
            assert self.process.wait(timeout=3) == 0
        assert self.original == termios.tcgetattr(self.slave), 'termios not restored'
        assert b'\x1b[?1049l' in self.output and b'\x1b[?25h' in self.output
        os.close(self.master)
        os.close(self.slave)


def sessions(directory):
    return [json.loads(p.read_text()) for p in directory.glob('*.json')]


def pty_tests(binary):
    with tempfile.TemporaryDirectory(prefix='flex-tui-') as temp:
        directory = Path(temp)
        clips = directory / 'bin'
        clips.mkdir()
        clipboard = directory / 'clipboard'
        clipboard.write_text('你好\nclipboard')
        for name, body in [
            ('wl-copy', "Path(os.environ['TUI_TEST_CLIPBOARD']).write_bytes(sys.stdin.buffer.read())"),
            ('wl-paste', "sys.stdout.buffer.write(Path(os.environ['TUI_TEST_CLIPBOARD']).read_bytes())"),
        ]:
            script = clips / name
            script.write_text('#!' + sys.executable + '\nimport os,sys\nfrom pathlib import Path\n' + body + '\n')
            script.chmod(0o755)
        env = dict(os.environ, PATH=str(clips) + ':' + os.environ['PATH'],
                   WAYLAND_DISPLAY='tui-test', TUI_TEST_CLIPBOARD=str(clipboard))
        history = directory / 'sessions'
        t = Terminal(binary, history, ['--demo', '1'], env)
        try:
            t.wait('Loading demo model')
            t.pump(.15)
            assert re.search(rb'% \([1-4]/4\)', t.output), 'loading did not show measured progress'
            t.wait('Warming demo worker')
            t.pump(.1)
            assert b'\x1b[s' in t.output and b'\x1b[u' in t.output, 'activity did not animate while worker was silent'
            t.wait('Model ready')
            assert b'Context 4096 | reply auto' in t.output, 'automatic reply/context defaults missing'
            frame = t.output[t.output.rfind(b'\x1b[1;1H'):]
            assert b'% (' not in frame, 'loading bar remained after ready'
            t.send('/models')
            t.wait('qwen3-1.7b | downloaded')
            assert not sessions(history), 'model preview submitted a command or saved a chat'
            t.send('\x1b')
            assert b'\x1b[1;36mModels' not in t.output[t.last_send_offset:], 'Escape did not dismiss preview'
            assert b'/models' in t.output[t.last_send_offset:], 'Escape cleared the draft command'
            t.send('\x15/mo\t')
            t.wait('qwen3-1.7b | downloaded')
            t.send('\x7f\x7f\x7f')
            assert b'\x1b[1;36mModels' not in t.output[t.last_send_offset:], 'editing away from /models kept the preview'
            t.send('\x15\x1b[200~/models\x1b[201~')
            t.wait('qwen3-1.7b | downloaded')
            assert not sessions(history), 'pasted model command was submitted'
            t.send('\x15')
            t.send('\x1b[200~你好\nclipboard\x1b[201~')
            assert not sessions(history), 'paste submitted a prompt'
            t.send('\x01\x03')
            assert clipboard.read_text() == '你好\nclipboard'
            t.send('\x18')
            t.send('\x16')
            t.send('\r')
            t.wait('Finished: limit')
            saved = sessions(history)
            assert len(saved) == 1
            assert saved[0]['messages'][0]['content'] == '你好\nclipboard'
            assert 'demo chat worker' in saved[0]['messages'][1]['content']
            first_id = saved[0]['id']
            t.send('/new\r')
            t.send('helo\x1b[D\x1b[Dl\r')
            t.wait('Finished: limit')
            saved = next(s for s in sessions(history) if s['id'] != first_id)
            assert saved['messages'][0]['content'] == 'hello'
            t.send('\x1b[<0;1;5M\x1b[<32;6;5M\x1b[<0;6;5m')
            assert clipboard.read_text() == 'hello', 'mouse transcript selection did not copy'
            assert b'\x1b[7m' in t.output[t.last_send_offset:], 'drag selection was not highlighted'
            t.send('\x1b[<0;3;5M\x1b[<0;3;5m')
            assert b'\x1b[7m' not in t.output[t.last_send_offset:], 'plain text click did not clear selection'
            assert clipboard.read_text() == 'hello', 'clearing selection replaced clipboard'
            t.send('\x1b[<0;1;5M\x1b[<32;6;5M\x1b[<0;6;5m')
            t.send('\x1b[<0;1;22M\x1b[<0;1;22m')
            assert b'\x1b[7m' not in t.output[t.last_send_offset:], 'click outside messages did not clear selection'
            t.send('\x1b[<2;1;23M')
            t.send('\x01\x03')
            assert clipboard.read_text() == 'hello', 'right-click paste did not enter composer'
            t.send('\x15')
            t.send('cancel this reply\r')
            t.send('\x1b')
            t.wait('Finished: cancelled')
            frame = t.output[t.output.rfind(b'\x1b[1;1H'):]
            assert b's | Esc stop' not in frame, 'activity indicator remained after cancellation'
            saved = next(s for s in sessions(history) if s['id'] != first_id)
            assert saved['messages'][-1]['status'] == 'cancelled'
            t.send('/resume ' + first_id + '\r')
            t.wait('Resumed saved conversation')
            t.send('/thinking on\r')
            assert next(s for s in sessions(history) if s['id'] == first_id)['thinking'] == 1
            t.send('/backend cuda\r')
            t.wait('Model ready')
            t.send('/temperature 0.7\r/tokens 4\r/models\r')
            t.wait('Esc close | Up/Down')
            frame = t.output[t.last_send_offset:]
            assert b'\x1b[21;1H\x1b[2K\x1b[90mEsc close' in frame, 'menu is not anchored above composer'
            models = re.findall(rb'\x1b\[(\d+);1H\x1b\[2K\x1b\[1;36mModels', frame)
            assert models and int(models[-1]) > 4, 'short menu starts at transcript top'
            fcntl.ioctl(t.slave, termios.TIOCSWINSZ, struct.pack('HHHH', 32, 100, 0, 0))
            t.pump(.15)
            assert b'\x1b[32;1H' in t.output, 'resize did not redraw'
            assert b'\x1b[29;1H\x1b[2K\x1b[90mEsc close' in t.output, 'menu did not follow resized composer'
            t.send('\x1b')
            assert b'\x1b[1;36mModels' not in t.output[t.last_send_offset:], 'Escape did not dismiss menu'
            fcntl.ioctl(t.slave, termios.TIOCSWINSZ, struct.pack('HHHH', 14, 80, 0, 0))
            t.pump(.15)
            t.send('/help\r')
            t.wait('Esc close | Up/Down')
            assert b'File tools and other model architectures' not in t.output[t.last_send_offset:], 'long menu was not clipped'
            t.send('\x1b[6~')
            t.wait('File tools and other model architectures')
            t.send('/sessions\r')
            t.wait('Saved conversations')
            t.send('\x1b')
            assert all(m['role'] != 'notice' for s in sessions(history) for m in s['messages']), 'menus leaked into chat history'
            malformed = history / 'broken.json'
            malformed.write_text('{invalid')
            t.send('/resume broken\r')
            t.wait('invalid or unsupported')
            malformed.write_text(json.dumps(dict(version=1, model='qwen3-1.7b',
                messages=[dict(role='assistant', content='invalid turn order')])))
            t.send('/resume broken\r')
            t.wait('invalid or unsupported')
            t.close()
        finally:
            if t.process.poll() is None:
                t.process.kill()
                t.process.wait()
        for sig in [signal.SIGINT, signal.SIGTERM, signal.SIGHUP]:
            t = Terminal(binary, history, ['--demo', '1'], env)
            t.wait('Model ready')
            t.close(sig=sig)
        t = Terminal(binary, history, ['--checkpoint', str(directory / 'missing')], env)
        t.wait('Model not downloaded')
        t.send('hello\r')
        assert t.process.poll() is None
        t.close()
    print('PTY: Unicode editing, clipboard adapters, bracketed paste, streaming, cancellation, sessions, backend switching, resize and signal cleanup passed.', flush=True)


def editor_test(binary):
    with tempfile.TemporaryDirectory(prefix='flex-editor-') as temp:
        t = Terminal(binary, Path(temp))
        t.wait('Flexscript reusable TUI editor')
        t.send('你好\rsecond line')
        t.wait('second line')
        t.send('\x1b[A\x1b[Hfirst ')
        t.wait('first ')
        fcntl.ioctl(t.slave, termios.TIOCSWINSZ, struct.pack('HHHH', 32, 100, 0, 0))
        t.pump(.15)
        assert b'\x1b[32;1H' in t.output, 'standalone resize did not redraw'
        t.close(keys='\x04')
    print('Standalone library editor: typing, multiline movement, resize and cleanup passed.', flush=True)


def thinking_tests(binary):
    with tempfile.TemporaryDirectory(prefix='flex-thinking-') as temp:
        directory = Path(temp)
        saved = dict(version=1, id='thought', model='qwen3-1.7b', thinking=1,
            messages=[dict(role='user', content='Question'),
                      dict(role='assistant', content='<think>Hidden reasoning</think>\n\nVisible answer', status='eos')])
        (directory / 'thought.json').write_text(json.dumps(saved))
        t = Terminal(binary, directory, ['--demo', '1', '--resume', 'thought'])
        t.wait('Model ready')
        frame = t.output[t.output.rfind(b'\x1b[1;1H'):]
        assert b'[+] Thinking' in frame and b'Visible answer' in frame and b'Hidden reasoning' not in frame
        t.send('\x1b[<0;2;8M\x1b[<0;2;8m')
        t.wait('[-] Thinking')
        assert b'Hidden reasoning' in t.output[t.last_send_offset:]
        t.send('\x14')
        t.wait('[+] Thinking')
        assert b'Hidden reasoning' not in t.output[t.last_send_offset:]
        # An unfinished reasoning block stays collapsible while streaming.
        saved['messages'][1]['content'] = '<think>Still reasoning'
        saved['messages'][1]['status'] = 'cancelled'
        (directory / 'stream.json').write_text(json.dumps(saved))
        t.send('/resume stream\r')
        t.wait('unfinished')
        t.send('\x14')
        t.wait('Still reasoning')
        t.send('/new\r/thinking on\rhello\r')
        t.wait('[+] Thinking | in progress')
        t.send('\x14')
        t.wait('Demo reasoning')
        t.send('\x1b')
        t.wait('Finished: cancelled')
        t.close()
    print('Thinking panels: collapsed default, visible answers, click/keyboard toggles and unfinished blocks passed.', flush=True)


def download_tests(binary):
    with tempfile.TemporaryDirectory(prefix='flex-download-') as temp:
        root = Path(temp)
        bins = root / 'bin'
        bins.mkdir()
        curl = bins / 'curl'
        curl.write_text('#!' + sys.executable + '''
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
with open(os.environ['TUI_DOWNLOAD_LOG'], 'a') as log:
    log.write(json.dumps(args) + '\\n')
output = Path(args[args.index('--output') + 1])
with output.open('ab') as file:
    file.write(b'fixture')
sys.exit(int(os.environ.get('TUI_DOWNLOAD_FAIL', '0')))
''')
        curl.chmod(0o755)
        log = root / 'calls.jsonl'
        env = dict(os.environ, PATH=str(bins) + ':' + os.environ['PATH'],
                   TUI_DOWNLOAD_LOG=str(log))
        checkpoint = root / 'model'
        checkpoint.mkdir()
        (checkpoint / 'config.json').write_text('existing')
        (checkpoint / 'tokenizer.json.part').write_text('partial-')
        command = [str(binary), '--download-worker', '1', '--checkpoint', str(checkpoint)]
        result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, check=True)
        events = [json.loads(line) for line in result.stdout.splitlines()]
        assert events[-1]['event'] == 'downloaded'
        counts = [e['completed'] for e in events if e['event'] == 'progress']
        assert counts[0] == 0 and counts[-1] == 6 and counts == sorted(counts), 'download file progress did not advance'
        assert (checkpoint / 'config.json').read_text() == 'existing'
        assert (checkpoint / 'tokenizer.json').read_text() == 'partial-fixture'
        assert not list(checkpoint.glob('*.part'))
        calls = [json.loads(line) for line in log.read_text().splitlines()]
        assert len(calls) == 5
        for args in calls:
            assert args[args.index('--continue-at') + 1] == '-'
            assert '/resolve/70d244cc86ccca08cf5af4e1e306ecf908b1ad5e/' in args[-1]
        missing = checkpoint / 'LICENSE'
        missing.unlink()
        result = subprocess.run(command, cwd=ROOT, env=dict(env, TUI_DOWNLOAD_FAIL='22'), capture_output=True)
        assert result.returncode != 0 and not missing.exists()
        assert (checkpoint / 'LICENSE.part').exists()
    print('Downloader: pinned URLs, existing files, partial resume and failed-download recovery passed (offline fixtures).', flush=True)


class Worker:
    def __init__(self, binary, checkpoint, backend):
        self.p = subprocess.Popen(
            [str(binary), '--worker', '1', '--checkpoint', checkpoint,
             '--compiler', 'build/flex-llm', '--backend', backend,
             '--weights', 'f16-tiled', '--context', '256'], cwd=ROOT,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0,
        )
        loading = self.until('ready')
        self.ready = loading[-1]
        progress = [e for e in loading if e['event'] == 'progress']
        for phase in ['Compiling GPU kernels', 'Loading weights:', 'Preparing weights', 'Building rotary table']:
            updates = [e for e in progress if e['text'].startswith(phase)]
            assert len(updates) > 1 and updates[0]['completed'] == 0 and updates[-1]['completed'] == updates[-1]['total'], phase

    def send(self, request):
        self.p.stdin.write((json.dumps(request, ensure_ascii=False) + '\n').encode())
        self.p.stdin.flush()

    def until(self, kind, timeout=60):
        result = []
        end = time.monotonic() + timeout
        while True:
            assert time.monotonic() < end, f'worker timed out waiting for {kind}'
            if not select.select([self.p.stdout], [], [], .1)[0]:
                assert self.p.poll() is None, self.p.stderr.read().decode(errors='replace')
                continue
            line = self.p.stdout.readline()
            assert line, self.p.stderr.read().decode(errors='replace')
            event = json.loads(line)
            result.append(event)
            if event['event'] == kind:
                return result

    def generate(self, turns, tokens=4, temperature=0):
        self.send(dict(op='generate', turns=turns, max_tokens=tokens, temperature=temperature, thinking=0))
        events = self.until('idle')
        idle = events[-1]
        assert idle['resident_bytes'] == self.ready['resident_bytes'], 'prompt scratch leaked GPU memory'
        return events

    def close(self):
        if self.p.poll() is None:
            self.send(dict(op='shutdown'))
            assert self.p.wait(timeout=10) == 0, self.p.stderr.read().decode(errors='replace')


def gpu_tests(binary, checkpoint):
    baseline = json.loads((ROOT / 'libs/ml/llm/tests/chat.json').read_text())
    prompt = dict(role='user', content=baseline['prompt'])
    evidence = {}
    for backend in ['sass', 'cuda']:
        w = Worker(binary, checkpoint, backend)
        try:
            events = w.generate([prompt], 60 if backend == 'sass' else 4)
            done = next(e for e in events if e['event'] == 'done')
            assert done['generated_ids'] == baseline['generated_ids'][:len(done['generated_ids'])]
            assert done['input_ids'] == baseline['input_ids']
            evidence[backend] = [done]
            turns = [prompt, dict(role='assistant', content=done['text']),
                     dict(role='user', content='What did I ask you to explain?')]
            events = w.generate(turns, 16)
            second = next(e for e in events if e['event'] == 'done')
            assert len(second['input_ids']) > len(done['input_ids'])
            evidence[backend].append(second)
            events = w.generate([dict(role='user', content='GPU ' * 600)], 4)
            assert any(e['event'] == 'error' for e in events), 'oversized prompt was not rejected'
            w.send(dict(op='generate', turns=[prompt], max_tokens=200, temperature=0, thinking=0))
            w.until('token')
            w.send(dict(op='cancel'))
            events = w.until('idle')
            assert next(e for e in events if e['event'] == 'done')['reason'] == 'cancelled'
            events = w.generate([prompt], 4)
            reset = next(e for e in events if e['event'] == 'done')
            assert reset['generated_ids'] == baseline['generated_ids'][:4], 'cancel/reset changed subsequent generation'
            evidence[backend].append(reset)
            events = w.generate([prompt], 4, 700)
            assert any(e['event'] == 'done' for e in events)
            events = w.generate([prompt], 0)
            usage = next(e for e in events if e['event'] == 'context')
            done = next(e for e in events if e['event'] == 'done')
            assert usage['max_tokens'] == w.ready['context_capacity'] - usage['prompt_tokens']
            assert done['reason'] in ('eos', 'context') and done['tokens'] <= usage['max_tokens']
        finally:
            w.close()
    (ROOT / 'build/llm/tui-worker-validation.json').write_text(json.dumps(evidence, indent=2))
    print('GPU: both backends match baseline tokens, preserve multi-turn context, reject oversized prompts, cancel/recover and release prompt scratch across requests.', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', default='build/flex-llm')
    parser.add_argument('--binary', default='build/llm-chat')
    parser.add_argument('--gpu', action='store_true')
    parser.add_argument('--checkpoint', default=os.environ.get('QWEN_CHECKPOINT'))
    args = parser.parse_args()
    binary = (ROOT / args.binary).resolve()
    subprocess.run([args.compiler, 'llm.flex', '-o', str(binary)], cwd=ROOT, check=True)
    pty_tests(binary)
    thinking_tests(binary)
    editor = binary.with_name('tui-editor')
    subprocess.run([args.compiler, 'examples/tui/editor.flex', '-o', str(editor)], cwd=ROOT, check=True)
    editor_test(editor)
    download_tests(binary)
    if args.gpu:
        assert args.checkpoint, '--gpu requires --checkpoint or QWEN_CHECKPOINT'
        gpu_tests(binary, args.checkpoint)


if __name__ == '__main__':
    main()
