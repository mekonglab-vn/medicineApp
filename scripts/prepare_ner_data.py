"""
Bước 1: Chuyển VAIPE JSON → HuggingFace NER Dataset.
Chạy: python scripts/prepare_ner_data.py
Output: data/ner_dataset/ (train.json, test.json)
"""
import json
import os
import re
from pathlib import Path
from collections import Counter

# === CẤU HÌNH ===
VAIPE_BASE = "VAIPE_Full/content/dataset"
TRAIN_DIR = f"{VAIPE_BASE}/train/prescription/labels"
TEST_DIR  = f"{VAIPE_BASE}/test/prescription/labels"
OUTPUT_DIR = "data/ner_dataset"

# Regex cho STT prefix: "1)", "2.", "3 ", "10-"
STT_REGEX = re.compile(r'^(\d+(?:[\)\.\-]|(?=\s))\s*)(.*)')

try:
    from underthesea import word_tokenize
    HAS_UNDERTHESEA = True
    print("✅ underthesea loaded")
except ImportError:
    HAS_UNDERTHESEA = False
    print("⚠ underthesea not found, using space-split only")


def convert_file(json_path):
    """
    Chuyển 1 file JSON VAIPE thành 1 sample NER.

    Mỗi block text trở thành 1 hoặc nhiều token.
    Label mapping: drugname → B-DRUG/I-DRUG, còn lại → O.
    """
    with open(json_path, "r", encoding="utf-8") as f:
        blocks = json.load(f)

    # Sắp xếp blocks theo vị trí: trên→dưới, trái→phải
    blocks.sort(key=lambda b: (b["box"][1], b["box"][0]))

    tokens = []   # Danh sách từng từ
    labels = []   # Nhãn BIO tương ứng

    for block in blocks:
        text = block.get("text", "").strip()
        label = block.get("label", "other").lower()

        if not text:
            continue

        # Tách tiền tố Số Thứ Tự (STT) để model không học STT là thuốc
        # Hỗ trợ: "1) Thuốc", "2. Thuốc", "3 Thuốc" (bảng)
        m = STT_REGEX.match(text)
        if m:
            prefix = m.group(1).strip()
            main_part = m.group(2).strip()
        else:
            prefix = ""
            main_part = text

        # Tách từ tiếng Việt cho phần main_part
        # "Hoạt huyết dưỡng não" → "Hoạt_huyết_dưỡng não"
        if HAS_UNDERTHESEA and main_part:
            main_part = word_tokenize(main_part, format="text")

        prefix_tokens = prefix.split()
        main_tokens = main_part.split()

        # Gán nhãn cho prefix (luôn là O)
        for tok in prefix_tokens:
            tokens.append(tok)
            labels.append("O")

        # Gán nhãn cho phần chữ chính
        for i, word in enumerate(main_tokens):
            tokens.append(word)
            if label == "drugname":
                labels.append("B-DRUG" if i == 0 else "I-DRUG")
            else:
                labels.append("O")

    return {"tokens": tokens, "ner_tags": labels}


def convert_dir(label_dir, split_name):
    """Chuyển tất cả file trong 1 thư mục."""
    samples = []
    json_files = sorted(Path(label_dir).glob("*.json"))

    for jf in json_files:
        try:
            sample = convert_file(str(jf))
            if len(sample["tokens"]) > 0:
                sample["id"] = jf.stem
                samples.append(sample)
        except Exception as e:
            print(f"⚠ Skip {jf.name}: {e}")

    print(f"  {split_name}: {len(samples)} samples, "
          f"avg {sum(len(s['tokens']) for s in samples)//len(samples)} tokens/sample")
    return samples


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    print("Converting VAIPE → NER format...")
    train = convert_dir(TRAIN_DIR, "train")
    test  = convert_dir(TEST_DIR,  "test")

    # Thống kê nhãn
    all_labels = []
    for s in train:
        all_labels.extend(s["ner_tags"])
    counts = Counter(all_labels)
    print(f"\n  Label distribution (train):")
    for label, count in counts.most_common():
        print(f"    {label}: {count} ({count/len(all_labels):.1%})")

    # Lưu ra JSON
    for name, data in [("train", train), ("test", test)]:
        path = os.path.join(OUTPUT_DIR, f"{name}.json")
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        print(f"  💾 Saved: {path} ({len(data)} samples)")

    # === CHECKPOINT KIỂM CHỨNG ===
    print("\n" + "=" * 60)
    print("  KIỂM CHỨNG: 3 mẫu đầu tiên")
    print("=" * 60)
    for sample in train[:3]:
        print(f"\n  📄 {sample['id']}:")
        for tok, lbl in zip(sample["tokens"][:20], sample["ner_tags"][:20]):
            marker = "💊" if "DRUG" in lbl else "  "
            print(f"    {marker} {tok:30s} → {lbl}")
        if len(sample["tokens"]) > 20:
            print(f"    ... ({len(sample['tokens'])} tokens total)")
    
    # Thống kê thêm
    drug_count = sum(1 for s in train for t in s["ner_tags"] if t == "B-DRUG")
    print(f"\n  📊 Total drug entities (B-DRUG): {drug_count}")
    print(f"  📊 Avg drugs per prescription: {drug_count / len(train):.1f}")


if __name__ == "__main__":
    main()
