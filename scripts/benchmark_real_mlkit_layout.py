"""
scripts/benchmark_real_mlkit_layout.py — Real-Data P0/P1/P2/P3 Layout Ablation Benchmark.

Evaluates the real-world impact of MLKitLayoutAdapter geometry reconstruction
on actual Google ML Kit OCR captures and canonical ground truth from development/validation splits.

Uses:
- Production PhoBERT NER model (models/phobert_ner_model)
- Production DrugLookup (data/drug_db_vn_full.json - 9,284 drugs)
- Development/Validation captures from ../medicineApp-rxie/data/ocr_final/
- Canonical Ground Truth from ../medicineApp-rxie/data/canonical_ground_truth/
- SEALED TEST SPLIT IS NEVER ACCESSED.
"""

from __future__ import annotations

import argparse
import csv
import json
import logging
import re
import unicodedata
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from core.pipeline import MedicinePipeline
from core.classify.mlkit_layout_adapter import MLKitLayoutAdapter

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("RealLayoutAblation")


def normalize_text(text: Optional[str]) -> str:
    """Normalize Unicode (NFC), lowercase, remove punctuation, collapse whitespace."""
    if not text:
        return ""
    text = unicodedata.normalize("NFC", text)
    text = text.lower()
    text = re.sub(r"[^\w\s]", " ", text)
    return " ".join(text.split())


def extract_ocr_lines_from_mlkit_json(data: dict) -> list[dict[str, Any]]:
    """Extract line elements with bounding boxes from ML Kit OCR JSON."""
    lines = []
    blocks = data.get("blocks", [])
    for b_idx, b in enumerate(blocks):
        for l_idx, line in enumerate(b.get("lines", [])):
            text = line.get("text", "").strip()
            if not text:
                continue
            bbox = line.get("boundingBox") or line.get("bbox") or {}
            conf = float(line.get("confidence", 0.95))
            lines.append({
                "text": text,
                "bbox": bbox,
                "confidence": conf,
                "block_index": b_idx,
                "line_index": l_idx,
            })
    return lines


def match_prediction_to_gt(
    pred_drug_name: str,
    pred_matched_name: Optional[str],
    gt_meds: list[dict[str, Any]],
) -> tuple[Optional[dict[str, Any]], bool, bool]:
    """
    Check if a predicted drug matches any GT medication.
    Returns: (matched_gt_med, is_strict_match, is_normalized_match)
    """
    norm_pred = normalize_text(pred_drug_name)
    norm_matched = normalize_text(pred_matched_name)

    for gt in gt_meds:
        targets = [
            normalize_text(gt.get("brand_normalized")),
            normalize_text(gt.get("drug_normalized")),
            normalize_text(gt.get("brand_raw")),
            normalize_text(gt.get("drug_raw")),
        ]
        targets = [t for t in targets if t]

        # 1. Strict Match: exact equality or complete brand token containment
        for t in targets:
            if norm_pred == t or norm_matched == t:
                return gt, True, True
            if len(t) >= 4 and (t == norm_pred or t in norm_pred.split()):
                return gt, True, True

        # 2. Normalized Match: substring containment or high token overlap
        for t in targets:
            if len(t) >= 3 and (t in norm_pred or t in norm_matched or norm_pred in t):
                return gt, False, True

    return None, False, False


def classify_failure_cascade(
    gt_med: dict[str, Any],
    raw_ocr_text: str,
    layout_blocks: list[dict[str, Any]],
    extracted_meds: list[dict[str, Any]],
) -> str:
    """Classify why a GT medication was not successfully extracted."""
    targets = [
        normalize_text(gt_med.get("brand_normalized")),
        normalize_text(gt_med.get("drug_normalized")),
        normalize_text(gt_med.get("brand_raw")),
    ]
    targets = [t for t in targets if t and len(t) >= 3]
    norm_full_ocr = normalize_text(raw_ocr_text)

    # 1. OCR_CHAR_FAIL: Not present in raw OCR
    if not any(t in norm_full_ocr for t in targets):
        return "OCR_CHAR_FAIL"

    # 2. Check presence in reconstructed layout blocks
    block_texts = [normalize_text(b.get("text", "")) for b in layout_blocks]
    matching_blocks = [b for b, b_txt in zip(layout_blocks, block_texts) if any(t in b_txt for t in targets)]

    if not matching_blocks:
        return "LINE_SPLIT_FAIL"

    # 3. Check DrugLookup matching
    for m in extracted_meds:
        m_txt = normalize_text(m.get("drug_name", ""))
        matched_txt = normalize_text(m.get("matched_drug_name", ""))
        if any(t in m_txt or t in matched_txt for t in targets):
            if m.get("mapping_status") in ("confirmed", "unmapped_candidate") and float(m.get("match_score", 0.0)) >= 0.7:
                return "SUCCESS"
            else:
                return "LOOKUP_FAIL"

    return "NER_FAIL"


def run_real_layout_ablation(
    rxie_root: Path,
    output_dir: Path,
    splits_filter: list[str],
    limit_captures: Optional[int] = None,
    rx_filter: Optional[str] = None,
):
    """Run real data P0/P1/P2/P3 layout ablation benchmark."""
    output_dir.mkdir(parents=True, exist_ok=True)
    splits_path = rxie_root / "data" / "manifests" / "balanced_prescription_splits.json"
    manifest_path = rxie_root / "data" / "manifests" / "prescriptions_manifest.json"
    gt_dir = rxie_root / "data" / "canonical_ground_truth"
    ocr_dir = rxie_root / "data" / "ocr_final"

    with open(splits_path, "r", encoding="utf-8") as f:
        splits = json.load(f)

    with open(manifest_path, "r", encoding="utf-8") as f:
        manifest = json.load(f)

    allowed_pids = set()
    for s in splits_filter:
        allowed_pids.update(splits.get(s, []))

    # Explicitly ensure SEALED TEST is NEVER accessed
    sealed_test_pids = set(splits.get("test", []))
    allowed_pids.difference_update(sealed_test_pids)

    if rx_filter:
        allowed_pids = {rx_filter} if rx_filter in allowed_pids else set()

    logger.info(f"Target prescriptions ({len(allowed_pids)}): {sorted(allowed_pids)}")
    logger.info(f"Sealed test prescriptions strictly excluded: {sorted(sealed_test_pids)}")

    # Collect captures to evaluate
    captures_to_eval = []
    for g in manifest.get("groups", []):
        pid = g["prescription_id"]
        if pid not in allowed_pids:
            continue
        gt_file = gt_dir / f"{pid}.json"
        if not gt_file.exists():
            continue
        with open(gt_file, "r", encoding="utf-8") as f:
            gt_data = json.load(f)

        for img in g.get("images", []):
            img_id = img["image_id"]
            ocr_file = ocr_dir / f"{img_id}.json"
            if ocr_file.exists():
                captures_to_eval.append({
                    "prescription_id": pid,
                    "image_id": img_id,
                    "ocr_file": ocr_file,
                    "gt_medications": gt_data.get("medications", []),
                    "split": "val" if pid in splits.get("val", []) else "train",
                })

    if limit_captures:
        captures_to_eval = captures_to_eval[:limit_captures]

    logger.info(f"Total captures to benchmark: {len(captures_to_eval)}")

    # Initialize Pipeline & Strategies
    pipe = MedicinePipeline()
    strategy_keys = ["p0", "p1", "p2", "p3"]
    strat_map = {
        "p0": "p0_raw_text",
        "p1": "p1_sorted_lines",
        "p2": "p2_row_clusters",
        "p3": "p3_medication_bands",
    }

    # Results collectors
    per_capture_records = []
    per_prescription_stats = defaultdict(lambda: {s: {"tp": 0, "fp": 0, "fn": 0, "gt_total": 0, "confirmed": 0} for s in strategy_keys})
    strategy_overall = {s: {"tp": 0, "fp": 0, "fn": 0, "gt_total": 0, "confirmed": 0} for s in strategy_keys}
    taxonomy_counts = {s: defaultdict(int) for s in strategy_keys}
    prediction_jsonl_writers = {s: open(output_dir / f"{s}_predictions.jsonl", "w", encoding="utf-8") for s in strategy_keys}
    p3_fixes_examples = []

    # Benchmark loop
    for cap_idx, cap in enumerate(captures_to_eval):
        pid = cap["prescription_id"]
        img_id = cap["image_id"]
        gt_meds = cap["gt_medications"]
        gt_count = len(gt_meds)

        with open(cap["ocr_file"], "r", encoding="utf-8") as f:
            ocr_data = json.load(f)

        raw_ocr_lines = extract_ocr_lines_from_mlkit_json(ocr_data)
        raw_full_text = ocr_data.get("fullText", "") or "\n".join(l["text"] for l in raw_ocr_lines)

        cap_results = {"prescription_id": pid, "image_id": img_id, "gt_count": gt_count}
        cap_strategy_preds = {}

        for s_key, strat in strat_map.items():
            res = pipe.scan_prescription_app(
                ocr_lines=raw_ocr_lines,
                layout_strategy=strat,
            )
            extracted_meds = res.get("medications", [])
            ocr_blocks = res.get("ocr_blocks", [])

            # Evaluate matches
            matched_gt_ids = set()
            tp = 0
            fp = 0
            confirmed = 0

            for m in extracted_meds:
                pred_name = m.get("drug_name", "") or m.get("ocr_text", "")
                matched_name = m.get("matched_drug_name")
                status = m.get("mapping_status")

                matched_gt, is_strict, is_norm = match_prediction_to_gt(pred_name, matched_name, gt_meds)
                if matched_gt is not None:
                    gt_mid = matched_gt.get("medication_id", id(matched_gt))
                    if gt_mid not in matched_gt_ids:
                        matched_gt_ids.add(gt_mid)
                        tp += 1
                        if status == "confirmed":
                            confirmed += 1
                    else:
                        # Duplicate detection
                        pass
                else:
                    fp += 1

            fn = max(0, gt_count - len(matched_gt_ids))

            # Failure taxonomy classification for each GT medication
            for gt in gt_meds:
                gt_mid = gt.get("medication_id", id(gt))
                if gt_mid in matched_gt_ids:
                    taxonomy_counts[s_key]["SUCCESS"] += 1
                else:
                    failure_tag = classify_failure_cascade(gt, raw_full_text, ocr_blocks, extracted_meds)
                    taxonomy_counts[s_key][failure_tag] += 1

            # Store metrics
            prec = tp / (tp + fp) if (tp + fp) > 0 else 0.0
            rec = tp / gt_count if gt_count > 0 else 0.0
            f1 = (2 * prec * rec) / (prec + rec) if (prec + rec) > 0 else 0.0

            cap_results[f"{s_key}_tp"] = tp
            cap_results[f"{s_key}_fp"] = fp
            cap_results[f"{s_key}_fn"] = fn
            cap_results[f"{s_key}_precision"] = round(prec, 4)
            cap_results[f"{s_key}_recall"] = round(rec, 4)
            cap_results[f"{s_key}_f1"] = round(f1, 4)
            cap_results[f"{s_key}_confirmed"] = confirmed

            strategy_overall[s_key]["tp"] += tp
            strategy_overall[s_key]["fp"] += fp
            strategy_overall[s_key]["fn"] += fn
            strategy_overall[s_key]["gt_total"] += gt_count
            strategy_overall[s_key]["confirmed"] += confirmed

            per_prescription_stats[pid][s_key]["tp"] += tp
            per_prescription_stats[pid][s_key]["fp"] += fp
            per_prescription_stats[pid][s_key]["fn"] += fn
            per_prescription_stats[pid][s_key]["gt_total"] += gt_count
            per_prescription_stats[pid][s_key]["confirmed"] += confirmed

            # Write JSONL prediction record
            pred_record = {
                "prescription_id": pid,
                "image_id": img_id,
                "strategy": strat,
                "tp": tp,
                "fp": fp,
                "fn": fn,
                "precision": prec,
                "recall": rec,
                "f1": f1,
                "extracted_medications": extracted_meds,
            }
            prediction_jsonl_writers[s_key].write(json.dumps(pred_record, ensure_ascii=False) + "\n")
            cap_strategy_preds[s_key] = extracted_meds

        per_capture_records.append(cap_results)

        # Detect P0 -> P3 fix examples
        p0_tp = cap_results["p0_tp"]
        p3_tp = cap_results["p3_tp"]
        if p3_tp > p0_tp and len(p3_fixes_examples) < 20:
            p3_fixes_examples.append({
                "prescription_id": pid,
                "image_id": img_id,
                "p0_extracted": [m.get("drug_name") for m in cap_strategy_preds["p0"]],
                "p3_extracted": [m.get("drug_name") for m in cap_strategy_preds["p3"]],
                "gt_drugs": [g.get("brand_raw") or g.get("drug_raw") for g in gt_meds],
            })

        if (cap_idx + 1) % 10 == 0 or (cap_idx + 1) == len(captures_to_eval):
            logger.info(f"Processed {cap_idx + 1}/{len(captures_to_eval)} captures...")

    for w in prediction_jsonl_writers.values():
        w.close()

    # ── 1. Per Capture CSV ──────────────────────────────────────────────────
    per_capture_csv = output_dir / "per_capture.csv"
    with open(per_capture_csv, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(per_capture_records[0].keys()))
        writer.writeheader()
        writer.writerows(per_capture_records)

    # ── 2. Per Prescription CSV ─────────────────────────────────────────────
    per_rx_records = []
    for pid, s_dict in per_prescription_stats.items():
        row = {"prescription_id": pid}
        for s_key in strategy_keys:
            s_tp = s_dict[s_key]["tp"]
            s_fp = s_dict[s_key]["fp"]
            s_gt = s_dict[s_key]["gt_total"]
            p = s_tp / (s_tp + s_fp) if (s_tp + s_fp) > 0 else 0.0
            r = s_tp / s_gt if s_gt > 0 else 0.0
            f1 = (2 * p * r) / (p + r) if (p + r) > 0 else 0.0
            row[f"{s_key}_precision"] = round(p, 4)
            row[f"{s_key}_recall"] = round(r, 4)
            row[f"{s_key}_f1"] = round(f1, 4)
            row[f"{s_key}_tp"] = s_tp
            row[f"{s_key}_fp"] = s_fp
            row[f"{s_key}_fn"] = max(0, s_gt - s_tp)
        per_rx_records.append(row)

    per_rx_csv = output_dir / "per_prescription.csv"
    with open(per_rx_csv, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(per_rx_records[0].keys()))
        writer.writeheader()
        writer.writerows(per_rx_records)

    # ── 3. Failure Taxonomy CSV ─────────────────────────────────────────────
    tax_records = []
    all_tax_keys = ["OCR_CHAR_FAIL", "READING_ORDER_FAIL", "LINE_SPLIT_FAIL", "MERGE_FAIL", "NER_FAIL", "LOOKUP_FAIL", "SUCCESS"]
    for s_key in strategy_keys:
        r = {"strategy": strat_map[s_key]}
        for k in all_tax_keys:
            r[k] = taxonomy_counts[s_key][k]
        tax_records.append(r)

    tax_csv = output_dir / "failure_taxonomy.csv"
    with open(tax_csv, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=["strategy"] + all_tax_keys)
        writer.writeheader()
        writer.writerows(tax_records)

    # ── 4. Summary CSV & Macro Calculation ──────────────────────────────────
    summary_records = []
    for s_key in strategy_keys:
        strat = strat_map[s_key]
        # Micro metrics
        tot_tp = strategy_overall[s_key]["tp"]
        tot_fp = strategy_overall[s_key]["fp"]
        tot_gt = strategy_overall[s_key]["gt_total"]
        tot_fn = max(0, tot_gt - tot_tp)
        micro_p = tot_tp / (tot_tp + tot_fp) if (tot_tp + tot_fp) > 0 else 0.0
        micro_r = tot_tp / tot_gt if tot_gt > 0 else 0.0
        micro_f1 = (2 * micro_p * micro_r) / (micro_p + micro_r) if (micro_p + micro_r) > 0 else 0.0
        lookup_r = strategy_overall[s_key]["confirmed"] / tot_gt if tot_gt > 0 else 0.0

        # Prescription-balanced macro metrics
        macro_p_list = [r[f"{s_key}_precision"] for r in per_rx_records]
        macro_r_list = [r[f"{s_key}_recall"] for r in per_rx_records]
        macro_f1_list = [r[f"{s_key}_f1"] for r in per_rx_records]
        macro_p = sum(macro_p_list) / max(1, len(macro_p_list))
        macro_r = sum(macro_r_list) / max(1, len(macro_r_list))
        macro_f1 = sum(macro_f1_list) / max(1, len(macro_f1_list))

        summary_records.append({
            "strategy": strat,
            "micro_precision": round(micro_p, 4),
            "micro_recall": round(micro_r, 4),
            "micro_f1": round(micro_f1, 4),
            "macro_precision": round(macro_p, 4),
            "macro_recall": round(macro_r, 4),
            "macro_f1": round(macro_f1, 4),
            "lookup_confirmed_recall": round(lookup_r, 4),
            "tp": tot_tp,
            "fp": tot_fp,
            "fn": tot_fn,
            "gt_total": tot_gt,
        })

    summary_csv = output_dir / "summary.csv"
    with open(summary_csv, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(summary_records[0].keys()))
        writer.writeheader()
        writer.writerows(summary_records)

    # Save P3 fix examples
    with open(output_dir / "p3_fixes_examples.json", "w", encoding="utf-8") as f:
        json.dump(p3_fixes_examples, f, ensure_ascii=False, indent=2)

    # ── 5. Terminal Display ─────────────────────────────────────────────────
    print("\n" + "=" * 94)
    print("        REAL-DATA P0 / P1 / P2 / P3 LAYOUT ABLATION BENCHMARK RESULTS")
    print("=" * 94)
    print(f"{'Strategy':<20} | {'Micro P':<8} {'Micro R':<8} {'Micro F1':<8} | {'Macro P':<8} {'Macro R':<8} {'Macro F1':<8} | {'Lookup R':<8}")
    print("-" * 94)
    for s in summary_records:
        print(f"{s['strategy']:<20} | {s['micro_precision']*100:<7.2f}% {s['micro_recall']*100:<7.2f}% {s['micro_f1']*100:<7.2f}% | {s['macro_precision']*100:<7.2f}% {s['macro_recall']*100:<7.2f}% {s['macro_f1']*100:<7.2f}% | {s['lookup_confirmed_recall']*100:<7.2f}%")
    print("=" * 94)

    print("\n--- Failure Taxonomy Breakdown ---")
    print(f"{'Strategy':<20} | {'OCR_FAIL':<10} {'SPLIT':<8} {'MERGE':<8} {'NER_FAIL':<10} {'LOOKUP_FAIL':<12} {'SUCCESS':<10}")
    print("-" * 88)
    for t in tax_records:
        print(f"{t['strategy']:<20} | {t['OCR_CHAR_FAIL']:<10} {t['LINE_SPLIT_FAIL']:<8} {t['MERGE_FAIL']:<8} {t['NER_FAIL']:<10} {t['LOOKUP_FAIL']:<12} {t['SUCCESS']:<10}")
    print("-" * 88)

    print("\n--- Per-prescription summaries ---")
    print(f"Computed aggregate metrics for {len(per_prescription_stats)} authorized prescription groups.")

    logger.info(f"Benchmark completed successfully! All reports saved to: {output_dir.resolve()}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Real-Data MLKit Layout Ablation Benchmark")
    parser.add_argument("--rxie-root", type=str, default="../medicineApp-rxie", help="Path to medicineApp-rxie worktree")
    parser.add_argument("--output-dir", type=str, default="reports/real_layout_ablation", help="Output directory for reports")
    parser.add_argument("--split", type=str, default="val", choices=["val", "train", "all_dev"], help="Dataset split to evaluate")
    parser.add_argument("--limit", type=int, default=None, help="Limit number of captures to evaluate")
    parser.add_argument("--rx", type=str, default=None, help="Evaluate one authorized prescription identifier")
    args = parser.parse_args()

    splits_filter = ["val"] if args.split == "val" else (["train"] if args.split == "train" else ["val", "train"])
    run_real_layout_ablation(
        rxie_root=Path(args.rxie_root),
        output_dir=Path(args.output_dir),
        splits_filter=splits_filter,
        limit_captures=args.limit,
        rx_filter=args.rx,
    )
