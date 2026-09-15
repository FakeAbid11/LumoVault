"""Export MobileOne-S2 image classifier to ONNX for on-device photo labeling.

Produces:
  assets/models/mobileone_s2.onnx   FP32 classifier (~8MB)
      input  'input':  float32 [batch, 3, 224, 224]  (ImageNet-normalized)
      output 'output': float32 [batch, 1000]           (logits)

Setup:
  pip install torch timm onnx onnxruntime

Usage:
  python tool/export_classifier.py
"""

import sys
from pathlib import Path

import torch

REPO_ROOT = Path(__file__).resolve().parent.parent
ASSETS = REPO_ROOT / "assets"
MODEL_OUT = ASSETS / "models" / "mobileone_s2.onnx"


def main() -> int:
    import timm

    model = timm.create_model("mobileone_s2", pretrained=True, num_classes=1000)
    model.eval()

    dummy = torch.randn(1, 3, 224, 224)

    MODEL_OUT.parent.mkdir(parents=True, exist_ok=True)

    with torch.no_grad():
        torch.onnx.export(
            model,
            dummy,
            str(MODEL_OUT),
            input_names=["input"],
            output_names=["output"],
            dynamic_axes={"input": {0: "batch"}, "output": {0: "batch"}},
            opset_version=17,
            dynamo=False,
        )

    size_mb = MODEL_OUT.stat().st_size / (1024 * 1024)
    print(f"MobileOne-S2 ONNX written: {MODEL_OUT} ({size_mb:.1f} MB)")

    with torch.no_grad():
        probe = model(dummy)
    print(f"Output shape: {probe.shape}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
