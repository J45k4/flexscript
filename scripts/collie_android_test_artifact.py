"""Require device evidence to come from the APK named in the test report."""
import hashlib
import subprocess
from pathlib import Path


def verify_installed_apk(adb, serial, apk, package="org.flexscript.collie"):
    expected = hashlib.sha256(Path(apk).read_bytes()).hexdigest()
    command = [str(adb), '-s', serial]
    paths = subprocess.check_output(
        [*command, 'shell', 'pm', 'path', package],
        timeout=40, text=True,
    ).splitlines()
    if len(paths) != 1 or not paths[0].startswith('package:/'):
        raise AssertionError(f'Expected one installed Collie APK, received {paths!r}')
    installed = subprocess.check_output(
        [*command, 'exec-out', 'cat', paths[0][len('package:'):]], timeout=40,
    )
    actual = hashlib.sha256(installed).hexdigest()
    if actual != expected:
        raise AssertionError(
            f'Installed Collie APK is {actual}; test artifact {apk} is {expected}. '
            'Install the test artifact before running this check.'
        )
    return expected
