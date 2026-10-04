"""Derive game-ready textures for the Kowloon world from assets-source/third_party.

Usage (from tools/world): uv run python ../assets/make_textures.py

- Copies the Poly Haven PBR maps (albedo, normal GL, roughness) into game/world/textures/.
- Composites foliage cards with alpha from the ambientCG single-leaf atlases:
  canopy (broad leaves, banyan-like), pioneer canopy (palmate leaves), ivy curtain,
  fern fan and grass tuft. Deterministic (fixed seeds).
Writes Godot .import presets so normal maps are imported as normal maps.
"""
import math
import random
import shutil
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "assets-source/third_party"
OUT = ROOT / "game/world/textures"

PBR = [
    "worn_plaster_wall", "rectangular_facade_tiles", "concrete_wall_008", "painted_concrete",
    "worn_mossy_plasterwall", "rusted_shutter", "road_damaged", "overgrown_concrete_pavers",
    "square_concrete_pavers", "concrete_moss", "forest_leaves_02", "leafy_grass",
    "brown_mud_leaves_01", "gravel_ground_01", "concrete_floor_worn_001", "rusty_metal_02",
    "japanese_camphor_bark",
]


def import_preset(path: Path, normal: bool, srgb_off: bool = False) -> None:
    lines = [
        "[remap]", "", 'importer="texture"', 'type="CompressedTexture2D"', "", "[params]", "",
        "compress/mode=2", "compress/high_quality=false", f"compress/normal_map={1 if normal else 2}",
        "mipmaps/generate=true", "detect_3d/compress_to=0",
    ]
    if srgb_off:
        lines.append("compress/channel_pack=1")
    imp = path.with_name(path.name + ".import")
    if not imp.exists():  # Godot fills in uid/dest on first import; keep its version afterwards
        imp.write_text("\n".join(lines) + "\n")


def leaves(asset: str):
    """Cut the 3x3 single-leaf atlas into RGBA leaf sprites."""
    d = SRC / "ambientcg" / asset
    col = Image.open(d / f"{asset}_1K-JPG_Color.jpg").convert("RGB")
    op = Image.open(d / f"{asset}_1K-JPG_Opacity.jpg").convert("L")
    w, h = col.size
    out = []
    for r in range(3):
        for c in range(3):
            box = (c * w // 3, r * h // 3, (c + 1) * w // 3, (r + 1) * h // 3)
            sprite = col.crop(box)
            sprite.putalpha(op.crop(box))
            bb = sprite.getbbox()
            if bb:
                out.append(sprite.crop(bb))
    return out


def scatter(canvas: Image.Image, sprites, n, rng, placer, size_range, tint_range):
    for _ in range(n):
        s = rng.choice(sprites)
        scale = rng.uniform(*size_range)
        sp = s.resize((max(4, int(s.width * scale)), max(4, int(s.height * scale))), Image.LANCZOS)
        x, y, ang = placer(rng)
        sp = sp.rotate(ang, expand=True, resample=Image.BICUBIC)
        b = rng.uniform(*tint_range)
        rgb = ImageEnhance.Brightness(sp.convert("RGB")).enhance(b)
        rgb.putalpha(sp.getchannel("A"))
        canvas.alpha_composite(rgb, (int(x - rgb.width / 2), int(y - rgb.height / 2)))


def canopy(asset: str, name: str, seed: int, size_range, count: int) -> None:
    rng = random.Random(seed)
    S = 1024
    img = Image.new("RGBA", (S, S), (40, 60, 25, 0))
    d = ImageDraw.Draw(img)
    # twigs
    for _ in range(26):
        a = rng.uniform(0, math.tau)
        r0, r1 = rng.uniform(0, 80), rng.uniform(250, 470)
        d.line([(S / 2 + math.cos(a) * r0, S / 2 + math.sin(a) * r0), (S / 2 + math.cos(a) * r1, S / 2 + math.sin(a) * r1)],
               fill=(70, 58, 44, 255), width=rng.randint(4, 9))
    sp = leaves(asset)

    def place(rng):
        r = 470 * math.sqrt(rng.random())
        a = rng.uniform(0, math.tau)
        return S / 2 + math.cos(a) * r, S / 2 + math.sin(a) * r, rng.uniform(0, 360)

    scatter(img, sp, count, rng, place, size_range, (0.55, 1.05))
    # darken toward the centre to fake self-shadowing inside the clump
    shade = Image.new("L", (S, S), 0)
    ImageDraw.Draw(shade).ellipse((S * 0.2, S * 0.2, S * 0.8, S * 0.8), fill=90)
    shade = shade.filter(ImageFilter.GaussianBlur(120))
    rgb = img.convert("RGB")
    rgb = Image.composite(Image.new("RGB", (S, S), (10, 18, 6)), rgb, shade)
    rgb.putalpha(img.getchannel("A"))
    rgb.save(OUT / f"{name}.png")
    import_preset(OUT / f"{name}.png", False)


def ivy() -> None:
    """Hanging ivy curtain, tileable horizontally; dense at the top, thinning strands downward."""
    rng = random.Random(17)
    W, H = 512, 1024
    img = Image.new("RGBA", (W, H), (30, 50, 20, 0))
    d = ImageDraw.Draw(img)
    sp = leaves("LeafSet017")
    strands = []
    for k in range(14):
        x0 = rng.uniform(0, W)
        length = H * rng.uniform(0.35, 1.0)
        pts = [(x0, 0.0)]
        x = x0
        for y in range(0, int(length), 16):
            x += rng.uniform(-6, 6)
            pts.append((x, float(y)))
        strands.append(pts)
        for dx in (-W, 0, W):
            d.line([(p[0] + dx, p[1]) for p in pts], fill=(64, 54, 36, 255), width=3)
    for pts in strands:
        for (x, y) in pts:
            if rng.random() < 0.85 - y / H * 0.4:
                for _ in range(2):
                    s = rng.choice(sp)
                    scale = rng.uniform(0.09, 0.16)
                    leaf = s.resize((max(4, int(s.width * scale)), max(4, int(s.height * scale))), Image.LANCZOS)
                    leaf = leaf.rotate(rng.uniform(150, 210), expand=True, resample=Image.BICUBIC)  # leaves hang down
                    b = rng.uniform(0.45, 0.95)
                    rgb = ImageEnhance.Brightness(leaf.convert("RGB")).enhance(b)
                    rgb.putalpha(leaf.getchannel("A"))
                    px, py = x + rng.uniform(-14, 14), y + rng.uniform(-8, 8)
                    for dx in (-W, 0, W):
                        img.alpha_composite(rgb, (int(px + dx - rgb.width / 2), int(py - rgb.height / 2)))
    # dense mat along the top edge (growth spilling over the parapet)
    scatter(img, sp, 260, rng, lambda r: (r.uniform(0, W), r.uniform(0, 110) ** 1.0, r.uniform(0, 360)), (0.1, 0.18), (0.5, 0.95))
    img.save(OUT / "ivy_curtain.png")
    import_preset(OUT / "ivy_curtain.png", False)


def fern() -> None:
    rng = random.Random(19)
    S = 512
    img = Image.new("RGBA", (S, S), (30, 50, 20, 0))
    sp = leaves("LeafSet019")
    for k in range(9):
        s = rng.choice(sp)
        scale = rng.uniform(0.5, 0.7)
        leaf = s.resize((int(s.width * scale), int(s.height * scale)), Image.LANCZOS)
        leaf = leaf.rotate(90 + rng.uniform(-35, 35), expand=True, resample=Image.BICUBIC)
        b = rng.uniform(0.6, 1.0)
        rgb = ImageEnhance.Brightness(leaf.convert("RGB")).enhance(b)
        rgb.putalpha(leaf.getchannel("A"))
        img.alpha_composite(rgb, (int(S / 2 - rgb.width / 2 + rng.uniform(-40, 40)), int(S - rgb.height)))
    img.save(OUT / "fern_card.png")
    import_preset(OUT / "fern_card.png", False)


def grass() -> None:
    rng = random.Random(23)
    W, H = 512, 512
    img = Image.new("RGBA", (W, H), (60, 80, 30, 0))
    d = ImageDraw.Draw(img)
    for k in range(140):
        x = rng.uniform(10, W - 10)
        h = rng.uniform(0.35, 1.0) * H
        bend = rng.uniform(-60, 60)
        base_w = rng.uniform(4, 9)
        g = rng.uniform(0.7, 1.15)
        col_base = (int(48 * g), int(66 * g), int(26 * g), 255)
        col_tip = (int(120 * g), int(130 * g), int(62 * g), 255)
        steps = 12
        for s in range(steps):
            t0, t1 = s / steps, (s + 1) / steps
            x0 = x + bend * t0 * t0
            x1 = x + bend * t1 * t1
            y0, y1 = H - h * t0, H - h * t1
            w0, w1 = base_w * (1 - t0), base_w * (1 - t1)
            c = tuple(int(col_base[i] + (col_tip[i] - col_base[i]) * t0) for i in range(4))
            d.polygon([(x0 - w0, y0), (x0 + w0, y0), (x1 + w1, y1), (x1 - w1, y1)], fill=c)
    img.save(OUT / "grass_card.png")
    import_preset(OUT / "grass_card.png", False)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for tid in PBR:
        d = SRC / "polyhaven" / tid
        for suffix, normal in (("diff", False), ("nor_gl", True), ("rough", False)):
            src = d / f"{tid}_{suffix}_1k.jpg"
            if not src.exists() and suffix == "diff":
                src = d / f"{tid}_diffuse_1k.jpg"
            dst = OUT / f"{tid}_{suffix}.jpg"
            shutil.copyfile(src, dst)
            import_preset(dst, normal)
    hdr = SRC / "polyhaven/kloofendal_overcast_puresky/kloofendal_overcast_puresky_2k.hdr"
    shutil.copyfile(hdr, OUT / "sky_overcast.hdr")
    shutil.copyfile(SRC / "polyhaven/kloofendal_38d_partly_cloudy_puresky/kloofendal_38d_partly_cloudy_puresky_2k.hdr", OUT / "sky_partly_cloudy.hdr")
    canopy("LeafSet024", "canopy_broad", 24, (0.10, 0.17), 900)
    canopy("LeafSet029", "canopy_palmate", 29, (0.14, 0.24), 420)
    ivy()
    fern()
    grass()
    print("textures written to", OUT)


if __name__ == "__main__":
    main()
