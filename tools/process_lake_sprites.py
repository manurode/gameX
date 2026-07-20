"""Process AI lake-body sprites into transparent Decor assets."""
from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "assets/tilesets/mediterranean/Decor"
GEN_DIR = Path(r"C:\Users\Manu\.cursor\projects\c-Repos-gameX\assets")

SOURCES = [
	("lake_a.png", GEN_DIR / "lake_body_a.png", (1100, 720)),
	("lake_b.png", GEN_DIR / "lake_body_b.png", (1050, 780)),
	("lake_c.png", GEN_DIR / "lake_body_c.png", (980, 820)),
]


def remove_near_white_bg(img: Image.Image) -> Image.Image:
	a = np.array(img.convert("RGBA"), dtype=np.float32)
	r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
	sat = np.maximum(np.maximum(r, g), b) - np.minimum(np.minimum(r, g), b)
	lum = (r + g + b) / 3.0
	# Near-white / light gray void (includes soft checker leftovers)
	is_bg = (lum > 232) & (sat < 18) & (np.abs(r - g) < 12) & (np.abs(g - b) < 12)
	# Soft fringe: slightly darker near-neutral pixels
	is_fringe = (lum > 210) & (sat < 14) & (np.abs(r - g) < 10) & (np.abs(g - b) < 10)
	a[is_bg, 3] = 0
	a[is_fringe, 3] = np.minimum(a[is_fringe, 3], 40)
	return Image.fromarray(a.astype(np.uint8), "RGBA")


def crop_alpha(img: Image.Image, pad: int = 8) -> Image.Image:
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


def fit_canvas(img: Image.Image, size: tuple[int, int], max_fill: float = 0.97) -> Image.Image:
	tw, th = size
	scale = min((tw * max_fill) / img.width, (th * max_fill) / img.height)
	nw = max(1, int(img.width * scale))
	nh = max(1, int(img.height * scale))
	resized = img.resize((nw, nh), Image.Resampling.LANCZOS)
	canvas = Image.new("RGBA", size, (0, 0, 0, 0))
	x = (tw - nw) // 2
	y = (th - nh) // 2
	canvas.paste(resized, (x, y), resized)
	return canvas


def process(path: Path, size: tuple[int, int]) -> Image.Image:
	img = remove_near_white_bg(Image.open(path))
	img = crop_alpha(img, pad=6)
	# Kill residual pale fringe after crop
	a = np.array(img.convert("RGBA"), dtype=np.float32)
	r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
	sat = np.maximum(np.maximum(r, g), b) - np.minimum(np.minimum(r, g), b)
	lum = (r + g + b) / 3.0
	fringe = (sat < 16) & (lum > 200) & (a[:, :, 3] > 0) & (np.abs(r - g) < 12)
	a[fringe, 3] = 0
	img = Image.fromarray(a.astype(np.uint8), "RGBA")
	img = crop_alpha(img, pad=4)
	return fit_canvas(img, size, max_fill=0.98)


def main() -> None:
	OUT_DIR.mkdir(parents=True, exist_ok=True)
	for name, src, size in SOURCES:
		if not src.exists():
			print("missing", src)
			continue
		out = OUT_DIR / name
		lake = process(src, size)
		lake.save(out, "PNG")
		print("saved", out, lake.size, "bbox", lake.getbbox())


if __name__ == "__main__":
	main()
