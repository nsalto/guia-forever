-- Guía Forever: quest objective / completion notices (sound + centre-screen line).
local G = GuiaForever

local known, primed = {}, false
local QUEST_SOUND = { "UI_WORLDQUEST_COMPLETE", "IG_QUEST_LIST_COMPLETE", "READY_CHECK" }
local OBJECTIVE_SOUND = { "UI_QUEST_ROLLING_FORWARD_01", "IG_QUEST_LIST_SELECT" }

local function playFirst(keys)
  if not (PlaySound and SOUNDKIT) then return end
  local db = G.core and G.core.db()
  if db and db.notifySound == false then return end
  for _, k in ipairs(keys) do
    if SOUNDKIT[k] then pcall(PlaySound, SOUNDKIT[k]); return end
  end
end

local function usable(v)
  if issecretvalue and issecretvalue(v) then return nil end
  return type(v) == "string" and v ~= "" and v or nil
end

local function warn(text, r, g, b)
  if UIErrorsFrame then UIErrorsFrame:AddMessage(text, r or 1, g or 0.82, b or 0) end
end

-- Modes: "listas" (default: quest ready, failed, new objective), "todo" (also each finished objective), "no".
local function mode()
  local db = G.core.db()
  local m = db and db.notify
  if m == false then return "no" end
  return (m == "todo" or m == "no") and m or "listas"
end
local function enabled() return mode() ~= "no" end

G.notify = {}
G.notify.mode = function() return mode() end
G.notify.label = function() return ({ listas = "solo misiones listas", todo = "todo", no = "apagados" })[mode()] end
function G.notify.command(arg)
  local db = G.core.db()
  if arg == "todo" or arg == "no" or arg == "listas" then db.notify = arg
  else db.notify = ({ listas = "todo", todo = "no", no = "listas" })[mode()] end
  local names = { listas = "solo misiones listas y objetivos nuevos", todo = "todo, también cada objetivo", no = "apagados" }
  G.core.msg("Avisos de misión: " .. names[mode()] .. ". Cambiá con /guia avisos [listas|todo|no].")
end

local function scan()
  local core = G.core
  local seen = {}
  for _, e in ipairs(core.questEntries()) do
    if e.id then
      seen[e.id] = true
      local objs = core.questObjectives(e)
      local state = { complete = e.complete, failed = e.failed, n = #objs, done = {} }
      for i, o in ipairs(objs) do state.done[i] = o.done and true or false end
      local old = known[e.id]
      if primed and old and enabled() then
        local title = usable(e.title) or "?"
        if state.failed and not old.failed then
          warn("Misión fallada: " .. title .. " (abandonala y volvé a tomarla)", 1, 0.3, 0.3)
        elseif state.complete and not old.complete then
          playFirst(QUEST_SOUND)
          warn("¡Misión lista! " .. title .. ": volvé a entregarla", 0.3, 0.9, 0.5)
        elseif state.n > old.n then
          playFirst(OBJECTIVE_SOUND)
          warn("Nuevo objetivo en " .. title, 0.5, 0.8, 1)
        elseif mode() == "todo" then
          for i, d in ipairs(state.done) do
            if d and old.done[i] == false then
              playFirst(OBJECTIVE_SOUND)
              local text = objs[i] and usable(objs[i].text)
              if text then warn("Hecho: " .. text) end
            end
          end
        end
      end
      known[e.id] = state
    end
  end
  for id in pairs(known) do if not seen[id] then known[id] = nil end end
  primed = true
end

local pending = false
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("QUEST_LOG_UPDATE")
f:SetScript("OnEvent", function(_, event)
  if not G.core then return end
  if event == "PLAYER_ENTERING_WORLD" then
    -- First scan only records state: no notices for what was already done at login.
    C_Timer.After(3, function() pcall(scan) end)
    return
  end
  if pending or not primed then return end
  pending = true
  C_Timer.After(0.3, function() pending = false; pcall(scan) end)
end)
