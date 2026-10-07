#!/usr/bin/env python3
"""Build Todo using the released compiler; test its model, storage and own X11 window."""
import argparse
import ctypes as C
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def wait_for(check, message, process=None):
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline:
        if check():
            return
        if process and process.poll() is not None:
            raise AssertionError(f"App exited: {process.communicate()}")
        time.sleep(0.03)
    raise AssertionError(message)


def records(path):
    if not path.exists():
        return []
    lines = path.read_text().splitlines()
    assert lines[0] == "FLEXTODO1"
    return [(line[0] == '1', line[2:]) for line in lines[1:]]


def storage_tests(binary, directory):
    subprocess.run([binary, '--self-test'], check=True)
    data = directory / 'roundtrip.db'
    subprocess.run([binary, '--self-test', '--data', str(data)], check=True)
    assert records(data) == [(True, 'Learn Flexscript'), (True, 'Make something useful')]
    assert data.stat().st_mode & 0o777 == 0o600
    assert not list(directory.glob('*.tmp.*'))
    before = data.read_bytes()
    result = subprocess.run([binary, '--self-test', '--data', str(data)], capture_output=True)
    assert result.returncode == 1 and data.read_bytes() == before
    bad_data = [b'', b'wrong header\n', b'FLEXTODO1\n2\tbad\n', b'FLEXTODO1\n0\t\n',
                b'FLEXTODO1\n0\tno newline', b'FLEXTODO1\n0\tnon\x01printable\n',
                b'FLEXTODO1\n0\t' + b'x' * 121 + b'\n',
                b'FLEXTODO1\n' + b'0\ta\n' * 257]
    environment = dict(os.environ, DISPLAY=':99999')
    for i, content in enumerate(bad_data):
        path = directory / f'bad-{i}.db'
        path.write_bytes(content)
        result = subprocess.run([binary, '--data', str(path)], env=environment, capture_output=True)
        assert result.returncode == 1 and b'Invalid or unreadable' in result.stderr
        assert path.read_bytes() == content
    link = directory / 'symlink.db'
    link.symlink_to(data)
    result = subprocess.run([binary, '--data', str(link)], env=environment, capture_output=True)
    assert result.returncode == 1 and data.read_bytes() == before
    result = subprocess.run([binary, '--data', str(directory / 'missing-display.db')],
                            env={k: v for k, v in os.environ.items() if k != 'DISPLAY'}, capture_output=True)
    assert result.returncode == 1 and b'DISPLAY is not set' in result.stderr
    assert subprocess.run([binary, '--bad-option'], capture_output=True).returncode == 1
    assert subprocess.run([binary, '--help'], capture_output=True, check=True).stdout.startswith(b'Flexscript Todo')
    print('Storage: round trip, atomic replacement, permissions, limits, corrupt files and symlinks passed')


# Xlib is used only by the test driver. The compiled app speaks X11 directly.
class KeyEvent(C.Structure):
    _fields_ = [('type', C.c_int), ('serial', C.c_ulong), ('send_event', C.c_int),
                ('display', C.c_void_p), ('window', C.c_ulong), ('root', C.c_ulong),
                ('subwindow', C.c_ulong), ('time', C.c_ulong), ('x', C.c_int), ('y', C.c_int),
                ('x_root', C.c_int), ('y_root', C.c_int), ('state', C.c_uint),
                ('keycode', C.c_uint), ('same_screen', C.c_int)]


class ButtonEvent(C.Structure):
    _fields_ = [(name if name != 'keycode' else 'button', kind) for name, kind in KeyEvent._fields_]


class ClientData(C.Union):
    _fields_ = [('b', C.c_char * 20), ('s', C.c_short * 10), ('l', C.c_long * 5)]


class ClientEvent(C.Structure):
    _fields_ = [('type', C.c_int), ('serial', C.c_ulong), ('send_event', C.c_int),
                ('display', C.c_void_p), ('window', C.c_ulong), ('message_type', C.c_ulong),
                ('format', C.c_int), ('data', ClientData)]


class Event(C.Union):
    _fields_ = [('key', KeyEvent), ('button', ButtonEvent), ('client', ClientEvent), ('pad', C.c_long * 24)]


class XImage(C.Structure):
    _fields_ = [('width', C.c_int), ('height', C.c_int), ('xoffset', C.c_int), ('format', C.c_int),
                ('data', C.c_void_p), ('byte_order', C.c_int), ('bitmap_unit', C.c_int),
                ('bitmap_bit_order', C.c_int), ('bitmap_pad', C.c_int), ('depth', C.c_int),
                ('bytes_per_line', C.c_int), ('bits_per_pixel', C.c_int),
                ('red_mask', C.c_ulong), ('green_mask', C.c_ulong), ('blue_mask', C.c_ulong)]


class Desktop:
    def __init__(self):
        self.x = C.CDLL('libX11.so.6')
        signatures = {
            'XOpenDisplay': (C.c_void_p, [C.c_char_p]),
            'XDefaultRootWindow': (C.c_ulong, [C.c_void_p]),
            'XQueryTree': (C.c_int, [C.c_void_p, C.c_ulong, C.POINTER(C.c_ulong), C.POINTER(C.c_ulong),
                                   C.POINTER(C.POINTER(C.c_ulong)), C.POINTER(C.c_uint)]),
            'XFetchName': (C.c_int, [C.c_void_p, C.c_ulong, C.POINTER(C.c_void_p)]),
            'XFree': (C.c_int, [C.c_void_p]),
            'XSendEvent': (C.c_int, [C.c_void_p, C.c_ulong, C.c_int, C.c_long, C.POINTER(Event)]),
            'XFlush': (C.c_int, [C.c_void_p]),
            'XSync': (C.c_int, [C.c_void_p, C.c_int]),
            'XKeysymToKeycode': (C.c_uint, [C.c_void_p, C.c_ulong]),
            'XInternAtom': (C.c_ulong, [C.c_void_p, C.c_char_p, C.c_int]),
            'XGetGeometry': (C.c_int, [C.c_void_p, C.c_ulong, C.POINTER(C.c_ulong), C.POINTER(C.c_int),
                                      C.POINTER(C.c_int), C.POINTER(C.c_uint), C.POINTER(C.c_uint),
                                      C.POINTER(C.c_uint), C.POINTER(C.c_uint)]),
            'XGetImage': (C.c_void_p, [C.c_void_p, C.c_ulong, C.c_int, C.c_int, C.c_uint, C.c_uint,
                                      C.c_ulong, C.c_int]),
            'XDestroyImage': (C.c_int, [C.c_void_p]),
            'XCloseDisplay': (C.c_int, [C.c_void_p]),
        }
        for name, (result, args) in signatures.items():
            fn = getattr(self.x, name)
            fn.restype, fn.argtypes = result, args
        self.display = self.x.XOpenDisplay(None)
        if not self.display:
            raise RuntimeError('Cannot open DISPLAY. Run with local display access, or omit --gui.')
        self.root = self.x.XDefaultRootWindow(self.display)
        self.window = 0

    def windows(self):
        result = set()
        def visit(window):
            name = C.c_void_p()
            if self.x.XFetchName(self.display, window, C.byref(name)) and name.value:
                if C.string_at(name.value) == b'Flexscript Todo':
                    result.add(window)
                self.x.XFree(name)
            root, parent, children, count = C.c_ulong(), C.c_ulong(), C.POINTER(C.c_ulong)(), C.c_uint()
            if self.x.XQueryTree(self.display, window, C.byref(root), C.byref(parent), C.byref(children), C.byref(count)):
                values = [children[i] for i in range(count.value)]
                if children:
                    self.x.XFree(children)
                for child in values:
                    visit(child)
        visit(self.root)
        return result

    def key(self, symbol, state=0):
        event = Event()
        key = event.key
        key.type, key.display, key.window, key.root, key.same_screen = 2, self.display, self.window, self.root, 1
        key.state, key.keycode = state, self.x.XKeysymToKeycode(self.display, symbol)
        assert key.keycode, f'No mapping for {symbol}'
        assert self.x.XSendEvent(self.display, self.window, 0, 1, C.byref(event))
        self.x.XFlush(self.display)

    def text(self, text):
        for char in text:
            self.key(ord(char), 1 if char.isupper() else 0)

    def click(self, x, y, button=1):
        event = Event()
        b = event.button
        b.type, b.display, b.window, b.root, b.same_screen = 4, self.display, self.window, self.root, 1
        b.x, b.y, b.button = x, y, button
        assert self.x.XSendEvent(self.display, self.window, 0, 4, C.byref(event))
        self.x.XFlush(self.display)
        time.sleep(0.07)

    def close_window(self):
        event = Event()
        event.client.type, event.client.display, event.client.window = 33, self.display, self.window
        event.client.message_type = self.x.XInternAtom(self.display, b'WM_PROTOCOLS', 0)
        event.client.format = 32
        event.client.data.l[0] = self.x.XInternAtom(self.display, b'WM_DELETE_WINDOW', 0)
        assert self.x.XSendEvent(self.display, self.window, 0, 0, C.byref(event))
        self.x.XFlush(self.display)

    def size(self):
        root, x, y = C.c_ulong(), C.c_int(), C.c_int()
        w, h, border, depth = C.c_uint(), C.c_uint(), C.c_uint(), C.c_uint()
        assert self.x.XGetGeometry(self.display, self.window, C.byref(root), C.byref(x), C.byref(y),
                                    C.byref(w), C.byref(h), C.byref(border), C.byref(depth))
        return w.value, h.value

    def screenshot(self, path):
        from PIL import Image
        self.x.XSync(self.display, 0)
        w, h = self.size()
        ptr = self.x.XGetImage(self.display, self.window, 0, 0, w, h, C.c_ulong(-1), 2)
        assert ptr
        try:
            info = C.cast(ptr, C.POINTER(XImage)).contents
            assert info.bits_per_pixel == 32 and info.byte_order == 0
            raw = C.string_at(info.data, info.bytes_per_line * info.height)
            image = Image.frombytes('RGB', (w, h), raw, 'raw', 'BGRX', info.bytes_per_line)
            assert image.getpixel((10, h // 2)) == (25, 61, 50), 'Sidebar was not drawn'
            assert image.getpixel((220, 10)) == (244, 244, 239), 'Page was not drawn'
            image.save(path)
        finally:
            self.x.XDestroyImage(ptr)


def gui_tests(binary, directory, screenshot):
    desktop = Desktop()
    path = directory / 'gui.db'
    processes = []
    def start():
        previous = desktop.windows()
        process = subprocess.Popen([binary, '--data', str(path)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        processes.append(process)
        wait_for(lambda: bool(desktop.windows() - previous), 'Window did not open', process)
        desktop.window = (desktop.windows() - previous).pop()
        time.sleep(0.3)
        return process
    def expect(expected):
        wait_for(lambda: records(path) == expected, f'Expected {expected}; got {records(path)}', process)
    def stop():
        desktop.close_window()
        output = process.communicate(timeout=5)
        assert process.returncode == 0 and output == (b'', b''), output
    try:
        process = start()
        w, h = desktop.size()
        assert w >= 760 and h >= 560
        desktop.text('Buy groceries'); desktop.key(0xff0d)
        expect([(False, 'Buy groceries')])
        desktop.text('Write Flexscript'); desktop.key(0xff0d)
        expect([(False, 'Buy groceries'), (False, 'Write Flexscript')])
        desktop.click(270, 294)
        expect([(True, 'Buy groceries'), (False, 'Write Flexscript')])
        desktop.click(60, 250)  # Active filter: one row remains.
        desktop.click(w - 98, 294)  # Edit active row, selected input gets replaced.
        desktop.text('Build something useful'); desktop.key(0xff0d)
        expect([(True, 'Buy groceries'), (False, 'Build something useful')])
        desktop.click(60, 302)  # Completed filter.
        desktop.click(w - 60, 294)
        expect([(False, 'Build something useful')])
        desktop.click(60, 198)  # All tasks.
        desktop.click(270, 294)
        expect([(True, 'Build something useful')])
        # Tab to input, create a second task, then verify keyboard list editing.
        desktop.key(0xff09); desktop.text('Take a break'); desktop.key(0xff0d)
        expect([(True, 'Build something useful'), (False, 'Take a break')])
        desktop.key(0xff09); desktop.key(0xffbf)
        desktop.text('Take a walk'); desktop.key(0xff0d)
        expect([(True, 'Build something useful'), (False, 'Take a walk')])
        locked = subprocess.run([binary, '--data', str(path)], capture_output=True)
        assert locked.returncode == 1 and b'Another Todo instance' in locked.stderr
        stop()
        process = start()
        expect([(True, 'Build something useful'), (False, 'Take a walk')])
        w, h = desktop.size()
        desktop.click(w - 100, 239)  # Clear done.
        expect([(False, 'Take a walk')])
        # An occupied temporary path must preserve both the data and the
        # existing temporary file; Ctrl+S must recover when it is removed.
        blocked = path.with_name(path.name + f'.tmp.{process.pid}')
        blocked.write_text('Leave this file alone')
        before = path.read_bytes()
        desktop.click(270, 294)
        time.sleep(0.2)
        assert path.read_bytes() == before and blocked.read_text() == 'Leave this file alone'
        blocked.unlink()
        desktop.key(ord('s'), 4)
        expect([(True, 'Take a walk')])
        desktop.click(270, 294)
        expect([(False, 'Take a walk')])
        desktop.click(300, 182)  # Return focus to text input after using the list.
        # Add a realistic synthetic list for visual inspection and exercise scrolling.
        for item in ['Review the weekly plan', 'Sketch a new idea', 'Learn a little Flexscript',
                     'Water the plants', 'Read a chapter', 'Make time for a friend',
                     'Keep the small promises', 'Finish the first draft', 'Tidy the desk']:
            desktop.text(item); desktop.key(0xff0d)
        wait_for(lambda: len(records(path)) == 10, 'Ten tasks were not saved', process)
        # Mouse wheel returns to the beginning without changing the task data.
        for _ in range(20):
            desktop.click(400, 350, 4)
        desktop.click(270, 294)
        wait_for(lambda: records(path)[0][0], 'Checkbox did not complete first task', process)
        time.sleep(0.25)
        desktop.screenshot(screenshot)
        desktop.click(300, 182)
        # Force actual overflow even on a large tiled desktop. Adding scrolls
        # to the end; a click there must affect the first visible last-page row.
        capacity = max(1, (h - 326) // 66)
        expected = records(path)
        while len(expected) <= capacity + 5:
            name = f'Extra task {len(expected)}'
            desktop.text(name); desktop.key(0xff0d)
            expected.append((False, name))
        expect(expected)
        last_page = len(expected) - capacity
        desktop.click(270, 294)
        expected[last_page] = (True, expected[last_page][1])
        expect(expected)
        for _ in range(len(expected)):
            desktop.click(400, 350, 4)
        desktop.click(400, 350, 5)
        desktop.click(270, 294)
        expected[1] = (True, expected[1][1])
        expect(expected)
        stop()
        process = start()
        process.send_signal(signal.SIGTERM)
        output = process.communicate(timeout=5)
        assert process.returncode == 0 and output == (b'', b''), output
        print('GUI: add, complete, filters, mouse/keyboard edit, delete, clear, scroll, save retry, restart, locking and shutdown passed')
        print(f'Window-only screenshot: {screenshot}')
    finally:
        for process in processes:
            if process.poll() is None:
                process.terminate()
                try:
                    process.communicate(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill(); process.communicate()
        desktop.x.XCloseDisplay(desktop.display)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, default=ROOT / 'build/downloaded/flexscript-0.0.1-linux-x86_64')
    parser.add_argument('--gui', action='store_true', help='Also test only the newly opened app window on DISPLAY')
    args = parser.parse_args()
    binary = ROOT / 'build/todo'
    binary.parent.mkdir(exist_ok=True)
    subprocess.run([str(args.compiler.resolve()), str(ROOT / 'examples/todo.flex'), '-o', str(binary)], check=True)
    with tempfile.TemporaryDirectory(prefix='flexscript-todo-') as folder:
        directory = Path(folder)
        storage_tests(str(binary), directory)
        if args.gui:
            gui_tests(str(binary), directory, ROOT / 'build/todo.png')


if __name__ == '__main__':
    main()
