-- Simulation hors jeu de Montures : le choix selon l'endroit.
-- Lancer depuis Windows :
--   wsl lua5.1 tests/Montures_simu.lua Montures/Montures.lua
local bidon
bidon = function()
  return setmetatable({}, { __index = function() return bidon() end, __call = function() return bidon() end })
end
function CreateFrame() return bidon() end
UIParent, SlashCmdList, UISpecialFrames, Minimap = {}, {}, {}, bidon()
tinsert = table.insert

local ns = {}
local reglagesLua = arg[1]:gsub("[^/]+$", "Reglages.lua")
assert(loadfile(reglagesLua))("Montures", ns)
assert(loadfile(arg[1]))("Montures", ns)

local ok = true
local function verifie(libelle, attendu, obtenu)
  local bon = attendu == obtenu
  ok = ok and bon
  io.write(string.format("%s %-55s attendu %s, obtenu %s\n", bon and "OK " or "KO ", libelle, tostring(attendu), tostring(obtenu)))
end
local function lire(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end
verifie("Reglages.lua identique dans QuetesAuto", true,
  lire(reglagesLua) == lire((reglagesLua:gsub("Montures/Reglages", "QuetesAuto/Reglages"))))

local premier = function() return 1 end
local cheval = { nom = "Cheval bai", utilisable = true, favorite = true, type = 230, sort = 1 }
local drake = { nom = "Proto-drake", utilisable = true, favorite = true, type = 248, sort = 2 }
local tortue = { nom = "Tortue de mer", utilisable = true, favorite = false, type = 231, sort = 3 }
local mammouth = { nom = "Mammouth", utilisable = true, favorite = true, type = 230, sort = 61425 }
local toutes = { cheval, drake, tortue, mammouth }
local opt = { favorites = true, hasard = false, aquatique = true, deuxPlaces = false }

verifie("au sol : terrestre", "Cheval bai", (ns.choisir(toutes, {}, opt, premier) or {}).nom)
verifie("là où on vole : volante", "Proto-drake", (ns.choisir(toutes, { vol = true }, opt, premier) or {}).nom)
verifie("dans l'eau : la tortue même pas favorite ? non, favorites d'abord", "Cheval bai",
  (ns.choisir(toutes, { eau = true }, opt, premier) or {}).nom)
verifie("dans l'eau, toutes les montures : la tortue", "Tortue de mer",
  (ns.choisir(toutes, { eau = true }, { favorites = false, aquatique = true }, premier) or {}).nom)
verifie("en groupe, deux places : le mammouth", "Mammouth",
  (ns.choisir(toutes, { groupe = true }, { favorites = true, deuxPlaces = true }, premier) or {}).nom)
verifie("aucune favorite utilisable : n'importe laquelle", "Tortue de mer",
  (ns.choisir({ { nom = "Cheval", utilisable = false, favorite = true, type = 230 }, tortue }, {}, opt, premier) or {}).nom)
verifie("rien d'utilisable : nil", nil, ns.choisir({ { utilisable = false } }, {}, opt, premier))
verifie("genre : dragonvol = volante", "volante", ns.genre(402))
verifie("genre : 231 = aquatique", "aquatique", ns.genre(231))

if ok then print("Tout est bon.") end
os.exit(ok and 0 or 1)
