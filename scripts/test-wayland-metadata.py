#!/usr/bin/env python3
"""Compare native protocol tables with wayland-scanner and public ABI headers.

Canonical, licensed XML is pinned under tests/tooling/wayland-protocols. All
C/scanner usage is an independent test oracle, not an application generator.
"""
import argparse,hashlib,json,shlex,subprocess,xml.etree.ElementTree as ET
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--compiler',type=Path,required=True);a=p.parse_args()
out=ROOT/'build/migration/metadata-tests';out.mkdir(parents=True,exist_ok=True)
base=ROOT/'tests/tooling/wayland-protocols'
files=[base/x for x in ['stable/xdg-shell/xdg-shell.xml','stable/viewporter/viewporter.xml','staging/fractional-scale/fractional-scale-v1.xml','staging/cursor-shape/cursor-shape-v1.xml','stable/tablet/tablet-v2.xml','unstable/text-input/text-input-unstable-v3.xml','stable/presentation-time/presentation-time.xml']]
manifest=json.loads((base/'manifest.json').read_text())
for f in files:assert hashlib.sha256(f.read_bytes()).hexdigest()==manifest['sha256'][str(f.relative_to(base))],f
subprocess.run([str(a.compiler.resolve()),str(ROOT/'scripts/wayland-protocols.flex'),'-o',str(out/'scanner-flex')],check=True)
args=[str(out/'scanner-flex')]
for f in files:args+=['--protocol',str(f)]
subprocess.run(args+['--out',str(out/'regenerated.flex')],check=True)
assert (out/'regenerated.flex').read_bytes()==(ROOT/'libs/gui/backends/wayland/protocols.flex').read_bytes(),'Regenerate the protocol tables from the canonical XML'
names=[i.attrib['name'] for f in files for i in ET.parse(f).getroot().findall('interface')]
code=[]
for i,f in enumerate(files):
    target=out/f'protocol-{i}.c';subprocess.run(['wayland-scanner','private-code',str(f),str(target)],check=True);code.append(str(target))
source=(ROOT/'tests/tooling/wayland-metadata.c').read_text()
source+='\n'+''.join(f'extern const struct wl_interface {name}_interface;\n' for name in names)
source+='int main(void){puts("[");'+''.join(('if(1)putchar(\',\');' if i else '')+f'interface(&{name}_interface);' for i,name in enumerate(names))+'puts("]");return 0;}\n'
oracle=out/'oracle.c';oracle.write_text(source)
flags=shlex.split(subprocess.check_output(['pkg-config','--cflags','--libs','wayland-client'],text=True))
subprocess.run(['cc','-O2',str(oracle),*code,*flags,'-o',str(out/'oracle')],check=True)
expected=json.loads(subprocess.check_output([str(out/'oracle')],text=True))
driver='''
import "'''+str(ROOT/'lib/ffi.flex')+'''";
import "'''+str(ROOT/'libs/gui/backends/wayland/protocols.flex')+'''";
import "'''+str(ROOT/'scripts/lib/json.flex')+'''";
fn messages(p,count){let out=j_array();let i=0;while i<count{let m=p+i*24;let o=j_object();j_set(o,"name",j_string(load64(m)));let signature=load64(m+8);j_set(o,"signature",j_string(signature));let types=j_array();let n=0;let at=0;while load8(signature+at){let c=load8(signature+at);if !(c>=48 && c<=57) && c!=63{let type=load64(load64(m+16)+n*8);let name="";if type{name=load64(type);}j_push(types,j_string(name));n=n+1;}at=at+1;}j_set(o,"types",types);j_push(out,o);i=i+1;}return out;}
fn face(out,p){let o=j_object();j_set(o,"name",j_string(load64(p)));j_set(o,"version",j_int(bytes_load32(p+8)));j_set(o,"requests",messages(load64(p+16),bytes_load32(p+12)));j_set(o,"events",messages(load64(p+32),bytes_load32(p+24)));j_push(out,o);return 0;}
fn main(argc,argv){h_environment(argc,argv);let lib=ffi_open("libwayland-client.so.0");h_assert(lib && wp_protocol_init(lib),"Protocol initialization failed");let out=j_array();
'''+''.join(f'face(out,wp_i_{name});' for name in names)+'''
let text=j_dump(out);wp_protocol_close();ffi_close(lib);h_print(1,text);return 0;}
'''
(out/'driver.flex').write_text(driver)
subprocess.run([str(a.compiler.resolve()),str(out/'driver.flex'),'-o',str(out/'driver')],check=True)
actual=json.loads(subprocess.check_output([str(out/'driver')],text=True));assert actual==expected,(actual,expected)
abi=out/'abi.c';abi.write_text('''#include <stdio.h>
#include <stddef.h>
#include <wayland-client.h>
#include <wayland-cursor.h>
int main(void){printf("%zu %zu %zu %zu %zu %zu %zu %zu %zu %zu %zu %zu %zu\\n",sizeof(struct wl_interface),offsetof(struct wl_interface,version),offsetof(struct wl_interface,method_count),offsetof(struct wl_interface,methods),offsetof(struct wl_interface,event_count),offsetof(struct wl_interface,events),sizeof(struct wl_message),offsetof(struct wl_message,signature),offsetof(struct wl_message,types),sizeof(struct wl_cursor),offsetof(struct wl_cursor,images),sizeof(struct wl_cursor_image),offsetof(struct wl_cursor_image,delay));}
''')
subprocess.run(['cc',str(abi),*flags,'-o',str(out/'abi')],check=True)
assert subprocess.check_output([str(out/'abi')],text=True).strip()=='40 8 12 16 24 32 24 8 16 24 8 20 16'
sdl_flags=shlex.split(subprocess.check_output(['pkg-config','--cflags','--libs','sdl2','wayland-client'],text=True))
sdl_abi=out/'sdl-abi';subprocess.run(['cc','-DSDL_OBSERVER_MAIN','-O2','-Wall','-Wextra','-Werror',str(ROOT/'tests/tooling/sdl-wayland.c'),'-o',str(sdl_abi),*sdl_flags],check=True)
assert subprocess.check_output([str(sdl_abi)],text=True).strip()=='72 4 8 16 6'
print(f'PASS {len(names)} native Wayland interfaces: versions, request/event names, signatures, nullable/since/typed references and public protocol/cursor/SDL SysWM ABI')
