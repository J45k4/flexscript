"""Pinned public Android SDK artifacts; no Gradle/SDK downloads in native-only builds."""
import hashlib,json,re,shutil,tempfile,urllib.request,zipfile
from pathlib import Path,PurePosixPath
import xml.etree.ElementTree as ET

HERE=Path(__file__).resolve().parent
ORIGINS=('https://dl.google.com/dl/android/maven2/','https://repo.maven.apache.org/maven2/')

def artifact(row,cache):
    name=row['file'];digest=row['sha256'];size=row['bytes'];url=row['url']
    if (Path(name).name!=name or not re.fullmatch(r'[a-zA-Z0-9_.-]+\.(aar|jar)',name)
        or not re.fullmatch('[0-9a-f]{64}',digest) or not isinstance(size,int) or not 0<size<=33554432
        or not url.startswith(ORIGINS) or not url.endswith('/'+name)):
        raise ValueError('Invalid pinned Android artifact: '+row['id'])
    target=cache/(digest+'-'+name)
    if not target.exists():
        with urllib.request.urlopen(url,timeout=30) as response:
            if not response.geturl().startswith(ORIGINS):raise ValueError('Unexpected artifact redirect')
            data=response.read(size+1)
        if len(data)!=size or hashlib.sha256(data).hexdigest()!=digest:raise ValueError('Android artifact digest mismatch: '+row['id'])
        with tempfile.NamedTemporaryFile(dir=cache,delete=False) as temporary:
            path=Path(temporary.name);temporary.write(data)
        path.replace(target)
    if target.stat().st_size!=size or hashlib.sha256(target.read_bytes()).hexdigest()!=digest:
        raise ValueError('Cached Android artifact digest mismatch: '+row['id'])
    return target

def notices(archive,prefix,licenses):
    for info in archive.infolist():
        name=PurePosixPath(info.filename)
        if name.is_absolute() or '..' in name.parts:raise ValueError('Invalid Android archive entry')
        if info.is_dir():continue
        if info.file_size>33554432:raise ValueError('Oversized Android archive entry')
        if re.search(r'(^|/)(license|notice|copying)([._-]|$)',str(name),re.I):
            licenses['META-INF/collie-dependencies/'+prefix+'/'+str(name)]=archive.read(info)

def protocol_classes(target,prefixes):
    # A pinned AAR may supply only its stable OEM protocol, without pulling its
    # unrelated higher-level implementation and runtime dependency graph.
    if (not isinstance(prefixes,list) or not 1<=len(prefixes)<=4 or
        any(not isinstance(p,str) or len(p)>128 or not re.fullmatch(r'(?:[A-Za-z_$][A-Za-z0-9_$]*/)+',p) for p in prefixes)):
        raise ValueError('Invalid SDK protocol class prefixes')
    selected=[]
    with zipfile.ZipFile(target) as source:
        for info in source.infolist():
            if info.filename.endswith('.class') and any(info.filename.startswith(p) for p in prefixes):
                if info.file_size>1048576 or len(selected)>=4096:raise ValueError('Oversized SDK protocol class set')
                selected.append((info.filename,source.read(info)))
    if not selected:raise ValueError('Empty SDK protocol class selection')
    with zipfile.ZipFile(target,'w',compression=zipfile.ZIP_DEFLATED) as output:
        for name,data in sorted(selected):output.writestr(name,data)

def prepare(out,cache):
    lock=json.loads((HERE/'dependencies.json').read_text())
    if lock.get('schema')!=1 or not 1<=len(lock['artifacts'])<=64:raise ValueError('Unsupported Android dependency lock')
    ids=[r['id'] for r in lock['artifacts']]
    if len(set(ids))!=len(ids):raise ValueError('Duplicate Android dependency')
    cache.mkdir(parents=True,exist_ok=True);root=out/'dependencies'
    if root.exists():shutil.rmtree(root)
    root.mkdir();jars=[];resources=[];packages=set();rules=[];assets={};licenses={}
    for index,row in enumerate(lock['artifacts']):
        path=artifact(row,cache);directory=root/str(index);directory.mkdir()
        with zipfile.ZipFile(path) as archive:
            notices(archive,str(index),licenses)
            if row['type']=='jar':jars.append(path);continue
            if row['type']!='aar':raise ValueError('Unsupported Android artifact format')
            manifest=ET.fromstring(archive.read('AndroidManifest.xml'))
            package=manifest.get('package')
            if not package or not re.fullmatch(r'[A-Za-z_]\w*(\.[A-Za-z_]\w*)+',package):raise ValueError('Invalid Android SDK resource package')
            packages.add(package)
            for info in archive.infolist():
                name=PurePosixPath(info.filename)
                if info.is_dir():continue
                text=str(name)
                if text=='classes.jar' or (text.startswith('libs/') and text.endswith('.jar')) or text.startswith('res/'):
                    target=directory/Path(text);target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(archive.read(info))
                    if text.endswith('.jar'):
                        jars.append(target)
                        with zipfile.ZipFile(target) as classes:notices(classes,str(index)+'/'+text,licenses)
                        if row.get('class_prefixes') is not None:protocol_classes(target,row['class_prefixes'])
                elif text=='proguard.txt' or text=='consumer-rules.pro':
                    target=directory/name.name;target.write_bytes(archive.read(info));rules.append(target)
                elif text.startswith('assets/'):
                    data=archive.read(info)
                    if text in assets and assets[text]!=data:raise ValueError('Conflicting Android SDK asset: '+text)
                    assets[text]=data
            if (directory/'res').is_dir():resources.append(directory/'res')
    assets['assets/collie-android-dependencies.json']=json.dumps(lock,indent=2).encode()+b'\n'
    return dict(jars=jars,resources=resources,packages=sorted(packages),rules=rules,assets=assets,licenses=licenses)
