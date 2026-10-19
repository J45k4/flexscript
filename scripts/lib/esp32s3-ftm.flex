// S3 FTM compensation data: esp-wifi-sys5afc3a38/esp-hal0f0ebd92.
// Vendor C macros and uint16 consumers are checked by the independent oracle.
fn er_s3_ftm(args,objtool,work) {
    let names=h_vec();let values=h_take(192);
    h_add(names,"est_PHY_INIT_FTM_COMP_20_20U_MHZ");store64(values+0,453);
    h_add(names,"est_PHY_RESP_FTM_COMP_20_20U_MHZ");store64(values+8,444);
    h_add(names,"est_PHY_INIT_FTM_COMP_20_20D_MHZ");store64(values+16,453);
    h_add(names,"est_PHY_RESP_FTM_COMP_20_20D_MHZ");store64(values+24,440);
    h_add(names,"est_PHY_INIT_FTM_COMP_20_20U_MHZ_DIS");store64(values+32,453);
    h_add(names,"est_PHY_INIT_FTM_COMP_20_20D_MHZ_DIS");store64(values+40,454);
    h_add(names,"est_PHY_RESP_FTM_COMP_20_20U_MHZ_DIS");store64(values+48,444);
    h_add(names,"est_PHY_RESP_FTM_COMP_20_20D_MHZ_DIS");store64(values+56,440);
    h_add(names,"est_PHY_INIT_FTM_COMP_40_40U_MHZ");store64(values+64,443);
    h_add(names,"est_PHY_RESP_FTM_COMP_40_40U_MHZ");store64(values+72,88);
    h_add(names,"est_PHY_INIT_FTM_COMP_40_40D_MHZ");store64(values+80,443);
    h_add(names,"est_PHY_RESP_FTM_COMP_40_40D_MHZ");store64(values+88,84);
    h_add(names,"est_PHY_INIT_FTM_COMP_20_40U_MHZ");store64(values+96,271);
    h_add(names,"est_PHY_RESP_FTM_COMP_20_40U_MHZ");store64(values+104,262);
    h_add(names,"est_PHY_INIT_FTM_COMP_20_40D_MHZ");store64(values+112,270);
    h_add(names,"est_PHY_RESP_FTM_COMP_20_40D_MHZ");store64(values+120,261);
    h_add(names,"est_PHY_INIT_FTM_COMP_20_40U_MHZ_DIS");store64(values+128,269);
    h_add(names,"est_PHY_RESP_FTM_COMP_20_40U_MHZ_DIS");store64(values+136,262);
    h_add(names,"est_PHY_INIT_FTM_COMP_20_40D_MHZ_DIS");store64(values+144,270);
    h_add(names,"est_PHY_RESP_FTM_COMP_20_40D_MHZ_DIS");store64(values+152,258);
    h_add(names,"est_PHY_INIT_FTM_COMP_40_40U_MHZ_DIS");store64(values+160,442);
    h_add(names,"est_PHY_RESP_FTM_COMP_40_40U_MHZ_DIS");store64(values+168,89);
    h_add(names,"est_PHY_INIT_FTM_COMP_40_40D_MHZ_DIS");store64(values+176,445);
    h_add(names,"est_PHY_RESP_FTM_COMP_40_40D_MHZ_DIS");store64(values+184,82);
    let i=0;while i<h_count(names) {let file=h_join(work,h_cat3("ftm-",h_int(i),".o"));let a=h_args(objtool,"--symbol",h_at(names,i),"--size","2","--value");h_add(a,h_int(load64(values+i*8)));h_add(a,"--output");h_add(a,file);h_ok(a);h_add(args,"--object");h_add(args,file);i=i+1;}return 0;
}
