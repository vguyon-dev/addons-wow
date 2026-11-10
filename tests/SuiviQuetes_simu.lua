-- Simulation hors jeu de Suivi des quêtes : genre d'une quête, tri, regroupement, textes, puis un
-- chargement simulé de l'addon avec de faux cadres (avec et sans les API du jeu).
-- Lancer depuis la racine du dépôt, sous Windows :
--   wsl lua5.1 tests/SuiviQuetes_simu.lua SuiviQuetes/SuiviQuetes.lua
local ok = true
local nbOK = 0
local function verifie(libelle, attendu, obtenu)
  local bon = attendu == obtenu
  ok = ok and bon
  if bon then nbOK = nbOK + 1 end
  io.write(string.format("%s %-62s attendu %s, obtenu %s\n", bon and "OK " or "KO ", libelle, tostring(attendu), tostring(obtenu)))
end

local fichier = arg[1]
local reglagesLua = fichier:gsub("[^/]+$", "Reglages.lua")

local function lire(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end
verifie("Reglages.lua identique dans QuetesAuto", true,
  lire(reglagesLua) == lire((reglagesLua:gsub("SuiviQuetes/Reglages", "QuetesAuto/Reglages"))))
local toc = lire((fichier:gsub("SuiviQuetes%.lua$", "SuiviQuetes.toc")))
verifie("toc : charge Reglages.lua puis SuiviQuetes.lua", true, toc:find("Reglages%.lua%s+SuiviQuetes%.lua") ~= nil)
verifie("toc : sauvegardes déclarées", true, toc:find("## SavedVariables: SuiviQuetesDB", 1, true) ~= nil
  and toc:find("## SavedVariablesPerCharacter: SuiviQuetesPerso", 1, true) ~= nil)
verifie("toc : les deux versions du jeu", true, toc:find("## Interface: 120105, 16001", 1, true) ~= nil)
verifie("toc : fonction du compartiment d'addons", true, toc:find("## AddonCompartmentFunc: SuiviQuetes_OuvrirReglages", 1, true) ~= nil)

-- ============================================================================
-- 1. La logique pure : on charge le fichier sans aucune fonction du jeu.
-- ============================================================================
local ns = {}
assert(loadfile(fichier))("SuiviQuetes", ns)

local ctx = {
  classe = "Paladin", classes = { "Guerrier", "Paladin", "Mage", "Chasseur" },
  metiers = { "Alchimie", "Cuisine", "Travail du cuir" }, manuel = {}, rendreEnHaut = true,
}
local function genre(infos, c) return ns.genreQuete(infos, c or ctx) end

-- Le choix manuel passe avant tout.
verifie("manuel : classe malgré fini et donjon", "classe", genre({ numero = 5, fini = true, tagID = 81 },
  { manuel = { [5] = "classe" }, rendreEnHaut = true }))
verifie("manuel : valeur inconnue ignorée", "aRendre", genre({ numero = 5, fini = true },
  { manuel = { [5] = "bidule" }, rendreEnHaut = true }))
verifie("manuel : autre quête non touchée", "general", genre({ numero = 6 }, { manuel = { [5] = "classe" } }))
-- Fini et l'option.
verifie("fini + option : à rendre", "aRendre", genre({ fini = true, tagID = 81 }))
verifie("fini sans l'option : garde son genre (campagne)", "principal", genre({ fini = true, campaignID = 3 },
  { rendreEnHaut = false }))
verifie("fini sans l'option : garde son genre (général)", "general", genre({ fini = true }, { rendreEnHaut = false }))
verifie("non fini avec l'option : pas à rendre", "general", genre({ fini = false }))
-- Donjon et groupe.
verifie("tag donjon (81)", "donjon", genre({ tagID = 81 }))
verifie("tag raid (62)", "donjon", genre({ tagID = 62 }))
verifie("tag groupe (1)", "donjon", genre({ tagID = 1 }))
verifie("tag héroïque (85)", "donjon", genre({ tagID = 85 }))
verifie("élite", "donjon", genre({ elite = true }))
verifie("groupe conseillé 5", "donjon", genre({ suggestedGroup = 5 }))
verifie("groupe conseillé 2", "donjon", genre({ suggestedGroup = 2 }))
verifie("groupe conseillé 1 : seul", "general", genre({ suggestedGroup = 1 }))
verifie("groupe conseillé 0", "general", genre({ suggestedGroup = 0 }))
verifie("donjon avant JcJ (élite + tag JcJ)", "donjon", genre({ elite = true, tagID = 41 }))
verifie("donjon avant métier", "donjon", genre({ tagID = 81, rubrique = "Cuisine" }))
-- JcJ.
verifie("tag JcJ (41)", "jcj", genre({ tagID = 41 }))
verifie("JcJ avant classe", "jcj", genre({ tagID = 41, rubrique = "Paladin" }))
-- Classe.
verifie("rubrique = ta classe", "classe", genre({ rubrique = "Paladin" }))
verifie("rubrique = ta classe, casse et accents", "classe", genre({ rubrique = "PALADIN" }))
verifie("rubrique = une autre classe", "classe", genre({ rubrique = "Mage" }))
verifie("tag classe (21)", "classe", genre({ tagID = 21 }))
verifie("classe sans la liste : ta classe suffit", "classe", genre({ rubrique = "Paladin" }, { classe = "Paladin" }))
verifie("classe avant métier", "classe", genre({ rubrique = "Paladin", tradeskill = 171 }))
-- Métiers.
verifie("rubrique = un métier", "metiers", genre({ rubrique = "Cuisine" }))
verifie("rubrique = un métier, minuscules", "metiers", genre({ rubrique = "cuisine" }))
verifie("rubrique = un métier à accents", "metiers", genre({ rubrique = "Travail du cuir" }))
verifie("ligne de métier connue du tag", "metiers", genre({ tradeskill = 171 }))
verifie("ligne de métier à zéro : pas un métier", "general", genre({ tradeskill = 0 }))
verifie("rubrique inconnue : général", "general", genre({ rubrique = "Forêt d'Elwynn" }))
-- Principal.
verifie("campagne", "principal", genre({ campaignID = 12 }))
verifie("campagne à zéro", "general", genre({ campaignID = 0 }))
verifie("classification importante (0)", "principal", genre({ classification = 0 }))
verifie("classification légendaire (1)", "principal", genre({ classification = 1 }))
verifie("classification campagne (2)", "principal", genre({ classification = 2 }))
verifie("classification suite de quêtes (6)", "principal", genre({ classification = 6 }))
verifie("classification normale (7, le repli de la doc de Forever)", "general", genre({ classification = 7 }))
verifie("principal avant répétable", "principal", genre({ campaignID = 4, frequency = 1 }))
-- Répétable.
verifie("journalière", "repetable", genre({ frequency = 1 }))
verifie("hebdomadaire", "repetable", genre({ frequency = 2 }))
verifie("classification récurrente (5)", "repetable", genre({ classification = 5 }))
verifie("fréquence 0 : pas répétable", "general", genre({ frequency = 0 }))
-- Général et cas vides.
verifie("rien du tout : général", "general", genre({}))
verifie("infos absentes : général", "general", genre(nil, nil))

-- Les accents en majuscules et la mémoire de sansAccents.
verifie("sansAccents : Ë Ï Ù Ü Œ", "eiuuoe", ns.sansAccents("ËÏÙÜŒ"))
verifie("sansAccents : deuxième appel (mémoire) identique", "eiuuoe", ns.sansAccents("ËÏÙÜŒ"))
verifie("rubrique en majuscules accentuées = métier", "metiers",
  genre({ rubrique = "ÉCHOPPE" }, { metiers = { "Échoppe" } }))

-- Les décalages d'une position suivent l'échelle du panneau.
local dx, dy = ns.decalageEchelle(-30, -60, 1, 1.5)
verifie("échelle : x converti (100 % vers 150 %)", -20, dx)
verifie("échelle : y converti", -40, dy)
dx = ns.decalageEchelle(-30, -60, nil, 1.5)
verifie("échelle : ancienne inconnue, rien ne bouge", -30, dx)

-- La distance.
verifie("distance : 140 m", "140 m", ns.texteDistance(140))
verifie("distance : arrondie", "141 m", ns.texteDistance(140.6))
verifie("distance : zéro", "0 m", ns.texteDistance(0))
verifie("distance : 999 m", "999 m", ns.texteDistance(999))
verifie("distance : 999,6 m passe en km", "1,0 km", ns.texteDistance(999.6))
verifie("distance : 2,6 km, virgule décimale", "2,6 km", ns.texteDistance(2600))
verifie("distance : 12,3 km", "12,3 km", ns.texteDistance(12345))
verifie("distance : inconnue", nil, ns.texteDistance(nil))
verifie("distance : négative", nil, ns.texteDistance(-5))
verifie("distance : texte", nil, ns.texteDistance("12"))
verifie("distance : infinie", nil, ns.texteDistance(math.huge))

-- La couleur de difficulté.
local function couleur(n, j, v) local r, g, b = ns.couleurDifficulte(n, j, v) return r .. "," .. g .. "," .. b end
verifie("couleur : +5 rouge", "1,0.1,0.1", couleur(15, 10))
verifie("couleur : +3 orange", "1,0.5,0.25", couleur(13, 10))
verifie("couleur : +2 jaune", "1,1,0", couleur(12, 10))
verifie("couleur : même niveau jaune", "1,1,0", couleur(10, 10))
verifie("couleur : -2 jaune", "1,1,0", couleur(8, 10))
verifie("couleur : -3 vert", "0.25,0.75,0.25", couleur(7, 10, 8))
verifie("couleur : -8 vert (plage 8)", "0.25,0.75,0.25", couleur(2, 10, 8))
verifie("couleur : -9 gris (plage 8)", "0.5,0.5,0.5", couleur(1, 10, 8))
verifie("couleur : plage de 5, -6 gris", "0.5,0.5,0.5", couleur(4, 10, 5))
verifie("couleur : niveau inconnu blanc", "1,1,1", couleur(nil, 10))

-- La zone.
verifie("zone : le jeu dit oui", true, ns.estIci(true, "Autre", { "Elwynn" }))
verifie("zone : rubrique = nom de la zone", true, ns.estIci(false, "Forêt d'Elwynn", { "Hurlevent", "foret d'elwynn" }))
verifie("zone : autre rubrique", false, ns.estIci(false, "Durotar", { "Forêt d'Elwynn" }))
verifie("zone : rubrique vide", false, ns.estIci(false, nil, { "Forêt d'Elwynn" }))

-- Le tri d'une section.
local function titres(l) local t = {} for _, q in ipairs(l) do t[#t + 1] = q.titre end return table.concat(t, ",") end
verifie("tri : la zone d'abord, puis la distance", "B,A,C", titres(ns.trierQuetes({
  { titre = "A", ici = false, distance = 10 }, { titre = "B", ici = true, distance = 900 }, { titre = "C", ici = false, distance = 50 } })))
verifie("tri : distance croissante, inconnue à la fin", "B,C,A", titres(ns.trierQuetes({
  { titre = "A", ici = true }, { titre = "B", ici = true, distance = 5 }, { titre = "C", ici = true, distance = 80 } })))
verifie("tri : même distance, le niveau", "B,A", titres(ns.trierQuetes({
  { titre = "A", ici = true, distance = 10, niveau = 9 }, { titre = "B", ici = true, distance = 10, niveau = 4 } })))
verifie("tri : même niveau, le titre sans accents", "Écu,Zèbre", titres(ns.trierQuetes({
  { titre = "Zèbre", niveau = 5 }, { titre = "Écu", niveau = 5 } })))
verifie("tri : même titre, le numéro", "2,7", (function()
  local l = ns.trierQuetes({ { titre = "X", numero = 7 }, { titre = "X", numero = 2 } })
  return l[1].numero .. "," .. l[2].numero
end)())
verifie("tri : toutes inconnues, par niveau", "B,A", titres(ns.trierQuetes({
  { titre = "A", niveau = 8 }, { titre = "B", niveau = 3 } })))

-- Le regroupement en sections.
local brut = {
  { titre = "j", genre = "repetable" }, { titre = "g1", genre = "general", niveau = 9 }, { titre = "r", genre = "aRendre" },
  { titre = "g2", genre = "general", niveau = 2 }, { titre = "d", genre = "donjon" }, { titre = "bizarre", genre = "nimporte" },
  { titre = "m", genre = "metiers" }, { titre = "p", genre = "principal" }, { titre = "c", genre = "classe" },
}
local sections = ns.sections(brut)
local noms = {}
for _, s in ipairs(sections) do noms[#noms + 1] = s.genre end
verifie("sections : ordre fixe, JcJ vide absente", "aRendre,principal,general,donjon,classe,metiers,repetable", table.concat(noms, ","))
verifie("sections : genre inconnu rangé dans Général, trié", "bizarre,g2,g1", (function()
  for _, s in ipairs(sections) do if s.genre == "general" then return titres(s.quetes) end end
end)())
verifie("sections : noms affichés", "À rendre|Principal|Général|Donjons et groupe|Classe|Métiers|Journalières et répétables",
  (function() local t = {} for _, s in ipairs(sections) do t[#t + 1] = s.nom end return table.concat(t, "|") end)())
verifie("sections : liste vide, aucune section", 0, #ns.sections({}))
verifie("sections : liste absente, aucune section", 0, #ns.sections(nil))
verifie("sections : une seule, les autres absentes", "jcj", ns.sections({ { titre = "x", genre = "jcj" } })[1].genre)

-- Les autres zones.
verifie("autres zones : option coupée, tout reste", true, ns.garderQuete({ ici = false, genre = "general" }, false))
verifie("autres zones : ici reste", true, ns.garderQuete({ ici = true, genre = "general" }, true))
verifie("autres zones : ailleurs partie", false, ns.garderQuete({ ici = false, genre = "general" }, true))
verifie("autres zones : un donjon reste", true, ns.garderQuete({ ici = false, genre = "donjon" }, true))
verifie("autres zones : une quête à rendre reste", true, ns.garderQuete({ ici = false, genre = "aRendre" }, true))

-- Les objectifs.
local function lignes(q) local t = {} for _, l in ipairs(ns.objectifsAffiches(q)) do t[#t + 1] = (l.fini and "+" or "-") .. l.texte end return table.concat(t, "|") end
verifie("objectifs : un par ligne", "-Loup tué : 0/4|+Peau : 2/2", lignes({ objectifs = {
  { text = "Loup tué : 0/4", finished = false }, { text = "Peau : 2/2", finished = true } } }))
verifie("objectifs : une ligne vide est ignorée", "-Loup tué : 0/4", lignes({ objectifs = {
  { text = "", finished = false }, { text = "Loup tué : 0/4", finished = false } } }))
verifie("objectifs : quête finie, texte du journal", "+À rendre : Retournez voir le garde", lignes({ fini = true,
  texteFin = "  Retournez voir le garde ", objectifs = { { text = "Loup tué : 4/4", finished = true } } }))
verifie("objectifs : quête finie sans texte", "+À rendre", lignes({ fini = true }))
verifie("objectifs : sans objectif, le texte court", "-Trouvez des épices", lignes({ texteCourt = "Trouvez des épices", objectifs = {} }))
verifie("objectifs : les objectifs passent avant le texte court", "-Un : 0/1", lignes({
  texteCourt = "court", objectifs = { { text = "Un : 0/1" } } }))
verifie("objectifs : rien du tout", "", lignes({}))
verifie("texte des objectifs : tiret et vert quand fini", "|cffd8d8d8- A : 0/4|r\n|cff40e040- B : 2/2|r",
  ns.texteObjectifs({ { texte = "A : 0/4", fini = false }, { texte = "B : 2/2", fini = true } }))
verifie("texte des objectifs : liste vide", "", ns.texteObjectifs({}))
verifie("titre : avec le niveau", "[12] Les loups", ns.titreAffiche(12, "Les loups"))
verifie("titre : sans niveau", "Les loups", ns.titreAffiche(nil, "Les loups"))
verifie("titre : niveau zéro", "Les loups", ns.titreAffiche(0, "Les loups"))

-- La place des boutons d'objet.
local p, x, y = ns.positionPorteur(1500, 1800, 800, 1, 1, 36)
verifie("porteur : à gauche, point", "TOPRIGHT", p)
verifie("porteur : à gauche, x", 1494, x)
verifie("porteur : à gauche, y (sous l'en-tête)", 776, y)
p, x, y = ns.positionPorteur(10, 310, 800, 1, 1, 36)
verifie("porteur : pas de place à gauche, à droite", "TOPLEFT", p)
verifie("porteur : à droite, x", 316, x)
p, x, y = ns.positionPorteur(1000, 1300, 500, 0.8, 1, 36)
verifie("porteur : échelle du panneau convertie, x", 794, x)
verifie("porteur : échelle du panneau convertie, y", 376, y)
p = ns.positionPorteur(40, 300, 500, 1, 1, 36)
verifie("porteur : juste la place à gauche (40 = 6 + 36 - 2)", "TOPLEFT", p)
verifie("objet : affiché si la quête n'est pas finie", true, ns.objetAffiche("|Hitem:1|h", false, false))
verifie("objet : caché si finie", false, ns.objetAffiche("|Hitem:1|h", true, false))
verifie("objet : affiché si finie et que l'objet le veut", true, ns.objetAffiche("|Hitem:1|h", true, true))
verifie("objet : sans lien", false, ns.objetAffiche(nil, false, false))
verifie("numéro d'objet d'un lien", 6948, ns.numeroObjet("|cffffffff|Hitem:6948:0:0|h[Pierre]|h|r"))
verifie("numéro d'objet : lien absent", nil, ns.numeroObjet(nil))
verifie("numéro d'objet : lien sans objet", nil, ns.numeroObjet("|Hquest:5|h"))

-- ============================================================================
-- 2. Chargement simulé avec de faux cadres.
-- ============================================================================
local bidon
bidon = function()
  return setmetatable({}, { __index = function() return bidon() end, __call = function() return bidon() end })
end

local imprime = {}
local function lireImprime() return table.concat(imprime, "\n") end
print = function(...)
  local t = {}
  for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end
  imprime[#imprime + 1] = table.concat(t, " ")
end

local toutes, enCombat, file, tickers, appelsJeu
local PROTEGES = { Show = 1, Hide = 1, SetShown = 1, SetPoint = 1, ClearAllPoints = 1, SetAttribute = 1,
  SetSize = 1, SetWidth = 1, SetHeight = 1, SetParent = 1, SetScale = 1 }
local M = {}
local metaF = {}
function metaF.__index(t, k)
  if type(k) ~= "string" or not k:match("^%u") then return nil end
  -- Seul un cadre créé avec BackdropTemplate a SetBackdrop (un cadre simple n'en a pas).
  if (k == "SetBackdrop" or k == "SetBackdropColor" or k == "SetBackdropBorderColor") and not rawget(t, "_fond") then return nil end
  -- Un cadre protégé ne se touche pas en combat : le jeu refuserait.
  if PROTEGES[k] and rawget(t, "_protege") and enCombat then
    return function() error("ADDON_ACTION_BLOCKED " .. k .. " sur " .. tostring(rawget(t, "_nom") or rawget(t, "_type")), 2) end
  end
  return M[k] or function() end
end

local function nouveau(genre, nom, parent, modele)
  local f = setmetatable({ _type = genre, _nom = nom, _parent = parent, _shown = true, _events = {}, _scripts = {},
    _w = 100, _h = 20, _scale = 1, _text = "", _attr = {}, _niveau = 1, _crochets = {} }, metaF)
  toutes[#toutes + 1] = f
  if nom then _G[nom] = f end
  if modele and tostring(modele):find("Backdrop") then f._fond = true end
  if modele and tostring(modele):find("Secure") then
    f._protege = true
    local p = parent
    while p and p._nom ~= "UIParent" do p._protege = true; p = p._parent end
  end
  return f
end

function M.SetSize(s, w, h) s._w, s._h = w, h end
function M.SetWidth(s, w) s._w = w end
function M.SetHeight(s, h) s._h = h end
function M.GetWidth(s) return s._w end
function M.GetHeight(s) return s._h end
function M.GetStringWidth(s) return #s._text * 6 end
function M.GetStringHeight(s)
  local _, n = s._text:gsub("\n", "")
  return 12 * (n + 1)
end
function M.SetText(s, t) s._text = tostring(t == nil and "" or t) end
function M.GetText(s) return s._text end
function M.SetTextColor(s, r, g, b) s._couleur = { r, g, b } end
function M.SetPoint(s, point, rel, relPoint, x, y)
  if type(rel) == "number" then x, y, rel, relPoint = rel, relPoint, nil, nil end
  s._pt = { point, rel, relPoint or point, x or 0, y or 0 }
end
function M.ClearAllPoints(s) s._pt = nil end
function M.GetPoint(s) local p = s._pt or { "CENTER", UIParent, "CENTER", 0, 0 } return p[1], p[2], p[3], p[4], p[5] end
function M.GetLeft(s) return s._gauche or 1500 end
function M.GetRight(s) return s._droite or 1800 end
function M.GetTop(s) return s._haut or 800 end
function M.GetBottom(s) return 300 end
function M.GetCenter() return 500, 400 end
function M.GetEffectiveScale(s) return s._scale end
function M.SetScale(s, v) s._scale = v end
function M.SetAlpha(s, v) s._alpha = v end
function M.GetAlpha(s) return s._alpha or 1 end
function M.GetScale(s) return s._scale end
function M.Show(s) s._shown = true; for _, h in ipairs(s._crochets.Show or {}) do h(s) end end
function M.Hide(s) s._shown = false; for _, h in ipairs(s._crochets.Hide or {}) do h(s) end end
function M.SetShown(s, v) if v then M.Show(s) else M.Hide(s) end end
function M.IsShown(s) return s._shown end
function M.IsVisible(s) return s._shown end
function M.RegisterEvent(s, e) s._events[e] = true end
M.RegisterUnitEvent = M.RegisterEvent
function M.UnregisterEvent(s, e) s._events[e] = nil end
function M.SetScript(s, nom, fn) s._scripts[nom] = fn end
function M.GetScript(s, nom) return s._scripts[nom] end
function M.CreateFontString(s) return nouveau("FontString", nil, s) end
function M.CreateTexture(s) return nouveau("Texture", nil, s) end
function M.SetAttribute(s, k, v) s._attr[k] = v end
function M.GetAttribute(s, k) return s._attr[k] end
function M.GetParent(s) return s._parent end
function M.GetName(s) return s._nom end
function M.SetFrameLevel(s, n) s._niveau = n end
function M.GetFrameLevel(s) return s._niveau end
function M.GetVerticalScroll(s) return s._defil or 0 end
function M.SetVerticalScroll(s, v) s._defil = v end
function M.GetVerticalScrollRange() return 0 end
function M.StartMoving(s) s._deplace = true end
function M.StopMovingOrSizing(s) s._deplace = false end
function M.IsObjectType() return false end
function M.GetThumbTexture() return bidon() end
function M.EnableMouse(s, v) s._souris = v end

local function installer(avecAPI)
  toutes, enCombat, file, tickers = {}, false, {}, {}
  appelsJeu = { suivi = {}, retire = {}, journal = {} }
  imprime = {}
  _G.ValentinAddons, _G.ValentinAddonsReglages, _G.ValentinAddonsMinimap = nil, nil, nil
  _G.SuiviQuetesDB, _G.SuiviQuetesPerso, _G.SuiviQuetesCadre = nil, nil, nil
  _G.ObjectiveTrackerFrame = nil
  for i = 1, 8 do _G["SuiviQuetesObjet" .. i] = nil end
  _G.SuiviQuetesPorteur, _G.SuiviQuetesMenu = nil, nil
  _G.UIParent = nouveau("Frame", "UIParent")
  UIParent._h, UIParent._w = 1080, 1920
  _G.GameTooltip = nouveau("GameTooltip", "GameTooltip")
  _G.Minimap = nouveau("Frame", "Minimap")
  _G.WorldMapFrame = nil
  _G.CreateFrame = function(genre, nom, parent, modele) return nouveau(genre, nom, parent or UIParent, modele) end
  _G.UISpecialFrames, _G.SlashCmdList = {}, {}
  _G.tinsert = table.insert
  _G.strtrim = function(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
  _G.hooksecurefunc = function(t, nom, fn)
    t._crochets[nom] = t._crochets[nom] or {}
    table.insert(t._crochets[nom], fn)
  end
  _G.C_Timer = {
    After = function(_, fn) file[#file + 1] = fn end,
    NewTicker = function(_, fn) tickers[#tickers + 1] = fn return {} end,
  }
  _G.InCombatLockdown = function() return enCombat end
  _G.IsShiftKeyDown = function() return false end
  _G.GetCursorPosition = function() return 600, 500 end
  _G.UnitName = function() return "Testeur" end
  _G.GetRealmName = function() return "Royaume" end
  _G.UnitLevel = function() return 10 end
  _G.UnitClass = function() return "Paladin", "PALADIN" end
  _G.GetQuestGreenRange = function() return 8 end
  _G.IsInInstance = function() return _G.EN_INSTANCE and true or false, "none" end
  _G.GetRealZoneText = function() return "Forêt d'Elwynn" end
  _G.GetZoneText = function() return "Forêt d'Elwynn" end
  _G.LOCALIZED_CLASS_NAMES_MALE = { PALADIN = "Paladin", MAGE = "Mage", WARRIOR = "Guerrier" }
  _G.LOCALIZED_CLASS_NAMES_FEMALE = { PALADIN = "Paladine", MAGE = "Mage", WARRIOR = "Guerrière" }
  _G.UNKNOWNOBJECT = "Inconnu"
  _G.BackdropTemplateMixin = {}
  _G.PlaySound, _G.HideUIPanel, _G.ClearCursor = function() end, function() end, function() end
  _G.GetCursorInfo = function() end
  _G.EN_INSTANCE = false
  for _, n in ipairs({ "C_QuestLog", "C_SuperTrack", "C_QuestInfoSystem", "GetQuestLogSpecialItemInfo",
    "GetQuestLogSpecialItemCooldown", "GetQuestLogCompletionText", "GetQuestLogQuestText", "QuestMapFrame_OpenToQuestDetails",
    "GetProfessions", "GetProfessionInfo", "GetNumClasses", "GetClassInfo" }) do _G[n] = nil end
  if not avecAPI then return end

  -- Le journal de quêtes simulé.
  local J = {}
  J.journal = {
    { isHeader = true, title = "Forêt d'Elwynn" },
    { questID = 100, title = "Loups de la forêt", level = 5, difficultyLevel = 5, isOnMap = true },
    { questID = 101, title = "Lettre pour Hurlevent", level = 6, difficultyLevel = 6, isOnMap = true },
    { questID = 102, title = "Le grand projet", level = 8, difficultyLevel = 8, isOnMap = true, campaignID = 7 },
    { questID = 111, title = "Sans genre", level = 3, difficultyLevel = 3, isOnMap = true },
    { isHeader = true, title = "Paladin" },
    { questID = 103, title = "Épreuve du paladin", level = 10, difficultyLevel = 10 },
    { isHeader = true, title = "Donjons" },
    { questID = 104, title = "Les Mortemines", level = 15, difficultyLevel = 15 },
    { isHeader = true, title = "Cuisine" },
    { questID = 105, title = "Épices rares", level = 5, difficultyLevel = 5 },
    { isHeader = true, title = "Journalières" },
    { questID = 106, title = "Corvée du jour", level = 10, difficultyLevel = 10, frequency = 1 },
    { questID = 108, title = "Cachée", level = 10, difficultyLevel = 10, isHidden = true },
    { questID = 109, title = "Tâche", level = 10, difficultyLevel = 10, isTask = true },
    { questID = 110, title = "Monde", level = 10, difficultyLevel = 10 },
  }
  for i, e in ipairs(J.journal) do e.questLogIndex = i; e.isHeader = e.isHeader or false end
  -- Une quête sous une zone repliée : absente du journal affiché, retrouvée par son numéro.
  J.cachees = { [107] = { questID = 107, title = "Message lointain", level = 40, difficultyLevel = 40, questLogIndex = 40, isHeader = false },
                [200] = { title = "Terres lointaines", isHeader = true, questLogIndex = 39 } }
  J.suivies = { 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111 }
  J.tags = { [104] = { tagID = 81, tagName = "Donjon" } }
  J.finies = { [101] = true }
  J.objectifs = {
    [100] = { { text = "Loup tué : 0/4", finished = false, numFulfilled = 0, numRequired = 4 } },
    [102] = { { text = "Parler au garde", finished = false }, { text = "Clé : 1/1", finished = true } },
    [106] = { { text = "Eau : 1/2", finished = false } },
  }
  J.distances = { [100] = 140, [101] = 2600, [102] = 900, [103] = 50, [104] = 5000, [106] = 80, [111] = 300 }
  J.objets = { [106] = { "|cffffffff|Hitem:6948:0:0|h[Pierre de foyer]|h|r", "Interface\\Icons\\INV_Misc_Rune_01", 1, false } }
  J.super = 0
  J.selection = 0
  J.courts = { [105] = "Trouvez des épices" }
  _G.JEU = J
  local function parId(id)
    for _, e in ipairs(J.journal) do if e.questID == id then return e end end
    return J.cachees[id]
  end
  _G.C_QuestLog = {
    GetNumQuestLogEntries = function() return #J.journal, 12 end,
    GetInfo = function(i)
      if J.journal[i] then return J.journal[i] end
      for _, e in pairs(J.cachees) do if e.questLogIndex == i then return e end end
    end,
    GetNumQuestWatches = function() return #J.suivies end,
    GetQuestIDForQuestWatchIndex = function(i) return J.suivies[i] end,
    GetQuestTagInfo = function(id) return J.tags[id] end,
    IsComplete = function(id) return J.finies[id] == true end,
    GetQuestObjectives = function(id) return J.objectifs[id] or {} end,
    GetDistanceSqToQuest = function(id) local d = J.distances[id] if d then return d * d, true end end,
    GetLogIndexForQuestID = function(id) local e = parId(id) return e and e.questLogIndex end,
    GetHeaderIndexForQuest = function(id) if id == 107 then return 39 end end,
    IsWorldQuest = function(id) return id == 110 end,
    RemoveQuestWatch = function(id) appelsJeu.retire[#appelsJeu.retire + 1] = id end,
    GetSelectedQuest = function() return J.selection end,
    SetSelectedQuest = function(id) J.selection = id end,
  }
  _G.C_SuperTrack = {
    GetSuperTrackedQuestID = function() return J.super end,
    SetSuperTrackedQuestID = function(id) J.super = id; appelsJeu.suivi[#appelsJeu.suivi + 1] = id end,
  }
  _G.C_QuestInfoSystem = { GetQuestClassification = function() return 7 end }
  _G.GetQuestLogSpecialItemInfo = function(index)
    local e = J.journal[index]
    local o = e and J.objets[e.questID]
    if o then return o[1], o[2], o[3], o[4] end
  end
  _G.GetQuestLogSpecialItemCooldown = function() return 0, 0, 1 end
  _G.GetQuestLogCompletionText = function(index)
    if J.journal[index] and J.journal[index].questID == 101 then return "Retournez voir le garde" end
  end
  _G.GetQuestLogQuestText = function(index) local e = J.journal[index] return "description", e and J.courts[e.questID] end
  _G.QuestMapFrame_OpenToQuestDetails = function(id) appelsJeu.journal[#appelsJeu.journal + 1] = id end
  _G.GetNumClasses = function() return 2 end
  _G.GetClassInfo = function(i) return ({ "Guerrier", "Paladin" })[i], "X", i end
  _G.GetProfessions = function() return 1, 2 end
  _G.GetProfessionInfo = function(i) return ({ "Alchimie", "Cuisine" })[i] end
  _G.ObjectiveTrackerFrame = nouveau("Frame", "ObjectiveTrackerFrame", UIParent)
  ObjectiveTrackerFrame._protege = true
end

local function declencher(evenement, ...)
  for _, f in ipairs(toutes) do
    if f._events[evenement] and f._scripts.OnEvent then f._scripts.OnEvent(f, evenement, ...) end
  end
end
local function avancer()
  local garde = 0
  while #file > 0 and garde < 1000 do garde = garde + 1; table.remove(file, 1)() end
end
local function tictac() for _, f in ipairs(tickers) do f() end end

local function chargerAddon()
  local n = {}
  assert(loadfile(reglagesLua))("SuiviQuetes", n)
  assert(loadfile(fichier))("SuiviQuetes", n)
  return n
end

local function demarrer()
  local n = chargerAddon()
  declencher("ADDON_LOADED", "SuiviQuetes")
  declencher("PLAYER_ENTERING_WORLD")
  avancer()
  return n
end

-- Ce qui est affiché : sections et quêtes dans l'ordre de leurs positions.
local function affichage()
  local l = {}
  for _, f in ipairs(toutes) do
    if f._shown and f._pt then
      if rawget(f, "genre") and f.nom and f.nombre then
        l[#l + 1] = { y = -f._pt[5], texte = "S:" .. f.nom._text .. "(" .. f.nombre._text .. ")" }
      elseif rawget(f, "numero") and f.titre then
        l[#l + 1] = { y = -f._pt[5], texte = "Q:" .. f.titre._text }
      end
    end
  end
  table.sort(l, function(a, b) return a.y < b.y end)
  local t = {}
  for _, e in ipairs(l) do t[#t + 1] = e.texte end
  return table.concat(t, " | ")
end

local function ligneDe(numero)
  for _, f in ipairs(toutes) do
    if rawget(f, "numero") == numero and f._shown then return f end
  end
end
local function sectionDe(genreCle)
  for _, f in ipairs(toutes) do
    if rawget(f, "genre") == genreCle and f._shown and f.nom then return f end
  end
end
local function boutonTexte(texte)
  for _, f in ipairs(toutes) do
    if f._type == "Button" and f._text == texte then return f end
  end
end
local function ligneMenuTexte(texte)
  for _, f in ipairs(toutes) do
    if f._type == "Button" and rawget(f, "texte") and f.texte._text:find(texte, 1, true) and f._shown
       and f._parent and f._parent._nom == "SuiviQuetesMenu" then return f end
  end
end

-- ---------------------------------------------------------------------------
-- 2a. Avec toutes les API
-- ---------------------------------------------------------------------------
installer(true)
local n = demarrer()
local cadre = SuiviQuetesCadre
verifie("chargement : aucune erreur retenue", nil, n.derniereErreur)
verifie("chargement : le cadre existe", true, cadre ~= nil)
verifie("chargement : global de la commande", "function", type(SuiviQuetes_OuvrirReglages))
verifie("chargement : /sq et /suivi", "/sq,/suivi", SLASH_SUIVIQUETES1 .. "," .. SLASH_SUIVIQUETES2)
verifie("panneau affiché", true, cadre._shown)
verifie("panneau : largeur par défaut", 300, cadre._w)
verifie("panneau : à droite sous la minimap", "TOPRIGHT,-240", cadre._pt[1] .. "," .. cadre._pt[5])

local attendu = table.concat({
  "S:À rendre(1)", "Q:[6] Lettre pour Hurlevent",
  "S:Principal(1)", "Q:[8] Le grand projet",
  "S:Général(3)", "Q:[5] Loups de la forêt", "Q:[3] Sans genre", "Q:[40] Message lointain",
  "S:Donjons et groupe(1)", "Q:[15] Les Mortemines",
  "S:Classe(1)", "Q:[10] Épreuve du paladin",
  "S:Métiers(1)", "Q:[5] Épices rares",
  "S:Journalières et répétables(1)", "Q:[10] Corvée du jour",
}, " | ")
verifie("sections et quêtes dans l'ordre", attendu, affichage())
verifie("en-tête : le compte", "Quêtes (9)", (function()
  for _, f in ipairs(toutes) do if f._type == "FontString" and f._text:match("^Quêtes %(") then return f._text end end
end)())
verifie("quête cachée, tâche, quête mondiale : absentes", nil, ligneDe(108) or ligneDe(109) or ligneDe(110))
verifie("quête sous une zone repliée : retrouvée", "[40] Message lointain", ligneDe(107) and ligneDe(107).titre._text)
verifie("distance : 140 m", "140 m", ligneDe(100).dist._text)
verifie("distance : 2,6 km", "2,6 km", ligneDe(101).dist._text)
verifie("distance : inconnue, vide", "", ligneDe(107).dist._text)
verifie("objectifs d'une quête", "|cffd8d8d8- Loup tué : 0/4|r", ligneDe(100).obj._text)
verifie("objectifs : fini en vert", "|cffd8d8d8- Parler au garde|r\n|cff40e040- Clé : 1/1|r", ligneDe(102).obj._text)
verifie("quête finie : « À rendre : … »", "|cff40e040- À rendre : Retournez voir le garde|r", ligneDe(101).obj._text)
verifie("quête sans objectif : le texte court du journal", "|cffd8d8d8- Trouvez des épices|r", ligneDe(105).obj._text)
verifie("pastille : ? pour une quête finie", "?", ligneDe(101).pastille._text)
verifie("pastille : … sinon", "…", ligneDe(100).pastille._text)
verifie("couleur : quête de niveau 40 pour un niveau 10 en rouge", "1,0.1,0.1", table.concat(ligneDe(107).titre._couleur, ","))
verifie("couleur : même niveau en jaune", "1,1,0", table.concat(ligneDe(103).titre._couleur, ","))
verifie("sélection du journal restaurée", 0, JEU.selection)
verifie("la quête choisie n'a pas encore de fond doré", false, ligneDe(100).fond._shown)

-- Aucun cadre protégé sous le panneau.
local protegeSousCadre = false
for _, f in ipairs(toutes) do
  local p = f
  while p do
    if p == cadre and f._protege then protegeSousCadre = true end
    p = p._parent
  end
end
verifie("aucun cadre protégé sous le panneau", false, protegeSousCadre)
verifie("le panneau lui-même n'est pas protégé", nil, cadre._protege)

-- Le suivi du jeu.
verifie("suivi du jeu caché", false, ObjectiveTrackerFrame._shown)
ObjectiveTrackerFrame:Show()
verifie("suivi du jeu : le jeu le remontre, on le recache", false, ObjectiveTrackerFrame._shown)

-- Les boutons d'objet.
local bouton = SuiviQuetesObjet1
verifie("objet : un bouton créé", true, bouton ~= nil)
verifie("objet : macro de clic gauche", "macro", bouton and bouton._attr.type1)
verifie("objet : /use item:NUMERO", "/use item:6948", bouton and bouton._attr.macrotext1)
verifie("objet : bouton visible", true, bouton and bouton._shown)
verifie("objet : enfant du porteur", "SuiviQuetesPorteur", bouton and bouton._parent._nom)
verifie("objet : porteur enfant de UIParent", "UIParent", SuiviQuetesPorteur._parent._nom)
verifie("objet : porteur accroché à l'écran, pas au panneau", "UIParent", SuiviQuetesPorteur._pt[2]._nom)
verifie("objet : porteur à gauche du panneau", "TOPRIGHT," .. 1494 .. "," .. 776,
  SuiviQuetesPorteur._pt[1] .. "," .. SuiviQuetesPorteur._pt[4] .. "," .. SuiviQuetesPorteur._pt[5])
verifie("objet : bouton accroché au porteur", "SuiviQuetesPorteur", bouton and bouton._pt[2]._nom)
verifie("objet : un seul bouton", nil, SuiviQuetesObjet2)

-- Clics.
local l100, l101 = ligneDe(100), ligneDe(101)
l100._scripts.OnClick(l100, "LeftButton")
verifie("clic : choisit la quête", 100, appelsJeu.suivi[#appelsJeu.suivi])
avancer()
verifie("la quête choisie a son fond doré", true, ligneDe(100).fond._shown)
verifie("une autre quête n'a pas de fond doré", false, ligneDe(101).fond._shown)
l100._scripts.OnClick(l100, "LeftButton")
verifie("clic sur la quête choisie : ouvre le journal", 100, appelsJeu.journal[#appelsJeu.journal])
verifie("clic sur la quête choisie : ne rechoisit pas", 1, #appelsJeu.suivi)
IsShiftKeyDown = function() return true end
l101._scripts.OnClick(l101, "LeftButton")
verifie("Maj + clic : ne plus suivre", 101, appelsJeu.retire[#appelsJeu.retire])
verifie("Maj + clic : ne choisit pas", 1, #appelsJeu.suivi)
IsShiftKeyDown = function() return false end

-- Le menu du clic droit.
local l103 = ligneDe(103)
l103._scripts.OnClick(l103, "RightButton")
local menu = SuiviQuetesMenu
verifie("menu : affiché", true, menu._shown)
verifie("menu : en-tête = titre de la quête", "Épreuve du paladin", ligneMenuTexte("Épreuve du paladin").texte._text)
verifie("menu : Automatique est coché", true, ligneMenuTexte("Automatique").texte._text:find("> ", 1, true) ~= nil)
verifie("menu : entrées proposées", true, ligneMenuTexte("Principal") and ligneMenuTexte("Général") and ligneMenuTexte("Donjons et groupe")
  and ligneMenuTexte("Classe") and ligneMenuTexte("Métiers") and ligneMenuTexte("Ne plus suivre") and ligneMenuTexte("Ouvrir dans le journal") and true)
local choix = ligneMenuTexte("Principal")
choix._scripts.OnClick(choix)
verifie("menu : choix manuel gardé par numéro", "principal", SuiviQuetesDB.genres[103])
verifie("menu : fermé après le choix", false, menu._shown)
avancer()
verifie("menu : la quête change de section", true, affichage():find("S:Principal(2) | Q:[8] Le grand projet | Q:[10] Épreuve du paladin", 1, true) ~= nil)
verifie("menu : la section Classe disparaît (vide)", nil, affichage():find("S:Classe", 1, true))
l103 = ligneDe(103)
l103._scripts.OnClick(l103, "RightButton")
local coche = ligneMenuTexte("Principal")
verifie("menu : le choix courant est coché", true, coche.texte._text:find("> ", 1, true) ~= nil)
local auto = ligneMenuTexte("Automatique")
auto._scripts.OnClick(auto)
verifie("menu : Automatique efface le choix", nil, SuiviQuetesDB.genres[103])
avancer()
verifie("menu : retour dans Classe", true, affichage():find("S:Classe(1) | Q:[10] Épreuve du paladin", 1, true) ~= nil)
l103 = ligneDe(103)
l103._scripts.OnClick(l103, "RightButton")
ligneMenuTexte("Ne plus suivre")._scripts.OnClick(ligneMenuTexte("Ne plus suivre"))
verifie("menu : ne plus suivre", 103, appelsJeu.retire[#appelsJeu.retire])
l103._scripts.OnClick(l103, "RightButton")
ligneMenuTexte("Ouvrir dans le journal")._scripts.OnClick(ligneMenuTexte("Ouvrir dans le journal"))
verifie("menu : ouvrir dans le journal", 103, appelsJeu.journal[#appelsJeu.journal])
l103._scripts.OnClick(l103, "RightButton")
local rideau
for _, f in ipairs(toutes) do if f._type == "Button" and f._scripts.OnClick and f._parent == UIParent and not rawget(f, "numero") and f._shown then rideau = f end end
rideau._scripts.OnClick(rideau)
verifie("menu : un clic à côté le ferme", false, menu._shown)

-- Replier une section.
local sec = sectionDe("general")
sec._scripts.OnClick(sec)
verifie("section repliée : gardée pour le personnage", true, SuiviQuetesPerso.replie.general)
verifie("section repliée : ses quêtes disparaissent, le nombre reste", true,
  affichage():find("S:Général(3) | S:Donjons", 1, true) ~= nil)
verifie("section repliée : une quête de Général n'est plus affichée", nil, ligneDe(100))
boutonTexte("Tout déplier")._scripts.OnClick()
verifie("tout déplier : plus rien de replié", nil, next(SuiviQuetesPerso.replie))
-- Une section repliée n'a plus de bouton d'objet (la quête 106 est dans « Journalières »).
local secRep = sectionDe("repetable")
verifie("objet : visible avant de replier sa section", true, SuiviQuetesObjet1 and SuiviQuetesObjet1._shown)
secRep._scripts.OnClick(secRep)
verifie("section repliée : le bouton d'objet de sa quête part", false, SuiviQuetesObjet1._shown)
secRep = sectionDe("repetable")
secRep._scripts.OnClick(secRep)
verifie("section dépliée : le bouton d'objet revient", true, SuiviQuetesObjet1._shown)
verifie("tout déplier : les quêtes reviennent", true, ligneDe(100) ~= nil)

-- Réglages qui s'appliquent sans /reload.
local r = n.reglages
r.changer("largeur", 400)
avancer()
verifie("réglage : largeur 400", 400, cadre._w)
r.changer("taille", 80)
verifie("réglage : taille 80 %", 0.8, cadre._scale)
r.changer("uneLigne", true)
avancer()
verifie("réglage : une ligne, sans objectifs", "", ligneDe(100).obj._text)
r.changer("uneLigne", false)
r.changer("distance", false)
avancer()
verifie("réglage : sans distance", "", ligneDe(100).dist._text)
r.changer("distance", true)
r.changer("rendreEnHaut", false)
avancer()
verifie("réglage : sans « À rendre » en haut, la quête finie retrouve son genre", nil, affichage():find("S:À rendre", 1, true))
r.changer("rendreEnHaut", true)
r.changer("cacherAutresZones", true)
avancer()
verifie("réglage : autres zones cachées (ici, donjon, à rendre restent)", true,
  ligneDe(100) ~= nil and ligneDe(104) ~= nil and ligneDe(101) ~= nil and ligneDe(103) == nil and ligneDe(107) == nil)
r.changer("cacherAutresZones", false)
r.changer("toutesLesQuetes", true)
JEU.suivies = { 100 }
avancer()
verifie("réglage : toutes les quêtes du journal", true, ligneDe(103) ~= nil and ligneDe(106) ~= nil)
r.changer("toutesLesQuetes", false)
avancer()
verifie("réglage : retour aux seules quêtes suivies", nil, ligneDe(103))
JEU.suivies = { 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111 }
r.changer("fondSombre", true)
verifie("réglage : fond sombre", true, cadre.fondHabille ~= nil and cadre.fondHabille._shown)
r.changer("fondSombre", false)
verifie("réglage : fond coupé", false, cadre.fondHabille._shown)
r.changer("boutonsObjets", false)
avancer()
verifie("réglage : sans boutons d'objet", false, SuiviQuetesObjet1._shown)
r.changer("boutonsObjets", true)
avancer()
verifie("réglage : boutons d'objet de retour", true, SuiviQuetesObjet1._shown)

-- Déplacement du panneau.
local entete
for _, f in ipairs(toutes) do if f._type == "Button" and f._scripts.OnDragStart and f._parent == cadre then entete = f end end
imprime = {}
entete._scripts.OnDragStart()
verifie("glisser l'en-tête : le panneau se déplace", true, cadre._deplace)
entete._scripts.OnDragStop()
verifie("glisser : position gardée", true, type(SuiviQuetesDB.position) == "table")
verifie("glisser : le cadre des objets suit", "TOPRIGHT", SuiviQuetesPorteur._pt[1])
r.changer("verrouiller", true)
cadre._deplace = nil
entete._scripts.OnDragStart()
verifie("verrouillé : le panneau ne bouge pas", nil, cadre._deplace)
r.changer("verrouiller", false)
enCombat = true
entete._scripts.OnDragStart()
verifie("combat : déplacement refusé", nil, cadre._deplace)
verifie("combat : un message court", true, lireImprime():find("combat", 1, true) ~= nil)
enCombat = false
SlashCmdList.SUIVIQUETES("centre")
verifie("/sq centre : position d'origine", nil, SuiviQuetesDB.position)
verifie("/sq centre : replacé", "TOPRIGHT,-240", cadre._pt[1] .. "," .. cadre._pt[5])
-- Changer la taille ne déplace pas le panneau à l'écran.
SuiviQuetesDB.position = { "TOPRIGHT", "TOPRIGHT", -30, -60, 1 }
r.changer("taille", 150)
verifie("taille 150 % : décalage converti pour rester en place", "-20,-40", cadre._pt[4] .. "," .. cadre._pt[5])
r.changer("taille", 100)
verifie("taille de nouveau 100 % : retour au décalage d'origine", "-30,-60", cadre._pt[4] .. "," .. cadre._pt[5])
SlashCmdList.SUIVIQUETES("centre")

-- Le combat : on redessine, mais on ne touche à rien de protégé.
local nbRafraichi = 0
enCombat = true
JEU.objets[100] = { "|Hitem:7005:0|h[Peau]|h", "Interface\\Icons\\INV_Misc_Rune_02", 1, false }
JEU.distances[100] = 5
JEU.objectifs[100] = { { text = "Loup tué : 3/4", finished = false } }
declencher("QUEST_LOG_UPDATE")
local okCombat, erreurCombat = pcall(avancer)
verifie("combat : un rafraîchissement ne lève aucune erreur", true, okCombat)
if not okCombat then io.write("   " .. tostring(erreurCombat) .. "\n") end
verifie("combat : aucune erreur retenue", nil, n.derniereErreur)
verifie("combat : le panneau se redessine quand même", "|cffd8d8d8- Loup tué : 3/4|r", ligneDe(100) and ligneDe(100).obj._text)
verifie("combat : les boutons d'objet attendent", "/use item:6948", SuiviQuetesObjet1._attr.macrotext1)
verifie("combat : pas de second bouton créé", nil, SuiviQuetesObjet2)
r.changer("cacherSuiviJeu", false)
verifie("combat : le suivi du jeu n'est pas touché", false, ObjectiveTrackerFrame._shown)
verifie("combat : ni caché ni montré de force (pas d'alpha non plus, il est déjà caché)", nil, ObjectiveTrackerFrame._alpha)
-- Le jeu remontre son suivi en combat : on n'y touche pas non plus (le crochet attend la fin du combat).
ObjectiveTrackerFrame._protege = nil
ObjectiveTrackerFrame:Show()
ObjectiveTrackerFrame._protege = true
r.changer("cacherSuiviJeu", true)
-- En combat, le jeu rappelle Show : on le rend transparent (jamais de Hide), la suite attend la fin du combat.
verifie("combat : le suivi remontré par le jeu est rendu transparent", 0, ObjectiveTrackerFrame._alpha)
verifie("combat : sans Hide (il reste affiché)", true, ObjectiveTrackerFrame._shown)
enCombat = false
declencher("PLAYER_REGEN_ENABLED")
avancer()
verifie("fin du combat : les boutons d'objet sont refaits (2)", "/use item:7005", SuiviQuetesObjet1._attr.macrotext1)
verifie("fin du combat : second bouton", "/use item:6948", SuiviQuetesObjet2 and SuiviQuetesObjet2._attr.macrotext1)
verifie("fin du combat : le suivi du jeu est recaché", false, ObjectiveTrackerFrame._shown)
verifie("fin du combat : opacité rendue (il sera visible quand on le remontrera)", 1, ObjectiveTrackerFrame._alpha)
-- Mode d'édition de l'interface : le suivi du jeu n'est pas recaché.
_G.EditModeManagerFrame = { IsEditModeActive = function() return true end }
ObjectiveTrackerFrame:Show()
verifie("mode d'édition : le suivi du jeu reste affiché", true, ObjectiveTrackerFrame._shown)
_G.EditModeManagerFrame = nil
ObjectiveTrackerFrame:Show()
verifie("hors mode d'édition : recaché", false, ObjectiveTrackerFrame._shown)
-- Un objet qui part pendant le combat.
enCombat = true
JEU.objets[100] = nil
declencher("QUEST_LOG_UPDATE")
verifie("combat : retirer un objet ne plante pas", true, pcall(avancer))
verifie("combat : le bouton reste jusqu'à la fin du combat", true, SuiviQuetesObjet2._shown)
enCombat = false
declencher("PLAYER_REGEN_ENABLED")
avancer()
verifie("fin du combat : le bouton en trop disparaît", false, SuiviQuetesObjet2._shown)

-- La quête de l'objet est finie : l'objet s'efface (sauf s'il demande à rester).
JEU.finies[106] = true
declencher("QUEST_LOG_UPDATE")
avancer()
verifie("quête finie : son objet n'est plus proposé", false, SuiviQuetesObjet1._shown)
JEU.objets[106][4] = true
declencher("QUEST_LOG_UPDATE")
avancer()
verifie("quête finie, objet qui reste : proposé", true, SuiviQuetesObjet1._shown)
JEU.finies[106] = nil

-- Les distances sont relues toutes les 2 secondes.
JEU.distances[103] = 7
tictac()
verifie("ticker : la distance est relue", "7 m", ligneDe(103).dist._text)
-- Le garde du ticker : pas d'appel si l'option est coupée.
r.changer("distance", false)
JEU.distances[103] = 9
tictac()
verifie("ticker : option coupée, pas de relecture", "", ligneDe(103).dist._text)
r.changer("distance", true)

-- Une instance : le suivi du jeu revient et on s'efface.
EN_INSTANCE = true
declencher("ZONE_CHANGED_NEW_AREA")
avancer()
verifie("instance : le suivi du jeu revient", true, ObjectiveTrackerFrame._shown)
verifie("instance : le panneau s'efface", false, cadre._shown)
verifie("instance : les boutons d'objet aussi", false, SuiviQuetesObjet1._shown)
EN_INSTANCE = false
declencher("ZONE_CHANGED_NEW_AREA")
avancer()
verifie("retour dehors : suivi du jeu caché", false, ObjectiveTrackerFrame._shown)
verifie("retour dehors : panneau de retour", true, cadre._shown)

-- Couper l'addon, puis le rallumer.
r.changer("actif", false)
avancer()
verifie("addon coupé : suivi du jeu remontré", true, ObjectiveTrackerFrame._shown)
verifie("addon coupé : panneau caché", false, cadre._shown)
verifie("addon coupé : boutons d'objet cachés", false, SuiviQuetesObjet1._shown)
ObjectiveTrackerFrame:Show()
verifie("addon coupé : le crochet ne le recache pas", true, ObjectiveTrackerFrame._shown)
r.changer("actif", true)
avancer()
verifie("addon rallumé : suivi du jeu recaché", false, ObjectiveTrackerFrame._shown)
verifie("addon rallumé : panneau de retour", true, cadre._shown)

-- Un suivi du jeu que le joueur a caché lui-même : on ne le remontre pas.
r.changer("cacherSuiviJeu", false)
verifie("option décochée : suivi du jeu remontré", true, ObjectiveTrackerFrame._shown)
ObjectiveTrackerFrame:Hide()
r.changer("cacherSuiviJeu", false)
verifie("option décochée de nouveau : pas remontré (caché par le joueur)", false, ObjectiveTrackerFrame._shown)
r.changer("cacherSuiviJeu", true)

-- Les commandes.
imprime = {}
SlashCmdList.SUIVIQUETES("genre")
local sortie = lireImprime()
verifie("/sq genre : une ligne par quête", true, sortie:find("Loups de la forêt (n° 100)", 1, true) ~= nil
  and sortie:find("Les Mortemines (n° 104)", 1, true) ~= nil)
verifie("/sq genre : ce que dit le jeu", true, sortie:find("rubrique=Forêt d'Elwynn, tagID=-, tagName=-, classification=7", 1, true) ~= nil)
verifie("/sq genre : le tag du donjon", true, sortie:find("tagID=81, tagName=Donjon", 1, true) ~= nil)
verifie("/sq genre : le genre retenu", true, sortie:find("-> Donjons et groupe", 1, true) ~= nil)
verifie("/sq genre : la quête finie", true, sortie:find("fini=oui -> À rendre", 1, true) ~= nil)
-- Avec « cacher les autres zones », /sq genre montre quand même toutes les quêtes suivies.
r.changer("cacherAutresZones", true)
imprime = {}
SlashCmdList.SUIVIQUETES("genre")
verifie("/sq genre : sans les filtres d'affichage", true, lireImprime():find("Message lointain (n° 107)", 1, true) ~= nil)
r.changer("cacherAutresZones", false)
imprime = {}
imprime = {}
SlashCmdList.SUIVIQUETES("aide")
verifie("/sq aide : donne les commandes", true, lireImprime():find("/sq genre", 1, true) ~= nil and lireImprime():find("/sq centre", 1, true) ~= nil)
imprime = {}
SlashCmdList.SUIVIQUETES("n'importe quoi")
verifie("commande inconnue : un message", true, lireImprime():find("inconnue", 1, true) ~= nil)
verifie("aucune erreur retenue sur toute la simulation", nil, n.derniereErreur)

-- ---------------------------------------------------------------------------
-- 2b. Sans aucune API de quêtes : aucune erreur, le panneau reste simplement vide.
-- ---------------------------------------------------------------------------
installer(false)
local n2 = demarrer()
declencher("QUEST_LOG_UPDATE")
declencher("SUPER_TRACKING_CHANGED")
declencher("PLAYER_REGEN_ENABLED")
declencher("BAG_UPDATE_COOLDOWN")
avancer()
tictac()
verifie("sans API : aucune erreur retenue", nil, n2.derniereErreur)
verifie("sans API : panneau vide donc caché", false, SuiviQuetesCadre._shown)
verifie("sans API : pas de bouton d'objet", nil, SuiviQuetesObjet1)
verifie("sans API : /sq genre dit qu'il n'y a rien", true, (function()
  imprime = {}
  SlashCmdList.SUIVIQUETES("genre")
  return lireImprime():find("aucune quête", 1, true) ~= nil
end)())
verifie("sans API : changer un réglage ne plante pas", true, pcall(n2.reglages.changer, "largeur", 350))

-- ---------------------------------------------------------------------------
-- 2c. Des API qui manquent une à une : la ligne concernée est absente, rien ne plante.
-- ---------------------------------------------------------------------------
local manques = {
  { "C_SuperTrack", function() C_SuperTrack = nil end },
  { "C_QuestInfoSystem", function() C_QuestInfoSystem = nil end },
  { "GetQuestTagInfo", function() C_QuestLog.GetQuestTagInfo = nil end },
  { "GetDistanceSqToQuest", function() C_QuestLog.GetDistanceSqToQuest = nil end },
  { "GetQuestObjectives", function() C_QuestLog.GetQuestObjectives = nil end },
  { "IsComplete", function() C_QuestLog.IsComplete = nil end },
  { "GetHeaderIndexForQuest", function() C_QuestLog.GetHeaderIndexForQuest = nil end },
  { "GetLogIndexForQuestID", function() C_QuestLog.GetLogIndexForQuestID = nil end },
  { "SetSelectedQuest", function() C_QuestLog.SetSelectedQuest = nil end },
  { "RemoveQuestWatch", function() C_QuestLog.RemoveQuestWatch = nil end },
  { "GetQuestLogSpecialItemInfo", function() GetQuestLogSpecialItemInfo = nil end },
  { "GetQuestLogCompletionText", function() GetQuestLogCompletionText = nil end },
  { "GetQuestLogQuestText", function() GetQuestLogQuestText = nil end },
  { "QuestMapFrame_OpenToQuestDetails", function() QuestMapFrame_OpenToQuestDetails = nil end },
  { "ObjectiveTrackerFrame", function() ObjectiveTrackerFrame = nil end },
  { "GetProfessions", function() GetProfessions = nil end },
  { "GetQuestGreenRange", function() GetQuestGreenRange = nil end },
  { "IsInInstance", function() IsInInstance = nil end },
  { "UnitClass", function() UnitClass = nil end },
  { "hooksecurefunc", function() hooksecurefunc = nil end },
  { "LOCALIZED_CLASS_NAMES", function() LOCALIZED_CLASS_NAMES_MALE = nil; LOCALIZED_CLASS_NAMES_FEMALE = nil end },
  { "GetQuestLogSpecialItemCooldown", function() GetQuestLogSpecialItemCooldown = nil end },
  { "un journal qui répond n'importe quoi", function()
      C_QuestLog.GetInfo = function() return "pas une table" end
      C_QuestLog.GetQuestObjectives = function() return "pas une liste" end
      C_QuestLog.GetQuestTagInfo = function() return 42 end
    end },
}
for _, m in ipairs(manques) do
  installer(true)
  m[2]()
  local nm = demarrer()
  local okM, err = pcall(function()
    declencher("QUEST_LOG_UPDATE")
    declencher("PLAYER_REGEN_ENABLED")
    avancer()
    tictac()
    local l = ligneDe(100)
    if l then l._scripts.OnClick(l, "LeftButton"); l._scripts.OnClick(l, "LeftButton"); l._scripts.OnClick(l, "RightButton") end
    avancer()
  end)
  verifie("API manquante : " .. m[1] .. " : aucune erreur", true, okM and nm.derniereErreur == nil)
  if not okM then io.write("   " .. tostring(err) .. "\n") end
  if nm.derniereErreur then io.write("   " .. nm.derniereErreur .. "\n") end
end

-- Quelques sorties précises quand une API manque.
installer(true)
C_QuestLog.GetDistanceSqToQuest = nil
demarrer()
verifie("sans distance : la colonne est vide", "", ligneDe(100).dist._text)
installer(true)
GetQuestLogCompletionText = nil
demarrer()
verifie("sans texte de fin : « À rendre » seul", "|cff40e040- À rendre|r", ligneDe(101).obj._text)
installer(true)
C_QuestLog.GetQuestTagInfo = nil
demarrer()
verifie("sans tag : le donjon tombe dans Général", true, affichage():find("Q:[15] Les Mortemines", 1, true) ~= nil
  and affichage():find("S:Donjons", 1, true) == nil)

print = io.write and function(...) io.write(table.concat({ ... }, " "), "\n") end or print
io.write(string.format("%d vérifications OK\n", nbOK))
-- Quête de métier reconnue par le texte de ses objectifs (relevé en jeu : Forever ne donne pas d'étiquette)
do
  local M = { "Secourisme", "Cuisine", "Pêche", "Forge" }
  local function egal(nom, attendu, obtenu)
    if attendu ~= obtenu then print("ECHEC  " .. nom .. " : attendu " .. tostring(attendu) .. ", obtenu " .. tostring(obtenu)); os.exit(1) end
    print("OK  " .. nom)
  end
  egal("métier : compétence en secourisme", true, ns.parleDeMetier("Atteindre une compétence de 20 en secourisme", M))
  egal("métier : nom de métier sans le mot compétence", false, ns.parleDeMetier("Apporter la caisse à la forge", M))
  egal("métier : compétence sans métier connu", false, ns.parleDeMetier("Atteindre une compétence de 20 en escalade", M))
  egal("métier : texte vide", false, ns.parleDeMetier("", M))
  egal("genre : objectif de métier -> Métiers", "metiers", ns.genreQuete({ rubrique = "Campement", texte = "Atteindre une compétence de 20 en secourisme" }, { metiers = M }))
  egal("genre : quête ordinaire -> Général", "general", ns.genreQuete({ rubrique = "Marche de l'Ouest", texte = "Dynamite basique : 0/10" }, { metiers = M }))
end

if ok then io.write("Tout est bon.\n") end
os.exit(ok and 0 or 1)
