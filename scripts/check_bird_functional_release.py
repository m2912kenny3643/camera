"""Verify the separately labelled first bird-model functional-test bundle.

This gate checks pinned files, required notices and a recorded research-use
decision. It does not decide legal rights or certify 100-image accuracy/iPhone
performance. The formal release gate remains independent and stricter.
"""

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODEL_FILE = 'R6Camera/Resources/BirdEyePose.onnx'
MODEL_SHA256 = '350f370aac45ec120bb73434eb0add0446a5f327344c65b03a633229dc2c551b'
MODEL_BYTES = 10_802_648
MODEL_SOURCE = 'user-provided NeoFocus-0.5.0-pro.apk/assets/bird-eye.onnx'
CARD = 'R6Camera/Resources/BIRD-MODEL-CARD.md'
LICENSE = 'R6Camera/Resources/LICENSE-ULTRALYTICS.txt'
SOURCE_URL = 'https://github.com/m2912kenny3643/camera'


def checked_file(root, relative):
    if not isinstance(relative, str) or not relative.strip():
        raise RuntimeError('A concrete repo-relative evidence path is required')
    candidate = Path(relative)
    if candidate.is_absolute():
        raise RuntimeError('Evidence paths must be relative to the repo')
    original = root / candidate
    path = original.resolve()
    if not path.is_relative_to(root.resolve()) or not path.is_file() or original.is_symlink():
        raise RuntimeError(f'Evidence must be an existing regular file inside the repo: {relative}')
    return path


def text_file(root, relative):
    try:
        return checked_file(root, relative).read_text(encoding='utf-8')
    except UnicodeError as error:
        raise RuntimeError(f'Notice/decision must be readable UTF-8: {relative}') from error


def validate(root=ROOT):
    root = Path(root)
    try:
        manifest = json.loads(checked_file(root, 'docs/bird-functional-release.json').read_bytes())
    except (ValueError, UnicodeError) as error:
        raise RuntimeError('Invalid bird functional release manifest JSON') from error
    if not isinstance(manifest, dict) or manifest.get('release_kind') != 'functional-test':
        raise RuntimeError('Bird bundle must be explicitly labelled functional-test')
    if manifest.get('formal_qualification') is not False:
        raise RuntimeError('Functional bundle must explicitly decline formal qualification')
    for key in ['full_plan_complete', 'device_performance_verified', 'accuracy_verified']:
        if manifest.get(key) is True:
            raise RuntimeError(f'Functional bundle cannot claim {key}')
    model = manifest.get('model')
    if not isinstance(model, dict) or model.get('file') != MODEL_FILE or model.get('source') != MODEL_SOURCE:
        raise RuntimeError('Bird model path/source must identify the pinned Android APK asset')
    if model.get('sha256') != MODEL_SHA256 or type(model.get('bytes')) is not int or model['bytes'] != MODEL_BYTES:
        raise RuntimeError('Bird model manifest must pin the approved ONNX SHA-256 and size')
    path = checked_file(root, MODEL_FILE)
    if path.stat().st_size != MODEL_BYTES:
        raise RuntimeError('Bundled bird ONNX size does not match the pinned model')
    digest = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(chunk)
    if digest.hexdigest() != MODEL_SHA256:
        raise RuntimeError('Bundled bird ONNX digest does not match the pinned model')
    rights = manifest.get('rights')
    if not isinstance(rights, dict) or rights.get('route') != 'AGPL-3.0-or-later':
        raise RuntimeError('The reviewed AGPL source/notices route is required')
    source_url = rights.get('source_url')
    if not isinstance(source_url, str) or source_url.rstrip('/') != SOURCE_URL:
        raise RuntimeError('The complete App source URL must accompany the functional bundle')
    notices = rights.get('notices')
    if not isinstance(notices, list) or not all(isinstance(n, str) for n in notices) or not {CARD, LICENSE}.issubset(notices):
        raise RuntimeError('Both the original bird model card and Ultralytics license notices are required')
    for notice in notices:
        if not text_file(root, notice).strip():
            raise RuntimeError(f'Notice is empty: {notice}')
    card = text_file(root, CARD)
    if not all(marker in card for marker in ['eye-pose-v0', 'left_eye', 'right_eye', 'head_top']):
        raise RuntimeError('Bird model card does not identify the expected six-point model')
    license_text = text_file(root, LICENSE)
    if len(license_text) < 30_000 or not all(marker in license_text for marker in [
        'GNU AFFERO GENERAL PUBLIC LICENSE', 'Version 3', 'TERMS AND CONDITIONS', 'END OF TERMS AND CONDITIONS'
    ]):
        raise RuntimeError('The actual full AGPL-3.0 license notice must accompany the model')
    decision = text_file(root, rights.get('decision'))
    lower = decision.lower()
    if not decision.strip() or 'agpl' not in lower or 'cub' not in lower or not ('research' in lower or '研究' in decision):
        raise RuntimeError('The decision must record AGPL, CUB source terms and research-use scope')
    return manifest


def validate_ipa(path, root=ROOT):
    import zipfile
    manifest = validate(root)
    with zipfile.ZipFile(path) as package:
        models = [name for name in package.namelist() if name.endswith('.app/BirdEyePose.onnx')]
        if len(models) != 1:
            raise RuntimeError('IPA must contain exactly one bundled BirdEyePose.onnx')
        prefix = models[0].removesuffix('BirdEyePose.onnx')
        data = package.read(models[0])
        if hashlib.sha256(data).hexdigest() != manifest['model']['sha256']:
            raise RuntimeError('IPA model hash differs from the reviewed Android model')
        for notice in manifest['rights']['notices']:
            if package.read(prefix + Path(notice).name) != (Path(root)/notice).read_bytes():
                raise RuntimeError('IPA is missing the actual license/model notices')
        if not package.read(prefix + 'SOURCE-COMMIT.txt').strip():
            raise RuntimeError('IPA must identify corresponding source commit')


if __name__ == '__main__':
    import sys
    validate()
    if len(sys.argv) == 2:
        validate_ipa(sys.argv[1])
    print('Pinned bird ONNX, functional-test label, source/notices and research-use record verified; formal qualification remains false')
