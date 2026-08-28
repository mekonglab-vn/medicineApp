import json
import random
import os
from datetime import datetime, timedelta

# ==============================================================================
# 1. MEDICAL KNOWLEDGE BASE (Cơ sở tri thức y khoa)
# ==============================================================================
class MedicalKnowledgeBase:
    def __init__(self):
        # Database về Bệnh (ICD-10 -> Tên -> Nhóm thuốc VAIPE)
        self.conditions = {
            # --- HÔ HẤP (Respiratory) ---
            "J00": { "code": "J00", "name": "Viêm mũi họng cấp", "types": ["Acute", "Pediatric", "Adult"], "drugs": ["Acefalgan_500mg", "Partamol_500mg", "Amoxicillin_250mg", "Vitamin_C_500mg", "Acetylcysteine"] },
            "J20.9": { "code": "J20.9", "name": "Viêm phế quản cấp", "types": ["Acute", "Adult", "Pediatric"], "drugs": ["Amoxicillin_500mg", "Cephalexin_500mg", "Acetylcysteine", "Halixol", "Panadol_500mg"] },
            "J44.9": { "code": "J44.9", "name": "Bệnh phổi tắc nghẽn mạn tính (COPD)", "types": ["Chronic", "Elderly"], "drugs": ["Acetylcysteine", "Halixol", "Hexinvon_8mg", "Medrol_4mg", "Flagyl_250mg"] },
            
            # --- TIM MẠCH (Cardiovascular) ---
            "I10": { "code": "I10", "name": "Tăng huyết áp vô căn", "types": ["Chronic", "Adult", "Elderly"], "drugs": ["Amlodipine_5mg", "Losartan_Boston_50mg", "Micardis_plus_40_12.5mg", "Enalapril_5mg", "Nifedipin_Hasan_20mg"] },
            "I25.1": { "code": "I25.1", "name": "Bệnh tim thiếu máu cục bộ mạn", "types": ["Chronic", "Elderly"], "drugs": ["Aspirin_81mg", "Amlodipine_5mg", "Losartan_Boston_50mg", "Carudxan_2mg", "Hoat_Huyet_Duong_Nao"] },
            "I63.9": { "code": "I63.9", "name": "Di chứng nhồi máu não", "types": ["Chronic", "Elderly", "Neuro"], "drugs": ["Aspirin_81mg", "Carudxan_2mg", "Hoat_Huyet_Duong_Nao", "Hoat_Huyet_Ich_Nao", "Piracetam_800mg"] },
            
            # --- NỘI TIẾT (Endocrine) ---
            "E11": { "code": "E11", "name": "Đái tháo đường type 2", "types": ["Chronic", "Adult", "Elderly"], "drugs": ["Glucofast_850mg", "Glucophage_500mg", "Glucophage_850mg", "Glumeform_850mg", "Savi_Acarbose_100"] },
            "E78.0": { "code": "E78.0", "name": "Tăng cholesterol máu thuần", "types": ["Chronic", "Adult", "Elderly"], "drugs": ["Amlodipine_5mg", "Losartan_Boston_50mg", "Glucofast_850mg", "Glucophage_500mg"] },

            # --- TIÊU HÓA (Gastrointestinal) ---
            "K21.9": { "code": "K21.9", "name": "Bệnh trào ngược dạ dày-thực quản (GERD)", "types": ["Chronic", "Acute", "Adult"], "drugs": ["Famotdin_40mg", "Kagasdine_20mg", "Normagut_250mg", "Omeprazole", "Prazopro_40mg"] },
            "K58.0": { "code": "K58.0", "name": "Hội chứng ruột kích thích (IBS)", "types": ["Chronic", "Adult"], "drugs": ["Famotdin_40mg", "Kagasdine_20mg", "Normagut_250mg", "Acefalgan_500mg"] },
            "K73.9": { "code": "K73.9", "name": "Viêm gan mạn tính", "types": ["Chronic", "Adult"], "drugs": ["France_Liver_Gold_Plus_Giai_Doc_Gan", "Heptonic_Forte", "LIVOLIN_FORTE", "Liverbil", "Silymarin"] },

            # --- CƠ XƯƠNG KHỚP (Musculoskeletal) ---
            "M17": { "code": "M17", "name": "Thoái hóa khớp gối", "types": ["Chronic", "Elderly"], "drugs": ["Alpha_Chymotrypsine", "Diclofenac_50mg", "Medrol_16mg", "Morif_7.5mg"] },
            "M54.5": { "code": "M54.5", "name": "Đau thắt lưng", "types": ["Acute", "Chronic", "Adult"], "drugs": ["Morif_7.5mg", "Medrol_4mg", "Diclofenac_50mg", "Partamol_500mg", "Vitamin_3B"] },
            
            # --- THẦN KINH (Neurology) ---
            "G40.9": { "code": "G40.9", "name": "Bệnh động kinh", "types": ["Chronic", "Adult", "Pediatric"], "drugs": ["Hoat_Huyet_Duong_Nao", "Hoat_Huyet_Ich_Nao", "Piracetam_800mg"] },
            "G43.9": { "code": "G43.9", "name": "Migraine", "types": ["Chronic", "Adult"], "drugs": ["Hoat_Huyet_Duong_Nao", "Piracetam_800mg", "Partamol_500mg"] },
            "G47.0": { "code": "G47.0", "name": "Rối loạn giấc ngủ", "types": ["Acute", "Adult", "Elderly"], "drugs": ["Hoat_Huyet_Duong_Nao", "Piracetam_800mg", "Vitamin_3B"] },
            
            # --- DA LIỄU (Dermatology) ---
            "L20.9": { "code": "L20.9", "name": "Viêm da cơ địa", "types": ["Chronic", "Pediatric", "Adult"], "drugs": ["Agilodin_10mg", "Loratadine_10mg", "Loreze_10mg", "Vitamin_C_500mg"] },
            "L70.0": { "code": "L70.0", "name": "Mụn trứng cá thông thường", "types": ["Chronic", "Adult"], "drugs": ["Flagyl_250mg", "Agilodin_10mg", "Loratadine_10mg"] },
            "B35.1": { "code": "B35.1", "name": "Nấm móng", "types": ["Chronic", "Adult"], "drugs": ["Flagyl_250mg", "Loratadine_10mg"] },
            
            # --- MẮT (Ophthalmology) ---
            "H10.1": { "code": "H10.1", "name": "Viêm kết mạc cấp", "types": ["Acute", "Pediatric", "Adult"], "drugs": ["Vitamin_C_500mg", "Vitamin_C_Vien_Sui", "Vina_AD"] },
            "H04.1": { "code": "H04.1", "name": "Hội chứng khô mắt", "types": ["Chronic", "Adult", "Elderly"], "drugs": ["Vitamin_C_500mg", "Vina_AD", "Rutin_C"] },
        }

        # Database về Thuốc — 105 VAIPE drug classes
        # Format giữ nguyên: {"brand": ..., "dosage": ..., "unit": ..., "instr": ...}
        self.drugs = {
            # --- Giảm đau / Hạ sốt ---
            "Acefalgan_500mg": [{"brand": "PARACETAMOL", "dosage": "500mg", "unit": "Viên", "instr": "Uống 1 viên khi đau/sốt, cách mỗi 4-6h"}],
            "Hapacol": [{"brand": "TYDOL PM", "dosage": "500mg", "unit": "Viên", "instr": "Uống 1 viên khi đau/sốt"}],
            "Panactol_500mg": [{"brand": "PANACTOL", "dosage": "500mg", "unit": "Viên", "instr": "Uống 1 viên khi đau/sốt, cách mỗi 4-6h"}],
            "Panadol_500mg": [{"brand": "MYPARA 500", "dosage": "500mg", "unit": "Viên", "instr": "Uống 1 viên khi đau/sốt"}],
            "Paracetamol_500mg": [{"brand": "PANACTOL", "dosage": "500mg", "unit": "Viên", "instr": "Uống 1 viên khi đau/sốt, cách mỗi 4-6h"}],
            "Partamol_500mg": [{"brand": "PARTAMOL TAB.", "dosage": "500mg", "unit": "Viên", "instr": "Uống 1 viên khi đau/sốt, cách mỗi 4-6h"}],
            "Tatanol_500mg_VBP": [{"brand": "MYPARA 500", "dosage": "500mg", "unit": "Viên", "instr": "Uống 1 viên khi đau/sốt"}],
            "Tydol_Pm": [{"brand": "TYDOL PM", "dosage": "500mg", "unit": "Viên", "instr": "Uống 1 viên khi đau/sốt, cách mỗi 4-6h"}],

            # --- Kháng sinh ---
            "Amoxicillin_250mg": [{"brand": "AMOXYCILIN", "dosage": "250mg", "unit": "Viên", "instr": "Ngày uống 3 viên sau ăn"}],
            "Amoxicillin_500mg": [{"brand": "AMOXICILLIN", "dosage": "500mg", "unit": "Viên", "instr": "Ngày uống 2 viên sau ăn (sáng, tối)"}],
            "Cephalexin_250mg": [{"brand": "FIRSTLEXIN", "dosage": "250mg", "unit": "Viên", "instr": "Ngày uống 3 viên sau ăn"}],
            "Cephalexin_500mg": [{"brand": "CEFACYL 500", "dosage": "500mg", "unit": "Viên", "instr": "Ngày uống 2 viên sau ăn"}],
            "Flagyl_250mg": [{"brand": "METRONIDAZOL", "dosage": "250mg", "unit": "Viên", "instr": "Ngày uống 3 viên sau ăn"}],
            "Hapenxin": [{"brand": "CEFACYL 500", "dosage": "0,5g", "unit": "Viên", "instr": "Ngày uống 2 viên sau ăn"}],
            "Moxacin_500mg": [{"brand": "NOVOXIM-500", "dosage": "0,5g", "unit": "Viên", "instr": "Ngày uống 2 viên sau ăn"}],

            # --- Tim mạch ---
            "Amlodipine_5mg": [{"brand": "KAVASDIN 5", "dosage": "5mg", "unit": "Viên", "instr": "Ngày uống 1 viên buổi sáng"}],
            "Aspirin_81mg": [{"brand": "ASPIRIN pH8", "dosage": "81mg", "unit": "Viên", "instr": "Ngày uống 1 viên sau ăn trưa"}],
            "Carudxan_2mg": [{"brand": "CARUDXAN", "dosage": "2mg", "unit": "Viên", "instr": "Ngày uống 1 viên buổi sáng"}],
            "Enalapril_5mg": [{"brand": "ENALAPRIL", "dosage": "5mg", "unit": "Viên", "instr": "Ngày uống 1 viên buổi sáng"}],
            "Enalapril_Stella_10mg": [{"brand": "RENAPRIL 5MG", "dosage": "5mg", "unit": "Viên", "instr": "Ngày uống 1 viên buổi sáng"}],
            "Losartan_Boston_50mg": [{"brand": "SAVILOSARTAN 50", "dosage": "50mg", "unit": "Viên", "instr": "Ngày uống 1 viên buổi sáng"}],
            "Micardis_plus_40_12.5mg": [{"brand": "HANGITOR PLUS", "dosage": "40mg+12,5mg", "unit": "Viên", "instr": "Ngày uống 1 viên buổi sáng"}],
            "Nifedipin_Hasan_20mg": [{"brand": "NIFEDIPIN T20 STADA RETARD", "dosage": "20mg", "unit": "Viên", "instr": "Ngày uống 1 viên buổi sáng"}],

            # --- Tiểu đường ---
            "Glucofast_850mg": [{"brand": "GLUCOFAST 850", "dosage": "850mg", "unit": "Viên", "instr": "Ngày uống 2 viên sau ăn (sáng, tối)"}],
            "Glucophage_500mg": [{"brand": "METFORMIN 500", "dosage": "500mg", "unit": "Viên", "instr": "Ngày uống 2 viên sau ăn"}],
            "Glucophage_850mg": [{"brand": "GLUCOFAST 850", "dosage": "850mg", "unit": "Viên", "instr": "Ngày uống 2 viên sau ăn"}],
            "Glumeform_850mg": [{"brand": "GLUCOFAST 850", "dosage": "850mg", "unit": "Viên", "instr": "Ngày uống 2 viên sau ăn"}],
            "Glucphage_1000mg": [{"brand": "MEGLUCON 1000", "dosage": "1000mg", "unit": "Viên", "instr": "Ngày uống 1 viên sau ăn tối"}],
            "Savi_Acarbose_100": [{"brand": "SAVI ACARBOSE 100", "dosage": "100mg", "unit": "Viên", "instr": "Ngày uống 1 viên trước ăn sáng"}],

            # --- Tiêu hóa ---
            "Famotdin_40mg": [{"brand": "FAMOGAST", "dosage": "40mg", "unit": "Viên", "instr": "Uống 1 viên trước ăn sáng 30 phút"}],
            "Kagasdine_20mg": [{"brand": "KAGASDINE", "dosage": "20mg", "unit": "Viên", "instr": "Uống 1 viên trước ăn sáng 30 phút"}],
            "Omeprazole": [{"brand": "KAGASDINE", "dosage": "20mg", "unit": "Viên", "instr": "Uống 1 viên trước ăn sáng 30 phút"}],
            "Prazopro_40mg": [{"brand": "PRAZOPRO", "dosage": "40mg", "unit": "Viên", "instr": "Ngày uống 1 viên trước ăn sáng"}],
            "Normagut_250mg": [{"brand": "NORMAGUT", "dosage": "250mg", "unit": "Viên", "instr": "Ngày uống 2 viên sau ăn"}],
            "Kim_Tien_Thao": [{"brand": "Kim tiền thảo", "dosage": "120mg+35mg", "unit": "Viên", "instr": "Ngày uống 3 viên sau ăn"}],
            "Spas_agi_40mg": [{"brand": "ALVERIN", "dosage": "40mg", "unit": "Viên", "instr": "Ngày uống 3 viên sau ăn"}],
            "Pymenospain_40mg": [{"brand": "SPASVINA", "dosage": "40mg", "unit": "Viên", "instr": "Ngày uống 3 viên trước ăn"}],
            "Nhiet_Mieng": [{"brand": "THANH NHIỆT TIÊU ĐỘC LIVERGOOD", "dosage": "Tab", "unit": "Viên", "instr": "Ngày uống 2 viên sau ăn"}],

            # --- Thần kinh ---
            "Hoat_Huyet_Duong_Nao": [{"brand": "HOẠT HUYẾT DƯỠNG NÃO", "dosage": "150mg+20mg", "unit": "Viên", "instr": "Ngày uống 2 viên (sáng, tối)"}],
            "Hoat_Huyet_Ich_Nao": [{"brand": "BỐ HUYẾT ÍCH NÃO BDF", "dosage": "40mg+300mg", "unit": "Viên", "instr": "Ngày uống 2 viên (sáng, tối)"}],
            "Piracetam_800mg": [{"brand": "STACETAM", "dosage": "800mg", "unit": "Viên", "instr": "Ngày uống 3 viên sau ăn"}],

            # --- Gan ---
            "France_Liver_Gold_Plus_Giai_Doc_Gan": [{"brand": "MEDIBOGAN", "dosage": "200mg+150mg+16mg", "unit": "Viên", "instr": "Ngày uống 2 viên sau ăn"}],
            "Heptonic_Forte": [{"brand": "KAHAGAN", "dosage": "0,1g+0,075g+0,075g", "unit": "Viên", "instr": "Ngày uống 2 viên sau ăn"}],
            "LIVOLIN_FORTE": [{"brand": "LIVONIC", "dosage": "2500mg+400mg+500mg+85mg", "unit": "Viên", "instr": "Ngày uống 2 viên sau ăn"}],
            "Liverbil": [{"brand": "GAPHYTON S", "dosage": "100mg+75mg+7,5mg", "unit": "Viên", "instr": "Ngày uống 2 viên sau ăn"}],
            "Silymarin": [{"brand": "CHORLATCYN", "dosage": "125mg;50mg;50mg;25mg", "unit": "Viên", "instr": "Ngày uống 2 viên sau ăn"}],

            # --- Cơ xương khớp / Kháng viêm ---
            "Alpha_Chymotrypsine": [{"brand": "STATRIPSINE", "dosage": "4,2mg", "unit": "Viên", "instr": "Ngày uống 3 viên trước ăn"}],
            "Diclofenac_50mg": [{"brand": "VOLTAREN", "dosage": "50mg", "unit": "Viên", "instr": "Ngày uống 2 viên sau ăn"}],
            "Morif_7.5mg": [{"brand": "MELOXICAM", "dosage": "7,5mg", "unit": "Viên", "instr": "Ngày uống 1 viên sau ăn"}],
            "Meyeroxofen_Meyer_60mg": [{"brand": "MEZAFEN", "dosage": "60mg", "unit": "Viên", "instr": "Ngày uống 1 viên sau ăn"}],
            "Medrol_16mg": [{"brand": "METHYLSOLONE", "dosage": "16mg", "unit": "Viên", "instr": "Ngày uống 1 viên buổi sáng sau ăn"}],
            "Medrol_4mg": [{"brand": "METHYLPREDNISOLON 4", "dosage": "4mg", "unit": "Viên", "instr": "Ngày uống 4 viên buổi sáng sau ăn"}],
            "Menison_16mg": [{"brand": "MENISON", "dosage": "16mg", "unit": "Viên", "instr": "Ngày uống 1 viên buổi sáng sau ăn"}],
            "Menison_4mg": [{"brand": "METHYLPREDNISOLON 4", "dosage": "4mg", "unit": "Viên", "instr": "Ngày uống 4 viên buổi sáng sau ăn"}],
            "Methylprednisolon_16mg_Vidipha": [{"brand": "VIPREDNI", "dosage": "16mg", "unit": "Viên", "instr": "Ngày uống 1 viên buổi sáng sau ăn"}],

            # --- Dị ứng ---
            "Agilodin_10mg": [{"brand": "SERGUROP", "dosage": "10mg", "unit": "Viên", "instr": "Ngày uống 1 viên tối"}],
            "Loratadine_10mg": [{"brand": "SERGUROP", "dosage": "10mg", "unit": "Viên", "instr": "Ngày uống 1 viên tối"}],
            "Loreze_10mg": [{"brand": "VACO LORATADINE", "dosage": "10mg", "unit": "Viên", "instr": "Ngày uống 1 viên tối"}],

            # --- Hô hấp ---
            "Acetylcysteine": [{"brand": "DIXIREIN", "dosage": "375mg", "unit": "Gói", "instr": "Hòa tan uống, ngày 2 gói"}],
            "Halixol": [{"brand": "BROMHEXIN ACTAVIS", "dosage": "8mg", "unit": "Viên", "instr": "Ngày uống 3 viên sau ăn"}],
            "Hexinvon_8mg": [{"brand": "BROMHEXIN ACTAVIS", "dosage": "8mg", "unit": "Viên", "instr": "Ngày uống 3 viên sau ăn"}],

            # --- Vitamin / Bổ sung ---
            "Rutin_C": [{"brand": "VENRUTINE", "dosage": "100mg+500mg", "unit": "Viên", "instr": "Ngày uống 2 viên sau ăn"}],
            "Trineuron": [{"brand": "SETBLOOD", "dosage": "115mg+100mg+50mcg", "unit": "Viên", "instr": "Ngày uống 1 viên sau ăn"}],
            "Venrutine": [{"brand": "VENRUTINE", "dosage": "100mg+500mg", "unit": "Viên", "instr": "Ngày uống 2 viên sau ăn"}],
            "Vina_AD": [{"brand": "VITAMINAD", "dosage": "2500ui+200ui", "unit": "Viên", "instr": "Ngày uống 1 viên"}],
            "Vitamin_3B": [{"brand": "COSYNDO B", "dosage": "175mg+100mg+50mcg", "unit": "Viên", "instr": "Ngày uống 1 viên sau ăn"}],
            "Vitamin_C_500mg": [{"brand": "VITAMIN C STADA", "dosage": "1g", "unit": "Viên", "instr": "Ngày uống 1 viên buổi sáng"}],
            "Vitamin_C_Vien_Sui": [{"brand": "C1000 FLOODE", "dosage": "1g", "unit": "Viên sủi", "instr": "Sáng uống 1 viên (hòa tan trong nước)"}],

            # --- Khác ---
            "Acetaminophen": [{"brand": "TROYSAR AM", "dosage": "5mg+160mg", "unit": "Viên", "instr": "Ngày uống 1 viên buổi sáng"}],
            "Agiclovir_800": [{"brand": "MEDIPLEX", "dosage": "800mg", "unit": "Viên", "instr": "Ngày uống 4 viên"}],
            "Agifuros_40mg": [{"brand": "BECOSEMID", "dosage": "40mg", "unit": "Viên", "instr": "Sáng uống 1 viên"}],
            "Allopurinol_STELLA_300mg": [{"brand": "SADAPRON 300", "dosage": "300mg", "unit": "Viên", "instr": "Ngày uống 1 viên sau ăn"}],
            "Bisoprolol_2.5mg": [{"brand": "CARUDXAN", "dosage": "2,5mg", "unit": "Viên", "instr": "Ngày uống 1 viên buổi sáng"}],
            "Cefpodoxime_100mg": [{"brand": "CEFOLAC", "dosage": "100mg", "unit": "Viên", "instr": "Ngày uống 2 viên sau ăn"}],
            "Expas_Forte_80mg": [{"brand": "DROMASM FORT", "dosage": "80mg", "unit": "Viên", "instr": "Ngày uống 3 viên trước ăn"}],
            "Hafenthyl_145mg": [{"brand": "FIBROFIN-145", "dosage": "145mg", "unit": "Viên", "instr": "Ngày uống 1 viên sau ăn"}],
            "Milurit_300mg": [{"brand": "MILURIT", "dosage": "300mg", "unit": "Viên", "instr": "Ngày uống 1 viên sau ăn"}],
            "Domperidone_10mg": [{"brand": "DOMPENYL", "dosage": "10mg", "unit": "Viên", "instr": "Ngày uống 3 viên trước ăn"}],
        }

        self.doctors = [
             {"name": "Nguyễn Văn A", "title": "BS.CKI"}, {"name": "Trần Thị B", "title": "ThS.BS"},
             {"name": "Lê Vũ C", "title": "BS.CKII"}, {"name": "Phạm Minh D", "title": "TS.BS"},
             {"name": "Hoàng Thị E", "title": "BS.CKI"}, {"name": "Vũ Văn F", "title": "BS"}
        ]
        
    def get_random_condition(self, age_group):
        candidates = [c for c in self.conditions.values() if age_group in c["types"]]
        if not candidates: return random.choice(list(self.conditions.values()))
        return random.choice(candidates)
    
    def get_drug_details(self, generic_name):
        if generic_name not in self.drugs:
            return None
        return random.choice(self.drugs[generic_name])

# ==============================================================================
# 2. GENERATOR LOGIC
# ==============================================================================
class PrescriptionGenerator:
    def __init__(self):
        self.kb = MedicalKnowledgeBase()
        self.current_id = 0

    def generate_patient(self):
        last_names = ["Nguyễn", "Trần", "Lê", "Phạm", "Hoàng", "Huỳnh", "Phan", "Vũ", "Võ", "Đặng", "Bùi", "Đỗ", "Hồ", "Ngô", "Dương", "Lý"]
        middle_names = ["Văn", "Thị", "Hữu", "Đức", "Minh", "Thu", "Ngọc", "Thanh", "Quang", "Mạnh", "Kim", "Xuân"]
        first_names = ["An", "Bình", "Cường", "Dung", "Em", "Giang", "Hải", "Lan", "Mai", "Oanh", "Khoa", "Phúc", "Tâm", "Thảo", "Hùng", "Sơn", "Tùng", "Trang"]
        
        gender = random.choice(["Nam", "Nữ"])
        name = f"{random.choice(last_names)} {random.choice(middle_names)} {random.choice(first_names)}"
        if gender == "Nam" and "Thị" in name: name = name.replace("Thị", "Văn")
        elif gender == "Nữ" and "Văn" in name: name = name.replace("Văn", "Thị")

        age_group_roll = random.random()
        if age_group_roll < 0.15: # 15% Pediatric
            age = random.randint(1, 16)
            group = "Pediatric"
        elif age_group_roll < 0.55: # 40% Adult
            age = random.randint(17, 60)
            group = "Adult"
        else: # 45% Elderly (High chance of Polypharmacy)
            age = random.randint(61, 95)
            group = "Elderly"

        address = f"{random.randint(1,999)} Đường {random.choice(['Nguyễn Huệ', 'Lê Lợi', 'Trần Hưng Đạo', '3/2', 'CMT8', 'Võ Văn Kiệt'])}, {random.choice(['Hà Nội', 'TP.HCM', 'Đà Nẵng', 'Cần Thơ', 'Hải Phòng'])}"
        insurance_code = f"DN{random.randint(4000000000, 9999999999)}"

        return {
            "name": name.upper(),
            "age": age,
            "gender": gender,
            "address": address,
            "insurance_code": insurance_code,
            "group": group
        }

    def generate_prescription(self):
        self.current_id += 1
        patient = self.generate_patient()
        doctor = random.choice(self.kb.doctors)
        # MEDICAL LOGIC: Assign Diseases
        patient_conditions = []
        
        # ROLL FOR COMPLEXITY
        # 15% Simple (1-3 meds, 1 condition)
        # 85% Complex (Multiple conditions, comorbidities)
        is_simple_case = random.random() < 0.15

        if is_simple_case:
            num_conditions = 1
        else:
            # COMPLEX LOGIC
            if patient["group"] == "Elderly":
                num_conditions = random.randint(3, 6) # High comorbidity
            elif patient["group"] == "Adult":
                num_conditions = random.randint(2, 4)
            else: # Pediatric
                num_conditions = random.choices([1, 2], weights=[0.7, 0.3])[0]
        
        chosen_codes = set()
        
        # Helper to force diversity (not just HTN all the time)
        # We define "seed" specialties to start with
        seed_specialties = ["Cardio", "Endo", "Neuro", "Resp", "GI", "Derma", "Eye"]
        weights = [0.3, 0.2, 0.15, 0.1, 0.1, 0.05, 0.1]
        
        # 1. Pick primary conditions
        for _ in range(num_conditions):
            cond = None
            
            # Smart Comorbidity Logic: If we already have Diabetes (E11), high chance to add Hypertension (I10) or Lipid (E78.0)
            if "E11" in chosen_codes and "I10" not in chosen_codes and random.random() < 0.7:
                 cond = self.kb.conditions["I10"]
            elif "E11" in chosen_codes and "E78.0" not in chosen_codes and random.random() < 0.7:
                 cond = self.kb.conditions["E78.0"]
            elif "I63.9" in chosen_codes and "I25.1" not in chosen_codes and random.random() < 0.6:
                 cond = self.kb.conditions["I25.1"]
            
            if not cond:
                # Pick random
                cond = self.kb.get_random_condition(patient["group"])
                
            if cond["code"] not in chosen_codes:
                patient_conditions.append(cond)
                chosen_codes.add(cond["code"])

        diag_str = "; ".join([f"{c['code']}: {c['name']}" for c in patient_conditions])
        
        selected_meds_list = []
        
        for cond in patient_conditions:
            possible_drugs = cond["drugs"]
            
            # Logic: Number of drugs to take from this condition
            if is_simple_case:
                 take_count = random.randint(1, min(2, len(possible_drugs)))
            else:
                 # Complex: Take more drugs (Polypharmacy)
                 # 70% chance to take 2-3 drugs if available, else 1
                 take_count = random.randint(1, len(possible_drugs))
                 # Bias towards taking more
                 if len(possible_drugs) >= 2 and random.random() < 0.7:
                     take_count = random.randint(2, len(possible_drugs))
            
            picked_generics = random.sample(possible_drugs, min(take_count, len(possible_drugs)))
            
            for generic in picked_generics:
                if any(m["generic_name"] == generic for m in selected_meds_list): continue
                
                details = self.kb.get_drug_details(generic)
                if details:
                    duration = 28 if "Chronic" in cond["types"] else 7
                    daily_dose = 1
                    if "2 viên" in details["instr"] or "2 lần" in details["instr"]: daily_dose = 2
                    if "3 viên" in details["instr"] or "3 lần" in details["instr"]: daily_dose = 3
                    
                    total_qty = duration * daily_dose
                    
                    # Randomize unit/qty slightly for realism
                    if details["unit"] == "Lọ" or details["unit"] == "Tuýp":
                        total_qty = random.randint(1, 2)

                    med_entry = {
                        "generic_name": generic,
                        "brand_name": details["brand"],
                        "dosage": details["dosage"],
                        "unit": details["unit"],
                        "quantity": total_qty,
                        "instructions": details["instr"]
                    }
                    selected_meds_list.append(med_entry)
        
        # Final check for "Simple Case": Max 3 drugs
        if is_simple_case and len(selected_meds_list) > 3:
            selected_meds_list = selected_meds_list[:3]

        # Randomize Date: Dec 2025 to Dec 2026
        start_date = datetime(2025, 12, 1)
        end_date = datetime(2026, 12, 31)
        delta_days = (end_date - start_date).days
        random_days = random.randint(0, delta_days)
        today = start_date + timedelta(days=random_days)
        
        follow_up_days = 28 if any("Chronic" in c["types"] for c in patient_conditions) else 7
        follow_up_date = (today + timedelta(days=follow_up_days)).strftime("%d/%m/%Y")
        
        return {
            "id": self.current_id,
            # "hospital": hospital, # REMOVED
            "patient": {k: v for k, v in patient.items() if k != "group"},
            "prescription_code": f"25{random.randint(100000,999999)}",
            "diagnosis": diag_str,
            "doctor": doctor,
            "medications": selected_meds_list,
            "follow_up_date": follow_up_date,
            "prescription_date": today.strftime("ngày %d tháng %m năm %Y"),
            "notes": "Tái khám nhớ mang theo đơn thuốc này." if len(selected_meds_list) > 5 else "",
            "lab_tests": "CT-Scanner, MRI, Huyết đồ" if "I63.9" in chosen_codes else "",
            "barcode_bottom": f"0000{self.current_id:08d}",
            "duration_days": follow_up_days
        }

def generate_dataset(num_records=50, output_file="generated_data.json"):
    gen = PrescriptionGenerator()
    data = {"prescriptions": [gen.generate_prescription() for _ in range(num_records)]}
    with open(output_file, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"Generated {num_records} prescriptions to {output_file}")

if __name__ == "__main__":
    # Generate 100 sample records
    generate_dataset(num_records=100, output_file="generated_sample_data.json")
