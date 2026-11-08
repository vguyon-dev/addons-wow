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

if ok then print("Tout est bon.") end
os.exit(ok and 0 or 1)
