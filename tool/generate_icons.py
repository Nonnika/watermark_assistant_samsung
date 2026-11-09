"""Generate every launcher / in-app icon asset from one raster source.

Usage (from the project root, needs Pillow + numpy):

    python3 tool/generate_icons.py [assets/app_icon_source.png]

The source is a square render of the icon sitting on a light backdrop. The
squircle is cropped out, re-masked with a clean analytic superellipse (so the
backdrop and its drop shadow never leak into the edge), and exported as:

- assets/logo/app_icon.png                     512px, transparent corners (in-app)
- android/.../mipmap-*/ic_launcher_oneui.png   legacy launcher icons
- android/.../drawable-xxxhdpi/ic_launcher_oneui_background.png
                                               full-bleed 108dp adaptive layer
"""

import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "android/app/src/main/res"

# Squircle bounds inside the source image (left, top, right, bottom) and the
# superellipse exponent fitted to its outline.
CROP_BOX = (137, 127, 1117, 1099)
EXPONENT = 3.75
WORK = 2048  # working resolution of the cropped squircle

# Adaptive icon: the artwork squircle spans this many dp of the 108dp layer.
# Launcher masks show the central 72dp, so the drawn edge stays hidden while
# the photo and sparkle remain inside the 66dp safe zone.
ADAPTIVE_ART_DP = 76

DENSITIES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}


def superellipse_mask(size: int, art: int, scale: float, ss: int = 4) -> np.ndarray:
    """Antialiased coverage of a superellipse of `art` px centered in `size` px."""
    n = size * ss
    coords = (np.arange(n) + 0.5) / ss - size / 2
    r = art / 2 * scale
    u = np.abs(coords / r) ** EXPONENT
    inside = (u[None, :] + u[:, None]) <= 1
    return inside.reshape(size, ss, size, ss).mean(axis=(1, 3))


def push_pull(rgb: np.ndarray, weight: np.ndarray) -> np.ndarray:
    """Fill pixels with weight 0 by smoothly extending the known colors."""
    if min(weight.shape) <= 1:
        w = weight.sum()
        mean = (rgb * weight[..., None]).sum((0, 1)) / max(w, 1e-6)
        return np.broadcast_to(mean, rgb.shape).copy()
    h, w = weight.shape
    ph, pw = h + h % 2, w + w % 2
    rgb_p = np.pad(rgb * weight[..., None], ((0, ph - h), (0, pw - w), (0, 0)))
    w_p = np.pad(weight, ((0, ph - h), (0, pw - w)))
    w_small = w_p.reshape(ph // 2, 2, pw // 2, 2).sum((1, 3))
    rgb_small = rgb_p.reshape(ph // 2, 2, pw // 2, 2, 3).sum((1, 3))
    known = w_small > 0
    rgb_small[known] /= w_small[known][:, None]
    coarse = push_pull(rgb_small, np.minimum(w_small, 1))
    up = np.stack(
        [
            np.asarray(
                Image.fromarray(coarse[..., c].astype(np.float32), "F").resize(
                    (pw, ph), Image.BILINEAR
                )
            )
            for c in range(3)
        ],
        axis=-1,
    )[:h, :w]
    a = np.clip(weight, 0, 1)[..., None]
    return rgb * a + up * (1 - a)


def save(arr: np.ndarray, path: Path, size: int) -> None:
    img = Image.fromarray(np.clip(arr + 0.5, 0, 255).astype(np.uint8))
    if img.width != size:
        img = img.resize((size, size), Image.LANCZOS)
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, optimize=True)
    print(f"Generated {path.relative_to(ROOT)} ({size} x {size})")


def main() -> None:
    source = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "assets/app_icon_source.png"
    art = (
        Image.open(source)
        .convert("RGB")
        .crop(CROP_BOX)
        .resize((WORK, WORK), Image.LANCZOS)
    )
    art = np.asarray(art).astype(np.float32)

    # Trust only pixels safely inside the outline; everything else (the
    # antialiased rim mixed with the backdrop) is re-extended from inside.
    trusted = superellipse_mask(WORK, WORK, 0.988) >= 1
    canvas = round(WORK * 108 / ADAPTIVE_ART_DP)
    pad = (canvas - WORK) // 2
    big_rgb = np.zeros((canvas, canvas, 3), np.float32)
    big_w = np.zeros((canvas, canvas), np.float32)
    big_rgb[pad : pad + WORK, pad : pad + WORK] = art
    big_w[pad : pad + WORK, pad : pad + WORK] = trusted
    full_bleed = push_pull(big_rgb, big_w)

    # Adaptive background layer (foreground is transparent).
    save(full_bleed, RES / "drawable-xxxhdpi/ic_launcher_oneui_background.png", 432)

    # Masked squircle with transparent corners.
    squircle = full_bleed[pad : pad + WORK, pad : pad + WORK]
    alpha = superellipse_mask(WORK, WORK, 0.996) * 255
    rgba = np.concatenate([squircle, alpha[..., None]], axis=-1)
    save(rgba, ROOT / "assets/logo/app_icon.png", 512)
    for name, px in DENSITIES.items():
        save(rgba, RES / f"mipmap-{name}/ic_launcher_oneui.png", px)


if __name__ == "__main__":
    main()
