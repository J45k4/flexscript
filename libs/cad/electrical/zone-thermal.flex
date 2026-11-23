// Thermal relief removes copper except for grid-aligned, full-width spoke
// corridors. All previous clearance losses remain clipped.
import "geometry.flex";

fn pct_floor_cell(um) {
    if um<0 {return (um-499)/500;}
    return um/500;
}
fn pct_ceil_cell(um) {return -pct_floor_cell(-um);}

fn pct_targets(board,zone) {
    let targets=cg_array();let gap=j_integer(zone,"thermal_gap");let width=j_integer(zone,"thermal_width");
    if !gap {return targets;}
    let shape=load64(j_get(board,"copper")+16);let index=0;
    let layer=j_integer(zone,"layers");let net=j_string(zone,"net");
    while shape && !cg_error {
        if (j_integer(shape,"layers")&layer) && m_eq(j_string(shape,"net"),net)
            && m_eq(j_string(shape,"kind"),"pad") {
            let ax=j_integer(shape,"ax");let ay=j_integer(shape,"ay");
            let bx=j_integer(shape,"bx");let by=j_integer(shape,"by");
            let margin=j_integer(shape,"radius")+gap;
            let target=m_take(80);
            store64(target,shape);store64(target+8,index);
            store64(target+16,pct_floor_cell(pc_min(ax,bx)-margin));
            store64(target+24,pct_ceil_cell(pc_max(ax,bx)+margin));
            store64(target+32,pct_floor_cell(pc_min(ay,by)-margin));
            store64(target+40,pct_ceil_cell(pc_max(ay,by)+margin));
            let x=pct_floor_cell((ax+bx)/2-width/2+250);let y=pct_floor_cell((ay+by)/2-width/2+250);
            store64(target+48,x);store64(target+56,x+width/500);
            store64(target+64,y);store64(target+72,y+width/500);
            cg_push(targets,target);
        }
        shape=load64(shape+24);index=index+1;
    }
    return targets;
}

fn pct_covers(zone,left,bottom,right,top) {
    let runs=j_integer(zone,"runs");let offsets=j_integer(zone,"row_offsets");
    let w=j_integer(zone,"grid_width");let h=j_integer(zone,"grid_height");
    if left<0 || right>w || bottom<0 || top>h || left>=right || bottom>=top {return 0;}
    let y=bottom;
    while y<top && !cg_error {
        cg_step();
        let i=load64(offsets+y*8);let end=load64(offsets+(y+1)*8);let covered=0;
        while i<end && !covered {
            let run=cg_at(runs,i);
            if load64(run+8)>left {i=end;}
            else {
                if load64(run+16)>=right {covered=1;}
                i=i+1;
            }
        }
        if !covered {return 0;}
        y=y+1;
    }
    return !cg_error;
}

// Follow a full-width corridor inward from the first mainland cell.
// A ray counts only when the continuous copper actually meets the pad.
fn pct_ray(zone,target,vertical,outside,inside,step) {
    let at=outside;let pad=load64(target);
    while (at-inside)*step<=0 && !cg_error {
        let left=at;let right=at+1;let bottom=load64(target+64);let top=load64(target+72);
        if vertical {
            left=load64(target+48);right=load64(target+56);bottom=at;top=at+1;
        }
        if !pct_covers(zone,left,bottom,right,top) {return 0;}
        if pc_shape_touches_rect(pad,left*500,bottom*500,right*500,top*500) {return 1;}
        at=at+step;
    }
    return 0;
}

fn pct_spokes(zone,target) {
    return pct_ray(zone,target,0,load64(target+16)-1,load64(target+48),1)
        +pct_ray(zone,target,0,load64(target+24),load64(target+56)-1,-1)
        +pct_ray(zone,target,1,load64(target+32)-1,load64(target+64),1)
        +pct_ray(zone,target,1,load64(target+40),load64(target+72)-1,-1);
}

fn pct_bypass(board,zone,target) {
    let layer=j_integer(zone,"layers");let net=j_string(zone,"net");
    let other=load64(j_get(board,"zones")+16);
    while other && !cg_error {
        if other!=zone && j_integer(other,"layers")==layer && m_eq(j_string(other,"net"),net)
            && (j_integer(other,"thermal_gap")<j_integer(zone,"thermal_gap")
                || j_integer(other,"thermal_width")>j_integer(zone,"thermal_width")) {
            let runs=j_integer(other,"runs");let offsets=j_integer(other,"row_offsets");
            let y=pc_max(0,load64(target+32));let top=pc_min(j_integer(zone,"grid_height"),load64(target+40));
            while y<top && !cg_error {
                if y<load64(target+64) || y>=load64(target+72) {
                    let i=load64(offsets+y*8);let end=load64(offsets+(y+1)*8);
                    while i<end && !cg_error {
                        cg_step();
                        let run=cg_at(runs,i);let left=load64(run+8);let right=load64(run+16);
                        if (left<load64(target+48) && right>load64(target+16))
                            || (left<load64(target+24) && right>load64(target+56)) {return 1;}
                        i=i+1;
                    }
                }
                y=y+1;
            }
        }
        other=load64(other+24);
    }
    return 0;
}

fn pct_report(board) {
    let zone=load64(j_get(board,"zones")+16);
    while zone && !cg_error {
        let targets=j_integer(zone,"thermal_targets");
        if cg_count(targets) {
            let report=j_array();let i=0;let mask=0;let islands=j_integer(zone,"islands");
            while i<cg_count(islands) {mask=mask|load64(cg_at(islands,i)+8);i=i+1;}
            i=0;
            while i<cg_count(targets) && !cg_error {
                let item=cg_at(targets,i);let pad=load64(item);
                let x=(j_integer(pad,"ax")+j_integer(pad,"bx"))*500;
                let y=(j_integer(pad,"ay")+j_integer(pad,"by"))*500;
                if (mask&(1<<load64(item+8))) || cb_contains(j_integer(zone,"ring"),cg_v(x,y,0)) {
                    let row=j_object();cg_j_text(row,"pad",j_string(pad,"id"));
                    cg_j_int(row,"pad_index",load64(item+8));
                    cg_j_int(row,"spokes",pct_spokes(zone,item));
                    cg_j_int(row,"bypass",pct_bypass(board,zone,item));
                    j_add(report,0,row);
                }
                i=i+1;
            }
            if cg_j_count(report) {j_add(zone,"thermals",report);}
        }
        zone=load64(zone+24);
    }
    return !cg_error;
}
