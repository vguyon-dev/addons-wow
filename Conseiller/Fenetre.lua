-- ============================================================================
-- Fenetre.lua : la fenêtre de Conseiller (/conseil), six onglets.
-- Les textes viennent de Logique.lua (ns.vueTalents, ns.vueRotation…) : ici, seulement le cadre.
-- ============================================================================

local NOM_ADDON, ns = ...
local D = ns.DONNEES

local LARGEUR, HAUTEUR = 600, 520

local fenetre = CreateFrame("Frame", "ConseillerFenetre", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
fenetre:SetSize(LARGEUR, HAUTEUR)
fenetre:SetPoint("CENTER")
fenetre:SetMovable(true)
fenetre:SetClampedToScreen(true)
fenetre:EnableMouse(true)
fenetre:RegisterForDrag("LeftButton")
fenetre:SetScript("OnDragStart", fenetre.StartMoving)
fenetre:SetScript("OnDragStop", fenetre.StopMovingOrSizing)
fenetre:SetFrameStrata("DIALOG")
fenetre:Hide()
tinsert(UISpecialFrames, "ConseillerFenetre")
ns.habiller(fenetre, { titre = "Conseiller", fermer = true })

-- ---------------------------------------------------------------------------
-- L'en-tête : qui tu es, ta situation
-- ---------------------------------------------------------------------------

local ligne1 = fenetre:CreateFontString(nil, "OVERLAY", "GameFontNormal")
ligne1:SetPoint("TOPLEFT", 14, -36)
local ligne2 = fenetre:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
ligne2:SetPoint("TOPLEFT", ligne1, "BOTTOMLEFT", 0, -3)
ligne2:SetWidth(LARGEUR - 220)
ligne2:SetJustifyH("LEFT")

local boutonSituation = CreateFrame("Button", nil, fenetre, "UIPanelButtonTemplate")
boutonSituation:SetSize(170, 24)
boutonSituation:SetPoint("TOPRIGHT", -14, -36)

-- ---------------------------------------------------------------------------
-- Les onglets
-- ---------------------------------------------------------------------------

local ongletCourant = 1
local boutonsOnglets = {}
local largeurOnglet = (LARGEUR - 28 - 4 * (#ns.ONGLETS - 1)) / #ns.ONGLETS
for i, o in ipairs(ns.ONGLETS) do
  local b = CreateFrame("Button", nil, fenetre, "UIPanelButtonTemplate")
  b:SetSize(largeurOnglet, 26)
  b:SetPoint("TOPLEFT", 14 + (i - 1) * (largeurOnglet + 4), -72)
  b:SetText(o[2])
  b:SetScript("OnClick", function() ns.fenetre.onglet(i) end)
  boutonsOnglets[i] = b
end

-- ---------------------------------------------------------------------------
-- Le contenu : un texte qui défile
-- ---------------------------------------------------------------------------

local defile = CreateFrame("ScrollFrame", nil, fenetre, "UIPanelScrollFrameTemplate")
defile:SetPoint("TOPLEFT", 14, -106)
defile:SetPoint("BOTTOMRIGHT", -34, 50)
local contenu = CreateFrame("Frame", nil, defile)
contenu:SetSize(LARGEUR - 70, 400)
defile:SetScrollChild(contenu)
local texte = contenu:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
texte:SetPoint("TOPLEFT", 0, 0)
texte:SetWidth(LARGEUR - 76)
texte:SetJustifyH("LEFT")
texte:SetJustifyV("TOP")
texte:SetSpacing(2)

-- ---------------------------------------------------------------------------
-- Les boutons du bas (selon l'onglet)
-- ---------------------------------------------------------------------------

local bas1 = CreateFrame("Button", nil, fenetre, "UIPanelButtonTemplate")
bas1:SetSize(200, 26)
bas1:SetPoint("BOTTOMLEFT", 14, 14)
local bas2 = CreateFrame("Button", nil, fenetre, "UIPanelButtonTemplate")
bas2:SetSize(200, 26)
bas2:SetPoint("LEFT", bas1, "RIGHT", 8, 0)
local boutonReglages = CreateFrame("Button", nil, fenetre, "UIPanelButtonTemplate")
boutonReglages:SetSize(110, 26)
boutonReglages:SetPoint("BOTTOMRIGHT", -14, 14)
boutonReglages:SetText("Réglages")
boutonReglages:SetScript("OnClick", function() ns.reglages.montrer() end)

local NOMS_SITUATION_BOUTON = { [false] = "Situation : auto" }

local function maj()
  if not fenetre:IsShown() then return end
  local e = ns.construireEtat()
  ligne1:SetText(string.format("%s niveau %s", e.classeNom, tostring(e.niveau)))
  ligne2:SetText(string.format("Race : %s  ·  Spécialisation : %s  ·  Situation : %s%s",
    tostring(e.raceNom or "?"), tostring(e.speNom or "inconnue"), D.NOMS_SITUATIONS[e.situation] or e.situation,
    ns.situationForcee and " (vue forcée)" or " (détectée)"))
  boutonSituation:SetText(ns.situationForcee and ("Vue : " .. D.NOMS_SITUATIONS[ns.situationForcee]) or NOMS_SITUATION_BOUTON[false])
  for i, b in ipairs(boutonsOnglets) do
    local fs = b.GetFontString and b:GetFontString()
    if fs and fs.SetTextColor then
      if i == ongletCourant then fs:SetTextColor(1, 0.82, 0.30) else fs:SetTextColor(1, 1, 1) end
    end
  end
  local o = ns.ONGLETS[ongletCourant]
  local ok, t = pcall(o[3], e)
  texte:SetText(ok and t or ("Erreur dans l'onglet : " .. tostring(t)))
  local h = texte:GetStringHeight()
  if type(h) == "number" then contenu:SetHeight(math.max(h + 10, 100)) end

  -- Les boutons du bas selon l'onglet.
  bas1:Hide(); bas2:Hide()
  if o[1] == "talents" then
    bas1:SetText("Prendre ce talent")
    bas1:SetScript("OnClick", function() ns.prendreTalent() end)
    bas1:SetEnabled(e.talents and e.talents.etat == "suivant" and true or false)
    bas1:Show()
    bas2:SetText("Exporter mon arbre")
    bas2:SetScript("OnClick", function() ns.exporter() end)
    bas2:Show()
  elseif o[1] == "rotation" then
    bas1:SetText("Changer de mode")
    bas1:SetEnabled(true)
    bas1:SetScript("OnClick", function()
      local actuel = ns.reglages.db and ns.reglages.db.modeRotation or 1
      ns.reglages.changer("modeRotation", actuel % 3 + 1)
      ns.fenetre.maj()
    end)
    bas1:Show()
  end
end

ns.fenetre = {
  maj = maj,
  montrer = function() fenetre:Show() end,
  cacher = function() fenetre:Hide() end,
  basculer = function() if fenetre:IsShown() then fenetre:Hide() else fenetre:Show() end end,
  onglet = function(i)
    ongletCourant = i
    ns.fenetre.maj()
    if defile.SetVerticalScroll then defile:SetVerticalScroll(0) end
  end,
}
ns.majFenetre = maj

boutonSituation:SetScript("OnClick", function()
  -- auto -> solo -> groupe -> donjon -> raid -> auto
  local ordre = D.SITUATIONS
  local suivant
  if not ns.situationForcee then suivant = ordre[1]
  else
    for i, s in ipairs(ordre) do
      if s == ns.situationForcee then suivant = ordre[i + 1]; break end
    end
  end
  ns.situationForcee = suivant
  ns.talentsSale = true
  maj()
end)
boutonSituation:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
  GameTooltip:AddLine("Situation")
  GameTooltip:AddLine("Conseiller détecte seul si tu es seul, en groupe, en donjon ou en raid. Ce bouton te montre les conseils des autres situations (la détection reprend à la fermeture).", 1, 1, 1, true)
  GameTooltip:Show()
end)
boutonSituation:SetScript("OnLeave", function() GameTooltip:Hide() end)

fenetre:SetScript("OnShow", maj)
fenetre:SetScript("OnHide", function()
  ns.situationForcee = nil
  ns.talentsSale = true
end)
