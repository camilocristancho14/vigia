#!/usr/bin/env python3
"""Measures how big the puffle is in every clip of the existing atlases and
writes it into puffles.json, so every clip can be drawn at the same body size.

build_puffles.py scales each clip by its own body (BODY = 0.74 of the cell),
but the sleep, doze and still frames, the clips with thought bubbles and the
ones whose motion fills the cell end up with a much smaller puffle in them.
This reads only the large (80 px) atlases — nothing is redrawn — and adds,
per clip and for the still frame:

    body       how big the puffle is, in large-atlas pixels: the median, over
               the clip's frames, of the square root of its body's opaque area
               (alpha > 24). Area, not height: the orange puffle's spiky hair
               makes it taller than the others for a smaller body, and a
               squashed jump or a puffle lying asleep keep their area
    bodyScale  how much the clip must be scaled for its puffle to be as big
               as the variant's idle one (idle body / body)
    box        the union of every frame's alpha box: everything that moves,
               Zs, bubbles and props included, [x0, y0, x1, y1]
    bodyBox    the union of the body's boxes alone, which must never be cut —
               leaving out a frame where a prop has stuck to it

The body in a frame is its connected blob standing lowest in the cell among
the big ones, once anything joined to it by a thin line has been cut away
(`OPEN`): Zs, sparkles and dirt are smaller, a dream or thought bubble
floats above the puffle, and a prop it holds or bounces is let go. `PuffleLayout` in PuffleMarks.swift turns
these into a scale and an offset for whatever box a mark is drawn in.

Usage: measure_bodies.py [resources dir]   (default Sources/Pulse/Resources)
"""
import json
import os
import statistics
import sys

from PIL import Image, ImageChops, ImageFilter

ALPHA = 24


def blobs(mask):
    """Every connected blob of a 0/255 mask: (area, box, pixels)."""
    width, height = mask.size
    px = mask.load()
    seen = bytearray(width * height)
    found = []
    for y in range(height):
        for x in range(width):
            if not px[x, y] or seen[y * width + x]:
                continue
            seen[y * width + x] = 1
            stack, pixels = [(x, y)], []
            x0 = x1 = x
            y0 = y1 = y
            while stack:
                cx, cy = stack.pop()
                pixels.append((cx, cy))
                x0, x1, y0, y1 = min(x0, cx), max(x1, cx), min(y0, cy), max(y1, cy)
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if 0 <= nx < width and 0 <= ny < height and not seen[ny * width + nx] and px[nx, ny]:
                        seen[ny * width + nx] = 1
                        stack.append((nx, ny))
            found.append((len(pixels), (x0, y0, x1 + 1, y1 + 1), pixels))
    return found


# How far a prop may touch the puffle and still be told apart from it: the
# mask is eroded by this many pixels before its blobs are found, so a thought
# bubble, a spray of dirt or a ball joined to the puffle by a thin line or a
# corner comes away; the puffle's blob is then grown back by as much, within
# its own pixels.
OPEN = 2


def body_blob(cell):
    """The puffle alone: (area, box) of its opaque pixels."""
    mask = cell.getchannel("A").point(lambda a: 255 if a > ALPHA else 0)
    size = 2 * OPEN + 1
    found = blobs(mask.filter(ImageFilter.MinFilter(size)))
    if not found:
        found = blobs(mask)
        if not found:
            return None
    biggest = max(b[0] for b in found)
    big = [b for b in found if b[0] >= biggest * 0.25]
    # Lowest first; between two on the same floor, the bigger.
    blob = max(big, key=lambda b: (b[1][3], b[0]))
    core = Image.new("L", mask.size, 0)
    for xy in blob[2]:
        core.putpixel(xy, 255)
    body = ImageChops.multiply(core.filter(ImageFilter.MaxFilter(size)), mask)
    box = body.getbbox()
    area = sum(1 for v in body.getdata() if v)
    return area, box


def union(a, b):
    return b if a is None else [min(a[0], b[0]), min(a[1], b[1]), max(a[2], b[2]), max(a[3], b[3])]


def measure(atlas, columns, cell, indices, window=False):
    sizes, box, bodies = [], None, []
    for i in indices:
        x, y = (i % columns) * cell, (i // columns) * cell
        frame = atlas.crop((x, y, x + cell, y + cell))
        bbox = frame.getchannel("A").point(lambda a: 255 if a > ALPHA else 0).getbbox()
        if not bbox:
            continue
        box = union(box, list(bbox))
        area, blob = body_blob(frame)
        sizes.append(area ** 0.5)
        bodies.append((area, blob))
    if not sizes:
        return None
    # A frame where a prop is still part of the puffle's blob — a bubble
    # coming off its head, a ball it lands on, a rope of light — is far wider
    # or taller than the puffle is in the rest of the clip, and bigger: its
    # box is left out of where the puffle goes, so the prop does not shrink
    # the clip.
    width = statistics.median(b[2] - b[0] for _, b in bodies)
    height = statistics.median(b[3] - b[1] for _, b in bodies)
    area = statistics.median(a for a, _ in bodies)
    if window:
        # A dig is filmed by a fixed camera on where the puffle starts, and
        # it dives out of that frame in a blur of dirt: where it goes is
        # where it stands, and the dive runs off the edge, as in the atlas.
        first = bodies[0][1]
        width, height = first[2] - first[0], first[3] - first[1]
    body_box = None
    for a, b in bodies:
        if window and (abs(b[2] - b[0] - width) > width * 0.15 or abs(b[3] - b[1] - height) > height * 0.15):
            continue
        # A spin stretches the puffle tall, motion lines and all, and that
        # is the puffle; a ball or a rope beside it makes it wider and
        # bigger, and that is a prop.
        wider = b[2] - b[0] > width * 1.3 and a > area * 1.2
        taller = b[3] - b[1] > height * 1.3 and a > area * 1.5
        if not (wider or taller):
            body_box = union(body_box, list(b))
    return {"body": round(statistics.median(sizes), 2), "box": box, "bodyBox": body_box}


def main(resources):
    path = os.path.join(resources, "puffles.json")
    with open(path) as f:
        manifest = json.load(f)
    for variant in manifest["variants"]:
        cell, columns = variant["large"], variant["columns"]
        atlas = Image.open(os.path.join(resources, f"puffle-{variant['id']}-large.png")).convert("RGBA")
        metrics = {}
        for name, clip in variant["clips"].items():
            metrics[name] = measure(atlas, columns, cell, range(clip["start"], clip["start"] + clip["count"]),
                                    window=name == "dig")
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
