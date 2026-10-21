import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location("package_ipa", Path(__file__).with_name("package_ipa.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
TEST_TMP = Path(__file__).resolve().parents[1] / "build/test-tmp"
TEST_TMP.mkdir(parents=True, exist_ok=True)


class PackagingTests(unittest.TestCase):
    def test_payload_contains_executable_and_resources(self):
        with tempfile.TemporaryDirectory(dir=TEST_TMP) as temporary:
            root = Path(temporary)
            app = root / "test.xcarchive/Products/Applications/R6Camera.app"
            app.mkdir(parents=True)
            (app / "Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": "R6Camera"}))
            binary = app / "R6Camera"
            binary.write_bytes(b"test executable")
            binary.chmod(0o755)
            resource = app / "model.mlmodelc/data.bin"
            resource.parent.mkdir()
            resource.write_bytes(b"model")
            module.package(root / "test.xcarchive", root / "test.ipa")
            with zipfile.ZipFile(root / "test.ipa") as package:
                self.assertIn("Payload/R6Camera.app/R6Camera", package.namelist())
                self.assertIn("Payload/R6Camera.app/model.mlmodelc/data.bin", package.namelist())

    def test_reject_missing_app(self):
        with tempfile.TemporaryDirectory(dir=TEST_TMP) as temporary:
            with self.assertRaisesRegex(RuntimeError, "Expected one"):
                module.package(Path(temporary), Path(temporary) / "test.ipa")

    def test_reject_archive_without_executable(self):
        with tempfile.TemporaryDirectory(dir=TEST_TMP) as temporary:
            root = Path(temporary)
            app = root / "Products/Applications/Broken.app"
            app.mkdir(parents=True)
            (app / "Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": "missing"}))
            with self.assertRaisesRegex(RuntimeError, "missing its executable"):
                module.package(root, root / "test.ipa")


if __name__ == "__main__":
    unittest.main()
