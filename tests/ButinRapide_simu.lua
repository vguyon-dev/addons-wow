-- Simulation hors jeu de Butin rapide : quoi ramasser, quel gris jeter, gain par heure, et le bilan de
-- farm partagé avec le Carnet de session (lignes rendues, cadre caché à la demande, prévenir le Carnet).
-- Lancer depuis Windows :
--   wsl lua5.1 tests/ButinRapide_simu.lua ButinRapide/ButinRapide.lua
local bidon
bidon = function()
  return setmetatable({}, { __index = function() return bidon() end, __call = function() return bidon() end })
end

-- Un texte qui se souvient de ce qu'on lui a demandé.
local function police()
  local f = bidon()
  local e = { texte = "" }
  rawset(f, "_e", e)
  rawset(f, "SetText", function(_, t) e.texte = t end)
  rawset(f, "GetStringHeight", function() return 12 end)
  return f
end

local ABSENTS = { titreHabille = true, traitHabille = true, fermerHabille = true, fondHabille = true }
local cadres, policesBilan = {}, {}
function CreateFrame(_, nom)
  local f = setmetatable({}, {
    __index = function(_, k) if ABSENTS[k] then return nil end return bidon() end,
    __call = function() return bidon() end,
  })
  local scripts, e = {}, { visible = false, h = 0 }
  rawset(f, "_scripts", scripts)
  rawset(f, "_e", e)
  rawset(f, "SetScript", function(_, n, fn) scripts[n] = fn end)
  rawset(f, "RegisterEvent", function() end)
  rawset(f, "IsShown", function() return e.visible end)
  rawset(f, "Show", function() e.visible = true end)
  rawset(f, "Hide", function() e.visible = false end)
  rawset(f, "SetShown", function(_, v) e.visible = v and true or false end)
  rawset(f, "SetHeight", function(_, h) e.h = h end)
  rawset(f, "CreateFontString", function()
    local p = police()
    if nom == "ButinRapideBilan" then policesBilan[#policesBilan + 1] = p end
    return p
  end)
  if nom == "ButinRapideBilan" then _G[nom] = f end
  cadres[#cadres + 1] = f
  return f
end
-- Aucun champ ne doit être écrit sur un cadre du jeu : UIParent refuse toute écriture.
UIParent = setmetatable({}, { __newindex = function(_, k) error("champ écrit sur UIParent : " .. tostring(k)) end })
SlashCmdList, UISpecialFrames, Minimap, C_Timer = {}, {}, bidon(), bidon()
tinsert = table.insert
time = os.time
function strtrim(s) return s end
function print() end
-- Un objet vendu 1 po (10000 cuivre) chez le marchand : le 11e champ de GetItemInfo.
function GetItemInfo() return "Peau", nil, 1, 1, 1, "", "", 20, "", 0, 10000 end

local ns = {}
local reglagesLua = arg[1]:gsub("[^/]+$", "Reglages.lua")
assert(loadfile(reglagesLua))("ButinRapide", ns)
-- Un bilan déjà commencé : 3 peaux, 2 po ramassés, une heure de jeu.
ButinRapidePerso = { debut = os.time(), joue = 3600, argent = 20000,
  objets = { [1] = { lien = "|cffffffff|Hitem:1|h[Peau]|h|r", nombre = 3 } } }
assert(loadfile(arg[1]))("ButinRapide", ns)

local ok = true
local function verifie(libelle, attendu, obtenu)
  local bon = attendu == obtenu
  ok = ok and bon
  io.write(string.format("%s %-50s attendu %s, obtenu %s\n", bon and "OK " or "KO ", libelle, tostring(attendu), tostring(obtenu)))
end
local function lire(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end
verifie("Reglages.lua identique dans QuetesAuto", true,
  lire(reglagesLua) == lire((reglagesLua:gsub("ButinRapide/Reglages", "QuetesAuto/Reglages"))))

local r = { ignorerGris = false }
verifie("objet normal : pris", "prendre", ns.decision({ qualite = 1, idObjet = 5 }, r, {}))
verifie("argent : toujours pris", "prendre", ns.decision({ argent = true }, { ignorerGris = true }, {}))
verifie("gris, filtre coupé : pris", "prendre", ns.decision({ qualite = 0 }, r, {}))
verifie("gris, filtre mis : laissé", "laisser", ns.decision({ qualite = 0 }, { ignorerGris = true }, {}))
verifie("objet de quête gris : pris quand même", "prendre", ns.decision({ qualite = 0, quete = true }, { ignorerGris = true }, {}))
verifie("objet de la liste : laissé", "laisser", ns.decision({ qualite = 2, idObjet = 9 }, r, { [9] = true }))
verifie("violet en groupe (seuil vert) : jet de dés", "attendre", ns.decision({ qualite = 4 }, r, {}, 2))
verifie("verrouillé : attendre", "attendre", ns.decision({ verrouille = true }, r, {}))

verifie("gris le moins cher", 2, ns.grisAJeter({ { valeur = 50 }, { valeur = 3 }, { valeur = 9 } }))
verifie("aucun gris : rien", nil, ns.grisAJeter({}))
verifie("par heure : 1000 en 30 min", 2000, ns.parHeure(1000, 1800))
verifie("durée jouée : sessions d'avant + celle-ci", 900, ns.dureeJouee(600, 1000, 1300))
verifie("durée jouée : rien d'avant", 300, ns.dureeJouee(nil, 1000, 1300))
verifie("durée jouée : horloge qui recule, pas de négatif", 600, ns.dureeJouee(600, 2000, 1300))
verifie("par heure : moins d'une minute = 0", 0, ns.parHeure(1000, 30))

-- Lignes de la liste « à ne jamais ramasser ».
local retires = {}
local info = function(id) if id == 3 then return "Pomme" end end
verifie("nom : pris du lien", "Eau", ns.nomObjet(1, "|cffffffff|Hitem:1|h[Eau]|h|r", info))
verifie("nom : pris du jeu sans lien", "Pomme", ns.nomObjet(3, nil, info))
verifie("nom : repli", "objet 9", ns.nomObjet(9, true, info))
local l = ns.lignesIgnores({ [2] = "[Zèbre]", [1] = "[abeille]", [3] = true }, info, function(id) retires[#retires + 1] = id end)
verifie("ignores : 3 lignes", 3, #l)
verifie("ignores : tri par nom sans casse", "abeille", l[1].texte)
verifie("ignores : lien de survol", "item:1", l[1].lien)
l[3].retirer()
verifie("ignores : la croix retire l'objet", 2, retires[1])
verifie("ignores : liste vide", 0, #ns.lignesIgnores(nil, info, function() end))

-- ===== Bilan partagé avec le Carnet de session =====
local function evt(nom, ...)
  for _, f in ipairs(cadres) do
    if f._scripts.OnEvent then f._scripts.OnEvent(f, nom, ...) end
  end
end
evt("ADDON_LOADED", "ButinRapide")
local bilan = ButinRapideBilan
local db = ButinRapideDB
verifie("le cadre du bilan est montré par défaut", true, bilan:IsShown())

local b = ButinRapide_LignesBilan()
verifie("lignes : table rendue", "table", type(b))
local par = {}
for _, ligne in ipairs(b.lignes) do par[ligne.libelle] = ligne end
verifie("lignes : durée en secondes", 3600, math.floor(b.duree))
verifie("lignes : durée", "60 min", par["Durée"].valeur)
verifie("lignes : objets", "3", par["Objets"].valeur)
verifie("lignes : or ramassé", "2 po", par["Or ramassé"].valeur)
verifie("lignes : revente marchand", "3 po", par["Revente marchand"].valeur)
verifie("lignes : pas d'hôtel des ventes sans addon", nil, par["Hôtel des ventes"])
verifie("lignes : par heure (or + hôtel des ventes)", "5 po", par["Par heure"].valeur)
verifie("lignes : par heure aussi à part", "5 po", b.parHeure)
verifie("lignes : par heure en vert", "40ff40", par["Par heure"].couleur)
verifie("ligne d'objet : valeur", "× 3", b.lignes[#b.lignes].valeur)
verifie("ligne d'objet : le lien", true, b.lignes[#b.lignes].libelle:find("[Peau]", 1, true) ~= nil)
-- Le cadre de Butin rapide écrit les mêmes lignes qu'avant.
local texteCadre
for _, p in ipairs(policesBilan) do
  if p._e.texte:find("Durée", 1, true) then texteCadre = p._e.texte end
end
verifie("cadre : il écrit les mêmes lignes qu'avant", "Durée : 60 min\nObjets : 3\nOr ramassé : 2 po\nRevente marchand : 3 po\n"
  .. "|cff40ff40Par heure : 5 po|r\n3 × |cffffffff|Hitem:1|h[Peau]|h|r", texteCadre)
verifie("texte de ligne : durée", "Durée : 60 min", b.lignes[1].texte)
verifie("texte de ligne : or", "Or ramassé : 2 po", par["Or ramassé"].texte)
verifie("texte de ligne : par heure coloré", "|cff40ff40Par heure : 5 po|r", par["Par heure"].texte)
verifie("texte de ligne : objet comme avant", "3 × |cffffffff|Hitem:1|h[Peau]|h|r", b.lignes[#b.lignes].texte)

-- Le Carnet demande de cacher le cadre : il disparaît, sans toucher au réglage « bilan ».
ButinRapide_SetBilanCache(true)
verifie("cache : le cadre de Butin rapide disparaît", false, bilan:IsShown())
verifie("cache : le réglage bilan est inchangé", true, db.bilan)
verifie("cache : les lignes restent rendues", "table", type(ButinRapide_LignesBilan()))

-- Butin rapide prévient le Carnet après chaque mise à jour (même s'il plante).
local prevenu = 0
function CarnetDeSession_MajFarm() prevenu = prevenu + 1 end
ns.reglages.changer("actif", true)
verifie("mise à jour : le Carnet est prévenu", true, prevenu >= 1)
verifie("mise à jour : le cadre reste caché", false, bilan:IsShown())
function CarnetDeSession_MajFarm() prevenu = prevenu + 1; error("boum") end
local avantPrevenu = prevenu
local bon = pcall(ns.reglages.changer, "actif", true)
verifie("Carnet qui plante : pas d'erreur chez Butin rapide", true, bon)
verifie("Carnet qui plante : il a bien été appelé", true, prevenu > avantPrevenu)
-- Un Carnet qui redemande le cache pendant qu'on le prévient ne fait pas de boucle.
function CarnetDeSession_MajFarm() prevenu = prevenu + 1; ButinRapide_SetBilanCache(true) end
avantPrevenu = prevenu
ns.reglages.changer("actif", true)
verifie("pas de boucle : un seul appel", 1, prevenu - avantPrevenu)

-- Bilan coupé dans les réglages : plus de lignes, le Carnet est prévenu pour retirer sa partie Farm.
function CarnetDeSession_MajFarm() prevenu = prevenu + 1 end
avantPrevenu = prevenu
ns.reglages.changer("bilan", false)
verifie("bilan coupé : plus de lignes", nil, ButinRapide_LignesBilan())
verifie("bilan coupé : le Carnet est prévenu", true, prevenu > avantPrevenu)
verifie("bilan coupé : cadre caché", false, bilan:IsShown())
ns.reglages.changer("bilan", true)
verifie("bilan remis : les lignes reviennent", "table", type(ButinRapide_LignesBilan()))
verifie("bilan remis : le cadre reste caché (le Carnet l'affiche)", false, bilan:IsShown())

-- Le Carnet n'en a plus besoin (réglage « non », cadre fermé) : le cadre revient.
ButinRapide_SetBilanCache(false)
verifie("cache levé : le cadre de Butin rapide revient", true, bilan:IsShown())
ButinRapide_SetBilanCache(false)
verifie("cache levé deux fois : rien ne change", true, bilan:IsShown())
-- Bilan coupé et cache levé : le cadre reste caché (le réglage décide).
ns.reglages.changer("bilan", false)
ButinRapide_SetBilanCache(true)
ButinRapide_SetBilanCache(false)
verifie("bilan coupé : le cadre ne revient pas tout seul", false, bilan:IsShown())
ns.reglages.changer("bilan", true)
verifie("bilan remis sans Carnet : le cadre revient", true, bilan:IsShown())
-- Sans Carnet du tout (fonction absente) : rien ne plante.
CarnetDeSession_MajFarm = nil
bon = pcall(ns.reglages.changer, "actif", true)
verifie("Carnet absent : pas d'erreur", true, bon)

-- Le code : aucune variable accentuée, aucun tiret cadratin ni demi-cadratin, bonne version.
local code = lire(arg[1])
local accent = false
for ligne in code:gmatch("[^\n]+") do
  local sansTexte = ligne:gsub('"[^"]*"', ""):gsub("%-%-.*$", "")
  if sansTexte:find("\195[\128-\191]") then accent = true end
end
verifie("code : aucune variable accentuée", false, accent)
verifie("code : aucun tiret cadratin ni demi-cadratin", false,
  code:find("\226\128\148", 1, true) ~= nil or code:find("\226\128\147", 1, true) ~= nil)
local toc = lire((arg[1]:gsub("ButinRapide%.lua$", "ButinRapide.toc")))
verifie("toc : version 0.8.0", true, toc:find("## Version: 0.8.0", 1, true) ~= nil)

io.write(ok and "Tout est bon.\n" or "Il reste des échecs.\n")
os.exit(ok and 0 or 1)
