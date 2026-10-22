"""Score externally annotated real bird images; never generate qualification evidence.

Input JSON: model_sha256, independence_evidence, image_rights_evidence, images.
Each image: sha256, real_image=true, annotation_source, distant (bool), birds, predictions.
Each bird: species (stable label), bbox [x,y,w,h], head_bbox, eyes {left_eye/right_eye: {visible,
point:[x,y] when visible}}. Predictions: bbox, eyes {name:{point,confidence}},
optional head_bbox and head_source="observed_keypoints". Coordinates are pixels.
Body boxes are matched one-to-one, highest IoU first (threshold .5). Eye sides
are semantic labels, not interchangeable nearest points. Default correct-point
threshold .1 * ground-truth head diagonal is an explicit evaluation convention,
not a measured universal perceptual tolerance. Reports also contain an error
curve, recall, unmatched predictions and invisible-eye denominators.

Usage: python scripts/bird_eval_metrics.py input.json --output report.json
Synthetic fixtures only test this scorer; they cannot qualify a model. This
script evaluates accuracy only. Distribution and real-device performance are
separate gates; accuracy-only success never authorizes a bundled model release.
"""

import argparse
import hashlib
import json
import math
from pathlib import Path

EYES = ("left_eye", "right_eye")


def number(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ValueError("Coordinates/confidences must be finite numbers")
    return float(value)


def point(value):
    if not isinstance(value, list) or len(value) != 2:
        raise ValueError("point must contain two coordinates")
    return tuple(number(v) for v in value)


def box(value):
    if not isinstance(value, list) or len(value) != 4:
        raise ValueError("bbox must contain x,y,width,height")
    result = tuple(number(v) for v in value)
    if result[2] <= 0 or result[3] <= 0:
        raise ValueError("Bounding boxes need positive width/height")
    return result


def iou(a, b):
    area = max(0, min(a[0] + a[2], b[0] + b[2]) - max(a[0], b[0])) * max(
        0, min(a[1] + a[3], b[1] + b[3]) - max(a[1], b[1]))
    return area / (a[2] * a[3] + b[2] * b[3] - area)


def digest(value):
    return isinstance(value, str) and len(value) == 64 and all(c in "0123456789abcdef" for c in value)


def score(data, confidence=0.5, error_threshold=0.1):
    confidence, error_threshold = number(confidence), number(error_threshold)
    if not 0 <= confidence <= 1 or error_threshold <= 0:
        raise ValueError("Confidence must be 0...1 and error threshold positive")
    if not digest(data.get("model_sha256")):
        raise ValueError("A concrete model SHA-256 is required")
    images = data.get("images")
    if not isinstance(images, list):
        raise ValueError("images must be a list")
    seen = set()
    total_predictions = visible = invisible = false_invisible = correct = 0
    unmatched_predictions = head_opportunities = head_correct = 0
    errors = []
    bird_images = distant_images = occluded_images = multiple_bird_images = 0
    species = set()
    complete_evidence = True
    for image in images:
        sha = image.get("sha256")
        if not digest(sha) or sha in seen:
            raise ValueError("Image SHA-256 must be valid and unique; duplicates are not independent images")
        seen.add(sha)
        complete_evidence &= image.get("real_image") is True and bool(image.get("annotation_source"))
        birds = image.get("birds", [])
        predictions = image.get("predictions", [])
        if 'distant' in image and type(image['distant']) is not bool:
            raise ValueError('distant must be a boolean annotation')
        bird_images += bool(birds)
        distant_images += bool(birds) and image.get('distant') is True
        multiple_bird_images += len(birds) >= 2
        image_has_occluded_eye = False
        truth_boxes = [box(b["bbox"]) for b in birds]
        predicted_boxes = [box(p["bbox"]) for p in predictions]
        truths = []
        for b in birds:
            if isinstance(b.get('species'), str) and b['species'].strip():
                species.add(b['species'].strip())
            head = box(b["head_bbox"])
            eyes = b["eyes"]
            if set(eyes) != set(EYES):
                raise ValueError("Ground truth must explicitly label both eye visibilities")
            parsed = {}
            for name in EYES:
                eye = eyes[name]
                if type(eye.get("visible")) is not bool:
                    raise ValueError("Unknown visibility cannot count as an invisible eye")
                if eye["visible"]:
                    visible += 1
                    parsed[name] = point(eye["point"])
                else:
                    invisible += 1
                    image_has_occluded_eye = True
                    parsed[name] = None
            truths.append((head, parsed))
        occluded_images += image_has_occluded_eye
        proposals = []
        for p in predictions:
            if set(p.get("eyes", {})) - set(EYES):
                raise ValueError("Unexpected eye name")
            eyes = {}
            for name, eye in p.get("eyes", {}).items():
                strength = number(eye["confidence"])
                if not 0 <= strength <= 1:
                    raise ValueError("Eye confidence must be 0...1")
                location = point(eye["point"])
                if strength >= confidence:
                    eyes[name] = location
            total_predictions += len(eyes)
            head = box(p["head_bbox"]) if p.get("head_bbox") is not None else None
            proposals.append((eyes, head, p.get("head_source")))
        pairs = sorted(((iou(a, b), ti, pi) for ti, a in enumerate(truth_boxes)
                        for pi, b in enumerate(predicted_boxes)), key=lambda p: (-p[0], p[1], p[2]))
        used_truth, used_prediction = set(), set()
        for overlap, ti, pi in pairs:
            if overlap < 0.5 or ti in used_truth or pi in used_prediction:
                continue
            used_truth.add(ti)
            used_prediction.add(pi)
            head, eyes = truths[ti]
            proposed, proposed_head, source = proposals[pi]
            scale = math.hypot(head[2], head[3])
            for name, location in proposed.items():
                target = eyes[name]
                if target is None:
                    false_invisible += 1
                else:
                    error = math.dist(location, target) / scale
                    errors.append(error)
                    correct += error <= error_threshold
            if not proposed:
                head_opportunities += 1
                head_correct += proposed_head is not None and source == "observed_keypoints" and iou(head, proposed_head) >= 0.5
        unmatched_predictions += sum(len(proposals[i][0]) for i in range(len(proposals)) if i not in used_prediction)
    precision = correct / total_predictions if total_predictions else None
    recall = correct / visible if visible else None
    false_rate = false_invisible / invisible if invisible else None
    blockers = []
    if len(seen) < 100:
        blockers.append("Fewer than 100 unique real images")
    if bird_images < 100:
        blockers.append("Fewer than 100 annotated bird images; blank negatives do not replace bird coverage")
    if distant_images == 0 or occluded_images == 0 or multiple_bird_images == 0 or len(species) < 2:
        blockers.append("Missing distant, occluded, multiple-bird or multi-species coverage")
    if not complete_evidence or not data.get("independence_evidence") or not data.get("image_rights_evidence"):
        blockers.append("Missing real-image, annotation, independence or image-use evidence")
    if precision is None or precision < 0.95:
        blockers.append("Eye precision missing or below 95%")
    if false_rate is None or false_rate > 0.01:
        blockers.append("Invisible-eye coverage missing or false-eye rate above 1%")
    if visible == 0:
        blockers.append("No visible-eye ground truth")
    return {
        "schema_version": 1, "model_sha256": data["model_sha256"],
        "images": len(seen), "confidence_threshold": confidence,
        "bird_images": bird_images, "distant_images": distant_images,
        "occluded_images": occluded_images, "multiple_bird_images": multiple_bird_images,
        "species": sorted(species),
        "correctness_threshold_head_diagonal": error_threshold,
        "association": "greedy one-to-one body IoU >= 0.5; semantic eye sides",
        "visible_eyes": visible, "invisible_eyes": invisible,
        "eye_predictions": total_predictions, "correct_eye_predictions": correct,
        "false_eye_predictions": total_predictions - correct,
        "missed_visible_eyes": visible - correct,
        "unmatched_bird_eye_predictions": unmatched_predictions,
        "false_invisible_eye_predictions": false_invisible,
        "eye_precision": precision, "eye_recall": recall,
        "invisible_eye_false_positive_rate": false_rate,
        "normalized_error_mean": sum(errors) / len(errors) if errors else None,
        "visible_eye_recall_curve": {str(t): sum(e <= t for e in errors) / visible if visible else None
                                     for t in [0.025, 0.05, 0.1, 0.2]},
        "head_fallback_opportunities": head_opportunities,
        "correct_observed_head_fallbacks": head_correct,
        "accuracy_thresholds_met": not blockers, "accuracy_blockers": blockers,
        "release_qualified": False,
        "remaining_release_gates": ["Independent evidence review", "Weight redistribution review",
                                    "iPhone >=10Hz and P95 <=150ms real-device benchmark"],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--confidence", type=float, default=0.5)
    parser.add_argument("--error-threshold", type=float, default=0.1)
    args = parser.parse_args()
    raw = args.input.read_bytes()
    report = score(json.loads(raw), args.confidence, args.error_threshold)
    report["input_sha256"] = hashlib.sha256(raw).hexdigest()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    print(json.dumps({"accuracy_thresholds_met": report["accuracy_thresholds_met"],
                      "release_qualified": False, "images": report["images"]}))


if __name__ == "__main__":
    main()
