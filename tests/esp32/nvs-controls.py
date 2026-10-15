#!/usr/bin/env python3
"""Check that independent NVS vectors detect four semantic regressions."""
import argparse,hashlib,json,subprocess,tempfile
from pathlib import Path

def main():
    p=argparse.ArgumentParser();p.add_argument('--compiler',required=True);p.add_argument('--report',type=Path,required=True);args=p.parse_args()
    root=Path(__file__).resolve().parents[2]
    source=(root/'lib/storage/nvs.flex').read_text().replace('import "settings.flex";',f'import "{root}/lib/storage/settings.flex";')
    oracle=(root/'tests/esp32/nvs-oracle.flex').read_text().replace('import "settings-fixture.flex";',f'import "{root}/tests/esp32/settings-fixture.flex";').replace('import "../../lib/storage/nvs.flex";','import "broken.flex";')
    controls=[('readonly','if write && !load8(p+4)','if 0'),('types','if kv_value_type!=type {return 0x1103;}','if 0 {return 0x1103;}'),('tokens','nv_next_token=nv_next_token+1;','nv_next_token=1;'),('namespaces','load8(r+8)==ns && size>ns+1 && kv_equal(r+9,p+8,ns)','size>ns+1')]
    results=[]
    with tempfile.TemporaryDirectory(prefix='flexscript-nvs-controls-') as tmp:
        work=Path(tmp);(work/'oracle.flex').write_text(oracle)
        for name,before,after in controls:
            assert source.count(before)==1;(work/'broken.flex').write_text(source.replace(before,after))
            subprocess.run([args.compiler,str(work/'oracle.flex'),'-o',str(work/'oracle')],cwd=root,check=True,capture_output=True)
            result=subprocess.run(['python3',str(root/'tests/esp32/nvs-vectors.py'),'--oracle',str(work/'oracle'),'--report',str(work/'unexpected.json')],cwd=root,capture_output=True,timeout=20)
            assert result.returncode!=0 and b'AssertionError' in result.stderr,(name,result.stdout,result.stderr)
            results.append({'name':name,'rejected':True,'exit':result.returncode,'log_sha256':hashlib.sha256(result.stderr).hexdigest()})
    args.report.write_text(json.dumps(results,indent=2)+'\n');print('NVS independent reference rejected all4 broken-source controls')
if __name__=='__main__':main()
