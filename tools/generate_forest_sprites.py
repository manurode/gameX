"""Compose dense forest sprites from the existing cypress asset + clean AI variants."""
from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
CYPRESS = ROOT / "assets/tilesets/mediterranean/Decor/cypress.png"
GRASS = ROOT / "assets/tilesets/mediterranean/Terrain/grass_a.png"
OUT_DIR = ROOT / "assets/tilesets/mediterranean/Decor"
GEN_A = Path(
	r"C:\Users\Manu\.cursor\projects\c-Repos-gameX\assets\forest_a.png"
)
GEN_B = Path(
	r"C:\Users\Manu\.cursor\projects\c-Repos-gameX\assets\forest_b.png"
)


def make_black_transparent(img: Image.Image, thr: float = 28.0) -> Image.Image:
	a = np.array(img.convert("RGBA"), dtype=np.float32)
	rgb = a[:, :, :3]
	lum = rgb.mean(axis=2)
	alpha = np.clip((lum - thr) / 18.0, 0, 1) * 255.0
	dark = (rgb[:, :, 0] < 18) & (rgb[:, :, 1] < 22) & (rgb[:, :, 2] < 18)
	alpha[dark] = 0
	a[:, :, 3] = np.minimum(a[:, :, 3], alpha)
	return Image.fromarray(a.astype(np.uint8), "RGBA")


def remove_checkerboard(img: Image.Image) -> Image.Image:
	a = np.array(img.convert("RGBA"), dtype=np.float32)
	r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
	sat = np.maximum(np.maximum(r, g), b) - np.minimum(np.minimum(r, g), b)
	lum = (r + g + b) / 3.0
	is_checker = (sat < 12) & (lum > 200) & (np.abs(r - g) < 8) & (np.abs(g - b) < 8)
	a[is_checker, 3] = 0
	is_water = (b > 140) & (b > g + 20) & (b > r + 40) & (a[:, :, 3] > 0)
	a[is_water, 3] = 0
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


def extract_tree(cypress: Image.Image) -> Image.Image:
	"""Keep only the vertical foliage column; strip stone plot and wide base."""
	a = np.array(cypress.convert("RGBA"))
	h, w = a.shape[:2]
	out = a.copy()
	cx = w * 0.5
	for y in range(h):
		# taper: keep a narrow column; kill everything below the grass mound
		half_w = 28 + (210 - y) * 0.12 if y < 210 else max(8, 28 - (y - 210) * 0.9)
		for x in range(w):
			if a[y, x, 3] < 10:
				continue
			r, g, b = a[y, x, :3].astype(int)
			# remove beige stone curb / plot
			is_stone = r > 115 and g > 105 and b < 145 and abs(int(r) - int(g)) < 45 and r > b + 15
			if is_stone and y > 195:
				out[y, x, 3] = 0
				continue
			if abs(x - cx) > half_w and y > 180:
				out[y, x, 3] = 0
				continue
			if y >= 235:
				out[y, x, 3] = 0
	img = Image.fromarray(out, "RGBA")
	# fade lower fringe so trees blend into shared forest floor
	arr = np.array(img, dtype=np.float32)
	fade_start = int(arr.shape[0] * 0.82)
	for y in range(fade_start, arr.shape[0]):
		t = (y - fade_start) / max(1, arr.shape[0] - fade_start)
		arr[y, :, 3] *= max(0.0, 1.0 - t * 0.85)
	return crop_alpha(Image.fromarray(arr.astype(np.uint8), "RGBA"), pad=2)


def iso_offset(col: int, row: int, tw: int = 128, th: int = 64) -> tuple[int, int]:
	return int((col - row) * tw * 0.5), int((col + row) * th * 0.5)


def tint(img: Image.Image, factor_g: float = 1.0, factor_r: float = 1.0, brightness: float = 1.0) -> Image.Image:
	a = np.array(img.convert("RGBA"), dtype=np.float32)
	a[:, :, 0] *= factor_r
	a[:, :, 1] *= factor_g
	a[:, :, :3] *= brightness
	a[:, :, :3] = np.clip(a[:, :, :3], 0, 255)
	return Image.fromarray(a.astype(np.uint8), "RGBA")


def compose_forest(tree: Image.Image, layout: list[tuple[int, int]], seed: int = 1) -> Image.Image:
	rng = np.random.default_rng(seed)
	positions: list[tuple[int, int, float, bool, float, float, float]] = []
	for col, row in layout:
		ox, oy = iso_offset(col, row)
		ox += int(rng.integers(-10, 11))
		oy += int(rng.integers(-6, 7))
		scale = float(rng.uniform(0.82, 1.08))
		flip = bool(rng.random() < 0.15)
		tg = float(rng.uniform(0.92, 1.08))
		tr = float(rng.uniform(0.95, 1.05))
		br = float(rng.uniform(0.92, 1.05))
		positions.append((ox, oy, scale, flip, tg, tr, br))

	tw, th = tree.size
	xs: list[int] = []
	ys: list[int] = []
	for ox, oy, scale, *_ in positions:
		w, h = int(tw * scale), int(th * scale)
		xs += [ox - w // 2, ox + w // 2]
		ys += [oy - int(h * 0.88), oy + int(h * 0.12)]
	minx, maxx = min(xs), max(xs)
	miny, maxy = min(ys), max(ys)
	pad = 40
	width = maxx - minx + pad * 2
	height = maxy - miny + pad * 2
	canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))

	cx = width // 2
	cy = int(height * 0.72)
	cols = [c for c, _ in layout]
	rows = [r for _, r in layout]
	span = max(cols) + max(rows) + 2
	dw = max(420, span * 64)
	dh = max(220, span * 32)

	base_mask = Image.new("L", (width, height), 0)
	md = ImageDraw.Draw(base_mask)
	diamond = [
		(cx, cy - dh // 2),
		(cx + dw // 2, cy),
		(cx, cy + dh // 2),
		(cx - dw // 2, cy),
	]
	md.polygon(diamond, fill=255)
	base_mask = base_mask.filter(ImageFilter.GaussianBlur(10))

	grass = Image.open(GRASS).convert("RGBA").resize((dw + 80, dh + 40), Image.Resampling.LANCZOS)
	grass_layer = Image.new("RGBA", (width, height), (0, 0, 0, 0))
	grass_layer.paste(grass, (cx - grass.width // 2, cy - grass.height // 2), grass)
	ga = np.array(grass_layer, dtype=np.float32)
	ga[:, :, :3] *= 0.85
	m = np.array(base_mask, dtype=np.float32) / 255.0
	ga[:, :, 3] *= m
	grass_layer = Image.fromarray(ga.astype(np.uint8), "RGBA")
	canvas = Image.alpha_composite(canvas, grass_layer)

	shadow = Image.new("RGBA", (width, height), (0, 0, 0, 0))
	sd = ImageDraw.Draw(shadow)
	sd.ellipse(
		[cx - dw // 3, cy - dh // 5, cx + dw // 3, cy + dh // 5],
		fill=(20, 30, 10, 90),
	)
	shadow = shadow.filter(ImageFilter.GaussianBlur(18))
	canvas = Image.alpha_composite(canvas, shadow)

	origin_x = -minx + pad
	origin_y = -miny + pad
	for ox, oy, scale, flip, tg, tr, br in sorted(positions, key=lambda p: p[1]):
		spr = tree.copy()
		if flip:
			spr = spr.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
		nw = max(1, int(tw * scale))
		nh = max(1, int(th * scale))
		spr = tint(spr.resize((nw, nh), Image.Resampling.LANCZOS), tg, tr, br)
		px = origin_x + ox - nw // 2
		py = origin_y + oy - int(nh * 0.88)
		canvas.alpha_composite(spr, (px, py))

	return crop_alpha(canvas, pad=6)


def scale_max_width(img: Image.Image, max_w: int) -> Image.Image:
	if img.width <= max_w:
		return img
	ratio = max_w / img.width
	return img.resize((max_w, int(img.height * ratio)), Image.Resampling.LANCZOS)


LAYOUT_A = [
	(0, 1), (0, 2), (0, 3),
	(1, 0), (1, 1), (1, 2), (1, 3),
	(2, 0), (2, 1), (2, 2), (2, 3),
	(3, 0), (3, 1), (3, 2),
]
LAYOUT_B = [
	(0, 0), (0, 1), (0, 2),
	(1, 0), (1, 1), (1, 2), (1, 3),
	(2, 0), (2, 1), (2, 2), (2, 3),
	(3, 1), (3, 2), (3, 3),
	(4, 2),
]
LAYOUT_C = [
	(1, 0), (2, 0), (3, 0),
	(0, 1), (1, 1), (2, 1), (3, 1), (4, 1),
	(0, 2), (1, 2), (2, 2), (3, 2), (4, 2),
	(1, 3), (2, 3), (3, 3),
]


GEN_WIDE = Path(
	r"C:\Users\Manu\.cursor\projects\c-Repos-gameX\assets\forest_wide.png"
)


def process_painted(path: Path, max_w: int = 900) -> Image.Image:
	img = Image.open(path)
	arr = np.array(img.convert("RGBA"))
	# Prefer black-key if corners are dark; otherwise strip checkerboard.
	corners = [arr[0, 0, :3], arr[0, -1, :3], arr[-1, 0, :3], arr[-1, -1, :3]]
	if np.mean([c.mean() for c in corners]) < 40:
		img = make_black_transparent(img)
	else:
		img = remove_checkerboard(img)
	return scale_max_width(crop_alpha(img, pad=4), max_w)


def main() -> None:
	OUT_DIR.mkdir(parents=True, exist_ok=True)
	tree = extract_tree(Image.open(CYPRESS))
	print("tree extract", tree.size)

	# Primary in-game variants: painted dense groves (frondoso, ~15 tiles).
	sources = [
		("forest_a.png", GEN_WIDE if GEN_WIDE.exists() else GEN_B),
		("forest_b.png", GEN_B),
		("forest_c.png", GEN_A),
	]
	for name, src in sources:
		if not src.exists():
			continue
		forest = process_painted(src)
		out = OUT_DIR / name
		forest.save(out, "PNG")
		print("saved painted", out, forest.size)

	# Extra composed variants from the real cypress sprite (style-locked).
	for name, layout, seed in [
		("forest_composed_a.png", LAYOUT_A, 11),
		("forest_composed_b.png", LAYOUT_B, 22),
		("forest_composed_c.png", LAYOUT_C, 33),
	]:
		forest = scale_max_width(compose_forest(tree, layout, seed=seed), 780)
		out = OUT_DIR / name
		forest.save(out, "PNG")
		print("saved composed", out, forest.size)


if __name__ == "__main__":
	main()
