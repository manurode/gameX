"""Offline preview of the wall post lattice.

Mirrors the runtime geometry (WallTexture) and draw math so wall chaining and
corners can be checked without launching the game:

  post(i, j) = i * STEP_SE + j * STEP_SW
  a segment is the edge between two neighbouring posts, drawn at its midpoint
  a world anchor maps to texture pixel (128, 208) at scale 0.95
  segments paint back-to-front by anchor Y (Godot Y-sort)

Usage: python tools/preview_walls.py [out.png]
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
BUILDINGS = ROOT / "assets" / "tilesets" / "mediterranean" / "Buildings"

SEGMENT_SPACING = 140.0
STEP = {
    False: (SEGMENT_SPACING, -SEGMENT_SPACING * 0.5),  # SE "/"
    True: (SEGMENT_SPACING, SEGMENT_SPACING * 0.5),  # SW "\"
}
SCALE = 0.95
ANCHOR_PX = (128.0, 208.0)


def post_position(i: int, j: int) -> tuple[float, float]:
    se, sw = STEP[False], STEP[True]
    return (se[0] * i + sw[0] * j, se[1] * i + sw[1] * j)


def segment_center(i: int, j: int, vertical: bool) -> tuple[float, float]:
    post = post_position(i, j)
    step = STEP[vertical]
    return (post[0] + step[0] * 0.5, post[1] + step[1] * 0.5)


def load(name: str) -> Image.Image:
    return Image.open(BUILDINGS / f"{name}.png").convert("RGBA")


def paste(canvas: Image.Image, tex: Image.Image, anchor, origin) -> None:
    scaled = tex.resize(
        (round(tex.width * SCALE), round(tex.height * SCALE)), Image.LANCZOS
    )
    x = origin[0] + anchor[0] - ANCHOR_PX[0] * SCALE
    y = origin[1] + anchor[1] - ANCHOR_PX[1] * SCALE
    canvas.alpha_composite(scaled, (round(x), round(y)))


def draw(canvas: Image.Image, items, origin) -> None:
    """items: list of (anchor, texture_name). Painted back-to-front by anchor Y."""
    for anchor, name in sorted(items, key=lambda w: w[0][1]):
        paste(canvas, load(name), anchor, origin)


def segment_art(i: int, j: int, vertical: bool, texture: str | None = None):
    return (segment_center(i, j, vertical), texture or ("wall_sw" if vertical else "wall_se"))


def ring(radius: int):
    """Closed ring of edges, the same one spawn_starter_walls builds."""
    items = []
    for k in range(-radius, radius):
        items.append(segment_art(radius, k, True))
        items.append(segment_art(-radius, k, True))
        items.append(segment_art(k, radius, False))
        items.append(segment_art(k, -radius, False))
    return items


def l_run(start, di: int, dj: int, ghost_from: int = 10**9):
    """SE leg then SW leg, like a drag. Segments past `ghost_from` use plot art."""
    items = []
    i, j = start
    n = 0
    for _ in range(abs(di)):
        step = 1 if di > 0 else -1
        low = i if step > 0 else i + step
        items.append(segment_art(low, j, False, "wall_se_plot" if n >= ghost_from else None))
        i += step
        n += 1
    for _ in range(abs(dj)):
        step = 1 if dj > 0 else -1
        low = j if step > 0 else j + step
        items.append(segment_art(i, low, True, "wall_sw_plot" if n >= ghost_from else None))
        j += step
        n += 1
    return items


def main() -> None:
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "output" / "wall_preview.png"
    canvas = Image.new("RGBA", (1700, 1100), (74, 122, 62, 255))

    items = ring(2)
    # A run that leaves the ring's east post and turns: exercises T junction + corner.
    items += l_run((2, 2), 2, 2)
    # Built run continued by ghosts, to check the placeholder lines up with the wall.
    items += l_run((-2, 2), 0, 3, ghost_from=1)

    draw(canvas, items, (700.0, 560.0))
    out.parent.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(out)
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
