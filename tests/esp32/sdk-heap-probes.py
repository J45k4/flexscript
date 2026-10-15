"""Count real allocator header visits without instrumenting production firmware."""
from pathlib import Path
import argparse,json
p=argparse.ArgumentParser();p.add_argument('output',type=Path);p.add_argument('--heap',type=Path);a=p.parse_args()
root=Path(__file__).resolve().parents[2];heap=(a.heap or root/'lib/platform/esp32-sdk-heap.flex').resolve();out=a.output.resolve();out.mkdir(parents=True,exist_ok=True)
s=heap.read_text();marker='let raw=esp32_load32(h);let span=raw&~15;';assert s.count(marker)==1,'allocator probe point changed'
s=s.replace('import "esp32.flex";', 'import '+json.dumps(str(root/'lib/platform/esp32.flex'))+';').replace(marker,'sh_probes=sh_probes+1;'+marker)
(out/'heap.flex').write_text('global sh_probes=0;\n'+s)
(out/'sdk-heap-probes.flex').write_text('import '+json.dumps(str(root/'lib/platform/esp32.flex'))+';\nimport '+json.dumps(str(out/'heap.flex'))+''';
fn main() {
    if esp_sdk_heap_init(0x3ffc8000,98304) {return 1;}let pinned=alloc(1024);let i=0;
    while i<128 {let p=esp_sdk_malloc(32);if !p {return 1;}store64(p,i+100);store64(pinned+i*8,p);i=i+1;}
    sh_probes=0;i=0;while i<1024 {let p=esp_sdk_malloc(64);if !p {return 1;}store64(p,0x12345678);if esp_sdk_free(p) {return 1;}i=i+1;}
    esp_uart_write("SDK heap block visits ");esp_uart_hex(sh_probes);esp_uart_write("\\r\\n");
    if sh_probes>2048 {return 2;}i=0;while i<128 {let p=load64(pinned+i*8);if load64(p)!=i+100 || esp_sdk_free(p) {return 3;}i=i+1;}
    if esp_sdk_allocated || esp_sdk_heap_free()!=98304-16 {return 4;}
    esp_uart_write("PASS: bounded SDK heap search with128 pinned blocks and1024 temporary allocations\\r\\n");esp_uart_flush();return 0;
}
''')
(out/'sdk-heap-probes-xip.flex').write_text('import '+json.dumps(str(root/'lib/platform/esp32-xip.flex'))+';\nimport '+json.dumps(str(out/'sdk-heap-probes.flex'))+';\n')
