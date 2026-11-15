-- Guía Forever: what the enemy nameplates add. Next to each plate, the icons of YOUR debuffs on that mob (bleeds,
-- poisons, curses...) with the seconds left; a red border when the mob is attacking you; and its health in %. Each
-- part has its own switch in Ajustes > Bichos. Only our own frames are added on the plates; the game's are untouched.
local G = GuiaForever

local function try(fn, ...) if type(fn) ~= "function" then return end local ok, a, b, c = pcall(fn, ...); if ok then return a, b, c end end
local function secret(v) return issecretvalue and issecretvalue(v) end
local function plain(v) if secret(v) then return nil end return v end
local function db() return G.core and G.core.db() end
local function on(key) local d = db(); return d and d[key] ~= false end

local MAX_ICONS, SIZE = 6, 20
local extras = {} -- nameplate frame -> our frame
local units = {}  -- nameplate frame -> unit token

local function extraFor(plate)
  if extras[plate] then return extras[plate] end
  local ok, f = pcall(CreateFrame, "Frame", nil, plate)
  if not ok or not f then return end
  f:SetAllPoints(plate)
  f:SetFrameLevel((plate:GetFrameLevel() or 0) + 5)
  f.icons = {}
  for i = 1, MAX_ICONS do
    local b = CreateFrame("Frame", nil, f)
    b:SetSize(SIZE, SIZE)
    if i == 1 then b:SetPoint("LEFT", f, "RIGHT", 2, 0) else b:SetPoint("LEFT", f.icons[i - 1], "RIGHT", 2, 0) end
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.border = b:CreateTexture(nil, "BACKGROUND")
    b.border:SetPoint("TOPLEFT", -1, 1); b.border:SetPoint("BOTTOMRIGHT", 1, -1)
    b.border:SetColorTexture(0, 0, 0, 0.9)
    b.time = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.time:SetPoint("BOTTOM", b, "BOTTOM", 0, -1)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.count:SetPoint("TOPRIGHT", b, "TOPRIGHT", 1, 1)
    b:Hide()
    f.icons[i] = b
  end
  -- Red border: four thin lines around the health bar (or the whole plate when the bar is not found).
  local bar = plate.UnitFrame and (plate.UnitFrame.healthBar or plate.UnitFrame.HealthBar)
  f.bar = bar or f
  f.aggro = {}
  for i, pts in ipairs({ { "TOPLEFT", "TOPRIGHT", 0, 2 }, { "BOTTOMLEFT", "BOTTOMRIGHT", 0, -2 },
    { "TOPLEFT", "BOTTOMLEFT", -2, 0 }, { "TOPRIGHT", "BOTTOMRIGHT", 2, 0 } }) do
    local t = f:CreateTexture(nil, "OVERLAY")
    t:SetColorTexture(1, 0.15, 0.1, 0.95)
    if i <= 2 then
      t:SetPoint(pts[1], f.bar, pts[1], -2, pts[4]); t:SetPoint(pts[2], f.bar, pts[2], 2, pts[4]); t:SetHeight(2)
    else
      t:SetPoint(pts[1], f.bar, pts[1], pts[3], 2); t:SetPoint(pts[2], f.bar, pts[2], pts[3], -2); t:SetWidth(2)
    end
    t:Hide()
    f.aggro[i] = t
  end
  f.hp = f:CreateFontString(nil, "OVERLAY", "SystemFont_Shadow_Small")
  f.hp:SetPoint("CENTER", f.bar, "CENTER", 0, 0)
  extras[plate] = f
  return f
end

-- Your debuffs on a unit: { { icon, count, duration, expires }, ... }.
local function myDebuffs(unit)
  local out = {}
  for i = 1, 40 do
    local icon, count, duration, expires
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
      local a = try(C_UnitAuras.GetAuraDataByIndex, unit, i, "HARMFUL|PLAYER")
      if not a then break end
      icon, count, duration, expires = a.icon, a.applications, a.duration, a.expirationTime
    elseif UnitAura then
      local name, ic, c, _, d, e = try(UnitAura, unit, i, "HARMFUL|PLAYER")
      if not name then break end
      icon, count, duration, expires = ic, c, d, e
    else break end
    out[#out + 1] = { icon = icon, count = count, duration = duration, expires = expires }
    if #out >= MAX_ICONS then break end
  end
  return out
end

local function timeText(b)
  local e, d = plain(b.expires), plain(b.duration)
  if not (e and d and d > 0) then return "" end
  local left = e - GetTime()
  if left <= 0 then return "" end
  if left < 10 then return string.format("|cffff5a3c%.0f|r", math.ceil(left)) end
  if left < 60 then return string.format("%d", math.floor(left)) end
  return string.format("%dm", math.floor(left / 60 + 0.5))
end

local function update(unit)
  local plate = C_NamePlate and try(C_NamePlate.GetNamePlateForUnit, unit)
  if not plate then return end
  local enemy = UnitCanAttack and plain(try(UnitCanAttack, "player", unit)) == true
  local f = extras[plate] or (enemy and extraFor(plate))
  if not f then return end
  units[plate] = unit
  -- Debuffs
  local list = (enemy and on("plateDebuffs")) and myDebuffs(unit) or {}
  for i, b in ipairs(f.icons) do
    local a = list[i]
    if a then
      pcall(b.tex.SetTexture, b.tex, a.icon)
      b.expires, b.duration = a.expires, a.duration
      local c = plain(a.count)
      b.count:SetText(c and c > 1 and c or "")
      b.time:SetText(timeText(b))
      b:Show()
    else
      b.expires = nil
      b:Hide()
    end
  end
  -- Aggro: the mob is targeting you (in a group: you have its threat).
  local aggro = false
  if enemy and on("plateAggro") then
    local status = UnitThreatSituation and plain(try(UnitThreatSituation, "player", unit))
    if status then aggro = status >= 2
    else aggro = UnitIsUnit and plain(try(UnitIsUnit, unit .. "target", "player")) == true end
  end
  for _, t in ipairs(f.aggro) do t:SetShown(aggro) end
  -- Health %
  local hp, max = plain(try(UnitHealth, unit)), plain(try(UnitHealthMax, unit))
  if enemy and on("plateHealth") and hp and max and max > 0 and hp < max then
    f.hp:SetText(math.floor(hp / max * 100 + 0.5) .. "%")
  else
    f.hp:SetText("")
  end
end

local function safeUpdate(unit) pcall(update, unit) end
local function updateAll()
  for i = 1, 40 do local u = "nameplate" .. i; if UnitExists(u) then safeUpdate(u) end end
end
G.plates = { refresh = updateAll }

local ev = CreateFrame("Frame")
for _, e in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_AURA", "UNIT_HEALTH", "UNIT_TARGET",
  "UNIT_THREAT_SITUATION_UPDATE", "PLAYER_TARGET_CHANGED", "PLAYER_REGEN_ENABLED" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function(_, event, unit)
  if event == "NAME_PLATE_UNIT_REMOVED" then
    local plate = C_NamePlate and try(C_NamePlate.GetNamePlateForUnit, unit)
    local f = plate and extras[plate]
    if f then
      for _, b in ipairs(f.icons) do b:Hide() end
      for _, t in ipairs(f.aggro) do t:Hide() end
      f.hp:SetText("")
      units[plate] = nil
    end
  elseif type(unit) == "string" and unit:find("^nameplate") then safeUpdate(unit)
  elseif event == "UNIT_TARGET" or event == "UNIT_THREAT_SITUATION_UPDATE" or event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_REGEN_ENABLED" then updateAll()
  end
end)

-- The seconds on the icons, and a slower full pass in case an event was missed (a mob changing target).
local t, full = 0, 0
ev:SetScript("OnUpdate", function(_, elapsed)
  t, full = t + elapsed, full + elapsed
  if full >= 0.5 then full, t = 0, 0; updateAll(); return end
  if t < 0.1 then return end
  t = 0
  for plate, f in pairs(extras) do
    if units[plate] then
      for _, b in ipairs(f.icons) do if b:IsShown() and b.expires then b.time:SetText(timeText(b)) end end
    end
  end
end)
