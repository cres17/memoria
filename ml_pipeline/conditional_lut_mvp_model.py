"""Stable, exportable module definitions for the conditional 3D LUT MVP.

Keep model classes outside numbered experiment runners: TorchScript records a
class's module path in an artifact and cannot reload a path segment that starts
with a digit.
"""

from __future__ import annotations

import importlib

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F


v2 = importlib.import_module("11_train_basis_v2")

CUBE_DIM = 17
STYLE_DIM = 128
HUE_ANCHOR_COUNT = 6
SEMANTIC_CLASSES = 6


def identity_lut(dim: int) -> torch.Tensor:
    values = torch.linspace(0.0, 1.0, dim, dtype=torch.float32)
    red, green, blue = torch.meshgrid(values, values, values, indexing="ij")
    return torch.stack((red, green, blue), dim=-1)


def rgb_to_hsv_numpy(rgb: np.ndarray) -> np.ndarray:
    maximum = rgb.max(axis=-1)
    minimum = rgb.min(axis=-1)
    delta = maximum - minimum
    hue = np.zeros_like(maximum)
    nonzero = delta > 1e-8
    red = (maximum == rgb[..., 0]) & nonzero
    green = (maximum == rgb[..., 1]) & nonzero
    blue = (maximum == rgb[..., 2]) & nonzero
    hue[red] = np.mod((rgb[..., 1][red] - rgb[..., 2][red]) / delta[red], 6.0)
    hue[green] = (rgb[..., 2][green] - rgb[..., 0][green]) / delta[green] + 2.0
    hue[blue] = (rgb[..., 0][blue] - rgb[..., 1][blue]) / delta[blue] + 4.0
    hue /= 6.0
    saturation = np.divide(delta, maximum, out=np.zeros_like(delta), where=maximum > 1e-8)
    return np.stack((hue, saturation, maximum), axis=-1)


class StyleEncoder(nn.Module):
    """Image encoder whose output is explicitly named Style Code, not a LUT ID."""

    def __init__(self, style_dim: int = STYLE_DIM, pretrained: bool = False):
        super().__init__()
        self.backbone, self.backbone_pretrained = v2.build_encoder(pretrained=pretrained)
        with torch.no_grad():
            feature_dim = self.backbone(torch.zeros(1, 3, v2.IMAGE_SIZE, v2.IMAGE_SIZE)).shape[-1]
        self.projector = nn.Sequential(
            nn.Linear(feature_dim, 256), nn.SiLU(), nn.LayerNorm(256), nn.Linear(256, style_dim)
        )

    def forward(self, reference: torch.Tensor) -> torch.Tensor:
        return self.projector(self.backbone(reference))


class SemanticPooledStyleEncoder(nn.Module):
    """Add only six pooled semantic probabilities; decoder capacity is unchanged."""

    def __init__(self, style_dim: int = STYLE_DIM, pretrained: bool = False):
        super().__init__()
        self.global_encoder = StyleEncoder(style_dim=style_dim, pretrained=pretrained)
        rng_state = torch.get_rng_state()
        self.semantic_projector = nn.Sequential(nn.Linear(SEMANTIC_CLASSES, 64), nn.SiLU(), nn.Linear(64, style_dim))
        self.fusion = nn.Linear(style_dim * 2, style_dim)
        nn.init.zeros_(self.fusion.weight)
        nn.init.zeros_(self.fusion.bias)
        with torch.no_grad():
            self.fusion.weight[:, :style_dim].copy_(torch.eye(style_dim))
        torch.set_rng_state(rng_state)

    def forward(self, reference: torch.Tensor, semantic_masks: torch.Tensor) -> torch.Tensor:
        if semantic_masks.ndim != 4 or semantic_masks.shape[1] != SEMANTIC_CLASSES:
            raise ValueError("semantic masks must be [B,6,H,W]")
        global_code = self.global_encoder(reference)
        pooled = semantic_masks.mean(dim=(2, 3))
        return self.fusion(torch.cat((global_code, self.semantic_projector(pooled)), dim=1))


class BoundedLUTDecoder(nn.Module):
    """Direct 17^3 LUT generator with selectable bounded output representations."""

    def __init__(self, style_dim: int = STYLE_DIM, cube_dim: int = CUBE_DIM, output_mode: str = "identity_logit", hidden_dim: int = 512):
        super().__init__()
        if output_mode not in ("identity_logit", "bounded_residual", "tone_curve", "tone_curve_hue_anchor"):
            raise ValueError(f"unsupported decoder output mode: {output_mode}")
        self.cube_dim = cube_dim
        self.output_mode = output_mode
        self.hidden_dim = hidden_dim
        self.trunk = nn.Sequential(nn.Linear(style_dim, hidden_dim), nn.SiLU(), nn.Linear(hidden_dim, hidden_dim), nn.SiLU())
        self.residual = nn.Linear(hidden_dim, cube_dim + HUE_ANCHOR_COUNT * 3 if output_mode == "tone_curve_hue_anchor" else cube_dim if output_mode == "tone_curve" else cube_dim ** 3 * 3)
        if output_mode in ("identity_logit", "tone_curve", "tone_curve_hue_anchor"):
            nn.init.zeros_(self.residual.weight)
        else:
            nn.init.normal_(self.residual.weight, mean=0.0, std=1e-3)
        nn.init.zeros_(self.residual.bias)
        identity = identity_lut(cube_dim).reshape(1, -1)
        self.register_buffer("identity", identity, persistent=False)
        self.register_buffer("identity_logit", torch.logit(identity.clamp(1e-4, 1.0 - 1e-4)))
        luminance = identity.reshape(cube_dim, cube_dim, cube_dim, 3) @ torch.tensor((0.2126, 0.7152, 0.0722), dtype=torch.float32)
        self.register_buffer("input_luminance", luminance, persistent=False)
        hsv = rgb_to_hsv_numpy(identity.reshape(cube_dim, cube_dim, cube_dim, 3).numpy())
        self.register_buffer("input_hue", torch.from_numpy(hsv[..., 0]), persistent=False)
        self.register_buffer("input_saturation", torch.from_numpy(hsv[..., 1]), persistent=False)

    def forward(self, style_code: torch.Tensor) -> torch.Tensor:
        residual = self.residual_logits(style_code)
        if self.output_mode == "identity_logit":
            output = torch.sigmoid(self.identity_logit + residual)
        elif self.output_mode == "bounded_residual":
            output = (self.identity + 0.25 * torch.tanh(residual)).clamp(0.0, 1.0)
        elif self.output_mode == "tone_curve":
            increments = F.softplus(residual) + 1e-4
            curve = torch.cumsum(increments, dim=1)
            curve = (curve - curve[:, :1]) / (curve[:, -1:] - curve[:, :1]).clamp_min(1e-6)
            output = self._tone_curve_output(style_code, curve)
        else:
            curve, anchors = self.structured_parameters(style_code)
            output = self._tone_curve_output(style_code, curve, anchors)
        return output.reshape(-1, self.cube_dim, self.cube_dim, self.cube_dim, 3)

    def _tone_curve_output(self, style_code: torch.Tensor, curve: torch.Tensor, anchors: torch.Tensor | None = None) -> torch.Tensor:
        positions = self.input_luminance.reshape(1, -1).mul(self.cube_dim - 1)
        lower = positions.floor().long().expand(style_code.shape[0], -1)
        upper = (lower + 1).clamp_max(self.cube_dim - 1)
        fraction = positions - lower[:1].to(positions.dtype)
        mapped_luminance = curve.gather(1, lower) + fraction * (curve.gather(1, upper) - curve.gather(1, lower))
        input_luminance = self.input_luminance.reshape(1, -1)
        scale = torch.where(input_luminance > 1e-6, mapped_luminance / input_luminance.clamp_min(1e-6), torch.zeros_like(mapped_luminance))
        identity = self.identity.reshape(1, self.cube_dim ** 3, 3).expand(style_code.shape[0], -1, -1)
        if anchors is None:
            return (identity * scale.unsqueeze(-1)).clamp(0.0, 1.0)
        hue_position = self.input_hue.reshape(1, -1) * HUE_ANCHOR_COUNT - 0.5
        hue_lower = hue_position.floor().long().remainder(HUE_ANCHOR_COUNT).expand(style_code.shape[0], -1)
        hue_upper = (hue_lower + 1).remainder(HUE_ANCHOR_COUNT)
        hue_fraction = hue_position - hue_lower[:1].to(hue_position.dtype)
        lower_anchor = anchors.gather(1, hue_lower.unsqueeze(-1).expand(-1, -1, 3))
        upper_anchor = anchors.gather(1, hue_upper.unsqueeze(-1).expand(-1, -1, 3))
        hue_residual = self.input_saturation.reshape(1, -1, 1) * (lower_anchor + hue_fraction.unsqueeze(-1) * (upper_anchor - lower_anchor))
        return (identity * scale.unsqueeze(-1) + hue_residual).clamp(0.0, 1.0)

    def structured_parameters(self, style_code: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor]:
        if self.output_mode != "tone_curve_hue_anchor":
            raise ValueError("structured parameters exist only for tone_curve_hue_anchor mode")
        residual = self.residual_logits(style_code)
        tone_logits = residual[:, :self.cube_dim]
        anchor_logits = residual[:, self.cube_dim:].reshape(-1, HUE_ANCHOR_COUNT, 3)
        increments = F.softplus(tone_logits) + 1e-4
        curve = torch.cumsum(increments, dim=1)
        curve = (curve - curve[:, :1]) / (curve[:, -1:] - curve[:, :1]).clamp_min(1e-6)
        return curve, 1.25 * torch.tanh(anchor_logits)

    def residual_logits(self, style_code: torch.Tensor) -> torch.Tensor:
        return self.residual(self.trunk(style_code))


class StructuredAuxiliaryHead(nn.Module):
    def __init__(self, style_dim: int = STYLE_DIM, cube_dim: int = CUBE_DIM):
        super().__init__()
        self.cube_dim = cube_dim
        self.trunk = nn.Sequential(nn.Linear(style_dim, 256), nn.SiLU(), nn.Linear(256, 256), nn.SiLU())
        self.output = nn.Linear(256, cube_dim + HUE_ANCHOR_COUNT * 3)
        nn.init.normal_(self.output.weight, mean=0.0, std=1e-3)
        nn.init.zeros_(self.output.bias)

    def forward(self, style_code: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor]:
        values = self.output(self.trunk(style_code))
        increments = F.softplus(values[:, :self.cube_dim]) + 1e-4
        curve = torch.cumsum(increments, dim=1)
        curve = (curve - curve[:, :1]) / (curve[:, -1:] - curve[:, :1]).clamp_min(1e-6)
        anchors = 1.25 * torch.tanh(values[:, self.cube_dim:].reshape(-1, HUE_ANCHOR_COUNT, 3))
        return curve, anchors


class ConditionalLUTMVP(nn.Module):
    def __init__(self, style_dim: int = STYLE_DIM, cube_dim: int = CUBE_DIM, pretrained: bool = False, decoder_output_mode: str = "identity_logit", decoder_hidden_dim: int = 512, structured_auxiliary: bool = False, semantic_pooled_features: bool = False):
        super().__init__()
        self.semantic_pooled_features = semantic_pooled_features
        self.style_encoder = SemanticPooledStyleEncoder(style_dim=style_dim, pretrained=pretrained) if semantic_pooled_features else StyleEncoder(style_dim=style_dim, pretrained=pretrained)
        self.lut_decoder = BoundedLUTDecoder(style_dim=style_dim, cube_dim=cube_dim, output_mode=decoder_output_mode, hidden_dim=decoder_hidden_dim)
        self.style_dim = style_dim
        self.cube_dim = cube_dim
        self.decoder_output_mode = decoder_output_mode
        self.decoder_hidden_dim = decoder_hidden_dim
        self.structured_auxiliary_enabled = structured_auxiliary
        if structured_auxiliary:
            self.structured_auxiliary_head = StructuredAuxiliaryHead(style_dim=style_dim, cube_dim=cube_dim)

    def forward(self, reference: torch.Tensor, semantic_masks: torch.Tensor | None = None) -> tuple[torch.Tensor, torch.Tensor]:
        if self.semantic_pooled_features:
            if semantic_masks is None:
                raise ValueError("semantic pooled model requires semantic masks")
            style_code = self.style_encoder(reference, semantic_masks)
        else:
            style_code = self.style_encoder(reference)
        return self.lut_decoder(style_code), style_code

    def structured_auxiliary_parameters(self, style_code: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor]:
        if not self.structured_auxiliary_enabled:
            raise ValueError("structured auxiliary head is not enabled")
        return self.structured_auxiliary_head(style_code)
