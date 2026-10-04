"""Download the pinned raw inputs for the Kowloon world into assets-source/kowloon/raw.

Usage: uv run python fetch.py [--refresh-buildings]

DTM and OSM are fixed files verified against sources.json checksums. The LandsD
building layer is a live ArcGIS service; the first fetch is saved as a dated
snapshot and its checksum recorded. Later runs reuse that snapshot unless
--refresh-buildings is given.
"""
import hashlib
import json
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "assets-source/kowloon/raw"
MANIFEST = ROOT / "assets-source/kowloon/sources.json"

# HK1980 Grid bbox covering the Kowloon polygon (OSM relation 10268797) with a margin.
BBOX = (831300, 815800, 843500, 824500)
BUILDING_LAYER = (
    "https://portal.csdi.gov.hk/server/rest/services/common/"
    "landsd_rcd_1637211194312_35158/FeatureServer/0/query"
)
BUILDING_FIELDS = "OBJECTID,BuildingID,BuildingBlockType,Status,BuildingNameEN,BaseHeight,TopHeight,Storeys"


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def get(url: str, timeout: int = 300) -> bytes:
    for attempt in range(4):
        try:
            with urllib.request.urlopen(url, timeout=timeout) as r:
                return r.read()
        except OSError as e:
            if attempt == 3:
                raise
            print(f"retry {attempt + 1}: {e}")
            time.sleep(3 * (attempt + 1))
    raise RuntimeError("unreachable")


def fetch_file(src: dict) -> None:
    path = RAW / src["file"]
    if not path.exists():
        print("download", src["url"])
        path.write_bytes(get(src["url"]))
    digest = sha256(path)
    if digest != src["sha256"]:
        sys.exit(f"checksum mismatch for {path.name}: {digest}")
    print("ok", path.name)


def fetch_buildings(src: dict, refresh: bool) -> None:
    path = RAW / src["file"]
    if path.exists() and not refresh:
        digest = sha256(path)
        if digest != src.get("sha256"):
            sys.exit(f"checksum mismatch for {path.name}: {digest}")
        print("ok", path.name)
        return
    features: list = []
    offset = 0
    while True:
        q = {
            "where": "1=1",
            "geometry": ",".join(map(str, BBOX)),
            "geometryType": "esriGeometryEnvelope",
            "inSR": "2326",
            "spatialRel": "esriSpatialRelIntersects",
            "outFields": BUILDING_FIELDS,
            "returnGeometry": "true",
            "outSR": "2326",
            "orderByFields": "OBJECTID",
            "resultOffset": str(offset),
            "resultRecordCount": "2000",
            "f": "json",
        }
        page = json.loads(get(BUILDING_LAYER + "?" + urllib.parse.urlencode(q)))
        if "error" in page:
            sys.exit(f"service error: {page['error']}")
        batch = page.get("features", [])
        features.extend(batch)
        print(f"buildings {len(features)}")
        if not batch or not page.get("exceededTransferLimit"):
            break
        offset += len(batch)
    path.write_text(json.dumps({"bbox": BBOX, "features": features}, separators=(",", ":")))
    src["sha256"] = sha256(path)
    src["feature_count"] = len(features)
    src["retrieved"] = time.strftime("%Y-%m-%d")
    MANIFEST.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
    print("snapshot", path.name, src["sha256"])


if __name__ == "__main__":
    RAW.mkdir(parents=True, exist_ok=True)
    manifest = json.loads(MANIFEST.read_text())
    for s in manifest["sources"]:
        if s["id"] == "landsd_buildings":
            fetch_buildings(s, "--refresh-buildings" in sys.argv)
        else:
            fetch_file(s)
