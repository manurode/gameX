#!/usr/bin/env python3
"""Build mage/ember/mire/hexwing with the SAME pipeline as knight/archer/enemy.

Sources (single poses, not full strips):
  tools/ai_poses/{unit}_front_base.png
  tools/ai_poses/{unit}_back_base.png
  tools/ai_poses/{unit}_side_base.png
  tools/ai_poses/{unit}_pose_windup.png
  tools/ai_poses/{unit}_pose_cast.png
  tools/ai_poses/{unit}_pose_follow.png
  tools/ai_poses/{unit}_back_pose_cast.png   (optional)
  tools/ai_poses/{unit}_side_pose_cast.png   (optional)

Pipeline mirrors import_directional_bases + normalize_anim_sheets:
  - punch light/black studio backdrop
  - fit_to_idle with STYLE_SHRINK against knight body height (pack scale)
  - procedural walks via make_walk
  - attack sheets stitched from idle + keyposes
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))

from generate_unit_animations import (  # noqa: E402
    FRAME,
    make_walk,
    place_sprite,
    save,
    to_sprite,
)
from normalize_anim_sheets import (  # noqa: E402
    STYLE_SHRINK,
    body_height,
    content_bbox,
    fit_to_idle,
    harden_alpha,
)

CHARS = ROOT / "assets/tilesets/mediterranean/Characters"
REFS = ROOT / "tools/anim_refs"
POSE_DIR = ROOT / "tools/ai_poses"
CURSOR_ASSETS = Path(r"C:\Users\Manu\.cursor\projects\c-Repos-gameX\assets")

UNITS = ("mage", "ember", "mire", "hexwing")


def _find_src(name: str) -> Path | None:
    for folder in (POSE_DIR, CURSOR_ASSETS, ROOT / "tools/sprite_gen/refs"):
        p = folder / name
        if p.exists():
            return p
    return None


def remove_studio_background(im: Image.Image) -> Image.Image:
    """Handle white studio (directional bases) OR black studio (attack poses)."""
    arr = np.array(im.convert("RGBA"))
    rgb = arr[:, :, :3].astype(np.int16)
    # Near-white / light gray canvas (match import_directional_bases)
    light = (rgb.min(axis=2) >= 220) | (
        (rgb.max(axis=2) >= 240) & (rgb.min(axis=2) >= 200)
    )
    arr[light, 3] = 0
    # Near-black studio
    black = rgb.max(axis=2) <= 18
    arr[black, 3] = 0
    # If still fully opaque, fall back to luma key
    if arr[:, :, 3].min() >= 250:
        lum = rgb.max(axis=2)
        arr[lum <= 22, 3] = 0
        arr[lum > 22, 3] = 255

    # Despill white fringe on edges (AA against white studio).
    alpha = arr[:, :, 3]
    mx = rgb.max(axis=2)
    mn = rgb.min(axis=2)
    pale = (mn >= 165) & ((mx - mn) <= 30) & (alpha > 0)
    # Drop pale pixels that have a transparent neighbor (true edge fringe).
    if pale.any():
        h, w = alpha.shape
        for y, x in zip(*np.where(pale)):
            y0, y1 = max(0, y - 1), min(h, y + 2)
            x0, x1 = max(0, x - 1), min(w, x + 2)
            if (alpha[y0:y1, x0:x1] < 40).any():
                arr[y, x, 3] = 0

    return Image.fromarray(arr, "RGBA")


def load_knight_metrics() -> tuple[int, int]:
    idle = Image.open(CHARS / "knight" / "chr_knight_idle.png").convert("RGBA")
    fr = harden_alpha(idle.crop((0, 0, FRAME, FRAME)), cut=30)
    return body_height(fr), content_bbox(fr)[3]


def fit_pose(src: Path, ref_h: int, foot_y: int) -> Image.Image:
    cleaned = remove_studio_background(Image.open(src))
    fitted = fit_to_idle(cleaned, ref_h, foot_y)
    return harden_alpha(to_sprite(fitted, threshold=14), cut=40)


def make_idle_sheet(base: Image.Image, frames: int = 4) -> Image.Image:
    sheet = Image.new("RGBA", (FRAME * frames, FRAME), (0, 0, 0, 0))
    for i in range(frames):
        # Tiny breathing bob on later frames (matches pack feel)
        dy = 0.0 if i == 0 else -0.4 * (i % 2)
        fr = place_sprite(base, dy=dy) if abs(dy) > 0.01 else base
        sheet.alpha_composite(fr, (i * FRAME, 0))
    return sheet


def make_deploy_sheet(base: Image.Image, frames: int) -> Image.Image:
    """Death/deploy: sink + squash, same idea as other combat units' short strips."""
    sheet = Image.new("RGBA", (FRAME * frames, FRAME), (0, 0, 0, 0))
    for i in range(frames):
        t = i / max(frames - 1, 1)
        fr = place_sprite(
            base,
            dy=t * 10.0,
            squash_y=1.0 - t * 0.45,
            scale=1.0 - t * 0.12,
        )
        sheet.alpha_composite(harden_alpha(fr, cut=40), (i * FRAME, 0))
    return sheet


def stitch(frames: list[Image.Image], path: Path) -> None:
    sheet = Image.new("RGBA", (FRAME * len(frames), FRAME), (0, 0, 0, 0))
    for i, fr in enumerate(frames):
        sheet.alpha_composite(fr, (i * FRAME, 0))
    path.parent.mkdir(parents=True, exist_ok=True)
    save(sheet, path)


def build_unit(unit: str, knight_h: int, knight_foot: int) -> None:
    unit_dir = CHARS / unit
    unit_dir.mkdir(parents=True, exist_ok=True)
    REFS.mkdir(parents=True, exist_ok=True)

    front_src = _find_src(f"{unit}_front_base.png")
    if front_src is None:
        # Allow ref_* as front fallback
        front_src = _find_src(f"ref_{unit}.png")
    if front_src is None:
        raise FileNotFoundError(f"Missing front base for {unit}")

    # Front idle: match PACK scale (knight). Compensate STYLE_SHRINK inside fit_to_idle
    # so the result lands near knight body height (not 15% smaller).
    front_ref_h = max(1, int(round(knight_h / STYLE_SHRINK)))
    front = fit_pose(front_src, front_ref_h, knight_foot)
    front.save(REFS / f"{unit}_base.png")
    save(make_idle_sheet(front, 4), unit_dir / f"chr_{unit}_idle.png")
    print(f"{unit}: front body_h={body_height(front)} (knight={knight_h})")

    # Subsequent facings match this unit's front idle.
    ref_h = body_height(front)
    foot_y = content_bbox(front)[3]

    bases = {"front": front}
    for facing in ("back", "side"):
        src = _find_src(f"{unit}_{facing}_base.png")
        if src is None:
            print(f"  WARN missing {unit}_{facing}_base.png — mirroring front")
            bases[facing] = front
        else:
            bases[facing] = fit_pose(src, ref_h, foot_y)
            bases[facing].save(REFS / f"{unit}_{facing}_base.png")
        save(make_idle_sheet(bases[facing], 4), unit_dir / f"chr_{unit}_idle_{facing}.png")

    # Procedural walks (same as knight/archer).
    save(make_walk(bases["front"], False), unit_dir / f"chr_{unit}_run_downward.png")
    save(make_walk(bases["back"], True), unit_dir / f"chr_{unit}_run_upward.png")
    save(make_walk(bases["back"], True), unit_dir / f"chr_{unit}_run_backward.png")
    save(make_walk(bases["side"], False), unit_dir / f"chr_{unit}_run_side.png")

    # Attack from keyposes (idle + windup + cast + follow).
    pose_names = [
        f"{unit}_pose_windup.png",
        f"{unit}_pose_cast.png",
        f"{unit}_pose_follow.png",
    ]
    poses = []
    for name in pose_names:
        src = _find_src(name)
        if src is None:
            print(f"  WARN missing {name}")
            poses.append(front)
        else:
            poses.append(fit_pose(src, ref_h, foot_y))
    bank = [front, *poses]
    # Same cadence as knight/enemy: [0,1,1,1,2,2,3,3,0]
    seq = [0, 1, 1, 1, 2, 2, 3, 3, 0]
    stitch([bank[i] for i in seq], unit_dir / f"chr_{unit}_attack.png")

    # Back attack
    back = bases["back"]
    back_cast_src = _find_src(f"{unit}_back_pose_cast.png")
    back_cast = fit_pose(back_cast_src, body_height(back), content_bbox(back)[3]) if back_cast_src else back
    back_bank = [back, back_cast]
    back_seq = [0, 0, 1, 1, 1, 1, 1, 0, 0]
    stitch([back_bank[min(i, len(back_bank) - 1)] for i in back_seq], unit_dir / f"chr_{unit}_attack_back.png")

    # Side attack
    side = bases["side"]
    side_cast_src = _find_src(f"{unit}_side_pose_cast.png")
    side_cast = fit_pose(side_cast_src, body_height(side), content_bbox(side)[3]) if side_cast_src else side
    side_bank = [side, side_cast]
    side_seq = [0, 0, 1, 1, 1, 1, 1, 0, 0]
    stitch([side_bank[min(i, len(side_bank) - 1)] for i in side_seq], unit_dir / f"chr_{unit}_attack_side.png")

    # Deploy / death
    save(make_deploy_sheet(front, 4), unit_dir / f"chr_{unit}_deploy.png")
    save(make_deploy_sheet(back, 3), unit_dir / f"chr_{unit}_deploy_back.png")
    print(f"  OK {unit} sheets written (STYLE_SHRINK={STYLE_SHRINK})")


def main() -> int:
    knight_h, knight_foot = load_knight_metrics()
    print(f"Knight reference: body_h={knight_h} foot_y={knight_foot}")
    missing: list[str] = []
    for unit in UNITS:
        try:
            build_unit(unit, knight_h, knight_foot)
        except FileNotFoundError as e:
            missing.append(str(e))
            print(f"FAIL {unit}: {e}")
    if missing:
        print("MISSING sources:")
        for m in missing:
            print(" ", m)
        return 1
    print("All new units built with pack pipeline.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
