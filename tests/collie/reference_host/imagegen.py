"""Image providers return bytes; private job journals prevent uncertain replay."""
import base64
import hashlib
import http.client
import io
import json
import os
import stat
from pathlib import Path
import time
import urllib.error
import urllib.request
import uuid

from PIL import Image
from linux_platform import atomic

MAX_IMAGE = 12*1024*1024
MAX_RESPONSE = 16*1024*1024
CODEX_URL = 'https://chatgpt.com/backend-api/codex/images/generations'


class CodexImages:
    """Use the same authenticated image endpoint as the installed Codex client."""
    def generate(self, prompt, options, task, transport, request_id):
        if transport.get('url') != CODEX_URL:
            raise ValueError('Invalid Codex image endpoint')
        deadline = time.monotonic()+240
        class Connection(http.client.HTTPSConnection):
            def __init__(self, *args, **kwargs):
                super().__init__(*args, **kwargs)
                task.connection = self
            def connect(self):
                task.check();super().connect();task.check()
                self.sock.settimeout(max(0.1, deadline-time.monotonic()))
        class HTTPS(urllib.request.HTTPSHandler):
            def https_open(self, req):
                return self.do_open(Connection, req, context=self._context)
        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, *args):
                raise ValueError('Image endpoint redirects are not accepted')
        body = dict(prompt=prompt, n=1, output_format='png', **options)
        headers = dict(transport['headers'], **{'x-codex-imagegen-request-id':request_id})
        request = urllib.request.Request(CODEX_URL, json.dumps(body).encode(), headers, method='POST')
        try:
            task.check()
            with urllib.request.build_opener(NoRedirect(), HTTPS()).open(request, timeout=30) as response:
                task.connection=response
                payload = bytearray()
                while True:
                    task.check()
                    if time.monotonic()>=deadline:raise TimeoutError('Image generation timed out')
                    part=response.read(65536)
                    if not part:break
                    payload.extend(part)
                    if len(payload)>MAX_RESPONSE:raise ValueError('Image response exceeds 16 MiB')
            result = json.loads(payload)
            rows = result.get('data')
            if not isinstance(rows, list) or len(rows)!=1 or not isinstance(rows[0].get('b64_json'), str):
                raise ValueError('Image provider did not return exactly one image')
            image = base64.b64decode(rows[0]['b64_json'], validate=True)
            validate_image(image)
            return image
        except urllib.error.HTTPError as error:
            # Never expose a provider body that might echo transport headers.
            if error.code==401:raise ValueError('Codex login rejected; refresh auth.json') from None
            if error.code==429:raise ValueError('Codex image generation usage limit reached') from None
            raise ValueError('Codex image endpoint returned HTTP '+str(error.code)) from None
        finally:
            connection = task.connection
            if connection is not None:
                connection.close()
            task.connection = None


def validate_image(data):
    if not isinstance(data, bytes) or not 0<len(data)<=MAX_IMAGE:
        raise ValueError('Generated image exceeds 12 MiB or is empty')
    with Image.open(io.BytesIO(data)) as image:
        if image.format!='PNG' or image.width*image.height>40000000:
            raise ValueError('Provider must return a PNG up to 40 megapixels')
        image.verify()


class ImageOutput:
    """Keep path traversal relative to owned directory descriptors, like fs_*."""
    def __init__(self, root, relative):
        if (not isinstance(relative, str) or not 5<=len(relative.encode())<=1024 or
                not relative.endswith('.png') or relative.startswith('/') or
                any(ord(c)<32 or c=='\\' for c in relative)):
            raise ValueError('imagen requires a project-relative .png output path')
        parts=relative.split('/')
        if any(p in ('','.','..') or len(p.encode())>255 for p in parts):
            raise ValueError('Invalid image output path')
        self.relative=relative;self.leaf=parts[-1]
        self.fd=os.open(root, os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW|os.O_CLOEXEC)
        try:
            for part in parts[:-1]:
                try:os.mkdir(part, mode=0o700, dir_fd=self.fd)
                except FileExistsError:pass
                child=os.open(part, os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW|os.O_CLOEXEC, dir_fd=self.fd)
                os.close(self.fd);self.fd=child
            try:mode=os.stat(self.leaf,dir_fd=self.fd,follow_symlinks=False).st_mode
            except FileNotFoundError:pass
            else:
                if not stat.S_ISREG(mode):raise ValueError('Image output must be a regular file')
        except BaseException:
            self.close();raise
    def close(self):
        if self.fd is not None:os.close(self.fd);self.fd=None
    def write(self, data):
        temp='.collie-image-'+uuid.uuid4().hex
        try:
            fd=os.open(temp, os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW|os.O_CLOEXEC, 0o600, dir_fd=self.fd)
            with os.fdopen(fd, 'wb') as stream:
                stream.write(data);stream.flush();os.fsync(stream.fileno())
            os.replace(temp, self.leaf, src_dir_fd=self.fd, dst_dir_fd=self.fd);os.fsync(self.fd)
        finally:
            try:os.unlink(temp, dir_fd=self.fd)
            except FileNotFoundError:pass


class ImageGenerators:
    def __init__(self):
        self.providers={'codex':CodexImages()}
    def register(self, name, provider):
        if not name or name in self.providers:raise ValueError('Duplicate or empty image provider')
        self.providers[name]=provider
    def generate(self, *, provider, prompt, path, options, task, transport, root, files, key, platform):
        if provider not in self.providers:raise ValueError('Unknown image provider: '+str(provider))
        if not isinstance(prompt,str) or not prompt.strip() or len(prompt.encode())>16384:
            raise ValueError('Image prompt must be nonempty and at most 16 KiB')
        if set(options)-{'model','size','quality','background'}:
            raise ValueError('Unsupported image options')
        digest=hashlib.sha256(json.dumps([provider,prompt,path,options],sort_keys=True).encode()).hexdigest()
        journal=Path(root)/'imagegen'/(hashlib.sha256(key.encode()).hexdigest()+'.json')
        output=ImageOutput(files,path)
        try:
            try:saved=json.loads(journal.read_text())
            except FileNotFoundError:saved=None
            if saved is not None:
                if saved.get('digest')!=digest:raise ValueError('Image job does not match its saved request')
                if saved.get('state')=='complete':
                    try:os.stat(output.leaf,dir_fd=output.fd,follow_symlinks=False)
                    except FileNotFoundError:raise ValueError('The generated image file no longer exists') from None
                    return saved['file']
                raise ValueError('This image request was interrupted or failed after dispatch and was not retried; make a new imagen call to request another image')
            task.check()
            request_id=uuid.uuid4().hex
            atomic(journal,json.dumps(dict(state='sent',digest=digest,request_id=request_id)).encode())
            data=self.providers[provider].generate(prompt,options,task,transport,request_id)
            task.check();validate_image(data)
            file=platform.image(root,data,max_input=MAX_IMAGE)
            file.update(path=path,name=Path(path).name,file_bytes=len(data),provider=provider)
            task.check();output.write(data)
            atomic(journal,json.dumps(dict(state='complete',digest=digest,request_id=request_id,file=file)).encode())
            return file
        finally:
            output.close()
