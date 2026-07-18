"""Build back-facing work strips from AI poses (tool working ahead of the unit)."""

from __future__ import annotations

import shutil
from pathlib import Path

import numpy as np
from PIL import Image

from import_directional_bases import remove_light_background
from normalize_anim_sheets import content_bbox, harden_alpha

FRAME = 80
CHARS = Path(r"C:\Repos\gameX\assets\tilesets\mediterranean\Characters")
POSE_DIR = Path(r"C:\Repos\gameX\tools\ai_poses")
AI_DIR = Path(r"C:\Users\Manu\.cursor\projects\c-Repos-gameX\assets")

SPECS = {
    "villager": {
        "raise": "villager_back_pose_raise.png",
        "strike": "villager_back_pose_strike.png",
        "out": "chr_villager_afk_back.png",
        "sequence": [0, 1, 1, 1, 2, 2, 2, 1, 0],
    },
    "builder": {
        "raise": "builder_back_pose_raise.png",
        "strike": "builder_back_pose_strike.png",
        "out": "chr_builder_afk_back.png",
        "sequence": [0, 1, 1, 1, 2, 2, 2, 1, 0],
    },
}


def collect(name: str) -> Path:
    src = AI_DIR / name
    if src.exists():
        POSE_DIR.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, POSE_DIR / name)
        return POSE_DIR / name
    local = POSE_DIR / name
    if local.exists():
        return local
    raise FileNotFoundError(name)


def idle_frame(unit: str) -> Image.Image:
    path = CHARS / unit / f"chr_{unit}_idle.png"
    return harden_alpha(Image.open(path).convert("RGBA").crop((0, 0, FRAME, FRAME)), cut=30)


def back_idle_frame(unit: str) -> Image.Image:
    path = CHARS / unit / f"chr_{unit}_idle_back.png"
    return harden_alpha(Image.open(path).convert("RGBA").crop((0, 0, FRAME, FRAME)), cut=30)


def silhouette_h(im: Image.Image) -> int:
    arr = np.array(im)
    mask = arr[:, :, 3] > 40
    if not mask.any():
        return 1
    ys = np.where(mask)[0]
    return int(ys.max() - ys.min() + 1)


def fit_pose_to_idle(src: Path, unit: str) -> Image.Image:
    """Fit pose to the same foot line / height as front idle (no mass shrink)."""
    idle = idle_frame(unit)
    foot_y = content_bbox(idle)[3]
    target_h = silhouette_h(idle)
    cleaned = remove_light_background(Image.open(src))
    cleaned = harden_alpha(cleaned, cut=40)
    bb = cleaned.getbbox()
    canvas = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    if bb is None:
        return canvas
    cropped = cleaned.crop(bb)
    scale = target_h / max(1, cropped.height)
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


def stitch(frames: list[Image.Image]) -> Image.Image:
    sheet = Image.new("RGBA", (FRAME * len(frames), FRAME), (0, 0, 0, 0))
    for i, fr in enumerate(frames):
        sheet.alpha_composite(fr, (i * FRAME, 0))
    return sheet


def build_unit(unit: str) -> None:
    spec = SPECS[unit]
    bank = [
        back_idle_frame(unit),
        fit_pose_to_idle(collect(spec["raise"]), unit),
        fit_pose_to_idle(collect(spec["strike"]), unit),
    ]
    frames = [bank[i] for i in spec["sequence"]]
    sheet = stitch(frames)
    out = CHARS / unit / spec["out"]
    sheet.save(out)
    print(f"wrote {out} size={sheet.size} pose_h={[silhouette_h(f) for f in bank]}")


def main() -> None:
    for unit in SPECS:
        build_unit(unit)
    print("Done.")


if __name__ == "__main__":
    main()
