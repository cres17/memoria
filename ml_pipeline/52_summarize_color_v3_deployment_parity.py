"""Summarize immutable color-v3 export/parity evidence into the G5 gate."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--onnx", type=Path, required=True)
    parser.add_argument("--tflite", type=Path, required=True)
    parser.add_argument("--onnx-report", type=Path, required=True)
    parser.add_argument("--tflite-report", type=Path, required=True)
    parser.add_argument("--benchmark-report", type=Path, required=True)
    parser.add_argument("--axis-report", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    onnx = json.loads(args.onnx_report.read_text())
    tflite = json.loads(args.tflite_report.read_text())
    benchmark = json.loads(args.benchmark_report.read_text())
    axis = json.loads(args.axis_report.read_text())
    onnx_error = onnx["onnx"]["max_abs_error_vs_pytorch"]
    tflite_error = tflite["tflite"]["max_abs_error_vs_pytorch"]
    limit = tflite["tflite"]["max_allowed_abs_error"]
    shapes_pass = (
        onnx["onnx"]["input"]["shape"] == [1, 3, 256, 256]
        and onnx["onnx"]["output"]["shape"] == [1, 17, 17, 17, 3]
        and tflite["tflite"]["input"]["shape"] == [1, 3, 256, 256]
        and tflite["tflite"]["output"]["shape"] == [1, 17, 17, 17, 3]
    )
    passed = onnx_error <= 1e-5 and tflite_error <= limit and shapes_pass and axis["passed"]
    result = {
        "schemaVersion": 1,
        "gate": "G5 desktop deployment parity",
        "passed": passed,
        "artifactSha256": {
            "checkpoint": sha256(args.checkpoint),
            "onnx": sha256(args.onnx),
            "tflite": sha256(args.tflite),
        },
        "artifactBytes": {
            "onnx": args.onnx.stat().st_size,
            "tflite": args.tflite.stat().st_size,
        },
        "onnxMaxAbsErrorVsPytorch": onnx_error,
        "tfliteMaxAbsErrorVsPytorch": tflite_error,
        "tfliteErrorLimit": limit,
        "tfliteLimitUtilization": tflite_error / limit,
        "tensorShapesPassed": shapes_pass,
        "axisContractPassed": axis["passed"],
        "desktopTfliteBenchmark": benchmark["inference"],
        "remainingGate": "G6 iOS/Android real-device latency, memory, export, and permission validation",
        "threeCharacterReleaseRatingKo": "조건부",
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))
    if not passed:
        raise SystemExit(1)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
