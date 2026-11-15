-- Guía Forever data: zones, dungeons, milestones and tips.
-- Compiled 2026-11-06 from Forever-specific guides (Warcraft Tavern, Method, Maxroll, Blizzard,
-- wowhead Forever, MeinMMO, Kami Labs). Ranges differ a little between sources; the in-game map wins.
GuiaForever = GuiaForever or {}
local G = GuiaForever

G.meta = { updated = "2026-11-06", version = "1.60.1" }

-- min/max = recommended levels. faction = who it suits (Both when omitted).
-- mapID = classic uiMapID; names = localized (esMX) and English names used as fallback.
G.zones = {
  { label = "Teldrassil", mapID = 1438, names = { "Teldrassil" }, min = 1, max = 10, faction = "Alliance",
    tips = { "Al 10 bajá a Rut'theran y tomá el barco a Auberdine (Costa Oscura)." } },
  { label = "Bosque de Elwynn", mapID = 1429, names = { "Bosque de Elwynn", "Elwynn Forest" }, min = 1, max = 10, faction = "Alliance" },
  { label = "Dun Morogh", mapID = 1426, names = { "Dun Morogh" }, min = 1, max = 10, faction = "Alliance",
    tips = { "Los Espías Hierro Negro de Ironband's Compound sueltan el Dark Iron Map: empieza una misión de Hall of Thanes." } },
  { label = "Costa Oscura", mapID = 1439, names = { "Costa Oscura", "Darkshore" }, min = 10, max = 19, faction = "Alliance",
    tips = {
      "Desde el muelle de Auberdine sale un barco NUEVO a Ventormenta: así llegás con tus amigos humanos sin pasar por Los Humedales.",
      "Rut'theran <-> Auberdine y el circuito Auberdine -> Menethil -> Costa Sur -> Auberdine (de un solo sentido) también salen de acá.",
    } },
  { label = "Páramos de Poniente", mapID = 1436, names = { "Páramos de Poniente", "Westfall" }, min = 10, max = 20, faction = "Alliance",
    tips = { "Las Minas de la Muerte (17-26) están en Villa Luna (Moonbrook).", "Acá empieza la cadena del Saco de dormir acogedor (nivel 14+): clic en los Restos calcinados del carro roto de la Granja Alexston (37, 50). Da hasta +3% XP por 1 h y cuenta como posada." } },
  { label = "Loch Modan", mapID = 1432, names = { "Loch Modan" }, min = 10, max = 20, faction = "Alliance" },
  { label = "Montañas Crestagrana", mapID = 1433, names = { "Montañas Crestagrana", "Redridge Mountains" }, min = 15, max = 25, faction = "Alliance" },
  { label = "Vallefresno", mapID = 1440, names = { "Vallefresno", "Ashenvale" }, min = 18, max = 30, faction = "Both",
    tips = { "Las Cavernas de Brazanegra (24-32) están en la Playa de Zoram, al oeste.", "Zona disputada: en reino JcJ andá atento a la Horda." } },
  { label = "Bosque del Ocaso", mapID = 1431, names = { "Bosque del Ocaso", "Duskwood" }, min = 18, max = 30, faction = "Alliance",
    tips = { "La misión de Mor'ladim ahora también da un anillo y una espada a dos manos mejorados." } },
  { label = "Los Humedales", mapID = 1437, names = { "Los Humedales", "Wetlands" }, min = 20, max = 30, faction = "Alliance",
    tips = { "Mazmorra nueva: Excavation Site (26-33)." } },
  { label = "Laderas de Trabalomas", mapID = 1424, names = { "Laderas de Trabalomas", "Hillsbrad Foothills" }, min = 20, max = 30, faction = "Both" },
  { label = "Los Baldíos", mapID = 1413, names = { "Los Baldíos", "The Barrens" }, min = 10, max = 25, faction = "Horde",
    tips = { "Paso 2 del Saco de dormir: torre quemada al sur de Campamento Taurajo (46, 74)." } },
  { label = "Sierra Espolón", mapID = 1442, names = { "Sierra Espolón", "Stonetalon Mountains" }, min = 15, max = 27, faction = "Both" },
  { label = "Las Mil Agujas", mapID = 1441, names = { "Las Mil Agujas", "Thousand Needles" }, min = 25, max = 35, faction = "Both" },
  { label = "Montañas de Alterac", mapID = 1416, names = { "Montañas de Alterac", "Alterac Mountains" }, min = 30, max = 40, faction = "Both",
    tips = { "Mazmorra nueva: City of Dalaran (28-35)." } },
  { label = "Tierras Altas de Arathi", mapID = 1417, names = { "Tierras Altas de Arathi", "Arathi Highlands" }, min = 30, max = 40, faction = "Both" },
  { label = "Desolace", mapID = 1443, names = { "Desolace" }, min = 30, max = 40, faction = "Both" },
  { label = "Vega de Tuercespina", mapID = 1434, names = { "Vega de Tuercespina", "Stranglethorn Vale" }, min = 30, max = 45, faction = "Both",
    tips = { "Las misiones de Hemet Nesingwary tienen recompensas nuevas.", "Mazmorra nueva frente a la costa: The Drowned City (35-42).", "Bahía del Botín: entrenador de pícaros (Ian Strom)." } },
  { label = "Riverglades", names = { "Riverglades", "Riverlands" }, min = 30, max = 45, faction = "Both",
    tips = { "Zona NUEVA. Mazmorra al aire libre: Krol'Dok Stronghold (40-47)." } },
  { label = "Pantano de las Penas", mapID = 1435, names = { "Pantano de las Penas", "Swamp of Sorrows" }, min = 35, max = 45, faction = "Both" },
  { label = "Tierras Inhóspitas", mapID = 1418, names = { "Tierras Inhóspitas", "Badlands" }, min = 35, max = 45, faction = "Both" },
  { label = "Marjal Revolcafango", mapID = 1445, names = { "Marjal Revolcafango", "Dustwallow Marsh" }, min = 35, max = 45, faction = "Both",
    tips = { "Theramore (Alianza). Mazmorra nueva: Alcaz Island Prison (48-55)." } },
  { label = "Feralas", mapID = 1444, names = { "Feralas" }, min = 40, max = 50, faction = "Both" },
  { label = "Tierras del Interior", mapID = 1425, names = { "Tierras del Interior", "The Hinterlands" }, min = 40, max = 50, faction = "Both" },
  { label = "Tanaris", mapID = 1446, names = { "Tanaris" }, min = 40, max = 50, faction = "Both" },
  { label = "Shen'dralas", names = { "Shen'dralas" }, min = 40, max = 55, faction = "Both", tips = { "Zona NUEVA." } },
  { label = "La Garganta de Fuego", mapID = 1427, names = { "La Garganta de Fuego", "Searing Gorge" }, min = 43, max = 50, faction = "Both" },
  { label = "Azshara", mapID = 1447, names = { "Azshara" }, min = 45, max = 55, faction = "Both", tips = { "Mazmorra nueva: Blackmaw Hold (55-60)." } },
  { label = "Frondavil", mapID = 1448, names = { "Frondavil", "Felwood" }, min = 45, max = 55, faction = "Both" },
  { label = "Las Tierras Devastadas", mapID = 1419, names = { "Las Tierras Devastadas", "Blasted Lands" }, min = 45, max = 55, faction = "Both" },
  { label = "Cráter de Un'Goro", mapID = 1449, names = { "Cráter de Un'Goro", "Un'Goro Crater" }, min = 48, max = 55, faction = "Both", tips = { "Mazmorra nueva: Shaper's Terrace (58-60)." } },
  { label = "Las Estepas Ardientes", mapID = 1428, names = { "Las Estepas Ardientes", "Burning Steppes" }, min = 50, max = 58, faction = "Both" },
  { label = "Tierras de la Peste del Oeste", mapID = 1422, names = { "Tierras de la Peste del Oeste", "Western Plaguelands" }, min = 50, max = 58, faction = "Both" },
  { label = "Tierras de la Peste del Este", mapID = 1423, names = { "Tierras de la Peste del Este", "Eastern Plaguelands" }, min = 53, max = 60, faction = "Both" },
  { label = "Cuna del Invierno", mapID = 1452, names = { "Cuna del Invierno", "Winterspring" }, min = 53, max = 60, faction = "Both",
    tips = { "Por Darkwhisper Gorge se llega al Monte Hyjal (zona nueva de nivel 60)." } },
  { label = "Silithus", mapID = 1451, names = { "Silithus" }, min = 55, max = 60, faction = "Both" },
  { label = "Monte Hyjal", names = { "Monte Hyjal", "Mount Hyjal" }, min = 60, max = 60, faction = "Both", tips = { "Zona NUEVA de nivel 60 y entrada a las bandas Barrow Deeps y Hyjal Summit (desde el 9/12)." } },
  { label = "Ventormenta", mapID = 1453, names = { "Ventormenta", "Stormwind City" }, min = 1, max = 60, city = true, faction = "Alliance",
    tips = { "Tranvía Subterráneo a Forjaz (Ironforge).", "Puerto: barco a Auberdine (Costa Oscura).", "Entrenadores de pícaro en Casco Antiguo: Lord Tony Romano y Osborne. Espadas: Woo Ping.", "Mathias Shaw empieza la misión de venenos (nivel 20)." } },
  { label = "Forjaz", mapID = 1455, names = { "Forjaz", "Ironforge" }, min = 1, max = 60, city = true, faction = "Alliance",
    tips = { "Hall of Thanes (13-20) está debajo de Forjaz, en Old Ironforge.", "Entrenadores de pícaro en la Caverna Olvidada. Mazas/puños/armas de fuego: Buliwyf Stonehand." } },
  { label = "Darnassus", mapID = 1457, names = { "Darnassus" }, min = 1, max = 60, city = true, faction = "Alliance",
    tips = { "Entrenadores de pícaro en el Enclave Cenarion (Anishar, Erion Shadewhisper, Syurna). Armas de puño y arcos: Ilyenia Moonfire." } },
}

G.zonesByMap = {}
for _, z in ipairs(G.zones) do if z.mapID then G.zonesByMap[z.mapID] = z end end

-- key = name used by the DungeonJournal addon, so its quests can be shown here. enter = { uiMapID, x%, y% } of the
-- entrance on this client's map, for the arrow and [Ir a la entrada]. via = { uiMapID, x%, y%, name } where the path
-- to an entrance up a hill starts: the arrow points there first (G.dq.entrancePoint).
G.dungeons = {
  { name = "Hall of Thanes", key = "Hall of Thanes", min = 13, max = 20, new = true, faction = "Alliance", where = "Debajo de Forjaz (Old Ironforge), Dun Morogh",
    howto = "Desde Costa Oscura: barco Auberdine -> Ventormenta, tranvía a Forjaz. Poné la piedra de hogar en la posada de Forjaz.",
    tips = {
      "El rey Magni NO da misiones de esta mazmorra. Son 4 (~16.000 XP en total):",
      "1) Important Heirlooms: Thom Filch, puente de la entrada en Forjaz (43.5, 52.0).",
      "2) The Restless Dead: Afadra Dunwall, arriba de Old Ironforge, AFUERA (33.3, 48.1).",
      "3) An Ancient Grudge: Ghostly Attendant, ADENTRO después de la primera sala. Se entrega a él mismo.",
      "4) Old Ironforge Incursion: primero el Dark Iron Map (espías de Ironband's Compound, Dun Morogh 76.2, 60.8) -> Earthseer Farsen (Dun Morogh 64.7, 58.4).",
      "El fantasma del rey Faldrim Anvilmar es un JEFE, no da misiones. 1-3 se comparten en grupo.",
    } },
  { name = "Ragefire Chasm", min = 13, max = 18, faction = "Horde", where = "Orgrimmar" },
  { name = "Ruins of Lordaeron", key = "Ruins of Lordaeron", min = 15, max = 22, new = true, where = "Claros de Tirisfal (historia de la Horda, la Alianza puede entrar)" },
  { name = "Wailing Caverns", key = "Wailing Caverns", min = 15, max = 24, where = "Los Baldíos (territorio Horda)" },
  { name = "The Deadmines", key = "The Deadmines", min = 17, max = 26, faction = "Alliance", where = "Villa Luna, Páramos de Poniente",
    howto = "Ideal con tus amigos humanos: está al lado de Elwynn.", tips = { "Varias misiones salen de Colina del Centinela (Sentinel Hill)." } },
  { name = "Shadowfang Keep", key = "Shadowfang Keep", min = 20, max = 30, where = "Bosque de Argénteos (territorio Horda)",
    tips = { "La misión de arma de pícaro (Horn of Xelthos) pasa por acá." } },
  { name = "Blackfathom Deeps", key = "Blackfathom Deeps", min = 24, max = 32, where = "Playa de Zoram, Vallefresno" },
  { name = "The Stockade", min = 25, max = 29, faction = "Alliance", where = "Ventormenta" },
  { name = "Excavation Site: Wetlands", min = 26, max = 33, new = true, where = "Excavación de Whelgar, Los Humedales",
    enter = { 1437, 47.8, 56.3 }, via = { 1437, 53.9, 65.4, "la Piedra de Encuentro (Roca Thelgen)" },
    howto = "Volá a Puerto de Menethil (o a Thelsamar y cruzá Dun Algaz). La Piedra de Encuentro está en 53.9, 65.4, a la izquierda de la Roca Thelgen; desde ahí subí la montaña hasta el portal, arriba de la Excavación de Whelgar (47.8, 56.3)." },
  { name = "City of Dalaran", min = 28, max = 35, new = true, where = "Montañas de Alterac" },
  { name = "Gnomeregan", min = 29, max = 38, where = "Dun Morogh" },
  { name = "Razorfen Kraul", min = 29, max = 38, where = "Los Baldíos" },
  { name = "Scarlet Monastery: Graveyard", min = 30, max = 38, where = "Claros de Tirisfal" },
  { name = "Scarlet Monastery: Library", min = 33, max = 41, where = "Claros de Tirisfal" },
  { name = "The Drowned City", min = 35, max = 42, new = true, where = "Frente a la costa de Tuercespina" },
  { name = "Scarlet Monastery: Armory", min = 36, max = 44, where = "Claros de Tirisfal" },
  { name = "Razorfen Downs", min = 37, max = 46, where = "Los Baldíos" },
  { name = "Scarlet Monastery: Cathedral", min = 38, max = 46, where = "Claros de Tirisfal" },
  { name = "Krol'Dok Stronghold", min = 40, max = 47, new = true, where = "Riverglades (al aire libre)" },
  { name = "Uldaman", min = 41, max = 51, where = "Tierras Inhóspitas" },
  { name = "Zul'Farrak", min = 44, max = 54, where = "Tanaris" },
  { name = "Maraudon", min = 46, max = 55, where = "Desolace" },
  { name = "Alcaz Island Prison", min = 48, max = 55, new = true, where = "Marjal Revolcafango" },
  { name = "Sunken Temple", min = 50, max = 60, where = "Pantano de las Penas" },
  { name = "Blackrock Depths", min = 52, max = 60, where = "Montaña Roca Negra" },
  { name = "Dire Maul", min = 54, max = 60, where = "Feralas" },
  { name = "Lower Blackrock Spire", min = 55, max = 60, where = "Montaña Roca Negra" },
  { name = "Blackmaw Hold", min = 55, max = 60, new = true, where = "Norte de Azshara" },
  { name = "Shaper's Terrace", min = 58, max = 60, new = true, where = "Cráter de Un'Goro" },
  { name = "Stratholme / Scholomance", min = 58, max = 60, where = "Tierras de la Peste" },
  { name = "Upper Blackrock Spire", min = 59, max = 60, where = "Montaña Roca Negra" },
}

-- Milestones every class shares.
G.milestones = {
  { level = 5, text = "Misión \"The Great Outdoors\" + Cocina: desbloquea los campamentos." },
  { level = 10, text = "Talentos (tecla N). Con el legado \"Talented\" llegan hasta 5 niveles antes." },
  { level = 10, text = "Profesiones nivel Oficial (Journeyman)." },
  { level = 14, text = "Saco de dormir acogedor: la cadena empieza en Páramos de Poniente (Granja Alexston, 37, 50). +3% XP por 1 h y descanso en cualquier lado." },
  { level = 20, text = "Profesiones nivel Experto (Expert)." },
  { level = 25, text = "Suele llegar tu primer punto de Legado (cuenta)." },
  { level = 30, text = "Campo de batalla Darkspear Islands (30-60)." },
  { level = 35, text = "Profesiones nivel Artesano (Artisan)." },
  { level = 40, text = "Equitación: 100 de oro (incluye la primera montura). Doble especialización en el entrenador." },
  { level = 60, text = "Equitación rápida (1000 de oro). Bandas: Onyxia, Barrow Deeps, Hyjal Summit (desde el 9/12)." },
}

-- One of these appears on the "Ahora" tab, filtered by level.
G.tips = {
  { text = "\"Bien alimentado\" (cualquier comida de Cocina en Forever) = +5% XP por muerte. Se pierde al morir: comé después del pull peligroso, no antes." },
  { text = "Descanso: 5% de la barra cada 8 h, tope 150%. Solo duplica XP por muerte: con descanso lleno, matá; sin descanso, entregá misiones." },
  { text = "Grupo de 5: cada uno recibe 1/5 x1.4 de la XP por muerte, pero las misiones dan el 100% a todos. Un compañero de mucho más nivel te baja la XP." },
  { text = "En mazmorras los bichos dan poca XP: lo que rinde son las misiones (una sola vez). Sin las misiones, no vale la pena entrar." },
  { text = "Máximo 5 instancias por hora por cuenta: si farmean una mazmorra, no reseteen de más." },
  { text = "Abandonar el grupo dentro de una mazmorra te teletransporta a tu piedra de hogar: sirve de hogar gratis si está en cooldown." },
  { text = "Saco de dormir acogedor: desconectarte encima cuenta como posada. No hace falta volver a la ciudad para acumular descanso." },
  { text = "Los objetos de misión tienen protección contra mala suerte: cada bicho sin drop sube la chance del siguiente." },
  { text = "Las bandas no comparten crédito de misión: para misiones, grupo de 5, nunca banda." },
  { max = 39, text = "Montura al 40: 100 de oro (la montura viene incluida con Equitación). Al 60, 1000." },
}

-- Quest ID -> short note shown on the "Misiones" tab. Only facts confirmed for Forever.
G.questNotes = {
  [96391] = "Empieza con un objeto (Dark Iron Map) de los Espías Hierro Negro. No se comparte: cada uno necesita su mapa.",
  [96393] = "La cabeza de Durgen Dirgehammer SOLO cae si tenés esta misión aceptada cuando lo matan.",
  [96395] = "La da y la recibe el Ghostly Attendant, ADENTRO después de la primera sala.",
  [96394] = "Tomala AFUERA (Afadra Dunwall, arriba de Old Ironforge) antes de entrar.",
  [96403] = "8 Dwarven Heirlooms dentro de la mazmorra. Recompensa: Tomb Robber's Gloves (buenos para pícaro).",
}

G.tipSections = {
  { title = "Sistemas nuevos de Forever", items = {
    "Legado: progreso de cuenta. ~65 desafíos; cada personaje gasta hasta 16 puntos en 3 árboles (Profesiones, Aventura, Recursos). Se resetea en el entrenador de clase.",
    "Legado útil para subir: Well Rested (+4% de descanso por rango), Talented (talentos antes), Permanence (+50% duración del descanso), Frequent Flier.",
    "Campamentos: fogata (Cocina) con 3/5/10 espacios. Cada profesión aporta un buff de 1 h: Peletería = descanso, Desuello = crítico, Minería = poder de ataque, Pesca = +8% estadísticas, Primeros auxilios = aguante.",
    "Saco de dormir acogedor: hasta +3% XP por 1 h (1% por minuto acostado) y cuenta como zona de descanso. Cadena en Páramos de Poniente.",
    "Grupo: la búsqueda de grupo es solo un tablero (sin teletransporte). Las piedras de encuentro NO invocan. Un brujo puede invocar si hay 2 más en la puerta.",
    "Reglas de reino: Normal / JcJ / Rol. Solo podés agruparte con gente de la misma regla y facción.",
    "Gestor de reutilizaciones integrado: Opciones o /cdm, y se ubica en Modo edición.",
    "Bandas desde el 9/12/2026: Onyxia (40), Barrow Deeps (10) y Hyjal Summit (20).",
  } },
  { title = "Trampas que nadie te dice", items = {
    "Antes del 10 el Ángel de la resurrección no aplica debilidad: revivir ahí es gratis.",
    "Elixires y \"Bien alimentado\" se pierden al morir; el buff de la Tienda de campaña NO.",
    "Los buffs de campamento no se suman al buff de clase equivalente (Piedra imán vs. Poderío): si hay paladín, la Piedra imán sobra.",
    "Un objeto de campamento de mayor nivel reemplaza al tuyo sin esperar el cooldown.",
    "Hay una ranura de bolsa nueva solo para componentes: una Linen Reagent Bag (Sastrería, 6 espacios) libera tus bolsas normales.",
    "No equipes un azul \"se liga al equiparlo\" sin mirar la subasta: en la primera semana pueden valer más que tu equipo entero.",
    { max = 30, text = "Entrenar todo del 1 al 60 cuesta ~200 de oro: no compres los rangos nuevos de hechizos que casi no usás." },
  } },
  { title = "Reino JcJ", items = {
    "Elfo de la noche: en Forever Fusión de las sombras baja tu amenaza en combate, no solo te esconde. Leé el tooltip.",
  } },
}
