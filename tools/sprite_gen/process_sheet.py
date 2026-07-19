#!/usr/bin/env python3
"""Normalize generated sprite strips to exact frame sizes with transparent background.

Detects individual character blobs by column gaps instead of blindly slicing,
so uneven AI spacing / near-touching frames don't get cut mid-sprite.
"""

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


def _is_backdrop_rgb(r: int, g: int, b: int) -> bool:
    mx = max(r, g, b)
    mn = min(r, g, b)
    # Near black / charcoal studio
    if mx < 48:
        return True
    if mx < 70 and (mx - mn) < 14:
        return True
    # Near white / light gray studio
    if mn > 228 and (mx - mn) < 24:
        return True
    if mn > 200 and (mx - mn) < 10 and mx > 215:
        return True
    return False


def remove_backdrop(img: Image.Image) -> Image.Image:
    img = img.convert("RGBA")
    pixels = img.load()
    w, h = img.size

    # Flood-fill backdrop from all border pixels so interior gaps stay
    # only if they are truly empty between characters.
    from collections import deque

    visited = bytearray(w * h)
    q: deque[tuple[int, int]] = deque()

    def push(x: int, y: int) -> None:
        idx = y * w + x
        if visited[idx]:
            return
        r, g, b, a = pixels[x, y]
        if a == 0 or _is_backdrop_rgb(r, g, b):
            visited[idx] = 1
            q.append((x, y))

    for x in range(w):
        push(x, 0)
        push(x, h - 1)
    for y in range(h):
        push(0, y)
        push(w - 1, y)

    while q:
        x, y = q.popleft()
        pixels[x, y] = (0, 0, 0, 0)
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < w and 0 <= ny < h:
                push(nx, ny)

    # Also clear remaining near-backdrop pixels that weren't border-connected
    # (AI sometimes leaves floating dark bars between frames).
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            if a and _is_backdrop_rgb(r, g, b):
                pixels[x, y] = (0, 0, 0, 0)
    return img


def content_bbox(img: Image.Image) -> tuple[int, int, int, int] | None:
    return img.split()[-1].getbbox()


def _column_mask(img: Image.Image, min_alpha: int = 16) -> list[bool]:
    pixels = img.load()
    w, h = img.size
    mask = [False] * w
    for x in range(w):
        for y in range(h):
            if pixels[x, y][3] >= min_alpha:
                mask[x] = True
                break
    return mask


def _runs_from_mask(mask: list[bool]) -> list[tuple[int, int]]:
    runs: list[tuple[int, int]] = []
    i = 0
    n = len(mask)
    while i < n:
        if mask[i]:
            j = i + 1
            while j < n and mask[j]:
                j += 1
            runs.append((i, j))
            i = j
        else:
            i += 1
    return runs


def _merge_tiny_runs(
    runs: list[tuple[int, int]], min_width: int, max_gap_merge: int
) -> list[tuple[int, int]]:
    if not runs:
        return []
    # First pass: glue runs separated by tiny gaps (touching frames / anti-alias seams).
    glued: list[tuple[int, int]] = [runs[0]]
    for start, end in runs[1:]:
        prev_s, prev_e = glued[-1]
        if start - prev_e <= max_gap_merge:
            glued[-1] = (prev_s, end)
        else:
            glued.append((start, end))

    # Second pass: absorb thin slivers into the nearer neighbor.
    changed = True
    while changed and len(glued) > 1:
        changed = False
        widths = [e - s for s, e in glued]
        tiny_idx = next((i for i, w in enumerate(widths) if w < min_width), -1)
        if tiny_idx < 0:
            break
        s, e = glued[tiny_idx]
        if tiny_idx == 0:
            ns, ne = glued[1]
            glued[1] = (s, ne)
            del glued[0]
        elif tiny_idx == len(glued) - 1:
            ps, pe = glued[-2]
            glued[-2] = (ps, e)
            del glued[-1]
        else:
            left_gap = s - glued[tiny_idx - 1][1]
            right_gap = glued[tiny_idx + 1][0] - e
            if left_gap <= right_gap:
                ps, pe = glued[tiny_idx - 1]
                glued[tiny_idx - 1] = (ps, e)
            else:
                ns, ne = glued[tiny_idx + 1]
                glued[tiny_idx + 1] = (s, ne)
            del glued[tiny_idx]
        changed = True
    return glued


def _split_into_n(start: int, end: int, n: int) -> list[tuple[int, int]]:
    parts: list[tuple[int, int]] = []
    for i in range(n):
        a = start + int(round(i * (end - start) / n))
        b = start + int(round((i + 1) * (end - start) / n))
        parts.append((a, max(a + 1, b)))
    return parts


def segment_frames(img: Image.Image, frame_count: int) -> list[tuple[int, int, int, int]]:
    """Return list of (left, top, right, bottom) crop boxes, one per frame."""
    bbox = content_bbox(img)
    if bbox is None:
        raise RuntimeError("No opaque content")
    left, top, right, bottom = bbox
    strip = img.crop(bbox)
    mask = _column_mask(strip)
    runs = _runs_from_mask(mask)
    # Min width ~2% of strip, gaps of a few px are seams not separators.
    min_w = max(12, strip.width // (frame_count * 8))
    runs = _merge_tiny_runs(runs, min_width=min_w, max_gap_merge=max(4, strip.width // 200))

    # Map runs back to absolute coords.
    abs_runs = [(left + s, left + e) for s, e in runs]

    if len(abs_runs) == frame_count:
        chosen = abs_runs
    elif len(abs_runs) > frame_count:
        # Too many pieces: keep the N widest.
        ranked = sorted(abs_runs, key=lambda r: r[1] - r[0], reverse=True)[:frame_count]
        chosen = sorted(ranked, key=lambda r: r[0])
    elif len(abs_runs) == 1:
        chosen = _split_into_n(abs_runs[0][0], abs_runs[0][1], frame_count)
    elif len(abs_runs) > 0:
        # Fewer blobs than frames: split the widest blobs until we reach N.
        pieces = list(abs_runs)
        while len(pieces) < frame_count:
            widths = [e - s for s, e in pieces]
            idx = max(range(len(pieces)), key=lambda i: widths[i])
            s, e = pieces[idx]
            mid = (s + e) // 2
            pieces[idx : idx + 1] = [(s, mid), (mid, e)]
        # If we overshot somehow, trim.
        if len(pieces) > frame_count:
            ranked = sorted(pieces, key=lambda r: r[1] - r[0], reverse=True)[:frame_count]
            pieces = sorted(ranked, key=lambda r: r[0])
        chosen = pieces
    else:
        chosen = _split_into_n(left, right, frame_count)

    boxes: list[tuple[int, int, int, int]] = []
    for s, e in chosen:
        # Per-frame vertical crop within the global content band.
        cell = img.crop((s, top, e, bottom))
        cb = content_bbox(cell)
        if cb is None:
            boxes.append((s, top, e, bottom))
        else:
            boxes.append((s + cb[0], top + cb[1], s + cb[2], top + cb[3]))
    return boxes


def fit_into_frame(part: Image.Image) -> Image.Image:
    out = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    if part.width <= 0 or part.height <= 0:
        return out
    # Leave a couple px padding; ground-align like existing knight sheets.
    ps = min((FRAME - 6) / part.width, (FRAME - 4) / part.height)
    pw = max(1, int(round(part.width * ps)))
    ph = max(1, int(round(part.height * ps)))
    resized = part.resize((pw, ph), Image.Resampling.LANCZOS)
    px = (FRAME - pw) // 2
    py = FRAME - ph - 1
    out.paste(resized, (px, py), resized)
    return out


def pack_strip(src: Path, frame_count: int, out: Path) -> None:
    raw = Image.open(src)
    img = remove_backdrop(raw)
    boxes = segment_frames(img, frame_count)

    cells = [fit_into_frame(img.crop(box)) for box in boxes]
    # Pad / trim to exact frame_count.
    while len(cells) < frame_count:
        cells.append(Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0)))
    cells = cells[:frame_count]

    final = Image.new("RGBA", (FRAME * frame_count, FRAME), (0, 0, 0, 0))
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
    stem = Path(name).stem
    for key, count in sorted(SPECS.items(), key=lambda kv: -len(kv[0])):
        if stem.endswith(key) or stem.endswith(f"{key}_raw"):
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
