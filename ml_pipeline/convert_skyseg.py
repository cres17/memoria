"""하늘 분할 모델(U²-Net, xiongzhu666/Sky-Segmentation-and-Post-processing)을 앱용 TFLite로 변환한다.

출처와 검증
- 가중치: https://github.com/xiongzhu666/Sky-Segmentation-and-Post-processing (저자가 MIT로 공개).
  같은 파일(SHA-256 아래)이 Hugging Face의 여러 저장소(JianyuanWang/skyseg 등)에도 올라 있다.
- 학습 데이터는 저자가 밝히지 않았다. 배포 전에 이 점을 확인해야 한다(docs/sky-model.md).

변환
- 입력 [1,3,320,320] NCHW, RGB 0~1. ImageNet 정규화는 모델 안에 포함한다.
- 출력 [1,1,320,320] 하늘 확률(0~1). 첫 번째 출력(최종 융합 결과)만 쓴다.
- 가중치는 float16으로 줄이고 flutter_litert가 읽을 수 있게 inline_buffers 처리한다.

사용: python ml_pipeline/convert_skyseg.py --out build/sky/skyseg_fp16.tflite [--onnx 경로] [--photos a.jpg b.jpg]
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import urllib.request
from pathlib import Path

import numpy as np
import torch

sys.path.insert(0, str(Path(__file__).resolve().parent))

from tflite_export import convert_fp16, run_tflite  # noqa: E402

ONNX_URL = "https://huggingface.co/JianyuanWang/skyseg/resolve/main/skyseg.onnx"
ONNX_SHA256 = "ab9c34c64c3d821220a2886a4a06da4642ffa14d5b30e8d5339056a089aa1d39"
SIZE = 320
MEAN = (0.485, 0.456, 0.406)
STD = (0.229, 0.224, 0.225)


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def fetch_onnx(path: Path) -> Path:
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        urllib.request.urlretrieve(ONNX_URL, path)
    digest = sha256_of(path)
    if digest != ONNX_SHA256:
        raise SystemExit(f"ONNX SHA-256 mismatch: {digest} != {ONNX_SHA256}")
    return path


def fold_constants(src: Path, dst: Path) -> Path:
    """입력 크기가 고정이므로 Shape/Slice 계산을 상수로 접는다.

    onnx2torch의 Slice 변환은 텐서 값을 numpy로 읽어 추적(trace)할 수 없다. onnxruntime의 기본 최적화는
    상수 접기만 하므로 연산 의미는 그대로이고, 접은 뒤에는 Conv/Relu/Concat/Resize/MaxPool/Add/Sigmoid만 남는다.
    """
    import onnxruntime as ort

    options = ort.SessionOptions()
    options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_BASIC
    options.optimized_model_filepath = str(dst)
    ort.InferenceSession(str(src), options, providers=["CPUExecutionProvider"])
    return dst


class StaticResize(torch.nn.Module):
    """크기가 고정된 양선형 보간. onnx2torch의 Resize는 크기를 텐서 값으로 읽어 추적이 안 된다."""

    def __init__(self, size: tuple[int, int]):
        super().__init__()
        self.size = size

    def forward(self, x):
        # ONNX pytorch_half_pixel + linear == align_corners=False
        return torch.nn.functional.interpolate(x, size=self.size, mode="bilinear", align_corners=False)


def freeze_resizes(graph_module: torch.nn.Module, onnx_model) -> int:
    """접힌 ONNX의 Resize 노드 크기를 읽어 추적 가능한 StaticResize로 바꾼다."""
    from onnx import numpy_helper
    from onnx2torch.node_converters.resize import OnnxResize

    init = {i.name: numpy_helper.to_array(i) for i in onnx_model.graph.initializer}
    ordered_sizes = []
    for node in onnx_model.graph.node:
        if node.op_type != "Resize":
            continue
        modes = {a.name: onnx_helper_value(a) for a in node.attribute}
        if modes.get("mode") != b"linear" or modes.get("coordinate_transformation_mode") != b"pytorch_half_pixel":
            raise SystemExit(f"unsupported Resize attributes: {modes}")
        target = init[node.input[3]]
        ordered_sizes.append((int(target[2]), int(target[3])))
    # onnx2torch는 노드 순서를 그대로 유지한다. 이름이 달라 순서로 짝을 맞추고, 아래 수치 비교로 다시 확인한다.
    fx_resizes = [
        n
        for n in graph_module.graph.nodes
        if n.op == "call_module" and isinstance(graph_module.get_submodule(n.target), OnnxResize)
    ]
    if len(fx_resizes) != len(ordered_sizes):
        raise SystemExit(f"Resize count mismatch: fx {len(fx_resizes)} vs onnx {len(ordered_sizes)}")
    replaced = 0
    for fx_node, size in zip(fx_resizes, ordered_sizes):
        graph_module.add_submodule(fx_node.target, StaticResize(size))
        fx_node.args = (fx_node.args[0],)
        replaced += 1
    graph_module.graph.lint()
    graph_module.recompile()
    return replaced


def onnx_helper_value(attribute):
    import onnx

    return onnx.helper.get_attribute_value(attribute)


class SkyNet(torch.nn.Module):
    """RGB 0~1 입력을 받아 하늘 확률 한 장을 돌려준다."""

    def __init__(self, inner: torch.nn.Module):
        super().__init__()
        self.inner = inner
        self.register_buffer("mean", torch.tensor(MEAN).view(1, 3, 1, 1))
        self.register_buffer("std", torch.tensor(STD).view(1, 3, 1, 1))

    def forward(self, x):
        out = self.inner((x - self.mean) / self.std)
        first = out[0] if isinstance(out, (tuple, list)) else out
        return first


def load_photo(path: Path) -> np.ndarray:
    from PIL import Image, ImageOps

    im = ImageOps.exif_transpose(Image.open(path)).convert("RGB").resize((SIZE, SIZE), Image.BILINEAR)
    return (np.asarray(im, dtype=np.float32) / 255.0).transpose(2, 0, 1)[None]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--onnx", type=Path, default=Path("build/sky/skyseg.onnx"))
    ap.add_argument("--photos", type=Path, nargs="*", default=[])
    args = ap.parse_args()

    import onnx
    import onnxruntime as ort
    from onnx2torch import convert as onnx_to_torch

    onnx_path = fetch_onnx(args.onnx)
    folded = fold_constants(onnx_path, onnx_path.with_name("skyseg_folded.onnx"))
    folded_model = onnx.load(str(folded))
    inner = onnx_to_torch(folded_model)
    print("resize nodes frozen:", freeze_resizes(inner, folded_model))
    module = SkyNet(inner).eval()

    sample = torch.rand(1, 3, SIZE, SIZE)
    with torch.no_grad():
        torch_out = module(sample).numpy()
    session = ort.InferenceSession(str(onnx_path))
    ort_in = ((sample.numpy() - np.array(MEAN, np.float32).reshape(1, 3, 1, 1)) / np.array(STD, np.float32).reshape(1, 3, 1, 1)).astype(np.float32)
    ort_out = session.run(None, {session.get_inputs()[0].name: ort_in})[0]
    print(f"torch vs onnxruntime max abs diff: {np.abs(torch_out - ort_out).max():.2e}")

    convert_fp16(module, sample, args.out)
    size = args.out.stat().st_size
    print(f"wrote {args.out} ({size} bytes)")

    report = {"onnx_sha256": ONNX_SHA256, "tflite_bytes": size, "tflite_sha256": sha256_of(args.out), "photos": {}}
    for photo in args.photos:
        x = load_photo(photo)
        raw = x.copy()
        norm = ((raw - np.array(MEAN, np.float32).reshape(1, 3, 1, 1)) / np.array(STD, np.float32).reshape(1, 3, 1, 1)).astype(np.float32)
        ref = session.run(None, {session.get_inputs()[0].name: norm})[0][0, 0]
        got, in_d, out_d = run_tflite(args.out, raw)
        got = got.reshape(ref.shape)
        ref_mask, got_mask = ref >= 0.5, got >= 0.5
        union = (ref_mask | got_mask).sum()
        iou = float((ref_mask & got_mask).sum() / union) if union else 1.0
        report["photos"][photo.name] = {
            "max_abs_diff": float(np.abs(ref - got).max()),
            "mean_abs_diff": float(np.abs(ref - got).mean()),
            "mask_iou": iou,
            "sky_fraction_onnx": float(ref_mask.mean()),
            "sky_fraction_tflite": float(got_mask.mean()),
        }
        print(photo.name, json.dumps(report["photos"][photo.name]))
    print("input", in_d["shape"], in_d["dtype"].__name__, "output", out_d["shape"], out_d["dtype"].__name__)
    args.out.with_suffix(".json").write_text(json.dumps(report, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
