import asyncio
import io
import sys
from pathlib import Path
from unittest.mock import patch

import cv2
import numpy as np
from fastapi import HTTPException, UploadFile


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from server import main


def scan_with(pipeline):
    async def run():
        upload = UploadFile(filename="prescription.png", file=io.BytesIO(b"image"))
        decoded = np.zeros((1, 1, 3), dtype=np.uint8)
        with patch.object(main, "_get_pipeline", return_value=pipeline), patch.object(
            cv2, "imdecode", return_value=decoded
        ):
            return await main.scan_prescription(upload)

    return asyncio.run(run())


def assert_failure(pipeline, status_code, code):
    try:
        scan_with(pipeline)
    except HTTPException as exc:
        assert exc.status_code == status_code
        assert exc.detail["code"] == code
        assert isinstance(exc.detail["message"], str)
        assert exc.detail["message"]
    else:
        raise AssertionError("Expected scan endpoint to raise HTTPException")


def test_initialization_failure_is_structured_503():
    assert_failure(None, 503, "PIPELINE_UNAVAILABLE")


def test_runtime_exception_is_structured_500():
    class FailingPipeline:
        def scan_prescription_app(self, *args, **kwargs):
            raise RuntimeError("inference exploded")

    assert_failure(FailingPipeline(), 500, "PIPELINE_EXECUTION_FAILED")


def test_terminal_pipeline_error_is_structured_422():
    class TerminalErrorPipeline:
        def scan_prescription_app(self, *args, **kwargs):
            return {"error": "No prescription region could be processed"}

    assert_failure(TerminalErrorPipeline(), 422, "SCAN_PROCESSING_FAILED")


def test_success_payload_is_returned_unchanged():
    expected = {
        "medications": [],
        "quality_state": "WARNING",
        "rejected": False,
    }

    class SuccessfulPipeline:
        def scan_prescription_app(self, *args, **kwargs):
            return expected

    assert scan_with(SuccessfulPipeline()) is expected


if __name__ == "__main__":
    test_initialization_failure_is_structured_503()
    test_runtime_exception_is_structured_500()
    test_terminal_pipeline_error_is_structured_422()
    test_success_payload_is_returned_unchanged()
    print("pipeline failure contract: 4 passed")
