"""Opt-in I-MuPPET research. No publisher code, permissive pickle, or app model copy.

Python 3.11/macOS: torch2.7.0, torchvision0.22.0, coremltools9.0, numpy1.26.4.
Only build/imuppet-research-report.json is publishable. Model bytes stay ignored.
Default: exact-byte retrieval/static audit only. --convert additionally requires
R6_BIRD_PERSONAL_RESEARCH=1. Synthetic parity is not bird accuracy evidence.
"""
from __future__ import annotations

import argparse
from collections import Counter, OrderedDict
import hashlib
import importlib.metadata
import io
import json
import os
from pathlib import Path, PurePosixPath
import pickletools
import platform
import time
import urllib.request
import zipfile
import zlib

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / "build/research/imuppet"
REPORT = ROOT / "build/imuppet-research-report.json"
URL = "https://zenodo.org/api/records/7037589/files/weights.zip/content"
START, COMPRESSED, TOTAL = 1094136243, 218642592, 1312779841
LENGTH, CRC = 236764912, 0x2CB9597D
SHA = "dab61b233202a4ee474d07d9c112a9f360b1c554bff37e4adec89a063d44cd1e"
COMPRESSED_SHA = "e780e90c0bae805761ff61f9eac63359722a3e75eecfbe90cb1a635575f51519"
PICKLE_SHA = "1fc6d806bc0a61757f4b71ce73baa36211b7abedd40ce0971269221e305d0c4e"
PACKAGES = {"torch": "2.7.0", "torchvision": "0.22.0", "coremltools": "9.0", "numpy": "1.26.4"}
GLOBALS = {"collections OrderedDict", "torch FloatStorage", "torch._utils _rebuild_tensor_v2"}
OPCODES = {"PROTO", "GLOBAL", "BINPUT", "EMPTY_TUPLE", "REDUCE", "MARK", "BINUNICODE",
           "BININT2", "TUPLE", "BINPERSID", "BININT1", "NEWFALSE", "BINGET", "TUPLE1",
           "LONG_BINPUT", "BININT", "TUPLE2", "SETITEMS", "EMPTY_DICT", "SETITEM", "LONG_BINGET", "BUILD", "STOP"}
HEAD_SHAPES = {
    "roi_heads.box_predictor.cls_score.weight": [2, 1024],
    "roi_heads.box_predictor.bbox_pred.weight": [8, 1024],
    "roi_heads.keypoint_predictor.kps_score_lowres.weight": [512, 7, 4, 4],
    "roi_heads.keypoint_predictor.kps_score_lowres.bias": [7],
}
OUTPUTS = ["boxes", "scores", "labels", "keypoints", "keypoints_scores"]
SMOKE_URL = "https://urs-waldmann.github.io/i-muppet/imgs/framework.jpg"
SMOKE_SHA = "b9d1970bf4a4a2c6f92c2173582c55e081a7bab4ac3f4dc04b46dbc34605bb91"
SMOKE_LENGTH = 225202


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def emit(report, event, **values):
    item = {"event": event, **values}
    report["events"].append(item)
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(report, indent=2, sort_keys=True, allow_nan=False), encoding="utf-8")
    print(json.dumps(item, sort_keys=True, allow_nan=False), flush=True)


def sha_file(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def publisher_smoke(report):
    """One unannotated photo panel in the publisher figure; never upload the image."""
    try:
        from PIL import Image
        import numpy as np
        with urllib.request.urlopen(SMOKE_URL, timeout=15) as response:
            data = response.read(SMOKE_LENGTH+1)
        require(len(data) == SMOKE_LENGTH and hashlib.sha256(data).hexdigest() == SMOKE_SHA,
                "Publisher smoke figure changed; refusing unpinned image")
        (WORK / "publisher-framework.jpg").write_bytes(data)
        with Image.open(io.BytesIO(data)) as image:
            require(image.size == (2244, 472), "Unexpected publisher figure dimensions")
            # The left input-photo panel, excluding diagram text, arrows and predictions.
            crop = image.convert("RGB").crop((34, 34, 354, 354)).resize((640, 640), Image.Resampling.BILINEAR)
            value = np.asarray(crop, dtype=np.float32).transpose(2, 0, 1)[None].copy()/255.0
        emit(report, "publisher_smoke_available", source=SMOKE_URL, bytes=SMOKE_LENGTH,
             sha256=SMOKE_SHA, crop_xyxy=[34, 34, 354, 354], training=False, uploaded=False,
             independent_accuracy_fixture=False, photo_redistribution_permission_established=False)
        return value
    except Exception as error:
        emit(report, "publisher_smoke_unavailable", error=str(error)[:1000],
             positive_coverage_pending=True, continue_conversion_probe=True)
        return None


def retrieve(path, report):
    if path.exists():
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    partial = path.with_suffix(".partial")
    for attempt in range(1, 4):
        try:
            request = urllib.request.Request(URL, headers={
                "Range": f"bytes={START}-{START+COMPRESSED-1}", "Accept-Encoding": "identity",
                "User-Agent": "R6Camera-imuppet-research/0.5"})
            compressed_hash, checkpoint_hash = hashlib.sha256(), hashlib.sha256()
            decoder = zlib.decompressobj(-15)
            received = size = crc = 0
            with urllib.request.urlopen(request, timeout=30) as response:
                require(response.status == 206, "Server ignored Range; full archive refused")
                require(response.headers.get("Content-Range") == f"bytes {START}-{START+COMPRESSED-1}/{TOTAL}", "Changed archive/Range")
                require(int(response.headers.get("Content-Length", COMPRESSED)) == COMPRESSED, "Unexpected response length")
                last_progress = time.monotonic()
                with partial.open("wb") as output:
                    while received < COMPRESSED:
                        block = response.read(min(1024*1024, COMPRESSED-received))
                        require(bool(block), "Truncated response")
                        received += len(block); compressed_hash.update(block)
                        data = decoder.decompress(block, LENGTH-size+1)
                        size += len(data)
                        require(size <= LENGTH and not decoder.unconsumed_tail, "Oversized decompressed checkpoint")
                        output.write(data); crc = zlib.crc32(data, crc); checkpoint_hash.update(data)
                        if time.monotonic()-last_progress > 30:
                            print(json.dumps({"event": "download_progress", "bytes": received, "total": COMPRESSED}), flush=True)
                            last_progress = time.monotonic()
            require(decoder.eof and not decoder.unused_data, "Invalid deflate boundary")
            require(size == LENGTH and crc == CRC, "Length/ZIP CRC mismatch")
            require(checkpoint_hash.hexdigest() == SHA and compressed_hash.hexdigest() == COMPRESSED_SHA, "Pinned SHA-256 mismatch")
            partial.rename(path)
            emit(report, "retrieval_passed", attempt=attempt, bytes=size, sha256=SHA, crc32=f"{crc:08x}")
            return
        except Exception as error:
            emit(report, "retrieval_attempt_failed", attempt=attempt, error=str(error)[:1000])
            if attempt == 3:
                raise


def inspect(path, report):
    require(path.stat().st_size == LENGTH and sha_file(path) == SHA, "Untrusted checkpoint bytes")
    with zipfile.ZipFile(path) as archive:
        entries = archive.infolist()
        require(len(entries) == 315 and len({x.filename for x in entries}) == 315, "Unexpected ZIP entries")
        require(sum(x.file_size for x in entries) < 240_000_000, "Unexpected ZIP budget")
        for entry in entries:
            member = PurePosixPath(entry.filename)
            require(not member.is_absolute() and ".." not in member.parts and "\\" not in entry.filename,
                    "Unsafe ZIP path")
            require(entry.filename.startswith("archive/") and not entry.flag_bits & 1, "Unexpected/encrypted ZIP member")
        require(archive.testzip() is None, "Inner ZIP CRC mismatch")
        data = archive.read("archive/data.pkl")
        require(len(data) == 55460 and hashlib.sha256(data).hexdigest() == PICKLE_SHA, "Changed pickle structure")
        seen, counts, last = set(), Counter(), None
        for opcode, argument, position in pickletools.genops(data):
            require(opcode.name in OPCODES, f"Unreviewed opcode {opcode.name}")
            counts[opcode.name] += 1; last = (opcode.name, position)
            if opcode.name == "GLOBAL":
                require(argument in GLOBALS, f"Unreviewed GLOBAL {argument}")
                seen.add(argument)
        require(seen == GLOBALS and last == ("STOP", len(data)-1), "Incomplete pickle audit")
        storages = [x for x in entries if x.filename.startswith("archive/data/")]
        require(len(storages) == 313 and sum(x.file_size for x in storages) == 236646272, "Storage budget mismatch")
    emit(report, "static_audit_passed", sha256=SHA, pickle_sha256=PICKLE_SHA,
         globals=sorted(seen), opcode_counts=dict(counts), tensors=313, tensor_elements=59161568,
         loaded=False, source="https://zenodo.org/records/7037589", weights_license="CC-BY-4.0")


def compare(reference, actual, report, event, case):
    import numpy as np
    metrics, passed = {}, True
    for name, before, after in zip(OUTPUTS, reference, actual):
        before, after = np.asarray(before), np.asarray(after)
        same_shape = before.shape == after.shape
        finite = bool(np.isfinite(before).all() and np.isfinite(after).all())
        error = float(np.max(np.abs(before-after))) if same_shape and finite and before.size else (0.0 if same_shape and finite else None)
        tolerance = 0.01 if name in {"boxes", "keypoints"} else 0.001 if name == "keypoints_scores" else 0.0001
        okay = same_shape and finite and error is not None and (np.array_equal(before, after) if name == "labels" else error <= tolerance)
        metrics[name] = {"reference_shape": list(before.shape), "actual_shape": list(after.shape),
                         "max_absolute_error": error, "tolerance": 0 if name == "labels" else tolerance, "passed": bool(okay)}
        passed = passed and okay
    emit(report, event, case=case, passed=bool(passed), outputs=metrics)
    require(passed, f"{event} failed for {case}; tolerances unchanged")


def onnx_probe(wrapper, inputs, references, export_case, positive_coverage, report):
    import numpy as np
    import torch
    import onnx
    import onnxruntime as ort
    destination = WORK / "imuppet-full-rcnn.onnx"
    emit(report, "onnx_export_started", case=export_case, opset=17, dynamo=False,
         dynamic_output_instance_axes=True, rpn_roi_nms_removed=False)
    torch.onnx.export(wrapper, (torch.from_numpy(inputs[export_case]),), str(destination),
                      dynamo=False, opset_version=17, input_names=["image_tensor"], output_names=OUTPUTS,
                      dynamic_axes={name: {0: "instances"} for name in OUTPUTS}, external_data=False)
    model = onnx.load(str(destination), load_external_data=False)
    require(all(t.data_location != onnx.TensorProto.EXTERNAL for t in model.graph.initializer),
            "Unexpected external ONNX tensor data")
    onnx.checker.check_model(model, full_check=True)
    operators = Counter()

    def visit(nodes):
        for node in nodes:
            operators[f"{node.domain or 'ai.onnx'}::{node.op_type}"] += 1
            for attribute in node.attribute:
                if attribute.type == onnx.AttributeProto.GRAPH:
                    visit(attribute.g.node)
                elif attribute.type == onnx.AttributeProto.GRAPHS:
                    for graph in attribute.graphs:
                        visit(graph.node)

    visit(model.graph.node)
    for function in model.functions:
        visit(function.node)
    emit(report, "onnx_checker_passed", model_sha256=sha_file(destination), model_bytes=destination.stat().st_size,
         ir_version=model.ir_version, opsets={x.domain or "ai.onnx": x.version for x in model.opset_import},
         complete_operator_counts=dict(sorted(operators.items())), model_uploaded=False)
    require(operators["ai.onnx::RoiAlign"] > 0 and operators["ai.onnx::NonMaxSuppression"] > 0,
            "Full RCNN export lacks required RoiAlign/NMS; no operator-removal workaround allowed")
    del model
    options = ort.SessionOptions()
    options.intra_op_num_threads = 2
    options.inter_op_num_threads = 1
    options.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
    started = time.monotonic()
    session = ort.InferenceSession(str(destination), sess_options=options, providers=["CPUExecutionProvider"])
    require(session.get_providers() == ["CPUExecutionProvider"], "Unexpected execution provider")
    emit(report, "ort_cpu_session_created", initialization_seconds=time.monotonic()-started,
         providers=session.get_providers(), machine=platform.machine(), operating_system=platform.system(),
         input_descriptors=[{"name": x.name, "shape": x.shape, "type": x.type} for x in session.get_inputs()],
         output_descriptors=[{"name": x.name, "shape": x.shape, "type": x.type} for x in session.get_outputs()],
         intra_op_threads=2, inter_op_threads=1, iphone_performance=False)
    for name, value in inputs.items():
        session.run(OUTPUTS, {"image_tensor": value})  # One explicit warm-up per case.
        timings = []
        for _ in range(3):
            started = time.monotonic()
            actual = session.run(OUTPUTS, {"image_tensor": value})
            timings.append((time.monotonic()-started)*1000)
        compare(references[name], actual, report, "onnx_cpu_parity", name)
        emit(report, "mac_cpu_latency", case=name, milliseconds=timings,
             median_ms=float(np.median(timings)), maximum_observed_ms=max(timings),
             warmup_calls=1, measured_calls=3, includes_image_preprocessing=False,
             includes_model_resize_rpn_roi_nms=True, iphone_performance=False)
    require(positive_coverage, "empty-positive-coverage: ONNX CPU probe completed without a nonempty publisher pigeon case; full RCNN validation remains incomplete")
    emit(report, "experiment_passed", backend="onnx_cpu", publisher_pigeon_nonempty=True,
         bird_accuracy_evaluated=False, device_latency_evaluated=False, bundled=False)


def convert(path, report, use_onnx=False):
    require(os.environ.get("R6_BIRD_PERSONAL_RESEARCH") == "1", "Explicit opt-in environment required")
    require(platform.system() == "Darwin", "This runtime feasibility experiment is scoped to macOS")
    packages = {name: version for name, version in PACKAGES.items() if name != "coremltools"}
    packages.update({"onnx": "1.17.0", "onnxruntime": "1.22.0"} if use_onnx else {"coremltools": "9.0"})
    for name, version in packages.items():
        require(importlib.metadata.version(name).split("+")[0] == version, f"Pin required: {name}=={version}")
    os.environ["TORCH_FORCE_WEIGHTS_ONLY_LOAD"] = "1"
    import numpy as np
    import torch
    import torchvision
    torch.set_num_threads(2)
    torch.manual_seed(0)
    torch.serialization.clear_safe_globals()
    emit(report, "strict_load_started", weights_only=True, map_location="cpu", strict=True)
    state = torch.load(path, map_location="cpu", weights_only=True)
    require(type(state) is OrderedDict and len(state) == 313, "Expected exact plain state_dict")
    require(all(type(t) is torch.Tensor and t.dtype == torch.float32 and t.device.type == "cpu" for t in state.values()), "Unexpected tensor type/dtype/device")
    require(sum(t.numel() for t in state.values()) == 59161568, "Parameter budget mismatch")
    require(all(torch.isfinite(t).all().item() for t in state.values()), "Nonfinite checkpoint tensor")
    for key, shape in HEAD_SHAPES.items():
        require(list(state[key].shape) == shape, f"Unexpected shape: {key}")
    # Match the author's pretrained_backbone=True normalization policy without
    # downloading ImageNet weights. The all-None factory would select plain BN.
    from torchvision.models.detection.backbone_utils import resnet_fpn_backbone
    from torchvision.ops.misc import FrozenBatchNorm2d
    backbone = resnet_fpn_backbone(backbone_name="resnet50", weights=None,
                                  norm_layer=FrozenBatchNorm2d, trainable_layers=0)
    model = torchvision.models.detection.KeypointRCNN(backbone, num_classes=2, num_keypoints=7)
    frozen_norms = [module for module in model.modules() if type(module) is FrozenBatchNorm2d]
    require(len(frozen_norms) == 53 and not any(isinstance(module, torch.nn.BatchNorm2d) for module in model.modules()),
            "Unexpected backbone normalization architecture")
    emit(report, "normalization_architecture", normalization="torchvision.ops.misc.FrozenBatchNorm2d",
         count=len(frozen_norms), eps=sorted({float(module.eps) for module in frozen_norms}),
         external_weights=None, trainable_layers=0, ordinary_batch_norm_count=0)
    # Preserve OrderedDict._metadata so torchvision's versioned FPN/RPN migrations run.
    incompatible = model.load_state_dict(state, strict=True)
    require(not incompatible.missing_keys and not incompatible.unexpected_keys, "Strict loading did not match")
    model.cpu().float().eval()
    emit(report, "strict_load_passed", tensor_count=len(state), elements=59161568,
         head_shapes=HEAD_SHAPES, missing_keys=[], unexpected_keys=[],
         checkpoint_metadata_preserved=True, publisher_code_executed=False, packages=packages,
         normalization="torchvision.ops.misc.FrozenBatchNorm2d", frozen_norm_count=len(frozen_norms),
         frozen_norm_eps=sorted({float(module.eps) for module in frozen_norms}),
         external_weights=None, backbone_trainable_layers=0)
    del state

    class FullRCNN(torch.nn.Module):
        def __init__(self, network):
            super().__init__(); self.network = network

        def forward(self, image):
            # Publisher's non-COCO video path applies Normalize(0.5, 0.5)
            # before the detector's own transform; the single-image helper alone omits it.
            prediction = self.network([(image[0] - 0.5) / 0.5])[0]
            return tuple(prediction[name] for name in OUTPUTS)

    wrapper = FullRCNN(model).eval()
    emit(report, "publisher_preprocessing", external_input="RGB float32 0..1 NCHW",
         before_detector="(image - 0.5) / 0.5", detector_internal_transform_retained=True,
         source="https://github.com/urs-waldmann/i-muppet/blob/a8588a792bd98dfc1513abcf809bfbdb40e30918/utils/video_stream_utils.py")
    rng = np.random.default_rng(7)
    gradient = np.broadcast_to(np.linspace(0, 1, 640, dtype=np.float32), (1, 3, 640, 640)).copy()
    inputs = {"gray": np.full((1, 3, 640, 640), 0.5, dtype=np.float32),
              "gradient": gradient, "noise": rng.random((1, 3, 640, 640), dtype=np.float32)}
    smoke = publisher_smoke(report)
    if smoke is not None:
        inputs["publisher_pigeon"] = smoke
    references = {}
    with torch.inference_mode():
        for name, value in inputs.items():
            emit(report, "standard_inference_started", case=name)
            started = time.monotonic()
            prediction = wrapper(torch.from_numpy(value))
            count = prediction[0].shape[0]
            require([tuple(t.shape) for t in prediction] == [(count, 4), (count,), (count,), (count, 7, 3), (count, 7)],
                    "Unexpected standard inference output contract")
            require(all(torch.isfinite(t).all().item() for t in prediction), "Nonfinite standard inference output")
            references[name] = [x.cpu().numpy() for x in prediction]
            emit(report, "standard_inference_passed", case=name, elapsed_seconds=time.monotonic()-started,
                 outputs={key: {"shape": list(t.shape), "dtype": str(t.dtype), "finite": bool(torch.isfinite(t).all())} for key,t in zip(OUTPUTS,prediction)},
                 accuracy_evaluated=False)
        nonempty = [name for name, values in references.items() if values[0].shape[0] > 0]
        positive_coverage = "publisher_pigeon" in nonempty
        emit(report, "positive_output_coverage", nonempty_cases=nonempty,
             publisher_pigeon_nonempty=positive_coverage,
             limitation=None if positive_coverage else "empty-positive-coverage: no nonempty verified publisher pigeon input",
             continue_conversion_probe=True)
        trace_case = "publisher_pigeon" if positive_coverage else nonempty[0] if nonempty else "gray"
        if use_onnx:
            onnx_probe(wrapper, inputs, references, trace_case, positive_coverage, report)
            return
        emit(report, "full_trace_started", case=trace_case, check_trace=False, explicit_all_input_parity=True)
        traced = torch.jit.trace(wrapper, torch.from_numpy(inputs[trace_case]), strict=True, check_trace=False)
        operators = sorted(set(node.kind() for node in traced.inlined_graph.nodes()))
        emit(report, "full_trace_created", operators=operators, rpn_roi_nms_removed=False)
        traced.save(str(WORK / "imuppet-full-rcnn.pt"))
        for name, value in inputs.items():
            actual = [x.cpu().numpy() for x in traced(torch.from_numpy(value))]
            compare(references[name], actual, report, "trace_parity", name)
    # Keep the entire detector graph. Unsupported necessary ops fail with a real blocker.
    import coremltools as ct
    emit(report, "coreml_conversion_started", compute_precision="FLOAT32", full_rcnn=True)
    converted = ct.convert(traced, convert_to="mlprogram", minimum_deployment_target=ct.target.iOS18,
                           inputs=[ct.TensorType(name="image_tensor", shape=(1, 3, 640, 640))],
                           outputs=[ct.TensorType(name=name) for name in OUTPUTS],
                           compute_precision=ct.precision.FLOAT32, compute_units=ct.ComputeUnit.CPU_ONLY,
                           skip_model_load=True)
    destination = WORK / "imuppet-full-rcnn.mlpackage"
    converted.save(str(destination))
    spec = converted.get_spec()
    emit(report, "coreml_export_passed", inputs=[str(x) for x in spec.description.input],
         outputs=[str(x) for x in spec.description.output], bundled=False)
    runtime = ct.models.MLModel(str(destination), compute_units=ct.ComputeUnit.CPU_ONLY)
    for name, value in inputs.items():
        prediction = runtime.predict({"image_tensor": value})
        compare(references[name], [prediction[key] for key in OUTPUTS], report, "coreml_parity", name)
    require(positive_coverage, "empty-positive-coverage: numeric conversion probe completed without a nonempty publisher pigeon case; full RCNN validation remains incomplete")
    emit(report, "experiment_passed", publisher_pigeon_nonempty=True,
         bird_accuracy_evaluated=False, device_latency_evaluated=False, bundled=False)


def main():
    parser = argparse.ArgumentParser()
    backend = parser.add_mutually_exclusive_group()
    backend.add_argument("--convert", action="store_true", help="Full Core ML probe (existing default conversion path)")
    backend.add_argument("--onnx-probe", action="store_true", help="Full ONNX/ORT CPU probe; no Core ML conversion")
    parser.add_argument("--checkpoint", type=Path, default=WORK / "muppet_600.pt")
    args = parser.parse_args()
    WORK.mkdir(parents=True, exist_ok=True)
    report = {"candidate": "imuppet", "checkpoint_sha256": SHA, "events": [],
              "accuracy_claim": False, "app_integration": False,
              "backend": "onnx_cpu" if args.onnx_probe else "coreml"}
    stage = "retrieval"
    try:
        retrieve(args.checkpoint, report)
        stage = "static_audit"; inspect(args.checkpoint, report)
        if args.convert or args.onnx_probe:
            stage = "strict_load_inference_onnx_cpu" if args.onnx_probe else "strict_load_inference_trace_coreml"
            convert(args.checkpoint, report, use_onnx=args.onnx_probe)
    except Exception as error:
        emit(report, "experiment_blocked", stage=stage, error_type=type(error).__name__,
             error=str(error)[:6000], no_operator_removal=True, no_permissive_load_retry=True)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
