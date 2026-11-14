-- Guía Forever: contextual guide window. Reads only the player's own state through the
-- standard API and shows bundled guide data (Data*.lua). It never acts in the game.
local ADDON = ...
local G = GuiaForever -- data namespace filled by Data*.lua
local DB

local C = {
  title = "|cffd97757", gold = "|cffffd100", green = "|cff4ade80", grey = "|cff9ca3af",
  red = "|cfff87171", blue = "|cff7dd3fc", orange = "|cfffb923c", r = "|r",
}
local TABS = { "Ahora", "Misiones", "Ruta", "Grupo", "Clase", "Guía" }
local TAB_CLASS = 5

local function try(fn, ...) local ok, a, b, c, d, e, f, g = pcall(fn, ...); if ok then return a, b, c, d, e, f, g end end

-- Map waypoint + the game's arrow to it (x, y from 0 to 1). The one place that sets it: quests, steps, city pins,
-- SOS and /guia ir all go through here. False when the client cannot put one on that map.
function G.setWaypoint(mapID, x, y)
  if not (mapID and x and y and UiMapPoint and C_Map and C_Map.SetUserWaypoint) then return false end
  if C_Map.CanSetUserWaypointOnMap and not try(C_Map.CanSetUserWaypointOnMap, mapID) then return false end
  if not pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(mapID, x, y)) then return false end
  if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then try(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
  return true
end

-- A map's world bounds on this client: { top, left, h, w, inst } in world yards (north X, west Y), or false.
-- Forever redrew some zone maps, so classic map % can be off by several percent; the client's own bounds
-- (same method as HereBeDragons) are always right. Used by CityPins and QuestDB.
local bounds = {}
function G.mapBounds(mapID)
  if bounds[mapID] ~= nil then return bounds[mapID] end
  bounds[mapID] = false
  if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return false end
  local ok1, inst, tl = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(0, 0))
  local ok2, _, br = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(1, 1))
  if not (ok1 and ok2 and tl and br and tl.GetXY) then return false end
  local top, left = tl:GetXY()
  local bottom, right = br:GetXY()
  if not (top and left and bottom and right) or top == bottom or left == right then return false end
  bounds[mapID] = { top = top, left = left, h = top - bottom, w = left - right, inst = inst }
  return bounds[mapID]
end

-- ---------------------------------------------------------------- data
-- Recipes and the quest database (DataRecipes.lua, DataQuestDB.lua) load with the addon. G.loadData() stays as the
-- single "is the data there?" check the other files call.
function G.loadData() return G.qdb ~= nil and G.qdb.quests ~= nil end

-- ---------------------------------------------------------------- player state
local function playerState()
  local s = {}
  s.level = UnitLevel("player") or 1
  s.class = select(2, UnitClass("player")) or "ROGUE"
  s.faction = UnitFactionGroup("player") or "Alliance"
  s.zone = GetZoneText() or ""
  s.mapID = C_Map and try(C_Map.GetBestMapForUnit, "player")
  local function num(v) if issecretvalue and issecretvalue(v) then return nil end return tonumber(v) end
  s.xp, s.xpMax = num(UnitXP("player")) or 0, num(UnitXPMax("player")) or 1
  s.rested = num(GetXPExhaustion and GetXPExhaustion()) or 0
  s.skills = {}
  if GetNumSkillLines then
    for i = 1, GetNumSkillLines() do
      local name, isHeader, _, rank, _, _, maxRank = try(GetSkillLineInfo, i)
      if name and not isHeader then s.skills[name] = { rank = rank or 0, max = maxRank or 0 } end
    end
  end
  s.completeQuests, s.quests = 0, 0
  if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
    for i = 1, (try(C_QuestLog.GetNumQuestLogEntries) or 0) do
      local q = try(C_QuestLog.GetInfo, i)
      if q and not q.isHeader then
        s.quests = s.quests + 1
        if try(C_QuestLog.IsComplete, q.questID) then s.completeQuests = s.completeQuests + 1 end
      end
    end
  elseif GetNumQuestLogEntries then
    for i = 1, (GetNumQuestLogEntries() or 0) do
      local title, _, _, isHeader, _, isComplete = try(GetQuestLogTitle, i)
      if title and not isHeader then
        s.quests = s.quests + 1
        if isComplete == 1 then s.completeQuests = s.completeQuests + 1 end
      end
    end
  end
  return s
end

local function zoneData(s)
  if s.mapID and G.zonesByMap[s.mapID] then return G.zonesByMap[s.mapID] end
  local z = (s.zone or ""):lower()
  for _, d in ipairs(G.zones) do
    for _, alias in ipairs(d.names) do
      if z == alias:lower() then return d end
    end
  end
end

local function factionOk(entry, faction)
  return not entry.faction or entry.faction == "Both" or entry.faction == faction
end

-- ---------------------------------------------------------------- text builders
local out
-- Section icons, matched by the start of the section title.
local SECTION_ICONS = {
  { "Tu zona", "INV_Misc_Map_01" }, { "Otras zonas", "INV_Misc_Map02" },
  { "Mazmorras", "INV_Misc_Key_14" }, { "Próximo", "INV_Misc_Book_09" }, { "Se viene", "INV_Misc_PocketWatch_01" },
  { "Consejo", "INV_Misc_Note_01" }, { "Pendientes", "INV_Misc_Note_02" }, { "Tu sesión", "INV_Misc_PocketWatch_02" }, { "Para hacer", "INV_Misc_Note_02" }, { "Tu ritmo", "INV_Misc_PocketWatch_02" }, { "Cerca de vos", "INV_Sword_04" }, { "Misiones en común", "INV_Misc_Note_06" }, { "A tus amigos", "INV_Letter_15" }, { "Profesiones", "Trade_Leatherworking" }, { "Cómo sacarle", "INV_Misc_QuestionMark" }, { "Enemigos que vio", "Ability_Hunter_SniperShot" }, { "Tu grupo", "Ability_Warrior_BattleShout" }, { "PvP", "INV_Sword_04" }, { "Comparar", "INV_Misc_Spyglass_02" }, { "Ramas", "Ability_Stealth" }, { "Talentos", "Ability_Rogue_Eviscerate" },
  { "Cómo pelear", "Ability_DualWield" }, { "Errores", "Ability_Creature_Cursed_02" }, { "Equipo", "INV_Chest_Leather_09" },
  { "Prioridad", "INV_Misc_Gem_Pearl_04" }, { "Paso ", "Ability_Tracking" }, { "Resumen del plan", "INV_Misc_Note_01" }, { "Tu plan", "INV_Misc_Map_01" }, { "Consumibles", "INV_Potion_54" }, { "Misiones", "INV_Misc_Note_06" },
  { "Sobrevivir", "Ability_Vanish" }, { "Habilidades", "INV_Misc_Book_11" }, { "Qué profesiones", "Trade_Leatherworking" },
  { "Sistemas", "INV_Misc_Gear_01" }, { "Cosas que", "INV_Misc_QuestionMark" }, { "Reino", "Ability_Warrior_Challange" },
}
local DIVIDER = "|TInterface\\Buttons\\WHITE8x8:1:260:0:0:8:8:0:8:0:8:90:90:100|t"
local function iconFor(text)
  for _, pair in ipairs(SECTION_ICONS) do
    if text:sub(1, #pair[1]) == pair[1] then return "|TInterface\\Icons\\" .. pair[2] .. ":16:16:0:0:64:64:5:59:5:59|t " end
  end
  return ""
end
-- Sections fold: clicking a section title hides its lines (remembered in GuiaForeverDB.folded).
local foldKeys, foldDefaults, skipping = {}, {}, false
local FOLD_OPEN = "|TInterface\\Buttons\\UI-MinusButton-Up:12:12|t"
local FOLD_CLOSED = "|TInterface\\Buttons\\UI-PlusButton-Up:12:12|t"
-- Builders write into "blocks": one card per section, holding text lines and progress bars.
local blocks, curBlock = {}, nil
local function newBlock(title, key, color) curBlock = { title = title, key = key, color = color, items = {} }; blocks[#blocks + 1] = curBlock end
local function raw(text)
  if not curBlock then newBlock(nil) end
  curBlock.items[#curBlock.items + 1] = { kind = "text", text = text or "" }
end
local function L(text) if not skipping then raw(text) end end
-- Progress bar line: P("Lobos 5/8", 5, 8, done)
local function P(label, have, need, done)
  if skipping then return end
  if not curBlock then newBlock(nil) end
  curBlock.items[#curBlock.items + 1] = { kind = "bar", text = label, have = have, need = need, done = done }
end
-- A section remembers its fold by its title without colors, marks or the "(...)" tail, so a quest keeps it when its
-- priority color changes.
local function sectionKey(text)
  return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^[!%s]+", ""):gsub("%s*%(.*$", ""))
end
local function isFolded(key)
  local v = DB and DB.folded and DB.folded[key]
  if v == nil then v = foldDefaults[key] or false end
  return v
end
local function H(text, closedByDefault, color)
  local key = sectionKey(text)
  if closedByDefault then foldDefaults[key] = true end
  local folded = isFolded(key)
  foldKeys[#foldKeys + 1] = key
  newBlock("|Hguiaf:fold:" .. #foldKeys .. "|h" .. (folded and FOLD_CLOSED or FOLD_OPEN) .. " " .. iconFor(text) .. text .. "|h", key, color)
  curBlock.folded = folded
  skipping = folded
end
-- Close the current card: what follows goes into a plain block without a title.
local function endBlock() curBlock = nil; skipping = false; newBlock(nil) end
-- Sub-heading inside a section (follows the parent's fold).
local function H2(text) L(""); L(C.gold .. text .. C.r) end
local function B(text) L("  |cff6b7280•|r " .. text) end
local function each(list, fn) for _, v in ipairs(list or {}) do fn(v) end end

local readyQuestsSummary, nearestTurnIn, goalPlan -- defined after the quest helpers

local function specKey(classData)
  local key = DB.spec and DB.spec[select(2, UnitClass("player"))]
  if key and classData.specs and classData.specs[key] then return key end
  return classData.defaultSpec
end

local function upcomingClassMilestones(classData, level, span)
  local rows = {}
  for _, m in ipairs(classData.milestones or {}) do
    if m.level > level and m.level <= level + span then rows[#rows + 1] = m end
  end
  return rows
end

-- ---------------------------------------------------------------- session stats
-- Leveling stats computed from XP/money events only (no combat log).
local S = { start = nil, xp = 0, questXP = 0, kills = 0, killXP = 0, money = 0, restedUsed = 0, deaths = 0, recent = {} }
local lastXP, lastMax, lastMoney, lastRested, levelMark

local function charKey() return (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?") end

local function charDB()
  DB.chars = DB.chars or {}
  local k = charKey()
  DB.chars[k] = DB.chars[k] or { levelActive = 0, levels = {} }
  return DB.chars[k]
end

-- Forever hides some values from addons in combat ("secret values"): read numbers through this
-- and retry after combat when they are hidden.
local function plain(v)
  if issecretvalue and issecretvalue(v) then return nil end
  return tonumber(v)
end

local function sessionStart()
  S.start = GetTime()
  lastXP, lastMax = plain(UnitXP("player")) or 0, plain(UnitXPMax("player")) or 1
  lastMoney = GetMoney and GetMoney() or 0
  lastRested = (GetXPExhaustion and GetXPExhaustion()) or 0
  levelMark = GetTime()
end

local function onXPChanged()
  if not S.start then return end
  local xp, max = plain(UnitXP("player")), plain(UnitXPMax("player"))
  if not (xp and max) then
    -- Hidden right now (combat): try again when the fight ends.
    S.pendingXP = true
    return
  end
  S.pendingXP = false
  local gained = xp - lastXP
  if gained < 0 then gained = (lastMax - lastXP) + xp end -- leveled up in between
  if gained > 0 then
    S.xp = S.xp + gained
    S.recent[#S.recent + 1] = { t = GetTime(), xp = gained }
  end
  local rested = plain(GetXPExhaustion and GetXPExhaustion()) or 0
  if rested < lastRested then S.restedUsed = S.restedUsed + (lastRested - rested) end
  lastXP, lastMax, lastRested = xp, max, rested
end

local function onLevelUp(level)
  if not levelMark then return end
  local c = charDB()
  local secs = c.levelActive + (GetTime() - levelMark)
  c.levels[(level or 2) - 1] = math.floor(secs)
  c.levelActive, levelMark = 0, GetTime()
end

local function onLogout()
  if not levelMark then return end
  local c = charDB()
  c.levelActive = c.levelActive + (GetTime() - levelMark)
  levelMark = GetTime()
end

local function firstNumber(msg)
  if issecretvalue and issecretvalue(msg) then return nil end
  if type(msg) ~= "string" then return nil end
  local n = msg:gsub("[%.,](%d%d%d)", "%1"):match("(%d+)")
  return tonumber(n)
end

local function stats()
  if not S.start then return end
  local now = GetTime()
  local elapsed = math.max(now - S.start, 1)
  local r = { elapsed = elapsed, xp = S.xp, perHour = S.xp / elapsed * 3600 }
  local win, sum = 600, 0
  for i = #S.recent, 1, -1 do
    local e = S.recent[i]
    if now - e.t > win then break end
    sum = sum + e.xp
  end
  r.recentPerHour = (elapsed >= 120) and (sum / math.min(elapsed, win) * 3600) or nil
  local rate = r.recentPerHour or r.perHour
  local left = (plain(UnitXPMax("player")) or lastMax or 1) - (plain(UnitXP("player")) or lastXP or 0)
  if rate > 0 and S.xp > 0 then r.toLevel = left / rate * 3600 end
  if S.kills > 0 and S.killXP > 0 then
    r.avgKill = S.killXP / S.kills
    r.killsToLevel = math.ceil(left / r.avgKill)
  end
  r.questXP, r.killXP, r.kills = S.questXP, S.killXP, S.kills
  r.money = (GetMoney and GetMoney() or 0) - (lastMoney or 0)
  r.moneyPerHour = r.money / elapsed * 3600
  r.restedUsed = S.restedUsed
  return r
end

local function fmtTime(sec)
  sec = math.floor(sec or 0)
  if sec >= 3600 then return string.format("%dh %02dm", math.floor(sec / 3600), math.floor((sec % 3600) / 60)) end
  return string.format("%d min", math.max(1, math.floor(sec / 60)))
end
local function fmtNum(n)
  n = math.floor(n or 0)
  if n >= 10000 then return string.format("%.1fk", n / 1000) end
  return tostring(n)
end
local function fmtMoney(c)
  local neg = c < 0; c = math.abs(math.floor(c))
  local g, sv, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  local t = (g > 0 and (g .. "o ") or "") .. ((g > 0 or sv > 0) and (sv .. "p ") or "") .. cp .. "c"
  return (neg and "-" or "") .. t
end

local function headerStats()
  local r = stats()
  if not r or r.xp <= 0 then return nil end
  local t = fmtNum(r.recentPerHour or r.perHour) .. " XP/h"
  if r.toLevel then t = t .. "  ·  nivel " .. ((UnitLevel("player") or 1) + 1) .. " en " .. fmtTime(r.toLevel) end
  return t
end

local function buildSession()
  local r = stats()
  if not r or r.xp <= 0 then B(C.grey .. "Matá unos bichos o entregá una misión para ver tu ritmo." .. C.r); return end
  local lvl = UnitLevel("player") or 1
  B(C.grey .. "Sesión de " .. fmtTime(r.elapsed) .. C.r)
  B(C.gold .. fmtNum(r.recentPerHour or r.perHour) .. " XP/h" .. C.r .. (r.recentPerHour and C.grey .. " (últimos 10 min; sesión: " .. fmtNum(r.perHour) .. ")" .. C.r or ""))
  if r.toLevel then B("Nivel " .. (lvl + 1) .. " en " .. C.gold .. fmtTime(r.toLevel) .. C.r .. " a este ritmo") end
  if r.killsToLevel then B("Faltan ~" .. C.gold .. r.killsToLevel .. C.r .. " bichos (" .. math.floor(r.avgKill) .. " XP por muerte)") end
  local other = math.max(r.xp - r.questXP - r.killXP, 0)
  if r.xp > 0 then
    local pq, pk = math.floor(r.questXP / r.xp * 100 + 0.5), math.floor(r.killXP / r.xp * 100 + 0.5)
    B("XP de misiones " .. pq .. "% · de bichos " .. pk .. "%" .. (other > 0 and (" · otra " .. (100 - pq - pk) .. "%") or "") .. C.grey .. "  (" .. r.kills .. " muertes)" .. C.r)
    if r.kills >= 10 and pk > 70 then B(C.grey .. "Casi todo viene de matar: entregá misiones para no estancarte." .. C.r) end
  end
  if r.restedUsed > 0 then B(C.blue .. "El descanso te dio " .. fmtNum(r.restedUsed) .. " XP extra." .. C.r) end
  if r.money ~= 0 then
    B("Oro: " .. fmtMoney(r.money) .. C.grey .. " (" .. fmtMoney(r.moneyPerHour) .. "/h)" .. C.r)
  end
  if lvl < 40 and GetMoney then
    local missing = 1000000 - GetMoney()
    if missing > 0 then B(C.grey .. "Para la montura del 40 te faltan " .. fmtMoney(missing) .. "." .. C.r) end
  end
  local c = DB.chars and DB.chars[charKey()]
  if c and c.levels then
    local rows = {}
    for l = lvl - 1, math.max(1, lvl - 4), -1 do
      if c.levels[l] then rows[#rows + 1] = l .. "->" .. (l + 1) .. ": " .. fmtTime(c.levels[l]) end
    end
    if #rows > 0 then B(C.grey .. "Tiempo por nivel: " .. table.concat(rows, " · ") .. C.r) end
  end
end

-- ---------------------------------------------------------------- level-up checklist
local function freeBagSlots()
  local get = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
  if not get then return end
  local free = 0
  for bag = 0, 4 do
    local n, bagType = try(get, bag)
    if n and (bagType == nil or bagType == 0) then free = free + n end
  end
  return free
end

local function lowestDurability()
  if not GetInventoryItemDurability then return end
  local low
  for slot = 1, 18 do
    local cur, max = try(GetInventoryItemDurability, slot)
    if cur and max and max > 0 then
      local pct = cur / max
      if not low or pct < low then low = pct end
    end
  end
  return low
end

-- Forever has no UnitCharacterPoints/GetUnspentTalentPoints: estimate from points spent per tree
-- (first point at level 10). The "Talented" Legacy perk gives points earlier, so this can under-count.
local function unspentTalents()
  local pts = UnitCharacterPoints and try(UnitCharacterPoints, "player")
  if not pts and GetUnspentTalentPoints then pts = try(GetUnspentTalentPoints) end
  if pts then return tonumber(pts) end
  if type(GetTalentTabInfo) ~= "function" then return nil end
  local spent, any = 0, false
  for i = 1, 3 do
    local ok, a, b, c, d, e = pcall(GetTalentTabInfo, i)
    if ok then
      -- classic order: name, icon, pointsSpent; modern: id, name, description, icon, pointsSpent
      local n = (type(a) == "string" and tonumber(c)) or tonumber(e)
      if n then spent, any = spent + n, true end
    end
  end
  if not any then return nil end
  return math.max(0, (UnitLevel("player") or 1) - 9 - spent)
end

local function checkOn(key) return not (DB.check and DB.check[key] == false) end

local function buildChecklist(s)
  local items = {}
  local pts = checkOn("talents") and unspentTalents()
  if pts and pts > 0 then items[#items + 1] = C.gold .. "Tenés " .. pts .. " punto(s) de talento sin gastar (tecla N)." .. C.r end

  local cd = G.classes[s.class]
  if cd and cd.milestones and checkOn("trainer") then
    local trained = charDB().trainedLevel
    local from = trained and (trained + 1) or (s.level - 1)
    local news = {}
    for _, m in ipairs(cd.milestones) do
      if m.level >= from and m.level <= s.level then news[#news + 1] = "Nv " .. m.level .. ": " .. m.text end
    end
    if #news > 0 then
      items[#items + 1] = C.gold .. "Habilidades nuevas en tu entrenador." .. C.r .. C.grey .. " " .. table.concat(news, " / ", 1, math.min(#news, 2)) .. C.r
    end
  end

  local free = checkOn("bags") and freeBagSlots()
  if free and free <= 2 then items[#items + 1] = C.red .. "Bolsas casi llenas (" .. free .. " libres): vendé los grises o te perdés el botín." .. C.r end

  local dur = checkOn("durability") and lowestDurability()
  if dur and dur < 0.25 then
    items[#items + 1] = (dur < 0.1 and C.red or C.orange) .. "Equipo al " .. math.floor(dur * 100) .. "%: repará en un herrero o vendedor de armaduras." .. C.r
  end

  for _, p in ipairs(G.professions) do
    local sk = s.skills[p.name] or (p.alias and s.skills[p.alias])
    if checkOn("profs") and sk and sk.max >= 75 and sk.max < 300 and sk.rank >= sk.max and p.nextRank then
      items[#items + 1] = C.orange .. p.label .. " al tope (" .. sk.rank .. "/" .. sk.max .. "): " .. p.nextRank(sk.max) .. "." .. C.r
    end
  end

  if checkOn("lockpick") and s.class == "ROGUE" and s.level >= 16 and s.level <= 24 then
    local lp = s.skills["Ganzúa"] or s.skills["Forzar cerraduras"] or s.skills["Lockpicking"]
    if lp and lp.rank < 80 then items[#items + 1] = "Ganzúa " .. lp.rank .. "/80: la misión de venenos del 20 la pide. Abrí cofres y cajas." end
  end

  return items
end

local tipShown -- when the current tip was picked: one tip per minute, not one per redraw
local function buildNow()
  local s = playerState()
  local classData = G.classes[s.class]
  local zd = zoneData(s)
  -- 0) Context cards that matter most right now (e.g. the dungeon you are in).
  for _, fn in ipairs(G.topSections or {}) do local ok, err = pcall(fn, s); if not ok then B(C.red .. tostring(err) .. C.r) end end

  -- 1) What to do right now (max 3 lines).
  local todo = {}
  local ready = readyQuestsSummary and readyQuestsSummary()
  if ready then todo[#todo + 1] = ready end
  local near = ready and nearestTurnIn and nearestTurnIn(s)
  if near then todo[#todo + 1] = near end
  for _, item in ipairs(buildChecklist(s)) do todo[#todo + 1] = item end
  H("Para hacer ya")
  if #todo == 0 then B(C.green .. "Nada pendiente: a jugar." .. C.r) end
  for i = 1, math.min(#todo, 3) do B(todo[i]) end
  if #todo > 3 then B(C.grey .. "y " .. (#todo - 3) .. " cosa(s) más." .. C.r) end

  -- 2) Your pace.
  H("Tu ritmo")
  if s.rested > 0 then
    B(C.blue .. "Descanso: " .. s.rested .. " XP extra (doble XP por muerte, no por misión)." .. C.r)
  end
  buildSession()
  if goalPlan then local ok, err = pcall(goalPlan, s); if not ok then B(C.red .. tostring(err) .. C.r) end end

  -- 3) What is around you (PvP module and others).
  for _, fn in ipairs(G.nowSections or {}) do local ok, err = pcall(fn, s); if not ok then B(C.red .. tostring(err) .. C.r) end end

  -- Zone fit
  H("Tu zona")
  if zd then
    local status
    if s.level < zd.min then status = C.red .. "Peligrosa para tu nivel (" .. zd.min .. "-" .. zd.max .. ")." .. C.r
    elseif s.level > zd.max then status = C.orange .. "Ya te quedó chica (" .. zd.min .. "-" .. zd.max .. "): conviene moverte." .. C.r
    else status = C.green .. "Buena para tu nivel (" .. zd.min .. "-" .. zd.max .. ")." .. C.r end
    B(zd.label .. ": " .. status)
    each(zd.tips, B)
  else
    B(C.grey .. "Sin datos de esta zona todavía." .. C.r)
  end
  local nextZones = {}
  for _, d in ipairs(G.zones) do
    if factionOk(d, s.faction) and not d.city and s.level >= d.min - 1 and s.level <= d.max - 2 and d ~= zd then
      nextZones[#nextZones + 1] = d.label .. " (" .. d.min .. "-" .. d.max .. ")"
    end
  end
  if #nextZones > 0 then B("Otras zonas para vos: " .. table.concat(nextZones, ", ", 1, math.min(#nextZones, 5))) end

  -- Dungeons now
  H("Mazmorras para tu nivel")
  local any = false
  for _, d in ipairs(G.dungeons) do
    if factionOk(d, s.faction) and s.level >= d.min - 1 and s.level <= d.max then
      any = true
      B(C.gold .. d.name .. C.r .. " (" .. d.min .. "-" .. d.max .. ") — " .. d.where)
      if d.howto then L("     " .. C.grey .. d.howto .. C.r) end
    end
  end
  if not any then
    for _, d in ipairs(G.dungeons) do
      if factionOk(d, s.faction) and d.min > s.level then
        B("La próxima: " .. C.gold .. d.name .. C.r .. " desde nivel " .. d.min .. " (" .. d.where .. ")"); break
      end
    end
  end

  -- Class milestones coming
  if classData then
    H("Próximo en tu clase")
    local rows = upcomingClassMilestones(classData, s.level, 6)
    if #rows == 0 then B(C.grey .. "Nada nuevo en los próximos niveles." .. C.r) end
    for _, m in ipairs(rows) do B(C.gold .. "Nv " .. m.level .. ":" .. C.r .. " " .. m.text) end
    local spec = specKey(classData)
    local sd = classData.specs and classData.specs[spec]
    if sd and sd.talents then
      local nextT = {}
      for _, t in ipairs(sd.talents) do if t.level and t.level <= s.level + 5 and t.level >= s.level - 4 then nextT[#nextT + 1] = t.name .. " (" .. t.level .. ")" end end
      if #nextT > 0 then B("Talentos " .. sd.label .. ": " .. table.concat(nextT, ", ")) end
    end
  end

  -- General milestones
  local gm = {}
  for _, m in ipairs(G.milestones) do if m.level > s.level and m.level <= s.level + 8 then gm[#gm + 1] = m end end
  if #gm > 0 then
    H("Se viene", true)
    for _, m in ipairs(gm) do B(C.gold .. "Nv " .. m.level .. ":" .. C.r .. " " .. m.text) end
  end

  -- One rotating tip for the level band
  local pool = {}
  for _, t in ipairs(G.tips) do if s.level >= (t.min or 1) and s.level <= (t.max or 60) then pool[#pool + 1] = t.text end end
  if #pool > 0 then
    H("Consejo")
    if not tipShown or GetTime() - tipShown > 60 then
      tipShown = GetTime()
      DB.tipIndex = ((DB.tipIndex or 0) % #pool) + 1
    end
    B(pool[(DB.tipIndex - 1) % #pool + 1])
  end
end

local function buildClass()
  local s = playerState()
  local cd = G.classes[s.class]
  if not cd then L("Sin datos para tu clase todavía."); return end
  L(C.gold .. cd.label .. C.r .. "  —  " .. (cd.summary or ""))
  local spec = specKey(cd)
  if cd.specs then
    H("Ramas (clic en el botón de abajo para cambiar)")
    for _, key in ipairs(cd.specOrder or {}) do
      local sd = cd.specs[key]
      B((key == spec and C.green .. "> " or "") .. sd.label .. (key == spec and C.r or "") .. ": " .. sd.pitch)
    end
    -- Compare specs per goal when the data has ratings.
    local rated = false
    for _, key in ipairs(cd.specOrder or {}) do if cd.specs[key].rating then rated = true end end
    if rated then
      H("Comparar ramas por objetivo")
      local function stars(n)
        n = n or 0
        local on = "|TInterface\\Buttons\\WHITE8x8:8:8:0:0:8:8:0:8:0:8:251:191:36|t"
        local off = "|TInterface\\Buttons\\WHITE8x8:8:8:0:0:8:8:0:8:0:8:70:70:80|t"
        return string.rep(on, n) .. string.rep(off, 5 - n)
      end
      local goals = { { "leveling", "Subir de nivel" }, { "pve60", "Daño/rol al 60" }, { "pvp", "PvP" } }
      for _, g in ipairs(goals) do
        local best, bestN = {}, 0
        for _, key in ipairs(cd.specOrder or {}) do
          local r = cd.specs[key].rating and cd.specs[key].rating[g[1]] or 0
          if r > bestN then best, bestN = { cd.specs[key].label }, r elseif r == bestN and r > 0 then best[#best + 1] = cd.specs[key].label end
        end
        if bestN > 0 then B(C.gold .. g[2] .. ":" .. C.r .. " " .. table.concat(best, " o ")) end
      end
      for _, key in ipairs(cd.specOrder or {}) do
        local sd2 = cd.specs[key]
        if sd2.rating then
          L("")
          L("  " .. (key == spec and C.green or C.gold) .. sd2.label .. C.r .. (sd2.roles and (C.grey .. " (" .. sd2.roles .. ")" .. C.r) or "")
            .. (sd2.build60 and (C.grey .. "   build 60: " .. sd2.build60 .. C.r) or ""))
          if sd2.capstone then L("     " .. C.grey .. "Talento final: " .. sd2.capstone .. C.r) end
          L("     Subir " .. stars(sd2.rating.leveling) .. "   60 " .. stars(sd2.rating.pve60) .. "   PvP " .. stars(sd2.rating.pvp))
          if sd2.endgame then L("     " .. C.grey .. sd2.endgame .. (sd2.confidence and (" (confianza " .. sd2.confidence .. ")") or "") .. C.r) end
        end
      end
      if cd.ratingNote then L(""); L("  " .. C.grey .. cd.ratingNote .. C.r) end
    end
    local sd = cd.specs[spec]
    if sd then
      H("Talentos " .. sd.label .. " (en orden)")
      for _, t in ipairs(sd.talents or {}) do
        local mark = (t.level and t.level <= s.level) and C.green .. "+ " .. C.r or C.grey .. "· " .. C.r
        L("  " .. mark .. C.gold .. (t.level or "  ") .. C.r .. "  " .. t.name .. (t.note and (C.grey .. " — " .. t.note .. C.r) or ""))
      end
      H("Cómo pelear (" .. sd.label .. ")")
      each(sd.rotation, B)
    end
  end
  if cd.mistakes then H("Errores de novato"); each(cd.mistakes, B) end
  if cd.gear then
    H("Equipo e ítems clave")
    each(cd.gear, function(g)
      if not g.max or s.level <= g.max + 5 then B((g.level and (C.gold .. g.level .. C.r .. " ") or "") .. g.text) end
    end)
  end
  if cd.stats then H("Prioridad de estadísticas"); B(cd.stats) end
  if cd.consumables then H("Consumibles"); each(cd.consumables, B) end
  if cd.quests then H("Misiones de clase"); each(cd.quests, B) end
  if cd.pvp then H("Sobrevivir en reino JcJ"); each(cd.pvp, B) end
  if cd.milestones then
    H("Habilidades por nivel")
    for _, m in ipairs(cd.milestones) do
      local col = m.level <= s.level and C.grey or ""
      L("  " .. col .. C.gold .. m.level .. C.r .. col .. "  " .. m.text .. (col ~= "" and C.r or ""))
    end
  end
end

local function buildDungeons()
  local s = playerState()
  L(C.grey .. "Verde = tu nivel. Las misiones de mazmorra dan casi toda la XP: agarralas antes de entrar." .. C.r)
  local fdj = _G.ForeverDungeonJournal_NS
  for _, d in ipairs(G.dungeons) do
    if factionOk(d, s.faction) then
      local fits = s.level >= d.min - 1 and s.level <= d.max
      local col = fits and C.green or (s.level > d.max and C.grey or "")
      L("")
      L(col .. d.name .. "  (" .. d.min .. "-" .. d.max .. ")" .. (col ~= "" and C.r or "") .. (d.new and (C.orange .. "  NUEVA" .. C.r) or ""))
      L("  " .. C.grey .. d.where .. C.r)
      if fits or (d.min > s.level and d.min <= s.level + 8) then
        if d.howto then B(d.howto) end
        each(d.tips, B)
        local fd = fdj and fdj.DB and fdj.DB[d.key or d.name]
        if fd and fd.quests then
          for _, q in ipairs(fd.quests) do
            if factionOk(q, s.faction) then
              B(C.gold .. (q.name or "?") .. C.r .. (q.level and (" (" .. q.level .. ")") or "") .. (q.pickup and (C.grey .. " — " .. q.pickup .. C.r) or ""))
            end
          end
        end
      end
    end
  end
  L(""); L(C.grey .. "Detalle de jefes y botín: /dj (DungeonJournal)." .. C.r)
end

local function buildProfessions()
  local s = playerState()
  local known = 0
  for _, p in ipairs(G.professions) do
    local sk = s.skills[p.name] or (p.alias and s.skills[p.alias])
    if sk then
      known = known + 1
      L(""); L(C.gold .. p.label .. C.r .. "  " .. sk.rank .. "/" .. sk.max)
      if sk.rank >= sk.max and sk.max > 0 and sk.max < 300 then
        B(C.orange .. "¡Tope alcanzado! Entrená el siguiente rango (" .. (p.nextRank and p.nextRank(sk.max) or "en el entrenador") .. ")." .. C.r)
      end
      for _, b in ipairs(p.brackets or {}) do
        if sk.rank >= b.from and sk.rank < b.to then
          B(C.blue .. b.from .. "-" .. b.to .. ":" .. C.r .. " " .. b.text)
        end
      end
      each(p.tips, B)
    end
  end
  if known == 0 then L(C.grey .. "No veo profesiones aprendidas." .. C.r) end
  H2("Qué profesiones conviene")
  local cd = G.classes[s.class]
  each(cd and cd.professions, B)
  each(G.professionGeneral, B)
end

local function buildTips()
  local s = playerState()
  for _, sec in ipairs(G.tipSections) do
    H2(sec.title)
    each(sec.items, function(t)
      if type(t) == "string" then B(t) elseif s.level >= (t.min or 1) and s.level <= (t.max or 60) then B(t.text) end
    end)
  end
  L(""); L(C.grey .. "Datos: " .. (G.meta and G.meta.updated or "?") .. ". Actualizá con el actualizador (ActualizarGuia) para tener lo último." .. C.r)
end

-- ---------------------------------------------------------------- quests tab
-- Quest ID -> known data from ForeverDungeonJournal (dungeon quests and their prerequisites).
local fdjIndex
local function fdjQuest(id)
  local fdj = _G.ForeverDungeonJournal_NS
  if not fdj or not id then return end
  if not fdjIndex then
    fdjIndex = {}
    for dname, d in pairs(fdj.DB or {}) do
      for _, q in ipairs(type(d) == "table" and d.quests or {}) do
        if q.id then fdjIndex[q.id] = { q = q, dungeon = dname } end
      end
    end
  end
  local e = fdjIndex[id] or {}
  return e.q, e.dungeon, fdj.QUEST_PREREQ_DETAILS and fdj.QUEST_PREREQ_DETAILS[id],
    fdj.QUEST_START_MAPS and fdj.QUEST_START_MAPS[id], fdj.QUEST_PREREQ_CHAINS and fdj.QUEST_PREREQ_CHAINS[id]
end

local function mapLabel(m)
  if not m or not m.x then return end
  local info = m.mapID and C_Map and C_Map.GetMapInfo and try(C_Map.GetMapInfo, m.mapID)
  local zone = info and info.name or ""
  return string.format("%s %s(%.1f, %.1f)", m.label or m.targetName or "", zone ~= "" and (zone .. " ") or "", m.x * 100, m.y * 100)
end

local function hexColor(c) return string.format("|cff%02x%02x%02x", math.floor((c.r or 1) * 255), math.floor((c.g or 1) * 255), math.floor((c.b or 1) * 255)) end

-- The quest log is read once per frame: a render asks for it 3-4 times (route, turn-ins, tabs). Each caller gets
-- its own copy of the list, since some sort it.
local entriesAt, entriesCache
local function readQuestLog()
  local list, header = {}, nil
  if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
    for i = 1, (try(C_QuestLog.GetNumQuestLogEntries) or 0) do
      local q = try(C_QuestLog.GetInfo, i)
      if q then
        if q.isHeader then header = q.title
        elseif not q.isHidden then
          local done = try(C_QuestLog.IsComplete, q.questID)
          list[#list + 1] = { index = i, id = q.questID, title = q.title, level = q.level, group = tonumber(q.suggestedGroup),
            header = header, complete = done and true or false, failed = q.isFailed or (try(C_QuestLog.IsFailed, q.questID) and true) }
        end
      end
    end
  elseif GetNumQuestLogEntries then
    for i = 1, (GetNumQuestLogEntries() or 0) do
      local title, level, group, isHeader, _, isComplete, _, questID = try(GetQuestLogTitle, i)
      if title then
        if isHeader then header = title
        else
          list[#list + 1] = { index = i, id = questID, title = title, level = level, group = tonumber(group),
            header = header, complete = isComplete == 1, failed = isComplete == -1 }
        end
      end
    end
  end
  return list
end

local function questEntries()
  local now = GetTime()
  if entriesAt ~= now or not entriesCache then entriesAt, entriesCache = now, readQuestLog() end
  local copy = {}
  for i, e in ipairs(entriesCache) do copy[i] = e end
  return copy
end

local function questObjectives(e)
  local rows = {}
  local objs = e.id and C_QuestLog and C_QuestLog.GetQuestObjectives and try(C_QuestLog.GetQuestObjectives, e.id)
  if type(objs) == "table" and #objs > 0 then
    for _, o in ipairs(objs) do
      local have, need = o.numFulfilled, o.numRequired
      if issecretvalue and (issecretvalue(have) or issecretvalue(need)) then have, need = nil, nil end
      have, need = tonumber(have), tonumber(need)
      if not need and type(o.text) == "string" then
        local a, b = o.text:match("(%d+)%s*/%s*(%d+)")
        have, need = tonumber(a), tonumber(b)
      end
      rows[#rows + 1] = { text = o.text or "", done = o.finished, type = o.type, have = have, need = need }
    end
  elseif GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
    for j = 1, (try(GetNumQuestLeaderBoards, e.index) or 0) do
      local t, kind, done = try(GetQuestLogLeaderBoard, j, e.index)
      if t then
        local a, b = t:match("(%d+)%s*/%s*(%d+)")
        rows[#rows + 1] = { text = t, done = done and done ~= 0, type = kind, have = tonumber(a), need = tonumber(b) }
      end
    end
  end
  return rows
end

-- The objectives paragraph and the XP reward need the entry selected; cache both so each
-- quest is selected once (selection can fire QUEST_LOG_UPDATE, which re-renders).
local questTextCache = {}

-- Rewards that make a quest important: a spell it teaches, a bag it gives (needs the entry selected).
local function selectedRewards()
  local spell
  if GetQuestLogRewardSpell then
    local _, name = try(GetQuestLogRewardSpell)
    if type(name) == "string" and name ~= "" and not (issecretvalue and issecretvalue(name)) then spell = name end
  end
  local bag
  local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  for _, kind in ipairs({ "reward", "choice" }) do
    local n = (kind == "reward" and GetNumQuestLogRewards and try(GetNumQuestLogRewards))
      or (kind == "choice" and GetNumQuestLogChoices and try(GetNumQuestLogChoices)) or 0
    for i = 1, tonumber(n) or 0 do
      local link = GetQuestLogItemLink and try(GetQuestLogItemLink, kind, i)
      if type(link) == "string" and not (issecretvalue and issecretvalue(link)) and instant then
        local _, _, _, equipLoc, _, classID = try(instant, link)
        if classID == 1 or equipLoc == "INVTYPE_BAG" then bag = link end
      end
    end
  end
  return spell, bag
end

local function questStatic(e)
  local key = e.id or e.title
  local c = questTextCache[key]
  -- Reward XP depends on your level: read it again after a level-up.
  if c and c.level == UnitLevel("player") then return c.summary, c.xp, c.desc end
  local summary, xp, desc, spell, bag
  local direct = e.id and GetQuestLogRewardXP and try(GetQuestLogRewardXP, e.id)
  if GetQuestLogQuestText then
    if C_QuestLog and C_QuestLog.SetSelectedQuest and e.id then
      local prev = try(C_QuestLog.GetSelectedQuest)
      try(C_QuestLog.SetSelectedQuest, e.id)
      desc, summary = try(GetQuestLogQuestText)
      xp = direct or (GetQuestLogRewardXP and try(GetQuestLogRewardXP))
      spell, bag = selectedRewards()
      if prev then try(C_QuestLog.SetSelectedQuest, prev) end
    elseif SelectQuestLogEntry then
      local prev = GetQuestLogSelection and try(GetQuestLogSelection)
      try(SelectQuestLogEntry, e.index)
      desc, summary = try(GetQuestLogQuestText)
      xp = direct or (GetQuestLogRewardXP and try(GetQuestLogRewardXP))
      spell, bag = selectedRewards()
      if prev and prev > 0 then try(SelectQuestLogEntry, prev) end
    end
  end
  if issecretvalue and (issecretvalue(desc) or issecretvalue(summary)) then desc, summary = nil, nil end
  questTextCache[key] = { summary = summary, xp = tonumber(xp), desc = desc, spell = spell, bag = bag, level = UnitLevel("player") }
  return summary, tonumber(xp), desc
end

-- Why a quest in your log matters beyond its XP, or nil: the curated list (DataImportant.lua),
-- a class quest (the log files it under your class name), or a spell/bag reward.
-- Second value: true for class quests (shown with a red "!!").
local function questImportance(e)
  local className = UnitClass("player")
  local isClass = className and e.header == className
  local entry = e.id and G.importantIndex and G.importantIndex[e.id]
  if entry then return entry.why, isClass or entry.class ~= nil end
  if isClass then return "Misión de clase", true end
  local c = questTextCache[e.id or e.title]
  if c and c.spell then return "Te enseña " .. c.spell end
  if c and c.bag then return "Te da una bolsa: " .. c.bag end
end

-- Direction from the player to the quest's next objective, when the client exposes it.
local COMPASS = { "este", "noreste", "norte", "noroeste", "oeste", "suroeste", "sur", "sureste" }
local function questWaypoint(e, s)
  if not (e.id and s.mapID and C_Map and C_Map.GetPlayerMapPosition) then return end
  local qx, qy
  if C_QuestLog and C_QuestLog.GetNextWaypoint then
    local m, x, y = try(C_QuestLog.GetNextWaypoint, e.id)
    if m == s.mapID then qx, qy = x, y end
  end
  if not qx and C_QuestLog and C_QuestLog.GetQuestsOnMap then
    for _, q in ipairs(try(C_QuestLog.GetQuestsOnMap, s.mapID) or {}) do
      if q.questID == e.id then qx, qy = q.x, q.y end
    end
  end
  if not qx then return end
  local pos = try(C_Map.GetPlayerMapPosition, s.mapID, "player")
  if not pos then return end
  local px, py = pos.x, pos.y
  if pos.GetXY then px, py = pos:GetXY() end
  if not px then return end
  local dx, dy = qx - px, py - qy -- map y grows southward
  local dist = math.sqrt(dx * dx + dy * dy)
  local where = string.format("(%.0f, %.0f)", qx * 100, qy * 100)
  if dist < 0.03 then return "Estás encima del objetivo " .. where end
  local angle = math.deg(math.atan2 and math.atan2(dy, dx) or math.atan(dy, dx)) % 360
  local dir = COMPASS[(math.floor((angle + 22.5) / 45) % 8) + 1]
  local how = dist < 0.12 and "cerca" or (dist < 0.3 and "a media distancia" or "lejos")
  return "Objetivo al " .. dir .. ", " .. how .. " " .. where
end

-- Priority tiers: what to do first and what you can drop.
local TIERS = {
  { label = "ENTREGAR YA", rgb = { 0.29, 0.87, 0.5 }, short = "para entregar", color = "|cff4ade80", sq = "|TInterface\\Buttons\\WHITE8x8:9:9:0:0:8:8:0:8:0:8:74:222:128|t" },
  { label = "PRIORIDAD ALTA", rgb = { 0.98, 0.75, 0.14 }, short = "alta", color = "|cfffbbf24", sq = "|TInterface\\Buttons\\WHITE8x8:9:9:0:0:8:8:0:8:0:8:251:191:36|t" },
  { label = "PRIORIDAD MEDIA", rgb = { 0.49, 0.83, 0.99 }, short = "media", color = "|cff7dd3fc", sq = "|TInterface\\Buttons\\WHITE8x8:9:9:0:0:8:8:0:8:0:8:125:211:252|t" },
  { label = "CON GRUPO / MÁS ADELANTE", rgb = { 0.75, 0.52, 0.99 }, short = "para después", color = "|cffc084fc", sq = "|TInterface\\Buttons\\WHITE8x8:9:9:0:0:8:8:0:8:0:8:192:132:252|t" },
  { label = "PRESCINDIBLE", rgb = { 0.61, 0.64, 0.69 }, short = "prescindibles", color = "|cff9ca3af", sq = "|TInterface\\Buttons\\WHITE8x8:9:9:0:0:8:8:0:8:0:8:156:163:175|t" },
}

-- ---------------------------------------------------------------- party quests
-- Party members with Guía Forever broadcast their quest progress over addon messages;
-- without it we can still ask the client whether a member is on a quest.
local PREFIX = "GUIAF"
local partyData = {} -- name -> { [questID] = { d = done, n = total, c = complete } }

local function inGroup()
  if IsInGroup then return IsInGroup() end
  return (GetNumPartyMembers and GetNumPartyMembers() or 0) > 0
end

local function partyUnits()
  local units = {}
  for i = 1, 4 do
    local u = "party" .. i
    if UnitExists and UnitExists(u) then units[#units + 1] = u end
  end
  return units
end

-- Instance groups use INSTANCE_CHAT; raids are skipped (5-player feature).
local function groupChannel()
  if IsInRaid and IsInRaid() then return nil end
  if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
  if inGroup() then return "PARTY" end
end

local function sendAddon(msg)
  local f = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
  local channel = groupChannel()
  if not (f and channel) then return false end
  if C_ChatInfo and type(C_ChatInfo.InChatMessagingLockdown) == "function" and try(C_ChatInfo.InChatMessagingLockdown) then return false end
  return try(f, PREFIX, msg, channel) ~= false
end

local sendPending, lastPayload, lastSentAt = false, nil, 0
local function broadcastQuests(force)
  if sendPending or not inGroup() then return end
  sendPending = true
  C_Timer.After(3, function()
    sendPending = false
    if not inGroup() then return end
    local parts = {}
    for _, e in ipairs(questEntries()) do
      if e.id then
        -- Real progress: summed counts ("3/8"); objectives without a count weigh 1.
        local d, n = 0, 0
        for _, o in ipairs(questObjectives(e)) do
          if o.need and o.need > 0 then n = n + o.need; d = d + math.min(o.have or 0, o.need)
          else n = n + 1; if o.done then d = d + 1 end end
        end
        parts[#parts + 1] = e.id .. "," .. d .. "," .. n .. "," .. (e.complete and 1 or 0)
      end
    end
    local payload = table.concat(parts, ";")
    if not force and payload == lastPayload and GetTime() - lastSentAt < 60 then return end
    lastPayload, lastSentAt = payload, GetTime()
    local chunk, first = "", true
    local function flush()
      sendAddon((first and "S" or "C") .. chunk); first, chunk = false, ""
    end
    for _, p in ipairs(parts) do
      if #chunk + #p + 1 > 230 then flush() end
      chunk = chunk == "" and p or (chunk .. ";" .. p)
    end
    flush()
  end)
end

-- ---------------------------------------------------------------- party stats
-- Every member with the Guía sends a small status line ("P") every 30 s: level, XP, pace, bags,
-- durability, professions and today's session. Without the Guía we only see what the client shows.
local partyStats = {} -- name -> { level, xpPct, perHour, toLevel, rested, dur, bags, elapsed, xp, kills, deaths, money, profs = { [name] = rank }, at }
local PROF_NAMES = {}
for _, n in ipairs({ "Herrería", "Peletería", "Sastrería", "Ingeniería", "Encantamiento", "Alquimia", "Cocina", "Primeros auxilios",
  "Minería", "Pesca", "Herboristería", "Desuello", "Venenos", "Blacksmithing", "Leatherworking", "Tailoring", "Engineering",
  "Enchanting", "Alchemy", "Cooking", "First Aid", "Mining", "Fishing", "Herbalism", "Skinning", "Poisons" }) do PROF_NAMES[n] = true end

local function myProfList()
  local out = {}
  if GetNumSkillLines then
    for i = 1, GetNumSkillLines() do
      local name, isHeader, _, rank = try(GetSkillLineInfo, i)
      if name and not isHeader and PROF_NAMES[name] and tonumber(rank) then out[#out + 1] = name .. ":" .. rank end
    end
  end
  return table.concat(out, "/")
end

local function myStatus()
  local r = stats() or {}
  local xp, max = plain(UnitXP("player")), plain(UnitXPMax("player"))
  local rested = plain(GetXPExhaustion and GetXPExhaustion())
  local dur = lowestDurability()
  return {
    level = UnitLevel("player") or 0,
    xpPct = (xp and max and max > 0) and math.floor(xp / max * 100) or nil,
    perHour = r.recentPerHour or r.perHour, toLevel = r.toLevel,
    rested = (rested and max and max > 0) and math.floor(rested / max * 100) or 0,
    dur = dur and math.floor(dur * 100) or nil, bags = freeBagSlots(),
    elapsed = r.elapsed, xp = r.xp or 0, kills = r.kills or 0, deaths = S.deaths or 0, money = r.money or 0,
  }
end

local lastStatsAt = 0
local function sendStats(force)
  if not inGroup() or (not force and GetTime() - lastStatsAt < 25) then return end
  lastStatsAt = GetTime()
  local m = myStatus()
  local function n(v) return v and tostring(math.floor(v)) or "" end
  sendAddon("P" .. table.concat({ n(m.level), n(m.xpPct), n(m.perHour), n(m.toLevel), n(m.rested), n(m.dur), n(m.bags),
    n(m.elapsed), n(m.xp), n(m.kills), n(m.deaths), n(m.money), (myProfList():gsub(",", " ")) }, ","))
end

local function readStats(name, body)
  local f = {}
  for v in (body .. ","):gmatch("([^,]*),") do f[#f + 1] = v end
  local profs = {}
  for pn, rank in (f[13] or ""):gmatch("([^/:]+):(%d+)") do profs[pn] = tonumber(rank) end
  partyStats[name] = { level = tonumber(f[1]), xpPct = tonumber(f[2]), perHour = tonumber(f[3]), toLevel = tonumber(f[4]),
    rested = tonumber(f[5]), dur = tonumber(f[6]), bags = tonumber(f[7]), elapsed = tonumber(f[8]), xp = tonumber(f[9]) or 0,
    kills = tonumber(f[10]) or 0, deaths = tonumber(f[11]) or 0, money = tonumber(f[12]) or 0, profs = profs, at = GetTime() }
end

local function onAddonMessage(prefix, msg, _, sender)
  if prefix ~= PREFIX or not msg or not sender then return end
  local name = sender:gsub("%-.*$", "")
  if name == UnitName("player") then return end
  local kind, body = msg:sub(1, 1), msg:sub(2)
  if kind == "R" then lastPayload = nil; broadcastQuests(true); sendStats(true); return end
  if kind == "P" then readStats(name, body); return end
  if G.addonHandlers and G.addonHandlers[kind] then pcall(G.addonHandlers[kind], name, body); return end
  if kind == "S" then partyData[name] = {} end
  partyData[name] = partyData[name] or {}
  for id, d, n, c in body:gmatch("(%d+),(%d+),(%d+),(%d)") do
    partyData[name][tonumber(id)] = { d = tonumber(d), n = tonumber(n), c = c == "1" }
  end
end

local function unitOnQuest(unit, e)
  if C_QuestLog and C_QuestLog.IsUnitOnQuest and e.id then return try(C_QuestLog.IsUnitOnQuest, unit, e.id) end
  if IsUnitOnQuest then return try(IsUnitOnQuest, e.index, unit) == 1 end
end

-- Returns { with = {"Juan 3/8", ...}, without = {"Ana"}, count = n }
local function questMates(e)
  local r = { with = {}, without = {}, count = 0 }
  for _, u in ipairs(partyUnits()) do
    local name = UnitName(u)
    local pd = name and partyData[name]
    local has, label = false, nil
    if pd then
      local q = e.id and pd[e.id]
      if q then has, label = true, name .. (q.c and " LISTA" or (q.n > 0 and (" " .. q.d .. "/" .. q.n) or "")) end
    else
      has = unitOnQuest(u, e) and true or false
      label = name
    end
    if has then r.with[#r.with + 1] = label; r.count = r.count + 1
    elseif name then r.without[#r.without + 1] = name end
  end
  return r
end

local function questPlan(e, s, objectives, xp, dungeon)
  local diff = (e.level or s.level) - s.level
  local here = e.header and s.zone ~= "" and e.header == s.zone
  local done, total = 0, #objectives
  for _, o in ipairs(objectives) do if o.done then done = done + 1 end end
  local inGroup = (IsInGroup and IsInGroup()) or ((GetNumPartyMembers and GetNumPartyMembers() or 0) > 0)
  local tips, why = {}, nil
  local tier
  if e.complete then tier, why = 1, "Ya está: es XP gratis"
  elseif e.failed then tier, why = 5, "Fallada"
  elseif diff <= -6 then tier, why = 5, "Gris: casi no da XP"
  elseif xp and s.xpMax > 0 and xp < s.xpMax * 0.03 and not here then tier, why = 5, "Da muy poca XP (" .. xp .. ") y está en otra zona"
  elseif dungeon and not inGroup then tier, why = 4, "Es de mazmorra: guardala para cuando armes grupo"
  elseif e.group and e.group > 1 and not inGroup then tier, why = 4, "Élite: pedí ayuda o volvé con 1-2 niveles más"
  elseif diff >= 4 then tier, why = 4, "Está " .. diff .. " niveles arriba tuyo"
  elseif here then tier, why = 2, (total > 0 and done > 0) and "En tu zona y ya la empezaste" or "En tu zona y de tu nivel"
  else tier, why = 3, "En otra zona: hacela cuando pases por " .. (e.header or "ahí") end
  if tier == 3 and total > 0 and done * 2 >= total then tier, why = 2, "Ya hiciste más de la mitad" end
  if e.mates and e.mates.count > 0 and (tier == 3 or tier == 4) and diff < 4 then
    tier, why = 2, "La tienen tus compañeros: háganla juntos"
  end
  if xp and xp > 0 then why = why .. " · " .. xp .. " XP" end

  if not e.complete then
    if e.group and e.group > 1 and not dungeon and s.class == "ROGUE" then tips[#tips + 1] = "Élite: abrí con Gubia para pegarle primero, Patada a sus hechizos, Evasión apenas pegue fuerte; Sprint para huir." end
  end
  while #tips > 2 do table.remove(tips) end
  return tier, why, tips
end

-- ---------------------------------------------------------------- clickable actions
-- Links inside the text: |Hguiaf:go:<questID>|h[Ir]|h  and  |Hguiaf:share:<questID>|h[Compartir]|h
local waypoints = {} -- coordinates referenced by [Ir] links in walkthrough steps (rebuilt every render)
local function actionLink(kind, id, label, color)
  return (color or "|cff7dd3fc") .. "|Hguiaf:" .. kind .. ":" .. id .. "|h[ " .. label .. " ]|h|r"
end

local function msg(text) print(C.title .. "Guía Forever|r " .. text) end

local function goToQuest(id)
  local mapID, x, y
  if C_QuestLog and C_QuestLog.GetNextWaypoint then mapID, x, y = try(C_QuestLog.GetNextWaypoint, id) end
  if not (mapID and x) then
    local _, _, prereq, startMap = fdjQuest(id)
    local m = (prereq and prereq.map) or startMap
    if m and m.x then mapID, x, y = m.mapID, m.x, m.y end
  end
  if G.setWaypoint(mapID, x, y) then
    local info = C_Map.GetMapInfo and try(C_Map.GetMapInfo, mapID)
    msg(string.format("Marcador puesto: %s (%.1f, %.1f). Seguí la flecha.", info and info.name or "", x * 100, y * 100))
    return
  end
  if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
    try(C_SuperTrack.SetSuperTrackedQuestID, id)
    msg("Misión seguida: el juego te marca el objetivo si lo conoce.")
  else
    msg("No encontré la ubicación de esta misión.")
  end
end

local function shareQuest(id)
  if not (C_QuestLog and C_QuestLog.SetSelectedQuest and QuestLogPushQuest) then return end
  local prev = try(C_QuestLog.GetSelectedQuest)
  try(C_QuestLog.SetSelectedQuest, id)
  try(QuestLogPushQuest)
  if prev then try(C_QuestLog.SetSelectedQuest, prev) end
  msg("Misión compartida con el grupo.")
end

local function onLink(link)
  local kind, id = (link or ""):match("^guiaf:(%a+):(%d+)")
  id = tonumber(id)
  if not id then return end
  if kind == "fold" then
    local key = foldKeys[id]
    if key then DB.folded = DB.folded or {}; DB.folded[key] = not isFolded(key) end
    if G.core and G.core.renderNow then G.core.renderNow() end
    return
  end
  if kind == "sos" then if G.pvp and G.pvp.sos then G.pvp.sos() end; return end
  local handler = G.linkHandlers and G.linkHandlers[kind] -- links added by other files (Roadmap.lua: "ruta")
  if handler then handler(id); return end
  if kind == "text" then
    DB.questText = DB.questText or {}
    DB.questText[id] = not DB.questText[id] or nil
    if G.core and G.core.renderNow then G.core.renderNow() end
    return
  end
  if kind == "wp" then
    local w = waypoints[id]
    if w and G.setWaypoint(w[1], w[2], w[3]) then
      msg(string.format("Marcador puesto en %.1f, %.1f. Seguí la flecha.", w[2] * 100, w[3] * 100))
    end
    return
  end
  if kind == "go" then goToQuest(id) elseif kind == "share" then shareQuest(id)
  elseif kind == "shareall" then
    local ids = {}
    for _, e in ipairs(questEntries()) do
      if e.id and not e.complete and inGroup() then
        local m = questMates(e)
        local pushable = not (C_QuestLog and C_QuestLog.IsPushableQuest) or try(C_QuestLog.IsPushableQuest, e.id)
        if #m.without > 0 and pushable then ids[#ids + 1] = e.id end
      end
    end
    for i, qid in ipairs(ids) do C_Timer.After((i - 1) * 1.5, function() shareQuest(qid) end) end
    if #ids == 0 then msg("No hay misiones para compartir.") end
  end
end

-- ---------------------------------------------------------------- route plan
-- Orders the quests you have into a short walking plan for the zone you are in: nearby objectives are
-- grouped into one stop, stops are picked by XP per distance, and turn-ins are batched.
local function questPoint(e, mapID)
  if not (e.id and mapID) then return end
  if C_QuestLog and C_QuestLog.GetQuestsOnMap then
    for _, q in ipairs(try(C_QuestLog.GetQuestsOnMap, mapID) or {}) do
      if q.questID == e.id and q.x and not (issecretvalue and issecretvalue(q.x)) then return q.x, q.y end
    end
  end
  if C_QuestLog and C_QuestLog.GetNextWaypoint then
    local m, x, y = try(C_QuestLog.GetNextWaypoint, e.id)
    if m == mapID and x and not (issecretvalue and issecretvalue(x)) then return x, y end
  end
end

local function playerPoint(mapID)
  if not (mapID and C_Map and C_Map.GetPlayerMapPosition) then return end
  local pos = try(C_Map.GetPlayerMapPosition, mapID, "player")
  if not pos or (issecretvalue and issecretvalue(pos)) then return end
  local x, y = pos.x, pos.y
  if pos.GetXY then x, y = pos:GetXY() end
  if not x or (issecretvalue and (issecretvalue(x) or issecretvalue(y))) then return end
  return x, y
end

local function direction(fromX, fromY, toX, toY)
  local dx, dy = toX - fromX, fromY - toY
  local dist = math.sqrt(dx * dx + dy * dy)
  if dist < 0.03 then return "acá mismo", dist end
  local angle = math.deg(math.atan2 and math.atan2(dy, dx) or math.atan(dy, dx)) % 360
  local dir = COMPASS[(math.floor((angle + 22.5) / 45) % 8) + 1]
  return "al " .. dir .. ", " .. (dist < 0.12 and "cerca" or (dist < 0.3 and "a media distancia" or "lejos")), dist
end

local function buildRoute(list, s)
  if DB.routePlan == false then return end
  local mapID = s.mapID
  local px, py = playerPoint(mapID)
  if not px then
    H("Tu plan")
    B(C.grey .. "El juego no da tu posición acá (por ejemplo en mazmorras). Usá [Ir] en cada misión." .. C.r)
    return
  end
  -- 1) points for usable quests on this map
  local points, later, drop = {}, {}, {}
  for _, e in ipairs(list) do
    if e.tier == 5 then drop[#drop + 1] = e
    elseif e.tier == 4 and not e.complete then later[#later + 1] = e
    else
      local x, y = questPoint(e, mapID)
      if x then points[#points + 1] = { e = e, x = x, y = y, xp = e.xp or 0 }
      elseif not e.complete then later[#later + 1] = e end
    end
  end
  if #points == 0 then
    H("Tu plan")
    B(C.grey .. "Ninguna de tus misiones tiene objetivos en esta zona: mirá las de prioridad alta y tocá [Ir]." .. C.r)
  end
  -- 2) group points closer than ~6% of the map into one stop
  local stops = {}
  for _, pt in ipairs(points) do
    local joined
    for _, st in ipairs(stops) do
      local dx, dy = st.x - pt.x, st.y - pt.y
      if math.sqrt(dx * dx + dy * dy) < 0.06 then joined = st; break end
    end
    if joined then
      joined.items[#joined.items + 1] = pt
      joined.x = (joined.x * (#joined.items - 1) + pt.x) / #joined.items
      joined.y = (joined.y * (#joined.items - 1) + pt.y) / #joined.items
      joined.xp = joined.xp + pt.xp
    else
      stops[#stops + 1] = { x = pt.x, y = pt.y, xp = pt.xp, items = { pt } }
    end
  end
  -- 3) greedy route: best XP per distance from where you are; turn-ins get a small bonus
  local cx, cy, total, n = px, py, 0, 0
  local remaining = {}
  for _, st in ipairs(stops) do remaining[#remaining + 1] = st end
  while #remaining > 0 and n < 5 do
    local bestI, bestScore
    for i, st in ipairs(remaining) do
      local dx, dy = st.x - cx, st.y - cy
      local dist = math.sqrt(dx * dx + dy * dy)
      local ready = 0
      for _, it in ipairs(st.items) do if it.e.complete then ready = ready + 1 end end
      local score = (st.xp + 200 + ready * 300) / (dist + 0.05)
      if not bestScore or score > bestScore then bestI, bestScore = i, score end
    end
    local st = table.remove(remaining, bestI)
    n = n + 1
    local where = direction(cx, cy, st.x, st.y)
    local turnIn, doing = {}, {}
    for _, it in ipairs(st.items) do
      if it.e.complete then turnIn[#turnIn + 1] = it.e.title or "?"
      else
        local step
        for _, o in ipairs(it.e.objectives or {}) do if not o.done then step = o.text; break end end
        doing[#doing + 1] = (step or (it.e.title or "?")) .. C.grey .. " (" .. (it.e.title or "?") .. ")" .. C.r
      end
    end
    -- One card per stop, so the "small" window size shows just the next step.
    H("Paso " .. n .. ": " .. where, false, #doing == 0 and { 0.29, 0.87, 0.5 } or nil)
    L("  " .. actionLink("go", st.items[1].e.id or 0, "Ir") .. (st.xp > 0 and (C.grey .. "  +" .. fmtNum(st.xp) .. " XP" .. C.r) or ""))
    for _, d in ipairs(doing) do B(d) end
    if #turnIn > 0 then B(C.green .. "Entregá: " .. table.concat(turnIn, ", ") .. C.r) end
    total = total + st.xp
    cx, cy = st.x, st.y
  end
  if total > 0 or #later > 0 or #drop > 0 then H("Resumen del plan", true) end
  if total > 0 then
    local cur, max = plain(UnitXP("player")), plain(UnitXPMax("player"))
    local tail = ""
    if cur and max and max > 0 then
      tail = (cur + total >= max) and (C.gold .. " -> ¡subís de nivel!" .. C.r) or (C.grey .. " -> quedás al " .. math.floor((cur + total) / max * 100) .. "%" .. C.r)
    end
    B("Total del plan: +" .. fmtNum(total) .. " XP" .. tail)
  end
  if #later > 0 then
    local names = {}
    for i = 1, math.min(#later, 3) do names[#names + 1] = later[i].title or "?" end
    B(C.grey .. "Para después: " .. table.concat(names, ", ") .. (#later > 3 and (" y " .. (#later - 3) .. " más") or "") .. C.r)
  end
  if #drop > 0 then
    local names = {}
    for i = 1, math.min(#drop, 3) do names[#names + 1] = drop[i].title or "?" end
    B(C.grey .. "Podés abandonar: " .. table.concat(names, ", ") .. C.r)
  end
end

-- Hand-written walkthrough for confusing quests (also for completed ones: some turn in at an object far away).
local function questGuideBlock(e)
  local guide = G.questGuides and e.id and G.questGuides[e.id]
  if guide then
    B(C.gold .. "Cómo se hace" .. C.r .. (guide.source == "classic" and C.grey .. " (según el WoW clásico)" .. C.r or ""))
    local mapID = nil
    for _, z in ipairs(G.zones) do if z.label == guide.zone and z.mapID then mapID = z.mapID end end
    for i, st in ipairs(guide.steps or {}) do
      local link = ""
      if st.x and st.y and mapID then
        waypoints[#waypoints + 1] = { mapID, st.x / 100, st.y / 100 }
        link = "  " .. actionLink("wp", #waypoints, "Ir")
      end
      L("       " .. C.gold .. i .. "." .. C.r .. " " .. st.text .. link)
    end
    if guide.warning then B(C.orange .. guide.warning .. C.r) end
    if guide.skip then B(C.grey .. "¿Vale la pena? " .. guide.skip .. C.r) end
  end
end

local function buildQuests()
  waypoints = {}
  local s = playerState()
  local list = questEntries()
  if #list == 0 then L(C.grey .. "No tenés misiones aceptadas." .. C.r); return end

  for _, e in ipairs(list) do
    e.objectives = questObjectives(e)
    e.summary, e.xp, e.desc = questStatic(e)
    e.fdj, e.dungeon, e.prereq, e.startMap, e.chain = fdjQuest(e.id)
    if inGroup() then e.mates = questMates(e) end
    e.tier, e.why, e.tips = questPlan(e, s, e.objectives, e.xp, e.dungeon)
    e.important, e.classQuest = questImportance(e)
    -- Never suggest dropping an important quest.
    if e.important and e.tier >= 4 and not e.complete then e.tier = 3; e.why = "No la abandones aunque dé poca XP: lo que te da dura todo el juego." end
  end
  table.sort(list, function(a, b)
    if a.tier ~= b.tier then return a.tier < b.tier end
    if (a.header == s.zone) ~= (b.header == s.zone) then return a.header == s.zone end
    return a.index < b.index
  end)

  buildRoute(list, s)
  endBlock()

  -- One-line plan at the top.
  local counts = {}
  for _, e in ipairs(list) do counts[e.tier] = (counts[e.tier] or 0) + 1 end
  local parts = {}
  for i, t in ipairs(TIERS) do if counts[i] then parts[#parts + 1] = t.color .. counts[i] .. " " .. t.short .. C.r end end
  L(table.concat(parts, C.grey .. "  ·  " .. C.r))
  if counts[1] then L(C.green .. "Primero entregá las listas, después seguí con las de prioridad alta." .. C.r)
  elseif counts[2] then L(C.gold .. "Hacé primero las de prioridad alta: están en tu zona." .. C.r) end
  if counts[5] then L(C.grey .. "Las prescindibles las podés abandonar si te falta lugar en el registro." .. C.r) end
  if inGroup() then
    local missing = 0
    for _, e in ipairs(list) do if e.mates and #e.mates.without > 0 and not e.complete and e.tier < 5 then missing = missing + 1 end end
    if missing > 0 then L(actionLink("shareall", 0, "Compartir las " .. missing .. " que les faltan a tus amigos", "|cfffb923c")) end
  end

  local lastTier
  for _, e in ipairs(list) do
    local t = TIERS[e.tier]
    if e.tier ~= lastTier then endBlock(); L(t.sq .. " " .. t.color .. t.label .. C.r); lastTier = e.tier end
    local col = (GetQuestDifficultyColor and e.level and hexColor(GetQuestDifficultyColor(e.level))) or C.gold
    local acts = ""
    if e.id and e.tier < 5 then
      acts = "  " .. actionLink("go", e.id, "Ir")
      if inGroup() and e.mates and #e.mates.without > 0 and not e.complete then acts = acts .. " " .. actionLink("share", e.id, "Compartir", "|cfffb923c") end
    end
    local mark = e.classQuest and (C.red .. "!! " .. C.r) or (e.important and (C.gold .. "! " .. C.r)) or ""
    -- One card per quest, like the Ahora tab: title folds the card, tier color on the left edge.
    H(mark .. col .. "[" .. (e.level or "?") .. "] " .. (e.title or "?") .. C.r, e.tier >= 5, t.rgb)
    L(C.grey .. (e.header or "") .. C.r .. acts)
    if e.important then
      L("     " .. (e.classQuest and (C.red .. "!! De tu clase: " .. C.r) or (C.gold .. "! Importante: " .. C.r)) .. e.important)
    end
    L("     " .. C.grey .. e.why .. C.r)
    if e.complete then
      local d = e.fdj or e.prereq
      local guide = G.questGuides and e.id and G.questGuides[e.id]
      if d and d.turnin then B("Entregar a: " .. C.green .. d.turnin .. C.r)
      elseif not guide then B(C.grey .. "Volvé con quien te la dio (está en el texto de la misión)." .. C.r) end
      questGuideBlock(e)
    elseif e.tier < 5 then
      if e.summary and e.summary ~= "" then L("     " .. e.summary) end
      -- Quest item you have to use (bowl, totem, flare...).
      local itemLink = GetQuestLogSpecialItemInfo and try(GetQuestLogSpecialItemInfo, e.index)
      if type(itemLink) == "string" and not (issecretvalue and issecretvalue(itemLink)) then
        B(C.gold .. "Tiene un objeto para usar: " .. C.r .. itemLink .. C.grey .. " (usalo desde tu bolsa donde lo pida la misión)" .. C.r)
      end
      -- Which step you are on when there are several.
      if #e.objectives > 1 then
        local step
        for i, o in ipairs(e.objectives) do if not o.done then step = i; break end end
        if step then B(C.grey .. "Paso " .. step .. " de " .. #e.objectives .. C.r) end
      end
      questGuideBlock(e)
      -- Full quest text on demand.
      if e.desc and e.desc ~= "" and e.id then
        if DB.questText and DB.questText[e.id] then
          L("     " .. C.grey .. e.desc .. C.r)
          L("     " .. actionLink("text", e.id, "Ocultar texto", "|cff9ca3af"))
        else
          L("     " .. actionLink("text", e.id, "Ver texto completo", "|cff9ca3af"))
        end
      end
      local allDone = #e.objectives > 0
      for _, o in ipairs(e.objectives) do
        if o.need and o.need > 1 then P(o.text, o.have or 0, o.need, o.done)
        else L("     " .. (o.done and (C.green .. "+ ") or (C.grey .. "- ")) .. o.text .. C.r) end
        if not o.done then allDone = false end
      end
      -- Forever quests can add objectives in sequence: everything visible is done but the quest is not.
      if allDone then B(C.orange .. "Lo visible está hecho pero la misión no: aparece un objetivo nuevo o hay que hablar con alguien. Tocá [Ir]." .. C.r) end
      local wp = questWaypoint(e, s)
      if wp then B(C.blue .. wp .. C.r) end
      local where = mapLabel(e.prereq and e.prereq.map) or mapLabel(e.startMap)
      if where then B(C.grey .. "Mapa: " .. where .. C.r) end
      local d = e.fdj or e.prereq
      if d and d.turnin then B("Entregar a: " .. d.turnin) end
      if d and d.warning then B(C.orange .. d.warning .. C.r) end
      if e.chain and #e.chain > 0 then
        local names = {}
        for _, c in ipairs(e.chain) do names[#names + 1] = c.name end
        B(C.grey .. "Antes: " .. table.concat(names, ", ") .. C.r)
      end
      each(e.tips, function(tip) B(C.grey .. tip .. C.r) end)
    end
    if e.mates and not e.complete then
      if #e.mates.with > 0 then B(C.green .. "También: " .. table.concat(e.mates.with, ", ") .. C.r) end
      if #e.mates.without > 0 then B(C.orange .. "No la tiene: " .. table.concat(e.mates.without, ", ") .. " -> tocá [Compartir]" .. C.r) end
    end
    local note = G.questNotes and e.id and G.questNotes[e.id]
    if note then B(C.gold .. note .. C.r) end
  end
  endBlock(); L(C.grey .. "Tocá [Ir] para poner un marcador con flecha. El mapa (M) sombrea la zona de cada objetivo." .. C.r)
end

-- Completed quests and the XP they give (for "Para hacer ya").
readyQuestsSummary = function()
  local n, xp = 0, 0
  for _, e in ipairs(questEntries()) do
    if e.complete then
      n = n + 1
      local _, rx = questStatic(e)
      xp = xp + (rx or 0)
    end
  end
  if n == 0 then return nil end
  local line = C.green .. "Entregá " .. n .. " misión(es) lista(s)" .. C.r
  local cur, max = plain(UnitXP("player")), plain(UnitXPMax("player"))
  if xp > 0 then
    line = line .. ": +" .. fmtNum(xp) .. " XP"
    if cur and max and max > 0 then
      if cur + xp >= max then line = line .. C.gold .. " (¡subís de nivel!)" .. C.r
      else line = line .. C.grey .. " (quedás al " .. math.floor((cur + xp) / max * 100) .. "%)" .. C.r end
    end
  end
  return line
end

-- The completed quest closest to you, with [Ir] (for "Para hacer ya").
-- XP to go from level L to L+1 on Classic Era. Forever may differ, so the table is rescaled by what the
-- client says for your current level (UnitXPMax).
local XP_TO_NEXT = { 400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8800, 10100, 11400, 12900, 14400, 16000,
  17700, 19400, 21300, 23200, 25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400, 50800, 54500, 58600,
  62800, 67100, 71600, 76100, 80800, 85700, 90700, 95800, 101000, 106300, 111800, 117500, 123200, 129100, 135100,
  141200, 147500, 153900, 160400, 167100, 173900, 180800, 187900, 195000, 202300, 209800 }

-- "Meta: nivel N" card on Ahora (/guia meta N): XP left, what your quest log covers, kills for the rest,
-- time at your pace and where to go.
goalPlan = function(s)
  local function num(v) if issecretvalue and issecretvalue(v) then return nil end return tonumber(v) end
  local goal = tonumber(DB.goalLevel)
  if not goal then return end
  if goal <= s.level then
    H("Tu meta")
    B(C.green .. "¡Llegaste al " .. goal .. "! Poné otra con /guia meta " .. math.min(s.level + 2, 60) .. "." .. C.r)
    return
  end
  local xp, xpMax = num(UnitXP("player")) or 0, num(UnitXPMax("player")) or 0
  local scale = (XP_TO_NEXT[s.level] and xpMax > 0) and (xpMax / XP_TO_NEXT[s.level]) or 1
  local need = math.max(xpMax - xp, 0)
  for l = s.level + 1, goal - 1 do need = need + math.floor((XP_TO_NEXT[l] or XP_TO_NEXT[#XP_TO_NEXT]) * scale) end

  local readyXP, readyN, openXP, openN, unknown = 0, 0, 0, 0, 0
  for _, e in ipairs(questEntries()) do
    local _, qxp = questStatic(e)
    local lvl = (e.level and e.level > 0) and e.level or s.level
    if e.complete then readyN = readyN + 1; readyXP = readyXP + (qxp or 0)
    elseif lvl <= s.level + 3 then
      openN = openN + 1; openXP = openXP + (qxp or 0)
      if not qxp then unknown = unknown + 1 end
    end
  end

  H("Tu meta: nivel " .. goal)
  B("Te faltan " .. C.gold .. fmtNum(need) .. " XP" .. C.r .. " (" .. (goal - s.level) .. " nivel" .. (goal - s.level > 1 and "es" or "") .. ").")
  local left = need
  if readyN > 0 then
    B(C.green .. "1) Entregá " .. readyN .. " misión(es) lista(s): " .. fmtNum(readyXP) .. " XP." .. C.r)
    left = left - readyXP
  end
  if openN > 0 and left > 0 then
    B((readyN > 0 and "2) " or "1) ") .. "Terminá tus " .. openN .. " misiones de tu nivel: " .. fmtNum(openXP) .. " XP"
      .. (unknown > 0 and C.grey .. " (" .. unknown .. " sin dato de XP)" .. C.r or "") .. ".")
    left = left - openXP
  end
  if left <= 0 then
    B(C.green .. "Con tus misiones alcanza para llegar." .. C.r)
  else
    -- Kill XP: your real average this session, else a same-level mob on Classic (45 + 5 x level).
    local per = (S.kills >= 5 and S.killXP > 0) and (S.killXP / S.kills) or (45 + 5 * s.level)
    -- Rested doubles kill XP until the pool is spent.
    local base = (s.rested >= left / 2) and (left / 2) or (left - s.rested)
    local kills = math.ceil(base / per)
    B("Para el resto (" .. fmtNum(left) .. " XP): unas " .. C.gold .. kills .. " muertes" .. C.r .. " de tu nivel (~" .. math.floor(per) .. " XP c/u"
      .. (s.rested > 0 and ", con descanso" or "") .. "), o misiones nuevas de las zonas de abajo.")
  end
  local r = stats()
  local rate = r and (r.recentPerHour or r.perHour)
  if rate and rate > 0 and (S.xp or 0) > 0 then B("A tu ritmo (" .. fmtNum(rate) .. " XP/h): " .. C.gold .. fmtTime(need / rate * 3600) .. C.r .. ".") end
  local zones = {}
  for _, z in ipairs(G.zones or {}) do
    if (not z.faction or z.faction == s.faction) and z.min and z.max and z.min <= goal - 1 and z.max >= s.level then
      zones[#zones + 1] = z.label .. " (" .. z.min .. "-" .. z.max .. ")"
    end
  end
  if #zones > 0 then B("Zonas para este tramo: " .. table.concat(zones, ", ", 1, math.min(#zones, 4)) .. ".") end
  B(C.grey .. "Cambiala con /guia meta " .. math.min(goal + 2, 60) .. " · sacala con /guia meta no." .. C.r)
end

nearestTurnIn = function(s)
  local mapID = s and s.mapID
  local px, py = playerPoint(mapID)
  local best, bestD, bestDir, anyReady
  for _, e in ipairs(questEntries()) do
    if e.complete and e.id then
      anyReady = anyReady or e
      local x, y
      if px then x, y = questPoint(e, mapID) end
      if x and y then
        local dir, d = direction(px, py, x, y)
        if not bestD or d < bestD then best, bestD, bestDir = e, d, dir end
      end
    end
  end
  best = best or anyReady
  if not best then return nil end
  local _, xp = questStatic(best)
  return C.green .. "La más cerca: " .. C.r .. (best.title or "?") .. (bestDir and (C.blue .. " (" .. bestDir .. ")" .. C.r) or "")
    .. ((xp or 0) > 0 and (C.grey .. " +" .. fmtNum(xp) .. " XP" .. C.r) or "") .. "  " .. actionLink("go", best.id, "Ir")
end

local function buildGuide()
  H("Mazmorras")
  buildDungeons()
  H("Profesiones")
  buildProfessions()
  H("Consejos", true)
  buildTips()
end

local function unitFlag(fn, unit)
  if type(fn) ~= "function" then return nil end
  local ok, v = pcall(fn, unit)
  if not ok or (issecretvalue and issecretvalue(v)) then return nil end
  return v
end

-- Your progress on a quest as "3/8" (summed counts), the same number party members receive.
local function questProgress(e)
  if e.complete then return "LISTA" end
  local d, n = 0, 0
  for _, o in ipairs(questObjectives(e)) do
    if o.need and o.need > 0 then n = n + o.need; d = d + math.min(o.have or 0, o.need)
    else n = n + 1; if o.done then d = d + 1 end end
  end
  return n > 0 and (d .. "/" .. n) or "-"
end

local function questTitle(id)
  local t = C_QuestLog and C_QuestLog.GetTitleForQuestID and try(C_QuestLog.GetTitleForQuestID, id)
  if not t and C_QuestLog and C_QuestLog.GetQuestInfo then t = try(C_QuestLog.GetQuestInfo, id) end
  if type(t) == "string" and t ~= "" and not (issecretvalue and issecretvalue(t)) then return t end
  return "misión " .. id
end

local function memberRow(name, colorHex, m, unit)
  local status = {}
  if unit then
    if unitFlag(UnitIsConnected, unit) == false then status[#status + 1] = C.grey .. "desconectado" .. C.r
    elseif unitFlag(UnitIsDeadOrGhost, unit) then status[#status + 1] = C.red .. "MUERTO" .. C.r end
    if unitFlag(UnitInRange, unit) == false then status[#status + 1] = C.orange .. "lejos" .. C.r end
  end
  local lvl = (m and m.level) or (unit and UnitLevel(unit)) or "?"
  local head = colorHex .. name .. C.r .. " " .. lvl
  if m and m.xpPct then
    P(head .. "  " .. m.xpPct .. "%" .. ((m.rested or 0) > 0 and (C.blue .. "  descanso " .. m.rested .. "%" .. C.r) or ""), m.xpPct, 100, false)
  else
    L("  " .. head)
  end
  local parts = {}
  if m then
    if m.perHour and m.perHour > 0 then parts[#parts + 1] = fmtNum(m.perHour) .. " XP/h" end
    if m.toLevel then parts[#parts + 1] = "sube en " .. fmtTime(m.toLevel) end
    if m.bags then parts[#parts + 1] = (m.bags <= 2 and C.orange .. "bolsas " .. m.bags .. "!" .. C.r or "bolsas " .. m.bags) end
    if m.dur then parts[#parts + 1] = (m.dur <= 30 and C.red .. "equipo " .. m.dur .. "%!" .. C.r or "equipo " .. m.dur .. "%") end
    local pr = {}
    for pn, rank in pairs(m.profs or {}) do pr[#pr + 1] = pn .. " " .. rank end
    table.sort(pr)
    if #pr > 0 then parts[#parts + 1] = C.grey .. table.concat(pr, ", ") .. C.r end
    if m.at and GetTime() - m.at > 120 then parts[#parts + 1] = C.grey .. "(datos de hace " .. fmtTime(GetTime() - m.at) .. ")" .. C.r end
  else
    parts[#parts + 1] = C.grey .. "sin la Guía: solo nivel y estado" .. C.r
  end
  for _, st in ipairs(status) do parts[#parts + 1] = st end
  L("     " .. table.concat(parts, C.grey .. " · " .. C.r))
end

local function buildGroup()
  if not inGroup() then
    L(C.grey .. "No estás en grupo." .. C.r)
    B("Invitá a tus amigos: clic derecho en su retrato -> Invitar.")
    B("Si tienen la Guía ves su nivel, ritmo, bolsas, equipo, profesiones y en qué etapa va cada misión.")
    return
  end
  local units = partyUnits()
  local me = myStatus()
  local r = stats()
  H("Grupo" .. (r and (" (sesión: " .. fmtTime(r.elapsed) .. ")") or ""))
  local _, myClass = UnitClass("player")
  local mc = RAID_CLASS_COLORS and myClass and RAID_CLASS_COLORS[myClass]
  memberRow(UnitName("player") or "Vos", mc and hexColor(mc) or C.gold, me)
  local names = {}
  for _, u in ipairs(units) do
    local name = UnitName(u)
    if name then
      names[#names + 1] = name
      local _, classFile = UnitClass(u)
      local c = RAID_CLASS_COLORS and classFile and RAID_CLASS_COLORS[classFile]
      memberRow(name, c and hexColor(c) or C.gold, partyStats[name], u)
    end
  end

  -- Shared quests: one line per quest, everyone's stage.
  H("Misiones en común")
  local list, mine, any = questEntries(), {}, false
  for _, e in ipairs(list) do
    if e.id then mine[e.id] = true end
    local cols, has, missing = {}, false, false
    for i, u in ipairs(units) do
      local name = names[i] or UnitName(u)
      local pd = name and partyData[name]
      local q = pd and e.id and pd[e.id]
      if q then has = true; cols[#cols + 1] = name .. " " .. (q.c and C.green .. "LISTA" .. C.r or (q.d .. "/" .. q.n))
      elseif not pd and unitOnQuest(u, e) then has = true; cols[#cols + 1] = name .. " la tiene"
      else missing = true; cols[#cols + 1] = C.grey .. name .. " -" .. C.r end
    end
    if has then
      any = true
      local mineP = questProgress(e)
      B(C.gold .. (e.title or "?") .. C.r .. "  vos " .. (mineP == "LISTA" and C.green .. "LISTA" .. C.r or mineP) .. C.grey .. " · " .. C.r
        .. table.concat(cols, C.grey .. " · " .. C.r) .. (missing and e.id and ("  " .. actionLink("share", e.id, "Compartir", "|cfffb923c")) or ""))
    end
  end
  if not any then B(C.grey .. "Ninguna todavía: compartí las tuyas desde la pestaña Misiones." .. C.r) end
  local theirs = {}
  for name, pd in pairs(partyData) do
    for id, q in pairs(pd) do
      if not mine[id] and not q.c then theirs[id] = theirs[id] or {}; table.insert(theirs[id], name) end
    end
  end
  local rows = {}
  for id, who in pairs(theirs) do rows[#rows + 1] = { id = id, who = who } end
  table.sort(rows, function(a, b) return #a.who > #b.who end)
  if #rows > 0 then
    H2("Las tienen ellos y vos no (pedí que te la compartan)")
    for i = 1, math.min(#rows, 6) do B(questTitle(rows[i].id) .. C.grey .. " · " .. table.concat(rows[i].who, ", ") .. C.r) end
  end

  -- Today: the group's session.
  H("Hoy")
  local xp, kills, deaths, money, worst = me.xp, me.kills, me.deaths, me.money, nil
  local deathRows = { { UnitName("player") or "Vos", me.deaths } }
  for _, name in ipairs(names) do
    local m = partyStats[name]
    if m then
      xp, kills, deaths, money = xp + m.xp, kills + m.kills, deaths + m.deaths, money + m.money
      deathRows[#deathRows + 1] = { name, m.deaths }
    end
  end
  B(fmtNum(xp) .. " XP entre todos · " .. kills .. " bichos · " .. deaths .. " muertes · oro " .. fmtMoney(money))
  table.sort(deathRows, function(a, b) return a[2] > b[2] end)
  if deathRows[1][2] > 0 then B(C.grey .. "Más muertes: " .. deathRows[1][1] .. " (" .. deathRows[1][2] .. ")" .. C.r) end
  local without = 0
  for _, name in ipairs(names) do if not partyStats[name] then without = without + 1 end end
  if without > 0 then B(C.grey .. without .. " sin la Guía: sus números no suman acá." .. C.r) end
end

-- Ruta: the leveling roadmap (Roadmap.lua).
local function buildRoadmap()
  if G.roadmap and G.roadmap.build then G.roadmap.build(playerState()) else L("Falta Roadmap.lua.") end
end
local BUILDERS = { buildNow, buildQuests, buildRoadmap, buildGroup, buildClass, buildGuide }

-- ---------------------------------------------------------------- UI
local updateToggles
local layoutBlocks
local applySize, smallHeight -- defined further down (window size modes)
local settingsPanel, minimapButton
local frame, scroll, content, text, tabButtons, specButton, header, xpBar, restBar, xpText, nameText, classIcon, subText, pvpToggle, notifyToggle

local function classColor()
  local class = select(2, UnitClass("player"))
  local c = (RAID_CLASS_COLORS and class and RAID_CLASS_COLORS[class]) or { r = 0.85, g = 0.47, b = 0.34 }
  return c.r, c.g, c.b
end

updateToggles = function()
  if not pvpToggle then return end
  local on = G.pvp and G.pvp.isOn()
  pvpToggle.label:SetTextColor(on and 0.29 or 0.5, on and 0.87 or 0.5, on and 0.5 or 0.5)
  local m = G.notify and G.notify.mode()
  notifyToggle.label:SetTextColor(m == "no" and 0.5 or 0.29, m == "no" and 0.5 or 0.87, m == "no" and 0.5 or 0.5)
end

local function updateHeader()
  if not header then return end
  local r, g, b = classColor()
  local class = select(2, UnitClass("player"))
  local coords = CLASS_ICON_TCOORDS and class and CLASS_ICON_TCOORDS[class]
  if coords then
    classIcon:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
    classIcon:SetTexCoord(unpack(coords))
  else
    classIcon:SetTexture("Interface\\Icons\\INV_Misc_Book_09"); classIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  end
  local level = UnitLevel("player") or 1
  nameText:SetText((UnitName("player") or "") .. "  |cffffffff" .. level .. "|r  " .. "|cff9ca3af" .. (GetZoneText() or "") .. "|r")
  nameText:SetTextColor(r, g, b)
  local xp, maxXP = plain(UnitXP("player")), plain(UnitXPMax("player"))
  local rested = plain(GetXPExhaustion and GetXPExhaustion()) or 0
  if xp and maxXP and maxXP > 0 then
    xpBar:SetMinMaxValues(0, maxXP); xpBar:SetValue(xp)
    restBar:SetMinMaxValues(0, maxXP); restBar:SetValue(math.min(maxXP, xp + rested))
    xpText:SetText(math.floor(xp / maxXP * 100) .. "%" .. (rested > 0 and ("  |cff7dd3fc+" .. rested .. " descanso|r") or ""))
  end
  local okStats, line = pcall(headerStats)
  subText:SetText((DB.headerStats ~= false and okStats and line) or "Guía Forever")
  updateToggles()
  frame:SetBackdropBorderColor(r, g, b, 0.7)
  for _, tb in ipairs(tabButtons) do tb.line:SetColorTexture(r, g, b, 1) end
end

-- ---------------------------------------------------------------- card layout
-- Everything is drawn as regions of the scroll child (so hyperlinks keep working), except progress
-- bars which are StatusBars. Widgets are pooled and reused on every render.
local pool = { fs = {}, title = {}, tex = {}, bar = {} }
local used = { fs = 0, title = 0, tex = 0, bar = 0 }
local function acquire(kind)
  used[kind] = used[kind] + 1
  local w = pool[kind][used[kind]]
  if not w then
    if kind == "fs" then
      w = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      w:SetJustifyH("LEFT"); w:SetJustifyV("TOP"); w:SetSpacing(3)
    elseif kind == "title" then
      w = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      w:SetJustifyH("LEFT"); w:SetWordWrap(false)
    elseif kind == "tex" then
      w = content:CreateTexture(nil, "BACKGROUND")
    else
      w = CreateFrame("StatusBar", nil, content)
      w:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
      w.bg = w:CreateTexture(nil, "BACKGROUND"); w.bg:SetAllPoints(); w.bg:SetColorTexture(1, 1, 1, 0.07)
      w.text = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      w.text:SetPoint("LEFT", 5, 0); w.text:SetPoint("RIGHT", -5, 0); w.text:SetJustifyH("LEFT"); w.text:SetWordWrap(false)
      local f, sz = w.text:GetFont(); if f then w.text:SetFont(f, sz or 10, "OUTLINE") end
    end
    pool[kind][used[kind]] = w
  end
  w:ClearAllPoints(); w:Show()
  return w
end

layoutBlocks = function()
  for k in pairs(used) do used[k] = 0 end
  local width = math.max((content:GetWidth() or 300), 200)
  local size = DB.fontSize or 12
  local cr, cg, cb = 0.85, 0.47, 0.34
  local class = select(2, UnitClass("player"))
  local cc = RAID_CLASS_COLORS and class and RAID_CLASS_COLORS[class]
  if cc then cr, cg, cb = cc.r, cc.g, cc.b end
  local y = -2
  local onlyFirst, drawn = DB.size == "small", 0
  for _, b in ipairs(blocks) do
    if onlyFirst and drawn > 0 then break end
    -- trim blank lines at the edges of the card
    while b.items[1] and b.items[1].kind == "text" and b.items[1].text == "" do table.remove(b.items, 1) end
    while b.items[#b.items] and b.items[#b.items].kind == "text" and b.items[#b.items].text == "" do table.remove(b.items) end
    if b.title or #b.items > 0 then
      local top = y
      y = y - 6
      if b.title then
        local t = acquire("title")
        local f = t:GetFont(); if f then t:SetFont(f, size + 1, "") end
        t:SetPoint("TOPLEFT", content, "TOPLEFT", 12, y); t:SetWidth(width - 24)
        t:SetText(b.title)
        local col = b.color
        if col then t:SetTextColor(col[1], col[2], col[3]) else t:SetTextColor(1, 0.82, 0) end
        y = y - (t:GetStringHeight() or 14) - (b.folded and 4 or 6)
      end
      local i = 1
      while i <= #b.items do
        local it = b.items[i]
        if it.kind == "bar" then
          local bar = acquire("bar")
          bar:SetPoint("TOPLEFT", content, "TOPLEFT", 26, y - 1); bar:SetSize(width - 44, 13)
          bar:SetMinMaxValues(0, math.max(it.need or 1, 1)); bar:SetValue(math.min(it.have or 0, it.need or 1))
          if it.done then bar:SetStatusBarColor(0.29, 0.87, 0.5, 0.75) else bar:SetStatusBarColor(cr, cg, cb, 0.6) end
          bar.text:SetText(it.text)
          y = y - 16
          i = i + 1
        else
          local lines = {}
          while i <= #b.items and b.items[i].kind == "text" do lines[#lines + 1] = b.items[i].text; i = i + 1 end
          local fs = acquire("fs")
          local f = fs:GetFont(); if f then fs:SetFont(f, size, "") end
          fs:SetPoint("TOPLEFT", content, "TOPLEFT", 10, y); fs:SetWidth(width - 20)
          fs:SetText(table.concat(lines, "\n"))
          y = y - (fs:GetStringHeight() or 14) - 4
        end
      end
      y = y - 4
      if b.title then
        local bg = acquire("tex")
        bg:SetPoint("TOPLEFT", content, "TOPLEFT", 2, top); bg:SetPoint("BOTTOMRIGHT", content, "TOPLEFT", width - 2, y)
        bg:SetColorTexture(1, 1, 1, 0.045)
        local accent = acquire("tex")
        accent:SetPoint("TOPLEFT", bg, "TOPLEFT"); accent:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT"); accent:SetWidth(2)
        local col = b.color or { cr, cg, cb }
        accent:SetColorTexture(col[1], col[2], col[3], 0.9)
      end
      y = y - 6
      drawn = drawn + 1
    end
  end
  for kind, list in pairs(pool) do
    for n = used[kind] + 1, #list do list[n]:Hide() end
  end
  content:SetHeight(-y + 10)
end

local function render()
  if not frame or not frame:IsShown() then return end
  local okH, errH = pcall(updateHeader)
  blocks, curBlock, foldKeys, skipping = {}, nil, {}, false
  if not DB.tab or DB.tab > #BUILDERS then DB.tab = 1 end
  local ok, err = pcall(BUILDERS[DB.tab or 1])
  if not ok then blocks = {}; curBlock = nil; raw(C.red .. "Error en la guía: " .. tostring(err) .. C.r) end
  layoutBlocks()
  if DB.size == "small" and scroll and frame:GetTop() and scroll:GetTop() then
    local want = math.floor((frame:GetTop() - scroll:GetTop()) + content:GetHeight() + 30)
    if want ~= smallHeight then smallHeight = math.max(90, math.min(want, DB.h or 420)); applySize() end
  end
  for i, b in ipairs(tabButtons) do
    local active = i == (DB.tab or 1)
    b.line:SetShown(active)
    b.label:SetTextColor(active and 1 or 0.6, active and 1 or 0.6, active and 1 or 0.65)
  end
  specButton:SetShown(not DB.collapsed and (DB.tab or 1) == TAB_CLASS and G.classes[select(2, UnitClass("player"))] ~= nil)
end

local function cycleSpec()
  local class = select(2, UnitClass("player"))
  local cd = G.classes[class]
  if not cd or not cd.specOrder then return end
  local cur = specKey(cd)
  local idx = 1
  for i, k in ipairs(cd.specOrder) do if k == cur then idx = i end end
  DB.spec = DB.spec or {}
  DB.spec[class] = cd.specOrder[(idx % #cd.specOrder) + 1]
  render()
end

-- Window size: "big" (everything), "small" (header, tabs and only the first card), "hide" (header only).
local SIZE_NEXT = { big = "small", small = "hide", hide = "big" }
local SIZE_LABEL = { big = "–", small = "=", hide = "+" }
local SIZE_TIP = { big = "Grande: todo. Clic: chica.", small = "Chica: solo la primera tarjeta. Clic: oculta.", hide = "Oculta: solo el encabezado. Clic: grande." }
local function sizeMode()
  local m = DB.size
  if not SIZE_NEXT[m] then m = DB.collapsed and "hide" or "big" end
  return m
end
applySize = function()
  DB.size = sizeMode()
  DB.collapsed = DB.size == "hide"
  local h = DB.collapsed and 34 or (DB.size == "small" and smallHeight or DB.h or 420)
  frame:SetSize(math.max(DB.w or 350, 340), h)
  scroll:SetShown(not DB.collapsed)
  restBar:SetShown(not DB.collapsed)
  -- XP bar under the title: off by default (WoW already has one). The bar stays as a 0-height anchor for the tabs.
  restBar:SetHeight(DB.xpBar and 10 or 0.1); restBar:SetAlpha(DB.xpBar and 1 or 0)
  for _, b in ipairs(tabButtons) do b:SetShown(not DB.collapsed) end
  if DB.collapsed then specButton:Hide() end
end

-- Flat button: dark fill, light text, subtle hover.
local function flatButton(parent, label, w, h)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(w, h)
  b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  b:SetBackdropColor(1, 1, 1, 0.06); b:SetBackdropBorderColor(1, 1, 1, 0.12)
  b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.label:SetPoint("CENTER"); b.label:SetText(label)
  b:SetScript("OnEnter", function(s) s:SetBackdropColor(1, 1, 1, 0.14) end)
  b:SetScript("OnLeave", function(s) s:SetBackdropColor(1, 1, 1, 0.06) end)
  return b
end

local function createUI()
  frame = CreateFrame("Frame", "GuiaForeverFrame", UIParent, "BackdropTemplate")
  frame:SetFrameStrata("MEDIUM")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true); frame:SetResizable(true)
  if frame.SetResizeBounds then frame:SetResizeBounds(340, 220, 700, 900) end
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", function(f)
    f:StopMovingOrSizing()
    local p, _, rp, x, y = f:GetPoint()
    DB.pos = { p, rp, x, y }
  end)
  frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  frame:SetBackdropColor(0.06, 0.06, 0.08, DB.alpha or 0.9)
  local pos = DB.pos or { "RIGHT", "RIGHT", -40, 60 }
  frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])

  -- Header: class icon, name/level/zone, close and collapse.
  header = CreateFrame("Frame", nil, frame)
  header:SetPoint("TOPLEFT", 1, -1); header:SetPoint("TOPRIGHT", -1, -1); header:SetHeight(32)
  local hbg = header:CreateTexture(nil, "BACKGROUND")
  hbg:SetAllPoints(); hbg:SetColorTexture(1, 1, 1, 0.04)
  classIcon = header:CreateTexture(nil, "ARTWORK")
  classIcon:SetSize(24, 24); classIcon:SetPoint("LEFT", 6, 0)
  nameText = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  nameText:SetPoint("TOPLEFT", classIcon, "TOPRIGHT", 7, -1)
  nameText:SetPoint("RIGHT", header, "RIGHT", -140, 0); nameText:SetJustifyH("LEFT"); nameText:SetWordWrap(false)
  subText = header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  local sub = subText
  sub:SetPoint("BOTTOMLEFT", classIcon, "BOTTOMRIGHT", 7, 0)
  sub:SetText("Guía Forever")

  local close = CreateFrame("Button", nil, header, "UIPanelCloseButton")
  close:SetPoint("RIGHT", -2, 0); close:SetSize(24, 24)
  close:SetScript("OnClick", function() frame:Hide(); DB.hidden = true end)
  local mini = flatButton(header, "–", 18, 16)
  mini:SetPoint("RIGHT", close, "LEFT", -2, 0)
  mini.label:SetText(SIZE_LABEL[sizeMode()])
  mini:SetScript("OnClick", function(self)
    DB.size = SIZE_NEXT[sizeMode()]; applySize(); render()
    self.label:SetText(SIZE_LABEL[DB.size])
    if GameTooltip:IsOwned(self) then GameTooltip:SetText(SIZE_TIP[DB.size], 1, 1, 1, 1, true) end
  end)
  mini:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:SetText(SIZE_TIP[sizeMode()], 1, 1, 1, 1, true); GameTooltip:Show()
  end)
  mini:HookScript("OnLeave", function() GameTooltip:Hide() end)

  -- On/off toggles: green = on, grey = off. Hover shows what they do.
  local function toggle(label, w, tip, onClick)
    local b = flatButton(header, label, w, 16)
    b:SetScript("OnClick", function() onClick(); updateToggles() end)
    b:SetScript("OnEnter", function(self)
      self:SetBackdropColor(1, 1, 1, 0.14)
      if GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:SetText(tip(), 1, 1, 1, 1, true); GameTooltip:Show() end
    end)
    b:SetScript("OnLeave", function(self) self:SetBackdropColor(1, 1, 1, 0.06); if GameTooltip then GameTooltip:Hide() end end)
    return b
  end
  notifyToggle = toggle("Avisos", 40, function()
    return "Avisos de misión: " .. (G.notify and G.notify.label() or "?") .. "\nClic: listas -> todo -> apagados"
  end, function() if G.notify then G.notify.command("") end end)
  notifyToggle:SetPoint("RIGHT", mini, "LEFT", -3, 0)
  pvpToggle = toggle("PvP", 26, function()
    return "Alertas de enemigos: " .. ((G.pvp and G.pvp.isOn()) and "activadas" or "apagadas") .. "\nClic para prender/apagar"
  end, function() if G.pvp then G.pvp.command("") end end)
  pvpToggle:SetPoint("RIGHT", notifyToggle, "LEFT", -3, 0)

  -- Settings button: opens the Ajustes panel over the content area.
  local gear = CreateFrame("Button", nil, header)
  gear:SetSize(16, 16); gear:SetPoint("RIGHT", pvpToggle, "LEFT", -4, 0)
  local gearIcon = gear:CreateTexture(nil, "ARTWORK")
  gearIcon:SetAllPoints(); gearIcon:SetTexture("Interface\\Icons\\Trade_Engineering"); gearIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  local gearHl = gear:CreateTexture(nil, "HIGHLIGHT")
  gearHl:SetAllPoints(); gearHl:SetColorTexture(1, 1, 1, 0.15)
  gear:SetScript("OnClick", function() if settingsPanel then settingsPanel:SetShown(not settingsPanel:IsShown()); if settingsPanel.refresh then settingsPanel.refresh() end end end)
  gear:SetScript("OnEnter", function(self) if GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:SetText("Ajustes"); GameTooltip:Show() end end)
  gear:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

  -- XP bar with rested overlay.
  restBar = CreateFrame("StatusBar", nil, frame)
  restBar:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0); restBar:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
  restBar:SetHeight(10)
  restBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar"); restBar:SetStatusBarColor(0.25, 0.45, 0.9, 0.45)
  local rbg = restBar:CreateTexture(nil, "BACKGROUND"); rbg:SetAllPoints(); rbg:SetColorTexture(0, 0, 0, 0.5)
  xpBar = CreateFrame("StatusBar", nil, restBar)
  xpBar:SetAllPoints()
  xpBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar"); xpBar:SetStatusBarColor(0.58, 0.0, 0.55, 0.95)
  xpText = xpBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  xpText:SetPoint("CENTER", 0, 0)
  xpText:SetFont(xpText:GetFont(), 9, "OUTLINE")

  -- Flat tabs with an underline on the active one.
  tabButtons = {}
  local prev
  for i, name in ipairs(TABS) do
    local b = CreateFrame("Button", nil, frame)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.label:SetPoint("CENTER", 0, 1); b.label:SetText(name)
    b:SetSize(b.label:GetStringWidth() + 10, 20)
    b.line = b:CreateTexture(nil, "ARTWORK")
    b.line:SetHeight(2); b.line:SetPoint("BOTTOMLEFT", 3, 0); b.line:SetPoint("BOTTOMRIGHT", -3, 0)
    local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.06)
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 0, 0) else b:SetPoint("TOPLEFT", restBar, "BOTTOMLEFT", 4, -4) end
    b:SetScript("OnClick", function() DB.tab = i; scroll:SetVerticalScroll(0); render() end)
    tabButtons[i] = b; prev = b
  end
  local sep = frame:CreateTexture(nil, "ARTWORK")
  sep:SetHeight(1); sep:SetColorTexture(1, 1, 1, 0.08)
  sep:SetPoint("TOPLEFT", tabButtons[1], "BOTTOMLEFT", -4, 0); sep:SetPoint("RIGHT", frame, "RIGHT", -1, 0)

  scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", tabButtons[1], "BOTTOMLEFT", 6, -6)
  scroll:SetPoint("BOTTOMRIGHT", -26, 28)
  content = CreateFrame("Frame", nil, scroll)
  content:SetSize(1, 1)
  scroll:SetScrollChild(content)
  if content.SetHyperlinksEnabled then
    content:SetHyperlinksEnabled(true)
    content:SetScript("OnHyperlinkClick", function(_, link) onLink(link) end)
  end
  scroll:SetScript("OnSizeChanged", function(_, w) content:SetWidth(w); render() end)

  -- ---------------------------------------------------------- Ajustes panel
  -- Categories as chips on top; each row = name, a short explanation and its control (switch, choice or +/-).
  settingsPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  settingsPanel:SetPoint("TOPLEFT", scroll, "TOPLEFT", -6, 4); settingsPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
  settingsPanel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
  settingsPanel:SetBackdropColor(0.06, 0.06, 0.08, 0.98)
  settingsPanel:SetFrameLevel((frame:GetFrameLevel() or 1) + 10)
  settingsPanel:EnableMouse(true)
  settingsPanel:Hide()
  local title = settingsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 10, -8); title:SetText("Ajustes")
  local closeS = flatButton(settingsPanel, "Listo", 50, 18)
  closeS:SetPoint("TOPRIGHT", -8, -6)
  closeS:SetScript("OnClick", function() settingsPanel:Hide(); render() end)

  local function pvp(key) return G.pvp and G.pvp.get(key) end
  local function setPvp(key, v) if G.pvp then G.pvp.set(key, v) end end
  local function meter(key) return G.meter and G.meter.get(key) end
  local function setMeter(key, v) if G.meter then G.meter.set(key, v) end end
  -- DB flag that is ON unless set to false.
  local function flag(key) return { get = function() return DB[key] ~= false end, set = function(v) DB[key] = v end, default = true } end
  -- DB flag that is OFF unless set to true.
  local function optIn(key) return { get = function() return DB[key] == true end, set = function(v) DB[key] = v or nil end, default = false } end
  local function subflag(tbl, key, default)
    return { get = function() local t = DB[tbl]; local v = t and t[key]; if v == nil then return default end return v end,
      set = function(v) DB[tbl] = DB[tbl] or {}; DB[tbl][key] = v end, default = default }
  end
  local function with(t, extra) for k, v in pairs(extra) do t[k] = v end return t end
  local NOTIFY_LABEL = { listas = "Solo misiones listas", todo = "Todo (cada objetivo)", no = "Apagados" }
  local bagRefresh = function() if G.items and G.items.refreshBags then G.items.refreshBags() end end

  local CATEGORIES = {
    { name = "General", rows = {
      { label = "Barra de XP arriba", desc = "La barra violeta con el % debajo del título. Apagada: WoW ya tiene la suya.", default = false,
        get = function() return DB.xpBar == true end, set = function(v) DB.xpBar = v or nil end, after = function() applySize() end },
      with(flag("headerStats"), { label = "XP/h debajo del nombre", desc = "Ritmo de XP y tiempo para subir en el encabezado." }),
      with(flag("cityPins"), { label = "Servicios en el mapa", desc = "En el mapa grande de cada pueblo y ciudad: posada, vuelo, reparar, tu instructor, maestros de armas, profesiones, banco y subasta. Clic para marcar el camino.",
        after = function() if G.cityMap then G.cityMap.refresh() end end }),
      { label = "Botón del minimapa", desc = "El libro del minimapa abre y cierra la Guía.", default = true,
        get = function() return not DB.minimapHidden end, set = function(v) DB.minimapHidden = not v; if minimapButton then minimapButton:SetShown(v) end end },
      { label = "Tamaño de letra", desc = "Del texto de la Guía.", value = function() return tostring(DB.fontSize or 12) end,
        step = function(d) DB.fontSize = math.max(9, math.min(18, (DB.fontSize or 12) + d)) end, reset = function() DB.fontSize = nil end },
      { label = "Opacidad del fondo", desc = "Qué tan transparente es la ventana.", value = function() return math.floor((DB.alpha or 0.9) * 100 + 0.5) .. "%" end,
        step = function(d) DB.alpha = math.max(0.2, math.min(1, (DB.alpha or 0.9) + d * 0.1)); frame:SetBackdropColor(0.06, 0.06, 0.08, DB.alpha) end,
        reset = function() DB.alpha = nil; frame:SetBackdropColor(0.06, 0.06, 0.08, 0.9) end },
    } },
    { name = "Misiones", rows = {
      { label = "Avisos de misión", desc = "Qué te avisa en el centro de la pantalla.", value = function() return NOTIFY_LABEL[G.notify and G.notify.mode() or "listas"] end,
        click = function() if G.notify then G.notify.command("") end end, reset = function() DB.notify = nil end },
      with(optIn("autoQuest"), { label = "Tomar y entregar solo", desc = "Al hablar con el PNJ acepta las misiones y entrega las terminadas. Si hay que elegir recompensa o pagar oro, lo hacés vos. Mantené Shift para hacerlo a mano. Apagado por defecto: Leatrix, Questie o RXP hacen lo mismo y dos a la vez se pisan." }),
      with(flag("notifySound"), { label = "Sonido de los avisos", desc = "Suena cuando una misión queda lista." }),
      with(flag("roadmapPins"), { label = "Misiones para tomar en el mapa", desc = "Un \"!\" en el mapa grande donde hay misiones que ya podés aceptar. Pasá el mouse para verlas, clic para el camino.",
        after = function() if G.roadmap then G.roadmap.refreshPins() end end }),
      with(flag("routePlan"), { label = "Plan de ruta", desc = "Arriba de Misiones: qué hacer y en qué orden, por cercanía y XP." }),
      with(flag("questMarks"), { label = "Marca en bichos de misión", desc = "Espadita con tu progreso sobre la barra del bicho, para matarlo o porque suelta un objeto de tu misión. Con ThreatPlates también: mientras esté prendida, la Guía apaga el ícono de misión de ThreatPlates para que haya una sola marca.",
        after = function() if G.questMarks then G.questMarks.refresh() end end }),
      with(flag("lootIcons"), { label = "Íconos de saqueo", desc = "Mano o bolsa del juego sobre cadáveres y objetos que se pueden levantar.",
        after = function() if G.questMarks then G.questMarks.applyLootIcons() end end }),
      with(flag("lootGlow"), { label = "Marco en la ventana de saqueo", desc = "Borde dorado en el objeto que pide tu misión." }),
      with({ get = function() return DB.lootReminder == true end, set = function(v) DB.lootReminder = v end, default = false },
        { label = "Aviso para saquear", desc = "Al matar un bicho que suelta un objeto de tu misión (según la tabla de botín, con su %). Apagado: no suma nada a la pantalla." }),
      with(flag("rewards"), { label = "Recompensa recomendada", desc = "Marca con ✓ la mejor recompensa y con moneda la más cara." }),
      { header = "Qué entra en \"Para hacer ya\"" },
      with(subflag("check", "talents", true), { label = "Talentos sin gastar", desc = "Estimado: puede contar de menos con el Legado." }),
      with(subflag("check", "trainer", true), { label = "Habilidades nuevas", desc = "Hasta que visites a tu entrenador." }),
      with(subflag("check", "bags", true), { label = "Bolsas llenas", desc = "Con 2 lugares libres o menos." }),
      with(subflag("check", "durability", true), { label = "Equipo roto", desc = "Por debajo del 25%." }),
      with(subflag("check", "profs", true), { label = "Profesión al tope", desc = "Cuando toca entrenar el siguiente rango." }),
      with(subflag("check", "lockpick", true), { label = "Ganzúa para venenos", desc = "Pícaro 16-24: la misión del 20 pide 80." }),
    } },
    { name = "PvP", rows = {
      { label = "Alertas de enemigos", desc = "Cartel cuando aparece un jugador enemigo.", default = true, get = function() return pvp("alerts") end, set = function(v) setPvp("alerts", v) end },
      { label = "Sonido de alerta", desc = "Alarma junto con el cartel.", default = true, get = function() return pvp("sound") end, set = function(v) setPvp("sound", v) end },
      { label = "Avisar a mi grupo", desc = "Tus amigos con la Guía ven a quién viste.", default = true, get = function() return pvp("share") end, set = function(v) setPvp("share", v) end },
      { label = "Consejos contra cada clase", desc = "En el chat, qué hacer contra ese enemigo (pícaro).", default = true,
        get = function() return pvp("classTips") ~= false end, set = function(v) setPvp("classTips", v) end },
      { label = "Contar rivales", desc = "Quién te mató y a quién mataste.", default = true,
        get = function() return pvp("rivals") ~= false end, set = function(v) setPvp("rivals", v) end },
      { label = "Nombres de enemigos", desc = "Necesario para detectar sin seleccionar (tecla V).",
        get = function() return G.pvp and G.pvp.namesOn() end,
        set = function(v) if v and G.pvp then G.pvp.turnNamesOn() elseif SetCVar then pcall(SetCVar, "nameplateShowEnemies", "0") end end },
      { header = "Capas (layer)" },
      { label = "Ver capas del grupo", desc = "Si tus amigos con la Guía están en tu misma capa.", default = true,
        get = function() return pvp("layers") ~= false end, set = function(v) setPvp("layers", v) end },
      { label = "Avisar si alguien está en otra capa", desc = "Cartel cuando un amigo está en tu zona pero no lo ves.", default = true,
        get = function() return pvp("layerWarn") ~= false end, set = function(v) setPvp("layerWarn", v) end },
      { label = "Ayudar a otros a cambiar de capa", desc = "Si estás solo y tranquilo, invitás un momento a otro con la Guía.", default = true,
        get = function() return pvp("hopHelp") ~= false end, set = function(v) setPvp("hopHelp", v) end },
      { label = "Botón de cambiar capa", desc = "Botón en pantalla: clic para cambiar, arrastrar para mover.", default = true,
        get = function() return G.layerHop and G.layerHop.buttonShown() end, set = function(v) if G.layerHop then G.layerHop.toggleButton(v) end end },
    } },
    { name = "Medidor", rows = {
      { label = "Mostrar medidor", desc = "Ventanita con barras de daño, curación y más.", get = function() return G.meter and G.meter.isShown() end,
        set = function(v) if G.meter then G.meter.toggle(v) end end },
      { label = "Aparecer solo en combate", desc = "Se muestra al pelear y se va 25 s después.", default = false,
        get = function() return meter("auto") end, set = function(v) setMeter("auto", v) end },
      { label = "Atenuar fuera de combate", desc = "Se vuelve medio transparente entre peleas.", default = true,
        get = function() return meter("fade") ~= false end, set = function(v) setMeter("fade", v) end },
      { label = "Bloquear posición", desc = "Que no se mueva al hacer clic.", default = false, get = function() return meter("locked") end, set = function(v) setMeter("locked", v) end },
      { label = "Aviso de amenaza alta", desc = "En grupo, si estás por sacarle el enemigo al tanque.", default = true,
        get = function() return meter("threatWarn") ~= false end, set = function(v) setMeter("threatWarn", v) end },
      { label = "Filas visibles", desc = "Con una sola medición (con varias: hasta 4).", value = function() return tostring(meter("rows") or 6) end,
        step = function(d) setMeter("rows", math.max(3, math.min(10, (meter("rows") or 6) + d))) end, reset = function() setMeter("rows", nil) end },
    } },
    { name = "Objetos", rows = {
      with(flag("itemAdvice"), { label = "Consejo en el tooltip", desc = "Guardar, equipar, vender o subastar." }),
      { label = "Solo con Shift", desc = "El consejo aparece si mantenés Shift.", default = false,
        get = function() return DB.itemAdviceShift end, set = function(v) DB.itemAdviceShift = v end },
      with(flag("bagMarksOn"), { label = "Marcas en la bolsa", desc = "Letras en las esquinas de tus objetos (con Baganator).", after = bagRefresh }),
      { header = "Qué marcas mostrar" },
      with(subflag("bagMarks", "quest", true), { label = "Q  para una misión", desc = "Lo pide una misión que tenés.", after = bagRefresh }),
      with(subflag("bagMarks", "equip", true), { label = "+  mejora para equipar", desc = "Mejor que lo que tenés puesto.", after = bagRefresh }),
      with(subflag("bagMarks", "material", true), { label = "M  material tuyo", desc = "Para una de tus profesiones.", after = bagRefresh }),
      with(subflag("bagMarks", "later", true), { label = "^  mejora más adelante", desc = "Todavía no te lo podés poner.", after = bagRefresh }),
      with(subflag("bagMarks", "auction", true), { label = "$  para subastar", desc = "Vale más en la subasta.", after = bagRefresh }),
    } },
    { name = "Mazmorras", rows = {
      with(flag("dungeonCard"), { label = "Tarjeta de mazmorra", desc = "Jefes, misiones y botín para vos al entrar." }),
      with(flag("bossMsg"), { label = "Aviso de jefe derrotado", desc = "Texto en el centro de la pantalla." }),
      with(flag("runSummary"), { label = "Resumen al salir", desc = "Tiempo, XP, jefes y muertes en el chat." }),
    } },
  }

  -- Category chips (wrap to a second line on narrow windows).
  local chips, currentCat = {}, DB.settingsCat or 1
  local chipArea = CreateFrame("Frame", nil, settingsPanel)
  chipArea:SetPoint("TOPLEFT", 8, -28); chipArea:SetPoint("RIGHT", settingsPanel, "RIGHT", -8, 0); chipArea:SetHeight(20)

  local sScroll = CreateFrame("ScrollFrame", nil, settingsPanel, "UIPanelScrollFrameTemplate")
  sScroll:SetPoint("TOPLEFT", chipArea, "BOTTOMLEFT", -8, -4); sScroll:SetPoint("BOTTOMRIGHT", -24, 30)
  local body = CreateFrame("Frame", nil, sScroll)
  body:SetSize(1, 1)
  sScroll:SetScrollChild(body)
  if sScroll.SetClipsChildren then sScroll:SetClipsChildren(true) end

  local resetBtn = flatButton(settingsPanel, "Restablecer esta sección", 160, 18)
  resetBtn:SetPoint("BOTTOMLEFT", 8, 6)

  -- Switch control: a pill with a knob, green when on.
  local function makeSwitch(parent)
    local sw = CreateFrame("Button", nil, parent)
    sw:SetSize(30, 14)
    sw.track = sw:CreateTexture(nil, "BACKGROUND"); sw.track:SetAllPoints()
    sw.knob = sw:CreateTexture(nil, "ARTWORK"); sw.knob:SetSize(12, 12); sw.knob:SetColorTexture(0.95, 0.95, 0.95, 1)
    sw.setOn = function(self, on)
      self.track:SetColorTexture(on and 0.2 or 0.3, on and 0.65 or 0.3, on and 0.38 or 0.33, 1)
      self.knob:ClearAllPoints(); self.knob:SetPoint(on and "RIGHT" or "LEFT", self, on and "RIGHT" or "LEFT", on and -1 or 1, 0)
    end
    return sw
  end

  local pages = {}
  local function buildPage(ci)
    local page = CreateFrame("Frame", nil, body)
    page:SetPoint("TOPLEFT"); page:SetPoint("RIGHT", body, "RIGHT")
    page.widgets = {}
    local y = -4
    local width = math.max((sScroll:GetWidth() or 300), 200)
    for _, row in ipairs(CATEGORIES[ci].rows) do
      if row.header then
        local h = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h:SetPoint("TOPLEFT", 10, y - 6); h:SetText(row.header); h:SetTextColor(0.85, 0.47, 0.34)
        y = y - 22
      else
        local label = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("TOPLEFT", 12, y - 2); label:SetJustifyH("LEFT"); label:SetText(row.label)
        local desc = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        desc:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2); desc:SetJustifyH("LEFT")
        desc:SetWidth(width - 150); desc:SetText(row.desc or "")
        local w = { row = row }
        if row.step then
          local minus = flatButton(page, "-", 18, 16); minus:SetPoint("TOPRIGHT", -70, y)
          local plus = flatButton(page, "+", 18, 16); plus:SetPoint("TOPRIGHT", -10, y)
          w.valueText = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
          w.valueText:SetPoint("RIGHT", plus, "LEFT", -6, 0); w.valueText:SetWidth(36); w.valueText:SetJustifyH("CENTER")
          minus:SetScript("OnClick", function() row.step(-1); settingsPanel.refresh(); render() end)
          plus:SetScript("OnClick", function() row.step(1); settingsPanel.refresh(); render() end)
        elseif row.value then
          local b = flatButton(page, "", 130, 16); b:SetPoint("TOPRIGHT", -10, y)
          b:SetScript("OnClick", function() row.click(); settingsPanel.refresh(); render() end)
          w.choice = b
        else
          local sw = makeSwitch(page); sw:SetPoint("TOPRIGHT", -12, y - 1)
          sw:SetScript("OnClick", function()
            row.set(not row.get())
            if row.after then row.after() end
            settingsPanel.refresh(); render()
          end)
          w.switch = sw
        end
        page.widgets[#page.widgets + 1] = w
        local h = (label:GetStringHeight() or 12) + 2 + (row.desc and (desc:GetStringHeight() or 10) or 0)
        y = y - math.max(h, 18) - 10
      end
    end
    page.height = -y + 6
    page:SetHeight(page.height)
    return page
  end

  local function showCategory(ci)
    currentCat, DB.settingsCat = ci, ci
    for i, p in pairs(pages) do p:SetShown(i == ci) end
    if not pages[ci] then pages[ci] = buildPage(ci) end
    pages[ci]:Show()
    body:SetHeight(pages[ci].height)
    for i, c in ipairs(chips) do
      local on = i == ci
      c:SetBackdropColor(1, 1, 1, on and 0.16 or 0.05)
      c.label:SetTextColor(on and 1 or 0.7, on and 0.82 or 0.7, on and 0.3 or 0.7)
    end
    sScroll:SetVerticalScroll(0)
    settingsPanel.refresh()
  end

  local function layoutChips()
    local maxW = math.max((chipArea:GetWidth() or 300), 150)
    local x, line = 0, 0
    for _, c in ipairs(chips) do
      local w = c:GetWidth()
      if x > 0 and x + w > maxW then x, line = 0, line + 1 end
      c:ClearAllPoints(); c:SetPoint("TOPLEFT", chipArea, "TOPLEFT", x, -line * 20)
      x = x + w + 4
    end
    chipArea:SetHeight((line + 1) * 20)
  end
  for i, cat in ipairs(CATEGORIES) do
    local c = flatButton(chipArea, cat.name, 10, 18)
    c:SetWidth((c.label:GetStringWidth() or 40) + 16)
    c:SetScript("OnClick", function() showCategory(i) end)
    c:SetScript("OnLeave", function() showCategory(currentCat) end)
    chips[i] = c
  end
  chipArea:SetScript("OnSizeChanged", layoutChips)

  resetBtn:SetScript("OnClick", function()
    for _, row in ipairs(CATEGORIES[currentCat].rows) do
      if row.reset then row.reset()
      elseif row.set and row.default ~= nil then row.set(row.default); if row.after then row.after() end end
    end
    settingsPanel.refresh(); render()
  end)

  settingsPanel.refresh = function()
    local sw = sScroll:GetWidth()
    if sw and sw > 0 then body:SetWidth(sw) end
    local page = pages[currentCat]
    for _, w in ipairs(page and page.widgets or {}) do
      local row = w.row
      if w.valueText then w.valueText:SetText(row.value())
      elseif w.choice then w.choice.label:SetText(row.value())
      elseif w.switch then w.switch:setOn(row.get() and true or false) end
    end
    updateToggles()
  end
  settingsPanel:SetScript("OnShow", function() layoutChips(); showCategory(currentCat) end)

  specButton = flatButton(frame, "Cambiar rama  >", 120, 20)
  specButton:SetPoint("BOTTOMLEFT", 8, 5)
  specButton:SetScript("OnClick", cycleSpec)

  local grip = CreateFrame("Button", nil, frame)
  grip:SetSize(14, 14); grip:SetPoint("BOTTOMRIGHT", -3, 3)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
  grip:SetScript("OnMouseUp", function()
    frame:StopMovingOrSizing(); DB.w = math.floor(frame:GetWidth()); if sizeMode() == "big" then DB.h = math.floor(frame:GetHeight()) end; render()
  end)

  frame:SetScript("OnShow", render)

  -- Minimap button: click opens/closes the guide, drag moves it around the minimap.
  if Minimap then
    local mm = CreateFrame("Button", "GuiaForeverMinimapButton", Minimap)
    minimapButton = mm
    mm:SetSize(31, 31); mm:SetFrameStrata("MEDIUM"); mm:SetFrameLevel(8)
    mm:RegisterForClicks("AnyUp"); mm:RegisterForDrag("LeftButton")
    local icon = mm:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20); icon:SetPoint("CENTER", 0, 1); icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    local border = mm:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53); border:SetPoint("TOPLEFT"); border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    mm:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local function place()
      local a = math.rad(DB.minimapAngle or 200)
      mm:ClearAllPoints(); mm:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * 80, math.sin(a) * 80)
    end
    place()
    mm:SetScript("OnDragStart", function(self)
      self:SetScript("OnUpdate", function()
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        DB.minimapAngle = math.deg(math.atan2 and math.atan2(cy / scale - my, cx / scale - mx) or math.atan(cy / scale - my, cx / scale - mx))
        place()
      end)
    end)
    mm:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    mm:SetScript("OnClick", function() SlashCmdList.GUIAFOREVER("") end)
    mm:SetScript("OnEnter", function(self)
      if GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:SetText("Guía Forever"); GameTooltip:AddLine("Clic: abrir/cerrar. Arrastrá para moverlo.", 1, 1, 1); GameTooltip:Show() end
    end)
    mm:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    if DB.minimapHidden then mm:Hide() end
  end
  applySize()
  if DB.hidden then frame:Hide() end
end

-- ---------------------------------------------------------------- events
-- Which events change each tab. Ahora shows everything (bags, money, durability, rest); the others redraw only for
-- their own events and otherwise just refresh the header (XP/h, level bar).
local TAB_EVENTS = {
  [2] = { QUEST_LOG_UPDATE = true, QUEST_TURNED_IN = true, PLAYER_LEVEL_UP = true, PLAYER_XP_UPDATE = true, ZONE_CHANGED_NEW_AREA = true,
    PLAYER_ENTERING_WORLD = true, CHAT_MSG_ADDON = true, GROUP_ROSTER_UPDATE = true, PARTY_MEMBERS_CHANGED = true },
  [3] = { QUEST_LOG_UPDATE = true, QUEST_TURNED_IN = true, PLAYER_LEVEL_UP = true, ZONE_CHANGED_NEW_AREA = true, PLAYER_ENTERING_WORLD = true,
    PLAYER_REGEN_ENABLED = true },
  [4] = { QUEST_LOG_UPDATE = true, PLAYER_LEVEL_UP = true, PLAYER_XP_UPDATE = true, ZONE_CHANGED_NEW_AREA = true, PLAYER_ENTERING_WORLD = true,
    CHAT_MSG_ADDON = true, GROUP_ROSTER_UPDATE = true, PARTY_MEMBERS_CHANGED = true, PLAYER_DEAD = true },
  [5] = { PLAYER_LEVEL_UP = true, SKILL_LINES_CHANGED = true, CHARACTER_POINTS_CHANGED = true, TRAINER_SHOW = true, PLAYER_ENTERING_WORLD = true },
  [6] = { PLAYER_LEVEL_UP = true, ZONE_CHANGED_NEW_AREA = true, PLAYER_ENTERING_WORLD = true, SKILL_LINES_CHANGED = true,
    QUEST_LOG_UPDATE = true, QUEST_TURNED_IN = true },
}
local pending, pendingFull = false, false
local function queueRender(event)
  local only = TAB_EVENTS[DB and DB.tab or 1]
  if not event or not only or only[event] then pendingFull = true end
  if pending then return end
  pending = true
  C_Timer.After(0.5, function()
    pending = false
    if pendingFull then pendingFull = false; render()
    elseif frame and frame:IsShown() then pcall(updateHeader) end
  end)
end

local function levelUpToast(level)
  local cd = G.classes[select(2, UnitClass("player"))]
  local msgs = {}
  for _, m in ipairs(cd and cd.milestones or {}) do if m.level == level then msgs[#msgs + 1] = m.text end end
  for _, m in ipairs(G.milestones) do if m.level == level then msgs[#msgs + 1] = m.text end end
  if #msgs > 0 then
    local line = "Nivel " .. level .. ": " .. table.concat(msgs, " · ")
    print(C.title .. "Guía Forever|r " .. line)
    if UIErrorsFrame then UIErrorsFrame:AddMessage(line, 1, 0.82, 0) end
  end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
local lastQuestXP, lastQuestAt = 0, 0
ev:SetScript("OnEvent", function(self, event, arg1, arg2, arg3, arg4)
  if event == "ADDON_LOADED" and arg1 == ADDON then
    GuiaForeverDB = GuiaForeverDB or {}
    DB = GuiaForeverDB
    -- Remove data left by earlier test builds.
    for _, k in ipairs({ "combatProbe", "liveProbe", "sessionDebug", "diag", "dungeonLog", "layerLog", "lastError" }) do DB[k] = nil end
    if DB.pvp then for _, k in ipairs({ "stats", "log", "testMobs", "honorLog", "sosProbe" }) do DB.pvp[k] = nil end end
    createUI()
    -- A file the client did not load (update copied in with only /reload, or a half-copied folder)
    -- leaves its tables nil and whole sections empty: say so instead of failing quietly.
    local expected = { { "zones", "Data.lua" }, { "classes", "DataClasses.lua" }, { "professions", "DataProfessions.lua" },
      { "questGuides", "DataQuests.lua" }, { "itemUses", "DataItems.lua" },
      { "importantQuests", "DataImportant.lua" }, { "questDropDB", "DataQuestDrops.lua" }, { "cityPins", "DataCity.lua" }, { "notify", "Notify.lua" }, { "pvp", "PvP.lua" },
      { "items", "Rewards.lua" }, { "meter", "Meter.lua" }, { "layerHop", "LayerHop.lua" }, { "dungeon", "Dungeon.lua" }, { "questMarks", "QuestMarks.lua" }, { "autoQuest", "AutoQuest.lua" },
      { "cityMap", "CityPins.lua" }, { "roadmap", "Roadmap.lua" }, { "companion", "Companion.lua" } }
    local missing = {}
    for _, e in ipairs(expected) do if G[e[1]] == nil then missing[#missing + 1] = e[2] end end
    if #missing > 0 then
      C_Timer.After(5, function()
        msg("|cffff4040faltan archivos sin cargar:|r " .. table.concat(missing, ", ")
          .. ". Cerrá y abrí el juego (con /reload no alcanza). Si sigue, borrá la carpeta GuiaForever y copiala entera de nuevo.")
      end)
    end
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA", "QUEST_LOG_UPDATE", "SKILL_LINES_CHANGED",
      "PLAYER_UPDATE_RESTING", "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "QUEST_TURNED_IN", "CHAT_MSG_COMBAT_XP_GAIN", "PLAYER_MONEY", "PLAYER_LOGOUT",
      "CHAT_MSG_ADDON", "GROUP_ROSTER_UPDATE", "PARTY_MEMBERS_CHANGED", "TRAINER_SHOW", "BAG_UPDATE", "UPDATE_INVENTORY_DURABILITY",
      "CHARACTER_POINTS_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_DEAD" }) do
      try(self.RegisterEvent, self, e)
    end
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then try(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
    elseif RegisterAddonMessagePrefix then try(RegisterAddonMessagePrefix, PREFIX) end
    C_Timer.NewTicker(30, function() sendStats() end)
    return
  end
  if not DB then return end
  if event == "PLAYER_ENTERING_WORLD" then
    if not S.start then sessionStart() end
  elseif event == "PLAYER_XP_UPDATE" then
    onXPChanged()
  elseif event == "PLAYER_REGEN_ENABLED" then
    if S.pendingXP then onXPChanged() end
  elseif event == "PLAYER_LEVEL_UP" then
    onXPChanged(); onLevelUp(arg1); levelUpToast(arg1)
  elseif event == "QUEST_TURNED_IN" then
    local xp = tonumber(arg2) or 0
    S.questXP = S.questXP + xp
    lastQuestXP, lastQuestAt = xp, GetTime()
  elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
    local xp = firstNumber(arg1)
    -- Skip the line some clients print for quest XP right after a turn-in.
    if xp and not (xp == lastQuestXP and GetTime() - lastQuestAt < 2) then
      S.kills = S.kills + 1
      S.killXP = S.killXP + xp
    elseif not xp then
      S.kills = S.kills + 1 -- message hidden: still count the kill
    end
  elseif event == "PLAYER_DEAD" then
    S.deaths = (S.deaths or 0) + 1; sendStats(true)
  elseif event == "PLAYER_LOGOUT" then
    onLogout(); return
  elseif event == "CHAT_MSG_ADDON" then
    if arg1 ~= PREFIX then return end
    onAddonMessage(arg1, arg2, arg3, arg4)
  elseif event == "GROUP_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" then
    for name in pairs(partyData) do
      local still = false
      for _, u in ipairs(partyUnits()) do if UnitName(u) == name then still = true end end
      if not still then partyData[name] = nil end
    end
    for name in pairs(partyStats) do
      local still = false
      for _, u in ipairs(partyUnits()) do if UnitName(u) == name then still = true end end
      if not still then partyStats[name] = nil end
    end
    if inGroup() then sendAddon("R"); broadcastQuests(); sendStats(true) end
  elseif event == "TRAINER_SHOW" then
    local tradeskill = IsTradeskillTrainer and try(IsTradeskillTrainer)
    if not tradeskill then charDB().trainedLevel = UnitLevel("player") end
  elseif event == "QUEST_LOG_UPDATE" then
    broadcastQuests()
  end
  queueRender(event)
end)

-- Shared helpers for the feature modules (Notify.lua, PvP.lua, Rewards.lua).
G.core = {
  try = try, C = C, L = L, H = H, B = B, msg = msg, each = each,
  db = function() return DB end, charDB = charDB, render = queueRender, renderNow = function() render() end,
  inGroup = inGroup, sendAddon = sendAddon, partyUnits = partyUnits,
  questEntries = questEntries, questObjectives = questObjectives,
  sessionXP = function() return S.xp or 0 end, factionOk = factionOk, actionLink = actionLink,
  partyStats = function() return partyStats end,
}

local msg_ = msg
SLASH_GUIAFOREVER1 = "/guia"
SlashCmdList.GUIAFOREVER = function(msg)
  msg = (msg or ""):lower()
  if msg == "ciudad" then
    DB.cityPins = (DB.cityPins == false)
    if G.cityMap then G.cityMap.refresh() end
    msg_("Servicios en el mapa: " .. (DB.cityPins and "prendidos (abrí el mapa grande con M)" or "apagados") .. ".")
    return
  end
  if msg == "medidor" then if G.meter then G.meter.toggle() end; return end
  if msg == "marcas" then if G.questMarks then G.questMarks.diagnose() end; return end
  local qdbID = msg:match("^qdb%s*(%d*)$")
  if qdbID then if G.qdb and G.qdb.diagnose then G.qdb.diagnose(tonumber(qdbID)) end; return end
  local goal = msg:match("^meta%s*(%S*)")
  if goal then
    local n = tonumber(goal)
    if goal == "no" then DB.goalLevel = nil; msg_("Meta borrada.")
    elseif n and n >= 2 and n <= 60 then DB.goalLevel = math.floor(n); msg_("Meta: nivel " .. DB.goalLevel .. ". Mirala en la pestaña Ahora.")
    else msg_("Usá /guia meta 20 (el nivel al que querés llegar) o /guia meta no.") end
    render()
    return
  end
  if msg == "foto" then if G.companion then G.companion.snapshot() end; return end
  if msg:match("^capa") then if G.layerHop then G.layerHop.command(msg:match("^capa%s*(.*)$") or "") end; return end
  if msg == "sos" then if G.pvp and G.pvp.sos then G.pvp.sos() end; return end
  -- /guia ir 36.1 44.9 -> waypoint on your current map; plain /guia ir -> last SOS from a friend.
  local wx, wy = msg:match("^ir%s+([%d%.]+)[%s,]+([%d%.]+)")
  if wx then
    local mapID = C_Map and try(C_Map.GetBestMapForUnit, "player")
    wx, wy = tonumber(wx), tonumber(wy)
    if wx and wy and G.setWaypoint(mapID, wx / 100, wy / 100) then
      msg_("Marcador puesto en " .. wx .. ", " .. wy .. ". Seguí la flecha.")
    end
    return
  end
  if msg == "ir" then if G.pvp and G.pvp.goToSOS then G.pvp.goToSOS() end; return end
  if msg == "rival" then if G.pvp and G.pvp.markRival then G.pvp.markRival() end; return end
  if msg == "ajustes" or msg == "config" then
    if not frame:IsShown() then frame:Show(); DB.hidden = false end
    settingsPanel:Show(); settingsPanel.refresh(); return
  elseif msg:match("^avisos") then
    if G.notify then G.notify.command(msg:match("^avisos%s*(.*)$") or "") end
    return
  elseif msg:match("^pvp") then
    if G.pvp and G.pvp.command then G.pvp.command(msg:match("^pvp%s*(.*)$") or "") end
    return
  elseif msg == "reset" then
    DB.pos, DB.w, DB.h, DB.collapsed, DB.size = nil, nil, nil, nil, nil
    frame:ClearAllPoints(); frame:SetPoint("RIGHT", UIParent, "RIGHT", -40, 60); applySize()
  elseif msg:match("^font") then
    DB.fontSize = math.max(9, math.min(18, tonumber(msg:match("(%d+)")) or 12))
    render()
  elseif msg:match("^alpha") then
    local a = tonumber(msg:match("([%d%.]+)")) or 0.85
    DB.alpha = math.max(0.2, math.min(1, a)); frame:SetBackdropColor(0.06, 0.06, 0.08, DB.alpha)
  else
    if frame:IsShown() then frame:Hide(); DB.hidden = true else frame:Show(); DB.hidden = false end
  end
  render()
end
