-- Guía Forever: leveling roadmap. From the quest database (QuestDB.lua) and your character, works out which quests
-- you can pick up right now (level, race, class, prerequisites done, not done yet, not in your log), which zones
-- have the most of them for your level, and puts "!" pins on the world map where their givers stand.
-- Nothing here is hand-written: it follows your progress quest by quest.
local G = GuiaForever
G.roadmap = {}
local Q = G.qdb

local function try(fn, ...) if type(fn) ~= "function" then return end local ok, a, b, c = pcall(fn, ...); if ok then return a, b, c end end
local function plain(v) if issecretvalue and issecretvalue(v) then return nil end return v end
local function db() return G.core and G.core.db() end
local function pinsOn() local d = db(); return d and d.roadmapPins ~= false end

-- Quests more than this many levels under you give almost no XP (grey in the quest log).
local function greyBelow(level)
  if level < 40 then return 5 + math.floor(level / 10) end
  return 1 + math.floor(level / 5)
end
local TOO_HARD = 3 -- levels above you that are still worth taking

local function playerPos()
  local mapID = C_Map and try(C_Map.GetBestMapForUnit, "player")
  local pos = mapID and try(C_Map.GetPlayerMapPosition, mapID, "player")
  local x, y
  if pos and plain(pos) and pos.GetXY then x, y = pos:GetXY() end
  x, y = plain(x), plain(y)
  return mapID, x and x * 100, y and y * 100
end

-- ---------------------------------------------------------------- which quests you can take
local cache, cacheAt, cacheLevel = nil, 0, nil

local function inLog()
  local set = {}
  for _, e in ipairs(G.core.questEntries()) do if e.id then set[e.id] = true end end
  return set
end

local function anyDone(list)
  for _, id in ipairs(list) do if Q.done(id) then return true end end
  return false
end
local function allDone(list)
  for _, id in ipairs(list) do if not Q.done(id) then return false end end
  return true
end
-- Prerequisites are met: any one of them, or every one when the quest says so (pa).
local function preMet(q) return not q.p or (q.pa and allDone(q.p)) or (not q.pa and anyDone(q.p)) end

-- A giver you can talk to: creatures friendly to the other faction only are left out (objects have no faction).
local myFaction
local function friendly(kind, id)
  if kind ~= "u" then return true end
  local f = Q.unitFaction and Q.unitFaction[id]
  return not f or f == myFaction
end
-- Quests an item starts are offered by the listed giver too only while you carry that item (the library books).
local function itemCount(id)
  local f = (C_Item and C_Item.GetItemCount) or GetItemCount
  local n = f and plain(try(f, id))
  return type(n) == "number" and n or 0
end
local function haveStartItem(q)
  if not q.s.i then return true end
  for _, id in ipairs(q.s.i) do if itemCount(id) > 0 then return true end end
  return false
end
local function hasGiver(q)
  for _, kind in ipairs({ "u", "o" }) do
    for _, id in ipairs(q.s[kind] or {}) do if friendly(kind, id) then return true end end
  end
  return false
end

-- What the server really offers. The quest data comes from the classic game and Forever changed some quests, so when
-- you open a quest giver, the quests expected from them that the server did not offer are remembered per character
-- (with your level then) and left out until you level up. The XP the server shows for an offered quest is kept too.
local function learned()
  local c = G.core and G.core.charDB and G.core.charDB()
  if not c then return {}, {} end
  c.notOffered = c.notOffered or {}
  c.questXP = c.questXP or {}
  return c.notOffered, c.questXP
end
-- Quests the server offers again after you turn them in (repeatable in Forever, not in the data): left out of the route.
local function repeats()
  local c = G.core and G.core.charDB and G.core.charDB()
  if not c then return {} end
  c.repeatable = c.repeatable or {}
  return c.repeatable
end
-- Givers you opened recently ("u123" -> time): the next step goes to the other givers at the same stop first.
local talked = {}
function G.roadmap.talked(kind, id) local t = talked[(kind or "") .. (id or "")]; return t and GetTime() - t < 300 end
-- "[No está]": the giver is not where the data says (Forever moved or removed it). Its quests leave the route until
-- you level up, like quests a giver did not offer.
function G.roadmap.skipQuests(list)
  local notOffered = learned()
  local level = UnitLevel("player") or 1
  for _, qid in ipairs(list or {}) do notOffered[qid] = level end
  cache = nil
end

-- { [qid] = q } for every quest you could accept now. Prerequisites mean "any one of these done".
-- World-event quests (Darkmoon Faire, holidays) and profession quests are left out.
local function computeAvailable()
  myFaction = (UnitFactionGroup("player") == "Horde") and "H" or "A"
  local level = UnitLevel("player") or 1
  local notOffered, rep = learned(), repeats()
  local _, _, race = UnitRace("player")
  local _, _, class = UnitClass("player")
  local minL, maxL = level - greyBelow(level), level + TOO_HARD
  local log, out = inLog(), {}
  local function allowed(mask, id) return not mask or not id or math.floor(mask / 2 ^ (id - 1)) % 2 == 1 end
  for qid, q in pairs(Q.quests) do
    if q.s and (q.s.u or q.s.o) and not q.k and not q.v and (q.m or 1) <= level and (q.l or level) >= minL and (q.l or level) <= maxL
      and allowed(q.r, race) and allowed(q.c, class) and not log[qid] and hasGiver(q) and haveStartItem(q) then
      if not Q.done(qid) and preMet(q) and not (q.x and anyDone(q.x))
        and not (notOffered[qid] and notOffered[qid] >= level) and not rep[qid] then out[qid] = q end
    end
  end
  return out
end

-- Recomputed at most every 10 s, and right away after a level-up or a quest change (G.roadmap.invalidate).
local function available()
  local level = UnitLevel("player")
  if cache and level == cacheLevel and GetTime() - cacheAt < 10 then return cache end
  cache, cacheAt, cacheLevel = computeAvailable(), GetTime(), level
  return cache
end
function G.roadmap.invalidate() cache = nil end

-- Givers of available quests on one map: { key = "u123", kind, id, name, x, y, quests = { qid, ... } }.
local function giversOn(mapID, list)
  local by = {}
  for qid, q in pairs(list) do
    for _, kind in ipairs({ "u", "o" }) do
      for _, id in ipairs(q.s[kind] or {}) do
        local pos = friendly(kind, id) and Q.positions(kind, id, mapID)[1]
        if pos then
          local key = kind .. id
          local g = by[key]
          if not g then
            g = { key = key, kind = kind, id = id, name = Q.name(kind, id), x = pos.x, y = pos.y, quests = {} }
            by[key] = g
          end
          g.quests[#g.quests + 1] = qid
        end
      end
    end
  end
  return by
end

-- ---------------------------------------------------------------- quests worth picking up (for "Lo próximo")
-- Rough reward of a quest, only to rank quests you have not opened yet (never shown): the XP the server showed you at
-- this level when known, else a curve close to classic rewards (600 at 10, 1500 at 20, 2700 at 30), cut for quests
-- under your level like the game does.
local function worth(qid, q, level)
  local _, seen = learned()
  local s = seen[qid]
  if s and s[2] == level and s[1] then return s[1] end
  local l = q.l or level
  local xp = 45 * l + 1.5 * l * l
  local under = level - l
  if under > 5 then xp = xp * math.max(0.1, 1 - (under - 5) * 0.2) end
  return xp
end

local dungeonSet
local function isDungeonQuest(qid)
  if not dungeonSet then
    dungeonSet = {}
    for _, ids in pairs(G.dungeonQuestIDs or {}) do for _, id in ipairs(ids) do dungeonSet[id] = true end end
  end
  return dungeonSet[qid]
end

-- True when the quest asks only for items no creature drops and no object gives in the data (bought, crafted, from a
-- battleground...): the guide could not tell you where to get them.
local function noSource(qid, q)
  local o = q.o
  if not (o and o.i) or o.u or o.o then return false end
  for _, item in ipairs(o.i) do
    local drops = G.questDropDB and G.questDropDB[qid] and G.questDropDB[qid][item]
    if (drops and #drops > 0) or (Q.itemObjects and Q.itemObjects[item]) then return false end
  end
  return true
end

-- Value of one available quest for a straight leveling route, or nil when it is not worth it: dungeon quests only
-- when they are for a dungeon you are preparing (boost set), nothing more than 2 levels over you, no donations or
-- battleground quests, nothing whose items have no known source. Quests that open a chain, class quests, important
-- quests (DataImportant.lua) and quests for your next dungeon are worth more.
local function questValue(qid, q, level, boost)
  local boosted = boost and boost[qid]
  local important = q.c or (G.importantIndex and G.importantIndex[qid])
  if G.notForLeveling and G.notForLeveling[qid] then return end
  if not boosted and isDungeonQuest(qid) then return end
  if not boosted and (q.l or level) > level + 2 then return end
  if not (boosted or important) and noSource(qid, q) then return end
  local v = worth(qid, q, level) * (1 + 0.25 * math.min(#Q.unlocks(qid), 3))
  if important then v = v * 1.5 end
  if boosted then v = v * 2.5 end
  return v
end

local function worthOn(givers, level, boost)
  local out = {}
  for _, g in pairs(givers) do
    local keep, value, dungeon = {}, 0, 0
    for _, qid in ipairs(g.quests) do
      local v = questValue(qid, Q.quests[qid], level, boost)
      if v then
        keep[#keep + 1] = qid; value = value + v
        if boost and boost[qid] then dungeon = dungeon + 1 end
      end
    end
    if #keep > 0 then
      table.sort(keep, function(a, b) return (Q.quests[a].l or 0) < (Q.quests[b].l or 0) end)
      out[#out + 1] = { name = g.name, x = g.x / 100, y = g.y / 100, quests = keep, value = value, dungeon = dungeon }
    end
  end
  return out
end

-- Givers on mapID with quests worth taking: { name, x, y (0-1), quests = { qid }, value }.
function G.roadmap.pickups(mapID, boost)
  if not (mapID and Q.ready()) then return {} end
  return worthOn(giversOn(mapID, available()), UnitLevel("player") or 1, boost)
end

-- Every map with quests worth taking, best first: { mapID, n, dungeon, value, best = giver with the most value there }
-- (dungeon = how many of the n are quests for the dungeon you are preparing).
function G.roadmap.zones(boost)
  if not Q.ready() then return {} end
  local level, list = UnitLevel("player") or 1, available()
  local maps = {}
  for _, q in pairs(list) do
    for _, kind in ipairs({ "u", "o" }) do
      for _, id in ipairs(q.s[kind] or {}) do
        if friendly(kind, id) then for ui in pairs(((kind == "o") and Q.objects or Q.units)[id] or {}) do maps[ui] = true end end
      end
    end
  end
  local out = {}
  for ui in pairs(maps) do
    local givers = worthOn(giversOn(ui, list), level, boost)
    if #givers > 0 then
      local z = { mapID = ui, n = 0, dungeon = 0, value = 0 }
      for _, g in ipairs(givers) do
        z.n, z.value, z.dungeon = z.n + #g.quests, z.value + g.value, z.dungeon + g.dungeon
        if not z.best or g.value > z.best.value then z.best = g end
      end
      out[#out + 1] = z
    end
  end
  table.sort(out, function(a, b) if a.value ~= b.value then return a.value > b.value end return a.mapID < b.mapID end)
  return out
end

-- The continent a map belongs to (to warn about boats and long trips), or nil.
function G.roadmap.continent(mapID)
  local CONTINENT = (Enum and Enum.UIMapType and Enum.UIMapType.Continent) or 2
  for _ = 1, 6 do
    local info = mapID and C_Map and try(C_Map.GetMapInfo, mapID)
    if not info then return end
    if info.mapType == CONTINENT then return mapID, info.name end
    mapID = info.parentMapID
  end
end

function G.roadmap.learnedCount()
  local n, level = 0, UnitLevel("player") or 1
  for _, l in pairs((learned())) do if l >= level then n = n + 1 end end
  return n
end

local function questLine(qid, level)
  local q = Q.quests[qid]
  local l = q.l or level
  local color = (l >= level + 3 and "|cffff6040") or (l >= level + 1 and "|cffffa040") or (l >= level - 2 and "|cffffff40") or "|cff40c040"
  local opens = #Q.unlocks(qid)
  return color .. "[" .. l .. "]|r " .. Q.title(qid) .. (opens > 0 and ("|cff9ca3af · abre " .. opens .. (opens == 1 and " misión" or " misiones") .. "|r") or "")
end

-- ---------------------------------------------------------------- "Ruta" tab
local links = {} -- [n] = { mapID, x, y, name } for the [Ir] links of the last render

function G.roadmap.build(s)
  local core, C = G.core, G.core.C
  local H, L, B = core.H, core.L, core.B
  links = {}
  if not Q.ready() then
    L(C.grey .. "Falta la base de misiones (DataQuestDB.lua): copiá la carpeta GuiaForever entera de nuevo." .. C.r)
    return
  end
  local level = UnitLevel("player") or 1
  local list = available()
  local mapID, px, py = playerPos()

  -- Zones with the most quests for you
  local perMap = {}
  for qid, q in pairs(list) do
    local maps = {}
    for _, kind in ipairs({ "u", "o" }) do
      for _, id in ipairs(q.s[kind] or {}) do
        if friendly(kind, id) then
          for ui in pairs(((kind == "o") and Q.objects or Q.units)[id] or {}) do maps[ui] = true end
        end
      end
    end
    for ui in pairs(maps) do perMap[ui] = (perMap[ui] or 0) + 1 end
  end
  local zones = {}
  for ui, n in pairs(perMap) do zones[#zones + 1] = { mapID = ui, n = n } end
  table.sort(zones, function(a, b) return a.n > b.n end)
  H("Ruta para tu nivel " .. level)
  if #zones == 0 then
    B(C.grey .. "No encontré misiones para tomar en tu rango. Entregá las que tengas o probá una zona de tu nivel." .. C.r)
  end
  for i = 1, math.min(4, #zones) do
    local z = zones[i]
    local info = C_Map and try(C_Map.GetMapInfo, z.mapID)
    local here = z.mapID == mapID
    B((here and C.green or C.gold) .. (info and info.name or ("mapa " .. z.mapID)) .. C.r .. ": " .. z.n .. " misiones para tomar"
      .. (here and (C.grey .. " (estás acá)" .. C.r) or ""))
  end
  local logCount = #core.questEntries()
  if logCount >= 20 then B(C.orange .. "Tu registro está lleno (" .. logCount .. "/20): entregá o abandoná algo antes de tomar más." .. C.r) end

  -- Givers in this zone, closest first, more quests first
  H("Para tomar acá")
  local givers = {}
  for _, g in pairs(mapID and giversOn(mapID, list) or {}) do
    g.d = (px and ((g.x - px) ^ 2 + (g.y - py) ^ 2) ^ 0.5) or 0
    givers[#givers + 1] = g
  end
  table.sort(givers, function(a, b)
    local sa, sb = a.d / (#a.quests + 1), b.d / (#b.quests + 1)
    if sa ~= sb then return sa < sb end
    return a.key < b.key
  end)
  if #givers == 0 then B(C.grey .. "Nada para tomar en esta zona: mirá la ruta de arriba." .. C.r) end
  for i = 1, math.min(8, #givers) do
    local g = givers[i]
    links[#links + 1] = { mapID, g.x / 100, g.y / 100, g.name }
    local dir = px and string.format("%.0f, %.0f", g.x, g.y) or ""
    L(C.gold .. g.name .. C.r .. C.grey .. "  " .. dir .. C.r .. "  " .. core.actionLink("ruta", #links, "Ir"))
    table.sort(g.quests, function(a, b) return (Q.quests[a].l or 0) < (Q.quests[b].l or 0) end)
    for _, qid in ipairs(g.quests) do B(questLine(qid, level)) end
  end
  if #givers > 8 then L(C.grey .. "  y " .. (#givers - 8) .. " PNJ más: todos están en el mapa con un \"!\"." .. C.r) end
  local fixed = G.roadmap.learnedCount()
  if fixed > 0 then
    L(C.grey .. "Corregido con el servidor: " .. fixed .. (fixed == 1 and " misión que el Forever no ofrece" or " misiones que el Forever no ofrece") .. " (salen de la ruta hasta que subas de nivel)." .. C.r)
  end
end

G.linkHandlers = G.linkHandlers or {}
G.linkHandlers.ruta = function(n)
  local w = links[n]
  if w and G.setWaypoint(w[1], w[2], w[3], w[4]) then G.core.msg("Marcador puesto: " .. (w[4] or "") .. ". Lo ves en el mapa (M) y, cuando estás en esa zona, también en pantalla.") end
end

-- ---------------------------------------------------------------- "!" on the world map
local pins = {}
local function pinFrame(i)
  local p = pins[i]
  if p then return p end
  p = CreateFrame("Button", nil, UIParent)
  p:SetSize(20, 20)
  p.icon = p:CreateTexture(nil, "ARTWORK")
  p.icon:SetAllPoints()
  p.icon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
  p:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(self.name or "?", 1, 0.82, 0)
    local level = UnitLevel("player") or 1
    for _, qid in ipairs(self.quests or {}) do GameTooltip:AddLine(questLine(qid, level), 1, 1, 1, true) end
    GameTooltip:AddLine("Clic: marcar el camino", 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end)
  p:SetScript("OnLeave", function() GameTooltip:Hide() end)
  p:SetScript("OnClick", function(self)
    if G.setWaypoint(self.mapID, self.x / 100, self.y / 100, self.name) and G.core then G.core.msg("Camino marcado: " .. (self.name or "?") .. ".") end
  end)
  pins[i] = p
  return p
end
local function hideAll() for _, p in ipairs(pins) do p:Hide() end end

local provider
local function refresh()
  hideAll()
  if not (provider and pinsOn() and Q.ready()) then return end
  local map = provider:GetMap()
  local mapID = map and map:GetMapID()
  if not mapID then return end
  local canvas = map:GetCanvas()
  local w, h = canvas:GetWidth(), canvas:GetHeight()
  local scale = 1 / ((map.GetCanvasScale and map:GetCanvasScale()) or 1)
  local n = 0
  for _, g in pairs(giversOn(mapID, available())) do
    if g.x > 0 and g.x < 100 and g.y > 0 and g.y < 100 then
      n = n + 1
      local p = pinFrame(n)
      p:SetParent(canvas)
      p:SetFrameLevel(canvas:GetFrameLevel() + 1990)
      p:SetScale(scale)
      p.mapID, p.x, p.y, p.name, p.quests = mapID, g.x, g.y, g.name, g.quests
      p:ClearAllPoints()
      p:SetPoint("CENTER", canvas, "TOPLEFT", (g.x / 100) * w / scale, -(g.y / 100) * h / scale)
      p:Show()
    end
  end
end

if WorldMapFrame and WorldMapFrame.AddDataProvider and MapCanvasDataProviderMixin and CreateFromMixins then
  provider = CreateFromMixins(MapCanvasDataProviderMixin)
  function provider:RemoveAllData() hideAll() end
  function provider:RefreshAllData() local ok = pcall(refresh); if not ok then hideAll() end end
  function provider:OnCanvasScaleChanged() self:RefreshAllData() end
  WorldMapFrame:AddDataProvider(provider)
end
function G.roadmap.refreshPins() if provider then provider:RefreshAllData() end end

-- ---------------------------------------------------------------- learning from the quest giver window
-- The creature ("u") or object ("o") whose window is open, from its GUID ("Creature-0-x-x-x-<id>-x").
local function openGiver()
  local guid = plain(UnitGUID and UnitGUID("npc"))
  if type(guid) ~= "string" then return end
  local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)")
  if kind == "Creature" then return "u", tonumber(id) elseif kind == "GameObject" then return "o", tonumber(id) end
end

-- Quest IDs the open window offers, or nil when the client does not say (then nothing is learned).
local function offeredNow(event)
  local set = {}
  if event == "GOSSIP_SHOW" then
    local list = C_GossipInfo and try(C_GossipInfo.GetAvailableQuests)
    if type(list) ~= "table" then return end
    for _, q in ipairs(list) do if q.questID then set[q.questID] = true end end
    return set
  end
  if not (GetNumAvailableQuests and GetAvailableQuestInfo) then return end
  for i = 1, (try(GetNumAvailableQuests) or 0) do
    local ok, _, _, _, _, qid = pcall(GetAvailableQuestInfo, i)
    if not (ok and qid) then return end
    set[qid] = true
  end
  return set
end

local function learn(event, given)
  if not Q.ready() then return end
  local kind, id = openGiver()
  if kind then talked[kind .. id] = GetTime() end
  local offered = kind and (given or offeredNow(event))
  if not offered then return end
  local notOffered = learned()
  local level = UnitLevel("player") or 1
  local changed = false
  for qid in pairs(offered) do if notOffered[qid] then notOffered[qid], changed = nil, true end end
  -- Quests near grey can be hidden by the "low level quests" tracking option: those are never counted as missing.
  -- Only quests this giver alone starts are judged (another giver may still offer the rest).
  local floor = level - greyBelow(level) + 2
  local missing = {}
  for qid, q in pairs(available()) do
    if not offered[qid] and (q.l or level) >= floor then
      local givers, mine = 0, false
      for _, k in ipairs({ "u", "o" }) do
        for _, sid in ipairs(q.s[k] or {}) do
          if friendly(k, sid) then givers = givers + 1; if k == kind and sid == id then mine = true end end
        end
      end
      if mine and givers == 1 then notOffered[qid] = level; missing[#missing + 1] = Q.title(qid); changed = true end
    end
  end
  if #missing > 0 and G.core then
    G.core.msg("Este PNJ no te ofrece " .. table.concat(missing, ", ") .. " (cambió en el Forever o pide algo antes): la saco de la ruta hasta que subas de nivel.")
  end
  if changed then cache = nil; if G.core and G.core.render then G.core.render() end end
end

-- The quest window shows the real reward XP: kept so the ranking uses it while you stay at this level.
-- A giver with a single quest opens it straight away, with no list first: then that quest is all it offers.
local listGuid, listAt = nil, 0
local function learnDetail()
  local qid = GetQuestID and try(GetQuestID)
  if not qid or qid == 0 then return end
  local guid = plain(UnitGUID and UnitGUID("npc"))
  if guid and (guid ~= listGuid or GetTime() - listAt > 30) then pcall(learn, "QUEST_DETAIL", { [qid] = true }) end
  local notOffered, seen = learned()
  notOffered[qid] = nil
  local xp = GetRewardXP and plain(try(GetRewardXP))
  if type(xp) == "number" and xp > 0 then seen[qid] = { xp, UnitLevel("player") or 1 } end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "QUEST_TURNED_IN", "QUEST_ACCEPTED", "QUEST_REMOVED", "PLAYER_LEVEL_UP", "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "BAG_UPDATE_DELAYED" }) do
  pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, arg1)
  if event == "QUEST_TURNED_IN" and type(arg1) == "number" then
    local qid = arg1
    C_Timer.After(3, function()
      if not Q.done(qid) then repeats()[qid] = true; cache = nil; if G.core and G.core.render then G.core.render() end end
    end)
  end
  if event == "GOSSIP_SHOW" or event == "QUEST_GREETING" then
    listGuid, listAt = plain(UnitGUID and UnitGUID("npc")), GetTime()
    pcall(learn, event); return
  end
  if event == "QUEST_DETAIL" then pcall(learnDetail); return end
  cache = nil
  if WorldMapFrame and WorldMapFrame:IsShown() then G.roadmap.refreshPins() end
end)
