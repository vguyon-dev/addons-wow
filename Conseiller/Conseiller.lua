-- ============================================================================
-- Conseiller : un conseiller qui s'adapte à ton personnage et à ta situation.
--
--   /conseil  (ou /cs)       la fenêtre : Talents, Rotation, Équipement, Métiers, Race
--   /cs export               écrit l'arbre de talents et le grimoire dans la sauvegarde
--                            (ConseillerDB.export) : fais ensuite /reload pour que le fichier soit écrit
--   /cs mode auto|a|c        le mode de la rotation (auto, contour sur la barre, liste seule)
--   /cs etat                 ce que Conseiller a compris (classe, spécialisation, sorts, mode)
--
-- Ce qu'il lit : classe, spécialisation, race, niveau, et ta situation (seul, en groupe, donjon,
-- raid) avec les rôles de ton groupe. Rien n'est lancé à ta place : la rotation entoure en
-- bleu, sur TA barre d'action, le bouton du prochain sort (un cadre à nous, posé par-dessus : aucun
-- bouton du jeu n'est modifié, donc aucun « taint »). Si le jeu cache les temps de recharge en
-- combat, Conseiller passe tout seul à la liste de priorité.
-- Les données (sorts, rotations, conseils) sont dans Donnees.lua, la logique dans Logique.lua.
-- ============================================================================

local NOM_ADDON, ns = ...
local D = ns.DONNEES

local DEFAUTS = {
  actif = true,
  rotation = true,       -- le prochain sort conseillé
  modeRotation = 1,      -- 1 = automatique, 2 = contour sur la barre (A), 3 = liste seule (C)
  tailleContour = 3,     -- épaisseur du contour, en pixels
  contourTalent = true,  -- entourer le prochain talent conseillé dans la fenêtre des talents du jeu
  conseilsGroupe = true, -- prévenir quand il manque un rôle au groupe
  minimap = false,
  angleMinimap = 200,
}

local db

-- ---------------------------------------------------------------------------
-- Ce que le jeu dit du personnage
-- ---------------------------------------------------------------------------

local function classeJoueur()
  local _, classe = UnitClass("player")
  if ns.estSecret(classe) then return nil end
  return classe
end

-- La clé de la spécialisation actuelle (nil si le jeu n'en donne pas).
local function speActuelle(classe)
  local idx
  local spec = C_SpecializationInfo
  local ok, i
  if spec and spec.GetSpecialization then ok, i = pcall(spec.GetSpecialization)
  elseif GetSpecialization then ok, i = pcall(GetSpecialization) end
  if ok and type(i) == "number" and i > 0 then idx = i end
  if not idx then return nil end
  local lire = (spec and spec.GetSpecializationInfo) or GetSpecializationInfo
  local nom
  if lire then
    local okI, _, n = pcall(lire, idx)
    if okI and type(n) == "string" then nom = n end
  end
  -- Le nombre de spécialisations distingue Gardien (Retail, 4 pour le druide) de Restauration (Forever, 3).
  local nbSpes
  local compter = (spec and spec.GetNumSpecializations) or GetNumSpecializations
  if compter then
    local okN, n = pcall(compter)
    if okN and type(n) == "number" and not ns.estSecret(n) then nbSpes = n end
  end
  return ns.cleSpe(classe, nom, idx, nbSpes), nom
end

-- Les membres du groupe (sans toi) avec leur rôle et leur classe.
local function lireMembres()
  local m = {}
  if not (IsInGroup and IsInGroup()) then return m end
  local n = GetNumGroupMembers and GetNumGroupMembers() or 0
  local raid = IsInRaid and IsInRaid()
  for i = 1, raid and n or (n - 1) do
    local u = raid and ("raid" .. i) or ("party" .. i)
    if UnitExists(u) then
      -- Dans un raid, ton propre jeton est dans la liste : on le saute (UnitIsUnit sert à ça).
      local moi = UnitIsUnit(u, "player")
      if ns.estSecret(moi) then moi = false end
      if not moi then
        -- Une valeur secrète veut dire « inconnu » : rôle NONE, classe inconnue.
        local _, classe = UnitClass(u)
        if ns.estSecret(classe) then classe = nil end
        local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(u) or "NONE"
        if ns.estSecret(role) then role = "NONE" end
        local nom = UnitName(u)
        if ns.estSecret(nom) then nom = nil end
        m[#m + 1] = { role = role, classe = classe, nom = nom }
      end
    end
  end
  return m
end

local function situationReelle()
  local _, typeInstance = IsInInstance()
  return ns.situation({
    typeInstance = typeInstance,
    groupe = IsInGroup and IsInGroup() or false,
    raid = IsInRaid and IsInRaid() or false,
  })
end

-- Le groupe tel qu'on l'a lu la dernière fois (mis à jour par les événements de groupe).
local groupe = ns.analyserGroupe({})
local situation = "solo"
local derniereAlerte

-- Ton rôle : celui que le jeu t'a attribué, sinon celui de ta spécialisation actuelle.
local function monRole(classe)
  local r = UnitGroupRolesAssigned and UnitGroupRolesAssigned("player")
  if ns.estSecret(r) then r = nil end
  if r == "TANK" or r == "HEALER" or r == "DAMAGER" then return r end
  local cle = speActuelle(classe)
  local spe = cle and D.CLASSES[classe] and D.CLASSES[classe].specs[cle]
  if not spe then return nil end
  return (spe.role == "tank" and "TANK") or (spe.role == "soins" and "HEALER") or "DAMAGER"
end

local function majGroupe()
  situation = situationReelle()
  groupe = ns.analyserGroupe(lireMembres(), monRole(classeJoueur()))
  -- Un rôle manque et ta classe peut le jouer : un seul message par changement.
  if db and db.actif and db.conseilsGroupe and situation ~= "solo" and groupe.manque then
    local classe = classeJoueur()
    local conseil = ns.speConseillee(classe, situation, groupe)
    local cle = groupe.manque .. "|" .. tostring(conseil and conseil.cle)
    if conseil and conseil.parManque and cle ~= derniereAlerte then
      local actuelle = speActuelle(classe)
      if actuelle ~= conseil.cle then
        ns.reglages.dire(string.format("ton groupe n'a pas de %s : tu pourrais jouer %s. /conseil pour voir pourquoi.",
          D.NOMS_ROLES[groupe.manque] or groupe.manque, conseil.nom))
      end
    end
    derniereAlerte = cle
  elseif situation == "solo" or not groupe.manque then
    derniereAlerte = nil
  end
end

-- ---------------------------------------------------------------------------
-- Les sorts du personnage (résolus au chargement et quand le grimoire change)
-- ---------------------------------------------------------------------------

ns.sorts = {}
ns.cacheBoutonsSale = true

local function resoudre()
  ns.sorts = ns.resoudreSorts(classeJoueur(), ns.apiJeu)
  ns.cacheBoutonsSale = true
end

-- ---------------------------------------------------------------------------
-- Talents : le build, le prochain nœud, l'achat, l'export
-- ---------------------------------------------------------------------------

local function idConfig()
  if C_ClassTalents and C_ClassTalents.GetActiveConfigID then
    local ok, id = pcall(C_ClassTalents.GetActiveConfigID)
    if ok and type(id) == "number" then return id end
  end
  return nil
end

local function rangDuNoeud(configID, nodeID)
  if not (C_Traits and C_Traits.GetNodeInfo) then return nil end
  local ok, n = pcall(C_Traits.GetNodeInfo, configID, nodeID)
  if not ok or type(n) ~= "table" or ns.estSecret(n) then return nil end
  if not n or n.ID ~= nodeID or (n.maxRanks or 0) == 0 then return nil end -- le nœud n'existe pas dans cet arbre
  local rang = n.currentRank
  if type(rang) ~= "number" then rang = n.ranksPurchased end
  return type(rang) == "number" and rang or 0
end

local function nomDuNoeud(configID, nodeID)
  local ok, n = pcall(C_Traits.GetNodeInfo, configID, nodeID)
  if not ok or type(n) ~= "table" then return nil end
  local entree = n.activeEntry and n.activeEntry.entryID or (n.entryIDs and n.entryIDs[1])
  if not entree then return nil end
  local okE, e = pcall(C_Traits.GetEntryInfo, configID, entree)
  if not okE or type(e) ~= "table" or not e.definitionID then return nil end
  local okD, d = pcall(C_Traits.GetDefinitionInfo, e.definitionID)
  if not okD or type(d) ~= "table" or not d.spellID then return nil end
  return ns.apiJeu.nomSort(d.spellID), d.spellID
end

-- Le prochain talent du build : { etat = "vide" | "sansArbre" | "suivant" | "fini", nodeID, nom, rang, rangs, configID }.
function ns.infoTalents(classe, speCle, situationVue)
  local build = ns.buildPour(classe, speCle, situationVue)
  if not build then return { etat = "vide" } end
  local configID = idConfig()
  if not configID or not (C_Traits and C_Traits.GetNodeInfo) then return { etat = "sansArbre" } end
  local entree, rang = ns.prochainNoeud(build, function(nodeID) return rangDuNoeud(configID, nodeID) end)
  if not entree then
    -- Aucun nœud du build n'existe dans l'arbre du personnage : le build n'est pas fait pour lui.
    local existe = false
    for _, e in ipairs(build) do
      if rangDuNoeud(configID, e.nodeID) ~= nil then existe = true; break end
    end
    return { etat = existe and "fini" or "horsArbre", configID = configID }
  end
  return { etat = "suivant", configID = configID, nodeID = entree.nodeID, entryID = entree.entryID, rang = rang, rangs = entree.rangs or 1,
    nom = nomDuNoeud(configID, entree.nodeID) or ("nœud " .. tostring(entree.nodeID)) }
end

-- « Prendre ce talent » : jamais en combat, un seul point, validé tout de suite.
function ns.prendreTalent()
  local dire = ns.reglages.dire
  if InCombatLockdown() then dire("pas de changement de talents en combat.") return end
  local e = ns.construireEtat()
  local t = e.talents
  if t.etat ~= "suivant" then dire("pas de talent à prendre : " .. (t.etat == "fini" and "tout le build est pris." or "pas de build écrit pour ce personnage.")) return end
  -- Nœud à choix (plusieurs entryIDs) : on choisit d'abord l'entrée voulue par le build.
  if t.entryID and C_Traits.SetSelection then
    local okN, n = pcall(C_Traits.GetNodeInfo, t.configID, t.nodeID)
    if okN and type(n) == "table" and not ns.estSecret(n) and type(n.entryIDs) == "table" and #n.entryIDs > 1 then
      local okS, choisi = pcall(C_Traits.SetSelection, t.configID, t.nodeID, t.entryID)
      if not okS or choisi == false then dire("le jeu refuse le choix pour « " .. t.nom .. " ».") return end
    end
  end
  local ok, reussi = pcall(C_Traits.PurchaseRank, t.configID, t.nodeID)
  if not ok or reussi == false then dire("le jeu refuse « " .. t.nom .. " » (plus de points, ou un talent à prendre avant).") return end
  local valider = (C_ClassTalents and C_ClassTalents.CommitConfig) or C_Traits.CommitConfig
  local okV, valide = pcall(valider, t.configID)
  ns.talentsSale = true
  if ns.majFenetre then ns.majFenetre() end
  if not okV or valide == false then dire("talent acheté, mais le jeu a refusé de valider : " .. t.nom .. ".") return end
  dire("talent pris : " .. t.nom .. ".")
  ns.talentsSale = true
  if ns.majFenetre then ns.majFenetre() end
end

-- « /cs export » : l'arbre complet et le grimoire, dans la sauvegarde.
function ns.exporter()
  local dire = ns.reglages.dire
  local configID = idConfig()
  if not configID or not (C_Traits and C_Traits.GetConfigInfo and C_Traits.GetTreeNodes) then
    dire("export impossible : le jeu ne donne pas l'arbre de talents (configuration active introuvable).")
    return
  end
  local classe = classeJoueur()
  local spe, nomSpe = speActuelle(classe)
  local sortie = {
    version = 1, date = date and date("%Y-%m-%d %H:%M") or "?", classe = classe, niveau = UnitLevel("player"),
    spe = spe, nomSpe = nomSpe, configID = configID, noeuds = {}, grimoire = {},
  }
  local okC, info = pcall(C_Traits.GetConfigInfo, configID)
  local arbres = okC and type(info) == "table" and info.treeIDs or {}
  sortie.arbres = arbres
  for _, treeID in ipairs(arbres) do
    local okN, ids = pcall(C_Traits.GetTreeNodes, treeID)
    for _, nodeID in ipairs(okN and ids or {}) do
      local ok, n = pcall(C_Traits.GetNodeInfo, configID, nodeID)
      if ok and type(n) == "table" and not ns.estSecret(n) then
        local noeud = { nodeID = nodeID, arbre = treeID, posX = n.posX, posY = n.posY, maxRanks = n.maxRanks,
          rang = n.currentRank, visible = n.isVisible, entrees = {} }
        for _, entryID in ipairs(n.entryIDs or {}) do
          local sort = { entryID = entryID }
          local okE, e = pcall(C_Traits.GetEntryInfo, configID, entryID)
          if okE and type(e) == "table" and e.definitionID then
            local okD, d = pcall(C_Traits.GetDefinitionInfo, e.definitionID)
            if okD and type(d) == "table" and d.spellID then
              sort.spellID = d.spellID
              sort.nom = ns.apiJeu.nomSort(d.spellID)
            end
          end
          noeud.entrees[#noeud.entrees + 1] = sort
        end
        sortie.noeuds[#sortie.noeuds + 1] = noeud
      end
    end
  end
  local okG, grimoire = pcall(ns.apiJeu.grimoire)
  if okG then sortie.grimoire = grimoire end
  db.export = sortie
  dire(string.format("arbre exporté : %d nœuds, %d sorts dans le grimoire. Fais /reload pour que le fichier soit écrit (ConseillerDB dans WTF\\Account\\…\\SavedVariables).",
    #sortie.noeuds, #sortie.grimoire))
end

-- ---------------------------------------------------------------------------
-- L'état de ce qu'on affiche (lu par la fenêtre)
-- ---------------------------------------------------------------------------

local etatRotation = {} -- rempli par rafraichir()
ns.situationForcee = nil

local function lireMetiers()
  local res = {}
  if GetProfessions and GetProfessionInfo then
    local liste = { GetProfessions() }
    for i = 1, 6 do
      local idx = liste[i]
      if idx then
        local ok, nom, _, niveau, plafond = pcall(GetProfessionInfo, idx)
        if ok and nom then res[#res + 1] = { nom = nom, niveau = niveau or 0, plafond = plafond or 75 } end
      end
    end
  elseif GetNumSkillLines and GetSkillLineInfo then
    local connus = { "Alchimie", "Forge", "Cuisine", "Enchantement", "Ingénierie", "Herboristerie",
      "Travail du cuir", "Minage", "Dépeçage", "Couture", "Pêche", "Secourisme" }
    local ensemble = {}
    for _, n in ipairs(connus) do ensemble[n] = true end
    for i = 1, GetNumSkillLines() do
      local nom, entete, _, niveau, _, _, plafond = GetSkillLineInfo(i)
      if nom and not entete and ensemble[nom] then res[#res + 1] = { nom = nom, niveau = niveau or 0, plafond = plafond or 75 } end
    end
  end
  return res
end

function ns.construireEtat()
  local classe = classeJoueur()
  local c = D.CLASSES[classe]
  local raceNom, raceToken = UnitRace("player")
  local e = {
    classe = classe, classeNom = c and c.nom or tostring(classe), niveau = UnitLevel("player"),
    raceNom = raceNom, raceToken = raceToken,
  }
  e.situationReelle = situation
  e.situation = ns.situationForcee or situation
  -- Le groupe lu : seulement si tu es vraiment en groupe (une vue forcée sans groupe n'invente pas de rôles).
  e.groupe = (e.situation ~= "solo" and situation ~= "solo") and groupe or nil
  e.speCle, e.speNom = speActuelle(classe)
  e.conseil = ns.speConseillee(classe, e.situation, e.groupe)
  e.talents = ns.infoTalents(classe, e.speCle or (e.conseil and e.conseil.cle), e.situation)
  -- Rotation : la spécialisation actuelle, sinon la conseillée.
  e.speRotation = e.speCle or (e.conseil and e.conseil.cle)
  local liste = D.ROTATIONS[classe] and e.speRotation and D.ROTATIONS[classe][e.speRotation]
  if liste then
    local statiques = {}
    for _, entree in ipairs(liste) do
      local s = ns.sorts[entree.sort]
      if s then statiques[#statiques + 1] = { sort = entree.sort, texte = entree.texte or s.nom, nom = s.nom } end
    end
    e.rotation = {
      liste = liste, lignesStatiques = statiques,
      resultat = etatRotation.speCle == e.speRotation and etatRotation.resultat or nil,
      mode = etatRotation.mode or ns.modeEffectif(db and db.modeRotation or 1, false),
      auto = etatRotation.auto, boutons = etatRotation.nbBoutons,
    }
  end
  e.metiers = lireMetiers()
  return e
end

-- ---------------------------------------------------------------------------
-- Contour pulsé (un cadre à nous, posé par-dessus un bouton du jeu)
-- ---------------------------------------------------------------------------

local function nouveauContour(r, v, b)
  local f = CreateFrame("Frame", nil, UIParent)
  f:SetFrameStrata("HIGH")
  f:EnableMouse(false)
  local bords = {}
  for i = 1, 4 do
    local t = f:CreateTexture(nil, "OVERLAY")
    t:SetColorTexture(r, v, b, 1)
    bords[i] = t
  end
  f.bords = bords
  f.temps = 0
  f:SetScript("OnUpdate", function(self, dt)
    if type(dt) ~= "number" then return end
    self.temps = self.temps + dt
    self:SetAlpha(0.55 + 0.45 * math.sin(self.temps * 5))
    -- Le bouton a disparu (autre barre, fenêtre fermée) : le contour part avec lui.
    local cible = self.cible
    if cible and not cible:IsVisible() then self:Hide() end
  end)
  f:Hide()
  function f:placer(cible, epaisseur)
    epaisseur = epaisseur or 3
    self.cible = cible
    self.epaisseur = epaisseur
    self:ClearAllPoints()
    self:SetPoint("TOPLEFT", cible, "TOPLEFT", -epaisseur, epaisseur)
    self:SetPoint("BOTTOMRIGHT", cible, "BOTTOMRIGHT", epaisseur, -epaisseur)
    local h, bas, g, d = bords[1], bords[2], bords[3], bords[4]
    h:ClearAllPoints(); h:SetPoint("TOPLEFT"); h:SetPoint("TOPRIGHT"); h:SetHeight(epaisseur)
    bas:ClearAllPoints(); bas:SetPoint("BOTTOMLEFT"); bas:SetPoint("BOTTOMRIGHT"); bas:SetHeight(epaisseur)
    g:ClearAllPoints(); g:SetPoint("TOPLEFT"); g:SetPoint("BOTTOMLEFT"); g:SetWidth(epaisseur)
    d:ClearAllPoints(); d:SetPoint("TOPRIGHT"); d:SetPoint("BOTTOMRIGHT"); d:SetWidth(epaisseur)
    self:SetFrameLevel((cible:GetFrameLevel() or 1) + 5)
    self:Show()
  end
  return f
end
ns.nouveauContour = nouveauContour

-- ---------------------------------------------------------------------------
-- Rotation : contour bleu sur la barre d'action, ou liste de priorité (mode C)
-- ---------------------------------------------------------------------------

local PREFIXES_BARRES = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
  "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }

-- L'action d'un bouton : on LIT seulement ce que le jeu y a posé, on n'écrit rien.
local function lireSlot(cadre)
  -- La page de barre active change la case réelle : CalculateAction la donne (lecture seule).
  if cadre.CalculateAction then
    local ok, v = pcall(cadre.CalculateAction, cadre)
    if ok and type(v) == "number" then return v end
  end
  local s = cadre.action
  if type(s) == "number" then return s end
  return nil
end

local function listeBoutons()
  local l = {}
  for _, prefixe in ipairs(PREFIXES_BARRES) do
    for i = 1, 12 do
      local cadre = _G[prefixe .. i]
      if cadre then l[#l + 1] = { cadre = cadre, slot = lireSlot(cadre) } end
    end
  end
  return l
end

local cacheBoutons = {}
local function boutonsDuSort(cle)
  if ns.cacheBoutonsSale then
    cacheBoutons = {}
    ns.cacheBoutonsSale = false
  end
  local c = cacheBoutons[cle]
  if not c then
    c = ns.boutonsPourSort(ns.sorts[cle], listeBoutons(), ns.apiJeu)
    cacheBoutons[cle] = c
  end
  return c
end

local contours = {}
local function cacherContours()
  for _, c in ipairs(contours) do c:Hide() end
end

local function montrerContours(boutons)
  local n = 0
  for _, b in ipairs(boutons) do
    if b.cadre:IsVisible() then
      n = n + 1
      if n > 4 then break end
      if not contours[n] then contours[n] = nouveauContour(0.35, 0.70, 1) end
      local epaisseur = db.tailleContour or 3
      local c = contours[n]
      -- On ne replace que si la cible, l'épaisseur ou la visibilité a changé.
      if c.cible ~= b.cadre or c.epaisseur ~= epaisseur or not c:IsShown() then c:placer(b.cadre, epaisseur) end
    end
  end
  for i = n + 1, #contours do contours[i]:Hide() end
  return n
end

-- Le petit cadre du mode C : l'ordre de priorité, déplaçable.
local cadreListe = CreateFrame("Frame", "ConseillerListe", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
cadreListe:SetSize(290, 60)
cadreListe:SetPoint("CENTER", UIParent, "CENTER", -280, -80)
cadreListe:SetMovable(true)
cadreListe:SetClampedToScreen(true)
cadreListe:EnableMouse(true)
cadreListe:RegisterForDrag("LeftButton")
cadreListe:SetScript("OnDragStart", cadreListe.StartMoving)
cadreListe:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local p, _, rp, x, y = self:GetPoint()
  if db then db.positionListe = { p, rp, x, y } end
end)
ns.habiller(cadreListe, { titre = "Rotation" })
local texteListe = cadreListe:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
texteListe:SetPoint("TOPLEFT", 12, -34)
texteListe:SetWidth(266)
texteListe:SetJustifyH("LEFT")
cadreListe:Hide()

local function placerListe()
  cadreListe:ClearAllPoints()
  local p = db and db.positionListe
  if p then cadreListe:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else cadreListe:SetPoint("CENTER", UIParent, "CENTER", -280, -80) end
end
ns.placerListe = placerListe

local function montrerListe(res)
  local lignes = {}
  for i, l in ipairs(res.lignes) do
    local couleur = l.verdict == true and ns.COULEURS.bleu or (l.verdict == false and ns.COULEURS.gris or "|cffffffff")
    lignes[#lignes + 1] = string.format("%s%d. %s%s|r", couleur, i, l.texte, res.choix == l and "  <" or "")
  end
  texteListe:SetText(table.concat(lignes, "\n"))
  cadreListe:SetHeight(44 + 15 * math.max(1, #lignes))
  cadreListe:Show()
end

local aDitModeC = false

local function listeDeRotation()
  local classe = classeJoueur()
  local spe = speActuelle(classe)
  if not spe then
    local conseil = ns.speConseillee(classe, ns.situationForcee or situation, groupe)
    spe = conseil and conseil.cle
  end
  return D.ROTATIONS[classe] and spe and D.ROTATIONS[classe][spe], spe
end

local function cibleAttaquable()
  return UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDeadOrGhost("target")
end

local function rafraichir()
  if not db then return end
  local liste, spe = listeDeRotation()
  etatRotation.speCle = spe
  if not (db.actif and db.rotation and liste and cibleAttaquable()) then
    cacherContours()
    cadreListe:Hide()
    etatRotation.resultat = nil
    return
  end
  local res = ns.evaluerRotation(liste, ns.sorts, ns.apiJeu)
  etatRotation.resultat = res
  local mode = ns.modeEffectif(db.modeRotation, res.illisible)
  etatRotation.mode = mode
  etatRotation.auto = db.modeRotation == 1 and res.illisible
  if etatRotation.auto and not aDitModeC then
    aDitModeC = true
    ns.reglages.dire("le jeu cache les temps de recharge pendant le combat : je passe tout seul à la liste de priorité (mode C).")
  end
  if mode == "A" then
    cadreListe:Hide()
    if res.choix then
      etatRotation.nbBoutons = montrerContours(boutonsDuSort(res.cle))
    else
      etatRotation.nbBoutons = nil
      cacherContours()
    end
  else
    cacherContours()
    etatRotation.nbBoutons = nil
    montrerListe(res)
  end
end

-- ---------------------------------------------------------------------------
-- Talents : le contour vert dans la fenêtre des talents du jeu
-- ---------------------------------------------------------------------------

local contourTalent = nouveauContour(0.25, 0.90, 0.35)
ns.talentsSale = true
local talentCache

local function majContourTalent()
  if not (db and db.actif and db.contourTalent) then contourTalent:Hide() return end
  local cadre = PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame
  if not (cadre and cadre.IsVisible and cadre:IsVisible()) then contourTalent:Hide() return end
  if ns.talentsSale or not talentCache then
    ns.talentsSale = false
    local e = ns.construireEtat()
    talentCache = e.talents
  end
  if talentCache.etat ~= "suivant" or not cadre.GetTalentButtonByNodeID then contourTalent:Hide() return end
  local ok, bouton = pcall(cadre.GetTalentButtonByNodeID, cadre, talentCache.nodeID)
  if ok and bouton and bouton:IsVisible() then
    if contourTalent.cible ~= bouton or not contourTalent:IsShown() then contourTalent:placer(bouton, 3) end
  else
    contourTalent:Hide()
  end
end

-- ---------------------------------------------------------------------------
-- Pour les autres addons
-- ---------------------------------------------------------------------------

-- L'ordre des statistiques de la spécialisation actuelle (copie : on peut la modifier).
function Conseiller_OrdreStats()
  local classe = classeJoueur()
  local spe = speActuelle(classe)
  local copie = {}
  for i, cle in ipairs(ns.ordreStats(classe, spe)) do copie[i] = cle end
  return copie
end

-- ---------------------------------------------------------------------------
-- Réglages
-- ---------------------------------------------------------------------------

local function nomMode(v)
  if v == 2 then return "A (contour)" end
  if v == 3 then return "C (liste)" end
  return "Auto"
end

ns.reglages = ns.creerReglages({
  titre = "Conseiller",
  icone = "Interface\\Icons\\INV_Misc_Book_09",
  nomDB = "ConseillerDB",
  defauts = DEFAUTS,
  options = {
    { titre = "Conseiller" },
    { cle = "actif", libelle = "Activer Conseiller",
      aide = "Lit ton personnage et ta situation, et te conseille : spécialisation, talents, prochain sort, statistiques, métiers, race." },
    { cle = "conseilsGroupe", libelle = "Prévenir quand il manque un rôle à ton groupe",
      aide = "Un message dans le chat quand ton groupe n'a pas de tank ou de soigneur et que ta classe peut le jouer. Une seule fois par changement." },
    { titre = "Rotation" },
    { cle = "rotation", libelle = "Montrer le prochain sort conseillé",
      aide = "Un contour bleu qui pulse sur le bouton du sort, sur ta barre d'action. Rien n'est lancé à ta place." },
    { cle = "modeRotation", type = "nombre", libelle = "Mode de la rotation", min = 1, max = 3, pas = 1, format = nomMode,
      dependDe = "rotation",
      aide = "Auto : contour sur la barre, et la liste de priorité si le jeu cache les temps de recharge. A : toujours le contour. C : toujours la liste." },
    { cle = "tailleContour", type = "nombre", libelle = "Épaisseur du contour", min = 2, max = 8, pas = 1,
      format = function(v) return v .. " px" end, dependDe = "rotation" },
    { titre = "Talents" },
    { cle = "contourTalent", libelle = "Entourer le prochain talent dans la fenêtre des talents",
      aide = "Un contour vert sur le talent conseillé, quand un build est écrit pour ta spécialisation." },
    { titre = "Icône" },
    { cle = "minimap", libelle = "Icône à part autour de la minimap",
      aide = "En plus de la ligne dans l'icône commune des addons de Valentin." },
  },
  boutons = {
    { texte = "Ouvrir le Conseiller", aide = "La fenêtre avec les cinq onglets.", action = function()
      if ns.fenetre then ns.fenetre.montrer() end
    end },
    { texte = "Exporter mon arbre de talents", aide = "Écrit l'arbre et le grimoire dans la sauvegarde ; fais /reload ensuite.", action = function()
      ns.exporter()
    end },
    { texte = "Replacer la liste de priorité", aide = "Remet le petit cadre du mode C à sa place d'origine.", action = function()
      db.positionListe = nil; placerListe()
    end },
  },
  ouvrirHub = function() if ns.fenetre then ns.fenetre.basculer() end end,
  texteHub = "Ouvrir le Conseiller",
  auChargement = function(d)
    db = d
    placerListe()
    pcall(resoudre)
    pcall(majGroupe)
  end,
  surChangement = function()
    if db and not (db.actif and db.rotation) then cacherContours(); cadreListe:Hide() end
    ns.talentsSale = true
  end,
})

-- ---------------------------------------------------------------------------
-- Événements et mise à jour
-- ---------------------------------------------------------------------------

local EVENEMENTS_GROUPE = { GROUP_ROSTER_UPDATE = true, PLAYER_ENTERING_WORLD = true, ZONE_CHANGED_NEW_AREA = true,
  PLAYER_ROLES_ASSIGNED = true }
local EVENEMENTS_BARRES = { ACTIONBAR_SLOT_CHANGED = true, ACTIONBAR_PAGE_CHANGED = true, UPDATE_BONUS_ACTIONBAR = true }
local EVENEMENTS_SPE = { PLAYER_SPECIALIZATION_CHANGED = true, ACTIVE_TALENT_GROUP_CHANGED = true }
local EVENEMENTS_TALENTS = { TRAIT_CONFIG_UPDATED = true, TRAIT_NODE_CHANGED = true, PLAYER_TALENT_UPDATE = true,
  ACTIVE_COMBAT_CONFIG_CHANGED = true, TRAIT_TREE_CURRENCY_INFO_UPDATED = true }
local AUTRES = { "PLAYER_TARGET_CHANGED", "SPELLS_CHANGED", "PLAYER_REGEN_ENABLED",
  "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED" }

local ecouteur = CreateFrame("Frame")
local function inscrire(liste)
  for ev in pairs(liste) do pcall(ecouteur.RegisterEvent, ecouteur, ev) end
end
inscrire(EVENEMENTS_GROUPE); inscrire(EVENEMENTS_BARRES); inscrire(EVENEMENTS_SPE); inscrire(EVENEMENTS_TALENTS)
for _, ev in ipairs(AUTRES) do pcall(ecouteur.RegisterEvent, ecouteur, ev) end

ecouteur:SetScript("OnEvent", function(_, ev)
  if not db then return end
  if ev == "SPELLS_CHANGED" or EVENEMENTS_SPE[ev] or ev == "PLAYER_ENTERING_WORLD" then pcall(resoudre) end
  if EVENEMENTS_GROUPE[ev] or EVENEMENTS_SPE[ev] then pcall(majGroupe) end
  if EVENEMENTS_BARRES[ev] then ns.cacheBoutonsSale = true end
  if EVENEMENTS_TALENTS[ev] or EVENEMENTS_SPE[ev] then ns.talentsSale = true end
  if ns.majFenetre and (EVENEMENTS_GROUPE[ev] or EVENEMENTS_SPE[ev] or EVENEMENTS_TALENTS[ev] or ev == "PLAYER_LEVEL_UP"
    or ev == "SKILL_LINES_CHANGED") then
    ns.majFenetre()
  end
end)

-- Mise à jour limitée : la rotation 10 fois par seconde (un temps de recharge qui finit ne
-- donne pas d'événement), le contour des talents 2 fois par seconde.
local pilote = CreateFrame("Frame")
local ecoule, ecouleTalents = 0, 0
pilote:SetScript("OnUpdate", function(_, dt)
  if type(dt) ~= "number" then return end
  ecoule = ecoule + dt
  if ecoule >= 0.1 then
    ecoule = 0
    local ok, err = pcall(rafraichir)
    if not ok then ns.derniereErreur = tostring(err) end
  end
  ecouleTalents = ecouleTalents + dt
  if ecouleTalents >= 0.5 then
    ecouleTalents = 0
    local ok, err = pcall(majContourTalent)
    if not ok then ns.derniereErreur = tostring(err) end
  end
end)

-- ---------------------------------------------------------------------------
-- Commandes
-- ---------------------------------------------------------------------------

local function dire(t) ns.reglages.dire(t) end

local function etatEnTexte()
  local e = ns.construireEtat()
  local n = 0
  for _ in pairs(ns.sorts) do n = n + 1 end
  dire(string.format("%s niveau %s, %s, spécialisation %s, situation %s%s. Sorts connus : %d. Mode : %s%s.",
    e.classeNom, tostring(e.niveau), tostring(e.raceNom), tostring(e.speNom or "inconnue"), e.situation,
    ns.situationForcee and " (forcée)" or "", n, etatRotation.mode or "?", etatRotation.auto and " (auto)" or ""))
  if ns.derniereErreur then dire("dernière erreur : " .. ns.derniereErreur) end
end

SLASH_CONSEILLER1 = "/conseil"
SLASH_CONSEILLER2 = "/cs"
SlashCmdList.CONSEILLER = function(message)
  local c = strtrim(message or ""):lower()
  if c == "" then
    if ns.fenetre then ns.fenetre.basculer() end
  elseif c == "export" then ns.exporter()
  elseif c == "etat" then etatEnTexte()
  elseif c == "options" or c == "reglages" then ns.reglages.montrer()
  elseif c == "on" or c == "off" then
    if (c == "on") ~= (db.actif and true or false) then ns.reglages.basculer() end
  elseif c:match("^mode ") then
    local v = c:match("^mode%s+(%S+)")
    local n = (v == "auto" and 1) or (v == "a" and 2) or (v == "c" and 3) or nil
    if n then ns.reglages.changer("modeRotation", n); dire("mode de la rotation : " .. nomMode(n))
    else dire("/cs mode auto | a | c") end
  elseif not ns.reglages.basculerOption(c) then
    dire("/conseil : la fenêtre ; /cs export ; /cs mode auto|a|c ; /cs etat ; /cs options ; /cs on | off")
  end
end
