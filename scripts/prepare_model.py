"""Fetch Apple's model at build time; bundle it for fully offline runtime inference."""
from pathlib import Path
import hashlib
import json
import os
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
MODEL_URL = "https://ml-assets.apple.com/coreml/models/Image/ObjectDetection/YOLOv3Tiny/YOLOv3TinyInt8LUT.mlmodel"
TARGET = ROOT / "R6Camera/Resources/YOLOv3TinyInt8LUT.mlmodel"
MODEL_SHA256 = "cde8af2528d6eca1d1580fdd0f0147cb6613d40ba962656b5f683c65f571870e"


def main():
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(MODEL_URL, headers={"User-Agent": "R6Camera-build/0.1"})
    with urllib.request.urlopen(request, timeout=120) as response:
        payload = response.read(30 * 1024 * 1024)
    if not 1_000_000 < len(payload) < 30 * 1024 * 1024:
        raise RuntimeError(f"Unexpected model size: {len(payload)}")
    if payload.lstrip().startswith((b"<", b"{")):
        raise RuntimeError("Model endpoint returned text instead of a model")
    digest = hashlib.sha256(payload).hexdigest()
    # Pinned to the official payload verified by the first Xcode build.
    expected = os.environ.get("MODEL_SHA256", MODEL_SHA256)
    if expected and digest != expected:
        raise RuntimeError(f"Model checksum mismatch: {digest}")
    TARGET.write_bytes(payload)
    provenance = {"url": MODEL_URL, "sha256": digest, "bytes": len(payload)}
    build = ROOT / "build"
    build.mkdir(exist_ok=True)
    (build / "model-provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
    print(json.dumps(provenance))


if __name__ == "__main__":
    main()
