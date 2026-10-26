"""Verify the LUT axis contract across persisted files and pipeline loaders.

The app persists RGB triples with R as the fastest-changing cube coordinate:

    flat_index = (r + g * dim + b * dim * dim) * 3 + channel

NumPy's default C-order reshape exposes that buffer as [B, G, R, channel].
This diagnostic writes an identity LUT in the app contract, loads it through
the current production-facing Python paths, and records which paths preserve
the intended [R, G, B, channel] tensor axes.

The command is intentionally usable before the migration is complete. Without
``--strict`` it always writes a report; with ``--strict`` it exits non-zero
until every required contract check passes.
"""

from __future__ import annotations

import argparse
import importlib
import json
import tempfile
from pathlib import Path

import numpy as np

from lut_axis_contract import to_r_fastest_values


PIPELINE_DIR = Path(__file__).resolve().parent
DEFAULT_OUTPUT = (
    PIPELINE_DIR / "reports" / "validation" / "lut_axis_contract_verification_001.json"
)


def identity_lut(dim: int) -> np.ndarray:
    values = np.linspace(0.0, 1.0, dim, dtype=np.float32)
    red, green, blue = np.meshgrid(values, values, values, indexing="ij")
    return np.stack((red, green, blue), axis=-1)


def r_fastest_buffer(lut_rgb_axes: np.ndarray) -> np.ndarray:
    """Flatten [R,G,B,C] axes into the buffer order consumed by the app."""
    return np.transpose(lut_rgb_axes, (2, 1, 0, 3)).reshape(-1, 3)


def app_reconstruct(buffer: np.ndarray, dim: int) -> np.ndarray:
    """Reconstruct the cube using the exact app flat-index formula."""
    flat = buffer.reshape(-1)
    result = np.empty((dim, dim, dim, 3), dtype=np.float32)
    for red in range(dim):
        for green in range(dim):
            for blue in range(dim):
                for channel in range(3):
                    index = (
                        red + green * dim + blue * dim * dim
                    ) * 3 + channel
                    result[red, green, blue, channel] = flat[index]
    return result


def max_abs_error(actual: np.ndarray, expected: np.ndarray) -> float:
    return float(np.max(np.abs(actual.astype(np.float32) - expected.astype(np.float32))))


def check(name: str, actual: np.ndarray, expected: np.ndarray, tolerance: float) -> dict:
    error = max_abs_error(actual, expected)
    return {
        "name": name,
        "max_abs_error": error,
        "tolerance": tolerance,
        "passed": bool(error <= tolerance),
    }


def write_cube(path: Path, dim: int, buffer: np.ndarray) -> None:
    lines = ["TITLE \"Memoria axis contract probe\"", f"LUT_3D_SIZE {dim}"]
    lines.extend(" ".join(f"{float(value):.8f}" for value in row) for row in buffer)
    path.write_text("\n".join(lines) + "\n")


def run(output: Path) -> dict:
    generator = importlib.import_module("2_generate_dataset")
    evaluator = importlib.import_module("17_evaluate_conditional_lut")

    dim = 3
    tolerance = 1e-3  # float16 persistence tolerance
    expected = identity_lut(dim)
    persisted = to_r_fastest_values(expected, dtype=np.float16)
    probes = np.asarray(
        (
            (1.0, 0.0, 0.0),
            (0.0, 1.0, 0.0),
            (0.0, 0.0, 1.0),
            (0.75, 0.25, 0.10),
        ),
        dtype=np.float32,
    )

    with tempfile.TemporaryDirectory(prefix="memoria-lut-axis-") as directory:
        root = Path(directory)
        bin_path = root / "identity_r_fastest.bin"
        cube_path = root / "identity_r_fastest.cube"
        persisted.tofile(bin_path)
        write_cube(cube_path, dim, persisted.astype(np.float32))

        evaluator_loaded = evaluator.load_lut(bin_path)
        original_generator_dim = generator.LUT_DIM
        generator.LUT_DIM = dim
        try:
            generator_bin_loaded = generator.load_bin_lut(str(bin_path))
            generator_cube_loaded = generator.load_cube_lut(str(cube_path))
        finally:
            generator.LUT_DIM = original_generator_dim

    app_loaded = app_reconstruct(persisted, dim)
    required_checks = [
        check("app_r_fastest_index", app_loaded, expected, tolerance),
        check("evaluator_load_lut_rgb_axes", evaluator_loaded, expected, tolerance),
        check("dataset_load_bin_lut_rgb_axes", generator_bin_loaded, expected, tolerance),
        check("dataset_load_cube_lut_rgb_axes", generator_cube_loaded, expected, tolerance),
        check(
            "identity_probe_outputs",
            evaluator.apply_lut(probes, evaluator_loaded),
            probes,
            tolerance,
        ),
    ]

    probe_outputs = evaluator.apply_lut(probes, evaluator_loaded)
    swapped = np.transpose(evaluator_loaded, (2, 1, 0, 3))
    swapped_error = max_abs_error(swapped, expected)
    report = {
        "schema_version": 1,
        "experiment_id": "LUT-AXIS-CONTRACT-001",
        "contract": {
            "tensor_axes": "[R,G,B,channel]",
            "persisted_axis_order": "r_fastest_rgb",
            "flat_index": "(r + g * dim + b * dim * dim) * 3 + channel",
            "numpy_c_order_observation": "reshape exposes an R-fastest buffer as [B,G,R,channel]",
        },
        "fixture": {
            "dim": dim,
            "kind": "identity LUT",
            "probe_inputs_rgb": probes.tolist(),
            "evaluator_probe_outputs_rgb": probe_outputs.tolist(),
        },
        "required_checks": required_checks,
        "axis_swap_guardrail": {
            "name": "unnecessary_r_b_swap_is_detected",
            "max_abs_error": swapped_error,
            "passed": bool(swapped_error > tolerance),
        },
        "passed": bool(all(item["passed"] for item in required_checks)),
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    return report


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Verify Memoria's persisted LUT axis contract across Python loaders."
    )
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Exit non-zero unless all production-facing loader checks pass.",
    )
    args = parser.parse_args()
    report = run(args.output)
    print(json.dumps({"passed": report["passed"], "output": str(args.output)}))
    if args.strict and not report["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
