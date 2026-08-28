import os
import sys
from pathlib import Path

ROOT = Path(__file__).parent.parent.parent
sys.path.insert(0, str(ROOT))


def test_api_alignment():
    from core.pipeline import MedicinePipeline
    pipeline = MedicinePipeline()

    sample_text = "1) Celecoxib 200mg - 20 Viên\n2) Loratadine 10mg - 10 Viên"
    result = pipeline.scan_prescription_app(ocr_text=sample_text)

    drugs = result.get("medications", [])
    print(f"Found {len(drugs)} drugs via new API path.")
    for d in drugs:
        print(
            f"  - {d.get('drug_name')} (score: {d.get('match_score')}) "
            f"[bbox: {d.get('bbox')}] [ocr: {d.get('ocr_text')}]"
        )


if __name__ == "__main__":
    test_api_alignment()
