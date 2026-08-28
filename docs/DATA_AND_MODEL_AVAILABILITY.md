# Data and model availability

## Public in this branch

- Source code for the application, services, and evaluation programs.
- Aggregate result tables that do not contain per-capture text or predictions.
- Public consistency checks.
- MIT license for source code.

## Not redistributed

The following material is intentionally absent:

- prescription photographs;
- OCR text and bounding-box JSON derived from prescriptions;
- canonical or visible-in-frame ground truth containing prescription-level identifiers or medication lists;
- per-capture and per-instance predictions;
- the provider-controlled Vietnamese drug catalog;
- model weights and checkpoints;
- full VAIPE data.

De-identification alone does not establish redistribution rights. Access to restricted material requires a separate review of consent, privacy, institutional policy, and third-party licenses.

## Reusing the code with independent resources

Researchers may run the code with their own authorized inputs by supplying:

1. ML Kit OCR JSON matching the schemas consumed by the benchmark scripts.
2. Independently annotated ground truth.
3. A legally obtained drug catalog with the fields expected by `DrugLookup`.
4. A compatible token-classification checkpoint.

Do not place those inputs in a public fork unless you have explicit redistribution rights.
