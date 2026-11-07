-- ============================================================================
-- Sacs rangés : un coup de balai dans les sacs.
--  1. Ranger : le tri du jeu (par type : équipement, composants, consommables…),
--     sur les sacs, et sur la banque quand elle est ouverte.
--  2. Un panneau qui signale l'équipement en double et l'équipement moins bon
--     que ce que tu portes (à vendre ou à mettre en banque ?).
-- Commande : /sr (le panneau), /sr ranger, /sr options (les réglages).
-- ============================================================================

local NOM_ADDON, ns = ...

local DEFAUTS = {
  actif = true,
  rangerMarchand = false,  -- ranger tout seul en refermant un marchand
  rangerBanque = true,     -- ranger aussi la banque quand elle est ouverte
  ecart = 0,               -- « moins bon » = au moins ce nombre de niveaux en dessous
  minimap = false,         -- icône à part (sinon seulement l'icône commune)
  angleMinimap = 120,
}

local db

-- ---------------------------------------------------------------------------
-- Partie « logique pure », testée hors jeu (tests/SacsRanges_simu.lua).
-- ---------------------------------------------------------------------------

-- Numéro d'interface : 120105 sur Retail, 16001 sur Forever.
local RETAIL = GetBuildInfo ~= nil and (tonumber((select(4, GetBuildInfo()))) or 0) >= 100000
-- Sur Forever, arc, fusil, arbalète, baguette, arme de jet et relique ont leur
-- propre emplacement (18) ; sur Retail, une arme à distance se tient en main (16).
local DISTANCE = RETAIL and 16 or 18

-- Emplacements du personnage où va chaque type d'objet (numéros du jeu).
local EMPLACEMENTS = {
  INVTYPE_THROWN = { DISTANCE }, INVTYPE_RELIC = { DISTANCE },
  INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 },
  INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 },
  INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
  INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
  INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
  INVTYPE_RANGED = { DISTANCE }, INVTYPE_RANGEDRIGHT = { DISTANCE },
  INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
}
ns.EMPLACEMENTS = EMPLACEMENTS

-- Sur WoW Forever, se servir d'une arme ou porter une armure s'apprend (maître
-- d'armes, maître de classe ; mailles et plaques au niveau 40). Chaque
-- compétence est un sort que le jeu te donne une fois apprise. Même table que
-- dans QuetesAuto : COMPETENCES[classe d'objet][sous-classe] = sort.
local COMPETENCES = {
  [2] = { -- armes
    [0] = 196, [1] = 197,       -- haches à une main, à deux mains
    [2] = 264, [3] = 266,       -- arcs, armes à feu
    [4] = 198, [5] = 199,       -- masses à une main, à deux mains
    [6] = 200,                  -- armes d'hast
    [7] = 201, [8] = 202,       -- épées à une main, à deux mains
    [10] = 227, [13] = 15590,   -- bâtons, armes de pugilat
    [15] = 1180, [16] = 2567,   -- dagues, armes de jet
    [18] = 5011, [19] = 5009,   -- arbalètes, baguettes
  },
  [4] = { -- armures
    [1] = 9078, [2] = 9077, [3] = 8737, [4] = 750, -- tissu, cuir, mailles, plaques
    [6] = 9116,                                    -- boucliers
  },
}
ns.COMPETENCES = COMPETENCES

-- Peux-tu te servir de cet objet ? Fonction pure, testée hors jeu.
-- `connait(sort)` : compétence apprise (nil = on ne sait pas le demander au jeu) ;
-- `rouge` : la bulle de l'objet affiche une ligne en rouge, la façon dont le jeu
-- dit « tu ne peux pas » (classe, niveau, compétence, race, réputation…).
function ns.utilisable(classeObjet, sousClasse, connait, rouge)
  if rouge then return false end
  local sort = connait and COMPETENCES[classeObjet] and COMPETENCES[classeObjet][sousClasse]
  if sort and not connait(sort) then return false end
  return true
end

-- objets : { { id, lien, niveau, type, utilisable } } (type = « INVTYPE_… » du
-- jeu ; utilisable = false si ton personnage ne peut pas s'en servir)
-- porte : [emplacement] = niveau de ce que tu portes
-- Renvoie trois listes :
--  doublons : { { lien, nombre } } même objet d'équipement au moins deux fois ;
--  moinsBons : { { lien, niveau, porte } } plus bas que le plus faible de tes
--    emplacements pour ce type (une bague est comparée à ta bague la plus faible) ;
--  inutilisables : { { lien, niveau } } équipement que tu ne peux pas porter
--    (pas appris, autre classe, niveau trop haut…), quel que soit son niveau.
function ns.analyser(objets, porte, ecart)
  ecart = ecart or 0
  local compte, premier = {}, {}
  local moinsBons, inutilisables = {}, {}
  for _, o in ipairs(objets) do
    local places = EMPLACEMENTS[o.type or ""]
    if places then
      compte[o.id] = (compte[o.id] or 0) + 1
      premier[o.id] = premier[o.id] or o
    end
    if places and o.utilisable == false then
      inutilisables[#inutilisables + 1] = { lien = o.lien, niveau = o.niveau or 0 }
    elseif places then
      local minPorte
      for _, e in ipairs(places) do
        local n = porte[e]
        if n and n > 0 and (not minPorte or n < minPorte) then minPorte = n end
      end
      if minPorte and o.niveau and o.niveau > 0 and o.niveau < minPorte - ecart then
        moinsBons[#moinsBons + 1] = { lien = o.lien, niveau = o.niveau, porte = minPorte }
      end
    end
  end
  local doublons = {}
  for id, n in pairs(compte) do
    if n >= 2 then doublons[#doublons + 1] = { lien = premier[id].lien, nombre = n } end
  end
  table.sort(doublons, function(a, b) return (a.lien or "") < (b.lien or "") end)
  table.sort(moinsBons, function(a, b) return a.niveau < b.niveau end)
  table.sort(inutilisables, function(a, b) return a.niveau < b.niveau end)
  return doublons, moinsBons, inutilisables
end

-- ---------------------------------------------------------------------------
-- Lecture des sacs (jeu)
-- ---------------------------------------------------------------------------

local function infoObjet(lien)
  if C_Item and C_Item.GetItemInfo then return C_Item.GetItemInfo(lien) end
  return GetItemInfo(lien)
end

local function niveau(lien)
  local f = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
  return f and f(lien) or 0
end

local function nbCases(sac)
  if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(sac) end
  return GetContainerNumSlots and GetContainerNumSlots(sac) or 0
end

local function lienCase(sac, case)
  if C_Container and C_Container.GetContainerItemInfo then
    local info = C_Container.GetContainerItemInfo(sac, case)
    return info and info.hyperlink, info and info.itemID
  end
  local lien = GetContainerItemLink and GetContainerItemLink(sac, case)
  return lien, lien and tonumber(lien:match("item:(%d+)"))
end

local function connaitSort(id)
  if IsPlayerSpell then return IsPlayerSpell(id) end
  return IsSpellKnown and IsSpellKnown(id) or false
end

-- La liste des compétences ne sert que sur Forever, et seulement si le jeu
-- répond : tout le monde connaît le tissu, sinon la question ne marche pas.
local function competences()
  if RETAIL or not connaitSort(COMPETENCES[4][1]) then return nil end
  return connaitSort
end

-- Lit la bulle de l'objet du sac dans une bulle cachée : vrai si une ligne est
-- en rouge, nil si la bulle n'a pas pu être lue.
local bulle
local function ligneRouge(sac, case)
  if not bulle then
    bulle = CreateFrame("GameTooltip", "SacsRangesBulle", nil, "GameTooltipTemplate")
  end
  bulle:SetOwner(WorldFrame, "ANCHOR_NONE")
  bulle:ClearLines()
  bulle:SetBagItem(sac, case)
  local n = bulle:NumLines() or 0
  local rouge = n > 0 and false or nil
  for l = 2, n do -- la ligne 1 est le nom de l'objet
    for _, cote in ipairs({ "Left", "Right" }) do
      local t = _G["SacsRangesBulleText" .. cote .. l]
      local mot = t and t:IsShown() and t:GetText()
      -- Une pièce cassée affiche sa durabilité en rouge : elle se répare, on l'ignore.
      if mot and not mot:find("%d+%s*/%s*%d+") then
        local r, g, b = t:GetTextColor()
        if r > 0.9 and g < 0.2 and b < 0.2 then rouge = true end
      end
    end
  end
  bulle:Hide()
  return rouge
end

local function lireSacs()
  local objets = {}
  local connait = competences()
  local dernier = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
  for sac = 0, dernier do
    for case = 1, nbCases(sac) do
      local lien, id = lienCase(sac, case)
      if lien and id then
        local typ, _, _, classeObjet, sousClasse = select(9, infoObjet(lien))
        if typ and EMPLACEMENTS[typ] then
          local lu, rouge = pcall(ligneRouge, sac, case)
          objets[#objets + 1] = { id = id, lien = lien, niveau = niveau(lien), type = typ,
            utilisable = ns.utilisable(classeObjet, sousClasse, connait, lu and rouge or nil) }
        elseif typ then
          objets[#objets + 1] = { id = id, lien = lien, niveau = niveau(lien), type = typ }
        end
      end
    end
  end
  local porte = {}
  for e = 1, 18 do
    local lien = GetInventoryItemLink("player", e)
    if lien then porte[e] = niveau(lien) end
  end
  return objets, porte
end

-- ---------------------------------------------------------------------------
-- Ranger
-- ---------------------------------------------------------------------------

local banqueOuverte = false

local function ranger()
  if not db.actif then return end
  if InCombatLockdown() then return ns.reglages.dire("|cffff4040pas en combat.|r") end
  local tri = C_Container and C_Container.SortBags or SortBags
  if not tri then return ns.reglages.dire("le tri des sacs n'existe pas sur cette version du jeu.") end
  tri()
  if banqueOuverte and db.rangerBanque then
    local triBanque = C_Container and C_Container.SortBankBags or SortBankBags
    if triBanque then C_Timer.After(1, triBanque) end
  end
  ns.reglages.dire("sacs rangés" .. ((banqueOuverte and db.rangerBanque) and ", banque aussi." or "."))
end
SacsRanges_Ranger = ranger
BINDING_HEADER_SACSRANGES = "Sacs rangés"
BINDING_NAME_SACSRANGES_RANGER = "Ranger les sacs"

-- ---------------------------------------------------------------------------
-- Le panneau
-- ---------------------------------------------------------------------------

local panneau = CreateFrame("Frame", "SacsRangesPanneau", UIParent, "BasicFrameTemplateWithInset")
panneau:SetSize(380, 420)
panneau:SetPoint("RIGHT", UIParent, "RIGHT", -300, 0)
panneau:SetMovable(true)
panneau:SetClampedToScreen(true)
panneau:EnableMouse(true)
panneau:RegisterForDrag("LeftButton")
panneau:SetScript("OnDragStart", panneau.StartMoving)
panneau:SetScript("OnDragStop", panneau.StopMovingOrSizing)
panneau:Hide()
tinsert(UISpecialFrames, panneau:GetName())
local titre = panneau.TitleText or panneau:CreateFontString(nil, "OVERLAY", "GameFontNormal")
if not panneau.TitleText then titre:SetPoint("TOP", 0, -5) end
titre:SetText("Sacs rangés")

local boutonRanger = CreateFrame("Button", nil, panneau, "UIPanelButtonTemplate")
boutonRanger:SetSize(160, 24)
boutonRanger:SetPoint("TOPLEFT", 14, -30)
boutonRanger:SetText("Ranger mes sacs")

local defile = CreateFrame("ScrollFrame", nil, panneau, "UIPanelScrollFrameTemplate")
defile:SetPoint("TOPLEFT", 12, -62)
defile:SetPoint("BOTTOMRIGHT", -30, 12)
local contenu = CreateFrame("Frame", nil, defile)
contenu:SetSize(330, 10)
defile:SetScrollChild(contenu)
local texte = contenu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
texte:SetPoint("TOPLEFT")
texte:SetWidth(330)
texte:SetJustifyH("LEFT")
texte:SetSpacing(2)

local function rafraichir()
  if not panneau:IsShown() then return end
  local objets, porte = lireSacs()
  local doublons, moinsBons, inutilisables = ns.analyser(objets, porte, db.ecart)
  local t = {}
  t[#t + 1] = "|cffffd200Équipement en double (" .. #doublons .. ")|r"
  for _, d in ipairs(doublons) do t[#t + 1] = "  " .. d.lien .. "  ×" .. d.nombre end
  if #doublons == 0 then t[#t + 1] = "  |cffaaaaaarien|r" end
  t[#t + 1] = " "
  t[#t + 1] = "|cffff9933Moins bon que ce que tu portes (" .. #moinsBons .. ")|r : à vendre ou en banque ?"
  for _, m in ipairs(moinsBons) do
    t[#t + 1] = string.format("  %s  |cffaaaaaaniv. %d, tu portes %d|r", m.lien, m.niveau, m.porte)
  end
  if #moinsBons == 0 then t[#t + 1] = "  |cffaaaaaarien|r" end
  t[#t + 1] = " "
  t[#t + 1] = "|cffff4040Tu ne peux pas le porter (" .. #inutilisables .. ")|r : pas appris, autre classe ou niveau trop haut"
  for _, m in ipairs(inutilisables) do
    t[#t + 1] = string.format("  %s  |cffaaaaaaniv. %d|r", m.lien, m.niveau)
  end
  if #inutilisables == 0 then t[#t + 1] = "  |cffaaaaaarien|r" end
  texte:SetText(table.concat(t, "\n"))
  contenu:SetHeight(texte:GetStringHeight() + 10)
end
panneau:SetScript("OnShow", rafraichir)
boutonRanger:SetScript("OnClick", function() ranger() C_Timer.After(1.5, rafraichir) end)

local function basculerPanneau()
  panneau:SetShown(not panneau:IsShown())
end

-- ---------------------------------------------------------------------------
-- Réglages (Reglages.lua) : le clic dans l'icône commune ouvre le panneau.
-- ---------------------------------------------------------------------------

ns.reglages = ns.creerReglages({
  titre = "Sacs rangés",
  icone = "Interface\\Icons\\INV_Misc_Bag_08",
  nomDB = "SacsRangesDB",
  defauts = DEFAUTS,
  ouvrirHub = basculerPanneau,
  options = {
    { titre = "Ranger" },
    { cle = "actif", libelle = "Activer Sacs rangés",
      aide = "Interrupteur général." },
    { cle = "rangerBanque", libelle = "Ranger aussi la banque quand elle est ouverte",
      aide = "Le bouton « Ranger » trie alors tes sacs puis la banque." },
    { cle = "rangerMarchand", libelle = "Ranger tout seul en refermant un marchand",
      aide = "Après la vente des gris par Marchand auto, par exemple." },
    { titre = "Affichage" },
    { cle = "minimap", libelle = "Icône à part autour de la minimap",
      aide = "En plus de l'icône commune des addons de Valentin. Clic droit : activer ou couper." },
  },
  astuce = "Le panneau : /sr ou la ligne Sacs rangés de l'icône commune. Ranger : /sr ranger ou un raccourci clavier.",
  auChargement = function(d) db = d end,
})

-- ---------------------------------------------------------------------------
-- Événements et commande /sr
-- ---------------------------------------------------------------------------

local ecouteur = CreateFrame("Frame")
for _, e in ipairs({ "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "MERCHANT_CLOSED", "BAG_UPDATE_DELAYED" }) do
  ecouteur:RegisterEvent(e)
end
local dernierRangement = 0
ecouteur:SetScript("OnEvent", function(_, evenement)
  if not db then return end
  if evenement == "BANKFRAME_OPENED" then banqueOuverte = true
  elseif evenement == "BANKFRAME_CLOSED" then banqueOuverte = false
  elseif evenement == "MERCHANT_CLOSED" then
    -- MERCHANT_CLOSED arrive parfois deux fois : un seul rangement.
    if db.actif and db.rangerMarchand and GetTime() - dernierRangement > 3 then
      dernierRangement = GetTime()
      C_Timer.After(0.5, ranger)
    end
  else
    rafraichir()
  end
end)

SLASH_SACSRANGES1 = "/sr"
SLASH_SACSRANGES2 = "/sacsranges"
SlashCmdList.SACSRANGES = function(message)
  local cmd = strtrim(message or ""):lower()
  local r = ns.reglages
  if cmd == "" then
    basculerPanneau()
  elseif cmd == "ranger" then
    ranger()
  elseif cmd == "options" or cmd == "reglages" then
    r.ouvrir()
  elseif cmd == "on" or cmd == "off" then
    if (cmd == "on") ~= (db.actif and true or false) then r.basculer() end
  elseif not r.basculerOption(cmd) then
    r.dire("/sr : le panneau     /sr ranger : ranger les sacs     /sr options : les réglages")
  end
end
