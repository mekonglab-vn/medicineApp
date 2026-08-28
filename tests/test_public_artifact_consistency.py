from __future__ import annotations

import subprocess
import sys
import unittest
from pathlib import Path


class PublicArtifactConsistencyTest(unittest.TestCase):
    def test_published_results_and_privacy_boundary(self) -> None:
        root = Path(__file__).resolve().parents[1]
        completed = subprocess.run(
            [sys.executable, str(root / "scripts/verify_published_results.py")],
            cwd=root,
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        self.assertIn("PASS:", completed.stdout)


if __name__ == "__main__":
    unittest.main()
