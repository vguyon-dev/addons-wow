-- ============================================================================
-- Familier du chasseur : une alerte avec le bon bouton quand ton familier
--   - a faim ou devient mécontent (si le jeu donne son humeur) : « Nourrir » ;
--   - est mort : « Ressusciter » ;
--   - n'est pas appelé (hors ville, après un combat ou un chargement) : « Appeler ».
-- Le bouton est un vrai bouton d'action du jeu : c'est ton clic qui lance le
-- sort (un appui = une action). Il ne change qu'en dehors des combats.
-- Ne sert qu'aux chasseurs.
-- ============================================================================

local NOM_ADDON, ns = ...

local DEFAUTS = {
  actif = true,
  faim = true,        -- prévenir quand il a faim ou devient mécontent
  mort = true,        -- prévenir quand il meurt
  oubli = true,       -- prévenir quand il n'est pas appelé
  son = false,
  nourritures = {},   -- [numéro d'objet] = nom : la nourriture qu'il aime, choisie par toi
  minimap = false,
  angleMinimap = 110,
}

local db

-- ---------------------------------------------------------------------------
-- Partie « logique pure », testée hors jeu (tests/FamilierChasseur_simu.lua).
-- ---------------------------------------------------------------------------

-- L'état à signaler.  info = { existe, mort, humeur (1 à 3 ou nil), auRepos, enCombat }
function ns.etat(info, options)
  if info.existe and info.mort then return options.mort and "mort" or nil end
  if not info.existe then
    if options.oubli and not info.auRepos and not info.enCombat then return "absent" end
    return nil
  end
  if options.faim and info.humeur and info.humeur < 3 then return "faim" end
  return nil
end

-- La nourriture à donner : d'abord celles que tu as choisies, sinon toute
-- nourriture du sac ; la moins chère à la revente d'abord.
--   objets : { { id, sac, case, nourriture = vrai/faux, prix } }
function ns.choisirNourriture(objets, preferes)
  local meilleure
  local function mieux(o) return not meilleure or (o.prix or 0) < (meilleure.prix or 0) end
  if preferes and next(preferes) then
    for _, o in ipairs(objets) do
      if preferes[o.id] and mieux(o) then meilleure = o end
    end
    if meilleure then return meilleure end
  end
  for _, o in ipairs(objets) do
    if o.nourriture and mieux(o) then meilleure = o end
  end
  return meilleure
end

if not CreateFrame or not UnitClass then return end -- hors jeu : la suite ne sert qu'en jeu

local _, classe = UnitClass("player")
local CHASSEUR = classe == "HUNTER"

local function nomSort(id)
  if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
  return GetSpellInfo and (GetSpellInfo(id)) or nil
end

-- ---------------------------------------------------------------------------
-- La nourriture du sac
-- ---------------------------------------------------------------------------

local function lireSac()
  local objets = {}
  for sac = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 do
    local n = C_Container and C_Container.GetContainerNumSlots(sac) or 0
    for case = 1, n do
      local info = C_Container.GetContainerItemInfo(sac, case)
      if info and info.itemID then
        local _, _, _, _, _, _, _, _, _, _, prix, classeObjet, sousClasse = ((C_Item and C_Item.GetItemInfo) or GetItemInfo)(info.itemID)
        objets[#objets + 1] = { id = info.itemID, sac = sac, case = case, prix = prix or 0,
          nourriture = classeObjet == 0 and sousClasse == 5 }
      end
    end
  end
  return objets
end

-- ---------------------------------------------------------------------------
-- L'alerte et son bouton
-- ---------------------------------------------------------------------------

local alerte = CreateFrame("Frame", "FamilierChasseurAlerte", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
alerte:SetSize(300, 86)
alerte:SetPoint("TOP", UIParent, "TOP", 0, -200)
if alerte.SetBackdrop then
  alerte:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  alerte:SetBackdropColor(0.10, 0.05, 0.03, 0.92)
  alerte:SetBackdropBorderColor(1, 0.3, 0.2, 1)
end
alerte:Hide()
-- L'alerte se déplace en la faisant glisser (position gardée).
alerte:SetMovable(true)
alerte:SetClampedToScreen(true)
alerte:EnableMouse(true)
alerte:RegisterForDrag("LeftButton")
alerte:SetScript("OnDragStart", alerte.StartMoving)
alerte:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local p, _, rp, x, y = self:GetPoint()
  db.positionAlerte = { p, rp, x, y }
end)
local texte = alerte:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
texte:SetPoint("TOP", 0, -12)
texte:SetTextColor(1, 0.35, 0.25)
local sousTexte = alerte:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
sousTexte:SetPoint("TOP", texte, "BOTTOM", 0, -3)

-- Le vrai bouton d'action (sécurisé) : c'est ton clic qui lance le sort.
local action = CreateFrame("Button", "FamilierChasseurAction", UIParent, "SecureActionButtonTemplate,UIPanelButtonTemplate")
action:SetSize(240, 26)
action:SetPoint("BOTTOM", alerte, "BOTTOM", 0, 10)
action:RegisterForClicks("AnyUp")
action:SetAttribute("type", "macro")
action:Hide()

local etatAffiche
local ferme -- l'état que tu as fermé avec la croix : plus d'alerte tant qu'il dure

-- La croix : ferme l'alerte jusqu'à ce que la situation change. En combat, le jeu
-- interdit de cacher un bouton d'action : on le rend invisible, et on le cache
-- vraiment à la fin du combat.
local croix = CreateFrame("Button", nil, alerte, "UIPanelCloseButton")
croix:SetPoint("TOPRIGHT", 0, 0)
croix:SetScript("OnClick", function()
  ferme = etatAffiche
  if InCombatLockdown() then
    alerte:SetAlpha(0); action:SetAlpha(0)
  else
    alerte:Hide(); action:Hide()
  end
end)
croix:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_TOP")
  GameTooltip:AddLine("Fermer")
  GameTooltip:AddLine("L'alerte revient seulement si la situation change. Pour ne plus jamais la voir : /familier (réglages).", 1, 1, 1, true)
  GameTooltip:Show()
end)
croix:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function placerAlerte()
  alerte:ClearAllPoints()
  local p = db.positionAlerte
  if p then alerte:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else alerte:SetPoint("TOP", UIParent, "TOP", 0, -200) end
end

local function afficher(etat, nomFamilier)
  if InCombatLockdown() then return end -- le bouton ne change qu'hors combat
  etatAffiche = etat
  alerte:SetAlpha(1); action:SetAlpha(1)
  if not etat then alerte:Hide(); action:Hide() return end
  local appel, ressu, nourrir = nomSort(883), nomSort(982), nomSort(6991)
  local qui = nomFamilier or "Ton familier"
  if etat == "faim" then
    local n = ns.choisirNourriture(lireSac(), db.nourritures)
    texte:SetText(qui .. " a faim")
    if n and nourrir then
      local nom = ((C_Item and C_Item.GetItemNameByID) and C_Item.GetItemNameByID(n.id)) or ("objet " .. n.id)
      sousTexte:SetText("Il devient mécontent : il fait moins de dégâts.")
      action:SetText("Nourrir (" .. nom .. ")")
      action:SetAttribute("macrotext", "/cast " .. nourrir .. "\n/use " .. n.sac .. " " .. n.case)
    else
      sousTexte:SetText("Aucune nourriture dans tes sacs.")
      action:SetText("Rien à lui donner")
      action:SetAttribute("macrotext", "")
    end
  elseif etat == "mort" or etat == "absent" then
    texte:SetText(etat == "mort" and (qui .. " est mort") or "Ton familier n'est pas appelé")
    sousTexte:SetText(etat == "mort" and "Il faut le ressusciter." or "Hors ville, il te protège.")
    action:SetText(etat == "mort" and "Ressusciter le familier" or "Appeler le familier")
    -- Un familier mort et renvoyé ne peut pas être appelé : la macro tente
    -- l'appel, puis la résurrection si l'appel a échoué.
    local lignes = {}
    if etat == "absent" and appel then lignes[#lignes + 1] = "/cast [nopet] " .. appel end
    if ressu then lignes[#lignes + 1] = "/cast [@pet,dead][nopet] " .. ressu end
    action:SetAttribute("macrotext", table.concat(lignes, "\n"))
  end
  alerte:Show()
  action:Show()
  if db.son and PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.RAID_WARNING or 8959) end
end

local function verifier()
  if not db or not CHASSEUR then return end
  if InCombatLockdown() then return end
  -- Pas encore de familier (chasseur de bas niveau, sort « Appel du familier »
  -- pas appris) : l'addon reste silencieux.
  local connu = (IsPlayerSpell and IsPlayerSpell(883)) or (IsSpellKnown and IsSpellKnown(883))
  if not db.actif or not connu then if etatAffiche then afficher(nil) end return end
  local existe = UnitExists("pet")
  local humeur = GetPetHappiness and (GetPetHappiness()) or nil
  local etat = ns.etat({
    existe = existe, mort = existe and UnitIsDead("pet"), humeur = humeur,
    auRepos = IsResting and IsResting() or false, enCombat = InCombatLockdown(),
  }, db)
  if UnitOnTaxi and UnitOnTaxi("player") then etat = nil end
  -- Fermée avec la croix : rien tant que la situation n'a pas changé.
  if ferme then
    if etat == ferme then
      if alerte:IsShown() then alerte:Hide(); action:Hide(); alerte:SetAlpha(1); action:SetAlpha(1) end
      etatAffiche = etat
      return
    end
    ferme = nil
  end
  if etat ~= etatAffiche then afficher(etat, existe and UnitName("pet") or nil) end
end

-- ---------------------------------------------------------------------------
-- Réglages et événements
-- ---------------------------------------------------------------------------

ns.reglages = ns.creerReglages({
  titre = "Familier du chasseur",
  icone = "Interface\\Icons\\Ability_Hunter_BeastCall",
  nomDB = "FamilierChasseurDB",
  defauts = DEFAUTS,
  options = {
    { titre = "Prévenir" },
    { cle = "actif", libelle = "Activer Familier du chasseur",
      aide = CHASSEUR == false and "Ce personnage n'est pas chasseur : l'addon ne fait rien pour lui."
        or "Une alerte avec le bon bouton : Nourrir, Ressusciter ou Appeler. Ton clic lance le sort." },
    { cle = "faim", libelle = "Quand il a faim ou devient mécontent",
      aide = "Seulement si le jeu donne l'humeur des familiers (à vérifier sur Forever)." },
    { cle = "mort", libelle = "Quand il meurt" },
    { cle = "oubli", libelle = "Quand tu oublies de l'appeler", aide = "Hors ville, après un combat ou un écran de chargement." },
    { cle = "son", libelle = "Son en plus du message" },
    { titre = "Icône" },
    { cle = "minimap", libelle = "Icône à part autour de la minimap",
      aide = "En plus de la ligne dans l'icône commune des addons de Valentin." },
  },
  ongletContenu = "Nourriture",
  contenu = function(f, y)
    local maj
    y, maj = ns.creerListe(f, y, {
      titre = "Nourriture qu'il aime", vide = "Vide : n'importe quelle nourriture du sac, la moins chère d'abord.",
      hauteur = 4,
      lignes = function()
        local l = {}
        for id, nom in pairs(db and db.nourritures or {}) do
          l[#l + 1] = { texte = nom, retirer = function() db.nourritures[id] = nil end }
        end
        table.sort(l, function(a, b) return a.texte < b.texte end)
        return l
      end,
      deposer = function(id, lien) db.nourritures[id] = lien and lien:match("%[(.-)%]") or ("objet " .. id) end,
      texteDepot = "Glisse ici une nourriture qu'il aime",
      vider = function() db.nourritures = {} end,
    })
    return y, maj
  end,
  boutons = {
    { texte = "Replacer l'alerte", aide = "Remet l'alerte en haut de l'écran.", action = function()
      db.positionAlerte = nil; placerAlerte()
    end },
  },
  auChargement = function(d) db = d; placerAlerte() end,
  surChangement = function() etatAffiche = false; verifier() end,
})

local ecouteur = CreateFrame("Frame")
for _, e in ipairs({ "UNIT_PET", "PET_UI_UPDATE", "UNIT_HAPPINESS", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD",
  "PLAYER_UPDATE_RESTING", "BAG_UPDATE_DELAYED", "UNIT_HEALTH", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB" }) do
  pcall(ecouteur.RegisterEvent, ecouteur, e)
end
local prevu = false
ecouteur:SetScript("OnEvent", function(_, evenement, unite)
  if evenement == "UNIT_HEALTH" and unite ~= "pet" then return end
  if prevu then return end
  prevu = true
  -- Un petit délai : après un chargement, le familier met un instant à apparaître.
  C_Timer.After(evenement == "PLAYER_ENTERING_WORLD" and 3 or 0.5, function() prevu = false; verifier() end)
end)

SLASH_FAMILIERCHASSEUR1 = "/familier"
SlashCmdList.FAMILIERCHASSEUR = function(message)
  local c = strtrim(message or ""):lower()
  if c == "on" or c == "off" then
    if (c == "on") ~= (db.actif and true or false) then ns.reglages.basculer() end
  elseif c == "" or c == "options" or c == "reglages" then ns.reglages.montrer()
  elseif not ns.reglages.basculerOption(c) then ns.reglages.dire("/familier : réglages ; /familier on | off") end
end
