"""Fail closed before a public IPA can contain unverified bird weights.

No weights are downloaded by this script. Converted package hash is a hash of
sorted relative file paths plus each file's SHA256, independent of timestamps.
"""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def package_digest(package):
    digest = hashlib.sha256()
    for path in sorted(p for p in package.rglob('*') if p.is_file()):
        digest.update(path.relative_to(package).as_posix().encode() + b'\0')
        digest.update(hashlib.sha256(path.read_bytes()).digest())
    return digest.hexdigest()

def validate(package, manifest):
    if manifest.get('redistribution_verified') is not True or not manifest.get('evidence'):
        raise RuntimeError('Bird model redistribution evidence is unresolved; public model IPA blocked')
    if not package.is_dir():
        raise RuntimeError('BirdEyePose.mlpackage is absent; cannot claim a complete bird-eye IPA')
    if package_digest(package) != manifest.get('converted_package_sha256'):
        raise RuntimeError('Converted bird package digest does not match the reviewed manifest')
    if manifest.get('independent_images_evaluated', 0) < 100 or not manifest.get('accuracy_report'):
        raise RuntimeError('Independent 100-image bird evaluation is incomplete')
    if not manifest.get('device_report'):
        raise RuntimeError('iPhone bird-eye latency and sustained-use evaluation is incomplete')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package', type=Path, default=ROOT/'R6Camera/Resources/BirdEyePose.mlpackage')
    args = parser.parse_args()
    validate(args.package, json.loads((ROOT/'docs/bird-release.json').read_text()))
    print('Bird release evidence and package digest verified')

if __name__ == '__main__':
    main()
