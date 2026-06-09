"""
Stage 3 — 학습된 모델 → TFLite (Android) + ONNX (CoreML 변환용) 내보내기

수정점 (워크트리 3_export_model.py 대비):
  - import 경로: train → 3_train
  - forward_small() 사용 (5³ 출력, TFLite 호환)

실행: python 7_export_model.py
요구사항:
  Android TFLite: pip install onnx-tf tensorflow
  iOS CoreML:     pip install coremltools (Mac에서 실행)
"""

import os
import sys
import numpy as np
import torch

# 같은 디렉토리의 3_train 임포트
sys.path.insert(0, str(__import__("pathlib").Path(__file__).parent))
from importlib import import_module
_train = import_module("3_train")
ColorTransferNet = _train.ColorTransferNet
LUT_DIM          = _train.LUT_DIM
DECODER_DIM      = _train.DECODER_DIM
CHECKPOINT       = _train.CHECKPOINT
DEVICE           = _train.DEVICE

OUTPUT_ONNX   = "exports/color_transfer.onnx"
OUTPUT_TFLITE = "exports/color_transfer.tflite"

os.makedirs("exports", exist_ok=True)


def load_model() -> ColorTransferNet:
    ckpt  = torch.load(CHECKPOINT, map_location=DEVICE)
    model = ColorTransferNet(DECODER_DIM, LUT_DIM).to(DEVICE)
    model.load_state_dict(ckpt["model"])
    model.eval()
    print(f"모델 로드 완료 (Val ΔE={ckpt['val_de']:.4f})")
    return model


# ── ONNX 내보내기 ─────────────────────────────────────────────────────────────
def export_onnx(model: ColorTransferNet):
    """forward_small() 기반: 5³ LUT 출력 (TFLite 안전)."""
    class _SmallWrapper(torch.nn.Module):
        def __init__(self, m): super().__init__(); self.m = m
        def forward(self, x): return self.m.forward_small(x)

    wrapper = _SmallWrapper(model)
    dummy   = torch.randn(1, 3, 256, 256).to(DEVICE)

    torch.onnx.export(
        wrapper, dummy, OUTPUT_ONNX,
        input_names=["style_image"],
        output_names=["lut_5"],          # (1, 5, 5, 5, 3)
        dynamic_axes={"style_image": {0: "batch"}},
        opset_version=17,
        do_constant_folding=True,
    )
    print(f"ONNX 저장: {OUTPUT_ONNX}")

    # 검증
    import onnxruntime as ort
    sess      = ort.InferenceSession(OUTPUT_ONNX,
                    providers=["CPUExecutionProvider"])
    dummy_np  = np.random.randn(1, 3, 256, 256).astype(np.float32)
    out       = sess.run(None, {"style_image": dummy_np})
    print(f"ONNX 출력 shape: {out[0].shape}")  # (1, 5, 5, 5, 3)


# ── TFLite 변환 (Android) ────────────────────────────────────────────────────
def export_tflite():
    """ONNX → TF SavedModel → TFLite (fp16 quantized, ~18MB)."""
    try:
        import tensorflow as tf
        from onnx_tf.backend import prepare
        import onnx

        print("\nTFLite 변환 중...")
        onnx_model = onnx.load(OUTPUT_ONNX)
        tf_rep     = prepare(onnx_model)
        tf_rep.export_graph("exports/tf_savedmodel")

        converter = tf.lite.TFLiteConverter.from_saved_model("exports/tf_savedmodel")
        converter.optimizations          = [tf.lite.Optimize.DEFAULT]
        converter.target_spec.supported_types = [tf.float16]

        tflite_model = converter.convert()
        with open(OUTPUT_TFLITE, "wb") as f:
            f.write(tflite_model)

        size_mb = os.path.getsize(OUTPUT_TFLITE) / 1e6
        print(f"TFLite 저장: {OUTPUT_TFLITE} ({size_mb:.1f}MB)")
        print("  → Android: lib/ai/models/ 에 복사 후 ai_manager.dart URL 업데이트")

    except ImportError:
        print("\nTFLite 변환 건너뜀 (onnx-tf / tensorflow 미설치)")
        print("Linux/Mac 환경에서 실행:")
        print("  pip install onnx-tf tensorflow")
        print("  python 7_export_model.py")


# ── CoreML 변환 안내 (iOS, Mac 전용) ─────────────────────────────────────────
def print_coreml_guide():
    print("""
──────────────────────────────────────────────
CoreML 변환 (Mac 환경에서 실행):

  pip install coremltools

  import coremltools as ct
  import torch
  from importlib import import_module
  _train = import_module("3_train")
  ColorTransferNet = _train.ColorTransferNet

  model = ColorTransferNet(_train.DECODER_DIM, _train.LUT_DIM)
  ckpt  = torch.load("checkpoints/color_transfer.pt", map_location="cpu")
  model.load_state_dict(ckpt["model"])
  model.eval()

  class SmallWrapper(torch.nn.Module):
      def forward(self, x): return model.forward_small(x)

  traced  = torch.jit.trace(SmallWrapper(), torch.randn(1, 3, 256, 256))
  mlmodel = ct.convert(
      traced,
      inputs=[ct.TensorType(name="style_image", shape=(1,3,256,256))],
      outputs=[ct.TensorType(name="lut_5")],
      compute_precision=ct.precision.FLOAT16,
      minimum_deployment_target=ct.target.iOS15,
  )
  mlmodel.save("exports/color_transfer.mlpackage")
  # → iOS: Runner/ 에 복사 후 ai_manager.dart URL 업데이트
──────────────────────────────────────────────
""")


if __name__ == "__main__":
    model = load_model()
    export_onnx(model)
    export_tflite()
    print_coreml_guide()
