-- Simulation hors jeu du Carnet : fausse API WoW, puis scénarios de passage de niveau et de présentation
-- (un cadre, onglets, séparés, replié) avec un faux Butin rapide.
-- Lancer depuis Windows :
--   wsl lua5.1 tests/CarnetDeSession_simu.lua CarnetDeSession/CarnetDeSession.lua
local bidon
bidon = function()
  return setmetatable({}, { __index = function() return bidon() end, __call = function() return bidon() end })
end

-- Un texte (ou une texture) qui se souvient de ce qu'on lui a demandé.
local function police(parent)
  local f = bidon()
  local e = { texte = "", visible = true }
  rawset(f, "_e", e)
  rawset(f, "SetText", function(_, t) e.texte = t end)
  rawset(f, "GetText", function() return e.texte end)
  rawset(f, "Show", function() e.visible = true end)
  rawset(f, "Hide", function() e.visible = false end)
  rawset(f, "SetShown", function(_, v) e.visible = v and true or false end)
  rawset(f, "IsShown", function() return e.visible end)
  rawset(f, "GetStringHeight", function() return 12 end)
  rawset(f, "SetPoint", function(_, ...) e.pt = { ... } end)
  rawset(f, "ClearAllPoints", function() e.pt = nil end)
  if parent then parent._polices[#parent._polices + 1] = f end
  return f
end

-- Les cadres de l'addon qu'on veut retrouver par leur nom.
local NOMMES = { CarnetDeSessionFrame = true, CarnetDeSessionTitre = true,
  CarnetDeSessionOngletPerso = true, CarnetDeSessionOngletFarm = true }
-- Champs que le code lit pour savoir s'il doit créer un élément : absents tant qu'on ne les a pas posés.
local ABSENTS = { titreHabille = true, traitHabille = true, fermerHabille = true, fondHabille = true }

local cadres = {}
function CreateFrame(_, nom)
  local f = setmetatable({}, {
    __index = function(_, k) if ABSENTS[k] then return nil end return bidon() end,
    __call = function() return bidon() end,
  })
  local scripts, e = {}, { visible = false, h = 0, l = 0 }
  rawset(f, "_scripts", scripts)
  rawset(f, "_e", e)
  rawset(f, "_polices", {})
  rawset(f, "SetScript", function(_, n, fn) scripts[n] = fn end)
  rawset(f, "RegisterEvent", function() end)
  rawset(f, "IsShown", function() return e.visible end)
  local function montrer(v)
    local avant = e.visible
    e.visible = v and true or false
    if e.visible and not avant and scripts.OnShow then scripts.OnShow(f) end
  end
  rawset(f, "Show", function() montrer(true) end)
  rawset(f, "Hide", function() montrer(false) end)
  rawset(f, "SetShown", function(_, v) montrer(v) end)
  rawset(f, "SetHeight", function(_, h) e.h = h end)
  rawset(f, "SetWidth", function(_, l) e.l = l end)
  rawset(f, "SetSize", function(_, l, h) e.l, e.h = l, h end)
  rawset(f, "GetPoint", function() return "CENTER", UIParent, "CENTER", 12, 34 end)
  rawset(f, "StartMoving", function() e.deplace = true end)
  rawset(f, "StopMovingOrSizing", function() e.deplace = false end)
  rawset(f, "CreateFontString", function(self) return police(self) end)
  rawset(f, "CreateTexture", function(self) return police(self) end)
  if nom and NOMMES[nom] then _G[nom] = f end
  cadres[#cadres + 1] = f
  return f
end
-- Aucun champ ne doit être écrit sur un cadre du jeu : UIParent refuse toute écriture.
UIParent = setmetatable({}, { __newindex = function(_, k) error("champ écrit sur UIParent : " .. tostring(k)) end })
UISpecialFrames = {}
tinsert = table.insert
Minimap = bidon()
rawset(Minimap, "GetWidth", function() return 140 end)
time, date = os.time, os.date
C_Timer = { NewTicker = function() end }
SlashCmdList = {}
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
local etat = { niveau = 1, xp = 0, xpMax = 250, argent = 0, uniteNiveau = 1 }
function UnitLevel() return etat.uniteNiveau end
function UnitXP() return etat.xp end
function UnitXPMax() return etat.xpMax end
function GetMoney() return etat.argent end
local sorties = {}
function print(t) sorties[#sorties + 1] = tostring(t) end

-- Un faux Butin rapide : les deux fonctions globales qu'il expose, et ce qu'on lui demande.
local bilanFaux = {
  lignes = {
    { libelle = "Durée", valeur = "76 min", texte = "Durée : 76 min" },
    { libelle = "Or ramassé", valeur = "2 po", texte = "Or ramassé : 2 po" },
    { libelle = "Par heure", valeur = "2 po 58", couleur = "40ff40", texte = "x" },
    { libelle = "|Hitem:1|h[Peau]|h", valeur = "× 3", texte = "3 × [Peau]" },
  },
  parHeure = "2 po 58", duree = 4560,
}
local appelsCache = {}
function ButinRapide_LignesBilan() return bilanFaux end
function ButinRapide_SetBilanCache(v) appelsCache[#appelsCache + 1] = v end

local ns = {}
local reglagesLua = arg[1]:gsub("[^/]+$", "Reglages.lua")
assert(loadfile(reglagesLua))("CarnetDeSession", ns)
assert(loadfile(arg[1]))("CarnetDeSession", ns)
-- Chaque événement va à tous les cadres qui écoutent (celui de l'addon, celui des réglages).
local function evt(nom, ...)
  for _, f in ipairs(cadres) do
    if f._scripts.OnEvent then f._scripts.OnEvent(f, nom, ...) end
  end
end

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
-- 6. carnet coupé : rien ne compte, et la réactivation repart de la barre actuelle
etat.uniteNiveau = 3
CarnetDeSessionDB.actif = false
local avant = s.xpGagnee
etat.xp = 300; evt("PLAYER_XP_UPDATE", "player")
evt("PARTY_KILL", nil, "Creature-0-1")
verifie("coupé : pas d'expérience comptée", avant, s.xpGagnee)
verifie("coupé : pas de monstre compté", 0, s.monstres)
CarnetDeSessionDB.actif = true
etat.xp = 350; evt("PLAYER_XP_UPDATE", "player")
verifie("réactivé : seulement le gain d'après", avant + 50, s.xpGagnee)
verifie("réglages : actif par défaut", true, CarnetDeSessionDB.affiche)

-- ===== Présentations =====
local F = CarnetDeSessionFrame
local db = CarnetDeSessionDB
local function carnet(commande) SlashCmdList.CARNETDESESSION(commande) end
-- Les lignes affichées, de haut en bas : « libellé|valeur » (valeur vide pour un intertitre).
local function lignesVisibles()
  local parY, ys = {}, {}
  for _, p in ipairs(F._polices) do
    local e = p._e
    if e.visible and e.pt and e.pt[3] and e.pt[3] <= -30 then
      local y = e.pt[3]
      if not parY[y] then parY[y] = { g = "", d = "" }; ys[#ys + 1] = y end
      if e.pt[1] == "TOPLEFT" then parY[y].g = e.texte else parY[y].d = e.texte end
    end
  end
  table.sort(ys, function(a, b) return a > b end)
  local l = {}
  for _, y in ipairs(ys) do l[#l + 1] = parY[y].g .. "|" .. parY[y].d end
  return l
end
local function titre() return F.titreHabille._e.texte end
local function dernierCache() return appelsCache[#appelsCache] end
-- Le texte de la ligne du cadre replié (à droite du titre), nil s'il n'est pas affiché.
local function resumeVisible()
  for _, p in ipairs(F._polices) do
    if p._e.visible and p._e.pt and p._e.pt[1] == "TOPRIGHT" and p._e.pt[3] == -12 then return p._e.texte end
  end
end

-- Au départ : présentation « un seul cadre » par défaut, farm repris du faux Butin, son cadre caché.
verifie("défaut : présentation un", "un", db.reunir)
verifie("défaut : le Carnet demande de cacher le bilan", true, appelsCache[1])
verifie("un : titre Session", "Session", titre())
verifie("un : largeur du cadre réuni", 250, F._e.l)
local l = lignesVisibles()
verifie("un : 5 lignes perso + Farm + 4 lignes farm", 10, #l)
verifie("un : l'intertitre Farm", "Farm|", l[6])
verifie("un : première ligne du farm", "Durée|76 min", l[7])
verifie("un : ligne colorée par la couleur donnée", "Par heure||cff40ff402 po 58|r", l[9])
verifie("un : le lien de l'objet et son nombre", "|Hitem:1|h[Peau]|h|× 3", l[10])
verifie("un : hauteur", 210, F._e.h)
verifie("un : zone du titre active", true, CarnetDeSessionTitre._e.visible)
verifie("un : pas d'onglets", false, CarnetDeSessionOngletFarm._e.visible)

-- Repli : une seule ligne avec le temps de jeu et l'or par heure du farm.
s.debut = os.time() - 4560
CarnetDeSessionTitre._scripts.OnMouseDown()
CarnetDeSessionTitre._scripts.OnClick()
verifie("replié : gardé dans les réglages", true, db.replie)
verifie("replié : hauteur d'une ligne", 30, F._e.h)
verifie("replié : plus aucune ligne", 0, #lignesVisibles())
verifie("replié : temps et or par heure", "1 h 16 · 2 po 58/h", resumeVisible())
verifie("replié : titre", "Session", titre())
verifie("pur : résumé sans farm", "1 h 16", ns.resume(4560, nil))
verifie("pur : résumé court", "42 min · 5/h", ns.resume(2520, "5"))
CarnetDeSessionTitre._scripts.OnClick()
verifie("déplié : état gardé", false, db.replie)
verifie("déplié : hauteur d'avant", 210, F._e.h)
verifie("déplié : les lignes reviennent", 10, #lignesVisibles())
verifie("déplié : le résumé disparaît", nil, resumeVisible())

-- Glisser par le titre : le cadre bouge, garde sa place, et le clic qui suit ne replie pas.
CarnetDeSessionTitre._scripts.OnMouseDown()
CarnetDeSessionTitre._scripts.OnDragStart()
verifie("glisser par le titre : le cadre bouge", true, F._e.deplace)
CarnetDeSessionTitre._scripts.OnDragStop()
verifie("glisser : le cadre s'arrête", false, F._e.deplace)
verifie("glisser : position gardée", 34, db.position[4])
CarnetDeSessionTitre._scripts.OnClick()
verifie("glisser : le clic d'après ne replie pas", false, db.replie)

-- Onglets.
carnet("reunir onglets")
verifie("onglets : réglage", "onglets", db.reunir)
verifie("onglets : les deux onglets visibles", true, CarnetDeSessionOngletPerso._e.visible and CarnetDeSessionOngletFarm._e.visible)
l = lignesVisibles()
verifie("onglets, Personnage : 5 lignes", 5, #l)
verifie("onglets, Personnage : Temps de jeu d'abord", "Temps de jeu", l[1]:match("^[^|]*"))
CarnetDeSessionOngletFarm._scripts.OnClick()
l = lignesVisibles()
verifie("onglets, Farm : 4 lignes du farm", 4, #l)
verifie("onglets, Farm : première ligne", "Durée|76 min", l[1])
verifie("onglets : onglet gardé", "farm", db.onglet)
CarnetDeSessionTitre._scripts.OnClick()
verifie("onglets replié : une ligne", 30, F._e.h)
verifie("onglets replié : onglets cachés", false, CarnetDeSessionOngletFarm._e.visible)
CarnetDeSessionTitre._scripts.OnClick()
CarnetDeSessionOngletPerso._scripts.OnClick()
verifie("onglets : retour au personnage", 5, #lignesVisibles())

-- Séparés : comme avant, et Butin rapide reprend son cadre.
carnet("reunir non")
verifie("non : titre d'avant", "Carnet de session", titre())
verifie("non : largeur d'avant", 230, F._e.l)
verifie("non : hauteur d'avant", 121, F._e.h)
verifie("non : 5 lignes, aucun farm", 5, #lignesVisibles())
verifie("non : zone du titre inactive", false, CarnetDeSessionTitre._e.visible)
verifie("non : Butin rapide reprend son cadre", false, dernierCache())
-- Même avec « replié » gardé dans le réglage, le cadre séparé reste entier.
db.replie = true
carnet("reunir non")
verifie("non : jamais replié", 121, F._e.h)
db.replie = false
carnet("reunir un")
verifie("retour à un : le cadre est de nouveau caché chez Butin", true, dernierCache())
verifie("retour à un : 10 lignes", 10, #lignesVisibles())
sorties = {}
carnet("reunir")
verifie("/carnet reunir : dit la présentation", true, sorties[1]:find("un seul cadre", 1, true) ~= nil)
carnet("reunir nimportequoi")
verifie("/carnet reunir inconnu : réglage inchangé", "un", db.reunir)
db.reunir = "abîmé"
verifie("réglage abîmé : vaut un", "un", ns.modePresentation(db.reunir))
db.reunir = "un"

-- La croix passe par les mêmes réglages que la case « Afficher la fenêtre ».
local croix = F.fermerHabille
croix._scripts.OnClick()
verifie("croix : cadre masqué", false, F._e.visible)
verifie("croix : Butin rapide reprend son cadre", false, dernierCache())
carnet("")
verifie("rouvert : cadre visible", true, F._e.visible)
verifie("rouvert : le farm est de nouveau chez nous", true, dernierCache())

-- Butin rapide prévient : le Carnet reprend les nouvelles lignes.
bilanFaux.lignes[1] = { libelle = "Durée", valeur = "80 min", texte = "" }
CarnetDeSession_MajFarm()
verifie("MajFarm : nouvelle valeur affichée", "Durée|80 min", lignesVisibles()[7])
local n = #appelsCache
CarnetDeSession_MajFarm()
verifie("MajFarm : pas de demande de cache répétée", n, #appelsCache)

-- Carnet coupé : plus rien à montrer, Butin rapide reprend son cadre.
db.actif = false
CarnetDeSession_MajFarm()
verifie("carnet coupé : Butin rapide reprend son cadre", false, dernierCache())
db.actif = true
CarnetDeSession_MajFarm()
verifie("carnet réactivé : cadre caché chez Butin", true, dernierCache())

-- Butin rapide sans bilan (la fonction rend nil) : seulement les lignes du Carnet, pas d'onglet Farm.
local rendre = nil
function ButinRapide_LignesBilan() return rendre end
CarnetDeSession_MajFarm()
verifie("bilan coupé : 5 lignes, pas de partie Farm", 5, #lignesVisibles())
verifie("bilan coupé : Butin rapide garde son cadre", false, dernierCache())
carnet("reunir onglets")
verifie("bilan coupé, onglets : aucun onglet", false, CarnetDeSessionOngletPerso._e.visible or CarnetDeSessionOngletFarm._e.visible)
verifie("bilan coupé, onglets : 5 lignes", 5, #lignesVisibles())
db.onglet = "farm"
CarnetDeSession_MajFarm()
verifie("bilan coupé, onglet farm gardé : le personnage s'affiche", 5, #lignesVisibles())
db.onglet = "perso"
CarnetDeSessionTitre._scripts.OnClick()
verifie("bilan coupé, replié : une ligne", 30, F._e.h)
verifie("bilan coupé, replié : pas d'or par heure", "1 h 16", resumeVisible())
CarnetDeSessionTitre._scripts.OnClick()

-- API retirées ou qui plantent : aucune erreur, le Carnet continue seul.
carnet("reunir un")
function ButinRapide_LignesBilan() error("boum") end
local bon = pcall(CarnetDeSession_MajFarm)
verifie("fonction qui plante : pas d'erreur", true, bon)
verifie("fonction qui plante : 5 lignes", 5, #lignesVisibles())
function ButinRapide_LignesBilan() return "n'importe quoi" end
bon = pcall(CarnetDeSession_MajFarm)
verifie("résultat absurde : pas d'erreur", true, bon)
verifie("résultat absurde : 5 lignes", 5, #lignesVisibles())
ButinRapide_LignesBilan, ButinRapide_SetBilanCache = nil, nil
bon = pcall(CarnetDeSession_MajFarm)
verifie("Butin rapide absent : pas d'erreur", true, bon)
bon = pcall(carnet, "reunir onglets")
verifie("Butin rapide absent, onglets : pas d'erreur", true, bon)
verifie("Butin rapide absent : 5 lignes", 5, #lignesVisibles())
bon = pcall(carnet, "reunir non")
verifie("Butin rapide absent, séparés : pas d'erreur", true, bon)
verifie("Butin rapide absent, séparés : 5 lignes", 5, #lignesVisibles())

-- Le code : aucune variable accentuée, aucun tiret cadratin ni demi-cadratin, bonne version.
local function lire(chemin)
  local fichier = assert(io.open(chemin, "rb"))
  local texte = fichier:read("*a")
  fichier:close()
  return texte
end
local code = lire(arg[1])
local accent = false
for ligne in code:gmatch("[^\n]+") do
  local sansTexte = ligne:gsub('"[^"]*"', ""):gsub("%-%-.*$", "")
  if sansTexte:find("\195[\128-\191]") then accent = true end
end
verifie("code : aucune variable accentuée", false, accent)
verifie("code : aucun tiret cadratin ni demi-cadratin", false,
  code:find("\226\128\148", 1, true) ~= nil or code:find("\226\128\147", 1, true) ~= nil)
local toc = lire((arg[1]:gsub("CarnetDeSession%.lua$", "CarnetDeSession.toc")))
verifie("toc : version 0.8.0", true, toc:find("## Version: 0.8.0", 1, true) ~= nil)

io.write(ok and "Tout est bon.\n" or "Il reste des échecs.\n")
os.exit(ok and 0 or 1)
