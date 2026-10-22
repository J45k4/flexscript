#!/usr/bin/env python3
"""Regenerate/check the portable DOM adapter embedded by Flexscript's web host."""
import argparse,json
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--check',action='store_true');a=p.parse_args()
root=Path(__file__).resolve().parents[1];directory=root/'libs/ui'
source=(directory/'web.js').read_text()+(directory/'web-transport.js').read_text()
expected='// Generated from web.js by scripts/ui-assets.py.\nfn mono_client_js(){return '+json.dumps(source,ensure_ascii=False)+';}\n'
asset=directory/'web-assets.flex'
if a.check:assert asset.read_text()==expected,'Run python3 scripts/ui-assets.py'
else:asset.write_text(expected)
