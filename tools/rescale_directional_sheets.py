"""Shrink back/side sheets to match ORIGINAL front idle (never enlarge idle).

Scale is limited by both silhouette height and opaque-pixel mass so denser
back art (cape/quiver) does not read larger than the front idle.
Does NOT modify chr_*_idle.png or front walk/attack sheets.
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image

from normalize_anim_sheets import content_bbox, harden_alpha

FRAME = 80
CHARS = Path(r"C:\Repos\gameX\assets\tilesets\mediterranean\Characters")
UNITS = ("villager", "builder", "knight", "archer", "enemy")
FINAL_UNDER = 0.98  # never land larger than idle

SHEET_GLOBS = (
    "chr_{u}_idle_back.png",
    "chr_{u}_idle_side.png",
    "chr_{u}_run_upward.png",
    "chr_{u}_run_backward.png",
    "chr_{u}_run_side.png",
    "chr_{u}_attack_back.png",
    "chr_{u}_attack_side.png",
    "chr_{u}_afk_back.png",
    "chr_{u}_afk_side.png",
    "chr_{u}_deploy_back.png",
)


def frame_stats(im: Image.Image) -> tuple[int, int, int]:
    arr = np.array(harden_alpha(im.convert("RGBA"), cut=30))
    mask = arr[:, :, 3] > 40
    if not mask.any():
        return 0, 0, 0
    ys, xs = np.where(mask)
    return int(ys.max() - ys.min() + 1), int(xs.max() - xs.min() + 1), int(mask.sum())


def idle_ref(unit: str) -> tuple[int, int, int]:
    idle = Image.open(CHARS / unit / f"chr_{unit}_idle.png").convert("RGBA")
    frame = idle.crop((0, 0, FRAME, FRAME))
    h, _w, px = frame_stats(frame)
    foot_y = content_bbox(harden_alpha(frame, cut=30))[3]
    return max(1, h), max(1, px), foot_y


def rescale_frame(
    frame: Image.Image, idle_h: int, idle_px: int, foot_y: int
) -> Image.Image:
    frame = harden_alpha(frame.convert("RGBA"), cut=30)
    bb = frame.getbbox()
    canvas = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    if bb is None:
        return canvas
    cropped = frame.crop(bb)
    pose_h, _pw, pose_px = frame_stats(cropped)
    if pose_h <= 0:
        return canvas
    scale_h = idle_h / pose_h
    scale_px = (idle_px / max(pose_px, 1)) ** 0.5
    scale = min(scale_h, scale_px) * FINAL_UNDER
    scale = max(0.5, min(scale, 1.0))
    max_scale = min((FRAME - 2) / max(cropped.width, 1), (FRAME - 2) / max(cropped.height, 1))
    scale = min(scale, max_scale)
    nw = max(1, int(round(cropped.width * scale)))
    nh = max(1, int(round(cropped.height * scale)))
    fitted = cropped.resize((nw, nh), Image.Resampling.LANCZOS)
    px = (FRAME - nw) // 2
    py = foot_y - nh
    px = max(0, min(FRAME - nw, px))
    py = max(0, min(FRAME - nh, py))
    canvas.alpha_composite(fitted, (px, py))
    return harden_alpha(canvas, cut=40)


def rescale_sheet(path: Path, idle_h: int, idle_px: int, foot_y: int) -> None:
    im = Image.open(path).convert("RGBA")
    count = max(1, im.width // FRAME)
    out = Image.new("RGBA", (FRAME * count, FRAME), (0, 0, 0, 0))
    for i in range(count):
        fr = im.crop((i * FRAME, 0, (i + 1) * FRAME, FRAME))
        out.alpha_composite(rescale_frame(fr, idle_h, idle_px, foot_y), (i * FRAME, 0))
    out.save(path)
    h, _w, px = frame_stats(out.crop((0, 0, FRAME, FRAME)))
    print(
        f"  {path.name:32s} h={h} px={px} | idle h={idle_h} px={idle_px} "
        f"| h%={100 * h / idle_h:.0f} px%={100 * px / idle_px:.0f}"
    )


def main() -> None:
    for unit in UNITS:
        idle_h, idle_px, foot_y = idle_ref(unit)
        print(f"{unit}: front idle h={idle_h} px={idle_px} (NOT modified)")
        for pattern in SHEET_GLOBS:
            path = CHARS / unit / pattern.format(u=unit)
            if path.exists():
                rescale_sheet(path, idle_h, idle_px, foot_y)
    print("Done.")


if __name__ == "__main__":
    main()
