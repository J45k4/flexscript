"""Launch the same embedded engine checks on Android ARM64 or native desktop."""
from pathlib import Path


def command(out, op, root, desktop, qemu):
    out = Path(out).resolve()
    if desktop:
        return [str(out/'engine'), str(op), str(root), str(out/'broker.so')]
    return [qemu, str(out/'native-test'), str(op), str(root)]
