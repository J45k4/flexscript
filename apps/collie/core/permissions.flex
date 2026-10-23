// Shared grant schema, conservative stored-policy normalization and UI metadata.
import "../lib/state.flex";
fn cp_permission(keys,key,title,detail){let row=j_object();j_set(row,"key",j_string(key));j_set(row,"title",j_string(title));j_set(row,"detail",j_string(detail));j_push(keys,row);return 0;}
fn cp_permissions(saved){
    let rows=j_array();
    cp_permission(rows,"internet","Internet access","Fetch web pages and APIs over HTTPS. Your ChatGPT connection stays available when this is off.");
    cp_permission(rows,"files_read","Read workspace files","Read files, list folders, and view text or images in this conversation's private workspace.");
    cp_permission(rows,"files_write","Write workspace files","Create folders and create or replace workspace files.");
    cp_permission(rows,"db_read","Read database","Read tables, columns and saved rows in this conversation's FlexDB.");
    cp_permission(rows,"db_write","Write database","Create tables, change schemas, and add, update or delete saved rows.");
    cp_permission(rows,"history","Read past messages","Search and read saved conversations, previous programs and results. Conversations with this permission off are excluded from recall.");
    cp_permission(rows,"workers","Manage workers","Start helper agents and ask the model for feedback inside a running program. Workers share this workspace and inherit its permissions.");
    let policy=j_object();let i=0;while i<j_count(rows){let key=j_s(j_at(rows,i),"key");let value=cj_get(saved,key);let allowed=!saved || j_kind(saved)==0;if value{allowed=j_kind(value)==5 && j_value(value);}j_set(policy,key,j_bool(allowed));i=i+1;}
    let out=j_object();j_set(out,"policy",policy);j_set(out,"entries",rows);return out;
}
