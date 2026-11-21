"""Prepares the trail ground scans (Poly Haven, CC0) for world/ground.gdshader.

    python prep_trail_textures.py <folder with the 4k downloads> <godot/assets/textures/trail>

Per scan <id> (files <id>_diff_4k.jpg, <id>_nor_gl_4k.jpg, <id>_rough_4k.jpg) it writes
  <id>_col.jpg  the colour as a RATIO to the scan's own mean (x 0.5, sRGB): the shader multiplies the biome's
                trail colour by it, so every biome keeps its colour and gets the scan's detail. The scan's slow
                light / dark drifts (anything wider than ~1/6 of the tile) are flattened out: those are what the
                eye picks up as a repeating tile. Half desaturated, so stones keep a little of their own hue.
  <id>_nr.jpg   normal x, y (OpenGL) in R, G and roughness in B
"""
import sys, os
import numpy as np
from PIL import Image

Image.MAX_IMAGE_PIXELS = None
IDS = ["brown_mud_02", "brown_mud_03", "rocky_trail", "gravelly_sand"]


def lowpass(a, sigma_frac):
    """wrap-around Gaussian blur (the scans tile), sigma as a fraction of the image"""
    h, w = a.shape[:2]
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.rfftfreq(w)[None, :]
    g = np.exp(-2.0 * (np.pi ** 2) * ((fy * h * sigma_frac) ** 2 + (fx * w * sigma_frac) ** 2))
    if a.ndim == 2:
        return np.fft.irfft2(np.fft.rfft2(a) * g, s=(h, w))
    return np.stack([np.fft.irfft2(np.fft.rfft2(a[..., c]) * g, s=(h, w)) for c in range(a.shape[2])], axis=-1)


def srgb_to_lin(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def lin_to_srgb(c):
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(np.maximum(c, 1e-9), 1 / 2.4) - 0.055)


def main(src, dst):
    os.makedirs(dst, exist_ok=True)
    for i in IDS:
        d = np.asarray(Image.open(os.path.join(src, i + "_diff_4k.jpg")).convert("RGB"), dtype=np.float32) / 255.0
        lin = srgb_to_lin(d)
        lum = lin @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
        slow = np.maximum(lowpass(lum, 1.0 / 6.0), 1e-4)
        lin = lin * (lum.mean() / slow)[..., None]
        ratio = lin / lin.reshape(-1, 3).mean(axis=0)
        grey = (ratio @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32))[..., None]
        ratio = grey + (ratio - grey) * 0.5
        ratio /= ratio.reshape(-1, 3).mean(axis=0)
        col = lin_to_srgb(np.clip(ratio * 0.5, 0, 1))
        Image.fromarray((col * 255 + 0.5).astype(np.uint8)).save(os.path.join(dst, i + "_col.jpg"), quality=90, subsampling=0)

        n = np.asarray(Image.open(os.path.join(src, i + "_nor_gl_4k.jpg")).convert("RGB"), dtype=np.uint8)
        r = np.asarray(Image.open(os.path.join(src, i + "_rough_4k.jpg")).convert("L"), dtype=np.float32) / 255.0
        r = np.clip(r - lowpass(r, 1.0 / 6.0) + r.mean(), 0, 1)
        nr = np.dstack([n[..., 0], n[..., 1], (r * 255 + 0.5).astype(np.uint8)])
        Image.fromarray(nr).save(os.path.join(dst, i + "_nr.jpg"), quality=92, subsampling=0)
        print(i, "mean rough %.3f" % r.mean(), "ratio p1/p99 %.2f %.2f" % tuple(np.percentile(grey, [1, 99])))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
