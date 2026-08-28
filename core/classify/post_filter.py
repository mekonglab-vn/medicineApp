import re


from core.classify.ai_semantic_filter import AISemanticFilter


class NerPostFilter:
    """Heuristic and AI Semantic post-filter to remove non-drug OCR blocks."""

    @staticmethod
    def is_likely_drug(
        text: str,
        ocr_text: str = "",
        match_score: float = 0.0,
        matched_name: str = None,
    ) -> bool:
        txt = (text or "").strip()
        if len(txt) < 3:
            return False

        if txt.casefold() in {"viên sủi", "vien sui"}:
            return False

        label, confidence, reason = AISemanticFilter.evaluate_candidate(
            text=txt,
            ocr_text=ocr_text,
            match_score=match_score,
            matched_name=matched_name,
        )

        return label == "DRUG"
