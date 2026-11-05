-- Simulation hors jeu de Marchand auto : quoi vendre, qui paie la réparation.
-- Lancer depuis Windows :
--   wsl lua5.1 tests/MarchandAuto_simu.lua MarchandAuto/MarchandAuto.lua
local bidon
bidon = function()
  return setmetatable({}, { __index = function() return bidon() end, __call = function() return bidon() end })
end
function CreateFrame() return bidon() end
UIParent, SlashCmdList, UISpecialFrames, Minimap = {}, {}, {}, bidon()
tinsert = table.insert

local ns = {}
local reglagesLua = arg[1]:gsub("[^/]+$", "Reglages.lua")
assert(loadfile(reglagesLua))("MarchandAuto", ns)
assert(loadfile(arg[1]))("MarchandAuto", ns)

local ok = true
local function verifie(libelle, attendu, obtenu)
  local bon = attendu == obtenu
  ok = ok and bon
  io.write(string.format("%s %-50s attendu %s, obtenu %s\n", bon and "OK " or "KO ", libelle, tostring(attendu), tostring(obtenu)))
end

-- Reglages.lua doit être la même copie dans chaque addon.
local function lire(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end
verifie("Reglages.lua identique dans QuetesAuto", true,
  lire(reglagesLua) == lire((reglagesLua:gsub("MarchandAuto/Reglages", "QuetesAuto/Reglages"))))

verifie("gris : vendu", true, ns.aVendre({ quality = 0, itemID = 1 }, {}))
verifie("blanc : gardé", false, ns.aVendre({ quality = 1, itemID = 1 }, {}))
verifie("gris sans valeur : gardé", false, ns.aVendre({ quality = 0, hasNoValue = true }, {}))
verifie("gris de la liste à garder : gardé", false, ns.aVendre({ quality = 0, itemID = 7 }, { [7] = true }))
verifie("case vide : rien", false, ns.aVendre(nil, {}))

verifie("guilde sans limite : la guilde paie", "guilde", ns.payeur(500, 0, -1, true))
verifie("guilde pas assez : toi", "perso", ns.payeur(500, 1000, 100, true))
verifie("option guilde coupée : toi", "perso", ns.payeur(500, 1000, -1, false))
verifie("pas assez d'or nulle part : rien", nil, ns.payeur(500, 100, nil, true))
verifie("rien à réparer : rien", nil, ns.payeur(0, 1000, -1, true))
os.exit(ok and 0 or 1)
