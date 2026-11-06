#!/usr/bin/env python3
"""Build pinned OBS libraries, the native engine, app, and renamed HAL driver."""
import argparse
import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path

from bundle_libraries import bundle

ROOT = Path(__file__).resolve().parents[1]


def run(*args):
    print("+", " ".join(str(arg) for arg in args), flush=True)
    subprocess.run([str(arg) for arg in args], check=True, cwd=ROOT)


def find_one(directory, name):
    matches = [path for path in directory.rglob(name) if path.is_file() or path.is_dir()]
    if len(matches) != 1:
        raise RuntimeError(f"Expected one {name} in {directory}, found: {matches}")
    return matches[0]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--arch", choices=["arm64", "x86_64"], default="arm64")
    args = parser.parse_args()
    if platform.system() != "Darwin":
        raise SystemExit("This build requires a Mac with Xcode. Portable checks: make test")
    for tool in ["cmake", "xcodebuild", "xcrun", "codesign", "iconutil", "otool", "install_name_tool"]:
        if not shutil.which(tool):
            raise SystemExit(f"Missing {tool}; install Xcode and CMake, then select Xcode with xcode-select")
    sdk_version = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-platform-version"], text=True).strip()
    version = tuple(int(part) for part in sdk_version.split(".")[:2])
    if version < (26, 5):
        raise SystemExit(f"Pinned OBS 33.0.1 requires Xcode/macOS SDK 26.5 or later; selected SDK is {sdk_version}. Runtime deployment target remains macOS 13.")
    run(sys.executable, ROOT / "tools/fetch_sources.py")
    work = ROOT / ".build" / args.arch
    work.mkdir(parents=True, exist_ok=True)
    obs_source = ROOT / "third_party/obs-studio"
    obs_build = work / "obs"
    run("cmake", "--preset", "macos", "-S", obs_source, "-B", obs_build,
        f"-DCMAKE_OSX_ARCHITECTURES={args.arch}", "-DCMAKE_OSX_DEPLOYMENT_TARGET=13.0",
        "-DOBS_VERSION_OVERRIDE=33.0.1", "-DOBS_BUILD_NUMBER=1",
        "-DENABLE_FRONTEND=OFF", "-DENABLE_CORE_MODULES=OFF", "-DENABLE_SCRIPTING=OFF",
        "-DENABLE_BROWSER=OFF", "-DENABLE_TEST_INPUT=OFF", "-DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO")
    run("cmake", "--build", obs_build, "--config", "Release", "--target", "libobs", "libobs-metal", "--parallel")
    framework = find_one(obs_build, "libobs.framework")
    if not (framework / "Resources/default.effect").is_file():
        raise RuntimeError("Built libobs.framework is missing its runtime effects/resources")
    metal = find_one(obs_build, "libobs-metal.dylib")
    deps = obs_source / ".deps/obs-deps-2026-10-23-universal"
    if not (deps / "include").exists():
        raise RuntimeError(f"OBS dependency prefix not found: {deps}")
    native_build = work / "native"
    run("cmake", "-S", ROOT / "native", "-B", native_build, "-G", "Xcode",
        f"-DCMAKE_OSX_ARCHITECTURES={args.arch}", f"-DOBS_SOURCE={obs_source}",
        f"-DOBS_BUILD={obs_build}", f"-DOBS_FRAMEWORK={framework}", f"-DOBS_DEPS={deps}",
        "-DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO")
    run("cmake", "--build", native_build, "--config", "Release", "--parallel")
    bridge = find_one(native_build, "libMixerBridge.a")
    input_module = find_one(native_build, "MixerMacInput.so")

    dist = ROOT / "dist" / args.arch
    dist.mkdir(parents=True, exist_ok=True)
    app = dist / "Mac Mic Mixer.app"
    if app.exists():
        shutil.rmtree(app)
    for name in ["MacOS", "Frameworks", "PlugIns", "Resources"]:
        (app / "Contents" / name).mkdir(parents=True)
    shutil.copy2(ROOT / "app/Info.plist", app / "Contents/Info.plist")
    bundled_framework = app / "Contents/Frameworks/libobs.framework"
    shutil.copytree(framework, bundled_framework, symlinks=True)
    bundled_metal = app / "Contents/Frameworks/libobs-metal.dylib"
    shutil.copy2(metal, bundled_metal)
    bundled_module = app / "Contents/PlugIns/MixerMacInput.so"
    shutil.copy2(input_module, bundled_module)
    shutil.copytree(obs_source / "plugins/mac-capture/data", app / "Contents/Resources/mac-input")
    shutil.copy2(ROOT / "docs/使用说明.html", app / "Contents/Resources/使用说明.html")
    notices = app / "Contents/Resources/Licenses"
    notices.mkdir()
    for source, target in [(ROOT / "LICENSE", "MacMicMixer-GPL-3.0.txt"),
                           (ROOT / "THIRD_PARTY_NOTICES.md", "ThirdParty.md"),
                           (obs_source / "COPYING", "OBS-COPYING.txt"),
                           (ROOT / "third_party/BlackHole/LICENSE", "BlackHole-LICENSE.txt")]:
        shutil.copy2(source, notices / target)
    if (deps / "share/licenses").exists():
        shutil.copytree(deps / "share/licenses", notices / "obs-deps")
    shutil.copy2(ROOT / "third_party/sources.json", notices / "sources.json")
    sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
    executable = app / "Contents/MacOS/MacMicMixer"
    run("xcrun", "swiftc", "-O", "-swift-version", "5", "-parse-as-library",
        "-target", f"{args.arch}-apple-macosx13.0", "-sdk", sdk,
        "-import-objc-header", ROOT / "native/include/MixerBridge.h",
        *sorted((ROOT / "app").glob("*.swift")), bridge,
        "-F", framework.parent, "-framework", "libobs", "-lc++",
        "-framework", "AppKit", "-framework", "Foundation", "-framework", "AVFoundation",
        "-framework", "CoreAudio", "-framework", "AudioUnit", "-framework", "AudioToolbox",
        "-framework", "ServiceManagement", "-framework", "SwiftUI",
        "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks", "-o", executable)
    run("xcrun", "swift", ROOT / "tools/make_icon.swift", work / "Mixer.iconset")
    icon = app / "Contents/Resources/Mixer.icns"
    run("iconutil", "-c", "icns", work / "Mixer.iconset", "-o", icon)

    driver = dist / "MacMicMixer.driver"
    if driver.exists():
        shutil.rmtree(driver)
    (driver / "Contents/MacOS").mkdir(parents=True)
    (driver / "Contents/Resources").mkdir()
    shutil.copy2(ROOT / "native/driver/Info.plist", driver / "Contents/Info.plist")
    shutil.copy2(icon, driver / "Contents/Resources/Mixer.icns")
    shutil.copy2(ROOT / "third_party/BlackHole/LICENSE", driver / "Contents/Resources/LICENSE")
    run("xcrun", "clang", "-O2", "-arch", args.arch, "-isysroot", sdk,
        "-mmacosx-version-min=13.0", "-bundle", "-include", ROOT / "native/driver/DriverConfig.h",
        ROOT / "third_party/BlackHole/BlackHole/BlackHole.c", "-framework", "CoreAudio",
        "-framework", "CoreFoundation", "-framework", "Accelerate", "-o", driver / "Contents/MacOS/MacMicMixer")

    # Manual swiftc builds do not run Xcode's Embed Swift Standard Libraries
    # phase. Scan the app AND Metal library before resolving the Mach-O closure.
    run("xcrun", "swift-stdlib-tool", "--copy", "--platform", "macosx",
        "--scan-executable", executable, "--scan-folder", app / "Contents/Frameworks",
        "--scan-folder", app / "Contents/PlugIns", "--destination", app / "Contents/Frameworks")
    swift_compiler = Path(subprocess.check_output(["xcrun", "--find", "swiftc"], text=True).strip())
    swift_runtime = swift_compiler.parent.parent / "lib/swift/macosx"
    runtime_roots = [(path, path) for path in (app / "Contents/Frameworks").glob("libswift*.dylib")]
    binaries = bundle(app, [(executable, executable), (framework / "libobs", bundled_framework / "libobs"),
                            (metal, bundled_metal), (input_module, bundled_module), *runtime_roots],
                      [framework.parent, metal.parent, deps / "lib", deps / "Frameworks", swift_runtime],
                      architecture=args.arch)
    identity = os.environ.get("MIXER_CODESIGN_IDENTITY", "-")
    # Sign from the inside out after every load-command rewrite. A development
    # build is ad-hoc signed; release signing and notarization are explicit.
    for binary in sorted(binaries, key=lambda path: len(path.parts), reverse=True):
        if binary == executable or ".framework/" in str(binary):
            continue
        run("codesign", "--force", "--sign", identity, "--options", "runtime", binary)
    for item in (app / "Contents/Frameworks").glob("*.framework"):
        run("codesign", "--force", "--sign", identity, "--options", "runtime", item)
    run("codesign", "--force", "--sign", identity, "--options", "runtime", driver)
    run("codesign", "--force", "--sign", identity, "--options", "runtime",
        "--entitlements", ROOT / "app/entitlements.plist", app)
    run("codesign", "--verify", "--deep", "--strict", app)
    run("codesign", "--verify", "--strict", driver)
    print(f"Built {app}\nBuilt {driver}\nNo driver was installed on this machine.")


if __name__ == "__main__":
    main()
