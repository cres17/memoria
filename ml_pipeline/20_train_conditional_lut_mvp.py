"""Train the bounded low-resolution conditional 3D LUT MVP.

This is deliberately separate from the V2/V3 PCA coefficient regressors.  A
graded reference image is encoded into a Style Code, which directly generates
a bounded 17^3 LUT.  The generated LUT is supervised against the full target
Color Cube, including cube colors that are not observed in the reference.

Examples:
  .venv-ml/bin/python ml_pipeline/20_train_conditional_lut_mvp.py --smoke-test
  .venv-ml/bin/python ml_pipeline/20_train_conditional_lut_mvp.py --train --epochs 10
"""

from __future__ import annotations

import argparse
import importlib
import json
import random
from collections import defaultdict
from dataclasses import asdict, dataclass
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
from torch.utils.data import DataLoader, Dataset, Sampler, WeightedRandomSampler

from conditional_lut_mvp_model import (
    BoundedLUTDecoder,
    ConditionalLUTMVP,
    SemanticPooledStyleEncoder,
    StructuredAuxiliaryHead,
    StyleEncoder,
    rgb_to_hsv_numpy,
)
from lut_axis_contract import save_float16_lut


PIPELINE_DIR = Path(__file__).resolve().parent
DATASET_DIR = PIPELINE_DIR / "data" / "dataset"
SPLIT_PATH = PIPELINE_DIR / "reports" / "splits" / "conditional_lut_holdout.jsonl"
MASK_PATH = PIPELINE_DIR / "reports" / "hue_masks" / "hue_coverage_17.npz"
CHECKPOINT_DIR = PIPELINE_DIR / "checkpoints"
REPORT_DIR = PIPELINE_DIR / "reports" / "mvp"
SEMANTIC_CACHE_DIR = PIPELINE_DIR / "reports" / "semantic_masks" / "selfie_multiclass_256_softmax_64"

v2 = importlib.import_module("11_train_basis_v2")
evaluator = importlib.import_module("17_evaluate_conditional_lut")

CUBE_DIM = 17
STYLE_DIM = 128
DEFAULT_BATCH_SIZE = 8
DEFAULT_LEARNING_RATE = 2e-4
SOURCE_GROUPS = ("crawled", "app", "canon")
DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")


@dataclass(frozen=True)
class LossWeights:
    """Experimental defaults; tune only after the smoke test validates gradients."""

    cube: float = 1.0
    image: float = 0.25
    smoothness: float = 0.01


STYLE_CONSISTENCY_WEIGHT = 0.25
STYLE_CONTRASTIVE_TEMPERATURE = 0.10
STYLE_INTRA_WEIGHT = 0.10
HUE_ANCHOR_COUNT = 6
SEMANTIC_CLASSES = 6


def set_seed(seed: int) -> None:
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(seed)


def freeze_batch_norm(module: nn.Module) -> None:
    """Keep small-batch encoder features consistent between train and evaluation."""
    for child in module.modules():
        if isinstance(child, nn.modules.batchnorm._BatchNorm):
            child.eval()


def read_split_records(
    path: Path,
    partitions: set[str],
    dataset_dir: Path = DATASET_DIR,
) -> list[dict]:
    if not path.exists():
        raise FileNotFoundError(f"split manifest is missing: {path}")
    records = []
    for line_number, line in enumerate(path.read_text().splitlines(), start=1):
        if not line:
            continue
        record = json.loads(line)
        required = {"id", "split", "samplingGroup", "sourceLut"}
        missing = required - record.keys()
        if missing:
            raise ValueError(f"{path}:{line_number} missing {sorted(missing)}")
        if record["split"] not in partitions:
            continue
        sample_id = record["id"]
        record["reference_path"] = dataset_dir / "graded" / f"{sample_id}.jpg"
        record["neutral_path"] = dataset_dir / "neutral" / f"{sample_id}.jpg"
        record["lut_path"] = dataset_dir / "luts" / f"{sample_id}.bin"
        if not all(record[key].exists() for key in ("reference_path", "neutral_path", "lut_path")):
            raise FileNotFoundError(f"dataset triplet missing for sample {sample_id}")
        records.append(record)
    records.sort(key=lambda item: item["id"])
    if not records:
        raise ValueError(f"no records for partitions {sorted(partitions)}")
    return records


def load_masks(path: Path) -> dict[str, np.ndarray]:
    with np.load(path) as archive:
        if int(archive["cube_dim"]) != CUBE_DIM:
            raise ValueError("Hue mask grid must match MVP cube dimension")
        return {
            str(sample_id): mask.astype(bool)
            for sample_id, mask in zip(archive["ids"].astype(str), archive["observed_cube_mask"])
        }


def load_semantic_masks(cache_dir: Path, sample_id: str) -> torch.Tensor:
    """Load the checksum-pinned six-class softmax cache used by semantic ablations."""
    path = cache_dir / f"{sample_id}.npz"
    with np.load(path) as archive:
        masks = archive["masks"].astype(np.float32)
        classes = tuple(archive["class_names"].astype(str))
        postprocess = str(archive["postprocess"])
    if masks.shape != (SEMANTIC_CLASSES, 64, 64) or len(classes) != SEMANTIC_CLASSES:
        raise ValueError(f"invalid semantic cache contract: {path}")
    if postprocess != "softmax_logits_then_bilinear_64x64":
        raise ValueError(f"unexpected semantic cache postprocess: {path}")
    return torch.from_numpy(masks)


def load_target_lut(path: Path) -> np.ndarray:
    """Sample the 65^3 LUT at the MVP grid and apply the renderer's target clamp."""
    full_lut = evaluator.load_lut(path)
    indices = np.linspace(0, full_lut.shape[0] - 1, CUBE_DIM).round().astype(np.int64)
    small_lut = full_lut[np.ix_(indices, indices, indices)]
    return np.clip(small_lut, 0.0, 1.0).astype(np.float32)


def structured_tone_hue_targets(target_lut: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Extract labels compatible with the normalized curve + six-anchor decoder."""
    if target_lut.shape != (CUBE_DIM, CUBE_DIM, CUBE_DIM, 3):
        raise ValueError(f"expected target LUT shape {(CUBE_DIM, CUBE_DIM, CUBE_DIM, 3)}")
    diagonal = target_lut[np.arange(CUBE_DIM), np.arange(CUBE_DIM), np.arange(CUBE_DIM)]
    raw_curve = diagonal @ np.asarray((0.2126, 0.7152, 0.0722), dtype=np.float32)
    curve = (raw_curve - raw_curve[0]) / max(float(raw_curve[-1] - raw_curve[0]), 1e-6)
    curve = np.clip(curve, 0.0, 1.0).astype(np.float32)
    identity = evaluator.identity_lut(CUBE_DIM).astype(np.float32)
    input_luminance = identity @ np.asarray((0.2126, 0.7152, 0.0722), dtype=np.float32)
    positions = input_luminance.reshape(-1) * (CUBE_DIM - 1)
    lower = np.floor(positions).astype(np.int64)
    upper = np.minimum(lower + 1, CUBE_DIM - 1)
    fraction = positions - lower
    mapped = curve[lower] + fraction * (curve[upper] - curve[lower])
    scale = np.divide(mapped, input_luminance.reshape(-1), out=np.zeros_like(mapped), where=input_luminance.reshape(-1) > 1e-6)
    tone_base = (identity.reshape(-1, 3) * scale[:, None]).reshape(target_lut.shape)
    hsv = rgb_to_hsv_numpy(identity.reshape(-1, 3))
    hue, saturation = hsv[:, 0], hsv[:, 1]
    residual = (target_lut - tone_base).reshape(-1, 3)
    bins = np.floor(hue * HUE_ANCHOR_COUNT).astype(np.int64) % HUE_ANCHOR_COUNT
    anchors = np.zeros((HUE_ANCHOR_COUNT, 3), dtype=np.float32)
    for index in range(HUE_ANCHOR_COUNT):
        selected = bins == index
        weights = saturation[selected]
        denominator = float(np.square(weights).sum())
        if denominator > 1e-8:
            anchors[index] = (weights[:, None] * residual[selected]).sum(axis=0) / denominator
    return curve, np.clip(anchors, -1.25, 1.25).astype(np.float32)


class ConditionalLUTDataset(Dataset):
    def __init__(self, records: list[dict], masks: dict[str, np.ndarray], semantic_cache_dir: Path | None = None):
        self.records = records
        self.masks = masks
        self.semantic_cache_dir = semantic_cache_dir
        self.target_by_source: dict[str, np.ndarray] = {}
        for record in records:
            self.target_by_source.setdefault(record["sourceLut"], load_target_lut(record["lut_path"]))
        self.structured_targets_by_source = {
            source_lut: structured_tone_hue_targets(target)
            for source_lut, target in self.target_by_source.items()
        }

    def __len__(self) -> int:
        return len(self.records)

    def __getitem__(self, index: int) -> dict:
        record = self.records[index]
        sample_id = record["id"]
        sample = {
            "reference": v2.load_image_tensor(record["reference_path"]),
            "neutral": v2.load_image_tensor(record["neutral_path"]),
            "target_lut": torch.from_numpy(self.target_by_source[record["sourceLut"]]),
            "target_tone_curve": torch.from_numpy(self.structured_targets_by_source[record["sourceLut"]][0]),
            "target_hue_anchors": torch.from_numpy(self.structured_targets_by_source[record["sourceLut"]][1]),
            "observed_mask": torch.from_numpy(self.masks[sample_id]),
            "id": sample_id,
            "group": record["samplingGroup"],
            "source_lut": record["sourceLut"],
        }
        if self.semantic_cache_dir is not None:
            sample["semantic_masks"] = load_semantic_masks(self.semantic_cache_dir, sample_id)
        return sample


def collate_samples(samples: list[dict]) -> dict:
    batch = {
        "reference": torch.stack([sample["reference"] for sample in samples]),
        "neutral": torch.stack([sample["neutral"] for sample in samples]),
        "target_lut": torch.stack([sample["target_lut"] for sample in samples]),
        "target_tone_curve": torch.stack([sample["target_tone_curve"] for sample in samples]),
        "target_hue_anchors": torch.stack([sample["target_hue_anchors"] for sample in samples]),
        "observed_mask": torch.stack([sample["observed_mask"] for sample in samples]),
        "id": [sample["id"] for sample in samples],
        "group": [sample["group"] for sample in samples],
        "source_lut": [sample["source_lut"] for sample in samples],
    }
    if "semantic_masks" in samples[0]:
        batch["semantic_masks"] = torch.stack([sample["semantic_masks"] for sample in samples])
    return batch


def balanced_sampler(records: list[dict]) -> WeightedRandomSampler:
    counts = {group: sum(record["samplingGroup"] == group for record in records) for group in SOURCE_GROUPS}
    if any(count == 0 for count in counts.values()):
        raise ValueError(f"cannot balance missing source group: {counts}")
    weights = torch.DoubleTensor([1.0 / counts[record["samplingGroup"]] for record in records])
    return WeightedRandomSampler(weights, num_samples=len(records), replacement=True)


class SourcePairBatchSampler(Sampler[list[int]]):
    """Yield full-coverage, epoch-varying scene pairs for Style Consistency."""

    def __init__(self, records: list[dict], batch_size: int, seed: int):
        if batch_size < 4 or batch_size % 2:
            raise ValueError("Style Consistency batches must be even and contain at least four samples")
        self.batch_size = batch_size
        self.pairs_per_batch = batch_size // 2
        self.seed = seed
        self.epoch = 0
        self.indices_by_source: dict[str, list[int]] = defaultdict(list)
        for index, record in enumerate(records):
            self.indices_by_source[record["sourceLut"]].append(index)
        self.sources = sorted(source for source, indices in self.indices_by_source.items() if len(indices) >= 2)
        if len(self.sources) < 2:
            raise ValueError("need at least two LUTs with two scenes for Style Consistency batches")
        source_pair_counts = {source: (len(self.indices_by_source[source]) + 1) // 2 for source in self.sources}
        total_pairs = sum(source_pair_counts.values())
        self.batches = max(
            max(source_pair_counts.values()),
            (total_pairs + self.pairs_per_batch - 1) // self.pairs_per_batch,
        )

    def __len__(self) -> int:
        return self.batches

    def set_epoch(self, epoch: int) -> None:
        if epoch < 0:
            raise ValueError("epoch must be non-negative")
        self.epoch = epoch

    def _build_batches(self) -> list[list[int]]:
        rng = np.random.default_rng(self.seed + self.epoch)
        pairs_by_source: dict[str, list[tuple[int, int]]] = {}
        for source in self.sources:
            indices = [int(index) for index in rng.permutation(self.indices_by_source[source])]
            pairs = [(indices[offset], indices[offset + 1]) for offset in range(0, len(indices) - 1, 2)]
            if len(indices) % 2:
                # Repeat one different scene only for an odd-sized source group.
                pairs.append((indices[-1], indices[0]))
            pairs_by_source[source] = pairs

        pair_batches: list[list[tuple[str, tuple[int, int]]]] = [[] for _ in range(self.batches)]
        source_order = sorted(self.sources, key=lambda source: (-len(pairs_by_source[source]), source))
        for source in source_order:
            pairs = pairs_by_source[source]
            # A source contributes at most one pair to each batch. Choose the
            # least-loaded batches with a random tie-break so large LUT groups
            # are spread across the entire epoch.
            tie_break = rng.random(self.batches)
            batch_order = sorted(range(self.batches), key=lambda index: (len(pair_batches[index]), tie_break[index]))
            for pair, batch_index in zip(pairs, batch_order):
                pair_batches[batch_index].append((source, pair))

        batches = []
        for pair_batch in pair_batches:
            if len(pair_batch) < 2:
                raise RuntimeError("Style Consistency batch must contain at least two source LUTs")
            if len(pair_batch) > self.pairs_per_batch:
                raise RuntimeError("pair allocation exceeded configured batch size")
            rng.shuffle(pair_batch)
            batches.append([index for _, pair in pair_batch for index in pair])
        return batches

    def sampling_summary(self) -> dict[str, float | int]:
        batches = self._build_batches()
        draws = [index for batch in batches for index in batch]
        unique = set(draws)
        all_indices = {index for indices in self.indices_by_source.values() for index in indices}
        return {
            "epoch": self.epoch,
            "draws": len(draws),
            "unique_records": len(unique),
            "eligible_records": len(all_indices),
            "coverage_fraction": len(unique) / len(all_indices),
            "duplicate_draws": len(draws) - len(unique),
            "batches": len(batches),
        }

    def __iter__(self):
        yield from self._build_batches()


def select_style_consistency_records(records: list[dict], pairs: int = 2) -> list[dict]:
    """Choose pairs with the same LUT but distinct source images for a deterministic smoke batch."""
    by_source: dict[str, list[dict]] = {}
    for record in records:
        by_source.setdefault(record["sourceLut"], []).append(record)
    selected = []
    for source_lut, source_records in sorted(by_source.items()):
        unique_images: dict[str, dict] = {}
        for record in source_records:
            unique_images.setdefault(record.get("sourceImage", record["id"]), record)
        if len(unique_images) >= 2:
            selected.extend(list(unique_images.values())[:2])
        if len(selected) == pairs * 2:
            break
    if len(selected) != pairs * 2:
        raise ValueError("need at least two LUTs with two distinct source images for Style Consistency smoke")
    source_luts = {record["sourceLut"] for record in selected}
    if len(source_luts) != pairs:
        raise RuntimeError("Style Consistency smoke must contain multiple source LUTs for collapse guard")
    return selected


def select_style_monitor_records(records: list[dict]) -> list[dict]:
    """Choose two deterministic, distinct scenes for every validation LUT."""
    by_source: dict[str, list[dict]] = defaultdict(list)
    for record in records:
        by_source[record["sourceLut"]].append(record)
    selected = []
    for source_lut, source_records in sorted(by_source.items()):
        unique_images: dict[str, dict] = {}
        for record in source_records:
            unique_images.setdefault(record.get("sourceImage", record["id"]), record)
        if len(unique_images) < 2:
            raise ValueError(f"Style monitor source LUT needs two distinct scenes: {source_lut}")
        selected.extend(list(unique_images.values())[:2])
    return selected


def apply_lut_torch(lut: torch.Tensor, colors: torch.Tensor) -> torch.Tensor:
    """Differentiable trilinear application for lut [B,R,G,B,3], colors [B,...,3]."""
    if lut.ndim != 5 or lut.shape[-1] != 3 or colors.shape[0] != lut.shape[0] or colors.shape[-1] != 3:
        raise ValueError("expected LUT [B,R,G,B,3] and colors [B,...,3]")
    original_shape = colors.shape
    points = colors.reshape(colors.shape[0], -1, 3).clamp(0.0, 1.0)
    # grid_sample coordinates are x=width(B), y=height(G), z=depth(R).
    grid = points[..., [2, 1, 0]].mul(2.0).sub(1.0).reshape(points.shape[0], -1, 1, 1, 3)
    volume = lut.permute(0, 4, 1, 2, 3)
    sampled = F.grid_sample(volume, grid, mode="bilinear", padding_mode="border", align_corners=True)
    output = sampled[:, :, :, 0, 0].transpose(1, 2)
    return output.reshape(*original_shape)


def second_difference_smoothness(lut: torch.Tensor) -> torch.Tensor:
    values = []
    for axis in (1, 2, 3):
        first = torch.diff(lut, dim=axis)
        values.append(torch.diff(first, dim=axis).square().mean())
    return torch.stack(values).mean()


def conditional_losses(
    prediction: torch.Tensor,
    target_lut: torch.Tensor,
    neutral: torch.Tensor,
    reference: torch.Tensor,
    weights: LossWeights,
) -> dict[str, torch.Tensor]:
    cube = F.smooth_l1_loss(prediction, target_lut)
    # The neutral image is normalized for the encoder, so recover [0,1] before LUT rendering.
    neutral_rgb = neutral * torch.as_tensor(v2.IMAGENET_STD, device=neutral.device) + torch.as_tensor(
        v2.IMAGENET_MEAN, device=neutral.device
    )
    neutral_rgb = neutral_rgb.permute(0, 2, 3, 1)
    reference_rgb = reference * torch.as_tensor(v2.IMAGENET_STD, device=reference.device) + torch.as_tensor(
        v2.IMAGENET_MEAN, device=reference.device
    )
    reference_rgb = reference_rgb.permute(0, 2, 3, 1)
    rendered = apply_lut_torch(prediction, neutral_rgb)
    image = F.smooth_l1_loss(rendered, reference_rgb)
    smoothness = second_difference_smoothness(prediction)
    total = weights.cube * cube + weights.image * image + weights.smoothness * smoothness
    return {"total": total, "cube": cube, "image": image, "smoothness": smoothness}


def style_consistency_losses(style_code: torch.Tensor, source_luts: list[str]) -> dict[str, torch.Tensor]:
    """Use positive/negative supervised contrast to avoid same-style latent collapse."""
    if len(source_luts) != style_code.shape[0]:
        raise ValueError("Style Code count and source LUT count differ")
    normalized = F.normalize(style_code, dim=1, eps=1e-6)
    similarities = normalized @ normalized.T
    same = torch.tensor(
        [[left == right and index != other for other, right in enumerate(source_luts)]
        for index, left in enumerate(source_luts)],
        dtype=torch.bool,
        device=style_code.device,
    )
    different = torch.tensor(
        [[left != right for right in source_luts] for left in source_luts],
        dtype=torch.bool,
        device=style_code.device,
    )
    if not same.any() or not different.any():
        raise ValueError("Style Consistency batch requires positive and negative LUT pairs")
    intra = 1.0 - similarities[same].mean()
    positive_cosine = similarities[same].mean()
    negative_cosine = similarities[different].mean()
    logits = []
    targets = []
    for index in range(len(source_luts)):
        candidates = [other for other in range(len(source_luts)) if other != index]
        positive = next(other for other in candidates if source_luts[other] == source_luts[index])
        logits.append(similarities[index, candidates] / STYLE_CONTRASTIVE_TEMPERATURE)
        targets.append(candidates.index(positive))
    contrastive = F.cross_entropy(torch.stack(logits), torch.tensor(targets, device=style_code.device))
    return {
        "style_intra": intra,
        "style_positive_cosine": positive_cosine,
        "style_negative_cosine": negative_cosine,
        "style_contrastive": contrastive,
        "style": contrastive + STYLE_INTRA_WEIGHT * intra,
    }


def move_batch(batch: dict) -> dict:
    return {key: value.to(DEVICE) if isinstance(value, torch.Tensor) else value for key, value in batch.items()}


def finite_loss_values(losses: dict[str, torch.Tensor]) -> dict[str, float]:
    values = {name: float(value.detach().cpu()) for name, value in losses.items()}
    if not all(np.isfinite(value) for value in values.values()):
        raise FloatingPointError(f"non-finite loss values: {values}")
    return values


def evaluate_single_prediction(prediction: np.ndarray, target: np.ndarray, observed_mask: np.ndarray) -> dict:
    return evaluator.evaluate_lut_pair(prediction, target, CUBE_DIM, observed_mask)


def export_lut_smoke(lut: np.ndarray, output: Path) -> dict:
    output.parent.mkdir(parents=True, exist_ok=True)
    save_float16_lut(lut, output)
    reloaded = evaluator.load_lut(output)
    if reloaded.shape != lut.shape:
        raise RuntimeError("export/reload LUT shape changed")
    if reloaded.min() < 0.0 or reloaded.max() > 1.0:
        raise RuntimeError("bounded decoder export left the [0,1] contract")
    return {
        "path": str(output),
        "reload_rmse": float(np.sqrt(np.square(reloaded - lut).mean())),
        "min": float(reloaded.min()),
        "max": float(reloaded.max()),
    }


def run_smoke_test(args: argparse.Namespace) -> Path:
    set_seed(args.seed)
    records = read_split_records(args.split_path, {"train"}, args.dataset_dir)
    masks = load_masks(args.mask_path)
    dataset = ConditionalLUTDataset(records, masks)
    loader = DataLoader(dataset, batch_size=args.smoke_batch_size, shuffle=False, collate_fn=collate_samples)
    batch = move_batch(next(iter(loader)))
    model = ConditionalLUTMVP(pretrained=False).to(DEVICE)
    optimizer = torch.optim.AdamW(model.parameters(), lr=args.smoke_learning_rate, weight_decay=0.0)
    weights = LossWeights()

    model.train()
    freeze_batch_norm(model.style_encoder)
    with torch.no_grad():
        initial_prediction, _ = model(batch["reference"])
        initial_losses = finite_loss_values(
            conditional_losses(initial_prediction, batch["target_lut"], batch["neutral"], batch["reference"], weights)
        )
    history = []
    for step in range(args.smoke_steps):
        optimizer.zero_grad(set_to_none=True)
        prediction, _ = model(batch["reference"])
        losses = conditional_losses(prediction, batch["target_lut"], batch["neutral"], batch["reference"], weights)
        finite_loss_values(losses)
        losses["total"].backward()
        gradient_norm = torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=10.0)
        optimizer.step()
        history.append({"step": step + 1, **finite_loss_values(losses), "gradient_norm": float(gradient_norm)})

    model.eval()
    with torch.no_grad():
        final_prediction, style_code = model(batch["reference"])
        final_losses = finite_loss_values(
            conditional_losses(final_prediction, batch["target_lut"], batch["neutral"], batch["reference"], weights)
        )
    prediction_np = final_prediction[0].cpu().numpy()
    target_np = batch["target_lut"][0].cpu().numpy()
    metrics = evaluate_single_prediction(prediction_np, target_np, batch["observed_mask"][0].cpu().numpy().astype(bool))
    output = args.report_path or REPORT_DIR / "mvp_skeleton_smoke_report.json"
    export = export_lut_smoke(prediction_np, output.with_suffix(".generated_17.bin"))
    report = {
        "schema_version": 1,
        "experiment_id": "MVP-SKELETON-001",
        "device": str(DEVICE),
        "renderer_contract": "bounded_generated_lut; target_accuracy_compares_clamped_srgb_render",
        "samples": batch["id"],
        "groups": batch["group"],
        "dataset_dir": str(args.dataset_dir),
        "split_path": str(args.split_path),
        "mask_path": str(args.mask_path),
        "style_code_shape": list(style_code.shape),
        "initial_losses": initial_losses,
        "final_losses": final_losses,
        "history": history,
        "first_sample_cube_metrics": metrics,
        "export_reload": export,
    }
    if final_losses["total"] > initial_losses["total"]:
        raise RuntimeError("one-batch smoke loss did not decrease; do not treat MVP as trainable")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    return output


def run_style_consistency_smoke_test(args: argparse.Namespace) -> Path:
    set_seed(args.seed)
    records = read_split_records(args.split_path, {"train"}, args.dataset_dir)
    selected_records = select_style_consistency_records(records)
    masks = load_masks(args.mask_path)
    batch = move_batch(collate_samples([ConditionalLUTDataset(selected_records, masks)[index] for index in range(len(selected_records))]))
    # Preserve source LUT IDs outside the tensor batch for the positive/negative pair contract.
    source_luts = [record["sourceLut"] for record in selected_records]
    model = ConditionalLUTMVP(pretrained=False).to(DEVICE)
    optimizer = torch.optim.AdamW(
        [
            {"params": model.style_encoder.parameters(), "lr": args.consistency_encoder_learning_rate},
            {"params": model.lut_decoder.parameters(), "lr": args.consistency_smoke_learning_rate},
        ],
        weight_decay=0.0,
    )
    weights = LossWeights()

    def loss_bundle(prediction: torch.Tensor, style_code: torch.Tensor) -> dict[str, torch.Tensor]:
        base = conditional_losses(prediction, batch["target_lut"], batch["neutral"], batch["reference"], weights)
        style = style_consistency_losses(style_code, source_luts)
        return base | style | {"total": base["total"] + STYLE_CONSISTENCY_WEIGHT * style["style"]}

    model.train()
    freeze_batch_norm(model.style_encoder)
    with torch.no_grad():
        initial_prediction, initial_style_code = model(batch["reference"])
        initial_losses = finite_loss_values(loss_bundle(initial_prediction, initial_style_code))
    history = []
    for step in range(args.smoke_steps):
        optimizer.zero_grad(set_to_none=True)
        prediction, style_code = model(batch["reference"])
        losses = loss_bundle(prediction, style_code)
        finite_loss_values(losses)
        losses["total"].backward()
        gradient_norm = torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=10.0)
        optimizer.step()
        history.append({"step": step + 1, **finite_loss_values(losses), "gradient_norm": float(gradient_norm)})

    model.eval()
    with torch.no_grad():
        final_prediction, final_style_code = model(batch["reference"])
        final_losses = finite_loss_values(loss_bundle(final_prediction, final_style_code))
    passed = (
        final_losses["total"] <= initial_losses["total"]
        and final_losses["style_positive_cosine"] > final_losses["style_negative_cosine"]
    )
    prediction_np = final_prediction[0].cpu().numpy()
    target_np = batch["target_lut"][0].cpu().numpy()
    output = args.report_path or REPORT_DIR / "style_consistency_smoke_v6_report.json"
    report = {
        "schema_version": 1,
        "experiment_id": "STYLE-CONSISTENCY-SMOKE-006",
        "device": str(DEVICE),
        "renderer_contract": "bounded_generated_lut; target_accuracy_compares_clamped_srgb_render",
        "samples": batch["id"],
        "source_luts": source_luts,
        "dataset_dir": str(args.dataset_dir),
        "split_path": str(args.split_path),
        "mask_path": str(args.mask_path),
        "style_code_shape": list(final_style_code.shape),
        "decoder_learning_rate": args.consistency_smoke_learning_rate,
        "style_encoder_learning_rate": args.consistency_encoder_learning_rate,
        "style_consistency_weight": STYLE_CONSISTENCY_WEIGHT,
        "style_contrastive_temperature": STYLE_CONTRASTIVE_TEMPERATURE,
        "style_intra_weight": STYLE_INTRA_WEIGHT,
        "initial_losses": initial_losses,
        "final_losses": final_losses,
        "passed": passed,
        "history": history,
        "first_sample_cube_metrics": evaluate_single_prediction(
            prediction_np, target_np, batch["observed_mask"][0].cpu().numpy().astype(bool)
        ),
        "export_reload": export_lut_smoke(prediction_np, output.with_suffix(".generated_17.bin")),
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    if not passed:
        raise RuntimeError(f"Style Consistency smoke failed; inspect preserved report: {output}")
    return output


def combined_training_losses(
    prediction: torch.Tensor,
    style_code: torch.Tensor,
    batch: dict,
    weights: LossWeights,
    style_weight: float = STYLE_CONSISTENCY_WEIGHT,
) -> dict[str, torch.Tensor]:
    base = conditional_losses(prediction, batch["target_lut"], batch["neutral"], batch["reference"], weights)
    style = style_consistency_losses(style_code, batch["source_lut"])
    return base | style | {"total": base["total"] + style_weight * style["style"]}


def structured_target_loss_from_parameters(
    curve: torch.Tensor, anchors: torch.Tensor, batch: dict
) -> dict[str, torch.Tensor]:
    """Compare normalized curve/six-anchor predictions with target-only labels."""
    curve_loss = F.smooth_l1_loss(curve, batch["target_tone_curve"])
    anchor_loss = F.smooth_l1_loss(anchors, batch["target_hue_anchors"])
    return {
        "tone_curve_target": curve_loss,
        "hue_anchor_target": anchor_loss,
        "structured_target": curve_loss + anchor_loss,
    }


def structured_target_loss(model: ConditionalLUTMVP, style_code: torch.Tensor, batch: dict) -> dict[str, torch.Tensor]:
    """Supervise only the explicitly structured decoder head, not test metrics."""
    return structured_target_loss_from_parameters(
        *model.lut_decoder.structured_parameters(style_code), batch
    )


def parallel_structured_auxiliary_loss(
    model: ConditionalLUTMVP, style_code: torch.Tensor, batch: dict
) -> dict[str, torch.Tensor]:
    """Regularize Style Code with a detached-from-rendering structured auxiliary head."""
    return structured_target_loss_from_parameters(
        *model.structured_auxiliary_parameters(style_code), batch
    )


def parameter_gradient_l2(loss: torch.Tensor, parameters: list[torch.nn.Parameter]) -> float:
    """Read a per-loss gradient scale without modifying .grad buffers."""
    gradients = torch.autograd.grad(loss, parameters, retain_graph=True, allow_unused=True)
    squared_norm = sum(float(gradient.detach().square().sum()) for gradient in gradients if gradient is not None)
    return float(np.sqrt(squared_norm))


def batch_instrumentation(model: ConditionalLUTMVP, prediction: torch.Tensor, style_code: torch.Tensor, losses: dict[str, torch.Tensor]) -> dict[str, float]:
    """Compact diagnostics for a fixed number of batches in a controlled run."""
    encoder_parameters = [parameter for parameter in model.style_encoder.parameters() if parameter.requires_grad]
    decoder_parameters = [parameter for parameter in model.lut_decoder.parameters() if parameter.requires_grad]
    residual_logits = model.lut_decoder.residual_logits(style_code)
    identity = evaluator.identity_lut(model.cube_dim)
    identity_tensor = torch.from_numpy(identity).to(prediction.device)
    return {
        "prediction_batch_variance": float(prediction.detach().var(dim=0, unbiased=False).mean()),
        "prediction_to_identity_rmse": float(torch.sqrt(torch.square(prediction.detach() - identity_tensor).mean())),
        "decoder_residual_logit_abs_mean": float(residual_logits.detach().abs().mean()),
        "decoder_residual_logit_std": float(residual_logits.detach().std(unbiased=False)),
        "gradient_l2_cube_encoder": parameter_gradient_l2(losses["cube"], encoder_parameters),
        "gradient_l2_cube_decoder": parameter_gradient_l2(losses["cube"], decoder_parameters),
        "gradient_l2_image_encoder": parameter_gradient_l2(losses["image"], encoder_parameters),
        "gradient_l2_image_decoder": parameter_gradient_l2(losses["image"], decoder_parameters),
        "gradient_l2_smoothness_decoder": parameter_gradient_l2(losses["smoothness"], decoder_parameters),
        "gradient_l2_style_encoder": parameter_gradient_l2(losses["style"], encoder_parameters),
    }


def validation_trajectory(predictions: list[torch.Tensor], residual_logits: list[torch.Tensor], style_codes: list[torch.Tensor]) -> dict[str, float]:
    """Summarize sample-to-sample variation across an entire validation epoch."""
    prediction_matrix = torch.cat([value.reshape(value.shape[0], -1) for value in predictions], dim=0)
    residual_matrix = torch.cat(residual_logits, dim=0)
    style_matrix = torch.cat(style_codes, dim=0)
    return {
        "samples": int(prediction_matrix.shape[0]),
        "prediction_output_variance": float(prediction_matrix.var(dim=0, unbiased=False).mean()),
        "decoder_residual_logit_variance": float(residual_matrix.var(dim=0, unbiased=False).mean()),
        "style_code_variance": float(style_matrix.var(dim=0, unbiased=False).mean()),
        "decoder_residual_logit_abs_mean": float(residual_matrix.abs().mean()),
    }


def train(args: argparse.Namespace) -> Path:
    if not args.experiment_id:
        raise ValueError("--experiment-id is required for --train so existing artifacts cannot be overwritten")
    set_seed(args.seed)
    train_records = read_split_records(args.split_path, {"train"}, args.dataset_dir)
    validation_records = read_split_records(args.split_path, {"validation"}, args.dataset_dir)
    validation_style_records = select_style_monitor_records(validation_records)
    masks = load_masks(args.mask_path)
    semantic_cache_dir = args.semantic_cache_dir
    if semantic_cache_dir is not None and not semantic_cache_dir.exists():
        raise FileNotFoundError(f"semantic cache directory is missing: {semantic_cache_dir}")
    train_dataset = ConditionalLUTDataset(train_records, masks, semantic_cache_dir)
    validation_dataset = ConditionalLUTDataset(validation_records, masks, semantic_cache_dir)
    validation_style_dataset = ConditionalLUTDataset(validation_style_records, masks, semantic_cache_dir)
    train_pair_sampler = SourcePairBatchSampler(train_records, args.batch_size, args.seed)
    train_loader = DataLoader(
        train_dataset, batch_sampler=train_pair_sampler, collate_fn=collate_samples
    )
    validation_accuracy_loader = DataLoader(
        validation_dataset,
        batch_size=args.batch_size,
        shuffle=False,
        collate_fn=collate_samples,
    )
    validation_style_loader = DataLoader(
        validation_style_dataset,
        batch_size=len(validation_style_dataset),
        shuffle=False,
        collate_fn=collate_samples,
    )
    model = ConditionalLUTMVP(
        pretrained=args.pretrained,
        decoder_output_mode=args.decoder_output_mode,
        decoder_hidden_dim=args.decoder_hidden_dim,
        structured_auxiliary=bool(args.parallel_structured_aux_weight),
        semantic_pooled_features=semantic_cache_dir is not None,
    ).to(DEVICE)
    decoder_parameters = list(model.lut_decoder.parameters())
    if model.structured_auxiliary_enabled:
        decoder_parameters.extend(model.structured_auxiliary_head.parameters())
    optimizer = torch.optim.AdamW(
        [
            {"params": model.style_encoder.parameters(), "lr": args.encoder_learning_rate},
            {"params": decoder_parameters, "lr": args.learning_rate},
        ],
        weight_decay=args.weight_decay,
    )
    scheduler = (
        torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=args.epochs, eta_min=0.0)
        if args.lr_scheduler == "cosine"
        else None
    )
    weights = LossWeights(cube=args.cube_weight, image=args.image_weight, smoothness=args.smoothness_weight)
    checkpoint_path = args.checkpoint_path or CHECKPOINT_DIR / f"conditional_lut_{args.experiment_id.lower()}.pt"
    report_path = args.report_path or REPORT_DIR / f"{args.experiment_id.lower()}_train_report.json"
    training_state_path = checkpoint_path.with_name(f"{checkpoint_path.stem}_training_state.pt")
    if args.resume_checkpoint:
        resume = torch.load(args.resume_checkpoint, map_location=DEVICE, weights_only=False)
        model.load_state_dict(resume["state_dict"])
        best_validation_cube = float(resume["best_validation_cube_loss"])
        completed_epochs = int(resume.get("completed_epochs", 1))
        best_epoch = int(resume.get("best_epoch", completed_epochs))
        epochs_without_improvement = int(resume.get("epochs_without_improvement", 0))
        checkpoint_saved = True
        history = json.loads(report_path.read_text())["history"] if report_path.exists() else []
    else:
        best_validation_cube = float("inf")
        completed_epochs = 0
        best_epoch = 0
        epochs_without_improvement = 0
        checkpoint_saved = False
        history = []
    if (checkpoint_path.exists() or report_path.exists()) and not args.resume_checkpoint:
        raise FileExistsError(f"refusing to overwrite existing experiment artifacts: {checkpoint_path}, {report_path}")

    stopped_early = False
    last_epoch = completed_epochs
    for epoch in range(completed_epochs + 1, completed_epochs + args.epochs + 1):
        last_epoch = epoch
        train_pair_sampler.set_epoch(epoch - 1)
        model.train()
        freeze_batch_norm(model.style_encoder)
        metric_names = ("total", "cube", "image", "smoothness", "style", "style_positive_cosine", "style_negative_cosine", "structured_target")
        train_totals = {name: 0.0 for name in metric_names}
        train_examples = 0
        instrumentation = []
        for batch_index, batch in enumerate(train_loader):
            batch = move_batch(batch)
            batch_examples = int(batch["reference"].shape[0])
            optimizer.zero_grad(set_to_none=True)
            prediction, style_code = model(batch["reference"], batch.get("semantic_masks"))
            losses = combined_training_losses(
                prediction, style_code, batch, weights, style_weight=args.style_consistency_weight
            )
            if args.structured_target_weight:
                structured = structured_target_loss(model, style_code, batch)
                losses = losses | structured | {
                    "total": losses["total"] + args.structured_target_weight * structured["structured_target"]
                }
            elif args.parallel_structured_aux_weight:
                structured = parallel_structured_auxiliary_loss(model, style_code, batch)
                losses = losses | structured | {
                    "total": losses["total"] + args.parallel_structured_aux_weight * structured["structured_target"]
                }
            else:
                losses["structured_target"] = torch.zeros((), device=prediction.device)
            finite_loss_values(losses)
            if batch_index < args.instrumentation_batches:
                instrumentation.append(batch_instrumentation(model, prediction, style_code, losses))
            losses["total"].backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=10.0)
            optimizer.step()
            for key in train_totals:
                train_totals[key] += float(losses[key].detach()) * batch_examples
            train_examples += batch_examples

        model.eval()
        validation_metric_names = ("total", "cube", "image", "smoothness")
        validation_totals = {name: 0.0 for name in validation_metric_names}
        validation_examples = 0
        validation_predictions = []
        validation_residual_logits = []
        validation_style_codes = []
        with torch.no_grad():
            for batch in validation_accuracy_loader:
                batch = move_batch(batch)
                batch_examples = int(batch["reference"].shape[0])
                prediction, style_code = model(batch["reference"], batch.get("semantic_masks"))
                losses = conditional_losses(
                    prediction, batch["target_lut"], batch["neutral"], batch["reference"], weights
                )
                for key in validation_totals:
                    validation_totals[key] += float(losses[key]) * batch_examples
                validation_examples += batch_examples
                validation_predictions.append(prediction.cpu())
                validation_residual_logits.append(model.lut_decoder.residual_logits(style_code).cpu())
                validation_style_codes.append(style_code.cpu())
        validation_style_names = (
            "style",
            "style_intra",
            "style_contrastive",
            "style_positive_cosine",
            "style_negative_cosine",
        )
        validation_style_totals = {name: 0.0 for name in validation_style_names}
        validation_style_examples = 0
        with torch.no_grad():
            for batch in validation_style_loader:
                batch = move_batch(batch)
                batch_examples = int(batch["reference"].shape[0])
                _, style_code = model(batch["reference"], batch.get("semantic_masks"))
                style_losses = style_consistency_losses(style_code, batch["source_lut"])
                for key in validation_style_totals:
                    validation_style_totals[key] += float(style_losses[key]) * batch_examples
                validation_style_examples += batch_examples
        train_mean = {key: value / train_examples for key, value in train_totals.items()}
        validation_mean = {
            key: value / validation_examples for key, value in validation_totals.items()
        }
        validation_style_mean = {
            key: value / validation_style_examples for key, value in validation_style_totals.items()
        }
        instrumentation_mean = {
            key: float(np.mean([item[key] for item in instrumentation]))
            for key in instrumentation[0]
        } if instrumentation else {}
        history.append({
            "epoch": epoch,
            "learning_rates": [float(group["lr"]) for group in optimizer.param_groups],
            "train": train_mean,
            "validation": validation_mean,
            "validation_style": validation_style_mean,
            "instrumentation": instrumentation_mean,
            "sampling": {
                "train": train_pair_sampler.sampling_summary(),
                "validation_accuracy": {
                    "records": validation_examples,
                    "coverage_fraction": 1.0,
                    "batches": len(validation_accuracy_loader),
                },
                "validation_style": {
                    "records": validation_style_examples,
                    "source_luts": len({record["sourceLut"] for record in validation_style_records}),
                    "coverage_fraction": 1.0,
                    "batches": len(validation_style_loader),
                },
            },
            "validation_trajectory": validation_trajectory(validation_predictions, validation_residual_logits, validation_style_codes),
        })
        style_separation = (
            validation_style_mean["style_positive_cosine"]
            - validation_style_mean["style_negative_cosine"]
        )
        print(
            f"epoch={epoch:03d} train={train_mean['total']:.6f} "
            f"validation_cube={validation_mean['cube']:.6f} style_separation={style_separation:.6f}"
        )
        improved = validation_mean["cube"] < best_validation_cube and style_separation > 0.0
        if improved:
            best_validation_cube = validation_mean["cube"]
            best_epoch = epoch
            epochs_without_improvement = 0
            checkpoint_saved = True
            CHECKPOINT_DIR.mkdir(parents=True, exist_ok=True)
            torch.save(
                {
                    "schema_version": 2,
                    "experiment_id": args.experiment_id,
                    "state_dict": model.state_dict(),
                    "style_dim": STYLE_DIM,
                    "cube_dim": CUBE_DIM,
                    "decoder_output_mode": args.decoder_output_mode,
                    "decoder_hidden_dim": args.decoder_hidden_dim,
                    "loss_weights": asdict(weights),
                    "style_consistency_weight": args.style_consistency_weight,
                    "structured_target_weight": args.structured_target_weight,
                    "parallel_structured_aux_weight": args.parallel_structured_aux_weight,
                    "structured_auxiliary_enabled": model.structured_auxiliary_enabled,
                    "semantic_pooled_features": model.semantic_pooled_features,
                    "semantic_cache_dir": str(semantic_cache_dir) if semantic_cache_dir is not None else None,
                    "structured_target_protocol": (
                        "normalized_neutral_luminance_curve_plus_six_saturation_scaled_hue_anchor_labels"
                        if args.structured_target_weight or args.parallel_structured_aux_weight else "none"
                    ),
                    "style_contrastive_temperature": STYLE_CONTRASTIVE_TEMPERATURE,
                    "encoder_batch_norm_frozen": True,
                    "encoder_learning_rate": args.encoder_learning_rate,
                    "decoder_learning_rate": args.learning_rate,
                    "dataset_dir": str(args.dataset_dir),
                    "split_path": str(args.split_path),
                    "mask_path": str(args.mask_path),
                    "renderer_contract": "bounded_generated_lut; target_accuracy_compares_clamped_srgb_render",
                    "training_sampler_protocol": "epoch_aware_full_coverage_source_pairs",
                    "validation_accuracy_protocol": "all_validation_records_sample_weighted",
                    "validation_style_protocol": "fixed_two_scenes_per_validation_lut",
                    "checkpoint_selection_metric": "full_validation_cube_smooth_l1",
                    "checkpoint_style_guardrail": "positive_cosine_minus_negative_cosine_gt_0",
                    "best_validation_cube_loss": best_validation_cube,
                    "best_epoch": best_epoch,
                    "early_stopping_patience": args.early_stopping_patience,
                    "validation_records": len(validation_records),
                },
                checkpoint_path,
            )
        elif checkpoint_saved:
            epochs_without_improvement += 1
        CHECKPOINT_DIR.mkdir(parents=True, exist_ok=True)
        torch.save(
            {
                "schema_version": 1,
                "state_dict": model.state_dict(),
                "completed_epochs": epoch,
                "best_epoch": best_epoch,
                "epochs_without_improvement": epochs_without_improvement,
                "best_validation_cube_loss": best_validation_cube,
                "selection_checkpoint": str(checkpoint_path),
                "experiment_id": args.experiment_id,
            },
            training_state_path,
        )
        if scheduler is not None:
            scheduler.step()
        if (
            args.early_stopping_patience > 0
            and checkpoint_saved
            and epochs_without_improvement >= args.early_stopping_patience
        ):
            stopped_early = True
            print(
                f"early_stopping epoch={epoch:03d} best_epoch={best_epoch:03d} "
                f"patience={args.early_stopping_patience}"
            )
            break
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(
        json.dumps({
            "schema_version": 2,
            "experiment_id": args.experiment_id,
            "checkpoint": str(checkpoint_path),
            "training_state": str(training_state_path),
            "completed_epochs": last_epoch,
            "requested_additional_epochs": args.epochs,
            "stopped_early": stopped_early,
            "early_stopping_patience": args.early_stopping_patience,
            "best_epoch": best_epoch,
            "instrumentation_batches": args.instrumentation_batches,
            "lr_scheduler": args.lr_scheduler,
            "encoder_learning_rate": args.encoder_learning_rate,
            "decoder_learning_rate": args.learning_rate,
            "style_consistency_weight": args.style_consistency_weight,
            "structured_target_weight": args.structured_target_weight,
            "parallel_structured_aux_weight": args.parallel_structured_aux_weight,
            "structured_auxiliary_enabled": model.structured_auxiliary_enabled,
            "semantic_pooled_features": model.semantic_pooled_features,
            "semantic_cache_dir": str(semantic_cache_dir) if semantic_cache_dir is not None else None,
            "structured_target_protocol": (
                "normalized_neutral_luminance_curve_plus_six_saturation_scaled_hue_anchor_labels"
                if args.structured_target_weight or args.parallel_structured_aux_weight else "none"
            ),
            "dataset_dir": str(args.dataset_dir),
            "split_path": str(args.split_path),
            "mask_path": str(args.mask_path),
            "training_sampler_protocol": "epoch_aware_full_coverage_source_pairs",
            "validation_accuracy_protocol": "all_validation_records_sample_weighted",
            "validation_style_protocol": "fixed_two_scenes_per_validation_lut",
            "checkpoint_selection_metric": "full_validation_cube_smooth_l1",
            "checkpoint_style_guardrail": "positive_cosine_minus_negative_cosine_gt_0",
            "history": history,
            "best_validation_cube_loss": best_validation_cube,
        }, indent=2) + "\n"
    )
    if not checkpoint_saved:
        raise RuntimeError(
            "no checkpoint met the Style separation guardrail; inspect the saved training report"
        )
    return report_path


def main() -> None:
    parser = argparse.ArgumentParser(description="Bounded direct conditional 17^3 LUT MVP.")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--smoke-test", action="store_true")
    mode.add_argument("--consistency-smoke-test", action="store_true")
    mode.add_argument("--train", action="store_true")
    parser.add_argument("--seed", type=int, default=20260729)
    parser.add_argument("--smoke-steps", type=int, default=4)
    parser.add_argument("--smoke-batch-size", type=int, default=2)
    parser.add_argument("--smoke-learning-rate", type=float, default=5e-3)
    parser.add_argument("--consistency-smoke-learning-rate", type=float, default=1e-3)
    parser.add_argument("--consistency-encoder-learning-rate", type=float, default=1e-4)
    parser.add_argument("--epochs", type=int, default=10)
    parser.add_argument(
        "--early-stopping-patience",
        type=int,
        default=0,
        help="stop after this many non-improving validation epochs; 0 disables",
    )
    parser.add_argument("--batch-size", type=int, default=DEFAULT_BATCH_SIZE)
    parser.add_argument("--learning-rate", type=float, default=DEFAULT_LEARNING_RATE)
    parser.add_argument("--encoder-learning-rate", type=float, default=1e-5)
    parser.add_argument("--weight-decay", type=float, default=1e-4)
    parser.add_argument("--cube-weight", type=float, default=1.0)
    parser.add_argument("--image-weight", type=float, default=0.25)
    parser.add_argument("--smoothness-weight", type=float, default=0.01)
    parser.add_argument("--style-consistency-weight", type=float, default=STYLE_CONSISTENCY_WEIGHT)
    parser.add_argument("--structured-target-weight", type=float, default=0.0)
    parser.add_argument("--parallel-structured-aux-weight", type=float, default=0.0)
    parser.add_argument("--semantic-cache-dir", type=Path, help="checksum-pinned six-class cache; enables semantic pooled Style Code features")
    parser.add_argument("--experiment-id", help="unique ID required for a training run; prevents artifact overwrite")
    parser.add_argument(
        "--dataset-dir",
        type=Path,
        default=DATASET_DIR,
        help="neutral/graded/luts dataset root for every mode",
    )
    parser.add_argument(
        "--split-path",
        type=Path,
        default=SPLIT_PATH,
        help="split JSONL used only for --train; defaults to the LUT-holdout contract",
    )
    parser.add_argument(
        "--mask-path",
        type=Path,
        default=MASK_PATH,
        help="observed-color mask archive for every mode",
    )
    parser.add_argument("--checkpoint-path", type=Path, help="new checkpoint path; defaults to an experiment-ID-specific name")
    parser.add_argument("--report-path", type=Path, help="new report path; defaults to an experiment-ID-specific name")
    parser.add_argument("--resume-checkpoint", type=Path, help="latest training state or compatible checkpoint to continue without overwriting its history")
    parser.add_argument("--instrumentation-batches", type=int, default=0, help="per epoch batches with per-loss gradient and decoder diagnostics")
    parser.add_argument("--decoder-output-mode", choices=("identity_logit", "bounded_residual", "tone_curve", "tone_curve_hue_anchor"), default="identity_logit")
    parser.add_argument("--decoder-hidden-dim", type=int, default=512, help="decoder trunk width; use a single controlled change per experiment")
    parser.add_argument("--lr-scheduler", choices=("none", "cosine"), default="none", help="epoch-level schedule applied after validation")
    parser.add_argument("--pretrained", action="store_true", help="allow timm to load pretrained encoder weights")
    args = parser.parse_args()
    positive = (args.smoke_steps, args.smoke_batch_size, args.epochs, args.batch_size)
    if any(value <= 0 for value in positive) or args.instrumentation_batches < 0 or args.decoder_hidden_dim <= 0 or args.early_stopping_patience < 0:
        parser.error("steps, batch sizes, and epochs must be positive")
    if any(value < 0 for value in (args.learning_rate, args.encoder_learning_rate, args.weight_decay, args.cube_weight, args.image_weight, args.smoothness_weight, args.style_consistency_weight, args.structured_target_weight, args.parallel_structured_aux_weight)):
        parser.error("loss weights and optimizer values must be non-negative")
    if args.structured_target_weight and args.decoder_output_mode != "tone_curve_hue_anchor":
        parser.error("--structured-target-weight requires --decoder-output-mode tone_curve_hue_anchor")
    if args.parallel_structured_aux_weight and args.decoder_output_mode != "identity_logit":
        parser.error("--parallel-structured-aux-weight requires --decoder-output-mode identity_logit")
    if args.structured_target_weight and args.parallel_structured_aux_weight:
        parser.error("structured decoder supervision and parallel auxiliary supervision cannot be combined")
    if args.parallel_structured_aux_weight and args.semantic_cache_dir is not None:
        parser.error("parallel structured auxiliary and semantic pooled features are separate controlled factors")
    if args.smoke_test:
        output = run_smoke_test(args)
    elif args.consistency_smoke_test:
        output = run_style_consistency_smoke_test(args)
    else:
        output = train(args)
    print(f"conditional LUT MVP complete -> {output}")


if __name__ == "__main__":
    main()
