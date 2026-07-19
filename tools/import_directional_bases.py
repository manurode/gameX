"""Import AI-generated back/side bases, fit to idle size, rebuild directional sheets."""

from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image

from generate_unit_animations import (
    FRAME,
    make_attack,
    make_walk,
    make_work,
    save,
    to_sprite,
)
from normalize_anim_sheets import body_height, content_bbox, fit_to_idle, harden_alpha

ROOT = Path(r"C:\Repos\gameX")
CHARS = ROOT / "assets" / "tilesets" / "mediterranean" / "Characters"
REFS = ROOT / "tools" / "anim_refs"
AI_DIR = Path(r"C:\Users\Manu\.cursor\projects\c-Repos-gameX\assets")

UNITS = ("villager", "builder", "knight", "archer", "enemy")
COMBAT = ("knight", "archer", "enemy")
WORKERS = ("villager", "builder")


def load_idle(unit: str) -> Image.Image:
    path = CHARS / unit / f"chr_{unit}_idle.png"
    im = Image.open(path).convert("RGBA")
    return harden_alpha(im.crop((0, 0, FRAME, FRAME)), cut=30)


def remove_light_background(im: Image.Image, white_cut: int = 232) -> Image.Image:
    """AI exports are opaque on white/gray — punch that out before fitting."""
    arr = np.array(im.convert("RGBA"))
    rgb = arr[:, :, :3].astype(np.int16)
    # Near-white / light gray canvas
    light = (rgb.min(axis=2) >= white_cut) | (
        (rgb.max(axis=2) >= 245) & (rgb.min(axis=2) >= 210)
    )
    # Soft fringe around the character
    arr[light, 3] = 0
    # Also drop pure black leftover canvas if any
    black = rgb.max(axis=2) <= 8
    arr[black, 3] = 0
    return Image.fromarray(arr, "RGBA")


def fit_generated(src: Path, unit: str) -> Image.Image:
    """Fit AI art to match front idle silhouette height (keeps STYLE_SHRINK so backs stay small)."""
    idle = load_idle(unit)
    bb = content_bbox(idle)
    foot_y = bb[3]
    # Use body-mass height like attack normalize — closer to how idle reads in-game.
    ref_h = body_height(idle)
    cleaned = remove_light_background(Image.open(src))
    fitted = fit_to_idle(cleaned, ref_h, foot_y)
    return harden_alpha(to_sprite(fitted, threshold=14), cut=40)


def make_idle_sheet(base: Image.Image, frames: int = 4) -> Image.Image:
    sheet = Image.new("RGBA", (FRAME * frames, FRAME), (0, 0, 0, 0))
    for i in range(frames):
        sheet.alpha_composite(base, (i * FRAME, 0))
    return sheet


def import_bases() -> dict[str, dict[str, Image.Image]]:
    REFS.mkdir(parents=True, exist_ok=True)
    out: dict[str, dict[str, Image.Image]] = {}
    for unit in UNITS:
        unit_bases: dict[str, Image.Image] = {"front": load_idle(unit)}
        for facing in ("back", "side"):
            src = AI_DIR / f"{unit}_{facing}_base_new.png"
            if not src.exists():
                print(f"MISSING {src}")
                continue
            fitted = fit_generated(src, unit)
            ref_name = f"{unit}_{facing}_base.png"
            fitted.save(REFS / ref_name)
            # Also stash under Characters for idle sheets
            unit_dir = CHARS / unit
            unit_dir.mkdir(parents=True, exist_ok=True)
            idle_name = f"chr_{unit}_idle_{facing}.png"
            save(make_idle_sheet(fitted), unit_dir / idle_name)
            unit_bases[facing] = fitted
            print(f"imported {unit}/{facing}")
        out[unit] = unit_bases
    return out


def _fit_pose(name: str, unit: str, facing_base: Image.Image) -> Image.Image:
    src = AI_DIR / name
    if not src.exists():
        src = Path(r"C:\Repos\gameX\tools\ai_poses") / name
    if not src.exists():
        raise FileNotFoundError(name)
    foot_y = content_bbox(facing_base)[3]
    ref_h = body_height(facing_base)
    cleaned = remove_light_background(Image.open(src))
    return harden_alpha(fit_to_idle(cleaned, ref_h, foot_y), cut=40)


def build_directional_attacks(bases: dict[str, dict[str, Image.Image]]) -> None:
    """Stitch AI attack keyframes onto back/side idle bases."""
    specs = {
        "knight": {
            "back": {
                "poses": ["knight_back_pose_windup.png", "knight_back_pose_slash.png"],
                "sequence": [0, 1, 1, 1, 2, 2, 2, 1, 0],
                "out": "chr_knight_attack_back.png",
            },
            "side": {
                "poses": ["knight_side_pose_slash.png"],
                "sequence": [0, 0, 1, 1, 1, 1, 1, 0, 0],
                "out": "chr_knight_attack_side.png",
            },
        },
        "archer": {
            "back": {
                "poses": ["archer_back_pose_draw.png"],
                "sequence": [0, 1, 1, 1, 1, 1, 1, 1, 0],
                "out": "chr_archer_attack_back.png",
            },
            "side": {
                "poses": ["archer_side_pose_aim.png"],
                "sequence": [0, 1, 1, 1, 1, 1, 1, 1, 0],
                "out": "chr_archer_attack_side.png",
            },
        },
        "enemy": {
            "back": {
                "poses": ["enemy_back_pose_slash.png"],
                "sequence": [0, 0, 1, 1, 1, 1, 1, 0, 0],
                "out": "chr_enemy_attack_back.png",
            },
        },
    }

    for unit, facings in specs.items():
        unit_bases = bases.get(unit, {})
        for facing, spec in facings.items():
            base = unit_bases.get(facing) or unit_bases.get("front")
            if base is None:
                continue
            bank = [base]
            for pose_name in spec["poses"]:
                bank.append(_fit_pose(pose_name, unit, base))
            frames = [bank[i] for i in spec["sequence"]]
            sheet = Image.new("RGBA", (FRAME * len(frames), FRAME), (0, 0, 0, 0))
            for i, fr in enumerate(frames):
                sheet.alpha_composite(fr, (i * FRAME, 0))
            out_path = CHARS / unit / spec["out"]
            save(sheet, out_path)


def rebuild_sheets(bases: dict[str, dict[str, Image.Image]]) -> None:
    for unit, unit_bases in bases.items():
        unit_dir = CHARS / unit
        front = unit_bases["front"]
        back = unit_bases.get("back", front)
        side = unit_bases.get("side", front)

        # Never rewrite front idle / run_downward — keep original front scale.
        save(make_walk(back, True), unit_dir / f"chr_{unit}_run_upward.png")
        save(make_walk(back, True), unit_dir / f"chr_{unit}_run_backward.png")
        save(make_walk(side, False), unit_dir / f"chr_{unit}_run_side.png")

        if unit in WORKERS:
            tool = "hoe" if unit == "villager" else "axe"
            # Front/back/side work prefer AI pose sheets when available.
            # Skip rewriting afk_back — tools/build_back_work_sheets.py owns it.
            # Skip rewriting afk_side when side poses exist — tools/build_side_work_sheets.py.
            side_pose = Path(r"C:\Repos\gameX\tools\ai_poses") / f"{unit}_side_pose_raise.png"
            if side_pose.exists():
                print(f"skip procedural afk_side for {unit} (AI side poses present)")
            else:
                save(
                    make_work(side, facing_side=True, tool=tool, unit=unit),
                    unit_dir / f"chr_{unit}_afk_side.png",
                )

        # Side attack fallback for enemy (mirror-friendly side idle lunge via walk bob)
        if unit == "enemy":
            save(make_attack(side, False, melee_kind="claw", unit=unit), unit_dir / "chr_enemy_attack_side.png")

        # Death/deploy back: prefer back idle strip when missing
        deploy_back = unit_dir / f"chr_{unit}_deploy_back.png"
        if unit in COMBAT:
            save(make_idle_sheet(back, frames=3), deploy_back)


def main() -> None:
    bases = import_bases()
    rebuild_sheets(bases)
    build_directional_attacks(bases)
    print("Directional bases imported and sheets rebuilt.")


if __name__ == "__main__":
    main()
