import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import check_bird_functional_release as gate

TEST_TMP = Path(__file__).resolve().parents[1] / 'build/test-tmp'
TEST_TMP.mkdir(parents=True, exist_ok=True)


class FunctionalBirdReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(dir=TEST_TMP)
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        # Synthetic gate fixture only. Never used as actual model-release evidence.
        self.weight = b'unit-test ONNX fixture, not executable model weights'
        self.digest = hashlib.sha256(self.weight).hexdigest()
        self.enterContext(patch.object(gate, 'MODEL_SHA256', self.digest))
        self.enterContext(patch.object(gate, 'MODEL_BYTES', len(self.weight)))
        self.write(gate.MODEL_FILE, self.weight)
        self.write(gate.CARD, 'eye-pose-v0: left_eye right_eye head_top, beak and shoulders')
        self.write(gate.LICENSE, 'GNU AFFERO GENERAL PUBLIC LICENSE\nVersion 3\nTERMS AND CONDITIONS\n'
                   + ('Synthetic license-length fixture.\n' * 1000) + 'END OF TERMS AND CONDITIONS')
        self.write('docs/research/android-bird-0.7.md', 'AGPL review; CUB image conditions; non-commercial research scope. Formal qualification remains incomplete.')
        self.manifest = {
            'release_kind': 'functional-test',
            'model': {'file': gate.MODEL_FILE, 'sha256': self.digest, 'bytes': len(self.weight), 'source': gate.MODEL_SOURCE},
            'rights': {'route': 'AGPL-3.0-or-later', 'decision': 'docs/research/android-bird-0.7.md',
                       'notices': [gate.CARD, gate.LICENSE], 'source_url': gate.SOURCE_URL},
            'formal_qualification': False,
        }
        self.save()

    def write(self, name, content):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content if isinstance(content, bytes) else content.encode('utf-8'))

    def save(self):
        self.write('docs/bird-functional-release.json', json.dumps(self.manifest))

    def test_functional_bundle_does_not_require_formal_accuracy_or_device_reports(self):
        self.assertEqual(gate.validate(self.root)['release_kind'], 'functional-test')
        self.assertFalse((self.root / 'docs/bird-release.json').exists())

    def test_weight_tamper_and_wrong_size_fail(self):
        self.write(gate.MODEL_FILE, b'x' * len(self.weight))
        with self.assertRaisesRegex(RuntimeError, 'digest'):
            gate.validate(self.root)
        self.write(gate.MODEL_FILE, b'short')
        with self.assertRaisesRegex(RuntimeError, 'size'):
            gate.validate(self.root)

    def test_manifest_cannot_switch_model_or_claim_formal_qualification(self):
        original = copy.deepcopy(self.manifest)
        for key, value in [('sha256', 'b' * 64), ('bytes', True), ('source', 'different model')]:
            self.manifest = copy.deepcopy(original)
            self.manifest['model'][key] = value
            self.save()
            with self.assertRaises(RuntimeError):
                gate.validate(self.root)
        for flag in [True, 0, None]:
            self.manifest = copy.deepcopy(original)
            self.manifest['formal_qualification'] = flag
            self.save()
            with self.assertRaisesRegex(RuntimeError, 'formal qualification'):
                gate.validate(self.root)

    def test_notice_list_and_actual_notice_files_are_required(self):
        self.manifest['rights']['notices'] = [gate.CARD]
        self.save()
        with self.assertRaisesRegex(RuntimeError, 'notices'):
            gate.validate(self.root)
        self.manifest['rights']['notices'].append(gate.LICENSE)
        self.save()
        (self.root / gate.LICENSE).unlink()
        with self.assertRaisesRegex(RuntimeError, 'existing regular file'):
            gate.validate(self.root)

    def test_stub_or_unreadable_license_is_not_a_full_notice(self):
        self.write(gate.LICENSE, 'AGPL-3.0')
        with self.assertRaisesRegex(RuntimeError, 'actual full'):
            gate.validate(self.root)
        self.write(gate.LICENSE, b'\xff\xfe')
        with self.assertRaisesRegex(RuntimeError, 'UTF-8'):
            gate.validate(self.root)

    def test_missing_decision_source_url_or_scope_fails(self):
        self.manifest['rights']['decision'] = 'docs/research/missing.md'
        self.save()
        with self.assertRaisesRegex(RuntimeError, 'existing regular file'):
            gate.validate(self.root)
        self.manifest['rights']['decision'] = 'docs/research/android-bird-0.7.md'
        self.manifest['rights']['source_url'] = ''
        self.save()
        with self.assertRaisesRegex(RuntimeError, 'source URL'):
            gate.validate(self.root)
        self.manifest['rights']['source_url'] = gate.SOURCE_URL
        self.save()
        self.write('docs/research/android-bird-0.7.md', 'AGPL with no source/scope evidence')
        with self.assertRaisesRegex(RuntimeError, 'research-use scope'):
            gate.validate(self.root)

    def test_repo_escape_absolute_paths_and_bad_manifest_fail(self):
        for decision in ['../outside.md', str(self.root / 'absolute.md')]:
            self.manifest['rights']['decision'] = decision
            self.save()
            with self.assertRaisesRegex(RuntimeError, 'inside the repo|relative to the repo'):
                gate.validate(self.root)
        self.write('docs/bird-functional-release.json', '{not JSON')
        with self.assertRaisesRegex(RuntimeError, 'manifest JSON'):
            gate.validate(self.root)

    def test_other_formal_completion_claims_fail(self):
        for key in ['full_plan_complete', 'device_performance_verified', 'accuracy_verified']:
            self.manifest[key] = True
            self.save()
            with self.assertRaisesRegex(RuntimeError, key):
                gate.validate(self.root)
            self.manifest.pop(key)


if __name__ == '__main__':
    unittest.main()
