# Core — Source Code Chính

Module chứa toàn bộ logic nghiệp vụ MedicineApp (đã được tối ưu hóa cho Google ML Kit di động).

## Cấu trúc

| Thư mục | Mô tả |
|---------|-------|
| `classify/` | Phân loại thực thể PhoBERT NER + Ghép dòng thông minh theo STT |
| `drug_search/` | Tra cứu và chuẩn hóa tên thuốc theo CSDL Việt Nam (9,284 thuốc) |
| `config.py` | Cấu hình các đường dẫn đầu vào/đầu ra |
| `pipeline.py` | Bộ điều phối (Orchestrator) chính của dịch vụ |
