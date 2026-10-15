"""Independent check: exposing the pinned WPA lock changes no allocated bytes."""
import struct,sys,hashlib,json
from pathlib import Path

def members(path):
 data=Path(path).read_bytes();assert data[:8]==b'!<arch>\n';p=8;names=b'';out={}
 while p<len(data):
  h=data[p:p+60];assert len(h)==60 and h[58:]==b'`\n';name=h[:16].decode().strip();size=int(h[48:58]);b=data[p+60:p+60+size];assert len(b)==size;p+=60+size+(size&1)
  if name=='//':names=b;continue
  if name=='/':continue
  if name.startswith('/'):
   off=int(name[1:]);end=names.index(b'/\n',off);name=names[off:end].decode()
  else:name=name.rstrip('/')
  assert name not in out;out[name]=b
 return out

def sections(data):
 assert data[:6]==b'\x7fELF\x01\x01';off=struct.unpack_from('<I',data,32)[0];size,count,strings=struct.unpack_from('<HHH',data,46);assert size==40
 sh=[struct.unpack_from('<10I',data,off+i*size) for i in range(count)];ns=sh[strings];names=data[ns[4]:ns[4]+ns[5]];out={}
 for s in sh:
  if not s[2]&2:continue
  name=names[s[0]:names.index(0,s[0])].decode();value=b'' if s[1]==8 else data[s[4]:s[4]+s[5]];assert name not in out;out[name]=(s[1],s[2],s[3],s[5],s[8],s[9],value)
 return out

a=members(sys.argv[1]);b=members(sys.argv[2]);assert a.keys()==b.keys();count=0;changed=[]
for name,old in a.items():
 assert sections(old)==sections(b[name]),name;count+=len(sections(old))
 if old!=b[name]:changed.append(name)
print(json.dumps({'pass':True,'members':len(a),'allocated_sections_identical':count,'members_with_metadata_changes':changed,'original_sha256':hashlib.sha256(Path(sys.argv[1]).read_bytes()).hexdigest(),'derived_sha256':hashlib.sha256(Path(sys.argv[2]).read_bytes()).hexdigest()},indent=2))
