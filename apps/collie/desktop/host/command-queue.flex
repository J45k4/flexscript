// Only explicitly marked complete navigation snapshots may supersede earlier
// snapshots. Unmarked/partial updates and ordered operations are barriers.
import "../../../../scripts/lib/json.flex";
fn scm_view_command(command){let kind=j_s(command,"kind");let flag=j_get(command,"view_snapshot");return h_equal(kind,"chat_activate") || (h_equal(kind,"navigation") && flag && j_kind(flag)==5 && j_value(flag));}
fn scm_view_queue(queue,command){
    let kind=j_s(command,"kind");if !scm_view_command(command){return queue;}
    let start=j_count(queue);while start>0 && scm_view_command(j_at(queue,start-1)){start=start-1;}
    let next=j_array();let i=0;while i<j_count(queue){let old=j_at(queue,i);if i<start || !h_equal(j_s(old,"kind"),kind){j_push(next,old);}i=i+1;}return next;
}
