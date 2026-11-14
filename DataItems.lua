-- Guía Forever: hand-written uses for items that are not recipe reagents (those come from DataRecipes.lua).
-- Shown as "Sirve para: ..." in item tooltips. Items not listed fall back to their item class/subclass.
local G = GuiaForever

G.itemUses = {
  [5523] = "Abrila con clic derecho: trae Carne de almeja (Cocina) y a veces una perla",
  [5524] = "Abrila con clic derecho: trae Carne de almeja (Cocina) y a veces una perla",
  [5140] = "Pícaro: lo gasta la habilidad Desvanecerse",
}

-- Recipe subclasses (item class 9) -> profession names that can learn them (esMX, English).
G.recipeProfs = {
  [1] = { "Peletería", "Leatherworking" }, [2] = { "Sastrería", "Tailoring" }, [3] = { "Ingeniería", "Engineering" },
  [4] = { "Herrería", "Blacksmithing" }, [5] = { "Cocina", "Cooking" }, [6] = { "Alquimia", "Alchemy" },
  [7] = { "Primeros auxilios", "First Aid" }, [8] = { "Encantamiento", "Enchanting" }, [9] = { "Pesca", "Fishing" },
}
