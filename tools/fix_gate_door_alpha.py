"""Fill leaky transparent voids in closed gate door leaves.

Dark wood was soft-keyed / punched out by process_gate_sprites.remove_dark_bg.
Those voids often connect to exterior alpha through hairline cracks, so a plain
flood-fill misses them and grass shows through the door.

Strategy (closed / damaged / construction only):
1. Aggressively close the opaque silhouette to seal cracks.
2. Fill holes inside the sealed silhouette (near existing paint).
3. Catch remaining locally-enclosed soft/transparent pixels at several scales.
4. Harden leftover deep-interior soft alpha to 255.
5. Open gates: light interior harden only (passageway must stay transparent).
"""

from __future__ import annotations

import shutil
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(r"C:\Repos\gameX")
BUILDINGS_DIR = ROOT / "assets" / "tilesets" / "mediterranean" / "Buildings"
BACKUP_DIR = ROOT / "assets" / "_archive" / "gate_pre_alpha_fix"

ALPHA_THRESH = 20
HARDEN_ERODE = 2
FILL_FALLBACK = (55, 36, 24)

CLOSED_TARGETS = (
	"gate_se.png",
	"gate_sw.png",
	"gate_se_damaged.png",
	"gate_sw_damaged.png",
	"gate_se_construction.png",
	"gate_sw_construction.png",
)
OPEN_TARGETS = (
	"gate_se_open.png",
	"gate_sw_open.png",
)


def _sample_wood(arr: np.ndarray, mask: np.ndarray) -> tuple[int, int, int]:
	h, w = arr.shape[:2]
	alpha = arr[..., 3]
	padded = np.pad(mask, 1, constant_values=False)
	ring = np.zeros_like(mask)
	for dy in (-1, 0, 1):
		for dx in (-1, 0, 1):
			if dx == 0 and dy == 0:
				continue
			ring |= padded[1 + dy : 1 + dy + h, 1 + dx : 1 + dx + w]
	ring &= ~mask
	opaque = (alpha >= ALPHA_THRESH) & ring
	if not opaque.any():
		return FILL_FALLBACK
	rgb = arr[..., :3][opaque].astype(np.float32)
	luma = 0.2126 * rgb[:, 0] + 0.7152 * rgb[:, 1] + 0.0722 * rgb[:, 2]
	chroma = rgb.max(axis=1) - rgb.min(axis=1)
	wood = rgb[(luma < 110) & (chroma > 8)]
	if len(wood) == 0:
		wood = rgb[luma <= np.percentile(luma, 35)]
	if len(wood) == 0:
		wood = rgb
	mean = np.clip(wood.mean(axis=0), [30, 20, 12], [95, 70, 48])
	return tuple(int(round(c)) for c in mean)


def _harden_interior_alpha(arr: np.ndarray) -> int:
	alpha = arr[..., 3]
	opaque = alpha >= ALPHA_THRESH
	inside = ndimage.binary_erosion(ndimage.binary_fill_holes(opaque), iterations=HARDEN_ERODE)
	semi = inside & (alpha < 250)
	n = int(semi.sum())
	if n:
		arr[semi, 3] = 255
	return n


def fix_closed(img: Image.Image) -> tuple[Image.Image, int, int, tuple[int, int, int] | None]:
	arr = np.asarray(img.convert("RGBA")).copy()
	alpha = arr[..., 3]
	opaque = alpha >= ALPHA_THRESH

	closed = ndimage.binary_closing(opaque, iterations=10)
	filled = ndimage.binary_fill_holes(closed)
	near = ndimage.binary_dilation(opaque, iterations=6)
	morph = filled & near & (alpha < 250)

	local = np.zeros_like(opaque)
	for size, ratio in ((5, 0.35), (7, 0.30), (9, 0.28), (11, 0.25), (15, 0.22)):
		neigh = ndimage.uniform_filter(opaque.astype(np.float32), size=size)
		local |= (alpha < 250) & (neigh >= ratio)
	local &= filled & near

	paint = morph | local
	n_paint = int(paint.sum())
	fill = None
	if n_paint:
		fill = _sample_wood(arr, paint)
		soft = paint & (alpha >= 40)
		void = paint & (alpha < 40)
		arr[soft, 3] = 255
		arr[void, 0] = fill[0]
		arr[void, 1] = fill[1]
		arr[void, 2] = fill[2]
		arr[void, 3] = 255

	n_hard = _harden_interior_alpha(arr)
	return Image.fromarray(arr, "RGBA"), n_paint, n_hard, fill


def fix_open(img: Image.Image) -> tuple[Image.Image, int]:
	"""Harden wall/door-leaf soft alpha; leave passageway connected to exterior."""
	arr = np.asarray(img.convert("RGBA")).copy()
	n_hard = _harden_interior_alpha(arr)
	return Image.fromarray(arr, "RGBA"), n_hard


def main() -> None:
	BACKUP_DIR.mkdir(parents=True, exist_ok=True)
	targets = CLOSED_TARGETS + OPEN_TARGETS
	for name in targets:
		bak = BACKUP_DIR / name
		if bak.exists():
			shutil.copy2(bak, BUILDINGS_DIR / name)

	for name in CLOSED_TARGETS:
		path = BUILDINGS_DIR / name
		if not path.exists():
			print(f"missing {name}")
			continue
		bak = BACKUP_DIR / name
		if not bak.exists():
			shutil.copy2(path, bak)
		out, n_paint, n_hard, fill = fix_closed(Image.open(bak))
		out.save(path)
		print(f"fix  {name:28} paint={n_paint} harden={n_hard} fill={fill}")

	for name in OPEN_TARGETS:
		path = BUILDINGS_DIR / name
		if not path.exists():
			print(f"missing {name}")
			continue
		bak = BACKUP_DIR / name
		if not bak.exists():
			shutil.copy2(path, bak)
		out, n_hard = fix_open(Image.open(bak))
		out.save(path)
		print(f"open  {name:28} harden={n_hard}")

	print("done")


if __name__ == "__main__":
	main()
