// The exact same generated patch batches are applied by DOM and Android tests.
import "../../libs/ui.flex";
extend "../../libs/ui/syntax.flex";
global ut_state=0;
global ut_rows=0;
global ut_traces=0;
fn ut_items(){let items=ui_items();if ut_rows==0 {ui_item_add(items,1);ui_item_add(items,2);}if ut_rows==1 {ui_item_add(items,2);ui_item_add(items,1);}if ut_rows==2 {ui_item_add(items,2);}if ut_rows==3 {ui_item_add(items,3);ui_item_add(items,2);}return items;}
fn ut_key(prefix,id){return m_cat(prefix,m_int(id));}
fn ut_description(){if ut_state==2{return 0;}return m_cat("State ",m_int(ut_state));}
fn ut_action(){if ut_state{return "changed";}return "initial";}
fn ut_value(){if ut_state==5{return "controlled";}return "initial";}
view ut_item(id){
    row(ut_key("row-",id),gap:8){
        text(ut_key("label-",id),text:m_int(id));
        input(ut_key("input-",id),text:"Type here",value:"initial",action:"edit",action_id:id);
    }
}
view app_view(){
    column("app",height:-1,padding:18,gap:10){
        text("heading",text:"Portable views");
        text("value",text:m_int(ut_state),size:16+ut_state,description:ut_description());
        button("act",text:"Act",action:ut_action(),action_id:ut_state);
        check("toggle",text:"Toggle",checked:ut_state>0,action:"toggle");
        input("draft",text:"Draft",value:ut_value(),action:"draft");
        text("hidden",text:"Hidden later",hidden:ut_state>1);
        if ut_state {button("branch",text:"Button branch",action:"branch");}
        else {text("branch",text:"Text branch");}
        column("rows"){each id in ut_items(){use ut_item(id);}}
    }
}
fn ut_trace(old,index){let next=app_view();if ut_traces{m_print(1,",");}m_print(1,"{\"version\":1,\"ops\":");m_print(1,ui_compiled_diff(old,next,index,ui_index));m_print(1,"}");ut_traces=ut_traces+1;return next;}
fn main(){
    m_print(1,"[");let current=ut_trace(0,0);let index=ui_index;
    current=ut_trace(current,index);index=ui_index;
    ut_state=1;current=ut_trace(current,index);index=ui_index;
    ut_state=2;ut_rows=1;current=ut_trace(current,index);index=ui_index;
    ut_rows=2;current=ut_trace(current,index);index=ui_index;
    ut_rows=3;current=ut_trace(current,index);index=ui_index;
    ut_rows=4;current=ut_trace(current,index);index=ui_index;
    ut_rows=0;current=ut_trace(current,index);index=ui_index;
    current=ut_trace(0,0);index=ui_index;
    ut_state=5;current=ut_trace(current,index);
    m_print(1,"]\n");m_assert(ui_generic_diff_calls==0,"portable views called generic differ");return 0;
}
