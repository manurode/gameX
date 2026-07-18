from PIL import Image
from pathlib import Path

SRC = Path(r"C:\Users\Manu\.cursor\projects\c-Repos-gameX\assets")
DST = Path(r"C:\Repos\gameX\assets\tilesets\mediterranean\Decor")

JOBS = [
	(SRC / "forest_large_a.png", DST / "forest_a.png", (1100, 640)),
	(SRC / "forest_large_b.png", DST / "forest_b.png", (1050, 720)),
	(SRC / "forest_large_c.png", DST / "forest_c.png", (980, 760)),
]


def near_black_to_alpha(img: Image.Image, threshold: int = 22) -> Image.Image:
	img = img.convert("RGBA")
	px = img.load()
	for y in range(img.height):
		for x in range(img.width):
			r, g, b, _a = px[x, y]
			if r <= threshold and g <= threshold and b <= threshold:
				px[x, y] = (0, 0, 0, 0)
	return img


def autocrop(img: Image.Image, pad: int = 6) -> Image.Image:
	bbox = img.getbbox()
	if not bbox:
		return img
	l, t, r, b = bbox
	return img.crop(
		(
			max(0, l - pad),
			max(0, t - pad),
			min(img.width, r + pad),
			min(img.height, b + pad),
		)
	)


def fit_canvas(img: Image.Image, size: tuple[int, int], max_fill: float = 0.97) -> Image.Image:
	tw, th = size
	scale = min((tw * max_fill) / img.width, (th * max_fill) / img.height)
	nw = max(1, int(img.width * scale))
	nh = max(1, int(img.height * scale))
	resized = img.resize((nw, nh), Image.Resampling.LANCZOS)
	canvas = Image.new("RGBA", size, (0, 0, 0, 0))
	x = (tw - nw) // 2
	y = th - nh - max(2, int(th * 0.02))
	if y < 0:
		y = (th - nh) // 2
	canvas.paste(resized, (x, y), resized)
	return canvas


def main() -> None:
	for src, dst, size in JOBS:
		im = near_black_to_alpha(Image.open(src))
		im = autocrop(im, pad=8)
		im = fit_canvas(im, size, max_fill=0.98)
		im.save(dst)
		print(f"{dst.name}: {im.size} bbox={im.getbbox()}")
	print("done")


if __name__ == "__main__":
	main()
