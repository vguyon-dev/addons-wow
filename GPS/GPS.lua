-- ============================================================================
-- GPS : des balises et une flèche pour y aller (comme TomTom, réécrit à notre
-- façon, sans reprendre son code).
--
--   /way 45.2 67.8 Titre        une balise sur la carte où tu es
--   /way Elwynn 45 67 Titre     une balise sur une autre carte (nom de la zone)
--   Ctrl + clic droit sur la carte du monde : une balise à cet endroit
--   /way effacer                retire toutes les balises
--   /gps                        les réglages, avec la liste des balises
--
-- Une flèche déplaçable montre la direction, la distance et le temps restant,
-- même au-delà de 1 000 m et depuis une autre zone du même continent. Arrivé à
-- moins de 10 m : un son, la balise disparaît et la suivante prend le relais.
-- La balise suivie est aussi posée comme épingle du jeu (carte et minimap).
-- Pour les autres addons : GPS_Ajouter(carte, x, y, titre) avec x, y entre 0 et 1.
-- ============================================================================

local NOM_ADDON, ns = ...

local DEFAUTS = {
  actif = true,
  fleche = true,        -- la flèche à l'écran
  epingle = true,       -- la balise suivie devient aussi l'épingle du jeu
  plusProche = true,    -- suivre la balise la plus proche (sinon la dernière posée)
  arrivee = true,       -- son et retrait de la balise à l'arrivée
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

local function ajouter(carte, x, y, titre)
  local b = { carte = carte, x = x, y = y, titre = titre }
  b.monde = versMonde(carte, x, y)
  table.insert(perso.balises, b)
  ns.reglages.dire("balise : " .. texteBalise(b))
  suivie = nil
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
  if bouton == "RightButton" and suivie then
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
  fleche:ClearAllPoints()
  local p = db.positionFleche
  if p then fleche:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else fleche:SetPoint("TOP", UIParent, "TOP", 0, -160) end
end

local derniere = { d = nil, t = nil, vitesse = nil }
local moteur = CreateFrame("Frame")
local attente = 0
moteur:SetScript("OnUpdate", function(_, ecoule)
  attente = attente + ecoule
  if attente < 0.1 then return end
  attente = 0
  if not db or not db.actif or #perso.balises == 0 then fleche:Hide() return end
  local moi = ici()
  -- Une balise posée avant que le monde soit chargé : sa position se calcule maintenant.
  for _, x in ipairs(perso.balises) do
    if not x.monde then x.monde = versMonde(x.carte, x.x, x.y) end
  end
  local b, d = ns.choisir(perso.balises, moi, db.plusProche)
  if b ~= suivie then
    suivie = b
    derniere.d, derniere.vitesse = nil, nil
    poserEpingle(b)
  end
  if not b or not d then fleche:Hide() return end

  -- Arrivé.
  if d < 10 then
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

  if not db.fleche then fleche:Hide() return end
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
    { cle = "epingle", libelle = "Épingle du jeu sur la balise suivie",
      aide = "La balise suivie apparaît aussi sur la carte et la minimap comme une épingle du jeu." },
    { cle = "plusProche", libelle = "Suivre la balise la plus proche",
      aide = "Décoché : la dernière balise posée." },
    { cle = "arrivee", libelle = "Son et retrait de la balise à l'arrivée",
      aide = "À moins de 10 m, la balise disparaît et la suivante prend le relais." },
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
  contenu = function(f, y)
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
  if bas == "effacer" or bas == "reset" then toutEffacer() ns.reglages.dire("balises effacées.") return end
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
