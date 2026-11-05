-- Simulation hors jeu de Butin rapide : quoi ramasser, quel gris jeter, gain par heure.
-- Lancer depuis Windows :
--   wsl lua5.1 tests/ButinRapide_simu.lua ButinRapide/ButinRapide.lua
local bidon
bidon = function()
  return setmetatable({}, { __index = function() return bidon() end, __call = function() return bidon() end })
end
function CreateFrame() return bidon() end
UIParent, SlashCmdList, UISpecialFrames, Minimap, C_Timer = {}, {}, {}, bidon(), bidon()
tinsert = table.insert

local ns = {}
local reglagesLua = arg[1]:gsub("[^/]+$", "Reglages.lua")
assert(loadfile(reglagesLua))("ButinRapide", ns)
assert(loadfile(arg[1]))("ButinRapide", ns)

local ok = true
local function verifie(libelle, attendu, obtenu)
  local bon = attendu == obtenu
  ok = ok and bon
  io.write(string.format("%s %-50s attendu %s, obtenu %s\n", bon and "OK " or "KO ", libelle, tostring(attendu), tostring(obtenu)))
end
local function lire(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end
verifie("Reglages.lua identique dans QuetesAuto", true,
  lire(reglagesLua) == lire((reglagesLua:gsub("ButinRapide/Reglages", "QuetesAuto/Reglages"))))

local r = { ignorerGris = false }
verifie("objet normal : pris", "prendre", ns.decision({ qualite = 1, idObjet = 5 }, r, {}))
verifie("argent : toujours pris", "prendre", ns.decision({ argent = true }, { ignorerGris = true }, {}))
verifie("gris, filtre coupé : pris", "prendre", ns.decision({ qualite = 0 }, r, {}))
verifie("gris, filtre mis : laissé", "laisser", ns.decision({ qualite = 0 }, { ignorerGris = true }, {}))
verifie("objet de quête gris : pris quand même", "prendre", ns.decision({ qualite = 0, quete = true }, { ignorerGris = true }, {}))
verifie("objet de la liste : laissé", "laisser", ns.decision({ qualite = 2, idObjet = 9 }, r, { [9] = true }))
verifie("violet en groupe (seuil vert) : jet de dés", "attendre", ns.decision({ qualite = 4 }, r, {}, 2))
verifie("verrouillé : attendre", "attendre", ns.decision({ verrouille = true }, r, {}))

verifie("gris le moins cher", 2, ns.grisAJeter({ { valeur = 50 }, { valeur = 3 }, { valeur = 9 } }))
verifie("aucun gris : rien", nil, ns.grisAJeter({}))
verifie("par heure : 1000 en 30 min", 2000, ns.parHeure(1000, 1800))
verifie("par heure : moins d'une minute = 0", 0, ns.parHeure(1000, 30))
os.exit(ok and 0 or 1)
