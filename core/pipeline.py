"""
core/pipeline.py — Full end-to-end MedicineApp pipeline.

Orchestrates Phase A: prescription scan → drug extraction.

Usage:
    from core.pipeline import MedicinePipeline
    pipe = MedicinePipeline()

    # Phase A: Scan prescription
    result = pipe.scan_prescription("prescription_photo.jpg")
    # → {"medications": [...], "ocr_blocks": [...]}
"""

import json
import logging
from datetime import datetime
from pathlib import Path
import re
from typing import Optional, Union, List, Dict, Any

import cv2
import numpy as np

logger = logging.getLogger(__name__)

ROOT = Path(__file__).parent.parent


def _save_debug_artifacts(img, ocr_text, ner_results, medications, candidates, stats):
    """Save debug scan artifacts to data/output/debug_scans/ WITHOUT modifying DB."""
    try:
        debug_dir = ROOT / "data" / "output" / "debug_scans"
        debug_dir.mkdir(parents=True, exist_ok=True)
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")

        json_path = debug_dir / f"scan_{timestamp}_debug.json"
        with open(json_path, "w", encoding="utf-8") as f:
            json.dump(
                {
                    "timestamp": timestamp,
                    "ocr_text": ocr_text,
                    "medications": medications,
                    "candidates": candidates,
                    "ocr_blocks": ner_results,
                    "stats": stats,
                },
                f,
                ensure_ascii=False,
                indent=2,
            )

        if img is not None and hasattr(img, "shape"):
            annotated_path = debug_dir / f"scan_{timestamp}_image.jpg"
            cv2.imwrite(str(annotated_path), img)

        logger.info(f"Saved debug artifacts to {json_path}")
    except Exception as e:
        logger.warning(f"Failed to save debug artifacts: {e}")


class MedicinePipeline:
    """
    Full pipeline: prescription scan → drug extraction.

    Lazy loads all models on first use to minimize startup time.
    """

    def __init__(
        self,
        device: Optional[str] = None,
    ):
        # ÉP SỬ DỤNG CPU MẶC ĐỊNH CHO MỌI THỬ NGHIỆM
        self._device = device or "cpu"

        # Lazy-loaded modules
        self._classifier = None
        self._drug_mapper = None

        logger.info("MedicinePipeline initialized")

    # ── Lazy loaders ─────────────────────────────────────

    def _get_classifier(self):
        if self._classifier is None:
            from core.classify.ner_extractor import (
                NerExtractor,
            )

            self._classifier = NerExtractor()
            logger.info("PhoBERT NER extractor loaded")
        return self._classifier

    def _get_drug_mapper(self):
        if self._drug_mapper is None:
            from core.drug_search.drug_lookup import (
                DrugLookup,
            )

            self._drug_mapper = DrugLookup()
            logger.info("Drug mapper loaded")
        return self._drug_mapper

    # ── Scan Prescription ────────────────────────────────

    def scan_prescription_app(
        self,
        ocr_text: Optional[str] = None,
        ocr_lines: Optional[Union[list, str]] = None,
        layout_strategy: str = "p3_medication_bands",
    ):
        """
        API scan path with geometry-aware MLKitLayoutAdapter and PhoBERT NER extraction.
        Accepts structured ocr_lines (with bounding boxes) and/or fallback ocr_text string.
        """
        has_lines = bool(ocr_lines and (isinstance(ocr_lines, list) and len(ocr_lines) > 0 or isinstance(ocr_lines, str) and len(ocr_lines.strip()) > 2))
        has_text = bool(ocr_text and ocr_text.strip())

        if not has_lines and not has_text:
            return {"error": "ocr_text or ocr_lines is required."}

        from core.classify.mlkit_layout_adapter import MLKitLayoutAdapter

        logger.info(f"Processing prescription scan with layout_strategy='{layout_strategy}' (structured lines: {has_lines})")
        adapter = MLKitLayoutAdapter()
        layout_blocks, layout_meta = adapter.process(
            ocr_lines_data=ocr_lines,
            fallback_text=ocr_text,
            strategy=layout_strategy,
        )

        ner_input = self._build_ner_input_from_text_blocks(layout_blocks)
        if not ner_input:
            return {"error": "OCR produced only empty blocks", "image_size": (1000, 1000)}

        ner_results = self._classify_blocks(ner_input)
        raw_meds, raw_candidates = self._extract_medications(ner_results)

        # Lọc bỏ rác tiêu đề bệnh viện / thông tin hành chính bị PhoBERT đoán nhầm qua AI Semantic Filter
        from core.classify.post_filter import NerPostFilter

        filtered_meds = [
            m for m in raw_meds
            if NerPostFilter.is_likely_drug(
                text=m.get("drug_name", "") or m.get("ocr_text", ""),
                ocr_text=m.get("ocr_text", ""),
                match_score=float(m.get("match_score", 0.0)),
                matched_name=m.get("matched_drug_name"),
            )
        ]

        medication_candidates = [
            c for c in (raw_candidates or [])
            if NerPostFilter.is_likely_drug(
                text=c.get("drug_name", "") or c.get("ocr_text", ""),
                ocr_text=c.get("ocr_text", ""),
                match_score=float(c.get("match_score", 0.0)),
                matched_name=c.get("matched_drug_name"),
            )
        ]

        res_stats = {
            "total_blocks": len(ner_input),
            "drugnames": len(filtered_meds),
            "others": len(ner_input) - len(filtered_meds),
            "selection_strategy": layout_meta.get("strategy", layout_strategy),
            "layout_meta": layout_meta,
            "candidate_count": len(filtered_meds),
        }

        # Lưu thông tin debug phục vụ kiểm tra (KHÔNG tạo bảng DB mới)
        _save_debug_artifacts(
            img=None,
            ocr_text=ocr_text or "\n".join(b.get("text", "") for b in layout_blocks),
            ner_results=ner_results,
            medications=filtered_meds,
            candidates=medication_candidates,
            stats=res_stats,
        )

        return {
            "medications": filtered_meds,
            "medication_candidates": medication_candidates,
            "ocr_blocks": ner_results,
            "image_size": (1000, 1000),
            "stats": res_stats,
        }

    @staticmethod
    def _build_ner_input_from_text_blocks(blocks):
        ner_input = []
        for block in blocks or []:
            if isinstance(block, dict):
                text = block.get("text", "").strip()
                bbox = block.get("bbox") or block.get("box", [[0, 0], [100, 0], [100, 20], [0, 20]])
            else:
                text = getattr(block, "text", "").strip()
                bbox = getattr(block, "bbox", [[0, 0], [100, 0], [100, 20], [0, 20]])
            if not text:
                continue
            ner_input.append(
                {
                    "text": text,
                    "label": "other",
                    "box": bbox,
                    "bbox": bbox,
                }
            )
        return ner_input

    @staticmethod
    def _summarize_scan_branch(ner_input, ner_results, medications):
        return {
            "ner_input_count": len(ner_input),
            "ocr_block_count": len(ner_results),
            "candidate_count": len(medications),
        }

    @staticmethod
    def _select_app_scan_branch(raw_summary, grouped_summary, grouping_meta):
        grouped_candidates = int(grouped_summary.get("candidate_count", 0))
        raw_candidates = int(raw_summary.get("candidate_count", 0))
        anchor_count = int(grouping_meta.get("anchor_count", 0))
        raw_overhang = raw_candidates - grouped_candidates
        grouped_floor = max(3, anchor_count - 1) if anchor_count >= 3 else 3

        if grouped_candidates <= 0:
            return "raw_blocks", "grouped_empty"
        if raw_candidates <= 0:
            return "stt_grouped", "raw_empty"
        if grouping_meta.get("strategy") != "stt_grouped":
            return "raw_blocks", "grouping_not_reliable"
        if grouped_candidates < grouped_floor:
            return "raw_blocks", "grouped_under_covers_rows"
        if raw_overhang >= 3:
            return "stt_grouped", "reduced_document_noise"
        return "raw_blocks", "preserve_raw_coverage"

    @staticmethod
    def _looks_like_valid_drugname_app(text, confidence):
        """Keep plausible OCR drug names even when DB matching is weak."""
        from core.classify.post_filter import NerPostFilter

        if float(confidence or 0) < 0.75:
            return False

        cleaned = re.sub(r"\s+", " ", str(text or "")).strip()
        if len(cleaned) < 4:
            return False
        if not NerPostFilter.is_likely_drug(cleaned):
            return False

        alpha_tokens = [
            token
            for token in re.split(r"[^A-Za-zÀ-ỹ0-9]+", cleaned)
            if any(ch.isalpha() for ch in token)
        ]
        if not alpha_tokens:
            return False

        normalized = cleaned.lower()
        reject_phrases = {
            "ngày uống",
            "buổi sáng",
            "buổi tối",
            "sau ăn",
            "trước ăn",
            "viên",
            "ống",
            "lọ",
        }
        if normalized in reject_phrases:
            return False

        return True

    def _classify_blocks(self, ocr_blocks):
        """Use PhoBERT NER to classify each block as drugname/other."""
        classifier = self._get_classifier()
        results = classifier.classify(ocr_blocks)
        return results

    def _extract_medications(self, ner_results):
        """Extract drugname blocks and map to standard names."""
        mapper = self._get_drug_mapper()
        medications = []
        candidates = []

        for block in ner_results:
            if block.get("label") == "drugname":
                text = block["text"]
                match = mapper.lookup(text)
                bbox = block.get("bbox") or block.get("box")
                confidence = block.get("confidence", 0)
                match_score = match.get("score", 0) if match else 0
                matched_name = match.get("name") if match else None
                if match:
                    registration_number = (
                        match.get("registration_number")
                        or match.get("so_dang_ky", "")
                    )
                else:
                    registration_number = ""
                normalized_candidate_strength = (
                    match.get("normalized_candidate_strength", "") if match else ""
                )
                normalized_query_strength = (
                    match.get("normalized_query_strength", "") if match else ""
                )
                confirmation_safe = bool(
                    match
                    and match.get("confirmation_safe")
                    and match.get("match_basis") == "brand_exact"
                    and match.get("strength_state") == "compatible"
                    and not match.get("ambiguous")
                    and normalized_candidate_strength
                )

                if matched_name and confirmation_safe:
                    mapping_status = "confirmed"
                    drug_name = matched_name
                elif match_score >= 0.65 or self._looks_like_valid_drugname_app(
                    text, confidence
                ):
                    mapping_status = "unmapped_candidate"
                    drug_name = text
                else:
                    mapping_status = "rejected_noise"
                    drug_name = text

                candidate = {
                    "ocr_text": text,
                    "drug_name_raw": text,
                    "drug_name": drug_name,
                    "matched_drug_name": matched_name,
                    "mapped_drug_name": matched_name,
                    "registration_number": registration_number,
                    "normalized_query_strength": normalized_query_strength,
                    "normalized_candidate_strength": normalized_candidate_strength,
                    "match_score": match_score,
                    "mapping_status": mapping_status,
                    "match_basis": match.get("match_basis", "none") if match else "none",
                    "strength_state": (
                        match.get("strength_state", "unknown_candidate")
                        if match else "unknown_candidate"
                    ),
                    "ambiguous": bool(match and match.get("ambiguous")),
                    "resolution_reason": (
                        match.get("resolution_reason", "no_match") if match else "no_match"
                    ),
                    "confirmation_safe": confirmation_safe,
                    "confidence": confidence,
                    "bbox": bbox,
                }
                candidates.append(candidate)
                if mapping_status != "rejected_noise":
                    medications.append(candidate)

        return medications, candidates

    # ── Utilities ────────────────────────────────────────

    def get_model_info(self):
        """Return info about loaded models."""
        info = {
            "classifier_loaded": self._classifier is not None,
        }
        if self._classifier is not None:
            info["checkpoint"] = self._classifier.checkpoint_info
        return info
