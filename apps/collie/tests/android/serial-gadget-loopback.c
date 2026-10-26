// Owned dummy-UDC fixture, not a production serial bridge or physical UART oracle.
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>
static volatile sig_atomic_t stopped;
static void stop(int sig) {
    (void)sig;
    stopped = 1;
}
static uint64_t now(void) {
    struct timespec t;
    if (clock_gettime(CLOCK_MONOTONIC, &t))
        return 0;
    return (uint64_t)t.tv_sec;
}
static int open_tty(const char *path) {
    int fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0)
        return -1;
    struct termios options;
    if (tcgetattr(fd, &options) < 0) {
        close(fd);
        return -1;
    }
    cfmakeraw(&options);
    options.c_cflag |= CLOCAL | CREAD;
    options.c_cflag &= ~HUPCL;
    if (tcsetattr(fd, TCSANOW, &options) < 0) {
        close(fd);
        return -1;
    }
    return fd;
}
int main(int argc, char **argv) {
    if (argc != 2) {
        fputs("usage: serial-loopback owned-ttyGS-number\n", stderr);
        return 1;
    }
    char *end;
    long port = strtol(argv[1], &end, 10);
    if (!*argv[1] || *end || port < 0 || port > 15)
        return 1;
    char path[32];
    snprintf(path, sizeof(path), "/dev/ttyGS%ld", port);
    int fd = open_tty(path);
    if (fd < 0) {
        perror("owned raw gadget tty");
        return 1;
    }
    if (tcflush(fd, TCIOFLUSH) < 0) {
        perror("initial fixture flush");
        close(fd);
        return 1;
    }
    signal(SIGTERM, stop);
    signal(SIGINT, stop);
    unsigned char *buffer = malloc(1048576);
    if (!buffer) {
        close(fd);
        return 1;
    }
    size_t used = 0, sent = 0;
    uint64_t input = 0, output = 0, in_hash = 14695981039346656037ULL, out_hash = in_hash,
             began = now(), end_time = began + 300;
    if (!began) {
        free(buffer);
        close(fd);
        return 1;
    }
    unsigned reopens = 0, break_set = 0, break_clear = 0;
    uint64_t break_time = 0;
    int error = 0;
    printf("READY owned-tty %ld pid %d\n", port, (int)getpid());
    fflush(stdout);
    while (!stopped) {
        uint64_t tick = now();
        if (!tick) {
            error = 1;
            break;
        }
        if (tick >= end_time)
            break;
        // A real tty break callback asks f_acm to enqueue a SERIAL_STATE interrupt
        // notification. Trigger only after the full binary exchange has settled.
        if (output == 32768 && !break_time)
            break_time = tick + 1;
        if (break_time && tick >= break_time && !break_set) {
            if (ioctl(fd, TIOCSBRK) < 0) {
                perror("fixture break on");
                error = 1;
                break;
            }
            break_set = 1;
            break_time = tick + 1;
        } else if (break_set && !break_clear && tick >= break_time) {
            if (ioctl(fd, TIOCCBRK) < 0) {
                perror("fixture break off");
                error = 1;
                break;
            }
            break_clear = 1;
        }
        struct pollfd p = {fd, (short)(POLLIN | (sent < used ? POLLOUT : 0)), 0};
        int ready = poll(&p, 1, 250);
        if (ready < 0) {
            if (errno == EINTR)
                continue;
            perror("tty poll");
            error = 1;
            break;
        }
        if (!ready)
            continue;
        if ((p.revents & POLLIN) && used < 1048576) {
            ssize_t n = read(fd, buffer + used, 1048576 - used);
            if (n > 0) {
                for (ssize_t i = 0; i < n; i++) {
                    in_hash ^= buffer[used + (size_t)i];
                    in_hash *= 1099511628211ULL;
                }
                used += (size_t)n;
                input += (uint64_t)n;
            } else if (n < 0 && errno != EAGAIN && errno != EINTR && errno != EIO) {
                perror("tty read");
                error = 1;
                break;
            }
        }
        if (sent < used) {
            ssize_t n = write(fd, buffer + sent, used - sent);
            if (n > 0) {
                for (ssize_t i = 0; i < n; i++) {
                    out_hash ^= buffer[sent + (size_t)i];
                    out_hash *= 1099511628211ULL;
                }
                sent += (size_t)n;
                output += (uint64_t)n;
            } else if (n < 0 && errno != EAGAIN && errno != EINTR && errno != EIO) {
                perror("tty write");
                error = 1;
                break;
            }
        }
        if (sent == used) {
            used = sent = 0;
        } else if (used == 1048576) {
            if (sent) {
                memmove(buffer, buffer + sent, used - sent);
                used -= sent;
                sent = 0;
            } else {
                fputs("bounded echo queue full\n", stderr);
                error = 1;
                break;
            }
        }
        if (p.revents & POLLHUP) {
            close(fd);
            fd = -1;
            do {
                struct timespec pause = {0, 10000000};
                nanosleep(&pause, NULL);
                fd = open_tty(path);
            } while (fd < 0 && !stopped && now() < end_time);
            if (fd < 0) {
                error = 1;
                break;
            }
            reopens++;
        }
    }
    printf("DONE input=%llu output=%llu input_hash=%016llx output_hash=%016llx pending=%zu "
           "error=%d reopens=%u break_set=%u break_clear=%u\n",
           (unsigned long long)input, (unsigned long long)output, (unsigned long long)in_hash,
           (unsigned long long)out_hash, used - sent, error, reopens, break_set, break_clear);
    free(buffer);
    close(fd);
    return error;
}
