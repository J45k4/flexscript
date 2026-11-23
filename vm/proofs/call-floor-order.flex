// The capacity check supplies the available-argument span. Subtracting the
// argument bytes leaves a new floor within the caller's operand range.
requires cursor >= 0 && cursor <= 524288;
requires floor >= 0 && floor <= cursor;
requires count >= 0 && count <= 4096;
requires count*8 <= cursor-floor;
ensures count*8 <= cursor && cursor-count*8 >= floor;
lemma fn call_argument_accept_order(cursor,floor,count) {
    let rest=cursor-count*8;
    assert count*8+floor <= cursor;
    assert floor+count*8 <= cursor;
    assert rest >= floor;
}
