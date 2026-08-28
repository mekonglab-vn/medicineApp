"""
run_pipeline.py — MedicineApp CLI runner (Text-only Fast-path).

Chạy thử nghiệm và debug PhoBERT NER + Drug Lookup từ văn bản OCR (On-device).

Usage:
  python scripts/run_pipeline.py --text "1) Celecoxib 200mg - 20 Viên\n2) Loratadine 10mg"
  python scripts/run_pipeline.py --text-file data/sample_ocr.txt
"""

import json
import logging
import os
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def print_header(text, char="═"):
    line = char * 60
    print(f"\n{line}")
    print(f"  {text}")
    print(f"{line}")


def main():
    import argparse
    parser = argparse.ArgumentParser(description="MedicineApp Text-only Pipeline")
    parser.add_argument("--text", type=str, help="Direct OCR text string")
    parser.add_argument("--text-file", type=str, help="Path to OCR text file")
    args = parser.parse_args()

    ocr_text = None
    if args.text:
        ocr_text = args.text
    elif args.text_file:
        with open(args.text_file, "r", encoding="utf-8") as f:
            ocr_text = f.read()

    if not ocr_text or not ocr_text.strip():
        logger.error("Vui lòng cung cấp đầu vào bằng --text hoặc --text-file")
        sys.exit(1)

    print_header("Loading Models (Fast-path NER + DrugLookup)")
    t0 = time.time()

    from core.pipeline import MedicinePipeline
    pipeline = MedicinePipeline(device="cpu")

    print(f"  Models loaded in {time.time()-t0:.1f}s")

    print_header("Running Pipeline")
    t_start = time.time()
    result = pipeline.scan_prescription_app(ocr_text=ocr_text)
    t_exec = time.time() - t_start

    if "error" in result:
        print(f"  ❌ Lỗi: {result['error']}")
        sys.exit(1)

    medications = result.get("medications", [])
    print(f"  🏁 Hoàn thành sau {t_exec:.2f}s | Tìm thấy {len(medications)} thuốc:")
    for idx, med in enumerate(medications, 1):
        raw = med.get("drug_name_raw") or med.get("ocr_text", "")
        matched = med.get("matched_drug_name") or med.get("mapped_drug_name") or "Không khớp CSDL"
        reg = med.get("registration_number", "N/A")
        strength = med.get("normalized_query_strength") or med.get("normalized_candidate_strength") or "N/A"
        score = int((med.get("match_score", 0) or 0) * 100)
        reason = med.get("resolution_reason", "N/A")
        print(f"  {idx}. Gốc: '{raw}'")
        print(f"     → Trùng khớp: '{matched}' | Số ĐK: {reg} | Hàm lượng: {strength} | Score: {score}% | Lý do: {reason}")


if __name__ == "__main__":
    main()
