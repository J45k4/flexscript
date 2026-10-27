import "../../lib/ffi-words.flex";
fn main(argc,argv){
    if argc!=2{return 1;}let library=ffi_open(load64(argv+8));let c=ffi_words_context();if !library || !c{return 2;}
    let args=alloc(96);let target=ffi_symbol(library,"words12");let n=0;while n<=12{
        let i=0;let expected=0;while i<12{let value=0;if i<n{value=i*17-111;expected=expected+value*(i+1);}store64(args+i*8,value);i=i+1;}
        let kept=0x123456789abcdef;let actual=ffi_words_call(c,target,args,n);if actual!=expected || kept!=0x123456789abcdef{return 3;}n=n+1;
    }
    target=ffi_symbol(library,"words_varargs");store64(args,11);let i=1;let expected=0;while i<12{store64(args+i*8,i*33);expected=expected+i*i*33;i=i+1;}
    if ffi_words_call(c,target,args,12)!=expected{return 4;}
    if ffi_words_call(c,target,args,13) || ffi_words_call(c,target,0,1){return 5;}
    target=ffi_symbol(library,"words12");i=0;expected=0;while i<11{store64(args+i*8,i*31-109);expected=expected+(i*31-109)*(i+1);i=i+1;}
    if ffi_call_words(target,args)!=expected{return 6;}ffi_call_words_close();
    ffi_words_free(c);syscall(11,args,96,0,0,0,0);return 0;
}
