#!/usr/bin/env python3
"""Step 1 of 3: download every puffle sprite SWF the Wayback Machine holds
for media1.clubpenguin.com/play/v2/content/global/puffle/sprites/.

The index is the CDX API's answer for that prefix, saved as JSON
(https://web.archive.org/cdx/search/cdx?url=media1.clubpenguin.com/play/v2/content/global/puffle&matchType=prefix&output=json).

Raw snapshot bytes via the `id_` Wayback flag; each file is checked for a Flash
header (CWS/FWS/ZWS) before it is kept. A manifest of local file -> snapshot URL is
written to sources.tsv beside the SWFs.

Usage: fetch_swfs.py <cdx.json> <swf dir>
"""
import json, os, subprocess, time, concurrent.futures as cf
import sys
CDX, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)
rows = json.load(open(CDX))[1:]
best = {}
for urlkey, ts, orig, mime, status, digest, length in rows:
    if status != "200" or "/sprites/" not in orig:
        continue
    clean = orig.split("?")[0]
    # newest snapshot of each URL
    if clean not in best or ts > best[clean][0]:
        best[clean] = (ts, orig)

def local_name(url):
    rel = url.split("/puffle/sprites/")[1]
    return rel.replace("/", "__")

def fetch(item):
    clean, (ts, orig) = item
    dest = os.path.join(OUT, local_name(clean))
    if os.path.exists(dest) and open(dest, "rb").read(3) in (b"CWS", b"FWS", b"ZWS"):
        return clean, ts, dest, "cached"
    wb = f"https://web.archive.org/web/{ts}id_/{orig}"
    for attempt in range(6):
        r = subprocess.run(["curl", "-sL", "-m", "90", "-o", dest, wb])
        if r.returncode == 0 and os.path.exists(dest) and open(dest, "rb").read(3) in (b"CWS", b"FWS", b"ZWS"):
            return clean, ts, dest, "ok"
        time.sleep(5 * (attempt + 1))
    if os.path.exists(dest):
        os.remove(dest)
    return clean, ts, dest, "FAILED"

with cf.ThreadPoolExecutor(4) as ex, open(os.path.join(OUT, "sources.tsv"), "w") as log:
    for clean, ts, dest, st in ex.map(fetch, sorted(best.items())):
        print(st, os.path.basename(dest), flush=True)
        if st != "FAILED":
            log.write(f"{os.path.basename(dest)}\thttps://web.archive.org/web/{ts}/{clean}\t{clean}\n")
