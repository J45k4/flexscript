/* Freestanding Android host. The compiler/checked VM/provider/database are
 * compiled from shared Flexscript sources; no libc, shell or child process. */
typedef unsigned long U;
typedef unsigned char B;
extern long collie_android_entry(long, long, long, long);
extern long collie_android_db_frame(long, long);
extern long collie_android_db_wire(void);
extern long collie_android_cleanup(void);
static long raw(long n, long a, long b, long c, long d, long e, long f) {
    register long x8 __asm__("x8") = n, x0 __asm__("x0") = a, x1 __asm__("x1") = b,
                     x2 __asm__("x2") = c, x3 __asm__("x3") = d, x4 __asm__("x4") = e,
                     x5 __asm__("x5") = f;
    __asm__ volatile("svc #0"
                     : "+r"(x0)
                     : "r"(x8), "r"(x1), "r"(x2), "r"(x3), "r"(x4), "r"(x5)
                     : "memory", "cc");
    return x0;
}
static long length(const char *s) {
    long n = 0;
    if (s)
        while (s[n])
            n++;
    return n;
}
static void copy(void *d, const void *s, long n) {
    B *a = d;
    const B *b = s;
    while (n-- > 0)
        *a++ = *b++;
}
static void zero(void *d, long n) {
    B *a = d;
    while (n-- > 0)
        *a++ = 0;
}
static int equal(const char *a, const char *b) {
    while (*a && *a == *b) {
        a++;
        b++;
    }
    return *a == *b;
}
static long now(void) {
    long t[2];
    if (raw(113, 1, (long)t, 0, 0, 0, 0) < 0)
        return 0;
    return t[0] * 1000 + t[1] / 1000000;
}
static int cancelled;
static long checkpoint[13];
__attribute__((returns_twice)) long ca_checkpoint(long *);
__attribute__((noreturn)) void ca_abort(long *);
__asm__(".text\n.hidden ca_checkpoint\n.type ca_checkpoint,%function\nca_checkpoint:\n"
        "stp x19,x20,[x0]\nstp x21,x22,[x0,#16]\nstp x23,x24,[x0,#32]\nstp x25,x26,[x0,#48]\nstp "
        "x27,x28,[x0,#64]\nstp x29,x30,[x0,#80]\nmov x1,sp\nstr x1,[x0,#96]\nmov x0,#0\nret\n"
        ".hidden ca_abort\n.type ca_abort,%function\nca_abort:\n"
        "ldp x19,x20,[x0]\nldp x21,x22,[x0,#16]\nldp x23,x24,[x0,#32]\nldp x25,x26,[x0,#48]\nldp "
        "x27,x28,[x0,#64]\nldp x29,x30,[x0,#80]\nldr x1,[x0,#96]\nmov sp,x1\nmov x0,#1\nret\n");
#define MAX_MAPS 16384
#define CAPTURE 32768
static struct {
    long p, n;
} maps[MAX_MAPS];
static long maps_n, arena_bytes, deadline, operation, pool_at, pool_left;
/* JNI references are borrowed only for the duration of nativeCall on its thread. */
static void *jni_env, *jni_class;
static long network_calls, java_result_n;
static int cleaning, active, truncated, executing;
static const char *problem;
static char root[4096];
static int descriptors[512], descriptors_n;
static B output[2][CAPTURE + 1];
static long output_n[2], output_total;
static const char *sources[2];
static long positions[2];
static B frame[65552], reply[65552];
static long frame_n, reply_n, reply_at, calls, response_bytes;
static void die(const char *s) {
    problem = s;
    ca_abort(checkpoint);
}
static void tick(void) {
    if (!cleaning) {
        if (__atomic_load_n(&cancelled, __ATOMIC_RELAXED))
            die("Execution cancelled.");
        if (now() > deadline)
            die("Native operation exceeded its deadline.");
    }
}
static long allocate(long n) {
    if (n < 0 || n > 134217728)
        die("Native allocation exceeded its limit.");
    if (!n)
        n = 1;
    n = (n + 65535) & ~65535L;
    if (maps_n >= MAX_MAPS || arena_bytes + n > 268435456)
        die("Native memory limit exceeded.");
    long p = raw(222, 0, n, 3, 0x22, -1, 0);
    if (p < 0 && p >= -4095)
        die("Native allocation failed.");
    maps[maps_n].p = p;
    maps[maps_n++].n = n;
    arena_bytes += n;
    return p;
}
static long small_allocate(long n) {
    if (n < 0)
        die("Invalid native allocation.");
    if (n >= 4096)
        return allocate(n);
    n = (n + 15) & ~15L;
    if (!n)
        n = 16;
    if (n > pool_left) {
        pool_at = allocate(1048576);
        pool_left = 1048576;
    }
    long p = pool_at;
    pool_at += n;
    pool_left -= n;
    return p;
}
static long release(long p) {
    for (long i = 0; i < maps_n; i++)
        if (maps[i].p == p) {
            long n = maps[i].n;
            maps[i] = maps[--maps_n];
            arena_bytes -= n;
            return raw(215, p, n, 0, 0, 0, 0);
        }
    return -22;
}
static int track(long fd) {
    if (fd < 0)
        return (int)fd;
    if (descriptors_n == 512) {
        raw(57, fd, 0, 0, 0, 0, 0);
        die("Native file descriptor limit exceeded.");
    }
    descriptors[descriptors_n++] = (int)fd;
    return (int)fd;
}
static long close_fd(long fd) {
    for (int i = 0; i < descriptors_n; i++)
        if (descriptors[i] == fd) {
            descriptors[i] = descriptors[--descriptors_n];
            break;
        }
    return raw(57, fd, 0, 0, 0, 0, 0);
}
static int virtual_file(const char *s) {
    if (equal(s, "/guest/main.flex"))
        return 0;
    if (equal(s, "/guest/sdk.flex"))
        return 1;
    return -1;
}
static int trusted_path(const char *p) {
    long n = length(root);
    if (!n || length(p) < n || (!equal(root, "/") && p[n] != '/' && p[n] != 0))
        return 0;
    for (long i = 0; i < n; i++)
        if (p[i] != root[i])
            return 0;
    for (long i = 0; p[i]; i++)
        if (p[i] == '.' && (i == 0 || p[i - 1] == '/') &&
            (p[i + 1] == '/' || p[i + 1] == 0 ||
             (p[i + 1] == '.' && (p[i + 2] == '/' || p[i + 2] == 0))))
            return 0;
    return 1;
}
static long open_flags(long f) {
    return (f & ~0x3c000L) | ((f & 0x4000) ? 0x10000 : 0) | ((f & 0x8000) ? 0x20000 : 0) |
           ((f & 0x10000) ? 0x4000 : 0) | ((f & 0x20000) ? 0x8000 : 0);
}
static long host_open(const char *p, long flags, long mode) {
    int v = virtual_file(p);
    if (v >= 0) {
        positions[v] = 0;
        return 4096 + v;
    }
    if (!trusted_path(p))
        return -13;
    return track(raw(56, -100, (long)p, open_flags(flags) | 0x8000, mode, 0, 0));
}
static long stat_fd(long fd, long dest) {
    B *p = (B *)dest;
    zero(p, 144);
    if (fd >= 4096 && fd < 4098) {
        long *v = (long *)p;
        v[0] = 1;
        v[1] = fd;
        *(unsigned int *)(p + 24) = 0100600;
        v[6] = length(sources[fd - 4096]);
        v[7] = 4096;
        return 0;
    }
    B st[128];
    long r = raw(80, fd, (long)st, 0, 0, 0, 0);
    if (r < 0)
        return r;
    copy(p, st, 16);
    copy(p + 16, st + 20, 4);
    copy(p + 24, st + 16, 4);
    copy(p + 28, st + 24, 8);
    copy(p + 40, st + 32, 8);
    copy(p + 48, st + 48, 8);
    copy(p + 56, st + 56, 4);
    copy(p + 64, st + 64, 56);
    return 0;
}
static void capture(int fd, const B *p, long n) {
    if (fd < 1 || fd > 2)
        return;
    output_total += n;
    if (output_total > 1048576)
        die("Program output exceeded 1 MiB.");
    long remaining = CAPTURE - output_n[fd - 1];
    if (n > remaining) {
        n = remaining;
        truncated = 1;
    }
    copy(output[fd - 1] + output_n[fd - 1], p, n);
    output_n[fd - 1] += n;
    output[fd - 1][output_n[fd - 1]] = 0;
}
static void stderr_bytes(const B *p, long n) {
    for (long i = 0; i < n; i++) {
        if (frame_n || p[i] == 'C') {
            if (frame_n >= 65552)
                die("Oversized database request.");
            frame[frame_n++] = p[i];
            if (frame_n <= 8 && frame[frame_n - 1] != (B) "COLLIEDB"[frame_n - 1]) {
                capture(2, frame, frame_n);
                frame_n = 0;
            }
            if (frame_n >= 16) {
                long size = *(long *)(frame + 8);
                if (size < 0 || size > 65536)
                    die("Invalid database request size.");
                if (frame_n == size + 16) {
                    if (++calls > 1024)
                        die("Database call limit exceeded.");
                    long bytes = collie_android_db_frame((long)frame + 16, size);
                    long wire = collie_android_db_wire();
                    if (bytes < 0 || bytes > 65536 || response_bytes + bytes > 1048576)
                        die("Database response limit exceeded.");
                    response_bytes += bytes;
                    *(long *)reply = bytes;
                    copy(reply + 8, (void *)wire, bytes);
                    reply_at = 0;
                    reply_n = bytes + 8;
                    frame_n = 0;
                }
            }
        } else
            capture(2, p + i, 1);
    }
}
static long secure_parent(const char *path, char *leaf) {
    if (!path || length(path) > 1024)
        return -22;
    char base[4096];
    long n = length(root);
    if (n + 7 >= 4096)
        return -22;
    copy(base, root, n);
    copy(base + n, "/files", 7);
    long fd = track(raw(56, -100, (long)base, 0x4000 | 0x8000, 0, 0, 0));
    if (fd < 0)
        return fd;
    while (*path == '/')
        path++;
    if (!*path) {
        leaf[0] = 0;
        return fd;
    }
    for (;;) {
        long k = 0;
        while (path[k] && path[k] != '/') {
            if (k >= 255) {
                close_fd(fd);
                return -22;
            }
            leaf[k] = path[k];
            k++;
        }
        leaf[k] = 0;
        if (equal(leaf, ".") || equal(leaf, "..") || !k) {
            close_fd(fd);
            return -13;
        }
        path += k;
        while (*path == '/')
            path++;
        if (!*path)
            return fd;
        long next = track(raw(56, fd, (long)leaf, 0x4000 | 0x8000, 0, 0, 0));
        close_fd(fd);
        if (next < 0)
            return next;
        fd = next;
    }
}
static long quote(char *out, const B *s, long n) {
    long k = 0;
    out[k++] = '"';
    for (long i = 0; i < n; i++) {
        B c = s[i];
        if (c == '"' || c == '\\') {
            out[k++] = '\\';
            out[k++] = c;
        } else if (c < 32) {
            const char *h = "0123456789abcdef";
            out[k++] = '\\';
            out[k++] = 'u';
            out[k++] = '0';
            out[k++] = '0';
            out[k++] = h[c >> 4];
            out[k++] = h[c & 15];
        } else
            out[k++] = c;
    }
    out[k++] = '"';
    return k;
}
static long files(long op, long *a) {
    char leaf[256];
    long dir = secure_parent((char *)a[0], leaf);
    if (dir < 0)
        return dir;
    long r = -22;
    if (op == 2000 || op == 2004) {
        long fd = track(raw(56, dir, (long)leaf, 0x8000 | 0x800, 0, 0, 0));
        if (fd >= 0) {
            B st[128];
            r = raw(80, fd, (long)st, 0, 0, 0, 0);
            if (r >= 0 && (*(unsigned int *)(st + 16) & 0170000) == 0100000) {
                long bytes = op == 2004 ? *(long *)(st + 48) : a[2];
                if (bytes < 0 || (op == 2004 && bytes > 2097152)) {
                    close_fd(fd);close_fd(dir);return -27;
                }
                long p = allocate(bytes + 1);
                r = raw(67, fd, p, bytes, op == 2004 ? 0 : a[1], 0, 0);
                if (op == 2004 && r >= 0 && r != bytes) r = -5;
                if (r >= 0) {
                    *(long *)a[3] = r;
                    r = p;
                }
            } else
                r = -13;
            close_fd(fd);
        } else
            r = fd;
    } else if (op == 2001) {
        if (!leaf[0])
            r = -13;
        else {
            char tmp[64] = ".collie-write-";
            B random[16];
            if (raw(278, (long)random, 16, 0, 0, 0, 0) != 16) {
                close_fd(dir);
                return -5;
            }
            for (int i = 0; i < 16; i++) {
                tmp[13 + i * 2] = "0123456789abcdef"[random[i] >> 4];
                tmp[14 + i * 2] = "0123456789abcdef"[random[i] & 15];
            }
            tmp[45] = 0;
            long fd = track(raw(56, dir, (long)tmp, 0x8000 | 0x80 | 0x241, 0600, 0, 0));
            if (fd >= 0) {
                r = raw(64, fd, a[1], a[2], 0, 0, 0);
                if (r == a[2])
                    r = raw(82, fd, 0, 0, 0, 0, 0);
                else
                    r = -5;
                close_fd(fd);
                if (r >= 0)
                    r = raw(38, dir, (long)tmp, dir, (long)leaf, 0, 0);
                if (r >= 0)
                    r = raw(82, dir, 0, 0, 0, 0, 0);
                if (r < 0)
                    raw(35, dir, (long)tmp, 0, 0, 0, 0);
            } else
                r = fd;
        }
    } else if (op == 2002) {
        r = leaf[0] ? raw(34, dir, (long)leaf, 0700, 0, 0, 0) : -13;
    } else if (op == 2003) {
        long fd = leaf[0] ? track(raw(56, dir, (long)leaf, 0x4000 | 0x8000, 0, 0, 0)) : dir;
        if (fd >= 0) {
            char *out = (char *)allocate(200000);
            long k = 0, count = 0;
            out[k++] = '[';
            B data[8192];
            r = 0;
            for (;;) {
                long bytes = raw(61, fd, (long)data, 8192, 0, 0, 0);
                if (bytes < 0) {
                    r = bytes;
                    break;
                }
                if (!bytes)
                    break;
                long at = 0;
                while (at < bytes) {
                    unsigned short size = *(unsigned short *)(data + at + 16);
                    if (size < 20 || size > bytes - at) {
                        r = -5;
                        break;
                    }
                    char *name = (char *)data + at + 19;
                    long n = 0;
                    while (n < size - 19 && name[n])
                        n++;
                    if (n == size - 19) {
                        r = -5;
                        break;
                    }
                    if (!equal(name, ".") && !equal(name, "..")) {
                        if (++count > 128) {
                            r = -7;
                            break;
                        }
                        if (count > 1)
                            out[k++] = ',';
                        k += quote(out + k, (B *)name, n);
                    }
                    at += size;
                }
                if (r < 0)
                    break;
            }
            if (fd != dir)
                close_fd(fd);
            out[k++] = ']';
            out[k] = 0;
            if (r >= 0)
                r = (long)out;
        } else
            r = fd;
    }
    close_fd(dir);
    return r;
}
static long java_bytes(const char *method_name, long data, long size) {
    java_result_n = -1;
    if (!jni_env || !jni_class)
        return (long)"{\"error\":\"This operation requires the Android host.\"}";
    if (size < 0 || size > 2097152)
        return (long)"{\"error\":\"Invalid Android bridge payload length.\"}";
    char *out = (char *)allocate(2097153);
    void *env = jni_env;
    const void *const *t = *(const void *const **)env;
    /* Standard JNINativeInterface slots, verified against JDK jni.h. jsize is
     * 32 bits; jvalue[] elements are 8 bytes on ARM64. No native abort may
     * cross a Java frame: check cancellation only after the call returns. */
    void *method = ((void *(*)(void *, void *, const char *, const char *))t[113])(
        env, jni_class, method_name, "([B)[B");
    void *input = (void *)0, *result = (void *)0;
    long bytes = -1;
    if (method) input = ((void *(*)(void *, int))t[176])(env, (int)size);
    if (input) {
        ((void (*)(void *, void *, int, int, const B *))t[208])(env, input, 0, (int)size, (B *)data);
        void *arguments[1] = {input};
        long started = now();
        result = ((void *(*)(void *, void *, void *, const void *))t[116])(
            env, jni_class, method, arguments);
        deadline += now() - started;
        if (result) {
            bytes = ((int (*)(void *, void *))t[171])(env, result);
            if (bytes >= 0 && bytes <= 2097152)
                ((void (*)(void *, void *, int, int, B *))t[200])(env, result, 0, (int)bytes, (B *)out);
            else bytes = -1;
        }
    }
    if (((unsigned char (*)(void *))t[228])(env)) {
        ((void (*)(void *))t[17])(env);
        bytes = -1;
    }
    if (result) ((void (*)(void *, void *))t[23])(env, result);
    if (input) ((void (*)(void *, void *))t[23])(env, input);
    tick();
    if (bytes < 0) return (long)"{\"error\":\"Android host bridge failed.\"}";
    out[bytes] = 0;
    java_result_n = bytes;
    return (long)out;
}
static long network_get(long url, long size) {
    if (++network_calls > 4)
        return (long)"{\"error\":\"HTTPS request limit (4 per program) exceeded.\"}";
    if (!jni_env || !jni_class)
        return (long)"{\"error\":\"HTTPS requires the Android host.\"}";
    if (size < 1 || size > 4096)
        return (long)"{\"error\":\"Invalid HTTPS URL length.\"}";
    return java_bytes("vmHttpGet", url, size);
}
/* Read-only sibling archives; these calls never widen the normal workspace root. */
static int archive_id(const char *id) {
    long n = length(id);
    if (n < 1 || n > 80) return 0;
    for (long i = 0; i < n; i++) {
        char c = id[i];
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
              (c >= '0' && c <= '9') || c == '-')) return 0;
    }
    return 1;
}
static int archive_compare(const char *a, const char *b) {
    while (*a && *a == *b) { a++; b++; }
    return (unsigned char)*a - (unsigned char)*b;
}
static long archives(long op, long *a) {
    const char *id = (const char *)a[0];
    if ((!id[0] && op != 1020) || (id[0] && !archive_id(id))) return -22;
    char parent[4096];long end = length(root);
    while (end > 0 && root[end - 1] != '/') end--;
    if (end < 2 || end > 4095) return -13;
    copy(parent, root, end - 1);parent[end - 1] = 0;
    long dir = track(raw(56, -100, (long)parent, 0x4000 | 0x8000 | 0x80000, 0, 0, 0));
    if (dir < 0) return dir;
    if (op == 1020) {
        B data[8192];char best[81] = {0};long r = 0;
        for (;;) {
            tick();long n = raw(61, dir, (long)data, sizeof(data), 0, 0, 0);
            if (n == -4) continue;
            if (n < 0) { r = n;break; }
            if (!n) break;
            long at = 0;
            while (at < n) {
                unsigned short size = *(unsigned short *)(data + at + 16);
                if (size < 20 || size > n - at) { r = -5;break; }
                const char *name = (char *)data + at + 19;
                long count = 0;while (count < size - 19 && name[count]) count++;
                if (count == size - 19) { r = -5;break; }
                if (count <= 80 && archive_id(name) && archive_compare(name,id) > 0 &&
                    (!best[0] || archive_compare(name,best) < 0)) copy(best,name,count + 1);
                at += size;
            }
            if (r < 0) break;
        }
        close_fd(dir);
        if (r < 0) return r;
        long p = small_allocate(length(best) + 1);copy((void *)p,best,length(best) + 1);return p;
    }
    long child = track(raw(56, dir, (long)id, 0x4000 | 0x8000 | 0x80000, 0, 0, 0));
    close_fd(dir);if (child < 0) return child;
    long fd = track(raw(56, child, (long)"session.json", 0x8000 | 0x80000 | 0x800, 0, 0, 0));
    close_fd(child);if (fd < 0) return fd;
    B st[128];long r = raw(80,fd,(long)st,0,0,0,0);
    if (r < 0) { close_fd(fd);return r; }
    long bytes = *(long *)(st + 48);
    if ((*(unsigned int *)(st + 16) & 0170000) != 0100000 || bytes < 2 || bytes > 8388608) {
        close_fd(fd);return -7;
    }
    long p = allocate(bytes + 1), at = 0;
    while (at < bytes) {
        tick();r = raw(63,fd,p + at,bytes - at,0,0,0);
        if (r == -4) continue;
        if (r <= 0) { close_fd(fd);return -5; }
        at += r;
    }
    close_fd(fd);*(long *)a[1] = bytes;return p;
}
static long callback(long n, long *a) {
    tick();
    if (n == 1000)
        return small_allocate(a[0]);
    if (n == 1001) {
        sources[0] = (char *)a[0];
        sources[1] = (char *)a[1];
        return 0;
    }
    if (n == 1002)
        return 0;
    if (n == 1003) {
        executing = 1;
        return 0;
    }
    if (n == 1006) {
        if (a[0] == 2 && frame_n) {
            capture(2, frame, frame_n);
            frame_n = 0;
        }
        return (long)output[a[0] == 2 ? 1 : 0];
    }
    if (n == 1007)
        return output_n[a[0] == 2 ? 1 : 0];
    if (n == 1008)
        return truncated;
    if (n == 1020 || n == 1021)
        return archives(n,a);
    if (n == 1013 || n == 1014) {
        long *budgets = (long *)a[0];
        if (n == 1013) {
            if (frame_n || reply_at != reply_n) return -16;
            budgets[0] = calls; budgets[1] = response_bytes;
            budgets[2] = network_calls; budgets[3] = output_total;
        } else {
            if (budgets[0] < 0 || budgets[0] > 1024 || budgets[1] < 0 || budgets[1] > 1048576 ||
                budgets[2] < 0 || budgets[2] > 1048576 || budgets[3] < 0 || budgets[3] > 1048576) return -22;
            calls = budgets[0]; response_bytes = budgets[1];
            network_calls = budgets[2]; output_total = budgets[3];
        }
        return 0;
    }
    if (n == 1010 || n == 1011 || n == 1012) {
        const char *path = (char *)a[0];
        if (!trusted_path(path)) return -13;
        if (n == 1012) return raw(35, -100, (long)path, 0, 0, 0, 0);
        if (n == 1011) {
            long fd = host_open(path, 0x80000, 0);
            if (fd < 0) return fd;
            B stat[144];
            if (stat_fd(fd, (long)stat) < 0) { close_fd(fd); return -5; }
            long size = *(long *)(stat + 48);
            if (size < 160 || size > 16777216) { close_fd(fd); return -7; }
            B *data = (B *)allocate(size); long at = 0;
            while (at < size) { tick(); long r = raw(63, fd, (long)data + at, size - at, 0, 0, 0); if (r == -4) continue; if (r <= 0) { close_fd(fd); return -5; } at += r; }
            close_fd(fd); *(long *)a[1] = size; return (long)data;
        }
        if (a[2] < 160 || a[2] > 16777216) return -7;
        char temp[4096]; long len = length(path);
        if (len > 4088) return -22;
        copy(temp, path, len); copy(temp + len, ".tmp", 5);
        long fd = host_open(temp, 0xa0241, 0600);
        if (fd < 0) return fd;
        long at = 0, result = 0;
        while (at < a[2]) { tick(); long r = raw(64, fd, a[1] + at, a[2] - at, 0, 0, 0); if (r == -4) continue; if (r <= 0) { result = -5; break; } at += r; }
        if (!result) result = raw(82, fd, 0, 0, 0, 0, 0);
        close_fd(fd);
        if (!result) result = raw(38, -100, (long)temp, -100, (long)path, 0, 0);
        return result;
    }
    if (n >= 2000 && n <= 2004)
        return files(n, a);
    if (n == 3000)
        return network_get(a[0], a[1]);
    if (n == 3001)
        return java_bytes("vmViewImage", a[0], a[1]);
    if (n == 3002) {
        long data = java_bytes("vmImageBytes", a[0], a[1]);
        if (java_result_n < 0 || java_result_n > 524288) return -5;
        *(long *)a[2] = java_result_n; return data;
    }
    long x = a[0], y = a[1], z = a[2], d = a[3], e = a[4], f = a[5];
    if (n == 0) {
        if (x == 0) {
            long bytes = reply_n - reply_at;
            if (z < bytes)
                bytes = z;
            if (bytes < 0)
                return -22;
            copy((void *)y, reply + reply_at, bytes);
            reply_at += bytes;
            return bytes;
        }
        if (x >= 4096 && x < 4098) {
            long v = x - 4096, size = length(sources[v]) - positions[v];
            if (z < size)
                size = z;
            copy((void *)y, sources[v] + positions[v], size);
            positions[v] += size;
            return size;
        }
        return raw(63, x, y, z, 0, 0, 0);
    }
    if (n == 1) {
        if (x == 1) {
            capture(1, (B *)y, z);
            return z;
        }
        if (x == 2) {
            stderr_bytes((B *)y, z);
            return z;
        }
        return raw(64, x, y, z, 0, 0, 0);
    }
    if (n == 2)
        return host_open((char *)x, y, z);
    if (n == 3) {
        if (x >= 4096)
            return 0;
        return close_fd(x);
    }
    if (n == 4) {
        long fd = host_open((char *)x, 0, 0);
        if (fd < 0)
            return fd;
        long r = stat_fd(fd, y);
        if (fd < 4096)
            close_fd(fd);
        return r;
    }
    if (n == 7) {
        long ready = 0;
        for (long i = 0; i < y; i++) {
            B *p = (B *)x + i * 8;
            int fd = *(int *)p;
            unsigned short events = *(unsigned short *)(p + 4);
            unsigned short revents = 0;
            if ((fd == 1 || fd == 2) && (events & 4))
                revents = 4;
            if (fd == 0 && (events & 1) && reply_at < reply_n)
                revents |= 1;
            *(unsigned short *)(p + 6) = revents;
            if (revents)
                ready++;
        }
        return ready;
    }
    if (n == 5)
        return stat_fd(x, y);
    if (n == 8)
        return raw(62, x, y, z, 0, 0, 0);
    if (n == 9) {
        if (x)
            return -22;
        if (z & 4)
            return -13;
        if ((d & 0x20) || e == -1)
            return allocate(y);
        /* Read-only private snapshots avoid host page-size assumptions in FlexDB. */
        if (z != 1 || !(d & 2))
            return -13;
        long p = allocate(y), at = 0;
        while (at < y) {
            long got = raw(67, e, p + at, y - at, f + at, 0, 0);
            if (got < 0) {
                release(p);
                return got;
            }
            if (!got)
                break;
            at += got;
        }
        return p;
    }
    if (n == 10)
        return -13;
    if (n == 11)
        return release(x);
    if (n == 17)
        return raw(67, x, y, z, d, 0, 0);
    if (n == 18)
        return raw(68, x, y, z, d, 0, 0);
    if (n == 28)
        return 0;
    if (n == 39)
        return raw(172, 0, 0, 0, 0, 0, 0);
    if (n == 72)
        return raw(25, x, y, z, 0, 0, 0);
    if (n == 73)
        return raw(32, x, y, 0, 0, 0, 0);
    if (n == 74)
        return raw(82, x, 0, 0, 0, 0, 0);
    if (n == 77)
        return raw(46, x, y, 0, 0, 0, 0);
    if (n == 82) {
        if (!trusted_path((char *)x) || !trusted_path((char *)y))
            return -13;
        return raw(38, -100, x, -100, y, 0, 0);
    }
    if (n == 83) {
        if (!trusted_path((char *)x))
            return -13;
        return raw(34, -100, x, y, 0, 0, 0);
    }
    if (n == 84 || n == 87) {
        if (!trusted_path((char *)x))
            return -13;
        return raw(35, -100, x, n == 84 ? 512 : 0, 0, 0, 0);
    }
    if (n == 91)
        return raw(52, x, y, 0, 0, 0, 0);
    if (n == 217)
        return raw(61, x, y, z, 0, 0, 0);
    if (n == 228)
        return raw(113, x, y, 0, 0, 0, 0);
    if (n == 318)
        return raw(278, x, y, z, 0, 0, 0);
    if (n == 60 || n == 231) {
        die("Flexscript compiler rejected the program.");
    }
    return -38;
}
static long failure(char *out, long cap) {
    const char *start =
        operation == 3 && executing
            ? "{\"state\":\"error\",\"executed\":true,\"phase\":\"vm\",\"exit_code\":-1,\"stdout\":"
        : operation == 3 ? "{\"state\":\"error\",\"executed\":false,\"phase\":\"compile\",\"exit_"
                           "code\":-1,\"stdout\":"
                         : "{\"error\":";
    long k = length(start);
    copy(out, start, k);
    if (operation == 3) {
        k += quote(out + k, output[0], output_n[0]);
        const char *s = ",\"stderr\":";
        copy(out + k, s, length(s));
        k += length(s);
        char message[CAPTURE + 1024];
        long n = output_n[1];
        copy(message, output[1], n);
        if (n)
            message[n++] = '\n';
        long m = length(problem);
        copy(message + n, problem, m);
        n += m;
        k += quote(out + k, (B *)message, n);
    } else
        k += quote(out + k, (B *)problem, length(problem));
    out[k++] = '}';
    if (k >= cap)
        return -7;
    return k;
}
long collie_call(long op, const char *input, long size, char *out, long cap, const char *session) {
    if (active)
        return -16;
    if (!input || !out || !session || size < 0 || size > 8388608 || cap < 262144 ||
        length(session) > 4000)
        return -22;
    active = 1;
    operation = op;
    maps_n = arena_bytes = pool_at = pool_left = 0;
    descriptors_n = 0;
    output_n[0] = output_n[1] = 0;
    output_total = 0;
    frame_n = reply_n = reply_at = calls = response_bytes = 0;
    truncated = 0;
    executing = 0;
    network_calls = 0;
    cleaning = 0;
    problem = "Unknown native failure.";
    sources[0] = sources[1] = "";
    positions[0] = positions[1] = 0;
    copy(root, session, length(session) + 1);
    deadline = now() + 15000;
    long result = 0;
    if (!ca_checkpoint(checkpoint)) {
        char *text = (char *)allocate(size + 1);
        copy(text, input, size);
        long packet[6];
        long p = collie_android_entry(op, (long)text, (long)callback, (long)packet);
        long n = length((char *)p);
        if (n >= cap)
            die("Native reply exceeded its limit.");
        copy(out, (void *)p, n);
        result = n;
    } else
        result = failure(out, cap);
    cleaning = 1; /* Broker rollback is best effort; preserve the original observation. */
    if (!ca_checkpoint(checkpoint))
        collie_android_cleanup();
    while (descriptors_n)
        raw(57, descriptors[--descriptors_n], 0, 0, 0, 0, 0);
    while (maps_n) {
        maps_n--;
        raw(215, maps[maps_n].p, maps[maps_n].n, 0, 0, 0, 0);
    }
    active = 0;
    return result;
}
static void *address(void *env, void *buffer) {
    if (!buffer)
        return (void *)0;
    const void *const *t = *(const void *const **)env;
    return ((void *(*)(void *, void *))t[230])(env, buffer);
}
static long capacity(void *env, void *buffer) {
    if (!buffer)
        return -1;
    const void *const *t = *(const void *const **)env;
    return ((long (*)(void *, void *))t[231])(env, buffer);
}
__attribute__((visibility("default"))) long
Java_org_flexscript_collie_MainActivity_nativeCall(void *env, void *clazz, long op, void *input,
                                                   long size, void *output_buffer, void *session) {
    if (size > capacity(env, input) || capacity(env, session) < 1)
        return -22;
    const char *root_path = address(env, session);
    if (root_path[capacity(env, session) - 1])
        return -22;
    jni_env = env;
    jni_class = clazz;
    long result = collie_call(op, address(env, input), size, address(env, output_buffer),
                             capacity(env, output_buffer), root_path);
    jni_env = jni_class = (void *)0;
    return result;
}
__attribute__((visibility("default"))) void
Java_org_flexscript_collie_MainActivity_nativeCancel(void *env, void *clazz) {
    (void)env;
    (void)clazz;
    __atomic_store_n(&cancelled, 1, __ATOMIC_RELAXED);
}
__attribute__((visibility("default"))) void
Java_org_flexscript_collie_MainActivity_nativeBegin(void *env, void *clazz) {
    (void)env;
    (void)clazz;
    __atomic_store_n(&cancelled, 0, __ATOMIC_RELAXED);
}
