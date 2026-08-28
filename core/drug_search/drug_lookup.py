"""
drug_lookup.py — Drug name lookup using Vietnamese drug database (9,284 drugs).

Priority: Local fuzzy match only (no API calls).
Database: data/drug_db_vn_full.json (9,284 thuốc từ ddi.lab.io.vn)
Fallback:  data/drug_db_vn.csv        (316 thuốc cũ)

Usage:
    from core.drug_search.drug_lookup import DrugLookup
    lu = DrugLookup()
    result = lu.lookup("Celecoxib 200mg")
    # {'name': 'Celecoxib', 'generic': 'celecoxib', 'score': 0.97, ...}
"""

import csv
import json
import logging
import os
import re
from collections import Counter
from decimal import Decimal
from typing import Optional

from rapidfuzz import fuzz, process

logger = logging.getLogger(__name__)

MIN_SCORE = 65   # Minimum fuzzy score to accept match

_NUMBER_PATTERN = r"(?:\d{1,3}(?:\.\d{3})+(?:,\d+)?|\d+(?:[.,]\d+)?)"
_STRENGTH_PATTERN = re.compile(
    rf"(?P<concentration>"
    rf"(?P<c_value>{_NUMBER_PATTERN})\s*(?P<c_unit>mcg|mg|iu|ui|u|ou|g)\s*/\s*"
    rf"(?:(?P<d_value>{_NUMBER_PATTERN})\s*)?(?P<d_unit>ml|g)\b"
    rf")|"
    rf"(?P<simple>"
    rf"(?P<s_value>{_NUMBER_PATTERN})\s*(?P<s_unit>mcg|mg|ml|iu|ui|u|ou|g)\b"
    rf")",
    flags=re.IGNORECASE,
)

# Paths relative to project root (3 levels up from this file)
_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(__file__)))
_DEFAULT_JSON_DB = os.path.join(_ROOT, "data", "drug_db_vn_full.json")
_DEFAULT_CSV_DB  = os.path.join(_ROOT, "data", "drug_db_vn.csv")


class DrugLookup:
    """
    Local Vietnamese drug name lookup via fuzzy matching.
    Ưu tiên drug_db_vn_full.json (9,284 thuốc), fallback sang CSV cũ.
    """

    def __init__(self, db_path: Optional[str] = None):
        self._entries: list = []
        self._search_keys: list = []
        self._match_bases: list = []
        # Thử JSON đầy đủ trước, fallback CSV
        json_path = db_path or _DEFAULT_JSON_DB
        if os.path.exists(json_path) and json_path.endswith(".json"):
            self._load_json(json_path)
        else:
            self._load_csv(_DEFAULT_CSV_DB)

    # ── Loaders ──────────────────────────────────────────────────────────────

    def _load_json(self, path: str) -> None:
        """Load drug_db_vn_full.json — 9,284 thuốc VN."""
        try:
            with open(path, encoding="utf-8") as f:
                data = json.load(f)
        except Exception as e:
            logger.error(f"DrugLookup: lỗi đọc JSON {path}: {e}")
            return

        drugs = data.get("drugs", []) if isinstance(data, dict) else data
        for drug in drugs:
            ten_thuoc = drug.get("tenThuoc", "").strip()
            if not ten_thuoc:
                continue

            hoat_chats = drug.get("hoatChat", [])
            if isinstance(hoat_chats, list):
                generic_names = [
                    hc.get("tenHoatChat", "") for hc in hoat_chats
                    if isinstance(hc, dict) and hc.get("tenHoatChat")
                ]
                nong_do = ", ".join(
                    hc.get("nongDo", "") for hc in hoat_chats
                    if isinstance(hc, dict) and hc.get("nongDo")
                )
            else:
                generic_names = []
                nong_do = ""

            entry = {
                "brand_name":  ten_thuoc,
                "generic_name": ", ".join(generic_names),
                "so_dang_ky":  drug.get("soDangKy", ""),
                "nong_do":     nong_do,
                "source":      "drug_db_vn_full",
            }

            self._entries.append(entry)
            self._search_keys.append(self._normalize_name(ten_thuoc))
            self._match_bases.append("brand")

            for g in generic_names:
                g_lo = self._normalize_name(g)
                if g_lo and g_lo != self._normalize_name(ten_thuoc):
                    self._entries.append(entry)
                    self._search_keys.append(g_lo)
                    self._match_bases.append("ingredient")

        logger.info(
            f"DrugLookup (JSON): {len(self._entries)} search keys "
            f"từ {len(drugs)} thuốc"
        )

    def _load_csv(self, path: str) -> None:
        """Fallback: load drug_db_vn.csv."""
        if not os.path.exists(path):
            logger.warning(f"Drug DB không tìm thấy: {path}")
            return
        with open(path, encoding="utf-8") as f:
            reader = csv.DictReader(f)
            for row in reader:
                brand   = row.get("brand_name", "").strip()
                generic = row.get("generic_name", "").strip()
                if not brand:
                    continue
                row["source"] = "drug_db_vn_csv"
                row["so_dang_ky"] = ""
                row["nong_do"] = ""
                self._entries.append(row)
                self._search_keys.append(self._normalize_name(brand))
                self._match_bases.append("brand")
                if generic and self._normalize_name(generic) != self._normalize_name(brand):
                    self._entries.append(row)
                    self._search_keys.append(self._normalize_name(generic))
                    self._match_bases.append("ingredient")
        logger.info(
            f"DrugLookup (CSV fallback): {len(self._entries)} search keys"
        )

    # ── Helpers ───────────────────────────────────────────────────────────────

    @staticmethod
    def _clean(text: str) -> str:
        """Làm sạch OCR text trước khi fuzzy search."""
        return DrugLookup._normalize_name(text)

    @staticmethod
    def _normalize_name(text: str) -> str:
        raw_clean = str(text or "").replace("_", " ")
        t = _STRENGTH_PATTERN.sub(" ", raw_clean)
        t = re.sub(r"^\d{1,3}\s+", "", t)
        t = re.sub(r"\s+\d{1,3}$", "", t)
        t = re.sub(r"[^\wÀ-ỹ]+", " ", t, flags=re.UNICODE)
        return " ".join(t.lower().split()).strip()

    @staticmethod
    def _has_root_overlap(query: str, candidate: str) -> bool:
        """Yêu cầu ít nhất 1 token có nghĩa chung."""
        stop = {
            "", "mg", "ml", "mcg", "g", "iu", "tab", "cap",
            "viên", "ống", "lọ", "chai", "gói", "sủi",
            "thuốc", "và", "the", "for", "forte", "extra", "plus",
            "max", "mini", "nano", "fast", "express", "drops", "syrup",
            "solution", "eye", "capsules", "tablets", "nhỏ", "mắt", "xịt", "mũi",
        }
        q_words = {w for w in re.split(r"\W+", query.lower()) if w not in stop and len(w) >= 3}
        c_words = {w for w in re.split(r"\W+", candidate.lower()) if w not in stop and len(w) >= 3}
        return bool(q_words & c_words)

    @staticmethod
    def _parse_amount(value: str) -> Decimal:
        value = value.strip()
        if re.fullmatch(r"\d{1,3}(?:\.\d{3})+(?:,\d+)?", value):
            value = value.replace(".", "").replace(",", ".")
        else:
            value = value.replace(",", ".")
        return Decimal(value)

    @staticmethod
    def _format_amount(amount: Decimal) -> str:
        formatted = format(amount, "f")
        if "." in formatted:
            formatted = formatted.rstrip("0").rstrip(".")
        return formatted or "0"

    @classmethod
    def _canonical_amount_unit(cls, value: str, unit: str) -> tuple[Decimal, str]:
        amount = cls._parse_amount(value)
        unit = unit.lower()
        if unit == "g":
            amount *= Decimal(1000)
            unit = "mg"
        elif unit == "mcg":
            amount /= Decimal(1000)
            unit = "mg"
        return amount, unit

    @classmethod
    def _extract_strength_tokens(cls, text: str) -> Counter:
        strengths = Counter()
        for match in _STRENGTH_PATTERN.finditer(str(text or "")):
            if match.group("concentration"):
                amount, unit = cls._canonical_amount_unit(
                    match.group("c_value"), match.group("c_unit")
                )
                denominator = cls._parse_amount(match.group("d_value") or "1")
                denominator_unit = match.group("d_unit").lower()
                token = (
                    f"{cls._format_amount(amount)} {unit}/"
                    f"{cls._format_amount(denominator)} {denominator_unit}"
                )
            else:
                amount, unit = cls._canonical_amount_unit(
                    match.group("s_value"), match.group("s_unit")
                )
                token = f"{cls._format_amount(amount)} {unit}"
            strengths[token] += 1
        return strengths

    @classmethod
    def _extract_query_strengths(
        cls, text: str, match_key: str
    ) -> tuple[Counter, bool, Counter]:
        for parenthetical_match in re.finditer(r"\(([^)]+)\)", text):
            parenthetical = parenthetical_match.group(1)
            strengths = cls._extract_strength_tokens(parenthetical)
            if strengths and cls._normalize_name(parenthetical) == match_key:
                outside = (
                    text[:parenthetical_match.start()]
                    + " "
                    + text[parenthetical_match.end():]
                )
                outside_strengths = cls._extract_strength_tokens(outside)
                contradictory = any(
                    token not in strengths for token in outside_strengths
                )
                if contradictory:
                    return strengths + outside_strengths, True, strengths
                return strengths, False, strengths
        strengths = cls._extract_strength_tokens(text)
        return strengths, False, strengths

    @staticmethod
    def _format_strength_evidence(strengths: Counter) -> str:
        return " + ".join(
            token
            for token in sorted(strengths)
            for _ in range(strengths[token])
        )

    @classmethod
    def _strength_evidence(
        cls,
        query_text: str,
        entry: dict,
        match_key: str,
    ) -> dict:
        (
            query_strengths,
            contradictory,
            preferred_strengths,
        ) = cls._extract_query_strengths(query_text, match_key)

        candidate_text = entry.get("nong_do", "").strip()
        if not candidate_text:
            candidate_text = " ".join(
                filter(
                    None,
                    [
                        entry.get("brand_name", ""),
                        entry.get("generic_name", ""),
                    ],
                )
            )
        candidate_strengths = cls._extract_strength_tokens(candidate_text)

        if not query_strengths:
            state = "unknown_query"
        elif not candidate_strengths:
            state = "unknown_candidate"
        elif contradictory or query_strengths != candidate_strengths:
            state = "mismatch"
        else:
            state = "compatible"

        return {
            "state": state,
            "contradictory": contradictory,
            "candidate_aligned": bool(
                preferred_strengths
                and candidate_strengths == preferred_strengths
            ),
            "normalized_query_strength": cls._format_strength_evidence(query_strengths),
            "normalized_candidate_strength": cls._format_strength_evidence(
                candidate_strengths
            ),
        }

    @classmethod
    def _strength_state(
        cls,
        query_text: str,
        entry: dict,
        match_key: str,
    ) -> str:
        return cls._strength_evidence(query_text, entry, match_key)["state"]

    @classmethod
    def _strength_compatible(
        cls,
        query_text: str,
        entry: dict,
        match_key: str,
    ) -> bool:
        return cls._strength_state(query_text, entry, match_key) == "compatible"

    # ── Public API ────────────────────────────────────────────────────────────

    def lookup(self, text: str) -> dict:
        """Fuzzy match tên thuốc OCR → tên chuẩn trong DB."""
        if not self._search_keys:
            return self._empty(text)

        text = re.sub(r"^\d+[\.\/\,\-]\s*", "", text.strip())
        query_clean  = self._clean(text)
        paren_m      = re.search(r"\(([^)]+)\)", text)
        query_paren  = self._clean(paren_m.group(1)) if paren_m else ""
        no_paren     = re.sub(r"\([^)]*\)", " ", text)
        query_no_par = self._clean(no_paren)

        candidates = []
        variant_priority = {
            "query_clean": 3,
            "query_no_par": 2,
            "query_paren": 1,
        }

        for variant_name, query in [
            ("query_clean", query_clean),
            ("query_paren", query_paren),
            ("query_no_par", query_no_par),
        ]:
            if not query or len(query) < 3:
                continue
            exact_indices = [
                idx for idx, key in enumerate(self._search_keys) if key == query
            ]
            if exact_indices:
                results = [(query, 100.0, idx) for idx in exact_indices]
            else:
                results = process.extract(
                    query,
                    self._search_keys,
                    scorer=fuzz.token_sort_ratio,
                    limit=10,
                )
            for match_key, score, idx in results:
                if score < MIN_SCORE:
                    continue
                if not self._has_root_overlap(query, match_key):
                    continue
                entry = self._entries[idx]
                alias_basis = self._match_bases[idx]
                exact = query == match_key
                match_basis = f"{alias_basis}_{'exact' if exact else 'fuzzy'}"
                strength_evidence = self._strength_evidence(text, entry, match_key)
                strength_state = strength_evidence["state"]
                basis_rank = {
                    "brand_exact": 4,
                    "ingredient_exact": 3,
                    "brand_fuzzy": 2,
                    "ingredient_fuzzy": 1,
                }[match_basis]
                # Ưu tiên các thuốc đơn chất (hoặc ít tá dược/hợp chất điện giải) để không nhầm sang Alvesin 40 / Diclofenac
                generic_count = len([g for g in entry.get("generic_name", "").split(",") if g.strip()])
                single_ingredient_bonus = 2 if generic_count <= 1 else 0

                candidate_rank = (
                    basis_rank,
                    single_ingredient_bonus,
                    1 if strength_evidence["candidate_aligned"] else 0,
                    variant_priority[variant_name],
                    score,
                )
                candidates.append({
                    "rank": candidate_rank,
                    "match_key": match_key,
                    "score": score,
                    "idx": idx,
                    "match_basis": match_basis,
                    "strength_state": strength_state,
                    "strength_evidence": strength_evidence,
                })

        if not candidates:
            return self._empty(text)

        selected = max(candidates, key=lambda item: item["rank"])
        match_key = selected["match_key"]
        score = selected["score"]
        idx = selected["idx"]
        entry = self._entries[idx]
        alias_type = self._match_bases[idx]
        related_indices = {
            candidate_idx
            for candidate_idx, candidate_key in enumerate(self._search_keys)
            if candidate_key == match_key and self._match_bases[candidate_idx] == alias_type
        }
        compatible_indices = {
            candidate_idx
            for candidate_idx in related_indices
            if self._strength_state(
                text,
                self._entries[candidate_idx],
                self._search_keys[candidate_idx],
            ) == "compatible"
        }
        unknown_indices = {
            candidate_idx
            for candidate_idx in related_indices
            if self._strength_state(
                text,
                self._entries[candidate_idx],
                self._search_keys[candidate_idx],
            ) == "unknown_candidate"
        }
        ambiguity_pool = (compatible_indices | unknown_indices) or related_indices
        product_ids = {
            self._entries[candidate_idx].get("so_dang_ky")
            or (
                self._entries[candidate_idx].get("brand_name"),
                self._entries[candidate_idx].get("nong_do"),
            )
            for candidate_idx in ambiguity_pool
        }
        ambiguous = len(product_ids) > 1
        match_basis = selected["match_basis"]
        strength_state = selected["strength_state"]
        strength_evidence = selected["strength_evidence"]
        confirmation_safe = (
            match_basis == "brand_exact"
            and strength_state == "compatible"
            and not ambiguous
        )

        if match_basis.startswith("ingredient_"):
            resolution_reason = "ingredient_only"
        elif strength_evidence["contradictory"]:
            resolution_reason = "contradictory_query_strength"
        elif strength_state == "mismatch":
            resolution_reason = "strength_mismatch"
        elif strength_state == "unknown_candidate":
            resolution_reason = "candidate_strength_unknown"
        elif strength_state == "unknown_query":
            resolution_reason = "query_strength_unknown"
        elif ambiguous:
            resolution_reason = "ambiguous_brand"
        elif match_basis == "brand_fuzzy":
            resolution_reason = "fuzzy_brand_only"
        else:
            resolution_reason = "exact_brand_compatible_strength"

        return {
            "original":    text,
            "name":        entry.get("brand_name", "").strip(),
            "generic":     entry.get("generic_name", "").strip(),
            "score":       round(score / 100.0, 3),
            "so_dang_ky":  entry.get("so_dang_ky", ""),
            "registration_number": entry.get("so_dang_ky", ""),
            "nong_do":     entry.get("nong_do", ""),
            "source":      entry.get("source", ""),
            "match_basis": match_basis,
            "strength_state": strength_state,
            "ambiguous": ambiguous,
            "resolution_reason": resolution_reason,
            "confirmation_safe": confirmation_safe,
            "normalized_query_strength": strength_evidence["normalized_query_strength"],
            "normalized_candidate_strength": strength_evidence[
                "normalized_candidate_strength"
            ],
        }

    def lookup_batch(self, texts: list) -> list:
        return [self.lookup(t) for t in texts]

    @staticmethod
    def _empty(original: str) -> dict:
        return {
            "original":   original,
            "name":       None,
            "generic":    None,
            "score":      0.0,
            "so_dang_ky": "",
            "registration_number": "",
            "nong_do":    "",
            "source":     None,
            "match_basis": "none",
            "strength_state": (
                "unknown_candidate"
                if DrugLookup._extract_strength_tokens(original)
                else "unknown_query"
            ),
            "ambiguous": False,
            "resolution_reason": "no_match",
            "confirmation_safe": False,
            "normalized_query_strength": DrugLookup._format_strength_evidence(
                DrugLookup._extract_strength_tokens(original)
            ),
            "normalized_candidate_strength": "",
        }

    @property
    def db_size(self) -> int:
        """Số lượng thuốc unique trong DB."""
        return len(set(e.get("brand_name", "") for e in self._entries))
