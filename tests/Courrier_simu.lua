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

-- Les destinataires rapides
local r = ns.retenirDestinataire({ "Anna", "Bob", "Cléo" }, "  bob ", 8)
verifie("derniers : le plus récent en tête, sans doublon", "bob/Anna/Cléo", table.concat(r, "/"))
local plein = {}
for i = 1, 8 do plein[i] = "P" .. i end
r = ns.retenirDestinataire(plein, "Nouveau", 8)
verifie("derniers : 8 au plus", 8, #r)
verifie("derniers : le plus ancien sort", "P7", r[8])
verifie("derniers : nom vide ignoré", "Anna", table.concat(ns.retenirDestinataire({ "Anna" }, "   "), "/"))
verifie("derniers : liste vide au départ", "Zed", table.concat(ns.retenirDestinataire(nil, "Zed"), "/"))

local persos = {}
verifie("perso retenu", true, ns.retenirPerso(persos, "Hyjal", "Moi"))
verifie("perso déjà connu", false, ns.retenirPerso(persos, "Hyjal", "Moi"))
verifie("perso sans nom refusé", false, ns.retenirPerso(persos, "Hyjal", " "))
verifie("perso sans royaume refusé", false, ns.retenirPerso(persos, nil, "Moi"))
ns.retenirPerso(persos, "Hyjal", "Zoe")
ns.retenirPerso(persos, "Hyjal", "alba")
ns.retenirPerso(persos, "Archimonde", "Ailleurs")
local liste = ns.listeDestinataires(persos, "Hyjal", "Moi", { "Bob", "zoe", "Moi", "Cléo" })
local texte = {}
for _, e in ipairs(liste) do texte[#texte + 1] = e.section and ("[" .. e.section .. "]") or e.nom end
verifie("liste : autres persos du royaume puis derniers, sans doublon ni soi-même",
  "[Mes personnages]/alba/Zoe/[Derniers destinataires]/Bob/Cléo", table.concat(texte, "/"))
liste = ns.listeDestinataires({}, "Hyjal", "Moi", {})
verifie("liste : vide", 0, #liste)
liste = ns.listeDestinataires(nil, "Hyjal", "Moi", { "Bob" })
verifie("liste : seulement des derniers", "Derniers destinataires", liste[1] and liste[1].section)
local gros = {}
for i = 1, 12 do gros[i] = "D" .. i end
local n = 0
for _, e in ipairs(ns.listeDestinataires({}, "H", "M", gros)) do if e.nom then n = n + 1 end end
verifie("liste : 8 derniers au plus", 8, n)

liste = ns.listeDestinataires(persos, "Hyjal", "Moi", { "Zorro" })
verifie("compléter : début de nom", "alba", ns.completerNom("AL", liste))
verifie("compléter : un dernier destinataire", "Zorro", ns.completerNom("zor", liste))
verifie("compléter : le premier de la liste", "Zoe", ns.completerNom("Z", liste))
verifie("compléter : rien trouvé", nil, ns.completerNom("Xyz", liste))
verifie("compléter : rien tapé", nil, ns.completerNom("  ", liste))

-- Le bilan
local cr2 = { index = 3, expediteur = "Inconnu", sujet = "Dague", argent = 0, contreRemboursement = 1200, nbObjets = 1, premierePiece = 1, jours = 2 }
local l = ns.courriersLaisses({ vente, colis, cr2, lettre, mj }, "tout", {}, {}, false)
verifie("laissés : contre-remboursement", 1, l.contreRemboursement)
verifie("laissés : MJ", 1, l.mj)
verifie("laissés : pas de sacs pleins", 0, l.sacsPleins)
l = ns.courriersLaisses({ colis, cr2 }, "tout", {}, {}, true)
verifie("laissés : sacs pleins (le colis reste)", 1, l.sacsPleins)
l = ns.courriersLaisses({ colis }, "tout", {}, { [ns.cleCourrier(colis)] = true }, true)
verifie("laissés : bloqué, pas compté en sacs pleins", "1/0", l.bloques .. "/" .. l.sacsPleins)
l = ns.courriersLaisses({ vente, cr2 }, "coches", { [ns.cleCourrier(vente)] = true }, {}, false)
verifie("laissés : mode cochés, hors sélection ignoré", 0, l.contreRemboursement)
l = ns.courriersLaisses({ colis, vente }, "or", {}, {}, false)
verifie("laissés : mode or, les objets restants ne comptent pas", 0, l.sacsPleins + l.bloques)
verifie("laissés : boîte vide", 0, ns.courriersLaisses(nil, "tout").mj)
verifie("bilan : or et objets", "4 po 80 pa, 12 objet(s)", ns.texteBilan(48000, 12))
verifie("bilan : pas d'or", "pas d'or, 0 objet(s)", ns.texteBilan(0, 0))
verifie("bilan : rien de laissé", nil, ns.texteLaisses({ contreRemboursement = 0, mj = 0, sacsPleins = 0, bloques = 0 }))
verifie("bilan : laissés avec la raison",
  "courriers laissés de côté : 2 en contre-remboursement (jamais payé), 1 de MJ (jamais ouvert), 3 faute de place dans les sacs",
  ns.texteLaisses({ contreRemboursement = 2, mj = 1, sacsPleins = 3, bloques = 0 }))
verifie("bilan : bloqués", "courriers laissés de côté : 1 impossible(s) à vider", ns.texteLaisses({ bloques = 1 }))
verifie("bilan : table absente", nil, ns.texteLaisses(nil))
verifie("arrêt : message donné, gardé", "terminé", ns.messageArret("terminé", "Courrier coupé", true, 0, 0))
verifie("arrêt : boîte fermée par défaut", "boîte fermée", ns.messageArret(nil, nil, true, 100, 0))
verifie("arrêt : addon coupé", "Courrier coupé", ns.messageArret(nil, "Courrier coupé", true, 0, 2))
verifie("arrêt : rien pris, rien à dire", nil, ns.messageArret(nil, "Courrier coupé", true, 0, 0))
verifie("arrêt : bilan coupé, rien à dire", nil, ns.messageArret(nil, nil, false, 100, 2))

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
