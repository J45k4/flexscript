# Android ARM64 backend

`--target android-arm64` emits a position-independent ELF64 AArch64 relocatable
object. Link that object into an Android `arm64-v8a` shared library and package
the library in an APK. ARM64 instruction encoding is implemented in Flexscript;
it does not invoke LLVM to compile the Flexscript program.

```sh
flexscript compiler/main.flex -o build/flex-android
build/flex-android --target android-arm64 examples/android/app.flex -o build/app.o
```

This target shares integer code generation with `linux-arm64`. It supports
Flexscript, SetaScript, saved FIR, imports, explicit platform modules and source
frontends. The output is an object, not an executable or APK. Its mode is 0644.

## Native object boundary

Functions use the AAPCS64 integer calling convention. The program's `main` is
named `flexscript_main` in the object symbol table; that name is reserved in
Android source. A native host can call `main()` without arguments or pass two
64-bit words to `main(count, words)`. The Android demo uses the latter form.

Static data addresses use `R_AARCH64_ADR_PREL_PG_HI21` and
`R_AARCH64_ADD_ABS_LO12_NC` relocations against the local `.data` section symbol.
Literal addresses retain their identity as a compiler-owned IR operation until
lowering; ordinary integer constants are never guessed to be pointers. Internal
calls remain relative branches. Function definitions are hidden so the linker
cannot preempt an internal target. The object includes a non-executable-stack
note. Linking should produce no `DT_TEXTREL`.

`alloc` and raw `syscall` retain their Linux ARM64 semantics. The example verifies
anonymous allocation, zero-filled memory, unaligned 64-bit access and unmapping
inside Android. Android's process sandbox still governs available syscalls.
Android framework APIs need a host binding: raw syscall IDs do not provide
camera, activity, permission, storage-picker or other framework integration.
`ffi_call`, `ffi_call_i32` and `ffi_call_u32` can call trusted host-supplied
integer/pointer function addresses using AAPCS64. `ffi_open` and `ffi_symbol`
remain unsupported; Android library loading belongs to the host. Restricted
VM programs still cannot use raw FFI.

[Collie for Android](../apps/collie/android/README.md) embeds the shared
compiler, checked interpreter, provider protocol and FlexDB in a native chat
app. It includes ChatGPT auth.json import, native tool calling and an app-private
filesystem; its guest dispatcher currently uses the interpreter.

## Build the Android demo

Requirements: an existing Flexscript compiler, Clang with AArch64 support, LLD,
JDK 17 or a compatible JDK, Android SDK platform 36 and Build Tools 36.1.0.
The example needs no Gradle, Maven dependencies, NDK sysroot or downloads.
It also embeds the [ARM64 leaf JIT](android-jit.md) and its independent fixtures.
For larger applications calling Android native libraries, use an NDK toolchain
and link the generated object with your application's native host.

```sh
flexscript compiler/main.flex -o build/flex-android
python3 scripts/build-android.py --compiler build/flex-android \
  --sdk /opt/android-sdk \
  --java-home /home/teppo/.gradle/jdks/eclipse_adoptium-17-amd64-linux.2
```

Override `--java-home` and `--sdk` for your machine. `--source` selects a
Flexscript program implementing the demo's entry contract. `--out` selects the
artifact directory, defaulting to `build/android`. The script:

1. Compiles the Flexscript program directly to `program.o`.
2. Compiles a small freestanding C JNI bridge and links `libflexscript.so` with
   LLD, using 16-KiB segment alignment, RELRO and a non-executable stack.
3. Compiles the Java host, builds DEX and the Android manifest, and packages the
   `arm64-v8a` library and JIT test fixtures in the APK.
4. Aligns the APK and signs it using a generated **development-only** key in the
   output directory. The sample app is debuggable; this is not release signing.

The resulting `build/android/flexscript-android.apk` has package
`org.flexscript.demo`, minimum Android API 26, and target API 36. `build.json`
records the APK path, hash and ABI. The development key stays in the ignored
build directory and is reused for subsequent installs.

## Demo host interface

[The Flexscript program](../examples/android/app.flex) receives five words:

| Word | Meaning |
|---|---|
| 0 | Address of a writable RGBA8888 pixel buffer |
| 1 | Width in pixels |
| 2 | Height in pixels |
| 3 | Touch count |
| 4 | Buffer capacity in bytes |

The program validates the bounds, runs arithmetic/memory checks, updates a native
global frame counter, fills the pixels, and returns the result and counters in a
64-bit word. The [JNI bridge](../examples/android/bridge.c) obtains a Java direct
buffer through the standardized JNI function table and forwards the five words.
It has no libc dependency. The [Java host](../examples/android/MainActivity.java)
handles activity lifecycle, touch events and bitmap display. Each tap invokes
the compiled Flexscript program again. Status and framebuffer checksums are
saved in app-private `files/status.json` for the emulator tests.

The JIT fixtures run on a worker thread. The screen also displays the result
of a runtime-generated function and the number of passing JIT tests. Raw native
JIT results are saved in `files/jit-results.bin` for independent verification.

This is a minimal Android host for native Flexscript programs. The full FlexOS
shell, editor, application APIs and phone integrations remain additional work.

## Headless emulator verification

Use an Android device advertising `arm64-v8a` in `ro.product.cpu.abilist`.
On an x86-64 host, an SDK Google APIs image may provide ARM64 support through
Android's native bridge. The tests report the device's ABI list and bridge;
they never substitute an x86 library for the ARM64 library.

An example with an existing AVD:

```sh
/opt/android-sdk/emulator/emulator -avd Pixel_9_API_36 -read-only \
  -no-window -no-snapshot -no-boot-anim -no-audio -gpu swiftshader \
  -memory 2048 -cores 2 -port 5580
```

In another terminal, after boot completes:

```sh
python3 scripts/test-android.py --compiler build/flex-android \
  --apk build/android/flexscript-android.apk --serial emulator-5580
```

Omit `--serial` to run only host object/linking tests. These require QEMU user
emulation, Clang, LLD and `readelf`. With `--serial`, tests install the APK on
that specific device, launch it, check native result 42, send three taps, verify
distinct native framebuffer checksums and persistent globals, background/resume
the activity, cold-restart the process, and inspect logs and the installed ABI.
Screenshots, UI XML, logcat, package metadata and `report.json` are saved under
`build/android/test`. Tests do not start a graphical emulator window.

Initial verification used Android 16/API 36 on an x86-64 Google APIs emulator
with `libndk_translation.so`. It exercised an ARM64 APK through Android's native
translation layer. This is Android emulator proof; a physical phone and native
ARM64 Android CPU have not been tested.

References: [Android ABI packaging](https://developer.android.com/ndk/guides/abis),
[JNI function table](https://docs.oracle.com/en/java/javase/17/docs/specs/jni/functions.html),
[16-KiB page support](https://developer.android.com/guide/practices/page-sizes).
