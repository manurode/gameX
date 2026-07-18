from PIL import Image
from pathlib import Path

SRC = Path(r"C:\Users\Manu\.cursor\projects\c-Repos-gameX\assets")
DST = Path(r"C:\Repos\gameX\assets\tilesets\mediterranean")
BACKUP = DST / "_backup_pre_scale"
BACKUP.mkdir(parents=True, exist_ok=True)


def near_black_to_alpha(img: Image.Image, threshold: int = 18) -> Image.Image:
	img = img.convert("RGBA")
	pixels = img.load()
	w, h = img.size
	for y in range(h):
		for x in range(w):
			r, g, b, _a = pixels[x, y]
			if r <= threshold and g <= threshold and b <= threshold:
				pixels[x, y] = (0, 0, 0, 0)
	return img


def autocrop(img: Image.Image, pad: int = 8) -> Image.Image:
	bbox = img.getbbox()
	if not bbox:
		return img
	l, t, r, b = bbox
	l = max(0, l - pad)
	t = max(0, t - pad)
	r = min(img.width, r + pad)
	b = min(img.height, b + pad)
	return img.crop((l, t, r, b))


def fit_canvas(img: Image.Image, size: tuple[int, int], max_fill: float = 0.92) -> Image.Image:
	tw, th = size
	max_w = int(tw * max_fill)
	max_h = int(th * max_fill)
	scale = min(max_w / img.width, max_h / img.height)
	nw = max(1, int(img.width * scale))
	nh = max(1, int(img.height * scale))
	resized = img.resize((nw, nh), Image.Resampling.LANCZOS)
	canvas = Image.new("RGBA", size, (0, 0, 0, 0))
	x = (tw - nw) // 2
	y = th - nh - max(4, int(th * 0.03))
	if y < 0:
		y = (th - nh) // 2
	canvas.paste(resized, (x, y), resized)
	return canvas


def backup(path: Path) -> None:
	if path.exists():
		dest = BACKUP / path.name
		if not dest.exists():
			Image.open(path).save(dest)
			print(f"backed up {path.name}")


def main() -> None:
	tower_src = SRC / "tower_new.png"
	tower_dst = DST / "Buildings" / "tower.png"
	backup(tower_dst)
	tower = near_black_to_alpha(Image.open(tower_src), threshold=22)
	tower = autocrop(tower, pad=6)
	tower = fit_canvas(tower, (256, 256), max_fill=0.94)
	tower.save(tower_dst)
	print(f"tower saved {tower.size} bbox={tower.getbbox()}")

	forest_jobs = [
		(SRC / "forest_a_new.png", DST / "Decor" / "forest_a.png", (780, 480)),
		(SRC / "forest_b_short.png", DST / "Decor" / "forest_b.png", (780, 500)),
		(SRC / "forest_c_short.png", DST / "Decor" / "forest_c.png", (700, 520)),
	]

	for src, dst, size in forest_jobs:
		backup(dst)
		im = near_black_to_alpha(Image.open(src), threshold=20)
		im = autocrop(im, pad=10)
		im = fit_canvas(im, size, max_fill=0.95)
		im.save(dst)
		print(f"{dst.name} saved {im.size} content_bbox={im.getbbox()}")

	print("done")


if __name__ == "__main__":
	main()
