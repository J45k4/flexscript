// Shared arithmetic for native mechanical studies and receipt verification.
import "../math.flex";

fn pms_sample(settings,index,intervals) {
    let start=j_get(settings,"start");let end=j_get(settings,"end");
    let kind=j_kind(start);let end_kind=j_kind(end);
    if (kind==1 || kind==6) && (end_kind==1 || end_kind==6) {
        let a=cg_number(start);let b=cg_number(end);
        if a==b || cg_error {return 0;}
        return cg_json_number(a+(b-a)*index/intervals);
    }
    if kind!=4 || end_kind!=4 {return 0;}
    let count=cg_j_count(start);
    if count<2 || count>3 || cg_j_count(end)!=count {return 0;}
    let out=j_object();let p=load64(start+16);let changes=0;
    while p && !cg_error {
        let name=load64(p+32);let other=j_get(end,name);
        if !other || j_get(out,name) {return 0;}
        let a=cg_number(p);let b=cg_number(other);
        if a!=b {changes=1;}
        j_add(out,name,cg_json_number(a+(b-a)*index/intervals));p=load64(p+24);
    }
    if !changes || cg_error {return 0;}
    return out;
}

fn pms_matches(frames,settings) {
    let count=1;if settings {count=j_integer(settings,"samples");}
    if j_kind(frames)!=3 || cg_j_count(frames)!=count {return 0;}
    let p=load64(frames+16);
    if !settings {return !j_get(p,"position");}
    if count<2 || count>9 {return 0;}
    let previous=cg_error;cg_error=0;let i=0;let valid=1;
    while p && valid {
        let expected=pms_sample(settings,i,count-1);
        let actual=j_get(p,"position");
        if !expected || !actual {valid=0;}
        else if j_kind(expected)==4 {
            valid=j_kind(actual)==4 && cg_j_count(expected)==cg_j_count(actual);
            let axis=load64(expected+16);
            while valid && axis {
                valid=cg_number(axis)==cg_number(j_get(actual,load64(axis+32))) && !cg_error;
                axis=load64(axis+24);
            }
        }else {valid=cg_number(expected)==cg_number(actual) && !cg_error;}
        i=i+1;p=load64(p+24);
    }
    cg_error=previous;
    return valid;
}
