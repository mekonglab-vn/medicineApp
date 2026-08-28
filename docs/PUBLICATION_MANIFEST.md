# Public artifact manifest

## Included

- `mobile/`: Flutter UI and Android ML Kit bridge, excluding real ROI manifests and images.
- `core/`: extraction and normalization pipeline.
- `server/` and `server-node/`: API implementation.
- `scripts/`: benchmark implementations, on-device orchestration, and public verifier.
- `reports/`: aggregate CSV/JSON only.
- `tests/`: tests that do not require restricted files.

## Explicitly excluded

- `data/drug_db_vn_full.json`, `data/drug_db_vn.csv`, and provider-derived catalogs.
- `data/visible_in_frame_gt.json` and provenance logs.
- RQ1 canonical ground truth and raw OCR JSON.
- `reports/**/mlkit_ocr/`, prediction JSONL, recovered-drug lists, and per-capture reports.
- `mobile/assets/real_roi_samples/` and `mobile/assets/roi_samples/`.
- model weights (`*.safetensors`, `*.pt`, `*.pth`, `*.onnx`).
- `.env`, signing keys, keystores, credentials, build outputs, caches, and local workspaces.

This branch was created with a new root commit so its own history does not inherit restricted files from the earlier research branches.
