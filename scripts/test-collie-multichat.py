#!/usr/bin/env python3
"""Real host concurrency, independent chat UI, docking and nested resizing."""
import argparse
import json
import os
import re
from pathlib import Path
import select
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--out", type=Path, default=ROOT / "build/collie-desktop")
parser.add_argument("--wayland-session", type=Path, help="JSON environment for a private headless Wayland compositor")
args = parser.parse_args()
out = args.out.resolve()
checks = []
env = dict(os.environ, SDL_VIDEODRIVER="dummy", COLLIE_HEADLESS="1", SHELL="/bin/sh", ENV="/dev/null")
env.pop("DISPLAY", None)
env.pop("WAYLAND_DISPLAY", None)
if args.wayland_session:
    import stat
    session = json.loads(args.wayland_session.read_text())
    runtime = Path(session["XDG_RUNTIME_DIR"])
    assert runtime.stat().st_uid == os.getuid() and stat.S_IMODE(runtime.stat().st_mode) == 0o700
    assert "/" not in session["WAYLAND_DISPLAY"] and stat.S_ISSOCK((runtime/session["WAYLAND_DISPLAY"]).stat().st_mode)
    env.update(session, FLEX_GUI_BACKEND="wayland")
    env.pop("SDL_VIDEODRIVER", None)
    env.pop("SDL_VIDEO_DRIVER", None)



def passed(label):
    checks.append(label)
    print("PASS", label, flush=True)


def completed(text):
    return dict(type="response.completed", response=dict(status="completed", output=[dict(
        type="message", role="assistant", content=[dict(type="output_text", text=text)])]))


def reply(label, delay):
    return [dict(events=[dict(type="response.output_text.delta", delta=label + " reply"),
        *[dict(type="response.created") for _ in range(delay)], completed(label + " reply")])]


def seed(data):
    for name in ("alpha", "beta", "gamma"):
        path = data / "sessions" / name
        (path / "files").mkdir(parents=True)
        (path / "session.json").write_text(json.dumps(dict(
            messages=[dict(role="user", content=name + " original")],
            cards=[dict(kind="user", text=name + " original")], navigation=dict(page="chat", draft=name + " draft"))))
    (data / "settings.json").write_text(json.dumps(dict(current="alpha")))


class Host:
    def __init__(self, data, fixture):
        self.views = {}
        self.notices = []
        self.buffer = b""
        self.errors = b""
        self.proc = subprocess.Popen([str(out / "service-native"), "--multi-chat", "--data", str(data),
            "--fixture", str(fixture)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
        self.wait(lambda: any(v.get("total") for v in self.views.values()))

    def poll(self):
        for channel in select.select([self.proc.stdout, self.proc.stderr], [], [], .025)[0]:
            raw = os.read(channel.fileno(), 65536)
            if channel == self.proc.stderr:
                self.errors += raw
                continue
            self.buffer += raw
            while b"\n" in self.buffer:
                line, self.buffer = self.buffer.split(b"\n", 1)
                packet = json.loads(line)
                sid = packet.get("chat_session")
                assert sid, packet
                view = self.views.setdefault(sid, {})
                action = packet["action"]
                if action == "clear":
                    view["cards"] = []
                elif action in ("update", "restore"):
                    view.update(packet["data"])
                elif action == "append":
                    view.setdefault("cards", []).extend(packet["append_cards"])
                elif action == "notice":
                    self.notices.append((sid, packet["text"]))

    def wait(self, predicate, timeout=15):
        end = time.monotonic() + timeout
        while not predicate():
            self.poll()
            assert self.proc.poll() is None, (self.proc.returncode, self.errors.decode(), self.notices)
            assert time.monotonic() < end, (self.views, self.notices, self.errors.decode())

    def send(self, kind, **data):
        self.proc.stdin.write(json.dumps(dict(kind=kind, **data)).encode() + b"\n")
        self.proc.stdin.flush()

    def close(self):
        self.proc.stdin.close()
        end = time.monotonic() + 5
        while self.proc.poll() is None and time.monotonic() < end:
            self.poll()
        if self.proc.poll() is None:
            self.proc.kill()
            raise AssertionError("multi-chat host did not shut down")
        assert self.proc.returncode == 0, self.errors.decode()


with tempfile.TemporaryDirectory(prefix="multichat-", dir=out) as directory:
    work = Path(directory)
    host_data = work / "host"
    seed(host_data)
    fixture = work / "host-fixture.json"
    fixture.write_text(json.dumps(dict(chats=dict(alpha=reply("Alpha", 55), beta=reply("Beta", 55)))))
    host = Host(host_data, fixture)
    try:
        host.send("chat_open", id="beta", chat_panel=3)
        host.wait(lambda: host.views.get("beta", {}).get("total"))
        host.send("save_model", chat_session="alpha", model="gpt-6-astra")
        host.wait(lambda: host.views["alpha"].get("model") == "gpt-6-astra")
        assert host.views["beta"]["model"] == "gpt-6.1-sol"
        host.send("submit", chat_session="alpha", text="Alpha task")
        host.send("submit", chat_session="beta", text="Beta task")
        host.wait(lambda: host.views["alpha"].get("busy") and host.views["beta"].get("busy"))
        host.wait(lambda: host.views["alpha"].get("stream") == "Alpha reply" and host.views["beta"].get("stream") == "Beta reply")
        passed("two host conversations run and stream concurrently with independent session tags")
        host.send("cancel", chat_session="alpha")
        host.wait(lambda: not host.views["alpha"].get("busy"))
        assert host.views["beta"].get("busy")
        host.wait(lambda: not host.views["beta"].get("busy"))
        assert any(c.get("text") == "Beta reply" for c in host.views["beta"]["cards"])
        assert not any(c.get("text") == "Beta task" for c in host.views["alpha"]["cards"])
        passed("cancelling Alpha leaves Beta running and saves messages to their own conversations")
        host.send("navigation", data=dict(active_session="beta", draft="Beta kept", page="chat", chat_navigation=[
            dict(session_id="alpha", navigation=dict(page="chat", draft="Alpha kept")),
            dict(session_id="beta", navigation=dict(page="chat", draft="Beta kept"))]))
    finally:
        host.close()
    for sid, draft in (("alpha", "Alpha kept"), ("beta", "Beta kept")):
        saved = json.loads((host_data / "sessions" / sid / "session.json").read_text())
        assert saved["navigation"]["draft"] == draft, saved["navigation"]
    passed("per-chat drafts and completed/cancelled sessions are durable on host shutdown")

    data = work / "ui"
    seed(data)
    fixture = work / "ui-fixture.json"
    fixture.write_text(json.dumps(dict(chats=dict(alpha=reply("Alpha", 25)+reply("Alpha again", 45), beta=reply("Beta", 25)), main=reply("New", 0))))
    native = work / "input.so"
    subprocess.run(["cc", "-shared", "-fPIC", "-O2", str(ROOT / "tests/ui/desktop-events.c"), "-o", str(native), "-ldl"], check=True)

    def event(at, key, action, id=0, value=None, type="click"):
        return dict(at=at, request=dict(action="event", event=dict(key=key, action=action, action_id=id, value=value, type=type)))

    def pointer(at, kind, x, y):
        return dict(at=at, request=dict(action="native_mouse", fixture=str(native), kind=kind,
            a=1 if kind != 1024 else x, b=x if kind != 1024 else y, c=y if kind != 1024 else 0, d=0))

    def key(id, suffix):
        return suffix if id == 1 else f"chat-panel-{id}::{suffix}"

    def run(name, events=(), frames=70):
        script = work / "events.json"
        script.write_text(json.dumps(events))
        state_path = out / f"multichat-{name}-state.json"
        layout_path = out / f"multichat-{name}-layout.json"
        capture = out / f"multichat-{name}.rgba"
        window_path = out / f"multichat-{name}-window.json"
        result = subprocess.run([str(out / "collie"), "--hidden", "--frames", str(frames), "--width", "1600", "--height", "1000",
            "--data", str(data), "--fixture", str(fixture), "--events", str(script), "--dump-state", str(state_path),
            "--dump-layout", str(layout_path), "--dump-window", str(window_path), "--capture", str(capture)], env=env, capture_output=True, timeout=30)
        assert result.returncode == 0, (name, result.returncode, result.stderr.decode())
        if args.wayland_session:
            window = json.loads(window_path.read_text())
            assert window["backend"] == "wayland" and window["sdl_loaded"] is False, window
        state = json.loads(state_path.read_text())
        boxes = {r["key"]: r for r in json.loads(layout_path.read_text())}
        fresh = subprocess.run([str(out / "ui-host")], input=json.dumps(dict(
            state=state, action="update", reset=True)).encode(), capture_output=True, check=True, timeout=10)
        expected = set()
        def visit(node, hidden=False):
            hidden = hidden or node.get("hidden", False)
            if not hidden:
                expected.add(node["key"])
            for child in node.get("children", []):
                visit(child, hidden)
        for op in json.loads(fresh.stdout)["ops"]:
            visit(op["node"])
        assert boxes.keys() == expected, (name, "stale widgets", sorted(boxes.keys()-expected), "missing", sorted(expected-boxes.keys()))
        from PIL import Image
        Image.frombytes("RGBA", (1600, 1000), capture.read_bytes()).save(out / f"multichat-{name}.png")
        return state, boxes

    def panel(state, sid):
        return next(p for p in state["workspace"]["panels"] if p["kind"] == "chat" and p.get("session_id") == sid)

    def owner(node, id):
        if "first" in node:
            return owner(node["first"], id) or owner(node["second"], id)
        return node if id in node["tabs"] else None

    state, boxes = run("open-beta", [event(250, "desktop-session-beta", "desktop_open_session")])
    alpha, beta = panel(state, "alpha"), panel(state, "beta")
    aid, bid = alpha["id"], beta["id"]
    assert alpha["chat"]["draft"] == "alpha draft" and beta["chat"]["draft"] == "beta draft", (alpha, beta)
    passed("opening a saved chat creates a second panel and restores both independent drafts")

    tab = boxes[f"workspace-tab-{bid}"]
    group = owner(state["workspace"]["root"], aid)
    box = boxes[f'workspace-group-{group["id"]}']
    sx, sy = tab["x"] + 15, tab["y"] + 15
    tx, ty = box["x"] + box["width"] - 20, box["y"] + box["height"] // 2
    state, boxes = run("side-by-side", [pointer(200, 1025, sx, sy), pointer(280, 1024, tx, ty), pointer(360, 1026, tx, ty)])
    assert boxes[key(bid, "composer-draft")]["x"] > boxes[key(aid, "composer-draft")]["x"]
    assert key(aid, "card-0-user") in boxes and key(bid, "card-0-user") in boxes
    passed("two real chat views render side by side with independent message and composer widget keys")

    def type_in(at, id, text):
        b = boxes[key(id, "composer-draft")]
        x, y = b["x"] + 30, b["y"] + b["height"] // 2
        return [pointer(at, 1025, x, y), pointer(at+40, 1026, x, y),
            dict(at=at+80, request=dict(action="native_key", code=4, modifiers=64)),
            dict(at=at+120, request=dict(action="native_text", fixture=str(native), text=text))]
    state, boxes = run("drafts", type_in(600, aid, "Alpha edited") + type_in(900, bid, "Beta edited"), frames=110)
    assert panel(state, "alpha")["chat"]["draft"] == "Alpha edited"
    assert panel(state, "beta")["chat"]["draft"] == "Beta edited"
    state, boxes = run("drafts-restart")
    assert panel(state, "alpha")["chat"]["draft"] == "Alpha edited"
    assert panel(state, "beta")["chat"]["draft"] == "Beta edited"
    passed("editing either composer preserves the other draft and both survive restart")

    divider = boxes[f'workspace-divider-{state["workspace"]["root"]["id"]}']
    x, y = divider["x"] - 3, divider["y"] + 150
    state, boxes = run("resize-side-by-side", [pointer(200, 1025, x, y), pointer(280, 1024, x - 130, y), pointer(360, 1026, x - 130, y)])
    assert state["workspace"]["root"]["ratio"] < 500
    passed("chat splits resize using the enlarged grab area beside the visible divider")

    state, boxes = run("stream-and-open-gamma", [event(200, key(aid, "composer-send"), "send"),
        event(300, key(bid, "composer-send"), "send"), event(450, "desktop-session-gamma", "desktop_open_session"), event(470, "desktop-session-beta", "desktop_open_session")], frames=230)
    alpha, beta, gamma = panel(state, "alpha"), panel(state, "beta"), panel(state, "gamma")
    assert any(c.get("text") == "Alpha reply" for c in alpha["chat"]["cards"]), alpha
    assert any(c.get("text") == "Beta reply" for c in beta["chat"]["cards"]), beta
    assert not any(c.get("text") == "Beta reply" for c in alpha["chat"]["cards"])
    assert gamma["chat"]["draft"] == "gamma draft"
    assert state["chat_active"] == bid, "a delayed open stole focus from the latest chat selection"
    passed("both panels send independently while another chat opens; responses stay in their original panels")

    gid = gamma["id"]
    group = owner(state["workspace"]["root"], bid)
    state, boxes = run("reopen-beta", [event(200, "desktop-session-beta", "desktop_open_session")])
    assert sum(p["kind"] == "chat" for p in state["workspace"]["panels"]) == 3
    state, boxes = run("close-gamma", [event(200, f"workspace-tab-close-{gid}", "workspace_close", gid)])
    assert not any(p.get("session_id") == "gamma" for p in state["workspace"]["panels"])
    assert any(c.get("text") == "Beta reply" for c in panel(state, "beta")["chat"]["cards"])
    passed("opening an existing panel focuses it and closing another chat keeps the remaining conversation intact")

    fixture.write_text(json.dumps(dict(chats=dict(alpha=reply("Alpha again", 45), beta=reply("Beta", 25)), main=reply("New", 0))))
    state, boxes = run("close-running-alpha", [event(200, key(aid, "composer-draft"), "draft", value="Alpha background", type="change"),
        event(280, key(aid, "composer-send"), "send"), event(450, f"workspace-tab-close-{aid}", "workspace_close", aid)], frames=220)
    assert not any(p.get("session_id") == "alpha" for p in state["workspace"]["panels"])
    assert not any(c.get("text") == "Alpha again reply" for c in panel(state, "beta")["chat"]["cards"])
    state, boxes = run("reopen-completed-alpha", [event(200, "desktop-session-alpha", "desktop_open_session")])
    assert any(c.get("text") == "Alpha again reply" for c in panel(state, "alpha")["chat"]["cards"])
    passed("closing a running chat keeps its response in the background and reopening restores its completed result")

    # Add a horizontal split inside the existing side-by-side arrangement.
    aid = panel(state, "alpha")["id"]
    tab = boxes[f"workspace-tab-{aid}"]
    target = owner(state["workspace"]["root"], bid)
    b = boxes[f'workspace-group-{target["id"]}']
    sx, sy = tab["x"] + 15, tab["y"] + 15
    tx, ty = b["x"] + b["width"] // 2, b["y"] + b["height"] - 20
    state, boxes = run("chat-below", [pointer(200, 1025, sx, sy), pointer(280, 1024, tx, ty), pointer(360, 1026, tx, ty)])
    split = state["workspace"]["root"]
    assert split["axis"] == "column", split
    divider = boxes[f'workspace-divider-{split["id"]}']
    x, y = divider["x"] + divider["width"] // 2, divider["y"] - 3
    state, boxes = run("resize-horizontal", [pointer(200, 1025, x, y), pointer(280, 1024, x, y - 100), pointer(360, 1026, x, y - 100),
        dict(at=450, request=dict(action="native_key", code=82, modifiers=0))])
    assert state["workspace"]["root"]["ratio"] < 450
    resized_ratio = state["workspace"]["root"]["ratio"]
    state, boxes = run("resize-restart")
    assert state["workspace"]["root"]["ratio"] == resized_ratio
    passed("horizontal dividers resize with mouse and arrow keys and preserve their ratio across restart")

    state, boxes = run("new-chat", [dict(at=200, request=dict(action="native_key", code=17, modifiers=64))])
    assert sum(p["kind"] == "chat" for p in state["workspace"]["panels"]) == 3
    assert panel(state, "alpha")["chat"]["cards"] and panel(state, "beta")["chat"]["cards"]
    fresh = next(p for p in state["workspace"]["panels"] if p["kind"] == "chat" and p.get("session_id") not in ("alpha", "beta"))
    assert fresh.get("session_id") and fresh["chat"]["total"] > 0 and not fresh["chat"]["cards"]
    passed("Ctrl+N opens a fresh chat panel while retaining the already open chats")
    fid = fresh["id"]
    tab = boxes[f"workspace-tab-{fid}"]
    target = owner(state["workspace"]["root"], bid)
    b = boxes[f'workspace-group-{target["id"]}']
    sx, sy = tab["x"] + 15, tab["y"] + 15
    tx, ty = b["x"] + b["width"] - 20, b["y"] + b["height"] // 2
    state, boxes = run("nested-chat-split", [pointer(200, 1025, sx, sy), pointer(280, 1024, tx, ty), pointer(360, 1026, tx, ty)])
    outer = state["workspace"]["root"]
    nested = outer["first"]
    assert outer["axis"] == "column" and nested["axis"] == "row", outer
    divider = boxes[f'workspace-divider-{nested["id"]}']
    x, y = divider["x"] + 3, divider["y"] + 70
    state, boxes = run("resize-nested", [pointer(200, 1025, x, y), pointer(280, 1024, x + 100, y), pointer(360, 1026, x + 100, y)])
    assert state["workspace"]["root"]["ratio"] == outer["ratio"]
    assert state["workspace"]["root"]["first"]["ratio"] > nested["ratio"]
    passed("resizing a nested split changes only that split and leaves no stale native panels")

    state, boxes = run("chat-terminal", [event(400, f"workspace-tab-{aid}", "workspace_tab", aid),
        dict(at=550, request=dict(action="native_key", code=13, modifiers=64))], frames=100)
    terminal = next(p for p in state["workspace"]["panels"] if p["kind"] == "terminal")
    tid = terminal["id"]
    assert terminal["project_path"] == str(data / "sessions/alpha/files")
    b = boxes[f"workspace-terminal-screen-{tid}"]
    x, y = b["x"] + 20, b["y"] + 20
    state, boxes = run("chat-terminal-origin", [pointer(400, 1025, x, y), pointer(440, 1026, x, y),
        dict(at=500, request=dict(action="native_text", fixture=str(native), text="echo PID:$$:BEFORE\n")),
        event(850, "desktop-session-beta", "desktop_open_session"),
        pointer(1100, 1025, x, y), pointer(1140, 1026, x, y),
        dict(at=1200, request=dict(action="native_text", fixture=str(native), text="echo PID:$$:AFTER; pwd\n"))], frames=160)
    terminal = next(p for p in state["workspace"]["panels"] if p["id"] == tid)
    pids = re.findall(r"PID:(\d+):(BEFORE|AFTER)", terminal["output"])
    assert len(pids) == 2 and pids[0][0] == pids[1][0], terminal["output"]
    assert terminal["cwd"] == str(data / "sessions/alpha/files") and not terminal["exited"]
    passed("switching chats preserves the terminal's original directory and running shell PID")

(out / "multichat-report.json").write_text(json.dumps(dict(checks=checks, headless=True, backend="wayland" if args.wayland_session else "sdl2", live_model=False), indent=2) + "\n")
print(len(checks), "multi-chat groups passed")
