#!/usr/bin/env python3
"""Independent protocol fixtures from Python struct/ipaddress, no firmware code."""
import ipaddress, struct
from pathlib import Path
CLIENT=bytes.fromhex('020000000002'); ROUTER=bytes.fromhex('020000000001'); BROADCAST=b'\xff'*6
ip=lambda value:ipaddress.IPv4Address(value).packed
u16=lambda value:struct.pack('!H',value)
u32=lambda value:struct.pack('!I',value)
def checksum(data):
    if len(data)%2:data+=b'\0'
    total=sum(struct.unpack('!'+str(len(data)//2)+'H',data))
    while total>>16:total=(total&65535)+(total>>16)
    return (~total)&65535

def ipv4(payload,protocol=17,source='10.0.0.1',target='10.0.0.2',options=b'',fragment=0x4000,dest=CLIENT,ident=123):
    header=struct.pack('!BBHHHBBH4s4s',0x45+len(options)//4,0,20+len(options)+len(payload),ident,fragment,64,protocol,0,ip(source),ip(target))+options
    header=header[:10]+u16(checksum(header))+header[12:]
    return dest+ROUTER+b'\x08\x00'+header+payload

def udp(payload,sp=5555,dp=9000,source='10.0.0.1',target='10.0.0.2',**kwargs):
    length=8+len(payload);header=struct.pack('!HHHH',sp,dp,length,0)
    pseudo=ip(source)+ip(target)+bytes([0,17])+u16(length)
    header=header[:6]+u16(checksum(pseudo+header+payload) or 65535)
    return ipv4(header+payload,source=source,target=target,**kwargs)

def arp(op):
    payload=struct.pack('!HHBBH',1,0x0800,6,4,op)+ROUTER+ip('10.0.0.1')+(b'\0'*6 if op==1 else CLIENT)+ip('10.0.0.2')
    return (BROADCAST if op==1 else CLIENT)+ROUTER+b'\x08\x06'+payload

def option(code,data):return bytes([code,len(data)])+data

def dhcp(kind,lease=120,xid=0x12345678,extra=b'',overload=False,broken=False):
    payload=bytearray(240);payload[0:3]=bytes([2,1,6]);payload[4:8]=u32(xid);payload[16:20]=ip('10.0.0.2');payload[28:34]=CLIENT;payload[236:240]=bytes.fromhex('63825363')
    options=option(53,bytes([kind]))+option(54,ip('10.0.0.1'))
    if kind!=6:
        options+=option(1,ip('255.255.255.0'))+option(3,ip('10.0.0.1'))+option(51,u32(lease))+option(58,u32(lease//2))+option(59,u32(lease*7//8))
        if overload:
            options+=option(52,b'\x01');other=option(6,ip('8.8.4.4'))+b'\xff';payload[108:108+len(other)]=other
        else:options+=option(6,ip('8.8.8.8'))
    options+=extra
    if broken:options+=bytes([1,4,255,255])
    else:options+=b'\xff'
    return udp(bytes(payload)+options,sp=67,dp=68,target='255.255.255.255',dest=BROADCAST)

def name(value):return b''.join(bytes([len(label)])+label.encode() for label in value.split('.'))+b'\0'
Q=name('example.com')+u16(1)+u16(1)
def dns(records=b'',count=0,flags=0x8180,additional=b'',arcount=0,source='8.8.8.8'):
    payload=struct.pack('!HHHHHH',0x4567,flags,1,count,0,arcount)+Q+records+additional
    return udp(payload,sp=53,dp=49152+(0x4567&16383),source=source)
def record(owner,kind,data,ttl=60):return owner+struct.pack('!HHIH',kind,1,ttl,len(data))+data

vectors={'arp_request':arp(1),'arp_reply':arp(2),'udp':udp(b'hello\0odd'),'udp_options':udp(b'hello\0odd',options=b'\x01\x01\0\0'),'fragment':udp(b'hello\0odd',fragment=0x2000)}
bad=bytearray(vectors['udp']);bad[-1]^=1;vectors['udp_bad_checksum']=bytes(bad)
bad=bytearray(vectors['udp']);bad[16]^=1;vectors['ip_bad_checksum']=bytes(bad)
echo=bytes([8,0,0,0])+u16(0x1234)+u16(1)+b'abc';echo=echo[:2]+u16(checksum(echo))+echo[4:];vectors['echo']=ipv4(echo,protocol=1)
for key,kwargs in {'offer':{'kind':2},'ack':{'kind':5},'renew_ack':{'kind':5,'lease':240},'nak':{'kind':6},'wrong_xid':{'kind':2,'xid':0x87654321},'bad_option':{'kind':5,'broken':True},'overload_ack':{'kind':5,'overload':True},'conflicting_server':{'kind':5,'extra':option(54,ip('10.0.0.3'))}}.items():vectors[key]=dhcp(**kwargs)
a=record(b'\xc0\x0c',1,ip('93.184.215.14'))
vectors['dns_a']=dns(a,1);vectors['dns_wrong_peer']=dns(a,1,source='8.8.4.4')
real=name('real.example.com');vectors['dns_cname']=dns(record(real,1,ip('93.184.215.14'),90)+record(b'\xc0\x0c',5,b'\xc0\x1d',30),2)
# A compression pointer pointing at itself is not a valid prior-name pointer.
pos=12+len(Q)+12;vectors['dns_loop']=dns(record(b'\xc0\x0c',5,u16(0xc000|pos)),1)
vectors['dns_bad_additional']=dns(a,1,additional=b'\xc0\x0c'+struct.pack('!HHIH',1,1,60,4)+b'\x01\x02\x03',arcount=1)
vectors['dns_truncated']=dns(a,1,flags=0x8380);vectors['dns_nxdomain']=dns(flags=0x8183)
# Fragments are independently split from checksum-valid transport payloads.
transport=vectors['udp'][34:]
def frag(key,start,end,more=True,body=transport,**kwargs):
    vectors[key]=ipv4(body[start:end],fragment=(0x2000 if more else 0)|start//8,**kwargs)
frag('frag_first',0,8);frag('frag_middle',8,16);frag('frag_last',16,17,False)
frag('frag_overlap',8,17,False);frag('frag_first16',0,16)
frag('frag_bad_multiple',0,9);frag('frag_other_key',0,8,ident=124)
frag('frag_options_first',0,8,options=b'\x01\x01\0\0')
frag('frag_bad_df',0,8);bad=bytearray(vectors['frag_bad_df']);bad[20:22]=u16(0x6000);bad[24:26]=b'\0\0';bad[24:26]=u16(checksum(bad[14:34]));vectors['frag_bad_df']=bytes(bad)
vectors['frag_beyond_limit']=ipv4(b'12345678',fragment=0x2000|185)
vectors['frag_past_final']=ipv4(b'12345678',fragment=0x2000|3)
big=bytes(i&255 for i in range(1472));bigtransport=udp(big)[34:]
frag('frag_big_first',0,512,body=bigtransport);frag('frag_big_middle',512,1024,body=bigtransport);frag('frag_big_last',1024,1480,False,body=bigtransport)
frag('frag_echo_first',0,8,body=echo,protocol=1);frag('frag_echo_last',8,11,False,body=echo,protocol=1)
# ACD peers use their own MAC; probes carry an all-zero sender IPv4 address.
def acd_arp(source,target,mac=ROUTER,op=1):
    return BROADCAST+mac+b'\x08\x06'+struct.pack('!HHBBH',1,0x0800,6,4,op)+mac+ip(source)+b'\0'*6+ip(target)
vectors['acd_claim']=acd_arp('10.0.0.2','10.0.0.1',op=2)
vectors['acd_probe']=acd_arp('0.0.0.0','10.0.0.2')
vectors['acd_self']=acd_arp('10.0.0.2','10.0.0.2',mac=CLIENT)
vectors['acd_unrelated']=acd_arp('10.0.0.1','10.0.0.2')
lines=['// Generated by network-vectors.py using independent Python packet/checksum logic.','global nv_buffer=0;','global nv_size=0;','fn nv_hex(c){if c>=48 && c<=57{return c-48;}return c-87;}','fn nv_decode(text){if !nv_buffer{nv_buffer=alloc(1536);}let i=0;nv_size=0;while load8(text+i){store8(nv_buffer+nv_size,(nv_hex(load8(text+i))<<4)|nv_hex(load8(text+i+1)));nv_size=nv_size+1;i=i+2;}return nv_buffer;}']
for key,value in vectors.items():lines.append(f'fn nv_{key}(){{return nv_decode("{value.hex()}");}}')
Path(__file__).with_suffix('.flex').write_text('\n'.join(lines)+'\n')
print('Generated',len(vectors),'independent Ethernet/IP/DHCP/DNS fixtures.')
