"""Check build-product discovery against Xcode's framework link stubs."""
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from build_macos import find_one


class BuildProductsTests(unittest.TestCase):
    def test_framework_discovery_ignores_xcode_link_stub(self):
        with tempfile.TemporaryDirectory(prefix="mixer-build-") as directory:
            root = Path(directory)
            product = root / "libobs/Release/libobs.framework"
            product.mkdir(parents=True)
            (product / "libobs").write_bytes(b"framework executable")
            stub = root / "build/EagerLinkingTBDs/Release/libobs.framework"
            stub.mkdir(parents=True)
            (stub / "libobs.tbd").write_text("link stub")
            self.assertEqual(find_one(root, "libobs.framework"), product)


if __name__ == "__main__":
    unittest.main()
