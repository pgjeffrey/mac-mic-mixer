#!/usr/bin/env python3
"""Bundle a Mach-O dependency closure and remove build-machine load paths."""
import hashlib
import re
import shutil
import subprocess
from collections import deque
from pathlib import Path


def command(*args):
    return subprocess.check_output([str(arg) for arg in args], text=True)


def dependencies(binary, architecture=None):
    selection = ("-arch", architecture) if architecture else ()
    lines = command("otool", *selection, "-L", binary).splitlines()
    # Universal binaries can contain several unindented architecture headers.
    return [line.strip().split(" (compatibility", 1)[0] for line in lines
            if line.strip() and line[:1].isspace()]


def rpaths(binary, architecture=None):
    selection = ("-arch", architecture) if architecture else ()
    return re.findall(r"cmd LC_RPATH\s+cmdsize \d+\s+path (.+?) \(offset", command("otool", *selection, "-l", binary))


def system_library(value):
    return value.startswith(("/usr/lib/", "/System/Library/"))


def bundle(app, roots, search_roots, architecture=None):
    app = Path(app).resolve()
    frameworks = app / "Contents/Frameworks"
    frameworks.mkdir(parents=True, exist_ok=True)
    searches = [frameworks, *[Path(root).resolve() for root in search_roots]]
    queue = deque()
    completed = set()
    origins = {}
    fingerprints = {}

    def fingerprint(path):
        if path not in fingerprints:
            fingerprints[path] = hashlib.sha256(path.read_bytes()).digest()
        return fingerprints[path]

    def schedule(original, target):
        original, target = Path(original).resolve(), Path(target).resolve()
        if not target.is_relative_to(app):
            raise RuntimeError(f"Refusing to rewrite a binary outside the application: {target}")
        if target in origins:
            # A reference can resolve to a binary that was already copied and
            # rewritten. Its on-disk bytes have changed, but its identity has not.
            if original != target and origins[target] != fingerprint(original):
                raise RuntimeError(f"Different libraries would occupy the same bundled path: {target}")
            return
        signature = fingerprint(original)
        if target.exists() and original != target and fingerprint(target) != signature:
            raise RuntimeError(f"Existing bundled library has different contents: {target}")
        origins[target] = signature
        queue.append((original, target))

    for original, target in roots:
        schedule(original, target)

    def locate(value, original):
        candidates = []
        if value.startswith("@loader_path/"):
            candidates.append(original.parent / value.removeprefix("@loader_path/"))
        elif value.startswith("@executable_path/"):
            candidates.append(app / "Contents/MacOS" / value.removeprefix("@executable_path/"))
        elif value.startswith("@rpath/"):
            suffix = value.removeprefix("@rpath/")
            for path in rpaths(original, architecture):
                path = path.replace("@loader_path", str(original.parent)).replace("@executable_path", str(app / "Contents/MacOS"))
                candidates.append(Path(path) / suffix)
            candidates.extend(root / suffix for root in searches)
        else:
            candidates.append(Path(value))
        for candidate in candidates:
            if candidate.is_file():
                return candidate.resolve()
        # Dependencies in a relocatable obs-deps archive may retain their build
        # prefix. Search by exact filename and reject ambiguous alternatives.
        matches = {path.resolve() for root in searches for path in root.rglob(Path(value).name) if path.is_file()}
        if len(matches) == 1:
            return matches.pop()
        raise RuntimeError(f"Cannot resolve {value} required by {original}; candidates={sorted(map(str, matches))}")

    def destination(source):
        try:
            source.relative_to(frameworks)
            return source
        except ValueError:
            pass
        for parent in source.parents:
            if parent.suffix == ".framework":
                target = frameworks / parent.name
                if not target.exists():
                    shutil.copytree(parent, target, symlinks=True)
                return target / source.relative_to(parent)
        return frameworks / source.name

    while queue:
        original, target = queue.popleft()
        if target in completed:
            continue
        completed.add(target)
        if not target.exists():
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(original, target)
        target.chmod(target.stat().st_mode | 0o200)
        for dependency in dependencies(original, architecture):
            if system_library(dependency):
                continue
            source = locate(dependency, original)
            if source == original:
                continue  # LC_ID_DYLIB is listed by otool as well.
            copied = destination(source).resolve()
            schedule(source, copied)
            relative = copied.relative_to(frameworks)
            new = "@rpath/" + str(relative)
            if dependency != new:
                command("install_name_tool", "-change", dependency, new, target)
        if target.suffix == ".dylib" or ".framework/" in str(target):
            command("install_name_tool", "-id", "@rpath/" + str(target.relative_to(frameworks)), target)
        existing = rpaths(target, architecture)
        for path in existing:
            if path.startswith("/") and not system_library(path):
                command("install_name_tool", "-delete_rpath", path, target)
        runtime_path = "@executable_path/../Frameworks"
        if runtime_path not in existing:
            command("install_name_tool", "-add_rpath", runtime_path, target)

    for binary in completed:
        for dependency in dependencies(binary, architecture):
            if dependency.startswith("/") and not system_library(dependency):
                raise RuntimeError(f"Build-machine dependency remains in {binary}: {dependency}")
            if dependency.startswith("@rpath/") and not (frameworks / dependency.removeprefix("@rpath/")).exists():
                raise RuntimeError(f"Missing bundled dependency in {binary}: {dependency}")
    return completed
