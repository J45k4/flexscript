// Read named records in a v4 document graph.
import "math.flex";

fn pc_first(array) {
    if j_kind(array)!=3 {return 0;}
    return load64(array+16);
}

fn pc_find(rows,id) {
    let row=pc_first(rows);
    while row {
        if m_eq(j_string(row,"id"),id) {return row;}
        row=load64(row+24);
    }
    return 0;
}
