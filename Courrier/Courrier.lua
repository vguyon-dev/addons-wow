-- ============================================================================
-- Courrier : récupérer son courrier en un clic (comme Postal, réécrit à notre
-- façon, sans reprendre son code).
--
-- Sous la boîte aux lettres, une barre ajoutée :
--   - « Tout récupérer » : l'or et les objets de tous les courriers ;
--   - « Or seulement »   : l'or (ventes de l'hôtel des ventes…), objets laissés ;
--   - « Récupérer les cochés » : seulement les courriers cochés (une case à
--     gauche de chaque courrier de la liste).
-- Et sur l'onglet Envoyer : une petite liste de destinataires rapides (tes autres
-- personnages du royaume, les 8 derniers destinataires, et « Compléter » le nom
-- tapé), un rappel du clic droit sur un objet du sac (pièce jointe, c'est le
-- jeu qui le fait, aussi sur les cases du sac rangé de Sacs rangés), et, à la
-- fin d'une récupération, un bilan dans le chat (or, objets, courriers laissés
-- de côté et pourquoi).
-- Une seule action toutes les 0,3 s, comme le ferait un joueur : le jeu
-- l'autorise sans appui, et c'est ce que fait Postal. Rien ne part tant que tu
-- n'as pas cliqué sur un bouton. Jamais de contre-remboursement payé, jamais de
-- courrier d'un MJ ouvert, arrêt quand les sacs sont pleins.
-- ============================================================================

local NOM_ADDON, ns = ...

local DEFAUTS = {
  actif = true,
  cases = true,      -- une case à cocher devant chaque courrier
  destinataires = true, -- la liste de destinataires rapides sur l'onglet Envoyer
  pieceJointe = true,   -- le rappel du clic droit sur un objet du sac
  bilan = true,         -- le bilan dans le chat à la fin d'une récupération
  persos = {},          -- [royaume] = { [nom du personnage] = vrai }, retenus à chaque connexion
  recents = {},         -- les derniers destinataires, le plus récent d'abord
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

-- ---------------------------------------------------------------------------
-- Les destinataires rapides
-- ---------------------------------------------------------------------------

local MAX_RECENTS = 8

local function net(nom)
  if type(nom) ~= "string" then return "" end
  return (nom:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Met un destinataire en tête des derniers destinataires (sans doublon, 8 au plus).
-- Rend la nouvelle liste.
function ns.retenirDestinataire(recents, nom, max)
  max = max or MAX_RECENTS
  nom = net(nom)
  local liste = {}
  if nom == "" then
    for _, n in ipairs(recents or {}) do liste[#liste + 1] = n end
    return liste
  end
  liste[1] = nom
  for _, n in ipairs(recents or {}) do
    if type(n) == "string" and n:lower() ~= nom:lower() and #liste < max then liste[#liste + 1] = n end
  end
  return liste
end

-- Retient un personnage du royaume. Rend vrai si la table a changé.
function ns.retenirPerso(persos, royaume, nom)
  nom = net(nom)
  if type(persos) ~= "table" or type(royaume) ~= "string" or royaume == "" or nom == "" then return false end
  persos[royaume] = persos[royaume] or {}
  if persos[royaume][nom] then return false end
  persos[royaume][nom] = true
  return true
end

-- La liste affichée : une ligne de titre par section (« section »), puis les noms (« nom »).
--   persos : [royaume] = { [nom] = vrai } ; moi : le personnage connecté (pas listé)
-- Les autres personnages du royaume d'abord (alphabétique), puis les derniers
-- destinataires qui ne sont pas déjà dans la première section.
function ns.listeDestinataires(persos, royaume, moi, recents)
  local liste, vus = {}, { [net(moi):lower()] = true }
  local autres = {}
  for nom in pairs((persos or {})[royaume] or {}) do
    if not vus[nom:lower()] then vus[nom:lower()] = true; autres[#autres + 1] = nom end
  end
  table.sort(autres, function(a, b) return a:lower() < b:lower() end)
  if #autres > 0 then
    liste[#liste + 1] = { section = "Mes personnages" }
    for _, nom in ipairs(autres) do liste[#liste + 1] = { nom = nom } end
  end
  local debut = #liste + 1
  local n = 0
  for _, nom in ipairs(recents or {}) do
    if type(nom) == "string" and net(nom) ~= "" and not vus[nom:lower()] and n < MAX_RECENTS then
      vus[nom:lower()] = true
      n = n + 1
      liste[#liste + 1] = { nom = nom }
    end
  end
  if n > 0 then table.insert(liste, debut, { section = "Derniers destinataires" }) end
  return liste
end

-- Le premier nom de la liste qui commence par ce qui est tapé (sans tenir compte
-- des majuscules). Rien tapé ou rien trouvé : nil.
function ns.completerNom(saisie, liste)
  saisie = net(saisie):lower()
  if saisie == "" then return nil end
  for _, e in ipairs(liste or {}) do
    if e.nom and e.nom:lower():sub(1, #saisie) == saisie then return e.nom end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- Le bilan d'une récupération
-- ---------------------------------------------------------------------------

-- Combien de courriers ont été laissés de côté, et pourquoi.
--   courriers : la boîte telle qu'elle est à la fin ; mode, coches, bloques : comme pour
--   ns.prochaineAction ; sacsPleins : la récupération s'est arrêtée faute de place.
-- Rend { contreRemboursement, mj, sacsPleins, bloques } (des nombres).
function ns.courriersLaisses(courriers, mode, coches, bloques, sacsPleins)
  coches, bloques = coches or {}, bloques or {}
  local l = { contreRemboursement = 0, mj = 0, sacsPleins = 0, bloques = 0 }
  for _, c in ipairs(courriers or {}) do
    local cle = ns.cleCourrier(c)
    if mode ~= "coches" or coches[cle] then
      if c.mj then
        if (c.argent or 0) > 0 or (c.nbObjets or 0) > 0 then l.mj = l.mj + 1 end
      elseif (c.contreRemboursement or 0) > 0 then
        l.contreRemboursement = l.contreRemboursement + 1
      elseif aPrendre(c, mode == "coches" and "tout" or mode) then
        if bloques[cle] then
          l.bloques = l.bloques + 1
        elseif sacsPleins then
          l.sacsPleins = l.sacsPleins + 1
        end
      end
    end
  end
  return l
end

-- « 4 po 80 pa, 12 objet(s) » : ce qui a été récupéré.
function ns.texteBilan(gagne, objets)
  return ((gagne or 0) > 0 and ns.texteArgent(gagne) or "pas d'or") .. ", " .. (objets or 0) .. " objet(s)"
end

-- Les courriers laissés de côté, en une phrase ; nil s'il n'y en a pas.
function ns.texteLaisses(l)
  if type(l) ~= "table" then return nil end
  local t = {}
  if (l.contreRemboursement or 0) > 0 then t[#t + 1] = l.contreRemboursement .. " en contre-remboursement (jamais payé)" end
  if (l.mj or 0) > 0 then t[#t + 1] = l.mj .. " de MJ (jamais ouvert)" end
  if (l.sacsPleins or 0) > 0 then t[#t + 1] = l.sacsPleins .. " faute de place dans les sacs" end
  if (l.bloques or 0) > 0 then t[#t + 1] = l.bloques .. " impossible(s) à vider" end
  if #t == 0 then return nil end
  return "courriers laissés de côté : " .. table.concat(t, ", ")
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

local function arreter(message, sacsPleins)
  if not enCours then return end
  if enCours.minuteur then enCours.minuteur:Cancel() end
  local en = enCours
  local gagne = GetMoney() - en.argentDepart
  enCours = nil
  -- Boîte fermée en route : avec le bilan, on dit quand même ce qui a été pris.
  if not message and db.bilan and (gagne > 0 or en.objets > 0) then message = "boîte fermée" end
  if message then
    ns.reglages.dire(message .. " (" .. ns.texteBilan(gagne, en.objets) .. ").")
    if db.bilan then
      local ok, laisses = pcall(function()
        return ns.texteLaisses(ns.courriersLaisses(lireBoite(), en.mode, coches, en.bloques, sacsPleins))
      end)
      if ok and laisses then ns.reglages.dire(laisses .. ".") end
    end
  end
  if majBarre then majBarre() end
end

local function etape()
  if not enCours then return end
  if not (MailFrame and MailFrame:IsShown()) then arreter() return end
  local courriers = lireBoite()
  local a, raison = ns.prochaineAction(courriers, enCours.mode, coches, placesLibres(), enCours.bloques)
  if not a then
    arreter(raison == "sacs pleins" and "|cffff4040sacs pleins|r : fais de la place puis relance" or "terminé", raison == "sacs pleins")
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
  ns.habiller(barre)

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

-- Les destinataires rapides : un bouton à droite du champ « À » ouvre une petite
-- liste dessous ; un clic sur un nom remplit le champ (rien n'est envoyé).
local panneauDest, boutonDest, remplirDest
local lignesDest = {}

local function creerDestinataires()
  if panneauDest or not (SendMailFrame and SendMailNameEditBox) then return end
  local champ = SendMailNameEditBox
  boutonDest = CreateFrame("Button", nil, SendMailFrame)
  boutonDest:SetSize(24, 24)
  boutonDest:SetPoint("LEFT", champ, "RIGHT", 2, 0)
  boutonDest:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
  boutonDest:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down")
  boutonDest:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

  panneauDest = CreateFrame("Frame", nil, SendMailFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
  panneauDest:SetFrameStrata("DIALOG")
  panneauDest:SetPoint("TOPLEFT", champ, "BOTTOMLEFT", -4, -2)
  panneauDest:SetWidth(210)
  panneauDest:Hide()
  ns.habiller(panneauDest)
  local astuce = panneauDest:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  astuce:SetWidth(190)
  astuce:SetJustifyH("LEFT")
  astuce:SetText("Astuce : clic droit sur un objet du sac pour l'ajouter en pièce jointe.")

  local function ligneNumero(i)
    local l = lignesDest[i]
    if l then return l end
    l = CreateFrame("Button", nil, panneauDest)
    l:SetSize(194, 18)
    l:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    l.texte = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l.texte:SetPoint("LEFT", 4, 0)
    l.texte:SetPoint("RIGHT", -4, 0)
    l.texte:SetJustifyH("LEFT")
    l:SetScript("OnClick", function(self)
      if not self.nomChoisi then return end
      champ:SetText(self.nomChoisi)
      if champ.SetCursorPosition then champ:SetCursorPosition(#self.nomChoisi) end
      panneauDest:Hide()
    end)
    lignesDest[i] = l
    return l
  end

  remplirDest = function()
    local moi = UnitName and UnitName("player") or ""
    local royaume = GetRealmName and GetRealmName() or "?"
    local liste = ns.listeDestinataires(db.persos, royaume, moi, db.recents)
    local tape = champ:GetText() or ""
    local completion = ns.completerNom(tape, liste)
    -- Première ligne : compléter le nom tapé.
    local rangees = { { complet = true } }
    for _, e in ipairs(liste) do rangees[#rangees + 1] = e end
    local y = -8
    for i, e in ipairs(rangees) do
      local l = ligneNumero(i)
      l:ClearAllPoints()
      l:SetPoint("TOPLEFT", 8, y)
      l.nomChoisi = nil
      if e.complet then
        if completion and completion:lower() ~= net(tape):lower() then
          l.texte:SetText("|cff66ff66Compléter :|r " .. completion)
          l.nomChoisi = completion
        elseif completion then
          l.texte:SetText("|cff888888Nom déjà complet|r")
        else
          l.texte:SetText("|cff888888Compléter (tape le début d'un nom)|r")
        end
      elseif e.section then
        l.texte:SetText("|cffffd24d" .. e.section .. "|r")
      else
        l.texte:SetText(e.nom)
        l.nomChoisi = e.nom
      end
      l:SetEnabled(l.nomChoisi ~= nil)
      l:Show()
      y = y - 18
    end
    for i = #rangees + 1, #lignesDest do lignesDest[i]:Hide() end
    astuce:ClearAllPoints()
    astuce:SetShown(db.pieceJointe and true or false)
    if db.pieceJointe then
      astuce:SetPoint("TOPLEFT", 12, y - 4)
      y = y - 4 - 26
    end
    panneauDest:SetHeight(-y + 8)
  end

  boutonDest:SetScript("OnClick", function()
    if panneauDest:IsShown() then panneauDest:Hide() else remplirDest(); panneauDest:Show() end
  end)
  boutonDest:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Destinataires rapides")
    GameTooltip:AddLine("Tes autres personnages du royaume, les derniers destinataires, et le nom tapé complété.", 1, 1, 1, true)
    if db.pieceJointe then GameTooltip:AddLine("Clic droit sur un objet du sac : pièce jointe.", 0.6, 0.9, 0.6, true) end
    GameTooltip:Show()
  end)
  boutonDest:SetScript("OnLeave", function() GameTooltip:Hide() end)
  SendMailFrame:HookScript("OnHide", function() panneauDest:Hide() end)
  -- La liste se met à jour quand on tape.
  if champ.HookScript then
    champ:HookScript("OnTextChanged", function() if panneauDest:IsShown() then remplirDest() end end)
  end
end

local function majDestinataires()
  if not boutonDest then return end
  local voulu = db.actif and db.destinataires and true or false
  boutonDest:SetShown(voulu)
  if not voulu then panneauDest:Hide() end
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
    { titre = "Envoyer" },
    { cle = "destinataires", libelle = "Destinataires rapides sur l'onglet Envoyer",
      aide = "Un petit bouton à droite du champ « À » ouvre la liste : tes autres personnages du royaume (retenus à chaque connexion), les 8 derniers destinataires, et « Compléter » le nom tapé. Un clic remplit le champ, rien n'est envoyé." },
    { cle = "pieceJointe", libelle = "Rappel : clic droit sur un objet du sac = pièce jointe", dependDe = "destinataires",
      aide = "Boîte ouverte sur l'onglet Envoyer, un clic droit sur un objet de ton sac l'ajoute en pièce jointe : c'est le jeu qui le fait, y compris sur les cases du sac rangé de Sacs rangés. Cette option affiche seulement le rappel dans la liste." },
    { titre = "Bilan" },
    { cle = "bilan", libelle = "Bilan dans le chat à la fin d'une récupération",
      aide = "À la fin : l'or et le nombre d'objets pris, puis les courriers laissés de côté et pourquoi (contre-remboursement, MJ, sacs pleins)." },
    { titre = "Icône" },
    { cle = "minimap", libelle = "Icône à part autour de la minimap",
      aide = "En plus de la ligne dans l'icône commune des addons de Valentin." },
  },
  astuce = "Jamais de contre-remboursement payé ni de courrier de MJ ouvert. La récupération s'arrête quand tes sacs sont pleins, quand tu fermes la boîte, ou si tu recliques sur le bouton.",
  auChargement = function(d) db = d end,
  surChangement = function(d)
    if barre then barre:SetShown(d.actif) end
    if not d.actif then arreter() end
    majDestinataires()
    majCases()
  end,
})

local ecouteur = CreateFrame("Frame")
for _, e in ipairs({ "MAIL_SHOW", "MAIL_CLOSED", "MAIL_INBOX_UPDATE", "UI_ERROR_MESSAGE", "PLAYER_ENTERING_WORLD", "MAIL_SEND_SUCCESS" }) do
  pcall(ecouteur.RegisterEvent, ecouteur, e)
end

-- Le destinataire du dernier envoi demandé, retenu quand le jeu confirme l'envoi.
local dernierDest
local function surEnvoi(destinataire) dernierDest = destinataire end
if C_Mail and C_Mail.SendMail then pcall(hooksecurefunc, C_Mail, "SendMail", surEnvoi) end
if SendMail then pcall(hooksecurefunc, "SendMail", surEnvoi) end

ecouteur:SetScript("OnEvent", function(_, evenement, _, message)
  if evenement == "PLAYER_ENTERING_WORLD" then
    if db and UnitName then ns.retenirPerso(db.persos, GetRealmName and GetRealmName() or "?", UnitName("player")) end
  elseif evenement == "MAIL_SEND_SUCCESS" then
    if db and dernierDest then db.recents = ns.retenirDestinataire(db.recents, dernierDest, MAX_RECENTS) end
    dernierDest = nil
  elseif evenement == "MAIL_SHOW" then
    creerInterface()
    pcall(creerDestinataires)
    majDestinataires()
    if barre then barre:SetShown(db.actif) end
    majCases()
  elseif evenement == "MAIL_CLOSED" then
    arreter()
    coches = {}
  elseif evenement == "MAIL_INBOX_UPDATE" then
    majCases()
  elseif evenement == "UI_ERROR_MESSAGE" and enCours then
    if message == ERR_INV_FULL or message == ERR_ITEM_MAX_COUNT then
      arreter("|cffff4040" .. tostring(message) .. "|r : récupération arrêtée", true)
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
