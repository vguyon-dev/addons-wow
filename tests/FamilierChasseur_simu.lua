-- Simulation hors jeu de Familier du chasseur : l'état à signaler, la nourriture.
-- Lancer depuis Windows :
--   wsl lua5.1 tests/FamilierChasseur_simu.lua FamilierChasseur/FamilierChasseur.lua
local bidon
bidon = function()
  return setmetatable({}, { __index = function() return bidon() end, __call = function() return bidon() end })
end
function CreateFrame() return bidon() end
UIParent, SlashCmdList, UISpecialFrames, Minimap = {}, {}, {}, bidon()
tinsert = table.insert

local ns = {}
local reglagesLua = arg[1]:gsub("[^/]+$", "Reglages.lua")
assert(loadfile(reglagesLua))("FamilierChasseur", ns)
assert(loadfile(arg[1]))("FamilierChasseur", ns)

local ok = true
local function verifie(libelle, attendu, obtenu)
  local bon = attendu == obtenu
  ok = ok and bon
  io.write(string.format("%s %-55s attendu %s, obtenu %s\n", bon and "OK " or "KO ", libelle, tostring(attendu), tostring(obtenu)))
end
local function lire(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end
verifie("Reglages.lua identique dans QuetesAuto", true,
  lire(reglagesLua) == lire((reglagesLua:gsub("FamilierChasseur/Reglages", "QuetesAuto/Reglages"))))

local tout = { faim = true, mort = true, oubli = true }
verifie("content : rien", nil, ns.etat({ existe = true, humeur = 3 }, tout))
verifie("mécontent : faim", "faim", ns.etat({ existe = true, humeur = 2 }, tout))
verifie("humeur inconnue (jeu moderne) : rien", nil, ns.etat({ existe = true }, tout))
verifie("mort", "mort", ns.etat({ existe = true, mort = true }, tout))
verifie("pas appelé, dehors : absent", "absent", ns.etat({ existe = false }, tout))
verifie("pas appelé, en ville : rien", nil, ns.etat({ existe = false, auRepos = true }, tout))
verifie("faim décochée : rien", nil, ns.etat({ existe = true, humeur = 1 }, { faim = false, mort = true, oubli = true }))

local sac = {
  { id = 1, nourriture = true, prix = 50 },   -- côtelette
  { id = 2, nourriture = true, prix = 10 },   -- pain, le moins cher
  { id = 3, nourriture = false, prix = 1 },   -- pas de la nourriture
  { id = 4, nourriture = true, prix = 30 },   -- viande de loup
}
verifie("sans préférence : la moins chère", 2, (ns.choisirNourriture(sac, {}) or {}).id)
verifie("avec préférences : la moins chère des préférées", 4, (ns.choisirNourriture(sac, { [1] = "Côtelette", [4] = "Viande" }) or {}).id)
verifie("préférée absente du sac : n'importe quelle nourriture", 2, (ns.choisirNourriture(sac, { [9] = "Poisson" }) or {}).id)
verifie("aucune nourriture : rien", nil, ns.choisirNourriture({ { id = 3, prix = 1 } }, {}))

if ok then print("Tout est bon.") end
os.exit(ok and 0 or 1)
