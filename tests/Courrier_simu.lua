-- Simulation hors jeu de Courrier : quelle action faire, dans quel ordre.
-- Lancer depuis Windows :
--   wsl lua5.1 tests/Courrier_simu.lua Courrier/Courrier.lua
local bidon
bidon = function()
  return setmetatable({}, { __index = function() return bidon() end, __call = function() return bidon() end })
end
function CreateFrame() return bidon() end
UIParent, SlashCmdList, UISpecialFrames, Minimap = {}, {}, {}, bidon()
tinsert = table.insert

local ns = {}
local reglagesLua = arg[1]:gsub("[^/]+$", "Reglages.lua")
assert(loadfile(reglagesLua))("Courrier", ns)
assert(loadfile(arg[1]))("Courrier", ns)

local ok = true
local function verifie(libelle, attendu, obtenu)
  local bon = attendu == obtenu
  ok = ok and bon
  io.write(string.format("%s %-55s attendu %s, obtenu %s\n", bon and "OK " or "KO ", libelle, tostring(attendu), tostring(obtenu)))
end

local function lire(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end
verifie("Reglages.lua identique dans QuetesAuto", true,
  lire(reglagesLua) == lire((reglagesLua:gsub("Courrier/Reglages", "QuetesAuto/Reglages"))))

local vente = { index = 1, expediteur = "Hôtel des ventes", sujet = "Vente", argent = 48000, nbObjets = 0, jours = 29 }
local colis = { index = 2, expediteur = "Jack", sujet = "Minerai", argent = 0, nbObjets = 2, premierePiece = 3, jours = 3 }
local cr = { index = 3, expediteur = "Inconnu", sujet = "Dague", argent = 0, contreRemboursement = 1200, nbObjets = 1, premierePiece = 1, jours = 2 }
local lettre = { index = 4, expediteur = "Garde", sujet = "Bonjour", argent = 0, nbObjets = 0, jours = 1 }
local mj = { index = 5, expediteur = "MJ", sujet = "Ticket", argent = 500, nbObjets = 1, premierePiece = 1, jours = 1, mj = true }
local boite = { vente, colis, cr, lettre, mj }

local a = ns.prochaineAction(boite, "tout", {}, 10)
verifie("tout : on part de la fin, le colis d'abord", 2, a and a.index)
verifie("tout : prendre l'objet du colis", "objet", a and a.action)
verifie("tout : la bonne pièce jointe", 3, a and a.piece)
local _, raison = ns.prochaineAction({ lettre, cr, mj }, "tout", {}, 10)
verifie("lettre, contre-remboursement, MJ : rien à faire", "fini", raison)
a = ns.prochaineAction(boite, "or", {}, 10)
verifie("or seulement : la vente", 1, a and a.index)
verifie("or seulement : de l'argent", "argent", a and a.action)
local _, plein = ns.prochaineAction({ colis }, "tout", {}, 0)
verifie("sacs pleins : on s'arrête et on le dit", "sacs pleins", plein)
a = ns.prochaineAction({ vente, colis }, "tout", {}, 0)
verifie("sacs pleins : l'or se prend quand même", "argent", a and a.action)
a = ns.prochaineAction(boite, "coches", { [ns.cleCourrier(vente)] = true }, 10)
verifie("cochés : seulement le courrier coché", 1, a and a.index)
local _, rien = ns.prochaineAction(boite, "coches", {}, 10)
verifie("cochés : rien de coché, rien à faire", "fini", rien)
a = ns.prochaineAction(boite, "tout", {}, 10, { [ns.cleCourrier(colis)] = true })
verifie("courrier bloqué : sauté", 1, a and a.index)
verifie("à récupérer, mode tout", 2, ns.restants(boite, "tout"))
verifie("à récupérer, mode or", 1, ns.restants(boite, "or"))
verifie("clé stable quand la place change", ns.cleCourrier(colis),
  ns.cleCourrier({ index = 1, expediteur = "Jack", sujet = "Minerai", argent = 0, nbObjets = 2, jours = 3 }))
verifie("clé stable pendant qu'on vide le courrier", ns.cleCourrier(colis),
  ns.cleCourrier({ index = 2, expediteur = "Jack", sujet = "Minerai", argent = 0, nbObjets = 1, jours = 3 }))
verifie("texte d'or", "4 po 80 pa", ns.texteArgent(48000))
verifie("texte d'or : rien", "0 pc", ns.texteArgent(0))

-- La recherche de la fenêtre de réglages commune (Reglages.lua)
local entrees = {
  { titre = "Sacs rangés", recherche = { { libelle = "Section « À équiper » et flèche verte", aide = "Les objets meilleurs", section = "Conseils", onglet = 2 } } },
  { titre = "GPS", recherche = { { libelle = "Taille de la flèche", section = "GPS", onglet = 1 }, { libelle = "Épingle du jeu", section = "GPS", onglet = 1 } } },
}
verifie("recherche : « fleche » sans accent, dans deux addons", 2, #ns.chercherReglages(entrees, "fleche"))
verifie("recherche : par le nom de l'addon", 2, #ns.chercherReglages(entrees, "gps"))
verifie("recherche : le bon onglet", 2, (ns.chercherReglages(entrees, "equiper")[1] or { item = {} }).item.onglet)
verifie("recherche : rien", 0, #ns.chercherReglages(entrees, "licorne"))
verifie("recherche : texte vide", 0, #ns.chercherReglages(entrees, ""))

if ok then print("Tout est bon.") end
os.exit(ok and 0 or 1)
