-- Guía Forever: professions. Sources: Gfinity 1-300 guides (Oct-Nov 2026), Warcraft Tavern
-- (camping, cooking, skinning, professions), Method, BlizzardWatch (First Aid potions), wow.gg.
-- name = esMX skill name; alias = English.
local G = GuiaForever

local function nextRank(max)
  if max <= 75 then return "Oficial: nivel 10" end
  if max <= 150 then return "Experto: nivel 20" end
  if max <= 225 then return "Artesano: nivel 35" end
  return "siguiente rango"
end

G.professions = {
  { name = "Desuello", alias = "Skinning", label = "Desuello", nextRank = nextRank,
    brackets = {
      { from = 1, to = 45, text = "Lobos, jabalíes y escórpidos de zonas iniciales." },
      { from = 45, to = 75, text = "Costa Oscura, Páramos de Poniente, Loch Modan (lobos, raptores, cocodrilos). Entrená Oficial antes de 75." },
      { from = 75, to = 110, text = "Loch Modan: osos, cocodrilos, merodeadores." },
      { from = 110, to = 150, text = "Los Humedales, Vallefresno, Trabalomas (raptores, osos)." },
      { from = 150, to = 180, text = "Trabalomas, Arathi, Las Mil Agujas (leones, osos)." },
      { from = 180, to = 225, text = "Tuercespina, Feralas." },
      { from = 225, to = 260, text = "Tanaris, Tierras del Interior." },
      { from = 260, to = 280, text = "Un'Goro." },
      { from = 280, to = 300, text = "Cuna del Invierno, Tierras Devastadas, Silithus." },
    },
    tips = {
      "El cuchillo va en la bolsa, no equipado. Solo podés desollar bichos de nivel acorde a tu habilidad: subila al ritmo de tu nivel.",
      "Pieles NUEVAS escasas (Pristine/Fel): son las caras. El talento de Legado Bountiful Harvest da +20-100% de estas.",
      "Entrenadores: Darnassus (Elissa Baldras, Bancal del Artesano), Forjaz (Balthus Stoneflayer), Ventormenta (Maris Granger).",
      "Campamento (habilidad 20): Silla de campamento = crítico para el grupo.",
    } },
  { name = "Peletería", alias = "Leatherworking", label = "Peletería", nextRank = nextRank,
    brackets = {
      { from = 1, to = 35, text = "Curtí retazos de cuero arruinado / Armadura ligera. Tienda de campaña a 20 (5 Cuero ligero): +5% de descanso." },
      { from = 35, to = 55, text = "20 Light Armor Kit (Cuero ligero). Receta NUEVA desde 35: Dark Leather Boots (Granny Finespindle, Forjaz)." },
      { from = 55, to = 75, text = "Embossed Leather Gloves / Pants. A 60: Brawler's Leather Belt (vendedor)." },
      { from = 75, to = 100, text = "25 Embossed Leather Pants. A 85: Brawler's Boots (Daniel Stitchsong, Three Corners, Crestagrana)." },
      { from = 100, to = 125, text = "Cured Medium Hide, Fine Leather Belt (cuero medio). Experto con Sara Tanner (Villa del Lago, nivel 20)." },
      { from = 125, to = 150, text = "Dark Leather Boots / Dark Leather Pants (tinte gris)." },
      { from = 150, to = 190, text = "Cured Heavy Hide, Heavy Armor Kit, Barbarian's Shoulders." },
      { from = 190, to = 225, text = "Thick Armor Kit, Nightscape Headband. Artesano: Drakk Stonehand (Nido del Águila, nivel 35)." },
      { from = 225, to = 250, text = "Nightscape Pants / Boots." },
      { from = 250, to = 300, text = "Wicked Leather (Gauntlets, Bracers, Headband) con cuero basto." },
    },
    tips = {
      "Sets NUEVOS de Forever por rol: Brawler's, Prowler's, Skulker's, Stalker's... Mirá el tooltip: elegí los de Agilidad.",
      "Entrenadores: Telonis (Darnassus), Fimble Finespindle (Forjaz), Simon Tanner (Ventormenta).",
      "Los kits de armadura sirven para subir habilidad, no para ganar oro: casi no se venden.",
    } },
  { name = "Cocina", alias = "Cooking", label = "Cocina", nextRank = nextRank,
    brackets = {
      { from = 1, to = 40, text = "Herb Baked Eggs o Roasted Boar Meat. Cocina 1 = fogata básica (campamento)." },
      { from = 40, to = 75, text = "Smoked Bear Meat. Entrená Oficial a 50." },
      { from = 75, to = 100, text = "Crab Cake (carne de reptador + especias suaves)." },
      { from = 100, to = 130, text = "Seasoned Wolf Kebab. A 90: Fogata de oficial (5 espacios)." },
      { from = 130, to = 175, text = "Curiously Tasty Omelet / Hot Lion Chops. Experto: libro de Shandrina (Lago Mystral, Vallefresno), nivel 20." },
      { from = 175, to = 225, text = "Roast Raptor, Spider Sausage. A 200-220: Fogata experta (10 espacios)." },
      { from = 225, to = 300, text = "Monster Omelet, Tender Wolf Steak, Smoked Desert Dumplings. Artesano: misión \"Clamlette Surprise\" (Gadgetzan)." },
    },
    tips = { "Casi toda la comida da +5% XP por muerte (Bien alimentado). Se vende bien a otros jugadores.", "Entrenador en Darnassus: Alegorn (Bancal del Artesano)." } },
  { name = "Primeros auxilios", alias = "First Aid", label = "Primeros auxilios", nextRank = nextRank,
    brackets = {
      { from = 1, to = 40, text = "Linen Bandage. NUEVO: Minor Healing Potion (especias suaves + Flor de paz)." },
      { from = 40, to = 75, text = "Heavy Linen Bandage. Lesser Healing Potion a 55." },
      { from = 75, to = 150, text = "Vendas de lana. Healing Potion a 110. Simple Poultice (enfermedades) a 90, Woolen Tourniquet (sangrados) a 120." },
      { from = 150, to = 225, text = "Seda/Tejido mágico. Greater Healing Potion a 155. Experto: Deneb Walker (Stromgarde, Arathi)." },
      { from = 225, to = 300, text = "Tejido de runas. Superior (215) y Major (275) Healing Potion. Artesano: Doctor Gustaf VanHowzen (Theramore)." },
    },
    tips = { "En Forever Primeros auxilios hace las pociones de vida: para un pícaro es oro puro.", "Entrenador en Darnassus: Byancie." } },
  { name = "Pesca", alias = "Fishing", label = "Pesca", nextRank = nextRank,
    brackets = {
      { from = 1, to = 55, text = "Cualquier agua de zona inicial. Receta NUEVA: Find Fish (rastrea bancos)." },
      { from = 55, to = 75, text = "Costa Oscura, Páramos de Poniente, Loch Modan." },
      { from = 75, to = 150, text = "Crestagrana, Humedales, Vallefresno, Trabalomas. Experto: libro de Old Man Heming (Bahía del Botín)." },
      { from = 150, to = 225, text = "Tuercespina, Arathi, Feralas, Tanaris." },
      { from = 225, to = 300, text = "Feralas, Tanaris, Azshara, Un'Goro. Artesano: Nat Pagle (Marjal Revolcafango)." },
    },
    tips = { "Campamento: Pecera = +8% a todas las estadísticas.", "Señuelos: Shiny Bauble +25." } },
  { name = "Minería", alias = "Mining", label = "Minería", nextRank = nextRank,
    brackets = { { from = 1, to = 65, text = "Cobre (Elwynn, Dun Morogh, Costa Oscura)." }, { from = 65, to = 125, text = "Estaño." }, { from = 125, to = 175, text = "Hierro y oro (Humedales, Trabalomas)." }, { from = 175, to = 230, text = "Mitril (Tuercespina, Inhóspitas)." }, { from = 230, to = 300, text = "Torio (Un'Goro, Cuna del Invierno)." } },
    tips = { "Campamento: Piedra imán = poder de ataque (bueno para pícaros)." } },
  { name = "Herboristería", alias = "Herbalism", label = "Herboristería", nextRank = nextRank,
    brackets = { { from = 1, to = 50, text = "Flor de paz, Hojaplata." }, { from = 50, to = 125, text = "Hierba cardenal, Brezospina." }, { from = 125, to = 300, text = "Sangrerreal, Hierba de sol, Sangre de Grom, Hojasueño." } } },
  { name = "Alquimia", alias = "Alchemy", label = "Alquimia", nextRank = nextRank, tips = { "En Forever las pociones de vida pasaron a Primeros auxilios; Alquimia queda con elixires, frascos, aceites y transmutaciones." } },
  { name = "Herrería", alias = "Blacksmithing", label = "Herrería", nextRank = nextRank, tips = { "Piedras de afilar: ahora se acumulan con los venenos del pícaro." } },
  { name = "Ingeniería", alias = "Engineering", label = "Ingeniería", nextRank = nextRank, tips = { "La mejor para JcJ (granadas, utilidades). Floja para oro." } },
  { name = "Encantamiento", alias = "Enchanting", label = "Encantamiento", nextRank = nextRank },
  { name = "Sastrería", alias = "Tailoring", label = "Sastrería", nextRank = nextRank, tips = { "Hace la mayoría de las recetas nuevas (164). Linen Reagent Bag: bolsa para la ranura NUEVA de componentes." } },
  { name = "Ganzúa", alias = "Lockpicking", label = "Ganzúa (pícaro)",
    brackets = { { from = 1, to = 80, text = "Abrí cajas fuertes de misiones y cofres. La misión de venenos del 20 pide 80." } } },
}

G.professionGeneral = {
  "Rangos: Oficial (nivel 10, habilidad 50-150), Experto (nivel 20, 125-225), Artesano (nivel 35, 200-300). Experto/Artesano de Cocina, Pesca y Primeros auxilios se compran como libro o misión.",
  "Primera semana sin precios de referencia: recolectar y vender materiales es seguro; fabricar para vender es apostar.",
  "Demanda NUEVA en Forever: comida de XP y pociones de vida (Primeros auxilios). Los que suben las compran por stack.",
  "Legado de profesiones: Dedicated Study sube tu profesión más baja, Working Overtime da más chance de subir, Reagent Economy hace que los objetos de campamento básicos no gasten materiales.",
  "Campamento: cada profesión aporta un objeto a habilidad 20/140/300. En grupo de 3 juntan 3 buffs.",
}
