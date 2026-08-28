"""
core/classify/mlkit_layout_adapter.py — Layout Adapter for Google ML Kit OCR.

Reconstructs structured lines and medication bands from raw ML Kit OCR elements,
preserving bounding-box geometry across the ingestion pipeline.

Key responsibilities:
1. Normalizes diverse bbox formats (ML Kit rect, 4-point polygons, [x1,y1,x2,y2]).
2. Row clustering: clusters lines sharing vertical bands into cohesive table rows.
3. Reading order reconstruction: sorts rows top-to-bottom, lines left-to-right.
4. STT medication band segmentation: groups row elements between consecutive STT anchors.
5. Formats structured medication blocks for PhoBERT NER extraction.
"""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Tuple, Union

import numpy as np

logger = logging.getLogger(__name__)

# Regex for matching explicit STT anchors (with punctuation or prefix, 1-2 digits only)
STT_EXPLICIT_ANCHOR_REGEX = re.compile(
    r"^(\d{1,2}[\.\/\),:\-]|STT\s*[:.]?\s*\d{1,2}|[①-⑩])$",
    re.IGNORECASE,
)

STT_PREFIX_REGEX = re.compile(
    r"^(\d{1,2}[\.\/\),:\-]|[①-⑩]|STT\s*[:.]?\s*\d{1,2})\s+(.*)",
    re.IGNORECASE,
)

# Common dosage units and instruction keywords
INSTRUCTION_KEYWORDS = (
    "ngày",
    "uống",
    "mỗi",
    "sau ăn",
    "trước ăn",
    "khi đau",
    "buổi sáng",
    "buổi trưa",
    "buổi chiều",
    "buổi tối",
    "sáng",
    "trưa",
    "chiều",
    "tối",
    "chia",
    "lần",
    "viên/lần",
    "gói/lần",
    "ống/lần",
    "x ",
    "liều",
    "nhai",
)

QUANTITY_UNIT_KEYWORDS = {
    "viên",
    "gói",
    "ống",
    "chai",
    "lọ",
    "vỉ",
    "hộp",
    "tuýp",
    "ml",
    "mg",
    "gam",
    "mcg",
    "bịch",
    "nang",
}


@dataclass
class LayoutLine:
    """A recognized text line with bounding box geometry."""

    text: str
    bbox: list[list[float]]  # [[x1, y1], [x2, y1], [x2, y2], [x1, y2]]
    confidence: float = 0.95
    block_index: int = 0
    line_index: int = 0
    x_min: float = 0.0
    x_max: float = 0.0
    y_min: float = 0.0
    y_max: float = 0.0
    x_center: float = 0.0
    y_center: float = 0.0
    width: float = 0.0
    height: float = 0.0

    def __post_init__(self):
        xs = [pt[0] for pt in self.bbox] if self.bbox else [0.0]
        ys = [pt[1] for pt in self.bbox] if self.bbox else [0.0]
        self.x_min = float(min(xs))
        self.x_max = float(max(xs))
        self.y_min = float(min(ys))
        self.y_max = float(max(ys))
        self.x_center = (self.x_min + self.x_max) / 2.0
        self.y_center = (self.y_min + self.y_max) / 2.0
        self.width = max(1.0, self.x_max - self.x_min)
        self.height = max(1.0, self.y_max - self.y_min)


@dataclass
class LayoutRow:
    """A cluster of layout lines aligned horizontally in the same row band."""

    lines: list[LayoutLine] = field(default_factory=list)
    anchor_y_min: float = 0.0
    anchor_y_max: float = 0.0
    anchor_y_center: float = 0.0
    y_min: float = 0.0
    y_max: float = 0.0
    y_center: float = 0.0
    height: float = 0.0

    def add_line(self, line: LayoutLine):
        if not self.lines:
            self.anchor_y_min = line.y_min
            self.anchor_y_max = line.y_max
            self.anchor_y_center = line.y_center
        self.lines.append(line)
        self._update_bounds()

    def _update_bounds(self):
        if not self.lines:
            return
        self.y_min = min(l.y_min for l in self.lines)
        self.y_max = max(l.y_max for l in self.lines)
        self.y_center = sum(l.y_center for l in self.lines) / len(self.lines)
        self.height = max(1.0, self.y_max - self.y_min)

    @property
    def sorted_lines(self) -> list[LayoutLine]:
        """Return lines sorted left-to-right by x_min."""
        return sorted(self.lines, key=lambda l: (l.x_min, l.x_center))

    @property
    def text(self) -> str:
        """Concatenated text of lines in reading order."""
        return " ".join(l.text.strip() for l in self.sorted_lines if l.text.strip())

    @property
    def bbox(self) -> list[list[float]]:
        """Union bounding box for the entire row."""
        if not self.lines:
            return [[0.0, 0.0], [0.0, 0.0], [0.0, 0.0], [0.0, 0.0]]
        all_x = [pt[0] for l in self.lines for pt in l.bbox]
        all_y = [pt[1] for l in self.lines for pt in l.bbox]
        min_x, max_x = min(all_x), max(all_x)
        min_y, max_y = min(all_y), max(all_y)
        return [
            [min_x, min_y],
            [max_x, min_y],
            [max_x, max_y],
            [min_x, max_y],
        ]


class MLKitLayoutAdapter:
    """
    Adapter that parses ML Kit OCR line elements, reconstructs geometric reading order,
    clusters lines into table rows, and segments rows into medication bands for PhoBERT NER.
    """

    def __init__(
        self,
        vertical_overlap_threshold: float = 0.35,
        row_height_tolerance_ratio: float = 0.5,
    ):
        self.vertical_overlap_threshold = vertical_overlap_threshold
        self.row_height_tolerance_ratio = row_height_tolerance_ratio

    # ── 1. Ingestion & Normalization ────────────────────────────────────────

    @staticmethod
    def normalize_bbox(raw_bbox: Any) -> list[list[float]]:
        """
        Normalize any bounding box representation to [[x1,y1], [x2,y1], [x2,y2], [x1,y2]].
        Supports:
        - Dict with left/top/right/bottom or x/y/w/h or x_min/y_min/x_max/y_max
        - List of 4 points [[x,y], [x,y], [x,y], [x,y]]
        - List of 4 numbers [x_min, y_min, x_max, y_max] or [x, y, w, h]
        """
        if isinstance(raw_bbox, dict):
            if "left" in raw_bbox and "top" in raw_bbox:
                l = float(raw_bbox.get("left", 0.0))
                t = float(raw_bbox.get("top", 0.0))
                r = float(raw_bbox.get("right", l + 100.0))
                b = float(raw_bbox.get("bottom", t + 20.0))
                return [[l, t], [r, t], [r, b], [l, b]]
            elif "x_min" in raw_bbox and "y_min" in raw_bbox:
                l = float(raw_bbox.get("x_min", 0.0))
                t = float(raw_bbox.get("y_min", 0.0))
                r = float(raw_bbox.get("x_max", l + 100.0))
                b = float(raw_bbox.get("y_max", t + 20.0))
                return [[l, t], [r, t], [r, b], [l, b]]
            elif "x" in raw_bbox and "y" in raw_bbox:
                x = float(raw_bbox.get("x", 0.0))
                y = float(raw_bbox.get("y", 0.0))
                w = float(raw_bbox.get("w", raw_bbox.get("width", 100.0)))
                h = float(raw_bbox.get("h", raw_bbox.get("height", 20.0)))
                return [[x, y], [x + w, y], [x + w, y + h], [x, y + h]]

        if isinstance(raw_bbox, (list, tuple)):
            if len(raw_bbox) == 4:
                # Could be 4 points or 4 scalar coordinates
                if isinstance(raw_bbox[0], (list, tuple)) and len(raw_bbox[0]) >= 2:
                    return [[float(pt[0]), float(pt[1])] for pt in raw_bbox[:4]]
                else:
                    try:
                        x1, y1, x2, y2 = [float(v) for v in raw_bbox]
                        return [[x1, y1], [x2, y1], [x2, y2], [x1, y2]]
                    except (ValueError, TypeError):
                        pass

        # Fallback dummy bbox
        return [[0.0, 0.0], [100.0, 0.0], [100.0, 20.0], [0.0, 20.0]]

    def parse_ocr_lines(
        self,
        ocr_lines_data: Union[List[Dict[str, Any]], str, None],
        fallback_text: Optional[str] = None,
    ) -> list[LayoutLine]:
        """
        Parse raw OCR lines data from client into structured LayoutLine objects.
        If data is empty or invalid, falls back to splitting fallback_text.
        """
        parsed_lines: list[LayoutLine] = []

        if isinstance(ocr_lines_data, str):
            import json

            try:
                ocr_lines_data = json.loads(ocr_lines_data)
            except Exception:
                ocr_lines_data = None

        if isinstance(ocr_lines_data, list) and ocr_lines_data:
            for idx, item in enumerate(ocr_lines_data):
                if not isinstance(item, dict):
                    continue
                text = str(item.get("text") or "").strip()
                if not text or text.startswith("---"):
                    continue

                raw_bbox = (
                    item.get("bbox")
                    or item.get("boundingBox")
                    or item.get("box")
                    or item.get("rect")
                )
                bbox = self.normalize_bbox(raw_bbox)
                conf = float(item.get("confidence", 0.95))
                b_idx = int(item.get("block_index", item.get("blockIndex", idx)))
                l_idx = int(item.get("line_index", item.get("lineIndex", 0)))

                parsed_lines.append(
                    LayoutLine(
                        text=text,
                        bbox=bbox,
                        confidence=conf,
                        block_index=b_idx,
                        line_index=l_idx,
                    )
                )

        if not parsed_lines and fallback_text:
            raw_lines = [
                l.strip()
                for l in fallback_text.split("\n")
                if l.strip() and not l.strip().startswith("---")
            ]
            for idx, text in enumerate(raw_lines):
                # Synthetic stepped Y coordinates for fallback plain text
                y_top = idx * 40.0
                y_bot = y_top + 20.0
                bbox = [[0.0, y_top], [300.0, y_top], [300.0, y_bot], [0.0, y_bot]]
                parsed_lines.append(
                    LayoutLine(
                        text=text,
                        bbox=bbox,
                        confidence=0.95,
                        block_index=idx,
                        line_index=0,
                    )
                )

        return parsed_lines

    # ── 2. Reading Order & Row Clustering (P1 & P2) ──────────────────────────

    def cluster_rows(self, lines: list[LayoutLine]) -> list[LayoutRow]:
        """
        Cluster lines that overlap vertically into horizontal rows (P2).
        Calculates median line height and clusters lines sharing vertical space.
        Sorts rows from top to bottom (Y-axis), and lines within each row left-to-right (X-axis).
        """
        if not lines:
            return []

        valid_lines = [l for l in lines if l.text.strip()]
        if not valid_lines:
            return []

        # Sort lines initially by y_top, then x_left (P1 sorting)
        sorted_lines = sorted(valid_lines, key=lambda l: (l.y_min, l.x_min))

        heights = [l.height for l in sorted_lines if l.height > 2.0]
        median_height = float(np.median(heights)) if heights else 20.0
        y_tolerance = max(6.0, median_height * self.row_height_tolerance_ratio)

        rows: list[LayoutRow] = []

        for line in sorted_lines:
            best_row: Optional[LayoutRow] = None
            best_score: float = -1e9

            for row in rows:
                anchor = row.lines[0]
                overlap_y = max(
                    0.0, min(line.y_max, anchor.y_max) - max(line.y_min, anchor.y_min)
                )
                min_h = min(line.height, anchor.height)
                overlap_ratio = overlap_y / min_h if min_h > 0 else 0.0

                center_diff = abs(line.y_center - anchor.y_center)

                if overlap_ratio >= self.vertical_overlap_threshold or (
                    overlap_y > 0.0 and center_diff <= y_tolerance
                ):
                    score = overlap_ratio - (center_diff / (y_tolerance * 2.0))
                    if score > best_score:
                        best_score = score
                        best_row = row

            if best_row is not None:
                best_row.add_line(line)
            else:
                new_row = LayoutRow()
                new_row.add_line(line)
                rows.append(new_row)

        rows.sort(key=lambda r: (r.y_center, r.y_min))
        return rows

    # ── 3. STT Medication Band Grouping (P3) ─────────────────────────────────

    @staticmethod
    def _is_instruction_line(text: str) -> bool:
        """Check if a text line is a usage instruction or dosage direction."""
        lowered = " ".join(text.lower().split())
        return any(
            lowered.startswith(kw) or f" {kw}" in lowered
            for kw in INSTRUCTION_KEYWORDS
        )

    def group_medication_bands(
        self,
        rows: list[LayoutRow],
    ) -> list[dict[str, Any]]:
        """
        Group table rows into medication records (P3) anchored by STT numbers.

        Output format for each block:
        {
            "text": "STT | Drug Content | Qty | Unit",
            "bbox": [[x1, y1], [x2, y1], [x2, y2], [x1, y2]],
            "confidence": 0.95,
            "original_lines": [LayoutLine, ...],
            "stt": "1.",
            "raw_text": "...",
        }
        """
        if not rows:
            return []

        indexed_rows: list[tuple[int, str]] = []
        for r_idx, row in enumerate(rows):
            s_lines = row.sorted_lines
            if not s_lines:
                continue
            first_line = s_lines[0]
            first_elem = first_line.text.strip()

            # Explicit STT pattern e.g. "1.", "1)", "STT 1", "①"
            if STT_EXPLICIT_ANCHOR_REGEX.match(first_elem):
                indexed_rows.append((r_idx, first_elem))
            else:
                m = STT_PREFIX_REGEX.match(first_elem)
                if m:
                    indexed_rows.append((r_idx, m.group(1).strip()))
                elif re.fullmatch(r"^\d{1,2}$", first_elem) and len(s_lines) > 1:
                    # Bare number like "1", "2" only when accompanied by text in the same row
                    indexed_rows.append((r_idx, first_elem))

        if not indexed_rows:
            logger.info("MLKitLayoutAdapter: No reliable STT anchors detected — using row grouping fallback.")
            return self._group_rows_without_anchors(rows)

        medication_bands: list[dict[str, Any]] = []

        # Header rows before first anchor
        first_anchor_idx = indexed_rows[0][0]
        header_rows = rows[:first_anchor_idx]
        for h_row in header_rows:
            if h_row.text.strip():
                medication_bands.append(self._format_row_block(h_row))

        # Band slicing between consecutive anchors
        num_anchors = len(indexed_rows)
        for i in range(num_anchors):
            start_row_idx, stt_label = indexed_rows[i]
            end_row_idx = (
                indexed_rows[i + 1][0] if i + 1 < num_anchors else len(rows)
            )

            band_rows = rows[start_row_idx:end_row_idx]
            band_block = self._assemble_band_block(band_rows, stt_label)
            if band_block:
                medication_bands.append(band_block)

        return medication_bands

    def _assemble_band_block(
        self,
        band_rows: list[LayoutRow],
        stt_label: str,
    ) -> Optional[dict[str, Any]]:
        """Assemble all rows in an STT band into a structured multi-column record."""
        if not band_rows:
            return None

        all_lines: list[LayoutLine] = []
        for r in band_rows:
            all_lines.extend(r.sorted_lines)

        if not all_lines:
            return None

        title_row = band_rows[0]
        subsequent_rows = band_rows[1:]

        title_lines = title_row.sorted_lines

        stt_part = stt_label
        drug_parts: list[str] = []
        qty_part = ""
        unit_part = ""

        # Extract tokens from title row
        drug_candidate_lines = []
        for idx, l in enumerate(title_lines):
            t = l.text.strip()
            # If first token in row matches STT anchor
            if idx == 0 and (STT_EXPLICIT_ANCHOR_REGEX.match(t) or (re.fullmatch(r"^\d{1,2}$", t) and len(title_lines) > 1)):
                if not stt_part:
                    stt_part = t
            elif idx == 0:
                m = STT_PREFIX_REGEX.match(t)
                if m:
                    if not stt_part:
                        stt_part = m.group(1).strip()
                    remainder = m.group(2).strip()
                    if remainder:
                        drug_candidate_lines.append(remainder)
                else:
                    drug_candidate_lines.append(t)
            else:
                drug_candidate_lines.append(t)

        for t in drug_candidate_lines:
            lowered = t.lower().strip()
            # Match quantity with unit attached, e.g. "30 Viên"
            qty_match = re.match(
                r"^(\d+)\s*(viên|gói|ống|chai|lọ|vỉ|hộp|ml|mg|gam|mcg|nang|tuýp)$",
                lowered,
            )
            if qty_match:
                qty_part = qty_match.group(1)
                unit_part = qty_match.group(2)
            elif lowered in QUANTITY_UNIT_KEYWORDS:
                unit_part = t
            elif re.fullmatch(r"^\d+$", t) and not drug_parts:
                # First token is purely digits -> dosage number
                drug_parts.append(t)
            elif re.fullmatch(r"^\d+$", t) and drug_parts:
                # Trailing pure digits -> quantity
                qty_part = t
            else:
                drug_parts.append(t)

        drug_name_str = " ".join(drug_parts).strip()

        # Collect usage instruction rows
        instruction_parts: list[str] = []
        for s_row in subsequent_rows:
            txt = s_row.text.strip()
            if txt:
                instruction_parts.append(txt)

        instruction_str = " ".join(instruction_parts).strip()

        # Format for PhoBERT NER:
        # V2 layout: STT | Content (Drug + Instructions) | Qty | Unit
        content_items = [drug_name_str]
        if instruction_str:
            content_items.append(instruction_str)
        content_str = " ".join(c for c in content_items if c).strip()

        parts = []
        if stt_part:
            parts.append(stt_part)
        if content_str:
            parts.append(content_str)
        if qty_part:
            parts.append(qty_part)
        if unit_part:
            parts.append(unit_part)

        if len(parts) >= 3:
            structured_text = " | ".join(parts)
        else:
            full_raw_text = " ".join(l.text.strip() for l in all_lines if l.text.strip())
            structured_text = (
                f"{stt_part} | {full_raw_text}"
                if stt_part and not full_raw_text.startswith(stt_part)
                else full_raw_text
            )

        # Union bounding box across all lines in band
        all_x = [pt[0] for l in all_lines for pt in l.bbox]
        all_y = [pt[1] for l in all_lines for pt in l.bbox]
        union_bbox = [
            [min(all_x), min(all_y)],
            [max(all_x), min(all_y)],
            [max(all_x), max(all_y)],
            [min(all_x), max(all_y)],
        ]
        avg_conf = sum(l.confidence for l in all_lines) / max(1, len(all_lines))

        return {
            "text": structured_text.strip(),
            "bbox": union_bbox,
            "confidence": round(avg_conf, 4),
            "original_lines": all_lines,
            "stt": stt_part,
            "raw_text": " ".join(l.text.strip() for l in all_lines),
        }

    def _group_rows_without_anchors(
        self,
        rows: list[LayoutRow],
    ) -> list[dict[str, Any]]:
        """Fallback grouping when no STT anchors are detected: preserves individual rows or merges continuation lines."""
        blocks: list[dict[str, Any]] = []

        for row in rows:
            txt = row.text.strip()
            if not txt:
                continue
            blocks.append(self._format_row_block(row))

        return blocks

    def _format_row_block(self, row: LayoutRow) -> dict[str, Any]:
        """Format a single LayoutRow as an independent OCR block."""
        avg_conf = sum(l.confidence for l in row.lines) / max(1, len(row.lines))
        return {
            "text": row.text.strip(),
            "bbox": row.bbox,
            "confidence": round(avg_conf, 4),
            "original_lines": row.lines,
            "stt": "",
            "raw_text": row.text.strip(),
        }

    # ── 4. Main Processing Entrypoint ────────────────────────────────────────

    def process(
        self,
        ocr_lines_data: Union[List[Dict[str, Any]], str, None],
        fallback_text: Optional[str] = None,
        strategy: str = "p3_medication_bands",
    ) -> tuple[list[dict[str, Any]], dict[str, Any]]:
        """
        Process OCR lines into structured blocks according to strategy.

        Strategies:
        - 'p0_raw_text': baseline raw text split by newline
        - 'p1_sorted_lines': sorted lines by (Y, X)
        - 'p2_row_clusters': clustered into horizontal rows
        - 'p3_medication_bands': full STT-anchored medication bands
        """
        lines = self.parse_ocr_lines(ocr_lines_data, fallback_text=fallback_text)
        if not lines:
            return [], {
                "strategy": "empty",
                "line_count": 0,
                "row_count": 0,
                "band_count": 0,
            }

        if strategy == "p0_raw_text":
            blocks = [
                {
                    "text": l.text.strip(),
                    "bbox": l.bbox,
                    "confidence": l.confidence,
                }
                for l in lines
                if l.text.strip()
            ]
            return blocks, {
                "strategy": "p0_raw_text",
                "line_count": len(lines),
                "block_count": len(blocks),
            }

        if strategy == "p1_sorted_lines":
            sorted_lines = sorted(lines, key=lambda l: (l.y_min, l.x_min))
            blocks = [
                {
                    "text": l.text.strip(),
                    "bbox": l.bbox,
                    "confidence": l.confidence,
                }
                for l in sorted_lines
                if l.text.strip()
            ]
            return blocks, {
                "strategy": "p1_sorted_lines",
                "line_count": len(lines),
                "block_count": len(blocks),
            }

        # For P2 and P3, cluster into rows first
        rows = self.cluster_rows(lines)

        if strategy == "p2_row_clusters":
            blocks = [self._format_row_block(r) for r in rows if r.text.strip()]
            return blocks, {
                "strategy": "p2_row_clusters",
                "line_count": len(lines),
                "row_count": len(rows),
                "block_count": len(blocks),
            }

        # P3: Full medication bands
        medication_bands = self.group_medication_bands(rows)
        return medication_bands, {
            "strategy": "p3_medication_bands",
            "line_count": len(lines),
            "row_count": len(rows),
            "band_count": len(medication_bands),
            "block_count": len(medication_bands),
        }
