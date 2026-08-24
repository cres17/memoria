"""Audit whether semantic masks are ready to become a conditional-LUT training input.

This is deliberately a read-only readiness gate.  It does not substitute
heuristic masks for semantic labels or begin a semantic training run without a
licensed, versioned segmentation model and a matching Python inference path.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import re
from collections import Counter
from pathlib import Path


PIPELINE_DIR = Path(__file__).resolve().parent
REPOSITORY_DIR = PIPELINE_DIR.parent
FAMILY_SPLIT = PIPELINE_DIR / "reports" / "splits" / "conditional_lut_family_holdout.jsonl"
DART_SEGMENTER = REPOSITORY_DIR / "lib" / "ai" / "models" / "segmenter_native.dart"
DEFAULT_OUTPUT = PIPELINE_DIR / "reports" / "baselines" / "semantic_mask_readiness_audit_001.json"
SELECTED_MODEL = PIPELINE_DIR / "models" / "selfie_multiclass.tflite"
SELECTED_MODEL_SHA256 = "c6748b1253a99067ef71f7e26ca71096cd449baefa8f101900ea23016507e0e0"
SEMANTIC_CACHE_SUMMARY = PIPELINE_DIR / "reports" / "semantic_masks" / "selfie_multiclass_256_softmax_64" / "summary.json"


def read_split_summary(path: Path) -> dict:
    records = [json.loads(line) for line in path.read_text().splitlines() if line]
    by_split = Counter(record["split"] for record in records)
    luts_by_split = {
        split: len({record["sourceLut"] for record in records if record["split"] == split})
        for split in sorted(by_split)
    }
    families_by_split = {
        split: len({record["lutFamily"] for record in records if record["split"] == split})
        for split in sorted(by_split)
    }
    return {
        "records": dict(sorted(by_split.items())),
        "source_luts": luts_by_split,
        "families": families_by_split,
    }


def dart_semantic_contract(path: Path) -> dict:
    text = path.read_text()
    enum_match = re.search(r"enum SemanticClass \{(.*?)\}", text, flags=re.DOTALL)
    if enum_match is None:
        raise ValueError(f"SemanticClass enum missing from {path}")
    classes = re.findall(r"^\s*([A-Za-z][A-Za-z0-9_]*)\s*,", enum_match.group(1), flags=re.MULTILINE)
    input_match = re.search(r"static const int _inWH = (\d+);", text)
    output_match = re.search(r"// Output \[1, (\d+), (\d+), (\d+)\]", text)
    return {
        "path": str(path),
        "classes": classes,
        "input_size": int(input_match.group(1)) if input_match else None,
        "declared_output": [int(value) for value in output_match.groups()] if output_match else None,
        "mask_semantics": "per-class score, resized to image resolution and feathered; not an argmax-only training label",
    }


def model_artifacts(repository: Path) -> list[str]:
    return sorted(
        str(path.relative_to(repository))
        for path in repository.rglob("*.tflite")
        if "basis_weights.tflite" not in str(path)
    )


def sha256(path: Path) -> str | None:
    if not path.exists():
        return None
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description="Audit semantic-mask readiness without changing training data.")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    artifacts = model_artifacts(REPOSITORY_DIR)
    inference_packages = {
        package: importlib.util.find_spec(package) is not None
        for package in ("ai_edge_litert", "tensorflow", "tflite_runtime", "mediapipe")
    }
    selected_hash = sha256(SELECTED_MODEL)
    selected_model_verified = selected_hash == SELECTED_MODEL_SHA256
    cache_summary = json.loads(SEMANTIC_CACHE_SUMMARY.read_text()) if SEMANTIC_CACHE_SUMMARY.exists() else None
    full_cache_ready = bool(
        cache_summary
        and cache_summary.get("completion") == "full"
        and cache_summary.get("records_requested") == 3000
        and cache_summary.get("model_sha256") == SELECTED_MODEL_SHA256
    )
    if not selected_model_verified:
        status = "not_ready"
        reason = "The selected model is absent or does not match its pinned SHA-256."
    elif not any(inference_packages.values()):
        status = "model_selected_runtime_missing"
        reason = "The selected model is pinned, but no Python TFLite/MediaPipe inference runtime is installed for deterministic mask generation."
    elif full_cache_ready:
        status = "ready_for_semantic_ablation"
        reason = "The selected model, Python inference runtime, and full checksum-pinned cache are available; semantic controlled ablation may proceed."
    else:
        status = "ready_for_mask_cache_implementation"
        reason = "The selected model and a Python inference runtime are available; cache implementation may proceed."
    report = {
        "schema_version": 1,
        "experiment_id": "SEMANTIC-MASK-READINESS-AUDIT-001",
        "scope": "read-only readiness gate for adding semantic masks to the direct family-holdout MVP",
        "family_holdout_data": read_split_summary(FAMILY_SPLIT),
        "existing_app_contract": dart_semantic_contract(DART_SEGMENTER),
        "training_runtime": {
            "segmentation_model_artifacts_excluding_unrelated_basis_export": artifacts,
            "python_inference_packages_available": inference_packages,
            "ml_pipeline_mask_generator_exists": False,
            "semantic_cache_summary": cache_summary,
        },
        "selected_model": {
            "name": "MediaPipe Selfie Multiclass Segmentation",
            "path": str(SELECTED_MODEL),
            "source": "LiteRT community mirror of the Google LiteRT codelab model",
            "license": "Apache-2.0 permitted by project decision",
            "expected_sha256": SELECTED_MODEL_SHA256,
            "actual_sha256": selected_hash,
            "sha256_verified": selected_model_verified,
            "input_output_contract": "float32 256x256 RGB input and six per-pixel classes: background, hair, bodySkin, faceSkin, clothes, other",
        },
        "decision": {
            "status": status,
            "reason": reason,
            "prohibited_shortcut": "Do not train with oval, color-threshold, or all-zero stand-in masks and call the result semantic disentanglement.",
        },
        "required_entry_contract": {
            "model": "fixed model name, version/hash, code+weight license, input normalization, output class map, and confidence semantics",
            "data": "mask cache keyed by reference image checksum and model hash; immutable train/validation/test family partition membership",
            "architecture": "keep the selected direct 17^3 LUT decoder unchanged; compare global Style Encoder against global-plus-semantic pooled features as one controlled factor",
            "evaluation": "same family-holdout ΔE sample/LUT-macro, monotonicity/OOG, plus subject-present/absent strata and same-LUT cross-scene Style Code consistency",
            "selection": "validation-only selection; test once after the protocol is frozen",
        },
        "next_authorized_action": "Implement the fixed-protocol semantic-pooled Style Code ablation; retain the direct 17^3 LUT decoder and select only on family-holdout validation.",
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(f"semantic mask readiness audit complete -> {args.output}")


if __name__ == "__main__":
    main()
