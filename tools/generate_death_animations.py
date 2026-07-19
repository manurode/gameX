#!/usr/bin/env python3
"""Generate themed death sprite strips from each unit's idle frames.

Keeps the living silhouette footprint (same cell size / body scale) and writes:
  chr_{unit}_death.png       (front / down)
  chr_{unit}_death_back.png  (back / up)
"""

from __future__ import annotations

import math
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
CHARS = ROOT / "assets/tilesets/mediterranean/Characters"
PREVIEW = ROOT / "tools/anim_preview/death"
FRAME = 80
DEATH_FRAMES = 6

# Monster kinds get flashy dissolve deaths; humanoids get a readable fall.
STYLES: dict[str, str] = {
    "knight": "fall",
    "archer": "fall",
    "mage": "fall",
    "villager": "fall",
    "builder": "fall",
    "enemy": "shatter",
    "ember": "evaporate",
    "mire": "crumble",
    "hexwing": "spectral",
}


def harden_alpha(im: Image.Image, cut: int = 40) -> Image.Image:
    arr = np.array(im.convert("RGBA"))
    arr[arr[:, :, 3] < cut, 3] = 0
    arr[arr[:, :, 3] >= cut, 3] = 255
    return Image.fromarray(arr, "RGBA")


def load_base(unit: str, facing: str) -> Image.Image:
    name = f"chr_{unit}_idle.png" if facing == "down" else f"chr_{unit}_idle_back.png"
    path = CHARS / unit / name
    if not path.exists() and facing == "up":
        path = CHARS / unit / f"chr_{unit}_idle.png"
    im = Image.open(path).convert("RGBA")
    return harden_alpha(im.crop((0, 0, FRAME, FRAME)), cut=30)


def content_bbox(im: Image.Image) -> tuple[int, int, int, int] | None:
    return im.split()[-1].getbbox()


def place_preserving_feet(
    sprite: Image.Image,
    *,
    angle: float = 0.0,
    dx: float = 0.0,
    dy: float = 0.0,
    scale: float = 1.0,
    squash_y: float = 1.0,
    alpha: float = 1.0,
) -> Image.Image:
    """Transform sprite while keeping feet near the original ground line."""
    src = harden_alpha(sprite, cut=30)
    bb = content_bbox(src)
    canvas = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    if bb is None:
        return canvas

    foot_y = bb[3]
    char = src.crop(bb)
    if abs(scale - 1.0) > 0.001 or abs(squash_y - 1.0) > 0.001:
        nw = max(1, int(round(char.width * scale)))
        nh = max(1, int(round(char.height * scale * squash_y)))
        char = char.resize((nw, nh), Image.Resampling.BILINEAR)

    if abs(angle) > 0.05:
        char = char.rotate(angle, resample=Image.Resampling.BILINEAR, expand=True, fillcolor=(0, 0, 0, 0))

    if alpha < 0.999:
        arr = np.array(char)
        arr[:, :, 3] = (arr[:, :, 3].astype(np.float32) * alpha).astype(np.uint8)
        char = Image.fromarray(arr, "RGBA")

    px = int(round((FRAME - char.width) / 2 + dx))
    py = int(round(foot_y - char.height + dy))
    px = max(-24, min(FRAME - char.width + 24, px))
    py = max(-24, min(FRAME - char.height + 24, py))
    canvas.alpha_composite(char, (px, py))
    return harden_alpha(canvas, cut=24)


def tint_alpha(im: Image.Image, color: tuple[int, int, int], strength: float) -> Image.Image:
    arr = np.array(im.convert("RGBA")).astype(np.float32)
    mask = arr[:, :, 3] > 0
    for c in range(3):
        arr[mask, c] = arr[mask, c] * (1.0 - strength) + color[c] * strength
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")


def boost_channel(im: Image.Image, rgb_gain: tuple[float, float, float], alpha_mul: float = 1.0) -> Image.Image:
    arr = np.array(im.convert("RGBA")).astype(np.float32)
    for i, g in enumerate(rgb_gain):
        arr[:, :, i] = np.clip(arr[:, :, i] * g, 0, 255)
    arr[:, :, 3] = np.clip(arr[:, :, 3] * alpha_mul, 0, 255)
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def draw_particles(
    canvas: Image.Image,
    particles: list[tuple[float, float, float, tuple[int, int, int, int]]],
) -> Image.Image:
    overlay = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    for x, y, r, color in particles:
        if r < 0.4:
            continue
        draw.ellipse([x - r, y - r, x + r, y + r], fill=color)
    return Image.alpha_composite(canvas, overlay)


def _rng(seed: int) -> random.Random:
    return random.Random(seed)


def death_fall(base: Image.Image, frame: int, total: int, seed: int) -> Image.Image:
    """Humanoid: stagger → buckle → tip → ground settle."""
    t = frame / max(total - 1, 1)
    # Ease-in collapse
    ease = t * t
    angle = -8.0 * t + (-78.0) * ease  # tip to the side
    squash = 1.0 - 0.35 * ease
    scale = 1.0 - 0.06 * ease
    dy = 2.0 * t + 14.0 * ease
    dx = 3.0 * ease
    alpha = 1.0 - 0.12 * ease
    fr = place_preserving_feet(
        base, angle=angle, dx=dx, dy=dy, scale=scale, squash_y=squash, alpha=alpha
    )
    if t > 0.35:
        fr = tint_alpha(fr, (110, 110, 120), 0.15 + 0.35 * ease)
    # Dust puffs near feet on impact frames
    if frame >= total // 2:
        rng = _rng(seed + frame * 17)
        bb = content_bbox(fr)
        particles = []
        if bb:
            cx = (bb[0] + bb[2]) * 0.5
            fy = bb[3] - 2
            for _ in range(4 + frame):
                particles.append(
                    (
                        cx + rng.uniform(-18, 18),
                        fy + rng.uniform(-3, 2),
                        rng.uniform(0.8, 2.2),
                        (160, 140, 110, int(140 * (1.0 - t * 0.4))),
                    )
                )
        fr = draw_particles(fr, particles)
    return fr


def death_evaporate(base: Image.Image, frame: int, total: int, seed: int) -> Image.Image:
    """Ember: flare → rise → dissolve into rising sparks."""
    t = frame / max(total - 1, 1)
    # Last frame is fully empty so nothing lingers on screen.
    if frame >= total - 1:
        return Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    ease = t ** 1.35
    body_alpha = max(0.0, 1.0 - ease * 1.25)
    rise = -28.0 * ease
    scale = 1.0 - 0.45 * ease
    squash = 1.0 + 0.25 * ease  # stretch as it becomes flame
    flared = boost_channel(base, (1.15 + 0.5 * t, 1.05 + 0.35 * t, 0.75), 1.0)
    if t < 0.75:
        body = place_preserving_feet(
            flared, dy=rise, scale=scale, squash_y=squash, alpha=body_alpha
        )
        body = tint_alpha(body, (255, 140, 40), 0.2 + 0.45 * ease)
    else:
        body = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))

    bb = content_bbox(base)
    rng = _rng(seed + frame * 31)
    particles: list[tuple[float, float, float, tuple[int, int, int, int]]] = []
    if bb and t < 0.92:
        cx = (bb[0] + bb[2]) * 0.5
        cy = (bb[1] + bb[3]) * 0.55
        fade = max(0.0, 1.0 - t * 1.15)
        n = int((10 + frame * 3) * fade)
        for i in range(n):
            life = (i / max(n, 1) + t) % 1.0
            px = cx + rng.uniform(-16, 16) * (0.4 + life)
            py = cy + rise * 0.6 - life * (22 + frame * 3) + rng.uniform(-4, 4)
            r = max(0.5, 2.6 * (1.0 - life) * fade)
            hot = rng.choice(
                [
                    (255, 220, 80, int(220 * (1.0 - life) * fade)),
                    (255, 140, 40, int(200 * (1.0 - life) * fade)),
                    (255, 80, 20, int(180 * (1.0 - life) * fade)),
                    (255, 255, 200, int(160 * (1.0 - life) * fade)),
                ]
            )
            particles.append((px, py, r, hot))
    return draw_particles(body, particles)


def _sample_rock_palette(base: Image.Image, n: int, rng: random.Random) -> list[tuple[int, int, int]]:
    arr = np.array(harden_alpha(base, cut=30))
    ys, xs = np.where(arr[:, :, 3] > 40)
    if len(xs) == 0:
        return [(110, 95, 70), (90, 100, 60), (70, 65, 50), (130, 120, 90)]
    colors: list[tuple[int, int, int]] = []
    for _ in range(n):
        i = rng.randrange(len(xs))
        r, g, b = (int(arr[ys[i], xs[i], c]) for c in range(3))
        # Prefer earthy rock tones; skip neon eyes.
        if g > 200 and r < 180:
            r, g, b = 100, 95, 70
        colors.append((r, g, b))
    return colors


def _draw_rock(
    draw: ImageDraw.ImageDraw,
    cx: float,
    cy: float,
    rw: float,
    rh: float,
    color: tuple[int, int, int],
    alpha: int,
    rng: random.Random,
) -> None:
    """Irregular stone polygon (no square blobs)."""
    pts: list[tuple[float, float]] = []
    sides = rng.randint(6, 8)
    for i in range(sides):
        ang = (i / sides) * math.tau + rng.uniform(-0.28, 0.28)
        rad_x = rw * rng.uniform(0.55, 1.05)
        rad_y = rh * rng.uniform(0.55, 1.05)
        pts.append((cx + math.cos(ang) * rad_x, cy + math.sin(ang) * rad_y))
    draw.polygon(pts, fill=(*color, alpha))
    # Tiny highlight polygon (not a square ellipse)
    hi = (
        min(255, color[0] + 35),
        min(255, color[1] + 30),
        min(255, color[2] + 20),
        alpha,
    )
    draw.polygon(
        [
            (cx - rw * 0.25, cy - rh * 0.35),
            (cx + rw * 0.05, cy - rh * 0.55),
            (cx + rw * 0.2, cy - rh * 0.15),
        ],
        fill=hi,
    )


def death_crumble(base: Image.Image, frame: int, total: int, seed: int) -> Image.Image:
    """Mire: body sinks, then breaks into a readable pile of small stones.

    0 intact · 1 crack · 2 stones falling · 3 pile forming · 4 settled pile · 5 gone
    """
    if frame >= total - 1:
        return Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))

    bb = content_bbox(base)
    canvas = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    if bb is None:
        return canvas

    x0, y0, x1, y1 = bb
    mid_x = (x0 + x1) * 0.5
    # Keep feet inside the cell (y1 is usually 78).
    foot_y = min(float(y1), float(FRAME - 2))
    body_w = float(max(x1 - x0, 1))
    body_h = float(max(y1 - y0, 1))

    palette = [
        (118, 108, 78),
        (92, 98, 62),
        (78, 72, 52),
        (140, 128, 96),
        (100, 88, 64),
        (70, 78, 48),
        (125, 115, 85),
        (88, 80, 58),
        (110, 100, 70),
        (95, 85, 60),
        (130, 118, 88),
        (85, 92, 55),
    ]

    # Body: squash in place (never clip under the cell).
    if frame <= 2:
        squash = [1.0, 0.90, 0.68][frame]
        alpha = [1.0, 0.92, 0.55][frame]
        # Scale down instead of sinking past the floor.
        scale = [1.0, 0.96, 0.88][frame]
        body = place_preserving_feet(base, scale=scale, squash_y=squash, alpha=alpha, dy=0.0)
        if frame >= 1:
            body = tint_alpha(body, (55, 50, 38), 0.1 * frame)
        canvas = Image.alpha_composite(canvas, body)

    overlay = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)

    # Explicit rock paths: start on body → end in mound.
    rock_count = 14
    for i in range(rock_count):
        rng_i = _rng(seed + i * 37 + 3)
        sx = mid_x + rng_i.uniform(-body_w * 0.36, body_w * 0.36)
        sy = y0 + body_h * rng_i.uniform(0.15, 0.70)
        layer = i % 4
        tx = mid_x + (i / rock_count - 0.5) * body_w * 0.72 + rng_i.uniform(-2, 2)
        ty = foot_y - 2.0 - layer * 3.2 - abs(tx - mid_x) * 0.05

        # When this rock appears / how far it has fallen by `frame`
        appear = 1 + (i % 3)  # frames 1..3
        if frame < appear:
            continue
        # fall 0 at appear, 1 two frames later
        fall = max(0.0, min(1.0, (frame - appear) / 2.0))
        fall_e = fall * fall * (3 - 2 * fall)

        px = sx * (1 - fall_e) + tx * fall_e
        py = sy * (1 - fall_e) + ty * fall_e
        # Clamp inside cell
        px = max(4.0, min(FRAME - 4.0, px))
        py = max(8.0, min(FRAME - 3.0, py))

        rw = rng_i.uniform(4.0, 7.0)
        rh = rng_i.uniform(3.0, 5.5)
        _draw_rock(draw, px, py, rw, rh, palette[i % len(palette)], 255, rng_i)

    # On pile frames, add a few base stones so the mound reads solid.
    if frame >= 3:
        for i in range(6):
            rng_i = _rng(seed + 900 + i)
            px = mid_x + rng_i.uniform(-body_w * 0.34, body_w * 0.34)
            py = foot_y - 1.0 - (i % 2) * 2.5
            _draw_rock(
                draw,
                px,
                py,
                rng_i.uniform(4.5, 7.5),
                rng_i.uniform(3.0, 5.0),
                palette[(i + 3) % len(palette)],
                255,
                rng_i,
            )

    canvas = Image.alpha_composite(canvas, overlay)
    return canvas


def death_spectral(base: Image.Image, frame: int, total: int, seed: int) -> Image.Image:
    """Hexwing: flare cyan, tear into rising wisps, vanish."""
    if frame >= total - 1:
        return Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    t = frame / max(total - 1, 1)
    ease = t ** 1.2
    body_alpha = max(0.0, 1.0 - ease * 1.1)
    rise = -18.0 * ease
    scale = 1.0 + 0.08 * math.sin(ease * math.pi) - 0.35 * ease
    flared = boost_channel(base, (0.85, 1.1 + 0.4 * t, 1.25 + 0.5 * t), 1.0)
    if body_alpha > 0.05:
        body = place_preserving_feet(flared, dy=rise, scale=scale, alpha=body_alpha)
        body = tint_alpha(body, (80, 220, 255), 0.25 * ease)
        # Soft blur as it dissolves
        if t > 0.35:
            body = body.filter(ImageFilter.GaussianBlur(radius=0.6 + ease))
            body = harden_alpha(body, cut=20)
    else:
        body = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))

    bb = content_bbox(base)
    rng = _rng(seed + frame * 13)
    particles: list[tuple[float, float, float, tuple[int, int, int, int]]] = []
    if bb and t < 0.9:
        cx = (bb[0] + bb[2]) * 0.5
        cy = (bb[1] + bb[3]) * 0.45
        fade = max(0.0, 1.0 - t * 1.1)
        for i in range(int((12 + frame * 2) * fade)):
            life = (i / 20 + t) % 1.0
            px = cx + rng.uniform(-20, 20) * (0.5 + life)
            py = cy + rise - life * (18 + frame * 2.5)
            r = max(0.4, 2.2 * (1.0 - life) * fade)
            col = rng.choice(
                [
                    (120, 240, 255, int(210 * (1.0 - life) * fade)),
                    (180, 120, 255, int(190 * (1.0 - life) * fade)),
                    (60, 80, 160, int(160 * (1.0 - life) * fade)),
                    (220, 240, 255, int(140 * (1.0 - life) * fade)),
                ]
            )
            particles.append((px, py, r, col))
    return draw_particles(body, particles)


def death_shatter(base: Image.Image, frame: int, total: int, seed: int) -> Image.Image:
    """Enemy: purple crystal body implodes into shards."""
    if frame >= total - 1:
        return Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    t = frame / max(total - 1, 1)
    ease = t * t
    arr = np.array(harden_alpha(base, cut=30))
    alpha = arr[:, :, 3] > 0
    ys, xs = np.where(alpha)
    if len(xs) == 0:
        return Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))

    y0, y1 = int(ys.min()), int(ys.max())
    x0, x1 = int(xs.min()), int(xs.max())
    cx = (x0 + x1) * 0.5
    cy = (y0 + y1) * 0.5
    rng = _rng(seed)

    out = np.zeros_like(arr)
    for y, x in zip(ys, xs):
        # Chunk index from local grid
        chunk_x = int((x - x0) // 4)
        chunk_y = int((y - y0) // 4)
        rngc = _rng(seed + chunk_x * 97 + chunk_y * 13)
        ang = rngc.uniform(0, math.tau)
        dist = ease * rngc.uniform(6, 18)
        # Later frames drop downward more
        sx = int(round(x + math.cos(ang) * dist))
        sy = int(round(y + math.sin(ang) * dist * 0.55 + ease * 10))
        if rngc.random() < ease * 0.65:
            continue  # piece already gone
        if 0 <= sx < FRAME and 0 <= sy < FRAME:
            pix = arr[y, x].copy()
            pix[3] = int(pix[3] * (1.0 - 0.5 * ease))
            # Magenta eye flash early
            if t < 0.4 and abs(x - cx) < 6 and y < cy:
                pix[0] = min(255, int(pix[0] * 1.3 + 40))
                pix[2] = min(255, int(pix[2] * 1.2 + 30))
            if pix[3] >= out[sy, sx, 3]:
                out[sy, sx] = pix

    body = Image.fromarray(out, "RGBA")
    body = tint_alpha(body, (160, 60, 200), 0.2 * ease)
    particles = []
    for _ in range(8 + frame * 3):
        particles.append(
            (
                cx + rng.uniform(-20, 20),
                cy + rng.uniform(-14, 16) + ease * 8,
                rng.uniform(0.6, 2.0),
                rng.choice(
                    [
                        (220, 80, 255, int(200 * (1.0 - ease))),
                        (120, 60, 200, int(180 * (1.0 - ease))),
                        (255, 120, 200, int(160 * (1.0 - ease))),
                    ]
                ),
            )
        )
    return draw_particles(body, particles)


GENERATORS = {
    "fall": death_fall,
    "evaporate": death_evaporate,
    "crumble": death_crumble,
    "spectral": death_spectral,
    "shatter": death_shatter,
}


def make_sheet(unit: str, facing: str) -> Image.Image:
    style = STYLES[unit]
    gen = GENERATORS[style]
    base = load_base(unit, facing)
    seed = abs(hash((unit, facing, style))) % 10_000
    sheet = Image.new("RGBA", (FRAME * DEATH_FRAMES, FRAME), (0, 0, 0, 0))
    for i in range(DEATH_FRAMES):
        fr = gen(base, i, DEATH_FRAMES, seed)
        # Rock piles keep soft shading and skip mass-clamp (pile is intentionally wide).
        if style == "crumble":
            sheet.alpha_composite(fr, (i * FRAME, 0))
        else:
            fr = _clamp_mass_to_base(fr, base)
            sheet.alpha_composite(harden_alpha(fr, cut=20), (i * FRAME, 0))
    return sheet


def _clamp_mass_to_base(
    frame: Image.Image,
    base: Image.Image,
    max_w_mul: float = 1.22,
    max_h_mul: float = 1.28,
) -> Image.Image:
    """If FX bloated the frame, shrink content toward idle feet/center."""
    bb_f = content_bbox(frame)
    bb_b = content_bbox(base)
    if bb_f is None or bb_b is None:
        return frame
    fw = bb_f[2] - bb_f[0]
    fh = bb_f[3] - bb_f[1]
    bw = bb_b[2] - bb_b[0]
    bh = bb_b[3] - bb_b[1]
    max_w = bw * max_w_mul
    max_h = bh * max_h_mul
    if fw <= max_w and fh <= max_h:
        return frame
    scale = min(max_w / max(fw, 1), max_h / max(fh, 1), 1.0)
    cropped = frame.crop(bb_f)
    nw = max(1, int(round(cropped.width * scale)))
    nh = max(1, int(round(cropped.height * scale)))
    fitted = cropped.resize((nw, nh), Image.Resampling.BILINEAR)
    canvas = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    px = (FRAME - nw) // 2
    py = bb_b[3] - nh
    px = max(0, min(FRAME - nw, px))
    py = max(0, min(FRAME - nh, py))
    canvas.alpha_composite(fitted, (px, py))
    return canvas


def save_sheet(sheet: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(path)
    print(f"  wrote {path.relative_to(ROOT)} ({sheet.size[0]}x{sheet.size[1]})")


def make_preview_row(unit: str) -> Image.Image:
    down = Image.open(CHARS / unit / f"chr_{unit}_death.png").convert("RGBA")
    idle = Image.open(CHARS / unit / f"chr_{unit}_idle.png").convert("RGBA").crop((0, 0, FRAME, FRAME))
    # Idle | death frames side by side on checker for QA
    row = Image.new("RGBA", (FRAME + down.width + 8, FRAME), (0, 0, 0, 0))
    row.alpha_composite(idle, (0, 0))
    row.alpha_composite(down, (FRAME + 8, 0))
    return row


def main() -> int:
    PREVIEW.mkdir(parents=True, exist_ok=True)
    for unit, style in STYLES.items():
        unit_dir = CHARS / unit
        if not (unit_dir / f"chr_{unit}_idle.png").exists():
            print(f"skip {unit}: missing idle")
            continue
        print(f"{unit} [{style}]")
        save_sheet(make_sheet(unit, "down"), unit_dir / f"chr_{unit}_death.png")
        save_sheet(make_sheet(unit, "up"), unit_dir / f"chr_{unit}_death_back.png")
        preview = make_preview_row(unit)
        # Composite on dark gray so transparent reads
        bg = Image.new("RGBA", preview.size, (32, 32, 36, 255))
        bg.alpha_composite(preview)
        bg.save(PREVIEW / f"{unit}_death_preview.png")
    print("Done.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
