-- Guía Forever: compact damage meter with class-colored bars.
-- Data comes from Blizzard's own meter (C_DamageMeter).
-- In combat the client may hide the numbers ("secret values"): they can still be handed to the
-- bars and texts, but not compared or formatted, so the meter shows them raw and tidies up after combat.
local G = GuiaForever
G.meter = {}

-- Every metric Blizzard's meter offers; only the ones this client has are kept.
local ALL_MODES = {
  { key = "DamageDone", label = "Daño hecho" },
  { key = "Dps", label = "Daño por segundo" },
  { key = "HealingDone", label = "Curación" },
  { key = "Hps", label = "Curación por segundo" },
  { key = "Absorbs", label = "Escudos (absorción)" },
  { key = "DamageTaken", label = "Daño recibido" },
  { key = "AvoidableDamageTaken", label = "Daño evitable recibido" },
  { key = "Interrupts", label = "Interrupciones" },
  { key = "Dispels", label = "Disipaciones" },
  { key = "Deaths", label = "Muertes" },
  { key = "EnemyDamageTaken", label = "Daño por enemigo" },
}
local MODES = {}
for _, m in ipairs(ALL_MODES) do
  if not (Enum and Enum.DamageMeterType) or Enum.DamageMeterType[m.key] ~= nil then MODES[#MODES + 1] = m end
end
-- Our own metric: threat on your current target for you and your party (readable in combat).
MODES[#MODES + 1] = { key = "Threat", label = "Amenaza (tu objetivo)", custom = true }
local MAX_ROWS, ROW_H, WIDTH = 10, 18, 260
local frame, rows, title, sessionBtn, emptyText, picker, labels, pickerButtons
local applyFade, getRow, startMove, stopMove -- defined below
local MAX_SELECTED = 4

local function secret(v) return issecretvalue and issecretvalue(v) end
local function db()
  local d = G.core.db()
  d.meter = d.meter or {}
  return d.meter
end

local function fmt(n)
  if secret(n) then
    if AbbreviateNumbers then local ok, t = pcall(AbbreviateNumbers, n); if ok then return t end end
    return n
  end
  n = tonumber(n) or 0
  if n >= 1000000 then return string.format("%.1fM", n / 1000000) end
  if n >= 10000 then return string.format("%.1fk", n / 1000) end
  return tostring(math.floor(n + 0.5))
end

-- Metrics shown at once (indices into MODES), at least 1 and at most MAX_SELECTED.
local function selected()
  local d = db()
  local list, seen = {}, {}
  for _, i in ipairs(type(d.modes) == "table" and d.modes or {}) do
    if MODES[i] and not seen[i] then list[#list + 1] = i; seen[i] = true end
  end
  if #list == 0 then list = { (MODES[d.mode or 1] and d.mode) or 1 } end
  d.modes = list
  return list
end

-- Which fight: "current", "overall" or a past session ID from Blizzard's list.
local function currentSession()
  local m = db()
  if m.session == nil and m.overall then m.session = "overall" end
  return m.session or "current"
end

local function threatSession()
  local sources = {}
  if not (UnitExists("target") and UnitCanAttack("player", "target")) then return { combatSources = sources, empty = "Seleccioná a un enemigo para ver la amenaza." } end
  local units = { "player" }
  for i = 1, 4 do if UnitExists("party" .. i) then units[#units + 1] = "party" .. i end end
  for _, u in ipairs(units) do
    local ok, tanking, _, scaled = pcall(UnitDetailedThreatSituation, u, "target")
    if ok and scaled ~= nil then
      local _, cf = UnitClass(u)
      sources[#sources + 1] = { name = UnitName(u), classFilename = cf, totalAmount = scaled, max = 100,
        isLocalPlayer = u == "player", tanking = tanking, threat = true }
    end
  end
  if #sources > 1 and not secret(sources[1].totalAmount) then
    table.sort(sources, function(a, b) return (tonumber(a.totalAmount) or 0) > (tonumber(b.totalAmount) or 0) end)
  end
  if #sources == 0 then return { combatSources = sources, empty = "Nadie tiene amenaza con ese objetivo todavía." } end
  return { combatSources = sources }
end

local function session(modeIndex)
  local mode = MODES[modeIndex] or MODES[1]
  if mode.custom then return threatSession() end
  local dm = C_DamageMeter
  if not (dm and dm.GetCombatSessionFromType and Enum and Enum.DamageMeterSessionType and Enum.DamageMeterType) then return nil, "no" end
  local which, ok, seg = currentSession()
  if type(which) == "number" and dm.GetCombatSessionFromID then
    ok, seg = pcall(dm.GetCombatSessionFromID, which, Enum.DamageMeterType[mode.key])
  else
    local st = which == "overall" and Enum.DamageMeterSessionType.Overall or Enum.DamageMeterSessionType.Current
    ok, seg = pcall(dm.GetCombatSessionFromType, st, Enum.DamageMeterType[mode.key])
  end
  if not ok then return nil, "error" end
  return seg
end

local function rowCount() return math.max(3, math.min(MAX_ROWS, db().rows or 6)) end

local function setBar(row, src, top, idx, total)
  local cf = src.classFilename
  if secret(cf) then cf = nil end
  local c = RAID_CLASS_COLORS and cf and RAID_CLASS_COLORS[cf]
  local r, g, b = c and c.r or 0.6, c and c.g or 0.6, c and c.b or 0.6
  row.bar:SetStatusBarColor(r, g, b, 0.9)
  -- Soft left-to-right gradient when the client supports it.
  local tex = row.bar:GetStatusBarTexture()
  if tex and tex.SetGradient and CreateColor then
    pcall(tex.SetGradient, tex, "HORIZONTAL", CreateColor(r * 0.55, g * 0.55, b * 0.55, 0.95), CreateColor(r, g, b, 0.95))
  end
  local coords = cf and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[cf]
  if coords then row.icon:SetTexCoord(unpack(coords)); row.icon:Show() else row.icon:Hide() end
  -- Max = the top source (Blizzard lists sources ordered by amount).
  local okMax = pcall(row.bar.SetMinMaxValues, row.bar, 0, top or 1)
  local okVal = pcall(row.bar.SetValue, row.bar, src.totalAmount or 0)
  if not (okMax and okVal) then pcall(row.bar.SetMinMaxValues, row.bar, 0, 1); pcall(row.bar.SetValue, row.bar, 1) end
  local name = src.name
  if secret(name) then pcall(row.left.SetText, row.left, name)
  else row.left:SetText(idx .. ". " .. (name or "?"):gsub("%-.*$", "")) end
  if src.threat then
    local okT = pcall(row.right.SetFormattedText, row.right, "%s%%%s", secret(src.totalAmount) and src.totalAmount or math.floor((tonumber(src.totalAmount) or 0) + 0.5),
      src.tanking == true and "  |cff4ade80(lo tiene)|r" or "")
    if not okT then row.right:SetText("?") end
    row.me:SetShown(src.isLocalPlayer == true)
    row:Show()
    return
  end
  local amount, perSec = fmt(src.totalAmount), fmt(src.amountPerSecond)
  local pct = ""
  if total and total > 0 and not secret(src.totalAmount) then pct = string.format("  %d%%", math.floor((tonumber(src.totalAmount) or 0) / total * 100 + 0.5)) end
  local okR = pcall(row.right.SetFormattedText, row.right, "%s  |cffaaaaaa(%s)%s|r", amount, perSec, pct)
  if not okR then pcall(row.right.SetText, row.right, amount) end
  row.me:SetShown(src.isLocalPlayer == true)
  row:Show()
end

local function refresh()
  if not frame or not frame:IsShown() then return end
  local m = db()
  local sel = selected()
  local which = currentSession()
  sessionBtn.label:SetText(which == "overall" and "Total" or (type(which) == "number" and "Pasada" or "Pelea"))
  -- Fight length in the title when readable.
  local dur = ""
  local dm = C_DamageMeter
  if type(which) ~= "number" and dm and dm.GetSessionDurationSeconds and Enum and Enum.DamageMeterSessionType then
    local okD, secs = pcall(dm.GetSessionDurationSeconds, which == "overall" and Enum.DamageMeterSessionType.Overall or Enum.DamageMeterSessionType.Current)
    if okD and type(secs) == "number" and not secret(secs) and secs > 0 then dur = string.format("  |cff9ca3af%d:%02d|r", math.floor(secs / 60), math.floor(secs % 60)) end
  end
  title:SetText((#sel == 1 and MODES[sel[1]].label or "Medidor") .. dur)
  for _, r in ipairs(rows) do r:Hide() end
  for _, l in ipairs(labels) do l:Hide() end
  if pickerButtons then
    for i, b in ipairs(pickerButtons) do
      local on = false
      for _, k in ipairs(sel) do if k == i then on = true end end
      b.check:SetText(on and "|cff4ade80x|r" or "")
    end
  end

  local multi = #sel > 1
  local perSection = multi and math.min(rowCount(), 4) or rowCount()
  local y, rowIndex, any, noApi, emptyMsg = -22, 0, false, false, nil
  for si, modeIndex in ipairs(sel) do
    if multi then
      local l = labels[si]
      if not l then
        l = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        l:SetTextColor(0.85, 0.47, 0.34)
        labels[si] = l
      end
      l:ClearAllPoints(); l:SetPoint("TOPLEFT", 8, y - 2); l:SetText(MODES[modeIndex].label); l:Show()
      y = y - 16
    end
    local seg, why = session(modeIndex)
    if why == "no" then noApi = true end
    if seg and seg.empty then emptyMsg = seg.empty end
    local sources = seg and seg.combatSources or {}
    local n = math.min(#sources, perSection)
    local top = sources[1] and (sources[1].max or sources[1].totalAmount)
    local total = 0
    for _, src in ipairs(sources) do
      if secret(src.totalAmount) then total = nil; break end
      total = total + (tonumber(src.totalAmount) or 0)
    end
    for i = 1, n do
      rowIndex = rowIndex + 1
      local row = getRow(rowIndex)
      row:ClearAllPoints(); row:SetPoint("TOPLEFT", 3, y); row:SetPoint("RIGHT", frame, "RIGHT", -3, 0)
      row.src, row.modeIndex = sources[i], modeIndex
      setBar(row, sources[i], top, i, total)
      y = y - ROW_H
      any = true
    end
    if n == 0 and multi then y = y - 4 end
  end
  emptyText:SetShown(not any)
  if not any then
    emptyText:ClearAllPoints(); emptyText:SetPoint("TOPLEFT", 8, y - 4)
    emptyText:SetText(emptyMsg or (noApi and "Tu cliente no tiene el medidor de Blizzard.") or "Sin datos todavía: peleá con algo.")
    y = y - ROW_H
  end
  frame:SetHeight(-y + 6)
end
G.meter.refresh = refresh

local function create()
  frame = CreateFrame("Frame", "GuiaForeverMeter", UIParent, "BackdropTemplate")
  frame:SetSize(WIDTH, 24 + ROW_H + 8)
  frame:SetFrameStrata("MEDIUM"); frame:SetClampedToScreen(true)
  frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
  frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  frame:SetBackdropColor(0.06, 0.06, 0.08, 0.88)
  frame:SetBackdropBorderColor(1, 1, 1, 0.12)
  local m = db()
  local pos = m.pos or { "BOTTOMRIGHT", "BOTTOMRIGHT", -260, 220 }
  frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
  frame:SetScript("OnEnter", function(f) f:SetAlpha(1) end)
  frame:SetScript("OnLeave", function() C_Timer.After(1, applyFade) end)
  -- Move by holding the left button anywhere on the meter (mouse down/up is more reliable than drag events).
  startMove = function() if not db().locked then frame:StartMoving(); frame.moving = true end end
  stopMove = function()
    if not frame.moving then return end
    frame.moving = false
    frame:StopMovingOrSizing()
    local p, _, rp, x, y = frame:GetPoint()
    db().pos = { p, rp, x, y }
  end
  frame:SetScript("OnMouseDown", function(_, button) if button == "LeftButton" then startMove() end end)
  frame:SetScript("OnMouseUp", stopMove)
  frame:SetScript("OnHide", function() stopMove(); if picker then picker:Hide() end end)

  local head = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
  head:SetPoint("TOPLEFT", 1, -1); head:SetPoint("TOPRIGHT", -1, -1); head:SetHeight(20)
  head:SetColorTexture(1, 1, 1, 0.05)

  -- Title = mode switch (click to cycle Daño / Curación / Interrupciones).
  local modeBtn = CreateFrame("Button", nil, frame)
  modeBtn:SetPoint("TOPLEFT", 6, -2); modeBtn:SetSize(120, 18)
  title = modeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  title:SetPoint("LEFT"); title:SetTextColor(0.85, 0.47, 0.34)
  local arrow = modeBtn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  arrow:SetPoint("LEFT", title, "RIGHT", 4, 0); arrow:SetText("v")
  modeBtn:SetScript("OnClick", function() picker:SetShown(not picker:IsShown()) end)
  modeBtn:RegisterForDrag("LeftButton")
  modeBtn:SetScript("OnDragStart", startMove)
  modeBtn:SetScript("OnDragStop", stopMove)
  modeBtn:SetScript("OnEnter", function(self)
    if GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("Clic: elegir qué medir (podés marcar varios). Rueda: pasar al siguiente."); GameTooltip:Show() end
  end)
  modeBtn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

  -- Metric picker: a list under the header.
  picker = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  picker:SetPoint("TOPLEFT", frame, "TOPLEFT", 3, -21)
  picker:SetSize(190, #MODES * 16 + 22)
  picker:SetFrameLevel((frame:GetFrameLevel() or 1) + 20)
  picker:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  picker:SetBackdropColor(0.08, 0.08, 0.1, 0.97); picker:SetBackdropBorderColor(1, 1, 1, 0.15)
  picker:Hide()
  local hint = picker:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("TOPLEFT", 8, -4); hint:SetText("Marcá hasta " .. MAX_SELECTED .. " para verlos juntos")
  pickerButtons = {}
  for i, mode in ipairs(MODES) do
    local b = CreateFrame("Button", nil, picker)
    b:SetPoint("TOPLEFT", 3, -18 - (i - 1) * 16); b:SetSize(184, 16)
    local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.1)
    local box = b:CreateTexture(nil, "ARTWORK"); box:SetSize(10, 10); box:SetPoint("LEFT", 6, 0); box:SetColorTexture(1, 1, 1, 0.15)
    b.check = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.check:SetPoint("CENTER", box, "CENTER", 0, 1)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("LEFT", box, "RIGHT", 6, 0); b.text:SetText(mode.label)
    b:SetScript("OnClick", function()
      local sel, out, had = selected(), {}, false
      for _, k in ipairs(sel) do if k == i then had = true else out[#out + 1] = k end end
      if not had then
        if #sel >= MAX_SELECTED then return end
        out = sel; out[#out + 1] = i
      elseif #out == 0 then return -- keep at least one
      end
      db().modes = out
      refresh()
    end)
    pickerButtons[i] = b
  end
  frame:EnableMouseWheel(true)
  frame:SetScript("OnMouseWheel", function(_, delta)
    local sel = selected()
    if #sel ~= 1 then return end
    db().modes = { (((sel[1]) - 1 - delta) % #MODES) + 1 }
    refresh()
  end)

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2); close:SetSize(22, 22)
  close:SetScript("OnClick", function() G.meter.toggle(false) end)

  sessionBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
  sessionBtn:SetSize(50, 14); sessionBtn:SetPoint("RIGHT", close, "LEFT", 0, 0)
  sessionBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  sessionBtn:SetBackdropColor(1, 1, 1, 0.06); sessionBtn:SetBackdropBorderColor(1, 1, 1, 0.12)
  sessionBtn.label = sessionBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  sessionBtn.label:SetPoint("CENTER")
  -- Fight picker: current, total, or one of the last fights Blizzard keeps.
  local history = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  history:SetPoint("TOPRIGHT", sessionBtn, "BOTTOMRIGHT", 0, -2)
  history:SetFrameLevel((frame:GetFrameLevel() or 1) + 20)
  history:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  history:SetBackdropColor(0.08, 0.08, 0.1, 0.97); history:SetBackdropBorderColor(1, 1, 1, 0.15)
  history:Hide()
  history.buttons = {}
  local function historyEntries()
    local list = { { label = "Pelea actual", value = "current" }, { label = "Total de la sesión", value = "overall" } }
    local dm = C_DamageMeter
    if dm and dm.GetAvailableCombatSessions then
      local ok, all = pcall(dm.GetAvailableCombatSessions)
      if ok and type(all) == "table" then
        for i = #all, math.max(1, #all - 9), -1 do
          local sInfo = all[i]
          local id = sInfo and sInfo.sessionID
          if id and not secret(id) then
            local name = sInfo.name
            if secret(name) or type(name) ~= "string" or name == "" then name = "Pelea " .. i end
            local secs = sInfo.durationSeconds
            local tail = (type(secs) == "number" and not secret(secs)) and string.format("  |cff9ca3af%d:%02d|r", math.floor(secs / 60), math.floor(secs % 60)) or ""
            list[#list + 1] = { label = name .. tail, value = id }
          end
        end
      end
    end
    return list
  end
  local function openHistory()
    local entries = historyEntries()
    for _, b in ipairs(history.buttons) do b:Hide() end
    for i, e in ipairs(entries) do
      local b = history.buttons[i]
      if not b then
        b = CreateFrame("Button", nil, history)
        b:SetSize(176, 16)
        local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.1)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.text:SetPoint("LEFT", 6, 0)
        b.text:SetWidth(166); b.text:SetJustifyH("LEFT"); b.text:SetWordWrap(false)
        history.buttons[i] = b
      end
      b:SetPoint("TOPLEFT", 2, -3 - (i - 1) * 16)
      b.text:SetText((currentSession() == e.value and "|cff4ade80> |r" or "") .. e.label)
      b:SetScript("OnClick", function() db().session = e.value; db().overall = nil; history:Hide(); refresh() end)
      b:Show()
    end
    history:SetSize(180, #entries * 16 + 6)
    history:Show()
  end
  sessionBtn:SetScript("OnClick", function() if history:IsShown() then history:Hide() else openHistory() end end)

  -- Report: top 5 of the first metric shown, to your group chat.
  local report = CreateFrame("Button", nil, frame, "BackdropTemplate")
  report:SetSize(18, 14); report:SetPoint("RIGHT", sessionBtn, "LEFT", -3, 0)
  report:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  report:SetBackdropColor(1, 1, 1, 0.06); report:SetBackdropBorderColor(1, 1, 1, 0.12)
  report.label = report:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); report.label:SetPoint("CENTER"); report.label:SetText("R")
  report:SetScript("OnEnter", function(self)
    if GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("Reportar el top 5 al chat del grupo"); GameTooltip:Show() end
  end)
  report:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  report:SetScript("OnClick", function() G.meter.report() end)

  emptyText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  emptyText:SetPoint("TOPLEFT", 8, -28)

  rows, labels = {}, {}
end

getRow = function(i)
  if rows[i] then return rows[i] end
  local r = CreateFrame("Frame", nil, frame)
  r:SetHeight(ROW_H - 1)
  local bg = r:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(1, 1, 1, 0.03)
  r.bar = CreateFrame("StatusBar", nil, r)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(ROW_H - 1, ROW_H - 1); r.icon:SetPoint("LEFT", 0, 0)
  r.icon:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
  r.bar:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 2, 0); r.bar:SetPoint("BOTTOMRIGHT")
  r.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
  r.bar:SetMinMaxValues(0, 1); r.bar:SetValue(0)
  r.me = r.bar:CreateTexture(nil, "OVERLAY"); r.me:SetSize(2, ROW_H - 1); r.me:SetPoint("LEFT"); r.me:SetColorTexture(1, 1, 1, 0.9)
  r.left = r.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.left:SetPoint("LEFT", 6, 0); r.left:SetJustifyH("LEFT"); r.left:SetWidth(WIDTH - 140); r.left:SetWordWrap(false)
  r.right = r.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.right:SetPoint("RIGHT", -5, 0); r.right:SetJustifyH("RIGHT")
  for _, fs in ipairs({ r.left, r.right }) do local f, sz = fs:GetFont(); if f then fs:SetFont(f, sz or 10, "OUTLINE") end end
  r:EnableMouse(true)
  r:SetScript("OnMouseDown", function(_, button) if button == "LeftButton" then startMove() end end)
  r:SetScript("OnMouseUp", function() stopMove() end)
  r:SetScript("OnEnter", function(self) frame:SetAlpha(1); G.meter.showDetail(self) end)
  r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  r:Hide()
  rows[i] = r
  return r
end

-- ---------------------------------------------------------------- detail and report
local function spellName(id)
  if C_Spell and C_Spell.GetSpellName then local ok, n = pcall(C_Spell.GetSpellName, id); if ok and n then return n end end
  if GetSpellInfo then local ok, n = pcall(GetSpellInfo, id); if ok and n then return n end end
  return "Habilidad " .. tostring(id)
end

function G.meter.showDetail(row)
  local src, mode = row.src, MODES[row.modeIndex or 1]
  if not (src and mode and GameTooltip) then return end
  GameTooltip:SetOwner(row, "ANCHOR_LEFT")
  GameTooltip:AddLine((secret(src.name) and "Detalle" or tostring(src.name)) .. " · " .. mode.label, 1, 0.82, 0)
  if mode.custom then
    GameTooltip:AddLine(src.tanking and "Tiene al enemigo." or "Si llega a 100%, el enemigo va por él.", 1, 1, 1, true)
    GameTooltip:Show(); return
  end
  local dm, guid = C_DamageMeter, src.sourceGUID
  local which = currentSession()
  local ok, data
  if dm and guid and not secret(guid) and Enum and Enum.DamageMeterType then
    if type(which) == "number" and dm.GetCombatSessionSourceFromID then
      ok, data = pcall(dm.GetCombatSessionSourceFromID, which, Enum.DamageMeterType[mode.key], guid)
    elseif dm.GetCombatSessionSourceFromType then
      local st = which == "overall" and Enum.DamageMeterSessionType.Overall or Enum.DamageMeterSessionType.Current
      ok, data = pcall(dm.GetCombatSessionSourceFromType, st, Enum.DamageMeterType[mode.key], guid)
    end
  end
  local spells = ok and type(data) == "table" and data.combatSpells or {}
  if #spells == 0 then
    GameTooltip:AddLine("Sin detalle por habilidad (todavía).", 0.7, 0.7, 0.7)
  else
    local list = {}
    for _, sp in ipairs(spells) do list[#list + 1] = sp end
    if not secret(list[1].totalAmount) then table.sort(list, function(a, b) return (tonumber(a.totalAmount) or 0) > (tonumber(b.totalAmount) or 0) end) end
    for i = 1, math.min(#list, 8) do
      local sp = list[i]
      local id = sp.spellID
      GameTooltip:AddDoubleLine(secret(id) and "?" or spellName(id), fmt(sp.totalAmount), 1, 1, 1, 0.8, 0.8, 0.8)
    end
  end
  GameTooltip:Show()
end

function G.meter.report()
  if InCombatLockdown and InCombatLockdown() then G.core.msg("Esperá a terminar la pelea para reportar."); return end
  local sel = selected()
  local mode = MODES[sel[1]]
  local seg = session(sel[1])
  local sources = seg and seg.combatSources or {}
  local parts = {}
  for i = 1, math.min(#sources, 5) do
    local src = sources[i]
    if secret(src.name) or secret(src.totalAmount) then G.core.msg("Los números todavía están ocultos: probá en unos segundos."); return end
    local amount = src.threat and (math.floor(tonumber(src.totalAmount) or 0) .. "%") or fmt(src.totalAmount)
    parts[#parts + 1] = i .. ". " .. tostring(src.name):gsub("%-.*$", "") .. " " .. amount
  end
  if #parts == 0 then G.core.msg("No hay datos para reportar."); return end
  local which = currentSession()
  local line = "Guía Forever · " .. mode.label .. " (" .. (which == "overall" and "total" or "pelea") .. "): " .. table.concat(parts, ", ")
  local channel = (IsInRaid and IsInRaid() and "RAID") or (IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and "INSTANCE_CHAT")
    or (IsInGroup and IsInGroup() and "PARTY") or nil
  if channel and SendChatMessage then pcall(SendChatMessage, line, channel) else G.core.msg(line) end
end

-- High-threat warning in groups (works even with the meter hidden).
local lastThreatWarn = 0
local function checkThreat()
  local d = db()
  if d.threatWarn == false or not (IsInGroup and IsInGroup()) then return end
  if not (UnitExists("target") and UnitCanAttack("player", "target")) then return end
  local ok, tanking, status, scaled = pcall(UnitDetailedThreatSituation, "player", "target")
  if not ok or tanking == true or secret(scaled) or secret(status) then return end
  scaled = tonumber(scaled)
  if not scaled or scaled < 85 then return end
  if GetTime() - lastThreatWarn < 4 then return end
  lastThreatWarn = GetTime()
  local rogue = select(2, UnitClass("player")) == "ROGUE"
  if UIErrorsFrame then UIErrorsFrame:AddMessage(string.format("¡Amenaza %d%%! %s", math.floor(scaled), rogue and "Usá Amago o frená." or "Frená un poco."), 1, 0.5, 0.2) end
end

applyFade = function()
  if not frame then return end
  local d = db()
  local idle = d.fade ~= false and not (InCombatLockdown and InCombatLockdown())
  frame:SetAlpha(idle and 0.55 or 1)
end
G.meter.applyFade = applyFade

function G.meter.isShown() return db().shown and true or false end
function G.meter.get(key) return db()[key] end
function G.meter.set(key, value) db()[key] = value; applyFade(); refresh() end

function G.meter.toggle(force)
  local m = db()
  if force == false then m.autoShown = nil end
  if force == nil then m.shown = not m.shown else m.shown = force end
  if m.shown then
    if not frame then create() end
    frame:Show(); applyFade(); refresh()
  elseif frame then frame:Hide() end
  if G.core.render then G.core.render() end
end

-- Refresh twice a second in combat, and once right after it ends (numbers become readable).
local ticker, inCombat = 0, false
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function(_, event)
  if not (G.core and G.core.db()) then return end
  if event == "PLAYER_ENTERING_WORLD" then
    if db().shown and not frame then create(); frame:Show() end
    refresh()
  elseif event == "PLAYER_REGEN_DISABLED" then
    inCombat = true
    local d = db()
    if d.auto and not d.shown then d.autoShown = true; G.meter.toggle(true) end
    if frame then frame:SetAlpha(1) end
  else
    inCombat = false; C_Timer.After(1, refresh); C_Timer.After(8, function() if not inCombat then applyFade() end end)
    -- Shown only because the fight started: hide it again a while after combat.
    C_Timer.After(25, function()
      local d = db()
      if d.autoShown and not inCombat then d.autoShown = nil; G.meter.toggle(false) end
    end)
  end
end)
ev:SetScript("OnUpdate", function(_, elapsed)
  if not inCombat then return end
  ticker = ticker + elapsed
  if ticker < 0.5 then return end
  ticker = 0
  pcall(refresh)
  pcall(checkThreat)
end)
