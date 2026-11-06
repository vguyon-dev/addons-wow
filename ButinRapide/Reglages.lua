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
--
-- Icône commune : tous les addons de Valentin passent par UNE seule icône
-- autour de la minimap (ns.inscrireAuHub). Le premier addon chargé la crée, les
-- autres s'y ajoutent. Chaque addon peut en plus garder son icône à part.
-- ============================================================================

local NOM_ADDON, ns = ...

-- ============================================================ icône commune
-- Une entrée : { titre, icone, db, ouvrir = fonction, basculer = fonction ou nil,
--               actif = fonction qui renvoie vrai/faux, ou nil }.
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

    -- Le menu : une ligne par addon. Clic gauche = réglages, clic droit = activer ou couper.
    local menu = CreateFrame("Frame", "ValentinAddonsMenu", UIParent, "BasicFrameTemplateWithInset")
    menu:SetFrameStrata("DIALOG")
    menu:SetClampedToScreen(true)
    menu:Hide()
    tinsert(UISpecialFrames, menu:GetName()) -- Échap le ferme
    local titreMenu = menu.TitleText or menu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if not menu.TitleText then titreMenu:SetPoint("TOP", 0, -5) end
    titreMenu:SetText("Addons de Valentin")
    local aideMenu = menu:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    aideMenu:SetText("Clic gauche : réglages     Clic droit : activer ou couper")
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
          else
            menu:Hide()
            x.ouvrir()
          end
        end)
        l:Show()
        y = y - 26
      end
      for i = #hub.entrees + 1, #lignes do lignes[i]:Hide() end
      aideMenu:ClearAllPoints()
      aideMenu:SetPoint("TOPLEFT", 16, y - 6)
      menu:SetSize(260, -y + 30)
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
    -- Une seule fois : l'icône à part laisse la place à l'icône commune.
    if not db.iconeCommune then db.minimap = false; db.iconeCommune = true end
    r.hub = ns.inscrireAuHub({
      titre = p.titre, icone = p.icone, db = db, ouvrir = r.ouvrir, basculer = r.basculer,
      actif = function() return db.actif and true or false end,
    })
    placerMini()
    if p.auChargement then p.auChargement(db) end
    r.appliquer()
  end)

  return r
end
