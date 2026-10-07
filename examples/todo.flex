// A native todo app. UI, font, model, persistence and X11 client are Flexscript.
global tasks = 0;
global task_count = 0;
global visible = 0;
global visible_count = 0;
global view = 0;
global scroll = 0;
global selected = -1;
global editing = -1;
global entry = 0;
global entry_size = 0;
global caret = 0;
global select_all = 0;
global entry_focus = 1;
global data_path = 0;
global temp_path = 0;
global lock_path = 0;
global lock_fd = -1;
global disk = 0;
global disk_size = 0;
global saved = 1;
global notice = 0;
global glyphs = 0;
global number_buf = 0;
global x_fd = -1;
global packet = 0;
global reply = 0;
global rectangles = 0;
global rectangle_count = 0;
global foreground = -1;
global root = 0;
global resource_base = 0;
global window = 0;
global gc = 0;
global pixmap = 0;
global root_depth = 0;
global width = 960;
global height = 700;
global pixmap_width = 0;
global pixmap_height = 0;
global wm_protocols = 0;
global wm_delete = 0;
global keyboard = 0;
global key_first = 0;
global key_last = 0;
global key_columns = 0;
global event = 0;
global pointer_x = -1;
global pointer_y = -1;
global hovered = 0;
global dirty = 1;
global running = 1;
global io_error = 0;
global environment = 0;
global display_name = 0;
global display_number = 0;
global authority = 0;
global cookie = 0;
global cookie_size = 0;
global socket_address = 0;
global signal_mask = 0;
global old_mask = 0;
global signal_fd = -1;
global polls = 0;
global tests = 0;
global failures = 0;

fn length(s) { let n = 0; while load8(s + n) { n = n + 1; } return n; }
fn copy(to, from, n) { let i = 0; while i < n { store8(to+i, load8(from+i)); i=i+1; } return 0; }
fn zero(p, n) { let i=0; while i<n { store8(p+i, 0); i=i+1; } return 0; }
fn same(a, b, n) { let i=0; while i<n { if load8(a+i)!=load8(b+i) { return 0; } i=i+1; } return 1; }
fn equal(a,b) { let n=length(a); return n==length(b) && same(a,b,n); }
fn u16(p) { return load8(p) | (load8(p+1)<<8); }
fn u32(p) { return u16(p) | (u16(p+2)<<16); }
fn be16(p) { return (load8(p)<<8) | load8(p+1); }
fn put16(p,n) { store8(p,n); store8(p+1,n>>8); return 0; }
fn put32(p,n) { put16(p,n); put16(p+2,n>>16); return 0; }
fn padded(n) { return ((n+3)/4)*4; }
fn minimum(a,b) { if a<b { return a; } return b; }
fn error(s) { syscall(1,2,s,length(s),0,0,0); syscall(1,2,"\n",1,0,0,0); return 0; }
fn env(name) {
    let n=length(name); let i=0;
    while load64(environment+i*8) {
        let value=load64(environment+i*8);
        if length(value)>n && same(value,name,n) && load8(value+n)==61 { return value+n+1; }
        i=i+1;
    }
    return 0;
}
fn decimal(n) {
    let i=47; store8(number_buf+i,0);
    while n>=10 { i=i-1; store8(number_buf+i,48+n%10); n=n/10; }
    i=i-1; store8(number_buf+i,48+n); return number_buf+i;
}

fn write_all(fd, p, n) {
    while n>0 {
        let count=syscall(1,fd,p,n,0,0,0);
        if count==-4 { count=0; } else if count<=0 { return 0; }
        p=p+count; n=n-count;
    }
    return 1;
}
fn row(i) { return tasks+i*128; }
fn rows_on_screen() { let n=(height-326)/66; if n<1 { return 1; } return n; }
fn rebuild_visible() {
    visible_count=0; let i=0;
    while i<task_count {
        let done=load8(row(i));
        if view==0 || (view==1 && !done) || (view==2 && done) {
            store64(visible+visible_count*8,i); visible_count=visible_count+1;
        }
        i=i+1;
    }
    let limit=visible_count-rows_on_screen(); if limit<0 { limit=0; }
    if scroll>limit { scroll=limit; } if scroll<0 { scroll=0; }
    return 0;
}
fn completed_count() {
    let count=0; let i=0;
    while i<task_count { count=count+load8(row(i)); i=i+1; }
    return count;
}
fn reset_entry() {
    entry_size=0; caret=0; select_all=0; store8(entry,0); editing=-1; dirty=1; return 0;
}
fn insert(c) {
    if c<32 || c>126 { return 0; }
    if select_all { entry_size=0; caret=0; select_all=0; }
    if entry_size==120 { notice="Tasks can have up to 120 characters."; dirty=1; return 0; }
    let i=entry_size;
    while i>caret { store8(entry+i,load8(entry+i-1)); i=i-1; }
    store8(entry+caret,c); caret=caret+1; entry_size=entry_size+1;
    store8(entry+entry_size,0); dirty=1; notice=0; return 1;
}
fn backspace() {
    if select_all { entry_size=0; caret=0; select_all=0; store8(entry,0); }
    else if caret>0 {
        let i=caret-1;
        while i<entry_size { store8(entry+i,load8(entry+i+1)); i=i+1; }
        caret=caret-1; entry_size=entry_size-1;
    }
    dirty=1; return 0;
}
fn delete_forward() {
    if select_all { backspace(); }
    else if caret<entry_size { caret=caret+1; backspace(); }
    return 0;
}
fn commit_entry() {
    let first=0; let end=entry_size;
    while first<end && load8(entry+first)==32 { first=first+1; }
    while end>first && load8(entry+end-1)==32 { end=end-1; }
    if first==end { notice="Write a task first."; dirty=1; return 0; }
    let index=editing;
    if index<0 {
        if task_count==256 { notice="The list is full (256 tasks)."; dirty=1; return 0; }
        index=task_count; task_count=task_count+1; zero(row(index),128);
    }
    store8(row(index)+1,end-first); copy(row(index)+2,entry+first,end-first);
    store8(row(index)+2+end-first,0); selected=index;
    reset_entry(); saved=0; rebuild_visible();
    let i=0;
    while i<visible_count {
        if load64(visible+i*8)==index && i>=scroll+rows_on_screen() { scroll=i-rows_on_screen()+1; }
        i=i+1;
    }
    return 1;
}
fn remove_task(index) {
    if index<0 || index>=task_count { return 0; }
    let i=index;
    while i+1<task_count { copy(row(i),row(i+1),128); i=i+1; }
    task_count=task_count-1; zero(row(task_count),128);
    if editing==index { reset_entry(); } else if editing>index { editing=editing-1; }
    if selected==index { selected=-1; } else if selected>index { selected=selected-1; }
    saved=0; dirty=1; rebuild_visible(); return 1;
}
fn toggle(index) {
    if index<0 || index>=task_count { return 0; }
    store8(row(index),!load8(row(index))); saved=0; dirty=1; selected=index;
    rebuild_visible(); return 1;
}
fn edit_task(index) {
    if index<0 || index>=task_count { return 0; }
    editing=index; selected=index; entry_size=load8(row(index)+1);
    copy(entry,row(index)+2,entry_size); store8(entry+entry_size,0);
    caret=entry_size; select_all=1; entry_focus=1; dirty=1; return 1;
}
fn clear_completed() {
    let i=0; let changed=0;
    while i<task_count {
        if load8(row(i)) { remove_task(i); changed=1; } else { i=i+1; }
    }
    return changed;
}

fn load_tasks() {
    let fd=syscall(2,data_path,0x20800,0,0,0,0);
    if fd==-2 { task_count=0; return 1; }
    if fd<0 { return 0; }
    let stat=reply;
    if syscall(5,fd,stat,0,0,0,0)<0 || (u32(stat+24)&0xf000)!=0x8000 {
        syscall(3,fd,0,0,0,0,0); return 0;
    }
    disk_size=0; let finished=0;
    while !finished {
        if disk_size==65536 { syscall(3,fd,0,0,0,0,0); return 0; }
        let n=syscall(0,fd,disk+disk_size,65536-disk_size,0,0,0);
        if n==-4 { n=0; }
        else if n<0 { syscall(3,fd,0,0,0,0,0); return 0; }
        else if n==0 { finished=1; }
        disk_size=disk_size+n;
    }
    syscall(3,fd,0,0,0,0,0);
    if disk_size<10 || !same(disk,"FLEXTODO1\n",10) { return 0; }
    task_count=0; let p=10;
    while p<disk_size {
        if task_count==256 || p+2>=disk_size { return 0; }
        let done=load8(disk+p)-48;
        if done<0 || done>1 || load8(disk+p+1)!=9 { return 0; }
        p=p+2; let n=0; zero(row(task_count),128);
        while p<disk_size && load8(disk+p)!=10 {
            let c=load8(disk+p);
            if c<32 || c>126 || n==120 { return 0; }
            store8(row(task_count)+2+n,c); n=n+1; p=p+1;
        }
        if p==disk_size || !n { return 0; }
        store8(row(task_count),done); store8(row(task_count)+1,n);
        task_count=task_count+1; p=p+1;
    }
    saved=1; rebuild_visible(); return 1;
}
fn save_tasks() {
    copy(disk,"FLEXTODO1\n",10); disk_size=10; let i=0;
    while i<task_count {
        let n=load8(row(i)+1);
        store8(disk+disk_size,48+load8(row(i))); store8(disk+disk_size+1,9);
        copy(disk+disk_size+2,row(i)+2,n); store8(disk+disk_size+2+n,10);
        disk_size=disk_size+n+3; i=i+1;
    }
    let fd=syscall(2,temp_path,0x200c1,384,0,0,0);
    if fd<0 { notice="Could not save. Ctrl+S retries."; saved=0; dirty=1; return 0; }
    let ok=write_all(fd,disk,disk_size);
    if syscall(74,fd,0,0,0,0,0)<0 { ok=0; }
    if syscall(3,fd,0,0,0,0,0)<0 { ok=0; }
    if ok && syscall(82,temp_path,data_path,0,0,0,0)==0 { saved=1; notice=0; return 1; }
    syscall(87,temp_path,0,0,0,0,0); saved=0;
    notice="Could not save. Ctrl+S retries."; dirty=1; return 0;
}
fn prepare_paths(path) {
    let n=length(path); if !n || n>4000 { return 0; }
    data_path=path; copy(lock_path,path,n); copy(lock_path+n,".lock",6);
    copy(temp_path,path,n); copy(temp_path+n,".tmp.",5);
    let pid=decimal(syscall(39,0,0,0,0,0,0)); copy(temp_path+n+5,pid,length(pid)+1);
    return 1;
}
fn acquire_lock() {
    lock_fd=syscall(2,lock_path,0x20842,384,0,0,0);
    if lock_fd<0 { return 0; }
    if syscall(73,lock_fd,6,0,0,0,0)<0 { syscall(3,lock_fd,0,0,0,0,0); lock_fd=-1; return 0; }
    return 1;
}

// X11 little-endian wire protocol. Drawing never calls a UI toolkit or Xlib.
fn send_bytes(p,n) {
    while n>0 {
        let count=syscall(44,x_fd,p,n,16384,0,0);
        if count==-4 { count=0; }
        else if count<=0 { io_error=1; running=0; return 0; }
        p=p+count; n=n-count;
    }
    return 1;
}
fn read_exact(p,n) {
    while n>0 {
        store64(polls,x_fd | (1<<32));
        let ready=syscall(7,polls,1,5000,0,0,0);
        if ready==-4 { ready=1; }
        if ready<=0 { return 0; }
        let count=syscall(0,x_fd,p,n,0,0,0);
        if count==-4 { count=0; } else if count<=0 { return 0; }
        p=p+count; n=n-count;
    }
    return 1;
}
fn request(op,size) { zero(packet,size); store8(packet,op); put16(packet+2,size/4); return 0; }
fn receive_reply() {
    let waiting=1;
    while waiting {
        if !read_exact(reply,32) { return 0; }
        let kind=load8(reply)&127;
        if kind==0 { error("X11 rejected a request."); return 0; }
        if kind==1 {
            let extra=u32(reply+4)*4;
            if extra>65504 || !read_exact(reply+32,extra) { return 0; }
            return 1;
        }
        dirty=1;
    }
    return 0;
}
fn intern(name) {
    let n=length(name); let size=8+padded(n); request(16,size);
    put16(packet+4,n); copy(packet+8,name,n);
    if !send_bytes(packet,size) || !receive_reply() { return 0; }
    return u32(reply+8);
}
fn property(atom,kind,format,bytes,n) {
    let count=n; if format==32 { count=n/4; }
    let size=24+padded(n); request(18,size); put32(packet+4,window);
    put32(packet+8,atom); put32(packet+12,kind); store8(packet+16,format);
    put32(packet+20,count); copy(packet+24,bytes,n); return send_bytes(packet,size);
}
fn load_cookie() {
    let filename=env("XAUTHORITY");
    if !filename || !length(filename) {
        let home=env("HOME"); if !home || length(home)>3900 { return 0; }
        copy(authority,home,length(home)); copy(authority+length(home),"/.Xauthority",13); filename=authority;
    }
    let fd=syscall(2,filename,0,0,0,0,0); if fd<0 { return 0; }
    let n=syscall(0,fd,reply,65536,0,0,0); syscall(3,fd,0,0,0,0,0);
    if n<=0 { return 0; }
    let p=0;
    while p+2<=n {
        let family=be16(reply+p); p=p+2;
        if p+2>n { return 0; } let size=be16(reply+p); p=p+2+size;
        if p+2>n { return 0; } size=be16(reply+p); p=p+2;
        if p+size>n { return 0; }
        let match_display=size==length(display_number) && same(reply+p,display_number,size);
        p=p+size; if p+2>n { return 0; } size=be16(reply+p); p=p+2;
        if p+size>n { return 0; }
        let match_name=size==18 && same(reply+p,"MIT-MAGIC-COOKIE-1",18);
        p=p+size; if p+2>n { return 0; } size=be16(reply+p); p=p+2;
        if p+size>n { return 0; }
        if (family==256 || family==65535) && match_display && match_name && size<=256 {
            copy(cookie,reply+p,size); cookie_size=size; return 1;
        }
        p=p+size;
    }
    return 0;
}
fn connect_display() {
    if !display_name { display_name=env("DISPLAY"); }
    if !display_name { error("DISPLAY is not set. Start the app in a graphical Linux session."); return 0; }
    let p=display_name;
    if length(p)>=5 && same(p,"unix:",5) { p=p+4; }
    if load8(p)!=58 { error("Only local X11/Xwayland displays are supported."); return 0; }
    p=p+1; let n=0;
    while load8(p+n)>=48 && load8(p+n)<=57 { n=n+1; }
    if n==0 || n>8 { return 0; }
    display_number=authority+4096; copy(display_number,p,n); store8(display_number+n,0);
    put16(socket_address,1); copy(socket_address+2,"/tmp/.X11-unix/X",16);
    copy(socket_address+18,p,n); store8(socket_address+18+n,0);
    x_fd=syscall(41,1,0x80001,0,0,0,0);
    if x_fd<0 || syscall(42,x_fd,socket_address,19+n,0,0,0)<0 {
        error("Cannot connect to the X11 display."); return 0;
    }
    load_cookie(); let name_size=0; if cookie_size { name_size=18; }
    let size=12+padded(name_size)+padded(cookie_size); zero(packet,size);
    store8(packet,108); put16(packet+2,11); put16(packet+6,name_size); put16(packet+8,cookie_size);
    if cookie_size { copy(packet+12,"MIT-MAGIC-COOKIE-1",18); copy(packet+12+padded(18),cookie,cookie_size); }
    if !send_bytes(packet,size) || !read_exact(packet,8) { return 0; }
    let setup_size=u16(packet+6)*4;
    if setup_size>65536 || !read_exact(reply,setup_size) { return 0; }
    if load8(packet)!=1 { error("X11 authentication failed. Check DISPLAY and XAUTHORITY."); return 0; }
    if setup_size<32 || load8(reply+20)<1 { return 0; }
    resource_base=u32(reply+4); key_first=load8(reply+26); key_last=load8(reply+27);
    let screen=32+padded(u16(reply+16))+load8(reply+21)*8;
    if screen+40>setup_size { return 0; }
    root=u32(reply+screen); root_depth=load8(reply+screen+38);
    if root_depth!=24 && root_depth!=32 { error("A TrueColor X11 display is required."); return 0; }
    window=resource_base|1; gc=resource_base|2; pixmap=resource_base|3;
    return 1;
}
fn create_window() {
    request(1,40); put32(packet+4,window); put32(packet+8,root);
    put16(packet+12,80); put16(packet+14,60); put16(packet+16,width); put16(packet+18,height);
    put16(packet+22,1); put32(packet+28,2050); put32(packet+32,0xf4f4ef);
    put32(packet+36,0x28045); send_bytes(packet,40);
    request(55,24); put32(packet+4,gc); put32(packet+8,window); put32(packet+12,12);
    put32(packet+16,0x172f28); put32(packet+20,0xf4f4ef); send_bytes(packet,24);
    property(39,31,8,"Flexscript Todo",15);
    property(67,31,8,"flexscript-todo\0FlexscriptTodo\0",31);
    wm_protocols=intern("WM_PROTOCOLS"); wm_delete=intern("WM_DELETE_WINDOW");
    if !wm_protocols || !wm_delete { return 0; }
    put32(rectangles,wm_delete); property(wm_protocols,4,32,rectangles,4);
    let normal=intern("WM_NORMAL_HINTS"); let hints=intern("WM_SIZE_HINTS");
    zero(rectangles,72); put32(rectangles,16); put32(rectangles+20,760); put32(rectangles+24,560);
    property(normal,hints,32,rectangles,72);
    request(101,8); store8(packet+4,key_first); store8(packet+5,key_last-key_first+1);
    if !send_bytes(packet,8) || !receive_reply() { return 0; }
    key_columns=load8(reply+1);
    if key_columns<1 || (key_last-key_first+1)*key_columns*4>32768 { return 0; }
    copy(keyboard,reply+32,(key_last-key_first+1)*key_columns*4);
    request(8,8); put32(packet+4,window); return send_bytes(packet,8);
}
fn resize_pixmap() {
    if pixmap_width==width && pixmap_height==height { return 0; }
    if pixmap_width { request(54,8); put32(packet+4,pixmap); send_bytes(packet,8); }
    request(53,16); store8(packet+1,root_depth); put32(packet+4,pixmap); put32(packet+8,window);
    put16(packet+12,width); put16(packet+14,height); send_bytes(packet,16);
    pixmap_width=width; pixmap_height=height; return 0;
}
fn flush_rectangles() {
    if !rectangle_count { return 0; }
    store8(rectangles,70); store8(rectangles+1,0); put16(rectangles+2,3+rectangle_count*2);
    put32(rectangles+4,pixmap); put32(rectangles+8,gc);
    send_bytes(rectangles,12+rectangle_count*8); rectangle_count=0; return 0;
}
fn color(value) {
    if foreground!=value {
        flush_rectangles(); request(56,16); put32(packet+4,gc); put32(packet+8,4);
        put32(packet+12,value); send_bytes(packet,16); foreground=value;
    }
    return 0;
}
fn rect(x,y,w,h) {
    if w<=0 || h<=0 { return 0; }
    if rectangle_count==1024 { flush_rectangles(); }
    let p=rectangles+12+rectangle_count*8;
    put16(p,x); put16(p+2,y); put16(p+4,w); put16(p+6,h);
    rectangle_count=rectangle_count+1; return 0;
}
fn rounded(x,y,w,h,r) {
    rect(x,y+r,w,h-2*r); let row=0;
    while row<r {
        let dy=r-row-1; let dx=0;
        while dx<r && (dx+1)*(dx+1)+dy*dy<=r*r { dx=dx+1; }
        let inset=r-dx; rect(x+inset,y+row,w-2*inset,1);
        rect(x+inset,y+h-row-1,w-2*inset,1); row=row+1;
    }
    return 0;
}
fn draw_text(x,y,s,n,scale) {
    let i=0;
    while i<n {
        let c=load8(s+i); if c<32 || c>126 { c=63; }
        let bits=load64(glyphs+c*8); let row=0;
        while row<7 {
            let col=0;
            while col<5 {
                if bits & (1<<(row*5+col)) {
                    let start=col;
                    while col<5 && (bits & (1<<(row*5+col))) { col=col+1; }
                    rect(x+i*6*scale+start*scale,y+row*scale,(col-start)*scale,scale);
                } else { col=col+1; }
            }
            row=row+1;
        }
        i=i+1;
    }
    return x+n*6*scale;
}
fn label(x,y,s,scale) { return draw_text(x,y,s,length(s),scale); }
fn checkmark(x,y,scale) {
    let i=0; while i<3 { rect(x+i*scale,y+i*scale,scale,scale); i=i+1; }
    i=0; while i<5 { rect(x+(i+2)*scale,y+(2-i)*scale,scale,scale); i=i+1; }
    return 0;
}
fn hit(x,y) {
    if x>=16 && x<192 && y>=178 && y<326 {
        let item=(y-178)/52; if (y-178)%52<44 { return 10+item; }
    }
    if y>=154 && y<216 {
        if x>=width-132 && x<width-36 { return 1; }
        if x>=240 && x<width-144 { return 2; }
    }
    if x>=width-164 && x<width-32 && y>=228 && y<252 { return 20; }
    if y>=266 && x>=240 && x<width-32 {
        let position=(y-266)/66;
        if position<rows_on_screen() && position+scroll<visible_count && (y-266)%66<58 {
            let code=1000+(position+scroll)*3;
            if x>=width-76 { return code+2; }
            if x>=width-114 { return code+1; }
            return code;
        }
    }
    return 0;
}
fn render() {
    rebuild_visible(); resize_pixmap(); color(0xf4f4ef); rect(0,0,width,height);
    if width<760 || height<560 {
        color(0x193d32); label(16,24,"Please enlarge the window",1);
        flush_rectangles(); request(62,28); put32(packet+4,pixmap); put32(packet+8,window); put32(packet+12,gc);
        put16(packet+24,width); put16(packet+26,height); send_bytes(packet,28); dirty=0; return 0;
    }
    color(0x193d32); rect(0,0,208,height);
    color(0xdbeaaf); rounded(28,35,40,40,10); color(0x193d32); checkmark(37,53,3);
    color(0xf4f4ef); label(28,99,"TODAY.",3);
    color(0xa9c0b2); label(28,137,"A LITTLE MORE DONE.",1);
    let done=completed_count(); let item=0;
    while item<3 {
        let y=178+item*52;
        if view==item { color(0x315648); rounded(16,y,176,44,8); }
        else if hovered==10+item { color(0x244b3e); rounded(16,y,176,44,8); }
        color(0xddeaaf); if view!=item { color(0xc0d0c5); }
        let name="All tasks"; let count=task_count;
        if item==1 { name="Active"; count=task_count-done; }
        else if item==2 { name="Completed"; count=done; }
        label(28,y+15,name,2); label(164,y+16,decimal(count),1); item=item+1;
    }
    color(0x244b3e); rounded(20,height-158,168,106,10);
    color(0xdbeaaf); label(32,height-138,"A little progress",1);
    color(0xf4f4ef); let x=label(32,height-116,decimal(done),2);
    label(x+8,height-111,"of",1); x=label(x+27,height-116,decimal(task_count),2);
    label(x+6,height-111,"done",1);
    color(0x416653); rounded(32,height-84,140,8,3);
    if task_count && done { color(0xdbeaaf); rect(32,height-84,140*done/task_count,8); }
    color(0xa9c0b2); label(28,height-28,"Small steps, daily.",1);
    color(0x64766a); label(244,40,"YOUR EVERYDAY LIST",1);
    color(0x193d32); label(240,68,"Make space.",4);
    color(0x64766a); label(244,116,"A clear place for the things that matter.",1);
    color(0xd1dcd3); if entry_focus { color(0x658d6f); } rounded(240,154,width-272,62,10);
    color(0xffffff); rounded(242,156,width-276,58,8);
    let capacity=(width-424)/12; if capacity<1 { capacity=1; }
    let start=0; if caret>=capacity { start=caret-capacity+1; }
    let shown=minimum(entry_size-start,capacity);
    if !entry_size {
        color(0x87958a); label(260,178,"Add a task...",2);
    } else {
        if select_all { color(0xdbeaaf); rect(258,174,shown*12+4,23); }
        color(0x213b2e); draw_text(260,178,entry+start,shown,2);
    }
    if entry_focus && !select_all { color(0x2f6a44); rect(260+(caret-start)*12,174,2,24); }
    color(0x2f6a44); if hovered==1 { color(0x244f34); } rounded(width-132,164,90,42,7);
    color(0xffffff); let button="+ Add"; if editing>=0 { button="Save"; } label(width-116,178,button,2);
    color(0x64766a); let heading="ALL TASKS"; if view==1 { heading="ACTIVE TASKS"; } else if view==2 { heading="COMPLETED TASKS"; }
    let end=label(244,235,heading,1); label(end+12,235,decimal(visible_count),1);
    color(0x87958a); if done { color(0x385f43); } label(width-144,235,"Clear done",1);
    let position=scroll;
    while position<visible_count && position<scroll+rows_on_screen() {
        let index=load64(visible+position*8); let y=266+(position-scroll)*66;
        let completed=load8(row(index)); let h=1000+position*3;
        color(0xe1e7df); rounded(240,y,width-272,58,9);
        color(0xffffff); if hovered>=h && hovered<=h+2 { color(0xf8faf4); }
        if editing==index || (!entry_focus && selected==index) { color(0xf0f7e8); } rounded(241,y+1,width-274,56,8);
        color(0xb9cbbb); if completed { color(0x2f6a44); } rounded(258,y+18,23,23,5);
        if completed { color(0xffffff); checkmark(262,y+28,2); }
        else { color(0xffffff); rounded(260,y+20,19,19,3); }
        color(0x233b2e); if completed { color(0x8a978d); }
        let n=load8(row(index)+1); let max=(width-414)/12;
        let displayed=minimum(n,max); let letters=displayed;
        if n>max { letters=max-3; } draw_text(296,y+23,row(index)+2,letters,2);
        if n>max { label(296+(max-3)*12,y+23,"...",2); }
        if completed { rect(295,y+31,displayed*12,1); }
        if hovered==h+1 { color(0xe2efdc); rounded(width-113,y+13,29,32,6); }
        color(0x6b816e); // Hand-drawn pencil, edit action.
        let i=0; while i<9 { rect(width-107+i,y+34-i,3,3); i=i+1; }
        if hovered==h+2 { color(0xf6ded8); rounded(width-75,y+13,29,32,6); }
        color(0x9c796d); i=0;
        while i<10 { rect(width-68+i,y+22+i,2,2); rect(width-68+i,y+31-i,2,2); i=i+1; }
        position=position+1;
    }
    if visible_count==0 {
        color(0xe8eddf); rounded(240,266,width-272,180,12);
        color(0xb8cda7); rounded(272,292,52,52,13); color(0x426648); checkmark(283,317,5);
        color(0x294f37); let title="One less thing.";
        if view==1 { title="All caught up."; } else if view==2 { title="Fresh beginnings."; }
        label(272,368,title,2); color(0x667968);
        let subtitle="Start with a small task above.";
        if view==1 { subtitle="Every task is checked off. Nice work."; }
        else if view==2 { subtitle="Completed tasks will appear here."; }
        label(272,405,subtitle,1);
    }
    color(0x64766a); label(244,height-47,"ENTER TO ADD / SAVE    ESC TO CANCEL",1);
    color(0x55775c); let status="Saved locally";
    if !saved { color(0xa8513b); status="Unsaved changes - Ctrl+S to retry"; }
    if notice { status=notice; } label(244,height-24,status,1);
    if visible_count>rows_on_screen() {
        color(0x64766a); let last=minimum(scroll+rows_on_screen(),visible_count);
        let x=label(width-158,height-24,decimal(scroll+1),1); x=label(x,height-24,"-",1);
        x=label(x,height-24,decimal(last),1); x=label(x,height-24," / ",1); label(x,height-24,decimal(visible_count),1);
    }
    flush_rectangles(); request(62,28); put32(packet+4,pixmap); put32(packet+8,window); put32(packet+12,gc);
    put16(packet+24,width); put16(packet+26,height); send_bytes(packet,28); dirty=0; return 0;
}

fn initialize_font() {
    store64(glyphs + 256, 0x0);
    store64(glyphs + 264, 0x100421084);
    store64(glyphs + 272, 0x294a);
    store64(glyphs + 280, 0x295f57d4a);
    store64(glyphs + 288, 0x11f4717c4);
    store64(glyphs + 296, 0x632221173);
    store64(glyphs + 304, 0x593532526);
    store64(glyphs + 312, 0x884);
    store64(glyphs + 320, 0x208210888);
    store64(glyphs + 328, 0x88842082);
    store64(glyphs + 336, 0x2aefbaa0);
    store64(glyphs + 344, 0x84f9080);
    store64(glyphs + 352, 0x88600000);
    store64(glyphs + 360, 0xf8000);
    store64(glyphs + 368, 0x18c000000);
    store64(glyphs + 376, 0x42222210);
    store64(glyphs + 384, 0x3a33ae62e);
    store64(glyphs + 392, 0x3884210c4);
    store64(glyphs + 400, 0x7c444422e);
    store64(glyphs + 408, 0x3e107420f);
    store64(glyphs + 416, 0x211f4a988);
    store64(glyphs + 424, 0x3e107843f);
    store64(glyphs + 432, 0x3a317842e);
    store64(glyphs + 440, 0x8422221f);
    store64(glyphs + 448, 0x3a317462e);
    store64(glyphs + 456, 0x3a10f462e);
    store64(glyphs + 464, 0xc6018c0);
    store64(glyphs + 472, 0x886018c0);
    store64(glyphs + 480, 0x410411110);
    store64(glyphs + 488, 0x1f07c00);
    store64(glyphs + 496, 0x44441041);
    store64(glyphs + 504, 0x10044422e);
    store64(glyphs + 512, 0x783daf62e);
    store64(glyphs + 520, 0x4631fc62e);
    store64(glyphs + 528, 0x3e317c62f);
    store64(glyphs + 536, 0x78210843e);
    store64(glyphs + 544, 0x3e318c62f);
    store64(glyphs + 552, 0x7c217843f);
    store64(glyphs + 560, 0x4217843f);
    store64(glyphs + 568, 0x3a31e843e);
    store64(glyphs + 576, 0x4631fc631);
    store64(glyphs + 584, 0x38842108e);
    store64(glyphs + 592, 0x19284211c);
    store64(glyphs + 600, 0x452519531);
    store64(glyphs + 608, 0x7c2108421);
    store64(glyphs + 616, 0x46318d771);
    store64(glyphs + 624, 0x4631cd671);
    store64(glyphs + 632, 0x3a318c62e);
    store64(glyphs + 640, 0x4217c62f);
    store64(glyphs + 648, 0x59358c62e);
    store64(glyphs + 656, 0x45257c62f);
    store64(glyphs + 664, 0x3e107043e);
    store64(glyphs + 672, 0x10842109f);
    store64(glyphs + 680, 0x3a318c631);
    store64(glyphs + 688, 0x11518c631);
    store64(glyphs + 696, 0x47758c631);
    store64(glyphs + 704, 0x462a22a31);
    store64(glyphs + 712, 0x108422a31);
    store64(glyphs + 720, 0x7c222221f);
    store64(glyphs + 728, 0x38421084e);
    store64(glyphs + 736, 0x420820821);
    store64(glyphs + 744, 0x39084210e);
    store64(glyphs + 752, 0x4544);
    store64(glyphs + 760, 0x7c0000000);
    store64(glyphs + 768, 0x82);
    store64(glyphs + 776, 0x7a3e83800);
    store64(glyphs + 784, 0x3e318bc21);
    store64(glyphs + 792, 0x78210f800);
    store64(glyphs + 800, 0x7a318fa10);
    store64(glyphs + 808, 0x783f8b800);
    store64(glyphs + 816, 0x84238a4c);
    store64(glyphs + 824, 0x3a1e8c7c0);
    store64(glyphs + 832, 0x46318bc21);
    store64(glyphs + 840, 0x388421804);
    store64(glyphs + 848, 0x192843008);
    store64(glyphs + 856, 0x24a32a421);
    store64(glyphs + 864, 0x388421086);
    store64(glyphs + 872, 0x4635aac00);
    store64(glyphs + 880, 0x46318bc00);
    store64(glyphs + 888, 0x3a318b800);
    store64(glyphs + 896, 0x42f8c5e0);
    store64(glyphs + 904, 0x421e8c7c0);
    store64(glyphs + 912, 0x4219b400);
    store64(glyphs + 920, 0x3e0e0f800);
    store64(glyphs + 928, 0x324211c42);
    store64(glyphs + 936, 0x7a318c400);
    store64(glyphs + 944, 0x11518c400);
    store64(glyphs + 952, 0x2ab58c400);
    store64(glyphs + 960, 0x454454400);
    store64(glyphs + 968, 0x3a1e8c620);
    store64(glyphs + 976, 0x7c4447c00);
    store64(glyphs + 984, 0x608431098);
    store64(glyphs + 992, 0x108421084);
    store64(glyphs + 1000, 0xc8461083);
    store64(glyphs + 1008, 0x6c800);
    return 0;
}

fn initialize() {
    tasks=alloc(32768); visible=alloc(2048); entry=alloc(128);
    disk=alloc(65536); lock_path=alloc(4096); temp_path=alloc(4096);
    glyphs=alloc(1024); number_buf=alloc(48); packet=alloc(65536); reply=alloc(65536);
    rectangles=alloc(16384); keyboard=alloc(32768); event=alloc(128);
    authority=alloc(8192); cookie=alloc(256); socket_address=alloc(128);
    signal_mask=alloc(8); old_mask=alloc(8); polls=alloc(16);
    initialize_font(); return 0;
}
fn focus_window() {
    request(42,12); store8(packet+1,1); put32(packet+4,window); send_bytes(packet,12); return 0;
}
fn scroll_by(amount) { scroll=scroll+amount; rebuild_visible(); dirty=1; return 0; }
fn select_row(direction) {
    let position=-1; let i=0;
    while i<visible_count { if load64(visible+i*8)==selected { position=i; } i=i+1; }
    if position<0 { position=scroll; } else { position=position+direction; }
    if position<0 { position=0; } if position>=visible_count { position=visible_count-1; }
    if position>=0 {
        selected=load64(visible+position*8);
        if position<scroll { scroll=position; }
        if position>=scroll+rows_on_screen() { scroll=position-rows_on_screen()+1; }
    }
    dirty=1; return 0;
}
fn key_symbol(code,state) {
    if code<key_first || code>key_last { return 0; }
    let p=keyboard+(code-key_first)*key_columns*4; let base=u32(p); let symbol=base;
    if (state&1) && key_columns>1 { symbol=u32(p+4); if !symbol { symbol=base; } }
    if state&2 {
        if symbol>=97 && symbol<=122 { symbol=symbol-32; }
        else if symbol>=65 && symbol<=90 { symbol=symbol+32; }
    }
    return symbol;
}
fn key_press(symbol,state) {
    if state&4 {
        if symbol==97 || symbol==65 { if entry_focus { select_all=1; dirty=1; } }
        else if symbol==115 || symbol==83 { save_tasks(); dirty=1; }
        else if symbol==113 || symbol==81 { running=0; }
        return 0;
    }
    if state&8 { return 0; }
    if symbol==0xff1b { reset_entry(); entry_focus=1; notice=0; return 0; }
    if symbol==0xff09 || symbol==0xfe20 {
        entry_focus=!entry_focus; select_all=0; if !entry_focus { select_row(0); } dirty=1; return 0;
    }
    if !entry_focus {
        if symbol==0xff52 { select_row(-1); }
        else if symbol==0xff54 { select_row(1); }
        else if symbol==0xff0d || symbol==32 { if toggle(selected) { save_tasks(); } }
        else if symbol==0xffff { if remove_task(selected) { save_tasks(); } }
        else if symbol==0xffbf || symbol==101 { edit_task(selected); }
        else if symbol==0xff55 { select_row(0-rows_on_screen()); }
        else if symbol==0xff56 { select_row(rows_on_screen()); }
        return 0;
    }
    if symbol==0xff0d || symbol==0xff8d { if commit_entry() { save_tasks(); } }
    else if symbol==0xff08 { backspace(); }
    else if symbol==0xffff { delete_forward(); }
    else if symbol==0xff51 { if caret>0 { caret=caret-1; } select_all=0; dirty=1; }
    else if symbol==0xff53 { if caret<entry_size { caret=caret+1; } select_all=0; dirty=1; }
    else if symbol==0xff50 { caret=0; select_all=0; dirty=1; }
    else if symbol==0xff57 { caret=entry_size; select_all=0; dirty=1; }
    else if symbol==0xff52 || symbol==0xff54 { entry_focus=0; select_row(0); }
    else { insert(symbol); }
    return 0;
}
fn click(button,x,y) {
    if width<760 || height<560 { return 0; }
    if button==4 { scroll_by(-1); return 0; }
    if button==5 { scroll_by(1); return 0; }
    if button!=1 { return 0; }
    focus_window(); let action=hit(x,y); notice=0;
    if action==1 { if commit_entry() { save_tasks(); } entry_focus=1; }
    else if action==2 {
        let capacity=(width-424)/12; if capacity<1 { capacity=1; }
        let start=0; if caret>=capacity { start=caret-capacity+1; }
        caret=start+(x-260+6)/12; if caret<0 { caret=0; } if caret>entry_size { caret=entry_size; }
        entry_focus=1; select_all=0;
    } else if action>=10 && action<=12 {
        view=action-10; scroll=0; selected=-1; rebuild_visible();
    } else if action==20 { if clear_completed() { save_tasks(); } }
    else if action>=1000 {
        let position=(action-1000)/3; let index=load64(visible+position*8); let choice=(action-1000)%3;
        if choice==1 { edit_task(index); }
        else if choice==2 { if remove_task(index) { save_tasks(); } }
        else { entry_focus=0; if toggle(index) { save_tasks(); } }
    }
    dirty=1; return 0;
}
fn start_signals() {
    store64(signal_mask,0x5007);
    if syscall(14,0,signal_mask,old_mask,8,0,0)<0 { return 0; }
    signal_fd=syscall(289,-1,signal_mask,8,0x80800,0,0);
    if signal_fd<0 { syscall(14,2,old_mask,0,8,0,0); return 0; }
    return 1;
}
fn stop_signals() {
    if signal_fd>=0 {
        while syscall(0,signal_fd,event,128,0,0,0)>0 { }
        syscall(3,signal_fd,0,0,0,0,0); signal_fd=-1;
        syscall(14,2,old_mask,0,8,0,0);
    }
    return 0;
}
fn dispatch_event() {
    let kind=load8(event)&127;
    if kind==0 {
        error("X11 request error; closing the window."); io_error=1; running=0;
    } else if kind==2 { key_press(key_symbol(load8(event+1),u16(event+28)),u16(event+28)); }
    else if kind==4 { click(load8(event+1),u16(event+24),u16(event+26)); }
    else if kind==6 {
        pointer_x=u16(event+24); pointer_y=u16(event+26); let target=hit(pointer_x,pointer_y);
        if hovered!=target { hovered=target; dirty=1; }
    } else if kind==12 { dirty=1; }
    else if kind==22 {
        let w=u16(event+20); let h=u16(event+22);
        if w>0 && h>0 && (w!=width || h!=height) { width=w; height=h; dirty=1; }
    } else if kind==17 { running=0; }
    else if kind==33 && u32(event+8)==wm_protocols && u32(event+12)==wm_delete { running=0; }
    return 0;
}
fn event_loop() {
    while running {
        if dirty { render(); }
        store64(polls,x_fd | (1<<32)); store64(polls+8,signal_fd | (1<<32));
        let n=syscall(7,polls,2,-1,0,0,0);
        if n<0 && n!=-4 { io_error=1; running=0; }
        else if n>0 {
            if u16(polls+14) { running=0; }
            else if u16(polls+6)&(8|16|32) { io_error=1; running=0; }
            else if u16(polls+6)&1 {
                if read_exact(event,32) { dispatch_event(); } else { io_error=1; running=0; }
            }
        }
    }
    return 0;
}
fn expect(ok,message) {
    tests=tests+1;
    if !ok { failures=failures+1; error(message); }
    return 0;
}
fn set_entry(s) { reset_entry(); let i=0; while load8(s+i) { insert(load8(s+i)); i=i+1; } return 0; }
fn model_tests() {
    expect(!commit_entry(),"Blank task rejected");
    set_entry("   "); expect(!commit_entry(),"Whitespace task rejected");
    set_entry("  Buy milk  "); expect(commit_entry(),"Add trimmed task");
    expect(task_count==1 && equal(row(0)+2,"Buy milk"),"Trim preserves task case");
    set_entry("Write Flexscript"); expect(commit_entry() && task_count==2,"Add second task");
    toggle(0); expect(completed_count()==1,"Complete a task");
    view=1; rebuild_visible(); expect(visible_count==1 && load64(visible)==1,"Active filter");
    view=2; rebuild_visible(); expect(visible_count==1 && load64(visible)==0,"Completed filter");
    edit_task(0); insert(82); insert(101); insert(97); insert(100);
    expect(commit_entry() && equal(row(0)+2,"Read") && load8(row(0))==1,"Edit preserves completion");
    view=0; rebuild_visible(); expect(visible_count==2,"All filter");
    expect(clear_completed() && task_count==1 && equal(row(0)+2,"Write Flexscript"),"Clear completed");
    set_entry("ac"); caret=1; insert(98); expect(equal(entry,"abc") && caret==2,"Caret insertion");
    backspace(); expect(equal(entry,"ac") && caret==1,"Backspace at caret");
    delete_forward(); expect(equal(entry,"a"),"Delete forward");
    select_all=1; insert(90); expect(equal(entry,"Z"),"Replace selection");
    select_all=1; backspace(); expect(entry_size==0,"Delete selection");
    let i=0; while i<120 { insert(120); i=i+1; }
    expect(entry_size==120 && !insert(120),"Length limit"); reset_entry();
    expect(!remove_task(-1) && !toggle(999),"Reject invalid indices");
    remove_task(0); expect(task_count==0,"Remove task");
    i=0; while i<256 { set_entry("A task"); commit_entry(); i=i+1; }
    expect(task_count==256,"Full task capacity"); set_entry("Overflow"); expect(!commit_entry(),"Capacity limit");
    scroll=999; rebuild_visible(); expect(scroll==visible_count-rows_on_screen(),"Clamp scrolling");
    scroll_by(-999); expect(scroll==0,"Clamp negative scrolling");
    edit_task(2); remove_task(1); expect(editing==1,"Edit index follows deletion");
    remove_task(1); expect(editing==-1 && entry_size==0,"Deleting edited task cancels edit");
    task_count=0; view=0; scroll=0; selected=-1; reset_entry(); rebuild_visible();
    set_entry("Learn Flexscript"); commit_entry(); set_entry("Make something useful"); commit_entry(); toggle(1);
    return 0;
}
fn self_test(file_test) {
    model_tests();
    if file_test {
        let fd=syscall(2,data_path,0x20800,0,0,0,0);
        if fd>=0 { syscall(3,fd,0,0,0,0,0); error("Self-test requires a new data path."); return 1; }
        if fd!=-2 { error("Cannot access self-test data path."); return 1; }
        if !acquire_lock() { error("Cannot lock self-test data path."); return 1; }
        expect(save_tasks(),"Save data"); task_count=0;
        expect(load_tasks() && task_count==2,"Load saved data");
        expect(equal(row(0)+2,"Learn Flexscript") && equal(row(1)+2,"Make something useful") && load8(row(1))==1,"Round-trip text and completion");
        toggle(0); expect(save_tasks(),"Replace data atomically"); task_count=0;
        expect(load_tasks() && completed_count()==2,"Load replaced data");
        syscall(3,lock_fd,0,0,0,0,0); lock_fd=-1;
    }
    let count=decimal(tests); syscall(1,1,count,length(count),0,0,0);
    let message=" todo checks passed\n"; if failures { message=" todo checks ran with failures\n"; }
    syscall(1,1,message,length(message),0,0,0);
    if failures { return 1; } return 0;
}
fn main(argc,argv) {
    environment=argv+(argc+1)*8; initialize();
    let path="flexscript-todos.db"; let test=0; let explicit_path=0; let i=1;
    while i<argc {
        let arg=load64(argv+i*8);
        if equal(arg,"--help") || equal(arg,"-h") {
            let help="Flexscript Todo - a hand-drawn native desktop app\nUsage: todo [--data PATH] [--display :N] [--self-test]\n\nAdd with Enter, edit with the pencil, delete with X, check off with the box.\nTab switches input/list; arrows navigate; F2 edits; Delete removes a task.\nCtrl+A selects input, Ctrl+S retries saving, Ctrl+Q closes, Esc cancels editing.\nData: flexscript-todos.db in the current directory; --data chooses another file.\nLinux x86-64, local X11/Xwayland, printable ASCII, 256 tasks, 120 characters.\n";
            syscall(1,1,help,length(help),0,0,0); return 0;
        } else if equal(arg,"--self-test") { test=1; }
        else if equal(arg,"--data") && i+1<argc { i=i+1; path=load64(argv+i*8); explicit_path=1; }
        else if equal(arg,"--display") && i+1<argc { i=i+1; display_name=load64(argv+i*8); }
        else { error("Unknown or incomplete option. Use --help."); return 1; }
        i=i+1;
    }
    if !prepare_paths(path) { error("Invalid data path."); return 1; }
    if test { return self_test(explicit_path); }
    if !acquire_lock() { error("Cannot lock the data file. Another Todo instance may be using it."); return 1; }
    if !load_tasks() { error("Invalid or unreadable todo data. The file was left unchanged."); syscall(3,lock_fd,0,0,0,0,0); return 1; }
    if !start_signals() { error("Cannot initialize signal handling."); syscall(3,lock_fd,0,0,0,0,0); return 1; }
    if !connect_display() || !create_window() {
        if x_fd>=0 { syscall(3,x_fd,0,0,0,0,0); } stop_signals(); syscall(3,lock_fd,0,0,0,0,0); return 1;
    }
    event_loop(); let status=0;
    if !saved && !save_tasks() { error("Could not save the pending changes."); status=1; }
    if io_error { error("The display connection closed unexpectedly."); status=1; }
    syscall(3,x_fd,0,0,0,0,0); stop_signals(); syscall(3,lock_fd,0,0,0,0,0); return status;
}
