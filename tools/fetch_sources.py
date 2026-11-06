#!/usr/bin/env python3
"""Fetch missing upstream workspaces and verify the pinned source revisions."""
import json
import hashlib
import os
import posixpath
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)


def digest(path):
    if path.is_symlink():
        # Safe tar extraction may normalize './target' to 'target'. Hash the
        # equivalent relative link identity rather than its redundant spelling.
        return hashlib.sha256(("symlink:" + posixpath.normpath(os.readlink(path))).encode()).hexdigest()
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify_sources(fetch_missing=True):
    sources = json.loads((ROOT / "third_party/sources.json").read_text())["sources"]
    snapshot_path = ROOT / "third_party/source-snapshots.json"
    snapshots = json.loads(snapshot_path.read_text()) if snapshot_path.exists() else {}
    for source in sources:
        destination = ROOT / "third_party" / source["name"]
        if not destination.exists():
            if not fetch_missing:
                raise RuntimeError(f"Missing {destination}; run make sources")
            run("git", "clone", "--depth", "1", "--branch", source["tag"], "--", source["url"], str(destination))
        if not (destination / ".git").exists():
            snapshot = snapshots.get(source["name"], {})
            if snapshot.get("commit") != source["commit"] or not snapshot.get("files"):
                raise RuntimeError(f"{destination}: neither a Git workspace nor a verified source snapshot; left untouched")
            for relative, expected in snapshot["files"].items():
                file = destination / relative
                if Path(relative).is_absolute() or ".." in Path(relative).parts:
                    raise RuntimeError(f"Invalid snapshot path: {relative}")
                if not file.exists() or digest(file) != expected:
                    raise RuntimeError(f"Source snapshot differs: {file}; left untouched")
            print(f"Verified snapshot {source['name']} {source['tag']} {source['commit']}")
            continue
        actual = subprocess.check_output(["git", "-C", str(destination), "rev-parse", "HEAD"], text=True).strip()
        if actual != source["commit"]:
            raise SystemExit(f"{destination}: expected {source['commit']}, found {actual}; left untouched")
        run("git", "-C", str(destination), "diff", "--exit-code", "--quiet", "HEAD", "--")
        print(f"Verified {source['name']} {source['tag']} {actual}")


if __name__ == "__main__":
    verify_sources()
