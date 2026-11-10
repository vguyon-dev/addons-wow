-- ============================================================================
-- GPS : des balises et une flèche pour y aller (comme TomTom, réécrit à notre
-- façon, sans reprendre son code).
--
--   /way 45.2 67.8 Titre        une balise sur la carte où tu es
--   /way Elwynn 45 67 Titre     une balise sur une autre carte (nom de la zone)
--   Ctrl + clic droit sur la carte du monde : une balise à cet endroit
--   /way effacer                retire toutes les balises
--   /way envoyer [tout]         envoie la balise suivie (ou toutes) au groupe
--   /gps                        les réglages, avec la liste des balises
--
-- Sans balise, la flèche suit l'épingle posée sur la carte du jeu, sinon la
-- quête suivie (son objectif, ou le PNJ à qui la rendre).
-- Une flèche déplaçable montre la direction, la distance et le temps restant,
-- même au-delà de 1 000 m et depuis une autre zone du même continent. Arrivé à
-- moins de 10 m : un son, la balise disparaît et la suivante prend le relais.
-- La balise suivie est aussi posée comme épingle du jeu (carte et minimap).
-- Pour les autres addons : GPS_Ajouter(carte, x, y, titre) avec x, y entre 0 et 1.
-- Partage : « Envoyer au groupe » (onglet Balises) ou /way envoyer envoient la
-- balise suivie aux membres du groupe (message d'addon, préfixe « GPSValentin »).
-- Chez eux, avec l'option « Accepter les balises de mon groupe », elle s'ajoute
-- avec « (de Nom) » dans son titre, sans doublon.
-- ============================================================================

local NOM_ADDON, ns = ...

local DEFAUTS = {
  actif = true,
  fleche = true,        -- la flèche à l'écran
  taille = 160,         -- taille de la flèche, en % (grosse par défaut : on ne la rate pas)
  epingle = true,       -- la balise suivie devient aussi l'épingle du jeu
  plusProche = true,    -- suivre la balise la plus proche (sinon la dernière posée)
  arrivee = true,       -- son et retrait de la balise à l'arrivée
  suivreQuete = true,   -- sans balise : la flèche suit la quête suivie
  suivreEpingle = true, -- sans balise : la flèche suit l'épingle posée sur la carte du jeu
  accepterGroupe = true, -- ajouter les balises envoyées par les membres de mon groupe
  minimap = false,
  angleMinimap = 30,
}

local db, perso
local estSecret = issecretvalue or function() return false end

-- ---------------------------------------------------------------------------
-- Partie « logique pure », testée hors jeu (tests/GPS_simu.lua).
-- ---------------------------------------------------------------------------

local function sansAccents(t)
  t = tostring(t or ""):lower()
  for a, b in pairs({ ["é"] = "e", ["è"] = "e", ["ê"] = "e", ["à"] = "a", ["â"] = "a", ["î"] = "i", ["ï"] = "i",
    ["ô"] = "o", ["û"] = "u", ["ù"] = "u", ["ç"] = "c", ["'"] = "", ["’"] = "", ["-"] = " " }) do
    t = t:gsub(a, b)
  end
  return t
end
ns.sansAccents = sansAccents

-- Lit « /way [zone] x y [titre] ». Accepte 45.2 ou 45,2, et « 45.2, 67.8 ».
--   cartes : { { id, nom } } pour retrouver une zone par son nom (début du nom suffit)
-- Renvoie { carte, x, y, titre } (x, y entre 0 et 1) ou nil et un message.
function ns.lireWay(texte, carteIci, cartes)
  texte = tostring(texte or ""):gsub("^%s+", ""):gsub("%s+$", "")
  -- Les nombres : on repère les deux premiers nombres qui se suivent.
  local avant, a, b, apres = texte:match("^(.-)%s*(%d+[%.,]?%d*)[%s,;]+(%d+[%.,]?%d*)%s*(.*)$")
  if not a then return nil, "écris deux nombres : /way 45.2 67.8 (et un titre si tu veux)" end
  local x, y = tonumber((a:gsub(",", "."))), tonumber((b:gsub(",", ".")))
  if not x or not y or x < 0 or x > 100 or y < 0 or y > 100 then return nil, "les coordonnées vont de 0 à 100" end
  local carte = carteIci
  if avant and avant ~= "" then
    local cherche = sansAccents(avant)
    carte = nil
    -- Un nom exact d'abord, sinon le premier nom qui commence pareil.
    for _, c in ipairs(cartes or {}) do
      if sansAccents(c.nom) == cherche then carte = c.id break end
    end
    if not carte then
      for _, c in ipairs(cartes or {}) do
        if sansAccents(c.nom):sub(1, #cherche) == cherche then carte = c.id break end
      end
    end
    if not carte then return nil, "zone inconnue : " .. avant end
  end
  if not carte then return nil, "ta position est inconnue ici (donjon ?)" end
  return { carte = carte, x = x / 100, y = y / 100, titre = apres ~= "" and apres or nil }
end

-- Distance (en mètres du jeu) entre deux points du monde.
function ns.distance(px, py, tx, ty)
  return math.sqrt((tx - px) ^ 2 + (ty - py) ^ 2)
end

-- Angle de la flèche (radians, sens inverse des aiguilles, 0 = tout droit).
-- Coordonnées du monde : x vers le nord, y vers l'ouest. orientation : celle de
-- GetPlayerFacing (0 = nord, sens inverse des aiguilles).
function ns.angle(px, py, tx, ty, orientation)
  return math.atan2(ty - py, tx - px) - orientation
end

-- « 1 min 20 s », « 45 s », « 2 h 05 » ; nil si on ne sait pas (immobile).
function ns.tempsRestant(distance, vitesse)
  if not vitesse or vitesse < 0.5 then return nil end
  local s = math.floor(distance / vitesse + 0.5)
  if s >= 3600 then return string.format("%d h %02d", math.floor(s / 3600), math.floor(s % 3600 / 60)) end
  if s >= 60 then return string.format("%d min %02d s", math.floor(s / 60), s % 60) end
  return s .. " s"
end

-- La balise à suivre : la plus proche du même continent, ou la dernière posée.
--   balises : { { …, monde = { continent, x, y } } } ; ici = { continent, x, y }
function ns.choisir(balises, ici, plusProche)
  local meilleure, dMin
  for i, b in ipairs(balises) do
    local m = b.monde
    if m and ici and m.continent == ici.continent then
      if not plusProche then
        meilleure, dMin = b, ns.distance(ici.x, ici.y, m.x, m.y)
      else
        local d = ns.distance(ici.x, ici.y, m.x, m.y)
        if not dMin or d < dMin then meilleure, dMin = b, d end
      end
    end
  end
  return meilleure, dMin
end

-- ---------------------------------------------------------------------------
-- Balises partagées avec le groupe : le message « B<tab>carte<tab>x<tab>y<tab>titre »
-- ---------------------------------------------------------------------------

local TITRE_MAX = 60       -- octets gardés d'un titre
local TOLERANCE = 0.005    -- 0,5 % de la carte : même point

-- Un texte coupé à `max` octets sans casser une lettre accentuée (UTF-8).
local function couper(t, max)
  if #t <= max then return t end
  local fin = max
  while fin > 0 do
    local suivant = t:byte(fin + 1)
    if suivant and suivant >= 0x80 and suivant < 0xC0 then fin = fin - 1 else break end
  end
  return t:sub(1, fin)
end

-- Un titre sûr : sans tabulation, retour à la ligne ni autre caractère de contrôle,
-- sans « | » (les codes de couleur et de lien du jeu), espaces resserrés, coupé.
function ns.nettoyerTitre(titre, max)
  local t = tostring(titre or "")
  t = t:gsub("%c", " ")
  t = t:gsub("|", "")
  t = t:gsub("%s+", " ")
  t = t:gsub("^ ", ""):gsub(" $", "")
  return (couper(t, max or TITRE_MAX):gsub(" $", ""))
end

-- Le message à envoyer pour une balise (x et y entre 0 et 1), ou nil si elle est invalide.
-- Le « (de Nom) » d'une balise reçue n'est pas renvoyé tel quel.
function ns.coderBalise(carte, x, y, titre)
  if type(carte) ~= "number" or carte <= 0 or carte % 1 ~= 0 or carte > 9999999 then return nil end
  if type(x) ~= "number" or type(y) ~= "number" or x ~= x or y ~= y or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
  local t = ns.nettoyerTitre(titre)
  t = t:gsub("%s*%(de [^%)]*%)$", "")
  return string.format("B\t%d\t%.4f\t%.4f\t%s", carte, x, y, t)
end

-- Lit un message reçu. Rend { carte, x, y, titre } (titre nil s'il est vide),
-- ou nil et la raison quand le message est mal formé.
function ns.decoderBalise(texte)
  if type(texte) ~= "string" then return nil, "pas du texte" end
  if #texte > 255 then return nil, "trop long" end
  local carte, x, y, titre = texte:match("^B\t(%d+)\t([%d%.]+)\t([%d%.]+)\t(.*)$")
  if not carte then carte, x, y = texte:match("^B\t(%d+)\t([%d%.]+)\t([%d%.]+)$"); titre = "" end
  if not carte then return nil, "mal formé" end
  if #carte > 7 then return nil, "carte invalide" end
  carte, x, y = tonumber(carte), tonumber(x), tonumber(y)
  if not carte or carte <= 0 then return nil, "carte invalide" end
  if not x or not y or x < 0 or x > 1 or y < 0 or y > 1 then return nil, "coordonnées invalides" end
  titre = ns.nettoyerTitre(titre)
  return { carte = carte, x = x, y = y, titre = titre ~= "" and titre or nil }
end

-- Le titre d'une balise reçue : « Le moulin (de Anna) ».
function ns.titreRecu(titre, nom)
  local t = ns.nettoyerTitre(titre)
  if t == "" then t = "Balise" end
  local n = ns.nettoyerTitre(nom, 40)
  if n == "" then n = "?" end
  return t .. " (de " .. n .. ")"
end

-- Même carte et même point à 0,5 % près.
function ns.memeBalise(a, b)
  if not (a and b) or a.carte ~= b.carte then return false end
  return math.abs(a.x - b.x) <= TOLERANCE + 1e-9 and math.abs(a.y - b.y) <= TOLERANCE + 1e-9
end

function ns.dejaConnue(balises, b)
  for _, x in ipairs(balises or {}) do
    if ns.memeBalise(x, b) then return true end
  end
  return false
end

-- Le canal du groupe (instance, raid, groupe), nil si on est seul.
function ns.canalGroupe(instance, raid, groupe)
  if instance then return "INSTANCE_CHAT" end
  if raid then return "RAID" end
  if groupe then return "PARTY" end
  return nil
end

-- La catégorie « groupe d'instance » du jeu : sa constante, ou 2 quand le jeu ne la donne pas.
function ns.categorieInstance(constante)
  return type(constante) == "number" and constante or 2
end

-- Une balise reçue ne fait pas lâcher la balise déjà suivie ; une balise posée à la main, si.
function ns.suivieApresAjout(suivie, recue)
  if recue then return suivie end
  return nil
end

-- L'envoi d'un message d'addon est-il parti ? Le jeu rend un code (0 = réussi), parfois vrai
-- ou rien selon la version ; pcall a pu échouer.
function ns.envoiParti(ok, resultat)
  if not ok then return false end
  return resultat == nil or resultat == true or resultat == 0
end

-- La phrase du chat après l'envoi au groupe.
function ns.texteEnvoi(partis, prevus)
  if partis <= 0 then return "aucune balise n'a pu être envoyée au groupe." end
  if partis < prevus then return partis .. " balise(s) sur " .. prevus .. " envoyée(s) au groupe." end
  return partis .. " balise(s) envoyée(s) au groupe."
end

if not CreateFrame or not C_Map then return end -- hors jeu : la suite ne sert qu'en jeu

-- ---------------------------------------------------------------------------
-- Positions dans le monde
-- ---------------------------------------------------------------------------

local function versMonde(carte, x, y)
  if not (C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
  local ok, continent, pos = pcall(C_Map.GetWorldPosFromMapPos, carte, CreateVector2D(x, y))
  if not ok or not continent or not pos then return nil end
  local wx, wy = pos:GetXY()
  return { continent = continent, x = wx, y = wy }
end

local function ici()
  if not C_Map.GetBestMapForUnit then return nil end
  local carte = C_Map.GetBestMapForUnit("player")
  if not carte or estSecret(carte) then return nil end
  local ok, pos = pcall(C_Map.GetPlayerMapPosition, carte, "player")
  if not ok or not pos then return nil end
  local x, y = pos:GetXY()
  if not x or estSecret(x) or estSecret(y) or (x == 0 and y == 0) then return nil end
  return versMonde(carte, x, y), carte, x, y
end

local function nomCarte(carte)
  local info = C_Map.GetMapInfo and C_Map.GetMapInfo(carte)
  return info and info.name or ("carte " .. tostring(carte))
end

-- Toutes les zones connues, pour « /way Elwynn 45 67 ».
local cartesConnues
local function cartes()
  if cartesConnues then return cartesConnues end
  cartesConnues = {}
  local vus = {}
  local function parcourir(id, profondeur)
    if profondeur > 6 or vus[id] then return end
    vus[id] = true
    local info = C_Map.GetMapInfo(id)
    if info and info.name and info.mapType and info.mapType >= 3 then
      cartesConnues[#cartesConnues + 1] = { id = id, nom = info.name }
    end
    local enfants = C_Map.GetMapChildrenInfo and C_Map.GetMapChildrenInfo(id)
    for _, e in ipairs(enfants or {}) do parcourir(e.mapID, profondeur + 1) end
  end
  parcourir(946, 0) -- le Cosmos (Retail)
  parcourir(947, 0) -- Azeroth
  return cartesConnues
end

-- ---------------------------------------------------------------------------
-- Les balises
-- ---------------------------------------------------------------------------

local suivie -- la balise suivie en ce moment
local majListe

local function texteBalise(b)
  return (b.titre or "Balise") .. "  |cff888888" .. nomCarte(b.carte) .. " "
    .. string.format("%.1f, %.1f", b.x * 100, b.y * 100) .. "|r"
end

local function poserEpingle(b)
  if not (db.epingle and C_Map.SetUserWaypoint and UiMapPoint) then return end
  if not b then
    if C_Map.ClearUserWaypoint then pcall(C_Map.ClearUserWaypoint) end
    return
  end
  if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(b.carte) then return end
  pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(b.carte, b.x, b.y))
  if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
end

local function ajouter(carte, x, y, titre, recue)
  local b = { carte = carte, x = x, y = y, titre = titre }
  b.monde = versMonde(carte, x, y)
  table.insert(perso.balises, b)
  ns.reglages.dire("balise : " .. texteBalise(b))
  suivie = ns.suivieApresAjout(suivie, recue)
  if majListe then ns.reglages.majFenetre() end
  return b
end

local function retirer(b)
  for i, x in ipairs(perso.balises) do
    if x == b then table.remove(perso.balises, i) break end
  end
  if suivie == b then suivie = nil; poserEpingle(nil) end
  ns.reglages.majFenetre()
end

local function toutEffacer()
  perso.balises = {}
  suivie = nil
  poserEpingle(nil)
  ns.reglages.majFenetre()
end

-- Pour les autres addons (Livres de bibliothèque, Alerte rare…).
function GPS_Ajouter(carte, x, y, titre)
  if not db or not db.actif or not carte or not x or not y then return nil end
  return ajouter(carte, x, y, titre)
end

-- ---------------------------------------------------------------------------
-- Le partage avec le groupe (même principe que Quêtes du groupe et Rapport d'erreurs :
-- un message d'addon sur le canal du groupe, préfixe enregistré une fois)
-- ---------------------------------------------------------------------------

local PREFIXE = "GPSValentin"
local MAX_ENVOI = 20   -- balises envoyées d'un coup, au plus
local MAX_BALISES = 100 -- au-delà, on n'ajoute plus de balise reçue

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
  pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIXE)
end

local function canalGroupe()
  return ns.canalGroupe(IsInGroup and IsInGroup(ns.categorieInstance(LE_PARTY_CATEGORY_INSTANCE)),
    IsInRaid and IsInRaid(), IsInGroup and IsInGroup())
end

-- Envoie la balise suivie, ou toutes les balises, aux membres du groupe.
-- Une balise par message, un toutes les 0,5 s (le jeu limite le débit).
local function envoyerAuGroupe(toutes)
  if not db.actif then ns.reglages.dire("GPS est coupé.") return end
  if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then ns.reglages.dire("envoi impossible sur cette version du jeu.") return end
  local canal = canalGroupe()
  if not canal then ns.reglages.dire("tu n'es pas dans un groupe.") return end
  local liste = {}
  if toutes then
    for _, b in ipairs(perso.balises) do liste[#liste + 1] = b end
  elseif suivie then
    liste[1] = suivie
  end
  local messages = {}
  for _, b in ipairs(liste) do
    local m = ns.coderBalise(b.carte, b.x, b.y, b.titre)
    if m and #messages < MAX_ENVOI then messages[#messages + 1] = m end
  end
  if #messages == 0 then
    ns.reglages.dire(toutes and "aucune balise à envoyer." or "aucune balise suivie à envoyer (pose-en une avec /way).")
    return
  end
  local partis = 0
  for i, m in ipairs(messages) do
    C_Timer.After((i - 1) * 0.5, function()
      if ns.envoiParti(pcall(C_ChatInfo.SendAddonMessage, PREFIXE, m, canal)) then partis = partis + 1 end
      if i == #messages then ns.reglages.dire(ns.texteEnvoi(partis, #messages)) end
    end)
  end
end

-- Une balise reçue d'un membre du groupe : ajoutée avec « (de Nom) », sans doublon,
-- jamais venant de soi-même.
local function surMessage(prefixe, texte, canalMessage, auteur)
  -- Les valeurs secrètes d'abord : on ne les compare à rien.
  if estSecret(prefixe) or estSecret(texte) or estSecret(canalMessage) or estSecret(auteur) then return end
  if prefixe ~= PREFIXE or not db or not db.actif or not db.accepterGroupe then return end
  if canalMessage ~= "PARTY" and canalMessage ~= "RAID" and canalMessage ~= "INSTANCE_CHAT" then return end
  if type(auteur) ~= "string" then return end
  local nom = Ambiguate and Ambiguate(auteur, "none") or auteur
  if nom == UnitName("player") then return end
  local b = ns.decoderBalise(texte)
  if not b then return end
  if not (C_Map.GetMapInfo and C_Map.GetMapInfo(b.carte)) then return end
  if #perso.balises >= MAX_BALISES or ns.dejaConnue(perso.balises, b) then return end
  ajouter(b.carte, b.x, b.y, ns.titreRecu(b.titre, nom), true)
end

local ecouteGroupe = CreateFrame("Frame")
ecouteGroupe:RegisterEvent("CHAT_MSG_ADDON")
ecouteGroupe:SetScript("OnEvent", function(_, _, ...) surMessage(...) end)

-- ---------------------------------------------------------------------------
-- La flèche
-- ---------------------------------------------------------------------------

local fleche = CreateFrame("Frame", "GPSFleche", UIParent)
fleche:SetSize(70, 86)
fleche:SetPoint("TOP", UIParent, "TOP", 0, -160)
fleche:SetMovable(true)
fleche:SetClampedToScreen(true)
fleche:EnableMouse(true)
fleche:RegisterForDrag("LeftButton")
fleche:SetScript("OnDragStart", fleche.StartMoving)
fleche:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local p, _, rp, x, y = self:GetPoint()
  db.positionFleche = { p, rp, x, y }
end)
fleche:SetScript("OnMouseUp", function(_, bouton)
  if bouton == "RightButton" and suivie and not suivie.auto then
    ns.reglages.dire("balise retirée : " .. (suivie.titre or "Balise"))
    retirer(suivie)
  end
end)
fleche:Hide()
local image = fleche:CreateTexture(nil, "ARTWORK")
image:SetSize(48, 48)
image:SetPoint("TOP")
image:SetTexture("Interface\\Minimap\\MiniMap-QuestArrow")
local titreFleche = fleche:CreateFontString(nil, "OVERLAY", "GameFontNormal")
titreFleche:SetPoint("TOP", image, "BOTTOM", 0, -2)
titreFleche:SetWidth(220)
local infoFleche = fleche:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
infoFleche:SetPoint("TOP", titreFleche, "BOTTOM", 0, -1)
fleche:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
  GameTooltip:AddLine("GPS")
  GameTooltip:AddLine("Glisser : déplacer la flèche\nClic droit : retirer cette balise", 1, 1, 1)
  GameTooltip:Show()
end)
fleche:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function placerFleche()
  fleche:SetScale((db.taille or 160) / 100)
  fleche:ClearAllPoints()
  local p = db.positionFleche
  if p then fleche:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else fleche:SetPoint("TOP", UIParent, "TOP", 0, -160) end
end

-- ---------------------------------------------------------------------------
-- Sans balise : la quête suivie, ou l'épingle posée sur la carte du jeu
-- ---------------------------------------------------------------------------

-- La quête à suivre : celle choisie dans le suivi des objectifs (super-suivi),
-- sinon la première de la liste de suivi.
-- Les quêtes candidates : la quête sélectionnée dans le suivi des objectifs s'il
-- y en a une (et elle seule), sinon les suivies puis le reste du journal (on
-- prendra la première dont le jeu donne la place).
local function quetesCandidates()
  local l, vues = {}, {}
  local function ajouter(id) if id and id ~= 0 and not vues[id] then vues[id] = true; l[#l + 1] = id end end
  -- Une quête sélectionnée dans le suivi des objectifs (comme TomTom) : c'est
  -- elle, et seulement elle.
  local choisie = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID()
  if choisie and choisie ~= 0 then return { choisie }, true end
  if C_QuestLog.GetNumQuestWatches and C_QuestLog.GetQuestIDForQuestWatchIndex then
    for i = 1, C_QuestLog.GetNumQuestWatches() or 0 do ajouter(C_QuestLog.GetQuestIDForQuestWatchIndex(i)) end
  end
  if C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
    for i = 1, C_QuestLog.GetNumQuestLogEntries() or 0 do
      local info = C_QuestLog.GetInfo(i)
      if info and not info.isHeader and info.questID then ajouter(info.questID) end
    end
  end
  return l
end
local diagnostic = "pas encore calculé"

-- Où aller pour cette quête : le prochain point du jeu (portail, bateau…), sinon
-- la marque de la quête sur la carte où tu es ou sur ses cartes parentes.
local function lieuQuete(id, carteIci)
  if C_QuestLog.GetNextWaypoint then
    local ok, carte, x, y = pcall(C_QuestLog.GetNextWaypoint, id)
    if ok and carte and x and y then return carte, x, y end
  end
  local carte = carteIci
  for _ = 1, 4 do
    if not carte or not C_QuestLog.GetQuestsOnMap then break end
    for _, q in ipairs(C_QuestLog.GetQuestsOnMap(carte) or {}) do
      if q.questID == id and q.x and q.y then return carte, q.x, q.y end
    end
    local info = C_Map.GetMapInfo(carte)
    carte = info and info.parentMapID
  end
end

local auto, autoCalcule = nil, 0
local function cibleAuto(carteIci)
  if GetTime() - autoCalcule < 0.5 then return auto end
  autoCalcule = GetTime()
  auto = nil
  diagnostic = "aucune balise ni épingle, et « suivre la quête » est décoché"
  -- Une épingle que tu as posée toi-même sur la carte du jeu.
  if db.suivreEpingle and C_Map.HasUserWaypoint and C_Map.HasUserWaypoint() then
    local p = C_Map.GetUserWaypoint()
    if p and p.position then
      local x, y = p.position:GetXY()
      auto = { titre = "Épingle de la carte", carte = p.uiMapID, x = x, y = y, auto = true }
    end
  end
  -- La quête suivie.
  if not auto and db.suivreQuete then
    local quetes, selectionnee = quetesCandidates()
    local id, carte, x, y
    for _, q in ipairs(quetes) do
      carte, x, y = lieuQuete(q, carteIci)
      if carte then id = q break end
    end
    if not carte then
      local titre = selectionnee and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(quetes[1])
      diagnostic = selectionnee and ("la quête sélectionnée « " .. (titre or "?") .. " » n'a pas de place donnée par le jeu")
        or #quetes == 0 and "aucune quête dans ton journal"
        or (#quetes .. " quête(s), mais le jeu ne donne la place d'aucune (pas de marque de quête sur la carte ici)")
    end
    if carte then
      local titre = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id) or "Quête"
      local fini = C_QuestLog.IsComplete and C_QuestLog.IsComplete(id)
      auto = { titre = (fini and "Rendre : " or "") .. titre, carte = carte, x = x, y = y, auto = true }
    end
  end
  if auto then auto.monde = versMonde(auto.carte, auto.x, auto.y) end
  return auto
end

local derniere = { d = nil, t = nil, vitesse = nil }
local moteur = CreateFrame("Frame")
local attente = 0
moteur:SetScript("OnUpdate", function(_, ecoule)
  attente = attente + ecoule
  if attente < 0.1 then return end
  attente = 0
  if not db or not db.actif then diagnostic = "GPS coupé"; fleche:Hide() return end
  local moi, carteIci = ici()
  local b, d
  if #perso.balises > 0 then
    -- Une balise posée avant que le monde soit chargé : sa position se calcule maintenant.
    for _, x in ipairs(perso.balises) do
      if not x.monde then x.monde = versMonde(x.carte, x.x, x.y) end
    end
    b, d = ns.choisir(perso.balises, moi, db.plusProche)
  else
    b = cibleAuto(carteIci)
    if b and b.monde and moi and b.monde.continent == moi.continent then
      d = ns.distance(moi.x, moi.y, b.monde.x, b.monde.y)
    end
  end
  if b ~= suivie and not (b and suivie and b.auto and suivie.auto and b.titre == suivie.titre) then
    suivie = b
    derniere.d, derniere.vitesse = nil, nil
    -- L'épingle du jeu ne suit que nos balises : la quête a déjà sa marque.
    if not (b and b.auto) then poserEpingle(b) end
  end
  if not b then
    if #perso.balises > 0 then diagnostic = "tes balises sont sur un autre continent" end
    fleche:Hide() return
  end
  if not d then
    diagnostic = moi and "« " .. (b.titre or "?") .. " » est sur un autre continent" or "ta position est inconnue ici (donjon ?)"
    fleche:Hide() return
  end
  diagnostic = "suit « " .. (b.titre or "Balise") .. " », " .. math.floor(d + 0.5) .. " m"

  -- Arrivé (seulement pour nos balises : une quête se termine dans le jeu).
  if d < 10 and not b.auto then
    ns.reglages.dire("arrivé : " .. (b.titre or "balise") .. ".")
    if db.arrivee then
      if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.MAP_PING or 3175) end
      retirer(b)
    end
    return
  end

  -- La vitesse (lissée) pour le temps restant.
  local maintenant = GetTime()
  if derniere.d and derniere.t and maintenant > derniere.t then
    local v = (derniere.d - d) / (maintenant - derniere.t)
    derniere.vitesse = derniere.vitesse and (derniere.vitesse * 0.85 + v * 0.15) or v
  end
  derniere.d, derniere.t = d, maintenant

  if not db.fleche then diagnostic = diagnostic .. " (flèche décochée)"; fleche:Hide() return end
  local orientation = GetPlayerFacing and GetPlayerFacing()
  if orientation and not estSecret(orientation) then
    local a = ns.angle(moi.x, moi.y, b.monde.x, b.monde.y, orientation)
    image:SetRotation(a)
    -- Verte quand tu vas dans la bonne direction, jaune sinon.
    local ecart = math.abs(((a + math.pi) % (2 * math.pi)) - math.pi)
    if ecart < 0.3 then image:SetVertexColor(0.2, 1, 0.2) else image:SetVertexColor(1, 0.82, 0) end
    image:Show()
  else
    image:Hide()
  end
  titreFleche:SetText(b.titre or "Balise")
  local temps = ns.tempsRestant(d, derniere.vitesse)
  infoFleche:SetText(math.floor(d + 0.5) .. " m" .. (temps and ("  ·  " .. temps) or ""))
  fleche:Show()
end)

-- ---------------------------------------------------------------------------
-- Ctrl + clic droit sur la carte du monde
-- ---------------------------------------------------------------------------

local carteAccrochee = false
local function accrocherCarte()
  if carteAccrochee or not WorldMapFrame or not WorldMapFrame.ScrollContainer then return end
  carteAccrochee = true
  WorldMapFrame.ScrollContainer:HookScript("OnMouseUp", function(self, bouton)
    if bouton ~= "RightButton" or not IsControlKeyDown() or not db.actif then return end
    local carte = WorldMapFrame:GetMapID()
    local ok, x, y = pcall(self.GetNormalizedCursorPosition, self)
    if ok and carte and x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
      ajouter(carte, x, y, "Balise sur la carte")
    end
  end)
end

-- ---------------------------------------------------------------------------
-- Réglages
-- ---------------------------------------------------------------------------

ns.reglages = ns.creerReglages({
  titre = "GPS",
  icone = "Interface\\Icons\\INV_Misc_Map_01",
  nomDB = "GPSDB",
  defauts = DEFAUTS,
  options = {
    { titre = "GPS" },
    { cle = "actif", libelle = "Activer GPS",
      aide = "Balises par /way 45.2 67.8 Titre, ou Ctrl + clic droit sur la carte du monde." },
    { cle = "fleche", libelle = "La flèche à l'écran",
      aide = "Direction (verte quand tu vas dans le bon sens), distance et temps restant, même au-delà de 1 000 m. Glisser pour la déplacer, clic droit pour retirer la balise." },
    { cle = "taille", type = "nombre", libelle = "Taille de la flèche", min = 60, max = 300, pas = 10,
      format = function(v) return v .. " %" end,
      aide = "Glisse la flèche à l'écran pour la placer où tu veux ; « Replacer la flèche » la remet en haut." },
    { cle = "epingle", libelle = "Épingle du jeu sur la balise suivie",
      aide = "La balise suivie apparaît aussi sur la carte et la minimap comme une épingle du jeu." },
    { cle = "suivreQuete", libelle = "Sans balise, suivre la quête suivie",
      aide = "La quête choisie dans le suivi des objectifs (sinon la première suivie) : son objectif, ou le PNJ à qui la rendre quand elle est finie. Passe aussi par les portails et bateaux que le jeu indique." },
    { cle = "suivreEpingle", libelle = "Sans balise, suivre l'épingle de la carte du jeu",
      aide = "L'épingle que tu poses toi-même sur la carte (clic sur la carte du jeu). Elle passe avant la quête." },
    { cle = "plusProche", libelle = "Suivre la balise la plus proche",
      aide = "Décoché : la dernière balise posée." },
    { cle = "arrivee", libelle = "Son et retrait de la balise à l'arrivée",
      aide = "À moins de 10 m, la balise disparaît et la suivante prend le relais." },
    { cle = "accepterGroupe", libelle = "Accepter les balises de mon groupe",
      aide = "Quand un membre de ton groupe t'envoie une balise (onglet Balises, ou /way envoyer), elle est ajoutée avec « (de Nom) » dans son titre, sans doublon. Jamais une balise venant de toi-même." },
    { titre = "Icône" },
    { cle = "minimap", libelle = "Icône à part autour de la minimap",
      aide = "En plus de la ligne dans l'icône commune des addons de Valentin." },
  },
  boutons = {
    { texte = "Balise ici", aide = "Pose une balise là où tu es (pour revenir plus tard).", action = function()
      local _, carte, x, y = ici()
      if carte then ajouter(carte, x, y, "Ici") else ns.reglages.dire("ta position est inconnue ici.") end
    end },
    { texte = "Tout effacer", aide = "Retire toutes les balises.", action = toutEffacer },
    { texte = "Replacer la flèche", aide = "Remet la flèche en haut de l'écran.", action = function()
      db.positionFleche = nil; placerFleche()
    end },
  },
  ongletContenu = "Balises",
  contenu = function(f, y)
    -- Ce que fait la flèche en ce moment, et sinon pourquoi elle est cachée.
    local diag = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    diag:SetPoint("TOPLEFT", 20, y - 4)
    diag:SetWidth(390)
    diag:SetJustifyH("LEFT")
    C_Timer.NewTicker(1, function()
      if diag:IsVisible() then diag:SetText("|cffffd200En ce moment :|r " .. diagnostic) end
    end)
    y = y - 34
    local maj
    y, maj = ns.creerListe(f, y, {
      titre = "Balises", vide = "Aucune balise. /way 45.2 67.8 Titre",
      lignes = function()
        local l = {}
        for _, b in ipairs(perso and perso.balises or {}) do
          l[#l + 1] = { texte = (b == suivie and "|cff20ff20> |r" or "") .. texteBalise(b), retirer = function() retirer(b) end }
        end
        return l
      end,
    })
    majListe = maj
    local bGroupe = ns.creerBouton(f, "Envoyer au groupe", "Envoie la balise suivie (celle marquée d'un « > ») aux membres de ton groupe ou de ton raid. Eux la reçoivent s'ils ont GPS et l'option « Accepter les balises de mon groupe ».", function() envoyerAuGroupe(false) end, 150)
    bGroupe:SetPoint("TOPLEFT", 16, y - 4)
    local bToutes = ns.creerBouton(f, "Envoyer toutes", "Envoie toutes tes balises (20 au plus) aux membres de ton groupe ou de ton raid.", function() envoyerAuGroupe(true) end, 130)
    bToutes:SetPoint("LEFT", bGroupe, "RIGHT", 8, 0)
    y = y - 34
    return y, maj
  end,
  astuce = "Pour les autres addons : GPS_Ajouter(carte, x, y, titre). Livres de bibliothèque s'en sert pour ses balises.",
  auChargement = function(d)
    db = d
    GPSPerso = GPSPerso or {}
    perso = GPSPerso
    perso.balises = perso.balises or {}
    -- Les positions dans le monde ne sont pas gardées : on les recalcule.
    for _, b in ipairs(perso.balises) do b.monde = nil end
    placerFleche()
  end,
  surChangement = function(d)
    placerFleche()
    if not d.actif or not d.epingle then poserEpingle(nil) end
    suivie = nil
  end,
})

local ecouteur = CreateFrame("Frame")
ecouteur:RegisterEvent("PLAYER_ENTERING_WORLD")
ecouteur:RegisterEvent("ADDON_LOADED")
ecouteur:SetScript("OnEvent", function(_, evenement, nom)
  if evenement == "ADDON_LOADED" and nom ~= "Blizzard_WorldMap" then return end
  accrocherCarte()
  if evenement == "PLAYER_ENTERING_WORLD" and perso then
    for _, b in ipairs(perso.balises) do b.monde = versMonde(b.carte, b.x, b.y) end
  end
end)

local function commandeWay(message)
  local m = strtrim(message or "")
  local bas = m:lower()
  if bas == "" or bas == "liste" then ns.reglages.montrer() return end
  if bas == "etat" or bas == "état" then ns.reglages.dire("en ce moment : " .. diagnostic) return end
  if bas == "effacer" or bas == "reset" then toutEffacer() ns.reglages.dire("balises effacées.") return end
  if bas == "envoyer" then envoyerAuGroupe(false) return end
  if bas == "envoyer tout" or bas == "envoyer toutes" then envoyerAuGroupe(true) return end
  local _, carte = ici()
  local r, erreur = ns.lireWay(m, carte, cartes())
  if not r then ns.reglages.dire(erreur) return end
  ajouter(r.carte, r.x, r.y, r.titre)
end

SLASH_GPSWAY1 = "/way"
SLASH_GPSWAY2 = "/balise"
SlashCmdList.GPSWAY = commandeWay
SLASH_GPS1 = "/gps"
SlashCmdList.GPS = function(message)
  local c = strtrim(message or ""):lower()
  if c == "on" or c == "off" then
    if (c == "on") ~= (db.actif and true or false) then ns.reglages.basculer() end
  elseif c == "" or c == "options" or c == "reglages" then
    ns.reglages.montrer()
  elseif not ns.reglages.basculerOption(c) then
    commandeWay(message)
  end
end
