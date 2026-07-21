"""
Generate hexwing idle/walk/attack sheets with a real wing-flap cycle.

Morphs outer wing regions around shoulder pivots using PIL rotation so movement
reads as flight (not a walk bob).
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image

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


def body_core_mask(mask: np.ndarray, facing: str) -> np.ndarray:
    x0, y0, x1, y1 = content_bbox(mask)
    cx = (x0 + x1) * 0.5
    cy = (y0 + y1) * 0.5
    w = max(1.0, x1 - x0)
    h = max(1.0, y1 - y0)
    core = np.zeros_like(mask)
    ys, xs = np.where(mask)
    for x, y in zip(xs, ys):
        nx = (x - cx) / (w * 0.5)
        ny = (y - cy) / (h * 0.5)
        if facing == "side":
            in_body = (abs(nx) < 0.50 and ny > -0.05) or (ny > 0.22 and abs(nx) < 0.72)
            if nx > 0.0 and abs(ny + 0.05) < 0.55:
                in_body = True
        else:
            in_body = abs(nx) < 0.36 and ny > -0.30
            if abs(nx) < 0.26 and ny < -0.15:
                in_body = True
            if abs(nx) < 0.42 and ny > 0.32:
                in_body = True
        if in_body:
            core[y, x] = True
    return core


def wing_masks(mask: np.ndarray, body: np.ndarray, facing: str) -> tuple[np.ndarray, np.ndarray]:
    wings = mask & ~body
    if facing == "side":
        return wings.copy(), np.zeros_like(wings)

    x0, _y0, x1, _y1 = content_bbox(mask)
    cx = (x0 + x1) * 0.5
    left = wings.copy()
    right = wings.copy()
    ys, xs = np.where(wings)
    for x, y in zip(xs, ys):
        if x < cx:
            right[y, x] = False
        else:
            left[y, x] = False
    return left, right


def shoulder_pivots(mask: np.ndarray, facing: str) -> tuple[tuple[float, float], tuple[float, float]]:
    x0, y0, x1, y1 = content_bbox(mask)
    cx = (x0 + x1) * 0.5
    cy = y0 + (y1 - y0) * 0.40
    if facing == "side":
        p = (cx - 1.5, cy - 1.0)
        return p, p
    return (cx - 5.5, cy), (cx + 5.5, cy)


def rotate_masked(src: np.ndarray, mask: np.ndarray, pivot: tuple[float, float], angle_deg: float) -> Image.Image:
    """Extract mask region, rotate around pivot with PIL, return full-frame RGBA."""
    layer = np.zeros_like(src)
    layer[mask] = src[mask]
    if not mask.any() or abs(angle_deg) < 0.05:
        return Image.fromarray(layer, "RGBA")

    img = Image.fromarray(layer, "RGBA")
    # Expand so rotation doesn't clip, then place so pivot stays fixed.
    px, py = pivot
    # Translate pivot to center, rotate, translate back — via expanded canvas.
    pad = 28
    big = Image.new("RGBA", (FRAME + pad * 2, FRAME + pad * 2), (0, 0, 0, 0))
    big.alpha_composite(img, dest=(pad, pad))
    # Pivot in big coords.
    bpx, bpy = px + pad, py + pad
    rotated = big.rotate(-angle_deg, resample=Image.Resampling.BICUBIC, center=(bpx, bpy))
    # Crop back to FRAME.
    return rotated.crop((pad, pad, pad + FRAME, pad + FRAME))


def shift_image(img: Image.Image, dy: float) -> Image.Image:
    if abs(dy) < 0.05:
        return img
    out = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    out.alpha_composite(img, dest=(0, int(round(dy))))
    return out


def flap_pose(base: Image.Image, facing: str, wing_angle: float, bob: float = 0.0) -> Image.Image:
    """
    wing_angle degrees: positive = raise wings further up; negative = downstroke.
    Base art already has wings raised.
    """
    src = np.array(base)
    mask = content_mask(src)
    body = body_core_mask(mask, facing)
    left_m, right_m = wing_masks(mask, body, facing)
    lp, rp = shoulder_pivots(mask, facing)

    body_img = Image.fromarray(np.where(body[:, :, None], src, 0).astype(np.uint8), "RGBA")

    if facing == "side":
        # Side: positive raises wing (rotate CW visually for right-facing bird).
        wing_img = rotate_masked(src, left_m, lp, wing_angle * 1.15)
        composed = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
        composed.alpha_composite(wing_img)
        composed.alpha_composite(body_img)
    else:
        # Front/back: opposite rotations open/close the V.
        # Positive wing_angle => raise: left CCW (+), right CW (- ) in PIL's CW-positive? 
        # PIL rotate positive = CCW. To raise left wing (move tip up/out): rotate CCW = +angle.
        left_img = rotate_masked(src, left_m, lp, wing_angle)
        right_img = rotate_masked(src, right_m, rp, -wing_angle)
        composed = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
        composed.alpha_composite(left_img)
        composed.alpha_composite(right_img)
        composed.alpha_composite(body_img)

    return shift_image(composed, bob)


def stitch(frames: list[Image.Image]) -> Image.Image:
    sheet = Image.new("RGBA", (FRAME * len(frames), FRAME), (0, 0, 0, 0))
    for i, fr in enumerate(frames):
        sheet.alpha_composite(fr, dest=(i * FRAME, 0))
    return sheet


def make_walk_sheet(base: Image.Image, facing: str) -> Image.Image:
    # Smooth full flap with flight bob.
    keys = [
        (16.0, -1.2),
        (6.0, -0.3),
        (-8.0, 1.2),
        (-24.0, 2.4),
        (-12.0, 1.0),
        (2.0, -0.2),
        (12.0, -1.0),
        (16.0, -1.2),
    ]
    return stitch([flap_pose(base, facing, a, bob) for a, bob in keys])


def make_idle_sheet(base: Image.Image, facing: str) -> Image.Image:
    keys = [
        (8.0, -0.6),
        (0.0, 0.4),
        (-10.0, 1.2),
        (0.0, 0.0),
    ]
    return stitch([flap_pose(base, facing, a, bob) for a, bob in keys])


def make_attack_sheet(base: Image.Image, facing: str) -> Image.Image:
    # Raise to gather energy, then strong downstroke on fireball release (~frame 6).
    keys = [
        (4.0, 0.0),
        (12.0, -0.8),
        (20.0, -1.4),
        (16.0, -1.0),
        (2.0, 0.4),
        (-14.0, 1.6),
        (-28.0, 2.6),
        (-10.0, 1.0),
        (4.0, 0.0),
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

    print("Generating hexwing flap sheets...")
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
        flap_pose(front, "front", 16.0),
        flap_pose(front, "front", 0.0),
        flap_pose(front, "front", -24.0),
        flap_pose(side, "side", 16.0),
        flap_pose(side, "side", 0.0),
        flap_pose(side, "side", -24.0),
    ]
    save(stitch(extremes), PREVIEW / "hexwing_flap_preview.png")
    print("Done.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
