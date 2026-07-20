"""Normalize building phase sprites to match complete content size/placement.

Damaged/construction phases were fit with an 8% size margin, so some buildings
visibly grow on phase swap. Rescales each phase PNG to the complete sprite's
opaque content box (uniform scale, bottom-center aligned).

Plot phases are skipped — foundations are intentionally smaller.
"""

from __future__ import annotations

import shutil
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(r"C:\Repos\gameX")
BUILDINGS_DIR = ROOT / "assets" / "tilesets" / "mediterranean" / "Buildings"
BACKUP_DIR = ROOT / "assets" / "_archive" / "phase_pre_size_norm"

ALPHA_THRESH = 16
PHASES = ("damaged", "construction")


def content_bounds(arr: np.ndarray, thresh: int = ALPHA_THRESH):
	a = arr[..., 3]
	ys, xs = np.where(a > thresh)
	if len(xs) == 0:
		return None
	return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def normalize_to_complete(complete: Image.Image, phase_img: Image.Image) -> tuple[Image.Image, float]:
	ref = np.asarray(complete.convert("RGBA"))
	src = np.asarray(phase_img.convert("RGBA"))
	tw, th = ref.shape[1], ref.shape[0]

	rb = content_bounds(ref)
	sb = content_bounds(src)
	if rb is None or sb is None:
		return Image.fromarray(src, "RGBA"), 1.0

	rx0, ry0, rx1, ry1 = rb
	sx0, sy0, sx1, sy1 = sb
	rw, rh = rx1 - rx0, ry1 - ry0
	sw, sh = sx1 - sx0, sy1 - sy0

	scale = min(rw / sw, rh / sh)
	nw = max(1, int(round(sw * scale)))
	nh = max(1, int(round(sh * scale)))

	cropped = Image.fromarray(src[sy0:sy1, sx0:sx1], "RGBA")
	resized = cropped.resize((nw, nh), Image.Resampling.LANCZOS)

	ox = rx0 + (rw - nw) // 2
	oy = ry1 - nh

	canvas = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
	canvas.paste(resized, (ox, oy), resized)
	return canvas, scale


def main() -> None:
	BACKUP_DIR.mkdir(parents=True, exist_ok=True)
	fixed = 0
	for phase in PHASES:
		for path in sorted(BUILDINGS_DIR.glob(f"*_{phase}.png")):
			stem = path.stem[: -len(f"_{phase}")]
			c_path = BUILDINGS_DIR / f"{stem}.png"
			if not c_path.exists():
				print(f"skip {path.name} (no complete)")
				continue

			complete = Image.open(c_path)
			phase_img = Image.open(path)
			cb = content_bounds(np.asarray(complete.convert("RGBA")))
			pb = content_bounds(np.asarray(phase_img.convert("RGBA")))
			if cb is None or pb is None:
				continue

			before_sw = (pb[2] - pb[0]) / (cb[2] - cb[0])
			before_sh = (pb[3] - pb[1]) / (cb[3] - cb[1])
			# Already within 2% — leave alone.
			if before_sw <= 1.02 and before_sh <= 1.02 and before_sw >= 0.90 and before_sh >= 0.90:
				print(f"ok   {path.name:32} {before_sw:.3f}x{before_sh:.3f}")
				continue

			out, scale = normalize_to_complete(complete, phase_img)
			ob = content_bounds(np.asarray(out.convert("RGBA")))
			assert ob
			after_sw = (ob[2] - ob[0]) / (cb[2] - cb[0])
			after_sh = (ob[3] - ob[1]) / (cb[3] - cb[1])

			bak = BACKUP_DIR / path.name
			if not bak.exists():
				shutil.copy2(path, bak)
			out.save(path)
			print(
				f"fix  {path.name:32} scale={scale:.3f}  "
				f"{before_sw:.3f}x{before_sh:.3f} -> {after_sw:.3f}x{after_sh:.3f}"
			)
			fixed += 1
	print(f"done ({fixed} files updated)")


if __name__ == "__main__":
	main()
