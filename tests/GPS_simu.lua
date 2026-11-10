-- Simulation hors jeu du GPS : lecture de /way, choix de la balise, flèche.
-- Lancer depuis Windows :
--   wsl lua5.1 tests/GPS_simu.lua GPS/GPS.lua
local bidon
bidon = function()
  return setmetatable({}, { __index = function() return bidon() end, __call = function() return bidon() end })
end
function CreateFrame() return bidon() end
UIParent, SlashCmdList, UISpecialFrames, Minimap = {}, {}, {}, bidon()
tinsert = table.insert

local ns = {}
local reglagesLua = arg[1]:gsub("[^/]+$", "Reglages.lua")
assert(loadfile(reglagesLua))("GPS", ns)
assert(loadfile(arg[1]))("GPS", ns)

local ok = true
local function verifie(libelle, attendu, obtenu)
  local bon = attendu == obtenu
  ok = ok and bon
  io.write(string.format("%s %-55s attendu %s, obtenu %s\n", bon and "OK " or "KO ", libelle, tostring(attendu), tostring(obtenu)))
end
local function proche(a, b) return a and math.abs(a - b) < 1e-6 end

local function lire(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end
verifie("Reglages.lua identique dans QuetesAuto", true,
  lire(reglagesLua) == lire((reglagesLua:gsub("GPS/Reglages", "QuetesAuto/Reglages"))))

local cartes = { { id = 37, nom = "Forêt d'Elwynn" }, { id = 84, nom = "Hurlevent" }, { id = 52, nom = "Marche de l'Ouest" } }
local r = ns.lireWay("45.2 67.8 Le moulin", 37, cartes)
verifie("way simple : carte d'ici", 37, r and r.carte)
verifie("way simple : x", true, proche(r and r.x, 0.452))
verifie("way simple : titre", "Le moulin", r and r.titre)
r = ns.lireWay("45,2 67,8", 37, cartes)
verifie("virgule décimale", true, proche(r and r.y, 0.678))
r = ns.lireWay("45.2, 67.8", 37, cartes)
verifie("nombres séparés par une virgule", true, proche(r and r.x, 0.452))
r = ns.lireWay("marche de l'ouest 56 47 Ferme", nil, cartes)
verifie("zone par son nom, sans accents ni apostrophe", 52, r and r.carte)
r = ns.lireWay("foret 10 20", 84, cartes)
verifie("zone par le début du nom", 37, r and r.carte)
local rien, erreur = ns.lireWay("Atlantide 10 20", 37, cartes)
verifie("zone inconnue refusée", "zone inconnue : Atlantide", erreur)
rien, erreur = ns.lireWay("bonjour", 37, cartes)
verifie("sans nombres : un message", true, rien == nil and erreur ~= nil)
rien = ns.lireWay("150 20", 37, cartes)
verifie("au-delà de 100 refusé", nil, rien)

verifie("distance", 5, ns.distance(0, 0, 3, 4))
-- Le monde : x vers le nord, y vers l'ouest. Face au nord (0), une balise au nord : tout droit.
verifie("balise devant : angle 0", true, proche(ns.angle(0, 0, 10, 0, 0), 0))
verifie("balise à l'ouest, face au nord : à gauche (+90°)", true, proche(ns.angle(0, 0, 0, 10, 0), math.pi / 2))
verifie("balise à l'ouest, face à l'ouest : tout droit", true, proche(ns.angle(0, 0, 0, 10, math.pi / 2), 0))
verifie("temps : 1 min 40 s", "1 min 40 s", ns.tempsRestant(700, 7))
verifie("temps : immobile, rien", nil, ns.tempsRestant(700, 0))

local a = { titre = "A", monde = { continent = 0, x = 100, y = 0 } }
local b = { titre = "B", monde = { continent = 0, x = 20, y = 0 } }
local c = { titre = "C", monde = { continent = 1, x = 1, y = 0 } }
local moi = { continent = 0, x = 0, y = 0 }
verifie("la plus proche du même continent", "B", (ns.choisir({ a, b, c }, moi, true) or {}).titre)
verifie("sinon la dernière posée du même continent", "A", (ns.choisir({ b, a, c }, moi, false) or {}).titre)
verifie("autre continent ignoré", nil, ns.choisir({ c }, moi, true))


-- Les balises partagées avec le groupe
local m = ns.coderBalise(37, 0.452, 0.678, "Le moulin")
verifie("code : message", "B\t37\t0.4520\t0.6780\tLe moulin", m)
r = ns.decoderBalise(m)
verifie("décode : carte", 37, r and r.carte)
verifie("décode : x", true, proche(r and r.x, 0.452))
verifie("décode : y", true, proche(r and r.y, 0.678))
verifie("décode : titre", "Le moulin", r and r.titre)
verifie("code : titre vide", "B\t37\t0.1000\t0.2000\t", ns.coderBalise(37, 0.1, 0.2, ""))
verifie("code : titre absent", "B\t37\t0.1000\t0.2000\t", ns.coderBalise(37, 0.1, 0.2, nil))
r = ns.decoderBalise("B\t37\t0.1000\t0.2000\t")
verifie("décode : titre vide = nil", true, r ~= nil and r.titre == nil)
r = ns.decoderBalise("B\t37\t0.1\t0.2")
verifie("décode : sans tabulation finale", 37, r and r.carte)
verifie("code : tabulation dans le titre", "B\t37\t0.1000\t0.2000\tun deux trois", ns.coderBalise(37, 0.1, 0.2, "un\tdeux\ntrois"))
r = ns.decoderBalise("B\t37\t0.1\t0.2\tpar\tmi\tles autres")
verifie("décode : tabulations dans le titre reçu", "par mi les autres", r and r.titre)
verifie("code : aucune barre « | » dans le message", nil, ns.coderBalise(37, 0.1, 0.2, "|cffff0000rouge|r"):find("|", 1, true))
verifie("décode : pas de | dans le titre", false, (ns.decoderBalise("B\t1\t0.1\t0.2\t|Hitem:1|h[x]|h").titre or ""):find("|", 1, true) ~= nil)
verifie("code : (de Nom) pas renvoyé", "B\t37\t0.1000\t0.2000\tLe moulin", ns.coderBalise(37, 0.1, 0.2, "Le moulin (de Anna)"))
local long = string.rep("é", 100)
local lm = ns.coderBalise(37, 0.1, 0.2, long)
verifie("code : titre coupé sans casser un accent", string.rep("é", 30), ns.decoderBalise(lm).titre)
verifie("code : message dans la limite du jeu", true, #lm <= 255)
verifie("code : x hors de 0 à 1 refusé", nil, ns.coderBalise(37, 1.5, 0.2, "a"))
verifie("code : y négatif refusé", nil, ns.coderBalise(37, 0.5, -0.1, "a"))
verifie("code : carte invalide refusée", nil, ns.coderBalise(0, 0.5, 0.5, "a"))
verifie("code : carte non entière refusée", nil, ns.coderBalise(37.5, 0.5, 0.5, "a"))
verifie("code : nombre non numérique refusé", nil, ns.coderBalise(37, "0.5", 0.5, "a"))
verifie("décode : nombre mal formé", nil, ns.decoderBalise("B\t37\tabc\t0.2\ta"))
verifie("décode : deux points dans un nombre", nil, ns.decoderBalise("B\t37\t0.1.2\t0.2\ta"))
verifie("décode : un point seul", nil, ns.decoderBalise("B\t37\t.\t0.2\ta"))
verifie("décode : notation scientifique refusée", nil, ns.decoderBalise("B\t37\t1e-3\t0.2\ta"))
verifie("décode : hors de 0 à 1", nil, ns.decoderBalise("B\t37\t45.2\t0.2\ta"))
verifie("décode : nombre négatif refusé", nil, ns.decoderBalise("B\t37\t-0.1\t0.2\ta"))
verifie("décode : carte à zéro", nil, ns.decoderBalise("B\t0\t0.1\t0.2\ta"))
verifie("décode : carte trop grande", nil, ns.decoderBalise("B\t123456789\t0.1\t0.2\ta"))
verifie("décode : mauvaise lettre", nil, ns.decoderBalise("Q\t37\t0.1\t0.2\ta"))
verifie("décode : champs manquants", nil, ns.decoderBalise("B\t37\t0.1"))
verifie("décode : texte vide", nil, ns.decoderBalise(""))
verifie("décode : pas du texte", nil, ns.decoderBalise(nil))
verifie("décode : trop long", nil, ns.decoderBalise("B\t37\t0.1\t0.2\t" .. string.rep("a", 300)))
verifie("titre reçu : avec le nom", "Le moulin (de Anna)", ns.titreRecu("Le moulin", "Anna"))
verifie("titre reçu : titre vide", "Balise (de Anna)", ns.titreRecu(nil, "Anna"))
verifie("titre reçu : aucune barre « | » du nom", nil, ns.titreRecu("", "|cffff0000Anna"):find("|", 1, true))
local base = { carte = 37, x = 0.452, y = 0.678 }
verifie("même balise : à 0,4 % près", true, ns.memeBalise(base, { carte = 37, x = 0.456, y = 0.674 }))
verifie("même balise : à 0,5 % pile", true, ns.memeBalise(base, { carte = 37, x = 0.457, y = 0.678 }))
verifie("autre balise : à 0,6 % de distance", false, ns.memeBalise(base, { carte = 37, x = 0.458, y = 0.678 }))
verifie("autre balise : autre carte", false, ns.memeBalise(base, { carte = 84, x = 0.452, y = 0.678 }))
verifie("doublon repéré dans la liste", true, ns.dejaConnue({ { carte = 1, x = 0, y = 0 }, base }, { carte = 37, x = 0.45, y = 0.68 }))
verifie("pas de doublon : liste vide", false, ns.dejaConnue({}, base))
verifie("pas de doublon : liste absente", false, ns.dejaConnue(nil, base))
verifie("canal : instance d'abord", "INSTANCE_CHAT", ns.canalGroupe(true, true, true))
verifie("canal : raid", "RAID", ns.canalGroupe(false, true, true))
verifie("canal : groupe", "PARTY", ns.canalGroupe(false, false, true))
verifie("canal : seul", nil, ns.canalGroupe(false, false, false))

verifie("catégorie d'instance : la constante du jeu", 3, ns.categorieInstance(3))
verifie("catégorie d'instance : sans constante, 2", 2, ns.categorieInstance(nil))
verifie("catégorie d'instance : constante abîmée, 2", 2, ns.categorieInstance("x"))
verifie("suivie : une balise reçue garde la suivie", "A", ns.suivieApresAjout("A", true))
verifie("suivie : rien de suivi, rien de suivi", nil, ns.suivieApresAjout(nil, true))
verifie("suivie : une balise posée à la main la lâche", nil, ns.suivieApresAjout("A", false))
verifie("suivie : sans précision, elle la lâche", nil, ns.suivieApresAjout("A", nil))
verifie("envoi : code 0 = parti", true, ns.envoiParti(true, 0))
verifie("envoi : rien rendu = parti", true, ns.envoiParti(true, nil))
verifie("envoi : vrai = parti", true, ns.envoiParti(true, true))
verifie("envoi : code d'erreur", false, ns.envoiParti(true, 3))
verifie("envoi : faux", false, ns.envoiParti(true, false))
verifie("envoi : erreur du jeu", false, ns.envoiParti(false, "boum"))
verifie("texte envoi : tout parti", "3 balise(s) envoyée(s) au groupe.", ns.texteEnvoi(3, 3))
verifie("texte envoi : une partie", "2 balise(s) sur 3 envoyée(s) au groupe.", ns.texteEnvoi(2, 3))
verifie("texte envoi : rien", "aucune balise n'a pu être envoyée au groupe.", ns.texteEnvoi(0, 3))

if ok then print("Tout est bon.") end
os.exit(ok and 0 or 1)
