"""
core/classify/ai_semantic_filter.py — AI-Driven Semantic Drug Verification & Noise Filtering.

Uses semantic component analysis, entity recognition, and DB match evidence
to classify OCR candidate blocks into:
  - DRUG: Valid drug name with brand/generic/dosage
  - NOISE_ADMIN: Administrative header (hospital, company, patient name, doctor, address, phone)
  - NOISE_DIAGNOSIS: Clinical diagnosis (trào ngược, đau bụng, v.v.)
  - NOISE_INSTRUCTION: Usage notes (sáng 1v, nhai nát, uống sau ăn)
"""

import re
from typing import Dict, Any, Tuple


class AISemanticFilter:
    """AI-driven semantic filter for validating candidate drug lines vs document noise."""

    # Dosage / Strength indicators
    STRENGTH_RE = re.compile(
        r"\b(\d+(\.\d+)?\s*(mg|ml|mcg|g|iu|ui|u|ou|unit|units|đơn\s+vị)\b|\d+\s*\+\s*\d+|\d+\s*u/ml|\d+\s*ou/ml|\d+\s*ui/ml)",
        re.IGNORECASE,
    )
    DOSAGE_FORM_RE = re.compile(
        r"\b(capsule|tablet|cap|tab|viên|gói|ống|lọ|vỉ|hộp|chai|bút|bút\s+tiêm|dung\s+dịch|hỗn\s+dịch|thuốc\s+tiêm|kem|mỡ|gel)\b",
        re.IGNORECASE,
    )

    # Pharmaceutical suffix patterns & common drug roots
    DRUG_SUFFIX_RE = re.compile(
        r"(zole|zola|zoli|sone|xone|prazole|statin|pril|sartan|cillin|mycin|thromycin|"
        r"tidine|fibrate|bital|dipine|olol|profen|cam|cetam|paracetamol|aspirin|"
        r"trisilicat|hydroxyd|magnesi|nhôm|calci|zinc|vitamin|"
        r"insulin|glargine|lantus|humulin|novomix|apidra|victoza|ozempic|metformin|gliclazide|"
        r"atorvastatin|rosuvastatin|amlodipine|nifedipine|valsartan|losartan|telmisartan|"
        r"perindopril|enalapril|bisoprolol|metoprolol|clopidogrel|omeprazole|esomeprazole|"
        r"pantoprazole|lansoprazole|eperisone|amoxicillin|cefuroxime|cefixime|azithromycin|"
        r"levofloxacin|ciprofloxacin|fluconazole|salbutamol|montelukast|loratadine|cetirizine)\b",
        re.IGNORECASE,
    )

    # Administrative & Hospital entity patterns
    ADMIN_ENTITY_RE = re.compile(
        r"("
        r"tnhh|cty|công\s+ty|medic|bvdk|bvđk|bvdv|bv\b|bệnh\s+viện|phòng\s+khám|viện\s+nhi|nhi\s+đồng|sở\s+y\s+tế|"
        r"họ\s+tên|bệnh\s+nhân|người\s+thân|nhân:|bác\s+sĩ|bác\s+sỹ|bs\.|cki|ckii|người\s+giao|nguyễn\s+thành|"
        r"cmnd|cccd|sđt|điện\s+thoại|tuổi|giới\s+tính|mã\s+bhyt|mã\s+bn|số\s+id|số\s+hđ|mã\s+bệnh|mã\s+đơn|số\s+toa|số\s+hồ\s+sơ|ms:|"
        r"địa\s+chỉ|đường|phường|quận|thành\s+phố|tpct|tp\.|khu\s+vực|tỉnh|lý\s+thái\s+tổ|vườn\s+lài|hùng\s+vương|ninh\s+kiều|"
        r"toa:|lời\s+dặn|khám\s+lại|tái\s+khám|xin\s+mang\s+theo|cộng\s+khoản|ghi\s+chú|đánh\s+giá|kết\s+luận|chế\s+độ|đề\s+nghị|"
        r"mạch|nhiệt\s+độ|cân\s+nặng|chiều\s+cao|chíêu\s+cao|biểu\s+hiện|lâm\s+sàng|dị\s+ứng|bệnh\s+kèm|trung\s+bình|cc/t|cn/t|cn/cc|bmi|co\s+giật|"
        r"trân\s+lê|trần\s+lê|tran\s+lê|mỹ\s+phương|ỹ\s+phương|huỳnh\s+đảm|huynh\s+dam|luu\s+phúc|phúc\s+khải|khải\s+hy"
        r")",
        re.IGNORECASE,
    )

    # Clinical Diagnosis & Symptom entity patterns
    DIAGNOSIS_ENTITY_RE = re.compile(
        r"("
        r"chẩn\s+đoán|chần\s+đoán|chần\s+đoản|chẩn\s+đoản|chan\s+doan|bệnh\s+trào\s+ngược|trào\s+ngược|dạ\s+dày|thực\s+quản|"
        r"đau\s+bụng|khu\s+trú|bụng\s+trên|rối\s+loạn|chuyển\s+hóa|tim\s+thiếu|chế\s+độ\s+ăn|sinh\s+hoạt|viêm\s+phế\s+quản|viềm\s+phể\s+quản|"
        r"sốt\s+cao|sốt|co\s+giật|vật\s+vã|bứt\s+rứt|nôn\s+ói|nôn\s+mửa|thở\s+mệt|dấu\s+hiệu"
        r")",
        re.IGNORECASE,
    )

    # Usage / Instruction patterns
    INSTRUCTION_ENTITY_RE = re.compile(
        r"("
        r"uống\s+trước|uống\s+sau|trước\s+ăn|sau\s+ăn|nhai\s+nát|nhại\s+nát|hòa\s+tan|"
        r"sáng\s+\d|trưa\s+\d|tối\s+\d|chiều\s+\d|ngày\s+\d|lần\s*,"
        r")",
        re.IGNORECASE,
    )

    DOSAGE_ONLY_RE = re.compile(
        r"^[\d\s.,]*(mg|ml|mcg|g|iu|viên|gói|ống|lọ|tab)\b$",
        re.IGNORECASE,
    )

    @classmethod
    def evaluate_candidate(
        cls,
        text: str,
        ocr_text: str = "",
        match_score: float = 0.0,
        matched_name: str = None,
    ) -> Tuple[str, float, str]:
        """
        Evaluate candidate text block using AI semantic rules.

        Returns:
            Tuple[classification_label, confidence_score, reason]
            classification_label: "DRUG" | "NOISE_ADMIN" | "NOISE_DIAGNOSIS" | "NOISE_INSTRUCTION"
        """
        cleaned_text = (text or "").strip()
        cleaned_ocr = (ocr_text or cleaned_text).strip()
        full_context = f"{cleaned_ocr} {cleaned_text}".strip()

        if len(cleaned_text) < 3:
            return "NOISE_ADMIN", 0.99, "Text length under 3 chars"

        if cls.DOSAGE_ONLY_RE.match(cleaned_text):
            return "NOISE_INSTRUCTION", 0.95, "Dosage-only text without drug name"

        # 1. Check for administrative / hospital noise in full context (takes precedence over weak fuzzy DB matches)
        if cls.ADMIN_ENTITY_RE.search(full_context):
            if match_score < 0.90 or not cls.STRENGTH_RE.search(cleaned_text):
                return "NOISE_ADMIN", 0.95, f"Matched administrative entity: '{cleaned_text}'"

        # 2. Check for clinical diagnosis noise
        if cls.DIAGNOSIS_ENTITY_RE.search(full_context):
            if match_score < 0.90:
                return "NOISE_DIAGNOSIS", 0.95, f"Matched clinical diagnosis: '{cleaned_text}'"

        # 3. Check for usage instruction noise
        if cls.INSTRUCTION_ENTITY_RE.search(full_context):
            if match_score < 0.90 and not cls.STRENGTH_RE.search(cleaned_text):
                return "NOISE_INSTRUCTION", 0.95, f"Matched usage instruction: '{cleaned_text}'"

        # 4. DB Match Evidence: Exact or High Confidence DB Match -> DRUG
        if match_score >= 0.65 or (matched_name and match_score >= 0.50):
            return "DRUG", min(1.0, match_score + 0.20), f"Strong DB match score: {match_score}"

        # 5. Semantic Drug Structure Evidence: Contains dosage/strength, dosage form, or drug suffix
        has_strength = bool(cls.STRENGTH_RE.search(cleaned_text))
        has_dosage_form = bool(cls.DOSAGE_FORM_RE.search(cleaned_text))
        has_drug_suffix = bool(cls.DRUG_SUFFIX_RE.search(cleaned_text))

        if has_strength or has_dosage_form or has_drug_suffix:
            return "DRUG", 0.85, "Valid semantic drug structure (strength/dosage form/suffix)"

        # 6. Fallback: If score is 0.0 and lacks all drug indicators, reject as unmapped noise
        if match_score == 0.0 and not (has_strength or has_drug_suffix):
            return "NOISE_ADMIN", 0.90, "Zero DB match and no semantic drug components"

        return "DRUG", 0.60, "Plausible drug candidate"
