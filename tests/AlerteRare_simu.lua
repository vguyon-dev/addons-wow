-- Simulation hors jeu d'Alerte rare : quoi annoncer, et une seule fois.
-- Lancer depuis Windows :
--   wsl lua5.1 tests/AlerteRare_simu.lua AlerteRare/AlerteRare.lua
local bidon
bidon = function()
  return setmetatable({}, { __index = function() return bidon() end, __call = function() return bidon() end })
end
function CreateFrame() return bidon() end
UIParent, SlashCmdList, UISpecialFrames, Minimap = {}, {}, {}, bidon()
tinsert = table.insert

local ns = {}
local reglagesLua = arg[1]:gsub("[^/]+$", "Reglages.lua")
assert(loadfile(reglagesLua))("AlerteRare", ns)
assert(loadfile(arg[1]))("AlerteRare", ns)

local ok = true
local function verifie(libelle, attendu, obtenu)
  local bon = attendu == obtenu
  ok = ok and bon
  io.write(string.format("%s %-50s attendu %s, obtenu %s\n", bon and "OK " or "KO ", libelle, tostring(attendu), tostring(obtenu)))
end

local function lire(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end
verifie("Reglages.lua identique dans QuetesAuto", true,
  lire(reglagesLua) == lire((reglagesLua:gsub("AlerteRare/Reglages", "QuetesAuto/Reglages"))))

verifie("vignette : rare", "rare", ns.typeVignette("VignetteKill"))
verifie("vignette : élite", "élite", ns.typeVignette("VignetteKillElite"))
verifie("vignette : coffre", "coffre", ns.typeVignette("VignetteLoot"))
verifie("vignette : autre image ignorée", nil, ns.typeVignette("VignetteEvent"))
verifie("barre de vie : rare élite = rare", "rare", ns.typeClassement("rareelite"))
verifie("barre de vie : normal ignoré", nil, ns.typeClassement("normal"))

local vus = {}
verifie("rare : annoncé", true, ns.doitPrevenir("A", "rare", { elites = false }, vus, 100))
verifie("rare : pas deux fois", false, ns.doitPrevenir("A", "rare", { elites = false }, vus, 200))
verifie("rare : de nouveau après 5 min", true, ns.doitPrevenir("A", "rare", { elites = false }, vus, 401))
verifie("élite : option coupée", false, ns.doitPrevenir("B", "élite", { elites = false }, vus, 100))
verifie("élite : option activée", true, ns.doitPrevenir("B", "élite", { elites = true }, vus, 100))
verifie("coffre : option activée", true, ns.doitPrevenir("C", "coffre", { coffres = true }, vus, 100))
verifie("coffre : option coupée", false, ns.doitPrevenir("D", "coffre", { coffres = false }, vus, 100))
verifie("rare : option coupée", false, ns.doitPrevenir("E", "rare", { rares = false }, vus, 100))
os.exit(ok and 0 or 1)
