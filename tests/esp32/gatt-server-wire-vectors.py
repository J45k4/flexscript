#!/usr/bin/env python3
"""Independent ATT wire reference and guarded-parser mutations; no RF claims."""
import argparse,copy,dataclasses,json,random,struct,subprocess
from pathlib import Path
U16=lambda n:struct.pack('<H',n)
R16=lambda b:struct.unpack('<H',b)[0]
BASE=bytes.fromhex('fb349b5f8000008000100000')
def canonical(uuid):
    return BASE+uuid+b'\0\0' if len(uuid)==2 else uuid
@dataclasses.dataclass
class Attribute:
    uuid:bytes
    value:bytes
    capacity:int
    permissions:int=1
    kind:str='plain'
    properties:int=0
    fixed:bool=False
    end:int=0
    related:int=0
    minimum_key:int=0
class Reference:
    def __init__(self,long_types=False):
        self.a={};self.mtu=23;self.prepared=[];self.pending_bytes=0
        def add(h,uuid,value,capacity=None,**kw):
            self.a[h]=Attribute(U16(uuid) if isinstance(uuid,int) else uuid,value,len(value) if capacity is None else capacity,**kw)
        add(1,0x2800,U16(0x1800),kind='service',fixed=True,end=3)
        add(2,0x2803,b'\2'+U16(3)+U16(0x2a00),fixed=True)
        add(3,0x2a00,b'Flexscript',64,properties=2)
        add(4,0x2800,bytes(range(16)),kind='service',fixed=True,end=18)
        custom=bytes([16])+bytes(range(1,16))
        add(5,0x2803,bytes([62])+U16(6)+custom,fixed=True)
        add(6,custom,b'abc',512,permissions=3,properties=62)
        add(7,0x2902,b'\0\0',permissions=3,kind='cccd',fixed=True,related=6)
        add(8,0x2901,b'Value')
        add(9,0x2803,b'\x08'+U16(10)+U16(0xff01),fixed=True)
        add(10,0xff01,b'secret',16,permissions=2,properties=8)
        add(11,0x2803,b'\2'+U16(12)+U16(0xff02),fixed=True)
        add(12,0xff02,b'locked',16,permissions=85,properties=2,minimum_key=16)
        add(13,0x2803,b'\x0a'+U16(14)+U16(0xff03),fixed=True)
        add(14,0xff03,b'ABCD',4,permissions=3,properties=10,fixed=True)
        add(15,0x2803,bytes([138])+U16(16)+U16(0xff04),fixed=True)
        add(16,0xff04,b'',16,permissions=3,properties=138)
        add(17,0x2900,U16(3),fixed=True)
        add(18,0x2901,b'Label',16,permissions=3)
        add(19,0x2800,U16(0x1801),kind='service',fixed=True,end=22)
        add(20,0x2803,b'\x20'+U16(21)+U16(0x2a05),fixed=True)
        add(21,0x2a05,b'\1\0\xff\xff',4,permissions=0,properties=32,fixed=True)
        add(22,0x2902,b'\0\0',permissions=3,kind='cccd',fixed=True,related=21)
        if long_types:
            self.a[19].end=26
            add(23,0x2803,b'\2'+U16(24)+U16(0xff05),fixed=True)
            add(24,0xff05,bytes(range(256))*2,512,properties=2)
            add(25,0x2803,b'\2'+U16(26)+U16(0xff05),fixed=True)
            add(26,0xff05,(bytes(range(256))*2)[:511],511,properties=2)
    @staticmethod
    def error(op,handle,code):return bytes([1,op])+U16(handle)+bytes([code])
    @staticmethod
    def permission(a,security,write=False):
        bits=a.permissions
        if not bits&(2 if write else 1):return 3 if write else 2
        if bits&(32 if write else 16) and not security&2:return 5
        if bits&(128 if write else 64) and not security&4:return 8
        if bits&(8 if write else 4) and not security&1:return 15
        if bits&(40 if write else 20) and security>>8<a.minimum_key:return 12
        return 0
    def cccd_ok(self,a,value):
        props=self.a[a.related].properties
        allowed=(1 if props&16 else 0)|(2 if props&32 else 0)
        return len(value)==2 and not R16(value)&~allowed
    @staticmethod
    def apply(a,offset,value):
        previous=a.value
        if a.fixed:a.value=previous[:offset]+value+previous[offset+len(value):]
        elif not offset:a.value=value
        else:a.value=previous[:offset]+value+previous[offset+len(value):]
    def input(self,pdu,security=0):
        op=pdu[0];err=lambda handle,code:self.error(op,handle,code)
        if op==30:return b''
        if op==0xd2 or op&64 and op!=0x52 or op&1:return b''
        if len(pdu)>self.mtu:return b'' if op==0x52 else err(0,4)
        if op==2:
            if len(pdu)!=3 or R16(pdu[1:])<23:return err(0,4)
            self.mtu=min(517,R16(pdu[1:]));return b'\3'+U16(517)
        if op in (4,6,8,16):
            if len(pdu)<5:return err(0,4)
            first,last=struct.unpack('<HH',pdu[1:5])
            if not first or first>last:return err(first,1)
            if op==4 and len(pdu)!=5:return err(0,4)
            if op==6 and len(pdu)<7:return err(0,4)
            if op in (8,16) and len(pdu) not in (7,21):return err(0,4)
            query=pdu[5:]
            if op==16 and canonical(query) not in (canonical(U16(0x2800)),canonical(U16(0x2801))):return err(first,16)
            candidates=[(h,a) for h,a in self.a.items() if first<=h<=last]
            if op==6:
                candidates=[(h,a) for h,a in candidates if canonical(a.uuid)==canonical(query[:2]) and (canonical(a.value)==canonical(query[2:]) if a.kind=='service' else a.value==query[2:])]
                rows=[U16(h)+U16(a.end if a.kind=='service' else h) for h,a in candidates]
                return b'\7'+b''.join(rows[:(self.mtu-1)//4]) if rows else err(first,10)
            if op!=4:candidates=[(h,a) for h,a in candidates if canonical(a.uuid)==canonical(query)]
            if not candidates:return err(first,10)
            if op==4:
                width=len(candidates[0][1].uuid);rows=[]
                for h,a in candidates:
                    if len(a.uuid)!=width or 2+sum(map(len,rows))+width+2>self.mtu:break
                    rows.append(U16(h)+a.uuid)
                return bytes([5,1 if width==2 else 2])+b''.join(rows)
            rows=[];first_size=len(candidates[0][1].value);header=4 if op==16 else 2
            for h,a in candidates:
                failure=self.permission(a,security)
                if failure:
                    if not rows:return err(h,failure)
                    break
                if len(a.value)!=first_size:break
                value=a.value[:min(self.mtu-2-header,255-header)]
                row=U16(h)+(U16(a.end) if op==16 else b'')+value
                if 2+sum(map(len,rows))+len(row)>self.mtu:break
                rows.append(row)
            return bytes([op+1,len(rows[0])])+b''.join(rows)
        if op in (10,12):
            if len(pdu)!=(3 if op==10 else 5):return err(0,4)
            h=R16(pdu[1:3]);a=self.a.get(h)
            if a is None:return err(h,1)
            failure=self.permission(a,security)
            if failure:return err(h,failure)
            offset=0 if op==10 else R16(pdu[3:])
            return err(h,7) if offset>len(a.value) else bytes([op+1])+a.value[offset:offset+self.mtu-1]
        if op in (14,32):
            if len(pdu)<5 or not len(pdu)&1:return err(0,4)
            handles=struct.unpack('<'+'H'*((len(pdu)-1)//2),pdu[1:])
            for h in handles:
                if h not in self.a:return err(h,1)
                failure=self.permission(self.a[h],security)
                if failure:return err(h,failure)
            out=bytes([op+1])
            for h in handles:
                value=self.a[h].value
                if op==32:
                    if len(out)+2>self.mtu:break
                    out+=U16(len(value))
                out+=value[:self.mtu-len(out)]
                if len(out)==self.mtu:break
            return out
        if op in (18,0x52,22):
            minimum=5 if op==22 else 3
            if len(pdu)<minimum:return b'' if op==0x52 else err(0,4)
            h=R16(pdu[1:3]);a=self.a.get(h);failure=1 if a is None else self.permission(a,security,True)
            if a is not None and not failure and a.properties and not a.properties&(4 if op==0x52 else 8):failure=3
            if failure:return b'' if op==0x52 else err(h,failure)
            value=pdu[minimum:]
            if op==22:
                if len(self.prepared)==32 or self.pending_bytes+len(value)>1024:return err(h,9)
                self.prepared.append((h,R16(pdu[3:5]),value,security));self.pending_bytes+=len(value)
                return bytes([23])+pdu[1:]
            if len(value)>a.capacity:return b'' if op==0x52 else err(h,13)
            if a.kind=='cccd' and not self.cccd_ok(a,value):return b'' if op==0x52 else err(h,13 if len(value)!=2 else 19)
            self.apply(a,0,value)
            return b'' if op==0x52 else bytes([19])
        if op==24:
            if len(pdu)!=2 or pdu[1]>1:return err(0,4)
            queue=self.prepared;self.prepared=[];self.pending_bytes=0
            if not pdu[1]:return bytes([25])
            proposed=copy.deepcopy(self.a)
            for h,offset,value,original_security in queue:
                a=proposed[h];failure=self.permission(a,security,True) or self.permission(a,original_security,True)
                if not failure and offset>len(a.value):failure=7
                if not failure and offset+len(value)>a.capacity:failure=13
                if failure:return err(h,failure)
                self.apply(a,offset,value)
            for h,_,_,_ in queue:
                a=proposed[h]
                if a.kind=='cccd' and not self.cccd_ok(a,a.value):return err(h,19)
            self.a=proposed;return bytes([25])
        return err(0,6)
def encode(records):return b''.join(U16(len(pdu))+U16(sec)+pdu for pdu,sec in records)
def decode(output):
    result=[];offset=0
    while offset<len(output):
        assert offset+2<=len(output),'short output header'
        n=R16(output[offset:offset+2]);offset+=2
        assert n<=517 and offset+n<=len(output),'invalid output boundary'
        result.append(output[offset:offset+n]);offset+=n
    return result

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--oracle',required=True);parser.add_argument('--report',required=True);args=parser.parse_args()
    counts={'valid_cases':0,'strict_failures':0,'prefix_cases':0,'mutations':0}
    def run(records,category='valid_cases',exact=True,long_types=False):
        wire=encode(records);r=subprocess.run([args.oracle]+(["long-types"] if long_types else []),input=wire,capture_output=True,timeout=3)
        assert r.returncode in (0,1),(category,r.returncode,r.stderr[-200:],wire[:64].hex())
        response=decode(r.stdout)
        if exact:
            ref=Reference(long_types);expected=[ref.input(pdu,sec) for pdu,sec in records]
            assert r.returncode==0 and response==expected,(category,[(p.hex(),s) for p,s in records],r.returncode,[p.hex() for p in response],[p.hex() for p in expected],r.stderr)
        counts[category]+=1
    for mtu in (23,24,64,128,247,517):
        prefix=[(b'\2'+U16(mtu),0)]
        for h in range(25):
            run(prefix+[(b'\x0a'+U16(h),0)])
            for offset in (0,1,3,10,512,513):run(prefix+[(b'\x0c'+U16(h)+U16(offset),0)])
        for uuid in (U16(0x2800),U16(0x2801),U16(0x2803),U16(0xff02),bytes([16])+bytes(range(1,16)),canonical(U16(0x2a00))):
            for first,last in ((0,65535),(1,0),(1,65535),(4,18),(19,22),(23,65535)):
                for op in (8,16):run(prefix+[(bytes([op])+U16(first)+U16(last)+uuid,0)])
        for h in (6,14,16,7):
            for length in (0,1,2,3,20,40,128,512,513):
                value=bytes((i*17+3)&255 for i in range(length));run(prefix+[(b'\x12'+U16(h)+value,0),(b'\x0a'+U16(h),0)])
        for handles in ((3,8),(6,3),(3,10),(3,0),(3,12),(7,22)):
            for op in (14,32):run(prefix+[(bytes([op])+b''.join(U16(h) for h in handles),0)])
    for security in (0,1,3,4,7,1|7<<8,3|16<<8,7|7<<8,7|16<<8):run([(b'\x0a'+U16(12),security)])
    value=bytes(range(256))*2
    long=[(b'\x16'+U16(6)+U16(i)+value[i:i+18],0) for i in range(0,512,18)]+[(b'\x18\1',0)]+[(b'\x0c'+U16(6)+U16(i),0) for i in range(0,513,22)]
    run(long)
    prepared=long[:30]
    run(prepared+[(bytes.fromhex('2006000300'),0)])
    run(prepared+[(b'\2'+U16(517),0),(bytes.fromhex('2006000300'),0)])
    run([(b'\2'+U16(517),0),(bytes.fromhex('080100ffff05ff'),0)],long_types=True)
    run([(b'\2'+U16(517),0),(bytes.fromhex('081900ffff05ff'),0)],long_types=True)
    run([(b'\x16'+U16(6)+U16(0),0)]*33+[(b'\x18\1',0),(b'\x0a'+U16(6),0)])
    run([(b'\2'+U16(517),0),(b'\x16'+U16(6)+U16(0)+value,0),(b'\x16'+U16(6)+U16(512)+value,0),(b'\x16'+U16(6)+U16(0)+b'x',0),(b'\x18\1',0),(b'\x0a'+U16(6),0)])
    for flags in (0,1,2):run([(b'\x16'+U16(6)+U16(0)+b'new',0),(b'\x16'+U16(14)+U16(4)+b'bad',0),(b'\x18'+bytes([flags]),0),(b'\x0a'+U16(6),0)])
    run([(b'\x16'+U16(7)+U16(0)+b'\3',0),(b'\x16'+U16(7)+U16(1)+b'\0',0),(b'\x18\1',0),(b'\x0a'+U16(7),0)])
    run([(b'\x16'+U16(7)+U16(0)+b'\xff\0',0),(b'\x18\1',0),(b'\x0a'+U16(7),0)])
    rng=random.Random(0x47415454)
    for _ in range(64):
        records=[]
        for _ in range(12):
            op=rng.choice((10,12,18,0x52,22,24));h=rng.choice((3,6,7,10,12,14,16,18,22,0,65535));body=bytes(rng.randrange(256) for _ in range(rng.randrange(0,21)))
            if op==24:pdu=bytes([op,rng.randrange(3)])
            elif op==10:pdu=bytes([op])+U16(h)
            elif op==12:pdu=bytes([op])+U16(h)+U16(rng.randrange(20))
            elif op==22:pdu=bytes([op])+U16(h)+U16(rng.randrange(20))+body[:18]
            else:pdu=bytes([op])+U16(h)+body
            records.append((pdu,0))
        run(records)
    seeds=[bytes.fromhex(h) for h in ('020502','040100ffff','060100ffff00280018','080100ffff0328','0a0600','0c06000100','0e03000800','100100ffff0028','120600616263','1606000000616263','1801','2003000800','1e','d20600')]
    for seed in seeds:
        for end in range(1,len(seed)):run([(seed[:end],0)],'prefix_cases')
    for wire in (b'\0',b'\0\0',b'\1\0\0',b'\5\0\0\0\x0a',b'\0\0\0\0',U16(1)+U16(8)+b'\x0a',U16(518)+U16(0)+b'\x52'*518):
        r=subprocess.run([args.oracle],input=wire,capture_output=True,timeout=3);assert r.returncode==1,(r.returncode,r.stderr);counts['strict_failures']+=1
    for _ in range(2048):
        pdu=bytearray(rng.choice(seeds))
        for _ in range(rng.randrange(1,4)):
            action=rng.randrange(3)
            if action==0 and pdu:pdu[rng.randrange(len(pdu))]=rng.randrange(256)
            elif action==1 and pdu:del pdu[rng.randrange(len(pdu))]
            else:pdu.insert(rng.randrange(len(pdu)+1),rng.randrange(256))
        run([(bytes(pdu),0)],'mutations',exact=False)
    report={**counts,'checks':sum(counts.values()),'guarded_input':True,'guarded_workspace':True,'internal_output_value_prepare_event_canaries':True,'reference':'independent Python struct/attribute-database model and atomic copy-on-commit transactions; no RF'}
    Path(args.report).write_text(json.dumps(report,indent=2)+'\n');print('PASS:',report['checks'],'GATT ATT reference/guard checks')
if __name__=='__main__':main()
