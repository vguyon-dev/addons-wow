-- ============================================================================
-- Quêtes auto : accepte et rend les quêtes à ta place.
--
-- Ce qui le distingue d'AutoQuests :
--  1. Chez un PNJ, il REND d'abord les quêtes finies, puis ACCEPTE les nouvelles.
--     Une quête en cours pas encore finie n'est jamais ouverte, donc elle ne
--     bloque plus l'acceptation des autres.
--  2. Il choisit la récompense : une amélioration pour toi, sinon l'objet qui se
--     revend le plus cher.
--  3. Des filtres : quêtes grises, journalières, payantes, PNJ et quêtes ignorés.
--  4. Un bouton à l'écran et un raccourci clavier pour le couper.
--  5. Il passe les cinématiques déjà vues une fois.
--
-- Maintenir Maj, Ctrl ou Alt en parlant au PNJ met l'addon en pause.
-- ============================================================================

local NOM_ADDON, ns = ...
local estSecret = issecretvalue or function() return false end

-- Réglages par défaut, recopiés dans QuetesAutoDB au premier chargement.
local DEFAUTS = {
  actif = true,            -- interrupteur général
  accepter = true,         -- accepter les quêtes tout seul
  rendre = true,           -- rendre les quêtes finies tout seul
  pauseTouches = true,     -- Maj, Ctrl ou Alt enfoncé = pause
  minimap = true,          -- icône autour de la minimap
  angleMinimap = 225,      -- position de l'icône sur le tour de la minimap, en degrés
  recompenseAuto = true,   -- choisir la récompense seul (sinon te laisser choisir)
  grises = true,           -- ignorer les quêtes grises (trop faciles)
  journalieres = false,    -- ignorer les journalières et hebdomadaires
  payantes = true,         -- ne pas rendre une quête qui coûte de l'or
  cinematiques = true,     -- passer les cinématiques déjà vues
  bouton = true,           -- afficher le bouton
  pnjIgnores = {},         -- [idPNJ] = nom
  quetesIgnorees = {},     -- [idQuête] = titre
  vues = {},               -- cinématiques déjà vues
}

local db

local function dire(texte)
  print("|cffffd200Quêtes auto|r : " .. texte)
end

-- C_Item d'abord, avec un repli sur l'ancienne fonction globale (règle du dépôt).
local infoObjet = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local function niveauObjet(lien)
  if C_Item and C_Item.GetDetailedItemLevelInfo then
    return C_Item.GetDetailedItemLevelInfo(lien) or 0
  end
  return (select(4, infoObjet(lien))) or 0
end

-- ---------------------------------------------------------------------------
-- Partie « logique pure » : aucune fonction du jeu, donc testable hors jeu
-- (voir tests/QuetesAuto_simu.lua).
-- ---------------------------------------------------------------------------

-- Une quête disponible passe-t-elle les filtres ?
-- q : { questID, isTrivial, frequency } ; frequency 1 = journalière, 2 = hebdo.
function ns.accepteQuete(q, reglages, ignorees)
  if q.questID and ignorees[q.questID] then return false end
  if reglages.grises and q.isTrivial then return false end
  if reglages.journalieres and q.frequency and q.frequency > 0 then return false end
  return true
end

-- Que faire chez ce PNJ ? Rend la première quête finie, sinon accepte la
-- première quête qui passe les filtres. Une quête en cours non finie est sautée.
-- Renvoie "rendre", index ou "accepter", index, ou nil s'il n'y a rien à faire.
-- Les réglages « rendre » et « accepter » coupent chacun leur moitié.
function ns.choisirAction(actives, disponibles, reglages, ignorees)
  if reglages.rendre ~= false then
    for i, q in ipairs(actives) do
      if q.isComplete then return "rendre", i end
    end
  end
  if reglages.accepter ~= false then
    for i, q in ipairs(disponibles) do
      if ns.accepteQuete(q, reglages, ignorees) then return "accepter", i end
    end
  end
  return nil
end

-- Quelle récompense prendre ? candidats : { gain = niveaux gagnés (ou nil si
-- pas une amélioration), vente = prix de revente }. Renvoie l'index choisi.
function ns.choisirRecompense(candidats)
  local meilleur, meilleurGain = nil, 0
  for i, c in ipairs(candidats) do
    if c.gain and c.gain > meilleurGain then meilleur, meilleurGain = i, c.gain end
  end
  if meilleur then return meilleur, "amélioration" end
  local plusCher, prix = 1, -1
  for i, c in ipairs(candidats) do
    if (c.vente or 0) > prix then plusCher, prix = i, c.vente or 0 end
  end
  return plusCher, "revente"
end

-- ---------------------------------------------------------------------------
-- Choix de la récompense en jeu
-- ---------------------------------------------------------------------------

-- Emplacements d'équipement par type d'objet.
local EMPLACEMENTS = {
  INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 },
  INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 },
  INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 },
  INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
  INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 },
  INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 },
  INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
  INVTYPE_RANGED = { 16 }, INVTYPE_RANGEDRIGHT = { 16 },
}

-- Type d'armure de chaque classe : 1 tissu, 2 cuir, 3 mailles, 4 plaques.
local ARMURE = {
  MAGE = 1, PRIEST = 1, WARLOCK = 1,
  ROGUE = 2, DRUID = 2, MONK = 2, DEMONHUNTER = 2,
  HUNTER = 3, SHAMAN = 3, EVOKER = 3,
  WARRIOR = 4, PALADIN = 4, DEATHKNIGHT = 4,
}

-- Combien de niveaux d'objet cette récompense ferait-elle gagner ? nil si ce
-- n'est pas une amélioration utilisable par ta classe.
local function gainPour(lien)
  local _, _, _, _, _, _, _, _, equipLoc, _, _, classeObjet, sousClasse = infoObjet(lien)
  local slots = equipLoc and EMPLACEMENTS[equipLoc]
  if not slots then return nil end
  -- Armure de corps (classe d'objet 4, sous-classes 1 à 4) : seulement la tienne.
  if classeObjet == 4 and sousClasse and sousClasse >= 1 and sousClasse <= 4
     and equipLoc ~= "INVTYPE_CLOAK" then
    local _, classe = UnitClass("player")
    if ARMURE[classe] and ARMURE[classe] ~= sousClasse then return nil end
  end
  -- Armes et boucliers : seulement si le jeu dit que tu peux t'en servir.
  if classeObjet == 2 or (classeObjet == 4 and sousClasse == 6) then
    local id = C_Item and C_Item.GetItemInfoInstant and C_Item.GetItemInfoInstant(lien)
    if not (id and C_PlayerInfo and C_PlayerInfo.CanUseItem and C_PlayerInfo.CanUseItem(id)) then
      return nil
    end
  end
  local niveau = niveauObjet(lien)
  -- On compare à la pièce portée la plus faible (pour les bagues et bijoux).
  local porte
  for _, slot in ipairs(slots) do
    local lienPorte = GetInventoryItemLink("player", slot)
    local n = lienPorte and niveauObjet(lienPorte) or 0
    if not porte or n < porte then porte = n end
  end
  local gain = niveau - (porte or 0)
  return gain > 0 and gain or nil
end

local essais = 0
local function prendreRecompense()
  local nombre = GetNumQuestChoices()
  if nombre <= 1 then
    GetQuestReward(nombre)
    return
  end
  if not db.recompenseAuto then
    dire("plusieurs récompenses, à toi de choisir.")
    PlaySound(5274, "master")
    return
  end
  local candidats = {}
  for i = 1, nombre do
    local lien = GetQuestItemLink("choice", i)
    if not lien or not infoObjet(lien) then
      -- Le jeu n'a pas encore les infos de l'objet : on réessaie un peu plus tard.
      essais = essais + 1
      if essais <= 10 then C_Timer.After(0.2, prendreRecompense) return end
      dire("infos des récompenses introuvables, à toi de choisir.")
      return
    end
    candidats[i] = { lien = lien, gain = gainPour(lien), vente = select(11, infoObjet(lien)) }
  end
  essais = 0
  local index, raison = ns.choisirRecompense(candidats)
  local c = candidats[index]
  if raison == "amélioration" then
    dire("récompense " .. c.lien .. " (+" .. c.gain .. " niveaux d'objet).")
  else
    dire("récompense " .. c.lien .. " (la plus chère à la revente).")
  end
  GetQuestReward(index)
end

-- ---------------------------------------------------------------------------
-- Dialogues avec les PNJ
-- ---------------------------------------------------------------------------

-- Numéro du PNJ à qui tu parles, lu dans son GUID : « Creature-0-…-<id>-… ».
local function idPNJ()
  local guid = UnitGUID("npc")
  if estSecret(guid) or not guid then return nil end
  local typ, _, _, _, _, id = strsplit("-", guid)
  if typ == "Creature" or typ == "Vehicle" then return tonumber(id) end
end

local function enPause()
  if not db.actif then return true end
  if db.pauseTouches and (IsShiftKeyDown() or IsControlKeyDown() or IsAltKeyDown()) then
    return true
  end
  local id = idPNJ()
  return id and db.pnjIgnores[id] ~= nil
end

-- PNJ moderne (fenêtre de dialogue « gossip »).
local function surDialogue()
  local actives = C_GossipInfo.GetActiveQuests() or {}
  local disponibles = C_GossipInfo.GetAvailableQuests() or {}
  local action, i = ns.choisirAction(actives, disponibles, db, db.quetesIgnorees)
  if action == "rendre" then
    C_GossipInfo.SelectActiveQuest(actives[i].questID)
  elseif action == "accepter" then
    C_GossipInfo.SelectAvailableQuest(disponibles[i].questID)
  end
end

-- Ancien PNJ (fenêtre « QUEST_GREETING », liste de quêtes sans dialogue).
local function surAccueil()
  local actives, disponibles = {}, {}
  for i = 1, GetNumActiveQuests() do
    local _, finie = GetActiveTitle(i)
    actives[i] = { isComplete = finie }
  end
  for i = 1, GetNumAvailableQuests() do
    local grise, frequence, _, _, id = GetAvailableQuestInfo(i)
    disponibles[i] = { isTrivial = grise, frequency = frequence, questID = id }
  end
  local action, i = ns.choisirAction(actives, disponibles, db, db.quetesIgnorees)
  if action == "rendre" then
    SelectActiveQuest(i)
  elseif action == "accepter" then
    SelectAvailableQuest(i)
  end
end

-- Détail d'une quête proposée : on l'accepte si elle passe les filtres.
local function surDetail()
  if not db.accepter then return end
  if QuestGetAutoAccept and QuestGetAutoAccept() then
    -- Quête déjà acceptée d'office par le jeu : on referme simplement.
    CloseQuest()
    return
  end
  local id = GetQuestID()
  local q = {
    questID = id,
    isTrivial = id and C_QuestLog.IsQuestTrivial and C_QuestLog.IsQuestTrivial(id),
    frequency = ((QuestIsDaily and QuestIsDaily()) or (QuestIsWeekly and QuestIsWeekly())) and 1 or 0,
  }
  if ns.accepteQuete(q, db, db.quetesIgnorees) then AcceptQuest() end
end

-- Étape « progression » : on rend seulement si la quête est finie.
local function surProgression()
  if not db.rendre then return end
  if not IsQuestCompletable() then return end -- pas finie : on ne bloque rien
  local cout = GetQuestMoneyToGet and GetQuestMoneyToGet() or 0
  if db.payantes and cout > 0 then
    dire("cette quête coûte de l'or, à toi de la rendre.")
    return
  end
  CompleteQuest()
end

-- ---------------------------------------------------------------------------
-- Cinématiques : la première fois on regarde, ensuite on passe.
-- ---------------------------------------------------------------------------

local function dejaVue(cle)
  if db.vues[cle] then return true end
  db.vues[cle] = true
  return false
end

local function surCinematique(peutPasser)
  if not db.cinematiques or peutPasser == false then return end
  local carte = C_Map.GetBestMapForUnit("player") or 0
  if dejaVue("cine:" .. carte .. ":" .. (GetSubZoneText() or "")) then
    C_Timer.After(0, function()
      if CinematicFrame_CancelCinematic then CinematicFrame_CancelCinematic()
      elseif StopCinematic then StopCinematic() end
    end)
  end
end

local function surFilm(idFilm)
  if not db.cinematiques or not idFilm then return end
  if dejaVue("film:" .. idFilm) then
    C_Timer.After(0, function()
      if MovieFrame and MovieFrame:IsShown() then pcall(MovieFrame.StopMovie, MovieFrame) end
    end)
  end
end

-- ---------------------------------------------------------------------------
-- La liste des options. Elle sert à la fois à la fenêtre de réglages et à la
-- commande /qa : ajouter une option ici l'ajoute partout.
-- Tout s'applique tout de suite, sans /reload.
-- ---------------------------------------------------------------------------

local OPTIONS = {
  { titre = "Automatisme" },
  { cle = "actif", libelle = "Activer Quêtes auto",
    aide = "Interrupteur général. L'icône, le bouton et le raccourci font la même chose." },
  { cle = "accepter", libelle = "Accepter les quêtes tout seul",
    aide = "Prend les nouvelles quêtes que les PNJ te proposent." },
  { cle = "rendre", libelle = "Rendre les quêtes finies tout seul",
    aide = "Toujours avant d'accepter les nouvelles. Une quête pas finie ne bloque rien." },
  { cle = "recompenseAuto", libelle = "Choisir la récompense tout seul",
    aide = "Une amélioration pour toi, sinon l'objet le plus cher à la revente." },
  { cle = "pauseTouches", libelle = "Maj, Ctrl ou Alt met en pause",
    aide = "Garde une de ces touches enfoncée en parlant au PNJ pour tout faire à la main." },
  { titre = "Filtres" },
  { cle = "grises", libelle = "Ignorer les quêtes grises",
    aide = "Les quêtes trop faciles pour ton niveau." },
  { cle = "journalieres", libelle = "Ignorer les journalières et hebdomadaires",
    aide = "Elles restent proposées, tu les prends toi-même si tu veux." },
  { cle = "payantes", libelle = "Ne pas rendre les quêtes qui coûtent de l'or",
    aide = "L'addon te prévient et te laisse payer toi-même." },
  { titre = "Confort" },
  { cle = "cinematiques", libelle = "Passer les cinématiques déjà vues",
    aide = "La première fois tu la regardes, les fois suivantes elle est passée." },
  { cle = "minimap", libelle = "Icône autour de la minimap",
    aide = "Clic gauche : réglages. Clic droit : activer ou couper. Glisser : déplacer." },
  { cle = "bouton", libelle = "Bouton à l'écran",
    aide = "Un « ! » jaune à poser où tu veux. Clic : activer ou couper." },
}

local appliquer -- défini plus bas, appelé après chaque changement

local function changer(cle, valeur)
  db[cle] = valeur
  appliquer()
end

function QuetesAuto_Basculer()
  changer("actif", not db.actif)
  dire(db.actif and "|cff00ff00activé|r" or "|cffff4040coupé|r")
end
BINDING_HEADER_QUETESAUTO = "Quêtes auto"
BINDING_NAME_QUETESAUTO_BASCULER = "Activer ou couper Quêtes auto"

-- ---------------------------------------------------------------------------
-- Fenêtre de réglages
-- ---------------------------------------------------------------------------

local fenetre = CreateFrame("Frame", "QuetesAutoReglages", UIParent, "BasicFrameTemplateWithInset")
fenetre:SetSize(430, 680)
fenetre:SetPoint("CENTER")
fenetre:SetFrameStrata("DIALOG")
fenetre:SetMovable(true)
fenetre:EnableMouse(true)
fenetre:RegisterForDrag("LeftButton")
fenetre:SetScript("OnDragStart", fenetre.StartMoving)
fenetre:SetScript("OnDragStop", fenetre.StopMovingOrSizing)
fenetre:Hide()
tinsert(UISpecialFrames, "QuetesAutoReglages") -- Échap la ferme
-- Titre : celui du modèle de fenêtre s'il existe, sinon le nôtre.
local titre = fenetre.TitleText or fenetre:CreateFontString(nil, "OVERLAY", "GameFontNormal")
if not fenetre.TitleText then titre:SetPoint("TOP", 0, -5) end
titre:SetText("Quêtes auto : réglages")

local cases = {}
local y = -34
for _, opt in ipairs(OPTIONS) do
  if opt.titre then
    local t = fenetre:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", 16, y - 6)
    t:SetText(opt.titre)
    y = y - 30
  else
    local c = CreateFrame("CheckButton", nil, fenetre, "UICheckButtonTemplate")
    c:SetSize(26, 26)
    c:SetPoint("TOPLEFT", 16, y)
    local libelle = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    libelle:SetPoint("TOPLEFT", c, "TOPRIGHT", 4, -2)
    libelle:SetText(opt.libelle)
    local aide = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    aide:SetPoint("TOPLEFT", libelle, "BOTTOMLEFT", 0, -2)
    aide:SetWidth(360)
    aide:SetJustifyH("LEFT")
    aide:SetText(opt.aide)
    c:SetScript("OnClick", function(self) changer(opt.cle, self:GetChecked() and true or false) end)
    cases[opt.cle] = c
    y = y - 38
  end
end

-- Listes d'ignorés et cinématiques vues : un compteur et un bouton pour vider.
local titreListes = fenetre:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
titreListes:SetPoint("TOPLEFT", 16, y - 6)
titreListes:SetText("Listes")
y = y - 32
local compteurs = fenetre:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
compteurs:SetPoint("TOPLEFT", 20, y)
compteurs:SetJustifyH("LEFT")
y = y - 22

local function compter(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

local function boutonVider(texte, x, cle, message)
  local b = CreateFrame("Button", nil, fenetre, "UIPanelButtonTemplate")
  b:SetSize(126, 24)
  b:SetPoint("TOPLEFT", x, y)
  b:SetText(texte)
  b:SetScript("OnClick", function() db[cle] = {}; appliquer(); dire(message) end)
end
boutonVider("Vider les PNJ", 16, "pnjIgnores", "plus aucun PNJ ignoré.")
boutonVider("Vider les quêtes", 148, "quetesIgnorees", "plus aucune quête ignorée.")
boutonVider("Revoir les cinés", 280, "vues", "les cinématiques seront de nouveau montrées une fois.")

local astuce = fenetre:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
astuce:SetPoint("BOTTOMLEFT", 16, 14)
astuce:SetWidth(400)
astuce:SetJustifyH("LEFT")
astuce:SetText("Ignorer un PNJ : parle-lui puis tape /qa ignorer. Tout s'applique tout de suite, sans /reload.")

local function majFenetre()
  for cle, c in pairs(cases) do c:SetChecked(db[cle] and true or false) end
  compteurs:SetText(string.format("PNJ ignorés : %d     Quêtes ignorées : %d     Cinématiques vues : %d",
    compter(db.pnjIgnores), compter(db.quetesIgnorees), compter(db.vues)))
end
fenetre:SetScript("OnShow", majFenetre)

function QuetesAuto_OuvrirReglages()
  if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
  fenetre:SetShown(not fenetre:IsShown())
end

-- Une page dans Échap > Options > AddOns, avec un bouton qui ouvre la fenêtre.
local page = CreateFrame("Frame")
page.name = "Quêtes auto"
local pageTexte = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
pageTexte:SetPoint("TOPLEFT", 16, -16)
pageTexte:SetText("Tous les réglages de Quêtes auto sont dans sa fenêtre :")
local pageBouton = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
pageBouton:SetSize(200, 26)
pageBouton:SetPoint("TOPLEFT", pageTexte, "BOTTOMLEFT", 0, -12)
pageBouton:SetText("Ouvrir les réglages")
pageBouton:SetScript("OnClick", QuetesAuto_OuvrirReglages)
if Settings and Settings.RegisterCanvasLayoutCategory then
  Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(page, page.name))
elseif InterfaceOptions_AddCategory then
  InterfaceOptions_AddCategory(page)
end

-- ---------------------------------------------------------------------------
-- Icône autour de la minimap (faite main, sans bibliothèque)
-- ---------------------------------------------------------------------------

local mini = CreateFrame("Button", "QuetesAutoMinimap", Minimap)
mini:SetSize(31, 31)
mini:SetFrameStrata("MEDIUM")
mini:SetFrameLevel(8)
mini:RegisterForClicks("LeftButtonUp", "RightButtonUp")
mini:RegisterForDrag("LeftButton")
mini:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
local fond = mini:CreateTexture(nil, "BACKGROUND")
fond:SetSize(20, 20)
fond:SetPoint("TOPLEFT", 7, -5)
fond:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
local iconeMini = mini:CreateTexture(nil, "ARTWORK")
iconeMini:SetSize(17, 17)
iconeMini:SetPoint("TOPLEFT", 7, -6)
iconeMini:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
local cadre = mini:CreateTexture(nil, "OVERLAY")
cadre:SetSize(53, 53)
cadre:SetPoint("TOPLEFT")
cadre:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

-- Place l'icône sur le bord de la minimap, à l'angle donné (0° = à droite).
local function placerMini()
  local rayon = Minimap:GetWidth() / 2 + 5
  local a = math.rad(db.angleMinimap)
  mini:ClearAllPoints()
  mini:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * rayon, math.sin(a) * rayon)
end

-- Pendant qu'on la fait glisser, l'icône suit la souris autour de la minimap.
local function suivreSouris()
  local cx, cy = Minimap:GetCenter()
  local sx, sy = GetCursorPosition()
  local echelle = Minimap:GetEffectiveScale()
  db.angleMinimap = math.deg(math.atan2(sy / echelle - cy, sx / echelle - cx))
  placerMini()
end
mini:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", suivreSouris) end)
mini:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
mini:SetScript("OnClick", function(_, souris)
  if souris == "RightButton" then QuetesAuto_Basculer() else QuetesAuto_OuvrirReglages() end
end)

-- ---------------------------------------------------------------------------
-- Bouton à l'écran
-- ---------------------------------------------------------------------------

local bouton = CreateFrame("Button", "QuetesAutoBouton", UIParent)
bouton:SetSize(30, 30)
bouton:SetMovable(true)
bouton:SetClampedToScreen(true)
bouton:RegisterForDrag("LeftButton")
bouton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
local icone = bouton:CreateTexture(nil, "ARTWORK")
icone:SetAllPoints()
icone:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
bouton:SetScript("OnClick", function(_, souris)
  if souris == "RightButton" then QuetesAuto_OuvrirReglages() else QuetesAuto_Basculer() end
end)
bouton:SetScript("OnDragStart", bouton.StartMoving)
bouton:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local point, _, pointRelatif, x, y2 = self:GetPoint()
  db.position = { point, pointRelatif, x, y2 }
end)

-- Infobulle commune à l'icône et au bouton.
local function infobulle(self, clics)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:AddLine("Quêtes auto")
  GameTooltip:AddLine(db.actif and "|cff00ff00Activé|r" or "|cffff4040Coupé|r")
  GameTooltip:AddLine(clics, 1, 1, 1)
  GameTooltip:Show()
end
mini:SetScript("OnEnter", function(self)
  infobulle(self, "Clic gauche : réglages\nClic droit : activer ou couper\nGlisser : déplacer")
end)
bouton:SetScript("OnEnter", function(self)
  infobulle(self, "Clic gauche : activer ou couper\nClic droit : réglages\nGlisser : déplacer")
end)
mini:SetScript("OnLeave", function() GameTooltip:Hide() end)
bouton:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Remet l'icône, le bouton et la fenêtre d'accord avec les réglages.
function appliquer()
  for _, t in ipairs({ icone, iconeMini }) do
    t:SetDesaturated(not db.actif)
  end
  icone:SetAlpha(db.actif and 1 or 0.5)
  bouton:SetShown(db.bouton)
  mini:SetShown(db.minimap)
  if fenetre:IsShown() then majFenetre() end
end

-- ---------------------------------------------------------------------------
-- Événements
-- ---------------------------------------------------------------------------

local ecouteur = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL",
                     "QUEST_PROGRESS", "QUEST_COMPLETE", "CINEMATIC_START", "PLAY_MOVIE" }) do
  ecouteur:RegisterEvent(e)
end

ecouteur:SetScript("OnEvent", function(_, evenement, ...)
  if evenement == "ADDON_LOADED" then
    if ... ~= NOM_ADDON then return end
    QuetesAutoDB = QuetesAutoDB or {}
    for cle, valeur in pairs(DEFAUTS) do
      if QuetesAutoDB[cle] == nil then
        QuetesAutoDB[cle] = type(valeur) == "table" and {} or valeur
      end
    end
    db = QuetesAutoDB
    bouton:ClearAllPoints()
    if db.position then
      local p = db.position
      bouton:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
      bouton:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -200, -200)
    end
    placerMini()
    appliquer()
    return
  end
  if not db then return end
  if evenement == "CINEMATIC_START" then return surCinematique(...) end
  if evenement == "PLAY_MOVIE" then return surFilm(...) end
  if enPause() then return end
  if evenement == "GOSSIP_SHOW" then surDialogue()
  elseif evenement == "QUEST_GREETING" then surAccueil()
  elseif evenement == "QUEST_DETAIL" then surDetail()
  elseif evenement == "QUEST_PROGRESS" then surProgression()
  elseif evenement == "QUEST_COMPLETE" and db.rendre then essais = 0; prendreRecompense()
  end
end)

-- ---------------------------------------------------------------------------
-- Commande /qa (la fenêtre fait la même chose, en plus simple)
-- ---------------------------------------------------------------------------

local function etat(v) return v and "|cff00ff00oui|r" or "|cffff4040non|r" end

SLASH_QUETESAUTO1 = "/qa"
SLASH_QUETESAUTO2 = "/quetesauto"
SlashCmdList.QUETESAUTO = function(texte)
  local cmd, reste = strtrim(texte or ""):match("^(%S*)%s*(.-)$")
  cmd = cmd:lower()
  if cmd == "" or cmd == "options" or cmd == "reglages" then
    QuetesAuto_OuvrirReglages()
  elseif cmd == "on" or cmd == "off" then
    if (cmd == "on") ~= (db.actif and true or false) then QuetesAuto_Basculer() end
  elseif cmd == "ignorer" then
    local id = tonumber(reste)
    if id then
      if db.quetesIgnorees[id] then db.quetesIgnorees[id] = nil else db.quetesIgnorees[id] = true end
      dire("quête " .. id .. (db.quetesIgnorees[id] and " ignorée." or " de nouveau prise."))
    elseif idPNJ() then
      local pnj = idPNJ()
      db.pnjIgnores[pnj] = db.pnjIgnores[pnj] == nil and (UnitName("npc") or "?") or nil
      dire((UnitName("npc") or "ce PNJ") .. (db.pnjIgnores[pnj] and " est ignoré." or " n'est plus ignoré."))
    else
      dire("parle à un PNJ puis tape /qa ignorer, ou /qa ignorer <numéro de quête>.")
    end
    appliquer()
  else
    for _, opt in ipairs(OPTIONS) do
      if opt.cle and opt.cle:lower() == cmd then
        changer(opt.cle, not db[opt.cle])
        return dire(opt.libelle .. " : " .. etat(db[opt.cle]))
      end
    end
    dire("/qa : ouvrir les réglages     /qa on, /qa off : activer ou couper")
    dire("/qa ignorer : ignorer le PNJ en face (ou /qa ignorer <numéro de quête>)")
  end
end
