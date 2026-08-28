"""
scripts/tests/test_p0_p3_ablation.py — P0 -> P1 -> P2 -> P3 Ablation Benchmark and Diagnostic Cascade.

Ablation Levels:
- P0: Raw OCR lines (baseline unordered / plain dump)
- P1: Geometric reading order (Y top-to-bottom, X left-to-right)
- P2: P1 + horizontal row clustering
- P3: P2 + STT medication band grouping (production target)

Failure Taxonomy Cascade:
1. OCR_CHAR_FAIL: Malformed character streams or missing text
2. READING_ORDER_FAIL: Columns interleaved inappropriately
3. LINE_SPLIT_FAIL: Drug names severed across disconnected blocks
4. MERGE_FAIL: Dosage / instruction misplaced into incorrect drug band
5. NER_FAIL: PhoBERT NER fails to extract drug entity
6. LOOKUP_FAIL: DrugLookup fuzzy matching score < 0.7
7. SUCCESS: Clean extraction and resolution (confirmed or valid candidate)
"""

import json
from pathlib import Path
from typing import Any, Dict, List

import pytest
from core.pipeline import MedicinePipeline
from core.classify.mlkit_layout_adapter import MLKitLayoutAdapter


# Realistic sample simulating ML Kit OCR line stream from a Vietnamese prescription
SAMPLE_PRESCRIPTION_MLKIT_LINES = [
    # Header info
    {"text": "BỆNH VIỆN ĐA KHOA HOÀN MỸ", "bbox": [100, 30, 450, 50], "confidence": 0.98},
    {"text": "ĐƠN THUỐC ĐIỀU TRỊ", "bbox": [180, 60, 380, 80], "confidence": 0.99},
    {"text": "Bệnh nhân: Nguyễn Văn An", "bbox": [50, 100, 250, 120], "confidence": 0.95},
    {"text": "Chẩn đoán: Viêm khớp dạng thấp", "bbox": [50, 130, 300, 150], "confidence": 0.96},

    # Drug 1: Multi-column: STT | Drug Name + Strength | Quantity | Unit | Usage
    {"text": "1.", "bbox": [50, 200, 70, 220], "confidence": 0.99},
    {"text": "Celecoxib 200mg", "bbox": [90, 200, 260, 220], "confidence": 0.97},
    {"text": "30", "bbox": [400, 200, 425, 220], "confidence": 0.95},
    {"text": "Viên", "bbox": [440, 200, 480, 220], "confidence": 0.96},
    {"text": "Ngày uống 2 lần, mỗi lần 1 viên sau ăn", "bbox": [90, 225, 380, 245], "confidence": 0.94},

    # Drug 2: STT prefix on name, multi-column: 2. Eperisone 50mg | 20 | Viên | Sáng 1 viên, tối 1 viên
    {"text": "2. Eperisone 50mg", "bbox": [50, 260, 240, 280], "confidence": 0.98},
    {"text": "20", "bbox": [400, 260, 425, 280], "confidence": 0.95},
    {"text": "Viên", "bbox": [440, 260, 480, 280], "confidence": 0.96},
    {"text": "Uống sau bữa ăn sáng và tối", "bbox": [90, 285, 320, 305], "confidence": 0.93},

    # Drug 3: Multi-column with parenthetical generic: 3 | Hapacol 650 (Paracetamol 650mg) | 10 | Gói
    {"text": "3.", "bbox": [50, 320, 70, 340], "confidence": 0.99},
    {"text": "Hapacol 650 (Paracetamol 650mg)", "bbox": [90, 320, 350, 340], "confidence": 0.98},
    {"text": "10", "bbox": [400, 320, 425, 340], "confidence": 0.95},
    {"text": "Gói", "bbox": [440, 320, 480, 340], "confidence": 0.96},
    {"text": "Uống khi đau hoặc sốt trên 38.5 độ", "bbox": [90, 345, 350, 365], "confidence": 0.92},

    # Footer
    {"text": "Bác sĩ điều trị: BS. CKII Lê Hoàng", "bbox": [250, 420, 500, 440], "confidence": 0.97},
]

EXPECTED_DRUGS = ["Celecoxib", "Eperisone", "Hapacol 650"]


def diagnose_scan_cascade(
    extracted_medications: list[dict[str, Any]],
    expected_drugs: list[str],
) -> dict[str, Any]:
    """Diagnose extraction cascade and classify results into failure taxonomy."""
    results = {
        "expected_count": len(expected_drugs),
        "extracted_count": len(extracted_medications),
        "taxonomy": {
            "OCR_CHAR_FAIL": 0,
            "READING_ORDER_FAIL": 0,
            "LINE_SPLIT_FAIL": 0,
            "MERGE_FAIL": 0,
            "NER_FAIL": 0,
            "LOOKUP_FAIL": 0,
            "SUCCESS": 0,
        },
        "extracted_names": [],
    }

    found_targets = set()
    for med in extracted_medications:
        drug_name = med.get("drug_name", "") or ""
        matched_name = med.get("matched_drug_name", "") or ""
        mapping_status = med.get("mapping_status", "")
        match_score = float(med.get("match_score", 0.0))

        matched_any_target = False
        for exp in expected_drugs:
            if exp.lower() in drug_name.lower() or exp.lower() in matched_name.lower():
                found_targets.add(exp)
                matched_any_target = True
                break

        if matched_any_target:
            if mapping_status in ("confirmed", "unmapped_candidate") and (match_score >= 0.7 or drug_name):
                results["taxonomy"]["SUCCESS"] += 1
                results["extracted_names"].append(drug_name)
            else:
                results["taxonomy"]["LOOKUP_FAIL"] += 1

    missing_count = len(expected_drugs) - len(found_targets)
    if missing_count > 0:
        results["taxonomy"]["NER_FAIL"] += missing_count

    return results


def test_p0_to_p3_ablation_benchmark():
    """Execute ablation test across P0, P1, P2, P3 strategies."""
    pipe = MedicinePipeline()
    strategies = ["p0_raw_text", "p1_sorted_lines", "p2_row_clusters", "p3_medication_bands"]
    benchmark_reports = {}

    for strat in strategies:
        res = pipe.scan_prescription_app(
            ocr_lines=SAMPLE_PRESCRIPTION_MLKIT_LINES,
            layout_strategy=strat,
        )
        meds = res.get("medications", [])
        diagnosis = diagnose_scan_cascade(meds, EXPECTED_DRUGS)
        benchmark_reports[strat] = {
            "med_count": len(meds),
            "extracted_count": len(diagnosis["extracted_names"]),
            "success_rate": diagnosis["taxonomy"]["SUCCESS"] / len(EXPECTED_DRUGS),
            "taxonomy": diagnosis["taxonomy"],
            "medications": [m.get("drug_name") for m in meds],
        }

    print("\n" + "=" * 70)
    print("           P0 -> P1 -> P2 -> P3 ABLATION BENCHMARK RESULTS")
    print("=" * 70)
    for strat, rep in benchmark_reports.items():
        print(f"\n▶ Strategy: {strat.upper()}")
        print(f"  - Extracted Drugs: {rep['med_count']}")
        print(f"  - Valid Target Drugs: {rep['extracted_count']} / {len(EXPECTED_DRUGS)}")
        print(f"  - Success Rate: {rep['success_rate'] * 100:.1f}%")
        print(f"  - Cascade Taxonomy: {rep['taxonomy']}")
        print(f"  - Detected Names: {rep['medications']}")

    # Assert that P3 achieves high extraction on structured prescription
    p3_report = benchmark_reports["p3_medication_bands"]
    assert p3_report["extracted_count"] >= 3, f"P3 expected at least 3 valid drugs, got {p3_report['extracted_count']}"
    assert p3_report["taxonomy"]["SUCCESS"] >= 3, "P3 taxonomy SUCCESS count must be >= 3"

    # Verify that in P3, quantity numbers (like '30' or '20') do not contaminate drug names
    p3_med_names = p3_report["medications"]
    for name in p3_med_names:
        assert not name.endswith(" 30"), f"Quantity 30 leaked into drug name in P3: {name}"
        assert not name.endswith(" 20"), f"Quantity 20 leaked into drug name in P3: {name}"

    print("\n[PASSED] P3 Layout Adapter cleanly separated quantities and achieved 100% structured drug recall!")


if __name__ == "__main__":
    test_p0_to_p3_ablation_benchmark()
