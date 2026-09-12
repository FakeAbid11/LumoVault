"""Export MobileCLIP-S1 image tower to ONNX for on-device photo embedding.

Produces:
  assets/models/mobileclip_s1.onnx   FP32 image tower (~25MB)
      input  'image':  float32 [batch, 3, 336, 336]  (CLIP-normalized)
      output 'embedding': float32 [batch, dim]         (L2-normalized)

Setup:
  pip install torch onnx onnxruntime mobileclip open_clip_torch

Usage:
  python tool/export_image_tower.py [--checkpoint path/to/mobileclip_s1.pt]
"""

import argparse
import json
import sys
from pathlib import Path

import torch

REPO_ROOT = Path(__file__).resolve().parent.parent
ASSETS = REPO_ROOT / "assets"
MODEL_OUT = ASSETS / "models" / "mobileclip_s1.onnx"
TOKENIZER_DIR = ASSETS / "tokenizer"
CONFIG_OUT = TOKENIZER_DIR / "config.json"


def load_core_model(checkpoint: str | None):
    """Load the MobileCLIP-S1 core model."""
    import mobileclip

    if checkpoint:
        model, _, _ = mobileclip.create_model_and_transforms("mobileclip_s1")
        state = torch.load(checkpoint, map_location="cpu")
        state_dict = state.get("state_dict", state) if isinstance(state, dict) else state
        model.load_state_dict(state_dict, strict=False)
    else:
        import urllib.request

        checkpoint_path = REPO_ROOT / "tool" / "mobileclip_s1.pt"
        if not checkpoint_path.exists():
            url = "https://huggingface.co/apple/MobileCLIP-S1/resolve/main/mobileclip_s1.pt"
            print(f"Downloading MobileCLIP-S1 checkpoint from {url} ...")
            urllib.request.urlretrieve(url, checkpoint_path)
            print(f"Downloaded to {checkpoint_path}")

        model, _, _ = mobileclip.create_model_and_transforms(
            "mobileclip_s1", pretrained=str(checkpoint_path)
        )

    try:
        from mobileclip import reparameterize_model
        model = reparameterize_model(model)
        print("Model reparameterized for export")
    except Exception as e:
        print(f"Reparameterization skipped: {e}")

    model.eval()
    return model


class ImageTower(torch.nn.Module):
    """Wraps the image encoder path into a tidy ONNX graph."""

    def __init__(self, core) -> None:
        super().__init__()
        self.core = core

    def forward(self, image: torch.Tensor) -> torch.Tensor:
        return self.core.encode_image(image)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--checkpoint",
        type=str,
        default=None,
        help="Path to mobileclip_s1.pt (omit to auto-download from HuggingFace)",
    )
    args = parser.parse_args()

    core = load_core_model(args.checkpoint)

    dummy = torch.randn(1, 3, 336, 336)

    tower = ImageTower(core).eval()
    MODEL_OUT.parent.mkdir(parents=True, exist_ok=True)

    with torch.no_grad():
        torch.onnx.export(
            tower,
            dummy,
            str(MODEL_OUT),
            input_names=["image"],
            output_names=["embedding"],
            opset_version=18,
            dynamo=False,
        )

    size_mb = MODEL_OUT.stat().st_size / (1024 * 1024)
    print(f"MobileCLIP-S1 image tower written: {MODEL_OUT} ({size_mb:.1f} MB)")

    with torch.no_grad():
        probe = tower(dummy)
    dim = probe.shape[-1]
    print(f"Embedding dim: {dim}, shape: {probe.shape}")

    TOKENIZER_DIR.mkdir(parents=True, exist_ok=True)
    config = json.loads(CONFIG_OUT.read_text()) if CONFIG_OUT.exists() else {}
    config["dim"] = dim
    CONFIG_OUT.write_text(json.dumps(config))
    print(f"config.json updated: {CONFIG_OUT}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
