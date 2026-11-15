-- Guía Forever: dungeon quests, start to end. For each dungeon: every quest it has, whether you did it (asked to the
-- server), and for the ones you are missing the whole chain before them, back to the first quest you can take
-- today, with who gives it, where, and a link that puts the arrow on it.
-- Quest list: DataDungeonQuests.lua, plus the dungeon quests of DungeonQuest / DungeonJournal when installed.
-- Chains, givers and positions: the quest database (QuestDB.lua).
local G = GuiaForever
G.dq = {}
local Q = G.qdb

local function try(fn, ...) if type(fn) ~= "function" then return end local ok, a, b, c = pcall(fn, ...); if ok then return a, b, c end end
local function plain(v) if issecretvalue and issecretvalue(v) then return nil end return v end

-- ---------------------------------------------------------------- dungeon names
-- "The Deadmines" and "Deadmines" are the same place. Scarlet Monastery wings share one list (its quests span
-- wings), and "Stratholme / Scholomance" is two dungeons.
local function norm(name)
  if type(name) ~= "string" then return nil end
  name = name:lower():gsub("^%s+", ""):gsub("%s+$", "")
  name = name:gsub("^the ", ""):gsub("^stormwind ", "")
  if name:find("^scarlet monastery") then return "scarlet monastery" end
  return name
end
local function keysOf(d)
  local out = {}
  for part in (d.key or d.name):gmatch("[^/]+") do out[#out + 1] = norm(part) end
  return out
end

-- Instance IDs (the 8th return of GetInstanceInfo, the same in every client language) of the classic dungeons.
local INSTANCE = {
  [389] = "ragefire chasm", [43] = "wailing caverns", [36] = "deadmines", [33] = "shadowfang keep",
  [48] = "blackfathom deeps", [34] = "stockade", [90] = "gnomeregan", [47] = "razorfen kraul",
  [189] = "scarlet monastery", [129] = "razorfen downs", [70] = "uldaman", [209] = "zul'farrak",
  [349] = "maraudon", [109] = "sunken temple", [230] = "blackrock depths", [429] = "dire maul",
  [329] = "stratholme", [289] = "scholomance",
}

-- ---------------------------------------------------------------- quest list per dungeon
-- byKey[key] = { qid, ... }; ext[qid] = what the other addons know of a quest our database lacks or names
-- differently: { name, starter, faction, prereq, level, minLevel }.
local byKey, ext = nil, {}

local function addInfo(qid, info)
  local x = ext[qid] or {}
  for k, v in pairs(info) do if x[k] == nil then x[k] = v end end
  ext[qid] = x
end
local function add(key, qid, info)
  qid = tonumber(qid)
  if not (key and qid) then return end
  local list = byKey[key]
  if not list then list = { seen = {} }; byKey[key] = list end
  if not list.seen[qid] then list.seen[qid] = true; list[#list + 1] = qid end
  if info then addInfo(qid, info) end
end

local function fromDQ(q)
  return { name = q.name, starter = q.starter, faction = q.faction,
    prereq = type(q.prereq) == "table" and q.prereq or nil, level = q.level, minLevel = q.minLevel }
end

local function build()
  byKey, ext = {}, {}
  for name, ids in pairs(G.dungeonQuestIDs or {}) do
    for _, qid in ipairs(ids) do add(norm(name), qid) end
  end
  local dq = _G.DungeonQuest
  if type(dq) == "table" and type(dq.Dungeons) == "table" then
    for _, d in pairs(dq.Dungeons) do
      if type(d) == "table" and type(d.quests) == "table" then
        local keys = { norm(d.name) }
        for _, a in ipairs(type(d.aliases) == "table" and d.aliases or {}) do keys[#keys + 1] = norm(a) end
        for _, q in ipairs(d.quests) do
          if type(q) == "table" and q.id then
            for _, k in ipairs(keys) do add(k, q.id, fromDQ(q)) end
          end
        end
      end
    end
    for id, q in pairs(type(dq.PrerequisiteQuests) == "table" and dq.PrerequisiteQuests or {}) do
      if type(q) == "table" and tonumber(id) then addInfo(tonumber(id), fromDQ(q)) end
    end
  end
  local fdj = _G.ForeverDungeonJournal_NS
  if type(fdj) == "table" and type(fdj.DB) == "table" then
    for name, d in pairs(fdj.DB) do
      if type(d) == "table" and type(d.quests) == "table" then
        for _, q in ipairs(d.quests) do
          if type(q) == "table" and q.id then add(norm(name), q.id, { name = q.name, starter = q.pickup, faction = q.faction }) end
        end
      end
    end
  end
end

-- ---------------------------------------------------------------- player and quest checks
local function me()
  local faction = UnitFactionGroup("player")
  return UnitLevel("player") or 1, faction, (faction == "Horde") and "H" or "A"
end

local logCache, logAt
local function inLog()
  if logCache and logAt == GetTime() then return logCache end
  logCache, logAt = {}, GetTime()
  for _, e in ipairs(G.core.questEntries()) do if e.id then logCache[e.id] = e end end
  return logCache
end

local function anyDone(list)
  for _, id in ipairs(list or {}) do if Q.done(id) then return true end end
  return false
end

local function dbQuest(qid) return Q.ready() and Q.quests[qid] end

-- A creature giver friendly to the other faction only is not yours (objects and items have no faction).
local function giverOk(kind, id)
  if kind ~= "u" then return true end
  local _, _, short = me()
  local f = Q.unitFaction and Q.unitFaction[id]
  return not f or f == short
end

-- Can this character ever do this quest? Race, class, faction of the giver, and not locked out by a sibling.
local function forMe(qid)
  local _, faction = me()
  local x = ext[qid]
  if x and (x.faction == "Alliance" or x.faction == "Horde") and x.faction ~= faction then return false end
  local q = dbQuest(qid)
  if not q then return true end
  if Q.forPlayer(qid) == false then return false end
  if q.x and anyDone(q.x) then return false end
  if q.s and (q.s.u or q.s.o) then
    for _, kind in ipairs({ "u", "o" }) do
      for _, id in ipairs(q.s[kind] or {}) do if giverOk(kind, id) then return true end end
    end
    return false
  end
  return true
end

-- Who gives a quest and where: { name, mapID, x, y } (x, y in map %), { name, inside = true }, { item, from }
-- or { text } (another addon's description), or nil.
local function giver(qid)
  local q, x = dbQuest(qid), ext[qid]
  if not (q and q.s) then return x and x.starter and { text = x.starter } or nil end
  local here = C_Map and try(C_Map.GetBestMapForUnit, "player")
  local best
  for _, kind in ipairs({ "u", "o" }) do
    for _, id in ipairs(q.s[kind] or {}) do
      if giverOk(kind, id) then
        local list = Q.positions(kind, id)
        local pick = list[1]
        for _, p in ipairs(list) do if p.mapID == here then pick = p; break end end
        -- No known spot, or only spots inside an instance: you meet them in the dungeon.
        local g = pick and not (Q.instanceMaps and Q.instanceMaps[pick.mapID])
          and { name = Q.name(kind, id), mapID = pick.mapID, x = pick.x, y = pick.y }
          or { name = Q.name(kind, id), inside = true }
        if not best or (best.inside and not g.inside) or (g.mapID == here and best.mapID ~= here) then best = g end
      end
    end
  end
  if not best and q.s.i and q.s.i[1] then
    local item = q.s.i[1]
    if C_Item and C_Item.RequestLoadItemDataByID then try(C_Item.RequestLoadItemDataByID, item) end
    local name = Q.name("i", item)
    best = { item = name:find("^objeto %d") and "un objeto" or name, from = G.questStartItemFrom and G.questStartItemFrom[item] }
  end
  return best
end

-- Who you turn a quest in to: { name, mapID, x, y } (map %), nearest to your map first, or nil.
local function ender(qid)
  local q = dbQuest(qid)
  if not (q and q.e) then return nil end
  local here = C_Map and try(C_Map.GetBestMapForUnit, "player")
  local best
  for _, kind in ipairs({ "u", "o" }) do
    for _, id in ipairs(q.e[kind] or {}) do
      if giverOk(kind, id) then
        for _, p in ipairs(Q.positions(kind, id)) do
          if not best or (p.mapID == here and best.mapID ~= here) then best = { name = Q.name(kind, id), mapID = p.mapID, x = p.x, y = p.y } end
        end
      end
    end
  end
  return best
end
G.dq.ender = function(qid) return ender(qid) end
G.dq.giver = function(qid) return giver(qid) end

local function title(qid)
  local t = Q.title(qid)
  if t:find("^misión %d") and ext[qid] and ext[qid].name then return ext[qid].name end
  return t
end
local function levels(qid)
  local q, x = dbQuest(qid), ext[qid] or {}
  return (q and q.l) or x.level, (q and q.m) or x.minLevel
end

-- The quests still to do before qid, oldest first, ending with qid itself: { qid, ... }.
-- Prerequisites mean "any one of these": the branch already in your log wins, then the shortest. A quest marked pa
-- needs every one of them, so every branch not done yet goes in.
local function chain(qid, depth, seen)
  depth, seen = depth or 0, seen or {}
  if depth > 25 or seen[qid] or Q.done(qid) then return {} end
  seen[qid] = true
  local q = dbQuest(qid)
  local pre = (q and q.p) or (ext[qid] and ext[qid].prereq) or nil
  local out = {}
  if pre and #pre > 0 and q and q.pa then
    for _, p in ipairs(pre) do
      if forMe(p) then for _, id in ipairs(chain(p, depth + 1, seen)) do out[#out + 1] = id end end
    end
  elseif pre and #pre > 0 and not anyDone(pre) then
    local log, best, bestScore = inLog(), nil, nil
    for _, p in ipairs(pre) do
      if forMe(p) then
        local sub = chain(p, depth + 1, seen)
        local score = #sub - (log[p] and 1000 or 0)
        if not bestScore or score < bestScore then best, bestScore = sub, score end
      end
    end
    for _, id in ipairs(best or {}) do out[#out + 1] = id end
  end
  out[#out + 1] = qid
  return out
end

-- One dungeon quest for this character: { id, title, level, min, state, steps }.
-- state: "done", "log" (in your quest log), "take" (you can take it now), "low" (not your level yet),
-- "chain" (other quests first). steps: the chain, oldest first, ending with this quest.
local function entry(qid)
  local level = me()
  local e = { id = qid, title = title(qid) }
  e.level, e.min = levels(qid)
  local log = inLog()
  if Q.done(qid) then e.state = "done"
  elseif log[qid] then e.state = "log"; e.complete = log[qid].complete
  else
    e.steps = chain(qid)
    if #e.steps > 1 then e.state = "chain"
    elseif e.min and e.min > level then e.state = "low"
    else e.state = "take" end
  end
  return e
end

-- Every quest of a dungeon (a G.dungeons entry) this character can do, sorted by what to do first, and whether
-- the dungeon has quest data at all. A quest that is a step of another one's chain shows only inside that chain.
local ORDER = { log = 1, take = 2, chain = 3, low = 4, done = 5 }
function G.dq.list(d)
  if not byKey then build() end
  local out, seen, known = {}, {}, false
  for _, key in ipairs(keysOf(d)) do
    for _, qid in ipairs(byKey[key] or {}) do
      known = true
      if not seen[qid] and forMe(qid) then
        seen[qid] = true
        out[#out + 1] = entry(qid)
      end
    end
  end
  local inChain = {}
  for _, e in ipairs(out) do
    for i = 1, #(e.steps or {}) - 1 do inChain[e.steps[i]] = true end
  end
  local kept = {}
  for _, e in ipairs(out) do if not inChain[e.id] then kept[#kept + 1] = e end end
  table.sort(kept, function(a, b)
    if ORDER[a.state] ~= ORDER[b.state] then return ORDER[a.state] < ORDER[b.state] end
    if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) < (b.level or 0) end
    return a.id < b.id
  end)
  return kept, known
end

-- The G.dungeons entry for the dungeon you are standing in, or nil.
function G.dq.current()
  local inInstance, kind = IsInInstance()
  if not inInstance or kind ~= "party" then return nil end
  local name, _, _, _, _, _, _, instanceID = GetInstanceInfo()
  name, instanceID = plain(name), tonumber(plain(instanceID)) or -1
  local fdj = _G.ForeverDungeonJournal_NS
  local wanted = INSTANCE[instanceID]
    or (type(fdj) == "table" and type(fdj.INSTANCE_ID_TO_DUNGEON) == "table" and norm(fdj.INSTANCE_ID_TO_DUNGEON[instanceID]))
    or norm(name)
  for _, d in ipairs(G.dungeons or {}) do
    for _, k in ipairs(keysOf(d)) do if k == wanted then return d end end
  end
end

-- ---------------------------------------------------------------- preparing one dungeon (the dungeon goal)
-- The dungeon you chose to prepare ([Preparar] on Ahora and Guía > Mazmorras, or Ajustes > Mazmorras): while it is
-- set, the next-step bar and "Lo próximo" only take you to that dungeon's quests. Saved per character.
function G.dq.goal()
  local name = G.core and G.core.charDB().dungeonGoal
  if not name then return nil end
  for _, d in ipairs(G.dungeons or {}) do if d.name == name then return d end end
end

function G.dq.setGoal(d)
  if not G.core then return end
  G.core.charDB().dungeonGoal = d and d.name or nil
  G.core.msg(d and ("Preparando " .. d.name .. ": la flecha te lleva a tomar sus misiones.")
    or "Listo el modo mazmorra: la flecha vuelve a guiarte para subir de nivel.")
  if G.nextStep then pcall(G.nextStep.refresh) end
  G.core.render()
end

-- Dungeons worth preparing now: your faction, your level range (or up to 3 levels before it) and at least one quest
-- not done yet.
function G.dq.candidates()
  local level, faction = me()
  local out = {}
  for _, d in ipairs(G.dungeons or {}) do
    if (not d.faction or d.faction == faction) and level >= d.min - 3 and level <= d.max then
      for _, e in ipairs((G.dq.list(d))) do
        if e.state ~= "done" then out[#out + 1] = d; break end
      end
    end
  end
  return out
end

-- What is left to prepare d:
--   take   = { { id, giver } } quests you can take now outside: the dungeon's own and the first step of their chains
--   doing  = { [qid] = true } chain steps in your log: finish (or turn in) them to unlock the next one
--   have   = the dungeon's quests already in your log
--   inside = quests that start inside the dungeon (a drop or someone in there)
--   later  = quests you cannot reach yet (level)
--   want   = the dungeon's quests you can get before going in (have + the ones still to take or unlock)
function G.dq.prepare(d)
  local level, log = me(), inLog()
  local r = { take = {}, doing = {}, have = 0, inside = 0, later = 0, done = 0, total = 0, want = 0 }
  local seen = {}
  -- Returns false when it starts inside the dungeon.
  local function take(qid)
    local g = giver(qid)
    if g and (g.inside or g.item) then if not seen[qid] then r.inside = r.inside + 1 end; seen[qid] = true; return false end
    if not seen[qid] then r.take[#r.take + 1] = { id = qid, giver = g } end
    seen[qid] = true
    return true
  end
  for _, e in ipairs((G.dq.list(d))) do
    r.total = r.total + 1
    if e.state == "done" then r.done = r.done + 1
    elseif e.state == "log" then r.have = r.have + 1; r.want = r.want + 1
    elseif e.state == "take" then if take(e.id) then r.want = r.want + 1 end
    elseif e.state == "low" then r.later = r.later + 1
    elseif e.state == "chain" then
      local first = e.steps[1]
      if log[first] then r.doing[first] = true; r.want = r.want + 1
      else
        local _, m = levels(first)
        if (m or 1) > level then r.later = r.later + 1
        elseif take(first) then r.want = r.want + 1 end
      end
    end
  end
  return r
end

G.dq.title = function(qid) return title(qid) end

-- ---------------------------------------------------------------- text
local links, shownKeys = {}, {}
G.linkHandlers = G.linkHandlers or {}
G.linkHandlers.dq = function(n)
  local w = links[n]
  if w and G.setWaypoint(w.mapID, w.x / 100, w.y / 100, w.name) then G.core.msg("Marcador puesto: " .. (w.name or "") .. ". Lo ves en el mapa (M) y, cuando estás en esa zona, también en pantalla.") end
end
-- [Preparar] / [Dejar]: n = index in G.dungeons, 0 = stop preparing.
G.linkHandlers.dqgoal = function(n) G.dq.setGoal(n > 0 and G.dungeons[n] or nil) end
-- [Ir a la entrada]: n = index in G.dungeons; the arrow (and the flight map distances) then point at the entrance.
G.linkHandlers.dqenter = function(n)
  local d = G.dungeons[n]
  local m, x, y, label, first = G.dq.entrancePoint(d)
  if m and G.setWaypoint(m, x, y, label) then
    if G.nextStep.followEntrance then G.nextStep.followEntrance(d) end
    G.core.msg(first and ("La entrada de " .. d.name .. " está arriba de una montaña: la flecha te lleva primero a donde empieza el camino (" .. first .. ") y, cuando llegás, cambia sola a la entrada. En el maestro de grifos ves qué vuelo te deja más cerca.")
      or ("Marcador en la entrada de " .. d.name .. ". La flecha te lleva; en el maestro de grifos ves qué vuelo te deja más cerca."))
  end
end

-- Where to walk for a dungeon's entrance: mapID, x, y (0-1), label, and the path start's name while it points there.
-- With d.via (the entrance is up a hill that walking straight at would run into rock), the path start comes first;
-- once you have been within 40 m of it, or are within 50 m of the entrance, the entrance itself (remembered until
-- /reload).
local onPath = {}
function G.dq.entrancePoint(d)
  local e = d and d.enter
  if not e then return end
  local v = d.via
  if v and not onPath[d] then
    local ns = G.nextStep
    local pn, pw = ns.playerWorld()
    local function near(p, yards)
      local n, w = ns.world(p[1], p[2] / 100, p[3] / 100)
      return pn and n and math.sqrt((n - pn) ^ 2 + (w - pw) ^ 2) < yards
    end
    if near(v, 40) or near(e, 50) then onPath[d] = true
    else return v[1], v[2] / 100, v[3] / 100, "Subida: " .. v[4], v[4] end
  end
  return e[1], e[2] / 100, e[3] / 100, "Entrada: " .. d.name
end
-- The link next to a dungeon's name: [Preparar] when it has quests left, [Dejar] when it is the one you prepare.
function G.dq.goalLink(d)
  local core = G.core
  if G.dq.goal() == d then return core.C.gold .. " ★ preparando" .. core.C.r .. " " .. core.actionLink("dqgoal", 0, "Dejar") end
  for i, x in ipairs(G.dungeons) do
    if x == d then
      for _, c in ipairs(G.dq.candidates()) do if c == d then return "  " .. core.actionLink("dqgoal", i, "★ Preparar", "|cfffb923c") end end
    end
  end
  return ""
end
-- Called at the start of every render of the window.
function G.dq.clearLinks() links, shownKeys = {}, {} end

local function zoneName(mapID)
  local info = mapID and C_Map and try(C_Map.GetMapInfo, mapID)
  return info and plain(info.name) or ""
end

-- "Gryan Mantorrecio, Páramos de Poniente (56, 48) [Ir]"; plainText = no colors and no link.
local function whereText(qid, plainText)
  local core, C = G.core, G.core.C
  local g = giver(qid)
  if not g then return "no sé quién la da" end
  if g.item then return "empieza con un objeto" .. (g.item ~= "un objeto" and (" (" .. g.item .. ")") or "") .. (g.from and (": " .. g.from) or "") end
  if g.text then return g.text end
  if g.inside or not (g.mapID and g.x and g.y) then return (g.name or "?") .. ", adentro de la mazmorra" end
  local text = (plainText and "" or C.gold) .. g.name .. (plainText and "" or C.r) .. ", " .. zoneName(g.mapID)
    .. string.format(" (%.0f, %.0f)", g.x, g.y)
  if plainText then return text end
  links[#links + 1] = g
  return text .. " " .. core.actionLink("dq", #links, "Ir")
end

local function tag(level) return G.core.C.grey .. "[" .. (level or "?") .. "]" .. G.core.C.r .. " " end

-- One step of a chain. first = the step to do now (the oldest one not in your log).
local function stepLine(qid, first)
  local C = G.core.C
  local l, m = levels(qid)
  if inLog()[qid] then return tag(l) .. title(qid) .. C.green .. " — en tu registro" .. C.r end
  if not first then return C.grey .. "[" .. (l or "?") .. "] " .. title(qid) .. " — después: " .. whereText(qid, true) .. C.r end
  if m and m > me() then return tag(l) .. title(qid) .. C.orange .. " — desde nivel " .. m .. C.r .. ": " .. whereText(qid) end
  return tag(l) .. title(qid) .. " — " .. C.blue .. "tomala: " .. C.r .. whereText(qid)
end

-- [Seguir] next to a chain: prepares this dungeon, so the bar walks you through the chain one quest at a time.
local function followLink(d)
  if G.dq.goal() == d then return G.core.C.gold .. "  ★ ya la estás siguiendo (mirá la flecha)" .. G.core.C.r end
  for i, x in ipairs(G.dungeons) do if x == d then return "  " .. G.core.actionLink("dqgoal", i, "Seguir") end end
  return ""
end

-- The quests of one dungeon. compact: only what to do next (for the "Ahora" tab and the in-dungeon card).
function G.dq.render(d, compact)
  local core, C = G.core, G.core.C
  local B, L = core.B, core.L
  if not Q.ready() then return end
  local id = table.concat(keysOf(d), "+")
  if shownKeys[id] then
    if not compact then B(C.grey .. "Las misiones son las mismas que en el ala de arriba." .. C.r) end
    return
  end
  shownKeys[id] = true
  local list, known = G.dq.list(d)
  if #list == 0 then
    if not compact then
      B(C.grey .. (known and "Esta mazmorra no tiene misiones para tu personaje (raza, clase o facción)."
        or "Todavía no tengo las misiones de esta mazmorra.") .. C.r)
    end
    return
  end
  local n = { done = 0, log = 0, take = 0, chain = 0, low = 0 }
  for _, e in ipairs(list) do n[e.state] = n[e.state] + 1 end
  local parts = { C.gold .. "Misiones: " .. n.done .. "/" .. #list .. " hechas" .. C.r }
  if n.log > 0 then parts[#parts + 1] = C.green .. n.log .. " en tu registro" .. C.r end
  if n.take > 0 then parts[#parts + 1] = C.blue .. n.take .. " para tomar" .. C.r end
  if n.chain > 0 then parts[#parts + 1] = C.orange .. n.chain .. " con misiones antes" .. C.r end
  if n.low > 0 then parts[#parts + 1] = C.grey .. n.low .. " de más nivel" .. C.r end
  B(table.concat(parts, C.grey .. " · " .. C.r))
  if id == "scarlet monastery" then L("     " .. C.grey .. "Todas las alas del Monasterio Escarlata:" .. C.r) end
  local shown, left, chains = 0, #list - n.done, {}
  for _, e in ipairs(list) do
    if e.state ~= "done" then
      if compact and shown >= 6 then break end
      shown = shown + 1
      if e.state == "log" then
        L("     " .. tag(e.level) .. C.green .. e.title .. C.r .. C.grey .. (e.complete and " — lista, entregala" or " — en tu registro") .. C.r)
      elseif e.state == "take" then
        L("     " .. tag(e.level) .. e.title .. " — " .. C.blue .. "tomala: " .. C.r .. whereText(e.id))
      elseif e.state == "low" then
        L("     " .. tag(e.level) .. C.grey .. e.title .. " — desde nivel " .. (e.min or "?") .. C.r .. ": " .. whereText(e.id))
      elseif chains[table.concat(e.steps, ",", 1, #e.steps - 1)] then
        L("     " .. tag(e.level) .. C.orange .. e.title .. C.r .. C.grey .. " — antes, la misma cadena que " .. chains[table.concat(e.steps, ",", 1, #e.steps - 1)] .. C.r)
      else
        local before = #e.steps - 1
        chains[table.concat(e.steps, ",", 1, before)] = e.title
        L("     " .. tag(e.level) .. C.orange .. e.title .. C.r .. C.grey .. " — antes "
          .. (before == 1 and "va 1 misión" or ("van " .. before .. " misiones")) .. ":" .. C.r .. followLink(d))
        local log, reached = inLog(), false
        for i = 1, before do
          local qid = e.steps[i]
          local first = not reached and not log[qid]
          if compact and reached then
            L("          " .. C.grey .. "y " .. (before - i + 1) .. " más después (Guía > Mazmorras)" .. C.r)
            break
          end
          L("          " .. i .. ". " .. stepLine(qid, first))
          if first then reached = true end
        end
      end
    end
  end
  if compact and shown < left then L("     " .. C.grey .. "y " .. (left - shown) .. " más en Guía > Mazmorras." .. C.r) end
  if not compact and n.done > 0 then
    local done = {}
    for _, e in ipairs(list) do if e.state == "done" then done[#done + 1] = e.title end end
    L("     " .. C.grey .. "Hechas: " .. table.concat(done, ", ") .. C.r)
  end
end

-- For the snapshot (Companion.lua): every dungeon near your level, quest by quest, as plain text.
function G.dq.report()
  local level = me()
  local out = {}
  for _, d in ipairs(G.dungeons or {}) do
    if d.max >= level - 2 and d.min <= level + 8 then
      for _, e in ipairs((G.dq.list(d))) do
        local s = d.name .. " | " .. e.id .. " " .. e.title .. " | " .. e.state
        if e.steps and #e.steps > 1 then
          local names = {}
          for i = 1, #e.steps - 1 do names[#names + 1] = e.steps[i] .. " " .. title(e.steps[i]) .. " (" .. whereText(e.steps[i], true) .. ")" end
          s = s .. " | antes: " .. table.concat(names, " > ")
        elseif e.state == "take" or e.state == "low" then
          s = s .. " | " .. whereText(e.id, true)
        end
        out[#out + 1] = s
      end
    end
  end
  return out
end

-- The other addons fill their tables while loading: read them once everything is in.
local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "PLAYER_LOGIN")
ev:SetScript("OnEvent", function() byKey = nil end)
