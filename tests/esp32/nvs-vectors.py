#!/usr/bin/env python3
"""Independent namespace/typed-handle model against guarded native Flexscript."""
import argparse,copy,importlib.util,json,random,struct,subprocess
from pathlib import Path
spec=importlib.util.spec_from_file_location('settings',Path(__file__).with_name('settings-vectors.py'))
settings=importlib.util.module_from_spec(spec);spec.loader.exec_module(settings)
SIZES={1:1,17:1,2:2,18:2,4:4,20:4,8:8,24:8,33:0,66:0}
def op(code,name=b'',kind=0,mode=0,token=0,value=b''):
    return (code,name,kind,mode,token,value)
def records(namespaces):
    result={}
    for ns,values in namespaces.items():
        result[b'\0'+ns]=(254,b'')
        for key,value in values.items():result[bytes([len(ns)])+ns+key]=value
    return result
def fits(state):
    entries=records(state)
    return len(entries)<=128 and sum((8+len(k)+len(v[1])+3)&~3 for k,v in entries.items())<=4064
def valid_name(name):return 1<=len(name)<=15 and b'\0' not in name
class Model:
    def __init__(self):
        self.state={};self.saved={};self.handles={};self.next=0;self.failed=False
    def execute(self,item):
        code,name,kind,mode,token,value=item
        if code==6:self.handles.pop(token,None);return 0,0,0,b''
        if code==8:self.state=copy.deepcopy(self.saved);self.handles={};self.failed=False;return 0,0,0,b''
        if code==9:self.failed=True;return 0,0,0,b''
        if code==10:self.handles={};self.failed=False;return 0,0,0,b''
        if self.failed:return 0x110b,0,0,b''
        if code==1:
            if not valid_name(name):return 0x1106,0,0,b''
            if mode not in (0,1):return 0x102,0,0,b''
            if len(self.handles)>=4:return 0x101,0,0,b''
            if name not in self.state:
                if not mode:return 0x1102,0,0,b''
                candidate=copy.deepcopy(self.state);candidate[name]={}
                if not fits(candidate):return 0x1105,0,0,b''
                self.state=candidate
            self.next+=1;self.handles[self.next]=(name,mode)
            return 0,self.next,0,b''
        if token not in self.handles:return 0x1107,0,0,b''
        ns,rw=self.handles[token]
        if code in (2,4,5) and not rw:return 0x1104,0,0,b''
        if code==7:
            if rw:self.saved=copy.deepcopy(self.state)
            return 0,0,0,b''
        if code==5:self.state[ns]={};return 0,0,0,b''
        if code==3 and kind not in SIZES:return 0x102,0,0,b''
        if len(name)>15:return 0x1109,0,0,b''
        if not valid_name(name):return 0x1106,0,0,b''
        values=self.state[ns]
        if code==2:
            if len(value)>4096-40-1-len(ns)-len(name):return 0x110e,0,0,b''
            if kind not in SIZES or (SIZES[kind] and len(value)!=SIZES[kind]) or (kind==33 and (not value or value[-1:]!=b'\0' or b'\0' in value[:-1])):return 0x102,0,0,b''
            candidate=copy.deepcopy(self.state);candidate[ns][name]=(kind,value)
            if not fits(candidate):return 0x1105,0,0,b''
            self.state=candidate;return 0,0,0,b''
        if name not in values:return 0x1102,0,0,b''
        if code==4:del values[name];return 0,0,0,b''
        if values[name][0]!=kind:return 0x1103,0,0,b''
        return 0,0,kind,values[name][1]
class Oracle:
    def __init__(self,path):self.p=subprocess.Popen([path],stdin=subprocess.PIPE,stdout=subprocess.PIPE);self.checks=0;self.requests=0
    def read(self,n):
        result=b''
        while len(result)<n:
            chunk=self.p.stdout.read(n-len(result));assert chunk,f'native oracle exited {self.p.poll()}'
            result+=chunk
        return result
    def query(self,ops):
        wire=b'\xff'*8192+b''.join(struct.pack('<BBBBII',c,len(k),t,m,h,len(v))+k+v for c,k,t,m,h,v in ops)
        self.p.stdin.write(struct.pack('<I',len(wire))+wire);self.p.stdin.flush();assert self.read(4)==b'\0'*4
        model=Model()
        for i,item in enumerate(ops):
            error,opened,kind,length=struct.unpack('<iIII',self.read(16));actual=error,opened,kind,self.read(length)
            expected=model.execute(item)
            assert actual==expected,(self.requests,i,item,actual,expected)
            self.checks+=1
        count,used,generation,ready,failed=struct.unpack('<IIIII',self.read(20));stage=self.read(used);disk=self.read(8192)
        assert ready==1 and failed==model.failed
        assert settings.records(stage,count)==records(model.state)
        status,saved=settings.expected_mount(disk);assert status==0 and saved[1]==records(model.saved)
        self.checks+=2;self.requests+=1
    def schema(self,entries,expected):
        disk=settings.snapshot(entries,7)+b'\xff'*4096
        self.p.stdin.write(struct.pack('<I',len(disk))+disk);self.p.stdin.flush()
        result=struct.unpack('<i',self.read(4))[0]
        count,used,generation,ready,failed=struct.unpack('<IIIII',self.read(20));stage=self.read(used);after=self.read(8192)
        assert result==expected and ready==int(expected==0),(entries,result,expected,ready)
        assert settings.records(stage,count)==entries and disk==after and generation==7
        self.checks+=2;self.requests+=1
    def close(self):self.p.stdin.close();assert self.p.wait(timeout=5)==0;self.p.stdout.close()
def main():
    p=argparse.ArgumentParser();p.add_argument('--oracle',required=True);p.add_argument('--report',type=Path,required=True);args=p.parse_args()
    oracle=Oracle(args.oracle);rng=random.Random(0x4e565331)
    try:
        # Canonical KV media are independently encoded; NVS schema validation
        # must reject malformed owned records without modifying stored bytes.
        oracle.schema({b'plain':(99,b'raw'),b'\x10opaque':(99,b'raw')},0)
        for key in (b'\0',b'\0a\0',b'\0'+b'a'*16):oracle.schema({key:(254,b'')},0x110b)
        for kind,value in ((66,b''),(254,b'x'),(1,b'\0')):oracle.schema({b'\0a':(kind,value)},0x110b)
        for key in (b'\x01',b'\x01a',b'\x01a\0',b'\x01a'+b'b'*16,b'\x02a\0b'):
            oracle.schema({b'\0a':(254,b''),key:(66,b'')},0x110b)
        oracle.schema({b'\x01ab':(66,b'data')},0x110b)
        for kind in (*SIZES,99,254):
            for value in (b'',b'x',b'xx',b'xxxx',b'xxxxxxxx',b'text\0',b'x\0x\0'):
                valid=kind in SIZES and (len(value)==SIZES[kind] if SIZES.get(kind) else (kind==66 or (bool(value) and value[-1:]==b'\0' and b'\0' not in value[:-1])))
                oracle.schema({b'\0a':(254,b''),b'\x01ab':(kind,value)},0 if valid else 0x110b)
        # All namespace/key/type boundaries, without terminators at guard-page ends.
        for ns in (b'',b'x',b'0123456789abcde',b'0123456789abcdef',b'x\0y'):
            oracle.query([op(1,ns,mode=1),op(7,token=1),op(8),op(1,ns,mode=0)])
        for ns in (b'wifi',b'0123456789abcde'):
            for key in (b'',b'x',b'0123456789abcde',b'0123456789abcdef',b'x\0y'):
                for kind in (*SIZES,0,99,254):
                    for n in (0,1,2,4,8,31,600,4020,4050):
                        value=bytes((i*17+7)&255 for i in range(n))
                        if kind==33 and n:value=b'a'*(n-1)+b'\0'
                        oracle.query([op(1,ns,mode=1),op(2,key,kind,token=1,value=value),op(3,key,kind,token=1),op(7,token=1),op(8),op(1,ns,mode=0),op(3,key,kind,token=2)])
        for case in range(70):
            ops=[op(1,b'wifi',mode=1),op(1,b'ble',mode=1),op(1,b'wifi',mode=0)]
            generator=Model()
            for item in ops:generator.execute(item)
            for i in range(110):
                code=rng.choices(range(1,11),[9,30,20,10,3,5,9,4,1,1])[0]
                if not generator.handles and not generator.failed:code=1
                token=rng.choice(list(generator.handles)) if generator.handles and rng.random()<.8 else rng.randrange(0,20)
                key=rng.choice([b'wifi',b'ble',b'app',b'x',b'0123456789abcde']) if code==1 else rng.choice([b'x',b'y',b'z',b'count',b'blob',b'',b'a'*16,b'a\0b'])
                kind=rng.choice(list(SIZES)+[99]);n=SIZES.get(kind,0) or rng.choice([0,1,15,200,600,4000]);value=rng.randbytes(n) if code==2 else b''
                if code==2 and kind==33:value=b'x'*(max(1,n)-1)+b'\0'
                item=op(code,key,kind,rng.choice([0,1,1,1,2]),token,value);ops.append(item);generator.execute(item)
            oracle.query(ops)
        # Capacity and handle pressure, plus commits shared across handles.
        for mode in (0,1):
            ops=[op(1,b'wifi',mode=1),op(1,b'ble',mode=1),op(1,b'wifi',mode=mode),op(1,b'app',mode=1),op(1,b'full',mode=1)]
            for i in range(140):ops.append(op(2,f'k{i}'.encode(),66,token=1,value=b'x'*23))
            ops += [op(7,token=3),op(8),op(1,b'wifi',mode=0),op(1,b'ble',mode=1),op(5,token=6),op(7,token=6),op(8)]
            oracle.query(ops)
    finally:oracle.close()
    report={'checks':oracle.checks,'requests':oracle.requests,'seed':'0x4e565331','guarded':['request end','KV workspace end','NVS workspace end'],'canaries':['KV prefix64','NVS prefix64'],'scope':'namespace/type/opaque handle model, capacity, RO, close, shared commit, reload, failure/reinit; native NOR backend'}
    args.report.write_text(json.dumps(report,indent=2)+'\n');print(f'NVS independent reference: {oracle.checks} checks in {oracle.requests} requests passed')
if __name__=='__main__':main()
