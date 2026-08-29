"""
tests/test_mlkit_layout_adapter.py — Unit tests for MLKitLayoutAdapter.
"""

import sys
from pathlib import Path

ROOT = str(Path(__file__).resolve().parents[1])
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

import pytest
from core.classify.mlkit_layout_adapter import (
    MLKitLayoutAdapter,
    LayoutLine,
    LayoutRow,
)


def test_normalize_bbox():
    adapter = MLKitLayoutAdapter()

    # Dict with left, top, right, bottom
    bbox1 = adapter.normalize_bbox({"left": 10, "top": 20, "right": 110, "bottom": 40})
    assert bbox1 == [[10.0, 20.0], [110.0, 20.0], [110.0, 40.0], [10.0, 40.0]]

    # Dict with x, y, width, height
    bbox2 = adapter.normalize_bbox({"x": 15, "y": 25, "width": 80, "height": 30})
    assert bbox2 == [[15.0, 25.0], [95.0, 25.0], [95.0, 55.0], [15.0, 55.0]]

    # 4 numbers [x1, y1, x2, y2]
    bbox3 = adapter.normalize_bbox([5, 10, 50, 30])
    assert bbox3 == [[5.0, 10.0], [50.0, 10.0], [50.0, 30.0], [5.0, 30.0]]

    # 4 points
    bbox4 = adapter.normalize_bbox([[1, 2], [10, 2], [10, 20], [1, 20]])
    assert bbox4 == [[1.0, 2.0], [10.0, 2.0], [10.0, 20.0], [1.0, 20.0]]


def test_parse_ocr_lines():
    adapter = MLKitLayoutAdapter()

    # Raw list of dicts
    data = [
        {
            "text": "1",
            "bbox": {"left": 30, "top": 100, "right": 50, "bottom": 120},
            "confidence": 0.99,
        },
        {
            "text": "Amlor 5mg",
            "bbox": {"left": 70, "top": 100, "right": 250, "bottom": 120},
            "confidence": 0.98,
        },
        {
            "text": "30 Viên",
            "bbox": {"left": 400, "top": 100, "right": 480, "bottom": 120},
            "confidence": 0.95,
        },
    ]

    lines = adapter.parse_ocr_lines(data)
    assert len(lines) == 3
    assert lines[0].text == "1"
    assert lines[1].text == "Amlor 5mg"
    assert lines[2].text == "30 Viên"
    assert lines[1].x_min == 70.0
    assert lines[1].width == 180.0


def test_row_clustering_and_reading_order():
    adapter = MLKitLayoutAdapter()

    # Create lines in random order across 2 rows
    # Row 1 (y ~ 100): "1", "Amlor 5mg", "30 Viên"
    # Row 2 (y ~ 130): "Ngày uống 1 viên sáng sau ăn"
    data = [
        {"text": "30 Viên", "bbox": {"left": 400, "top": 102, "right": 480, "bottom": 122}},
        {"text": "1", "bbox": {"left": 30, "top": 98, "right": 50, "bottom": 118}},
        {"text": "Amlor 5mg", "bbox": {"left": 70, "top": 100, "right": 250, "bottom": 120}},
        {"text": "Ngày uống 1 viên sáng sau ăn", "bbox": {"left": 70, "top": 130, "right": 350, "bottom": 150}},
    ]

    lines = adapter.parse_ocr_lines(data)
    rows = adapter.cluster_rows(lines)

    assert len(rows) == 2
    # First row should be sorted left-to-right
    assert rows[0].text == "1 Amlor 5mg 30 Viên"
    assert rows[1].text == "Ngày uống 1 viên sáng sau ăn"


def test_medication_band_grouping_p3():
    adapter = MLKitLayoutAdapter()

    data = [
        # Drug 1
        {"text": "1.", "bbox": {"left": 30, "top": 100, "right": 50, "bottom": 120}},
        {"text": "Amlor 5mg", "bbox": {"left": 70, "top": 100, "right": 250, "bottom": 120}},
        {"text": "28", "bbox": {"left": 400, "top": 100, "right": 430, "bottom": 120}},
        {"text": "Viên", "bbox": {"left": 440, "top": 100, "right": 480, "bottom": 120}},
        {"text": "Ngày uống 1 viên sáng sau ăn", "bbox": {"left": 70, "top": 130, "right": 350, "bottom": 150}},
        # Drug 2
        {"text": "2.", "bbox": {"left": 30, "top": 170, "right": 50, "bottom": 190}},
        {"text": "Micardis 40mg", "bbox": {"left": 70, "top": 170, "right": 280, "bottom": 190}},
        {"text": "30", "bbox": {"left": 400, "top": 170, "right": 430, "bottom": 190}},
        {"text": "Viên", "bbox": {"left": 440, "top": 170, "right": 480, "bottom": 190}},
        {"text": "Ngày uống 1 viên", "bbox": {"left": 70, "top": 200, "right": 220, "bottom": 220}},
    ]

    blocks, meta = adapter.process(data, strategy="p3_medication_bands")
    assert meta["strategy"] == "p3_medication_bands"
    assert len(blocks) == 2

    # Block 1
    assert "Amlor 5mg" in blocks[0]["text"]
    assert "28" in blocks[0]["text"]
    assert "Viên" in blocks[0]["text"]
    assert "Ngày uống 1 viên sáng sau ăn" in blocks[0]["text"]

    # Block 2
    assert "Micardis 40mg" in blocks[1]["text"]
    assert "30" in blocks[1]["text"]
    assert "Viên" in blocks[1]["text"]
    assert "Ngày uống 1 viên" in blocks[1]["text"]


def test_fallback_plain_text():
    adapter = MLKitLayoutAdapter()
    sample_text = "1. Paracetamol 500mg - 20 Viên\nUống khi đau sốt\n2. Celecoxib 200mg - 10 Viên\nUống sau ăn"

    blocks, meta = adapter.process(None, fallback_text=sample_text, strategy="p3_medication_bands")
    assert len(blocks) == 2
    assert "Paracetamol 500mg" in blocks[0]["text"]
    assert "Celecoxib 200mg" in blocks[1]["text"]
