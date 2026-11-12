-- ============================================================================
-- Conseiller : un conseiller qui s'adapte à ton personnage et à ta situation.
--
--   /conseil  (ou /cs)       la fenêtre : Talents, Rotation, Compétences, Équipement, Métiers, Race
--   /cs export               écrit l'arbre de talents et le grimoire dans la sauvegarde
--                            (ConseillerDB.export) : fais ensuite /reload pour que le fichier soit écrit
--   /cs mode auto|a|c        le mode de la rotation (auto, contour sur la barre, liste seule)
--   /cs etat                 ce que Conseiller a compris (classe, spécialisation et points par groupe de talents,
--                            build utilisé, prochain talent, état du contour vert, sorts, mode, liste retenue chez le
--                            maître de classe, marques, et les talents du build qu'il n'a pas reconnus dans l'arbre)
--
-- Ce qu'il lit : classe, spécialisation, race, niveau, et ta situation (seul, en groupe, donjon,
-- raid) avec les rôles de ton groupe. Rien n'est lancé à ta place : la rotation entoure en
-- bleu, sur TA barre d'action, le bouton du prochain sort (un cadre à nous, posé par-dessus : aucun
-- bouton du jeu n'est modifié, donc aucun « taint »). La rotation ne porte que des sorts d'attaque ; en option,
-- un contour rouge à part signale le sort de soin ou de défense quand ta vie est basse. Si le jeu cache les temps de recharge en
-- combat, Conseiller passe tout seul à la liste de priorité.
-- Les données (sorts, rotations, builds de talents, conseils : les 9 classes) sont dans Donnees.lua, tirées des
-- fiches de outils/donnees-conseiller/ ; la logique est dans Logique.lua. Un build de talents désigne chaque
-- talent par ses sorts et ses noms (français, anglais) : Conseiller le retrouve dans l'arbre du jeu.
-- ============================================================================

local NOM_ADDON, ns = ...
local D = ns.DONNEES

local DEFAUTS = {
  actif = true,
  rotation = true,       -- le prochain sort conseillé
  modeRotation = 1,      -- 1 = automatique, 2 = contour sur la barre (A), 3 = liste seule (C)
  alerteUrgence = false, -- contour rouge sur le sort de soin ou de défense quand ta vie est basse
  tailleContour = 3,     -- épaisseur du contour, en pixels
  contourTalent = true,  -- entourer le prochain talent conseillé dans la fenêtre des talents du jeu
  rappelNiveau = true,   -- à la montée de niveau : les sorts indispensables du maître de classe
  marquesMaitre = true,  -- une marque dorée ou argentée sur les sorts utiles dans la fenêtre du maître de classe
  rappelBarre = true,    -- un message quand un sort de ta rotation n'est sur aucune barre
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

-- Les groupes de l'arbre de talents (Forever : Sacré, Protection, Vindicte côte à côte, dans UN seul arbre)
-- avec les points dépensés dans chacun : { { groupID, displayName, orderIndex, depense } }, ou nil quand le jeu
-- ne donne pas de groupes (Retail : une spécialisation = un arbre).
local function lireGroupes()
  if not (C_Traits and C_Traits.GetGroupDisplayInfoByTreeID and C_Traits.GetConfigInfo and C_ClassTalents
    and C_ClassTalents.GetActiveConfigID) then return nil end
  local okId, configID = pcall(C_ClassTalents.GetActiveConfigID)
  if not okId or type(configID) ~= "number" then return nil end
  local okC, info = pcall(C_Traits.GetConfigInfo, configID)
  if not okC or type(info) ~= "table" or ns.estSecret(info) then return nil end
  local treeID = info.treeIDs and info.treeIDs[1]
  if not treeID then return nil end
  local okG, infos = pcall(C_Traits.GetGroupDisplayInfoByTreeID, treeID)
  if not okG or type(infos) ~= "table" or ns.estSecret(infos) or #infos < 2 then return nil end
  local ids = {}
  for _, g in ipairs(infos) do ids[#ids + 1] = g.groupID end
  local depenses = {}
  if C_Traits.GetGroupCurrencyInfo then
    local okD, lignes = pcall(C_Traits.GetGroupCurrencyInfo, configID, ids)
    if okD and type(lignes) == "table" and not ns.estSecret(lignes) then
      for _, l in ipairs(lignes) do
        local total = 0
        for _, c in ipairs(l.currencyInfos or {}) do
          if type(c.spent) == "number" and not ns.estSecret(c.spent) then total = total + c.spent end
        end
        depenses[l.traitNodeGroupID] = total
      end
    end
  end
  local res = {}
  for _, g in ipairs(infos) do
    res[#res + 1] = { groupID = g.groupID, displayName = type(g.displayName) == "string" and g.displayName or nil,
      orderIndex = g.orderIndex, depense = depenses[g.groupID] or 0 }
  end
  return res, treeID, configID
end

-- Les points par groupe et la spécialisation qui en découle (cache court : le jeu est interrogé au plus
-- toutes les 2 secondes, ou quand un événement de talents marque ns.speSale).
ns.speSale = true
local cacheSpe = { t = -100 }
function ns.infoGroupes(classe)
  local maintenant = GetTime and GetTime() or 0
  if not ns.speSale and cacheSpe.classe == classe and maintenant - cacheSpe.t < 2 then return cacheSpe.res end
  local groupes = lireGroupes()
  local res = groupes and ns.speParGroupes(classe, groupes) or nil
  cacheSpe = { t = maintenant, classe = classe, res = res }
  ns.speSale = false
  return res
end

-- La clé de la spécialisation actuelle (nil si le jeu n'en donne pas).
local function speActuelle(classe)
  -- Un arbre partagé en groupes (Forever) : la spécialisation est le groupe où l'on a le plus de points.
  local gr = ns.infoGroupes(classe)
  if gr then return gr.cle, gr.nom end
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
        -- (pas de « x or "NONE" » : cela testerait la valeur avant qu'on sache si elle est secrète)
        local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(u)
        if ns.estSecret(role) or role == nil then role = "NONE" end
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

-- Le rang pris d'un nœud (nil si le nœud n'existe pas dans l'arbre du personnage : il est sauté).
-- Quand le nœud est « à choix » et qu'un autre choix est actif, l'entrée voulue n'est pas prise : rang 0.
local function rangDuNoeud(configID, nodeID, entryID)
  if not (C_Traits and C_Traits.GetNodeInfo) then return nil end
  local ok, n = pcall(C_Traits.GetNodeInfo, configID, nodeID)
  if not ok or type(n) ~= "table" or ns.estSecret(n) then return nil end
  if not n or n.ID ~= nodeID or (n.maxRanks or 0) == 0 then return nil end -- le nœud n'existe pas dans cet arbre
  local rang = n.currentRank
  if type(rang) ~= "number" then rang = n.ranksPurchased end
  if type(rang) ~= "number" then rang = 0 end
  if entryID and type(n.entryIDs) == "table" and #n.entryIDs > 1 and type(n.activeEntry) == "table"
    and n.activeEntry.entryID and n.activeEntry.entryID ~= entryID then
    return 0
  end
  return rang, n.maxRanks
end

-- Le jeu laisse-t-il acheter un rang de ce nœud maintenant (palier atteint, point à dépenser) ?
-- true / false, ou nil quand le jeu ne le dit pas (on essaiera).
-- Les points libres de l'arbre de la configuration (nil si le jeu ne le dit pas).
local function pointsLibresArbre(configID)
  if not (C_Traits.GetConfigInfo and C_Traits.GetTreeCurrencyInfo) then return nil end
  local okC, c = pcall(C_Traits.GetConfigInfo, configID)
  local arbre = okC and type(c) == "table" and type(c.treeIDs) == "table" and c.treeIDs[1]
  if not arbre or ns.estSecret(arbre) then return nil end
  local okD, devises = pcall(C_Traits.GetTreeCurrencyInfo, configID, arbre, false)
  if not okD then return nil end
  return ns.pointsLibres(devises)
end

local function peutAcheter(configID, nodeID)
  -- Aucun point libre : rien n'est achetable, même si le nœud dit le contraire (voir ns.pointsLibres).
  if pointsLibresArbre(configID) == 0 then return false end
  local ok, n = pcall(C_Traits.GetNodeInfo, configID, nodeID)
  if not ok or type(n) ~= "table" or ns.estSecret(n) then return nil end
  if n.canPurchaseRank == false or n.isAvailable == false then return false end
  return true
end

-- Le sort et le nom (dans la langue du jeu) du talent d'une entrée de l'arbre.
local function sortDeLEntree(configID, entryID)
  if not (C_Traits and C_Traits.GetEntryInfo and C_Traits.GetDefinitionInfo) then return nil, nil end
  local okE, e = pcall(C_Traits.GetEntryInfo, configID, entryID)
  if not okE or type(e) ~= "table" or not e.definitionID then return nil, nil end
  local okD, d = pcall(C_Traits.GetDefinitionInfo, e.definitionID)
  if not okD or type(d) ~= "table" then return nil, nil end
  local spellID = d.spellID
  if ns.estSecret(spellID) then return nil, nil end
  local nom = spellID and ns.apiJeu.nomSort(spellID) or nil
  if type(nom) ~= "string" or ns.estSecret(nom) then nom = nil end
  if not nom and type(d.overrideName) == "string" and not ns.estSecret(d.overrideName) then nom = d.overrideName end
  return spellID, nom
end

local function nomDuNoeud(configID, nodeID, entryID)
  if not entryID then
    local ok, n = pcall(C_Traits.GetNodeInfo, configID, nodeID)
    if not ok or type(n) ~= "table" then return nil end
    entryID = n.activeEntry and n.activeEntry.entryID or (n.entryIDs and n.entryIDs[1])
  end
  if not entryID then return nil end
  local spellID, nom = sortDeLEntree(configID, entryID)
  return nom, spellID
end

-- L'arbre du personnage sous forme de liste pure : { { nodeID, entrees = { { entryID, spellID, nom } } } }.
function ns.lireArbre(configID)
  local res = {}
  if not (C_Traits and C_Traits.GetConfigInfo and C_Traits.GetTreeNodes and C_Traits.GetNodeInfo) then return res end
  local okC, info = pcall(C_Traits.GetConfigInfo, configID)
  if not okC or type(info) ~= "table" or ns.estSecret(info) then return res end
  for _, treeID in ipairs(info.treeIDs or {}) do
    local okN, ids = pcall(C_Traits.GetTreeNodes, treeID)
    for _, nodeID in ipairs(okN and type(ids) == "table" and ids or {}) do
      local ok, n = pcall(C_Traits.GetNodeInfo, configID, nodeID)
      if ok and type(n) == "table" and not ns.estSecret(n) then
        local noeud = { nodeID = nodeID, entrees = {} }
        for _, entryID in ipairs(n.entryIDs or {}) do
          local spellID, nom = sortDeLEntree(configID, entryID)
          noeud.entrees[#noeud.entrees + 1] = { entryID = entryID, spellID = spellID, nom = nom }
        end
        res[#res + 1] = noeud
      end
    end
  end
  return res
end

-- La table de correspondance des talents, gardée tant que l'arbre ne change pas (ns.arbreSale la rend à refaire).
local cacheArbre = {}
ns.arbreSale = true
local function indexDeLArbre(configID)
  if not ns.arbreSale and cacheArbre.index and cacheArbre.configID == configID then return cacheArbre.index end
  local index = ns.indexArbre(ns.lireArbre(configID))
  -- Un arbre vide (pas encore chargé) n'est pas gardé : on relira au prochain appel.
  if index.nb > 0 then cacheArbre = { configID = configID, index = index }; ns.arbreSale = false end
  return index
end

-- Le prochain talent du build : { etat = "vide" | "sansArbre" | "horsArbre" | "suivant" | "attente" | "fini",
--   nodeID, entryID, nom, rang, rangs, configID, nonReconnus = { noms }, nbNonReconnus, date }.
function ns.infoTalents(classe, speCle, situationVue)
  local build = ns.buildPour(classe, speCle, situationVue)
  if not build then return { etat = "vide" } end
  local date = ns.dateBuild(classe)
  local configID = idConfig()
  if not configID or not (C_Traits and C_Traits.GetNodeInfo) then return { etat = "sansArbre", date = date } end
  -- La table de correspondance ne sert que si une entrée est désignée par son sort ou son nom.
  local index
  for _, e in ipairs(build) do
    if not e.nodeID then index = indexDeLArbre(configID); break end
  end
  local resolu = ns.resoudreBuild(build, index)
  local valides, absents = {}, resolu.nonReconnus
  for _, e in ipairs(resolu.entrees) do
    local rang, maxRangs = rangDuNoeud(configID, e.nodeID, e.entryID)
    if rang ~= nil then
      -- Un rang voulu au-dessus du maximum du nœud (rangs de Classic de mémoire) est ramené à ce maximum.
      if type(maxRangs) == "number" and (e.rangs or 1) > maxRangs then e.rangs = maxRangs end
      valides[#valides + 1] = e
    else absents[#absents + 1] = e.nom or ("nœud " .. tostring(e.nodeID)) end
  end
  local info = { configID = configID, date = date, nonReconnus = absents, nbNonReconnus = #absents }
  -- Aucun talent du build n'existe dans l'arbre du personnage : le build n'est pas fait pour lui.
  if #valides == 0 then info.etat = "horsArbre"; return info end
  local entree, rang, _, bloque = ns.prochainNoeud(valides,
    function(nodeID, e) return rangDuNoeud(configID, nodeID, e.entryID) end,
    function(nodeID) return peutAcheter(configID, nodeID) end)
  if not entree then
    if bloque then
      info.etat = "attente"
      info.nodeID, info.entryID = bloque.nodeID, bloque.entryID
      info.nom = nomDuNoeud(configID, bloque.nodeID, bloque.entryID) or bloque.nom or ("nœud " .. tostring(bloque.nodeID))
    else
      info.etat = "fini"
    end
    return info
  end
  info.etat = "suivant"
  info.nodeID, info.entryID, info.rang, info.rangs = entree.nodeID, entree.entryID, rang, entree.rangs or 1
  info.nom = nomDuNoeud(configID, entree.nodeID, entree.entryID) or entree.nom or ("nœud " .. tostring(entree.nodeID))
  return info
end

-- « Prendre ce talent » : jamais en combat, un seul point, validé tout de suite.
function ns.prendreTalent()
  local dire = ns.reglages.dire
  if InCombatLockdown() then dire("pas de changement de talents en combat.") return end
  if not (C_Traits and C_Traits.PurchaseRank and C_Traits.CommitConfig) then
    dire("le jeu ne laisse pas un addon acheter un talent ici : fais-le dans la fenêtre des talents.")
    return
  end
  -- Le jeu dit lui-même si les talents peuvent changer maintenant (zone, effet, clé mythique…).
  if C_ClassTalents and C_ClassTalents.CanEditTalents then
    local okE, peut, raison = pcall(C_ClassTalents.CanEditTalents)
    if okE and peut == false then
      dire("le jeu ne permet pas de changer de talents maintenant" .. (type(raison) == "string" and raison ~= "" and (" : " .. raison) or "") .. ".")
      return
    end
  end
  local e = ns.construireEtat()
  local t = e.talents
  if t.etat ~= "suivant" then
    dire("pas de talent à prendre : " .. (t.etat == "fini" and "tout le build est pris."
      or (t.etat == "attente" and "le jeu n'en laisse prendre aucun pour l'instant (palier ou points)."
        or "pas de build écrit pour ce personnage.")))
    return
  end
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
  -- C_Traits.CommitConfig prend l'identifiant de la configuration active. (C_ClassTalents.CommitConfig, lui,
  -- attend l'identifiant d'une configuration SAUVEGARDÉE : lui donner celui-ci ne validerait rien.)
  local okV, valide = pcall(C_Traits.CommitConfig, t.configID)
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
  ns.speSale = true
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
          rang = n.currentRank, visible = n.isVisible, groupIDs = n.groupIDs, entrees = {} }
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
  -- Les groupes de l'arbre (Sacré, Protection, Vindicte) et les points dépensés dans chacun.
  local groupes = lireGroupes()
  if groupes then
    sortie.groupes = {}
    for _, g in ipairs(groupes) do
      sortie.groupes[#sortie.groupes + 1] = { groupID = g.groupID, displayName = g.displayName,
        orderIndex = g.orderIndex, depense = g.depense }
    end
  end
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
  e.groupesTalents = ns.infoGroupes(classe) -- points par groupe de l'arbre (Forever), nil sur Retail
  e.speBuild = e.speCle or (e.conseil and e.conseil.cle)
  e.talents = ns.infoTalents(classe, e.speBuild, e.situation)
  e.talents.speBuild, e.talents.situationBuild = e.speBuild, e.situation
  -- Rotation : la spécialisation actuelle, sinon la conseillée.
  e.speRotation = e.speCle or (e.conseil and e.conseil.cle)
  local liste = D.ROTATIONS[classe] and e.speRotation and D.ROTATIONS[classe][e.speRotation]
  if liste then
    local statiques, urgences, vus = {}, {}, {}
    for _, entree in ipairs(liste) do
      local s = ns.sorts[entree.sort]
      if s and entree.urgence then
        -- Les sorts d'urgence ne sont pas dans la rotation : ils sont nommés à part.
        if not vus[entree.sort] then vus[entree.sort] = true; urgences[#urgences + 1] = s.nom end
      elseif s then
        statiques[#statiques + 1] = { sort = entree.sort, texte = entree.texte or s.nom, nom = s.nom }
      end
    end
    e.rotation = {
      liste = liste, lignesStatiques = statiques, urgences = urgences,
      resultat = etatRotation.speCle == e.speRotation and etatRotation.resultat or nil,
      mode = etatRotation.mode or ns.modeEffectif(db and db.modeRotation or 1, false),
      auto = etatRotation.auto, boutons = etatRotation.nbBoutons,
    }
  end
  e.metiers = lireMetiers()
  -- Onglet Compétences : la liste retenue chez le maître, le classement, et deux lectures du jeu faites à la demande.
  e.sorts = ns.sorts
  e.aMaitre = ns.aMaitre(classe)
  e.maitre = ConseillerPerso and ConseillerPerso.maitre or nil
  e.ctxMaitre = ns.contexteMaitre(classe, e.speRotation, ns.sorts)
  e.rangsGrimoire = ns.rangsGrimoire
  e.surBarre = ns.surLaBarre
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

-- Le contour rouge du sort d'urgence : un seul, à part du bleu de la rotation.
local contourUrgence
local function cacherUrgence()
  if contourUrgence then contourUrgence:Hide() end
end

local function montrerUrgence(boutons)
  for _, b in ipairs(boutons) do
    if b.cadre:IsVisible() then
      if not contourUrgence then contourUrgence = nouveauContour(0.95, 0.25, 0.20) end
      local epaisseur = db.tailleContour or 3
      if contourUrgence.cible ~= b.cadre or contourUrgence.epaisseur ~= epaisseur or not contourUrgence:IsShown() then
        contourUrgence:placer(b.cadre, epaisseur)
      end
      return
    end
  end
  cacherUrgence()
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
    cacherUrgence()
    cadreListe:Hide()
    etatRotation.resultat = nil
    return
  end
  -- Le sort d'urgence : contour rouge à part, seulement si l'option est cochée.
  if db.alerteUrgence then
    local u = ns.evaluerUrgence(liste, ns.sorts, ns.apiJeu)
    if u then montrerUrgence(boutonsDuSort(u.cle)) else cacherUrgence() end
  else
    cacherUrgence()
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

-- Ce que le contour a constaté la dernière fois (lu par /cs etat) : "ok", "reglageCoupe", "pasDeFenetre",
-- "fenetreFermee", "rienAEntourer", "boutonIntrouvable", "boutonCache".
ns.diagContour = "pasDeFenetre"

-- Les cadres qui peuvent porter l'arbre de talents, selon la version du jeu (Retail et Forever : PlayerSpellsFrame
-- .TalentsFrame ; anciennes versions : ClassTalentFrame et son onglet). Le premier visible gagne.
local function cadresDeTalents()
  local l = {}
  if PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame then l[#l + 1] = PlayerSpellsFrame.TalentsFrame end
  if ClassTalentFrame then
    if ClassTalentFrame.TalentsTab then l[#l + 1] = ClassTalentFrame.TalentsTab end
    if ClassTalentFrame.TalentsFrame then l[#l + 1] = ClassTalentFrame.TalentsFrame end
    l[#l + 1] = ClassTalentFrame
  end
  return l
end

local function idDuBouton(b)
  if type(b) ~= "table" then return nil end
  if b.GetNodeID then
    local ok, id = pcall(b.GetNodeID, b)
    if ok and id then return id end
  end
  if type(b.nodeInfo) == "table" and b.nodeInfo.ID then return b.nodeInfo.ID end
  return b.nodeID
end

-- Le bouton d'un nœud dans un cadre de talents : la méthode du jeu d'abord, sinon on parcourt les boutons.
-- Le cadre de Forever hérite de TalentFrameBaseTemplate : GetTalentButtonByNodeID existe.
local function boutonDuNoeud(cadre, nodeID)
  if cadre.GetTalentButtonByNodeID then
    local ok, b = pcall(cadre.GetTalentButtonByNodeID, cadre, nodeID)
    if ok and b then return b end
  end
  if cadre.EnumerateAllTalentButtons then
    local trouve
    pcall(function()
      for a, b in cadre:EnumerateAllTalentButtons() do
        if idDuBouton(b) == nodeID then trouve = b; return end
        if idDuBouton(a) == nodeID then trouve = a; return end
      end
    end)
    if trouve then return trouve end
  end
  return nil
end
ns.boutonDuNoeud = boutonDuNoeud

local function majContourTalent()
  if not (db and db.actif and db.contourTalent) then ns.diagContour = "reglageCoupe"; contourTalent:Hide() return end
  local cadre, existe
  for _, c in ipairs(cadresDeTalents()) do
    existe = true
    if c.IsVisible and c:IsVisible() then cadre = c; break end
  end
  if not cadre then ns.diagContour = existe and "fenetreFermee" or "pasDeFenetre"; contourTalent:Hide() return end
  if ns.talentsSale or not talentCache then
    ns.talentsSale = false
    local e = ns.construireEtat()
    talentCache = e.talents
  end
  if talentCache.etat ~= "suivant" then ns.diagContour = "rienAEntourer"; contourTalent:Hide() return end
  local bouton = boutonDuNoeud(cadre, talentCache.nodeID)
  if not bouton then ns.diagContour = "boutonIntrouvable"; contourTalent:Hide() return end
  if bouton.IsVisible and not bouton:IsVisible() then ns.diagContour = "boutonCache"; contourTalent:Hide() return end
  ns.diagContour = "ok"
  if contourTalent.cible ~= bouton or not contourTalent:IsShown() then contourTalent:placer(bouton, 3) end
end

-- ---------------------------------------------------------------------------
-- Compétences : le maître de classe, la barre d'action, les rappels
-- ---------------------------------------------------------------------------
-- Le jeu ne donne la liste des sorts du maître de classe que fenêtre du maître ouverte (GetNumTrainerServices,
-- GetTrainerServiceInfo, GetTrainerServiceCost, événements TRAINER_SHOW et TRAINER_UPDATE ; la fenêtre est
-- ClassTrainerFrame, avec une liste défilante ScrollBox dont chaque ligne est un bouton : GetID() = numéro du service).
-- Conseiller retient cette liste par personnage (ConseillerPerso.maitre) à chaque visite. Il ne l'écrit jamais dans un
-- cadre du jeu, n'achète rien et ne pose aucun sort sur une barre.

-- Le jeu a-t-il un maître de classe ? (Forever : oui ; Retail : les sorts s'apprennent tout seuls.)
function ns.aMaitre(classe)
  if type(GetNumTrainerServices) ~= "function" or type(GetTrainerServiceInfo) ~= "function" then return false end
  if ConseillerPerso and ConseillerPerso.maitre then return true end
  return ns.infoGroupes(classe) ~= nil
end

-- Les rangs du grimoire (nil quand le jeu ne donne pas le grimoire).
function ns.rangsGrimoire()
  local ok, liste = pcall(ns.apiJeu.grimoire)
  if not ok or type(liste) ~= "table" then return nil end
  return ns.indexRangsGrimoire(liste)
end

-- Le sort est-il sur une barre d'action ? true / false, ou nil quand on ne peut pas le savoir (pas de barre lisible).
function ns.surLaBarre(cle)
  local s = ns.sorts[cle]
  if not s then return nil end
  if #boutonsDuSort(cle) > 0 then return true end
  local lu = false
  if ns.apiJeu.slotsDuSort then
    local ok, l = pcall(ns.apiJeu.slotsDuSort, s.id)
    if ok and type(l) == "table" and not ns.estSecret(l) then
      lu = true
      if #l > 0 then return true end
    end
  end
  if lu or #listeBoutons() > 0 then return false end
  return nil
end

-- Le contexte du classement (rotation, urgences, entretien, sorts à ignorer) de ta spécialisation, gardé tant que
-- la classe, la spécialisation et les sorts résolus ne changent pas.
local cacheCtx = {}
local function contexteDuMaitre()
  local classe = classeJoueur()
  local _, spe = listeDeRotation()
  if cacheCtx.ctx and cacheCtx.classe == classe and cacheCtx.spe == spe and cacheCtx.sorts == ns.sorts then
    return cacheCtx.ctx
  end
  local ctx = ns.contexteMaitre(classe, spe, ns.sorts)
  cacheCtx = { classe = classe, spe = spe, sorts = ns.sorts, ctx = ctx }
  return ctx
end

-- À chaque visite chez le maître de classe : retenir sa liste (nom, rang, niveau requis, prix, état). Ni un maître
-- de métier ni un maître de familier ; une liste vide n'écrase pas la précédente.
local function retenirMaitre()
  if not ConseillerPerso then return end
  if not (GetNumTrainerServices and GetTrainerServiceInfo) then return end
  if C_Trainer and C_Trainer.GetTrainerType and Enum and Enum.TrainerType then
    local ok, t = pcall(C_Trainer.GetTrainerType)
    if ok and t ~= nil and not ns.estSecret(t) and t ~= Enum.TrainerType.General then return end
  end
  if IsTradeskillTrainer then
    local ok, metier = pcall(IsTradeskillTrainer)
    if ok and metier == true then return end
  end
  local okN, n = pcall(GetNumTrainerServices)
  if not okN or type(n) ~= "number" or ns.estSecret(n) then return end
  local services = {}
  for i = 1, n do
    local ok, nom, typeService, _, niveau, sous = pcall(GetTrainerServiceInfo, i)
    if ok then
      local prix, estMetier
      if GetTrainerServiceCost then
        local okC, p, m = pcall(GetTrainerServiceCost, i)
        if okC then prix, estMetier = p, m end
      end
      local s = ns.serviceMaitre(nom, typeService, niveau, sous, prix, estMetier)
      if s then services[#services + 1] = s end
    end
  end
  if #services == 0 then return end
  ConseillerPerso.maitre = { services = services, niveau = UnitLevel("player"),
    date = date and date("%d/%m/%Y") or nil }
  if ns.majFenetre then ns.majFenetre() end
end
ns.retenirMaitre = retenirMaitre

-- Les marques dans la fenêtre du maître : un petit carré doré (indispensable) ou argenté (utile) à nous, posé par-dessus
-- le coin de l'icône de la ligne. On LIT la fenêtre du jeu (la liste défilante, le numéro de chaque ligne) et on ancre
-- notre cadre sur la ligne : aucun champ ni aucun attribut d'un cadre du jeu n'est écrit, aucune fonction n'est remplacée.
-- Elles sont replacées dix fois par seconde tant que la fenêtre est ouverte (la liste recycle ses lignes quand on défile).
local COULEURS_MARQUES = { indispensable = { 1, 0.82, 0 }, utile = { 0.82, 0.84, 0.90 } }
local marquesMaitre = {}
-- Ce que les marques ont constaté la dernière fois (lu par /cs etat) : "ok", "reglageCoupe", "pasDeFenetre",
-- "listeIntrouvable", "erreur".
ns.diagMarques = "pasDeFenetre"

local function nouvelleMarque()
  local f = CreateFrame("Frame", nil, UIParent)
  f:SetFrameStrata("HIGH")
  f:EnableMouse(false)
  f:SetSize(14, 14)
  local fond = f:CreateTexture(nil, "BACKGROUND")
  fond:SetAllPoints()
  fond:SetColorTexture(0, 0, 0, 0.85)
  local coeur = f:CreateTexture(nil, "ARTWORK")
  coeur:SetPoint("TOPLEFT", 2, -2)
  coeur:SetPoint("BOTTOMRIGHT", -2, 2)
  f.coeur = coeur
  f:Hide()
  function f:placer(cible, classement)
    local c = COULEURS_MARQUES[classement] or COULEURS_MARQUES.utile
    self.cible, self.classement = cible, classement
    self.coeur:SetColorTexture(c[1], c[2], c[3], 1)
    self:ClearAllPoints()
    self:SetPoint("TOPLEFT", cible, "TOPLEFT", 2, -2)
    local niveau = cible.GetFrameLevel and cible:GetFrameLevel()
    self:SetFrameLevel((type(niveau) == "number" and niveau or 1) + 5)
    self:Show()
  end
  return f
end

local function cacherMarques()
  for _, m in ipairs(marquesMaitre) do m:Hide() end
end

local function majMarquesMaitre()
  if not (db and db.actif and db.marquesMaitre) then ns.diagMarques = "reglageCoupe"; cacherMarques() return end
  local cadre = _G.ClassTrainerFrame
  if not (cadre and cadre.IsVisible and cadre:IsVisible()) then ns.diagMarques = "pasDeFenetre"; cacherMarques() return end
  local boite = cadre.ScrollBox
  if not (boite and boite.ForEachFrame and GetTrainerServiceInfo) then ns.diagMarques = "listeIntrouvable"; cacherMarques() return end
  local ctx = contexteDuMaitre()
  local n = 0
  local ok = pcall(boite.ForEachFrame, boite, function(bouton)
    if type(bouton) ~= "table" or not bouton.GetID then return end
    if bouton.IsVisible and not bouton:IsVisible() then return end
    -- Une ligne de catégorie n'est pas un sort.
    if bouton.buttonContext ~= nil and bouton.buttonContext ~= "ButtonContext_TrainerUISkill" then return end
    local okI, nom, typeService, _, niveau, sous = pcall(GetTrainerServiceInfo, bouton:GetID())
    if not okI then return end
    local s = ns.serviceMaitre(nom, typeService, niveau, sous, nil, false)
    if not s or s.etat == "appris" then return end
    local classement = ns.classerService(s, ctx).classement
    if classement ~= "indispensable" and classement ~= "utile" then return end
    n = n + 1
    local m = marquesMaitre[n]
    if not m then m = nouvelleMarque(); marquesMaitre[n] = m end
    if m.cible ~= bouton or m.classement ~= classement or not m:IsShown() then m:placer(bouton, classement) end
  end)
  for i = n + 1, #marquesMaitre do marquesMaitre[i]:Hide() end
  if ok then ns.diagMarques = "ok" else ns.diagMarques = "erreur"; cacherMarques() end
end
ns.majMarquesMaitre = majMarquesMaitre

-- Rappel : un sort de ta rotation que tu connais et qui n'est sur aucune barre. Un message par sort et par session,
-- hors combat, avec un anti-rebond (les barres changent des dizaines de fois au chargement).
local rappelsBarreDits = {}
local barreEnAttente = false

local function verifierBarre()
  barreEnAttente = false
  if not (db and db.actif and db.rappelBarre) then return end
  if InCombatLockdown and InCombatLockdown() then return end
  local classe = classeJoueur()
  local _, spe = listeDeRotation()
  if not (classe and spe) then return end
  local absents = ns.sortsAbsentsDeLaBarre(classe, spe, ns.sorts, ns.surLaBarre, rappelsBarreDits)
  for i, a in ipairs(absents) do
    if i > 3 then break end -- pas plus de trois messages d'un coup : les autres viendront à la vérification suivante
    rappelsBarreDits[a.cle] = true
    ns.reglages.dire(ns.texteSortAbsent(a.nom))
  end
end
ns.verifierBarre = verifierBarre

local function demanderVerifBarre(delai)
  if barreEnAttente or not (db and db.actif and db.rappelBarre) then return end
  if not (C_Timer and C_Timer.After) then return end
  barreEnAttente = true
  C_Timer.After(delai or 3, function()
    local ok, err = pcall(verifierBarre)
    if not ok then barreEnAttente = false; ns.derniereErreur = tostring(err) end
  end)
end

-- Rappel : à la montée de niveau, les sorts indispensables du maître de classe (voir ns.texteRappelNiveau).
local function rappelNiveau(niveau)
  if not (db and db.actif and db.rappelNiveau) then return end
  local classe = classeJoueur()
  if not ns.aMaitre(classe) then return end
  if type(niveau) ~= "number" or ns.estSecret(niveau) then niveau = UnitLevel("player") end
  local perso = ConseillerPerso and ConseillerPerso.maitre
  local texte = ns.texteRappelNiveau(niveau, perso and perso.services, contexteDuMaitre(), ns.rangsGrimoire())
  if texte then ns.reglages.dire(texte) end
end
ns.rappelNiveau = rappelNiveau

ns.contexteDuMaitre = contexteDuMaitre

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
    { cle = "alerteUrgence", libelle = "Signaler le sort d'urgence quand ta vie est basse",
      dependDe = "rotation",
      aide = "Un contour rouge, à part de la rotation, sur ton sort de soin ou de défense." },
    { titre = "Talents" },
    { cle = "contourTalent", libelle = "Entourer le prochain talent dans la fenêtre des talents",
      aide = "Un contour vert sur le talent conseillé, quand un build est écrit pour ta spécialisation." },
    { titre = "Compétences" },
    { cle = "rappelNiveau", libelle = "Rappeler le maître de classe à la montée de niveau",
      aide = "Un message dans le chat quand des sorts indispensables deviennent accessibles chez ton maître de classe (la liste est retenue à chaque visite)." },
    { cle = "marquesMaitre", libelle = "Marquer les sorts utiles dans la fenêtre du maître de classe",
      aide = "Un petit carré doré sur les sorts indispensables à ta rotation, argenté sur les sorts utiles. Rien n'est acheté à ta place." },
    { cle = "rappelBarre", libelle = "Prévenir quand un sort de la rotation n'est sur aucune barre",
      aide = "Un message dans le chat, une fois par sort et par session, hors combat. Conseiller ne pose rien sur ta barre." },
    { titre = "Icône" },
    { cle = "minimap", libelle = "Icône à part autour de la minimap",
      aide = "En plus de la ligne dans l'icône commune des addons de Valentin." },
  },
  boutons = {
    { texte = "Ouvrir le Conseiller", aide = "La fenêtre avec les six onglets.", action = function()
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
    ConseillerPerso = ConseillerPerso or {} -- sauvegarde propre à ce personnage (liste du maître de classe)
    placerListe()
    pcall(resoudre)
    pcall(majGroupe)
    demanderVerifBarre(8)
  end,
  surChangement = function()
    if db and not (db.actif and db.rotation) then cacherContours(); cacherUrgence(); cadreListe:Hide() end
    if db and not db.alerteUrgence then cacherUrgence() end
    if db and not (db.actif and db.marquesMaitre) then cacherMarques() end
    if db and db.actif and db.rappelBarre then demanderVerifBarre(3) end
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
  "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED", "TRAINER_SHOW", "TRAINER_UPDATE" }

local ecouteur = CreateFrame("Frame")
local function inscrire(liste)
  for ev in pairs(liste) do pcall(ecouteur.RegisterEvent, ecouteur, ev) end
end
inscrire(EVENEMENTS_GROUPE); inscrire(EVENEMENTS_BARRES); inscrire(EVENEMENTS_SPE); inscrire(EVENEMENTS_TALENTS)
for _, ev in ipairs(AUTRES) do pcall(ecouteur.RegisterEvent, ecouteur, ev) end

ecouteur:SetScript("OnEvent", function(_, ev, arg1)
  if not db then return end
  -- Le maître de classe : retenir sa liste à chaque visite et à chaque changement de sa liste.
  if ev == "TRAINER_SHOW" or ev == "TRAINER_UPDATE" then
    local ok, err = pcall(retenirMaitre)
    if not ok then ns.derniereErreur = tostring(err) end
    return
  end
  if ev == "PLAYER_LEVEL_UP" then
    local ok, err = pcall(rappelNiveau, arg1)
    if not ok then ns.derniereErreur = tostring(err) end
  end
  -- Un sort sorti des barres ou appris : on revérifie la barre, une fois que ça s'est calmé.
  if ev == "SPELLS_CHANGED" or ev == "ACTIONBAR_SLOT_CHANGED" or ev == "PLAYER_REGEN_ENABLED" then demanderVerifBarre(3) end
  if EVENEMENTS_TALENTS[ev] or EVENEMENTS_SPE[ev] or ev == "PLAYER_LEVEL_UP" or ev == "PLAYER_ENTERING_WORLD" then ns.speSale = true end
  if ev == "SPELLS_CHANGED" or EVENEMENTS_SPE[ev] or ev == "PLAYER_ENTERING_WORLD" then pcall(resoudre) end
  if EVENEMENTS_GROUPE[ev] or EVENEMENTS_SPE[ev] then pcall(majGroupe) end
  if EVENEMENTS_BARRES[ev] then ns.cacheBoutonsSale = true end
  if EVENEMENTS_TALENTS[ev] or EVENEMENTS_SPE[ev] then ns.talentsSale = true; ns.arbreSale = true end
  if ev == "PLAYER_LEVEL_UP" or ev == "PLAYER_ENTERING_WORLD" then ns.arbreSale = true end
  if ns.majFenetre and (EVENEMENTS_GROUPE[ev] or EVENEMENTS_SPE[ev] or EVENEMENTS_TALENTS[ev] or ev == "PLAYER_LEVEL_UP"
    or ev == "SKILL_LINES_CHANGED") then
    ns.majFenetre()
  end
end)

-- Mise à jour limitée : la rotation 10 fois par seconde (un temps de recharge qui finit ne
-- donne pas d'événement), le contour des talents 2 fois par seconde, les marques de la fenêtre du maître 10 fois
-- par seconde (rien à faire tant que cette fenêtre est fermée).
local pilote = CreateFrame("Frame")
local ecoule, ecouleTalents, ecouleMarques = 0, 0, 0
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
  ecouleMarques = ecouleMarques + dt
  if ecouleMarques >= 0.1 then
    ecouleMarques = 0
    local ok, err = pcall(majMarquesMaitre)
    if not ok then ns.derniereErreur = tostring(err) end
  end
end)

-- ---------------------------------------------------------------------------
-- Commandes
-- ---------------------------------------------------------------------------

local function dire(t) ns.reglages.dire(t) end

local TEXTES_CONTOUR = {
  ok = "contour vert posé sur le talent.",
  reglageCoupe = "contour vert coupé dans les réglages.",
  pasDeFenetre = "contour vert : la fenêtre des talents du jeu n'a pas été trouvée (ouvre-la, puis refais /cs etat).",
  fenetreFermee = "contour vert : la fenêtre des talents est fermée (ouvre-la, puis refais /cs etat).",
  rienAEntourer = "contour vert : aucun talent à entourer pour l'instant.",
  boutonIntrouvable = "bouton du talent introuvable dans la fenêtre.",
  boutonCache = "le bouton du talent est caché dans la fenêtre (autre onglet ou zone défilée).",
}

local TEXTES_MARQUES = {
  ok = "posées (ou rien à marquer dans la liste).",
  reglageCoupe = "coupées dans les réglages.",
  pasDeFenetre = "la fenêtre du maître est fermée.",
  listeIntrouvable = "la liste défilante de la fenêtre du maître n'a pas été trouvée.",
  erreur = "la lecture de la liste a échoué.",
}

local function etatEnTexte()
  ns.speSale = true
  local e = ns.construireEtat()
  local n = 0
  for _ in pairs(ns.sorts) do n = n + 1 end
  dire(string.format("%s niveau %s, %s, spécialisation %s, situation %s%s. Sorts connus : %d. Mode : %s%s.",
    e.classeNom, tostring(e.niveau), tostring(e.raceNom), tostring(e.speNom or "inconnue"), e.situation,
    ns.situationForcee and " (forcée)" or "", n, etatRotation.mode or "?", etatRotation.auto and " (auto)" or ""))
  -- Les points par groupe de l'arbre (Forever), et la spécialisation qui en découle.
  if e.groupesTalents then
    local morceaux = {}
    for _, p in ipairs(e.groupesTalents.points) do
      morceaux[#morceaux + 1] = string.format("%s %d", tostring(p.nom or ("groupe " .. p.rang)), p.depense)
    end
    dire("points par groupe de talents : " .. table.concat(morceaux, ", ") .. " ; spécialisation détectée : "
      .. (e.speCle and tostring(e.speNom or e.speCle) or (e.groupesTalents.egalite and "aucune (égalité)" or "aucune (pas de points)")) .. ".")
  else
    dire("spécialisation détectée par le jeu : " .. tostring(e.speNom or "aucune") .. " (pas de groupes de talents).")
  end
  local t = e.talents
  if t then
    local nbBuild = 0
    local b = ns.buildPour(e.classe, t.speBuild, t.situationBuild)
    if b then nbBuild = #b end
    dire(string.format("build utilisé : %s, %s (%d entrées).", tostring(t.speBuild or "aucun"), tostring(t.situationBuild or "?"), nbBuild))
    if t.etat == "suivant" then
      dire(string.format("prochain talent : %s (nœud %s), rang %d sur %d.", tostring(t.nom), tostring(t.nodeID), t.rang or 0, t.rangs or 1))
    elseif t.etat == "attente" then
      dire(string.format("prochain talent bloqué : %s (nœud %s), le jeu ne le laisse pas prendre pour l'instant.", tostring(t.nom), tostring(t.nodeID)))
    elseif t.etat == "fini" then dire("prochain talent : aucun, tout le build est pris.")
    elseif t.etat == "horsArbre" then dire("prochain talent : aucun, le build ne correspond pas à l'arbre.")
    elseif t.etat == "sansArbre" then dire("prochain talent : le jeu ne donne pas l'arbre (configuration active introuvable).")
    else dire("prochain talent : pas de build écrit pour ce personnage.") end
    if t.etat == "suivant" or t.etat == "attente" then
      dire(TEXTES_CONTOUR[ns.diagContour] or TEXTES_CONTOUR.pasDeFenetre)
    end
  end
  if t and (t.nbNonReconnus or 0) > 0 then
    dire(string.format("talents du build non reconnus (%d) : %s. Fais /cs export puis /reload pour qu'on corrige leurs noms.",
      t.nbNonReconnus, table.concat(t.nonReconnus, ", ")))
  end
  -- Le maître de classe : ce qui a été retenu à la dernière visite, et les marques.
  if ns.aMaitre(e.classe) then
    local m = ConseillerPerso and ConseillerPerso.maitre
    if m and m.services then
      local utiles = 0
      for _, s in ipairs(m.services) do
        if s.etat ~= "appris" and ns.classerService(s, e.ctxMaitre).classement ~= "attendre" then utiles = utiles + 1 end
      end
      dire(string.format("maître de classe : liste retenue%s, %d services dont %d indispensables ou utiles.",
        m.date and (" le " .. m.date) or "", #m.services, utiles))
    else
      dire("maître de classe : pas encore de liste retenue (va voir ton maître de classe une fois).")
    end
    dire("marques dans la fenêtre du maître : " .. (TEXTES_MARQUES[ns.diagMarques] or TEXTES_MARQUES.pasDeFenetre))
  else
    dire("maître de classe : ce jeu n'en a pas (les sorts s'apprennent tout seuls).")
  end
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
