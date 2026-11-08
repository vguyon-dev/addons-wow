-- ============================================================================
-- Barres de vie : les barres au-dessus des monstres, en plus lisible (dans
-- l'esprit de Threat Plates, réécrit à notre façon, sans reprendre son code).
--
-- On garde les barres du jeu et on les améliore :
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
  menace = true,       -- couleur selon la menace
  etoiles = true,      -- marque des rares et des élites
  pourcent = true,     -- pourcentage de vie sur la barre
  cibleGrande = true,  -- la cible plus grande
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
  ajouts[plaque] = a
  return a
end

local function majPourcent(unite, a)
  if not db.pourcent then a.pourcent:Hide() return end
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
    { cle = "menace", libelle = "Couleur selon la menace",
      aide = "Vert : tranquille. Orange : il commence à te viser. Rouge : il te tape. En tank, c'est l'inverse (rouge = il t'échappe). En donjon, le jeu cache parfois la menace : la couleur du jeu reste alors." },
    { cle = "etoiles", libelle = "Une marque pour les rares et les élites",
      aide = "Marque argentée pour un rare, dorée pour un élite, à gauche de la barre." },
    { cle = "pourcent", libelle = "Le pourcentage de vie sur la barre", aide = "« 63 % » au milieu de la barre." },
    { cle = "cibleGrande", libelle = "La cible un peu plus grande",
      aide = "La barre de ta cible est agrandie (réglage du jeu remis comme avant si tu décoches)." },
    { titre = "Icône" },
    { cle = "minimap", libelle = "Icône à part autour de la minimap",
      aide = "En plus de la ligne dans l'icône commune des addons de Valentin." },
  },
  auChargement = function(d) db = d end,
  surChangement = function()
    appliquerCible()
    toutMettreAJour()
  end,
})

local ecouteur = CreateFrame("Frame")
for _, e in ipairs({ "NAME_PLATE_UNIT_ADDED", "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE",
  "UNIT_HEALTH", "UNIT_CLASSIFICATION_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_SPECIALIZATION_CHANGED" }) do
  pcall(ecouteur.RegisterEvent, ecouteur, e)
end
ecouteur:SetScript("OnEvent", function(_, evenement, unite)
  if not db then return end
  if evenement == "PLAYER_REGEN_ENABLED" or evenement == "PLAYER_SPECIALIZATION_CHANGED" then
    appliquerCible()
    toutMettreAJour()
  elseif type(unite) == "string" and unite:find("^nameplate") then
    majPlaque(unite)
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
