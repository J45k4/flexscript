#define _GNU_SOURCE
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl3.h>
#include <gbm.h>
#include <xf86drm.h>
#include <xf86drmMode.h>
#include <fcntl.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void stop(void) { for (;;) pause(); }
static void require(int ok, const char *what) {
    if (!ok) { fprintf(stderr, "FAIL: Mesa %s (EGL %#x, GL %#x)\n", what, eglGetError(), glGetError()); stop(); }
}
static GLuint shader(GLenum type, const char *source) {
    GLuint object = glCreateShader(type);
    glShaderSource(object, 1, &source, NULL);
    glCompileShader(object);
    GLint ok = 0;
    glGetShaderiv(object, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char log[2048]; GLsizei n = 0;
        glGetShaderInfoLog(object, sizeof log, &n, log);
        fprintf(stderr, "Shader log: %.*s\n", n, log);
    }
    require(ok, "shader compilation");
    return object;
}
static uint32_t property(int fd, uint32_t object, uint32_t type, const char *name, uint64_t *value) {
    drmModeObjectProperties *properties = drmModeObjectGetProperties(fd, object, type);
    require(properties != NULL, "DRM object properties");
    uint32_t id = 0;
    for (uint32_t i = 0; i < properties->count_props; ++i) {
        drmModePropertyRes *p = drmModeGetProperty(fd, properties->props[i]);
        require(p != NULL, "DRM property description");
        if (!strcmp(p->name, name)) { id = p->prop_id; if (value) *value = properties->prop_values[i]; }
        drmModeFreeProperty(p);
    }
    drmModeFreeObjectProperties(properties);
    require(id != 0, name);
    return id;
}
static void add_property(drmModeAtomicReq *request, int fd, uint32_t object, uint32_t type, const char *name, uint64_t value) {
    require(drmModeAtomicAddProperty(request, object, property(fd, object, type, name, NULL), value) >= 0, "atomic property append");
}
static uint32_t framebuffer(int fd, struct gbm_bo *bo) {
    int dma = gbm_bo_get_fd(bo); require(dma >= 0, "scanout PRIME export");
    uint32_t handles[4] = {0}, pitches[4] = {gbm_bo_get_stride(bo)}, offsets[4] = {0}, fb = 0;
    require(drmPrimeFDToHandle(fd, dma, handles) == 0, "primary-node PRIME import");
    close(dma);
    require(drmModeAddFB2(fd, gbm_bo_get_width(bo), gbm_bo_get_height(bo), GBM_FORMAT_XRGB8888, handles, pitches, offsets, &fb, 0) == 0, "rendered scanout framebuffer");
    return fb;
}
static void flipped(int fd, unsigned sequence, unsigned seconds, unsigned microseconds, void *data) {
    (void)fd; (void)sequence; (void)seconds; (void)microseconds;
    *(int *)data = 1;
}
static int primary_node(void) {
    int fd = -1;
    for (unsigned i = 0; i < 2; ++i) {
        char path[32]; snprintf(path, sizeof path, "/dev/dri/card%u", i);
        int candidate = open(path, O_RDWR | O_CLOEXEC);
        if (candidate < 0) continue;
        drmVersion *version = drmGetVersion(candidate);
        int matches = version && version->name_len == 10 && !memcmp(version->name, "virtio_gpu", 10);
        if (version) drmFreeVersion(version);
        if (matches) { fd = candidate; break; }
        close(candidate);
    }
    require(fd >= 0, "virtio GPU primary node");
    return fd;
}
static void scanout(int fd, EGLDisplay display, EGLSurface surface, struct gbm_surface *gbm_surface, struct gbm_bo *front) {
    require(drmSetClientCap(fd, DRM_CLIENT_CAP_UNIVERSAL_PLANES, 1) == 0 && drmSetClientCap(fd, DRM_CLIENT_CAP_ATOMIC, 1) == 0, "atomic DRM capabilities");
    require(drmIsMaster(fd) == 1 || drmSetMaster(fd) == 0, "DRM master");
    drmModeRes *resources = drmModeGetResources(fd);
    require(resources && resources->count_crtcs == 1 && resources->count_connectors == 1, "atomic scanout topology");
    uint32_t crtc = resources->crtcs[0], connector = resources->connectors[0];
    drmModeConnector *connection = drmModeGetConnector(fd, connector);
    require(connection && connection->connection == DRM_MODE_CONNECTED, "connected scanout");
    drmModeModeInfo *mode = NULL;
    for (int i = 0; i < connection->count_modes; ++i)
        if (connection->modes[i].hdisplay == 1024 && connection->modes[i].vdisplay == 768) mode = &connection->modes[i];
    require(mode != NULL, "1024x768 atomic mode");
    drmModePlaneRes *planes = drmModeGetPlaneResources(fd);
    require(planes != NULL, "DRM planes");
    uint32_t plane = 0;
    for (uint32_t i = 0; i < planes->count_planes; ++i) {
        drmModePlane *p = drmModeGetPlane(fd, planes->planes[i]);
        require(p != NULL, "DRM plane description");
        uint64_t type = 0; property(fd, p->plane_id, DRM_MODE_OBJECT_PLANE, "type", &type);
        if ((p->possible_crtcs & 1) && type == DRM_PLANE_TYPE_PRIMARY) plane = p->plane_id;
        drmModeFreePlane(p);
    }
    require(plane != 0, "primary scanout plane");
    uint32_t blob = 0, first = framebuffer(fd, front);
    require(drmModeCreatePropertyBlob(fd, mode, sizeof *mode, &blob) == 0, "mode property blob");
    drmModeAtomicReq *request = drmModeAtomicAlloc(); require(request != NULL, "atomic request");
    add_property(request, fd, connector, DRM_MODE_OBJECT_CONNECTOR, "CRTC_ID", crtc);
    add_property(request, fd, crtc, DRM_MODE_OBJECT_CRTC, "MODE_ID", blob);
    add_property(request, fd, crtc, DRM_MODE_OBJECT_CRTC, "ACTIVE", 1);
    add_property(request, fd, plane, DRM_MODE_OBJECT_PLANE, "FB_ID", first);
    add_property(request, fd, plane, DRM_MODE_OBJECT_PLANE, "CRTC_ID", crtc);
    add_property(request, fd, plane, DRM_MODE_OBJECT_PLANE, "SRC_X", 0);
    add_property(request, fd, plane, DRM_MODE_OBJECT_PLANE, "SRC_Y", 0);
    add_property(request, fd, plane, DRM_MODE_OBJECT_PLANE, "SRC_W", 1024u << 16);
    add_property(request, fd, plane, DRM_MODE_OBJECT_PLANE, "SRC_H", 768u << 16);
    add_property(request, fd, plane, DRM_MODE_OBJECT_PLANE, "CRTC_X", 0);
    add_property(request, fd, plane, DRM_MODE_OBJECT_PLANE, "CRTC_Y", 0);
    add_property(request, fd, plane, DRM_MODE_OBJECT_PLANE, "CRTC_W", 1024);
    add_property(request, fd, plane, DRM_MODE_OBJECT_PLANE, "CRTC_H", 768);
    require(drmModeAtomicCommit(fd, request, DRM_MODE_ATOMIC_TEST_ONLY | DRM_MODE_ATOMIC_ALLOW_MODESET, NULL) == 0, "atomic test-only modeset");
    require(drmModeAtomicCommit(fd, request, DRM_MODE_ATOMIC_ALLOW_MODESET, NULL) == 0, "atomic modeset");
    drmModeAtomicFree(request);
    puts("PASS: rendered Mesa buffer imported into real Linux atomic scanout");
    glClearColor(0.f, 1.f, 0.f, 1.f); glClear(GL_COLOR_BUFFER_BIT); glFinish();
    require(glGetError() == GL_NO_ERROR && eglSwapBuffers(display, surface), "second rendered frame");
    struct gbm_bo *next = gbm_surface_lock_front_buffer(gbm_surface); require(next != NULL && next != front, "second GBM front buffer");
    uint32_t second = framebuffer(fd, next);
    request = drmModeAtomicAlloc(); require(request != NULL, "page-flip atomic request");
    add_property(request, fd, plane, DRM_MODE_OBJECT_PLANE, "FB_ID", second);
    int complete = 0;
    require(drmModeAtomicCommit(fd, request, DRM_MODE_ATOMIC_NONBLOCK | DRM_MODE_PAGE_FLIP_EVENT, &complete) == 0, "nonblocking atomic page flip");
    drmModeAtomicFree(request);
    drmEventContext events = { .version = 2, .page_flip_handler = flipped };
    struct pollfd event = { .fd = fd, .events = POLLIN };
    require(poll(&event, 1, 10000) == 1 && (event.revents & POLLIN) && drmHandleEvent(fd, &events) == 0 && complete, "page-flip completion event");
    drmModeCrtc *current = drmModeGetCrtc(fd, crtc);
    require(current && current->buffer_id == second && current->mode_valid && current->width == 1024 && current->height == 768, "page-flipped CRTC state");
    puts("PASS: real Linux atomic page flip, completion event and rendered CRTC state");
    // Keep both buffers and the DRM master alive while the host inspects output.
}
int main(int argc, char **argv) {
    int display_test = argc == 2 && !strcmp(argv[1], "--scanout");
    require(argc == 1 || display_test, "probe arguments");
    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);
    puts("Linux Mesa diagnostic started (official offline packages, software renderer)");
    int render = open("/dev/dri/renderD128", O_RDWR | O_CLOEXEC);
    require(render >= 0, "render node"); close(render);
    // kms_swrast allocates dumb buffers, which Linux permits on a primary node
    // rather than a render node. Keep the render-node existence check separate.
    int fd = primary_node();
    struct gbm_device *gbm = gbm_create_device(fd);
    require(gbm != NULL, "GBM device");
    printf("GBM backend: %s\n", gbm_device_get_backend_name(gbm));
    PFNEGLGETPLATFORMDISPLAYEXTPROC get_display = (void *)eglGetProcAddress("eglGetPlatformDisplayEXT");
    require(get_display != NULL, "platform display API");
    EGLDisplay display = get_display(EGL_PLATFORM_GBM_KHR, gbm, NULL);
    require(display != EGL_NO_DISPLAY, "GBM EGL display");
    EGLint major = 0, minor = 0;
    require(eglInitialize(display, &major, &minor), "EGL initialization");
    printf("EGL version: %d.%d; vendor: %s\n", major, minor, eglQueryString(display, EGL_VENDOR));
    require(eglBindAPI(EGL_OPENGL_ES_API), "OpenGL ES API");
    const EGLint attributes[] = {
        EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT_KHR,
        EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8,
        EGL_ALPHA_SIZE, 0, EGL_NONE
    };
    EGLConfig config = NULL; EGLint count = 0;
    require(eglChooseConfig(display, attributes, NULL, 0, &count) && count > 0 && count <= 4096, "ES3 window configurations");
    EGLConfig *configs = calloc((size_t)count, sizeof *configs);
    require(configs != NULL, "configuration allocation");
    require(eglChooseConfig(display, attributes, configs, count, &count), "ES3 window configuration enumeration");
    EGLint format = 0;
    for (EGLint i = 0; i < count; ++i) {
        require(eglGetConfigAttrib(display, configs[i], EGL_NATIVE_VISUAL_ID, &format), "native visual format");
        if (format == GBM_FORMAT_XRGB8888) { config = configs[i]; break; }
    }
    free(configs);
    require(config != NULL, "matching GBM/EGL format");
    printf("EGL native format: %#x (XRGB8888)\n", format);
    const EGLint context_attributes[] = { EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE };
    EGLContext context = eglCreateContext(display, config, EGL_NO_CONTEXT, context_attributes);
    require(context != EGL_NO_CONTEXT, "ES3 context");
    int width = display_test ? 1024 : 64, height = display_test ? 768 : 64;
    struct gbm_surface *gbm_surface = gbm_surface_create(gbm, width, height, GBM_FORMAT_XRGB8888, GBM_BO_USE_RENDERING | GBM_BO_USE_SCANOUT);
    require(gbm_surface != NULL, "GBM rendering surface");
    EGLSurface surface = eglCreateWindowSurface(display, config, (EGLNativeWindowType)gbm_surface, NULL);
    require(surface != EGL_NO_SURFACE, "EGL window surface");
    require(eglMakeCurrent(display, surface, surface, context), "current context");
    printf("GL version: %s\nRenderer: %s\n", glGetString(GL_VERSION), glGetString(GL_RENDERER));
    const char *vertex_source = "#version 300 es\nconst vec2 p[3]=vec2[3](vec2(-1.,-1.),vec2(3.,-1.),vec2(-1.,3.));void main(){gl_Position=vec4(p[gl_VertexID],0.,1.);}";
    const char *fragment_source = "#version 300 es\nprecision highp float;out vec4 color;void main(){color=vec4(1.,0.,0.,1.);}";
    GLuint vertex = shader(GL_VERTEX_SHADER, vertex_source);
    GLuint fragment = shader(GL_FRAGMENT_SHADER, fragment_source);
    GLuint program = glCreateProgram();
    glAttachShader(program, vertex); glAttachShader(program, fragment); glLinkProgram(program);
    GLint linked = 0; glGetProgramiv(program, GL_LINK_STATUS, &linked);
    require(linked, "program linking");
    glUseProgram(program); glViewport(0, 0, width, height);
    glClearColor(0.f, 0.f, 1.f, 1.f); glClear(GL_COLOR_BUFFER_BIT);
    glDrawArrays(GL_TRIANGLES, 0, 3); glFinish();
    unsigned char pixel[4] = {0};
    glReadPixels(32, 32, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
    printf("Shader pixel: %u %u %u %u\n", pixel[0], pixel[1], pixel[2], pixel[3]);
    require(glGetError() == GL_NO_ERROR && pixel[0] == 255 && pixel[1] == 0 && pixel[2] == 0 && pixel[3] == 255, "ES3 shader pixel readback");
    require(eglSwapBuffers(display, surface), "buffer swap");
    struct gbm_bo *front = gbm_surface_lock_front_buffer(gbm_surface);
    require(front != NULL, "GBM front buffer");
    int dma = gbm_bo_get_fd(front);
    require(dma >= 0, "rendered buffer PRIME export");
    close(dma);
    puts("PASS: official Mesa GBM/EGL, ES3 shaders, pixel readback and rendered PRIME buffer");
    if (display_test) scanout(fd, display, surface, gbm_surface, front);
    stop();
}
