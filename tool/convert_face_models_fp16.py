"""Convert ONNX models to FP16 in place — halves model bytes, no calibration.

FP16 (not INT8) is the right conversion for the face models: SCRFD and
MobileFaceNet are Conv-heavy, and dynamic INT8 quantization only shrinks
MatMul/Gemm layers, so it does almost nothing here. ONNX Runtime casts the
app's existing fp32 input tensors automatically, so no Dart changes follow.

Usage:
  pip install onnx onnxconverter-common
  python tool/convert_face_models_fp16.py assets/models/w600k_mbf.onnx
  python tool/convert_face_models_fp16.py assets/models/det_500m.onnx
  python tool/convert_face_models_fp16.py assets/models/scrfd_2_5g_kps.onnx

For the 2.5G detector itself, download scrfd_2.5g_kps.zip from the InsightFace
SCRFD release and unpack the .onnx into assets/models/ first:
  https://github.com/deepinsight/insightface/releases (SCRFD section)
"""

import sys
from pathlib import Path

import onnx
from onnxconverter_common import float16


def convert_to_fp16(path: Path) -> None:
    model = onnx.load(str(path))
    # keep_io_types=True keeps inputs/outputs fp32, so the app's existing
    # tensor-building code and the flutter_onnxruntime calls stay unchanged.
    fp16_model = float16.convert_float_to_float16(model, keep_io_types=True)
    onnx.save(fp16_model, str(path))

    before = path.stat().st_size / (1024 * 1024)
    print(f"converted to fp16: {path} (now {before:.1f} MB)")


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    for arg in sys.argv[1:]:
        path = Path(arg)
        if not path.exists():
            print(f"skip (missing): {path}")
            continue
        convert_to_fp16(path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
