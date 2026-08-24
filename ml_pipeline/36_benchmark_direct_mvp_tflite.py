"""Measure desktop TFLite inference for the app's exact direct-MVP contract."""

from __future__ import annotations

import argparse
import json
import time
from pathlib import Path

import numpy as np
import tensorflow as tf


PIPELINE_DIR = Path(__file__).resolve().parent
DEPLOYMENT_DIR = PIPELINE_DIR / "reports" / "deployment"
MODEL = DEPLOYMENT_DIR / "direct_mvp_family_holdout_smooth_010_001_fp16.tflite"
REPORT = DEPLOYMENT_DIR / "direct_mvp_tflite_benchmark_001.json"


def summary(values: list[float]) -> dict[str, float | int]:
    array = np.asarray(values, dtype=np.float64)
    return {"samples": len(values), "mean_ms": float(array.mean()), "p50_ms": float(np.percentile(array, 50)), "p95_ms": float(np.percentile(array, 95))}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", type=Path, default=MODEL)
    parser.add_argument("--output", type=Path, default=REPORT)
    parser.add_argument("--warmup", type=int, default=3)
    parser.add_argument("--samples", type=int, default=20)
    parser.add_argument("--threads", type=int, default=2)
    args = parser.parse_args()
    if args.warmup < 0 or args.samples <= 0 or args.threads <= 0:
        parser.error("warmup must be non-negative; samples and threads must be positive")

    interpreter = tf.lite.Interpreter(model_path=str(args.model), num_threads=args.threads)
    interpreter.allocate_tensors()
    input_detail = interpreter.get_input_details()[0]
    output_detail = interpreter.get_output_details()[0]
    reference = np.linspace(-2.0, 2.0, int(np.prod(input_detail["shape"])), dtype=np.float32).reshape(input_detail["shape"])
    for _ in range(args.warmup):
        interpreter.set_tensor(input_detail["index"], reference)
        interpreter.invoke()
    values = []
    for _ in range(args.samples):
        start = time.perf_counter()
        interpreter.set_tensor(input_detail["index"], reference)
        interpreter.invoke()
        interpreter.get_tensor(output_detail["index"])
        values.append((time.perf_counter() - start) * 1000.0)
    report = {
        "schema_version": 1,
        "experiment_id": "DIRECT-MVP-TFLITE-BENCHMARK-001",
        "model": str(args.model),
        "model_bytes": args.model.stat().st_size,
        "threads": args.threads,
        "input": {"shape": input_detail["shape"].tolist(), "dtype": input_detail["dtype"].__name__},
        "output": {"shape": output_detail["shape"].tolist(), "dtype": output_detail["dtype"].__name__},
        "inference": summary(values),
        "contract": "Desktop TensorFlow Lite/XNNPACK benchmark only; it is not an Android or iOS device latency claim.",
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(f"direct MVP TFLite benchmark complete -> {args.output}")


if __name__ == "__main__":
    main()
