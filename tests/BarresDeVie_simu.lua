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

-- Quêtes lues dans la bulle du monstre
local T = { titre = 17, objectif = 8 }
local objs = ns.objectifs({
  { type = 16, leftText = "Loup des bois" },
  { type = 17, leftText = "Des crocs pour le forgeron" },
  { type = 8, leftText = "Croc de loup : 2/6" },
  { type = 8, leftText = "Loups des bois tués : 8/8", completed = true },
  { type = 17, leftText = "La chasse" },
  { type = 8, leftText = "Loups des bois tués : 3/10" },
}, T)
verifie("deux objectifs pas finis", 2, #objs)
verifie("objet à ramasser : 2/6", "2/6", objs[1] and (objs[1].fait .. "/" .. objs[1].total))
verifie("objet à ramasser : genre objet", "objet", objs[1] and objs[1].genre)
verifie("objet à ramasser : son nom", "Croc de loup", objs[1] and objs[1].nom)
verifie("monstre à tuer : genre tuer", "tuer", objs[2] and objs[2].genre)
verifie("objectif fini par les chiffres : ignoré", 0, #ns.objectifs({ { type = 8, leftText = "Croc : 6/6" } }, T))
verifie("monstre sans quête : rien", 0, #ns.objectifs({ { type = 16, leftText = "Kobold" } }, T))

-- Butins appris : le jeu ne dit pas toujours qu'un monstre donne un objet de quête
verifie("numéro d'un monstre", 114, ns.npcDuGuid("Creature-0-4444-0-12-114-00001A2B3C"))
verifie("un joueur n'est pas un monstre", nil, ns.npcDuGuid("Player-93-0ABCDEF1"))
verifie("identifiant absent", nil, ns.npcDuGuid(nil))
verifie("clé d'objet, compte à la fin", "flasque d'huile", (ns.cleObjet("Flasque d'huile : 2/5")))
verifie("clé d'objet, compte au début", "flasque d'huile", (ns.cleObjet("2/5 Flasque d'huile")))
verifie("clé d'objet, nom seul (butin)", "flasque d'huile", (ns.cleObjet("Flasque d'huile")))
verifie("clé d'objet, vide", nil, (ns.cleObjet("")))
local journal = { ["flasque d'huile"] = { nom = "Flasque d'huile", fait = 2, total = 5 }, ["croc"] = { nom = "Croc", fait = 6, total = 6 } }
local manque = ns.butinManquant({ ["flasque d'huile"] = true }, journal)
verifie("monstre connu : il manque 2/5", "2/5", manque and (manque.fait .. "/" .. manque.total))
verifie("objet déjà complet : rien", nil, ns.butinManquant({ ["croc"] = true }, journal))
verifie("quête rendue (plus au journal) : rien", nil, ns.butinManquant({ ["plume"] = true }, journal))
verifie("monstre inconnu : rien", nil, ns.butinManquant(nil, journal))

if ok then print("Tout est bon.") end
os.exit(ok and 0 or 1)
