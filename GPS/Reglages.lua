-- ============================================================================
-- Reglages.lua : fenêtre de réglages complète + icône commune de la minimap.
--
-- Fichier COMMUN : la même copie se trouve dans chaque addon du dépôt
-- (QuetesAuto, MarchandAuto…). Si tu le modifies, recopie-le dans les autres
-- (un test vérifie qu'ils sont identiques).
--
-- Utilisation, dans le fichier principal de l'addon :
--   local reglages = ns.creerReglages({
--     titre = "Mon addon",                      -- nom affiché
--     icone = "Interface\\Icons\\…",            -- icône de minimap
--     nomDB = "MonAddonDB",                     -- SavedVariables du .toc
--     defauts = { actif = true, … },            -- valeurs de départ
--     options = {
--       { titre = "Section" },
--       { cle = "x", libelle = "…", aide = "…" },              -- case à cocher
--       { cle = "x", libelle = "…", dependDe = "y" },          -- grisée si y est décochée
--       { cle = "x", libelle = "…", dependDe = "!y" },         -- grisée si y est cochée
--       { cle = "n", type = "nombre", libelle = "…", min = 0, max = 20, pas = 1 }, -- curseur
--     },
--     boutons = { { texte = "…", aide = "…", action = fonction }, … }, -- en haut de la fenêtre
--     ouvrirHub = fonction, texteHub = "…",     -- le panneau de l'addon : un bouton en haut
--                                               -- de la fenêtre et Maj+clic dans le menu commun
--     contenu = function(f, y, r) … return y, maj end, -- facultatif : zone en plus
--     astuce = "texte en bas de la fenêtre",    -- facultatif
--     auChargement = function(db) … end,        -- quand les réglages sont lus
--     surChangement = function(db) … end,       -- après chaque changement
--   })
-- Quand l'addon a une case « actif », les autres cases sont grisées tant qu'il
-- est coupé (sauf « minimap » et les options marquées toujours = true).
-- Tout s'applique tout de suite, sans /reload. La fenêtre défile quand elle est
-- plus haute que l'écran.
--
-- ns.creerListe(parent, y, spec) : une liste d'objets éditable (retrait d'une
-- ligne, dépôt d'un objet du sac), à utiliser dans contenu().
--
-- Icône commune : tous les addons de Valentin passent par UNE seule icône
-- autour de la minimap (ns.inscrireAuHub). Le premier addon chargé la crée, les
-- autres s'y ajoutent. Clic gauche sur une ligne = ses réglages complets.
-- ============================================================================

local NOM_ADDON, ns = ...

local function nombre(v, defaut) return type(v) == "number" and v or defaut end

-- ============================================================ icône commune
-- Une entrée : { titre, icone, db, ouvrir = fonction, basculer = fonction ou nil,
--               actif = fonction qui renvoie vrai/faux, ou nil, panneau = fonction ou nil }.
-- La position de l'icône est gardée dans le db de chaque addon inscrit (angleHub),
-- comme ça elle survit même si on n'installe qu'une partie des addons.
function ns.inscrireAuHub(e)
  local hub = _G.ValentinAddons
  if not hub then
    hub = { entrees = {} }
    _G.ValentinAddons = hub

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
      local rayon = Minimap:GetWidth() / 2 + 5
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

    -- Le menu : une ligne par addon. Clic gauche = réglages, clic droit = activer ou
    -- couper, Maj+clic = le panneau de l'addon quand il en a un.
    local menu = CreateFrame("Frame", "ValentinAddonsMenu", UIParent, "BasicFrameTemplateWithInset")
    menu:SetFrameStrata("DIALOG")
    menu:SetClampedToScreen(true)
    menu:Hide()
    tinsert(UISpecialFrames, menu:GetName()) -- Échap le ferme
    local titreMenu = menu.TitleText or menu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if not menu.TitleText then titreMenu:SetPoint("TOP", 0, -5) end
    titreMenu:SetText("Addons de Valentin")
    local aideMenu = menu:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    aideMenu:SetJustifyH("LEFT")
    aideMenu:SetText("Clic gauche : tous les réglages\nClic droit : activer ou couper\nMaj+clic : le panneau de l'addon")
    local lignes = {}

    function hub.majMenu()
      table.sort(hub.entrees, function(a, b) return a.titre < b.titre end)
      local y = -30
      for i, x in ipairs(hub.entrees) do
        local l = lignes[i]
        if not l then
          l = CreateFrame("Button", nil, menu)
          l:SetSize(236, 24)
          l:RegisterForClicks("LeftButtonUp", "RightButtonUp")
          l:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
          l.icone = l:CreateTexture(nil, "ARTWORK")
          l.icone:SetSize(20, 20)
          l.icone:SetPoint("LEFT", 4, 0)
          l.nom = l:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
          l.nom:SetPoint("LEFT", l.icone, "RIGHT", 6, 0)
          l.etat = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
          l.etat:SetPoint("RIGHT", -6, 0)
          lignes[i] = l
        end
        l:SetPoint("TOPLEFT", 12, y)
        l.icone:SetTexture(x.icone)
        l.nom:SetText(x.titre)
        local actif = x.actif and x.actif()
        if actif == nil then l.etat:SetText("")
        elseif actif then l.etat:SetText("|cff00ff00activé|r")
        else l.etat:SetText("|cffff4040coupé|r") end
        l.icone:SetDesaturated(actif == false)
        l:SetScript("OnClick", function(_, souris)
          if souris == "RightButton" and x.basculer then
            x.basculer()
            hub.majMenu()
          elseif IsShiftKeyDown() and x.panneau then
            menu:Hide()
            x.panneau()
          else
            menu:Hide()
            x.ouvrir()
          end
        end)
        l:SetScript("OnEnter", function(self)
          if not x.panneau then return end
          GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
          GameTooltip:AddLine(x.titre)
          GameTooltip:AddLine("Maj+clic : " .. (x.textePanneau or "le panneau"), 1, 1, 1)
          GameTooltip:Show()
        end)
        l:SetScript("OnLeave", function() GameTooltip:Hide() end)
        l:Show()
        y = y - 26
      end
      for i = #hub.entrees + 1, #lignes do lignes[i]:Hide() end
      aideMenu:ClearAllPoints()
      aideMenu:SetPoint("TOPLEFT", 16, y - 6)
      menu:SetSize(260, -y + 56)
    end

    bouton:SetScript("OnClick", function(self)
      if menu:IsShown() then menu:Hide() return end
      hub.majMenu()
      menu:ClearAllPoints()
      menu:SetPoint("TOPRIGHT", self, "BOTTOMLEFT", 0, 0)
      menu:Show()
    end)
    bouton:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:AddLine("Addons de Valentin")
      for _, x in ipairs(hub.entrees) do
        local actif = x.actif and x.actif()
        local etat = actif == nil and "" or (actif and "|cff00ff00activé|r" or "|cffff4040coupé|r")
        GameTooltip:AddDoubleLine(x.titre, etat, 1, 1, 1)
      end
      GameTooltip:AddLine("Clic : la liste des addons\nGlisser : déplacer", 0.7, 0.7, 0.7)
      GameTooltip:Show()
    end)
    bouton:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  table.insert(hub.entrees, e)
  hub.placer()
  -- Un réglage change ailleurs (commande, raccourci) : le menu ouvert se remet à jour.
  e.maj = function() if ValentinAddonsMenu and ValentinAddonsMenu:IsShown() then hub.majMenu() end end
  return e
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
      GameTooltip:AddLine(texte)
      GameTooltip:AddLine(aide, 1, 1, 1, true)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  return b
end
ns.creerBouton = creerBouton

-- Un curseur fait main (les modèles du jeu changent d'une version à l'autre).
local function creerCurseur(parent, mini, maxi, pas)
  local s = CreateFrame("Slider", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  s:SetOrientation("HORIZONTAL")
  s:SetSize(200, 16)
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
--   lignes = function() return { { texte = "…", lien = lien ou nil, retirer = fonction }, … } end,
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
      -- La liste ne bouge plus (courte, ou au bout) : c'est la fenêtre qui défile.
      local defile = parent.GetParent and parent:GetParent()
      local roulette = defile and defile.GetScript and defile:GetScript("OnMouseWheel")
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
        l:Show(); l.croix:Show()
      else
        l:Hide(); l.croix:Hide()
      end
    end
  end
  return y, maj
end

-- ============================================================ fenêtre de réglages

function ns.creerReglages(p)
  local r = {}
  local db

  local function dire(texte) print("|cffffd200" .. p.titre .. "|r : " .. texte) end
  r.dire = dire

  local LARGEUR = 460
  local fenetre = CreateFrame("Frame", NOM_ADDON .. "Reglages", UIParent, "BasicFrameTemplateWithInset")
  fenetre:SetPoint("CENTER")
  fenetre:SetFrameStrata("DIALOG")
  fenetre:SetToplevel(true)
  fenetre:SetMovable(true)
  fenetre:SetClampedToScreen(true)
  fenetre:EnableMouse(true)
  fenetre:RegisterForDrag("LeftButton")
  fenetre:SetScript("OnDragStart", fenetre.StartMoving)
  fenetre:SetScript("OnDragStop", fenetre.StopMovingOrSizing)
  fenetre:Hide()
  tinsert(UISpecialFrames, fenetre:GetName()) -- Échap la ferme
  local titre = fenetre.TitleText or fenetre:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  if not fenetre.TitleText then titre:SetPoint("TOP", 0, -5) end
  titre:SetText(p.titre .. " : réglages")

  -- Le contenu défile quand il dépasse l'écran.
  local ok, defile = pcall(CreateFrame, "ScrollFrame", NOM_ADDON .. "ReglagesDefile", fenetre, "UIPanelScrollFrameTemplate")
  if not ok or not defile then defile = CreateFrame("ScrollFrame", nil, fenetre) end
  defile:SetPoint("TOPLEFT", 6, -28)
  defile:SetPoint("BOTTOMRIGHT", -28, 8)
  local f = CreateFrame("Frame", nil, defile)
  f:SetSize(LARGEUR - 40, 10)
  defile:SetScrollChild(f)
  defile:EnableMouseWheel(true)
  defile:SetScript("OnMouseWheel", function(self, sens)
    local maxi = nombre(self:GetVerticalScrollRange(), 0)
    self:SetVerticalScroll(math.max(0, math.min(maxi, self:GetVerticalScroll() - sens * 40)))
  end)

  local y = -4

  -- Les boutons d'action, en haut : le panneau de l'addon d'abord.
  local actions = {}
  if p.ouvrirHub then
    actions[1] = { texte = p.texteHub or "Ouvrir le panneau", aide = "Aussi : Maj+clic sur sa ligne dans le menu des addons.",
      action = function() fenetre:Hide(); p.ouvrirHub() end }
  end
  for _, b in ipairs(p.boutons or {}) do actions[#actions + 1] = b end
  if #actions > 0 then
    local x = 16
    for _, a in ipairs(actions) do
      local largeur = a.largeur or 136
      if x + largeur > LARGEUR - 50 then x = 16; y = y - 26 end
      local b = creerBouton(f, a.texte, a.aide, a.action, largeur)
      b:SetPoint("TOPLEFT", x, y)
      x = x + largeur + 6
    end
    y = y - 32
  end

  -- Les options : cases et curseurs.
  local controles = {}
  local aActif = false
  for _, opt in ipairs(p.options) do if opt.cle == "actif" then aActif = true end end

  for _, opt in ipairs(p.options) do
    if opt.titre then
      local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
      t:SetPoint("TOPLEFT", 16, y - 6)
      t:SetText(opt.titre)
      y = y - 30
    elseif opt.type == "nombre" then
      local libelle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      libelle:SetPoint("TOPLEFT", 20, y - 2)
      libelle:SetText(opt.libelle)
      local s = creerCurseur(f, opt.min or 0, opt.max or 10, opt.pas or 1)
      s:SetPoint("TOPLEFT", 24, y - 22)
      local valeur = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      valeur:SetPoint("LEFT", s, "RIGHT", 12, 0)
      local aide = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
      aide:SetPoint("TOPLEFT", 20, y - 42)
      aide:SetWidth(380)
      aide:SetJustifyH("LEFT")
      aide:SetText(opt.aide or "")
      local enCours = false
      s:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v / (opt.pas or 1) + 0.5) * (opt.pas or 1)
        valeur:SetText(opt.format and opt.format(v) or tostring(v))
        if not enCours and db and db[opt.cle] ~= v then r.changer(opt.cle, v) end
      end)
      controles[#controles + 1] = { opt = opt, curseur = s, libelle = libelle, aide = aide,
        poser = function(v) enCours = true; s:SetValue(v or opt.min or 0); enCours = false
          valeur:SetText(opt.format and opt.format(v or 0) or tostring(v or 0)) end }
      y = y - 46 - (opt.aide and hauteurTexte(aide, 10) or 0) - 6
    else
      local c = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
      c:SetSize(26, 26)
      c:SetPoint("TOPLEFT", 16, y)
      local libelle = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      libelle:SetPoint("TOPLEFT", c, "TOPRIGHT", 4, -2)
      libelle:SetWidth(360)
      libelle:SetJustifyH("LEFT")
      libelle:SetText(opt.libelle)
      local aide = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
      aide:SetPoint("TOPLEFT", libelle, "BOTTOMLEFT", 0, -2)
      aide:SetWidth(360)
      aide:SetJustifyH("LEFT")
      aide:SetText(opt.aide or "")
      c:SetScript("OnClick", function(self) r.changer(opt.cle, self:GetChecked() and true or false) end)
      controles[#controles + 1] = { opt = opt, case = c, libelle = libelle, aide = aide }
      -- La hauteur suit le texte : une aide sur deux ou trois lignes ne chevauche plus la suivante.
      y = y - math.max(30, hauteurTexte(libelle, 12) + (opt.aide and hauteurTexte(aide, 10) or 0) + 10)
    end
  end

  local majContenu
  if p.contenu then y, majContenu = p.contenu(f, y, r) end

  if p.astuce then
    local astuce = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    astuce:SetPoint("TOPLEFT", 16, y - 10)
    astuce:SetWidth(390)
    astuce:SetJustifyH("LEFT")
    astuce:SetText(p.astuce)
    y = y - 16 - hauteurTexte(astuce, 24)
  end
  local hauteurContenu = -y + 8
  f:SetHeight(hauteurContenu)

  -- Une option est grisée quand ce dont elle dépend n'est pas réglé comme il faut.
  local function disponible(opt)
    if aActif and opt.cle ~= "actif" and opt.cle ~= "minimap" and not opt.toujours and not db.actif then
      return false
    end
    local d = opt.dependDe
    if not d then return true end
    if d:sub(1, 1) == "!" then return not db[d:sub(2)] end
    return db[d] and true or false
  end

  local function majFenetre()
    for _, ctl in ipairs(controles) do
      local dispo = disponible(ctl.opt)
      if ctl.case then
        ctl.case:SetChecked(db[ctl.opt.cle] and true or false)
        if dispo then ctl.case:Enable() else ctl.case:Disable() end
      else
        ctl.poser(db[ctl.opt.cle])
        if dispo then ctl.curseur:Enable() else ctl.curseur:Disable() end
        ctl.curseur:SetAlpha(dispo and 1 or 0.5)
      end
      if dispo then ctl.libelle:SetTextColor(1, 1, 1) else ctl.libelle:SetTextColor(0.5, 0.5, 0.5) end
    end
    if majContenu then majContenu(db) end
  end
  r.majFenetre = function() if fenetre:IsShown() then majFenetre() end end

  fenetre:SetScript("OnShow", function()
    -- La fenêtre prend la hauteur de son contenu, sans dépasser 85 % de l'écran.
    local ecran = nombre(UIParent:GetHeight(), 768) / nombre(fenetre:GetScale(), 1)
    local h = math.min(hauteurContenu + 36, ecran * 0.85)
    local defileUtile = hauteurContenu + 36 > ecran * 0.85
    fenetre:SetSize(LARGEUR, h)
    local barre = defile.ScrollBar or _G[NOM_ADDON .. "ReglagesDefileScrollBar"]
    if barre then barre:SetShown(defileUtile) end
    defile:SetPoint("BOTTOMRIGHT", defileUtile and -28 or -8, 8)
    defile:SetVerticalScroll(0)
    majFenetre()
  end)

  -- Ouvre ou ferme (icône, commande) ; montrer() ouvre toujours (menu commun).
  function r.ouvrir()
    if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
    fenetre:SetShown(not fenetre:IsShown())
  end
  function r.montrer()
    if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
    if fenetre:IsShown() then fenetre:Raise() else fenetre:Show() end
  end
  -- Nom global pour le .toc (## AddonCompartmentFunc) et les raccourcis.
  _G[NOM_ADDON .. "_OuvrirReglages"] = r.ouvrir

  -- Page dans Échap > Options > AddOns, avec un bouton qui ouvre la fenêtre.
  local page = CreateFrame("Frame")
  page.name = p.titre
  local pageTexte = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  pageTexte:SetPoint("TOPLEFT", 16, -16)
  pageTexte:SetText("Tous les réglages de " .. p.titre .. " sont dans sa fenêtre :")
  local pageBouton = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
  pageBouton:SetSize(200, 26)
  pageBouton:SetPoint("TOPLEFT", pageTexte, "BOTTOMLEFT", 0, -12)
  pageBouton:SetText("Ouvrir les réglages")
  pageBouton:SetScript("OnClick", r.montrer)
  if Settings and Settings.RegisterCanvasLayoutCategory then
    Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(page, page.name))
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(page)
  end

  -- ------------------------------------------------------- icône minimap
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
    local rayon = Minimap:GetWidth() / 2 + 5
    local a = math.rad(db.angleMinimap or 225)
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
    if fenetre:IsShown() then majFenetre() end
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

  -- Bascule une case par son nom (pour la commande slash). Renvoie vrai si trouvée.
  function r.basculerOption(nom)
    for _, opt in ipairs(p.options) do
      if opt.cle and opt.cle:lower() == nom and opt.type ~= "nombre" then
        r.changer(opt.cle, not db[opt.cle])
        dire(opt.libelle .. " : " .. (db[opt.cle] and "|cff00ff00oui|r" or "|cffff4040non|r"))
        return true
      end
    end
  end

  -- ------------------------------------------------------- chargement
  local ecouteur = CreateFrame("Frame")
  ecouteur:RegisterEvent("ADDON_LOADED")
  ecouteur:SetScript("OnEvent", function(self, _, nom)
    if nom ~= NOM_ADDON then return end
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
    -- Dans le menu commun, le clic gauche ouvre toujours les réglages complets ;
    -- le panneau de l'addon passe par Maj+clic et par le bouton en haut de la fenêtre.
    r.hub = ns.inscrireAuHub({
      titre = p.titre, icone = p.icone, db = db, ouvrir = r.montrer, basculer = r.basculer,
      panneau = p.ouvrirHub, textePanneau = p.texteHub,
      actif = function() return db.actif and true or false end,
    })
    placerMini()
    if p.auChargement then p.auChargement(db) end
    r.appliquer()
  end)

  return r
end
