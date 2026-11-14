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

-- A giver you can talk to: creatures friendly to the other faction only are left out (objects have no faction).
local myFaction
local function friendly(kind, id)
  if kind ~= "u" then return true end
  local f = Q.unitFaction and Q.unitFaction[id]
  return not f or f == myFaction
end
local function hasGiver(q)
  for _, kind in ipairs({ "u", "o" }) do
    for _, id in ipairs(q.s[kind] or {}) do if friendly(kind, id) then return true end end
  end
  return false
end

-- { [qid] = q } for every quest you could accept now. Prerequisites mean "any one of these done".
-- World-event quests (Darkmoon Faire, holidays) and profession quests are left out.
local function computeAvailable()
  myFaction = (UnitFactionGroup("player") == "Horde") and "H" or "A"
  local level = UnitLevel("player") or 1
  local _, _, race = UnitRace("player")
  local _, _, class = UnitClass("player")
  local minL, maxL = level - greyBelow(level), level + TOO_HARD
  local log, out = inLog(), {}
  local function allowed(mask, id) return not mask or not id or math.floor(mask / 2 ^ (id - 1)) % 2 == 1 end
  for qid, q in pairs(Q.quests) do
    if q.s and (q.s.u or q.s.o) and not q.k and not q.v and (q.m or 1) <= level and (q.l or level) >= minL and (q.l or level) <= maxL
      and allowed(q.r, race) and allowed(q.c, class) and not log[qid] and hasGiver(q) then
      if not Q.done(qid) and (not q.p or anyDone(q.p)) and not (q.x and anyDone(q.x)) then out[qid] = q end
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
end

G.linkHandlers = G.linkHandlers or {}
G.linkHandlers.ruta = function(n)
  local w = links[n]
  if w and G.setWaypoint(w[1], w[2], w[3]) then G.core.msg("Marcador puesto: " .. (w[4] or "") .. ". Seguí la flecha.") end
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
    if G.setWaypoint(self.mapID, self.x / 100, self.y / 100) and G.core then G.core.msg("Camino marcado: " .. (self.name or "?") .. ".") end
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

local ev = CreateFrame("Frame")
for _, e in ipairs({ "QUEST_TURNED_IN", "QUEST_ACCEPTED", "QUEST_REMOVED", "PLAYER_LEVEL_UP" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function() cache = nil; if WorldMapFrame and WorldMapFrame:IsShown() then G.roadmap.refreshPins() end end)
