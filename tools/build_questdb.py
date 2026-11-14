#!/usr/bin/env python3
"""Build DataQuestDB.lua and DataQuestDrops.lua from Polestar's forever-db (World of Warcraft: Forever data).

Usage: python3 tools/build_questdb.py <forever-db folder> tools/old_extras.tsv [out dir]

tools/prereq_fixes.json adds chains forever-db does not know yet (quest id -> extra p / b).

forever-db (https://github.com/fitzforge/polestar/tree/main/forever-db, GPL-3.0) is read from the game client
and open sources. Its spawn points are world yards; each one is stored as a percent of the smallest in-game map
frame that holds it, and zoneFit carries that frame, so QuestDB.lua turns it back into world yards exactly.

The old extras file keeps what forever-db has no field for: profession (k), world event (v) and exclusive
quests (x) per quest, creature faction ("A"/"H") and the zone each creature or object was in, dumped from the previous DataQuestDB.lua as
  q <tab> id <tab> skill <tab> event <tab> exclusive ids (comma separated)
  f <tab> npc id <tab> A|H
  u|o <tab> creature or object id <tab> uiMapIDs it was on (comma separated)
"""
import json
import os
import sys
from collections import Counter, defaultdict

MAX_POINTS = 20      # spawn points kept per creature or object per map
MAX_DROPS = 15       # drop sources kept per quest item
CONTINENTS = {1414, 1415}  # Kalimdor, Eastern Kingdoms: points go to the zone maps inside them


def load(folder, table):
    with open(os.path.join(folder, table + ".jsonl"), encoding="utf-8") as f:
        return [json.loads(line) for line in f if line.strip()]


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ") + '"'


def num(v):
    if isinstance(v, float):
        return ("%.1f" % v).rstrip("0").rstrip(".")
    return str(v)


def main():
    src, extras_path = sys.argv[1], sys.argv[2]
    out = sys.argv[3] if len(sys.argv) > 3 else "."

    quests = {r["id"]: r for r in load(src, "quest")}
    starts, ends, objectives, prereqs = defaultdict(list), defaultdict(list), defaultdict(list), defaultdict(list)
    for r in load(src, "quest_start"):
        starts[r["quest"]].append(r)
    for r in load(src, "quest_end"):
        ends[r["quest"]].append(r)
    for r in load(src, "quest_objective"):
        objectives[r["quest"]].append(r)
    for r in load(src, "quest_prereq"):
        prereqs[r["quest"]].append(r)
    npcs = {r["id"]: r for r in load(src, "npc")}
    objects = {r["id"]: r for r in load(src, "object")}
    ui_maps = load(src, "ui_map")
    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "prereq_fixes.json"), encoding="utf-8") as f:
        fixes = {int(k): v for k, v in json.load(f).items() if not k.startswith("_")}
    for qid, fx in fixes.items():
        for pre in fx.get("p", []):
            prereqs[qid].append({"mode": "any", "pre": pre, "quest": qid})
        for pre in fx.get("b", []):
            prereqs[qid].append({"mode": "any", "pre": pre, "quest": qid, "breadcrumb": True})

    extras, old_faction, old_zone = {}, {}, {}
    with open(extras_path, encoding="utf-8") as f:
        for line in f:
            p = line.rstrip("\n").split("\t")
            if p[0] == "q":
                extras[int(p[1])] = p[2:]
            elif p[0] == "f":
                old_faction[int(p[1])] = p[2]
            elif p[0] in ("u", "o"):
                old_zone[("npc" if p[0] == "u" else "object", int(p[1]))] = {int(m) for m in p[2].split(",") if m}

    # ---------------------------------------------------------------- map frames
    frames = defaultdict(list)  # client map id -> [(area, ui_map, top, left, h, w)]
    fit, instance_maps = {}, set()
    for m in ui_maps:
        if m["map"] not in (0, 1):
            instance_maps.add(m["ui_map"])
        h, w = m["top"] - m["bottom"], m["left"] - m["right"]
        if h <= 0 or w <= 0:
            continue
        fit[m["ui_map"]] = (m["top"], m["left"], h, w)
        if m["ui_map"] not in CONTINENTS:
            frames[m["map"]].append((h * w, m["ui_map"], m["top"], m["left"], h, w))
    for v in frames.values():
        v.sort()

    # Map frames are rectangles and overlap near borders: a point goes to the zone the previous data had for that
    # creature or object when its frame holds it, otherwise to the smallest frame that holds it.
    def place(map_id, x, y, prefer=()):
        found = None
        for _, ui, top, left, h, w in frames.get(map_id, ()):
            px, py = (left - y) / w * 100, (top - x) / h * 100
            if 0 <= px <= 100 and 0 <= py <= 100:
                if ui in prefer:
                    return ui, px, py
                found = found or (ui, px, py)
        return found

    # ---------------------------------------------------------------- positions
    points = {"npc": defaultdict(lambda: defaultdict(list)), "object": defaultdict(lambda: defaultdict(list))}
    for r in load(src, "spawn"):
        kind = r.get("kind")
        if kind not in points:
            continue
        p = place(r["map"], r["x"], r["y"], old_zone.get((kind, r["id"]), ()))
        if p:
            ui, px, py = p
            points[kind][r["id"]][ui].append((round(px * 10), round(py * 10)))

    def thin(lst):
        lst = sorted(set(lst))
        if len(lst) <= MAX_POINTS:
            return lst
        step = len(lst) / MAX_POINTS
        return [lst[int(i * step)] for i in range(MAX_POINTS)]

    # ---------------------------------------------------------------- quests
    used_npcs, used_objects = set(), set()
    item_objects = defaultdict(set)
    drops = defaultdict(list)
    for r in load(src, "item_source"):
        if r["kind"] == "object":
            item_objects[r["item"]].add(r["id"])
        elif r["kind"] == "npc":
            drops[r["item"]].append((r.get("chance"), r["id"]))

    def part(rows, kind_key="kind", id_key="id"):
        t = defaultdict(list)
        for r in rows:
            k = {"npc": "u", "object": "o", "item": "i"}.get(r[kind_key])
            if k and r[id_key] not in t[k]:
                t[k].append(r[id_key])
        return t

    lines = []
    titles = {}
    drop_lines = []
    for qid in sorted(quests):
        q = quests[qid]
        titles[qid] = q.get("title", "")
        f = ["l=%d" % q["level"]] if q.get("level") else []
        if q.get("min_level"):
            f.append("m=%d" % q["min_level"])
        if q.get("races"):
            f.append("r=%d" % q["races"])
        if q.get("classes"):
            f.append("c=%d" % q["classes"])
        ex = extras.get(qid)
        if ex and ex[0]:
            f.append("k=%s" % ex[0])
        if ex and ex[1]:
            f.append("v=%s" % ex[1])
        if q.get("repeatable"):
            f.append("rep=true")
        # Prerequisites: breadcrumbs are optional and left out; pa=true means every one is needed, not any one.
        pre = [r for r in prereqs.get(qid, []) if not r.get("breadcrumb")]
        if pre:
            ids = []
            for r in pre:
                if r["pre"] not in ids:
                    ids.append(r["pre"])
            f.append("p={%s}" % ",".join(map(str, ids)))
            if len(ids) > 1 and all(r["mode"] == "all" for r in pre):
                f.append("pa=true")
        crumbs = [r["pre"] for r in prereqs.get(qid, []) if r.get("breadcrumb")]
        if crumbs:
            f.append("b={%s}" % ",".join(map(str, dict.fromkeys(crumbs))))
        if ex and ex[2]:
            f.append("x={%s}" % ex[2])
        for key, rows in (("s", starts.get(qid, [])), ("e", ends.get(qid, []))):
            t = part(rows)
            used_npcs.update(t.get("u", []))
            used_objects.update(t.get("o", []))
            body = ",".join("%s={%s}" % (k, ",".join(map(str, v))) for k, v in t.items() if v)
            if body:
                f.append("%s={%s}" % (key, body))
        o = defaultdict(list)
        for r in sorted(objectives.get(qid, []), key=lambda r: r.get("n", 0)):
            k = {"kill": "u", "talk": "u", "item": "i", "object": "o"}.get(r["kind"])
            if k and r.get("target") and r["target"] not in o[k]:
                o[k].append(r["target"])
        used_npcs.update(o.get("u", []))
        used_objects.update(o.get("o", []))
        body = ",".join("%s={%s}" % (k, ",".join(map(str, v))) for k, v in o.items() if v)
        if body:
            f.append("o={%s}" % body)
        lines.append("[%d]={%s}," % (qid, ",".join(f)))

        # Drops for each objective item, best known chance first (unknown chances last).
        items = []
        for item in o.get("i", []):
            src_list = sorted(drops.get(item, []), key=lambda d: -(d[0] if d[0] is not None else -1))[:MAX_DROPS]
            for _, npc in src_list:
                used_npcs.add(npc)
            for obj in item_objects.get(item, ()):
                used_objects.add(obj)
            if src_list:
                items.append("[%d]={%s}" % (item, ",".join("%d,%s" % (n, num(c if c is not None else 0)) for c, n in src_list)))
        if items:
            drop_lines.append("[%d]={%s}," % (qid, ",".join(items)))

    # ---------------------------------------------------------------- faction of creatures
    # Kept from the previous data; a creature it did not know takes the side most creatures of its faction template had.
    by_template = defaultdict(Counter)
    for nid, side in old_faction.items():
        if nid in npcs and "faction_template" in npcs[nid]:
            by_template[npcs[nid]["faction_template"]][side] += 1
    faction = {}
    for nid in used_npcs:
        if nid in old_faction:
            faction[nid] = old_faction[nid]
        elif nid in npcs and npcs[nid].get("faction_template") in by_template:
            side, n = by_template[npcs[nid]["faction_template"]].most_common(1)[0]
            if n >= 3:
                faction[nid] = side

    def pos_table(kind, ids):
        rows = []
        for i in sorted(ids):
            maps = points[kind].get(i)
            if not maps:
                continue
            body = ",".join("[%d]={%s}" % (ui, ",".join("%d,%d" % xy for xy in thin(maps[ui]))) for ui in sorted(maps))
            rows.append("[%d]={%s}," % (i, body))
        return rows

    with open(os.path.join(out, "DataQuestDB.lua"), "w", encoding="utf-8") as w:
        w.write("-- Guía Forever: generated by tools/build_questdb.py from forever-db (see THIRD_PARTY_LICENSES.md). Do not edit by hand.\n")
        w.write("-- quests[id] = { l=level, m=min level, r=race mask, c=class mask, k=skill, v=world event, rep=repeatable,\n")
        w.write("--   p=prerequisites (any one; every one when pa=true), b=optional breadcrumbs, x=exclusive with,\n")
        w.write("--   s=start, e=end, o=objectives }, each of s/e/o = { u=creatures, o=objects, i=items }.\n")
        w.write("-- units/objects[id] = { [uiMapID] = { x*10, y*10, ... } } in % of that map's frame; zoneFit[uiMapID] = { top, left,\n")
        w.write("-- h, w } is the frame in world yards; instanceMaps = maps inside an instance; itemObjects[item] = objects that give it; unitFaction[id] = \"A\" or \"H\" for\n")
        w.write("-- creatures friendly to one faction only.\n")
        w.write("local G = GuiaForever\n")
        w.write("G.qdb = G.qdb or {} -- QuestDB.lua (in GuiaForever) already put its functions here\n")
        w.write("G.qdb.zoneFit = {\n")
        for ui in sorted(fit):
            w.write("  [%d]={%s},\n" % (ui, ",".join("%.1f" % v for v in fit[ui])))
        w.write("}\n-- Maps inside an instance: a creature only there is met inside the dungeon.\n")
        w.write("G.qdb.instanceMaps = {%s}\n" % ",".join("[%d]=true" % ui for ui in sorted(instance_maps)))
        w.write("G.qdb.quests = {\n")
        w.write("\n".join(lines))
        w.write("\n}\nG.qdb.units = {\n")
        w.write("\n".join(pos_table("npc", used_npcs)))
        w.write("\n}\nG.qdb.objects = {\n")
        w.write("\n".join(pos_table("object", used_objects)))
        w.write("\n}\nG.qdb.itemObjects = {\n")
        for item in sorted(item_objects):
            objs = sorted(o for o in item_objects[item] if o in used_objects)
            if objs:
                w.write("[%d]={%s},\n" % (item, ",".join(map(str, objs))))
        w.write("}\nG.qdb.titleData = {\n")
        for qid in sorted(titles):
            if titles[qid]:
                w.write("[%d]=%s,\n" % (qid, lua_str(titles[qid])))
        w.write("}\nG.qdb.unitName = {\n")
        for nid in sorted(used_npcs):
            if nid in npcs and npcs[nid].get("name"):
                w.write("[%d]=%s,\n" % (nid, lua_str(npcs[nid]["name"])))
        w.write("}\nG.qdb.unitFaction = {\n")
        for nid in sorted(faction):
            w.write("[%d]=\"%s\",\n" % (nid, faction[nid]))
        w.write("}\nG.qdb.objectName = {\n")
        for oid in sorted(used_objects):
            if oid in objects and objects[oid].get("name"):
                w.write("[%d]=%s,\n" % (oid, lua_str(objects[oid]["name"])))
        w.write("}\n")

    with open(os.path.join(out, "DataQuestDrops.lua"), "w", encoding="utf-8") as w:
        w.write("-- Guía Forever: generated by tools/build_questdb.py from forever-db (see THIRD_PARTY_LICENSES.md). Do not edit by hand.\n")
        w.write("-- G.questDropDB[questID] = { [itemID] = { npcID, chance%, npcID, chance%, ... } } (best sources first; 0 = chance unknown).\n")
        w.write("local G = GuiaForever\nG.questDropDB = {\n")
        w.write("\n".join(drop_lines))
        w.write("\n}\n")

    print("quests", len(lines), "npcs", len(used_npcs), "objects", len(used_objects), "drops", len(drop_lines), "factions", len(faction))


if __name__ == "__main__":
    main()
