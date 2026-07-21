"""
Generate hexwing idle/walk/attack sheets with a sealed wing-flap cycle.

Only outer wing tips are warped. Shoulder roots and the full body stay as in
the base sprite, so the silhouette never tears open at the join.
"""

from __future__ import annotations

import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(r"C:\Repos\gameX")
REFS = ROOT / "tools" / "anim_refs"
OUT = ROOT / "assets" / "tilesets" / "mediterranean" / "Characters" / "hexwing"
PREVIEW = ROOT / "tools" / "anim_preview" / "frames"
FRAME = 80


def load_base(name: str) -> Image.Image:
    return Image.open(REFS / name).convert("RGBA")


def content_mask(arr: np.ndarray, threshold: int = 18) -> np.ndarray:
    return arr[:, :, 3] > threshold


def content_bbox(mask: np.ndarray) -> tuple[int, int, int, int]:
    ys, xs = np.where(mask)
    return int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())


def smoothstep(edge0: float, edge1: float, x: float) -> float:
    t = (x - edge0) / max(1e-6, edge1 - edge0)
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)


def dilate_mask(mask: np.ndarray, radius: int) -> np.ndarray:
    if radius <= 0:
        return mask.copy()
    img = Image.fromarray((mask.astype(np.uint8) * 255), mode="L")
    img = img.filter(ImageFilter.MaxFilter(radius * 2 + 1))
    return np.array(img) > 127


def body_lock_mask(mask: np.ndarray, facing: str) -> np.ndarray:
    """Rigid core + shoulder roots — never modified."""
    x0, y0, x1, y1 = content_bbox(mask)
    cx = (x0 + x1) * 0.5
    cy = (y0 + y1) * 0.5
    w = max(1.0, float(x1 - x0))
    h = max(1.0, float(y1 - y0))
    core = np.zeros_like(mask)
    ys, xs = np.where(mask)
    for x, y in zip(xs, ys):
        nx = (x - cx) / (w * 0.5)
        ny = (y - cy) / (h * 0.5)
        if facing == "side":
            locked = (
                (abs(nx) < 0.68 and ny > -0.25)
                or (nx > -0.10 and abs(ny) < 0.65)
                or (ny > 0.15 and abs(nx) < 0.85)
            )
        else:
            # Wide column so shoulders stay glued to torso.
            locked = (
                abs(nx) < 0.48
                or (abs(nx) < 0.62 and ny > 0.0)
                or (abs(nx) < 0.45 and ny < -0.05)
            )
        if locked:
            core[y, x] = True
    return dilate_mask(core, 2) & mask


def shoulder_pivots(mask: np.ndarray, facing: str) -> tuple[tuple[float, float], tuple[float, float]]:
    x0, y0, x1, y1 = content_bbox(mask)
    cx = (x0 + x1) * 0.5
    cy = y0 + (y1 - y0) * 0.45
    if facing == "side":
        p = (cx - 1.0, cy)
        return p, p
    return (cx - 2.0, cy), (cx + 2.0, cy)


def sample_bilinear(src: np.ndarray, x: float, y: float) -> np.ndarray:
    if x < -0.5 or y < -0.5 or x >= FRAME - 0.5 or y >= FRAME - 0.5:
        return np.zeros(4, dtype=np.float32)
    x = max(0.0, min(FRAME - 1.001, x))
    y = max(0.0, min(FRAME - 1.001, y))
    x0 = int(math.floor(x))
    y0 = int(math.floor(y))
    x1 = min(FRAME - 1, x0 + 1)
    y1 = min(FRAME - 1, y0 + 1)
    fx = x - x0
    fy = y - y0
    c00 = src[y0, x0].astype(np.float32)
    c10 = src[y0, x1].astype(np.float32)
    c01 = src[y1, x0].astype(np.float32)
    c11 = src[y1, x1].astype(np.float32)
    top = c00 * (1.0 - fx) + c10 * fx
    bot = c01 * (1.0 - fx) + c11 * fx
    return top * (1.0 - fy) + bot * fy


def tip_weight(facing: str, nx: float, ny: float, dist: float) -> float:
    """0 at shoulder roots, 1 at outer tips. Roots never move."""
    if facing == "side":
        w = smoothstep(8.0, 20.0, dist)
        if ny > 0.25:
            w *= 0.15
        return w
    # Front/back: require being clearly lateral AND away from pivot.
    radial = smoothstep(8.0, 20.0, dist)
    lateral = smoothstep(0.40, 0.85, abs(nx))
    # Upper tips flap more; lower fringe less (avoids tearing near talons).
    vertical = 0.55 + 0.45 * smoothstep(0.2, -0.6, ny)
    return radial * lateral * vertical


def warp_wing_tips(src: np.ndarray, facing: str, wing_angle: float, body: np.ndarray) -> np.ndarray:
    """
    Non-destructive tip warp:
    - Start from a full copy (roots stay connected).
    - Only overwrite outer tip destinations.
    - Erase only the original tip pixels that actually moved away.
    """
    if abs(wing_angle) < 0.05:
        return src.copy()

    mask = content_mask(src)
    x0, y0, x1, y1 = content_bbox(mask)
    cx = (x0 + x1) * 0.5
    cy = (y0 + y1) * 0.5
    w = max(1.0, float(x1 - x0))
    h = max(1.0, float(y1 - y0))
    lp, rp = shoulder_pivots(mask, facing)

    wing = mask & ~body
    out = src.copy().astype(np.float32)

    # 1) Erase only high-weight tip origins (they will be redrawn at new pose).
    ys, xs = np.where(wing)
    for x, y in zip(xs, ys):
        nx = (x - cx) / (w * 0.5)
        ny = (y - cy) / (h * 0.5)
        side = -1.0 if x < cx else 1.0
        pivot = lp if (facing != "side" and side < 0) else (rp if facing != "side" else lp)
        dist = math.hypot(float(x) - pivot[0], float(y) - pivot[1])
        weight = tip_weight(facing, nx, ny, dist)
        if weight > 0.45:
            out[y, x] = 0.0

    # 2) Inverse-map tip destinations into the cleared/halo region.
    dest = dilate_mask(wing, 4) & ~body
    ty, tx = np.where(dest)
    for x, y in zip(tx, ty):
        nx = (x - cx) / (w * 0.5)
        ny = (y - cy) / (h * 0.5)
        side = -1.0 if x < cx else 1.0
        pivot = lp if (facing != "side" and side < 0) else (rp if facing != "side" else lp)
        dist = math.hypot(float(x) - pivot[0], float(y) - pivot[1])
        weight = tip_weight(facing, nx, ny, dist)
        if weight < 0.12:
            continue

        if facing == "side":
            angle = math.radians(wing_angle * weight)
        else:
            angle = math.radians(wing_angle * side * weight)

        cos_a = math.cos(angle)
        sin_a = math.sin(angle)
        rdx = float(x) - pivot[0]
        rdy = float(y) - pivot[1]
        sx = pivot[0] + rdx * cos_a + rdy * sin_a
        sy = pivot[1] - rdx * sin_a + rdy * cos_a
        sample = sample_bilinear(src, sx, sy)
        if sample[3] < 12.0:
            continue

        # Soft blend near the root so joins stay continuous.
        if weight < 0.55 and out[y, x, 3] > 12.0:
            t = smoothstep(0.12, 0.55, weight)
            a0 = out[y, x, 3] / 255.0
            a1 = sample[3] / 255.0
            ao = a0 * (1.0 - t) + a1 * t
            if ao > 1e-4:
                rgb = (out[y, x, :3] * a0 * (1.0 - t) + sample[:3] * a1 * t) / ao
                out[y, x, :3] = rgb
                out[y, x, 3] = ao * 255.0
        else:
            out[y, x] = sample

    # 3) Force original body + shoulder roots back on top.
    out[body] = src[body].astype(np.float32)
    return np.clip(out, 0, 255).astype(np.uint8)


def fill_shoulder_cracks(arr: np.ndarray, src: np.ndarray, body: np.ndarray) -> np.ndarray:
    """Close 1px cracks between locked body and nearby wing pixels."""
    out = arr.copy()
    body_edge = dilate_mask(body, 1) & ~body
    wing = content_mask(arr) & ~body
    near_wing = dilate_mask(wing, 1)
    cracks = body_edge & near_wing & (out[:, :, 3] < 18)
    # Also any transparent pixel that had body-or-wing neighbors in source.
    src_solid = content_mask(src)
    extra = dilate_mask(body, 2) & dilate_mask(wing, 2) & (out[:, :, 3] < 18) & src_solid
    cracks |= extra

    ys, xs = np.where(cracks)
    for x, y in zip(xs, ys):
        acc = np.zeros(4, dtype=np.float32)
        n = 0.0
        for dy in range(-1, 2):
            for dx in range(-1, 2):
                if dx == 0 and dy == 0:
                    continue
                xx, yy = x + dx, y + dy
                if not (0 <= xx < FRAME and 0 <= yy < FRAME):
                    continue
                pix = out[yy, xx]
                if pix[3] < 18:
                    pix = src[yy, xx]
                if pix[3] < 18:
                    continue
                acc += pix.astype(np.float32)
                n += 1.0
        if n > 0.0:
            out[y, x] = (acc / n).astype(np.uint8)
            out[y, x, 3] = max(int(out[y, x, 3]), 230)
    out[body] = src[body]
    return out


def shift_image(img: Image.Image, dy: float) -> Image.Image:
    if abs(dy) < 0.05:
        return img
    out = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    out.alpha_composite(img, dest=(0, int(round(dy))))
    return out


def flap_pose(base: Image.Image, facing: str, wing_angle: float, bob: float = 0.0) -> Image.Image:
    src = np.array(base)
    body = body_lock_mask(content_mask(src), facing)
    warped = warp_wing_tips(src, facing, wing_angle, body)
    sealed = fill_shoulder_cracks(warped, src, body)
    return shift_image(Image.fromarray(sealed, "RGBA"), bob)


def stitch(frames: list[Image.Image]) -> Image.Image:
    sheet = Image.new("RGBA", (FRAME * len(frames), FRAME), (0, 0, 0, 0))
    for i, fr in enumerate(frames):
        sheet.alpha_composite(fr, dest=(i * FRAME, 0))
    return sheet


def make_walk_sheet(base: Image.Image, facing: str) -> Image.Image:
    keys = [
        (12.0, -0.6),
        (4.0, -0.2),
        (-6.0, 0.6),
        (-14.0, 1.2),
        (-7.0, 0.5),
        (2.0, -0.1),
        (8.0, -0.4),
        (12.0, -0.6),
    ]
    return stitch([flap_pose(base, facing, a, bob) for a, bob in keys])


def make_idle_sheet(base: Image.Image, facing: str) -> Image.Image:
    keys = [
        (5.0, -0.3),
        (0.0, 0.2),
        (-6.0, 0.6),
        (0.0, 0.0),
    ]
    return stitch([flap_pose(base, facing, a, bob) for a, bob in keys])


def make_attack_sheet(base: Image.Image, facing: str) -> Image.Image:
    keys = [
        (2.0, 0.0),
        (7.0, -0.4),
        (12.0, -0.8),
        (8.0, -0.5),
        (1.0, 0.2),
        (-8.0, 0.9),
        (-15.0, 1.4),
        (-6.0, 0.5),
        (2.0, 0.0),
    ]
    return stitch([flap_pose(base, facing, a, bob) for a, bob in keys])


def save(img: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)
    print(f"  wrote {path.relative_to(ROOT)}")


def main() -> int:
    PREVIEW.mkdir(parents=True, exist_ok=True)
    front = load_base("hexwing_base.png")
    side = load_base("hexwing_side_base.png")
    back = load_base("hexwing_back_base.png")

    print("Generating sealed hexwing flap sheets...")
    save(make_idle_sheet(front, "front"), OUT / "chr_hexwing_idle.png")
    save(make_idle_sheet(back, "back"), OUT / "chr_hexwing_idle_back.png")
    save(make_idle_sheet(side, "side"), OUT / "chr_hexwing_idle_side.png")

    save(make_walk_sheet(front, "front"), OUT / "chr_hexwing_run_downward.png")
    save(make_walk_sheet(back, "back"), OUT / "chr_hexwing_run_upward.png")
    save(make_walk_sheet(back, "back"), OUT / "chr_hexwing_run_backward.png")
    save(make_walk_sheet(side, "side"), OUT / "chr_hexwing_run_side.png")

    save(make_attack_sheet(front, "front"), OUT / "chr_hexwing_attack.png")
    save(make_attack_sheet(back, "back"), OUT / "chr_hexwing_attack_back.png")
    save(make_attack_sheet(side, "side"), OUT / "chr_hexwing_attack_side.png")

    extremes = [
        flap_pose(front, "front", 12.0),
        flap_pose(front, "front", 0.0),
        flap_pose(front, "front", -14.0),
        flap_pose(side, "side", 12.0),
        flap_pose(side, "side", 0.0),
        flap_pose(side, "side", -14.0),
    ]
    save(stitch(extremes), PREVIEW / "hexwing_flap_preview.png")

    zooms = [
        flap_pose(front, "front", a).crop((18, 28, 62, 62)).resize((176, 136), Image.Resampling.NEAREST)
        for a in (12.0, 0.0, -8.0, -14.0)
    ]
    diag = Image.new("RGBA", (176 * 4 + 12, 136), (12, 12, 12, 255))
    for i, z in enumerate(zooms):
        diag.paste(z, (i * (176 + 4), 0))
    save(diag, PREVIEW / "hexwing_shoulder_zoom.png")
    print("Done.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
