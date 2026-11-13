-- ============================================================================
-- Barres de vie : les barres au-dessus des monstres, en plus lisible (dans
-- l'esprit de Threat Plates, réécrit à notre façon, sans reprendre son code).
--
-- On garde les barres du jeu telles quelles (« comme le jeu », voulu par
-- le joueur) et on ajoute :
--   - un grand « ! » au-dessus des monstres de tes quêtes, et sous lui ta
--     progression « 2/6 » avec l'icône de l'objet à ramasser (ou une épée
--     quand il faut le tuer) ;
-- et, en option (décochées au départ) :
--   - couleur selon la menace : vert = tranquille, orange = il commence à te
--     viser, rouge = il te tape (pour un tank, c'est l'inverse : rouge = il
--     t'échappe) ;
--   - une étoile pour les rares (argent) et les élites (or) ;
--   - le pourcentage de vie écrit sur la barre ;
--   - la cible un peu plus grande.
-- Depuis Midnight, le jeu cache aux addons certaines valeurs de combat (« valeurs
-- secrètes »), surtout en donjon et en raid : on peut les afficher, pas les
-- comparer. Quand une valeur est cachée, on ne colore pas, on laisse le jeu faire.
-- ============================================================================

local NOM_ADDON, ns = ...

local DEFAUTS = {
  actif = true,
  quetes = true,       -- « ! » et progression des quêtes au-dessus des monstres
  menace = false,      -- couleur selon la menace (sinon la couleur du jeu)
  etoiles = false,     -- marque des rares et des élites
  pourcent = false,    -- pourcentage de vie sur la barre
  cibleGrande = false, -- la cible plus grande
  minimap = false,
  angleMinimap = 250,
}

local db
local estSecret = issecretvalue or function() return false end

-- ---------------------------------------------------------------------------
-- Partie « logique pure », testée hors jeu (tests/BarresDeVie_simu.lua).
-- ---------------------------------------------------------------------------

local VERT, ORANGE, ROUGE = { 0.2, 0.85, 0.2 }, { 1, 0.6, 0 }, { 0.95, 0.15, 0.1 }

-- La couleur selon la menace (UnitThreatSituation : nil = pas en combat avec lui,
-- 0 = tu n'es pas visé, 1 = tu vas bientôt l'être, 2 = il te vise mais c'est
-- fragile, 3 = il te vise). nil = laisser la couleur du jeu.
function ns.couleurMenace(statut, estTank)
  if statut == nil then return nil end
  if estTank then
    if statut == 3 then return VERT end
    if statut == 2 or statut == 1 then return ORANGE end
    return ROUGE -- il tape quelqu'un d'autre : à reprendre
  end
  if statut == 3 or statut == 2 then return ROUGE end
  if statut == 1 then return ORANGE end
  return VERT
end

-- L'étoile à mettre selon la classification du jeu.
function ns.etoile(classification)
  if classification == "rare" or classification == "rareelite" then return "rare" end
  if classification == "elite" or classification == "worldboss" then return "elite" end
  return nil
end

-- Les quêtes d'un monstre, lues dans les lignes de sa bulle d'aide.
--   lignes : { { type, leftText, completed } } (C_TooltipInfo.GetUnit)
--   types  : { titre = numéro du type « titre de quête », objectif = « objectif » }
-- Renvoie { { texte, fait, total, genre = "objet" | "tuer" | "autre" } } pour
-- les objectifs pas encore finis.
local MOTS_TUER = { "tué", "tue", "tués", "slain", "killed", "vaincu", "vaincus", "défait" }
function ns.objectifs(lignes, types)
  local liste = {}
  for _, l in ipairs(lignes or {}) do
    if l.type == types.objectif and type(l.leftText) == "string" then
      local t = l.leftText
      local fait, total = t:match("(%d+)%s*/%s*(%d+)")
      fait, total = tonumber(fait), tonumber(total)
      local fini = l.completed or (fait and total and fait >= total)
      if not fini then
        local genre = fait and "objet" or "autre"
        local bas = t:lower()
        for _, m in ipairs(MOTS_TUER) do
          if bas:find(m, 1, true) then genre = "tuer" break end
        end
        -- Le nom de ce qu'il faut, sans « 2/6 » ni « - » au début.
        local nom = t:gsub("%s*:?%s*%d+%s*/%s*%d+%s*", " "):gsub("^[%s%-]+", ""):gsub("%s+$", "")
        liste[#liste + 1] = { texte = t, nom = nom, fait = fait, total = total, genre = genre }
      end
    end
  end
  return liste
end

-- Le jeu ne dit pas toujours qu'un monstre donne un objet de quête (sa bulle n'en parle pas).
-- On l'apprend alors nous-mêmes : quand un objet demandé par une quête sort du butin d'un
-- monstre, on retient « ce genre de monstre donne cet objet ».

-- Le numéro du genre de monstre, tiré de son identifiant (« Creature-0-…-numéro-… »).
function ns.npcDuGuid(guid)
  if type(guid) ~= "string" then return nil end
  local genre, numero = guid:match("^(%a+)%-[^%-]*%-[^%-]*%-[^%-]*%-[^%-]*%-(%d+)")
  if genre ~= "Creature" and genre ~= "Vehicle" then return nil end
  return tonumber(numero)
end

-- « Flasque d'huile : 2/5 » ou « 2/5 Flasque d'huile » -> « flasque d'huile ».
function ns.cleObjet(texte)
  if type(texte) ~= "string" then return nil end
  local nom = texte:gsub("%s*:?%s*%d+%s*/%s*%d+%s*", " "):gsub("^[%s%-]+", ""):gsub("%s+$", "")
  if nom == "" then return nil end
  return nom:lower(), nom
end

-- connus : { [cle d'objet] = true } pour ce genre de monstre ; journal : { [cle] = { nom, fait, total } }
-- pour les objets encore à ramasser. Renvoie le premier objet qu'il te manque, ou nil.
function ns.butinManquant(connus, journal)
  if not connus or not journal then return nil end
  local cles = {}
  for cle in pairs(connus) do cles[#cles + 1] = cle end
  table.sort(cles)
  for _, cle in ipairs(cles) do
    local o = journal[cle]
    if o and o.fait and o.total and o.fait < o.total then return o end
  end
  return nil
end

if not CreateFrame or not C_NamePlate then return end -- hors jeu : la suite ne sert qu'en jeu

-- ---------------------------------------------------------------------------
-- Les barres
-- ---------------------------------------------------------------------------

local ajouts = {} -- [plaque] = { etoile, pourcent }

local function sur(valeur) return valeur ~= nil and not estSecret(valeur) end

local function estTank()
  if GetSpecialization and GetSpecializationRole then
    local spe = GetSpecialization()
    return spe and GetSpecializationRole(spe) == "TANK"
  end
  return false
end

local function barreDe(cadre)
  return cadre and (cadre.healthBar or (cadre.HealthBarsContainer and cadre.HealthBarsContainer.healthBar))
end

local function ajoutsDe(plaque)
  local a = ajouts[plaque]
  if a then return a end
  local barre = barreDe(plaque.UnitFrame)
  if not barre then return nil end
  a = {}
  a.cadre = CreateFrame("Frame", nil, plaque)
  a.cadre:SetAllPoints(barre)
  a.cadre:SetFrameLevel(barre:GetFrameLevel() + 5)
  a.etoile = a.cadre:CreateTexture(nil, "OVERLAY")
  a.etoile:SetSize(16, 16)
  a.etoile:SetPoint("RIGHT", a.cadre, "LEFT", -2, 0)
  a.etoile:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1")
  a.etoile:Hide()
  a.pourcent = a.cadre:CreateFontString(nil, "OVERLAY", "SystemFont_Shadow_Small")
  a.pourcent:SetPoint("CENTER")
  -- Le « ! » de quête, gros, tout en haut ; la progression juste dessous.
  a.quete = a.cadre:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  a.quete:SetText("!")
  a.quete:SetTextColor(1, 0.82, 0)
  a.quete:SetPoint("BOTTOM", a.cadre, "TOP", 0, 34)
  a.quete:Hide()
  a.progres = a.cadre:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  a.progres:SetPoint("BOTTOM", a.cadre, "TOP", 8, 18)
  a.progres:Hide()
  a.icone = a.cadre:CreateTexture(nil, "OVERLAY")
  a.icone:SetSize(16, 16)
  a.icone:SetPoint("RIGHT", a.progres, "LEFT", -3, 0)
  a.icone:Hide()
  ajouts[plaque] = a
  return a
end

local function majPourcent(unite, a)
  if not db.pourcent then a.pourcent:Hide() return end
  -- Une chose sans vie (le bouchon de pêche, un objet visé) : pas de « 0 % » (vu en jeu le 13/11).
  local sansVie = UnitHealthMax(unite)
  if sur(sansVie) and sansVie <= 0 then a.pourcent:Hide() return end
  local guid = UnitGUID and UnitGUID(unite)
  if sur(guid) and type(guid) == "string" and guid:sub(1, 10) == "GameObject" then a.pourcent:Hide() return end
  -- Retail récent : UnitHealthPercent rend un pourcentage affichable même caché.
  if UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100 then
    local ok = pcall(function()
      a.pourcent:SetFormattedText("%.0f %%", UnitHealthPercent(unite, true, CurveConstants.ScaleTo100))
    end)
    if ok then a.pourcent:Show() return end
  end
  local vie, max = UnitHealth(unite), UnitHealthMax(unite)
  if sur(vie) and sur(max) and max > 0 then
    a.pourcent:SetText(math.floor(vie / max * 100 + 0.5) .. " %")
    a.pourcent:Show()
  else
    a.pourcent:Hide()
  end
end

-- Les types de lignes de bulle « titre de quête » et « objectif ».
local TYPES = Enum and Enum.TooltipDataLineType and {
  titre = Enum.TooltipDataLineType.QuestTitle, objectif = Enum.TooltipDataLineType.QuestObjective,
}

local ICONE_TUER = "Interface\\Icons\\Ability_DualWield"
local ICONE_OBJET = "Interface\\Icons\\INV_Misc_Bag_10"

-- L'icône de l'objet à ramasser, d'après son nom (connue dès qu'on en a vu un).
local function iconeObjet(nom)
  local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  local ok, _, _, _, _, _, _, _, _, _, icone = pcall(info, nom)
  return ok and icone or ICONE_OBJET
end

-- Les objets que tes quêtes demandent encore, relus seulement quand le journal change.
local journalObjets
local function objetsDuJournal()
  if journalObjets then return journalObjets end
  journalObjets = {}
  if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo and C_QuestLog.GetQuestObjectives) then
    return journalObjets
  end
  local ok, n = pcall(C_QuestLog.GetNumQuestLogEntries)
  for i = 1, (ok and tonumber(n)) or 0 do
    local ok2, info = pcall(C_QuestLog.GetInfo, i)
    if ok2 and info and not info.isHeader and info.questID then
      local ok3, objs = pcall(C_QuestLog.GetQuestObjectives, info.questID)
      for _, o in ipairs(ok3 and objs or {}) do
        if o.type == "item" and not o.finished then
          local cle, nom = ns.cleObjet(o.text)
          if cle then journalObjets[cle] = { nom = nom, fait = o.numFulfilled, total = o.numRequired } end
        end
      end
    end
  end
  return journalObjets
end

-- À l'ouverture d'un butin : si un objet demandé par une quête en sort, on retient le monstre.
local function apprendreButin()
  if not db or not (GetNumLootItems and GetLootSlotInfo and GetLootSourceInfo) then return end
  local journal = objetsDuJournal()
  if not next(journal) then return end
  for case = 1, GetNumLootItems() or 0 do
    local ok, _, nom = pcall(GetLootSlotInfo, case)
    local cle = ok and ns.cleObjet(nom)
    if cle and journal[cle] then
      local sources = { pcall(GetLootSourceInfo, case) }
      for i = 2, #sources, 2 do
        local numero = sur(sources[i]) and ns.npcDuGuid(sources[i])
        if numero then
          db.butins[numero] = db.butins[numero] or {}
          db.butins[numero][cle] = true
        end
      end
    end
  end
end

local function majQuete(unite, a)
  a.quete:Hide(); a.progres:Hide(); a.icone:Hide()
  if not db.quetes or not TYPES or not (C_TooltipInfo and C_TooltipInfo.GetUnit) then return end
  local ok, donnees = pcall(C_TooltipInfo.GetUnit, unite)
  if not ok or not donnees or not donnees.lines then return end
  local lignes = {}
  for _, l in ipairs(donnees.lines) do
    if sur(l.leftText) then lignes[#lignes + 1] = { type = l.type, leftText = l.leftText, completed = l.completed } end
  end
  local objs = ns.objectifs(lignes, TYPES)
  if #objs == 0 then
    -- La bulle du jeu ne dit rien : ce genre de monstre a-t-il déjà donné un objet qu'il te manque ?
    local guid = UnitGUID and UnitGUID(unite)
    local numero = sur(guid) and ns.npcDuGuid(guid)
    local o = numero and db.butins and ns.butinManquant(db.butins[numero], objetsDuJournal())
    if not o then return end
    a.quete:Show()
    a.progres:SetText(o.fait .. "/" .. o.total)
    a.progres:Show()
    a.icone:SetTexture(iconeObjet(o.nom))
    a.icone:Show()
    return
  end
  a.quete:Show()
  -- La première progression chiffrée : « 2/6 » et son icône.
  for _, o in ipairs(objs) do
    if o.fait and o.total then
      a.progres:SetText(o.fait .. "/" .. o.total)
      a.progres:Show()
      a.icone:SetTexture(o.genre == "tuer" and ICONE_TUER or iconeObjet(o.nom))
      a.icone:Show()
      break
    end
  end
end

local function majEtoile(unite, a)
  local c = db.etoiles and UnitClassification(unite)
  local e = sur(c) and ns.etoile(c) or nil
  if e == "rare" then
    a.etoile:SetVertexColor(0.85, 0.9, 1)
    a.etoile:Show()
  elseif e == "elite" then
    a.etoile:SetVertexColor(1, 0.82, 0)
    a.etoile:Show()
  else
    a.etoile:Hide()
  end
end

local function majCouleur(unite, cadre)
  if not db.actif or not db.menace then return end
  if not UnitCanAttack("player", unite) then return end
  local statut = UnitThreatSituation("player", unite)
  if not sur(statut) then return end -- caché par le jeu : on laisse sa couleur
  local couleur = ns.couleurMenace(statut, estTank())
  local barre = barreDe(cadre)
  if couleur and barre then barre:SetStatusBarColor(couleur[1], couleur[2], couleur[3]) end
end

local function majPlaque(unite)
  local plaque = C_NamePlate.GetNamePlateForUnit(unite)
  if not plaque or not plaque.UnitFrame then return end
  local a = ajoutsDe(plaque)
  if not a then return end
  if not db.actif then a.cadre:Hide() return end
  a.cadre:Show()
  majPourcent(unite, a)
  majEtoile(unite, a)
  majQuete(unite, a)
  majCouleur(unite, plaque.UnitFrame)
end

local function toutMettreAJour()
  for _, plaque in ipairs(C_NamePlate.GetNamePlates() or {}) do
    local unite = plaque.namePlateUnitToken or (plaque.UnitFrame and plaque.UnitFrame.unit)
    if unite then majPlaque(unite) end
  end
end

-- Le jeu recolore ses barres sans arrêt : on repasse derrière lui.
if CompactUnitFrame_UpdateHealthColor then
  hooksecurefunc("CompactUnitFrame_UpdateHealthColor", function(cadre)
    local unite = cadre and cadre.unit
    if db and unite and type(unite) == "string" and unite:find("^nameplate") then majCouleur(unite, cadre) end
  end)
end

-- La cible plus grande : un réglage du jeu (gardé et remis au décochage).
local function appliquerCible()
  if not C_CVar or not C_CVar.SetCVar then return end
  if db.actif and db.cibleGrande then
    if db.echelleAvant == nil then db.echelleAvant = C_CVar.GetCVar("nameplateSelectedScale") end
    if not InCombatLockdown() then C_CVar.SetCVar("nameplateSelectedScale", "1.25") end
  elseif db.echelleAvant ~= nil then
    if not InCombatLockdown() then C_CVar.SetCVar("nameplateSelectedScale", db.echelleAvant); db.echelleAvant = nil end
  end
end

-- ---------------------------------------------------------------------------
-- Réglages et événements
-- ---------------------------------------------------------------------------

ns.reglages = ns.creerReglages({
  titre = "Barres de vie",
  icone = "Interface\\Icons\\Ability_Warrior_DefensiveStance",
  nomDB = "BarresDeVieDB",
  defauts = DEFAUTS,
  options = {
    { titre = "Barres de vie" },
    { cle = "actif", libelle = "Activer Barres de vie",
      aide = "Améliore les barres de vie du jeu au-dessus des monstres (affiche-les avec V ou Maj+V)." },
    { cle = "quetes", libelle = "« ! » et progression des quêtes au-dessus des monstres",
      aide = "Un grand « ! » jaune sur les monstres de tes quêtes, et dessous « 2/6 » avec l'icône de l'objet à ramasser (une épée quand il faut le tuer). Quand le jeu ne dit pas qu'un monstre donne un objet de quête, l'addon l'apprend au premier objet ramassé sur ce genre de monstre." },
    { titre = "En plus (sinon les barres restent comme le jeu)" },
    { cle = "menace", libelle = "Couleur selon la menace",
      aide = "Vert : tranquille. Orange : il commence à te viser. Rouge : il te tape. En tank, c'est l'inverse (rouge = il t'échappe). En donjon, le jeu cache parfois la menace : la couleur du jeu reste alors." },
    { cle = "etoiles", libelle = "Une marque pour les rares et les élites",
      aide = "Marque argentée pour un rare, dorée pour un élite, à gauche de la barre." },
    { cle = "pourcent", libelle = "Le pourcentage de vie sur la barre", aide = "« 63 % » au milieu de la barre." },
    { cle = "cibleGrande", libelle = "La cible un peu plus grande",
      aide = "La barre de ta cible est agrandie (réglage du jeu remis comme avant si tu décoches)." },
    { titre = "Icône" },
    { cle = "minimap", libelle = "Icône à part autour de la minimap",
      aide = "En plus de la ligne dans l'icône commune « Mes addons »." },
  },
  auChargement = function(d)
    db = d
    d.butins = type(d.butins) == "table" and d.butins or {} -- [genre de monstre] = { [objet] = true }
    -- Une fois : la 0.1.0 cochait tout ; le joueur veut les barres « comme le jeu ».
    if not d.commeLeJeu then
      d.menace, d.etoiles, d.pourcent, d.cibleGrande, d.commeLeJeu = false, false, false, false, true
    end
  end,
  surChangement = function()
    appliquerCible()
    toutMettreAJour()
  end,
})

local majPrevue = false
local ecouteur = CreateFrame("Frame")
for _, e in ipairs({ "NAME_PLATE_UNIT_ADDED", "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED", "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE",
  "UNIT_HEALTH", "UNIT_CLASSIFICATION_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_SPECIALIZATION_CHANGED", "LOOT_READY", "LOOT_OPENED" }) do
  pcall(ecouteur.RegisterEvent, ecouteur, e)
end
ecouteur:SetScript("OnEvent", function(_, evenement, unite)
  if not db then return end
  if evenement == "LOOT_READY" or evenement == "LOOT_OPENED" then
    pcall(apprendreButin)
    return
  end
  if evenement == "QUEST_LOG_UPDATE" or evenement == "UNIT_QUEST_LOG_CHANGED" then journalObjets = nil end
  if evenement == "PLAYER_REGEN_ENABLED" or evenement == "PLAYER_SPECIALIZATION_CHANGED" then
    appliquerCible()
    toutMettreAJour()
  elseif type(unite) == "string" and unite:find("^nameplate") then
    majPlaque(unite)
  elseif evenement == "QUEST_LOG_UPDATE" or evenement == "UNIT_QUEST_LOG_CHANGED" then
    -- Un objet ramassé, un monstre tué : la progression change sur toutes les barres.
    if not majPrevue then
      majPrevue = true
      C_Timer.After(0.3, function() majPrevue = false; toutMettreAJour() end)
    end
  elseif evenement == "UNIT_THREAT_LIST_UPDATE" or evenement == "UNIT_THREAT_SITUATION_UPDATE" then
    toutMettreAJour()
  end
end)

SLASH_BARRESDEVIE1 = "/bv"
SLASH_BARRESDEVIE2 = "/barresdevie"
SlashCmdList.BARRESDEVIE = function(message)
  local c = strtrim(message or ""):lower()
  if c == "on" or c == "off" then
    if (c == "on") ~= (db.actif and true or false) then ns.reglages.basculer() end
  elseif c == "" or c == "options" or c == "reglages" then
    ns.reglages.montrer()
  elseif not ns.reglages.basculerOption(c) then
    ns.reglages.dire("/bv : réglages ; /bv on | off")
  end
end
