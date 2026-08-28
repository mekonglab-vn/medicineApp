# Server — FastAPI

### Khởi chạy

```bash
# Bước 1: Activate môi trường
source venv/bin/activate

# Bước 2: Start server
uvicorn server.main:app --reload --host 0.0.0.0 --port 8000
```

### Endpoints

| Method | Path | Mô tả |
|--------|------|-------|
| GET | `/api/health` | Health check — trạng thái server |
| POST | `/api/scan-prescription` | Phase A: quét ảnh đơn thuốc → danh sách thuốc |
| POST | `/api/scan-pills` | Phase B: xác minh viên thuốc với đơn thuốc |

### Drug Info APIs

| Method | Path | Mô tả |
|--------|------|-------|
| GET | `/api/drug-info/{name}` | Tra cứu thuốc theo tên (local DB + optional online) |
| GET | `/api/drugs?q=...&limit=20` | Tìm kiếm / liệt kê drug DB local |
| GET | `/api/drugs-online?q=...` | Tìm kiếm thuốc qua OpenFDA API |
| GET | `/api/drugs-vn?q=...` | Tìm kiếm thuốc VN (ddi.lab.io.vn) |
| GET | `/api/drugs-vn/suggest?q=...` | Autocomplete tên thuốc VN |
| GET | `/api/drugs-vn/interactions?ingredient=...` | Tương tác thuốc (VN database) |

### Cấu trúc

```
server/
├── main.py            # FastAPI app + tất cả endpoints
├── data/
│   ├── drug_db.json       # Drug database (190+ thuốc)
│   └── drug_db_full.json  # Drug database mở rộng (830KB)
├── routers/           # (reserved)
├── schemas/           # (reserved)
└── services/          # Business logic services
```
