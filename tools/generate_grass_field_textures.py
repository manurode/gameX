#!/usr/bin/env python3
"""Bake seam-fixed grass tiles that keep original speckles/detail.

Removes the dark bevel by blending rim pixels toward the interior mean
(keeping high-chroma flowers). Does NOT dilate the diamond silhouette —
dilation created vertical tip bars. Only extrudes RGB under alpha=0 so
linear filtering does not sample black at edges.
"""

from __future__ import annotations

from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[1]
TERRAIN = ROOT / "assets" / "tilesets" / "mediterranean" / "Terrain"
RIM = 10
EXTRUDE_PX = 1
SPECKLE_CHROMA = 40.0


def load(name: str) -> np.ndarray:
	return np.array(Image.open(TERRAIN / f"{name}.png").convert("RGBA")).astype(np.float32)


def color_match(image: np.ndarray, ref_mean: np.ndarray) -> np.ndarray:
	out = image.copy()
	opaque = out[:, :, 3] >= 128
	out[opaque, :3] = np.clip(out[opaque, :3] + (ref_mean - out[opaque, :3].mean(0)), 0, 255)
	return out


def _luminance(rgb: np.ndarray) -> float:
	return float(0.299 * rgb[0] + 0.587 * rgb[1] + 0.114 * rgb[2])


def flatten_bevel_rim(image: np.ndarray, rim: int = RIM) -> np.ndarray:
	"""Remove dark/light bevel by matching rim luminance to the interior.

	Keeps local grain (no flat halo, no cloned vertical tip bars).
	High-chroma speckles/flowers are left untouched.
	"""
	out = image.copy()
	opaque = out[:, :, 3] >= 128
	dist = ndimage.distance_transform_edt(opaque)
	interior = opaque & (dist > rim)
	if not interior.any():
		return out

	chroma = np.abs(out[:, :, 0] - out[interior, 0].mean())
	chroma += np.abs(out[:, :, 1] - out[interior, 1].mean())
	chroma += np.abs(out[:, :, 2] - out[interior, 2].mean())
	body = interior & (chroma < SPECKLE_CHROMA)
	if not body.any():
		body = interior
	body_rgb = out[body, :3]
	body_mean = body_rgb.mean(0)
	target_lum = float(
		0.299 * body_mean[0] + 0.587 * body_mean[1] + 0.114 * body_mean[2]
	)

	ys, xs = np.where(opaque & (dist <= rim))
	for y, x in zip(ys, xs):
		color = out[y, x, :3]
		pix_chroma = float(np.abs(color - body_mean).sum())
		if pix_chroma >= SPECKLE_CHROMA:
			continue
		lum = _luminance(color)
		if lum < 1.0:
			continue
		scale = target_lum / lum
		# Only correct bevel shading; clamp so speckles aren't blown out.
		scale = float(np.clip(scale, 0.85, 1.25))
		edge_dist = float(dist[y, x])
		strength = float(np.clip(1.0 - (edge_dist - 1.0) / float(rim), 0.0, 1.0))
		# Outer pixels need a full correction — residual bevel reads as grid.
		if edge_dist <= 5.0:
			strength = max(strength, 0.95)
		mixed_scale = 1.0 + (scale - 1.0) * strength
		out[y, x, :3] = np.clip(color * mixed_scale, 0, 255)
	return out


def extrude_rgb(image: np.ndarray, px: int = EXTRUDE_PX) -> np.ndarray:
	"""Fill RGB under nearby transparent pixels; keep alpha=0 (no silhouette growth)."""
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


def process(image: np.ndarray, ref_mean: np.ndarray | None = None) -> np.ndarray:
	out = image if ref_mean is None else color_match(image, ref_mean)
	out = flatten_bevel_rim(out)
	out = extrude_rgb(out)
	return out


def main() -> None:
	names = ["grass_a", "grass_b", "grass_c", "grass_d"]
	raw = [load(name) for name in names]
	ref_mean = raw[0][raw[0][:, :, 3] >= 128, :3].mean(0)
	processed: list[np.ndarray] = []
	for i, name in enumerate(names):
		tile = process(raw[i], None if i == 0 else ref_mean)
		if i > 0:
			tile = color_match(tile, processed[0][processed[0][:, :, 3] >= 128, :3].mean(0))
		processed.append(tile)
		out_path = TERRAIN / f"{name}_field.png"
		Image.fromarray(np.clip(tile, 0, 255).astype(np.uint8)).save(out_path)
		print(f"Wrote {out_path}")


if __name__ == "__main__":
	main()
