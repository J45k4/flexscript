#!/usr/bin/env python3
"""Build the native ARM64 Android demo using Flexscript, LLVM and Android SDK.

No Gradle, external Maven packages, NDK sysroot, or network downloads are needed.
Only the freestanding JNI bridge is compiled by Clang; the program object is
directly emitted by Flexscript. Signing uses a generated local development key.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import zipfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--sdk", type=Path, default=Path(os.environ.get("ANDROID_HOME", "/opt/android-sdk")))
    parser.add_argument("--java-home", type=Path)
    parser.add_argument("--source", type=Path, default=Path("examples/android/app.flex"))
    parser.add_argument("--out", type=Path, default=Path("build/android"))
    parser.add_argument("--build-tools", default="36.1.0")
    parser.add_argument("--api", default="36")
    args = parser.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    sdk = args.sdk.resolve()
    bt = sdk / "build-tools" / args.build_tools
    android_jar = sdk / "platforms" / ("android-" + args.api) / "android.jar"
    assert android_jar.is_file(), android_jar
    environment = os.environ.copy()
    if args.java_home:
        environment["JAVA_HOME"] = str(args.java_home.resolve())
        environment["PATH"] = str(args.java_home.resolve() / "bin") + os.pathsep + environment["PATH"]

    def run(command):
        subprocess.run([str(value) for value in command], env=environment, check=True)

    def java_tool(name):
        executable = shutil.which(name, path=environment["PATH"])
        assert executable, "Missing JDK tool: " + name
        return executable

    program = out / "program.o"
    bridge = out / "bridge.o"
    jit_host = out / "jit-host.o"
    jit_runtime = out / "jit-runtime.o"
    library = out / "libflexscript.so"
    run([args.compiler.resolve(), "--target", "android-arm64", args.source, "-o", program])
    run(["clang", "--target=aarch64-linux-android26", "-ffreestanding", "-fPIC", "-fno-stack-protector",
         "-fno-builtin", "-fvisibility=hidden", "-Wall", "-Wextra", "-Werror", "-O2", "-c",
         "examples/android/bridge.c", "-o", bridge])
    run(["clang", "--target=aarch64-linux-android26", "-ffreestanding", "-fPIC", "-fno-stack-protector",
         "-fno-builtin", "-fvisibility=hidden", "-Wall", "-Wextra", "-Werror", "-O2", "-c",
         "platform/android/jit-host.c", "-o", jit_host])
    run(["clang", "--target=aarch64-linux-android26", "-ffreestanding", "-fPIC", "-fno-stack-protector",
         "-fno-builtin", "-fvisibility=hidden", "-Wall", "-Wextra", "-Werror", "-O2", "-c",
         "platform/android/jit-runtime.c", "-o", jit_runtime])
    run(["ld.lld", "-shared", "-z", "defs", "-z", "relro", "-z", "now", "-z", "noexecstack",
         "-z", "max-page-size=16384", "--hash-style=both", "-soname", "libflexscript.so",
         bridge, jit_host, jit_runtime, program, "-o", library])
    classes = out / "classes"
    dex = out / "dex"
    classes.mkdir(exist_ok=True)
    dex.mkdir(exist_ok=True)
    run([java_tool("javac"), "-source", "8", "-target", "8", "-bootclasspath", android_jar,
         "-d", classes, "examples/android/MainActivity.java"])
    class_files = sorted(classes.rglob("*.class"))
    assert class_files, "javac produced no class files"
    run([bt / "d8", "--min-api", "26", "--lib", android_jar, "--output", dex, *class_files])
    unsigned = out / "unsigned.apk"
    run([bt / "aapt2", "link", "-I", android_jar, "--manifest", "examples/android/AndroidManifest.xml",
         "--version-code", "1", "--version-name", "0.0.1", "-o", unsigned])
    assets = out / "assets"
    run([sys.executable, "tests/arm64/jit_cases.py", "--out", assets])
    with zipfile.ZipFile(unsigned, "a", compression=zipfile.ZIP_STORED) as apk:
        apk.write(dex / "classes.dex", "classes.dex")
        apk.write(library, "lib/arm64-v8a/libflexscript.so")
        apk.write(assets / "jit-cases.bin", "assets/jit-cases.bin")
        apk.write(assets / "jit-cases.json", "assets/jit-cases.json")
    aligned = out / "aligned.apk"
    run([bt / "zipalign", "-f", "-P", "16", "4", unsigned, aligned])
    key = out / "development.keystore"
    if not key.exists():
        run([java_tool("keytool"), "-genkeypair", "-noprompt", "-keystore", key,
             "-storepass", "android", "-keypass", "android", "-alias", "development",
             "-dname", "CN=Flexscript Development", "-keyalg", "RSA", "-keysize", "2048", "-validity", "3650"])
    result = out / "flexscript-android.apk"
    run([bt / "apksigner", "sign", "--ks", key, "--ks-key-alias", "development",
         "--ks-pass", "pass:android", "--key-pass", "pass:android", "--out", result, aligned])
    run([bt / "apksigner", "verify", "--verbose", result])
    run([bt / "zipalign", "-c", "-P", "16", "4", result])
    metadata = {"apk": str(result), "sha256": hashlib.sha256(result.read_bytes()).hexdigest(),
                "source": str(args.source.resolve()), "abi": "arm64-v8a", "package": "org.flexscript.demo",
                "component": "org.flexscript.demo/.MainActivity", "min_api": 26,
                "native_program": "direct Flexscript ARM64 object; freestanding JNI bridge linked by LLD"}
    (out / "build.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(json.dumps(metadata, indent=2))


if __name__ == "__main__":
    main()
