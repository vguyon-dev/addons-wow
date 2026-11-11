-- ============================================================================
-- Tenues : enregistre ce que tu portes (combat, pêche, ville…) et change de tenue
-- d'un clic ou d'une touche.
--
-- Une tenue = un nom et une liste { [emplacement] = lien de l'objet } pour les
-- emplacements 1 à 19. Elle peut être PARTIELLE (pêche : canne, chapeau, bottes) :
-- seuls ses emplacements changent, le reste de ta tenue ne bouge pas.
--
--   /tenue : la fenêtre            /tenue <nom> : met la tenue (début de nom accepté)
--   /tenue enregistrer <nom>       /tenue retour : remet ce qui était porté avant
--   /tenue liste, /tenue options, /tenue aide
--   Touches : « Tenue 1 » à « Tenue 5 » (Échap > Options > Raccourcis, ou l'onglet
--   Touches des réglages) : la touche n met la n-ième tenue de la liste.
--
-- Jamais en combat : le jeu refuse de changer d'équipement. La demande est gardée et la
-- tenue se met à la fin du combat. Les pièces se mettent une par une (0,1 s entre deux)
-- pour laisser le jeu suivre. Aucune action sans ton clic, ta touche ou ta commande ; la
-- seule exception voulue : le mode pêche de Métiers auto appelle Tenues_ModePeche.
--
-- Le fichier a deux parties : la logique pure (testée hors jeu, tests/Tenues_simu.lua)
-- puis tout ce qui parle au jeu.
-- ============================================================================

local NOM_ADDON, ns = ...

local DEFAUTS = {
  actif = true,
  prevenirManque = true, -- dire quelles pièces manquent (ni portées ni dans les sacs)
  modePeche = true,      -- mettre la tenue « Pêche » avec le mode pêche de Métiers auto
  minimap = false,
}

-- ---------------------------------------------------------------------------
-- Partie « logique pure » : aucune fonction du jeu, donc testable hors jeu.
-- ---------------------------------------------------------------------------

local PREMIER_EMPLACEMENT, DERNIER_EMPLACEMENT = 1, 19
ns.DERNIER_EMPLACEMENT = DERNIER_EMPLACEMENT

-- Les emplacements d'équipement du jeu (0, les munitions, n'est pas géré).
ns.NOMS_EMPLACEMENTS = {
  [1] = "Tête", [2] = "Cou", [3] = "Épaules", [4] = "Chemise", [5] = "Torse", [6] = "Taille",
  [7] = "Jambes", [8] = "Pieds", [9] = "Poignets", [10] = "Mains", [11] = "Anneau 1", [12] = "Anneau 2",
  [13] = "Bijou 1", [14] = "Bijou 2", [15] = "Dos", [16] = "Main droite", [17] = "Main gauche",
  [18] = "Distance", [19] = "Tabard",
}

-- Les emplacements jumeaux : une pièce portée dans l'autre emplacement de la paire compte comme portée
-- (deux anneaux, deux bijoux), sinon on les échangerait pour rien.
local JUMEAUX = { [11] = 12, [12] = 11, [13] = 14, [14] = 13 }

-- Les noms qu'une tenue ne peut pas porter : ce sont des mots de la commande /tenue.
local MOTS_RESERVES = { retour = true, liste = true, options = true, aide = true, enregistrer = true }

local LONGUEUR_NOM = 24

-- Un texte comparable : sans accents ni majuscules, apostrophes et tirets en espaces.
local ACCENTS = {
  { "é", "e" }, { "è", "e" }, { "ê", "e" }, { "ë", "e" }, { "à", "a" }, { "â", "a" }, { "î", "i" }, { "ï", "i" },
  { "ô", "o" }, { "û", "u" }, { "ù", "u" }, { "ü", "u" }, { "ç", "c" }, { "œ", "oe" },
  { "É", "e" }, { "È", "e" }, { "Ê", "e" }, { "Ë", "e" }, { "À", "a" }, { "Â", "a" }, { "Ç", "c" }, { "Î", "i" },
  { "Ï", "i" }, { "Ô", "o" }, { "Û", "u" }, { "Ù", "u" }, { "Ü", "u" }, { "Œ", "oe" },
}
local function sansAccents(t)
  t = tostring(t or "")
  for _, p in ipairs(ACCENTS) do t = t:gsub(p[1], p[2]) end
  t = t:gsub("’", "'"):lower()
  t = t:gsub("[%-']", " "):gsub("%s+", " ")
  t = t:gsub("^ ", ""):gsub(" $", "")
  return t
end
ns.sansAccents = sansAccents

-- Le numéro d'objet d'un lien (« |Hitem:12345:… »), d'un « item:12345 » ou d'un nombre, ou nil.
function ns.numeroObjet(lien)
  if type(lien) == "number" then return lien end
  if type(lien) ~= "string" then return nil end
  return tonumber(lien:match("item:(%d+)"))
end

-- Ce qui identifie vraiment l'objet dans un lien : « item:123:0:… », sans la couleur ni le nom affiché.
local function charge(lien)
  if type(lien) ~= "string" then return nil end
  return lien:match("|H(item:[^|]*)|h") or lien:match("^(item:[%d:%-]*)$")
end

-- Deux liens désignent-ils la même pièce ? Le lien exact, sinon le même numéro d'objet : un lien
-- change avec le niveau du personnage ou une amélioration, la pièce reste la même.
local function memePiece(a, b)
  if type(a) ~= "string" or type(b) ~= "string" then return false end
  if a == b then return true end
  local ca, cb = charge(a), charge(b)
  if ca and cb and ca == cb then return true end
  local na, nb = ns.numeroObjet(a), ns.numeroObjet(b)
  return na ~= nil and na == nb
end
ns.memePiece = memePiece

local function memeLienExact(a, b)
  if type(a) ~= "string" or type(b) ~= "string" then return false end
  if a == b then return true end
  local ca, cb = charge(a), charge(b)
  return ca ~= nil and ca == cb
end

-- Les emplacements d'une tenue, dans l'ordre (1, 2, … 19 : la main droite avant la main gauche).
local function emplacementsTries(pieces)
  local liste = {}
  if type(pieces) ~= "table" then return liste end
  for slot = PREMIER_EMPLACEMENT, DERNIER_EMPLACEMENT do
    if type(pieces[slot]) == "string" and pieces[slot] ~= "" then liste[#liste + 1] = slot end
  end
  return liste
end
ns.emplacementsTries = emplacementsTries

function ns.nbPieces(tenue)
  return tenue and #emplacementsTries(tenue.pieces) or 0
end

function ns.copierPieces(pieces)
  local copie = {}
  if type(pieces) ~= "table" then return copie end
  for slot = PREMIER_EMPLACEMENT, DERNIER_EMPLACEMENT do
    if type(pieces[slot]) == "string" and pieces[slot] ~= "" then copie[slot] = pieces[slot] end
  end
  return copie
end

-- Quelles pièces de la tenue sont déjà portées ? etat[emplacement] = vrai.
-- D'abord à leur propre emplacement ; ensuite dans l'emplacement jumeau s'il n'est pas déjà pris
-- (deux anneaux échangés ne demandent aucun changement).
-- Rend aussi pris[emplacement] = vrai pour chaque emplacement PORTÉ dont la pièce compte déjà pour la tenue.
local function dejaPortees(pieces, porte)
  local etat, pris = {}, {}
  porte = type(porte) == "table" and porte or {}
  local slots = emplacementsTries(pieces)
  for _, slot in ipairs(slots) do
    if memePiece(pieces[slot], porte[slot]) then etat[slot] = true; pris[slot] = true end
  end
  for _, slot in ipairs(slots) do
    if not etat[slot] then
      local jumeau = JUMEAUX[slot]
      if jumeau and not pris[jumeau] and memePiece(pieces[slot], porte[jumeau]) then
        etat[slot] = true
        pris[jumeau] = true
      end
    end
  end
  return etat, pris
end

-- La tenue est-elle portée ? Toutes ses pièces le sont (une tenue vide ne l'est jamais).
function ns.estPortee(tenue, porte)
  local pieces = tenue and tenue.pieces
  local slots = emplacementsTries(pieces)
  if #slots == 0 then return false end
  local etat = dejaPortees(pieces, porte)
  for _, slot in ipairs(slots) do
    if not etat[slot] then return false end
  end
  return true
end

-- Cherche, parmi les objets des sacs encore libres, celui qui correspond au lien. exact = vrai : le même
-- lien seulement ; sinon le même numéro d'objet. Rend l'indice dans sacs, ou nil.
local function chercherDansSacs(lien, sacs, utilises, exact)
  for i, e in ipairs(sacs) do
    if not utilises[i] and type(e) == "table" and type(e.lien) == "string" then
      if exact then
        if memeLienExact(lien, e.lien) then return i end
      elseif memePiece(lien, e.lien) then
        return i
      end
    end
  end
end

-- Le plan pour mettre une tenue.
--   tenue : { nom, pieces = { [emplacement] = lien } }
--   porte : { [emplacement] = lien } ce qui est porté
--   sacs  : { { sac, case, lien }, … } les objets des sacs
-- Rend { aEquiper = { { emplacement, sac, case, lien }, … } (dans l'ordre : main droite avant main
-- gauche), manquants = { liens }, dejaPortes = n, inverses = n (armes portées dans l'autre main),
-- etat = { [emplacement] = "porte" | "sac" | "manque" | "inverse" } }.
-- Une pièce des sacs destinée à un anneau ou un bijou va sur l'emplacement de la paire dont l'occupant
-- n'est pas déjà une pièce voulue : l'« emplacement » de l'ordre peut donc être le jumeau.
-- Une même pièce des sacs n'est jamais attribuée à deux emplacements. Le lien de l'ordre est celui de
-- la pièce trouvée dans le sac (pas celui qui était enregistré).
function ns.plan(tenue, porte, sacs)
  local pieces = tenue and tenue.pieces
  sacs = type(sacs) == "table" and sacs or {}
  local slots = emplacementsTries(pieces)
  local deja, pris = dejaPortees(pieces, porte)
  porte = type(porte) == "table" and porte or {}
  local resultat = { aEquiper = {}, manquants = {}, dejaPortes = 0, inverses = 0, etat = {} }
  local utilises, trouve = {}, {}
  -- Deux passes : les liens exacts d'abord, pour qu'une pièce ressemblante ne prenne pas la place d'une autre.
  for passe = 1, 2 do
    for _, slot in ipairs(slots) do
      if not deja[slot] and not trouve[slot] then
        local i = chercherDansSacs(pieces[slot], sacs, utilises, passe == 1)
        if i then utilises[i] = true; trouve[slot] = i end
      end
    end
  end
  for _, slot in ipairs(slots) do
    if deja[slot] then
      resultat.dejaPortes = resultat.dejaPortes + 1
      resultat.etat[slot] = "porte"
    elseif trouve[slot] then
      local e = sacs[trouve[slot]]
      -- Si l'occupant actuel de cet emplacement compte déjà pour son jumeau (deux anneaux : B voulu
      -- en 12 et porté en 11), on ne le chasse pas : la pièce va sur le jumeau, qui n'est pas pris.
      local cible = slot
      local jumeau = JUMEAUX[slot]
      if pris[slot] and jumeau and not pris[jumeau] then cible = jumeau end
      resultat.aEquiper[#resultat.aEquiper + 1] = { emplacement = cible, sac = e.sac, case = e.case, lien = e.lien }
      resultat.etat[slot] = "sac"
    elseif (slot == 16 or slot == 17) and not pris[33 - slot] and memePiece(pieces[slot], porte[33 - slot]) then
      -- Les deux mains échangées : l'arme voulue est portée dans l'autre main. Rien à chercher dans
      -- les sacs, et ce n'est pas une pièce manquante (l'addon n'échange pas les mains tout seul).
      pris[33 - slot] = true
      resultat.inverses = resultat.inverses + 1
      resultat.etat[slot] = "inverse"
    else
      resultat.manquants[#resultat.manquants + 1] = pieces[slot]
      resultat.etat[slot] = "manque"
    end
  end
  return resultat
end

-- Ce qu'il faudra pouvoir remettre : ce qui est porté dans les emplacements que le plan change. Si la main
-- droite change, la main gauche est retenue aussi : une arme à deux mains la renvoie dans les sacs.
function ns.precedente(plan, porte)
  local p = {}
  porte = type(porte) == "table" and porte or {}
  for _, e in ipairs(plan and plan.aEquiper or {}) do
    if porte[e.emplacement] then p[e.emplacement] = porte[e.emplacement] end
    if e.emplacement == 16 and porte[17] then p[17] = porte[17] end
  end
  return p
end

-- Une suite de tenue (interrompue par un combat) garde ce qui avait déjà été retenu : seuls les
-- emplacements nouveaux s'ajoutent.
function ns.fusionnerPrecedente(ancienne, nouvelle)
  local p = ns.copierPieces(ancienne)
  for slot, lien in pairs(ns.copierPieces(nouvelle)) do
    if p[slot] == nil then p[slot] = lien end
  end
  return p
end

-- Le nombre de lettres d'un texte (un « é » compte pour un).
local function nbLettres(t) return (select(2, t:gsub("[^\128-\191]", ""))) end

-- Un nom de tenue utilisable : rend le nom nettoyé, ou nil et le message à dire.
function ns.nomValide(nom, tenues)
  nom = tostring(nom or ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
  if nom == "" then return nil, "donne un nom à la tenue." end
  if nom:find("|", 1, true) then return nil, "le nom ne peut pas contenir le caractère |." end
  if nbLettres(nom) > LONGUEUR_NOM then return nil, "le nom est trop long (" .. LONGUEUR_NOM .. " lettres au plus)." end
  local simple = sansAccents(nom)
  if MOTS_RESERVES[simple] then return nil, "« " .. nom .. " » est un mot de la commande /tenue : choisis un autre nom." end
  for _, t in ipairs(tenues or {}) do
    if sansAccents(t.nom) == simple then return nil, "une tenue s'appelle déjà « " .. t.nom .. " »." end
  end
  return nom
end

-- La tenue qui correspond au texte tapé : le nom exact (sans accents ni majuscules), sinon un début de nom
-- à condition qu'il soit unique. Rend la tenue et son indice ; si plusieurs conviennent : nil et la liste de
-- leurs noms ; si aucune : nil.
function ns.trouverTenue(tenues, texte)
  local q = sansAccents(texte)
  if q == "" or type(tenues) ~= "table" then return nil end
  for i, t in ipairs(tenues) do
    if sansAccents(t.nom) == q then return t, i end
  end
  local debuts = {}
  for i, t in ipairs(tenues) do
    if sansAccents(t.nom):sub(1, #q) == q then debuts[#debuts + 1] = { t = t, i = i } end
  end
  if #debuts == 1 then return debuts[1].t, debuts[1].i end
  if #debuts > 1 then
    local noms = {}
    for _, d in ipairs(debuts) do noms[#noms + 1] = d.t.nom end
    return nil, noms
  end
  return nil
end

-- La tenue de pêche : celle dont le nom est « pêche » (sans accents ni majuscules).
function ns.tenuePeche(tenues)
  for _, t in ipairs(tenues or {}) do
    if sansAccents(t.nom) == "peche" then return t end
  end
end

-- Une nouvelle tenue à partir de ce qui est porté. coches : { [emplacement] = vrai } pour les emplacements
-- choisis (pas de table = tous).
-- Rend la tenue, ou nil et le message à dire.
function ns.fabriquerTenue(nom, porte, coches)
  local pieces = {}
  porte = type(porte) == "table" and porte or {}
  for slot = PREMIER_EMPLACEMENT, DERNIER_EMPLACEMENT do
    local voulu = type(coches) ~= "table" or coches[slot] == true
    if voulu and type(porte[slot]) == "string" and porte[slot] ~= "" then pieces[slot] = porte[slot] end
  end
  if next(pieces) == nil then return nil, "aucune pièce à enregistrer : rien n'est porté dans les emplacements cochés." end
  return { nom = nom, pieces = pieces }
end

-- « Mettre à jour » : les emplacements de la tenue gardent leur place, leurs liens sont remplacés par ce qui
-- est porté maintenant (un emplacement vide en ce moment garde sa pièce). Rend le nombre de pièces changées.
function ns.majTenue(tenue, porte)
  local n = 0
  if not tenue or type(tenue.pieces) ~= "table" or type(porte) ~= "table" then return 0 end
  for _, slot in ipairs(emplacementsTries(tenue.pieces)) do
    local lien = porte[slot]
    if type(lien) == "string" and lien ~= "" and lien ~= tenue.pieces[slot] then
      tenue.pieces[slot] = lien
      n = n + 1
    end
  end
  return n
end

-- Ce qui est lu dans la sauvegarde : seules les tenues bien formées sont gardées.
function ns.assainir(liste)
  local propre = {}
  if type(liste) ~= "table" then return propre end
  for _, t in ipairs(liste) do
    if type(t) == "table" and type(t.nom) == "string" and t.nom ~= "" and type(t.pieces) == "table" then
      propre[#propre + 1] = { nom = t.nom, pieces = ns.copierPieces(t.pieces) }
    end
  end
  return propre
end

-- Le message des pièces introuvables.
function ns.texteManque(liens)
  return "il manque : " .. table.concat(liens or {}, ", ") .. " (ni portée ni dans tes sacs)."
end

-- Une confirmation en deux clics : le premier arme la clé, le second (même clé) confirme. Un clic sur
-- autre chose arme l'autre action et désarme la première. Rend vrai quand l'action est confirmée.
function ns.confirmation(etat, cle)
  if etat.cle == cle then
    etat.cle = nil
    return true
  end
  etat.cle = cle
  etat.jeton = (etat.jeton or 0) + 1
  return false
end

-- Ce que tape le joueur après /tenue : { action = "ouvrir" | "enregistrer" | "retour" | "liste" | "options"
-- | "aide" | "mettre", nom = … }.
function ns.analyserCommande(texte)
  texte = tostring(texte or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if texte == "" then return { action = "ouvrir" } end
  local mot, reste = texte:match("^(%S+)%s*(.-)$")
  local m = sansAccents(mot)
  if m == "enregistrer" then return { action = "enregistrer", nom = reste } end
  if reste == "" and (m == "retour" or m == "liste" or m == "options" or m == "aide") then return { action = m } end
  if reste == "" and (m == "reglages" or m == "help" or m == "?") then
    return { action = (m == "reglages") and "options" or "aide" }
  end
  return { action = "mettre", nom = texte }
end

if not CreateFrame then return end -- hors jeu : la suite ne sert qu'en jeu

-- ---------------------------------------------------------------------------
-- Les fonctions du jeu, toutes protégées : si l'une manque sur une version, la fonction
-- concernée ne fait rien et aucune erreur ne sort.
-- ---------------------------------------------------------------------------

local db, perso

-- Appelle f sous pcall ; rend ses résultats, ou rien si elle manque ou plante.
local function sur(f, ...)
  if type(f) ~= "function" then return end
  local ok, a, b, c, d = pcall(f, ...)
  if ok then return a, b, c, d end
end

-- Une valeur « secrète » du jeu ne se compare pas : on la traite comme absente.
local function propre(v)
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end

local function enCombat() return InCombatLockdown and InCombatLockdown() and true or false end

local majFenetre -- définie avec la fenêtre
local statut      -- le texte d'état en bas de la fenêtre

local function dire(texte)
  if ns.reglages then ns.reglages.dire(texte) else print("|cffffd200Tenues|r : " .. texte) end
  if statut then statut:SetText(texte) end
end

-- Un nom de tenue entre guillemets français.
local function guillemets(nom) return "« " .. tostring(nom) .. " »" end

-- Ce qui est porté : { [emplacement] = lien }.
local function lirePortes()
  local porte = {}
  if not GetInventoryItemLink then return porte end
  for slot = PREMIER_EMPLACEMENT, DERNIER_EMPLACEMENT do
    local lien = propre(sur(GetInventoryItemLink, "player", slot))
    if type(lien) == "string" and lien ~= "" then porte[slot] = lien end
  end
  return porte
end

-- Les objets des sacs : { { sac, case, lien }, … } (le sac 0 est le sac à dos).
local function lireSacs()
  local sacs = {}
  local nbCases = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
  local lienCase = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink
  local infoCase = C_Container and C_Container.GetContainerItemInfo
  if not nbCases then return sacs end
  local dernierSac = tonumber(NUM_BAG_SLOTS) or 4
  for sac = 0, dernierSac do
    local n = tonumber(propre(sur(nbCases, sac))) or 0
    for case = 1, n do
      local lien = lienCase and propre(sur(lienCase, sac, case)) or nil
      if not lien and infoCase then
        local info = sur(infoCase, sac, case)
        if type(info) == "table" then lien = propre(info.hyperlink) end
      end
      if type(lien) == "string" and lien ~= "" then sacs[#sacs + 1] = { sac = sac, case = case, lien = lien } end
    end
  end
  return sacs
end

local function estMort()
  return UnitIsDeadOrGhost and propre(sur(UnitIsDeadOrGhost, "player")) == true
end

-- Le curseur tient-il déjà quelque chose ?
local function curseurOccupe()
  if not GetCursorInfo then return false end
  return propre(sur(GetCursorInfo)) ~= nil
end

local function apres(delai, fonction)
  if C_Timer and C_Timer.After then C_Timer.After(delai, fonction) else fonction() end
end

-- Met une pièce de ses sacs sur son emplacement. Rend vrai si un appel a été fait.
local function equiper(p)
  if C_Item and C_Item.EquipItemByName then
    if pcall(C_Item.EquipItemByName, p.lien, p.emplacement) then return true end
  end
  if EquipItemByName then
    if pcall(EquipItemByName, p.lien, p.emplacement) then return true end
  end
  -- Repli : prendre l'objet dans le sac, puis le poser sur son emplacement.
  local prendre = (C_Container and C_Container.PickupContainerItem) or PickupContainerItem
  if prendre and p.sac and p.case and pcall(prendre, p.sac, p.case) then
    if EquipCursorItem then
      pcall(EquipCursorItem, p.emplacement)
    elseif PickupInventoryItem then
      pcall(PickupInventoryItem, p.emplacement)
    end
    -- Si le curseur tient encore l'objet, il retourne à sa place.
    if curseurOccupe() and ClearCursor then pcall(ClearCursor) end
    return true
  end
  return false
end

-- ---------------------------------------------------------------------------
-- Mettre une tenue
-- ---------------------------------------------------------------------------

local attente = nil      -- une demande gardée pour la fin du combat : { nom, pieces, suite, peche }
local chaine = 0         -- numéro de la série de pièces en cours (une nouvelle demande annule l'ancienne)
local pecheMise = false  -- vrai quand c'est nous qui avons mis la tenue Pêche (le retour n'a lieu que dans ce cas)

-- Met une demande { nom, pieces }. Rend vrai si elle est lancée ou gardée pour la fin du combat, et un
-- second résultat : vrai si elle va vraiment changer quelque chose (ou le fera après le combat).
-- opts : peche = vrai pour la tenue Pêche du mode pêche ; suite = vrai pour la fin d'une série interrompue.
local function appliquer(demande, opts)
  opts = opts or {}
  if not db or not perso then return false end
  if not db.actif then dire("l'addon est coupé (réglages > Tenues).") return false end
  local nom = demande.nom
  if enCombat() then
    -- Une seule demande en attente ; la série en cours s'arrête.
    chaine = chaine + 1
    attente = { nom = nom, pieces = ns.copierPieces(demande.pieces), suite = opts.suite, peche = opts.peche }
    dire("tenue " .. guillemets(nom) .. " : elle sera mise à la fin du combat.")
    return true, true
  end
  if estMort() then dire("tenue " .. guillemets(nom) .. " : impossible tant que ton personnage est mort.") return false end
  if curseurOccupe() then dire("tenue " .. guillemets(nom) .. " : ton curseur tient un objet, repose-le d'abord.") return false end
  attente = nil
  local porte, sacs = lirePortes(), lireSacs()
  local plan = ns.plan(demande, porte, sacs)
  if #plan.manquants > 0 and db.prevenirManque then dire(ns.texteManque(plan.manquants)) end
  if #plan.aEquiper == 0 then
    if #plan.manquants == 0 then
      if plan.inverses > 0 then
        dire("tenue " .. guillemets(nom) .. " : tes armes sont portées dans l'autre main, échange-les toi-même.")
      else
        dire("tenue " .. guillemets(nom) .. " : déjà portée.")
      end
    end
    if opts.peche then pecheMise = false end
    if majFenetre then majFenetre() end
    return true, false
  end
  -- On retient ce qui sera remplacé, pour pouvoir le remettre (« retour »).
  local avant = ns.precedente(plan, porte)
  perso.precedente = opts.suite and ns.fusionnerPrecedente(perso.precedente, avant) or avant
  if opts.peche then pecheMise = true end
  chaine = chaine + 1
  local mien = chaine
  local i = 0
  local function pas()
    if mien ~= chaine then return end
    i = i + 1
    local p = plan.aEquiper[i]
    if not p then
      dire("tenue " .. guillemets(nom) .. " mise.")
      if majFenetre then majFenetre() end
      return
    end
    if enCombat() then
      -- Le combat commence au milieu : le reste attend la fin du combat (il sera recalculé).
      attente = { nom = nom, pieces = ns.copierPieces(demande.pieces), suite = true, peche = opts.peche }
      dire("tenue " .. guillemets(nom) .. " : le combat commence, le reste sera mis à la fin du combat.")
      return
    end
    if estMort() or curseurOccupe() then
      dire("tenue " .. guillemets(nom) .. " interrompue (personnage mort ou curseur occupé).")
      if majFenetre then majFenetre() end
      return
    end
    equiper(p)
    apres(0.1, pas)
  end
  pas()
  return true, true
end

-- Une erreur ne sort jamais : elle est notée (et dite une fois) ; la commande suivante réessaie.
local erreurDite = false
local function protege(f, ...)
  local ok, a, b = pcall(f, ...)
  if ok then return a, b end
  ns.derniereErreur = tostring(a)
  if not erreurDite then
    erreurDite = true
    dire("une erreur a été retenue (" .. ns.derniereErreur .. ").")
  end
end

local function mettreTenue(tenue, opts)
  return protege(appliquer, { nom = tenue.nom, pieces = tenue.pieces }, opts) and true or false
end

-- Remet ce qui était porté avant la dernière tenue. silencieux : rien à dire s'il n'y a rien à remettre.
local function retour(silencieux)
  if not perso or type(perso.precedente) ~= "table" or next(perso.precedente) == nil then
    if not silencieux then dire("pas de tenue précédente à remettre.") end
    return false
  end
  return protege(appliquer, { nom = "précédente", pieces = ns.copierPieces(perso.precedente) }) and true or false
end

-- Met la tenue de ce nom (début de nom accepté s'il est unique). Rend vrai si elle est lancée.
function Tenues_Mettre(nom)
  if not perso then return false end
  local t, ambigus = ns.trouverTenue(perso.tenues, nom)
  if not t then
    if ambigus then
      dire("plusieurs tenues commencent par « " .. tostring(nom) .. " » : " .. table.concat(ambigus, ", ") .. ".")
    else
      dire("aucune tenue « " .. tostring(nom) .. " ». /tenue liste donne la liste.")
    end
    return false
  end
  return mettreTenue(t)
end

function Tenues_Precedente() return retour(false) end

-- La touche n met la n-ième tenue de la liste.
function Tenues_Touche(n)
  if not perso then return end
  local t = perso.tenues[tonumber(n) or 0]
  if not t then
    dire("aucune tenue n° " .. tostring(n) .. " : enregistre-en une avec /tenue.")
    return
  end
  mettreTenue(t)
end

local pecheEnAttente = false -- vrai : le mode pêche a démarré en plein canal, la tenue Pêche attend sa fin

local function pecheEnCanal()
  if not UnitChannelInfo then return false end
  return propre(sur(UnitChannelInfo, "player")) ~= nil
end

-- Le mode pêche de Métiers auto : actif met la tenue Pêche (s'il y en a une), sinon remet la précédente, mais
-- seulement si c'est nous qui avions mis la tenue Pêche.
function Tenues_ModePeche(actif)
  if not db or not perso or not db.actif or not db.modePeche then return end
  if actif then
    local t = ns.tenuePeche(perso.tenues)
    if not t then return end
    -- Changer d'équipement en plein canal (une ligne qui vient de partir) risque de l'interrompre :
    -- on attend la fin du canal (UNIT_SPELLCAST_CHANNEL_STOP), puis la tenue se met.
    if pecheEnCanal() then
      pecheEnAttente = true
      return
    end
    pecheEnAttente = false
    mettreTenue(t, { peche = true })
  else
    pecheEnAttente = false
    if attente and attente.peche then attente = nil end -- la tenue Pêche n'avait pas encore été mise
    if pecheMise then
      pecheMise = false
      retour(true)
    end
  end
end

-- ---------------------------------------------------------------------------
-- Enregistrer, mettre à jour, supprimer
-- ---------------------------------------------------------------------------

local majTouches = function() end -- remplacée par l'onglet Touches des réglages (rafraîchit les noms de tenues)

local function enregistrer(nom, coches)
  if not db or not perso then return false end
  local propreNom, erreur = ns.nomValide(nom, perso.tenues)
  if not propreNom then dire(erreur) return false end
  local t, erreur2 = ns.fabriquerTenue(propreNom, lirePortes(), coches)
  if not t then dire(erreur2) return false end
  perso.tenues[#perso.tenues + 1] = t
  dire("tenue " .. guillemets(propreNom) .. " enregistrée (" .. ns.nbPieces(t) .. " pièces).")
  if majFenetre then majFenetre() end
  majTouches()
  return true
end

local function mettreAJour(tenue)
  local n = ns.majTenue(tenue, lirePortes())
  dire("tenue " .. guillemets(tenue.nom) .. " mise à jour (" .. n .. " pièce" .. (n > 1 and "s" or "") .. " changée" .. (n > 1 and "s" or "") .. ").")
  if majFenetre then majFenetre() end
end

local function supprimer(tenue)
  for i, t in ipairs(perso.tenues) do
    if t == tenue then table.remove(perso.tenues, i) break end
  end
  dire("tenue " .. guillemets(tenue.nom) .. " supprimée.")
  if majFenetre then majFenetre() end
  majTouches()
end

-- ---------------------------------------------------------------------------
-- Les touches
-- ---------------------------------------------------------------------------

BINDING_HEADER_TENUES = "Tenues"
for n = 1, 5 do _G["BINDING_NAME_TENUES_TENUE" .. n] = "Tenue " .. n end

local function texteTouche(n)
  if not GetBindingKey then return nil end
  local k = sur(GetBindingKey, "TENUES_TENUE" .. n)
  if not k then return nil end
  return GetBindingText and sur(GetBindingText, k) or k
end

-- Choisir la touche : on écoute la touche suivante (Échap annule). Même méthode que Montures.
local capture = CreateFrame("Frame", nil, UIParent)
capture:SetAllPoints()
capture:EnableKeyboard(true)
capture:SetFrameStrata("FULLSCREEN_DIALOG")
capture:Hide()
capture.numero = 1
local MODIFS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true }

capture:SetScript("OnKeyDown", function(self, touche)
  if MODIFS[touche] then return end
  self:Hide()
  local n = self.numero or 1
  if touche == "ESCAPE" then dire("touche inchangée.") majTouches() return end
  if enCombat() then dire("pas en combat.") return end
  local combo = ((IsShiftKeyDown and IsShiftKeyDown()) and "SHIFT-" or "")
    .. ((IsControlKeyDown and IsControlKeyDown()) and "CTRL-" or "")
    .. ((IsAltKeyDown and IsAltKeyDown()) and "ALT-" or "") .. touche
  local nomLiaison = "TENUES_TENUE" .. n
  local anciennes = { sur(GetBindingKey, nomLiaison) }
  for _, k in ipairs(anciennes) do sur(SetBinding, k) end
  sur(SetBinding, combo, nomLiaison)
  if SaveBindings and GetCurrentBindingSet then sur(SaveBindings, sur(GetCurrentBindingSet)) end
  dire("touche de la tenue " .. n .. " : " .. tostring(GetBindingText and sur(GetBindingText, combo) or combo))
  majTouches()
  if majFenetre then majFenetre() end
end)

local function choisirTouche(n)
  if enCombat() then dire("pas en combat.") return end
  capture.numero = n
  capture:Show()
  dire("appuie sur la touche de la tenue " .. n .. " (Échap annule)…")
end

local function effacerTouche(n)
  if enCombat() then dire("pas en combat.") return end
  local nomLiaison = "TENUES_TENUE" .. n
  for _, k in ipairs({ sur(GetBindingKey, nomLiaison) }) do sur(SetBinding, k) end
  if SaveBindings and GetCurrentBindingSet then sur(SaveBindings, sur(GetCurrentBindingSet)) end
  dire("touche de la tenue " .. n .. " effacée.")
  majTouches()
  if majFenetre then majFenetre() end
end

-- ---------------------------------------------------------------------------
-- La fenêtre
-- ---------------------------------------------------------------------------

local LARGEUR, MAX_LIGNES, HAUTEUR_LIGNE, BAS, HAUT = 560, 7, 50, 150, 36
local ICONE_VIDE = "Interface\\Icons\\INV_Misc_QuestionMark"
local FOND_LIGNE = { bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 }

local fenetre
local lignes, cases = {}, {}
local coches = {}
for slot = PREMIER_EMPLACEMENT, DERNIER_EMPLACEMENT do coches[slot] = true end
local decalage = 0   -- indice de la tenue juste avant la première affichée
local saisie         -- le champ du nom
local texteVide
local etatConfirmation = {}

-- L'icône d'un objet d'après son lien.
local function iconeDe(lien)
  local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if f and lien then
    -- GetItemInfoInstant rend l'icône en cinquième : pas de sur() (il ne garde que quatre résultats).
    local ok, _, _, _, _, icone = pcall(f, lien)
    if ok and icone then return icone end
  end
  return ICONE_VIDE
end

local function placerFenetre(f)
  f:ClearAllPoints()
  local p = db and db.position
  if type(p) == "table" and type(p[1]) == "string" then
    f:SetPoint(p[1], UIParent, type(p[2]) == "string" and p[2] or p[1], tonumber(p[3]) or 0, tonumber(p[4]) or 0)
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end
end

local function sauverPosition(f)
  if not db then return end
  local point, _, relPoint, x, y = f:GetPoint()
  if point then db.position = { point, relPoint or point, x or 0, y or 0 } end
end

local function infobulleLien(bouton, lien, ligneEnPlus, rouge)
  GameTooltip:SetOwner(bouton, "ANCHOR_RIGHT")
  if lien then pcall(GameTooltip.SetHyperlink, GameTooltip, lien) end
  if ligneEnPlus then
    if rouge then GameTooltip:AddLine(ligneEnPlus, 1, 0.3, 0.3, true) else GameTooltip:AddLine(ligneEnPlus, 1, 1, 1, true) end
  end
  GameTooltip:Show()
end

-- Une confirmation par un second clic : « Sûr ? » pendant 3 secondes.
local function demanderConfirmation(cle, action)
  if ns.confirmation(etatConfirmation, cle) then
    action()
  else
    local jeton = etatConfirmation.jeton
    apres(3, function()
      if etatConfirmation.cle == cle and etatConfirmation.jeton == jeton then
        etatConfirmation.cle = nil
        if majFenetre then majFenetre() end
      end
    end)
  end
  if majFenetre then majFenetre() end
end

local function creerLigne(f, i)
  local row = CreateFrame("Frame", nil, f, "BackdropTemplate")
  row:SetSize(LARGEUR - 24, HAUTEUR_LIGNE - 4)
  row:SetPoint("TOPLEFT", 12, -HAUT - (i - 1) * HAUTEUR_LIGNE)
  if row.SetBackdrop then
    row:SetBackdrop(FOND_LIGNE)
    row:SetBackdropColor(0.12, 0.10, 0.07, 0.9)
    row:SetBackdropBorderColor(0.45, 0.36, 0.17, 1)
  end
  row.nom = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  row.nom:SetPoint("TOPLEFT", 8, -7)
  row.nom:SetWidth(190)
  row.nom:SetJustifyH("LEFT")
  if row.nom.SetWordWrap then row.nom:SetWordWrap(false) end
  row.info = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  row.info:SetPoint("TOPLEFT", 202, -9)
  row.info:SetWidth(110)
  row.info:SetJustifyH("LEFT")
  if row.info.SetWordWrap then row.info:SetWordWrap(false) end

  row.bSupprimer = ns.creerBouton(row, "Suppr.", "Supprime la tenue (un second clic confirme). Les objets ne sont pas touchés.", function()
    local t = row.tenue
    if t then demanderConfirmation("sup:" .. t.nom, function() supprimer(t) end) end
  end, 50)
  row.bSupprimer:SetPoint("TOPRIGHT", -4, -4)
  row.bMaj = ns.creerBouton(row, "Mettre à jour", "Rafraîchit les pièces de la tenue avec ce que tu portes (les mêmes emplacements). Un second clic confirme.", function()
    local t = row.tenue
    if t then demanderConfirmation("maj:" .. t.nom, function() mettreAJour(t) end) end
  end, 96)
  row.bMaj:SetPoint("TOPRIGHT", -58, -4)
  row.bMettre = ns.creerBouton(row, "Mettre", "Met cette tenue. Pas en combat : elle se met alors à la fin du combat.", function()
    local t = row.tenue
    if t then mettreTenue(t) end
  end, 62)
  row.bMettre:SetPoint("TOPRIGHT", -158, -4)

  row.icones = {}
  for k = 1, DERNIER_EMPLACEMENT do
    local b = CreateFrame("Button", nil, row)
    b:SetSize(18, 18)
    b:SetPoint("TOPLEFT", 8 + (k - 1) * 20, -26)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    b:SetScript("OnEnter", function(self)
      if not self.lien then return end
      infobulleLien(self, self.lien, self.manque and "Introuvable : ni portée ni dans tes sacs." or nil, true)
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    row.icones[k] = b
  end
  return row
end

local function majLigne(row, indice, tenue, porte, sacs)
  row.tenue = tenue
  local plan = ns.plan(tenue, porte, sacs)
  local portee = ns.estPortee(tenue, porte)
  row.nom:SetText(tenue.nom .. (portee and " |cff40e040(portée)|r" or ""))
  local n = ns.nbPieces(tenue)
  local touche = indice <= 5 and texteTouche(indice) or nil
  row.info:SetText(n .. " pièce" .. (n > 1 and "s" or "") .. (touche and ("  |cffffd200[" .. tostring(touche) .. "]|r") or ""))
  if row.SetBackdropBorderColor then
    if portee then row:SetBackdropBorderColor(0.25, 0.8, 0.25, 1) else row:SetBackdropBorderColor(0.45, 0.36, 0.17, 1) end
  end
  row.bMaj:SetText(etatConfirmation.cle == "maj:" .. tenue.nom and "Sûr ?" or "Mettre à jour")
  row.bSupprimer:SetText(etatConfirmation.cle == "sup:" .. tenue.nom and "Sûr ?" or "Suppr.")
  local slots = emplacementsTries(tenue.pieces)
  for k, b in ipairs(row.icones) do
    local slot = slots[k]
    if slot then
      local lien = tenue.pieces[slot]
      local manque = plan.etat[slot] == "manque"
      b.lien, b.manque = lien, manque
      b.tex:SetTexture(iconeDe(lien))
      if manque then
        b.tex:SetVertexColor(1, 0.25, 0.25)
        if b.tex.SetDesaturated then b.tex:SetDesaturated(true) end
      else
        b.tex:SetVertexColor(1, 1, 1)
        if b.tex.SetDesaturated then b.tex:SetDesaturated(false) end
      end
      b:Show()
    else
      b.lien = nil
      b:Hide()
    end
  end
  row:Show()
end

-- Les cases des emplacements : l'icône de ce qui est porté, entourée de vert si l'emplacement fera partie de la tenue.
local function majCases(porte)
  for slot = PREMIER_EMPLACEMENT, DERNIER_EMPLACEMENT do
    local b = cases[slot]
    if b then
      local lien = porte[slot]
      b.lien = lien
      if lien then b.tex:SetTexture(iconeDe(lien)) else b.tex:SetColorTexture(0.12, 0.12, 0.12, 1) end
      if coches[slot] then
        b.fond:SetColorTexture(0.2, 0.75, 0.2, 1)
        b.tex:SetAlpha(1)
      else
        b.fond:SetColorTexture(0.35, 0.1, 0.1, 1)
        b.tex:SetAlpha(0.4)
      end
    end
  end
end

majFenetre = function()
  if not fenetre or not fenetre:IsShown() or not perso then return end
  local tenues = perso.tenues
  local n = #tenues
  decalage = math.max(0, math.min(decalage, math.max(0, n - MAX_LIGNES)))
  fenetre:SetHeight(HAUT + math.min(MAX_LIGNES, math.max(n, 1)) * HAUTEUR_LIGNE + BAS)
  local porte, sacs = lirePortes(), lireSacs()
  for i, row in ipairs(lignes) do
    local t = tenues[decalage + i]
    if t then majLigne(row, decalage + i, t, porte, sacs) else row.tenue = nil; row:Hide() end
  end
  texteVide:SetShown(n == 0)
  majCases(porte)
end

local function creerFenetre()
  if fenetre then return fenetre end
  local f = CreateFrame("Frame", "TenuesFenetre", UIParent, "BackdropTemplate")
  f:SetSize(LARGEUR, HAUT + HAUTEUR_LIGNE + BAS)
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); sauverPosition(self) end)
  ns.habiller(f, { titre = "Tenues", fermer = true })
  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function(_, sens) decalage = decalage - sens; majFenetre() end)
  f:SetScript("OnShow", function() majFenetre() end)
  placerFenetre(f)
  if UISpecialFrames then
    local deja = false
    for _, nom in ipairs(UISpecialFrames) do if nom == "TenuesFenetre" then deja = true end end
    if not deja then table.insert(UISpecialFrames, "TenuesFenetre") end
  end
  f:Hide()
  fenetre = f

  texteVide = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  texteVide:SetPoint("TOPLEFT", 20, -HAUT - 10)
  texteVide:SetWidth(LARGEUR - 40)
  texteVide:SetJustifyH("LEFT")
  texteVide:SetText("Aucune tenue. Mets l'équipement voulu, choisis les pièces, donne un nom, puis « Enregistrer ce que je porte ».")

  for i = 1, MAX_LIGNES do lignes[i] = creerLigne(f, i) end

  -- Les cases : quels emplacements font partie de la nouvelle tenue.
  local etiquette = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  etiquette:SetPoint("BOTTOMLEFT", 14, 128)
  etiquette:SetText("Pièces de la nouvelle tenue (clic : cocher ou décocher)")
  for slot = PREMIER_EMPLACEMENT, DERNIER_EMPLACEMENT do
    local b = CreateFrame("Button", nil, f)
    b:SetSize(28, 28)
    local rang = slot <= 10 and 0 or 1
    local col = slot <= 10 and (slot - 1) or (slot - 11)
    b:SetPoint("BOTTOMLEFT", 14 + col * 32, 96 - rang * 32)
    b.fond = b:CreateTexture(nil, "BACKGROUND")
    b.fond:SetAllPoints()
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetPoint("TOPLEFT", 2, -2)
    b.tex:SetPoint("BOTTOMRIGHT", -2, 2)
    b:SetScript("OnClick", function()
      coches[slot] = not coches[slot]
      majCases(lirePortes())
    end)
    b:SetScript("OnEnter", function(self)
      infobulleLien(self, self.lien, ns.NOMS_EMPLACEMENTS[slot] .. (coches[slot] and " : fait partie de la tenue" or " : ne fait pas partie de la tenue"))
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    cases[slot] = b
  end
  local bTout = ns.creerBouton(f, "Tout cocher", "Coche tous les emplacements.", function()
    for slot = PREMIER_EMPLACEMENT, DERNIER_EMPLACEMENT do coches[slot] = true end
    majCases(lirePortes())
  end, 100)
  bTout:SetPoint("BOTTOMRIGHT", -118, 122)
  local bRien = ns.creerBouton(f, "Tout décocher", "Décoche tous les emplacements : coche ensuite seulement ce que la tenue doit changer (canne, chapeau, bottes…).", function()
    for slot = PREMIER_EMPLACEMENT, DERNIER_EMPLACEMENT do coches[slot] = false end
    majCases(lirePortes())
  end, 100)
  bRien:SetPoint("BOTTOMRIGHT", -14, 122)

  -- Le nom et le bouton d'enregistrement.
  local etiqNom = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  etiqNom:SetPoint("BOTTOMLEFT", 14, 36)
  etiqNom:SetText("Nom :")
  local ok, champ = pcall(CreateFrame, "EditBox", nil, f, "InputBoxTemplate")
  if not ok or not champ then champ = CreateFrame("EditBox", nil, f) end
  champ:SetSize(190, 22)
  champ:SetPoint("BOTTOMLEFT", 60, 30)
  champ:SetAutoFocus(false)
  champ:SetMaxLetters(LONGUEUR_NOM)
  local function enregistrerDuChamp()
    if enregistrer(champ:GetText(), coches) then
      champ:SetText("")
      champ:ClearFocus()
    end
  end
  champ:SetScript("OnEnterPressed", enregistrerDuChamp)
  champ:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  saisie = champ
  local bEnreg = ns.creerBouton(f, "Enregistrer ce que je porte", "Crée une tenue avec les pièces cochées que tu portes en ce moment. Le nom ne peut pas être vide ni déjà pris.", enregistrerDuChamp, 210)
  bEnreg:SetPoint("BOTTOMLEFT", 262, 30)

  statut = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  statut:SetPoint("BOTTOMLEFT", 14, 10)
  statut:SetWidth(LARGEUR - 28)
  statut:SetJustifyH("LEFT")
  if statut.SetWordWrap then statut:SetWordWrap(false) end
  return f
end

local function ouvrirFenetre()
  local f = creerFenetre()
  if f:IsShown() then f:Hide() else f:Show() end
end

-- ---------------------------------------------------------------------------
-- Réglages
-- ---------------------------------------------------------------------------

ns.reglages = ns.creerReglages({
  titre = "Tenues",
  icone = "Interface\\Icons\\INV_Chest_Cloth_17",
  nomDB = "TenuesDB",
  defauts = DEFAUTS,
  options = {
    { titre = "Tenues" },
    { cle = "actif", libelle = "Activer les tenues",
      aide = "Coupé : aucune tenue ne se met (ni par la fenêtre, ni par les touches, ni par le mode pêche). Tes tenues enregistrées restent." },
    { cle = "prevenirManque", libelle = "Prévenir s'il manque une pièce",
      aide = "Quand une tenue contient une pièce qui n'est ni portée ni dans tes sacs, un message au chat dit laquelle. Les autres pièces se mettent quand même." },
    { cle = "modePeche", libelle = "Mettre la tenue Pêche avec le mode pêche",
      aide = "Quand le mode pêche de Métiers auto démarre, la tenue nommée « Pêche » se met ; quand il s'arrête, ce qui était porté avant revient. Sans tenue Pêche, rien ne change." },
  },
  -- Le bouton « Ouvrir les tenues » (et Maj+clic sur le nom dans la liste des addons).
  ouvrirHub = function() creerFenetre():Show() end,
  texteHub = "Ouvrir les tenues",
  astuce = "/tenue ouvre la fenêtre, /tenue <nom> met une tenue, /tenue retour remet ce qui était porté avant, /tenue aide donne la liste. Les touches se choisissent dans l'onglet Touches.",
  ongletContenu = "Touches",
  contenu = function(f, y)
    local titre = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titre:SetPoint("TOPLEFT", 16, y - 6)
    titre:SetText("Une touche par tenue")
    y = y - 32
    local aide = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    aide:SetPoint("TOPLEFT", 20, y)
    aide:SetWidth(500)
    aide:SetJustifyH("LEFT")
    aide:SetText("La touche n met la n-ième tenue de la liste. Impossible de choisir une touche en combat.")
    y = y - 26
    local textes = {}
    for n = 1, 5 do
      local t = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      t:SetPoint("TOPLEFT", 20, y - 5)
      t:SetWidth(230)
      t:SetJustifyH("LEFT")
      textes[n] = t
      local bChoisir = ns.creerBouton(f, "Choisir la touche", "Appuie ensuite sur la touche voulue. Échap annule. Impossible en combat.", function() choisirTouche(n) end, 130)
      bChoisir:SetPoint("TOPLEFT", 254, y)
      local bEffacer = ns.creerBouton(f, "Effacer", "Retire la touche de cette tenue.", function() effacerTouche(n) end, 70)
      bEffacer:SetPoint("TOPLEFT", 390, y)
      y = y - 32
    end
    majTouches = function()
      for n = 1, 5 do
        local t = perso and perso.tenues[n]
        local k = texteTouche(n)
        textes[n]:SetText("Tenue " .. n .. (t and (" (" .. t.nom .. ")") or " (aucune)") .. " : "
          .. (k and ("|cff00ff00" .. tostring(k) .. "|r") or "|cffff4040aucune|r"))
      end
    end
    return y, majTouches
  end,
  auChargement = function(d)
    db = d
    TenuesPerso = TenuesPerso or {}
    perso = TenuesPerso
    perso.tenues = ns.assainir(perso.tenues)
    perso.precedente = type(perso.precedente) == "table" and ns.copierPieces(perso.precedente) or nil
  end,
  surChangement = function()
    if not db then return end
    if majFenetre then majFenetre() end
  end,
})

-- ---------------------------------------------------------------------------
-- Événements
-- ---------------------------------------------------------------------------

local majEnAttente = false
local function demanderMaj()
  if majEnAttente then return end
  majEnAttente = true
  apres(0.2, function()
    majEnAttente = false
    if majFenetre then protege(majFenetre) end
  end)
end

local ecouteur = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED",
                     "PLAYER_ENTERING_WORLD", "UNIT_SPELLCAST_CHANNEL_STOP" }) do
  pcall(ecouteur.RegisterEvent, ecouteur, e)
end
ecouteur:SetScript("OnEvent", function(_, evenement, unite)
  if not db or not perso then return end
  if evenement == "UNIT_SPELLCAST_CHANNEL_STOP" then
    -- Le canal du joueur est fini : la tenue Pêche qui attendait peut se mettre.
    if unite == "player" and pecheEnAttente then
      pecheEnAttente = false
      if not pecheEnCanal() then protege(Tenues_ModePeche, true) end
    end
  elseif evenement == "PLAYER_REGEN_DISABLED" then
    -- Le combat commence : la capture de touche (plein écran) n'avale plus les touches du jeu.
    if capture:IsShown() then capture:Hide() end
  elseif evenement == "PLAYER_REGEN_ENABLED" and attente then
    local a = attente
    attente = nil
    protege(appliquer, { nom = a.nom, pieces = a.pieces }, { suite = a.suite, peche = a.peche })
  else
    demanderMaj()
  end
end)

-- ---------------------------------------------------------------------------
-- Commandes
-- ---------------------------------------------------------------------------

local function commande(texte)
  local c = ns.analyserCommande(texte)
  if c.action == "ouvrir" then
    ouvrirFenetre()
  elseif c.action == "options" then
    ns.reglages.ouvrir()
  elseif c.action == "enregistrer" then
    enregistrer(c.nom, nil)
  elseif c.action == "retour" then
    retour(false)
  elseif c.action == "liste" then
    if not perso or #perso.tenues == 0 then
      dire("aucune tenue enregistrée. /tenue enregistrer <nom> enregistre ce que tu portes.")
    else
      local porte = lirePortes()
      for i, t in ipairs(perso.tenues) do
        local n = ns.nbPieces(t)
        dire(i .. ". " .. t.nom .. " (" .. n .. " pièce" .. (n > 1 and "s" or "") .. ")" .. (ns.estPortee(t, porte) and " |cff40e040portée|r" or ""))
      end
    end
  elseif c.action == "aide" then
    dire("/tenue : la fenêtre     /tenue <nom> : met la tenue (un début de nom suffit)")
    dire("/tenue enregistrer <nom> : enregistre ce que tu portes     /tenue retour : remet ce qui était porté avant")
    dire("/tenue liste : tes tenues     /tenue options : les réglages")
  else
    Tenues_Mettre(c.nom)
  end
end

SLASH_TENUES1 = "/tenue"
SLASH_TENUES2 = "/tenues"
SlashCmdList.TENUES = function(texte) protege(commande, texte) end
