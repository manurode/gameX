"""Fill transparent damage voids in damaged building sprites.

AI chroma-key punched out near-black interior fills. Thin cracks often keep
roof holes 4-connected to exterior alpha, so a plain flood-fill misses them.

Strategy:
1. Close the opaque silhouette slightly to seal hairline cracks.
2. Fill holes in the closed mask.
3. Catch remaining locally-enclosed voids (majority-opaque neighborhood).
4. Harden semi-transparent pixels deep inside the silhouette (shadow dither).
"""

from __future__ import annotations

import shutil
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(r"C:\Repos\gameX")
BUILDINGS_DIR = ROOT / "assets" / "tilesets" / "mediterranean" / "Buildings"
BACKUP_DIR = ROOT / "assets" / "_archive" / "damaged_pre_hole_fix"

ALPHA_THRESH = 20
SOFT_ALPHA = 200
CLOSE_ITERS = 4
LOCAL_SIZE = 11
LOCAL_RATIO = 0.50
HARDEN_ERODE = 2
FILL_FALLBACK = (28, 22, 18)

SKIP = {"wall_se_damaged.png", "wall_sw_damaged.png"}
MIN_PAINT = 20


def _sample_fill_color(arr: np.ndarray, hole_mask: np.ndarray) -> tuple[int, int, int]:
	h, w = arr.shape[:2]
	alpha = arr[..., 3]
	padded = np.pad(hole_mask, 1, constant_values=False)
	ring = np.zeros_like(hole_mask)
	for dy in (-1, 0, 1):
		for dx in (-1, 0, 1):
			if dx == 0 and dy == 0:
				continue
			ring |= padded[1 + dy : 1 + dy + h, 1 + dx : 1 + dx + w]
	ring &= ~hole_mask
	opaque = (alpha >= ALPHA_THRESH) & ring
	if not opaque.any():
		return FILL_FALLBACK
	rgb = arr[..., :3][opaque].astype(np.float32)
	luma = 0.2126 * rgb[:, 0] + 0.7152 * rgb[:, 1] + 0.0722 * rgb[:, 2]
	dark = rgb[luma <= np.percentile(luma, 40)]
	if len(dark) == 0:
		dark = rgb
	mean = np.clip(dark.mean(axis=0), [16, 12, 10], [58, 50, 42])
	return tuple(int(round(c)) for c in mean)


def _hole_mask(alpha: np.ndarray) -> np.ndarray:
	opaque = alpha >= ALPHA_THRESH
	closed = ndimage.binary_closing(opaque, iterations=CLOSE_ITERS)
	filled = ndimage.binary_fill_holes(closed)
	filled_open = ndimage.binary_fill_holes(opaque)
	rim = closed & ~opaque & ~filled_open
	morph_holes = (filled & ~closed) | (filled & (alpha < SOFT_ALPHA) & ~rim)

	# Local enclosure: transparent pixels mostly surrounded by opaque neighbors.
	neigh = ndimage.uniform_filter(opaque.astype(np.float32), size=LOCAL_SIZE)
	local_holes = (alpha < ALPHA_THRESH) & (neigh >= LOCAL_RATIO)

	return morph_holes | local_holes


def _harden_interior_alpha(arr: np.ndarray) -> int:
	"""Force deep-interior semi-transparent pixels to full opacity."""
	alpha = arr[..., 3]
	opaque = alpha >= ALPHA_THRESH
	inside = ndimage.binary_erosion(ndimage.binary_fill_holes(opaque), iterations=HARDEN_ERODE)
	semi = inside & (alpha < 250)
	n = int(semi.sum())
	if n:
		arr[semi, 3] = 255
	return n


def fix_image(img: Image.Image) -> tuple[Image.Image, int, int]:
	arr = np.asarray(img.convert("RGBA")).copy()
	holes = _hole_mask(arr[..., 3])
	n_holes = int(holes.sum())
	if n_holes:
		fill = _sample_fill_color(arr, holes)
		arr[holes, 0] = fill[0]
		arr[holes, 1] = fill[1]
		arr[holes, 2] = fill[2]
		arr[holes, 3] = 255
	n_hard = _harden_interior_alpha(arr)
	return Image.fromarray(arr, "RGBA"), n_holes, n_hard


def main() -> None:
	BACKUP_DIR.mkdir(parents=True, exist_ok=True)
	# Restore originals so re-runs stay idempotent.
	for bak in BACKUP_DIR.glob("*_damaged.png"):
		shutil.copy2(bak, BUILDINGS_DIR / bak.name)

	fixed = 0
	for path in sorted(BUILDINGS_DIR.glob("*_damaged.png")):
		if path.name in SKIP:
			print(f"skip {path.name}")
			continue
		bak = BACKUP_DIR / path.name
		if not bak.exists():
			shutil.copy2(path, bak)
		out, n_holes, n_hard = fix_image(Image.open(bak))
		if n_holes + n_hard < MIN_PAINT:
			print(f"ok   {path.name:28} holes={n_holes} harden={n_hard}")
			continue
		out.save(path)
		print(f"fix  {path.name:28} holes={n_holes} harden={n_hard}")
		fixed += 1
	print(f"done ({fixed} files updated)")


if __name__ == "__main__":
	main()
