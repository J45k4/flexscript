// Generate Wayland wl_interface/wl_message metadata directly in Flexscript.
// Input is trusted installed protocol XML; no C/Python scanner or runtime shim.
import "lib/build.flex";
import "../lib/bytes.flex";
global wp_xml=0;global wp_at=0;global wp_tag=0;global wp_notices=0;
fn wp_next(){
    while load8(wp_xml+wp_at){
        while load8(wp_xml+wp_at) && load8(wp_xml+wp_at)!=60{wp_at=wp_at+1;}if !load8(wp_xml+wp_at){return 0;}
        if h_starts(wp_xml+wp_at,"<!--"){let end=h_find(wp_xml+wp_at+4,"-->");h_assert(end>=0,"Unclosed XML comment");wp_at=wp_at+4+end+3;}
        else{let start=wp_at+1;let quote=0;wp_at=start;while load8(wp_xml+wp_at) && (load8(wp_xml+wp_at)!=62 || quote){let c=load8(wp_xml+wp_at);if c==34{quote=!quote;}wp_at=wp_at+1;}h_assert(load8(wp_xml+wp_at)==62,"Unclosed XML tag");wp_tag=h_slice(wp_xml+start,wp_at-start);wp_at=wp_at+1;if load8(wp_tag)!=33 && load8(wp_tag)!=63{return 1;}}
    }return 0;
}
fn wp_attr(name){
    let needle=h_cat(name,"=\"");let at=0;let n=h_len(needle);while load8(wp_tag+at){
        if (at==0 || load8(wp_tag+at-1)==32 || load8(wp_tag+at-1)==10 || load8(wp_tag+at-1)==9) && h_starts(wp_tag+at,needle){let start=at+n;let end=start;while load8(wp_tag+end) && load8(wp_tag+end)!=34{end=end+1;}h_assert(load8(wp_tag+end)==34,"Invalid XML attribute");return h_slice(wp_tag+start,end-start);}at=at+1;
    }return "";
}
fn wp_name(name){return h_starts(wp_tag,name) && (load8(wp_tag+h_len(name))==32 || load8(wp_tag+h_len(name))==10 || load8(wp_tag+h_len(name))==9 || !load8(wp_tag+h_len(name)));}
fn wp_read(path,interfaces){
    wp_xml=h_read(path);wp_at=0;let current=0;let message=0;
    while wp_next(){
        if wp_name("protocol"){wp_line(wp_notices,h_cat("// Protocol: ",wp_attr("name")));}
        else if wp_name("copyright"){let n=h_find(wp_xml+wp_at,"</copyright>");h_assert(n>=0,"Unclosed protocol license");let text=h_slice(wp_xml+wp_at,n);let start=0;let end=0;while end<=n{if end==n || load8(text+end)==10{wp_line(wp_notices,h_cat("// ",h_slice(text+start,end-start)));start=end+1;}end=end+1;}}
        else if wp_name("interface"){current=j_object();j_set(current,"name",j_string(wp_attr("name")));j_set(current,"version",j_int(h_number(wp_attr("version"))));j_set(current,"requests",j_array());j_set(current,"events",j_array());j_push(interfaces,current);}
        else if wp_name("/interface"){current=0;}
        else if current && (wp_name("request") || wp_name("event")){message=j_object();j_set(message,"name",j_string(wp_attr("name")));let since=wp_attr("since");if !h_len(since){since="1";}j_set(message,"since",j_int(h_number(since)));j_set(message,"args",j_array());let key="requests";if wp_name("event"){key="events";}j_push(j_get(current,key),message);}
        else if wp_name("/request") || wp_name("/event"){message=0;}
        else if current && message && wp_name("arg"){let arg=j_object();j_set(arg,"type",j_string(wp_attr("type")));j_set(arg,"interface",j_string(wp_attr("interface")));j_set(arg,"nullable",j_bool(h_equal(wp_attr("allow-null"),"true")));j_push(j_get(message,"args"),arg);}
    }return 0;
}
fn wp_s(o,key){return j_value(j_get(o,key));}
fn wp_int(o,key){return j_value(j_get(o,key));}
fn wp_line(out,text){h_text(out,text);h_text(out,"\n");return 0;}
fn wp_store(out,offset,value,word){let operation="store64";if !word{operation="bytes_store32";}return wp_line(out,h_cat3("    ",operation,h_cat3("(p+",h_int(offset),h_cat3(",",value,");"))));}
fn wp_signature(message){
    let s=h_buffer();let since=wp_int(message,"since");if since>1{h_text(s,h_int(since));}let args=j_get(message,"args");let i=0;
    while i<j_count(args){let a=j_at(args,i);if wp_int(a,"nullable"){h_text(s,"?");}let t=wp_s(a,"type");let code=0;
        if h_equal(t,"int"){code="i";}else if h_equal(t,"uint"){code="u";}else if h_equal(t,"fixed"){code="f";}else if h_equal(t,"string"){code="s";}else if h_equal(t,"object"){code="o";}else if h_equal(t,"new_id"){code="n";}else if h_equal(t,"array"){code="a";}else if h_equal(t,"fd"){code="h";}h_assert(code,"Unknown Wayland argument type");h_text(s,code);i=i+1;
    }return h_data(s);
}
fn main(argc,argv){
    h_environment(argc,argv);let files=h_vec();let target=0;let i=1;while i<argc{let arg=load64(argv+i*8);h_assert(i+1<argc,"Option needs a value");let value=load64(argv+(i+1)*8);if h_equal(arg,"--protocol"){h_add(files,value);}else if h_equal(arg,"--out"){target=value;}else{h_die("Usage: wayland-protocols --protocol file.xml [--protocol file.xml] --out file.flex");}i=i+2;}
    h_assert(target && h_count(files)>0,"Provide protocol XML files and output");let interfaces=j_array();wp_notices=h_buffer();i=0;while i<h_count(files){wp_read(h_at(files,i),interfaces);i=i+1;}h_assert(j_count(interfaces)>0,"No protocol interfaces");
    let offsets=j_object();let bytes=j_count(interfaces)*40;i=0;while i<j_count(interfaces){let face=j_at(interfaces,i);let name=wp_s(face,"name");h_assert(!j_get(offsets,name),"Duplicate protocol interface");j_set(offsets,name,j_int(i*40));i=i+1;}
    let out=h_buffer();wp_line(out,"// Generated by scripts/wayland-protocols.flex. Do not hand-edit metadata.");h_text(out,h_data(wp_notices));wp_line(out,"import \"../../../../lib/bytes.flex\";");wp_line(out,"global wp_protocol_memory=0;");i=0;while i<j_count(interfaces){wp_line(out,h_cat3("global wp_i_",wp_s(j_at(interfaces,i),"name"),"=0;"));i=i+1;}
    let body=h_buffer();i=0;while i<j_count(interfaces){let face=j_at(interfaces,i);let at=i*40;wp_line(body,h_cat3("    wp_i_",wp_s(face,"name"),h_cat3("=p+",h_int(at),";")));wp_store(body,at,j_dump(j_string(wp_s(face,"name"))),1);wp_store(body,at+8,h_int(wp_int(face,"version")),0);let group=0;
        while group<2{let key="requests";let count_at=at+12;let ptr_at=at+16;if group{key="events";count_at=at+24;ptr_at=at+32;}let messages=j_get(face,key);let count=j_count(messages);wp_store(body,count_at,h_int(count),0);wp_store(body,ptr_at,h_cat("p+",h_int(bytes)),1);let msg=bytes;bytes=bytes+count*24;let m=0;
            while m<count{let message=j_at(messages,m);let loc=msg+m*24;let args=j_get(message,"args");wp_store(body,loc,j_dump(j_string(wp_s(message,"name"))),1);wp_store(body,loc+8,j_dump(j_string(wp_signature(message))),1);wp_store(body,loc+16,h_cat("p+",h_int(bytes)),1);let a=0;
                while a<j_count(args){let iface=wp_s(j_at(args,a),"interface");let value="0";if h_len(iface){let local=j_get(offsets,iface);if local{value=h_cat("p+",h_int(j_value(local)));}else{value=h_cat3("ffi_symbol(lib,",j_dump(j_string(h_cat(iface,"_interface"))),")");}}wp_store(body,bytes,value,1);bytes=bytes+8;a=a+1;}m=m+1;
            }group=group+1;
        }i=i+1;
    }
    wp_line(out,"fn wp_protocol_init(lib){if wp_protocol_memory{return wp_protocol_memory;}");wp_line(out,h_cat3("    let p=alloc(",h_int(bytes),");if p<0{return 0;}wp_protocol_memory=p;"));h_text(out,h_data(body));wp_line(out,"    return p;}");wp_line(out,"fn wp_protocol_close(){if !wp_protocol_memory{return 0;}");wp_line(out,h_cat3("    syscall(11,wp_protocol_memory,",h_int(bytes),",0,0,0,0);wp_protocol_memory=0;"));i=0;while i<j_count(interfaces){wp_line(out,h_cat3("    wp_i_",wp_s(j_at(interfaces,i),"name"),"=0;"));i=i+1;}wp_line(out,"    return 0;}");h_save(target,h_data(out));h_print(1,h_cat3("Generated ",h_int(j_count(interfaces))," Wayland interfaces\n"));return 0;
}
