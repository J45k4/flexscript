// Pinned esp-wifi-sys5afc3a38 FTM uint16 data; C3/C6 coefficient oracle.
fn er_rv_ftm(args,objtool,work,chip){
 h_assert(chip==3 || chip==6,"unsupported RISC-V FTM profile");let names=h_vec();let values=h_take(192);
 h_add(names,"est_PHY_INIT_FTM_COMP_20_20U_MHZ");let value0=451;if chip==6{value0=704;}store64(values+0,value0);
 h_add(names,"est_PHY_INIT_FTM_COMP_20_20U_MHZ_DIS");let value1=448;if chip==6{value1=711;}store64(values+8,value1);
 h_add(names,"est_PHY_INIT_FTM_COMP_20_20D_MHZ");let value2=454;if chip==6{value2=707;}store64(values+16,value2);
 h_add(names,"est_PHY_INIT_FTM_COMP_20_20D_MHZ_DIS");let value3=455;if chip==6{value3=717;}store64(values+24,value3);
 h_add(names,"est_PHY_RESP_FTM_COMP_20_20U_MHZ");let value4=439;if chip==6{value4=714;}store64(values+32,value4);
 h_add(names,"est_PHY_RESP_FTM_COMP_20_20U_MHZ_DIS");let value5=441;if chip==6{value5=706;}store64(values+40,value5);
 h_add(names,"est_PHY_RESP_FTM_COMP_20_20D_MHZ");let value6=431;if chip==6{value6=712;}store64(values+48,value6);
 h_add(names,"est_PHY_RESP_FTM_COMP_20_20D_MHZ_DIS");let value7=433;if chip==6{value7=702;}store64(values+56,value7);
 h_add(names,"est_PHY_INIT_FTM_COMP_20_40U_MHZ");let value8=260;if chip==6{value8=601;}store64(values+64,value8);
 h_add(names,"est_PHY_INIT_FTM_COMP_20_40U_MHZ_DIS");let value9=267;if chip==6{value9=610;}store64(values+72,value9);
 h_add(names,"est_PHY_INIT_FTM_COMP_20_40D_MHZ");let value10=268;if chip==6{value10=605;}store64(values+80,value10);
 h_add(names,"est_PHY_INIT_FTM_COMP_20_40D_MHZ_DIS");let value11=270;if chip==6{value11=616;}store64(values+88,value11);
 h_add(names,"est_PHY_RESP_FTM_COMP_20_40U_MHZ");let value12=252;if chip==6{value12=609;}store64(values+96,value12);
 h_add(names,"est_PHY_RESP_FTM_COMP_20_40U_MHZ_DIS");let value13=259;if chip==6{value13=614;}store64(values+104,value13);
 h_add(names,"est_PHY_RESP_FTM_COMP_20_40D_MHZ");let value14=247;if chip==6{value14=608;}store64(values+112,value14);
 h_add(names,"est_PHY_RESP_FTM_COMP_20_40D_MHZ_DIS");let value15=250;if chip==6{value15=611;}store64(values+120,value15);
 h_add(names,"est_PHY_INIT_FTM_COMP_40_40U_MHZ");let value16=443;if chip==6{value16=786;}store64(values+128,value16);
 h_add(names,"est_PHY_INIT_FTM_COMP_40_40U_MHZ_DIS");let value17=439;if chip==6{value17=786;}store64(values+136,value17);
 h_add(names,"est_PHY_INIT_FTM_COMP_40_40D_MHZ");let value18=440;if chip==6{value18=791;}store64(values+144,value18);
 h_add(names,"est_PHY_INIT_FTM_COMP_40_40D_MHZ_DIS");let value19=440;if chip==6{value19=794;}store64(values+152,value19);
 h_add(names,"est_PHY_RESP_FTM_COMP_40_40U_MHZ");let value20=82;if chip==6{value20=436;}store64(values+160,value20);
 h_add(names,"est_PHY_RESP_FTM_COMP_40_40U_MHZ_DIS");let value21=86;if chip==6{value21=436;}store64(values+168,value21);
 h_add(names,"est_PHY_RESP_FTM_COMP_40_40D_MHZ");let value22=80;if chip==6{value22=436;}store64(values+176,value22);
 h_add(names,"est_PHY_RESP_FTM_COMP_40_40D_MHZ_DIS");let value23=81;if chip==6{value23=433;}store64(values+184,value23);
 let i=0;while i<h_count(names){let file=h_join(work,h_cat3("ftm-",h_int(i),".o"));let cmd=h_args(objtool,"--arch","riscv32","--symbol",h_at(names,i),"--size");h_add(cmd,"2");h_add(cmd,"--value");h_add(cmd,h_int(load64(values+i*8)));h_add(cmd,"--output");h_add(cmd,file);h_ok(cmd);h_add(args,"--object");h_add(args,file);i=i+1;}return 0;
}
