import json
import sys
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))


from core.drug_search.drug_lookup import DrugLookup
from core.pipeline import MedicinePipeline


@pytest.fixture()
def lookup(tmp_path):
    fixture = {
        "drugs": [
            {
                "tenThuoc": "Cardiol 50mg",
                "soDangKy": "REG-C50",
                "hoatChat": [{"tenHoatChat": "Atenolol", "nongDo": "50mg"}],
            },
            {
                "tenThuoc": "Cardiol 100mg",
                "soDangKy": "REG-C100",
                "hoatChat": [{"tenHoatChat": "Atenolol", "nongDo": "100mg"}],
            },
            {
                "tenThuoc": "NoStrength",
                "soDangKy": "REG-NS",
                "hoatChat": [{"tenHoatChat": "Example ingredient", "nongDo": ""}],
            },
            {
                "tenThuoc": "Shared Brand A",
                "soDangKy": "REG-SA",
                "hoatChat": [{"tenHoatChat": "Sharedol", "nongDo": "10mg"}],
            },
            {
                "tenThuoc": "Shared Brand B",
                "soDangKy": "REG-SB",
                "hoatChat": [{"tenHoatChat": "Sharedol", "nongDo": "20mg"}],
            },
            {
                "tenThuoc": "Combix",
                "soDangKy": "REG-COMBO",
                "hoatChat": [
                    {"tenHoatChat": "Alpha", "nongDo": "500mg"},
                    {"tenHoatChat": "Beta", "nongDo": "125mg"},
                ],
            },
            {
                "tenThuoc": "Twin 10mg",
                "soDangKy": "REG-T1",
                "hoatChat": [{"tenHoatChat": "Twinol", "nongDo": "10mg"}],
            },
            {
                "tenThuoc": "Twin 10mg",
                "soDangKy": "REG-T2",
                "hoatChat": [{"tenHoatChat": "Twinol", "nongDo": "10mg"}],
            },
            {
                "tenThuoc": "Liquidol 50mg/ml",
                "soDangKy": "REG-LIQ",
                "hoatChat": [{"tenHoatChat": "Liquid ingredient", "nongDo": "50mg/ml"}],
            },
            {
                "tenThuoc": "Repeatix",
                "soDangKy": "REG-REPEAT",
                "hoatChat": [
                    {"tenHoatChat": "Repeat alpha", "nongDo": "500mg"},
                    {"tenHoatChat": "Repeat beta", "nongDo": "500mg"},
                ],
            },
            {
                "tenThuoc": "Shadow 50mg",
                "soDangKy": "REG-SHADOW-KNOWN",
                "hoatChat": [{"tenHoatChat": "Shadow ingredient", "nongDo": "50mg"}],
            },
            {
                "tenThuoc": "Shadow",
                "soDangKy": "REG-SHADOW-UNKNOWN",
                "hoatChat": [{"tenHoatChat": "Shadow ingredient", "nongDo": ""}],
            },
            {
                "tenThuoc": "Immuglob",
                "soDangKy": "REG-IU-MILLION",
                "hoatChat": [{"tenHoatChat": "Immune ingredient", "nongDo": "1.000.000 IU"}],
            },
            {
                "tenThuoc": "Interfer",
                "soDangKy": "REG-IU-THOUSAND",
                "hoatChat": [{"tenHoatChat": "Interferon", "nongDo": "15.000 IU"}],
            },
        ]
    }
    db_path = tmp_path / "drug_fixture.json"
    db_path.write_text(json.dumps(fixture), encoding="utf-8")
    return DrugLookup(str(db_path))


def test_exact_unambiguous_brand_with_compatible_strength_is_safe(lookup):
    result = lookup.lookup("Cardiol 50 mg")

    assert result["name"] == "Cardiol 50mg"
    assert result["match_basis"] == "brand_exact"
    assert result["strength_state"] == "compatible"
    assert result["ambiguous"] is False
    assert result["confirmation_safe"] is True
    assert result["resolution_reason"] == "exact_brand_compatible_strength"


def test_brand_with_incompatible_strength_is_not_safe(lookup):
    result = lookup.lookup("Cardiol 75mg")

    assert result["match_basis"] == "brand_exact"
    assert result["strength_state"] == "mismatch"
    assert result["confirmation_safe"] is False
    assert result["resolution_reason"] == "strength_mismatch"


def test_query_strength_with_no_candidate_strength_is_unknown(lookup):
    result = lookup.lookup("NoStrength 10mg")

    assert result["match_basis"] == "brand_exact"
    assert result["strength_state"] == "unknown_candidate"
    assert result["confirmation_safe"] is False
    assert result["resolution_reason"] == "candidate_strength_unknown"


def test_shared_ingredient_is_ambiguous_and_not_a_confirmed_brand(lookup):
    result = lookup.lookup("Sharedol")

    assert result["match_basis"] == "ingredient_exact"
    assert result["strength_state"] == "unknown_query"
    assert result["ambiguous"] is True
    assert result["confirmation_safe"] is False
    assert result["resolution_reason"] == "ingredient_only"


def test_ingredient_with_unique_strength_still_does_not_confirm_brand(lookup):
    result = lookup.lookup("Sharedol 10mg")

    assert result["name"] == "Shared Brand A"
    assert result["match_basis"] == "ingredient_exact"
    assert result["strength_state"] == "compatible"
    assert result["ambiguous"] is False
    assert result["confirmation_safe"] is False
    assert result["resolution_reason"] == "ingredient_only"


def test_combination_product_requires_complete_strength_evidence(lookup):
    complete = lookup.lookup("Combix 500mg/125mg")
    incomplete = lookup.lookup("Combix 500mg")

    assert complete["strength_state"] == "compatible"
    assert complete["confirmation_safe"] is True
    assert incomplete["strength_state"] == "mismatch"
    assert incomplete["confirmation_safe"] is False


def test_strength_form_distinguishes_mass_from_concentration(lookup):
    concentration = lookup.lookup("Liquidol 50mg/ml")
    mass_only = lookup.lookup("Liquidol 50mg")

    assert concentration["strength_state"] == "compatible"
    assert concentration["confirmation_safe"] is True
    assert mass_only["match_basis"] == "brand_exact"
    assert mass_only["strength_state"] == "mismatch"
    assert mass_only["confirmation_safe"] is False


def test_repeated_combination_strengths_preserve_multiplicity(lookup):
    complete = lookup.lookup("Repeatix 500mg/500mg")
    incomplete = lookup.lookup("Repeatix 500mg")

    assert complete["strength_state"] == "compatible"
    assert complete["confirmation_safe"] is True
    assert incomplete["strength_state"] == "mismatch"
    assert incomplete["confirmation_safe"] is False


def test_parenthetical_explicit_brand_remains_supported(lookup):
    result = lookup.lookup("Atenolol (Cardiol 50 mg) 50 mg")

    assert result["name"] == "Cardiol 50mg"
    assert result["match_basis"] == "brand_exact"
    assert result["strength_state"] == "compatible"
    assert result["confirmation_safe"] is True


def test_parenthetical_brand_cannot_hide_conflicting_outer_strength(lookup):
    result = lookup.lookup("Atenolol 100mg (Cardiol 50mg)")

    assert result["name"] == "Cardiol 50mg"
    assert result["match_basis"] == "brand_exact"
    assert result["strength_state"] == "mismatch"
    assert result["confirmation_safe"] is False
    assert result["resolution_reason"] == "contradictory_query_strength"
    assert result["so_dang_ky"] == "REG-C50"
    assert result["normalized_candidate_strength"] == "50 mg"


def test_pipeline_keeps_conflicting_candidate_evidence_for_review(lookup):
    pipeline = MedicinePipeline()
    pipeline._drug_mapper = lookup

    medications, candidates = pipeline._extract_medications([{
        "label": "drugname",
        "text": "Atenolol 100mg (Cardiol 50mg)",
        "confidence": 0.99,
    }])

    assert len(medications) == 1
    assert len(candidates) == 1
    assert candidates[0]["mapping_status"] == "unmapped_candidate"
    assert candidates[0]["matched_drug_name"] == "Cardiol 50mg"
    assert candidates[0]["resolution_reason"] == "contradictory_query_strength"
    assert candidates[0]["registration_number"] == "REG-C50"
    assert candidates[0]["normalized_candidate_strength"] == "50 mg"
    assert candidates[0]["normalized_query_strength"] == "100 mg + 50 mg"


def test_duplicate_exact_brand_is_ambiguous(lookup):
    result = lookup.lookup("Twin 10mg")

    assert result["match_basis"] == "brand_exact"
    assert result["ambiguous"] is True
    assert result["confirmation_safe"] is False
    assert result["resolution_reason"] == "ambiguous_brand"


def test_unknown_strength_duplicate_keeps_exact_brand_ambiguous(lookup):
    result = lookup.lookup("Shadow 50mg")

    assert result["match_basis"] == "brand_exact"
    assert result["strength_state"] == "compatible"
    assert result["ambiguous"] is True
    assert result["confirmation_safe"] is False
    assert result["resolution_reason"] == "ambiguous_brand"


def test_vietnamese_thousands_separators_are_parsed_as_nonzero_iu(lookup):
    strengths = DrugLookup._extract_strength_tokens("1.000.000 IU; 15.000 IU")
    million = lookup.lookup("Immuglob 1.000.000 IU")
    thousand = lookup.lookup("Interfer 15.000 IU")
    wrong = lookup.lookup("Immuglob 1 IU")

    assert strengths == {"1000000 iu": 1, "15000 iu": 1}
    assert "0 iu" not in strengths
    assert million["strength_state"] == "compatible"
    assert million["confirmation_safe"] is True
    assert thousand["strength_state"] == "compatible"
    assert thousand["confirmation_safe"] is True
    assert wrong["strength_state"] == "mismatch"
    assert wrong["confirmation_safe"] is False


def test_lookup_preserves_existing_keys_and_adds_evidence(lookup):
    result = lookup.lookup("Cardiol 50mg")

    assert {
        "original", "name", "generic", "score", "so_dang_ky", "nong_do", "source",
        "match_basis", "strength_state", "ambiguous", "resolution_reason",
        "confirmation_safe",
    } <= result.keys()
    assert result["original"] == "Cardiol 50mg"


def test_pipeline_preserves_raw_text_and_all_candidates_without_models():
    pipeline = MedicinePipeline()

    class FakeMapper:
        def lookup(self, text):
            if text == "Cardiol 50mg":
                return {
                    "name": "Cardiol 50mg",
                    "score": 1.0,
                    "match_basis": "brand_exact",
                    "strength_state": "compatible",
                    "ambiguous": False,
                    "resolution_reason": "exact_brand_compatible_strength",
                    "confirmation_safe": True,
                    "so_dang_ky": "REG-C50",
                    "normalized_candidate_strength": "50 mg",
                }
            if text == "Sharedol 10mg":
                return {
                    "name": "Shared Brand A",
                    "score": 1.0,
                    "match_basis": "ingredient_exact",
                    "strength_state": "compatible",
                    "ambiguous": False,
                    "resolution_reason": "ingredient_only",
                    # Pipeline must independently reject inconsistent upstream evidence.
                    "confirmation_safe": True,
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

    pipeline._drug_mapper = FakeMapper()
    medications, candidates = pipeline._extract_medications([
        {"label": "drugname", "text": "Cardiol 50mg", "confidence": 0.98},
        {"label": "drugname", "text": "Sharedol 10mg", "confidence": 0.96},
        {"label": "drugname", "text": "10ml", "confidence": 0.8},
    ])

    assert [item["mapping_status"] for item in medications] == [
        "confirmed", "unmapped_candidate",
    ]
    assert [item["mapping_status"] for item in candidates] == [
        "confirmed", "unmapped_candidate", "rejected_noise",
    ]
    assert medications[0]["ocr_text"] == "Cardiol 50mg"
    assert medications[0]["drug_name_raw"] == "Cardiol 50mg"
    assert medications[0]["registration_number"] == "REG-C50"
    assert medications[0]["normalized_candidate_strength"] == "50 mg"
    assert medications[1]["matched_drug_name"] == "Shared Brand A"
    assert medications[1]["mapped_drug_name"] == "Shared Brand A"
    assert medications[1]["confirmation_safe"] is False
