# Bird eye and head localization feasibility

## Actual macOS experiments

[Research run 39702376853](https://github.com/m2912kenny3643/camera/actions/runs/39702376853) successfully loaded the hash-pinned checkpoint through the restricted weights-only loader and exported Core ML. Measured input is RGB image `image`, 640×640; measured output is float32 `var_1345`, shape `[1,23,8400]`. The checkpoint has 2,672,601 parameters. No model was published or added to the app.

Initial synthetic parity failed the unchanged 5-pixel / 0.03 probability gates: gray 36.5184 / 0.16813; gradient 9.24063 / 0.04521; noise 7.94821 / 0.05574. Ultralytics' Core ML helper omits compute_precision, so ML Program defaults to FP16 even when half=False. The next experiment explicitly requests FLOAT32 compute and compares original PyTorch, export-prepared PyTorch, and Core ML independently. A successful export is not sufficient to enable bird-eye AF; real image accuracy and iPhone performance remain untested.

**FLOAT32 result:** [Research run 39704478800](https://github.com/m2912kenny3643/camera/actions/runs/39704478800) passed all three comparisons (original→prepared, prepared→Core ML, original→Core ML) for gray, gradient and seeded-noise inputs, with unchanged gates. Actual float32 output is `pose_output`, shape [1,23,8400]. Original→Core ML maximum coordinate errors were 0.004242, 0.001160 and 0.000946 pixels respectively; maximum probability errors were about 0.00001013, 0.00000440 and 0.00000992. No weights/model artifact was uploaded. This validates conversion consistency only, not bird-eye accuracy or iPhone latency.

The user explicitly chose to deliver the other app fixes and research code first, with **no bird-eye model in this IPA**. Real-image accuracy, app integration and iPhone performance remain future work. The following source investigation is historical context; its previously unverified retrieval/export gates are superseded by the measured results above.

Checked: 2026-10-22 (Asia/Taipei). Model-source research; no app code or datasets changed. The checkpoint was downloaded into ignored `build/research/bird-eye/` for static inspection only. It was **not loaded, unpickled, executed, or exported**.

## Decision

The user approved **personal-only investigation/integration** of `synthet/eye-pose-v0`. Its actual checkpoint has now been obtained and hash-verified; the download-availability blocker is resolved. There is still no exported, parity-checked Core ML artifact or iPhone performance result. Keep genuine whole-bird fallback until those technical gates pass; do not describe a point derived from the bird box as an eye.

The checkpoint's own metadata identifies AGPL-3.0, despite an MIT tag in the publisher's model card. Personal-only approval does not establish unrestricted redistribution rights. No weights or publisher code were added to tracked/public source. Core ML export, actual exported output descriptors, inference parity and phone performance remain unverified.

## Candidates and evidence

### 1. synthet/eye-pose-v0: closest practical candidate, not release-ready

The publisher describes a YOLO11n-pose checkpoint fine-tuned on CUB-200-2011. Its documented output semantics are a full-bird box plus these six keypoints, in order: `beak`, `left_eye`, `right_eye`, `head_top`, `left_shoulder`, `right_shoulder`. The model card advertises `eye_pose_v0.pt` and a Hugging Face download command. It warns that distant field birds can differ from training images. These are publisher claims, not independently reproduced results. [Model card and download instructions](https://huggingface.co/synthet/eye-pose-v0/raw/main/README.md)

The publisher's pipeline selects one bird and filters boxes and points by confidence. Eye sharpness is a separate heuristic, not an additional model output. No published Core ML package was found. [Publisher pipeline](https://raw.githubusercontent.com/synthet/image-scoring-model/main/docs/architecture/PIPELINE.md)

**Weights availability — now verified:** Hugging Face's API returned an ungated public model at revision `6e7bd361ba84b17d81f0fb4315a44a868df5b692`. The revision-pinned checkpoint downloaded successfully (HTTP 200): **5,654,984 bytes**, SHA-256 **`ec9e4b80a93eb6e2b21633e2ff2df30c49faa1eb7919dd24345c7dc295b2d1be`**. This matches the publisher's LFS object hash and length. [Model API](https://huggingface.co/api/models/synthet/eye-pose-v0), [revision-pinned file metadata](https://huggingface.co/api/models/synthet/eye-pose-v0/tree/6e7bd361ba84b17d81f0fb4315a44a868df5b692?recursive=true&expand=true), [pinned checkpoint](https://huggingface.co/synthet/eye-pose-v0/resolve/6e7bd361ba84b17d81f0fb4315a44a868df5b692/eye_pose_v0.pt)

The ignored local directory contains `retrieval.json`, publisher metadata/card/schema files, the checkpoint, its ZIP index, and static opcode findings. No model-specific Python import was performed. The checkpoint is a PyTorch ZIP with a 165,687-byte `best/data.pkl` member; `zipfile` and `pickletools.genops` inspected its structure without executing pickle instructions. HF's scan includes expected PyTorch/Ultralytics global-class references, so it must not be treated as a plain safetensors file or casually unpickled in a privileged environment.

**Licence:** the card says MIT while declaring an Ultralytics YOLO11n-pose base. Static inspection finds the checkpoint's actual `license` string is **`AGPL-3.0 (https://ultralytics.com/license)`** and its recorded Ultralytics version is **8.4.67**. The HF file tree contains no standalone LICENSE file; requesting `/raw/main/LICENSE` returns 404. The related publisher project's `pyproject.toml` declares MIT, but a root LICENSE request also returned 404. These observations do not resolve rights in derived weights. Ultralytics describes AGPL-3.0/Enterprise licensing for its trained and fine-tuned models. [Pinned publisher card](https://huggingface.co/synthet/eye-pose-v0/raw/6e7bd361ba84b17d81f0fb4315a44a868df5b692/README.md), [publisher project metadata](https://raw.githubusercontent.com/synthet/image-scoring-model/20bae89a25d923c56466fb1a0421572ad291e4a0/pyproject.toml), [Ultralytics licensing position](https://www.ultralytics.com/license), [upstream code licence](https://raw.githubusercontent.com/ultralytics/ultralytics/v8.4.67/LICENSE)

The CUB dataset publisher restricts the source images to noncommercial research and education and does not own their copyrights. This does not by itself settle the legal status of resulting model weights, but it leaves provenance and intended distribution use unresolved. [Caltech dataset terms](https://www.vision.caltech.edu/datasets/cub_200_2011/)

**Static checkpoint contract — verified without loading:** `nc=1`, class name `0: bird`, `kpt_shape=[6,3]`, `nk=18`, three detection scales (`nl=3`), training `imgsz=640`, and model YAML name `yolo11n-pose.yaml`. The bundled `wildlife_bird.yaml` confirms keypoints `[beak,left_eye,right_eye,head_top,left_shoulder,right_shoulder]` and flip indices `[0,2,1,3,5,4]`. These are checkpoint/schema facts, not a successfully executed inference. [Pinned training schema](https://huggingface.co/synthet/eye-pose-v0/raw/6e7bd361ba84b17d81f0fb4315a44a868df5b692/wildlife_bird.yaml), [publisher keypoint contract](https://raw.githubusercontent.com/synthet/image-scoring-model/20bae89a25d923c56466fb1a0421572ad291e4a0/src/eye_quality/localization/keypoint_schema.py)

### Source-only Core ML export findings for this checkpoint

- Use the checkpoint-recorded **Ultralytics 8.4.67** as the initial compatibility target, with pinned PyTorch/coremltools versions. That exporter requires `coremltools>=9.0`, NumPy `<=2.3.5`, and macOS or Linux; it explicitly rejects Windows. A clean macOS conversion job is the appropriate next environment. [Versioned exporter, lines 1041–1084](https://github.com/ultralytics/ultralytics/blob/v8.4.67/ultralytics/engine/exporter.py#L1041)
- Recommended starting flags for a personal experiment are `format=coreml, imgsz=640, batch=1, dynamic=False, nms=False`. This is a proposed export configuration, **not a command that was run**. Static image export names its RGB input `image`, sets the input scale to `1/255`, and uses a `.mlpackage` ML Program. Pose `nms=True` does **not** produce the detection-style NMS pipeline; the exporter warns that Core ML NMS is only supported for detection models. [Exporter, lines 1065–1109](https://github.com/ultralytics/ultralytics/blob/v8.4.67/ultralytics/engine/exporter.py#L1065)
- Versioned `Pose._inference` appends decoded pose points to box/class output. Its exported point decoder returns six ordered `(x,y,visibility-score)` triples, with sigmoid applied to the third value. For a non-end-to-end 640-square, three-scale YOLO11 configuration, the **source-derived expected raw output** is `[1,23,8400]`: four box coordinates, one bird score and 18 keypoint values per anchor. This expected shape must be asserted against the actual exported artifact before implementing a decoder; it has not been measured. [Pose inference and point decoder, lines 608–658](https://github.com/ultralytics/ultralytics/blob/v8.4.67/ultralytics/nn/modules/head.py#L608)
- Export's non-end-to-end box coordinates use center-x/center-y/width/height in model input pixels; point coordinates are also model input pixels, not normalized full-camera coordinates. The app must filter bird scores, run its own NMS and undo the precise preprocessing transform. Use explicit, recorded 640-square letterboxing and invert padding/scale for boxes and points together; never mix raw-pixel points with Vision's lower-left normalized boxes. [Decode path, lines 179–216](https://github.com/ultralytics/ultralytics/blob/v8.4.67/ultralytics/nn/modules/head.py#L179)
- Output feature names are **not pinned by this Core ML helper**: `torch2coreml` calls `ct.convert` without supplying explicit output names. Inspect `modelDescription` after export and select/validate the actual multi-array feature by name and shape. Do not expect `VNRecognizedObjectObservation` to carry bird-eye points. [Core ML helper, lines 167–221](https://github.com/ultralytics/ultralytics/blob/v8.4.67/ultralytics/utils/export/coreml.py#L167)
- The publisher applies per-box and per-point confidence gates and converts predictions to real image pixels through Ultralytics results. Its thresholds are local heuristics (default keypoint 0.25), not a guarantee that a distant bird eye is visible. Preserve user-selected bird identity, use actual confident beak/head-top/eye points for a head region, and fall back to genuine body detection when points are absent. [Publisher inference implementation](https://raw.githubusercontent.com/synthet/image-scoring-model/20bae89a25d923c56466fb1a0421572ad291e4a0/src/eye_quality/localization/pose_model.py)

**Remaining technical gate:** the full-object checkpoint has not yet been reconstructed through the restricted loader or exported. The download/hash/schema gate passes; export/parity/latency gates do not yet pass. Actual Core ML feature names, output dtype/dimensions, decoded parity and iPhone 17/iOS 27 latency remain untested.

### Opt-in restricted conversion script (not yet run on macOS)

`scripts/research_bird_export.py` now supplies an executable research path. Its default inspect-only mode passed against the actual hash-pinned checkpoint on Windows. Python compilation also passed. It changes no app code and never copies weights/model packages into app resources.

- Proposed ephemeral macOS environment: Python 3.11; `torch==2.7.0`, `torchvision==0.22.0`, `ultralytics==8.4.67`, `coremltools==9.0`, `numpy==1.26.4`, `opencv-python==4.11.0.86`. The script checks installed distribution versions before conversion and disables Ultralytics dependency auto-install.
- Conversion requires both `--convert` and `R6_BIRD_PERSONAL_RESEARCH=1`. It must run without deployment secrets and with read-only repository permissions. Do not upload `build/research/`, `.pt`, `.mlpackage`, compiled models, or an IPA containing this research model; publish only `build/bird-research.log`.
- Before loading, it validates SHA-256, length, decompressed size, and all 29 statically observed global references. Unknown GLOBAL targets or unreviewed dynamic-global/extension pickle opcodes fail closed. Its `safe_globals` list is a fixed set of the exact PyTorch/Ultralytics module classes found here plus `set`, not an automatic allowlist inferred from arbitrary checkpoint strings.
- It uses **`torch.load(..., weights_only=True)` only**; `TORCH_FORCE_WEIGHTS_ONLY_LOAD=1` prevents permissive secondary loads. There is no `weights_only=False` retry, `pickle.load`, checkpoint-specified import, or `YOLO(checkpoint)` call. The known Ultralytics classes were checked against their versioned source for custom unpickle hooks; their inherited PyTorch module state restoration updates state and adds missing bookkeeping attributes. The reviewed allowlist excludes unrelated Ultralytics classes that do define extra hooks. [PyTorch module restoration](https://github.com/pytorch/pytorch/blob/v2.7.0/torch/nn/modules/module.py#L1892), [Ultralytics blocks](https://github.com/ultralytics/ultralytics/blob/v8.4.67/ultralytics/nn/modules/block.py), [convolutions](https://github.com/ultralytics/ultralytics/blob/v8.4.67/ultralytics/nn/modules/conv.py), [PyTorch restricted loading reference](https://pytorch.org/docs/stable/notes/serialization.html#torch-load-with-weights-only-true)
- After restricted reconstruction, it checks exact module types, rejects instance-callable overrides and registered hooks, verifies finite parameters/schema/parameter-count budget, sanitizes export metadata paths, then calls the versioned Exporter directly on that already-loaded model.
- If conversion succeeds, it records the real input/output descriptors and compares Core ML CPU outputs to PyTorch CPU outputs on gray, gradient and seeded-noise RGB inputs. Shape/nonfinite mismatches fail; research tolerances are max 5 model-input pixels and max 0.03 probability error. These synthetic parity checks do not establish localization accuracy, preprocessing parity on real camera crops, species coverage or device performance.

Exact macOS invocation and dependency pins are in the script docstring. This path is ready for an explicitly opted-in CI experiment; its result must be observed before describing conversion as successful.

### 2. VHR-BirdPose / Animal Kingdom: research route with heavier integration

VHR-BirdPose publishes PyTorch source, an MIT source-code licence, and a Google Drive/Baidu link advertised as pretrained weights. Its tested setup is CUDA/PyTorch; it does not supply a verified Core ML/mobile artifact. The source licence does not establish that the external checkpoints and training data have the same redistribution grant. [Publisher README](https://raw.githubusercontent.com/LuoXishuang0712/VHR-BirdPose/main/README.md), [source licence](https://raw.githubusercontent.com/LuoXishuang0712/VHR-BirdPose/main/LICENSE)

The supplied configuration specifies 256 x 256 model images, 64 x 64 heatmaps and 23 joints. The Animal Kingdom annotation contract assigns joint 0 to `Head_Mid_Top`, 1 to `Eye_Left`, and 2 to `Eye_Right`; these are genuine annotated points. The dataset/code download requires a form. These configuration facts do not prove the external checkpoint's exact tensor interface or phone latency. [Model configuration](https://raw.githubusercontent.com/LuoXishuang0712/VHR-BirdPose/main/experiments/mpii/vhrbirdpose/w32_256x256_adam_lr1e-3_ak_vhr_b.yaml), [dataset annotation and setup contract](https://raw.githubusercontent.com/sutdcv/Animal-Kingdom/master/Animal_Kingdom/pose_estimation/README_pose_estimation.md)

**Verdict:** possible research/export project; not a dependency ready to add to the current app. Checkpoint bytes, checkpoint-specific rights, preprocessing, decoder and Core ML parity would all need verification first.

### 3. LegendLeoChen/yolov8-bird: custom research implementation

The publisher advertises bird pose checkpoints in external dataset archives, custom YOLO architecture changes and an additional pose-classification network. The repository is labelled MIT, but an inherited Ultralytics architecture and externally packaged weights still require separate rights/provenance checking. No validated Core ML artifact or exact exported output contract was established. [Publisher repository](https://github.com/LegendLeoChen/yolov8-bird)

### 4. DeepLabCut SuperAnimal: not the missing bird model

The official pretrained offerings documented by DeepLabCut are SuperAnimal-Quadruped and SuperAnimal-TopViewMouse. They do not establish general bird-eye support and should not be presented as such. [Official pretrained-model documentation](https://deeplabcut.github.io/DeepLabCut/)

## Dog/cat eyes and a truthful head region

The app already has the appropriate local system model: `VNDetectAnimalBodyPoseRequest`. Apple documents cat/dog support and eye, nose and ear landmarks. It does not establish bird support. [Apple animal-pose presentation](https://developer.apple.com/videos/play/wwdc2023/10045/)

Verified Swift joint names for the head are:

```swift
let names: [VNAnimalBodyPoseObservation.JointName] = [
    .leftEye, .rightEye, .nose,
    .leftEarTop, .leftEarMiddle, .leftEarBottom,
    .rightEarTop, .rightEarMiddle, .rightEarBottom
]
// Each: try observation.recognizedPoint(name)
// Returned VNRecognizedPoint: location and confidence.
// .neck also exists, but is not an eye/head-surface point.
```

[Apple joint-name reference](https://developer.apple.com/documentation/vision/vnanimalbodyposeobservation/jointname)

Engineering recommendation: form a bounding envelope only from sufficiently confident observed head landmarks, with nonzero spread. Call this a **landmark-derived head region**; it is not a separately detected head box. If points are absent or degenerate, retain the genuine body detection. Never create eye coordinates from a fixed fraction of a body box. Do not combine landmarks from different animals: associate the pose with the selected subject first.

## Gates before adding a bird-eye model

1. **Retrieval complete:** source revision, filename, hash, size and static keypoint shape are recorded above. Personal-only use is authorized; unrestricted redistribution rights remain unestablished. Preserve the checkpoint's AGPL notice and do not treat the MIT card tag as overriding it.
2. Reproduce inference using the publisher's implementation on a small, legally usable fixture set. Verify keypoint order, visibility semantics, preprocessing and behavior when eyes are hidden.
3. Export to Core ML with pinned tool versions. Inspect the artifact's real input/output description, and add a decoder for those tensors. Compare decoded points against original inference, including letterboxing and crop inversion.
4. On iPhone 17, measure end-to-end latency and thermal behavior alongside preview and capture. Test distant/tiny birds, profile views, occlusion, flight, multiple birds and no-bird scenes. A card's validation mAP is not an autofocus accuracy guarantee.
5. Require confidence-gated fallback to actual head/body detection and truthful UI labels. Freeze target identity through brief misses, but expire stale eye points; never render an old or fabricated point as a current detection.

If a clean checkpoint cannot be obtained, the durable path is a small keypoint model trained from appropriately licensed bird-head/eye annotations. Training, export and evaluation are separate work and were not performed here. No release-ready bird-eye capability is claimed by this note.
