-- Simulation hors jeu de Barres de vie : couleur selon la menace, étoiles.
-- Lancer depuis Windows :
--   wsl lua5.1 tests/BarresDeVie_simu.lua BarresDeVie/BarresDeVie.lua
local bidon
bidon = function()
  return setmetatable({}, { __index = function() return bidon() end, __call = function() return bidon() end })
end
function CreateFrame() return bidon() end
UIParent, SlashCmdList, UISpecialFrames, Minimap = {}, {}, {}, bidon()
tinsert = table.insert

local ns = {}
local reglagesLua = arg[1]:gsub("[^/]+$", "Reglages.lua")
assert(loadfile(reglagesLua))("BarresDeVie", ns)
assert(loadfile(arg[1]))("BarresDeVie", ns)

local ok = true
local function verifie(libelle, attendu, obtenu)
  local bon = attendu == obtenu
  ok = ok and bon
  io.write(string.format("%s %-55s attendu %s, obtenu %s\n", bon and "OK " or "KO ", libelle, tostring(attendu), tostring(obtenu)))
end
local function nom(c)
  if not c then return "jeu" end
  if c[1] > 0.9 and c[2] < 0.3 then return "rouge" end
  if c[1] > 0.9 then return "orange" end
  return "vert"
end

local function lire(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end
verifie("Reglages.lua identique dans QuetesAuto", true,
  lire(reglagesLua) == lire((reglagesLua:gsub("BarresDeVie/Reglages", "QuetesAuto/Reglages"))))

verifie("pas en combat avec lui : couleur du jeu", "jeu", nom(ns.couleurMenace(nil, false)))
verifie("DPS, pas visé : vert", "vert", nom(ns.couleurMenace(0, false)))
verifie("DPS, bientôt visé : orange", "orange", nom(ns.couleurMenace(1, false)))
verifie("DPS, il te tape : rouge", "rouge", nom(ns.couleurMenace(3, false)))
verifie("tank, il te tape : vert", "vert", nom(ns.couleurMenace(3, true)))
verifie("tank, il t'échappe : rouge", "rouge", nom(ns.couleurMenace(0, true)))
verifie("tank, fragile : orange", "orange", nom(ns.couleurMenace(2, true)))
verifie("rare", "rare", ns.etoile("rare"))
verifie("rare élite : rare", "rare", ns.etoile("rareelite"))
verifie("élite", "elite", ns.etoile("elite"))
verifie("normal : rien", nil, ns.etoile("normal"))

if ok then print("Tout est bon.") end
os.exit(ok and 0 or 1)
