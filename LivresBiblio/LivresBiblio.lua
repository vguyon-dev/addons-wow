-- ============================================================================
-- Livres de bibliothèque (WoW Forever) : où sont les livres à ramasser, et
-- ceux qu'il te reste.
--
-- Ce qui change par rapport à l'addon téléchargé : un livre disparaît de la
-- carte DÈS QUE TU L'AS RAMASSÉ, pas seulement quand tu l'as rendu au PNJ.
-- Trois états par livre :
--   à trouver : ni dans tes sacs, ni rendu → épinglé sur la carte ;
--   à rendre  : ramassé (vu dans tes sacs) → plus sur la carte,
--               le PNJ à qui le rendre est épinglé à la place ;
--   rendu     : sa quête de rendu est validée → plus rien.
--
--  - Épingles sur la carte du monde (zone et continent), clic gauche = balise
--    (TomTom s'il est installé, sinon la balise du jeu), clic droit = marquer
--    ramassé ou pas (pour un livre ramassé avant d'installer l'addon et
--    rangé en banque).
--  - Panneau /livres : tous les livres, leur état, le compte.
-- ============================================================================

local NOM_ADDON, ns = ...

local DEFAUTS = {
  actif = true,
  continent = true,        -- épingles aussi sur les cartes de Kalimdor et des Royaumes de l'Est
  niv60 = true,            -- montrer les livres « niveau 60 »
  aRendre = false,         -- montrer aussi, en grisé, les livres ramassés pas encore rendus
  pnj = true,              -- épingler le PNJ à qui rendre quand tu as des livres sur toi
  minimap = false,         -- icône à part (sinon seulement l'icône commune)
  angleMinimap = 40,
}

local db
local baliserLePlusProche
local perso -- LivresBiblioPerso : { ramasses = { [quete] = true } }, propre à chaque personnage

-- ---------------------------------------------------------------------------
-- Partie « logique pure », testée hors jeu (tests/LivresBiblio_simu.lua).
-- ---------------------------------------------------------------------------

-- Nom simplifié pour comparer un objet à un livre : minuscules, sans espaces
-- ni ponctuation, apostrophe typographique ramenée à la simple.
-- Lettres accentuées (UTF-8) ramenées à la lettre simple : le jeu écrit parfois
-- « Theocritus » là où le livre s'appelle « Théocritus ».
local SANS_ACCENT = {
  ["à"] = "a", ["â"] = "a", ["ä"] = "a", ["ç"] = "c", ["é"] = "e", ["è"] = "e", ["ê"] = "e",
  ["ë"] = "e", ["î"] = "i", ["ï"] = "i", ["ô"] = "o", ["ö"] = "o", ["ù"] = "u", ["û"] = "u",
  ["ü"] = "u", ["œ"] = "oe", ["É"] = "e", ["È"] = "e", ["À"] = "a", ["Ç"] = "c",
}

function ns.simplifier(texte)
  if type(texte) ~= "string" then return "" end
  texte = texte:gsub("[\195\197][\128-\191]", function(c) return SANS_ACCENT[c] end)
  -- Tout le reste en minuscules, sans espaces ni ponctuation (’ compris).
  texte = texte:lower():gsub("\226\128[\152\153]", "")
  return (texte:gsub("[%s%p]", ""))
end

-- Les noms simplifiés d'un livre (titre français, anglais, et noms d'objet
-- connus quand l'objet ne porte pas le titre), calculés une seule fois.
local function titresDe(livre)
  if not livre.simples then
    livre.simples = {}
    for _, t in ipairs({ livre.nom, livre.en, unpack(livre.objets or {}) }) do
      livre.simples[#livre.simples + 1] = ns.simplifier(t)
    end
  end
  return livre.simples
end

-- L'objet est-il ce livre ? Le nom de l'objet peut avoir des mots en plus
-- (« Le journal de… », « Almanach de Nar'thalas, vol. 74 ») : il doit
-- CONTENIR un titre du livre. Un titre court (« Ka-Boom! ») doit être égal,
-- pour qu'un objet ordinaire ne soit jamais pris pour un livre.
-- objetSimple : le nom de l'objet déjà simplifié (ns.simplifier).
function ns.estCeLivre(objetSimple, livre)
  local o = objetSimple
  if #o < 5 then return false end
  for _, t in ipairs(titresDe(livre)) do
    if #t >= 10 then
      if o:find(t, 1, true) then return true end
    elseif #t >= 5 and o == t then
      return true
    end
  end
  return false
end

-- État d'un livre : « rendu », « aRendre » ou « aTrouver ».
function ns.etat(livre, estRendue, ramasses)
  if estRendue(livre.quete) then return "rendu" end
  if ramasses[livre.quete] then return "aRendre" end
  return "aTrouver"
end

-- Position d'une zone ramenée sur la carte du continent.
-- rect = { gauche, droite, haut, bas } (C_Map.GetMapRectOnMap).
function ns.versContinent(x, y, rect)
  return rect[1] + x * (rect[2] - rect[1]), rect[3] + y * (rect[4] - rect[3])
end

-- Compte par état : { rendu = n, aRendre = n, aTrouver = n, total = n }.
function ns.compter(livres, estRendue, ramasses, avecNiv60)
  local c = { rendu = 0, aRendre = 0, aTrouver = 0, total = 0 }
  for _, l in ipairs(livres) do
    if avecNiv60 or not l.niv60 then
      local e = ns.etat(l, estRendue, ramasses)
      c[e] = c[e] + 1
      c.total = c.total + 1
    end
  end
  return c
end

-- ---------------------------------------------------------------------------
-- État dans le jeu
-- ---------------------------------------------------------------------------

local function estRendue(quete)
  if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then return C_QuestLog.IsQuestFlaggedCompleted(quete) end
  return IsQuestFlaggedCompleted and IsQuestFlaggedCompleted(quete) or false
end

local function etat(livre) return ns.etat(livre, estRendue, perso.ramasses) end

local function faction() return UnitFactionGroup("player") == "Horde" and "Horde" or "Alliance" end

local function nomCarte(carte)
  local info = C_Map.GetMapInfo(carte)
  return info and info.name or ("carte " .. carte)
end

local rafraichirTout -- défini plus bas : carte et panneau

-- Un livre trouvé dans tes sacs passe « à rendre ». Sauf si tu l'as remis
-- « à trouver » à la main (perso.ignores) : on respecte ton choix.
local function noterObjet(nomObjet)
  if not nomObjet then return false end
  local o = ns.simplifier(nomObjet)
  for _, l in ipairs(ns.LIVRES) do
    if not perso.ramasses[l.quete] and not perso.ignores[l.quete] and not estRendue(l.quete)
      and ns.estCeLivre(o, l) then
      perso.ramasses[l.quete] = true
      ns.reglages.dire("livre ramassé : |cffffd200" .. l.nom .. "|r. Il quitte la carte, il reste à le rendre.")
      return true
    end
  end
  return false
end

local function nbCases(sac)
  if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(sac) end
  return GetContainerNumSlots and GetContainerNumSlots(sac) or 0
end

local function lienCase(sac, case)
  if C_Container and C_Container.GetContainerItemLink then return C_Container.GetContainerItemLink(sac, case) end
  return GetContainerItemLink and GetContainerItemLink(sac, case)
end

local function lireSacs()
  local change = false
  local dernier = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
  for sac = 0, dernier do
    for case = 1, nbCases(sac) do
      local lien = lienCase(sac, case)
      local nom = lien and lien:match("%[(.-)%]")
      if nom and noterObjet(nom) then change = true end
    end
  end
  if change then rafraichirTout() end
end

-- ---------------------------------------------------------------------------
-- Balise : TomTom s'il est là, sinon la balise du jeu.
-- ---------------------------------------------------------------------------

local function baliser(carte, x, y, titre)
  if TomTom and TomTom.AddWaypoint then
    TomTom:AddWaypoint(carte, x, y, { title = titre, from = "Livres de bibliothèque", persistent = false })
  elseif C_Map.SetUserWaypoint and UiMapPoint
    and (not C_Map.CanSetUserWaypointOnMap or C_Map.CanSetUserWaypointOnMap(carte)) then
    pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(carte, x, y))
    if C_Map.HasUserWaypoint and not C_Map.HasUserWaypoint() then
      return ns.reglages.dire("balise refusée par le jeu : " .. titre .. ", " .. nomCarte(carte)
        .. string.format(" %.1f, %.1f", x * 100, y * 100))
    end
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
      C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    end
  else
    return ns.reglages.dire("pas de balise possible ici : " .. titre .. ", " .. nomCarte(carte)
      .. string.format(" %.1f, %.1f", x * 100, y * 100))
  end
  ns.reglages.dire(string.format("balise posée : %s (%s %.1f, %.1f).", titre, nomCarte(carte), x * 100, y * 100))
end

-- ---------------------------------------------------------------------------
-- Épingles sur la carte du monde
-- ---------------------------------------------------------------------------

local ICONE_LIVRE = "Interface\\Icons\\INV_Misc_Book_09"
local ICONE_PNJ = "Interface\\GossipFrame\\ActiveQuestIcon"
local epingles = {} -- réserve d'épingles, réutilisées d'une carte à l'autre

local function infobulle(self)
  local e = self.donnees
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  if e.pnj then
    GameTooltip:AddLine(e.pnj.nom, 1, 0.82, 0)
    GameTooltip:AddLine(e.texte, 1, 1, 1, true)
  else
    local l = e.livre
    GameTooltip:AddLine(l.nom, 1, 0.82, 0, true)
    if l.niv60 then GameTooltip:AddLine("Livre « niveau 60 »", 0.6, 0.8, 1) end
    GameTooltip:AddLine(e.aide or l.aide, 1, 1, 1, true)
    local et = etat(l)
    GameTooltip:AddLine(et == "aRendre" and "|cff66bbffRamassé : à rendre|r" or "|cffffa040À trouver|r")
    GameTooltip:AddLine("Clic gauche : balise     Clic droit : marquer ramassé ou pas", 0.6, 0.6, 0.6)
  end
  GameTooltip:Show()
end

local function clic(self, bouton)
  local e = self.donnees
  if bouton == "RightButton" and e.livre then
    local q = e.livre.quete
    perso.ramasses[q] = not perso.ramasses[q] or nil
    -- Remis « à trouver » à la main : la lecture des sacs ne le remarquera plus.
    perso.ignores[q] = not perso.ramasses[q] or nil
    ns.reglages.dire(e.livre.nom .. (perso.ramasses[q] and " : marqué ramassé." or " : de nouveau à trouver."))
    rafraichirTout()
    GameTooltip:Hide()
  else
    baliser(e.carte, e.x, e.y, e.pnj and e.pnj.nom or e.livre.nom)
  end
end

local function prendreEpingle(i, parent)
  local p = epingles[i]
  if not p then
    p = CreateFrame("Button", nil, parent)
    p:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    p.image = p:CreateTexture(nil, "ARTWORK")
    p.image:SetAllPoints()
    p:SetScript("OnEnter", infobulle)
    p:SetScript("OnLeave", function() GameTooltip:Hide() end)
    p:SetScript("OnClick", clic)
    epingles[i] = p
  end
  p:SetParent(parent)
  return p
end

-- Ce qu'il faut épingler sur une carte donnée : liste de { livre ou pnj, carte, x, y, aide }.
local function aEpingler(carte)
  local liste = {}
  local function ajouter(e, carteObjet, x, y)
    if carteObjet == carte then
      e.carte, e.x, e.y, e.ici = carteObjet, x, y, { x, y }
      liste[#liste + 1] = e
    elseif db.continent and (carte == ns.KALIMDOR or carte == ns.ROYAUMES) then
      local ok, g, d, h, b = pcall(C_Map.GetMapRectOnMap, carteObjet, carte)
      if ok and g and d and h and b and d > g and b > h then
        local cx, cy = ns.versContinent(x, y, { g, d, h, b })
        -- Une zone de l'autre continent tomberait hors de la carte : on l'écarte.
        if cx >= 0 and cx <= 1 and cy >= 0 and cy <= 1 then
          e.carte, e.x, e.y, e.ici = carteObjet, x, y, { cx, cy }
          liste[#liste + 1] = e
        end
      end
    end
  end
  local aRendreBase, aRendre60 = 0, 0
  for _, l in ipairs(ns.LIVRES) do
    if db.niv60 or not l.niv60 then
      local et = etat(l)
      if et == "aRendre" then
        if l.niv60 then aRendre60 = aRendre60 + 1 else aRendreBase = aRendreBase + 1 end
      end
      if et == "aTrouver" or (et == "aRendre" and db.aRendre) then
        ajouter({ livre = l, grise = et == "aRendre" }, l.carte, l.x, l.y)
        for _, autre in ipairs(l.autres or {}) do
          ajouter({ livre = l, grise = et == "aRendre", aide = autre.aide }, autre.carte, autre.x, autre.y)
        end
      end
    end
  end
  if db.pnj then
    local pnj = ns.PNJ[faction()]
    if aRendreBase > 0 then
      ajouter({ pnj = pnj.base, texte = "Rends-lui tes livres : " .. aRendreBase .. " sur toi." },
        pnj.base.carte, pnj.base.x, pnj.base.y)
    end
    if aRendre60 > 0 then
      ajouter({ pnj = pnj.niv60, texte = "Rends-lui tes livres « niveau 60 » : " .. aRendre60 .. " sur toi." },
        pnj.niv60.carte, pnj.niv60.x, pnj.niv60.y)
    end
  end
  return liste
end

local function majCarte()
  if not WorldMapFrame or not WorldMapFrame:IsShown() then return end
  local toile = WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child
  local carte = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
  for _, p in ipairs(epingles) do p:Hide() end
  if not toile or not carte or not db or not db.actif then return end
  local largeur, hauteur = toile:GetWidth(), toile:GetHeight()
  if not largeur or largeur <= 0 then return end -- carte pas encore dimensionnée : OnSizeChanged rappellera
  local taille = math.max(12, largeur * 0.022)
  for i, e in ipairs(aEpingler(carte)) do
    local p = prendreEpingle(i, toile)
    p.donnees = e
    p:SetSize(taille, taille)
    p:SetFrameLevel(toile:GetFrameLevel() + 2000)
    p.image:SetTexture(e.pnj and ICONE_PNJ or ICONE_LIVRE)
    if not e.pnj then p.image:SetTexCoord(0.08, 0.92, 0.08, 0.92) else p.image:SetTexCoord(0, 1, 0, 1) end
    p.image:SetDesaturated(e.grise and true or false)
    p:SetAlpha(e.grise and 0.6 or 1)
    p:ClearAllPoints()
    p:SetPoint("CENTER", toile, "TOPLEFT", e.ici[1] * largeur, -e.ici[2] * hauteur)
    p:Show()
  end
end

-- ---------------------------------------------------------------------------
-- Le panneau /livres
-- ---------------------------------------------------------------------------

local panneau = CreateFrame("Frame", "LivresBiblioPanneau", UIParent, "BasicFrameTemplateWithInset")
panneau:SetSize(400, 460)
panneau:SetPoint("LEFT", UIParent, "LEFT", 60, 0)
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
titre:SetText("Livres de bibliothèque")
local resume = panneau:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
resume:SetPoint("TOPLEFT", 16, -32)
resume:SetWidth(370)
resume:SetJustifyH("LEFT")

local defile = CreateFrame("ScrollFrame", nil, panneau, "UIPanelScrollFrameTemplate")
defile:SetPoint("TOPLEFT", 12, -72)
defile:SetPoint("BOTTOMRIGHT", -30, 12)
local contenu = CreateFrame("Frame", nil, defile)
contenu:SetSize(350, 10)
defile:SetScrollChild(contenu)
local lignes = {}

local COULEURS = { rendu = "|cff40ff40", aRendre = "|cff66bbff", aTrouver = "|cffffa040" }
local MOTS = { rendu = "rendu", aRendre = "à rendre", aTrouver = "à trouver" }

local function ligne(i)
  local b = lignes[i]
  if not b then
    b = CreateFrame("Button", nil, contenu)
    b:SetSize(350, 16)
    b:SetPoint("TOPLEFT", 0, -(i - 1) * 16)
    b.texte = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.texte:SetAllPoints()
    b.texte:SetJustifyH("LEFT")
    b.texte:SetWordWrap(false) -- un titre long est coupé (« … »), pas renvoyé sur la ligne suivante
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(self, bouton)
      local l = self.livre
      if not l then return end
      local e = etat(l)
      if bouton == "LeftButton" and e == "rendu" then
        return ns.reglages.dire(l.nom .. " : déjà rendu.")
      elseif bouton == "LeftButton" and e == "aRendre" then
        -- Ramassé : la balise mène au PNJ qui le reprend, pas à l'endroit du livre.
        local pnj = ns.PNJ[faction()][l.niv60 and "niv60" or "base"]
        return baliser(pnj.carte, pnj.x, pnj.y, pnj.nom .. " (rendre " .. l.nom .. ")")
      end
      clic({ donnees = { livre = l, carte = l.carte, x = l.x, y = l.y } }, bouton)
    end)
    b:SetScript("OnEnter", function(self)
      if not self.livre then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(self.livre.nom, 1, 0.82, 0, true)
      GameTooltip:AddLine(self.livre.aide, 1, 1, 1, true)
      GameTooltip:AddLine("Clic gauche : balise     Clic droit : marquer ramassé ou pas", 0.6, 0.6, 0.6)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    lignes[i] = b
  end
  b:Show()
  return b
end

local function majPanneau()
  if not panneau:IsShown() then return end
  local c = ns.compter(ns.LIVRES, estRendue, perso.ramasses, db.niv60)
  local amis = {}
  for _, q in ipairs(ns.QUETES_AMI) do
    amis[#amis + 1] = (estRendue(q.quete) and "|cff40ff40" or "|cff888888") .. q.nom .. "|r"
  end
  resume:SetText(string.format("%s%d rendus|r · %s%d à rendre|r · %s%d à trouver|r  (sur %d)\n%s",
    COULEURS.rendu, c.rendu, COULEURS.aRendre, c.aRendre, COULEURS.aTrouver, c.aTrouver, c.total,
    table.concat(amis, " · ")))
  local n = 0
  local function titreSection(t)
    n = n + 1
    local b = ligne(n)
    b.livre = nil
    b.texte:SetText("|cffffd200" .. t .. "|r")
  end
  local sections = {
    { "Kalimdor", ns.KALIMDOR, false }, { "Royaumes de l'Est", ns.ROYAUMES, false },
    { "Niveau 60", nil, true },
  }
  for _, s in ipairs(sections) do
    if not s[3] or db.niv60 then
      titreSection(s[1])
      for _, l in ipairs(ns.LIVRES) do
        local continent = ns.CARTES_KALIMDOR[l.carte] and ns.KALIMDOR or ns.ROYAUMES
        local garder = (s[3] and l.niv60) or (not s[3] and not l.niv60 and continent == s[2])
        if garder then
          n = n + 1
          local b = ligne(n)
          b.livre = l
          local e = etat(l)
          b.texte:SetText(string.format("  %s%s|r  %s  |cff888888%s|r", COULEURS[e], MOTS[e], l.nom, nomCarte(l.carte)))
        end
      end
    end
  end
  for i = n + 1, #lignes do lignes[i]:Hide() end
  contenu:SetHeight(n * 16 + 10)
end
panneau:SetScript("OnShow", majPanneau)

local function basculerPanneau()
  panneau:SetShown(not panneau:IsShown())
end

rafraichirTout = function()
  majCarte()
  majPanneau()
end

-- Balise vers le livre à trouver le plus proche, sur ta carte (bouton et /livres proche).
baliserLePlusProche = function()
  local r = ns.reglages
  local carte = C_Map.GetBestMapForUnit("player")
  local pos = carte and C_Map.GetPlayerMapPosition(carte, "player")
  if not pos then return r.dire("position inconnue ici.") end
  local px, py = pos:GetXY()
  -- Tous les endroits possibles : celui du livre et ses « autres » (Rumi).
  local meilleur, dMin
  for _, l in ipairs(ns.LIVRES) do
    if etat(l) == "aTrouver" and (db.niv60 or not l.niv60) then
      for _, lieu in ipairs({ l, unpack(l.autres or {}) }) do
        if lieu.carte == carte then
          local d = (lieu.x - px) ^ 2 + (lieu.y - py) ^ 2
          if not dMin or d < dMin then meilleur, dMin = { l = l, lieu = lieu }, d end
        end
      end
    end
  end
  if not meilleur then return r.dire("plus aucun livre à trouver dans cette zone.") end
  baliser(meilleur.lieu.carte, meilleur.lieu.x, meilleur.lieu.y, meilleur.l.nom)
end

-- Vide les livres ramassés et ceux remis à trouver à la main (après confirmation).
local function toutRemettreATrouver()
  if not perso then return end
  for k in pairs(perso.ramasses) do perso.ramasses[k] = nil end
  for k in pairs(perso.ignores) do perso.ignores[k] = nil end
  ns.reglages.dire("tous les livres sont de nouveau à trouver (sauf ceux déjà rendus).")
  rafraichirTout()
end
ns.toutRemettreATrouver = toutRemettreATrouver
if StaticPopupDialogs then
  StaticPopupDialogs["LIVRESBIBLIO_REMETTRE"] = {
    text = "Livres de bibliothèque : remettre tous les livres de ce personnage à trouver ?\nLes livres déjà rendus restent rendus.",
    button1 = YES or "Oui", button2 = NO or "Non",
    OnAccept = toutRemettreATrouver,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
  }
end

-- ---------------------------------------------------------------------------
-- Réglages (Reglages.lua) : le clic dans l'icône commune ouvre le panneau.
-- ---------------------------------------------------------------------------

ns.reglages = ns.creerReglages({
  titre = "Livres de bibliothèque",
  icone = "Interface\\Icons\\INV_Misc_Book_09",
  nomDB = "LivresBiblioDB",
  defauts = DEFAUTS,
  ouvrirHub = basculerPanneau, texteHub = "Liste des livres",
  boutons = {
    { texte = "Balise vers le livre le plus proche", largeur = 210,
      aide = "Pose une balise sur le livre à trouver le plus proche, sur ta carte (comme /livres proche).",
      action = function() baliserLePlusProche() end },
    { texte = "Tout remettre à trouver", largeur = 160,
      aide = "Oublie les livres marqués ramassés et ceux remis à trouver à la main, pour ce personnage. Les livres déjà rendus restent rendus.",
      action = function() StaticPopup_Show("LIVRESBIBLIO_REMETTRE") end },
  },
  options = {
    { titre = "Carte" },
    { cle = "actif", libelle = "Activer Livres de bibliothèque",
      aide = "Coupé : plus aucun livre ni PNJ épinglé sur la carte. La liste, /livres proche et le suivi des livres ramassés continuent." },
    { cle = "continent", libelle = "Aussi sur les cartes des continents",
      aide = "Kalimdor et les Royaumes de l'Est, pour voir d'un coup d'œil où il en reste." },
    { cle = "niv60", libelle = "Livres « niveau 60 »", toujours = true,
      aide = "Huit livres de haut niveau, rendus à un autre PNJ. Agit sur la carte, la liste et /livres proche." },
    { cle = "pnj", libelle = "Épingler le PNJ à qui rendre tes livres",
      aide = "Seulement quand tu as des livres ramassés pas encore rendus." },
    { cle = "aRendre", libelle = "Garder en grisé les livres ramassés pas encore rendus",
      aide = "Coupé : ils disparaissent de la carte dès que tu les ramasses." },
    { titre = "Affichage" },
    { cle = "minimap", libelle = "Icône à part autour de la minimap",
      aide = "En plus de l'icône commune des addons de Valentin. Clic droit : activer ou couper." },
  },
  astuce = "La liste des livres : /livres, le bouton en haut ou Maj+clic dans l'icône commune. Sur la carte : clic gauche = balise, clic droit = ramassé ou pas.",
  auChargement = function(d)
    db = d
    LivresBiblioPerso = LivresBiblioPerso or {}
    perso = LivresBiblioPerso
    perso.ramasses = perso.ramasses or {}
    perso.ignores = perso.ignores or {} -- remis « à trouver » à la main
  end,
  surChangement = function() if perso then rafraichirTout() end end,
})

-- ---------------------------------------------------------------------------
-- Événements et commande /livres
-- ---------------------------------------------------------------------------

-- S'accrocher à la carte du monde : changement de carte, ouverture, et
-- changement de taille (carte agrandie ou réduite). La carte peut être chargée
-- après l'addon : on réessaie à l'entrée dans le monde et quand elle arrive.
-- Chaque accroche est protégée : si le jeu n'a pas la fonction, l'addon
-- continue sans elle au lieu de s'arrêter.
local accroche = false
local function accrocherCarte()
  if accroche or type(WorldMapFrame) ~= "table" then return end
  accroche = true
  local function maj() if perso then majCarte() end end
  if type(WorldMapFrame.OnMapChanged) == "function" then pcall(hooksecurefunc, WorldMapFrame, "OnMapChanged", maj) end
  pcall(WorldMapFrame.HookScript, WorldMapFrame, "OnShow", maj)
  local toile = WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child
  if toile then pcall(toile.HookScript, toile, "OnSizeChanged", maj) end
end
accrocherCarte()

local ecouteur = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "QUEST_TURNED_IN", "ADDON_LOADED" }) do
  ecouteur:RegisterEvent(e)
end
ecouteur:SetScript("OnEvent", function(_, evenement, arg1)
  if evenement == "ADDON_LOADED" then
    if arg1 == "Blizzard_WorldMap" then accrocherCarte() end
    return
  end
  if not perso then return end
  if evenement == "PLAYER_ENTERING_WORLD" then accrocherCarte() end
  if evenement == "QUEST_TURNED_IN" then
    -- Livre rendu : le compte et l'épingle du PNJ changent, un peu après.
    C_Timer.After(1, rafraichirTout)
  else
    lireSacs()
  end
end)

SLASH_LIVRESBIBLIO1 = "/livres"
SLASH_LIVRESBIBLIO2 = "/livresbiblio"
SlashCmdList.LIVRESBIBLIO = function(message)
  local cmd = strtrim(message or ""):lower()
  local r = ns.reglages
  if cmd == "" then
    basculerPanneau()
  elseif cmd == "options" or cmd == "reglages" then
    r.ouvrir()
  elseif cmd == "proche" then
    baliserLePlusProche()
  elseif not r.basculerOption(cmd) then
    r.dire("/livres : le panneau     /livres proche : balise vers le livre le plus proche     /livres options")
  end
end
