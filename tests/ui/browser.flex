// Actual Chromium and the same portable view / patch fixture used by Android.
import "../monolith/cdp.flex";
fn ub_free_port(){let fd=tcp_listen("127.0.0.1","0",8);h_assert(fd>=0,"cannot allocate port");let address=h_take(16);let size=h_take(8);store64(size,16);syscall(51,fd,address,size,0,0,0);let port=(load8(address+2)<<8)|load8(address+3);h_close(fd);return port;}
fn ub_check(tab,expression){let value=cd_eval(tab,expression);h_assert(j_kind(value)==5 && j_value(value),expression);return 0;}
fn ub_counter(binary){
    let port=ub_free_port();let server=h_spawn(h_args(h_real(binary),h_int(port),0,0,0,0),"",0);h_until(server,"listening",5000);let tab=cd_tab(h_cat3("http://127.0.0.1:",h_int(port),"/"));
    cd_wait(tab,"document.querySelector('[data-ui-key=\"count\"]')?.textContent==='0'");
    cd_eval(tab,"window.sharedDraft=document.querySelector('[data-ui-key=\"draft\"]');sharedDraft.value='same view, local draft';sharedDraft.focus();sharedDraft.setSelectionRange(2,7);document.querySelector('[data-ui-key=\"increase\"]').click();true");
    cd_wait(tab,"document.querySelector('[data-ui-key=\"count\"]').textContent==='1'");
    ub_check(tab,"document.querySelector('[data-ui-key=\"draft\"]')===sharedDraft && sharedDraft.value==='same view, local draft' && sharedDraft.selectionStart===2 && sharedDraft.selectionEnd===7");
    cd_eval(tab,"document.querySelector('[data-ui-key=\"reset\"]').click();true");cd_wait(tab,"document.querySelector('[data-ui-key=\"count\"]').textContent==='0'");cd_close(tab);h_stop(server);return 0;
}
fn main(argc,argv){
    h_environment(argc,argv);h_assert(argc==3 || argc==4,"Usage: test-ui-browser WEB-BINARY CHROMIUM [COUNTER-BINARY]");let port=ub_free_port();let server=h_spawn(h_args(h_real(load64(argv+8)),h_int(port),0,0,0,0),"",0);h_until(server,"listening",5000);
    let temp=h_temp();let profile=h_join(temp,"chromium");let args=h_args(load64(argv+16),"--headless","--no-sandbox","--disable-gpu","--no-first-run","--no-default-browser-check");h_add(args,h_cat("--user-data-dir=",profile));h_add(args,"--remote-debugging-address=127.0.0.1");h_add(args,"--remote-debugging-port=0");h_add(args,"about:blank");let chrome=h_spawn(args,"",0);cd_chrome=chrome;
    let portfile=h_join(profile,"DevToolsActivePort");let end=net_now()+30000;
    while !h_exists(portfile){h_pump(chrome,10);if h_status(chrome)!= -999 || net_now()>end{h_stop(chrome);h_stop(server);h_die("headless browser failed to start");}}
    let text=h_read(portfile);cd_port=h_number(h_slice(text,h_find(text,"\n")));let url=h_cat3("http://127.0.0.1:",h_int(port),"/");let a=cd_tab(url);let b=cd_tab(url);
    let ready="document.querySelector('[data-ui-key=\"permissions-summary\"]')?.textContent==='0 allowed · 29 ask · 0 denied'";cd_wait(a,ready);cd_wait(b,ready);
    cd_eval(b,"window.original=document.querySelector('[data-ui-key=\"deny-internet\"]');true");
    cd_eval(a,"document.querySelector('[data-ui-key=\"deny-internet\"]').click();true");cd_wait(b,"document.querySelector('[data-ui-key=\"permissions-summary\"]').textContent==='0 allowed · 28 ask · 1 denied'");
    ub_check(b,"document.querySelector('[data-ui-key=\"deny-internet\"]')===original && original.textContent==='Deny'");
    cd_eval(a,"document.querySelector('[data-ui-key=\"ask-internet\"]').click();true");cd_wait(b,ready);
    cd_screenshot(a,"build/ui-permissions-browser.png",430,932,1);ub_check(a,"document.documentElement.scrollWidth<=430");
    let packets=h_read("build/ui-portable-packets.json");cd_eval(a,h_cat3("window.packets=",packets,";window.mount=document.createElement('div');document.body.append(mount);window.events=[];window.testUi=new FlexscriptUi(mount,e=>events.push(e));testUi.apply(packets[0]);window.field=testUi.need('input-2').el;field.value='local draft';field.focus();field.setSelectionRange(2,6);window.heading=testUi.need('heading').el;true"));
    cd_eval(a,"testUi.apply(packets[1]);testUi.apply(packets[2]);testUi.apply(packets[3]);true");
    ub_check(a,"testUi.need('input-2').el===field && field.value==='local draft' && document.activeElement===field && field.selectionStart===2 && field.selectionEnd===6 && testUi.need('heading').el===heading");
    ub_check(a,"[...testUi.need('rows').el.children].map(n=>n.dataset.uiKey).join(',')==='row-2,row-1' && testUi.need('branch').el.tagName==='BUTTON' && testUi.need('hidden').el.hidden && !testUi.need('value').el.hasAttribute('aria-label')");
    cd_eval(a,"testUi.need('act').el.click();true");ub_check(a,"events.length===1 && events[0].key==='act' && events[0].action==='changed' && events[0].action_id===2");
    cd_eval(a,"testUi.apply(packets[4]);testUi.apply(packets[5]);true");ub_check(a,"testUi.need('input-2').el===field && !testUi.nodes.has('row-1') && testUi.nodes.has('input-3')");
    cd_eval(a,"testUi.apply(packets[6]);true");ub_check(a,"testUi.need('rows').el.children.length===0 && !testUi.nodes.has('input-2')");
    cd_eval(a,"testUi.apply(packets[7]);window.draft=testUi.need('draft').el;draft.value='keep across snapshot';draft.focus();draft.setSelectionRange(1,5);testUi.apply(packets[8]);true");ub_check(a,"testUi.need('draft').el===draft && draft.value==='keep across snapshot' && document.activeElement===draft && draft.selectionStart===1 && draft.selectionEnd===5");
    cd_eval(a,"testUi.apply(packets[9]);true");ub_check(a,"draft.value==='controlled' && testUi.need('value').el.textContent==='5' && testUi.need('value').el.style.fontSize==='21px'");
    // Replay actual Collie screen transitions produced by its compiled reducer.
    let app=h_read("build/collie-ui-packets.json");
    cd_eval(a,h_cat3("window.appPackets=",app,";mount.remove();window.appMount=document.createElement('div');appMount.style.cssText='position:fixed;inset:0;width:430px;height:932px;overflow:hidden;background:#10151a';document.body.append(appMount);window.appEvents=[];window.appUi=new FlexscriptUi(appMount,e=>appEvents.push(e),{imageSource:()=>\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='64' height='64'%3E%3Crect width='64' height='64' fill='%23c5e3ae'/%3E%3C/svg%3E\"});window.appSeen=new Set();window.sawRich=false;window.sawCode=false;window.sawPreview=false;for(const packet of appPackets){appUi.apply(packet);appSeen.add(packet.page);if(appUi.nodes.has('card-3-body')){const el=appUi.need('card-3-body').el;if(el.querySelector('a[href=\"https://example.com/\"]')&&el.querySelector('span[style*=\"bold\"]'))sawRich=true;}if(appUi.nodes.has('card-1-source-body'))sawCode=!!appUi.need('card-1-source-body').el.querySelector('span[style*=\"color\"]');if(packet.page==='preview')sawPreview=appUi.need('preview-image').el.getAttribute('aria-label')==='Full image: /photo.jpg';}true"));
    ub_check(a,"['chat','menu','permissions','model','conversations','workers','preview','attachments','notice'].every(page=>appSeen.has(page)) && sawRich && sawCode && sawPreview && appEvents.length===0");
    ub_check(a,"appUi.need('card-179-body').el.textContent==='Historical message 179' && appUi.need('composer-draft').el.tagName==='TEXTAREA' && appUi.need('app-root').el.getBoundingClientRect().height===932 && appUi.need('composer').el.getBoundingClientRect().bottom<=932");
    cd_eval(a,"appUi.need('chat-menu').el.click();true");ub_check(a,"appEvents.length===1 && appEvents[0].key==='chat-menu' && appEvents[0].action==='menu'");
    cd_wait(a,"[...appMount.querySelectorAll('img')].every(el=>el.complete && el.naturalWidth>0)");
    cd_screenshot(a,"build/collie-ui-browser.png",430,932,1);
    if argc==4{ub_counter(load64(argv+24));}
    cd_close(a);cd_close(b);h_stop(chrome);h_stop(server);h_print(1,"PASS: portable browser actions, cross-client patches, layout, keyed identity, focus/drafts, replacement, removal, snapshot, controlled input and every Collie screen\n");return 0;
}
