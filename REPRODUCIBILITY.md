# Reproducibility guide

This public branch separates two levels of verification.

## Level 1 — public aggregate verification

Anyone can verify the arithmetic and cross-file consistency of the published aggregate results:

```bash
python3 scripts/verify_published_results.py
python3 -m unittest tests/test_public_artifact_consistency.py
```

This checks:

- the four P0–P3 rows and their TP/FP/FN totals;
- all R0/R1 micro and macro values;
- the paired transition sum `95 + 14 + 9 + 19 = 137`;
- the exact two-sided binomial/McNemar p-value;
- the stored capture- and prescription-level bootstrap intervals;
- the absence of private raw-data, OCR, prediction, and checkpoint paths.

Level 1 does not rerun OCR or PhoBERT inference.

## Level 2 — full experiment re-execution

Exact re-execution requires resources that are deliberately excluded from this public branch:

| Resource | Required role | Public status |
|---|---|---|
| Frozen nine-label PhoBERT checkpoint | Fixed downstream NER | Restricted; not redistributed here |
| RQ1 ML Kit OCR observations | P0–P3 input | Restricted pending privacy review |
| RQ1 canonical ground truth | RQ1 scoring | Restricted pending consent/privacy review |
| RQ2 R0/R1 OCR JSON | Paired comparison input | Restricted pending privacy review |
| Visible-in-frame ground truth | RQ2 scoring | Restricted pending consent/privacy review |
| 9,284-record drug catalog | Name normalization | Provider-controlled; license must be confirmed |
| VAIPE files | Clean diagnostic reference | Obtain from the original dataset source under its terms |

The frozen checkpoint recorded by the authors has SHA-256:

```text
d8e1ab2f6bc3d71480fffb6e487e5b63f36467a2d0a586585f871ce65b9d25f6
```

The retained artifacts do not establish the original training seed of this nine-label checkpoint. Seed `42` in the paper is the RQ2 bootstrap seed, not a model-training seed.

### RQ1 command

After mounting an authorized RxIE resource tree:

```bash
python3 scripts/benchmark_real_mlkit_layout.py \
  --rxie-root /path/to/authorized/rxie-root \
  --output-dir /tmp/isbm-rq1-results \
  --split val
```

Expected aggregate output: `reports/real_layout_ablation/summary.csv`.

### RQ2 command

After mounting authorized R0/R1 OCR JSON and visible-in-frame ground truth:

```bash
python3 scripts/benchmark_real_medication_roi.py \
  --ocr-dir /path/to/authorized/mlkit_ocr \
  --visible-gt /path/to/authorized/visible_in_frame_gt.json \
  --output-dir /tmp/isbm-rq2-results \
  --bootstrap 10000
```

Expected aggregate outputs include `summary.csv`, `paired_transition_matrix.csv`, and `statistical_significance.json`.

### On-device OCR collection

`scripts/run_real_roi_phone_ocr.py` contains the Android/Flutter orchestration used to collect R0/R1 ML Kit OCR outputs. It requires an authorized manifest, the corresponding local images, Flutter tooling, and a connected Android device. No prescription images or manifests are bundled in this branch.

## Environment summary

- Android OCR: `google_mlkit_text_recognition 0.15.0`, Latin recognizer.
- Recorded device for the paper: TECNO CM5, Android 16.
- Downstream base model: `vinai/phobert-base-v2`, fixed fine-tuned checkpoint.
- Bootstrap: 10,000 percentile iterations, seed 42.
- RQ2 sample: 30 captures, 5 prescription clusters, 137 visible drug instances.

## Interpretation boundary

The public aggregate verifier establishes internal consistency of the released result files. It does not independently establish dataset provenance, annotation validity, model-training provenance, or external generalization. The paper reports a numerical R1 improvement with a non-significant exact paired test; this branch preserves that interpretation.
