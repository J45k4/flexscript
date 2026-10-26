#!/usr/bin/env python3
"""Start Collie with the caller's display settings or an unambiguous local session."""
import os
from pathlib import Path
import stat
import sys


def display_environment(env, args, uid=None):
    result = dict(env)
    # Explicit backend choices and headless runs must never attach to an
    # unrelated graphical session as a side effect of a test.
    if (result.get('SDL_VIDEODRIVER') or result.get('SDL_VIDEO_DRIVER') or
            result.get('COLLIE_HEADLESS') == '1' or '--hidden' in args or
            result.get('WAYLAND_DISPLAY') or result.get('DISPLAY')):
        return result
    uid = os.getuid() if uid is None else uid
    runtime = Path(result.get('XDG_RUNTIME_DIR') or f'/run/user/{uid}')
    try:
        info = runtime.stat()
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != uid:
            return result
        sockets = []
        for path in runtime.glob('wayland-*'):
            info = path.lstat()
            if stat.S_ISSOCK(info.st_mode) and info.st_uid == uid:
                sockets.append(path)
        if len(sockets) == 1:
            result.update(XDG_RUNTIME_DIR=str(runtime), WAYLAND_DISPLAY=sockets[0].name,
                          XDG_SESSION_TYPE='wayland')
    except OSError:
        pass
    return result


def main():
    # These paths come from the generated launcher, not a shell command string.
    if len(sys.argv) < 3:
        raise SystemExit('Usage: launch.py BINARY SERVICE [OPTIONS]')
    binary, service, *args = sys.argv[1:]
    os.execve(binary, [binary, '--service', service, *args], display_environment(os.environ, args))


if __name__ == '__main__':
    main()
