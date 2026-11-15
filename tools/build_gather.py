#!/usr/bin/env python3
"""Build DataGather.lua: where to get every crafting reagent, from Polestar's forever-db (WoW Forever data).

Usage: python3 tools/build_gather.py <forever-db folder> [out dir]

Reagents are the item IDs DataRecipes.lua lists (read from the Forever client). For each one:
  - creatures that drop it (forever-db item_source, with drop chance) and containers/objects that hold it;
  - herb and ore nodes, matched by node name (forever-db has the nodes and their spawns but not what they give);
  - vendor reagents (spices, thread, dyes, vials, flux) and skinned leather or caught fish, from fixed lists below,
    because forever-db has no vendor, skinning or fishing loot.
Spawns are grouped into cells of a zone map; the best cells per reagent are kept with their weight (expected drops,
roughly chance x spawns), creature level range and a sample creature, so the game can pick the closest place that
has most of what a recipe needs.
"""
import json
import os
import re
import sys
from collections import defaultdict

CELL = 6.0            # cell size in map percent
SPOTS_PER_ITEM = 30   # best cells kept per reagent
SPOTS_PER_MAP = 2     # at most this many per zone, so far zones still show up
CONTINENTS = {1414, 1415}

HERBS = {
    "Peacebloom": 2447, "Silverleaf": 765, "Earthroot": 2449, "Mageroyal": 785, "Briarthorn": 2450,
    "Stranglekelp": 3820, "Bruiseweed": 2453, "Wild Steelbloom": 3355, "Grave Moss": 3369, "Kingsblood": 3356,
    "Liferoot": 3357, "Fadeleaf": 3818, "Goldthorn": 3821, "Khadgar's Whisker": 3358, "Wintersbite": 3819,
    "Firebloom": 4625, "Purple Lotus": 8831, "Arthas' Tears": 8836, "Sungrass": 8838, "Blindweed": 8839,
    "Ghost Mushroom": 8845, "Gromsblood": 8846, "Golden Sansam": 13464, "Dreamfoil": 13463,
    "Mountain Silversage": 13465, "Plaguebloom": 13466, "Icecap": 13467, "Black Lotus": 13468,
}
# Swiftthistle comes from Mageroyal and Briarthorn nodes.
HERB_EXTRA = {"Mageroyal": [2452], "Briarthorn": [2452]}
ORES = [  # (substring of the node name, items it gives)
    ("Copper Vein", [2770, 2835]), ("Tin Vein", [2771, 2836]), ("Silver Vein", [2775]), ("Iron Deposit", [2772, 2838]),
    ("Gold Vein", [2776]), ("Mithril Deposit", [3858, 7912]), ("Truesilver Deposit", [7911]),
    ("Thorium Vein", [10620, 12365]), ("Dark Iron Deposit", [11370]),
]
# Sold by trade-supply vendors, which stand next to the trainers in towns. Value = profession whose trainer to go to.
VENDOR = {
    2678: 185, 2692: 185, 3713: 185, 4289: 185, 159: 185, 1179: 185, 30817: 185,  # spices, salt, water, milk, flour
    2320: 197, 2321: 197, 4291: 197, 8343: 197, 14341: 197,  # thread
    2324: 197, 4340: 197, 2604: 197, 6260: 197, 2605: 197, 2325: 197, 4341: 197, 4342: 197, 6261: 197, 10290: 197,
    2880: 164, 3466: 164,  # flux
    3371: 171, 3372: 171, 8925: 171, 18256: 171,  # vials
    4470: 202, 4399: 202, 4400: 202,  # wood, wooden stock, heavy stock
    6217: 333,  # copper rod
}
# Skinned leather: (min, max) creature level to skin for it.
SKIN = {2934: (1, 20), 2318: (1, 20), 783: (5, 20), 2319: (18, 30), 4232: (18, 30), 4234: (28, 40), 4235: (28, 40),
        4304: (38, 50), 8169: (38, 50), 8170: (48, 60), 8171: (48, 60)}
# Beast meats with no drop data in forever-db: creatures whose name has one of the words, in that level range.
KEYWORD_DROPS = {
    2672: (["Wolf"], 1, 12), 2886: (["Crag Boar"], 1, 12), 5465: (["Spider"], 1, 12), 5471: (["Stag"], 1, 15),
    2673: (["Coyote"], 10, 20), 723: (["Goretusk"], 10, 20), 731: (["Goretusk"], 10, 20),
    5467: (["Kodo"], 10, 25), 5469: (["Strider"], 10, 25), 5470: (["Thunder Lizard"], 10, 25),
    2924: (["Crocolisk"], 15, 30), 1081: (["Spider"], 15, 30), 2674: (["Crawler"], 15, 30),
    2675: (["Crawler"], 15, 30), 1468: (["Murloc"], 15, 25),
    3730: (["Bear"], 20, 40), 3731: (["Lion"], 25, 40), 3712: (["Turtle"], 25, 40),
    3667: (["Crocolisk"], 25, 40), 3685: (["Raptor"], 25, 40),
    12203: (["Wolf", "Worg"], 30, 45), 12202: (["Tiger", "Panther"], 33, 45), 12184: (["Raptor"], 35, 50),
    12204: (["Kodo"], 35, 50), 12206: (["Crab", "Makrura"], 35, 50), 12205: (["Spider"], 40, 55),
    12208: (["Wolf", "Worg"], 40, 55),
}
KEYWORD_CHANCE = 30.0  # assumed drop chance for those
# Caught with fishing (no drop data for them).
REAL_FISH = {6291, 6303, 6289, 6317, 6361, 6308, 6362, 21071, 8365, 13754, 13755, 13756, 13758, 13759, 13760, 13888,
             13889, 13893, 4603, 7974}


def load(folder, table):
    with open(os.path.join(folder, table + ".jsonl"), encoding="utf-8") as f:
        return [json.loads(line) for line in f if line.strip()]


def main():
    src = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else "."
    with open(os.path.join(out, "DataRecipes.lua"), encoding="utf-8") as f:
        reagents = {int(m) for m in re.findall(r"^  \[(\d+)\] = ", f.read(), re.M)}

    npcs = {r["id"]: r for r in load(src, "npc")}
    objects = {r["id"]: r for r in load(src, "object")}

    # Map frames: same method as build_questdb.py (smallest zone frame that holds the point).
    frames = defaultdict(list)
    for m in load(src, "ui_map"):
        h, w = m["top"] - m["bottom"], m["left"] - m["right"]
        if h <= 0 or w <= 0 or m["ui_map"] in CONTINENTS or m["map"] not in (0, 1) or h * w > 100e6:  # world-sized maps
            continue
        frames[m["map"]].append((h * w, m["ui_map"], m["top"], m["left"], h, w))
    for v in frames.values():
        v.sort()

    # Zone frames overlap at the borders: a point goes to the frame it sits deepest inside (the farthest from that
    # frame's edges), so a Westfall spawn near Elwynn's frame edge stays in Westfall.
    def place(map_id, x, y):
        best, depth = None, -1
        for _, ui, top, left, h, w in frames.get(map_id, ()):
            px, py = (left - y) / w * 100, (top - x) / h * 100
            if 0 <= px <= 100 and 0 <= py <= 100:
                d = min(px, 100 - px, py, 100 - py)
                if d > depth:
                    best, depth = (ui, px, py), d
        return best

    # sources[item] = [(kind, id, chance or None)]
    sources = defaultdict(list)
    for r in load(src, "item_source"):
        if r["item"] in reagents and r["kind"] in ("npc", "object"):
            sources[r["item"]].append((r["kind"], r["id"], r.get("chance")))
    for it, (words, lo, hi) in KEYWORD_DROPS.items():
        if it not in reagents or any(k == "npc" for k, _, _ in sources.get(it, [])):
            continue
        for nid, n in npcs.items():
            name = n.get("name") or ""
            if n.get("rank", 0) == 0 and lo <= n.get("level_min", 0) and n.get("level_max", 0) <= hi \
                    and any(re.search(r"\b" + re.escape(w) + r"\b", name) for w in words) and "Rider" not in name:
                sources[it].append(("npc", nid, KEYWORD_CHANCE))
    node_items, node_kind = {}, {}
    for oid, o in objects.items():
        name = o.get("name") or ""
        items = None
        if name in HERBS:
            items = [HERBS[name]] + HERB_EXTRA.get(name, [])
        else:
            for sub, ids in ORES:
                if sub in name:
                    items = ids
        if items:
            node_items[oid] = items
            node_kind[oid] = "h" if name in HERBS else "m"
    for it in list(sources):
        sources[it] = [x for x in sources[it] if not (x[0] == "object" and x[1] in node_items)]
    for oid, items in node_items.items():
        for it in items:
            if it in reagents:
                sources[it].append(("node", oid, None))

    wanted = defaultdict(set)
    for it, lst in sources.items():
        for kind, sid, _ in lst:
            wanted[("object" if kind == "node" else kind, sid)].add(it)
    points = defaultdict(list)  # (kind, id) -> [(ui, px, py)]
    for r in load(src, "spawn"):
        key = (r.get("kind"), r["id"])
        if key in wanted:
            p = place(r["map"], r["x"], r["y"])
            if p:
                points[key].append(p)

    data = {}
    for it in sorted(reagents):
        cells = {}
        for kind, sid, chance in sources.get(it, []):
            pts = points.get(("object" if kind == "node" else kind, sid), [])
            if not pts:
                continue
            if kind == "npc":
                n = npcs.get(sid, {})
                if n.get("rank", 0) >= 1:      # elites and bosses: not a farming spot
                    continue
                c = (chance if chance is not None else 3.0) / 100.0
                if c < 0.02:                  # under 2%: not worth farming
                    continue
                lmin, lmax = n.get("level_min", 0), n.get("level_max", 0)
                k = "u"
            else:
                c = 1.0 if kind == "node" else ((chance if chance is not None else 30.0) / 100.0)
                lmin = lmax = 0
                k = node_kind[sid] if kind == "node" else "o"
            for ui, px, py in pts:
                key = (ui, int(px // CELL), int(py // CELL))
                cell = cells.setdefault(key, {"w": 0.0, "sx": 0.0, "sy": 0.0, "n": 0, "lmin": 999, "lmax": 0,
                                              "k": k, "best": (0, sid)})
                cell["w"] += c
                cell["sx"] += px * c
                cell["sy"] += py * c
                cell["n"] += 1
                if lmin:
                    cell["lmin"] = min(cell["lmin"], lmin)
                    cell["lmax"] = max(cell["lmax"], lmax)
                if c > cell["best"][0]:
                    cell["best"] = (c, sid)
                    cell["k"] = k
        ranked = sorted(cells.items(), key=lambda kv: -kv[1]["w"])
        keep, per_map = [], defaultdict(int)
        for (ui, _, _), cell in ranked:
            if per_map[ui] >= SPOTS_PER_MAP:
                continue
            per_map[ui] += 1
            keep.append((ui, cell))
            if len(keep) >= SPOTS_PER_ITEM:
                break
        entry = {}
        if keep:
            entry["s"] = keep
        if it in VENDOR:
            entry["v"] = VENDOR[it]
        if it in SKIN:
            entry["sk"] = SKIN[it]
        if it in REAL_FISH and not keep:
            entry["f"] = True
        if entry:
            data[it] = entry

    names = {}
    for it, e in data.items():
        for _, cell in e.get("s", []):
            k, sid = cell["k"], cell["best"][1]
            if k == "u":
                names[("u", sid)] = npcs.get(sid, {}).get("name", "")
            else:
                names[("o", sid)] = objects.get(sid, {}).get("name", "")

    def s(v):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'

    with open(os.path.join(out, "DataGather.lua"), "w", encoding="utf-8") as w:
        w.write("-- Generated by tools/build_gather.py from Polestar forever-db (GPL-3.0) - do not edit.\n")
        w.write("-- G.gatherData[item] = { s = { { uiMap, x, y, weight, minLevel, maxLevel, kind, sourceID }, ... },\n")
        w.write("--   v = profession whose trainer area sells it, sk = { minLevel, maxLevel } to skin, f = fished }\n")
        w.write("-- x/y: map percent x10; weight: expected items per full clear x100; kind: u creature, o object, h herb node, m ore node.\n")
        w.write("local G = GuiaForever\nG.gatherData = {\n")
        for it in sorted(data):
            e = data[it]
            parts = []
            if "s" in e:
                spots = []
                for ui, c in e["s"]:
                    spots.append("{%d,%d,%d,%d,%d,%d,\"%s\",%d}" % (
                        ui, round(c["sx"] / c["w"] * 10), round(c["sy"] / c["w"] * 10), max(1, round(c["w"] * 100)),
                        0 if c["lmin"] == 999 else c["lmin"], c["lmax"], c["k"], c["best"][1]))
                parts.append("s={" + ",".join(spots) + "}")
            if "v" in e:
                parts.append("v=%d" % e["v"])
            if "sk" in e:
                parts.append("sk={%d,%d}" % e["sk"])
            if e.get("f"):
                parts.append("f=true")
            w.write("  [%d]={%s},\n" % (it, ",".join(parts)))
        w.write("}\nG.gatherNames = {\n")
        for (k, sid), nm in sorted(names.items()):
            if nm:
                w.write("  [\"%s%d\"]=%s,\n" % (k, sid, s(nm)))
        w.write("}\n")
    print("reagents", len(reagents), "with data", len(data), "spots", sum(len(e.get("s", [])) for e in data.values()))


if __name__ == "__main__":
    main()
