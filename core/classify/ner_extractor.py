"""
NER Extractor: PhoBERT-based Named Entity Recognition for drug names.
Uses a fine-tuned PhoBERT NER model to classify text blocks as drugname/other.

Strategy: Process each OCR block independently to avoid truncation.
"""
import re
import torch
from transformers import AutoTokenizer, AutoModelForTokenClassification

try:
    from underthesea import word_tokenize
    HAS_UNDERTHESEA = True
except ImportError:
    HAS_UNDERTHESEA = False

# Regex for STT prefix: "1)", "2.", "3 ", "10-"
STT_REGEX = re.compile(r'^(\d+(?:[\)\.\-]|(?=\s))\s*)(.*)')


class NerExtractor:
    """Extract drug names from OCR text blocks using PhoBERT NER."""

    def __init__(self, model_path="models/phobert_ner_model"):
        self.tokenizer = AutoTokenizer.from_pretrained(model_path)
        self.model = AutoModelForTokenClassification.from_pretrained(
            model_path
        )
        self.model.eval()
        self.id2label = self.model.config.id2label

    def _get_label(self, pred_id):
        """Get label string from prediction id (handles int/str keys)."""
        return self.id2label.get(
            pred_id, self.id2label.get(str(pred_id), "O")
        )

    def _extract_drug_and_instruction(self, text):
        """
        Dùng PhoBERT NER để tách Tên thuốc (B-DRUG, I-DRUG) và Hướng dẫn (O)
        từ một chuỗi văn bản.
        """
        text = text.strip()
        if not text:
            return "", "", 0.0

        # Word segment Vietnamese
        if HAS_UNDERTHESEA:
            text_seg = word_tokenize(text, format="text")
        else:
            text_seg = text

        words = text_seg.split()
        if not words:
            return "", "", 0.0

        # Tokenize each word manually
        word_subwords = []
        for word in words:
            encoded = self.tokenizer.encode(word, add_special_tokens=False)
            if not encoded:
                encoded = [self.tokenizer.unk_token_id]
            word_subwords.append(encoded)

        # Build input: [CLS] + subwords + [SEP]
        input_ids = [self.tokenizer.cls_token_id]
        word_map = [-1]  # CLS → no word

        for word_idx, subs in enumerate(word_subwords):
            if len(input_ids) + len(subs) + 1 > 256:
                break
            for j, sw in enumerate(subs):
                input_ids.append(sw)
                word_map.append(word_idx if j == 0 else -1)

        input_ids.append(self.tokenizer.sep_token_id)
        word_map.append(-1)

        # Run model
        ids_tensor = torch.tensor([input_ids])
        attn_mask = torch.ones(1, len(input_ids), dtype=torch.long)

        with torch.no_grad():
            logits = self.model(
                input_ids=ids_tensor,
                attention_mask=attn_mask,
            ).logits

        probs = torch.softmax(logits, dim=-1)
        preds = torch.argmax(logits, dim=-1)[0]
        confs = probs.max(dim=-1).values[0]

        drug_words = []
        dosage_words = []
        qty_words = []
        usage_words = []
        instruction_words = []
        max_conf = 0.0

        # Lấy nhãn của từ dựa trên subword đầu tiên (khi word_map >= 0)
        # Bỏ qua '_' do underthesea sinh ra
        for idx, wid in enumerate(word_map):
            if wid >= 0:
                raw_word = words[wid].replace('_', ' ')
                label = self._get_label(preds[idx].item())
                if label in ("B-DRUG", "I-DRUG"):
                    drug_words.append(raw_word)
                    max_conf = max(max_conf, confs[idx].item())
                elif label in ("B-DOSAGE", "I-DOSAGE"):
                    dosage_words.append(raw_word)
                elif label in ("B-QTY", "I-QTY"):
                    qty_words.append(raw_word)
                elif label in ("B-USAGE", "I-USAGE"):
                    usage_words.append(raw_word)
                else:
                    instruction_words.append(raw_word)

        drug_name = " ".join(drug_words).strip()
        dosage = " ".join(dosage_words).strip()
        qty_extracted = " ".join(qty_words).strip()
        usage_extracted = " ".join(usage_words).strip()

        # Combine extracted dosage into drug_name if not already present
        if dosage and dosage not in drug_name:
            drug_name = f"{drug_name} {dosage}".strip()

        instruction = usage_extracted or " ".join(instruction_words).strip()

        return drug_name, instruction, max_conf

    def classify(self, ocr_blocks, **kwargs):
        """
        Classify OCR text blocks as drugname or other and extract structured info.
        Hỗ trợ định dạng v2: STT | Nội dung | Số lượng | Đơn vị

        Input:  list of dicts [{text, label, box}, ...]
        Output: list of dicts [{text, label, confidence, box, extracted_info}, ...]
                with label = "drugname" or "other"
        """
        results = []
        for block in ocr_blocks:
            full_text = block.get("text", "")
            bbox = block.get("bbox") or block.get("box", [0, 0, 0, 0])

            # Khởi tạo giá trị mặc định
            stt = ""
            drug_name = ""
            instruction = ""
            qty = ""
            unit = ""
            is_drug = False
            conf = 0.0

            # Phân tách theo dấu " | " để bóc cấu trúc (nếu có form chuẩn)
            parts = [p.strip() for p in full_text.split(" | ")]

            if len(parts) >= 3:
                # Dòng chuẩn format V2 có đủ chia cắt: STT | Nội dung | SL | Đơn vị
                stt = parts[0]
                if len(parts) >= 4:
                    content_str = " ".join(parts[1:-2]) # Đề phòng nội dung bị dính char |
                    qty = parts[-2]
                    unit = parts[-1]
                else:
                    content_str = parts[1]
                    qty = parts[2]

                # Chạy NER chỉ trên phần Nội dung để bóc Tên thuốc vs Hướng dẫn
                drug_name, instruction, conf = self._extract_drug_and_instruction(content_str)
                is_drug = bool(drug_name)

            else:
                # Dòng text thường (không theo form V2) -> Tách tất cả từ text
                drug_name, instruction, conf = self._extract_drug_and_instruction(full_text)
                is_drug = bool(drug_name)
                # Fallback lấy STT bằng regex (giống cũ)
                m = STT_REGEX.match(full_text)
                if m:
                    stt = m.group(1).strip()

            # Đè lại text bằng phần Tên Thuốc để Bước 5 (Tra cứu) chỉ dùng nó đi tìm kiếm
            # Phần văn bản gốc sẽ được lưu trong 'original_text'
            final_text = drug_name if is_drug else full_text

            results.append({
                "original_text": full_text,     # Giữ lại đoạn text gốc STT | Drug | Qty
                "text": final_text,             # Quan trọng: Ghi đè text = drug_name để DrugLookup chuẩn
                "label": "drugname" if is_drug else "other",
                "confidence": round(conf, 4),
                "bbox": bbox,
                "extracted": {
                    "stt": stt,
                    "drug_name": drug_name,
                    "instruction": instruction,
                    "quantity": qty,
                    "unit": unit
                }
            })

        return results
