#!/usr/bin/env python3
"""Independent NumPy Qwen3 oracle; never used by the Flexscript inference path."""
import argparse
import json
import os
import struct
from pathlib import Path

os.environ.setdefault("OPENBLAS_NUM_THREADS", "2")
os.environ.setdefault("OMP_NUM_THREADS", "2")
import numpy as np


class Checkpoint:
    def __init__(self, directory, weight_storage="bf16"):
        self.weight_storage = weight_storage
        self.tensor_core_prefill = False
        self.directory = Path(directory)
        self.config = json.loads((self.directory / "config.json").read_text())
        self.index = json.loads((self.directory / "model.safetensors.index.json").read_text())["weight_map"]
        self.shards = {}
        for shard in set(self.index.values()):
            path = self.directory / shard
            with path.open("rb") as file:
                length = struct.unpack("<Q", file.read(8))[0]
                header = json.loads(file.read(length))
            self.shards[shard] = (np.memmap(path, mode="r", dtype=np.uint8), length + 8, header)

    def weight(self, name, rows=None):
        shard, start, header = self.shards[self.index[name]]
        spec = header[name]
        assert spec["dtype"] == "BF16"
        begin, end = spec["data_offsets"]
        raw = shard[start + begin:start + end].view("<u2").reshape(spec["shape"])
        if rows is not None:
            raw = raw[rows]
        value = (raw.astype(np.uint32) << 16).view(np.float32)
        if self.weight_storage != "bf16":
            value = value.astype(np.float16).astype(np.float32)
        return value

    def linear(self, name, x):
        # Chunk the vocabulary projection to bound temporary host memory.
        rows = self.shards[self.index[name]][2][name]["shape"][0]
        half_products = self.tensor_core_prefill and name != "lm_head.weight"
        if half_products:
            x = x.astype(np.float16).astype(np.float32)
        outputs = []
        for i in range(0, rows, 2048):
            weight = self.weight(name, slice(i, i + 2048))
            if half_products:
                weight = weight.astype(np.float16).astype(np.float32)
            outputs.append(weight @ x)
        return np.concatenate(outputs)


def reference(checkpoint, ids, prompt_count=0):
    c = checkpoint.config
    heads, kv_heads, width = c["num_attention_heads"], c["num_key_value_heads"], c["head_dim"]
    caches = [([], []) for _ in range(c["num_hidden_layers"])]
    inv_freq = 1.0 / (c["rope_theta"] ** (np.arange(0, width, 2, dtype=np.float32) / width))

    def rms(x, name):
        return x * (1 / np.sqrt(np.mean(x * x, axis=-1, keepdims=True) + c["rms_norm_eps"])) * checkpoint.weight(name)

    results = []
    for position, token in enumerate(ids):
        checkpoint.tensor_core_prefill = position < prompt_count
        x = checkpoint.weight("model.embed_tokens.weight", token)
        cosine = np.cos(position * inv_freq)
        sine = np.sin(position * inv_freq)

        def rotary(v):
            left, right = np.split(v, 2, axis=-1)
            return np.concatenate((left * cosine - right * sine, right * cosine + left * sine), axis=-1)

        for layer, (keys, values) in enumerate(caches):
            prefix = f"model.layers.{layer}."
            h = rms(x, prefix + "input_layernorm.weight")
            q = checkpoint.linear(prefix + "self_attn.q_proj.weight", h).reshape(heads, width)
            k = checkpoint.linear(prefix + "self_attn.k_proj.weight", h).reshape(kv_heads, width)
            v = checkpoint.linear(prefix + "self_attn.v_proj.weight", h).reshape(kv_heads, width)
            q = rotary(rms(q, prefix + "self_attn.q_norm.weight"))
            k = rotary(rms(k, prefix + "self_attn.k_norm.weight"))
            keys.append(k)
            values.append(v)
            kk = np.repeat(np.stack(keys), heads // kv_heads, axis=1)
            vv = np.repeat(np.stack(values), heads // kv_heads, axis=1)
            scores = np.einsum("hd,thd->ht", q, kk) / np.sqrt(np.float32(width))
            scores = np.exp(scores - scores.max(axis=-1, keepdims=True))
            scores /= scores.sum(axis=-1, keepdims=True)
            attention = np.einsum("ht,thd->hd", scores, vv).reshape(-1)
            x = x + checkpoint.linear(prefix + "self_attn.o_proj.weight", attention)
            h = rms(x, prefix + "post_attention_layernorm.weight")
            gate = checkpoint.linear(prefix + "mlp.gate_proj.weight", h)
            gate = gate / (1 + np.exp(-gate))
            up = checkpoint.linear(prefix + "mlp.up_proj.weight", h)
            x = x + checkpoint.linear(prefix + "mlp.down_proj.weight", gate * up)
        results.append(checkpoint.linear("lm_head.weight", rms(x, "model.norm.weight")))
        print(f"Reference token {position + 1}/{len(ids)}", flush=True)
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkpoint", required=True)
    parser.add_argument("--report", required=True)
    parser.add_argument("--logits")
    parser.add_argument("--logits-prefix")
    parser.add_argument("--save-reference-prefix", help="Save independent reference logits for reuse")
    parser.add_argument("--output", default="build/llm/reference.json")
    parser.add_argument("--math", choices=["report", "fp32"], default="report",
                        help="Match reported weight storage and batch FP16 products, or use original BF16/FP32 math")
    args = parser.parse_args()
    report = json.loads(Path(args.report).read_text())
    assert args.logits or args.logits_prefix, "provide --logits or --logits-prefix"
    ids = report["input_ids"]
    if args.logits_prefix:
        ids = ids + report["generated_ids"][:-1]
    storage = report.get("weight_storage", "bf16") if args.math == "report" else "bf16"
    assert storage in ("bf16", "f16", "f16-tiled")
    prompt_count = len(report["input_ids"]) if args.math == "report" and report.get("prefill_mode") == "batch" else 0
    predictions = reference(Checkpoint(args.checkpoint, storage), ids, prompt_count)
    offset = len(report["input_ids"]) - 1
    tolerance = 0.02 if prompt_count else 0.002
    results = []
    for step, expected in enumerate(predictions[offset:]):
        path = f"{args.logits_prefix}{step}.f32" if args.logits_prefix else args.logits
        if args.save_reference_prefix:
            expected.astype("<f4").tofile(f"{args.save_reference_prefix}{step}.f32")
        actual = np.fromfile(path, dtype="<f4")
        assert actual.shape == expected.shape and np.isfinite(actual).all()
        error = np.abs(actual - expected)
        result = {"step": step, "weight_storage": storage, "fp16_prompt_products": bool(prompt_count), "absolute_error_limit": tolerance, "logits": len(actual), "max_absolute_error": float(error.max()),
                  "rms_error": float(np.sqrt(np.mean(error * error))),
                  "reference_argmax": int(expected.argmax()), "sass_argmax": int(actual.argmax()),
                  "reference_top5": expected.argsort()[-5:][::-1].tolist(),
                  "sass_top5": actual.argsort()[-5:][::-1].tolist()}
        results.append(result)
        print(json.dumps(result, indent=2))
        assert result["reference_argmax"] == result["sass_argmax"], "greedy token differs"
        assert result["max_absolute_error"] < tolerance, "logit error exceeds tolerance"
    Path(args.output).write_text(json.dumps(results, indent=2) + "\n")



if __name__ == "__main__":
    main()
