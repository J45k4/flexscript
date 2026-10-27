#!/usr/bin/env python3
"""Compare live native dock transitions against a fresh declarative tree.

In particular, promote a surviving child out of a removed outer split. Every
native key must still belong to the new tree; obsolete containers must not cover
the chat, terminal, tabs or dividers after reparenting.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--out", type=Path, default=ROOT / "build/collie-desktop")
out = parser.parse_args().out.resolve()
checks = []


def event(at, key, action, id=0):
    return dict(at=at, request=dict(action="event", event=dict(
        key=key, action=action, action_id=id, type="click")))


def owner(node, panel):
    if "first" in node:
        return owner(node["first"], panel) or owner(node["second"], panel)
    return node if panel in node["tabs"] else None


with tempfile.TemporaryDirectory(prefix="docking-", dir=out) as directory:
    work = Path(directory)
    data = work / "data"
    session = data / "sessions/docking"
    (session / "files").mkdir(parents=True)
    (session / "session.json").write_text(json.dumps(dict(
        navigation=dict(page="chat", sidebar_collapsed=1))))
    (data / "settings.json").write_text(json.dumps(dict(current="docking")))
    fixture = work / "fixture.json"
    fixture.write_text("[]")
    native = work / "input.so"
    subprocess.run(["cc", "-shared", "-fPIC", "-O2", str(ROOT / "tests/ui/desktop-events.c"),
                    "-o", str(native), "-ldl"], check=True)
    env = dict(os.environ, SDL_VIDEODRIVER="dummy", COLLIE_HEADLESS="1", SHELL="/bin/sh", ENV="/dev/null")
    env.pop("DISPLAY", None)
    env.pop("WAYLAND_DISPLAY", None)

    def pointer(at, kind, x, y):
        return dict(at=at, request=dict(action="native_mouse", fixture=str(native),
                                       kind=kind, a=1 if kind != 1024 else x,
                                       b=x if kind != 1024 else y, c=y if kind != 1024 else 0, d=0))

    def run(name, events=(), width=1330, height=1880, frames=55):
        script = work / "events.json"
        script.write_text(json.dumps(events))
        state_path = out / f"docking-{name}-state.json"
        layout_path = out / f"docking-{name}-layout.json"
        capture = out / f"docking-{name}.rgba"
        result = subprocess.run([str(out / "collie"), "--hidden", "--frames", str(frames), "--width", str(width),
            "--height", str(height), "--fixture", str(fixture), "--data", str(data), "--events", str(script),
            "--dump-state", str(state_path), "--dump-layout", str(layout_path), "--capture", str(capture)],
            env=env, capture_output=True, timeout=15)
        assert result.returncode == 0, (name, result.returncode, result.stderr.decode())
        state = json.loads(state_path.read_text())
        boxes = {box["key"]: box for box in json.loads(layout_path.read_text())}
        fresh = subprocess.run([str(out / "ui-host")], input=json.dumps(dict(
            state=state, action="update", reset=True)).encode(), capture_output=True, check=True, timeout=10)
        expected = {}

        def tree(node, hidden=False):
            hidden = hidden or node.get("hidden", False)
            if not hidden:
                expected[node["key"]] = node
            for child in node.get("children", []):
                tree(child, hidden)

        for op in json.loads(fresh.stdout)["ops"]:
            assert op["op"] == "insert", op
            tree(op["node"])
        extra = boxes.keys() - expected.keys()
        missing = expected.keys() - boxes.keys()
        assert not extra and not missing, (name, "obsolete native widgets", sorted(extra), "missing widgets", sorted(missing))
        main = boxes["desktop-main"]
        for key, box in boxes.items():
            if key.startswith("workspace-group-") and key.removeprefix("workspace-group-").isdigit():
                assert box["x"] >= main["x"] and box["y"] >= 28, (name, box)
                assert box["x"] + box["width"] <= main["x"] + main["width"], (name, box)
                assert box["y"] + box["height"] <= main["height"], (name, box)
        try:
            from PIL import Image
            Image.frombytes("RGBA", (state["viewport_width"], state["viewport_height"]), capture.read_bytes()).save(
                out / f"docking-{name}.png")
        except ImportError:
            pass
        checks.append(name)
        print("PASS", name, "matches a fresh tree without obsolete panels", flush=True)
        return state, boxes

    state, boxes = run("bottom", [dict(at=100, request=dict(action="native_key", code=13, modifiers=64))])
    assert state["workspace"]["root"]["axis"] == "column"

    def drag(name, panel, target, edge):
        tab = boxes[f"workspace-tab-{panel}"]
        group = owner(state["workspace"]["root"], target)
        box = boxes[f'workspace-group-{group["id"]}']
        sx, sy = tab["x"] + 10, tab["y"] + 15
        tx, ty = box["x"] + box["width"] // 2, box["y"] + box["height"] // 2
        if edge == "left":
            tx = box["x"] + 20
        elif edge == "right":
            tx = box["x"] + box["width"] - 20
        elif edge == "above":
            ty = box["y"] + 45
        elif edge == "below":
            ty = box["y"] + box["height"] - 20
        elif edge == "join":
            ty = box["y"] + 15
        events = [pointer(160, 1025, sx, sy), pointer(230, 1024, tx, ty), pointer(300, 1026, tx, ty)]
        if name == "bottom-to-right":
            events = [pointer(400, 1025, sx, sy), pointer(470, 1024, tx, ty), pointer(540, 1026, tx, ty)]
            events.insert(0, dict(at=300, request=dict(action="native_text", fixture=str(native),
                                                   text="echo $$; sleep .3; echo ALIVE\n")))
            events.append(dict(at=800, request=dict(action="native_text", fixture=str(native), text="echo $$\n")))
        return run(name, events, frames=85 if name == "bottom-to-right" else 55)

    state, boxes = drag("bottom-to-right", 3, 1, "right")
    assert state["workspace"]["root"]["axis"] == "row"
    assert boxes["workspace-terminal-3"]["x"] > boxes["chat"]["x"]
    assert boxes["workspace-terminal-3"]["y"] == boxes["chat"]["y"] == 62
    terminal = next(p for p in state["workspace"]["panels"] if p["id"] == 3)
    pids = re.findall(r"^([0-9]+)$", terminal["output"], re.MULTILINE)
    assert len(pids) == 2 and pids[0] == pids[1] and "\nALIVE\n" in terminal["output"], terminal
    state, boxes = drag("right-to-below", 3, 1, "below")
    state, boxes = drag("below-to-left", 3, 1, "left")
    state, boxes = drag("left-to-above", 3, 1, "above")
    state, boxes = drag("above-to-joined", 3, 1, "join")
    assert "first" not in state["workspace"]["root"]
    assert set(state["workspace"]["root"]["tabs"]) == {1, 3}
    state, boxes = drag("chat-out-of-terminal-group", 1, 3, "right")
    state, boxes = drag("chat-joined-back", 1, 3, "join")
    state, boxes = run("terminal-active", [event(100, "workspace-tab-3", "workspace_tab", 3)])
    state, boxes = run("second-terminal", [event(100, "workspace-terminal-new-3", "workspace_terminal_new")])
    terminal = next(p["id"] for p in state["workspace"]["panels"] if p["kind"] == "terminal" and p["id"] != 3)
    state, boxes = drag("second-terminal-right", terminal, 3, "right")
    state, boxes = drag("chat-below-nested-terminals", 1, terminal, "below")
    active = state["workspace"]["focused"]
    group = owner(state["workspace"]["root"], active)
    state, boxes = run("reset-after-repeated-docking", [
        event(100, f'workspace-panel-menu-{group["id"]}', "workspace_panel_menu", active),
        event(180, "workspace-reset", "workspace_reset")])
    assert "first" not in state["workspace"]["root"]
    state, boxes = run("restart-after-reset")

(out / "docking-report.json").write_text(json.dumps(dict(checks=checks, headless=True), indent=2) + "\n")
print(len(checks), "native docking transitions passed")
