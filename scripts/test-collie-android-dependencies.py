#!/usr/bin/env python3
"""Verify the complete pinned SDK graph offline, nested notices and corrupt-cache rejection."""
import argparse,json,runpy,shutil,tempfile,zipfile
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--cache',type=Path,default=Path('build/android-dependency-cache'));a=p.parse_args();root=Path(__file__).resolve().parents[1]
ns=runpy.run_path(str(root/'apps/collie/android/dependencies.py'));lock=json.loads((root/'apps/collie/android/dependencies.json').read_text());checks=[]
def passed(text):checks.append(text);print('PASS',text)
with tempfile.TemporaryDirectory(prefix='collie-sdk-lock-') as directory:
 temp=Path(directory);(temp/'out').mkdir();original=ns['artifact'].__globals__['urllib'].request.urlopen
 def offline(*args,**kwargs):raise AssertionError('Fully cached SDK preparation unexpectedly used the network')
 ns['artifact'].__globals__['urllib'].request.urlopen=offline
 try:
  result=ns['prepare'](temp/'out',a.cache.resolve())
  assert len(result['jars'])>=len(lock['artifacts']) and result['resources'] and result['packages']
  assert json.loads(result['assets']['assets/collie-android-dependencies.json'])==lock
  assert all(row.get('licenses') and row['sha256'] and row['bytes'] for row in lock['artifacts'])
  passed('every pinned SDK artifact is size/hash-verified and prepares offline with the exact upstream license manifest')
  expected={}
  for index,row in enumerate(lock['artifacts']):
   path=ns['artifact'](row,a.cache.resolve())
   with zipfile.ZipFile(path) as archive:
    ns['notices'](archive,str(index),expected)
    if row['type']=='aar':
     import io
     for name in archive.namelist():
      if name=='classes.jar' or name.startswith('libs/') and name.endswith('.jar'):
       with zipfile.ZipFile(io.BytesIO(archive.read(name))) as classes:ns['notices'](classes,str(index)+'/'+name,expected)
  assert expected and result['licenses']==expected
  passed('all embedded SDK license/notice bytes are preserved, including nested AAR class archives when present')
  for index,row in enumerate(lock['artifacts']):
   if not row.get('class_prefixes'):continue
   source=ns['artifact'](row,a.cache.resolve())
   import io
   with zipfile.ZipFile(source) as aar,zipfile.ZipFile(io.BytesIO(aar.read('classes.jar'))) as original_classes,zipfile.ZipFile(temp/'out'/'dependencies'/str(index)/'classes.jar') as filtered:
    expected_names={n for n in original_classes.namelist() if n.endswith('.class') and any(n.startswith(prefix) for prefix in row['class_prefixes'])}
    assert set(filtered.namelist())==expected_names and len(expected_names)==35
    assert all(filtered.read(n)==original_classes.read(n) for n in expected_names)
    assert not any('/impl/' in n or n.endswith('/UwbManager.class') for n in filtered.namelist())
  passed('the pinned OEM artifact contributes exactly its 35 unmodified protocol classes, without the higher-level AndroidX implementation')
  target=temp/'selection.jar'
  for prefixes in [[],['../'],['androidx//'],['/androidx/'],['androidx/core/uwb/backend/']*5]:
   try:ns['protocol_classes'](target,prefixes);raise AssertionError('Malformed protocol selection accepted')
   except ValueError:pass
  with zipfile.ZipFile(target,'w') as z:z.writestr('other/Unrelated.class',b'not a protocol class')
  try:ns['protocol_classes'](target,['androidx/core/uwb/backend/']);raise AssertionError('Empty protocol selection accepted')
  except ValueError:pass
  passed('malformed package prefixes and an empty protocol class selection fail before packaging')
  row=lock['artifacts'][0];bad=temp/'corrupt-cache';bad.mkdir();name=row['sha256']+'-'+row['file'];data=bytearray(ns['artifact'](row,a.cache.resolve()).read_bytes());data[-1]^=1;(bad/name).write_bytes(data)
  try:ns['artifact'](row,bad);raise AssertionError('Corrupt cached artifact accepted')
  except ValueError as e:assert 'digest mismatch' in str(e)
  passed('a same-size single-byte cache corruption fails before any SDK class/resource extraction')
  for update in [dict(url='https://example.invalid/'+row['file']),dict(file='../escape.aar'),dict(sha256='0'*63),dict(bytes=33554433)]:
   try:ns['artifact'](dict(row,**update),bad);raise AssertionError('Malformed SDK pin accepted')
   except ValueError:pass
  passed('noncanonical origin/path, invalid digest and oversized pins are rejected before network access')
 finally:ns['artifact'].__globals__['urllib'].request.urlopen=original
print(len(checks),'Android SDK dependency checks passed')
