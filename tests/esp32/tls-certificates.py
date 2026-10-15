#!/usr/bin/env python3
"""Create ephemeral OpenSSL-interoperability certificates; keys stay in scratch."""
from pathlib import Path
from datetime import datetime, timezone
import argparse
from cryptography import x509
from cryptography.x509.oid import NameOID, ExtendedKeyUsageOID
from cryptography.hazmat.primitives import serialization, hashes
from cryptography.hazmat.primitives.asymmetric import ec, rsa
p=argparse.ArgumentParser();p.add_argument('output',type=Path);a=p.parse_args();out=a.output;out.mkdir(parents=True,exist_ok=True)
start=datetime(2024,1,1,tzinfo=timezone.utc);end=datetime(2030,1,1,tzinfo=timezone.utc)
def name(s):return x509.Name([x509.NameAttribute(NameOID.COMMON_NAME,s)])
def keyfile(path,key):path.write_bytes(key.private_bytes(serialization.Encoding.PEM,serialization.PrivateFormat.PKCS8,serialization.NoEncryption()));path.chmod(0o600)
ca_key=ec.generate_private_key(ec.SECP384R1());ca_name=name('Flexscript temporary test CA')
ca=(x509.CertificateBuilder().subject_name(ca_name).issuer_name(ca_name).public_key(ca_key.public_key()).serial_number(x509.random_serial_number()).not_valid_before(start).not_valid_after(datetime(2400,1,1,tzinfo=timezone.utc)).add_extension(x509.BasicConstraints(ca=True,path_length=0),True).add_extension(x509.KeyUsage(False,False,False,False,False,True,True,False,False),True).sign(ca_key,hashes.SHA384()))
(out/'ca.der').write_bytes(ca.public_bytes(serialization.Encoding.DER));(out/'ca.pem').write_bytes(ca.public_bytes(serialization.Encoding.PEM))
for kind,key in [('ecdsa',ec.generate_private_key(ec.SECP256R1())),('rsa',rsa.generate_private_key(public_exponent=65537,key_size=2048))]:
 cert=(x509.CertificateBuilder().subject_name(name('esp32.test')).issuer_name(ca_name).public_key(key.public_key()).serial_number(x509.random_serial_number()).not_valid_before(start).not_valid_after(end).add_extension(x509.BasicConstraints(ca=False,path_length=None),True).add_extension(x509.SubjectAlternativeName([x509.DNSName('esp32.test')]),False).add_extension(x509.ExtendedKeyUsage([ExtendedKeyUsageOID.SERVER_AUTH]),False).sign(ca_key,hashes.SHA384()))
 (out/(kind+'.pem')).write_bytes(cert.public_bytes(serialization.Encoding.PEM));keyfile(out/(kind+'.key'),key)
other_key=ec.generate_private_key(ec.SECP256R1());other_name=name('Untrusted temporary CA')
other=(x509.CertificateBuilder().subject_name(other_name).issuer_name(other_name).public_key(other_key.public_key()).serial_number(x509.random_serial_number()).not_valid_before(start).not_valid_after(end).add_extension(x509.BasicConstraints(ca=True,path_length=0),True).sign(other_key,hashes.SHA256()))
(out/'ca-untrusted.der').write_bytes(other.public_bytes(serialization.Encoding.DER))
print('Generated temporary CA and two server certificates; no private keys enter firmware.')
