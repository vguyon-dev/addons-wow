-- Simulation hors jeu d'Entre frères : messages échangés et comparaison des quêtes.
-- Lancer depuis Windows :
--   wsl lua5.1 tests/EntreFreres_simu.lua EntreFreres/EntreFreres.lua
local bidon
bidon = function()
  return setmetatable({}, { __index = function() return bidon() end, __call = function() return bidon() end })
end
function CreateFrame() return bidon() end
UIParent, SlashCmdList, UISpecialFrames, Minimap = {}, {}, {}, bidon()
C_ChatInfo = { RegisterAddonMessagePrefix = function() end }
tinsert = table.insert

local ns = {}
local reglagesLua = arg[1]:gsub("[^/]+$", "Reglages.lua")
assert(loadfile(reglagesLua))("EntreFreres", ns)
assert(loadfile(arg[1]))("EntreFreres", ns)

local ok = true
local function verifie(libelle, attendu, obtenu)
  local bon = attendu == obtenu
  ok = ok and bon
  io.write(string.format("%s %-50s attendu %s, obtenu %s\n", bon and "OK " or "KO ", libelle, tostring(attendu), tostring(obtenu)))
end

local function lire(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end
verifie("Reglages.lua identique dans QuetesAuto", true,
  lire(reglagesLua) == lire((reglagesLua:gsub("EntreFreres/Reglages", "QuetesAuto/Reglages"))))

-- Progression.
verifie("progression : deux objectifs", "3/8,1/1",
  ns.progression({ { numFulfilled = 3, numRequired = 8 }, { numFulfilled = 1, numRequired = 1 } }, false))
verifie("progression : quête finie", "fini", ns.progression({}, true))

-- Aller-retour d'un message.
local m = ns.lireMessage(ns.messageQuete({ id = 123, titre = "Les loups~affamés", prog = "2/6" }))
verifie("message quête : type", "Q", m.type)
verifie("message quête : id", 123, m.id)
verifie("message quête : ~ remplacé dans le titre", "Les loups-affamés", m.titre)
verifie("message quête : progression", "2/6", m.prog)
local p = ns.lireMessage(ns.messageProfil(12, "Forêt d'Elwynn", 7))
verifie("message profil : niveau", 12, p.niveau)
verifie("message profil : zone", "Forêt d'Elwynn", p.zone)
verifie("message « ? »", "?", ns.lireMessage("?").type)
verifie("message inconnu ignoré", nil, ns.lireMessage("n'importe quoi"))
local long = ns.messageQuete({ id = 1, titre = string.rep("é", 200), prog = "" })
verifie("message trop long coupé (< 255 octets)", true, #long < 255)
verifie("coupé sans lettre à moitié", true, ns.lireMessage(long).titre:match("[\195]$") == nil)

-- Comparaison.
local commun, lui, moi = ns.comparer(
  { [1] = { titre = "A", prog = "1/5" }, [2] = { titre = "B", prog = "" } },
  { [1] = { titre = "A", prog = "4/5" }, [3] = { titre = "C", prog = "0/2" } })
verifie("en commun : une quête", 1, #commun)
verifie("en commun : sa progression", "4/5", commun[1].lui)
verifie("en commun : la mienne", "1/5", commun[1].moi)
verifie("lui seulement : C", "C", lui[1] and lui[1].titre)
verifie("moi seulement : B", "B", moi[1] and moi[1].titre)

print(ok and "Tout est bon." or "IL Y A DES ERREURS.")
