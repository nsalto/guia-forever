-- Guía Forever: quest database access (data in DataQuestDB.lua, generated data;
-- call Q.ready() before reading Q.quests and the other tables).
-- Who gives and takes each quest, its prerequisites, what it asks for, and where all of that is on the client's map.
-- Positions are stored as classic map %; Forever redrew some zone maps, so they go classic % -> world yards (zoneFit,
-- fitted on DataCity's Forever world coordinates) -> this client's map % (the client's own map bounds, as CityPins.lua).
local G = GuiaForever
G.qdb = G.qdb or {}
local Q = G.qdb

-- False only when DataQuestDB.lua is missing.
function Q.ready() return Q.quests ~= nil or (G.loadData() and Q.quests ~= nil) end

local function try(fn, ...) local ok, a, b, c, d = pcall(fn, ...); if ok then return a, b, c, d end end
local function secret(v) return issecretvalue and issecretvalue(v) end
local function say(text) if G.core and G.core.msg then G.core.msg(text) else print("Guía: " .. text) end end

Q.mapBounds = G.mapBounds

-- Classic map % on uiMapID -> this client's map % on the same map (unchanged when the map has no fit).
function Q.toClient(mapID, x, y)
  local fit, b = Q.zoneFit[mapID], Q.mapBounds(mapID)
  if not (fit and b) then return x, y end
  local worldX = fit[1] - y / 100 * fit[3]
  local worldY = fit[2] - x / 100 * fit[4]
  return (b.left - worldY) / b.w * 100, (b.top - worldX) / b.h * 100
end

-- Every known position of a creature ("u") or object ("o"): { { mapID = , x = , y = }, ... } in client map %.
-- With mapID, only the ones on that map.
function Q.positions(kind, id, mapID)
  if not Q.ready() then return {} end
  local t = (kind == "o" and Q.objects or Q.units)[id]
  local out = {}
  if not t then return out end
  for ui, xy in pairs(t) do
    if not mapID or ui == mapID then
      for i = 1, #xy, 2 do
        local x, y = Q.toClient(ui, xy[i] / 10, xy[i + 1] / 10)
        out[#out + 1] = { mapID = ui, x = x, y = y }
      end
    end
  end
  return out
end

function Q.name(kind, id)
  if not Q.ready() then return (kind == "o" and "objeto " or "PNJ ") .. id end
  if kind == "o" then return Q.objectName[id] or ("objeto " .. id) end
  if kind == "i" then return (GetItemInfo and try(GetItemInfo, id)) or ("objeto " .. id) end
  return Q.unitName[id] or ("PNJ " .. id)
end

function Q.title(qid)
  local t = C_QuestLog and C_QuestLog.GetTitleForQuestID and try(C_QuestLog.GetTitleForQuestID, qid)
  if t and not secret(t) and t ~= "" then return t end
  return (Q.ready() and Q.titleData[qid]) or ("misión " .. qid)
end

function Q.done(qid)
  local f = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted or IsQuestFlaggedCompleted
  return f and try(f, qid) and true or false
end

-- Race / class masks: bit (id - 1) set means allowed.
local function allowed(mask, id) return not mask or not id or math.floor(mask / 2 ^ (id - 1)) % 2 == 1 end
function Q.forPlayer(qid)
  local q = Q.ready() and Q.quests[qid]
  if not q then return nil end
  local _, _, race = UnitRace("player")
  local _, _, class = UnitClass("player")
  return allowed(q.r, race) and allowed(q.c, class)
end

-- Prerequisites, oldest first, without repeats: { qid, ... }. Depth-limited (the data has a few loops).
function Q.chain(qid)
  if not Q.ready() then return {} end
  local out, seen = {}, {}
  local function walk(id, depth)
    local q = Q.quests[id]
    if not q or not q.p or depth > 30 then return end
    for _, pre in ipairs(q.p) do
      if not seen[pre] then
        seen[pre] = true
        walk(pre, depth + 1)
        out[#out + 1] = pre
      end
    end
  end
  walk(qid, 0)
  return out
end

-- The quests that unlock after this one (reverse of p), built once.
local unlocks
function Q.unlocks(qid)
  if not Q.ready() then return {} end
  if not unlocks then
    unlocks = {}
    for id, q in pairs(Q.quests) do
      for _, pre in ipairs(q.p or {}) do
        unlocks[pre] = unlocks[pre] or {}
        table.insert(unlocks[pre], id)
      end
    end
  end
  return unlocks[qid] or {}
end

-- Places for a quest part ("s" start, "e" end, "o" objectives): { { kind, id, name, positions }, ... }.
-- Objective items add the creatures that drop them (DataQuestDrops) and the objects that give them.
function Q.places(qid, part, mapID)
  if not Q.ready() then return {} end
  local q = Q.quests[qid]
  local p = q and q[part]
  local out = {}
  if not p then return out end
  local function add(kind, id, why)
    out[#out + 1] = { kind = kind, id = id, name = Q.name(kind, id), why = why, positions = Q.positions(kind, id, mapID) }
  end
  for _, id in ipairs(p.u or {}) do add("u", id) end
  for _, id in ipairs(p.o or {}) do add("o", id) end
  if part == "o" then
    for _, item in ipairs(p.i or {}) do
      local drops = G.questDropDB and G.questDropDB[qid] and G.questDropDB[qid][item]
      if drops then for i = 1, #drops, 2 do add("u", drops[i], { item = item, chance = drops[i + 1] }) end end
      for _, obj in ipairs(Q.itemObjects[item] or {}) do add("o", obj, { item = item }) end
    end
  end
  return out
end

-- The position closest to the player among a list of places, on the player's current map.
function Q.nearest(places)
  local mapID = C_Map and try(C_Map.GetBestMapForUnit, "player")
  local pos = mapID and try(C_Map.GetPlayerMapPosition, mapID, "player")
  local px, py
  if pos and not secret(pos) then px, py = pos:GetXY() end
  if not px or secret(px) then return nil end
  px, py = px * 100, py * 100
  local best, bestD
  for _, pl in ipairs(places) do
    for _, p in ipairs(pl.positions) do
      if p.mapID == mapID then
        local d = (p.x - px) ^ 2 + (p.y - py) ^ 2
        if not bestD or d < bestD then best, bestD = { place = pl, mapID = p.mapID, x = p.x, y = p.y }, d end
      end
    end
  end
  return best
end

-- /guia qdb [questID]: what the database knows about a quest, plus which navigation APIs this client has.
function Q.diagnose(qid)
  local probes = {
    { "GetPlayerFacing", GetPlayerFacing },
    { "C_Map.GetMapRectOnMap", C_Map and C_Map.GetMapRectOnMap },
    { "C_Map.GetMapWorldSize", C_Map and C_Map.GetMapWorldSize },
    { "C_Minimap.GetViewRadius", C_Minimap and C_Minimap.GetViewRadius },
    { "C_QuestLog.IsQuestFlaggedCompleted", C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted },
    { "C_QuestLog.GetTitleForQuestID", C_QuestLog and C_QuestLog.GetTitleForQuestID },
  }
  local have = {}
  for _, p in ipairs(probes) do have[#have + 1] = p[1] .. (p[2] and " sí" or " NO") end
  if not Q.ready() then say("La base de misiones no está cargada (falta DataQuestDB.lua: copiá la carpeta GuiaForever entera de nuevo).") return end
  local facing = GetPlayerFacing and try(GetPlayerFacing)
  say("APIs: " .. table.concat(have, ", ") .. ". Orientación ahora: " .. tostring(facing and not secret(facing) and string.format("%.2f", facing) or "no disponible") .. ".")
  if not qid then
    local n = 0
    for _ in pairs(Q.quests) do n = n + 1 end
    say("Base de misiones: " .. n .. " misiones. Probá /guia qdb <id de misión>.")
    return
  end
  local q = Q.quests[qid]
  if not q then say("La base no tiene la misión " .. qid .. ".") return end
  say(string.format("%s (%d): nivel %s, desde %s, %s, %s.", Q.title(qid), qid, q.l or "?", q.m or "?",
    Q.forPlayer(qid) and "es para vos" or "no es para tu raza o clase", Q.done(qid) and "ya hecha" or "sin hacer"))
  local chain = Q.chain(qid)
  if #chain > 0 then
    local names = {}
    for _, id in ipairs(chain) do names[#names + 1] = Q.title(id) .. (Q.done(id) and " (hecha)" or "") end
    say("Antes: " .. table.concat(names, " > "))
  end
  for _, part in ipairs({ { "s", "La da" }, { "e", "Se entrega a" }, { "o", "Objetivos" } }) do
    for _, pl in ipairs(Q.places(qid, part[1])) do
      local p = pl.positions[1]
      local where = p and string.format("mapa %d, %.1f %.1f", p.mapID, p.x, p.y) or "sin posición"
      local why = pl.why and (" (suelta " .. Q.name("i", pl.why.item) .. (pl.why.chance and (" " .. pl.why.chance .. "%") or "") .. ")") or ""
      say(part[2] .. ": " .. pl.name .. why .. " · " .. where .. (#pl.positions > 1 and (" y " .. (#pl.positions - 1) .. " más") or ""))
    end
  end
end
