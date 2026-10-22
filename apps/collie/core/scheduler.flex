// Worker scheduling policy, independent of Android threads/executors.
import "session.flex";
fn cs_plan(request){
    ch_config=j_need(request,"config");cw_config=ch_config;if !ag_open(){return c_error(cw_problem);}let active=j_need(request,"active");let capacity=3-j_count(active);let start=j_array();let cancel=j_array();let allowed=cj_int(request,"allowed") && cj_int(request,"authenticated");
    let table=ag_table("collie_workers");let rows=load64(table+24);let i=0;
    while i<fd_size(rows){let row=fd_table_row(table,i);let id=flexdb_rowid(row);let status=ag_text(row,2);let running=0;let k=0;while k<j_count(active){if j_value(j_at(active,k))==id{running=1;}k=k+1;}
        if cj_int(request,"recover") && (h_equal(status,"running") || h_equal(status,"waiting")){ag_host(ch_host_action("pause",id));status="paused";}
        if running && (h_equal(status,"cancelled") || !cj_int(request,"allowed")) {if !h_equal(status,"cancelled"){ag_host(ch_host_action("pause",id));}j_push(cancel,j_int(id));}
        if h_equal(status,"queued") && !running && allowed && capacity>0{
            let claimed=ag_host(ch_host_action("claim",id));if cj_int(claimed,"changed"){let entry=j_object();j_set(entry,"id",j_int(id));j_set(entry,"revision",j_int(ag_number(row,5)));j_push(start,entry);capacity=capacity-1;}
        }i=i+1;
    }
    let out=j_object();j_set(out,"start",start);j_set(out,"cancel",cancel);let list=ag_host(ch_host_action("list",0));j_set(out,"workers",j_need(list,"workers"));return out;
}
fn cs_messages(request){ch_config=j_need(request,"config");cw_config=ch_config;if !ag_open(){return c_error(cw_problem);}let id=cj_int(request,"id");let t=ag_table("collie_messages");let rows=load64(t+24);let out=j_array();let i=0;while i<fd_size(rows){let row=fd_table_row(t,i);if row && load64(row+8) && ag_number(row,0)==id{j_push(out,ag_json_value(cw_row(row)));}i=i+1;}let result=j_object();j_set(result,"messages",out);return result;}
fn cs_host(request){let action=cj_text(request,"action");if h_equal(action,"plan"){return cs_plan(request);}if h_equal(action,"messages"){return cs_messages(request);}return ag_host(request);}
