#!/usr/bin/env python3
"""Verify the aggregate result files and public-artifact privacy boundary."""

from __future__ import annotations

import csv
import json
import math
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]


def _assert_close(actual: float, expected: float, label: str, tolerance: float = 1e-9) -> None:
    if not math.isclose(actual, expected, rel_tol=0.0, abs_tol=tolerance):
        raise AssertionError(f"{label}: expected {expected}, found {actual}")


def _read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def _read_json(path: Path) -> Any:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def verify_layout_ablation() -> None:
    rows = _read_csv(ROOT / "reports/real_layout_ablation/summary.csv")
    by_strategy = {row["strategy"]: row for row in rows}
    expected = {
        "p0_raw_text": (0.8936, 0.3002, 0.4494, 504, 60, 1175, 1679),
        "p1_sorted_lines": (0.8936, 0.3002, 0.4494, 504, 60, 1175, 1679),
        "p2_row_clusters": (0.8279, 0.2549, 0.3898, 428, 89, 1251, 1679),
        "p3_medication_bands": (0.9063, 0.1959, 0.3222, 329, 34, 1350, 1679),
    }
    if set(by_strategy) != set(expected):
        raise AssertionError("Unexpected RQ1 strategy set")

    for strategy, values in expected.items():
        row = by_strategy[strategy]
        precision, recall, f1, tp, fp, fn, gt_total = values
        _assert_close(float(row["micro_precision"]), precision, f"{strategy} precision")
        _assert_close(float(row["micro_recall"]), recall, f"{strategy} recall")
        _assert_close(float(row["micro_f1"]), f1, f"{strategy} F1")
        observed_counts = tuple(int(row[key]) for key in ("tp", "fp", "fn", "gt_total"))
        if observed_counts != (tp, fp, fn, gt_total):
            raise AssertionError(f"{strategy} count mismatch: {observed_counts}")


def verify_roi_ablation() -> None:
    rows = _read_csv(ROOT / "reports/real_medication_roi_ablation/summary.csv")
    by_key = {(row["granularity"], row["condition"]): row for row in rows}
    expected = {
        ("Drug-Instance Micro", "r0"): (0.9051, 0.7761, 0.7591, 0.7675, 137),
        ("Drug-Instance Micro", "r1"): (0.9270, 0.8074, 0.7956, 0.8015, 137),
        ("Capture-Macro", "r0"): (0.9067, 0.7783, 0.7700, 0.7694, 30),
        ("Capture-Macro", "r1"): (0.9300, 0.8100, 0.8100, 0.8057, 30),
        ("Prescription-Macro", "r0"): (0.9737, 0.8213, 0.9207, 0.8620, 5),
        ("Prescription-Macro", "r1"): (0.9798, 0.8428, 0.9434, 0.8842, 5),
    }
    if set(by_key) != set(expected):
        raise AssertionError("Unexpected RQ2 granularity/condition set")

    for key, values in expected.items():
        row = by_key[key]
        coverage, precision, recall, f1, sample_size = values
        for column, expected_value in (
            ("visible_ocr_coverage", coverage),
            ("precision", precision),
            ("recall", recall),
            ("f1_score", f1),
        ):
            _assert_close(float(row[column]), expected_value, f"{key} {column}")
        if int(row["sample_size"]) != sample_size:
            raise AssertionError(f"{key} sample-size mismatch")

    stats = _read_json(
        ROOT / "reports/real_medication_roi_ablation/statistical_significance.json"
    )
    mcnemar = stats["mcnemar_exact_test"]
    if (mcnemar["b_gain"], mcnemar["c_loss"], mcnemar["net_gain"]) != (14, 9, 5):
        raise AssertionError("Unexpected paired transition counts")
    exact_p = 2.0 * sum(math.comb(23, k) * 0.5**23 for k in range(14, 24))
    _assert_close(mcnemar["two_sided_p_value"], exact_p, "exact McNemar p-value")

    capture_ci = stats["capture_level_bootstrap_95ci"]["delta_f1_pct"]
    clustered_ci = stats["prescription_clustered_bootstrap_95ci"]["delta_f1_pct"]
    for actual, expected_value, label in (
        (capture_ci["point_estimate"], 3.39, "capture point estimate"),
        (capture_ci["ci_lower"], -3.18, "capture CI lower"),
        (capture_ci["ci_upper"], 10.18, "capture CI upper"),
        (clustered_ci["point_estimate"], 3.39, "clustered point estimate"),
        (clustered_ci["ci_lower"], 0.0, "clustered CI lower"),
        (clustered_ci["ci_upper"], 7.21, "clustered CI upper"),
    ):
        _assert_close(float(actual), expected_value, label)


def verify_public_boundary() -> None:
    forbidden_paths = (
        "data/visible_in_frame_gt.json",
        "data/human_verification_provenance_log.json",
        "data/drug_db_vn_full.json",
        "data/drug_db_vn.csv",
        "server/data/drug_db.json",
        "mobile/assets/real_roi_samples",
        "mobile/assets/roi_samples",
    )
    present = []
    for relative in forbidden_paths:
        candidate = ROOT / relative
        if candidate.is_file() or (candidate.is_dir() and any(candidate.rglob("*"))):
            present.append(relative)
    if present:
        raise AssertionError(f"Restricted path present in public artifact: {present}")

    forbidden_suffixes = {".safetensors", ".pt", ".pth", ".onnx", ".jsonl"}
    forbidden_names: list[str] = []
    for path in ROOT.rglob("*"):
        if ".git" in path.parts or not path.is_file():
            continue
        if path.suffix.lower() in forbidden_suffixes or "predictions" in path.name.lower():
            forbidden_names.append(str(path.relative_to(ROOT)))
        if "mlkit_ocr" in {part.lower() for part in path.parts}:
            forbidden_names.append(str(path.relative_to(ROOT)))
    if forbidden_names:
        raise AssertionError(f"Restricted artifact files present: {sorted(set(forbidden_names))}")


def main() -> None:
    verify_layout_ablation()
    verify_roi_ablation()
    verify_public_boundary()
    print("PASS: aggregate RQ1/RQ2 results and public-artifact boundary are consistent")


if __name__ == "__main__":
    main()
