// Named coordinates for joints with independent degrees of freedom. All
// settings use the parent attachment frame, millimetres and degrees.
import "model.flex";

fn cam_axes(type) {
    if m_eq(type,"cylindrical") {return j_parse("[\"axial_mm\",\"angle_deg\"]");}
    if m_eq(type,"planar") {return j_parse("[\"x_mm\",\"y_mm\",\"angle_deg\"]");}
    if m_eq(type,"ball") {return j_parse("[\"x_deg\",\"y_deg\",\"z_deg\"]");}
    return 0;
}

// Each compiled coordinate carries its name, minimum, maximum and default.
fn cam_coordinates(axes,limits,value) {
    let count=cg_j_count(axes);
    if j_kind(limits)!=4 || cg_j_count(limits)!=count
        || (value && (j_kind(value)!=4 || cg_j_count(value)!=count)) {
        return cg_fail("Joint limits and values must name each of its movement coordinates");
    }
    let result=cg_array();let axis=load64(axes+16);
    while axis && !cg_error {
        let key=j_value(axis);let range=j_get(limits,key);let supplied=j_get(value,key);
        if j_kind(range)!=3 || cg_j_count(range)!=2 || (value && !supplied) {
            return cg_fail(m_cat("Joint coordinate needs a value and ordered limits when specified: ",key));
        }
        let pair=load64(range+16);
        let low=cg_number(pair);let high=cg_number(load64(pair+24));
        let at=0;if supplied {at=cg_number(supplied);}
        if low>high || at<low || at>high {return cg_fail(m_cat("Joint coordinate is outside its ordered travel limits: ",key));}
        let row=m_take(32);store64(row,key);store64(row+8,low);store64(row+16,high);store64(row+24,at);
        cg_push(result,row);axis=load64(axis+24);
    }
    return result;
}
