/* Independent protocol producer for a PRIVATE Weston 15 test compositor.
 * Supplies preferred fractional scales and validates cursor-shape requests.
 * This is protocol correctness evidence, not a physical mixed-monitor test.
 * Never linked into or required by the application. */
#include <stdio.h>
#include <stdlib.h>
#include <libweston/libweston.h>
#include "fractional-server.h"
#include "cursor-server.h"
struct fixture {struct weston_compositor *compositor;struct wl_global *fractional,*cursor;struct wl_listener destroy;unsigned shapes,defaults,resizes,bad_serial,scales;};
struct sample {struct fixture *fixture;struct wl_resource *resource;struct wl_event_source *timer;unsigned phase;};
static void report(struct fixture *f){const char *path=getenv("FLEX_WESTON_DISPLAY_REPORT");if(!path)return;FILE *out=fopen(path,"w");if(!out)return;fprintf(out,"{\"shape_calls\":%u,\"defaults\":%u,\"resizes\":%u,\"bad_serial\":%u,\"scale_events\":%u}\n",f->shapes,f->defaults,f->resizes,f->bad_serial,f->scales);fclose(out);}
static void destroy_request(struct wl_client *client,struct wl_resource *resource){(void)client;wl_resource_destroy(resource);}
static int sample_step(void *data){struct sample *s=data;const unsigned scales[]={150,180,240,120};wp_fractional_scale_v1_send_preferred_scale(s->resource,scales[s->phase]);s->fixture->scales++;report(s->fixture);s->phase++;if(s->phase<4)wl_event_source_timer_update(s->timer,250);return 0;}
static void sample_destroy(struct wl_resource *resource){struct sample *s=wl_resource_get_user_data(resource);wl_event_source_remove(s->timer);free(s);}
static const struct wp_fractional_scale_v1_interface sample_impl={.destroy=destroy_request};
static void get_fractional(struct wl_client *client,struct wl_resource *manager,uint32_t id,struct wl_resource *surface){
    (void)surface;struct fixture *f=wl_resource_get_user_data(manager);struct sample *s=calloc(1,sizeof *s);if(!s){wl_client_post_no_memory(client);return;}s->fixture=f;s->resource=wl_resource_create(client,&wp_fractional_scale_v1_interface,1,id);if(!s->resource){free(s);wl_client_post_no_memory(client);return;}
    s->timer=wl_event_loop_add_timer(wl_display_get_event_loop(f->compositor->wl_display),sample_step,s);if(!s->timer){wl_resource_destroy(s->resource);free(s);wl_client_post_no_memory(client);return;}
    wl_resource_set_implementation(s->resource,&sample_impl,s,sample_destroy);wp_fractional_scale_v1_send_preferred_scale(s->resource,120);f->scales++;report(f);wl_event_source_timer_update(s->timer,500);
}
static const struct wp_fractional_scale_manager_v1_interface fractional_impl={.destroy=destroy_request,.get_fractional_scale=get_fractional};
static void bind_fractional(struct wl_client *client,void *data,uint32_t version,uint32_t id){struct wl_resource *resource=wl_resource_create(client,&wp_fractional_scale_manager_v1_interface,version,id);if(!resource){wl_client_post_no_memory(client);return;}wl_resource_set_implementation(resource,&fractional_impl,data,NULL);}
static void set_shape(struct wl_client *client,struct wl_resource *resource,uint32_t serial,uint32_t shape){
    (void)client;struct fixture *f=wl_resource_get_user_data(resource);struct weston_seat *seat;struct weston_pointer *pointer=NULL;wl_list_for_each(seat,&f->compositor->seat_list,link){pointer=weston_seat_get_pointer(seat);if(pointer)break;}
    if(!pointer || serial!=pointer->focus_serial){f->bad_serial++;}
    f->shapes++;if(shape==1)f->defaults++;else if(shape==26)f->resizes++;else wl_resource_post_error(resource,WP_CURSOR_SHAPE_DEVICE_V1_ERROR_INVALID_SHAPE,"Unexpected test shape");report(f);
}
static const struct wp_cursor_shape_device_v1_interface device_impl={.destroy=destroy_request,.set_shape=set_shape};
static void get_pointer(struct wl_client *client,struct wl_resource *manager,uint32_t id,struct wl_resource *pointer){
    (void)pointer;struct wl_resource *resource=wl_resource_create(client,&wp_cursor_shape_device_v1_interface,1,id);if(!resource){wl_client_post_no_memory(client);return;}wl_resource_set_implementation(resource,&device_impl,wl_resource_get_user_data(manager),NULL);
}
static void get_tablet(struct wl_client *client,struct wl_resource *manager,uint32_t id,struct wl_resource *tool){(void)client;(void)id;(void)tool;wl_resource_post_error(manager,0,"Tablet tools are outside this test fixture");}
static const struct wp_cursor_shape_manager_v1_interface cursor_impl={.destroy=destroy_request,.get_pointer=get_pointer,.get_tablet_tool_v2=get_tablet};
static void bind_cursor(struct wl_client *client,void *data,uint32_t version,uint32_t id){struct wl_resource *resource=wl_resource_create(client,&wp_cursor_shape_manager_v1_interface,version,id);if(!resource){wl_client_post_no_memory(client);return;}wl_resource_set_implementation(resource,&cursor_impl,data,NULL);}
static void fixture_destroy(struct wl_listener *listener,void *data){(void)data;struct fixture *f=wl_container_of(listener,f,destroy);report(f);wl_global_destroy(f->fractional);wl_global_destroy(f->cursor);wl_list_remove(&f->destroy.link);free(f);}
__attribute__((visibility("default")))
int wet_module_init(struct weston_compositor *compositor,int *argc,char *argv[]){
    (void)argc;(void)argv;struct fixture *f=calloc(1,sizeof *f);if(!f)return -1;f->compositor=compositor;f->fractional=wl_global_create(compositor->wl_display,&wp_fractional_scale_manager_v1_interface,1,f,bind_fractional);f->cursor=wl_global_create(compositor->wl_display,&wp_cursor_shape_manager_v1_interface,1,f,bind_cursor);if(!f->fractional || !f->cursor){if(f->fractional)wl_global_destroy(f->fractional);if(f->cursor)wl_global_destroy(f->cursor);free(f);return -1;}f->destroy.notify=fixture_destroy;wl_signal_add(&compositor->destroy_signal,&f->destroy);report(f);return 0;
}
