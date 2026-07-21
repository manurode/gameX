"""Bake lake water collision masks + texture-centered outline polygons.

Masks / outlines use the same teal test as TerrainObstacle (epsilon 3.5).
Re-run after changing lake_a/b/c.png:
  python tools/bake_lake_water_masks.py
"""
from __future__ import annotations

import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
DECOR = ROOT / "assets/tilesets/mediterranean/Decor"
OUTLINES_JSON = DECOR / "lake_water_outlines.json"

WATER_MIN_BLUE = 0.32
WATER_ALPHA_BYTE_MIN = 72
POLYGON_EPSILON = 3.5

LAKES = ("lake_a.png", "lake_b.png", "lake_c.png")


def is_water_rgba(a: np.ndarray) -> np.ndarray:
	r = a[:, :, 0].astype(np.float32) / 255.0
	g = a[:, :, 1].astype(np.float32) / 255.0
	b = a[:, :, 2].astype(np.float32) / 255.0
	alpha = a[:, :, 3]
	return (
		(alpha >= WATER_ALPHA_BYTE_MIN)
		& (b > g * 0.7)
		& (g > r)
		& (b > WATER_MIN_BLUE)
	)


def outlines_from_water(water: np.ndarray) -> list[list[list[float]]]:
	h, w = water.shape
	binary = water.astype(np.uint8) * 255
	contours, _hierarchy = cv2.findContours(
		binary, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE
	)
	half_x = w * 0.5
	half_y = h * 0.5
	result: list[list[list[float]]] = []
	for contour in contours:
		if contour is None or len(contour) < 3:
			continue
		approx = cv2.approxPolyDP(contour, POLYGON_EPSILON, True)
		if approx is None or len(approx) < 3:
			continue
		poly = [
			[round(float(pt[0][0]) - half_x, 3), round(float(pt[0][1]) - half_y, 3)]
			for pt in approx
		]
		if len(poly) >= 3:
			result.append(poly)
	return result


def bake_one(name: str, outlines: dict) -> None:
	src = DECOR / name
	if not src.exists():
		print("missing", src)
		return
	img = np.array(Image.open(src).convert("RGBA"), dtype=np.uint8)
	water = is_water_rgba(img)
	mask = np.zeros_like(img)
	mask[water] = (255, 255, 255, 255)
	mask_path = DECOR / f"{src.stem}_water_mask.png"
	Image.fromarray(mask, "RGBA").save(mask_path, "PNG")

	key = f"res://assets/tilesets/mediterranean/Decor/{name}"
	polys = outlines_from_water(water)
	outlines[key] = polys
	print(
		f"saved {mask_path.name} water_pixels={int(water.sum())} "
		f"polys={len(polys)} verts={sum(len(p) for p in polys)}"
	)


def main() -> None:
	outlines: dict = {}
	for name in LAKES:
		bake_one(name, outlines)
	OUTLINES_JSON.write_text(json.dumps(outlines, separators=(",", ":")), encoding="utf-8")
	print("wrote", OUTLINES_JSON)


if __name__ == "__main__":
	main()
