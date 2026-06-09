#!/usr/bin/env bash
# Convert best.pt → ONNX → TFLite (fp16)
# Requirements: pip install onnx onnx-tf tensorflow

set -e
CKPT="${1:-ml/checkpoints/best.pt}"
ONNX="ml/checkpoints/model.onnx"
SAVED_MODEL="ml/checkpoints/saved_model"
TFLITE="ml/color_transfer.tflite"

echo "Step 1: PyTorch → ONNX"
python - <<'PY'
import torch
from ml.train import ColorTransferModel
import sys

ckpt_path = sys.argv[1] if len(sys.argv) > 1 else "ml/checkpoints/best.pt"
model = ColorTransferModel()
model.load_state_dict(torch.load(ckpt_path, map_location="cpu")["model_state"])
model.eval()

dummy = torch.zeros(1, 3, 256, 256)
torch.onnx.export(
    model, dummy, "ml/checkpoints/model.onnx",
    input_names=["style_image"], output_names=["lut"],
    opset_version=12,
)
print("ONNX saved.")
PY

echo "Step 2: ONNX → TF SavedModel"
python -c "
import onnx
from onnx_tf.backend import prepare
model = onnx.load('$ONNX')
tf_rep = prepare(model)
tf_rep.export_graph('$SAVED_MODEL')
print('SavedModel saved.')
"

echo "Step 3: SavedModel → TFLite (fp16)"
python -c "
import tensorflow as tf
converter = tf.lite.TFLiteConverter.from_saved_model('$SAVED_MODEL')
converter.optimizations = [tf.lite.Optimize.DEFAULT]
converter.target_spec.supported_types = [tf.float16]
tflite_model = converter.convert()
open('$TFLITE', 'wb').write(tflite_model)
import os
size_mb = os.path.getsize('$TFLITE') / 1024 / 1024
print(f'TFLite saved: $TFLITE  ({size_mb:.1f} MB)')
"
