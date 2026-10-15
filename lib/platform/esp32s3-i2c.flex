import "esp32s3-common.flex";
// Hardware I2C master, 7-bit addresses, FIFO-sized combined write/repeated-start
// read transactions. External pull-ups are required for specified bus timing.
fn esp_i2c_base(bus) {if bus<0 || bus>1 {return 0;}return 0x60013000+bus*81920;}
fn esp_i2c_init(bus,sda,scl,hz) {
    let base=esp_i2c_base(bus);if !base || !esp_gpio_valid(sda) || !esp_gpio_valid(scl) || sda==scl || hz<10000 || hz>400000 {return -22;}
    esp_clock_enable(0,7+bus*11);
    esp_gpio_output(sda);esp_gpio_output(scl);esp_gpio_write(sda,1);esp_gpio_write(scl,1);
    esp_gpio_open_drain(sda,1);esp_gpio_open_drain(scl,1);esp_gpio_pull(sda,1);esp_gpio_pull(scl,1);
    esp_gpio_route_output(scl,89+bus*2);esp_gpio_route_input(scl,89+bus*2);esp_gpio_route_output(sda,90+bus*2);esp_gpio_route_input(sda,90+bus*2);
    let div=40000000/(hz*1024)+1;let half=40000000/div/hz/2;let wait=half/4;if hz>=80000 {wait=half/2-2;}
    esp32_store32(base+84,(div-1)|(1<<21));esp32_store32(base,half-1);
    esp32_store32(base+56,(half-wait)|(wait<<9));esp32_store32(base+48,half/4-1);esp32_store32(base+52,half/2-1);
    esp32_store32(base+64,half-1);esp32_store32(base+68,half-1);esp32_store32(base+72,half-1);esp32_store32(base+76,half-1);
    let timeout=0;let v=5*half;while v {v=v>>1;timeout=timeout+1;}timeout=timeout+2;
    esp32_store32(base+12,timeout|32);esp32_store32(base+40,0);esp32_store32(base+36,16383);
    esp32_store32(base+4,0x713);esp32_store32(base+4,0xb13);return 0;
}
fn esp_i2c_command(base,index,op,count,ack) {esp32_store32(base+88+index*4,(op<<11)|count|ack);return index+1;}
fn esp_i2c_transfer(bus,address,tx,tx_size,rx,rx_size,cycles) {
    let base=esp_i2c_base(bus);
    if !base || address<0 || address>127 || tx_size<0 || tx_size>30 || rx_size<0 || rx_size>32 || cycles<1 || cycles>2147483647 {return -22;}
    if (tx_size && !esp_buffer_valid(tx,tx_size)) || (rx_size && !esp_buffer_valid(rx,rx_size)) {return -22;}
    esp_reg_update(base+24,3<<12,3<<12);esp_reg_update(base+24,3<<12,0);esp32_store32(base+36,16383);
    let i=0;while i<8 {esp_i2c_command(base,i,4,0,0);i=i+1;}
    let cmd=esp_i2c_command(base,0,6,0,0); // S3 RESTART opcode is 6 (i2c_ll.h).
    let read_first=!tx_size && rx_size;esp32_store32(base+28,(address<<1)|!!read_first);
    i=0;while i<tx_size {esp32_store32(base+28,load8(tx+i));i=i+1;}
    cmd=esp_i2c_command(base,cmd,1,tx_size+1,256);
    if tx_size && rx_size {cmd=esp_i2c_command(base,cmd,6,0,0);esp32_store32(base+28,(address<<1)|1);cmd=esp_i2c_command(base,cmd,1,1,256);}
    if rx_size>1 {cmd=esp_i2c_command(base,cmd,3,rx_size-1,0);}if rx_size {cmd=esp_i2c_command(base,cmd,3,1,1024);}
    esp_i2c_command(base,cmd,2,0,0);esp_reg_update(base+4,1<<11,1<<11);esp_reg_update(base+4,1<<5,1<<5);
    let start=esp32_cycles();let ready=0;let error=0;
    while !ready && !error {
        let status=esp32_load32(base+32);
        if status&(1<<10) {error=-6;}else if status&(1<<5) {error=-11;}else if status&(1<<8) {error=-110;}
        else if status&(1<<7) {ready=1;}else if ((esp32_cycles()-start)&4294967295)>=cycles {error=-110;}
    }
    if error {esp_reg_update(base+4,1<<10,1<<10);esp32_store32(base+36,16383);return error;}
    i=0;while i<rx_size {store8(rx+i,esp32_load32(base+28));i=i+1;}esp32_store32(base+36,16383);return tx_size+rx_size;
}
