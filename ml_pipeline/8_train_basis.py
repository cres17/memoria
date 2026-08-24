"""P4 — lightweight basis-residual LUT experiment.

This script deliberately trains from the project's own LUT/image pairs. It
does not download or embed third-party model weights: ``pretrained=False`` is
the default. The network predicts K bounded coefficients, not a full 3D LUT.

Usage:
  python 8_train_basis.py --fit-basis
  python 8_train_basis.py --train

Artifacts:
  checkpoints/basis_lut.npz       mean LUT + residual PCA bases (17³)
  checkpoints/basis_color.pt      weight-predictor checkpoint
"""

import argparse
import math
from pathlib import Path

import numpy as np
from PIL import Image
import timm
import torch
import torch.nn as nn
from torch.utils.data import DataLoader, Dataset

DATASET_DIR = Path("data/dataset")
LUT_DIM = 65
BASIS_DIM = 17
NUM_BASES = 8
COEFFICIENT_BOUND = 2.0
# Keep targets clear of tanh's asymptotes while retaining the Dart ±2 contract.
COEFFICIENT_TARGET_MARGIN = 0.95
IMAGE_SIZE = 256
BATCH_SIZE = 32
EPOCHS = 40
LEARNING_RATE = 2e-4
EARLY_STOPPING_PATIENCE = 20
CHECKPOINT_DIR = Path("checkpoints")
BASIS_PATH = CHECKPOINT_DIR / "basis_lut.npz"
MODEL_PATH = CHECKPOINT_DIR / "basis_color.pt"
IMAGENET_MEAN = np.array([0.485, 0.456, 0.406], dtype=np.float32)[:, None, None]
IMAGENET_STD = np.array([0.229, 0.224, 0.225], dtype=np.float32)[:, None, None]
DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")


def lut_paths(root: Path):
    images = sorted((root / "graded").glob("*.jpg"))
    luts = sorted((root / "luts").glob("*.bin"))
    if not images or len(images) != len(luts):
        raise RuntimeError(f"expected equal graded/luts pairs, got {len(images)}/{len(luts)}")
    return images, luts


def load_small_lut(path: Path) -> np.ndarray:
    """Reads the project R-fastest float16 LUT and takes the 65→17 grid."""
    values = np.fromfile(path, dtype=np.float16).astype(np.float32)
    expected = LUT_DIM * LUT_DIM * LUT_DIM * 3
    if values.size != expected:
        raise ValueError(f"{path} has {values.size} values, expected {expected}")
    lut = values.reshape(LUT_DIM, LUT_DIM, LUT_DIM, 3)
    indices = np.linspace(0, LUT_DIM - 1, BASIS_DIM).round().astype(np.int64)
    return lut[np.ix_(indices, indices, indices)].astype(np.float32)


def fit_basis(paths, num_bases: int = NUM_BASES):
    """Fits PCA residual bases. The mean is a LUT, bases are not LUT assets."""
    samples = np.stack([load_small_lut(path).reshape(-1) for path in paths])
    mean = samples.mean(axis=0)
    residuals = samples - mean
    # Full SVD is deterministic and practical for the small local experiment.
    _, singular_values, vt = np.linalg.svd(residuals, full_matrices=False)
    actual_k = min(num_bases, vt.shape[0])
    raw_bases = vt[:actual_k]
    raw_coefficients = residuals @ raw_bases.T
    # Store scaled bases. The model still emits bounded coefficients, while
    # reconstruction happens in the original LUT coefficient space.
    coefficient_scales = np.maximum(
        np.max(np.abs(raw_coefficients), axis=0) /
        (COEFFICIENT_BOUND * COEFFICIENT_TARGET_MARGIN),
        1e-3,
    ).astype(np.float32)
    bases = raw_bases * coefficient_scales[:, None]
    CHECKPOINT_DIR.mkdir(parents=True, exist_ok=True)
    np.savez_compressed(
        BASIS_PATH,
        mean=mean.reshape(BASIS_DIM, BASIS_DIM, BASIS_DIM, 3),
        bases=bases.reshape(actual_k, BASIS_DIM, BASIS_DIM, BASIS_DIM, 3),
        basis_dim=BASIS_DIM,
        lut_axis_order="r_fastest_rgb",
        coefficient_bound=COEFFICIENT_BOUND,
        coefficient_scales=coefficient_scales,
        coefficient_space="normalized_scaled_bases",
        explained_energy=float((singular_values[:actual_k] ** 2).sum() /
                               max((singular_values ** 2).sum(), 1e-12)),
    )
    print(f"saved {actual_k} bases → {BASIS_PATH}")


def load_basis():
    if not BASIS_PATH.exists():
        raise RuntimeError("basis artifact missing; run with --fit-basis first")
    raw = np.load(BASIS_PATH)
    if int(raw["basis_dim"]) != BASIS_DIM or str(raw["lut_axis_order"]) != "r_fastest_rgb":
        raise RuntimeError("basis artifact contract does not match the app LUT contract")
    if str(raw["coefficient_space"]) != "normalized_scaled_bases":
        raise RuntimeError("basis artifact coefficient contract is not normalized")
    bases = raw["bases"].reshape(raw["bases"].shape[0], -1)
    scales = raw["coefficient_scales"].astype(np.float32)
    if scales.shape != (bases.shape[0],) or np.any(scales <= 0) or not np.all(np.isfinite(scales)):
        raise RuntimeError("basis artifact coefficient scales are invalid")
    return raw["mean"].reshape(-1), bases, scales


class BasisDataset(Dataset):
    def __init__(self, root: Path, mean: np.ndarray, bases: np.ndarray, coefficient_scales: np.ndarray):
        self.images, self.luts = lut_paths(root)
        self.mean = mean
        self.bases = bases
        self.coefficient_scales = coefficient_scales
        flat_luts = np.stack([load_small_lut(path).reshape(-1) for path in self.luts])
        # bases are raw PCA vectors multiplied by scale. Projection produces
        # raw_coefficients * scale; dividing by scale² returns model targets.
        self.coefficients = ((flat_luts - mean) @ bases.T) / (coefficient_scales ** 2)

    def __len__(self):
        return len(self.images)

    def __getitem__(self, index):
        image = Image.open(self.images[index]).convert("RGB").resize((IMAGE_SIZE, IMAGE_SIZE))
        image = np.asarray(image, dtype=np.float32).transpose(2, 0, 1) / 255.0
        image = (image - IMAGENET_MEAN) / IMAGENET_STD
        return torch.from_numpy(image), torch.from_numpy(self.coefficients[index])


class BasisWeightNet(nn.Module):
    def __init__(self, num_bases: int):
        super().__init__()
        # No third-party pretrained weights are pulled into the experiment.
        self.encoder = timm.create_model(
            "mobilenetv3_small_100", pretrained=False, num_classes=0, global_pool="avg"
        )
        with torch.no_grad():
            feature_dim = self.encoder(torch.zeros(1, 3, IMAGE_SIZE, IMAGE_SIZE)).shape[-1]
        self.head = nn.Sequential(
            nn.Linear(feature_dim, 128), nn.SiLU(), nn.Linear(128, num_bases), nn.Tanh()
        )

    def forward(self, image):
        return self.head(self.encoder(image)) * COEFFICIENT_BOUND


def train(epochs: int = EPOCHS, batch_size: int = BATCH_SIZE):
    mean, bases, coefficient_scales = load_basis()
    dataset = BasisDataset(DATASET_DIR, mean, bases, coefficient_scales)
    split = max(1, int(len(dataset) * 0.1))
    train_set, validation_set = torch.utils.data.random_split(
        dataset, [len(dataset) - split, split], generator=torch.Generator().manual_seed(20260715)
    )
    train_loader = DataLoader(train_set, batch_size=batch_size, shuffle=True, num_workers=0)
    validation_loader = DataLoader(validation_set, batch_size=batch_size, shuffle=False, num_workers=0)

    model = BasisWeightNet(bases.shape[0]).to(DEVICE)
    optimizer = torch.optim.AdamW(model.parameters(), lr=LEARNING_RATE, weight_decay=1e-4)
    basis_tensor = torch.from_numpy(bases).to(DEVICE)
    best_loss = float("inf")
    epochs_without_improvement = 0

    print(f"training {len(train_set)} pairs, validating {len(validation_set)} pairs, "
          f"batch_size={batch_size}, max_epochs={epochs}")
    for epoch in range(epochs):
        model.train()
        for image, target in train_loader:
            image, target = image.to(DEVICE), target.to(DEVICE)
            prediction = model(image)
            # Coefficient loss plus reconstructed LUT residual loss.
            coefficient_loss = nn.functional.mse_loss(prediction, target)
            reconstruction_loss = nn.functional.l1_loss(
                prediction @ basis_tensor, target @ basis_tensor
            )
            loss = coefficient_loss + 0.25 * reconstruction_loss
            optimizer.zero_grad()
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            optimizer.step()

        model.eval()
        losses = []
        with torch.no_grad():
            for image, target in validation_loader:
                prediction = model(image.to(DEVICE))
                losses.append(nn.functional.mse_loss(prediction, target.to(DEVICE)).item())
        validation_loss = float(np.mean(losses))
        print(f"epoch={epoch + 1:02d} val_coefficient_mse={validation_loss:.6f}")
        if validation_loss < best_loss:
            best_loss = validation_loss
            epochs_without_improvement = 0
            CHECKPOINT_DIR.mkdir(parents=True, exist_ok=True)
            torch.save(
                {
                    "state_dict": model.state_dict(),
                    "basis_path": str(BASIS_PATH),
                    "basis_dim": BASIS_DIM,
                    "num_bases": bases.shape[0],
                    "coefficient_bound": COEFFICIENT_BOUND,
                    "coefficient_space": "normalized_scaled_bases",
                    "pretrained_weights": False,
                    "val_coefficient_mse": validation_loss,
                },
                MODEL_PATH,
            )
        else:
            epochs_without_improvement += 1
            if epochs_without_improvement >= EARLY_STOPPING_PATIENCE:
                print(f"early stopping after {epoch + 1} epochs (best_mse={best_loss:.6f})")
                break
    print(f"saved best checkpoint → {MODEL_PATH} (mse={best_loss:.6f})")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--fit-basis", action="store_true")
    parser.add_argument("--train", action="store_true")
    parser.add_argument("--num-bases", type=int, default=NUM_BASES)
    parser.add_argument("--epochs", type=int, default=EPOCHS)
    parser.add_argument("--batch-size", type=int, default=BATCH_SIZE)
    args = parser.parse_args()
    if not args.fit_basis and not args.train:
        parser.error("choose --fit-basis and/or --train")
    if args.epochs <= 0 or args.batch_size <= 0:
        parser.error("--epochs and --batch-size must be positive")
    if args.fit_basis:
        _, paths = lut_paths(DATASET_DIR)
        fit_basis(paths, args.num_bases)
    if args.train:
        train(args.epochs, args.batch_size)
