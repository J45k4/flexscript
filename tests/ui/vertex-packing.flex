// CPU-only GL vertex ABI fixture. The Python oracle uses standard little-endian
// struct packing, independently of renderer writes. Each record keeps original
// 64-bit inputs, an 8-byte guard, the 24-byte vertex, and another 8-byte guard.
import "../../libs/gui/renderer/gl.flex";
import "../../scripts/lib/json.flex";
fn main(argc,argv){
    h_environment(argc,argv);h_assert(argc==2,"Provide vertex-record output path");let count=2060;let bytes=count*88;let records=alloc(bytes);h_assert(records>0,"Vertex fixture allocation failed");bytes_fill(records,0xa5,bytes);let edges=alloc(80);store64(edges,0);store64(edges+8,1);store64(edges+16,-1);store64(edges+24,0x7fffffff);store64(edges+32,0x80000000);store64(edges+40,0xffffffff);store64(edges+48,0x100000000);store64(edges+56,-0x100000000);store64(edges+64,0x7fffffffffffffff);store64(edges+72,-0x7fffffffffffffff-1);
    let state=0x6a09e667f3bcc909;let i=0;while i<count{let row=records+i*88;let j=0;while j<6{let value=0;if i<12{value=load64(edges+((i+j*3)%10)*8);}else{state=state*6364136223846793005+1442695040888963407;value=state;}store64(row+j*8,value);j=j+1;}gr_vertex(row+56,load64(row),load64(row+8),load64(row+16),load64(row+24),load64(row+32),load64(row+40));i=i+1;}
    h_save_bytes(load64(argv+8),records,bytes,420);syscall(11,records,bytes,0,0,0,0);syscall(11,edges,80,0,0,0,0);h_print(1,"PASS vertex records generated without opening a display\n");return 0;
}
