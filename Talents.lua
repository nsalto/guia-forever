-- Guía Forever: talent suggestions. Adds a "Sugerir" button to the talent window. It reads your tree (C_Traits),
-- works out the spec you are building (points per tree, else the spec chosen in the Clase tab) and your weapons,
-- then glows the talents to take next (numbered in order), marks points that do nothing for you in red, and lists
-- the reasons in a small panel. It only marks: it never spends or refunds points.
local G = GuiaForever

local function try(fn, ...) if type(fn) ~= "function" then return end local ok, a, b, c = pcall(fn, ...); if ok then return a, b, c end end
local function db() return G.core and G.core.db() end

-- Priorities per class and spec: spell ID of the talent, ranks to reach, why. Order = order to take them.
-- `trees` lists the specs left to right as the trees appear in the window. `avoid` = points wasted under a condition.
-- Sources: Warcraft Tavern, Method, Icy Veins and Kami Labs rogue guides for Forever (see DataClasses.lua).
local DATA = {
  ROGUE = {
    trees = { "assassination", "combat", "subtlety" },
    specs = {
      combat = {
        { 13732, 2, "Golpe siniestro cuesta menos energía: más golpes por pelea." },
        { 14162, 3, "Eviscerar pega más fuerte: tu remate principal." },
        { 13705, 3, "Fallás menos golpes." },
        { 13713, 3, "Parás más ataques, y cada parada habilita Contestación." },
        { 14251, 1, "Contraataque gratis después de parar." },
        { 13742, 2, "Evasión y Sprint vuelven antes: sobrevivís y escapás más seguido." },
        { 1310711, 1, "Eviscerar cuesta 10 de energía menos." },
        { 18427, 3, "Más daño en Golpe siniestro y Eviscerar." },
        { 30919, 2, "Los bichos esquivan y paran menos tus golpes." },
        { 13877, 1, "Aluvión de acero: pegás a 2 bichos a la vez y atacás más rápido." },
        { 13960, 5, "Cortar y rebanar: ataques extra con espadas y hachas, las mazas ignoran armadura." },
        { 13715, 2, "La mano izquierda pega más." },
        { 1329284, 5, "Destello de acero: muchísima energía." },
        { 13750, 1, "Subidón de adrenalina: ráfaga de energía para jefes y apuros." },
        { 14144, 2, "Crítico seguro después de matar: encadenás bichos más rápido." },
        { 14138, 5, "Más probabilidad de crítico." },
      },
      assassination = {
        { 14144, 2, "Crítico seguro después de matar: encadenás bichos más rápido." },
        { 14138, 5, "Más probabilidad de crítico." },
        { 14165, 3, "Hacer picadillo dura más." },
        { 14156, 3, "Tus remates pueden devolverte un punto de combo." },
        { 14128, 2, "Más daño en los críticos de tus golpes de combo." },
        { 14177, 1, "Sangre fría: tu próximo golpe es crítico seguro." },
        { 14113, 5, "Tus venenos se aplican más seguido." },
        { 1329328, 1, "Veneno: remate que sube mucho el daño de tus venenos." },
        { 14179, 5, "Tus remates te devuelven energía." },
        { 14186, 3, "Los críticos te dan un punto de combo extra." },
        { 399956, 1, "Mutilar: golpe doble con dos dagas, tu generador principal." },
        { 16513, 5, "Venenos más fuertes." },
      },
      subtlety = {
        { 14057, 5, "Más daño con Puñalada y Emboscada desde atrás." },
        { 13958, 3, "Te ven menos en sigilo." },
        { 13983, 3, "Al esquivar o parar ganás puntos de combo." },
        { 14079, 3, "Emboscada hace crítico más seguido." },
        { 14082, 2, "Más daño a bichos con poca vida." },
        { 14183, 1, "Premeditación: dos puntos de combo antes de atacar." },
        { 14171, 3, "Tus golpes ignoran parte de la armadura." },
        { 13976, 3, "Tus aperturas pueden dar un punto de combo extra." },
        { 14278, 1, "Golpe fantasmal: te deja usar Emboscada en combate." },
        { 14185, 1, "Preparación: reinicia Evasión, Sprint y Esfumarse." },
        { 16511, 1, "Hemorragia: generador de combos que no necesita daga." },
        { 1329286, 5, "Cuchillo de bota." },
        { 1316709, 1, "Marca mortal: más daño contra élites y jefes." },
      },
    },
    avoid = {
      { 1224716, "dagger", "Heridas perforantes mejora Puñalada y Mutilar, que necesitan daga. Con tus armas ese punto no hace nada: el instructor te lo devuelve si reiniciás los talentos." },
    },
  },
}

-- Weapon type of the main hand: "dagger", "sword", "mace", "axe", "fist" or nil.
local SUBCLASS = { [15] = "dagger", [7] = "sword", [8] = "sword", [4] = "mace", [5] = "mace", [0] = "axe", [1] = "axe", [13] = "fist" }
local function mainHand()
  local link = GetInventoryItemLink and GetInventoryItemLink("player", 16)
  if not link then return nil end
  if type(GetItemInfoInstant) ~= "function" then return nil end
  local ok, _, _, _, _, _, classID, sub = pcall(GetItemInfoInstant, link)
  if not ok then return nil end
  if classID ~= 2 then return nil end
  return SUBCLASS[sub]
end

-- Splits the nodes into trees by their x position (the trees are separated by wide gaps).
local function treeIndexer(nodes)
  local xs = {}
  for _, n in ipairs(nodes) do if n.x then xs[#xs + 1] = n.x end end
  table.sort(xs)
  local cuts = {}
  for i = 2, #xs do if xs[i] - xs[i - 1] > 1500 then cuts[#cuts + 1] = (xs[i] + xs[i - 1]) / 2 end end
  return function(x)
    if not x then return 1 end
    local idx = 1
    for _, c in ipairs(cuts) do if x > c then idx = idx + 1 end end
    return idx
  end
end

-- Can this node take a point now? Uses the game's own answer when given, else the classic rule (5 points in the
-- tree per row, rows 600 apart in y).
local function purchasable(n, spentInTree, minY)
  if n.can ~= nil then return n.can end
  if n.rank >= n.max then return false end
  local row = n.y and math.floor((n.y - minY) / 600 + 0.5) or 0
  return spentInTree >= row * 5
end

-- The plan: { spec, next = { {node, n, why, rank target, now} ... }, wasted = { {node, why} }, unspent }.
local function plan()
  local _, class = UnitClass("player")
  local data = DATA[class]
  local t = G.talents and G.talents.read()
  if not (data and t) then return nil, data and "notree" or "noclass" end
  local idxOf = treeIndexer(t.nodes)
  local spent, bySpell, minY = {}, {}, math.huge
  for _, n in ipairs(t.nodes) do
    local i = idxOf(n.x)
    n.tree = i
    spent[i] = (spent[i] or 0) + (n.rank or 0)
    if n.spell then bySpell[n.spell] = n end
    if n.y and n.y < minY then minY = n.y end
  end
  local best, bestPts = nil, 0
  for i, pts in pairs(spent) do if pts > bestPts then best, bestPts = i, pts end end
  local spec = best and data.trees[best]
  if not spec then
    local chosen = db() and db().spec and db().spec[class]
    spec = (chosen and data.specs[chosen]) and chosen or data.trees[1]
  end
  local out = { spec = spec, next = {}, wasted = {}, unspent = t.unspent or 0 }
  local budget = out.unspent
  for _, p in ipairs(data.specs[spec] or {}) do
    local n = bySpell[p[1]]
    if n and n.rank < math.min(p[2], n.max) then
      local now = budget > 0 and purchasable(n, spent[n.tree] or 0, minY)
      if now then budget = budget - math.min(budget, math.min(p[2], n.max) - n.rank) end
      out.next[#out.next + 1] = { node = n.node, n = n, why = p[3], target = math.min(p[2], n.max), now = now }
      if #out.next >= 6 then break end
    end
  end
  local weapon = mainHand()
  for _, a in ipairs(data.avoid or {}) do
    local n = bySpell[a[1]]
    if n and n.rank > 0 and weapon ~= a[2] then out.wasted[#out.wasted + 1] = { node = n.node, n = n, why = a[3] } end
  end
  return out
end

-- The talent window: Forever's client is retail-like (PlayerSpellsFrame) with an older fallback (ClassTalentFrame).
local function talentsFrame()
  return (PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame) or (ClassTalentFrame and ClassTalentFrame.TalentsFrame)
end

local function buttonFor(tf, nodeID)
  if tf.GetTalentButtonByNodeID then
    local b = try(tf.GetTalentButtonByNodeID, tf, nodeID)
    if b then return b end
  end
  if tf.EnumerateAllTalentButtons then
    for b in tf:EnumerateAllTalentButtons() do
      local id = (b.GetNodeID and try(b.GetNodeID, b)) or b.nodeID
      if id == nodeID then return b end
    end
  end
end

local marks, active, panel, toggle = {}, false, nil, nil
local SPEC_LABEL = { combat = "Combate", assassination = "Asesinato", subtlety = "Sutileza" }

local function markFor(b)
  if marks[b] then return marks[b] end
  local m = CreateFrame("Frame", nil, b)
  m:SetAllPoints(b)
  m:SetFrameLevel(b:GetFrameLevel() + 10)
  m.glow = m:CreateTexture(nil, "OVERLAY")
  m.glow:SetTexture("Interface\\Cooldown\\star4")
  m.glow:SetBlendMode("ADD")
  m.glow:SetPoint("CENTER")
  m.badge = m:CreateTexture(nil, "OVERLAY", nil, 2)
  m.badge:SetSize(18, 18)
  m.badge:SetPoint("TOPRIGHT", 6, 6)
  m.badge:SetTexture("Interface\\Buttons\\WHITE8x8")
  m.num = m:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  m.num:SetPoint("CENTER", m.badge, "CENTER", 0, 0)
  m.num:SetDrawLayer("OVERLAY", 3)
  m:SetScript("OnUpdate", function(self)
    if not self.pulse then return end
    local a = 0.55 + 0.45 * math.sin(GetTime() * 4)
    self.glow:SetAlpha(a)
  end)
  -- The reason in the talent's own tooltip.
  b:HookScript("OnEnter", function(self)
    local mk = marks[self]
    if active and mk and mk:IsShown() and mk.why and GameTooltip:IsOwned(self) then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine("Guía: " .. mk.why, mk.r, mk.g, mk.bl, true)
      GameTooltip:Show()
    end
  end)
  marks[b] = m
  return m
end

local function clearMarks() for _, m in pairs(marks) do m:Hide(); m.why = nil end end

local function showMark(b, kind, num, why)
  local m = markFor(b)
  local w = b:GetWidth() or 40
  m.glow:SetSize(w * 2, w * 2)
  if kind == "now" then
    m.glow:SetVertexColor(0.3, 0.85, 1); m.pulse = true
    m.badge:SetVertexColor(0.12, 0.33, 0.58); m.num:SetTextColor(1, 1, 1)
    m.r, m.g, m.bl = 0.49, 0.78, 0.99
  elseif kind == "later" then
    m.glow:SetVertexColor(0.3, 0.85, 1); m.glow:SetAlpha(0.25); m.pulse = false
    m.badge:SetVertexColor(0.2, 0.2, 0.2); m.num:SetTextColor(0.8, 0.8, 0.8)
    m.r, m.g, m.bl = 0.8, 0.8, 0.8
  else
    m.glow:SetVertexColor(1, 0.15, 0.1); m.glow:SetAlpha(0.7); m.pulse = false
    m.badge:SetVertexColor(0.6, 0.1, 0.1); m.num:SetTextColor(1, 1, 1)
    m.r, m.g, m.bl = 0.97, 0.44, 0.44
  end
  m.num:SetText(num)
  m.why = why
  m:Show()
end

local function ensurePanel(tf)
  if panel then return panel end
  panel = CreateFrame("Frame", nil, tf, "BackdropTemplate")
  panel:SetSize(300, 60)
  local search = tf.SearchBox
  if search and search.GetLeft then
    panel:SetPoint("TOPRIGHT", search, "BOTTOMRIGHT", 0, -8)
  else
    panel:SetPoint("TOPLEFT", tf, "TOPLEFT", 12, -40)
  end
  panel:SetFrameStrata("HIGH")
  if panel.SetBackdrop then
    panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    panel:SetBackdropColor(0.05, 0.05, 0.07, 0.92)
    panel:SetBackdropBorderColor(0.49, 0.78, 0.99, 0.6)
  end
  panel.text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.text:SetPoint("TOPLEFT", 10, -10)
  panel.text:SetWidth(280)
  panel.text:SetJustifyH("LEFT")
  panel.text:SetSpacing(2)
  return panel
end

local function refresh()
  local tf = talentsFrame()
  if not (tf and tf:IsVisible()) then return end
  clearMarks()
  if not active then if panel then panel:Hide() end return end
  local p, why = plan()
  local pn = ensurePanel(tf)
  local lines = {}
  if not p then
    lines[1] = why == "noclass" and "Todavía no tengo sugerencias de talentos para tu clase." or "No pude leer tu árbol de talentos."
  else
    lines[#lines + 1] = "|cffffd100Guía: " .. (SPEC_LABEL[p.spec] or p.spec) .. "|r" ..
      (p.unspent > 0 and ("  ·  " .. p.unspent .. " punto(s) libres") or "")
    local i = 0
    for _, s in ipairs(p.next) do
      i = i + 1
      local b = buttonFor(tf, s.node)
      if b then showMark(b, s.now and "now" or "later", tostring(i), s.why) end
      local color = s.now and "|cff7dc7fc" or "|cff9ca3af"
      lines[#lines + 1] = color .. i .. ". " .. (s.n.name or "?") .. " " .. s.n.rank .. "/" .. s.target .. "|r  " .. s.why ..
        (s.now and "" or " |cff9ca3af(más adelante)|r")
    end
    for _, w in ipairs(p.wasted) do
      local b = buttonFor(tf, w.node)
      if b then showMark(b, "wasted", "!", w.why) end
      lines[#lines + 1] = "|cfff87171! " .. (w.n.name or "?") .. "|r  " .. w.why
    end
    if #p.next == 0 and #p.wasted == 0 then lines[#lines + 1] = "Tu árbol está al día." end
  end
  pn.text:SetText(table.concat(lines, "\n"))
  pn:SetHeight(pn.text:GetStringHeight() + 20)
  pn:Show()
end

local function setup()
  local tf = talentsFrame()
  if not tf or toggle then return end
  -- The guide's shared button (Core.lua G.ui.button), left of the talent search box.
  local function label() toggle:SetLabel(active and "Ocultar sugerencias" or "Sugerir talentos"); toggle:SetOn(active) end
  toggle = G.ui.button(tf, "Sugerir talentos", function()
    active = not active
    local d = db(); if d then d.talentSuggest = active end
    label(); refresh()
  end, "talentos", "Marca qué talentos tomar ahora (celeste, en orden), cuáles vienen después (gris) y los puntos que no te sirven (rojo), con el porqué.")
  local search = tf.SearchBox
  if search and search.GetLeft then
    toggle:SetPoint("RIGHT", search, "LEFT", -14, 0)
  else
    toggle:SetPoint("TOPLEFT", tf, "TOPLEFT", 12, -12)
  end
  local d = db()
  active = d and d.talentSuggest == true or false
  label()
  tf:HookScript("OnShow", function() C_Timer.After(0, refresh) end)
  C_Timer.After(0, refresh)
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "TRAIT_CONFIG_UPDATED", "TRAIT_NODE_CHANGED",
  "TRAIT_TREE_CURRENCY_INFO_UPDATED", "PLAYER_TALENT_UPDATE", "PLAYER_EQUIPMENT_CHANGED" }) do pcall(ev.RegisterEvent, ev, e) end
local pending = false
ev:SetScript("OnEvent", function(_, event)
  if event == "ADDON_LOADED" or event == "PLAYER_ENTERING_WORLD" then pcall(setup) end
  if toggle and not pending then
    pending = true
    C_Timer.After(0.1, function() pending = false; pcall(refresh) end)
  end
end)

G.talentSuggest = { plan = plan, refresh = function() pcall(refresh) end }
