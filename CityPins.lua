-- Guía Forever: town and city services on the world map (what the guards point you to).
-- Shows your class trainers, weapon masters, profession trainers, bank, auction house, inn, flight, stable
-- masters and repair vendors in every Alliance-friendly town and city. Hover for who it is; click to set a waypoint.
-- Pins are our own frames on the map canvas; data comes from DataCity.lua.
local G = GuiaForever
G.cityMap = {}

local KIND = {
  banker = { icon = "Interface\\Minimap\\Tracking\\Banker", label = "Banco" },
  auctioneer = { icon = "Interface\\Minimap\\Tracking\\Auctioneer", label = "Casa de subastas" },
  innkeeper = { icon = "Interface\\Minimap\\Tracking\\Innkeeper", label = "Posada (piedra de hogar)" },
  flight = { icon = "Interface\\Minimap\\Tracking\\FlightMaster", label = "Maestro de vuelo" },
  stablemaster = { icon = "Interface\\Minimap\\Tracking\\StableMaster", label = "Maestro de establos" },
  mailbox = { icon = "Interface\\Minimap\\Tracking\\Mailbox", label = "Buzón" },
  repair = { icon = "Interface\\Minimap\\Tracking\\Repair", label = "Reparar y vender" },
  class = { icon = "Interface\\Minimap\\Tracking\\Class", label = "Instructor de tu clase" },
  weapon = { icon = "Interface\\Icons\\INV_Sword_04", label = "Maestro de armas" },
  profession = { icon = "Interface\\Minimap\\Tracking\\Profession", label = "Instructor de profesión" },
}

local CLASSES = { Warrior = "WARRIOR", Paladin = "PALADIN", Hunter = "HUNTER", Rogue = "ROGUE", Priest = "PRIEST",
  Mage = "MAGE", Warlock = "WARLOCK", Druid = "DRUID", Shaman = "SHAMAN" }
local CLASS_ES = { Warrior = "guerrero", Paladin = "paladín", Hunter = "cazador", Rogue = "pícaro", Priest = "sacerdote",
  Mage = "mago", Warlock = "brujo", Druid = "druida", Shaman = "chamán" }
local PROF_ES = { Alchemy = "Alquimia", Blacksmithing = "Herrería", Armorsmith = "Forjador de armaduras",
  Weaponsmith = "Forjador de armas", Cooking = "Cocina", Enchanting = "Encantamiento", Engineering = "Ingeniería",
  ["Gnomish Engineering"] = "Ingeniería gnómica", ["Goblin Engineering"] = "Ingeniería goblin",
  ["First Aid"] = "Primeros auxilios", Fishing = "Pesca", Herbalism = "Herboristería", Leatherworking = "Peletería",
  Mining = "Minería", Skinning = "Desuello", Tailoring = "Sastrería" }
-- Researched weapon lists (Warcraft Tavern / Wowhead classic weapon trainer guides).
local WEAPONS_TAUGHT = {
  ["Woo Ping"] = "Espadas (1 y 2 manos), armas de asta, bastones, ballestas",
  ["Buliwyf Stonehand"] = "Hachas y mazas (1 y 2 manos), armas de puño, armas de fuego",
}

local function enabled() local DB = G.core and G.core.db(); return not (DB and DB.cityPins == false) end

-- Which pins this character cares about, and how to describe each one.
local function describe(kind, name, title)
  if kind == "repair" then return kind, "Reparar y vender" .. (title and title ~= "" and (" (" .. title .. ")") or "") end
  if kind ~= "trainer" then return kind, KIND[kind] and KIND[kind].label or title end
  title = title or ""
  if title == "Weapon Master" then
    local taught = WEAPONS_TAUGHT[name]
    return "weapon", "Maestro de armas" .. (taught and (": " .. taught) or "") .. " (10 de plata cada arma)"
  end
  local what = title:match("^(.-) Trainer$")
  if not what then return end
  local _, myClass = UnitClass("player")
  if CLASSES[what] then
    if CLASSES[what] ~= myClass then return end
    return "class", "Instructor de " .. CLASS_ES[what] .. ": hechizos y talentos"
  end
  if what == "Pet" then if myClass ~= "HUNTER" then return end return "class", "Instructor de mascotas" end
  if what == "Portal" then if myClass ~= "MAGE" then return end return "class", "Instructor de portales" end
  if PROF_ES[what] then return "profession", "Instructor de " .. PROF_ES[what] end
  return "profession", title
end

-- World position -> this client's map position, through the client's own map bounds (G.mapBounds in Core.lua).
-- C_Map world vectors are (north X, west Y), the same axes as the database's worldX / worldY.
local mapBounds = G.mapBounds
local function position(mapID, e)
  local b = e[6] and mapBounds(mapID)
  local cont = G.cityPinsContinent and G.cityPinsContinent[mapID]
  if b and (cont == nil or b.inst == nil or b.inst == cont) then
    return (b.left - e[7]) / b.w * 100, (b.top - e[6]) / b.h * 100
  end
  return e[1], e[2]
end

local pins = {}
local function pinFrame(i)
  local p = pins[i]
  if p then return p end
  p = CreateFrame("Button", nil, UIParent)
  p:SetSize(18, 18)
  p.icon = p:CreateTexture(nil, "ARTWORK")
  p.icon:SetAllPoints()
  p:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(self.name or "?", 1, 0.82, 0)
    if self.text then GameTooltip:AddLine(self.text, 1, 1, 1, true) end
    GameTooltip:AddLine("Clic: marcar el camino", 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end)
  p:SetScript("OnLeave", function() GameTooltip:Hide() end)
  p:SetScript("OnClick", function(self)
    if not G.setWaypoint(self.mapID, self.x and self.x / 100, self.y and self.y / 100) then return end
    if G.core then G.core.msg("Camino marcado: " .. (self.name or "?") .. ".") end
  end)
  pins[i] = p
  return p
end

local function hideAll() for _, p in ipairs(pins) do p:Hide() end end

local provider
local function refresh()
  hideAll()
  if not (provider and enabled() and G.cityPins) then return end
  local map = provider:GetMap()
  if not map then return end
  local mapID = map:GetMapID()
  local list = mapID and G.cityPins[mapID]
  if not list then return end
  local canvas = map:GetCanvas()
  local w, h = canvas:GetWidth(), canvas:GetHeight()
  local scale = 1 / ((map.GetCanvasScale and map:GetCanvasScale()) or 1)
  local n = 0
  for _, e in ipairs(list) do
    local kind, text = describe(e[3], e[4], e[5])
    local px, py = position(mapID, e)
    if kind and KIND[kind] and px > 0 and px < 100 and py > 0 and py < 100 then
      n = n + 1
      local p = pinFrame(n)
      p:SetParent(canvas)
      p:SetFrameLevel(canvas:GetFrameLevel() + 2000)
      p:SetScale(scale)
      local big = kind == "class" or kind == "weapon"
      p:SetSize(big and 22 or 16, big and 22 or 16)
      p.icon:SetTexture(KIND[kind].icon)
      p.mapID, p.x, p.y, p.name, p.text = mapID, px, py, e[4], text
      p:ClearAllPoints()
      p:SetPoint("CENTER", canvas, "TOPLEFT", (px / 100) * w / scale, -(py / 100) * h / scale)
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

function G.cityMap.refresh() if provider then provider:RefreshAllData() end end
function G.cityMap.available() return provider ~= nil end
