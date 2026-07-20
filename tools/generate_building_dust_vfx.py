"""Generate painterly building-dust VFX matching mediterranean building art style."""
from __future__ import annotations

import math
import os
import random

from PIL import Image, ImageDraw

OUT = os.path.normpath(
	os.path.join(
		os.path.dirname(__file__),
		"..",
		"assets",
		"tilesets",
		"tiny_tiles",
		"VFX",
		"VFX_building_dust.png",
	)
)

FRAME = 256
N_FRAMES = 8

# Stucco / masonry dust — same family as house_small
HIGHLIGHT = (248, 238, 220)
MID = (228, 208, 178)
SHADE = (198, 170, 138)
DEEP = (158, 128, 98)
RIM = (132, 104, 78)
PEBBLE = (112, 88, 66)


def _clamp(v: float, lo: float = 0.0, hi: float = 1.0) -> float:
	return max(lo, min(hi, v))


def _lerp_color(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
	t = _clamp(t)
	return (
		int(a[0] + (b[0] - a[0]) * t),
		int(a[1] + (b[1] - a[1]) * t),
		int(a[2] + (b[2] - a[2]) * t),
	)


def paint_lobe(
	img: Image.Image,
	cx: float,
	cy: float,
	rx: float,
	ry: float,
	alpha: float,
	rng: random.Random,
) -> None:
	"""Cel-soft painted puff: crisp silhouette, soft internal shading, no mushy blur."""
	if rx < 2 or ry < 2 or alpha <= 0.01:
		return
	layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
	px = layer.load()
	w, h = img.size
	# Mild irregularity so lobes aren't perfect circles
	warp_x = rng.uniform(-0.08, 0.08)
	warp_y = rng.uniform(-0.08, 0.08)
	x0 = max(0, int(cx - rx - 3))
	x1 = min(w, int(cx + rx + 4))
	y0 = max(0, int(cy - ry - 3))
	y1 = min(h, int(cy + ry + 4))
	for y in range(y0, y1):
		for x in range(x0, x1):
			nx = (x - cx) / rx
			ny = (y - cy) / ry
			# Squircle-ish warp for painterly blob
			d = math.sqrt((nx * nx) ** 1.05 + (ny * ny) ** 1.05)
			d += warp_x * nx * ny + warp_y * nx
			if d > 1.0:
				continue
			# Harder edge than gaussian smoke
			if d > 0.88:
				edge = _clamp((1.0 - d) / 0.12)
			else:
				edge = 1.0
			light = _clamp(0.52 + (-nx * 0.4 - ny * 0.5))
			if d > 0.82:
				rgb = RIM
			elif light > 0.7:
				rgb = HIGHLIGHT
			elif light > 0.48:
				rgb = _lerp_color(MID, HIGHLIGHT, (light - 0.48) / 0.22)
			elif light > 0.3:
				rgb = _lerp_color(SHADE, MID, (light - 0.3) / 0.18)
			else:
				rgb = DEEP
			a = int(255 * alpha * edge)
			if a <= 0:
				continue
			prev = px[x, y]
			if prev[3] == 0:
				px[x, y] = (*rgb, a)
			else:
				# Overpaint with higher alpha preference for denser cores
				oa = prev[3] / 255.0
				na = a / 255.0
				out_a = oa + na * (1.0 - oa)
				if out_a <= 0:
					continue
				t = na / out_a
				px[x, y] = (
					int(prev[0] + (rgb[0] - prev[0]) * t),
					int(prev[1] + (rgb[1] - prev[1]) * t),
					int(prev[2] + (rgb[2] - prev[2]) * t),
					int(out_a * 255),
				)
	img.alpha_composite(layer)


def paint_pebbles(
	img: Image.Image,
	cx: float,
	cy: float,
	spread: float,
	count: int,
	alpha: float,
	rng: random.Random,
) -> None:
	draw = ImageDraw.Draw(img)
	for _ in range(count):
		px = cx + rng.uniform(-spread, spread)
		py = cy + rng.uniform(-spread * 0.2, spread * 0.3)
		rad = rng.uniform(1.0, 2.4)
		a = int(220 * alpha * rng.uniform(0.55, 1.0))
		draw.ellipse([px - rad, py - rad, px + rad, py + rad], fill=(*PEBBLE, a))


def make_frame(fi: int) -> Image.Image:
	rng = random.Random(77 + fi * 13)
	frame = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
	t = fi / (N_FRAMES - 1)

	expand = 0.3 + 0.7 * (1.0 - (1.0 - min(t / 0.48, 1.0)) ** 1.5)
	if t < 0.14:
		alpha = t / 0.14
	elif t < 0.5:
		alpha = 1.0
	else:
		alpha = max(0.0, 1.0 - (t - 0.5) / 0.5) ** 0.75

	cx = FRAME * 0.5
	cy = FRAME * 0.6
	base_r = FRAME * 0.17 * expand

	lobes: list[tuple[float, float, float, float, float]] = [
		(cx, cy - base_r * 0.25, base_r * 1.4, base_r * 1.05, 1.0),
		(cx - base_r * 0.95, cy, base_r * 1.0, base_r * 0.82, 0.95),
		(cx + base_r * 1.0, cy - base_r * 0.05, base_r * 1.05, base_r * 0.88, 0.95),
		(cx - base_r * 0.15, cy - base_r * 1.05, base_r * 0.95, base_r * 0.95, 0.9),
		(cx + base_r * 0.4, cy - base_r * 1.4, base_r * 0.75, base_r * 0.8, 0.85),
		(cx, cy - base_r * 1.85, base_r * 0.58, base_r * 0.62, 0.75),
		(cx - base_r * 1.55, cy + base_r * 0.2, base_r * 0.7, base_r * 0.5, 0.8),
		(cx + base_r * 1.6, cy + base_r * 0.25, base_r * 0.72, base_r * 0.52, 0.8),
	]
	if 0.12 < t < 0.72:
		for _ in range(5):
			ang = rng.uniform(-2.5, -0.6)
			dist = rng.uniform(0.35, 1.15) * base_r
			lobes.append(
				(
					cx + math.cos(ang) * dist * 1.35,
					cy + math.sin(ang) * dist * 0.85 - base_r * 0.35,
					base_r * rng.uniform(0.32, 0.58),
					base_r * rng.uniform(0.28, 0.52),
					rng.uniform(0.6, 0.9),
				)
			)

	for lx, ly, rx, ry, mul in lobes:
		paint_lobe(frame, lx, ly, rx, ry, alpha * mul, rng)

	if t > 0.55:
		settle = (t - 0.55) / 0.45
		for side in (-1.15, 0.0, 1.15):
			paint_lobe(
				frame,
				cx + side * base_r * (1.0 + settle * 0.35),
				cy + base_r * (0.25 + settle * 0.2),
				base_r * (0.95 - settle * 0.25),
				base_r * (0.32 - settle * 0.08),
				alpha * (0.65 - settle * 0.2),
				rng,
			)

	paint_pebbles(frame, cx, cy + base_r * 0.55, base_r * 1.35, int(5 + 12 * expand * alpha), alpha, rng)
	return frame


def main() -> void:
	os.makedirs(os.path.dirname(OUT), exist_ok=True)
	sheet = Image.new("RGBA", (FRAME * N_FRAMES, FRAME), (0, 0, 0, 0))
	for fi in range(N_FRAMES):
		sheet.paste(make_frame(fi), (fi * FRAME, 0), make_frame(fi))
	sheet.save(OUT)
	print(f"Wrote {OUT} {sheet.size}")


# Fix typo - main shouldn't use void
def run() -> None:
	os.makedirs(os.path.dirname(OUT), exist_ok=True)
	sheet = Image.new("RGBA", (FRAME * N_FRAMES, FRAME), (0, 0, 0, 0))
	for fi in range(N_FRAMES):
		frame = make_frame(fi)
		sheet.paste(frame, (fi * FRAME, 0), frame)
	sheet.save(OUT)
	print(f"Wrote {OUT} {sheet.size}")


if __name__ == "__main__":
	run()
