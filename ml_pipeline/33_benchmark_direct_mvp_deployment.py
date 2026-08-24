"""Benchmark selected direct MVP inference and verify a TorchScript deployment artifact."""

from __future__ import annotations

import argparse
import importlib
import json
import time
from pathlib import Path

import numpy as np
import torch


PIPELINE_DIR = Path(__file__).resolve().parent
CHECKPOINT = PIPELINE_DIR / "checkpoints" / "conditional_lut_mvp-family-holdout-smooth-010-001.pt"
OUTPUT = PIPELINE_DIR / "reports" / "deployment" / "direct_mvp_deployment_benchmark_001.json"
TORCHSCRIPT = PIPELINE_DIR / "reports" / "deployment" / "direct_mvp_family_holdout_smooth_010_001.torchscript.pt"
mvp = importlib.import_module("20_train_conditional_lut_mvp")


def percentile(values: list[float], value: float) -> float:
    return float(np.percentile(np.asarray(values, dtype=np.float64), value))


def measure(action, warmup: int, samples: int) -> dict:
    for _ in range(warmup):
        action()
    values = []
    for _ in range(samples):
        start = time.perf_counter()
        action()
        values.append((time.perf_counter() - start) * 1000.0)
    return {"samples": samples, "mean_ms": float(np.mean(values)), "p50_ms": percentile(values, 50), "p95_ms": percentile(values, 95)}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--checkpoint", type=Path, default=CHECKPOINT)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    parser.add_argument("--torchscript-output", type=Path, default=TORCHSCRIPT)
    parser.add_argument("--warmup", type=int, default=3)
    parser.add_argument("--samples", type=int, default=20)
    parser.add_argument("--render-size", type=int, default=512)
    args = parser.parse_args()
    if args.warmup < 0 or args.samples <= 0 or args.render_size <= 0:
        parser.error("warmup must be non-negative; samples and render-size must be positive")

    checkpoint = torch.load(args.checkpoint, map_location=mvp.DEVICE, weights_only=False)
    model = mvp.ConditionalLUTMVP(
        style_dim=int(checkpoint["style_dim"]), cube_dim=int(checkpoint["cube_dim"]), pretrained=False,
        decoder_output_mode=str(checkpoint.get("decoder_output_mode", "identity_logit")),
        decoder_hidden_dim=int(checkpoint.get("decoder_hidden_dim", 512)),
    ).to(mvp.DEVICE).eval()
    model.load_state_dict(checkpoint["state_dict"])
    record = mvp.read_split_records(Path(checkpoint["split_path"]), {"validation"})[0]
    reference = mvp.v2.load_image_tensor(record["reference_path"]).unsqueeze(0).to(mvp.DEVICE)
    render_input = torch.linspace(0.0, 1.0, args.render_size, device=mvp.DEVICE)
    render_input = torch.stack(torch.meshgrid(render_input, render_input, indexing="ij"), dim=-1)
    render_input = torch.cat((render_input, render_input[..., :1]), dim=-1).unsqueeze(0)

    with torch.inference_mode():
        generated_lut, generated_style = model(reference)
        generation = measure(lambda: model(reference), args.warmup, args.samples)
        render = measure(lambda: mvp.apply_lut_torch(generated_lut, render_input), args.warmup, args.samples)
        args.torchscript_output.parent.mkdir(parents=True, exist_ok=True)
        traced = torch.jit.trace(model, (reference,), strict=False)
        scripted_lut, scripted_style = traced(reference)
        try:
            traced.save(str(args.torchscript_output))
            torch.jit.load(str(args.torchscript_output), map_location=mvp.DEVICE)(reference)
            torchscript_export = {"path": str(args.torchscript_output), "bytes": args.torchscript_output.stat().st_size,
                                  "serialization": "reload_passed"}
        except RuntimeError as error:
            args.torchscript_output.unlink(missing_ok=True)
            lines = [line.strip() for line in str(error).splitlines() if line.strip()]
            reason = " ".join(lines[:2]) if lines else type(error).__name__
            torchscript_export = {"serialization": "reload_failed", "reason": reason}
    report = {
        "schema_version": 1,
        "experiment_id": "DIRECT-MVP-DEPLOYMENT-BENCHMARK-001",
        "checkpoint": str(args.checkpoint),
        "device": str(mvp.DEVICE),
        "model_parameters": int(sum(parameter.numel() for parameter in model.parameters())),
        "checkpoint_bytes": args.checkpoint.stat().st_size,
        "torchscript": torchscript_export | {
                        "lut_max_abs_error": float((generated_lut - scripted_lut).abs().max()),
                        "style_max_abs_error": float((generated_style - scripted_style).abs().max())},
        "lut_generation": generation,
        "lut_application": render | {"render_size": args.render_size},
        "contract": "CPU benchmark includes one reference-to-17^3-LUT generation and a separate 512px differentiable LUT application; not a mobile device latency claim.",
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(f"direct MVP deployment benchmark complete -> {args.output}")


if __name__ == "__main__":
    main()
