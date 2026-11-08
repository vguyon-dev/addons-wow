-- Simulation hors jeu de Métiers auto : lecture des recettes, liste de courses, fenêtre de réglages.
-- Lancer depuis Windows :
--   wsl lua5.1 tests/MetiersAuto_simu.lua MetiersAuto/MetiersAuto.lua
local bidon
bidon = function()
  return setmetatable({}, { __index = function() return bidon() end, __call = function() return bidon() end })
end
-- Un cadre qui retient ses SetScript et son SetText : la simulation peut ainsi « cliquer » un bouton.
local scripts = {}
local function cadre()
  return setmetatable({}, { __index = function(_, k)
    if k == "SetScript" then
      return function(self, nom, f) scripts[#scripts + 1] = { self = self, nom = nom, f = f } end
    elseif k == "SetText" then
      return function(self, texte) rawset(self, "_texte", texte) end
    end
    return bidon()
  end })
end
function CreateFrame() return cadre() end
UIParent, SlashCmdList, UISpecialFrames, WorldFrame, C_Timer = bidon(), {}, {}, bidon(), bidon()
Minimap = cadre()
Minimap.GetWidth = function() return 140 end
tinsert = table.insert
-- Quelques fonctions du jeu appelées quand la fenêtre s'ouvre.
function InCombatLockdown() return false end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function SetCVar() end
function GetTime() return 0 end
function IsInInstance() return false end
C_Map = {
  GetBestMapForUnit = function() return 7 end,
  GetPlayerMapPosition = function() return { GetXY = function() return 0.5, 0.5 end } end,
}

local ns = {}
local reglagesLua = arg[1]:gsub("[^/]+$", "Reglages.lua")
assert(loadfile(reglagesLua))("MetiersAuto", ns)
assert(loadfile(arg[1]))("MetiersAuto", ns)

local ok = true
local function verifie(libelle, attendu, obtenu)
  local bon = attendu == obtenu
  ok = ok and bon
  io.write(string.format("%s %-50s attendu %s, obtenu %s\n", bon and "OK " or "KO ", libelle, tostring(attendu), tostring(obtenu)))
end

local function lire(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end
verifie("Reglages.lua identique dans QuetesAuto", true,
  lire(reglagesLua) == lire((reglagesLua:gsub("MetiersAuto/Reglages", "QuetesAuto/Reglages"))))

local lien = "|cffffd000|Henchant:2657|h[Fabriquer : Barre de cuivre]|h|r"
local n, id = ns.lireRecette("5 " .. lien)
verifie("« 5 [recette] » : nombre", 5, n)
verifie("« 5 [recette] » : numéro", 2657, id)
n, id = ns.lireRecette(lien)
verifie("« [recette] » seul : 1 fois", 1, n)
verifie("numéro tapé à la main", 2657, select(2, ns.lireRecette("2657")))

-- Deux recettes qui demandent toutes deux du minerai (qualités 1 et 2 = deux ids).
local recettes = {
  [1] = { { ids = { 10, 11 }, quantite = 2 }, { ids = { 20 }, quantite = 1 } },
  [2] = { { ids = { 10, 11 }, quantite = 3 } },
}
local b = ns.besoins({ { recette = 1, nombre = 5 }, { recette = 2, nombre = 2 } }, function(r) return recettes[r] end)
verifie("composants regroupés", 2, #b)
verifie("minerai : 5×2 + 2×3", 16, b[1].besoin)
local stock = { [10] = 4, [11] = 3, [20] = 9 }
local a, manque = ns.manque(b[1], function(i) return stock[i] end)
verifie("minerai possédé (deux qualités additionnées)", 7, a)
verifie("minerai manquant", 9, manque)
verifie("rien ne manque", 0, select(2, ns.manque(b[2], function(i) return stock[i] end)))

-- Filons mémorisés et flèche (carte de 1000 m sur 1000 m).
local liste = {}
verifie("filon : nouvel endroit", true, ns.memoriser(liste, 0.5, 0.5, "Cuivre", 1000, 1000))
verifie("filon : même endroit à 10 m près", false, ns.memoriser(liste, 0.505, 0.5, "Cuivre", 1000, 1000))
verifie("filon : deux endroits retenus", true, ns.memoriser(liste, 0.6, 0.5, "Étain", 1000, 1000))
verifie("distance : 100 m vers l'est", 100, math.floor(ns.distance(0.5, 0.5, 0.6, 0.5, 1000, 1000) + 0.5))
local p, d = ns.plusProche(liste, 0.5, 0.5, 1000, 1000, {}, 0)
verifie("plus proche : saute celui où je suis", "Étain", p and p[3])
local recent = { [liste[2]] = 100 }
verifie("plus proche : saute celui récolté il y a peu", nil, (ns.plusProche(liste, 0.5, 0.5, 1000, 1000, recent, 150)))
verifie("plus proche : revient après 3 minutes", "Étain", (ns.plusProche(liste, 0.5, 0.5, 1000, 1000, recent, 400) or {})[3])
local function arrondi(a) a = a % (2 * math.pi) return math.floor(a * 100 + 0.5) / 100 end
verifie("flèche : cible au nord, je regarde au nord", 0, arrondi(ns.angleFleche(0.5, 0.5, 0.5, 0.4, 1000, 1000, 0)))
verifie("flèche : cible à l'est, je regarde au nord", arrondi(-math.pi / 2), arrondi(ns.angleFleche(0.5, 0.5, 0.6, 0.5, 1000, 1000, 0)))
verifie("flèche : cible à l'est, je regarde à l'est", 0, arrondi(ns.angleFleche(0.5, 0.5, 0.6, 0.5, 1000, 1000, -math.pi / 2)))
verifie("flèche : cible derrière moi", arrondi(math.pi), arrondi(ns.angleFleche(0.5, 0.5, 0.5, 0.6, 1000, 1000, 0)))

-- Lignes de la liste de courses dans la fenêtre.
local retires = {}
local courses = { { recette = 1, nombre = 5, nom = "Barre de cuivre" }, { recette = 2 } }
local lignes = ns.lignesCourses(courses, function(i) retires[#retires + 1] = i end)
verifie("courses : deux lignes", 2, #lignes)
verifie("courses : « nombre × nom »", "5 × Barre de cuivre", lignes[1].texte)
verifie("courses : sans nom ni nombre, le numéro et 1 fois", "1 × 2", lignes[2].texte)
lignes[2].retirer()
verifie("courses : la croix retire la bonne ligne", 2, retires[1])
verifie("courses : liste vide, aucune ligne", 0, #ns.lignesCourses({}, function() end))

-- Texte des endroits connus.
verifie("filons : plusieurs ici", "3 endroits connus ici, 12 en tout", ns.texteFilons(3, 12))
verifie("filons : un seul ici", "1 endroit connu ici, 1 en tout", ns.texteFilons(1, 1))
verifie("filons : aucun ici", "0 endroit connu ici, 5 en tout", ns.texteFilons(0, 5))
verifie("filons : position inconnue", "Position inconnue ici, 5 endroits en tout", ns.texteFilons(nil, 5))

-- La fenêtre entière : chargement, ouverture, boutons. Les erreurs sont comptées comme des échecs.
local function essaie(libelle, f, ...)
  local bon, erreur = pcall(f, ...)
  if not bon then io.write("   erreur : " .. tostring(erreur) .. "\n") end
  verifie(libelle, true, bon)
end
local function cliquer(texte, rang)
  local vus = 0
  for _, s in ipairs(scripts) do
    if s.nom == "OnClick" and rawget(s.self, "_texte") == texte then
      vus = vus + 1
      if vus == (rang or 1) then s.f(s.self) return true end
    end
  end
  return false
end
local function premier(nom)
  for _, s in ipairs(scripts) do if s.nom == nom then return s end end
end
SlashCmdList = SlashCmdList -- (la commande /mt est rangée là)
local charge = premier("OnEvent")
verifie("un écouteur de chargement existe", true, charge ~= nil)
essaie("chargement sans erreur", charge.f, charge.self, "ADDON_LOADED", "MetiersAuto")
local db = MetiersAutoDB
verifie("réglages lus dans la base", true, db ~= nil and db.actif == true)
local aff = premier("OnShow")
essaie("ouverture de la fenêtre sans erreur", aff.f, aff.self)

db.courses = { { recette = 1, nombre = 2, nom = "A" }, { recette = 2, nombre = 1, nom = "B" } }
db.filons[7] = { { 0.5, 0.5, "Cuivre" } }
db.filons[9] = { { 0.1, 0.1, "Étain" } }
db.positionFleche, db.positionCourses = { "TOP", "TOP", 0, -50 }, { "LEFT", "LEFT", 10, 10 }
essaie("réouverture avec des données sans erreur", aff.f, aff.self)
verifie("bouton « Tout retirer » (liste de courses)", true, cliquer("Tout retirer"))
verifie("liste de courses vidée", 0, #db.courses)
verifie("bouton « Oublier cette carte »", true, cliquer("Oublier cette carte"))
verifie("carte oubliée", nil, db.filons[7])
verifie("l'autre carte reste", 1, #db.filons[9])
verifie("bouton « Replacer la flèche et la liste »", true, cliquer("Replacer la flèche et la liste"))
verifie("positions effacées", true, db.positionFleche == nil and db.positionCourses == nil)
verifie("bouton du mode pêche", true, (cliquer("Démarrer le mode pêche")))
essaie("commande /mt filons sans erreur", SlashCmdList.METIERSAUTO, "filons")
essaie("commande /mt filons oublier sans erreur", SlashCmdList.METIERSAUTO, "filons oublier")

-- Minerai ou herbe, et la flèche selon les métiers du personnage
verifie("butin de cuivre : minerai", "minerai", ns.genreDepuisButin({ { classe = 7, sousClasse = 7 } }))
verifie("butin de pacifique : herbe", "herbe", ns.genreDepuisButin({ { classe = 0, sousClasse = 0 }, { classe = 7, sousClasse = 9 } }))
verifie("butin d'un coffre : rien de retenu", nil, ns.genreDepuisButin({ { classe = 4, sousClasse = 2 } }))
verifie("ancien point « Filon de cuivre » : minerai", "minerai", ns.genreDepuisNom("Filon de cuivre"))
verifie("ancien point « Pacifique » : herbe", "herbe", ns.genreDepuisNom("Pacifique"))
local pts = { { 0.50, 0.50, "Filon de cuivre" }, { 0.60, 0.50, "Pacifique", "herbe" } }
local p1 = ns.plusProche(pts, 0.40, 0.50, 1000, 1000, {}, 0, { herbe = true })
verifie("herboriste : le filon plus proche est ignoré", "Pacifique", p1 and p1[3])
local p2 = ns.plusProche(pts, 0.40, 0.50, 1000, 1000, {}, 0, {})
verifie("dépeceur seul : aucune flèche", nil, p2)
local p3 = ns.plusProche(pts, 0.40, 0.50, 1000, 1000, {}, 0, { minerai = true, herbe = true })
verifie("mineur herboriste : le plus proche", "Filon de cuivre", p3 and p3[3])

os.exit(ok and 0 or 1)
