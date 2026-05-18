#!/usr/bin/env python3
"""delta_e.py — Compute CIE76 deltaE color distance between two colors.

Usage:
    delta_e.py <color1> <color2> [--method cie76|cie94|ciede2000]

Inputs accepted (auto-detected):
    Hex:        '#1b2227', '1b2227', '#1b2'  (3-digit shorthand expanded)
    RGB tuple:  '27,34,39'  (decimal 0-255, comma-separated)
    RGBA tuple: '27,34,39,255'  (alpha is ignored — color distance is RGB)

Output (stdout, one line):
    A floating-point deltaE value with 2 decimals (e.g. '17.42').

Thresholds for human-perceptible difference (rule of thumb):
    < 1.0  → not perceptible by human eyes
    1.0-2  → perceptible through close observation
    2-10   → perceptible at a glance (typical UI-divergence range)
    10-49  → colors are more similar than opposite
    > 49   → colors are exact opposite

Exit codes:
    0  success
    1  bad arguments / unparseable color
    2  unsupported --method

CIE76 (default): Euclidean distance in Lab space. Simple, fast, used by
petrics' existing test_palette_assertion.py. Good for "is this color
close enough to a target?" with threshold ~5.

CIE94 and CIEDE2000 are perceptually-weighted refinements; harder to
explain to humans but more accurate for borderline cases. Implemented
here for completeness; CIE76 is the default to match the threshold most
visual-fidelity tooling has calibrated against.

This is part of /octo:visual-review's tooling — reviewers call it to
compare code values (hex from a token) against sampled mockup values
(hex from sample_pixel.py), then flag findings where the distance
exceeds the project's `visual.delta_e_threshold` (default 5.0).
"""

import math
import sys
from pathlib import Path


def die(code: int, msg: str) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(code)


def parse_color(s: str) -> tuple[int, int, int]:
    """Parse a color string into (R, G, B) 0-255 tuple. Alpha is ignored."""
    s = s.strip()
    # Hex variants
    if s.startswith("#"):
        s = s[1:]
    if all(c in "0123456789abcdefABCDEF" for c in s):
        if len(s) == 3:
            # #rgb → #rrggbb
            r = int(s[0] * 2, 16)
            g = int(s[1] * 2, 16)
            b = int(s[2] * 2, 16)
            return r, g, b
        if len(s) == 6:
            return int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16)
        if len(s) == 8:
            # #rrggbbaa — drop alpha
            return int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16)
    # RGB or RGBA decimal tuple
    if "," in s:
        parts = [p.strip() for p in s.split(",")]
        try:
            ints = [int(p) for p in parts]
        except ValueError:
            die(1, f"cannot parse color: {s!r}")
        if not all(0 <= v <= 255 for v in ints):
            die(1, f"RGB values must be 0-255, got: {s!r}")
        if len(ints) == 3:
            return ints[0], ints[1], ints[2]
        if len(ints) == 4:
            return ints[0], ints[1], ints[2]
    die(1, f"unrecognized color format: {s!r}")
    return 0, 0, 0  # unreachable


def srgb_to_linear(c: float) -> float:
    """Convert sRGB (0-1) to linear RGB (0-1) using the standard gamma."""
    if c <= 0.04045:
        return c / 12.92
    return ((c + 0.055) / 1.055) ** 2.4


def rgb_to_xyz(r: int, g: int, b: int) -> tuple[float, float, float]:
    """sRGB (0-255) → XYZ (D65)."""
    rl = srgb_to_linear(r / 255.0)
    gl = srgb_to_linear(g / 255.0)
    bl = srgb_to_linear(b / 255.0)
    # sRGB D65 matrix
    x = rl * 0.4124564 + gl * 0.3575761 + bl * 0.1804375
    y = rl * 0.2126729 + gl * 0.7151522 + bl * 0.0721750
    z = rl * 0.0193339 + gl * 0.1191920 + bl * 0.9503041
    return x * 100.0, y * 100.0, z * 100.0


def xyz_to_lab(x: float, y: float, z: float) -> tuple[float, float, float]:
    """XYZ → CIE Lab (D65 reference white)."""
    # D65 white point
    xn, yn, zn = 95.0489, 100.0, 108.8840
    fx = _lab_f(x / xn)
    fy = _lab_f(y / yn)
    fz = _lab_f(z / zn)
    L = 116.0 * fy - 16.0
    a = 500.0 * (fx - fy)
    b = 200.0 * (fy - fz)
    return L, a, b


def _lab_f(t: float) -> float:
    if t > (6.0 / 29.0) ** 3:
        return t ** (1.0 / 3.0)
    return t / (3.0 * (6.0 / 29.0) ** 2) + 4.0 / 29.0


def rgb_to_lab(r: int, g: int, b: int) -> tuple[float, float, float]:
    return xyz_to_lab(*rgb_to_xyz(r, g, b))


def delta_e_cie76(c1: tuple[int, int, int], c2: tuple[int, int, int]) -> float:
    """Euclidean distance in Lab space — CIE 1976 formula."""
    L1, a1, b1 = rgb_to_lab(*c1)
    L2, a2, b2 = rgb_to_lab(*c2)
    return math.sqrt((L1 - L2) ** 2 + (a1 - a2) ** 2 + (b1 - b2) ** 2)


def delta_e_cie94(c1: tuple[int, int, int], c2: tuple[int, int, int]) -> float:
    """CIE 1994 deltaE (graphic-arts weighting)."""
    L1, a1, b1 = rgb_to_lab(*c1)
    L2, a2, b2 = rgb_to_lab(*c2)
    dL = L1 - L2
    da = a1 - a2
    db = b1 - b2
    C1 = math.sqrt(a1 * a1 + b1 * b1)
    C2 = math.sqrt(a2 * a2 + b2 * b2)
    dC = C1 - C2
    dH_sq = da * da + db * db - dC * dC
    dH = math.sqrt(max(0.0, dH_sq))
    SL, SC, SH = 1.0, 1.0 + 0.045 * C1, 1.0 + 0.015 * C1
    return math.sqrt((dL / SL) ** 2 + (dC / SC) ** 2 + (dH / SH) ** 2)


def delta_e_ciede2000(c1: tuple[int, int, int], c2: tuple[int, int, int]) -> float:
    """CIEDE2000 — most accurate but most complex."""
    L1, a1, b1 = rgb_to_lab(*c1)
    L2, a2, b2 = rgb_to_lab(*c2)
    avg_L = (L1 + L2) / 2.0
    C1 = math.sqrt(a1 * a1 + b1 * b1)
    C2 = math.sqrt(a2 * a2 + b2 * b2)
    avg_C = (C1 + C2) / 2.0
    G = 0.5 * (1 - math.sqrt(avg_C ** 7 / (avg_C ** 7 + 25.0 ** 7)))
    a1p = (1 + G) * a1
    a2p = (1 + G) * a2
    C1p = math.sqrt(a1p ** 2 + b1 ** 2)
    C2p = math.sqrt(a2p ** 2 + b2 ** 2)
    avg_Cp = (C1p + C2p) / 2.0
    h1p = math.degrees(math.atan2(b1, a1p)) % 360
    h2p = math.degrees(math.atan2(b2, a2p)) % 360
    if abs(h1p - h2p) > 180:
        avg_hp = (h1p + h2p + 360) / 2.0
    else:
        avg_hp = (h1p + h2p) / 2.0
    T = (1 - 0.17 * math.cos(math.radians(avg_hp - 30))
         + 0.24 * math.cos(math.radians(2 * avg_hp))
         + 0.32 * math.cos(math.radians(3 * avg_hp + 6))
         - 0.20 * math.cos(math.radians(4 * avg_hp - 63)))
    dhp = h2p - h1p
    if abs(dhp) > 180:
        dhp += 360 if dhp < 0 else -360
    dLp = L2 - L1
    dCp = C2p - C1p
    dHp = 2 * math.sqrt(C1p * C2p) * math.sin(math.radians(dhp / 2.0))
    SL = 1 + (0.015 * (avg_L - 50) ** 2) / math.sqrt(20 + (avg_L - 50) ** 2)
    SC = 1 + 0.045 * avg_Cp
    SH = 1 + 0.015 * avg_Cp * T
    delta_theta = 30 * math.exp(-((avg_hp - 275) / 25) ** 2)
    RC = 2 * math.sqrt(avg_Cp ** 7 / (avg_Cp ** 7 + 25.0 ** 7))
    RT = -RC * math.sin(math.radians(2 * delta_theta))
    return math.sqrt((dLp / SL) ** 2 + (dCp / SC) ** 2 + (dHp / SH) ** 2
                     + RT * (dCp / SC) * (dHp / SH))


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        die(1, f"usage: {Path(argv[0]).name} <color1> <color2> [--method cie76|cie94|ciede2000]")

    method = "cie76"
    if "--method" in argv:
        i = argv.index("--method")
        if i + 1 >= len(argv):
            die(1, "--method requires an argument")
        method = argv[i + 1]

    c1 = parse_color(argv[1])
    c2 = parse_color(argv[2])

    if method == "cie76":
        result = delta_e_cie76(c1, c2)
    elif method == "cie94":
        result = delta_e_cie94(c1, c2)
    elif method == "ciede2000":
        result = delta_e_ciede2000(c1, c2)
    else:
        die(2, f"unsupported --method: {method!r} (use cie76|cie94|ciede2000)")
        return 2

    print(f"{result:.2f}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
