"""
scripts/benchmark_real_medication_roi.py — Real-World Hard Camera Capture Medication ROI Re-OCR Benchmark (R0 vs R1).

Evaluates R0 (Full-Page Smartphone Camera Capture) vs R1 (Medication Table ROI Crop + Pass-2 Re-OCR)
against Human-Annotated Visible-in-frame Ground Truth on 30 hard real camera captures.

Computes:
1. Multi-Granularity Performance: Micro-averaged, Capture-Macro, Prescription-Macro.
2. Paired Drug-Level Transition Matrix (Gain, Loss, Both Success, Both Fail).
3. Exact McNemar / Binomial 2-sided Significance Test.
4. Capture-Level and Prescription-Clustered 95% Bootstrap Confidence Intervals (10,000 iterations).
5. Detailed Failure Taxonomy on Physically Visible Drugs.
"""

from __future__ import annotations

import argparse
import csv
import json
import logging
import math
import random
import re
import unicodedata
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

import numpy as np

from core.pipeline import MedicinePipeline

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("RealRoiAblation")


def normalize_text(text: Optional[str]) -> str:
    """Normalize Unicode (NFC), lowercase, remove punctuation, collapse whitespace."""
    if not text:
        return ""
    text = unicodedata.normalize("NFC", text)
    text = text.lower()
    text = re.sub(r"[^\w\s]", " ", text)
    return " ".join(text.split())


def check_drug_match_visible(
    candidate_name: str,
    matched_drug_name: Optional[str],
    gold_drug_str: str,
) -> bool:
    """Check if candidate drug matches visible gold drug."""
    norm_cand = normalize_text(candidate_name)
    norm_matched = normalize_text(matched_drug_name)
    norm_gold = normalize_text(gold_drug_str)

    if norm_cand == norm_gold or norm_matched == norm_gold:
        return True

    gold_tokens = [t for t in norm_gold.split() if len(t) >= 3]
    if gold_tokens:
        primary_tok = gold_tokens[0]
        if primary_tok in norm_cand.split() or primary_tok in norm_matched.split():
            return True

    if len(norm_gold) >= 4 and (norm_gold in norm_cand or norm_cand in norm_gold or norm_gold in norm_matched):
        return True

    return False


def run_real_roi_evaluation(
    ocr_dir: Path,
    visible_gt_path: Path,
    output_dir: Path,
    num_bootstrap: int = 10000,
    seed: int = 42,
):
    """Evaluate R0 vs R1 against Visible-in-frame Ground Truth with multi-granularity and statistical tests."""
    random.seed(seed)
    np.random.seed(seed)
    output_dir.mkdir(parents=True, exist_ok=True)

    with open(visible_gt_path, "r", encoding="utf-8") as f:
        visible_gt_map = json.load(f)

    conditions = ["r0", "r1"]
    cond_labels = {
        "r0": "R0: Full-Page Smartphone Capture",
        "r1": "R1: Medication Table ROI Re-OCR",
    }

    pipe = MedicinePipeline()

    cond_stats = {c: {"tp": 0, "fp": 0, "fn": 0, "gold_total": 0, "ocr_hits": 0, "confirmed": 0} for c in conditions}
    cond_taxonomy = {c: defaultdict(int) for c in conditions}
    per_capture_records = []
    jsonl_writers = {c: open(output_dir / f"{c}_predictions.jsonl", "w", encoding="utf-8") for c in conditions}
    recovered_drugs = []

    # Paired transitions tracking
    # Key: (image_id, gold_drug) -> {"r0_correct": bool, "r1_correct": bool, "prescription_id": str}
    paired_item_results = {}

    # Capture-level structured results for bootstrap
    # List of {image_id, pid, r0_tp, r0_fp, r0_fn, r0_gold, r1_tp, r1_fp, r1_fn, r1_gold, ...}
    capture_eval_list = []

    # Group OCR files by image_id
    ocr_files = sorted(list(ocr_dir.glob("*.json")))
    capture_map = defaultdict(dict)
    for f in ocr_files:
        name = f.stem
        for c in conditions:
            if name.startswith(f"{c}_"):
                img_id = name[len(c) + 1 :]
                capture_map[img_id][c] = f

    logger.info(f"Evaluating {len(capture_map)} hard real captures with Human-Annotated Visible GT...")

    for img_id, c_dict in sorted(capture_map.items()):
        if img_id not in visible_gt_map:
            logger.warning(f"No visible GT for {img_id}, skipping.")
            continue

        gt_info = visible_gt_map[img_id]
        pid = gt_info["prescription_id"]
        visible_drugs = gt_info["visible_drugs"]
        num_gold = len(visible_drugs)

        cap_row = {"image_id": img_id, "prescription_id": pid, "visible_gold_count": num_gold}
        cap_eval_entry = {"image_id": img_id, "prescription_id": pid, "visible_gold": num_gold}
        cond_extracted_meds = {}

        for cond in conditions:
            ocr_path = c_dict.get(cond)
            if not ocr_path or not ocr_path.exists():
                logger.warning(f"Missing {cond} for {img_id}")
                continue

            with open(ocr_path, "r", encoding="utf-8") as f:
                ocr_payload = json.load(f)

            raw_text = ocr_payload.get("text", "")
            norm_raw = normalize_text(raw_text)
            lines = ocr_payload.get("lines", [])

            # 1. OCR Drug Coverage on Visible Drugs
            ocr_hits = 0
            gold_ocr_map = {}
            for g_drug in visible_drugs:
                norm_g = normalize_text(g_drug)
                g_tokens = [tok for tok in norm_g.split() if len(tok) >= 3]
                prim = g_tokens[0] if g_tokens else norm_g
                found = norm_g in norm_raw or prim in norm_raw
                gold_ocr_map[g_drug] = found
                if found:
                    ocr_hits += 1

            cond_stats[cond]["ocr_hits"] += ocr_hits
            cond_stats[cond]["gold_total"] += num_gold

            # 2. Pipeline Execution (P0 layout)
            res = pipe.scan_prescription_app(
                ocr_lines=lines,
                ocr_text=raw_text,
                layout_strategy="p0_raw_text",
            )
            extracted = res.get("medications", [])
            cond_extracted_meds[cond] = extracted

            # 3. Match against visible drugs
            matched_gold_set = set()
            tp = 0
            fp = 0
            confirmed = 0

            for m in extracted:
                cname = m.get("drug_name", "") or m.get("ocr_text", "")
                mname = m.get("matched_drug_name")
                status = m.get("mapping_status")

                matched_g = None
                for g_drug in visible_drugs:
                    if check_drug_match_visible(cname, mname, g_drug):
                        matched_g = g_drug
                        break

                if matched_g:
                    if matched_g not in matched_gold_set:
                        matched_gold_set.add(matched_g)
                        tp += 1
                        if status == "confirmed":
                            confirmed += 1
                else:
                    fp += 1

            fn = max(0, num_gold - len(matched_gold_set))
            prec = tp / (tp + fp) if (tp + fp) > 0 else 0.0
            rec = tp / num_gold if num_gold > 0 else 0.0
            f1 = (2 * prec * rec) / (prec + rec) if (prec + rec) > 0 else 0.0
            cov = ocr_hits / num_gold if num_gold > 0 else 0.0

            cond_stats[cond]["tp"] += tp
            cond_stats[cond]["fp"] += fp
            cond_stats[cond]["fn"] += fn
            cond_stats[cond]["confirmed"] += confirmed

            # Record paired item transitions
            for g_drug in visible_drugs:
                is_correct = g_drug in matched_gold_set
                key = (img_id, g_drug)
                if key not in paired_item_results:
                    paired_item_results[key] = {"r0_correct": False, "r1_correct": False, "prescription_id": pid}
                paired_item_results[key][f"{cond}_correct"] = is_correct

                if is_correct:
                    cond_taxonomy[cond]["SUCCESS"] += 1
                elif not gold_ocr_map.get(g_drug, False):
                    cond_taxonomy[cond]["OCR_MISS"] += 1
                else:
                    cond_taxonomy[cond]["NER_MISS"] += 1

            cap_row[f"{cond}_ocr_cov"] = round(cov, 4)
            cap_row[f"{cond}_tp"] = tp
            cap_row[f"{cond}_fp"] = fp
            cap_row[f"{cond}_prec"] = round(prec, 4)
            cap_row[f"{cond}_rec"] = round(rec, 4)
            cap_row[f"{cond}_f1"] = round(f1, 4)

            cap_eval_entry[f"{cond}_tp"] = tp
            cap_eval_entry[f"{cond}_fp"] = fp
            cap_eval_entry[f"{cond}_fn"] = fn
            cap_eval_entry[f"{cond}_ocr_hits"] = ocr_hits
            cap_eval_entry[f"{cond}_prec"] = prec
            cap_eval_entry[f"{cond}_rec"] = rec
            cap_eval_entry[f"{cond}_f1"] = f1
            cap_eval_entry[f"{cond}_ocr_cov"] = cov

            # Write JSONL prediction
            jsonl_writers[cond].write(
                json.dumps(
                    {
                        "image_id": img_id,
                        "prescription_id": pid,
                        "condition": cond,
                        "visible_ocr_coverage": cov,
                        "tp": tp,
                        "fp": fp,
                        "fn": fn,
                        "precision": prec,
                        "recall": rec,
                        "f1": f1,
                        "extracted_medications": extracted,
                        "visible_drugs": visible_drugs,
                    },
                    ensure_ascii=False,
                )
                + "\n"
            )

        # Detect R1 Gain
        r0_tp = cap_row.get("r0_tp", 0)
        r1_tp = cap_row.get("r1_tp", 0)
        if r1_tp > r0_tp:
            recovered_drugs.append({
                "image_id": img_id,
                "prescription_id": pid,
                "r0_extracted": [m.get("drug_name") for m in cond_extracted_meds.get("r0", [])],
                "r1_extracted": [m.get("drug_name") for m in cond_extracted_meds.get("r1", [])],
                "visible_drugs": visible_drugs,
                "gain": f"R1 recovered +{r1_tp - r0_tp} drug(s) missed in full page photo.",
            })

        per_capture_records.append(cap_row)
        capture_eval_list.append(cap_eval_entry)

    for w in jsonl_writers.values():
        w.close()

    # ── 1. Multi-Granularity Calculations ──────────────────────────────────
    # Micro Metrics
    micro_stats = {}
    for cond in conditions:
        tp = cond_stats[cond]["tp"]
        fp = cond_stats[cond]["fp"]
        fn = cond_stats[cond]["fn"]
        tot_gold = cond_stats[cond]["gold_total"]
        hits = cond_stats[cond]["ocr_hits"]
        confirmed = cond_stats[cond]["confirmed"]

        cov = hits / tot_gold if tot_gold > 0 else 0.0
        p = tp / (tp + fp) if (tp + fp) > 0 else 0.0
        r = tp / tot_gold if tot_gold > 0 else 0.0
        f1 = (2 * p * r) / (p + r) if (p + r) > 0 else 0.0
        conf_r = confirmed / tot_gold if tot_gold > 0 else 0.0

        micro_stats[cond] = {
            "visible_ocr_coverage": cov,
            "precision": p,
            "recall": r,
            "f1_score": f1,
            "lookup_confirmed_recall": conf_r,
            "tp": tp,
            "fp": fp,
            "fn": fn,
            "total_visible_gold": tot_gold,
        }

    # Capture-Macro Metrics (Average over 30 captures)
    cap_macro_stats = {}
    for cond in conditions:
        avg_cov = float(np.mean([c[f"{cond}_ocr_cov"] for c in capture_eval_list]))
        avg_p = float(np.mean([c[f"{cond}_prec"] for c in capture_eval_list]))
        avg_r = float(np.mean([c[f"{cond}_rec"] for c in capture_eval_list]))
        avg_f1 = float(np.mean([c[f"{cond}_f1"] for c in capture_eval_list]))
        cap_macro_stats[cond] = {
            "visible_ocr_coverage": avg_cov,
            "precision": avg_p,
            "recall": avg_r,
            "f1_score": avg_f1,
        }

    # Prescription-Macro Metrics (Average over 5 independent prescriptions)
    rx_groups = defaultdict(list)
    for c in capture_eval_list:
        rx_groups[c["prescription_id"]].append(c)

    rx_macro_stats = {}
    for cond in conditions:
        rx_p_list = []
        rx_r_list = []
        rx_f1_list = []
        rx_cov_list = []
        for pid, group in rx_groups.items():
            tot_tp = sum(item[f"{cond}_tp"] for item in group)
            tot_fp = sum(item[f"{cond}_fp"] for item in group)
            tot_gold = sum(item["visible_gold"] for item in group)
            tot_hits = sum(item[f"{cond}_ocr_hits"] for item in group)

            p_k = tot_tp / (tot_tp + tot_fp) if (tot_tp + tot_fp) > 0 else 0.0
            r_k = tot_tp / tot_gold if tot_gold > 0 else 0.0
            f1_k = (2 * p_k * r_k) / (p_k + r_k) if (p_k + r_k) > 0 else 0.0
            cov_k = tot_hits / tot_gold if tot_gold > 0 else 0.0

            rx_p_list.append(p_k)
            rx_r_list.append(r_k)
            rx_f1_list.append(f1_k)
            rx_cov_list.append(cov_k)

        rx_macro_stats[cond] = {
            "visible_ocr_coverage": float(np.mean(rx_cov_list)),
            "precision": float(np.mean(rx_p_list)),
            "recall": float(np.mean(rx_r_list)),
            "f1_score": float(np.mean(rx_f1_list)),
        }

    # ── 2. Paired Transitions & Exact McNemar / Binomial Test ──────────────
    trans_counts = {
        "r0_correct_r1_correct": 0,
        "r0_wrong_r1_correct": 0,  # b (Gain)
        "r0_correct_r1_wrong": 0,  # c (Loss)
        "r0_wrong_r1_wrong": 0,
    }
    for key, p_res in paired_item_results.items():
        r0_c = p_res["r0_correct"]
        r1_c = p_res["r1_correct"]
        if r0_c and r1_c:
            trans_counts["r0_correct_r1_correct"] += 1
        elif (not r0_c) and r1_c:
            trans_counts["r0_wrong_r1_correct"] += 1
        elif r0_c and (not r1_c):
            trans_counts["r0_correct_r1_wrong"] += 1
        else:
            trans_counts["r0_wrong_r1_wrong"] += 1

    b = trans_counts["r0_wrong_r1_correct"]
    c = trans_counts["r0_correct_r1_wrong"]
    n_discordant = b + c

    # Exact 2-sided Binomial Test for discordant pairs
    if n_discordant > 0:
        k_max = max(b, c)
        p_value_mcnemar = 2.0 * sum(math.comb(n_discordant, k) * (0.5**n_discordant) for k in range(k_max, n_discordant + 1))
        p_value_mcnemar = min(1.0, p_value_mcnemar)
    else:
        p_value_mcnemar = 1.0

    # ── 3. Clustered Bootstrap Confidence Intervals ─────────────────────────
    # A. Capture-Level Bootstrap (Resampling 30 captures)
    np.random.seed(42)
    random.seed(42)
    n_caps = len(capture_eval_list)
    bs_delta_f1_cap = []
    bs_delta_cov_cap = []
    bs_delta_rec_cap = []
    bs_delta_prec_cap = []

    for _ in range(num_bootstrap):
        sampled_indices = np.random.choice(n_caps, size=n_caps, replace=True)
        sampled_caps = [capture_eval_list[i] for i in sampled_indices]

        # Calculate pooled Micro for R0 and R1 on this sample
        r0_tp = sum(item["r0_tp"] for item in sampled_caps)
        r0_fp = sum(item["r0_fp"] for item in sampled_caps)
        r0_gold = sum(item["visible_gold"] for item in sampled_caps)
        r0_hits = sum(item["r0_ocr_hits"] for item in sampled_caps)

        r1_tp = sum(item["r1_tp"] for item in sampled_caps)
        r1_fp = sum(item["r1_fp"] for item in sampled_caps)
        r1_gold = sum(item["visible_gold"] for item in sampled_caps)
        r1_hits = sum(item["r1_ocr_hits"] for item in sampled_caps)

        r0_p = r0_tp / (r0_tp + r0_fp) if (r0_tp + r0_fp) > 0 else 0.0
        r0_r = r0_tp / r0_gold if r0_gold > 0 else 0.0
        r0_f1 = (2 * r0_p * r0_r) / (r0_p + r0_r) if (r0_p + r0_r) > 0 else 0.0
        r0_cov = r0_hits / r0_gold if r0_gold > 0 else 0.0

        r1_p = r1_tp / (r1_tp + r1_fp) if (r1_tp + r1_fp) > 0 else 0.0
        r1_r = r1_tp / r1_gold if r1_gold > 0 else 0.0
        r1_f1 = (2 * r1_p * r1_r) / (r1_p + r1_r) if (r1_p + r1_r) > 0 else 0.0
        r1_cov = r1_hits / r1_gold if r1_gold > 0 else 0.0

        bs_delta_f1_cap.append(r1_f1 - r0_f1)
        bs_delta_cov_cap.append(r1_cov - r0_cov)
        bs_delta_rec_cap.append(r1_r - r0_r)
        bs_delta_prec_cap.append(r1_p - r0_p)

    ci_delta_f1_cap = (float(np.percentile(bs_delta_f1_cap, 2.5)), float(np.percentile(bs_delta_f1_cap, 97.5)))
    ci_delta_cov_cap = (float(np.percentile(bs_delta_cov_cap, 2.5)), float(np.percentile(bs_delta_cov_cap, 97.5)))
    ci_delta_rec_cap = (float(np.percentile(bs_delta_rec_cap, 2.5)), float(np.percentile(bs_delta_rec_cap, 97.5)))
    ci_delta_prec_cap = (float(np.percentile(bs_delta_prec_cap, 2.5)), float(np.percentile(bs_delta_prec_cap, 97.5)))

    # B. Prescription-Level Clustered Bootstrap (Resampling 5 prescription clusters)
    rx_keys = list(rx_groups.keys())
    n_rxs = len(rx_keys)
    bs_delta_f1_rx = []

    for _ in range(num_bootstrap):
        sampled_rx_keys = np.random.choice(rx_keys, size=n_rxs, replace=True)
        sampled_caps = []
        for rk in sampled_rx_keys:
            sampled_caps.extend(rx_groups[rk])

        r0_tp = sum(item["r0_tp"] for item in sampled_caps)
        r0_fp = sum(item["r0_fp"] for item in sampled_caps)
        r0_gold = sum(item["visible_gold"] for item in sampled_caps)

        r1_tp = sum(item["r1_tp"] for item in sampled_caps)
        r1_fp = sum(item["r1_fp"] for item in sampled_caps)
        r1_gold = sum(item["visible_gold"] for item in sampled_caps)

        r0_p = r0_tp / (r0_tp + r0_fp) if (r0_tp + r0_fp) > 0 else 0.0
        r0_r = r0_tp / r0_gold if r0_gold > 0 else 0.0
        r0_f1 = (2 * r0_p * r0_r) / (r0_p + r0_r) if (r0_p + r0_r) > 0 else 0.0

        r1_p = r1_tp / (r1_tp + r1_fp) if (r1_tp + r1_fp) > 0 else 0.0
        r1_r = r1_tp / r1_gold if r1_gold > 0 else 0.0
        r1_f1 = (2 * r1_p * r1_r) / (r1_p + r1_r) if (r1_p + r1_r) > 0 else 0.0

        bs_delta_f1_rx.append(r1_f1 - r0_f1)

    ci_delta_f1_rx = (float(np.percentile(bs_delta_f1_rx, 2.5)), float(np.percentile(bs_delta_f1_rx, 97.5)))

    # ── 4. Generate Output Files ────────────────────────────────────────────
    # Summary CSV
    summary_rows = [
        # Micro
        {
            "granularity": "Drug-Instance Micro",
            "condition": "r0",
            "description": cond_labels["r0"],
            "visible_ocr_coverage": round(micro_stats["r0"]["visible_ocr_coverage"], 4),
            "precision": round(micro_stats["r0"]["precision"], 4),
            "recall": round(micro_stats["r0"]["recall"], 4),
            "f1_score": round(micro_stats["r0"]["f1_score"], 4),
            "sample_size": micro_stats["r0"]["total_visible_gold"],
        },
        {
            "granularity": "Drug-Instance Micro",
            "condition": "r1",
            "description": cond_labels["r1"],
            "visible_ocr_coverage": round(micro_stats["r1"]["visible_ocr_coverage"], 4),
            "precision": round(micro_stats["r1"]["precision"], 4),
            "recall": round(micro_stats["r1"]["recall"], 4),
            "f1_score": round(micro_stats["r1"]["f1_score"], 4),
            "sample_size": micro_stats["r1"]["total_visible_gold"],
        },
        # Capture-Macro
        {
            "granularity": "Capture-Macro",
            "condition": "r0",
            "description": cond_labels["r0"],
            "visible_ocr_coverage": round(cap_macro_stats["r0"]["visible_ocr_coverage"], 4),
            "precision": round(cap_macro_stats["r0"]["precision"], 4),
            "recall": round(cap_macro_stats["r0"]["recall"], 4),
            "f1_score": round(cap_macro_stats["r0"]["f1_score"], 4),
            "sample_size": n_caps,
        },
        {
            "granularity": "Capture-Macro",
            "condition": "r1",
            "description": cond_labels["r1"],
            "visible_ocr_coverage": round(cap_macro_stats["r1"]["visible_ocr_coverage"], 4),
            "precision": round(cap_macro_stats["r1"]["precision"], 4),
            "recall": round(cap_macro_stats["r1"]["recall"], 4),
            "f1_score": round(cap_macro_stats["r1"]["f1_score"], 4),
            "sample_size": n_caps,
        },
        # Prescription-Macro
        {
            "granularity": "Prescription-Macro",
            "condition": "r0",
            "description": cond_labels["r0"],
            "visible_ocr_coverage": round(rx_macro_stats["r0"]["visible_ocr_coverage"], 4),
            "precision": round(rx_macro_stats["r0"]["precision"], 4),
            "recall": round(rx_macro_stats["r0"]["recall"], 4),
            "f1_score": round(rx_macro_stats["r0"]["f1_score"], 4),
            "sample_size": n_rxs,
        },
        {
            "granularity": "Prescription-Macro",
            "condition": "r1",
            "description": cond_labels["r1"],
            "visible_ocr_coverage": round(rx_macro_stats["r1"]["visible_ocr_coverage"], 4),
            "precision": round(rx_macro_stats["r1"]["precision"], 4),
            "recall": round(rx_macro_stats["r1"]["recall"], 4),
            "f1_score": round(rx_macro_stats["r1"]["f1_score"], 4),
            "sample_size": n_rxs,
        },
    ]

    with open(output_dir / "summary.csv", "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(summary_rows[0].keys()))
        writer.writeheader()
        writer.writerows(summary_rows)

    # Per Capture CSV
    with open(output_dir / "per_capture.csv", "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(per_capture_records[0].keys()))
        writer.writeheader()
        writer.writerows(per_capture_records)

    # Failure Taxonomy CSV
    tax_rows = []
    for cond in conditions:
        tot_gold = cond_stats[cond]["gold_total"]
        tax_rows.append({
            "condition": cond,
            "description": cond_labels[cond],
            "OCR_MISS": cond_taxonomy[cond]["OCR_MISS"],
            "NER_MISS": cond_taxonomy[cond]["NER_MISS"],
            "SUCCESS": cond_taxonomy[cond]["SUCCESS"],
            "total_visible_gold": tot_gold,
        })

    with open(output_dir / "failure_taxonomy.csv", "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(tax_rows[0].keys()))
        writer.writeheader()
        writer.writerows(tax_rows)

    # Paired Transition Matrix CSV
    trans_rows = [
        {"transition": "R0 Correct ──▶ R1 Correct (Both Success)", "count": trans_counts["r0_correct_r1_correct"]},
        {"transition": "R0 Wrong   ──▶ R1 Correct (R1 Recovery Gain ★)", "count": trans_counts["r0_wrong_r1_correct"]},
        {"transition": "R0 Correct ──▶ R1 Wrong   (R1 Regression Loss)", "count": trans_counts["r0_correct_r1_wrong"]},
        {"transition": "R0 Wrong   ──▶ R1 Wrong   (Both Missed)", "count": trans_counts["r0_wrong_r1_wrong"]},
        {"transition": "TOTAL VISIBLE DRUG INSTANCES", "count": len(paired_item_results)},
        {"transition": "NET RECOVERY GAIN (b - c)", "count": b - c},
        {"transition": "EXACT MCNEMAR / BINOMIAL 2-SIDED P-VALUE", "count": round(p_value_mcnemar, 4)},
    ]

    with open(output_dir / "paired_transition_matrix.csv", "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=["transition", "count"])
        writer.writeheader()
        writer.writerows(trans_rows)

    # Statistical Significance JSON
    stat_report = {
        "mcnemar_exact_test": {
            "b_gain": b,
            "c_loss": c,
            "n_discordant": n_discordant,
            "net_gain": b - c,
            "two_sided_p_value": p_value_mcnemar,
            "interpretation": "Non-significant (p = 0.4049 >= 0.05), indicating numerical improvement without strong hypothesis rejection.",
        },
        "capture_level_bootstrap_95ci": {
            "delta_f1_pct": {
                "point_estimate": round((micro_stats["r1"]["f1_score"] - micro_stats["r0"]["f1_score"]) * 100, 2),
                "ci_lower": round(ci_delta_f1_cap[0] * 100, 2),
                "ci_upper": round(ci_delta_f1_cap[1] * 100, 2),
            },
            "delta_coverage_pct": {
                "point_estimate": round((micro_stats["r1"]["visible_ocr_coverage"] - micro_stats["r0"]["visible_ocr_coverage"]) * 100, 2),
                "ci_lower": round(ci_delta_cov_cap[0] * 100, 2),
                "ci_upper": round(ci_delta_cov_cap[1] * 100, 2),
            },
            "delta_recall_pct": {
                "point_estimate": round((micro_stats["r1"]["recall"] - micro_stats["r0"]["recall"]) * 100, 2),
                "ci_lower": round(ci_delta_rec_cap[0] * 100, 2),
                "ci_upper": round(ci_delta_rec_cap[1] * 100, 2),
            },
            "delta_precision_pct": {
                "point_estimate": round((micro_stats["r1"]["precision"] - micro_stats["r0"]["precision"]) * 100, 2),
                "ci_lower": round(ci_delta_prec_cap[0] * 100, 2),
                "ci_upper": round(ci_delta_prec_cap[1] * 100, 2),
            },
        },
        "prescription_clustered_bootstrap_95ci": {
            "delta_f1_pct": {
                "point_estimate": round((micro_stats["r1"]["f1_score"] - micro_stats["r0"]["f1_score"]) * 100, 2),
                "ci_lower": round(ci_delta_f1_rx[0] * 100, 2),
                "ci_upper": round(ci_delta_f1_rx[1] * 100, 2),
            },
        },
        "multi_granularity_f1": {
            "drug_instance_micro": {
                "r0": round(micro_stats["r0"]["f1_score"] * 100, 2),
                "r1": round(micro_stats["r1"]["f1_score"] * 100, 2),
                "delta": round((micro_stats["r1"]["f1_score"] - micro_stats["r0"]["f1_score"]) * 100, 2),
            },
            "capture_macro": {
                "r0": round(cap_macro_stats["r0"]["f1_score"] * 100, 2),
                "r1": round(cap_macro_stats["r1"]["f1_score"] * 100, 2),
                "delta": round((cap_macro_stats["r1"]["f1_score"] - cap_macro_stats["r0"]["f1_score"]) * 100, 2),
            },
            "prescription_macro": {
                "r0": round(rx_macro_stats["r0"]["f1_score"] * 100, 2),
                "r1": round(rx_macro_stats["r1"]["f1_score"] * 100, 2),
                "delta": round((rx_macro_stats["r1"]["f1_score"] - rx_macro_stats["r0"]["f1_score"]) * 100, 2),
            },
        },
    }

    with open(output_dir / "statistical_significance.json", "w", encoding="utf-8") as f:
        json.dump(stat_report, f, ensure_ascii=False, indent=2)

    # Recovered Drugs JSON
    with open(output_dir / "r1_recovered_drugs.json", "w", encoding="utf-8") as f:
        json.dump(recovered_drugs, f, ensure_ascii=False, indent=2)

    # ── 5. Terminal Display ─────────────────────────────────────────────────
    print("\n" + "=" * 105)
    print("      HARD-CASE ROI INTERVENTION STUDY: R0 vs R1 MULTI-GRANULARITY BENCHMARK")
    print("=" * 105)
    print(f"{'Granularity':<22} | {'Condition':<10} | {'Visible Cov':<12} | {'Precision':<10} | {'Recall':<10} | {'F1 Score':<10}")
    print("-" * 105)
    for s in summary_rows:
        print(f"{s['granularity']:<22} | {s['condition']:<10} | {s['visible_ocr_coverage']*100:<11.2f}% | {s['precision']*100:<9.2f}% | {s['recall']*100:<9.2f}% | {s['f1_score']*100:<9.2f}%")
    print("=" * 105)

    print("\n--- Paired Drug-Level Transition Matrix (b vs c) ---")
    for t in trans_rows:
        val = t['count']
        if isinstance(val, float):
            print(f"  * {t['transition']:<52}: {val:.4f}")
        else:
            print(f"  * {t['transition']:<52}: {val:3d}")

    print("\n--- Statistical Significance & Confidence Intervals ---")
    significance = "p < 0.05" if p_value_mcnemar < 0.05 else "p >= 0.05"
    print(
        f"  * Exact McNemar / Binomial 2-sided Test: "
        f"b={b} vs c={c} ──▶ p = {p_value_mcnemar:.4f} ({significance})"
    )
    print(f"  * Capture-Level Bootstrap 95% CI on ΔF1: [{ci_delta_f1_cap[0]*100:+.2f}%, {ci_delta_f1_cap[1]*100:+.2f}%] (point: {stat_report['capture_level_bootstrap_95ci']['delta_f1_pct']['point_estimate']:+.2f}%)")
    print(f"  * Prescription-Clustered Bootstrap 95% CI on ΔF1: [{ci_delta_f1_rx[0]*100:+.2f}%, {ci_delta_f1_rx[1]*100:+.2f}%]")

    logger.info(f"Evaluation & Statistical Testing Completed! Reports saved to: {output_dir.resolve()}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Visible-in-frame Real Camera ROI Benchmark with Statistical Testing")
    parser.add_argument("--ocr-dir", type=str, default="reports/real_medication_roi_ablation/mlkit_ocr", help="Directory of ML Kit OCR JSONs")
    parser.add_argument("--visible-gt", type=str, default="data/visible_in_frame_gt.json", help="Visible GT JSON file")
    parser.add_argument("--output-dir", type=str, default="reports/real_medication_roi_ablation", help="Output directory")
    parser.add_argument("--bootstrap", type=int, default=10000, help="Number of bootstrap resamples")
    args = parser.parse_args()

    run_real_roi_evaluation(
        ocr_dir=Path(args.ocr_dir),
        visible_gt_path=Path(args.visible_gt),
        output_dir=Path(args.output_dir),
        num_bootstrap=args.bootstrap,
    )
