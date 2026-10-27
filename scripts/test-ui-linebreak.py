#!/usr/bin/env python3
"""Native wrap integration: canonical opportunities and independent HB widths.

Official default line-break expectations constrain actual selected soft breaks;
additional Latin cases calculate greedy choices by exhaustively trying legal
stops with the independent C HarfBuzz oracle. App code remains Flexscript.
"""
import argparse, functools, json, random, shlex, subprocess, unicodedata
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--compiler',required=True,type=Path);a=p.parse_args()
    out=ROOT/'build/migration/ui-linebreak-tests';out.mkdir(parents=True,exist_ok=True)
    flags=shlex.split(subprocess.check_output(['pkg-config','--cflags','--libs','freetype2','harfbuzz'],text=True))
    oracle=out/'oracle';subprocess.run(['cc','-O2',str(ROOT/'tests/tooling/caret-oracle.c'),*flags,'-o',str(oracle)],check=True)
    fonts=[subprocess.check_output(['fc-match','-f','%{file}',name],text=True) for name in ['Noto Sans','Noto Sans:weight=200']]
    @functools.lru_cache(maxsize=8192)
    def width(text,bold=0):
        if not text:return 0
        if '\t' in text:return sum(width(part,bold) for part in text.replace('\t','\0    \0').split('\0'))
        result=json.loads(subprocess.check_output([str(oracle),fonts[bold],'20',text,'4'],text=True))
        return (sum(g['advance'] for g in result['glyphs'])+63)//64
    requests=[];expected=[]
    pool=[]
    path=ROOT/'tests/tooling/unicode/17.0.0/auxiliary/LineBreakTest.txt'
    hard={0,10,11,12,13,28,29,30,0x85,0x2028,0x2029}
    for number,raw in enumerate(path.read_text().splitlines(),1):
        raw=raw.split('#',1)[0].strip()
        if not raw:continue
        chars=[];allowed=[];byte=0
        for token in raw.split():
            if token=='÷':allowed.append(byte)
            elif token!='×':chars.append(chr(int(token,16)));byte+=len(chars[-1].encode())
        if len(chars)<=80 and not any(ord(c) in hard for c in chars):pool.append((''.join(chars),set(allowed),number))
    selected=pool[:96]+random.Random(170014).sample(pool[96:],256)
    for text,allowed,source in selected:
        for available,styled in [(32,0),(90,1)]:
            requests.append(dict(text=text,width=available,styled=styled));expected.append(dict(allowed=allowed,source=source))
    latin=['AV ffi alpha beta gamma', 'no\u00a0break next word', 'co\u00adoperate again',
           'a\u00adb\u00adc\u00add longword', 'foo\u00ad bar baz', 'a\tbc def gh',
           'word'+(' '*25)+'next', 'a b '+(' '*40), 'fifa AVAV a\u0301bc next']
    for text in latin:
        chars=list(text);offsets=[0]
        for char in chars:offsets.append(offsets[-1]+len(char.encode()))
        # These focused cases have legal opportunities after SP groups, TAB or
        # SHY. NBSP is inside its nonbreaking word, and combining marks attach.
        allowed={offsets[i+1] for i,c in enumerate(chars) if c in (' ','\t','\xad') and (i+1==len(chars) or chars[i+1]!=' ')}|{offsets[-1]}
        for available in [max(1,width('AV ffi')-2),width('co-'),width('no\u00a0break')+2,120]:
            for styled in (0,1):
                requests.append(dict(text=text,width=available,styled=styled));expected.append(dict(latin=True,allowed=allowed))
    for text in ['你好世界，中文换行。更多文字。','日本語（かっこ）と句読点。','👨‍👩‍👧‍👦 🇫🇮 á क्ष',
                 'שלום\u00a0עולם 123 עוד מילים', 'مرحبا بالعالم 123 hello',
                 'one\r\ntwo\u2028three\u2029four\vfive\fsix\u0085seven']:
        for styled in (0,1):
            requests.append(dict(text=text,width=85,styled=styled));expected.append(dict(extra=True))
    requests.append(dict(text='AVffi'*8000,width=2400,styled=0));expected.append(dict(long=True))
    source=out/'requests.json';source.write_text(json.dumps(requests,ensure_ascii=False))
    for pipeline in ('ir','direct'):
        binary=out/('layout-'+pipeline)
        subprocess.run([str(a.compiler.resolve()),'--native-pipeline',pipeline,str(ROOT/'tests/ui/bidi-layout.flex'),'-o',str(binary)],check=True)
        result=subprocess.run([str(binary),str(source)],capture_output=True,text=True,timeout=120)
        (out/(pipeline+'.stderr.log')).write_text(result.stderr)
        assert result.returncode==0,(pipeline,result.returncode,result.stderr)
        reports=[json.loads(line) for line in result.stdout.splitlines()];(out/(pipeline+'.json')).write_text(json.dumps(reports))
        for index,(request,want,report) in enumerate(zip(requests,expected,reports,strict=True)):
            raw=request['text'].encode();plans=report['lines'];previous=0
            for row in plans:
                assert row['start']>=previous and row['end']>row['start'],(index,'Line range',row)
                previous=row['end']
                if row['soft'] and not row['emergency'] and 'allowed' in want:
                    assert row['end'] in want['allowed'],(pipeline,index,want,'Not a Unicode opportunity',row)
                same_line=[p for p in report['pieces'] if p[6]==row['y']]
                actual=sum(p[5] for p in same_line)
                if actual>request['width']:
                    # An indivisible cluster may overflow an exceptionally
                    # narrow line, but a group of multiple visible clusters may not.
                    assert row['emergency'],(index,'Non-emergency line overflow',request,row,actual)
            for piece,display in zip(report['pieces'],report['display'],strict=True):
                start,end,level,visual,x,advance,y,direction=piece;logical=raw[start:end].decode();kind=display['mapping']
                if kind==1:assert logical=='\t' and display['text']=='    '
                elif kind==2:assert logical.endswith('\xad') and display['text']==logical[:-1]+'-'
                elif kind==3:assert logical and not logical.strip(' ') and not display['text'] and advance==0
                else:assert display['text']==logical,(index,'Changed display/source mapping',logical,display)
                assert len(display['text'].encode())<=32768,(index,'Shaper limit',display)
                if want.get('latin'):
                    assert advance==width(display['text'],int(bool(display['style']&1))),(index,'Independent draw width',logical,advance)
            if want.get('latin') and not request['styled']:
                text=request['text'];offsets=[0];graphemes=[]
                for char in text:offsets.append(offsets[-1]+len(char.encode()))
                # Only the known U+0301 mark combines in these focused Latin cases.
                graphemes=[offsets[i] for i in range(1,len(offsets)) if i==len(text) or not unicodedata.combining(text[i])]
                def measure(first,end):
                    value=raw[first:end].decode().rstrip(' ')
                    if end<len(raw) and value.endswith('\xad') and raw[end-1]!=32:value=value[:-1]+'-'
                    return width(value)
                begin=0;ends=[]
                while begin<len(raw):
                    legal=sorted(end for end in want['allowed'] if end>begin)
                    fitting=[end for end in legal if measure(begin,end)<=request['width']]
                    if fitting:end=max(fitting)
                    else:
                        candidates=[end for end in graphemes if begin<end<=legal[0]]
                        fitting=[end for end in candidates if measure(begin,end)<=request['width']]
                        end=max(fitting) if fitting else candidates[0]
                    ends.append(end);begin=end
                assert [row['end'] for row in plans]==ends,(pipeline,index,'Greedy independent widths',request,ends,plans)
            if want.get('long'):assert plans[-1]['end']==len(raw) and report['height']<16384,(index,'Long unbroken text truncated',report['height'])
        print(f'PASS {pipeline}: {len(reports)} native Unicode wrap layouts, canonical opportunities, independent greedy/draw widths, rich runs, substitutions and 40KB word',flush=True)
    (out/'report.json').write_text(json.dumps(dict(status='pass',layouts=len(requests),official_samples=len(selected),pipelines=['ir','direct']),indent=2)+'\n')


if __name__=='__main__':main()
