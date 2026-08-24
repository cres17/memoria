"""Convert the validated direct-MVP ONNX bundle to float16-weight TFLite."""

from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path

import numpy as np
import onnx
from onnx import helper, numpy_helper
from onnx_tf.backend import prepare
import tensorflow as tf


PIPELINE_DIR = Path(__file__).resolve().parent
DEPLOYMENT_DIR = PIPELINE_DIR / "reports" / "deployment"
ONNX_MODEL = DEPLOYMENT_DIR / "direct_mvp_family_holdout_smooth_010_001.onnx"
SAVED_MODEL = DEPLOYMENT_DIR / "direct_mvp_family_holdout_smooth_010_001_savedmodel"
TFLITE_MODEL = DEPLOYMENT_DIR / "direct_mvp_family_holdout_smooth_010_001_fp16.tflite"
REPORT_OUTPUT = DEPLOYMENT_DIR / "direct_mvp_tflite_conversion_001.json"
PARITY_FIXTURE = DEPLOYMENT_DIR / "direct_mvp_onnx_parity_fixture_001.npz"
MAX_FP16_ABS_ERROR = 2e-3


def decompose_layer_normalization(model: onnx.ModelProto) -> int:
    """Replace ONNX LayerNormalization with opset-17 primitives supported by onnx-tf."""
    rewritten = []
    count = 0
    for node in model.graph.node:
        if node.op_type != "LayerNormalization":
            rewritten.append(node)
            continue
        if len(node.input) != 3 or len(node.output) != 1:
            raise ValueError(f"unsupported LayerNormalization node: {node.name}")
        attributes = {attribute.name: helper.get_attribute_value(attribute) for attribute in node.attribute}
        axis = int(attributes.get("axis", -1))
        epsilon = float(attributes.get("epsilon", 1e-5))
        source, scale, bias = node.input
        output = node.output[0]
        prefix = f"{node.name.replace('/', '_')}_tflite"
        epsilon_name = f"{prefix}_epsilon"
        model.graph.initializer.append(numpy_helper.from_array(np.asarray(epsilon, dtype=np.float32), epsilon_name))
        mean, centered = f"{prefix}_mean", f"{prefix}_centered"
        squared, variance = f"{prefix}_squared", f"{prefix}_variance"
        variance_epsilon, std = f"{prefix}_variance_epsilon", f"{prefix}_std"
        normalized, scaled = f"{prefix}_normalized", f"{prefix}_scaled"
        rewritten.extend((
            helper.make_node("ReduceMean", [source], [mean], name=f"{prefix}_mean", axes=[axis], keepdims=1),
            helper.make_node("Sub", [source, mean], [centered], name=f"{prefix}_center"),
            helper.make_node("Mul", [centered, centered], [squared], name=f"{prefix}_square"),
            helper.make_node("ReduceMean", [squared], [variance], name=f"{prefix}_variance", axes=[axis], keepdims=1),
            helper.make_node("Add", [variance, epsilon_name], [variance_epsilon], name=f"{prefix}_epsilon_add"),
            helper.make_node("Sqrt", [variance_epsilon], [std], name=f"{prefix}_sqrt"),
            helper.make_node("Div", [centered, std], [normalized], name=f"{prefix}_normalize"),
            helper.make_node("Mul", [normalized, scale], [scaled], name=f"{prefix}_scale"),
            helper.make_node("Add", [scaled, bias], [output], name=f"{prefix}_bias"),
        ))
        count += 1
    del model.graph.node[:]
    model.graph.node.extend(rewritten)
    return count


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--onnx-model", type=Path, default=ONNX_MODEL)
    parser.add_argument("--saved-model", type=Path, default=SAVED_MODEL)
    parser.add_argument("--tflite-model", type=Path, default=TFLITE_MODEL)
    parser.add_argument("--output", type=Path, default=REPORT_OUTPUT)
    parser.add_argument("--parity-fixture", type=Path, default=PARITY_FIXTURE)
    args = parser.parse_args()
    if not args.onnx_model.exists():
        raise FileNotFoundError(f"ONNX artifact is missing: {args.onnx_model}")
    if not args.parity_fixture.exists():
        raise FileNotFoundError(f"PyTorch parity fixture is missing: {args.parity_fixture}")

    if args.saved_model.exists():
        shutil.rmtree(args.saved_model)
    onnx_model = onnx.load(args.onnx_model, load_external_data=True)
    source_ir_version = int(onnx_model.ir_version)
    # onnx-tf 1.10's bundled checker accepts IR <= 9. This graph uses no IR v10
    # features, so lowering the container metadata allows the converter to read
    # the already ONNX Runtime-validated graph.
    if source_ir_version > 9:
        onnx_model.ir_version = 9
    decomposed_layer_norms = decompose_layer_normalization(onnx_model)
    onnx.checker.check_model(onnx_model)
    prepare(onnx_model).export_graph(args.saved_model)

    converter = tf.lite.TFLiteConverter.from_saved_model(str(args.saved_model))
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.target_spec.supported_types = [tf.float16]
    tflite_bytes = converter.convert()
    args.tflite_model.parent.mkdir(parents=True, exist_ok=True)
    args.tflite_model.write_bytes(tflite_bytes)

    with np.load(args.parity_fixture) as fixture:
        reference = fixture["style_image"]
        pytorch_output = fixture["pytorch_lut"]
    saved = tf.saved_model.load(str(args.saved_model))
    signature = saved.signatures["serving_default"]
    saved_output = next(iter(signature(style_image=tf.convert_to_tensor(reference)).values())).numpy()

    interpreter = tf.lite.Interpreter(model_path=str(args.tflite_model), num_threads=2)
    interpreter.allocate_tensors()
    input_detail = interpreter.get_input_details()[0]
    output_detail = interpreter.get_output_details()[0]
    interpreter.set_tensor(input_detail["index"], reference)
    interpreter.invoke()
    tflite_output = interpreter.get_tensor(output_detail["index"])
    if tuple(tflite_output.shape) != tuple(saved_output.shape):
        raise RuntimeError(f"TFLite output shape {tflite_output.shape} differs from SavedModel {saved_output.shape}")
    max_abs_error = float(np.max(np.abs(saved_output - tflite_output)))
    if max_abs_error > MAX_FP16_ABS_ERROR:
        raise RuntimeError(f"TFLite parity error {max_abs_error} exceeds {MAX_FP16_ABS_ERROR}")
    savedmodel_error = float(np.max(np.abs(pytorch_output - saved_output)))
    tflite_error = float(np.max(np.abs(pytorch_output - tflite_output)))
    if savedmodel_error > 1e-4:
        raise RuntimeError(f"SavedModel parity error {savedmodel_error} exceeds 1e-4")
    if tflite_error > MAX_FP16_ABS_ERROR:
        raise RuntimeError(f"TFLite-vs-PyTorch parity error {tflite_error} exceeds {MAX_FP16_ABS_ERROR}")

    report = {
        "schema_version": 1,
        "experiment_id": "DIRECT-MVP-TFLITE-CONVERSION-001",
        "source_onnx": str(args.onnx_model),
        "source_onnx_ir_version": source_ir_version,
        "converter_onnx_ir_version": int(onnx_model.ir_version),
        "decomposed_layer_normalizations": decomposed_layer_norms,
        "tflite": {
            "path": str(args.tflite_model),
            "bytes": args.tflite_model.stat().st_size,
            "weight_precision": "float16",
            "input": {"shape": input_detail["shape"].tolist(), "dtype": input_detail["dtype"].__name__},
            "output": {"shape": output_detail["shape"].tolist(), "dtype": output_detail["dtype"].__name__},
            "max_abs_error_vs_savedmodel": max_abs_error,
            "savedmodel_max_abs_error_vs_pytorch": savedmodel_error,
            "max_abs_error_vs_pytorch": tflite_error,
            "max_allowed_abs_error": MAX_FP16_ABS_ERROR,
        },
        "contract": "Compatible with LutPredictor's NCHW float32 input and [1,17,17,17,3] float32 output. This validates desktop TensorFlow Lite only; Android/iOS device latency remains required.",
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(f"direct MVP TFLite conversion complete -> {args.output}")


if __name__ == "__main__":
    main()
