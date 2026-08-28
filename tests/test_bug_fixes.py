"""
Tests cho Phase A classifier.
"""
import pytest
from core.pipeline import MedicinePipeline


class _FakeMapper:
    def lookup(self, text):
        if "para" in text.lower():
            return {
                "name": "Paracetamol",
                "score": 0.94,
                "match_basis": "brand_exact",
                "strength_state": "compatible",
                "ambiguous": False,
                "resolution_reason": "exact_brand_compatible_strength",
                "confirmation_safe": True,
                "so_dang_ky": "REG-PARA-500",
                "normalized_candidate_strength": "500 mg",
            }
        return {
            "name": None,
            "score": 0.0,
            "match_basis": "none",
            "strength_state": "unknown_candidate",
            "ambiguous": False,
            "resolution_reason": "no_match",
            "confirmation_safe": False,
        }


class TestPipelineResolution:
    def test_extract_medications_keeps_unmapped_candidates(self):
        pipe = MedicinePipeline()
        pipe._drug_mapper = _FakeMapper()

        ner_results = [
            {
                "label": "drugname",
                "text": "Paracetamol 500mg",
                "confidence": 0.95,
                "bbox": [1, 2, 3, 4],
            },
            {
                "label": "drugname",
                "text": "Mystery Capsule",
                "confidence": 0.88,
                "bbox": [5, 6, 7, 8],
            },
            {
                "label": "drugname",
                "text": "10ml",
                "confidence": 0.8,
                "bbox": [9, 10, 11, 12],
            },
        ]

        medications, candidates = pipe._extract_medications(ner_results)

        assert [item["mapping_status"] for item in medications] == [
            "confirmed",
            "unmapped_candidate",
        ]
        assert candidates[2]["mapping_status"] == "rejected_noise"
        assert medications[1]["drug_name"] == "Mystery Capsule"


class TestNerKeys:
    """Test NER extractor returns 'bbox' key."""

    def test_ner_returns_bbox_key(self):
        """NER classify() output should have 'bbox' key, not 'box'."""
        from core.classify.ner_extractor import NerExtractor
        extractor = NerExtractor()
        blocks = [
            {"text": "Paracetamol 500mg", "bbox": [10, 20, 100, 40]},
        ]
        results = extractor.classify(blocks)
        assert len(results) > 0
        assert "bbox" in results[0]
        assert "box" not in results[0]

    def test_ner_reads_box_input(self):
        """NER should also read 'box' key from input (backward compat)."""
        from core.classify.ner_extractor import NerExtractor
        extractor = NerExtractor()
        blocks = [
            {"text": "Paracetamol", "box": [10, 20, 100, 40]},
        ]
        results = extractor.classify(blocks)
        assert results[0]["bbox"] == [10, 20, 100, 40]
