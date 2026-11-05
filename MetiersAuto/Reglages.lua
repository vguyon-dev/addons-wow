-- ============================================================================
-- Reglages.lua : fenêtre de réglages à cases à cocher + icône de minimap.
--
-- Fichier COMMUN : la même copie se trouve dans chaque addon du dépôt
-- (QuetesAuto, MarchandAuto…). Si tu le modifies, recopie-le dans les autres.
--
-- Utilisation, dans le fichier principal de l'addon :
--   local reglages = ns.creerReglages({
--     titre = "Mon addon",                      -- nom affiché
--     icone = "Interface\\Icons\\…",            -- icône de minimap
--     nomDB = "MonAddonDB",                     -- SavedVariables du .toc
--     defauts = { actif = true, … },            -- valeurs de départ
--     options = { { titre = "Section" }, { cle = "actif", libelle = "…", aide = "…" }, … },
--     astuce = "texte en bas de la fenêtre",    -- facultatif
--     contenu = function(fenetre, y) … return y, maj end, -- facultatif : zone en plus
--     auChargement = function(db) … end,        -- quand les réglages sont lus
--     surChangement = function(db) … end,       -- après chaque changement
--   })
-- Tout s'applique tout de suite, sans /reload.
-- ============================================================================

local NOM_ADDON, ns = ...

function ns.creerReglages(p)
  local r = {}
  local db

  local function dire(texte) print("|cffffd200" .. p.titre .. "|r : " .. texte) end
  r.dire = dire

  -- ------------------------------------------------------------- fenêtre
  local fenetre = CreateFrame("Frame", NOM_ADDON .. "Reglages", UIParent, "BasicFrameTemplateWithInset")
  fenetre:SetPoint("CENTER")
  fenetre:SetFrameStrata("DIALOG")
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

  local cases = {}
  local y = -32
  for _, opt in ipairs(p.options) do
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
      aide:SetWidth(370)
      aide:SetJustifyH("LEFT")
      aide:SetText(opt.aide)
      c:SetScript("OnClick", function(self) r.changer(opt.cle, self:GetChecked() and true or false) end)
      cases[opt.cle] = c
      y = y - 34
    end
  end

  local majContenu
  if p.contenu then y, majContenu = p.contenu(fenetre, y, r) end

  if p.astuce then
    local astuce = fenetre:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    astuce:SetPoint("TOPLEFT", 16, y - 10)
    astuce:SetWidth(400)
    astuce:SetJustifyH("LEFT")
    astuce:SetText(p.astuce)
    y = y - 40
  end
  fenetre:SetSize(440, -y + 12)

  local function majFenetre()
    for cle, c in pairs(cases) do c:SetChecked(db[cle] and true or false) end
    if majContenu then majContenu(db) end
  end
  fenetre:SetScript("OnShow", majFenetre)

  function r.ouvrir()
    if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
    fenetre:SetShown(not fenetre:IsShown())
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
  pageBouton:SetScript("OnClick", r.ouvrir)
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
    if souris == "RightButton" then r.basculer() else r.ouvrir() end
  end)
  mini:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(p.titre)
    GameTooltip:AddLine(db.actif and "|cff00ff00Activé|r" or "|cffff4040Coupé|r")
    GameTooltip:AddLine("Clic gauche : réglages\nClic droit : activer ou couper\nGlisser : déplacer", 1, 1, 1)
    GameTooltip:Show()
  end)
  mini:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- ------------------------------------------------------- changements
  function r.appliquer()
    iconeMini:SetDesaturated(not db.actif)
    mini:SetShown(db.minimap ~= false)
    if fenetre:IsShown() then majFenetre() end
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
  function r.basculerOption(nom)
    for _, opt in ipairs(p.options) do
      if opt.cle and opt.cle:lower() == nom then
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
    placerMini()
    if p.auChargement then p.auChargement(db) end
    r.appliquer()
  end)

  return r
end
