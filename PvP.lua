-- Guía Forever: world-PvP awareness for PvP realms. No combat log on Forever, so enemies are seen
-- only through nameplates, target and mouseover (~40 yd). Stealthed players cannot be detected.
local G = GuiaForever
G.pvp = {}

local seen = {}          -- guid -> { name, class, classFile, level, guild, first, last, alerted, targetMe }
local lastShare = {}     -- name -> time
local groupSeen = {}     -- enemies reported by party members (newest first)
local honorVictim         -- defined in the rivals section below

-- ---------------------------------------------------------------- layers
-- Every NPC GUID looks like "Creature-0-server-instance-ZONEUID-npcID-spawn": the ZONEUID is the layer
-- We read it from NPCs you see and compare it with your party's.
local layer = { id = nil, mapID = nil, at = 0 }   -- your current layer
local partyLayers = {}                            -- name -> { id, mapID, at }
local lastLayerSent, layerWarned = 0, {}
local sendLayer -- defined below

local CLASS_TIPS = {
  WARRIOR = "Guerrero: Gubia y distancia; si carga, Evasión. No pelees a la larga.",
  PALADIN = "Paladín: Patada a su sanación; si se pone la burbuja, andate.",
  HUNTER = "Cazador: pegate a él (de cerca es débil), cuidado con la Trampa congelante.",
  ROGUE = "Pícaro: si desaparece, puede volver con Golpe bajo. Evasión lista.",
  PRIEST = "Sacerdote: Patada a sus curas; el miedo te deja suelto, guardá Sprint.",
  SHAMAN = "Chamán: Patada a sus curas o rayos; rompé tótems si podés.",
  MAGE = "Mago: Patada a Bola de fuego/Escarcha; si te congela, Evasión no sirve.",
  WARLOCK = "Brujo: Patada al Miedo; matá rápido o andate, su mascota molesta.",
  DRUID = "Druida: cambia de forma para escapar; Patada a sus curas.",
}

local function safe(v)
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end
local function ask(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c = pcall(fn, ...)
  if not ok then return nil end
  return safe(a), safe(b), safe(c)
end

local function settings()
  local db = G.core.db()
  db.pvp = db.pvp or {}
  local p = db.pvp
  if p.alerts == nil then p.alerts = true end
  if p.sound == nil then p.sound = true end
  if p.share == nil then p.share = true end
  p.killers = p.killers or {}
  p.victims = p.victims or {}  -- players you killed (from the honor message): name -> { count, class }
  p.marked = p.marked or {}    -- players you marked as rivals
  return p
end

local function paused()
  if ask(UnitIsDeadOrGhost, "player") then return true end
  if ask(UnitOnTaxi, "player") then return true end
  local inst = ask(IsInInstance)
  if inst then return true end
  local zoneType = ask(GetZonePVPInfo)
  return zoneType == "sanctuary"
end

local banner
local function showBanner(text, r, g, b, onClick)
  if not banner then
    banner = CreateFrame("Frame", "GuiaForeverPvPBanner", UIParent, "BackdropTemplate")
    banner:SetSize(420, 34); banner:SetPoint("TOP", UIParent, "TOP", 0, -120); banner:SetFrameStrata("HIGH")
    banner:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    banner:SetBackdropColor(0.08, 0.02, 0.02, 0.85)
    banner.text = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    banner.text:SetPoint("CENTER"); banner.text:SetWidth(400)
    banner:Hide()
  end
  banner:SetBackdropBorderColor(r, g, b, 0.9)
  banner.text:SetText(text)
  banner:EnableMouse(onClick ~= nil)
  banner:SetScript("OnMouseUp", onClick and function() onClick(); banner:Hide() end or nil)
  banner:SetAlpha(1); banner:Show()
  banner.hideAt = GetTime() + (onClick and 10 or 5)
  banner:SetScript("OnUpdate", function(f)
    local left = f.hideAt - GetTime()
    if left <= 0 then f:Hide(); f:SetScript("OnUpdate", nil) elseif left < 1 then f:SetAlpha(left) end
  end)
end

local function levelInfo(level)
  local me = UnitLevel("player") or 1
  if not level or level <= 0 then return "??", 1, 0.2, 0.2, "PELIGRO (calavera)" end
  local d = level - me
  if d >= 5 then return tostring(level), 1, 0.2, 0.2, "PELIGRO" end
  if d <= -5 then return tostring(level), 0.6, 0.6, 0.6, "presa fácil" end
  return tostring(level), 1, 0.8, 0.2, "pelea pareja"
end

local function className(e)
  local c = RAID_CLASS_COLORS and e.classFile and RAID_CLASS_COLORS[e.classFile]
  local hex = c and string.format("|cff%02x%02x%02x", math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255)) or "|cffffffff"
  return hex .. (e.class or "?") .. "|r"
end

local function alert(e)
  local p = settings()
  e.alerted = GetTime()
  local lvl, r, g, b, verdict = levelInfo(e.level)
  local text = "Enemigo cerca: " .. (e.name or "?") .. " - " .. className(e) .. " " .. lvl .. " (" .. verdict .. ")"
  local rival = G.pvp.rivalText(e.name)
  if rival then text = text .. "  " .. rival end
  if p.alerts then
    showBanner(text, r, g, b)
    if p.sound and PlaySound and SOUNDKIT then
      local k = SOUNDKIT.RAID_WARNING or SOUNDKIT.READY_CHECK
      if k then pcall(PlaySound, k) end
    end
    local tip = e.classFile and CLASS_TIPS[e.classFile]
    if tip and p.classTips ~= false and select(2, UnitClass("player")) == "ROGUE" then G.core.msg(tip) end
  end
  if p.share and G.core.inGroup() and e.name and (not lastShare[e.name] or GetTime() - lastShare[e.name] > 60) then
    lastShare[e.name] = GetTime()
    local zone = (GetZoneText and GetZoneText() or ""):gsub("[,;|]", " ")
    G.core.sendAddon("E" .. e.name .. "," .. (e.classFile or "") .. "," .. (e.level or 0) .. "," .. zone)
  end
  G.core.render()
end

local function readLayer(unit)
  local guid = ask(UnitGUID, unit)
  if type(guid) ~= "string" then return end
  local kind, _, _, _, zoneUID = strsplit("-", guid)
  if (kind ~= "Creature" and kind ~= "Vehicle") or not zoneUID then return end
  if ask(UnitPlayerControlled, unit) then return end -- pets and summons follow their owner
  local id = tonumber(zoneUID)
  if not id or id == 0 then return end
  local mapID = C_Map and ask(C_Map.GetBestMapForUnit, "player")
  local changed = layer.id ~= id
  layer.id, layer.mapID, layer.at = id, mapID, GetTime()
  if changed and sendLayer then sendLayer(true) end
end

local function observe(unit)
  if not unit or not ask(UnitExists, unit) then return end
  if not ask(UnitIsPlayer, unit) then readLayer(unit) end
  if not ask(UnitIsPlayer, unit) then return end
  if not (ask(UnitCanAttack, "player", unit) or ask(UnitIsEnemy, "player", unit)) then return end
  local guid = ask(UnitGUID, unit)
  if type(guid) ~= "string" or not guid:match("^Player%-") then return end
  if paused() then return end
  local now = GetTime()
  local e = seen[guid]
  if not e then
    local name = ask(UnitName, unit)
    if not name then return end
    local class, classFile = ask(UnitClass, unit)
    e = { name = name, class = class, classFile = classFile, first = now, guild = ask(GetGuildInfo, unit) }
    seen[guid] = e
  end
  e.last = now
  e.level = ask(UnitLevel, unit) or e.level
  e.zone = GetZoneText and GetZoneText()
  local tgt = ask(UnitIsUnit, unit .. "target", "player")
  if tgt then e.targetMe = now end
  if not e.alerted or now - e.alerted > 90 then alert(e) end
end

-- Remember who was hitting at you just before you died (no combat log: best guess).
local function onDeath()
  local p = settings()
  if p.rivals == false then return end
  local now, names = GetTime(), {}
  for _, e in pairs(seen) do
    if e.targetMe and now - e.targetMe < 20 and e.last and now - e.last < 20 then
      local k = p.killers[e.name] or { count = 0 }
      k.count, k.class, k.classFile, k.level, k.at = k.count + 1, e.class, e.classFile, e.level, date and date("%Y-%m-%d")
      p.killers[e.name] = k
      names[#names + 1] = e.name
    end
  end
  if #names > 0 then G.core.msg("Probablemente te mató: " .. table.concat(names, ", ") .. ". Queda en tu lista.") end
end

local ticker = 0
local f = CreateFrame("Frame")
local registered = {}
for _, ev in ipairs({ "NAME_PLATE_UNIT_ADDED", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "PLAYER_DEAD", "PLAYER_ENTERING_WORLD", "CHAT_MSG_COMBAT_HONOR_GAIN" }) do
  registered[ev] = pcall(f.RegisterEvent, f, ev)
end

-- Enemy nameplates must be on, or the client reports nobody nearby (to any addon).
local function namesOn()
  local v = GetCVar and GetCVar("nameplateShowEnemies")
  return v == nil or v == "1"
end
local function turnNamesOn()
  if InCombatLockdown and InCombatLockdown() then G.core.msg("En combate no se puede: probá al terminar la pelea."); return end
  if SetCVar then pcall(SetCVar, "nameplateShowEnemies", "1") end
  G.core.msg(namesOn() and "Nombres de enemigos activados: ahora la Guía ve quién aparece cerca." or "No pude activarlos: apretá V.")
end
f:SetScript("OnEvent", function(_, event, unit)
  if not (G.core and G.core.db()) then return end
  if event == "NAME_PLATE_UNIT_ADDED" then observe(unit)
  elseif event == "PLAYER_TARGET_CHANGED" then observe("target")
  elseif event == "UPDATE_MOUSEOVER_UNIT" then observe("mouseover")
  elseif event == "PLAYER_DEAD" then onDeath()
  elseif event == "CHAT_MSG_COMBAT_HONOR_GAIN" then
    local p = settings()
    local raw = unit
    local victim = p.rivals ~= false and honorVictim(raw)
    if victim then
      local v = p.victims[victim] or { count = 0 }
      v.count = v.count + 1
      for _, e in pairs(seen) do if e.name == victim then v.class, v.classFile, v.level = e.class, e.classFile, e.level end end
      p.victims[victim] = v
      local rival = G.pvp.rivalText(victim)
      G.core.msg("Mataste a " .. victim .. (rival and (" · " .. rival) or ""))
      G.core.render()
    end
  elseif event == "PLAYER_ENTERING_WORLD" then
    layer.id = nil -- new zone or instance: read it again from the next NPC
    C_Timer.After(5, function()
      local p = settings()
      if p.alerts and not namesOn() then
        G.core.msg("Para que las alertas funcionen sin seleccionar, activá los nombres de enemigos: apretá V o escribí /guia pvp nombres")
      end
    end)
  end
end)
-- Twice a second: layer sync. Every 2 s: a sweep of the visible nameplates, a fallback that catches units even if
-- NAME_PLATE_UNIT_ADDED never fired (the event already covers the usual case).
local sweep = 0
f:SetScript("OnUpdate", function(_, elapsed)
  ticker = ticker + elapsed
  if ticker < 0.5 then return end
  ticker = 0
  if not (G.core and G.core.db()) then return end
  local p = settings()
  sendLayer(false)
  if not (p.alerts or p.layers ~= false) then return end
  sweep = (sweep + 1) % 4
  if sweep ~= 0 then return end
  for i = 1, 40 do
    local u = "nameplate" .. i
    if ask(UnitExists, u) then observe(u) end
  end
end)

local lastSOS, lastHelp = 0, nil
local compareLayers -- defined below, with the layer helpers
G.addonHandlers = G.addonHandlers or {}
G.addonHandlers.L = function(sender, body)
  local mapID, id = body:match("^(%d+),(%d+)$")
  if not id then return end
  partyLayers[sender] = { id = tonumber(id), mapID = tonumber(mapID), at = GetTime() }
  local p = settings()
  if compareLayers(sender) == "otra" and p.layerWarn ~= false and not layerWarned[sender .. id] then
    layerWarned[sender .. id] = true
    showBanner(sender .. " está en tu zona pero en OTRA CAPA: no se ven. Mirá Ahora -> Capas.", 0.98, 0.75, 0.14)
  end
  G.core.render()
end
G.addonHandlers.H = function(sender, body)
  local mapID, x, y, zone, foe, foeClass, foeLevel = body:match("^([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*)$")
  if not mapID then return end
  lastHelp = { from = sender, mapID = tonumber(mapID), x = tonumber(x), y = tonumber(y), zone = zone }
  local text = "¡" .. sender .. " pide ayuda en " .. (zone ~= "" and zone or "su zona") .. "!"
  if foe and foe ~= "" then
    local e = { classFile = foeClass, class = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[foeClass]) or foeClass }
    text = text .. " Contra " .. foe .. " (" .. className(e) .. " " .. (tonumber(foeLevel) or "?") .. ")"
  end
  text = text .. (lastHelp.x and "  |cff7dd3fc[clic: ir]|r" or "")
  showBanner(text, 1, 0.3, 0.1, lastHelp.x and G.pvp.goToSOS or nil)
  if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then pcall(PlaySound, SOUNDKIT.RAID_WARNING) end
  G.core.msg(text:gsub("  |cff7dd3fc%[clic: ir%]|r", "") .. (lastHelp.x and " Escribí /guia ir para el marcador." or ""))
end
G.addonHandlers.E = function(sender, body)
  local name, classFile, level, zone = body:match("^([^,]*),([^,]*),([^,]*),(.*)$")
  if not name then return end
  local p = settings()
  local e = { name = name, classFile = classFile, class = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile]) or classFile, level = tonumber(level) }
  e.by, e.zone, e.at = sender, zone, GetTime()
  table.insert(groupSeen, 1, e)
  while #groupSeen > 10 do table.remove(groupSeen) end
  local lvl, r, g, b = levelInfo(e.level)
  if p.alerts then showBanner(sender .. " vio a " .. name .. " - " .. className(e) .. " " .. lvl .. (zone ~= "" and (" en " .. zone) or ""), r, g, b) end
end

-- ---------------------------------------------------------------- rivals
function G.pvp.rivalText(name)
  if not name then return nil end
  local p = settings()
  local k, v = p.killers[name], p.victims[name]
  local killedMe, iKilled = k and k.count or 0, v and v.count or 0
  local parts = {}
  if p.marked[name] then parts[#parts + 1] = "|cfffb923cRIVAL|r" end
  if killedMe >= 3 and killedMe > iKilled then parts[#parts + 1] = "|cfff87171NÉMESIS|r" end
  if killedMe > 0 then parts[#parts + 1] = "|cfff87171te mató " .. killedMe .. "|r" end
  if iKilled > 0 then parts[#parts + 1] = "|cff4ade80lo mataste " .. iKilled .. "|r" end
  if #parts == 0 then return nil end
  return table.concat(parts, " · ")
end

function G.pvp.markRival()
  local name = ask(UnitName, "target")
  if not (name and ask(UnitIsPlayer, "target")) then G.core.msg("Seleccioná a un jugador y escribí /guia rival."); return end
  local p = settings()
  p.marked[name] = not p.marked[name] or nil
  G.core.msg(p.marked[name] and (name .. " marcado como RIVAL: te aviso fuerte cuando aparezca.") or (name .. " ya no es rival."))
  G.core.render()
end

-- Honor message: "<name> dies, honorable kill..." in the client's language (COMBATLOG_HONORGAIN*).
local honorPatterns
honorVictim = function(msg)
  if type(msg) ~= "string" or (issecretvalue and issecretvalue(msg)) then return nil end
  if not honorPatterns then
    honorPatterns = {}
    for _, key in ipairs({ "COMBATLOG_HONORGAIN", "COMBATLOG_HONORGAIN_NO_RANK" }) do
      local fmt = _G[key]
      if type(fmt) == "string" then
        local pat = fmt:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
        pat = pat:gsub("%%(%d)%%%$", "%%")   -- positional %1$s -> %s
        pat = pat:gsub("%%s", "(.-)"):gsub("%%d", "%%d+")
        pat = "^" .. pat .. "$"
        honorPatterns[#honorPatterns + 1] = pat
      end
    end
  end
  for _, pat in ipairs(honorPatterns) do
    local name = msg:match(pat)
    if name and name ~= "" then return name end
  end
end

-- ---------------------------------------------------------------- SOS
function G.pvp.sos()
  if not G.core.inGroup() then G.core.msg("No estás en grupo: el SOS les llega a tus compañeros de grupo que tienen la Guía."); return end
  if GetTime() - lastSOS < 15 then G.core.msg("Ya pediste ayuda hace un momento."); return end
  lastSOS = GetTime()
  local mapID = C_Map and ask(C_Map.GetBestMapForUnit, "player")
  local x, y
  if mapID and C_Map.GetPlayerMapPosition then
    local okP, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if okP and pos and not (issecretvalue and issecretvalue(pos)) then
      local okX, px, py = pcall(pos.GetXY, pos)
      if okX and not (issecretvalue and (issecretvalue(px) or issecretvalue(py))) then x, y = px, py end
    end
  end
  local now, foe = GetTime(), nil
  for _, e in pairs(seen) do if not e.mob and e.last and now - e.last < 30 and (not foe or e.last > foe.last) then foe = e end end
  local zone = (GetZoneText and GetZoneText() or ""):gsub("[,;|]", " ")
  local body = (mapID or 0) .. "," .. (x and string.format("%.4f", x) or "") .. "," .. (y and string.format("%.4f", y) or "") .. "," .. zone .. ","
    .. (foe and (foe.name or "") or "") .. "," .. (foe and (foe.classFile or "") or "") .. "," .. (foe and (foe.level or 0) or 0)
  if G.core.sendAddon("H" .. body) then
    showBanner("Pediste ayuda a tu grupo" .. (foe and (" (" .. foe.name .. ")") or ""), 1, 0.5, 0.2)
  else
    G.core.msg("No pude mandar el SOS (el juego bloquea mensajes en este momento).")
  end
end

function G.pvp.goToSOS()
  local h = lastHelp
  if not (h and G.setWaypoint(h.mapID, h.x, h.y)) then G.core.msg("Ese pedido no trae ubicación: andá a " .. ((h and h.zone) or "su zona") .. "."); return end
  G.core.msg("Marcador puesto: seguí la flecha hasta " .. (h.from or "tu amigo") .. ".")
end

-- ---------------------------------------------------------------- layer sharing
sendLayer = function(force)
  if not (layer.id and G.core.inGroup()) then return end
  if not force and GetTime() - lastLayerSent < 60 then return end
  lastLayerSent = GetTime()
  G.core.sendAddon("L" .. (layer.mapID or 0) .. "," .. layer.id)
end

local function shortLayer(id) return id and tostring(id % 10000) or "?" end

compareLayers = function(name)
  local them = partyLayers[name]
  if not them or GetTime() - them.at > 600 then return "sin datos" end
  if not layer.id or GetTime() - layer.at > 600 then return "sin datos tuyos" end
  if them.mapID ~= layer.mapID then return "otra zona" end
  return them.id == layer.id and "misma" or "otra"
end
G.pvp.compareLayers = compareLayers
-- Your layer (LayerHop.lua): id, mapID, GetTime() of the reading; scanLayer re-reads it from target and nameplates now.
function G.pvp.layer() return layer.id, layer.mapID, layer.at end
function G.pvp.scanLayer()
  readLayer("target")
  for i = 1, 40 do local u = "nameplate" .. i; if ask(UnitExists, u) then readLayer(u) end end
end

function G.pvp.isOn() return settings().alerts and true or false end
function G.pvp.get(key) return settings()[key] end
function G.pvp.set(key, value) settings()[key] = value; G.core.render() end
G.pvp.namesOn = function() return namesOn() end
G.pvp.turnNamesOn = function() turnNamesOn() end

function G.pvp.command(arg)
  local p = settings()
  if arg == "sonido" then p.sound = not p.sound; G.core.msg("Sonido de alerta: " .. (p.sound and "sí" or "no"))
  elseif arg == "compartir" then p.share = not p.share; G.core.msg("Avisar al grupo: " .. (p.share and "sí" or "no"))
  elseif arg == "limpiar" then p.killers = {}; G.core.msg("Lista de los que te mataron borrada.")
  elseif arg == "nombres" then turnNamesOn()
  else p.alerts = not p.alerts; G.core.msg("Alertas de enemigos: " .. (p.alerts and "activadas" or "apagadas") .. ". Opciones: /guia pvp sonido | compartir | limpiar | nombres") end
  G.core.render()
end

-- Section for the "Ahora" tab.
G.nowSections = G.nowSections or {}
table.insert(G.nowSections, function()
  local core, C = G.core, G.core.C
  local p = settings()
  local now = GetTime()
  local recent = {}
  for _, e in pairs(seen) do if e.last and now - e.last < 300 and not e.mob then recent[#recent + 1] = e end end
  table.sort(recent, function(a, b) return a.last > b.last end)
  local flagged = ask(UnitIsPVP, "player")
  local zoneType = ask(GetZonePVPInfo)
  local killers = {}
  for name, k in pairs(p.killers) do killers[#killers + 1] = { name = name, k = k } end
  table.sort(killers, function(a, b) return a.k.count > b.k.count end)
  local fromGroup = {}
  for _, e in ipairs(groupSeen) do if now - e.at < 600 then fromGroup[#fromGroup + 1] = e end end
  local rivals = {}
  for name in pairs(p.marked) do rivals[name] = true end
  for name, k in pairs(p.killers) do if k.count >= 2 then rivals[name] = true end end
  for name, v in pairs(p.victims) do if v.count >= 2 then rivals[name] = true end end
  local rivalList = {}
  for name in pairs(rivals) do rivalList[#rivalList + 1] = name end
  if #recent == 0 and #killers == 0 and #fromGroup == 0 and #rivalList == 0 and not flagged and not G.core.inGroup() then return end
  core.H("Cerca de vos")
  local zt = ({ hostile = C.red .. "zona enemiga" .. C.r, contested = C.orange .. "zona disputada" .. C.r,
    friendly = C.green .. "zona aliada" .. C.r, sanctuary = C.blue .. "santuario" .. C.r })[zoneType or ""] or C.grey .. "zona sin datos" .. C.r
  core.B((flagged and (C.red .. "JcJ activado" .. C.r) or (C.green .. "JcJ apagado" .. C.r)) .. " · " .. zt ..
    (p.alerts and "" or (C.grey .. " · alertas apagadas (/guia pvp)" .. C.r)))
  if G.core.inGroup() then core.L("  " .. core.actionLink("sos", 0, "Pedir ayuda al grupo (SOS)", "|cfff87171")) end
  for i = 1, math.min(#recent, 5) do
    local e = recent[i]
    local lvl, r, g, b, verdict = levelInfo(e.level)
    core.B(className(e) .. " " .. (e.name or "?") .. " " .. lvl .. C.grey .. " · " .. verdict .. " · hace " .. math.floor((now - e.last) / 60) .. " min" .. C.r)
  end
  for i = 1, math.min(#fromGroup, 3) do
    local e = fromGroup[i]
    local lvl, _, _, _, verdict = levelInfo(e.level)
    core.B(className(e) .. " " .. (e.name or "?") .. " " .. lvl .. C.grey .. " · lo vio " .. e.by .. (e.zone ~= "" and (" en " .. e.zone) or "") ..
      " · hace " .. math.floor((now - e.at) / 60) .. " min · " .. verdict .. C.r)
  end
  if #rivalList > 0 then
    local parts = {}
    for i = 1, math.min(#rivalList, 4) do parts[#parts + 1] = rivalList[i] .. " (" .. (G.pvp.rivalText(rivalList[i]) or "") .. ")" end
    core.B(C.orange .. "Rivales: " .. C.r .. table.concat(parts, ", "))
  end
  if #killers > 0 then
    local parts = {}
    for i = 1, math.min(#killers, 3) do parts[#parts + 1] = killers[i].name .. " (" .. killers[i].k.count .. ")" end
    core.B(C.red .. "Te mataron: " .. C.r .. table.concat(parts, ", "))
  end
end)

-- Section for "Ahora": are your friends on your layer?
table.insert(G.nowSections, 1, function()
  local core, C = G.core, G.core.C
  local p = settings()
  if p.layers == false or not core.inGroup() then return end
  core.H("Capas (layer)")
  if layer.id then
    core.B("Tu capa: " .. C.gold .. "#" .. shortLayer(layer.id) .. C.r .. C.grey .. " (leída de los bichos cercanos)" .. C.r)
  else
    core.B(C.grey .. "Todavía no sé tu capa: pasá el mouse por un bicho o un NPC." .. C.r)
  end
  local anyOther = false
  for _, u in ipairs(core.partyUnits()) do
    local name = UnitName(u)
    if name then
      local st = compareLayers(name)
      local txt = ({ misma = C.green .. "misma capa: se ven" .. C.r, otra = C.orange .. "OTRA capa: no se ven" .. C.r,
        ["otra zona"] = C.grey .. "en otra zona" .. C.r })[st] or (C.grey .. "sin datos (¿tiene la Guía?)" .. C.r)
      if st == "otra" then anyOther = true end
      core.B(name .. ": " .. txt)
    end
  end
  if anyOther then
    core.B(C.gold .. "Para juntarse:" .. C.r .. " estando en grupo, el que está solo busca un lugar tranquilo y espera el aviso de cambiar de capa (aceptalo fuera de combate). Si no llega, salgan y vuelvan a entrar a una ciudad, o reconectá.")
  end
end)
