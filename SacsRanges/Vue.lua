-- ============================================================================
-- Sacs rangés : le sac par catégories (maquette 1, « un seul sac en sections »).
--
-- Quand l'option est cochée, les sacs du jeu ne s'ouvrent plus : à leur place,
-- une seule fenêtre range tout en sections (Équipement, Consommables,
-- Composants, Quête, Divers, À vendre), avec une recherche et les boutons de
-- l'addon. Deux apparences au choix : le nouveau visuel (sombre et doré) ou le
-- cadre habituel du jeu ; le contenu et les boutons sont les mêmes.
--
-- Les cases sont de vraies cases de sac du jeu (ContainerFrameItemButtonTemplate) :
-- clic droit pour utiliser ou équiper, glisser, vendre au marchand, bulle d'aide,
-- tout marche comme dans les sacs du jeu. Elles sont créées hors combat ; en
-- combat, la fenêtre se met à jour mais ne se réorganise qu'après le combat.
-- ============================================================================

local NOM_ADDON, ns = ...

-- ---------------------------------------------------------------------------
-- Partie « logique pure », testée hors jeu (tests/SacsRanges_simu.lua).
-- ---------------------------------------------------------------------------

ns.SECTIONS = {
  { id = "equip", nom = "Équipement", couleur = { 0.42, 0.62, 1.00 } },
  { id = "conso", nom = "Consommables", couleur = { 0.40, 0.85, 0.50 } },
  { id = "compo", nom = "Composants", couleur = { 0.90, 0.70, 0.35 } },
  { id = "metier", nom = "Métiers", couleur = { 0.55, 0.80, 0.85 } },
  { id = "quete", nom = "Quête", couleur = { 1.00, 0.82, 0.20 } },
  { id = "divers", nom = "Divers", couleur = { 0.75, 0.70, 0.62 } },
  { id = "pasPourToi", nom = "Tu ne peux pas le porter", couleur = { 0.88, 0.48, 0.37 } },
  { id = "vendre", nom = "À vendre", couleur = { 0.62, 0.62, 0.62 } },
}

-- Classes d'objets du jeu : 0 consommable, 2 arme, 4 armure, 5 composant
-- (anciennes versions), 7 artisanat, 3 gemme, 12 quête, 15 divers.
local CLASSES = { [0] = "conso", [2] = "equip", [4] = "equip", [5] = "compo", [7] = "compo", [3] = "compo",
  [12] = "quete" }

-- La section d'un objet. Gris ou équipement que tu ne peux pas porter : à vendre.
-- Un objet de quête reste en « Quête » même s'il est gris (on ne le vend pas).
-- Un outil de métier (canne à pêche, couteau à dépecer…) va dans « Métiers ».
-- extra (facultatif) = { livre = vrai si c'est un livre de bibliothèque à rendre,
--   lie = vrai si l'objet est lié quand ramassé, artisanat = faux si le jeu dit
--   qu'il ne sert à aucun artisanat }.
function ns.categorie(classe, qualite, quete, utilisable, sousClasse, id, extra)
  extra = extra or {}
  if quete or classe == 12 or extra.livre then return "quete" end
  if ns.estOutilMetier and ns.estOutilMetier(classe, sousClasse, id) then return "metier" end
  if qualite == 0 then return "vendre" end
  local c = CLASSES[classe]
  -- Équipement que tu ne peux pas porter : lié (ni donnable ni vendable à
  -- l'hôtel des ventes) et pas une simple question de niveau -> à vendre ;
  -- sinon il se donne, se vend aux enchères ou se portera plus tard.
  if c == "equip" and utilisable == false then
    if extra.estLie and extra.raison ~= "niveau" then return "vendre" end
    return "pasPourToi"
  end
  -- Lié et inutile à l'artisanat (un journal, un souvenir) : pas un composant.
  if c == "compo" and extra.lie and extra.artisanat == false then return "divers" end
  return c or "divers"
end

-- Range les objets lus ({ sac, case, categorie, nom, qualite }) par section, et
-- dans chaque section par qualité (la meilleure d'abord) puis par nom.
-- La phrase « pourquoi c'est rangé ici », pour la bulle de l'objet.
function ns.texteRangement(categorie, qualite, estLie, texte)
  if categorie == "vendre" then
    if qualite == 0 then return "objet gris" end
    return "lié, et tu ne pourras pas le porter" .. (texte and (" (" .. texte .. ")") or "")
  end
  if categorie == "pasPourToi" then
    return (texte or "tu ne peux pas le porter") .. (estLie and "" or " ; pas lié : tu peux le donner ou le vendre aux enchères")
  end
  return nil
end

function ns.repartir(objets)
  local parSection = {}
  for _, s in ipairs(ns.SECTIONS) do parSection[s.id] = {} end
  for _, o in ipairs(objets) do
    local liste = parSection[o.categorie] or parSection.divers
    liste[#liste + 1] = o
  end
  for _, liste in pairs(parSection) do
    table.sort(liste, function(a, b)
      if (a.qualite or 1) ~= (b.qualite or 1) then return (a.qualite or 1) > (b.qualite or 1) end
      if (a.nom or "") ~= (b.nom or "") then return (a.nom or "") < (b.nom or "") end
      if a.sac ~= b.sac then return a.sac < b.sac end
      return a.case < b.case
    end)
  end
  return parSection
end

-- Dans les objets lus, ceux de la section « À vendre » qui ne sont PAS gris
-- (l'équipement lié que le personnage ne pourra pas porter) : c'est ce que
-- Marchand auto peut vendre en plus des gris. Rend { sac, case, lien, id, raison, qualite }.
function ns.filtrerAVendre(objets)
  local l = {}
  for _, o in ipairs(objets or {}) do
    if o.categorie == "vendre" and o.qualite ~= 0 and o.sac and o.case and o.lien then
      l[#l + 1] = { sac = o.sac, case = o.case, lien = o.lien, id = o.id, raison = o.raison, qualite = o.qualite }
    end
  end
  return l
end

-- Recherche sans accents ni majuscules : « etoffe » trouve « Étoffe de lin ».
local ACCENTS = { ["à"] = "a", ["â"] = "a", ["ä"] = "a", ["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e",
  ["î"] = "i", ["ï"] = "i", ["ô"] = "o", ["ö"] = "o", ["ù"] = "u", ["û"] = "u", ["ü"] = "u", ["ç"] = "c",
  ["œ"] = "oe", ["À"] = "a", ["É"] = "e", ["È"] = "e", ["Ê"] = "e", ["Ç"] = "c", ["Œ"] = "oe", ["Ô"] = "o" }
function ns.simplifier(texte)
  texte = tostring(texte or "")
  for a, b in pairs(ACCENTS) do texte = texte:gsub(a, b) end
  return texte:lower()
end

if not CreateFrame or not hooksecurefunc then return end -- hors jeu : la suite ne sert qu'en jeu

-- ---------------------------------------------------------------------------
-- Accès au jeu, compatibles Retail et Forever
-- ---------------------------------------------------------------------------

local function infoCase(sac, case)
  if C_Container and C_Container.GetContainerItemInfo then
    local i = C_Container.GetContainerItemInfo(sac, case)
    if not i then return nil end
    return i.iconFileID, i.stackCount, i.isLocked, i.quality, i.hyperlink, i.itemID, i.isBound
  end
  local icone, nombre, verrou, qualite, _, _, lien, _, _, id = GetContainerItemInfo(sac, case)
  return icone, nombre, verrou, qualite, lien, id, nil
end

local function infoQuete(sac, case)
  if C_Container and C_Container.GetContainerItemQuestInfo then
    local q = C_Container.GetContainerItemQuestInfo(sac, case)
    return q and (q.isQuestItem or q.questID ~= nil)
  end
  if GetContainerItemQuestInfo then
    local estQuete, idQuete = GetContainerItemQuestInfo(sac, case)
    return estQuete or idQuete ~= nil
  end
end

local function infoObjet(lien)
  if C_Item and C_Item.GetItemInfo then return C_Item.GetItemInfo(lien) end
  return GetItemInfo(lien)
end

local function derniersSac()
  return NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
end

local function texteOr(cuivre)
  local f = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
  return f and f(cuivre) or tostring(math.floor(cuivre / 10000)) .. " po"
end

-- ---------------------------------------------------------------------------
-- La fenêtre
-- ---------------------------------------------------------------------------

local TAILLE, ECART, MARGE = 37, 4, 12
local colonnes = 10

local fenetre = CreateFrame("Frame", "SacsRangesSac", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
fenetre:SetSize(MARGE * 2 + colonnes * (TAILLE + ECART), 300)
fenetre:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -90, 110)
fenetre:SetFrameStrata("MEDIUM")
fenetre:SetToplevel(true)
fenetre:SetMovable(true)
fenetre:SetClampedToScreen(true)
fenetre:EnableMouse(true)
fenetre:RegisterForDrag("LeftButton")
fenetre:SetScript("OnDragStart", fenetre.StartMoving)
fenetre:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  if ns.db then
    local p, _, rp, x, y = self:GetPoint()
    ns.db.positionSac = { p, rp, x, y }
  end
end)
fenetre:Hide()
tinsert(UISpecialFrames, "SacsRangesSac") -- Échap la ferme

-- Apparence « cadre du jeu » : le modèle de fenêtre habituel, posé derrière.
local cadreWow = CreateFrame("Frame", nil, fenetre, "BasicFrameTemplateWithInset")
cadreWow:SetAllPoints()
cadreWow:SetFrameLevel(fenetre:GetFrameLevel())
if cadreWow.CloseButton then cadreWow.CloseButton:SetScript("OnClick", function() fenetre:Hide() end) end

-- Nouveau visuel : fond sombre, bordure dorée, titre or.
local fermer = CreateFrame("Button", nil, fenetre, "UIPanelCloseButton")
fermer:SetPoint("TOPRIGHT", 2, 2)
fermer:SetScript("OnClick", function() fenetre:Hide() end)

local titre = fenetre:CreateFontString(nil, "OVERLAY", "GameFontNormal")
local function appliquerApparence()
  local wow = ns.db and ns.db.apparenceWow
  cadreWow:SetShown(wow)
  fermer:SetShown(not wow)
  titre:ClearAllPoints()
  if wow then
    if fenetre.SetBackdrop then fenetre:SetBackdrop(nil) end
    titre:SetFontObject("GameFontNormal")
    titre:SetPoint("TOP", 0, -5)
  else
    if fenetre.SetBackdrop then
      fenetre:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
      })
      fenetre:SetBackdropColor(0.07, 0.06, 0.045, 0.96)
      fenetre:SetBackdropBorderColor(0.80, 0.63, 0.30, 1)
    end
    titre:SetFontObject("GameFontNormalLarge")
    titre:SetPoint("TOPLEFT", MARGE, -9)
  end
end

-- La barre : Ranger, Analyse, recherche.
local function bouton(texte, largeur, aide, action)
  local b = CreateFrame("Button", nil, fenetre, "UIPanelButtonTemplate")
  b:SetSize(largeur, 22)
  b:SetText(texte)
  b:SetScript("OnClick", action)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(texte)
    GameTooltip:AddLine(aide, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end
local bRanger = bouton("Ranger", 70, "Le tri du jeu (et la banque si elle est ouverte). Ici, les sections se rangent toutes seules.",
  function() if ns.ranger then ns.ranger() end end)
local bAnalyse = bouton("Analyse", 70, "Équipement en double, moins bon que ce que tu portes, ou que tu ne peux pas porter.",
  function() if ns.basculerPanneau then ns.basculerPanneau() end end)
bRanger:SetPoint("TOPLEFT", MARGE, -30)
bAnalyse:SetPoint("LEFT", bRanger, "RIGHT", 4, 0)

local okRecherche, recherche = pcall(CreateFrame, "EditBox", "SacsRangesRecherche", fenetre, "SearchBoxTemplate")
if not okRecherche then recherche = CreateFrame("EditBox", "SacsRangesRecherche", fenetre, "InputBoxTemplate") end
recherche:SetHeight(20)
recherche:SetPoint("LEFT", bAnalyse, "RIGHT", 12, 0)
recherche:SetPoint("RIGHT", fenetre, "RIGHT", -MARGE, 0)
recherche:SetAutoFocus(false)

-- Le contenu : un cadre par sac (son numéro sert aux cases du jeu), et les titres.
local contenu = CreateFrame("Frame", nil, fenetre)
contenu:SetPoint("TOPLEFT", MARGE, -58)
contenu:SetPoint("RIGHT", -MARGE, 0)
contenu:SetHeight(10)

local pied = fenetre:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
pied:SetPoint("BOTTOMLEFT", MARGE, 10)
local argent = fenetre:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
argent:SetPoint("BOTTOMRIGHT", -MARGE, 10)

local cadresSac, cases, titres = {}, {}, {}

local function cadreDuSac(sac)
  if not cadresSac[sac] then
    local f = CreateFrame("Frame", nil, contenu)
    f:SetID(sac)
    f:SetAllPoints()
    -- Ce que le code des cases du jeu peut demander à leur parent (Retail).
    f.GetBagID = function() return sac end
    f.IsCombinedBagContainer = function() return false end
    f.IsBankBag = function() return false end
    cadresSac[sac] = f
  end
  return cadresSac[sac]
end

-- Une case du jeu, créée une fois pour toutes pour (sac, case).
local function caseDe(sac, case)
  local cle = sac * 1000 + case
  local b = cases[cle]
  if b then return b end
  if InCombatLockdown() then return nil end
  local parent = cadreDuSac(sac)
  local nom = "SacsRangesCase" .. sac .. "_" .. case
  local ok, nouveau = pcall(CreateFrame, "ItemButton", nom, parent, "ContainerFrameItemButtonTemplate")
  if not ok or not nouveau then
    nouveau = CreateFrame("Button", nom, parent, "ContainerFrameItemButtonTemplate")
  end
  b = nouveau
  b:SetID(case)
  -- Le numéro de sac passe par SetBagID (un attribut), JAMAIS par b.bagID = sac :
  -- une valeur posée par un addon « contamine » le clic, et le jeu refuse alors
  -- d'utiliser ou d'équiper l'objet (ADDON_ACTION_FORBIDDEN sur UseContainerItem,
  -- vu en jeu le 08/11). Sans SetBagID, le jeu lit le numéro du parent (SetID).
  if b.SetBagID then pcall(b.SetBagID, b, sac) end
  b:SetSize(TAILLE, TAILLE)
  -- Le compteur de cases libres, sur la case vide qui les représente.
  b.libres = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  b.libres:SetPoint("BOTTOMRIGHT", -3, 3)
  -- La flèche verte des objets à équiper (une flèche du jeu, teintée en vert).
  b.fleche = b:CreateTexture(nil, "OVERLAY", nil, 7)
  b.fleche:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up")
  b.fleche:SetVertexColor(0.2, 1, 0.2)
  b.fleche:SetSize(22, 22)
  b.fleche:SetPoint("TOPLEFT", -5, 5)
  b.fleche:Hide()
  -- La flèche rouge vers le bas : moins bon que ce que tu portes.
  b.moins = b:CreateTexture(nil, "OVERLAY", nil, 7)
  b.moins:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
  b.moins:SetVertexColor(1, 0.25, 0.2)
  b.moins:SetSize(20, 20)
  b.moins:SetPoint("TOPLEFT", -5, 5)
  b.moins:Hide()
  b.estCaseSacsRanges = true -- pour la bulle (voir ajouterRangement plus bas)
  cases[cle] = b
  return b
end

-- Dans la bulle d'un objet du sac rangé : pourquoi il est rangé là, s'il est
-- moins bon, et la raison du conseil (sauf si l'avis est déjà dans toutes les
-- bulles). Passe par le crochet des bulles du jeu : tant que la souris reste
-- sur une case, le jeu redessine la bulle sans arrêt, ce qui effaçait des lignes
-- ajoutées une seule fois au survol (vu en jeu le 09/11).
local function ajouterRangement(tip)
  if tip ~= GameTooltip then return end
  local case = tip.GetOwner and tip:GetOwner()
  if not (case and case.estCaseSacsRanges) then return end
  local ajoute = false
  if case.raison then
    tip:AddLine(" ")
    tip:AddLine("Rangé ici : " .. case.raison, 1, 0.82, 0, true)
    ajoute = true
  end
  if case.moinsQue then
    if not ajoute then tip:AddLine(" ") end
    tip:AddLine("Moins bon que " .. case.moinsQue .. " (ce que tu portes).", 1, 0.3, 0.25, true)
  end
  local c = case.conseil
  if c and not (ns.bullesActives and ns.bullesActives()) then
    tip:AddLine(" ")
    tip:AddLine("À équiper" .. (ns.nomSpecialisation and ns.nomSpecialisation() and (" (" .. ns.nomSpecialisation() .. ")") or "")
      .. " : " .. (c.raison or ""), 0.12, 1, 0)
    if c.remplace then tip:AddLine("Remplace : " .. c.remplace, 0.6, 0.6, 0.6) end
  end
end
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ajouterRangement)
elseif GameTooltip and GameTooltip.HookScript then
  GameTooltip:HookScript("OnTooltipSetItem", ajouterRangement)
end

local function titreDe(i)
  if not titres[i] then
    local t = contenu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    t:SetJustifyH("LEFT")
    titres[i] = t
  end
  return titres[i]
end

local function remplir(b, icone, nombre, verrou, qualite, lien)
  if SetItemButtonTexture then SetItemButtonTexture(b, icone) end
  if SetItemButtonCount then SetItemButtonCount(b, nombre or 0) end
  if SetItemButtonDesaturated then SetItemButtonDesaturated(b, verrou) end
  if SetItemButtonQuality then pcall(SetItemButtonQuality, b, qualite, lien) end
  b.libres:SetText("")
  b.conseil, b.raison, b.moinsQue = nil, nil, nil
  b.fleche:Hide()
  b.moins:Hide()
end

-- Les lignes de la section « À équiper » : le nom de l'objet et la raison, à droite de la case.
local lignesConseil = {}
local function ligneConseil(i)
  if not lignesConseil[i] then
    local nom = contenu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nom:SetJustifyH("LEFT")
    local raison = contenu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    raison:SetJustifyH("LEFT")
    raison:SetTextColor(0.12, 1, 0)
    local remplace = contenu:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    remplace:SetJustifyH("LEFT")
    lignesConseil[i] = { nom = nom, raison = raison, remplace = remplace }
  end
  return lignesConseil[i]
end

-- ---------------------------------------------------------------------------
-- Mise à jour
-- ---------------------------------------------------------------------------

local aRefaire = false -- une réorganisation attend la fin du combat

local function lire(sansConseils)
  local objets, libres, total, premiereLibre = {}, 0, 0, nil
  for sac = 0, derniersSac() do
    local n = ns.nbCases and ns.nbCases(sac) or 0
    for case = 1, n do
      total = total + 1
      local icone, nombre, verrou, qualite, lien, idObjet, estLie = infoCase(sac, case)
      if icone and lien then
        local nom, _, q, _, _, _, _, _, _, _, _, classe, sousClasse, liaison, _, _, artisanat = infoObjet(lien)
        qualite = qualite or q or 1
        local utilisable, raison, texteRaison = true, nil, nil
        if (classe == 2 or classe == 4) and ns.utilisableCase then
          utilisable, raison, texteRaison = ns.utilisableCase(sac, case, lien)
        end
        local estLivre = LivresBiblio_EstUnLivre and nom and LivresBiblio_EstUnLivre(nom) or false
        local categorie = ns.categorie(classe, qualite, infoQuete(sac, case), utilisable, sousClasse, idObjet,
          { livre = estLivre, lie = liaison == 1, artisanat = artisanat, estLie = estLie, raison = raison })
        local conseil, moins
        if categorie == "equip" and not sansConseils and ns.db and ns.db.conseils ~= false and ns.conseil then
          local ok, c = pcall(ns.conseil, lien)
          if ok then conseil = c end
          if not conseil and ns.moinsBon then
            local okM, m = pcall(ns.moinsBon, lien)
            if okM then moins = m end
          end
        end
        objets[#objets + 1] = {
          sac = sac, case = case, id = idObjet, icone = icone, nombre = nombre, verrou = verrou, qualite = qualite, lien = lien,
          nom = nom or lien, categorie = categorie, conseil = conseil, moins = moins,
          raison = ns.texteRangement(categorie, qualite, estLie, texteRaison),
        }
      else
        libres = libres + 1
        premiereLibre = premiereLibre or { sac = sac, case = case }
      end
    end
  end
  return objets, libres, total, premiereLibre
end

-- Pour les autres addons (Marchand auto) : les objets non gris de la section
-- « À vendre », sans avoir besoin de la fenêtre (marche même si la vue par
-- catégories est décochée). Rien en combat, ni si Sacs rangés est coupé.
function SacsRanges_AVendre()
  if InCombatLockdown() or not (ns.db and ns.db.actif) then return {} end
  local ok, objets = pcall(lire, true)
  if not ok then return {} end
  return ns.filtrerAVendre(objets)
end

local function majVue()
  if not fenetre:IsShown() then return end
  if InCombatLockdown() then aRefaire = true end
  local db = ns.db or {}
  local objets, libres, total, premiereLibre = lire()
  colonnes = total > 110 and 14 or (total > 70 and 12 or 10)
  local largeur = colonnes * (TAILLE + ECART) - ECART
  if not InCombatLockdown() then fenetre:SetWidth(MARGE * 2 + largeur) end

  for _, b in pairs(cases) do b.utilisee = false end
  local filtre = ns.simplifier(recherche:GetText() or "")
  local function visible(o) return filtre == "" or ns.simplifier(o.nom):find(filtre, 1, true) end

  -- Les objets à équiper sortent de leur section et passent en tête, une ligne chacun.
  local aEquiper, autres = {}, {}
  for _, o in ipairs(objets) do
    if o.conseil then aEquiper[#aEquiper + 1] = o else autres[#autres + 1] = o end
  end
  table.sort(aEquiper, function(a, b) return (a.nom or "") < (b.nom or "") end)
  local parSection = ns.repartir(autres)
  local y, it = 0, 0

  if #aEquiper > 0 then
    it = it + 1
    local t = titreDe(it)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -y)
    t:SetText("À équiper  |cff888888" .. #aEquiper .. "|r")
    t:SetTextColor(0.12, 1, 0)
    t:Show()
    y = y + 16
  end
  for i, o in ipairs(aEquiper) do
    local b = caseDe(o.sac, o.case)
    local l = ligneConseil(i)
    if b then
      b.utilisee = true
      if not InCombatLockdown() then
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -y)
      end
      remplir(b, o.icone, o.nombre, o.verrou, o.qualite, o.lien)
      b.conseil = o.conseil
      b.fleche:Show()
      b:SetAlpha(visible(o) and 1 or 0.2)
      b:Show()
    end
    l.nom:ClearAllPoints()
    l.nom:SetPoint("TOPLEFT", contenu, "TOPLEFT", TAILLE + 8, -(y + 1))
    l.nom:SetText(o.lien or o.nom)
    l.raison:ClearAllPoints()
    l.raison:SetPoint("TOPLEFT", l.nom, "BOTTOMLEFT", 0, -1)
    l.raison:SetText(o.conseil.raison or "")
    l.remplace:ClearAllPoints()
    l.remplace:SetPoint("TOPLEFT", l.raison, "BOTTOMLEFT", 0, -1)
    l.remplace:SetText(o.conseil.remplace and ("remplace : " .. o.conseil.remplace) or "")
    for _, fs in pairs(l) do
      fs:SetWidth(largeur - TAILLE - 8)
      if fs.SetWordWrap then fs:SetWordWrap(false) end
      fs:Show()
    end
    y = y + TAILLE + ECART + 4
  end
  for i = #aEquiper + 1, #lignesConseil do
    local l = lignesConseil[i]
    l.nom:Hide(); l.raison:Hide(); l.remplace:Hide()
  end
  if #aEquiper > 0 then y = y + 6 end

  for _, s in ipairs(ns.SECTIONS) do
    local liste = parSection[s.id]
    if #liste > 0 then
      it = it + 1
      local t = titreDe(it)
      t:ClearAllPoints()
      t:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -y)
      t:SetText(s.nom .. "  |cff888888" .. #liste .. "|r")
      t:SetTextColor(s.couleur[1], s.couleur[2], s.couleur[3])
      t:Show()
      y = y + 16
      for i, o in ipairs(liste) do
        local b = caseDe(o.sac, o.case)
        if b then
          b.utilisee = true
          if not InCombatLockdown() then
            local col, ligne = (i - 1) % colonnes, math.floor((i - 1) / colonnes)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", contenu, "TOPLEFT", col * (TAILLE + ECART), -(y + ligne * (TAILLE + ECART)))
          end
          remplir(b, o.icone, o.nombre, o.verrou, o.qualite, o.lien)
          b.raison, b.moinsQue = o.raison, o.moins
          if o.moins then b.moins:Show() end
          b:SetAlpha(visible(o) and 1 or 0.2)
          b:Show()
        end
      end
      y = y + math.ceil(#liste / colonnes) * (TAILLE + ECART) + 6
    end
  end

  -- Une seule case vide pour déposer un objet, avec le nombre de cases libres.
  if premiereLibre then
    it = it + 1
    local t = titreDe(it)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -y)
    t:SetText("Cases libres  |cff888888" .. libres .. "|r")
    t:SetTextColor(0.6, 0.6, 0.6)
    t:Show()
    y = y + 16
    local b = caseDe(premiereLibre.sac, premiereLibre.case)
    if b then
      b.utilisee = true
      if not InCombatLockdown() then
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -y)
      end
      remplir(b, nil, 0, false, nil, nil)
      b.libres:SetText(libres)
      b:SetAlpha(1)
      b:Show()
    end
    y = y + TAILLE + ECART
  end

  for i = it + 1, #titres do titres[i]:Hide() end
  if not InCombatLockdown() then
    for _, b in pairs(cases) do if not b.utilisee then b:Hide() end end
    contenu:SetHeight(math.max(y, 10))
    fenetre:SetHeight(58 + y + 30)
  end

  titre:SetText("Sacs de " .. (UnitName("player") or "?"))
  pied:SetText(libres .. " cases libres sur " .. total)
  argent:SetText(texteOr(GetMoney()))
  if db.apparenceWow ~= fenetre.apparence then
    fenetre.apparence = db.apparenceWow
    appliquerApparence()
  end
end

recherche:HookScript("OnTextChanged", majVue)
fenetre:SetScript("OnShow", function()
  appliquerApparence()
  majVue()
  if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_BACKPACK_OPEN) end
end)
fenetre:SetScript("OnHide", function()
  if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_BACKPACK_CLOSE) end
end)

-- ---------------------------------------------------------------------------
-- Remplacer les sacs du jeu quand l'option est cochée
-- ---------------------------------------------------------------------------

local function vueActive()
  return ns.db and ns.db.actif and ns.db.vueCategories
end

local function fenetresDuJeu()
  local l = {}
  if ContainerFrameCombinedBags then l[#l + 1] = ContainerFrameCombinedBags end
  for i = 1, (NUM_CONTAINER_FRAMES or 13) do
    local f = _G["ContainerFrame" .. i]
    if f then l[#l + 1] = f end
  end
  return l
end

-- Une fenêtre de sac du jeu qui s'ouvre se referme aussitôt quand notre vue est active.
for _, f in ipairs(fenetresDuJeu()) do
  f:HookScript("OnShow", function(self)
    if vueActive() then self:Hide() end
  end)
end

-- Le jeu enchaîne ses fonctions : B appelle « basculer », qui appelle à son tour
-- « ouvrir » (il croit ses sacs fermés, puisqu'on les cache). Réagir à chacune
-- ouvrait puis refermait aussitôt la fenêtre. On note donc tout ce qui arrive
-- pendant une image et on décide une seule fois, à l'image suivante : une
-- bascule l'emporte (on inverse l'état d'avant), sinon la dernière demande.
local etatAvant, bascule, demande, decisionPrevue = nil, false, nil, false

local function decider()
  decisionPrevue = false
  local montrer
  if bascule then montrer = not etatAvant else montrer = demande end
  etatAvant, bascule, demande = nil, false, nil
  if montrer == nil then return end
  if montrer and not vueActive() then return end
  fenetre:SetShown(montrer)
end

local function noter(quoi)
  if not vueActive() and quoi ~= "fermer" then return end
  if etatAvant == nil then etatAvant = fenetre:IsShown() end
  if quoi == "basculer" then bascule = true else demande = (quoi == "ouvrir") end
  if not decisionPrevue then
    decisionPrevue = true
    C_Timer.After(0, decider)
  end
end

for nom, quoi in pairs({
  ToggleAllBags = "basculer", ToggleBackpack = "basculer", ToggleBag = "basculer",
  OpenAllBags = "ouvrir", OpenBackpack = "ouvrir",
  CloseAllBags = "fermer", CloseBackpack = "fermer",
}) do
  if _G[nom] then hooksecurefunc(nom, function() noter(quoi) end) end
end

-- Bouton des réglages : montre le sac par catégories, ou prévient qu'il est coupé.
function ns.ouvrirVue()
  if not vueActive() then
    if ns.reglages then
      ns.reglages.dire(ns.db and not ns.db.actif and "Sacs rangés est coupé : active-le d'abord."
        or "le sac par catégories n'est pas activé : coche-le dans les réglages.")
    end
    return
  end
  if fenetre:IsShown() then fenetre:Raise() else fenetre:Show() end
end

-- Option cochée ou décochée, apparence changée.
function ns.vueMaj()
  if not vueActive() then fenetre:Hide() return end
  if fenetre:IsShown() then appliquerApparence(); majVue() end
end

-- ---------------------------------------------------------------------------
-- Événements
-- ---------------------------------------------------------------------------

local ecouteur = CreateFrame("Frame")
for _, e in ipairs({ "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED", "PLAYER_MONEY", "PLAYER_REGEN_ENABLED",
  "QUEST_ACCEPTED", "QUEST_REMOVED", "GET_ITEM_INFO_RECEIVED", "PLAYER_LOGIN" }) do
  pcall(ecouteur.RegisterEvent, ecouteur, e)
end
local enAttente = false
ecouteur:SetScript("OnEvent", function(_, evenement)
  if evenement == "PLAYER_LOGIN" then
    local p = ns.db and ns.db.positionSac
    if p then fenetre:ClearAllPoints(); fenetre:SetPoint(p[1], UIParent, p[2], p[3], p[4]) end
    return
  end
  if evenement == "PLAYER_REGEN_ENABLED" and not aRefaire then return end
  if not fenetre:IsShown() then return end
  aRefaire = false
  -- Plusieurs événements d'affilée : une seule mise à jour.
  if enAttente then return end
  enAttente = true
  C_Timer.After(0.05, function() enAttente = false; majVue() end)
end)
