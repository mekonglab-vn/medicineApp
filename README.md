# MedicineApp — ISBM 2026 Public Research Artifact

This branch contains the public software artifact associated with the paper:

> **A Mobile Information System for Drug Extraction from Vietnamese Prescriptions: OCR Layout Ablation and Text-Anchored ROI Re-OCR under Challenging Smartphone Conditions**

The artifact includes the Flutter application interface, the Python and Node.js pipeline code, the RQ1/RQ2 evaluation programs, and aggregate result files that can be checked without access to restricted prescription data.

> **Research prototype:** this software is not a medical device and must not be used to make clinical decisions. OCR and extracted medication names require human verification.

## What is public

- Flutter mobile/web interface for scanning, reviewing, and managing prescription-derived drafts.
- Python extraction pipeline and FastAPI service.
- Node.js API and database layer.
- P0–P3 OCR-layout ablation code.
- R0 full-page versus R1 ROI re-OCR evaluation code.
- Public aggregate CSV/JSON results and a consistency verifier.
- Tests that do not require private prescription files.

## What is not public

- Original prescription images or screenshots containing prescription text.
- Per-capture OCR JSON, ground-truth medication lists, prediction JSONL, or provenance records.
- The provider-controlled 9,284-record drug database.
- VAIPE images or files whose redistribution terms have not been confirmed.
- The frozen PhoBERT checkpoint and other model weights.

These exclusions are intentional. They protect privacy, consent, and third-party licensing while leaving the implementation and aggregate claims inspectable. See [DATA_AND_MODEL_AVAILABILITY.md](docs/DATA_AND_MODEL_AVAILABILITY.md).

## Reported results

### RQ1: OCR representation ablation

| Strategy | Micro precision | Micro recall | Micro F1 |
|---|---:|---:|---:|
| P0 raw lines | 89.36% | 30.02% | 44.94% |
| P1 sorted lines | 89.36% | 30.02% | 44.94% |
| P2 row clusters | 82.79% | 25.49% | 38.98% |
| P3 medication bands | 90.63% | 19.59% | 32.22% |

### RQ2: paired full-page versus ROI re-OCR

| Condition | OCR coverage | Precision | Recall | Micro F1 |
|---|---:|---:|---:|---:|
| R0 full-page OCR | 90.51% | 77.61% | 75.91% | 76.75% |
| R1 ROI re-OCR | 92.70% | 80.74% | 79.56% | 80.15% |

The paired transition counts were 95 successes in both conditions, 14 R1 recoveries, 9 R1 regressions, and 19 misses in both conditions. The exact two-sided McNemar/binomial test returned `p = 0.4049`; the numerical gain should therefore not be interpreted as established superiority.

## Verify the public artifact

Only Python's standard library is required:

```bash
python3 scripts/verify_published_results.py
```

Or run the public test:

```bash
python3 -m unittest tests/test_public_artifact_consistency.py
```

The verifier checks the published aggregate tables, transition arithmetic, confidence intervals, and the absence of restricted artifact classes.

## Run the application interface

Requirements: Flutter compatible with Dart `3.10.x` and an Android emulator, Android device, Linux desktop, or web target.

```bash
cd mobile
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000/api
```

For a physical Android device connected by USB, expose the API port and use device localhost:

```bash
adb reverse tcp:3000 tcp:3000
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:3000/api
```

The application source is included for interface inspection and research use. A full extraction run additionally requires the restricted or independently licensed resources described below.

## Repository layout

```text
mobile/       Flutter interface and Android ML Kit bridge
core/         OCR representation, NER, normalization, and pipeline code
server/       Python FastAPI service
server-node/  Node.js API and PostgreSQL layer
scripts/      Evaluation and public verification programs
reports/      Aggregate publication results only
data/         Availability instructions; no restricted data
models/       Model availability instructions; no weights
tests/        Public consistency and unit tests
```

## Full experimental reproduction

Exact re-execution of RQ1/RQ2 requires the same frozen checkpoint, OCR observations, ground truth, and drug catalog. Those files are not redistributed in this public branch. The commands, expected schemas, hashes where available, and verification levels are documented in [REPRODUCIBILITY.md](REPRODUCIBILITY.md).

## Citation and license

Citation metadata is provided in [CITATION.cff](CITATION.cff). Source code in this branch is released under the [MIT License](LICENSE). Data, model weights, and third-party services are not automatically covered by the source-code license.
