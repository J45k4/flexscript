import "esp32-riscv-ftm.flex";
// Explicit local C3/C6 Wi-Fi vendor linking. No compiler/library downloads.
// Keep compiled newlib/native exports authoritative over ROM aliases.
fn er_rv_inventory(path,directory,output){
 er_preserve(output,path);let text=h_read(path);let files=h_vec();let at=0;
 while load8(text+at){let begin=at;while load8(text+at) && load8(text+at)!=10{at=at+1;}let size=at-begin;
  if size>66 && load8(text+begin)!=35{let name=h_slice(text+begin+66,size-66);h_assert(!h_has(name,"/") && !h_has(name,"\\") && !h_equal(name,".") && !h_equal(name,".."),"invalid pinned inventory filename");let file=h_join(directory,name);er_preserve(output,file);er_pin_path(path,file,name);h_add(files,file);}if load8(text+at){at=at+1;}
 }h_assert(h_count(files),"empty pinned radio inventory");return files;
}
fn er_rv_rom_tail(value){let tail=h_trim(value);h_assert(!load8(tail) || load8(tail)==59 || load8(tail)==41,"unsupported pinned ROM expression");return 0;}
fn er_rv_rom_symbols(symbols,path){
 let text=h_read(path);let at=0;while load8(text+at){let begin=at;while load8(text+at) && load8(text+at)!=10{at=at+1;}let line=h_trim(h_slice(text+begin,at-begin));let eq=0;while load8(line+eq) && load8(line+eq)!=61{eq=eq+1;}
  if load8(line+eq){let name=h_trim(h_slice(line,eq));if h_len(name)>8 && h_equal(h_slice(name,7),"PROVIDE"){let start=7;while load8(name+start)==32 || load8(name+start)==9{start=start+1;}if load8(name+start)==40{name=h_trim(name+start+1);}}let value=h_trim(line+eq+1);
   if ee_valid_symbol(name) && load8(value)==48 && load8(value+1)==120{let n=2;while (load8(value+n)>=48 && load8(value+n)<=57) || (load8(value+n)>=97 && load8(value+n)<=102) || (load8(value+n)>=65 && load8(value+n)<=70){n=n+1;}if n>2{er_rv_rom_tail(value+n);j_set(symbols,name,j_string(h_slice(value,n)));}}else if ee_valid_symbol(name){let n=0;while (load8(value+n)>=65 && load8(value+n)<=90) || (load8(value+n)>=97 && load8(value+n)<=122) || (load8(value+n)>=48 && load8(value+n)<=57) || load8(value+n)==95{n=n+1;}let alias=h_slice(value,n);if ee_valid_symbol(alias) && !h_equal(name,alias){er_rv_rom_tail(value+n);j_set(symbols,name,j_string(alias));}}
  }if load8(text+at){at=at+1;}
 }return 0;
}
fn er_rv_defined(symbols,nm,path){
 let result=h_ok(h_args(nm,"--defined-only","--extern-only","-P",path,0));let text=h_out(result);let at=0;
 while load8(text+at){let begin=at;while load8(text+at) && load8(text+at)!=10{at=at+1;}let line=h_trim(h_slice(text+begin,at-begin));let space=0;while load8(line+space) && load8(line+space)!=32 && load8(line+space)!=9{space=space+1;}
  if load8(line+space){let name=h_slice(line,space);let type=h_trim(line+space);if load8(type) && (load8(type+1)==32 || load8(type+1)==9) && j_get(symbols,name){j_set(symbols,name,j_int(0));}}
  if load8(text+at){at=at+1;}
 }return 0;
}
fn er_rv_build(argc,argv,compiler,vendor,rom,output,kind,chip){
 h_assert(h_equal(kind,"wifi"),"C3/C6 Bluetooth vendor startup is not yet integrated");h_assert(!b_option(argc,argv,"--tls",0),"C3/C6 TLS vendor archives require a matching native profile");let source=b_option(argc,argv,"--source",0);h_assert(source,"C3/C6 vendor builds require --source app.flex while full radio startup is being integrated");
 output=h_absolute(output);source=h_absolute(source);vendor=h_absolute(vendor);rom=h_absolute(rom);let name=h_cat("esp32c",h_int(chip));let archive_inventory=h_cat3("docs/",name,"-vendor-sha256.txt");let rom_inventory=h_cat3("docs/",name,"-rom-sha256.txt");let libc_inventory="docs/esp32-riscv-libc-sha256.txt";
 er_preserve(output,source);er_preserve(output,compiler);er_preserve(output,libc_inventory);h_assert(!er_alias(output,h_cat(output,".map")) && !er_alias(output,h_cat(output,".elf")) && !er_alias(h_cat(output,".map"),h_cat(output,".elf")),"radio output paths alias");
 let archives=er_rv_inventory(archive_inventory,vendor,output);let maps=er_rv_inventory(rom_inventory,rom,output);let libc=b_option(argc,argv,"--libc",0);let libgcc=b_option(argc,argv,"--libgcc",0);let libm=b_option(argc,argv,"--libm",0);
 if !libc || !libgcc || !libm{let gcc=h_executable(b_option(argc,argv,"--gcc","riscv32-esp-elf-gcc"));er_preserve(output,gcc);if !libc{libc=h_trim(h_out(h_ok(h_args(gcc,"-march=rv32imc","-mabi=ilp32","-print-file-name=libc.a",0,0))));}if !libm{libm=h_trim(h_out(h_ok(h_args(gcc,"-march=rv32imc","-mabi=ilp32","-print-file-name=libm.a",0,0))));}if !libgcc{libgcc=h_trim(h_out(h_ok(h_args(gcc,"-march=rv32imc","-mabi=ilp32","-print-libgcc-file-name",0,0))));}}
 libc=h_real(libc);libgcc=h_real(libgcc);libm=h_real(libm);er_preserve(output,libc);er_preserve(output,libgcc);er_preserve(output,libm);er_pin_path(libc_inventory,libc,"libc.a");er_pin_path(libc_inventory,libgcc,"libgcc.a");er_pin_path(libc_inventory,libm,"libm.a");h_add(archives,libc);h_add(archives,libgcc);h_add(archives,libm);let nm=h_real(h_executable(b_option(argc,argv,"--nm","riscv32-esp-elf-nm")));let ld=h_real(h_executable(b_option(argc,argv,"--ld","riscv32-esp-elf-ld")));
 let objcopy=b_option(argc,argv,"--objcopy",0);if !objcopy{h_assert(h_len(nm)>2 && h_equal(h_slice(nm+h_len(nm)-2,2),"nm"),"nonstandard nm requires --objcopy PATH");objcopy=h_cat(h_slice(nm,h_len(nm)-2),"objcopy");}objcopy=h_real(h_executable(objcopy));er_preserve(output,objcopy);er_preserve(output,nm);er_preserve(output,ld);let work=h_temp();let linker=h_join(work,"linker");let data=h_join(work,"data-object");let firmware=h_join(work,"native.elf");h_compile(compiler,"scripts/esp32-link.flex",linker);h_compile(compiler,"scripts/esp32-data-object.flex",data);h_ok(h_args(compiler,"--target",h_cat(name,"-radio-elf"),source,"-o",firmware));
 let args=h_args(linker,"--ld",ld,"--xip","--firmware",firmware);h_add(args,"--newlib-stdio");h_add(args,"--newlib-rom");h_add(args,"--output");h_add(args,h_cat(output,".elf"));h_add(args,"--image");h_add(args,output);h_add(args,"--map");h_add(args,h_cat(output,".map"));
 let symbols=j_object();let i=0;while i<h_count(maps){er_rv_rom_symbols(symbols,h_at(maps,i));i=i+1;}er_rv_defined(symbols,nm,firmware);i=0;while i<h_count(archives){let archive=h_at(archives,i);if h_equal(archive,h_join(vendor,"libwpa_supplicant.a")){let visible=h_join(work,"wpa-lifecycle.a");h_ok(h_args(objcopy,"--globalize-symbol=eloop_data_lock",archive,visible,0,0));archive=visible;}er_rv_defined(symbols,nm,archive);h_add(args,"--archive");h_add(args,archive);i=i+1;}
 let event=h_join(work,"WIFI_EVENT.o");let osi=h_join(work,"g_wifi_osi_funcs.o");let bytes="480";if chip==6{bytes="508";}
 let cmd=h_args(data,"--arch","riscv32","--symbol","WIFI_EVENT","--output");h_add(cmd,event);h_ok(cmd);cmd=h_args(data,"--arch","riscv32","--symbol","g_wifi_osi_funcs","--size");h_add(cmd,bytes);h_add(cmd,"--output");h_add(cmd,osi);h_ok(cmd);h_add(args,"--object");h_add(args,event);h_add(args,"--object");h_add(args,osi);er_rv_defined(symbols,nm,event);er_rv_defined(symbols,nm,osi);
 er_rv_ftm(args,data,work,chip);
 let aliases=h_buffer();let fields=j_value(symbols);i=0;while i<h_count(fields){let row=h_at(fields,i);let value=load64(row+8);if j_kind(value)==2{h_text(aliases,h_cat3("PROVIDE(",load64(row),"="));h_text(aliases,h_cat(j_value(value),");\n"));}i=i+1;}let script=h_join(work,"ROM-aliases.ld");h_save(script,h_data(aliases));h_add(args,"--rom");h_add(args,script);h_print(1,h_out(h_ok(args)));h_remove(work);return 0;
}
