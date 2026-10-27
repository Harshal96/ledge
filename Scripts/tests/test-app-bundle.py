"""Check the actual built macOS bundle, not a source/plist text fixture."""
import os
from pathlib import Path
import plistlib
import struct
import unittest


class AppBundleTests(unittest.TestCase):
    def test_installed_product_is_a_discoverable_app_with_a_real_icon(self):
        root = Path(os.environ["LEDGE_TEST_APP_BUNDLE"])
        with (root / "Contents/Info.plist").open("rb") as stream:
            info = plistlib.load(stream)
        self.assertEqual(info["CFBundlePackageType"], "APPL")
        self.assertEqual(info["CFBundleIdentifier"], "com.ledge.app")
        self.assertFalse(info.get("LSUIElement", False), "Ledge must appear in Dock and app switching")
        self.assertEqual(info["CFBundleDisplayName"], "Ledge")
        icon = root / "Contents/Resources" / info["CFBundleIconFile"]
        data = icon.read_bytes()
        self.assertEqual(data[:4], b"icns")
        self.assertEqual(struct.unpack(">I", data[4:8])[0], len(data))
        self.assertGreater(len(data), 4096)


if __name__ == "__main__":
    unittest.main()
