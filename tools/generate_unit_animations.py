"""
Generate walk / attack / work sprite strips from idle base frames.

- Preserves true alpha (no opaque black boxes)
- Walk = upright stride bob + leg split (no drunken whole-body sway)
- Attack / work = upright body; weapon arm rotates around the shoulder
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


def character_bounds(sprite: Image.Image) -> tuple[int, int, int, int, float, float]:
    arr = np.array(sprite)
    alpha = arr[:, :, 3] > 8
    ys, xs = np.where(alpha)
    if len(xs) == 0:
        return 0, 0, FRAME - 1, FRAME - 1, FRAME * 0.5, FRAME * 0.4
    y0, y1 = int(ys.min()), int(ys.max())
    x0, x1 = int(xs.min()), int(xs.max())
    mid_x = (x0 + x1) * 0.5
    shoulder_y = y0 + (y1 - y0) * 0.38
    return x0, y0, x1, y1, mid_x, shoulder_y


def swing_arm_band(sprite: Image.Image, amount: float, right_side: bool) -> Image.Image:
    """Nudge one side of the torso horizontally to suggest arm swing (walk)."""
    arr = np.array(sprite)
    x0, y0, x1, y1, mid_x, _shoulder = character_bounds(sprite)
    shoulder = y0 + int((y1 - y0) * 0.34)
    waist = y0 + int((y1 - y0) * 0.58)

    out = arr.copy()
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


def move_weapon_arm(
    sprite: Image.Image,
    *,
    right_side: bool,
    dx: float,
    dy: float,
    stretch_down: float = 0.0,
) -> Image.Image:
    """
    Move the outer weapon/forearm only (painted pixels), like walk does for legs.
    Includes blades/handles that hang below the hip so the sword doesn't double.
    """
    if abs(dx) < 0.1 and abs(dy) < 0.1 and abs(stretch_down) < 0.1:
        return sprite

    arr = np.array(sprite)
    x0, y0, x1, y1, mid_x, shoulder_y = character_bounds(sprite)
    height = max(y1 - y0, 1)
    width = max(x1 - x0, 1)
    hip_y = y0 + int(height * 0.62)
    y_top = max(y0, int(shoulder_y - height * 0.08))
    y_bot = min(FRAME - 1, y1)

    # Outer fringe on the weapon side (keeps shield/torso core still)
    if right_side:
        fringe = mid_x + width * 0.10
    else:
        fringe = mid_x - width * 0.10

    def is_weapon_pixel(x: int, y: int) -> bool:
        if arr[y, x, 3] < 8:
            return False
        # Never touch the head
        if y < shoulder_y and abs(x - mid_x) < width * 0.22:
            return False
        on_side = x >= fringe if right_side else x <= fringe
        if not on_side:
            return False
        r, g, b = int(arr[y, x, 0]), int(arr[y, x, 1]), int(arr[y, x, 2])
        is_metal = abs(r - g) < 40 and abs(g - b) < 40 and 50 <= r <= 230
        is_wood = r > g + 10 and g >= b - 5 and 45 < r < 200
        # Forearm band: all outer pixels between shoulder and hip
        if y_top <= y <= hip_y:
            return True
        # Below hip: only blade/handle colors (not armored legs / pants bulk)
        if y > hip_y and (is_metal or is_wood):
            # Prefer thin outer sticks (sword/bow) over wide leg plates
            edge = x1 if right_side else x0
            if abs(x - edge) <= width * 0.42:
                return True
        return False

    # Collect then clear — avoids duplicates
    moves: list[tuple[int, int, np.ndarray, float, float]] = []
    for y in range(y_top, y_bot + 1):
        t = (y - y_top) / max(y_bot - y_top, 1)
        strength = 0.35 + 0.65 * t
        local_dx = dx * strength
        local_dy = dy * strength + stretch_down * t
        for x in range(FRAME):
            if is_weapon_pixel(x, y):
                moves.append((x, y, arr[y, x].copy(), local_dx, local_dy))

    out = arr.copy()
    for x, y, _pix, _ldx, _ldy in moves:
        out[y, x] = 0

    arm_layer = np.zeros_like(arr)
    for x, y, pix, local_dx, local_dy in moves:
        sx = int(round(x + local_dx))
        sy = int(round(y + local_dy))
        if 0 <= sx < FRAME and 0 <= sy < FRAME and pix[3] >= arm_layer[sy, sx, 3]:
            arm_layer[sy, sx] = pix

    body = Image.fromarray(out, "RGBA")
    arm = Image.fromarray(arm_layer, "RGBA")
    return Image.alpha_composite(body, arm)


def hand_point(sprite: Image.Image, right_side: bool) -> tuple[float, float]:
    """Approximate hand position on the weapon side (for attaching drawn tools)."""
    x0, y0, x1, y1, mid_x, shoulder_y = character_bounds(sprite)
    # Hand sits below shoulder on the outer side
    hx = mid_x + (12 if right_side else -12)
    hy = shoulder_y + (y1 - y0) * 0.28
    return hx, hy


def draw_attached_tool(
    frame: Image.Image,
    *,
    pivot: tuple[float, float],
    angle_deg: float,
    tool: str,
) -> Image.Image:
    """Draw axe/hoe attached to the hand, rotating with the arm swing."""
    overlay = transparent_canvas()
    draw = ImageDraw.Draw(overlay)
    px, py = pivot
    length = 16 if tool == "axe" else 18
    rad = math.radians(angle_deg)
    ex = px + math.cos(rad) * length
    ey = py + math.sin(rad) * length
    handle = (125, 82, 45, 255)
    draw.line([(px, py), (ex, ey)], fill=handle, width=2)
    # grip knuckle
    draw.ellipse([px - 1.5, py - 1.5, px + 1.5, py + 1.5], fill=(210, 170, 130, 255))
    hx = ex + math.cos(rad) * 2
    hy = ey + math.sin(rad) * 2
    perp = rad + math.pi / 2
    if tool == "axe":
        head = (175, 175, 185, 255)
        p1 = (hx + math.cos(perp) * 5, hy + math.sin(perp) * 5)
        p2 = (hx - math.cos(perp) * 2, hy - math.sin(perp) * 2)
        p3 = (hx + math.cos(rad) * 5, hy + math.sin(rad) * 5)
        draw.polygon([p1, p2, p3], fill=head)
    else:
        head = (155, 115, 65, 255)
        p1 = (hx + math.cos(perp) * 6, hy + math.sin(perp) * 6)
        p2 = (hx - math.cos(perp) * 6, hy - math.sin(perp) * 6)
        draw.line([p1, p2], fill=head, width=3)
    return Image.alpha_composite(frame, overlay)


def draw_slash_trail(
    frame: Image.Image,
    *,
    pivot: tuple[float, float],
    angle_deg: float,
    length: float = 22.0,
) -> Image.Image:
    overlay = transparent_canvas()
    draw = ImageDraw.Draw(overlay)
    rad = math.radians(angle_deg)
    cx, cy = pivot
    # short arc centered on current swing angle
    bbox = [cx - length, cy - length, cx + length, cy + length]
    start = angle_deg - 28
    end = angle_deg + 8
    draw.arc(bbox, start=start, end=end, fill=(240, 240, 255, 150), width=2)
    return Image.alpha_composite(frame, overlay)


def draw_bow_draw(frame: Image.Image, pull: float, facing_back: bool) -> Image.Image:
    """pull 0..1 — string pulled back on the bow."""
    if pull <= 0.05:
        return frame
    overlay = transparent_canvas()
    draw = ImageDraw.Draw(overlay)
    x0, y0, x1, y1, mid_x, shoulder_y = character_bounds(frame)
    # Bow roughly on the outer side opposite the draw hand
    bow_x = mid_x + (10 if not facing_back else -10)
    bow_y0 = shoulder_y - 2
    bow_y1 = shoulder_y + 18
    string_x = bow_x - pull * (10 if not facing_back else -10)
    draw.line([(bow_x, bow_y0), (string_x, (bow_y0 + bow_y1) / 2), (bow_x, bow_y1)], fill=(90, 60, 35, 220), width=1)
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


def detect_weapon_side(sprite: Image.Image) -> bool:
    """
    Return True if the weapon/tool is on the viewer's-right half.

    Prefers thin metal/wood extremities that stick outward — not bulky shields.
    """
    arr = np.array(sprite)
    x0, y0, x1, y1, mid_x, shoulder_y = character_bounds(sprite)
    width = max(x1 - x0, 1)
    left_score = 0.0
    right_score = 0.0
    y_start = int(shoulder_y - (y1 - y0) * 0.05)
    for y in range(max(0, y_start), min(FRAME, y1 + 1)):
        for x in range(FRAME):
            if arr[y, x, 3] < 8:
                continue
            r, g, b = int(arr[y, x, 0]), int(arr[y, x, 1]), int(arr[y, x, 2])
            is_metal = abs(r - g) < 36 and abs(g - b) < 36 and 55 <= r <= 220
            is_wood = r > g + 12 and g >= b and 50 < r < 190
            if not (is_metal or is_wood):
                continue
            # Distance from center — weapons stick out further than shield face
            dist = abs(x - mid_x) / width
            weight = dist * dist
            if is_wood:
                weight *= 1.25
            if x < mid_x:
                left_score += weight
            else:
                right_score += weight
    if left_score < 0.5 and right_score < 0.5:
        # Fallback: left (sword/hammer side on most front sheets)
        return False
    return right_score > left_score


def suppress_static_weapon(sprite: Image.Image, right_side: bool) -> Image.Image:
    """Erase idle-painted sword/hammer pixels (alpha only — no torso fill holes)."""
    arr = np.array(sprite).copy()
    x0, y0, x1, y1, mid_x, shoulder_y = character_bounds(sprite)
    # Include raised hammers above the shoulder on the outer side only
    y_top = max(y0, int(shoulder_y - (y1 - y0) * 0.25))
    y_bot = min(FRAME - 1, int(shoulder_y + (y1 - y0) * 0.55))
    if right_side:
        x_a, x_b = int(mid_x + 3), x1 + 1
    else:
        x_a, x_b = x0, int(mid_x - 3)

    for y in range(y_top, y_bot + 1):
        for x in range(max(0, x_a), min(FRAME, x_b)):
            if arr[y, x, 3] < 8:
                continue
            # Never erase head core
            if y < shoulder_y and abs(x - mid_x) < (x1 - x0) * 0.16:
                continue
            r, g, b = int(arr[y, x, 0]), int(arr[y, x, 1]), int(arr[y, x, 2])
            is_metal = abs(r - g) < 36 and abs(g - b) < 36 and 55 <= r <= 220
            is_wood = r > g + 15 and g >= b and 50 < r < 180
            if is_metal or is_wood:
                arr[y, x, 3] = 0
    return Image.fromarray(arr, "RGBA")


def draw_swinging_weapon(
    frame: Image.Image,
    *,
    angle_deg: float,
    right_side: bool,
    kind: str,
    show_trail: bool = False,
) -> Image.Image:
    """Weapon arcs around a hand pivot glued to the shoulder; body stays intact."""
    hx, hy = hand_point(frame, right_side)
    # Pull pivot slightly toward shoulder so it reads as held, not floating
    _x0, _y0, _x1, _y1, mid_x, shoulder_y = character_bounds(frame)
    pivot_x = (hx + mid_x + (8 if right_side else -8)) * 0.5
    pivot_y = (hy + shoulder_y + 4) * 0.5
    overlay = transparent_canvas()
    draw = ImageDraw.Draw(overlay)
    rad = math.radians(angle_deg)
    length = 18 if kind == "sword" else 15
    ex = pivot_x + math.cos(rad) * length
    ey = pivot_y + math.sin(rad) * length
    perp = rad + math.pi / 2

    if kind == "sword":
        draw.line([(pivot_x, pivot_y), (ex, ey)], fill=(200, 205, 215, 255), width=2)
        tx = pivot_x + math.cos(rad) * (length + 3)
        ty = pivot_y + math.sin(rad) * (length + 3)
        draw.line([(ex, ey), (tx, ty)], fill=(235, 235, 245, 255), width=1)
        gx = pivot_x + math.cos(rad) * 3.5
        gy = pivot_y + math.sin(rad) * 3.5
        draw.line(
            [
                (gx + math.cos(perp) * 3.5, gy + math.sin(perp) * 3.5),
                (gx - math.cos(perp) * 3.5, gy - math.sin(perp) * 3.5),
            ],
            fill=(170, 145, 70, 255),
            width=2,
        )
    elif kind == "hammer":
        # Short mallet matching the builder idle prop
        draw.line([(pivot_x, pivot_y), (ex, ey)], fill=(110, 72, 40, 255), width=2)
        hx2 = ex + math.cos(rad) * 0.5
        hy2 = ey + math.sin(rad) * 0.5
        p1 = (
            hx2 + math.cos(perp) * 3.5 + math.cos(rad) * 2.5,
            hy2 + math.sin(perp) * 3.5 + math.sin(rad) * 2.5,
        )
        p2 = (
            hx2 - math.cos(perp) * 3.5 + math.cos(rad) * 2.5,
            hy2 - math.sin(perp) * 3.5 + math.sin(rad) * 2.5,
        )
        p3 = (
            hx2 - math.cos(perp) * 3.5 - math.cos(rad) * 2.5,
            hy2 - math.sin(perp) * 3.5 - math.sin(rad) * 2.5,
        )
        p4 = (
            hx2 + math.cos(perp) * 3.5 - math.cos(rad) * 2.5,
            hy2 + math.sin(perp) * 3.5 - math.sin(rad) * 2.5,
        )
        draw.polygon([p1, p2, p3, p4], fill=(145, 150, 160, 255))
    else:
        draw.line([(pivot_x, pivot_y), (ex, ey)], fill=(125, 82, 45, 255), width=2)
        hx2 = ex + math.cos(rad) * 2
        hy2 = ey + math.sin(rad) * 2
        p1 = (hx2 + math.cos(perp) * 5.5, hy2 + math.sin(perp) * 5.5)
        p2 = (hx2 - math.cos(perp) * 5.5, hy2 - math.sin(perp) * 5.5)
        draw.line([p1, p2], fill=(155, 115, 65, 255), width=3)

    # Grip — sits on top of the handle so it reads as held
    draw.ellipse([pivot_x - 2.2, pivot_y - 2.2, pivot_x + 2.2, pivot_y + 2.2], fill=(215, 175, 135, 255))
    composed = Image.alpha_composite(frame, overlay)
    if show_trail:
        composed = draw_slash_trail(composed, pivot=(pivot_x, pivot_y), angle_deg=angle_deg, length=18)
    return composed


def _outward(right_side: bool) -> float:
    return 1.0 if right_side else -1.0


# Front-sheet weapon side (viewer's right == True). Back sheets flip.
# Knight sword is on the left; shield must not win detection.
WEAPON_SIDE_FRONT: dict[str, bool] = {
    "knight": False,   # sword on viewer's left
    "archer": True,    # bow on viewer's right
    "builder": True,   # hammer on viewer's right when facing right
    "villager": False,
    "enemy": False,
}


def make_attack(
    base: Image.Image,
    facing_back: bool = False,
    ranged: bool = False,
    melee_kind: str = "sword",
    unit: str = "",
) -> Image.Image:
    """
    Attack using ONLY the painted weapon/arm already on the sprite.
    No second sword/bow overlays — same limb-shift approach as walk.
    """
    sprite = to_sprite(base)
    if unit in WEAPON_SIDE_FRONT:
        weapon_right = WEAPON_SIDE_FRONT[unit]
    else:
        weapon_right = detect_weapon_side(sprite)
    if facing_back:
        weapon_right = not weapon_right
    out = _outward(weapon_right)

    frames = []
    for i in range(9):
        if ranged:
            # Bow stays on weapon side; draw-hand is the opposite side.
            draw_right = not weapon_right
            if i <= 6:
                pull = i / 6.0
                # Draw hand pulls back toward quiver; bow arm raises slightly
                draw_dx = -_outward(draw_right) * pull * 3.5
                draw_dy = -pull * 2.5
                bow_dx = out * pull * 0.8
                bow_dy = -pull * 1.5
                bob = -pull * 1.0
            else:
                release = (i - 6) / 2.0
                pull = max(0.0, 1.0 - release * 1.6)
                draw_dx = -_outward(draw_right) * pull * 3.5
                draw_dy = -pull * 2.5
                bow_dx = out * (0.8 - release * 1.2)
                bow_dy = -1.5 + release * 2.0
                bob = -1.0 + release * 1.0

            posed = move_weapon_arm(sprite, right_side=draw_right, dx=draw_dx, dy=draw_dy)
            posed = move_weapon_arm(posed, right_side=weapon_right, dx=bow_dx, dy=bow_dy)
            fr = place_sprite(posed, angle=0.0, dx=0.0, dy=bob)
        else:
            # Melee keyframes: (weapon_dx, weapon_dy, stretch, bob, lunge)
            # Moves the EXISTING sword/claw arm — windup up/back, strike down/forward.
            poses = [
                (0.0, 0.0, 0.0, 0.0, 0.0),       # 0 ready
                (-1.2, -3.0, 0.0, -0.4, -0.4),   # 1 windup
                (-2.0, -5.5, 0.0, -0.8, -0.8),   # 2
                (-2.4, -7.0, 0.0, -1.0, -1.2),   # 3 peak raise
                (1.5, -2.0, 0.8, 0.2, 0.8),      # 4 start swing
                (4.5, 3.0, 1.8, 1.2, 2.2),       # 5 HIT
                (3.2, 2.2, 1.0, 0.8, 1.4),       # 6 follow
                (1.4, 0.8, 0.3, 0.3, 0.5),       # 7
                (0.3, 0.0, 0.0, 0.0, 0.0),       # 8 recover
            ]
            wdx, wdy, stretch, bob, lunge = poses[i]
            posed = move_weapon_arm(
                sprite,
                right_side=weapon_right,
                dx=out * wdx,
                dy=wdy,
                stretch_down=stretch,
            )
            # Tiny weight shift on the plant foot side (readable, not a sway)
            if abs(lunge) > 0.2:
                posed = split_legs(posed, stride=out * lunge * 0.35, lift=0.0)
            fr = place_sprite(
                posed,
                angle=0.0,
                dx=lunge * (0.6 if not facing_back else -0.6),
                dy=bob,
            )
        frames.append(fr)
    return stitch(frames)


def harden_alpha(sprite: Image.Image, cut: int = 40) -> Image.Image:
    """Remove soft/ghost fringes left by pixel arm moves."""
    arr = np.array(sprite.convert("RGBA"))
    arr[arr[:, :, 3] < cut, 3] = 0
    arr[arr[:, :, 3] >= cut, 3] = 255
    return Image.fromarray(arr, "RGBA")


def _is_green_staff_pixel(r: int, g: int, b: int) -> bool:
    """Villager painted staff is green — never match the brown vest."""
    return g > r + 12 and g > b + 8 and 55 < g < 200


def _plot_line(
    arr: np.ndarray,
    x0: float,
    y0: float,
    x1: float,
    y1: float,
    color: tuple[int, int, int, int],
) -> None:
    """Bresenham-style solid line — no antialias dark fringes."""
    steps = max(int(math.hypot(x1 - x0, y1 - y0) * 2), 1)
    for i in range(steps + 1):
        t = i / steps
        x = int(round(x0 + (x1 - x0) * t))
        y = int(round(y0 + (y1 - y0) * t))
        if 0 <= x < FRAME and 0 <= y < FRAME:
            arr[y, x] = color


def draw_hoe_crisp(frame: Image.Image, pivot: tuple[float, float], angle_deg: float) -> Image.Image:
    """Crisp hoe with no ImageDraw antialias ghosts."""
    arr = np.array(frame.convert("RGBA"))
    px, py = pivot
    rad = math.radians(angle_deg)
    length = 17.0
    ex = px + math.cos(rad) * length
    ey = py + math.sin(rad) * length
    handle = (168, 112, 58, 255)
    head = (176, 132, 72, 255)
    grip = (220, 180, 130, 255)
    _plot_line(arr, px, py, ex, ey, handle)
    # tip blade perpendicular
    perp = rad + math.pi / 2
    bx0 = ex + math.cos(perp) * 5
    by0 = ey + math.sin(perp) * 5
    bx1 = ex - math.cos(perp) * 5
    by1 = ey - math.sin(perp) * 5
    _plot_line(arr, bx0, by0, bx1, by1, head)
    gx, gy = int(round(px)), int(round(py))
    if 0 <= gx < FRAME and 0 <= gy < FRAME:
        arr[gy, gx] = grip
    return Image.fromarray(arr, "RGBA")


def make_villager_work(base: Image.Image) -> Image.Image:
    """
    9-frame farming chop matching attack cadence.
    Idle-sized body + crisp hoe on the outer hand (no antialias ghosts).
    """
    sprite = harden_alpha(to_sprite(base), cut=30)
    # Remove green sash-drape streaks that read as a second stick
    arr = np.array(sprite)
    x0, y0, x1, y1, mid_x, shoulder_y = character_bounds(sprite)
    for y in range(int(shoulder_y + (y1 - y0) * 0.35), y1 + 1):
        for x in range(FRAME):
            if arr[y, x, 3] < 8:
                continue
            r, g, b = int(arr[y, x, 0]), int(arr[y, x, 1]), int(arr[y, x, 2])
            # Only erase thin green drips below the waist (not the sash band itself)
            if _is_green_staff_pixel(r, g, b) and abs(x - mid_x) <= 3:
                arr[y, x] = 0
    body = harden_alpha(Image.fromarray(arr, "RGBA"), cut=40)

    grip_x = float(mid_x + (x1 - x0) * 0.32)
    grip_y = float(shoulder_y + (y1 - y0) * 0.20)

    # Stay on the right side of the body (0°=right, 90°=down)
    # Full chop arc: ready → raise → strike → follow (no long idle tail)
    angles = [88.0, 60.0, 28.0, -20.0, 15.0, 55.0, 78.0, 90.0, 88.0]
    bobs = [0.0, -0.8, -1.4, -1.8, 0.2, 2.0, 1.0, 0.4, 0.0]
    leans = [0.0, -0.8, -1.2, -1.5, 1.0, 2.0, 1.0, 0.4, 0.0]
    grip_dy = [0.0, -2.8, -5.0, -6.8, -2.0, 2.5, 1.0, 0.3, 0.0]
    grip_dx = [0.0, 0.8, 1.4, 1.8, 1.2, 2.0, 1.0, 0.4, 0.0]

    frames = []
    for i in range(9):
        # No swing_arm_band — pixel warps leave black seams on this sprite
        pivot = (grip_x + grip_dx[i], grip_y + grip_dy[i])
        posed = draw_hoe_crisp(body, pivot, angles[i])
        fr = place_sprite(posed, angle=0.0, dx=leans[i], dy=bobs[i])
        frames.append(harden_alpha(fr, cut=40))
    return stitch(frames)


def make_work(
    base: Image.Image,
    facing_back: bool = False,
    tool: str = "axe",
    unit: str = "",
) -> Image.Image:
    """
    Fluid 9-frame work loop matching attack cadence.
    Villagers use a dedicated staff/hoe swing (vest browns must not be warped).
    """
    if unit == "villager" or tool == "hoe":
        return make_villager_work(base)

    sprite = harden_alpha(to_sprite(base), cut=30)
    if unit in WEAPON_SIDE_FRONT:
        weapon_right = WEAPON_SIDE_FRONT[unit]
    else:
        weapon_right = detect_weapon_side(sprite)
    if facing_back:
        weapon_right = not weapon_right
    out = _outward(weapon_right)

    poses = [
        (0.0, 0.0, 0.0, 0.0),
        (-1.0, -3.0, 0.0, -0.3),
        (-1.6, -5.5, 0.0, -0.6),
        (-2.0, -7.0, 0.0, -0.9),
        (1.2, -1.5, 0.6, 0.2),
        (3.8, 3.2, 1.6, 1.1),
        (2.6, 2.0, 0.8, 0.7),
        (1.2, 0.7, 0.25, 0.3),
        (0.3, 0.0, 0.0, 0.0),
    ]

    frames = []
    for wdx, wdy, stretch, bob in poses:
        posed = move_weapon_arm(
            sprite,
            right_side=weapon_right,
            dx=out * wdx,
            dy=wdy,
            stretch_down=stretch,
        )
        posed = harden_alpha(posed, cut=48)
        fr = place_sprite(posed, angle=0.0, dx=0.0, dy=bob)
        frames.append(harden_alpha(fr, cut=40))
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

    # Knight/archer/enemy attacks and builder/villager work are built from
    # dedicated pose sheets (tools/build_attack_sheets_from_poses.py).
    skip_attack = unit in ("knight", "archer", "enemy")
    if has_attack and not skip_attack:
        melee_kind = "claw" if unit == "enemy" else "sword"
        save(
            make_attack(front, False, ranged=ranged, melee_kind=melee_kind, unit=unit),
            unit_dir / f"chr_{unit}_attack.png",
        )
        save(
            make_attack(back, True, ranged=ranged, melee_kind=melee_kind, unit=unit),
            unit_dir / f"chr_{unit}_attack_back.png",
        )

    skip_work = unit in ("builder", "villager")  # work from AI poses when available
    if has_work and not skip_work:
        save(make_work(front, False, tool=tool, unit=unit), unit_dir / f"chr_{unit}_afk.png")


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
