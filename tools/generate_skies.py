"""Paints the official sky panoramas (original, procedural) into assets/skies/.

Each sky is a 4096 x 2048 equirectangular image: column 0.5 faces north (-Z), 0.75 east (+X),
the top row is straight up. The sun or moon is NOT painted: the sky shader
(src/maps/map_sky.gdshader) draws it where the map's lighting puts it, with its glow, so a sky
can be used with any sun direction.

Run:  python tools/generate_skies.py [sky_id ...]
Needs numpy and Pillow. Deterministic: the same seed always paints the same sky.
"""
from __future__ import annotations

import math
import os
import sys

import numpy as np
from PIL import Image

W, H = 4096, 2048
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "skies")

# ---------------------------------------------------------------------------------------------
# Geometry: per-pixel azimuth (0 = north, + toward east) and elevation, and the view direction.
u = (np.arange(W) + 0.5) / W
v = (np.arange(H) + 0.5) / H
AZ = ((u - 0.5) * 2.0 * math.pi)[None, :].repeat(H, 0)
EL = ((0.5 - v) * math.pi)[:, None].repeat(W, 1)
DX = np.cos(EL) * np.sin(AZ)
DY = np.sin(EL)
DZ = -np.cos(EL) * np.cos(AZ)
EL_DEG = np.degrees(EL)


def srgb_to_linear(c: np.ndarray) -> np.ndarray:
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(c: np.ndarray) -> np.ndarray:
    c = np.clip(c, 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1 / 2.4) - 0.055)


def col(hex_str: str) -> np.ndarray:
    rgb = np.array([int(hex_str[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])
    return srgb_to_linear(rgb)


def mix(a: np.ndarray, b: np.ndarray, t: np.ndarray) -> np.ndarray:
    t = np.asarray(t)[..., None] if np.ndim(t) else t
    return a * (1 - t) + b * t


def smooth(e0: float, e1: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


# ---------------------------------------------------------------------------------------------
# Noise: hashed value noise and fBm, evaluated at arbitrary float coordinates.

def _hash(ix: np.ndarray, iy: np.ndarray, seed: int) -> np.ndarray:
    h = (ix.astype(np.int64) * 374761393 + iy.astype(np.int64) * 668265263 + seed * 2246822519) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    h = h ^ (h >> 16)
    return (h & 0xFFFFFF).astype(np.float64) / float(0xFFFFFF)


def value_noise(x: np.ndarray, y: np.ndarray, seed: int, period: int = 0) -> np.ndarray:
    x0 = np.floor(x)
    y0 = np.floor(y)
    fx = x - x0
    fy = y - y0
    fx = fx * fx * (3 - 2 * fx)
    fy = fy * fy * (3 - 2 * fy)
    ix = x0.astype(np.int64)
    iy = y0.astype(np.int64)
    ix1 = ix + 1
    if period:
        ix = np.mod(ix, period)
        ix1 = np.mod(ix1, period)
    a = _hash(ix, iy, seed)
    b = _hash(ix1, iy, seed)
    c = _hash(ix, iy + 1, seed)
    d = _hash(ix1, iy + 1, seed)
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def fbm(x: np.ndarray, y: np.ndarray, seed: int, octaves: int = 5, lacunarity: float = 2.0,
        gain: float = 0.5, period: int = 0) -> np.ndarray:
    total = np.zeros_like(x)
    amp = 1.0
    norm = 0.0
    freq = 1.0
    for o in range(octaves):
        p = int(period * freq) if period else 0
        total += amp * value_noise(x * freq, y * freq, seed + o * 101, p)
        norm += amp
        amp *= gain
        freq *= lacunarity
    return total / norm


def ridge(az: np.ndarray, seed: int, base: float, amp: float, rough: float = 1.0) -> np.ndarray:
    """A periodic horizon profile in degrees of elevation (integer harmonics wrap around)."""
    rng = np.random.default_rng(seed)
    h = np.full_like(az, base)
    for k in range(1, 48):
        a = amp * rng.normal() / (k ** (1.25 / rough))
        h += a * np.sin(k * az + rng.uniform(0, 2 * math.pi))
    return h


def horizon_profile(seed: int, base: float, amp: float, rough: float = 1.0) -> np.ndarray:
    """Profile per column (1-D), so silhouettes can be tested against EL_DEG."""
    return ridge(AZ[0], seed, base, amp, rough)[None, :]


# ---------------------------------------------------------------------------------------------
# Layers

def gradient(zenith: str, mid: str, horizon: str, ground: str, mid_at: float = 22.0) -> np.ndarray:
    z, m, h, g = col(zenith), col(mid), col(horizon), col(ground)
    up = np.clip(EL_DEG, 0, 90)
    low = mix(h, m, smooth(0.0, mid_at, up))
    sky = mix(low, z, smooth(mid_at, 90.0, up))
    below = mix(h, g, smooth(0.0, -12.0, EL_DEG))
    return np.where((EL_DEG >= 0)[..., None], sky, below)


def cloud_layer(img: np.ndarray, seed: int, scale: float, coverage: float, softness: float,
                lit: str, shade: str, height: float = 1.0, stretch: float = 1.0,
                opacity: float = 1.0, horizon_fade: float = 4.0, octaves: int = 6,
                drift: tuple[float, float] = (0.0, 0.0)) -> np.ndarray:
    """A cloud deck seen in perspective: noise on a plane above the viewer."""
    up = np.maximum(DY, 0.0)
    t = height / (up + 0.035)
    px = DX * t * scale * stretch + drift[0]
    pz = DZ * t * scale + drift[1]
    n = fbm(px, pz, seed, octaves)
    density = smooth(coverage, coverage + softness, n)
    # Thicker cloud is darker underneath; a second sample offset gives fake depth.
    n2 = fbm(px + 0.35, pz + 0.22, seed + 7, 4)
    body = np.clip((n - coverage) * 2.2 + (n2 - 0.5) * 0.6, 0, 1)
    colour = mix(col(lit), col(shade), body)
    alpha = density * smooth(0.0, horizon_fade, EL_DEG) * opacity
    return mix(img, colour, alpha)


def haze_band(img: np.ndarray, colour: str, width: float, strength: float) -> np.ndarray:
    a = np.exp(-np.abs(EL_DEG) / width) * strength
    return mix(img, col(colour), a)


def silhouette(img: np.ndarray, profile: np.ndarray, colour: str, top_colour: str | None = None,
               floor: float = -90.0) -> np.ndarray:
    mask = (EL_DEG <= profile) & (EL_DEG >= floor)
    c = col(colour)
    if top_colour is not None:
        # Lighter toward the ridge line, as distant land catches the haze.
        t = smooth(-2.0, 0.0, EL_DEG - profile)
        fill = mix(c, col(top_colour), t)
    else:
        fill = np.broadcast_to(c, img.shape)
    return np.where(mask[..., None], fill, img)


def stars(img: np.ndarray, seed: int, count: int, brightness: float, min_el: float = 4.0,
          band: tuple[float, float, float] | None = None) -> np.ndarray:
    rng = np.random.default_rng(seed)
    acc = np.zeros((H, W), np.float64)
    tints = np.zeros((H, W, 3), np.float64)
    # Directions uniform on the upper hemisphere (sin(el) uniform).
    n = count
    s = rng.uniform(math.sin(math.radians(min_el)), 1.0, n)
    el = np.arcsin(s)
    az = rng.uniform(-math.pi, math.pi, n)
    mag = rng.pareto(2.2, n) + 1.0
    mag = np.minimum(mag, 14.0)
    if band is not None:
        # Extra faint stars concentrated along the galactic band.
        bx, by, bz = band
        extra = count * 2
        s2 = rng.uniform(math.sin(math.radians(min_el)), 1.0, extra * 3)
        e2 = np.arcsin(s2)
        a2 = rng.uniform(-math.pi, math.pi, extra * 3)
        d = np.abs(np.cos(e2) * np.sin(a2) * bx + np.sin(e2) * by - np.cos(e2) * np.cos(a2) * bz)
        keep = rng.uniform(0, 1, extra * 3) < np.exp(-(d / 0.18) ** 2)
        el = np.concatenate([el, e2[keep][:extra]])
        az = np.concatenate([az, a2[keep][:extra]])
        mag = np.concatenate([mag, np.full(min(extra, int(keep.sum())), 1.0) * rng.uniform(0.4, 1.0, min(extra, int(keep.sum())))])
    x = (az / (2 * math.pi) + 0.5) * W
    y = (0.5 - el / math.pi) * H
    temp = rng.uniform(0, 1, len(x))
    tint = np.stack([0.85 + 0.3 * temp, 0.9 + 0.05 * temp, 1.15 - 0.35 * temp], 1)
    # Stretch the footprint horizontally with latitude so stars stay round.
    stretch = 1.0 / np.maximum(np.cos(el), 0.05)
    for dx in range(-3, 4):
        for dy in range(-2, 3):
            xi = np.floor(x).astype(int) + dx
            yi = np.floor(y).astype(int) + dy
            fx = (xi + 0.5 - x) / np.minimum(stretch, 6.0)
            fy = yi + 0.5 - y
            r2 = fx * fx + fy * fy
            sigma = 0.42 + 0.12 * np.log(mag)
            w = mag * np.exp(-r2 / (2 * sigma * sigma))
            ok = (yi >= 0) & (yi < H) & (w > 1e-4)
            np.add.at(acc, (yi[ok], np.mod(xi[ok], W)), w[ok])
            for ch in range(3):
                np.add.at(tints[..., ch], (yi[ok], np.mod(xi[ok], W)), w[ok] * tint[ok, ch])
    light = tints * brightness * 0.06
    fade = smooth(min_el - 2, min_el + 8, EL_DEG)[..., None]
    return img + light * fade


def milky_way(img: np.ndarray, seed: int, normal: tuple[float, float, float], strength: float) -> np.ndarray:
    nx, ny, nz = normal
    d = DX * nx + DY * ny + DZ * nz
    band = np.exp(-(d / 0.16) ** 2)
    n = fbm(DX * 6 + 11, DZ * 6 + DY * 4, seed, 6)
    dust = fbm(DX * 14 - 3, DZ * 14 + DY * 9, seed + 3, 5)
    glow = band * smooth(0.35, 0.8, n) * (1.0 - 0.75 * smooth(0.5, 0.7, dust) * band)
    tint = mix(col("9aa8d0"), col("e8d8c0"), n)
    return img + tint * (glow * strength * smooth(2, 15, EL_DEG))[..., None]


def finish(img: np.ndarray, name: str, seed: int) -> None:
    rng = np.random.default_rng(seed + 999)
    out = linear_to_srgb(img)
    # Dither half a step so long gradients do not band.
    out = out * 255.0 + rng.uniform(-0.5, 0.5, out.shape)
    data = np.clip(np.round(out), 0, 255).astype(np.uint8)
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".webp")
    Image.fromarray(data, "RGB").save(path, "WEBP", quality=92, method=6)
    print(f"{name}: {os.path.getsize(path) // 1024} KiB")


# ---------------------------------------------------------------------------------------------
# The skies

def hazy_noon() -> np.ndarray:
    """Kilnmarket: a hot, pale noon over dry terracotta hills, high cirrus, kiln smoke."""
    img = gradient("4f86c4", "86aed6", "e8dcc4", "8c7258", 26)
    img = cloud_layer(img, 11, 0.9, 0.62, 0.22, "f6f2ea", "d8d4cc", stretch=4.0, opacity=0.55,
                      octaves=7, horizon_fade=8)
    img = cloud_layer(img, 12, 2.4, 0.66, 0.12, "fbf8f2", "e2dcd2", opacity=0.35, horizon_fade=10)
    img = haze_band(img, "efe2c8", 5.0, 0.55)
    img = silhouette(img, horizon_profile(21, 1.6, 2.2, 0.8), "b49272", "d6bfa0")
    img = silhouette(img, horizon_profile(22, 0.6, 1.4, 1.2), "8e6a4c", "b08868")
    # Kiln chimneys with drifting smoke on the far hills.
    rng = np.random.default_rng(23)
    for _ in range(9):
        a = rng.uniform(-math.pi, math.pi)
        width = rng.uniform(0.0016, 0.0026)
        top = rng.uniform(2.8, 4.4)
        da = np.angle(np.exp(1j * (AZ - a)))
        stack = (np.abs(da) < width) & (EL_DEG < top) & (EL_DEG > -1)
        img = np.where(stack[..., None], col("6a5040"), img)
        lean = (EL_DEG - top) * 0.004
        plume = np.exp(-((da - lean) / (0.004 + (EL_DEG - top) * 0.0018)) ** 2)
        plume *= smooth(top, top + 0.4, EL_DEG) * (1 - smooth(top + 2, top + 9, EL_DEG))
        img = mix(img, col("cfc6ba"), plume * 0.5 * fbm(AZ * 300, EL_DEG * 2, 24, 3))
    return img


def overcast_works() -> np.ndarray:
    """Switchyard: a low grey deck over an industrial plain: cooling towers, stacks, pylons."""
    img = gradient("6b7684", "8a94a0", "b6bcc2", "4a4e52", 18)
    img = cloud_layer(img, 31, 0.55, 0.38, 0.35, "c4c9cf", "6c737c", opacity=0.95, octaves=7,
                      horizon_fade=3)
    img = cloud_layer(img, 32, 1.6, 0.52, 0.2, "d6dade", "8a9098", opacity=0.45, horizon_fade=3)
    img = haze_band(img, "b8bec4", 3.0, 0.6)
    img = silhouette(img, horizon_profile(33, 0.5, 0.6, 0.7), "7c848c")
    rng = np.random.default_rng(34)
    # Cooling towers (hyperboloid outline), chimneys and lattice pylons.
    for _ in range(5):
        a = rng.uniform(-math.pi, math.pi)
        hgt = rng.uniform(3.0, 4.6)
        base = rng.uniform(0.020, 0.028)
        da = np.angle(np.exp(1j * (AZ - a)))
        t = np.clip(EL_DEG / hgt, 0, 1)
        half = base * (1 - 0.38 * np.sin(t * math.pi * 0.82))
        tower = (np.abs(da) < half) & (EL_DEG < hgt) & (EL_DEG > -1)
        img = np.where(tower[..., None], mix(col("6a7078"), col("8a9098"), (da / base + 1) * 0.5), img)
        steam = np.exp(-(da / (base * 0.9 + (EL_DEG - hgt) * 0.004)) ** 2)
        steam *= smooth(hgt, hgt + 0.5, EL_DEG) * (1 - smooth(hgt + 3, hgt + 14, EL_DEG))
        img = mix(img, col("dfe2e6"), steam * 0.75 * fbm(AZ * 120, EL_DEG * 1.5, 35, 4))
    for _ in range(7):
        a = rng.uniform(-math.pi, math.pi)
        da = np.angle(np.exp(1j * (AZ - a)))
        top = rng.uniform(4.0, 6.5)
        stack = (np.abs(da) < 0.0022) & (EL_DEG < top) & (EL_DEG > -1)
        img = np.where(stack[..., None], col("5a5f66"), img)
        band = stack & (np.abs(EL_DEG - top + 0.5) < 0.12)
        img = np.where(band[..., None], col("9a4a3c"), img)
    pylon_az = np.linspace(-math.pi, math.pi, 23, endpoint=False) + 0.07
    for a in pylon_az:
        da = np.angle(np.exp(1j * (AZ - a)))
        hgt = 1.6 + 0.3 * math.sin(a * 3)
        t = np.clip(EL_DEG / hgt, 0, 1)
        leg = (np.abs(np.abs(da) - 0.004 * (1 - t)) < 0.0006) & (EL_DEG < hgt) & (EL_DEG > -0.5)
        arm = (np.abs(da) < 0.006) & (np.abs(EL_DEG - hgt * 0.8) < 0.05)
        img = np.where((leg | arm)[..., None], col("4c5056"), img)
    return img


def harbour_fair() -> np.ndarray:
    """Cluts: a bright maritime sky with fair-weather cumulus over open water and a far coast."""
    img = gradient("2f6fb8", "64a0d8", "cfe2ee", "2f5f78", 20)
    img = cloud_layer(img, 41, 1.3, 0.58, 0.12, "ffffff", "aab8c8", opacity=1.0, octaves=6,
                      horizon_fade=2.5)
    img = cloud_layer(img, 42, 0.6, 0.7, 0.2, "f4f8fc", "d0dae4", stretch=3.0, opacity=0.4,
                      horizon_fade=6)
    img = haze_band(img, "d8e6ee", 2.5, 0.5)
    # A low headland and a lighthouse far across the water.
    coast = horizon_profile(43, -0.4, 1.3, 0.9)
    coast = np.where(np.abs(np.angle(np.exp(1j * (AZ[0:1] - 2.2)))) < 1.3, coast, -5.0)
    img = silhouette(img, coast, "6f8a96", "9fb6c0", floor=-0.05)
    da = np.angle(np.exp(1j * (AZ - 2.55)))
    house = (np.abs(da) < 0.0016) & (EL_DEG < 1.9) & (EL_DEG > 0.4)
    img = np.where(house[..., None], col("e8e4dc"), img)
    # The sea below the horizon: darker with distance, with glittering ripples.
    sea = EL_DEG < 0
    depth = smooth(0.0, -25.0, EL_DEG)
    ripples = fbm(DX / (np.abs(DY) + 0.02) * 9, DZ / (np.abs(DY) + 0.02) * 2.2, 44, 4)
    water = mix(col("8fb0c4"), col("1e4a64"), depth)
    water = water * (0.85 + 0.3 * ripples)[..., None]
    img = np.where(sea[..., None], water, img)
    return img


def city_dusk() -> np.ndarray:
    """Rooftops: dusk seen from the top of a tower: glowing horizon, towers, the lit city below."""
    img = gradient("1d2550", "4a4f86", "f0a070", "141828", 16)
    # Warm band low on the horizon all round (the shader adds more toward the sun).
    img = haze_band(img, "ffb27a", 4.5, 0.55)
    img = cloud_layer(img, 51, 0.8, 0.6, 0.18, "ffb890", "5a4a70", stretch=3.5, opacity=0.8,
                      octaves=6, horizon_fade=3)
    img = stars(img, 52, 500, 0.6, min_el=35)
    # The city below the horizon: a dark plain receding into haze, streets of light in perspective.
    below = EL_DEG < 0
    gx = DX / (np.abs(DY) + 0.004)
    gz = DZ / (np.abs(DY) + 0.004)
    street = np.maximum(np.exp(-((np.mod(gx * 2.0, 1.0) - 0.5) / 0.02) ** 2),
                        np.exp(-((np.mod(gz * 2.0 + 0.37 * np.floor(gx * 2.0), 1.0) - 0.5) / 0.02) ** 2))
    grain = fbm(gx * 3.0, gz * 3.0, 53, 4)
    # Streets only light up where the city is dense; scattered windows fill the blocks.
    dense = smooth(0.42, 0.62, fbm(gx * 0.6, gz * 0.6, 57, 4))
    lights = street * dense * (0.3 + 0.7 * grain) * 0.6 + smooth(0.78, 0.95, fbm(gx * 30, gz * 30, 54, 2)) * (0.3 + 0.7 * dense)
    dist = smooth(-40.0, -0.5, EL_DEG)
    ground = mix(col("0e1018"), col("6a4a54"), dist ** 3)
    glow = mix(col("ffb060"), col("ffd8a0"), grain) * (lights * (1 - dist ** 2) * 0.55)[..., None]
    img = np.where(below[..., None], ground + glow, img)
    # Far towers rising above the horizon line, with lit windows.
    rng = np.random.default_rng(55)
    a = -math.pi
    while a < math.pi:
        w = rng.uniform(0.006, 0.03)
        hgt = rng.choice([rng.uniform(0.3, 1.6), rng.uniform(1.6, 4.5)], p=[0.7, 0.3])
        da = np.angle(np.exp(1j * (AZ - (a + w / 2))))
        body = (np.abs(da) < w / 2) & (EL_DEG < hgt) & (EL_DEG > -2.5)
        if body.any():
            shade = rng.uniform(0.0, 1.0)
            img = np.where(body[..., None], mix(col("1a1c2c"), col("2c2c44"), shade), img)
            wx = np.mod((da + w / 2) / 0.0011, 1.0)
            wy = np.mod(EL_DEG / 0.11, 1.0)
            cell = (np.floor((da + 10) / 0.0011) * 7 + np.floor(EL_DEG / 0.11) * 13).astype(np.int64)
            on = _hash(cell, np.full_like(cell, int(a * 1000)), 56) > 0.62
            window = body & (wx > 0.3) & (wy > 0.35) & on
            img = np.where(window[..., None], col("ffcf8a") * 0.9, img)
            if hgt > 2.5:
                beacon = (np.abs(da) < 0.0012) & (np.abs(EL_DEG - hgt - 0.08) < 0.08)
                img = np.where(beacon[..., None], col("ff3020") * 3.0, img)
        a += w + rng.uniform(0.0, 0.02)
    return img


def highland_afternoon() -> np.ndarray:
    """Kestrel Keep: broken cumulus and long light over layered mountains."""
    img = gradient("3a64a0", "7a9cc4", "e6dcc8", "3a4436", 24)
    img = cloud_layer(img, 61, 0.9, 0.5, 0.16, "fff4e4", "6a7486", opacity=1.0, octaves=7,
                      horizon_fade=2.0)
    img = cloud_layer(img, 62, 0.35, 0.62, 0.25, "f0ece4", "b0b4bc", stretch=2.5, opacity=0.5,
                      horizon_fade=4.0)
    img = haze_band(img, "dcd6cc", 3.5, 0.45)
    img = silhouette(img, horizon_profile(63, 3.5, 4.5, 1.4), "8494a4", "a8b4c0")
    img = silhouette(img, horizon_profile(64, 2.2, 3.4, 1.2), "61707c", "7d8a94")
    img = silhouette(img, horizon_profile(65, 0.8, 2.0, 1.0), "3e4a3e", "566250")
    return img


def english_grey() -> np.ndarray:
    """Barnwell: a soft English sky, a thin bright deck with darker rain clouds, low fields."""
    img = gradient("8494a6", "a8b4c0", "d4d8d8", "4e5a44", 20)
    img = cloud_layer(img, 71, 0.5, 0.42, 0.3, "eef0f0", "8a929a", opacity=0.9, octaves=7,
                      horizon_fade=3)
    img = cloud_layer(img, 72, 1.1, 0.6, 0.14, "f6f6f2", "7c848c", opacity=0.6, horizon_fade=3)
    img = haze_band(img, "d8dcd8", 3.0, 0.5)
    img = silhouette(img, horizon_profile(73, 0.6, 0.7, 0.9), "7f8c7c", "98a494")
    # Hedgerow trees, a church spire and a water tower along the fields.
    rng = np.random.default_rng(74)
    tree_noise = fbm(AZ * 220, np.zeros_like(AZ), 75, 4)
    trees = horizon_profile(73, 0.6, 0.7, 0.9) + 0.25 + 0.6 * smooth(0.5, 0.8, tree_noise)
    img = silhouette(img, trees, "4a5642", floor=0.0)
    for a, hgt in [(0.9, 2.6), (-2.3, 1.9)]:
        da = np.angle(np.exp(1j * (AZ - a)))
        spire = (np.abs(da) < 0.0045 * np.clip((hgt - EL_DEG) / (hgt - 0.8), 0, 1)) & (EL_DEG > 0.5)
        tower = (np.abs(da) < 0.0040) & (EL_DEG < 1.0) & (EL_DEG > 0)
        img = np.where((spire | tower)[..., None], col("5a6058"), img)
    da = np.angle(np.exp(1j * (AZ + 0.6)))
    tank = (np.abs(da) < 0.006) & (EL_DEG > 1.3) & (EL_DEG < 1.9)
    stem = (np.abs(da) < 0.0012) & (EL_DEG > 0.2) & (EL_DEG <= 1.3)
    img = np.where((tank | stem)[..., None], col("6a706c"), img)
    del rng
    return img


def desert_night() -> np.ndarray:
    """Saffra: a clear desert night, dense stars and the galactic band over low dunes."""
    img = gradient("03050c", "0b1226", "1c2a48", "06070c", 30)
    img = milky_way(img, 81, (0.55, 0.45, 0.70), 0.05)
    img = stars(img, 82, 9000, 1.0, min_el=3.0, band=(0.55, 0.45, 0.70))
    img = haze_band(img, "24324e", 3.0, 0.35)
    img = silhouette(img, horizon_profile(83, 0.7, 1.0, 0.7), "0e1220", "161c2e")
    img = silhouette(img, horizon_profile(84, 0.2, 0.6, 0.6), "080a12")
    # A far town's glow low on one horizon.
    da = np.angle(np.exp(1j * (AZ + 2.4)))
    img = img + col("ffa860")[None, None, :] * (np.exp(-(da / 0.35) ** 2) * np.exp(-np.abs(EL_DEG) / 1.6) * 0.06)[..., None]
    return img


def fen_summer() -> np.ndarray:
    """Barnwell: a late-summer fenland sky, clear blue with thin cirrus and small cumulus over
    flat land; tall poplars, broadleaf tree lines, a church tower and pylons on the horizon."""
    img = gradient("2c64b4", "6c9ed6", "dbe6ec", "56664a", 22)
    img = cloud_layer(img, 91, 0.45, 0.7, 0.3, "ffffff", "dfe8f0", stretch=4.0, opacity=0.55,
                      octaves=7, horizon_fade=8)
    img = cloud_layer(img, 92, 1.6, 0.74, 0.1, "ffffff", "b4c0cc", opacity=0.95, octaves=6,
                      horizon_fade=2.0)
    img = haze_band(img, "e2eaee", 2.2, 0.55)
    # Dead flat land: a faint far tree line, then nearer broadleaf belts with poplars standing up.
    far = horizon_profile(93, 0.15, 0.25, 0.6) + 0.2 * smooth(0.45, 0.8, fbm(AZ * 140, np.zeros_like(AZ), 94, 4))
    img = silhouette(img, far, "8c9a90", floor=-0.05)
    belt = 0.25 + 1.1 * smooth(0.4, 0.75, fbm(AZ * 60, np.zeros_like(AZ), 95, 5)) \
        + 0.35 * fbm(AZ * 400, np.zeros_like(AZ), 96, 3)
    belt = np.where(fbm(AZ * 8, np.zeros_like(AZ), 97, 3) > 0.42, belt, 0.1)
    img = silhouette(img, belt, "4a5a3c", "5e6e48", floor=0.0)
    rng = np.random.default_rng(98)
    for _ in range(70):
        a = rng.uniform(-math.pi, math.pi)
        hgt = rng.uniform(1.6, 3.6)
        w = rng.uniform(0.0025, 0.005)
        da = np.angle(np.exp(1j * (AZ - a)))
        t = np.clip(EL_DEG / hgt, 0, 1)
        poplar = (np.abs(da) < w * np.sqrt(np.clip(1 - t ** 2, 0, 1)) * (0.6 + 0.4 * (1 - t))) & (EL_DEG > 0.1)
        img = np.where(poplar[..., None], mix(col("3e4e34"), col("56663e"), rng.uniform(0, 1)), img)
    # A church tower with pinnacles, and a line of pylons.
    da = np.angle(np.exp(1j * (AZ - 1.2)))
    tower = (np.abs(da) < 0.006) & (EL_DEG > 0.2) & (EL_DEG < 2.2)
    pins = (np.abs(np.abs(da) - 0.0052) < 0.0009) & (EL_DEG >= 2.2) & (EL_DEG < 2.55)
    img = np.where((tower | pins)[..., None], col("6e7068"), img)
    for k in range(6):
        a = -2.0 + k * 0.22
        hgt = 2.4 - k * 0.25
        da = np.angle(np.exp(1j * (AZ - a)))
        tt = np.clip(EL_DEG / hgt, 0, 1)
        leg = (np.abs(np.abs(da) - 0.004 * (1 - tt)) < 0.0005) & (EL_DEG < hgt) & (EL_DEG > 0.1)
        arm = (np.abs(da) < 0.005) & (np.abs(EL_DEG - hgt * 0.82) < 0.04)
        img = np.where((leg | arm)[..., None], col("5a6066"), img)
    return img


SKIES = {
    "hazy_noon": (hazy_noon, 1),
    "overcast_works": (overcast_works, 2),
    "harbour_fair": (harbour_fair, 3),
    "city_dusk": (city_dusk, 4),
    "highland_afternoon": (highland_afternoon, 5),
    "english_grey": (english_grey, 6),
    "desert_night": (desert_night, 7),
    "fen_summer": (fen_summer, 8),
}


def main() -> None:
    names = sys.argv[1:] or list(SKIES)
    for name in names:
        fn, seed = SKIES[name]
        finish(fn(), name, seed)


if __name__ == "__main__":
    main()
