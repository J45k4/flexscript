"""Independent MQTT3.1.1 wire corpus, UTF-8 reference and guarded mutation runner."""
from pathlib import Path
import argparse, json, random, struct, subprocess

p=argparse.ArgumentParser();p.add_argument('--oracle',required=True);p.add_argument('--report',type=Path,required=True);a=p.parse_args()
def packet(header,body=b''):
    length=len(body);digits=bytearray()
    while length>=128:digits.append(length%128|128);length//=128
    return bytes([header])+digits+bytes([length])+body
def string(value):return struct.pack('!H',len(value))+value
def publish(topic,payload,qos=0,identifier=1,dup=0,retain=0):
    return packet(0x30|qos*2|dup*8|retain,string(topic)+(struct.pack('!H',identifier) if qos else b'')+payload)
def utf8(value):
    text=value.decode('utf-8',errors='strict')
    if '\0' in text:raise ValueError('NUL')
    return text
def reference(wire):
    if len(wire)<2:raise ValueError('header')
    header=wire[0];kind=header>>4;flags=header&15;at=1;length=0
    for shift in (0,7,14,21):
        digit=wire[at];at+=1;length+=(digit&127)<<shift
        if not digit&128:
            if shift and not digit:raise ValueError('nonminimal')
            break
    else:raise ValueError('length')
    if length>2048 or len(wire)!=at+length:raise ValueError('size')
    if kind==3:
        qos=flags//2%4
        if qos==3 or (not qos and flags&8):raise ValueError('flags')
    elif kind==6:
        if flags!=2:raise ValueError('flags')
    elif kind not in (2,4,5,7,9,11,13) or flags:raise ValueError('direction/flags')
    body=wire[at:];identifier=qos=dup=retain=session=code=0;topic=payload=b''
    if kind==2:
        if len(body)!=2 or body[0]>1 or body[1]>5 or (body[1] and body[0]):raise ValueError('CONNACK')
        session,code=body
    elif kind==3:
        qos=flags//2%4;dup=flags//8;retain=flags%2;topic_length=struct.unpack('!H',body[:2])[0]
        topic=body[2:2+topic_length]
        if not topic_length or len(topic)!=topic_length or '#' in utf8(topic) or '+' in utf8(topic):raise ValueError('topic')
        cursor=2+topic_length
        if qos:
            identifier=struct.unpack('!H',body[cursor:cursor+2])[0];cursor+=2
            if not identifier:raise ValueError('identifier')
        payload=body[cursor:]
    elif kind==13:
        if body:raise ValueError('PINGRESP')
    else:
        if (kind==9 and len(body)<3) or (kind!=9 and len(body)!=2):raise ValueError('size')
        identifier=struct.unpack('!H',body[:2])[0]
        if not identifier:raise ValueError('identifier')
        if kind==9:
            payload=body[2:]
            if any(c not in (0,1,2,128) for c in payload):raise ValueError('grant')
    return (kind,flags,identifier,qos,dup,retain,session,code,len(topic),len(payload)),topic+payload

valid=[packet(0x20,bytes([sp,code])) for code in range(6) for sp in range(2) if not sp or not code]
valid += [publish(t,b'\0\x01\xffpayload',q,65535,dup,retain) for t in [b'a',b'/',b'a//b',b'$SYS/value','中文/🚀'.encode(),b'\xef\xbb\xbf/a'] for q in range(3) for dup in range(2) if q or not dup for retain in range(2)]
valid += [packet(t*16+(2 if t==6 else 0),struct.pack('!H',i)) for t in (4,5,6,7,11) for i in (1,65535)]
valid += [packet(0x90,b'\0\x01'+bytes([0,1,2,128])),packet(0xd0),publish(b'a',bytes(i%251 for i in range(2045))),publish(b'x'*2046,b'')]
invalid=[bytes([kind*16|flags,0]) for kind in range(16) for flags in range(16) if not ((kind==3 and flags//2%4!=3 and (flags//2%4 or not flags&8)) or (kind==6 and flags==2) or (kind in (2,4,5,7,9,11,13) and not flags))]
invalid += [b'\xd0\x80\0',b'\x30\xff\xff\xff\xff\0',b'\x30\x81\x10',b'\x30\x80\x80\x80\x80',packet(0x20,b'\x02\0'),packet(0x20,b'\x01\x05'),packet(0x20,b'\0\x06'),packet(0x20,b'\0'),packet(0x90,b'\0\x01'),packet(0x90,b'\0\x01\x03'),packet(0x90,b'\0\0\0'),packet(0xd0,b'x')]
invalid += [packet(kind*16+(2 if kind==6 else 0),body) for kind in (4,5,6,7,11) for body in (b'',b'\0',b'\0\0',b'\0\x01\0')]
invalid += [publish(topic,b'',1) for topic in (b'',b'a/#',b'+',b'a\0b',b'\x80',b'\xc0\x80',b'\xed\xa0\x80',b'\xf4\x90\x80\x80',b'\xe0\x80\x80',b'\xf0\x80\x80\x80',b'\xe4\xb8')]
invalid += [packet(0x32,b'\0\x01a\0\0'),packet(0x32,b'\0\x02a'),packet(0x32,b'\0\x01a\0'),packet(0x30,b'\0\x05a'),packet(0x30,b'\0')]
checks=0
def check(wire,step,expected=None):
    global checks
    try:want=reference(wire)
    except (ValueError,IndexError,struct.error,UnicodeError):want=None
    if expected is not None:assert (want is not None)==expected,wire.hex()
    run=subprocess.run([a.oracle,str(step)],input=wire,capture_output=True,timeout=3)
    assert run.returncode in (0,1),(run.returncode,wire.hex(),run.stderr)
    assert (run.returncode==0)==(want is not None),(wire.hex(),run.stderr,want)
    if want is not None:
        fields=list(map(int,run.stderr.split()));assert fields[:3]==[3,0,len(wire)]
        assert tuple(fields[3:])==want[0] and run.stdout==want[1],(wire.hex(),fields,want)
    checks+=1
for wire in valid:
    for step in (1,2,7,1499,8192):check(wire,step,True)
for wire in invalid:
    for step in (1,7,8192):check(wire,step,False)
prefixes=0
for wire in [packet(0x20,b'\0\0'),publish(b'abc',b'binary\0data',2),packet(0x90,b'\0\x01\0\x02\x80'),packet(0x62,b'\0\x01')]:
    for end in range(len(wire)):
        check(wire[:end],1,False);prefixes+=1
rng=random.Random(311);mutations=1024
for _ in range(mutations):
    wire=bytearray(rng.choice(valid))
    for _ in range(rng.randrange(1,5)):
        if wire:wire[rng.randrange(len(wire))]=rng.randrange(256)
    if rng.randrange(3)==0:del wire[rng.randrange(len(wire)+1):]
    check(bytes(wire),rng.choice([1,3,8192]))
report={'checks':checks,'valid_cases':len(valid),'strict_failures':len(invalid),'all_prefix_truncations':prefixes,'mutations':mutations,'guarded_input':True,'guarded_workspace':True,'independent_utf8':'Python strict UTF-8 decoder','reference':'independent struct/Unicode MQTT3.1.1 packet reference; not a broker test'}
a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(report,indent=2)+'\n');print(f'PASS: {checks} MQTT packet/reference/guard checks')
