#!/usr/bin/env python3
"""Execute emitted I2S firmware and verify its declared evidence boundary.

The PCM fixture uses the same payload source as the saved board test, with
only ROM clock setup/absent-PLL boot checks removed for the explicit emulator
profile. UART equality does not imply byte-identical firmware or ROM support.
This tool never opens a device and always records physical_hardware=False.
"""
import argparse,hashlib,json,re,subprocess,time
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--kind',choices=['pcm','irq'],required=True)
for flag in ['elf','runner','work','report']:p.add_argument('--'+flag,type=Path,required=True)
p.add_argument('--capture',type=Path);a=p.parse_args();root=Path(__file__).resolve().parents[2];w=a.work.resolve();w.mkdir(parents=True,exist_ok=True);elf=a.elf.resolve();runner=a.runner.resolve();uart=w/'uart.bin';sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();before=(sha(elf),sha(runner));started=time.time();q=subprocess.run([str(runner),str(elf),str(uart),'21','25','--fuel','2000000000'],cwd=root,capture_output=True,timeout=600);(w/'stdout.log').write_bytes(q.stdout);(w/'stderr.log').write_bytes(q.stderr);assert q.returncode==0,(q.returncode,q.stdout,q.stderr);assert before==(sha(elf),sha(runner)),'execution artifact changed while running';match=re.fullmatch(rb'PASS board firmware: instructions=(\d+) ticks=(\d+)\n',q.stdout);assert match and not q.stderr;data=uart.read_bytes();assert b'FAIL' not in data and b'MISMATCH' not in data
report={'pass':True,'kind':a.kind,'machine_code_executed':True,'physical_hardware':False,'rom_initialization_executed':False,'same_image_physical_replay':False,'clock_profile':'explicit80MHz CPU/APB, PLL_D2=160MHz','exit_code':q.returncode,'started_at':started,'finished_at':time.time(),'instructions':int(match[1]),'ticks':int(match[2]),'image_sha256':before[0],'runner_sha256':before[1],'uart_sha256':sha(uart),'uart_bytes':len(data),'stdout_sha256':sha(w/'stdout.log')}
if a.kind=='pcm':
 assert a.capture,'saved physical capture required';capture=a.capture.resolve();physical=json.loads((capture/'physical.json').read_text());closed=json.loads((capture.parent/'report.json').read_text());assert physical['pass'] and physical['ram_only'] and not physical['flash_write_requested'] and physical['flash_unchanged'] and physical['stages'][-1]=='physical-final-reset';assert closed['pass'] and closed['closed'];assert physical['image_sha256']==sha(capture/'peer.elf')==closed['physical']['image_sha256'];assert data==(capture/'physical-uart.bin').read_bytes()==physical['uart'].encode();assert sha(capture/'physical-uart.bin')==closed['physical']['uart_sha256']
 original=(root/'tests/esp32/i2s-duplex-physical.flex').read_text();saved=capture/'source/i2s-duplex-physical.flex';assert sha(saved)==closed['source_sha256']['tests/esp32/i2s-duplex-physical.flex']==sha(root/'tests/esp32/i2s-duplex-physical.flex');assert original==saved.read_text()
 expected=original.replace('import "../../lib/platform/esp32-radio-clock.flex";\n','').replace('ix_check(esp_i2s_init_duplex(0,22,4,21,25,16000,16)== -19,9);esp_radio_clock_init();','');expected='// Emulator-only80MHz PLL profile. Same64 PCM payloads as the physical probe;\n// ROM initialization/absent-PLL boot check are deliberately separate gates.\n'+expected;assert expected==(root/'tests/esp32/emulator-i2s.flex').read_text(),'PCM payload fixture drifted from the physical source'
 rows=re.findall(rb'EXCHANGE BUS ([0-9a-f]{16}) BITS ([0-9a-f]{16}) RATE ([0-9a-f]{16}) SIZE ([0-9a-f]{16}) RESULT ([0-9a-f]{16})\r\n',data);assert len(rows)==64 and data.endswith(b'PASS: I2S0/1 DMA,64 exact PCM exchanges,16/32-bit\r\n');assert all(int(row[3],16)==int(row[4],16) for row in rows);assert len(set((row[0],row[1],row[2],row[3]) for row in rows))==64
 report.update({'PCM_cases':64,'saved_physical_capture_compared':True,'byte_identical_physical_uart':True,'physical_image_sha256':sha(capture/'peer.elf'),'image_differs_from_physical':sha(elf)!=sha(capture/'peer.elf'),'payload_source_transform_verified':True,'physical_capture_source_sha256':sha(saved)})
else:
 assert data==b'PASS: I2S0/1,16 native WAITI completion pairs\r\n';report.update({'native_waiti_completion_pairs':16,'controllers':2,'sample_widths':[16,32],'saved_physical_capture_compared':False})
a.report.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
