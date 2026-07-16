#!/usr/bin/env python3
"""Generate painterly isometric grass tiles from AI/forest ground textures.

Samples rich meadow textures into 256x128 iso diamonds. Variants are
tone-matched (same mean RGB) so mixed placement reads as continuous grass
without a flat shared edge band (those bands showed up as an olive grid).

Creates 12 floor variants + grass_press, then bakes *_field.png.
"""

from __future__ import annotations

import hashlib
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[1]
TERRAIN = ROOT / "assets" / "tilesets" / "mediterranean" / "Terrain"
REFS = ROOT / "tools" / "grass_refs"
PREVIEW = ROOT / "tools" / "seam_preview"

W, H = 256, 128
# Only neutralize a thin bevel / filter fringe — NOT a wide flat rim.
RIM = 4
EXTRUDE_PX = 1
SPECKLE_CHROMA = 45.0
# Keep loud accents a few px inside the silhouette so they aren't sheared.
ACCENT_MARGIN = 5

FLOOR_STEMS = [f"grass_{i:02d}" for i in range(12)]
PRESS_STEM = "grass_press"
ALL_STEMS = FLOOR_STEMS + [PRESS_STEM]

# Playable olive mean — matches forest Decor floors, slightly lifted.
TARGET_MEAN = np.array([92.0, 122.0, 55.0], dtype=np.float32)


def _hash_seed(stem: str, salt: int = 0) -> int:
	return int(hashlib.md5(f"{stem}:{salt}".encode()).hexdigest()[:8], 16)


def load_diamond_mask() -> np.ndarray:
	ref = np.array(Image.open(TERRAIN / "grass_a.png").convert("RGBA"))
	return ref[:, :, 3].astype(np.float32)


def load_source_textures() -> list[np.ndarray]:
	"""Prefer full-bleed meadow refs; fall back to center-crops of island arts."""
	names = [
		"ref_c.png",
		"ref_d.png",
		"ref_a_center.png",
		"ref_b_center.png",
		"ref_a.png",
		"ref_b.png",
	]
	textures: list[np.ndarray] = []
	for name in names:
		path = REFS / name
		if not path.exists():
			continue
		im = Image.open(path).convert("RGB")
		# Mild downscale keeps brush feel at tile resolution
		im = im.resize((768, 768), Image.Resampling.LANCZOS)
		textures.append(np.array(im).astype(np.float32))
		print(f"Loaded source {name} -> {im.size}")
	if not textures:
		raise FileNotFoundError(f"No grass refs in {REFS}")
	return textures


def value_noise(shape: tuple[int, int], cell: int, rng: np.random.Generator) -> np.ndarray:
	gh = shape[0] // cell + 3
	gw = shape[1] // cell + 3
	grid = rng.random((gh, gw), dtype=np.float32)
	ys = np.linspace(0, gh - 2, shape[0], dtype=np.float32)
	xs = np.linspace(0, gw - 2, shape[1], dtype=np.float32)
	y0 = np.floor(ys).astype(np.int32)
	x0 = np.floor(xs).astype(np.int32)
	fy = ys - y0
	fx = xs - x0
	fy = fy * fy * (3.0 - 2.0 * fy)
	fx = fx * fx * (3.0 - 2.0 * fx)
	n00 = grid[y0[:, None], x0[None, :]]
	n10 = grid[y0[:, None] + 1, x0[None, :]]
	n01 = grid[y0[:, None], x0[None, :] + 1]
	n11 = grid[y0[:, None] + 1, x0[None, :] + 1]
	top = n00 * (1 - fx) + n01 * fx
	bot = n10 * (1 - fx) + n11 * fx
	return top * (1 - fy[:, None]) + bot * fy[:, None]


def sample_patch(tex: np.ndarray, rng: np.random.Generator, out_w: int, out_h: int) -> np.ndarray:
	"""Sample a diamond-sized region with random offset, scale, and mild warp."""
	th, tw = tex.shape[:2]
	scale = float(rng.uniform(0.55, 0.95))
	src_w = int(out_w / scale)
	src_h = int(out_h / scale)
	src_w = min(src_w, tw - 4)
	src_h = min(src_h, th - 4)
	x0 = int(rng.integers(0, max(tw - src_w, 1)))
	y0 = int(rng.integers(0, max(th - src_h, 1)))
	patch = tex[y0 : y0 + src_h, x0 : x0 + src_w]
	pil = Image.fromarray(np.clip(patch, 0, 255).astype(np.uint8), "RGB")
	# Slight rotation keeps variants from looking stamped
	angle = float(rng.uniform(-12, 12))
	pil = pil.rotate(angle, resample=Image.Resampling.BICUBIC, expand=True, fillcolor=(90, 120, 50))
	pil = pil.resize((out_w, out_h), Image.Resampling.LANCZOS)
	if rng.random() < 0.5:
		pil = pil.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
	return np.array(pil).astype(np.float32)


def suppress_large_props(rgb: np.ndarray, mask_opaque: np.ndarray) -> np.ndarray:
	"""Tone down oversized rocks/bushes that break seamless floor reading."""
	out = rgb.copy()
	# Luminance outliers vs local mean → blend toward neighborhood
	lum = 0.299 * out[:, :, 0] + 0.587 * out[:, :, 1] + 0.114 * out[:, :, 2]
	smooth = ndimage.gaussian_filter(lum, sigma=3.0)
	delta = np.abs(lum - smooth)
	# Strong outliers (big bright rocks / dark bush blobs)
	hot = mask_opaque & (delta > 28)
	if not hot.any():
		return out
	blurred = np.stack(
		[ndimage.gaussian_filter(out[:, :, c], sigma=2.5) for c in range(3)],
		axis=-1,
	)
	# Soft weight
	weight = np.clip((delta - 22.0) / 30.0, 0.0, 0.75)
	w = weight[..., None]
	out[hot] = out[hot] * (1.0 - w[hot]) + blurred[hot] * w[hot]
	return out


def paint_tile(
	mask: np.ndarray,
	stem: str,
	sources: list[np.ndarray],
	press: bool = False,
) -> np.ndarray:
	rng = np.random.default_rng(_hash_seed(stem, 11))
	opaque = mask >= 128.0
	out = np.zeros((H, W, 4), dtype=np.float32)
	out[:, :, 3] = mask

	# Blend 2 source patches for richer variation
	a = sample_patch(sources[int(rng.integers(0, len(sources)))], rng, W, H)
	b = sample_patch(sources[int(rng.integers(0, len(sources)))], rng, W, H)
	mix = value_noise((H, W), 20, rng)[..., None]
	rgb = a * (0.55 + 0.35 * mix) + b * (0.45 - 0.35 * mix)

	rgb = suppress_large_props(rgb, opaque)

	# Fine storybook grain (subtle)
	grain = (value_noise((H, W), 4, rng) - 0.5) * 12.0
	rgb += grain[..., None] * np.array([0.7, 1.0, 0.5], dtype=np.float32)

	if press:
		rgb = rgb * 0.78 + np.array([48.0, 68.0, 30.0], dtype=np.float32) * 0.22

	dist = ndimage.distance_transform_edt(opaque)

	# Micro accents stay a few px inside so bright dots aren't sheared at seams.
	interior = opaque & (dist > float(ACCENT_MARGIN))
	if interior.any() and not press:
		ys, xs = np.where(interior)
		n = min(10, len(ys))
		pick = rng.choice(len(ys), size=n, replace=False)
		flower_palette = [
			np.array([210.0, 95.0, 85.0]),
			np.array([230.0, 200.0, 80.0]),
			np.array([180.0, 145.0, 210.0]),
			np.array([245.0, 240.0, 220.0]),
		]
		for idx in pick:
			y, x = int(ys[idx]), int(xs[idx])
			col = flower_palette[int(rng.integers(0, len(flower_palette)))]
			rgb[y, x] = rgb[y, x] * 0.25 + col * 0.75
			if y + 1 < H and opaque[y + 1, x]:
				rgb[y + 1, x] = rgb[y + 1, x] * 0.6 + col * 0.4

	out[:, :, :3] = np.clip(rgb, 0, 255)
	out[~opaque] = 0
	return out


def flatten_bevel_rim(image: np.ndarray, rim: int = RIM) -> np.ndarray:
	"""Luminance-only rim fix — keeps texture so we don't paint a flat olive band."""
	out = image.copy()
	opaque = out[:, :, 3] >= 128
	dist = ndimage.distance_transform_edt(opaque)
	interior = opaque & (dist > rim + 2)
	if not interior.any():
		return out
	body = out[interior, :3]
	target_lum = float(0.299 * body[:, 0].mean() + 0.587 * body[:, 1].mean() + 0.114 * body[:, 2].mean())
	lum = 0.299 * out[:, :, 0] + 0.587 * out[:, :, 1] + 0.114 * out[:, :, 2]
	rim_mask = opaque & (dist <= rim)
	strength = np.clip(1.0 - (dist - 1.0) / float(rim), 0.0, 1.0)
	strength = np.where(dist <= 1.5, np.maximum(strength, 0.95), strength)
	with np.errstate(divide="ignore", invalid="ignore"):
		scale = np.where(lum > 1.0, np.clip(target_lum / lum, 0.85, 1.2), 1.0)
	mixed = 1.0 + (scale - 1.0) * strength
	for c in range(3):
		out[:, :, c] = np.where(rim_mask, np.clip(out[:, :, c] * mixed, 0, 255), out[:, :, c])
	# Soften only the outermost pixel toward local blur (anti AA bright fringe).
	outer = opaque & (dist <= 1.5)
	blur = np.stack([ndimage.gaussian_filter(out[:, :, c], 1.0) for c in range(3)], axis=-1)
	out[:, :, :3] = np.where(outer[..., None], out[:, :, :3] * 0.55 + blur * 0.45, out[:, :, :3])
	return out


def extrude_rgb(image: np.ndarray, px: int = EXTRUDE_PX) -> np.ndarray:
	out = image.copy()
	h, w = out.shape[:2]
	opaque = out[:, :, 3] >= 128
	zone = opaque.copy()
	for _ in range(px):
		zone = ndimage.binary_dilation(zone, ndimage.generate_binary_structure(2, 1))
	nearest = np.full((h, w, 2), -1, dtype=np.int32)
	queue: deque[tuple[int, int]] = deque()
	for y, x in zip(*np.where(opaque)):
		nearest[y, x] = (y, x)
		queue.append((y, x))
	while queue:
		y, x = queue.popleft()
		for dy, dx in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
			ny, nx = y + dy, x + dx
			if not (0 <= ny < h and 0 <= nx < w):
				continue
			if nearest[ny, nx, 0] >= 0 or not zone[ny, nx]:
				continue
			nearest[ny, nx] = nearest[y, x]
			queue.append((ny, nx))
	for y, x in zip(*np.where(zone & ~opaque)):
		oy, ox = nearest[y, x]
		out[y, x, :3] = out[oy, ox, :3]
	return out


def color_match(image: np.ndarray, ref_mean: np.ndarray) -> np.ndarray:
	out = image.copy()
	opaque = out[:, :, 3] >= 128
	out[opaque, :3] = np.clip(out[opaque, :3] + (ref_mean - out[opaque, :3].mean(0)), 0, 255)
	return out


def bake(image: np.ndarray, ref_mean: np.ndarray | None) -> np.ndarray:
	out = image if ref_mean is None else color_match(image, ref_mean)
	out = flatten_bevel_rim(out)
	out = extrude_rgb(out)
	return out


def mild_sharpen(image: np.ndarray) -> np.ndarray:
	"""Recover brush detail after sampling without reintroducing edge bevel."""
	pil = Image.fromarray(np.clip(image, 0, 255).astype(np.uint8), "RGBA")
	rgb = pil.convert("RGB").filter(
		ImageFilter.UnsharpMask(radius=1.2, percent=85, threshold=2)
	)
	arr = np.array(pil).astype(np.float32)
	arr[:, :, :3] = np.array(rgb).astype(np.float32)
	arr[:, :, 3] = image[:, :, 3]
	return arr


def write_preview(tiles: list[np.ndarray], path: Path, cols: int = 4, rows: int = 3) -> None:
	pad_x, pad_y = 128, 64
	canvas = Image.new("RGBA", (cols * pad_x + W, rows * pad_y + H), (22, 26, 20, 255))
	for i, tile in enumerate(tiles[: cols * rows]):
		r, c = divmod(i, cols)
		x = c * pad_x + (pad_x // 2 if r % 2 else 0)
		y = r * pad_y
		spr = Image.fromarray(np.clip(tile, 0, 255).astype(np.uint8), "RGBA")
		canvas.alpha_composite(spr, (x, y))
	path.parent.mkdir(parents=True, exist_ok=True)
	canvas.save(path)
	print(f"Wrote preview {path}")


def main() -> None:
	mask = load_diamond_mask()
	sources = load_source_textures()
	print(f"Target mean RGB: {TARGET_MEAN.round(1)}")

	raw_tiles: list[np.ndarray] = []
	for stem in FLOOR_STEMS:
		tile = paint_tile(mask, stem, sources, press=False)
		tile = mild_sharpen(tile)
		raw_tiles.append(tile)
		print(f"Painted {stem}")

	press = paint_tile(mask, PRESS_STEM, sources, press=True)
	press = mild_sharpen(press)
	raw_tiles.append(press)
	print(f"Painted {PRESS_STEM}")

	# Tone-match all floor tiles to the same mean — no flat edge band.
	raw_tiles[0] = color_match(raw_tiles[0], TARGET_MEAN)
	ref_mean = raw_tiles[0][raw_tiles[0][:, :, 3] >= 128, :3].mean(0)

	baked: list[np.ndarray] = []
	for i, stem in enumerate(ALL_STEMS):
		if stem == PRESS_STEM:
			field = bake(raw_tiles[i], None)
			opaque = field[:, :, 3] >= 128
			press_target = ref_mean * 0.84
			field[opaque, :3] = np.clip(
				field[opaque, :3] + (press_target - field[opaque, :3].mean(0)) * 0.7,
				0,
				255,
			)
			field = flatten_bevel_rim(field)
			field = extrude_rgb(field)
		else:
			field = bake(raw_tiles[i], None if i == 0 else ref_mean)
			if i > 0:
				field = color_match(field, baked[0][baked[0][:, :, 3] >= 128, :3].mean(0))
		baked.append(field)
		out = TERRAIN / f"{stem}_field.png"
		Image.fromarray(np.clip(field, 0, 255).astype(np.uint8)).save(out)
		Image.fromarray(np.clip(field, 0, 255).astype(np.uint8)).save(TERRAIN / f"{stem}.png")
		mean = field[field[:, :, 3] >= 128, :3].mean(0)
		print(f"Wrote {out.name} mean={mean.round(1)}")

	write_preview(baked[:12], PREVIEW / "painterly_grass_grid.png")
	write_preview([baked[0]] * 9, PREVIEW / "painterly_grass_same_tile.png", cols=3, rows=3)
	write_preview([baked[i % 12] for i in range(12)], PREVIEW / "painterly_grass_mixed.png")


if __name__ == "__main__":
	main()
