// Optional standalone native application builder.
import "../libs/monolith/internal/schema.flex";
fn main(argc,argv) {
    h_environment(argc,argv);
    if argc<3 || !h_equal(load64(argv+8),"build") {h_print(2,"Usage: monolith build APP --schema SCHEMA --compiler FLEXSCRIPT -o OUTPUT\nRun from the Flexscript repository root.\n");return 1;}
    let app=h_real(load64(argv+16));let schema=0;let compiler=0;let output=0;let i=3;
    while i<argc {
        h_assert(i+1<argc,"missing option value");let option=load64(argv+i*8);let value=load64(argv+(i+1)*8);
        if h_equal(option,"--schema") {h_assert(!schema,"duplicate schema option");schema=value;}
        else if h_equal(option,"--compiler") {h_assert(!compiler,"duplicate compiler option");compiler=value;}
        else if h_equal(option,"-o") {h_assert(!output,"duplicate output option");output=value;}
        else {h_die(h_cat("unknown option: ",option));}i=i+2;
    }
    h_assert(schema && compiler && output,"schema, compiler and output are required");
    let generated=sc_compile(schema);compiler=h_real(compiler);output=h_absolute(output);
    h_assert(!h_equal(app,output) && !h_equal(h_real(schema),output) && !h_equal(compiler,output) && !sc_alias(app,output) && !sc_alias(schema,output) && !sc_alias(compiler,output),"output aliases an input");
    h_mkdir(h_dir(output));let code=h_buffer();h_text(code,h_cat3("import ",sc_literal(app),";\n"));h_text(code,generated);
    let entry=h_cat(output,".generated.flex");h_assert(!sc_alias(entry,app) && !sc_alias(entry,schema) && !sc_alias(entry,compiler),"generated output aliases an input");h_save(entry,h_data(code));
    let random=h_take(8);h_assert(syscall(318,random,8,0,0,0,0)==8,"temporary name failed");let temporary=h_cat(output,h_cat(".tmp-",h_hex(random,8)));
    h_compile(compiler,entry,temporary);h_assert(syscall(82,temporary,output,0,0,0,0)==0,"atomic output replacement failed");h_print(1,h_cat3("Built ",output,"\n"));return 0;
}
