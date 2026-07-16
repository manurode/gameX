"""
Generate walk / attack / work sprite strips from idle base frames.

- Preserves true alpha (no opaque black boxes)
- Walk = upright stride bob + leg split (no drunken whole-body sway)
- Attack = short lunge + light lean + slash cue
- Work = tool swing + impact bob
"""

from __future__ import annotations

import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(r"C:\Repos\gameX\assets\tilesets\mediterranean\Characters")
REFS = Path(r"C:\Repos\gameX\tools\anim_refs")
FRAME = 80


def load_base(name: str) -> Image.Image:
    return Image.open(REFS / f"{name}_base.png").convert("RGBA")


def to_sprite(img: Image.Image, threshold: int = 14) -> Image.Image:
    """Keep painted pixels; force near-black background to transparent."""
    arr = np.array(img).copy()
    # Prefer existing alpha if the source already has transparency
    if arr[:, :, 3].min() < 250:
        # Soft-clean near-black fully transparent pixels
        near_black = (arr[:, :, :3].max(axis=2) <= threshold) & (arr[:, :, 3] < 250)
        arr[near_black, 3] = 0
        return Image.fromarray(arr, "RGBA")

    mask = arr[:, :, :3].max(axis=2) > threshold
    arr[~mask, 3] = 0
    arr[mask, 3] = 255
    return Image.fromarray(arr, "RGBA")


def transparent_canvas() -> Image.Image:
    return Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))


def place_sprite(
    sprite: Image.Image,
    *,
    angle: float = 0.0,
    dx: float = 0.0,
    dy: float = 0.0,
    scale: float = 1.0,
    squash_y: float = 1.0,
) -> Image.Image:
    src = sprite
    bbox = src.getbbox()
    if bbox is None:
        return transparent_canvas()

    char = src.crop(bbox)
    if abs(scale - 1.0) > 0.001 or abs(squash_y - 1.0) > 0.001:
        nw = max(1, int(char.width * scale))
        nh = max(1, int(char.height * scale * squash_y))
        char = char.resize((nw, nh), Image.Resampling.BILINEAR)

    if abs(angle) > 0.05:
        # Expand so rotation doesn't clip, then we'll re-ground feet
        char = char.rotate(angle, resample=Image.Resampling.BILINEAR, expand=True, fillcolor=(0, 0, 0, 0))

    canvas = transparent_canvas()
    ground_y = 78
    px = int(round((FRAME - char.width) / 2 + dx))
    py = int(round(ground_y - char.height + dy))
    px = max(-20, min(FRAME - char.width + 20, px))
    py = max(-20, min(FRAME - char.height + 20, py))
    canvas.alpha_composite(char, dest=(px, py))
    return canvas


def split_legs(sprite: Image.Image, stride: float, lift: float = 0.0) -> Image.Image:
    """
    Move left/right halves of the lower body in opposite directions and lift
    the trailing foot so the cycle reads as a step, not a sway.
    stride > 0 => viewer's-right foot forward.
    """
    arr = np.array(sprite)
    alpha = arr[:, :, 3] > 8
    ys, xs = np.where(alpha)
    if len(xs) == 0:
        return sprite

    y0, y1 = int(ys.min()), int(ys.max())
    x0, x1 = int(xs.min()), int(xs.max())
    mid_x = (x0 + x1) * 0.5
    hip_y = y0 + int((y1 - y0) * 0.52)

    out = np.zeros_like(arr)
    out[:hip_y] = arr[:hip_y]

    height = max(y1 - hip_y, 1)
    for y in range(hip_y, FRAME):
        t = (y - hip_y) / height
        strength = t * t
        for x in range(FRAME):
            if arr[y, x, 3] < 8:
                continue
            right = x >= mid_x
            # Trailing foot lifts; planting foot stays down
            if right:
                foot_lift = -lift * strength if stride < 0 else 0.0
                sx = int(round(x + stride * strength))
            else:
                foot_lift = -lift * strength if stride > 0 else 0.0
                sx = int(round(x - stride * strength))
            sy = int(round(y + foot_lift))
            if 0 <= sx < FRAME and 0 <= sy < FRAME and arr[y, x, 3] >= out[sy, sx, 3]:
                out[sy, sx] = arr[y, x]

    return Image.fromarray(out, "RGBA")


def swing_arm_band(sprite: Image.Image, amount: float, right_side: bool) -> Image.Image:
    """Nudge one side of the torso horizontally to suggest arm swing."""
    arr = np.array(sprite)
    alpha = arr[:, :, 3] > 8
    ys, xs = np.where(alpha)
    if len(xs) == 0:
        return sprite
    y0, y1 = int(ys.min()), int(ys.max())
    x0, x1 = int(xs.min()), int(xs.max())
    mid_x = (x0 + x1) * 0.5
    shoulder = y0 + int((y1 - y0) * 0.34)
    waist = y0 + int((y1 - y0) * 0.58)

    out = arr.copy()
    # clear arm band on chosen side
    for y in range(shoulder, waist + 1):
        for x in range(FRAME):
            if arr[y, x, 3] < 8:
                continue
            on_side = x >= mid_x - 1 if right_side else x <= mid_x + 1
            if on_side:
                out[y, x] = 0

    for y in range(shoulder, waist + 1):
        t = (y - shoulder) / max(waist - shoulder, 1)
        dx = amount * (0.35 + 0.65 * t)
        for x in range(FRAME):
            if arr[y, x, 3] < 8:
                continue
            on_side = x >= mid_x - 1 if right_side else x <= mid_x + 1
            if not on_side:
                continue
            sx = int(round(x + dx))
            if 0 <= sx < FRAME and arr[y, x, 3] >= out[y, sx, 3]:
                out[y, sx] = arr[y, x]

    return Image.fromarray(out, "RGBA")


def draw_melee_slash(frame: Image.Image, progress: float, facing_back: bool) -> Image.Image:
    if progress < 0.35 or progress > 0.72:
        return frame
    overlay = transparent_canvas()
    draw = ImageDraw.Draw(overlay)
    cx = 30 if facing_back else 50
    cy = 44
    t = (progress - 0.35) / 0.37
    start = -95 + t * 120
    end = start + 50
    bbox = [cx - 26, cy - 26, cx + 26, cy + 26]
    alpha = int(180 * (1.0 - abs(t - 0.5) * 2))
    color = (245, 245, 255, max(0, alpha))
    if facing_back:
        draw.arc(bbox, start=180 - end, end=180 - start, fill=color, width=2)
    else:
        draw.arc(bbox, start=start, end=end, fill=color, width=2)
    return Image.alpha_composite(frame, overlay)


def draw_work_tool(frame: Image.Image, angle_deg: float, facing_back: bool, tool: str = "axe") -> Image.Image:
    overlay = transparent_canvas()
    draw = ImageDraw.Draw(overlay)
    px = 34 if facing_back else 46
    py = 40
    length = 17
    rad = math.radians(angle_deg)
    ex = px + math.cos(rad) * length
    ey = py + math.sin(rad) * length
    handle = (118, 76, 40, 255)
    head = (168, 168, 178, 255) if tool == "axe" else (150, 110, 60, 255)
    draw.line([(px, py), (ex, ey)], fill=handle, width=2)
    hx = ex + math.cos(rad) * 2
    hy = ey + math.sin(rad) * 2
    perp = rad + math.pi / 2
    if tool == "axe":
        p1 = (hx + math.cos(perp) * 5, hy + math.sin(perp) * 5)
        p2 = (hx - math.cos(perp) * 2, hy - math.sin(perp) * 2)
        p3 = (hx + math.cos(rad) * 4, hy + math.sin(rad) * 4)
        draw.polygon([p1, p2, p3], fill=head)
    else:
        p1 = (hx + math.cos(perp) * 6, hy + math.sin(perp) * 6)
        p2 = (hx - math.cos(perp) * 6, hy - math.sin(perp) * 6)
        draw.line([p1, p2], fill=head, width=3)
    return Image.alpha_composite(frame, overlay)


def stitch(frames: list[Image.Image]) -> Image.Image:
    sheet = transparent_canvas().resize((FRAME * len(frames), FRAME))
    sheet = Image.new("RGBA", (FRAME * len(frames), FRAME), (0, 0, 0, 0))
    for i, fr in enumerate(frames):
        sheet.alpha_composite(fr, dest=(i * FRAME, 0))
    return sheet


def make_walk(base: Image.Image, facing_back: bool = False) -> Image.Image:
    sprite = to_sprite(base)
    frames = []
    for i in range(8):
        t = i / 8.0 * math.tau
        # Contact -> passing -> contact; lift peaks at mid-stride
        stride = math.sin(t) * 5.0
        lift = abs(math.sin(t)) * 3.0
        posed = split_legs(sprite, stride, lift=lift)
        arm = math.sin(t + math.pi) * 2.5
        posed = swing_arm_band(posed, arm, right_side=not facing_back)
        # Upright bob only (never rotate the whole body while walking)
        bob = -abs(math.sin(t)) * 2.0
        squash = 1.0 - abs(math.sin(t)) * 0.03
        frames.append(
            place_sprite(
                posed,
                angle=0.0,
                dx=0.0,
                dy=bob,
                squash_y=squash,
            )
        )
    return stitch(frames)


def make_attack(base: Image.Image, facing_back: bool = False, ranged: bool = False) -> Image.Image:
    sprite = to_sprite(base)
    frames = []
    sign = -1.0 if facing_back else 1.0
    for i in range(9):
        p = i / 8.0
        if ranged:
            if i <= 6:
                pull = i / 6.0
                angle = -5 * pull * sign
                dx = -3.5 * pull * sign
                dy = -1.5 * pull
                scale = 1.0 - pull * 0.02
            else:
                release = (i - 6) / 2.0
                angle = (-5 + release * 8) * sign
                dx = (-3.5 + release * 5) * sign
                dy = -1.5 + release * 1.5
                scale = 0.98 + release * 0.03
            fr = place_sprite(sprite, angle=angle, dx=dx, dy=dy, scale=scale)
        else:
            if i <= 3:
                wind = i / 3.0
                angle = -8 * wind * sign
                dx = -3.5 * wind * sign
                dy = -1.5 * wind
                scale = 1.0
            elif i <= 5:
                strike = (i - 3) / 2.0
                angle = (-8 + strike * 18) * sign
                dx = (-3.5 + strike * 9) * sign
                dy = -1.5 + strike * 3
                scale = 1.0 + strike * 0.03
            else:
                rec = (i - 5) / 3.0
                angle = (10 * (1.0 - rec)) * sign
                dx = (5.5 * (1.0 - rec)) * sign
                dy = 1.2 * (1.0 - rec)
                scale = 1.03 - rec * 0.03
            fr = place_sprite(sprite, angle=angle, dx=dx, dy=dy, scale=scale)
            fr = draw_melee_slash(fr, p, facing_back)
        frames.append(fr)
    return stitch(frames)


def make_work(base: Image.Image, facing_back: bool = False, tool: str = "axe") -> Image.Image:
    sprite = to_sprite(base)
    frames = []
    sign = -1.0 if facing_back else 1.0
    for i in range(6):
        t = i / 6.0 * math.tau
        # Impact bob, tiny lean only
        body_angle = math.sin(t) * 4.0 * sign
        dy = (1.0 - math.cos(t)) * 3.0
        fr = place_sprite(
            sprite,
            angle=body_angle,
            dy=dy,
            squash_y=1.0 - (1.0 - math.cos(t)) * 0.04,
            dx=math.sin(t) * 1.2 * sign,
        )
        tool_angle = 25 + (0.5 - 0.5 * math.cos(t)) * 95
        fr = draw_work_tool(fr, tool_angle, facing_back, tool=tool)
        frames.append(fr)
    return stitch(frames)


def save(sheet: Image.Image, path: Path) -> None:
    arr = np.array(sheet.convert("RGBA"))
    # Only clear empty leftovers: pure black with no meaningful color (bg mistakes)
    # Keep dark character outlines (they usually have alpha and slight color)
    empty = (arr[:, :, 0] <= 1) & (arr[:, :, 1] <= 1) & (arr[:, :, 2] <= 1) & (arr[:, :, 3] > 0)
    # Don't wipe if surrounded by character color — simple: wipe only fully black cells
    arr[empty, 3] = 0
    Image.fromarray(arr, "RGBA").save(path)
    opaque_black = ((arr[:, :, 0] < 5) & (arr[:, :, 1] < 5) & (arr[:, :, 2] < 5) & (arr[:, :, 3] > 200)).sum()
    transparent = (arr[:, :, 3] < 10).sum()
    print(
        f"wrote {path.name:32s} {sheet.size[0]}x{sheet.size[1]}  "
        f"opaque_black={opaque_black} transparent={transparent}"
    )


def process_unit(unit: str, *, has_attack: bool, has_work: bool, ranged: bool = False, tool: str = "axe") -> None:
    front = load_base(unit)
    back_path = REFS / f"{unit}_back_base.png"
    back = load_base(f"{unit}_back") if back_path.exists() else front
    unit_dir = ROOT / unit

    save(make_walk(front, False), unit_dir / f"chr_{unit}_run_downward.png")
    save(make_walk(back, True), unit_dir / f"chr_{unit}_run_upward.png")
    save(make_walk(back, True), unit_dir / f"chr_{unit}_run_backward.png")

    if has_attack:
        save(make_attack(front, False, ranged=ranged), unit_dir / f"chr_{unit}_attack.png")
        save(make_attack(back, True, ranged=ranged), unit_dir / f"chr_{unit}_attack_back.png")

    if has_work:
        save(make_work(front, False, tool=tool), unit_dir / f"chr_{unit}_afk.png")


def main() -> None:
    # Refresh refs from ORIGINAL idle frames (transparent)
    for unit in ("villager", "builder", "knight", "archer", "enemy"):
        src = ROOT / unit / f"chr_{unit}_idle.png"
        if src.exists():
            im = Image.open(src).convert("RGBA")
            # Use first frame; ensure transparency
            frame = to_sprite(im.crop((0, 0, 80, 80)))
            REFS.mkdir(parents=True, exist_ok=True)
            frame.save(REFS / f"{unit}_base.png")
        back = ROOT / unit / f"chr_{unit}_idle_back.png"
        if back.exists():
            im = Image.open(back).convert("RGBA")
            frame = to_sprite(im.crop((0, 0, 80, 80)))
            frame.save(REFS / f"{unit}_back_base.png")

    process_unit("villager", has_attack=True, has_work=True, tool="hoe")
    process_unit("builder", has_attack=True, has_work=True, tool="axe")
    process_unit("knight", has_attack=True, has_work=False)
    process_unit("archer", has_attack=True, has_work=False, ranged=True)
    process_unit("enemy", has_attack=True, has_work=False)
    print("Done.")


if __name__ == "__main__":
    main()
