#!/usr/bin/env python3
"""Normalize generated sprite strips to exact frame sizes with transparent background.

AI strips are prompted as N evenly spaced frames. Equal-width cells are the primary
slicer; gap detection is only a fallback when equal cells look empty/broken.
"""

from __future__ import annotations

import argparse
import sys
from collections import deque
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

    # Clear remaining near-backdrop pixels (floating dark bars between frames).
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            if a and _is_backdrop_rgb(r, g, b):
                pixels[x, y] = (0, 0, 0, 0)
    return img


def _remove_dark_specks(img: Image.Image, min_area: int = 18, max_luma: int = 90) -> Image.Image:
    """Remove tiny dark disconnected blobs; keep bright FX sparks."""
    try:
        import numpy as np
    except ImportError:
        return img

    arr = np.array(img)
    alpha = arr[:, :, 3] >= 16
    h, w = alpha.shape
    visited = np.zeros((h, w), dtype=bool)
    for y in range(h):
        xs = np.where(alpha[y] & ~visited[y])[0]
        for x in xs:
            if visited[y, x]:
                continue
            stack = [(int(x), int(y))]
            visited[y, x] = True
            comp: list[tuple[int, int]] = []
            peak = 0
            while stack:
                cx, cy = stack.pop()
                comp.append((cx, cy))
                peak = max(peak, int(arr[cy, cx, :3].max()))
                for nx, ny in ((cx - 1, cy), (cx + 1, cy), (cx, cy - 1), (cx, cy + 1)):
                    if 0 <= nx < w and 0 <= ny < h and alpha[ny, nx] and not visited[ny, nx]:
                        visited[ny, nx] = True
                        stack.append((nx, ny))
            if len(comp) < min_area and peak <= max_luma:
                for cx, cy in comp:
                    arr[cy, cx, 3] = 0
    return Image.fromarray(arr, "RGBA")


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
    glued: list[tuple[int, int]] = [runs[0]]
    for start, end in runs[1:]:
        prev_s, prev_e = glued[-1]
        if start - prev_e <= max_gap_merge:
            glued[-1] = (prev_s, end)
        else:
            glued.append((start, end))

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


def _boxes_from_x_ranges(
    img: Image.Image, ranges: list[tuple[int, int]], top: int, bottom: int
) -> list[tuple[int, int, int, int]]:
    boxes: list[tuple[int, int, int, int]] = []
    for s, e in ranges:
        cell = img.crop((s, top, e, bottom))
        cb = content_bbox(cell)
        if cb is None:
            boxes.append((s, top, e, bottom))
        else:
            boxes.append((s + cb[0], top + cb[1], s + cb[2], top + cb[3]))
    return boxes


def _score_boxes(boxes: list[tuple[int, int, int, int]], frame_count: int) -> float:
    """Higher is better. Penalize empty, tiny, or wildly inconsistent widths."""
    if len(boxes) != frame_count:
        return -1e9
    widths = [max(1, b[2] - b[0]) for b in boxes]
    heights = [max(1, b[3] - b[1]) for b in boxes]
    areas = [w * h for w, h in zip(widths, heights)]
    med_w = sorted(widths)[len(widths) // 2]
    med_a = sorted(areas)[len(areas) // 2]
    score = 0.0
    for w, a in zip(widths, areas):
        if a < med_a * 0.12:
            score -= 50
        ratio = w / med_w
        if ratio < 0.55 or ratio > 1.75:
            score -= 25
        else:
            score += 10 - abs(1.0 - ratio) * 8
    # Prefer similar consecutive widths (even spacing).
    for i in range(len(widths) - 1):
        score -= abs(widths[i] - widths[i + 1]) / med_w * 3
    return score


def _normalize_run_count(
    runs: list[tuple[int, int]], frame_count: int, expected_w: float
) -> list[tuple[int, int]]:
    """Force exactly frame_count ranges by splitting wide blobs / merging close ones."""
    if not runs:
        return []
    pieces = list(runs)

    # Absorb slivers into the nearer neighbor.
    min_keep = max(10, int(expected_w * 0.28))
    changed = True
    while changed and len(pieces) > 1:
        changed = False
        widths = [e - s for s, e in pieces]
        tiny = next((i for i, w in enumerate(widths) if w < min_keep), -1)
        if tiny < 0:
            break
        s, e = pieces[tiny]
        if tiny == 0:
            pieces[1] = (s, pieces[1][1])
            del pieces[0]
        elif tiny == len(pieces) - 1:
            pieces[-2] = (pieces[-2][0], e)
            del pieces[-1]
        else:
            left_gap = s - pieces[tiny - 1][1]
            right_gap = pieces[tiny + 1][0] - e
            if left_gap <= right_gap:
                pieces[tiny - 1] = (pieces[tiny - 1][0], e)
            else:
                pieces[tiny + 1] = (s, pieces[tiny + 1][1])
            del pieces[tiny]
        changed = True

    # Too many: merge the closest pair repeatedly.
    while len(pieces) > frame_count:
        best_i = 0
        best_gap = 10**9
        for i in range(len(pieces) - 1):
            gap = pieces[i + 1][0] - pieces[i][1]
            if gap < best_gap:
                best_gap = gap
                best_i = i
        pieces[best_i] = (pieces[best_i][0], pieces[best_i + 1][1])
        del pieces[best_i + 1]

    # Too few: split the widest blob (usually FX-connected frames).
    while len(pieces) < frame_count:
        widths = [e - s for s, e in pieces]
        idx = max(range(len(pieces)), key=lambda i: widths[i])
        s, e = pieces[idx]
        # Split into how many we still need from this blob, at least 2.
        need = frame_count - len(pieces) + 1
        parts = _split_into_n(s, e, need)
        pieces[idx : idx + 1] = parts

    return pieces[:frame_count]


def _gap_ranges(img: Image.Image, frame_count: int, left: int, right: int) -> list[tuple[int, int]]:
    strip = img.crop((left, 0, right, img.height))
    expected_w = max(1.0, strip.width / frame_count)
    mask = _column_mask(strip)
    runs = _runs_from_mask(mask)
    # Only glue anti-alias hairline gaps — never large gaps between characters.
    runs = _merge_tiny_runs(runs, min_width=max(8, int(expected_w * 0.2)), max_gap_merge=3)
    abs_runs = [(left + s, left + e) for s, e in runs]
    if not abs_runs:
        return _split_into_n(left, right, frame_count)
    return _normalize_run_count(abs_runs, frame_count, expected_w)


def _edge_bleed_penalty(
    img: Image.Image, ranges: list[tuple[int, int]], top: int, bottom: int
) -> float:
    """Penalize cells whose content touches both vertical edges (cut mid-sprite)."""
    penalty = 0.0
    for s, e in ranges:
        cell_w = max(1, e - s)
        cell = img.crop((s, top, e, bottom))
        cb = content_bbox(cell)
        if cb is None:
            penalty += 40
            continue
        touches_left = cb[0] <= 1
        touches_right = cb[2] >= cell_w - 1
        if touches_left and touches_right:
            penalty += 35  # almost certainly sliced through a character
        elif touches_left or touches_right:
            penalty += 8
        # Very empty cell
        area = (cb[2] - cb[0]) * (cb[3] - cb[1])
        if area < (cell_w * (bottom - top)) * 0.08:
            penalty += 20
    return penalty


def _column_density(img: Image.Image, min_alpha: int = 16) -> list[int]:
    pixels = img.load()
    w, h = img.size
    dens = [0] * w
    for x in range(w):
        total = 0
        for y in range(h):
            if pixels[x, y][3] >= min_alpha:
                total += 1
        dens[x] = total
    return dens


def _valley_ranges(img: Image.Image, frame_count: int, left: int, right: int) -> list[tuple[int, int]]:
    """Equal-ish splits snapped to local density valleys (best for AI strips)."""
    strip = img.crop((left, 0, right, img.height))
    dens = _column_density(strip)
    w = strip.width
    if w < frame_count * 4:
        return _split_into_n(left, right, frame_count)

    # Light smooth to ignore 1px noise.
    smooth = dens[:]
    for x in range(1, w - 1):
        smooth[x] = (dens[x - 1] + dens[x] * 2 + dens[x + 1]) // 4

    search = max(6, w // (frame_count * 5))
    cuts = [0]
    for i in range(1, frame_count):
        ideal = int(round(i * w / frame_count))
        a = max(cuts[-1] + 2, ideal - search)
        b = min(w - 2, ideal + search)
        # Prefer the emptiest column near the ideal boundary.
        best = min(range(a, b + 1), key=lambda x: (smooth[x], abs(x - ideal)))
        cuts.append(best)
    cuts.append(w)
    # Ensure strictly increasing.
    for i in range(1, len(cuts)):
        if cuts[i] <= cuts[i - 1]:
            cuts[i] = cuts[i - 1] + 1
    return [(left + cuts[i], left + cuts[i + 1]) for i in range(frame_count)]


def segment_frames(img: Image.Image, frame_count: int) -> list[tuple[int, int, int, int]]:
    """Return list of (left, top, right, bottom) crop boxes, one per frame."""
    bbox = content_bbox(img)
    if bbox is None:
        raise RuntimeError("No opaque content")
    left, top, right, bottom = bbox

    candidates: list[tuple[float, list[tuple[int, int, int, int]]]] = []

    equal_ranges = _split_into_n(left, right, frame_count)
    equal_boxes = _boxes_from_x_ranges(img, equal_ranges, top, bottom)
    equal_score = _score_boxes(equal_boxes, frame_count) - _edge_bleed_penalty(
        img, equal_ranges, top, bottom
    )
    candidates.append((equal_score, equal_boxes))

    valley_ranges = _valley_ranges(img, frame_count, left, right)
    valley_boxes = _boxes_from_x_ranges(img, valley_ranges, top, bottom)
    valley_score = _score_boxes(valley_boxes, frame_count) - _edge_bleed_penalty(
        img, valley_ranges, top, bottom
    )
    candidates.append((valley_score, valley_boxes))

    gap_ranges = _gap_ranges(img, frame_count, left, right)
    gap_boxes = _boxes_from_x_ranges(img, gap_ranges, top, bottom)
    gap_score = _score_boxes(gap_boxes, frame_count)
    candidates.append((gap_score, gap_boxes))

    candidates.sort(key=lambda c: c[0], reverse=True)
    return candidates[0][1]


def fit_into_frame(part: Image.Image, scale: float | None = None) -> Image.Image:
    out = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    bb = content_bbox(part)
    if bb is None:
        return out
    cropped = part.crop(bb)
    if cropped.width <= 0 or cropped.height <= 0:
        return out
    if scale is None:
        scale = min((FRAME - 6) / cropped.width, (FRAME - 4) / cropped.height)
    pw = max(1, int(round(cropped.width * scale)))
    ph = max(1, int(round(cropped.height * scale)))
    # Never exceed the frame.
    if pw > FRAME - 2 or ph > FRAME - 2:
        scale = min((FRAME - 2) / cropped.width, (FRAME - 2) / cropped.height)
        pw = max(1, int(round(cropped.width * scale)))
        ph = max(1, int(round(cropped.height * scale)))
    resized = cropped.resize((pw, ph), Image.Resampling.LANCZOS)
    px = (FRAME - pw) // 2
    py = FRAME - ph - 1
    out.paste(resized, (px, py), resized)
    out = _harden_alpha(out)
    return _remove_dark_specks(out)


def _harden_alpha(img: Image.Image, cut: int = 40) -> Image.Image:
    try:
        import numpy as np

        arr = np.array(img)
        arr[arr[:, :, 3] < cut, 3] = 0
        arr[arr[:, :, 3] >= cut, 3] = 255
        return Image.fromarray(arr, "RGBA")
    except ImportError:
        pixels = img.load()
        w, h = img.size
        for y in range(h):
            for x in range(w):
                r, g, b, a = pixels[x, y]
                if a < cut:
                    pixels[x, y] = (0, 0, 0, 0)
                else:
                    pixels[x, y] = (r, g, b, 255)
        return img


def pack_strip(src: Path, frame_count: int, out: Path) -> None:
    raw = Image.open(src)
    img = remove_backdrop(raw)
    boxes = segment_frames(img, frame_count)
    parts = [img.crop(box) for box in boxes]

    # Uniform scale across the sheet so characters don't pulse between frames.
    sizes: list[tuple[int, int]] = []
    for part in parts:
        bb = content_bbox(part)
        if bb is not None:
            sizes.append((bb[2] - bb[0], bb[3] - bb[1]))
    if sizes:
        max_w = max(w for w, _ in sizes)
        max_h = max(h for _, h in sizes)
        # Use ~92nd percentile so one oversized FX frame doesn't shrink everyone.
        widths = sorted(w for w, _ in sizes)
        heights = sorted(h for _, h in sizes)
        idx = max(0, int(len(widths) * 0.92) - 1)
        ref_w = max(widths[idx], 1)
        ref_h = max(heights[idx], 1)
        # Still respect the true max so nothing clips hard.
        ref_w = min(max_w, int(ref_w * 1.08))
        ref_h = min(max_h, int(ref_h * 1.08))
        scale = min((FRAME - 6) / ref_w, (FRAME - 4) / ref_h)
    else:
        scale = None

    cells = [fit_into_frame(part, scale) for part in parts]
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
