// Operation spies and scripted samples only; no timing/peripheral emulator.
import "../../lib/platform/esp32s3-adc.flex";
global sa_ref=0;global sa_regs=0;global sa_n=0;global sa_checks=0;
global sa_ps=0;global sa_ticks=0;global sa_depth=0;global sa_writes=0;
global sa_unit=0;global sa_channel=0;global sa_attenuation=0;
global sa_mode=0;global sa_flags=0;global sa_pending=0;global sa_polls=0;
global sa_idles=0;
global sa_starts=0;global sa_reentry=0;global sa_reentries=0;global sa_drift=0;
fn sv(i) {return load64(sa_ref+16+i*8);}
fn sc(ok,id) {sa_checks=sa_checks+1;if !ok {let p=alloc(16);store64(p,id);store64(p+8,sa_checks);syscall(1,2,p,16,0,0,0);syscall(60,1,0,0,0,0,0);}return 0;}
fn si(address) {let i=0;while i<sa_n {if load64(sa_regs+i*16)==address {return i;}i=i+1;}store64(sa_regs+i*16,address);store64(sa_regs+i*16+8,0);sa_n=sa_n+1;return i;}
fn sg(address) {return load64(sa_regs+si(address)*16+8);}
fn ss(address,value) {store64(sa_regs+si(address)*16+8,value&4294967295);return 0;}
fn esp32_state() {return 0x3fcc0000;}
fn esp32_irq_save() {let old=sa_ps;sa_ps=sa_ps|15;return old;}
fn esp32_irq_restore(ps) {sa_ps=ps;return 0;}
fn esp32_cycles() {sa_ticks=(sa_ticks+50)&4294967295;return sa_ticks;}
fn sample() {return (sa_unit*103+sa_channel*271+sa_attenuation*523+0x987)&4095;}
fn esp32_load32(address) {
    if address==esp32_state()+16 {return sa_depth;}
    if address==sv(9) && sa_mode==1 {return sv(41);}
    if address==sv(9) && sa_mode==5 {sa_idles=sa_idles+1;if sa_idles<=2 {return sv(41);}return 0;}
    if sa_pending && address==sv(1+sa_pending) {
        sa_polls=sa_polls+1;
        if sa_mode!=2 && sa_polls>=3 {let flag=sa_flags*(sv(57)&-sv(57));ss(address,(sg(address)&~sv(31))|sv(27)|sample()|flag);sa_pending=0;}
    }return sg(address);
}
fn starting(unit) {
    let read=sv(unit-1);let inv=sv(31+unit);let interrupt=sv(33+unit);
    sc((sg(read)&sv(36))==1 && !(sg(read)&(inv|interrupt)),101);
    sc((sg(sv(13))&sv(42))==sv(42) && (sg(sv(10))&sv(37))==sv(37) && (sg(sv(8))&sv(38))==sv(38),102);
    sc(!(sg(sv(3+unit))&(1<<31)),103);
    let attenuation=(sg(sv(5+unit))>>(sa_channel*2))&3;sc(attenuation==sa_attenuation,104);
    let pad=(sv(28)&-sv(28))*(1<<sa_channel);let mask=sv(28)|sv(29)|sv(30);sc((sg(sv(1+unit))&mask)==(pad|sv(29)|sv(30)),105);
    if unit==2 {sc((sg(sv(12))&sv(39))==sv(40),106);}
    if sa_mode==4 {ss(sv(10),sg(sv(10))^(1<<31));sa_drift=1;}
    return 0;
}
fn esp32_store32(address,value) {
    sc((sa_ps&15)==15,90);sa_writes=sa_writes+1;value=value&4294967295;
    if esp_adc_busy && !sa_reentry {
        sa_reentry=1;let before=sa_writes;let count=s3a_saved_count;
        sc(esp_adc_init(sa_unit,sa_channel,0)== -16 && esp_adc_read(sa_unit,sa_channel,100)== -16 && esp_adc_deinit(sa_unit,sa_channel)== -16,91);
        sc((sa_ps&15)==15 && sa_writes==before && s3a_saved_count==count && esp_adc_busy==sa_unit,92);sa_reentry=0;sa_reentries=sa_reentries+1;
    }
    let unit=1;while unit<=2 {
        if address==sv(1+unit) {
            let old=sg(address);value=(value&~(sv(31)|sv(27)))|(old&(sv(31)|sv(27)));ss(address,value);
            if (value&sv(26)) && !(old&sv(26)) {sc(esp_adc_busy==unit,93);sa_starts=sa_starts+1;starting(unit);sa_pending=unit;sa_polls=0;ss(address,value&~sv(27));}
            if !(value&sv(26)) {sa_pending=0;}return 0;
        }unit=unit+1;
    }ss(address,value);return 0;
}
fn snapshot(p) {let i=0;while i<22 {store64(p+i*8,sg(sv(i)));i=i+1;}return 0;}
fn restored(p) {
    let i=0;while i<22 {let mask=4294967295;let expected=load64(p+i*8);
        if i==2 || i==3 {mask=mask&~(sv(31)|sv(27));}
        if i==10 && sa_drift {expected=expected^(1<<31);}
        sc((sg(sv(i))&mask)==(expected&mask),200+i);i=i+1;
    }sc(!esp_adc_busy && !s3a_saved_count && !sa_pending,222);return 0;
}
fn prepare(index,attenuation) {
    sa_unit=1+index/10;sa_channel=index%10;sa_attenuation=attenuation;sa_mode=0;sa_flags=0;sa_drift=0;sa_pending=0;
    let i=0;while i<22 {ss(sv(i),((i+1)*0x1234567+index*0x19631+attenuation*97)&4294967295);i=i+1;}
    ss(sv(0),sg(sv(0))|sv(32)|sv(34));ss(sv(1),sg(sv(1))|sv(33)|sv(35));
    i=2;while i<4 {ss(sv(i),sg(sv(i))&~sv(26));i=i+1;}
    i=4;while i<6 {ss(sv(i),sg(sv(i))&~(1<<31));i=i+1;}
    ss(sv(9),0);ss(sv(10),sg(sv(10))&~sv(43));ss(sv(11),sg(sv(11))&~sv(44));ss(sv(14),sg(sv(14))&~sv(42));
    i=15;while i<20 {ss(sv(i),0);i=i+1;}ss(sv(20),sg(sv(20))&~sv(49));ss(sv(21),sg(sv(21))&~sv(50));
    let pin=sv(62+index);ss(sv(23)+pin*4,0x65a59a5a|sv(51)|sv(52)|sv(53)|sv(54));ss(sv(25)+pin*4,0xc35a695a);sa_depth=0;esp_radio_owner=0;esp_radio_phy_refs=0;esp_radio_phy_clock_refs=0;return 0;
}
fn denied(unit,channel,expected) {
    let writes=sa_writes;let count=sa_starts;let state=load64(s3a_state+s3a_index(unit,channel)*16);let attenuation=load64(s3a_state+s3a_index(unit,channel)*16+8);let ps=sa_ps;
    sc(esp_adc_init(unit,channel,0)==expected && esp_adc_read(unit,channel,10000)==expected && esp_adc_deinit(unit,channel)==expected,300);
    sc(sa_writes==writes && sa_starts==count && sa_ps==ps && load64(s3a_state+s3a_index(unit,channel)*16)==state && load64(s3a_state+s3a_index(unit,channel)*16+8)==attenuation,301);return 0;
}
fn main(argc,argv) {
    if argc!=2 {return 99;}sa_ref=alloc(2048);let fd=syscall(2,load64(argv+8),0,0,0,0,0);if fd<0 {return 98;}let n=syscall(0,fd,sa_ref,2048,0,0,0);syscall(3,fd,0,0,0,0,0);
    if n!=672 || load64(sa_ref)!=0x5333414443000001 || load64(sa_ref+8)!=82 {return 97;}sa_regs=alloc(32768);let saved=alloc(176);let pad_saved=alloc(176);
    sc(esp_adc_read(1,0,100)== -19 && esp_adc_deinit(1,0)==0 && !s3a_state,1);
    prepare(0,0);let first_hold=0;while first_hold<4 {let address=sv(18+first_hold);let mask=1<<sv(62);if first_hold==2 {mask=sv(49);}else if first_hold==3 {mask=sv(50);}let old=sg(address);ss(address,old|mask);let writes=sa_writes;sc(esp_adc_init(1,0,0)== -16 && !s3a_state && sa_writes==writes,30);ss(address,old);first_hold=first_hold+1;}
    sa_depth=1;sc(esp_adc_init(1,0,0)== -16 && !s3a_state,31);sa_depth=0;esp_radio_owner=1;sc(esp_adc_init(2,0,0)== -16 && !s3a_state,32);esp_radio_owner=0;
    let index=0;while index<20 {let unit=1+index/10;let channel=index%10;let pin=sv(62+index);sc(esp_adc_pin(unit,channel)==pin,2);
        let attenuation=0;while attenuation<4 {prepare(index,attenuation);snapshot(saved);let pad=sg(sv(23)+pin*4);let digital=sg(sv(25)+pin*4);
            let level=0;while level<5 {sa_ps=0x40000|((1<<level)-1);let ps=sa_ps;let starts=sa_starts;let writes=sa_writes;
                sc(!esp_adc_init(unit,channel,attenuation) && sa_ps==ps,3);
                sc(load64(s3a_state+index*16)==1 && load64(s3a_state+index*16+8)==attenuation,4);
                sc(sg(sv(23)+pin*4)==((pad&~(sv(51)|sv(52)|sv(53)|sv(54)))|sv(51)),5);
                sc(sg(sv(25)+pin*4)==((digital&~(sv(58)|sv(55)|sv(61)))|sv(59)) && sg(sv(24))==(1<<pin) && sg(sv(22))==(1<<(pin+sv(56))),6);restored(saved);
                sa_ticks=4294967280;sa_mode=0;sc(esp_adc_read(unit,channel,10000)==sample() && sa_ps==ps && sa_starts==starts+1,7);restored(saved);
                starts=sa_starts;sa_mode=2;sc(esp_adc_read(unit,channel,250)== -110 && sa_ps==ps && sa_starts==starts+1,8);restored(saved);
                sa_mode=0;sc(esp_adc_read(unit,channel,10000)==sample() && sa_ps==ps,9);restored(saved);
                starts=sa_starts;sc(esp_adc_read(unit,channel,1)== -110 && sa_starts==starts && sa_ps==ps,10);restored(saved);
                if unit==1 {sa_mode=1;sc(esp_adc_read(unit,channel,250)== -110 && sa_starts==starts && sa_ps==ps,11);restored(saved);sa_idles=0;sa_mode=5;sc(esp_adc_read(unit,channel,250)== -110 && sa_starts==starts+1 && sa_ps==ps,33);restored(saved);sa_mode=0;}
                else {let flag=1;while flag<=3 {sa_flags=flag;sc(esp_adc_read(unit,channel,10000)== -11 && sa_ps==ps,12);restored(saved);flag=flag+1;}sa_flags=0;}
                // Masked read-modify-restore preserves a new unrelated device bit.
                sa_mode=4;sc(esp_adc_read(unit,channel,10000)==sample() && sa_ps==ps,13);restored(saved);ss(sv(10),load64(saved+80));sa_mode=0;sa_drift=0;
                esp_adc_busy=2;denied(unit,channel,-16);esp_adc_busy=0;sa_depth=1;denied(unit,channel,-16);sa_depth=0;
                let radio=0;while radio<4 {esp_radio_owner=0;esp_radio_phy_refs=0;esp_radio_phy_clock_refs=0;
                    if radio<2 {esp_radio_owner=radio+1;}else if radio==2 {esp_radio_phy_refs=1;}else {esp_radio_phy_clock_refs=1;}
                    if unit==2 {denied(unit,channel,-16);}else {sc(esp_adc_read(unit,channel,10000)==sample() && sa_ps==ps,14);restored(saved);}radio=radio+1;
                }esp_radio_owner=0;esp_radio_phy_refs=0;esp_radio_phy_clock_refs=0;
                let hold=0;while hold<4 {let address=sv(18+hold);let mask=1<<pin;if hold==2 {mask=sv(49);}if hold==3 {mask=sv(50);}let old=sg(address);ss(address,old|mask);denied(unit,channel,-16);ss(address,old);hold=hold+1;}
                let busy=0;while busy<9 {let address=sv(3+unit);let mask=1<<31;
                    if busy==1 {address=sv(1+unit);mask=sv(26);}else if busy==2 {address=sv(10);mask=sv(43);}else if busy==3 {address=sv(11);mask=sv(44);}else if busy==4 {address=sv(14);mask=sv(42);}
                    else if busy==5 {address=sv(15);mask=sv(44+unit);}else if busy==6 {address=sv(16);mask=sv(47);}else if busy==7 {address=sv(17);mask=sv(48)&-sv(48);}
                    else if busy==8 {address=sv(17);mask=sv(48)&~(sv(48)&-sv(48));}
                    let old=sg(address);ss(address,old|mask);denied(unit,channel,-16);ss(address,old);
                    busy=busy+1;
                }
                writes=sa_writes;sc(esp_adc_init(unit,channel,4)== -22 && esp_adc_read(unit,channel,0)== -22 && esp_adc_read(unit,channel,2147483648)== -22 && sa_writes==writes && sa_ps==ps,15);
                snapshot(pad_saved);sc(!esp_adc_deinit(unit,channel) && !esp_adc_deinit(unit,channel) && esp_adc_read(unit,channel,10000)== -19 && sa_ps==ps,16);
                sc(!(sg(sv(23)+pin*4)&sv(51)) && !load64(s3a_state+index*16),17);restored(pad_saved);
                level=level+1;
            }attenuation=attenuation+1;
        }index=index+1;
    }
    let writes=sa_writes;sc(esp_adc_init(0,0,0)== -22 && esp_adc_init(3,0,0)== -22 && esp_adc_init(1,-1,0)== -22 && esp_adc_init(2,10,0)== -22 && esp_adc_read(0,0,1)== -22 && esp_adc_deinit(1,10)== -22 && esp_adc_pin(2,10)== -22 && sa_writes==writes,18);
    sc(sa_reentries>10000,19);let out=alloc(16);store64(out,sa_checks);store64(out+8,sa_reentries);syscall(1,1,out,16,0,0,0);return 0;
}
