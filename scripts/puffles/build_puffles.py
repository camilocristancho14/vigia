#!/usr/bin/env python3
"""Builds Vigía's puffle atlases from the original Club Penguin SWFs.

Input: the frames JPEXS ffdec exported from every puffle SWF in the Wayback
Machine's copy of media1.clubpenguin.com (fetch_swfs.py, extract_frames.sh):

    <frames>/<swf name>/DefineSprite_<n>/<frame>.png

Output, into Sources/Pulse/Resources:

    puffle-<variant>-small.png   44 px cells: the menu bar's 22 pt at 2x
    puffle-<variant>-large.png   80 px cells: the rail's rings and settings
    puffles.json                 where every clip sits in the atlases

**No pixel is drawn here.** Frames are picked, put in order, cropped,
scaled down, centred in their cell and palettised for size. Every clip is
one of the game's own symbols, or a run of consecutive frames from one.

Usage: build_puffles.py <frames dir> <resources dir> [--report report.json]
"""
import glob
import json
import math
import os
import re
import sys
from collections import defaultdict

from PIL import Image

SMALL, LARGE = 44, 80
# The puffle's body fills this much of its cell; the rest is room to move.
BODY = 0.74
# Clips longer than this are sampled more sparsely, to keep the atlas small.
MAX_FRAMES = 40
SOURCE_FPS = 25.0

COLORS = ["blue", "pink", "black", "green", "purple", "red", "yellow", "white",
          "orange", "brown", "gold", "rainbow"]
NAMES = {
    "blue": ("Blue", "Azul"), "pink": ("Pink", "Rosado"), "black": ("Black", "Negro"),
    "green": ("Green", "Verde"), "purple": ("Purple", "Morado"), "red": ("Red", "Rojo"),
    "yellow": ("Yellow", "Amarillo"), "white": ("White", "Blanco"), "orange": ("Orange", "Naranja"),
    "brown": ("Brown", "Café"), "gold": ("Gold", "Dorado"), "rainbow": ("Rainbow", "Arcoíris"),
}
# What each creature puffle is, from looking at its frames.
CREATURES = json.load(open(os.path.join(os.path.dirname(__file__), "creatures.json")))

TRICKS = {"jumpForward": "jump", "jumpSpin": "spin", "nuzzle": "nuzzle", "roll": "roll",
          "speak": "speak", "standOnHead": "headstand"}
# Puffle Park's swing, post and hydrant and the hotel's dive are left out:
# their props dwarf the puffle, which is a speck at 22 points.
SINGLES = {  # file pattern -> clip
    "hotelcare__weightlifting__puffle_{id}_weightlifting": "lift",
    "eat__puffle_{id}_eat": "eat",
    "animation__splash__puffle_{id}_splash": "splash",
}


def sprites(swf_dir):
    """The symbols of one SWF with at least two frames, in symbol order."""
    out = []
    for path in glob.glob(os.path.join(swf_dir, "DefineSprite_*")):
        tail = os.path.basename(path)[len("DefineSprite_"):]
        frames = sorted(glob.glob(os.path.join(path, "*.png")),
                        key=lambda p: int(os.path.basename(p)[:-4]))
        if len(frames) < 2:
            continue
        number = int(re.match(r"\d+", tail).group())
        out.append({"path": path, "name": os.path.basename(path), "number": number,
                    "named": not tail.isdigit(), "frames": frames})
    return sorted(out, key=lambda s: s["number"])


_bbox_cache = {}


def bbox(frame_path):
    if frame_path not in _bbox_cache:
        image = Image.open(frame_path).convert("RGBA")
        _bbox_cache[frame_path] = image.getchannel("A").point(lambda a: 255 if a > 24 else 0).getbbox()
    return _bbox_cache[frame_path]


def body_size(frames):
    """How big the puffle is in a clip, from its smaller frames."""
    sides = sorted(max(b[2] - b[0], b[3] - b[1]) for b in (bbox(f) for f in frames) if b)
    return sides[len(sides) // 10] if sides else 0


def clip(frames, step=None, fps=None):
    step = step or max(2, math.ceil(len(frames) / MAX_FRAMES))
    picked = frames[::step]
    return {"frames": picked, "fps": fps or SOURCE_FPS / step}


def library_roles(swf_dir, roles, body_hint=None):
    """Idle, look, walks, sleep and the moods from a walk, igloo or base SWF."""
    sps = sprites(swf_dir)
    eights = [s for s in sps if len(s["frames"]) == 8 and not s["named"]]
    twelves = [s for s in sps if len(s["frames"]) == 12 and not s["named"]]
    if len(eights) < 5:
        return
    front = eights[0]["frames"]
    reference = body_size(front)

    def puffle_sized(s):
        b = bbox(s["frames"][0])
        if not b:
            return False
        side = max(b[2] - b[0], b[3] - b[1])
        return 0.7 * reference <= side <= 1.5 * reference

    if "idle" not in roles:
        # Facing out, breathing and blinking, twice through.
        roles["idle"] = {"frames": front + front, "fps": 12.5}
        # Head turned three-quarters, then to the side, and back: the
        # direction clips the game turned a puffle with, in a row.
        q, side = eights[1]["frames"], eights[2]["frames"]
        roles["look"] = {"frames": front[:4] + q[:4] + side + side + q[:4] + front[:4], "fps": 12.5}
    if len(twelves) >= 3:
        roles.setdefault("walk", clip(twelves[0]["frames"], step=1, fps=12.5))
        roles.setdefault("walkSide", clip(twelves[2]["frames"], step=1, fps=12.5))

    sized = [s for s in sps if not s["named"] and puffle_sized(s)]
    def stays(s):
        # Asleep where it lay all the way through: the gold puffle's long
        # clip vanishes in a shower of sparkles instead.
        n = len(s["frames"])
        return body_size(s["frames"][n * 3 // 10:n * 8 // 10]) >= 0.6 * reference

    sleepers = [s for s in sized if 195 <= len(s["frames"]) <= 370 and stays(s)]
    if sleepers and "sleep" not in roles:
        frames = sleepers[0]["frames"]
        n = len(frames)
        doze_end, wake_start = round(n * 0.07), round(n * 0.9)
        roles["doze"] = clip(frames[:doze_end], step=1, fps=12.5)
        roles["sleep"] = clip(frames[doze_end:wake_start], step=4)
        roles["wake"] = clip(frames[wake_start:], step=1, fps=12.5)
        roles["_still"] = frames[doze_end + 2]
    for count, role in ((64, "bounce"), (167, "yawn"), (85, "hungry"), (45, "sick")):
        if role in roles:
            continue
        found = [s for s in sized if len(s["frames"]) == count]
        if found:
            roles[role] = clip(found[0]["frames"])


def trick(swf_dir):
    """The full-size copy of a trick: each SWF carries a small one too."""
    sps = [s for s in sprites(swf_dir) if not s["named"]]
    if not sps:
        return None
    # Sparkles and props can have more frames; the puffle is the biggest.
    sps = [s for s in sps if len(s["frames"]) >= 20] or sps
    best = max(sps, key=lambda s: body_size(s["frames"][:1]))
    return best["frames"]


def dig(swf_dir):
    sps = [s for s in sprites(swf_dir) if not s["named"]]
    if not sps:
        return None
    best = max(sps, key=lambda s: len(s["frames"]) * math.sqrt(max(body_size(s["frames"][:3]), 1)))
    return best["frames"]


def single(swf_dir):
    sps = [s for s in sprites(swf_dir) if not s["named"]]
    if not sps:
        return None
    return max(sps, key=lambda s: len(s["frames"]))["frames"]


def discover(frames_dir):
    ids = set()
    for name in os.listdir(frames_dir):
        m = re.search(r"puffle_([a-z]+)(\d*)_", name + "_")
        if m and m.group(1) in COLORS:
            ids.add(m.group(1) + m.group(2))
        elif name in COLORS:
            ids.add(name)
    return ids


def roles_for(frames_dir, pid):
    color = re.match(r"[a-z]+", pid).group()
    roles, sources = {}, defaultdict(list)

    def mark(role_names, swf):
        for r in role_names:
            sources[r].append(swf)

    libs = [f"walk__puffle_{pid}_walk", f"igloo__puffle_{pid}_igloo"]
    if pid == color:
        libs.append(color)
    for lib in libs:
        path = os.path.join(frames_dir, lib)
        if os.path.isdir(path):
            before = set(roles)
            library_roles(path, roles)
            mark(set(roles) - before, lib)
    for swf, role in TRICKS.items():
        path = os.path.join(frames_dir, f"tricks__puffle_{pid}_{swf}")
        if os.path.isdir(path):
            frames = trick(path)
            if frames:
                roles[role] = clip(frames)
                mark([role], os.path.basename(path))
    path = os.path.join(frames_dir, f"dig__puffle_{pid}_dig")
    if os.path.isdir(path):
        frames = dig(path)
        if frames:
            roles["dig"] = dict(clip(frames), first=True)
            mark(["dig"], os.path.basename(path))
    for pattern, role in SINGLES.items():
        path = os.path.join(frames_dir, pattern.format(id=pid))
        if os.path.isdir(path):
            frames = single(path)
            if frames:
                roles[role] = dict(clip(frames), first=True)
                mark([role], os.path.basename(path))
    # No walk, igloo or base library survived for the brown puffle: it rests
    # on the opening frames of its own speak trick, before it starts talking.
    if "idle" not in roles and "speak" in roles:
        opening = roles["speak"]["frames"][:4]
        roles["idle"] = {"frames": opening * 2, "fps": 6.25}
        sources["idle"] = sources["speak"]
    return roles, sources


def place(frames, cell, scale):
    """Each frame scaled by `scale` and set in a square cell, the clip's
    motion kept wherever it fits."""
    boxes = [bbox(f) or (0, 0, 1, 1) for f in frames]
    union = (min(b[0] for b in boxes), min(b[1] for b in boxes),
             max(b[2] for b in boxes), max(b[3] for b in boxes))
    widest = max(b[2] - b[0] for b in boxes) * scale
    tallest = max(b[3] - b[1] for b in boxes) * scale
    # A frame bigger than the cell — a headstand, a leap — shrinks the clip.
    shrink = min(1.0, cell * 0.98 / max(widest, tallest, 1))
    s = scale * shrink
    keep_x = (union[2] - union[0]) * s <= cell * 0.98
    keep_y = (union[3] - union[1]) * s <= cell * 0.98
    out = []
    for f, b in zip(frames, boxes):
        image = Image.open(f).convert("RGBA")
        x0 = union[0] if keep_x else b[0]
        x1 = union[2] if keep_x else b[2]
        y0 = union[1] if keep_y else b[1]
        y1 = union[3] if keep_y else b[3]
        # Crop to the clip's span (or the frame's), scale, centre.
        crop = image.crop((x0, y0, x1, y1))
        w, h = max(1, round(crop.width * s)), max(1, round(crop.height * s))
        crop = crop.resize((w, h), Image.LANCZOS)
        canvas = Image.new("RGBA", (cell, cell), (0, 0, 0, 0))
        ox = (cell - w) // 2
        # Sitting on the cell's floor when the clip's span is kept: a puffle
        # stands on the ground, it does not float in the middle of the icon.
        oy = (cell - h) - max(1, round(cell * 0.04)) if keep_y else (cell - h) // 2
        canvas.alpha_composite(crop, (max(ox, 0), max(oy, 0)))
        out.append(canvas)
    return out


def placed_body(cells, quantile=0.1):
    sides = sorted(max(b[2] - b[0], b[3] - b[1]) for b in
                   (c.getchannel("A").point(lambda a: 255 if a > 24 else 0).getbbox() for c in cells) if b)
    return sides[int(len(sides) * quantile)] if sides else 0


def place_window(frames, cell):
    """A fixed camera on the puffle where it starts, for clips whose props —
    a volcano, a spray of dirt — would otherwise shrink it to a speck. The
    props run off the edge of the frame; nothing is redrawn."""
    b = bbox(frames[0]) or (0, 0, 1, 1)
    side = max(b[2] - b[0], b[3] - b[1]) / BODY
    cx, cy = (b[0] + b[2]) / 2, (b[1] + b[3]) / 2
    # Its feet stay near the floor of the cell, the way it stands elsewhere.
    floor = b[3] + side * 0.04
    window = (cx - side / 2, floor - side, cx + side / 2, floor)
    out = []
    for f in frames:
        image = Image.open(f).convert("RGBA")
        canvas = Image.new("RGBA", (int(side) + 2, int(side) + 2), (0, 0, 0, 0))
        canvas.alpha_composite(image, (int(-window[0]), int(-window[1]))) if window[0] <= 0 and window[1] <= 0 \
            else canvas.paste(image, (int(round(-window[0])), int(round(-window[1]))), image)
        out.append(canvas.resize((cell, cell), Image.LANCZOS))
    return out


ORDER = ["idle", "look", "bounce", "walk", "walkSide", "doze", "sleep", "wake", "jump", "spin",
         "nuzzle", "roll", "speak", "headstand", "dig", "eat", "splash", "swing", "scratch",
         "hydrant", "dive", "lift", "yawn", "hungry", "sick"]


def build(frames_dir, resources, report_path=None):
    variants, report = [], {}
    only = set(filter(None, os.environ.get("PUFFLES_ONLY", "").split(",")))
    for pid in sorted(discover(frames_dir)):
        if only and pid not in only:
            continue
        roles, sources = roles_for(frames_dir, pid)
        if "idle" not in roles:
            print(f"skip {pid}: no idle", file=sys.stderr)
            continue
        color = re.match(r"[a-z]+", pid).group()
        number = pid[len(color):]
        still = roles.pop("_still", None)
        ref = body_size(roles["idle"]["frames"][:8])
        clips, small_cells, large_cells = {}, [], []
        for role in ORDER:
            if role not in roles:
                continue
            frames = roles[role]["frames"]
            # Dirt, food and water fly about in some: those are measured by
            # the puffle at rest in their first frame.
            own = (body_size(frames[:1]) if roles[role].get("first") else body_size(frames)) or ref
            # Each clip scaled by its own body, so one drawn at a different
            # size in its SWF is the same puffle on screen.
            if role == "dig":
                small, large = place_window(frames, SMALL), place_window(frames, LARGE)
                empty = sum(1 for c in large if placed_body([c]) < 0.3 * LARGE)
                if empty > len(large) // 4:
                    print(f"  {pid}: dig left out, it leaves the frame", file=sys.stderr)
                    continue
            else:
                small = place(frames, SMALL, SMALL * BODY / own)
                large = place(frames, LARGE, LARGE * BODY / own)
            if role not in ("idle", "dig") and placed_body(large) < 0.5 * LARGE * BODY:
                # Sparkles or props made it a speck: better left out.
                print(f"  {pid}: {role} left out, too small to read", file=sys.stderr)
                continue
            clips[role] = {"start": len(small_cells), "count": len(small), "fps": roles[role]["fps"]}
            small_cells += small
            large_cells += large
        if still:
            # The spent puffle: asleep, eyes shut, from the sleep clip's frames.
            frames = roles.get("sleep", {"frames": [still]})["frames"]
            own = body_size(frames)
            small_cells += place([still], SMALL, SMALL * BODY / own)
            large_cells += place([still], LARGE, LARGE * BODY / own)
            still_index = len(small_cells) - 1
        else:
            still_index = clips["idle"]["start"]
        vid = f"{color}-{CREATURES[pid]['slug']}" if number else color
        columns = math.ceil(math.sqrt(len(small_cells)))
        for cells, size, suffix in ((small_cells, SMALL, "small"), (large_cells, LARGE, "large")):
            rows = math.ceil(len(cells) / columns)
            atlas = Image.new("RGBA", (columns * size, rows * size), (0, 0, 0, 0))
            for i, c in enumerate(cells):
                atlas.alpha_composite(c, ((i % columns) * size, (i // columns) * size))
            # Palettised: flat vector art loses nothing a reader can see.
            atlas.quantize(colors=256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE) \
                .save(os.path.join(resources, f"puffle-{vid}-{suffix}.png"), optimize=True)
        en, es = NAMES[color]
        if number:
            creature = CREATURES[pid]
            en, es = f"{en} · {creature['en']}", f"{es} · {creature['es']}"
        variants.append({"id": vid, "color": color, "source": pid, "creature": bool(number),
                         "name": {"en": en, "es": es}, "columns": columns, "small": SMALL,
                         "large": LARGE, "clips": clips, "still": still_index})
        report[vid] = {"source": pid, "clips": {r: sources[r] for r in clips}}
        print(f"{vid:28s} {len(small_cells):4d} frames  {', '.join(clips)}")
    variants.sort(key=lambda v: (COLORS.index(v["color"]), v["creature"], v["source"]))
    with open(os.path.join(resources, "puffles.json"), "w") as f:
        json.dump({"variants": variants}, f, ensure_ascii=False, separators=(",", ":"))
    if report_path:
        with open(report_path, "w") as f:
            json.dump(report, f, ensure_ascii=False, indent=1)


if __name__ == "__main__":
    args = sys.argv[1:]
    report = None
    if "--report" in args:
        i = args.index("--report")
        report = args[i + 1]
        del args[i:i + 2]
    build(args[0], args[1], report)
