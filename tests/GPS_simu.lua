-- Simulation hors jeu du GPS : lecture de /way, choix de la balise, flèche.
-- Lancer depuis Windows :
--   wsl lua5.1 tests/GPS_simu.lua GPS/GPS.lua
local bidon
bidon = function()
  return setmetatable({}, { __index = function() return bidon() end, __call = function() return bidon() end })
end
function CreateFrame() return bidon() end
UIParent, SlashCmdList, UISpecialFrames, Minimap = {}, {}, {}, bidon()
tinsert = table.insert

local ns = {}
local reglagesLua = arg[1]:gsub("[^/]+$", "Reglages.lua")
assert(loadfile(reglagesLua))("GPS", ns)
assert(loadfile(arg[1]))("GPS", ns)

local ok = true
local function verifie(libelle, attendu, obtenu)
  local bon = attendu == obtenu
  ok = ok and bon
  io.write(string.format("%s %-55s attendu %s, obtenu %s\n", bon and "OK " or "KO ", libelle, tostring(attendu), tostring(obtenu)))
end
local function proche(a, b) return a and math.abs(a - b) < 1e-6 end

local function lire(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end
verifie("Reglages.lua identique dans QuetesAuto", true,
  lire(reglagesLua) == lire((reglagesLua:gsub("GPS/Reglages", "QuetesAuto/Reglages"))))

local cartes = { { id = 37, nom = "Forêt d'Elwynn" }, { id = 84, nom = "Hurlevent" }, { id = 52, nom = "Marche de l'Ouest" } }
local r = ns.lireWay("45.2 67.8 Le moulin", 37, cartes)
verifie("way simple : carte d'ici", 37, r and r.carte)
verifie("way simple : x", true, proche(r and r.x, 0.452))
verifie("way simple : titre", "Le moulin", r and r.titre)
r = ns.lireWay("45,2 67,8", 37, cartes)
verifie("virgule décimale", true, proche(r and r.y, 0.678))
r = ns.lireWay("45.2, 67.8", 37, cartes)
verifie("nombres séparés par une virgule", true, proche(r and r.x, 0.452))
r = ns.lireWay("marche de l'ouest 56 47 Ferme", nil, cartes)
verifie("zone par son nom, sans accents ni apostrophe", 52, r and r.carte)
r = ns.lireWay("foret 10 20", 84, cartes)
verifie("zone par le début du nom", 37, r and r.carte)
local rien, erreur = ns.lireWay("Atlantide 10 20", 37, cartes)
verifie("zone inconnue refusée", "zone inconnue : Atlantide", erreur)
rien, erreur = ns.lireWay("bonjour", 37, cartes)
verifie("sans nombres : un message", true, rien == nil and erreur ~= nil)
rien = ns.lireWay("150 20", 37, cartes)
verifie("au-delà de 100 refusé", nil, rien)

verifie("distance", 5, ns.distance(0, 0, 3, 4))
-- Le monde : x vers le nord, y vers l'ouest. Face au nord (0), une balise au nord : tout droit.
verifie("balise devant : angle 0", true, proche(ns.angle(0, 0, 10, 0, 0), 0))
verifie("balise à l'ouest, face au nord : à gauche (+90°)", true, proche(ns.angle(0, 0, 0, 10, 0), math.pi / 2))
verifie("balise à l'ouest, face à l'ouest : tout droit", true, proche(ns.angle(0, 0, 0, 10, math.pi / 2), 0))
verifie("temps : 1 min 40 s", "1 min 40 s", ns.tempsRestant(700, 7))
verifie("temps : immobile, rien", nil, ns.tempsRestant(700, 0))

local a = { titre = "A", monde = { continent = 0, x = 100, y = 0 } }
local b = { titre = "B", monde = { continent = 0, x = 20, y = 0 } }
local c = { titre = "C", monde = { continent = 1, x = 1, y = 0 } }
local moi = { continent = 0, x = 0, y = 0 }
verifie("la plus proche du même continent", "B", (ns.choisir({ a, b, c }, moi, true) or {}).titre)
verifie("sinon la dernière posée du même continent", "A", (ns.choisir({ b, a, c }, moi, false) or {}).titre)
verifie("autre continent ignoré", nil, ns.choisir({ c }, moi, true))

if ok then print("Tout est bon.") end
os.exit(ok and 0 or 1)
