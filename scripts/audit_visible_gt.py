#!/usr/bin/env python3
"""Create a privacy-minimized audit summary for an authorized dataset.

This utility intentionally writes neither source capture identifiers nor medication
names. It is suitable for producing an aggregate provenance record that can be
shared independently from restricted clinical images and annotations.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def _load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def _capture_key(raw_identifier: str) -> str:
    return hashlib.sha256(raw_identifier.encode("utf-8")).hexdigest()[:16]


def build_audit_summary(
    manifest_path: Path,
    ground_truth_path: Path,
    output_path: Path,
    annotator: str,
    role: str,
    institution: str,
) -> dict[str, Any]:
    """Validate authorized inputs and write a de-identified audit summary."""
    manifest = _load_json(manifest_path)
    ground_truth = _load_json(ground_truth_path)
    if not isinstance(manifest, list):
        raise ValueError("Manifest must be a JSON list of capture records")
    if not isinstance(ground_truth, dict):
        raise ValueError("Ground truth must map capture identifiers to annotations")

    records: list[dict[str, Any]] = []
    total_instances = 0
    manifest_ids: set[str] = set()

    for item in manifest:
        if not isinstance(item, dict):
            raise ValueError("Each manifest entry must be a JSON object")
        raw_id = str(item.get("image_id", "")).strip()
        if not raw_id:
            raise ValueError("Every manifest entry requires image_id")
        if raw_id in manifest_ids:
            raise ValueError(f"Duplicate capture identifier in manifest: {raw_id}")
        manifest_ids.add(raw_id)

        annotation = ground_truth.get(raw_id)
        if not isinstance(annotation, dict):
            raise ValueError(f"Missing ground-truth record for capture: {raw_id}")
        visible_items = annotation.get("visible_medications", [])
        if not isinstance(visible_items, list):
            raise ValueError(f"visible_medications must be a list for capture: {raw_id}")

        instance_count = len(visible_items)
        total_instances += instance_count
        records.append(
            {
                "capture_key": _capture_key(raw_id),
                "visible_instance_count": instance_count,
                "verification_status": "HUMAN_REVIEW_RECORDED",
            }
        )

    unexpected = sorted(set(ground_truth) - manifest_ids)
    if unexpected:
        raise ValueError("Ground truth contains capture identifiers absent from the manifest")

    payload: dict[str, Any] = {
        "protocol_version": "2.0-public-summary",
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "annotator": {
            "name": annotator,
            "role": role,
            "institution": institution,
        },
        "summary": {
            "capture_count": len(records),
            "visible_instance_count": total_instances,
            "identifier_scheme": "sha256-prefix-16",
            "contains_medication_names": False,
        },
        "records": records,
    }

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    return payload


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--ground-truth", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--annotator", required=True)
    parser.add_argument("--role", default="Human annotator")
    parser.add_argument("--institution", default="Not specified")
    args = parser.parse_args()
    payload = build_audit_summary(
        args.manifest,
        args.ground_truth,
        args.out,
        args.annotator,
        args.role,
        args.institution,
    )
    print(
        f"Wrote {payload['summary']['capture_count']} de-identified capture records "
        f"to {args.out}"
    )


if __name__ == "__main__":
    main()
