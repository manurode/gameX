"""Bake hub resource icons: transparent 256x256, clean edges for HUD."""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageFilter

SRC_DIR = Path(r"C:/Users/Manu/.cursor/projects/c-Repos-gameX/assets")
DST_DIR = Path(__file__).resolve().parents[1] / "assets" / "ui" / "icons"
TARGET = 256
PAD_RATIO = 0.1


def _is_bg(r: int, g: int, b: int, luma_min: float = 200.0, chroma_max: float = 36.0) -> bool:
	luma = 0.299 * r + 0.587 * g + 0.114 * b
	chroma = max(r, g, b) - min(r, g, b)
	return luma >= luma_min and chroma <= chroma_max


def remove_backdrop(im: Image.Image) -> Image.Image:
	im = im.convert("RGBA")
	w, h = im.size
	px = im.load()
	visited = bytearray(w * h)
	stack: list[tuple[int, int]] = []
	for x in range(w):
		stack.append((x, 0))
		stack.append((x, h - 1))
	for y in range(h):
		stack.append((0, y))
		stack.append((w - 1, y))
	while stack:
		x, y = stack.pop()
		i = y * w + x
		if visited[i]:
			continue
		visited[i] = 1
		r, g, b, _a = px[x, y]
		if not _is_bg(r, g, b):
			continue
		px[x, y] = (0, 0, 0, 0)
		if x > 0:
			stack.append((x - 1, y))
		if x + 1 < w:
			stack.append((x + 1, y))
		if y > 0:
			stack.append((x, y - 1))
		if y + 1 < h:
			stack.append((x, y + 1))
	for y in range(h):
		for x in range(w):
			r, g, b, a = px[x, y]
			if a and _is_bg(r, g, b, luma_min=215.0, chroma_max=28.0):
				px[x, y] = (0, 0, 0, 0)
	return im


def despeckle_dark(im: Image.Image) -> Image.Image:
	"""Remove isolated near-black speckles on bright painted surfaces."""
	px = im.load()
	w, h = im.size
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			r, g, b, a = px[x, y]
			if a < 200:
				continue
			luma = 0.299 * r + 0.587 * g + 0.114 * b
			if luma > 55:
				continue
			# Average bright neighbors; if surrounded by brighter paint, replace speck.
			samples: list[tuple[int, int, int]] = []
			for oy in (-1, 0, 1):
				for ox in (-1, 0, 1):
					if ox == 0 and oy == 0:
						continue
					nr, ng, nb, na = px[x + ox, y + oy]
					if na < 200:
						continue
					nl = 0.299 * nr + 0.587 * ng + 0.114 * nb
					if nl > 90:
						samples.append((nr, ng, nb))
			if len(samples) >= 5:
				sr = sum(s[0] for s in samples) // len(samples)
				sg = sum(s[1] for s in samples) // len(samples)
				sb = sum(s[2] for s in samples) // len(samples)
				px[x, y] = (sr, sg, sb, a)
	return im


def content_bbox(im: Image.Image, alpha_thresh: int = 10) -> tuple[int, int, int, int]:
	alpha = im.split()[3]
	bbox = alpha.point(lambda a: 255 if a > alpha_thresh else 0).getbbox()
	return bbox or (0, 0, im.width, im.height)


def fit_square(im: Image.Image) -> Image.Image:
	left, top, right, bottom = content_bbox(im)
	cropped = im.crop((left, top, right, bottom))
	cw, ch = cropped.size
	pad = int(max(cw, ch) * PAD_RATIO)
	side = max(cw, ch) + pad * 2
	canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
	canvas.paste(cropped, ((side - cw) // 2, (side - ch) // 2), cropped)
	return canvas.resize((TARGET, TARGET), Image.Resampling.LANCZOS)


def clean_fringe(im: Image.Image) -> Image.Image:
	px = im.load()
	w, h = im.size
	for y in range(h):
		for x in range(w):
			r, g, b, a = px[x, y]
			if a == 0:
				continue
			if _is_bg(r, g, b, luma_min=225.0, chroma_max=22.0):
				px[x, y] = (0, 0, 0, 0)
	return im


def process_one(src_name: str, dst_name: str) -> None:
	src = SRC_DIR / src_name
	out = clean_fringe(fit_square(despeckle_dark(remove_backdrop(Image.open(src)))))
	# Mild sharpen after resize for hub readability.
	r, g, b, a = out.split()
	rgb = Image.merge("RGB", (r, g, b)).filter(
		ImageFilter.UnsharpMask(radius=1.0, percent=90, threshold=3)
	)
	out = Image.merge("RGBA", (*rgb.split(), a))
	DST_DIR.mkdir(parents=True, exist_ok=True)
	dst = DST_DIR / dst_name
	out.save(dst, "PNG", optimize=True)
	print(f"{dst_name}: {out.size}")


def main() -> None:
	process_one("icon_wood_raw.png", "icon_wood.png")
	process_one("icon_gold_raw.png", "icon_gold.png")
	process_one("icon_food_raw.png", "icon_food.png")
	# Preview strip at hub size on dark panel.
	panel = Image.new("RGBA", (240, 100), (31, 26, 19, 255))
	x = 16
	for name in ("icon_gold.png", "icon_wood.png", "icon_food.png"):
		im = Image.open(DST_DIR / name).convert("RGBA").resize((56, 56), Image.Resampling.LANCZOS)
		panel.paste(im, (x, 22), im)
		x += 74
	panel.save(DST_DIR / "hub_preview.png")
	print("hub_preview.png written")


if __name__ == "__main__":
	main()
