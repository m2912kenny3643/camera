import copy
import unittest

from bird_eval_metrics import score


def fixture():
    return {
        "model_sha256": "a" * 64,
        "images": [{"sha256": "b" * 64, "real_image": False,
                    "birds": [{"species": "fixture species A", "bbox": [0, 0, 100, 100], "head_bbox": [10, 10, 20, 20],
                               "eyes": {"left_eye": {"visible": True, "point": [15, 15]},
                                        "right_eye": {"visible": False}}}],
                    "predictions": [{"bbox": [0, 0, 100, 100],
                                     "eyes": {"left_eye": {"point": [15, 15], "confidence": 0.9}}}]}],
    }


class BirdEvalTests(unittest.TestCase):
    def test_correct_eye_and_unobserved_side_have_separate_denominators(self):
        report = score(fixture())
        self.assertEqual(report["eye_precision"], 1)
        self.assertEqual(report["eye_recall"], 1)
        self.assertEqual(report["invisible_eye_false_positive_rate"], 0)
        self.assertFalse(report["accuracy_thresholds_met"])
        self.assertFalse(report["release_qualified"])

    def test_hallucinated_occluded_eye_is_false_positive(self):
        data = fixture()
        data["images"][0]["predictions"][0]["eyes"]["right_eye"] = {"point": [25, 15], "confidence": 0.8}
        report = score(data)
        self.assertEqual(report["eye_precision"], 0.5)
        self.assertEqual(report["invisible_eye_false_positive_rate"], 1)

    def test_unmatched_bird_and_duplicate_proposals_penalize_precision(self):
        data = fixture()
        duplicate = copy.deepcopy(data["images"][0]["predictions"][0])
        data["images"][0]["predictions"].append(duplicate)
        report = score(data)
        self.assertEqual(report["eye_precision"], 0.5)
        self.assertEqual(report["unmatched_bird_eye_predictions"], 1)
        self.assertEqual(report["missed_visible_eyes"], 0)

    def test_blank_predictions_do_not_pass_with_nan_or_perfect_precision(self):
        data = fixture()
        data["images"][0]["predictions"] = []
        report = score(data)
        self.assertIsNone(report["eye_precision"])
        self.assertEqual(report["eye_recall"], 0)
        self.assertEqual(report["missed_visible_eyes"], 1)
        self.assertFalse(report["accuracy_thresholds_met"])

    def test_wrong_location_is_both_false_prediction_and_missed_visible_eye(self):
        data = fixture()
        data["images"][0]["predictions"][0]["eyes"]["left_eye"]["point"] = [90, 90]
        report = score(data)
        self.assertEqual(report["eye_precision"], 0)
        self.assertEqual(report["eye_recall"], 0)
        self.assertEqual(report["false_eye_predictions"], 1)
        self.assertEqual(report["missed_visible_eyes"], 1)

    def test_invalid_and_duplicate_evidence_fails(self):
        data = fixture()
        data["images"].append(copy.deepcopy(data["images"][0]))
        with self.assertRaises(ValueError):
            score(data)
        data = fixture()
        data["images"][0]["predictions"][0]["eyes"]["left_eye"]["point"] = [float("nan"), 0]
        with self.assertRaises(ValueError):
            score(data)
        data = fixture()
        data["images"][0]["birds"][0]["eyes"]["right_eye"]["visible"] = None
        with self.assertRaises(ValueError):
            score(data)

    def test_head_fallback_needs_observed_points_and_correct_box(self):
        data = fixture()
        prediction = data["images"][0]["predictions"][0]
        prediction.update(eyes={}, head_bbox=[10, 10, 20, 20], head_source="body_guess")
        self.assertEqual(score(data)["correct_observed_head_fallbacks"], 0)
        prediction["head_source"] = "observed_keypoints"
        self.assertEqual(score(data)["correct_observed_head_fallbacks"], 1)

    def test_large_synthetic_set_never_qualifies_as_real_evidence(self):
        data = fixture()
        template = data["images"][0]
        data["images"] = []
        for i in range(100):
            image = copy.deepcopy(template)
            image["sha256"] = f"{i:064x}"
            data["images"].append(image)
        report = score(data)
        self.assertEqual(report["images"], 100)
        self.assertFalse(report["accuracy_thresholds_met"])
        self.assertFalse(report["release_qualified"])

    def test_accuracy_numbers_never_authorize_distribution(self):
        # The declarations here are fixtures, not an actual independent dataset.
        data = fixture()
        data.update(independence_evidence="fixture proof", image_rights_evidence="fixture proof")
        template = data["images"][0]
        data["images"] = []
        for i in range(100):
            image = copy.deepcopy(template)
            image.update(sha256=f"{i:064x}", real_image=True, annotation_source="fixture annotator")
            image['distant'] = i == 0
            image['birds'][0]['species'] = f'fixture species {i % 2}'
            if i == 0:
                extra = copy.deepcopy(image['birds'][0])
                extra.update(bbox=[200, 0, 100, 100], head_bbox=[210, 10, 20, 20])
                extra['eyes']['left_eye']['point'] = [215, 15]
                image['birds'].append(extra)
                image['predictions'].append(dict(bbox=[200, 0, 100, 100],
                                                eyes=dict(left_eye=dict(point=[215, 15], confidence=0.9))))
            data["images"].append(image)
        report = score(data)
        self.assertTrue(report["accuracy_thresholds_met"])
        self.assertFalse(report["release_qualified"])

    def test_blank_images_and_missing_scenarios_do_not_replace_bird_coverage(self):
        data = fixture()
        data.update(independence_evidence='fixture proof', image_rights_evidence='fixture proof')
        template = data['images'][0]
        data['images'] = []
        for i in range(100):
            image = copy.deepcopy(template)
            image.update(sha256=f'{i:064x}', real_image=True, annotation_source='fixture annotator')
            if i > 0:
                image.update(birds=[], predictions=[])
            data['images'].append(image)
        report = score(data)
        self.assertEqual(report['bird_images'], 1)
        self.assertFalse(report['accuracy_thresholds_met'])
        self.assertEqual(report['multiple_bird_images'], 0)


if __name__ == "__main__":
    unittest.main()
