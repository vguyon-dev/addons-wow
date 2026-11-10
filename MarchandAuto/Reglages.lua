-- ============================================================================
-- Reglages.lua : LA fenêtre de réglages de tous les addons de Valentin.
--
-- Fichier COMMUN : la même copie se trouve dans chaque addon du dépôt
-- (QuetesAuto, MarchandAuto…). Si tu le modifies, recopie-le dans les autres
-- (un test vérifie qu'ils sont identiques).
--
-- Une seule fenêtre « Addons de Valentin » (créée par le premier addon chargé) :
--   - à gauche, la liste des addons avec un point vert (activé) ou rouge (coupé) ;
--     clic = ses réglages, clic droit = activer ou couper, Maj+clic = son panneau ;
--   - à droite, la page de l'addon : interrupteur général, un onglet par
--     section, des interrupteurs et des curseurs, les boutons d'action en bas ;
--   - en haut, une recherche qui trouve un réglage dans tous les addons.
--
-- Utilisation, dans le fichier principal de l'addon :
--   local reglages = ns.creerReglages({
--     titre = "Mon addon",                      -- nom affiché
--     icone = "Interface\\Icons\\…",
--     nomDB = "MonAddonDB",                     -- SavedVariables du .toc
--     defauts = { actif = true, … },            -- valeurs de départ
--     options = {
--       { titre = "Section" },                                 -- un onglet
--       { cle = "x", libelle = "…", aide = "…" },              -- interrupteur
--       { cle = "x", libelle = "…", dependDe = "y" },          -- grisé si y est coupé
--       { cle = "x", libelle = "…", dependDe = "!y" },         -- grisé si y est activé
--       { cle = "n", type = "nombre", libelle = "…", min = 0, max = 20, pas = 1 }, -- curseur
--     },
--     boutons = { { texte = "…", aide = "…", action = fonction }, … }, -- en bas de la page
--     ouvrirHub = fonction, texteHub = "…",     -- le panneau de l'addon : un bouton en bas
--                                               -- de la page et Maj+clic dans la liste
--     contenu = function(f, y, r) … return y, maj end, -- facultatif : un onglet en plus
--     ongletContenu = "Listes",                 -- le nom de cet onglet (« Détails » sinon)
--     astuce = "texte sous le premier onglet",  -- facultatif
--     auChargement = function(db) … end,        -- quand les réglages sont lus
--     surChangement = function(db) … end,       -- après chaque changement
--   })
-- Quand l'addon a une option « actif », les autres sont grisées tant qu'il est
-- coupé (sauf « minimap » et les options marquées toujours = true).
-- Tout s'applique tout de suite, sans /reload.
--
-- ns.creerListe(parent, y, spec) : une liste d'objets éditable (retrait d'une
-- ligne, dépôt d'un objet du sac), à utiliser dans contenu().
-- ============================================================================

local NOM_ADDON, ns = ...

local function nombre(v, defaut) return type(v) == "number" and v or defaut end

local LARGEUR, HAUTEUR, COTE, PAGE = 790, 570, 200, 540
local FOND = { bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } }

-- ============================================================ l'habillage commun
-- Le visuel « sombre et doré » de toutes les fenêtres propres aux addons.

local HABILLAGE = {
  fond = { 0.07, 0.06, 0.045, 0.96 },
  bordure = { 0.80, 0.63, 0.30, 1 },
  couleurTitre = { 1, 0.82, 0.30 },
}

-- Ce que ns.habiller va appliquer, options facultatives comprises (fonction pure,
-- testée hors jeu). options : titre = "…", fermer = vrai, trait = faux pour
-- sans filet doré sous le titre, fond = { r, v, b, a }, bordure = { r, v, b, a }.
function ns.styleHabillage(options)
  options = type(options) == "table" and options or {}
  local function couleur(c, defaut, avecAlpha)
    if type(c) ~= "table" then c = defaut end
    local r, v, b = nombre(c[1], defaut[1]), nombre(c[2], defaut[2]), nombre(c[3], defaut[3])
    if avecAlpha then return { r, v, b, nombre(c[4], defaut[4] or 1) } end
    return { r, v, b }
  end
  local titre = type(options.titre) == "string" and options.titre ~= "" and options.titre or nil
  return {
    fond = couleur(options.fond, HABILLAGE.fond, true),
    bordure = couleur(options.bordure, HABILLAGE.bordure, true),
    couleurTitre = couleur(options.couleurTitre, HABILLAGE.couleurTitre, false),
    titre = titre,
    fermer = options.fermer and true or false,
    trait = titre ~= nil and options.trait ~= false,
  }
end

-- Habille un cadre : fond sombre, bordure dorée et, si on les demande, un titre doré
-- et une croix de fermeture. Un cadre sans SetBackdrop (créé sans BackdropTemplate)
-- reçoit un enfant BackdropTemplate en fond. Renvoie le titre et la croix (ou nil) :
-- l'appelant peut donner son propre OnClick à la croix.
-- Rien d'autre n'est touché : ni position, ni scripts, ni taille.
function ns.habiller(cadre, options)
  if not cadre then return end
  local s = ns.styleHabillage(options)

  local cible = cadre
  if not cadre.SetBackdrop then
    cible = cadre.fondHabille
    if not cible and BackdropTemplateMixin then
      local ok, enfant = pcall(CreateFrame, "Frame", nil, cadre, "BackdropTemplate")
      if ok and enfant then
        enfant:SetAllPoints(cadre)
        local niveau = cadre.GetFrameLevel and cadre:GetFrameLevel() or 1
        enfant:SetFrameLevel(math.max(niveau - 1, 0))
        enfant:EnableMouse(false)
        cadre.fondHabille = enfant
        cible = enfant
      end
    end
  end
  if cible and cible.SetBackdrop then
    cible:SetBackdrop(FOND)
    cible:SetBackdropColor(s.fond[1], s.fond[2], s.fond[3], s.fond[4])
    cible:SetBackdropBorderColor(s.bordure[1], s.bordure[2], s.bordure[3], s.bordure[4])
  end

  local titre, fermer
  if s.titre then
    titre = cadre.titreHabille
    if not titre then
      titre = cadre:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
      titre:SetPoint("TOPLEFT", 12, -8)
      cadre.titreHabille = titre
    end
    titre:SetText(s.titre)
    titre:SetTextColor(s.couleurTitre[1], s.couleurTitre[2], s.couleurTitre[3])
    if s.trait and not cadre.traitHabille then
      local trait = cadre:CreateTexture(nil, "ARTWORK")
      trait:SetColorTexture(s.bordure[1], s.bordure[2], s.bordure[3], 0.6)
      trait:SetPoint("TOPLEFT", 6, -27)
      trait:SetPoint("TOPRIGHT", -6, -27)
      trait:SetHeight(1)
      cadre.traitHabille = trait
    end
  end
  if s.fermer then
    fermer = cadre.fermerHabille
    if not fermer then
      fermer = CreateFrame("Button", nil, cadre, "UIPanelCloseButton")
      fermer:SetSize(22, 22)
      fermer:SetPoint("TOPRIGHT", -2, -2)
      fermer:SetScript("OnClick", function() cadre:Hide() end)
      cadre.fermerHabille = fermer
    end
  end
  return titre, fermer
end

-- Recherche sans accents ni majuscules.
local ACCENTS = { ["à"] = "a", ["â"] = "a", ["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e", ["î"] = "i",
  ["ï"] = "i", ["ô"] = "o", ["ù"] = "u", ["û"] = "u", ["ç"] = "c", ["É"] = "e", ["À"] = "a", ["Ê"] = "e",
  ["È"] = "e", ["Ç"] = "c", ["Î"] = "i", ["Ô"] = "o", ["Â"] = "a", ["Ù"] = "u", ["Û"] = "u", ["œ"] = "oe" }
local function simple(t)
  t = tostring(t or "")
  for a, b in pairs(ACCENTS) do t = t:gsub(a, b) end
  return t:lower()
end
ns.simpleRecherche = simple

-- Les réglages qui contiennent le texte cherché.
--   entrees : { { titre, recherche = { { libelle, aide, section, onglet } } } }
-- Renvoie { { entree, item } } (fonction pure, testée hors jeu).
function ns.chercherReglages(entrees, texte)
  local q = simple(texte)
  local resultats = {}
  if q == "" then return resultats end
  for _, e in ipairs(entrees) do
    for _, item in ipairs(e.recherche or {}) do
      if simple(item.libelle .. " " .. (item.aide or "") .. " " .. e.titre):find(q, 1, true) then
        resultats[#resultats + 1] = { entree = e, item = item }
      end
    end
  end
  return resultats
end

-- ============================================================ petits outils

-- Un bouton de la fenêtre, avec sa bulle d'aide.
local function creerBouton(parent, texte, aide, action, largeur)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(largeur or 150, 22)
  b:SetText(texte)
  b:SetScript("OnClick", function() action() end)
  if aide then
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:AddLine(self:GetText() or texte)
      GameTooltip:AddLine(aide, 1, 1, 1, true)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  return b
end
ns.creerBouton = creerBouton

-- Un interrupteur : vert à droite = activé, rouge sombre à gauche = coupé.
local function creerInterrupteur(parent, surClic)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(42, 20)
  local bord = b:CreateTexture(nil, "BACKGROUND")
  bord:SetAllPoints()
  bord:SetColorTexture(0, 0, 0, 1)
  local fond = b:CreateTexture(nil, "BORDER")
  fond:SetPoint("TOPLEFT", 1, -1)
  fond:SetPoint("BOTTOMRIGHT", -1, 1)
  local pastille = b:CreateTexture(nil, "ARTWORK")
  pastille:SetSize(16, 16)
  pastille:SetColorTexture(0.88, 0.82, 0.70, 1)
  local etat = false
  function b.poser(v)
    etat = v and true or false
    pastille:ClearAllPoints()
    if etat then
      fond:SetColorTexture(0.16, 0.52, 0.12, 1)
      pastille:SetPoint("RIGHT", -2, 0)
    else
      fond:SetColorTexture(0.32, 0.10, 0.07, 1)
      pastille:SetPoint("LEFT", 2, 0)
    end
  end
  function b.permettre(v)
    if v then b:Enable() else b:Disable() end
    b:SetAlpha(v and 1 or 0.4)
  end
  b:SetScript("OnClick", function()
    if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856) end
    surClic(not etat)
  end)
  b.poser(false)
  return b
end

-- Un curseur fait main (les modèles du jeu changent d'une version à l'autre).
local function creerCurseur(parent, mini, maxi, pas)
  local s = CreateFrame("Slider", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  s:SetOrientation("HORIZONTAL")
  s:SetSize(170, 16)
  if s.SetBackdrop then
    s:SetBackdrop({
      bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
      edgeFile = "Interface\\Buttons\\UI-SliderBar-Border", edgeSize = 8, tile = true, tileSize = 8,
      insets = { left = 3, right = 3, top = 6, bottom = 6 },
    })
  end
  s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  local poignee = s.GetThumbTexture and s:GetThumbTexture()
  if poignee then poignee:SetSize(32, 32) end
  s:SetMinMaxValues(mini, maxi)
  s:SetValueStep(pas)
  if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
  s:EnableMouseWheel(true)
  s:SetScript("OnMouseWheel", function(self, sens)
    if self:IsEnabled() then self:SetValue(self:GetValue() + sens * pas) end
  end)
  return s
end

-- La hauteur réelle d'un texte (repli quand elle n'est pas encore connue).
local function hauteurTexte(fs, defaut)
  local h = fs.GetStringHeight and fs:GetStringHeight()
  return math.max(nombre(h, defaut), defaut)
end

-- ============================================================ liste éditable
-- spec = {
--   titre = "…", vide = "texte quand la liste est vide", hauteur = lignes visibles (5),
--   lignes = function() return { { texte = "…", lien = lien ou nil, retirer = fonction, clic = fonction ou nil }, … } end,
--   deposer = function(idObjet, lien, quantite) end,   -- facultatif : zone de dépôt
--   texteDepot = "…", quantite = 20,                   -- quantite : un champ nombre en plus
--   vider = function() end,                            -- facultatif : bouton « Tout retirer »
-- }
-- Renvoie le nouveau y et une fonction maj().
function ns.creerListe(parent, y, spec)
  local visibles = spec.hauteur or 5
  local HAUT = 18
  local t = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  t:SetPoint("TOPLEFT", 16, y - 4)
  y = y - 22

  local cadre = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  cadre:SetPoint("TOPLEFT", 16, y)
  cadre:SetSize(370, visibles * HAUT + 8)
  if cadre.SetBackdrop then
    cadre:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    cadre:SetBackdropColor(0, 0, 0, 0.35)
    cadre:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
  end
  local videTexte = cadre:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  videTexte:SetPoint("CENTER")
  videTexte:SetText(spec.vide or "Vide.")

  local decalage, donnees = 0, {}
  local boutons = {}
  local maj
  for i = 1, visibles do
    local l = CreateFrame("Button", nil, cadre)
    l:SetPoint("TOPLEFT", 4, -4 - (i - 1) * HAUT)
    l:SetSize(340, HAUT)
    l:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    l.texte = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l.texte:SetPoint("LEFT", 4, 0)
    l.texte:SetPoint("RIGHT", -4, 0)
    l.texte:SetJustifyH("LEFT")
    if l.texte.SetWordWrap then l.texte:SetWordWrap(false) end
    l.croix = CreateFrame("Button", nil, cadre, "UIPanelCloseButton")
    l.croix:SetSize(18, 18)
    l.croix:SetPoint("LEFT", l, "RIGHT", 2, 0)
    l.croix:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine("Retirer de la liste")
      GameTooltip:Show()
    end)
    l.croix:SetScript("OnLeave", function() GameTooltip:Hide() end)
    l:SetScript("OnEnter", function(self)
      if self.lien then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        pcall(GameTooltip.SetHyperlink, GameTooltip, self.lien)
        GameTooltip:Show()
      end
    end)
    l:SetScript("OnLeave", function() GameTooltip:Hide() end)
    boutons[i] = l
  end
  cadre:EnableMouseWheel(true)
  cadre:SetScript("OnMouseWheel", function(_, sens)
    local nouveau = math.max(0, math.min(decalage - sens, math.max(0, #donnees - visibles)))
    if nouveau == decalage then
      -- La liste ne bouge plus (courte, ou au bout) : c'est la page qui défile.
      local defile = parent.GetParent and parent:GetParent()
      local estDefilant = defile and defile.IsObjectType and defile:IsObjectType("ScrollFrame")
      local roulette = estDefilant and defile:GetScript("OnMouseWheel")
      if roulette then roulette(defile, sens) end
      return
    end
    decalage = nouveau
    maj()
  end)
  y = y - (visibles * HAUT + 8) - 6

  -- La zone de dépôt : on y lâche un objet pris dans le sac (ou on clique avec).
  local depot, qte
  if spec.deposer then
    depot = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    depot:SetPoint("TOPLEFT", 16, y)
    depot:SetSize(spec.quantite and 300 or 370, 26)
    if depot.SetBackdrop then
      depot:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
      depot:SetBackdropColor(0.2, 0.15, 0.05, 0.5)
      depot:SetBackdropBorderColor(0.8, 0.63, 0.3, 0.9)
    end
    local dt = depot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dt:SetPoint("CENTER")
    dt:SetText(spec.texteDepot or "Glisse un objet de ton sac ici pour l'ajouter")
    local function recevoir()
      local genre, id, lien = GetCursorInfo()
      if genre ~= "item" then return end
      local n = qte and tonumber(qte:GetText()) or nil
      ClearCursor()
      spec.deposer(id, lien, n)
      maj()
    end
    depot:RegisterForClicks("LeftButtonUp")
    depot:SetScript("OnReceiveDrag", recevoir)
    depot:SetScript("OnClick", recevoir)
    if spec.quantite then
      qte = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
      qte:SetSize(50, 20)
      qte:SetPoint("LEFT", depot, "RIGHT", 12, 0)
      qte:SetAutoFocus(false)
      qte:SetNumeric(true)
      qte:SetMaxLetters(4)
      qte:SetText(tostring(spec.quantite))
      local q = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
      q:SetPoint("BOTTOM", qte, "TOP", 0, 0)
      q:SetText("Quantité")
    end
    y = y - 32
  end
  if spec.vider then
    local b = creerBouton(parent, "Tout retirer", "Vide toute la liste.", function() spec.vider(); maj() end, 120)
    b:SetPoint("TOPLEFT", 16, y)
    y = y - 28
  end

  maj = function()
    donnees = spec.lignes() or {}
    decalage = math.max(0, math.min(decalage, math.max(0, #donnees - visibles)))
    t:SetText((spec.titre or "") .. "  |cff888888" .. #donnees .. "|r")
    videTexte:SetShown(#donnees == 0)
    for i, l in ipairs(boutons) do
      local d = donnees[i + decalage]
      if d then
        l.texte:SetText(d.texte)
        l.lien = d.lien
        l.croix:SetScript("OnClick", function() d.retirer(); maj() end)
        -- Une ligne peut aussi se cliquer (d.clic), par exemple pour lancer une recherche.
        l:SetScript("OnClick", d.clic and function() d.clic() end or nil)
        l:Show(); l.croix:Show()
      else
        l:Hide(); l.croix:Hide()
      end
    end
  end
  return y, maj
end

-- ============================================================ la fenêtre commune
-- _G.ValentinAddons : { entrees, fenetre, zone, courant, … }, créé par le premier
-- addon chargé. Une entrée : { titre, icone, db, ouvrir, basculer, actif = fonction,
-- panneau = fonction ou nil, page = cadre, recherche = { … }, allerOnglet = fonction }.

local function leHub()
  local hub = _G.ValentinAddons
  if hub and hub.pret then return hub end
  hub = hub or {}
  hub.entrees = hub.entrees or {}
  _G.ValentinAddons = hub

  -- Si une copie précédente a échoué en route, on repart de sa fenêtre.
  local fenetre = _G.ValentinAddonsReglages
    or CreateFrame("Frame", "ValentinAddonsReglages", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  hub.fenetre = fenetre
  fenetre:SetSize(LARGEUR, HAUTEUR)
  fenetre:SetPoint("CENTER")
  fenetre:SetFrameStrata("DIALOG")
  fenetre:SetToplevel(true)
  fenetre:SetMovable(true)
  fenetre:SetClampedToScreen(true)
  fenetre:EnableMouse(true)
  fenetre:RegisterForDrag("LeftButton")
  fenetre:SetScript("OnDragStart", fenetre.StartMoving)
  fenetre:SetScript("OnDragStop", fenetre.StopMovingOrSizing)
  if fenetre.SetBackdrop then
    fenetre:SetBackdrop(FOND)
    fenetre:SetBackdropColor(0.07, 0.06, 0.045, 0.97)
    fenetre:SetBackdropBorderColor(0.80, 0.63, 0.30, 1)
  end
  fenetre:Hide()
  tinsert(UISpecialFrames, "ValentinAddonsReglages") -- Échap la ferme

  local titre = fenetre:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  titre:SetPoint("TOPLEFT", 14, -12)
  titre:SetText("Addons de Valentin")
  local fermer = CreateFrame("Button", nil, fenetre, "UIPanelCloseButton")
  fermer:SetPoint("TOPRIGHT", 0, 0)
  fermer:SetScript("OnClick", function() fenetre:Hide() end)
  local trait = fenetre:CreateTexture(nil, "ARTWORK")
  trait:SetColorTexture(0.80, 0.63, 0.30, 0.6)
  trait:SetPoint("TOPLEFT", 6, -38)
  trait:SetPoint("TOPRIGHT", -6, -38)
  trait:SetHeight(1)

  local okR, recherche = pcall(CreateFrame, "EditBox", "ValentinAddonsRecherche", fenetre, "SearchBoxTemplate")
  if not okR or not recherche then recherche = CreateFrame("EditBox", "ValentinAddonsRecherche", fenetre, "InputBoxTemplate") end
  recherche:SetSize(220, 20)
  recherche:SetPoint("TOPRIGHT", -40, -10)
  recherche:SetAutoFocus(false)
  hub.recherche = recherche

  -- La liste des addons, à gauche.
  local cote = CreateFrame("Frame", nil, fenetre)
  cote:SetPoint("TOPLEFT", 6, -42)
  cote:SetPoint("BOTTOMLEFT", 6, 6)
  cote:SetWidth(COTE)
  local fondCote = cote:CreateTexture(nil, "BACKGROUND")
  fondCote:SetAllPoints()
  fondCote:SetColorTexture(0, 0, 0, 0.25)
  local aideCote = cote:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  aideCote:SetPoint("BOTTOMLEFT", 6, 6)
  aideCote:SetWidth(COTE - 12)
  aideCote:SetJustifyH("LEFT")
  aideCote:SetText("Clic droit : activer ou couper\nMaj+clic : le panneau de l'addon")

  -- La zone des pages, à droite.
  local zone = CreateFrame("Frame", nil, fenetre)
  zone:SetPoint("TOPLEFT", COTE + 14, -44)
  zone:SetPoint("BOTTOMRIGHT", -8, 8)
  hub.zone = zone

  -- Les résultats de la recherche.
  local resultats = CreateFrame("Frame", nil, zone)
  resultats:SetAllPoints()
  resultats:Hide()
  local titreResultats = resultats:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  titreResultats:SetPoint("TOPLEFT", 8, -6)
  local lignesResultats = {}

  local lignes = {}
  function hub.majCote()
    table.sort(hub.entrees, function(a, b) return a.titre < b.titre end)
    for i, e in ipairs(hub.entrees) do
      local l = lignes[i]
      if not l then
        l = CreateFrame("Button", nil, cote)
        l:SetSize(COTE - 8, 24)
        l:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 25)
        l:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        l:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        l.choisi = l:CreateTexture(nil, "BACKGROUND")
        l.choisi:SetAllPoints()
        l.choisi:SetColorTexture(0.80, 0.63, 0.30, 0.22)
        l.icone = l:CreateTexture(nil, "ARTWORK")
        l.icone:SetSize(18, 18)
        l.icone:SetPoint("LEFT", 4, 0)
        l.nom = l:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        l.nom:SetPoint("LEFT", l.icone, "RIGHT", 6, 0)
        l.point = l:CreateTexture(nil, "OVERLAY")
        l.point:SetSize(8, 8)
        l.point:SetPoint("RIGHT", -6, 0)
        lignes[i] = l
      end
      l.icone:SetTexture(e.icone)
      l.nom:SetText(e.titre)
      local actif = e.actif and e.actif()
      l.point:SetShown(actif ~= nil)
      if actif then l.point:SetColorTexture(0.24, 0.86, 0.24, 1) else l.point:SetColorTexture(1, 0.29, 0.23, 1) end
      l.icone:SetDesaturated(actif == false)
      if e == hub.courant then l.nom:SetTextColor(1, 0.82, 0) else l.nom:SetTextColor(1, 1, 1) end
      l.choisi:SetShown(e == hub.courant)
      l:SetScript("OnClick", function(_, souris)
        if souris == "RightButton" then
          if e.basculer then e.basculer() end
        elseif IsShiftKeyDown() and e.panneau then
          fenetre:Hide()
          e.panneau()
        else
          recherche:SetText("")
          if recherche.ClearFocus then recherche:ClearFocus() end
          hub.selectionner(e)
        end
      end)
      l:Show()
    end
    for i = #hub.entrees + 1, #lignes do lignes[i]:Hide() end
    -- Beaucoup d'addons : la fenêtre grandit pour tous les montrer.
    fenetre:SetHeight(math.max(HAUTEUR, #hub.entrees * 25 + 96))
  end

  function hub.selectionner(e)
    hub.courant = e or hub.courant or hub.entrees[1]
    for _, x in ipairs(hub.entrees) do
      if x.page and x ~= hub.courant then x.page:Hide() end
    end
    resultats:Hide()
    if hub.courant and hub.courant.page then hub.courant.page:Show() end
    hub.majCote()
  end

  function hub.montrer(e)
    if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
    if fenetre:IsShown() then fenetre:Raise() else fenetre:Show() end
    if recherche:GetText() ~= "" then recherche:SetText("") end
    hub.selectionner(e)
  end

  function hub.basculerFenetre()
    if fenetre:IsShown() then fenetre:Hide() else hub.montrer(nil) end
  end

  -- La recherche : chaque résultat mène au bon addon et au bon onglet.
  function hub.chercher(texte)
    local trouves = ns.chercherReglages(hub.entrees, texte)
    if simple(texte) == "" then hub.selectionner(hub.courant) return end
    for _, x in ipairs(hub.entrees) do
      if x.page then x.page:Hide() end
    end
    resultats:Show()
    titreResultats:SetText(#trouves == 0 and "Aucun réglage ne contient ce texte."
      or (#trouves .. " réglage(s) trouvé(s)" .. (#trouves > 14 and ", les 14 premiers ci-dessous" or "") .. " : clique pour y aller"))
    for i = 1, math.max(#trouves, #lignesResultats) do
      local l = lignesResultats[i]
      local t = trouves[i]
      if t and i <= 14 then
        if not l then
          l = CreateFrame("Button", nil, resultats)
          l:SetSize(PAGE, 32)
          l:SetPoint("TOPLEFT", 4, -28 - (i - 1) * 34)
          l:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
          l.chemin = l:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
          l.chemin:SetPoint("TOPLEFT", 6, -2)
          l.libelle = l:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
          l.libelle:SetPoint("TOPLEFT", 6, -14)
          lignesResultats[i] = l
        end
        l.chemin:SetText(t.entree.titre .. "  >  " .. (t.item.section or ""))
        l.libelle:SetText(t.item.libelle)
        l:SetScript("OnClick", function()
          recherche:SetText("")
          if recherche.ClearFocus then recherche:ClearFocus() end
          hub.selectionner(t.entree)
          if t.entree.allerOnglet then t.entree.allerOnglet(t.item.onglet) end
        end)
        l:Show()
      elseif l then
        l:Hide()
      end
    end
  end
  recherche:HookScript("OnTextChanged", function(self) hub.chercher(self:GetText()) end)

  -- L'icône commune autour de la minimap : un clic ouvre la fenêtre.
  if not _G.ValentinAddonsMinimap then
    local bouton = CreateFrame("Button", "ValentinAddonsMinimap", Minimap)
    bouton:SetSize(31, 31)
    bouton:SetFrameStrata("MEDIUM")
    bouton:SetFrameLevel(8)
    bouton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    bouton:RegisterForDrag("LeftButton")
    bouton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local fond = bouton:CreateTexture(nil, "BACKGROUND")
    fond:SetSize(20, 20)
    fond:SetPoint("TOPLEFT", 7, -5)
    fond:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    local icone = bouton:CreateTexture(nil, "ARTWORK")
    icone:SetSize(17, 17)
    icone:SetPoint("TOPLEFT", 7, -6)
    icone:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
    local cadre = bouton:CreateTexture(nil, "OVERLAY")
    cadre:SetSize(53, 53)
    cadre:SetPoint("TOPLEFT")
    cadre:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    -- Angle gardé : celui du premier addon inscrit qui en a un.
    local function angle()
      for _, x in ipairs(hub.entrees) do
        if x.db and x.db.angleHub then return x.db.angleHub end
      end
      return 200
    end
    function hub.placer()
      local rayon = nombre(Minimap:GetWidth(), 140) / 2 + 5
      local a = math.rad(angle())
      bouton:ClearAllPoints()
      bouton:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * rayon, math.sin(a) * rayon)
    end
    local function suivreSouris()
      local cx, cy = Minimap:GetCenter()
      local sx, sy = GetCursorPosition()
      local echelle = Minimap:GetEffectiveScale()
      local a = math.deg(math.atan2(sy / echelle - cy, sx / echelle - cx))
      for _, x in ipairs(hub.entrees) do if x.db then x.db.angleHub = a end end
      hub.placer()
    end
    bouton:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", suivreSouris) end)
    bouton:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    bouton:SetScript("OnClick", function() hub.basculerFenetre() end)
    bouton:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:AddLine("Addons de Valentin")
      for _, x in ipairs(hub.entrees) do
        local actif = x.actif and x.actif()
        local etat = actif == nil and "" or (actif and "|cff00ff00activé|r" or "|cffff4040coupé|r")
        GameTooltip:AddDoubleLine(x.titre, etat, 1, 1, 1)
      end
      GameTooltip:AddLine("Clic : tous les réglages\nGlisser : déplacer", 0.7, 0.7, 0.7)
      GameTooltip:Show()
    end)
    bouton:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  hub.placer = hub.placer or function() end
  hub.pret = true
  return hub
end

-- Inscrit un addon dans la fenêtre commune.
function ns.inscrireAuHub(e)
  local hub = leHub()
  table.insert(hub.entrees, e)
  hub.placer()
  hub.majCote()
  -- Un réglage change ailleurs (commande, raccourci) : la liste se remet à jour.
  e.maj = function() hub.majCote() end
  return e
end

-- ============================================================ la page d'un addon

function ns.creerReglages(p)
  local r = {}
  local db
  local hub = leHub()

  local function dire(texte) print("|cffffd200" .. p.titre .. "|r : " .. texte) end
  r.dire = dire

  local page = CreateFrame("Frame", NOM_ADDON .. "Reglages", hub.zone)
  page:SetAllPoints()
  page:Hide()

  -- ------------------------------------------------------- en-tête
  local icone = page:CreateTexture(nil, "ARTWORK")
  icone:SetSize(34, 34)
  icone:SetPoint("TOPLEFT", 6, -4)
  icone:SetTexture(p.icone)
  local nom = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  nom:SetPoint("TOPLEFT", icone, "TOPRIGHT", 10, -1)
  nom:SetText(p.titre)
  local description = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  description:SetPoint("TOPLEFT", nom, "BOTTOMLEFT", 0, -3)
  description:SetWidth(PAGE - 190)
  description:SetJustifyH("LEFT")
  if description.SetMaxLines then description:SetMaxLines(2) end
  local lireNotes = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  if lireNotes then
    local okN, notes = pcall(lireNotes, NOM_ADDON, "Notes")
    if okN and type(notes) == "string" then description:SetText(notes) end
  end

  local aActif = false
  for _, opt in ipairs(p.options) do if opt.cle == "actif" then aActif = true end end
  local interrupteurGeneral, etatGeneral
  if aActif then
    interrupteurGeneral = creerInterrupteur(page, function(v) r.changer("actif", v) end)
    interrupteurGeneral:SetPoint("TOPRIGHT", -30, -10)
    etatGeneral = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    etatGeneral:SetPoint("RIGHT", interrupteurGeneral, "LEFT", -8, 0)
  end

  -- ------------------------------------------------------- onglets
  -- Un onglet par section ({ titre = … }) ; les options d'avant la première
  -- section vont dans « Général » ; contenu() a son propre onglet.
  local onglets = {}
  local courant
  for _, opt in ipairs(p.options) do
    if opt.titre then
      courant = { titre = opt.titre, options = {} }
      onglets[#onglets + 1] = courant
    else
      if not courant then
        courant = { titre = "Général", options = {} }
        onglets[#onglets + 1] = courant
      end
      -- L'interrupteur général est déjà dans l'en-tête.
      if opt.cle ~= "actif" then courant.options[#courant.options + 1] = opt end
    end
  end
  -- Une section qui n'avait que « actif » : on ne garde pas un onglet vide.
  for i = #onglets, 1, -1 do
    if #onglets[i].options == 0 then table.remove(onglets, i) end
  end
  if p.contenu then onglets[#onglets + 1] = { titre = p.ongletContenu or "Détails", contenu = true, options = {} } end
  if #onglets == 0 then onglets[1] = { titre = "Général", options = {} } end

  local x, ligne = 4, 0
  for _, o in ipairs(onglets) do
    local b = CreateFrame("Button", nil, page)
    b.texte = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.texte:SetPoint("CENTER")
    b.texte:SetText(o.titre)
    local largeur = nombre(b.texte:GetStringWidth(), #o.titre * 7) + 22
    if x + largeur > PAGE then x, ligne = 4, ligne + 1 end
    b:SetSize(largeur, 24)
    b:SetPoint("TOPLEFT", x, -50 - ligne * 26)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b.trait = b:CreateTexture(nil, "ARTWORK")
    b.trait:SetColorTexture(1, 0.82, 0, 1)
    b.trait:SetPoint("BOTTOMLEFT", 4, 0)
    b.trait:SetPoint("BOTTOMRIGHT", -4, 0)
    b.trait:SetHeight(2)
    o.bouton = b
    x = x + largeur + 4
  end
  local hautOnglets = 50 + (ligne + 1) * 26 + 6

  -- ------------------------------------------------------- boutons d'action, en bas
  local actions = {}
  if p.ouvrirHub then
    actions[1] = { texte = p.texteHub or "Ouvrir le panneau", aide = "Aussi : Maj+clic sur son nom dans la liste des addons.",
      action = function() hub.fenetre:Hide(); p.ouvrirHub() end }
  end
  for _, b in ipairs(p.boutons or {}) do actions[#actions + 1] = b end
  local places, bx, rangee = {}, 4, 0
  for _, a in ipairs(actions) do
    local largeur = a.largeur or 150
    if bx + largeur > PAGE then bx, rangee = 4, rangee + 1 end
    places[#places + 1] = { a = a, x = bx, rangee = rangee, largeur = largeur }
    bx = bx + largeur + 6
  end
  local hautActions = #actions > 0 and ((rangee + 1) * 26 + 8) or 0
  for _, pl in ipairs(places) do
    local b = creerBouton(page, pl.a.texte, pl.a.aide, pl.a.action, pl.largeur)
    b:SetPoint("BOTTOMLEFT", pl.x, 4 + (rangee - pl.rangee) * 26)
  end

  -- ------------------------------------------------------- le contenu qui défile
  local okD, defile = pcall(CreateFrame, "ScrollFrame", NOM_ADDON .. "ReglagesDefile", page, "UIPanelScrollFrameTemplate")
  if not okD or not defile then defile = CreateFrame("ScrollFrame", nil, page) end
  defile:SetPoint("TOPLEFT", 0, -hautOnglets)
  defile:SetPoint("BOTTOMRIGHT", -26, hautActions + 2)
  defile:EnableMouseWheel(true)
  defile:SetScript("OnMouseWheel", function(self, sens)
    local maxi = nombre(self:GetVerticalScrollRange(), 0)
    self:SetVerticalScroll(math.max(0, math.min(maxi, nombre(self:GetVerticalScroll(), 0) - sens * 40)))
  end)

  local controles = {}
  local majContenu

  -- Une option = une ligne : libellé et aide à gauche, interrupteur ou curseur à droite.
  local function ligneOption(parent, opt, y)
    local rangeeOpt = CreateFrame("Frame", nil, parent)
    rangeeOpt:SetPoint("TOPLEFT", 0, y)
    rangeeOpt:SetWidth(PAGE)
    local libelle = rangeeOpt:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    libelle:SetPoint("TOPLEFT", 8, -7)
    libelle:SetJustifyH("LEFT")
    libelle:SetText(opt.libelle)
    local aide = rangeeOpt:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    aide:SetPoint("TOPLEFT", libelle, "BOTTOMLEFT", 0, -2)
    aide:SetJustifyH("LEFT")
    aide:SetText(opt.aide or "")
    local ctl = { opt = opt, libelle = libelle, aide = aide, rangee = rangeeOpt }
    if opt.type == "nombre" then
      libelle:SetWidth(PAGE - 270)
      aide:SetWidth(PAGE - 270)
      local s = creerCurseur(rangeeOpt, opt.min or 0, opt.max or 10, opt.pas or 1)
      s:SetPoint("TOPRIGHT", -62, -8)
      local valeur = rangeeOpt:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      valeur:SetPoint("LEFT", s, "RIGHT", 8, 0)
      local enCours = false
      local function texte(v) return opt.format and opt.format(v) or tostring(v) end
      s:SetScript("OnValueChanged", function(_, v)
        local mini, pas = opt.min or 0, opt.pas or 1
        v = mini + math.floor((nombre(v, mini) - mini) / pas + 0.5) * pas
        valeur:SetText(texte(v))
        if not enCours and db and db[opt.cle] ~= v then r.changer(opt.cle, v) end
      end)
      ctl.curseur = s
      ctl.poser = function(v)
        enCours = true
        s:SetValue(v or opt.min or 0)
        enCours = false
        valeur:SetText(texte(v or opt.min or 0))
      end
    else
      libelle:SetWidth(PAGE - 80)
      aide:SetWidth(PAGE - 80)
      ctl.interrupteur = creerInterrupteur(rangeeOpt, function(v) r.changer(opt.cle, v) end)
      ctl.interrupteur:SetPoint("TOPRIGHT", -10, -8)
    end
    local h = math.max(36, hauteurTexte(libelle, 12) + (opt.aide and hauteurTexte(aide, 10) + 2 or 0) + 16)
    rangeeOpt:SetHeight(h)
    local filet = rangeeOpt:CreateTexture(nil, "BACKGROUND")
    filet:SetColorTexture(1, 1, 1, 0.07)
    filet:SetPoint("BOTTOMLEFT", 4, 0)
    filet:SetPoint("BOTTOMRIGHT", -4, 0)
    filet:SetHeight(1)
    controles[#controles + 1] = ctl
    parent.rangees = parent.rangees or {}
    parent.rangees[#parent.rangees + 1] = ctl
    return y - h
  end

  local recherche = {}
  for i, o in ipairs(onglets) do
    local f = CreateFrame("Frame", nil, defile)
    f:SetSize(PAGE, 10)
    f:Hide()
    o.cadre = f
    local y = -2
    if o.contenu then
      y, majContenu = p.contenu(f, -4, r)
      y = nombre(y, -200)
    else
      for _, opt in ipairs(o.options) do
        y = ligneOption(f, opt, y)
        recherche[#recherche + 1] = { libelle = opt.libelle, aide = opt.aide, section = o.titre, onglet = i }
      end
    end
    if i == 1 and p.astuce then
      local astuce = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
      o.astuce = astuce
      astuce:SetPoint("TOPLEFT", 8, y - 10)
      astuce:SetWidth(PAGE - 20)
      astuce:SetJustifyH("LEFT")
      astuce:SetText(p.astuce)
      y = y - 16 - hauteurTexte(astuce, 24)
    end
    o.hauteur = -y + 8
    f:SetHeight(o.hauteur)
  end

  -- Remet chaque ligne à sa vraie hauteur, une fois les textes mesurables.
  local function disposer(o)
    if o.contenu or not o.cadre.rangees then return end
    local y = -2
    for _, ctl in ipairs(o.cadre.rangees) do
      local h = math.max(36, hauteurTexte(ctl.libelle, 12) + (ctl.opt.aide and hauteurTexte(ctl.aide, 10) + 2 or 0) + 16)
      ctl.rangee:ClearAllPoints()
      ctl.rangee:SetPoint("TOPLEFT", 0, y)
      ctl.rangee:SetHeight(h)
      y = y - h
    end
    if o.astuce then
      o.astuce:ClearAllPoints()
      o.astuce:SetPoint("TOPLEFT", 8, y - 10)
      y = y - 16 - hauteurTexte(o.astuce, 24)
    end
    o.hauteur = -y + 8
    o.cadre:SetHeight(o.hauteur)
  end

  local ongletOuvert = 1
  local function choisirOnglet(i)
    if not onglets[i] then i = 1 end
    ongletOuvert = i
    disposer(onglets[i])
    for j, o in ipairs(onglets) do
      o.cadre:SetShown(j == i)
      o.bouton.trait:SetShown(j == i)
      if j == i then o.bouton.texte:SetTextColor(1, 0.82, 0) else o.bouton.texte:SetTextColor(0.6, 0.57, 0.5) end
    end
    defile:SetScrollChild(onglets[i].cadre)
    defile:SetVerticalScroll(0)
    local barre = defile.ScrollBar or _G[NOM_ADDON .. "ReglagesDefileScrollBar"]
    local visible = nombre(defile:GetHeight(), 0)
    if visible <= 0 then visible = HAUTEUR - 52 - hautOnglets - hautActions end
    if barre then barre:SetShown(onglets[i].hauteur > visible) end
  end
  for i, o in ipairs(onglets) do
    o.bouton:SetScript("OnClick", function() choisirOnglet(i) end)
  end

  -- Une option est grisée quand ce dont elle dépend n'est pas réglé comme il faut.
  local function disponible(opt)
    if aActif and opt.cle ~= "minimap" and not opt.toujours and not db.actif then return false end
    local d = opt.dependDe
    if not d then return true end
    if d:sub(1, 1) == "!" then return not db[d:sub(2)] end
    return db[d] and true or false
  end

  local function majFenetre()
    if not db then return end
    if interrupteurGeneral then
      interrupteurGeneral.poser(db.actif)
      etatGeneral:SetText(db.actif and "|cff3ddc3dActivé|r" or "|cffff4a3aCoupé|r")
    end
    for _, ctl in ipairs(controles) do
      local dispo = disponible(ctl.opt)
      if ctl.interrupteur then
        ctl.interrupteur.poser(db[ctl.opt.cle])
        ctl.interrupteur.permettre(dispo)
      else
        ctl.poser(db[ctl.opt.cle])
        if dispo then ctl.curseur:Enable() else ctl.curseur:Disable() end
        ctl.curseur:SetAlpha(dispo and 1 or 0.4)
      end
      if dispo then ctl.libelle:SetTextColor(1, 1, 1) else ctl.libelle:SetTextColor(0.5, 0.5, 0.5) end
    end
    if majContenu then majContenu(db) end
  end
  r.majFenetre = function() if page:IsShown() then majFenetre() end end
  page:SetScript("OnShow", function()
    choisirOnglet(ongletOuvert)
    majFenetre()
  end)

  -- Ouvre ou ferme (icône, commande) ; montrer() ouvre toujours.
  function r.montrer() hub.montrer(r.hub) end
  function r.ouvrir()
    if hub.fenetre:IsShown() and hub.courant == r.hub and page:IsShown() then hub.fenetre:Hide() else r.montrer() end
  end
  -- Nom global pour le .toc (## AddonCompartmentFunc) et les raccourcis.
  _G[NOM_ADDON .. "_OuvrirReglages"] = r.ouvrir

  -- Page dans Échap > Options > AddOns, avec un bouton qui ouvre la fenêtre.
  local pageJeu = CreateFrame("Frame")
  pageJeu.name = p.titre
  local pageTexte = pageJeu:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  pageTexte:SetPoint("TOPLEFT", 16, -16)
  pageTexte:SetText("Tous les réglages de " .. p.titre .. " sont dans la fenêtre des addons de Valentin :")
  local pageBouton = CreateFrame("Button", nil, pageJeu, "UIPanelButtonTemplate")
  pageBouton:SetSize(200, 26)
  pageBouton:SetPoint("TOPLEFT", pageTexte, "BOTTOMLEFT", 0, -12)
  pageBouton:SetText("Ouvrir les réglages")
  pageBouton:SetScript("OnClick", function() r.montrer() end)
  if Settings and Settings.RegisterCanvasLayoutCategory then
    Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(pageJeu, pageJeu.name))
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(pageJeu)
  end

  -- ------------------------------------------------------- icône minimap à part
  local mini = CreateFrame("Button", NOM_ADDON .. "Minimap", Minimap)
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
  iconeMini:SetTexture(p.icone)
  r.iconeMini = iconeMini
  local cadre = mini:CreateTexture(nil, "OVERLAY")
  cadre:SetSize(53, 53)
  cadre:SetPoint("TOPLEFT")
  cadre:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

  -- Place l'icône sur le bord de la minimap, à l'angle donné (0° = à droite).
  local function placerMini()
    local rayon = nombre(Minimap:GetWidth(), 140) / 2 + 5
    local a = math.rad(db.angleMinimap or 225)
    mini:ClearAllPoints()
    mini:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * rayon, math.sin(a) * rayon)
  end
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
    if souris == "RightButton" then r.basculer()
    elseif IsShiftKeyDown() and p.ouvrirHub then p.ouvrirHub()
    else r.ouvrir() end
  end)
  mini:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(p.titre)
    GameTooltip:AddLine(db.actif and "|cff00ff00Activé|r" or "|cffff4040Coupé|r")
    GameTooltip:AddLine("Clic gauche : réglages\nClic droit : activer ou couper\nGlisser : déplacer", 1, 1, 1)
    if p.ouvrirHub then GameTooltip:AddLine("Maj+clic : " .. (p.texteHub or "le panneau"), 1, 1, 1) end
    GameTooltip:Show()
  end)
  mini:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- ------------------------------------------------------- changements
  function r.appliquer()
    iconeMini:SetDesaturated(not db.actif)
    mini:SetShown(db.minimap == true)
    if page:IsShown() then majFenetre() end
    if r.hub then r.hub.maj() end
    if p.surChangement then p.surChangement(db) end
  end

  function r.changer(cle, valeur)
    db[cle] = valeur
    r.appliquer()
  end

  function r.basculer()
    r.changer("actif", not db.actif)
    dire(db.actif and "|cff00ff00activé|r" or "|cffff4040coupé|r")
  end

  -- Bascule une option par son nom (pour la commande slash). Renvoie vrai si trouvée.
  function r.basculerOption(nomOption)
    for _, opt in ipairs(p.options) do
      if opt.cle and opt.cle:lower() == nomOption and opt.type ~= "nombre" then
        r.changer(opt.cle, not db[opt.cle])
        dire(opt.libelle .. " : " .. (db[opt.cle] and "|cff00ff00oui|r" or "|cffff4040non|r"))
        return true
      end
    end
  end

  -- ------------------------------------------------------- chargement
  local ecouteur = CreateFrame("Frame")
  ecouteur:RegisterEvent("ADDON_LOADED")
  ecouteur:SetScript("OnEvent", function(self, _, nomCharge)
    if nomCharge ~= NOM_ADDON then return end
    self:UnregisterEvent("ADDON_LOADED")
    local sauve = _G[p.nomDB] or {}
    _G[p.nomDB] = sauve
    for cle, valeur in pairs(p.defauts) do
      if sauve[cle] == nil then sauve[cle] = type(valeur) == "table" and {} or valeur end
    end
    db = sauve
    r.db = db
    -- Une seule fois : l'icône à part laisse la place à l'icône commune.
    if not db.iconeCommune then db.minimap = false; db.iconeCommune = true end
    r.hub = ns.inscrireAuHub({
      titre = p.titre, icone = p.icone, db = db, ouvrir = r.montrer, basculer = r.basculer,
      panneau = p.ouvrirHub, textePanneau = p.texteHub, page = page, recherche = recherche, allerOnglet = choisirOnglet,
      actif = function() return db.actif and true or false end,
    })
    placerMini()
    if p.auChargement then p.auChargement(db) end
    r.appliquer()
  end)

  return r
end
