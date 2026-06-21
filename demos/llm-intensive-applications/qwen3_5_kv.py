"""Qwen3.5-0.8B with KV cache, plus a multi-key cache store extension.

Everything from `FeedForward` through `Qwen3_5Tokenizer` is ported with no
functional changes from Sebastian Raschka's
ch05/16_qwen3.5/qwen3.5-plus-kv-cache.ipynb in:

    https://github.com/rasbt/LLMs-from-scratch
    License: Apache License 2.0 — see demos/LLMs-from-scratch/LICENSE.txt

`Qwen3_5GatedDeltaNet` (the linear-attention layer) is imported directly from
that checkout's qwen3_5_transformers.py, which is itself copied from Hugging
Face Transformers (Apache 2.0).

`PromptCacheStore`, at the bottom, is the new piece for this demo: Raschka's
`KVCache` holds exactly one conversation's state. This wraps many of them
behind a dict keyed by SKU, so independent product-review prefixes can be
warmed, read, updated, and deleted like rows in a key-value store — CREATE,
READ, UPDATE, DELETE — with real latency and memory measured on each.
"""
import re
import sys
import time
from dataclasses import dataclass
from pathlib import Path

import torch
import torch.nn as nn
import torch.nn.functional as F
from tokenizers import Tokenizer

_RASCHKA_QWEN35_DIR = Path(__file__).resolve().parents[1] / "LLMs-from-scratch" / "ch05" / "16_qwen3.5"
if str(_RASCHKA_QWEN35_DIR) not in sys.path:
    sys.path.insert(0, str(_RASCHKA_QWEN35_DIR))

from qwen3_5_transformers import Qwen3_5GatedDeltaNet  # noqa: E402

# Enable the flash-linear-attention CUDA fast path — Raschka's standalone copy
# leaves is_fast_path_available=False by default (no import attempt). Patch the
# module before the class is instantiated so __init__ picks up the real kernels.
# Pre-load libcudart.so.12 for causal_conv1d, which requires it at import time.
try:
    import ctypes
    try:
        ctypes.CDLL("libcudart.so.12")
    except OSError:
        for _libdir in (
            "/home/m/Desktop/.lmstudio/extensions/backends/vendor/linux-llama-cuda12-vendor-v1",
            "/home/m/.cache/uv/archive-v0/g0k_usdvCOelXOIX/nvidia/cuda_runtime/lib",
        ):
            try:
                ctypes.CDLL(f"{_libdir}/libcudart.so.12")
                break
            except OSError:
                continue

    from causal_conv1d import causal_conv1d_fn as _cc1d_fn
    from causal_conv1d import causal_conv1d_update as _cc1d_upd
    from fla.ops.gated_delta_rule import chunk_gated_delta_rule as _cgdr
    from fla.ops.gated_delta_rule import fused_recurrent_gated_delta_rule as _frgdr

    import qwen3_5_transformers as _q35t
    _q35t.causal_conv1d_fn = _cc1d_fn
    _q35t.causal_conv1d_update = _cc1d_upd
    _q35t.chunk_gated_delta_rule = _cgdr
    _q35t.fused_recurrent_gated_delta_rule = _frgdr
    _q35t.is_fast_path_available = True
    print(">>> flash-linear-attention fast path enabled")
except ImportError:
    pass

# ---------------------------------------------------------------------------
# Ported from qwen3.5-plus-kv-cache.ipynb
# ---------------------------------------------------------------------------


class FeedForward(nn.Module):
    def __init__(self, cfg):
        super().__init__()
        self.fc1 = nn.Linear(cfg["emb_dim"], cfg["hidden_dim"], dtype=cfg["dtype"], bias=False)
        self.fc2 = nn.Linear(cfg["emb_dim"], cfg["hidden_dim"], dtype=cfg["dtype"], bias=False)
        self.fc3 = nn.Linear(cfg["hidden_dim"], cfg["emb_dim"], dtype=cfg["dtype"], bias=False)

    def forward(self, x):
        x_fc1 = self.fc1(x)
        x_fc2 = self.fc2(x)
        x = nn.functional.silu(x_fc1) * x_fc2
        return self.fc3(x)


class RMSNorm(nn.Module):
    def __init__(self, emb_dim, eps=1e-6):
        super().__init__()
        self.eps = eps
        # Qwen3.5 uses (1 + weight) scaling with zero init
        self.weight = nn.Parameter(torch.zeros(emb_dim))

    def _norm(self, x):
        return x * torch.rsqrt(x.pow(2).mean(dim=-1, keepdim=True) + self.eps)

    def forward(self, x):
        x_norm = self._norm(x.float())
        x_norm = x_norm * (1.0 + self.weight.float())
        return x_norm.to(dtype=x.dtype)


def compute_rope_params(
    head_dim,
    theta_base=10_000,
    context_length=4096,
    partial_rotary_factor=1.0,
    dtype=torch.float32,
):
    assert head_dim % 2 == 0, "Embedding dimension must be even"

    rotary_dim = int(head_dim * partial_rotary_factor)
    rotary_dim = max(2, rotary_dim - (rotary_dim % 2))

    inv_freq = 1.0 / (
        theta_base ** (
            torch.arange(0, rotary_dim, 2, dtype=dtype)[: (rotary_dim // 2)].float() / rotary_dim
        )
    )

    positions = torch.arange(context_length, dtype=dtype)
    angles = positions.unsqueeze(1) * inv_freq.unsqueeze(0)
    angles = torch.cat([angles, angles], dim=1)

    cos = torch.cos(angles)
    sin = torch.sin(angles)

    return cos, sin


def apply_rope(x, cos, sin, offset=0):
    _, _, seq_len, head_dim = x.shape
    assert head_dim % 2 == 0, "Head dimension must be even"

    rot_dim = cos.shape[-1]
    if rot_dim > head_dim:
        raise ValueError(f"RoPE dim {rot_dim} cannot exceed head_dim {head_dim}.")

    x_rot = x[..., :rot_dim]
    x_pass = x[..., rot_dim:]

    x1 = x_rot[..., : rot_dim // 2]
    x2 = x_rot[..., rot_dim // 2:]

    cos = cos[offset:offset + seq_len, :].unsqueeze(0).unsqueeze(0)
    sin = sin[offset:offset + seq_len, :].unsqueeze(0).unsqueeze(0)

    rotated = torch.cat((-x2, x1), dim=-1)
    x_rotated = (x_rot * cos) + (rotated * sin)

    x_out = torch.cat([x_rotated, x_pass], dim=-1)
    return x_out.to(dtype=x.dtype)


class GroupedQueryAttention(nn.Module):
    def __init__(
        self, d_in, num_heads, num_kv_groups, head_dim=None, qk_norm=False, dtype=None
    ):
        super().__init__()
        assert num_heads % num_kv_groups == 0, "num_heads must be divisible by num_kv_groups"

        self.num_heads = num_heads
        self.num_kv_groups = num_kv_groups
        self.group_size = num_heads // num_kv_groups

        if head_dim is None:
            assert d_in % num_heads == 0, "`d_in` must be divisible by `num_heads` if `head_dim` is not set"
            head_dim = d_in // num_heads

        self.head_dim = head_dim
        self.d_out = num_heads * head_dim

        # Qwen3.5 full-attention uses a gated Q projection (2x output dim)
        self.W_query = nn.Linear(d_in, self.d_out * 2, bias=False, dtype=dtype)
        self.W_key = nn.Linear(d_in, num_kv_groups * head_dim, bias=False, dtype=dtype)
        self.W_value = nn.Linear(d_in, num_kv_groups * head_dim, bias=False, dtype=dtype)

        self.out_proj = nn.Linear(self.d_out, d_in, bias=False, dtype=dtype)

        if qk_norm:
            self.q_norm = RMSNorm(head_dim, eps=1e-6)
            self.k_norm = RMSNorm(head_dim, eps=1e-6)
        else:
            self.q_norm = self.k_norm = None

    def forward(self, x, mask, cos, sin, start_pos=0, cache=None):
        b, num_tokens, _ = x.shape

        q_and_gate = self.W_query(x)
        q_and_gate = q_and_gate.view(b, num_tokens, self.num_heads, self.head_dim * 2)
        queries, gate = torch.chunk(q_and_gate, 2, dim=-1)
        gate = gate.reshape(b, num_tokens, self.d_out)

        keys = self.W_key(x)
        values = self.W_value(x)

        queries = queries.transpose(1, 2)
        keys_new = keys.view(b, num_tokens, self.num_kv_groups, self.head_dim).transpose(1, 2)
        values_new = values.view(b, num_tokens, self.num_kv_groups, self.head_dim).transpose(1, 2)

        if self.q_norm:
            queries = self.q_norm(queries)
        if self.k_norm:
            keys_new = self.k_norm(keys_new)

        prev_len = 0
        if cache is not None:
            prev_k, prev_v = cache
            if prev_k is not None:
                prev_len = prev_k.size(2)
                keys_cat_raw = torch.cat([prev_k, keys_new], dim=2)
                values_cat_raw = torch.cat([prev_v, values_new], dim=2)
            else:
                keys_cat_raw = keys_new
                values_cat_raw = values_new
        else:
            keys_cat_raw = keys_new
            values_cat_raw = values_new

        queries = apply_rope(queries, cos, sin, offset=start_pos)
        keys = apply_rope(keys_cat_raw, cos, sin, offset=start_pos - prev_len)

        keys = keys.repeat_interleave(self.group_size, dim=1)
        values = values_cat_raw.repeat_interleave(self.group_size, dim=1)

        if cache is not None and cache[0] is not None:
            next_cache = (
                torch.cat([cache[0], keys_new], dim=2),
                torch.cat([cache[1], values_new], dim=2),
            )
        else:
            next_cache = (keys_new, values_new)

        context = F.scaled_dot_product_attention(
            queries, keys, values,
            attn_mask=None,
            dropout_p=0.0,
            is_causal=True,
            scale=self.head_dim ** -0.5,
        ).transpose(1, 2).reshape(b, num_tokens, self.d_out)

        # Qwen3.5 full-attention uses a gated Q projection
        context = context * torch.sigmoid(gate)
        out = self.out_proj(context)
        return out, next_cache


# Just a mapping for the different naming convention in Hugging Face transformers
class _Qwen3_5ConfigAdapter:
    def __init__(self, cfg):
        self.hidden_size = cfg["emb_dim"]
        self.linear_num_value_heads = cfg["linear_num_value_heads"]
        self.linear_num_key_heads = cfg["linear_num_key_heads"]
        self.linear_key_head_dim = cfg["linear_key_head_dim"]
        self.linear_value_head_dim = cfg["linear_value_head_dim"]
        self.linear_conv_kernel_dim = cfg["linear_conv_kernel_dim"]
        self.hidden_act = "silu"
        self.rms_norm_eps = cfg.get("rms_norm_eps", 1e-6)
        self.dtype = cfg.get("dtype", None)


class TransformerBlock(nn.Module):
    def __init__(self, cfg, layer_type, layer_idx):
        super().__init__()
        self.layer_type = layer_type

        if layer_type == "full_attention":
            self.token_mixer = GroupedQueryAttention(
                d_in=cfg["emb_dim"],
                num_heads=cfg["n_heads"],
                head_dim=cfg["head_dim"],
                num_kv_groups=cfg["n_kv_groups"],
                qk_norm=cfg["qk_norm"],
                dtype=cfg["dtype"],
            )
        elif layer_type == "linear_attention":
            self.token_mixer = Qwen3_5GatedDeltaNet(_Qwen3_5ConfigAdapter(cfg), layer_idx)
        else:
            raise ValueError(f"Unsupported layer type: {layer_type}")

        self.ff = FeedForward(cfg)
        self.norm1 = RMSNorm(cfg["emb_dim"], eps=cfg.get("rms_norm_eps", 1e-6))
        self.norm2 = RMSNorm(cfg["emb_dim"], eps=cfg.get("rms_norm_eps", 1e-6))

    def forward(self, x, mask, cos, sin, start_pos=0, cache=None, linear_cache=None, cache_position=None):
        shortcut = x
        x = self.norm1(x)

        if self.layer_type == "full_attention":
            x, next_cache = self.token_mixer(
                x,
                mask,
                cos,
                sin,
                start_pos=start_pos,
                cache=cache,
            )
        else:
            x = self.token_mixer(
                x,
                cache_params=linear_cache,
                cache_position=cache_position,
            )
            next_cache = None

        x = x + shortcut

        shortcut = x
        x = self.norm2(x)
        x = self.ff(x)
        x = x + shortcut

        return x, next_cache


class Qwen3_5Model(nn.Module):
    def __init__(self, cfg):
        super().__init__()

        self.tok_emb = nn.Embedding(cfg["vocab_size"], cfg["emb_dim"], dtype=cfg["dtype"])

        layer_types = cfg.get("layer_types", ["full_attention"] * cfg["n_layers"])
        if len(layer_types) != cfg["n_layers"]:
            raise ValueError("len(layer_types) must equal n_layers")

        self.trf_blocks = nn.ModuleList(
            [TransformerBlock(cfg, layer_type, idx) for idx, layer_type in enumerate(layer_types)]
        )

        self.final_norm = RMSNorm(cfg["emb_dim"], eps=cfg.get("rms_norm_eps", 1e-6))
        self.out_head = nn.Linear(cfg["emb_dim"], cfg["vocab_size"], bias=False, dtype=cfg["dtype"])

        head_dim = cfg["emb_dim"] // cfg["n_heads"] if cfg["head_dim"] is None else cfg["head_dim"]
        cos, sin = compute_rope_params(
            head_dim=head_dim,
            theta_base=cfg["rope_base"],
            context_length=cfg["context_length"],
            partial_rotary_factor=cfg.get("partial_rotary_factor", 1.0),
            dtype=torch.float32,
        )
        self.register_buffer("cos", cos, persistent=False)
        self.register_buffer("sin", sin, persistent=False)
        self.cfg = cfg
        self.current_pos = 0

    def create_mask(self, cur_len, device, pos_start=0, pos_end=None):
        if pos_end is None:
            pos_end = cur_len

        ones = torch.ones((pos_end, pos_end), device=device, dtype=torch.bool)
        mask_full = torch.triu(ones, diagonal=1)
        row_slice = slice(pos_start, pos_end)
        mask = mask_full[row_slice, :pos_end][None, None, :, :]
        return mask

    def forward(self, in_idx, cache=None):
        x = self.tok_emb(in_idx)

        num_tokens = x.shape[1]
        if cache is not None:
            pos_start = self.current_pos
            pos_end = pos_start + num_tokens
            self.current_pos = pos_end
            mask = self.create_mask(
                cur_len=num_tokens,
                device=x.device,
                pos_start=pos_start,
                pos_end=pos_end,
            )
            cache_position = torch.arange(pos_start, pos_end, device=x.device, dtype=torch.long)
        else:
            pos_start = 0
            mask = self.create_mask(
                cur_len=num_tokens,
                device=x.device,
                pos_start=0,
                pos_end=num_tokens,
            )
            cache_position = None

        for i, block in enumerate(self.trf_blocks):
            blk_cache = cache.get(i) if cache is not None else None
            x, new_blk_cache = block(
                x,
                mask=mask,
                cos=self.cos,
                sin=self.sin,
                start_pos=pos_start,
                cache=blk_cache,
                linear_cache=cache.linear_cache if cache is not None else None,
                cache_position=cache_position,
            )
            if cache is not None and new_blk_cache is not None:
                cache.update(i, new_blk_cache)

        if cache is not None:
            cache.linear_cache.has_previous_state = True

        x = self.final_norm(x)
        logits = self.out_head(x.to(self.cfg["dtype"]))
        return logits

    def reset_kv_cache(self):
        self.current_pos = 0


class Qwen3_5LinearAttentionCache:
    def __init__(self, n_layers):
        self.conv_states = [None] * n_layers
        self.recurrent_states = [None] * n_layers
        self.has_previous_state = False

    def reset(self):
        for i in range(len(self.conv_states)):
            self.conv_states[i] = None
            self.recurrent_states[i] = None
        self.has_previous_state = False


class KVCache:
    def __init__(self, n_layers):
        self.cache = [None] * n_layers
        self.linear_cache = Qwen3_5LinearAttentionCache(n_layers)

    def get(self, layer_idx):
        return self.cache[layer_idx]

    def update(self, layer_idx, value):
        self.cache[layer_idx] = value

    def get_all(self):
        return self.cache

    def reset(self):
        for i in range(len(self.cache)):
            self.cache[i] = None
        self.linear_cache.reset()


QWEN3_5_CONFIG = {
    "vocab_size": 248_320,
    "context_length": 262_144,
    "emb_dim": 1_024,
    "n_heads": 8,
    "n_layers": 24,
    "hidden_dim": 3_584,
    "head_dim": 256,
    "qk_norm": True,
    "n_kv_groups": 2,
    "rope_base": 10_000_000.0,
    "partial_rotary_factor": 0.25,
    "rms_norm_eps": 1e-6,
    "linear_conv_kernel_dim": 4,
    "linear_key_head_dim": 128,
    "linear_value_head_dim": 128,
    "linear_num_key_heads": 16,
    "linear_num_value_heads": 16,
    "dtype": torch.bfloat16,
    "layer_types": [
        "linear_attention", "linear_attention", "linear_attention", "full_attention",
        "linear_attention", "linear_attention", "linear_attention", "full_attention",
        "linear_attention", "linear_attention", "linear_attention", "full_attention",
        "linear_attention", "linear_attention", "linear_attention", "full_attention",
        "linear_attention", "linear_attention", "linear_attention", "full_attention",
        "linear_attention", "linear_attention", "linear_attention", "full_attention",
    ],
}


def load_weights_into_qwen3_5(model, param_config, params):
    def assign(left, right, tensor_name="unknown"):
        if left.shape != right.shape:
            raise ValueError(
                f"Shape mismatch in tensor '{tensor_name}'. Left: {left.shape}, Right: {right.shape}"
            )

        with torch.no_grad():
            if isinstance(right, torch.Tensor):
                left.copy_(right)
            else:
                left.copy_(torch.as_tensor(right, dtype=left.dtype, device=left.device))

        return left

    if "model.embed_tokens.weight" in params:
        model_prefix = "model"
    elif "model.language_model.embed_tokens.weight" in params:
        model_prefix = "model.language_model"
    else:
        raise KeyError("Could not find embed token weights in checkpoint.")

    def pkey(suffix):
        return f"{model_prefix}.{suffix}"

    model.tok_emb.weight = assign(
        model.tok_emb.weight,
        params[pkey("embed_tokens.weight")],
        pkey("embed_tokens.weight"),
    )

    n_layers = param_config["n_layers"]
    layer_types = param_config.get("layer_types", ["full_attention"] * n_layers)

    for l in range(n_layers):
        block = model.trf_blocks[l]
        layer_type = layer_types[l]

        if layer_type == "full_attention":
            att = block.token_mixer
            att.W_query.weight = assign(
                att.W_query.weight,
                params[pkey(f"layers.{l}.self_attn.q_proj.weight")],
                pkey(f"layers.{l}.self_attn.q_proj.weight"),
            )
            att.W_key.weight = assign(
                att.W_key.weight,
                params[pkey(f"layers.{l}.self_attn.k_proj.weight")],
                pkey(f"layers.{l}.self_attn.k_proj.weight"),
            )
            att.W_value.weight = assign(
                att.W_value.weight,
                params[pkey(f"layers.{l}.self_attn.v_proj.weight")],
                pkey(f"layers.{l}.self_attn.v_proj.weight"),
            )
            att.out_proj.weight = assign(
                att.out_proj.weight,
                params[pkey(f"layers.{l}.self_attn.o_proj.weight")],
                pkey(f"layers.{l}.self_attn.o_proj.weight"),
            )
            if hasattr(att, "q_norm") and att.q_norm is not None:
                att.q_norm.weight = assign(
                    att.q_norm.weight,
                    params[pkey(f"layers.{l}.self_attn.q_norm.weight")],
                    pkey(f"layers.{l}.self_attn.q_norm.weight"),
                )
            if hasattr(att, "k_norm") and att.k_norm is not None:
                att.k_norm.weight = assign(
                    att.k_norm.weight,
                    params[pkey(f"layers.{l}.self_attn.k_norm.weight")],
                    pkey(f"layers.{l}.self_attn.k_norm.weight"),
                )

        elif layer_type == "linear_attention":
            lat = block.token_mixer
            lat.dt_bias = assign(
                lat.dt_bias,
                params[pkey(f"layers.{l}.linear_attn.dt_bias")],
                pkey(f"layers.{l}.linear_attn.dt_bias"),
            )
            lat.A_log = assign(
                lat.A_log,
                params[pkey(f"layers.{l}.linear_attn.A_log")],
                pkey(f"layers.{l}.linear_attn.A_log"),
            )
            lat.conv1d.weight = assign(
                lat.conv1d.weight,
                params[pkey(f"layers.{l}.linear_attn.conv1d.weight")],
                pkey(f"layers.{l}.linear_attn.conv1d.weight"),
            )
            lat.norm.weight = assign(
                lat.norm.weight,
                params[pkey(f"layers.{l}.linear_attn.norm.weight")],
                pkey(f"layers.{l}.linear_attn.norm.weight"),
            )
            lat.out_proj.weight = assign(
                lat.out_proj.weight,
                params[pkey(f"layers.{l}.linear_attn.out_proj.weight")],
                pkey(f"layers.{l}.linear_attn.out_proj.weight"),
            )
            lat.in_proj_qkv.weight = assign(
                lat.in_proj_qkv.weight,
                params[pkey(f"layers.{l}.linear_attn.in_proj_qkv.weight")],
                pkey(f"layers.{l}.linear_attn.in_proj_qkv.weight"),
            )
            lat.in_proj_z.weight = assign(
                lat.in_proj_z.weight,
                params[pkey(f"layers.{l}.linear_attn.in_proj_z.weight")],
                pkey(f"layers.{l}.linear_attn.in_proj_z.weight"),
            )
            lat.in_proj_b.weight = assign(
                lat.in_proj_b.weight,
                params[pkey(f"layers.{l}.linear_attn.in_proj_b.weight")],
                pkey(f"layers.{l}.linear_attn.in_proj_b.weight"),
            )
            lat.in_proj_a.weight = assign(
                lat.in_proj_a.weight,
                params[pkey(f"layers.{l}.linear_attn.in_proj_a.weight")],
                pkey(f"layers.{l}.linear_attn.in_proj_a.weight"),
            )

        else:
            raise ValueError(f"Unsupported layer type: {layer_type}")

        block.norm1.weight = assign(
            block.norm1.weight,
            params[pkey(f"layers.{l}.input_layernorm.weight")],
            pkey(f"layers.{l}.input_layernorm.weight"),
        )

        block.ff.fc1.weight = assign(
            block.ff.fc1.weight,
            params[pkey(f"layers.{l}.mlp.gate_proj.weight")],
            pkey(f"layers.{l}.mlp.gate_proj.weight"),
        )
        block.ff.fc2.weight = assign(
            block.ff.fc2.weight,
            params[pkey(f"layers.{l}.mlp.up_proj.weight")],
            pkey(f"layers.{l}.mlp.up_proj.weight"),
        )
        block.ff.fc3.weight = assign(
            block.ff.fc3.weight,
            params[pkey(f"layers.{l}.mlp.down_proj.weight")],
            pkey(f"layers.{l}.mlp.down_proj.weight"),
        )
        block.norm2.weight = assign(
            block.norm2.weight,
            params[pkey(f"layers.{l}.post_attention_layernorm.weight")],
            pkey(f"layers.{l}.post_attention_layernorm.weight"),
        )

    model.final_norm.weight = assign(
        model.final_norm.weight,
        params[pkey("norm.weight")],
        pkey("norm.weight"),
    )

    if "lm_head.weight" in params:
        model.out_head.weight = assign(model.out_head.weight, params["lm_head.weight"], "lm_head.weight")
    elif pkey("lm_head.weight") in params:
        model.out_head.weight = assign(model.out_head.weight, params[pkey("lm_head.weight")], pkey("lm_head.weight"))
    else:
        model.out_head.weight = model.tok_emb.weight
        print("Model uses weight tying.")


class Qwen3_5Tokenizer:
    _SPECIALS = [
        "<|endoftext|>",
        "<|im_start|>", "<|im_end|>",
        "<|object_ref_start|>", "<|object_ref_end|>",
        "<|box_start|>", "<|box_end|>",
        "<|quad_start|>", "<|quad_end|>",
        "<|vision_start|>", "<|vision_end|>",
        "<|vision_pad|>", "<|image_pad|>", "<|video_pad|>",
        "<think>", "</think>",
    ]
    _SPLIT_RE = re.compile(r"(<\|[^>]+?\|>|<think>|</think>)")

    def __init__(
        self,
        tokenizer_file_path="tokenizer.json",
        repo_id=None,
        apply_chat_template=True,
        add_generation_prompt=False,
        add_thinking=False,
    ):
        self.apply_chat_template = apply_chat_template
        self.add_generation_prompt = add_generation_prompt
        self.add_thinking = add_thinking

        tok_file = Path(tokenizer_file_path)
        self._tok = Tokenizer.from_file(str(tok_file))
        self._special_to_id = {}
        for t in self._SPECIALS:
            tid = self._tok.token_to_id(t)
            if tid is not None:
                self._special_to_id[t] = tid

        self.pad_token_id = self._special_to_id["<|endoftext|>"]
        self.eos_token_id = self.pad_token_id

        if repo_id and "Base" not in repo_id:
            eos_token = "<|im_end|>"
        else:
            eos_token = "<|endoftext|>"
        if eos_token in self._special_to_id:
            self.eos_token_id = self._special_to_id[eos_token]

    def encode(self, text, chat_wrapped=None):
        if chat_wrapped is None:
            chat_wrapped = self.apply_chat_template

        stripped = text.strip()
        if stripped in self._special_to_id and "\n" not in stripped:
            return [self._special_to_id[stripped]]

        if chat_wrapped:
            text = self._wrap_chat(text)

        ids = []
        for part in filter(None, self._SPLIT_RE.split(text)):
            if part in self._special_to_id:
                ids.append(self._special_to_id[part])
            else:
                ids.extend(self._tok.encode(part).ids)
        return ids

    def decode(self, ids):
        return self._tok.decode(ids, skip_special_tokens=False)

    def _wrap_chat(self, user_msg):
        s = f"<|im_start|>user\n{user_msg}<|im_end|>\n"
        if self.add_generation_prompt:
            s += "<|im_start|>assistant\n"
            if self.add_thinking:
                s += "<think>\n"
            else:
                s += "<think>\n\n</think>\n\n"
        return s


# ---------------------------------------------------------------------------
# New: a named, multi-entry cache store on top of Raschka's single-conversation
# KVCache/Qwen3_5LinearAttentionCache. This is the hash map of per-item
# contexts — CREATE/READ/UPDATE/DELETE, with real latency and byte size.
# ---------------------------------------------------------------------------


@dataclass
class CacheEntry:
    kv: KVCache
    current_pos: int
    prefix_tokens: int


class PromptCacheStore:
    """dict[key -> cached prefix state], backed by a single live model.

    `model.current_pos` is process-wide state Raschka's code keeps on the
    model instance itself (needed for RoPE offsets and the causal mask). Since
    many keys share one model here, every call saves/restores it around the
    forward pass -- the context switch a multi-tenant cache always pays,
    whether it's a dict of tensors or a dict of database connections.
    """

    def __init__(self, model, tokenizer, device):
        self.model = model
        self.tokenizer = tokenizer
        self.device = device
        self._store: dict[str, CacheEntry] = {}
        self.metrics: list[dict] = []

    def _ids_tensor(self, ids):
        return torch.tensor(ids, device=self.device).unsqueeze(0)

    def warm(self, key, prefix_text):
        """CREATE / UPDATE: cold-build the cache for `key` from `prefix_text`."""
        ids = self.tokenizer.encode(prefix_text, chat_wrapped=False)
        kv = KVCache(n_layers=self.model.cfg["n_layers"])
        self.model.current_pos = 0

        t0 = time.perf_counter()
        with torch.no_grad():
            self.model(self._ids_tensor(ids), cache=kv)
        elapsed = time.perf_counter() - t0

        self._store[key] = CacheEntry(kv=kv, current_pos=self.model.current_pos, prefix_tokens=len(ids))
        self.metrics.append({"op": "WARM", "key": key, "latency_s": elapsed, "tokens": len(ids)})
        return elapsed

    def ask(self, key, question_text, max_new_tokens=30):
        """READ: resume `key`'s cached state, decode a response to `question_text`."""
        entry = self._store[key]
        self.model.current_pos = entry.current_pos

        question_ids = self.tokenizer.encode(question_text, chat_wrapped=False)
        generated = []

        t0 = time.perf_counter()
        with torch.no_grad():
            logits = self.model(self._ids_tensor(question_ids), cache=entry.kv)
            for _ in range(max_new_tokens):
                next_token = torch.argmax(logits[:, -1], dim=-1, keepdim=True)
                if torch.all(next_token == self.tokenizer.eos_token_id):
                    break
                generated.append(next_token.item())
                logits = self.model(next_token, cache=entry.kv)
        elapsed = time.perf_counter() - t0

        entry.current_pos = self.model.current_pos
        text = self.tokenizer.decode(generated)
        self.metrics.append({
            "op": "READ", "key": key, "latency_s": elapsed,
            "tokens": len(question_ids) + len(generated),
        })
        return text, elapsed

    def delete(self, key):
        """DELETE: drop the entry. The next warm() pays full recompute -- not this call."""
        self._store.pop(key, None)
        self.metrics.append({"op": "DELETE", "key": key, "latency_s": 0.0, "tokens": 0})

    def memory_report(self, key):
        """Bytes held for `key`, split by attention type.

        Full-attention KV grows with prefix length (it's a real per-token
        cache). Linear-attention (gated delta net) state does not -- it's a
        fixed-size recurrent state plus a small conv buffer, the entire VRAM
        trick, made visible as two numbers instead of one.
        """
        entry = self._store[key]
        full_attention_bytes = 0
        for layer_cache in entry.kv.cache:
            if layer_cache is None:
                continue
            k, v = layer_cache
            full_attention_bytes += k.numel() * k.element_size() + v.numel() * v.element_size()

        linear_attention_bytes = 0
        lc = entry.kv.linear_cache
        for conv_state, recurrent_state in zip(lc.conv_states, lc.recurrent_states):
            if conv_state is not None:
                linear_attention_bytes += conv_state.numel() * conv_state.element_size()
            if recurrent_state is not None:
                linear_attention_bytes += recurrent_state.numel() * recurrent_state.element_size()

        return {
            "full_attention_kv_bytes": full_attention_bytes,
            "linear_attention_state_bytes": linear_attention_bytes,
            "prefix_tokens": entry.prefix_tokens,
        }
