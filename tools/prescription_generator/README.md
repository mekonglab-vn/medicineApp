# Prescription Data Generator (Dữ liệu Đơn thuốc Tổng hợp)

Dự án **Prescription Data Generator** là bộ công cụ chuyên nghiệp dùng để sinh dữ liệu đơn thuốc giả lập (Synthetic Medical Prescription Data). Hệ thống được thiết kế để tạo ra hàng nghìn mẫu đơn thuốc đa dạng, từ các ca bệnh đơn giản đến phức tạp, đồng thời hỗ trợ tiêm lỗi (Error Injection) để phục vụ việc huấn luyện và kiểm thử các mô hình AI (OCR, NLP, Medical Error Detection).

## 🚀 Tính năng nổi bật

*   **Sinh dữ liệu thông minh**: Tự động tạo thông tin bệnh nhân, bác sĩ, và chẩn đoán bệnh dựa trên Knowledge Base (KB) y khoa phong phú.
*   **Ca bệnh phức tạp (Complex Cases)**: Hỗ trợ sinh các đơn thuốc "khó" với nhiều loại thuốc, bệnh lý nền (Tiểu đường, Huyết áp, Tim mạch...) và ghi chú lâm sàng chi tiết.
*   **Tiêm lỗi tự động (Medical Error Injection)**:
    *   **Lỗi số lượng**: Sai lệch gấp 10, 100 lần, lỗi nhập liệu.
    *   **Lỗi đơn vị**: Sai đơn vị tính logic (Ví dụ: Thuốc nước nhưng kê đơn vị "Viên").
    *   **Tương tác thuốc**: Tự động chèn các cặp thuốc gây tương tác (Drug-Drug Interactions) như Warfarin + Aspirin.
    *   **Chống chỉ định**: Cảnh báo thuốc theo độ tuổi hoặc bệnh lý đi kèm.
*   **Xuất bản tài liệu**:
    *   Hỗ trợ xuất file **JSON** tiêu chuẩn.
*   Tự động sinh file **DOCX** theo bố cục đơn thuốc mô phỏng với tên cơ sở y tế hư cấu.
    *   Tự động convert sang **PDF** để mô phỏng thực tế in ấn.

## 📂 Cấu trúc Dự án

```text
prescription_generator/
├── data_generator.py        # Core: Script sinh dữ liệu gốc (Sample Data)
├── error_injector.py        # Core: Module tiêm lỗi vào dữ liệu (Error Data)
├── generate_prescription.py # Tool: Chuyển đổi JSON -> DOCX/PDF
├── append_complex_cases.py  # Util: Thêm các ca bệnh mẫu phức tạp từ template
├── long_data.json           # Template: Mẫu ca bệnh phức tạp (Lê Văn Trận)
├── generated_sample_data.json # Output: Dữ liệu sạch (Clean Data)
├── generated_error_data.json  # Output: Dữ liệu lỗi (Dirty/Error Data)
├── output/                  # Chứa các file DOCX/PDF sau khi render
├── requirements.txt         # Các thư viện Python cần thiết
└── README.md                # Tài liệu hướng dẫn
```

## 🛠️ Yêu cầu cài đặt

1.  **Python 3.8+**
2.  **LibreOffice** (Bắt buộc để convert DOCX sang PDF trên Linux/Headless server).
    ```bash
    sudo apt-get install libreoffice
    ```
3.  **Python Libraries**:
    ```bash
    pip install -r requirements.txt
    ```

## 📖 Hướng dẫn sử dụng

### 1. Sinh dữ liệu mẫu (Sample Data)
Chạy script để tạo bộ dữ liệu đơn thuốc tiêu chuẩn. Mặc định sẽ tạo 100 đơn thuốc với ngày khám ngẫu nhiên từ 12/2015 đến 12/2026.

```bash
python data_generator.py
```
*Kết quả*: File `generated_sample_data.json` được cập nhật.

### 2. Thêm ca bệnh phức tạp
Để tăng độ khó cho bộ dữ liệu (test case tim mạch, đa bệnh lý), chạy script sau:

```bash
python append_complex_cases.py
```
*Tác dụng*: Nhân bản và thêm 10 ca bệnh phức tạp dựa trên mẫu `long_data.json` vào file sample.

### 3. Tạo dữ liệu lỗi (Error Data)
Dựa trên bộ dữ liệu sạch, script này sẽ tạo ra file `generated_error_data.json` chứa các lỗi y khoa và hành chính cố ý.

```bash
python error_injector.py
```
*Cấu hình lỗi*: Được định nghĩa trong Class `ErrorInjector` (Tỷ lệ lỗi đơn vị, tương tác thuốc...).

### 4. Xuất tài liệu (Render DOCX & PDF)
Cuối cùng, chạy script để chuyển đổi JSON thành văn bản in ấn.

```bash
# Sinh PDF cho toàn bộ dữ liệu mẫu
python generate_prescription.py --data generated_sample_data.json --output output/all_samples.docx --all

# Sinh PDF cho toàn bộ dữ liệu lỗi
python generate_prescription.py --data generated_error_data.json --output output/all_errors.docx --all
```

Sau khi tạo xong DOCX, hệ thống sẽ tự động gọi LibreOffice để convert sang PDF trong thư mục `output/`.

## 📝 Ghi chú Kỹ thuật (Technical Notes)

*   **Logic Random Date**: Hệ thống sử dụng `datetime` và `random` để phân bổ ngày khám đều trong khoảng thời gian chỉ định, giúp dữ liệu trông tự nhiên hơn.
*   **Word Rendering**: Sử dụng `python-docx` với các hàm căn chỉnh Table/Cell custom để đảm bảo form in ra giống thật nhất (bao gồm cả Header/Footer lặp lại).
*   **Encoding**: Tất cả file I/O đều sử dụng `utf-8` để hỗ trợ Tiếng Việt đầy đủ.

---
**Author**: Hong Phuoc
**Repository**: [github.com/hongphuoc6104/createData](https://github.com/hongphuoc6104/createData)
