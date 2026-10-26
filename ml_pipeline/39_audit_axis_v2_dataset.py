"""Verify an axis-v2 dataset against the original LUT color values.

This is a value audit, not a perceptual or blind test.  It reconstructs every
unique source LUT in canonical [R, G, B, channel] axes, reloads the persisted
float16 target, and compares both cube nodes and deterministic interpolated
RGB probes.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import io
import json
from collections import defaultdict
from pathlib import Path

import numpy as np
from PIL import Image

from lut_axis_contract import load_float16_lut


PIPELINE_DIR = Path(__file__).resolve().parent
DEFAULT_DATASET_DIR = PIPELINE_DIR / "data" / "dataset_axis_v2_001"
DEFAULT_OUTPUT = PIPELINE_DIR / "reports" / "validation" / "dataset_axis_v2_001_value_audit.json"
def load_generator_module():
    path = PIPELINE_DIR / "2_generate_dataset.py"
    spec = importlib.util.spec_from_file_location("generate_dataset", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load generator: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_manifest(path: Path) -> list[dict]:
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def reconstruct_source(generator, record: dict) -> np.ndarray:
    source_path = Path(record["sourceLut"])
    kind = record["lutKind"]
    lut = (
        generator.load_bin_lut(str(source_path))
        if kind == "bin"
        else generator.load_cube_lut(str(source_path))
    )
    if lut.shape != (generator.LUT_DIM, generator.LUT_DIM, generator.LUT_DIM, 3):
        lut = generator.resample_lut(lut, generator.LUT_DIM)
    if kind.startswith("canon_"):
        lut = generator.compose_canon_srgb_lut(lut, kind)
    return lut.astype(np.float32)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dataset-dir", type=Path, default=DEFAULT_DATASET_DIR)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--max-storage-error", type=float, default=0.0)
    parser.add_argument("--max-probe-error", type=float, default=0.001)
    parser.add_argument("--expected-dataset-version", default="axis-v2-001")
    parser.add_argument("--expected-seed", type=int, default=42)
    args = parser.parse_args()

    dataset_dir = args.dataset_dir.resolve()
    records = read_manifest(dataset_dir / "manifest.jsonl")
    generator = load_generator_module()
    expected_metadata = {
        "datasetVersion": args.expected_dataset_version,
        "generationSeed": args.expected_seed,
        "lutAxisOrder": "r_fastest_rgb",
        "lutTensorAxes": "rgb_channel",
    }
    by_source: dict[str, list[dict]] = defaultdict(list)
    metadata_errors = []
    for record in records:
        by_source[record["sourceLut"]].append(record)
        mismatches = {
            key: {"expected": expected, "actual": record.get(key)}
            for key, expected in expected_metadata.items()
            if record.get(key) != expected
        }
        if mismatches:
            metadata_errors.append({"id": record.get("id"), "mismatches": mismatches})

    generator_sha = sha256(PIPELINE_DIR / "2_generate_dataset.py")
    recorded_generator_shas = {record.get("generatorCodeSha256") for record in records}
    if recorded_generator_shas != {generator_sha}:
        metadata_errors.append({
            "error": "generator_code_sha256_mismatch",
            "expected": generator_sha,
            "actual": sorted(str(value) for value in recorded_generator_shas),
        })

    canon_contract_sha = sha256(PIPELINE_DIR / "canon_color_contract.py")
    recorded_canon_contract_shas = {
        record.get("canonColorContractSha256")
        for record in records
        if str(record.get("lutKind", "")).startswith("canon_")
    }
    if recorded_canon_contract_shas != {canon_contract_sha}:
        metadata_errors.append({
            "error": "canon_color_contract_sha256_mismatch",
            "expected": canon_contract_sha,
            "actual": sorted(str(value) for value in recorded_canon_contract_shas),
        })

    rng = np.random.default_rng(20260828)
    probes = np.concatenate(
        [
            np.array(
                [
                    [0.0, 0.0, 0.0],
                    [1.0, 1.0, 1.0],
                    [1.0, 0.0, 0.0],
                    [0.0, 1.0, 0.0],
                    [0.0, 0.0, 1.0],
                    [0.5, 0.5, 0.5],
                ],
                dtype=np.float32,
            ),
            rng.random((250, 3), dtype=np.float32),
        ]
    )

    source_results = []
    failures = []
    for source, source_records in sorted(by_source.items()):
        record = source_records[0]
        source_path = Path(source)
        expected_sha = sha256(source_path)
        sha_values = {item.get("sourceLutSha256") for item in source_records}
        expected = reconstruct_source(generator, record)
        actual = load_float16_lut(
            dataset_dir / "luts" / f"{record['id']}.bin",
            expected_dim=generator.LUT_DIM,
        )
        node_error = np.abs(actual - expected)
        quantized_expected = expected.astype(np.float16).astype(np.float32)
        storage_error = np.abs(actual - quantized_expected)
        expected_probe = generator.apply_lut_to_colors(probes, expected)
        actual_probe = generator.apply_lut_to_colors(probes, actual)
        probe_error = np.abs(actual_probe - expected_probe)
        swapped_error = np.abs(actual - np.transpose(expected, (2, 1, 0, 3)))

        source_image = generator.NEUTRAL_IMAGES_DIR / record["sourceImage"]
        with Image.open(source_image) as image:
            resized = image.convert("RGB").resize(generator.TARGET_SIZE)
        neutral_pixels = np.asarray(resized, dtype=np.float32) / 255.0
        graded_pixels = generator.apply_lut_to_image(neutral_pixels, expected)
        expected_neutral = Image.fromarray((neutral_pixels * 255).astype(np.uint8))
        expected_graded = Image.fromarray((graded_pixels * 255).astype(np.uint8))
        neutral_buffer = io.BytesIO()
        graded_buffer = io.BytesIO()
        expected_neutral.save(neutral_buffer, format="JPEG", quality=95)
        expected_graded.save(graded_buffer, format="JPEG", quality=95)
        neutral_bytes_match = neutral_buffer.getvalue() == (
            dataset_dir / "neutral" / f"{record['id']}.jpg"
        ).read_bytes()
        graded_bytes_match = graded_buffer.getvalue() == (
            dataset_dir / "graded" / f"{record['id']}.jpg"
        ).read_bytes()
        result = {
            "sourceLut": source,
            "lutKind": record["lutKind"],
            "sampleCount": len(source_records),
            "sourceSha256Matches": sha_values == {expected_sha},
            "nodeMae": float(node_error.mean()),
            "nodeRmse": float(np.sqrt(np.mean(node_error ** 2))),
            "nodeMaxAbs": float(node_error.max()),
            "storageMaxAbs": float(storage_error.max()),
            "probeMae": float(probe_error.mean()),
            "probeMaxAbs": float(probe_error.max()),
            "unnecessaryRbSwapMae": float(swapped_error.mean()),
            "representativeNeutralJpegExact": neutral_bytes_match,
            "representativeGradedJpegExact": graded_bytes_match,
        }
        source_results.append(result)
        if (
            not result["sourceSha256Matches"]
            or result["storageMaxAbs"] > args.max_storage_error
            or result["probeMaxAbs"] > args.max_probe_error
            or not result["representativeNeutralJpegExact"]
            or not result["representativeGradedJpegExact"]
        ):
            failures.append(result)

    node_maxima = np.asarray([item["nodeMaxAbs"] for item in source_results])
    node_maes = np.asarray([item["nodeMae"] for item in source_results])
    probe_maxima = np.asarray([item["probeMaxAbs"] for item in source_results])
    storage_maxima = np.asarray([item["storageMaxAbs"] for item in source_results])
    swapped_maes = np.asarray([item["unnecessaryRbSwapMae"] for item in source_results])
    report = {
        "schemaVersion": 1,
        "method": "direct source-node and deterministic trilinear RGB-probe comparison",
        "datasetDir": str(dataset_dir),
        "manifestRecords": len(records),
        "uniqueSourceLuts": len(source_results),
        "probeColorCount": int(len(probes)),
        "thresholds": {
            "maxStorageAbsAfterFloat16Quantization": args.max_storage_error,
            "maxInterpolatedProbeAbs": args.max_probe_error,
        },
        "summary": {
            "metadataErrors": len(metadata_errors),
            "failedSourceLuts": len(failures),
            "sourceChecksumMatches": sum(item["sourceSha256Matches"] for item in source_results),
            "generatorCodeSha256Matches": recorded_generator_shas == {generator_sha},
            "canonColorContractSha256Matches": (
                recorded_canon_contract_shas == {canon_contract_sha}
            ),
            "representativeNeutralJpegExact": sum(item["representativeNeutralJpegExact"] for item in source_results),
            "representativeGradedJpegExact": sum(item["representativeGradedJpegExact"] for item in source_results),
            "nodeMaeMean": float(node_maes.mean()),
            "nodeMaxAbs": float(node_maxima.max()),
            "storageMaxAbsAfterFloat16Quantization": float(storage_maxima.max()),
            "probeMaxAbs": float(probe_maxima.max()),
            "unnecessaryRbSwapMaeMedian": float(np.median(swapped_maes)),
            "passed": not metadata_errors and not failures,
        },
        "metadataErrors": metadata_errors,
        "failures": failures,
        "sources": source_results,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report["summary"], indent=2))
    print(f"report={args.output}")
    return 0 if report["summary"]["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
