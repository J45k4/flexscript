#!/usr/bin/env python3
"""Exercise the docked workspace through the real native SDL host and PTY."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument("--out", type=Path, default=ROOT / "build/collie-desktop")
a = p.parse_args()
out = a.out.resolve()
checks = []


def passed(message):
    checks.append(message)
    print("PASS", message, flush=True)


def event(at, key, action, id=0, value=None, type="click"):
    return dict(at=at, request=dict(action="event", event=dict(
        key=key, action=action, action_id=id, value=value, type=type)))


def key(at, code, modifiers=64):
    return dict(at=at, request=dict(action="native_key", code=code, modifiers=modifiers))


with tempfile.TemporaryDirectory(prefix="workspace-", dir=out) as directory:
    work = Path(directory)
    fixture = work / "fixture.json"
    fixture.write_text("[]")
    native = work / "input.so"
    subprocess.run(["cc", "-shared", "-fPIC", "-O2", str(ROOT / "tests/ui/desktop-events.c"),
                    "-o", str(native), "-ldl"], check=True)
    project = work / "project"
    project.mkdir()
    (project / "src").mkdir()
    (project / "src/main.flex").write_text("fn main(){\n    return 42;\n}\n")
    (project / "notes.txt").write_text("original notes\n")
    (project / "run.sh").write_text("#!/bin/sh\necho original\n")
    (project / "run.sh").chmod(0o755)
    subprocess.run(["git", "init", "-q", str(project)], check=True)
    subprocess.run(["git", "-C", str(project), "add", "src/main.flex", "notes.txt", "run.sh"], check=True)
    subprocess.run(["git", "-C", str(project), "-c", "user.name=Fixture", "-c", "user.email=fixture@localhost",
                    "commit", "-qm", "Fixture baseline"], check=True)
    (project / "notes.txt").write_text("changed on disk\n")
    data = work / "data"
    session = data / "sessions/conversation"
    (session / "files").mkdir(parents=True)
    (session / "session.json").write_text(json.dumps(dict(project_id="project", messages=[], cards=[])))
    (data / "settings.json").write_text(json.dumps(dict(current="conversation")))
    (data / "projects.json").write_text(json.dumps([dict(id="project", name="Workspace fixture", path=str(project))]))
    env = dict(os.environ, SDL_VIDEODRIVER="dummy", COLLIE_HEADLESS="1", SHELL="/bin/sh", ENV="/dev/null")
    env.pop("DISPLAY", None)
    env.pop("WAYLAND_DISPLAY", None)

    def text(at, value):
        return dict(at=at, request=dict(action="native_text", fixture=str(native), text=value))

    def pointer(at, kind, x, y):
        return dict(at=at, request=dict(action="native_mouse", fixture=str(native),
                                       kind=kind, a=1 if kind != 1024 else x,
                                       b=x if kind != 1024 else y, c=y if kind != 1024 else 0, d=0))

    def run(name, events=(), frames=90, width=1440, height=960):
        script = work / f"{name}-events.json"
        expanded = []
        for item in events:
            request = item["request"]
            if request.get("action") == "native_text":
                value = request["text"]
                chunks = [value[i:i + 24] for i in range(0, len(value), 24)]
                for i, chunk in enumerate(chunks):
                    expanded.append(dict(at=item["at"] + i * 2, request=dict(request, text=chunk)))
            else:
                expanded.append(item)
        script.write_text(json.dumps(expanded))
        state = out / f"workspace-{name}-state.json"
        layout = out / f"workspace-{name}-layout.json"
        capture = out / f"workspace-{name}.rgba"
        result = subprocess.run([str(out / "collie"), "--hidden", "--frames", str(frames),
                                 "--width", str(width), "--height", str(height), "--data", str(data),
                                 "--fixture", str(fixture), "--events", str(script), "--dump-state", str(state),
                                 "--dump-layout", str(layout), "--capture", str(capture)],
                                env=env, capture_output=True, timeout=25)
        assert result.returncode == 0, (name, result.returncode, result.stderr.decode())
        facts = json.loads(state.read_text())
        boxes = {row["key"]: row for row in json.loads(layout.read_text())}
        try:
            from PIL import Image
            Image.frombytes("RGBA", (width, height), capture.read_bytes()).save(out / f"workspace-{name}.png")
        except ImportError:
            pass
        return facts, boxes

    def panel(state, kind, path=None):
        return next(p for p in state["workspace"]["panels"]
                    if p["kind"] == kind and (path is None or p.get("path") == path))

    def active_group(node, id):
        if "first" in node:
            return active_group(node["first"], id) or active_group(node["second"], id)
        return node if id in node["tabs"] else None

    state, boxes = run("welcome", frames=25)
    assert boxes["composer"]["y"] > 700, boxes["composer"]
    assert all(f"workspace-side-{mode}" in boxes for mode in ("chats", "files", "git"))
    passed("workspace starts with chat, three sidebar modes and a bottom composer")

    state, boxes = run("files", [event(80, "workspace-side-files", "workspace_side", 1)])
    rows = state["workspace_files"]
    src = next(r for r in rows if r["path"] == "src")
    assert src["directory"]
    state, boxes = run("expanded", [event(80, f'workspace-file-{src["index"]}', "workspace_file", src["index"])])
    source = next(r for r in state["workspace_files"] if r["path"] == "src/main.flex")
    state, boxes = run("editor", [event(80, f'workspace-file-{source["index"]}', "workspace_file", source["index"])])
    document = panel(state, "file", "src/main.flex")
    id = document["id"]
    assert document["text"].startswith("fn main") and boxes[f"workspace-editor-{id}"]["focused"]
    passed("file tree expands real project directories and opens a file buffer")

    state, boxes = run("indent", [event(80, f"workspace-tab-{id}", "workspace_tab", id),
        key(130, 4), text(170, "fn main(){"), key(220, 40, 0), text(270, "return 12;"), key(320, 43, 0)])
    assert panel(state, "file")["text"] == "fn main(){\n    return 12;    "
    passed("Enter retains code indentation and Tab inserts spaces in the editor")

    replacement = "fn main(){\n    return 73;\n}\n"
    state, boxes = run("save", [event(80, f"workspace-tab-{id}", "workspace_tab", id),
                                key(130, 4), text(170, replacement), key(230, 22)])
    assert (project / "src/main.flex").read_text() == replacement
    assert not panel(state, "file", "src/main.flex")["dirty"]
    passed("native editor input and Ctrl+S save the actual project file")

    state, boxes = run("undo", [event(80, f"workspace-tab-{id}", "workspace_tab", id),
                                key(140, 4), text(180, "temporary"), key(240, 29)])
    assert panel(state, "file", "src/main.flex")["text"] == replacement
    state, boxes = run("redo", [event(80, f"workspace-tab-{id}", "workspace_tab", id), key(140, 28)])
    assert panel(state, "file", "src/main.flex")["text"] == "temporary"
    passed("undo and redo preserve buffer history across restart")

    state, boxes = run("unsaved", [event(80, f"workspace-tab-{id}", "workspace_tab", id),
                                   key(130, 4), text(170, replacement),
                                   event(240, f"workspace-tab-close-{id}", "workspace_close", id)])
    # Replacement equals disk, so closing is safe. Reopen to create an unsaved edit.
    if not any(p["kind"] == "file" for p in state["workspace"]["panels"]):
        source = next(r for r in state["workspace_files"] if r["path"] == "src/main.flex")
        state, boxes = run("reopen", [event(80, f'workspace-file-{source["index"]}', "workspace_file", source["index"])])
        id = panel(state, "file")["id"]
    state, boxes = run("dirty-close", [event(80, f"workspace-tab-{id}", "workspace_tab", id),
                                       key(130, 4), text(170, "unsaved draft\n"),
                                       event(240, f"workspace-tab-close-{id}", "workspace_close", id)])
    assert state["workspace_close"] == id and "workspace-close-dialog" in boxes
    state, boxes = run("keep-editing")
    assert panel(state, "file")["text"] == "unsaved draft\n"
    passed("closing dirty files requires a choice and recovery preserves their contents")

    # Dock the live editor with native pointer events, then move chat below it.
    tab = boxes[f"workspace-tab-{id}"]
    group = active_group(state["workspace"]["root"], id)
    target = boxes[f'workspace-group-{group["id"]}']
    sx, sy = tab["x"] + 10, tab["y"] + 15
    tx, ty = target["x"] + target["width"] - 25, target["y"] + target["height"] // 2
    state, boxes = run("docked", [pointer(100, 1025, sx, sy), pointer(160, 1024, tx, ty), pointer(240, 1026, tx, ty)])
    assert state["workspace"]["root"]["axis"] == "row"
    assert boxes[f"workspace-editor-{id}"]["x"] > boxes["chat"]["x"]
    assert panel(state, "file")["text"] == "unsaved draft\n"
    passed("native tab dragging creates a side split and preserves the dirty file")

    divider = boxes[f'workspace-divider-{state["workspace"]["root"]["id"]}']
    x, y = divider["x"] + 2, divider["y"] + 100
    state, boxes = run("resize", [pointer(100, 1025, x, y), pointer(160, 1024, x - 100, y), pointer(220, 1026, x - 100, y)])
    assert state["workspace"]["root"]["ratio"] < 500
    passed("native divider dragging resizes the split and the ratio survives restart")

    state, boxes = run("terminal", [key(120, 13), text(350, "printf 'PTY_MARKER\\n'; pwd\n")], frames=110)
    terminal = panel(state, "terminal")
    tid = terminal["id"]
    assert "PTY_MARKER" in terminal["output"] and str(project) in terminal["output"].replace("\n", ""), terminal
    assert terminal["cols"] > 20 and terminal["rows"] >= 3
    passed("Ctrl+J opens a real PTY and native text executes in the project directory")

    # A job finishes while the panel is hidden, then its output is still there.
    state, boxes = run("terminal-hidden-job", [event(80, f"workspace-tab-{tid}", "workspace_tab", tid),
        text(200, "sleep 0.4; printf 'BACKGROUND_DONE\\n'\n"), key(280, 13), key(950, 13)], frames=110)
    assert "BACKGROUND_DONE" in panel(state, "terminal")["output"]
    passed("hiding and reopening the terminal keeps the shell and background job alive")

    state, boxes = run("terminal-control", [event(80, f"workspace-tab-{tid}", "workspace_tab", tid),
        text(200, "sleep 10\n"), key(350, 6), text(500, "printf '\\033[31mRED\\033[0m\\n'; stty size\n")], frames=110)
    terminal = panel(state, "terminal")
    assert "RED" in terminal["output"] and any(r.get("color") == "#e06c75" for r in terminal["runs"]), terminal
    assert not terminal["exited"]
    passed("Ctrl+C interrupts the foreground job and ANSI colour renders through the VT screen")

    state, boxes = run("git", [event(100, "workspace-side-git", "workspace_side", 2)])
    changed = next(r for r in state["workspace_changes"] if r["path"] == "notes.txt")
    state, boxes = run("diff", [event(100, f'workspace-change-{changed["index"]}', "workspace_diff", changed["index"])])
    assert "+changed on disk" in panel(state, "diff", "notes.txt")["text"]
    passed("Git sidebar reads actual status and opens a unified diff panel")

    # Open/save failures keep the current buffer and never overwrite newer disk contents.
    (project / "src/main.flex").write_text("external change\n")
    state, boxes = run("conflict", [event(80, f"workspace-tab-{id}", "workspace_tab", id), key(180, 22)])
    assert (project / "src/main.flex").read_text() == "external change\n"
    assert "changed on disk" in state["workspace_error"]
    assert panel(state, "file", "src/main.flex")["text"] == "unsaved draft\n"
    passed("saving detects external changes and keeps both the disk version and unsaved buffer")

    # Search selects an actual match in the native editor.
    state, boxes = run("find", [event(80, f"workspace-tab-{id}", "workspace_tab", id), key(140, 9),
        event(200, f"workspace-find-input-{id}", "workspace_find_query", id, "draft", "change"),
        event(260, f"workspace-find-next-{id}", "workspace_find_next", id)])
    selection = boxes[f"workspace-editor-{id}"]
    assert selection["anchor"] == 8 and selection["caret"] == 13, selection
    passed("Ctrl+F finds and selects a match in the file buffer")

    group = active_group(state["workspace"]["root"], id)
    state, boxes = run("move-menu", [event(80, f'workspace-panel-menu-{group["id"]}', "workspace_panel_menu", id),
        event(160, "workspace-move-left", "workspace_move", 1)])
    assert state["workspace"]["root"]["first"]["tabs"] == [id]
    assert panel(state, "file", "src/main.flex")["text"] == "unsaved draft\n"
    passed("keyboard-accessible move controls reposition an existing split without losing its buffer")

    state, boxes = run("narrow-files", [event(100, "workspace-toolbar-files", "workspace_side", 1)], width=560, height=700)
    assert "workspace-drawer-overlay" in boxes and "workspace-tree" in boxes
    state, boxes = run("narrow-git", [event(100, "workspace-toolbar-git", "workspace_side", 2)], width=560, height=700)
    assert "workspace-drawer-overlay" in boxes and "workspace-git" in boxes
    state, boxes = run("narrow-return", [key(80, 41, 0)], width=560, height=700)
    assert "workspace-group-0" in boxes and "workspace-drawer-overlay" not in boxes
    assert panel(state, "file", "src/main.flex")["text"] == "unsaved draft\n"
    passed("narrow windows retain every panel as tabs and expose Files/Git in a dismissible drawer")

    state, boxes = run("executable-files", [event(80, "workspace-side-files", "workspace_side", 1)])
    script = next(r for r in state["workspace_files"] if r["path"] == "run.sh")
    state, boxes = run("executable-editor", [event(80, f'workspace-file-{script["index"]}', "workspace_file", script["index"])])
    executable = panel(state, "file", "run.sh")["id"]
    updated = "#!/bin/sh\necho changed\n"
    state, boxes = run("save-close", [event(80, f"workspace-tab-{executable}", "workspace_tab", executable),
        key(140, 4), text(180, updated), event(240, f"workspace-tab-close-{executable}", "workspace_close", executable),
        event(310, "workspace-close-save", "workspace_close_save")])
    assert (project / "run.sh").read_text() == updated
    assert not any(p.get("path") == "run.sh" for p in state["workspace"]["panels"])
    passed("Save and close writes a dirty file and removes its tab after the save succeeds")

    assert (project / "run.sh").stat().st_mode & 0o777 == 0o755
    assert not list(project.glob(".collie-*"))
    passed("workspace operations leave unrelated files and project permissions intact")

(out / "workspace-report.json").write_text(json.dumps(dict(
    checks=checks, headless=True, physical_display=False, live_model=False,
    screenshots=["workspace-terminal.png", "workspace-narrow-files.png", "workspace-diff.png"]), indent=2) + "\n")
print(f"{len(checks)} workspace groups passed")
