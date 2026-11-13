-- Simulation hors jeu de Confort : qui accepter.
-- Lancer depuis Windows :
--   wsl lua5.1 tests/Confort_simu.lua Confort/Confort.lua
local bidon
bidon = function()
  return setmetatable({}, { __index = function() return bidon() end, __call = function() return bidon() end })
end
function CreateFrame() return bidon() end
UIParent, SlashCmdList, UISpecialFrames, Minimap = {}, {}, {}, bidon()
tinsert = table.insert

local ns = {}
local reglagesLua = arg[1]:gsub("[^/]+$", "Reglages.lua")
assert(loadfile(reglagesLua))("Confort", ns)
assert(loadfile(arg[1]))("Confort", ns)

local ok = true
local function verifie(libelle, attendu, obtenu)
  local bon = attendu == obtenu
  ok = ok and bon
  io.write(string.format("%s %-55s attendu %s, obtenu %s\n", bon and "OK " or "KO ", libelle, tostring(attendu), tostring(obtenu)))
end
local function lire(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end
verifie("Reglages.lua identique dans QuetesAuto", true,
  lire(reglagesLua) == lire((reglagesLua:gsub("Confort/Reglages", "QuetesAuto/Reglages"))))

local groupe = { "Jack", "Emberiel-Sacreforge" }
verifie("ton frère dans le groupe : accepté", true, ns.accepterDuGroupe("Jack", groupe, false))
verifie("même joueur avec son royaume", true, ns.accepterDuGroupe("Jack-Sacreforge", groupe, false))
verifie("même joueur sans son royaume", true, ns.accepterDuGroupe("Emberiel", groupe, false))
verifie("un inconnu : refusé", false, ns.accepterDuGroupe("Gorlak", groupe, false))
verifie("en combat : jamais", false, ns.accepterDuGroupe("Jack", groupe, true))
verifie("personne : refusé", false, ns.accepterDuGroupe(nil, groupe, false))
verifie("scintillement : préréglage graphique surveillé", true, ns.reglageSurveille("graphicsQuality"))
verifie("scintillement : son propre réglage surveillé", true, ns.reglageSurveille("outlineModeShowLootEffectWhenDisabled"))
verifie("scintillement : un autre réglage ne compte pas", false, ns.reglageSurveille("Sound_MasterVolume"))
verifie("scintillement : pas un texte", false, ns.reglageSurveille(nil))

if ok then print("Tout est bon.") end
os.exit(ok and 0 or 1)
