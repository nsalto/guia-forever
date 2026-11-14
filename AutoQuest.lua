-- Guía Forever: accept and turn in quests on their own when you talk to the NPC. Hold Shift while
-- opening the NPC to do it by hand. Never picks a reward when there is a choice (the window stays open
-- with the recommended one marked), never pays gold, and leaves the NPC's other options alone.
local G = GuiaForever

local function db() return G.core and G.core.db() end
local function on() local d = db(); return d and d.autoQuest == true end -- off unless turned on in Ajustes
local function try(fn, ...) if type(fn) ~= "function" then return end local ok, a, b, c = pcall(fn, ...); if ok then return a, b, c end end
local function skip() return IsShiftKeyDown and IsShiftKeyDown() end

-- Gossip window (NPC with chat options): turn in finished quests first, then take new ones.
local function onGossip()
  if not C_GossipInfo then return end
  for _, q in ipairs(try(C_GossipInfo.GetActiveQuests) or {}) do
    if q.isComplete and q.questID then try(C_GossipInfo.SelectActiveQuest, q.questID); return end
  end
  for _, q in ipairs(try(C_GossipInfo.GetAvailableQuests) or {}) do
    if q.questID and not q.isTrivial then try(C_GossipInfo.SelectAvailableQuest, q.questID); return end
  end
end

-- Quest greeting window (NPC with only a quest list).
local function onGreeting()
  for i = 1, (try(GetNumActiveQuests) or 0) do
    local _, complete = try(GetActiveTitle, i)
    if complete then try(SelectActiveQuest, i); return end
  end
  for i = 1, (try(GetNumAvailableQuests) or 0) do
    local trivial = IsAvailableQuestTrivial and try(IsAvailableQuestTrivial, i)
    if not trivial then try(SelectAvailableQuest, i); return end
  end
end

G.autoQuest = {}

local f = CreateFrame("Frame")
for _, ev in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE" }) do
  pcall(f.RegisterEvent, f, ev)
end
f:SetScript("OnEvent", function(_, event)
  if not on() or skip() then return end
  if event == "GOSSIP_SHOW" then onGossip()
  elseif event == "QUEST_GREETING" then onGreeting()
  elseif event == "QUEST_DETAIL" then
    -- Quests that start from an item or are shared by a mate show here too: accept them the same way.
    try(AcceptQuest)
  elseif event == "QUEST_PROGRESS" then
    if ((GetQuestMoneyToGet and try(GetQuestMoneyToGet)) or 0) > 0 then return end -- costs gold: your call
    if IsQuestCompletable and try(IsQuestCompletable) then try(CompleteQuest) end
  elseif event == "QUEST_COMPLETE" then
    if ((GetQuestMoneyToGet and try(GetQuestMoneyToGet)) or 0) > 0 then return end
    local choices = try(GetNumQuestChoices) or 0
    if choices <= 1 then try(GetQuestReward, choices) end -- 0 or 1 reward: nothing to decide
  end
end)
