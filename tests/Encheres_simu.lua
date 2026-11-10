-- Simulation hors jeu d'Enchères : prix minimum, âge, attente entre relevés.
-- Lancer depuis Windows :
--   wsl lua5.1 tests/Encheres_simu.lua Encheres/Encheres.lua
local bidon
bidon = function()
  return setmetatable({}, { __index = function() return bidon() end, __call = function() return bidon() end })
end
function CreateFrame() return bidon() end
UIParent, SlashCmdList, UISpecialFrames, Minimap = {}, {}, {}, bidon()
tinsert = table.insert

local ns = {}
local reglagesLua = arg[1]:gsub("[^/]+$", "Reglages.lua")
assert(loadfile(reglagesLua))("Encheres", ns)
assert(loadfile(arg[1]))("Encheres", ns)

local ok = true
local function verifie(libelle, attendu, obtenu)
  local bon = attendu == obtenu
  ok = ok and bon
  io.write(string.format("%s %-55s attendu %s, obtenu %s\n", bon and "OK " or "KO ", libelle, tostring(attendu), tostring(obtenu)))
end

local function lire(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end
verifie("Reglages.lua identique dans QuetesAuto", true,
  lire(reglagesLua) == lire((reglagesLua:gsub("Encheres/Reglages", "QuetesAuto/Reglages"))))

local mins = ns.minimums({
  { id = 2589, quantite = 20, prixAchat = 2000 },   -- étoffe de lin : 100 l'unité
  { id = 2589, quantite = 5, prixAchat = 400 },     -- 80 l'unité : le moins cher
  { id = 2589, quantite = 1, prixAchat = 0 },       -- enchère seule : ignorée
  { id = 2770, quantite = 3, prixAchat = 1000 },    -- 333,3 -> 333
})
verifie("prix à l'unité le plus bas", 80, mins[2589])
verifie("arrondi à la pièce", 333, mins[2770])
local t = {}
verifie("enregistrement : nombre d'objets", 2, ns.enregistrer(t, mins, 1000))
verifie("enregistrement : prix et date", "80/1000", t[2589][1] .. "/" .. t[2589][2])
verifie("âge : à l'instant", "à l'instant", ns.age(30))
verifie("âge : minutes", "il y a 45 min", ns.age(2700))
verifie("âge : heures", "il y a 3 h", ns.age(3 * 3600 + 100))
verifie("âge : jours", "il y a 2 j", ns.age(2 * 86400 + 5))
verifie("numéro depuis un lien", 2589, ns.idObjet("|cffffffff|Hitem:2589::::::::60:::::|h[Étoffe de lin]|h|r"))
verifie("numéro direct", 2589, ns.idObjet(2589))
verifie("relevé : jamais fait, tout de suite", 0, ns.attenteReleve(nil, 5000))
verifie("relevé : 15 min entre deux", 600, ns.attenteReleve(1000, 1300))

-- Le prix conseillé à la mise en vente.
verifie("conseil lot : 1 cuivre sous le plus bas", 499, (ns.prixConseille(500, nil, true)))
verifie("conseil lot : raison", "sous", select(2, ns.prixConseille(500, nil, true)))
verifie("conseil unique : 1 argent de moins, arrondi", 12200, (ns.prixConseille(12345, nil, false)))
verifie("conseil unique : plus bas rond", 9900, (ns.prixConseille(10000, nil, false)))
verifie("conseil : jamais sous le marchand (lot)", 600, (ns.prixConseille(500, 600, true)))
verifie("conseil : plancher marchand (lot, valeur)", 500, (ns.prixConseille(501, 500, true)))
verifie("conseil : plancher marchand (raison)", "plancher", select(2, ns.prixConseille(300, 500, true)))
verifie("conseil : plancher marchand (unique)", 800, (ns.prixConseille(850, 800, false)))
verifie("conseil : marchand égal au calcul, pas de plancher", "sous", select(2, ns.prixConseille(501, 500, true)))
verifie("conseil : plus bas minuscule, au moins 1 cuivre", 1, (ns.prixConseille(1, nil, true)))
verifie("conseil : unique bon marché, au moins 1 cuivre", 1, (ns.prixConseille(50, nil, false)))
verifie("conseil : pas de prix connu (nil)", nil, (ns.prixConseille(nil, 100, true)))
verifie("conseil : pas de prix connu (raison)", "inconnu", select(2, ns.prixConseille(nil, 100, true)))
verifie("conseil : prix zéro = inconnu", "inconnu", select(2, ns.prixConseille(0, nil, false)))
verifie("conseil : marchand invalide ignoré", 499, (ns.prixConseille(500, "x", true)))
local connu, avis = ns.texteConseil(500, 3 * 3600 + 100, 499, "sous", true, function(c) return c .. "c" end)
verifie("texte : prix connu", "Le plus bas connu : 500c l'unité (il y a 3 h)", connu)
verifie("texte : conseil", "Prix conseillé : 499c l'unité", avis)
connu, avis = ns.texteConseil(900, 60, 800, "plancher", false, function(c) return c .. "c" end)
verifie("texte : plancher marchand", "Prix conseillé : 800c (pas sous le prix du marchand)", avis)
connu, avis = ns.texteConseil(nil, nil, nil, "inconnu", true)
verifie("texte : pas de prix connu", "Pas de prix connu pour cet objet.", connu)
verifie("texte : pas de conseil", "Pas de prix conseillé : relève les prix de l'hôtel des ventes.", avis)

if ok then print("Tout est bon.") end
os.exit(ok and 0 or 1)
