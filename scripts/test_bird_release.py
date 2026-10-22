import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('gate', Path(__file__).with_name('check_bird_release.py'))
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)
TEST_TMP = Path(__file__).resolve().parents[1] / 'build/test-tmp'
TEST_TMP.mkdir(parents=True, exist_ok=True)

class BirdReleaseTests(unittest.TestCase):
    def test_missing_rights_fail_even_if_package_exists(self):
        with tempfile.TemporaryDirectory(dir=TEST_TMP) as temporary:
            with self.assertRaisesRegex(RuntimeError, 'redistribution'):
                gate.validate(Path(temporary), {})

    def test_modified_weights_and_missing_measurements_fail(self):
        with tempfile.TemporaryDirectory(dir=TEST_TMP) as temporary:
            package = Path(temporary)
            weight = package/'weight.bin'; weight.write_bytes(b'first')
            manifest = dict(redistribution_verified=True, evidence=['publisher grant'],
                            converted_package_sha256=gate.package_digest(package),
                            independent_images_evaluated=100, accuracy_report='measured.json', device_report='device.json')
            gate.validate(package, manifest)
            weight.write_bytes(b'different')
            with self.assertRaisesRegex(RuntimeError, 'digest'): gate.validate(package, manifest)
            manifest['converted_package_sha256'] = gate.package_digest(package)
            manifest['independent_images_evaluated'] = 99
            with self.assertRaisesRegex(RuntimeError, '100-image'): gate.validate(package, manifest)

if __name__ == '__main__': unittest.main()
