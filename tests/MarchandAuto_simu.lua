-- Simulation hors jeu de Marchand auto : quoi vendre, qui paie la réparation.
-- Lancer depuis Windows :
--   wsl lua5.1 tests/MarchandAuto_simu.lua MarchandAuto/MarchandAuto.lua
local bidon
bidon = function()
  return setmetatable({}, { __index = function() return bidon() end, __call = function() return bidon() end })
end
function CreateFrame() return bidon() end
UIParent, SlashCmdList, UISpecialFrames, Minimap = {}, {}, {}, bidon()
tinsert = table.insert

local ns = {}
local reglagesLua = arg[1]:gsub("[^/]+$", "Reglages.lua")
assert(loadfile(reglagesLua))("MarchandAuto", ns)
assert(loadfile(arg[1]))("MarchandAuto", ns)

local ok = true
local function verifie(libelle, attendu, obtenu)
  local bon = attendu == obtenu
  ok = ok and bon
  io.write(string.format("%s %-50s attendu %s, obtenu %s\n", bon and "OK " or "KO ", libelle, tostring(attendu), tostring(obtenu)))
end

-- Reglages.lua doit être la même copie dans chaque addon.
local function lire(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end
verifie("Reglages.lua identique dans QuetesAuto", true,
  lire(reglagesLua) == lire((reglagesLua:gsub("MarchandAuto/Reglages", "QuetesAuto/Reglages"))))

-- Achat du stock.
verifie("stock : il en manque 15, vendus à l'unité", 15, ns.lotsAAcheter(20, 5, 1, 10, 100000))
verifie("stock : déjà assez", 0, ns.lotsAAcheter(20, 25, 1, 10, 100000))
verifie("stock : vendus par 5, il en manque 12 → 3 lots", 3, ns.lotsAAcheter(20, 8, 5, 10, 100000))
verifie("stock : pas assez d'or → ce qu'on peut", 4, ns.lotsAAcheter(20, 0, 1, 25, 100))
verifie("stock : pas d'or du tout", 0, ns.lotsAAcheter(20, 0, 1, 25, 0))

verifie("gris : vendu", true, ns.aVendre({ quality = 0, itemID = 1 }, {}))
verifie("blanc : gardé", false, ns.aVendre({ quality = 1, itemID = 1 }, {}))
verifie("gris sans valeur : gardé", false, ns.aVendre({ quality = 0, hasNoValue = true }, {}))
verifie("gris de la liste à garder : gardé", false, ns.aVendre({ quality = 0, itemID = 7 }, { [7] = true }))
verifie("case vide : rien", false, ns.aVendre(nil, {}))

verifie("guilde sans limite : la guilde paie", "guilde", ns.payeur(500, 0, -1, true))
verifie("guilde pas assez : toi", "perso", ns.payeur(500, 1000, 100, true))
verifie("option guilde coupée : toi", "perso", ns.payeur(500, 1000, -1, false))
verifie("pas assez d'or nulle part : rien", nil, ns.payeur(500, 100, nil, true))
verifie("rien à réparer : rien", nil, ns.payeur(0, 1000, -1, true))

-- Lignes des listes de la fenêtre.
local retires = {}
local function retirer(id) retires[#retires + 1] = id end
local info = function(id) if id == 3 then return "Pomme" end end
verifie("nom : pris du lien", "Eau", ns.nomObjet(1, "|cffffffff|Hitem:1|h[Eau]|h|r", info))
verifie("nom : pris du jeu sans lien", "Pomme", ns.nomObjet(3, nil, info))
verifie("nom : repli", "objet 9", ns.nomObjet(9, true, info))
local g = ns.lignesGardes({ [2] = "[Zèbre]", [1] = "[abeille]", [3] = true }, info, retirer)
verifie("gardes : 3 lignes", 3, #g)
verifie("gardes : tri par nom sans casse", "abeille", g[1].texte)
verifie("gardes : lien de survol", "item:1", g[1].lien)
g[2].retirer()
verifie("gardes : la croix retire l'objet", 3, retires[1])
verifie("gardes : liste vide", 0, #ns.lignesGardes(nil, info, retirer))
local st = ns.lignesStock({ [5] = { lien = "[Eau]", qte = 20 }, [6] = { lien = "[Biscuit]", qte = 5 } }, info, retirer)
verifie("stock : « 5 x Biscuit » en premier", "5 x Biscuit", st[1].texte)
verifie("stock : « 20 x Eau »", "20 x Eau", st[2].texte)
st[2].retirer()
verifie("stock : la croix retire l'objet", 5, retires[2])
os.exit(ok and 0 or 1)
