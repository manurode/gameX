"""Rebuild depleted forest/mountain PNGs with clean alpha and exact canvas size."""
from __future__ import annotations

from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image

DECOR = Path(r"C:\Repos\gameX\assets\tilesets\mediterranean\Decor")
GEN = Path(r"C:\Users\Manu\.cursor\projects\c-Repos-gameX\assets")

FORESTS = [
	("forest_a", (1100, 640)),
	("forest_b", (1050, 720)),
	("forest_c", (980, 760)),
]
MOUNTAINS = [
	("mountain_a", (1100, 642)),
	("mountain_b", (1025, 732)),
	("mountain_c", (896, 824)),
]


def is_background_rgb(r: int, g: int, b: int) -> bool:
	mx = max(r, g, b)
	mn = min(r, g, b)
	# Near-black (tool solid bg)
	if mx <= 32:
		return True
	# Near-white / light checker square
	if mn >= 230:
		return True
	# Low-chroma light gray (checkerboard mid tones)
	if (mx - mn) <= 28 and mn >= 145:
		return True
	return False


def flood_clear_background(arr: np.ndarray) -> np.ndarray:
	"""Make edge-connected background pixels fully transparent."""
	h, w = arr.shape[:2]
	out = arr.copy()
	bg = np.zeros((h, w), dtype=bool)
	for y in range(h):
		for x in range(w):
			r, g, b, a = out[y, x]
			if a < 8 or is_background_rgb(int(r), int(g), int(b)):
				bg[y, x] = True

	seen = np.zeros((h, w), dtype=bool)
	q: deque[tuple[int, int]] = deque()
	for x in range(w):
		for y in (0, h - 1):
			if bg[y, x] and not seen[y, x]:
				seen[y, x] = True
				q.append((x, y))
	for y in range(h):
		for x in (0, w - 1):
			if bg[y, x] and not seen[y, x]:
				seen[y, x] = True
				q.append((x, y))

	while q:
		x, y = q.popleft()
		out[y, x, 3] = 0
		for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			if seen[ny, nx] or not bg[ny, nx]:
				continue
			seen[ny, nx] = True
			q.append((nx, ny))
	return out


def content_bbox(arr: np.ndarray, alpha_min: int = 12) -> tuple[int, int, int, int]:
	ys, xs = np.where(arr[:, :, 3] > alpha_min)
	if len(xs) == 0:
		return (0, 0, arr.shape[1], arr.shape[0])
	return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def fit_to_original(gen_rgba: np.ndarray, orig: Image.Image) -> Image.Image:
	"""Place cleaned generated art onto the original canvas, bottom-aligned to orig content."""
	orig_a = np.array(orig.convert("RGBA"))
	ob = content_bbox(orig_a)
	gb = content_bbox(gen_rgba)
	crop = gen_rgba[gb[1] : gb[3], gb[0] : gb[2]]
	ow = ob[2] - ob[0]
	oh = ob[3] - ob[1]
	scale = min(ow / max(crop.shape[1], 1), oh / max(crop.shape[0], 1))
	nw = max(1, int(round(crop.shape[1] * scale)))
	nh = max(1, int(round(crop.shape[0] * scale)))
	cropped = Image.fromarray(crop, "RGBA").resize((nw, nh), Image.Resampling.LANCZOS)
	canvas = Image.new("RGBA", orig.size, (0, 0, 0, 0))
	ox_center = (ob[0] + ob[2]) // 2
	paste_x = int(np.clip(ox_center - nw // 2, 0, orig.width - nw))
	paste_y = int(np.clip(ob[3] - nh, 0, orig.height - nh))
	canvas.paste(cropped, (paste_x, paste_y), cropped)

	# Force footprint: nothing outside a dilated original silhouette.
	orig_alpha = orig_a[:, :, 3]
	# Dilate a bit so stumps/rubble near edges aren't clipped harshly.
	dilated = orig_alpha.copy()
	for _ in range(2):
		pad = np.pad(dilated, 1, mode="edge")
		dilated = np.maximum.reduce(
			[
				pad[1:-1, 1:-1],
				pad[:-2, 1:-1],
				pad[2:, 1:-1],
				pad[1:-1, :-2],
				pad[1:-1, 2:],
			]
		)
	out = np.array(canvas)
	# Soft mask: keep generated alpha only where original (dilated) had content.
	out[:, :, 3] = (out[:, :, 3].astype(np.float32) * (dilated.astype(np.float32) / 255.0)).astype(
		np.uint8
	)
	# Kill leftover near-white that somehow survived inside the mask fringe.
	rgb = out[:, :, :3].astype(np.int16)
	whiteish = (out[:, :, 3] > 0) & (rgb.min(axis=2) >= 235) & ((rgb.max(axis=2) - rgb.min(axis=2)) <= 20)
	out[whiteish, 3] = 0
	return Image.fromarray(out, "RGBA")


def make_mountain_empty_from_original(orig: Image.Image) -> Image.Image:
	"""Edit original mountain: strip gold veins into dark hollows, keep exact footprint."""
	arr = np.array(orig.convert("RGBA"), dtype=np.float32)
	rgb = arr[:, :, :3]
	alpha = arr[:, :, 3]
	r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
	# Gold / yellow vein detector (bright yellow, low blue).
	gold = (alpha > 20) & (r > 150) & (g > 120) & (b < 110) & ((r + g) > (b * 3.2))
	# Warm highlight that is still ore-like
	gold |= (alpha > 20) & (r > 180) & (g > 140) & (b < 130) & ((r - b) > 60) & ((g - b) > 30)

	# Replace gold with dark recessed rock (hollowed mine look).
	dark = np.stack(
		[
			np.full_like(r, 48.0),
			np.full_like(g, 28.0),
			np.full_like(b, 18.0),
		],
		axis=2,
	)
	# Slight variation from neighboring rock luminance.
	luma = 0.3 * r + 0.5 * g + 0.2 * b
	dark[:, :, 0] = np.clip(32 + luma * 0.08, 20, 70)
	dark[:, :, 1] = np.clip(20 + luma * 0.05, 12, 50)
	dark[:, :, 2] = np.clip(14 + luma * 0.04, 8, 40)

	out = arr.copy()
	out[gold, :3] = dark[gold]
	# Slight overall desaturation so it reads as spent ore, not shiny rock.
	opaque = alpha > 20
	mean = out[:, :, :3].mean(axis=2, keepdims=True)
	out[opaque, :3] = out[opaque, :3] * 0.92 + mean[opaque] * 0.08
	# Darken former gold crevices' neighbors a touch for depth.
	from scipy import ndimage  # optional; fallback below

	try:
		gold_dilated = ndimage.binary_dilation(gold, iterations=2)
		ring = gold_dilated & ~gold & opaque
		out[ring, :3] *= 0.78
	except Exception:
		pass

	out[:, :, 3] = alpha
	return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA")


def make_mountain_empty_no_scipy(orig: Image.Image) -> Image.Image:
	arr = np.array(orig.convert("RGBA"), dtype=np.float32)
	rgb = arr[:, :, :3]
	alpha = arr[:, :, 3]
	r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
	gold = (alpha > 20) & (r > 150) & (g > 120) & (b < 110) & ((r + g) > (b * 3.2))
	gold |= (alpha > 20) & (r > 180) & (g > 140) & (b < 130) & ((r - b) > 60) & ((g - b) > 30)
	luma = 0.3 * r + 0.5 * g + 0.2 * b
	dark = np.zeros_like(rgb)
	dark[:, :, 0] = np.clip(32 + luma * 0.08, 20, 70)
	dark[:, :, 1] = np.clip(20 + luma * 0.05, 12, 50)
	dark[:, :, 2] = np.clip(14 + luma * 0.04, 8, 40)
	out = arr.copy()
	out[gold, :3] = dark[gold]
	opaque = alpha > 20
	mean = out[:, :, :3].mean(axis=2, keepdims=True)
	out[opaque, :3] = out[opaque, :3] * 0.90 + mean[opaque] * 0.10
	# Manual 1px darken around gold
	gold_u8 = gold.astype(np.uint8)
	pad = np.pad(gold_u8, 1, mode="constant")
	neigh = (
		pad[:-2, 1:-1]
		| pad[2:, 1:-1]
		| pad[1:-1, :-2]
		| pad[1:-1, 2:]
		| pad[:-2, :-2]
		| pad[:-2, 2:]
		| pad[2:, :-2]
		| pad[2:, 2:]
	).astype(bool)
	ring = neigh & ~gold & opaque
	out[ring, :3] *= 0.75
	out[:, :, 3] = alpha
	return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA")


def process_forest(name: str, size: tuple[int, int]) -> None:
	orig = Image.open(DECOR / f"{name}.png").convert("RGBA")
	assert orig.size == size, (name, orig.size, size)
	gen_path = GEN / f"{name}_empty.png"
	if not gen_path.exists():
		raise FileNotFoundError(gen_path)
	gen = np.array(Image.open(gen_path).convert("RGBA"))
	gen = flood_clear_background(gen)
	out = fit_to_original(gen, orig)
	out_path = DECOR / f"{name}_empty.png"
	out.save(out_path)
	oa = np.array(out)
	white = (
		(oa[:, :, 3] > 200)
		& (oa[:, :, :3].min(axis=2) >= 230)
		& ((oa[:, :, :3].max(axis=2) - oa[:, :, :3].min(axis=2)) <= 20)
	)
	print(f"{name}_empty: {out.size} opaque={(oa[:,:,3]>10).sum()} white_left={white.sum()}")


def process_mountain(name: str, size: tuple[int, int]) -> None:
	orig = Image.open(DECOR / f"{name}.png").convert("RGBA")
	assert orig.size == size, (name, orig.size, size)
	# Prefer edited original (exact footprint). Also keep a gen-based variant merged for cave look.
	base = make_mountain_empty_no_scipy(orig)
	gen_path = GEN / f"{name}_empty.png"
	if gen_path.exists():
		gen = flood_clear_background(np.array(Image.open(gen_path).convert("RGBA")))
		gen_fit = fit_to_original(gen, orig)
		# Blend: use gen where it has strong alpha AND is not white; keep base alpha from original.
		base_a = np.array(base)
		gen_a = np.array(gen_fit)
		orig_a = np.array(orig)
		# Where gen has content inside original silhouette, prefer gen RGB (hollow caves).
		use_gen = (gen_a[:, :, 3] > 40) & (orig_a[:, :, 3] > 20)
		# Avoid gen white bleed
		g_rgb = gen_a[:, :, :3].astype(np.int16)
		use_gen &= ~(
			(g_rgb.min(axis=2) >= 220) & ((g_rgb.max(axis=2) - g_rgb.min(axis=2)) <= 25)
		)
		out = base_a.copy()
		out[use_gen, :3] = gen_a[use_gen, :3]
		# Always keep original alpha exactly — same footprint, same place.
		out[:, :, 3] = orig_a[:, :, 3]
		base = Image.fromarray(out, "RGBA")
	out_path = DECOR / f"{name}_empty.png"
	base.save(out_path)
	oa = np.array(base)
	print(f"{name}_empty: {base.size} opaque={(oa[:,:,3]>10).sum()} (alpha locked to original)")


def main() -> None:
	for name, size in FORESTS:
		process_forest(name, size)
	for name, size in MOUNTAINS:
		process_mountain(name, size)
	print("done")


if __name__ == "__main__":
	main()
