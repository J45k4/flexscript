global emu_irq_seen=0;
fn on_irq(source){if source== -1{emu_irq_seen=emu_irq_seen+1;}return 0;}
fn main(){if esp_irq_software(esp32_callback(on_irq)){return 1;}let i=0;while i<20{let old=esp32_irq_save();esp32_irq_raise(128);if emu_irq_seen!=i{return 2;}esp32_irq_restore(old);esp_irq_enable();let start=esp32_cycles();while emu_irq_seen==i && ((esp32_cycles()-start)&0xffffffff)<1000000{}if emu_irq_seen!=i+1{return 3;}i=i+1;}return 0;}
