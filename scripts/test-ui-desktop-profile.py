#!/usr/bin/env python3
"""Compare desktop-specialized UI output with ordinary portable code generation."""
import json,os,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];compiler=Path(os.environ.get('FLEX_COMPILER','build/flex')).resolve()
with tempfile.TemporaryDirectory(prefix='desktop-ui-profile-',dir=ROOT/'build') as directory:
 work=Path(directory)
 def compile_run(text,name,profile=False):
  source=work/(name+'.flex');source.write_text(text);binary=work/name
  args=[str(compiler)]+(['--native-literals','shared'] if profile else [])+[str(source),'-o',str(binary)]
  result=subprocess.run(args,capture_output=True,timeout=30);assert result.returncode==0,result.stderr.decode()
  run=subprocess.run([str(binary)],capture_output=True,timeout=10);assert run.returncode==0,run.stderr.decode()
  return run.stdout,binary,source
 portable=(ROOT/'tests/ui/portable.flex').read_text().replace('"../../libs/ui.flex"',json.dumps(str(ROOT/'libs/ui.flex'))).replace('"../../libs/ui/syntax.flex"',json.dumps(str(ROOT/'libs/ui/syntax.flex')))
 ordinary,_,_=compile_run(portable,'portable-normal')
 profile=portable.replace('syntax.flex";', 'syntax.flex" with "desktop";')
 optimized,_,_=compile_run(profile,'portable-desktop',True);assert ordinary==optimized
 print('PASS compact desktop property tables preserve the complete portable patch trace',flush=True)
 source=r'''
 import LIB;
 extend SYNTAX CONFIG;
 global tick=0;
 fn cu_desktop(){return 1;}
 fn label(){if tick{return "next";}return "first";}
 view phone_only(){column("phone",padding:123){text("phone-text",text:label(),description:"PHONE_ONLY_UNREACHABLE_MARKER");}}
 view unused_view(){text("unused",text:label(),description:"UNUSED_VIEW_UNREACHABLE_MARKER");}
 view nested(){
   column("nested",padding:0x14,height:-1,enabled:0,description:"",color:0){
     text("mixed",text:label(),padding_x:8,description:label(),size:16,color:"#abcdef",background:label(),weight:1,font:"mono",align:"center");
     text("escaped",text:"fixed",description:"quote \" slash \\ and line\n",color:"#123456",size:13);
     text("nul",text:"fixed",description:"prefix\0suffix",padding:3);
   }
 }
 view direct_view(){text("direct",text:label(),size:14,color:"#123456");}
 fn ordinary_caller(){return direct_view();}
 view app_view(){column("app"){if cu_desktop(){use nested();}else{use phone_only();}if !cu_desktop() && tick || tick {text("precedence",text:label(),size:14);}if cu_desktop() && tick || tick {text("and",text:label());}if !cu_desktop() || tick {text("or",text:label());}if cu_desktop() || tick {text("true",text:label());}}}
 fn main(){let first=app_view();let index=ui_index;tick=1;let next=app_view();m_print(1,"[");m_print(1,ui_compiled_diff(first,next,index,ui_index));m_print(1,",");let b=m_buffer();uv_tree(b,next);m_print(1,m_data(b));m_print(1,",");ui_compiled_begin();tick=0;first=ui_compiled_snapshot(ordinary_caller());index=ui_index;ui_compiled_begin();tick=2;next=ui_compiled_snapshot(ordinary_caller());m_print(1,ui_compiled_diff(first,next,index,ui_index));m_print(1,"]");return 0;}
 '''.replace('LIB',json.dumps(str(ROOT/'libs/ui.flex'))).replace('SYNTAX',json.dumps(str(ROOT/'libs/ui/syntax.flex')))
 normal,_,_=compile_run(source.replace(' CONFIG',''),'mixed-normal')
 specialized,binary,path=compile_run(source.replace('CONFIG','with "desktop:cu_desktop"'),'mixed-desktop',True)
 assert normal==specialized,(normal,specialized)
 packets=json.loads(specialized);props=packets[1]['children'][0]['props'];assert props['padding']=='20' and props['height']=='-1' and props['enabled']=='false' and props['description']=='' and 'color' not in props
 assert any(p['key']=='direct' and p['op']=='text' for p in packets[2])
 data=binary.read_bytes();assert b'PHONE_ONLY_UNREACHABLE_MARKER' not in data and b'UNUSED_VIEW_UNREACHABLE_MARKER' not in data
 for mode in ['--interpret','--jit']:
  result=subprocess.run([str(compiler),'run',mode,'--fuel=200000000','--timeout-ms=20000',str(path)],capture_output=True,timeout=30)
  assert result.returncode==0 and result.stdout==specialized,(mode,result.stderr.decode())
 print('PASS desktop branch pruning, reachable/public templates, mixed patch indexes, hex/negative/boolean/null properties, escapes and native/interpreter/JIT output',flush=True)
 # Structural/property validation is retained even in excluded mobile branches.
 invalid=source.replace('CONFIG','with "desktop:cu_desktop"').replace('padding:123','mystery:123');path.write_text(invalid)
 result=subprocess.run([str(compiler),str(path),'-o',str(binary)],capture_output=True);assert result.returncode and b'unknown portable UI property' in result.stderr
 print('PASS specialization retains validation of excluded UI branches',flush=True)
