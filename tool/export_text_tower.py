"""Export the MobileCLIP S0 text encoder to INT8 ONNX for on-device search.

Run this ONCE on a machine with Python + internet. The app ships the image
tower already (assets/models/mobileclip_s0.onnx); this script produces the
matching TEXT tower so Dart can embed search queries into the same 512-dim
space as the stored image embeddings.

What it produces (in assets/):
  models/mobileclip_s0_text_int8.onnx   INT8 text tower (~40-45MB)
      input  'text':     int64 [batch, context_length]
      output 'embedding': float32 [batch, 512], L2-normalized
  tokenizer/bpe_simple_vocab_16e6.txt.gz   OpenCLIP BPE vocab (~1.7MB)
  tokenizer/config.json                    {"contextLength": N, "dim": 512}

After it finishes, uncomment the two asset lines in pubspec.yaml (marked
'INT8 TEXT TOWER') and rebuild. Until then the app runs fine with semantic
search showing an explicit 'model not in this build' state.

Setup:
  pip install torch onnx onnxruntime mobileclip open_clip_torch
  python tool/export_text_tower.py [--checkpoint path/to/mobileclip_s0.pt]

The checkpoint comes from Apple's release page:
  https://github.com/apple/ml-mobileclip (checkpoints section)
If --checkpoint is omitted, the script tries the pretrained download via
`mobileclip.create_model_and_transforms('MobileCLIP-S0', pretrained=...)`.
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
MODEL_OUT = ASSETS / "models" / "mobileclip_s0_text_int8.onnx"
TOKENIZER_DIR = ASSETS / "tokenizer"
VOCAB_OUT = TOKENIZER_DIR / "bpe_simple_vocab_16e6.txt.gz"
CONFIG_OUT = TOKENIZER_DIR / "config.json"


def load_core_model(checkpoint: str | None):
    """Load the MobileCLIP core model (has .encode_text / .context_length)."""
    import mobileclip  # noqa: deferred — only needed for the export.

    if checkpoint:
        model, _, _ = mobileclip.create_model_and_transforms("MobileCLIP-S0")
        state = torch.load(checkpoint, map_location="cpu")
        # The release checkpoint stores the full core model under 'state_dict'
        # (or the raw state itself, depending on the release).
        state_dict = state.get("state_dict", state) if isinstance(state, dict) else state
        model.load_state_dict(state_dict, strict=False)
    else:
        model, _, _ = mobileclip.create_model_and_transforms(
            "MobileCLIP-S0", pretrained="datacompdr"
        )
    model.eval()
    return model


class TextTower(torch.nn.Module):
    """Wraps the checkpoint's text path into a single tidy ONNX graph.

    Input:  int64 token ids [batch, context_length] (SOT ... EOT, zero-padded)
    Output: float32 [batch, 512] projected + L2-normalized embedding — the
    exact same space as the image tower's output.
    """

    def __init__(self, core) -> None:
        super().__init__()
        self.core = core

    def forward(self, text: torch.Tensor) -> torch.Tensor:
        # ml-mobileclip's core model exposes encode_text(text) which already
        # does: encoder -> EOT-pool -> projection -> L2 normalize.
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
            # Batch is dynamic; the token axis stays fixed to context_length
            # (the tokenizer always pads to it).
            dynamic_axes={"text": {0: "batch"}, "embedding": {0: "batch"}},
            opset_version=17,
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
    except Exception:  # pragma: no cover — fallback when open_clip is absent
        import urllib.request

        src = out_path.with_suffix(".tmp")
        urllib.request.urlretrieve(
            "https://github.com/openai/CLIP/raw/main/clip/bpe_simple_vocab_16e6.txt.gz",
            src,
        )

    TOKENIZER_DIR.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src, out_path)

    # Sanity: the file must parse as gzip with the expected header.
    with gzip.open(out_path, "rt", encoding="utf-8") as fh:
        first = fh.readline().strip()
    print(f"vocab copied ({first!r} header): {out_path}")
    return len(first)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--checkpoint",
        type=str,
        default=None,
        help="Path to mobileclip_s0.pt (omit to use the pretrained download)",
    )
    args = parser.parse_args()

    core = load_core_model(args.checkpoint)

    context_length = int(getattr(core, "context_length", 77))
    with torch.no_grad():
        probe = torch.ones(1, context_length, dtype=torch.int64)
        dim = int(core.encode_text(probe).shape[-1])
    print(f"context_length={context_length} embedding_dim={dim}")

    MODEL_OUT.parent.mkdir(parents=True, exist_ok=True)
    TOKENIZER_DIR.mkdir(parents=True, exist_ok=True)

    fp32_tmp = MODEL_OUT.with_suffix(".fp32.onnx")
    export_onnx(core, context_length, fp32_tmp)
    quantize_int8(fp32_tmp, MODEL_OUT)
    export_vocab(VOCAB_OUT)

    CONFIG_OUT.write_text(
        json.dumps({"contextLength": context_length, "dim": dim})
    )
    print(f"config written: {CONFIG_OUT}")
    print("\nDone. Now uncomment the 'INT8 TEXT TOWER' asset lines in"
          " pubspec.yaml, then: flutter pub get && flutter test")
    return 0


if __name__ == "__main__":
    sys.exit(main())
