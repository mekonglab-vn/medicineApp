# Methods and Annotation Protocol: Medication ROI Intervention Study

This public document describes the aggregate protocol and results. Source
prescription images, capture identifiers, OCR payloads, medication lists, and
per-capture annotations are intentionally excluded because they are restricted
research data.

## Evaluation subset

The paired study used 30 challenging smartphone captures grouped into five
prescription clusters. Human inspection identified 137 medication instances
that were physically visible in frame. An item was counted as visible when at
least 70% of its character glyphs could be read directly from the original
image. Annotation was performed without consulting OCR predictions.

## Conditions

- **R0:** OCR and extraction from the original full-page camera image.
- **R1:** a user-selected medication-table region was cropped from the same
  high-resolution image and reprocessed by the same OCR and extraction stack.

Both conditions used the same downstream model and normalization resources.
Those restricted artifacts are not redistributed in this repository.

## Aggregate results

| Granularity | Condition | Coverage | Precision | Recall | F1 | Sample size |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Drug-instance micro | R0 | 90.51% | 77.61% | 75.91% | 76.75% | 137 instances |
| Drug-instance micro | R1 | 92.70% | 80.74% | 79.56% | 80.15% | 137 instances |
| Capture macro | R0 | 90.67% | 77.83% | 77.00% | 76.94% | 30 captures |
| Capture macro | R1 | 93.00% | 81.00% | 81.00% | 80.57% | 30 captures |
| Prescription macro | R0 | 97.37% | 82.13% | 92.07% | 86.20% | 5 clusters |
| Prescription macro | R1 | 97.98% | 84.28% | 94.34% | 88.42% | 5 clusters |

The paired transition counts were: both correct 95, R1 recovery 14, R1
regression 9, and both incorrect 19. The numerical net gain was five instances.
An exact two-sided McNemar/binomial test gave `p = 0.4049`, so the study does
not establish statistical superiority.

The capture-level bootstrap estimate for the F1 change was +3.39 percentage
points with a 95% confidence interval of [-3.18, +10.18]. The
prescription-clustered interval was [0.00, +7.21]. Both intervals and the
non-significant paired test should accompany any report of the point estimate.

## Reproduction boundary

The committed aggregate CSV/JSON files can be checked with
`python3 scripts/verify_published_results.py`. Re-running OCR and extraction
requires separately authorized access to the source images, annotations,
model checkpoint, and drug normalization database; see the repository-level
`REPRODUCIBILITY.md` for the required input contract.
