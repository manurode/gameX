"""Bake mitered wall junction sprites.

Each arm is a full-length half of wall_se/wall_sw, clipped to a ~50° wedge
around its axis so L/T/+ joins don't form an X of overlapping roofs.
"""

from __future__ import annotations

import hashlib
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(r"C:\Repos\gameX")
OUT_DIR = ROOT / "assets" / "tilesets" / "mediterranean" / "Buildings"

SE_POS, SE_NEG, SW_POS, SW_NEG = 1, 2, 4, 8

IMPORT_TEMPLATE = """[remap]

importer="texture"
type="CompressedTexture2D"
uid="uid://{uid}"
path="res://.godot/imported/{name}-{digest}.ctex"
metadata={{
"vram_texture": false
}}

[deps]

source_file="{source}"
dest_files=["res://.godot/imported/{name}-{digest}.ctex"]

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=false
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=1
"""


def ensure_import(png: Path) -> None:
	imp = Path(str(png) + ".import")
	rel = "res://" + png.relative_to(ROOT).as_posix()
	digest = hashlib.md5(rel.encode()).hexdigest()
	uid = "d" + digest[:13]
	imp.write_text(
		IMPORT_TEMPLATE.format(uid=uid, name=png.name, digest=digest, source=rel),
		encoding="utf-8",
	)


def load_rgba(path: Path) -> np.ndarray:
	return np.asarray(Image.open(path).convert("RGBA"), dtype=np.float32)


def over(a: np.ndarray, b: np.ndarray) -> np.ndarray:
	aa = a[..., 3:4] / 255.0
	ba = b[..., 3:4] / 255.0
	oa = ba + aa * (1.0 - ba)
	rgb = np.zeros_like(a[..., :3])
	np.divide(
		b[..., :3] * ba + a[..., :3] * aa * (1.0 - ba),
		np.maximum(oa, 1e-6),
		out=rgb,
	)
	return np.concatenate([rgb, oa * 255.0], axis=-1)


def mitered_arm(
	src: np.ndarray,
	axis: tuple[float, float],
	positive: bool,
	center: tuple[float, float],
	half_angle_deg: float = 48.0,
	pillar_r: float = 18.0,
) -> np.ndarray:
	size = src.shape[0]
	yy, xx = np.mgrid[0:size, 0:size]
	ax = np.array(axis, dtype=np.float32)
	ax /= np.linalg.norm(ax)
	if not positive:
		ax = -ax
	dx = xx.astype(np.float32) - center[0]
	dy = yy.astype(np.float32) - center[1]
	dist = np.sqrt(dx * dx + dy * dy) + 1e-3
	along = dx * ax[0] + dy * ax[1]
	cosang = along / dist

	# Full-length arm: half-plane along the axis + angular wedge (miter).
	half = np.clip((along + 5.0) / 6.0, 0.0, 1.0)
	cos_lim = float(np.cos(np.deg2rad(half_angle_deg)))
	wedge = np.clip((cosang - cos_lim) / 0.12, 0.0, 1.0)
	pillar = np.clip((pillar_r - dist) / 3.5, 0.0, 1.0)
	mask = np.maximum(pillar, half * wedge)

	out = src.copy()
	out[..., 3] *= mask
	return out


def phase_suffix(phase: str) -> str:
	return "" if phase == "complete" else f"_{phase}"


def process_phase(phase: str) -> int:
	se_path = OUT_DIR / f"wall_se{phase_suffix(phase)}.png"
	sw_path = OUT_DIR / f"wall_sw{phase_suffix(phase)}.png"
	if not se_path.exists() or not sw_path.exists():
		print("skip", phase)
		return 0
	se = load_rgba(se_path)
	sw = load_rgba(sw_path)
	# Shared join slightly between the two painted masses.
	join = (128.0, 160.0)
	se_axis = (2.0, -1.0)
	sw_axis = (2.0, 1.0)

	bit_arm = {
		SE_POS: mitered_arm(se, se_axis, True, join),
		SE_NEG: mitered_arm(se, se_axis, False, join),
		SW_POS: mitered_arm(sw, sw_axis, True, join),
		SW_NEG: mitered_arm(sw, sw_axis, False, join),
	}

	# Export individual arms for debugging / future dual-sprite use.
	names = {SE_POS: "se_pos", SE_NEG: "se_neg", SW_POS: "sw_pos", SW_NEG: "sw_neg"}
	count = 0
	for bit, name in names.items():
		path = OUT_DIR / f"wall_arm_{name}{phase_suffix(phase)}.png"
		Image.fromarray(np.clip(bit_arm[bit], 0, 255).astype(np.uint8), "RGBA").save(path)
		ensure_import(path)
		count += 1

	for mask in range(1, 16):
		if mask in (SE_POS | SE_NEG, SW_POS | SW_NEG):
			continue
		layers = [bit_arm[b] for b in (SE_NEG, SW_POS, SE_POS, SW_NEG) if mask & b]
		if not layers:
			continue

		def y_key(a: np.ndarray) -> float:
			m = a[..., 3] > 24
			if not np.any(m):
				return 0.0
			ys, _ = np.where(m)
			return float(ys.mean())

		layers = sorted(layers, key=y_key)
		out = layers[0]
		for layer in layers[1:]:
			out = over(out, layer)

		path = OUT_DIR / f"wall_junc_{mask:02d}{phase_suffix(phase)}.png"
		Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA").save(path)
		ensure_import(path)
		print("wrote", path.name)
		count += 1
	return count


def main() -> None:
	total = 0
	for phase in ("complete", "plot", "construction", "damaged"):
		total += process_phase(phase)
	print(f"done: {total}")


if __name__ == "__main__":
	main()
