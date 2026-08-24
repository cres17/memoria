"""V3 balanced basis-residual LUT training with automatic weight search.

This script keeps the V2 basis artifact, but tunes the training loss weights
automatically instead of forcing manual sweep-by-hand experiments.

Typical flow:
  1. python 12_train_basis_v3.py --sweep
  2. python 12_train_basis_v3.py --train

Or do both in one go:
  python 12_train_basis_v3.py --sweep --train

Artifacts:
  checkpoints/basis_v3_color.pt
  checkpoints/basis_v3_color.report.json
  checkpoints/basis_v3_params.json
  checkpoints/basis_v3_sweep.json
"""

from __future__ import annotations

import argparse
import importlib
import json
import math
from dataclasses import dataclass, asdict
from pathlib import Path

import numpy as np
import torch
import torch.nn.functional as F
from torch.amp import GradScaler, autocast
from torch.utils.data import DataLoader, Dataset


v2 = importlib.import_module("11_train_basis_v2")

PIPELINE_DIR = v2.PIPELINE_DIR
DATASET_DIR = v2.DATASET_DIR
CHECKPOINT_DIR = v2.CHECKPOINT_DIR
BASIS_PATH = v2.BASIS_PATH
MODEL_PATH = CHECKPOINT_DIR / "basis_v3_color.pt"
REPORT_PATH = CHECKPOINT_DIR / "basis_v3_color.report.json"
PARAMS_PATH = CHECKPOINT_DIR / "basis_v3_params.json"
SWEEP_PATH = CHECKPOINT_DIR / "basis_v3_sweep.json"
BASELINE_REPORT_PATH = CHECKPOINT_DIR / "basis_v2_color.report.json"

SOURCE_GROUPS = v2.SOURCE_GROUPS
DEVICE = v2.DEVICE

DEFAULT_SWEEP_TRIALS = 8
DEFAULT_SWEEP_EPOCHS = 3
DEFAULT_TRAIN_EPOCHS = 60
DEFAULT_BATCH_SIZE = 32
DEFAULT_SEED = 20260720
DEFAULT_LR = 2e-4
DEFAULT_WEIGHT_DECAY = 1e-4
DEFAULT_RECONSTRUCTION_WEIGHT = 10.0
BASES_SPLIT_SEED = v2.SEED
SCORE_TAIL_SOURCE_COUNT = 5
SCORE_GROUP_STD_WEIGHT = 0.10
SCORE_TAIL_WEIGHT = 0.10
SCORE_BASELINE_PENALTY_WEIGHT = 1.50
DEFAULT_GROUP_WEIGHTS = {
    "crawled": 1.0,
    "app": 1.0,
    "canon": 1.0,
}


@dataclass(frozen=True)
class V3Config:
    crawled_weight: float = 1.0
    app_weight: float = 1.0
    canon_weight: float = 1.0
    reconstruction_weight: float = DEFAULT_RECONSTRUCTION_WEIGHT
    learning_rate: float = DEFAULT_LR
    weight_decay: float = DEFAULT_WEIGHT_DECAY
    pretrained: bool = True

    def normalized_group_weights(self) -> dict[str, float]:
        raw = np.array([self.crawled_weight, self.app_weight, self.canon_weight], dtype=np.float64)
        if np.any(raw <= 0) or not np.all(np.isfinite(raw)):
            raise ValueError("group weights must be positive finite numbers")
        raw = raw / raw.mean()
        return {group: float(value) for group, value in zip(SOURCE_GROUPS, raw)}


class V3BasisDataset(Dataset):
    def __init__(self, records: list[dict], vectors_by_source, coefficients_by_source):
        self.records = records
        self.vectors_by_source = vectors_by_source
        self.coefficients_by_source = coefficients_by_source

    def __len__(self):
        return len(self.records)

    def __getitem__(self, index):
        record = self.records[index]
        return (
            v2.load_image_tensor(record["image_path"]),
            torch.from_numpy(self.coefficients_by_source[record["source_lut"]]),
            torch.from_numpy(self.vectors_by_source[record["source_lut"]]),
            record["group"],
            record["source_lut"],
        )


def load_baseline_group_metrics() -> dict[str, float] | None:
    if not BASELINE_REPORT_PATH.exists():
        return None
    report = json.loads(BASELINE_REPORT_PATH.read_text())
    by_group = report.get("by_group", {})
    metrics = {}
    for group in SOURCE_GROUPS:
        group_metrics = by_group.get(group)
        if not group_metrics or "small_lut_rmse" not in group_metrics:
            return None
        metrics[group] = float(group_metrics["small_lut_rmse"])
    return metrics


def score_report(report: dict, baseline_group_metrics: dict[str, float] | None) -> tuple[float, dict, dict]:
    group_metrics = {
        group: float(report["by_group"][group]["small_lut_rmse"])
        for group in SOURCE_GROUPS
    }
    group_values = np.array([group_metrics[group] for group in SOURCE_GROUPS], dtype=np.float32)
    group_mean = float(group_values.mean())
    group_std = float(group_values.std())

    top_sources = report.get("top_sources_by_small_lut_rmse", [])[:SCORE_TAIL_SOURCE_COUNT]
    if top_sources:
        tail_source_mean = float(np.mean([float(source["small_lut_rmse"]) for source in top_sources]))
        tail_source_luts = [str(source["source_lut"]) for source in top_sources]
    else:
        tail_source_mean = group_mean
        tail_source_luts = []

    baseline_penalty = 0.0
    baseline_gap_by_group = {}
    if baseline_group_metrics:
        for group in ("app", "canon"):
            overshoot = max(0.0, group_metrics[group] - float(baseline_group_metrics[group]))
            baseline_gap_by_group[group] = overshoot
            baseline_penalty += SCORE_BASELINE_PENALTY_WEIGHT * overshoot

    score = (
        group_mean
        + SCORE_GROUP_STD_WEIGHT * group_std
        + SCORE_TAIL_WEIGHT * tail_source_mean
        + baseline_penalty
    )
    score_components = {
        "group_mean": group_mean,
        "group_std": group_std,
        "tail_source_mean": tail_source_mean,
        "tail_source_luts": tail_source_luts,
        "baseline_penalty": baseline_penalty,
        "baseline_gap_by_group": baseline_gap_by_group,
        "score": score,
    }
    return score, group_metrics, score_components


def sample_sweep_config(rng: np.random.Generator) -> V3Config:
    crawled_weight = float(np.exp(rng.uniform(np.log(1.0), np.log(5.0))))
    canon_weight = float(np.exp(rng.uniform(np.log(0.7), np.log(1.6))))
    reconstruction_weight = float(np.exp(rng.uniform(np.log(6.0), np.log(14.0))))
    return V3Config(
        crawled_weight=crawled_weight,
        app_weight=1.0,
        canon_weight=canon_weight,
        reconstruction_weight=reconstruction_weight,
        learning_rate=DEFAULT_LR,
        weight_decay=DEFAULT_WEIGHT_DECAY,
        pretrained=True,
    )


def load_params_from_file(path: Path) -> V3Config:
    payload = json.loads(path.read_text())
    return V3Config(
        crawled_weight=float(payload["crawled_weight"]),
        app_weight=float(payload["app_weight"]),
        canon_weight=float(payload["canon_weight"]),
        reconstruction_weight=float(payload.get("reconstruction_weight", DEFAULT_RECONSTRUCTION_WEIGHT)),
        learning_rate=float(payload.get("learning_rate", DEFAULT_LR)),
        weight_decay=float(payload.get("weight_decay", DEFAULT_WEIGHT_DECAY)),
        pretrained=bool(payload.get("pretrained", True)),
    )


def save_json(path: Path, payload: dict):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


def train_once(
    config: V3Config,
    epochs: int,
    batch_size: int,
    run_seed: int,
    save_checkpoint: bool,
    trial_name: str,
    split_seed: int = BASES_SPLIT_SEED,
    split_path: Path | None = None,
    basis_path: Path = BASIS_PATH,
):
    records = v2.read_manifest(DATASET_DIR)
    torch.manual_seed(run_seed)
    np.random.seed(run_seed)
    if split_path is None:
        train_records, validation_records, validation_sources = v2.split_lut_sources(
            records, v2.VAL_RATIO, split_seed
        )
        split_metadata = {"split_type": "legacy_random_source_lut_holdout"}
    else:
        train_records, validation_records, _, split_metadata = v2.read_explicit_split(records, split_path)
        validation_sources = sorted({record["source_lut"] for record in validation_records})
    mean, bases, scales = v2.load_basis(train_records, basis_path)
    if bases.shape[0] != v2.NUM_BASES:
        raise RuntimeError(
            f"basis artifact has {bases.shape[0]} bases but V3 expects {v2.NUM_BASES}; rerun V2 basis fit"
        )

    train_vectors, train_coefficients = v2.coefficients_for_records(train_records, mean, bases, scales)
    validation_vectors, validation_coefficients = v2.coefficients_for_records(
        validation_records, mean, bases, scales
    )
    train_dataset = V3BasisDataset(train_records, train_vectors, train_coefficients)
    validation_dataset = V3BasisDataset(validation_records, validation_vectors, validation_coefficients)
    train_loader = DataLoader(
        train_dataset,
        batch_size=batch_size,
        sampler=v2.make_balanced_sampler(train_records),
        num_workers=0,
    )

    model = v2.BasisResidualNetV2(bases.shape[0], pretrained=config.pretrained).to(DEVICE)
    optimizer = torch.optim.AdamW(
        model.parameters(), lr=config.learning_rate, weight_decay=config.weight_decay
    )
    scaler = GradScaler("cuda", enabled=DEVICE.type == "cuda")
    mean_tensor = torch.from_numpy(mean).to(DEVICE)
    basis_tensor = torch.from_numpy(bases).to(DEVICE)
    group_weights = config.normalized_group_weights()
    baseline_group_metrics = load_baseline_group_metrics()
    best_score = float("inf")
    best_payload = None

    print(
        f"[{trial_name}] device={DEVICE}; train={len(train_dataset)} {v2.counts_by_group(train_records)}; "
        f"val={len(validation_dataset)} {v2.counts_by_group(validation_records)}; "
        f"weights={group_weights}; recon_w={config.reconstruction_weight:.4f}"
    )

    for epoch in range(epochs):
        model.train()
        train_losses = []
        for image, target_coefficients, target_lut, groups, _ in train_loader:
            image = image.to(DEVICE)
            target_coefficients = target_coefficients.to(DEVICE)
            target_lut = target_lut.to(DEVICE)
            batch_weights = torch.tensor(
                [group_weights[group] for group in groups],
                dtype=torch.float32,
                device=DEVICE,
            )

            optimizer.zero_grad(set_to_none=True)
            with autocast(DEVICE.type, enabled=DEVICE.type == "cuda"):
                predicted_coefficients = model(image)
                predicted_lut = v2.reconstruct(predicted_coefficients, mean_tensor, basis_tensor)
                coefficient_mse = ((predicted_coefficients - target_coefficients) ** 2).mean(dim=1)
                reconstruction_loss = F.smooth_l1_loss(
                    predicted_lut, target_lut, reduction="none"
                ).mean(dim=1)
                per_sample_loss = coefficient_mse + config.reconstruction_weight * reconstruction_loss
                loss = (per_sample_loss * batch_weights).mean()

            if not torch.isfinite(loss):
                optimizer.zero_grad(set_to_none=True)
                continue

            scaler.scale(loss).backward()
            scaler.unscale_(optimizer)
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            scaler.step(optimizer)
            scaler.update()
            train_losses.append(loss.item())

        validation_report = v2.evaluate_records(
            model,
            validation_dataset.records,
            validation_vectors,
            validation_coefficients,
            mean_tensor,
            basis_tensor,
        )
        validation_score, group_metrics, score_components = score_report(
            validation_report, baseline_group_metrics
        )
        validation_report = dict(validation_report)
        validation_report["score"] = validation_score
        validation_report["score_components"] = score_components
        validation_report["baseline_group_metrics"] = baseline_group_metrics
        print(
            f"[{trial_name}] epoch={epoch + 1:02d} train_loss={float(np.mean(train_losses)):.6f} "
            f"score={validation_score:.6f} "
            f"group_mean={score_components['group_mean']:.6f} "
            f"group_std={score_components['group_std']:.6f} "
            f"tail={score_components['tail_source_mean']:.6f} "
            f"crawled={group_metrics['crawled']:.6f} "
            f"app={group_metrics['app']:.6f} "
            f"canon={group_metrics['canon']:.6f}"
        )

        if validation_score < best_score:
            best_score = validation_score
            best_payload = {
                "state_dict": model.state_dict(),
                "basis_path": str(basis_path),
                "split_path": str(split_path) if split_path else None,
                "split_metadata": split_metadata,
                "basis_dim": v2.BASIS_DIM,
                "num_bases": bases.shape[0],
                "coefficient_bound": v2.COEFFICIENT_BOUND,
                "coefficient_space": "normalized_scaled_bases",
                "pretrained_weights": bool(config.pretrained),
                "epoch": epoch,
                "val_score": validation_score,
                "val_loss": validation_score,
                "val_group_metrics": group_metrics,
                "val_score_components": score_components,
                "validation_report": validation_report,
                "validation_report_path": str(REPORT_PATH),
                "train_counts_by_group": v2.counts_by_group(train_records),
                "validation_counts_by_group": v2.counts_by_group(validation_records),
                "validation_lut_sources": validation_sources,
                "v3_config": asdict(config),
                "v3_group_weights": group_weights,
                "v3_reconstruction_weight": config.reconstruction_weight,
            }
            if save_checkpoint:
                CHECKPOINT_DIR.mkdir(parents=True, exist_ok=True)
                torch.save(best_payload, MODEL_PATH)
                save_json(REPORT_PATH, validation_report)

    if best_payload is None:
        raise RuntimeError("training finished without a valid checkpoint")
    return best_score, best_payload


def run_sweep(trials: int, epochs: int, batch_size: int, seed: int, split_path: Path | None, basis_path: Path) -> tuple[V3Config, dict]:
    rng = np.random.default_rng(seed)
    results = []
    best_score = float("inf")
    best_config = None
    best_payload = None

    for trial_index in range(trials):
        config = sample_sweep_config(rng)
        trial_seed = seed + trial_index
        score, payload = train_once(
            config=config,
            epochs=epochs,
            batch_size=batch_size,
            run_seed=trial_seed,
            save_checkpoint=False,
            trial_name=f"sweep-{trial_index + 1}/{trials}",
            split_path=split_path,
            basis_path=basis_path,
        )
        result = {
            "trial": trial_index + 1,
            "seed": trial_seed,
            "score": score,
            "config": asdict(config),
            "group_weights": config.normalized_group_weights(),
            "val_group_metrics": payload["val_group_metrics"],
            "val_score_components": payload["val_score_components"],
        }
        results.append(result)
        if score < best_score:
            best_score = score
            best_config = config
            best_payload = payload

    assert best_config is not None and best_payload is not None
    sweep_payload = {
        "seed": seed,
        "trials": results,
        "best": {
            "score": best_score,
            "config": asdict(best_config),
            "group_weights": best_config.normalized_group_weights(),
            "val_group_metrics": best_payload["val_group_metrics"],
            "val_score_components": best_payload["val_score_components"],
        },
        "baseline_group_metrics": load_baseline_group_metrics(),
    }
    save_json(SWEEP_PATH, sweep_payload)
    save_json(PARAMS_PATH, asdict(best_config) | {
        "group_weights": best_config.normalized_group_weights(),
        "score": best_score,
    })
    print(
        f"sweep complete -> {SWEEP_PATH}\n"
        f"best score={best_score:.6f} weights={best_config.normalized_group_weights()} "
        f"recon_w={best_config.reconstruction_weight:.4f}"
    )
    return best_config, best_payload


def main():
    parser = argparse.ArgumentParser(description="Train the V3 basis-residual LUT model with auto weight search.")
    parser.add_argument("--train", action="store_true", help="Train the final V3 checkpoint.")
    parser.add_argument("--sweep", action="store_true", help="Run automatic search before training.")
    parser.add_argument("--sweep-trials", type=int, default=DEFAULT_SWEEP_TRIALS)
    parser.add_argument("--sweep-epochs", type=int, default=DEFAULT_SWEEP_EPOCHS)
    parser.add_argument("--epochs", type=int, default=DEFAULT_TRAIN_EPOCHS)
    parser.add_argument("--batch-size", type=int, default=DEFAULT_BATCH_SIZE)
    parser.add_argument("--seed", type=int, default=DEFAULT_SEED)
    parser.add_argument("--group-weight-crawled", type=float)
    parser.add_argument("--group-weight-app", type=float)
    parser.add_argument("--group-weight-canon", type=float)
    parser.add_argument("--reconstruction-weight", type=float)
    parser.add_argument("--learning-rate", type=float)
    parser.add_argument("--weight-decay", type=float)
    parser.add_argument("--no-pretrained", action="store_true")
    parser.add_argument("--config", type=Path, help="Load V3 parameters from JSON.")
    parser.add_argument("--split-path", type=Path, help="explicit family-holdout split; requires family-specific artifact paths")
    parser.add_argument("--experiment-id")
    parser.add_argument("--basis-path", type=Path)
    parser.add_argument("--model-path", type=Path)
    parser.add_argument("--report-path", type=Path)
    parser.add_argument("--params-path", type=Path)
    parser.add_argument("--sweep-path", type=Path)
    parser.add_argument(
        "--sweep-only",
        action="store_true",
        help="Run the sweep and stop after saving the best parameter set.",
    )
    args = parser.parse_args()

    if not args.sweep and not args.train and not args.sweep_only:
        parser.error("choose --sweep, --train, or both")
    if args.sweep_trials <= 0 or args.sweep_epochs <= 0 or args.epochs <= 0 or args.batch_size <= 0:
        parser.error("trial, epoch, and batch sizes must be positive")

    torch.manual_seed(args.seed)
    np.random.seed(args.seed)

    global BASIS_PATH, MODEL_PATH, REPORT_PATH, PARAMS_PATH, SWEEP_PATH
    if args.split_path:
        if not args.experiment_id or not args.basis_path:
            parser.error("--split-path requires --experiment-id and --basis-path")
        suffix = args.experiment_id.lower()
        BASIS_PATH = args.basis_path
        MODEL_PATH = args.model_path or CHECKPOINT_DIR / f"basis_v3_{suffix}.pt"
        REPORT_PATH = args.report_path or CHECKPOINT_DIR / f"basis_v3_{suffix}.report.json"
        PARAMS_PATH = args.params_path or CHECKPOINT_DIR / f"basis_v3_{suffix}.params.json"
        SWEEP_PATH = args.sweep_path or CHECKPOINT_DIR / f"basis_v3_{suffix}.sweep.json"
        if any(path.exists() for path in (MODEL_PATH, REPORT_PATH, PARAMS_PATH, SWEEP_PATH)):
            parser.error("refusing to overwrite existing family V3 artifacts")
    if args.sweep_only:
        args.sweep = True

    if args.config:
        config = load_params_from_file(args.config)
    else:
        explicit_weights = [
            args.group_weight_crawled,
            args.group_weight_app,
            args.group_weight_canon,
        ]
        if all(value is not None for value in explicit_weights):
            config = V3Config(
                crawled_weight=float(args.group_weight_crawled),
                app_weight=float(args.group_weight_app),
                canon_weight=float(args.group_weight_canon),
                reconstruction_weight=float(args.reconstruction_weight or DEFAULT_RECONSTRUCTION_WEIGHT),
                learning_rate=float(args.learning_rate or DEFAULT_LR),
                weight_decay=float(args.weight_decay or DEFAULT_WEIGHT_DECAY),
                pretrained=not args.no_pretrained,
            )
        else:
            config = V3Config(
                reconstruction_weight=float(args.reconstruction_weight or DEFAULT_RECONSTRUCTION_WEIGHT),
                learning_rate=float(args.learning_rate or DEFAULT_LR),
                weight_decay=float(args.weight_decay or DEFAULT_WEIGHT_DECAY),
                pretrained=not args.no_pretrained,
            )

    if args.sweep:
        best_config, _ = run_sweep(args.sweep_trials, args.sweep_epochs, args.batch_size, args.seed, args.split_path, BASIS_PATH)
        config = best_config

    if args.sweep_only:
        return

    if args.train:
        score, payload = train_once(
            config=config,
            epochs=args.epochs,
            batch_size=args.batch_size,
            run_seed=args.seed,
            save_checkpoint=True,
            trial_name="final",
            split_path=args.split_path,
            basis_path=BASIS_PATH,
        )
        payload["val_score"] = score
        payload["val_loss"] = score
        CHECKPOINT_DIR.mkdir(parents=True, exist_ok=True)
        torch.save(payload, MODEL_PATH)
        save_json(REPORT_PATH, payload["validation_report"])
        save_json(PARAMS_PATH, asdict(config) | {
            "group_weights": config.normalized_group_weights(),
            "score": score,
        })
        print(f"saved best V3 checkpoint -> {MODEL_PATH} (score={score:.6f})")


if __name__ == "__main__":
    main()
