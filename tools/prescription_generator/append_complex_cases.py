import json
import random
import os
from datetime import datetime, timedelta

def append_complex_cases():
    # 1. Load Long Data Template
    with open("long_data.json", "r", encoding="utf-8") as f:
        long_data = json.load(f)
    template = long_data["prescriptions"][0]
    
    # 2. Load Target Sample Data
    target_file = "generated_sample_data.json"
    if os.path.exists(target_file):
        with open(target_file, "r", encoding="utf-8") as f:
            target_data = json.load(f)
    else:
        target_data = {"prescriptions": []}
        
    current_max_id = max([p["id"] for p in target_data["prescriptions"]]) if target_data["prescriptions"] else 0
    
    # 3. Generate 10 Complex Cases
    new_cases = []
    print(f"Generating 10 complex cases based on template: {template['patient']['name']}")
    
    for i in range(10):
        new_case = template.copy()
        new_case["id"] = current_max_id + i + 1
        
        # Randomize items to avoid duplicates
        new_case["prescription_code"] = f"25{random.randint(800000, 999999)}"
        new_case["barcode_bottom"] = f"0000{new_case['id']:08d}"
        
        # Keep Patient Name mostly same but maybe vary ID slightly? 
        # Requirement says "add 10 patients... complex diagnosis". 
        # Let's keep the name "LÊ VĂN TRẬN" as requested template or vary names?
        # "thêm 10 bệnh nhân có bệnh án chuẩn đoán phức tạp" -> imply different patients
        # I will randomize the name slightly to distinct them
        last_names = ["LÊ", "NGUYỄN", "TRẦN", "PHẠM"]
        middle_names = ["VĂN", "HỮU", "ĐỨC"]
        first_names = ["TRẬN", "HÙNG", "MẠNH", "CƯỜNG", "THẮNG"]
        new_case["patient"] = template["patient"].copy()
        new_case["patient"]["name"] = f"{random.choice(last_names)} {random.choice(middle_names)} {random.choice(first_names)}"
        
        # Randomize Date: Dec 2025 to Dec 2026
        start_date = datetime(2025, 12, 1)
        end_date = datetime(2026, 12, 31)
        delta_days = (end_date - start_date).days
        random_days = random.randint(0, delta_days)
        today = start_date + timedelta(days=random_days)
        
        # Calculate follow up date based on patient logic or random
        # Complex cases usually 28 days
        follow_up_days = 28
        follow_up_date = (today + timedelta(days=follow_up_days)).strftime("%d/%m/%Y")
        
        new_case["prescription_date"] = today.strftime("ngày %d tháng %m năm %Y")
        new_case["follow_up_date"] = follow_up_date
        new_case["duration_days"] = follow_up_days
        
        # Remove Hospital field if exists (as we standardized on removing it)
        if "hospital" in new_case:
            del new_case["hospital"]
        
        new_cases.append(new_case)
        
    # 4. Append
    target_data["prescriptions"].extend(new_cases)
    
    # 5. Save
    with open(target_file, "w", encoding="utf-8") as f:
        json.dump(target_data, f, ensure_ascii=False, indent=2)
        
    print(f"Success! Added 10 complex cases. Total records: {len(target_data['prescriptions'])}")

if __name__ == "__main__":
    append_complex_cases()
