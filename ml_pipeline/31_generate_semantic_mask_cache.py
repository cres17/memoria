"""Generate a deterministic semantic-mask cache for conditional-LUT references.

The selected MediaPipe Selfie Multiclass model outputs six logits per 256x256
pixel.  This cache applies the pinned [-1, 1] normalization and a stable
softmax, then stores 64x64 float16 probability masks keyed by both the source
image checksum and the model checksum.  It never changes a split manifest.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from ai_edge_litert.interpreter import Interpreter
from PIL import Image


PIPELINE_DIR = Path(__file__).resolve().parent
DATASET_DIR = PIPELINE_DIR / "data" / "dataset"
SPLIT_PATH = PIPELINE_DIR / "reports" / "splits" / "conditional_lut_family_holdout.jsonl"
MODEL_PATH = PIPELINE_DIR / "models" / "selfie_multiclass.tflite"
MODEL_SHA256 = "c6748b1253a99067ef71f7e26ca71096cd449baefa8f101900ea23016507e0e0"
DEFAULT_CACHE_DIR = PIPELINE_DIR / "reports" / "semantic_masks" / "selfie_multiclass_256_softmax_64"
CLASSES = ("background", "hair", "bodySkin", "faceSkin", "clothes", "other")
MODEL_SIZE = 256
CACHE_SIZE = 64


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def read_records(path: Path) -> list[dict]:
    records = [json.loads(line) for line in path.read_text().splitlines() if line]
    if len({record["id"] for record in records}) != len(records):
        raise ValueError("semantic cache requires a unique image ID per split manifest row")
    return records


def stable_softmax(logits: np.ndarray) -> np.ndarray:
    shifted = logits - logits.max(axis=-1, keepdims=True)
    exponentials = np.exp(shifted)
    return exponentials / exponentials.sum(axis=-1, keepdims=True)


def model_input(path: Path) -> np.ndarray:
    with Image.open(path) as image:
        rgb = image.convert("RGB").resize((MODEL_SIZE, MODEL_SIZE), Image.Resampling.BILINEAR)
        pixels = np.asarray(rgb, dtype=np.float32)
    return (pixels / 127.5 - 1.0)[None]


def cache_masks(probabilities: np.ndarray) -> np.ndarray:
    masks = np.empty((len(CLASSES), CACHE_SIZE, CACHE_SIZE), dtype=np.float32)
    for index in range(len(CLASSES)):
        resized = Image.fromarray(probabilities[..., index], mode="F").resize(
            (CACHE_SIZE, CACHE_SIZE), Image.Resampling.BILINEAR
        )
        masks[index] = np.asarray(resized, dtype=np.float32)
    return masks


def valid_cache(path: Path, image_hash: str) -> bool:
    if not path.exists():
        return False
    with np.load(path) as archive:
        return (
            str(archive["source_sha256"])
            == image_hash
            and str(archive["model_sha256"])
            == MODEL_SHA256
            and archive["masks"].shape == (len(CLASSES), CACHE_SIZE, CACHE_SIZE)
        )


def main() -> None:
    parser = argparse.ArgumentParser(description="Build checksum-pinned semantic mask cache.")
    parser.add_argument("--split-path", type=Path, default=SPLIT_PATH)
    parser.add_argument("--model-path", type=Path, default=MODEL_PATH)
    parser.add_argument("--cache-dir", type=Path, default=DEFAULT_CACHE_DIR)
    parser.add_argument("--max-samples", type=int, help="limit an explicit smoke run; omitting processes the full split")
    args = parser.parse_args()
    if args.max_samples is not None and args.max_samples <= 0:
        parser.error("--max-samples must be positive")
    if sha256(args.model_path) != MODEL_SHA256:
        raise ValueError("selected semantic model SHA-256 does not match the pinned contract")

    records = read_records(args.split_path)
    if args.max_samples is not None:
        records = records[:args.max_samples]
    args.cache_dir.mkdir(parents=True, exist_ok=True)
    interpreter = Interpreter(model_path=str(args.model_path))
    interpreter.allocate_tensors()
    input_detail = interpreter.get_input_details()[0]
    output_detail = interpreter.get_output_details()[0]
    if tuple(input_detail["shape"]) != (1, MODEL_SIZE, MODEL_SIZE, 3):
        raise ValueError(f"unexpected model input shape: {input_detail['shape']}")
    if tuple(output_detail["shape"]) != (1, MODEL_SIZE, MODEL_SIZE, len(CLASSES)):
        raise ValueError(f"unexpected model output shape: {output_detail['shape']}")

    written = 0
    skipped = 0
    coverage = np.zeros(len(CLASSES), dtype=np.float64)
    for record in records:
        image_path = DATASET_DIR / "graded" / f"{record['id']}.jpg"
        image_hash = sha256(image_path)
        cache_path = args.cache_dir / f"{record['id']}.npz"
        if valid_cache(cache_path, image_hash):
            with np.load(cache_path) as archive:
                coverage += archive["masks"].astype(np.float32).mean(axis=(1, 2))
            skipped += 1
            continue
        interpreter.set_tensor(input_detail["index"], model_input(image_path))
        interpreter.invoke()
        probabilities = stable_softmax(interpreter.get_tensor(output_detail["index"])[0])
        if not np.isfinite(probabilities).all() or not np.allclose(probabilities.sum(axis=-1), 1.0, atol=1e-5):
            raise ValueError(f"non-probability semantic output for {record['id']}")
        masks = cache_masks(probabilities)
        coverage += masks.mean(axis=(1, 2))
        np.savez_compressed(
            cache_path,
            masks=masks.astype(np.float16),
            source_sha256=image_hash,
            model_sha256=MODEL_SHA256,
            class_names=np.asarray(CLASSES),
            input_normalization="rgb/127.5-1.0",
            postprocess="softmax_logits_then_bilinear_64x64",
        )
        written += 1

    summary = {
        "schema_version": 1,
        "experiment_id": "SEMANTIC-MASK-CACHE-001",
        "split_path": str(args.split_path),
        "model_path": str(args.model_path),
        "model_sha256": MODEL_SHA256,
        "classes": CLASSES,
        "input_normalization": "rgb/127.5-1.0",
        "postprocess": "softmax_logits_then_bilinear_64x64",
        "cache_shape": [len(CLASSES), CACHE_SIZE, CACHE_SIZE],
        "records_requested": len(records),
        "written": written,
        "skipped_valid": skipped,
        "mean_class_coverage": {
            name: float(value / len(records)) for name, value in zip(CLASSES, coverage)
        },
        "completion": "full" if args.max_samples is None else "explicit_smoke_subset",
    }
    (args.cache_dir / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    print(f"semantic mask cache complete -> {args.cache_dir}")


if __name__ == "__main__":
    main()
