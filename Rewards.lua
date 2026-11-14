-- Guía Forever: quest reward hint. When a quest offers a choice, mark the best one for your class
-- (green check) and the most valuable to sell (coin). Only reads Blizzard frames; marks are our own frames.
local G = GuiaForever

-- best armor subclass per class id: { below 40, from 40 }
local ARMOR = { [1] = { 3, 4 }, [2] = { 3, 4 }, [3] = { 2, 3 }, [7] = { 2, 3 }, [4] = { 2, 2 }, [11] = { 2, 2 },
  [5] = { 1, 1 }, [8] = { 1, 1 }, [9] = { 1, 1 } }
-- usable weapon subclasses per class id (rogue also gets axes in Forever)
local WEAPONS = {
  [1] = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 }, [2] = { 0, 1, 4, 5, 6, 7, 8 },
  [3] = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 }, [4] = { 0, 2, 3, 4, 7, 13, 15, 16, 18 },
  [5] = { 4, 10, 15, 19 }, [7] = { 0, 1, 4, 5, 10, 13, 15 }, [8] = { 7, 10, 15, 19 }, [9] = { 7, 10, 15, 19 },
  [11] = { 4, 5, 10, 13, 15 },
}
-- leveling stat weights: strength, agility, stamina, intellect, spirit
local WEIGHTS = {
  [1] = { 2, 1.5, 1.25, 0, 0.5 }, [2] = { 2, 1.25, 0.5, 0.75, 0.5 }, [3] = { 0, 2, 0.5, 1, 1.25 },
  [4] = { 1.5, 2, 0.75, 0, 0.75 }, [5] = { 0, 0, 1, 1.75, 1.5 }, [7] = { 2, 1.5, 0.5, 1, 0.25 },
  [8] = { 0, 0, 1, 2, 1.5 }, [9] = { 0, 0, 1.5, 1.75, 1.25 }, [11] = { 1.75, 1.75, 0.75, 0.25, 0.5 },
}
local STAT_KEYS = { "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_STAMINA_SHORT",
  "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_SPIRIT_SHORT" }
local SLOTS = { INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 },
  INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 },
  INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
  INVTYPE_WEAPON = { 16, 17 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_SHIELD = { 17 },
  INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 },
  INVTYPE_THROWN = { 18 } }
local DPS_WEIGHT = 4 -- per point of weapon DPS, melee and ranged classes

local function safe(v) if issecretvalue and issecretvalue(v) then return nil end return v end
local function num(v) v = safe(v); return type(v) == "number" and v or tonumber(v) end
local function has(list, v) for _, x in ipairs(list or {}) do if x == v then return true end end return false end

local function instant(link)
  local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if not fn then return end
  local ok, id, _, _, equipLoc, _, classID, subID = pcall(fn, link)
  if ok then return num(id), safe(equipLoc), num(classID), num(subID) end
end
local function stats(link)
  local fn = (C_Item and C_Item.GetItemStats) or GetItemStats
  if not (fn and type(link) == "string") then return {} end
  local ok, t = pcall(fn, link)
  return ok and type(t) == "table" and t or {}
end
local function sellPrice(link)
  local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if not fn then return 0 end
  local ok, _, _, _, _, _, _, _, _, _, _, price = pcall(fn, link)
  return ok and num(price) or 0
end

local function classID() local _, _, id = UnitClass("player"); return id end

local function score(link)
  local cid, level = classID(), UnitLevel("player") or 1
  local id, equipLoc, itemClass, sub = instant(link)
  if not id or not SLOTS[equipLoc or ""] then return nil end
  local s = 0
  if itemClass == 4 and sub and sub >= 1 and sub <= 4 and equipLoc ~= "INVTYPE_CLOAK" then
    local a = ARMOR[cid]; if not a then return nil end
    local best = level >= 40 and a[2] or a[1]
    if sub > best then return nil end
    s = s + (sub == best and 3 or -2)
  elseif itemClass == 4 and sub == 6 then
    if not (cid == 1 or cid == 2 or cid == 7) then return nil end
  elseif itemClass == 2 then
    if not has(WEAPONS[cid], sub) then return nil end
  end
  local st = stats(link)
  local w = WEIGHTS[cid] or {}
  for i, key in ipairs(STAT_KEYS) do s = s + (w[i] or 0) * (num(st[key]) or 0) end
  local dps = num(st.ITEM_MOD_DAMAGE_PER_SECOND_SHORT)
  if dps and ((w[1] or 0) > 0 or (w[2] or 0) > 0) then s = s + dps * DPS_WEIGHT end
  s = s + (num(st.RESISTANCE0_NAME) or 0) * 0.02
  return s, SLOTS[equipLoc]
end

local function worn(slots)
  local worst
  for _, slot in ipairs(slots) do
    local link = GetInventoryItemLink("player", slot)
    local sc = link and score(link) or 0
    if not worst or sc < worst then worst = sc end
  end
  return worst or 0
end

local function rewardButton(index)
  local rewards = QuestInfoRewardsFrame
  if rewards and type(rewards.RewardButtons) == "table" then
    for _, button in ipairs(rewards.RewardButtons) do
      if button.type == "choice" and button.GetID and button:GetID() == index and button:IsShown() then return button end
    end
  end
  local button = _G["QuestInfoRewardsFrameQuestInfoItem" .. index]
  if button and button:IsShown() then return button end
end

local marks = {}
local function mark(kind, button)
  local m = marks[kind]
  if not m then
    m = CreateFrame("Frame", nil, UIParent)
    m:SetSize(18, 18); m:SetFrameStrata("DIALOG")
    m.icon = m:CreateTexture(nil, "OVERLAY"); m.icon:SetAllPoints()
    m.icon:SetTexture(kind == "best" and "Interface\\RaidFrame\\ReadyCheck-Ready" or "Interface\\MoneyFrame\\UI-GoldIcon")
    marks[kind] = m
  end
  m:ClearAllPoints()
  if kind == "best" then m:SetPoint("TOPLEFT", button, "TOPLEFT", -4, 4) else m:SetPoint("TOPRIGHT", button, "TOPRIGHT", -2, -2) end
  m:Show()
end
local function hideMarks() for _, m in pairs(marks) do m:Hide() end end

local function evaluate(retry)
  hideMarks()
  local db = G.core and G.core.db()
  if db and db.rewards == false then return end
  local n = GetNumQuestChoices and (num(GetNumQuestChoices()) or 0) or 0
  if n < 2 then return end
  local bestI, bestGain, bestLink, priceI, priceV, missing = nil, 0, nil, nil, 0, false
  for i = 1, n do
    local link = GetQuestItemLink and safe(GetQuestItemLink("choice", i))
    if not link then missing = true
    else
      local sc, slots = score(link)
      if sc and slots then
        local gain = sc - worn(slots)
        if not bestI or gain > bestGain then bestI, bestGain, bestLink = i, gain, link end
      end
      local price = sellPrice(link)
      if price > priceV then priceI, priceV = i, price end
    end
  end
  if missing and not retry then C_Timer.After(0.6, function() evaluate(true) end) return end
  local msg = G.core and G.core.msg or print
  if bestI and bestGain > 0 then
    local b = rewardButton(bestI); if b then mark("best", b) end
    msg("Recompensa recomendada: " .. bestLink .. " (mejora lo que tenés puesto).")
  elseif priceI then
    msg("Ninguna recompensa mejora tu equipo: elegí la que más vale para vender (moneda).")
  end
  if priceI then local b = rewardButton(priceI); if b then mark("coin", b) end end
end

local f = CreateFrame("Frame")
for _, ev in ipairs({ "QUEST_COMPLETE", "QUEST_FINISHED", "GET_ITEM_INFO_RECEIVED" }) do pcall(f.RegisterEvent, f, ev) end
local open = false
f:SetScript("OnEvent", function(_, event)
  if event == "QUEST_COMPLETE" then open = true; C_Timer.After(0.1, function() pcall(evaluate) end)
  elseif event == "QUEST_FINISHED" then open = false; hideMarks() end
end)

-- ---------------------------------------------------------------- item verdict in tooltips
-- "Keep, equip, sell or auction?" on every item tooltip. Uses the same class scoring as the
-- reward hint, your quest objectives, your professions and (if installed) Auctionator prices.
local PROF_MATS = {
  -- [tradegoods subclass] = { profession names (esMX / English) }
  [5] = { "Sastrería", "Primeros auxilios", "Tailoring", "First Aid" },   -- cloth
  [6] = { "Peletería", "Leatherworking" },                                -- leather
  [7] = { "Herrería", "Ingeniería", "Blacksmithing", "Engineering" },      -- metal & stone
  [8] = { "Cocina", "Cooking" },                                           -- meat
  [9] = { "Alquimia", "Alchemy" },                                         -- herbs
  [12] = { "Encantamiento", "Enchanting" },                                -- enchanting
}

-- name -> current skill rank (number), for every skill line the character has.
local function myProfessions()
  local have = {}
  if GetNumSkillLines then
    for i = 1, GetNumSkillLines() do
      local ok, name, isHeader, _, rank = pcall(GetSkillLineInfo, i)
      if ok and name and not isHeader then have[name] = tonumber(rank) or 0 end
    end
  end
  return have
end

-- Skill line IDs used in DataRecipes.lua -> { esMX name, English name }.
local SKILL_NAMES = {
  [164] = { "Herrería", "Blacksmithing" }, [165] = { "Peletería", "Leatherworking" },
  [197] = { "Sastrería", "Tailoring" }, [202] = { "Ingeniería", "Engineering" },
  [333] = { "Encantamiento", "Enchanting" }, [171] = { "Alquimia", "Alchemy" }, [185] = { "Cocina", "Cooking" },
  [129] = { "Primeros auxilios", "First Aid" }, [40] = { "Venenos", "Poisons" }, [186] = { "Minería", "Mining" },
  [356] = { "Pesca", "Fishing" }, [182] = { "Herboristería", "Herbalism" }, [393] = { "Desuello", "Skinning" },
}

-- Party members (with the Guía) who have this profession: { { name, rank }, ... }.
local function matesFor(g)
  local out = {}
  local stats = G.core and G.core.partyStats and G.core.partyStats() or {}
  local names = SKILL_NAMES[g.skill] or {}
  for name, m in pairs(stats) do
    local rank = m.profs and (m.profs[names[1] or ""] or m.profs[names[2] or ""])
    if rank then out[#out + 1] = { name = name, rank = rank } end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

-- Recipes that use an item, grouped by profession: { skill, label, rank (nil if not yours), list }.
-- Yours first, then by number of recipes.
local function recipeGroups(itemID)
  local rows = itemID and G.itemRecipes and G.itemRecipes[itemID]
  if not rows then return end
  local mine, byId, groups = myProfessions(), {}, {}
  for _, r in ipairs(rows) do
    local g = byId[r[1]]
    if not g then
      local names = SKILL_NAMES[r[1]] or { "?" }
      g = { skill = r[1], label = names[1], list = {} }
      g.rank = mine[names[1]] or (names[2] and mine[names[2]])
      if r[1] == 40 and not g.rank and classID() == 4 and (UnitLevel("player") or 1) < 20 then g.future = 20 end
      byId[r[1]] = g; groups[#groups + 1] = g
    end
    g.list[#g.list + 1] = { yellow = r[2], grey = r[3], count = r[4], name = r[5], output = r[6] or 0 }
  end
  for _, g in ipairs(groups) do g.mates = #matesFor(g) > 0 end
  table.sort(groups, function(a, b)
    if (a.rank ~= nil) ~= (b.rank ~= nil) then return a.rank ~= nil end
    if a.mates ~= b.mates then return a.mates end
    if #a.list ~= #b.list then return #a.list > #b.list end
    return a.label < b.label
  end)
  return groups
end

-- Recipes of a group that still give you skill points (grey above your rank), lowest first.
local function stillUseful(g)
  local out = {}
  for _, r in ipairs(g.list) do if g.rank and r.grey > g.rank then out[#out + 1] = r end end
  return out
end

local function questUse(name)
  if not (name and G.core) then return end
  for _, e in ipairs(G.core.questEntries()) do
    for _, o in ipairs(G.core.questObjectives(e)) do
      local t = o.text
      if type(t) == "string" and not (issecretvalue and issecretvalue(t)) and t:find(name, 1, true) then
        return (e.title or "?") .. " (" .. t:gsub("^.-:%s*", "") .. ")", o.done
      end
    end
  end
end

local function money(c)
  c = math.floor(c or 0)
  local g, sv, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  if g > 0 then return g .. "o " .. sv .. "p" end
  if sv > 0 then return sv .. "p " .. cp .. "c" end
  return cp .. "c"
end

local function auctionPrice(link)
  local api = rawget(_G, "Auctionator") and Auctionator.API and Auctionator.API.v1
  if not (api and api.GetAuctionPriceByItemLink) then return nil end
  local ok, price = pcall(api.GetAuctionPriceByItemLink, "GuiaForever", link)
  return ok and tonumber(price) or nil
end

-- Red tooltip lines mean the game won't let you use the item (weapon skill not learned, class/profession
-- requirement...). The "Requires Level" line is skipped: that case is handled as "save it for later".
local function isRed(c) return type(c) == "table" and type(c.r) == "number" and c.r > 0.9 and (c.g or 1) < 0.25 and (c.b or 1) < 0.25 end
local function blockedReason(link)
  if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink) then return end
  local ok, data = pcall(C_TooltipInfo.GetHyperlink, link)
  if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return end
  local lvlPat = type(ITEM_MIN_LEVEL) == "string" and ("^" .. ITEM_MIN_LEVEL:gsub("%%d", "%%d+") .. "$") or nil
  local found
  for _, line in ipairs(data.lines) do
    for _, side in ipairs({ { line.leftText, line.leftColor }, { line.rightText, line.rightColor } }) do
      local t, c = side[1], side[2]
      if type(t) == "string" and t ~= "" and not (issecretvalue and issecretvalue(t)) and isRed(c)
        and not (lvlPat and t:match(lvlPat)) then
        found = t -- keep the last one: for weapons that is the type ("Hacha"), after the slot line
      end
    end
  end
  return found
end

local function verdict(link, soulbound)
  local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if not fn then return end
  local ok, name, _, quality, _, reqLevel, _, _, _, equipLoc, _, sellPrice, classID, subclassID, bindType = pcall(fn, link)
  if not ok or not name or (issecretvalue and issecretvalue(name)) then return end
  sellPrice = tonumber(sellPrice) or 0

  -- 1) needed for a quest you have
  local quest, done = questUse(name)
  if quest and not done then return "|cff4ade80GUARDALO|r: lo pide la misión " .. quest, "quest" end

  -- 2) grey junk
  if quality == 0 then return "|cff9ca3afVENDELO|r: basura, " .. money(sellPrice) .. " al vendedor", "junk" end

  -- 3) equipment: upgrade for you?
  if equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_BAG" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE" then
    local sc, slots = score(link)
    if sc and slots then
      local gain = sc - worn(slots)
      if gain > 0.5 then
        local blocked = blockedReason(link)
        if blocked then
          if classID == 2 then
            return "|cfffbbf24APRENDÉ " .. blocked:upper() .. "|r con un maestro de armas (10 de plata) y después equipalo: mejora lo que tenés", "later"
          end
          return "|cfffbbf24TODAVÍA NO LO PODÉS USAR|r (" .. blocked .. "): después te mejora", "later"
        end
        local lvl = UnitLevel("player") or 1
        if reqLevel and reqLevel > lvl then return "|cfffbbf24GUARDALO|r: mejora para vos al nivel " .. reqLevel, "later" end
        return "|cff4ade80EQUIPALO|r: mejora lo que tenés puesto", "equip"
      end
    end
    local ah = (not soulbound) and auctionPrice(link)
    if ah and ah > sellPrice * 1.5 then return "|cff7dd3fcSUBASTALO|r: ~" .. money(ah) .. " en la subasta (vendedor " .. money(sellPrice) .. ")", "auction" end
    if not soulbound and bindType == 2 and (quality or 0) >= 2 then
      return "|cff7dd3fcSUBASTALO|r: se liga al equipar y no te sirve; mirá el precio en la subasta", "auction"
    end
    return "|cff9ca3afVENDELO|r: no te sirve, " .. money(sellPrice) .. " al vendedor", "sell"
  end

  -- 4) material: decided by the real recipes that use it and your skill in each profession
  local groups = recipeGroups(instant(link))
  if groups then
    local best, later
    for _, g in ipairs(groups) do
      local useful = stillUseful(g)
      if #useful > 0 then
        local top = 0
        for _, r in ipairs(useful) do if r.grey > top then top = r.grey end end
        if useful[1].yellow > g.rank + 50 then
          later = later or ("|cfffbbf24GUARDALO|r para más adelante: tu " .. g.label .. " lo usa desde ~" .. useful[1].yellow .. " (tenés " .. g.rank .. ")")
        else
          best = best or ("|cff4ade80GUARDALO|r: te sirve para subir " .. g.label .. " (da puntos hasta " .. top .. ", tenés " .. g.rank .. ")")
        end
      end
    end
    if best then return best, "material" end
    -- Intermediate material (scraps -> leather, ore -> bar, cloth -> bolt): useful if what you make with it is.
    for _, g in ipairs(groups) do
      if g.rank then
        for _, r in ipairs(g.list) do
          local sub = r.output > 0 and recipeGroups(r.output)
          if sub then
            for _, sg in ipairs(sub) do
              local useful = stillUseful(sg)
              if #useful > 0 then
                local top = 0
                for _, u in ipairs(useful) do if u.grey > top then top = u.grey end end
                return "|cff4ade80GUARDALO|r: con " .. r.count .. " hacés " .. r.name .. " (" .. g.label .. "), que te sirve para subir "
                  .. sg.label .. " (da puntos hasta " .. top .. ")", "material"
              end
            end
          end
        end
      end
    end
    for _, g in ipairs(groups) do
      if g.future then return "|cfffbbf24GUARDALO|r: lo vas a usar para " .. g.label .. " (se aprende al nivel " .. g.future .. ")", "later" end
    end
    if later then return later, "later" end
    -- Not useful to you, but to a party member: hand it over.
    for _, g in ipairs(groups) do
      if not g.rank then
        for _, mate in ipairs(matesFor(g)) do
          for _, r in ipairs(g.list) do
            if r.grey > mate.rank then
              return "|cff4ade80PASASELO|r a " .. mate.name .. ": le sirve para subir " .. g.label .. " (tiene " .. mate.rank .. ")", "material"
            end
          end
        end
      end
    end
    local ah = (not soulbound) and auctionPrice(link)
    local why = groups[1].rank and ("a tu " .. groups[1].label .. " ya no le da puntos") or "no lo usa ninguna de tus profesiones"
    if ah and ah > sellPrice * 1.5 then
      return "|cff7dd3fcSUBASTALO|r: " .. why .. "; ~" .. money(ah) .. " en la subasta (vendedor " .. money(sellPrice) .. ")", "auction"
    elseif ah then
      return "|cff9ca3afVENDELO|r al vendedor: " .. why .. " y la subasta no paga más (" .. money(ah) .. ")", "sell"
    elseif sellPrice == 0 then
      return "|cff7dd3fcSUBASTALO|r: " .. why .. "; el vendedor no lo compra", "auction"
    end
    return "|cff7dd3fcVENDELO O SUBASTALO|r: " .. why .. ". Vendedor: " .. money(sellPrice) .. "; escaneá la subasta para comparar", "auction"
  end

  -- 4b) trade good without recipe data: guess from its subclass
  if classID == 7 and PROF_MATS[subclassID] then
    local mine = myProfessions()
    for _, prof in ipairs(PROF_MATS[subclassID]) do
      if mine[prof] then return "|cff4ade80GUARDALO|r: material de " .. prof, "material" end
    end
    local ah = (not soulbound) and auctionPrice(link)
    if ah then return "|cff7dd3fcSUBASTALO|r: material que no usás, ~" .. money(ah) .. " en la subasta", "auction" end
    return "|cff7dd3fcVENDELO O SUBASTALO|r: material que no usás", "auction"
  end

  -- 5) consumables: keep (food, bandages, potions)
  if classID == 0 then return "|cff4ade80GUARDALO|r: consumible (comida, venda o poción)", "consumable" end
  return nil
end

-- ---------------------------------------------------------------- "what is it for" line
-- Hand-written uses for common items (DataItems.lua), else a hint from the item class/subclass.
local TRADE_USES = {
  [1] = "Ingeniería (piezas)", [5] = "Sastrería y Primeros auxilios (vendas)", [6] = "Peletería",
  [7] = "Herrería e Ingeniería", [8] = "Cocina", [9] = "Alquimia (pociones y elixires)",
  [10] = "recetas de nivel medio de varias profesiones", [12] = "Encantamiento",
}

local function anyMine(profs)
  local mine = myProfessions()
  for _, p in ipairs(profs or {}) do if mine[p] then return p end end
end

local function plural(n, one, many) return n .. " " .. (n == 1 and one or (many or one .. "s")) end

-- One line per profession: which recipes use the item and at what skill.
local function recipeLines(groups)
  local lines = {}
  for i, g in ipairs(groups) do
    if i > 4 then lines[#lines + 1] = "|cff9ca3af+" .. plural(#groups - 4, "profesión", "profesiones") .. " más|r"; break end
    local show, head
    if g.rank then
      local useful = stillUseful(g)
      head = "|cff4ade80" .. g.label .. " (tuya, " .. g.rank .. ")|r: "
      if #useful == 0 then
        local names = {}
        for j = 1, math.min(2, #g.list) do names[#names + 1] = g.list[j].name .. (g.list[j].count > 1 and (" x" .. g.list[j].count) or "") end
        lines[#lines + 1] = head .. table.concat(names, ", ") .. " |cff9ca3af(" .. (#g.list == 1 and "gris" or plural(#g.list, "receta") .. ", todas grises") .. ": ya no te da puntos)|r"
      else
        show = useful
      end
    else
      local lo, hi = nil, 0
      for _, r in ipairs(g.list) do
        if r.yellow > 0 and (not lo or r.yellow < lo) then lo = r.yellow end
        if r.grey > hi then hi = r.grey end
      end
      local mates = {}
      for _, mate in ipairs(matesFor(g)) do mates[#mates + 1] = mate.name .. " " .. mate.rank end
      head = "|cfffbbf24" .. g.label .. "|r" .. (#mates > 0 and (" |cff7dd3fc(" .. table.concat(mates, ", ") .. ")|r") or "") .. (g.future and (" (la aprendés al nivel " .. g.future .. ")") or (lo and (" (" .. lo .. "-" .. hi .. ")") or "")) .. ": "
      show = g.list
    end
    if show then
      local parts = {}
      for j = 1, math.min(2, #show) do
        local r = show[j]
        parts[#parts + 1] = r.name .. (r.count > 1 and (" x" .. r.count) or "") .. (r.grey > 0 and (" |cff9ca3af(" .. r.yellow .. "-" .. r.grey .. ")|r") or "")
      end
      local rest = #show - #parts
      lines[#lines + 1] = head .. table.concat(parts, ", ") .. (rest > 0 and (" |cff9ca3afy " .. plural(rest, "receta") .. " más|r") or "")
    end
  end
  return lines
end

local function purpose(link)
  local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if not fn then return end
  local ok, name, _, _, _, _, _, subName, _, _, _, _, classID, subclassID = pcall(fn, link)
  if not ok or not name or (issecretvalue and issecretvalue(name)) then return end
  local id = instant(link)
  local groups = recipeGroups(id)
  if groups then return recipeLines(groups) end
  local text = id and G.itemUses and G.itemUses[id]
  if not text then
    if classID == 7 then text = TRADE_USES[subclassID]
    elseif classID == 9 then
      local profs = G.recipeProfs and G.recipeProfs[subclassID]
      if profs then
        text = "Receta de " .. profs[1] .. (anyMine(profs) and ": |cff4ade80la podés aprender|r (clic derecho)" or ": la aprende quien tenga " .. profs[1])
      else text = "Libro o receta: clic derecho para aprenderla" end
    elseif classID == 1 then
      text = subclassID == 0 and "Bolsa: ponela en un hueco de bolsa (abajo a la derecha) para tener más lugar"
        or "Bolsa especial: solo guarda " .. (safe(subName) or "un tipo de objeto")
    elseif classID == 6 then text = "Munición de cazador (flechas o balas)"
    elseif classID == 11 then text = "Carcaj o canana: solo para cazadores"
    elseif classID == 5 then text = "Componente de hechizo de algunas clases"
    elseif classID == 13 then text = "Llave: abre una puerta o un cofre"
    elseif classID == 12 then
      text = "Objeto de misión. Si no tenés la misión, o la empieza (dice 'Este objeto inicia una misión') o ya no sirve"
    end
  end
  if not text then return end
  if classID == 7 then
    local p = anyMine(PROF_MATS[subclassID])
    if p then text = text .. " |cff4ade80(tu " .. p .. ")|r" end
  end
  return { text }
end
G.items = G.items or {}
G.items.purpose = purpose

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
    local db = G.core and G.core.db()
    if not db or db.itemAdvice == false then return end
    if db.itemAdviceShift and not (IsShiftKeyDown and IsShiftKeyDown()) then return end
    if not (tooltip and tooltip.GetItem and tooltip.AddLine) then return end
    local ok, _, link = pcall(tooltip.GetItem, tooltip)
    if not ok or type(link) ~= "string" or (issecretvalue and issecretvalue(link)) then return end
    local soulbound = false
    for _, line in ipairs(type(data) == "table" and data.lines or {}) do
      local t = line.leftText
      if type(t) == "string" and not (issecretvalue and issecretvalue(t)) and (t == ITEM_SOULBOUND or t == ITEM_ACCOUNTBOUND) then soulbound = true end
    end
    local okP, use = pcall(purpose, link)
    local okV, text = pcall(verdict, link, soulbound)
    if (okP and use) or (okV and text) then tooltip:AddLine(" ") end
    if okP and use then
      if #use == 1 then tooltip:AddLine("|cfffbbf24Sirve para:|r " .. use[1], 1, 1, 1, true)
      else
        tooltip:AddLine("|cfffbbf24Sirve para (recetas, habilidad amarilla-gris):|r")
        for _, l in ipairs(use) do tooltip:AddLine("  " .. l, 1, 1, 1, true) end
      end
    end
    if okV and text then tooltip:AddLine("Guía: " .. text, 1, 1, 1, true) end
  end)
end

-- ---------------------------------------------------------------- bag marks (Baganator corner widget)
-- A small badge on bag items: Q = needed for a quest, + = upgrade to equip now, M = material for your
-- professions, ^ = upgrade for a later level, $ = worth auctioning.
local BADGES = {
  quest = { "Q", 1, 0.82, 0 }, equip = { "+", 0.29, 0.87, 0.5 }, material = { "M", 0.29, 0.87, 0.5 },
  later = { "^", 0.98, 0.75, 0.14 }, auction = { "$", 0.49, 0.83, 0.99 },
}
local function badgeKinds()
  local db = G.core and G.core.db()
  local b = db and db.bagMarks
  return type(b) == "table" and b or {}
end
G.items.BADGES = BADGES
G.items.verdict = verdict

local function registerBaganator()
  local api = rawget(_G, "Baganator") and Baganator.API
  if not (api and api.RegisterCornerWidget) then return false end
  api.RegisterCornerWidget("Guía Forever: guardar / vender", "guiaforever_verdict", function(corner, details)
    local db = G.core and G.core.db()
    if not db or db.bagMarksOn == false then return false end
    local link = details and details.itemLink
    if type(link) ~= "string" then return nil end
    local ok, _, kind = pcall(verdict, link, details.isBound)
    if not ok or not kind then return false end
    local style = BADGES[kind]
    if not style or badgeKinds()[kind] == false then return false end
    corner.text:SetText(style[1])
    corner.text:SetTextColor(style[2], style[3], style[4])
    return true
  end, function(itemButton)
    local f = CreateFrame("Frame", nil, itemButton)
    f:SetSize(14, 14)
    local bg = f:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.65)
    f.text = f:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    f.text:SetPoint("CENTER", 0, 0)
    return f
  end, { corner = "top_left", priority = 1 })
  G.items.refreshBags = function() if api.RequestItemButtonsRefresh then pcall(api.RequestItemButtonsRefresh) end end
  return true
end
if not registerBaganator() then
  local w = CreateFrame("Frame")
  w:RegisterEvent("ADDON_LOADED")
  w:SetScript("OnEvent", function(self, _, name) if name == "Baganator" and registerBaganator() then self:UnregisterAllEvents() end end)
end
