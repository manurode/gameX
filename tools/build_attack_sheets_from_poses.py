"""Build 80x80 attack sheets from individual AI pose frames + idle base."""

from __future__ import annotations

import shutil
from pathlib import Path

import numpy as np
from PIL import Image

FRAME = 80
CURSOR = Path(r"C:\Users\Manu\.cursor\projects\c-Repos-gameX\assets")
POSE_DIR = Path(r"C:\Repos\gameX\tools\ai_poses")
REFS = Path(r"C:\Repos\gameX\tools\anim_refs")
CHARS = Path(r"C:\Repos\gameX\assets\tilesets\mediterranean\Characters")
PREVIEWS = Path(r"C:\Repos\gameX\tools\anim_preview\frames")


def collect_poses() -> None:
    POSE_DIR.mkdir(parents=True, exist_ok=True)
    names = [
        "knight_pose_windup.png",
        "knight_pose_slash.png",
        "knight_pose_follow.png",
        "archer_pose_draw.png",
        "archer_pose_aim.png",
        "archer_pose_release.png",
        "builder_pose_raise.png",
        "builder_pose_strike.png",
    ]
    for name in names:
        src = CURSOR / name
        if src.exists():
            shutil.copy2(src, POSE_DIR / name)
            print("copied", name)
        else:
            print("MISSING", name)


def to_alpha(im: Image.Image, threshold: int = 20) -> Image.Image:
    arr = np.array(im.convert("RGBA"))
    lum = arr[:, :, :3].max(axis=2)
    alpha = np.zeros_like(lum, dtype=np.uint8)
    alpha[lum > threshold + 18] = 255
    mid = (lum > threshold) & (lum <= threshold + 18)
    alpha[mid] = ((lum[mid] - threshold) * (255 / 18)).astype(np.uint8)
    arr[:, :, 3] = alpha
    return Image.fromarray(arr, "RGBA")


def fit80(im: Image.Image) -> Image.Image:
    im = to_alpha(im)
    bbox = im.getbbox()
    canvas = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    if bbox is None:
        return canvas
    cropped = im.crop(bbox)
    scale = min(68 / cropped.width, 70 / cropped.height, 1.4)
    nw = max(1, int(cropped.width * scale))
    nh = max(1, int(cropped.height * scale))
    cropped = cropped.resize((nw, nh), Image.Resampling.LANCZOS)
    px = (FRAME - nw) // 2
    py = FRAME - nh - 3
    canvas.alpha_composite(cropped, (max(0, px), max(0, py)))
    return canvas


def stitch(frames: list[Image.Image], path: Path) -> None:
    sheet = Image.new("RGBA", (FRAME * len(frames), FRAME), (0, 0, 0, 0))
    for i, fr in enumerate(frames):
        sheet.alpha_composite(fr, (i * FRAME, 0))
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(path)
    print("wrote", path, sheet.size)

    # preview
    PREVIEWS.mkdir(parents=True, exist_ok=True)
    idxs = [0, len(frames) // 3, (2 * len(frames)) // 3, len(frames) - 1]
    prev = Image.new("RGBA", (len(idxs) * 240, 240), (0, 0, 0, 0))
    for n, i in enumerate(idxs):
        fr = frames[i].resize((240, 240), Image.Resampling.NEAREST)
        bg = Image.new("RGBA", fr.size)
        for y in range(0, 240, 12):
            for x in range(0, 240, 12):
                c = (70, 130, 70, 255) if ((x // 12) + (y // 12)) % 2 == 0 else (55, 110, 55, 255)
                for yy in range(y, min(y + 12, 240)):
                    for xx in range(x, min(x + 12, 240)):
                        bg.putpixel((xx, yy), c)
        prev.paste(Image.alpha_composite(bg, fr), (n * 240, 0))
    prev.save(PREVIEWS / f"poses_{path.stem}.png")


def load_pose(name: str) -> Image.Image:
    return fit80(Image.open(POSE_DIR / name))


def load_idle(unit: str) -> Image.Image:
    # Prefer original idle first frame
    idle_path = CHARS / unit / f"chr_{unit}_idle.png"
    im = Image.open(idle_path).convert("RGBA")
    return fit80(im.crop((0, 0, 80, 80))) if im.size[0] >= 80 else fit80(im)


def build_knight() -> None:
    idle = load_idle("knight")
    windup = load_pose("knight_pose_windup.png")
    slash = load_pose("knight_pose_slash.png")
    follow = load_pose("knight_pose_follow.png")
    # 9 frames, melee hit on frame 5
    frames = [
        idle,    # 0
        windup,  # 1
        windup,  # 2
        windup,  # 3 peak raise
        slash,   # 4 swing
        slash,   # 5 HIT
        follow,  # 6
        follow,  # 7
        idle,    # 8
    ]
    stitch(frames, CHARS / "knight" / "chr_knight_attack.png")
    stitch(frames, CHARS / "knight" / "chr_knight_attack_back.png")


def build_archer() -> None:
    idle = load_idle("archer")
    draw = load_pose("archer_pose_draw.png")
    aim = load_pose("archer_pose_aim.png")
    release = load_pose("archer_pose_release.png")
    # 9 frames, ranged hit on frame 6
    frames = [
        idle,     # 0
        draw,     # 1
        draw,     # 2
        aim,      # 3
        aim,      # 4
        aim,      # 5
        release,  # 6 HIT / arrow spawn
        release,  # 7
        idle,     # 8
    ]
    stitch(frames, CHARS / "archer" / "chr_archer_attack.png")
    stitch(frames, CHARS / "archer" / "chr_archer_attack_back.png")


def build_builder_work() -> None:
    idle = load_idle("builder")
    raise_p = load_pose("builder_pose_raise.png")
    strike = load_pose("builder_pose_strike.png")
    # 6-frame gather/work loop
    frames = [
        idle,     # 0
        raise_p,  # 1
        raise_p,  # 2
        strike,   # 3 impact
        strike,   # 4
        idle,     # 5
    ]
    stitch(frames, CHARS / "builder" / "chr_builder_afk.png")


def main() -> None:
    collect_poses()
    build_knight()
    build_archer()
    if (POSE_DIR / "builder_pose_raise.png").exists():
        build_builder_work()
    print("Done.")


if __name__ == "__main__":
    main()
