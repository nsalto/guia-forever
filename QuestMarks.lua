-- Guía Forever: our own mark over quest mobs (small sword + "2/6" on the nameplate), shown only when no
-- nameplate addon marks them (ThreatPlates does it from the game's quest lines). Sources, all facts, never
-- name guesses: the unit's tooltip quest lines, the client's "related to an active quest" check, the mob
-- name inside a kill objective, the quest-item drop tables (DataQuestDrops.lua) and drops seen by you or
-- a party member with the Guía. Ground objects cannot be marked (no API).
local G = GuiaForever

local marks = {}     -- nameplate frame -> mark frame
local cache = {}     -- guid -> { text = "2/6" or "" or false, at = time }
local CACHE_SECS = 2

local function db() return G.core and G.core.db() end
local function enabled() local d = db(); return d and d.questMarks ~= false end
local function plain(v) if issecretvalue and issecretvalue(v) then return nil end return v end
local function try(fn, ...) if type(fn) ~= "function" then return end local ok, a, b = pcall(fn, ...); if ok then return a, b end end
-- Our sword shows with or without ThreatPlates (it hangs from the base nameplate, which ThreatPlates keeps);
-- while it is on, syncThreatPlates turns ThreatPlates' own quest icon off so there is only one mark.
local function marksOn() return enabled() end

-- An objective still to do: not flagged finished and its count not full (the flag can be hidden or lag).
local function open(o)
  if plain(o.done) then return false end
  return not (o.have and o.need and o.have >= o.need)
end

-- Among several matching objectives, a counted one beats an uncounted one ("" = unknown count).
local function better(cur, new) if cur == nil or (cur == "" and new ~= "") then return new end return cur end

-- 1) Tooltip quest lines (same data nameplate addons use on clients with tooltip line types).
local function fromTooltip(unit)
  if not (C_TooltipInfo and C_TooltipInfo.GetUnit and Enum and Enum.TooltipDataLineType) then return nil end
  local data = try(C_TooltipInfo.GetUnit, unit)
  if type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
  local T = Enum.TooltipDataLineType
  local me = UnitName("player")
  -- In a group the tooltip also lists your mates' quests: only titles in your own log count.
  -- Titles are compared without colour codes, level tags or case; solo, every quest line is yours.
  local function norm(t) return (t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s*%[[^%]]*%]%s*", ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()) end
  local grouped = IsInGroup and plain(IsInGroup()) and true or false
  local own = {}
  if grouped and G.core then for _, e in ipairs(G.core.questEntries()) do if type(e.title) == "string" then own[norm(e.title)] = true end end end
  local mine, sawQuest, best = true, false, nil
  for _, line in ipairs(data.lines) do
    local text = plain(line.leftText)
    if type(text) == "string" then
      if line.type == T.QuestPlayer then mine = (text == me)
      elseif line.type == T.QuestTitle then mine = not grouped or next(own) == nil or own[norm(text)] or false; sawQuest = sawQuest or mine
      elseif line.type == T.QuestObjective and mine then
        sawQuest = true
        local a, b = text:match("(%d+)%s*/%s*(%d+)")
        a, b = tonumber(a), tonumber(b)
        if a and b and a < b then best = better(best, a .. "/" .. b)
        elseif not a and not text:find("%(Completado%)") and not text:find("%(Complete%)") then best = better(best, "") end
      end
    end
  end
  if best then return best end
  if sawQuest then return false end -- quest unit, but your objectives on it are done
  return nil
end

-- 3) The mob name appears in an unfinished objective ("Grisoso cardo asesinado: 2/4").
local function fromObjectives(unit)
  local name = plain(UnitName(unit))
  if type(name) ~= "string" or name == "" or not G.core then return nil end
  local best
  for _, e in ipairs(G.core.questEntries()) do
    if not e.complete then
      for _, o in ipairs(G.core.questObjectives(e)) do
        local t = plain(o.text)
        if open(o) and type(t) == "string" and t:find(name, 1, true) then
          best = better(best, (o.have and o.need) and (o.have .. "/" .. o.need) or "")
        end
      end
    end
  end
  return best
end

-- Learned drops: DB.questDrops[npcID] = { [item name] = true }.
local function drops() local d = db(); if not d then return {} end d.questDrops = d.questDrops or {}; return d.questDrops end
local function npcID(guid)
  if type(guid) ~= "string" then return nil end
  local kind, _, _, _, _, id = strsplit("-", guid)
  if kind ~= "Creature" then return nil end
  return tonumber(id)
end

-- Unfinished objective whose text names this item: progress "2/6" (or "").
local function objectiveFor(itemName)
  if not G.core then return nil end
  local best
  for _, e in ipairs(G.core.questEntries()) do
    if not e.complete then
      for _, o in ipairs(G.core.questObjectives(e)) do
        local t = plain(o.text)
        if open(o) and type(t) == "string" and t:find(itemName, 1, true) then
          best = better(best, (o.have and o.need) and (o.have .. "/" .. o.need) or "")
        end
      end
    end
  end
  return best
end

-- 2b) Known drop tables (DataQuestDrops.lua): this creature drops an item one of your
-- quests still needs. Returns progress, item name, drop chance.
local function itemName(id)
  local n = C_Item and C_Item.GetItemNameByID and try(C_Item.GetItemNameByID, id)
  if not n and GetItemInfo then n = try(GetItemInfo, id) end
  if not n and C_Item and C_Item.RequestLoadItemDataByID then try(C_Item.RequestLoadItemDataByID, id) end
  return plain(n)
end

local function fromQuestDB(unit)
  local dbq = G.questDropDB
  local id = dbq and npcID(plain(UnitGUID(unit)))
  if not id or not G.core then return nil end
  local best, bestItem, bestChance
  for _, e in ipairs(G.core.questEntries()) do
    local items = not e.complete and e.id and dbq[e.id]
    if items then
      local objs
      for itemID, list in pairs(items) do
        for i = 1, #list, 2 do
          if list[i] == id then
            objs = objs or G.core.questObjectives(e)
            local name = itemName(itemID)
            local p
            if name then
              for _, o in ipairs(objs) do
                local t = plain(o.text)
                if open(o) and type(t) == "string" and t:find(name, 1, true) then
                  p = (o.have and o.need) and (o.have .. "/" .. o.need) or ""
                end
              end
            else
              -- Item name not cached yet: fine when the quest has a single open item objective.
              local only, n = nil, 0
              for _, o in ipairs(objs) do if open(o) and o.type == "item" then n = n + 1; only = o end end
              if n == 1 then p = (only.have and only.need) and (only.have .. "/" .. only.need) or "" end
            end
            if p and better(best, p) ~= best then best, bestItem, bestChance = p, name, list[i + 1] end
            break
          end
        end
      end
    end
  end
  return best, bestItem, bestChance
end

local function fromDrops(unit)
  local id = npcID(plain(UnitGUID(unit)))
  local known = id and drops()[id]
  if not known then return nil end
  local best
  for itemName in pairs(known) do
    local p = objectiveFor(itemName)
    if p then best = better(best, p) end
  end
  return best
end

-- Progress text for a quest mob ("2/6", or "" when the count is unknown); nil/false when not one.
local function questProgress(unit)
  if not UnitExists(unit) or UnitIsPlayer(unit) or plain(UnitIsDead(unit)) then return nil end
  if UnitCanAttack and plain(UnitCanAttack("player", unit)) == false then return nil end
  local guid = plain(UnitGUID(unit))
  local c = guid and cache[guid]
  if c and GetTime() - c.at < CACHE_SECS then return c.text, c.kind end
  local text = fromTooltip(unit)
  local tipDone = text == false -- the tooltip quest on it is done, but another quest may still need it
  if text == false then text = nil end
  if text == nil and not tipDone and C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest then
    if plain(try(C_QuestLog.UnitIsRelatedToActiveQuest, unit)) == true then text = fromObjectives(unit) or "" end
  end
  if text == nil then text = fromObjectives(unit) end
  local kind = "kill"
  -- The tooltip and the "related to a quest" check also flag mobs you only loot (scales, fangs...): when the mob's
  -- name is in no objective and it is known to drop an item you still need, it is a drop mob, not a kill target.
  if text and not fromObjectives(unit) and (fromQuestDB(unit) ~= nil or fromDrops(unit) ~= nil) then kind = "drop" end
  if text == nil then text = fromQuestDB(unit); if text ~= nil then kind = "drop" end end
  if text == nil then text = fromDrops(unit); if text ~= nil then kind = "drop" end end
  if text == nil and tipDone then text = false end
  if text == nil and c then text, kind = c.text, c.kind end -- hidden right now (combat): keep the last answer
  if guid then cache[guid] = { text = text, kind = kind, at = GetTime() } end
  return text, kind
end

-- The mark: a small dark pill over the nameplate. Icon and border say why the mob matters (red sword: kill it,
-- gold bag: it drops a quest item), the count shows your progress and a thin bar under it fills up, yellow to
-- green. Your current target's pill is drawn bigger.
local KIND = {
  kill = { icon = "Interface\\CURSOR\\Attack", r = 1, g = 0.36, b = 0.28 },
  drop = { icon = "Interface\\Icons\\INV_Misc_Bag_10", r = 1, g = 0.8, b = 0.2 },
}
local WHITE = "Interface\\Buttons\\WHITE8x8"

local function solid(parent, layer, r, g, b, a)
  local t = parent:CreateTexture(nil, layer)
  t:SetTexture(WHITE)
  t:SetVertexColor(r, g, b, a)
  return t
end

local function markFor(plate)
  local m = marks[plate]
  if m then return m end
  local ok
  ok, m = pcall(CreateFrame, "Frame", nil, plate)
  if not ok or not m then return nil end
  m:SetSize(40, 20)
  m:SetPoint("BOTTOM", plate, "TOP", 0, 4)
  m:SetFrameStrata("HIGH")
  -- border: a colored rectangle behind a slightly smaller dark one
  m.border = solid(m, "BACKGROUND", 1, 1, 1, 0.9)
  m.border:SetAllPoints()
  m.bg = solid(m, "BORDER", 0.05, 0.05, 0.07, 0.85)
  m.bg:SetPoint("TOPLEFT", 1, -1); m.bg:SetPoint("BOTTOMRIGHT", -1, 1)
  m.icon = m:CreateTexture(nil, "ARTWORK")
  m.icon:SetSize(16, 16)
  m.icon:SetPoint("LEFT", 2, 1)
  m.text = m:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  m.text:SetPoint("LEFT", m.icon, "RIGHT", 3, 1)
  local font, size = m.text:GetFont()
  if font then m.text:SetFont(font, size or 10, "OUTLINE") end
  m.barBg = solid(m, "ARTWORK", 1, 1, 1, 0.12)
  m.barBg:SetHeight(2)
  m.barBg:SetPoint("BOTTOMLEFT", 2, 2); m.barBg:SetPoint("BOTTOMRIGHT", -2, 2)
  m.bar = solid(m, "OVERLAY", 1, 0.82, 0, 1)
  m.bar:SetHeight(2)
  m.bar:SetPoint("BOTTOMLEFT", m.barBg, "BOTTOMLEFT", 0, 0)
  marks[plate] = m
  return m
end

local function paint(m, unit, text, kind)
  local k = KIND[kind] or KIND.kill
  m.icon:SetTexture(k.icon)
  if kind == "drop" then m.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) else m.icon:SetTexCoord(0, 1, 0, 1) end
  m.border:SetVertexColor(k.r, k.g, k.b, 0.9)
  local have, need = (text or ""):match("(%d+)%s*/%s*(%d+)")
  have, need = tonumber(have), tonumber(need)
  local width = 22 + (text ~= "" and (m.text:GetStringWidth() + 6) or 0)
  m:SetWidth(width)
  if have and need and need > 0 then
    local f = math.min(1, have / need)
    -- yellow (just started) to green (almost done)
    m.bar:SetVertexColor(1 - 0.7 * f, 0.82 + 0.1 * f, 0.1 + 0.3 * f, 1)
    m.text:SetTextColor(1 - 0.6 * f, 0.9, 0.3 + 0.3 * f)
    m.bar:SetWidth(math.max(1, (width - 4) * f))
    m.bar:Show(); m.barBg:Show()
  else
    m.text:SetTextColor(1, 0.9, 0.6)
    m.bar:Hide(); m.barBg:Hide()
  end
  local isTarget = UnitIsUnit and plain(UnitIsUnit(unit, "target")) == true
  m:SetScale(isTarget and 1.25 or 1)
  m:SetAlpha(isTarget and 1 or 0.9)
end

local function update(unit)
  local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and try(C_NamePlate.GetNamePlateForUnit, unit)
  if not plate then return end
  local text, kind
  if marksOn() then text, kind = questProgress(unit) end
  local m = marks[plate] or (text and markFor(plate))
  if not m then return end
  if text then
    m.text:SetText(text)
    paint(m, unit, text, kind)
    m:Show()
  else
    m:Hide()
  end
end

local lastError
local function safeUpdate(unit)
  local ok, err = pcall(update, unit)
  if not ok then lastError = tostring(err) end
end

local function updateAll()
  for i = 1, 40 do
    local u = "nameplate" .. i
    if UnitExists(u) then safeUpdate(u) end
  end
end

-- /guia marcas: why your target is (or is not) marked. Prints what each check sees.
-- ThreatPlates draws its own "!" + bag + progress over the same mobs. Our sword only shows without
-- ThreatPlates; if an earlier build hid its quest icon (DB.tpIconOff), it is given back here.
local function threatPlatesProfile()
  if not (ThreatPlatesDB and LibStub) then return nil end
  local ok, AceDB = pcall(LibStub, "AceDB-3.0", true)
  if not ok or type(AceDB) ~= "table" or type(AceDB.db_registry) ~= "table" then return nil end
  for adb in pairs(AceDB.db_registry) do
    if type(adb) == "table" and adb.sv == ThreatPlatesDB and type(adb.profile) == "table" then return adb.profile end
  end
end

-- Returns true once ThreatPlates was found and set (the ticker retries until then).
local function syncThreatPlates()
  local profile, d = threatPlatesProfile(), db()
  local qw = profile and profile.questWidget
  if type(qw) ~= "table" or not d then return false end
  if marksOn() then
    if qw.ModeIcon ~= false then
      qw.ModeIcon = false; d.tpIconOff = true
      if G.core then G.core.msg("Apagué el ícono de misión de ThreatPlates: la marca de misión ahora es solo la espadita.") end
    end
  elseif d.tpIconOff then
    qw.ModeIcon = true; d.tpIconOff = nil
  end
  return true
end

-- The game's own "interact" icons: a hand/bag over lootable corpses and over objects you can use
-- (ground quest objects included). Only on clients that have these settings.
-- Arc 2 = all around you (not only in front); range 15 yd; the nameplate on the object is what our sparkle hangs from.
local LOOT_CVARS = { SoftTargetIconGameObject = "1", SoftTargetIconInteract = "1", SoftTargetInteract = "3",
  SoftTargetInteractArc = "2", SoftTargetInteractRange = "15", SoftTargetNameplateInteract = "1" }
local LOOT_OFF = { SoftTargetInteractArc = "0", SoftTargetInteractRange = "10" } -- the game's defaults when turned off
local function cvarExists(name)
  if C_CVar and C_CVar.GetCVar then return C_CVar.GetCVar(name) ~= nil end
  return GetCVar and GetCVar(name) ~= nil
end

local function diagnose()
  local msg = G.core and G.core.msg or print
  local u = "target"
  if not UnitExists(u) then msg("Seleccioná un bicho y volvé a escribir /guia marcas.") return end
  local guid = plain(UnitGUID(u))
  msg("Marcas: " .. tostring(plain(UnitName(u))) .. " (npc " .. tostring(npcID(guid)) .. ")")
  local plate = C_NamePlate and try(C_NamePlate.GetNamePlateForUnit, u)
  msg("  barra de vida visible: " .. (plate and "sí" or "NO (acercate o apretá V)"))
  local tp = threatPlatesProfile()
  local qw = tp and type(tp.questWidget) == "table" and tp.questWidget
  msg("  ThreatPlates: " .. (not tp and "no encontrado" or (qw and qw.ModeIcon == false and "ícono de misión apagado" or "ícono de misión PRENDIDO")))
  local lines = {}
  if C_TooltipInfo and C_TooltipInfo.GetUnit then
    local data = try(C_TooltipInfo.GetUnit, u)
    if type(data) == "table" and type(data.lines) == "table" then
      for i, line in ipairs(data.lines) do
        if i > 1 then lines[#lines + 1] = tostring(line.type) .. "=" .. tostring(plain(line.leftText)) end
      end
    else lines[1] = "sin datos" end
  else lines[1] = "función no disponible" end
  msg("  cuadro del bicho: " .. table.concat(lines, " | "))
  local related = C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest and try(C_QuestLog.UnitIsRelatedToActiveQuest, u)
  msg("  el juego dice relacionado a misión: " .. tostring(plain(related)))
  msg("  por cuadro: " .. tostring(fromTooltip(u)) .. " · por nombre: " .. tostring(fromObjectives(u))
    .. " · por tabla de botín: " .. tostring((fromQuestDB(u))) .. " · por loot aprendido: " .. tostring(fromDrops(u)))
  local n = 0
  for _ in pairs(drops()) do n = n + 1 end
  local iconsOk = false
  for name in pairs(LOOT_CVARS) do if cvarExists(name) then iconsOk = true end end
  msg("  íconos de saqueo del juego: " .. (iconsOk and "disponibles" or "este cliente no los tiene"))
  msg("  tipos de bicho aprendidos: " .. n .. (lastError and (" · último error: " .. lastError) or ""))
end

-- ---------------------------------------------------------------- loot helpers
-- What a quest mob drops for you: item name (+ drop chance) and progress, from the drop tables or
-- from a drop already seen. Never from the mob's name.
local function dropHint(unit)
  local p, name, chance = fromQuestDB(unit)
  if p and name then return name .. (chance and (" ~" .. chance .. "%") or ""), p end
  local id = npcID(plain(UnitGUID(unit)))
  local known = id and drops()[id]
  if known then
    for itemName in pairs(known) do
      local p = objectiveFor(itemName)
      if p then return itemName, p end
    end
  end
end

local function applyLootIcons()
  if InCombatLockdown and InCombatLockdown() then return false end
  local d = db()
  local on = d and d.lootIcons ~= false
  local supported = false
  for name, value in pairs(LOOT_CVARS) do
    if cvarExists(name) then
      supported = true
      if on then pcall(SetCVar, name, value)
      elseif name ~= "SoftTargetInteract" then pcall(SetCVar, name, LOOT_OFF[name] or "0") end
    end
  end
  return supported
end

-- Sparkle on usable objects (quest objects, chests, herbs...): the game gives the object you can use right now a
-- nameplate (SoftTargetNameplateInteract); we hang a soft gold glow with two slowly turning stars on it. Mobs and
-- players never get it. Nothing shows on clients that give objects no nameplate.
local sparkles = {}
local function sparkleFor(plate)
  if sparkles[plate] then return sparkles[plate] end
  local ok, f = pcall(CreateFrame, "Frame", nil, plate)
  if not ok or not f then return end
  f:SetSize(64, 64); f:SetPoint("CENTER", plate, "CENTER", 0, 0)
  f:SetFrameLevel((plate:GetFrameLevel() or 0) + 6)
  local function star(size, alpha, dir, secs)
    local t = f:CreateTexture(nil, "OVERLAY")
    t:SetTexture("Interface\\Cooldown\\star4"); t:SetBlendMode("ADD")
    t:SetVertexColor(1, 0.85, 0.35, alpha); t:SetSize(size, size); t:SetPoint("CENTER")
    local g = t:CreateAnimationGroup(); g:SetLooping("REPEAT")
    local r = g:CreateAnimation("Rotation"); r:SetDegrees(360 * dir); r:SetDuration(secs)
    g:Play()
    return t
  end
  star(60, 0.55, 1, 6); star(38, 0.8, -1, 4)
  local pulse = f:CreateAnimationGroup(); pulse:SetLooping("BOUNCE")
  local a = pulse:CreateAnimation("Alpha"); a:SetFromAlpha(1); a:SetToAlpha(0.35); a:SetDuration(0.9)
  pulse:Play()
  sparkles[plate] = f
  return f
end
local function sparkleUpdate(unit, removed)
  local plate = C_NamePlate and try(C_NamePlate.GetNamePlateForUnit, unit)
  if not plate then return end
  local d = db()
  local guid = not removed and plain(UnitGUID(unit))
  local object = type(guid) == "string" and guid:find("^GameObject") ~= nil
  if object and d and d.lootIcons ~= false and d.objectSparkle ~= false then
    local f = sparkleFor(plate); if f then f:Show() end
  elseif sparkles[plate] then sparkles[plate]:Hide() end
end

-- Kill reminder: your target just died and it may carry an item a quest of yours needs.
local lastTarget = { guid = nil, dead = false }
local function checkTargetDeath()
  local d = db()
  if not (d and d.lootReminder == true) or not UnitExists("target") then lastTarget.guid = nil; return end
  local guid = plain(UnitGUID("target"))
  local dead = plain(UnitIsDead("target")) and true or false
  if guid ~= lastTarget.guid then lastTarget.guid, lastTarget.dead = guid, dead; return end
  if dead and not lastTarget.dead then
    local itemName, p = dropHint("target")
    if itemName and UIErrorsFrame then
      UIErrorsFrame:AddMessage("¡Saqueá a " .. tostring(plain(UnitName("target"))) .. "! Puede tener " .. itemName .. " (" .. p .. ")", 0.3, 0.87, 0.5)
    end
  end
  lastTarget.dead = dead
end

-- Corpse tooltip: "Guía: puede tener ... (saqueálo)".
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
    local d = db()
    if not (d and d.lootReminder == true and tooltip and tooltip.GetUnit and tooltip.AddLine) then return end
    local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
    unit = ok and plain(unit)
    if type(unit) ~= "string" or not plain(UnitIsDead(unit)) or UnitIsPlayer(unit) then return end
    local okH, itemName, p = pcall(dropHint, unit)
    if okH and itemName then tooltip:AddLine("Guía: puede tener " .. itemName .. " (" .. p .. "): saqueálo", 0.3, 0.87, 0.5, true) end
  end)
end

-- Learn from loot: an item an unfinished objective asks for, dropped by a creature.
local function learn(id, itemName, share)
  if not (id and itemName) then return end
  local d = drops()
  d[id] = d[id] or {}
  if d[id][itemName] then return end
  d[id][itemName] = true
  wipe(cache)
  if share and G.core and G.core.inGroup() then G.core.sendAddon("D" .. id .. "," .. itemName:gsub(",", " ")) end
end

local function onLoot()
  if not (GetNumLootItems and GetLootSlotLink) then return end
  for slot = 1, (try(GetNumLootItems) or 0) do
    local link = plain(try(GetLootSlotLink, slot))
    local itemName = type(link) == "string" and link:match("%[(.-)%]")
    if itemName and objectiveFor(itemName) then
      local guid = GetLootSourceInfo and plain(try(GetLootSourceInfo, slot))
      if not guid then guid = plain(UnitGUID("target")) end
      local id = npcID(guid)
      learn(id, itemName, true)
    end
  end
end

-- Loot window: a gold glowing frame around the items an unfinished objective of yours asks for.
-- Works with the classic window (LootButton1..N) and the modern one (LootFrame.ScrollBox).
local glows = {}
local function glow(button, on)
  local g = glows[button]
  if not g and on then
    g = button:CreateTexture(nil, "OVERLAY")
    g:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    g:SetBlendMode("ADD")
    g:SetVertexColor(1, 0.82, 0)
    local icon = button.icon or button.Icon or (button.Item and (button.Item.icon or button.Item.Icon)) or button
    g:SetPoint("CENTER", icon, "CENTER", 0, 0)
    local w = (icon.GetWidth and icon:GetWidth()) or 36
    g:SetSize(w * 1.8, w * 1.8)
    glows[button] = g
  end
  if g then g:SetShown(on) end
end

local function isQuestLoot(slot)
  local link = slot and GetLootSlotLink and plain(try(GetLootSlotLink, slot))
  local itemName = type(link) == "string" and link:match("%[(.-)%]")
  return itemName and objectiveFor(itemName) ~= nil
end

local function highlightLoot()
  local d = db()
  local on = not (d and d.lootGlow == false)
  -- Modern loot window.
  local box = LootFrame and LootFrame.ScrollBox
  if box and box.ForEachFrame then
    pcall(box.ForEachFrame, box, function(frame)
      local slot = (frame.GetSlotIndex and frame:GetSlotIndex()) or frame.slotIndex
      local button = frame.Item or frame
      glow(button, on and isQuestLoot(slot) or false)
    end)
  end
  -- Classic loot window.
  for i = 1, (LOOTFRAME_NUMBUTTONS or 4) do
    local b = _G["LootButton" .. i]
    if b then glow(b, on and b:IsShown() and isQuestLoot(b.slot) or false) end
  end
end
if hooksecurefunc and type(LootFrame_Update) == "function" then
  hooksecurefunc("LootFrame_Update", function() pcall(highlightLoot) end)
end

G.addonHandlers = G.addonHandlers or {}
G.addonHandlers.D = function(_, body)
  local id, itemName = body:match("^(%d+),(.+)$")
  learn(tonumber(id), itemName, false)
end

local f = CreateFrame("Frame")
for _, ev in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED", "PLAYER_REGEN_ENABLED",
  "LOOT_OPENED", "LOOT_SLOT_CHANGED", "LOOT_SLOT_CLEARED", "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED" }) do
  pcall(f.RegisterEvent, f, ev)
end
-- Health only matters for the target (to catch its death); every other unit would wake this on each hit.
if f.RegisterUnitEvent then pcall(f.RegisterUnitEvent, f, "UNIT_HEALTH", "target") else pcall(f.RegisterEvent, f, "UNIT_HEALTH") end
f:SetScript("OnEvent", function(_, event, unit)
  if event == "LOOT_OPENED" or event == "LOOT_SLOT_CHANGED" or event == "LOOT_SLOT_CLEARED" then
    if event == "LOOT_OPENED" then pcall(onLoot) end
    C_Timer.After(0, function() pcall(highlightLoot) end)
    return
  end
  if event == "PLAYER_TARGET_CHANGED" then pcall(checkTargetDeath); pcall(updateAll); return end -- the target's mark grows
  if event == "UNIT_HEALTH" and unit == "target" then pcall(checkTargetDeath); return end
  if event == "UNIT_HEALTH" then return end
  if event == "PLAYER_ENTERING_WORLD" then pcall(applyLootIcons); pcall(syncThreatPlates); return end
  if event == "NAME_PLATE_UNIT_ADDED" then safeUpdate(unit); pcall(sparkleUpdate, unit)
  elseif event == "NAME_PLATE_UNIT_REMOVED" then
    pcall(sparkleUpdate, unit, true)
    local plate = C_NamePlate and try(C_NamePlate.GetNamePlateForUnit, unit)
    if plate and marks[plate] then marks[plate]:Hide() end
  else
    if event == "PLAYER_REGEN_ENABLED" then pcall(applyLootIcons) end
    wipe(cache); updateAll()
  end
end)
-- Kill counts change without a quest event on some clients: refresh visible plates once a second.
local tpSynced = false
C_Timer.NewTicker(1, function()
  if not tpSynced then local ok, done = pcall(syncThreatPlates); tpSynced = ok and done end
  if marksOn() then updateAll() end; pcall(checkTargetDeath)
end)

G.questMarks = { refresh = function() tpSynced = false; wipe(cache); updateAll() end, diagnose = diagnose,
  applyLootIcons = function()
    local ok = applyLootIcons()
    if G.core then G.core.msg(ok and "Íconos de saqueo actualizados." or "Este cliente no tiene íconos de saqueo (o estás en combate).") end
  end }
