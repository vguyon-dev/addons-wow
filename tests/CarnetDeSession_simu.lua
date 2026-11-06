-- Simulation hors jeu du Carnet : fausse API WoW, puis scénarios de passage de niveau.
-- Lancer depuis Windows :
--   wsl lua5.1 tests/CarnetDeSession_simu.lua CarnetDeSession/CarnetDeSession.lua
local function bidon()
  return setmetatable({}, { __index = function() return function() return bidon() end end })
end
local ecouteur
function CreateFrame()
  local f = bidon()
  local scripts = {}
  rawset(f, "SetScript", function(self, nom, fn) scripts[nom] = fn end)
  rawset(f, "IsShown", function() return false end)
  rawset(f, "RegisterEvent", function() end)
  rawset(f, "_scripts", scripts)
  ecouteur = f
  return f
end
UIParent = {}
time, date = os.time, os.date
C_Timer = { NewTicker = function() end }
SlashCmdList = {}
function strtrim(s) return s end
local etat = { niveau = 1, xp = 0, xpMax = 250, argent = 0, uniteNiveau = 1 }
function UnitLevel() return etat.uniteNiveau end
function UnitXP() return etat.xp end
function UnitXPMax() return etat.xpMax end
function GetMoney() return etat.argent end
function print() end

local chunk = assert(loadfile(arg[1]))
chunk("CarnetDeSession", {})
local function evt(nom, ...) ecouteur._scripts.OnEvent(ecouteur, nom, ...) end

evt("ADDON_LOADED", "CarnetDeSession")
evt("PLAYER_ENTERING_WORLD", true, false)
local s = CarnetDeSessionPerso
local ok = true
local function verifie(libelle, attendu, obtenu)
  local bon = attendu == obtenu
  ok = ok and bon
  io.write(string.format("%s %-55s attendu %s, obtenu %s\n", bon and "OK " or "KO ", libelle, tostring(attendu), tostring(obtenu)))
end

-- 1. gain simple
etat.xp = 100; evt("PLAYER_XP_UPDATE", "player")
verifie("gain simple +100", 100, s.xpGagnee)
-- 2. niveau pris, UnitLevel en retard, PLAYER_LEVEL_UP après l'XP (240/250 + 50 -> niv 2, 40/400)
etat.xp = 240; evt("PLAYER_XP_UPDATE", "player")
etat.xp, etat.xpMax = 40, 400; evt("PLAYER_XP_UPDATE", "player")
verifie("niveau pris, UnitLevel en retard", 290, s.xpGagnee)
evt("PLAYER_LEVEL_UP", 2)
etat.uniteNiveau = 2
-- 3. gain normal au niveau 2
etat.xp = 140; evt("PLAYER_XP_UPDATE", "player")
verifie("gain normal au niveau 2", 390, s.xpGagnee)
-- 4. grosse quête : 140/400 + 500 -> niv 3 à 240/600, PLAYER_LEVEL_UP d'abord, UnitLevel en retard
evt("PLAYER_LEVEL_UP", 3)
etat.xp, etat.xpMax = 240, 600; evt("PLAYER_XP_UPDATE", "player")
verifie("niveau pris, barre finale plus haute", 890, s.xpGagnee)
etat.uniteNiveau = 3
-- 5. déconnexion avec UnitLevel périmé
etat.uniteNiveau = 1
evt("PLAYER_LOGOUT")
verifie("niveau de fin malgré UnitLevel périmé", 3, s.niveauFin)
os.exit(ok and 0 or 1)
