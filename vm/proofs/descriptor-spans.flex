requires slot>=0 && slot<67;
requires writable_bytes(table,536);
ensures writable_bytes(table+slot*8,8);
ensures readable_bytes(table+slot*8,8);
lemma fn vm_init_descriptor_grant(table,slot) {
    assert slot*8>=0 && slot*8<=528;
}

requires first>=0 && first<67;
requires second>=0 && second<67;
requires first!=second;
requires writable_bytes(table,536);
ensures disjoint_bytes(table+first*8,8,table+second*8,8);
lemma fn vm_init_descriptor_separation(table,first,second) {
    vm_init_descriptor_grant(table,first);
    vm_init_descriptor_grant(table,second);
    if first<second {assert (first+1)*8<=second*8;}
    else {assert (second+1)*8<=first*8;}
}
