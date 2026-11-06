#!/usr/bin/env python3
"""Portable structural checks. This is NOT a macOS build or audio acceptance."""
import json
import os
import plistlib
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    first_party = []
    for directory, children, files in os.walk(ROOT):
        relative = Path(directory).relative_to(ROOT)
        children[:] = [name for name in children if name not in {".git", ".build", "dist", "__pycache__", ".impeccable"}
                       and not (relative == Path("third_party") and name in {"obs-studio", "BlackHole"})]
        first_party.extend(Path(directory) / name for name in files)
    links = 0
    for path in first_party:
        if path.suffix == ".py":
            compile(path.read_text(), str(path), "exec")
        if path.suffix == ".plist":
            with path.open("rb") as stream:
                plistlib.load(stream)
        if path.suffix == ".md":
            text = path.read_text()
            assert text.count("```") % 2 == 0, f"Unclosed code fence: {path}"
            for link in re.findall(r"\]\(([^)]+)\)", text):
                if "://" in link or link.startswith("#"):
                    continue
                target = path.parent / link.split("#")[0]
                assert target.exists(), f"Broken link: {path} -> {link}"
                links += 1
        if path.suffix in {".md", ".swift", ".hpp", ".cpp", ".mm", ".h", ".c", ".py"}:
            for number, line in enumerate(path.read_text().splitlines(), 1):
                assert line.rstrip() == line, f"Trailing whitespace: {path}:{number}"
    for path in (ROOT / "packaging").glob("*-scripts/*"):
        subprocess.run(["bash", "-n", str(path)], check=True)
        assert os.access(path, os.X_OK), f"Installer script not executable: {path}"

    manifest = json.loads((ROOT / "third_party/sources.json").read_text())
    index = (ROOT / "third_party/README.md").read_text()
    for source in manifest["sources"]:
        assert re.fullmatch(r"[0-9a-f]{40}", source["commit"])
        assert source["commit"] in index

    # Exercise the actual distribution generator without invoking installer tools.
    sys.path.insert(0, str(ROOT / "tools"))
    import fetch_sources
    fetch_sources.verify_sources(fetch_missing=False)
    for source in manifest["sources"]:
        location = ROOT / "third_party" / source["name"]
        if (location / ".git").exists():
            subprocess.run(["git", "-C", str(location), "diff", "--check"], check=True)
    import package_macos
    for identifier in ["com.macmicmixer.installer", "com.macmicmixer.uninstaller"]:
        root = ET.fromstring(package_macos.distribution(identifier, "payload.pkg", "arm64"))
        assert root.find("options").get("hostArchitectures") == "arm64"
        assert root.find("pkg-ref").get("onConclusion") == "RequireRestart"
        assert root.find("pkg-ref").get("id") == identifier
    print(f"Project checks passed: {len(first_party)} files, {links} local links, plists, Python, shell syntax, source pins and installer XML")


if __name__ == "__main__":
    main()
