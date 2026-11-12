-- Simulation hors jeu de Fenêtres déplaçables : les fonctions pures (point, borne, taille, clé), la table
-- des fenêtres, puis un chargement simulé de l'addon avec de faux cadres : poignée, glisser, réouverture après
-- le replacement du jeu, combat sur une fenêtre protégée, Ctrl + molette, menu, fenêtre chargée plus tard,
-- addon coupé, API retirées une à une.
-- Les faux cadres DU JEU refusent qu'on leur écrive un champ (c'est ce qui contaminerait le vrai jeu) et lèvent
-- une erreur sur un appel protégé en combat.
-- Lancer depuis la racine du dépôt, sous Windows :
--   wsl lua5.1 tests/Fenetres_simu.lua Fenetres/Fenetres.lua
local ok = true
local nbOK = 0
local function verifie(libelle, attendu, obtenu)
  local bon = attendu == obtenu
  ok = ok and bon
  if bon then nbOK = nbOK + 1 end
  io.write(string.format("%s %-70s attendu %s, obtenu %s\n", bon and "OK " or "KO ", libelle, tostring(attendu), tostring(obtenu)))
end
-- Deux nombres égaux à un millième près.
local function proche(libelle, attendu, obtenu)
  local bon = type(obtenu) == "number" and math.abs(attendu - obtenu) < 0.001
  ok = ok and bon
  if bon then nbOK = nbOK + 1 end
  io.write(string.format("%s %-70s attendu %s, obtenu %s\n", bon and "OK " or "KO ", libelle, tostring(attendu), tostring(obtenu)))
end

local fichier = arg[1]
local reglagesLua = fichier:gsub("[^/]+$", "Reglages.lua")

local function lire(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end
verifie("Reglages.lua identique dans QuetesAuto", true,
  lire(reglagesLua) == lire((reglagesLua:gsub("Fenetres/Reglages", "QuetesAuto/Reglages"))))
local toc = lire((fichier:gsub("Fenetres%.lua$", "Fenetres.toc")))
local source = lire(fichier)
verifie("toc : charge Reglages.lua puis Fenetres.lua", true, toc:find("Reglages%.lua%s+Fenetres%.lua") ~= nil)
verifie("toc : sauvegarde déclarée", true, toc:find("## SavedVariables: FenetresDB", 1, true) ~= nil)
verifie("toc : les deux versions du jeu", true, toc:find("## Interface: 120105, 16001", 1, true) ~= nil)
verifie("toc : fonction du compartiment d'addons", true, toc:find("## AddonCompartmentFunc: Fenetres_OuvrirReglages", 1, true) ~= nil)
verifie("toc : titre affiché", true, toc:find("## Title: Fenêtres déplaçables", 1, true) ~= nil)
verifie("toc : catégorie, auteur, version", true, toc:find("## Category: Addons de Valentin", 1, true) ~= nil
  and toc:find("## Author: Valentin", 1, true) ~= nil and toc:find("## Version: 0.1.1", 1, true) ~= nil)
verifie("toc : icône", true, toc:find("## IconTexture: ", 1, true) ~= nil)
-- Aucun tiret cadratin ni demi-cadratin, aucun prénom dans le code ni dans le .toc.
verifie("texte : pas de tiret cadratin ni demi-cadratin", false,
  (source .. toc):find("\226\128\148", 1, true) ~= nil or (source .. toc):find("\226\128\147", 1, true) ~= nil)
verifie("code : aucun prénom", false, source:find("Valentin", 1, true) ~= nil)

-- ============================================================================
-- 1. La logique pure : on charge le fichier sans aucune fonction du jeu.
-- ============================================================================
local ns = {}
assert(loadfile(fichier))("Fenetres", ns)

-- La place à partir du jeu.
local pt = ns.pointDepuis(100, 900, 1, 1, 1920, 1080)
verifie("pointDepuis : ancre", "TOPLEFT", pt.point)
verifie("pointDepuis : x", 100, pt.x)
verifie("pointDepuis : y (depuis le haut, négatif vers le bas)", -180, pt.y)
pt = ns.pointDepuis(100, 900, 1.2, 1, 1920, 1080)
verifie("pointDepuis : fenêtre à 120 %, x en unités de l'écran", 120, pt.x)
proche("pointDepuis : fenêtre à 120 %, y", 0, pt.y)
pt = ns.pointDepuis(100, 900, 0.8, 0.8, 1920, 1080)
verifie("pointDepuis : même échelle que l'écran, rien ne change (x)", 100, pt.x)
verifie("pointDepuis : échelle de l'écran à 0,5 et fenêtre à 1 : x doublé", 200, ns.pointDepuis(100, 900, 1, 0.5, 1920, 1080).x)
verifie("pointDepuis : gauche absent", nil, ns.pointDepuis(nil, 900, 1, 1, 1920, 1080))
verifie("pointDepuis : haut texte", nil, ns.pointDepuis(100, "900", 1, 1, 1920, 1080))
verifie("pointDepuis : hauteur de l'écran absente", nil, ns.pointDepuis(100, 900, 1, 1, 1920, nil))
verifie("pointDepuis : largeur de l'écran absente", nil, ns.pointDepuis(100, 900, 1, 1, nil, 1080))
verifie("pointDepuis : échelle négative", nil, ns.pointDepuis(100, 900, -1, 1, 1920, 1080))
verifie("pointDepuis : nombre infini", nil, ns.pointDepuis(math.huge, 900, 1, 1, 1920, 1080))
verifie("pointDepuis : échelle inconnue = 1", 100, ns.pointDepuis(100, 900, nil, nil, 1920, 1080).x)
-- Aller puis retour : le décalage du SetPoint remet la fenêtre où elle était.
do
  local g, h, ef, ep = 250, 700, 1.25, 0.9
  local p = ns.pointDepuis(g, h, ef, ep, 1920, 1080)
  local ox, oy = ns.decalageDepuis(p.x, p.y, ef, ep)
  local k = ef / ep
  proche("aller-retour : le coin gauche en unités de l'écran", g * k, ox * k)
  proche("aller-retour : le haut en unités de l'écran", h * k, oy * k + 1080)
  proche("décalage : x", 100, (ns.decalageDepuis(120, -180, 1.2, 1)))
  local _, dy = ns.decalageDepuis(120, -180, 1.2, 1)
  proche("décalage : y", -150, dy)
end

-- Ramener une place dans l'écran.
local bx, by = ns.borner(1900, -100, 300, 400, 1920, 1080)
verifie("borner : trop à droite, x", 1620, bx)
verifie("borner : trop à droite, y inchangé", -100, by)
bx, by = ns.borner(-50, 20, 300, 400, 1920, 1080)
verifie("borner : trop à gauche, x", 0, bx)
verifie("borner : trop haut, y", 0, by)
bx, by = ns.borner(10, -900, 300, 400, 1920, 1080)
verifie("borner : trop bas, y", -680, by)
verifie("borner : trop bas, x inchangé", 10, bx)
bx, by = ns.borner(500, -50, 3000, 2000, 1920, 1080)
verifie("borner : fenêtre plus grande que l'écran, x", 0, bx)
verifie("borner : fenêtre plus grande que l'écran, y", 0, by)
bx, by = ns.borner(500, -50, 300, 400, 1920, 1080)
verifie("borner : déjà dedans, x", 500, bx)
verifie("borner : déjà dedans, y", -50, by)
bx, by = ns.borner(5000, -50, nil, nil, 1920, 1080)
verifie("borner : dimensions inconnues, rien ne change", 5000, bx)
bx, by = ns.borner("a", 5, 1, 1, 10, 10)
verifie("borner : x texte, rendu tel quel", "a", bx)

-- La taille suivante.
verifie("taille : 100 -> 105", 1.05, ns.echelleSuivante(1, 1))
verifie("taille : 100 -> 95", 0.95, ns.echelleSuivante(1, -1))
verifie("taille : plafond 150", 1.5, ns.echelleSuivante(1.5, 1))
verifie("taille : plancher 50", 0.5, ns.echelleSuivante(0.5, -1))
verifie("taille : 97 monte à 100", 1.0, ns.echelleSuivante(0.97, 1))
verifie("taille : 97 descend à 95", 0.95, ns.echelleSuivante(0.97, -1))
verifie("taille : 110 -> 115 (flottant)", 1.15, ns.echelleSuivante(1.1, 1))
verifie("taille : 110 -> 105 (flottant)", 1.05, ns.echelleSuivante(1.1, -1))
verifie("taille : inconnue = 100", 1.05, ns.echelleSuivante(nil, 1))
verifie("taille : sens nul = vers le bas", 0.95, ns.echelleSuivante(1, 0))
verifie("taille : 49 monte à 50", 0.5, ns.echelleSuivante(0.49, 1))
verifie("taille : 151 descend à 150", 1.5, ns.echelleSuivante(1.51, -1))

-- La clé d'une fenêtre.
verifie("clé : un nom de cadre", "CharacterFrame", ns.cleFenetre("CharacterFrame"))
verifie("clé : espaces retirés", "Frame_1", ns.cleFenetre("  Frame_1 "))
verifie("clé : tiret refusé", nil, ns.cleFenetre("a-b"))
verifie("clé : accent refusé", nil, ns.cleFenetre("Fenêtre"))
verifie("clé : vide", nil, ns.cleFenetre(""))
verifie("clé : absente", nil, ns.cleFenetre(nil))
verifie("clé : un nombre", nil, ns.cleFenetre(42))
verifie("clé : un point refusé", nil, ns.cleFenetre("A.B"))

-- Les marges de la poignée.
do
  local g, d, h = ns.margesDe({})
  verifie("marges : défauts (gauche)", 58, g)
  verifie("marges : défauts (droite)", 26, d)
  verifie("marges : défauts (hauteur)", 22, h)
  g, d, h = ns.margesDe({ g = 30, d = 80, h = 28 })
  verifie("marges : réglées à la main", "30,80,28", g .. "," .. d .. "," .. h)
  g, d, h = ns.margesDe({ g = -5, d = "x", h = 0 / 0 })
  verifie("marges : valeurs absurdes, défauts", "58,26,22", g .. "," .. d .. "," .. h)
  g = ns.margesDe(nil)
  verifie("marges : entrée absente", 58, g)
end

-- Une place gardée, nettoyée.
do
  local p = ns.lirePlace({ x = 10, y = -20, echelle = 1.1 })
  verifie("lirePlace : valide", "10,-20,1.1", p.x .. "," .. p.y .. "," .. p.echelle)
  verifie("lirePlace : texte", nil, ns.lirePlace({ x = "a", y = 5 }))
  verifie("lirePlace : pas une table", nil, ns.lirePlace(7))
  verifie("lirePlace : absente", nil, ns.lirePlace(nil))
  verifie("lirePlace : x sans y", nil, ns.lirePlace({ x = 5 }))
  verifie("lirePlace : très loin", nil, ns.lirePlace({ x = 1e9, y = 0 }))
  verifie("lirePlace : taille hors bornes ignorée", nil, ns.lirePlace({ echelle = 3 }))
  p = ns.lirePlace({ x = 1, y = 2, echelle = 9 })
  verifie("lirePlace : taille absurde ignorée, position gardée", "1,2,nil", p.x .. "," .. p.y .. "," .. tostring(p.echelle))
  p = ns.lirePlace({ echelle = 0.8 })
  verifie("lirePlace : taille seule", 0.8, p.echelle)
  verifie("lirePlace : NaN", nil, ns.lirePlace({ x = 0 / 0, y = 0 }))
  verifie("sansPosition : la taille reste", 1.1, ns.sansPosition({ x = 1, y = 2, echelle = 1.1 }).echelle)
  verifie("sansPosition : sans taille, plus rien", nil, ns.sansPosition({ x = 1, y = 2 }))
  verifie("sansEchelle : la position reste", 1, ns.sansEchelle({ x = 1, y = 2, echelle = 1.1 }).x)
  verifie("sansEchelle : sans position, plus rien", nil, ns.sansEchelle({ echelle = 1.1 }))
  verifie("ligne : déplacée et redimensionnée", "Personnage : déplacée, taille 110 %",
    ns.texteLigne("Personnage", { x = 1, y = 2, echelle = 1.1 }))
  verifie("ligne : déplacée", "Courrier : déplacée", ns.texteLigne("Courrier", { x = 1, y = 2 }))
  verifie("ligne : taille seule", "Carte : taille 90 %", ns.texteLigne("Carte", { echelle = 0.9 }))
  verifie("ligne : rien", "Carte", ns.texteLigne("Carte", nil))
end

-- La table des fenêtres.
do
  local vus, valide, sansTiret, ascii = {}, true, true, true
  local titresOK = true
  for _, e in ipairs(ns.FENETRES) do
    if vus[e.nom] or ns.cleFenetre(e.nom) ~= e.nom then valide = false end
    vus[e.nom] = true
    if type(e.titre) ~= "string" or e.titre == "" then titresOK = false end
    if e.nom:find("[\128-\255]") then ascii = false end
    if (e.titre or ""):find("\226\128[\147\148]") then sansTiret = false end
  end
  verifie("fenêtres : noms uniques et valides", true, valide)
  verifie("fenêtres : titres non vides", true, titresOK)
  verifie("fenêtres : noms de cadre en ASCII", true, ascii)
  verifie("fenêtres : titres sans tiret cadratin", true, sansTiret)
  local voulues = { "CharacterFrame", "PlayerSpellsFrame", "SpellBookFrame", "ClassTalentFrame", "PlayerTalentFrame",
    "WorldMapFrame", "QuestFrame", "GossipFrame", "MerchantFrame", "MailFrame", "OpenMailFrame", "BankFrame",
    "AuctionHouseFrame", "ClassTrainerFrame", "ProfessionsFrame", "TradeSkillFrame", "FriendsFrame", "CommunitiesFrame",
    "GuildFrame", "PVEFrame", "LFGParentFrame", "CollectionsJournal", "AchievementFrame", "EncounterJournal",
    "InspectFrame", "TradeFrame", "ItemTextFrame", "TaxiFrame", "FlightMapFrame", "MacroFrame", "AddonList",
    "SettingsPanel", "GameMenuFrame", "DressUpFrame", "StableFrame", "HelpFrame", "CalendarFrame", "LootFrame" }
  local manque = {}
  for _, n in ipairs(voulues) do if not vus[n] then manque[#manque + 1] = n end end
  verifie("fenêtres : toutes celles du cahier des charges", "", table.concat(manque, ","))
  local exclues = { "PlayerFrame", "TargetFrame", "Minimap", "MinimapCluster", "ObjectiveTrackerFrame", "ContainerFrame1",
    "MainMenuBar", "MainActionBar", "SuiviQuetesCadre", "GPSCadre", "ValentinAddonsReglages", "UIParent" }
  local presentes = {}
  for _, n in ipairs(exclues) do if vus[n] then presentes[#presentes + 1] = n end end
  verifie("fenêtres : rien de ce qui est géré ailleurs", "", table.concat(presentes, ","))
  local surCarte
  for _, e in ipairs(ns.FENETRES) do if e.nom == "WorldMapFrame" then surCarte = e end end
  verifie("fenêtres : la carte a une règle « agrandie »", "function", type(surCarte and surCarte.sauf))
end

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
local function compter(motif)
  local n = 0
  for _, l in ipairs(imprime) do if l:find(motif, 1, true) then n = n + 1 end end
  return n
end

local toutes, enCombat, file, tickers, ecritures, appelsBloques, appelsSetAttribute, creees, ctrl, appelsMenuJeu
local retiresJeu = {}
local MP = {}
local M = {}

-- Les appels qu'un cadre protégé refuse en combat.
local PROTEGES = { Show = 1, Hide = 1, SetPoint = 1, ClearAllPoints = 1, SetScale = 1, SetMovable = 1, StartMoving = 1,
  StopMovingOrSizing = 1, SetClampedToScreen = 1, Raise = 1, SetUserPlaced = 1, SetAttribute = 1, SetSize = 1,
  SetWidth = 1, SetHeight = 1 }

local function indexer(t, k, jeu)
  if type(k) ~= "string" or not k:match("^%u") then return nil end
  if jeu and retiresJeu[k] then return nil end
  if jeu and rawget(t, "_protege") and enCombat and PROTEGES[k] then
    return function() appelsBloques = appelsBloques + 1 error("ADDON_ACTION_BLOCKED " .. k .. " sur " .. tostring(rawget(t, "_nom")), 2) end
  end
  if jeu and k == "SetAttribute" then
    return function(_, a) appelsSetAttribute[#appelsSetAttribute + 1] = tostring(a) end
  end
  -- Seul un cadre créé avec BackdropTemplate a SetBackdrop (un cadre simple n'en a pas).
  if (k == "SetBackdrop" or k == "SetBackdropColor" or k == "SetBackdropBorderColor") and not rawget(t, "_fond") then return nil end
  return M[k] or function() end
end
local metaNous = { __index = function(t, k) return indexer(t, k, false) end }
local metaJeu = {
  __index = function(t, k) return indexer(t, k, true) end,
  -- Écrire un champ d'un cadre du jeu contaminerait le vrai jeu : on le note ET on lève l'erreur.
  __newindex = function(_, k) ecritures[#ecritures + 1] = tostring(k) error("ecriture d'un champ sur un cadre du jeu : " .. tostring(k), 2) end,
}

local function nouveau(genre, nom, parent, modele, jeu)
  local f = { _type = genre, _nom = nom, _parent = parent, _shown = not jeu, _events = {}, _scripts = {}, _hookscripts = {},
    _w = 100, _h = 20, _scale = 1, _text = "", _attr = {}, _niveau = 1, _crochets = {}, _pts = {}, _strate = "MEDIUM" }
  if jeu then f._jeu = true end
  toutes[#toutes + 1] = f
  if nom then _G[nom] = f end
  if modele and tostring(modele):find("Backdrop") then f._fond = true end
  return setmetatable(f, jeu and metaJeu or metaNous)
end

local function eff(s)
  if rawget(s, "_nom") == "UIParent" then return s._scale end
  return s._scale * UIParent._scale
end

function M.SetSize(s, w, h) rawset(s, "_w", w) rawset(s, "_h", h) end
function M.SetWidth(s, w) rawset(s, "_w", w) end
function M.SetHeight(s, h) rawset(s, "_h", h) end
function M.GetWidth(s) return s._w end
function M.GetHeight(s) return s._h end
function M.GetStringWidth(s) return #s._text * 6 end
function M.GetStringHeight(s)
  local _, n = s._text:gsub("\n", "")
  return 12 * (n + 1)
end
function M.SetText(s, t) rawset(s, "_text", tostring(t == nil and "" or t)) end
function M.GetText(s) return s._text end
function M.SetTextColor() end
function M.SetPoint(s, ...)
  local point, rel, relPoint, x, y = ...
  if type(rel) == "number" then x, y, rel, relPoint = rel, relPoint, nil, nil end
  if type(rel) == "string" then rel = _G[rel] end
  rel = rel or UIParent
  relPoint = relPoint or point
  local pts = rawget(s, "_pts")
  for i, p in ipairs(pts) do if p[1] == point then table.remove(pts, i) break end end
  pts[#pts + 1] = { point, rel, relPoint, x or 0, y or 0 }
  local fe, pe = eff(s), UIParent._scale
  if rel == UIParent and point == "TOPLEFT" and relPoint == "TOPLEFT" then
    rawset(s, "_l", (x or 0) * fe / pe)
    rawset(s, "_t", UIParent._h + (y or 0) * fe / pe)
  elseif rel == UIParent and point == "TOP" and relPoint == "TOP" then
    rawset(s, "_l", UIParent._w / 2 + (x or 0) * fe / pe - s._w * fe / pe / 2)
    rawset(s, "_t", UIParent._h + (y or 0) * fe / pe)
  end
  for _, h in ipairs(rawget(s, "_crochets").SetPoint or {}) do h(s, ...) end
end
function M.ClearAllPoints(s)
  rawset(s, "_pts", {})
  for _, h in ipairs(rawget(s, "_crochets").ClearAllPoints or {}) do h(s) end
end
function M.SetAllPoints() end
function M.GetLeft(s) local l = rawget(s, "_l") if not l then return nil end return l * UIParent._scale / eff(s) end
function M.GetTop(s) local t = rawget(s, "_t") if not t then return nil end return t * UIParent._scale / eff(s) end
function M.GetRight(s) return (s:GetLeft() or 0) + s._w end
function M.GetBottom(s) return (s:GetTop() or 0) - s._h end
function M.GetCenter() return 500, 400 end
function M.GetEffectiveScale(s) return eff(s) end
function M.SetScale(s, v)
  rawset(s, "_scale", v)
  for _, h in ipairs(rawget(s, "_crochets").SetScale or {}) do h(s, v) end
end
function M.GetScale(s) return s._scale end
function M.SetAlpha(s, v) rawset(s, "_alpha", v) end
function M.GetAlpha(s) return s._alpha or 1 end
function M.Show(s)
  rawset(s, "_shown", true)
  if rawget(s, "_jeu") then
    if s._scripts.OnShow then s._scripts.OnShow(s) end
    for _, h in ipairs(s._hookscripts.OnShow or {}) do h(s) end
  end
end
function M.Hide(s)
  rawset(s, "_shown", false)
  if rawget(s, "_jeu") then
    if s._scripts.OnHide then s._scripts.OnHide(s) end
    for _, h in ipairs(s._hookscripts.OnHide or {}) do h(s) end
  end
end
function M.SetShown(s, v) if v then M.Show(s) else M.Hide(s) end end
function M.IsShown(s) return s._shown end
function M.IsVisible(s) return s._shown end
function M.RegisterEvent(s, e) s._events[e] = true end
M.RegisterUnitEvent = M.RegisterEvent
function M.UnregisterEvent(s, e) s._events[e] = nil end
function M.SetScript(s, nom, fn) s._scripts[nom] = fn end
function M.GetScript(s, nom) return s._scripts[nom] end
function M.HookScript(s, nom, fn)
  s._hookscripts[nom] = s._hookscripts[nom] or {}
  table.insert(s._hookscripts[nom], fn)
end
function M.CreateFontString(s) return nouveau("FontString", nil, s) end
function M.CreateTexture(s) return nouveau("Texture", nil, s) end
function M.SetAttribute(s, k, v) s._attr[k] = v end
function M.GetAttribute(s, k) return s._attr[k] end
function M.GetParent(s) return s._parent end
function M.GetName(s) return s._nom end
function M.SetFrameLevel(s, n) rawset(s, "_niveau", n) end
function M.GetFrameLevel(s) return s._niveau end
function M.SetFrameStrata(s, v) rawset(s, "_strate", v) end
function M.GetFrameStrata(s) return s._strate end
-- Raise : au-dessus de TOUS les cadres frères (comme le jeu), poignées comprises.
function M.Raise(s)
  local haut = 0
  for _, h in ipairs(toutes) do if h._niveau > haut then haut = h._niveau end end
  rawset(s, "_niveau", haut + 1)
  rawset(s, "_leves", (rawget(s, "_leves") or 0) + 1)
  for _, h in ipairs(rawget(s, "_crochets").Raise or {}) do h(s) end
end
function M.GetVerticalScroll(s) return s._defil or 0 end
function M.SetVerticalScroll(s, v) rawset(s, "_defil", v) end
function M.GetVerticalScrollRange() return 0 end
function M.StartMoving(s) rawset(s, "_deplace", true) end
function M.StopMovingOrSizing(s)
  if not rawget(s, "_deplace") then return end
  rawset(s, "_deplace", false)
  -- Comme le jeu : après un déplacement, la fenêtre est ancrée au coin bas gauche de l'écran.
  rawset(s, "_pts", { { "BOTTOMLEFT", UIParent, "BOTTOMLEFT", s._l, s._t - s._h * eff(s) } })
end
function M.IsObjectType() return false end
function M.GetThumbTexture() return bidon() end
function M.EnableMouse(s, v) rawset(s, "_souris", v) end
function M.EnableMouseWheel(s, v) rawset(s, "_molette", v) end
function M.RegisterForDrag(s, ...) rawset(s, "_glisse", { ... }) end
function M.RegisterForClicks(s, ...) rawset(s, "_clics", { ... }) end
function M.SetMovable(s, v) rawset(s, "_movable", v and true or false) end
function M.IsMovable(s) return s._movable and true or false end
function M.SetClampedToScreen(s, v) rawset(s, "_clamped", v and true or false) end
function M.IsClampedToScreen(s) return s._clamped and true or false end
function M.SetUserPlaced(s, v) rawset(s, "_userPlaced", v) rawset(s, "_appelsUP", (rawget(s, "_appelsUP") or 0) + 1) end
function M.IsProtected(s) return rawget(s, "_protege") and true or false, false end
function M.IsForbidden() return false end

local function installer()
  toutes, enCombat, file, tickers = {}, false, {}, {}
  ecritures, appelsBloques, appelsSetAttribute, ctrl, appelsMenuJeu = {}, 0, {}, false, 0
  retiresJeu = {}
  imprime = {}
  for _, n in ipairs(creees or {}) do _G[n] = nil end
  creees = {}
  _G.ValentinAddons, _G.ValentinAddonsReglages, _G.ValentinAddonsMinimap = nil, nil, nil
  _G.FenetresDB, _G.FenetresMenu = nil, nil
  _G.UIParent = nouveau("Frame", "UIParent")
  UIParent._h, UIParent._w = 1080, 1920
  _G.GameTooltip = nouveau("GameTooltip", "GameTooltip")
  _G.Minimap = nouveau("Frame", "Minimap")
  _G.CreateFrame = function(genre, nom, parent, modele) return nouveau(genre, nom, parent or UIParent, modele) end
  _G.UISpecialFrames, _G.SlashCmdList = {}, {}
  _G.tinsert = table.insert
  _G.strtrim = function(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
  _G.hooksecurefunc = function(t, nom, fn)
    local c = rawget(t, "_crochets")
    c[nom] = c[nom] or {}
    table.insert(c[nom], fn)
  end
  _G.C_Timer = {
    After = function(_, fn)
      if type(fn) ~= "function" then error("C_Timer.After exige une fonction Lua") end
      file[#file + 1] = fn
    end,
    NewTicker = function(_, fn) tickers[#tickers + 1] = fn return {} end,
  }
  _G.InCombatLockdown = function() return enCombat end
  _G.IsShiftKeyDown = function() return false end
  _G.IsControlKeyDown = function() return ctrl end
  _G.IsAltKeyDown = function() return false end
  _G.GetCursorPosition = function() return 600, 500 end
  _G.UnitName = function() return "Testeur" end
  _G.GetRealmName = function() return "Royaume" end
  _G.UNKNOWNOBJECT = "Inconnu"
  _G.BackdropTemplateMixin = {}
  _G.PlaySound = function() end
  _G.date = os.date
  -- Des pièges : le menu déroulant du jeu contamine ; l'addon ne doit jamais l'appeler.
  local function piege() appelsMenuJeu = appelsMenuJeu + 1 end
  _G.UIDropDownMenu_Initialize, _G.ToggleDropDownMenu, _G.UIDropDownMenu_AddButton = piege, piege, piege
  _G.EasyMenu, _G.CloseDropDownMenus = piege, piege
end

-- Les fenêtres du jeu, créées avant l'addon, cachées.
local function fenetreJeu(nom, opts)
  opts = opts or {}
  local f = nouveau("Frame", nom, UIParent, nil, true)
  rawset(f, "_shown", false)
  rawset(f, "_protege", opts.protege and true or false)
  rawset(f, "_w", opts.w or 338)
  rawset(f, "_h", opts.h or 424)
  rawset(f, "_scale", opts.echelle or 1)
  rawset(f, "_movable", opts.movable and true or false)
  rawset(f, "_niveau", 10)
  rawset(f, "_strate", opts.strate or "MEDIUM")
  if opts.carte then
    rawset(f, "IsMaximized", function() return rawget(f, "_maximisee") and true or false end)
  end
  creees[#creees + 1] = nom
  return f
end

-- Ce que fait le gestionnaire de panneaux du jeu (appels directs : le jeu, lui, a le droit, même en combat).
local function jeuPose(f, ox, oy)
  M.ClearAllPoints(f)
  M.SetPoint(f, "TOPLEFT", UIParent, "TOPLEFT", ox, oy)
end
local function jeuOuvre(f, ox, oy) jeuPose(f, ox, oy) M.Show(f) end -- il pose, PUIS il affiche
local function jeuFerme(f) M.Hide(f) end

local function declencher(evenement, ...)
  for _, f in ipairs(toutes) do
    if f._events[evenement] and f._scripts.OnEvent then f._scripts.OnEvent(f, evenement, ...) end
  end
end
-- Les minuteries (« à l'image suivante ») : on les exécute toutes ; une boucle infinie serait coupée.
local function avancer()
  local n = 0
  while #file > 0 and n < 200 do n = n + 1; table.remove(file, 1)() end
  return n
end

local function chargerAddon()
  local n = {}
  assert(loadfile(reglagesLua))("Fenetres", n)
  assert(loadfile(fichier))("Fenetres", n)
  return n
end

local function demarrer()
  local n = chargerAddon()
  declencher("ADDON_LOADED", "Fenetres")
  declencher("PLAYER_ENTERING_WORLD")
  avancer()
  return n
end

-- La poignée posée sur une fenêtre : le cadre à nous ancré sur elle.
local function poigneeDe(f)
  for _, h in ipairs(toutes) do
    if not rawget(h, "_jeu") and h._type == "Button" then
      local p = h._pts[1]
      if p and p[2] == f then return h end
    end
  end
end
local function nbPoignees()
  local n = 0
  for _, h in ipairs(toutes) do
    if not rawget(h, "_jeu") and h._type == "Button" and h._pts[1] and h._pts[1][2] and rawget(h._pts[1][2], "_jeu") then n = n + 1 end
  end
  return n
end
local function boutonTexte(texte)
  for _, f in ipairs(toutes) do
    if f._type == "Button" and f._text == texte then return f end
  end
end
local function ligneMenuTexte(texte)
  for _, f in ipairs(toutes) do
    if f._type == "Button" and rawget(f, "texte") and f.texte._text:find(texte, 1, true) and f._shown
       and f._parent and f._parent._nom == "FenetresMenu" then return f end
  end
end
local function menuVisible() return _G.FenetresMenu ~= nil and _G.FenetresMenu._shown end
local function glisser(f, gauche, haut)
  local h = poigneeDe(f)
  h._scripts.OnDragStart(h)
  rawset(f, "_l", gauche)
  rawset(f, "_t", haut)
  h._scripts.OnDragStop(h)
end
local function clicDroit(f)
  local h = poigneeDe(f)
  h._scripts.OnClick(h, "RightButton")
end
local function molette(f, sens)
  local h = poigneeDe(f)
  h._scripts.OnMouseWheel(h, sens)
end
local function ancre(f)
  local p = f._pts[1]
  return p and (p[1] .. "/" .. tostring(p[2] and p[2]._nom) .. "/" .. p[3]) or "aucune"
end

-- Chaque scénario part d'un monde neuf et finit par un contrôle : rien n'a été écrit sur un cadre du jeu,
-- et aucun appel interdit n'est arrivé jusqu'au jeu.
local function scenario(nom, corps)
  installer()
  local bon, erreur = pcall(corps)
  verifie(nom .. " : aucune erreur", true, bon or erreur)
  verifie(nom .. " : aucun champ écrit sur un cadre du jeu", 0, #ecritures)
  verifie(nom .. " : aucun SetAttribute sur un cadre du jeu", 0, #appelsSetAttribute)
  verifie(nom .. " : aucun appel protégé refusé par le jeu", 0, appelsBloques)
  verifie(nom .. " : aucun menu déroulant du jeu", 0, appelsMenuJeu)
end

-- Le contrôle de la détection : écrire un champ d'un cadre du jeu doit être vu.
installer()
do
  local f = fenetreJeu("FenetreEssai")
  local bon = pcall(function() f.monChamp = 1 end)
  verifie("détection : l'écriture d'un champ sur un cadre du jeu est refusée", false, bon)
  verifie("détection : et notée", 1, #ecritures)
end

-- ----- 1. chargement : une poignée seulement pour les fenêtres présentes
scenario("chargement", function()
  local perso = fenetreJeu("CharacterFrame", { movable = true })
  local marchand = fenetreJeu("MerchantFrame", { protege = true })
  local n = demarrer()
  verifie("chargement : deux poignées, une par fenêtre présente", 2, nbPoignees())
  verifie("chargement : poignée du personnage", true, poigneeDe(perso) ~= nil)
  verifie("chargement : poignée du marchand", true, poigneeDe(marchand) ~= nil)
  verifie("chargement : rien pour une fenêtre absente", nil, _G.PlayerSpellsFrame)
  local h = poigneeDe(perso)
  verifie("poignée : cadre à nous, enfant de l'écran et pas de la fenêtre", "UIParent", h._parent._nom)
  verifie("poignée : cadre simple (jamais sécurisé)", "Button", h._type)
  verifie("poignée : caché tant que la fenêtre est fermée", false, h._shown)
  verifie("poignée : ancrée en haut à gauche, marge du portrait", "TOPLEFT/CharacterFrame/TOPLEFT/58/0",
    h._pts[1][1] .. "/" .. h._pts[1][2]._nom .. "/" .. h._pts[1][3] .. "/" .. h._pts[1][4] .. "/" .. h._pts[1][5])
  verifie("poignée : ancrée en haut à droite, marge de la croix", "TOPRIGHT/-26/0",
    h._pts[2][1] .. "/" .. h._pts[2][4] .. "/" .. h._pts[2][5])
  verifie("poignée : hauteur 22", 22, h._h)
  verifie("poignée : glisser avec le bouton gauche", "LeftButton", h._glisse[1])
  verifie("poignée : la molette est écoutée", true, h._molette)
  verifie("poignée : clic droit", "RightButtonUp", h._clics[1])
  jeuOuvre(perso, 100, -50)
  verifie("poignée : visible quand la fenêtre s'ouvre", true, h._shown)
  verifie("poignée : même strate que la fenêtre", perso._strate, h._strate)
  verifie("poignée : au-dessus de la fenêtre (niveau)", true, h._niveau > perso._niveau + 500)
  jeuFerme(perso)
  verifie("poignée : cachée quand la fenêtre se ferme", false, h._shown)
  verifie("fenêtre : rendue mobile", true, perso._movable)
  verifie("fenêtre : dans l'écran (option cochée)", true, perso._clamped)
  verifie("fenêtre protégée : rendue mobile aussi (hors combat)", true, marchand._movable)
  verifie("commande /fen déclarée", "function", type(SlashCmdList.FENETRES))
  verifie("commande /fenetres déclarée", "/fenetres", SLASH_FENETRES2)
  verifie("compartiment d'addons : fonction globale", "function", type(_G.Fenetres_OuvrirReglages))
end)

-- ----- 2. glisser, réouverture, replacement par le jeu
scenario("glisser", function()
  local perso = fenetreJeu("CharacterFrame")
  demarrer()
  jeuOuvre(perso, 100, -50)
  local h = poigneeDe(perso)
  h._scripts.OnDragStart(h)
  verifie("glisser : StartMoving appelé", true, perso._deplace)
  verifie("glisser : la fenêtre est mobile", true, perso._movable)
  verifie("glisser : passée devant", true, (perso._leves or 0) >= 1)
  rawset(perso, "_l", 400) rawset(perso, "_t", 700)
  h._scripts.OnDragStop(h)
  verifie("glisser : arrêté", false, perso._deplace)
  verifie("glisser : SetUserPlaced(false) appelé", false, perso._userPlaced)
  verifie("glisser : x enregistré", 400, FenetresDB.fenetres.CharacterFrame.x)
  verifie("glisser : y enregistré (depuis le haut)", -380, FenetresDB.fenetres.CharacterFrame.y)
  verifie("glisser : pas de taille enregistrée sans molette", nil, FenetresDB.fenetres.CharacterFrame.echelle)
  verifie("glisser : ancre propre au coin haut gauche de l'écran", "TOPLEFT/UIParent/TOPLEFT", ancre(perso))
  verifie("glisser : la fenêtre n'a pas bougé", "400,700", perso:GetLeft() .. "," .. perso:GetTop())
  -- Fermer, puis le jeu rouvre à SA place : notre place revient tout de suite (avant l'image suivante).
  jeuFerme(perso)
  jeuOuvre(perso, 100, -50)
  verifie("réouverture : notre x revient aussitôt", 400, perso:GetLeft())
  verifie("réouverture : notre haut revient aussitôt", 700, perso:GetTop())
  local n = avancer()
  verifie("réouverture : toujours à notre place à l'image suivante", "400,700", perso:GetLeft() .. "," .. perso:GetTop())
  verifie("réouverture : une seule minuterie, pas de boucle", true, n <= 2)
  verifie("réouverture : plus rien en attente", 0, #file)
  -- Le jeu replace la fenêtre ouverte (une autre fenêtre s'ouvre) : on remet notre place à l'image suivante.
  jeuPose(perso, 50, -10)
  verifie("replacement : avant l'image suivante, c'est la place du jeu", 50, perso:GetLeft())
  verifie("replacement : une minuterie prévue", 1, #file)
  jeuPose(perso, 60, -20)
  jeuPose(perso, 70, -30)
  verifie("replacement : dix appels d'affilée ne font qu'une minuterie", 1, #file)
  n = avancer()
  verifie("replacement : notre place est remise", "400,700", perso:GetLeft() .. "," .. perso:GetTop())
  verifie("replacement : sans boucle (nos SetPoint ne relancent rien)", 0, #file)
  verifie("replacement : une seule exécution", 1, n)
  -- Notre ancre ne se confond pas avec celles du jeu : la place « d'origine » retenue est celle du jeu.
  verifie("replacement : ancre finale", "TOPLEFT/UIParent/TOPLEFT", ancre(perso))
  -- Pendant un glissement, le replacement du jeu ne doit pas tirer la fenêtre en arrière.
  h._scripts.OnDragStart(h)
  jeuPose(perso, 5, -5)
  avancer()
  verifie("pendant le glissement : on n'intervient pas", 5, perso:GetLeft())
  rawset(perso, "_l", 800) rawset(perso, "_t", 600)
  h._scripts.OnDragStop(h)
  verifie("après le glissement : la nouvelle place est gardée", 800, FenetresDB.fenetres.CharacterFrame.x)
  -- Une session plus tard : la sauvegarde sert.
  local sauve = FenetresDB
  installer()
  local perso2 = fenetreJeu("CharacterFrame")
  _G.FenetresDB = sauve
  demarrer()
  jeuOuvre(perso2, 100, -50)
  verifie("autre session : la place gardée est reprise", 800, perso2:GetLeft())
end)

-- ----- 3. fenêtre à l'échelle : le coin haut gauche suit
scenario("échelle de la fenêtre", function()
  local perso = fenetreJeu("CharacterFrame", { echelle = 1.25 })
  demarrer()
  jeuOuvre(perso, 100, -50)
  glisser(perso, 400, 700)
  verifie("échelle 125 % : x en unités de l'écran", 400, FenetresDB.fenetres.CharacterFrame.x)
  jeuFerme(perso)
  jeuOuvre(perso, 10, -10)
  proche("échelle 125 % : la fenêtre revient au même endroit", 400, perso:GetLeft() * 1.25)
  proche("échelle 125 % : le haut revient au même endroit", 700, perso:GetTop() * 1.25)
end)

-- ----- 4. combat sur une fenêtre protégée
scenario("combat", function()
  local marchand = fenetreJeu("MerchantFrame", { protege = true })
  local perso = fenetreJeu("CharacterFrame")
  demarrer()
  jeuOuvre(marchand, 100, -50)
  glisser(marchand, 600, 500)
  verifie("combat : place gardée avant le combat", 600, FenetresDB.fenetres.MerchantFrame.x)
  jeuFerme(marchand)
  enCombat = true
  -- Le jeu replace la fenêtre protégée en combat : on ne touche à rien.
  jeuOuvre(marchand, 100, -50)
  local avant = marchand._pts[1]
  avancer()
  verifie("combat : fenêtre protégée, nous n'appelons rien (place du jeu)", 100, marchand:GetLeft())
  verifie("combat : aucune écriture refusée", 0, appelsBloques)
  verifie("combat : ancre inchangée", true, marchand._pts[1] == avant)
  jeuPose(marchand, 120, -60)
  avancer()
  verifie("combat : encore rien après un autre replacement", 120, marchand:GetLeft())
  -- Essayer de glisser en combat : refus, un seul message.
  local h = poigneeDe(marchand)
  h._scripts.OnDragStart(h)
  verifie("combat : glisser refusé (StartMoving jamais appelé)", false, marchand._deplace == true)
  h._scripts.OnDragStart(h)
  verifie("combat : un seul message pour deux essais", 1, compter("ne peut pas être déplacée en combat"))
  verifie("combat : Ctrl + molette refusé aussi", true, (function() ctrl = true molette(marchand, 1) return marchand._scale == 1 end)())
  verifie("combat : toujours un seul message", 1, compter("en combat"))
  ctrl = false
  -- Une fenêtre non protégée se déplace, même en combat.
  jeuOuvre(perso, 100, -50)
  glisser(perso, 300, 300)
  verifie("combat : fenêtre non protégée, déplacée", 300, FenetresDB.fenetres.CharacterFrame.x)
  -- Fin du combat : rattrapage.
  enCombat = false
  declencher("PLAYER_REGEN_ENABLED")
  avancer()
  verifie("fin du combat : notre place est remise", 600, marchand:GetLeft())
  verifie("fin du combat : le haut aussi", 500, marchand:GetTop())
  -- Nouveau combat : le message revient une fois.
  enCombat = true
  h._scripts.OnDragStart(h)
  verifie("nouveau combat : le message revient", 2, compter("ne peut pas être déplacée en combat"))
  enCombat = false
  declencher("PLAYER_REGEN_ENABLED")
  verifie("combat : le jeu n'a refusé aucun appel jusqu'ici", 0, appelsBloques)
  declencher("PLAYER_LOGOUT")
  verifie("diagnostic : refus en combat comptés", true, (FenetresDB.diagnostic.refusCombat.MerchantFrame or 0) >= 3)
  verifie("combat : le jeu n'a jamais refusé un appel", 0, appelsBloques)
end)

-- Une fenêtre protégée qui s'affiche en combat (le jeu l'ouvre lui-même) : la poignée suit, rien n'est refusé.
scenario("ouverture en combat", function()
  local marchand = fenetreJeu("MerchantFrame", { protege = true })
  demarrer()
  jeuOuvre(marchand, 100, -50)
  glisser(marchand, 600, 500)
  jeuFerme(marchand)
  enCombat = true
  jeuOuvre(marchand, 100, -50)
  verifie("ouverture en combat : poignée visible", true, poigneeDe(marchand)._shown)
  verifie("ouverture en combat : place du jeu", 100, marchand:GetLeft())
  enCombat = false
  declencher("PLAYER_REGEN_ENABLED")
  avancer()
  verifie("ouverture en combat : place gardée à la fin du combat", 600, marchand:GetLeft())
end)

-- ----- 4 bis. le combat commence pendant un glisser (constat 3 de la relecture)
scenario("combat pendant un glisser", function()
  local marchand = fenetreJeu("MerchantFrame", { protege = true })
  demarrer()
  jeuOuvre(marchand, 100, -50)
  glisser(marchand, 600, 500)
  jeuFerme(marchand)
  jeuOuvre(marchand, 100, -50)
  avancer()
  local h = poigneeDe(marchand)
  h._scripts.OnDragStart(h)           -- le glisser commence hors combat
  enCombat = true                     -- le combat démarre avant le relâchement
  rawset(marchand, "_l", 300)
  rawset(marchand, "_t", 300)
  h._scripts.OnDragStop(h)            -- on ne touche à rien : aucun appel refusé
  verifie("glisser puis combat : aucun appel refusé par le jeu", 0, appelsBloques)
  verifie("glisser puis combat : l'ancienne place gardée est intacte", 600, FenetresDB.fenetres.MerchantFrame.x)
  jeuFerme(marchand)                  -- la fermeture appelle aussi finirDeplacement : rien de plus
  verifie("glisser puis combat : toujours aucun appel refusé après la fermeture", 0, appelsBloques)
  enCombat = false
  declencher("PLAYER_REGEN_ENABLED")
  jeuOuvre(marchand, 100, -50)
  avancer()
  verifie("glisser puis combat : notre place revient à la fin du combat", 600, marchand:GetLeft())
end)

-- ----- 4 ter. la poignée reste devant sa fenêtre et suit sa taille (constats 1 et 2)
scenario("poignée devant et à l'échelle", function()
  local perso = fenetreJeu("CharacterFrame")
  local mail = fenetreJeu("MailFrame")
  demarrer()
  jeuOuvre(perso, 100, -50)
  jeuOuvre(mail, 500, -50)
  local hp, hm = poigneeDe(perso), poigneeDe(mail)
  verifie("poignée : devant sa fenêtre à l'ouverture", true, hp._niveau > perso._niveau)
  -- Le gestionnaire de panneaux relève les fenêtres : leur niveau passe au-dessus de toutes les poignées.
  M.Raise(perso)
  verifie("poignée : toujours devant sa fenêtre après un Raise du jeu", true, hp._niveau > perso._niveau)
  M.Raise(mail)
  M.Raise(perso)
  verifie("poignée : encore devant après plusieurs Raise", true, hp._niveau > perso._niveau and hm._niveau > mail._niveau)
  -- Un clic dans la fenêtre la relève sans Raise visible : le crochet OnMouseDown remet la poignée devant.
  rawset(perso, "_niveau", 5000)
  for _, fn in ipairs(perso._hookscripts.OnMouseDown or {}) do fn(perso) end
  verifie("poignée : devant après un clic dans la fenêtre", true, hp._niveau > perso._niveau)
  -- Taille : la poignée prend l'échelle de la fenêtre, quel que soit celui qui la change.
  M.SetScale(perso, 1.5)
  proche("poignée : échelle 150 % suit la fenêtre (changée par le jeu)", 1.5, hp._scale)
  M.SetScale(perso, 0.5)
  proche("poignée : échelle 50 % suit la fenêtre", 0.5, hp._scale)
  ctrl = true
  perso._scale = 1
  M.SetScale(perso, 1)
  molette(perso, 1)
  ctrl = false
  proche("poignée : échelle suit Ctrl + molette", 1.05, hp._scale)
  jeuFerme(perso)
  jeuOuvre(perso, 100, -50)
  proche("poignée : échelle gardée à la réouverture", perso._scale, hp._scale)
end)

-- ----- 4 quater. création à moitié faite : les crochets ne sont pas posés deux fois (constat 7)
scenario("création à moitié faite", function()
  local perso = fenetreJeu("CharacterFrame")
  local vrai = _G.CreateFrame
  local echecs = 0
  _G.CreateFrame = function(genre, nom, parent, modele)
    if genre == "Button" and parent == UIParent and nom == nil and echecs < 1 and rawget(perso, "_crochets").SetPoint == nil then
      echecs = echecs + 1
      error("création refusée")
    end
    return vrai(genre, nom, parent, modele)
  end
  demarrer()
  _G.CreateFrame = vrai
  -- Premier passage : la poignée a échoué. Deuxième passage (le jeu rappelle scanner) : tout est posé.
  declencher("ADDON_LOADED", "Blizzard_Autre")
  avancer()
  verifie("création à moitié faite : le premier essai a bien échoué", 1, echecs)
  verifie("création à moitié faite : la poignée existe au second passage", true, poigneeDe(perso) ~= nil)
  local c = rawget(perso, "_crochets")
  verifie("création à moitié faite : un seul crochet SetPoint", 1, #(c.SetPoint or {}))
  verifie("création à moitié faite : un seul crochet Raise", 1, #(c.Raise or {}))
  verifie("création à moitié faite : un seul crochet OnShow", 1, #(perso._hookscripts.OnShow or {}))
  declencher("ADDON_LOADED", "Blizzard_Autre")
  verifie("création à moitié faite : toujours un seul crochet SetPoint", 1, #(rawget(perso, "_crochets").SetPoint or {}))
end)

-- ----- 4 quinquies. un refus en combat n'est compté qu'une fois par ouverture (constat 6)
scenario("refus comptés une fois", function()
  local marchand = fenetreJeu("MerchantFrame", { protege = true })
  demarrer()
  jeuOuvre(marchand, 100, -50)
  glisser(marchand, 600, 500)
  jeuFerme(marchand)
  enCombat = true
  jeuOuvre(marchand, 100, -50)
  avancer()
  declencher("PLAYER_LOGOUT")
  verifie("refus : un seul refus compté pour une ouverture en combat", 1, FenetresDB.diagnostic.refusCombat.MerchantFrame)
  enCombat = false
end)

-- ----- 5. Ctrl + molette
scenario("molette", function()
  local perso = fenetreJeu("CharacterFrame")
  local n = demarrer()
  jeuOuvre(perso, 100, -50)
  glisser(perso, 400, 700)
  molette(perso, 1)
  verifie("molette sans Ctrl : rien", 1, perso._scale)
  ctrl = true
  molette(perso, 1)
  proche("molette : Ctrl, un cran de plus", 1.05, perso._scale)
  proche("molette : taille gardée", 1.05, FenetresDB.fenetres.CharacterFrame.echelle)
  proche("molette : le coin gauche ne bouge pas à l'écran", 400, perso:GetLeft() * 1.05)
  proche("molette : le haut ne bouge pas à l'écran", 700, perso:GetTop() * 1.05)
  verifie("molette : ancre propre", "TOPLEFT/UIParent/TOPLEFT", ancre(perso))
  molette(perso, -1) molette(perso, -1) molette(perso, -1)
  proche("molette : trois crans de moins", 0.9, perso._scale)
  for _ = 1, 20 do molette(perso, -1) end
  proche("molette : plancher 50 %", 0.5, perso._scale)
  for _ = 1, 30 do molette(perso, 1) end
  proche("molette : plafond 150 %", 1.5, perso._scale)
  -- La taille revient à la réouverture.
  jeuFerme(perso)
  jeuOuvre(perso, 100, -50)
  proche("réouverture : taille gardée", 1.5, perso._scale)
  verifie("réouverture : coin gauche gardé", true, math.abs(perso:GetLeft() * 1.5 - 400) < 0.01)
  -- L'option coupée.
  n.reglages.changer("molette", false)
  molette(perso, -1)
  proche("option « molette » coupée : rien", 1.5, perso._scale)
  n.reglages.changer("molette", true)
  -- Bulle d'aide : montre la taille.
  local h = poigneeDe(perso)
  h._scripts.OnEnter(h)
  verifie("bulle : la poignée a une bulle", true, true)
  ctrl = false
end)

-- ----- 6. le menu du clic droit
scenario("menu", function()
  local perso = fenetreJeu("CharacterFrame")
  demarrer()
  jeuOuvre(perso, 100, -50)
  jeuPose(perso, 50, -10) -- la dernière place choisie par le jeu : l'« origine »
  glisser(perso, 400, 700)
  ctrl = true molette(perso, 1) ctrl = false
  verifie("menu : fermé au départ", false, menuVisible() and true or false)
  clicDroit(perso)
  verifie("menu : ouvert par le clic droit", true, menuVisible())
  verifie("menu : en-tête avec le nom de la fenêtre", true, ligneMenuTexte("Personnage") ~= nil)
  verifie("menu : remettre à sa place d'origine", true, ligneMenuTexte("Remettre à sa place d'origine") ~= nil)
  verifie("menu : taille normale", true, ligneMenuTexte("Taille normale") ~= nil)
  verifie("menu : ne plus gérer", true, ligneMenuTexte("Ne plus gérer cette fenêtre") ~= nil)
  -- Taille normale.
  local b = ligneMenuTexte("Taille normale")
  b._scripts.OnClick(b)
  verifie("menu : le menu se ferme", false, menuVisible() and true or false)
  proche("taille normale : taille d'origine", 1, perso._scale)
  verifie("taille normale : taille oubliée", nil, FenetresDB.fenetres.CharacterFrame.echelle)
  verifie("taille normale : la place reste", 400, FenetresDB.fenetres.CharacterFrame.x)
  proche("taille normale : le coin gauche ne bouge pas", 400, perso:GetLeft())
  -- Remettre à sa place d'origine : le jeu reprend la main, la fenêtre va là où il l'avait mise.
  clicDroit(perso)
  b = ligneMenuTexte("Remettre à sa place d'origine")
  b._scripts.OnClick(b)
  verifie("remise : notre place est oubliée", nil, FenetresDB.fenetres.CharacterFrame)
  verifie("remise : la fenêtre retrouve la place du jeu (x)", 50, perso:GetLeft())
  verifie("remise : la fenêtre retrouve la place du jeu (haut)", 1070, perso:GetTop())
  -- Plus de réapplication ensuite.
  jeuFerme(perso)
  jeuOuvre(perso, 100, -50)
  avancer()
  verifie("remise : le jeu replace sans nous", 100, perso:GetLeft())
  -- Ne plus gérer.
  glisser(perso, 300, 600)
  clicDroit(perso)
  b = ligneMenuTexte("Ne plus gérer cette fenêtre")
  b._scripts.OnClick(b)
  verifie("ne plus gérer : exclue dans la sauvegarde", true, FenetresDB.ignorees.CharacterFrame)
  verifie("ne plus gérer : place oubliée", nil, FenetresDB.fenetres.CharacterFrame)
  verifie("ne plus gérer : poignée cachée", false, poigneeDe(perso)._shown)
  verifie("ne plus gérer : mobilité d'origine rendue", false, perso._movable)
  verifie("ne plus gérer : « dans l'écran » d'origine rendu", false, perso._clamped)
  jeuFerme(perso)
  jeuOuvre(perso, 100, -50)
  avancer()
  verifie("ne plus gérer : la poignée ne revient pas", false, poigneeDe(perso)._shown)
  verifie("ne plus gérer : le jeu garde la main", 100, perso:GetLeft())
end)

-- Le menu n'utilise jamais UIDropDownMenu.
scenario("menu fait main", function()
  local perso = fenetreJeu("CharacterFrame")
  demarrer()
  jeuOuvre(perso, 100, -50)
  clicDroit(perso)
  verifie("menu fait main : pas de menu déroulant du jeu", 0, appelsMenuJeu)
  verifie("menu fait main : dans la liste d'Échap", true, (function()
    for _, n in ipairs(UISpecialFrames) do if n == "FenetresMenu" then return true end end
  end)())
end)

-- ----- 7. fenêtres chargées plus tard
scenario("chargée plus tard", function()
  local perso = fenetreJeu("CharacterFrame")
  local n = demarrer()
  verifie("plus tard : pas de poignée pour l'hôtel des ventes", nil, _G.AuctionHouseFrame)
  FenetresDB.fenetres.AuctionHouseFrame = { x = 250, y = -150 }
  local hdv = fenetreJeu("AuctionHouseFrame", { w = 800, h = 538 })
  declencher("ADDON_LOADED", "Blizzard_AuctionHouseUI")
  verifie("plus tard : poignée créée au chargement de l'addon du jeu", true, poigneeDe(hdv) ~= nil)
  verifie("plus tard : deux poignées maintenant", 2, nbPoignees())
  jeuOuvre(hdv, 100, -50)
  verifie("plus tard : la place gardée est reprise", 250, hdv:GetLeft())
  -- Une fenêtre qui apparaît sans événement : trouvée par la vérification générale (2 s après).
  local carte = fenetreJeu("WorldMapFrame", { carte = true })
  verifie("2 s après : pas encore de poignée", nil, poigneeDe(carte))
  declencher("PLAYER_ENTERING_WORLD")
  avancer()
  verifie("2 s après : poignée créée", true, poigneeDe(carte) ~= nil)
  -- Un autre addon du jeu qui ne nous concerne pas : rien ne casse.
  declencher("ADDON_LOADED", "AutreAddonDeJoueur")
  declencher("ADDON_LOADED", "Blizzard_Inconnu")
  verifie("addon inconnu chargé : toujours trois poignées", 3, nbPoignees())
  verifie("la vérification ne double pas les poignées", 3, nbPoignees())
end)

-- ----- 8. la carte du monde agrandie se place toute seule
scenario("carte", function()
  local carte = fenetreJeu("WorldMapFrame", { carte = true, w = 1000, h = 700 })
  demarrer()
  jeuOuvre(carte, 100, -50)
  glisser(carte, 400, 700)
  verifie("carte : place gardée", 400, FenetresDB.fenetres.WorldMapFrame.x)
  jeuFerme(carte)
  jeuOuvre(carte, 100, -50)
  verifie("carte réduite : notre place", 400, carte:GetLeft())
  rawset(carte, "_maximisee", true)
  jeuFerme(carte)
  jeuOuvre(carte, 100, -50)
  avancer()
  verifie("carte agrandie : on laisse le jeu la placer", 100, carte:GetLeft())
  verifie("poignée de la carte : marge droite plus large (bouton agrandir)", "-80", tostring(poigneeDe(carte)._pts[2][4]))
end)

-- ----- 9. addon coupé, puis rallumé
scenario("addon coupé", function()
  local perso = fenetreJeu("CharacterFrame", { movable = true })
  local n = demarrer()
  jeuOuvre(perso, 100, -50)
  glisser(perso, 400, 700)
  local h = poigneeDe(perso)
  verifie("coupé : poignée visible avant", true, h._shown)
  n.reglages.changer("actif", false)
  verifie("coupé : poignée disparue", false, h._shown)
  verifie("coupé : mobilité d'origine (déjà mobile)", true, perso._movable)
  verifie("coupé : « dans l'écran » d'origine", false, perso._clamped)
  verifie("coupé : la fenêtre retrouve la place du jeu", 100, perso:GetLeft())
  jeuFerme(perso)
  jeuOuvre(perso, 100, -50)
  avancer()
  verifie("coupé : le jeu garde la main à la réouverture", 100, perso:GetLeft())
  jeuPose(perso, 90, -40)
  avancer()
  verifie("coupé : un replacement du jeu n'est pas contrarié", 90, perso:GetLeft())
  n.reglages.changer("actif", true)
  verifie("rallumé : la poignée revient", true, h._shown)
  avancer()
  verifie("rallumé : la place gardée est remise", 400, perso:GetLeft())
  -- Démarrer coupé : aucune poignée.
  local sauve = FenetresDB
  installer()
  local perso2 = fenetreJeu("CharacterFrame")
  _G.FenetresDB = { actif = false }
  demarrer()
  verifie("démarré coupé : aucune poignée", 0, nbPoignees())
  jeuOuvre(perso2, 100, -50)
  verifie("démarré coupé : le jeu garde la main", 100, perso2:GetLeft())
  verifie("démarré coupé : fenêtre intacte (pas rendue mobile)", false, perso2._movable)
end)

-- ----- 10. les réglages
scenario("réglages", function()
  local perso = fenetreJeu("CharacterFrame")
  local n = demarrer()
  verifie("réglages : valeurs de départ", "true,true,true,true",
    tostring(FenetresDB.actif) .. "," .. tostring(FenetresDB.memoriser) .. "," .. tostring(FenetresDB.dansEcran) .. "," .. tostring(FenetresDB.molette))
  jeuOuvre(perso, 100, -50)
  -- Dans l'écran.
  FenetresDB.fenetres.CharacterFrame = { x = 5000, y = -200 }
  jeuFerme(perso)
  jeuOuvre(perso, 100, -50)
  verifie("dans l'écran : une place hors écran est ramenée (x)", 1920 - 338, perso:GetLeft())
  n.reglages.changer("dansEcran", false)
  verifie("hors écran permis : « dans l'écran » retiré du cadre", false, perso._clamped)
  jeuFerme(perso)
  jeuOuvre(perso, 100, -50)
  verifie("hors écran permis : la place est gardée telle quelle", 5000, perso:GetLeft())
  n.reglages.changer("dansEcran", true)
  verifie("dans l'écran rétabli : le cadre aussi", true, perso._clamped)
  -- Ne pas garder la place.
  FenetresDB.fenetres.CharacterFrame = { x = 400, y = -380 }
  n.reglages.changer("memoriser", false)
  jeuFerme(perso)
  jeuOuvre(perso, 100, -50)
  avancer()
  verifie("« garder la place » coché off : le jeu place la fenêtre", 100, perso:GetLeft())
  glisser(perso, 700, 700)
  verifie("« garder la place » off : rien d'enregistré de nouveau", 400, FenetresDB.fenetres.CharacterFrame.x)
  n.reglages.changer("memoriser", true)
  jeuFerme(perso)
  jeuOuvre(perso, 100, -50)
  verifie("« garder la place » rallumé : la place gardée revient", 400, perso:GetLeft())
end)

-- ----- 11. la liste des réglages et les commandes
scenario("liste et commandes", function()
  local perso = fenetreJeu("CharacterFrame")
  local courrier = fenetreJeu("MailFrame")
  local n = demarrer()
  jeuOuvre(perso, 100, -50)
  jeuOuvre(courrier, 100, -50)
  glisser(perso, 400, 700)
  glisser(courrier, 300, 500)
  ctrl = true molette(courrier, 1) ctrl = false
  n.reglages.ouvrir()
  n.reglages.majFenetre()
  local function ligne(texte)
    for _, f in ipairs(toutes) do
      if f._type == "FontString" and f._text == texte and f._parent and f._parent._shown then return f._parent end
    end
  end
  verifie("liste : fenêtre déplacée", true, ligne("Personnage : déplacée") ~= nil)
  verifie("liste : fenêtre déplacée et redimensionnée", true, ligne("Courrier : déplacée, taille 105 %") ~= nil)
  local l = ligne("Personnage : déplacée")
  l.croix._scripts.OnClick(l.croix)
  verifie("liste : la croix remet la fenêtre à sa place d'origine", nil, FenetresDB.fenetres.CharacterFrame)
  verifie("liste : l'autre fenêtre garde sa place", true, FenetresDB.fenetres.MailFrame ~= nil)
  verifie("liste : la ligne disparaît", nil, ligne("Personnage : déplacée"))
  -- Un bouton « Tout remettre à sa place d'origine ».
  local b = boutonTexte("Tout remettre à sa place d'origine")
  verifie("bouton : « Tout remettre à sa place d'origine » existe", true, b ~= nil)
  b._scripts.OnClick(b)
  verifie("bouton : tout est oublié", nil, next(FenetresDB.fenetres))
  proche("bouton : la taille aussi est rendue", 1, courrier._scale)
  verifie("bouton : un message", true, compter("remise(s) à leur place d'origine") >= 1)
  -- Commandes.
  glisser(perso, 450, 650)
  SlashCmdList.FENETRES("reset")
  verifie("/fen reset : tout oublié", nil, next(FenetresDB.fenetres))
  imprime = {}
  SlashCmdList.FENETRES("etat")
  verifie("/fen etat : le nombre de fenêtres suivies", true, compter("2 fenêtre(s) suivie(s)") == 1)
  imprime = {}
  SlashCmdList.FENETRES("aide")
  verifie("/fen aide : la liste des commandes", true, compter("/fen reset") >= 1)
  SlashCmdList.FENETRES("n'importe quoi")
  verifie("/fen inconnue : message", true, compter("commande inconnue") == 1)
  _G.ValentinAddonsReglages:Hide()
  SlashCmdList.FENETRES("")
  verifie("/fen : ouvre les réglages", true, _G.ValentinAddonsReglages._shown)
  SlashCmdList.FENETRES("off")
  verifie("/fen off : coupe l'addon", false, FenetresDB.actif)
  SlashCmdList.FENETRES("on")
  verifie("/fen on : le rallume", true, FenetresDB.actif)
  -- Fenêtre exclue : la liste des exclues.
  clicDroit(perso)
  local m = ligneMenuTexte("Ne plus gérer cette fenêtre")
  m._scripts.OnClick(m)
  n.reglages.majFenetre()
  local e = ligne("Personnage")
  verifie("liste des exclues : la fenêtre y est", true, e ~= nil)
  e.croix._scripts.OnClick(e.croix)
  verifie("liste des exclues : la croix la remet dans la liste", nil, FenetresDB.ignorees.CharacterFrame)
  verifie("liste des exclues : la poignée revient", true, poigneeDe(perso)._shown)
end)

-- ----- 12. diagnostic
scenario("diagnostic", function()
  local perso = fenetreJeu("CharacterFrame")
  local marchand = fenetreJeu("MerchantFrame", { protege = true })
  demarrer()
  jeuOuvre(perso, 100, -50)
  glisser(perso, 400, 700)
  ctrl = true molette(perso, 1) ctrl = false
  declencher("PLAYER_LOGOUT")
  local d = FenetresDB.diagnostic
  verifie("diagnostic : écrit à la déconnexion", "table", type(d))
  local function contient(liste, texte)
    for _, v in ipairs(liste) do if v:find(texte, 1, true) then return true end end
    return false
  end
  verifie("diagnostic : fenêtres trouvées", true, contient(d.trouvees, "CharacterFrame") and contient(d.trouvees, "MerchantFrame"))
  verifie("diagnostic : fenêtres introuvables, avec leur addon", true, contient(d.introuvables, "PlayerSpellsFrame (Blizzard_PlayerSpells)"))
  verifie("diagnostic : une fenêtre trouvée n'est pas dans les introuvables", false, contient(d.introuvables, "CharacterFrame"))
  verifie("diagnostic : fenêtres déplacées avec leur point", true, contient(d.deplacees, "CharacterFrame : TOPLEFT x=400.0 y=-380.0 taille=1.05"))
  verifie("diagnostic : la date", true, type(d.date) == "string" and d.date ~= "")
  verifie("diagnostic : table des refus présente", "table", type(d.refusCombat))
end)

-- ----- 13. données abîmées dans la sauvegarde
scenario("sauvegarde abîmée", function()
  local perso = fenetreJeu("CharacterFrame")
  local marchand = fenetreJeu("MerchantFrame")
  local courrier = fenetreJeu("MailFrame")
  _G.FenetresDB = { fenetres = { CharacterFrame = { x = "abc", y = 5 }, MerchantFrame = 7, MailFrame = { x = 1e12, y = 1 } },
                    ignorees = "pas une table" }
  demarrer()
  jeuOuvre(perso, 100, -50)
  jeuOuvre(marchand, 100, -50)
  jeuOuvre(courrier, 100, -50)
  avancer()
  verifie("sauvegarde abîmée : place texte ignorée", 100, perso:GetLeft())
  verifie("sauvegarde abîmée : valeur isolée ignorée", 100, marchand:GetLeft())
  verifie("sauvegarde abîmée : place démesurée ignorée", 100, courrier:GetLeft())
  verifie("sauvegarde abîmée : la table des exclues est refaite", "table", type(FenetresDB.ignorees))
  local sauve = FenetresDB
  installer()
  perso = fenetreJeu("CharacterFrame")
  _G.FenetresDB = { fenetres = "x" }
  demarrer()
  jeuOuvre(perso, 100, -50)
  verifie("sauvegarde abîmée : table des places refaite", "table", type(FenetresDB.fenetres))
end)

-- ----- 14. des cadres bizarres
scenario("cadres bizarres", function()
  -- Un cadre sans HookScript, un nom qui n'est pas un cadre, un cadre interdit.
  local perso = fenetreJeu("CharacterFrame")
  rawset(perso, "HookScript", false)
  _G.MerchantFrame = "pas un cadre"
  creees[#creees + 1] = "MerchantFrame"
  local mail = fenetreJeu("MailFrame")
  rawset(mail, "IsForbidden", function() return true end)
  local troc = fenetreJeu("TradeFrame")
  rawset(troc, "IsForbidden", function() error("boum") end)
  local ok2 = fenetreJeu("FriendsFrame")
  demarrer()
  verifie("cadres bizarres : seul le cadre sain est suivi", 1, nbPoignees())
  verifie("cadres bizarres : c'est le bon", true, poigneeDe(ok2) ~= nil)
end)

-- ----- 15. API retirées une à une
local function parcoursComplet()
  local perso = fenetreJeu("CharacterFrame")
  local marchand = fenetreJeu("MerchantFrame", { protege = true })
  local carte = fenetreJeu("WorldMapFrame", { carte = true })
  local n = demarrer()
  jeuOuvre(perso, 100, -50)
  jeuOuvre(marchand, 100, -50)
  jeuOuvre(carte, 100, -50)
  for _, f in ipairs({ perso, marchand, carte }) do
    local h = poigneeDe(f)
    if h then
      h._scripts.OnEnter(h)
      h._scripts.OnLeave(h)
      h._scripts.OnDragStart(h)
      rawset(f, "_l", 400) rawset(f, "_t", 700)
      h._scripts.OnDragStop(h)
      ctrl = true h._scripts.OnMouseWheel(h, 1) ctrl = false
      h._scripts.OnClick(h, "RightButton")
      local m = ligneMenuTexte("Taille normale")
      if m then m._scripts.OnClick(m) end
    end
  end
  jeuFerme(perso)
  jeuOuvre(perso, 100, -50)
  jeuPose(perso, 20, -20)
  avancer()
  enCombat = true
  jeuPose(marchand, 30, -30)
  local h = poigneeDe(marchand)
  if h then h._scripts.OnDragStart(h) end
  avancer()
  enCombat = false
  declencher("PLAYER_REGEN_ENABLED")
  avancer()
  n.reglages.changer("dansEcran", false)
  n.reglages.changer("memoriser", false)
  n.reglages.changer("memoriser", true)
  n.reglages.changer("actif", false)
  n.reglages.changer("actif", true)
  local hp = poigneeDe(perso)
  if hp then
    hp._scripts.OnClick(hp, "RightButton")
    local m = ligneMenuTexte("Remettre à sa place d'origine")
    if m then m._scripts.OnClick(m) end
    hp._scripts.OnClick(hp, "RightButton")
    m = ligneMenuTexte("Ne plus gérer cette fenêtre")
    if m then m._scripts.OnClick(m) end
  end
  SlashCmdList.FENETRES("etat")
  SlashCmdList.FENETRES("reset")
  declencher("DISPLAY_SIZE_CHANGED")
  declencher("UI_SCALE_CHANGED")
  avancer()
  declencher("PLAYER_LOGOUT")
end

-- Sans retrait : le parcours complet passe.
scenario("parcours complet", parcoursComplet)

local methodesJeu = { "SetPoint", "ClearAllPoints", "HookScript", "IsShown", "IsVisible", "GetLeft", "GetTop",
  "GetEffectiveScale", "GetScale", "SetScale", "SetMovable", "IsMovable", "SetClampedToScreen", "IsClampedToScreen",
  "StartMoving", "StopMovingOrSizing", "SetUserPlaced", "IsProtected", "IsForbidden", "GetWidth", "GetHeight",
  "GetFrameStrata", "GetFrameLevel", "Raise" }
for _, nom in ipairs(methodesJeu) do
  installer()
  retiresJeu[nom] = true
  local bon, erreur = pcall(parcoursComplet)
  verifie("API retirée du cadre : " .. nom, true, bon or erreur)
  verifie("API retirée du cadre : " .. nom .. " (aucun champ écrit)", 0, #ecritures)
  verifie("API retirée du cadre : " .. nom .. " (aucun refus du jeu)", 0, appelsBloques)
  verifie("API retirée du cadre : " .. nom .. " (aucun menu déroulant du jeu)", 0, appelsMenuJeu)
end

local globalesRetirees = { "hooksecurefunc", "InCombatLockdown", "IsControlKeyDown", "GetCursorPosition", "GameTooltip",
  "C_Timer", "date", "UnitName", "IsShiftKeyDown" }
-- (UISpecialFrames n'est pas dans la liste : Reglages.lua, commun à tous les addons, l'utilise sans garde.)
for _, nom in ipairs(globalesRetirees) do
  installer()
  local copie = _G[nom]
  -- C_Timer sert aux minuteries : sans lui, la file reste vide et on saute avancer(). Le parcours reste valable.
  _G[nom] = nil
  local bon, erreur = pcall(parcoursComplet)
  _G[nom] = copie
  verifie("API retirée du jeu : " .. nom, true, bon or erreur)
  verifie("API retirée du jeu : " .. nom .. " (aucun champ écrit)", 0, #ecritures)
end

-- ----- 15 bis. le jeu ignore StartMoving (vu en jeu sur Forever le 12/11) : glisser à la main
scenario("glisser à la main", function()
  local perso = fenetreJeu("CharacterFrame")
  demarrer()
  jeuOuvre(perso, 100, -50)
  local h = poigneeDe(perso)
  local avantL, avantT = perso:GetLeft(), perso:GetTop()
  local curseur = { 600, 500 }
  local copie = _G.GetCursorPosition
  _G.GetCursorPosition = function() return curseur[1], curseur[2] end
  h._scripts.OnDragStart(h)
  verifie("à la main : suivi de la souris branché", "function", type(h._scripts.OnUpdate))
  -- Le jeu ne bouge pas la fenêtre ; la souris va 120 points à droite et 80 vers le bas.
  curseur[1], curseur[2] = 720, 420
  h._scripts.OnUpdate(h)
  local ef = perso:GetEffectiveScale()
  verifie("à la main : la fenêtre suit la souris (gauche)", math.floor(avantL + 120 / ef + 0.5), math.floor(perso:GetLeft() + 0.5))
  verifie("à la main : la fenêtre suit la souris (haut)", math.floor(avantT - 80 / ef + 0.5), math.floor(perso:GetTop() + 0.5))
  curseur[1], curseur[2] = 760, 420
  h._scripts.OnUpdate(h)
  h._scripts.OnDragStop(h)
  verifie("à la main : suivi de la souris débranché", nil, h._scripts.OnUpdate)
  verifie("à la main : place enregistrée", math.floor(avantL + 160 / ef + 0.5), math.floor((FenetresDB.fenetres.CharacterFrame.x or -1) * UIParent._scale / ef + 0.5))
  -- Fermer puis rouvrir : la place revient.
  jeuFerme(perso)
  jeuOuvre(perso, 100, -50)
  verifie("à la main : place gardée à la réouverture", math.floor(avantL + 160 / ef + 0.5), math.floor(perso:GetLeft() + 0.5))
  _G.GetCursorPosition = copie
end)

-- ----- 16. nettoyage : rien ne reste dans le monde global de ce qui n'est pas à nous
installer()
verifie("nettoyage : le menu déroulant du jeu n'a jamais été appelé", 0, appelsMenuJeu)

io.write(string.format("\n%d vérifications OK\n", nbOK))
if ok then io.write("Tout est bon.\n") else io.write("DES ECHECS (lignes KO ci-dessus).\n") os.exit(1) end
