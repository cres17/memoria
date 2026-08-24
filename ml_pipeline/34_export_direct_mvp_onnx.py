"""Export the selected direct MVP as an app-contract ONNX artifact and validate it."""

from __future__ import annotations

import argparse
import importlib
import json
from pathlib import Path

import numpy as np
import onnx
from onnx import TensorProto
import onnxruntime as ort
import torch
import torch.nn as nn


PIPELINE_DIR = Path(__file__).resolve().parent
CHECKPOINT = PIPELINE_DIR / "checkpoints" / "conditional_lut_mvp-family-holdout-smooth-010-001.pt"
ONNX_OUTPUT = PIPELINE_DIR / "reports" / "deployment" / "direct_mvp_family_holdout_smooth_010_001.onnx"
REPORT_OUTPUT = PIPELINE_DIR / "reports" / "deployment" / "direct_mvp_onnx_export_001.json"
PARITY_FIXTURE = PIPELINE_DIR / "reports" / "deployment" / "direct_mvp_onnx_parity_fixture_001.npz"
v2 = importlib.import_module("11_train_basis_v2")
model_definitions = importlib.import_module("conditional_lut_mvp_model")


class LUTOnlyWrapper(nn.Module):
    """Expose the exact single-input/single-output contract consumed by Flutter."""

    def __init__(self, model: nn.Module):
        super().__init__()
        self.model = model

    def forward(self, reference: torch.Tensor) -> torch.Tensor:
        lut, _ = self.model(reference)
        return lut


def load_model(path: Path) -> nn.Module:
    checkpoint = torch.load(path, map_location="cpu", weights_only=False)
    model = model_definitions.ConditionalLUTMVP(
        style_dim=int(checkpoint["style_dim"]),
        cube_dim=int(checkpoint["cube_dim"]),
        pretrained=False,
        decoder_output_mode=str(checkpoint.get("decoder_output_mode", "identity_logit")),
        decoder_hidden_dim=int(checkpoint.get("decoder_hidden_dim", 512)),
    ).eval()
    model.load_state_dict(checkpoint["state_dict"])
    return model


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--checkpoint", type=Path, default=CHECKPOINT)
    parser.add_argument("--onnx-output", type=Path, default=ONNX_OUTPUT)
    parser.add_argument("--output", type=Path, default=REPORT_OUTPUT)
    parser.add_argument("--parity-fixture", type=Path, default=PARITY_FIXTURE)
    args = parser.parse_args()

    model = LUTOnlyWrapper(load_model(args.checkpoint)).eval()
    reference = torch.linspace(-2.0, 2.0, 3 * v2.IMAGE_SIZE * v2.IMAGE_SIZE, dtype=torch.float32)
    reference = reference.reshape(1, 3, v2.IMAGE_SIZE, v2.IMAGE_SIZE)
    with torch.inference_mode():
        expected = model(reference).numpy()
    args.parity_fixture.parent.mkdir(parents=True, exist_ok=True)
    np.savez_compressed(args.parity_fixture, style_image=reference.numpy(), pytorch_lut=expected)

    args.onnx_output.parent.mkdir(parents=True, exist_ok=True)
    # The legacy exporter embeds weights. Remove the exact stale sidecar left
    # by a previous new-exporter attempt so packaging size is not overstated.
    args.onnx_output.with_suffix(args.onnx_output.suffix + ".data").unlink(missing_ok=True)
    torch.onnx.export(
        model,
        reference,
        args.onnx_output,
        input_names=["style_image"],
        output_names=["lut_small"],
        opset_version=17,
        do_constant_folding=True,
        # onnx-tf 1.10 supports opset 17 but not the current exporter's
        # fallback opset 18 graph. Keep the mobile conversion contract fixed.
        dynamo=False,
    )
    exported = onnx.load(args.onnx_output)
    onnx.checker.check_model(exported)
    external_data_paths = {
        args.onnx_output.parent / dict(initializer.external_data)["location"]
        for initializer in exported.graph.initializer
        if initializer.data_location == TensorProto.EXTERNAL
    }
    session = ort.InferenceSession(str(args.onnx_output), providers=["CPUExecutionProvider"])
    actual = session.run(["lut_small"], {"style_image": reference.numpy()})[0]
    if actual.shape != expected.shape:
        raise RuntimeError(f"ONNX output shape {actual.shape} differs from PyTorch {expected.shape}")
    max_abs_error = float(np.max(np.abs(expected - actual)))
    if max_abs_error > 1e-5:
        raise RuntimeError(f"ONNX parity error {max_abs_error} exceeds 1e-5")

    report = {
        "schema_version": 1,
        "experiment_id": "DIRECT-MVP-ONNX-EXPORT-001",
        "checkpoint": str(args.checkpoint),
        "onnx": {
            "path": str(args.onnx_output),
            "bytes": args.onnx_output.stat().st_size,
            "external_data_bytes": sum(path.stat().st_size for path in external_data_paths),
            "opset": next(item.version for item in exported.opset_import if item.domain == ""),
            "input": {"name": "style_image", "shape": list(reference.shape), "dtype": "float32"},
            "output": {"name": "lut_small", "shape": list(actual.shape), "dtype": "float32"},
            "onnxruntime_provider": "CPUExecutionProvider",
            "max_abs_error_vs_pytorch": max_abs_error,
            "parity_fixture": str(args.parity_fixture),
        },
        "contract": "Matches LutPredictor's NCHW [1,3,256,256] input and [1,D,D,D,3] float32 LUT output; this is ONNX validation, not yet a TFLite device claim.",
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(f"direct MVP ONNX export complete -> {args.output}")


if __name__ == "__main__":
    main()
