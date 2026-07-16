"""Process AI mountain-range sprites into transparent Decor assets."""
from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "assets/tilesets/mediterranean/Decor"
GEN_DIR = Path(r"C:\Users\Manu\.cursor\projects\c-Repos-gameX\assets")

SOURCES = [
	("mountain_a.png", GEN_DIR / "mountain_range_a.png"),
	("mountain_b.png", GEN_DIR / "mountain_range_b.png"),
	("mountain_c.png", GEN_DIR / "mountain_range_c.png"),
]


def remove_checkerboard(img: Image.Image) -> Image.Image:
	a = np.array(img.convert("RGBA"), dtype=np.float32)
	r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
	sat = np.maximum(np.maximum(r, g), b) - np.minimum(np.minimum(r, g), b)
	lum = (r + g + b) / 3.0
	# Light checker (~200-255 near-neutral gray/white)
	is_checker = (sat < 14) & (lum > 185) & (np.abs(r - g) < 10) & (np.abs(g - b) < 10)
	a[is_checker, 3] = 0
	# Near-black void
	is_black = (lum < 18) & (sat < 12)
	a[is_black, 3] = 0
	return Image.fromarray(a.astype(np.uint8), "RGBA")


def make_black_transparent(img: Image.Image, thr: float = 22.0) -> Image.Image:
	a = np.array(img.convert("RGBA"), dtype=np.float32)
	rgb = a[:, :, :3]
	lum = rgb.mean(axis=2)
	alpha = np.clip((lum - thr) / 16.0, 0, 1) * 255.0
	a[:, :, 3] = np.minimum(a[:, :, 3], alpha)
	return Image.fromarray(a.astype(np.uint8), "RGBA")


def crop_alpha(img: Image.Image, pad: int = 6) -> Image.Image:
	a = np.array(img)
	mask = a[:, :, 3] > 12
	ys, xs = np.where(mask)
	if len(xs) == 0:
		return img
	x0 = max(0, int(xs.min()) - pad)
	x1 = min(img.width, int(xs.max()) + pad + 1)
	y0 = max(0, int(ys.min()) - pad)
	y1 = min(img.height, int(ys.max()) + pad + 1)
	return img.crop((x0, y0, x1, y1))


def scale_max_width(img: Image.Image, max_w: int) -> Image.Image:
	if img.width <= max_w:
		return img
	ratio = max_w / img.width
	return img.resize((max_w, int(img.height * ratio)), Image.Resampling.LANCZOS)


def process(path: Path) -> Image.Image:
	img = Image.open(path)
	arr = np.array(img.convert("RGBA"))
	corners = [arr[0, 0, :3], arr[0, -1, :3], arr[-1, 0, :3], arr[-1, -1, :3]]
	if np.mean([float(c.mean()) for c in corners]) < 40:
		img = make_black_transparent(img)
	else:
		img = remove_checkerboard(img)
	# Soften leftover fringe: kill near-white low-sat pixels again after crop
	img = crop_alpha(img, pad=4)
	a = np.array(img.convert("RGBA"), dtype=np.float32)
	r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
	sat = np.maximum(np.maximum(r, g), b) - np.minimum(np.minimum(r, g), b)
	lum = (r + g + b) / 3.0
	fringe = (sat < 18) & (lum > 170) & (a[:, :, 3] > 0) & (np.abs(r - g) < 14)
	a[fringe, 3] = 0
	img = Image.fromarray(a.astype(np.uint8), "RGBA")
	return scale_max_width(crop_alpha(img, pad=4), 1100)


def main() -> None:
	OUT_DIR.mkdir(parents=True, exist_ok=True)
	for name, src in SOURCES:
		if not src.exists():
			print("missing", src)
			continue
		out = OUT_DIR / name
		forest = process(src)
		forest.save(out, "PNG")
		print("saved", out, forest.size)


if __name__ == "__main__":
	main()
