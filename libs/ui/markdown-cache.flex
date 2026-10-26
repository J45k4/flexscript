// Optional native cache. Stateless hosts keep using the ordinary formatter.
import "markdown-tables.flex";
global rt_cache_entries=0;
global rt_cache_bytes=0;
global rt_cache_clock=0;
fn rt_cache_open(){if !rt_cache_entries{rt_cache_entries=h_zero(alloc(512),512);}return 0;}
fn rt_cache_drop(slot){let entry=load64(slot);if entry{let bytes=load64(entry);syscall(11,entry,bytes,0,0,0,0);rt_cache_bytes=rt_cache_bytes-bytes;store64(slot,0);}return 0;}
fn rt_cache_close(){if rt_cache_entries{let i=0;while i<64{rt_cache_drop(rt_cache_entries+i*8);i=i+1;}syscall(11,rt_cache_entries,512,0,0,0,0);}rt_cache_entries=0;rt_cache_clock=0;return 0;}
fn rt_cache_oldest(){let oldest=0;let age=0;let i=0;while i<64{let slot=rt_cache_entries+i*8;let entry=load64(slot);if entry{if !oldest || load64(entry+8)<age{oldest=slot;age=load64(entry+8);}}i=i+1;}return oldest;}
fn rt_cache_slot(){let i=0;while i<64{let slot=rt_cache_entries+i*8;if !load64(slot){return slot;}i=i+1;}return rt_cache_oldest();}
fn rt_cached_markdown_tables(text){
    if !rt_cache_entries{return rt_markdown_tables(text);}
    rt_cache_clock=rt_cache_clock+1;let n=h_len(text);let i=0;
    while i<64{let entry=load64(rt_cache_entries+i*8);if entry && load64(entry+16)==n && h_equal(entry+32,text){
        store64(entry+8,rt_cache_clock);
        // UI snapshots retain their strings until the frame ends. Return a
        // frame-owned copy so a later cache eviction cannot invalidate them.
        return h_slice(entry+33+n,load64(entry+24));
    }i=i+1;}
    let formatted=rt_markdown_tables(text);let length=h_len(formatted);let bytes=((34+n+length+4095)/4096)*4096;
    // Bound both unusually large individual messages and total retained memory.
    if bytes>1048576{return formatted;}
    while rt_cache_bytes+bytes>8388608{rt_cache_drop(rt_cache_oldest());}
    let slot=rt_cache_slot();rt_cache_drop(slot);let entry=alloc(bytes);store64(entry,bytes);store64(entry+8,rt_cache_clock);store64(entry+16,n);store64(entry+24,length);h_copy(entry+32,text,n+1);h_copy(entry+33+n,formatted,length+1);store64(slot,entry);rt_cache_bytes=rt_cache_bytes+bytes;return formatted;
}
