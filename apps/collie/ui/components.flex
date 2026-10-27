import "markdown.flex";
view cu_header(key,title,back){
    row(cu_key(key,"-header"),padding_x:16,padding_y:12,gap:12){
        button(cu_key(key,"-back"),text:"‹",description:back,action:"back",size:28,align:"center",width:46,height:46,color:"#c5e3ae");
        text(cu_key(key,"-title"),text:title,size:23,font:"medium",color:"#edf2ed",weight:1);
    }
}
view cu_action(key,title,action,id){
    button(key,text:title,description:title,action:action,action_id:id,padding:14,min_height:48,size:15,color:"#edf2ed",background:"#232c33",radius:12);
}
view cu_fold(key,title,body,code){
    column(cu_key(key,"-fold"),background:"#191f25",radius:16,border_width:1,border_color:"#2c353b",padding:12,gap:8){
        button(cu_key(key,"-toggle"),text:cu_fold_label(title,cu_expanded(cu_key(key,"-toggle"))),description:cu_fold_label(title,cu_expanded(cu_key(key,"-toggle"))),action:"fold",size:14,color:"#c5e3ae",min_height:44);
        if cu_expanded(cu_key(key,"-toggle")){
            row(cu_key(key,"-tools")){
                text(cu_key(key,"-lines"),text:cu_line_label(body),size:11,color:"#8e9d9f",weight:1);
                button(cu_key(key,"-copy"),text:"Copy",description:cu_copy_label(code),action:"copy",action_id:cu_copy_text(body),color:"#c5e3ae",min_height:40);
            }
            if code{
                hscroll(cu_key(key,"-scroll")){
                    row(cu_key(key,"-code-row"),padding:10,gap:12,background:"#0d1217"){
                        text(cu_key(key,"-numbers"),text:cu_line_numbers(body),font:"monospace",size:12,color:"#8e9d9f",align:"end",line_height:4);
                        text(cu_key(key,"-body"),text:body,runs:cu_code_runs(body),font:"monospace",selectable:1,size:12,color:"#d8e2e7",line_height:4);
                    }
                }
            }else{
                text(cu_key(key,"-body"),text:body,font:"monospace",selectable:1,size:13,color:"#dce9d7",line_height:4);
            }
        }
    }
}
view cu_file_tile(key,file,remove,index){
    let path=cj_text(file,"path");
    row(key,padding:10,gap:8,radius:12,background:"#232c33",action:"preview",action_id:cu_preview(file),description:cu_key("Open attached image: ",path),width:240,min_height:72){
        if h_len(cj_text(file,"image_id")){
            image(cu_key(key,"-thumb"),source:cu_key("preview:",cj_text(file,"image_id")),description:cu_key("Image preview: ",path),width:48,height:48);
        }
        column(cu_key(key,"-labels"),weight:1,gap:5){
            text(cu_key(key,"-name"),text:path,max_lines:1,size:13,color:"#edf2ed");
            text(cu_key(key,"-bytes"),text:cu_size(cj_int(file,"file_bytes")),size:11,color:"#8e9d9f");
        }
        if remove{
            button(cu_key(key,"-remove"),text:"×",description:cu_key("Remove attachment: ",path),action:"remove_attachment",action_id:index+1,align:"center",width:44,height:48,color:"#8e9d9f",size:24);
        }
    }
}
view cu_view_tile(key,file){
    let path=cj_text(file,"path");let type=cj_text(file,"type");let image=h_equal(type,"image");let prefix=cu_view_label(file,0);let title=cu_view_label(file,1);let button=cu_view_label(file,2);
    column(key,padding:12,gap:10,background:"#232c33",radius:10,action:"preview",action_id:cu_preview(file),description:cu_key(prefix,path)){
        text(cu_key(key,"-title"),text:cu_key(title,path),size:14,color:"#c5e3ae",font:"medium");
        if image{
            image(cu_key(key,"-image"),source:cu_key("preview:",cj_text(file,"image_id")),description:cu_key("Image preview: ",path),height:180);
        }else{
            text(cu_key(key,"-excerpt"),text:cj_text(file,"text"),font:"monospace",max_lines:3,size:12,color:"#edf2ed");
        }
        text(cu_key(key,"-open"),text:button,size:12,color:"#c5e3ae");
    }
}
view cu_result(key,card){
    let o=cu_observation(card);let title=cu_result_state(o);let output=cj_text(o,"stdout");let error=cj_text(o,"stderr");
    column(key,padding:12,gap:8,background:"#191f25",radius:16,border_width:1,border_color:"#2c353b"){
        row(cu_key(key,"-header")){
            text(cu_key(key,"-name"),text:"VM result",weight:1,size:14,color:"#edf2ed");
            text(cu_key(key,"-state"),text:title,size:12,color:"#c5e3ae");
        }
        if cu_expanded(cu_key(key,"-toggle")){
            button(cu_key(key,"-toggle"),text:"Hide result",description:"Hide VM result",action:"fold",size:12,color:"#c5e3ae",min_height:44);
            if h_len(output){text(cu_key(key,"-stdout"),text:output,font:"monospace",selectable:1,size:13,color:"#dce9d7",line_height:4);}
            if h_len(error){text(cu_key(key,"-stderr"),text:error,font:"monospace",selectable:1,size:13,color:"#f1aaa6",line_height:4);}
            if !h_len(output) && !h_len(error){text(cu_key(key,"-empty"),text:"Finished without output",size:12,color:"#8e9d9f");}
            if cj_int(o,"output_truncated"){text(cu_key(key,"-truncated"),text:"Output truncated",size:12,color:"#f1aaa6");}
            each index in cu_indices(cu_array(o,"views"),0,4){use cu_view_tile(cu_key(key,cu_k("-view-",index)),j_at(cu_array(o,"views"),index));}
        }else{
            button(cu_key(key,"-toggle"),text:"Show result",description:"Show VM result",action:"fold",size:12,color:"#c5e3ae",min_height:44);
        }
    }
}
view cu_card(key,card){
    let kind=cj_text(card,"kind");let body=cj_text(card,"text");
    column(key,gap:8){
        if h_equal(kind,"image"){use cu_view_tile(cu_key(key,"-generated"),cu_observation(card));}
        if h_equal(kind,"source"){
            use cu_fold(cu_key(key,"-source"),"Show program",body,1);
        }else{
            if h_equal(kind,"result"){
                use cu_result(cu_key(key,"-result"),card);
            }else{
                if h_equal(kind,"user"){
                    column(cu_key(key,"-user"),padding:16,gap:10,background:"#25332b",radius:20){
                        if h_len(body){text(cu_key(key,"-body"),text:body,selectable:1,size:16,color:"#edf2ed",line_height:5);}
                        each index in cu_indices(cu_array(card,"attachments"),0,4){use cu_file_tile(cu_key(key,cu_k("-file-",index)),j_at(cu_array(card,"attachments"),index),0,index);}
                    }
                }else{
                    if h_equal(kind,"assistant"){
                        row(cu_key(key,"-assistant-header")){
                            text(cu_key(key,"-author"),text:"Collie",size:13,color:"#c5e3ae",font:"medium",weight:1);
                            button(cu_key(key,"-copy"),text:"Copy",description:"Copy reply",action:"copy",action_id:cu_copy_text(body),color:"#c5e3ae",size:12,min_height:36);
                        }
                        use cm_text(cu_key(key,"-body"),body,16,"#edf2ed");
                    }else{
                        if h_equal(kind,"error"){
                            column(cu_key(key,"-error"),padding:16,gap:8,background:"#2b2023",radius:16){
                                text(cu_key(key,"-title"),text:"Something needs attention",size:13,color:"#f1aaa6",font:"medium");
                                text(cu_key(key,"-body"),text:body,size:14,color:"#e9c5c2",selectable:1);
                            }
                        }else{
                            if !h_equal(kind,"image") && !h_starts(body,"App-private workspace ready."){text(cu_key(key,"-info"),text:body,size:12,color:"#8e9d9f",align:"center");}
                        }
                    }
                }
            }
        }
    }
}
