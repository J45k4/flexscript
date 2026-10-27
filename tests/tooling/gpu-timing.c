/* Independent driver oracle only, never application/build implementation. */
#define GL_GLEXT_PROTOTYPES
#include <GL/gl.h>
#include <GL/glext.h>
#include <stdint.h>
int oracle_timer_read(unsigned start, unsigned end, uint64_t *out) {
    GLuint available = 0;
    glGetQueryObjectuiv(end, GL_QUERY_RESULT_AVAILABLE, &available);
    if (!available || glGetError() != GL_NO_ERROR) return 0;
    glGetQueryObjectui64v(start, GL_QUERY_RESULT, &out[0]);
    glGetQueryObjectui64v(end, GL_QUERY_RESULT, &out[1]);
    return glGetError() == GL_NO_ERROR;
}
int oracle_timer_exists(unsigned query) { return glIsQuery(query) == GL_TRUE; }
