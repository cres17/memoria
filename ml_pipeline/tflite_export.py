"""PyTorch 모델을 float16 가중치 TFLite로 변환하는 공용 함수.

litert-torch가 PyTorch 그래프를 LiteRT(TFLite) 모델로 직접 변환하므로
ONNX → onnx-tf → TensorFlow SavedModel 단계를 거치지 않는다. 변환 환경에
TensorFlow · keras · onnx-tf가 필요 없다.

가중치는 ai-edge-quantizer의 float casting(weight-only float16)으로 줄인다.
양자화 도구는 256KB 이상 모델의 가중치를 flatbuffer 뒤쪽에 offset으로 따로 저장하는데,
앱이 쓰는 flutter_litert(LiteRT 2.20 C 라이브러리)는 이 형식의 float16 상수를 읽지 못해
"Input tensor N lacks data"로 실행에 실패한다. 그래서 저장 직전에 모든 가중치를
flatbuffer 본문으로 다시 넣는다(TFLite flatbuffer 한도인 2GB 미만 모델만 해당).
"""

from __future__ import annotations

from pathlib import Path

import flatbuffers
import numpy as np
import torch

FLOAT16_WEIGHT_RECIPE = [
    {
        "regex": ".*",
        "operation": "*",
        "algorithm_key": "float_casting",
        "op_config": {
            "weight_tensor_config": {"num_bits": 16, "dtype": "FLOAT"},
            "compute_precision": "FLOAT",
            "explicit_dequantize": True,
            "skip_checks": False,
        },
    }
]
_FLATBUFFER_LIMIT = 2 * 1024**3


def inline_buffers(model_bytes: bytes) -> bytes:
    """offset으로 저장된 가중치를 flatbuffer 본문으로 옮긴 모델 bytes를 반환한다."""
    from ai_edge_litert import schema_py_generated as schema

    model = schema.ModelT.InitFromObj(schema.Model.GetRootAsModel(model_bytes, 0))
    for buffer in model.buffers:
        if buffer.offset and buffer.offset > 1:
            start, end = buffer.offset, buffer.offset + buffer.size
            buffer.data = np.frombuffer(model_bytes[start:end], dtype=np.uint8)
            buffer.offset = 0
            buffer.size = 0
    builder = flatbuffers.Builder(len(model_bytes))
    builder.Finish(model.Pack(builder), file_identifier=b"TFL3")
    packed = bytes(builder.Output())
    if len(packed) >= _FLATBUFFER_LIMIT:
        raise ValueError("inlined TFLite model exceeds the 2GB flatbuffer limit")
    return packed


def convert_fp16(module: torch.nn.Module, sample: torch.Tensor, output_path: Path) -> Path:
    """`module(sample)`을 추적해 float16 가중치 TFLite 파일로 저장한다."""
    import litert_torch
    from ai_edge_quantizer import quantizer

    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    float32_path = output_path.with_name(output_path.stem + "_float32.tflite")
    litert_torch.convert(module.eval(), (sample,)).export(str(float32_path))
    try:
        fp16 = quantizer.Quantizer(str(float32_path))
        fp16.load_quantization_recipe(FLOAT16_WEIGHT_RECIPE)
        quantized = bytes(fp16.quantize().quantized_model)
    finally:
        float32_path.unlink(missing_ok=True)
    output_path.write_bytes(inline_buffers(quantized))
    return output_path


def run_tflite(model_path: Path, array: np.ndarray, num_threads: int = 2):
    """단일 입력 · 단일 출력 TFLite 모델을 실행하고 (출력, 입력 정보, 출력 정보)를 반환한다."""
    from ai_edge_litert.interpreter import Interpreter

    interpreter = Interpreter(model_path=str(model_path), num_threads=num_threads)
    interpreter.allocate_tensors()
    input_detail = interpreter.get_input_details()[0]
    output_detail = interpreter.get_output_details()[0]
    interpreter.set_tensor(input_detail["index"], np.ascontiguousarray(array, dtype=np.float32))
    interpreter.invoke()
    return interpreter.get_tensor(output_detail["index"]), input_detail, output_detail
