"""Download the CC0 texture/HDRI assets used by the Kowloon world and record checksums.

Usage (from tools/world, which provides the Python env):
    uv run python ../assets/fetch_assets.py

Sources: Poly Haven (https://polyhaven.com, CC0) via its public API and ambientCG
(https://ambientcg.com, CC0). Files land in assets-source/third_party/ (ignored by Git);
assets-source/third_party/manifest.json records URL, licence and sha256 for each file.
make_textures.py then derives the game-ready textures in game/world/textures/.
"""
import hashlib
import io
import json
import time
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / "assets-source/third_party"
MANIFEST = DEST / "manifest.json"

# Poly Haven textures: id -> maps (1k JPG)
POLYHAVEN_TEXTURES = {
    "worn_plaster_wall": ["Diffuse", "nor_gl", "Rough"],
    "rectangular_facade_tiles": ["Diffuse", "nor_gl", "Rough"],
    "concrete_wall_008": ["Diffuse", "nor_gl", "Rough"],
    "painted_concrete": ["Diffuse", "nor_gl", "Rough"],
    "worn_mossy_plasterwall": ["Diffuse", "nor_gl", "Rough"],
    "rusted_shutter": ["Diffuse", "nor_gl", "Rough"],
    "road_damaged": ["Diffuse", "nor_gl", "Rough"],
    "overgrown_concrete_pavers": ["Diffuse", "nor_gl", "Rough"],
    "square_concrete_pavers": ["Diffuse", "nor_gl", "Rough"],
    "concrete_moss": ["Diffuse", "nor_gl", "Rough"],
    "forest_leaves_02": ["Diffuse", "nor_gl", "Rough"],
    "leafy_grass": ["Diffuse", "nor_gl", "Rough"],
    "brown_mud_leaves_01": ["Diffuse", "nor_gl", "Rough"],
    "gravel_ground_01": ["Diffuse", "nor_gl", "Rough"],
    "concrete_floor_worn_001": ["Diffuse", "nor_gl", "Rough"],
    "rusty_metal_02": ["Diffuse", "nor_gl", "Rough"],
    "japanese_camphor_bark": ["Diffuse", "nor_gl", "Rough"],
}
POLYHAVEN_HDRIS = {"kloofendal_overcast_puresky": "2k", "kloofendal_38d_partly_cloudy_puresky": "2k"}
# ambientCG leaf atlases (1K JPG zip): broad leaves, ivy, fern fronds, palmate leaves
AMBIENTCG = ["LeafSet024", "LeafSet017", "LeafSet019", "LeafSet029"]


def get(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "LastKnown-asset-fetch/1.0"})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                return r.read()
        except OSError as e:
            if attempt == 3:
                raise
            print("retry", url, e)
            time.sleep(2 + attempt * 3)
    raise RuntimeError


def save(path: Path, data: bytes, entry: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    entry["sha256"] = hashlib.sha256(data).hexdigest()
    entry["bytes"] = len(data)
    entry["file"] = str(path.relative_to(DEST))


def main() -> None:
    old = {e["file"]: e for e in json.loads(MANIFEST.read_text())["files"]} if MANIFEST.exists() else {}
    files = []
    for tid, maps in POLYHAVEN_TEXTURES.items():
        info = json.loads(get(f"https://api.polyhaven.com/files/{tid}"))
        for m in maps:
            f = info[m]["1k"]["jpg"]
            path = DEST / "polyhaven" / tid / Path(f["url"]).name
            entry = {"source": "Poly Haven", "asset": tid, "url": f["url"], "license": "CC0 1.0", "md5_upstream": f["md5"]}
            rel = str(path.relative_to(DEST))
            if path.exists() and hashlib.md5(path.read_bytes()).hexdigest() == f["md5"]:
                entry.update({k: old.get(rel, {}).get(k) for k in ("sha256", "bytes")}, file=rel)
                if not entry.get("sha256"):
                    save(path, path.read_bytes(), entry)
            else:
                data = get(f["url"])
                if hashlib.md5(data).hexdigest() != f["md5"]:
                    raise SystemExit(f"md5 mismatch {f['url']}")
                save(path, data, entry)
            files.append(entry)
            print("ok", rel)
    for hid, res in POLYHAVEN_HDRIS.items():
        info = json.loads(get(f"https://api.polyhaven.com/files/{hid}"))
        f = info["hdri"][res]["hdr"]
        path = DEST / "polyhaven" / hid / Path(f["url"]).name
        entry = {"source": "Poly Haven", "asset": hid, "url": f["url"], "license": "CC0 1.0", "md5_upstream": f["md5"]}
        if not (path.exists() and hashlib.md5(path.read_bytes()).hexdigest() == f["md5"]):
            save(path, get(f["url"]), entry)
        else:
            save(path, path.read_bytes(), entry)
        files.append(entry)
        print("ok", entry["file"])
    for aid in AMBIENTCG:
        url = f"https://ambientcg.com/get?file={aid}_1K-JPG.zip"
        zdata = get(url)
        z = zipfile.ZipFile(io.BytesIO(zdata))
        for name in z.namelist():
            if name.endswith(("_Color.jpg", "_Opacity.jpg", "_NormalGL.jpg")):
                entry = {"source": "ambientCG", "asset": aid, "url": url, "license": "CC0 1.0"}
                save(DEST / "ambientcg" / aid / name, z.read(name), entry)
                files.append(entry)
                print("ok", entry["file"])
    MANIFEST.write_text(json.dumps({
        "note": "CC0 assets; attribution not required but credited in docs/world-map-pipeline.md",
        "retrieved": time.strftime("%Y-%m-%d"),
        "files": files,
    }, indent=1) + "\n")


if __name__ == "__main__":
    main()
