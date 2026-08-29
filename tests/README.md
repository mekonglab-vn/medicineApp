# Tests

All Python tests live here. None of them require the restricted inputs listed in
[`docs/PUBLICATION_MANIFEST.md`](../docs/PUBLICATION_MANIFEST.md); tests that
would need a restricted file skip themselves instead of failing.

## Public verification, no dependencies

Runs on the Python 3 standard library alone:

```bash
./reproduce.sh
```

## Full suite

Needs the packages in [`requirements.txt`](../requirements.txt):

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt pytest
python -m pytest tests/ -v
```

Run pytest from the repository root so that `core/` resolves on the import path.

## What each file covers

| File | Covers |
| :-- | :-- |
| `test_public_artifact_consistency.py` | Aggregate RQ1/RQ2 results and the privacy boundary |
| `test_p0_p3_ablation.py` | P0 to P3 layout ablation and the failure taxonomy cascade |
| `test_mlkit_layout_adapter.py` | ML Kit line stream to reading order reconstruction |
| `test_ai_semantic_filter.py` | Semantic drug/non-drug classification |
| `test_post_filter.py` | NER post-filter drug-likeness rules |
| `test_drug_lookup_resolution_safety.py` | Drug normalization resolution safety |
| `test_pipeline_failure_contract.py` | Pipeline error contract for malformed uploads |
| `test_api_alignment.py` | Pipeline output shape against the API contract |
| `test_bug_fixes.py` | Regression tests for the Phase A classifier |
