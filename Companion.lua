-- Guía Forever: character snapshot (was a separate snapshot addon). A read-only copy of the player (level, zone, gear,
-- quests, professions, spellbook, action bars and keys, group) written to the GuiaForeverSnapshot saved variable on
-- /reload, logout and /guia foto, so tools outside the game can read it. It never acts in the game.
local G = GuiaForever
G.companion = {}
local f = CreateFrame("Frame")
local function try(fn, ...) local ok, a, b, c, d = pcall(fn, ...); if ok then return a, b, c, d end end

local SLOTS = { "Head","Neck","Shoulder","Shirt","Chest","Waist","Legs","Feet","Wrist","Hands",
  "Finger0","Finger1","Trinket0","Trinket1","Back","MainHand","SecondaryHand","Ranged","Tabard" }

local function position(unit)
  local mapID = C_Map and try(C_Map.GetBestMapForUnit, unit)
  if not mapID then return nil end
  local info = try(C_Map.GetMapInfo, mapID)
  local pos = try(C_Map.GetPlayerMapPosition, mapID, unit)
  local x, y = pos and try(pos.GetXY, pos)
  return { mapID = mapID, map = info and info.name, x = x and math.floor(x * 1000) / 10, y = y and math.floor(y * 1000) / 10 }
end

local function quests()
  local list = {}
  if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
    for i = 1, (try(C_QuestLog.GetNumQuestLogEntries) or 0) do
      local q = try(C_QuestLog.GetInfo, i)
      if q and not q.isHeader then
        local objs = {}
        for _, o in ipairs(try(C_QuestLog.GetQuestObjectives, q.questID) or {}) do objs[#objs + 1] = o.text end
        list[#list + 1] = { id = q.questID, title = q.title, level = q.level,
          complete = try(C_QuestLog.IsComplete, q.questID) or false, objectives = objs }
      end
    end
  elseif GetNumQuestLogEntries then
    for i = 1, (GetNumQuestLogEntries() or 0) do
      local title, level, _, isHeader, _, isComplete, _, questID = try(GetQuestLogTitle, i)
      if title and not isHeader then
        local objs = {}
        for j = 1, (try(GetNumQuestLeaderBoards, i) or 0) do objs[#objs + 1] = try(GetQuestLogLeaderBoard, j, i) end
        list[#list + 1] = { id = questID, title = title, level = level, complete = isComplete == 1, objectives = objs }
      end
    end
  end
  return list
end

local function skills()
  local list = {}
  if GetNumSkillLines then
    for i = 1, GetNumSkillLines() do
      local name, isHeader, _, rank, _, _, maxRank = try(GetSkillLineInfo, i)
      if name and not isHeader then list[#list + 1] = { name = name, rank = rank, max = maxRank } end
    end
  elseif GetProfessions then
    for _, idx in ipairs({ GetProfessions() }) do
      local name, _, rank, maxRank = try(GetProfessionInfo, idx)
      if name then list[#list + 1] = { name = name, rank = rank, max = maxRank } end
    end
  end
  return list
end

-- The spellbook, tab by tab: { { tab = "Combate", spells = { "Golpe siniestro (Rango 3)", ... } }, ... }.
-- Uses C_SpellBook when the client has it, else the classic GetSpellTabInfo / GetSpellBookItemName.
local function spells()
  local out = {}
  local SB = C_SpellBook
  if SB and SB.GetNumSpellBookSkillLines and SB.GetSpellBookSkillLineInfo and SB.GetSpellBookItemInfo then
    local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
    for t = 1, (try(SB.GetNumSpellBookSkillLines) or 0) do
      local line = try(SB.GetSpellBookSkillLineInfo, t)
      if line then
        local list = {}
        for i = line.itemIndexOffset + 1, line.itemIndexOffset + (line.numSpellBookItems or 0) do
          local it = try(SB.GetSpellBookItemInfo, i, bank)
          if it and it.name then
            list[#list + 1] = it.name .. ((it.subName and it.subName ~= "") and (" (" .. it.subName .. ")") or "")
              .. (it.isPassive and " [pasiva]" or "") .. (it.spellID and (" #" .. it.spellID) or "")
          end
        end
        out[#out + 1] = { tab = line.name, spells = list }
      end
    end
  elseif GetNumSpellTabs and GetSpellTabInfo then
    local nameOf = GetSpellBookItemName or GetSpellName
    for t = 1, (try(GetNumSpellTabs) or 0) do
      local name, _, offset, num = try(GetSpellTabInfo, t)
      local list = {}
      for i = (offset or 0) + 1, (offset or 0) + (num or 0) do
        local sname, sub = try(nameOf, i, BOOKTYPE_SPELL or "spell")
        if sname then list[#list + 1] = sname .. ((sub and sub ~= "") and (" (" .. sub .. ")") or "") end
      end
      out[#out + 1] = { tab = name, spells = list }
    end
  end
  return out
end

-- Action bars: { [slot] = "Golpe siniestro (spell 1752) [1]" } for every used slot (1-120), with the key bound to it.
-- Slots 1-12 are the main bar (keys ACTIONBUTTON1-12), 61-72 bottom left, 49-60 bottom right, 25-36 right, 37-48 right 2.
local BAR_BINDS = { { 1, "ACTIONBUTTON" }, { 61, "MULTIACTIONBAR1BUTTON" }, { 49, "MULTIACTIONBAR2BUTTON" },
  { 25, "MULTIACTIONBAR3BUTTON" }, { 37, "MULTIACTIONBAR4BUTTON" } }
local function keyFor(slot)
  for _, b in ipairs(BAR_BINDS) do
    if slot >= b[1] and slot < b[1] + 12 and GetBindingKey then
      local k1, k2 = try(GetBindingKey, b[2] .. (slot - b[1] + 1))
      return k1 and (k1 .. (k2 and (" / " .. k2) or "")) or nil
    end
  end
end
local function actionBars()
  local out = {}
  if not GetActionInfo then return out end
  for slot = 1, 120 do
    local kind, id, sub = try(GetActionInfo, slot)
    if kind then
      local name
      if kind == "spell" then
        name = (C_Spell and C_Spell.GetSpellName and try(C_Spell.GetSpellName, id)) or (GetSpellInfo and try(GetSpellInfo, id))
      elseif kind == "item" then
        name = GetItemInfo and try(GetItemInfo, id)
      elseif kind == "macro" then
        name = GetMacroInfo and try(GetMacroInfo, id)
      end
      local key = keyFor(slot)
      out[slot] = (name or "?") .. " (" .. kind .. " " .. tostring(id) .. ")" .. (key and (" [" .. key .. "]") or "")
    end
  end
  return out
end

local function talents()
  local t = G.talents and G.talents.read()
  if t then
    local picked = {}
    for _, n in ipairs(t.nodes) do
      picked[#picked + 1] = string.format("%s %d/%d @%s,%s spell=%s node=%s", n.name or "?", n.rank or 0, n.max or 0,
        tostring(n.x), tostring(n.y), tostring(n.spell), tostring(n.node))
    end
    return { unspent = t.unspent, spent = t.spent, nodes = picked }
  end
  if not GetNumTalentTabs then return nil end
  local tabs = {}
  for t = 1, GetNumTalentTabs() do
    local name, _, spent = try(GetTalentTabInfo, t)
    local picked = {}
    for i = 1, (try(GetNumTalents, t) or 0) do
      local tname, _, _, _, rank = try(GetTalentInfo, t, i)
      if tname and rank and rank > 0 then picked[#picked + 1] = tname .. " " .. rank end
    end
    tabs[#tabs + 1] = { tree = name, spent = spent, talents = picked }
  end
  return tabs
end

local function group()
  local members = {}
  local n = GetNumGroupMembers and GetNumGroupMembers() or 0
  local prefix = (IsInRaid and IsInRaid()) and "raid" or "party"
  for i = 1, (prefix == "party" and n - 1 or n) do
    local u = prefix .. i
    if UnitExists(u) then
      local _, class = UnitClass(u)
      members[#members + 1] = { name = UnitName(u), level = UnitLevel(u), class = class,
        race = UnitRace(u), zone = nil, online = UnitIsConnected(u), pos = position(u) }
    end
  end
  return members
end

-- Which optional APIs this client exposes (useful when planning addon features).
local API_PROBE = {
  "C_SuperTrack.SetSuperTrackedQuestID", "C_SuperTrack.SetSuperTrackedUserWaypoint", "C_Map.SetUserWaypoint",
  "C_Map.CanSetUserWaypointOnMap", "UiMapPoint.CreateFromCoordinates", "C_QuestLog.GetNextWaypoint",
  "C_QuestLog.GetQuestsOnMap", "C_QuestLog.IsUnitOnQuest", "IsUnitOnQuest", "GetQuestLogRewardXP",
  "C_QuestLog.SetSelectedQuest", "SelectQuestLogEntry", "QuestLogPushQuest", "C_QuestLog.GetQuestObjectives",
  "TooltipDataProcessor.AddTooltipPostCall", "GameTooltip.HookScript", "C_UnitAuras.GetAuraDataByIndex", "UnitAura",
  "C_Container.GetContainerNumFreeSlots", "GetContainerNumFreeSlots", "UnitCharacterPoints", "GetUnspentTalentPoints",
  "C_ChatInfo.SendAddonMessage", "CombatLogGetCurrentEventInfo", "C_Map.GetWorldPosFromMapPos", "IsTradeskillTrainer",
  "GetNumSkillLines", "GetSkillLineInfo", "C_SpellBook.GetSpellBookItemInfo", "GetSpellTabInfo", "GetNumTalentTabs", "GetProfessions", "GetProfessionInfo", "C_SkillLine", "GetWeaponSkill",
  "C_GossipInfo.GetAvailableQuests", "GetAvailableQuestInfo", "GetNumAvailableQuests", "GetQuestID", "GetRewardXP", "UnitGUID",
  "C_QuestLog.GetMaxNumQuestsCanAccept", "IsInInstance",
}

-- Completed quests up to 5 levels over you, as "id,id,..." (lets "Lo próximo" be replayed outside the game).
local function doneQuests()
  local Q = G.qdb
  if not (Q and Q.ready and Q.ready() and Q.done) then return nil end
  local top, ids = (UnitLevel("player") or 1) + 5, {}
  for qid, q in pairs(Q.quests) do if (q.l or 0) <= top and Q.done(qid) then ids[#ids + 1] = qid end end
  table.sort(ids)
  return table.concat(ids, ",")
end
local function probe()
  local r = {}
  for _, path in ipairs(API_PROBE) do
    local v = _G
    for part in path:gmatch("[^%.]+") do v = type(v) == "table" and v[part] or nil end
    r[path] = v ~= nil
  end
  local build, _, _, toc = GetBuildInfo and GetBuildInfo()
  r._build, r._toc = build, toc
  return r
end

local function snapshot(reason)
  -- At logout the client has often already emptied gear and quest data: keep the last good snapshot then.
  if reason == "PLAYER_LOGOUT" and not (GetInventoryItemLink and GetInventoryItemLink("player", 16)) then return end
  local _, class = UnitClass("player")
  local gear = {}
  for _, s in ipairs(SLOTS) do
    local id = try(GetInventorySlotInfo, s .. "Slot")
    local link = id and GetInventoryItemLink("player", id)
    if link then gear[s] = (link:match("%[(.-)%]") or "?") .. " (" .. (link:match("item:(%d+)") or "?") .. ")" end
  end
  local xp, xpMax = UnitXP("player"), UnitXPMax("player")
  GuiaForeverSnapshot = GuiaForeverSnapshot or {}
  GuiaForeverSnapshot[UnitName("player") .. "-" .. (GetRealmName() or "?")] = {
    savedAt = date("%Y-%m-%d %H:%M:%S"), reason = reason,
    name = UnitName("player"), level = UnitLevel("player"), class = class, race = UnitRace("player"),
    faction = UnitFactionGroup("player"), xp = xp, xpMax = xpMax, restedXP = GetXPExhaustion and GetXPExhaustion() or 0,
    gold = math.floor((GetMoney() or 0) / 10000), copperTotal = GetMoney(),
    zone = GetZoneText(), subzone = GetSubZoneText(), pos = position("player"),
    hearth = GetBindLocation and GetBindLocation(), health = UnitHealthMax("player"),
    gear = gear, api = probe(), quests = quests(), skills = skills(), spells = spells(), bars = actionBars(), talents = try(talents), group = group(),
    dungeonQuests = G.dq and try(G.dq.report) or nil,
    doneQuests = try(doneQuests),
    skillLines = GetNumSkillLines and try(GetNumSkillLines) or -1,
  }
end

f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_LOGOUT")
f:SetScript("OnEvent", function(_, event) snapshot(event) end)

function G.companion.snapshot()
  snapshot("manual")
  if G.core then G.core.msg("Foto del personaje lista. Escribí /reload para que se guarde en el archivo.") end
end
