-- ============================================================================
-- Sacs rangés : quels objets du sac valent mieux que ce que tu portes.
--
-- Si Pawn est installé, son avis fait foi (il connaît ta spécialisation et ses
-- poids). Sinon on compare nous-mêmes, au même emplacement :
--   - la caractéristique principale de ta spécialisation (Force, Agilité ou
--     Intelligence), l'Endurance, les caractéristiques secondaires, l'armure ;
--   - pour une arme, les dégâts par seconde (qui comptent peu pour un lanceur
--     de sorts) ;
--   - à défaut de caractéristiques lisibles, le niveau d'objet.
-- Un objet que tu ne peux pas porter n'est jamais conseillé (vérifié avant).
-- ============================================================================

local NOM_ADDON, ns = ...

-- ---------------------------------------------------------------------------
-- Partie « logique pure », testée hors jeu (tests/SacsRanges_simu.lua).
-- ---------------------------------------------------------------------------

-- Emplacements d'équipement (numéros du jeu) pour chaque type d'objet.
-- L'emplacement à distance (18) n'existe que sur les anciens clients : sans lui,
-- arcs et fusils vont en main droite (16).
function ns.emplacementsPour(typeObjet, aEmplacementDistance)
  local distance = aEmplacementDistance and { 18 } or { 16 }
  local t = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 },
    INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
    INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
    INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 },
    INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 },
    INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = distance, INVTYPE_RANGEDRIGHT = distance,
    INVTYPE_THROWN = distance, INVTYPE_RELIC = aEmplacementDistance and { 18 } or nil,
  }
  return t[typeObjet]
end

-- Les caractéristiques du jeu (GetItemStats) ramenées à quelques chiffres.
local CLES = {
  ITEM_MOD_STRENGTH_SHORT = "force", ITEM_MOD_AGILITY_SHORT = "agilite", ITEM_MOD_INTELLECT_SHORT = "intelligence",
  ITEM_MOD_STAMINA_SHORT = "endurance", ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "dps", RESISTANCE0_NAME = "armure",
  ITEM_MOD_SPIRIT_SHORT = "secondaires", ITEM_MOD_CRIT_RATING_SHORT = "secondaires",
  ITEM_MOD_HASTE_RATING_SHORT = "secondaires", ITEM_MOD_MASTERY_RATING_SHORT = "secondaires",
  ITEM_MOD_VERSATILITY = "secondaires", ITEM_MOD_HIT_RATING_SHORT = "secondaires",
  ITEM_MOD_ATTACK_POWER_SHORT = "secondaires", ITEM_MOD_SPELL_POWER_SHORT = "secondaires",
}
function ns.lireStats(brut)
  local s = {}
  for cle, valeur in pairs(brut or {}) do
    local c = CLES[cle]
    if c and type(valeur) == "number" then s[c] = (s[c] or 0) + valeur end
  end
  return s
end

local NOMS = { force = "Force", agilite = "Agilité", intelligence = "Intelligence", endurance = "Endurance" }

-- Une note pour un objet : plus elle est haute, mieux c'est pour cette spécialisation.
function ns.note(stats, principale)
  stats = stats or {}
  local poidsDps = principale == "intelligence" and 0.3 or 3
  return (stats.dps or 0) * poidsDps + (stats[principale] or 0) + (stats.endurance or 0) * 0.5
    + (stats.secondaires or 0) * 0.4 + (stats.armure or 0) * 0.01
end

local function nombreFr(n)
  local t = string.format("%.1f", n):gsub("%.0$", ""):gsub("%.", ",")
  return t
end

-- Ce qui fait la différence, en une ligne : « +0,4 dégâts par seconde, +2 Agilité ».
function ns.raison(nouv, ancien, principale)
  nouv, ancien = nouv or {}, ancien or {}
  local morceaux = {}
  local dDps = (nouv.dps or 0) - (ancien.dps or 0)
  if dDps > 0.05 and principale ~= "intelligence" then morceaux[#morceaux + 1] = "+" .. nombreFr(dDps) .. " dégâts par seconde" end
  for _, c in ipairs({ principale, "endurance" }) do
    local d = (nouv[c] or 0) - (ancien[c] or 0)
    if d > 0 and NOMS[c] then morceaux[#morceaux + 1] = "+" .. nombreFr(d) .. " " .. NOMS[c] end
  end
  if #morceaux == 0 and dDps > 0.05 then morceaux[1] = "+" .. nombreFr(dDps) .. " dégâts par seconde" end
  return table.concat(morceaux, ", ", 1, math.min(2, #morceaux))
end

-- Compare un objet du sac à ce que tu portes.
--   objet  = { stats, niveau, type }
--   portes = { [emplacement] = { stats, niveau, type, nom } ou false si vide }
-- Renvoie nil si ce n'est pas mieux, sinon { raison, remplace = nom ou nil }.
function ns.comparer(objet, portes, principale, aEmplacementDistance, ambidextre)
  local emplacements = ns.emplacementsPour(objet.type, aEmplacementDistance)
  if not emplacements then return nil end
  -- Sans ambidextrie, une arme à une main ne va qu'en main droite.
  if objet.type == "INVTYPE_WEAPON" and not ambidextre then emplacements = { 16 } end
  local mainDroite = portes[16]
  local deuxMains = mainDroite and mainDroite.type == "INVTYPE_2HWEAPON"

  -- Arme à deux mains : elle remplace la main droite ET la main gauche.
  if objet.type == "INVTYPE_2HWEAPON" then
    local avant = (mainDroite and ns.note(mainDroite.stats, principale) or 0)
      + (portes[17] and ns.note(portes[17].stats, principale) or 0)
    local apres = ns.note(objet.stats, principale)
    if apres > avant * 1.02 + 0.05 then
      return { raison = ns.raison(objet.stats, mainDroite and mainDroite.stats, principale),
        remplace = mainDroite and mainDroite.nom }
    end
    return nil
  end

  -- Le plus faible des emplacements possibles (deux bagues, deux bijoux, deux armes).
  local pire, notePire, emplacementPire
  for _, e in ipairs(emplacements) do
    local porte = portes[e]
    -- Main gauche vide parce qu'on tient une arme à deux mains : pas un trou.
    if not porte and not (e == 17 and deuxMains) then
      return { raison = "emplacement vide" }
    end
    if porte then
      local n = ns.note(porte.stats, principale)
      if not notePire or n < notePire then pire, notePire, emplacementPire = porte, n, e end
    end
  end
  if not pire then return nil end
  if emplacementPire == 17 and deuxMains then return nil end -- il faudrait lâcher l'arme à deux mains

  local n = ns.note(objet.stats, principale)
  if n > 0 or notePire > 0 then
    if n > notePire * 1.02 + 0.05 then
      return { raison = ns.raison(objet.stats, pire.stats, principale), remplace = pire.nom }
    end
    return nil
  end
  -- Aucune caractéristique lisible des deux côtés : le niveau d'objet tranche.
  if (objet.niveau or 0) > (pire.niveau or 0) then
    return { raison = "niveau d'objet " .. (objet.niveau or 0) .. " contre " .. (pire.niveau or 0), remplace = pire.nom }
  end
  return nil
end

-- Caractéristique principale d'une classe (quand la spécialisation est inconnue).
ns.PRINCIPALE_CLASSE = {
  WARRIOR = "force", PALADIN = "force", DEATHKNIGHT = "force",
  HUNTER = "agilite", ROGUE = "agilite", DEMONHUNTER = "agilite", MONK = "agilite",
  MAGE = "intelligence", PRIEST = "intelligence", WARLOCK = "intelligence", EVOKER = "intelligence",
  SHAMAN = "intelligence", DRUID = "intelligence",
}

if not CreateFrame or not GetInventoryItemLink then return end -- hors jeu : la suite ne sert qu'en jeu

-- ---------------------------------------------------------------------------
-- Accès au jeu
-- ---------------------------------------------------------------------------

local cache = {}       -- lien -> résultat (vidé quand l'équipement ou la spé change)
local principale, nomSpe

local function lireSpecialisation()
  principale, nomSpe = nil, nil
  if GetSpecialization and GetSpecializationInfo then
    local ok, spe = pcall(GetSpecialization)
    if ok and spe then
      local _, nom, _, _, _, stat = GetSpecializationInfo(spe)
      principale = ({ [1] = "force", [2] = "agilite", [4] = "intelligence" })[stat]
      nomSpe = nom
    end
  end
  local nomClasse, classe = UnitClass("player")
  principale = principale or ns.PRINCIPALE_CLASSE[classe] or "force"
  nomSpe = nomSpe or nomClasse
end

local aDistance = false
do
  local ok, id = pcall(GetInventorySlotInfo, "RangedSlot")
  aDistance = ok and id == 18
end

local function statsDe(lien)
  local f = (C_Item and C_Item.GetItemStats) or GetItemStats
  return ns.lireStats(f and f(lien) or nil)
end

local function infos(lien)
  local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  local nom, _, _, niveau, _, _, _, _, typeObjet = f(lien)
  local n = (C_Item and C_Item.GetDetailedItemLevelInfo or GetDetailedItemLevelInfo)
  if n then niveau = n(lien) or niveau end
  return nom, niveau, typeObjet
end

local function avisPawn(lien)
  if not (PawnGetItemData and PawnIsItemAnUpgrade) then return nil end
  local ok, objet = pcall(PawnGetItemData, lien)
  if not ok or not objet then return nil end
  local ok2, infosPawn = pcall(PawnIsItemAnUpgrade, objet)
  if not ok2 then return nil end
  local u = type(infosPawn) == "table" and infosPawn[1]
  if not u then return false end
  -- Pawn compare parfois à un emplacement vide qu'on ne peut pas remplir (main
  -- gauche sans ambidextrie) : « +10000 % » pour un couteau à dépecer, vu en jeu
  -- le 08/11. Sans objet porté en face, c'est notre propre comparaison qui tranche.
  if not u.ExistingItemLink then return nil end
  local pourcent = tonumber(u.PercentUpgrade)
  local echelle = u.LocalizedScaleName or u.ScaleName or "Pawn"
  return { raison = (pourcent and ("+" .. math.floor(pourcent * 100 + 0.5) .. " % ") or "") .. "(" .. echelle .. ")" }
end

-- Le conseil pour un objet du sac (nil s'il n'est pas mieux). L'appelant a déjà
-- vérifié que c'est de l'équipement que tu peux porter.
function ns.conseil(lien)
  if not lien then return nil end
  local cle = lien .. (ns.db and ns.db.avisPawn and "|P" or "")
  if cache[cle] ~= nil then return cache[cle] or nil end
  if not principale then lireSpecialisation() end
  local resultat = nil
  if ns.db and ns.db.avisPawn then resultat = avisPawn(lien) end
  if resultat == nil then
    local _, niveau, typeObjet = infos(lien)
    if not typeObjet then return nil end -- pas encore en cache : on reviendra
    local portes = {}
    for _, e in ipairs(ns.emplacementsPour(typeObjet, aDistance) or {}) do
      local l = GetInventoryItemLink("player", e)
      if l then
        local nom, nv, t = infos(l)
        portes[e] = { stats = statsDe(l), niveau = nv, type = t, nom = nom }
      else
        portes[e] = false
      end
    end
    if typeObjet == "INVTYPE_2HWEAPON" or typeObjet == "INVTYPE_WEAPON" then
      local l16 = GetInventoryItemLink("player", 16)
      if l16 and portes[16] == nil then
        local nom, nv, t = infos(l16)
        portes[16] = { stats = statsDe(l16), niveau = nv, type = t, nom = nom }
      end
      local l17 = GetInventoryItemLink("player", 17)
      if l17 and portes[17] == nil then
        local nom, nv, t = infos(l17)
        portes[17] = { stats = statsDe(l17), niveau = nv, type = t, nom = nom }
      end
    end
    for e, v in pairs(portes) do if v == false then portes[e] = nil end end
    local ambidextre = CanDualWield and CanDualWield() or false
    resultat = ns.comparer({ stats = statsDe(lien), niveau = niveau, type = typeObjet }, portes, principale, aDistance,
      ambidextre) or false
  end
  cache[cle] = resultat
  return resultat or nil
end

-- ---------------------------------------------------------------------------
-- L'avis dans toutes les bulles d'objets (butin, récompenses, marchand, sac…)
-- ---------------------------------------------------------------------------

function ns.bullesActives()
  return ns.db and ns.db.actif and ns.db.conseilsBulles ~= false
end

-- Une ligne en rouge dans la bulle : le jeu dit « tu ne peux pas ».
local function rougeDans(tip)
  local nom = tip.GetName and tip:GetName()
  if not nom then return nil end
  local rouge = false
  for l = 2, tip:NumLines() or 0 do
    for _, cote in ipairs({ "Left", "Right" }) do
      local t = _G[nom .. "Text" .. cote .. l]
      local mot = t and t:IsShown() and t:GetText()
      -- Une durabilité en rouge se répare : on l'ignore.
      if mot and not mot:find("%d+%s*/%s*%d+") then
        local r, g, b = t:GetTextColor()
        if r > 0.9 and g < 0.2 and b < 0.2 then rouge = true end
      end
    end
  end
  return rouge
end

local function ajouterAvis(tip)
  if not ns.bullesActives() then return end
  -- Pas dans les bulles de comparaison (ce que tu portes déjà).
  if tip ~= GameTooltip and tip ~= ItemRefTooltip then return end
  local ok, _, lien = pcall(tip.GetItem, tip)
  if not ok or not lien then return end
  local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  local _, _, _, _, _, _, _, _, typeObjet, _, _, classe, sousClasse = f(lien)
  if not typeObjet or not ns.emplacementsPour(typeObjet, aDistance) then return end
  local id = tonumber(lien:match("item:(%d+)"))
  if ns.estOutilMetier and ns.estOutilMetier(classe, sousClasse, id) then return end
  if ns.utilisable and not ns.utilisable(classe, sousClasse, ns.competences and ns.competences(), rougeDans(tip)) then
    return
  end
  local okC, c = pcall(ns.conseil, lien)
  if not okC or not c then return end
  if not principale then lireSpecialisation() end
  tip:AddLine(" ")
  tip:AddLine("Mieux pour " .. (nomSpe or "toi") .. " : " .. (c.raison or ""), 0.12, 1, 0, true)
  if c.remplace then tip:AddLine("Remplace : " .. c.remplace, 0.6, 0.6, 0.6) end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ajouterAvis)
else
  for _, tip in ipairs({ GameTooltip, ItemRefTooltip }) do
    if tip and tip.HookScript then pcall(tip.HookScript, tip, "OnTooltipSetItem", ajouterAvis) end
  end
end

function ns.nomSpecialisation()
  if not principale then lireSpecialisation() end
  return nomSpe
end

local ecouteur = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "PLAYER_SPECIALIZATION_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED",
  "PLAYER_LEVEL_UP", "CHARACTER_POINTS_CHANGED" }) do
  pcall(ecouteur.RegisterEvent, ecouteur, e)
end
ecouteur:SetScript("OnEvent", function()
  cache = {}
  principale = nil
  if ns.vueMaj then ns.vueMaj() end
end)
