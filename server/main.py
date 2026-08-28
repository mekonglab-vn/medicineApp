"""
FastAPI server for MedicineApp.

Endpoints:
    GET  /api/health              → Server status
    GET  /api/drug-info/{name}    → Drug information lookup
    GET  /api/drug-metadata/{name} → Drug metadata enrichment
    POST /api/scan-prescription   → Scan prescription image

Run:
    uvicorn server.main:app --host 0.0.0.0 --port 8000 --reload
"""

import os

# PaddlePaddle 3.3.0 fixes — MUST be set before any paddle import
os.environ.setdefault("FLAGS_enable_pir_api", "0")
os.environ.setdefault("PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK", "True")

import asyncio
import logging
import platform
import socket
import sys
from pathlib import Path
from contextlib import asynccontextmanager
from datetime import datetime, timezone

from typing import Optional
from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from fastapi.middleware.cors import CORSMiddleware

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

ROOT = Path(__file__).parent.parent
DRUG_DB_PATH = ROOT / "server" / "data" / "drug_db.json"

# Global state
_drug_service = None
_pipeline = None
_pipeline_last_error = None
_pipeline_loaded_at = None

# VĐ7: Semaphore giới hạn GPU concurrent (RTX 3050 4GB)
# Chỉ cho phép 1 scan chạy đồng thời để tránh OOM
scan_semaphore = asyncio.Semaphore(1)


def _get_drug_service():
    global _drug_service
    if _drug_service is None:
        from server.services.drug_service import DrugService

        _drug_service = DrugService()
    return _drug_service


def _get_pipeline():
    """Lazy load the AI pipeline (heavy models)."""
    global _pipeline, _pipeline_last_error, _pipeline_loaded_at
    if _pipeline is None:
        try:
            from core.pipeline import MedicinePipeline

            # Ép khởi tạo pipeline chạy 100% trên CPU cho thử nghiệm
            _pipeline = MedicinePipeline(device="cpu")
            _pipeline_last_error = None
            _pipeline_loaded_at = datetime.now(timezone.utc).isoformat()
            logger.info("AI pipeline loaded (Forced CPU mode)")
        except Exception as e:
            _pipeline_last_error = str(e)
            logger.warning(f"AI pipeline not available: {e}")
    return _pipeline


def _runtime_info() -> dict:
    expected_venv = ROOT / "venv"
    expected_venv_bin = expected_venv / "bin"
    expected_venv_resolved = str(expected_venv.resolve())
    expected_bin_prefix = str(expected_venv_bin.resolve())
    python_exec_raw = sys.executable
    python_exec_resolved = str(Path(sys.executable).resolve())
    sys_prefix_resolved = str(Path(sys.prefix).resolve())
    using_expected_venv = (
        sys_prefix_resolved == expected_venv_resolved
        or sys_prefix_resolved.startswith(f"{expected_venv_resolved}{os.sep}")
        or python_exec_raw.startswith(f"{expected_bin_prefix}{os.sep}")
        or python_exec_raw.startswith(expected_bin_prefix)
    )

    return {
        "service": "medicineapp-fastapi",
        "pid": os.getpid(),
        "hostname": socket.gethostname(),
        "cwd": str(Path.cwd()),
        "root_dir": str(ROOT),
        "python_executable": python_exec_raw,
        "python_executable_resolved": python_exec_resolved,
        "python_version": platform.python_version(),
        "sys_prefix": sys.prefix,
        "sys_prefix_resolved": sys_prefix_resolved,
        "virtual_env": os.environ.get("VIRTUAL_ENV"),
        "is_venv": sys.prefix != sys.base_prefix,
        "expected_venv": str(expected_venv),
        "expected_venv_exists": expected_venv.exists(),
        "using_expected_venv": using_expected_venv,
        "inside_docker": Path("/.dockerenv").exists(),
    }


@asynccontextmanager
async def lifespan(app: FastAPI):
    # VĐ7: Pre-load services + warm-up AI pipeline
    _get_drug_service()

    pipeline = _get_pipeline()
    if pipeline:
        try:
            import numpy as np

            pipeline.scan_prescription_app("1. Paracetamol 500mg")
            logger.info("✅ Pipeline warmed up successfully")
        except Exception as e:
            logger.warning(
                f"⚠️ Warm-up failed: {e} — pipeline will lazy-load on first request"
            )

    logger.info("MedicineApp server started")
    yield
    logger.info("MedicineApp server stopped")


app = FastAPI(
    title="MedicineApp API",
    description="AI-powered prescription scanning",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Health ────────────────────────────────────────────


@app.get("/api/health")
async def health():
    svc = _get_drug_service()
    pipeline = _get_pipeline()
    return {
        "status": "ok",
        "drug_db": svc.count(),
        "ai_ready": pipeline is not None,
        "runtime": _runtime_info(),
        "scan_runtime": {
            "mode": "full_ai" if pipeline is not None else "pipeline_unavailable",
            "pipeline_loaded": pipeline is not None,
            "pipeline_loaded_at": _pipeline_loaded_at,
            "pipeline_last_error": _pipeline_last_error,
            "scan_semaphore_limit": 1,
        },
    }


# ── Drug Info ─────────────────────────────────────────


@app.get("/api/drug-info/{name}")
async def drug_info(name: str, online: bool = False):
    """
    Look up drug information by name.

    Args:
        name: Drug name (e.g. Paracetamol-500mg)
        online: If True, also query RxNorm + DailyMed APIs
    """
    svc = _get_drug_service()

    if online:
        result = await svc.lookup_online(name)
        if result:
            return result
    else:
        result = svc.lookup(name)
        if result:
            return result

    raise HTTPException(404, f"Drug not found: {name}")


@app.get("/api/drug-metadata/{name}")
async def drug_metadata(name: str):
    """Enrich a drug name with structured metadata for Phase B."""
    svc = _get_drug_service()
    return await svc.enrich_metadata(name)


@app.get("/api/drugs")
async def list_drugs(q: str = "", limit: int = 20):
    """List or search local drug DB."""
    svc = _get_drug_service()

    if not q:
        return {
            "drugs": list(svc.get_all().keys()),
            "count": svc.count(),
        }

    matches = svc.search(q, limit=limit)
    return {
        "results": matches,
        "count": len(matches),
        "query": q,
    }


@app.get("/api/drugs/search-online")
async def search_drugs_online(q: str, limit: int = 5):
    """
    Search drugs online using OpenFDA API.

    Returns brand name, generic name, dosage form,
    active ingredients, and pharmacological class.
    Free API, no key required.
    """
    if not q or len(q) < 2:
        raise HTTPException(400, "Query too short (min 2 chars)")

    svc = _get_drug_service()
    results = await svc.search_online(q, limit=limit)

    if not results:
        local = svc.search(q, limit=limit)
        if local:
            return {
                "results": local,
                "count": len(local),
                "query": q,
                "source": "local",
            }
        raise HTTPException(404, f"No drugs found for: {q}")

    return {
        "results": results,
        "count": len(results),
        "query": q,
        "source": "openfda",
    }


# ── Vietnamese Drug APIs (ddi.lab.io.vn) ──────────────


@app.get("/api/drugs/search-vn")
async def search_vn_drugs(q: str, limit: int = 10):
    """
    Search Vietnamese drugs from ddi.lab.io.vn.

    Returns drug name, active ingredients, dosage form,
    packaging, manufacturer — all in Vietnamese.
    Free API, no key required.
    """
    if not q or len(q) < 2:
        raise HTTPException(400, "Query too short (min 2 chars)")

    svc = _get_drug_service()
    results = await svc.search_vn(q, limit=limit)

    if not results:
        raise HTTPException(404, f"No VN drugs found for: {q}")

    return {
        "results": results,
        "count": len(results),
        "query": q,
        "source": "ddi.lab.io.vn",
    }


@app.get("/api/drugs/suggest-vn")
async def suggest_vn_drugs(q: str):
    """
    Vietnamese drug name autocomplete.

    Returns list of matching drug names.
    """
    if not q or len(q) < 2:
        raise HTTPException(400, "Query too short (min 2 chars)")

    svc = _get_drug_service()
    suggestions = await svc.suggest_vn(q)
    return {"suggestions": suggestions, "query": q}


@app.get("/api/drugs/interactions")
async def drug_interactions(ingredient: str):
    """
    Get drug-drug interactions for an active ingredient.

    Data from Vietnamese drug interaction database.
    Returns interactions grouped by severity.
    """
    if not ingredient or len(ingredient) < 2:
        raise HTTPException(400, "Ingredient name too short")

    svc = _get_drug_service()
    result = await svc.interactions(ingredient)

    if not result:
        raise HTTPException(404, f"No interactions found for: {ingredient}")

    return result


# ── Scan Prescription ─────────────────────────────────


@app.post("/api/scan-prescription")
async def scan_prescription(
    ocr_text: Optional[str] = Form(None),
    ocr_lines: Optional[str] = Form(None),
    layout_strategy: str = Form("p3_medication_bands"),
):
    """
    Scan prescription text/lines → extract drug list.

    Receive structured OCR lines or OCR text from client and get back
    a list of detected medications.
    """
    if not ocr_text and not ocr_lines:
        raise HTTPException(
            status_code=422,
            detail={
                "code": "MISSING_OCR_PAYLOAD",
                "message": "Either ocr_text or ocr_lines must be provided.",
            },
        )

    pipeline = _get_pipeline()
    if pipeline is None:
        raise HTTPException(
            status_code=503,
            detail={
                "code": "PIPELINE_UNAVAILABLE",
                "message": "AI pipeline is unavailable. Please try again later.",
            },
        )

    try:
        result = pipeline.scan_prescription_app(
            ocr_text=ocr_text,
            ocr_lines=ocr_lines,
            layout_strategy=layout_strategy,
        )
    except Exception as exc:
        logger.exception("Prescription pipeline execution failed")
        raise HTTPException(
            status_code=500,
            detail={
                "code": "PIPELINE_EXECUTION_FAILED",
                "message": "AI pipeline failed while processing the prescription.",
            },
        ) from exc

    if isinstance(result, dict) and result.get("error"):
        raise HTTPException(
            status_code=422,
            detail={
                "code": "SCAN_PROCESSING_FAILED",
                "message": str(result["error"]),
            },
        )
    return result
