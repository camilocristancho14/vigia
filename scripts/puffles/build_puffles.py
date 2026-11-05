#!/usr/bin/env python3
"""Builds Vigía's puffle atlases from the original Club Penguin SWFs.

Input: the frames JPEXS ffdec exported from every puffle SWF in the Wayback
Machine's copy of media1.clubpenguin.com (fetch_swfs.py, extract_frames.sh):

    <frames>/<swf name>/DefineSprite_<n>[_<class>]/<frame>.png

Output, into Sources/Pulse/Resources:

    puffle-<variant>-small.png   cells 44 px tall: the menu bar's 22 pt at 2x
    puffle-<variant>-large.png   cells 80 px tall: the rail's rings and settings
    puffles.json                 where every clip sits in the atlases, and what
                                 kind of animation it is

**No pixel is drawn here.** Frames are picked, put in order, cropped,
scaled, set in their cell and palettised for size. Every clip is one of the
game's own symbols, or a run of consecutive frames from one.

Cells are as tall as the menu bar and as wide as the variant needs: the
transparent margin around the puffle is cut away, with one crop for the
whole clip (so it does not shake) and one scale for the whole variant (so it
is the same size from clip to clip), and the puffle at rest fills the cell's
height. A clip that reaches higher or wider than that — a headstand, a
skateboard — is scaled down as a whole until it fits; nothing is cut.

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
# Widest a cell may be, against its height: a puffle is a little wider than
# tall; a skateboard or a walk in profile is scaled down to fit this.
MAX_ASPECT = 1.4
# Clips longer than this are sampled more sparsely, to keep the atlas small.
MAX_FRAMES = 56
SOURCE_FPS = 25.0
# A clip whose puffle would end up smaller than this, against the cell's
# height, is left out: at 22 points it would be a speck.
MIN_BODY = 0.33
# How far a clip that reaches too high is scaled down before the camera
# follows the puffle up instead.
MIN_SHRINK = 0.7
MIN_BODY_WINDOWED = 0.18

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
# The rest of each puffle's own animations — its toys, its bath, its moods —
# picked out by eye from the libraries' symbols (see extra_clips.json).
EXTRAS = json.load(open(os.path.join(os.path.dirname(__file__), "extra_clips.json")))

TRICKS = {"jumpForward": "jump", "jumpSpin": "spin", "nuzzle": "nuzzle", "roll": "roll",
          "speak": "speak", "standOnHead": "headstand"}
# Puffle Park's swing, post and hydrant and the hotel's dive are left out:
# their props dwarf the puffle, which is a speck at 22 points.
SINGLES = {  # file pattern -> clip
    "hotelcare__weightlifting__puffle_{id}_weightlifting": "lift",
    "eat__puffle_{id}_eat": "eat",
    "animation__splash__puffle_{id}_splash": "splash",
}

# What every clip is, which decides where the app plays it. The app's
# choreography (PuffleMarks.swift) deals each mood its kinds.
KINDS = {
    "idle": "rest", "look": "look", "walk": "walk", "walkSide": "walk",
    "doze": "doze", "sleep": "sleep", "wake": "wake",
    "jump": "trick", "spin": "trick", "headstand": "trick", "bounce": "trick",
    "nuzzle": "happy", "roll": "work", "dig": "work", "lift": "work",
    "speak": "speak", "eat": "eat", "splash": "bath",
    "yawn": "yawn", "hungry": "hungry", "sick": "sick",
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


def library_roles(swf_dir, roles):
    """Idle, look, walks, sleep and the moods from a walk, igloo or base SWF."""
    sps = sprites(swf_dir)
    eights = [s for s in sps if len(s["frames"]) == 8 and not s["named"]]
    twelves = [s for s in sps if len(s["frames"]) == 12 and not s["named"]]
    # The ghost puffle floats instead of breathing: its five turns of the
    # head are 60 frames each, not 8.
    sixties = [s for s in sps if len(s["frames"]) == 60 and not s["named"]]
    if len(eights) >= 5:
        front, q, side = (eights[i]["frames"] for i in range(3))
        twice = front + front
    elif len(sixties) >= 5:
        front, q, side = (sixties[i]["frames"][::2] for i in range(3))
        twice = front
    else:
        return
    reference = body_size(front)

    def puffle_sized(s):
        b = bbox(s["frames"][0])
        if not b:
            return False
        side = max(b[2] - b[0], b[3] - b[1])
        return 0.7 * reference <= side <= 1.5 * reference

    if "idle" not in roles:
        # Facing out, breathing and blinking (or floating), twice through.
        roles["idle"] = {"frames": twice, "fps": 12.5}
        # Head turned three-quarters, then to the side, and back: the
        # direction clips the game turned a puffle with, in a row.
        n = max(4, len(q) // 2)
        roles["look"] = {"frames": front[:4] + q[:n] + side + side + q[:n] + front[:4], "fps": 12.5}
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
        roles["_sleeper"] = sleepers[0]["number"]
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


def extra_symbol(frames_dir, lib, symbol):
    """One symbol of a library by number, or by the class name it was
    exported under (`BathAsset`)."""
    path = os.path.join(frames_dir, lib)
    if not os.path.isdir(path):
        return None
    for s in sprites(path):
        if str(symbol).isdigit() and s["number"] == int(symbol):
            return s
        if not str(symbol).isdigit() and s["name"].endswith("." + symbol):
            return s
    return None


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
            mark(set(roles) - before - {"_still", "_sleeper"}, lib)
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
    # The libraries' other symbols: toys, baths, the care screen's moods.
    for entry in EXTRAS["clips"].get(pid, []):
        lib, symbol, role, kind = entry[:4]
        s = extra_symbol(frames_dir, lib, symbol)
        if not s:
            print(f"  {pid}: {lib} {symbol} not found", file=sys.stderr)
            continue
        frames = s["frames"]
        roles[role] = dict(clip(frames), first=True, kind=kind)
        mark([role], f"{lib}/{s['name']}")
    # No walk, igloo or base library survived for the brown puffle: it rests
    # on the opening frames of its own speak trick, before it starts talking.
    if "idle" not in roles and "speak" in roles:
        opening = roles["speak"]["frames"][:4]
        roles["idle"] = {"frames": opening * 2, "fps": 6.25}
        sources["idle"] = sources["speak"]
    return roles, sources


def union_box(frames):
    boxes = [bbox(f) for f in frames]
    boxes = [b for b in boxes if b] or [(0, 0, 1, 1)]
    return (min(b[0] for b in boxes), min(b[1] for b in boxes),
            max(b[2] for b in boxes), max(b[3] for b in boxes))


def smoothed(values, reach=2):
    """A running mean over five frames, so a camera glides."""
    return [sum(values[max(0, i - reach):i + reach + 1]) / len(values[max(0, i - reach):i + reach + 1])
            for i in range(len(values))]


def place(frames, union, scale, width, height, track_x=False, track_y=False):
    """Every frame of a clip cut to the clip's own box — one crop for all of
    them, so nothing shakes — scaled by `scale`, centred across the cell and
    standing on its floor.

    `track_x`: for a clip that travels sideways (a roll, a dig throwing dirt
    about) the camera follows the puffle across instead, smoothly.
    `track_y`: for a leap too high to fit at a readable size, the camera
    keeps the top of the puffle in view, smoothly: the shadow on the floor
    may drop out of the frame while it is in the air; the puffle does not.
    """
    boxes = [bbox(f) or union for f in frames]
    if track_x:
        cx = smoothed([(b[0] + b[2]) / 2 for b in boxes])
        span_x = width / scale
    if track_y:
        span_y = height / scale
        # The highest the puffle gets in the frames around each one, then
        # smoothed: the camera is up there before it is, never behind it.
        tops = [b[1] for b in boxes]
        top = smoothed([min(tops[max(0, i - 3):i + 4]) for i in range(len(tops))], reach=1)
    out = []
    for i, f in enumerate(frames):
        if track_x:
            x0, x1, w, ox = cx[i] - span_x / 2, cx[i] + span_x / 2, width, 0
        else:
            w = min(width, max(1, round((union[2] - union[0]) * scale)))
            x0, x1, ox = union[0], union[2], max((width - w) // 2, 0)
        if track_y:
            y0 = min(max(top[i] - span_y * 0.05, union[1]), union[3] - span_y)
            y1, h, oy = y0 + span_y, height, 0
        else:
            h = min(height, max(1, round((union[3] - union[1]) * scale)))
            y0, y1, oy = union[1], union[3], max(height - h, 0)
        image = Image.open(f).convert("RGBA").crop((round(x0), round(y0), round(x1), round(y1)))
        canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
        canvas.alpha_composite(image.resize((w, h), Image.LANCZOS), (ox, oy))
        out.append(canvas)
    return out


def place_window(frames, scale, width, height):
    """A fixed camera on the puffle where it starts, for clips whose props —
    a spray of dirt, a bubble, a tub — would otherwise shrink it to a speck.
    The props run off the edge of the frame; nothing is redrawn."""
    b = bbox(frames[0]) or (0, 0, 1, 1)
    span_w, span_h = width / scale, height / scale
    cx = (b[0] + b[2]) / 2
    box = (round(cx - span_w / 2), round(b[3] - span_h), round(cx + span_w / 2), b[3])
    out = []
    for f in frames:
        image = Image.open(f).convert("RGBA").crop(box)
        out.append(image.resize((width, height), Image.LANCZOS))
    return out


def coverage(cell):
    return sum(cell.getchannel("A").histogram()[25:])


def cell_body(cells):
    """How tall the puffle stands in its placed cells, from the smaller ones."""
    sides = sorted(b[3] - b[1] for b in
                   (c.getchannel("A").point(lambda a: 255 if a > 24 else 0).getbbox() for c in cells) if b)
    return sides[len(sides) // 4] if sides else 0


# The tricks: the puffle alone, no props, so a camera rising with it keeps
# it whole and readable.
PUFFLE_ONLY = {"jump", "spin", "headstand", "bounce", "nuzzle", "speak", "wake"}

# Clips where the puffle stays where it is and only its props fly about —
# dirt, a bubble, a tub, a brush — so a camera fixed on it cuts the props,
# never the puffle.
WINDOWED = {"dig", "eat", "bubblegum", "bath", "brush"}

ORDER = ["idle", "look", "bounce", "walk", "walkSide", "doze", "sleep", "wake", "jump", "spin",
         "nuzzle", "roll", "speak", "headstand", "dig", "eat", "splash", "lift", "yawn", "hungry", "sick"]


def layout(roles, ref):
    """One scale for the variant and the size of its cell.

    `unit` turns a clip's source pixels into cell pixels per unit of cell
    height: the idle clip, cut to its own box, exactly fills the height.
    """
    measured = {}
    for role, spec in roles.items():
        frames = spec["frames"]
        own = (body_size(frames[:1]) if spec.get("first") else body_size(frames)) or ref
        u = union_box(frames)
        # In units of the idle puffle's body.
        measured[role] = (own, u, (u[2] - u[0]) / own, (u[3] - u[1]) / own)
    _, _, idle_w, idle_h = measured["idle"]
    # Width: what most clips need, never less than the idle puffle.
    widths = sorted(w / idle_h for _, _, w, _ in measured.values())
    aspect = min(MAX_ASPECT, max(idle_w / idle_h, widths[len(widths) * 3 // 4]))
    return measured, idle_h, aspect


def build(frames_dir, resources, report_path=None):
    variants, report = [], {}
    only = set(filter(None, os.environ.get("PUFFLES_ONLY", "").split(",")))
    left_out = EXTRAS.get("leftOut", {})
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
        roles.pop("_sleeper", None)
        for role in left_out.get(pid, []):
            roles.pop(role, None)
        ref = body_size(roles["idle"]["frames"][:8])
        measured, idle_h, aspect = layout(roles, ref)
        sizes = {}
        for size in (SMALL, LARGE):
            sizes[size] = (max(size, round(size * aspect)) & ~1, size)
        order = [r for r in ORDER if r in roles] + [r for r in roles if r not in ORDER]
        clips, cells = {}, {SMALL: [], LARGE: []}
        for role in order:
            spec = roles[role]
            own, union, w_units, h_units = measured[role]
            placed = {}
            for size, (cw, ch) in sizes.items():
                # The idle puffle's body is `ch / idle_h` pixels; the clip is
                # scaled down as a whole if it reaches past the cell.
                scale = ch / idle_h / own
                # Too tall (a headstand, a leap): the whole clip shrinks, to
                # 70 % at most; past that the camera rises with the puffle.
                tall = ch / (h_units * own * scale)
                track_y = tall < MIN_SHRINK and role in PUFFLE_ONLY
                s = scale * (max(min(1.0, tall), MIN_SHRINK) if track_y else min(1.0, tall))
                wide = cw / (w_units * own * s)
                track_x = wide < 0.75
                if not track_x:
                    s *= min(1.0, wide)
                    track_y = track_y and (h_units * own * s) > ch
                placed[size] = place(spec["frames"], union, s, cw, ch, track_x, track_y)
            body = cell_body(placed[LARGE]) / LARGE
            if role in WINDOWED and body < MIN_BODY:
                # Props made it a speck, in a clip where the puffle stays put:
                # the camera stays on the puffle instead, unless that leaves
                # the frame empty. Measured by the puffle without its props.
                # The median frame, props and all: zooming in less risks
                # cutting the puffle less.
                sides = sorted(max(b[2] - b[0], b[3] - b[1]) for b in map(bbox, spec["frames"]) if b)
                plain = max(sides[len(sides) // 2] if sides else own, own)
                window = {size: place_window(spec["frames"], ch / idle_h / plain, cw, ch)
                          for size, (cw, ch) in sizes.items()}
                start = coverage(window[LARGE][0]) or 1
                empty = sum(1 for c in window[LARGE] if coverage(c) < 0.3 * start)
                if empty <= len(window[LARGE]) // 5:
                    placed, body = window, cell_body(window[LARGE]) / LARGE
                    print(f"  {pid}: {role} framed on the puffle", file=sys.stderr)
            # A windowed clip is measured with its props cut away: a lower bar.
            if role != "idle" and body < (MIN_BODY_WINDOWED if role in WINDOWED else MIN_BODY):
                print(f"  {pid}: {role} left out, too small to read ({body:.2f})", file=sys.stderr)
                continue
            clips[role] = {"start": len(cells[SMALL]), "count": len(placed[SMALL]),
                           "fps": round(spec["fps"], 4), "kind": spec.get("kind") or KINDS[role]}
            for size in sizes:
                cells[size] += placed[size]
        if still:
            # Lying asleep, eyes shut, for Reduce Motion once the limit is spent.
            spec = roles.get("sleep") or {"frames": [still]}
            own = body_size(spec["frames"])
            union = union_box(spec["frames"])
            for size, (cw, ch) in sizes.items():
                scale = ch / idle_h / own
                h = (union[3] - union[1]) * scale
                w = (union[2] - union[0]) * scale
                fit = min(1.0, ch / h, cw / w)
                cells[size] += place([still], union, scale * fit, cw, ch)
            still_index = len(cells[SMALL]) - 1
        else:
            still_index = clips["idle"]["start"]
        vid = f"{color}-{CREATURES[pid]['slug']}" if number else color
        columns = math.ceil(math.sqrt(len(cells[SMALL]) * sizes[SMALL][1] / sizes[SMALL][0]))
        for size, suffix in ((SMALL, "small"), (LARGE, "large")):
            cw, ch = sizes[size]
            rows = math.ceil(len(cells[size]) / columns)
            atlas = Image.new("RGBA", (columns * cw, rows * ch), (0, 0, 0, 0))
            for i, c in enumerate(cells[size]):
                atlas.alpha_composite(c, ((i % columns) * cw, (i // columns) * ch))
            # Palettised: flat vector art loses nothing a reader can see.
            atlas.quantize(colors=256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE) \
                .save(os.path.join(resources, f"puffle-{vid}-{suffix}.png"), optimize=True)
        en, es = NAMES[color]
        if number:
            creature = CREATURES[pid]
            en, es = f"{en} · {creature['en']}", f"{es} · {creature['es']}"
        variants.append({"id": vid, "color": color, "source": pid, "creature": bool(number),
                         "name": {"en": en, "es": es}, "columns": columns,
                         "small": sizes[SMALL][1], "smallWidth": sizes[SMALL][0],
                         "large": sizes[LARGE][1], "largeWidth": sizes[LARGE][0],
                         "clips": clips, "still": still_index})
        report[vid] = {"source": pid, "clips": {r: sources[r] for r in clips}}
        print(f"{vid:28s} {len(cells[SMALL]):4d} frames  {sizes[SMALL][0]}x{sizes[SMALL][1]}  "
              f"{len(clips)} clips: {', '.join(clips)}")
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
