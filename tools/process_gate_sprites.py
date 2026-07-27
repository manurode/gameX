"""Process AI-generated gate sprites into Buildings/ at wall size."""

from __future__ import annotations

import hashlib
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(r"C:\Repos\gameX")
SRC = Path(r"C:\Users\Manu\.cursor\projects\c-Repos-gameX\assets")
OUT = ROOT / "assets" / "tilesets" / "mediterranean" / "Buildings"

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


def ensure_import(png: Path) -> None:
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
	chroma = rgb.max(axis=-1) - rgb.min(axis=-1)
	bg = (luma < luma_thresh) & (chroma < 18.0)
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
	alpha = np.asarray(src.split()[-1])
	ys, xs = np.where(alpha > 16)
	if len(xs) == 0:
		return Image.new("RGBA", (tw, th), (0, 0, 0, 0))
	x0, x1 = int(xs.min()), int(xs.max()) + 1
	y0, y1 = int(ys.min()), int(ys.max()) + 1
	cropped = src.crop((x0, y0, x1, y1))
	cw, ch = cropped.size
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
	if ref_x0 is not None and ref_y1 is not None:
		ox = ref_x0 + ((ref_x1 - ref_x0) - nw) // 2
		oy = ref_y1 - nh
	else:
		ox = (tw - nw) // 2
		oy = th - nh - pad_y
	canvas.paste(resized, (ox, oy), resized)
	return canvas


def process(src_name: str, out_name: str, ref_path: Path) -> None:
	src = SRC / src_name
	if not src.exists():
		print(f"MISSING {src}")
		return
	ref = Image.open(ref_path).convert("RGBA") if ref_path.exists() else None
	img = remove_dark_bg(Image.open(src).convert("RGBA"))
	img = fit_to_canvas(img, (256, 256), ref)
	out = OUT / out_name
	img.save(out)
	ensure_import(out)
	print(f"wrote {out_name}")


def main() -> None:
	OUT.mkdir(parents=True, exist_ok=True)
	# Complete first, aligned to wall complete.
	for orient in ("se", "sw"):
		process(f"gate_{orient}_ai.png", f"gate_{orient}.png", OUT / f"wall_{orient}.png")

	for orient in ("se", "sw"):
		complete = OUT / f"gate_{orient}.png"
		process(f"gate_{orient}_open_ai.png", f"gate_{orient}_open.png", complete)
		process(f"gate_{orient}_construction_ai.png", f"gate_{orient}_construction.png", complete)
		process(f"gate_{orient}_damaged_ai.png", f"gate_{orient}_damaged.png", complete)
		process(f"gate_{orient}_plot_ai.png", f"gate_{orient}_plot.png", OUT / f"wall_{orient}_plot.png")
	print("done")


if __name__ == "__main__":
	main()
