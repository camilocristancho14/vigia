#!/usr/bin/env python3
"""Measures how big the puffle is in every clip of the existing atlases and
writes it into puffles.json, so every clip can be drawn at the same body size.

build_puffles.py scales each clip by its own body (BODY = 0.74 of the cell),
but the sleep, doze and still frames, the clips with thought bubbles and the
ones whose motion fills the cell end up with a much smaller puffle in them.
This reads only the large (80 px) atlases — nothing is redrawn — and adds,
per clip and for the still frame:

    body       the puffle's height in large-atlas pixels: the median, over the
               clip's frames, of its body's alpha box (alpha > 24)
    bodyScale  how much the clip must be scaled for its puffle to be as big
               as the variant's idle one (idle body / body)
    box        the union of every frame's alpha box: everything that moves,
               Zs, bubbles and props included, [x0, y0, x1, y1]
    bodyBox    the union of the body's boxes alone, which must never be cut

The body in a frame is its connected blob standing lowest in the cell among
the big ones: Zs, sparkles and dirt are smaller, and a dream or thought
bubble floats above the puffle. `PuffleLayout` in PuffleMarks.swift turns
these into a scale and an offset for whatever box a mark is drawn in.

Usage: measure_bodies.py [resources dir]   (default Sources/Pulse/Resources)
"""
import json
import os
import statistics
import sys

from PIL import Image

ALPHA = 24


def blobs(cell):
    """Every connected blob of opaque pixels: (area, (x0, y0, x1, y1))."""
    alpha = cell.getchannel("A")
    width, height = alpha.size
    px = alpha.load()
    seen = bytearray(width * height)
    found = []
    for y in range(height):
        for x in range(width):
            if px[x, y] <= ALPHA or seen[y * width + x]:
                continue
            seen[y * width + x] = 1
            stack, area = [(x, y)], 0
            x0 = x1 = x
            y0 = y1 = y
            while stack:
                cx, cy = stack.pop()
                area += 1
                x0, x1, y0, y1 = min(x0, cx), max(x1, cx), min(y0, cy), max(y1, cy)
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if 0 <= nx < width and 0 <= ny < height and not seen[ny * width + nx] \
                            and px[nx, ny] > ALPHA:
                        seen[ny * width + nx] = 1
                        stack.append((nx, ny))
            found.append((area, (x0, y0, x1 + 1, y1 + 1)))
    return found


def body_blob(cell):
    found = blobs(cell)
    if not found:
        return None
    biggest = max(area for area, _ in found)
    big = [b for b in found if b[0] >= biggest * 0.25]
    # Lowest first; between two on the same floor, the bigger.
    return max(big, key=lambda b: (b[1][3], b[0]))[1]


def union(a, b):
    return b if a is None else [min(a[0], b[0]), min(a[1], b[1]), max(a[2], b[2]), max(a[3], b[3])]


def measure(atlas, columns, cell, indices):
    heights, box, body_box = [], None, None
    for i in indices:
        x, y = (i % columns) * cell, (i // columns) * cell
        frame = atlas.crop((x, y, x + cell, y + cell))
        bbox = frame.getchannel("A").point(lambda a: 255 if a > ALPHA else 0).getbbox()
        if not bbox:
            continue
        box = union(box, list(bbox))
        blob = body_blob(frame)
        heights.append(blob[3] - blob[1])
        body_box = union(body_box, list(blob))
    if not heights:
        return None
    return {"body": round(statistics.median(heights), 1), "box": box, "bodyBox": body_box}


def main(resources):
    path = os.path.join(resources, "puffles.json")
    with open(path) as f:
        manifest = json.load(f)
    for variant in manifest["variants"]:
        cell, columns = variant["large"], variant["columns"]
        atlas = Image.open(os.path.join(resources, f"puffle-{variant['id']}-large.png")).convert("RGBA")
        metrics = {}
        for name, clip in variant["clips"].items():
            metrics[name] = measure(atlas, columns, cell, range(clip["start"], clip["start"] + clip["count"]))
        still = measure(atlas, columns, cell, [variant["still"]])
        reference = metrics["idle"]["body"]
        for name, clip in variant["clips"].items():
            m = metrics[name]
            clip.update(body=m["body"], bodyScale=round(reference / m["body"], 4),
                        box=m["box"], bodyBox=m["bodyBox"])
        variant["stillMetrics"] = dict(body=still["body"], bodyScale=round(reference / still["body"], 4),
                                       box=still["box"], bodyBox=still["bodyBox"])
        print(f"{variant['id']:22s} " + " ".join(
            f"{n}:{c['bodyScale']:.2f}" for n, c in variant["clips"].items()), file=sys.stderr)
    with open(path, "w") as f:
        json.dump(manifest, f, ensure_ascii=False, separators=(",", ":"))


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "..", "..", "Sources", "Pulse", "Resources"))
