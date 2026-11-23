import "cad/project-arrangement.flex";

fn test_segment(segments,x0,y0,x1,y1,source) {
    return cg_push(segments,cg_v(cg_v(x0*1000000,y0*1000000,0),cg_v(x1*1000000,y1*1000000,0),source));
}

fn test_outer(reversed) {
    let segments=cg_array();
    if reversed {test_segment(segments,80,-50,-80,-50,1);}
    else {test_segment(segments,-80,-50,80,-50,1);}
    test_segment(segments,80,-50,80,50,2);
    test_segment(segments,80,50,-80,50,3);
    test_segment(segments,-80,50,-80,-50,4);
    return segments;
}

fn test_bounds(loop,low,high) {
    let points=load64(loop);let min=500000001;let max=-500000001;let i=0;
    while i<cg_count(points) {
        let x=load64(cg_at(points,i));
        if x<min {min=x;}if x>max {max=x;}i=i+1;
    }
    m_assert(min==low*1000000 && max==high*1000000,"Wrong region ordinal or boundary");
}

fn test_asymmetric(reversed) {
    cg_begin();let segments=test_outer(reversed);
    m_assert(!pc_arrangement_needed(segments),"Unbranched profiles use the ordinary contour path");
    test_segment(segments,-40,50,-40,-50,5);
    m_assert(pc_arrangement_needed(segments),"Divider endpoints sit inside boundary edges");
    let loops=cg_array();m_assert(pc_arrangement_trace(segments,loops),cg_error);
    m_assert(cg_count(loops)==2,"Only positive bounded faces");
    let first=cg_at(loops,0);let second=cg_at(loops,1);
    m_assert(load64(first+8)==1 && load64(second+8)==1,"Both region seeds come from the split first boundary");
    if reversed {test_bounds(first,-40,80);test_bounds(second,-80,-40);}
    else {test_bounds(first,-80,-40);test_bounds(second,-40,80);}
}

fn test_crossing_and_hole() {
    cg_begin();let segments=test_outer(0);
    test_segment(segments,-20,-20,20,-20,5);test_segment(segments,20,-20,20,20,6);
    test_segment(segments,20,20,-20,20,7);test_segment(segments,-20,20,-20,-20,8);
    test_segment(segments,-40,60,-40,-60,9);
    test_segment(segments,-40,0,-25,0,10);
    m_assert(pc_arrangement_needed(segments),"Crossing divider and dangling junction");
    let loops=cg_array();m_assert(pc_arrangement_trace(segments,loops),cg_error);
    m_assert(cg_count(loops)==3,"Two outer faces and the disconnected hole boundary");
    test_bounds(cg_at(loops,0),-80,-40);test_bounds(cg_at(loops,1),-40,80);test_bounds(cg_at(loops,2),-20,20);
    m_assert(cg_count(load64(cg_at(loops,0)))==5 && cg_count(load64(cg_at(loops,1)))==5,
        "Keep shared subdivision vertices after pruning the dangling edges");
}

fn main() {
    test_asymmetric(0);test_asymmetric(1);test_crossing_and_hole();
    return 0;
}
