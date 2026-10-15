#!/usr/bin/env python3
"""Independent DNS-over-TCP framing and transport fixtures."""
from pathlib import Path
import struct,ipaddress
u16=lambda n:struct.pack('!H',n)
ip=lambda s:ipaddress.IPv4Address(s).packed
def checksum(b):
 if len(b)&1:b+=b'\0'
 n=sum(struct.unpack('!'+str(len(b)//2)+'H',b))
 while n>>16:n=(n&65535)+(n>>16)
 return (~n)&65535

def packet(seq,ack,flags=16,body=b'',sp=53,dp=50535,source='8.8.8.8'):
 h=struct.pack('!HHIIBBHHH',sp,dp,seq,ack,0x50,flags,4096,0,0)
 h=h[:16]+u16(checksum(ip(source)+ip('10.0.0.2')+bytes([0,6])+u16(20+len(body))+h+body))+h[18:]
 v=struct.pack('!BBHHHBBH4s4s',0x45,0,40+len(body),123,0x4000,64,6,0,ip(source),ip('10.0.0.2'));v=v[:10]+u16(checksum(v))+v[12:]
 return bytes.fromhex('0200000000020200000000010800')+v+h+body
Q=b'\x07example\x03com\0'+u16(1)+u16(1)
def answer(ident=0x4567,address='93.184.215.14'):
 p=struct.pack('!HHHHHH',ident,0x8180,1,1,0,0)+Q+b'\xc0\x0c'+struct.pack('!HHIH',1,1,60,4)+ip(address)
 return u16(len(p))+p
reply=answer();v={'syn_ack':packet(1000,101,18),'prefix_one':packet(1001,132,24,reply[:1]),'prefix_two_header':packet(1002,132,24,reply[1:11]),'answer_rest':packet(1012,132,24,reply[11:]),'app_data':packet(888,778,24,b'OK',sp=8080,dp=50000,source='10.0.0.1'),'oversize':packet(1095,163,24,u16(4097)),'second_answer':packet(1048,163,24,answer(address='1.1.1.1'))}
lines=['// Generated independently by dns-tcp-vectors.py.','global dv_buffer=0;','global dv_size=0;','fn dv_hex(c){if c>=48 && c<=57{return c-48;}return c-87;}','fn dv_decode(t){if !dv_buffer{dv_buffer=alloc(1536);}let i=0;dv_size=0;while load8(t+i){store8(dv_buffer+dv_size,(dv_hex(load8(t+i))<<4)|dv_hex(load8(t+i+1)));dv_size=dv_size+1;i=i+2;}return dv_buffer;}']
for k,b in v.items():lines.append('fn dv_'+k+'(){return dv_decode("'+b.hex()+'");}')
Path(__file__).with_suffix('.flex').write_text('\n'.join(lines)+'\n');print('Generated',len(v),'independent DNS/TCP fixtures.')
