"""Build small Godot cursor textures from generated square source images."""

from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path

from PIL import Image, ImageDraw


CURSORS = {
    "default": "cursor_default_src.png",
    "gather_wood": "cursor_saw_src.png",
    "gather_gold": "cursor_pickaxe_straight_src.png",
    "gather_food": "cursor_hoe_src.png",
    "build": "cursor_hammer_src.png",
    "attack": "cursor_sword_src.png",
}
OUTPUT_SIZE = 48
CONTENT_SIZE = 38
PADDING = 2
ROTATIONS: dict[str, float] = {}


def _is_background_candidate(pixel: tuple[int, int, int, int]) -> bool:
    red, green, blue, _alpha = pixel
    return min(red, green, blue) >= 225 and max(red, green, blue) - min(red, green, blue) <= 8


def _remove_checkerboard(image: Image.Image) -> Image.Image:
    """Remove the light checkerboard baked into generated preview images.

    The outside is flood-filled so light paint inside each dark tool outline is
    preserved. Enclosed checker components (for example, a saw handle opening)
    are removed only when most pixels match the two checker shades.
    """
    rgba = image.convert("RGBA")
    width, height = rgba.size
    pixels = rgba.load()
    visited = bytearray(width * height)
    components: list[tuple[list[tuple[int, int]], bool]] = []

    for y in range(height):
        for x in range(width):
            index = y * width + x
            if visited[index] or not _is_background_candidate(pixels[x, y]):
                continue
            queue = deque([(x, y)])
            visited[index] = 1
            component: list[tuple[int, int]] = []
            touches_edge = False
            while queue:
                px, py = queue.popleft()
                component.append((px, py))
                touches_edge = touches_edge or px == 0 or py == 0 or px == width - 1 or py == height - 1
                for nx, ny in ((px - 1, py), (px + 1, py), (px, py - 1), (px, py + 1)):
                    if nx < 0 or ny < 0 or nx >= width or ny >= height:
                        continue
                    neighbor_index = ny * width + nx
                    if visited[neighbor_index] or not _is_background_candidate(pixels[nx, ny]):
                        continue
                    visited[neighbor_index] = 1
                    queue.append((nx, ny))
            components.append((component, touches_edge))

    for component, touches_edge in components:
        checker_like = 0
        for x, y in component:
            red, green, blue, _alpha = pixels[x, y]
            level = (red + green + blue) / 3.0
            if 232.0 <= level <= 243.0 or level >= 249.0:
                checker_like += 1
        remove = touches_edge or (
            len(component) >= 64 and checker_like / float(len(component)) >= 0.82
        )
        if remove:
            for x, y in component:
                red, green, blue, _alpha = pixels[x, y]
                pixels[x, y] = (red, green, blue, 0)

    return rgba


def _crop_and_resize(image: Image.Image, action: str) -> Image.Image:
    rotation = ROTATIONS.get(action, 0.0)
    if rotation:
        image = image.rotate(
            rotation,
            resample=Image.Resampling.BICUBIC,
            expand=True,
        )
    alpha = image.getchannel("A")
    bbox = alpha.getbbox()
    if bbox is None:
        raise ValueError("source became fully transparent")
    cropped = image.crop(bbox)
    scale = min(CONTENT_SIZE / cropped.width, CONTENT_SIZE / cropped.height)
    resized = cropped.resize(
        (max(1, round(cropped.width * scale)), max(1, round(cropped.height * scale))),
        Image.Resampling.LANCZOS,
    )
    output = Image.new("RGBA", (OUTPUT_SIZE, OUTPUT_SIZE), (0, 0, 0, 0))
    output.alpha_composite(resized, (PADDING, PADDING))
    return output


def _make_preview(outputs: list[tuple[str, Image.Image]], destination: Path) -> None:
    cell = 72
    preview = Image.new("RGBA", (cell * len(outputs), cell), (126, 200, 80, 255))
    for index, (_name, image) in enumerate(outputs):
        x = index * cell + (cell - OUTPUT_SIZE) // 2
        y = (cell - OUTPUT_SIZE) // 2
        preview.alpha_composite(image, (x, y))
    preview.save(destination)


def _make_forbidden_cursor(image: Image.Image) -> Image.Image:
    scale = 4
    large = image.resize(
        (OUTPUT_SIZE * scale, OUTPUT_SIZE * scale),
        Image.Resampling.LANCZOS,
    )
    draw = ImageDraw.Draw(large)
    ring = (215, 50, 42, 255)
    shadow = (74, 28, 24, 255)
    bounds = tuple(value * scale for value in (5, 5, 43, 43))
    draw.ellipse(bounds, outline=shadow, width=5 * scale)
    draw.ellipse(bounds, outline=ring, width=3 * scale)
    slash = tuple(value * scale for value in (10, 38, 38, 10))
    draw.line(slash, fill=shadow, width=6 * scale)
    draw.line(slash, fill=ring, width=4 * scale)
    return large.resize((OUTPUT_SIZE, OUTPUT_SIZE), Image.Resampling.LANCZOS)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source_dir", type=Path)
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("assets/ui/cursors"),
    )
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)

    outputs: list[tuple[str, Image.Image]] = []
    for action, source_name in CURSORS.items():
        source = args.source_dir / source_name
        image = _crop_and_resize(_remove_checkerboard(Image.open(source)), action)
        image.save(args.output_dir / f"cursor_{action}.png", optimize=True)
        outputs.append((action, image))

    build_image = dict(outputs)["build"]
    forbidden = _make_forbidden_cursor(build_image)
    forbidden.save(args.output_dir / "cursor_build_forbidden.png", optimize=True)
    outputs.append(("build_forbidden", forbidden))
    _make_preview(outputs, args.output_dir / "_preview.png")


if __name__ == "__main__":
    main()
