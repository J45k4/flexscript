/* Independent compositor-side test producer. Never linked into the GUI/app.
 * Weston 15 public API; load only into an explicitly private --fake-seat server.
 * Delivers protocol input, not physical-device or button-to-photon evidence. */
#include <stdlib.h>
#include <time.h>
#include <libweston/libweston.h>
struct fixture {
    struct weston_compositor *compositor;
    struct wl_event_source *timer;
    struct wl_listener destroy;
    struct wl_listener target_destroy;
    struct wl_resource *target_resource;
    unsigned stage;
    int cursor_lifecycle;
};
static void target_destroyed(struct wl_listener *listener,void *data) {
    (void)data;struct fixture *f=wl_container_of(listener,f,target_destroy);
    wl_list_remove(&f->target_destroy.link);f->target_resource=NULL;f->stage=0;
}
static int step(void *data) {
    struct fixture *f=data;
    struct weston_seat *seat;
    struct weston_view *view;
    struct weston_keyboard *keyboard=NULL;
    struct weston_pointer *pointer=NULL;
    wl_list_for_each(seat,&f->compositor->seat_list,link) {
        keyboard=weston_seat_get_keyboard(seat);pointer=weston_seat_get_pointer(seat);
        if (keyboard && pointer) break;
    }
    struct weston_view *target=NULL;
    wl_list_for_each(view,&f->compositor->view_list,link) {
        if (view->is_mapped && view->surface->resource && view->surface->width>600) {target=view;break;}
    }
    if (!target || !keyboard || !pointer) {wl_event_source_timer_update(f->timer,20);return 0;}
    if (target->surface->resource!=f->target_resource) {
        if (f->target_resource) wl_list_remove(&f->target_destroy.link);
        f->target_resource=target->surface->resource;f->stage=0;
        f->target_destroy.notify=target_destroyed;
        wl_resource_add_destroy_listener(f->target_resource,&f->target_destroy);
    }
    if (f->cursor_lifecycle) {
        /* Protocol producer: drop capabilities while the other device survives,
         * then remove the global. This deliberately does not emulate hardware. */
        struct wl_resource *resource;
        struct timespec now;clock_gettime(CLOCK_MONOTONIC,&now);
        unsigned stage=f->stage++;
        if(stage==0){weston_keyboard_set_focus(keyboard,target->surface);weston_pointer_set_focus(pointer,target);}
        if(stage==3)weston_keyboard_send_key(keyboard,&now,30,WL_KEYBOARD_KEY_STATE_PRESSED);
        if(stage==10 || stage==30){
            uint32_t caps=stage==10?WL_SEAT_CAPABILITY_POINTER:WL_SEAT_CAPABILITY_KEYBOARD;
            wl_resource_for_each(resource,&seat->base_resource_list)wl_seat_send_capabilities(resource,caps);
        }
        if(stage==13)weston_keyboard_send_key(keyboard,&now,30,WL_KEYBOARD_KEY_STATE_RELEASED);
        if(stage==15 || stage==35){
            wl_resource_for_each(resource,&seat->base_resource_list)wl_seat_send_capabilities(resource,WL_SEAT_CAPABILITY_POINTER|WL_SEAT_CAPABILITY_KEYBOARD);
        }
        if(stage==20)weston_pointer_set_focus(pointer,NULL);
        if(stage==25)weston_pointer_set_focus(pointer,target);
        if(stage==18 || stage==28){weston_pointer_send_button(pointer,&now,272,WL_POINTER_BUTTON_STATE_PRESSED);weston_pointer_send_frame(pointer);}
        if(stage==23 || stage==33){weston_pointer_send_button(pointer,&now,272,WL_POINTER_BUTTON_STATE_RELEASED);weston_pointer_send_frame(pointer);}
        if(stage==40)wl_global_remove(seat->global);
        wl_event_source_timer_update(f->timer,100);return 0;
    }
    if (f->stage>3) {wl_event_source_timer_update(f->timer,20);return 0;}
    struct timespec now;clock_gettime(CLOCK_MONOTONIC,&now);
    if (f->stage==0) {
        weston_keyboard_set_focus(keyboard,target->surface);
        weston_pointer_set_focus(pointer,target);
        weston_keyboard_send_modifiers(keyboard,wl_display_next_serial(f->compositor->wl_display),0,0,0,0);
    } else if (f->stage==1) {
        struct weston_pointer_motion_event event={.mask=WESTON_POINTER_MOTION_ABS,.time=now,.abs={.c={500,300}}};
        weston_pointer_move(pointer,&event);weston_pointer_send_motion(pointer,&now,&event);
        weston_pointer_send_frame(pointer);
        weston_keyboard_send_key(keyboard,&now,30,WL_KEYBOARD_KEY_STATE_PRESSED);
    } else if (f->stage==2) {
        weston_keyboard_send_key(keyboard,&now,30,WL_KEYBOARD_KEY_STATE_RELEASED);
        weston_pointer_send_button(pointer,&now,272,WL_POINTER_BUTTON_STATE_PRESSED);
        weston_pointer_send_frame(pointer);
    } else if (f->stage==3) {
        weston_pointer_send_button(pointer,&now,272,WL_POINTER_BUTTON_STATE_RELEASED);
        weston_pointer_send_axis_source(pointer,WL_POINTER_AXIS_SOURCE_WHEEL);
        struct weston_pointer_axis_event event={.axis=WL_POINTER_AXIS_VERTICAL_SCROLL,.value=10,.has_discrete=true,.discrete=1};
        weston_pointer_send_axis(pointer,&now,&event);weston_pointer_send_frame(pointer);
    }
    f->stage++;
    wl_event_source_timer_update(f->timer,100);
    return 0;
}
static void destroyed(struct wl_listener *listener,void *data) {
    (void)data;struct fixture *f=wl_container_of(listener,f,destroy);
    wl_event_source_remove(f->timer);if(f->target_resource)wl_list_remove(&f->target_destroy.link);wl_list_remove(&f->destroy.link);free(f);
}
__attribute__((visibility("default")))
int wet_module_init(struct weston_compositor *compositor,int *argc,char *argv[]) {
    (void)argc;(void)argv;struct fixture *f=calloc(1,sizeof *f);if(!f)return -1;
    f->compositor=compositor;f->destroy.notify=destroyed;f->cursor_lifecycle=getenv("FLEX_WESTON_CURSOR_LIFECYCLE")!=NULL;
    f->timer=wl_event_loop_add_timer(wl_display_get_event_loop(compositor->wl_display),step,f);
    if(!f->timer){free(f);return -1;}
    wl_signal_add(&compositor->destroy_signal,&f->destroy);wl_event_source_timer_update(f->timer,20);return 0;
}
