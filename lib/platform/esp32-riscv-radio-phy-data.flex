// Default20dBm init bytes from pinned esp-phy0f0ebd92, C3/C6 params128.
fn esp_radio_phy_defaults(data){
    if rv_hal_chip==5{
        store64(data+0,0x484c4c5050500000);
        store64(data+8,0x4246464a4448484c);
        store64(data+16,0xffffffffff000000);
        store64(data+24,0xffffffffffffffff);
        store64(data+32,0xffffffffffffffff);
        store64(data+40,0xffffffffffffffff);
        store64(data+48,0xffffffffffffffff);
        store64(data+56,0xffffffffffffffff);
        store64(data+64,0x0000ffffffffffff);
        store64(data+72,0x0000000000000000);
        store64(data+80,0x0000000000000000);
        store64(data+88,0x0000000000000000);
        store64(data+96,0x0000000000000000);
        store64(data+104,0x7400000000000000);
        store64(data+112,0x0000000000000000);
        store64(data+120,0x0000000000000000);
    }else{
        store64(data+0,0x4c50505050500001);
        store64(data+8,0x28282828484c4c4c);
        store64(data+16,0x282828484c4c4c4c);
        store64(data+24,0xffffffff00000028);
        store64(data+32,0xffffffffffffffff);
        store64(data+40,0xffffffffffffffff);
        store64(data+48,0xffffffffffffffff);
        store64(data+56,0xffffffffffffffff);
        store64(data+64,0xffffffffffffffff);
        store64(data+72,0x00ffffffffffffff);
        store64(data+80,0x0000000000000000);
        store64(data+88,0x0000000000000000);
        store64(data+96,0x0000000000000000);
        store64(data+104,0x9b00000000000000);
        store64(data+112,0x0000000000000000);
        store64(data+120,0x0000000000000000);
    }return 0;
}
