#!/usr/bin/env python3
"""Linux lifecycle/TLS/dialog host. Conversation and UI policy live in Flexscript."""
import argparse
import asyncio
import contextlib
import fcntl
import json
import os
from pathlib import Path
import re
import shutil
import sys
import threading
import time
import urllib.error
import urllib.request
import urllib.parse
import webbrowser
import uuid

from engine import Engine, LIMIT
from linux_platform import Platform, atomic
from projects import Projects
from imagegen import ImageGenerators
from account import account_details
from accounts import Accounts, login_key
from login import CodexLogin, login_url


class Cancelled(Exception):
    pass


class Task:
    def __init__(self, id):
        self.id = id
        self.cancel = threading.Event()
        self.connection = None

    def stop(self):
        self.cancel.set()
        if self.connection is not None:
            # Closing a socket interrupts a pending read without waiting on the
            # buffered response's lock in the UI/event-loop thread.
            with contextlib.suppress(Exception):
                connection = self.connection
                sock = getattr(connection, 'sock', None)
                if sock is None:sock=connection.fp.raw._sock
                sock.shutdown(2)

    def check(self):
        if self.cancel.is_set():
            raise Cancelled('Cancelled.')


class Desktop:
    def __init__(self, engine, data, auth=None, fixture=None, emit=None):
        self.data = Path(data).resolve()
        self.data.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.lease = (self.data/'desktop.lock').open('a')
        try:
            fcntl.flock(self.lease, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError('This Collie data folder is already open')
        self.platform = Platform()
        self.engine = Engine(engine, self.platform)
        self.auth_file = Path(auth).expanduser() if auth else Path(os.environ.get('CODEX_HOME', str(Path.home()/'.codex')))/'auth.json'
        self.fixture = json.loads(Path(fixture).read_text()) if fixture else None
        self.account_metadata_enabled = self.fixture is None or auth is not None
        self.sink = emit or (lambda packet: print(json.dumps(packet, separators=(',', ':')), flush=True))
        self.session_request = 0
        self.settings = self.read(self.data/'settings.json', {})
        if auth is None and self.settings.get('auth_file'):
            self.auth_file=Path(self.settings['auth_file'])
        self.accounts=Accounts(self.data)
        if self.account_metadata_enabled:
            if auth is not None:
                selected=self.read(self.auth_file,{})
                self.accounts.add(selected,self.auth_file,activate=True)
            elif not self.accounts.entries:
                try:
                    selected=self.read(self.auth_file,{})
                    login_key(selected)
                    self.accounts.add(selected,self.auth_file,activate=True)
                except (OSError,ValueError,RecursionError):pass
            if self.accounts.active:
                self.auth_file=self.accounts.path()
                self.settings.pop('auth_file',None)
        self.projects = Projects(self.data)
        self.images = ImageGenerators()
        self.project_id = ''
        self.model = self.settings.get('model', 'gpt-6.1-sol')
        self.root = None
        self.state = {}
        self.permissions = {}
        self.permission_entries = []
        self.attachments = []
        self.navigation = {}
        self.last_activity = 0
        self.session_entries = []
        self.session_summaries = {}
        self.saved_session = None
        self.saved_settings = None
        self.tasks = {}
        self.workers = {}
        self.prompts = []
        self.sequence = 0
        self.closed = False
        self.closing = False
        self.switching = False
        self.operation_lock = asyncio.Lock()
        self.scheduler_lock = asyncio.Lock()
        self.worker_wake = asyncio.Event()
        self.last_worker_rows = None
        self.background = set()
        self.login = None
        self.login_task = None
        self.login_view = {}

    @staticmethod
    def read(path, fallback):
        try:
            if path.stat().st_size > LIMIT:
                raise ValueError('Saved state exceeds 8 MiB')
            return json.loads(path.read_text())
        except FileNotFoundError:
            return fallback

    def spawn(self, awaitable):
        task = asyncio.create_task(awaitable)
        self.background.add(task)
        task.add_done_callback(self.background.discard)
        task.add_done_callback(lambda t: self.notice(str(t.exception())) if not t.cancelled() and t.exception() else None)
        return task
        return task

    def emit(self, packet):
        if self.session_request:
            packet = dict(packet, session_request=self.session_request)
        self.sink(packet)

    def update(self, **data):
        if not self.closed:
            self.emit({'action': 'update', 'data': data})

    def notice(self, text):
        if not self.closed:
            self.emit({'action': 'notice', 'text': text})

    def save(self):
        data = dict(self.state, permissions=self.permissions, pending_attachments=self.attachments,
                    navigation=self.navigation, model=self.model, last_activity=self.last_activity, project_id=self.project_id)
        encoded = json.dumps(data, separators=(',', ':')).encode()
        if len(encoded) > LIMIT:
            raise ValueError('Conversation exceeds 8 MiB. Start a new conversation.')
        path = self.root/'session.json'
        # Navigation and session recovery can save the same state repeatedly.
        # Keep durability for changed data without repeating fsync for a no-op.
        if self.saved_session != (path, encoded):
            atomic(path, encoded)
            self.saved_session = (path, encoded)
        settings = json.dumps(dict(self.settings, current=self.root.name, model=self.model)).encode()
        if self.saved_settings != settings:
            atomic(self.data/'settings.json', settings)
            self.saved_settings = settings

    def set_permission(self, key, value):
        prior = self.permissions[key]
        self.permissions[key] = value
        try:
            self.save()
        except Exception:
            self.permissions[key] = prior
            self.update(policy=self.permissions)
            raise

    def config(self, id=0):
        return {'workspace_file': str(self.root/'agent.flexdb'), 'model': self.model,
                'permissions': self.permissions, 'agent_id': id,
                'files_directory': str(self.files_directory()), 'project_name': self.project_name()}

    def project_name(self):
        project = self.projects.get(self.project_id)
        return project['name'] if project else 'Personal chats'

    def files_directory(self):
        project = self.projects.get(self.project_id)
        return Path(project['path']) if project else self.root/'files'

    def workspace_path(self, relative):
        base = self.files_directory()
        if base.resolve(strict=True) != base or not base.is_dir():
            raise ValueError('Project folder is unavailable')
        path = (base/relative).resolve()
        if Path(relative).is_absolute() or not path.is_relative_to(base):
            raise ValueError('File is outside the project folder')
        return path

    async def call(self, op, agent=0, cancel=None, **request):
        return await self.engine.call(op, dict(request, config=self.config(agent)), self.root, cancel)

    def authenticated(self):
        if self.fixture is not None:
            return True
        try:
            auth = self.read_auth()
            tokens = auth.get('tokens') if isinstance(auth,dict) else None
            return isinstance(tokens,dict) and auth.get('auth_mode') == 'chatgpt' and isinstance(tokens.get('access_token'),str) and bool(tokens['access_token'])
        except (ValueError, OSError, RecursionError):
            return False

    def account(self):
        # Fixture runs must not copy the host user's identity into test output.
        if not self.account_metadata_enabled:return {}
        try:return account_details(self.read_auth())
        except (ValueError, OSError, RecursionError):return {}

    def refresh_account(self):
        if self.account_metadata_enabled:self.accounts.refresh()
        self.update(authenticated=self.authenticated(), account=self.account(), accounts=self.account_rows(), account_busy=bool(self.tasks), account_login=self.login_view)

    def read_auth(self):
        self.ensure_accounts()
        if self.account_metadata_enabled and self.accounts.active:
            self.accounts.refresh(self.accounts.active)
            self.auth_file=self.accounts.path()
            return self.accounts.auth()
        return self.read(self.auth_file,{})

    def ensure_accounts(self):
        if self.account_metadata_enabled and not self.accounts.entries:
            try:
                auth=self.read(self.auth_file,{})
                login_key(auth)
            except (OSError,ValueError,RecursionError):return
            self.accounts.add(auth,self.auth_file,activate=True)
            self.auth_file=self.accounts.path()

    def account_rows(self):
        return self.accounts.details() if self.account_metadata_enabled else []

    def account_idle(self,allow_login=False):
        if self.tasks:raise ValueError('Stop active replies and workers before adding or switching accounts')
        if not allow_login and self.login_view.get('running'):
            raise ValueError('Finish or cancel sign-in before switching accounts')

    async def open_login_browser(self):
        if not self.login_view.get('running') or not self.login_view.get('url'):
            raise ValueError('No sign-in page is available')
        url=login_url(self.login_view['url'])
        if os.environ.get('COLLIE_HEADLESS')=='1':return False
        return await asyncio.to_thread(webbrowser.open,url,new=2)

    async def start_login(self,method):
        self.account_idle(allow_login=True)
        await self.cancel_login(emit=False)
        attempt=CodexLogin(self.data/'account-logins'/uuid.uuid4().hex)
        self.login=attempt;self.login_view=dict(running=True,status='starting',method=method,message='Starting secure Codex sign-in…')
        self.update(account_login=self.login_view)
        self.login_task=self.spawn(self.run_login(attempt,method))

    async def cancel_login(self,emit=True):
        task=self.login_task
        if task is not None and task is not asyncio.current_task():
            if not task.done() and self.login_view.get('running'):task.cancel()
            await asyncio.gather(task,return_exceptions=True)
            if self.login_task is task:
                if self.login:await self.login.close()
                self.login=None;self.login_task=None
        if emit:
            self.login_view=dict(running=False,status='cancelled',message='Sign-in cancelled.')
            self.update(account_login=self.login_view)

    async def run_login(self,attempt,method):
        committed=False
        try:
            instructions=await attempt.start(method)
            self.login_view=dict(instructions,running=True,status='waiting',message='Complete sign-in in your browser. Your current account stays selected.')
            self.update(account_login=self.login_view)
            opened=await self.open_login_browser()
            if not opened:
                self.login_view=dict(self.login_view,message='Open the sign-in page below to continue. Your current account stays selected.')
                self.update(account_login=self.login_view)
            path=await attempt.wait();auth=self.read(path,{})
            await self.call(8,action='authenticate',auth=auth)
            key=login_key(auth)
            old=next((row.get('source') for row in self.accounts.entries if row['key']==key),None)
            previous=self.accounts.active
            saved=self.accounts.add(auth,path)
            committed=True;self.account_metadata_enabled=True;self.auth_file=self.accounts.path()
            self.settings.pop('auth_file',None);self.save()
            message='Account added. Choose Use account to change the selected login.'
            if not previous:message='Signed in. This account is now selected.'
            elif saved['id']==previous:message='Login updated for the selected account.'
            self.login_view=dict(running=False,status='completed',message=message)
            self.refresh_account()
            if old and old!=str(path) and Path(old).parent.parent==self.data/'account-logins' and not any(row.get('source')==old for row in self.accounts.entries):
                shutil.rmtree(Path(old).parent,ignore_errors=True)
        except asyncio.CancelledError:
            self.login_view=dict(running=False,status='cancelled',message='Sign-in cancelled.')
            self.update(account_login=self.login_view)
            raise
        except Exception as error:
            # Known host errors are bounded. Never pass raw process output,
            # auth responses or token data into notices or chat history.
            message=str(error) if isinstance(error,ValueError) else 'Sign-in could not finish. Try again or use device code.'
            self.login_view=dict(running=False,status='error',message=message[:300])
            self.update(account_login=self.login_view)
        finally:
            await attempt.close()
            if not committed:shutil.rmtree(attempt.home,ignore_errors=True)
            if self.login is attempt:self.login=None;self.login_task=None

    async def initialize(self):
        current = self.settings.get('current')
        await self.open_session(current if current and self.valid_id(current) and (self.data/'sessions'/current/'session.json').exists() else None)
        self.spawn(self.scheduler())

    @staticmethod
    def valid_id(id):
        return isinstance(id, str) and re.fullmatch(r'[A-Za-z0-9_-]{1,80}', id)

    async def open_session(self, id=None, project_id=None):
        self.switching = True
        try:
            async with self.scheduler_lock:
                pass
            await self._open_session(id, project_id)
        finally:
            self.switching = False

    async def _open_session(self, id=None, project_id=None):
        if 0 in self.tasks:
            raise ValueError('Stop the current reply before changing conversations')
        if id is not None and not self.valid_id(id):
            raise ValueError('Invalid conversation ID')
        if project_id is not None:
            self.projects.get(project_id)
        creating = id is None
        next_project = self.project_id if project_id is None else project_id
        for worker_id, task in list(self.tasks.items()):
            await self.call(9, action='pause', id=worker_id)
            task.stop()
        while self.tasks:
            await asyncio.sleep(0.02)
        if self.root:
            self.save()
            self.platform.close(self.root)
        id = id or time.strftime('%Y%m%d-%H%M%S-')+uuid.uuid4().hex[:10]
        root = self.data/'sessions'/id
        if root.is_symlink():
            raise ValueError('Conversation folders cannot be symlinks')
        root.mkdir(mode=0o700, parents=True, exist_ok=True)
        (root/'files').mkdir(mode=0o700, exist_ok=True)
        state = self.read(root/'session.json', {})
        next_project = next_project if creating else state.pop('project_id', '')
        self.projects.get(next_project)
        self.root = root
        self.state = state
        self.project_id = next_project
        # Capture legacy recency before navigation/policy saves rewrite the file.
        self.last_activity = self.session_activity(self.state, root/'session.json')
        self.state.pop('last_activity', None)
        self.navigation = self.state.pop('navigation', {})
        self.attachments = self.state.pop('pending_attachments', [])
        saved = self.state.pop('permissions', None)
        policy = await self.call(8, action='permissions', saved=saved)
        self.permissions = policy['policy']
        self.permission_entries = self.platform.permission_entries(policy['entries'])
        self.state.setdefault('messages', [])
        self.state.setdefault('cards', [])
        self.state.setdefault('archive', [])
        self.save()
        await self.load_sessions(emit=False)
        self.emit({'action': 'clear'})
        if self.navigation:
            self.emit({'action': 'restore', 'data': self.navigation})
        await self.facts()
        await self.schedule(recover=True)
        self.save()

    @staticmethod
    def session_activity(saved, path):
        activity = saved.get('last_activity')
        if isinstance(activity, int) and not isinstance(activity, bool) and activity >= 0:
            return activity
        # Old desktop conversations have no activity field. Preserve their
        # existing order when first opened; subsequent saves persist it.
        return int((path.stat().st_mtime if path.exists() else time.time())*1000)

    @staticmethod
    def order_sessions(rows):
        return sorted(rows, key=lambda row: (row['updated'], row['id']), reverse=True)

    async def load_sessions(self, emit=True):
        rows = []
        summaries = {}
        for path in (self.data/'sessions').glob('*/session.json'):
            stat = path.stat()
            stamp = (stat.st_dev, stat.st_ino, stat.st_size, stat.st_mtime_ns, stat.st_ctime_ns)
            cached = self.session_summaries.get(path)
            if cached is not None and cached[0] == stamp:
                entry = cached[1]
            else:
                saved = self.read(path, {})
                summary = await self.call(11, action='summary', saved=saved)
                entry = dict(summary, id=path.parent.name, updated=self.session_activity(saved, path), project_id=saved.get('project_id', ''))
            summaries[path] = (stamp, entry)
            rows.append(dict(entry, current=path.parent == self.root))
        self.session_summaries = summaries
        self.session_entries = self.order_sessions(rows)
        if emit:
            self.update(sessions=self.session_entries, session_id=self.root.name, sessions_loading=False)

    async def select_project(self, id):
        if 0 in self.tasks:
            raise ValueError('Stop the current reply before changing projects')
        self.projects.get(id)
        closed = dict(self.settings.get('sidebar_closed', {}))
        closed[id] = False
        self.settings['sidebar_closed'] = closed
        target = next((row['id'] for row in self.session_entries if row.get('project_id', '') == id), None)
        await self.open_session(target, project_id=id)

    async def update_session_entry(self):
        summary = await self.call(11, action='summary', saved=self.state)
        current = dict(summary, id=self.root.name, current=True, updated=self.last_activity, project_id=self.project_id)
        self.session_entries = self.order_sessions([current]+[dict(row, current=False) for row in self.session_entries if row['id'] != self.root.name])
        self.update(sessions=self.session_entries, session_id=self.root.name)

    async def facts(self):
        limits = await self.call(6, **self.state)
        usage = limits['usage']
        self.update(platform='linux', permission_entries=self.permission_entries, model=self.model, model_network='default', authenticated=self.authenticated(), account=self.account(), accounts=self.account_rows(), account_busy=bool(self.tasks), account_login=self.login_view,
                    sidebar_width=self.settings.get('sidebar_width', 252), sidebar_mode=self.settings.get('sidebar_mode', 'projects'), sidebar_closed=self.settings.get('sidebar_closed', {}),
                    projects=self.projects.entries, project_id=self.project_id, project_name=self.project_name(), project_path=str(self.files_directory()),
                    sessions=self.session_entries, session_id=self.root.name, sessions_loading=False, pending_session_id='',
                    policy=self.permissions, cards=self.state.get('cards', []), attachments=self.attachments,
                    continuation=bool(self.state.get('pending_execution')), busy=0 in self.tasks,
                    used=usage.get('total_tokens', 0), total=limits['usable_context_window'],
                    estimated=usage.get('estimated', True))
        images = {'resource:mipmap/ic_launcher': str(Path(__file__).resolve().parents[3]/'apps/collie/android/res/drawable-nodpi/collie_border_collie.png')}
        for name in ('new-chat', 'new-project', 'settings'):
            images['resource:collie/'+name] = str(Path(__file__).resolve().parents[3]/'apps/collie/desktop/icons'/(name+'.svg'))
        for path in (self.root/'images').glob('*.jpg'):
            images['preview:'+path.stem] = str(path)
            images['attachment:'+path.stem] = str(path)
        self.emit({'action': 'update', 'data': {}, 'images': images})

    async def transition(self, task, state, action, **event):
        return await self.call(8, task.id, action=action, state=state, fixture=self.fixture is not None, **event)

    async def apply(self, task, state, cards):
        if task.id:
            return
        self.state = state
        if cards:
            self.last_activity = max(self.last_activity+1, int(time.time()*1000))
        self.save()
        if cards:
            self.emit({'action': 'append', 'append_cards': cards})
        if any(card.get('kind') == 'user' for card in cards) or state.get('phase') in ('done', 'failed'):
            await self.update_session_entry()
        limits = await self.call(6, **state)
        self.update(continuation=bool(state.get('pending_execution')), used=limits['usage'].get('total_tokens', 0),
                    total=limits['usable_context_window'], estimated=limits['usage'].get('estimated', True))
        if any(card.get('kind')=='image' or card.get('observation', {}).get('views') for card in cards):
            await self.facts()

    async def run(self, task, action, state, event):
        try:
            while not self.closed:
                transition = await self.transition(task, state, action, **event)
                state = transition['state']
                await self.apply(task, state, transition['cards'])
                command = transition['command']
                if command['kind'] == 'done':
                    if command.get('error'):
                        raise RuntimeError(command['error'])
                    return
                if action == 'failure' and task.cancel.is_set():
                    return
                try:
                    task.check()
                    kind = command['kind']
                    if kind == 'model':
                        compact = command['compact']
                        base = dict(messages=state['messages'])
                        body = await self.call(command['engine_op'], task.id, **base)
                        reply = await self.response(task, body, command['response_index'], compact, base['messages'])
                        action, event = ('compacted' if compact else 'reply'), {'reply': reply}
                    elif kind == 'feedback':
                        body = await self.call(1, task.id, messages=command['messages'], feedback=True)
                        reply = await self.response(task, body, command['response_index'], False, command['messages'], True)
                        action, event = 'feedback', {'reply': reply}
                    elif kind == 'imagegen':
                        self.update(status='Generating image…')
                        provider = self.settings.get('image_provider', 'codex')
                        transport = {}
                        if provider == 'codex':
                            transport = await self.call(8, action='imagegen_transport', auth=self.read_auth())
                        signal=command['signal']
                        options=dict(size=self.settings.get('image_size','1024x1024'), quality=self.settings.get('image_quality','auto'), background=self.settings.get('image_background','auto'))
                        if self.settings.get('image_model'):options['model']=self.settings['image_model']
                        file=await asyncio.to_thread(self.images.generate,provider=provider,prompt=signal['prompt'],path=signal['path'],options=options,
                            task=task,transport=transport,root=self.root,files=self.files_directory(),platform=self.platform,
                            key=str(task.id)+':'+command['call_id']+':'+str(signal['id']))
                        action,event='image_generated',{'file':file}
                    elif kind == 'vm':
                        task.check()
                        self.update(status='Running Flexscript…' if not task.id else f'Worker #{task.id} running…')
                        observation = await self.call(3, task.id, cancel=task.cancel, **command['request'], history=state['archive'])
                        action, event = 'observation', {'observation': observation}
                        await self.schedule()
                    elif kind == 'permission':
                        await self.permission(task, command['signal'])
                        action, event = 'next', {}
                    elif kind == 'platform_permission':
                        raise RuntimeError('This operation requires an Android platform consent flow and has no Linux adapter.')
                    elif kind == 'wait':
                        await self.schedule()
                        await asyncio.sleep(command['milliseconds']/1000)
                        action, event = 'next', {}
                    else:
                        raise ValueError('Unknown shared engine effect: '+kind)
                except Exception as error:
                    action, event = 'failure', {'error': str(error), 'cancelled': task.cancel.is_set()}
        except Exception as error:
            if not self.closed:
                self.notice(str(error))
        finally:
            self.tasks.pop(task.id, None)
            self.update(account_busy=bool(self.tasks))
            self.workers.pop(str(task.id), None)
            self.worker_wake.set()
            self.show_prompt()
            if not task.id and not self.closed:
                self.update(busy=False, stream='', live={}, status='', continuation=bool(self.state.get('pending_execution')))
                self.save()

    async def start(self, action, event=None):
        if 0 in self.tasks:
            raise ValueError('A conversation task is already running')
        if action == 'begin' and not self.authenticated():
            raise ValueError('Connect ChatGPT by importing your Codex auth.json first')
        task = Task(0)
        self.tasks[0] = task
        self.update(busy=True,account_busy=True)
        self.spawn(self.run(task, action, self.state, event or {}))

    async def response(self, task, body, index, compact, messages, feedback=False):
        if not task.id:
            self.update(status='')
        config = self.config(task.id)
        if self.fixture is not None:
            sequence = self.fixture
            if isinstance(sequence, dict):
                sequence = sequence.get('workers', {}).get(str(task.id), []) if task.id else sequence['main']
            if index >= len(sequence):
                raise ValueError('Fixture response sequence is exhausted')
            entry = sequence[index]
            if isinstance(entry, dict) and 'events' in entry:
                events = entry['events']
            else:
                events = [entry]
            stream = {}
            for event in events:
                task.check()
                packet = await self.call(8, task.id, action='stream', stream=stream, event_json=json.dumps(event),
                                         compact=compact, messages=messages, feedback=feedback)
                stream = packet['stream']
                self.live(task, packet['display'])
                await asyncio.sleep(0.025)
                if packet.get('complete'):
                    self.clear_live(task)
                    return packet['reply']
            raise ValueError('Fixture must contain a completed response')
        auth = self.read_auth()
        transport = await self.call(8, action='authenticate', auth=auth)
        loop = asyncio.get_running_loop()
        root = self.root

        def request():
            # Model credentials go only to the exact shared provider endpoint;
            # redirects are rejected so credentials cannot cross an origin.
            class NoRedirect(urllib.request.HTTPRedirectHandler):
                def redirect_request(self, *args):
                    raise ValueError('Model endpoint redirects are not accepted')
            opener = urllib.request.build_opener(NoRedirect())
            req = urllib.request.Request(transport['url'], json.dumps(body).encode(), transport['headers'], method='POST')
            stream = {}
            total = 0
            event_data = []
            try:
                response = opener.open(req, timeout=30)
                task.connection = response
                with response:
                    for line in response:
                        task.check()
                        total += len(line)
                        if total > LIMIT:
                            raise ValueError('Model stream exceeds 8 MiB')
                        if len(line) > 1048576:
                            raise ValueError('Model stream line exceeds 1 MiB')
                        line = line.decode('utf-8').rstrip('\r\n')
                        if line.startswith('data:'):
                            event_data.append(line[5:].lstrip(' '))
                        elif not line and event_data:
                            raw = '\n'.join(event_data); event_data.clear()
                            packet = self.engine.call_sync(8, dict(config=config, action='stream', stream=stream,
                                                                 event_json=raw, compact=compact, messages=messages, feedback=feedback), root)
                            stream = packet['stream']
                            loop.call_soon_threadsafe(self.live, task, packet['display'])
                            if packet.get('complete'):
                                return packet['reply']
                    raise ValueError('Model stream ended before a completed response')
            except urllib.error.HTTPError as error:
                result = self.engine.call_sync(8, dict(config=config, action='transport_error', status=error.code), root)
                raise RuntimeError(result['message']) from None
            finally:
                task.connection = None
        try:
            return await asyncio.to_thread(request)
        finally:
            self.clear_live(task)

    def live(self, task, display):
        if self.closed or task.cancel.is_set() or self.tasks.get(task.id) is not task:
            return
        if task.id:
            self.workers[str(task.id)] = display
            self.update(worker_streams=dict(self.workers))
        else:
            self.update(stream=display.get('text', ''), live=display)

    def clear_live(self, task):
        if task.id:
            self.workers.pop(str(task.id), None)
            self.update(worker_streams=dict(self.workers))
        else:
            self.update(stream='', live={})

    async def permission(self, task, signal):
        self.sequence += 1
        future = asyncio.get_running_loop().create_future()
        pending = dict(signal, request_id=self.sequence, agent_id=task.id)
        self.prompts.append((task, pending, future))
        self.show_prompt()
        try:
            while not future.done():
                task.check()
                await asyncio.sleep(0.05)
            future.result()
            task.check()
        finally:
            self.prompts = [item for item in self.prompts if item[2] is not future]
            self.show_prompt()

    def show_prompt(self):
        for task, pending, future in list(self.prompts):
            if task.cancel.is_set():
                if not future.done(): future.set_result(None)
                self.prompts.remove((task, pending, future))
            elif self.permissions.get(pending['key']) != 'ask':
                if not future.done(): future.set_result(None)
                self.prompts.remove((task, pending, future))
        self.update(permission_request=self.prompts[0][1] if self.prompts else {})

    async def schedule(self, recover=False):
        async with self.scheduler_lock:
            if self.closed or self.closing or (self.switching and not recover):
                return
            plan = await self.call(9, action='plan', active=[id for id in self.tasks if id], recover=recover,
                                   allowed=self.permissions.get('workers') is True, authenticated=self.authenticated())
            for id in plan['cancel']:
                if id in self.tasks: self.tasks[id].stop()
            for entry in plan['start']:
                id = entry['id']; task = Task(id); self.tasks[id] = task
                self.spawn(self.run(task, 'open_worker', {}, {'revision': entry['revision']}))
            if plan['start']:
                self.update(account_busy=True)
                self.worker_wake.set()
            if plan['workers'] != self.last_worker_rows:
                self.last_worker_rows = plan['workers']
                self.update(workers=plan['workers'], workers_error='')

    async def scheduler(self):
        while not self.closed:
            if any(self.tasks):
                try:
                    await asyncio.wait_for(self.worker_wake.wait(), 0.5)
                except asyncio.TimeoutError:
                    pass
            else:
                await self.worker_wake.wait()
            self.worker_wake.clear()
            await self.schedule()

    async def choose(self, title, folder=False):
        if os.environ.get('COLLIE_HEADLESS') == '1':
            raise ValueError('File dialogs are disabled during headless testing')
        if shutil.which('zenity'):
            cmd = ['zenity', '--file-selection', '--title='+title]
            if folder: cmd.append('--directory')
        elif shutil.which('kdialog'):
            cmd = ['kdialog', '--getexistingdirectory' if folder else '--getopenfilename', str(Path.home()), '--title', title]
        else:
            raise ValueError('Install zenity or kdialog for file selection, or use --auth PATH')
        proc = await asyncio.create_subprocess_exec(*cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL)
        out, _ = await proc.communicate()
        if proc.returncode: return None
        return Path(out.decode().strip())

    async def attach(self, path):
        if len(self.attachments) >= 4:
            raise ValueError('At most four attachments per message')
        path = Path(path)
        if not path.is_file() or path.stat().st_size > 2097152:
            raise ValueError('Choose a regular file up to 2 MiB')
        data = await asyncio.to_thread(path.read_bytes)
        name = re.sub(r'[^\w .-]', '_', path.name)[:100] or 'attachment'
        relative = 'attachments/'+uuid.uuid4().hex[:12]+'-'+name
        atomic(self.workspace_path(relative), data)
        file = dict(type='file', path=relative, name=name, file_bytes=len(data), bytes=len(data))
        if path.suffix.lower() in ('.png', '.jpg', '.jpeg', '.webp'):
            file.update(await asyncio.to_thread(self.platform.image, self.root, data))
        else:
            try: file.update(text=data[:16384].decode('utf-8'), truncated=len(data) > 16384)
            except UnicodeDecodeError: pass
        self.attachments.append(file)
        self.save()
        await self.facts()

    async def open_link(self, href):
        if not isinstance(href, str) or not href or len(href)>8192 or any(ord(c)<32 or ord(c)==127 for c in href):
            raise ValueError('Invalid message link')
        parts = urllib.parse.urlsplit(href)
        if parts.scheme in ('http', 'https') and parts.netloc:
            target = href
        elif not parts.scheme and not parts.netloc:
            relative = Path(urllib.parse.unquote(parts.path))
            path = self.workspace_path(relative)
            if not path.is_file():
                raise ValueError('Linked file does not exist')
            target = path.as_uri()
            if parts.query: target += '?'+parts.query
            if parts.fragment: target += '#'+parts.fragment
        else:
            raise ValueError('Only web links and files in this conversation can be opened')
        if os.environ.get('COLLIE_HEADLESS')=='1':
            raise ValueError('Browser launch is disabled during headless testing')
        if not await asyncio.to_thread(webbrowser.open, target, new=2):
            raise ValueError('Could not open the link in your browser')

    async def command(self, command):
        async with self.operation_lock:
            kind = command['kind']
            if kind == 'submit':
                attached = self.attachments
                self.attachments = []
                try:
                    await self.start('begin', dict(text=command['text'], attachments=attached))
                except Exception:
                    self.attachments = attached
                    self.update(draft=command['text'])
                    raise
                self.update(attachments=[])
            elif kind == 'cancel':
                if 0 in self.tasks: self.tasks[0].stop()
                for id, task in self.tasks.items():
                    if id: task.stop()
                self.platform.close(self.root)
                self.show_prompt()
            elif kind == 'new_session':
                await self.open_session(project_id=command.get('project_id'))
            elif kind == 'choose_project_folder':
                if 0 in self.tasks:
                    raise ValueError('Stop the current reply before changing projects')
                folder = await self.choose('Choose a project folder', folder=True)
                if folder is not None:
                    project = self.projects.add(folder)
                    await self.select_project(project['id'])
            elif kind == 'select_project':
                await self.select_project(command['id'])
            elif kind == 'open_session':
                if 'request_id' in command:
                    self.session_request = command['request_id']
                await self.open_session(command['id'])
            elif kind == 'load_sessions':
                await self.load_sessions()
            elif kind == 'load_worker':
                result = await self.call(9, action='messages', id=command['id'])
                self.update(worker_owner=command['id'], worker_messages=result['messages'])
            elif kind == 'worker_action':
                await self.call(9, action=command['action'], id=command['id'])
                if command['action'] == 'cancel' and command['id'] in self.tasks:
                    self.tasks[command['id']].stop()
                await self.schedule()
            elif kind == 'permission':
                key = command['key']
                if key not in self.permissions or command['allowed'] not in (True, False, 'ask'):
                    raise ValueError('Invalid permission setting')
                self.set_permission(key, command['allowed'])
                if command['allowed'] is not True:
                    self.platform.close(self.root, key)
                    for task in self.tasks.values(): task.stop()
                self.show_prompt(); self.update(policy=self.permissions)
                await self.schedule()
            elif kind == 'permission_decision':
                if not self.prompts or self.prompts[0][1]['request_id'] != command['request_id']:
                    raise ValueError('Stale permission request')
                task, pending, future = self.prompts[0]
                if command.get('stop'):
                    task.stop()
                else:
                    self.set_permission(pending['key'], bool(command['allowed']))
                future.set_result(None); self.show_prompt(); self.update(policy=self.permissions)
            elif kind == 'save_model':
                if not re.fullmatch(r'[A-Za-z0-9_.-]{1,120}', command['model']): raise ValueError('Invalid model name')
                self.model = command['model']; self.save(); await self.facts()
            elif kind == 'save_model_network':
                if command['network'] != 'default':
                    raise ValueError('Desktop currently uses the system default network for model requests')
                self.update(model_network='default')
            elif kind == 'resume_main':
                await self.start('resume')
            elif kind == 'compact':
                await self.start('compact')
            elif kind == 'start_account_login':
                await self.start_login(command.get('method','browser'))
            elif kind == 'cancel_account_login':
                await self.cancel_login()
            elif kind == 'open_account_login':
                if not await self.open_login_browser():
                    self.login_view=dict(self.login_view,message='Could not open a browser automatically. Copy the sign-in link or try device code.')
                    self.update(account_login=self.login_view)
            elif kind == 'import_auth':
                self.account_idle()
                self.ensure_accounts()
                path = await self.choose('Add OpenAI account · Choose Codex auth.json')
                if path:
                    auth = self.read(path, {})
                    await self.call(8, action='authenticate', auth=auth)
                    self.account_idle()
                    self.accounts.add(auth,path)
                    self.account_metadata_enabled=True
                    self.auth_file=self.accounts.path()
                    self.settings.pop('auth_file',None)
                    self.save(); self.refresh_account()
            elif kind == 'select_account':
                self.account_idle()
                self.accounts.refresh(command['id'])
                await self.call(8,action='authenticate',auth=self.accounts.auth(command['id']))
                self.account_idle()
                self.auth_file=self.accounts.select(command['id'])
                self.account_metadata_enabled=True
                self.settings.pop('auth_file',None)
                self.save();self.refresh_account()
            elif kind == 'refresh_account':
                self.refresh_account()
            elif kind in ('files', 'gallery'):
                path = await self.choose('Attach an image' if kind == 'gallery' else 'Attach a file')
                if path: await self.attach(path)
            elif kind == 'camera':
                await self.capture_camera()
            elif kind == 'remove_attachment':
                index = command['index']
                if not 0 <= index < len(self.attachments): raise ValueError('Stale attachment')
                self.attachments.pop(index); self.save(); self.update(attachments=self.attachments)
            elif kind == 'open_link':
                await self.open_link(command['href'])
            elif kind == 'read_preview':
                file = dict(command['file']); relative = Path(file['path'])
                if relative.is_absolute() or '..' in relative.parts: raise ValueError('Invalid workspace preview path')
                path = self.workspace_path(relative)
                if not path.is_file(): raise ValueError('Preview file does not exist')
                data = await asyncio.to_thread(path.read_bytes)
                if len(data) > 2097152: raise ValueError('Preview exceeds 2 MiB')
                if file.get('type') == 'image': file.update(self.platform.image(self.root, data))
                else: file.update(text=data[:16384].decode('utf-8'), truncated=len(data) > 16384)
                self.emit({'action': 'preview', 'file': file})
            elif kind == 'sidebar_width':
                width = command.get('width')
                if type(width) is not int or not 220 <= width <= 520:
                    raise ValueError('Invalid sidebar width')
                self.settings['sidebar_width'] = width
                self.save()
            elif kind == 'navigation':
                navigation = dict(command['data'])
                mode = navigation.pop('sidebar_mode', None)
                closed = navigation.pop('sidebar_closed', None)
                width = navigation.pop('sidebar_width', None)
                if type(width) is int:
                    self.settings['sidebar_width'] = max(220, min(520, width))
                if mode in ('projects', 'timeline'):
                    self.settings['sidebar_mode'] = mode
                if isinstance(closed, dict):
                    self.settings['sidebar_closed'] = closed
                self.navigation = navigation; self.save()
            else:
                raise ValueError('Unknown desktop effect: '+kind)

    async def capture_camera(self):
        if os.environ.get('COLLIE_HEADLESS') == '1':
            raise ValueError('Physical camera capture is disabled during headless testing')
        if not shutil.which('ffmpeg'):
            raise ValueError('Install ffmpeg to capture a camera image, or attach an existing image from Images')
        devices = [Path('/dev')/p.name for p in sorted(Path('/sys/class/video4linux').glob('video*'))
                   if os.access(Path('/dev')/p.name, os.R_OK)]
        if not devices:
            raise ValueError('No readable Linux camera device is available')
        device = devices[0]
        if len(devices) > 1 and shutil.which('zenity'):
            choices = []
            for path in devices:
                name = (Path('/sys/class/video4linux')/path.name/'name').read_text().strip()
                choices.extend([str(path), name])
            chooser = await asyncio.create_subprocess_exec('zenity', '--list', '--title=Choose a camera',
                        '--column=Device', '--column=Camera', *choices, stdout=asyncio.subprocess.PIPE,
                        stderr=asyncio.subprocess.DEVNULL)
            selected, _ = await chooser.communicate()
            if chooser.returncode: return
            device = Path(selected.decode().strip())
            if device not in devices: raise ValueError('Invalid camera selection')
        path = self.root/('capture-'+uuid.uuid4().hex+'.jpg')
        self.update(status='Capturing camera image…')
        process = await asyncio.create_subprocess_exec('ffmpeg', '-hide_banner', '-loglevel', 'error', '-nostdin',
                    '-f', 'v4l2', '-i', str(device), '-frames:v', '1', '-vf', 'scale=1536:1536:force_original_aspect_ratio=decrease',
                    '-update', '1', str(path), stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.PIPE)
        try:
            _, error = await asyncio.wait_for(process.communicate(), 12)
            if process.returncode: raise ValueError('Camera capture failed: '+error[:500].decode(errors='replace'))
            await self.attach(path)
        finally:
            if process.returncode is None:
                process.kill(); await process.wait()
            path.unlink(missing_ok=True)
            self.update(status='')

    async def close(self):
        await self.cancel_login(emit=False)
        self.closing = True
        for task in list(self.tasks.values()): task.stop()
        self.engine.stop()
        deadline = asyncio.get_running_loop().time()+3
        while self.tasks and asyncio.get_running_loop().time() < deadline:
            await asyncio.sleep(0.02)
        self.closed = True
        for task in list(self.background): task.cancel()
        await asyncio.gather(*self.background, return_exceptions=True)
        self.platform.close()
        if self.root: self.save()
        self.lease.close()


async def main(args):
    desktop = Desktop(args.engine, args.data, args.auth, args.fixture)
    try:
        await desktop.initialize()
        reader = asyncio.StreamReader(limit=LIMIT)
        protocol = asyncio.StreamReaderProtocol(reader)
        await asyncio.get_running_loop().connect_read_pipe(lambda: protocol, sys.stdin.buffer)
        while line := await reader.readline():
            try:
                await desktop.command(json.loads(line))
            except Exception as error:
                desktop.notice(str(error))
    finally:
        await desktop.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine', type=Path, required=True)
    parser.add_argument('--data', type=Path, default=Path(os.environ.get('XDG_DATA_HOME', str(Path.home()/'.local/share')))/'collie')
    parser.add_argument('--auth', type=Path)
    parser.add_argument('--fixture', type=Path)
    try:
        asyncio.run(main(parser.parse_args()))
    except (BrokenPipeError, KeyboardInterrupt):
        pass
