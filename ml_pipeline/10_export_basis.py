"""Exports the P4 basis-weight experiment without shipping a full LUT decoder.

The TFLite model emits [1, K] bounded coefficients. ``basis_lut.bin`` carries
the mean/residual tensors in a documented little-endian format:
  magic ``MBLT`` | uint32 version | uint32 basis_dim | uint32 num_bases |
  float32 mean[dim³*3] | float32 residual_bases[K][dim³*3]

Neither artifact is connected to product routing until device measurements and
the Dart common safety gate pass on the approved fixture set.
"""

import importlib
import json
import os
import struct

import numpy as np
import torch

train = importlib.import_module("8_train_basis")
EXPORT_DIR = "exports"
ONNX_PATH = os.path.join(EXPORT_DIR, "basis_weights.onnx")
TFLITE_PATH = os.path.join(EXPORT_DIR, "basis_weights.tflite")
BASIS_BINARY_PATH = os.path.join(EXPORT_DIR, "basis_lut.bin")
METADATA_PATH = os.path.join(EXPORT_DIR, "basis_lut_metadata.json")


def load_model():
    checkpoint = torch.load(train.MODEL_PATH, map_location="cpu")
    model = train.BasisWeightNet(int(checkpoint["num_bases"]))
    model.load_state_dict(checkpoint["state_dict"])
    model.eval()
    return model, checkpoint


def write_basis_binary(mean: np.ndarray, bases: np.ndarray):
    mean = mean.astype("<f4", copy=False).reshape(-1)
    bases = bases.astype("<f4", copy=False).reshape(-1)
    with open(BASIS_BINARY_PATH, "wb") as output:
        output.write(struct.pack("<4sIII", b"MBLT", 1, train.BASIS_DIM, len(bases) // len(mean)))
        output.write(mean.tobytes())
        output.write(bases.tobytes())


def export_onnx(model, num_bases):
    dummy = torch.zeros(1, 3, train.IMAGE_SIZE, train.IMAGE_SIZE)
    torch.onnx.export(
        model,
        dummy,
        ONNX_PATH,
        input_names=["style_image"],
        output_names=["basis_coefficients"],
        dynamic_axes={"style_image": {0: "batch"}},
        # Use the legacy exporter for ONNX 17, which is supported by onnx-tf.
        dynamo=False,
        opset_version=17,
        do_constant_folding=True,
    )
    print(f"wrote {ONNX_PATH} with [1, {num_bases}] output")


def export_tflite():
    try:
        import onnx
        import tensorflow as tf
        from onnx_tf.backend import prepare

        representation = prepare(onnx.load(ONNX_PATH))
        representation.export_graph(os.path.join(EXPORT_DIR, "basis_tf_savedmodel"))
        converter = tf.lite.TFLiteConverter.from_saved_model(
            os.path.join(EXPORT_DIR, "basis_tf_savedmodel")
        )
        converter.optimizations = [tf.lite.Optimize.DEFAULT]
        converter.target_spec.supported_types = [tf.float16]
        with open(TFLITE_PATH, "wb") as output:
            output.write(converter.convert())
        print(f"wrote {TFLITE_PATH}")
    except ImportError:
        print("TFLite export skipped; install tensorflow, onnx, and onnx-tf to enable it.")


if __name__ == "__main__":
    os.makedirs(EXPORT_DIR, exist_ok=True)
    mean, bases, coefficient_scales = train.load_basis()
    model, checkpoint = load_model()
    write_basis_binary(mean, bases)
    export_onnx(model, int(checkpoint["num_bases"]))
    export_tflite()
    metadata = {
        "format": "MBLT",
        "version": 1,
        "basisDim": train.BASIS_DIM,
        "numBases": int(checkpoint["num_bases"]),
        "axisOrder": "r_fastest_rgb",
        "coefficientBound": train.COEFFICIENT_BOUND,
        "coefficientSpace": "normalized_scaled_bases",
        "pretrainedWeights": False,
        "productRouting": "disabled_until_benchmark_and_common_safety_gate_pass",
    }
    with open(METADATA_PATH, "w") as output:
        json.dump(metadata, output, indent=2)
        output.write("\n")
    print(f"wrote {BASIS_BINARY_PATH} and {METADATA_PATH}")
