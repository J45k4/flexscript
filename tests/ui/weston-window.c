/* Independent observer for a PRIVATE Weston 15 desktop-shell test session.
 * Uses compositor state and protocol logging; never linked into the app. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
#include <libweston/libweston.h>
#include <libweston/desktop.h>
struct fixture {
    struct weston_compositor *compositor;
    struct wl_event_source *timer;
    struct wl_listener destroy,target_destroy;
    struct weston_surface *target;
    struct wl_protocol_logger *logger;
    struct wl_client *target_client;
    struct wl_resource *target_top;
    int req_min_w,req_min_h,req_max_w,req_max_h;
    unsigned minimizes,closes,maps,unmaps,attaches;
    int previous_mapped,ui_sent;
};
static void target_destroyed(struct wl_listener *listener,void *data){
    (void)data;struct fixture *f=wl_container_of(listener,f,target_destroy);
    wl_list_remove(&f->target_destroy.link);f->target=NULL;f->previous_mapped=0;f->ui_sent=0;
}
static void protocol(void *data,enum wl_protocol_logger_type direction,const struct wl_protocol_logger_message *message){
    struct fixture *f=data;
    if(direction==WL_PROTOCOL_LOGGER_REQUEST && !strcmp(wl_resource_get_class(message->resource),"xdg_toplevel") && !strcmp(message->message->name,"set_app_id") && !strcmp(message->arguments[0].s,"org.flexscript.Collie")){f->target_client=wl_resource_get_client(message->resource);if(f->target_top!=message->resource){f->target_top=message->resource;f->req_min_w=f->req_min_h=f->req_max_w=f->req_max_h=0;}}
    if(wl_resource_get_client(message->resource)!=f->target_client)return;
    if(direction==WL_PROTOCOL_LOGGER_REQUEST && message->resource==f->target_top){
        if(!strcmp(message->message->name,"set_min_size")){f->req_min_w=message->arguments[0].i;f->req_min_h=message->arguments[1].i;}
        if(!strcmp(message->message->name,"set_max_size")){f->req_max_w=message->arguments[0].i;f->req_max_h=message->arguments[1].i;}
    }
    if(direction==WL_PROTOCOL_LOGGER_REQUEST && !strcmp(wl_resource_get_class(message->resource),"xdg_toplevel") && !strcmp(message->message->name,"set_minimized"))f->minimizes++;
    if(direction==WL_PROTOCOL_LOGGER_REQUEST && !strcmp(wl_resource_get_class(message->resource),"wl_surface") && !strcmp(message->message->name,"attach") && message->arguments[0].o)f->attaches++;
}
static int step(void *data){
    struct fixture *f=data;struct weston_view *view;struct weston_desktop_surface *desktop=NULL;int listed=0;long layer=-1;
    wl_list_for_each(view,&f->compositor->view_list,link){
        if(!weston_surface_is_desktop_surface(view->surface))continue;
        struct weston_desktop_surface *candidate=weston_surface_get_desktop_surface(view->surface);
        const char *id=weston_desktop_surface_get_app_id(candidate);
        if(!id || strcmp(id,"org.flexscript.Collie"))continue;
        if(view->surface!=f->target){
            if(f->target)wl_list_remove(&f->target_destroy.link);
            f->target=view->surface;f->target_destroy.notify=target_destroyed;f->previous_mapped=0;f->ui_sent=0;
            wl_signal_add(&f->target->destroy_signal,&f->target_destroy);
        }
        desktop=candidate;listed=1;if(view->layer_link.layer)layer=view->layer_link.layer->position;break;
    }
    if(!desktop && f->target && weston_surface_is_desktop_surface(f->target))desktop=weston_surface_get_desktop_surface(f->target);
    int mapped=f->target && f->target->is_mapped;
    if(mapped!=f->previous_mapped){if(mapped)f->maps++;else f->unmaps++;f->previous_mapped=mapped;}
    const char *title=desktop?weston_desktop_surface_get_title(desktop):NULL;
    const char *id=desktop?weston_desktop_surface_get_app_id(desktop):NULL;
    /* An actual protocol key gives replayed clipboard checks a valid serial.
     * Restricted to the private UI fixture; never affects lifecycle clients. */
    if(mapped && !f->ui_sent && getenv("FLEX_WESTON_UI_INPUT") && title &&
       (!strcmp(title,"Flexscript desktop UI verification") || !strcmp(title,"Collie shared UI on desktop") || !strcmp(title,"Headless Markdown tables") || !strcmp(title,"Scroll regression"))){
        struct weston_seat *seat;
        wl_list_for_each(seat,&f->compositor->seat_list,link){
            struct weston_keyboard *keyboard=weston_seat_get_keyboard(seat);
            if(!keyboard)continue;
            struct timespec now;clock_gettime(CLOCK_MONOTONIC,&now);
            weston_keyboard_set_focus(keyboard,f->target);
            weston_keyboard_send_key(keyboard,&now,42,WL_KEYBOARD_KEY_STATE_PRESSED);
            weston_keyboard_send_key(keyboard,&now,42,WL_KEYBOARD_KEY_STATE_RELEASED);
            f->ui_sent=1;break;
        }
    }

    struct weston_geometry geometry={0};struct weston_size min={0},max={0};
    if(desktop){geometry=weston_desktop_surface_get_geometry(desktop);min=weston_desktop_surface_get_min_size(desktop);max=weston_desktop_surface_get_max_size(desktop);}
    const char *close=getenv("FLEX_WESTON_WINDOW_CLOSE");
    if(desktop && mapped && close && !access(close,F_OK)){unlink(close);weston_desktop_surface_close(desktop);f->closes++;}
    const char *path=getenv("FLEX_WESTON_WINDOW_REPORT");if(path){
        char temporary[4096];snprintf(temporary,sizeof temporary,"%s.tmp",path);FILE *out=fopen(temporary,"w");
        if(out){
            const pixman_box32_t empty = {0,0,0,0};
            const pixman_box32_t *opaque = f->target ? pixman_region32_extents(&f->target->opaque) : &empty;
            const pixman_box32_t bounds = {0,0,geometry.width,geometry.height};
            const int full_opaque = f->target && geometry.width > 0 && geometry.height > 0 &&
                pixman_region32_contains_rectangle(&f->target->opaque, &bounds) == PIXMAN_REGION_IN;
            /* Titles are controlled test constants without quotes or slashes. */
            fprintf(out,"{\"mapped\":%s,\"listed\":%s,\"layer\":%ld,\"width\":%d,\"height\":%d,\"title\":\"%s\",\"app_id\":\"%s\",\"maximized\":%s,\"fullscreen\":%s,\"min_width\":%d,\"min_height\":%d,\"max_width\":%d,\"max_height\":%d,\"minimize_requests\":%u,\"close_requests\":%u,\"maps\":%u,\"unmaps\":%u,\"buffer_attaches\":%u,\"requested_min_width\":%d,\"requested_min_height\":%d,\"requested_max_width\":%d,\"requested_max_height\":%d",mapped?"true":"false",listed?"true":"false",layer,geometry.width,geometry.height,title?title:"",id?id:"",desktop&&weston_desktop_surface_get_maximized(desktop)?"true":"false",desktop&&weston_desktop_surface_get_fullscreen(desktop)?"true":"false",min.width,min.height,max.width,max.height,f->minimizes,f->closes,f->maps,f->unmaps,f->attaches,f->req_min_w,f->req_min_h,f->req_max_w,f->req_max_h);
            fprintf(out,",\"opaque\":[%d,%d,%d,%d],\"full_opaque\":%s}\n",opaque->x1,opaque->y1,opaque->x2,opaque->y2,full_opaque?"true":"false");
            fclose(out);rename(temporary,path);
        }
    }
    wl_event_source_timer_update(f->timer,20);return 0;
}
static void destroyed(struct wl_listener *listener,void *data){
    (void)data;struct fixture *f=wl_container_of(listener,f,destroy);wl_event_source_remove(f->timer);wl_protocol_logger_destroy(f->logger);if(f->target)wl_list_remove(&f->target_destroy.link);wl_list_remove(&f->destroy.link);free(f);
}
__attribute__((visibility("default")))
int wet_module_init(struct weston_compositor *compositor,int *argc,char *argv[]){
    (void)argc;(void)argv;struct fixture *f=calloc(1,sizeof *f);if(!f)return -1;f->compositor=compositor;f->destroy.notify=destroyed;
    f->timer=wl_event_loop_add_timer(wl_display_get_event_loop(compositor->wl_display),step,f);f->logger=wl_display_add_protocol_logger(compositor->wl_display,protocol,f);
    if(!f->timer || !f->logger){if(f->timer)wl_event_source_remove(f->timer);if(f->logger)wl_protocol_logger_destroy(f->logger);free(f);return -1;}wl_signal_add(&compositor->destroy_signal,&f->destroy);wl_event_source_timer_update(f->timer,20);return 0;
}
