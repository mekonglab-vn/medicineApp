"""
stt_grouping.py — Gộp TextBlock theo cấu trúc Số thứ tự (STT) và phân cột.
Di chuyển từ module OCR cũ để dùng chung độc lập.
"""

import re
import logging
import numpy as np
from dataclasses import dataclass

logger = logging.getLogger(__name__)


@dataclass
class TextBlock:
    """Một dòng/vùng text đã được nhận diện từ đơn thuốc."""
    text: str
    confidence: float
    bbox: list


def _detect_dynamic_col_bounds(blocks, num_cols=4):
    """
    Tự động tìm (num_cols - 1) ranh giới cột dựa trên khoảng trống (gap)
    lớn nhất theo trục X.
    """
    if len(blocks) < num_cols:
        return None

    all_x_bounds = []
    for b in blocks:
        xs = [pt[0] for pt in b.bbox]
        min_x = min(xs)
        max_x = max(xs)
        if max_x - min_x < 500:
            all_x_bounds.append((min_x, max_x))

    if len(all_x_bounds) < num_cols:
        return None

    all_x_bounds.sort(key=lambda x: x[0])

    gaps = []
    current_max_x = all_x_bounds[0][1]

    for i in range(1, len(all_x_bounds)):
        next_min_x, next_max_x = all_x_bounds[i]

        if next_min_x > current_max_x:
            gap_size = next_min_x - current_max_x
            gap_center = (next_min_x + current_max_x) / 2.0
            gaps.append((gap_size, gap_center))

        current_max_x = max(current_max_x, next_max_x)

    gaps.sort(key=lambda x: x[0], reverse=True)
    if len(gaps) < num_cols - 1:
        return None

    top_gaps = [g[1] for g in gaps[: num_cols - 1]]
    top_gaps.sort()
    logger.debug(f"Dynamic Column Bounds (Absolute X): {top_gaps}")
    return top_gaps


def _bbox_min_y(bbox):
    return min(pt[1] for pt in bbox)


def _bbox_max_y(bbox):
    return max(pt[1] for pt in bbox)


def _is_instruction_like(text: str) -> bool:
    normalized = " ".join(str(text or "").lower().split())
    return normalized.startswith(
        (
            "ngày uống",
            "uống ",
            "mỗi ",
            "sau ăn",
            "trước ăn",
            "khi đau",
            "buổi sáng",
            "buổi tối",
        )
    )


def _is_drug_title_candidate(text: str) -> bool:
    cleaned = " ".join(str(text or "").split())
    if not cleaned or _is_instruction_like(cleaned):
        return False
    if not any(ch.isalpha() for ch in cleaned):
        return False

    lowered = cleaned.lower()
    if lowered in {"viên", "ống", "gói", "chai", "lọ"}:
        return False

    if cleaned[0].isdigit() and len(cleaned.split()) <= 2:
        return False

    if re.fullmatch(r"[\d\s.,/+%-]+", cleaned):
        return False

    return True


def _split_band_on_missing_anchor(band, col_idx, num_cols, y_center_fn):
    """Split one STT band when OCR missed an anchor but another drug title starts."""
    if len(band) < 2:
        return [band]

    text_col = 1 if num_cols > 1 else 0
    text_blocks = [b for b in band if col_idx(b) == text_col]
    if len(text_blocks) < 2:
        return [band]

    title_blocks = [
        b for b in text_blocks if _is_drug_title_candidate(getattr(b, "text", ""))
    ]
    title_blocks.sort(key=lambda b: y_center_fn(b.bbox))
    if len(title_blocks) < 2:
        return [band]

    text_blocks.sort(key=lambda b: y_center_fn(b.bbox))
    median_height = float(
        np.median(
            [max(1, _bbox_max_y(b.bbox) - _bbox_min_y(b.bbox)) for b in text_blocks]
        )
    )
    min_title_gap = max(52.0, median_height * 1.15)

    split_bounds = []
    for prev_title, curr_title in zip(title_blocks, title_blocks[1:]):
        title_gap = y_center_fn(curr_title.bbox) - y_center_fn(prev_title.bbox)
        if title_gap < min_title_gap:
            continue

        prev_text_block = prev_title
        for candidate in text_blocks:
            if y_center_fn(candidate.bbox) < y_center_fn(curr_title.bbox):
                prev_text_block = candidate
            else:
                break

        prev_bottom = _bbox_max_y(prev_text_block.bbox)
        curr_top = _bbox_min_y(curr_title.bbox)
        if curr_top > prev_bottom:
            split_bounds.append((prev_bottom + curr_top) / 2.0)
        else:
            split_bounds.append(
                (y_center_fn(prev_text_block.bbox) + y_center_fn(curr_title.bbox)) / 2.0
            )

    if not split_bounds:
        return [band]

    split_bounds = sorted(set(split_bounds))
    subbands = [[] for _ in range(len(split_bounds) + 1)]
    for block in band:
        yc = y_center_fn(block.bbox)
        subband_idx = 0
        while subband_idx < len(split_bounds) and yc > split_bounds[subband_idx]:
            subband_idx += 1
        subbands[subband_idx].append(block)

    return [subband for subband in subbands if subband]


def group_by_stt_with_meta(blocks: list) -> tuple[list, dict]:
    """
    Gộp TextBlock thành các dòng hoàn chỉnh với thứ tự ngữ nghĩa đúng.
    """
    if not blocks:
        return [], {
            "strategy": "raw_empty",
            "raw_block_count": 0,
            "merged_block_count": 0,
            "anchor_count": 0,
            "used_dynamic_bounds": False,
            "header_block_count": 0,
        }

    def _y_center(bbox):
        ys = [pt[1] for pt in bbox]
        return (min(ys) + max(ys)) / 2.0

    def _x_center(bbox):
        xs = [pt[0] for pt in bbox]
        return (min(xs) + max(xs)) / 2.0

    all_x = [pt[0] for b in blocks for pt in b.bbox]
    min_x = min(all_x)
    max_x = max(all_x)
    board_width = max(max_x - min_x, 1)

    abs_col_bounds = _detect_dynamic_col_bounds(blocks, num_cols=4)

    def _col_idx(block):
        if abs_col_bounds:
            xc = _x_center(block.bbox)
            for i, bound in enumerate(abs_col_bounds):
                if xc <= bound:
                    return i
            return len(abs_col_bounds)
        else:
            rx = (_x_center(block.bbox) - min_x) / board_width
            FALLBACK_BOUNDS = [0.13, 0.75, 0.88]
            for i, bnd in enumerate(FALLBACK_BOUNDS):
                if rx <= bnd:
                    return i
            return len(FALLBACK_BOUNDS)

    stt_re = re.compile(r"^(\d+[\.\/\),]?|STT\s*\d+|[①-⑩])$", re.IGNORECASE)
    anchors = [b for b in blocks if _col_idx(b) <= 1 and stt_re.match(b.text.strip())]
    anchors.sort(key=lambda b: _y_center(b.bbox))

    if not anchors:
        logger.warning("group_by_stt: Không tìm thấy STT anchor → trả về blocks gốc.")
        return blocks, {
            "strategy": "raw_no_anchor",
            "raw_block_count": len(blocks),
            "merged_block_count": len(blocks),
            "anchor_count": 0,
            "used_dynamic_bounds": bool(abs_col_bounds),
            "header_block_count": 0,
        }

    boundaries = [
        (_y_center(anchors[i].bbox) + _y_center(anchors[i + 1].bbox)) / 2.0
        for i in range(len(anchors) - 1)
    ]
    bands: list[list] = [[] for _ in range(len(anchors))]
    headers = []

    for b in blocks:
        yc = _y_center(b.bbox)
        if yc < _y_center(anchors[0].bbox) - 20:
            headers.append(b)
            continue
        assigned = False
        for i, bound in enumerate(boundaries):
            if yc <= bound:
                bands[i].append(b)
                assigned = True
                break
        if not assigned:
            bands[-1].append(b)

    merged = []
    headers.sort(key=lambda b: _y_center(b.bbox))
    merged.extend(headers)

    num_cols = len(abs_col_bounds) + 1 if abs_col_bounds else 4
    for band in bands:
        if not band:
            continue

        logical_bands = _split_band_on_missing_anchor(
            band,
            col_idx=_col_idx,
            num_cols=num_cols,
            y_center_fn=_y_center,
        )

        for logical_band in logical_bands:
            col_groups: dict[int, list] = {i: [] for i in range(num_cols)}
            for b in logical_band:
                col_groups[_col_idx(b)].append(b)

            for cg in col_groups.values():
                cg.sort(key=lambda b: _y_center(b.bbox))

            parts = []
            for col_i in sorted(col_groups.keys()):
                col_texts = [
                    b.text.strip() for b in col_groups[col_i] if b.text.strip()
                ]
                if col_texts:
                    parts.append(" ".join(col_texts))

            merged_text = " | ".join(parts)

            all_pts = [pt for b in logical_band for pt in b.bbox]
            xs = [pt[0] for pt in all_pts]
            ys = [pt[1] for pt in all_pts]
            merged_bbox = [
                [min(xs), min(ys)],
                [max(xs), min(ys)],
                [max(xs), max(ys)],
                [min(xs), max(ys)],
            ]
            avg_conf = sum(b.confidence for b in logical_band) / len(logical_band)
            merged.append(
                TextBlock(
                    text=merged_text.strip(),
                    confidence=round(avg_conf, 4),
                    bbox=merged_bbox,
                )
            )

    mode = "Dynamic" if abs_col_bounds else "StaticFallback"
    logger.info(
        f"group_by_stt [{mode}]: {len(blocks)} blocks → {len(merged)} lines "
        f"(Found {len(anchors)} STTs)"
    )
    return merged, {
        "strategy": "stt_grouped",
        "raw_block_count": len(blocks),
        "merged_block_count": len(merged),
        "anchor_count": len(anchors),
        "used_dynamic_bounds": bool(abs_col_bounds),
        "header_block_count": len(headers),
    }


def group_by_stt(blocks: list) -> list:
    merged, _ = group_by_stt_with_meta(blocks)
    return merged
