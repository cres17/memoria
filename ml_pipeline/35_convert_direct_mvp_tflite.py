"""Convert the validated direct-MVP checkpoint to float16-weight TFLite.

litert-torch converts the PyTorch model directly, so this step no longer needs
ONNX → onnx-tf → TensorFlow. Run 34_export_direct_mvp_onnx.py first: it writes
the PyTorch parity fixture this script checks the TFLite output against.
"""

from __future__ import annotations

import argparse
import importlib
import json
from pathlib import Path

import numpy as np
import torch

from tflite_export import convert_fp16, run_tflite


PIPELINE_DIR = Path(__file__).resolve().parent
DEPLOYMENT_DIR = PIPELINE_DIR / "reports" / "deployment"
onnx_export = importlib.import_module("34_export_direct_mvp_onnx")
CHECKPOINT = onnx_export.CHECKPOINT
TFLITE_MODEL = DEPLOYMENT_DIR / "direct_mvp_family_holdout_smooth_010_001_fp16.tflite"
REPORT_OUTPUT = DEPLOYMENT_DIR / "direct_mvp_tflite_conversion_001.json"
PARITY_FIXTURE = DEPLOYMENT_DIR / "direct_mvp_onnx_parity_fixture_001.npz"
MAX_FP16_ABS_ERROR = 2e-3


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--checkpoint", type=Path, default=CHECKPOINT)
    parser.add_argument("--tflite-model", type=Path, default=TFLITE_MODEL)
    parser.add_argument("--output", type=Path, default=REPORT_OUTPUT)
    parser.add_argument("--parity-fixture", type=Path, default=PARITY_FIXTURE)
    args = parser.parse_args()
    if not args.checkpoint.exists():
        raise FileNotFoundError(f"checkpoint is missing: {args.checkpoint}")
    if not args.parity_fixture.exists():
        raise FileNotFoundError(f"PyTorch parity fixture is missing (run 34 first): {args.parity_fixture}")

    model = onnx_export.LUTOnlyWrapper(onnx_export.load_model(args.checkpoint)).eval()
    with np.load(args.parity_fixture) as fixture:
        reference = fixture["style_image"]
        pytorch_output = fixture["pytorch_lut"]
    with torch.inference_mode():
        current = model(torch.from_numpy(reference)).numpy()
    if float(np.max(np.abs(current - pytorch_output))) > 1e-5:
        raise RuntimeError("checkpoint output no longer matches the parity fixture; rerun 34 first")

    convert_fp16(model, torch.from_numpy(reference), args.tflite_model)
    tflite_output, input_detail, output_detail = run_tflite(args.tflite_model, reference)
    if tuple(tflite_output.shape) != tuple(pytorch_output.shape):
        raise RuntimeError(f"TFLite output shape {tflite_output.shape} differs from PyTorch {pytorch_output.shape}")
    tflite_error = float(np.max(np.abs(pytorch_output - tflite_output)))
    if tflite_error > MAX_FP16_ABS_ERROR:
        raise RuntimeError(f"TFLite-vs-PyTorch parity error {tflite_error} exceeds {MAX_FP16_ABS_ERROR}")

    report = {
        "schema_version": 2,
        "experiment_id": "DIRECT-MVP-TFLITE-CONVERSION-001",
        "checkpoint": str(args.checkpoint),
        "converter": "litert-torch (PyTorch → LiteRT) + ai-edge-quantizer float16 weights",
        "tflite": {
            "path": str(args.tflite_model),
            "bytes": args.tflite_model.stat().st_size,
            "weight_precision": "float16",
            "input": {"shape": input_detail["shape"].tolist(), "dtype": input_detail["dtype"].__name__},
            "output": {"shape": output_detail["shape"].tolist(), "dtype": output_detail["dtype"].__name__},
            "max_abs_error_vs_pytorch": tflite_error,
            "max_allowed_abs_error": MAX_FP16_ABS_ERROR,
        },
        "contract": "Compatible with LutPredictor's NCHW float32 input and [1,17,17,17,3] float32 output. This validates desktop LiteRT only; Android/iOS device latency remains required.",
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(f"direct MVP TFLite conversion complete -> {args.output}")


if __name__ == "__main__":
    main()
