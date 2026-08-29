"""
tests/test_ai_semantic_filter.py

Test AISemanticFilter and MedicinePipeline on debug scan outputs.
"""

import sys
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from core.classify.ai_semantic_filter import AISemanticFilter
from core.pipeline import MedicinePipeline


def test_ai_semantic_filter_direct():
    print("--- Testing AISemanticFilter Direct Component Evaluation ---")

    # 1. Hospital header noise
    label, conf, reason = AISemanticFilter.evaluate_candidate(
        text="BVÐK HỎA HÁ0 MEDIC CẦN THƠ",
        ocr_text="BVÐK HỎA HÁ0 - MEDIC CẦN THƠ",
        match_score=0.0,
    )
    print(f"Hospital Header: label={label}, conf={conf}, reason={reason}")
    assert label == "NOISE_ADMIN", f"Failed: Hospital header expected NOISE_ADMIN, got {label}"

    # 2. Patient name noise
    label, conf, reason = AISemanticFilter.evaluate_candidate(
        text="TRÂN LÊ MỸ PHƯƠNG",
        ocr_text="Họ tên bệnh nhân: TRÂN LÊ MỸ PHƯƠNG",
        match_score=0.0,
    )
    print(f"Patient Name: label={label}, conf={conf}, reason={reason}")
    assert label == "NOISE_ADMIN", f"Failed: Patient name expected NOISE_ADMIN, got {label}"

    # 3. Address noise
    label, conf, reason = AISemanticFilter.evaluate_candidate(
        text="Cách Mạng Thâng Tám,",
        ocr_text="102 Cách Mạng Thâng Tám, P. Cái Khế, Q. NK, TPCT",
        match_score=0.0,
    )
    print(f"Address: label={label}, conf={conf}, reason={reason}")
    assert label == "NOISE_ADMIN", f"Failed: Address expected NOISE_ADMIN, got {label}"

    # 4. Valid Drug (Lansoprazol 30mg)
    label, conf, reason = AISemanticFilter.evaluate_candidate(
        text="Lansoprazol",
        ocr_text="Lansoprazol 30mg (Savi Lansoprazole 30)",
        match_score=1.0,
        matched_name="Lansoprazol",
    )
    print(f"Valid Drug: label={label}, conf={conf}, reason={reason}")
    assert label == "DRUG", f"Failed: Valid drug expected DRUG, got {label}"

    # 5. Valid Drug (Magnesi trisilicat + nhôm hydroxyd 250mg+120mg)
    label, conf, reason = AISemanticFilter.evaluate_candidate(
        text="Magnesi trisilicat + nhôm hydroxyd 250mg+120mg",
        ocr_text="Magnesi trisilicat + nhôm hydroxyd 250mg+120mg (Mezatrihexyl)",
        match_score=0.72,
        matched_name="Magnesi trisilicat",
    )
    print(f"Valid Drug 2: label={label}, conf={conf}, reason={reason}")
    assert label == "DRUG", f"Failed: Valid drug expected DRUG, got {label}"

    print("-> ALL DIRECT COMPONENT TESTS PASSED!\n")


def test_full_pipeline_with_ai_filter():
    print("--- Testing Full Pipeline With AI Semantic Filter ---")
    debug_dir = ROOT / "data" / "output" / "debug_scans"
    scan_files = [
        debug_dir / "scan_20260722_000027_065865_debug.json",
        debug_dir / "scan_20260722_000124_290677_debug.json",
    ]

    pipe = MedicinePipeline()

    for sf in scan_files:
        if not sf.exists():
            print(f"Skipping {sf.name}")
            continue

        with open(sf, "r", encoding="utf-8") as f:
            data = json.load(f)

        ocr_text = data.get("ocr_text", "")
        res = pipe.scan_prescription_app(ocr_text)
        meds = res.get("medications", [])

        print(f"\n{sf.name} -> Extracted {len(meds)} drugs:")
        for m in meds:
            print(f"  - [{m.get('mapping_status')}] {m.get('drug_name')}")

        med_names = [m.get("drug_name") for m in meds]

        assert len(meds) == 2, f"Expected 2 drugs, got {len(meds)}"
        assert any("Lansoprazol" in n for n in med_names), "Missing Lansoprazol"
        assert any("Magnesi" in n for n in med_names), "Missing Magnesi trisilicat"

        print("-> PASS for", sf.name)


if __name__ == "__main__":
    test_ai_semantic_filter_direct()
    test_full_pipeline_with_ai_filter()
