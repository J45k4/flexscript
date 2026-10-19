import "../../lib/platform/esp32c3-xip.flex";
import "../../lib/platform/esp32c3-irq.flex";
// The runner imports a copy of the actual atomics module with only its word
// read accessor redirected here, allowing a real IRQ in the read/write window.
global directed_pointer=0;global directed_armed=0;
fn atom_pause(a,b,c,d,e,f,g,h){return 0;}
fn directed_read(pointer){let value=esp32_load32(pointer);if pointer==directed_pointer && directed_armed{directed_armed=0;esp32_irq_raise(128);}return value;}
fn directed_irq(source){return esp32_call32(esp32_external("atomic_interrupt"),0,0,0,0,0,0,0,0);}
fn main(){
 if esp_atomics_bind()||esp_irq_software(esp32_iram_callback(directed_irq))||esp_irq_enable(){return 1;}
 esp32_callback32(atom_pause);directed_pointer=esp32_call32(esp32_external("atomic_directed_reset"),0,0,0,0,0,0,0,0);directed_armed=1;
 if esp32_call32(esp32_external("atomic_directed_add"),0,0,0,0,0,0,0,0){return 2;}
 let start=esp32_cycles();while !esp32_load32(directed_pointer) {if ((esp32_cycles()-start)&4294967295)>1000000{return 3;}}
 return esp32_call32(esp32_external("atomic_directed_check"),0,0,0,0,0,0,0,0);
}
