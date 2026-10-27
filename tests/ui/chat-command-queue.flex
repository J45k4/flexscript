import "../../apps/collie/desktop/host/command-queue.flex";
fn cq_add(queue,kind,id){let command=j_object();j_set(command,"kind",j_string(kind));j_set(command,"id",j_int(id));if h_equal(kind,"navigation"){j_set(command,"view_snapshot",j_bool(1));}let next=scm_view_queue(queue,command);j_push(next,command);return next;}
fn main(argc,argv){
    h_environment(argc,argv);let queue=j_array();let i=0;
    while i<300{queue=cq_add(queue,"chat_activate",i);queue=cq_add(queue,"navigation",i);h_assert(j_count(queue)==2,"View intents grew without bound");i=i+1;}
    h_assert(j_n(j_at(queue,0),"id")==299 && j_n(j_at(queue,1),"id")==299,"Latest focus/draft snapshot was lost");
    queue=cq_add(queue,"submit",1);queue=cq_add(queue,"navigation",300);queue=cq_add(queue,"chat_activate",300);queue=cq_add(queue,"navigation",301);queue=cq_add(queue,"chat_activate",301);
    h_assert(j_count(queue)==5 && h_equal(j_s(j_at(queue,2),"kind"),"submit"),"A submit barrier was crossed");
    h_assert(j_n(j_at(queue,0),"id")==299 && j_n(j_at(queue,1),"id")==299 && j_n(j_at(queue,3),"id")==301 && j_n(j_at(queue,4),"id")==301,"View ordering around submit changed");
    queue=cq_add(queue,"cancel",2);queue=cq_add(queue,"navigation",302);queue=cq_add(queue,"workspace_write",3);queue=cq_add(queue,"navigation",303);queue=cq_add(queue,"navigation",304);
    h_assert(j_count(queue)==9 && h_equal(j_s(j_at(queue,5),"kind"),"cancel") && h_equal(j_s(j_at(queue,7),"kind"),"workspace_write"),"Cancel/file barriers were crossed");
    h_assert(j_n(j_at(queue,6),"id")==302 && j_n(j_at(queue,8),"id")==304,"Snapshots on opposite sides of a file operation were merged");
    let partial=j_object();j_set(partial,"kind",j_string("navigation"));j_set(partial,"data",j_parse("{\"draft\":\"keep me\"}"));queue=scm_view_queue(queue,partial);j_push(queue,partial);queue=cq_add(queue,"navigation",305);
    h_assert(j_count(queue)==11 && j_at(queue,9)==partial,"A partial navigation update was overwritten");
    h_print(1,"PASS chat command queue: 600 view intents remain bounded; latest drafts/focus survive; submit/cancel/file barriers preserve order\n");return 0;
}
