-- Guía Forever: dungeon companion. While you are inside a dungeon, the "Ahora" tab shows its bosses
-- (killed / left), your quests for it, the ones you are missing and loot that suits your class.
-- When you leave, a short run summary. Dungeon, boss, quest and loot data come from
-- ForeverDungeonJournal (optional); boss kills from the client's encounter events.
local G = GuiaForever
G.dungeon = {}

local run      -- current run: { key, label, start, xp, deaths, killed = { [bossName] = true } }
local lastRun  -- summary of the previous run (also saved in GuiaForeverDB.lastRun)

local function fdj() return _G.ForeverDungeonJournal_NS end
local function safe(v) if issecretvalue and issecretvalue(v) then return nil end return v end

-- Which FDJ dungeon are we in? Instance ID first (same on every client), then the localized name.
local function currentDungeon()
  local inInstance, kind = IsInInstance()
  if not inInstance or kind ~= "party" then return nil end
  local name, _, _, _, _, _, _, instanceID = GetInstanceInfo()
  name, instanceID = safe(name), safe(instanceID)
  local f = fdj()
  if not (f and f.DB) then return nil, name end
  local byID = f.INSTANCE_ID_TO_DUNGEON and f.INSTANCE_ID_TO_DUNGEON[tonumber(instanceID) or -1]
  if byID and f.DB[byID] then return byID, name end
  if type(name) == "string" then
    if f.DB[name] then return name, name end
    local wanted = name:lower()
    for _, content in pairs(f.ContentLocales or {}) do
      for internal, entry in pairs(content.dungeons or {}) do
        if f.DB[internal] and type(entry.name) == "string" and entry.name:lower() == wanted then return internal, name end
      end
    end
  end
  return nil, name
end

-- Loot words per class (FDJ loot slots look like "Hands, Leather" or "Main Hand, Dagger").
local ARMOR = { ROGUE = "Leather", DRUID = "Leather", HUNTER = "Mail", SHAMAN = "Mail", WARRIOR = "Mail", PALADIN = "Mail",
  MAGE = "Cloth", PRIEST = "Cloth", WARLOCK = "Cloth" }
local WEAPONS = {
  ROGUE = { "Dagger", "Sword", "Mace", "Fist", "Axe", "Thrown", "Bow", "Gun", "Crossbow" },
  WARRIOR = { "Sword", "Axe", "Mace", "Polearm", "Staff", "Dagger", "Fist", "Bow", "Gun", "Crossbow", "Thrown", "Shield" },
  PALADIN = { "Sword", "Axe", "Mace", "Polearm", "Shield" }, HUNTER = { "Bow", "Gun", "Crossbow", "Axe", "Sword", "Polearm", "Staff", "Dagger", "Fist" },
  SHAMAN = { "Mace", "Axe", "Staff", "Dagger", "Fist", "Shield" }, DRUID = { "Mace", "Staff", "Dagger", "Fist", "Polearm" },
  MAGE = { "Staff", "Dagger", "Sword", "Wand" }, PRIEST = { "Staff", "Dagger", "Mace", "Wand" }, WARLOCK = { "Staff", "Dagger", "Sword", "Wand" },
}
local function suitsMe(slot)
  if type(slot) ~= "string" then return false end
  local class = select(2, UnitClass("player"))
  for _, w in ipairs(WEAPONS[class] or {}) do if slot:find(w, 1, true) then return true end end
  local a = ARMOR[class]
  if slot:find("Cloth", 1, true) or slot:find("Leather", 1, true) or slot:find("Mail", 1, true) or slot:find("Plate", 1, true) then
    return a and slot:find(a, 1, true) ~= nil
  end
  -- neck, finger, trinket, back without armor type
  return slot:find("Neck", 1, true) or slot:find("Finger", 1, true) or slot:find("Trinket", 1, true) or (slot:find("Back", 1, true) ~= nil)
end

local function bossKilled(boss)
  if not run then return false end
  for _, alias in ipairs(boss.aliases or { boss.name }) do if run.killed[alias] then return true end end
  return run.killed[boss.name] or false
end

local function questState(id)
  for _, e in ipairs(G.core.questEntries()) do
    if e.id == id then
      local done, total = 0, 0
      for _, o in ipairs(G.core.questObjectives(e)) do total = total + 1; if o.done then done = done + 1 end end
      return e.complete and "lista" or (done .. "/" .. total)
    end
  end
end

local function fmtTime(sec)
  sec = math.floor(sec or 0)
  return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

-- ---------------------------------------------------------------- events
local function startRun(key, label)
  run = { key = key, label = label or key, start = GetTime(), xp = G.core.sessionXP(), deaths = 0, killed = {} }
end

local function endRun()
  if not run then return end
  local bosses = run.key and fdj() and fdj().DB[run.key] and fdj().DB[run.key].bosses or {}
  local killed = 0
  for _, b in ipairs(bosses) do if bossKilled(b) then killed = killed + 1 end end
  lastRun = {
    label = run.label, secs = GetTime() - run.start, xp = math.max(0, G.core.sessionXP() - run.xp),
    deaths = run.deaths, killed = killed, total = #bosses, at = GetTime(),
  }
  local d = G.core.db()
  if d then d.lastRun = { label = lastRun.label, secs = math.floor(lastRun.secs), xp = lastRun.xp, deaths = lastRun.deaths, killed = killed, total = #bosses } end
  if d and d.runSummary == false then run = nil; return end
  G.core.msg(string.format("%s terminada: %s · %d XP · jefes %d/%d · %d muerte(s).",
    lastRun.label, fmtTime(lastRun.secs), lastRun.xp, killed, #bosses, lastRun.deaths))
  run = nil
end

local function checkZone()
  local key, label = currentDungeon()
  local inInstance, kind = IsInInstance()
  if inInstance and kind == "party" then
    if not run or run.label ~= (label or key) then
      if run then endRun() end
      startRun(key, label)
    end
  elseif run then
    endRun()
  end
  G.core.render()
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ENCOUNTER_END", "BOSS_KILL", "PLAYER_DEAD" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function(_, event, a1, a2, a3, a4, a5)
  if not (G.core and G.core.db()) then return end
  if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
    C_Timer.After(1, checkZone)
  elseif event == "ENCOUNTER_END" or event == "BOSS_KILL" then
    local name = safe(a2)
    local success = (event == "BOSS_KILL") or a5 == 1 or a5 == true
    local d = G.core.db()
    if run and name and success then
      run.killed[name] = true
      if UIErrorsFrame and d.bossMsg ~= false then UIErrorsFrame:AddMessage("Jefe derrotado: " .. name, 0.3, 0.9, 0.5) end
      G.core.render()
    end
  elseif event == "PLAYER_DEAD" then
    if run then run.deaths = run.deaths + 1 end
  end
end)

-- ---------------------------------------------------------------- "Ahora" card
G.topSections = G.topSections or {}
table.insert(G.topSections, function(s)
  local core, C = G.core, G.core.C
  local d = core.db()
  if d and d.dungeonCard == false then return end
  if run then
    local f = fdj()
    local data = run.key and f and f.DB and f.DB[run.key]
    core.H("Mazmorra: " .. (run.label or "?"))
    core.B(C.grey .. "Llevás " .. fmtTime(GetTime() - run.start) .. " · " .. (core.sessionXP() - run.xp) .. " XP · " .. run.deaths .. " muerte(s)" .. C.r)
    if not data then
      core.B(C.grey .. "Sin datos de esta mazmorra (instalá ForeverDungeonJournal para ver jefes y misiones)." .. C.r)
      return
    end
    -- bosses
    local parts, killed = {}, 0
    for _, b in ipairs(data.bosses or {}) do
      if bossKilled(b) then killed = killed + 1; parts[#parts + 1] = C.green .. b.name .. C.r
      else parts[#parts + 1] = b.name end
    end
    if #parts > 0 then core.B(C.gold .. "Jefes " .. killed .. "/" .. #parts .. ":" .. C.r .. " " .. table.concat(parts, C.grey .. " · " .. C.r)) end
    -- quests
    local missing = {}
    for _, q in ipairs(data.quests or {}) do
      if core.factionOk(q, s.faction) then
        local st = q.id and questState(q.id)
        if st then core.B((st == "lista" and C.green or "") .. "Misión " .. q.name .. ": " .. st .. C.r)
        else missing[#missing + 1] = q end
      end
    end
    for _, q in ipairs(missing) do
      core.B(C.orange .. "Te falta: " .. q.name .. C.r .. C.grey .. (q.pickup and (" (se toma: " .. q.pickup .. ")") or "") .. C.r)
    end
    -- loot for you, from bosses still alive
    local loot = {}
    for _, b in ipairs(data.bosses or {}) do
      if not bossKilled(b) then
        for _, it in ipairs(b.loot or {}) do
          if suitsMe(it[3]) then loot[#loot + 1] = it[2] .. C.grey .. " (" .. b.name .. ")" .. C.r end
        end
      end
    end
    if #loot > 0 then core.B(C.blue .. "Botín para vos: " .. C.r .. table.concat(loot, ", ", 1, math.min(#loot, 4))) end
  elseif lastRun and GetTime() - lastRun.at < 1800 then
    core.H("Última mazmorra: " .. lastRun.label)
    core.B(string.format("%s · %d XP · jefes %d/%d · %d muerte(s)", fmtTime(lastRun.secs), lastRun.xp, lastRun.killed, lastRun.total, lastRun.deaths))
  end
end)
