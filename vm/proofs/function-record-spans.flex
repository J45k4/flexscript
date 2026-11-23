requires index>=0 && index<capacity && capacity<=18432;
ensures index+1<=capacity;
ensures index>=0 && index<=18431;
lemma fn function_record_index_bounds(index,capacity) {}

requires first>=0 && first<=last && last<=18432;
ensures first*32<=last*32;
lemma fn function_record_scale_order(first,last) {}

requires index>=0 && index<=18431;
ensures index*32>=0;
ensures index*32+32==(index+1)*32;
lemma fn function_record_offset(index) {}

requires capacity>=2048 && capacity<=18432;
requires index>=0 && index<capacity;
requires writable_bytes(table,capacity*32);
ensures writable_bytes(table+index*32,32);
ensures readable_bytes(table+index*32,32);
lemma fn function_record_grant(table,index,capacity) {
    function_record_index_bounds(index,capacity);
    function_record_scale_order(index+1,capacity);
    function_record_offset(index);
}

requires capacity>=2048 && capacity<=18432;
requires index>=0 && index<capacity;
requires count==index+1;
ensures index<count && count<=capacity;
lemma fn function_count_after_reserve(index,count,capacity) {}
