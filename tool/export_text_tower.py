"""Export MobileCLIP text encoder to INT8 ONNX for on-device search.

Supports MobileCLIP-S0 (default) and MobileCLIP-S1 via --model flag.

What it produces (in assets/):
  models/mobileclip_s{0,1}_text_int8.onnx   INT8 text tower
      input  'text':      int64 [batch, context_length]
      output 'embedding': float32 [batch, dim], L2-normalized
  tokenizer/bpe_simple_vocab_16e6.txt.gz     OpenCLIP BPE vocab (~1.7MB)
  tokenizer/config.json                      {"contextLength": N, "dim": D, "embeddingVersion": N}

Setup:
  pip install torch onnx onnxruntime mobileclip open_clip_torch

Usage:
  python tool/export_text_tower.py --model mobileclip_s1
  python tool/export_text_tower.py --model mobileclip_s0  (default)
  python tool/export_text_tower.py --model mobileclip_s1 --checkpoint path/to/mobileclip_s1.pt
"""

import argparse
import gzip
import json
import shutil
import sys
from pathlib import Path

import torch

REPO_ROOT = Path(__file__).resolve().parent.parent
ASSETS = REPO_ROOT / "assets"
TOKENIZER_DIR = ASSETS / "tokenizer"
VOCAB_OUT = TOKENIZER_DIR / "bpe_simple_vocab_16e6.txt.gz"
CONFIG_OUT = TOKENIZER_DIR / "config.json"

MODEL_CONFIGS = {
    "mobileclip_s0": {
        "hf_repo": "apple/MobileCLIP-S0",
        "hf_file": "mobileclip_s0.pt",
        "apple_url": "https://docs-assets.developer.apple.com/ml-research/datasets/mobileclip/mobileclip_s0.pt",
        "version": 1,
    },
    "mobileclip_s1": {
        "hf_repo": "apple/MobileCLIP-S1",
        "hf_file": "mobileclip_s1.pt",
        "apple_url": None,
        "version": 2,
    },
}


def get_model_out(model_name: str) -> Path:
    return ASSETS / "models" / f"{model_name}_text_int8.onnx"


def load_core_model(model_name: str, checkpoint: str | None):
    """Load the MobileCLIP core model (has .encode_text / .context_length)."""
    import mobileclip

    cfg = MODEL_CONFIGS[model_name]

    if checkpoint:
        model, _, _ = mobileclip.create_model_and_transforms(model_name)
        state = torch.load(checkpoint, map_location="cpu")
        state_dict = state.get("state_dict", state) if isinstance(state, dict) else state
        model.load_state_dict(state_dict, strict=False)
    else:
        import urllib.request

        checkpoint_path = REPO_ROOT / "tool" / f"{model_name}.pt"
        if not checkpoint_path.exists():
            url = cfg["apple_url"] or f"https://huggingface.co/{cfg['hf_repo']}/resolve/main/{cfg['hf_file']}"
            print(f"Downloading {model_name} checkpoint from {url} ...")
            urllib.request.urlretrieve(url, checkpoint_path)
            print(f"Downloaded to {checkpoint_path}")

        model, _, _ = mobileclip.create_model_and_transforms(
            model_name, pretrained=str(checkpoint_path)
        )
    model.eval()
    return model


class TextTower(torch.nn.Module):
    """Wraps the checkpoint's text path into a single tidy ONNX graph."""

    def __init__(self, core) -> None:
        super().__init__()
        self.core = core

    def forward(self, text: torch.Tensor) -> torch.Tensor:
        return self.core.encode_text(text)


def export_onnx(core, context_length: int, out_path: Path) -> None:
    tower = TextTower(core).eval()
    dummy = torch.ones(1, context_length, dtype=torch.int64)

    with torch.no_grad():
        torch.onnx.export(
            tower,
            dummy,
            str(out_path),
            input_names=["text"],
            output_names=["embedding"],
            dynamic_axes={"text": {0: "batch"}, "embedding": {0: "batch"}},
            opset_version=17,
            dynamo=False,
        )
    print(f"fp32 export written: {out_path}")


def quantize_int8(fp32_path: Path, out_path: Path) -> None:
    from onnxruntime.quantization import quantize_dynamic, QuantType

    quantize_dynamic(
        model_input=str(fp32_path),
        model_output=str(out_path),
        weight_type=QuantType.QInt8,
    )
    fp32_path.unlink()
    print(f"INT8 quantized model written: {out_path}")


def export_vocab(out_path: Path) -> int:
    """Copy OpenCLIP's BPE vocab (MobileCLIP uses the same tokenizer)."""
    try:
        from open_clip.tokenizer import _tokenizer

        src = Path(_tokenizer.bpe_path)
    except Exception:
        import urllib.request

        src = out_path.with_suffix(".tmp")
        urllib.request.urlretrieve(
            "https://github.com/openai/CLIP/raw/main/clip/bpe_simple_vocab_16e6.txt.gz",
            src,
        )

    TOKENIZER_DIR.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src, out_path)

    with gzip.open(out_path, "rt", encoding="utf-8") as fh:
        first = fh.readline().strip()
    print(f"vocab copied ({first!r} header): {out_path}")
    return len(first)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--model",
        type=str,
        default="mobileclip_s0",
        choices=list(MODEL_CONFIGS.keys()),
        help="MobileCLIP variant to export (default: mobileclip_s0)",
    )
    parser.add_argument(
        "--checkpoint",
        type=str,
        default=None,
        help="Path to checkpoint .pt (omit to auto-download)",
    )
    args = parser.parse_args()

    model_out = get_model_out(args.model)
    core = load_core_model(args.model, args.checkpoint)

    context_length = int(getattr(core, "context_length", 77))
    with torch.no_grad():
        probe = torch.ones(1, context_length, dtype=torch.int64)
        dim = int(core.encode_text(probe).shape[-1])
    print(f"context_length={context_length} embedding_dim={dim}")

    model_out.parent.mkdir(parents=True, exist_ok=True)
    TOKENIZER_DIR.mkdir(parents=True, exist_ok=True)

    fp32_tmp = model_out.with_suffix(".fp32.onnx")
    export_onnx(core, context_length, fp32_tmp)
    quantize_int8(fp32_tmp, model_out)
    export_vocab(VOCAB_OUT)

    version = MODEL_CONFIGS[args.model]["version"]
    CONFIG_OUT.write_text(
        json.dumps({"contextLength": context_length, "dim": dim, "embeddingVersion": version})
    )
    print(f"config written: {CONFIG_OUT}")
    print(f"\nDone. Model: {model_out.name}, dim={dim}, version={version}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
