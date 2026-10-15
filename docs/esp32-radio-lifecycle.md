# Original ESP32 radio lifecycle

The native Wi-Fi, Bluetooth-controller, BLE and GATT adapters support explicit
shutdown and reinitialization in their standalone original-ESP32 firmware
profiles. Use the same application SDK task that initialized the adapter.
These APIs reject interrupt context, reentrant calls, a different controlling
task and shutdown while a software-timer callback remains on the stack.

| API | Result |
| --- | --- |
| `esp_wifi_station_stop()` | Stop the station and cancel reconnect intent; retain configuration and runtime allocations for start. |
| `esp_wifi_station_start()` | Start an initialized, stopped station; call reconnect explicitly to join again. |
| `esp_wifi_station_deinit()` | Stop, deinitialize vendor Wi-Fi and supplicant, then release native radio resources. |
| `esp_bt_controller_deinit()` | Shut down a raw VHCI controller, release its PHY guard and transport resources. Reject an active BLE host. |
| `esp_ble_stop()` | Shut down the controller and release host storage, invalidating connection handles and exported views. Reject an active GATT adapter. |
| `esp_gatt_deinit()` | Release only the database when the BLE host has no connections, advertising or connection attempt. |
| `esp_gatt_stop()` | Shut down controller, host and database together, including active connections. |

Successful deinit/stop calls return zero and accept repetition after teardown.
Wi-Fi start/stop require an initialized station and otherwise return-19.
Context, ownership and busy errors return-16. A stopped station can be started
without rebuilding its runtime; a deinitialized station needs init again.
Controller/BLE initialization can also be repeated after successful teardown.
New BLE connections use fresh tokens across host restarts, including when the
controller reuses the same numerical HCI handle. Remote peers observe radio
shutdown through their ordinary disconnection/supervision behavior.

Initialization records completed vendor stages and attempts rollback on error.
If vendor stop/deinit fails, the adapter retains the resources required for a
retry instead of freeing live state. Wi-Fi returns the original initialization
error and records rollback failure in `esp_wifi_cleanup_error`; the raw
controller exposes `esp_bt_cleanup_error`. Retry the relevant deinit/stop API.
The pinned Bluetooth controller's deinit ABI is void; its return register is
not an error result.

Wi-Fi shutdown changes the link generation and cancels reconnect intent. Keep
polling the application IP stack so TCP/DNS consumers observe link loss. TLS,
HTTP, MQTT, IP and application storage are separate users: close/deinitialize
those layers in application order. Radio teardown never sweeps their memory.
A retained packet view or connection handle becomes invalid at shutdown.

## Resource ownership

Only allocations made through radio OSI callbacks carry a radio domain tag in
the shared SDK arena. Ordinary native application allocations and allocations
for TCP/IP, TLS and GATT do not inherit a tag. Tagged synchronization objects,
radio timer nodes and completed radio tasks are released only after the
vendor has stopped and its tasks have exited. Reaping a task also releases its
lazy thread semaphore. The facade explicitly releases its own buffers and
configuration; the last PHY user releases calibration/init buffers.

A software-timer worker is shared. If Wi-Fi created it and no application
timers remain, teardown deletes/reaps it. An existing worker and application
timers survive. A worker created for the radio also survives if application
timers subsequently acquired it; the application can call
`esp_sdk_timer_deinit()` after removing its last timer. That call rejects a
live timer list, a suspended callback or the worker calling it on itself.

IRQ teardown restores the radio's previous matrix routes, removes only its
own bindings and preserves unrelated handlers and CPU interrupt bits. Wi-Fi
interrupt masking routes its own source away from the shared CPU interrupt;
it does not mask the application's timer/GPIO handlers. Bluetooth rejects an
already occupied software interrupt or controller source before modifying ROM
controller memory. A second controller init also rejects before that reset.
Native bump-heap workspace for the IRQ table and routing records is retained
and reused; SDK radio allocations are reclaimable.

## Pinned vendor mutexes

The pinned Wi-Fi/WPA libraries retain three lazy mutex references after their
normal deinit: `s_wifi_api_lock`, `g_wifi_global_lock` and `eloop_data_lock`.
After every vendor task exits, the facade clears those references before
releasing the tagged mutex objects. Without this step the next Wi-Fi init can
follow a pointer into a freed block and stall.

The radio builder verifies the original archive checksum, then uses the
installed Xtensa `objcopy --globalize-symbol=eloop_data_lock` on a temporary
copy of the WPA archive. It exposes that one local object without changing
vendor code/data. The original archive remains untouched. `--objcopy PATH`
can select the tool explicitly; by default its path is derived from the
selected GNU `ld` path. The independent visibility oracle compares every
allocated ELF section in all111 archive members (2749 sections with the pinned
input); only the metadata in `eloop.c.obj` differs.

## Verification

`tests/esp32/sdk-task-reap.flex`, `sdk-radio-resources.flex`,
`wifi-lifecycle-failures.flex` and `ble-adapter-lifecycle.flex` run in the vendor
link/ABI suite. They cover exact SDK heap recovery, independent allocations,
IRQ/timer sharing, callbacks that yield, initialization allocation failures,
failed vendor stages, retained mutex references, teardown retries, active-link
host cleanup and stale-token rejection. C code is an independent ABI oracle.

`wifi-lifecycle.flex` and `bluetooth-lifecycle.flex` are physical radio probes.
They exercise four lifetimes, scan/HCI commands, double-init rejection, exact
SDK heap recovery, an application hardware-timer IRQ and shared software-timer
progress. The Bluetooth probe also exercises BLE/GATT ownership and shutdown.
The original board passes four Wi-Fi lifetimes (each with scan and a stop/start
before deinit) and four Bluetooth lifetimes (two raw VHCI, two BLE/GATT). Every
lifetime restores exact SDK free space and preserves application IRQ/timer
progress. Each completed physical probe restores the original full4MiB image,
verifies its checksum and resets the board. The ABI/vendor suite passes1220
checks; BLE1438 and GATT3965 independent wire cases plus24 core checks each,
and TLS84 checks also pass. Evidence and source snapshots are under
`build/esp32-goal-verification/radio-lifecycle/`; failed Wi-Fi/stale-HCI probes
are retained as controls and have their own verified restoration records.
Physical shutdown coverage is separate from independent-peer BLE connection,
ACL and GATT behavior, which remain open under T137/T138/T191.

This implementation does not supply simultaneous Wi-Fi/Bluetooth coexistence,
S3 radio lifecycle or BLE pairing/bonding. Those remain separate requirements.
