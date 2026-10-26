"""Linux platform facts and bounded resource adapters for the shared VM ABI."""
import base64
import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import re
import socket
import struct
import threading
import urllib.error
import urllib.parse
import urllib.request
import uuid


def atomic(path, data):
    path = Path(path)
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    temp = path.with_name('.'+path.name+'.'+uuid.uuid4().hex)
    try:
        with temp.open('xb') as f:
            os.chmod(temp, 0o600)
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        os.replace(temp, path)
        fd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)
    finally:
        temp.unlink(missing_ok=True)


class Failure(Exception):
    def __init__(self, code, message):
        self.code = code
        super().__init__(message)


class HTTPSRedirect(urllib.request.HTTPRedirectHandler):
    def __init__(self):
        self.count = 0

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        self.count += 1
        if self.count > 3 or urllib.parse.urlsplit(newurl).scheme != 'https':
            raise ValueError('HTTPS redirect limit exceeded or non-HTTPS redirect')
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def https_get(url, timeout=8, binary=False):
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password or len(url) > 4096:
        raise ValueError('A credential-free HTTPS URL is required')
    request = urllib.request.Request(url, headers={'User-Agent': 'collie/0.1', 'Accept-Encoding': 'identity'})
    opener = urllib.request.build_opener(HTTPSRedirect())
    try:
        response = opener.open(request, timeout=timeout)
    except urllib.error.HTTPError as error:
        response = error
    with response:
        body = response.read(32769)
        data = body[:32768]
        return {'status': response.code, 'url': response.url,
                'body': {'$bytes': base64.b64encode(data).decode()} if binary else data.decode('utf-8', 'strict'),
                'truncated': len(body) > 32768}


class Platform:
    # Resource ownership survives individual engine calls, never process restart.
    IMPLEMENTED = {'net_list': 'network', 'net_info': 'network', 'net_resolve': 'network',
                   'net_tcp_connect': 'network', 'net_tcp_open': 'network', 'net_tcp_dial': 'network',
                   'net_tcp_listen': 'network', 'net_tcp_accept': 'network', 'net_udp_open': 'network',
                   'net_udp_send': 'network', 'net_udp_receive': 'network', 'net_http': 'network',
                   'battery_info': 'device_status', 'thermal_info': 'device_status',
                   'sensor_list': 'sensors', 'sensor_info': 'sensors', 'usb_list': 'usb', 'usb_info': 'usb',
                   'device_read': 'network', 'device_write': 'network', 'device_info': 'network',
                   'device_wait': 'network', 'device_close': 'network'}

    def __init__(self):
        self.handles = {}
        self.lock = threading.RLock()
        self.generation = 0
        self.local = threading.local()

    @staticmethod
    def permission_entries(entries):
        descriptions = {
            'network': 'Use bounded TCP, UDP and HTTPS connections through the Linux system default route.',
            'usb': 'Inspect Linux USB device metadata. Desktop USB transfers are not implemented yet.',
            'sensors': 'Inspect Linux IIO sensor metadata. Desktop measurement streaming is not implemented yet.',
            'device_status': 'Read actual Linux power-supply and thermal-zone information.'}
        generic = {'internet', 'files_read', 'files_write', 'db_read', 'db_write', 'history', 'workers'}
        result = []
        for entry in entries:
            row = dict(entry)
            if row['key'] == 'sensors': row['title'] = 'Sensors'
            if row['key'] == 'device_status': row['title'] = 'System status'
            if row['key'] in descriptions:
                row['detail'] = descriptions[row['key']]
            elif row['key'] not in generic:
                continue
            result.append(row)
        return result

    def close(self, root=None, permission=None):
        with self.lock:
            self.generation += 1
            for key, item in list(self.handles.items()):
                if (root is None or item['root'] == str(root)) and (permission is None or item['permission'] == permission):
                    with contextlib.suppress(OSError):
                        item['socket'].shutdown(socket.SHUT_RDWR)
                    item['socket'].close()
                    del self.handles[key]

    def image(self, root, data, max_input=2097152):
        from PIL import Image, ImageOps
        if len(data) > max_input:
            raise ValueError('Image exceeds 2 MiB')
        with Image.open(io.BytesIO(data)) as original:
            if original.format not in ('PNG', 'JPEG', 'WEBP') or original.width*original.height > 40000000:
                raise ValueError('Use PNG, JPEG or WebP up to 40 megapixels')
            image = ImageOps.exif_transpose(original).convert('RGB')
            image.thumbnail((1536, 1536))
            out = io.BytesIO()
            for quality in (85, 70, 50):
                out.seek(0); out.truncate()
                image.save(out, 'JPEG', quality=quality)
                if out.tell() <= 524288:
                    break
            if out.tell() > 524288:
                raise ValueError('Normalized image exceeds snapshot limit')
            snapshot = out.getvalue()
            key = hashlib.sha256(snapshot).hexdigest()
            atomic(Path(root)/'images'/f'{key}.jpg', snapshot)
            return {'type': 'image', 'image_id': key, 'width': image.width, 'height': image.height,
                    'bytes': len(snapshot), 'mime': 'image/jpeg'}

    def call(self, root, name, value):
        if name == 'vmHttpGet':
            return https_get(value.decode())
        if name == 'vmViewImage':
            return self.image(root, value)
        if name == 'vmImageBytes':
            key = value.decode()
            if not re.fullmatch('[a-f0-9]{64}', key):
                raise ValueError('Invalid image ID')
            return (Path(root)/'images'/f'{key}.jpg').read_bytes()
        if name != 'vmHardware':
            raise ValueError('Unknown platform operation')
        packet = json.loads(value)
        try:
            with self.lock:
                self.local.generation = self.generation
            if packet.get('phase') == 'permission':
                item = self.handle(root, packet['args'][0])
                return {'value': {'permission': item['permission'], 'also': ''}}
            return {'value': self.hardware(root, packet['operation'], packet['args'])}
        except Failure as error:
            return {'error': {'code': error.code, 'message': str(error)}}
        except (OSError, ValueError, KeyError, TypeError) as error:
            return {'error': {'code': 'platform_error', 'message': str(error)}}

    @staticmethod
    def integer(value, minimum, maximum):
        if type(value) is not int or not minimum <= value <= maximum:
            raise Failure('invalid_argument', f'Integer must be {minimum}..{maximum}')
        return value

    def handle(self, root, key):
        with self.lock:
            item = self.handles.get(key)
        if not item or item['root'] != str(root):
            raise Failure('stale_handle', 'Resource is closed or belongs to another conversation')
        return item

    def add(self, root, sock, kind):
        with self.lock:
            if getattr(self.local, 'generation', self.generation) != self.generation:
                sock.close()
                raise Failure('permission_revoked', 'Resource opened after its owning session was closed or revoked')
            if sum(item['root'] == str(root) for item in self.handles.values()) >= 32:
                sock.close()
                raise Failure('resource_limit', 'At most 32 resources per conversation')
            key = 'linux-'+uuid.uuid4().hex
            self.handles[key] = {'root': str(root), 'socket': sock, 'kind': kind, 'permission': 'network'}
            return key

    @staticmethod
    def network(selector):
        # No global route changes, and never claim a transport was bound.
        if selector != 'default':
            raise Failure('unsupported_operation', 'Linux sockets currently support the default route only')

    def hardware(self, root, op, args):
        if op == 'hardware_access_info':
            return {'platform': 'linux', 'uid': os.getuid(), 'device_access': 'normal user permissions',
                    'privileged_adapter': False, 'implemented_operations': sorted(self.IMPLEMENTED)}
        if op == 'hardware_capabilities':
            return [{'id': name, 'implemented': True, 'supported': True, 'available': True, 'permission': grant}
                    for name, grant in self.IMPLEMENTED.items()]
        if op.startswith('device_'):
            item = self.handle(root, args[0]); sock = item['socket']
            if op == 'device_close':
                sock.close(); del self.handles[args[0]]; return 1
            if op == 'device_info':
                return {'kind': item['kind'], 'network': 'default', 'local': str(sock.getsockname())}
            if op == 'device_read':
                limit = self.integer(args[1], 1, 32768); sock.settimeout(self.integer(args[2], 1, 8000)/1000)
                try:
                    data = sock.recv(limit)
                    return {'$bytes': base64.b64encode(data).decode()} if data else None
                except socket.timeout:
                    return None
            if op == 'device_write':
                value = args[1]
                data = value.encode() if isinstance(value, str) else base64.b64decode(value['$bytes'], validate=True)
                if len(data) > 32768:
                    raise Failure('size_limit', 'Write exceeds 32 KiB')
                sock.settimeout(8)
                return sock.send(data)
            if op == 'device_wait':
                import select
                timeout = self.integer(args[1], 0, 1000)/1000
                return {'type': 'readable'} if select.select([sock], [], [], timeout)[0] else None
        if op == 'net_list':
            return [{'id': 'default', 'transport': 'system', 'interfaces': [name for _, name in socket.if_nameindex()]}]
        if op == 'net_info':
            self.network(args[0]); return {'id': 'default', 'transport': 'system', 'bound': False}
        if op == 'net_resolve':
            self.network(args[0]); return list(dict.fromkeys(row[4][0] for row in socket.getaddrinfo(args[1], None)))[:32]
        if op == 'net_http':
            self.network(args[0]); return https_get(args[1], self.integer(args[2], 1, 8000)/1000, True)
        if op == 'net_tcp_open':
            self.network(args[0]); return self.add(root, socket.socket(), 'tcp')
        if op == 'net_tcp_connect':
            self.network(args[0]); timeout = self.integer(args[3], 1, 8000)/1000
            port = self.integer(args[2], 1, 65535)
            return self.add(root, socket.create_connection((args[1], port), timeout), 'tcp')
        if op == 'net_tcp_dial':
            item = self.handle(root, args[0]); sock = item['socket']
            sock.settimeout(self.integer(args[3], 1, 8000)/1000)
            sock.connect((args[1], self.integer(args[2], 1, 65535))); return 1
        if op == 'net_tcp_listen':
            self.network(args[0]); port = self.integer(args[1], 0, 65535); backlog = self.integer(args[2], 1, 32)
            sock = socket.socket(); sock.bind(('', port)); sock.listen(backlog)
            return self.add(root, sock, 'tcp_listener')
        if op == 'net_tcp_accept':
            item = self.handle(root, args[0]); sock = item['socket']
            sock.settimeout(self.integer(args[1], 1, 8000)/1000)
            try:
                connection, _ = sock.accept(); return self.add(root, connection, 'tcp')
            except socket.timeout:
                return None
        if op == 'net_udp_open':
            self.network(args[0]); sock = socket.socket(type=socket.SOCK_DGRAM)
            sock.bind(('', self.integer(args[1], 0, 65535))); return self.add(root, sock, 'udp')
        if op == 'net_udp_send':
            item = self.handle(root, args[0]); data = args[3]
            data = data.encode() if isinstance(data, str) else base64.b64decode(data['$bytes'], validate=True)
            if len(data) > 32768: raise Failure('size_limit', 'Datagram exceeds 32 KiB')
            return item['socket'].sendto(data, (args[1], self.integer(args[2], 1, 65535)))
        if op == 'net_udp_receive':
            item = self.handle(root, args[0]); sock = item['socket']
            sock.settimeout(self.integer(args[2], 1, 8000)/1000)
            try:
                data, address = sock.recvfrom(self.integer(args[1], 1, 32768))
                return {'data': {'$bytes': base64.b64encode(data).decode()}, 'host': address[0], 'port': address[1]}
            except socket.timeout:
                return None
        if op == 'battery_info':
            supplies = []
            for path in sorted(Path('/sys/class/power_supply').glob('*'))[:16]:
                facts = {'id': path.name}
                for field in ('type', 'status', 'capacity', 'online', 'voltage_now', 'current_now', 'energy_now', 'energy_full'):
                    try: facts[field] = (path/field).read_text().strip()
                    except OSError: pass
                supplies.append(facts)
            return {'supplies': supplies, 'present': bool(supplies)}
        if op == 'thermal_info':
            rows = []
            for path in sorted(Path('/sys/class/thermal').glob('thermal_zone*'))[:32]:
                try: rows.append({'id': path.name, 'type': (path/'type').read_text().strip(), 'temperature_millicelsius': int((path/'temp').read_text())})
                except OSError: pass
            return {'zones': rows}
        if op == 'sensor_list':
            rows = []
            for path in sorted(Path('/sys/bus/iio/devices').glob('iio:device*'))[:32]:
                try: rows.append({'id': path.name, 'name': (path/'name').read_text().strip()})
                except OSError: pass
            return {'sensors': rows, 'total': len(rows), 'next': -1}
        if op == 'sensor_info':
            if not re.fullmatch(r'iio:device\d+', args[0]): raise Failure('invalid_argument', 'Invalid IIO sensor ID')
            path = Path('/sys/bus/iio/devices')/args[0]
            return {'id': args[0], 'name': (path/'name').read_text().strip()}
        if op == 'usb_list':
            offset = self.integer(args[0], 0, 65535); limit = self.integer(args[1], 1, 32)
            rows = []
            for path in sorted(Path('/sys/bus/usb/devices').glob('*')):
                if (path/'idVendor').exists(): rows.append(self.usb_info(path))
            return {'devices': rows[offset:offset+limit], 'total': len(rows), 'next': offset+limit if offset+limit < len(rows) else -1}
        if op == 'usb_info':
            if not re.fullmatch(r'[0-9a-z.-]{1,64}', args[0]): raise Failure('invalid_argument', 'Invalid USB device ID')
            return self.usb_info(Path('/sys/bus/usb/devices')/args[0])
        raise Failure('unsupported_operation', f'{op} has no Linux adapter. Android-specific services are unavailable on desktop.')

    @staticmethod
    def usb_info(path):
        row = {'id': path.name}
        for key in ('idVendor', 'idProduct', 'manufacturer', 'product', 'serial', 'busnum', 'devnum'):
            try: row[key] = (path/key).read_text().strip()
            except OSError: pass
        return row
