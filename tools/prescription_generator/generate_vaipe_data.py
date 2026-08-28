"""
generate_vaipe_data.py — Tạo dữ liệu đơn thuốc dùng thuốc VAIPE.

Inject thuốc từ VAIPE dataset vào data_generator format,
rồi dùng generate_prescription.py để in đơn thuốc DOCX/PDF.

Usage:
    python generate_vaipe_data.py --count 200
    # Sau đó: python generate_prescription.py --data vaipe_prescriptions.json --all
"""
import json
import os
import sys
import re
import random
from datetime import datetime, timedelta

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VAIPE_KB = os.path.join(ROOT, "data", "vaipe_drugs_kb.json")

# ── Load VAIPE drugs ─────────────────────────────────────
with open(VAIPE_KB, encoding="utf-8") as f:
    VAIPE_DRUGS = json.load(f)

print(f"Loaded {len(VAIPE_DRUGS)} VAIPE drugs")

# ── Build instruction templates ──────────────────────────
INSTRUCTIONS_TEMPLATES = [
    "Ngày uống {n} lần, mỗi lần 1 viên",
    "Uống {n} viên/ngày sau ăn",
    "Ngày uống {n} viên (sáng{extra})",
    "Sáng uống {n} viên sau ăn",
    "Ngày uống {n} lần, mỗi lần 1 viên sau ăn",
    "Uống {n} viên khi đau/sốt, cách mỗi 4-6h",
    "Ngày {n} lần, mỗi lần 1 viên trước ăn",
    "Trưa uống {n} viên sau ăn",
]

UNITS = ["Viên", "Viên", "Viên", "Gói", "Ống", "Lọ",
         "Viên sủi", "Viên nang"]

# ── Build VAIPE drug list in data_generator format ───────
def build_vaipe_drug_entry(drug_info):
    """
    Convert a VAIPE drug KB entry to data_generator medication format.

    Input:  {"id": 64, "name": "Hoat-Huyet-Duong-Nao",
             "brand": "HOẠT HUYẾT DƯỠNG NÃO QN", "dosage": "150mg", ...}
    Output: {"generic_name": "Hoat-Huyet-Duong-Nao",
             "brand_name": "HOẠT HUYẾT DƯỠNG NÃO QN",
             "dosage": "150mg", "unit": "Viên",
             "quantity": 28, "instructions": "...",
             "vaipe_id": 64}
    """
    name = drug_info["name"]
    brand = drug_info["brand"]
    dosage = drug_info.get("dosage", "")

    # Clean brand
    brand = re.sub(r'\s+', ' ', brand).strip()
    if not brand:
        brand = name.replace("-", " ")

    # Clean generic name: "Hoat-Huyet-Duong-Nao" -> "Hoạt Huyết Dưỡng Não"
    # Use first sample text to get Vietnamese name if available
    sample_texts = drug_info.get("sample_texts", [])
    generic_display = name.replace("-", " ")

    # Try to extract a cleaner generic from sample text
    if sample_texts:
        sample = sample_texts[0]
        # Remove prefix like "1) "
        sample = re.sub(r'^\d+[).\s]+', '', sample).strip()
        # If sample has parentheses, use the part before ()
        paren = re.match(r'^(.+?)\s*\(', sample)
        if paren:
            generic_display = paren.group(1).strip()
        else:
            # Use sample but remove dosage part
            generic_display = re.sub(
                r'\s+\d+(?:[.,]\d+)?(?:mg|g|ml|mcg|ui).*$',
                '', sample, flags=re.I
            ).strip()

    if not generic_display:
        generic_display = name.replace("-", " ")

    # Random instruction and quantity
    n = random.choice([1, 2, 2, 3])
    extra = ", tối" if n >= 2 else ""
    instr = random.choice(INSTRUCTIONS_TEMPLATES).format(
        n=n, extra=extra
    )
    unit = random.choice(UNITS)
    qty = random.choice([7, 10, 14, 20, 28, 30, 60])
    if unit in ("Lọ", "Tuýp", "Ống"):
        qty = random.randint(1, 3)

    return {
        "generic_name": generic_display,
        "brand_name": brand,
        "dosage": dosage if dosage else "Tab",
        "unit": unit,
        "quantity": qty,
        "instructions": instr,
        "vaipe_id": drug_info["id"],
    }


# ── Patient / Doctor / Hospital generators ───────────────
# (same as data_generator.py but simplified)

LAST_NAMES = [
    "Nguyễn", "Trần", "Lê", "Phạm", "Hoàng", "Huỳnh",
    "Phan", "Vũ", "Võ", "Đặng", "Bùi", "Đỗ", "Hồ",
    "Ngô", "Dương", "Lý",
]
MIDDLE_NAMES = [
    "Văn", "Thị", "Hữu", "Đức", "Minh", "Thu",
    "Ngọc", "Thanh", "Quang", "Mạnh", "Kim", "Xuân",
]
FIRST_NAMES = [
    "An", "Bình", "Cường", "Dung", "Em", "Giang", "Hải",
    "Lan", "Mai", "Oanh", "Khoa", "Phúc", "Tâm",
    "Thảo", "Hùng", "Sơn", "Tùng", "Trang",
]

DOCTORS = [
    {"name": "Nguyễn Văn A", "title": "BS.CKI"},
    {"name": "Trần Thị B", "title": "ThS.BS"},
    {"name": "Lê Vũ C", "title": "BS.CKII"},
    {"name": "Phạm Minh D", "title": "TS.BS"},
    {"name": "Hoàng Thị E", "title": "BS.CKI"},
    {"name": "Vũ Văn F", "title": "BS"},
    {"name": "Lê Thị Kim Đài", "title": "BS.CKI"},
    {"name": "Phan Văn K", "title": "ThS.BS"},
]

DIAGNOSES_ICD = [
    ("J00", "Viêm mũi họng cấp"),
    ("J20.9", "Viêm phế quản cấp"),
    ("I10", "Tăng huyết áp vô căn"),
    ("I25.1", "Bệnh tim thiếu máu cục bộ mạn"),
    ("E11", "Đái tháo đường type 2"),
    ("E78.0", "Tăng cholesterol máu"),
    ("K21.9", "Trào ngược dạ dày-thực quản"),
    ("M17", "Thoái hóa khớp gối"),
    ("M54.5", "Đau thắt lưng"),
    ("G47.0", "Rối loạn giấc ngủ"),
    ("K73.9", "Viêm gan mạn tính"),
    ("Z95.4", "Sự có mặt của van tim thay thế"),
    ("H04.1", "Hội chứng khô mắt"),
    ("L20.9", "Viêm da cơ địa"),
]

ADDRESSES = [
    "Ấp 3, Xã Vị Thủy, TP Cần Thơ",
    "123 Nguyễn Huệ, Q.1, TP.HCM",
    "456 Trần Hưng Đạo, Hà Nội",
    "789 Lê Lợi, Đà Nẵng",
    "12 Đường CMT8, Cần Thơ",
    "34 Võ Văn Kiệt, Q.5, TP.HCM",
    "567 Nguyễn Trãi, Q.5, TP.HCM",
    "89 Lý Thường Kiệt, Hải Phòng",
]


def generate_patient():
    gender = random.choice(["Nam", "Nữ"])
    name = (
        f"{random.choice(LAST_NAMES)} "
        f"{random.choice(MIDDLE_NAMES)} "
        f"{random.choice(FIRST_NAMES)}"
    )
    if gender == "Nam" and "Thị" in name:
        name = name.replace("Thị", "Văn")
    elif gender == "Nữ" and "Văn" in name:
        name = name.replace("Văn", "Thị")

    age = random.randint(20, 85)
    return {
        "name": name.upper(),
        "age": age,
        "gender": gender,
        "address": random.choice(ADDRESSES),
        "insurance_code": f"DN{random.randint(4000000000, 9999999999)}",
    }


def generate_prescription(pres_id, all_drug_ids):
    """Generate one prescription using VAIPE drugs."""
    patient = generate_patient()
    doctor = random.choice(DOCTORS)

    # Random diagnosis
    n_diag = random.choices([1, 2, 3], weights=[0.5, 0.35, 0.15])[0]
    diags = random.sample(DIAGNOSES_ICD, min(n_diag, len(DIAGNOSES_ICD)))
    diag_str = "; ".join(f"{c}: {d}" for c, d in diags)

    # Pick random VAIPE drugs
    n_drugs = random.choices(
        [3, 4, 5, 6, 7], weights=[0.15, 0.25, 0.3, 0.2, 0.1]
    )[0]
    drug_ids = random.sample(all_drug_ids, min(n_drugs, len(all_drug_ids)))

    medications = []
    for did in drug_ids:
        did_str = str(did)
        if did_str not in VAIPE_DRUGS:
            continue
        med = build_vaipe_drug_entry(VAIPE_DRUGS[did_str])
        medications.append(med)

    # Date
    start = datetime(2025, 12, 1)
    end = datetime(2026, 12, 31)
    today = start + timedelta(days=random.randint(0, (end - start).days))
    follow_up = random.choice([7, 14, 28])
    follow_date = (today + timedelta(days=follow_up)).strftime("%d/%m/%Y")

    return {
        "id": pres_id,
        "patient": patient,
        "prescription_code": f"25{random.randint(100000, 999999)}",
        "diagnosis": diag_str,
        "doctor": doctor,
        "medications": medications,
        "follow_up_date": follow_date,
        "prescription_date": today.strftime("ngày %d tháng %m năm %Y"),
        "notes": "" if len(medications) <= 5 else
                 "Tái khám nhớ mang theo đơn thuốc này.",
        "lab_tests": "",
        "barcode_bottom": f"0000{pres_id:08d}",
        "duration_days": follow_up,
    }


def main():
    import argparse
    parser = argparse.ArgumentParser(
        description="Generate prescription data with VAIPE drugs"
    )
    parser.add_argument("--count", type=int, default=200)
    parser.add_argument(
        "--output", default="vaipe_prescriptions.json"
    )
    args = parser.parse_args()

    all_drug_ids = [int(k) for k in VAIPE_DRUGS.keys()]

    prescriptions = []
    for i in range(1, args.count + 1):
        pres = generate_prescription(i, all_drug_ids)
        prescriptions.append(pres)

    data = {"prescriptions": prescriptions}
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    # Stats
    total_meds = sum(len(p["medications"]) for p in prescriptions)
    drug_ids_used = set()
    for p in prescriptions:
        for m in p["medications"]:
            drug_ids_used.add(m.get("vaipe_id", -1))

    print(f"\nGenerated {args.count} prescriptions -> {args.output}")
    print(f"  Total medications: {total_meds}")
    print(f"  Unique VAIPE drug classes: {len(drug_ids_used)}")
    print(f"  Avg drugs/prescription: {total_meds/args.count:.1f}")
    print()
    print("Next steps:")
    print(f"  python generate_prescription.py "
          f"--data {args.output} --all "
          f"--output output/vaipe_prescriptions.docx")


if __name__ == "__main__":
    main()
