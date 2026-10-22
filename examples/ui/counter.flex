// Standalone portable views with a browser host. The view has no DOM dependency.
import "ui/web.flex";
import "counter-view.flex";
extend "ui/syntax.flex";
fn main(argc,argv){return mono_run(argc,argv,"Portable counter",8092,"");}
