// Test/benchmark oracle only. Never linked into the Flexscript image library.
#include <gdk-pixbuf/gdk-pixbuf.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct {uint64_t w,h,stride;unsigned char *pixels;uint64_t bytes,alpha;GdkPixbuf *owner;} Raster;
typedef struct {unsigned char *data;uint64_t n,w,h,quality;} Encoded;
static void size_ready(GdkPixbufLoader *loader,int w,int h,void *bad) {
    if(w<1 || h<1 || (uint64_t)w*h>40000000){*(int *)bad=1;gdk_pixbuf_loader_set_size(loader,1,1);}
}
static GdkPixbuf *decode(const unsigned char *data,size_t n) {
    GdkPixbufLoader *loader=gdk_pixbuf_loader_new();GError *error=NULL;int bad=0;
    g_signal_connect(loader,"size-prepared",G_CALLBACK(size_ready),&bad);
    int a=gdk_pixbuf_loader_write(loader,data,n,&error);
    if(error){g_error_free(error);error=NULL;}
    int b=gdk_pixbuf_loader_close(loader,&error);if(error)g_error_free(error);
    GdkPixbuf *image=NULL;if(a && b && !bad){image=gdk_pixbuf_loader_get_pixbuf(loader);if(image)g_object_ref(image);}
    g_object_unref(loader);return image;
}
static Raster *wrap(GdkPixbuf *image) {
    if(!image)return NULL;Raster *r=calloc(1,sizeof(*r));
    r->w=gdk_pixbuf_get_width(image);r->h=gdk_pixbuf_get_height(image);r->stride=r->w*4;r->bytes=r->stride*r->h;
    r->alpha=gdk_pixbuf_get_has_alpha(image);r->pixels=malloc(r->bytes);r->owner=image;
    const unsigned char *p=gdk_pixbuf_read_pixels(image);int channels=gdk_pixbuf_get_n_channels(image),stride=gdk_pixbuf_get_rowstride(image);
    for(size_t y=0;y<r->h;y++){unsigned char *d=r->pixels+y*r->stride;const unsigned char *s=p+y*stride;
        if(channels==4)memcpy(d,s,r->stride);else for(size_t x=0;x<r->w;x++){d[x*4]=s[x*3];d[x*4+1]=s[x*3+1];d[x*4+2]=s[x*3+2];d[x*4+3]=255;}}
    return r;
}
Raster *oracle_decode(const unsigned char *p,size_t n){return wrap(decode(p,n));}
Raster *oracle_resize(Raster *r,int w,int h){return wrap(gdk_pixbuf_scale_simple(r->owner,w,h,GDK_INTERP_BILINEAR));}
void oracle_free(Raster *r){if(r){g_object_unref(r->owner);free(r->pixels);free(r);}}
Encoded *oracle_encode(Raster *r,int quality){
    char q[8];g_snprintf(q,sizeof(q),"%d",quality);char *keys[]={"quality",NULL},*values[]={q,NULL};
    char *data=NULL;gsize n=0;GError *error=NULL;
    // Installed GDK 2.44's encoder produces grayscale from RGBA input. Supply
    // packed RGB explicitly, retaining colors and counting conversion time.
    GdkPixbuf *rgb=r->owner;
    if(gdk_pixbuf_get_has_alpha(rgb)){
        rgb=gdk_pixbuf_new(GDK_COLORSPACE_RGB,FALSE,8,r->w,r->h);
        const unsigned char *s=gdk_pixbuf_read_pixels(r->owner);unsigned char *d=gdk_pixbuf_get_pixels(rgb);
        int ss=gdk_pixbuf_get_rowstride(r->owner),ds=gdk_pixbuf_get_rowstride(rgb);
        for(size_t y=0;y<r->h;y++)for(size_t x=0;x<r->w;x++)memcpy(d+y*ds+x*3,s+y*ss+x*4,3);
    }
    int ok=gdk_pixbuf_save_to_bufferv(rgb,&data,&n,"jpeg",keys,values,&error);
    if(rgb!=r->owner)g_object_unref(rgb);
    if(!ok){if(error)g_error_free(error);return NULL;}
    Encoded *e=calloc(1,sizeof(*e));e->data=(unsigned char *)data;e->n=n;e->w=r->w;e->h=r->h;e->quality=quality;return e;
}
Encoded *oracle_preview(const unsigned char *p,size_t n,int side,size_t limit){
    GdkPixbuf *image=decode(p,n);if(!image)return NULL;GdkPixbuf *oriented=gdk_pixbuf_apply_embedded_orientation(image);g_object_unref(image);image=oriented;
    int w=gdk_pixbuf_get_width(image),h=gdk_pixbuf_get_height(image);
    if(w>side || h>side){int nw=side,nh=(int)((int64_t)h*side/w);if(h>w){nh=side;nw=(int)((int64_t)w*side/h);}if(nw<1)nw=1;if(nh<1)nh=1;
        GdkPixbuf *scaled=gdk_pixbuf_scale_simple(image,nw,nh,GDK_INTERP_BILINEAR);g_object_unref(image);image=scaled;}
    Raster r={.w=gdk_pixbuf_get_width(image),.h=gdk_pixbuf_get_height(image),.owner=image};
    int qualities[]={85,70,50};Encoded *e=NULL;
    for(int i=0;i<3;i++){e=oracle_encode(&r,qualities[i]);if(!e || e->n<=limit)break;g_free(e->data);free(e);e=NULL;}
    g_object_unref(image);return e;
}
void oracle_encoded_free(Encoded *e){if(e){g_free(e->data);free(e);}}
