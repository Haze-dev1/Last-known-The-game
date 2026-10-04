"""Validate generated world data: bounds, scale, building counts, coverage, chunk seams.

Usage: uv run python validate.py   (after build.py). Exit code 1 on any failure.
Writes game/world/data/validation_report.json.
"""
import json
import struct
import sys
import zlib
from pathlib import Path

import numpy as np
import shapely
from shapely.geometry import box

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "game/world/data"
failures = []
report = {}


def check(ok, label):
    print(("PASS: " if ok else "FAIL: ") + label)
    if not ok:
        failures.append(label)


def read_chunk(path):
    packed = path.read_bytes()
    assert packed[:4] == b"LKZ1"
    raw = zlib.decompress(packed[8:])
    assert len(raw) == struct.unpack_from("<I", packed, 4)[0]
    at = 4
    meshes, mms, boxes = [], [], None
    for _ in range(struct.unpack_from("<I", raw, 0)[0]):
        kind = struct.unpack_from("<I", raw, at)[0]
        if kind == 1:
            _, mat, collide, nv, ni = struct.unpack_from("<IIIII", raw, at)
            at += 20
            pos = np.frombuffer(raw, "<f4", nv * 3, at).reshape(-1, 3)
            at += nv * (12 + 12 + 8 + 16 + 8)
            idx = np.frombuffer(raw, "<u4", ni, at)
            at += ni * 4
            meshes.append((mat, collide, pos, idx))
        elif kind == 2:
            _, asset, count = struct.unpack_from("<III", raw, at)
            at += 12
            mms.append((asset, np.frombuffer(raw, "<f4", count * 16, at).reshape(-1, 16)))
            at += count * 64
        elif kind == 3:
            _, count = struct.unpack_from("<II", raw, at)
            at += 8
            boxes = np.frombuffer(raw, "<f4", count * 7, at).reshape(-1, 7)
            at += count * 28
        else:
            raise ValueError(f"unknown section {kind} in {path.name}")
    assert at == len(raw), f"trailing bytes in {path.name}"
    return meshes, mms, boxes


def main():
    index = json.loads((DATA / "world_index.json").read_text())
    cs = index["chunk_size"]
    step = index["terrain_step"]
    chunks = index["chunks"]
    stats = index["stats"]
    E0, N0 = index["origin_hk1980"]

    # --- coverage: chunk squares cover every land cell of the Kowloon polygon
    cover = shapely.union_all([box(c["i"] * cs, c["j"] * cs, (c["i"] + 1) * cs, (c["j"] + 1) * cs) for c in chunks.values()])
    kowloon = shapely.union_all([shapely.Polygon(r) for r in index["coverage_polygon"]])
    missing = kowloon.difference(cover)
    report["polygon_area_outside_chunks_m2"] = round(missing.area, 1)
    # uncovered parts must be sea: sample them on a 10 m grid against the DTM land mask
    d = np.load(Path(__file__).resolve().parent / ".cache/dtm_crop.npz")
    dtm, e_first, n_first = d["h"], float(d["e_first"]), float(d["n_first"])
    mx0, mz0, mx1, mz1 = missing.bounds
    X, Z = np.meshgrid(np.arange(mx0, mx1, 10.0), np.arange(mz0, mz1, 10.0))
    inside = shapely.contains_xy(missing, X, Z)
    col = ((X[inside] + E0 - e_first) / 5).round().astype(int)
    row = ((n_first - (N0 - Z[inside])) / 5).round().astype(int)
    land_missing = int((dtm[row, col] > 0.05).sum()) * 100
    report["uncovered_polygon_land_m2"] = land_missing
    check(land_missing == 0, f"chunks cover all land in the Kowloon polygon (uncovered sea {missing.area / 1e6:.2f} km2, uncovered land {land_missing} m2)")

    # --- per-chunk parse, bounds, terrain seams
    edges = {}
    max_overflow = 0.0
    max_other = 0.0
    tri_total = 0
    min_y, max_y = 1e9, -1e9
    terrain_vertex_count = (cs // step + 1) ** 2
    bad_terrain = 0
    for key, c in chunks.items():
        i, j = c["i"], c["j"]
        meshes, mms, boxes = read_chunk(DATA / "chunks" / f"n_{key}.bin")
        read_chunk(DATA / "chunks" / f"f_{key}.bin")
        for mat, collide, pos, idx in meshes:
            tri_total += len(idx) // 3
            assert idx.max() < len(pos)
            dx = np.maximum(np.maximum(i * cs - pos[:, 0], pos[:, 0] - (i + 1) * cs), 0)
            dz = np.maximum(np.maximum(j * cs - pos[:, 2], pos[:, 2] - (j + 1) * cs), 0)
            o = float(np.max(np.maximum(dx, dz)))
            if mat in (3, 4, 6, 7, 8):  # facades, roofs, canopies/rooftop structures, signs, ivy
                max_overflow = max(max_overflow, o)
            else:
                max_other = max(max_other, o)
            min_y, max_y = min(min_y, float(pos[:, 1].min())), max(max_y, float(pos[:, 1].max()))
            if mat == 0:
                if len(pos) != terrain_vertex_count:
                    bad_terrain += 1
                    continue
                n = cs // step + 1
                g = pos.reshape(n, n, 3)
                edges[(i, j)] = {"w": g[:, 0], "e": g[:, -1], "n": g[0, :], "s": g[-1, :]}
    report["max_building_overflow_m"] = round(max_overflow, 1)
    report["max_other_overflow_m"] = round(max_other, 1)
    report["height_range_mpd"] = [round(min_y, 1), round(max_y, 1)]
    check(bad_terrain == 0, "every near chunk has one complete terrain grid")
    check(max_other < 30, f"terrain, roads, paving and rail stay within 30 m of their chunk ({max_other:.1f} m)")
    check(max_overflow < 400, f"building-attached geometry (assigned by footprint centroid) overflows by at most {max_overflow:.1f} m (largest Kai Tak/industrial footprints)")
    check(-30 < min_y and max_y < 700, f"heights plausible for Kowloon in mPD ({min_y:.1f} .. {max_y:.1f})")
    seam_err = 0.0
    seams = 0
    for (i, j), e in edges.items():
        if (i + 1, j) in edges:
            seam_err = max(seam_err, float(np.abs(e["e"] - edges[(i + 1, j)]["w"]).max())); seams += 1
        if (i, j + 1) in edges:
            seam_err = max(seam_err, float(np.abs(e["s"] - edges[(i, j + 1)]["n"]).max())); seams += 1
    report["terrain_seams_checked"] = seams
    report["terrain_seam_max_error_m"] = seam_err
    check(seams > 1500 and seam_err == 0.0, f"terrain edges identical across {seams} shared chunk seams (max error {seam_err})")

    # --- buildings and scale against the source snapshot
    src = json.loads((ROOT / "assets-source/kowloon/raw/landsd_buildings_kowloon.json").read_text())
    tops = [f["attributes"]["TopHeight"] for f in src["features"] if f["attributes"].get("TopHeight")]
    report["source_max_top_height_mpd"] = max(tops)
    check(stats["buildings_emitted"] == sum(c["buildings"] for c in chunks.values()), "building count in index equals per-chunk sum")
    check(stats["buildings_emitted"] > 25000, f"building coverage plausible ({stats['buildings_emitted']} footprints in the coverage polygon + fringe)")
    check(max_y >= max(tops) - 1.0, f"tallest generated geometry reaches the tallest surveyed roof ({max(tops)} mPD)")
    # scale: local coordinates are HK1980 metres minus the origin; check a known span
    span = (843347 - 831472)  # Kowloon polygon east-west extent from OSM relation bounds (HK1980)
    kb = kowloon.bounds
    report["polygon_extent_m"] = [round(kb[2] - kb[0], 1), round(kb[3] - kb[1], 1)]
    check(abs((kb[2] - kb[0]) - span) < 30, f"metric scale preserved (east-west extent {kb[2] - kb[0]:.0f} m vs {span} m)")
    report["jump_points"] = len(index["jump_points"])
    check(len(index["jump_points"]) >= 20, "district jump points generated")
    for jp in index["jump_points"]:
        x, _, z = jp["pos"]
        if not shapely.contains_xy(kowloon.buffer(index["chunk_size"]), x, z):
            check(False, f"jump point {jp['name']} inside coverage")
    report["near_triangles"] = tri_total
    report["failures"] = failures
    (DATA / "validation_report.json").write_text(json.dumps(report, indent=1))
    print(f"VALIDATION: {len(failures)} failures")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
