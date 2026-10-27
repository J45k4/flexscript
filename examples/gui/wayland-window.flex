// SDL-free xdg-shell/shared-memory bring-up. Use a private Wayland display for
// automated runs; frame callbacks are scheduling evidence, not scanout timings.
import "../../libs/gui/backends/wayland/client.flex";
import "../../scripts/lib/json.flex";
fn main(argc,argv){
    h_environment(argc,argv);let count=3;if argc>1{count=h_number(load64(argv+8));}h_assert(count>=1 && count<=10000,"Provide a frame count from 1 to 10000");
    let client=wl_client_open(0,"Flexscript native Wayland",640,480);h_assert(client,wl_error);let sent=0;let until=wl_now(client)+10000;
    while load64(client+208)<count && !load64(client+112) && wl_now(client)<until{
        if sent<count && !load64(client+168){let color=0xff20302a;if sent%2{color=0xff405840;}if wl_client_present_shm(client,color){sent=sent+1;}}
        wl_client_wait(client,20);
    }
    let report=j_object();j_set(report,"configured",j_bool(load64(client+104)));j_set(report,"width",j_int(load64(client+72)));j_set(report,"height",j_int(load64(client+80)));j_set(report,"frame_callbacks",j_int(load64(client+208)));j_set(report,"buffer_count",j_int(load64(client+216)));j_set(report,"events",j_int(load64(client+176)));let ok=load64(client+208)==count && !load64(client+120);if load64(client+120){j_set(report,"error",j_string(load64(client+120)));}wl_client_close(client);h_print(1,h_cat(j_dump(report),"\n"));return !ok;
}
