"""Build side-facing work strips from AI poses (body + tool in sync)."""

from __future__ import annotations

import shutil
from pathlib import Path

import numpy as np
from PIL import Image

from import_directional_bases import remove_light_background
from normalize_anim_sheets import body_height, content_bbox, harden_alpha

FRAME = 80
CHARS = Path(r"C:\Repos\gameX\assets\tilesets\mediterranean\Characters")
POSE_DIR = Path(r"C:\Repos\gameX\tools\ai_poses")
AI_DIR = Path(r"C:\Users\Manu\.cursor\projects\c-Repos-gameX\assets")
PREVIEWS = Path(r"C:\Repos\gameX\tools\anim_preview")

SPECS = {
    "villager": {
        "raise": "villager_side_pose_raise.png",
        "strike": "villager_side_pose_strike.png",
        "out": "chr_villager_afk_side.png",
        "sequence": [0, 1, 1, 1, 2, 2, 2, 1, 0],
        # Strike AI art is much denser/wider when bent; shrink so it matches idle.
        "raise_shrink": 0.92,
        "strike_shrink": 0.66,
    },
}


def collect(name: str) -> Path:
    src = AI_DIR / name
    if src.exists():
        POSE_DIR.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, POSE_DIR / name)
    local = POSE_DIR / name
    if local.exists():
        return local
    raise FileNotFoundError(name)


def side_idle_frame(unit: str) -> Image.Image:
    path = CHARS / unit / f"chr_{unit}_idle_side.png"
    return harden_alpha(Image.open(path).convert("RGBA").crop((0, 0, FRAME, FRAME)), cut=30)


def silhouette_h(im: Image.Image) -> int:
    arr = np.array(im)
    mask = arr[:, :, 3] > 40
    if not mask.any():
        return 1
    ys = np.where(mask)[0]
    return int(ys.max() - ys.min() + 1)


def _row_widths(solid: np.ndarray) -> np.ndarray:
    h = solid.shape[0]
    widths = np.zeros(h, dtype=np.int32)
    for y in range(h):
        cols = np.where(solid[y])[0]
        if len(cols):
            widths[y] = int(cols[-1] - cols[0] + 1)
    return widths


def _hat_metrics(im: Image.Image) -> tuple[int, int]:
    """Return (feet→hat height, hat brim width)."""
    arr = np.array(im.convert("RGBA"))
    solid = arr[:, :, 3] >= 120
    mass = solid.sum(axis=1)
    rows = np.where(mass >= 3)[0]
    if len(rows) == 0:
        return 1, 1
    top = int(rows[0])
    foot = int(rows[-1])
    span = max(foot - top, 1)
    search_lo = top
    search_hi = top + max(3, int(span * 0.45))
    widths = _row_widths(solid)
    segment = widths[search_lo:search_hi]
    if segment.size == 0 or segment.max() < 4:
        return body_height(im), 1
    hat_y = search_lo + int(np.argmax(segment))
    return max(foot - hat_y + 1, 1), int(segment.max())


def foot_to_hat_height(im: Image.Image) -> int:
    return _hat_metrics(im)[0]


def place_on_feet(cropped: Image.Image, scale: float, foot_y: int) -> Image.Image:
    canvas = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    nw = max(1, int(round(cropped.width * scale)))
    nh = max(1, int(round(cropped.height * scale)))
    fitted = cropped.resize((nw, nh), Image.Resampling.LANCZOS)
    px = (FRAME - nw) // 2
    py = foot_y - nh
    if py < 0:
        fitted = fitted.crop((0, -py, nw, nh))
        nh = fitted.height
        py = foot_y - nh
    if nw > FRAME:
        x0 = (nw - FRAME) // 2
        fitted = fitted.crop((x0, 0, x0 + FRAME, nh))
        nw = fitted.width
        px = 0
    px = max(0, min(FRAME - nw, px))
    py = max(0, min(FRAME - nh, py))
    canvas.alpha_composite(fitted, (px, py))
    return harden_alpha(canvas, cut=40)


def fit_pose_to_side_idle(
    src: Path,
    unit: str,
    *,
    style_shrink: float = 1.0,
) -> Image.Image:
    """
    Fit raise/strike to the side-idle character size.

    Uses dense body-mass height (feet→torso/head) so a raised hoe cannot
    inflate the standing silhouette. `style_shrink` pulls chunky AI poses
    (especially the bent strike) back down to idle visual weight.
    """
    idle = side_idle_frame(unit)
    foot_y = content_bbox(idle)[3]
    ref_h = body_height(idle)

    cleaned = remove_light_background(Image.open(src))
    cleaned = harden_alpha(cleaned, cut=40)
    bb = cleaned.getbbox()
    if bb is None:
        return Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    cropped = cleaned.crop(bb)

    pose_h = body_height(cropped)
    scale = (ref_h / max(pose_h, 1)) * style_shrink
    return place_on_feet(cropped, scale, foot_y)


def stitch(frames: list[Image.Image]) -> Image.Image:
    sheet = Image.new("RGBA", (FRAME * len(frames), FRAME), (0, 0, 0, 0))
    for i, fr in enumerate(frames):
        sheet.alpha_composite(fr, (i * FRAME, 0))
    return sheet


def _write_preview(unit: str, bank: list[Image.Image], sheet: Image.Image) -> None:
    PREVIEWS.mkdir(parents=True, exist_ok=True)
    preview = Image.new("RGBA", (FRAME * 3 * 3, FRAME * 3), (40, 80, 40, 255))
    for i, fr in enumerate(bank):
        big = fr.resize((FRAME * 3, FRAME * 3), Image.Resampling.NEAREST)
        preview.alpha_composite(big, (i * FRAME * 3, 0))
    preview.save(PREVIEWS / f"verify_{unit}_side_work_bank.png")
    strip = sheet.resize((sheet.width * 2, sheet.height * 2), Image.Resampling.NEAREST)
    strip.save(PREVIEWS / f"verify_{unit}_side_work_strip.png")


def build_unit(unit: str) -> None:
    spec = SPECS[unit]
    bank = [
        side_idle_frame(unit),
        fit_pose_to_side_idle(
            collect(spec["raise"]), unit, style_shrink=spec.get("raise_shrink", 1.0)
        ),
        fit_pose_to_side_idle(
            collect(spec["strike"]), unit, style_shrink=spec.get("strike_shrink", 1.0)
        ),
    ]
    frames = [bank[i] for i in spec["sequence"]]
    sheet = stitch(frames)
    out = CHARS / unit / spec["out"]
    sheet.save(out)
    _write_preview(unit, bank, sheet)
    print(
        f"wrote {out} size={sheet.size} "
        f"sil_h={[silhouette_h(f) for f in bank]} "
        f"foot_hat={[foot_to_hat_height(f) for f in bank]} "
        f"body_h={[body_height(f) for f in bank]}"
    )


def main() -> None:
    for unit in SPECS:
        build_unit(unit)
    print("Done.")


if __name__ == "__main__":
    main()
