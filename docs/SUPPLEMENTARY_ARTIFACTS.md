# Supplementary artifacts

The public GitHub repository contains source code and aggregate reports. Larger
or controlled resources are referenced separately through the MedicineApp ISBM
2026 supplementary folder:

**[Open the Google Drive supplementary folder](https://drive.google.com/drive/folders/12sm6zRuUiiAzQM8xxAFrLngVKZ07Kpul?usp=sharing)**

The folder is intended for exceptional artifacts such as a frozen model
checkpoint, checksums, manifests, or authorized experimental inputs that are not
appropriate for normal Git history. Its contents and access policy may change.

## Important access boundary

- The Drive URL is a pointer, not a license grant.
- Download access does not automatically permit redistribution or publication.
- Do not add real prescriptions, patient identifiers, raw OCR, or ground truth
  unless consent, institutional policy, security, and sharing permissions have
  been reviewed for that exact folder and audience.
- A file in Drive is not automatically covered by the repository's MIT License.
- Public aggregate verification does not require any Drive download.

## Expected local placement

Only after authorization, place compatible resources in Git-ignored locations:

```text
models/phobert_ner_model/
data/drug_db_vn_full.json
private/rxie/
private/rq2/mlkit_ocr/
private/rq2/visible_in_frame_gt.json
```

The benchmark commands accept explicit paths for the RxIE tree and RQ2 inputs;
see [`REPRODUCIBILITY.md`](../REPRODUCIBILITY.md).

## Integrity check

For each downloaded artifact, record its filename, version, source, license or
permission basis, and SHA-256 checksum before use:

```bash
sha256sum /absolute/path/to/artifact
```

The recorded SHA-256 for the frozen nine-label PhoBERT checkpoint used in the
paper is:

```text
d8e1ab2f6bc3d71480fffb6e487e5b63f36467a2d0a586585f871ce65b9d25f6
```

Do not assume that a similarly named checkpoint is equivalent; verify the
actual file and keep the verification record outside public logs when filenames
or paths reveal sensitive study information.

## Reproduction levels

- **Level 1 — public:** clone GitHub and run `./reproduce.sh`.
- **Level 2 — controlled:** obtain authorized resources, verify checksums, mount
  them locally, and run the RQ1/RQ2 commands in `REPRODUCIBILITY.md`.

If a required file is unavailable or its redistribution basis is unclear,
report the experiment as not fully re-executed rather than substituting an
untracked artifact and claiming exact reproduction.
