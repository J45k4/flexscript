// Standalone Linux host for the exact Android screen and action reducer.
import "../../apps/collie/ui/permissions.flex";
extend "../../libs/ui/syntax.flex";
view app_view(){use permission_screen();}
fn main(){let text=h_take(65537);let n=0;let more=1;while more && n<65536{let k=syscall(0,0,text+n,65536-n,0,0,0);if k>0{n=n+k;}else if k!=-4{more=0;}}store8(text+n,0);h_print(1,j_dump(cu_permissions(c_json(text))));return 0;}
