"""Post-process AI building phase sprites: chroma key, resize, export."""

from __future__ import annotations

import hashlib
import shutil
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(r"C:\Repos\gameX")
SRC_DIR = Path(r"C:\Users\Manu\.cursor\projects\c-Repos-gameX\assets")
OUT_DIR = ROOT / "assets" / "tilesets" / "mediterranean" / "Buildings"
IMPORT_TEMPLATE = """[remap]

importer="texture"
type="CompressedTexture2D"
uid="uid://{uid}"
path="res://.godot/imported/{name}-{digest}.ctex"
metadata={{
"vram_texture": false
}}

[deps]

source_file="{source}"
dest_files=["res://.godot/imported/{name}-{digest}.ctex"]

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=false
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=1
"""

# (stem, phase) -> optional source filename override
PHASES = ("plot", "construction", "damaged")
BUILDINGS = [
	"house_small",
	"house_big",
	"lumber_camp",
	"mill",
	"mine",
	"stable",
	"barracks",
	"tower",
	"wall_se",
	"wall_sw",
	"castle_small",
	"castle_big",
	"town_center",
]


def _ensure_import(png: Path) -> None:
	imp = Path(str(png) + ".import")
	if imp.exists():
		return
	rel = "res://" + png.relative_to(ROOT).as_posix()
	digest = hashlib.md5(rel.encode()).hexdigest()
	uid = "d" + digest[:13]
	imp.write_text(
		IMPORT_TEMPLATE.format(uid=uid, name=png.name, digest=digest, source=rel),
		encoding="utf-8",
	)


def remove_dark_bg(img: Image.Image, luma_thresh: float = 28.0) -> Image.Image:
	rgba = img.convert("RGBA")
	arr = np.asarray(rgba).astype(np.float32)
	rgb = arr[..., :3]
	luma = 0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2]
	# Near-black / near-gray dark backgrounds from the generator.
	chroma = rgb.max(axis=-1) - rgb.min(axis=-1)
	bg = (luma < luma_thresh) & (chroma < 18.0)
	# Soft edge: fade very dark pixels.
	soft = (luma < luma_thresh * 1.8) & (chroma < 28.0)
	alpha = arr[..., 3].copy()
	alpha[bg] = 0.0
	fade = np.clip((luma - luma_thresh) / max(luma_thresh * 0.8, 1.0), 0.0, 1.0)
	alpha[soft & ~bg] = np.minimum(alpha[soft & ~bg], fade[soft & ~bg] * 255.0)
	arr[..., 3] = alpha
	return Image.fromarray(arr.astype(np.uint8), "RGBA")


def fit_to_canvas(img: Image.Image, size: tuple[int, int], ref: Image.Image | None = None) -> Image.Image:
	tw, th = size
	src = img.convert("RGBA")
	# Crop to opaque content.
	alpha = np.asarray(src.split()[-1])
	ys, xs = np.where(alpha > 16)
	if len(xs) == 0:
		canvas = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
		return canvas
	x0, x1 = int(xs.min()), int(xs.max()) + 1
	y0, y1 = int(ys.min()), int(ys.max()) + 1
	cropped = src.crop((x0, y0, x1, y1))
	cw, ch = cropped.size

	# Target content box from reference if available.
	# Match complete size exactly — any margin makes damaged/plot phases visibly grow.
	pad_x, pad_y = 8, 8
	max_w = tw - pad_x * 2
	max_h = th - pad_y * 2
	ref_x0 = ref_y0 = ref_x1 = ref_y1 = None
	if ref is not None:
		ra = np.asarray(ref.convert("RGBA").split()[-1])
		rys, rxs = np.where(ra > 16)
		if len(rxs):
			ref_x0 = int(rxs.min())
			ref_y0 = int(rys.min())
			ref_x1 = int(rxs.max()) + 1
			ref_y1 = int(rys.max()) + 1
			max_w = min(max_w, ref_x1 - ref_x0)
			max_h = min(max_h, ref_y1 - ref_y0)

	scale = min(max_w / cw, max_h / ch)
	nw = max(1, int(round(cw * scale)))
	nh = max(1, int(round(ch * scale)))
	resized = cropped.resize((nw, nh), Image.Resampling.LANCZOS)

	canvas = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
	# Align bottom-center to the complete sprite's content box when possible.
	if ref_x0 is not None and ref_y1 is not None:
		ox = ref_x0 + ((ref_x1 - ref_x0) - nw) // 2
		oy = ref_y1 - nh
	else:
		ox = (tw - nw) // 2
		oy = th - nh - pad_y
	canvas.paste(resized, (ox, oy), resized)
	return canvas


def find_source(stem: str, phase: str) -> Path | None:
	candidates = [
		SRC_DIR / f"{stem}_{phase}_ai.png",
		SRC_DIR / f"{stem}_{phase}.png",
		ROOT / "assets" / f"{stem}_{phase}_ai.png",
	]
	for c in candidates:
		if c.exists():
			return c
	return None


def fill_enclosed_damage_holes(img: Image.Image) -> Image.Image:
	"""Restore opaque dark interiors punched out by remove_dark_bg."""
	import importlib.util

	mod_path = Path(__file__).with_name("fix_damaged_building_holes.py")
	spec = importlib.util.spec_from_file_location("fix_damaged_building_holes", mod_path)
	if spec is None or spec.loader is None:
		raise RuntimeError(f"Cannot load {mod_path}")
	mod = importlib.util.module_from_spec(spec)
	spec.loader.exec_module(mod)
	fixed, _n_holes, _n_hard = mod.fix_image(img)
	return fixed


def process_one(stem: str, phase: str) -> bool:
	if stem == "town_center" and phase != "damaged":
		return False
	src = find_source(stem, phase)
	if src is None:
		print(f"MISSING {stem}_{phase}")
		return False

	ref_name = f"{stem}.png"
	ref_path = OUT_DIR / ref_name
	ref = Image.open(ref_path).convert("RGBA") if ref_path.exists() else None
	size = ref.size if ref is not None else (256, 256)

	img = Image.open(src).convert("RGBA")
	img = remove_dark_bg(img)
	img = fit_to_canvas(img, size, ref)
	if phase == "damaged":
		img = fill_enclosed_damage_holes(img)

	out = OUT_DIR / f"{stem}_{phase}.png"
	img.save(out)
	_ensure_import(out)
	print(f"wrote {out.relative_to(ROOT)} from {src.name}")
	return True


def main() -> None:
	OUT_DIR.mkdir(parents=True, exist_ok=True)
	ok = 0
	for stem in BUILDINGS:
		phases = ("damaged",) if stem == "town_center" else PHASES
		for phase in phases:
			if process_one(stem, phase):
				ok += 1
	print(f"done ({ok} sprites)")


if __name__ == "__main__":
	main()
