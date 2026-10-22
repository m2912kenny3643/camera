import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('gate', Path(__file__).with_name('check_bird_release.py'))
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)
TEST_TMP = Path(__file__).resolve().parents[1] / 'build/test-tmp'
TEST_TMP.mkdir(parents=True, exist_ok=True)


class BirdReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(dir=TEST_TMP)
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.package = self.root / 'BirdEyePose.mlpackage'
        self.package.mkdir()
        (self.package / 'weight.bin').write_bytes(b'test weights only')
        self.manifest = dict(redistribution_verified=True, evidence=['unit-test synthetic grant'],
                             checkpoint_sha256='a' * 64,
                             converted_package_sha256=gate.package_digest(self.package),
                             independent_images_evaluated=100)
        # Invented validator fixtures, never submitted as actual release evidence.
        self.source = dict(model_sha256='a' * 64, independence_evidence='fixture declaration',
                           image_rights_evidence='fixture declaration', images=[])
        for i in range(100):
            self.source['images'].append(dict(
                sha256=f'{i:064x}', real_image=True, annotation_source='unit-test fixture', distant=i == 0,
                birds=[dict(species=f'fixture species {i % 2}', bbox=[0, 0, 100, 100], head_bbox=[10, 10, 20, 20],
                            eyes=dict(left_eye=dict(visible=True, point=[15, 15]), right_eye=dict(visible=False)))],
                predictions=[dict(bbox=[0, 0, 100, 100],
                                  eyes=dict(left_eye=dict(point=[15, 15], confidence=0.9)))],
            ))
        extra = copy.deepcopy(self.source['images'][0]['birds'][0])
        extra.update(bbox=[200, 0, 100, 100], head_bbox=[210, 10, 20, 20])
        extra['eyes']['left_eye']['point'] = [215, 15]
        self.source['images'][0]['birds'].append(extra)
        self.source['images'][0]['predictions'].append(dict(bbox=[200, 0, 100, 100],
                                                           eyes=dict(left_eye=dict(point=[215, 15], confidence=0.9))))
        self.write('accuracy_input', self.source)
        self.accuracy = gate.score(self.source)
        self.accuracy.update(converted_package_sha256=self.manifest['converted_package_sha256'],
                             input_sha256=self.manifest['accuracy_input_sha256'],
                             review=dict(reviewed_by='unit-test fixture', reviewed_at='2026-10-23',
                                         real_images_verified=True, independence_verified=True,
                                         image_rights_verified=True, coverage_verified=True))
        self.write('accuracy_report', self.accuracy)
        self.device = dict(model_sha256='a' * 64,
                           converted_package_sha256=self.manifest['converted_package_sha256'],
                           review=dict(reviewed_by='unit-test fixture', reviewed_at='2026-10-23'),
                           real_device=True, platform='iOS', device_model='iPhone unit-test fixture', os_version='27',
                           latency_scope='camera_frame_to_focus_result', measurement_start=0, measurement_end=10,
                           sustained_seconds=10, measured_hz=10, p95_latency_ms=50,
                           samples=[dict(frame_timestamp=i * 0.1, completed_timestamp=i * 0.1 + 0.05)
                                    for i in range(100)])
        self.write('device_report', self.device)

    def write(self, key, document):
        raw = (json.dumps(document, allow_nan=False) + '\n').encode()
        path = self.root / (key + '.json')
        path.write_bytes(raw)
        self.manifest[key] = path.name
        self.manifest[key + '_sha256'] = gate.sha256(raw)

    def validate(self):
        gate.validate(self.package, self.manifest, self.root)

    def test_concrete_reviewed_reports_pass_despite_accuracy_release_false(self):
        self.assertFalse(self.accuracy['release_qualified'])
        self.validate()

    def test_missing_rights_fail_even_if_package_exists(self):
        with self.assertRaisesRegex(RuntimeError, 'redistribution'):
            gate.validate(self.package, {}, self.root)

    def test_modified_weights_fail(self):
        (self.package / 'weight.bin').write_bytes(b'changed')
        with self.assertRaisesRegex(RuntimeError, 'digest'):
            self.validate()

    def test_path_strings_and_missing_report_files_do_not_pass(self):
        self.manifest['accuracy_report'] = 'nonexistent.json'
        with self.assertRaisesRegex(RuntimeError, 'inside the repo'):
            self.validate()
        self.manifest['accuracy_report'] = '../outside.json'
        with self.assertRaisesRegex(RuntimeError, 'inside the repo'):
            self.validate()

    def test_report_mutation_without_reviewed_hash_fails(self):
        (self.root / 'device_report.json').write_text('{}')
        with self.assertRaisesRegex(RuntimeError, 'digest'):
            self.validate()

    def test_report_must_tie_to_exact_model_and_package(self):
        for key in ['model_sha256', 'converted_package_sha256']:
            original = copy.deepcopy(self.accuracy)
            self.accuracy[key] = 'c' * 64
            self.write('accuracy_report', self.accuracy)
            with self.assertRaisesRegex(RuntimeError, 'digest'):
                self.validate()
            self.accuracy = original

    def test_self_declared_accuracy_pass_and_counts_do_not_override_actual_input(self):
        self.source['images'][0]['predictions'][0]['eyes']['left_eye']['point'] = [99, 99]
        self.write('accuracy_input', self.source)
        self.accuracy['input_sha256'] = self.manifest['accuracy_input_sha256']
        self.write('accuracy_report', self.accuracy)
        with self.assertRaisesRegex(RuntimeError, 'does not reproduce'):
            self.validate()

    def test_fewer_than_100_or_nonreal_images_fail(self):
        self.source['images'].pop()
        self.write('accuracy_input', self.source)
        self.accuracy.update(gate.score(self.source), input_sha256=self.manifest['accuracy_input_sha256'])
        self.write('accuracy_report', self.accuracy)
        with self.assertRaisesRegex(RuntimeError, '100-image'):
            self.validate()

    def test_accuracy_numeric_thresholds_and_visibility_coverage_are_required(self):
        for image in self.source['images']:
            image['predictions'][0]['eyes']['right_eye'] = dict(point=[25, 15], confidence=0.9)
        self.write('accuracy_input', self.source)
        self.accuracy.update(gate.score(self.source), input_sha256=self.manifest['accuracy_input_sha256'])
        self.write('accuracy_report', self.accuracy)
        with self.assertRaisesRegex(RuntimeError, 'accuracy thresholds failed'):
            self.validate()

    def test_reviewed_real_images_independence_and_coverage_required(self):
        self.accuracy['review']['independence_verified'] = False
        self.write('accuracy_report', self.accuracy)
        with self.assertRaisesRegex(RuntimeError, 'review incomplete'):
            self.validate()

    def test_declared_coverage_cannot_replace_missing_actual_scenarios(self):
        for image in self.source['images']:
            image['distant'] = False
        self.write('accuracy_input', self.source)
        self.accuracy.update(gate.score(self.source), input_sha256=self.manifest['accuracy_input_sha256'])
        self.write('accuracy_report', self.accuracy)
        with self.assertRaisesRegex(RuntimeError, 'Missing distant'):
            self.validate()

    def test_simulator_or_mac_trace_cannot_replace_iphone(self):
        self.device['real_device'] = False
        self.write('device_report', self.device)
        with self.assertRaisesRegex(RuntimeError, 'real iPhone'):
            self.validate()

    def test_declared_device_metrics_must_reproduce_from_trace(self):
        self.device['p95_latency_ms'] = 1
        self.write('device_report', self.device)
        with self.assertRaisesRegex(RuntimeError, 'does not reproduce'):
            self.validate()

    def test_slow_or_short_device_measurements_fail(self):
        self.device.update(measurement_end=11, sustained_seconds=11, measured_hz=100 / 11)
        self.device['samples'] = [dict(frame_timestamp=i * 0.11, completed_timestamp=i * 0.11 + 0.05)
                                  for i in range(100)]
        self.write('device_report', self.device)
        with self.assertRaisesRegex(RuntimeError, '>=10 Hz'):
            self.validate()
        self.device.update(measurement_end=9, sustained_seconds=9)
        self.write('device_report', self.device)
        with self.assertRaisesRegex(RuntimeError, 'at least 10 seconds'):
            self.validate()

    def test_initial_cluster_cannot_claim_ten_second_sustained_throughput(self):
        self.device['samples'] = [dict(frame_timestamp=i * 0.009, completed_timestamp=i * 0.009 + 0.05)
                                  for i in range(100)]
        self.write('device_report', self.device)
        with self.assertRaisesRegex(RuntimeError, 'both window edges'):
            self.validate()

    def test_delayed_start_cannot_claim_full_window_coverage(self):
        self.device['samples'] = [dict(frame_timestamp=0.5 + i * 0.095, completed_timestamp=0.55 + i * 0.095)
                                  for i in range(100)]
        self.write('device_report', self.device)
        with self.assertRaisesRegex(RuntimeError, 'both window edges'):
            self.validate()

    def test_middle_idle_gap_cannot_hide_behind_average_hz(self):
        frame_times = [i * 0.095 for i in range(50)] + [5.25 + i * 0.095 for i in range(50)]
        self.device['samples'] = [dict(frame_timestamp=t, completed_timestamp=t + 0.05) for t in frame_times]
        self.write('device_report', self.device)
        with self.assertRaisesRegex(RuntimeError, 'result gap exceeds'):
            self.validate()

    def test_real_trace_with_high_latency_fails_even_at_ten_hz(self):
        self.device['samples'] = [dict(frame_timestamp=i * 0.098, completed_timestamp=i * 0.098 + 0.2)
                                  for i in range(100)]
        self.device['p95_latency_ms'] = 200
        self.write('device_report', self.device)
        with self.assertRaisesRegex(RuntimeError, 'P95 <=150 ms'):
            self.validate()

    def test_nonreal_image_and_missing_invisible_eye_coverage_fail(self):
        self.source['images'][0]['real_image'] = False
        self.write('accuracy_input', self.source)
        self.accuracy.update(gate.score(self.source), input_sha256=self.manifest['accuracy_input_sha256'])
        self.write('accuracy_report', self.accuracy)
        with self.assertRaisesRegex(RuntimeError, 'accuracy thresholds failed'):
            self.validate()
        self.source['images'][0]['real_image'] = True
        for image in self.source['images']:
            for bird in image['birds']:
                bird['eyes']['right_eye'] = dict(visible=True, point=[bird['head_bbox'][0] + 15, 15])
        self.write('accuracy_input', self.source)
        self.accuracy.update(gate.score(self.source), input_sha256=self.manifest['accuracy_input_sha256'])
        self.write('accuracy_report', self.accuracy)
        with self.assertRaisesRegex(RuntimeError, 'Invisible-eye coverage missing'):
            self.validate()

    def test_nonfinite_duplicate_or_future_device_times_fail(self):
        for value in [True, float('nan'), float('inf')]:
            with self.assertRaisesRegex(RuntimeError, 'finite numeric'):
                gate.finite(value, 'test')
        self.device['samples'][1]['frame_timestamp'] = 0
        self.write('device_report', self.device)
        with self.assertRaisesRegex(RuntimeError, 'unique increasing'):
            self.validate()
        self.device['samples'][1]['frame_timestamp'] = 0.1
        self.device['samples'][1]['completed_timestamp'] = 11
        self.write('device_report', self.device)
        with self.assertRaisesRegex(RuntimeError, 'inside the measurement window'):
            self.validate()


if __name__ == '__main__':
    unittest.main()
