"""P4 basis-LUT experiment benchmark.

Reports the quality proxy (small-LUT RMSE), CPU p50/p95 inference latency, and
Python-visible peak allocation using the same validation pairs for every run.
Pass --baseline-json from the algorithmic benchmark to produce one comparable
JSON document; this script never decides product routing by itself.
"""

import argparse
import importlib
import json
import time
import tracemalloc
from pathlib import Path

import numpy as np
import torch

train = importlib.import_module("8_train_basis")


def percentile(values, q):
    return float(np.percentile(np.asarray(values, dtype=np.float64), q))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--runs", type=int, default=30)
    parser.add_argument("--baseline-json", type=Path)
    parser.add_argument("--output", type=Path, default=Path("exports/basis_benchmark.json"))
    args = parser.parse_args()

    mean, bases, coefficient_scales = train.load_basis()
    checkpoint = torch.load(train.MODEL_PATH, map_location="cpu")
    model = train.BasisWeightNet(int(checkpoint["num_bases"]))
    model.load_state_dict(checkpoint["state_dict"])
    model.eval()
    dataset = train.BasisDataset(train.DATASET_DIR, mean, bases, coefficient_scales)

    example, _ = dataset[0]
    batch = example.unsqueeze(0)
    for _ in range(5):
        model(batch)
    tracemalloc.start()
    latencies_ms = []
    with torch.no_grad():
        for _ in range(args.runs):
            started = time.perf_counter()
            model(batch)
            latencies_ms.append((time.perf_counter() - started) * 1000.0)
    _, peak = tracemalloc.get_traced_memory()
    tracemalloc.stop()

    coefficient_errors = []
    lut_errors = []
    basis_tensor = torch.from_numpy(bases)
    with torch.no_grad():
        for image, target in torch.utils.data.DataLoader(dataset, batch_size=16):
            predicted = model(image)
            coefficient_errors.append(torch.mean((predicted - target) ** 2).sqrt().item())
            lut_errors.append(
                torch.mean((predicted @ basis_tensor - target @ basis_tensor) ** 2).sqrt().item()
            )

    report = {
        "experiment": "basis_residual_lut_v1",
        "basisDim": train.BASIS_DIM,
        "numBases": int(bases.shape[0]),
        "coefficientBound": train.COEFFICIENT_BOUND,
        "quality": {
            "normalizedCoefficientRmse": float(np.mean(coefficient_errors)),
            "smallLutRmse": float(np.mean(lut_errors)),
        },
        "latencyMs": {"p50": percentile(latencies_ms, 50), "p95": percentile(latencies_ms, 95)},
        "memory": {"pythonVisiblePeakBytes": peak},
        "routing": "experiment_only_requires_common_lut_safety_gate",
    }
    if args.baseline_json and args.baseline_json.exists():
        report["baseline"] = json.loads(args.baseline_json.read_text())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
