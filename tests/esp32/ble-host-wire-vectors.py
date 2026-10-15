"""Independent HCI/L2CAP framing reference, guard checks and malformed corpus."""
from pathlib import Path
import argparse,json,random,struct,subprocess
p=argparse.ArgumentParser();p.add_argument('--oracle',required=True);p.add_argument('--report',type=Path,required=True);a=p.parse_args()
def packet(handle,boundary,payload):return bytes([2])+struct.pack('<HH',handle|boundary<<12,len(payload))+payload
def frames(cid,payload,fragment=27,handle=64):
    body=struct.pack('<HH',len(payload),cid)+payload
    return [packet(handle,2 if start==0 else 1,body[start:start+fragment]) for start in range(0,len(body),fragment)]
def pack(packets):return b''.join(struct.pack('<H',len(p))+p for p in packets)
def reference(wire):
    at=0;pending=None;out=bytearray();packets=0
    while at<len(wire):
        if len(wire)-at<2:raise ValueError('record')
        size=struct.unpack_from('<H',wire,at)[0];at+=2
        if size>len(wire)-at:raise ValueError('record')
        frame=wire[at:at+size];at+=size;packets+=1
        if packets>4096 or len(frame)<5 or len(frame)>1029 or frame[0]!=2:raise ValueError('header')
        bits,length=struct.unpack_from('<HH',frame,1);handle=bits&4095;boundary=bits>>12&3
        if handle>0xeff or bits&0xc000 or boundary not in (1,2) or length!=len(frame)-5:raise ValueError('header')
        if handle!=64:continue
        if boundary==2:
            if pending is not None:raise ValueError('overlap')
            pending=bytearray()
        elif pending is None:raise ValueError('orphan')
        pending+=frame[5:]
        if len(pending)>=4:
            length,cid=struct.unpack_from('<HH',pending);known=cid in (4,5,6) or 64<=cid<=127
            if known and length>1024:raise ValueError('limit')
            if len(pending)>length+4:raise ValueError('extra')
            if len(pending)==length+4:
                if known:out+=pending[2:4]+pending[:2]+pending[4:]
                pending=None
    if pending is not None:raise ValueError('truncated PDU')
    return bytes(out)
checks=0
def check(wire,expected=None):
    global checks
    try:want=reference(wire)
    except (ValueError,struct.error,IndexError):want=None
    if expected is not None:assert (want is not None)==expected,wire.hex()
    run=subprocess.run([a.oracle],input=wire,capture_output=True,timeout=3)
    assert run.returncode in (0,1),(run.returncode,wire[:128].hex(),run.stderr)
    assert (run.returncode==0)==(want is not None),(wire[:128].hex(),run.stderr,want)
    if want is not None:assert run.stdout==want,(wire[:128].hex(),run.stdout,want)
    checks+=1
valid=[]
for cid in (4,5,6,64,127):
    for size in (0,1,3,23,128,517,1024):
        payload=bytes(i%251 for i in range(size))
        for fragment in (1,2,3,7,27,251,1024):valid.append(pack(frames(cid,payload,fragment)))
for cid in (0,7,63,128,65535):
    for size in (0,5,1024,2048,65535):
        payload=b'x'*size
        for fragment in ((251,1024) if size==65535 else (1,7,251,1024)):valid.append(pack(frames(cid,payload,fragment)))
valid += [pack(frames(4,b'a')+frames(6,b'')+frames(64,b'\0\xff')),pack([packet(64,2,b''),packet(64,1,b''),packet(64,1,b'\x01\0\x04\0x')]),pack(frames(4,b'ignored',7,65)),b'']
invalid=[pack([bytes([t])+b'\0'*4]) for t in (0,1,3,5,255)]
invalid += [pack([packet(64,b,b'\0\0\x04\0')]) for b in (0,1,3)]
invalid += [pack([packet(h,2,b'\0\0\x04\0')]) for h in (0xf00,0xfff,0x4040,0x8040,0xc040)]
invalid += [pack([b'']),pack([b'\x02']),pack([b'\x02\x40\x20']),pack([b'\x02\x40\x20\x01\0']),pack([packet(64,2,b'\x01\0\x04\0')]),pack([packet(64,2,b'\0\0\x04\0x')]),pack([packet(64,2,b'x'),packet(64,2,b'\0\0\x04\0')])]
invalid += [pack(frames(cid,b'x'*1025,251)) for cid in (4,5,6,64,127)]
for wire in valid:check(wire,True)
for wire in invalid:check(wire,False)
sample=pack(frames(4,b'binary\0data',3));prefixes=0
for end in range(len(sample)):check(sample[:end]);prefixes+=1
rng=random.Random(4137);mutations=1024
seeds=[frames(4,b'a\0b',3),frames(6,bytes(range(64)),27),frames(64,b'x'*517,251),frames(0,b'x'*100,27)]
for _ in range(mutations):
    packets=[bytearray(x) for x in rng.choice(seeds)]
    for _ in range(rng.randrange(1,5)):
        frame=rng.choice(packets)
        if len(frame)>1:frame[rng.randrange(1,len(frame))]=rng.randrange(256)
    wire=pack(packets)
    if rng.randrange(4)==0:wire=wire[:rng.randrange(len(wire)+1)]
    check(wire)
report={'checks':checks,'valid_cases':len(valid),'strict_failures':len(invalid),'prefix_cases':prefixes,'mutations':mutations,'guarded_workspace':True,'guarded_input':True,'internal_rx_tx_event_canaries':True,'reference':'independent Python struct HCI/L2CAP reassembly model; no controller or RF'}
a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(report,indent=2)+'\n');print(f'PASS: {checks} BLE HCI/L2CAP reference/guard checks')
