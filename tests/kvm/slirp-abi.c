#include <stddef.h>
#include <stdio.h>
#include <slirp/libslirp.h>

#define CHECK(value, expected) _Static_assert((value) == (expected), #value)
CHECK(sizeof(SlirpConfig), 192);
CHECK(sizeof(SlirpCb), 104);
CHECK(offsetof(SlirpConfig, version), 0);
CHECK(offsetof(SlirpConfig, restricted), 4);
CHECK(offsetof(SlirpConfig, in_enabled), 8);
CHECK(offsetof(SlirpConfig, vnetwork), 12);
CHECK(offsetof(SlirpConfig, vnetmask), 16);
CHECK(offsetof(SlirpConfig, vhost), 20);
CHECK(offsetof(SlirpConfig, in6_enabled), 24);
CHECK(offsetof(SlirpConfig, vdhcp_start), 96);
CHECK(offsetof(SlirpConfig, vnameserver), 100);
CHECK(offsetof(SlirpConfig, if_mtu), 136);
CHECK(offsetof(SlirpConfig, if_mru), 144);
CHECK(offsetof(SlirpConfig, disable_host_loopback), 152);
CHECK(offsetof(SlirpConfig, enable_emu), 153);
CHECK(offsetof(SlirpCb, send_packet), 0);
CHECK(offsetof(SlirpCb, guest_error), 8);
CHECK(offsetof(SlirpCb, clock_get_ns), 16);
CHECK(offsetof(SlirpCb, timer_new), 24);
CHECK(offsetof(SlirpCb, notify), 64);
CHECK(SLIRP_POLL_IN, 1);
CHECK(SLIRP_POLL_OUT, 2);
CHECK(SLIRP_POLL_PRI, 4);
CHECK(SLIRP_POLL_ERR, 8);
CHECK(SLIRP_POLL_HUP, 16);
int main(void) {
    puts("PASS: libslirp IPv4 configuration, callbacks and poll ABI");
    return 0;
}
