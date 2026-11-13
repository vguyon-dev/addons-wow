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
  -- l'hôtel des ventes) et impossible pour toujours (classe, race, type d'armure
  -- que ta classe ne portera jamais) -> à vendre ; sinon (niveau, arme ou armure
  -- qui peut s'apprendre) il se garde, se donne, se vend aux enchères ou se portera plus tard.
  if c == "equip" and utilisable == false then
    if extra.estLie and extra.raison == "definitif" then return "vendre" end
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
    return "lié, et tu ne pourras jamais le porter" .. (texte and (" (" .. texte .. ")") or "")
  end
  if categorie == "pasPourToi" then
    return (texte or "tu ne peux pas le porter")
      .. (estLie and " ; lié : tu pourras peut-être le porter plus tard" or " ; pas lié : tu peux le donner ou le vendre aux enchères")
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
-- Marchand auto peut vendre en plus des gris. Rend { sac, case, lien, id, raison, qualite, remboursable }.
function ns.filtrerAVendre(objets)
  local l = {}
  for _, o in ipairs(objets or {}) do
    if o.categorie == "vendre" and o.qualite ~= 0 and o.sac and o.case and o.lien then
      l[#l + 1] = { sac = o.sac, case = o.case, lien = o.lien, id = o.id, raison = o.raison, qualite = o.qualite,
        remboursable = o.remboursable }
    end
  end
  return l
end

local TAILLE, ECART, MARGE = 37, 4, 12

-- La hauteur de la fenêtre pour ce plan : { aEquiper = nombre de lignes « À équiper »,
-- sections = { nombre d'objets de chaque section }, libre = vrai s'il y a une case libre à montrer }.
-- Même calcul que la fenêtre dessinée (titre de 16, une rangée = TAILLE + ECART, 6 d'espace).
function ns.hauteurVue(plan, colonnes)
  plan = type(plan) == "table" and plan or {}
  colonnes = math.max(1, colonnes or 10)
  local y = 0
  local equiper = plan.aEquiper or 0
  if equiper > 0 then y = y + 16 + equiper * (TAILLE + ECART + 4) + 6 end
  for _, n in ipairs(plan.sections or {}) do
    if type(n) == "table" then
      -- Une section découpée en groupes (les composants par extension) : un sous-titre de 14 par groupe.
      local h = 0
      for _, k in ipairs(n) do
        if k > 0 then h = h + 14 + math.ceil(k / colonnes) * (TAILLE + ECART) end
      end
      if h > 0 then y = y + 16 + h + 6 end
    elseif n > 0 then
      y = y + 16 + math.ceil(n / colonnes) * (TAILLE + ECART) + 6
    end
  end
  if plan.libre then y = y + 16 + TAILLE + ECART end
  return 58 + y + 30
end

-- Combien de colonnes de cases selon le nombre de cases du sac ou de la banque.
-- Avec plan (voir ns.hauteurVue) et hauteurMax (en pixels), on ajoute des colonnes, jusqu'à 24,
-- tant que la fenêtre dépasse cette hauteur.
function ns.colonnesPour(total, plan, hauteurMax)
  total = total or 0
  local base = total > 110 and 14 or (total > 70 and 12 or 10)
  if type(plan) ~= "table" or type(hauteurMax) ~= "number" or hauteurMax <= 0 then return base end
  for colonnes = base, 24 do
    if ns.hauteurVue(plan, colonnes) <= hauteurMax then return colonnes end
  end
  return 24
end

-- Sépare les objets lus : ceux « À équiper » (qui portent un conseil, triés par
-- nom) et les autres. Sans conseils (la banque), tout va dans les autres.
function ns.separerConseils(objets, avecConseils)
  local aEquiper, autres = {}, {}
  for _, o in ipairs(objets or {}) do
    if avecConseils and o.conseil then aEquiper[#aEquiper + 1] = o else autres[#autres + 1] = o end
  end
  table.sort(aEquiper, function(a, b) return (a.nom or "") < (b.nom or "") end)
  return aEquiper, autres
end

-- Les numéros de sacs de la banque, dans l'ordre d'affichage. faits :
--  onglets = numéros des onglets de banque du personnage (Retail récent), s'il y en a ;
--  banque = numéro de la banque elle-même, premierSac et nbSacs = les sacs de banque
--  achetés (Forever, Retail ancien). Les onglets l'emportent quand le jeu en donne.
function ns.sacsBanque(faits)
  faits = faits or {}
  local l = {}
  if type(faits.onglets) == "table" and #faits.onglets > 0 then
    for _, id in ipairs(faits.onglets) do l[#l + 1] = id end
    return l
  end
  if faits.banque then l[#l + 1] = faits.banque end
  for i = 1, faits.nbSacs or 0 do l[#l + 1] = (faits.premierSac or 5) + i - 1 end
  return l
end

-- La banque rangée se montre-t-elle ? Il faut la vue par catégories, l'option,
-- la banque ouverte, et au moins une case lisible : si le jeu ne dit rien de la
-- banque (nbCases = 0), on laisse la banque du jeu toute seule.
-- Fermée à la main (la croix) : elle reste fermée jusqu'à la prochaine ouverture de la banque.
function ns.banqueAMontrer(faits)
  faits = faits or {}
  return (faits.vue and faits.option and faits.ouverte and not faits.fermeeMain and (faits.nbCases or 0) > 0) and true or false
end

-- ---------------------------------------------------------------------------
-- Les composants par extension (Retail) : le jeu donne à chaque objet le numéro
-- de son extension (0 = Classique … 11 = Midnight).
-- ---------------------------------------------------------------------------

ns.EXTENSIONS = { [0] = "Classique", "The Burning Crusade", "Wrath of the Lich King", "Cataclysm",
  "Mists of Pandaria", "Warlords of Draenor", "Legion", "Battle for Azeroth", "Shadowlands",
  "Dragonflight", "The War Within", "Midnight" }

function ns.nomExtension(e)
  return ns.EXTENSIONS[e] or ("Extension " .. tostring(e))
end

-- « Ancienne » : ni l'extension en cours ni celle d'avant (on y joue encore souvent).
function ns.estAncienne(e, actuelle)
  return (e or 0) <= (actuelle or 0) - 2
end

-- Découpe une liste d'objets déjà triée en groupes { cle, nom, objets, ancienne },
-- l'extension la plus récente d'abord. regrouper : toutes les anciennes en un seul
-- groupe (cle = "anciennes"). Rend nil quand le jeu n'a pas d'extension (Forever) :
-- la section se dessine alors d'un bloc, comme avant.
function ns.grouperExtensions(liste, actuelle, regrouper)
  actuelle = tonumber(actuelle) or 0
  if actuelle <= 0 then return nil end
  local parCle, cles = {}, {}
  for _, o in ipairs(liste or {}) do
    local e = tonumber(o.extension) or 0
    local ancienne = ns.estAncienne(e, actuelle)
    local cle = (regrouper and ancienne) and "anciennes" or e
    if not parCle[cle] then
      parCle[cle] = { cle = cle, nom = cle == "anciennes" and "Anciennes extensions" or ns.nomExtension(e),
        objets = {}, ancienne = ancienne, rang = cle == "anciennes" and -1 or e }
      cles[#cles + 1] = parCle[cle]
    end
    local g = parCle[cle]
    g.objets[#g.objets + 1] = o
  end
  table.sort(cles, function(a, b) return a.rang > b.rang end)
  if parCle.anciennes then ns.trierParExtension(parCle.anciennes.objets) end
  return cles
end

-- Dans le groupe « Anciennes extensions », les objets se suivent par extension
-- (la plus récente d'abord), l'ordre d'arrivée (qualité puis nom) gardé à l'intérieur.
function ns.trierParExtension(objets)
  local rangs = {}
  for i, o in ipairs(objets) do rangs[o] = i end
  table.sort(objets, function(a, b)
    local ea, eb = tonumber(a.extension) or 0, tonumber(b.extension) or 0
    if ea ~= eb then return ea > eb end
    return rangs[a] < rangs[b]
  end)
  return objets
end

-- Les composants du sac à envoyer en banque : ceux dont l'extension est cochée.
-- choix[e] = vrai ou faux quand le joueur a tranché ; sinon, cochée si « ancienne ».
-- Un objet verrouillé (déjà en main, en cours d'échange) est laissé.
function ns.aDeposer(objets, choix, actuelle)
  local l = {}
  choix = choix or {}
  for _, o in ipairs(objets or {}) do
    if o.categorie == "compo" and not o.verrou then
      local e = tonumber(o.extension) or 0
      local coche = choix[e]
      if coche == nil then coche = ns.estAncienne(e, actuelle) end
      if coche then l[#l + 1] = { sac = o.sac, case = o.case, id = o.id, extension = e } end
    end
  end
  return l
end

-- La phrase de fin d'un dépôt en banque.
function ns.bilanDepot(faits, destination, lies, laisses, raison)
  faits, lies, laisses = faits or 0, lies or 0, laisses or 0
  local function s(n) return n > 1 and "s" or "" end
  local texte = faits .. " pile" .. s(faits) .. " de composants déposée" .. s(faits) .. " en banque (" .. (destination or "?") .. ")"
  if lies > 0 then texte = texte .. ", " .. lies .. " liée" .. s(lies) .. " au personnage laissée" .. s(lies) end
  if laisses > 0 then texte = texte .. ", " .. laisses .. " laissée" .. s(laisses) .. " (verrouillée ou déplacée)" end
  return texte .. (raison and (". Arrêt : " .. raison) or "") .. "."
end

-- Combien de composants du sac par extension : { [e] = nombre de piles }, et la liste
-- des extensions présentes, la plus récente d'abord.
function ns.compterExtensions(objets)
  local parExt, liste = {}, {}
  for _, o in ipairs(objets or {}) do
    if o.categorie == "compo" then
      local e = tonumber(o.extension) or 0
      if not parExt[e] then parExt[e] = 0; liste[#liste + 1] = e end
      parExt[e] = parExt[e] + 1
    end
  end
  table.sort(liste, function(a, b) return a > b end)
  return parExt, liste
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
    return i.iconFileID, i.stackCount, i.isLocked, i.quality, i.hyperlink, i.itemID, i.isBound, i.isRefundable
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
-- Les fenêtres : le sac et la banque sont deux fenêtres du même genre
-- (creerVue), avec leurs propres cases et titres.
-- ---------------------------------------------------------------------------

-- nom : nom global de la fenêtre ; prefixe : début du nom de ses cases ;
-- options.deplacable : la fenêtre se déplace à la souris et retient sa place.
local function creerVue(nom, prefixe, nomRecherche, options)
  options = options or {}
  local v = { prefixe = prefixe, cases = {}, cadresSac = {}, titres = {}, lignesConseil = {}, colonnes = 10 }
  local fenetre = CreateFrame("Frame", nom, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  v.fenetre = fenetre
  fenetre:SetSize(MARGE * 2 + v.colonnes * (TAILLE + ECART), 300)
  fenetre:SetFrameStrata("MEDIUM")
  fenetre:SetToplevel(true)
  fenetre:SetClampedToScreen(true)
  fenetre:EnableMouse(true)
  if options.deplacable then
    fenetre:SetMovable(true)
    fenetre:RegisterForDrag("LeftButton")
    fenetre:SetScript("OnDragStart", fenetre.StartMoving)
    fenetre:SetScript("OnDragStop", function(self)
      self:StopMovingOrSizing()
      if ns.db then
        local p, _, rp, x, y = self:GetPoint()
        ns.db.positionSac = { p, rp, x, y }
      end
    end)
    -- Ctrl + molette : la taille de la fenêtre (de 50 à 150 %), gardée dans ns.db.echelleSac.
    -- Jamais en combat : la fenêtre contient les vraies cases du sac, que le jeu protège.
    fenetre:EnableMouseWheel(true)
    fenetre:SetScript("OnMouseWheel", function(self, sens)
      if not (IsControlKeyDown and IsControlKeyDown()) then return end
      if InCombatLockdown() then
        if ns.reglages and ns.reglages.dire then ns.reglages.dire("la taille du sac se change hors combat.") end
        return
      end
      local actuelle = self:GetScale() or 1
      local nouvelle = math.floor((actuelle + (sens > 0 and 0.05 or -0.05)) * 20 + 0.5) / 20
      if nouvelle < 0.5 then nouvelle = 0.5 elseif nouvelle > 1.5 then nouvelle = 1.5 end
      -- Garder le coin haut gauche à sa place pendant le changement de taille.
      local gauche, haut = self:GetLeft(), self:GetTop()
      self:SetScale(nouvelle)
      if gauche and haut then
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", gauche * actuelle / nouvelle, haut * actuelle / nouvelle)
        if ns.db then
          local p, _, rp, x, y = self:GetPoint()
          ns.db.positionSac = { p, rp, x, y }
        end
      end
      if ns.db then ns.db.echelleSac = nouvelle end
    end)
  end
  fenetre:Hide()

  -- Apparence « cadre du jeu » : le modèle de fenêtre habituel, posé derrière.
  local cadreWow = CreateFrame("Frame", nil, fenetre, "BasicFrameTemplateWithInset")
  cadreWow:SetAllPoints()
  cadreWow:SetFrameLevel(fenetre:GetFrameLevel())
  if cadreWow.CloseButton then cadreWow.CloseButton:SetScript("OnClick", function() v.fermeeMain = true; fenetre:Hide() end) end

  -- Nouveau visuel : fond sombre, bordure dorée, titre or.
  local fermer = CreateFrame("Button", nil, fenetre, "UIPanelCloseButton")
  fermer:SetPoint("TOPRIGHT", 2, 2)
  fermer:SetScript("OnClick", function() v.fermeeMain = true; fenetre:Hide() end)

  local titre = fenetre:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  v.titre = titre
  function v.appliquerApparence()
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

  local okRecherche, recherche = pcall(CreateFrame, "EditBox", nomRecherche, fenetre, "SearchBoxTemplate")
  if not okRecherche then recherche = CreateFrame("EditBox", nomRecherche, fenetre, "InputBoxTemplate") end
  recherche:SetHeight(20)
  recherche:SetAutoFocus(false)
  v.recherche = recherche

  -- Le contenu : un cadre par sac (son numéro sert aux cases du jeu), et les titres.
  local contenu = CreateFrame("Frame", nil, fenetre)
  contenu:SetPoint("TOPLEFT", MARGE, -58)
  contenu:SetPoint("RIGHT", -MARGE, 0)
  contenu:SetHeight(10)
  v.contenu = contenu

  v.pied = fenetre:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  v.pied:SetPoint("BOTTOMLEFT", MARGE, 10)
  v.argent = fenetre:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  v.argent:SetPoint("BOTTOMRIGHT", -MARGE, 10)
  return v
end

local sac = creerVue("SacsRangesSac", "SacsRangesCase", "SacsRangesRecherche", { deplacable = true })
local fenetre, recherche = sac.fenetre, sac.recherche
fenetre:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -90, 110)
tinsert(UISpecialFrames, "SacsRangesSac") -- Échap la ferme

-- La banque : une seconde fenêtre, à gauche du sac. La fenêtre de banque du jeu
-- n'est JAMAIS cachée ni touchée : on ne fait que montrer son contenu rangé.
local banque = creerVue("SacsRangesBanque", "SacsRangesBanque", "SacsRangesBanqueRecherche")
banque.fenetre:SetPoint("BOTTOMRIGHT", fenetre, "BOTTOMLEFT", -8, 0)

-- La barre du sac : Ranger, Analyse, recherche.
local function bouton(texte, largeur, aide, action, parent)
  local b = CreateFrame("Button", nil, parent or fenetre, "UIPanelButtonTemplate")
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
recherche:SetPoint("LEFT", bAnalyse, "RIGHT", 12, 0)
recherche:SetPoint("RIGHT", fenetre, "RIGHT", -MARGE, 0)

banque.recherche:SetPoint("TOPLEFT", MARGE, -30)
banque.recherche:SetPoint("RIGHT", banque.fenetre, "RIGHT", -MARGE, 0)

local function cadreDuSac(v, numero)
  if not v.cadresSac[numero] then
    local f = CreateFrame("Frame", nil, v.contenu)
    f:SetID(numero)
    f:SetAllPoints()
    -- Ce que le code des cases du jeu peut demander à leur parent (Retail).
    f.GetBagID = function() return numero end
    f.IsCombinedBagContainer = function() return false end
    f.IsBankBag = function() return false end
    v.cadresSac[numero] = f
  end
  return v.cadresSac[numero]
end

-- Une case du jeu, créée une fois pour toutes pour (sac, case) de cette fenêtre.
local function caseDe(v, numero, case)
  local cle = numero * 1000 + case
  local b = v.cases[cle]
  if b then return b end
  if InCombatLockdown() then return nil end
  local parent = cadreDuSac(v, numero)
  local nom = v.prefixe .. numero .. "_" .. case
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
  if b.SetBagID then pcall(b.SetBagID, b, numero) end
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
  v.cases[cle] = b
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

local function titreDe(v, i)
  if not v.titres[i] then
    local t = v.contenu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    t:SetJustifyH("LEFT")
    v.titres[i] = t
  end
  return v.titres[i]
end

-- La lueur « nouvel objet » du jeu (bleue ou de la couleur de la qualité). Dans ses sacs, le jeu
-- la règle lui-même à chaque affichage ; dans notre fenêtre personne ne le faisait, et après un
-- /reload toutes les cases restaient allumées jusqu'au survol. On l'éteint, sauf si le jeu dit
-- que l'objet vient vraiment d'arriver dans le sac.
local function reglerLueur(b)
  local nouveau = false
  if C_NewItems and C_NewItems.IsNewItem then
    local parent = b:GetParent()
    local ok, r = pcall(C_NewItems.IsNewItem, parent and parent:GetID() or 0, b:GetID())
    nouveau = ok and r == true
  end
  local nom = b.GetName and b:GetName()
  local paye = b.BattlepayItemTexture or (nom and _G[nom .. "BattlepayItemTexture"])
  if paye and paye.Hide then paye:Hide() end
  local lueur = b.NewItemTexture or (nom and _G[nom .. "NewItemTexture"])
  if lueur and lueur.Hide and not nouveau then
    lueur:Hide()
    for _, cle in ipairs({ "flashAnim", "newitemglowAnim" }) do
      local anim = b[cle]
      if anim and anim.Stop then pcall(anim.Stop, anim) end
    end
  end
end
ns.reglerLueur = reglerLueur

local function remplir(b, icone, nombre, verrou, qualite, lien)
  reglerLueur(b)
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
local function ligneConseil(v, i)
  if not v.lignesConseil[i] then
    local nom = v.contenu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nom:SetJustifyH("LEFT")
    local raison = v.contenu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    raison:SetJustifyH("LEFT")
    raison:SetTextColor(0.12, 1, 0)
    local remplace = v.contenu:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    remplace:SetJustifyH("LEFT")
    v.lignesConseil[i] = { nom = nom, raison = raison, remplace = remplace }
  end
  return v.lignesConseil[i]
end

-- ---------------------------------------------------------------------------
-- Les sacs lus : ceux du personnage, ceux de la banque
-- ---------------------------------------------------------------------------

local function sacsPersonnage()
  local l = {}
  for numero = 0, derniersSac() do l[#l + 1] = numero end
  return l
end

-- Les sacs de la banque, d'après ce que le jeu sait répondre : les onglets de
-- banque du personnage (Retail récent, C_Bank), sinon la banque et ses sacs
-- (Forever, Retail ancien). La banque de bataillon (partagée entre les
-- personnages du compte, Retail) a ses propres onglets : sacsBataillon.
local function ongletsDe(genre)
  if C_Bank and C_Bank.FetchPurchasedBankTabIDs and Enum and Enum.BankType and Enum.BankType[genre] then
    local ok, ids = pcall(C_Bank.FetchPurchasedBankTabIDs, Enum.BankType[genre])
    if ok and type(ids) == "table" then return ids end
  end
end

-- Le jeu laisse-t-il voir cette banque ici ? (La banque de bataillon ouverte à
-- distance ne montre pas celle du personnage.) Sans réponse du jeu : oui.
local function banqueVisible(genre)
  if C_Bank and C_Bank.CanViewBank and Enum and Enum.BankType and Enum.BankType[genre] then
    local ok, r = pcall(C_Bank.CanViewBank, Enum.BankType[genre])
    if ok then return r and true or false end
  end
  return true
end

local function sacsBataillon()
  if not banqueVisible("Account") then return {} end
  return ongletsDe("Account") or {}
end

local function sacsBanqueJeu()
  local onglets = ongletsDe("Character")
  local banqueId = (Enum and Enum.BagIndex and Enum.BagIndex.Bank) or BANK_CONTAINER or -1
  return ns.sacsBanque({
    onglets = onglets, banque = banqueId, premierSac = derniersSac() + 1, nbSacs = NUM_BANKBAGSLOTS or 0,
  })
end

local function lire(sacs, sansConseils)
  local objets, libres, total, premiereLibre = {}, 0, 0, nil
  -- Les sacs spéciaux (carquois, sacs de métier) : leurs cases vides ne sont pas des cases libres pour tout.
  local speciaux = {}
  for _, numero in ipairs(sacs) do
    local n = ns.nbCases and ns.nbCases(numero) or 0
    local special = ns.familleSac and ns.familleSac(numero) ~= 0 and { sac = numero, libres = 0 } or nil
    if special then speciaux[#speciaux + 1] = special end
    for case = 1, n do
      if not special then total = total + 1 end
      local icone, nombre, verrou, qualite, lien, idObjet, estLie, remboursable = infoCase(numero, case)
      if icone and lien then
        local nom, _, q, _, _, _, _, _, _, _, _, classe, sousClasse, liaison, extension, _, artisanat = infoObjet(lien)
        qualite = qualite or q or 1
        local utilisable, raison, texteRaison = true, nil, nil
        if (classe == 2 or classe == 4) and ns.utilisableCase then
          utilisable, raison, texteRaison = ns.utilisableCase(numero, case, lien)
        end
        local estLivre = LivresBiblio_EstUnLivre and nom and LivresBiblio_EstUnLivre(nom) or false
        local categorie = ns.categorie(classe, qualite, infoQuete(numero, case), utilisable, sousClasse, idObjet,
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
          sac = numero, case = case, id = idObjet, icone = icone, nombre = nombre, verrou = verrou, qualite = qualite,
          lien = lien, nom = nom or lien, categorie = categorie, conseil = conseil, moins = moins, remboursable = remboursable,
          extension = extension,
          raison = ns.texteRangement(categorie, qualite, estLie, texteRaison),
        }
      elseif special then
        special.libres = special.libres + 1
        special.case = special.case or case
      else
        libres = libres + 1
        premiereLibre = premiereLibre or { sac = numero, case = case }
      end
    end
  end
  for _, s in ipairs(speciaux) do
    local nom = C_Container and C_Container.GetBagName and C_Container.GetBagName(s.sac)
    s.nom = type(nom) == "string" and nom ~= "" and nom or "un sac spécial"
  end
  return objets, libres, total, premiereLibre, speciaux
end

-- ---------------------------------------------------------------------------
-- Mise à jour
-- ---------------------------------------------------------------------------

local aRefaire = false -- une réorganisation attend la fin du combat

-- Le numéro de l'extension en cours (11 = Midnight). Toujours 0 hors Retail
-- (Forever, interface 16001) : pas d'extensions, rien ne change, pas de bouton « Déposer ».
local SUR_RETAIL = GetBuildInfo ~= nil and (tonumber((select(4, GetBuildInfo()))) or 0) >= 100000
local function extensionActuelle()
  if not SUR_RETAIL then return 0 end
  local n = LE_EXPANSION_LEVEL_CURRENT
  if n == nil and GetExpansionLevel then n = GetExpansionLevel() end
  return tonumber(n) or 0
end
ns.extensionActuelle = extensionActuelle

-- Les groupes par extension de la section Composants, ou nil (option décochée, Forever).
local function groupesCompo(liste)
  local db = ns.db or {}
  if db.compoExtension == false or #liste == 0 then return nil end
  return ns.grouperExtensions(liste, extensionActuelle(), db.compoRegrouper)
end

-- Pour les autres addons (Marchand auto) : les objets non gris de la section
-- « À vendre », sans avoir besoin de la fenêtre (marche même si la vue par
-- catégories est décochée). Rien en combat, ni si Sacs rangés est coupé.
function SacsRanges_AVendre()
  if InCombatLockdown() or not (ns.db and ns.db.actif) then return {} end
  local ok, objets = pcall(lire, sacsPersonnage(), true)
  if not ok then return {} end
  return ns.filtrerAVendre(objets)
end

-- Dessine une fenêtre : les sections, les cases, le pied. Le sac garde les
-- conseils « À équiper » ; la banque n'en a pas (le clic droit y envoie l'objet
-- dans les sacs, il ne l'équipe pas).
local function dessiner(v, sacs, avecConseils, titreTexte, avecArgent)
  if not v.fenetre:IsShown() then return end
  if InCombatLockdown() then aRefaire = true end
  local db = ns.db or {}
  local objets, libres, total, premiereLibre, speciaux = lire(sacs, not avecConseils)
  -- Les objets à équiper sortent de leur section et passent en tête, une ligne chacun.
  local aEquiper, autres = ns.separerConseils(objets, avecConseils)
  local parSection = ns.repartir(autres)
  -- La banque ne dépasse pas 80 % de la hauteur de l'écran : au besoin, plus de colonnes.
  local plan, hauteurMax
  if not avecConseils and UIParent and UIParent.GetHeight then
    plan = { aEquiper = #aEquiper, sections = {}, libre = premiereLibre and true or false }
    for _, s in ipairs(ns.SECTIONS) do
      local groupes = s.id == "compo" and groupesCompo(parSection[s.id])
      if groupes then
        local n = {}
        for _, g in ipairs(groupes) do n[#n + 1] = #g.objets end
        plan.sections[#plan.sections + 1] = n
      else
        plan.sections[#plan.sections + 1] = #parSection[s.id]
      end
    end
    hauteurMax = (UIParent:GetHeight() or 0) * 0.8
  end
  v.colonnes = ns.colonnesPour(total, plan, hauteurMax)
  local colonnes = v.colonnes
  local largeur = colonnes * (TAILLE + ECART) - ECART
  if not InCombatLockdown() then v.fenetre:SetWidth(MARGE * 2 + largeur) end

  local cases, contenu = v.cases, v.contenu
  for _, b in pairs(cases) do b.utilisee = false end
  local filtre = ns.simplifier(v.recherche:GetText() or "")
  local function visible(o) return filtre == "" or ns.simplifier(o.nom):find(filtre, 1, true) end

  local y, it = 0, 0

  if #aEquiper > 0 then
    it = it + 1
    local t = titreDe(v, it)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -y)
    t:SetText("À équiper  |cff888888" .. #aEquiper .. "|r")
    t:SetTextColor(0.12, 1, 0)
    t:Show()
    y = y + 16
  end
  for i, o in ipairs(aEquiper) do
    local b = caseDe(v, o.sac, o.case)
    local l = ligneConseil(v, i)
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
  for i = #aEquiper + 1, #v.lignesConseil do
    local l = v.lignesConseil[i]
    l.nom:Hide(); l.raison:Hide(); l.remplace:Hide()
  end
  if #aEquiper > 0 then y = y + 6 end

  for _, s in ipairs(ns.SECTIONS) do
    local liste = parSection[s.id]
    if #liste > 0 then
      it = it + 1
      local t = titreDe(v, it)
      t:ClearAllPoints()
      t:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -y)
      t:SetText(s.nom .. "  |cff888888" .. #liste .. "|r")
      t:SetTextColor(s.couleur[1], s.couleur[2], s.couleur[3])
      t:Show()
      y = y + 16
      -- Une grille de cases à partir de y ; avance y de ses rangées.
      local function grille(objetsGrille)
        for i, o in ipairs(objetsGrille) do
          local b = caseDe(v, o.sac, o.case)
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
        y = y + math.ceil(#objetsGrille / colonnes) * (TAILLE + ECART)
      end
      local groupes = s.id == "compo" and groupesCompo(liste)
      if groupes then
        -- Les composants par extension : un sous-titre par extension, la plus récente d'abord.
        for _, g in ipairs(groupes) do
          it = it + 1
          local st = titreDe(v, it)
          st:ClearAllPoints()
          st:SetPoint("TOPLEFT", contenu, "TOPLEFT", 6, -(y + 1))
          st:SetText(g.nom .. "  |cff888888" .. #g.objets .. "|r")
          if g.ancienne then st:SetTextColor(0.62, 0.58, 0.50) else st:SetTextColor(0.92, 0.88, 0.78) end
          st:Show()
          y = y + 14
          grille(g.objets)
        end
      else
        grille(liste)
      end
      y = y + 6
    end
  end

  -- Une seule case vide pour déposer un objet, avec le nombre de cases libres.
  if premiereLibre then
    it = it + 1
    local t = titreDe(v, it)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -y)
    t:SetText("Cases libres  |cff888888" .. libres .. "|r")
    t:SetTextColor(0.6, 0.6, 0.6)
    t:Show()
    y = y + 16
    local b = caseDe(v, premiereLibre.sac, premiereLibre.case)
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
  -- Une case vide par sac spécial qui a de la place : on y dépose ce qui y va (flèches, cuir…).
  for _, s in ipairs(speciaux or {}) do
    if s.libres > 0 and s.case then
      it = it + 1
      local t = titreDe(v, it)
      t:ClearAllPoints()
      t:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -y)
      t:SetText(s.nom .. "  |cff888888" .. s.libres .. "|r")
      t:SetTextColor(0.6, 0.6, 0.6)
      t:Show()
      y = y + 16
      local b = caseDe(v, s.sac, s.case)
      if b then
        b.utilisee = true
        if not InCombatLockdown() then
          b:ClearAllPoints()
          b:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -y)
        end
        remplir(b, nil, 0, false, nil, nil)
        b.libres:SetText(s.libres)
        b:SetAlpha(1)
        b:Show()
      end
      y = y + TAILLE + ECART
    end
  end

  for i = it + 1, #v.titres do v.titres[i]:Hide() end
  if not InCombatLockdown() then
    for _, b in pairs(cases) do if not b.utilisee then b:Hide() end end
    contenu:SetHeight(math.max(y, 10))
    v.fenetre:SetHeight(58 + y + 30)
  end

  v.titre:SetText(titreTexte)
  v.pied:SetText(ns.texteCasesLibres(libres, total, speciaux))
  if avecArgent then v.argent:SetText(texteOr(GetMoney())) else v.argent:SetText("") end
  if db.apparenceWow ~= v.apparence then
    v.apparence = db.apparenceWow
    v.appliquerApparence()
  end
end

local function majVue()
  dessiner(sac, sacsPersonnage(), true, "Sacs de " .. (UnitName("player") or "?"), true)
end

-- La banque a deux onglets quand le jeu donne une banque de bataillon (Retail) :
-- « Personnage » et « Bataillon ». banque.onglet = "perso" ou "bataillon".
banque.onglet = "perso"

-- Les sacs de l'onglet montré, et s'il y a une banque de bataillon à proposer.
local function sacsBanqueCourants()
  local bataillon = sacsBataillon()
  if banque.onglet == "bataillon" and #bataillon == 0 then banque.onglet = "perso" end
  if banque.onglet == "perso" and #bataillon > 0 and not banqueVisible("Character") then banque.onglet = "bataillon" end
  if banque.onglet == "bataillon" then return bataillon, true end
  return sacsBanqueJeu(), #bataillon > 0
end

local majBanque
local bPerso = bouton("Personnage", 92, "La banque de ce personnage.",
  function() banque.onglet = "perso"; majBanque() end, banque.fenetre)
local bBataillon = bouton("Bataillon", 80, "La banque de bataillon, partagée entre tous tes personnages.",
  function() banque.onglet = "bataillon"; majBanque() end, banque.fenetre)
bPerso:SetPoint("TOPLEFT", MARGE, -30)
bBataillon:SetPoint("LEFT", bPerso, "RIGHT", 4, 0)
bPerso:Hide(); bBataillon:Hide()

majBanque = function()
  local sacs, aBataillon = sacsBanqueCourants()
  if banque.aBataillon ~= aBataillon then
    banque.aBataillon = aBataillon
    bPerso:SetShown(aBataillon)
    bBataillon:SetShown(aBataillon)
    banque.recherche:ClearAllPoints()
    if aBataillon then
      banque.recherche:SetPoint("LEFT", bBataillon, "RIGHT", 12, 0)
    else
      banque.recherche:SetPoint("TOPLEFT", MARGE, -30)
    end
    banque.recherche:SetPoint("RIGHT", banque.fenetre, "RIGHT", -MARGE, 0)
  end
  -- L'onglet montré a son bouton grisé.
  bPerso:SetEnabled(banque.onglet ~= "perso")
  bBataillon:SetEnabled(banque.onglet ~= "bataillon")
  dessiner(banque, sacs, false,
    banque.onglet == "bataillon" and "Banque de bataillon" or ("Banque de " .. (UnitName("player") or "?")), false)
end

recherche:HookScript("OnTextChanged", majVue)
banque.recherche:HookScript("OnTextChanged", majBanque)
fenetre:SetScript("OnShow", function()
  sac.appliquerApparence()
  majVue()
  if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_BACKPACK_OPEN) end
end)
fenetre:SetScript("OnHide", function()
  if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_BACKPACK_CLOSE) end
end)
banque.fenetre:SetScript("OnShow", function()
  banque.appliquerApparence()
  majBanque()
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

-- ---------------------------------------------------------------------------
-- La banque rangée : montrée seulement si la banque est ouverte, l'option cochée
-- et que le jeu sait nous dire ce qu'elle contient (sinon rien : la banque du jeu
-- reste la seule).
-- ---------------------------------------------------------------------------

local banqueOuverte = false

local majBoutonDepot

local function banqueMaj()
  if majBoutonDepot then majBoutonDepot() end
  local nbCases = 0
  if vueActive() and banqueOuverte then
    for _, numero in ipairs((sacsBanqueCourants())) do nbCases = nbCases + (ns.nbCases and ns.nbCases(numero) or 0) end
  end
  local montrer = ns.banqueAMontrer({
    vue = vueActive(), option = ns.db and ns.db.banqueCategories, ouverte = banqueOuverte, nbCases = nbCases,
    fermeeMain = banque.fermeeMain,
  })
  if montrer == banque.fenetre:IsShown() then
    if montrer then majBanque() end
    return
  end
  banque.fenetre:SetShown(montrer)
end

-- ---------------------------------------------------------------------------
-- Déposer en banque les composants des anciennes extensions (Retail, banque
-- ouverte). Le bouton « Déposer » du sac ouvre un petit panneau : une case par
-- extension présente dans les sacs, la destination (Personnage ou Bataillon),
-- puis l'addon déplace les piles une par une vers une case libre de la banque,
-- comme tu le ferais à la souris. Rien en combat ; arrêt si la banque se ferme.
-- ---------------------------------------------------------------------------

local depot = { file = {}, prises = {}, lignes = {} }
local prendreCase = (C_Container and C_Container.PickupContainerItem) or PickupContainerItem

local bDeposer = bouton("Déposer", 74,
  "Envoie en banque les composants des extensions que tu coches. La banque doit être ouverte.",
  function() if depot.basculerPanneau then depot.basculerPanneau() end end)
bDeposer:SetPoint("LEFT", bAnalyse, "RIGHT", 4, 0)
bDeposer:Hide()

majBoutonDepot = function()
  local montrer = banqueOuverte and extensionActuelle() > 0 and (ns.db and ns.db.compoExtension ~= false) and true or false
  if montrer ~= bDeposer:IsShown() then
    bDeposer:SetShown(montrer)
    recherche:ClearAllPoints()
    recherche:SetPoint("LEFT", montrer and bDeposer or bAnalyse, "RIGHT", 12, 0)
    recherche:SetPoint("RIGHT", fenetre, "RIGHT", -MARGE, 0)
  end
  if not montrer and depot.panneau then depot.panneau:Hide() end
end

local function dire(texte)
  if ns.reglages and ns.reglages.dire then ns.reglages.dire(texte) end
end

local function nomDestination()
  return banque.onglet == "bataillon" and "Bataillon" or "Personnage"
end

-- Un objet lié au personnage ne va pas en banque de bataillon : le jeu le dit.
local function accepteBataillon(numero, case)
  if not (C_Bank and C_Bank.IsItemAllowedInBankType and ItemLocation and Enum and Enum.BankType) then return true end
  local ok, r = pcall(function()
    return C_Bank.IsItemAllowedInBankType(Enum.BankType.Account, ItemLocation:CreateFromBagAndSlot(numero, case))
  end)
  return not ok or r ~= false
end

local function caseLibreBanque(sacs)
  for _, numero in ipairs(sacs) do
    for case = 1, (ns.nbCases and ns.nbCases(numero) or 0) do
      if not depot.prises[numero * 1000 + case] and not infoCase(numero, case) then return numero, case end
    end
  end
end

local function finDepot(raison)
  depot.enCours = false
  bDeposer:SetText("Déposer")
  local restent = (depot.total or 0) - (depot.faits or 0) - (depot.lies or 0) - (depot.laisses or 0)
  if raison and restent > 0 then
    raison = raison .. " (" .. restent .. " pile" .. (restent > 1 and "s restent" or " reste") .. " dans tes sacs)"
  end
  dire(ns.bilanDepot(depot.faits, depot.destination, depot.lies, depot.laisses, raison))
  depot.file, depot.prises = {}, {}
end

local pasDepot
local function unPasDepot()
  if not depot.enCours then return end
  if not banqueOuverte then return finDepot("la banque s'est fermée") end
  if InCombatLockdown() then return finDepot("tu es en combat") end
  if CursorHasItem and CursorHasItem() then return finDepot("tu tiens un objet à la souris") end
  local o
  while true do
    o = table.remove(depot.file, 1)
    if not o then return finDepot() end
    local icone, _, verrou, _, _, id = infoCase(o.sac, o.case)
    if not icone or id ~= o.id or verrou then
      depot.laisses = depot.laisses + 1
    elseif depot.versBataillon and not accepteBataillon(o.sac, o.case) then
      depot.lies = depot.lies + 1
    else
      break
    end
  end
  local numero, case = caseLibreBanque(depot.sacs)
  if not numero then return finDepot("la banque est pleine") end
  prendreCase(o.sac, o.case)
  if CursorHasItem and not CursorHasItem() then
    depot.laisses = depot.laisses + 1
  else
    prendreCase(numero, case)
    if CursorHasItem and CursorHasItem() then
      if ClearCursor then ClearCursor() end
      return finDepot("le jeu a refusé un objet")
    end
    depot.prises[numero * 1000 + case] = true
    depot.faits = depot.faits + 1
  end
  bDeposer:SetText((depot.faits + depot.laisses + depot.lies) .. "/" .. depot.total)
  C_Timer.After(0.25, pasDepot)
end
-- Une erreur en cours de route ne doit pas laisser le dépôt « en cours » pour toujours.
pasDepot = function()
  local ok, erreur = pcall(unPasDepot)
  if not ok then
    if depot.enCours then finDepot("erreur de l'addon") end
    if geterrorhandler then geterrorhandler()(erreur) end
  end
end

local function lancerDepot()
  if depot.enCours then return end
  if InCombatLockdown() then return dire("pas de dépôt en combat.") end
  if not banqueOuverte then return dire("ouvre d'abord la banque.") end
  local objets = lire(sacsPersonnage(), true)
  local file = ns.aDeposer(objets, ns.db and ns.db.depotExtensions, extensionActuelle())
  if #file == 0 then return dire("rien à déposer : coche au moins une extension.") end
  local sacs = sacsBanqueCourants()
  depot.file, depot.prises, depot.sacs = file, {}, sacs
  depot.total, depot.faits, depot.laisses, depot.lies = #file, 0, 0, 0
  depot.versBataillon = banque.onglet == "bataillon"
  depot.destination = nomDestination()
  depot.enCours = true
  if depot.panneau then depot.panneau:Hide() end
  pasDepot()
end

local function creerPanneauDepot()
  local f = CreateFrame("Frame", "SacsRangesDepot", fenetre, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(250, 100)
  f:SetPoint("BOTTOMRIGHT", fenetre, "TOPRIGHT", 0, 4)
  f:SetFrameStrata("HIGH")
  f:EnableMouse(true)
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    f:SetBackdropColor(0.07, 0.06, 0.045, 0.97)
    f:SetBackdropBorderColor(0.80, 0.63, 0.30, 1)
  end
  f.titre = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.titre:SetPoint("TOPLEFT", MARGE, -10)
  f.titre:SetText("Déposer en banque")
  local fermer = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  fermer:SetPoint("TOPRIGHT", 2, 2)
  f.vers = bouton("Vers : Personnage", 226,
    "La banque qui reçoit les composants. Un objet lié au personnage ne part jamais en banque de bataillon.",
    function()
      banque.onglet = banque.onglet == "bataillon" and "perso" or "bataillon"
      banqueMaj()
      depot.majPanneau()
    end, f)
  f.vers:SetPoint("TOPLEFT", MARGE, -30)
  f.lancer = bouton("Déposer", 226, "Déplace les piles cochées vers la banque, une par une.", lancerDepot, f)
  f:Hide()
  return f
end

local function ligneDepot(f, i)
  if not depot.lignes[i] then
    local c = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    c:SetSize(24, 24)
    c.libelle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    c.libelle:SetPoint("LEFT", c, "RIGHT", 2, 0)
    c:SetScript("OnClick", function(self)
      if not ns.db then return end
      ns.db.depotExtensions = ns.db.depotExtensions or {}
      ns.db.depotExtensions[self.extension] = self:GetChecked() and true or false
      depot.majPanneau()
    end)
    depot.lignes[i] = c
  end
  return depot.lignes[i]
end

function depot.majPanneau()
  local f = depot.panneau
  if not (f and f:IsShown()) then return end
  local objets = lire(sacsPersonnage(), true)
  local parExt, liste = ns.compterExtensions(objets)
  local actuelle = extensionActuelle()
  local choix = ns.db and ns.db.depotExtensions or {}
  local _, aBataillon = sacsBanqueCourants()
  f.vers:SetShown(aBataillon)
  f.vers:SetText("Vers : " .. nomDestination())
  local y = aBataillon and 58 or 32
  for i, e in ipairs(liste) do
    local c = ligneDepot(f, i)
    c.extension = e
    local coche = choix[e]
    if coche == nil then coche = ns.estAncienne(e, actuelle) end
    c:SetChecked(coche)
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", MARGE - 2, -y)
    c.libelle:SetText(ns.nomExtension(e) .. "  |cff888888" .. parExt[e] .. "|r")
    c:Show(); c.libelle:Show()
    y = y + 22
  end
  for i = #liste + 1, #depot.lignes do depot.lignes[i]:Hide(); depot.lignes[i].libelle:Hide() end
  local n = #ns.aDeposer(objets, choix, actuelle)
  f.lancer:ClearAllPoints()
  f.lancer:SetPoint("TOPLEFT", MARGE, -(y + 6))
  f.lancer:SetText(#liste == 0 and "Aucun composant dans tes sacs" or ("Déposer " .. n .. " pile" .. (n > 1 and "s" or "")))
  f.lancer:SetEnabled(n > 0)
  f:SetHeight(y + 6 + 22 + 12)
end

function depot.basculerPanneau()
  if depot.enCours then return end
  depot.panneau = depot.panneau or creerPanneauDepot()
  depot.panneau:SetShown(not depot.panneau:IsShown())
  depot.majPanneau()
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
  if not vueActive() then
    fenetre:Hide()
    banque.fenetre:Hide()
    return
  end
  if fenetre:IsShown() then sac.appliquerApparence(); majVue() end
  if banque.fenetre:IsShown() then banque.appliquerApparence() end
  banqueMaj()
end

-- ---------------------------------------------------------------------------
-- Événements
-- ---------------------------------------------------------------------------

local ecouteur = CreateFrame("Frame")
for _, e in ipairs({ "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED", "PLAYER_MONEY", "PLAYER_REGEN_ENABLED",
  "QUEST_ACCEPTED", "QUEST_REMOVED", "GET_ITEM_INFO_RECEIVED", "PLAYER_LOGIN",
  "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW",
  "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "PLAYERBANKSLOTS_CHANGED", "PLAYERBANKBAGSLOTS_CHANGED",
  "PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED", "BANK_TABS_CHANGED" }) do
  pcall(ecouteur.RegisterEvent, ecouteur, e)
end
local enAttente = false
local function programmer()
  -- Plusieurs événements d'affilée : une seule mise à jour.
  if enAttente then return end
  enAttente = true
  C_Timer.After(0.05, function()
    enAttente = false
    majVue()
    banqueMaj()
    if not depot.enCours then depot.majPanneau() end
  end)
end

-- Le guichet de banque, pour les événements « interaction » de Retail récent.
local function estBanquier(type)
  local t = Enum and Enum.PlayerInteractionType
  -- AccountBanker : la banque de bataillon ouverte seule (à distance).
  return t and type ~= nil and (type == t.Banker or (t.AccountBanker ~= nil and type == t.AccountBanker))
end

ecouteur:SetScript("OnEvent", function(_, evenement, arg1)
  if evenement == "PLAYER_LOGIN" then
    local e = ns.db and tonumber(ns.db.echelleSac)
    if e and e >= 0.5 and e <= 1.5 then fenetre:SetScale(e) end
    local p = ns.db and ns.db.positionSac
    if p then fenetre:ClearAllPoints(); fenetre:SetPoint(p[1], UIParent, p[2], p[3], p[4]) end
    return
  end
  if evenement == "BANKFRAME_OPENED" or (evenement == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" and estBanquier(arg1)) then
    banqueOuverte = true
    banque.fermeeMain = false -- une nouvelle ouverture de la banque la remontre
    return programmer()
  elseif evenement == "BANKFRAME_CLOSED" or (evenement == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" and estBanquier(arg1)) then
    banqueOuverte = false
    return programmer()
  end
  if evenement == "PLAYER_REGEN_ENABLED" and not aRefaire then return end
  if not (fenetre:IsShown() or banque.fenetre:IsShown()) then return end
  aRefaire = false
  programmer()
end)
