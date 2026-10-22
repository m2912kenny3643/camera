"""Fail closed before a public IPA can contain unverified bird weights.

No weights are downloaded by this script. Converted package hash is a hash of
sorted relative file paths plus each file's SHA256, independent of timestamps.
Reports and accuracy inputs must exist under the repo and match reviewed hashes;
accuracy and >=10s real-iPhone throughput/P95 are recomputed from submitted data.
This checks evidence consistency, not the truth of human review declarations.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path

from bird_eval_metrics import score

ROOT = Path(__file__).resolve().parents[1]
MAX_RESULT_GAP_SECONDS = 0.25

def package_digest(package):
    digest = hashlib.sha256()
    if any(p.is_symlink() for p in package.rglob('*')):
        raise RuntimeError('Bird package cannot contain symlinks')
    for path in sorted(p for p in package.rglob('*') if p.is_file()):
        digest.update(path.relative_to(package).as_posix().encode() + b'\0')
        digest.update(hashlib.sha256(path.read_bytes()).digest())
    return digest.hexdigest()

def sha256(value):
    return hashlib.sha256(value).hexdigest()

def valid_digest(value):
    return isinstance(value, str) and len(value) == 64 and all(c in '0123456789abcdef' for c in value)

def reviewed_json(manifest, key, root):
    relative, expected = manifest.get(key), manifest.get(key + '_sha256')
    if not isinstance(relative, str) or not relative.strip() or not valid_digest(expected):
        raise RuntimeError(f'{key}: concrete reviewed path and SHA-256 are required')
    candidate = Path(relative)
    if candidate.is_absolute():
        raise RuntimeError(f'{key}: evidence path must be relative to the repo')
    path = (root / candidate).resolve()
    if not path.is_relative_to(root.resolve()) or not path.is_file():
        raise RuntimeError(f'{key}: evidence must exist inside the repo')
    raw = path.read_bytes()
    if sha256(raw) != expected:
        raise RuntimeError(f'{key}: digest differs from the reviewed evidence')
    try:
        result = json.loads(raw)
    except (ValueError, UnicodeError) as error:
        raise RuntimeError(f'{key}: invalid JSON') from error
    if not isinstance(result, dict):
        raise RuntimeError(f'{key}: report must be a JSON object')
    return result

def finite(value, label):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise RuntimeError(f'{label}: finite numeric evidence required')
    return float(value)

def check_identity(report, manifest, label):
    if report.get('model_sha256') != manifest['checkpoint_sha256']:
        raise RuntimeError(f'{label}: model digest does not match the reviewed checkpoint')
    if report.get('converted_package_sha256') != manifest['converted_package_sha256']:
        raise RuntimeError(f'{label}: converted package digest does not match')

def check_review(report, label, flags=()):
    review = report.get('review')
    if not isinstance(review, dict) or not all(isinstance(review.get(k), str) and review[k].strip()
                                              for k in ['reviewed_by', 'reviewed_at']):
        raise RuntimeError(f'{label}: named, dated evidence review is required')
    if any(review.get(flag) is not True for flag in flags):
        raise RuntimeError(f'{label}: real-image, independence, image-use and coverage review incomplete')

def check_accuracy(manifest, root):
    report = reviewed_json(manifest, 'accuracy_report', root)
    source = reviewed_json(manifest, 'accuracy_input', root)
    check_identity(report, manifest, 'accuracy_report')
    if source.get('model_sha256') != manifest['checkpoint_sha256']:
        raise RuntimeError('accuracy_input: model digest does not match')
    if report.get('input_sha256') != manifest['accuracy_input_sha256']:
        raise RuntimeError('accuracy_report: reviewed input digest does not match')
    check_review(report, 'accuracy_report', ['real_images_verified', 'independence_verified',
                                           'image_rights_verified', 'coverage_verified'])
    threshold = finite(report.get('correctness_threshold_head_diagonal'), 'eye correctness threshold')
    if not 0 < threshold <= 0.1:
        raise RuntimeError('Eye correctness threshold cannot exceed 0.1 head diagonal')
    try:
        measured = score(source, report.get('confidence_threshold'), threshold)
    except (ValueError, TypeError, KeyError) as error:
        raise RuntimeError(f'accuracy_input: invalid annotation/prediction evidence: {error}') from error
    for key in ['images', 'bird_images', 'distant_images', 'occluded_images', 'multiple_bird_images', 'species',
                'visible_eyes', 'invisible_eyes', 'eye_predictions',
                'correct_eye_predictions', 'false_eye_predictions', 'missed_visible_eyes',
                'false_invisible_eye_predictions', 'eye_precision', 'eye_recall',
                'invisible_eye_false_positive_rate', 'accuracy_thresholds_met']:
        if type(report.get(key)) is not type(measured[key]) or report[key] != measured[key]:
            raise RuntimeError(f'accuracy_report: {key} does not reproduce from reviewed input')
    if manifest.get('independent_images_evaluated') != measured['images'] or measured['images'] < 100:
        raise RuntimeError('Independent 100-image bird evaluation is incomplete or count mismatched')
    if not measured['accuracy_thresholds_met']:
        raise RuntimeError('Bird accuracy thresholds failed: ' + '; '.join(measured['accuracy_blockers']))
    # The accuracy-only scorer intentionally never authorizes redistribution.

def check_device(manifest, root):
    report = reviewed_json(manifest, 'device_report', root)
    check_identity(report, manifest, 'device_report')
    check_review(report, 'device_report')
    if report.get('real_device') is not True or report.get('platform') != 'iOS' or not (
        isinstance(report.get('device_model'), str) and report['device_model'].startswith('iPhone')
        and isinstance(report.get('os_version'), str) and report['os_version'].strip()
    ):
        raise RuntimeError('Bird-eye performance requires an identified real iPhone/iOS device')
    if report.get('latency_scope') != 'camera_frame_to_focus_result':
        raise RuntimeError('Device latency must include camera frame to decoded focus result')
    start = finite(report.get('measurement_start'), 'measurement_start')
    end = finite(report.get('measurement_end'), 'measurement_end')
    duration = end - start
    if duration < 10:
        raise RuntimeError('Real iPhone sustained measurement must cover at least 10 seconds')
    samples = report.get('samples')
    if not isinstance(samples, list) or len(samples) < 100:
        raise RuntimeError('Real iPhone trace needs at least 100 actual inference samples')
    latencies, completions, previous = [], [], None
    for sample in samples:
        if not isinstance(sample, dict):
            raise RuntimeError('Invalid iPhone inference sample')
        frame = finite(sample.get('frame_timestamp'), 'frame_timestamp')
        done = finite(sample.get('completed_timestamp'), 'completed_timestamp')
        if not start <= frame <= done <= end or (previous is not None and frame <= previous):
            raise RuntimeError('iPhone samples need unique increasing frame times inside the measurement window')
        previous = frame
        latencies.append((done - frame) * 1000)
        completions.append(done)
    completions.sort()
    # A high average cannot conceal an initial burst followed by an idle window.
    # Same 250ms freshness budget as camera result admission, including both edges.
    if completions[0] - start > MAX_RESULT_GAP_SECONDS or end - completions[-1] > MAX_RESULT_GAP_SECONDS:
        raise RuntimeError('Real iPhone sustained coverage must reach both window edges within 250 ms')
    if any(b - a > MAX_RESULT_GAP_SECONDS for a, b in zip(completions, completions[1:])):
        raise RuntimeError('Real iPhone sustained result gap exceeds the 250 ms freshness budget')
    measured_hz = len(samples) / duration
    p95 = sorted(latencies)[math.ceil(len(latencies) * 0.95) - 1]
    for key, actual in [('sustained_seconds', duration), ('measured_hz', measured_hz), ('p95_latency_ms', p95)]:
        if not math.isclose(finite(report.get(key), key), actual, rel_tol=1e-6, abs_tol=1e-6):
            raise RuntimeError(f'device_report: {key} does not reproduce from the actual trace')
    if measured_hz < 10 or p95 > 150:
        raise RuntimeError('Real iPhone bird-eye gate requires >=10 Hz and P95 <=150 ms')

def validate(package, manifest, root=ROOT):
    evidence = manifest.get('evidence')
    if manifest.get('redistribution_verified') is not True or not isinstance(evidence, list) or not evidence or not all(
        isinstance(item, str) and item.strip() for item in evidence
    ):
        raise RuntimeError('Bird model redistribution evidence is unresolved; public model IPA blocked')
    if not package.is_dir():
        raise RuntimeError('BirdEyePose.mlpackage is absent; cannot claim a complete bird-eye IPA')
    if package_digest(package) != manifest.get('converted_package_sha256'):
        raise RuntimeError('Converted bird package digest does not match the reviewed manifest')
    if not valid_digest(manifest.get('checkpoint_sha256')):
        raise RuntimeError('Reviewed checkpoint SHA-256 is required')
    check_accuracy(manifest, root)
    check_device(manifest, root)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package', type=Path, default=ROOT/'R6Camera/Resources/BirdEyePose.mlpackage')
    args = parser.parse_args()
    validate(args.package, json.loads((ROOT/'docs/bird-release.json').read_text()))
    print('Bird release reviewed accuracy, real-iPhone trace and package digest verified')

if __name__ == '__main__':
    main()
