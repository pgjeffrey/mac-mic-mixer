#!/usr/bin/env python3
import tarfile
import io
import json
import hashlib
import subprocess
from pathlib import Path
from fetch_sources import digest, verify_sources

ROOT = Path(__file__).resolve().parents[1]


def create_archive():
    verify_sources(fetch_missing=False)
    output = ROOT / "dist/MacMicMixer-0.1.0-source.tar.gz"
    output.parent.mkdir(parents=True, exist_ok=True)
    excluded = {".git", ".build", ".deps", "dist", "__pycache__", ".DS_Store"}
    snapshots = {}
    for source in json.loads((ROOT / "third_party/sources.json").read_text())["sources"]:
        directory = ROOT / "third_party" / source["name"]
        if (directory / ".git").exists():
            tracked = subprocess.check_output(["git", "-C", str(directory), "ls-files", "-z"]).decode().split("\0")
            files = {name: digest(directory / name) for name in tracked if name and (directory / name).is_file()}
            snapshots[source["name"]] = {"commit": source["commit"], "files": files}
        else:
            snapshots[source["name"]] = json.loads((ROOT / "third_party/source-snapshots.json").read_text())[source["name"]]
    with tarfile.open(output, "w:gz") as archive:
        for path in sorted(ROOT.rglob("*")):
            relative = path.relative_to(ROOT)
            if any(part in excluded for part in relative.parts) or path.is_dir():
                continue
            if relative.parts[0] == ".impeccable" and relative != Path(".impeccable/design.json"):
                continue
            if relative == Path("third_party/source-snapshots.json"):
                continue
            archive.add(path, arcname="MacMicMixer-0.1.0/" + str(relative), recursive=False)
        content = json.dumps(snapshots, indent=2).encode()
        info = tarfile.TarInfo("MacMicMixer-0.1.0/third_party/source-snapshots.json")
        info.size = len(content)
        info.mode = 0o644
        archive.addfile(info, io.BytesIO(content))
    checksum = hashlib.sha256(output.read_bytes()).hexdigest()
    output.with_suffix(output.suffix + ".sha256").write_text(checksum + "  " + output.name + "\n")
    print(output)
    return output


if __name__ == "__main__":
    create_archive()
