#!/usr/bin/env python3
"""Primary-header C oracle versus the actual Flexscript C3/C6 GPIO adapter."""
import argparse
import json
from pathlib import Path
import shutil
import struct
import subprocess

C_ORACLE = r'''
#include <stdint.h>
#include <stdio.h>
#include "soc/gpio_reg.h"
#include "soc/io_mux_reg.h"
#include "soc/uart_reg.h"
#include "soc/gpio_sig_map.h"
static uint64_t trace[4096][3];static unsigned count;
static uint32_t get(uint32_t address){for(unsigned i=count;i>0;i--)if(trace[i-1][0]==address)return trace[i-1][1];return 0xa5a5a5a5;}
static void put(uint32_t address,uint32_t value,unsigned masked){trace[count][0]=address;trace[count][1]=value;trace[count][2]=masked;count++;}
static void mux(unsigned pin){uint32_t p=IO_MUX_GPIO0_REG+pin*4;put(p,(get(p)&~MCU_SEL_M)|(FUNC_MTMS_GPIO4<<MCU_SEL_S)|FUN_IE,1);}
static void pull(unsigned pin,unsigned direction){uint32_t p=IO_MUX_GPIO0_REG+pin*4;put(p,(get(p)&~(FUN_PU|FUN_PD))|(direction==1?FUN_PU:direction==2?FUN_PD:0),1);}
int main(void){
#ifdef C6
 uint64_t header[]={0x40830000,DR_REG_GPIO_BASE,DR_REG_IO_MUX_BASE,UART_RXFIFO_CNT_V,30,24,30,0};
#else
 uint64_t header[]={0x3fca0000,DR_REG_GPIO_BASE,DR_REG_IO_MUX_BASE,UART_RXFIFO_CNT_V,21,11,17,0};
#endif
 for(unsigned pin=0;pin<=header[4];pin++){
  if(pin>=header[5]&&pin<=header[6])continue;
  mux(pin);put(GPIO_FUNC0_OUT_SEL_CFG_REG+pin*4,SIG_GPIO_OUT_IDX|GPIO_FUNC0_OEN_SEL,0);put(GPIO_ENABLE_W1TS_REG,1u<<pin,0);
  put(GPIO_OUT_W1TS_REG,1u<<pin,0);put(GPIO_OUT_W1TC_REG,1u<<pin,0);
  uint32_t p=GPIO_PIN0_REG+pin*4;put(p,get(p)&~GPIO_PIN0_PAD_DRIVER,1);put(p,get(p)|GPIO_PIN0_PAD_DRIVER,1);
  pull(pin,1);mux(pin);put(GPIO_ENABLE_W1TC_REG,1u<<pin,0);pull(pin,2);
 }
 put(UART_FIFO_REG(0),0x78,0);header[7]=count;
 fwrite(header,sizeof header,1,stdout);fwrite(trace,sizeof trace[0],count,stdout);return ferror(stdout)?1:0;
}
'''

FLEX_MODEL = r'''
global expected=0;global writes=0;global register_rows=0;global model_ps=0x1888;global status=0;global assertions=0;
fn verify(ok,n){assertions=assertions+1;if !ok{h_print(2,h_cat3("GPIO oracle check ",h_int(n)," failed\n"));syscall(60,1,0,0,0,0,0);}return 0;}
fn esp32_state(){return load64(expected);}
fn esp32_cycles(){return 0;}
fn esp32_irq_save(){let old=model_ps;model_ps=model_ps&~8;return old;}
fn esp32_irq_restore(ps){model_ps=ps;return 0;}
fn esp32_load32(address){if address==0x6000001c{return status;}let i=writes;while i>0{i=i-1;if load64(register_rows+i*16)==address{return load64(register_rows+i*16+8);}}return 0xa5a5a5a5;}
fn esp32_store32(address,value){verify(writes<load64(expected+56),1);let row=expected+64+writes*24;verify(address==load64(row),2);verify((value&0xffffffff)==load64(row+8),3);if load64(row+16){verify((model_ps&8)==0,4);}store64(register_rows+writes*16,address);store64(register_rows+writes*16+8,value&0xffffffff);writes=writes+1;return 0;}
fn main(argc,argv){h_environment(argc,argv);verify(argc==2,5);expected=h_read(load64(argv+8));register_rows=alloc(65536);verify(rv_hal_state==load64(expected)&&rv_hal_gpio==load64(expected+8)&&rv_hal_mux==load64(expected+16)&&rv_hal_uart_mask==load64(expected+24),6);
 let pin=0;while pin<=load64(expected+32){if pin<load64(expected+40)||pin>load64(expected+48){verify(esp_gpio_valid(pin),7);verify(esp_gpio_output(pin)==0,8);verify(esp_gpio_write(pin,1)==0&&esp_gpio_write(pin,0)==0,9);verify(esp_gpio_open_drain(pin,0)==0&&esp_gpio_open_drain(pin,1)==0,10);verify(esp_gpio_pull(pin,1)==0&&esp_gpio_input(pin,2)==0,11);verify(esp_gpio_read(pin)==((0xa5a5a5a5>>pin)&1),12);verify(model_ps==0x1888,13);}else{verify(!esp_gpio_valid(pin),14);verify(esp_gpio_output(pin)== -22,15);}pin=pin+1;}
 verify(esp_gpio_output(-1)== -22&&esp_gpio_output(load64(expected+32)+1)== -22,16);verify(esp_gpio_input(4,3)== -22,17);verify(esp_uart_read()== -1,18);status=256;let got=esp_uart_read();if load64(expected+24)==255{verify(got== -1,19);}else{verify(got==0xa5,20);}status=0;verify(esp_uart_putc(0x12345678)==0,21);verify(esp_uart_flush()==0,22);verify(writes==load64(expected+56),23);let result=alloc(16);store64(result,assertions);store64(result+8,writes);return syscall(1,1,result,16,0,0,0)!=16;}
'''


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--compiler', required=True)
    parser.add_argument('--reference', type=Path, required=True)
    parser.add_argument('--work', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    args.work.mkdir(parents=True, exist_ok=True)
    rows = []
    for chip in ('esp32c3', 'esp32c6'):
        work = args.work / chip
        include = work / 'include'
        (include / 'soc').mkdir(parents=True, exist_ok=True)
        for path in (args.reference / 'components/soc' / chip / 'register/soc').glob('*.h'):
            shutil.copyfile(path, include / 'soc' / path.name)
        for name in ('soc.h', 'gpio_sig_map.h'):
            shutil.copyfile(args.reference / 'components/soc' / chip / 'include/soc' / name, include / 'soc' / name)
        (include / 'esp_assert.h').write_text('#pragma once\n')
        (include / 'esp_bit_defs.h').write_text('#pragma once\n#define BIT(n) (1U<<(n))\n#define BIT64(n) (1ULL<<(n))\n')
        source, oracle, reference = work / 'oracle.c', work / 'oracle', work / 'reference.bin'
        source.write_text(C_ORACLE)
        command = ['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-I', str(include), str(source), '-o', str(oracle)]
        if chip == 'esp32c6': command.insert(1, '-DC6')
        subprocess.run(command, check=True)
        reference.write_bytes(subprocess.check_output([str(oracle)]))
        model, binary = work / 'model.flex', work / 'model'
        model.write_text(f'import "{root / "scripts/lib/build.flex"}";\nimport "{root / "lib/platform" / (chip + ".flex")}";\n' + FLEX_MODEL)
        subprocess.run([args.compiler, str(model), '-o', str(binary)], check=True)
        checks, writes = struct.unpack('<QQ', subprocess.check_output([str(binary), str(reference)]))
        rows.append(dict(chip=chip, checks=checks, writes=writes, physical_hardware=False))
        print(f'PASS: {chip} GPIO/UART primary-header oracle: {checks} checks, {writes} exact writes')
    (args.work / 'report.json').write_text(json.dumps(dict(pass_all=True, cases=rows, reference='unmodified ESP-IDF v5.5.1 C headers'), indent=2) + '\n')


if __name__ == '__main__':
    main()
