-- Guía Forever: the next-step bar. A small movable bar with only the first step of "Lo próximo" (Core.lua): a big icon
-- for what to do (take, turn in, kill, loot, travel), an arrow that turns toward the target as you turn, the distance,
-- a progress bar for counted objectives and a short name. The detail is in the tooltip. The map waypoint and the arrow
-- in the middle of the screen follow the step on their own; when the step changes the bar flashes green. Hidden inside
-- instances and when turned off.
local G = GuiaForever
G.nextStep = {}

local function try(fn, ...) if type(fn) ~= "function" then return end local ok, a, b, c = pcall(fn, ...); if ok then return a, b, c end end
local function plain(v) if issecretvalue and issecretvalue(v) then return nil end return v end
local function db() return G.core and G.core.db() end
-- The bar is off unless turned on: the arrow in the middle of the screen says the same with less on screen.
local function on() local d = db(); return d and d.nextBar == true end
local function autoMark() local d = db(); return d and d.nextBarWaypoint ~= false end
G.nextStep.ownArrow = autoMark

local ICON = {
  take = "Interface\\GossipFrame\\AvailableQuestIcon",
  turnin = "Interface\\GossipFrame\\ActiveQuestIcon",
  kill = "Interface\\Icons\\INV_Sword_04",
  loot = "Interface\\Icons\\INV_Misc_Bag_08",
  ["do"] = "Interface\\Icons\\INV_Misc_Note_01",
  travel = "Interface\\Icons\\INV_Misc_Map_01",
  dungeon = "Interface\\Icons\\INV_Misc_Key_14",
}
local VERB = { take = "Tomar", turnin = "Entregar", kill = "Matar", loot = "Juntar", ["do"] = "Hacer", travel = "Viajar a", dungeon = "" }

local bar, step, stepKey, lastPlan

-- World position (yards, north and west) of a point on a map, through the client's own map bounds.
local function world(mapID, x, y)
  local b = mapID and G.mapBounds and G.mapBounds(mapID)
  if not (b and x and y) then return end
  return b.top - y * b.h, b.left - x * b.w, b.inst
end

local function playerWorld()
  local mapID = C_Map and try(C_Map.GetBestMapForUnit, "player")
  local pos = mapID and try(C_Map.GetPlayerMapPosition, mapID, "player")
  if not (pos and plain(pos)) then return end
  local x, y = pos.x, pos.y
  if pos.GetXY then x, y = pos:GetXY() end
  x, y = plain(x), plain(y)
  if not x then return end
  return world(mapID, x, y)
end
G.nextStep.world, G.nextStep.playerWorld = world, playerWorld

-- Border: gold while preparing a dungeon, grey otherwise; a short green flash when a step is done.
local flashing = false
local function border()
  if not (bar and bar.SetBackdropBorderColor) or flashing then return end
  if step and step.goal then bar:SetBackdropBorderColor(0.9, 0.75, 0.2, 1) else bar:SetBackdropBorderColor(0.3, 0.3, 0.35, 1) end
end
local function flash(r, g, b)
  if not (bar and bar.SetBackdropBorderColor) then return end
  bar:SetBackdropBorderColor(r, g, b, 1)
  flashing = true
  if C_Timer then C_Timer.After(1.5, function() flashing = false; border() end) else flashing = false end
end

local function playDone()
  local d = db()
  if d and d.notifySound == false or not (PlaySound and SOUNDKIT) then return end
  for _, k in ipairs({ "UI_QUEST_ROLLING_FORWARD_01", "IG_QUEST_LIST_SELECT" }) do
    if SOUNDKIT[k] then pcall(PlaySound, SOUNDKIT[k]); return end
  end
end

-- ---------------------------------------------------------------- the arrow in the middle of the screen
-- Ours instead of the game's waypoint marker: only a gold arrow, the name and the meters; the detail on mouse over.
-- It points at the last waypoint set through G.setWaypoint (the step, an [Ir] link, a city pin...).
local center, target

local function createCenter()
  if center or not db() then return end
  center = CreateFrame("Frame", "GuiaForeverArrow", UIParent)
  center:SetSize(160, 92)
  center:SetMovable(true)
  center:SetClampedToScreen(true)
  -- Clicks and the camera go through it; holding Shift makes it take the mouse (detail on hover, drag to move).
  center:EnableMouse(false)
  center:RegisterForDrag("LeftButton")
  center:RegisterEvent("MODIFIER_STATE_CHANGED")
  center:SetScript("OnEvent", function(self)
    local alt = IsShiftKeyDown and IsShiftKeyDown() or false
    self:EnableMouse(alt)
    if not alt then GameTooltip:Hide() end
  end)
  local p = db().arrowPos
  if p then center:SetPoint(p[1], UIParent, p[1], p[2], p[3]) else center:SetPoint("CENTER", UIParent, "CENTER", 0, 170) end
  center:SetScript("OnDragStart", function(self) self:StartMoving() end)
  center:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, _, x, y = self:GetPoint()
    db().arrowPos = { point, x, y }
  end)
  center.arrow = center:CreateTexture(nil, "ARTWORK")
  center.arrow:SetSize(44, 44)
  center.arrow:SetPoint("TOP", 0, 0)
  center.arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
  center.arrow:SetVertexColor(1, 0.82, 0.2)
  center.text = center:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  center.text:SetPoint("TOP", center.arrow, "BOTTOM", 0, -2)
  center.text:SetWidth(240)
  center.text:SetWordWrap(false)
  center.text:SetShadowOffset(1, -1)
  -- Second line, small: "Preparando <dungeon>: 3 de 5" and "3/8" for counted objectives.
  -- The meters on their own line, so a long name never hides them.
  center.dist = center:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  center.dist:SetPoint("TOP", center.text, "BOTTOM", 0, -2)
  center.dist:SetShadowOffset(1, -1)
  center.sub = center:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  center.sub:SetPoint("TOP", center.dist, "BOTTOM", 0, -2)
  center.sub:SetTextColor(0.75, 0.75, 0.75)
  center:SetScript("OnEnter", function(self)
    if not target then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(target.label, 1, 0.82, 0, true)
    for _, l in ipairs(target.detail or {}) do GameTooltip:AddLine(l, 1, 1, 1, true) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Con Shift: ver esto y arrastrarla · Ajustes > Misiones > Flecha en pantalla", 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
  end)
  center:SetScript("OnLeave", function() GameTooltip:Hide() end)
  local t = 0
  center:SetScript("OnUpdate", function(self, elapsed)
    t = t + elapsed
    if t < 0.05 then return end
    t = 0
    if target and target.noPos then
      self:SetAlpha(1); self.arrow:Hide(); self.text:SetText("|cff4ade80" .. target.label .. "|r"); self.dist:SetText(""); return
    end
    local pn, pw, pinst = playerWorld()
    local tn, tw, tinst = world(target and target.mapID, target and target.x, target and target.y)
    if not (pn and tn) or (pinst and tinst and pinst ~= tinst) or (IsInInstance and IsInInstance()) then self:SetAlpha(0); return end
    self:SetAlpha(1)
    local north, east = tn - pn, -(tw - pw)
    local yards = math.sqrt(north * north + east * east)
    local facing = GetPlayerFacing and plain(try(GetPlayerFacing))
    if yards < 8 then
      self.text:SetText(target.label)
      self.dist:SetText("|cff4ade80¡Llegaste!|r")
      self.arrow:Hide()
    else
      self.text:SetText(target.label)
      self.dist:SetText(math.floor(yards + 0.5) .. " m")
      if facing then
        local bearing = math.atan2 and math.atan2(-east, north) or math.atan(-east, north)
        self.arrow:SetRotation(bearing - facing)
        self.arrow:Show()
      else
        self.arrow:Hide()
      end
    end
  end)
end

-- The game's own navigation marker (the square with "!" or "?" in the middle of the screen, for a tracked quest or a
-- waypoint) is made invisible while our arrow is on; it comes back when the arrow is turned off. Only its alpha is
-- touched, after the game's own update, so nothing of the game's UI is replaced.
local function quietNative()
  local f = _G.SuperTrackedFrame
  if not (f and f.HookScript) then return end
  if not f.guiaQuiet then
    f.guiaQuiet = true
    f:HookScript("OnUpdate", function(self) if autoMark() and self:GetAlpha() > 0 then self:SetAlpha(0) end end)
    f:HookScript("OnShow", function(self) if autoMark() then self:SetAlpha(0) end end)
  end
  f:SetAlpha(autoMark() and 0 or 1)
end
G.nextStep.quietNative = quietNative

function G.nextStep.point(mapID, x, y, label, detail)
  target = { mapID = mapID, x = x, y = y, label = label or "Marcador", detail = detail }
  if not autoMark() then return end
  createCenter()
  if center then center:Show() end
end

function G.nextStep.hideArrow()
  target = nil
  if center then center:Hide() end
end

local function mark()
  if step and step.mapID and step.x then
    G.setWaypoint(step.mapID, step.x, step.y, (VERB[step.kind] and VERB[step.kind] ~= "" and (VERB[step.kind] .. ": ") or "") .. (step.name or ""), step.detail)
    if target then target.fromStep = true end
  end
end
function G.nextStep.remark() mark() end

local function showTooltip(self)
  if not step then return end
  GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
  GameTooltip:AddLine((VERB[step.kind] or "") .. " " .. (step.name or ""), 1, 0.82, 0, true)
  for _, l in ipairs(step.detail or {}) do GameTooltip:AddLine(l, 1, 1, 1, true) end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Clic: marcar de nuevo · Clic derecho: abrir la guía · Arrastrá para moverla", 0.6, 0.6, 0.6, true)
  GameTooltip:Show()
end

local function create()
  if bar or not db() then return end
  local d = db()
  bar = CreateFrame("Button", "GuiaForeverNextStep", UIParent, "BackdropTemplate")
  bar:SetSize(220, 52)
  bar:SetMovable(true)
  bar:SetClampedToScreen(true)
  bar:RegisterForDrag("LeftButton")
  bar:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  if bar.SetBackdrop then
    bar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    bar:SetBackdropColor(0.06, 0.06, 0.08, 0.85)
    bar:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)
  end
  local p = d.nextBarPos
  if p then bar:SetPoint(p[1], UIParent, p[1], p[2], p[3]) else bar:SetPoint("TOP", UIParent, "TOP", 0, -120) end
  bar:SetScript("OnDragStart", function(self) self:StartMoving() end)
  bar:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, _, x, y = self:GetPoint()
    db().nextBarPos = { point, x, y }
  end)

  bar.icon = bar:CreateTexture(nil, "ARTWORK")
  bar.icon:SetSize(40, 40)
  bar.icon:SetPoint("LEFT", 6, 0)

  bar.arrow = bar:CreateTexture(nil, "ARTWORK")
  bar.arrow:SetSize(34, 34)
  bar.arrow:SetPoint("LEFT", bar.icon, "RIGHT", 6, 0)
  bar.arrow:SetTexture("Interface\\Minimap\\MinimapArrow")

  bar.name = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  bar.name:SetPoint("TOPLEFT", bar.arrow, "TOPRIGHT", 6, -1)
  bar.name:SetPoint("RIGHT", -22, 0)
  bar.name:SetJustifyH("LEFT")
  bar.name:SetWordWrap(false)

  bar.dist = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  bar.dist:SetPoint("TOPLEFT", bar.name, "BOTTOMLEFT", 0, -3)

  bar.progress = CreateFrame("StatusBar", nil, bar)
  bar.progress:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  bar.progress:SetStatusBarColor(0.29, 0.87, 0.5)
  bar.progress:SetHeight(8)
  bar.progress:SetPoint("BOTTOMLEFT", bar.arrow, "BOTTOMRIGHT", 6, 2)
  bar.progress:SetPoint("RIGHT", -8, 0)
  bar.progress.bg = bar.progress:CreateTexture(nil, "BACKGROUND")
  bar.progress.bg:SetAllPoints()
  bar.progress.bg:SetColorTexture(1, 1, 1, 0.12)
  bar.progress.text = bar.progress:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  bar.progress.text:SetPoint("RIGHT", bar.progress, "RIGHT", 0, 9)

  -- "Preparando <dungeon>" above the bar while a dungeon goal is set (G.dq.goal).
  bar.mode = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  bar.mode:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 2, 2)
  bar.mode:SetTextColor(1, 0.82, 0)

  bar.skip = CreateFrame("Button", nil, bar)
  bar.skip:SetSize(16, 16)
  bar.skip:SetPoint("TOPRIGHT", -3, -3)
  bar.skip.t = bar.skip:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  bar.skip.t:SetPoint("CENTER")
  bar.skip.t:SetText("»")
  bar.skip:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Saltar este paso", 1, 0.82, 0)
    GameTooltip:AddLine("No te lo vuelve a sugerir hasta que subas de nivel.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  bar.skip:SetScript("OnLeave", function() GameTooltip:Hide() end)
  bar.skip:SetScript("OnClick", function()
    if step and #step.quests > 0 and G.core then G.core.skipStep(step.quests); stepKey = "skipped"; G.nextStep.refresh() end
  end)

  bar:SetScript("OnEnter", showTooltip)
  bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
  bar:SetScript("OnClick", function(_, button)
    if button == "RightButton" then
      local f = _G.GuiaForeverFrame
      if f then d.tab = 1; d.hidden = false; f:Show(); if G.core then G.core.render() end end
    else
      mark()
    end
  end)

  -- Arrow and distance every 0.05 s (the step itself: the ticker at the end of the file and quest events).
  local tArrow = 0
  bar:SetScript("OnUpdate", function(_, elapsed)
    tArrow = tArrow + elapsed
    if tArrow < 0.05 or not step then return end
    tArrow = 0
    local pn, pw, pinst = playerWorld()
    local tn, tw, tinst = world(step.mapID, step.x, step.y)
    if not (pn and tn) or (pinst and tinst and pinst ~= tinst) then
      bar.arrow:Hide(); bar.dist:SetText(""); return
    end
    local north, east = tn - pn, -(tw - pw)
    local yards = math.sqrt(north * north + east * east)
    bar.dist:SetText(yards < 8 and "|cff4ade80¡Llegaste!|r" or (math.floor(yards + 0.5) .. " m"))
    local facing = GetPlayerFacing and plain(try(GetPlayerFacing))
    if facing and yards >= 8 then
      -- Bearing counter-clockwise from north (as GetPlayerFacing), turned by where you look.
      local bearing = math.atan2 and math.atan2(-east, north) or math.atan(-east, north)
      bar.arrow:SetRotation(bearing - facing)
      bar.arrow:Show()
    else
      bar.arrow:Hide()
    end
  end)
end

local function stepID(s)
  if not s then return nil end
  return s.kind .. ":" .. (s.quests[1] or s.name or "?")
end

function G.nextStep.refresh()
  pcall(quietNative)
  -- Walking into the dungeon you were preparing ends the goal.
  local goal, here = G.dq and G.dq.goal(), G.dq and G.dq.current()
  if goal and here == goal and G.core then
    G.core.charDB().dungeonGoal = nil
    G.core.msg("Llegaste a " .. goal.name .. ". ¡Suerte! Al salir, la flecha vuelve a guiarte para subir de nivel.")
  end
  local wantBar, wantArrow = on(), autoMark()
  if bar and not wantBar then bar:Hide() end
  if not (wantBar or wantArrow) then return end
  local s = G.core and G.core.nextStep()
  step = s
  if not s then
    if bar then bar:Hide() end
    if center and target and target.fromStep then G.nextStep.hideArrow() end
    stepKey = nil
    return
  end
  local mode = s.goal and ("Preparando " .. s.goal.name .. (s.goalWant and s.goalWant > 0 and (": tenés " .. (s.goalHave or 0) .. " de " .. s.goalWant .. " misiones") or "")) or ""
  local id = stepID(s)
  if id ~= stepKey then
    if stepKey and stepKey ~= "skipped" then flash(0.29, 0.87, 0.5); playDone() end
    stepKey = id
    if wantArrow then
      if s.x then mark()
      else -- no place to point at ("Andá a <dungeon>"): the text alone, without the arrow
        target = { label = s.name or "", detail = s.detail, fromStep = true, noPos = true }
        createCenter()
        if center then center:Show() end
      end
    end
  elseif wantArrow and s.kind == "dungeon" and s.x and target and target.fromStep and (target.x ~= s.x or target.y ~= s.y) then
    mark() -- the dungeon's entrance leg changed (path start reached): same step, new point
  end
  if center then
    local count = (s.need and s.need > 1) and ((s.have or 0) .. "/" .. s.need) or ""
    center.sub:SetText(mode .. ((mode ~= "" and count ~= "") and "  ·  " or "") .. count)
  end
  if not wantBar then return end
  create()
  if not bar then return end
  bar.icon:SetTexture(ICON[s.kind] or ICON["do"])
  bar.name:SetText(s.kind == "dungeon" and ("|cff4ade80" .. (s.name or "") .. "|r") or (s.name or ""))
  bar.mode:SetText(mode)
  border()
  if s.need and s.need > 1 then
    bar.progress:SetMinMaxValues(0, s.need)
    bar.progress:SetValue(s.have or 0)
    bar.progress.text:SetText((s.have or 0) .. "/" .. s.need)
    bar.progress:Show()
  else
    bar.progress:Hide()
  end
  bar.skip:SetShown(#s.quests > 0 and not s.goal)
  bar:Show()
end

-- The arrow in the middle of the screen: on by default, it follows the step. Turned off, it and the game's marker are
-- cleared, and [Ir] links use the game's marker again.
function G.nextStep.clearWaypoint()
  G.nextStep.hideArrow()
  if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then try(C_SuperTrack.SetSuperTrackedUserWaypoint, false) end
  if C_Map and C_Map.ClearUserWaypoint then try(C_Map.ClearUserWaypoint) end
end

function G.nextStep.toggleWaypoint()
  local d = db()
  if not d then return end
  d.nextBarWaypoint = (d.nextBarWaypoint == false)
  pcall(quietNative)
  if d.nextBarWaypoint then mark() else G.nextStep.clearWaypoint() end
  if G.core then G.core.msg("Flecha en pantalla: " .. (d.nextBarWaypoint and "prendida" or "apagada") .. ".") end
end

function G.nextStep.toggle()
  local d = db()
  if not d then return end
  d.nextBar = not on()
  G.nextStep.refresh()
  if G.core then G.core.msg("Barra del próximo paso: " .. (d.nextBar and "prendida" or "apagada") .. ".") end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "QUEST_LOG_UPDATE",
  "ZONE_CHANGED_NEW_AREA", "PLAYER_LEVEL_UP" }) do pcall(ev.RegisterEvent, ev, e) end
-- The step itself every 2 s (positions change as you walk), whether the bar or only the arrow is on.
local tick = 0
ev:SetScript("OnUpdate", function(_, elapsed)
  tick = tick + elapsed
  if tick < 2 then return end
  tick = 0
  if on() or autoMark() then pcall(G.nextStep.refresh) end
  -- An [Ir a la entrada] marker moves from the path start to the entrance once you get there.
  local d = target and target.entrance
  if d and G.dq and G.dq.entrancePoint then
    local m, x, y, label = G.dq.entrancePoint(d)
    if m and (x ~= target.x or y ~= target.y) and G.setWaypoint(m, x, y, label) and target then target.entrance = d end
  end
end)
function G.nextStep.followEntrance(d) if target then target.entrance = d end end
local pending = false
ev:SetScript("OnEvent", function()
  -- Many quest events come together: one refresh on the next frame.
  if pending then return end
  pending = true
  local function run() pending = false; pcall(G.nextStep.refresh) end
  if C_Timer then C_Timer.After(0.3, run) else run() end
end)

-- ---------------------------------------------------------------- flight master
-- On the flight map, each reachable flight point shows how far it lands from what the arrow points at, the closest one
-- in green with a star, and a line on top compares it with the distance from here. Positions come from the client
-- (C_TaxiMap on the continent map), so they are Forever's own.
local function goalWorld()
  local t = target
  if t and not t.noPos and t.mapID then return world(t.mapID, t.x, t.y) end
  if step and step.mapID and step.x then return world(step.mapID, step.x, step.y) end
end
local function goalLabel()
  return (target and not target.noPos and target.label) or (step and step.name) or ""
end

local function continentOf(mapID)
  local guard = 0
  while mapID and guard < 10 do
    local info = C_Map and try(C_Map.GetMapInfo, mapID)
    if not info then return end
    if info.mapType == 2 then return mapID end
    mapID, guard = info.parentMapID, guard + 1
  end
end

local function metersText(yards) return math.floor(yards + 0.5) .. " m" end

local taxiHead, taxiLabels, taxiBySlot = nil, {}, {}
local function clearTaxi()
  for _, fs in pairs(taxiLabels) do fs:Hide() end
  if taxiHead then taxiHead:Hide() end
  taxiBySlot = {}
end

-- Where each flight point is, in world yards: { [slot] = { n, w, inst, name, current } }. C_TaxiMap first; when it
-- gives no positions, the flight map's own (TaxiNodePosition: 0-1 on the continent map, measured from the bottom).
local function taxiNodes(cont)
  local out, any = {}, false
  local nodes = cont and C_TaxiMap and try(C_TaxiMap.GetAllTaxiNodes, cont)
  for _, n in ipairs(type(nodes) == "table" and nodes or {}) do
    local pos, x, y = n.position
    if pos and pos.GetXY then x, y = pos:GetXY() elseif pos then x, y = pos.x, pos.y end
    local nn, nw, ni = world(cont, x, y)
    if nn and n.slotIndex and n.state ~= 2 then
      out[n.slotIndex] = { n = nn, w = nw, inst = ni, name = n.name, current = n.state == 0 }; any = true
    end
  end
  if any or not (NumTaxiNodes and TaxiNodePosition) then return out end
  for i = 1, (try(NumTaxiNodes) or 0) do
    local kind = TaxiNodeGetType and try(TaxiNodeGetType, i)
    local x, y = try(TaxiNodePosition, i)
    local nn, nw, ni = world(cont, x, y and (1 - y))
    if nn and kind ~= "NONE" and kind ~= "DISTANT" then
      out[i] = { n = nn, w = nw, inst = ni, name = TaxiNodeName and try(TaxiNodeName, i), current = kind == "CURRENT" }
    end
  end
  return out
end

local function fillTaxi()
  clearTaxi()
  if not (TaxiFrame and TaxiFrame:IsShown()) then return end
  if not taxiHead then
    taxiHead = TaxiFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    taxiHead:SetPoint("BOTTOM", TaxiFrame, "TOP", 0, 4)
    taxiHead:SetWidth(420)
    taxiHead:SetJustifyH("CENTER")
  end
  local function say(text) taxiHead:SetText(text); taxiHead:Show() end
  local gn, gw, ginst = goalWorld()
  if not gn then
    return say("|cffaaaaaaGuía: no hay destino marcado. Tocá [Ir] en la guía (o [Ir a la entrada] de una mazmorra) y te digo a qué vuelo subirte.|r")
  end
  local pmap = C_Map and try(C_Map.GetBestMapForUnit, "player")
  local cont = continentOf(pmap)
  local nodes = taxiNodes(cont)
  local best, bestYards
  for slot, n in pairs(nodes) do
    if not ginst or not n.inst or ginst == n.inst then
      local yards = math.sqrt((gn - n.n) ^ 2 + (gw - n.w) ^ 2)
      taxiBySlot[slot] = { yards = yards, name = n.name, current = n.current }
      if not n.current and (not bestYards or yards < bestYards) then best, bestYards = slot, yards end
    end
  end
  for slot, info in pairs(taxiBySlot) do
    local btn = _G["TaxiButton" .. slot]
    if btn and btn:IsShown() and not info.current then
      local fs = taxiLabels[slot]
      if not fs then
        fs = TaxiFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        taxiLabels[slot] = fs
      end
      fs:ClearAllPoints()
      fs:SetPoint("TOP", btn, "BOTTOM", 0, 1)
      if slot == best then fs:SetText("|cff4ade80★ " .. metersText(info.yards) .. "|r") else fs:SetText("|cffffd100" .. metersText(info.yards) .. "|r") end
      fs:Show()
    end
  end
  local pn, pw, pinst = playerWorld()
  local here = pn and (not pinst or not ginst or pinst == ginst) and math.sqrt((gn - pn) ^ 2 + (gw - pw) ^ 2)
  local line = "Destino: |cffffd100" .. goalLabel() .. "|r"
  if best then line = line .. "\n|cff4ade80★ Volá a " .. (taxiBySlot[best].name or "?") .. "|r: te deja a " .. metersText(bestYards) end
  if here then line = line .. " · desde acá " .. metersText(here) end
  if not best then line = line .. (next(nodes) and "\nEstá en otro continente: tomá el barco o el zepelín." or "\nNo pude leer los puntos de vuelo de este mapa.") end
  say(line)
end

-- The tooltip of a flight point says the same, for points whose label is hard to read on the map.
if hooksecurefunc and type(TaxiNodeOnButtonEnter) == "function" then
  hooksecurefunc("TaxiNodeOnButtonEnter", function(btn)
    local info = btn and btn.GetID and taxiBySlot[btn:GetID()]
    if info and not info.current and GameTooltip:IsShown() then
      GameTooltip:AddLine("Queda a " .. metersText(info.yards) .. " de " .. goalLabel(), 0.3, 0.87, 0.5, true)
      GameTooltip:Show()
    end
  end)
end

local taxiEv = CreateFrame("Frame")
pcall(taxiEv.RegisterEvent, taxiEv, "TAXIMAP_OPENED")
pcall(taxiEv.RegisterEvent, taxiEv, "TAXIMAP_CLOSED")
taxiEv:SetScript("OnEvent", function(_, e)
  if e == "TAXIMAP_CLOSED" then clearTaxi(); return end
  -- The flight map lays out its buttons when it shows: fill on the next frame.
  if C_Timer then C_Timer.After(0.05, function() pcall(fillTaxi) end) else pcall(fillTaxi) end
end)
