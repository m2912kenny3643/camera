"""Opt-in, private bird-pose conversion research; never copies a model into app resources.

Use an ephemeral macOS arm64 job with Python 3.11 and no credentials/secrets:
  python -m pip install torch==2.7.0 torchvision==0.22.0 ultralytics==8.4.67 \
      coremltools==9.0 numpy==1.26.4 opencv-python==4.11.0.86
  R6_BIRD_PERSONAL_RESEARCH=1 python scripts/research_bird_export.py --convert

Default invocation only verifies/downloads bytes and statically inspects pickle opcodes.
Conversion uses a fixed source-audited global allowlist and weights_only=True; there is
no fallback to a permissive loader. Source audit references are in the research note.
Only build/bird-research.log contains publishable descriptors/metrics. All model and
checkpoint paths stay under ignored build/research/bird-eye; never upload that folder.
Synthetic-input parity measures conversion error, NOT bird localization accuracy.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib
import importlib.metadata
import json
import os
from pathlib import Path
import pickletools
import platform
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / "build/research/bird-eye"
LOG = ROOT / "build/bird-research.log"
REVISION = "6e7bd361ba84b17d81f0fb4315a44a868df5b692"
SHA256 = "ec9e4b80a93eb6e2b21633e2ff2df30c49faa1eb7919dd24345c7dc295b2d1be"
LENGTH = 5_654_984
URL = f"https://huggingface.co/synthet/eye-pose-v0/resolve/{REVISION}/eye_pose_v0.pt"
PACKAGES = {
    "torch": "2.7.0", "torchvision": "0.22.0", "ultralytics": "8.4.67",
    "coremltools": "9.0", "numpy": "1.26.4", "opencv-python": "4.11.0.86",
}

# Exact GLOBAL opcodes found in the hash-pinned checkpoint. Unknown globals fail closed.
# Audited Ultralytics classes inherit nn.Module.__setstate__; no custom unpickle hook.
MODULE_CLASSES = {
    "torch.nn.modules.activation.SiLU", "torch.nn.modules.batchnorm.BatchNorm2d",
    "torch.nn.modules.container.ModuleList", "torch.nn.modules.container.Sequential",
    "torch.nn.modules.conv.Conv2d", "torch.nn.modules.linear.Identity",
    "torch.nn.modules.pooling.MaxPool2d", "torch.nn.modules.upsampling.Upsample",
    "ultralytics.nn.modules.block.Attention", "ultralytics.nn.modules.block.Bottleneck",
    "ultralytics.nn.modules.block.C2PSA", "ultralytics.nn.modules.block.C3k",
    "ultralytics.nn.modules.block.C3k2", "ultralytics.nn.modules.block.DFL",
    "ultralytics.nn.modules.block.PSABlock", "ultralytics.nn.modules.block.SPPF",
    "ultralytics.nn.modules.conv.Concat", "ultralytics.nn.modules.conv.Conv",
    "ultralytics.nn.modules.conv.DWConv", "ultralytics.nn.modules.head.Pose",
    "ultralytics.nn.tasks.PoseModel",
}
DEFAULT_GLOBALS = {
    "__builtin__.set", "collections.OrderedDict", "torch.FloatStorage",
    "torch.HalfStorage", "torch.LongStorage", "torch.Size",
    "torch._utils._rebuild_parameter", "torch._utils._rebuild_tensor_v2",
}


def report(event: str, **values):
    line = json.dumps({"event": event, **values}, sort_keys=True)
    print(line, flush=True)
    LOG.parent.mkdir(parents=True, exist_ok=True)
    with LOG.open("a", encoding="utf-8") as stream:
        stream.write(line + "\n")


def inspect_checkpoint() -> Path:
    WORK.mkdir(parents=True, exist_ok=True)
    path = WORK / "eye_pose_v0.pt"
    if not path.exists():
        request = urllib.request.Request(URL, headers={"User-Agent": "R6Camera-private-research/1"})
        with urllib.request.urlopen(request, timeout=90) as response:
            data = response.read(LENGTH + 1)
        if len(data) != LENGTH or hashlib.sha256(data).hexdigest() != SHA256:
            raise RuntimeError("Checkpoint length/hash mismatch; refusing to save or load")
        path.write_bytes(data)
    data = path.read_bytes()
    if len(data) != LENGTH or hashlib.sha256(data).hexdigest() != SHA256:
        raise RuntimeError("Local checkpoint length/hash mismatch; refusing to load")
    with zipfile.ZipFile(path) as archive:
        entries = archive.infolist()
        if sum(entry.file_size for entry in entries) > 25_000_000:
            raise RuntimeError("Unexpected uncompressed checkpoint size")
        pickle_members = [entry for entry in entries if entry.filename.endswith("/data.pkl")]
        if len(pickle_members) != 1 or pickle_members[0].file_size > 250_000:
            raise RuntimeError("Unexpected checkpoint pickle layout")
        seen = set()
        for opcode, argument, _ in pickletools.genops(archive.read(pickle_members[0])):
            if opcode.name == "GLOBAL":
                module, name = argument.split(" ", 1)
                seen.add(f"{module}.{name}")
            elif opcode.name in {"STACK_GLOBAL", "EXT1", "EXT2", "EXT4", "INST", "OBJ"}:
                raise RuntimeError(f"Unreviewed pickle opcode {opcode.name}")
        unknown = seen - MODULE_CLASSES - DEFAULT_GLOBALS
        if unknown:
            raise RuntimeError(f"Unreviewed checkpoint globals: {sorted(unknown)}")
    report("checkpoint_verified", revision=REVISION, sha256=SHA256, bytes=LENGTH,
           global_count=len(seen), loaded=False)
    return path


def convert_and_compare(path: Path):
    if os.environ.get("R6_BIRD_PERSONAL_RESEARCH") != "1":
        raise RuntimeError("Conversion requires explicit R6_BIRD_PERSONAL_RESEARCH=1")
    if platform.system() != "Darwin":
        raise RuntimeError("Core ML prediction/parity research requires macOS")
    versions = {name: importlib.metadata.version(name) for name in PACKAGES}
    if versions != PACKAGES:
        raise RuntimeError(f"Unreviewed package versions: {versions}; expected {PACKAGES}")
    # Disable dependency auto-install and any permissive secondary checkpoint loading.
    os.environ["YOLO_CONFIG_DIR"] = str(WORK / "config")
    os.environ["YOLO_AUTOINSTALL"] = "false"
    os.environ["ULTRALYTICS_SAFE_LOAD"] = "1"
    os.environ["TORCH_FORCE_WEIGHTS_ONLY_LOAD"] = "1"
    import torch
    import numpy as np
    import coremltools as ct
    from PIL import Image
    from ultralytics.engine.exporter import Exporter
    from ultralytics.nn.tasks import PoseModel

    # No autodiscovery or adding checkpoint-requested globals. Resolve only this fixed list.
    classes = []
    for qualified in sorted(MODULE_CLASSES):
        module, name = qualified.rsplit(".", 1)
        klass = getattr(importlib.import_module(module), name)
        if not isinstance(klass, type) or not issubclass(klass, torch.nn.Module):
            raise RuntimeError(f"Allowlisted symbol is not a known nn.Module: {qualified}")
        classes.append(klass)
    unsupported = set(torch.serialization.get_unsafe_globals_in_checkpoint(path)) - MODULE_CLASSES - {"builtins.set"}
    if unsupported:
        raise RuntimeError(f"Restricted loader requested unreviewed globals: {sorted(unsupported)}")
    with torch.serialization.safe_globals([set, *classes]):
        checkpoint = torch.load(path, map_location="cpu", weights_only=True)
    model = checkpoint.get("model") if isinstance(checkpoint, dict) else None
    if type(model) is not PoseModel:
        raise RuntimeError("Checkpoint is not the expected exact PoseModel class")
    allowed_types = set(classes)
    for layer in model.modules():
        if type(layer) not in allowed_types:
            raise RuntimeError(f"Unexpected module class: {type(layer)}")
        # Checkpoints may hold module state, not instance-method overrides or executable hooks.
        if any(callable(value) for value in layer.__dict__.values()):
            raise RuntimeError("Unexpected callable in checkpoint module instance state")
        for name, value in layer.__dict__.items():
            if "hook" in name and isinstance(value, dict) and value:
                raise RuntimeError(f"Unexpected registered checkpoint hook: {name}")
    head = model.model[-1]
    if head.nc != 1 or list(head.kpt_shape) != [6, 3] or model.names != {0: "bird"}:
        raise RuntimeError("Checkpoint's actual pose schema differs from the researched contract")
    parameters = sum(value.numel() for value in model.parameters())
    if not 1_000_000 <= parameters <= 5_000_000:
        raise RuntimeError(f"Unexpected model size: {parameters}")
    if not all(torch.isfinite(value).all().item() for value in model.parameters()):
        raise RuntimeError("Non-finite checkpoint parameters")
    # Sanitize metadata; do not let checkpoint-supplied file paths become exporter destinations.
    model.pt_path = str(path)
    model.yaml = {"channels": 3, "yaml_file": "eye_pose_v0.yaml"}
    model.args = {"model": str(path), "data": "bird-personal-research"}
    model.task = "pose"
    model = model.cpu().float().eval()
    report("restricted_load_verified", packages=versions, parameters=parameters, keypoints=[6, 3],
           weight_license=checkpoint.get("license"), loaded=True)
    torch.set_num_threads(2)
    exporter = Exporter(overrides={"format": "coreml", "imgsz": 640, "batch": 1,
                                   "dynamic": False, "nms": False, "half": False,
                                   "int8": False, "device": "cpu", "verbose": False})
    exported = Path(exporter(model=model)).resolve()
    if WORK.resolve() not in exported.parents:
        raise RuntimeError("Exporter wrote outside ignored research directory")
    converted = ct.models.MLModel(str(exported), compute_units=ct.ComputeUnit.CPU_ONLY)
    spec = converted.get_spec()
    def describe(feature):
        kind = feature.type.WhichOneof("Type")
        result = {"name": feature.name, "kind": kind}
        if kind == "multiArrayType":
            result.update(shape=list(feature.type.multiArrayType.shape), dtype=int(feature.type.multiArrayType.dataType))
        elif kind == "imageType":
            result.update(width=feature.type.imageType.width, height=feature.type.imageType.height,
                          color_space=int(feature.type.imageType.colorSpace))
        return result
    inputs = [describe(feature) for feature in spec.description.input]
    outputs = [describe(feature) for feature in spec.description.output]
    report("coreml_descriptors", inputs=inputs, outputs=outputs)
    if len(inputs) != 1 or inputs[0].get("width") != 640 or inputs[0].get("height") != 640:
        raise RuntimeError("Unexpected Core ML input descriptor")
    matching_outputs = [value for value in outputs if value.get("shape") == [1, 23, 8400]]
    if len(matching_outputs) != 1:
        raise RuntimeError("Expected exactly one [1,23,8400] pose multi-array")
    input_name, output_name = inputs[0]["name"], matching_outputs[0]["name"]
    gray = np.full((640, 640, 3), 114, dtype=np.uint8)
    ramp = np.linspace(0, 255, 640, dtype=np.uint8)
    gradient = np.stack(np.broadcast_arrays(ramp[None, :], ramp[:, None], np.full((640, 640), 114, dtype=np.uint8)), axis=-1)
    noise = np.random.default_rng(42).integers(0, 256, (640, 640, 3), dtype=np.uint8)
    coordinate_channels = [0, 1, 2, 3] + [5 + 3 * i + offset for i in range(6) for offset in [0, 1]]
    probability_channels = [4] + [7 + 3 * i for i in range(6)]
    passed = True
    for name, image in [("gray", gray), ("gradient", gradient), ("seeded_noise", noise)]:
        tensor = torch.from_numpy(np.ascontiguousarray(image.transpose(2, 0, 1))).unsqueeze(0).float() / 255
        with torch.inference_mode():
            original = model(tensor)
            reference = (original[0] if isinstance(original, tuple) else original).detach().cpu().numpy()
        prediction = np.asarray(converted.predict({input_name: Image.fromarray(image)})[output_name])
        if reference.shape != prediction.shape or not np.isfinite(prediction).all():
            raise RuntimeError(f"Invalid parity result for {name}")
        difference = np.abs(reference.astype(np.float32) - prediction.astype(np.float32))
        pixel_max = float(difference[:, coordinate_channels, :].max())
        probability_max = float(difference[:, probability_channels, :].max())
        within_tolerance = pixel_max <= 5 and probability_max <= 0.03
        passed &= within_tolerance
        report("synthetic_parity", fixture=name, shape=list(prediction.shape),
               mean_abs=float(difference.mean()), max_pixel_abs=pixel_max,
               max_probability_abs=probability_max, within_research_tolerance=within_tolerance)
    report("research_complete", converted=True, synthetic_parity_passed=passed,
           localization_accuracy_tested=False, iphone_performance_tested=False,
           model_artifact_uploaded=False)
    if not passed:
        raise RuntimeError("Synthetic conversion parity exceeded research tolerance")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--convert", action="store_true", help="Explicit personal-only macOS conversion/parity experiment")
    args = parser.parse_args()
    LOG.parent.mkdir(parents=True, exist_ok=True)
    LOG.write_text("", encoding="utf-8")
    path = inspect_checkpoint()
    if args.convert:
        convert_and_compare(path)
    else:
        report("inspect_only", converted=False)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        report("research_failed", error_type=type(error).__name__, message=str(error))
        raise SystemExit(1)
