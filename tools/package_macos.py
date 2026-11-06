#!/usr/bin/env python3
import argparse
import os
import platform
import plistlib
import shutil
import subprocess
from pathlib import Path

from source_archive import create_archive

ROOT = Path(__file__).resolve().parents[1]
VERSION = "0.1.0"


def run(*args):
    print("+", " ".join(map(str, args)), flush=True)
    subprocess.run(list(map(str, args)), check=True)


def distribution(identifier, payload, arch):
    return f'''<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
  <title>Mac Mic Mixer</title>
  <options customize="never" rootVolumeOnly="true" hostArchitectures="{arch}"/>
  <domains enable_anywhere="false" enable_currentUserHome="false" enable_localSystem="true"/>
  <allowed-os-versions><os-version min="13.0"/></allowed-os-versions>
  <conclusion file="conclusion.html" mime-type="text/html"/>
  <choices-outline><line choice="default"/></choices-outline>
  <choice id="default" visible="false"><pkg-ref id="{identifier}"/></choice>
  <pkg-ref id="{identifier}" version="{VERSION}" onConclusion="RequireRestart">{payload}</pkg-ref>
</installer-gui-script>
'''


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--arch", choices=["arm64", "x86_64"], default="arm64")
    args = parser.parse_args()
    if platform.system() != "Darwin":
        raise SystemExit("Installer packaging requires macOS pkgbuild/productbuild")
    dist = ROOT / "dist" / args.arch
    app = dist / "Mac Mic Mixer.app"
    driver = dist / "MacMicMixer.driver"
    if not app.is_dir() or not driver.is_dir():
        raise SystemExit("Run make build first")
    for artifact in [app, driver]:
        run("codesign", "--verify", "--deep", "--strict", artifact)
    work = ROOT / ".build" / f"package-{args.arch}"
    if work.exists():
        shutil.rmtree(work)
    root = work / "root"
    (root / "Applications").mkdir(parents=True)
    hal = root / "Library/Audio/Plug-Ins/HAL"
    hal.mkdir(parents=True)
    shutil.copytree(app, root / "Applications" / app.name, symlinks=True)
    shutil.copytree(driver, hal / driver.name, symlinks=True)
    components = [{"RootRelativeBundlePath": "Applications/Mac Mic Mixer.app",
                   "BundleIsRelocatable": False, "BundleHasStrictIdentifier": True,
                   "BundleOverwriteAction": "upgrade"}]
    component_file = work / "components.plist"
    component_file.write_bytes(plistlib.dumps(components))
    run("pkgbuild", "--root", root, "--install-location", "/", "--ownership", "recommended",
        "--component-plist", component_file, "--identifier", "com.macmicmixer.installer",
        "--version", VERSION, "--scripts", ROOT / "packaging/install-scripts", work / "payload.pkg")
    run("pkgbuild", "--nopayload", "--identifier", "com.macmicmixer.uninstaller",
        "--version", VERSION, "--scripts", ROOT / "packaging/uninstall-scripts", work / "uninstall-payload.pkg")
    identity = os.environ.get("MIXER_INSTALLER_IDENTITY")
    profile = os.environ.get("MIXER_NOTARY_PROFILE")
    if profile and (not identity or os.environ.get("MIXER_CODESIGN_IDENTITY", "-") == "-"):
        raise SystemExit("Notarization requires both Developer ID application and installer signing identities")
    for uninstall in [False, True]:
        name = "Uninstall" if uninstall else "Install"
        identifier = "com.macmicmixer.uninstaller" if uninstall else "com.macmicmixer.installer"
        payload = "uninstall-payload.pkg" if uninstall else "payload.pkg"
        resources = work / f"resources-{name}"
        resources.mkdir()
        message = ("卸载完成。请重启 Mac，以卸载音频服务中仍然加载的虚拟麦克风。个人设置保留在用户的 Application Support/MacMicMixer 目录。"
                   if uninstall else "安装完成后请重启 Mac，再从应用程序中打开 Mac Mic Mixer。添加输入并开始混音，然后在其他 App 中选择 Mac Mic Mixer 麦克风。")
        (resources / "conclusion.html").write_text(f"<!doctype html><html lang='zh-CN'><meta charset='utf-8'><body><h2>{name} Mac Mic Mixer</h2><p>{message}</p></body></html>")
        xml = work / f"{name}.xml"
        xml.write_text(distribution(identifier, payload, args.arch))
        output = dist / f"MacMicMixer-{VERSION}-{args.arch}-{name}.pkg"
        command = ["productbuild", "--distribution", xml, "--resources", resources, "--package-path", work]
        if identity:
            command += ["--sign", identity, "--timestamp"]
        run(*command, output)
        if profile:
            run("xcrun", "notarytool", "submit", output, "--keychain-profile", profile, "--wait")
            run("xcrun", "stapler", "staple", output)
    create_archive()
    print(f"Packages saved to {dist}. Nothing was installed or uninstalled.")


if __name__ == "__main__":
    main()
