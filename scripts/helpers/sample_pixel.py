#!/usr/bin/env python3
"""sample_pixel.py — Sample a pixel color from an image at given coords.

Usage:
    sample_pixel.py <image_path> <x> <y> [--format hex|rgb|rgba]

Output (stdout, one line):
    hex   → #rrggbb (default)
    rgb   → 123,45,67
    rgba  → 123,45,67,255

Exit codes:
    0  success
    1  bad arguments / out-of-bounds coords
    2  Pillow not installed (with install hint)
    3  image not readable / unsupported format
    4  pixel sampling returned unexpected mode

This is part of /octo:visual-review's tooling — reviewers call it to
sample mockup pixels at named coordinates, then compare to code values
via delta_e.py. Closes the "no tool means eyeballing" gap noted in
GH #11 (cheap-leg-feedback).
"""

import sys
from pathlib import Path


def die(code: int, msg: str) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(code)


def parse_args(argv: list[str]) -> tuple[str, int, int, str]:
    if len(argv) < 4:
        die(1, f"usage: {Path(argv[0]).name} <image_path> <x> <y> [--format hex|rgb|rgba]")
    image_path = argv[1]
    try:
        x, y = int(argv[2]), int(argv[3])
    except ValueError:
        die(1, f"x and y must be integers, got: {argv[2]!r}, {argv[3]!r}")
    fmt = "hex"
    if "--format" in argv:
        i = argv.index("--format")
        if i + 1 >= len(argv):
            die(1, "--format requires an argument (hex|rgb|rgba)")
        fmt = argv[i + 1]
    if fmt not in ("hex", "rgb", "rgba"):
        die(1, f"--format must be hex|rgb|rgba, got: {fmt!r}")
    return image_path, x, y, fmt


def main(argv: list[str]) -> int:
    image_path, x, y, fmt = parse_args(argv)

    if not Path(image_path).is_file():
        die(3, f"image not found: {image_path}")

    try:
        from PIL import Image  # type: ignore
    except ImportError:
        die(2, "Pillow not installed. Install with: pip install Pillow")

    try:
        img = Image.open(image_path)
    except Exception as e:
        die(3, f"cannot open image {image_path}: {e}")

    w, h = img.size
    if not (0 <= x < w and 0 <= y < h):
        die(1, f"coords ({x},{y}) out of bounds for image size {w}x{h}")

    # Convert to RGBA for uniform sampling (handles palette, grayscale, etc.)
    img_rgba = img.convert("RGBA")
    pixel = img_rgba.getpixel((x, y))
    if not isinstance(pixel, tuple) or len(pixel) != 4:
        die(4, f"unexpected pixel value: {pixel!r}")
    r, g, b, a = pixel

    if fmt == "hex":
        print(f"#{r:02x}{g:02x}{b:02x}")
    elif fmt == "rgb":
        print(f"{r},{g},{b}")
    elif fmt == "rgba":
        print(f"{r},{g},{b},{a}")

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
