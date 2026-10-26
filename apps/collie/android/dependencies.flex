// Pinned public Android libraries. First-party dependency policy and ZIP/JAR
// handling are native Flexscript; no Gradle or Python build environment needed.
import "../../../scripts/lib/zip.flex";
import "../lib/state.flex";
fn ad_suffix(s,tail){let n=h_len(s);let m=h_len(tail);return n>=m&&h_equal(s+n-m,tail);}
fn ad_compare(a,b){let i=0;while load8(a+i)&&load8(a+i)==load8(b+i){i=i+1;}return load8(a+i)-load8(b+i);}
fn ad_sort(values,entries){let i=1;while i<h_count(values){let value=h_at(values,i);let name=value;if entries{name=load64(value);}let j=i;let more=1;while j>0&&more{let prior=h_at(values,j-1);let key=prior;if entries{key=load64(prior);}if ad_compare(key,name)>0{store64(values+8+j*8,prior);j=j-1;}else{more=0;}}store64(values+8+j*8,value);i=i+1;}return values;}
fn ad_size(path){let stat=h_take(144);h_assert(syscall(4,path,stat,0,0,0,0)==0,h_cat("Cannot stat Android artifact: ",path));return load64(stat+48);}
fn ad_origin(url){return h_starts(url,"https://dl.google.com/dl/android/maven2/")||h_starts(url,"https://repo.maven.apache.org/maven2/");}
fn ad_pin_valid(row){
    let name=cj_text(row,"file");let hash=cj_text(row,"sha256");let url=cj_text(row,"url");let bytes=cj_get(row,"bytes");let type=cj_text(row,"type");
    if !h_len(name)||h_len(hash)!=64||!ad_origin(url)||!ad_suffix(url,h_cat("/",name))||!bytes||j_kind(bytes)!=1||j_value(bytes)<=0||j_value(bytes)>33554432{return 0;}
    let i=0;while load8(name+i){let c=load8(name+i);if !((c>=65&&c<=90)||(c>=97&&c<=122)||(c>=48&&c<=57)||c==95||c==46||c==45){return 0;}i=i+1;}
    i=0;while i<64{let c=load8(hash+i);if !((c>=48&&c<=57)||(c>=97&&c<=102)){return 0;}i=i+1;}
    return (h_equal(type,"aar")&&ad_suffix(name,".aar"))||(h_equal(type,"jar")&&ad_suffix(name,".jar"));
}
fn ad_artifact(row,cache,offline){
    h_assert(ad_pin_valid(row),"Invalid pinned Android artifact");let name=cj_text(row,"file");let hash=cj_text(row,"sha256");let size=cj_int(row,"bytes");let target=h_join(cache,h_cat3(hash,"-",name));
    if !h_exists(target){
        h_assert(!offline,h_cat("Android artifact is absent from offline cache: ",name));let temporary=h_cat(h_join(cache,".collie-download-"),"XXXXXX");let libc=ffi_open("libc.so.6");let fd=ffi_call(ffi_symbol(libc,"mkstemp"),temporary,0,0,0,0,0);h_assert(fd>=0,"Cannot create Android download staging file");h_close(fd);
        let args=h_args("curl","--fail","--silent","--show-error","--location","--proto");h_add(args,"=https");h_add(args,"--proto-redir");h_add(args,"=https");h_add(args,"--max-time");h_add(args,"30");h_add(args,"--max-filesize");h_add(args,h_int(size));h_add(args,"--output");h_add(args,temporary);h_add(args,"--write-out");h_add(args,"%{url_effective}");h_add(args,cj_text(row,"url"));let result=h_run(args);
        let valid=h_status(result)==0&&ad_origin(h_trim(h_out(result)))&&ad_size(temporary)==size&&h_equal(h_sha(temporary),hash);
        if !valid{syscall(87,temporary,0,0,0,0,0);h_print(2,h_err(result));h_die(h_cat("Android artifact download/digest mismatch: ",name));}
        h_assert(syscall(82,temporary,target,0,0,0,0)==0,"Cannot promote verified Android artifact");
    }
    h_assert(ad_size(target)==size&&h_equal(h_sha(target),hash),h_cat("Cached Android artifact digest mismatch: ",name));return target;
}
fn ad_notice_word(name,word){let k=0;while load8(word+k){let c=load8(name+k);if c>=65&&c<=90{c=c+32;}if c!=load8(word+k){return 0;}k=k+1;}let c=load8(name+k);return !c||c==46||c==95||c==45;}
fn ad_notice(name){let i=0;while load8(name+i){if !i||load8(name+i-1)==47{if ad_notice_word(name+i,"license")||ad_notice_word(name+i,"notice")||ad_notice_word(name+i,"copying"){return 1;}}i=i+1;}return 0;}
fn ad_add(entries,entry){let i=0;while i<h_count(entries){let prior=h_at(entries,i);if h_equal(load64(prior),load64(entry)){h_assert(load64(prior+24)==load64(entry+24)&&h_bytes(az_data(prior),az_data(entry),load64(entry+24)),"Conflicting Android SDK archive assets");return 0;}i=i+1;}h_add(entries,entry);return 0;}
fn ad_notices(archive,prefix,licenses){let entries=load64(archive+16);let i=0;while i<h_count(entries){let e=h_at(entries,i);let name=load64(e);if !ad_suffix(name,"/")&&ad_notice(name){ad_add(licenses,az_new(h_cat3("META-INF/collie-dependencies/",prefix,h_cat("/",name)),az_data(e),load64(e+24),1));}i=i+1;}return 0;}
fn ad_prefixes_valid(prefixes){
    if !prefixes||j_kind(prefixes)!=3||j_count(prefixes)<1||j_count(prefixes)>4{return 0;}let i=0;
    while i<j_count(prefixes){let node=j_at(prefixes,i);if j_kind(node)!=2{return 0;}let text=j_value(node);let n=h_len(text);if !n||n>128||load8(text+n-1)!=47{return 0;}let at=0;let start=1;while at<n{let c=load8(text+at);let letter=(c>=65&&c<=90)||(c>=97&&c<=122)||c==95||c==36;if start&&!letter{return 0;}if c==47{if start{return 0;}start=1;}else{if !letter&&!(c>=48&&c<=57){return 0;}start=0;}at=at+1;}i=i+1;}return 1;
}
fn ad_protocol(path,prefixes){
    h_assert(ad_prefixes_valid(prefixes),"Invalid SDK protocol class prefixes");let archive=az_open(path);let entries=load64(archive+16);let selected=h_vec_sized(4096);let i=0;
    while i<h_count(entries){let e=h_at(entries,i);let name=load64(e);let matches=0;let j=0;while j<j_count(prefixes){if h_starts(name,j_value(j_at(prefixes,j))){matches=1;}j=j+1;}
        if ad_suffix(name,".class")&&matches{h_assert(load64(e+24)<=1048576&&h_count(selected)<4096,"Oversized SDK protocol class set");h_add_sized(selected,az_new(name,az_data(e),load64(e+24),1));}i=i+1;}
    h_assert(h_count(selected)>0,"Empty SDK protocol class selection");ad_sort(selected,1);az_write(path,selected);return 0;
}
fn ad_package(data,n){
    h_assert(h_len(data)==n,"NUL in Android SDK manifest");let at=0;let begin=-1;
    while load8(data+at)&&begin<0{if h_starts(data+at,"<!--"){let end=h_find(data+at+4,"-->");h_assert(end>=0,"Unterminated SDK manifest comment");at=at+4+end+3;}else if h_starts(data+at,"<manifest")&&(load8(data+at+9)==32||load8(data+at+9)==10||load8(data+at+9)==13||load8(data+at+9)==9){begin=at+9;}else{at=at+1;}}
    h_assert(begin>=0,"Missing Android SDK manifest root");at=begin;let package=0;let done=0;
    while !done{while load8(data+at)&&load8(data+at)<=32{at=at+1;}let c=load8(data+at);h_assert(c,"Unterminated Android SDK manifest");if c==62||(c==47&&load8(data+at+1)==62){done=1;}else{let start=at;while load8(data+at)&&load8(data+at)>32&&load8(data+at)!=61{at=at+1;}let key=h_slice(data+start,at-start);while load8(data+at)&&load8(data+at)<=32{at=at+1;}h_assert(load8(data+at)==61,"Malformed SDK manifest attribute");at=at+1;while load8(data+at)&&load8(data+at)<=32{at=at+1;}let quote=load8(data+at);h_assert(quote==34||quote==39,"Unquoted SDK manifest attribute");at=at+1;start=at;while load8(data+at)&&load8(data+at)!=quote{at=at+1;}h_assert(load8(data+at)==quote,"Unterminated SDK manifest attribute");if h_equal(key,"package"){h_assert(!package,"Duplicate SDK resource package");package=h_slice(data+start,at-start);}at=at+1;}}
    h_assert(package&&h_len(package)>0,"Missing SDK resource package");let i=0;let first=1;let dots=0;
    while load8(package+i){let c=load8(package+i);let letter=(c>=65&&c<=90)||(c>=97&&c<=122)||c==95;if first{h_assert(letter,"Invalid SDK resource package");first=0;}else if c==46{dots=dots+1;first=1;}else{h_assert(letter||(c>=48&&c<=57),"Invalid SDK resource package");}i=i+1;}h_assert(!first&&dots>0,"Invalid SDK resource package");return package;
}
// Result slots: JARs, resource directories, package names, R8 rules, assets,
// notices. Every returned entry keeps the original pinned SDK bytes.
fn ad_prepare(root,out,cache,offline,lock_path){
    let text=h_read(lock_path);h_assert(h_len(text)==h_file_size,"NUL in Android dependency lock");let lock=c_json(text);let artifacts=cj_get(lock,"artifacts");h_assert(cj_int(lock,"schema")==1&&artifacts&&j_kind(artifacts)==3&&j_count(artifacts)>=1&&j_count(artifacts)<=64,"Unsupported Android dependency lock");let ids=j_object();let i=0;
    while i<j_count(artifacts){let row=j_at(artifacts,i);let id=cj_text(row,"id");h_assert(h_len(id)&&!j_get(ids,id)&&ad_pin_valid(row),"Invalid or duplicate Android dependency");j_set(ids,id,j_bool(1));i=i+1;}
    h_mkdir(cache);cache=h_real(cache);let directory=h_join(out,"dependencies");h_remove(directory);h_mkdir(directory);let result=h_take(48);i=0;while i<6{store64(result+i*8,h_vec());i=i+1;}let jars=load64(result);let resources=load64(result+8);let packages=load64(result+16);let rules=load64(result+24);let assets=load64(result+32);let licenses=load64(result+40);let known=j_object();i=0;
    while i<j_count(artifacts){
        let row=j_at(artifacts,i);let artifact=ad_artifact(row,cache,offline);let dir=h_join(directory,h_int(i));h_mkdir(dir);let archive=az_open(artifact);ad_notices(archive,h_int(i),licenses);
        if h_equal(cj_text(row,"type"),"jar"){h_add(jars,artifact);}else{
            let manifest=az_find(archive,"AndroidManifest.xml");h_assert(manifest,"Missing Android SDK manifest");let package=ad_package(az_data(manifest),load64(manifest+24));if !j_get(known,package){j_set(known,package,j_bool(1));h_add(packages,package);}
            let entries=load64(archive+16);let at=0;while at<h_count(entries){let e=h_at(entries,at);let name=load64(e);
                if !ad_suffix(name,"/"){
                    if h_equal(name,"classes.jar")||(h_starts(name,"libs/")&&ad_suffix(name,".jar"))||h_starts(name,"res/"){
                        let target=h_join(dir,name);h_mkdir(h_dir(target));h_save_bytes(target,az_data(e),load64(e+24),420);
                        if ad_suffix(name,".jar"){h_add(jars,target);ad_notices(az_open(target),h_cat3(h_int(i),"/",name),licenses);let prefixes=cj_get(row,"class_prefixes");if prefixes&&j_kind(prefixes)!=0{ad_protocol(target,prefixes);}}
                    }else if h_equal(name,"proguard.txt")||h_equal(name,"consumer-rules.pro"){let target=h_join(dir,name);h_save_bytes(target,az_data(e),load64(e+24),420);h_add(rules,target);}
                    else if h_starts(name,"assets/"){ad_add(assets,az_new(name,az_data(e),load64(e+24),1));}
                }at=at+1;
            }
            if h_isdir(h_join(dir,"res")){h_add(resources,h_join(dir,"res"));}
        }i=i+1;
    }
    ad_add(assets,az_new("assets/collie-android-dependencies.json",text,h_len(text),1));ad_sort(packages,0);return result;
}
