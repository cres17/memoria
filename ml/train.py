"""
Neural Color Transfer Training Pipeline
Architecture: MobileNetV3-Small encoder + FC LUT decoder
Target: 65^3 LUT prediction from a single style image
Hardware: GTX 1650 Max-Q (~4GB VRAM), fp16, batch=4
"""
import os
import math
import struct
import random
import argparse
import numpy as np
from pathlib import Path

import torch
import torch.nn as nn
import torch.nn.functional as F
from torch.utils.data import Dataset, DataLoader
from torchvision import transforms, models
from PIL import Image

# ── Constants ──────────────────────────────────────────────────────────────────
DIM = 65          # output LUT resolution (65^3, ~1.6MB binary)
DIM_PRED = 17     # predicted resolution — upsampled to DIM (17^3=4913 voxels, ~29MB FC weight)
LUT_SIZE = DIM * DIM * DIM        # 274625
LUT_SIZE_PRED = DIM_PRED ** 3     # 4913
DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")

# ── Color space utils ──────────────────────────────────────────────────────────

def rgb_to_lab_tensor(rgb):
    """rgb: (B,3,H,W) float [0,1] → (B,3,H,W) Lab"""
    # sRGB linearize
    mask = rgb > 0.04045
    linear = torch.where(mask, ((rgb + 0.055) / 1.055) ** 2.4, rgb / 12.92)

    r, g, b = linear[:, 0], linear[:, 1], linear[:, 2]
    x = 0.4124564 * r + 0.3575761 * g + 0.1804375 * b
    y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
    z = 0.0193339 * r + 0.1191920 * g + 0.9503041 * b

    XN, YN, ZN = 0.95047, 1.00000, 1.08883
    x, y, z = x / XN, y / YN, z / ZN

    def f(t):
        delta = 6.0 / 29.0
        return torch.where(t > delta ** 3, t ** (1.0 / 3.0), t / (3 * delta ** 2) + 4.0 / 29.0)

    fx, fy, fz = f(x), f(y), f(z)
    L = 116 * fy - 16
    a = 500 * (fx - fy)
    bv = 200 * (fy - fz)
    return torch.stack([L, a, bv], dim=1)


# ── LUT utilities ──────────────────────────────────────────────────────────────

def build_identity_lut(dim=DIM):
    """Returns (dim^3, 3) float32 identity LUT."""
    idx = torch.linspace(0, 1, dim)
    r, g, b = torch.meshgrid(idx, idx, idx, indexing='ij')
    lut = torch.stack([r, g, b], dim=-1).reshape(-1, 3)
    return lut


def apply_lut_to_image(img, lut):
    """
    img: (B,3,H,W) float [0,1]
    lut: (B, DIM^3, 3) float [0,1]
    returns: (B,3,H,W)
    """
    B, _, H, W = img.shape
    dim = DIM

    # Scale to LUT index space
    scaled = img * (dim - 1)  # (B,3,H,W)
    r = scaled[:, 0]
    g = scaled[:, 1]
    b = scaled[:, 2]

    r0 = r.long().clamp(0, dim - 2)
    g0 = g.long().clamp(0, dim - 2)
    b0 = b.long().clamp(0, dim - 2)
    r1 = (r0 + 1).clamp(0, dim - 1)
    g1 = (g0 + 1).clamp(0, dim - 1)
    b1 = (b0 + 1).clamp(0, dim - 1)

    rf = (r - r0).unsqueeze(1)
    gf = (g - g0).unsqueeze(1)
    bf = (b - b0).unsqueeze(1)

    def idx3(ri, gi, bi):
        return ri * dim * dim + gi * dim + bi  # (B,H,W)

    lut_t = lut.permute(0, 2, 1)  # (B,3,DIM^3)

    def lookup(ri, gi, bi):
        flat = idx3(ri, gi, bi).reshape(B, -1)  # (B,H*W)
        flat = flat.unsqueeze(1).expand(-1, 3, -1)  # (B,3,H*W)
        return lut_t.gather(2, flat).reshape(B, 3, H, W)

    c000 = lookup(r0, g0, b0)
    c100 = lookup(r1, g0, b0)
    c010 = lookup(r0, g1, b0)
    c110 = lookup(r1, g1, b0)
    c001 = lookup(r0, g0, b1)
    c101 = lookup(r1, g0, b1)
    c011 = lookup(r0, g1, b1)
    c111 = lookup(r1, g1, b1)

    c00 = c000 + (c100 - c000) * rf
    c10 = c010 + (c110 - c010) * rf
    c01 = c001 + (c101 - c001) * rf
    c11 = c011 + (c111 - c011) * rf
    c0 = c00 + (c10 - c00) * gf
    c1 = c01 + (c11 - c01) * gf
    return (c0 + (c1 - c0) * bf).clamp(0, 1)


# ── Model ──────────────────────────────────────────────────────────────────────

class ColorTransferModel(nn.Module):
    """
    Predicts a 17^3 LUT from a style image, then trilinearly upsamples to 65^3.
    FC weight: 512 × 17^3 × 3 × 4B = ~29MB  (vs 1.6GB for direct 65^3)
    Total model: ~32MB fp32 / ~16MB fp16
    """
    def __init__(self):
        super().__init__()
        backbone = models.mobilenet_v3_small(weights=models.MobileNet_V3_Small_Weights.DEFAULT)
        self.encoder = nn.Sequential(backbone.features, backbone.avgpool)
        enc_dim = 576

        self.head = nn.Sequential(
            nn.Flatten(),
            nn.Linear(enc_dim, 256),
            nn.Hardswish(),
            nn.Dropout(0.2),
            nn.Linear(256, 512),
            nn.Hardswish(),
        )
        # Predict 17^3 LUT (small), upsample to 65^3
        self.lut_decoder = nn.Linear(512, LUT_SIZE_PRED * 3)
        nn.init.zeros_(self.lut_decoder.bias)
        nn.init.normal_(self.lut_decoder.weight, std=0.01)

    def forward(self, x):
        """x: (B,3,256,256) → (B, LUT_SIZE=65^3, 3)"""
        feat = self.encoder(x)
        h = self.head(feat)
        raw = self.lut_decoder(h)  # (B, 17^3 * 3)
        # Reshape to 5D grid (B, 3, D, D, D) for trilinear upsample
        lut_small = torch.sigmoid(raw).reshape(-1, 3, DIM_PRED, DIM_PRED, DIM_PRED)
        # Upsample to 65^3
        lut_full = F.interpolate(lut_small, size=(DIM, DIM, DIM), mode='trilinear', align_corners=True)
        # (B, 3, 65, 65, 65) → (B, LUT_SIZE, 3)
        return lut_full.reshape(-1, 3, LUT_SIZE).permute(0, 2, 1)


# ── Loss ───────────────────────────────────────────────────────────────────────

def delta_e_loss(pred_rgb, target_rgb):
    """Mean CIE76 ΔE between two (B,3,H,W) RGB images."""
    pred_lab = rgb_to_lab_tensor(pred_rgb)
    target_lab = rgb_to_lab_tensor(target_rgb)
    diff = pred_lab - target_lab
    return diff.pow(2).sum(dim=1).sqrt().mean()


def histogram_loss(pred, target, bins=64):
    """Soft histogram matching loss over each channel."""
    loss = 0.0
    for c in range(3):
        p = pred[:, c].reshape(pred.shape[0], -1)
        t = target[:, c].reshape(target.shape[0], -1)
        edges = torch.linspace(0, 1, bins + 1, device=pred.device)
        centers = (edges[:-1] + edges[1:]) / 2

        def soft_hist(vals):
            dists = (vals.unsqueeze(-1) - centers.unsqueeze(0).unsqueeze(0)).pow(2)
            sigma = 1.0 / bins
            w = torch.exp(-dists / (2 * sigma ** 2))
            w = w / (w.sum(-1, keepdim=True) + 1e-8)
            return w.sum(1)  # (B, bins)

        ph = soft_hist(p)
        th = soft_hist(t)
        loss += F.l1_loss(ph, th)
    return loss / 3.0


def smoothness_loss(lut):
    """TV-like smoothness on the LUT (B, DIM^3, 3)."""
    B = lut.shape[0]
    l = lut.reshape(B, DIM, DIM, DIM, 3)
    dr = (l[:, 1:] - l[:, :-1]).pow(2).mean()
    dg = (l[:, :, 1:] - l[:, :, :-1]).pow(2).mean()
    db = (l[:, :, :, 1:] - l[:, :, :, :-1]).pow(2).mean()
    return dr + dg + db


def total_loss(pred_lut, target_lut, neutral_img, target_img, lambdas=(1.0, 0.5, 0.1)):
    """
    pred_lut, target_lut: (B, LUT_SIZE, 3)
    neutral_img, target_img: (B,3,H,W)
    """
    # Apply predicted LUT to neutral image
    pred_applied = apply_lut_to_image(neutral_img, pred_lut)

    # ΔE loss: predicted output vs target image
    l_de = delta_e_loss(pred_applied, target_img)

    # Histogram loss
    l_hist = histogram_loss(pred_applied, target_img)

    # Smoothness on predicted LUT
    l_smooth = smoothness_loss(pred_lut)

    return lambdas[0] * l_de + lambdas[1] * l_hist + lambdas[2] * l_smooth, {
        'delta_e': l_de.item(),
        'histogram': l_hist.item(),
        'smoothness': l_smooth.item(),
    }


# ── Dataset ────────────────────────────────────────────────────────────────────

class ColorTransferDataset(Dataset):
    """
    Expects a directory with paired images:
      data_dir/
        neutral/  *.jpg  (neutral/base images)
        styled/   *.jpg  (same image with LUT applied — style target)
        luts/     *.bin  (65^3 float16 binary LUTs, corresponding to styled/)

    File names must match: neutral/foo.jpg ↔ styled/foo.jpg ↔ luts/foo.bin
    """

    def __init__(self, data_dir, img_size=256, augment=True):
        self.data_dir = Path(data_dir)
        self.img_size = img_size
        self.augment = augment

        self.neutral_dir = self.data_dir / "neutral"
        self.styled_dir = self.data_dir / "styled"
        self.lut_dir = self.data_dir / "luts"

        stems = [p.stem for p in self.styled_dir.glob("*.jpg")]
        # Only keep pairs that have all three files
        self.items = [
            s for s in stems
            if (self.neutral_dir / f"{s}.jpg").exists()
            and (self.lut_dir / f"{s}.bin").exists()
        ]
        if not self.items:
            # Also try .png
            stems = [p.stem for p in self.styled_dir.glob("*.png")]
            self.items = [
                s for s in stems
                if (self.neutral_dir / f"{s}.png").exists()
                and (self.lut_dir / f"{s}.bin").exists()
            ]

        print(f"Dataset: {len(self.items)} pairs in {data_dir}")

        self.to_tensor = transforms.Compose([
            transforms.Resize((img_size, img_size)),
            transforms.ToTensor(),  # [0,1]
        ])
        self.aug = transforms.Compose([
            transforms.RandomHorizontalFlip(),
            transforms.ColorJitter(brightness=0.05, contrast=0.05, saturation=0.05),
        ]) if augment else None

    def __len__(self):
        return len(self.items)

    def _load_img(self, path):
        return Image.open(path).convert("RGB")

    def _load_lut(self, path):
        """Load 65^3 × 3 float16 binary → float32 tensor (LUT_SIZE, 3)."""
        raw = Path(path).read_bytes()
        arr = np.frombuffer(raw, dtype=np.float16).astype(np.float32)
        return torch.from_numpy(arr).reshape(LUT_SIZE, 3)

    def __getitem__(self, idx):
        stem = self.items[idx]
        ext = ".jpg" if (self.neutral_dir / f"{stem}.jpg").exists() else ".png"

        neutral = self._load_img(self.neutral_dir / f"{stem}{ext}")
        styled = self._load_img(self.styled_dir / f"{stem}{ext}")
        lut = self._load_lut(self.lut_dir / f"{stem}.bin")

        if self.aug:
            seed = random.randint(0, 2 ** 32)
            random.seed(seed)
            torch.manual_seed(seed)
            neutral = self.aug(neutral)
            random.seed(seed)
            torch.manual_seed(seed)
            styled = self.aug(styled)

        neutral = self.to_tensor(neutral)
        styled = self.to_tensor(styled)

        # Style image for encoder input: styled (gives the "look" to transfer)
        return {
            "style": styled,      # input to encoder
            "neutral": neutral,   # neutral image to apply LUT to
            "target": styled,     # target output (same as style in paired training)
            "lut": lut,           # ground truth LUT
        }


# ── Training loop ──────────────────────────────────────────────────────────────

def train(args):
    print(f"Device: {DEVICE}")
    print(f"Data: {args.data_dir}")

    dataset = ColorTransferDataset(args.data_dir, img_size=256, augment=True)
    val_size = max(1, int(len(dataset) * 0.05))
    train_size = len(dataset) - val_size
    train_ds, val_ds = torch.utils.data.random_split(dataset, [train_size, val_size])

    train_loader = DataLoader(train_ds, batch_size=args.batch_size, shuffle=True,
                              num_workers=4, pin_memory=True)
    val_loader = DataLoader(val_ds, batch_size=args.batch_size, shuffle=False,
                            num_workers=2, pin_memory=True)

    model = ColorTransferModel().to(DEVICE)
    optimizer = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=1e-4)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=args.epochs)
    scaler = torch.amp.GradScaler('cuda', enabled=args.fp16)

    best_val_de = float('inf')
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    for epoch in range(1, args.epochs + 1):
        model.train()
        train_loss = 0.0
        train_de = 0.0

        for step, batch in enumerate(train_loader):
            style = batch["style"].to(DEVICE)
            neutral = batch["neutral"].to(DEVICE)
            target = batch["target"].to(DEVICE)

            optimizer.zero_grad()
            with torch.amp.autocast('cuda', enabled=args.fp16):
                pred_lut = model(style)
                loss, comps = total_loss(pred_lut, None, neutral, target)

            scaler.scale(loss).backward()
            scaler.unscale_(optimizer)
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            scaler.step(optimizer)
            scaler.update()

            train_loss += loss.item()
            train_de += comps['delta_e']

            if step % 100 == 0:
                print(f"  Epoch {epoch} step {step}/{len(train_loader)}  "
                      f"loss={loss.item():.4f}  dE={comps['delta_e']:.4f}  "
                      f"hist={comps['histogram']:.4f}  smooth={comps['smoothness']:.6f}")

        scheduler.step()

        # Validation
        model.eval()
        val_de = 0.0
        with torch.no_grad():
            for batch in val_loader:
                style = batch["style"].to(DEVICE)
                neutral = batch["neutral"].to(DEVICE)
                target = batch["target"].to(DEVICE)
                with torch.amp.autocast('cuda', enabled=args.fp16):
                    pred_lut = model(style)
                    _, comps = total_loss(pred_lut, None, neutral, target)
                val_de += comps['delta_e']

        val_de /= len(val_loader)
        train_de /= len(train_loader)

        print(f"Epoch {epoch}/{args.epochs}  train_dE={train_de:.4f}  val_dE={val_de:.4f}  "
              f"lr={scheduler.get_last_lr()[0]:.6f}")

        # Save checkpoint
        ckpt = {
            'epoch': epoch,
            'model_state': model.state_dict(),
            'optimizer_state': optimizer.state_dict(),
            'val_de': val_de,
        }
        torch.save(ckpt, out_dir / "last.pt")

        if val_de < best_val_de:
            best_val_de = val_de
            torch.save(ckpt, out_dir / "best.pt")
            print(f"  [best] saved (val_dE={val_de:.4f})")

    print(f"\nTraining done. Best val dE: {best_val_de:.4f}")
    print(f"Checkpoints: {out_dir}/best.pt")


# ── Export to TFLite ───────────────────────────────────────────────────────────

def export_tflite(checkpoint_path, out_path):
    """Export best.pt → color_transfer.tflite (fp16 quantized)."""
    try:
        import tensorflow as tf
    except ImportError:
        print("TensorFlow not found. Install: pip install tensorflow")
        return

    model = ColorTransferModel()
    ckpt = torch.load(checkpoint_path, map_location='cpu')
    model.load_state_dict(ckpt['model_state'])
    model.eval()

    # Export via ONNX → TFLite
    import tempfile
    dummy = torch.zeros(1, 3, 256, 256)

    with tempfile.TemporaryDirectory() as tmp:
        onnx_path = os.path.join(tmp, "model.onnx")
        torch.onnx.export(
            model, dummy, onnx_path,
            input_names=["style_image"],
            output_names=["lut"],
            opset_version=12,
            dynamic_axes={"style_image": {0: "batch"}, "lut": {0: "batch"}},
        )
        print(f"ONNX exported to {onnx_path}")
        print("Convert ONNX → TFLite using onnx-tf or ai-edge-torch.")
        print("See ml/convert_tflite.sh for the conversion script.")


# ── Data generation helper ─────────────────────────────────────────────────────

def generate_synthetic_pairs(neutral_dir, lut_dir, out_dir, count=None):
    """
    Generate (neutral, styled, lut) triples from neutral images + existing LUTs.
    neutral_dir: directory of neutral .jpg images
    lut_dir: directory of 65^3 float16 .bin LUT files
    out_dir: output directory (creates neutral/, styled/, luts/ subdirs)
    """
    neutral_dir = Path(neutral_dir)
    lut_dir = Path(lut_dir)
    out_dir = Path(out_dir)

    neutrals = list(neutral_dir.glob("*.jpg")) + list(neutral_dir.glob("*.png"))
    luts = list(lut_dir.glob("*.bin"))

    if not neutrals:
        print(f"No neutral images found in {neutral_dir}")
        return
    if not luts:
        print(f"No LUT .bin files found in {lut_dir}")
        return

    (out_dir / "neutral").mkdir(parents=True, exist_ok=True)
    (out_dir / "styled").mkdir(parents=True, exist_ok=True)
    (out_dir / "luts").mkdir(parents=True, exist_ok=True)

    pairs = []
    for n in neutrals:
        for l in luts:
            pairs.append((n, l))

    if count:
        random.shuffle(pairs)
        pairs = pairs[:count]

    print(f"Generating {len(pairs)} pairs…")

    for i, (n_path, l_path) in enumerate(pairs):
        if i % 500 == 0:
            print(f"  {i}/{len(pairs)}")

        # Load LUT
        raw = l_path.read_bytes()
        lut_np = np.frombuffer(raw, dtype=np.float16).astype(np.float32)
        if lut_np.size != LUT_SIZE * 3:
            continue
        lut_np = lut_np.reshape(DIM, DIM, DIM, 3)

        # Load + resize neutral image
        img = Image.open(n_path).convert("RGB").resize((256, 256), Image.LANCZOS)
        img_np = np.array(img, dtype=np.float32) / 255.0

        # Apply LUT (trilinear)
        styled_np = _apply_lut_np(img_np, lut_np)
        styled_img = Image.fromarray((styled_np * 255).clip(0, 255).astype(np.uint8))

        stem = f"{n_path.stem}__{l_path.stem}"

        # Copy/save files
        img.save(out_dir / "neutral" / f"{stem}.jpg", quality=95)
        styled_img.save(out_dir / "styled" / f"{stem}.jpg", quality=95)

        # Copy LUT binary
        import shutil
        shutil.copy(l_path, out_dir / "luts" / f"{stem}.bin")

    print(f"Done. {len(pairs)} pairs written to {out_dir}")


def _apply_lut_np(img, lut):
    """img: (H,W,3) float32, lut: (DIM,DIM,DIM,3) → (H,W,3)"""
    ri = img[..., 0] * (DIM - 1)
    gi = img[..., 1] * (DIM - 1)
    bi = img[..., 2] * (DIM - 1)

    r0 = np.floor(ri).astype(int).clip(0, DIM - 2)
    g0 = np.floor(gi).astype(int).clip(0, DIM - 2)
    b0 = np.floor(bi).astype(int).clip(0, DIM - 2)
    r1 = (r0 + 1).clip(0, DIM - 1)
    g1 = (g0 + 1).clip(0, DIM - 1)
    b1 = (b0 + 1).clip(0, DIM - 1)

    rf = (ri - r0)[..., np.newaxis]
    gf = (gi - g0)[..., np.newaxis]
    bf = (bi - b0)[..., np.newaxis]

    c00 = lut[r0, g0, b0] + (lut[r1, g0, b0] - lut[r0, g0, b0]) * rf
    c10 = lut[r0, g1, b0] + (lut[r1, g1, b0] - lut[r0, g1, b0]) * rf
    c01 = lut[r0, g0, b1] + (lut[r1, g0, b1] - lut[r0, g0, b1]) * rf
    c11 = lut[r0, g1, b1] + (lut[r1, g1, b1] - lut[r0, g1, b1]) * rf
    c0 = c00 + (c10 - c00) * gf
    c1 = c01 + (c11 - c01) * gf
    return (c0 + (c1 - c0) * bf).clip(0, 1)


# ── Inference / LUT export ─────────────────────────────────────────────────────

def predict_lut(model_path, style_image_path, out_lut_path):
    """Run inference on a style image, save 65^3 float16 .bin LUT."""
    model = ColorTransferModel().to(DEVICE)
    ckpt = torch.load(model_path, map_location=DEVICE)
    model.load_state_dict(ckpt['model_state'])
    model.eval()

    tf = transforms.Compose([
        transforms.Resize((256, 256)),
        transforms.ToTensor(),
    ])
    img = Image.open(style_image_path).convert("RGB")
    x = tf(img).unsqueeze(0).to(DEVICE)

    with torch.no_grad():
        lut = model(x)  # (1, LUT_SIZE, 3)

    lut_np = lut[0].cpu().numpy().astype(np.float16)  # (LUT_SIZE, 3)
    lut_np.tofile(out_lut_path)
    print(f"LUT saved: {out_lut_path}  ({lut_np.nbytes / 1024:.1f} KB)")
    return lut_np


# ── CLI ────────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Memoria Neural Color Transfer Trainer")
    subparsers = parser.add_subparsers(dest="cmd")

    # train
    p_train = subparsers.add_parser("train")
    p_train.add_argument("--data-dir", required=True)
    p_train.add_argument("--out-dir", default="ml/checkpoints")
    p_train.add_argument("--epochs", type=int, default=30)
    p_train.add_argument("--batch-size", type=int, default=4)
    p_train.add_argument("--lr", type=float, default=1e-3)
    p_train.add_argument("--fp16", action="store_true", default=True)

    # generate synthetic data
    p_gen = subparsers.add_parser("gen-data")
    p_gen.add_argument("--neutral-dir", required=True, help="Dir of neutral images")
    p_gen.add_argument("--lut-dir", required=True, help="Dir of .bin LUT files")
    p_gen.add_argument("--out-dir", required=True, help="Output dataset dir")
    p_gen.add_argument("--count", type=int, default=None, help="Max pairs to generate")

    # predict single LUT
    p_pred = subparsers.add_parser("predict")
    p_pred.add_argument("--model", required=True, help="Path to best.pt")
    p_pred.add_argument("--style", required=True, help="Style image path")
    p_pred.add_argument("--out", required=True, help="Output .bin path")

    # export TFLite
    p_exp = subparsers.add_parser("export-tflite")
    p_exp.add_argument("--model", required=True)
    p_exp.add_argument("--out", default="ml/color_transfer.tflite")

    args = parser.parse_args()

    if args.cmd == "train":
        train(args)
    elif args.cmd == "gen-data":
        generate_synthetic_pairs(args.neutral_dir, args.lut_dir, args.out_dir, args.count)
    elif args.cmd == "predict":
        predict_lut(args.model, args.style, args.out)
    elif args.cmd == "export-tflite":
        export_tflite(args.model, args.out)
    else:
        parser.print_help()
