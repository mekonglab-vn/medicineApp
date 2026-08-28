import json
import random
import os
import copy

class ErrorInjector:
    def __init__(self, input_file):
        with open(input_file, 'r', encoding='utf-8') as f:
            self.valid_data = json.load(f)
        self.errored_prescriptions = []

    def inject_quantity_errors(self, ratio=0.3):
        """Inject errors: x10 quantity, wrong unit, weird typos"""
        data = copy.deepcopy(self.valid_data)
        count = 0
        
        for p in data["prescriptions"]:
            if random.random() < ratio:
                if not p["medications"]: continue
                target_med = random.choice(p["medications"])
                
                error_type = random.choice(["x10", "x100", "wrong_unit", "missing_digit", "extra_zero"])
                
                if error_type == "x10":
                    if target_med["quantity"] < 100:
                        target_med["quantity"] = target_med["quantity"] * 10
                        p["error_type"] = "wrong_quantity_x10"
                        p["error_description"] = f"Số lượng thuốc {target_med['brand_name']} gấp 10 lần bình thường"
                
                elif error_type == "x100":
                    if target_med["quantity"] < 10:
                        target_med["quantity"] = target_med["quantity"] * 100
                        p["error_type"] = "wrong_quantity_x100"
                        p["error_description"] = f"Số lượng thuốc {target_med['brand_name']} gấp 100 lần (lỗi nhập liệu)"

                elif error_type == "wrong_unit":
                    original_unit = target_med["unit"]
                    # Priority Error: Unit Swap Logic
                    swap_map = {
                        "Viên": ["Lọ", "Ống", "Bịch", "Chai"],
                        "Lọ": ["Viên", "Vỉ", "Ống"],
                        "Ống": ["Viên", "Chai", "Lọ"],
                        "Gói": ["Viên", "Chai", "Lọ"]
                    }
                    if original_unit in swap_map:
                        new_unit = random.choice(swap_map[original_unit])
                    else:
                        new_unit = "Viên" # Default fallback
                        
                    target_med["unit"] = new_unit
                    p["error_type"] = "wrong_unit"
                    p["error_description"] = f"Sai đơn vị tính nghiêm trọng: {original_unit} -> {new_unit}"
                
                elif error_type == "missing_digit":
                     # e.g. 28 -> 8
                     s_qty = str(target_med["quantity"])
                     if len(s_qty) > 1:
                         target_med["quantity"] = int(s_qty[1:])
                         p["error_type"] = "missing_digit"
                         p["error_description"] = f"Số lượng thiếu chữ số: {s_qty} -> {target_med['quantity']}"

                elif error_type == "extra_zero":
                    # e.g. 2 -> 20
                    target_med["quantity"] = int(str(target_med["quantity"]) + "0")
                    p["error_type"] = "extra_zero"
                    p["error_description"] = f"Số lượng thừa số 0: {target_med['quantity']}"
                    
                count += 1
                self.errored_prescriptions.append(p)
        
        print(f"Generated {count} quantity/unit errors")

    def inject_medical_errors(self, ratio=0.4):
        """Inject errors: Interactions, Specialty Contraindications, Overdose"""
        data = copy.deepcopy(self.valid_data)
        count = 0
        
        # DEFINITION OF DANGEROUS DRUGS FOR INJECTION
        bad_scenarios = [
            # 1. CONTRAINDICATIONS
            {
                "trigger_diag": ["J44", "J45"], # Asthma/COPD
                "drug": {"generic_name": "Propranolol", "brand_name": "Dorocardyl 40mg", "dosage": "40mg", "unit": "Viên", "instructions": "Ngày uống 2 viên"},
                "desc": "Chống chỉ định: Kê Beta-blocker (Propranolol) cho bệnh nhân Hen/COPD"
            },
            {
                "trigger_diag": ["K21", "K25", "K29"], # Gastric Ulcer/GERD
                "drug": {"generic_name": "Prednisolone", "brand_name": "Prednisolone 5mg", "dosage": "5mg", "unit": "Viên", "instructions": "Ngày uống 3 viên"},
                "desc": "Thận trọng: Kê Corticoid (Prednisolone) cho bệnh nhân viêm loét dạ dày"
            },
            {
                "trigger_diag": ["H40", "H04"], # Glaucoma/Eye
                "drug": {"generic_name": "Prednisolone Acetate", "brand_name": "Pred Forte", "dosage": "1%", "unit": "Lọ", "instructions": "Nhỏ mắt 4 lần/ngày"},
                "desc": "Chống chỉ định tuyệt đối: Kê Corticoid nhỏ mắt cho bệnh nhân Glaucoma/Mắt"
            },
            
            # 2. DRUG INTERACTIONS (Priority)
            {
                "force_pair": True,
                "drug1": {"generic_name": "Warfarin", "brand_name": "Coumadin", "dosage": "5mg", "unit": "Viên", "instructions": "Ngày uống 1 viên"},
                "drug2": {"generic_name": "Aspirin", "brand_name": "Aspirin 81mg", "dosage": "81mg", "unit": "Viên", "instructions": "Ngày uống 1 viên"},
                "desc": "Tương tác thuốc nghiêm trọng: Warfarin + Aspirin (Nguy cơ xuất huyết nội)"
            },
             {
                "force_pair": True,
                "drug1": {"generic_name": "Simvastatin", "brand_name": "Zocor", "dosage": "20mg", "unit": "Viên", "instructions": "Ngày uống 1 viên tối"},
                "drug2": {"generic_name": "Clarithromycin", "brand_name": "Klacid", "dosage": "500mg", "unit": "Viên", "instructions": "Ngày uống 2 viên"},
                "desc": "Tương tác thuốc nghiêm trọng: Simvastatin + Clarithromycin (Tiêu cơ vân)"
            },
            {
                "force_pair": True,
                "drug1": {"generic_name": "Sildenafil", "brand_name": "Viagra", "dosage": "50mg", "unit": "Viên", "instructions": "Uống khi cần"},
                "drug2": {"generic_name": "Isosorbide Mononitrate", "brand_name": "Imdur", "dosage": "60mg", "unit": "Viên", "instructions": "Ngày uống 1 viên sáng"},
                "desc": "Tương tác thuốc CHẾT NGƯỜI: Nitrat + Viagra (Tụt huyết áp trụy mạch)"
            },
            {
                "force_pair": True,
                "drug1": {"generic_name": "Spironolactone", "brand_name": "Verospiron", "dosage": "25mg", "unit": "Viên", "instructions": "Ngày uống 1 viên"},
                "drug2": {"generic_name": "Kalium Chloride", "brand_name": "Kaleorid", "dosage": "600mg", "unit": "Viên", "instructions": "Ngày uống 2 viên"},
                "desc": "Tương tác thuốc: Lợi tiểu giữ Kali + Bổ sung Kali (Tăng Kali máu gây ngưng tim)"
            },
            
            # 3. AGE / SPECIALTY WARNINGS
            {
                "trigger_age_min": 0, "trigger_age_max": 12,
                "drug": {"generic_name": "Ciprofloxacin", "brand_name": "Ciprobay", "dosage": "500mg", "unit": "Viên", "instructions": "Ngày uống 2 viên"},
                "desc": "Cảnh báo tuổi: Kê Quinolone (Ciprofloxacin) cho trẻ em < 12 tuổi"
            },
             {
                "trigger_age_min": 0, "trigger_age_max": 16,
                 "drug": {"generic_name": "Doxycycline", "brand_name": "Doxycycline", "dosage": "100mg", "unit": "Viên", "instructions": "Ngày uống 1 viên"},
                "desc": "Cảnh báo tuổi: Kê Doxycycline cho trẻ em (nguy cơ hỏng men răng)"
            }
        ]

        for p in data["prescriptions"]:
            if random.random() < ratio:
                diagnosis_code = p["diagnosis"]
                patient_age = p["patient"]["age"]
                
                injected = False
                scenario = random.choice(bad_scenarios)
                
                # Check Logic
                if "trigger_diag" in scenario:
                    if any(code in diagnosis_code for code in scenario["trigger_diag"]):
                        drug = scenario["drug"]
                        drug["quantity"] = 10
                        p["medications"].append(drug)
                        p["error_type"] = "contraindication"
                        p["error_description"] = scenario["desc"]
                        injected = True
                        
                elif "trigger_age_min" in scenario:
                    if scenario["trigger_age_min"] <= patient_age <= scenario["trigger_age_max"]:
                        drug = scenario["drug"]
                        drug["quantity"] = 10
                        p["medications"].append(drug)
                        p["error_type"] = "age_warning"
                        p["error_description"] = scenario["desc"]
                        injected = True
                
                elif "force_pair" in scenario:
                    # Inject both drugs regardless of condition to simulate error
                    # Only do this if list isn't too long already
                    if len(p["medications"]) < 8:
                        d1 = scenario["drug1"]
                        d1["quantity"] = 10
                        d2 = scenario["drug2"]
                        d2["quantity"] = 10
                        p["medications"].append(d1)
                        p["medications"].append(d2)
                        p["error_type"] = "drug_interaction"
                        p["error_description"] = scenario["desc"]
                        injected = True

                if injected:
                    count += 1
                    self.errored_prescriptions.append(p)
                    
        print(f"Generated {count} complex medical errors")

    def save(self, output_file):
        for i, p in enumerate(self.errored_prescriptions):
            p["id"] = i + 1
        data = {"prescriptions": self.errored_prescriptions}
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        print(f"Saved {len(self.errored_prescriptions)} errors to {output_file}")

if __name__ == "__main__":
    injector = ErrorInjector("generated_sample_data.json") # Input from new sample data
    injector.inject_quantity_errors(ratio=0.5)
    injector.inject_medical_errors(ratio=0.6) 
    injector.save("generated_error_data.json") # Output to error data file
