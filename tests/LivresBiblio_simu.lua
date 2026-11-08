-- Simulation hors jeu de Livres de bibliothèque : données, reconnaissance des
-- livres dans les sacs, états et compte.
-- Lancer depuis Windows :
--   wsl lua5.1 tests/LivresBiblio_simu.lua LivresBiblio/LivresBiblio.lua
local bidon
bidon = function()
  return setmetatable({}, { __index = function() return bidon() end, __call = function() return bidon() end })
end
function CreateFrame() return bidon() end
UIParent, SlashCmdList, UISpecialFrames, Minimap = {}, {}, {}, bidon()
tinsert = table.insert

local ns = {}
local dossier = arg[1]:gsub("[^/]+$", "")
assert(loadfile(dossier .. "Reglages.lua"))("LivresBiblio", ns)
assert(loadfile(dossier .. "Donnees.lua"))("LivresBiblio", ns)
assert(loadfile(arg[1]))("LivresBiblio", ns)

local ok = true
local function verifie(libelle, attendu, obtenu)
  local bon = attendu == obtenu
  ok = ok and bon
  io.write(string.format("%s %-55s attendu %s, obtenu %s\n", bon and "OK " or "KO ", libelle, tostring(attendu), tostring(obtenu)))
end

local function lire(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end
verifie("Reglages.lua identique dans QuetesAuto", true,
  lire(dossier .. "Reglages.lua") == lire((dossier:gsub("LivresBiblio/$", "QuetesAuto/")) .. "Reglages.lua"))

-- Données : 30 livres ordinaires + 8 « niveau 60 », chacun complet et unique.
local base, n60, vus, completes = 0, 0, {}, true
for _, l in ipairs(ns.LIVRES) do
  if l.niv60 then n60 = n60 + 1 else base = base + 1 end
  if vus[l.quete] then completes = false end
  vus[l.quete] = true
  if not (l.nom and l.en and l.aide and l.carte and l.x > 0 and l.x < 1 and l.y > 0 and l.y < 1) then completes = false end
end
verifie("données : 30 livres ordinaires", 30, base)
verifie("données : 8 livres niveau 60", 8, n60)
verifie("données : chaque livre complet, quête unique", true, completes)
verifie("Badaboum ! suivi par sa propre quête (84399)", true, vus[84399] == true)

-- Reconnaissance d'un objet.
local almanach = { nom = "Almanach de Nar’thalas", en = "Nar'thalas Almanac" }
verifie("objet plus long que le titre", true, ns.estCeLivre(ns.simplifier("Almanach de Nar'thalas, vol. 74"), almanach))
verifie("apostrophe droite ou typographique", true, ns.estCeLivre(ns.simplifier("Almanach de Nar’thalas"), almanach))
verifie("client anglais", true, ns.estCeLivre(ns.simplifier("Nar'thalas Almanac, Vol. 74"), almanach))
local badaboum = { nom = "Badaboum !", en = "Ka-Boom!" }
verifie("espaces et ponctuation ignorés", true, ns.estCeLivre(ns.simplifier("Badaboum!"), badaboum))
verifie("autre objet : non", false, ns.estCeLivre(ns.simplifier("Pierre de foyer"), almanach))
verifie("nom trop court : non", false, ns.estCeLivre(ns.simplifier("Alma"), almanach))
local theocritus = { nom = "Journal de recherche de l’archimage Théocritus", en = "Archmage Theocritus" }
verifie("« Le » devant et sans accent (vu en jeu)", true,
  ns.estCeLivre(ns.simplifier("Le journal de recherche de l'archimage Theocritus"), theocritus))
verifie("client anglais : nom complet de l'objet", true,
  ns.estCeLivre(ns.simplifier("Archmage Theocritus's Research Journal"), theocritus))
local function livre(quete) for _, l in ipairs(ns.LIVRES) do if l.quete == quete then return l end end end
verifie("Ataeric : l'objet « Secrets des arcanes »", true,
  ns.estCeLivre(ns.simplifier("Secrets des arcanes"), livre(79096)))
verifie("titre court : égalité exacte (Ka-Boom!)", true, ns.estCeLivre(ns.simplifier("Ka-Boom!"), livre(84399)))
verifie("titre court : pas dans un autre nom", false, ns.estCeLivre(ns.simplifier("Ka-Boom! Bombe"), livre(84399)))
-- Objets ordinaires du butin qui ressemblent à un titre : jamais pris pour un livre.
local ordinaires = { "Écaille de basilic", "Basilisk Scale", "Basilisk Skin", "Parchemin", "Momie",
  "Mummified Remains", "Secrets", "Grimoire", "Vieux livre", "Tome de la Lumière", "Scourgestone" }
local fauxPositifs = 0
for _, nom in ipairs(ordinaires) do
  for _, l in ipairs(ns.LIVRES) do
    if ns.estCeLivre(ns.simplifier(nom), l) then fauxPositifs = fauxPositifs + 1 end
  end
end
verifie("objets ordinaires : aucun pris pour un livre", 0, fauxPositifs)
-- Aucun livre ne doit en reconnaître un autre (titres trop proches).
local confusions = 0
for _, a in ipairs(ns.LIVRES) do
  for _, b in ipairs(ns.LIVRES) do
    if a ~= b and ns.estCeLivre(ns.simplifier(a.nom), b) then confusions = confusions + 1 end
  end
end
verifie("aucun livre confondu avec un autre", 0, confusions)

-- États.
local rendues = { [1] = true }
local function estRendue(q) return rendues[q] == true end
verifie("état : rendu", "rendu", ns.etat({ quete = 1 }, estRendue, { [1] = true }))
verifie("état : ramassé = à rendre", "aRendre", ns.etat({ quete = 2 }, estRendue, { [2] = true }))
verifie("état : à trouver", "aTrouver", ns.etat({ quete = 3 }, estRendue, {}))
local c = ns.compter({ { quete = 1 }, { quete = 2 }, { quete = 3 }, { quete = 4, niv60 = true } },
  estRendue, { [2] = true }, false)
verifie("compte sans niveau 60 : total", 3, c.total)
verifie("compte : à trouver", 1, c.aTrouver)

-- Zone ramenée sur le continent.
local cx, cy = ns.versContinent(0.5, 0.5, { 0.4, 0.6, 0.2, 0.4 })
verifie("continent : x", 0.5, math.floor(cx * 1000 + 0.5) / 1000)
verifie("continent : y", 0.3, math.floor(cy * 1000 + 0.5) / 1000)

verifie("pour Sacs rangés : le journal de Théocritus est un livre", true, LivresBiblio_EstUnLivre("Journal de recherche de l'archimage Théocritus"))
verifie("pour Sacs rangés : une potion n'est pas un livre", false, LivresBiblio_EstUnLivre("Potion de soins"))
os.exit(ok and 0 or 1)
