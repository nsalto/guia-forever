-- Guía Forever: change layer ("capa"). Layers are swapped the usual way: someone on another layer of your zone invites
-- you, the game moves you to their layer, you leave the group. This file automates the three steps:
--   1. Guía users share a hidden chat channel. "/guia capa" asks there; a free Guía user in your zone on a different
--      layer offers, you pick the first offer, they invite you.
--   2. Nobody answers in 8 s: a link asks for an invite in the zone's General chat ("inv layer"), like people do by hand.
--   3. The invite is accepted for you (only from the helper you picked, or anyone for 60 s after asking in chat), the
--      new layer is read from the NPCs around you (PvP.lua) and you leave the group.
-- Helping is on by default and only happens when you are out of combat, solo, outside instances and your layer is known;
-- the helper leaves the group too if the other player has not left after 60 s.
local G = GuiaForever
G.layerHop = {}

local PREFIX, CHANNEL = "GUIAFL", "GuiaForeverCapas"
local ASK_WAIT, HOP_TIMEOUT, PUBLIC_WINDOW, HELP_COOLDOWN = 8, 45, 60, 30

local function try(fn, ...) if type(fn) ~= "function" then return end local ok, a, b, c = pcall(fn, ...); if ok then return a, b, c end end
local function msg(text) if G.core and G.core.msg then G.core.msg(text) end end
local function settings() local d = G.core and G.core.db(); return d and d.pvp or {} end
local function helpOn() return settings().hopHelp ~= false end
local function inGroup() return G.core and G.core.inGroup() end
local function inInstance() local _, kind = IsInInstance(); return kind and kind ~= "none" end
-- Caves, towns and other sub-maps count as the zone they belong to, so two players in the same zone always match.
local function zoneOf(mapID)
  local ZONE = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3
  for _ = 1, 5 do
    local info = mapID and C_Map and try(C_Map.GetMapInfo, mapID)
    if not info or not info.mapType or info.mapType <= ZONE or not info.parentMapID or info.parentMapID == 0 then return mapID end
    mapID = info.parentMapID
  end
  return mapID
end
local function zoneMap() return zoneOf(C_Map and try(C_Map.GetBestMapForUnit, "player")) end
-- The layer only changes on a hop or a loading screen (PvP.lua forgets it then), so an old reading is still good.
local function myLayer()
  if not (G.pvp and G.pvp.layer) then return nil end
  local id, mapID, at = G.pvp.layer()
  if id and at and GetTime() - at < 1800 then return id, zoneOf(mapID) end
end
local function short(id) return id and tostring(id % 10000) or "?" end

-- ---------------------------------------------------------------- hidden channel
local function channelIndex() local id = GetChannelName(CHANNEL); return (id and id > 0) and id or nil end
local function hideChannel()
  for i = 1, (NUM_CHAT_WINDOWS or 10) do
    local cf = _G["ChatFrame" .. i]
    if cf and ChatFrame_RemoveChannel then pcall(ChatFrame_RemoveChannel, cf, CHANNEL) end
  end
end
local function join()
  if channelIndex() then hideChannel(); return end
  if JoinTemporaryChannel then try(JoinTemporaryChannel, CHANNEL) elseif JoinChannelByName then try(JoinChannelByName, CHANNEL) end
  C_Timer.After(2, hideChannel)
end
local function send(text, target)
  local f = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
  if not f then return end
  if target then try(f, PREFIX, text, "WHISPER", target); return end
  local idx = channelIndex()
  if idx then try(f, PREFIX, text, "CHANNEL", idx) end
end

-- ---------------------------------------------------------------- asking (you)
-- hop.state: "asking" (waiting for offers), "invited" (helper picked), "public" (asked in General), "joined" (in their group)
local hop = nil

local function finish(text)
  if text then msg(text) end
  hop = nil
  if G.core then G.core.render() end
end

local function leave()
  if C_PartyInfo and C_PartyInfo.LeaveParty then try(C_PartyInfo.LeaveParty) elseif LeaveParty then try(LeaveParty) end
end

function G.layerHop.start()
  if hop and hop.state ~= "noOffer" then msg("Ya estoy buscando otra capa... (/guia capa cancelar)"); return end
  hop = nil
  if InCombatLockdown() then msg("Fuera de combate."); return end
  if inInstance() then msg("Dentro de una instancia no hay capas."); return end
  if inGroup() then msg("Salí del grupo primero: cambiar de capa se hace entrando al grupo de alguien de otra capa."); return end
  local id = myLayer()
  if G.pvp and G.pvp.scanLayer then G.pvp.scanLayer(); id = myLayer() end
  join()
  hop = { state = "asking", from = id, map = zoneMap(), at = GetTime() }
  send("Q" .. (hop.map or 0) .. "," .. (id or 0))
  msg("Buscando a alguien con la Guía en otra capa de tu zona" .. (id and (" (estás en la #" .. short(id) .. ")") or "") .. "...")
  if G.core then G.core.render() end
  C_Timer.After(ASK_WAIT, function()
    if hop and hop.state == "asking" then
      hop.state = "noOffer"
      G.layerHop.probe("quiet")
      msg("Nadie con la Guía respondió. " .. G.core.actionLink("capa", 1, "Pedir invitación en el chat General") .. " o probá de nuevo en un rato.")
      if G.core then G.core.render() end
    end
  end)
end

-- Typed in General by a click on the chat link (sending to a public channel needs your click).
local function askPublic()
  if inGroup() then msg("Ya estás en un grupo."); return end
  local id = GetChannelName(1)
  if not (id and id > 0) then msg("No encontré el canal General."); return end
  try(SendChatMessage, "inv layer pls", "CHANNEL", nil, id)
  hop = hop or { from = myLayer(), map = zoneMap() }
  hop.state, hop.at = "public", GetTime()
  msg("Pedido en el General. Acepto la primera invitación que llegue en " .. PUBLIC_WINDOW .. " s.")
  C_Timer.After(PUBLIC_WINDOW, function() if hop and hop.state == "public" then finish("Nadie invitó. Probá de nuevo más tarde.") end end)
end

function G.layerHop.cancel()
  if hop and hop.state == "joined" then leave() end
  finish("Cambio de capa cancelado.")
end

-- After joining: wait until the NPCs around you report a new layer, then leave.
local function watchJoined()
  local started = GetTime()
  local ticker
  ticker = C_Timer.NewTicker(1, function()
    if not hop or hop.state ~= "joined" then ticker:Cancel(); return end
    if G.pvp and G.pvp.scanLayer then G.pvp.scanLayer() end
    local id = myLayer()
    local moved = id and ((hop.target and id == hop.target) or (hop.from and id ~= hop.from))
    local blind = not (hop.from or hop.target) and GetTime() - started > 10 -- no layer known before: give it 10 s
    if blind then
      ticker:Cancel()
      leave()
      finish("Listo, salí del grupo. No pude leer tu capa anterior para confirmarlo: pasá el mouse por un bicho y mirá Ahora.")
    elseif moved then
      ticker:Cancel()
      C_Timer.After(2, function()
        leave()
        finish("¡Listo! Ahora estás en la capa #" .. short(id) .. ". Salí del grupo.")
      end)
    elseif GetTime() - started > HOP_TIMEOUT then
      ticker:Cancel()
      leave()
      finish("No me cambió de capa a tiempo (puede tardar si hay combate cerca). Salí del grupo; probá otra vez.")
    end
  end)
end

-- ---------------------------------------------------------------- helping (others)
local lastHelp, helping = 0, nil -- helping = { name, at }

-- Why you cannot help someone in mapID / theirLayer right now (a reason code), or nil when you can.
local function whyNot(mapID, theirLayer)
  if not helpOn() then return "apagado" end
  if hop then return "ocupado" end
  if inGroup() then return "grupo" end
  if inInstance() then return "instancia" end
  if InCombatLockdown() then return "combate" end
  if GetTime() - lastHelp < HELP_COOLDOWN then return "espera" end
  local id, myMap = myLayer()
  if not id then return "sincapa" end
  if myMap ~= zoneMap() or mapID ~= myMap then return "otrazona" end
  if id == theirLayer then return "mismacapa" end
end
local function canHelp(mapID, theirLayer) return whyNot(mapID, theirLayer) == nil end

-- ---------------------------------------------------------------- "who has the guide?" test
local REASON = { apagado = "tiene la ayuda apagada", ocupado = "está cambiando de capa", grupo = "está en un grupo",
  instancia = "está en una instancia", combate = "está en combate", espera = "acaba de ayudar a otro (30 s)",
  sincapa = "su Guía no leyó su capa (que pase el mouse por un bicho)", otrazona = "está en otra zona",
  mismacapa = "está en TU misma capa" }
local VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata and try(C_AddOns.GetAddOnMetadata, "GuiaForever", "Version"))
  or (GetAddOnMetadata and try(GetAddOnMetadata, "GuiaForever", "Version")) or "?"
local probe -- the test running now: { at, replies = { name = text }, n }
local known, knownAt = {}, 0 -- last test's answers, for the button's list: { name = text }
local onKnown -- called when an answer arrives (refreshes the open tooltip)

-- mode: "print" (typed test: announce and print), "quiet" (print the result only), "silent" (only fill the list)
function G.layerHop.probe(mode)
  join()
  local id = myLayer()
  probe = { at = GetTime(), replies = {}, n = 0 }
  known, knownAt = {}, GetTime()
  send("W" .. (zoneMap() or 0) .. "," .. (id or 0))
  if mode == "print" then msg("Buscando a otros con la Guía (canal " .. (channelIndex() and "conectado" or "SIN CONECTAR") .. ")...") end
  C_Timer.After(4, function()
    if not probe then return end
    if mode == "silent" then probe = nil; return end
    local zoneName = (C_Map and try(C_Map.GetMapInfo, zoneMap() or 0) or {}).name or "?"
    msg("Prueba de capas. Vos: " .. zoneName .. ", capa " .. (id and ("#" .. short(id)) or "sin leer") .. ", versión " .. VERSION .. ".")
    if probe.n == 0 then
      msg("Nadie con la Guía nueva respondió. Tus amigos necesitan esta versión (la del zip de hoy) y entrar al juego de nuevo.")
    else
      for name, text in pairs(probe.replies) do msg("  " .. name .. ": " .. text) end
    end
    probe = nil
  end)
end


local function invite(name)
  if C_PartyInfo and C_PartyInfo.InviteUnit then try(C_PartyInfo.InviteUnit, name) elseif InviteUnit then try(InviteUnit, name) end
end

local handlers = {}
handlers.Q = function(sender, body) -- someone wants to change: offer if you can
  local mapID, theirLayer = body:match("^(%d+),(%d+)$")
  if canHelp(tonumber(mapID), tonumber(theirLayer)) then send("O" .. (myLayer() or 0), sender) end
end
handlers.O = function(sender, body) -- an offer for your request: take the first one
  if not hop or hop.state ~= "asking" then return end
  local theirLayer = tonumber(body)
  if hop.from and theirLayer == hop.from then return end
  hop.state, hop.helper, hop.target = "invited", sender, theirLayer
  send("A", sender)
  msg(sender .. " te va a invitar a la capa #" .. short(theirLayer) .. ". Acepto solo.")
  C_Timer.After(15, function() if hop and hop.state == "invited" then finish("No llegó la invitación de " .. sender .. ". Probá otra vez.") end end)
end
handlers.W = function(sender, body) -- the test: say who you are and whether you could help
  local mapID, theirLayer = body:match("^(%d+),(%d+)$")
  local id, myMap = myLayer()
  send("w" .. VERSION .. "," .. (myMap or zoneMap() or 0) .. "," .. (id or 0) .. "," .. (whyNot(tonumber(mapID), tonumber(theirLayer)) or "ok"), sender)
end
handlers.w = function(sender, body)
  if not probe then return end
  local ver, mapID, id, why = body:match("^([^,]*),(%d+),(%d+),(%a+)$")
  if not ver then return end
  local zone = (C_Map and try(C_Map.GetMapInfo, tonumber(mapID)) or {}).name or "?"
  local text = zone .. ", capa " .. (tonumber(id) ~= 0 and ("#" .. short(tonumber(id))) or "sin leer") .. " · "
    .. (why == "ok" and "|cff40ff40te puede cambiar de capa|r" or ("|cffff8040no puede: " .. (REASON[why] or why) .. "|r"))
    .. " (v" .. ver .. ")"
  if not probe.replies[sender] then probe.n = probe.n + 1 end
  probe.replies[sender] = text
  known[sender] = text
  if onKnown then onKnown() end
end
handlers.A = function(sender) -- you were picked: invite and leave later if they stay
  if not canHelp(zoneMap(), -1) then return end
  lastHelp, helping = GetTime(), { name = sender, at = GetTime() }
  invite(sender)
  C_Timer.After(60, function()
    if helping and helping.name == sender and inGroup() and (GetNumGroupMembers and GetNumGroupMembers() or 0) <= 2 then leave() end
    helping = nil
  end)
end

-- ---------------------------------------------------------------- events
local f = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "CHAT_MSG_ADDON", "PARTY_INVITE_REQUEST", "GROUP_ROSTER_UPDATE" }) do pcall(f.RegisterEvent, f, e) end
f:SetScript("OnEvent", function(_, event, a1, a2, a3, a4)
  if event == "PLAYER_ENTERING_WORLD" then
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then try(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
    C_Timer.After(8, join)
    C_Timer.After(20, function() G.layerHop.probe("silent") end)
  elseif event == "CHAT_MSG_ADDON" then
    if a1 ~= PREFIX or not a2 or not a4 then return end
    local name = a4:gsub("%-.*$", "")
    if name == UnitName("player") then return end
    local h = handlers[a2:sub(1, 1)]
    if h then pcall(h, name, a2:sub(2)) end
  elseif event == "PARTY_INVITE_REQUEST" then
    local from = a1 and a1:gsub("%-.*$", "")
    if hop and ((hop.state == "invited" and from == hop.helper) or hop.state == "public") then
      hop.helper = hop.helper or from
      try(AcceptGroup)
      if StaticPopup_Hide then StaticPopup_Hide("PARTY_INVITE") end
      hop.state = "joined"
      watchJoined()
    end
  elseif event == "GROUP_ROSTER_UPDATE" then
    if helping and not inGroup() then helping = nil end
  end
end)

-- Key binding (Esc > Opciones > Atajos > Guía Forever), see Bindings.xml.
BINDING_HEADER_GUIAFOREVER = "Guía Forever"
BINDING_NAME_GUIAFOREVER_CAPA = "Cambiar de capa"

G.linkHandlers = G.linkHandlers or {}
G.linkHandlers.capa = function(n)
  if n == 1 then askPublic() elseif n == 2 then G.layerHop.cancel() else G.layerHop.start() end
end

function G.layerHop.command(arg)
  if arg == "cancelar" or arg == "no" then G.layerHop.cancel()
  elseif arg == "boton" or arg == "botón" then
    G.layerHop.toggleButton()
    msg("Botón de capa en pantalla: " .. (G.layerHop.buttonShown() and "visible (arrastralo a donde quieras)" or "oculto") .. ".")
  elseif arg == "prueba" or arg == "quien" then G.layerHop.probe("print")
  elseif arg == "ayudar" then
    local p = G.core.db().pvp
    p.hopHelp = not helpOn()
    msg("Ayudar a otros con la Guía a cambiar de capa: " .. (helpOn() and "sí" or "no") .. ".")
  else G.layerHop.start() end
end

-- Line for the "Ahora" tab: your layer and a button to change it.
G.nowSections = G.nowSections or {}
table.insert(G.nowSections, function()
  local core, C = G.core, G.core.C
  if inInstance() then return end
  local id = myLayer()
  local state = hop and ({ asking = "buscando a alguien...", invited = "esperando la invitación...", public = "pedido en el General...",
    joined = "en el grupo, esperando el cambio...", noOffer = "nadie con la Guía respondió" })[hop.state]
  if state then
    core.L(C.gold .. "Capa: " .. C.r .. state .. "  " .. core.actionLink("capa", 2, "Cancelar"))
  else
    core.L(C.grey .. "Capa " .. (id and ("#" .. short(id)) or "sin leer") .. C.r .. "  " .. core.actionLink("capa", 0, "Cambiar de capa"))
  end
end)

-- ---------------------------------------------------------------- on-screen button
-- A small movable button: left click changes layer (or cancels while it works), drag to move, right click hides it
-- (bring it back in Ajustes > PvP or with /guia capa boton). Shows your layer under the icon.
local btn
local STATE_TEXT = { asking = "buscando...", invited = "invitando...", public = "en General...", joined = "cambiando...", noOffer = "nadie" }

local function btnShown() local p = settings(); return p.hopButton ~= false end

local function updateButton()
  if not btn then return end
  if not btnShown() or inInstance() then btn:Hide(); return end
  btn:Show()
  local working = hop and hop.state ~= "noOffer"
  local id = myLayer()
  btn.label:SetText(working and ("|cffffd100" .. STATE_TEXT[hop.state] .. "|r") or (hop and "|cffff8040nadie|r")
    or (id and ("capa #" .. short(id)) or "|cff9ca3afcapa ?|r"))
  btn.icon:SetDesaturated(inGroup() and not working)
  btn.glow:SetShown(working and true or false)
end

local function createButton()
  if btn or not (G.core and G.core.db()) then return end
  btn = CreateFrame("Button", "GuiaForeverLayerButton", UIParent)
  btn:SetSize(34, 34)
  btn:SetMovable(true)
  btn:SetClampedToScreen(true)
  btn:RegisterForDrag("LeftButton")
  btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  btn.icon = btn:CreateTexture(nil, "ARTWORK")
  btn.icon:SetAllPoints()
  btn.icon:SetTexture("Interface\\Icons\\Spell_Arcane_Blink")
  btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  local border = btn:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
  border:SetPoint("TOPLEFT", -12, 12)
  border:SetPoint("BOTTOMRIGHT", 12, -12)
  btn.glow = btn:CreateTexture(nil, "OVERLAY")
  btn.glow:SetTexture("Interface\\Buttons\\CheckButtonHilight")
  btn.glow:SetBlendMode("ADD")
  btn.glow:SetAllPoints()
  btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  btn.label:SetPoint("TOP", btn, "BOTTOM", 0, -2)

  local p = G.core.db().pvp
  local pos = p.hopButtonPos
  if pos then btn:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3]) else btn:SetPoint("CENTER", UIParent, "CENTER", 0, -180) end

  btn:SetScript("OnDragStart", function(self) if not InCombatLockdown() then self:StartMoving() end end)
  btn:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, _, x, y = self:GetPoint()
    G.core.db().pvp.hopButtonPos = { point, x, y }
  end)
  btn:SetScript("OnClick", function(_, mouse)
    if mouse == "RightButton" then
      G.core.db().pvp.hopButton = false
      msg("Botón de capa oculto. Volvé a mostrarlo con /guia capa boton o en Ajustes > PvP.")
    elseif hop and hop.state ~= "noOffer" then G.layerHop.cancel()
    else G.layerHop.start() end
    updateButton()
  end)
  local function showTip(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Cambiar de capa", 1, 0.82, 0)
    local id = myLayer()
    GameTooltip:AddLine("Tu capa: " .. (id and ("#" .. short(id)) or "sin leer (pasá el mouse por un bicho)"), 1, 1, 1)
    if inGroup() and not hop then GameTooltip:AddLine("Estás en un grupo: salí primero.", 1, 0.5, 0.25) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Con la Guía conectados:", 1, 0.82, 0)
    local names = {}
    for name in pairs(known) do names[#names + 1] = name end
    table.sort(names)
    if #names == 0 then
      GameTooltip:AddLine(probe and "buscando..." or "nadie con esta versión", 0.6, 0.6, 0.6)
    end
    for _, name in ipairs(names) do GameTooltip:AddLine(name .. ": " .. known[name], 1, 1, 1, true) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Clic: cambiar (clic otra vez: cancelar)", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("Arrastrar: mover · Clic derecho: ocultar", 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end
  btn:SetScript("OnEnter", function(self)
    if not probe and GetTime() - knownAt > 30 then G.layerHop.probe("silent") end
    onKnown = function() if GameTooltip:IsOwned(self) then showTip(self) end end
    showTip(self)
    C_Timer.After(4.2, onKnown) -- redraw when the test ends ("buscando..." -> result)
  end)
  btn:SetScript("OnLeave", function() onKnown = nil; GameTooltip:Hide() end)
  local t = 0
  btn:SetScript("OnUpdate", function(_, e) t = t + e; if t >= 0.5 then t = 0; updateButton() end end)
  -- OnUpdate stops while hidden: a ticker brings the button back when it should show again.
  C_Timer.NewTicker(2, updateButton)
  updateButton()
end

function G.layerHop.toggleButton(v)
  local p = G.core.db().pvp
  if v == nil then v = not btnShown() end
  p.hopButton = v and true or false
  createButton()
  updateButton()
end
G.layerHop.buttonShown = btnShown

local bf = CreateFrame("Frame")
bf:RegisterEvent("PLAYER_ENTERING_WORLD")
bf:SetScript("OnEvent", function() C_Timer.After(1, function() createButton(); updateButton() end) end)
