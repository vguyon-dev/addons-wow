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
-- L'écouteur d'évènements de l'addon : le dernier posé par le fichier (pour lui envoyer des évènements du jeu simulé).
local evenementsAddon
for i = #scripts, 1, -1 do
  if scripts[i].nom == "OnEvent" then evenementsAddon = scripts[i] break end
end

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
SlashCmdList = SlashCmdList -- (la commande /metiers est rangée là)
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
db.positionPeche = { "LEFT", "LEFT", 5, 5 }
verifie("bouton « Replacer les fenêtres »", true, cliquer("Replacer les fenêtres"))
verifie("positions effacées", true, db.positionFleche == nil and db.positionCourses == nil and db.positionPeche == nil)
verifie("bouton du mode pêche", true, (cliquer("Démarrer le mode pêche")))
essaie("commande /metiers filons sans erreur", SlashCmdList.METIERSAUTO, "filons")
essaie("commande /metiers filons oublier sans erreur", SlashCmdList.METIERSAUTO, "filons oublier")

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

-- ============================================================================
-- Pêche facilitée : calculs purs
-- ============================================================================

-- Appâts : le meilleur selon la compétence et le contenu des sacs.
local sacs = { [6529] = 3, [6530] = 2, [6533] = 1 }
local function compterSacs(id) return sacs[id] or 0 end
local meilleur, bloque = ns.meilleurAppat(75, compterSacs)
verifie("appât : compétence 75, le meilleur utilisable", 6530, meilleur and meilleur.id)
verifie("appât : le meilleur refusé est signalé", 6533, bloque and bloque.id)
verifie("appât : demande de compétence du refusé", 100, bloque and bloque.requis)
verifie("appât : compétence 100, le meilleur", 6533, (ns.meilleurAppat(100, compterSacs)).id)
verifie("appât : compétence 20, seulement le bauble", 6529, (ns.meilleurAppat(20, compterSacs)).id)
verifie("appât : sacs vides, aucun", nil, (ns.meilleurAppat(300, function() return 0 end)))
verifie("appât : compétence inconnue = 0", 6529, (ns.meilleurAppat(nil, compterSacs)).id)
local utilisables = ns.appatsDesSacs(100, compterSacs)
verifie("appâts utilisables : triés du meilleur au moins bon", "6533,6530,6529",
  utilisables[1].id .. "," .. utilisables[2].id .. "," .. utilisables[3].id)
verifie("appât : nombre dans les sacs", 2, utilisables[2].nombre)
verifie("appât : bonus posé 264 = +50", 50, ns.bonusAppatPose(264))
verifie("appât : bonus posé inconnu", nil, ns.bonusAppatPose(999))
verifie("appât connu", true, ns.appatConnu(6529) ~= nil)
verifie("appât inconnu", nil, ns.appatConnu(12345))

-- Paliers du rachat : 0, 5, 10, 20.
verifie("rachat : palier 0 = aucun", 0, ns.nombreRachat(0))
verifie("rachat : palier 1 = 5", 5, ns.nombreRachat(1))
verifie("rachat : palier 2 = 10", 10, ns.nombreRachat(2))
verifie("rachat : palier 3 = 20", 20, ns.nombreRachat(3))
verifie("rachat : palier hors limites = 0", 0, ns.nombreRachat(9))
verifie("rachat : palier absent = 0", 0, ns.nombreRachat(nil))
verifie("rachat : texte aucun", "Aucun", ns.texteRachat(0))
verifie("rachat : texte 10", "jusqu'à 10", ns.texteRachat(2))
verifie("rachat : nombre tapé 20 = palier 3", 3, ns.palierDeNombre(20))
verifie("rachat : nombre tapé 7 refusé", nil, ns.palierDeNombre(7))

-- Choix de l'appât chez le marchand : jamais un appât que la compétence refuse.
local offres = {
  { index = 1, id = 6529, prix = 100, lot = 1 },
  { index = 2, id = 6530, prix = 400, lot = 1 },
  { index = 3, id = 6533, prix = 5000, lot = 1 },
  { index = 4, id = 999, prix = 1, lot = 1 },
}
verifie("marchand : compétence 75, le 6530", 6530, (ns.choisirAppatMarchand(offres, 75) or {}).id)
verifie("marchand : compétence 100, le 6533", 6533, (ns.choisirAppatMarchand(offres, 100) or {}).id)
verifie("marchand : compétence 10, le 6529", 6529, (ns.choisirAppatMarchand(offres, 10) or {}).id)
verifie("marchand : compétence inconnue, rien", nil, ns.choisirAppatMarchand(offres, nil))
offres[3].utilisable = false
verifie("marchand : un appât inutilisable est sauté", 6530, (ns.choisirAppatMarchand(offres, 100) or {}).id)
verifie("marchand : un autre objet n'est jamais pris", nil, ns.choisirAppatMarchand({ { index = 1, id = 999, prix = 1 } }, 300))
local egaux = { { index = 1, id = 6530, prix = 800, lot = 1 }, { index = 2, id = 6811, prix = 300, lot = 1 } }
verifie("marchand : à bonus égal, le moins cher", 6811, (ns.choisirAppatMarchand(egaux, 100) or {}).id)

-- Combien en racheter.
local n, cout, reduit = ns.nombreARacheter(10, 4, 100, 1, 100000)
verifie("racheter : 10 voulus, 4 possédés", 6, n)
verifie("racheter : coût en cuivre", 600, cout)
verifie("racheter : pas réduit", false, reduit)
n, cout, reduit = ns.nombreARacheter(5, 5, 100, 1, 100000)
verifie("racheter : déjà assez", 0, n)
verifie("racheter : déjà assez, aucun coût", 0, cout)
n, cout, reduit = ns.nombreARacheter(5, 9, 100, 1, 100000)
verifie("racheter : plus que voulu, rien", 0, n)
n, cout, reduit = ns.nombreARacheter(20, 0, 100, 1, 450)
verifie("racheter : limité par l'or (4 sur 20)", 4, n)
verifie("racheter : limité par l'or, coût", 400, cout)
verifie("racheter : limité par l'or, signalé", true, reduit)
n = ns.nombreARacheter(20, 0, 100, 1, 50)
verifie("racheter : pas assez d'or du tout", 0, n)
n = ns.nombreARacheter(20, 0, 100, 1, 100000, 3)
verifie("racheter : limité par le stock", 3, n)
n = ns.nombreARacheter(20, 0, 100, 1, 100000, -1)
verifie("racheter : stock illimité (-1)", 20, n)
n, cout = ns.nombreARacheter(10, 0, 500, 5, 100000)
verifie("racheter : lot de 5, prix unitaire 100", 10, n)
verifie("racheter : lot de 5, coût", 1000, cout)
verifie("racheter : prix inconnu, rien", 0, (ns.nombreARacheter(10, 0, nil, 1, 1000)))
verifie("racheter : voulu 0, rien", 0, (ns.nombreARacheter(0, 0, 100, 1, 1000)))

-- Temps restant de l'appât, alerte.
verifie("temps : pas d'appât", "aucun appât posé", ns.texteTempsRestant(nil))
verifie("temps : fini", "plus d'appât", ns.texteTempsRestant(0))
verifie("temps : 45 s", "45 s", ns.texteTempsRestant(45))
verifie("temps : 3 min 05 s", "3 min 05 s", ns.texteTempsRestant(185))
verifie("temps : 10 min 00 s", "10 min 00 s", ns.texteTempsRestant(600))
verifie("alerte : à 50 s, première fois", true, ns.doitAlerterAppat(50, false))
verifie("alerte : déjà donnée", false, ns.doitAlerterAppat(50, true))
verifie("alerte : trop tôt (120 s)", false, ns.doitAlerterAppat(120, false))
verifie("alerte : fini (0 s)", false, ns.doitAlerterAppat(0, false))
verifie("alerte : durée inconnue", false, ns.doitAlerterAppat(nil, false))

-- Argent et textes de la fenêtre.
verifie("argent : 0", "0 pc", ns.texteArgent(0))
verifie("argent : 5 pc", "5 pc", ns.texteArgent(5))
verifie("argent : 1 pa 5 pc", "1 pa 5 pc", ns.texteArgent(105))
verifie("argent : 3 po 20 pa", "3 po 20 pa", ns.texteArgent(32000))
verifie("argent : 2 po 5 pc", "2 po 5 pc", ns.texteArgent(20005))
verifie("argent : inconnu = 0", "0 pc", ns.texteArgent(nil))
verifie("compétence : 97 / 150", "Pêche : 97 / 150", ns.texteCompetence(97, 150))
verifie("compétence : sans maximum", "Pêche : 97", ns.texteCompetence(97, nil))
verifie("compétence : pas apprise", "Pêche : pas apprise", ns.texteCompetence(nil, nil))
verifie("bonus d'appât affiché", "appât +50", ns.texteBonusAppat(50))
verifie("bonus d'appât absent", "", ns.texteBonusAppat(nil))

-- La session : lancers, prises, par heure, valeur.
local ses = ns.nouvelleSession()
ns.compterLancer(ses, 100)
ns.compterLancer(ses, 130)
ns.compterLancer(ses, 160)
verifie("session : 3 lancers", 3, ses.lancers)
verifie("session : temps actif 60 s", 60, ses.actif)
ns.compterPrise(ses, { { id = 10, nombre = 2 } })
ns.compterPrise(ses, { { id = 11, nombre = 1 }, { id = 10, nombre = 1 } })
verifie("session : 2 prises", 2, ses.prises)
verifie("session : par heure inconnu sous 3 prises", nil, ns.prisesParHeure(ses, 160))
ns.compterPrise(ses, {})
verifie("session : 3 prises (l'or compte)", 3, ses.prises)
verifie("session : par heure = 3 prises en 60 s = 180", 180, ns.prisesParHeure(ses, 160))
verifie("session : par heure compte la fin en cours (30 s de plus)", 120, math.floor(ns.prisesParHeure(ses, 190) + 0.5))
verifie("session : après une longue pause, le temps n'augmente plus", 180, ns.prisesParHeure(ses, 660))
verifie("session : par heure écrit", "180", ns.textePrisesParHeure(180))
verifie("session : par heure inconnu écrit", "-", ns.textePrisesParHeure(nil))
verifie("session : objet 10 pêché 3 fois", 3, ses.objets[10])
local prix = { [10] = 50, [11] = 200 }
verifie("session : valeur 3×50 + 1×200", 350, ns.valeurSession(ses, function(id) return prix[id] end))
verifie("session : valeur d'un objet au prix inconnu = 0", 150, ns.valeurSession(ses, function(id) return id == 10 and 50 or nil end))
local vues = ns.prisesAffichees(ses, 8)
verifie("session : prises affichées, la plus récente d'abord", 11, vues[1].id)
verifie("session : prises affichées, nombre de l'objet 10", 3, vues[2].nombre)
verifie("session : maximum affiché", 1, #ns.prisesAffichees(ses, 1))
ns.compterEchappe(ses)
verifie("session : un échappé", 1, ses.echappes)
-- Pause de plus de 90 s : le temps de pêche ne compte pas la pause.
local ses2 = ns.nouvelleSession()
ns.compterLancer(ses2, 0)
ns.compterLancer(ses2, 500)
verifie("session : pause trop longue non comptée", 0, ses2.actif)

-- La touche unique : que fait-elle ?
verifie("état : mode coupé", "arret", ns.etatPeche(false, false, false, true))
verifie("état : en combat", "combat", ns.etatPeche(true, true, true, true))
verifie("état : ligne à l'eau", "ferrer", ns.etatPeche(true, false, true, true))
verifie("état : canne sans appât", "appat", ns.etatPeche(true, false, false, true))
verifie("état : prêt à lancer", "lancer", ns.etatPeche(true, false, false, false))
verifie("phrase : lancer", "Appuie sur F pour lancer la ligne.", ns.texteAction("lancer", "F"))
verifie("phrase : ferrer", "Ligne à l'eau : appuie sur F au plouf pour ferrer.", ns.texteAction("ferrer", "F"))
verifie("phrase : appât", "Appuie sur F pour poser l'appât.", ns.texteAction("appat", "F"))
verifie("phrase : sans touche", "Choisis une touche de pêche avec le bouton ci-dessous.", ns.texteAction("lancer", nil))
verifie("phrase : en combat", "En combat : la touche reprend son rôle normal.", ns.texteAction("combat", "F"))
verifie("phrase : mode coupé", "Mode pêche arrêté : relance-le pour utiliser la touche.", ns.texteAction("arret", "F"))

-- Choisir une touche.
verifie("combo : F seule", "F", ns.comboTouche("F", false, false, false))
verifie("combo : Maj+F", "SHIFT-F", ns.comboTouche("F", false, false, true))
verifie("combo : Alt+Ctrl+Maj+F", "ALT-CTRL-SHIFT-F", ns.comboTouche("F", true, true, true))
verifie("touche tapée : f", "F", ns.toucheValide("f"))
verifie("touche tapée : shift-f", "SHIFT-F", ns.toucheValide(" shift-f "))
verifie("touche tapée : vide", nil, ns.toucheValide(""))
verifie("touche tapée : tiret final", nil, ns.toucheValide("shift-"))
verifie("touche tapée : caractères bizarres", nil, ns.toucheValide("a;b"))
verifie("touche tapée : trop longue", nil, ns.toucheValide(string.rep("A", 40)))

-- Réglages du jeu pour ferrer : notés avant, remis après.
local reglagesJeu = { SoftTargetInteract = "1", SoftTargetInteractArc = "0", SoftTargetInteractRange = "10" }
local gardees = ns.garderValeurs(ns.NOMS_FERRAGE, function(nom) return reglagesJeu[nom] end)
local nbGardees = 0
for _ in pairs(gardees) do nbGardees = nbGardees + 1 end
verifie("ferrage : trois valeurs notées (deux réglages inconnus)", 3, nbGardees)
verifie("ferrage : valeur d'origine notée", "1", gardees.SoftTargetInteract)
verifie("ferrage : réglage inconnu non noté", nil, gardees.SoftTargetIconGameObject)
for nom, v in pairs(ns.REGLAGES_FERRAGE) do if reglagesJeu[nom] ~= nil then reglagesJeu[nom] = v end end
verifie("ferrage : réglage changé", "3", reglagesJeu.SoftTargetInteract)
local remis = ns.remettreValeurs(gardees, ns.NOMS_FERRAGE, function(nom, v) reglagesJeu[nom] = v end)
verifie("ferrage : trois valeurs remises", 3, remis)
verifie("ferrage : valeur d'origine remise", "1", reglagesJeu.SoftTargetInteract)
verifie("ferrage : portée d'origine remise", "10", reglagesJeu.SoftTargetInteractRange)
verifie("ferrage : réglage inconnu pas créé", nil, reglagesJeu.SoftTargetIconGameObject)

-- Poisson échappé.
verifie("échappé : message dans le 1er argument", true, ns.estMessageEchappe("Ça s'est échappé", nil, "Ça s'est échappé"))
verifie("échappé : message dans le 2e argument", true, ns.estMessageEchappe(50, "Ça s'est échappé", "Ça s'est échappé"))
verifie("échappé : autre message", false, ns.estMessageEchappe("Autre", nil, "Ça s'est échappé"))
verifie("échappé : texte attendu inconnu", false, ns.estMessageEchappe(nil, nil, nil))

-- ============================================================================
-- Pêche facilitée : le jeu simulé (touche, ferrage, appât, ramassage, rachat)
-- ============================================================================
local sorties = {}
local printOrigine = print
print = function(...) sorties[#sorties + 1] = table.concat({ ... }, " ") end
local function derniereSortie() return sorties[#sorties] or "" end

local horloge = 1000
function GetTime() return horloge end
local enCombat = false
function InCombatLockdown() return enCombat end
local journal = {}
function SetOverrideBindingClick(_, _, touche, bouton) journal[#journal + 1] = { "clic", touche, bouton } end
function SetOverrideBinding(_, _, touche, commande) journal[#journal + 1] = { "cmd", touche, commande } end
function ClearOverrideBindings() journal[#journal + 1] = { "effacer" } end
local function dernier()
  local j = journal[#journal]
  if not j then return "rien" end
  return table.concat(j, " ")
end
local cvars = { SoftTargetInteract = "1", SoftTargetInteractArc = "0", SoftTargetInteractRange = "10",
  Sound_SFXVolume = "0.5", Sound_MusicVolume = "0.4", Sound_AmbienceVolume = "0.3" }
function GetCVar(nom) return cvars[nom] end
function SetCVar(nom, v) if cvars[nom] ~= nil then cvars[nom] = v end end
local jeu = { canne = true, enchant = false, competence = 75, sacs = { [6529] = 3 } }
function IsPlayerSpell(id) return id == 7620 end
function GetSpellInfo() return "Pêche" end
function GetInventoryItemID() return 2000 end
function GetItemInfoInstant()
  if jeu.canne then return 2000, "Arme", "Cannes à pêche", "", 135, 2, 20 end
  return 2000, "Arme", "Épées", "", 135, 2, 7
end
function GetWeaponEnchantInfo() return jeu.enchant, 180000, 0, 264 end
function GetProfessions() return nil, nil, nil, 4 end
function GetProfessionInfo() return "Pêche", 1, jeu.competence, 300, 0, 0, 356, 0 end
function GetItemCount(id) return jeu.sacs[id] or 0 end
function UnitChannelInfo() return nil end
function PlaySound() end
SOUNDKIT = { RAID_WARNING = 8959 }
ERR_FISH_ESCAPED = "Votre poisson s'est échappé !"
C_Timer = { After = function(_, f) f() end, NewTicker = function() end }
local function envoyer(evenement, ...) evenementsAddon.f(evenementsAddon.self, evenement, ...) end
local appuyes = {} -- les PostClick des boutons sécurisés, dans l'ordre : lancer, appât (touche), appât (fenêtre)
for _, s in ipairs(scripts) do if s.nom == "PostClick" then appuyes[#appuyes + 1] = s end end
verifie("trois boutons sécurisés ont un PostClick", 3, #appuyes)

db = MetiersAutoDB
db.actif, db.pecheTouche, db.pecheAppat, db.pecheFenetre, db.pecheRamasser = true, true, true, true, true
db.rachatPalier, db.touchePeche, db.ferrageAvant, db.sonAvant = 0, nil, nil, nil
-- Le réglage « une touche pour récolter » met déjà l'interaction à 3 : on le coupe pour voir la vraie valeur d'origine.
db.interaction = false
cvars.SoftTargetInteract = "1"

-- La touche se choisit par commande.
essaie("/metiers touche sans erreur", SlashCmdList.METIERSAUTO, "touche F")
verifie("touche de pêche retenue", "F", db.touchePeche)
essaie("/metiers touche sans argument", SlashCmdList.METIERSAUTO, "touche")
verifie("/metiers touche dit la touche", true, derniereSortie():find("touche de pêche : F", 1, true) ~= nil)
essaie("/metiers touche refuse une touche absurde", SlashCmdList.METIERSAUTO, "touche a;b")
verifie("touche absurde refusée, F gardée", "F", db.touchePeche)

-- Mode coupé : rien n'est relié.
journal = {}
envoyer("BAG_UPDATE_DELAYED")
verifie("mode coupé : la touche n'est pas reliée", true, dernier() == "rien" or dernier() == "effacer")

-- Démarrage du mode pêche : canne sans appât et un appât dans les sacs, donc la touche pose l'appât.
essaie("démarrage du mode pêche", MetiersAuto_ModePeche)
verifie("mode pêche : la touche pose d'abord l'appât", "clic F MetiersAutoAppat", dernier())
verifie("mode pêche : le son est noté", "0.5", db.sonAvant and db.sonAvant.Sound_SFXVolume)
-- Un appui : la touche lance ensuite la ligne (le jeu met un instant à voir l'appât).
essaie("appui sur le bouton d'appât", appuyes[2].f, appuyes[2].self)
verifie("après l'appât : la touche lance la ligne", "clic F MetiersAutoLancer", dernier())
-- L'appât est posé : on lance toujours.
horloge = horloge + 10
jeu.enchant = true
envoyer("UNIT_INVENTORY_CHANGED", "player")
verifie("appât posé : la touche lance la ligne", "clic F MetiersAutoLancer", dernier())
-- Ligne à l'eau : la touche ferre, les réglages du jeu sont notés puis changés.
envoyer("UNIT_SPELLCAST_CHANNEL_START", "player", "guid", 7620)
verifie("ligne à l'eau : la touche ferre (interaction)", "cmd F INTERACTTARGET", dernier())
verifie("ferrage : interaction réglée à 3", "3", cvars.SoftTargetInteract)
verifie("ferrage : portée réglée à 30", "30", cvars.SoftTargetInteractRange)
verifie("ferrage : valeur d'origine notée dans la base", "1", db.ferrageAvant and db.ferrageAvant.SoftTargetInteract)
verifie("ferrage : réglage inconnu jamais créé", nil, cvars.SoftTargetIconGameObject)
-- Le poisson mord : le canal s'arrête, le butin s'ouvre.
envoyer("UNIT_SPELLCAST_CHANNEL_STOP", "player", "guid", 7620)
verifie("canal fini : la touche relance la ligne", "clic F MetiersAutoLancer", dernier())
local pris = {}
IsFishingLoot = function() return true end
GetNumLootItems = function() return 3 end
GetLootSlotLink = function(i)
  if i == 1 then return "|cffffffff|Hitem:6358::::::::|h[Poisson]|h|r" end
  if i == 2 then return "|cffffffff|Hitem:6359::::::::|h[Autre poisson]|h|r" end
  return nil -- l'or n'a pas de lien
end
GetLootSlotInfo = function(i) return 134, "x", (i == 2) and 2 or 1 end
LootSlot = function(i) pris[#pris + 1] = i end
envoyer("LOOT_READY")
envoyer("LOOT_OPENED")
verifie("ramassage : les trois emplacements pris, du dernier au premier", "3,2,1", table.concat(pris, ","))
envoyer("LOOT_CLOSED")
envoyer("UI_ERROR_MESSAGE", 50, ERR_FISH_ESCAPED)
essaie("/metiers session sans erreur", SlashCmdList.METIERSAUTO, "session")
verifie("session : 1 lancer, 1 prise (une seule fois), 1 échappé", true,
  derniereSortie():find("1 lancers, 1 prises, 1 échappés", 1, true) ~= nil)
-- Ramassage coupé : on ne prend rien.
db.pecheRamasser = false
pris = {}
envoyer("LOOT_READY")
envoyer("LOOT_CLOSED")
verifie("ramassage coupé : rien n'est pris", 0, #pris)
db.pecheRamasser = true
-- Un butin qui n'est pas de la pêche n'est pas compté.
IsFishingLoot = function() return false end
pris = {}
envoyer("LOOT_READY")
envoyer("LOOT_CLOSED")
verifie("butin hors pêche : rien n'est pris", 0, #pris)
IsFishingLoot = function() return true end

-- Fin du mode pêche : les réglages du jeu sont remis à leur valeur d'origine.
envoyer("UNIT_SPELLCAST_CHANNEL_START", "player", "guid", 7620)
essaie("arrêt du mode pêche", MetiersAuto_ModePeche)
verifie("fin du mode : interaction remise à 1", "1", cvars.SoftTargetInteract)
verifie("fin du mode : arc remis à 0", "0", cvars.SoftTargetInteractArc)
verifie("fin du mode : portée remise à 10", "10", cvars.SoftTargetInteractRange)
verifie("fin du mode : rien de noté", nil, db.ferrageAvant)
verifie("fin du mode : la touche est retirée", "effacer", dernier())
verifie("fin du mode : le son est remis", "0.5", cvars.Sound_SFXVolume)
envoyer("UNIT_SPELLCAST_CHANNEL_STOP", "player", "guid", 7620)

-- Combat : la touche n'est jamais touchée en combat, et tout est remis après.
jeu.enchant = true
essaie("nouveau mode pêche", MetiersAuto_ModePeche)
envoyer("UNIT_SPELLCAST_CHANNEL_START", "player", "guid", 7620)
verifie("combat : ligne à l'eau, la touche ferre", "cmd F INTERACTTARGET", dernier())
local avant = #journal
enCombat = true
envoyer("PLAYER_REGEN_DISABLED")
verifie("combat : rien n'est relié ni retiré en plein combat", avant, #journal)
verifie("combat : réglages du jeu gardés jusqu'à la fin du combat", "1", db.ferrageAvant and db.ferrageAvant.SoftTargetInteract)
enCombat = false
envoyer("PLAYER_REGEN_ENABLED")
verifie("fin du combat : la touche est retirée", "effacer", dernier())
verifie("fin du combat : interaction remise à 1", "1", cvars.SoftTargetInteract)
verifie("fin du combat : rien de noté", nil, db.ferrageAvant)
envoyer("UNIT_SPELLCAST_CHANNEL_STOP", "player", "guid", 7620)
-- En combat, on ne peut pas démarrer le mode pêche.
enCombat = true
journal = {}
essaie("mode pêche refusé en combat", MetiersAuto_ModePeche)
verifie("combat : le mode ne démarre pas", 0, #journal)
enCombat = false

-- Déconnexion pendant la pêche : les réglages sont remis.
essaie("mode pêche avant déconnexion", MetiersAuto_ModePeche)
envoyer("UNIT_SPELLCAST_CHANNEL_START", "player", "guid", 7620)
verifie("avant déconnexion : interaction à 3", "3", cvars.SoftTargetInteract)
envoyer("PLAYER_LOGOUT")
verifie("déconnexion : interaction remise à 1", "1", cvars.SoftTargetInteract)
verifie("déconnexion : portée remise à 10", "10", cvars.SoftTargetInteractRange)
envoyer("UNIT_SPELLCAST_CHANNEL_STOP", "player", "guid", 7620)
MetiersAuto_ModePeche()

-- Touche coupée dans les réglages : rien n'est relié.
db.pecheTouche = false
jeu.enchant = false
journal = {}
MetiersAuto_ModePeche()
verifie("touche coupée : rien n'est relié", true, dernier() == "rien" or dernier() == "effacer")
db.pecheTouche = true
-- Appât coupé : la touche lance directement.
db.pecheAppat = false
envoyer("BAG_UPDATE_DELAYED")
verifie("appât coupé : la touche lance la ligne", "clic F MetiersAutoLancer", dernier())
db.pecheAppat = true
-- Pas d'appât dans les sacs : elle lance aussi.
jeu.sacs = {}
envoyer("BAG_UPDATE_DELAYED")
verifie("sacs sans appât : la touche lance la ligne", "clic F MetiersAutoLancer", dernier())
jeu.sacs = { [6529] = 3 }
-- Plus de canne : pas d'appât à poser.
jeu.canne = false
envoyer("PLAYER_EQUIPMENT_CHANGED")
verifie("sans canne : la touche lance la ligne", "clic F MetiersAutoLancer", dernier())
jeu.canne = true
envoyer("PLAYER_EQUIPMENT_CHANGED")
verifie("canne remise : la touche pose l'appât", "clic F MetiersAutoAppat", dernier())
MetiersAuto_ModePeche()

-- Rachat d'appâts chez un marchand (coupé au départ).
local achats = {}
local marchand = { { 6529, 100 }, { 6530, 400 }, { 6533, 5000 } }
function GetMerchantNumItems() return #marchand end
function GetMerchantItemLink(i) return "|cffffffff|Hitem:" .. marchand[i][1] .. "::::::::|h[Appât]|h|r" end
function GetMerchantItemInfo(i) return "Appât", 1, marchand[i][2], 1, -1, true, true, nil end
function GetMerchantItemMaxStack() return 20 end
local orJoueur = 100000
function GetMoney() return orJoueur end
function BuyMerchantItem(i, k) achats[#achats + 1] = i .. "x" .. k end
jeu.competence, jeu.sacs = 75, { [6530] = 2 }
db.rachatPalier = 0
envoyer("MERCHANT_SHOW")
verifie("rachat coupé au départ : rien n'est acheté", 0, #achats)
db.rachatPalier = 1 -- 5 appâts
envoyer("MERCHANT_SHOW")
verifie("rachat : le meilleur appât permis (n° 2) pour compléter à 5", "2x3", achats[1])
verifie("rachat : dit dans le chat ce qui est acheté et le prix", true,
  derniereSortie():find("racheté 3 ×", 1, true) ~= nil and derniereSortie():find("12 pa", 1, true) ~= nil)
achats = {}
jeu.sacs = { [6530] = 5 }
envoyer("MERCHANT_SHOW")
verifie("rachat : déjà assez, rien n'est acheté", 0, #achats)
jeu.sacs = {}
orJoueur = 450
envoyer("MERCHANT_SHOW")
verifie("rachat : limité par l'or (1 sur 5)", "2x1", achats[1])
achats = {}
orJoueur = 10
envoyer("MERCHANT_SHOW")
verifie("rachat : plus assez d'or, rien n'est acheté", 0, #achats)
verifie("rachat : le dit dans le chat", true, derniereSortie():find("pas assez d'or", 1, true) ~= nil)
orJoueur = 100000
jeu.competence = 10
db.rachatPalier = 3
envoyer("MERCHANT_SHOW")
verifie("rachat : jamais un appât que la compétence refuse (le bauble seul)", "1x20", achats[1])
achats = {}
GetProfessions = function() return nil end
envoyer("MERCHANT_SHOW")
verifie("rachat : pêche pas apprise, rien n'est acheté", 0, #achats)
essaie("/metiers appats sans erreur", SlashCmdList.METIERSAUTO, "appats 10")
verifie("/metiers appats 10 règle le palier 2", 2, db.rachatPalier)
essaie("/metiers appats 7 refusé", SlashCmdList.METIERSAUTO, "appats 7")
verifie("/metiers appats 7 : palier inchangé", 2, db.rachatPalier)
essaie("/metiers touche aucune", SlashCmdList.METIERSAUTO, "touche aucune")
verifie("touche retirée", nil, db.touchePeche)
essaie("/metiers fenetre sans erreur", SlashCmdList.METIERSAUTO, "fenetre")
essaie("/metiers session vider sans erreur", SlashCmdList.METIERSAUTO, "session vider")
essaie("aide /metiers sans erreur", SlashCmdList.METIERSAUTO, "aide")
print = printOrigine

-- Canne à pêche absente : on ne prévient que là où le jeu en exige une.
local function infosCanne() return 1, "", "", "", 1, 2, 20 end
local function infosEpee() return 1, "", "", "", 1, 2, 7 end
verifie("canne : Forever, une épée en main", true, ns.canneManque(16001, 248007, infosEpee))
verifie("canne : Forever, rien en main", true, ns.canneManque(16001, nil, infosEpee))
verifie("canne : Forever, une canne en main", false, ns.canneManque(16001, 6256, infosCanne))
verifie("canne : Retail ne demande pas de canne", false, ns.canneManque(120105, 248007, infosEpee))
verifie("canne : le jeu ne décrit pas les objets", false, ns.canneManque(16001, 248007, nil))

if ok then print("Tout est bon.") end

os.exit(ok and 0 or 1)
