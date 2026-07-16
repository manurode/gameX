"""
Normalize attack/work sprite sheets so character body size matches idle.

AI pose art is chunkier than the idle sheets, so we:
1) Match body mass height (feet → dense torso/head)
2) Apply a style shrink so heads/torsos don't look bigger than idle
3) Bottom-align to the idle foot line and harden alpha
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image

FRAME = 80
# AI poses read ~15-20% larger than native idle art at the same bbox height
STYLE_SHRINK = 0.85
CHARS = Path(r"C:\Repos\gameX\assets\tilesets\mediterranean\Characters")
POSE_DIR = Path(r"C:\Repos\gameX\tools\ai_poses")
PREVIEWS = Path(r"C:\Repos\gameX\tools\anim_preview\frames")


def harden_alpha(im: Image.Image, cut: int = 48) -> Image.Image:
    arr = np.array(im.convert("RGBA"))
    arr[arr[:, :, 3] < cut, 3] = 0
    arr[arr[:, :, 3] >= cut, 3] = 255
    return Image.fromarray(arr, "RGBA")


def to_alpha(im: Image.Image, threshold: int = 20) -> Image.Image:
    arr = np.array(im.convert("RGBA"))
    if arr[:, :, 3].min() < 240 and (arr[:, :, 3] < 20).mean() > 0.2:
        return harden_alpha(Image.fromarray(arr, "RGBA"), cut=40)

    lum = arr[:, :, :3].max(axis=2)
    alpha = np.zeros_like(lum, dtype=np.uint8)
    alpha[lum > threshold] = 255
    arr[:, :, 3] = alpha
    return Image.fromarray(arr, "RGBA")


def idle_frame(unit: str) -> Image.Image:
    path = CHARS / unit / f"chr_{unit}_idle.png"
    im = Image.open(path).convert("RGBA")
    return harden_alpha(im.crop((0, 0, FRAME, FRAME)), cut=30)


def content_bbox(im: Image.Image) -> tuple[int, int, int, int]:
    bb = im.getbbox()
    if bb is None:
        return 0, 0, 1, 1
    return bb


def body_height(im: Image.Image, mass_frac: float = 0.90) -> int:
    """Standing body height from feet, ignoring sparse raised-weapon pixels."""
    arr = np.array(im.convert("RGBA"))
    solid = arr[:, :, 3] >= 120
    row_mass = solid.sum(axis=1).astype(np.float64)
    total = float(row_mass.sum())
    if total < 1:
        return 1
    rows = np.where(row_mass > 0)[0]
    foot = int(rows[-1])
    acc = 0.0
    top = int(rows[0])
    for y in range(foot, -1, -1):
        acc += row_mass[y]
        if acc >= total * mass_frac:
            top = y
            break
    return max(foot - top + 1, 1)


def fit_to_idle(im: Image.Image, ref_body_h: int, foot_y: int) -> Image.Image:
    im = to_alpha(im)
    bb = im.getbbox()
    canvas = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    if bb is None:
        return canvas

    cropped = im.crop(bb)
    pose_h = body_height(cropped)
    scale = (ref_body_h * STYLE_SHRINK) / max(pose_h, 1)

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
    return harden_alpha(canvas, cut=48)


def stitch(frames: list[Image.Image], path: Path) -> None:
    sheet = Image.new("RGBA", (FRAME * len(frames), FRAME), (0, 0, 0, 0))
    for i, fr in enumerate(frames):
        sheet.alpha_composite(fr, (i * FRAME, 0))
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(path)
    print(f"wrote {path} {sheet.size}")

    PREVIEWS.mkdir(parents=True, exist_ok=True)
    idxs = [0, len(frames) // 3, (2 * len(frames)) // 3, len(frames) - 1]
    prev = Image.new("RGBA", (len(idxs) * 240, 240), (40, 40, 40, 255))
    for n, i in enumerate(idxs):
        fr = frames[i].resize((240, 240), Image.Resampling.NEAREST)
        prev.paste(fr, (n * 240, 0), fr)
    prev.save(PREVIEWS / f"norm_{path.stem}.png")


def load_pose(name: str, ref_h: int, foot_y: int) -> Image.Image:
    return fit_to_idle(Image.open(POSE_DIR / name), ref_h, foot_y)


def build_unit_attack(unit: str, pose_names: list[str], sequence: list[int]) -> None:
    idle = idle_frame(unit)
    foot_y = content_bbox(idle)[3]
    ref_h = body_height(idle)
    print(f"{unit}: body_h={ref_h} foot_y={foot_y}")

    poses = [load_pose(n, ref_h, foot_y) for n in pose_names]
    bank = [idle, *poses]
    frames = [bank[i] for i in sequence]
    stitch(frames, CHARS / unit / f"chr_{unit}_attack.png")
    stitch(frames, CHARS / unit / f"chr_{unit}_attack_back.png")


def build_knight() -> None:
    build_unit_attack(
        "knight",
        ["knight_pose_windup.png", "knight_pose_slash.png", "knight_pose_follow.png"],
        [0, 1, 1, 1, 2, 2, 3, 3, 0],
    )


def build_archer() -> None:
    build_unit_attack(
        "archer",
        ["archer_pose_draw.png", "archer_pose_aim.png", "archer_pose_release.png"],
        [0, 1, 1, 2, 2, 2, 3, 3, 0],
    )


def build_builder_work() -> None:
    idle = idle_frame("builder")
    foot_y = content_bbox(idle)[3]
    ref_h = body_height(idle)
    print(f"builder: body_h={ref_h} foot_y={foot_y}")
    raise_p = load_pose("builder_pose_raise.png", ref_h, foot_y)
    strike = load_pose("builder_pose_strike.png", ref_h, foot_y)
    frames = [idle, raise_p, raise_p, raise_p, strike, strike, strike, raise_p, idle]
    stitch(frames, CHARS / "builder" / "chr_builder_afk.png")


def build_enemy() -> None:
    build_unit_attack(
        "enemy",
        ["enemy_pose_windup.png", "enemy_pose_slash.png", "enemy_pose_follow.png"],
        [0, 1, 1, 1, 2, 2, 3, 3, 0],
    )


def build_villager_work() -> None:
    idle = idle_frame("villager")
    foot_y = content_bbox(idle)[3]
    ref_h = body_height(idle)
    print(f"villager: body_h={ref_h} foot_y={foot_y}")
    raise_p = load_pose("villager_pose_raise.png", ref_h, foot_y)
    strike = load_pose("villager_pose_strike.png", ref_h, foot_y)
    frames = [idle, raise_p, raise_p, raise_p, strike, strike, strike, raise_p, idle]
    stitch(frames, CHARS / "villager" / "chr_villager_afk.png")


def main() -> None:
    build_knight()
    build_archer()
    if (POSE_DIR / "builder_pose_raise.png").exists():
        build_builder_work()
    if (POSE_DIR / "enemy_pose_windup.png").exists():
        build_enemy()
    if (POSE_DIR / "villager_pose_raise.png").exists():
        build_villager_work()
    print("Done normalizing attack/work sheets.")


if __name__ == "__main__":
    main()
