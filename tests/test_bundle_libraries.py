"""Exercise real file copying and dependency resolution with synthetic otool data.

These tests never invoke Apple tools or load fixture files as executable code.
They verify packaging behavior, not real Mach-O compatibility or signing.
"""
import copy
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import bundle_libraries


class MachOFixture:
    def __init__(self):
        self.images = {}
        self.paths = {}
        self.rewrites = []
        self.architectures = []

    def create(self, path, dependencies=(), rpaths=(), identifier=None, token=None):
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        token = token or str(path)
        path.write_text(token)
        self.images[token] = {"dependencies": list(map(str, dependencies)),
                              "rpaths": list(map(str, rpaths)), "identifier": identifier}
        return path

    def metadata(self, path):
        path = Path(path).resolve()
        if path not in self.paths:
            self.paths[path] = copy.deepcopy(self.images[path.read_text()])
        return self.paths[path]

    def __call__(self, *args):
        args = list(map(str, args))
        if args[:2] == ["otool", "-arch"]:
            self.architectures.append(args[2])
            args = [args[0], *args[3:]]
        if args[:2] == ["otool", "-L"]:
            state = self.metadata(args[2])
            dependencies = [*([state["identifier"]] if state["identifier"] else []), *state["dependencies"]]
            return args[2] + ":\n" + "".join(
                f"\t{name} (compatibility version 1.0.0, current version 1.0.0)\n" for name in dependencies)
        if args[:2] == ["otool", "-l"]:
            return "".join(f"Load command 0\n cmd LC_RPATH\n cmdsize 48\n path {path} (offset 12)\n"
                           for path in self.metadata(args[2])["rpaths"])
        if args[0] == "install_name_tool":
            self.rewrites.append(Path(args[-1]).resolve())
            state = self.metadata(args[-1])
            if args[1] == "-change":
                state["dependencies"] = [args[3] if item == args[2] else item for item in state["dependencies"]]
            elif args[1] == "-id":
                state["identifier"] = args[2]
            elif args[1] == "-delete_rpath":
                state["rpaths"].remove(args[2])
            elif args[1] == "-add_rpath":
                state["rpaths"].append(args[2])
            else:
                raise AssertionError(args)
            return ""
        raise AssertionError(args)


class BundleTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="mixer-bundle-")
        self.root = Path(self.directory.name)
        self.app = self.root / "Mac Mic Mixer.app"
        self.frameworks = self.app / "Contents/Frameworks"
        self.frameworks.mkdir(parents=True)
        self.executable = self.app / "Contents/MacOS/MacMicMixer"
        self.shell = MachOFixture()
        self.mock = patch.object(bundle_libraries, "command", side_effect=self.shell)
        self.mock.start()
        self.addCleanup(self.mock.stop)
        self.addCleanup(self.directory.cleanup)

    def bundle(self, searches, extra_roots=()):
        return bundle_libraries.bundle(self.app, [(self.executable, self.executable), *extra_roots], searches)

    def test_transitive_dependencies_cycles_swift_runtime_and_system_rpath(self):
        deps = self.root / "build with spaces"
        first = self.shell.create(deps / "libFirst.1.dylib", rpaths=[deps])
        second = self.shell.create(deps / "libSecond.2.dylib", dependencies=["@loader_path/libFirst.1.dylib"])
        self.shell.images[first.read_text()]["dependencies"] = [str(second), "/usr/lib/libSystem.B.dylib"]
        self.shell.images[first.read_text()]["identifier"] = str(first)
        runtime = self.shell.create(self.root / "toolchain/libswift_Concurrency.dylib",
                                    dependencies=["/usr/lib/libSystem.B.dylib"],
                                    identifier="@rpath/libswift_Concurrency.dylib")
        # This is what swift-stdlib-tool prepares before the dependency pass.
        bundled_runtime = self.frameworks / runtime.name
        shutil.copy2(runtime, bundled_runtime)
        self.shell.create(self.executable, dependencies=["@rpath/libFirst.1.dylib", "@rpath/libswift_Concurrency.dylib"],
                          rpaths=[deps, "/usr/lib/swift"])
        result = self.bundle([deps], [(bundled_runtime, bundled_runtime)])
        self.assertEqual(len(result), 4)
        self.assertTrue((self.frameworks / first.name).is_file())
        self.assertTrue((self.frameworks / second.name).is_file())
        self.assertEqual(self.shell.metadata(self.executable)["dependencies"],
                         ["@rpath/libFirst.1.dylib", "@rpath/libswift_Concurrency.dylib"])
        self.assertEqual(self.shell.metadata(self.frameworks / first.name)["dependencies"],
                         ["@rpath/libSecond.2.dylib", "/usr/lib/libSystem.B.dylib"])
        self.assertEqual(self.shell.metadata(self.frameworks / second.name)["dependencies"], ["@rpath/libFirst.1.dylib"])
        self.assertIn("/usr/lib/swift", self.shell.metadata(self.executable)["rpaths"])
        for target in result:
            self.assertNotIn(str(deps), self.shell.metadata(target)["rpaths"])
            self.assertTrue(target.is_relative_to(self.app))
        self.assertEqual(self.shell.metadata(first)["dependencies"][0], str(second))

    def test_missing_dependency_fails_instead_of_emitting_an_incomplete_bundle(self):
        self.shell.create(self.executable, dependencies=["@rpath/libMissing.dylib"])
        with self.assertRaisesRegex(RuntimeError, "Cannot resolve"):
            self.bundle([])

    def test_dependency_reads_use_the_selected_architecture(self):
        library = self.shell.create(self.root / "lib/libSelected.dylib")
        self.shell.create(self.executable, dependencies=[str(library)])
        bundle_libraries.bundle(self.app, [(self.executable, self.executable)], [], architecture="arm64")
        self.assertTrue(self.shell.architectures)
        self.assertEqual(set(self.shell.architectures), {"arm64"})

    def test_same_filename_with_different_contents_is_rejected(self):
        first = self.shell.create(self.root / "one/libShared.dylib")
        second = self.shell.create(self.root / "two/libShared.dylib")
        self.shell.create(self.executable, dependencies=[str(first), str(second)])
        with self.assertRaisesRegex(RuntimeError, "same bundled path"):
            self.bundle([])

    def test_identical_aliases_can_share_one_bundled_library(self):
        first = self.shell.create(self.root / "one/libShared.dylib", token="same-image")
        second = self.shell.create(self.root / "two/libShared.dylib", token="same-image")
        self.shell.create(self.executable, dependencies=[str(first), str(second)])
        result = self.bundle([])
        self.assertEqual(len(result), 2)
        self.assertEqual(self.shell.metadata(self.executable)["dependencies"],
                         ["@rpath/libShared.dylib", "@rpath/libShared.dylib"])

    def test_versioned_framework_and_resource_symlinks_are_preserved(self):
        framework = self.root / "build/Foo.framework"
        binary = self.shell.create(framework / "Versions/A/Foo", dependencies=["/usr/lib/libSystem.B.dylib"],
                                   identifier="@rpath/Foo.framework/Versions/A/Foo")
        resources = framework / "Versions/A/Resources"
        resources.mkdir()
        (resources / "effect.txt").write_text("required resource")
        (framework / "Versions/Current").symlink_to("A")
        (framework / "Foo").symlink_to("Versions/Current/Foo")
        (framework / "Resources").symlink_to("Versions/Current/Resources")
        self.shell.create(self.executable, dependencies=["@rpath/Foo.framework/Versions/A/Foo"],
                          rpaths=[framework.parent])
        self.bundle([framework.parent])
        copied = self.frameworks / "Foo.framework"
        self.assertTrue((copied / "Foo").is_symlink())
        self.assertTrue((copied / "Resources").is_symlink())
        self.assertEqual((copied / "Resources/effect.txt").read_text(), "required resource")
        self.assertEqual(self.shell.metadata(copied / "Foo")["identifier"], "@rpath/Foo.framework/Versions/A/Foo")
        self.assertEqual(self.shell.metadata(binary)["identifier"], "@rpath/Foo.framework/Versions/A/Foo")

    def test_symlink_cannot_make_rewrites_escape_application(self):
        outside = self.shell.create(self.root / "original.dylib")
        linked = self.frameworks / "unsafe.dylib"
        linked.symlink_to(outside)
        self.shell.create(self.executable)
        with self.assertRaisesRegex(RuntimeError, "outside the application"):
            self.bundle([], [(outside, linked)])
        self.assertEqual(self.shell.rewrites, [])

    def test_installer_scripts_reject_another_volume_before_touching_host_paths(self):
        root = Path(__file__).resolve().parents[1]
        for script in (root / "packaging").glob("*-scripts/*"):
            with self.subTest(script=script):
                result = subprocess.run(["bash", str(script), "package.pkg", "/", "/Volumes/Another Mac"],
                                        text=True, capture_output=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("只支持当前启动磁盘", result.stderr)


if __name__ == "__main__":
    unittest.main()
