import "permissions.flex";
// Cross-conversation recall. Platform hooks expose only sibling session archives;
// search, paging, permissions and field selection stay in shared Flexscript.
import "../adapters/workspace.flex";
import "../lib/state.flex";
global cm_size=0;
fn cm_id(text){let n=h_len(text);if n<1 || n>80{return 0;}let i=0;while i<n{let c=load8(text+i);if !((c>=65 && c<=90) || (c>=97 && c<=122) || (c>=48 && c<=57) || c==45){return 0;}i=i+1;}return 1;}
fn cm_allowed(saved){let p=cj_get(saved,"permissions");if !p || j_kind(p)==0{return 1;}return h_equal(cp_mode(p,"history"),"allow");}
fn cm_load(id){let text=cm_storage_read(id);if !text{return 0;}let saved=c_json(text);if j_kind(saved)!=4 || !cm_allowed(saved){return 0;}let a=cj_get(saved,"archive");if !a || j_kind(a)!=3{return 0;}return a;}
fn cm_excerpt(text,at,limit){let n=h_len(text);let start=at-160;if start<0{start=0;}while start>0 && (load8(text+start)&192)==128{start=start-1;}let end=start+limit;if end>n{end=n;}while end>start && (load8(text+end)&192)==128{end=end-1;}return h_slice(text+start,end-start);}
fn cm_lower(text){let n=h_len(text);let out=h_take(n+1);let i=0;while i<n{let c=load8(text+i);if c>=65 && c<=90{c=c+32;}store8(out+i,c);i=i+1;}return out;}
fn cm_page(matches,id,after){let page=db_list();db_add(page,matches);db_add(page,db_text(id));db_add(page,db_int(after));return page;}
fn cm_search(request){
    let q=db_at(request,1);let cursor=db_at(request,2);let after=db_at(request,3);let limit=db_at(request,4);
    if db_count(request)!=5 || db_kind(q)!=2 || db_bytes(q)<1 || db_bytes(q)>256 || db_kind(cursor)!=2 || (db_bytes(cursor) && !cm_id(db_word(cursor))) || db_kind(after)!=1 || db_word(after)<0 || db_word(after)>1000000000 || (!db_bytes(cursor) && db_word(after)) || db_kind(limit)!=1 || db_word(limit)<1 || db_word(limit)>20{return cw_fail("memory_search requires a query (1..256 bytes), session cursor (empty initially), message cursor (0 initially), and limit (1..20).");}
    let matches=db_list();let query=cm_lower(db_word(q));let id=db_word(cursor);let at=db_word(after);if !h_len(id){id=cm_storage_next("");if !id{return 0;}}let sessions=0;let entries=0;let bytes=0;
    while id && h_len(id){
        let archive=cm_load(id);bytes=bytes+cm_size;sessions=sessions+1;
        if archive{
            while at<j_count(archive){
                let item=j_at(archive,at);let keys=h_args("content","source","observation",0,0,0);let k=0;let hit=0;
                while k<3 && !hit{let field=h_at(keys,k);let text=cw_history_field(item,field);let pos=h_find(cm_lower(text),query);if pos>=0{let row=db_list();db_add(row,db_text(id));db_add(row,db_int(at+1));db_add(row,db_text(cj_text(item,"role")));db_add(row,db_text(field));db_add(row,db_text(cm_excerpt(text,pos,512)));db_add(matches,row);hit=1;}k=k+1;}
                at=at+1;entries=entries+1;
                if db_count(matches)>=db_word(limit) || entries>=1024{return cm_page(matches,id,at);}
            }
        }
        id=cm_storage_next(id);at=0;if !id{return 0;}
        if sessions>=8 || bytes>=8388608{return cm_page(matches,id,0);}
    }
    return cm_page(matches,"",0);
}
fn cm_rpc(request){
    let op=db_word(db_at(request,0));if h_equal(op,"memory_search"){return cm_search(request);}
    if !(h_equal(op,"memory_history") || h_equal(op,"memory_read")){return cw_fail("Unknown memory operation.");}
    let id=db_at(request,1);if db_kind(id)!=2 || !cm_id(db_word(id)){return cw_fail("Invalid conversation ID.");}
    let expected=4;if h_equal(op,"memory_read"){expected=6;}if db_count(request)!=expected{return cw_fail("Incorrect memory argument count.");}
    let archive=cm_load(db_word(id));if !archive{return cw_fail("Conversation archive is unavailable or history access is disabled.");}
    let local=db_request("history");let i=2;while i<db_count(request){db_add(local,db_at(request,i));i=i+1;}
    let previous=cw_history;cw_history=archive;let mode="history";if h_equal(op,"memory_read"){mode="history_read";}let result=cw_history_request(local,mode);cw_history=previous;return result;
}
