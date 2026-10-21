# Bird eye and head localization feasibility

Checked: 2026-10-22 (Asia/Taipei). Read-only investigation of model sources; no app code, model weights, or datasets changed.

## Decision

No ready, verified Core ML bird-eye model with a sufficiently clear redistribution licence was established in this investigation. Keep the current genuine whole-bird detection, and do not describe a point derived from the bird box as an eye. This is a missing model capability, not an AVFoundation limitation.

There are real bird-keypoint research candidates. The closest small-model candidate has a documented eye-point schema and advertised downloadable PyTorch weights, but its upstream licensing, actual checkpoint retrieval, Core ML export, output tensors, and phone performance remain unverified. It should not be silently added to a distributable IPA.

## Candidates and evidence

### 1. synthet/eye-pose-v0: closest practical candidate, not release-ready

The publisher describes a YOLO11n-pose checkpoint fine-tuned on CUB-200-2011. Its documented output semantics are a full-bird box plus these six keypoints, in order: `beak`, `left_eye`, `right_eye`, `head_top`, `left_shoulder`, `right_shoulder`. The model card advertises `eye_pose_v0.pt` and a Hugging Face download command. It warns that distant field birds can differ from training images. These are publisher claims, not independently reproduced results. [Model card and download instructions](https://huggingface.co/synthet/eye-pose-v0/raw/main/README.md)

The publisher's pipeline selects one bird and filters boxes and points by confidence. Eye sharpness is a separate heuristic, not an additional model output. No published Core ML package was found. [Publisher pipeline](https://raw.githubusercontent.com/synthet/image-scoring-model/main/docs/architecture/PIPELINE.md)

**Weights availability:** advertised by the publisher at `https://huggingface.co/synthet/eye-pose-v0/resolve/main/eye_pose_v0.pt`; the research web tool could not retrieve the file or file listing. No bytes, hash, checkpoint metadata, or executable model have been verified. The advertised filename is therefore not a validated build dependency.

**Licence:** the card says MIT while declaring an Ultralytics YOLO11n-pose base. Ultralytics' own licensing page describes AGPL-3.0/Enterprise obligations for its trained and fine-tuned models. The discrepancy has not been resolved with either publisher. It is not sufficient to treat the card's MIT tag as clearing all upstream rights. [Ultralytics licensing position](https://www.ultralytics.com/license), [upstream code licence](https://raw.githubusercontent.com/ultralytics/ultralytics/main/LICENSE)

The CUB dataset publisher restricts the source images to noncommercial research and education and does not own their copyrights. This does not by itself settle the legal status of resulting model weights, but it leaves provenance and intended distribution use unresolved. [Caltech dataset terms](https://www.vision.caltech.edu/datasets/cub_200_2011/)

**Exact contract status:** the six semantic indices above are documented. Actual checkpoint `kpt_shape`, input preprocessing, output tensor names/dimensions, score calibration, and exported Core ML layout have not been inspected. Do not hardcode an assumed YOLO tensor shape or claim `VNRecognizedObjectObservation` will include keypoints. A Core ML pose model will require an adapter for its verified outputs.

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

1. Obtain the actual checkpoint and pin its source revision, filename, hash and size; record model-weight rights independently of code and dataset labels. Resolve the candidate's MIT/Ultralytics provenance discrepancy for the intended use.
2. Reproduce inference using the publisher's implementation on a small, legally usable fixture set. Verify keypoint order, visibility semantics, preprocessing and behavior when eyes are hidden.
3. Export to Core ML with pinned tool versions. Inspect the artifact's real input/output description, and add a decoder for those tensors. Compare decoded points against original inference, including letterboxing and crop inversion.
4. On iPhone 17, measure end-to-end latency and thermal behavior alongside preview and capture. Test distant/tiny birds, profile views, occlusion, flight, multiple birds and no-bird scenes. A card's validation mAP is not an autofocus accuracy guarantee.
5. Require confidence-gated fallback to actual head/body detection and truthful UI labels. Freeze target identity through brief misses, but expire stale eye points; never render an old or fabricated point as a current detection.

If a clean checkpoint cannot be obtained, the durable path is a small keypoint model trained from appropriately licensed bird-head/eye annotations. Training, export and evaluation are separate work and were not performed here. No release-ready bird-eye capability is claimed by this note.
