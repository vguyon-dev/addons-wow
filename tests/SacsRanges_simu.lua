-- Simulation hors jeu de Sacs rangés : équipement en double et moins bon.
-- Lancer depuis Windows :
--   wsl lua5.1 tests/SacsRanges_simu.lua SacsRanges/SacsRanges.lua
local bidon
bidon = function()
  return setmetatable({}, { __index = function() return bidon() end, __call = function() return bidon() end })
end
function CreateFrame() return bidon() end
UIParent, SlashCmdList, UISpecialFrames, Minimap = {}, {}, {}, bidon()
tinsert = table.insert

local ns = {}
local reglagesLua = arg[1]:gsub("[^/]+$", "Reglages.lua")
assert(loadfile(reglagesLua))("SacsRanges", ns)
assert(loadfile(arg[1]))("SacsRanges", ns)
assert(loadfile((arg[1]:gsub("[^/]+$", "Conseils.lua"))))("SacsRanges", ns)
assert(loadfile((arg[1]:gsub("[^/]+$", "Vue.lua"))))("SacsRanges", ns)

local ok = true
local function verifie(libelle, attendu, obtenu)
  local bon = attendu == obtenu
  ok = ok and bon
  io.write(string.format("%s %-50s attendu %s, obtenu %s\n", bon and "OK " or "KO ", libelle, tostring(attendu), tostring(obtenu)))
end

local function lire(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end
verifie("Reglages.lua identique dans QuetesAuto", true,
  lire(reglagesLua) == lire((reglagesLua:gsub("SacsRanges/Reglages", "QuetesAuto/Reglages"))))

local porte = { [1] = 200, [11] = 210, [12] = 190, [16] = 220 }
local objets = {
  { id = 1, lien = "Casque", niveau = 180, type = "INVTYPE_HEAD" },     -- moins bon (200)
  { id = 2, lien = "Bague", niveau = 195, type = "INVTYPE_FINGER" },    -- mieux que la bague à 190
  { id = 3, lien = "Bague faible", niveau = 150, type = "INVTYPE_FINGER" },
  { id = 3, lien = "Bague faible", niveau = 150, type = "INVTYPE_FINGER" }, -- en double
  { id = 4, lien = "Potion", niveau = 1, type = "INVTYPE_NON_EQUIP_IGNORE" }, -- pas de l'équipement
  { id = 4, lien = "Potion", niveau = 1, type = "INVTYPE_NON_EQUIP_IGNORE" },
  { id = 5, lien = "Cape", niveau = 100, type = "INVTYPE_CLOAK" },      -- rien porté au dos : on ne juge pas
}
local doublons, moinsBons = ns.analyser(objets, porte)
verifie("doublons : seulement l'équipement", 1, #doublons)
verifie("doublons : la bague faible ×2", 2, doublons[1] and doublons[1].nombre)
verifie("moins bons : casque, bague faible ×2", 3, #moinsBons)
verifie("moins bons : le plus faible d'abord", 150, moinsBons[1] and moinsBons[1].niveau)
verifie("bague comparée à la plus faible portée", 190, moinsBons[1] and moinsBons[1].porte)
local _, avecEcart = ns.analyser(objets, porte, 25)
verifie("écart de 25 niveaux : seule la bague faible", 2, #avecEcart)

-- Équipement que le personnage ne peut pas porter : sa propre liste, même s'il est meilleur.
local mailles = { { id = 6, lien = "Cotte de mailles", niveau = 250, type = "INVTYPE_CHEST", utilisable = false },
  { id = 7, lien = "Casque de cuir", niveau = 150, type = "INVTYPE_HEAD", utilisable = true } }
local _, mb, inut = ns.analyser(mailles, porte)
verifie("inutilisable : listé à part", 1, #inut)
verifie("inutilisable : c'est la cotte de mailles", "Cotte de mailles", inut[1] and inut[1].lien)
verifie("inutilisable : pas aussi dans « moins bon »", 1, #mb)

local C = ns.COMPETENCES
local chasseur20 = function(s) return s == C[4][1] or s == C[4][2] or s == C[2][2] end
verifie("chasseur niveau 20 : mailles, non", false, ns.utilisable(4, 3, chasseur20))
verifie("chasseur : épée pas apprise, non", false, ns.utilisable(2, 7, chasseur20))
verifie("chasseur : arc appris, oui", true, ns.utilisable(2, 2, chasseur20))
verifie("ligne rouge dans la bulle : non", false, ns.utilisable(4, 0, chasseur20, true))

-- La table des compétences doit rester la même que celle de QuetesAuto.
local qa = {}
local bidonQA
bidonQA = function()
  return setmetatable({}, { __index = function() return bidonQA() end, __call = function() return bidonQA() end })
end
local quetes = (reglagesLua:gsub("SacsRanges/Reglages.lua", "QuetesAuto/"))
assert(loadfile(quetes .. "Reglages.lua"))("QuetesAuto", qa)
assert(loadfile(quetes .. "QuetesAuto.lua"))("QuetesAuto", qa)
local pareil = true
for classe, t in pairs(C) do
  for sc, sort in pairs(t) do if qa.COMPETENCES[classe][sc] ~= sort then pareil = false end end
end
for classe, t in pairs(qa.COMPETENCES) do
  for sc, sort in pairs(t) do if C[classe][sc] ~= sort then pareil = false end end
end
verifie("compétences identiques à QuetesAuto", true, pareil)
-- Vue par catégories : la section de chaque objet.
verifie("catégorie : arme portable", "equip", ns.categorie(2, 2, false, true))
verifie("catégorie : arme pas apprise, à vendre", "vendre", ns.categorie(2, 1, false, false))
verifie("catégorie : gris, à vendre", "vendre", ns.categorie(15, 0, false, true))
verifie("catégorie : objet de quête gris reste en Quête", "quete", ns.categorie(15, 0, true, true))
verifie("catégorie : classe quête", "quete", ns.categorie(12, 1, false, true))
verifie("catégorie : potion", "conso", ns.categorie(0, 1, false, true))
verifie("catégorie : étoffe", "compo", ns.categorie(7, 1, false, true))
verifie("catégorie : inconnue (pas encore lue)", "divers", ns.categorie(nil, 1, false, true))
local parts = ns.repartir({
  { sac = 0, case = 3, categorie = "compo", nom = "Pierre brute", qualite = 1 },
  { sac = 0, case = 1, categorie = "compo", nom = "Étoffe de lin", qualite = 1 },
  { sac = 1, case = 2, categorie = "compo", nom = "Cristal", qualite = 3 },
  { sac = 0, case = 2, categorie = "rien", nom = "Truc", qualite = 1 },
})
verifie("répartition : meilleure qualité d'abord", "Cristal", parts.compo[1].nom)
verifie("répartition : catégorie inconnue en Divers", 1, #parts.divers)
verifie("répartition : 3 composants", 3, #parts.compo)
verifie("recherche sans accents", true, ns.simplifier("Étoffe de LIN"):find("etoffe", 1, true) ~= nil)
verifie("recherche : œ", "oeil de murloc", ns.simplifier("Œil de murloc"))

-- Objets conseillés à équiper (Conseils.lua)
local milice = { stats = { dps = 2.0 }, type = "INVTYPE_WEAPON", nom = "Dague de la milice" }
local usee = { stats = { dps = 0.9 }, type = "INVTYPE_WEAPON" }
verifie("dague usée moins bonne que la milice : pas de conseil", nil, ns.comparer(usee, { [16] = milice }, "agilite", false, false))
local gants = ns.comparer({ stats = { agilite = 2, endurance = 1 }, type = "INVTYPE_HAND" }, {}, "agilite")
verifie("gants sur un emplacement vide", "emplacement vide", gants and gants.raison)
local arc = ns.comparer({ stats = { dps = 3.0 }, type = "INVTYPE_RANGEDRIGHT" },
  { [16] = { stats = { dps = 1.8 }, type = "INVTYPE_RANGEDRIGHT", nom = "Arc usé" } }, "agilite", false)
verifie("arc meilleur : la raison", "+1,2 dégâts par seconde", arc and arc.raison)
verifie("arc meilleur : ce qu'il remplace", "Arc usé", arc and arc.remplace)
local bague = ns.comparer({ stats = { agilite = 3 }, type = "INVTYPE_FINGER" },
  { [11] = { stats = { agilite = 5 }, nom = "Forte" }, [12] = { stats = { agilite = 1 }, nom = "Faible" } }, "agilite")
verifie("bague : remplace la plus faible", "Faible", bague and bague.remplace)
verifie("bague : la raison", "+2 Agilité", bague and bague.raison)
local deuxMains = { stats = { dps = 4, force = 2 }, type = "INVTYPE_2HWEAPON", nom = "Grande hache" }
verifie("main gauche vide sous une arme à deux mains : pas un trou", nil,
  ns.comparer({ stats = { force = 1 }, type = "INVTYPE_SHIELD" }, { [16] = deuxMains }, "force"))
local hache = ns.comparer({ stats = { dps = 5, force = 3 }, type = "INVTYPE_2HWEAPON" },
  { [16] = { stats = { dps = 2 }, type = "INVTYPE_WEAPON" }, [17] = { stats = { force = 1 }, type = "INVTYPE_SHIELD" } }, "force")
verifie("deux mains mieux que arme + bouclier", true, hache ~= nil)
verifie("lanceur : les dégâts de l'arme comptent peu", nil,
  ns.comparer({ stats = { dps = 3 }, type = "INVTYPE_WEAPON" }, { [16] = { stats = { dps = 1, intelligence = 2 } } }, "intelligence"))
verifie("sans ambidextrie : pas de conseil pour la main gauche vide", nil,
  ns.comparer({ stats = { dps = 1 }, type = "INVTYPE_WEAPON" }, { [16] = milice }, "agilite", false, false))
verifie("ambidextre : main gauche vide conseillée", "emplacement vide",
  (ns.comparer({ stats = { dps = 1 }, type = "INVTYPE_WEAPON" }, { [16] = milice }, "agilite", false, true) or {}).raison)
local st = ns.lireStats({ ITEM_MOD_AGILITY_SHORT = 2, ITEM_MOD_CRIT_RATING_SHORT = 3, ITEM_MOD_HASTE_RATING_SHORT = 1, BIDON = 9 })
verifie("lecture des caractéristiques", "2/4", st.agilite .. "/" .. st.secondaires)
verifie("sans caractéristiques : le niveau d'objet tranche", true, ns.comparer({ stats = {}, niveau = 12, type = "INVTYPE_CLOAK" },
  { [15] = { stats = {}, niveau = 8, nom = "Cape" } }, "agilite") ~= nil)
-- Outils de métier : leur propre section, jamais comparés comme des armes
verifie("canne à pêche (arme, sous-classe 20) : Métiers", "metier", ns.categorie(2, 1, false, true, 20, 6256))
verifie("couteau à dépecer (arme divers, 14) : Métiers", "metier", ns.categorie(2, 1, false, true, 14, 7005))
verifie("outil de métier Retail (classe 19) : Métiers", "metier", ns.categorie(19, 1, false, true, 0, 1))
verifie("une vraie dague reste de l'équipement", "equip", ns.categorie(2, 2, false, true, 15, 2092))
verifie("un outil d'objet de quête reste en Quête", "quete", ns.categorie(2, 1, true, true, 14, 7005))
-- Livres de bibliothèque et objets liés sans usage d'artisanat
verifie("livre de bibliothèque : Quête (à rendre)", "quete", ns.categorie(15, 3, false, true, 0, 1, { livre = true }))
verifie("objet lié, classe composant, pas d'artisanat : Divers", "divers", ns.categorie(7, 3, false, true, 0, 1, { lie = true, artisanat = false }))
verifie("vrai composant lié (artisanat) : Composants", "compo", ns.categorie(7, 1, false, true, 0, 1, { lie = true, artisanat = true }))
verifie("composant non lié : Composants", "compo", ns.categorie(7, 1, false, true, 0, 1, { lie = false, artisanat = false }))
os.exit(ok and 0 or 1)
