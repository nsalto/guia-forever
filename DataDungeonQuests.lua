-- Guía Forever: which quests belong to each dungeon (quest IDs, checked one by one against the quest database).
-- Keys match G.dungeons keys (key, or name when it has none). Prerequisites, givers and positions come from DataQuestDB.lua; whether a quest is
-- done always comes from the server. Quests a quest needs first are not listed here: DungeonQuests.lua walks them.
local G = GuiaForever
G.dungeonQuestIDs = {
  ["Ragefire Chasm"] = { 5723, 5724, 5725, 5728, 5761 },
  ["Wailing Caverns"] = { 914, 959, 962, 1486, 1487, 1491, 6981 },
  ["The Deadmines"] = { 166, 167, 168, 214, 373, 2040, 92753 },
  ["Shadowfang Keep"] = { 1013, 1014, 1098 },
  ["Blackfathom Deeps"] = { 971, 1198, 1199, 1200, 1275, 6561, 6563, 6565, 6921 },
  ["The Stockade"] = { 377, 378, 386, 387, 388, 391 },
  ["Gnomeregan"] = { 2841, 2904, 2922, 2924, 2926, 2928, 2929, 2930, 2945, 2947, 2949, 2951, 2962 },
  ["Razorfen Kraul"] = { 1100, 1101, 1102, 1109, 1142, 1144, 1221, 6522 },
  ["Scarlet Monastery: Graveyard"] = { 1051 },
  ["Scarlet Monastery: Library"] = { 1049, 1050 },
  ["Scarlet Monastery: Cathedral"] = { 1048, 1053 },
  ["Razorfen Downs"] = { 3341, 3523, 3525, 3636, 6521, 6626 },
  -- New in Forever (quest zone in forever-db). Breadcrumbs that only point to a giver are left out.
  ["Hall of Thanes"] = { 96393, 96394, 96395, 96403 },
  ["Ruins of Lordaeron"] = { 92401, 92415, 92421, 92422, 95189, 95195, 95204, 95216, 95250, 97288, 97289, 97291, 97292 },
  ["Excavation Site: Wetlands"] = { 95646, 95647, 95663, 95664, 95682, 95697, 95772, 95795, 95809, 95810, 98815, 98823, 98824 },
  ["City of Dalaran"] = { 92456, 92457, 92458, 92489, 96984, 96986, 96987, 96988 },
}

-- What to know before taking a quest, shown with the step (the giver is an escort that walks away and comes back
-- later, and so on).
G.questTakeTips = {
  [214] = "El Explorador Riell está arriba de todo de la Torre del Centinela, en Colina del Centinela: entrá a la torre y subí la escalera. En el mapa sale encima de Gryan porque el mapa no muestra la altura.",
  [155] = "Es una escolta: si El Traidor de los Defias no está, otro jugador lo está acompañando. Vuelve a aparecer al lado de Gryan en unos minutos. Lo llevás hasta Villa Luna (la entrada de Las Minas) y después volvés con Gryan.",
}

-- Quests that start from an item: who drops it (or the object that gives it), for the "where" of that step.
G.questStartItemFrom = {
  [2874] = "lo suelta Edwin VanCleef, adentro de Las Minas de la Muerte",
  [5791] = "es un objeto adentro de Horado Rajacieno (Diario de Henrig Soliceja)",
  [9326] = "lo suelta un Agente Hierro Negro, adentro de Gnomeregan",
  [10441] = "lo suelta Mutanus el Devorador, adentro de las Cuevas de los Lamentos",
  [16790] = "lo suelta un Sacerdote de las mareas Brazanegra, en Brazanegra",
  [17008] = "lo suelta Charlga Filonavaja, adentro de Horado Rajacieno",
}
