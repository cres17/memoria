"""V2 balanced basis-residual LUT training.

This experiment replaces direct 3D-LUT regression with a small set of bounded
coefficients. It only accepts the balanced manifest produced by
``2_generate_dataset.py`` and keeps complete LUTs out of validation.

Usage:
  python 11_train_basis_v2.py --fit-basis --train

Artifacts:
  checkpoints/basis_v2_lut.npz
  checkpoints/basis_v2_color.pt
"""

import argparse
import hashlib
import json
import math
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np
from PIL import Image
import timm
import torch
import torch.nn as nn
import torch.nn.functional as F
from torch.amp import GradScaler, autocast
from torch.utils.data import DataLoader, Dataset, WeightedRandomSampler


PIPELINE_DIR = Path(__file__).resolve().parent
DATASET_DIR = PIPELINE_DIR / "data/dataset"
CHECKPOINT_DIR = PIPELINE_DIR / "checkpoints"
BASIS_PATH = CHECKPOINT_DIR / "basis_v2_lut.npz"
MODEL_PATH = CHECKPOINT_DIR / "basis_v2_color.pt"
REPORT_PATH = CHECKPOINT_DIR / "basis_v2_color.report.json"

LUT_DIM = 65
BASIS_DIM = 17
NUM_BASES = 12
COEFFICIENT_BOUND = 2.0
COEFFICIENT_TARGET_MARGIN = 0.95
IMAGE_SIZE = 256
BATCH_SIZE = 32
EPOCHS = 60
LEARNING_RATE = 2e-4
WEIGHT_DECAY = 1e-4
EARLY_STOPPING_PATIENCE = 15
VAL_RATIO = 0.10
SEED = 20260720

SOURCE_GROUP_BY_KIND = {
    "cube": "crawled",
    "bin": "app",
    "canon_clog2": "canon",
    "canon_clog3": "canon",
}
SOURCE_GROUPS = ("crawled", "app", "canon")
IMAGENET_MEAN = np.array([0.485, 0.456, 0.406], dtype=np.float32)[:, None, None]
IMAGENET_STD = np.array([0.229, 0.224, 0.225], dtype=np.float32)[:, None, None]
DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")


def load_image_tensor(path: Path) -> torch.Tensor:
    with Image.open(path) as image:
        image = image.convert("RGB").resize((IMAGE_SIZE, IMAGE_SIZE))
    image = np.asarray(image, dtype=np.float32).transpose(2, 0, 1) / 255.0
    image = (image - IMAGENET_MEAN) / IMAGENET_STD
    return torch.from_numpy(image)


def load_lut_tensor(path: Path) -> torch.Tensor:
    lut = np.fromfile(path, dtype=np.float16).astype(np.float32)
    return torch.from_numpy(lut).reshape(LUT_DIM, LUT_DIM, LUT_DIM, 3)


def build_encoder(pretrained: bool = True):
    try:
        return timm.create_model(
            "mobilenetv3_small_100", pretrained=pretrained, num_classes=0, global_pool="avg"
        ), pretrained
    except Exception as error:
        if not pretrained:
            raise
        print(f"pretrained backbone unavailable, falling back to random init: {error}")
        return timm.create_model(
            "mobilenetv3_small_100", pretrained=False, num_classes=0, global_pool="avg"
        ), False


def read_manifest(root: Path) -> list[dict]:
    """Read and validate the balanced, sRGB-domain dataset manifest."""
    manifest_path = root / "manifest.jsonl"
    if not manifest_path.exists():
        raise FileNotFoundError(
            f"{manifest_path} is missing. Run 2_generate_dataset.py --clean first."
        )

    records = []
    for line_number, line in enumerate(manifest_path.read_text().splitlines(), start=1):
        if not line.strip():
            continue
        try:
            row = json.loads(line)
            sample_id = row["id"]
            lut_kind = row["lutKind"]
            sampling_group = row["samplingGroup"]
            sampling_mode = row["samplingMode"]
            input_domain = row["inputDomain"]
            source_lut = row["sourceLut"]
        except (json.JSONDecodeError, KeyError) as error:
            raise ValueError(
                f"{manifest_path}:{line_number} is not a V2-ready manifest: {error}"
            ) from error

        expected_group = SOURCE_GROUP_BY_KIND.get(lut_kind)
        expected_domain = "srgb_composed" if lut_kind.startswith("canon_") else "srgb"
        if (expected_group is None or sampling_group != expected_group or
                sampling_mode != "balanced_source" or input_domain != expected_domain):
            raise ValueError(
                f"{manifest_path}:{line_number} does not satisfy the balanced V2 contract. "
                "Regenerate the dataset with 2_generate_dataset.py --clean."
            )

        image_path = root / "graded" / f"{sample_id}.jpg"
        lut_path = root / "luts" / f"{sample_id}.bin"
        if not image_path.exists() or not lut_path.exists():
            raise FileNotFoundError(f"missing files for manifest sample {sample_id}")
        records.append({
            "id": sample_id,
            "image_path": image_path,
            "lut_path": lut_path,
            "source_lut": source_lut,
            "lut_kind": lut_kind,
            "group": sampling_group,
        })

    if not records:
        raise ValueError("manifest has no records")
    counts = Counter(record["group"] for record in records)
    if set(counts) != set(SOURCE_GROUPS) or max(counts.values()) - min(counts.values()) > 1:
        raise ValueError(f"manifest is not source-balanced: {dict(counts)}")
    return records


def read_explicit_split(records: list[dict], split_path: Path) -> tuple[list[dict], list[dict], list[dict], dict]:
    """Select explicit train/validation/test records without re-splitting LUTs.

    This is used for the LUT-family contract, where the provided validation and
    test families must never participate in basis fitting or predictor updates.
    """
    if not split_path.exists():
        raise FileNotFoundError(split_path)
    by_id = {record["id"]: record for record in records}
    selected = {"train": [], "validation": [], "test": []}
    for line_number, line in enumerate(split_path.read_text().splitlines(), start=1):
        if not line.strip():
            continue
        row = json.loads(line)
        try:
            record = by_id[row["id"]]
            partition = row["split"]
        except KeyError as error:
            raise ValueError(f"{split_path}:{line_number} has an unknown record or partition: {error}") from error
        if partition not in selected:
            raise ValueError(f"{split_path}:{line_number} has unsupported partition {partition!r}")
        if row.get("sourceLut") != record["source_lut"] or row.get("samplingGroup") != record["group"]:
            raise ValueError(f"{split_path}:{line_number} does not match the dataset manifest")
        selected[partition].append(record)
    if any(not selected[partition] for partition in selected):
        raise ValueError(f"{split_path} must contain non-empty train, validation, and test partitions")
    source_sets = {
        partition: {record["source_lut"] for record in partition_records}
        for partition, partition_records in selected.items()
    }
    overlaps = {
        f"{left}_{right}": len(source_sets[left] & source_sets[right])
        for left, right in (("train", "validation"), ("train", "test"), ("validation", "test"))
    }
    if any(overlaps.values()):
        raise ValueError(f"source LUT leakage in explicit split: {overlaps}")
    metadata = {
        "split_path": str(split_path),
        "split_type": "explicit_source_lut_holdout",
        "records": {partition: len(partition_records) for partition, partition_records in selected.items()},
        "source_luts": {partition: len(source_sets[partition]) for partition in selected},
        "source_lut_overlap_counts": overlaps,
        "source_fingerprints": {
            partition: source_fingerprint(source_sets[partition]) for partition in selected
        },
    }
    return selected["train"], selected["validation"], selected["test"], metadata


def split_lut_sources(records: list[dict], val_ratio: float, seed: int):
    """Hold out whole LUTs while keeping every source group represented."""
    source_groups = defaultdict(list)
    for record in records:
        source_groups[record["source_lut"]].append(record)

    grouped_sources = defaultdict(list)
    for source_lut, source_records in source_groups.items():
        grouped_sources[source_records[0]["group"]].append(source_lut)

    rng = np.random.default_rng(seed)
    validation_sources = set()
    for group in SOURCE_GROUPS:
        sources = sorted(grouped_sources[group])
        if len(sources) < 2:
            raise ValueError(f"{group} needs at least two LUTs for a grouped split")
        rng.shuffle(sources)
        count = min(len(sources) - 1, max(1, round(len(sources) * val_ratio)))
        validation_sources.update(sources[:count])

    train_records = [record for record in records if record["source_lut"] not in validation_sources]
    validation_records = [record for record in records if record["source_lut"] in validation_sources]
    return train_records, validation_records, sorted(validation_sources)


def load_small_lut(path: Path) -> np.ndarray:
    values = np.fromfile(path, dtype=np.float16).astype(np.float32)
    expected = LUT_DIM * LUT_DIM * LUT_DIM * 3
    if values.size != expected:
        raise ValueError(f"{path} contains {values.size} values; expected {expected}")
    lut = values.reshape(LUT_DIM, LUT_DIM, LUT_DIM, 3)
    indices = np.linspace(0, LUT_DIM - 1, BASIS_DIM).round().astype(np.int64)
    return lut[np.ix_(indices, indices, indices)].reshape(-1).astype(np.float32)


def unique_lut_vectors(records: list[dict]) -> dict[str, np.ndarray]:
    """Load each generated target LUT once, independent of image-pair counts."""
    representatives = {}
    for record in records:
        representatives.setdefault(record["source_lut"], record["lut_path"])
    return {
        source_lut: load_small_lut(lut_path)
        for source_lut, lut_path in sorted(representatives.items())
    }


def balanced_pca_samples(records: list[dict], vectors_by_source: dict[str, np.ndarray]):
    """Repeat smaller source groups so PCA is not dominated by Canon LUT count."""
    sources_by_group = defaultdict(list)
    for record in records:
        source_lut = record["source_lut"]
        if source_lut not in sources_by_group[record["group"]]:
            sources_by_group[record["group"]].append(source_lut)
    for group in SOURCE_GROUPS:
        sources_by_group[group].sort()
        if not sources_by_group[group]:
            raise ValueError(f"missing {group} LUTs for balanced PCA")

    samples_per_group = max(len(sources_by_group[group]) for group in SOURCE_GROUPS)
    balanced_sources = []
    for group in SOURCE_GROUPS:
        sources = sources_by_group[group]
        balanced_sources.extend(sources[index % len(sources)] for index in range(samples_per_group))
    return np.stack([vectors_by_source[source] for source in balanced_sources]), {
        group: len(sources_by_group[group]) for group in SOURCE_GROUPS
    }


def source_fingerprint(source_luts) -> str:
    payload = "\n".join(sorted(source_luts)).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def fit_basis(train_records: list[dict], num_bases: int, basis_path: Path, split_metadata: dict):
    """Fit PCA only on training LUTs, so validation LUTs cannot leak into bases."""
    vectors_by_source = unique_lut_vectors(train_records)
    samples, unique_counts_by_group = balanced_pca_samples(train_records, vectors_by_source)
    mean = samples.mean(axis=0)
    residuals = samples - mean
    _, singular_values, right_vectors = np.linalg.svd(residuals, full_matrices=False)
    actual_bases = min(num_bases, right_vectors.shape[0])
    raw_bases = right_vectors[:actual_bases]
    raw_coefficients = residuals @ raw_bases.T
    coefficient_scales = np.maximum(
        np.max(np.abs(raw_coefficients), axis=0) /
        (COEFFICIENT_BOUND * COEFFICIENT_TARGET_MARGIN),
        1e-3,
    ).astype(np.float32)
    bases = (raw_bases * coefficient_scales[:, None]).astype(np.float32)

    basis_path.parent.mkdir(parents=True, exist_ok=True)
    np.savez_compressed(
        basis_path,
        mean=mean.reshape(BASIS_DIM, BASIS_DIM, BASIS_DIM, 3).astype(np.float32),
        bases=bases.reshape(actual_bases, BASIS_DIM, BASIS_DIM, BASIS_DIM, 3),
        basis_dim=BASIS_DIM,
        num_bases=actual_bases,
        coefficient_bound=COEFFICIENT_BOUND,
        coefficient_scales=coefficient_scales,
        coefficient_space="normalized_scaled_bases",
        lut_axis_order="r_fastest_rgb",
        train_source_fingerprint=source_fingerprint(vectors_by_source),
        train_source_count=len(vectors_by_source),
        train_unique_source_counts_by_group=json.dumps(unique_counts_by_group, sort_keys=True),
        pca_samples_per_group=samples.shape[0] // len(SOURCE_GROUPS),
        split_metadata=json.dumps(split_metadata, sort_keys=True),
        explained_energy=float(
            (singular_values[:actual_bases] ** 2).sum() /
            max((singular_values ** 2).sum(), 1e-12)
        ),
    )
    print(
        f"saved {actual_bases} train-only bases from {len(vectors_by_source)} LUTs "
        f"with balanced PCA groups {unique_counts_by_group} "
        f"(explained_energy={float((singular_values[:actual_bases] ** 2).sum() / max((singular_values ** 2).sum(), 1e-12)):.4f})"
    )


def load_basis(train_records: list[dict], basis_path: Path):
    if not basis_path.exists():
        raise RuntimeError("basis artifact is missing; run with --fit-basis first")
    raw = np.load(basis_path)
    if (int(raw["basis_dim"]) != BASIS_DIM or
            str(raw["coefficient_space"]) != "normalized_scaled_bases" or
            str(raw["lut_axis_order"]) != "r_fastest_rgb"):
        raise RuntimeError("basis artifact contract does not match V2")
    expected_fingerprint = source_fingerprint({record["source_lut"] for record in train_records})
    if str(raw["train_source_fingerprint"]) != expected_fingerprint:
        raise RuntimeError("basis artifact was fit on a different train LUT split; rerun --fit-basis")
    mean = raw["mean"].reshape(-1).astype(np.float32)
    bases = raw["bases"].reshape(raw["bases"].shape[0], -1).astype(np.float32)
    scales = raw["coefficient_scales"].astype(np.float32)
    if scales.shape != (bases.shape[0],) or not np.all(np.isfinite(scales)) or np.any(scales <= 0):
        raise RuntimeError("basis artifact has invalid coefficient scales")
    return mean, bases, scales


def coefficients_for_records(records: list[dict], mean, bases, scales):
    vectors_by_source = unique_lut_vectors(records)
    coefficients = {}
    for source_lut, vector in vectors_by_source.items():
        # Scaled basis projection: (residual @ basis.T) / scale².
        coefficient = ((vector - mean) @ bases.T) / (scales ** 2)
        coefficients[source_lut] = np.clip(
            coefficient, -COEFFICIENT_BOUND * COEFFICIENT_TARGET_MARGIN,
            COEFFICIENT_BOUND * COEFFICIENT_TARGET_MARGIN,
        ).astype(np.float32)
    return vectors_by_source, coefficients


class BalancedBasisDataset(Dataset):
    def __init__(self, records: list[dict], vectors_by_source, coefficients_by_source):
        self.records = records
        self.vectors_by_source = vectors_by_source
        self.coefficients_by_source = coefficients_by_source

    def __len__(self):
        return len(self.records)

    def __getitem__(self, index):
        record = self.records[index]
        return (
            load_image_tensor(record["image_path"]),
            torch.from_numpy(self.coefficients_by_source[record["source_lut"]]),
            torch.from_numpy(self.vectors_by_source[record["source_lut"]]),
        )


class BasisResidualNetV2(nn.Module):
    """MobileNet encoder that emits bounded basis coefficients, not a 3D LUT."""
    def __init__(self, num_bases: int, pretrained: bool = True):
        super().__init__()
        self.encoder, self.encoder_pretrained = build_encoder(pretrained=pretrained)
        with torch.no_grad():
            feature_dim = self.encoder(torch.zeros(1, 3, IMAGE_SIZE, IMAGE_SIZE)).shape[-1]
        self.head = nn.Sequential(
            nn.Linear(feature_dim, 256), nn.SiLU(), nn.Dropout(0.1),
            nn.Linear(256, num_bases), nn.Tanh(),
        )

    def forward(self, image):
        return self.head(self.encoder(image)) * COEFFICIENT_BOUND


def reconstruct(coefficients: torch.Tensor, mean: torch.Tensor, bases: torch.Tensor):
    return mean.unsqueeze(0) + coefficients @ bases


def counts_by_group(records: list[dict]):
    return {group: sum(record["group"] == group for record in records) for group in SOURCE_GROUPS}


def make_balanced_sampler(records: list[dict]):
    counts = counts_by_group(records)
    weights = torch.DoubleTensor([1.0 / counts[record["group"]] for record in records])
    return WeightedRandomSampler(weights, num_samples=len(records), replacement=True)


def summarize_metric_bucket(bucket: dict) -> dict:
    count = bucket["count"]
    if count == 0:
        return {"count": 0}
    return {
        "count": count,
        "loss": bucket["loss"] / count,
        "coefficient_mse": bucket["coefficient_mse"] / count,
        "small_lut_rmse": bucket["small_lut_rmse"] / count,
    }


def evaluate_records(model, records: list[dict], vectors_by_source, coefficients_by_source,
                     mean_tensor: torch.Tensor, basis_tensor: torch.Tensor):
    """Compute per-group and per-source validation metrics for a fixed record set."""
    grouped = {group: {"count": 0, "loss": 0.0, "coefficient_mse": 0.0, "small_lut_rmse": 0.0}
               for group in SOURCE_GROUPS}
    by_source = {}
    total = {"count": 0, "loss": 0.0, "coefficient_mse": 0.0, "small_lut_rmse": 0.0}

    model.eval()
    with torch.no_grad():
        for record in records:
            image = load_image_tensor(record["image_path"]).unsqueeze(0).to(DEVICE)
            target_coefficients = torch.from_numpy(
                coefficients_by_source[record["source_lut"]]
            ).unsqueeze(0).to(DEVICE)
            target_lut = torch.from_numpy(vectors_by_source[record["source_lut"]]).unsqueeze(0).to(DEVICE)
            predicted_coefficients = model(image)
            predicted_lut = reconstruct(predicted_coefficients, mean_tensor, basis_tensor)
            coefficient_mse = F.mse_loss(predicted_coefficients, target_coefficients).item()
            reconstruction_loss = F.smooth_l1_loss(predicted_lut, target_lut).item()
            small_lut_rmse = F.mse_loss(predicted_lut, target_lut).sqrt().item()
            loss = coefficient_mse + 10.0 * reconstruction_loss

            group = record["group"]
            source_lut = record["source_lut"]
            grouped[group]["count"] += 1
            grouped[group]["loss"] += loss
            grouped[group]["coefficient_mse"] += coefficient_mse
            grouped[group]["small_lut_rmse"] += small_lut_rmse

            source_bucket = by_source.setdefault(
                source_lut, {"count": 0, "group": group, "loss": 0.0,
                             "coefficient_mse": 0.0, "small_lut_rmse": 0.0}
            )
            source_bucket["count"] += 1
            source_bucket["loss"] += loss
            source_bucket["coefficient_mse"] += coefficient_mse
            source_bucket["small_lut_rmse"] += small_lut_rmse

            total["count"] += 1
            total["loss"] += loss
            total["coefficient_mse"] += coefficient_mse
            total["small_lut_rmse"] += small_lut_rmse

    report = {
        "overall": summarize_metric_bucket(total),
        "by_group": {group: summarize_metric_bucket(bucket) for group, bucket in grouped.items()},
        "by_source_lut": {
            source_lut: summarize_metric_bucket(bucket) | {"group": bucket["group"]}
            for source_lut, bucket in by_source.items()
        },
    }
    report["top_sources_by_small_lut_rmse"] = [
        {
            "source_lut": source_lut,
            "group": bucket["group"],
            "small_lut_rmse": bucket["small_lut_rmse"] / bucket["count"],
            "coefficient_mse": bucket["coefficient_mse"] / bucket["count"],
            "loss": bucket["loss"] / bucket["count"],
        }
        for source_lut, bucket in sorted(
            by_source.items(), key=lambda item: item[1]["small_lut_rmse"] / item[1]["count"], reverse=True
        )[:10]
    ]
    return report


def train(
    train_records: list[dict],
    validation_records: list[dict],
    epochs: int,
    batch_size: int,
    num_bases: int,
    basis_path: Path,
    model_path: Path,
    report_path: Path,
    split_metadata: dict,
):
    validation_sources = sorted({record["source_lut"] for record in validation_records})
    mean, bases, scales = load_basis(train_records, basis_path)
    if bases.shape[0] != num_bases:
        raise RuntimeError(
            f"basis artifact has {bases.shape[0]} bases but --num-bases={num_bases}; rerun --fit-basis"
        )

    train_vectors, train_coefficients = coefficients_for_records(train_records, mean, bases, scales)
    validation_vectors, validation_coefficients = coefficients_for_records(
        validation_records, mean, bases, scales
    )
    train_dataset = BalancedBasisDataset(train_records, train_vectors, train_coefficients)
    validation_dataset = BalancedBasisDataset(
        validation_records, validation_vectors, validation_coefficients
    )
    train_loader = DataLoader(
        train_dataset, batch_size=batch_size, sampler=make_balanced_sampler(train_records), num_workers=0
    )
    validation_loader = DataLoader(validation_dataset, batch_size=batch_size, shuffle=False, num_workers=0)

    model = BasisResidualNetV2(bases.shape[0]).to(DEVICE)
    optimizer = torch.optim.AdamW(model.parameters(), lr=LEARNING_RATE, weight_decay=WEIGHT_DECAY)
    scaler = GradScaler("cuda", enabled=DEVICE.type == "cuda")
    mean_tensor = torch.from_numpy(mean).to(DEVICE)
    basis_tensor = torch.from_numpy(bases).to(DEVICE)
    best_loss = float("inf")
    epochs_without_improvement = 0

    print(f"device={DEVICE}; train={len(train_dataset)} {counts_by_group(train_records)}; "
          f"val={len(validation_dataset)} {counts_by_group(validation_records)}; "
          f"held_out_luts={len(validation_sources)}")
    for epoch in range(epochs):
        model.train()
        train_losses = []
        for image, target_coefficients, target_lut in train_loader:
            image = image.to(DEVICE)
            target_coefficients = target_coefficients.to(DEVICE)
            target_lut = target_lut.to(DEVICE)
            optimizer.zero_grad(set_to_none=True)
            with autocast(DEVICE.type, enabled=DEVICE.type == "cuda"):
                predicted_coefficients = model(image)
                predicted_lut = reconstruct(predicted_coefficients, mean_tensor, basis_tensor)
                coefficient_loss = F.mse_loss(predicted_coefficients, target_coefficients)
                reconstruction_loss = F.smooth_l1_loss(predicted_lut, target_lut)
                loss = coefficient_loss + 10.0 * reconstruction_loss
            scaler.scale(loss).backward()
            scaler.unscale_(optimizer)
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            scaler.step(optimizer)
            scaler.update()
            train_losses.append(loss.item())

        model.eval()
        validation_losses = []
        validation_coefficient_mse = []
        validation_lut_rmse = []
        with torch.no_grad():
            for image, target_coefficients, target_lut in validation_loader:
                image = image.to(DEVICE)
                target_coefficients = target_coefficients.to(DEVICE)
                target_lut = target_lut.to(DEVICE)
                predicted_coefficients = model(image)
                predicted_lut = reconstruct(predicted_coefficients, mean_tensor, basis_tensor)
                coefficient_mse = F.mse_loss(predicted_coefficients, target_coefficients)
                reconstruction_loss = F.smooth_l1_loss(predicted_lut, target_lut)
                validation_losses.append((coefficient_mse + 10.0 * reconstruction_loss).item())
                validation_coefficient_mse.append(coefficient_mse.item())
                validation_lut_rmse.append(F.mse_loss(predicted_lut, target_lut).sqrt().item())
        validation_loss = float(np.mean(validation_losses))
        print(
            f"epoch={epoch + 1:02d} train_loss={float(np.mean(train_losses)):.6f} "
            f"val_loss={validation_loss:.6f} "
            f"val_coeff_mse={float(np.mean(validation_coefficient_mse)):.6f} "
            f"val_small_lut_rmse={float(np.mean(validation_lut_rmse)):.6f}"
        )

        if validation_loss < best_loss:
            best_loss = validation_loss
            epochs_without_improvement = 0
            validation_report = evaluate_records(
                model,
                validation_dataset.records,
                validation_vectors,
                validation_coefficients,
                mean_tensor,
                basis_tensor,
            )
            model_path.parent.mkdir(parents=True, exist_ok=True)
            checkpoint = {
                "state_dict": model.state_dict(),
                "basis_path": str(basis_path),
                "basis_dim": BASIS_DIM,
                "num_bases": bases.shape[0],
                "coefficient_bound": COEFFICIENT_BOUND,
                "coefficient_space": "normalized_scaled_bases",
                "pretrained_weights": bool(model.encoder_pretrained),
                "epoch": epoch,
                "val_loss": validation_loss,
                "val_coefficient_mse": float(np.mean(validation_coefficient_mse)),
                "val_small_lut_rmse": float(np.mean(validation_lut_rmse)),
                "train_counts_by_group": counts_by_group(train_records),
                "validation_counts_by_group": counts_by_group(validation_records),
                "validation_lut_sources": validation_sources,
                "validation_report": validation_report,
                "validation_report_path": str(report_path),
                "split_metadata": split_metadata,
            }
            torch.save(checkpoint, model_path)
            with report_path.open("w") as output:
                json.dump(validation_report, output, indent=2)
                output.write("\n")
            top_source = validation_report["top_sources_by_small_lut_rmse"][0]
            group_summary = ", ".join(
                f"{group}: {validation_report['by_group'][group]['small_lut_rmse']:.4f}"
                for group in SOURCE_GROUPS
            )
            print(
                "  validation_report "
                f"group_rmse={{{group_summary}}} "
                f"worst_source={Path(top_source['source_lut']).name} "
                f"worst_rmse={top_source['small_lut_rmse']:.4f}"
            )
        else:
            epochs_without_improvement += 1
            if epochs_without_improvement >= EARLY_STOPPING_PATIENCE:
                print(f"early_stopping epoch={epoch + 1} best_val_loss={best_loss:.6f}")
                break
    print(f"saved best V2 checkpoint -> {model_path} (val_loss={best_loss:.6f})")


def main():
    parser = argparse.ArgumentParser(description="Train the balanced V2 basis-residual LUT model.")
    parser.add_argument("--fit-basis", action="store_true")
    parser.add_argument("--train", action="store_true")
    parser.add_argument("--num-bases", type=int, default=NUM_BASES)
    parser.add_argument("--epochs", type=int, default=EPOCHS)
    parser.add_argument("--batch-size", type=int, default=BATCH_SIZE)
    parser.add_argument("--seed", type=int, default=SEED)
    parser.add_argument("--split-path", type=Path, help="explicit source-LUT split JSONL; do not re-split its partitions")
    parser.add_argument("--experiment-id", help="required with --split-path; keeps family-contract artifacts separate")
    parser.add_argument("--basis-path", type=Path)
    parser.add_argument("--model-path", type=Path)
    parser.add_argument("--report-path", type=Path)
    args = parser.parse_args()
    if not args.fit_basis and not args.train:
        parser.error("choose --fit-basis and/or --train")
    if args.num_bases <= 0 or args.epochs <= 0 or args.batch_size <= 0:
        parser.error("--num-bases, --epochs, and --batch-size must be positive")

    records = read_manifest(DATASET_DIR)
    if args.split_path:
        if not args.experiment_id:
            parser.error("--experiment-id is required with --split-path")
        train_records, validation_records, test_records, split_metadata = read_explicit_split(records, args.split_path)
        artifact_stem = args.experiment_id.lower().replace("_", "-")
        basis_path = args.basis_path or CHECKPOINT_DIR / f"basis_v2_{artifact_stem}.npz"
        model_path = args.model_path or CHECKPOINT_DIR / f"basis_v2_{artifact_stem}.pt"
        report_path = args.report_path or CHECKPOINT_DIR / f"basis_v2_{artifact_stem}.report.json"
        if args.fit_basis and basis_path.exists():
            raise FileExistsError(f"refusing to overwrite basis artifact: {basis_path}")
        if args.train and (model_path.exists() or report_path.exists()):
            raise FileExistsError(f"refusing to overwrite model/report artifacts: {model_path}, {report_path}")
    else:
        train_records, validation_records, _ = split_lut_sources(records, VAL_RATIO, args.seed)
        test_records = []
        split_metadata = {
            "split_type": "legacy_internal_lut_holdout",
            "seed": args.seed,
            "validation_ratio": VAL_RATIO,
            "records": {"train": len(train_records), "validation": len(validation_records), "test": 0},
        }
        basis_path = args.basis_path or BASIS_PATH
        model_path = args.model_path or MODEL_PATH
        report_path = args.report_path or REPORT_PATH

    torch.manual_seed(args.seed)
    np.random.seed(args.seed)
    if args.fit_basis:
        fit_basis(train_records, args.num_bases, basis_path, split_metadata)
    if args.train:
        train(
            train_records,
            validation_records,
            args.epochs,
            args.batch_size,
            args.num_bases,
            basis_path,
            model_path,
            report_path,
            split_metadata | {"test_records_reserved": len(test_records)},
        )


if __name__ == "__main__":
    main()
