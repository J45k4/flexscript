#!/usr/bin/env python3
"""Offline PTY checks of Collie's native UI; --vm exercises real guest execution."""
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

ROOT = Path(__file__).resolve().parents[3]


class Terminal:
    def __init__(self, binary, history, extra=(), env=None, defaults=True, cwd=ROOT):
        self.master, self.slave = pty.openpty()
        fcntl.ioctl(self.slave, termios.TIOCSWINSZ, struct.pack('HHHH', 28, 110, 0, 0))
        self.original = termios.tcgetattr(self.slave)
        self.output = b''
        self.offset = 0
        options = ['--model', 'fixture-model', '--compiler', str(COMPILER), '--history-dir', str(history)] if defaults else []
        command = list(map(str, binary)) if isinstance(binary, (list, tuple)) else [str(binary)]
        self.process = subprocess.Popen(
            [*command, *options, *extra], cwd=cwd,
            stdin=self.slave, stdout=self.slave, stderr=self.slave,
            env=env, start_new_session=True,
        )

    def pump(self, seconds=.08):
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            if select.select([self.master], [], [], .01)[0]:
                self.output += os.read(self.master, 65536)

    def send(self, text):
        self.offset = len(self.output)
        os.write(self.master, text.encode() if isinstance(text, str) else text)
        self.pump()

    def wait(self, text, timeout=8):
        end = time.monotonic() + timeout
        while text.encode() not in self.output[self.offset:]:
            self.pump()
            assert self.process.poll() is None, self.output[-2500:].decode(errors='replace')
            assert time.monotonic() < end, f'Missing {text!r}: {self.output[-2000:]!r}'

    def frame(self):
        # Each complete frame begins by writing the title at row one.
        return self.output[self.output.rfind(b'\x1b[1;1H'):]

    def close(self, sig=None):
        try:
            if self.process.poll() is None:
                if sig:
                    os.kill(self.process.pid, sig)
                else:
                    self.send('\x15/quit\r')
                self.pump(.2)
                assert self.process.wait(timeout=5) == 0
            assert termios.tcgetattr(self.slave) == self.original, 'terminal attributes not restored'
            assert b'\x1b[?1049l' in self.output and b'\x1b[?25h' in self.output, 'alternate screen/cursor not restored'
        finally:
            if self.process.poll() is None:
                self.process.kill()
                self.process.wait()
            os.close(self.master)
            os.close(self.slave)


def saved(history):
    return [json.loads(p.read_text()) for p in history.glob('*.json')]


def default_startup_tests(binary, directory):
    cache = directory / 'codex-login'
    cache.mkdir()
    auth = cache / 'auth.json'
    tokens = dict(auth_mode='chatgpt', tokens=dict(access_token='fixture-access', account_id='fixture-account'))
    original = json.dumps(tokens)
    auth.write_text(original)
    (cache / 'models_cache.json').write_text(json.dumps(dict(models=[dict(
        slug='gpt-6.1-sol', context_window=500000, max_context_window=872000)])))
    env = dict(os.environ, CODEX_HOME=str(cache), XDG_STATE_HOME=str(directory / 'state'), COLLIE_COMPILER=str(COMPILER))
    # This is literally argc=1: config comes only from the existing login and environment.
    t = Terminal(binary, None, env=env, defaults=False)
    try:
        t.wait('Welcome to Collie')
        t.wait('Collie | gpt-6.1-sol')
        assert b'Context ?/258400 tok' in t.frame(), 'shared cache changed the bundled default window'
        assert 'fixture-access' not in t.output.decode() and 'fixture-account' not in t.output.decode()
        assert auth.read_text() == original, 'startup modified the login cache'
    finally:
        t.close()
    t = Terminal(binary, None, ['--context-window', '500000'], env=env, defaults=False)
    try:
        t.wait('Context ?/475000 tok')
    finally:
        t.close()
    # An explicit model still wins.
    t = Terminal(binary, None, ['--model', 'custom-model'], env=env, defaults=False)
    try:
        t.wait('Collie | custom-model')
    finally:
        t.close()
    auth.unlink()
    for invalid in (None, dict(auth_mode='apikey', OPENAI_API_KEY='fixture-private-key')):
        if invalid:
            auth.write_text(json.dumps(invalid))
        p = subprocess.run([str(binary)], cwd=ROOT, env=env, capture_output=True, timeout=5)
        assert p.returncode == 1 and b'auth.json' in p.stderr, p.stderr
        assert b'\x1b[?1049h' not in p.stdout, 'login failure entered raw mode'
        assert b'fixture-private-key' not in p.stdout + p.stderr
    # Offline replay needs neither a model argument nor a login file.
    p = subprocess.run([str(binary), '--replay', 'apps/collie/tests/fixtures/greeting.json', 'Hello'],
                       cwd=ROOT, env=env, capture_output=True, timeout=5)
    assert p.returncode == 0 and b'Hello! No program is needed.' in p.stdout, p.stderr
    print('Default startup: zero arguments, cached login, default/explicit models, private credentials and login failures passed.')


def script_launch_tests(directory):
    cache = directory / 'script-login'
    cache.mkdir()
    auth = cache / 'auth.json'
    auth.write_text(json.dumps(dict(auth_mode='chatgpt', tokens=dict(access_token='fixture-access', account_id='fixture-account'))))
    env = dict(os.environ, CODEX_HOME=str(cache), XDG_STATE_HOME=str(directory / 'script-state'))
    env.pop('COLLIE_COMPILER', None)
    app = ROOT / 'apps/collie'
    for prefix in ([str(COMPILER), 'main.flex'], [str(COMPILER), 'run', 'main.flex']):
        # No app arguments: select the default model and validate cached auth
        # through an actual native adapter; do not make a network request.
        t = Terminal(prefix, None, env=env, defaults=False, cwd=app)
        try:
            t.wait('Welcome to Collie')
            t.wait('Collie | gpt-6.1-sol')
            assert b'Building native Collie host...' in t.output
            t.pump(5.2)
            assert t.process.poll() is None, 'TUI remained under the script VM deadline'
        finally:
            t.close()
        # Forward app options and a task, and execute the native model worker.
        command = [*prefix, '--compiler', str(COMPILER), '--replay', 'tests/fixtures/greeting.json', '--', '--compiler']
        result = subprocess.run(command, cwd=app, env=env, capture_output=True, timeout=10)
        assert result.returncode == 0 and result.stdout == b'Hello! No program is needed.\n', result.stderr
        assert b'unknown compiler option' not in result.stderr
    print('Script launch: direct/run forms, argument forwarding, native auth/model workers and VM-deadline escape passed.')


def descendants(pid):
    try:
        children = [int(p) for p in Path(f'/proc/{pid}/task/{pid}/children').read_text().split()]
    except FileNotFoundError:
        return []
    return children + [p for child in children for p in descendants(child)]


def stopped(pids):
    end = time.monotonic() + 3
    while True:
        running = []
        for pid in pids:
            try:
                state = Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()[0]
                if state != 'Z':
                    running.append(pid)
            except FileNotFoundError:
                pass
        if not running:
            return
        assert time.monotonic() < end, f'cancel left workers running: {running}'
        time.sleep(.02)


def chat_tests(binary, directory):
    history = directory / 'chat'
    t = Terminal(binary, history)
    try:
        t.wait('Welcome to Collie')
        # Cursor editing of Unicode, and paste containing a command/newline.
        t.send('Remember 你好x\x7f\x1b[D好\x1b[C\r')
        t.wait('Remembered: 你好好')
        t.wait('Done.')
        t.send('Recall\r')
        t.wait('Recalled: 你好好')
        t.wait('Done.')
        t.send('\x1b[A')
        assert b'Recall' in t.frame(), 'prompt history recall failed'
        t.send('\x15\x1b[200~line one\n/quit\x1b[201~')
        t.wait('/quit')
        assert t.process.poll() is None and len(saved(history)[0]['items']) == 4, 'paste submitted a command'
        t.send('\x15/help\r')
        t.wait('Collie help')
        t.send('\x1b')
        t.send('/clear\r')
        t.wait('conversation retained')
        t.send('Recall\r')
        t.wait('Recalled: 你好好')
        t.wait('Done.')
        data = saved(history)[0]
        assert len(data['messages']) == 6 and all(m['role'] in ('user', 'assistant') for m in data['messages'])
        for path in history.glob('*.json'):
            assert path.stat().st_mode & 0o777 == 0o600, 'private session mode'
        t.send('/sessions\r')
        t.wait('Saved conversations')
        t.send('\x1b')
        t.send('/new\r')
        t.wait('Welcome to Collie')
        t.send('/resume latest\r')
        t.wait('Resumed saved conversation')
        t.send('Recall\r')
        t.wait('Recalled: 你好好')
        t.wait('Done.')
        # Resize while an editor draft is active.
        fcntl.ioctl(t.slave, termios.TIOCSWINSZ, struct.pack('HHHH', 16, 60, 0, 0))
        t.pump(.2)
        assert b'\x1b[16;1H' in t.frame(), 'resize did not redraw footer'
        t.send('/model different-model\r')
        t.wait('Selected model: different-model')
        assert b'Collie | different-model' in t.frame()
        t.send('/resume ../../escape\r')
        t.wait('Invalid session ID')
        (history / '1-2-3.json').write_text('{invalid')
        t.send('/resume 1-2-3\r')
        t.wait('invalid or unsupported')
        t.send('/new\rcontrols\r')
        t.wait('Safe [2Jtext')
        assert b'Safe \x1b[2J' not in t.output, 'model text injected a terminal escape'
    finally:
        t.close()
    # Resume across processes, rather than only switching in memory.
    t = Terminal(binary, history, ['--resume', 'latest'])
    try:
        t.wait('Resumed saved conversation')
        t.wait('Safe [2Jtext')
    finally:
        t.close()
    print('PTY chat: Unicode editing, paste, history, context, sessions, model switching, resize and safe display passed.')


def cancellation_tests(binary, directory):
    history = directory / 'cancel'
    t = Terminal(binary, history)
    try:
        t.wait('Welcome to Collie')
        t.send('slow\r')
        t.wait('First streamed chunk')
        size = len(json.dumps([dict(role='user', content='slow')], separators=(',', ':')).encode())
        assert f'Context {size} B/8 MiB | 1 messages'.encode() in t.frame(), 'pending prompt missing from context size'
        assert b'last chunk' not in t.frame(), 'reply was buffered until completion'
        t.send('unsent draft')
        t.wait('unsent draft')
        children = descendants(t.process.pid)
        assert len(children) >= 2, 'did not exercise turn and model workers'
        t.send('\x1b')
        t.wait('Turn cancelled.')
        stopped(children)
        assert b'unsent draft' in t.frame(), 'cancel discarded the draft'
        t.send('\x15Remember cancelled safely\r')
        t.wait('Remembered: cancelled safely')
        t.wait('Done.')
        t.send('worker crash\r')
        t.wait('Turn failed.')
        t.wait('host adapter failed')
        t.send('Recall\r')
        t.wait('Recalled: cancelled safely')
        t.wait('Done.')
        t.send('literal tags\r')
        t.wait('is ordinary text.')
        t.wait('Done.')
        data = saved(history)[0]
        literal = next(item for item in data['items'] if 'is ordinary text.' in item.get('content', ''))
        assert '<FLEXSCRIPT>' in literal['content'] and not literal.get('source') and not literal.get('observation'), 'ordinary tags executed a program'
        t.send('unknown tool\r')
        t.wait('Turn failed.')
        t.send('Recall\r')
        t.wait('Recalled: cancelled safely')
        t.wait('Done.')
        t.send('/code\rslow code\r')
        t.wait('fn main(){')
        assert b'[-] Flexscript' in t.frame() and b'return 0;' not in t.frame().rsplit(b'[-] Flexscript', 1)[1], 'source was not streamed incrementally'
        assert b'VM continue' not in t.output[t.offset:], 'partial program executed'
        children = descendants(t.process.pid)
        t.send('\x1b')
        t.wait('Turn cancelled.')
        stopped(children)
    finally:
        t.close()
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        t = Terminal(binary, directory / f'signal-{sig}')
        t.wait('Welcome to Collie')
        t.send('slow\r')
        t.wait('First streamed chunk')
        children = descendants(t.process.pid)
        t.close(sig=sig)
        stopped(children)
    print('PTY streaming: partial replies, draft retention, cancellation/retry, adapter failure, native tools and signal cleanup passed.')


def clipboard_tests(binary, directory):
    bins = directory / 'clipboard-bin'
    bins.mkdir()
    clipboard = directory / 'clipboard.txt'
    helper = '#!' + sys.executable + '''
import os, sys
from pathlib import Path
file = Path(os.environ['COLLIE_TEST_CLIPBOARD'])
if Path(sys.argv[0]).name == 'wl-copy':
    file.write_bytes(sys.stdin.buffer.read())
else:
    sys.stdout.buffer.write(file.read_bytes())
'''
    for name in ('wl-copy', 'wl-paste'):
        file = bins / name
        file.write_text(helper)
        file.chmod(0o755)
    env = dict(os.environ, PATH=str(bins) + ':' + os.environ['PATH'],
               WAYLAND_DISPLAY='isolated-collie-test', COLLIE_TEST_CLIPBOARD=str(clipboard))
    t = Terminal(binary, directory / 'clipboard-history', env=env)
    try:
        t.wait('Welcome to Collie')
        t.send('你好 clipboard\x01\x03')
        t.wait('Copied selection.')
        assert clipboard.read_text() == '你好 clipboard'
        # Cut and paste replace the composer selection and retain Unicode.
        t.send('\x18')
        assert b'\xe4\xbd\xa0\xe5\xa5\xbd clipboard' not in t.frame()
        t.send('\x16')
        t.wait('你好 clipboard')
        t.send('\x15Remember mouse copy\r')
        t.wait('Remembered: mouse copy')
        t.wait('Done.')
        # Drag a range in the transcript and copy on release.
        row = int(re.search(rb'\x1b\[(\d+);1H\x1b\[2KRemembered: mouse copy', t.frame()).group(1))
        t.send(f'\x1b[<0;1;{row}M\x1b[<32;11;{row}M\x1b[<0;11;{row}m')
        t.wait('Copied selection.')
        assert clipboard.read_text() == 'Remembered', 'transcript selection offsets wrong'
        # A later click dismisses the old range; right-click pastes in composer.
        t.send('\x1b[<0;1;27M\x1b[<0;1;27m')
        assert b'\x1b[7m' not in t.frame(), 'stale transcript selection remained'
        clipboard.write_text('right-click paste')
        t.send('\x1b[<2;1;27M')
        t.wait('right-click paste')
    finally:
        t.close()
    print('PTY clipboard: Unicode copy/cut/paste, transcript drag, selection dismissal and right-click paste passed.')


def context_tests(binary, directory):
    history = directory / 'context-history'
    cache = directory / 'context-codex'
    cache.mkdir()
    models = cache / 'models_cache.json'
    models.write_text(json.dumps(dict(models=[dict(slug='fixture-model', context_window=100000), dict(slug='another-model', context_window=200000)])))
    env = dict(os.environ, CODEX_HOME=str(cache))
    t = Terminal(binary, history, env=env)
    try:
        t.wait('Context ?/95000 tok')
        assert b'Context 2 B/8 MiB | 0 messages' in t.frame()
        t.send('usage one\r')
        t.wait('Done.')
        assert b'Context 120/95000 tok (last)' in t.frame()
        data = saved(history)[0]
        size = len(json.dumps(data['messages'], ensure_ascii=False, separators=(',', ':')).encode())
        assert f'Context {size} B/8 MiB | 2 messages'.encode() in t.frame()
        assert data['usage']['total_tokens'] == 120
        t.send('usage two\r')
        t.wait('Done.')
        assert b'Context 230/95000 tok (last)' in t.frame(), 'usage was summed across requests'
        t.send('/help\r')
        t.wait('Collie help')
        assert b'Context 230/95000 tok (last)' in t.frame(), 'menu hid context'
        t.send('\x1b/new\r')
        t.wait('Context ?/95000 tok')
        t.send('/resume latest\r')
        t.wait('Resumed saved conversation')
        assert b'Context 230/95000 tok (last)' in t.frame()
        t.send('/clear\r')
        t.wait('conversation retained')
        assert b'Context 230/95000 tok (last)' in t.frame()
        # Old session files without usage remain readable.
        data = saved(history)[0]
        data.pop('usage')
        (history / '1-2-3.json').write_text(json.dumps(data))
        t.send('/resume 1-2-3\r')
        t.wait('Resumed saved conversation')
        assert b'Context ?/95000 tok' in t.frame()
        t.send('/model another-model\r')
        t.wait('Selected model: another-model')
        assert b'Context ?/190000 tok' in t.frame() and b'Context 2 B/8 MiB | 0 messages' in t.frame()
        models.write_text('{broken cache')
        t.send('/model uncached-model\r')
        t.wait('Selected model: uncached-model')
        assert b'Context ?/258400 tok' in t.frame(), 'optional corrupt cache did not use Codex fallback'
    finally:
        t.close()
    print('PTY context: reported tokens, cached window, current bytes, reset/resume, menus and optional metadata passed.')


def context_command_tests(binary, directory):
    history = directory / 'context-command-history'
    cache = directory / 'context-command-codex'
    cache.mkdir()
    (cache / 'models_cache.json').write_text(json.dumps(dict(models=[dict(
        slug='fixture-model', context_window=272000, max_context_window=872000)])))
    env = dict(os.environ, CODEX_HOME=str(cache))
    t = Terminal(binary, history, env=env)
    try:
        t.wait('Welcome to Collie')
        t.send('/con\t\r')
        t.wait('Context limits')
        assert b'Context window: 272000' in t.frame() and b'Auto-compact tokens: 244800' in t.frame()
        t.send('\x1busage one\r')
        t.wait('Done.')
        before = saved(history)[0]['messages']
        t.send('/context 500000\r')
        t.wait('Context limits')
        assert b'Context 120/475000 tok' in t.frame() and b'Auto-compact tokens: 450000' in t.frame()
        t.send('\x1b/compact 300000\r')
        t.wait('Auto-compact tokens: 300000')
        data = saved(history)[0]
        assert data['messages'] == before and data['usage']['total_tokens'] == 120
        assert data['limits'] == dict(model_context_window=500000, model_auto_compact_token_limit=300000)
        for invalid in ('0', '-1', 'abc', '1000000001', '999999999999999999999999', 'compact 0', 'compact', '500000 extra'):
            t.send('\x1b/context ' + invalid + '\r')
            t.wait('Use /context N')
            assert b'Context 120/475000 tok' in t.frame()
            assert saved(history)[0]['limits'] == data['limits']
        t.send('/context 1000000\r')
        t.wait('Context window: 872000')
        data = saved(history)[0]
        for invalid in ('0', '-1', 'abc', '1000000001', '999999999999999999999999', '300000 extra'):
            t.send('\x1b/compact ' + invalid + '\r')
            t.wait('Use /compact N')
            assert saved(history)[0]['limits'] == data['limits']
        t.send('/compact 999999\r')
        t.wait('Auto-compact tokens: 784800')
        t.send('\x1b/context default\r')
        t.wait('Auto-compact tokens: 244800')
        assert b'Context 120/258400 tok' in t.frame() and saved(history)[0]['limits'] == {}
        t.send('\x1b/context 500000\r')
        t.wait('Auto-compact tokens: 450000')
        t.send('\x1b/compact 300000\r')
        t.wait('Auto-compact tokens: 300000')
        t.send('\x1b/compact default\r')
        t.wait('Auto-compact tokens: 450000')
        t.send('\x1b/compact 300000\r')
        t.wait('Auto-compact tokens: 300000')
    finally:
        t.close()
    t = Terminal(binary, history, env=env)
    try:
        t.wait('Context ?/258400 tok')
        t.send('/resume latest\r')
        t.wait('Resumed saved conversation')
        assert b'Context 120/475000 tok' in t.frame()
        t.send('/context\r')
        t.wait('Auto-compact tokens: 300000')
        t.send('\x1bslow\r')
        t.wait('First streamed chunk')
        t.send('/compact default\r')
        t.wait('before changing context limits')
        assert b'/475000 tok' in t.frame()
        t.wait('Done.')
        # Invalid limits in an untrusted session are rejected before loading.
        data = saved(history)[0]
        data['limits']['model_context_window'] = 'bad'
        (history / '1-2-3.json').write_text(json.dumps(data))
        t.send('/resume 1-2-3\r')
        t.wait('Cannot resume: invalid or unsupported session.')
        assert b'/475000 tok' in t.frame()
    finally:
        t.close()
    print('PTY /context and /compact: completion, limits, caps, validation, reset, preserved conversation, restart/resume and busy guard passed.')


def workspace_tests(binary, directory):
    history = directory / 'workspace-history'
    mode = directory / 'workspace-compact-mode'
    mode.write_text('ok')
    cache = directory / 'workspace-codex'
    cache.mkdir()
    env = dict(os.environ, CODEX_HOME=str(cache), COLLIE_FIXTURE_COMPACT_MODE=str(mode))
    t = Terminal(binary, history, env=env)
    try:
        t.wait('Welcome to Collie')
        t.send('db seed\r')
        t.wait('Workspace saved.')
        t.wait('Done.')
        session = next(history.glob('*.json')).stem
        file = history / (session + '.json')
        data = json.loads(file.read_text())
        assert data['items'][1]['observation']['stdout'] == 'stored\n'
        workspace = history / 'workspaces' / (session + '.flexdb')
        assert workspace.read_bytes().startswith(b'FLEXDB') and workspace.stat().st_mode & 0o777 == 0o600
        t.send('db evolve\r')
        t.wait('Schema evolved.')
        t.wait('Done.')
        t.send('/compact\r')
        t.wait('Conversation compacted.')
        assert json.loads(file.read_text())['compactions'] == 1
        t.send('db history\r')
        t.wait('Archived seed request found.')
        t.wait('Done.')
        t.send('/new\r')
        t.wait('Ready.')
        t.send('db inspect\r')
        t.wait('Workspace is empty.')
        t.wait('Done.')
        t.send('/resume ' + session + '\r')
        t.wait('Resumed saved conversation')
        t.send('db recall\r')
        t.wait('Workspace recalled.')
        t.wait('Done.')
        archive = json.loads(Path(str(workspace) + '.history.json').read_text())['items']
        assert archive[0]['content'] == 'db seed' and any(m.get('observation', {}).get('stdout') == 'evolved\n' for m in archive)
    finally:
        t.close()
    t = Terminal(binary, history, ['--resume', session], env=env)
    try:
        t.wait('Resumed saved conversation')
        t.send('db recall\r')
        t.wait('Workspace recalled.')
        t.wait('Done.')
    finally:
        t.close()
    print('PTY workspace: empty schema, real VM writes, schema evolution, compaction, archived history, new-session isolation and restart/resume passed.')


def compaction_tests(binary, directory, with_vm):
    history = directory / 'compact-history'
    cache = directory / 'compact-codex'
    cache.mkdir()
    (cache / 'models_cache.json').write_text(json.dumps(dict(models=[dict(slug='fixture-model', context_window=100000, max_context_window=200000)])))
    mode = directory / 'compact-mode'
    mode.write_text('ok')
    env = dict(os.environ, CODEX_HOME=str(cache), COLLIE_FIXTURE_COMPACT_MODE=str(mode))
    options = ['--auto-compact', '5000']
    t = Terminal(binary, history, env=env)
    try:
        t.wait('Welcome to Collie')
        t.send('/compact 5000\r')
        t.wait('Auto-compact tokens: 5000')
        t.send('\x1bRemember checkpoint memory\r')
        t.wait('Remembered: checkpoint memory')
        t.wait('Done.')
        t.send('grow context\r')
        t.wait('Done.')
        assert b'Context 6100/95000 tok (last)' in t.frame()
        t.send('Recall\r')
        t.wait('Recalled: checkpoint memory')
        t.wait('Done.')
        data = saved(history)[0]
        assert data['compactions'] == 1 and len(data['items']) == 6
        assert sum(m.get('type') == 'compaction' for m in data['messages']) == 1
        assert sum(m.get('role') == 'assistant' for m in data['messages']) == 1, 'old assistant text was not replaced'
        assert b'(est)' in t.frame(), 'checkpoint estimate presented as exact usage'
        t.send('/compact\r')
        t.wait('Conversation compacted.')
        t.pump(.15)
        data = saved(history)[0]
        assert data['compactions'] == 2 and len(data['items']) == 6, 'manual compaction changed the visible conversation'
        assert sum(m.get('type') == 'compaction' for m in data['messages']) == 1, 'old checkpoint accumulated'
        # Interrupted manual compaction keeps the last committed window.
        before = data['messages']
        mode.write_text('slow')
        t.send('/compact\r')
        t.wait('Compacting conversation...')
        children = descendants(t.process.pid)
        t.send('\x1b')
        t.wait('Compaction stopped.')
        stopped(children)
        assert saved(history)[0]['messages'] == before
        # Failed and malformed summaries must never replace the checkpoint.
        for failure in ('failure', 'malformed'):
            mode.write_text(failure)
            t.send('/compact\r')
            t.wait('Compaction failed:')
            t.wait('Turn failed.')
            t.pump(.1)
            assert saved(history)[0]['messages'] == before
        mode.write_text('ok')
        t.send('/new\r/resume latest\r')
        t.wait('Resumed saved conversation')
        t.send('Recall\r')
        t.wait('Recalled: checkpoint memory')
        t.wait('Done.')
    finally:
        t.close()
    for failure in ('failure', 'nonreducing'):
        mode.write_text(failure)
        failed_history = directory / f'auto-compact-{failure}'
        t = Terminal(binary, failed_history, options, env)
        try:
            t.wait('Welcome to Collie')
            t.send('grow context\r')
            t.wait('Done.')
            t.send('Remember pending request\r')
            t.wait('Compaction failed:')
            t.wait('Turn failed.')
            t.pump(.1)
            data = saved(failed_history)[0]
            assert data['compactions'] == 0 and not any(m.get('type') == 'compaction' for m in data['messages'])
            assert any(m.get('content') == 'Remember pending request' for m in data['messages']), 'failure lost pending user input'
            mode.write_text('ok')
            t.send('Remember recovered request\r')
            t.wait('Remembered: recovered request')
            t.wait('Done.')
        finally:
            t.close()
    mode.write_text('ok')
    # A restart must send the opaque item back, rather than stringify it as prose.
    t = Terminal(binary, history, [*options, '--resume', 'latest'], env)
    try:
        t.wait('Resumed saved conversation')
        t.send('Recall\r')
        t.wait('Recalled: checkpoint memory')
        t.wait('Done.')
    finally:
        t.close()
    # Explicit backend context-length errors compact and retry once, even below the threshold.
    t = Terminal(binary, directory / 'recover-context', env=env)
    try:
        t.wait('Welcome to Collie')
        t.send('grow context\r')
        t.wait('Done.')
        t.send('context exceeded\r')
        t.wait('Recovered from context exhaustion.')
        t.wait('Done.')
        assert b'1 compactions' in t.frame()
    finally:
        t.close()
    if with_vm:
        t = Terminal(binary, directory / 'compact-vm', options, env)
        try:
            t.wait('Welcome to Collie')
            t.send('mid compact\r')
            t.wait('Mid-turn compaction kept the VM result: 42.')
            t.wait('Done.')
            data = saved(directory / 'compact-vm')[0]
            assert data['compactions'] == 1
            assert sum(bool(m.get('observation')) for m in data['items']) == 1, 'VM ran again during compaction'
        finally:
            t.close()
        mode.write_text('slow')
        cancelled = directory / 'compact-vm-cancelled'
        t = Terminal(binary, cancelled, options, env)
        try:
            t.wait('Welcome to Collie')
            t.send('mid compact\r')
            t.wait('Compacting conversation...')
            children = descendants(t.process.pid)
            t.send('\x1b')
            t.wait('Turn cancelled.')
            stopped(children)
            data = saved(cancelled)[0]
            assert sum(m.get('content') == 'mid compact' for m in data['messages']) == 1, 'cancel duplicated the pending prompt'
            calls = [m for m in data['messages'] if m.get('type') == 'custom_tool_call']
            results = [m for m in data['messages'] if m.get('type') == 'custom_tool_call_output']
            assert len(calls) == len(results) == 1 and calls[0]['call_id'] == results[0]['call_id'], 'cancel lost the completed tool call/result pair'
            assert data['compactions'] == 0
        finally:
            t.close()
    print('PTY compaction: automatic/manual checkpoints, transcript retention, cancellation/failure, resume, retry and VM boundaries passed.')


def vm_tests(binary, directory):
    history = directory / 'vm'
    t = Terminal(binary, history)
    try:
        t.wait('Welcome to Collie')
        t.send('host failure\r')
        t.wait('Turn failed.')
        t.wait('Fixture isolated VM could not start.')
        data = saved(history)[0]
        calls = [m for m in data['messages'] if m.get('type') == 'custom_tool_call']
        results = [m for m in data['messages'] if m.get('type') == 'custom_tool_call_output']
        assert len(calls) == len(results) == 1 and calls[0]['call_id'] == results[0]['call_id']
        assert json.loads(results[0]['output'])['executed'] is False
        t.send('/resume latest\r')
        t.wait('Resumed saved conversation')
        t.send('/new\r')
        t.send('failure\r')
        t.wait('Recovered from the compiler error.')
        t.wait('Done.')
        assert b'undefined function' in t.frame(), 'collapsed compiler diagnostic missing'
        assert b'\x1b[33m' in t.frame(), 'error lost its color'
        t.send('/new\rcode\r')
        t.wait('42 is the actual VM result.')
        t.wait('Done.')
        assert b'[+] Flexscript' in t.frame() and b'fn main' not in t.frame()
        t.send('\x14')
        t.wait('[-] Flexscript')
        t.wait('VM stdout:')
        assert b'fn main' in t.frame() and b'42' in t.frame()
        t.send('\x14')
        t.wait('[+] Flexscript')
        # Click the actual wrapped heading row.
        matches = re.findall(rb'\x1b\[(\d+);1H\x1b\[2K(?:\x1b\[[0-9;]*m)*\[\+\] Flexscript', t.frame())
        assert matches, 'collapsed heading not visible'
        row = int(matches[0])
        t.send(f'\x1b[<0;2;{row}M\x1b[<0;2;{row}m')
        t.wait('[-] Flexscript')
        t.send('/code off\r')
        t.wait('Code display: off')
        assert b'fn main' not in t.frame()
        t.send('/code\r')
        t.wait('Code display: on')
        assert b'fn main' in t.frame()
        t.send('/logs\r')
        t.wait('Activity log')
        t.send('\x1b')
        t.send('/resume latest\r')
        t.wait('Resumed saved conversation')
        assert b'VM stdout:' in t.frame(), 'resumed observation missing'
    finally:
        t.close()
    print('PTY VM: real execution, visible compiler errors, expandable source/output, mouse and resumed observations passed.')


def main():
    global COMPILER
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', default='build/flex-android')
    parser.add_argument('--binary', default='build/collie')
    parser.add_argument('--vm', action='store_true')
    args = parser.parse_args()
    COMPILER = (ROOT / args.compiler).resolve()
    binary = (ROOT / args.binary).resolve()
    with tempfile.TemporaryDirectory(prefix='collie-tui-', dir=ROOT / 'build') as temp:
        directory = Path(temp)
        default_startup_tests(binary, directory)
        script_launch_tests(directory)
        worker = directory / 'fixture-collie'
        subprocess.run([str(COMPILER), 'apps/collie/tests/tui-worker.flex', '-o', str(worker)], cwd=ROOT, check=True)
        chat_tests(worker, directory)
        cancellation_tests(worker, directory)
        clipboard_tests(worker, directory)
        context_tests(worker, directory)
        context_command_tests(worker, directory)
        compaction_tests(worker, directory, args.vm)
        if args.vm:
            vm_tests(worker, directory)
            workspace_tests(worker, directory)
        # Exercise the production entry point with no prompt (automatic TUI).
        t = Terminal(binary, directory / 'production', ['--replay', 'apps/collie/tests/fixtures/greeting.json'])
        try:
            t.wait('Welcome to Collie')
            t.send('Hello\r')
            t.wait('Hello! No program is needed.')
            t.wait('Done.')
        finally:
            t.close()
        t = Terminal(binary, directory / 'initial-task', ['--tui', 'Hello', '--replay', 'apps/collie/tests/fixtures/greeting.json'])
        try:
            t.wait('Hello! No program is needed.')
            t.wait('Done.')
        finally:
            t.close()
    print('Production CLI: automatic TUI and offline reply passed.')


if __name__ == '__main__':
    main()
