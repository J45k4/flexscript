#!/usr/bin/env python3
"""Independent TCP checksum, header and byte-stream fixtures."""
from pathlib import Path
import struct,ipaddress
u16=lambda n:struct.pack('!H',n)
ip=lambda s:ipaddress.IPv4Address(s).packed
CLIENT=bytes.fromhex('020000000002');PEER=bytes.fromhex('020000000001')
def checksum(b):
 if len(b)&1:b+=b'\0'
 n=sum(struct.unpack('!'+str(len(b)//2)+'H',b))
 while n>>16:n=(n&65535)+(n>>16)
 return (~n)&65535

def packet(seq,ack,flags=16,body=b'',window=4096,options=b'',sp=8080,dp=50000,out=False,ident=123):
 src,dst=('10.0.0.1','10.0.0.2') if not out else ('10.0.0.2','10.0.0.1')
 h=struct.pack('!HHIIBBHHH',sp,dp,seq&0xffffffff,ack&0xffffffff,((20+len(options))//4)<<4,flags,window,0,0)+options
 pseudo=ip(src)+ip(dst)+bytes([0,6])+u16(len(h)+len(body));h=h[:16]+u16(checksum(pseudo+h+body))+h[18:]
 ipv4=struct.pack('!BBHHHBBH4s4s',0x45,0,20+len(h)+len(body),ident,0x4000,64,6,0,ip(src),ip(dst));ipv4=ipv4[:10]+u16(checksum(ipv4))+ipv4[12:]
 return (CLIENT+PEER if not out else PEER+CLIENT)+b'\x08\x00'+ipv4+h+body
C=0xfffffff0;S=0x12345678
v={
 'expect_syn':packet(C,0,2,window=2048,options=bytes.fromhex('020405b4'),sp=50000,dp=8080,out=True,ident=1),
 'syn_ack':packet(S,C+1,18,options=bytes.fromhex('0204040001010402')),
 'bad_syn_ack':packet(S,C,18),
 'ack_partial':packet(S+1,C+9),
 'ack_full':packet(S+1,1),
 'data':packet(S+1,1,24,b'world\0tcp'),
 'out_of_order':packet(S+13,1,24,b'future'),
 'overlap':packet(S+8,1,24,b'cpnext'),
 'zero_window':packet(S+14,1,window=0),
 'window_four':packet(S+14,1,window=4),
 'ack_four_zero':packet(S+14,5,window=0),
 'peer_fin':packet(S+14,5,17),
 'last_ack':packet(S+15,6),
 'new_syn_ack':packet(1000,101,18),
 'fin_ack':packet(1001,102,17),
 'timewait_rst':packet(1002,102,4),
 'listen_syn':packet(9000,0,2,sp=40000,dp=4243,options=bytes.fromhex('02040218')),
 'listen_ack':packet(9001,501,sp=40000,dp=4243),
 'listen_rst_challenge':packet(9002,501,4,sp=40000,dp=4243),
 'listen_rst_exact':packet(9001,501,4,sp=40000,dp=4243),
 'ack_unsent':packet(1001,105),
 'window_zero_101':packet(1001,101,window=0),
 'probe_ack_one':packet(1001,102,window=0),
 'window_two_102':packet(1001,102,window=2),
 'ack_two_104':packet(1001,104,window=2),
 'ack_one_105':packet(1001,105,window=2),
 'sim_syn':packet(1000,0,2),
 'sim_ack':packet(1001,101),
 'rx_big_first':packet(1001,101,24,bytes(i&255 for i in range(1460))),
 'rx_big_last':packet(2461,101,24,bytes(i&255 for i in range(1460,2048))),
 'rx_full_fin':packet(3049,101,17),
}
bad=bytearray(v['syn_ack']);bad[-1]^=1;v['bad_checksum']=bytes(bad)
bad=bytearray(v['syn_ack']);bad[46]=0xf0;bad[50:52]=b'\0\0';bad[50:52]=u16(checksum(ip('10.0.0.1')+ip('10.0.0.2')+bytes([0,6])+u16(len(bad)-34)+bad[34:]));v['bad_offset']=bytes(bad)
lines=['// Generated independently by tcp-vectors.py.','global tv_buffer=0;','global tv_size=0;','fn tv_hex(c){if c>=48 && c<=57{return c-48;}return c-87;}','fn tv_decode(t){if !tv_buffer{tv_buffer=alloc(1536);}let i=0;tv_size=0;while load8(t+i){store8(tv_buffer+tv_size,(tv_hex(load8(t+i))<<4)|tv_hex(load8(t+i+1)));tv_size=tv_size+1;i=i+2;}return tv_buffer;}']
for k,b in v.items():lines.append('fn tv_'+k+'(){return tv_decode("'+b.hex()+'");}')
Path(__file__).with_suffix('.flex').write_text('\n'.join(lines)+'\n');print('Generated',len(v),'independent TCP wire fixtures.')
