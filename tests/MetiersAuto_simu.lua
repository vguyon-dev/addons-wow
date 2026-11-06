-- Simulation hors jeu de Métiers auto : lecture des recettes et liste de courses.
-- Lancer depuis Windows :
--   wsl lua5.1 tests/MetiersAuto_simu.lua MetiersAuto/MetiersAuto.lua
local bidon
bidon = function()
  return setmetatable({}, { __index = function() return bidon() end, __call = function() return bidon() end })
end
function CreateFrame() return bidon() end
UIParent, SlashCmdList, UISpecialFrames, Minimap, WorldFrame, C_Timer = {}, {}, {}, bidon(), bidon(), bidon()
tinsert = table.insert

local ns = {}
local reglagesLua = arg[1]:gsub("[^/]+$", "Reglages.lua")
assert(loadfile(reglagesLua))("MetiersAuto", ns)
assert(loadfile(arg[1]))("MetiersAuto", ns)

local ok = true
local function verifie(libelle, attendu, obtenu)
  local bon = attendu == obtenu
  ok = ok and bon
  io.write(string.format("%s %-50s attendu %s, obtenu %s\n", bon and "OK " or "KO ", libelle, tostring(attendu), tostring(obtenu)))
end

local function lire(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end
verifie("Reglages.lua identique dans QuetesAuto", true,
  lire(reglagesLua) == lire((reglagesLua:gsub("MetiersAuto/Reglages", "QuetesAuto/Reglages"))))

local lien = "|cffffd000|Henchant:2657|h[Fabriquer : Barre de cuivre]|h|r"
local n, id = ns.lireRecette("5 " .. lien)
verifie("« 5 [recette] » : nombre", 5, n)
verifie("« 5 [recette] » : numéro", 2657, id)
n, id = ns.lireRecette(lien)
verifie("« [recette] » seul : 1 fois", 1, n)
verifie("numéro tapé à la main", 2657, select(2, ns.lireRecette("2657")))

-- Deux recettes qui demandent toutes deux du minerai (qualités 1 et 2 = deux ids).
local recettes = {
  [1] = { { ids = { 10, 11 }, quantite = 2 }, { ids = { 20 }, quantite = 1 } },
  [2] = { { ids = { 10, 11 }, quantite = 3 } },
}
local b = ns.besoins({ { recette = 1, nombre = 5 }, { recette = 2, nombre = 2 } }, function(r) return recettes[r] end)
verifie("composants regroupés", 2, #b)
verifie("minerai : 5×2 + 2×3", 16, b[1].besoin)
local stock = { [10] = 4, [11] = 3, [20] = 9 }
local a, manque = ns.manque(b[1], function(i) return stock[i] end)
verifie("minerai possédé (deux qualités additionnées)", 7, a)
verifie("minerai manquant", 9, manque)
verifie("rien ne manque", 0, select(2, ns.manque(b[2], function(i) return stock[i] end)))

-- Filons mémorisés et flèche (carte de 1000 m sur 1000 m).
local liste = {}
verifie("filon : nouvel endroit", true, ns.memoriser(liste, 0.5, 0.5, "Cuivre", 1000, 1000))
verifie("filon : même endroit à 10 m près", false, ns.memoriser(liste, 0.505, 0.5, "Cuivre", 1000, 1000))
verifie("filon : deux endroits retenus", true, ns.memoriser(liste, 0.6, 0.5, "Étain", 1000, 1000))
verifie("distance : 100 m vers l'est", 100, math.floor(ns.distance(0.5, 0.5, 0.6, 0.5, 1000, 1000) + 0.5))
local p, d = ns.plusProche(liste, 0.5, 0.5, 1000, 1000, {}, 0)
verifie("plus proche : saute celui où je suis", "Étain", p and p[3])
local recent = { [liste[2]] = 100 }
verifie("plus proche : saute celui récolté il y a peu", nil, (ns.plusProche(liste, 0.5, 0.5, 1000, 1000, recent, 150)))
verifie("plus proche : revient après 3 minutes", "Étain", (ns.plusProche(liste, 0.5, 0.5, 1000, 1000, recent, 400) or {})[3])
local function arrondi(a) a = a % (2 * math.pi) return math.floor(a * 100 + 0.5) / 100 end
verifie("flèche : cible au nord, je regarde au nord", 0, arrondi(ns.angleFleche(0.5, 0.5, 0.5, 0.4, 1000, 1000, 0)))
verifie("flèche : cible à l'est, je regarde au nord", arrondi(-math.pi / 2), arrondi(ns.angleFleche(0.5, 0.5, 0.6, 0.5, 1000, 1000, 0)))
verifie("flèche : cible à l'est, je regarde à l'est", 0, arrondi(ns.angleFleche(0.5, 0.5, 0.6, 0.5, 1000, 1000, -math.pi / 2)))
verifie("flèche : cible derrière moi", arrondi(math.pi), arrondi(ns.angleFleche(0.5, 0.5, 0.5, 0.6, 1000, 1000, 0)))

os.exit(ok and 0 or 1)
