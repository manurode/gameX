#!/usr/bin/env python3
"""Normalize generated sprite strips to exact frame sizes with transparent background."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image


FRAME = 80
SPECS = {
    "idle": 4,
    "idle_back": 4,
    "idle_side": 4,
    "run_upward": 8,
    "run_downward": 8,
    "run_side": 8,
    "run_backward": 8,
    "attack": 9,
    "attack_back": 9,
    "attack_side": 9,
    "deploy": 4,
    "deploy_back": 3,
    "afk": 4,
    "afk_back": 4,
    "afk_side": 4,
}


def remove_backdrop(img: Image.Image) -> Image.Image:
    img = img.convert("RGBA")
    pixels = img.load()
    w, h = img.size
    samples = [pixels[2, 2], pixels[w - 3, 2], pixels[2, h - 3], pixels[w - 3, h - 3]]
    avg = tuple(sum(c[i] for c in samples) // 4 for i in range(3))
    white_bg = avg[0] > 200 and avg[1] > 200 and avg[2] > 200
    black_bg = avg[0] < 40 and avg[1] < 40 and avg[2] < 40
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            if a == 0:
                continue
            mx = max(r, g, b)
            mn = min(r, g, b)
            if black_bg or not white_bg:
                if mx < 28 or (mx < 42 and (mx - mn) < 12):
                    pixels[x, y] = (0, 0, 0, 0)
                    continue
            if white_bg or not black_bg:
                if mn > 232 and (mx - mn) < 22:
                    pixels[x, y] = (0, 0, 0, 0)
                    continue
                if mn > 210 and (mx - mn) < 12 and mx > 225:
                    pixels[x, y] = (0, 0, 0, 0)
    return img


def content_bbox(img: Image.Image) -> tuple[int, int, int, int] | None:
    alpha = img.split()[-1]
    return alpha.getbbox()


def pack_strip(src: Path, frame_count: int, out: Path) -> None:
    raw = Image.open(src)
    img = remove_backdrop(raw)
    bbox = content_bbox(img)
    if bbox is None:
        raise RuntimeError(f"No opaque content in {src}")

    cropped = img.crop(bbox)
    target_w = FRAME * frame_count
    target_h = FRAME

    # Fit entire strip into target while preserving aspect, then center.
    scale = min(target_w / cropped.width, target_h / cropped.height)
    new_w = max(1, int(round(cropped.width * scale)))
    new_h = max(1, int(round(cropped.height * scale)))
    resized = cropped.resize((new_w, new_h), Image.Resampling.LANCZOS)

    canvas = Image.new("RGBA", (target_w, target_h), (0, 0, 0, 0))
    ox = (target_w - new_w) // 2
    oy = (target_h - new_h) // 2
    canvas.paste(resized, (ox, oy), resized)

    # Re-slice into equal cells and re-center each character per cell for cleaner anim.
    cells: list[Image.Image] = []
    cell_w = max(1, new_w // frame_count)
    for i in range(frame_count):
        # Prefer equal division of full canvas width for AI strips that already laid out frames.
        left = int(round(i * target_w / frame_count))
        right = int(round((i + 1) * target_w / frame_count))
        cell = canvas.crop((left, 0, right, target_h))
        cb = content_bbox(cell)
        out_cell = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
        if cb is not None:
            part = cell.crop(cb)
            # Scale part into ~70px tall so feet/head fit
            ps = min((FRAME - 8) / part.width, (FRAME - 6) / part.height)
            pw = max(1, int(round(part.width * ps)))
            ph = max(1, int(round(part.height * ps)))
            part = part.resize((pw, ph), Image.Resampling.LANCZOS)
            px = (FRAME - pw) // 2
            py = FRAME - ph - 2  # ground-align
            out_cell.paste(part, (px, py), part)
        cells.append(out_cell)

    final = Image.new("RGBA", (target_w, target_h), (0, 0, 0, 0))
    for i, cell in enumerate(cells):
        final.paste(cell, (i * FRAME, 0), cell)

    out.parent.mkdir(parents=True, exist_ok=True)
    final.save(out)
    print(f"OK {out} ({final.size[0]}x{final.size[1]}, {frame_count}f)")


def process_building(src: Path, out: Path, size: int = 256) -> None:
    raw = Image.open(src)
    img = remove_backdrop(raw)
    bbox = content_bbox(img)
    if bbox is None:
        raise RuntimeError(f"No opaque content in {src}")
    cropped = img.crop(bbox)
    scale = min(size / cropped.width, size / cropped.height) * 0.92
    nw = max(1, int(round(cropped.width * scale)))
    nh = max(1, int(round(cropped.height * scale)))
    resized = cropped.resize((nw, nh), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.paste(resized, ((size - nw) // 2, (size - nh) // 2), resized)
    out.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out)
    print(f"OK building {out} ({size}x{size})")


def infer_frames(name: str) -> int | None:
    for key, count in SPECS.items():
        if name.endswith(key) or f"_{key}." in name or name == key:
            return count
    # chr_TYPE_ACTION pattern
    for key, count in SPECS.items():
        if f"_{key}." in name or name.endswith(f"_{key}.png"):
            return count
    stem = Path(name).stem
    for key, count in sorted(SPECS.items(), key=lambda kv: -len(kv[0])):
        if stem.endswith(key):
            return count
    return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("out")
    ap.add_argument("--frames", type=int, default=0)
    ap.add_argument("--building", action="store_true")
    args = ap.parse_args()
    src = Path(args.src)
    out = Path(args.out)
    if args.building:
        process_building(src, out)
        return 0
    frames = args.frames or infer_frames(out.name) or infer_frames(src.name)
    if not frames:
        print(f"Cannot infer frame count for {src}", file=sys.stderr)
        return 1
    pack_strip(src, frames, out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
