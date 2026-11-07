-- Simulation hors jeu de Rapport d'erreurs : découpage, recollage, codage, rangement.
-- Lancer depuis Windows :
--   wsl lua5.1 tests/RapportErreurs_simu.lua RapportErreurs/RapportErreurs.lua
local bidon
bidon = function()
  return setmetatable({}, { __index = function() return bidon() end, __call = function() return bidon() end })
end
function CreateFrame() return bidon() end
UIParent, SlashCmdList, UISpecialFrames, Minimap = {}, {}, {}, bidon()
C_ChatInfo = { RegisterAddonMessagePrefix = function() end }
tinsert = table.insert

-- Un gestionnaire d'erreurs existant, pour vérifier qu'on le rappelle toujours.
local appelsAncien = 0
local gestionnaire = function() appelsAncien = appelsAncien + 1 end
function geterrorhandler() return gestionnaire end
function seterrorhandler(f) gestionnaire = f end

local ns = {}
local reglagesLua = arg[1]:gsub("[^/]+$", "Reglages.lua")
assert(loadfile(reglagesLua))("RapportErreurs", ns)
assert(loadfile(arg[1]))("RapportErreurs", ns)

local ok = true
local function verifie(libelle, attendu, obtenu)
  local bon = attendu == obtenu
  ok = ok and bon
  io.write(string.format("%s %-52s attendu %s, obtenu %s\n", bon and "OK " or "KO ", libelle, tostring(attendu), tostring(obtenu)))
end

local function lire(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end
verifie("Reglages.lua identique dans QuetesAuto", true,
  lire(reglagesLua) == lire((reglagesLua:gsub("RapportErreurs/Reglages", "QuetesAuto/Reglages"))))

-- Codage : tabulations, retours à la ligne et barres obliques survivent.
local champs = { "QuetesAuto", "0.5.5", "a\tb\nc\\nd", "" , "é è ç" }
local retour = ns.decoder(ns.encoder(champs))
local pareil = #retour == #champs
for i = 1, #champs do pareil = pareil and retour[i] == champs[i] end
verifie("codage puis décodage : champs identiques", true, pareil)
verifie("une ligne codée n'a pas de retour à la ligne", nil, ns.encoder(champs):find("\n"))

-- Découpage : aucune lettre accentuée coupée, rien de perdu.
local long = string.rep("Pile d'appels : éàç ", 60)
local morceaux = ns.decouper(long, 50)
local tailleOk, coupeOk = true, true
for _, m in ipairs(morceaux) do
  if #m > 50 then tailleOk = false end
  local b = m:byte(1)
  if b and b >= 0x80 and b < 0xC0 then coupeOk = false end
end
verifie("découpage : morceaux de 50 octets au plus", true, tailleOk)
verifie("découpage : jamais une lettre coupée", true, coupeOk)
verifie("découpage : rien de perdu", true, long == table.concat(morceaux))
verifie("découpage d'un texte vide : un morceau", 1, #ns.decouper("", 50))

-- Recollage : morceaux arrivés dans le désordre, et deux envois mêlés.
local recoller = ns.nouveauRecolleur()
verifie("recollage : incomplet", nil, recoller("Paul", "E1", 2, 3, "B"))
verifie("recollage : autre envoi intercalé", nil, recoller("Paul", "E2", 1, 2, "x"))
verifie("recollage : toujours incomplet", nil, recoller("Paul", "E1", 1, 3, "A"))
verifie("recollage : complet, dans l'ordre", "ABC", recoller("Paul", "E1", 3, 3, "C"))
verifie("recollage : le second envoi aussi", "xy", recoller("Paul", "E2", 2, 2, "y"))

-- Addon en cause.
verifie("addon : depuis le message", "QuetesAuto",
  ns.addonDe("Interface/AddOns/QuetesAuto/QuetesAuto.lua:12: attempt to index nil", ""))
verifie("addon : depuis la pile", "SacsRanges",
  ns.addonDe("bad argument #1", "[Interface/AddOns/SacsRanges/SacsRanges.lua]:40: in function"))
verifie("addon : inconnu", nil, ns.addonDe("bad argument", "[C]: in function"))

-- Rangement : même message = une seule entrée, comptée.
local liste = {}
ns.ranger(liste, { message = "A" }, 3)
local _, nouvelle = ns.ranger(liste, { message = "A" }, 3)
verifie("même erreur : pas de doublon", 1, #liste)
verifie("même erreur : comptée deux fois", 2, liste[1].nombre)
verifie("même erreur : pas nouvelle", false, nouvelle)
ns.ranger(liste, { message = "B" }, 3); ns.ranger(liste, { message = "C" }, 3); ns.ranger(liste, { message = "D" }, 3)
verifie("liste limitée à 3", 3, #liste)
verifie("la plus récente en tête", "D", liste[1].message)

-- Le gestionnaire d'erreurs d'avant est toujours appelé.
gestionnaire("une erreur")
verifie("gestionnaire précédent rappelé", 1, appelsAncien)

os.exit(ok and 0 or 1)
