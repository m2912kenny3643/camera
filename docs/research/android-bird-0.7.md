# Android bird model: R6 Camera 0.7 functional-test decision

Evidence refreshed 2026-10-23. This is an engineering release decision for the user-approved, noncommercial research functional test, not a representation of unrestricted commercial rights or a legal opinion.

## Decision

The positive publisher MIT model-card grant, the actual export metadata AGPL-3.0 declaration, and the upstream AGPL route support including this exact model in the first functional-test IPA **under the full corresponding source AGPL route accepted by the user**. Preserve the MIT model card, upstream AGPL text, provenance, exact weight hash, export details, complete application/build source and the distributed model. Do not describe the artifact as merely MIT, proprietary, commercially cleared, or accuracy certified.

The previous open question about CUB training images is not itself evidence of a downstream weight-distribution prohibition. Caltech expressly restricts use of the images to noncommercial research/education and disclaims ownership of their copyrights; its page does not expressly impose those terms on trained weights. We have neither a blanket commercial image clearance nor evidence that the image terms automatically prohibit this functional model distribution. Keep this distinction visible. A future commercial distribution requires its own review.

## Exact artifact and trace

- User-supplied `NeoFocus-0.5.0-pro.apk`, entry `assets/bird-eye.onnx`.
- 10,802,648 bytes; SHA-256 `350f370aac45ec120bb73434eb0add0446a5f327344c65b03a633229dc2c551b`.
- Local NeoFocus source `MODELS-0.4.1.md` records synthet/eye-pose-v0, Ultralytics 8.4.178, PyTorch 2.14.1 CPU, ONNX opset 17, fixed 320×320, simplify=False. Its adjacent model card and AGPL license accompany the model.
- Publisher model card revision `6e7bd361ba84b17d81f0fb4315a44a868df5b692`, original checkpoint SHA-256 `ec9e4b80a93eb6e2b21633e2ff2df30c49faa1eb7919dd24345c7dc295b2d1be` (recorded by earlier conversion research). The APK hash is the distribution identity; it must not silently be replaced by a new export.
- Runtime contract independently exercised: `images` Float32 `[1,3,320,320]` → `output0` Float32 `[1,23,2100]`. Six actual pose points: beak, left/right eyes, crown, left/right shoulders.

## Primary evidence

1. [Publisher model card](https://huggingface.co/synthet/eye-pose-v0): declares MIT, identifies YOLO11n-pose and CUB-200-2011 training, lists the six landmarks and warns about domain/visibility limits. Its author-reported metrics are not R6 Camera field accuracy. [Pinned card](https://huggingface.co/synthet/eye-pose-v0/blob/6e7bd361ba84b17d81f0fb4315a44a868df5b692/README.md).
2. [Ultralytics license](https://www.ultralytics.com/license): expressly provides the AGPL route for personal/open-source/research projects and trained/fine-tuned models, requiring complete corresponding source. User accepted this route; retain source and notices rather than treating the model card alone as the entire licensing story.
3. [Caltech CUB page](https://www.vision.caltech.edu/datasets/cub_200_2011/): image copyright disclaimer and noncommercial research/education conditions. No express model-weight distribution clause was found on that page. No author was contacted.
4. [Official ONNX Runtime Swift package 1.24.2](https://github.com/microsoft/onnxruntime-swift-package-manager/blob/1.24.2/Package.swift): pinned implementation dependency. Use CPU as the reproducible first baseline; Core ML conversion is not required for the functional test.

## Real-image functional probe

Four original photographs were obtained with explicit CC0/public-domain source evidence. All files, source URLs, authors, bytes and SHA-256 hashes are in ignored `build/research/bird07/fixture-manifest.json`.

| Photograph | Rights/source | Model decoder result | Qualification |
|---|---|---|---|
| eagle.png | Dayane Machado, CC0, [scikit-image data README](https://gitlab.com/scikit-image/data/-/blob/master/README.md) | EYE; body score 0.872 | Same source image as Android bird.png; not a new independent accuracy benchmark |
| owl-front.jpg | Ted Moravec, CC0, [Commons page](https://commons.wikimedia.org/wiki/File:An_owl_portrait_(52264733713).jpg) | EYE; body score 0.939 | Oblique close owl portrait despite filename; predicted locations require scoring |
| snowy-owl.jpg | Petr Kratochvil, CC0, [Commons page](https://commons.wikimedia.org/wiki/File:Snowy_Owl_Portrait.jpg) | EYE; body score 0.912 | Frontal owl; visual overlay puts predictions near visible eyes, without formal annotation |
| flock.jpg | Heather Henkel / USGS, [public-domain source](https://www.usgs.gov/media/images/flock-birds) | No detections | Distant multi-bird failure is retained, not counted as a pass |

The functional probe used ONNX Runtime 1.24.2, Windows CPU, two intra-op threads and one inter-op thread, one warm-up and one measured inference per picture. Observed single measurements were roughly 11–13 ms; they are **not** iPhone performance, end-to-end latency, P95, or sustained inference results.

Eagle derivatives with grey rectangles over measured eye regions exercised HEAD (radius 4.5%, score 0.641) and BODY (7%, score 0.591) decoder outcomes. These are explicitly synthetic occlusion derivatives, not independent real photographs and not proof of natural occlusion reliability. Small masks can leave eye evidence visible. On the close owl image, measured points can be offset from true eye centers; masking predicted coordinates did not fully cover the visible eyes. Do not use that experiment to claim either a measured invisible-eye false-positive rate or accurate eye localization.

`cpu-smoke.json` and `occlusion-smoke.json` retain all decoded points and confidence values. `fixture-expected.json` includes all top accepted body boxes and six keypoints, with `correctness_claim=false`; full input/output `.npy` and little-endian Float32 `.f32` tensors are available for native inference parity checks. Pillow bilinear square-padding RGB114 was used as a functional reference; no bit-exact Android Canvas rasterization claim is made.

Python ORT is isolated under ignored `build/python-bird07`, installed with `--target --no-deps onnxruntime==1.24.2`. Python executable: `C:/Users/m2912/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe`. No global Python environment change or unsafe PyTorch pickle load was needed. Reproducer: `build/research/bird07/probe_model.py`.

## Functional release versus formal acceptance

This evidence allows a clearly labeled functional-test artifact containing the exact model and full-source notices. It proves the model runs and produces real landmark outputs; it does not prove all predictions correct or the camera lens has physically focused on the eye. Keep confidence/geometry/age checks, one-frame freshness, eye→observed head→body downgrade and identity association. Never add guessed eyes to compensate for missed points.

Deferred formal acceptance remains: at least 100 independent annotated real images, invisible-eye false-positive rate, localization and miss metrics, phone inference throughput/latency, temperature, multi-bird identity stability and camera focus. Phone burst cadence with bird inference enabled must also be measured separately. Neither these four images nor Windows inference substitutes for those tests.

## Native sampler cross-check

A second Windows ORT probe reproduced the native adapter's direct bilinear RGB sampling, including source pixel centers and gray114 outside bounds. Top body scores were eagle0.866, artificially eye-masked HEAD0.671 and BODY0.594, frontal owl0.905; the distant flock maximum was0.0014 (below threshold). Eagle measured left eye was approximately(0.4927,0.2631), right eye(0.4743,0.2632). This supplements the earlier Pillow antialiased reference; it does not claim bit-exact Android Canvas decoding. Raw probe is retained locally at `build/research/bird07/native-sampler-smoke.json`.

ONNX Runtime1.24.2 MIT license and upstream ThirdPartyNotices are preserved in the application resources from the official pinned tag.
