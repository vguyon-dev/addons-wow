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
--  4. En groupe, il partage tes quêtes et accepte celles de tes frères.
--  5. Il passe les cinématiques déjà vues une fois.
--  6. Tout se règle dans une fenêtre (Reglages.lua) : icône de minimap, /qa,
--     ou Échap > Options > AddOns. Bouton à l'écran et raccourci clavier.
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
  dialogueUnique = false,  -- cliquer seul la phrase quand un PNJ n'en a qu'une (coupé au départ)
  bouton = true,           -- afficher le bouton
  partager = true,         -- partager ses quêtes avec le groupe
  accepterPartagees = true, -- accepter les quêtes partagées par le groupe
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

-- Dialogue unique : quelle phrase cliquer ? Seulement s'il n'y en a qu'UNE,
-- et pas deux fois de suite la même (sinon on tournerait en rond).
-- Renvoie le numéro de l'option, ou nil.
function ns.optionUnique(options, derniere)
  if #options ~= 1 then return nil end
  local id = options[1].gossipOptionID
  if not id or id == derniere then return nil end
  return id
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

-- Dernière phrase de dialogue cliquée, oubliée 3 secondes après.
local derniereOption

-- PNJ moderne (fenêtre de dialogue « gossip »).
local function surDialogue()
  local actives = C_GossipInfo.GetActiveQuests() or {}
  local disponibles = C_GossipInfo.GetAvailableQuests() or {}
  local action, i = ns.choisirAction(actives, disponibles, db, db.quetesIgnorees)
  if action == "rendre" then
    C_GossipInfo.SelectActiveQuest(actives[i].questID)
  elseif action == "accepter" then
    C_GossipInfo.SelectAvailableQuest(disponibles[i].questID)
  elseif db.dialogueUnique then
    -- Plus de quête à rendre ni à prendre : s'il ne reste qu'une phrase, on la clique.
    local id = ns.optionUnique(C_GossipInfo.GetOptions() or {}, derniereOption)
    if id then
      derniereOption = id
      C_Timer.After(3, function() if derniereOption == id then derniereOption = nil end end)
      C_GossipInfo.SelectOption(id)
    end
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

-- Quêtes reçues du groupe : on ne les repartage pas (sinon ping-pong entre frères).
local recuesDuGroupe = {}

-- La quête affichée vient-elle d'un joueur de ton groupe (quête partagée) ?
-- Le jeu désigne celui qui te parle par « npc » ou « questnpc » : on regarde les deux.
local function partageeParLeGroupe()
  for _, unite in ipairs({ "questnpc", "npc" }) do
    local joueur = UnitIsPlayer(unite)
    if not estSecret(joueur) and joueur and (UnitInParty(unite) or UnitInRaid(unite)) then
      return true
    end
  end
  return false
end

-- Détail d'une quête proposée : on l'accepte si elle passe les filtres.
local function surDetail()
  if partageeParLeGroupe() then
    -- Partagée par ton frère : il l'a choisie, donc pas de filtre.
    if db.accepterPartagees then
      recuesDuGroupe[GetQuestID() or 0] = true
      AcceptQuest()
    end
    return
  end
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
-- En groupe : partager ses quêtes, accepter les escortes lancées par le groupe.
-- ---------------------------------------------------------------------------

-- Une quête vient d'être acceptée : on la partage avec le groupe.
local function surQueteAcceptee(a, b)
  local id = b or a -- selon la version du jeu : (id) ou (index, id)
  if not db.partager or not IsInGroup() or not id or recuesDuGroupe[id] then return end
  C_Timer.After(0.5, function()
    if C_QuestLog.IsPushableQuest and C_QuestLog.IsPushableQuest(id) then
      C_QuestLog.SetSelectedQuest(id)
      QuestLogPushQuest()
      dire("quête partagée avec le groupe : " .. (C_QuestLog.GetTitleForQuestID(id) or id))
    end
  end)
end

-- Un membre du groupe lance une escorte : on la rejoint.
local function surConfirmation()
  if not db.accepterPartagees then return end
  ConfirmAcceptQuest()
  StaticPopup_Hide("QUEST_ACCEPT")
end

-- ---------------------------------------------------------------------------
-- Les réglages (fenêtre, icône de minimap, page des options) : Reglages.lua.
-- La liste ci-dessous sert à la fois à la fenêtre et à la commande /qa.
-- ---------------------------------------------------------------------------

local bouton, icone -- bouton à l'écran, créé plus bas

local function compter(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

local reglages = ns.creerReglages({
  titre = "Quêtes auto",
  icone = "Interface\\GossipFrame\\AvailableQuestIcon",
  nomDB = "QuetesAutoDB",
  defauts = DEFAUTS,
  options = {
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
    { cle = "dialogueUnique", libelle = "Cliquer la phrase quand le PNJ n'en a qu'une",
      aide = "Coupé au départ : certains PNJ demandent un vrai choix. Plusieurs phrases = rien." },
    { titre = "En groupe" },
    { cle = "partager", libelle = "Partager mes quêtes avec le groupe",
      aide = "Chaque quête que tu acceptes est proposée aux autres membres du groupe." },
    { cle = "accepterPartagees", libelle = "Accepter les quêtes partagées par le groupe",
      aide = "Sans filtre : si ton frère la partage, tu la prends. Escortes comprises." },
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
  },
  -- Zone « Listes » : compteurs et boutons pour vider.
  contenu = function(fenetre, y, r)
    local t = fenetre:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", 16, y - 6)
    t:SetText("Listes")
    y = y - 32
    local compteurs = fenetre:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    compteurs:SetPoint("TOPLEFT", 20, y)
    y = y - 22
    local function vider(texte, x, cle, message)
      local b = CreateFrame("Button", nil, fenetre, "UIPanelButtonTemplate")
      b:SetSize(130, 24)
      b:SetPoint("TOPLEFT", x, y)
      b:SetText(texte)
      b:SetScript("OnClick", function() r.changer(cle, {}); dire(message) end)
    end
    vider("Vider les PNJ", 16, "pnjIgnores", "plus aucun PNJ ignoré.")
    vider("Vider les quêtes", 152, "quetesIgnorees", "plus aucune quête ignorée.")
    vider("Revoir les cinés", 288, "vues", "les cinématiques seront de nouveau montrées une fois.")
    y = y - 28
    return y, function(d)
      compteurs:SetText(string.format("PNJ ignorés : %d     Quêtes ignorées : %d     Cinématiques vues : %d",
        compter(d.pnjIgnores), compter(d.quetesIgnorees), compter(d.vues)))
    end
  end,
  astuce = "Ignorer un PNJ : parle-lui puis tape /qa ignorer. Tout s'applique tout de suite, sans /reload.",
  auChargement = function(d)
    db = d
    bouton:ClearAllPoints()
    if db.position then
      local p = db.position
      bouton:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
      bouton:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -200, -200)
    end
  end,
  surChangement = function(d)
    icone:SetDesaturated(not d.actif)
    icone:SetAlpha(d.actif and 1 or 0.5)
    bouton:SetShown(d.bouton)
  end,
})

function QuetesAuto_Basculer() reglages.basculer() end
BINDING_HEADER_QUETESAUTO = "Quêtes auto"
BINDING_NAME_QUETESAUTO_BASCULER = "Activer ou couper Quêtes auto"
BINDING_NAME_QUETESAUTO_REGLAGES = "Ouvrir les réglages de Quêtes auto"

-- ---------------------------------------------------------------------------
-- Bouton à l'écran
-- ---------------------------------------------------------------------------

bouton = CreateFrame("Button", "QuetesAutoBouton", UIParent)
bouton:SetSize(30, 30)
bouton:SetMovable(true)
bouton:SetClampedToScreen(true)
bouton:RegisterForDrag("LeftButton")
bouton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
icone = bouton:CreateTexture(nil, "ARTWORK")
icone:SetAllPoints()
icone:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
bouton:SetScript("OnClick", function(_, souris)
  if souris == "RightButton" then reglages.ouvrir() else reglages.basculer() end
end)
bouton:SetScript("OnDragStart", bouton.StartMoving)
bouton:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local point, _, pointRelatif, x, y = self:GetPoint()
  db.position = { point, pointRelatif, x, y }
end)
bouton:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:AddLine("Quêtes auto")
  GameTooltip:AddLine(db.actif and "|cff00ff00Activé|r" or "|cffff4040Coupé|r")
  GameTooltip:AddLine("Clic gauche : activer ou couper\nClic droit : réglages\nGlisser : déplacer", 1, 1, 1)
  GameTooltip:Show()
end)
bouton:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- ---------------------------------------------------------------------------
-- Événements
-- ---------------------------------------------------------------------------

local ecouteur = CreateFrame("Frame")
for _, e in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS",
                     "QUEST_COMPLETE", "QUEST_ACCEPTED", "QUEST_ACCEPT_CONFIRM",
                     "CINEMATIC_START", "PLAY_MOVIE" }) do
  ecouteur:RegisterEvent(e)
end

ecouteur:SetScript("OnEvent", function(_, evenement, ...)
  if not db then return end
  if evenement == "CINEMATIC_START" then return surCinematique(...) end
  if evenement == "PLAY_MOVIE" then return surFilm(...) end
  if not db.actif then return end
  if evenement == "QUEST_ACCEPTED" then return surQueteAcceptee(...) end
  if enPause() then return end
  if evenement == "GOSSIP_SHOW" then surDialogue()
  elseif evenement == "QUEST_GREETING" then surAccueil()
  elseif evenement == "QUEST_DETAIL" then surDetail()
  elseif evenement == "QUEST_PROGRESS" then surProgression()
  elseif evenement == "QUEST_COMPLETE" and db.rendre then essais = 0; prendreRecompense()
  elseif evenement == "QUEST_ACCEPT_CONFIRM" then surConfirmation()
  end
end)

-- ---------------------------------------------------------------------------
-- Commande /qa (la fenêtre fait la même chose, en plus simple)
-- ---------------------------------------------------------------------------

SLASH_QUETESAUTO1 = "/qa"
SLASH_QUETESAUTO2 = "/quetesauto"
SlashCmdList.QUETESAUTO = function(texte)
  local cmd, reste = strtrim(texte or ""):match("^(%S*)%s*(.-)$")
  cmd = cmd:lower()
  if cmd == "" or cmd == "options" or cmd == "reglages" then
    reglages.ouvrir()
  elseif cmd == "on" or cmd == "off" then
    if (cmd == "on") ~= (db.actif and true or false) then reglages.basculer() end
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
    reglages.appliquer()
  elseif not reglages.basculerOption(cmd) then
    dire("/qa : ouvrir les réglages     /qa on, /qa off : activer ou couper")
    dire("/qa ignorer : ignorer le PNJ en face (ou /qa ignorer <numéro de quête>)")
  end
end
