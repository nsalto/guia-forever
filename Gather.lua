-- Guía Forever: "Conseguir": where to get what a recipe needs. Pick a recipe (in the profession window, in the
-- Profesiones section of the guide, or /guia conseguir <nombre>) and the guide counts what you are missing (bags and
-- bank), finds the place closest to you that has the most of it together (creatures of your level, herb and ore
-- nodes, containers), then the next place for what is left, and points the arrow there. Vendor reagents send you to
-- the profession's trainer area (the supply vendors stand there); skinned leather and fish get a short note.
-- Data: DataGather.lua (tools/build_gather.py, from forever-db) and DataRecipes.lua (the Forever client).
local G = GuiaForever

local function try(fn, ...) if type(fn) ~= "function" then return end local ok, a, b, c, d = pcall(fn, ...); if ok then return a, b, c, d end end
local function secret(v) return issecretvalue and issecretvalue(v) end
local function say(text) if G.core and G.core.msg then G.core.msg(text) else print("Guía: " .. text) end end

local GX = {}
G.gather = GX

local SKILL = { [185] = "Cocina", [165] = "Peletería", [197] = "Sastrería", [164] = "Herrería", [171] = "Alquimia",
  [202] = "Ingeniería", [333] = "Encantamiento", [129] = "Primeros auxilios", [755] = "Joyería", [186] = "Minería" }
local SKILL_BY_NAME = {}
for id, name in pairs(SKILL) do SKILL_BY_NAME[name] = id end
SKILL_BY_NAME["Cooking"], SKILL_BY_NAME["Leatherworking"], SKILL_BY_NAME["Tailoring"] = 185, 165, 197
SKILL_BY_NAME["Blacksmithing"], SKILL_BY_NAME["Alchemy"], SKILL_BY_NAME["Engineering"] = 164, 171, 202
SKILL_BY_NAME["Enchanting"], SKILL_BY_NAME["First Aid"] = 333, 129
local TRAINER = { [185] = "Cooking Trainer", [197] = "Tailoring Trainer", [164] = "Blacksmithing Trainer",
  [171] = "Alchemy Trainer", [202] = "Engineering Trainer", [333] = "Enchanting Trainer", [165] = "Leatherworking Trainer" }
local ENEMY_CAPITALS = { Alliance = { [1454] = true, [1456] = true, [1458] = true }, Horde = { [1453] = true, [1455] = true, [1457] = true } }
local NEAR = 250        -- yards: reagents whose spots are this close to a stop are farmed at that stop
local MAX_STOPS = 4

-- ---------------------------------------------------------------- recipes
local recipes, byCreated
local function index()
  if recipes then return end
  recipes, byCreated = {}, {}
  local seen = {}
  for item, rows in pairs(G.itemRecipes or {}) do
    for _, r in ipairs(rows) do
      local key = r[1] .. ":" .. r[5] .. ":" .. r[6]
      local rec = seen[key]
      if not rec then
        rec = { skill = r[1], yellow = r[2], grey = r[3], name = r[5], created = r[6], reagents = {} }
        seen[key] = rec
        recipes[#recipes + 1] = rec
      end
      rec.reagents[#rec.reagents + 1] = { item = item, count = r[4] }
    end
  end
  table.sort(recipes, function(a, b)
    if a.skill ~= b.skill then return a.skill < b.skill end
    if a.yellow ~= b.yellow then return a.yellow < b.yellow end
    return a.name < b.name
  end)
  for i, rec in ipairs(recipes) do
    rec.idx = i
    table.sort(rec.reagents, function(a, b) return a.item < b.item end)
    if rec.created and rec.created > 0 and not byCreated[rec.created] then byCreated[rec.created] = rec end
  end
end

local function fold(s)
  s = s:lower()
  for a, b in pairs({ ["á"] = "a", ["é"] = "e", ["í"] = "i", ["ó"] = "o", ["ú"] = "u", ["ñ"] = "n", ["ü"] = "u" }) do s = s:gsub(a, b) end
  return s
end

function GX.findRecipe(text)
  index()
  local q = fold(text or "")
  if q == "" then return nil end
  local best
  for _, rec in ipairs(recipes) do
    local n = fold(rec.name)
    if n == q then return rec end
    if not best and n:find(q, 1, true) then best = rec end
  end
  return best
end

-- Every reagent has a known source (a place, a vendor, skinning, fishing, or a recipe of its own). Leaves out
-- holiday and drop-only recipes the guide could not help with.
local function obtainable(rec)
  for _, r in ipairs(rec.reagents) do
    if not ((G.gatherData and G.gatherData[r.item]) or byCreated[r.item]) then return false end
  end
  return true
end

-- Recipes worth making at your current skill: the ones that still give points, the closest to turning grey last.
function GX.recipesFor(skillName, rank, limit)
  index()
  local skill = SKILL_BY_NAME[skillName]
  if not skill then return {} end
  local out = {}
  for _, rec in ipairs(recipes) do
    if rec.skill == skill and rec.yellow > 0 and rank < rec.grey and rec.yellow <= rank + 25 and rec.yellow >= rank - 40
      and obtainable(rec) then
      out[#out + 1] = rec
    end
  end
  table.sort(out, function(a, b)
    local ao, bo = a.yellow > rank, b.yellow > rank -- orange first: a point every craft
    if ao ~= bo then return ao end
    return a.yellow < b.yellow
  end)
  while #out > (limit or 4) do table.remove(out) end
  return out
end

-- ---------------------------------------------------------------- items and positions
local function itemName(id)
  local n = (C_Item and C_Item.GetItemNameByID and try(C_Item.GetItemNameByID, id)) or (GetItemInfo and try(GetItemInfo, id))
  if not n and C_Item and C_Item.RequestLoadItemDataByID then try(C_Item.RequestLoadItemDataByID, id) end
  return n or ("objeto " .. id)
end

local function count(id, bank)
  local f = (C_Item and C_Item.GetItemCount) or GetItemCount
  return tonumber((f and try(f, id, bank)) or 0) or 0
end

-- Stored map % (forever-db frame) -> world yards, and -> this client's map %.
local function spotWorld(ui, x, y)
  local fit = G.qdb and G.qdb.zoneFit and G.qdb.zoneFit[ui]
  if not fit then return nil end
  return fit[1] - y / 100 * fit[3], fit[2] - x / 100 * fit[4]
end
local function continent(ui)
  local b = G.mapBounds and G.mapBounds(ui)
  return b and b.inst
end

local function playerWorld()
  local mapID = C_Map and try(C_Map.GetBestMapForUnit, "player")
  local pos = mapID and try(C_Map.GetPlayerMapPosition, mapID, "player")
  if not pos or secret(pos) then return nil end
  local px, py = pos:GetXY()
  if not px or secret(px) then return nil end
  local b = G.mapBounds and G.mapBounds(mapID)
  if not b then return nil end
  return b.top - py * b.h, b.left - px * b.w, b.inst
end

local function dist(ax, ay, ac, bx, by, bc)
  if not (ax and bx) then return 1e6 end
  local d = math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
  if ac and bc and ac ~= bc then d = d + 20000 end -- another continent: a boat or a long flight
  return d
end

local function knowsSkill(skillLine)
  if not GetProfessions then return nil end
  local list = { try(GetProfessions) }
  for _, idx in pairs(list) do
    if idx then
      local _, _, _, _, _, _, line = try(GetProfessionInfo, idx)
      if line == skillLine then return true end
    end
  end
  return false
end

-- Spots of one item, in world yards, that are safe for your level.
local function spotsOf(item, level)
  local d = G.gatherData and G.gatherData[item]
  local out = {}
  for _, s in ipairs(d and d.s or {}) do
    local ui, x, y, w, lmin, lmax, kind, src = s[1], s[2] / 10, s[3] / 10, s[4], s[5], s[6], s[7], s[8]
    if kind ~= "u" or lmin == 0 or lmin <= level + 3 then
      local wx, wy = spotWorld(ui, x, y)
      if wx then
        out[#out + 1] = { item = item, ui = ui, x = x, y = y, w = w, lmin = lmin, lmax = lmax, kind = kind, src = src,
          wx = wx, wy = wy, cont = continent(ui) }
      end
    end
  end
  return out
end

-- Nearest trainer pin of a profession (the supply vendors stand next to it), not in an enemy capital.
local function trainerFor(skill, px, py, pc)
  local title = TRAINER[skill]
  local enemy = ENEMY_CAPITALS[UnitFactionGroup("player") or ""] or {}
  local best, bestD
  for mapID, list in pairs(G.cityPins or {}) do
    if not enemy[mapID] then
      for _, e in ipairs(list) do
        if e[5] == title and e[6] then
          local b = G.mapBounds and G.mapBounds(mapID)
          local d = dist(px, py, pc, e[6], e[7], b and b.inst)
          if not bestD or d < bestD then
            local x, y = e[1], e[2]
            if b then x, y = (b.left - e[7]) / b.w * 100, (b.top - e[6]) / b.h * 100 end
            best, bestD = { mapID = mapID, x = x, y = y, name = e[4], wx = e[6], wy = e[7], cont = b and b.inst }, d
          end
        end
      end
    end
  end
  return best
end

-- ---------------------------------------------------------------- the plan
local active -- { title, skill, need = { {item, count, have, bank, via} }, stops = { ... }, notes = { ... } }

-- What is still missing: { [item] = n }, expanding reagents you craft yourself (bars, bolts, cured hides) one level.
local function missing(reagents, mult, out, via, depth)
  for _, r in ipairs(reagents) do
    local need = r.count * mult
    out[r.item] = out[r.item] or { item = r.item, count = 0, via = via }
    out[r.item].count = out[r.item].count + need
  end
  if depth >= 1 then return out end
  local rows = {}
  for _, r in pairs(out) do rows[#rows + 1] = r end
  for _, r in ipairs(rows) do
    local have = count(r.item, true)
    local short = r.count - have
    local sub = byCreated[r.item]
    if short > 0 and sub and not (G.gatherData and G.gatherData[r.item] and G.gatherData[r.item].s) and not r.via then
      r.craft = sub
      missing(sub.reagents, short, out, r.item, depth + 1)
    end
  end
  return out
end

local function build(title, skill, reagents)
  index()
  local level = UnitLevel("player") or 1
  local px, py, pc = playerWorld()
  local list = missing(reagents, 1, {}, nil, 0)
  local plan = { title = title, skill = skill, need = {}, stops = {}, notes = {} }
  local todo = {}
  for _, r in pairs(list) do
    local bags, all = count(r.item, false), count(r.item, true)
    r.have, r.bank = bags, all - bags
    r.short = math.max(0, r.count - all)
    plan.need[#plan.need + 1] = r
    if r.short > 0 and not r.craft then todo[r.item] = r end
  end
  table.sort(plan.need, function(a, b) if (a.via ~= nil) ~= (b.via ~= nil) then return a.via == nil end return a.item < b.item end)

  -- Vendor, skinning, fishing and unknown items.
  local spots = {}
  local herb, mine = knowsSkill(182), knowsSkill(186)
  for item, r in pairs(todo) do
    local d = G.gatherData and G.gatherData[item]
    if d and d.v then
      r.how = "vendor"
      local t = trainerFor(d.v, px, py, pc)
      if t then
        plan.vendor = plan.vendor or { mapID = t.mapID, x = t.x, y = t.y, wx = t.wx, wy = t.wy, cont = t.cont, items = {},
          name = "Proveedor al lado del " .. (t.name or "instructor") }
        table.insert(plan.vendor.items, item)
      end
      todo[item] = nil
    else
      local s = spotsOf(item, level)
      if d and d.sk then -- leather: skinning beats the odd chest that holds some
        r.how = "skin"; r.skin = d.sk; todo[item] = nil
      elseif #s > 0 then
        spots[item] = s
        local k = s[1].kind
        if k == "h" then r.how = "herb" elseif k == "m" then r.how = "ore" end
      elseif d and d.f then
        r.how = "fish"; todo[item] = nil
      else
        r.how = "unknown"; todo[item] = nil
      end
    end
  end

  -- Greedy: the stop that covers the most of what is left, closest to where you are (then to the previous stop).
  local fromX, fromY, fromC = px, py, pc
  while next(todo) and #plan.stops < MAX_STOPS do
    local best, bestScore, bestCover
    for item in pairs(todo) do
      for _, c in ipairs(spots[item] or {}) do
        local cover, value = {}, 0
        for other in pairs(todo) do
          for _, s in ipairs(spots[other] or {}) do
            if s.cont == c.cont and dist(c.wx, c.wy, nil, s.wx, s.wy, nil) <= NEAR then
              cover[other] = s; value = value + math.min(s.w, 400) / 400
              break
            end
          end
        end
        local n = 0
        for _ in pairs(cover) do n = n + 1 end
        local score = n * 4000 + value * 300 - dist(fromX, fromY, fromC, c.wx, c.wy, c.cont)
        if c.kind == "u" and c.lmax > 0 and c.lmax < level - 8 then score = score + 200 end -- easy, safe creatures
        if not bestScore or score > bestScore then best, bestScore, bestCover = c, score, cover end
      end
    end
    if not best then break end
    local x, y = best.x, best.y
    if G.qdb and G.qdb.toClient then x, y = G.qdb.toClient(best.ui, x, y) end
    local stop = { mapID = best.ui, x = x, y = y, items = {}, wx = best.wx, wy = best.wy, cont = best.cont }
    local lmin, lmax, srcs = 999, 0, {}
    for item, s in pairs(bestCover) do
      table.insert(stop.items, item)
      todo[item] = nil
      if s.kind == "u" and s.lmin > 0 then lmin, lmax = math.min(lmin, s.lmin), math.max(lmax, s.lmax) end
      local key = (s.kind == "u" and "u" or "o") .. s.src
      local nm = G.gatherNames and G.gatherNames[key]
      if nm and not srcs[nm] then srcs[nm] = true; srcs[#srcs + 1] = nm end
    end
    stop.lvl = lmax > 0 and (lmin == lmax and tostring(lmin) or (lmin .. "-" .. lmax)) or nil
    stop.sources = srcs
    plan.stops[#plan.stops + 1] = stop
    fromX, fromY, fromC = best.wx, best.wy, best.cont
  end
  for _, r in pairs(todo) do r.later = true end
  if plan.vendor then table.insert(plan.stops, plan.vendor) end
  -- Walking order: always the nearest remaining stop next.
  local ordered, cx, cy, cc = {}, px, py, pc
  while #plan.stops > 0 do
    local bi, bd
    for i, st in ipairs(plan.stops) do
      local d = dist(cx, cy, cc, st.wx, st.wy, st.cont)
      if not bd or d < bd then bi, bd = i, d end
    end
    local st = table.remove(plan.stops, bi)
    st.d = bd
    ordered[#ordered + 1] = st
    cx, cy, cc = st.wx, st.wy, st.cont
  end
  plan.stops = ordered
  plan.herb, plan.mine = herb, mine
  return plan
end

-- ---------------------------------------------------------------- start, follow, render
local function point(stop, why)
  if not stop then return end
  local names = {}
  for _, it in ipairs(stop.items) do names[#names + 1] = itemName(it) end
  if G.nextStep and G.nextStep.following and G.nextStep.following() then
    G.nextStep.setFollow(false, "Flecha a tus ingredientes; sugerencias en pausa")
  end
  G.setWaypoint(stop.mapID, stop.x / 100, stop.y / 100, "Conseguir: " .. table.concat(names, ", "), why)
end

local function complete(plan)
  for _, r in ipairs(plan.need) do if not r.via and r.count > count(r.item, true) then return false end end
  return true
end

local function refreshCounts()
  if not active then return end
  local before = active.stops[1]
  local plan = build(active.title, active.skill, active.reagents)
  plan.reagents = active.reagents
  local done = complete(plan)
  active = plan
  local now = plan.stops[1]
  if not done and before and now and (before.mapID ~= now.mapID or math.abs(before.x - now.x) > 1 or math.abs(before.y - now.y) > 1) then
    say("Listo con esa parada. Te marco la siguiente.")
    point(now)
  end
  if done then
    say("¡Tenés todo para " .. plan.title .. "!")
    active.done = true
  end
  if G.core and G.core.render then G.core.render() end
end

-- reagents: { { item = id, count = n }, ... }
function GX.start(title, skill, reagents)
  index()
  local plan = build(title, skill, reagents)
  plan.reagents = reagents
  active = plan
  if #plan.need == 0 then
    say("No encontré los ingredientes de " .. title .. ".")
    active = nil
  elseif complete(plan) then
    say("Ya tenés todo para " .. title .. ".")
  elseif plan.stops[1] then
    point(plan.stops[1])
    say("Conseguir " .. title .. ": te marqué el lugar más cercano. Detalle en la Guía > Profesiones.")
  else
    say("Conseguir " .. title .. ": no tengo un lugar para lo que te falta (mirá la Guía > Profesiones).")
  end
  if G.core and G.core.render then G.core.render() end
end

function GX.startRecipe(rec)
  if rec then GX.start(rec.name, rec.skill, rec.reagents) end
end

function GX.stop()
  active = nil
  if G.core and G.core.render then G.core.render() end
end

function GX.command(text)
  local rec = GX.findRecipe(text)
  if rec then GX.startRecipe(rec) else say("No encontré una receta con \"" .. text .. "\". Probá con parte del nombre: /guia conseguir estofado") end
end

function GX.active() return active end

local HOW = {
  vendor = "se compra al proveedor",
  skin = "desollando",
  fish = "se pesca",
  unknown = "no sé de dónde sale: mirá la casa de subastas",
  herb = "herboristería",
  ore = "minería",
}

-- Lines for the Profesiones section (Core.lua passes its text helpers).
function GX.render(L, B, link, C)
  if not active then return end
  local p = active
  L(C.gold .. "Conseguir: " .. p.title .. C.r .. "  " .. link("gatx", 1, "Terminar"))
  if p.done then B(C.green .. "¡Tenés todo! Andá a fabricarlo." .. C.r) end
  for _, r in ipairs(p.need) do
    local name = itemName(r.item)
    local have = r.have + r.bank
    local line
    if have >= r.count then
      line = C.green .. "✓ " .. name .. " " .. math.min(have, r.count) .. "/" .. r.count .. C.r
    elseif r.craft then
      line = name .. " " .. have .. "/" .. r.count .. C.grey .. "  (lo fabricás: " .. r.craft.name .. ")" .. C.r
    else
      line = name .. " " .. C.gold .. have .. "/" .. r.count .. C.r
      local how = r.how and HOW[r.how]
      if r.how == "skin" and r.skin then how = "desollando bestias de nivel " .. r.skin[1] .. "-" .. r.skin[2] end
      if r.how == "herb" and p.herb == false then how = "herboristería (no la tenés: comprala en la casa de subastas)" end
      if r.how == "ore" and p.mine == false then how = "minería (no la tenés: comprala en la casa de subastas)" end
      if r.later then how = (how and (how .. ", ") or "") .. "en otra zona (después de estas paradas)" end
      if how then line = line .. C.grey .. "  " .. how .. C.r end
    end
    if r.bank > 0 then line = line .. C.grey .. " (" .. r.bank .. " en el banco)" .. C.r end
    if r.via then line = "   " .. line end
    B(line)
  end
  if #p.stops > 0 then L(C.grey .. "Dónde, en orden:" .. C.r) end
  for i, s in ipairs(p.stops) do
    local names = {}
    for _, it in ipairs(s.items) do names[#names + 1] = itemName(it) end
    local where = s.name or ((s.sources and #s.sources > 0) and table.concat(s.sources, ", ", 1, math.min(2, #s.sources)) or "")
    local zone = C_Map and C_Map.GetMapInfo and try(C_Map.GetMapInfo, s.mapID)
    B(C.gold .. i .. "." .. C.r .. " " .. table.concat(names, ", ") .. C.grey .. " — " .. ((zone and zone.name) or "") ..
      (where ~= "" and (", " .. where) or "") .. (s.lvl and (" (nv " .. s.lvl .. ")") or "") ..
      ((s.d or 0) >= 20000 and " · otro continente" or string.format(" · %d m", math.floor((s.d or 0) * 0.9144 + 0.5))) ..
      C.r .. "  " .. link("gat", i, "Ir"))
  end
end

-- [Conseguir] links next to recipes in the Profesiones section.
function GX.recipeLines(skillName, rank, B, link, C)
  local list = GX.recipesFor(skillName, rank, 4)
  if #list == 0 then return end
  B(C.grey .. "Para subir (si tenés la receta):" .. C.r)
  for _, rec in ipairs(list) do
    local color = rec.yellow > rank and C.orange or C.gold
    local parts = {}
    for _, r in ipairs(rec.reagents) do parts[#parts + 1] = r.count .. " " .. itemName(r.item) end
    B("   " .. color .. rec.name .. C.r .. C.grey .. " (" .. table.concat(parts, ", ") .. ")" .. C.r .. "  " .. link("gatr", rec.idx, "Conseguir"))
  end
end

G.linkHandlers = G.linkHandlers or {}
G.linkHandlers.gat = function(i) if active and active.stops[i] then point(active.stops[i]) end end
G.linkHandlers.gatr = function(i) index(); GX.startRecipe(recipes[i]) end
G.linkHandlers.gatx = function() GX.stop() end

-- ---------------------------------------------------------------- profession window button
-- The recipe selected in the profession window -> its name, skill line and reagents straight from the client.
local function selectedRecipe()
  local pf = ProfessionsFrame
  local form = pf and pf.CraftingPage and pf.CraftingPage.SchematicForm
  if form and form:IsVisible() then
    local info = (form.GetRecipeInfo and try(form.GetRecipeInfo, form)) or form.currentRecipeInfo
    local id = info and info.recipeID
    local sch = id and C_TradeSkillUI and try(C_TradeSkillUI.GetRecipeSchematic, id, false)
    if sch then
      local reagents = {}
      for _, slot in ipairs(sch.reagentSlotSchematics or {}) do
        local r = slot.reagents and slot.reagents[1]
        local basic = slot.reagentType == nil or slot.reagentType == 1 or (Enum and Enum.CraftingReagentType and slot.reagentType == Enum.CraftingReagentType.Basic)
        if r and r.itemID and basic then reagents[#reagents + 1] = { item = r.itemID, count = slot.quantityRequired or 1 } end
      end
      local child = C_TradeSkillUI.GetChildProfessionInfo and try(C_TradeSkillUI.GetChildProfessionInfo)
      local base = C_TradeSkillUI.GetBaseProfessionInfo and try(C_TradeSkillUI.GetBaseProfessionInfo)
      local line = (base and base.professionID) or (child and child.parentProfessionID)
      return info.name or sch.name or "receta", line, reagents
    end
  end
  if TradeSkillFrame and TradeSkillFrame:IsVisible() and GetTradeSkillSelectionIndex then
    local i = try(GetTradeSkillSelectionIndex)
    if not i or i == 0 then return end
    local name = try(GetTradeSkillInfo, i)
    local reagents = {}
    for j = 1, (try(GetTradeSkillNumReagents, i) or 0) do
      local _, _, need = try(GetTradeSkillReagentInfo, i, j)
      local link = try(GetTradeSkillReagentItemLink, i, j)
      local id = link and tonumber(link:match("item:(%d+)"))
      if id then reagents[#reagents + 1] = { item = id, count = need or 1 } end
    end
    return name or "receta", nil, reagents
  end
end

local wbtn
local function windowButton()
  if wbtn then return end
  local pf = ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.SchematicForm
  local parent = pf or TradeSkillFrame
  if not parent then return end
  wbtn = G.ui.button(parent, "Conseguir ingredientes", nil, "conseguir ingredientes",
    "Te marca el lugar más cercano donde conseguir lo que te falta para esta receta.")
  if pf then wbtn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, -8) else wbtn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -40, -44) end
  wbtn:SetScript("OnClick", function()
    local name, line, reagents = selectedRecipe()
    if not name then say("Elegí una receta de la lista primero."); return end
    -- What the window reports is kept for diagnosis (/reload writes it to SavedVariables).
    local d = G.core and G.core.db()
    if d then d.gatherLast = { name = name, line = line, reagents = reagents } end
    -- The guide's recipe data (read from the Forever client's files) wins: the window's reagent list has come back
    -- wrong on Forever (counts of 0). The window's list is only used for recipes the data does not have.
    local rec = GX.findRecipe(name)
    if rec and fold(rec.name) == fold(name) then GX.startRecipe(rec); return end
    local clean = {}
    for _, r in ipairs(reagents or {}) do
      local n = tonumber(r.count)
      if r.item then clean[#clean + 1] = { item = r.item, count = (n and n >= 1) and n or 1 } end
    end
    if #clean == 0 then say("No pude leer los ingredientes de " .. name .. ". Probá con /guia conseguir " .. name:lower()); return end
    GX.start(name, line, clean)
  end)
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "TRADE_SKILL_SHOW", "BAG_UPDATE_DELAYED" }) do pcall(ev.RegisterEvent, ev, e) end
local pending = false
ev:SetScript("OnEvent", function(_, event)
  if event == "BAG_UPDATE_DELAYED" then
    if active and not active.done and not pending then
      pending = true
      C_Timer.After(1, function() pending = false; pcall(refreshCounts) end)
    end
    return
  end
  pcall(windowButton)
end)
