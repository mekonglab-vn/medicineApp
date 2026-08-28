"""
Bước 2: Fine-tune PhoBERT cho NER (Named Entity Recognition).
Chạy trên Google Colab GPU.

Hướng dẫn:
1. Upload file này + train.json + test.json lên Colab
2. Cài thư viện: !pip install transformers datasets seqeval accelerate
3. Chạy: !python train_ner.py
"""
import json
import numpy as np
import os
from datasets import Dataset, DatasetDict
from transformers import (
    AutoTokenizer,
    AutoModelForTokenClassification,
    TrainingArguments,
    Trainer,
    DataCollatorForTokenClassification,
)
from seqeval.metrics import (
    classification_report,
    f1_score,
    precision_score,
    recall_score,
)

# === CẤU HÌNH ===
MODEL_NAME = "vinai/phobert-base-v2"
LABEL_LIST = ["O", "B-DRUG", "I-DRUG"]
label2id = {lab: i for i, lab in enumerate(LABEL_LIST)}
id2label = {i: lab for i, lab in enumerate(LABEL_LIST)}

# Tự động tìm data (hỗ trợ cả local và Colab)
def find_data_path(filename):
    candidates = [
        filename,
        f"data/ner_dataset/{filename}",
        f"/content/{filename}",
        f"/content/data/ner_dataset/{filename}",
    ]
    for p in candidates:
        if os.path.exists(p):
            return p
    raise FileNotFoundError(
        f"Không tìm thấy {filename}!\n"
        f"Đã tìm ở: {candidates}\n"
        f"Hãy upload file vào đúng vị trí."
    )


TRAIN_PATH = find_data_path("train.json")
TEST_PATH = find_data_path("test.json")
print(f"  Train data: {TRAIN_PATH}")
print(f"  Test data:  {TEST_PATH}")

OUTPUT_DIR = "phobert_ner_output"
MODEL_DIR = "phobert_ner_model"

# Hyperparameters
NUM_EPOCHS = 15
BATCH_SIZE = 16
LEARNING_RATE = 2e-5
MAX_LENGTH = 256


# === 1. LOAD DATA ===
def load_json_dataset(path):
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    return Dataset.from_dict({
        "tokens": [s["tokens"] for s in data],
        "ner_tags": [
            [label2id[lab] for lab in s["ner_tags"]]
            for s in data
        ],
    })


print("Loading data...")
train_ds = load_json_dataset(TRAIN_PATH)
test_ds = load_json_dataset(TEST_PATH)
ds = DatasetDict({"train": train_ds, "test": test_ds})
print(f"  Train: {len(train_ds)} samples")
print(f"  Test:  {len(test_ds)} samples")


# === 2. TOKENIZER + SUBWORD ALIGNMENT ===
print(f"\nLoading tokenizer: {MODEL_NAME}...")
tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)


def tokenize_and_align(examples):
    """
    PhoBERT dùng slow tokenizer (không có word_ids()).
    Phải tự build word→subword mapping thủ công:
    1. Tokenize từng word riêng lẻ
    2. Nối các subwords lại
    3. Gán nhãn: subword đầu = nhãn gốc, subword sau = -100
    """
    all_input_ids = []
    all_attention_mask = []
    all_labels = []

    for idx in range(len(examples["tokens"])):
        words = examples["tokens"][idx]
        tags = examples["ner_tags"][idx]

        # Tokenize từng word → lấy subword ids (bỏ [CLS]/[SEP])
        word_subwords = []
        for word in words:
            encoded = tokenizer.encode(word, add_special_tokens=False)
            if not encoded:
                encoded = [tokenizer.unk_token_id]
            word_subwords.append(encoded)

        # Nối tất cả subwords + thêm [CLS] đầu, [SEP] cuối
        input_ids = [tokenizer.cls_token_id]
        label_ids = [-100]  # [CLS] → bỏ qua

        for word_idx, subwords in enumerate(word_subwords):
            if len(input_ids) + len(subwords) + 1 > MAX_LENGTH:
                break  # Truncate
            for j, sw in enumerate(subwords):
                input_ids.append(sw)
                if j == 0:
                    # Subword đầu tiên → nhận nhãn gốc
                    label_ids.append(tags[word_idx])
                else:
                    # Subword tiếp theo → bỏ qua
                    label_ids.append(-100)

        input_ids.append(tokenizer.sep_token_id)
        label_ids.append(-100)  # [SEP] → bỏ qua

        attention_mask = [1] * len(input_ids)

        all_input_ids.append(input_ids)
        all_attention_mask.append(attention_mask)
        all_labels.append(label_ids)

    return {
        "input_ids": all_input_ids,
        "attention_mask": all_attention_mask,
        "labels": all_labels,
    }


print("Tokenizing...")
tokenized_ds = ds.map(
    tokenize_and_align, batched=True,
    remove_columns=ds["train"].column_names
)
print(f"  Train tokens: {len(tokenized_ds['train'])}")
print(f"  Test tokens:  {len(tokenized_ds['test'])}")


# === 3. METRICS ===
def compute_metrics(eval_pred):
    logits, labels = eval_pred
    preds = np.argmax(logits, axis=-1)

    true_labels = []
    true_preds = []

    for pred_seq, label_seq in zip(preds, labels):
        true_label = []
        true_pred = []
        for p, lab in zip(pred_seq, label_seq):
            if lab != -100:
                true_label.append(id2label[lab])
                true_pred.append(id2label[p])
        true_labels.append(true_label)
        true_preds.append(true_pred)

    report = classification_report(true_labels, true_preds)
    print(f"\n{report}")

    return {
        "precision": precision_score(true_labels, true_preds),
        "recall": recall_score(true_labels, true_preds),
        "f1": f1_score(true_labels, true_preds),
    }


# === 4. MODEL ===
print(f"\nLoading model: {MODEL_NAME}...")
model = AutoModelForTokenClassification.from_pretrained(
    MODEL_NAME,
    num_labels=len(LABEL_LIST),
    label2id=label2id,
    id2label=id2label,
)
total_params = sum(p.numel() for p in model.parameters())
print(f"  Model params: {total_params / 1e6:.1f}M")


# === 5. TRAINING ===
training_args = TrainingArguments(
    output_dir=OUTPUT_DIR,
    num_train_epochs=NUM_EPOCHS,
    per_device_train_batch_size=BATCH_SIZE,
    per_device_eval_batch_size=BATCH_SIZE * 2,
    learning_rate=LEARNING_RATE,
    weight_decay=0.01,
    eval_strategy="epoch",
    save_strategy="epoch",
    load_best_model_at_end=True,
    metric_for_best_model="f1",
    logging_steps=50,
    fp16=True,
    report_to="none",
)

trainer = Trainer(
    model=model,
    args=training_args,
    train_dataset=tokenized_ds["train"],
    eval_dataset=tokenized_ds["test"],
    processing_class=tokenizer,
    data_collator=DataCollatorForTokenClassification(tokenizer),
    compute_metrics=compute_metrics,
)

print(f"\n{'=' * 60}")
print("  BẮT ĐẦU TRAINING")
print(f"  Epochs: {NUM_EPOCHS}, Batch: {BATCH_SIZE}, LR: {LEARNING_RATE}")
print("=" * 60 + "\n")

trainer.train()


# === 6. ĐÁNH GIÁ CUỐI CÙNG ===
print("\n" + "=" * 60)
print(f"  KẾT QUẢ TRÊN TẬP TEST ({len(test_ds)} đơn thuốc)")
print("=" * 60)

results = trainer.evaluate()
p = results['eval_precision']
r = results['eval_recall']
f = results['eval_f1']

print(f"  Precision: {p:.4f} ({p:.1%})")
print(f"  Recall:    {r:.4f} ({r:.1%})")
print(f"  F1-Score:  {f:.4f} ({f:.1%})")
print()

if f >= 0.90:
    print("  ✅ F1 >= 0.90 → Model ĐẠT CHUẨN!")
elif f >= 0.80:
    print("  ⚠️ F1 0.80-0.90 → Dùng được, cần cải thiện.")
else:
    print("  ❌ F1 < 0.80 → Cần điều chỉnh.")


# === 7. LƯU MODEL ===
trainer.save_model(MODEL_DIR)
tokenizer.save_pretrained(MODEL_DIR)

config_info = {
    "model_name": MODEL_NAME,
    "labels": LABEL_LIST,
    "label2id": label2id,
    "id2label": {str(k): v for k, v in id2label.items()},
    "epochs": NUM_EPOCHS,
    "eval_f1": f,
    "eval_precision": p,
    "eval_recall": r,
    "train_samples": len(train_ds),
    "test_samples": len(test_ds),
}
with open(os.path.join(MODEL_DIR, "training_config.json"), "w") as cfg:
    json.dump(config_info, cfg, indent=2)

print(f"\n  💾 Model saved to: {MODEL_DIR}/")
print(f"  📦 Tải thư mục '{MODEL_DIR}/' về máy local.")
print(f"\n  Files trong {MODEL_DIR}/:")
for f_name in sorted(os.listdir(MODEL_DIR)):
    size = os.path.getsize(os.path.join(MODEL_DIR, f_name))
    if size > 1024 * 1024:
        print(f"    {f_name} ({size / 1024 / 1024:.1f} MB)")
    else:
        print(f"    {f_name} ({size / 1024:.1f} KB)")
