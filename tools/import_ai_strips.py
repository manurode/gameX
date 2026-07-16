"""Slice AI-generated animation strips into 80x80 transparent game sheets."""

from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image

FRAME = 80
SRC_DIR = Path(r"C:\Repos\gameX\tools\ai_source")
GAME_CHARS = Path(r"C:\Repos\gameX\assets\tilesets\mediterranean\Characters")
OUT_PREVIEWS = Path(r"C:\Repos\gameX\tools\anim_preview\frames")


def to_rgba_transparent(im: Image.Image, threshold: int = 22) -> Image.Image:
    arr = np.array(im.convert("RGBA"))
    lum = arr[:, :, :3].max(axis=2)
    alpha = np.zeros(lum.shape, dtype=np.uint8)
    alpha[lum > threshold + 20] = 255
    mid = (lum > threshold) & (lum <= threshold + 20)
    alpha[mid] = ((lum[mid] - threshold) * (255 / 20)).astype(np.uint8)
    arr[:, :, 3] = alpha
    return Image.fromarray(arr, "RGBA")


def extract_characters(im: Image.Image, expected: int) -> list[Image.Image]:
    """Find separate character blobs left-to-right."""
    arr = np.array(im)
    mask = arr[:, :, 3] > 40
    # column occupancy
    cols = mask.any(axis=0)
    segments: list[tuple[int, int]] = []
    in_run = False
    start = 0
    for x, occupied in enumerate(cols):
        if occupied and not in_run:
            in_run = True
            start = x
        elif not occupied and in_run:
            in_run = False
            if x - start > 8:
                segments.append((start, x))
    if in_run and len(cols) - start > 8:
        segments.append((start, len(cols)))

    # Merge tiny gaps (anti-alias splits)
    merged: list[tuple[int, int]] = []
    for seg in segments:
        if not merged:
            merged.append(seg)
            continue
        prev = merged[-1]
        if seg[0] - prev[1] < 6:
            merged[-1] = (prev[0], seg[1])
        else:
            merged.append(seg)

    # If we got too many, keep the largest `expected`
    if len(merged) > expected:
        merged = sorted(merged, key=lambda s: s[1] - s[0], reverse=True)[:expected]
        merged = sorted(merged, key=lambda s: s[0])

    # If too few, fall back to equal splits of content bbox
    if len(merged) < max(3, expected // 2):
        ys, xs = np.where(mask)
        if len(xs) == 0:
            return [Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))] * expected
        x0, x1 = int(xs.min()), int(xs.max()) + 1
        y0, y1 = int(ys.min()), int(ys.max()) + 1
        band = im.crop((x0, y0, x1, y1))
        cell_w = band.width / expected
        frames = []
        for i in range(expected):
            frames.append(band.crop((int(i * cell_w), 0, int((i + 1) * cell_w), band.height)))
        return frames

    # Pad/trim to expected count
    while len(merged) < expected:
        # duplicate last
        merged.append(merged[-1])
    merged = merged[:expected]

    frames = []
    for x0, x1 in merged:
        # vertical crop to content in this column range
        col_mask = mask[:, x0:x1]
        ys = np.where(col_mask.any(axis=1))[0]
        if len(ys) == 0:
            frames.append(Image.new("RGBA", (1, 1), (0, 0, 0, 0)))
            continue
        y0, y1 = int(ys.min()), int(ys.max()) + 1
        pad = 2
        frames.append(
            im.crop(
                (
                    max(0, x0 - pad),
                    max(0, y0 - pad),
                    min(im.width, x1 + pad),
                    min(im.height, y1 + pad),
                )
            )
        )
    return frames


def fit_frame(char: Image.Image, target_body_h: int = 40) -> Image.Image:
    """Fit a character into 80x80 matching idle body height (no upscale-to-fill)."""
    char = char.convert("RGBA")
    bbox = char.getbbox()
    canvas = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    if bbox is None:
        return canvas
    cropped = char.crop(bbox)
    # Match idle-sized bodies; AI art is chunkier so shrink a bit more
    style = 0.78
    scale = (target_body_h * style) / max(cropped.height, 1)
    max_scale = min((FRAME - 2) / max(cropped.width, 1), (FRAME - 2) / max(cropped.height, 1))
    scale = min(scale, max_scale)
    nw = max(1, int(cropped.width * scale))
    nh = max(1, int(cropped.height * scale))
    cropped = cropped.resize((nw, nh), Image.Resampling.LANCZOS)
    px = (FRAME - cropped.width) // 2
    py = FRAME - cropped.height - 2
    canvas.alpha_composite(cropped, dest=(max(0, px), max(0, py)))
    arr = np.array(canvas)
    arr[arr[:, :, 3] < 48, 3] = 0
    arr[arr[:, :, 3] >= 48, 3] = 255
    return Image.fromarray(arr, "RGBA")


def process(src_name: str, dest: Path, frame_count: int) -> None:
    src = SRC_DIR / src_name
    if not src.exists():
        raise FileNotFoundError(src)

    im = to_rgba_transparent(Image.open(src))
    raw = extract_characters(im, frame_count)
    # If blob count mismatched, equal-split content band
    if len(raw) != frame_count:
        print(f"  warn: got {len(raw)} blobs, equal-splitting to {frame_count}")
        arr = np.array(im)
        mask = arr[:, :, 3] > 40
        ys, xs = np.where(mask)
        x0, x1 = int(xs.min()), int(xs.max()) + 1
        y0, y1 = int(ys.min()), int(ys.max()) + 1
        band = im.crop((x0, y0, x1, y1))
        cell = band.width / frame_count
        raw = [band.crop((int(i * cell), 0, int((i + 1) * cell), band.height)) for i in range(frame_count)]

    fitted = [fit_frame(f) for f in raw]
    sheet = Image.new("RGBA", (FRAME * frame_count, FRAME), (0, 0, 0, 0))
    for i, fr in enumerate(fitted):
        sheet.alpha_composite(fr, dest=(i * FRAME, 0))
    dest.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(dest)
    print(f"wrote {dest.relative_to(GAME_CHARS.parent.parent.parent)} {sheet.size}")

    OUT_PREVIEWS.mkdir(parents=True, exist_ok=True)
    idxs = [0, max(0, frame_count // 3), max(0, (2 * frame_count) // 3), frame_count - 1]
    prev = Image.new("RGBA", (len(idxs) * 240, 240), (0, 0, 0, 0))
    for n, i in enumerate(idxs):
        fr = fitted[i].resize((240, 240), Image.Resampling.NEAREST)
        bg = Image.new("RGBA", fr.size)
        cell = 12
        for y in range(0, 240, cell):
            for x in range(0, 240, cell):
                c = (70, 130, 70, 255) if ((x // cell) + (y // cell)) % 2 == 0 else (55, 110, 55, 255)
                for yy in range(y, min(y + cell, 240)):
                    for xx in range(x, min(x + cell, 240)):
                        bg.putpixel((xx, yy), c)
        prev.paste(Image.alpha_composite(bg, fr), (n * 240, 0))
    prev.save(OUT_PREVIEWS / f"imported_{dest.stem}.png")


def main() -> None:
    process("ai_knight_attack_strip.png", GAME_CHARS / "knight" / "chr_knight_attack.png", 9)
    process("ai_knight_attack_strip.png", GAME_CHARS / "knight" / "chr_knight_attack_back.png", 9)
    process("ai_archer_attack_strip.png", GAME_CHARS / "archer" / "chr_archer_attack.png", 9)
    process("ai_archer_attack_strip.png", GAME_CHARS / "archer" / "chr_archer_attack_back.png", 9)
    process("ai_builder_work_strip.png", GAME_CHARS / "builder" / "chr_builder_afk.png", 6)
    print("Done.")


if __name__ == "__main__":
    main()
