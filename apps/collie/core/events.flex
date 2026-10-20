// Internal newline-delimited display events, separate from Responses tool items.
import "../lib/json.flex";

global ce_enabled=0;
fn ce_write(fd,event) {h_print(fd,h_cat(j_dump(event),"\n"));return 0;}
fn ce_event(kind) {let e=j_object();j_set(e,"event",j_string(kind));return e;}
fn ce_text(fd,kind,text) {let e=ce_event(kind);j_set(e,"text",j_string(text));return ce_write(fd,e);}
fn ce_note(kind,text) {if ce_enabled {ce_text(1,kind,text);}return 0;}
fn ce_data(kind,data) {if ce_enabled {let e=ce_event(kind);j_set(e,"data",data);ce_write(1,e);}return 0;}
