#!/usr/bin/env bash
set -euo pipefail

artifact_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "$artifact_root"

python3 scripts/verify_published_results.py
python3 -m unittest tests/test_public_artifact_consistency.py
