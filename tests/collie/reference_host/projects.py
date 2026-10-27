"""Desktop project registry; conversation metadata stays in Collie's data folder."""
from pathlib import Path
import json
import uuid

from linux_platform import atomic


class Projects:
    def __init__(self, data):
        self.file = Path(data)/'projects.json'
        try:
            self.entries = json.loads(self.file.read_text())
        except FileNotFoundError:
            self.entries = []
        if not isinstance(self.entries, list) or any(
                not isinstance(row, dict) or not all(isinstance(row.get(k), str) for k in ('id', 'name', 'path'))
                or not Path(row['path']).is_absolute() for row in self.entries):
            raise ValueError('Invalid project registry')

    def get(self, id):
        if not id:
            return None
        for entry in self.entries:
            if entry['id'] == id:
                return entry
        raise ValueError('Project no longer exists')

    def add(self, folder):
        path = Path(folder).expanduser().resolve(strict=True)
        if not path.is_dir():
            raise ValueError('Choose a project folder')
        for entry in self.entries:
            if entry['path'] == str(path):
                return entry
        if len(self.entries) >= 128:
            raise ValueError('Up to 128 project folders are supported')
        entry = dict(id=uuid.uuid4().hex, name=path.name or str(path), path=str(path))
        entries = self.entries+[entry]
        atomic(self.file, json.dumps(entries, separators=(',', ':')).encode())
        self.entries = entries
        return entry
