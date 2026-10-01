# Approximates each night's in-game ColorCorrection (saturation + tint + contrast).
from PIL import Image, ImageEnhance
import numpy as np
GRADE = {
    "house": (-1.0, (255, 255, 255), 0.22),
    "ward": (-0.25, (255, 175, 175), 0.3),
    "sewer": (-0.45, (185, 255, 225), 0.25),
    "atrium": (-0.55, (210, 225, 255), 0.12),
    "void": (-0.15, (225, 175, 255), 0.35),
}
def grade(im, mood):
    sat, tint, contrast = GRADE[mood]
    im = ImageEnhance.Color(im.convert("RGB")).enhance(1 + sat)
    a = np.asarray(im).astype(np.float32) / 255
    a = a * (np.array(tint, np.float32) / 255)
    a = np.clip((a - 0.5) * (1 + contrast * 0.6) + 0.5, 0, 1)
    return Image.fromarray((a * 255).astype(np.uint8))
