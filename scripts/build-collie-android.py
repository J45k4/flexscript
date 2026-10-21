#!/usr/bin/env python3
"""Build the native Collie Android APK (no Python runtime on the phone)."""
import runpy
from pathlib import Path
runpy.run_path(str(Path(__file__).resolve().parents[1]/'apps/collie/android/build.py'),run_name='__main__')
