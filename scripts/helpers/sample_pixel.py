#!/usr/bin/env python3
"""sample_pixel.py — Sample a pixel color from an image at given coords.

Usage:
    sample_pixel.py <image_path> <x> <y> [--format hex|rgb|rgba] [--patch SIZE]

Output (stdout, one line):
    hex   → #rrggbb (default)
    rgb   → 123,45,67
    rgba  → 123,45,67,255

--patch SIZE (default 1):
    Average an N×N patch centered on (x,y). Patch sampling is common in
    design-token tooling because single-pixel values for high-frequency
    content (icon edges, antialiased text, hard outlines) can be
    unrepresentative of the perceived token colour. petrics dogfood on
    GH #11 reopen found that single-pixel `#96c01f` vs 3×3-averaged
    `#90b534` at the same coord both flag the regression by miles, but
    the inconsistency forces the fleet to negotiate during synthesis.
    Defaults to 1 (single pixel) to preserve current behaviour; pass
    --patch 3 (or 5) for averaged sampling.

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


def parse_args(argv: list[str]) -> tuple[str, int, int, str, int]:
    if len(argv) < 4:
        die(1, f"usage: {Path(argv[0]).name} <image_path> <x> <y> [--format hex|rgb|rgba] [--patch SIZE]")
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
    patch = 1
    if "--patch" in argv:
        i = argv.index("--patch")
        if i + 1 >= len(argv):
            die(1, "--patch requires a positive odd integer")
        try:
            patch = int(argv[i + 1])
        except ValueError:
            die(1, f"--patch must be an integer, got: {argv[i + 1]!r}")
        if patch < 1:
            die(1, f"--patch must be ≥ 1, got: {patch}")
        # Reject even values: the centering logic (`patch // 2` half-window)
        # turns `--patch 4` into a 5×5 region, surprising the caller. Only
        # odd sizes have a true center pixel. Closes gemini SEV-2 from
        # GH #11 reopen consensus.
        if patch % 2 == 0:
            die(1, f"--patch must be ODD (1, 3, 5, ...) for a true centered window; got: {patch}")
    return image_path, x, y, fmt, patch


def main(argv: list[str]) -> int:
    image_path, x, y, fmt, patch = parse_args(argv)

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

    if patch == 1:
        pixel = img_rgba.getpixel((x, y))
        if not isinstance(pixel, tuple) or len(pixel) != 4:
            die(4, f"unexpected pixel value: {pixel!r}")
        r, g, b, a = pixel
    else:
        # N×N patch centered on (x,y), clamped to image bounds.
        # Average over collected pixels; integer-truncate for hex output.
        half = patch // 2
        x_lo = max(0, x - half)
        x_hi = min(w - 1, x + half)
        y_lo = max(0, y - half)
        y_hi = min(h - 1, y + half)
        r_sum = g_sum = b_sum = a_sum = 0
        count = 0
        for px in range(x_lo, x_hi + 1):
            for py in range(y_lo, y_hi + 1):
                pr, pg, pb, pa = img_rgba.getpixel((px, py))
                r_sum += pr; g_sum += pg; b_sum += pb; a_sum += pa
                count += 1
        if count == 0:
            die(4, "patch sampling collected zero pixels (unexpected)")
        r = r_sum // count
        g = g_sum // count
        b = b_sum // count
        a = a_sum // count

    if fmt == "hex":
        print(f"#{r:02x}{g:02x}{b:02x}")
    elif fmt == "rgb":
        print(f"{r},{g},{b}")
    elif fmt == "rgba":
        print(f"{r},{g},{b},{a}")

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
