#!/usr/bin/env python3
"""Turns a clean render into the cover: crushed to black, the face warped and the jaw
dragged long, ghost exposures, torn scanlines, a split that bleeds red, melting drips,
pinprick eyes, film damage.

  python3 tools/monster-lab/distort.py <in.png> <out.png> [size]
"""
import sys
import numpy as np
from PIL import Image, ImageFilter


def sample(img, sx, sy):
    """Bilinear sample of a (h, w) or (h, w, c) float image at float coords."""
    h, w = img.shape[:2]
    sx = np.clip(sx, 0, w - 1.001)
    sy = np.clip(sy, 0, h - 1.001)
    x0 = np.floor(sx).astype(int)
    y0 = np.floor(sy).astype(int)
    fx = sx - x0
    fy = sy - y0
    if img.ndim == 3:
        fx = fx[..., None]
        fy = fy[..., None]
    a = img[y0, x0] * (1 - fx) + img[y0, x0 + 1] * fx
    b = img[y0 + 1, x0] * (1 - fx) + img[y0 + 1, x0 + 1] * fx
    return a * (1 - fy) + b * fy


def distort(src, size=1024, seed=13):
    rng = np.random.default_rng(seed)
    im = Image.open(src).convert("L").resize((size, size), Image.LANCZOS)
    g = np.asarray(im).astype(np.float32) / 255
    g = np.clip((g - 0.05) / 0.8, 0, 1)
    h, w = g.shape
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    # the face sits a little above the middle
    fx, fy = 0.5 * w, 0.44 * h
    dx, dy = xx - fx, yy - fy
    r = np.sqrt(dx * dx + dy * dy) / w

    # 0. pinprick eyes in the empty sockets (slightly mismatched); drawn first so the
    #    warp drags them along with the face
    for ex, ey, rr in ((0.416, 0.414, 3.0), (0.576, 0.414, 2.4)):
        d = np.sqrt((xx - ex * w) ** 2 + (yy - ey * h) ** 2)
        g = np.maximum(g, np.exp(-(d / rr) ** 2) * 1.2 + np.exp(-(d / (rr * 5)) ** 2) * 0.2)

    # 1. warp: a slow twist around the face, a ripple through everything, and the jaw
    #    dragged downward like it's still opening
    twist = 0.2 * np.exp(-(r / 0.3) ** 2)
    ang = np.arctan2(dy, dx) + twist
    rad = np.sqrt(dx * dx + dy * dy)
    sx = fx + np.cos(ang) * rad + 5 * np.sin(yy * 0.045) + 2 * np.sin(yy * 0.31)
    sy = fy + np.sin(ang) * rad
    jaw = np.clip((yy / h - 0.5) / 0.28, 0, 1)
    jaw_x = np.exp(-((xx - fx) / (0.11 * w)) ** 2)
    sy = sy - jaw * jaw_x * 0.11 * h * (1 - jaw * 0.5)
    g = sample(g, sx, sy)

    # 2. crush it: the hall falls into black, the bone stays
    g = np.clip((g - 0.07) / 0.93, 0, 1) ** 1.55
    light = np.exp(-(r / 0.3) ** 2)
    g *= 0.12 + 0.88 * light

    # 3. ghosts: two faint copies, as if it moved while the shutter was open
    for off, k in ((-17, 0.22), (23, 0.14)):
        g = np.maximum(g, np.roll(g, off, axis=1) * k + g * (1 - k) * 0.0)
        g = g * (1 - k * 0.3) + np.roll(g, off, axis=1) * k * 0.3

    # 4. melt: columns drip downward below the face
    drip = np.zeros(w, np.float32)
    for _ in range(60):
        c = int(rng.integers(0, w))
        width = int(rng.integers(2, 9))
        drip[max(0, c - width):c + width] = np.maximum(drip[max(0, c - width):c + width], rng.uniform(20, 120))
    drip = np.convolve(drip, np.ones(5) / 5, mode="same")
    below = np.clip((yy / h - 0.55) / 0.45, 0, 1)
    g = np.maximum(g, sample(g, xx, yy - drip[None, :] * below) * 0.9)

    # 6. colour: grey, but the red channel slips off the edges like it's bleeding
    rgb = np.stack([np.maximum(g, np.roll(g, 8, axis=1) * 0.9), g * 0.93, g * 0.95], -1)
    rgb = np.clip(rgb, 0, 1)

    # 7. torn scanlines: bands of rows shoved sideways (mostly away from the eyes)
    for _ in range(14):
        y0 = int(rng.integers(0, h))
        if abs(y0 - 0.414 * h) < 30:
            continue
        band = int(rng.integers(2, 22))
        shift = int(rng.normal(0, 34))
        rgb[y0:y0 + band] = np.roll(rgb[y0:y0 + band], shift, axis=1)
        if rng.random() < 0.3:
            rgb[y0:y0 + band] *= rng.uniform(0.2, 0.6)
    rgb[::3] *= 0.86  # scanlines

    # 8. film damage: grain, scratches, dust, a heavy vignette
    rgb += rng.normal(0, 0.045, (h, w, 1))
    for _ in range(7):
        x = rng.integers(0, w)
        rgb[:, x:x + 1] = np.clip(rgb[:, x:x + 1] + rng.uniform(0.08, 0.25), 0, 1)
    for _ in range(140):
        x, y = rng.integers(0, w), rng.integers(0, h)
        s = rng.integers(1, 4)
        rgb[y:y + s, x:x + s] = 0 if rng.random() < 0.6 else 0.8
    vig = 1 - 0.97 * np.clip(r * 1.7 - 0.2, 0, 1) ** 1.2
    rgb *= vig[..., None]
    out = Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8))
    return out.filter(ImageFilter.UnsharpMask(radius=2, percent=60, threshold=2))


if __name__ == "__main__":
    size = int(sys.argv[3]) if len(sys.argv) > 3 else 1024
    distort(sys.argv[1], size).save(sys.argv[2])
    print("wrote", sys.argv[2])
