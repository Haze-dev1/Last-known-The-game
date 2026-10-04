"""Build the streamed Kowloon world from the pinned inputs in assets-source/kowloon/raw.

Usage: uv run python build.py            (writes game/world/data/)

Deterministic: the same inputs produce byte-identical chunk files. Coordinates are
HK1980 Grid (EPSG:2326) shifted to a local origin: Godot x = E - E0, z = N0 - N,
y = metres above Hong Kong Principal Datum. See docs/world-map-pipeline.md.
"""
from __future__ import annotations

import hashlib
import io
import json
import math
import struct
import sys
import time
import zipfile
import zlib
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np
import osmium
import shapely
import shapely.prepared
from PIL import Image, ImageDraw
from pyproj import Transformer
from scipy import ndimage
from shapely import wkb
from shapely.geometry import LineString, MultiPolygon, Point, Polygon, box
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "assets-source/kowloon/raw"
OUT = ROOT / "game/world/data"
CACHE = Path(__file__).resolve().parent / ".cache"

E0, N0 = 837000.0, 820000.0  # local origin (HK1980 Grid), near Mong Kok / Ho Man Tin
CHUNK = 256  # metres per chunk side
STEP = 4  # near terrain grid spacing (m)
FAR_STEP = 16  # far terrain grid spacing (m)
SEA_LEVEL = 1.2  # mPD; approximate mean sea level in Victoria Harbour
FRINGE = 120  # metres of content kept outside the Kowloon polygon
KOWLOON_REL = 10268797
DISTRICT_RELS = {
    2670978: "Yau Tsim Mong",
    2800200: "Sham Shui Po",
    2800201: "Kowloon City",
    2800277: "Wong Tai Sin",
    2800276: "Kwun Tong",
}
# Background terrain extent (HK1980) and DTM crop.
BG_E = (822000, 852000)
BG_N = (806000, 832000)
BG_STEP = 60

# ---------------------------------------------------------------- materials / ids
M_TERRAIN, M_ROAD, M_PAVING, M_FACADE, M_ROOF, M_RAIL, M_CONCRETE, M_PROP, M_IVY = range(9)
A_BANYAN, A_SLENDER, A_SHRUB, A_GRASS, A_LAMP, A_CAR, A_BUS, A_BLOB, A_FERN = range(9)

ROAD_CLASSES = {
    # highway: (width m, surface material, z-offset, class code, auto sidewalks, major)
    "motorway": (14.0, M_ROAD, 0.22, 9, False, True),
    "trunk": (13.0, M_ROAD, 0.21, 8, False, True),
    "primary": (12.0, M_ROAD, 0.20, 7, True, True),
    "secondary": (10.0, M_ROAD, 0.19, 6, True, True),
    "tertiary": (8.0, M_ROAD, 0.18, 5, True, True),
    "motorway_link": (7.0, M_ROAD, 0.17, 9, False, False),
    "trunk_link": (7.0, M_ROAD, 0.17, 8, False, False),
    "primary_link": (6.5, M_ROAD, 0.17, 7, False, False),
    "secondary_link": (6.0, M_ROAD, 0.17, 6, False, False),
    "tertiary_link": (6.0, M_ROAD, 0.17, 5, False, False),
    "unclassified": (6.0, M_ROAD, 0.165, 4, True, False),
    "residential": (6.0, M_ROAD, 0.165, 4, True, False),
    "road": (6.0, M_ROAD, 0.165, 4, False, False),
    "living_street": (5.0, M_ROAD, 0.16, 3, False, False),
    "service": (4.0, M_ROAD, 0.155, 3, False, False),
    "pedestrian": (6.0, M_PAVING, 0.13, 2, False, False),
    "footway": (2.5, M_PAVING, 0.12, 1, False, False),
    "steps": (2.5, M_PAVING, 0.12, 1, False, False),
    "cycleway": (2.5, M_PAVING, 0.12, 1, False, False),
    "path": (2.0, M_PAVING, 0.115, 0, False, False),
    "track": (3.0, M_PAVING, 0.115, 0, False, False),
}
RAIL_TYPES = {"rail", "subway", "light_rail", "narrow_gauge"}

# terrain classes: id -> (rgb, overgrowth amount)
T_PAVED, T_PARK, T_WOOD, T_SCRUB, T_SAND, T_WATER, T_INDUSTRIAL, T_SEA, T_PITCH, T_RAIL, T_CEMETERY, T_SLOPE = range(12)
T_COLORS = {
    T_PAVED: ((0.43, 0.42, 0.39), 0.22),
    T_PARK: ((0.30, 0.37, 0.19), 0.85),
    T_WOOD: ((0.19, 0.25, 0.13), 1.0),
    T_SCRUB: ((0.36, 0.35, 0.22), 0.9),
    T_SAND: ((0.60, 0.55, 0.44), 0.1),
    T_WATER: ((0.17, 0.21, 0.19), 0.6),
    T_INDUSTRIAL: ((0.39, 0.37, 0.34), 0.3),
    T_SEA: ((0.16, 0.18, 0.16), 0.0),
    T_PITCH: ((0.31, 0.36, 0.22), 0.75),
    T_RAIL: ((0.35, 0.32, 0.29), 0.55),
    T_CEMETERY: ((0.33, 0.37, 0.24), 0.7),
    T_SLOPE: ((0.55, 0.53, 0.46), 0.35),
}
# terrain texture weights per class: (grass, forest floor, mud/scrub, wet); remainder = hard paving
T_WEIGHTS = {
    T_PAVED: (0.0, 0.0, 0.0, 0.0), T_PARK: (1.0, 0.0, 0.0, 0.0), T_WOOD: (0.0, 1.0, 0.0, 0.0),
    T_SCRUB: (0.45, 0.0, 0.55, 0.0), T_SAND: (0.0, 0.0, 0.35, 0.0), T_WATER: (0.0, 0.0, 0.2, 0.8),
    T_INDUSTRIAL: (0.0, 0.0, 0.0, 0.0), T_SEA: (0.0, 0.0, 0.6, 0.4), T_PITCH: (0.8, 0.0, 0.2, 0.0),
    T_RAIL: (0.15, 0.0, 0.45, 0.0), T_CEMETERY: (0.75, 0.1, 0.15, 0.0), T_SLOPE: (0.0, 0.0, 0.0, 0.0),
}
LANDUSE_CLASS = [
    # (tag, values, class); later entries override earlier ones
    ("landuse", {"industrial", "port", "depot", "garages"}, T_INDUSTRIAL),
    ("landuse", {"railway"}, T_RAIL),
    ("landuse", {"brownfield", "construction", "greenfield", "vacant", "farmland", "meadow", "allotments"}, T_SCRUB),
    ("natural", {"scrub", "heath", "grassland"}, T_SCRUB),
    ("landuse", {"grass", "village_green", "recreation_ground", "flowerbed"}, T_PARK),
    ("leisure", {"park", "garden", "golf_course", "nature_reserve", "dog_park"}, T_PARK),
    ("landuse", {"cemetery"}, T_CEMETERY),
    ("leisure", {"pitch", "playground", "track", "sports_centre"}, T_PITCH),
    ("landuse", {"forest"}, T_WOOD),
    ("natural", {"wood"}, T_WOOD),
    ("natural", {"beach", "sand"}, T_SAND),
    ("natural", {"water"}, T_WATER),
    ("waterway", {"riverbank", "canal", "dock"}, T_WATER),
]
STYLE_RES, STYLE_TONGLAU, STYLE_INDUSTRIAL, STYLE_PUBLIC, STYLE_PODIUM, STYLE_COMMERCIAL, STYLE_CANOPY, STYLE_SHED = range(8)

to_hk = Transformer.from_crs(4326, 2326, always_xy=True)


def log(*a):
    print(f"[{time.strftime('%H:%M:%S')}]", *a, flush=True)


def h32(*vals) -> int:
    """Stable integer hash for deterministic placement."""
    return int.from_bytes(hashlib.blake2b(repr(vals).encode(), digest_size=4).digest(), "little")


def local_xy(E, N):
    return np.asarray(E) - E0, N0 - np.asarray(N)


# ---------------------------------------------------------------- inputs
def load_dtm():
    CACHE.mkdir(exist_ok=True)
    cache = CACHE / "dtm_crop.npz"
    if cache.exists():
        d = np.load(cache)
        return d["h"], float(d["e_first"]), float(d["n_first"])
    log("parsing DTM ASCII grid")
    zf = zipfile.ZipFile(RAW / "Whole_HK_DTM_5m.zip")
    f = io.TextIOWrapper(zf.open("Whole_HK_DTM_5m.asc"))
    hdr = {}
    for _ in range(6):
        k, v = f.readline().split()
        hdr[k.lower()] = float(v)
    cs = hdr["cellsize"]
    top = hdr["yllcorner"] + hdr["nrows"] * cs - cs / 2  # centre of first row
    left = hdr["xllcorner"] + cs / 2
    r0, r1 = int((top - BG_N[1]) / cs), int((top - BG_N[0]) / cs)
    c0, c1 = int((BG_E[0] - left) / cs), int((BG_E[1] - left) / cs)
    rows = []
    for r, line in enumerate(f):
        if r < r0:
            continue
        if r > r1:
            break
        rows.append(np.array(line.split()[c0 : c1 + 1], dtype=np.float32))
    h = np.array(rows)
    h[h < -1000] = 0.0
    e_first, n_first = left + c0 * cs, top - r0 * cs
    np.savez_compressed(cache, h=h, e_first=e_first, n_first=n_first)
    return h, e_first, n_first


class OsmCollector(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.fab = osmium.geom.WKBFactory()
        self.ways = []  # (id, tags, node ids, lon, lat)
        self.areas = []  # (tags, wkb hex)
        self.admin = {}
        self.trees = []
        self.places = []

    def node(self, n):
        t = n.tags
        if t.get("natural") == "tree":
            self.trees.append((n.location.lon, n.location.lat))
        elif t.get("place") in ("suburb", "neighbourhood", "quarter") and "name:en" in t:
            self.places.append((t["name:en"], t["place"], n.location.lon, n.location.lat))

    def way(self, w):
        t = w.tags
        keep = ("highway" in t) or (t.get("railway") in RAIL_TYPES) or ("waterway" in t)
        if not keep:
            return
        try:
            refs = [nd.ref for nd in w.nodes]
            lon = [nd.lon for nd in w.nodes]
            lat = [nd.lat for nd in w.nodes]
        except osmium.InvalidLocationError:
            return
        keys = ("highway", "railway", "waterway", "bridge", "tunnel", "layer", "width", "lanes",
                "sidewalk", "name:en", "service", "covered", "indoor", "area", "level")
        self.ways.append((w.id, {k: t[k] for k in keys if k in t}, refs, lon, lat))

    def area(self, a):
        t = a.tags
        if not a.from_way() and a.orig_id() in DISTRICT_RELS.keys() | {KOWLOON_REL}:
            self.admin[a.orig_id()] = self.fab.create_multipolygon(a)
            return
        for key, vals, _ in LANDUSE_CLASS:
            if t.get(key) in vals:
                try:
                    self.areas.append(({key: t[key]}, self.fab.create_multipolygon(a)))
                except RuntimeError:
                    pass
                return


def geom_to_local(g):
    return shapely.transform(g, lambda c: np.column_stack(local_xy(*to_hk.transform(c[:, 0], c[:, 1]))))


def load_osm():
    log("reading OSM extract")
    h = OsmCollector()
    h.apply_file(str(RAW / "hong-kong-261003.osm.pbf"), locations=True)
    admin = {k: geom_to_local(wkb.loads(v, hex=True)) for k, v in h.admin.items()}
    areas = []
    for tags, hexwkb in h.areas:
        g = geom_to_local(wkb.loads(hexwkb, hex=True))
        if g.is_valid or (g := g.buffer(0)).is_valid:
            areas.append((tags, g))
    ways = []
    for wid, tags, refs, lon, lat in h.ways:
        E, N = to_hk.transform(np.array(lon), np.array(lat))
        x, z = local_xy(E, N)
        ways.append({"id": wid, "tags": tags, "refs": refs, "xz": np.column_stack([x, z])})
    trees = np.column_stack(local_xy(*to_hk.transform(*np.array(h.trees).T))) if h.trees else np.zeros((0, 2))
    places = []
    for name, kind, lon, lat in h.places:
        E, N = to_hk.transform(lon, lat)
        places.append((name, kind, *local_xy(E, N)))
    log(f"OSM: {len(ways)} ways, {len(areas)} land-use areas, {len(trees)} trees, {len(places)} places")
    return admin, areas, ways, trees, places


def load_buildings():
    data = json.loads((RAW / "landsd_buildings_kowloon.json").read_text())
    out = []
    for f in data["features"]:
        rings = f.get("geometry", {}).get("rings")
        if not rings:
            continue
        shells, holes = [], []
        for r in rings:
            a = np.asarray(r, dtype=np.float64)
            if len(a) < 4:
                continue
            signed = 0.5 * np.sum(a[:-1, 0] * a[1:, 1] - a[1:, 0] * a[:-1, 1])
            (shells if signed < 0 else holes).append(a)  # Esri: clockwise outer rings
        polys = []
        for s in shells:
            x, z = local_xy(s[:, 0], s[:, 1])
            shell = Polygon(np.column_stack([x, z]))
            hs = []
            for hring in holes:
                hx, hz = local_xy(hring[:, 0], hring[:, 1])
                hp = np.column_stack([hx, hz])
                if shell.contains(Point(hp[0])):
                    hs.append(hp)
            p = Polygon(shell.exterior.coords, hs)
            if not p.is_valid:
                p = p.buffer(0)
            if not p.is_empty:
                polys.append(p)
        if not polys:
            continue
        g = unary_union(polys)
        out.append({"attr": f["attributes"], "geom": g})
    log(f"LandsD buildings: {len(out)}")
    return out


# ---------------------------------------------------------------- terrain
class Terrain:
    """Ground model on a global STEP grid shared by all chunks (guarantees seams)."""

    def __init__(self, dtm, e_first, n_first, bridge_polys, x_range, z_range):
        self.dtm, self.e_first, self.n_first = dtm, e_first, n_first
        self.raw_dtm = dtm
        self.ground = self._remove_bridges(dtm, bridge_polys)
        self.xa, self.xb = x_range
        self.za, self.zb = z_range
        xs = np.arange(self.xa, self.xb + STEP, STEP, dtype=np.float64)
        zs = np.arange(self.za, self.zb + STEP, STEP, dtype=np.float64)
        self.nx, self.nz = len(xs), len(zs)
        X, Z = np.meshgrid(xs, zs)
        g = self.sample_grid(self.ground, X, Z)
        land = self.sample_grid((dtm > 0.05).astype(np.float32), X, Z) > 0.5
        self.land = land
        dist = ndimage.distance_transform_edt(~land) * STEP
        sea = SEA_LEVEL - 1.6 - np.minimum(dist * 0.06, 9.0)
        self.h = np.where(land, np.maximum(g, SEA_LEVEL + 0.6), sea).astype(np.float64)
        gz, gx = np.gradient(self.h, STEP)
        n = np.stack([-gx, np.ones_like(gx), -gz], axis=-1)
        self.normal = n / np.linalg.norm(n, axis=-1, keepdims=True)
        self.slope = np.degrees(np.arccos(np.clip(self.normal[..., 1], -1, 1)))

    def _remove_bridges(self, dtm, polys):
        mask = np.zeros(dtm.shape, bool)
        for p in polys:
            minx, minz, maxx, maxz = p.bounds
            c0, c1 = self._col(minx) - 1, self._col(maxx) + 2
            r0, r1 = self._row(minz) - 1, self._row(maxz) + 2
            c0, r0 = max(c0, 0), max(r0, 0)
            cc, rr = np.meshgrid(np.arange(c0, c1), np.arange(r0, r1))
            if cc.size == 0:
                continue
            X = self.e_first + cc * 5.0 - E0
            Z = N0 - (self.n_first - rr * 5.0)
            mask[rr, cc] |= shapely.contains_xy(p, X, Z)
        _, idx = ndimage.distance_transform_edt(mask, return_indices=True)
        filled = dtm[idx[0], idx[1]]
        smooth = ndimage.uniform_filter(filled, size=5)
        log(f"bridge corridors removed from DTM: {int(mask.sum())} cells")
        return np.where(mask, smooth, dtm).astype(np.float32)

    def _col(self, x):
        return int((x + E0 - self.e_first) / 5.0)

    def _row(self, z):
        return int((self.n_first - (N0 - z)) / 5.0)

    def sample_grid(self, arr, X, Z):
        col = (np.asarray(X) + E0 - self.e_first) / 5.0
        row = (self.n_first - (N0 - np.asarray(Z))) / 5.0
        return ndimage.map_coordinates(arr, [row, col], order=1, mode="nearest")

    def raw_at(self, x, z):
        return self.sample_grid(self.raw_dtm, x, z)

    def at(self, x, z):
        """Height of the triangulated terrain mesh (same split as the emitted mesh)."""
        fx = (np.asarray(x, dtype=np.float64) - self.xa) / STEP
        fz = (np.asarray(z, dtype=np.float64) - self.za) / STEP
        ix = np.clip(np.floor(fx).astype(int), 0, self.nx - 2)
        iz = np.clip(np.floor(fz).astype(int), 0, self.nz - 2)
        u, v = fx - ix, fz - iz
        h00 = self.h[iz, ix]
        h10 = self.h[iz, ix + 1]
        h01 = self.h[iz + 1, ix]
        h11 = self.h[iz + 1, ix + 1]
        upper = u >= v
        return np.where(upper, h00 + u * (h10 - h00) + v * (h11 - h10), h00 + v * (h01 - h00) + u * (h11 - h01))

    def index(self, x, z):
        return int(round((z - self.za) / STEP)), int(round((x - self.xa) / STEP))


def rasterize(grid_shape, xa, za, step, geoms, out, value):
    nz, nx = grid_shape
    for g in geoms:
        if g.is_empty:
            continue
        minx, minz, maxx, maxz = g.bounds
        i0, i1 = max(int((minx - xa) / step), 0), min(int((maxx - xa) / step) + 2, nx)
        j0, j1 = max(int((minz - za) / step), 0), min(int((maxz - za) / step) + 2, nz)
        if i0 >= i1 or j0 >= j1:
            continue
        X, Z = np.meshgrid(xa + np.arange(i0, i1) * step, za + np.arange(j0, j1) * step)
        m = shapely.contains_xy(g, X, Z)
        out[j0:j1, i0:i1][m] = value


# ---------------------------------------------------------------- mesh building
class MeshSet:
    """Accumulates triangle meshes per (material, collide) for one chunk file."""

    def __init__(self):
        self.parts = defaultdict(list)

    def add(self, mat, collide, pos, nrm, uv, c0, c1, idx):
        pos = np.asarray(pos, np.float32)
        if len(pos) == 0:
            return
        n = len(pos)
        self.parts[(mat, collide)].append((
            pos, np.asarray(nrm, np.float32).reshape(n, 3), np.asarray(uv, np.float32).reshape(n, 2),
            np.broadcast_to(np.asarray(c0, np.uint8), (n, 4)), np.broadcast_to(np.asarray(c1, np.uint8), (n, 4)),
            np.asarray(idx, np.int64).reshape(-1, 3),
        ))

    def sections(self):
        for (mat, collide), parts in sorted(self.parts.items()):
            off = 0
            P, Nn, U, C0, C1, I = [], [], [], [], [], []
            for p, n, u, c0, c1, idx in parts:
                P.append(p); Nn.append(n); U.append(u); C0.append(c0); C1.append(c1); I.append(idx + off)
                off += len(p)
            P, Nn, I = np.concatenate(P), np.concatenate(Nn), np.concatenate(I)
            # Godot treats clockwise triangles as front faces: cross(b-a, c-a) must oppose the normal.
            a, b, c = P[I[:, 0]], P[I[:, 1]], P[I[:, 2]]
            cr = np.cross(b - a, c - a)
            flip = np.einsum("ij,ij->i", cr, Nn[I[:, 0]] + Nn[I[:, 1]] + Nn[I[:, 2]]) > 0
            I[flip] = I[flip][:, ::-1]
            yield mat, collide, P, Nn, np.concatenate(U), np.concatenate(C0), np.concatenate(C1), I.astype(np.uint32)


def box_mesh(ms, mat, collide, center, half, yaw, c0, c1=(0, 0, 0, 0), pitch=0.0):
    """Axis box rotated by yaw (around y) then optional pitch tilt. half = (hx, hy, hz)."""
    hx, hy, hz = half
    faces = [
        ((1, 0, 0), [(1, -1, -1), (1, 1, -1), (1, 1, 1), (1, -1, 1)]),
        ((-1, 0, 0), [(-1, -1, 1), (-1, 1, 1), (-1, 1, -1), (-1, -1, -1)]),
        ((0, 1, 0), [(-1, 1, -1), (-1, 1, 1), (1, 1, 1), (1, 1, -1)]),
        ((0, -1, 0), [(-1, -1, 1), (-1, -1, -1), (1, -1, -1), (1, -1, 1)]),
        ((0, 0, 1), [(1, -1, 1), (1, 1, 1), (-1, 1, 1), (-1, -1, 1)]),
        ((0, 0, -1), [(-1, -1, -1), (-1, 1, -1), (1, 1, -1), (1, -1, -1)]),
    ]
    cy, sy = math.cos(yaw), math.sin(yaw)
    cp, sp = math.cos(pitch), math.sin(pitch)

    def rot(v):
        x, y, z = v
        y, z = y * cp - z * sp, y * sp + z * cp
        return (x * cy + z * sy, y, -x * sy + z * cy)

    P, Nn, U, I = [], [], [], []
    for k, (n, corners) in enumerate(faces):
        for cx, cyy, cz in corners:
            p = rot((cx * hx, cyy * hy, cz * hz))
            P.append((center[0] + p[0], center[1] + p[1], center[2] + p[2]))
            Nn.append(rot(n))
            U.append(((cx * hx + cz * hz), cyy * hy + hy))
        b = 4 * k
        I += [(b, b + 1, b + 2), (b, b + 2, b + 3)]
    ms.add(mat, collide, P, Nn, U, c0, c1, I)


def ribbon(ms, line, widths, heights_fn, mat, collide, c0, c1, offset, max_step=3.0):
    """Strip along a polyline (n,2) with several columns across; heights_fn(x, z, s) -> y."""
    line = np.asarray(line, np.float64)
    if len(line) < 2:
        return None
    ls = shapely.segmentize(LineString(line), max_step)
    pts = np.asarray(ls.coords)[:, :2]
    if len(pts) < 2:
        return None
    seg = np.diff(pts, axis=0)
    seglen = np.linalg.norm(seg, axis=1)
    keep = np.concatenate([[True], seglen > 0.05])
    pts = pts[keep]
    if len(pts) < 2:
        return None
    seg = np.diff(pts, axis=0)
    seglen = np.linalg.norm(seg, axis=1)
    s = np.concatenate([[0.0], np.cumsum(seglen)])
    t = np.zeros_like(pts)
    t[1:-1] = pts[2:] - pts[:-2]
    t[0], t[-1] = pts[1] - pts[0], pts[-1] - pts[-2]
    t /= np.maximum(np.linalg.norm(t, axis=1, keepdims=True), 1e-9)
    nrm2 = np.column_stack([-t[:, 1], t[:, 0]])
    # miter scale from the turn angle between adjacent segments
    d = seg / np.maximum(seglen[:, None], 1e-9)
    miter = np.ones(len(pts))
    cosang = np.einsum("ij,ij->i", d[:-1], d[1:]) if len(d) > 1 else np.zeros(0)
    miter[1:-1] = 1.0 / np.sqrt(np.clip((1 + cosang) / 2, 0.25, 1.0))
    w = float(widths)
    cols = max(2, int(math.ceil(w / 4.0)) + 1)
    across = np.linspace(-w / 2, w / 2, cols)
    P = pts[:, None, :] + nrm2[:, None, :] * (across[None, :, None] * miter[:, None, None])
    X, Z = P[..., 0], P[..., 1]
    Y = heights_fn(X, Z, np.repeat(s[:, None], cols, axis=1)) + offset
    pos = np.stack([X, Y, Z], axis=-1)
    # normals from the surface grid
    da = np.gradient(pos, axis=0)
    dc = np.gradient(pos, axis=1) if cols > 1 else np.zeros_like(pos)
    nrm = np.cross(dc, da)
    nrm *= np.sign(nrm[..., 1:2] + 1e-9)
    nrm /= np.maximum(np.linalg.norm(nrm, axis=-1, keepdims=True), 1e-9)
    uv = np.stack([np.broadcast_to(across[None, :], X.shape), np.repeat(s[:, None], cols, axis=1)], axis=-1)
    n = len(pts)
    idx = []
    grid = np.arange(n * cols).reshape(n, cols)
    a, b = grid[:-1, :-1].ravel(), grid[:-1, 1:].ravel()
    c, e = grid[1:, :-1].ravel(), grid[1:, 1:].ravel()
    idx = np.concatenate([np.column_stack([a, b, e]), np.column_stack([a, e, c])])
    ms.add(mat, collide, pos.reshape(-1, 3), nrm.reshape(-1, 3), uv.reshape(-1, 2), c0, c1, idx)
    return pts, s, t


def extrude_walls(ms, ring, bottom, top, mat, collide, c0, c1, ground_ref):
    ring = np.asarray(ring, np.float64)
    if np.allclose(ring[0], ring[-1]):
        ring = ring[:-1]
    n = len(ring)
    if n < 3:
        return
    a = ring
    b = np.roll(ring, -1, axis=0)
    edge = b - a
    L = np.linalg.norm(edge, axis=1)
    ok = L > 0.05
    a, b, edge, L = a[ok], b[ok], edge[ok], L[ok]
    s0 = np.concatenate([[0.0], np.cumsum(L)[:-1]])
    m = len(a)
    # outward normal: ring orientation decides the sign
    area2 = np.sum(a[:, 0] * b[:, 1] - b[:, 0] * a[:, 1])
    sign = 1.0 if area2 > 0 else -1.0
    nx, nz = edge[:, 1] * sign, -edge[:, 0] * sign
    nl = np.maximum(np.hypot(nx, nz), 1e-9)
    nx, nz = nx / nl, nz / nl
    P = np.zeros((m, 4, 3))
    P[:, 0] = np.column_stack([a[:, 0], np.full(m, bottom), a[:, 1]])
    P[:, 1] = np.column_stack([b[:, 0], np.full(m, bottom), b[:, 1]])
    P[:, 2] = np.column_stack([b[:, 0], np.full(m, top), b[:, 1]])
    P[:, 3] = np.column_stack([a[:, 0], np.full(m, top), a[:, 1]])
    N = np.repeat(np.column_stack([nx, np.zeros(m), nz])[:, None, :], 4, axis=1)
    U = np.zeros((m, 4, 2))
    # u increases along cross(normal, up) for either ring orientation (consistent tangents)
    u0, u1 = s0 * sign, (s0 + L) * sign
    U[:, 0] = np.column_stack([u0, np.full(m, bottom - ground_ref)])
    U[:, 1] = np.column_stack([u1, np.full(m, bottom - ground_ref)])
    U[:, 2] = np.column_stack([u1, np.full(m, top - ground_ref)])
    U[:, 3] = np.column_stack([u0, np.full(m, top - ground_ref)])
    base = np.arange(m) * 4
    idx = np.concatenate([np.column_stack([base, base + 1, base + 2]), np.column_stack([base, base + 2, base + 3])])
    ms.add(mat, collide, P.reshape(-1, 3), N.reshape(-1, 3), U.reshape(-1, 2), c0, c1, idx)


def cap(ms, poly, y, mat, collide, c0, c1, up=True):
    tris = shapely.constrained_delaunay_triangles(poly)
    pts = []
    for t in shapely.get_parts(tris):
        c = np.asarray(t.exterior.coords)[:3]
        pts.append(c)
    if not pts:
        return
    T = np.asarray(pts).reshape(-1, 2)
    n = len(T)
    P = np.column_stack([T[:, 0], np.full(n, y), T[:, 1]])
    N = np.tile([0.0, 1.0 if up else -1.0, 0.0], (n, 1))
    ms.add(mat, collide, P, N, T, c0, c1, np.arange(n).reshape(-1, 3))


def instances_buffer(items):
    """MultiMesh buffer: 12 floats transform (row-major 3x4) + 4 floats colour per instance."""
    buf = np.zeros((len(items), 16), np.float32)
    for k, (x, y, z, yaw, scale, col, tilt) in enumerate(items):
        cy, sy = math.cos(yaw), math.sin(yaw)
        ct, st = math.cos(tilt), math.sin(tilt)
        # basis = Ry(yaw) * Rx(tilt) * scale; columns X, Y, Z
        X = np.array([cy, 0.0, -sy])
        Y = np.array([sy * st, ct, cy * st])
        Z = np.array([sy * ct, -st, cy * ct])
        Bm = np.column_stack([X, Y, Z]) * scale
        buf[k, 0:4] = [Bm[0, 0], Bm[0, 1], Bm[0, 2], x]
        buf[k, 4:8] = [Bm[1, 0], Bm[1, 1], Bm[1, 2], y]
        buf[k, 8:12] = [Bm[2, 0], Bm[2, 1], Bm[2, 2], z]
        buf[k, 12:16] = col
    return buf


def write_chunk(path, ms, multimeshes, boxes):
    out = io.BytesIO()
    secs = list(ms.sections())
    n_sections = len(secs) + len(multimeshes) + (1 if boxes else 0)
    out.write(struct.pack("<I", n_sections))
    verts = tris = 0
    for mat, collide, P, Nn, U, C0, C1, I in secs:
        out.write(struct.pack("<IIIII", 1, mat, int(collide), len(P), I.size))
        out.write(P.astype("<f4").tobytes()); out.write(Nn.astype("<f4").tobytes()); out.write(U.astype("<f4").tobytes())
        # Compatibility renderer ignores CUSTOM0/1, so attributes travel as COLOR (float RGBA)
        # and UV2 packing two bytes per float: uv2 = (c1.r + 256 c1.b, c1.g + 256 c1.a).
        out.write((C0.astype("<f4") / 255.0).astype("<f4").tobytes())
        C1i = C1.astype(np.float32)
        out.write(np.column_stack([C1i[:, 0] + 256 * C1i[:, 2], C1i[:, 1] + 256 * C1i[:, 3]]).astype("<f4").tobytes())
        out.write(I.astype("<u4").tobytes())
        verts += len(P); tris += I.size // 3
    for asset, items in sorted(multimeshes.items()):
        buf = instances_buffer(items)
        out.write(struct.pack("<III", 2, asset, len(items)))
        out.write(buf.astype("<f4").tobytes())
    if boxes:
        b = np.asarray(boxes, np.float32)
        out.write(struct.pack("<II", 3, len(b)))
        out.write(b.astype("<f4").tobytes())
    raw = out.getvalue()
    data = b"LKZ1" + struct.pack("<I", len(raw)) + zlib.compress(raw, 6)
    path.write_bytes(data)
    return len(data), verts, tris


# ---------------------------------------------------------------- world assembly
def main():
    t0 = time.time()
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "chunks").mkdir(exist_ok=True)
    for old in (OUT / "chunks").glob("*.bin"):
        old.unlink()
    dtm, e_first, n_first = load_dtm()
    admin, areas, ways, osm_trees, places = load_osm()
    kowloon = admin[KOWLOON_REL]
    districts = {name: admin[rid] for rid, name in DISTRICT_RELS.items()}
    fringe = kowloon.buffer(FRINGE)
    shapely.prepare(fringe)
    shapely.prepare(kowloon)
    buildings = load_buildings()

    # ---- ways: classify, clip to fringe polygon
    fb = fringe.bounds
    node_use = defaultdict(lambda: [0, 0])  # ref -> [bridge ways, ground ways]
    roads, rails, waters = [], [], []
    for w in ways:
        t = w["tags"]
        if t.get("indoor") == "yes" or t.get("area") == "yes" or "level" in t and t.get("highway") == "corridor":
            continue
        tunnel = t.get("tunnel") in ("yes", "building_passage", "culvert", "flooded") or _layer(t) < 0
        bridge = t.get("bridge") not in (None, "no") and not tunnel
        kind = None
        if t.get("highway") in ROAD_CLASSES:
            kind = "road"
        elif t.get("railway") in RAIL_TYPES:
            kind = "rail"
        elif t.get("waterway") in ("river", "canal", "drain", "stream", "ditch"):
            kind = "water"
        if kind is None:
            continue
        xz = w["xz"]
        if xz[:, 0].max() < fb[0] or xz[:, 0].min() > fb[2] or xz[:, 1].max() < fb[1] or xz[:, 1].min() > fb[3]:
            continue
        w["bridge"], w["tunnel"] = bridge, tunnel
        if kind in ("road", "rail") and not tunnel:
            for ref in (w["refs"][0], w["refs"][-1]):
                node_use[ref][0 if bridge else 1] += 1
        {"road": roads, "rail": rails, "water": waters}[kind].append(w)
    log(f"roads {len(roads)}, rails {len(rails)}, waterways {len(waters)}")

    bridge_ways = [w for w in roads + rails if w["bridge"]]
    bridge_polys = []
    for w in bridge_ways:
        width = _road_width(w)
        g = LineString(w["xz"]).buffer(width / 2 + 2.5, cap_style="flat")
        if g.intersects(fringe):
            bridge_polys.append(g)

    # ---- chunk set
    kb = fringe.bounds
    i_min, i_max = math.floor(kb[0] / CHUNK), math.floor(kb[2] / CHUNK)
    j_min, j_max = math.floor(kb[1] / CHUNK), math.floor(kb[3] / CHUNK)
    x_range = ((i_min - 1) * CHUNK, (i_max + 2) * CHUNK)
    z_range = ((j_min - 1) * CHUNK, (j_max + 2) * CHUNK)
    terr = Terrain(dtm, e_first, n_first, bridge_polys, x_range, z_range)
    log(f"terrain grid {terr.nx}x{terr.nz} at {STEP} m")

    # ---- land-use classes on the terrain grid
    cls = np.full((terr.nz, terr.nx), T_PAVED, np.uint8)
    for key, vals, c in LANDUSE_CLASS:
        geoms = [g for tags, g in areas if tags.get(key) in vals and g.intersects(fringe)]
        rasterize(cls.shape, terr.xa, terr.za, STEP, geoms, cls, c)
    water_lines = []
    for w in waters:
        if w["tunnel"]:
            continue
        width = _num(w["tags"].get("width"), {"river": 12, "canal": 10, "drain": 4, "stream": 3, "ditch": 2}[w["tags"]["waterway"]])
        g = LineString(w["xz"]).buffer(width / 2)
        if g.intersects(fringe):
            water_lines.append(g)
    rasterize(cls.shape, terr.xa, terr.za, STEP, water_lines, cls, T_WATER)

    # building and road masks on the terrain grid (for vegetation and hill classification)
    bmask = np.zeros(cls.shape, np.uint8)
    rmask = np.zeros(cls.shape, np.uint8)
    rasterize(cls.shape, terr.xa, terr.za, STEP, [b["geom"].buffer(1.5) for b in buildings], bmask, 1)
    road_geoms = []
    for w in roads:
        if w["tunnel"]:
            continue
        width = _road_width(w)
        road_geoms.append(LineString(w["xz"]).buffer(width / 2 + 0.5, cap_style="flat"))
    rasterize(cls.shape, terr.xa, terr.za, STEP, road_geoms, rmask, 1)
    near_built = ndimage.binary_dilation(bmask | rmask, iterations=6)  # 24 m
    unbuilt_high = (cls == T_PAVED) & ~near_built & (terr.h > 18) & terr.land
    cls[unbuilt_high] = T_WOOD
    steep = (terr.slope > 33) & terr.land & (bmask == 0) & (rmask == 0) & np.isin(cls, [T_PAVED, T_WOOD, T_SCRUB])
    near_urban = ndimage.binary_dilation(bmask | rmask, iterations=10)
    cls[steep & near_urban] = T_SLOPE
    cls[~terr.land] = T_SEA
    log("land-use classes: " + ", ".join(f"{k}:{int(v)}" for k, v in zip(*np.unique(cls, return_counts=True))))

    # ---- bridge deck node heights (shared by all ways at a node)
    node_deck = {}
    for w in bridge_ways:
        xz = w["xz"]
        ground = terr.at(xz[:, 0], xz[:, 1])
        raw = terr.raw_at(xz[:, 0], xz[:, 1])
        seg = np.linalg.norm(np.diff(xz, axis=0), axis=1)
        s = np.concatenate([[0.0], np.cumsum(seg)])
        total = s[-1]
        grounded0 = node_use[w["refs"][0]][1] > 0
        grounded1 = node_use[w["refs"][-1]][1] > 0
        layer = max(_layer(w["tags"]), 1)
        clearance = np.full(len(xz), 5.2 * layer)
        if grounded0:
            clearance = np.minimum(clearance, s * 0.07)
        if grounded1:
            clearance = np.minimum(clearance, (total - s) * 0.07)
        deck = np.maximum(raw, ground + clearance)
        deck = np.maximum(deck, ground + 0.25)
        for ref, h in zip(w["refs"], deck):
            node_deck[ref] = max(node_deck.get(ref, -1e9), float(h))
    for w in bridge_ways:
        w["deck"] = np.array([node_deck[r] for r in w["refs"]])

    # ---- buildings: heights, styles
    landuse_index = shapely.STRtree([g for _, g in areas])
    landuse_tags = [tags for tags, _ in areas]
    major_lines = [LineString(w["xz"]) for w in roads if not w["tunnel"] and ROAD_CLASSES[w["tags"]["highway"]][5]]
    major_tree = shapely.STRtree(major_lines)
    height_src = Counter()
    kept = []
    for b in buildings:
        g = b["geom"]
        c = g.representative_point()
        if not fringe.contains(c):
            continue
        a = b["attr"]
        ext = np.concatenate([np.asarray(p.exterior.coords) for p in shapely.get_parts(g)])
        gh = terr.at(ext[:, 0], ext[:, 1])
        gmin, gmax = float(gh.min()), float(gh.max())
        base, top, storeys = a.get("BaseHeight"), a.get("TopHeight"), a.get("Storeys")
        btype = a.get("BuildingBlockType") or "Tower"
        if base is None:
            base = gmin
        src = "surveyed"
        if top is None or top <= base + 1.0:
            if storeys:
                top, src = base + storeys * 3.0 + 1.0, "storeys"
            else:
                default = {"Podium": 9.0, "Open-sided Structure": 4.5, "Temporary Structure": 3.5}.get(btype)
                if default is None:
                    default = float(np.clip(math.sqrt(g.area) * 0.9, 6.0, 30.0))
                top, src = base + default, "inferred"
        height_src[src] += 1
        elevated = base > gmax + 1.5
        bottom = base if elevated else min(gmin, base) - 0.6
        ground_ref = base if elevated else gmin
        top = max(top, ground_ref + 2.5)
        hgt = top - ground_ref
        name = (a.get("BuildingNameEN") or "").upper()
        lu = {k for i in landuse_index.query(c, predicate="intersects") for k in landuse_tags[i].values()}
        if btype == "Open-sided Structure":
            style = STYLE_CANOPY
        elif btype == "Temporary Structure":
            style = STYLE_SHED
        elif any(k in name for k in ("INDUSTRIAL", "FACTORY", "GODOWN", "WAREHOUSE", "WORKSHOP")) or lu & {"industrial", "port"}:
            style = STYLE_INDUSTRIAL
        elif btype == "Podium":
            style = STYLE_PODIUM
        elif (" HOUSE" in name or "ESTATE" in name or " COURT" in name) and hgt > 30:
            style = STYLE_PUBLIC
        elif hgt <= 27:
            style = STYLE_TONGLAU
        elif hgt > 45 and ("CENTRE" in name or "PLAZA" in name or "TOWER" in name or "COMMERCIAL" in name or lu & {"commercial", "retail"}):
            style = STYLE_COMMERCIAL
        else:
            style = STYLE_RES
        b.update(bottom=bottom, top=top, ground=ground_ref, style=style, centroid=(c.x, c.y), hsrc=src,
                 seed=h32("b", a.get("BuildingID"), a.get("OBJECTID")))
        kept.append(b)
    buildings = kept
    log(f"buildings in coverage: {len(buildings)}; height sources {dict(height_src)}")

    # ---- generated chunk list: intersects fringe and has land or buildings
    by_chunk = defaultdict(list)
    for k, b in enumerate(buildings):
        cx, cz = b["centroid"]
        by_chunk[(math.floor(cx / CHUNK), math.floor(cz / CHUNK))].append(k)
    chunks = []
    for i in range(i_min, i_max + 1):
        for j in range(j_min, j_max + 1):
            rect = box(i * CHUNK, j * CHUNK, (i + 1) * CHUNK, (j + 1) * CHUNK)
            if not rect.intersects(fringe):
                continue
            iz0, ix0 = terr.index(i * CHUNK, j * CHUNK)
            has_land = terr.land[iz0 : iz0 + CHUNK // STEP + 1, ix0 : ix0 + CHUNK // STEP + 1].any()
            if has_land or (i, j) in by_chunk:
                chunks.append((i, j))
    log(f"chunks to generate: {len(chunks)}")

    # ---- clip linear features per chunk
    road_lines = defaultdict(list)
    for w in roads + rails:
        if w["tunnel"]:
            continue
        line = LineString(w["xz"])
        if not line.intersects(fringe):
            continue
        minx, minz, maxx, maxz = line.bounds
        for i in range(math.floor(minx / CHUNK) - 1, math.floor(maxx / CHUNK) + 2):
            for j in range(math.floor(minz / CHUNK) - 1, math.floor(maxz / CHUNK) + 2):
                road_lines[(i, j)].append(w)

    building_tree = shapely.STRtree([b["geom"] for b in buildings])
    road_poly_tree = shapely.STRtree(road_geoms)
    chunk_set = set(chunks)
    index_chunks = {}
    safe_points = {}
    totals = Counter()
    for n_done, (i, j) in enumerate(chunks):
        rect = box(i * CHUNK, j * CHUNK, (i + 1) * CHUNK, (j + 1) * CHUNK)
        near, far = MeshSet(), MeshSet()
        mm_near, mm_far = defaultdict(list), defaultdict(list)
        boxes = []
        inside = fringe.contains(rect)
        build_terrain(near, terr, cls, i, j, STEP, skirt=0.0)
        build_terrain(far, terr, cls, i, j, FAR_STEP, skirt=4.0)
        # linear features
        for w in road_lines.get((i, j), []):
            clipped = shapely.clip_by_rect(LineString(w["xz"]), *rect.bounds)
            if not inside:
                clipped = clipped.intersection(fringe)
            for part in shapely.get_parts(clipped):
                if part.geom_type != "LineString" or part.length < 0.5:
                    continue
                build_linear(near, far, mm_near, boxes, terr, w, np.asarray(part.coords), i, j, building_tree)
        # buildings
        for k in by_chunk.get((i, j), []):
            build_building(near, far, boxes, buildings[k], major_tree, major_lines, mm_near)
        totals["buildings"] += len(by_chunk.get((i, j), []))
        # vegetation and props
        place_vegetation(mm_near, mm_far, terr, cls, i, j, building_tree, road_poly_tree, osm_trees, boxes)
        sp = safe_spawns(terr, road_lines.get((i, j), []), rect, building_tree, fringe)
        if sp:
            safe_points[f"{i}_{j}"] = sp
        nb, nv, nt = write_chunk(OUT / "chunks" / f"n_{i}_{j}.bin", near, mm_near, boxes)
        fb, fv, ft = write_chunk(OUT / "chunks" / f"f_{i}_{j}.bin", far, mm_far, [])
        index_chunks[f"{i}_{j}"] = {"i": i, "j": j, "near_bytes": nb, "far_bytes": fb, "near_tris": nt,
                                    "far_tris": ft, "buildings": len(by_chunk.get((i, j), [])),
                                    "trees": sum(len(mm_near[a]) for a in (A_BANYAN, A_SLENDER))}
        totals["near_bytes"] += nb; totals["far_bytes"] += fb
        totals["near_tris"] += nt; totals["far_tris"] += ft
        totals["instances"] += sum(len(v) for v in mm_near.values())
        if n_done % 50 == 0:
            log(f"chunk {n_done}/{len(chunks)} ({i},{j}) near {nb // 1024} KiB far {fb // 1024} KiB")

    # ---- background terrain, overview map, jump points, index
    bg_bytes = build_background(terr, dtm, e_first, n_first, chunk_set)
    map_info = build_overview(kowloon, districts, terr, cls, buildings, roads, rails, chunks)
    jumps = jump_points(places, kowloon, districts, safe_points, terr)
    land_k = _land_polygon(terr).intersection(kowloon)
    stats = {
        "kowloon_area_km2": round(kowloon.area / 1e6, 2),
        "kowloon_land_area_km2": round(land_k.area / 1e6, 2),
        "chunks": len(chunks),
        "buildings_emitted": totals["buildings"],
        "building_height_sources": dict(height_src),
        "road_ways": len([w for w in roads if not w["tunnel"]]),
        "bridge_ways": len(bridge_ways),
        "tunnel_ways_omitted": len([w for w in roads + rails if w["tunnel"]]),
        "near_bytes": totals["near_bytes"], "far_bytes": totals["far_bytes"], "background_bytes": bg_bytes,
        "near_tris": totals["near_tris"], "far_tris": totals["far_tris"], "near_instances": totals["instances"],
        "per_district": district_stats(districts, buildings, roads),
    }
    index = {
        "format": 1,
        "origin_hk1980": [E0, N0],
        "axes": "x = E - E0 (east), z = N0 - N (south), y = mPD",
        "chunk_size": CHUNK, "terrain_step": STEP, "far_terrain_step": FAR_STEP, "sea_level": SEA_LEVEL,
        "grid": {"i_min": i_min, "i_max": i_max, "j_min": j_min, "j_max": j_max},
        "coverage_name": "Kowloon (OSM relation 10268797: Yau Tsim Mong, Sham Shui Po, Kowloon City, Wong Tai Sin, Kwun Tong districts)",
        "coverage_polygon": _rings(kowloon.simplify(12)),
        "boundary_polygon": _rings(kowloon.buffer(FRINGE - 20).simplify(12)),
        "districts": [{"name": n, "polygon": _rings(g.simplify(15)), "centroid": [round(g.centroid.x, 1), round(g.centroid.y, 1)]}
                      for n, g in districts.items()],
        "jump_points": jumps,
        "safe_points": safe_points,
        "chunks": index_chunks,
        "map": map_info,
        "stats": stats,
        "inputs": {s["id"]: s["sha256"] for s in json.loads((ROOT / "assets-source/kowloon/sources.json").read_text())["sources"]},
    }
    (OUT / "world_index.json").write_text(json.dumps(index, separators=(",", ":")))
    log(f"done in {time.time() - t0:.0f}s: {json.dumps({k: v for k, v in stats.items() if k != 'per_district'})}")


def _rings(g):
    out = []
    for p in shapely.get_parts(g):
        if p.geom_type == "Polygon" and p.area > 2000:
            out.append([[round(x, 1), round(z, 1)] for x, z in p.exterior.coords])
    return out


def _land_polygon(terr):
    # land outline traced from the node grid at 4 m
    from shapely import box as sbox
    cells = []
    land = terr.land
    for r in range(land.shape[0]):
        row = land[r]
        if not row.any():
            continue
        edges = np.flatnonzero(np.diff(np.concatenate([[0], row.astype(np.int8), [0]])))
        for a, b in zip(edges[::2], edges[1::2]):
            cells.append(sbox(terr.xa + a * STEP - STEP / 2, terr.za + r * STEP - STEP / 2,
                              terr.xa + b * STEP - STEP / 2, terr.za + r * STEP + STEP / 2))
    return unary_union(cells)


def _layer(t):
    try:
        return int(float(t.get("layer", 0)))
    except ValueError:
        return 0


def _num(v, default):
    try:
        return float(str(v).replace("m", "").strip())
    except (TypeError, ValueError):
        return float(default)


def _road_width(w):
    t = w["tags"]
    if "railway" in t and "highway" not in t:
        return 3.6
    base = ROAD_CLASSES[t["highway"]][0]
    if "width" in t:
        return float(np.clip(_num(t["width"], base), 1.5, 30))
    if "lanes" in t and ROAD_CLASSES[t["highway"]][1] == M_ROAD:
        return float(np.clip(_num(t["lanes"], 2) * 3.3, 3.3, 30))
    return base


def build_terrain(ms, terr, cls, i, j, step, skirt):
    k = step // STEP
    n = CHUNK // step + 1
    iz0, ix0 = terr.index(i * CHUNK, j * CHUNK)
    rows = iz0 + np.arange(n) * k
    colsx = ix0 + np.arange(n) * k
    H = terr.h[np.ix_(rows, colsx)]
    Nn = terr.normal[np.ix_(rows, colsx)]
    C = cls[np.ix_(rows, colsx)]
    S = terr.slope[np.ix_(rows, colsx)]
    xs = i * CHUNK + np.arange(n) * step
    zs = j * CHUNK + np.arange(n) * step
    X, Z = np.meshgrid(xs, zs)
    veg = np.array([T_COLORS[c][1] for c in range(12)])
    weights = np.array([T_WEIGHTS[c] for c in range(12)])
    c0 = np.clip(weights[C] * 255, 0, 255).astype(np.uint8)
    c1 = np.stack([C.astype(np.uint8), np.clip(S * 2.8, 0, 255).astype(np.uint8),
                   np.clip(veg[C] * 255, 0, 255).astype(np.uint8), np.full_like(C, 255, np.uint8)], axis=-1)
    pos = np.stack([X, H, Z], axis=-1).reshape(-1, 3)
    uv = np.stack([X, Z], axis=-1).reshape(-1, 2)
    g = np.arange(n * n).reshape(n, n)
    a, b, c, d = g[:-1, :-1].ravel(), g[:-1, 1:].ravel(), g[1:, :-1].ravel(), g[1:, 1:].ravel()
    # split along (0,0)-(1,1), matching Terrain.at
    idx = np.concatenate([np.column_stack([a, b, d]), np.column_stack([a, d, c])])
    ms.add(M_TERRAIN, step == STEP, pos, Nn.reshape(-1, 3), uv, c0.reshape(-1, 4), c1.reshape(-1, 4), idx)
    if skirt > 0:
        for edge in (g[0, :], g[-1, :], g[:, 0], g[:, -1]):
            p = pos[edge]
            low = p.copy(); low[:, 1] -= skirt
            P = np.concatenate([p, low])
            m = len(edge)
            e = np.arange(m - 1)
            I = np.concatenate([np.column_stack([e, e + 1, e + m + 1]), np.column_stack([e, e + m + 1, e + m])])
            N = np.tile([0.0, 1.0, 0.0], (2 * m, 1))
            ms.add(M_TERRAIN, False, P, N, np.concatenate([uv[edge], uv[edge]]), np.concatenate([c0.reshape(-1, 4)[edge]] * 2),
                   np.concatenate([c1.reshape(-1, 4)[edge]] * 2), I)


def build_linear(near, far, mm, boxes, terr, w, coords, ci, cj, building_tree=None):
    t = w["tags"]
    is_rail = "highway" not in t
    width = _road_width(w)
    if is_rail:
        mat, offset, code, sidewalks, major = M_RAIL, 0.2, 10, False, False
    else:
        _, mat, offset, code, sidewalks, major = ROAD_CLASSES[t["highway"]]
        if t.get("sidewalk") in ("no", "none", "separate"):
            sidewalks = False
    lanes = int(_num(t.get("lanes"), 2 if code >= 4 else 1))
    c0 = (code * 20, min(lanes, 8) * 30, int(min(width, 25) * 10), 255)
    c1 = (1 if w["bridge"] else 0, 0, 0, 255)
    if w["bridge"]:
        xz_full = w["xz"]
        seg = np.linalg.norm(np.diff(xz_full, axis=0), axis=1)
        s_full = np.concatenate([[0.0], np.cumsum(seg)])
        line_full = LineString(xz_full)
        deck_nodes = w["deck"]

        def deck_fn(X, Z, S):
            proj = shapely.line_locate_point(line_full, shapely.points(X.ravel(), Z.ravel())).reshape(X.shape)
            h = np.interp(proj, s_full, deck_nodes)
            return np.maximum(h, terr.at(X, Z) + 0.25)

        res = ribbon(near, coords, width, deck_fn, mat, True, c0, c1, 0.0)
        if res is None:
            return
        pts, s, tan = res
        line_pts = np.asarray(coords)
        thick = 1.2 if (is_rail or code >= 3) else 0.6
        # underside and parapets
        ribbon(near, coords, width, lambda X, Z, S: deck_fn(X, Z, S) - thick, M_CONCRETE, False, (120, 118, 112, 255), (0, 0, 0, 255), 0.0)
        deck_c = deck_fn(pts[:, 0], pts[:, 1], s)
        side = np.column_stack([-tan[:, 1], tan[:, 0]])
        for sgn in (-1, 1):
            edge = pts + side * (sgn * (width / 2 - 0.15))
            _wall_strip(near, edge, deck_c - thick, deck_c + 1.05, M_CONCRETE, True)
        # far: deck slab only
        ribbon(far, coords, width, deck_fn, M_CONCRETE, False, (120, 118, 112, 255), (0, 0, 0, 255), 0.0, max_step=12.0)
        # piers
        spacing = 18.0 if code >= 3 or is_rail else 14.0
        for k in range(len(pts)):
            if k % max(1, int(spacing / 3.0)) != 0:
                continue
            g = float(terr.at(pts[k, 0], pts[k, 1]))
            top = deck_c[k] - thick
            if top - g < 2.5:
                continue
            half = 0.7 if code >= 3 or is_rail else 0.25
            yaw = math.atan2(tan[k, 0], tan[k, 1])
            box_mesh(near, M_CONCRETE, True, (pts[k, 0], (top + g - 1) / 2, pts[k, 1]), (half * (2.5 if code >= 6 else 1), (top - g + 1) / 2, half), yaw,
                     (128, 125, 118, 255))
        heights_fn = deck_fn
    else:
        def heights_fn(X, Z, S):
            return terr.at(X, Z)

        res = ribbon(near, coords, width, heights_fn, mat, False, c0, c1, offset)
        if res is None:
            return
        pts, s, tan = res
        if sidewalks:
            side = np.column_stack([-tan[:, 1], tan[:, 0]])
            for sgn in (-1, 1):
                ribbon(near, pts + side * sgn * (width / 2 + 1.6), 3.2, heights_fn, M_PAVING, False, (20, 30, 32, 255), (0, 0, 0, 255), 0.10)
    if is_rail:
        side = np.column_stack([-tan[:, 1], tan[:, 0]])
        for sgn in (-1, 1):
            ribbon(near, pts + side * sgn * 0.75, 0.12, heights_fn, M_PROP, False, (70, 62, 55, 255), (0, 0, 0, 255), offset + 0.18)
        return
    # props along roads (deterministic)
    if code >= 5 and not w["bridge"]:
        side = np.column_stack([-tan[:, 1], tan[:, 0]])
        step_n = max(1, int(36 / 3.0))
        for k in range(step_n // 2, len(pts), step_n):
            hh = h32("lamp", w["id"], round(pts[k, 0]), round(pts[k, 1]))
            if hh % 5 == 0:
                continue
            p = pts[k] + side[k] * (width / 2 + 0.9)
            y = float(terr.at(p[0], p[1]))
            yaw = math.atan2(-side[k, 0], -side[k, 1])
            tilt = ((hh >> 8) % 100 - 50) / 50.0 * 0.07
            mm[A_LAMP].append((p[0], y, p[1], yaw, 1.0, (0.36, 0.37, 0.35, 1.0), tilt))
            boxes.append((p[0], y + 3.5, p[1], 0.12, 3.5, 0.12, 0.0))
    # street trees in planters along both kerbs, decades overgrown
    if code >= 4 and not w["bridge"] and building_tree is not None:
        side = np.column_stack([-tan[:, 1], tan[:, 0]])
        for k in range(2, len(pts), 5):
            for sgn in (-1, 1):
                hh = h32("st", w["id"], k, sgn)
                if hh % 100 >= 42:
                    continue
                p = pts[k] + side[k] * sgn * (width / 2 + 2.6)
                if len(building_tree.query(Point(p).buffer(2.5), predicate="intersects")):
                    continue
                y = float(terr.at(p[0], p[1]))
                kind = A_BANYAN if (hh >> 8) % 100 < 55 else A_SLENDER
                sc = 0.6 + ((hh >> 12) % 60) / 100.0
                mm[kind].append((p[0], y - 0.1, p[1], (hh % 628) / 100.0, sc, (1.0, 1.0, 1.0, 1.0), 0.0))
                boxes.append((p[0], y + 1.5, p[1], 0.35 * sc, 1.5, 0.35 * sc, 0.0))
                for g in range(3):
                    hg = h32("stg", w["id"], k, sgn, g)
                    mm[A_GRASS].append((p[0] + ((hg % 100) - 50) / 40.0, y, p[1] + (((hg >> 8) % 100) - 50) / 40.0, (hg % 628) / 100.0, 0.8, (1.0, 1.0, 1.0, 1.0), 0.0))
    if code >= 3 and len(pts) > 3:
        spacing = 70.0
        for k in range(0, len(pts), max(1, int(spacing / 3.0))):
            hh = h32("car", w["id"], round(pts[k, 0]), round(pts[k, 1]))
            if hh % 100 > 30:
                continue
            lane = ((hh >> 7) % 2 * 2 - 1) * width * 0.22
            side = np.array([-tan[k, 1], tan[k, 0]])
            p = pts[k] + side * lane
            y = float(heights_fn(np.array([p[0]]), np.array([p[1]]), np.array([s[k]]))[0]) + (offset if not w["bridge"] else 0)
            yaw = math.atan2(tan[k, 0], tan[k, 1]) + ((hh >> 9) % 100 - 50) / 50.0 * 0.25
            kind = A_BUS if (hh >> 12) % 100 < 9 and code >= 5 else A_CAR
            palette = [(0.55, 0.53, 0.48), (0.42, 0.45, 0.47), (0.58, 0.24, 0.18), (0.62, 0.60, 0.52), (0.30, 0.33, 0.30), (0.62, 0.55, 0.34)]
            col = palette[(hh >> 15) % len(palette)] if kind == A_CAR else (0.62, 0.58, 0.45)
            mm[kind].append((p[0], y, p[1], yaw, 1.0, (*col, 1.0), 0.0))
            if kind == A_BUS:
                boxes.append((p[0], y + 2.2, p[1], 1.25, 2.2, 5.6, yaw))
            else:
                boxes.append((p[0], y + 0.75, p[1], 0.9, 0.75, 2.2, yaw))


def _wall_strip(ms, edge, y0, y1, mat, collide):
    n = len(edge)
    if n < 2:
        return
    P = np.concatenate([np.column_stack([edge[:, 0], y0, edge[:, 1]]), np.column_stack([edge[:, 0], y1, edge[:, 1]])])
    d = np.gradient(edge, axis=0)
    nrm = np.column_stack([d[:, 1], np.zeros(n), -d[:, 0]])
    nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-9)
    e = np.arange(n - 1)
    I = np.concatenate([np.column_stack([e, e + 1, e + n + 1]), np.column_stack([e, e + n + 1, e + n])])
    I = np.concatenate([I, I[:, ::-1]])  # double-sided parapet
    P = np.concatenate([P, P])
    N = np.concatenate([nrm, nrm, -nrm, -nrm])
    I2 = I.copy()
    I2[len(I) // 2 :] += 2 * n
    uv = np.zeros((4 * n, 2))
    ms.add(mat, collide, P, N, uv, (124, 121, 114, 255), (0, 0, 0, 255), I2)


STYLE_TINTS = {
    # mosaic-tile and painted towers: beige, salmon, mint, butter yellow, powder blue, grey
    STYLE_RES: [(0.80, 0.74, 0.62), (0.82, 0.62, 0.54), (0.62, 0.76, 0.66), (0.84, 0.78, 0.52), (0.62, 0.70, 0.80),
                (0.70, 0.70, 0.68), (0.78, 0.66, 0.70), (0.74, 0.62, 0.48)],
    # tong lau: faded paint over render, ochre, green, rust, grey
    STYLE_TONGLAU: [(0.66, 0.58, 0.44), (0.56, 0.64, 0.52), (0.70, 0.54, 0.44), (0.60, 0.60, 0.58), (0.72, 0.66, 0.50),
                    (0.52, 0.60, 0.64), (0.70, 0.50, 0.50)],
    STYLE_INDUSTRIAL: [(0.68, 0.66, 0.58), (0.74, 0.70, 0.56), (0.58, 0.62, 0.62), (0.66, 0.60, 0.52)],
    # public estates: pastel bands
    STYLE_PUBLIC: [(0.86, 0.80, 0.66), (0.70, 0.80, 0.74), (0.86, 0.70, 0.62), (0.72, 0.76, 0.86), (0.88, 0.84, 0.60)],
    STYLE_PODIUM: [(0.60, 0.59, 0.56), (0.66, 0.63, 0.57), (0.55, 0.55, 0.54), (0.64, 0.56, 0.50)],
    STYLE_COMMERCIAL: [(0.40, 0.44, 0.47), (0.50, 0.50, 0.49), (0.36, 0.40, 0.42), (0.56, 0.54, 0.50)],
    STYLE_CANOPY: [(0.55, 0.55, 0.52)],
    STYLE_SHED: [(0.50, 0.48, 0.42), (0.45, 0.47, 0.46), (0.52, 0.42, 0.36)],
}
SIGN_COLORS = [(150, 60, 52), (196, 186, 160), (170, 140, 70), (70, 90, 110), (150, 150, 140), (110, 50, 60), (60, 100, 80)]


def build_building(near, far, boxes, b, major_tree, major_lines, mm):
    g, style, seed = b["geom"], b["style"], b["seed"]
    bottom, top, ground = b["bottom"], b["top"], b["ground"]
    tints = STYLE_TINTS[style]
    tint = tints[seed % len(tints)]
    shade = 0.92 + ((seed >> 4) % 16) / 100.0
    c0 = tuple(int(min(255, v * shade * 255)) for v in tint) + (style * 32 + 16,)
    flags = (1 if style in (STYLE_TONGLAU, STYLE_COMMERCIAL, STYLE_PODIUM) else 0) | (2 if (seed >> 10) % 100 < 12 and style in (STYLE_TONGLAU, STYLE_SHED, STYLE_INDUSTRIAL) else 0)
    c1 = ((seed >> 16) % 256, int(np.clip((top - ground) * 0.5, 0, 255)), flags, 255)
    roof_c0 = (int(tint[0] * 150), int(tint[1] * 148), int(tint[2] * 140), style * 32 + 16)
    for poly in shapely.get_parts(g):
        p = poly.simplify(0.25)
        if p.is_empty or p.area < 2.0 or p.geom_type != "Polygon":
            continue
        if style == STYLE_CANOPY:
            slab_bot = top - 0.45
            for ring in [p.exterior]:
                extrude_walls(near, ring.coords, slab_bot, top, M_CONCRETE, True, (128, 126, 120, 255), c1, ground)
            cap(near, p, top, M_ROOF, True, roof_c0, c1)
            cap(near, p, slab_bot, M_CONCRETE, False, (100, 98, 94, 255), c1, up=False)
            ring = np.asarray(p.exterior.coords)[:-1]
            for k in range(0, len(ring), max(1, len(ring) // 4)):
                x, z = ring[k]
                box_mesh(near, M_CONCRETE, True, (x, (slab_bot + bottom) / 2, z), (0.15, (slab_bot - bottom) / 2, 0.15), 0.0, (120, 118, 112, 255))
            cap(far, p.simplify(1.0), top, M_ROOF, False, roof_c0, c1)
            continue
        for ring in [p.exterior, *p.interiors]:
            extrude_walls(near, ring.coords, bottom, top, M_FACADE, True, c0, c1, ground)
        cap(near, p, top, M_ROOF, True, roof_c0, c1)
        pf = p.simplify(1.5)
        if not pf.is_empty and pf.geom_type == "Polygon":
            extrude_walls(far, pf.exterior.coords, bottom, top, M_FACADE, False, c0, c1, ground)
            cap(far, pf, top, M_ROOF, False, roof_c0, c1)
        # rooftop structures on towers
        if style in (STYLE_RES, STYLE_PUBLIC, STYLE_INDUSTRIAL, STYLE_COMMERCIAL, STYLE_TONGLAU) and p.area > 90:
            rp = p.representative_point()
            n_struct = 1 + (seed >> 3) % 2
            for k in range(n_struct):
                hh = h32("roof", seed, k)
                ox, oz = ((hh % 100) - 50) / 50.0 * math.sqrt(p.area) * 0.18, (((hh >> 8) % 100) - 50) / 50.0 * math.sqrt(p.area) * 0.18
                sx, sz, sy = 1.5 + (hh >> 16) % 3, 1.5 + (hh >> 18) % 3, 1.2 + ((hh >> 20) % 3) * 0.8
                cx, cz = rp.x + ox, rp.y + oz
                if p.contains(box(cx - sx, cz - sz, cx + sx, cz + sz)):
                    box_mesh(near, M_CONCRETE, True, (cx, top + sy, cz), (sx, sy, sz), 0.0, (int(tint[0] * 170), int(tint[1] * 168), int(tint[2] * 160), 255))
        # hanging street signs and concrete shop canopies on buildings facing major roads
        if style in (STYLE_TONGLAU, STYLE_RES, STYLE_COMMERCIAL, STYLE_PODIUM) and top - ground > 8:
            add_signs(near, p, ground, top, seed, major_tree, major_lines, mm)
        add_ivy(near, p, ground, top, seed, style)
        add_roof_garden(mm, p, ground, top, seed, style)


def add_signs(ms, p, ground, top, seed, major_tree, major_lines, mm):
    ring = np.asarray(p.exterior.coords)
    area2 = np.sum(ring[:-1, 0] * ring[1:, 1] - ring[1:, 0] * ring[:-1, 1])
    sign = 1.0 if area2 > 0 else -1.0
    count = 0
    for k in range(len(ring) - 1):
        a, b = ring[k], ring[k + 1]
        L = float(np.hypot(*(b - a)))
        if L < 5:
            continue
        mid = (a + b) / 2
        out = np.array([(b - a)[1], -(b - a)[0]]) * sign / L
        probe = Point(mid + out * 8)
        near_idx = major_tree.query(probe, predicate="dwithin", distance=6.0)
        if len(near_idx) == 0:
            continue
        if style_canopy_ok(seed, k) and L > 4:
            yaw_c = math.atan2(out[0], out[1])
            depth_c = 1.6 + (h32("cn", seed, k) % 100) / 100.0
            cc = mid + out * (depth_c / 2)
            box_mesh(ms, M_CONCRETE, True, (cc[0], ground + 3.7, cc[1]), (L * 0.46, 0.14, depth_c / 2), yaw_c, (132, 128, 120, 255))
            # weeds and ferns rooted in the debris on top of the canopy
            for q in range(int(L // 3)):
                hq = h32("cng", seed, k, q)
                if hq % 3 == 0:
                    continue
                t = ((hq >> 4) % 100) / 100.0
                pt = a + (b - a) * (0.06 + 0.88 * t) + out * (0.3 + ((hq >> 11) % 100) / 100.0 * (depth_c - 0.6))
                kind = A_FERN if hq % 5 == 1 else A_GRASS
                mm[kind].append((pt[0], ground + 3.84, pt[1], (hq % 628) / 100.0, 0.7 + ((hq >> 17) % 60) / 100.0, (1.0, 1.0, 1.0, 1.0), 0.0))
        n_signs = int(min(3, L // 7))
        for q in range(n_signs):
            hh = h32("sign", seed, k, q)
            if hh % 100 < 35:
                continue
            f = 0.15 + 0.7 * ((hh >> 7) % 100) / 100.0
            pos = a + (b - a) * f
            depth = 1.0 + ((hh >> 13) % 100) / 100.0 * 2.2
            height = 1.4 + ((hh >> 17) % 100) / 100.0 * 3.2
            y0 = ground + 4.0 + ((hh >> 21) % 100) / 100.0 * min(10.0, max(0.5, top - ground - 10))
            if y0 + height > top - 0.5:
                continue
            centre = pos + out * (depth / 2 + 0.1)
            yaw = math.atan2(out[0], out[1])
            col = SIGN_COLORS[(hh >> 25) % len(SIGN_COLORS)]
            box_mesh(ms, M_PROP, False, (centre[0], y0 + height / 2, centre[1]), (0.12, height / 2, depth / 2), yaw, (*col, 255))
            # mounting arm
            box_mesh(ms, M_PROP, False, (centre[0], y0 + height + 0.05, centre[1]), (0.04, 0.04, depth / 2 + 0.1), yaw, (70, 68, 64, 255))
            count += 1
            if count >= 6:
                return


VEG = {
    # class: (tree prob, shrub prob, grass prob)
    T_PAVED: (0.005, 0.035, 0.20),
    T_PARK: (0.09, 0.18, 0.95),
    T_WOOD: (0.24, 0.22, 0.12),
    T_SCRUB: (0.045, 0.40, 0.95),
    T_SAND: (0.0, 0.01, 0.06),
    T_WATER: (0.01, 0.10, 0.40),
    T_INDUSTRIAL: (0.008, 0.04, 0.12),
    T_SEA: (0.0, 0.0, 0.0),
    T_PITCH: (0.004, 0.05, 0.6),
    T_RAIL: (0.004, 0.08, 0.30),
    T_CEMETERY: (0.05, 0.12, 0.40),
    T_SLOPE: (0.02, 0.08, 0.14),
}


def place_vegetation(mm_near, mm_far, terr, cls, i, j, building_tree, road_poly_tree, osm_trees, boxes):
    n = CHUNK // STEP
    iz0, ix0 = terr.index(i * CHUNK, j * CHUNK)
    C = cls[iz0 : iz0 + n, ix0 : ix0 + n]
    rng = np.random.default_rng(h32("veg", i, j))
    X = i * CHUNK + (np.arange(n)[None, :] + rng.random((n, n))) * STEP
    Z = j * CHUNK + (np.arange(n)[:, None] + rng.random((n, n))) * STEP
    # low-frequency "neglect" field so growth clusters rather than spreading evenly
    neglect = 0.5 + 0.5 * np.sin(X * 0.031 + 1.7 * np.sin(Z * 0.017)) * np.cos(Z * 0.027 + 0.9 * np.sin(X * 0.021))
    probs = np.array([VEG[c] for c in range(12)])
    pt, ps, pg = probs[C][..., 0], probs[C][..., 1], probs[C][..., 2]
    boost = np.where(np.isin(C, [T_PAVED, T_INDUSTRIAL]), 0.3 + 1.6 * neglect, 0.7 + 0.6 * neglect)
    r = rng.random((n, n))
    kind = np.full((n, n), -1)
    kind[r < (pt + ps + pg) * boost] = A_GRASS
    kind[r < (pt + ps) * boost] = A_SHRUB
    kind[r < pt * boost] = A_BANYAN
    sel = kind >= 0
    xs, zs, ks = X[sel], Z[sel], kind[sel]
    # OSM-mapped street and park trees
    m = (osm_trees[:, 0] >= i * CHUNK) & (osm_trees[:, 0] < (i + 1) * CHUNK) & (osm_trees[:, 1] >= j * CHUNK) & (osm_trees[:, 1] < (j + 1) * CHUNK)
    xs = np.concatenate([xs, osm_trees[m, 0]]); zs = np.concatenate([zs, osm_trees[m, 1]]); ks = np.concatenate([ks, np.full(int(m.sum()), A_BANYAN)])
    if len(xs) == 0:
        return
    pts = shapely.points(xs, zs)
    blocked = np.zeros(len(xs), bool)
    hit = building_tree.query(pts, predicate="intersects")
    blocked[hit[0]] = True
    road_hit = road_poly_tree.query(pts, predicate="intersects")
    on_road = np.zeros(len(xs), bool)
    on_road[road_hit[0]] = True
    # grass survives in road edges/cracks; shrubs and trees do not
    blocked |= on_road & (ks != A_GRASS)
    ys = terr.at(xs, zs)
    underwater = ys < SEA_LEVEL + 0.3
    blocked |= underwater
    for k in np.flatnonzero(~blocked):
        x, z, y, a = float(xs[k]), float(zs[k]), float(ys[k]), int(ks[k])
        hh = h32("v", round(x, 1), round(z, 1))
        c_here = int(cls[terr.index(x, z)])
        yaw = (hh % 628) / 100.0
        u = ((hh >> 10) % 1000) / 1000.0
        if a == A_BANYAN:
            c = int(cls[terr.index(x, z)])
            a = A_SLENDER if (c == T_WOOD and u < 0.65) or (c != T_WOOD and u < 0.4) else A_BANYAN
            scale = 0.7 + 0.6 * ((hh >> 20) % 100) / 100.0
            tint = (0.85 + 0.2 * u, 0.9 + 0.15 * ((hh >> 5) % 10) / 10.0, 0.8 + 0.2 * u, 1.0)
            tilt = (((hh >> 3) % 100) - 50) / 50.0 * 0.06
            mm_near[a].append((x, y - 0.1, z, yaw, scale, tint, tilt))
            mm_far[A_BLOB].append((x, y - 0.1, z, yaw, scale * (1.25 if a == A_BANYAN else 0.95), tint, 0.0))
            if scale > 0.9:
                boxes.append((x, y + 1.5, z, 0.3 * scale, 1.5, 0.3 * scale, 0.0))
        elif a == A_SHRUB:
            if u < 0.35:
                a = A_FERN
            scale = 0.6 + 0.8 * ((hh >> 20) % 100) / 100.0
            mm_near[a].append((x, y - 0.05, z, yaw, scale, (0.9 + 0.2 * u, 0.95, 0.85, 1.0), 0.0))
        else:
            scale = 0.6 + 0.7 * ((hh >> 20) % 100) / 100.0
            if c_here in (T_PARK, T_SCRUB, T_CEMETERY, T_PITCH, T_WATER):
                scale *= 1.7  # uncut meadow grass, knee to waist high
            mm_near[A_GRASS].append((x, y + (0.12 if on_road[k] else 0.0), z, yaw, scale, (0.95 + 0.15 * u, 0.95 + 0.1 * u, 0.8, 1.0), 0.0))


def safe_spawns(terr, ways, rect, building_tree, fringe):
    pts = []
    for w in ways:
        t = w["tags"]
        if "highway" not in t or w["bridge"] or w["tunnel"] or ROAD_CLASSES[t["highway"]][3] < 1:
            continue
        line = shapely.clip_by_rect(LineString(w["xz"]), *rect.bounds)
        for part in shapely.get_parts(line):
            if part.geom_type != "LineString" or part.length < 8:
                continue
            p = part.interpolate(0.5, normalized=True)
            if not fringe.contains(p) or len(building_tree.query(p.buffer(2.0), predicate="intersects")):
                continue
            pts.append((h32("sp", w["id"], round(p.x), round(p.y)), p.x, p.y))
    pts.sort()
    out = []
    for _, x, z in pts[:4]:
        out.append([round(x, 2), round(float(terr.at(x, z)) + 0.4, 2), round(z, 2)])
    return out


def build_background(terr, dtm, e_first, n_first, chunk_set):
    ms = MeshSet()
    E = np.arange(BG_E[0], BG_E[1] + 1, BG_STEP)
    N = np.arange(BG_N[1], BG_N[0] - 1, -BG_STEP)
    EE, NN = np.meshgrid(E, N)
    col = (EE - e_first) / 5.0
    row = (n_first - NN) / 5.0
    H = ndimage.map_coordinates(dtm, [row, col], order=1, mode="nearest").astype(np.float64)
    land = H > 0.05
    dist = ndimage.distance_transform_edt(~land) * BG_STEP
    H = np.where(land, np.maximum(H, SEA_LEVEL + 0.6), SEA_LEVEL - 1.6 - np.minimum(dist * 0.06, 12))
    X, Z = local_xy(EE, NN)
    ci, cj = np.floor(X / CHUNK).astype(int), np.floor(Z / CHUNK).astype(int)
    inside = np.array([[(a, b) in chunk_set for a, b in zip(r1, r2)] for r1, r2 in zip(ci, cj)])
    H = np.where(inside, H - 8.0, H)  # sits below streamed chunks
    gz, gx = np.gradient(H, BG_STEP)
    nrm = np.stack([-gx, np.ones_like(gx), -gz], axis=-1)
    nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)
    slope = np.degrees(np.arccos(nrm[..., 1]))
    urban_low = (H < 45) & land
    rgb = np.where(urban_low[..., None], np.array([0.40, 0.40, 0.38]), np.array([0.20, 0.26, 0.14]))
    rgb = np.where((slope > 38)[..., None] & land[..., None], np.array([0.42, 0.40, 0.33]), rgb)
    rgb = np.where(~land[..., None], np.array([0.15, 0.17, 0.15]), rgb)
    c0 = np.concatenate([rgb * 255, np.full(H.shape + (1,), 128)], axis=-1).astype(np.uint8)
    nz, nx = H.shape
    pos = np.stack([X, H, Z], axis=-1).reshape(-1, 3)
    g = np.arange(nz * nx).reshape(nz, nx)
    a, b, c, d = g[:-1, :-1].ravel(), g[:-1, 1:].ravel(), g[1:, :-1].ravel(), g[1:, 1:].ravel()
    idx = np.concatenate([np.column_stack([a, b, d]), np.column_stack([a, d, c])])
    ms.add(M_TERRAIN, False, pos, nrm.reshape(-1, 3), pos[:, [0, 2]], c0.reshape(-1, 4), (T_WOOD, 0, 1, 255), idx)
    size, _, _ = write_chunk(OUT / "background.bin", ms, {}, [])
    return size


def build_overview(kowloon, districts, terr, cls, buildings, roads, rails, chunks):
    mpp = 6.0
    minx, minz, maxx, maxz = kowloon.buffer(500).bounds
    W, H = int((maxx - minx) / mpp), int((maxz - minz) / mpp)
    img = Image.new("RGB", (W, H), (34, 44, 48))
    d = ImageDraw.Draw(img)

    def px(coords):
        c = np.asarray(coords)
        return [((x - minx) / mpp, (z - minz) / mpp) for x, z in c[:, :2]]

    # land from terrain classes
    xs = minx + (np.arange(W) + 0.5) * mpp
    zs = minz + (np.arange(H) + 0.5) * mpp
    ix = np.clip(((xs - terr.xa) / STEP).round().astype(int), 0, terr.nx - 1)
    iz = np.clip(((zs - terr.za) / STEP).round().astype(int), 0, terr.nz - 1)
    C = cls[np.ix_(iz, ix)]
    pal = np.array([[96, 94, 88], [86, 104, 62], [58, 78, 50], [100, 98, 70], [150, 140, 110], [52, 70, 72],
                    [92, 88, 82], [34, 44, 48], [80, 100, 66], [90, 84, 78], [86, 100, 70], [120, 116, 104]], np.uint8)
    arr = pal[C]
    outside = ~shapely.contains_xy(kowloon, *np.meshgrid(xs, zs))
    arr[outside] = (arr[outside] * 0.55).astype(np.uint8)
    img = Image.fromarray(arr, "RGB")
    d = ImageDraw.Draw(img)
    for w in roads:
        if w["tunnel"]:
            continue
        code = ROAD_CLASSES[w["tags"]["highway"]][3]
        if code < 2:
            continue
        d.line(px(w["xz"]), fill=(196, 188, 160) if code >= 6 else (160, 156, 140), width=3 if code >= 7 else (2 if code >= 5 else 1))
    for w in rails:
        if not w["tunnel"]:
            d.line(px(w["xz"]), fill=(150, 110, 90), width=2)
    for b in buildings:
        for p in shapely.get_parts(b["geom"]):
            if p.geom_type == "Polygon" and p.area > 30:
                v = int(np.clip(70 + (b["top"] - b["ground"]) * 0.6, 70, 190))
                d.polygon(px(p.exterior.coords), fill=(v, v - 6, v - 14))
    for n, g in districts.items():
        for p in shapely.get_parts(g):
            d.line(px(p.exterior.coords), fill=(150, 150, 150), width=1)
    for p in shapely.get_parts(kowloon):
        d.line(px(p.exterior.coords), fill=(224, 170, 70), width=3)
    rgba = np.asarray(img.convert("RGBA"), np.uint8)
    raw = rgba.tobytes()
    (OUT / "overview_map.bin").write_bytes(b"LKM1" + struct.pack("<III", W, H, len(raw)) + zlib.compress(raw, 6))
    img.save(CACHE / "overview_map.png")
    return {"file": "overview_map.bin", "x0": minx, "z0": minz, "m_per_px": mpp, "width": W, "height": H}


def jump_points(places, kowloon, districts, safe_points, terr):
    allpts = [(k, p) for k, lst in safe_points.items() for p in lst]
    arr = np.array([[p[0], p[2]] for _, p in allpts])
    out = []
    seen = []
    order = sorted(places, key=lambda p: (p[1] != "suburb", p[0]))
    for name, kind, x, z in order:
        if not kowloon.contains(Point(x, z)) or any(math.hypot(x - a, z - b) < 450 for a, b in seen) or name in [o["name"] for o in out]:
            continue
        k = int(np.argmin(np.hypot(arr[:, 0] - x, arr[:, 1] - z)))
        sx, sy, sz = allpts[k][1]
        district = next((n for n, g in districts.items() if g.contains(Point(x, z))), "")
        out.append({"name": name, "kind": kind, "district": district, "pos": [sx, sy, sz]})
        seen.append((x, z))
    return out


def district_stats(districts, buildings, roads):
    out = {}
    for n, g in districts.items():
        shapely.prepare(g)
        nb = sum(1 for b in buildings if g.contains(Point(b["centroid"])))
        km = sum(LineString(w["xz"]).intersection(g).length for w in roads if not w["tunnel"]) / 1000
        out[n] = {"buildings": nb, "road_km": round(km, 1), "area_km2": round(g.area / 1e6, 2)}
    return out




def style_canopy_ok(seed, k):
    return h32("canopy", seed, k) % 100 < 55


IVY_CHANCE = {STYLE_TONGLAU: 38, STYLE_SHED: 55, STYLE_INDUSTRIAL: 30, STYLE_PODIUM: 34, STYLE_RES: 14,
              STYLE_PUBLIC: 10, STYLE_COMMERCIAL: 6, STYLE_CANOPY: 0}


def add_ivy(ms, p, ground, top, seed, style):
    """Ivy/creeper curtains: hanging from parapets and climbing from wall bases on some walls."""
    chance = IVY_CHANCE.get(style, 10)
    if chance == 0:
        return
    ring = np.asarray(p.exterior.coords)
    area2 = np.sum(ring[:-1, 0] * ring[1:, 1] - ring[1:, 0] * ring[:-1, 1])
    sign = 1.0 if area2 > 0 else -1.0
    height = top - ground
    for k in range(len(ring) - 1):
        a, b = ring[k], ring[k + 1]
        L = float(np.hypot(*(b - a)))
        hh = h32("ivy", seed, k)
        if L < 2.5 or hh % 100 >= chance:
            continue
        d = (b - a) / L
        out = np.array([d[1], -d[0]]) * sign
        w = min(L, 2.5 + ((hh >> 7) % 100) / 100.0 * 9.0)
        f0 = ((hh >> 14) % 100) / 100.0 * (L - w)
        p0 = a + d * f0 + out * 0.12
        p1 = p0 + d * w
        hanging = (hh >> 21) % 3 != 0 or height < 6
        if hanging:
            length = min(height - 0.3, 3.0 + ((hh >> 23) % 100) / 100.0 * min(22.0, height))
            y_top, y_bot = top + 0.5, top - length
        else:
            length = min(height - 0.5, 2.5 + ((hh >> 23) % 100) / 100.0 * 9.0)
            y_top, y_bot = ground + length, ground - 0.3
        P = np.array([[p0[0], y_bot, p0[1]], [p1[0], y_bot, p1[1]], [p1[0], y_top, p1[1]], [p0[0], y_top, p0[1]]])
        n = np.array([out[0], 0.0, out[1]])
        u0, u1 = f0 / 5.0, (f0 + w) / 5.0
        span = (y_top - y_bot) / 10.0
        if hanging:
            U = np.array([[u0, span], [u1, span], [u1, 0.0], [u0, 0.0]])
        else:  # climbing: dense part of the texture at the ground
            U = np.array([[u0, 0.0], [u1, 0.0], [u1, span], [u0, span]])
        ms.add(M_IVY, False, P, np.tile(n, (4, 1)), U, (255, 255, 255, 255), ((hh >> 9) % 256, 0, 0, 255),
               np.array([[0, 1, 2], [0, 2, 3]]))


def add_roof_garden(mm, p, ground, top, seed, style):
    """Self-seeded growth on low and mid-rise roofs: grass, ferns, shrubs, the odd young tree."""
    if style in (STYLE_CANOPY,) or top - ground > 45 or p.area < 25:
        return
    hh = h32("roofg", seed)
    if hh % 100 >= (60 if style in (STYLE_TONGLAU, STYLE_SHED, STYLE_INDUSTRIAL, STYLE_PODIUM) else 30):
        return
    minx, minz, maxx, maxz = p.bounds
    count = int(min(30, p.area / 18))
    prepared = shapely.prepared.prep(p.buffer(-0.8))
    for q in range(count * 2):
        hq = h32("rg", seed, q)
        x = minx + (hq % 10000) / 10000.0 * (maxx - minx)
        z = minz + ((hq >> 13) % 10000) / 10000.0 * (maxz - minz)
        if not prepared.contains(Point(x, z)):
            continue
        r = (hq >> 26) % 64
        kind = A_SLENDER if r < 3 else (A_SHRUB if r < 18 else (A_FERN if r < 32 else A_GRASS))
        scale = (0.45 + ((hq >> 3) % 40) / 100.0) if kind == A_SLENDER else 0.6 + ((hq >> 5) % 70) / 100.0
        mm[kind].append((x, top, z, (hq % 628) / 100.0, scale, (1.0, 1.0, 1.0, 1.0), 0.0))
        count -= 1
        if count <= 0:
            break

if __name__ == "__main__":
    sys.exit(main())
