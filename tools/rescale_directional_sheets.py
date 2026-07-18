"""Upscale directional sheets so character silhouette height matches front idle."""

from __future__ import annotations

from pathlib import Path

from PIL import Image

from normalize_anim_sheets import content_bbox, harden_alpha

FRAME = 80
CHARS = Path(r"C:\Repos\gameX\assets\tilesets\mediterranean\Characters")
UNITS = ("villager", "builder", "knight", "archer", "enemy")
# Match idle hat→feet height exactly (1.0). Slight boost if still reading small in-game.
TARGET_RATIO = 1.0

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


def silhouette_h(im: Image.Image) -> int:
    bb = im.getbbox()
    if bb is None:
        return 0
    return max(1, bb[3] - bb[1] + 1)


def idle_metrics(unit: str) -> tuple[int, int]:
    idle = Image.open(CHARS / unit / f"chr_{unit}_idle.png").convert("RGBA")
    frame = harden_alpha(idle.crop((0, 0, FRAME, FRAME)), cut=30)
    bb = content_bbox(frame)
    return max(1, bb[3] - bb[1] + 1), bb[3]


def rescale_frame(frame: Image.Image, ref_h: int, foot_y: int) -> Image.Image:
    frame = harden_alpha(frame.convert("RGBA"), cut=30)
    bb = frame.getbbox()
    canvas = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    if bb is None:
        return canvas
    cropped = frame.crop(bb)
    pose_h = max(1, cropped.height)
    scale = (ref_h * TARGET_RATIO) / pose_h
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


def rescale_sheet(path: Path, ref_h: int, foot_y: int) -> None:
    im = Image.open(path).convert("RGBA")
    count = max(1, im.width // FRAME)
    out = Image.new("RGBA", (FRAME * count, FRAME), (0, 0, 0, 0))
    for i in range(count):
        fr = im.crop((i * FRAME, 0, (i + 1) * FRAME, FRAME))
        out.alpha_composite(rescale_frame(fr, ref_h, foot_y), (i * FRAME, 0))
    out.save(path)
    h0 = silhouette_h(out.crop((0, 0, FRAME, FRAME)))
    print(f"  {path.name:32s} h={h0} (target {ref_h})")


def main() -> None:
    for unit in UNITS:
        ref_h, foot_y = idle_metrics(unit)
        print(f"{unit}: idle h={ref_h} foot_y={foot_y}")
        for pattern in SHEET_GLOBS:
            path = CHARS / unit / pattern.format(u=unit)
            if path.exists():
                rescale_sheet(path, ref_h, foot_y)
    print("Done rescaling directional sheets.")


if __name__ == "__main__":
    main()
