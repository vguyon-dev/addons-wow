-- ============================================================================
-- Courrier : récupérer son courrier en un clic (comme Postal, réécrit à notre
-- façon, sans reprendre son code).
--
-- Sous la boîte aux lettres, une barre ajoutée :
--   - « Tout récupérer » : l'or et les objets de tous les courriers ;
--   - « Or seulement »   : l'or (ventes de l'hôtel des ventes…), objets laissés ;
--   - « Récupérer les cochés » : seulement les courriers cochés (une case à
--     gauche de chaque courrier de la liste).
-- Une seule action toutes les 0,3 s, comme le ferait un joueur : le jeu
-- l'autorise sans appui, et c'est ce que fait Postal. Rien ne part tant que tu
-- n'as pas cliqué sur un bouton. Jamais de contre-remboursement payé, jamais de
-- courrier d'un MJ ouvert, arrêt quand les sacs sont pleins.
-- ============================================================================

local NOM_ADDON, ns = ...

local DEFAUTS = {
  actif = true,
  cases = true,      -- une case à cocher devant chaque courrier
  minimap = false,   -- icône à part (sinon seulement l'icône commune)
  angleMinimap = 300,
}

local db

-- ---------------------------------------------------------------------------
-- Partie « logique pure », testée hors jeu (tests/Courrier_simu.lua).
-- ---------------------------------------------------------------------------

-- Une clé qui reconnaît un courrier même quand sa place dans la liste change
-- (la liste se resserre chaque fois qu'un courrier vidé disparaît).
function ns.cleCourrier(c)
  -- Ni l'or ni le nombre d'objets : ils changent pendant qu'on vide le courrier,
  -- et un courrier coché doit le rester jusqu'au bout.
  return table.concat({ tostring(c.expediteur or "?"), tostring(c.sujet or ""), string.format("%.1f", c.jours or 0) }, "|")
end

-- Ce qu'il reste à prendre dans un courrier, selon le mode.
local function aPrendre(c, mode)
  if c.mj or (c.contreRemboursement or 0) > 0 then return false end
  if (c.argent or 0) > 0 then return true end
  return mode ~= "or" and (c.nbObjets or 0) > 0
end

-- La prochaine action à faire.
--   courriers : { { index, expediteur, sujet, argent, contreRemboursement, nbObjets,
--                   premierePiece, jours, mj } } (dans l'ordre de la boîte)
--   mode      : "tout", "or" ou "coches"
--   coches    : [cle] = vrai, pour le mode "coches"
--   sacsLibres: nombre de places libres dans les sacs
--   bloques   : [cle] = vrai, courriers à sauter (une action qui n'a rien donné)
-- Renvoie { action = "argent" | "objet", index, piece } ou nil et la raison :
-- "fini" ou "sacs pleins".
function ns.prochaineAction(courriers, mode, coches, sacsLibres, bloques)
  coches, bloques = coches or {}, bloques or {}
  local sacsPleins = false
  -- On part de la fin : prendre le dernier ne décale pas les précédents.
  for i = #courriers, 1, -1 do
    local c = courriers[i]
    local cle = ns.cleCourrier(c)
    local retenu = not bloques[cle] and (mode ~= "coches" or coches[cle])
    if retenu and aPrendre(c, mode == "coches" and "tout" or mode) then
      if (c.argent or 0) > 0 then
        return { action = "argent", index = c.index }
      end
      if (sacsLibres or 0) > 0 and c.premierePiece then
        return { action = "objet", index = c.index, piece = c.premierePiece }
      end
      sacsPleins = true
    end
  end
  return nil, sacsPleins and "sacs pleins" or "fini"
end

-- Combien de courriers restent à traiter (pour la barre de progression).
function ns.restants(courriers, mode, coches, bloques)
  coches, bloques = coches or {}, bloques or {}
  local n = 0
  for _, c in ipairs(courriers) do
    local cle = ns.cleCourrier(c)
    if not bloques[cle] and (mode ~= "coches" or coches[cle]) and aPrendre(c, mode == "coches" and "tout" or mode) then
      n = n + 1
    end
  end
  return n
end

-- « 45 po 12 pa 3 pc » sans icônes, pour le texte d'état.
function ns.texteArgent(cuivre)
  cuivre = math.max(0, math.floor(cuivre or 0))
  local po, pa, pc = math.floor(cuivre / 10000), math.floor(cuivre % 10000 / 100), cuivre % 100
  local t = {}
  if po > 0 then t[#t + 1] = po .. " po" end
  if pa > 0 then t[#t + 1] = pa .. " pa" end
  if pc > 0 or #t == 0 then t[#t + 1] = pc .. " pc" end
  return table.concat(t, " ")
end

if not CreateFrame or not GetInboxNumItems then return end -- hors jeu : la suite ne sert qu'en jeu

-- ---------------------------------------------------------------------------
-- Lecture de la boîte
-- ---------------------------------------------------------------------------

local MAX_PIECES = ATTACHMENTS_MAX_RECEIVE or 16

local function lireBoite()
  local liste = {}
  for i = 1, GetInboxNumItems() do
    local _, _, expediteur, sujet, argent, cr, jours, nbObjets, _, _, _, _, mj = GetInboxHeaderInfo(i)
    local premiere
    if (nbObjets or 0) > 0 then
      for p = 1, MAX_PIECES do
        if GetInboxItem(i, p) then premiere = p break end
      end
    end
    liste[#liste + 1] = { index = i, expediteur = expediteur, sujet = sujet, argent = argent or 0,
      contreRemboursement = cr or 0, nbObjets = nbObjets or 0, premierePiece = premiere, jours = jours or 0, mj = mj }
  end
  return liste
end

local function placesLibres()
  local n = 0
  for sac = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 do
    local libres
    if C_Container and C_Container.GetContainerNumFreeSlots then
      libres = C_Container.GetContainerNumFreeSlots(sac)
    elseif GetContainerNumFreeSlots then
      libres = GetContainerNumFreeSlots(sac)
    end
    n = n + (libres or 0)
  end
  return n
end

-- ---------------------------------------------------------------------------
-- La récupération
-- ---------------------------------------------------------------------------

local coches = {}          -- [cle] = vrai : courriers cochés (pour cette ouverture de la boîte)
local enCours              -- { mode, total, argentDepart, objets, minuteur, dernier, essais, bloques }
local barre, majBarre      -- l'interface, créée à la première ouverture de la boîte

local function arreter(message)
  if not enCours then return end
  if enCours.minuteur then enCours.minuteur:Cancel() end
  local gagne = GetMoney() - enCours.argentDepart
  local resume = (gagne > 0 and ns.texteArgent(gagne) or "pas d'or") .. ", " .. enCours.objets .. " objet(s)"
  enCours = nil
  if message then ns.reglages.dire(message .. " (" .. resume .. ").") end
  if majBarre then majBarre() end
end

local function etape()
  if not enCours then return end
  if not (MailFrame and MailFrame:IsShown()) then arreter() return end
  local courriers = lireBoite()
  local a, raison = ns.prochaineAction(courriers, enCours.mode, coches, placesLibres(), enCours.bloques)
  if not a then
    arreter(raison == "sacs pleins" and "|cffff4040sacs pleins|r : fais de la place puis relance" or "terminé")
    return
  end
  -- La même action trois fois de suite sans effet : on saute ce courrier.
  local c = courriers[a.index]
  local cle = ns.cleCourrier(c)
  local signature = cle .. a.action .. (a.piece or "")
  if enCours.dernier == signature then
    enCours.essais = enCours.essais + 1
    if enCours.essais >= 3 then enCours.bloques[cle] = true; enCours.essais = 0 end
  else
    enCours.dernier, enCours.essais = signature, 0
  end
  if a.action == "argent" then
    TakeInboxMoney(a.index)
  else
    TakeInboxItem(a.index, a.piece)
    enCours.objets = enCours.objets + 1
  end
  if majBarre then majBarre() end
end

local function demarrer(mode)
  if not db.actif then ns.reglages.dire("Courrier est coupé : active-le dans ses réglages.") return end
  if enCours then arreter("arrêté") return end
  if mode == "coches" and not next(coches) then ns.reglages.dire("coche d'abord des courriers.") return end
  local total = ns.restants(lireBoite(), mode, coches, {})
  if total == 0 then ns.reglages.dire(mode == "or" and "aucun or à prendre." or "rien à récupérer.") return end
  enCours = { mode = mode, total = total, argentDepart = GetMoney(), objets = 0, essais = 0, bloques = {} }
  enCours.minuteur = C_Timer.NewTicker(0.3, etape)
  etape()
end

-- ---------------------------------------------------------------------------
-- L'interface : une barre sous la boîte aux lettres, une case par courrier
-- ---------------------------------------------------------------------------

local boutons = {}
local casesCourrier = {}

local function creerInterface()
  if barre or not MailFrame then return end
  barre = CreateFrame("Frame", "CourrierBarre", MailFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
  barre:SetPoint("TOPLEFT", MailFrame, "BOTTOMLEFT", 0, -2)
  barre:SetPoint("TOPRIGHT", MailFrame, "BOTTOMRIGHT", 0, -2)
  barre:SetHeight(58)
  if barre.SetBackdrop then
    barre:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    barre:SetBackdropColor(0.07, 0.06, 0.045, 0.95)
    barre:SetBackdropBorderColor(0.80, 0.63, 0.30, 1)
  end

  local defs = {
    { "tout", "Tout récupérer", "L'or et les objets de tous les courriers. Les contre-remboursements sont laissés de côté." },
    { "or", "Or seulement", "Seulement l'or (ventes de l'hôtel des ventes…). Les objets restent dans la boîte." },
    { "coches", "Les cochés", "Seulement les courriers cochés dans la liste (case à gauche de chaque courrier)." },
  }
  local x = 8
  for _, d in ipairs(defs) do
    local b = ns.creerBouton(barre, d[2], d[3] .. "\nCliquer pendant la récupération l'arrête.", function() demarrer(d[1]) end, 108)
    b:SetPoint("TOPLEFT", x, -7)
    boutons[d[1]] = b
    x = x + 112
  end

  local fond = CreateFrame("StatusBar", nil, barre)
  fond:SetPoint("TOPLEFT", 10, -34)
  fond:SetPoint("TOPRIGHT", -10, -34)
  fond:SetHeight(8)
  fond:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  fond:SetStatusBarColor(0.12, 0.85, 0.1)
  fond:SetMinMaxValues(0, 1)
  local fondGris = fond:CreateTexture(nil, "BACKGROUND")
  fondGris:SetAllPoints()
  fondGris:SetColorTexture(0, 0, 0, 0.6)
  local etat = barre:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  etat:SetPoint("TOPLEFT", fond, "BOTTOMLEFT", 0, -2)

  majBarre = function()
    if not barre then return end
    local courriers = lireBoite()
    for mode, b in pairs(boutons) do
      b:SetText(enCours and enCours.mode == mode and "Arrêter" or
        ({ tout = "Tout récupérer", ["or"] = "Or seulement", coches = "Les cochés" })[mode])
    end
    if enCours then
      local reste = ns.restants(courriers, enCours.mode, coches, enCours.bloques)
      local fait = math.max(0, enCours.total - reste)
      fond:SetValue(enCours.total > 0 and fait / enCours.total or 1)
      etat:SetText(fait .. " / " .. enCours.total .. " courriers · " .. ns.texteArgent(GetMoney() - enCours.argentDepart)
        .. " · " .. enCours.objets .. " objet(s)")
    else
      fond:SetValue(0)
      local tout, orSeul = ns.restants(courriers, "tout"), ns.restants(courriers, "or")
      local nCoches = 0
      for _ in pairs(coches) do nCoches = nCoches + 1 end
      local _, total = GetInboxNumItems()
      local enAttente = (total or 0) - #courriers
      etat:SetText(tout .. " courrier(s) à récupérer, dont " .. orSeul .. " avec de l'or · " .. nCoches .. " coché(s)"
        .. (enAttente > 0 and (" · " .. enAttente .. " encore sur le serveur") or ""))
    end
  end

  -- Une case à cocher devant chaque ligne de la liste de la boîte.
  for i = 1, INBOXITEMS_TO_DISPLAY or 7 do
    local ligne = _G["MailItem" .. i]
    if ligne then
      local c = CreateFrame("CheckButton", nil, ligne, "UICheckButtonTemplate")
      c:SetSize(22, 22)
      c:SetPoint("RIGHT", ligne, "LEFT", 2, 0)
      c:SetFrameLevel(ligne:GetFrameLevel() + 5)
      c:SetScript("OnClick", function(self)
        if self.cle then coches[self.cle] = self:GetChecked() and true or nil end
        majBarre()
      end)
      casesCourrier[i] = c
    end
  end
end

local function majCases()
  if not barre then return end
  local page = (InboxFrame and InboxFrame.pageNum) or 1
  local parPage = INBOXITEMS_TO_DISPLAY or 7
  local courriers = lireBoite()
  for i, c in pairs(casesCourrier) do
    local courrier = courriers[(page - 1) * parPage + i]
    if db.actif and db.cases and courrier then
      c.cle = ns.cleCourrier(courrier)
      c:SetChecked(coches[c.cle] and true or false)
      c:Show()
    else
      c.cle = nil
      c:Hide()
    end
  end
  boutons.coches:SetShown(db.actif and db.cases)
  majBarre()
end

-- ---------------------------------------------------------------------------
-- Réglages et événements
-- ---------------------------------------------------------------------------

ns.reglages = ns.creerReglages({
  titre = "Courrier",
  icone = "Interface\\Icons\\INV_Letter_15",
  nomDB = "CourrierDB",
  defauts = DEFAUTS,
  options = {
    { titre = "Courrier" },
    { cle = "actif", libelle = "Activer Courrier",
      aide = "Une barre sous la boîte aux lettres : « Tout récupérer », « Or seulement » et « Les cochés ». Rien ne se fait sans un clic de ta part." },
    { cle = "cases", libelle = "Cases à cocher devant les courriers",
      aide = "Pour choisir quels courriers récupérer avec « Les cochés ». Les cases se vident quand tu fermes la boîte." },
    { titre = "Icône" },
    { cle = "minimap", libelle = "Icône à part autour de la minimap",
      aide = "En plus de la ligne dans l'icône commune des addons de Valentin." },
  },
  astuce = "Jamais de contre-remboursement payé ni de courrier de MJ ouvert. La récupération s'arrête quand tes sacs sont pleins, quand tu fermes la boîte, ou si tu recliques sur le bouton.",
  auChargement = function(d) db = d end,
  surChangement = function(d)
    if barre then barre:SetShown(d.actif) end
    if not d.actif then arreter() end
    majCases()
  end,
})

local ecouteur = CreateFrame("Frame")
for _, e in ipairs({ "MAIL_SHOW", "MAIL_CLOSED", "MAIL_INBOX_UPDATE", "UI_ERROR_MESSAGE" }) do
  ecouteur:RegisterEvent(e)
end
ecouteur:SetScript("OnEvent", function(_, evenement, _, message)
  if evenement == "MAIL_SHOW" then
    creerInterface()
    if barre then barre:SetShown(db.actif) end
    majCases()
  elseif evenement == "MAIL_CLOSED" then
    arreter()
    coches = {}
  elseif evenement == "MAIL_INBOX_UPDATE" then
    majCases()
  elseif evenement == "UI_ERROR_MESSAGE" and enCours then
    if message == ERR_INV_FULL or message == ERR_ITEM_MAX_COUNT then
      arreter("|cffff4040" .. tostring(message) .. "|r : récupération arrêtée")
    end
  end
end)

if InboxFrame_Update then hooksecurefunc("InboxFrame_Update", majCases) end

SLASH_COURRIER1 = "/courrier"
SlashCmdList.COURRIER = function(message)
  local commande = strtrim(message or ""):lower()
  if commande == "on" or commande == "off" then
    if (commande == "on") ~= (db.actif and true or false) then ns.reglages.basculer() end
  elseif commande == "tout" or commande == "or" then
    if MailFrame and MailFrame:IsShown() then demarrer(commande) else ns.reglages.dire("ouvre d'abord une boîte aux lettres.") end
  elseif commande == "" or commande == "options" or commande == "reglages" then
    ns.reglages.ouvrir()
  elseif not ns.reglages.basculerOption(commande) then
    ns.reglages.dire("/courrier : réglages ; /courrier tout | or : récupérer (boîte ouverte) ; /courrier on | off")
  end
end
