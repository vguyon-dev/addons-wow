-- ============================================================================
-- Quêtes auto : accepte et rend les quêtes à ta place.
--
-- Ce qui le distingue d'AutoQuests :
--  1. Chez un PNJ, il REND d'abord les quêtes finies, puis ACCEPTE les nouvelles.
--     Une quête en cours pas encore finie n'est jamais ouverte, donc elle ne
--     bloque plus l'acceptation des autres.
--  2. Il choisit la récompense : une amélioration pour toi, sinon l'objet qui se
--     revend le plus cher.
--  3. Des filtres : quêtes grises, journalières, payantes, PNJ et quêtes ignorés.
--  4. En groupe, il partage tes quêtes et accepte celles de tes frères.
--  5. Il passe les cinématiques déjà vues une fois.
--  6. Tout se règle dans une fenêtre (Reglages.lua), listes des PNJ et des quêtes
--     ignorés comprises : icône de minimap, /qa, ou Échap > Options > AddOns.
--     Bouton à l'écran et raccourci clavier.
--
-- Maintenir Maj, Ctrl ou Alt en parlant au PNJ met l'addon en pause.
-- ============================================================================

local NOM_ADDON, ns = ...
local estSecret = issecretvalue or function() return false end

-- Réglages par défaut, recopiés dans QuetesAutoDB au premier chargement.
local DEFAUTS = {
  actif = true,            -- interrupteur général
  accepter = true,         -- accepter les quêtes tout seul
  rendre = true,           -- rendre les quêtes finies tout seul
  pauseTouches = true,     -- Maj, Ctrl ou Alt enfoncé = pause
  minimap = false,         -- icône à part (sinon seulement l'icône commune)
  angleMinimap = 225,      -- position de l'icône sur le tour de la minimap, en degrés
  recompenseAuto = true,   -- choisir la récompense seul (sinon te laisser choisir)
  grises = true,           -- ignorer les quêtes grises (trop faciles)
  journalieres = false,    -- ignorer les journalières et hebdomadaires
  payantes = true,         -- ne pas rendre une quête qui coûte de l'or
  cinematiques = true,     -- passer les cinématiques déjà vues
  dialogueUnique = false,  -- cliquer seul la phrase quand un PNJ n'en a qu'une (coupé au départ)
  bouton = false,          -- bouton « ! » à l'écran (coupé : l'icône de la minimap fait pareil)
  partager = true,         -- partager ses quêtes avec le groupe
  accepterPartagees = true, -- accepter les quêtes partagées par le groupe
  objetsQuete = true,      -- bouton pour commencer la quête d'un objet ramassé
  pnjIgnores = {},         -- [idPNJ] = nom
  quetesIgnorees = {},     -- [idQuête] = titre
  vues = {},               -- cinématiques déjà vues
}

local db

local function dire(texte)
  print("|cffffd200Quêtes auto|r : " .. texte)
end

-- C_Item d'abord, avec un repli sur l'ancienne fonction globale (règle du dépôt).
local infoObjet = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local function niveauObjet(lien)
  if C_Item and C_Item.GetDetailedItemLevelInfo then
    return C_Item.GetDetailedItemLevelInfo(lien) or 0
  end
  return (select(4, infoObjet(lien))) or 0
end

-- ---------------------------------------------------------------------------
-- Partie « logique pure » : aucune fonction du jeu, donc testable hors jeu
-- (voir tests/QuetesAuto_simu.lua).
-- ---------------------------------------------------------------------------

-- Une quête disponible passe-t-elle les filtres ?
-- q : { questID, isTrivial, frequency } ; frequency 1 = journalière, 2 = hebdo.
function ns.accepteQuete(q, reglages, ignorees)
  if q.questID and ignorees[q.questID] then return false end
  if reglages.grises and q.isTrivial then return false end
  if reglages.journalieres and q.frequency and q.frequency > 0 then return false end
  return true
end

-- Que faire chez ce PNJ ? Rend la première quête finie, sinon accepte la
-- première quête qui passe les filtres. Une quête en cours non finie est sautée.
-- Renvoie "rendre", index ou "accepter", index, ou nil s'il n'y a rien à faire.
-- Les réglages « rendre » et « accepter » coupent chacun leur moitié.
function ns.choisirAction(actives, disponibles, reglages, ignorees)
  if reglages.rendre ~= false then
    for i, q in ipairs(actives) do
      if q.isComplete then return "rendre", i end
    end
  end
  if reglages.accepter ~= false then
    for i, q in ipairs(disponibles) do
      if ns.accepteQuete(q, reglages, ignorees) then return "accepter", i end
    end
  end
  return nil
end

-- Objets qui commencent une quête : parmi les objets des sacs
-- ({ sac, case, questID, isActive }), le premier dont la quête n'est pas encore
-- prise (isActive faux) et que tu n'as pas écarté (ecartees[questID]).
function ns.objetDeQuete(objets, ecartees)
  for _, o in ipairs(objets) do
    if o.questID and not o.isActive and not ecartees[o.questID] then return o end
  end
  return nil
end

-- Dialogue unique : quelle phrase cliquer ? Seulement s'il n'y en a qu'UNE,
-- et pas deux fois de suite la même (sinon on tournerait en rond).
-- Renvoie le numéro de l'option, ou nil.
function ns.optionUnique(options, derniere)
  if #options ~= 1 then return nil end
  local id = options[1].gossipOptionID
  if not id or id == derniere then return nil end
  return id
end

-- Lignes des listes de la fenêtre de réglages : { texte, retirer }, rangées par nom.
-- ignores : db.pnjIgnores ([idPNJ] = nom) ; retirer(id) est appelé par la croix.
function ns.lignesPNJ(ignores, retirer)
  local lignes = {}
  for id, nom in pairs(ignores) do
    local ok = type(nom) == "string" and nom ~= "" and nom ~= "?"
    lignes[#lignes + 1] = {
      id = tonumber(id) or 0, cle = ok and nom:lower() or "~",
      texte = (ok and nom or "PNJ") .. " (n° " .. tostring(id) .. ")",
      retirer = function() retirer(id) end,
    }
  end
  table.sort(lignes, function(a, b)
    if a.cle ~= b.cle then return a.cle < b.cle end
    return a.id < b.id
  end)
  return lignes
end

-- Pareil pour db.quetesIgnorees ([idQuête] = titre, ou true pour les anciennes entrées).
function ns.lignesQuetes(ignorees, retirer)
  local lignes = {}
  for id, titre in pairs(ignorees) do
    local ok = type(titre) == "string" and titre ~= ""
    lignes[#lignes + 1] = {
      id = tonumber(id) or 0, cle = ok and titre:lower() or "~",
      texte = ok and (titre .. " (n° " .. tostring(id) .. ")") or ("Quête n° " .. tostring(id)),
      retirer = function() retirer(id) end,
    }
  end
  table.sort(lignes, function(a, b)
    if a.cle ~= b.cle then return a.cle < b.cle end
    return a.id < b.id
  end)
  return lignes
end

-- Métiers (numéros « skillLine » du jeu) qui se servent d'un objet, d'après sa
-- classe et sa sous-classe. nil = l'objet n'a rien à voir avec les métiers.
local FORGE, CUIR, ALCHI, HERBO, CUISINE, MINAGE, COUTURE, INGE, ENCHANT, PECHE, DEPECE, JOAILLE, CALLI =
  164, 165, 171, 182, 185, 186, 197, 202, 333, 356, 393, 755, 773
local ARTISANS = { FORGE, CUIR, ALCHI, COUTURE, INGE, ENCHANT, JOAILLE, CALLI }
local METIERS_OBJET = {
  -- 7 = composants d'artisanat
  [7] = { [1] = { INGE }, [4] = { JOAILLE }, [5] = { COUTURE }, [6] = { CUIR, DEPECE },
          [7] = { FORGE, INGE, JOAILLE, MINAGE }, [8] = { CUISINE }, [9] = { ALCHI, CALLI, HERBO },
          [10] = ARTISANS, [11] = ARTISANS, [12] = { ENCHANT }, [16] = { CALLI },
          [18] = ARTISANS, [19] = ARTISANS },
  -- 9 = recettes
  [9] = { [1] = { CUIR }, [2] = { COUTURE }, [3] = { INGE }, [4] = { FORGE }, [5] = { CUISINE },
          [6] = { ALCHI }, [8] = { ENCHANT }, [9] = { PECHE }, [10] = { JOAILLE }, [11] = { CALLI } },
  -- 19 = outils et équipement de métier
  [19] = { [0] = { FORGE }, [1] = { CUIR }, [2] = { ALCHI }, [3] = { HERBO }, [4] = { CUISINE },
           [5] = { MINAGE }, [6] = { COUTURE }, [7] = { INGE }, [8] = { ENCHANT }, [9] = { PECHE },
           [10] = { DEPECE }, [11] = { JOAILLE }, [12] = { CALLI } },
}
function ns.metiersPour(classe, sousClasse)
  local t = METIERS_OBJET[classe]
  if not t then return nil end
  return t[sousClasse] or (classe == 7 and ARTISANS) or nil
end

-- Quelle récompense prendre ? candidats : { gain = niveaux gagnés (ou nil si
-- pas une amélioration), vente = prix de revente, metiers = liste ou nil }.
-- mesMetiers : { [skillLine] = true }, ou nil si le jeu ne sait pas les donner.
-- Renvoie l'index choisi et la raison, ou nil quand c'est au joueur de choisir.
function ns.choisirRecompense(candidats, mesMetiers)
  -- 1) Une vraie amélioration d'équipement passe avant tout.
  local meilleur, meilleurGain = nil, 0
  for i, c in ipairs(candidats) do
    if c.gain and c.gain > meilleurGain then meilleur, meilleurGain = i, c.gain end
  end
  if meilleur then return meilleur, "amélioration" end
  -- 2) Des récompenses de métier : s'il y en a UNE SEULE pour tes métiers, on la
  --    prend. Plusieurs (même métier ou métiers différents), aucune, ou métiers
  --    inconnus : c'est à toi de choisir.
  local metierTrouve, pourMoi, combien = false, nil, 0
  for i, c in ipairs(candidats) do
    if c.metiers then
      metierTrouve = true
      for _, m in ipairs(c.metiers) do
        if mesMetiers and mesMetiers[m] then
          pourMoi, combien = i, combien + 1
          break -- une récompense ne compte qu'une fois
        end
      end
    end
  end
  if combien == 1 then return pourMoi, "métier" end
  if metierTrouve then return nil, combien > 1 and "plusieurs" or "métier" end
  -- 3) Sinon, la plus chère à la revente, mais jamais un objet que tu ne peux
  --    pas porter (un arc pour un paladin). Si aucune récompense n'est pour toi,
  --    c'est à toi de choisir.
  local plusCher, prix = nil, -1
  for i, c in ipairs(candidats) do
    if not c.inutilisable and (c.vente or 0) > prix then plusCher, prix = i, c.vente or 0 end
  end
  if plusCher then return plusCher, "revente" end
  return nil, "inutilisable"
end

-- Tes métiers, sous la forme { [skillLine] = true }. nil si le jeu ne les donne pas.
local function mesMetiers()
  if not (GetProfessions and GetProfessionInfo) then return nil end
  local t = {}
  for _, index in pairs({ GetProfessions() }) do
    local skillLine = select(7, GetProfessionInfo(index))
    if skillLine then t[skillLine] = true end
  end
  return t
end

-- ---------------------------------------------------------------------------
-- Choix de la récompense en jeu
-- ---------------------------------------------------------------------------

-- Numéro d'interface : 120105 sur Retail, 16001 sur Forever.
local RETAIL = GetBuildInfo ~= nil and (tonumber((select(4, GetBuildInfo()))) or 0) >= 100000

-- Sur Forever, arc, fusil, arbalète, baguette, arme de jet et relique ont leur
-- propre emplacement (18) ; sur Retail, une arme à distance se tient en main (16).
local DISTANCE = RETAIL and 16 or 18

-- Emplacements d'équipement par type d'objet.
local EMPLACEMENTS = {
  INVTYPE_THROWN = { DISTANCE }, INVTYPE_RELIC = { DISTANCE },
  INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 },
  INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 },
  INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 },
  INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
  INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 },
  INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 },
  INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
  INVTYPE_RANGED = { DISTANCE }, INVTYPE_RANGEDRIGHT = { DISTANCE },
}

-- Type d'armure de chaque classe : 1 tissu, 2 cuir, 3 mailles, 4 plaques.
local ARMURE = {
  MAGE = 1, PRIEST = 1, WARLOCK = 1,
  ROGUE = 2, DRUID = 2, MONK = 2, DEMONHUNTER = 2,
  HUNTER = 3, SHAMAN = 3, EVOKER = 3,
  WARRIOR = 4, PALADIN = 4, DEATHKNIGHT = 4,
}

-- Sur WoW Forever (règles d'origine), se servir d'une arme ou porter une armure
-- s'apprend : chaque type d'arme chez le maître d'armes ou le maître de classe,
-- les mailles (chasseur, chaman) et les plaques (guerrier, paladin) au niveau 40.
-- Chaque compétence est un sort que le jeu te donne une fois apprise.
-- COMPETENCES[classe d'objet][sous-classe] = sort de la compétence.
local COMPETENCES = {
  [2] = { -- armes
    [0] = 196,   -- haches à une main
    [1] = 197,   -- haches à deux mains
    [2] = 264,   -- arcs
    [3] = 266,   -- armes à feu
    [4] = 198,   -- masses à une main
    [5] = 199,   -- masses à deux mains
    [6] = 200,   -- armes d'hast
    [7] = 201,   -- épées à une main
    [8] = 202,   -- épées à deux mains
    [10] = 227,  -- bâtons
    [13] = 15590, -- armes de pugilat
    [15] = 1180, -- dagues
    [16] = 2567, -- armes de jet
    [18] = 5011, -- arbalètes
    [19] = 5009, -- baguettes
  },
  [4] = { -- armures
    [1] = 9078,  -- tissu
    [2] = 9077,  -- cuir
    [3] = 8737,  -- mailles
    [4] = 750,   -- plaques
    [6] = 9116,  -- boucliers
  },
}
ns.COMPETENCES = COMPETENCES

-- Peux-tu te servir de cet objet ? Fonction pure, testée hors jeu.
-- `connait(sort)` : compétence apprise (nil = on ne sait pas le demander au jeu) ;
-- `rouge` : la bulle de l'objet affiche une ligne en rouge, la façon dont le jeu
-- dit « tu ne peux pas » (classe, niveau, compétence, race, réputation…).
function ns.utilisable(classeObjet, sousClasse, connait, rouge)
  if rouge then return false end
  local sort = connait and COMPETENCES[classeObjet] and COMPETENCES[classeObjet][sousClasse]
  if sort and not connait(sort) then return false end
  return true
end

-- Type d'armure à viser : la plus lourde que tu as apprise (Forever), sinon
-- celle de ta classe (Retail, où chaque classe porte la sienne dès le niveau 1).
function ns.armureDe(classe, retail, connait)
  if not retail and connait then
    for t = 4, 1, -1 do
      if connait(COMPETENCES[4][t]) then return t end
    end
  end
  return ARMURE[classe]
end

local function connaitSort(id)
  if IsPlayerSpell then return IsPlayerSpell(id) end
  return IsSpellKnown and IsSpellKnown(id) or false
end

-- La liste des compétences ne sert que sur Forever, et seulement si le jeu
-- répond : tout le monde connaît le tissu, sinon la question ne marche pas.
local function competences()
  if RETAIL or not connaitSort(COMPETENCES[4][1]) then return nil end
  return connaitSort
end

-- Lit la bulle de la récompense n° i dans une bulle cachée : vrai si une ligne
-- est en rouge. nil si la bulle n'a pas pu être lue.
local bulle
local function ligneRouge(i)
  if not bulle then
    bulle = CreateFrame("GameTooltip", "QuetesAutoBulle", nil, "GameTooltipTemplate")
  end
  bulle:SetOwner(WorldFrame, "ANCHOR_NONE")
  bulle:ClearLines()
  bulle:SetQuestItem("choice", i)
  local n = bulle:NumLines() or 0
  local rouge = n > 0 and false or nil
  for l = 2, n do -- la ligne 1 est le nom de l'objet
    for _, cote in ipairs({ "Left", "Right" }) do
      local texte = _G["QuetesAutoBulleText" .. cote .. l]
      if texte and texte:IsShown() and texte:GetText() then
        local r, g, b = texte:GetTextColor()
        if r > 0.9 and g < 0.2 and b < 0.2 then rouge = true end
      end
    end
  end
  bulle:Hide()
  return rouge
end

-- Combien de niveaux d'objet cette récompense (n° i) ferait-elle gagner ? nil si
-- ce n'est pas une amélioration dont ton personnage peut se servir. Second
-- résultat : vrai si c'est de l'équipement que ton personnage ne peut pas porter
-- du tout (un arc pour un paladin), pour ne pas le prendre non plus à la revente.
local function gainPour(lien, i)
  local _, _, _, _, _, _, _, _, equipLoc, _, _, classeObjet, sousClasse = infoObjet(lien)
  local slots = equipLoc and EMPLACEMENTS[equipLoc]
  if not slots then return nil end
  local connait = competences()
  local lu, rouge = pcall(ligneRouge, i)
  if not ns.utilisable(classeObjet, sousClasse, connait, lu and rouge or nil) then return nil, true end
  -- Armure de corps (classe d'objet 4, sous-classes 1 à 4) : seulement le type
  -- que tu vises (un chasseur de niveau 20 sur Forever : cuir).
  if classeObjet == 4 and sousClasse and sousClasse >= 1 and sousClasse <= 4
     and equipLoc ~= "INVTYPE_CLOAK" then
    local _, classe = UnitClass("player")
    local mienne = ns.armureDe(classe, RETAIL, connait)
    if mienne and mienne ~= sousClasse then return nil end
  end
  -- Armes et boucliers, quand la liste des compétences ne sert pas (Retail) :
  -- seulement si le jeu dit que tu peux t'en servir.
  if not connait and (classeObjet == 2 or (classeObjet == 4 and sousClasse == 6)) then
    local id = C_Item and C_Item.GetItemInfoInstant and C_Item.GetItemInfoInstant(lien)
    if not (id and C_PlayerInfo and C_PlayerInfo.CanUseItem and C_PlayerInfo.CanUseItem(id)) then
      return nil, true
    end
  end
  local niveau = niveauObjet(lien)
  -- On compare à la pièce portée la plus faible (pour les bagues et bijoux).
  local porte
  for _, slot in ipairs(slots) do
    local lienPorte = GetInventoryItemLink("player", slot)
    local n = lienPorte and niveauObjet(lienPorte) or 0
    if not porte or n < porte then porte = n end
  end
  local gain = niveau - (porte or 0)
  return gain > 0 and gain or nil
end

local essais = 0
local function prendreRecompense()
  local nombre = GetNumQuestChoices()
  if nombre <= 1 then
    GetQuestReward(nombre)
    return
  end
  if not db.recompenseAuto then
    dire("plusieurs récompenses, à toi de choisir.")
    PlaySound(5274, "master")
    return
  end
  local candidats = {}
  for i = 1, nombre do
    local lien = GetQuestItemLink("choice", i)
    if not lien or not infoObjet(lien) then
      -- Le jeu n'a pas encore les infos de l'objet : on réessaie un peu plus tard.
      essais = essais + 1
      if essais <= 10 then C_Timer.After(0.2, prendreRecompense) return end
      dire("infos des récompenses introuvables, à toi de choisir.")
      return
    end
    local classe, sousClasse = select(12, infoObjet(lien))
    local gain, inutilisable = gainPour(lien, i)
    candidats[i] = { lien = lien, gain = gain, inutilisable = inutilisable,
                     vente = select(11, infoObjet(lien)), metiers = ns.metiersPour(classe, sousClasse) }
  end
  essais = 0
  local index, raison = ns.choisirRecompense(candidats, mesMetiers())
  if not index then
    if raison == "inutilisable" then
      dire("aucune récompense que tu peux porter : à toi de choisir.")
    elseif raison == "plusieurs" then
      dire("plusieurs récompenses pour tes métiers : à toi de choisir.")
    else
      dire("récompenses de métier, mais aucune pour tes métiers : à toi de choisir.")
    end
    PlaySound(5274, "master")
    return
  end
  local c = candidats[index]
  -- Journal des 20 derniers choix, écrit dans SavedVariables au /reload ou à la
  -- déconnexion : il permet de comprendre après coup pourquoi un objet a été pris.
  local detail = {}
  for i, k in ipairs(candidats) do
    detail[i] = string.format("%s gain=%s inutilisable=%s vente=%s",
      (k.lien or "?"):match("%[(.-)%]") or "?", tostring(k.gain), tostring(k.inutilisable == true), tostring(k.vente))
  end
  db.journal = db.journal or {}
  table.insert(db.journal, 1, { quete = GetTitleText and GetTitleText() or "?", choix = index,
    raison = raison, candidats = detail, competencesLues = competences() ~= nil })
  while #db.journal > 20 do table.remove(db.journal) end
  -- Copie dans le journal de RapportErreurs s'il est installé (envoyé sur demande).
  if RapportErreurs_Noter then
    pcall(RapportErreurs_Noter, "QuetesAuto", string.format("%s : choix %s (%s) parmi %s",
      db.journal[1].quete, tostring(index), tostring(raison), table.concat(detail, " | ")))
  end
  if raison == "métier" then
    dire("récompense " .. c.lien .. " (pour ton métier).")
  elseif raison == "amélioration" then
    dire("récompense " .. c.lien .. " (+" .. c.gain .. " niveaux d'objet).")
  else
    dire("récompense " .. c.lien .. " (la plus chère à la revente).")
  end
  GetQuestReward(index)
end

-- ---------------------------------------------------------------------------
-- Dialogues avec les PNJ
-- ---------------------------------------------------------------------------

-- Numéro du PNJ à qui tu parles, lu dans son GUID : « Creature-0-…-<id>-… ».
local function idPNJ(unite)
  local guid = UnitGUID(unite or "npc")
  if estSecret(guid) or not guid then return nil end
  local typ, _, _, _, _, id = strsplit("-", guid)
  if typ == "Creature" or typ == "Vehicle" then return tonumber(id) end
end

local function enPause()
  if not db.actif then return true end
  if db.pauseTouches and (IsShiftKeyDown() or IsControlKeyDown() or IsAltKeyDown()) then
    return true
  end
  local id = idPNJ()
  return id and db.pnjIgnores[id] ~= nil
end

-- Dernière phrase de dialogue cliquée, oubliée 3 secondes après.
local derniereOption

-- PNJ moderne (fenêtre de dialogue « gossip »).
local function surDialogue()
  local actives = C_GossipInfo.GetActiveQuests() or {}
  local disponibles = C_GossipInfo.GetAvailableQuests() or {}
  local action, i = ns.choisirAction(actives, disponibles, db, db.quetesIgnorees)
  if action == "rendre" then
    C_GossipInfo.SelectActiveQuest(actives[i].questID)
  elseif action == "accepter" then
    C_GossipInfo.SelectAvailableQuest(disponibles[i].questID)
  elseif db.dialogueUnique then
    -- Plus de quête à rendre ni à prendre : s'il ne reste qu'une phrase, on la clique.
    local id = ns.optionUnique(C_GossipInfo.GetOptions() or {}, derniereOption)
    if id then
      derniereOption = id
      C_Timer.After(3, function() if derniereOption == id then derniereOption = nil end end)
      C_GossipInfo.SelectOption(id)
    end
  end
end

-- Ancien PNJ (fenêtre « QUEST_GREETING », liste de quêtes sans dialogue).
local function surAccueil()
  local actives, disponibles = {}, {}
  for i = 1, GetNumActiveQuests() do
    local _, finie = GetActiveTitle(i)
    actives[i] = { isComplete = finie }
  end
  for i = 1, GetNumAvailableQuests() do
    local grise, frequence, _, _, id = GetAvailableQuestInfo(i)
    disponibles[i] = { isTrivial = grise, frequency = frequence, questID = id }
  end
  local action, i = ns.choisirAction(actives, disponibles, db, db.quetesIgnorees)
  if action == "rendre" then
    SelectActiveQuest(i)
  elseif action == "accepter" then
    SelectAvailableQuest(i)
  end
end

-- Quêtes reçues du groupe : on ne les repartage pas (sinon ping-pong entre frères).
local recuesDuGroupe = {}

-- Moment du dernier clic sur le bouton « objet de quête » (plus bas) : la quête
-- qui s'ouvre juste après vient de là, tu l'as choisie, donc pas de filtre.
local clicObjet = 0

-- La quête affichée vient-elle d'un joueur de ton groupe (quête partagée) ?
-- Le jeu désigne celui qui te parle par « npc » ou « questnpc » : on regarde les deux.
local function partageeParLeGroupe()
  for _, unite in ipairs({ "questnpc", "npc" }) do
    local joueur = UnitIsPlayer(unite)
    if not estSecret(joueur) and joueur and (UnitInParty(unite) or UnitInRaid(unite)) then
      return true
    end
  end
  return false
end

-- Détail d'une quête proposée : on l'accepte si elle passe les filtres.
local function surDetail()
  if partageeParLeGroupe() then
    -- Partagée par ton frère : il l'a choisie, donc pas de filtre.
    if db.accepterPartagees then
      recuesDuGroupe[GetQuestID() or 0] = true
      AcceptQuest()
    end
    return
  end
  if GetTime() - clicObjet < 5 then AcceptQuest() return end
  if not db.accepter then return end
  if QuestGetAutoAccept and QuestGetAutoAccept() then
    -- Quête déjà acceptée d'office par le jeu : on referme simplement.
    CloseQuest()
    return
  end
  local id = GetQuestID()
  local q = {
    questID = id,
    isTrivial = id and C_QuestLog.IsQuestTrivial and C_QuestLog.IsQuestTrivial(id),
    frequency = ((QuestIsDaily and QuestIsDaily()) or (QuestIsWeekly and QuestIsWeekly())) and 1 or 0,
  }
  if ns.accepteQuete(q, db, db.quetesIgnorees) then AcceptQuest() end
end

-- Étape « progression » : on rend seulement si la quête est finie.
local function surProgression()
  if not db.rendre then return end
  if not IsQuestCompletable() then return end -- pas finie : on ne bloque rien
  local cout = GetQuestMoneyToGet and GetQuestMoneyToGet() or 0
  if db.payantes and cout > 0 then
    dire("cette quête coûte de l'or, à toi de la rendre.")
    return
  end
  CompleteQuest()
end

-- ---------------------------------------------------------------------------
-- Cinématiques : la première fois on regarde, ensuite on passe.
-- ---------------------------------------------------------------------------

local function dejaVue(cle)
  if db.vues[cle] then return true end
  db.vues[cle] = true
  return false
end

local function surCinematique(peutPasser)
  if not db.cinematiques or peutPasser == false then return end
  local carte = C_Map.GetBestMapForUnit("player") or 0
  if dejaVue("cine:" .. carte .. ":" .. (GetSubZoneText() or "")) then
    C_Timer.After(0, function()
      if CinematicFrame_CancelCinematic then CinematicFrame_CancelCinematic()
      elseif StopCinematic then StopCinematic() end
    end)
  end
end

local function surFilm(idFilm)
  if not db.cinematiques or not idFilm then return end
  if dejaVue("film:" .. idFilm) then
    C_Timer.After(0, function()
      if MovieFrame and MovieFrame:IsShown() then pcall(MovieFrame.StopMovie, MovieFrame) end
    end)
  end
end

-- ---------------------------------------------------------------------------
-- En groupe : partager ses quêtes, accepter les escortes lancées par le groupe.
-- ---------------------------------------------------------------------------

-- Une quête vient d'être acceptée : on la partage avec le groupe.
-- Partager seulement ce qui peut l'être, et une seule fois par quête :
--  - le jeu dit si la quête est partageable (les quêtes de classe, de métier,
--    d'histoire perso ne le sont pas) : on lui fait confiance, sans réessayer ;
--  - jamais les quêtes mondiales ni les objectifs bonus (acceptés tout seuls en
--    entrant dans la zone) ;
--  - jamais une quête reçue du groupe (sinon on se la renverrait en boucle) ;
--  - jamais deux fois la même quête dans la session.
local dejaPartagees = {}
local function partageable(id)
  local q = C_QuestLog
  if not (q and q.IsPushableQuest and q.SetSelectedQuest and QuestLogPushQuest) then return false end
  if q.IsWorldQuest and q.IsWorldQuest(id) then return false end
  if q.IsQuestTask and q.IsQuestTask(id) then return false end
  local ok, oui = pcall(q.IsPushableQuest, id)
  return ok and not estSecret(oui) and oui == true
end

local function surQueteAcceptee(a, b)
  local id = b or a -- selon la version du jeu : (id) ou (index, id)
  if not db.partager or not IsInGroup() or type(id) ~= "number" then return end
  if recuesDuGroupe[id] or dejaPartagees[id] then return end
  dejaPartagees[id] = true -- même si le partage échoue : on ne réessaie pas
  C_Timer.After(0.5, function()
    if not IsInGroup() or not partageable(id) then return end
    -- On remet ensuite la quête qui était sélectionnée dans ton journal.
    local avant = C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()
    C_QuestLog.SetSelectedQuest(id)
    QuestLogPushQuest()
    if avant and avant ~= 0 then C_QuestLog.SetSelectedQuest(avant) end
    dire("quête partagée avec le groupe : " .. (C_QuestLog.GetTitleForQuestID(id) or id))
  end)
end

-- Un membre du groupe lance une escorte : on la rejoint.
local function surConfirmation()
  if not db.accepterPartagees then return end
  ConfirmAcceptQuest()
  StaticPopup_Hide("QUEST_ACCEPT")
end

-- ---------------------------------------------------------------------------
-- Les réglages (fenêtre, icône de minimap, page des options) : Reglages.lua.
-- La liste ci-dessous sert à la fois à la fenêtre et à la commande /qa.
-- ---------------------------------------------------------------------------

local bouton, icone -- bouton à l'écran, créé plus bas

local function compter(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

-- Ignore (ou ne plus ignorer) le PNJ en face : celui à qui tu parles, sinon ta cible.
-- Renvoie ce qu'il faut dire, ou nil quand il n'y a pas de PNJ.
local function basculerPNJ()
  for _, unite in ipairs({ "npc", "target" }) do
    local pnj = idPNJ(unite)
    if pnj then
      local nom = UnitName(unite)
      if estSecret(nom) or type(nom) ~= "string" or nom == "" then nom = nil end
      db.pnjIgnores[pnj] = db.pnjIgnores[pnj] == nil and (nom or "?") or nil
      return (nom or "ce PNJ") .. (db.pnjIgnores[pnj] and " est ignoré." or " n'est plus ignoré.")
    end
  end
end

-- Le titre d'une quête, quand le jeu le connaît (nil sinon). Le titre est gardé dans la
-- liste des quêtes ignorées pour qu'on la reconnaisse dans la fenêtre.
local function titreQuete(id)
  local t
  if GetQuestID and GetTitleText and GetQuestID() == id then t = GetTitleText() end -- quête affichée
  if (not t or t == "") and C_QuestLog and C_QuestLog.GetTitleForQuestID then
    t = C_QuestLog.GetTitleForQuestID(id)
  end
  if not t or t == "" then
    -- Forever : on cherche la quête dans le journal.
    local rang = C_QuestLog and C_QuestLog.GetLogIndexForQuestID or GetQuestLogIndexByID
    if rang and GetQuestLogTitle then
      local i = rang(id)
      if i and i > 0 then t = GetQuestLogTitle(i) end
    end
  end
  if estSecret(t) or type(t) ~= "string" or t == "" then return nil end
  return t
end

-- Ignore une quête : on garde son titre quand on le connaît (sinon true).
local function ignorerQuete(id)
  db.quetesIgnorees[id] = titreQuete(id) or true
end

-- Le bouton à l'écran à sa place : celle que tu as choisie en le glissant, sinon celle d'origine.
local function placerBouton()
  bouton:ClearAllPoints()
  local p = db.position
  if p then bouton:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  else bouton:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -200, -200) end
end

-- Remet le bouton à sa place d'origine. Faux en combat.
local function replacerBouton()
  if InCombatLockdown() then return false end
  db.position = nil
  placerBouton()
  return true
end

local reglages = ns.creerReglages({
  titre = "Quêtes auto",
  icone = "Interface\\GossipFrame\\AvailableQuestIcon",
  nomDB = "QuetesAutoDB",
  defauts = DEFAUTS,
  options = {
    { titre = "Automatisme" },
    { cle = "actif", libelle = "Activer Quêtes auto",
      aide = "Interrupteur général. L'icône, le bouton et le raccourci font la même chose." },
    { cle = "accepter", libelle = "Accepter les quêtes tout seul",
      aide = "Prend les nouvelles quêtes que les PNJ te proposent. Coupé, les quêtes partagées par le groupe et les objets de quête restent gérés par leurs propres cases." },
    { cle = "rendre", libelle = "Rendre les quêtes finies tout seul",
      aide = "Toujours avant d'accepter les nouvelles. Une quête pas finie ne bloque rien. Coupé, tu rends chaque quête toi-même et tu choisis toi-même la récompense." },
    { cle = "recompenseAuto", libelle = "Choisir la récompense tout seul", dependDe = "rendre",
      aide = "Une amélioration pour toi, sinon l'objet le plus cher à la revente. Décoché, l'addon te prévient et te laisse choisir puis rendre la quête." },
    { cle = "pauseTouches", libelle = "Maj, Ctrl ou Alt met en pause",
      aide = "Garde une de ces touches enfoncée en parlant au PNJ pour tout faire à la main." },
    { cle = "dialogueUnique", libelle = "Cliquer la phrase quand le PNJ n'en a qu'une",
      aide = "Coupé au départ : certains PNJ demandent un vrai choix. Plusieurs phrases = rien." },
    { titre = "En groupe" },
    { cle = "partager", libelle = "Partager mes quêtes avec le groupe",
      aide = "Chaque quête que tu acceptes est proposée aux autres membres du groupe." },
    { cle = "accepterPartagees", libelle = "Accepter les quêtes partagées par le groupe",
      aide = "Sans filtre : si ton frère la partage, tu la prends. Escortes comprises." },
    { titre = "Objets" },
    { cle = "objetsQuete", libelle = "Bouton pour les objets qui commencent une quête",
      aide = "Un objet ramassé lance une quête : un clic sur le bouton qui apparaît, et la quête est acceptée. La croix l'écarte." },
    { titre = "Filtres" },
    { cle = "grises", libelle = "Ignorer les quêtes grises", dependDe = "accepter",
      aide = "Les quêtes trop faciles pour ton niveau." },
    { cle = "journalieres", libelle = "Ignorer les journalières et hebdomadaires", dependDe = "accepter",
      aide = "Elles restent proposées, tu les prends toi-même si tu veux." },
    { cle = "payantes", libelle = "Ne pas rendre les quêtes qui coûtent de l'or", dependDe = "rendre",
      aide = "L'addon te prévient et te laisse payer toi-même." },
    { titre = "Confort" },
    { cle = "cinematiques", libelle = "Passer les cinématiques déjà vues",
      aide = "La première fois tu la regardes, les fois suivantes elle est passée." },
    { cle = "minimap", libelle = "Icône à part autour de la minimap",
      aide = "En plus de l'icône commune « Mes addons ». Clic droit : activer ou couper." },
    { cle = "bouton", libelle = "Bouton à l'écran",
      aide = "Un second « ! » jaune à poser où tu veux, en plus de l'icône de la minimap. Clic : activer ou couper." },
  },
  -- Zone « Listes et outils » : PNJ et quêtes ignorés (avec leur croix), cinématiques,
  -- place du bouton à l'écran.
  ongletContenu = "Listes",
  contenu = function(fenetre, y, r)
    local t = fenetre:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", 16, y - 6)
    t:SetText("Listes et outils")
    y = y - 32
    local function texte(police, x, haut, largeur)
      local fs = fenetre:CreateFontString(nil, "OVERLAY", police)
      fs:SetPoint("TOPLEFT", x, haut)
      fs:SetWidth(largeur)
      fs:SetJustifyH("LEFT")
      return fs
    end

    -- PNJ ignorés : la liste, puis le bouton pour ignorer celui qu'on a en face.
    local majPNJ, majQuetes
    y, majPNJ = ns.creerListe(fenetre, y, {
      titre = "PNJ ignorés",
      vide = "Aucun PNJ ignoré.",
      hauteur = 4,
      lignes = function()
        return ns.lignesPNJ(db.pnjIgnores, function(id) db.pnjIgnores[id] = nil; r.appliquer() end)
      end,
      vider = function() r.changer("pnjIgnores", {}); dire("plus aucun PNJ ignoré.") end,
    })
    local bPNJ = ns.creerBouton(fenetre, "Ignorer le PNJ en face",
      "Le PNJ à qui tu parles, sinon ton PNJ ciblé. S'il est déjà ignoré, il ne l'est plus. Un PNJ ignoré n'est plus géré par l'addon.",
      function()
        local message = basculerPNJ()
        dire(message or "aucun PNJ en face : parle à un PNJ ou cible-le d'abord.")
        if message then r.appliquer() end
      end, 170)
    bPNJ:SetPoint("TOPLEFT", 16, y)
    texte("GameFontDisableSmall", 196, y - 6, 210):SetText("Parle au PNJ ou cible-le d'abord.")
    y = y - 34

    -- Quêtes ignorées : la liste, puis une zone pour en ajouter une par son numéro.
    y, majQuetes = ns.creerListe(fenetre, y, {
      titre = "Quêtes ignorées",
      vide = "Aucune quête ignorée.",
      hauteur = 4,
      lignes = function()
        return ns.lignesQuetes(db.quetesIgnorees, function(id) db.quetesIgnorees[id] = nil; r.appliquer() end)
      end,
      vider = function() r.changer("quetesIgnorees", {}); dire("plus aucune quête ignorée.") end,
    })
    texte("GameFontHighlightSmall", 20, y - 6, 90):SetText("N° de quête :")
    local champ = CreateFrame("EditBox", nil, fenetre, "InputBoxTemplate")
    champ:SetSize(70, 20)
    champ:SetPoint("TOPLEFT", 112, y - 2)
    champ:SetAutoFocus(false)
    champ:SetNumeric(true)
    champ:SetMaxLetters(7)
    champ:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    champ:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    local bQuete = ns.creerBouton(fenetre, "Ignorer cette quête",
      "Pour une quête que tu connais par son numéro (par exemple celui de Wowhead) : elle ne sera plus acceptée toute seule. Pour la reprendre, retire-la de la liste.",
      function()
        local id = tonumber(champ:GetText())
        if not id or id <= 0 then return dire("tape d'abord le numéro de la quête.") end
        if db.quetesIgnorees[id] then return dire("la quête " .. id .. " est déjà ignorée.") end
        ignorerQuete(id)
        champ:SetText("")
        dire("quête " .. id .. " ignorée.")
        r.appliquer()
      end, 150)
    bQuete:SetPoint("TOPLEFT", 190, y)
    y = y - 34

    -- Cinématiques vues et place du bouton à l'écran.
    local cines = texte("GameFontHighlight", 20, y - 5, 230)
    local bCines = ns.creerBouton(fenetre, "Revoir les cinés",
      "Oublie les cinématiques déjà vues : chacune sera de nouveau montrée une fois, puis passée.",
      function() r.changer("vues", {}); dire("les cinématiques seront de nouveau montrées une fois.") end, 150)
    bCines:SetPoint("TOPLEFT", 254, y)
    y = y - 34
    local bPlace = ns.creerBouton(fenetre, "Replacer le bouton à l'écran",
      "Remet le bouton « ! » à sa place d'origine (en haut à droite), par exemple s'il est sorti de l'écran. Il ne se montre que si la case « Bouton à l'écran » est cochée.",
      function()
        if replacerBouton() then dire("bouton remis à sa place.")
        else dire("|cffff4040pas en combat.|r") end
      end, 200)
    bPlace:SetPoint("TOPLEFT", 16, y)
    y = y - 34

    return y, function(d)
      majPNJ()
      majQuetes()
      cines:SetText("Cinématiques déjà vues : " .. compter(d.vues))
    end
  end,
  astuce = "Tout s'applique tout de suite, sans /reload. Commande : /qa.",
  auChargement = function(d)
    db = d
    -- Une seule fois : le bouton à l'écran faisait doublon avec l'icône de la minimap.
    if not db.boutonRange then db.bouton = false; db.boutonRange = true end
    placerBouton()
  end,
  surChangement = function(d)
    icone:SetDesaturated(not d.actif)
    icone:SetAlpha(d.actif and 1 or 0.5)
    bouton:SetShown(d.bouton)
    if ns.majObjetQuete then ns.majObjetQuete() end
  end,
})

function QuetesAuto_Basculer() reglages.basculer() end
BINDING_HEADER_QUETESAUTO = "Quêtes auto"
BINDING_NAME_QUETESAUTO_BASCULER = "Activer ou couper Quêtes auto"
BINDING_NAME_QUETESAUTO_REGLAGES = "Ouvrir les réglages de Quêtes auto"

-- ---------------------------------------------------------------------------
-- Bouton à l'écran
-- ---------------------------------------------------------------------------

bouton = CreateFrame("Button", "QuetesAutoBouton", UIParent)
bouton:SetSize(30, 30)
bouton:SetMovable(true)
bouton:SetClampedToScreen(true)
bouton:RegisterForDrag("LeftButton")
bouton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
icone = bouton:CreateTexture(nil, "ARTWORK")
icone:SetAllPoints()
icone:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
bouton:SetScript("OnClick", function(_, souris)
  if souris == "RightButton" then reglages.ouvrir() else reglages.basculer() end
end)
bouton:SetScript("OnDragStart", bouton.StartMoving)
bouton:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local point, _, pointRelatif, x, y = self:GetPoint()
  db.position = { point, pointRelatif, x, y }
end)
bouton:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:AddLine("Quêtes auto")
  GameTooltip:AddLine(db.actif and "|cff00ff00Activé|r" or "|cffff4040Coupé|r")
  GameTooltip:AddLine("Clic gauche : activer ou couper\nClic droit : réglages\nGlisser : déplacer", 1, 1, 1)
  GameTooltip:Show()
end)
bouton:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- ---------------------------------------------------------------------------
-- Objets qui commencent une quête
-- ---------------------------------------------------------------------------
-- Un addon n'a pas le droit d'utiliser un objet à ta place (c'est protégé par
-- le jeu). Il peut en revanche te tendre un bouton « sécurisé » : UN clic de
-- toi sur ce bouton utilise l'objet, la quête s'ouvre, et Quêtes auto
-- l'accepte. Le bouton ne peut pas changer pendant un combat : on attend la fin.

local ecartees = {}   -- [questID] = true : croix cliquée, on n'insiste plus (jusqu'au /reload)
local boutonObjet = CreateFrame("Button", "QuetesAutoObjetQuete", UIParent, "SecureActionButtonTemplate")
boutonObjet:SetSize(40, 40)
boutonObjet:SetPoint("CENTER", UIParent, "CENTER", 0, 180)
boutonObjet:RegisterForClicks("AnyUp", "AnyDown")
-- Clic gauche seulement. Une macro « /use sac case » plutôt que le type « item » :
-- sur Forever, le type « item » avec « sac case » plante dans le code de Blizzard
-- (C_Item.IsEquippableItem reçoit nil).
boutonObjet:SetAttribute("type1", "macro")
boutonObjet:Hide()
local imageObjet = boutonObjet:CreateTexture(nil, "ARTWORK")
imageObjet:SetAllPoints()
local lueur = boutonObjet:CreateTexture(nil, "OVERLAY")
lueur:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
lueur:SetBlendMode("ADD")
lueur:SetSize(76, 76)
lueur:SetPoint("CENTER")
local texteObjet = boutonObjet:CreateFontString(nil, "OVERLAY", "GameFontNormal")
texteObjet:SetPoint("TOP", boutonObjet, "BOTTOM", 0, -4)
texteObjet:SetText("Nouvelle quête ! Clic pour la commencer")
local croix = CreateFrame("Button", nil, boutonObjet, "UIPanelCloseButton")
croix:SetSize(20, 20)
croix:SetPoint("TOPRIGHT", 14, 14)
boutonObjet:HookScript("PreClick", function() clicObjet = GetTime() end)
boutonObjet:SetScript("OnEnter", function(self)
  if self.sac then
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetBagItem(self.sac, self.case)
    GameTooltip:Show()
  end
end)
boutonObjet:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function infoQueteObjet(sac, case)
  if C_Container and C_Container.GetContainerItemQuestInfo then
    local info = C_Container.GetContainerItemQuestInfo(sac, case)
    if info then return info.questID, info.isActive end
  elseif GetContainerItemQuestInfo then
    local _, id, actif = GetContainerItemQuestInfo(sac, case)
    return id, actif
  end
end

local function nbCases(sac)
  if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(sac) end
  return GetContainerNumSlots and GetContainerNumSlots(sac) or 0
end

local function iconeCase(sac, case)
  if C_Container and C_Container.GetContainerItemInfo then
    local info = C_Container.GetContainerItemInfo(sac, case)
    return info and info.iconFileID
  end
  return GetContainerItemInfo and (GetContainerItemInfo(sac, case))
end

local majPrevue = false
local function majObjetQuete()
  majPrevue = false
  if InCombatLockdown() then majPrevue = true return end -- refait à la fin du combat
  local objets = {}
  if db and db.actif and db.objetsQuete then
    local dernier = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
    for sac = 0, dernier do
      for case = 1, nbCases(sac) do
        local id, actif = infoQueteObjet(sac, case)
        if id then objets[#objets + 1] = { sac = sac, case = case, questID = id, isActive = actif } end
      end
    end
  end
  local o = ns.objetDeQuete(objets, ecartees)
  if not o then boutonObjet:Hide() return end
  boutonObjet.sac, boutonObjet.case, boutonObjet.quete = o.sac, o.case, o.questID
  boutonObjet:SetAttribute("macrotext1", "/use " .. o.sac .. " " .. o.case)
  imageObjet:SetTexture(iconeCase(o.sac, o.case) or "Interface\\Icons\\INV_Misc_Note_01")
  if not boutonObjet:IsShown() then PlaySound(SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_OPEN or 875) end
  boutonObjet:Show()
end

ns.majObjetQuete = majObjetQuete

croix:SetScript("OnClick", function()
  if InCombatLockdown() then return end
  if boutonObjet.quete then ecartees[boutonObjet.quete] = true end
  majObjetQuete()
end)

-- ---------------------------------------------------------------------------
-- Événements
-- ---------------------------------------------------------------------------

local ecouteur = CreateFrame("Frame")
for _, e in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS",
                     "QUEST_COMPLETE", "QUEST_ACCEPTED", "QUEST_ACCEPT_CONFIRM",
                     "CINEMATIC_START", "PLAY_MOVIE", "BAG_UPDATE_DELAYED", "PLAYER_REGEN_ENABLED",
                     "PLAYER_ENTERING_WORLD" }) do
  ecouteur:RegisterEvent(e)
end

ecouteur:SetScript("OnEvent", function(_, evenement, ...)
  if not db then return end
  if evenement == "CINEMATIC_START" then return surCinematique(...) end
  if evenement == "PLAY_MOVIE" then return surFilm(...) end
  if evenement == "BAG_UPDATE_DELAYED" or evenement == "PLAYER_ENTERING_WORLD" then return majObjetQuete() end
  if evenement == "PLAYER_REGEN_ENABLED" then
    if majPrevue then majObjetQuete() end
    return
  end
  if not db.actif then return end
  if evenement == "QUEST_ACCEPTED" then
    C_Timer.After(0.5, majObjetQuete) -- la quête de l'objet est prise : le bouton passe au suivant
    return surQueteAcceptee(...)
  end
  if enPause() then return end
  if evenement == "GOSSIP_SHOW" then surDialogue()
  elseif evenement == "QUEST_GREETING" then surAccueil()
  elseif evenement == "QUEST_DETAIL" then surDetail()
  elseif evenement == "QUEST_PROGRESS" then surProgression()
  elseif evenement == "QUEST_COMPLETE" and db.rendre then essais = 0; prendreRecompense()
  elseif evenement == "QUEST_ACCEPT_CONFIRM" then surConfirmation()
  end
end)

-- ---------------------------------------------------------------------------
-- Commande /qa (la fenêtre fait la même chose, en plus simple)
-- ---------------------------------------------------------------------------

SLASH_QUETESAUTO1 = "/qa"
SLASH_QUETESAUTO2 = "/quetesauto"
SlashCmdList.QUETESAUTO = function(texte)
  local cmd, reste = strtrim(texte or ""):match("^(%S*)%s*(.-)$")
  cmd = cmd:lower()
  if cmd == "" or cmd == "options" or cmd == "reglages" then
    reglages.ouvrir()
  elseif cmd == "on" or cmd == "off" then
    if (cmd == "on") ~= (db.actif and true or false) then reglages.basculer() end
  elseif cmd == "ignorer" then
    local id = tonumber(reste)
    if id then
      if db.quetesIgnorees[id] then db.quetesIgnorees[id] = nil else ignorerQuete(id) end
      dire("quête " .. id .. (db.quetesIgnorees[id] and " ignorée." or " de nouveau prise."))
    else
      dire(basculerPNJ() or "parle à un PNJ (ou cible-le) puis tape /qa ignorer, ou /qa ignorer <numéro de quête>.")
    end
    reglages.appliquer()
  elseif not reglages.basculerOption(cmd) then
    dire("/qa : ouvrir les réglages     /qa on, /qa off : activer ou couper")
    dire("/qa ignorer : ignorer le PNJ en face (ou /qa ignorer <numéro de quête>)")
  end
end
