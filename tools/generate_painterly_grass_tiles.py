#!/usr/bin/env python3
"""Generate Wang/blob isometric grass that hides the diamond grid.

Goal (like seamless top-down meadows): same-terrain neighbors must look like ONE
continuous field — no rim/halo per diamond. Different terrains meet as organic
blobs that cross tile boundaries.

Method:
  1. Build TWO shared materials (dense / soft) — identical on every tile.
  2. Each Wang code is only a soft-mask: where soft meadow sits vs dense grass.
  3. Mask is pinned to edge codes so neighbors agree on the shared facet, then
     warped into an organic blob in the interior (never a border frame).

Godot TILE_LAYOUT_DIAMOND_RIGHT edge → diamond facet:
  N (0,-1) → top-right    (top → right)
  E (+1,0) → bottom-right (right → bottom)
  S (0,+1) → bottom-left  (left → bottom)
  W (-1,0) → top-left     (top → left)
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
EXTRUDE_PX = 2
ACCENT_MARGIN = 10

DENSE = 0
SOFT = 1

TOP = (128.0, 0.0)
RIGHT = (256.0, 64.0)
BOTTOM = (128.0, 128.0)
LEFT = (0.0, 64.0)

EDGE_GEOM = {
	"N": (TOP, RIGHT),
	"E": (RIGHT, BOTTOM),
	"S": (LEFT, BOTTOM),
	"W": (TOP, LEFT),
}
EDGE_ORDER = ("N", "E", "S", "W")

PRESS_STEM = "grass_press"
TARGET_MEAN = np.array([92.0, 122.0, 55.0], dtype=np.float32)
DENSE_TINT = np.array([70.0, 116.0, 40.0], dtype=np.float32)
SOFT_TINT = np.array([110.0, 140.0, 68.0], dtype=np.float32)


def _hash_seed(*parts: object) -> int:
	key = ":".join(str(p) for p in parts)
	return int(hashlib.md5(key.encode()).hexdigest()[:8], 16)


def wang_stem(n: int, e: int, s: int, w: int) -> str:
	return f"grass_w{n}{e}{s}{w}"


def wang_index(n: int, e: int, s: int, w: int) -> int:
	return (n << 3) | (e << 2) | (s << 1) | w


def decode_wang(idx: int) -> tuple[int, int, int, int]:
	return ((idx >> 3) & 1, (idx >> 2) & 1, (idx >> 1) & 1, idx & 1)


def all_wang_stems() -> list[str]:
	return [wang_stem(*decode_wang(i)) for i in range(16)]


def load_diamond_mask() -> np.ndarray:
	ref = np.array(Image.open(TERRAIN / "grass_a.png").convert("RGBA"))
	return ref[:, :, 3].astype(np.float32)


def load_source_textures() -> list[np.ndarray]:
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
	th, tw = tex.shape[:2]
	scale = float(rng.uniform(0.65, 1.05))
	src_w = int(out_w / scale)
	src_h = int(out_h / scale)
	src_w = min(src_w, tw - 4)
	src_h = min(src_h, th - 4)
	x0 = int(rng.integers(0, max(tw - src_w, 1)))
	y0 = int(rng.integers(0, max(th - src_h, 1)))
	patch = tex[y0 : y0 + src_h, x0 : x0 + src_w]
	pil = Image.fromarray(np.clip(patch, 0, 255).astype(np.uint8), "RGB")
	angle = float(rng.uniform(-8, 8))
	pil = pil.rotate(angle, resample=Image.Resampling.BICUBIC, expand=True, fillcolor=(90, 120, 50))
	pil = pil.resize((out_w, out_h), Image.Resampling.LANCZOS)
	if rng.random() < 0.5:
		pil = pil.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
	return np.array(pil).astype(np.float32)


def suppress_large_props(rgb: np.ndarray, mask_opaque: np.ndarray) -> np.ndarray:
	out = rgb.copy()
	lum = 0.299 * out[:, :, 0] + 0.587 * out[:, :, 1] + 0.114 * out[:, :, 2]
	smooth = ndimage.gaussian_filter(lum, sigma=3.0)
	delta = np.abs(lum - smooth)
	hot = mask_opaque & (delta > 28)
	if not hot.any():
		return out
	blurred = np.stack(
		[ndimage.gaussian_filter(out[:, :, c], sigma=2.5) for c in range(3)],
		axis=-1,
	)
	weight = np.clip((delta - 22.0) / 30.0, 0.0, 0.75)
	w = weight[..., None]
	out[hot] = out[hot] * (1.0 - w[hot]) + blurred[hot] * w[hot]
	return out


def _point_to_segment(
	px: np.ndarray,
	py: np.ndarray,
	ax: float,
	ay: float,
	bx: float,
	by: float,
) -> tuple[np.ndarray, np.ndarray]:
	abx, aby = bx - ax, by - ay
	apx, apy = px - ax, py - ay
	ab2 = abx * abx + aby * aby
	t = np.clip((apx * abx + apy * aby) / ab2, 0.0, 1.0)
	cx = ax + t * abx
	cy = ay + t * aby
	dist = np.sqrt((px - cx) ** 2 + (py - cy) ** 2)
	return dist.astype(np.float32), t.astype(np.float32)


def _build_material(
	sources: list[np.ndarray],
	kind: int,
	opaque: np.ndarray,
) -> np.ndarray:
	"""One shared fill texture per terrain kind — reused by every Wang tile."""
	rng = np.random.default_rng(_hash_seed("shared_mat", kind, 42))
	a = sample_patch(sources[int(rng.integers(0, len(sources)))], rng, W, H)
	b = sample_patch(sources[int(rng.integers(0, len(sources)))], rng, W, H)
	mix = value_noise((H, W), 16, rng)[..., None]
	rgb = a * (0.55 + 0.35 * mix) + b * (0.45 - 0.35 * mix)
	rgb = suppress_large_props(rgb, opaque)
	grain = (value_noise((H, W), 3, rng) - 0.5) * 9.0
	rgb += grain[..., None] * np.array([0.7, 1.0, 0.5], dtype=np.float32)
	tint = SOFT_TINT if kind == SOFT else DENSE_TINT
	# Dense reads darker/richer; soft reads sunnier — but same family.
	if kind == DENSE:
		rgb = rgb * 0.72 + tint * 0.28
		rgb *= 0.90
	else:
		rgb = rgb * 0.68 + tint * 0.32
		rgb = rgb * 1.06 + np.array([10.0, 8.0, 5.0], dtype=np.float32)
	rgb = np.clip(rgb, 0, 255).astype(np.float32)
	# Critical: opposite diamond edges must match so copies of this material
	# abut without a texture jump (E↔W, N↔S in Godot diamond-right).
	return make_diamond_self_seamless(rgb, opaque)


def _edge_points(edge_name: str, t: float, inset: float) -> tuple[int, int]:
	(ax, ay), (bx, by) = EDGE_GEOM[edge_name]
	x = ax + (bx - ax) * t
	y = ay + (by - ay) * t
	# Step toward diamond center so we sample opaque texels.
	cx, cy = 128.0, 64.0
	vx, vy = cx - x, cy - y
	norm = max((vx * vx + vy * vy) ** 0.5, 1e-6)
	x += vx / norm * inset
	y += vy / norm * inset
	return int(np.clip(round(x), 0, W - 1)), int(np.clip(round(y), 0, H - 1))


def make_diamond_self_seamless(rgb: np.ndarray, opaque: np.ndarray, band: int = 18) -> np.ndarray:
	"""Force E↔W and N↔S edge strips to agree so the tile self-tiles in iso."""
	out = rgb.copy()
	pairs = (("E", "W"), ("N", "S"))
	ts = np.linspace(0.01, 0.99, 160)
	# Two passes: first average, then force outer pixels identical.
	for _pass in range(2):
		for edge_a, edge_b in pairs:
			for t in ts:
				for inset in range(band):
					# Outer pixels must be identical; deeper band blends gently.
					if inset <= 3:
						strength = 1.0
					else:
						strength = (1.0 - (inset - 3) / float(band - 3)) ** 1.1
					xa, ya = _edge_points(edge_a, float(t), float(inset) + 0.8)
					xb, yb = _edge_points(edge_b, float(t), float(inset) + 0.8)
					if not opaque[ya, xa] or not opaque[yb, xb]:
						continue
					avg = (out[ya, xa] + out[yb, xb]) * 0.5
					out[ya, xa] = out[ya, xa] * (1.0 - strength) + avg * strength
					out[yb, xb] = out[yb, xb] * (1.0 - strength) + avg * strength
	return np.clip(out, 0, 255).astype(np.float32)


def wang_soft_mask(codes: tuple[int, int, int, int]) -> np.ndarray:
	"""Soft-amount field in [0,1]. Edge-pinned, organically blended inside.

	All-dense → 0 everywhere (pure shared dense material → invisible grid).
	All-soft  → 1 everywhere.
	Mixed     → organic blob crossing the tile, continuous with neighbors.
	"""
	n, e, s, w = codes
	types = {"N": float(n), "E": float(e), "S": float(s), "W": float(w)}
	ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)

	dists: dict[str, np.ndarray] = {}
	for name in EDGE_ORDER:
		(ax, ay), (bx, by) = EDGE_GEOM[name]
		d, _t = _point_to_segment(xs, ys, ax, ay, bx, by)
		dists[name] = d

	# Inverse-distance blend of the four edge constraints.
	eps = 2.5
	num = np.zeros((H, W), dtype=np.float32)
	den = np.zeros((H, W), dtype=np.float32)
	for name in EDGE_ORDER:
		wt = 1.0 / np.maximum(dists[name], eps) ** 2
		num += wt * types[name]
		den += wt
	field = num / np.maximum(den, 1e-6)

	uniform = n == e == s == w
	if not uniform:
		# Warp into a blob — seeded only by the Wang code so it's stable.
		rng = np.random.default_rng(_hash_seed("blobwarp", n, e, s, w))
		warp = value_noise((H, W), 14, rng)
		warp = ndimage.gaussian_filter(warp, sigma=2.0)
		# Stronger warp away from edges so seams stay pinned.
		min_dist = np.minimum(
			np.minimum(dists["N"], dists["E"]),
			np.minimum(dists["S"], dists["W"]),
		)
		interior = np.clip((min_dist - 6.0) / 28.0, 0.0, 1.0)
		field = np.clip(field + (warp - 0.5) * 0.55 * interior, 0.0, 1.0)
		# Soft threshold → crisp but organic meadow boundary (like ref blobs).
		field = ndimage.gaussian_filter(field, sigma=1.2)
		lo, hi = 0.38, 0.62
		field = np.clip((field - lo) / (hi - lo), 0.0, 1.0)
		field = field * field * (3.0 - 2.0 * field)

	# Pin a thin band on each facet to the exact edge code (neighbor match).
	pin_px = 5.0
	for name in EDGE_ORDER:
		near = dists[name] <= pin_px
		# Smooth pin: full force at 0, release by pin_px.
		strength = np.clip(1.0 - dists[name] / pin_px, 0.0, 1.0)
		field = np.where(near, field * (1.0 - strength) + types[name] * strength, field)

	return field.astype(np.float32)


def paint_wang_tile(
	mask: np.ndarray,
	codes: tuple[int, int, int, int],
	materials: dict[int, np.ndarray],
	press: bool = False,
) -> np.ndarray:
	n, e, s, w = codes
	opaque = mask >= 128.0
	# 1px overlap between neighboring diamonds kills hairline cracks that read as a grid.
	opaque_draw = ndimage.binary_dilation(opaque, iterations=1)
	out = np.zeros((H, W, 4), dtype=np.float32)
	out[:, :, 3] = np.where(opaque_draw, 255.0, 0.0)

	soft_m = wang_soft_mask(codes)
	rgb = materials[DENSE] * (1.0 - soft_m[..., None]) + materials[SOFT] * soft_m[..., None]
	# Fill the dilated ring from nearest opaque texel (same as extrude).
	if opaque_draw.any() and (~opaque & opaque_draw).any():
		inds = ndimage.distance_transform_edt(~opaque, return_distances=False, return_indices=True)
		ring = opaque_draw & ~opaque
		rgb[ring] = rgb[inds[0][ring], inds[1][ring]]

	# Sparse accents only deep inside, and only on soft meadow (like ref flowers).
	if not press:
		rng = np.random.default_rng(_hash_seed("accent", n, e, s, w))
		dist_in = ndimage.distance_transform_edt(opaque)
		interior = opaque & (dist_in > float(ACCENT_MARGIN)) & (soft_m > 0.55)
		if interior.any():
			ys_i, xs_i = np.where(interior)
			n_pick = min(8 if (n + e + s + w) >= 2 else 3, len(ys_i))
			if n_pick > 0:
				pick = rng.choice(len(ys_i), size=n_pick, replace=False)
				palette = [
					np.array([210.0, 95.0, 85.0]),
					np.array([230.0, 200.0, 80.0]),
					np.array([180.0, 145.0, 210.0]),
					np.array([245.0, 240.0, 220.0]),
				]
				for idx in pick:
					y, x = int(ys_i[idx]), int(xs_i[idx])
					col = palette[int(rng.integers(0, len(palette)))]
					rgb[y, x] = rgb[y, x] * 0.3 + col * 0.7

	if press:
		rgb = rgb * 0.78 + np.array([48.0, 68.0, 30.0], dtype=np.float32) * 0.22

	out[:, :, :3] = np.clip(rgb, 0, 255)
	out[~opaque] = 0
	return out


def extrude_rgb(image: np.ndarray, px: int = EXTRUDE_PX) -> np.ndarray:
	"""Bleed opaque RGB into the transparent fringe so filtering doesn't darken seams."""
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
		# Keep alpha 0 outside — extrude is only for filter sampling.
	return out


def mild_sharpen(image: np.ndarray) -> np.ndarray:
	pil = Image.fromarray(np.clip(image, 0, 255).astype(np.uint8), "RGBA")
	rgb = pil.convert("RGB").filter(
		ImageFilter.UnsharpMask(radius=1.0, percent=60, threshold=3)
	)
	arr = np.array(pil).astype(np.float32)
	arr[:, :, :3] = np.array(rgb).astype(np.float32)
	arr[:, :, 3] = image[:, :, 3]
	return arr


def write_iso_preview(tiles: list[np.ndarray], path: Path, cols: int, rows: int) -> None:
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


def _blit_iso(canvas: Image.Image, tile: np.ndarray, cell: tuple[int, int], origin: tuple[int, int]) -> None:
	cx, cy = cell
	px = origin[0] + (cx - cy) * 128
	py = origin[1] + (cx + cy) * 64
	spr = Image.fromarray(np.clip(tile, 0, 255).astype(np.uint8), "RGBA")
	canvas.alpha_composite(spr, (px, py))


def write_wang_match_preview(baked_by_idx: list[np.ndarray], path: Path) -> None:
	"""Left: pure dense field (must show NO grid). Right: soft blob into dense."""
	cw, ch = 1100, 560
	canvas = Image.new("RGBA", (cw, ch), (22, 26, 20, 255))

	dense = baked_by_idx[wang_index(DENSE, DENSE, DENSE, DENSE)]
	soft = baked_by_idx[wang_index(SOFT, SOFT, SOFT, SOFT)]

	# --- Pure dense 4x4: if the grid is visible here, art is wrong ---
	origin_a = (200, 40)
	for y in range(4):
		for x in range(4):
			_blit_iso(canvas, dense, (x, y), origin_a)

	# --- Soft meadow patch inside dense (valid Wang field) ---
	# Cell types: soft blob at (1,1),(2,1),(1,2) surrounded by dense.
	# Edge between two cells = SOFT only if BOTH are soft, else DENSE.
	# Actually for our edge-field wang: build from cell types with
	# edge = soft if either... use explicit codes that match.
	origin_b = (720, 40)

	def cell_type(x: int, y: int) -> int:
		return SOFT if (1 <= x <= 2 and 1 <= y <= 2) else DENSE

	# Derive edge-consistent Wang codes from cell types:
	# Shared edge type = type of the "from" cell toward neighbor is wrong when differing.
	# Use: edge between A and B gets type of A∩B when equal, else we put the
	# transition inside both via edge = neighbor's type on the facing side...
	# Simpler: edge type = SOFT iff at least one endpoint cell is SOFT? No that breaks.
	# Correct for material composite: edge type = the terrain that should appear
	# ON that edge. For two equal cells, that terrain. For unequal, pick one
	# consistently: use min() so dense(0) wins on boundaries → soft blobs shrink
	# inside soft cells. Or max() soft expands. Use: edge = type if equal else DENSE
	# with soft cells having soft interior via... hmm.
	#
	# Best for preview: manually set a known-good wang neighborhood.
	field = {
		# Pure dense surround
		(0, 0): wang_index(DENSE, DENSE, DENSE, DENSE),
		(1, 0): wang_index(DENSE, DENSE, SOFT, DENSE),  # S opens to soft below
		(2, 0): wang_index(DENSE, DENSE, SOFT, DENSE),
		(3, 0): wang_index(DENSE, DENSE, DENSE, DENSE),
		(0, 1): wang_index(DENSE, SOFT, DENSE, DENSE),  # E opens to soft
		(1, 1): wang_index(SOFT, SOFT, SOFT, SOFT),  # soft core — but edges must match!
	}
	# Rebuild properly from cell types with edge = cell_type of the cell that
	# "owns" the dual: edge H between (x,y-1)-(x,y) = SOFT if BOTH soft else
	# if one soft one dense → transition edge. Use OR (max): soft bleeds.
	cells_w, cells_h = 4, 4
	h_edge = [[DENSE] * cells_w for _ in range(cells_h + 1)]
	v_edge = [[DENSE] * (cells_w + 1) for _ in range(cells_h)]
	for y in range(cells_h + 1):
		for x in range(cells_w):
			above = cell_type(x, y - 1) if y > 0 else cell_type(x, y)
			below = cell_type(x, y) if y < cells_h else cell_type(x, y - 1)
			# Shared facet shows soft only when a soft cell touches it.
			h_edge[y][x] = SOFT if (above == SOFT or below == SOFT) else DENSE
	for y in range(cells_h):
		for x in range(cells_w + 1):
			left = cell_type(x - 1, y) if x > 0 else cell_type(x, y)
			right = cell_type(x, y) if x < cells_w else cell_type(x - 1, y)
			v_edge[y][x] = SOFT if (left == SOFT or right == SOFT) else DENSE

	# Fix boundary edges outside map to match the single cell.
	for y in range(cells_h + 1):
		for x in range(cells_w):
			if y == 0:
				h_edge[y][x] = cell_type(x, 0)
			if y == cells_h:
				h_edge[y][x] = cell_type(x, cells_h - 1)
	for y in range(cells_h):
		for x in range(cells_w + 1):
			if x == 0:
				v_edge[y][x] = cell_type(0, y)
			if x == cells_w:
				v_edge[y][x] = cell_type(cells_w - 1, y)

	for y in range(cells_h):
		for x in range(cells_w):
			nn = h_edge[y][x]
			ss = h_edge[y + 1][x]
			ww = v_edge[y][x]
			ee = v_edge[y][x + 1]
			idx = wang_index(nn, ee, ss, ww)
			_blit_iso(canvas, baked_by_idx[idx], (x, y), origin_b)

	# Tiny labels via color bars under each cluster
	path.parent.mkdir(parents=True, exist_ok=True)
	canvas.save(path)
	print(f"Wrote Wang match preview {path}")
	_ = soft  # kept for clarity / future label strip


def main() -> None:
	mask = load_diamond_mask()
	sources = load_source_textures()
	opaque = mask >= 128.0
	print(f"Target mean RGB: {TARGET_MEAN.round(1)}")
	print("Generating blob Wang grass (shared materials, no edge halos)")

	materials = {
		DENSE: _build_material(sources, DENSE, opaque),
		SOFT: _build_material(sources, SOFT, opaque),
	}
	# Pull both materials toward a common playable mean so seams don't flash.
	for kind in (DENSE, SOFT):
		op = opaque
		mean = materials[kind][op].mean(0)
		materials[kind][op] = np.clip(
			materials[kind][op] + (TARGET_MEAN - mean) * 0.35, 0, 255
		)

	stems = all_wang_stems()
	baked: list[np.ndarray] = []
	for i, stem in enumerate(stems):
		codes = decode_wang(i)
		tile = paint_wang_tile(mask, codes, materials, press=False)
		tile = mild_sharpen(tile)
		tile = extrude_rgb(tile)
		baked.append(tile)
		Image.fromarray(np.clip(tile, 0, 255).astype(np.uint8)).save(TERRAIN / f"{stem}_field.png")
		Image.fromarray(np.clip(tile, 0, 255).astype(np.uint8)).save(TERRAIN / f"{stem}.png")
		mean = tile[tile[:, :, 3] >= 128, :3].mean(0)
		print(f"Wrote {stem} edges=NESW{codes} mean={mean.round(1)}")

	press = paint_wang_tile(mask, (SOFT, SOFT, SOFT, SOFT), materials, press=True)
	press = mild_sharpen(press)
	press = extrude_rgb(press)
	baked.append(press)
	Image.fromarray(np.clip(press, 0, 255).astype(np.uint8)).save(TERRAIN / f"{PRESS_STEM}_field.png")
	Image.fromarray(np.clip(press, 0, 255).astype(np.uint8)).save(TERRAIN / f"{PRESS_STEM}.png")
	print(f"Wrote {PRESS_STEM}")

	floor = baked[:16]
	write_iso_preview(floor, PREVIEW / "painterly_grass_grid.png", cols=4, rows=4)
	write_iso_preview([floor[0]] * 16, PREVIEW / "painterly_grass_same_tile.png", cols=4, rows=4)
	write_wang_match_preview(floor, PREVIEW / "wang_grass_match.png")
	write_iso_preview(
		[
			floor[wang_index(DENSE, DENSE, DENSE, DENSE)],
			floor[wang_index(DENSE, DENSE, SOFT, DENSE)],
			floor[wang_index(SOFT, SOFT, SOFT, SOFT)],
			floor[wang_index(SOFT, DENSE, DENSE, SOFT)],
		]
		* 4,
		PREVIEW / "painterly_grass_mixed.png",
		cols=4,
		rows=4,
	)


if __name__ == "__main__":
	main()
