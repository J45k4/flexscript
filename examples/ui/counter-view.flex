// Shared unchanged view/state for the browser and native desktop hosts.
global count=0;
view app_view(){
    column("app",height:-1,padding:24,gap:16,background:"#10151a"){
        text("heading",text:"One view. Native widgets.",size:24,color:"#edf2ed");
        text("count",text:m_int(count),size:40,color:"#c5e3ae");
        row("controls",gap:12){
            button("increase",text:"Increase",action:"increase",padding:12,color:"#10151a",background:"#c5e3ae",radius:12);
            button("reset",text:"Reset",action:"reset",padding:12,color:"#edf2ed",background:"#232c33",radius:12);
        }
        input("draft",text:"This draft survives count updates",description:"Local draft",padding:12,color:"#edf2ed",background:"#232c33",radius:12);
    }
}
fn app_init(path){return 0;}
fn app_tick(){return 0;}
fn app_action(action,id){if m_eq(action,"increase"){count=count+1;return 200;}if m_eq(action,"reset"){count=0;return 200;}return 422;}
