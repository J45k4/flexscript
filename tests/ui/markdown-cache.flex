import "../../libs/ui/markdown-cache.flex";
fn main(){
    let text="## Notes\n\n**Hello**, [guide](https://example.test), 中文.\n\n| Name | Value |\n| --- | ---: |\n| One | 1 |\n";
    h_assert(h_equal(rt_cached_markdown_tables(text),rt_markdown_tables(text)),"stateless formatter changed");
    h_reset(0);rt_cache_open();
    h_assert(h_equal(rt_cached_markdown_tables(text),rt_markdown_tables(text)),"cold cached formatting changed");
    h_reset(0);
    let retained=rt_cached_markdown_tables(text);
    h_assert(h_equal(retained,rt_markdown_tables(text)),"cache did not survive frame arena reset");
    h_assert(!h_equal(rt_cached_markdown_tables("**first**"),rt_cached_markdown_tables("**other**")),"same-length updated text reused stale formatting");
    let i=0;while i<80{rt_cached_markdown_tables(h_cat("Replacement ",h_int(i)));i=i+1;}
    h_assert(h_equal(retained,rt_markdown_tables(text)),"eviction invalidated an earlier UI snapshot");
    h_assert(h_equal(rt_cached_markdown_tables(text),retained),"evicted Markdown did not reformat correctly");
    // Hit the byte limit with fewer than 64 entries, leaving empty slots.
    rt_cache_close();rt_cache_open();let body=h_zero(h_take(400001),400001);i=0;while i<400000{store8(body+i,97);i=i+1;}
    i=0;while i<24{let value=h_cat(h_int(i),body);h_assert(h_equal(rt_cached_markdown_tables(value),rt_markdown_tables(value)),"byte-budget eviction changed formatting");h_assert(rt_cache_bytes<=8388608,"cache exceeded byte budget");i=i+1;}
    rt_cache_close();h_assert(!rt_cache_bytes && !rt_cache_entries,"cache shutdown retained allocations");
    h_assert(h_equal(rt_cached_markdown_tables(text),rt_markdown_tables(text)),"formatter changed after cache shutdown");
    h_print(1,"PASS: native Markdown cache preserves formatting across frames, edits and bounded eviction\n");return 0;
}
