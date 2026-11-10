-- ============================================================================
-- Logique.lua : la logique de Conseiller, sans aucune fenêtre.
-- Presque tout est « pur » (des fonctions qui reçoivent des données et rendent un résultat) :
-- c'est ce que tests/Conseiller_simu.lua vérifie hors du jeu. Les seules fonctions qui
-- touchent au jeu sont dans ns.apiJeu, et chacune se protège (pcall, valeurs secrètes).
--
-- Valeurs secrètes (Midnight) : en combat, le jeu peut cacher à un addon un temps de recharge,
-- les effets d'une cible, une vie… Comparer ou calculer avec une valeur secrète fait une
-- erreur. Toute valeur lue en combat passe donc par secret() avant d'être utilisée, et une
-- valeur secrète veut dire « je ne sais pas » (nil), jamais « non ».
-- ============================================================================

local NOM_ADDON, ns = ...
local D = ns.DONNEES

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) or false end
ns.estSecret = secret

local simple = ns.simpleRecherche or function(t) return tostring(t or ""):lower() end

-- ============================================================ situation et groupe

-- infos : { typeInstance = "party" | "raid" | "none"…, groupe = bool, raid = bool }
function ns.situation(infos)
  infos = infos or {}
  if infos.typeInstance == "raid" then return "raid" end
  if infos.typeInstance == "party" then return "donjon" end
  if infos.raid then return "raid" end
  if infos.groupe then return "groupe" end
  return "solo"
end

-- Le rôle d'un membre : celui que le jeu a attribué, sinon le plus courant pour sa classe (deviné).
local ROLE_PAR_CLASSE = { WARRIOR = "TANK", PALADIN = "HEALER", PRIEST = "HEALER", DRUID = "HEALER", SHAMAN = "HEALER" }
function ns.roleDe(membre)
  local r = type(membre) == "table" and membre.role or nil
  if secret(r) then r = "NONE" end -- valeur cachée par le jeu : rôle inconnu
  if r == "TANK" or r == "HEALER" or r == "DAMAGER" then return r, false end
  local classe = type(membre) == "table" and membre.classe or ""
  if secret(classe) then classe = "" end
  return ROLE_PAR_CLASSE[classe] or "DAMAGER", true
end

-- membres : { { role = "TANK"|"HEALER"|"DAMAGER"|"NONE", classe = "WARRIOR", nom = "…" }, … }, sans le joueur.
-- moi : le rôle du joueur ("TANK", "HEALER" ou "DAMAGER"), s'il est connu : il compte dans le groupe,
-- sinon un joueur déjà tank passerait pour « il manque un tank ».
-- Renvoie { tank, soins, degats, moi, total (toi compris), devine, manques = { "tank", "soins" } (dans l'ordre), manque }.
function ns.analyserGroupe(membres, moi)
  local r = { tank = 0, soins = 0, degats = 0, devine = false, manques = {} }
  membres = type(membres) == "table" and membres or {}
  if moi == "TANK" then r.tank = 1; r.moi = "tank"
  elseif moi == "HEALER" then r.soins = 1; r.moi = "soins"
  elseif moi == "DAMAGER" then r.degats = 1; r.moi = "degats" end
  for _, m in ipairs(membres) do
    local role, devine = ns.roleDe(m)
    if devine then r.devine = true end
    if role == "TANK" then r.tank = r.tank + 1
    elseif role == "HEALER" then r.soins = r.soins + 1
    else r.degats = r.degats + 1 end
  end
  r.total = #membres + 1
  local besoinTank = r.total >= 10 and 2 or 1
  local besoinSoins = math.max(1, math.floor(r.total / 5))
  if r.tank < besoinTank then r.manques[#r.manques + 1] = "tank" end
  if r.soins < besoinSoins then r.manques[#r.manques + 1] = "soins" end
  r.manque = r.manques[1]
  return r
end

-- ============================================================ spécialisation

-- Retrouve la clé de la spécialisation (par son nom dans le jeu, sinon par son rang).
-- nbSpes (facultatif) : le nombre de spécialisations de la classe dans ce jeu. Une spécialisation peut
-- avoir un rang `index` (jeu à 3 spécialisations) et un rang `index4` (jeu à 4 : druide Retail, où
-- Gardien est 3e et Restauration 4e). Sans nbSpes, un rang ambigu entre les deux ne donne rien.
function ns.cleSpe(classe, nomJeu, index, nbSpes)
  local c = D.CLASSES[classe]
  if not c then return nil end
  if type(nomJeu) == "string" and nomJeu ~= "" then
    local n = simple(nomJeu)
    for _, cle in ipairs(c.ordre) do
      for _, alias in ipairs(c.specs[cle].noms) do
        if alias == n then return cle end
      end
    end
  end
  if type(index) == "number" then
    for _, cle in ipairs(c.ordre) do
      local sp = c.specs[cle]
      local i4 = sp.index4 or sp.index
      local bon
      if nbSpes == 4 then bon = i4 == index
      elseif nbSpes ~= nil then bon = sp.index == index
      else bon = sp.index == index and i4 == index end
      if bon then return cle end
    end
  end
  return nil
end

-- La spécialisation conseillée : d'abord le rôle qui manque au groupe (si la classe peut le jouer),
-- sinon le choix par défaut de la situation.
-- Renvoie { cle, nom, role, raison, parManque = rôle manquant comblé ou nil } ou nil.
function ns.speConseillee(classe, situation, groupe)
  local c = D.CLASSES[classe]
  if not c then return nil end
  if situation ~= "solo" and type(groupe) == "table" and c.parRole then
    for _, role in ipairs(groupe.manques or {}) do
      local cle = c.parRole[role]
      if cle and c.specs[cle] then
        return { cle = cle, nom = c.specs[cle].nom, role = c.specs[cle].role, parManque = role,
          raison = c.raisons[role] or "ton groupe manque de ce rôle." }
      end
    end
  end
  local cle = c.choix[situation] or c.choix.groupe or c.choix.solo
  return { cle = cle, nom = c.specs[cle].nom, role = c.specs[cle].role,
    raison = c.raisons[situation] or c.raisons.groupe or "" }
end

-- ============================================================ builds de talents

-- La liste ordonnée { nodeID, rangs } d'une classe, d'une spécialisation et d'une situation
-- (donjon et raid retombent sur « groupe »). nil s'il n'y en a pas d'écrit.
function ns.buildPour(classe, spe, situation)
  local c = D.BUILDS[classe]
  local s = c and c[spe]
  if type(s) ~= "table" then return nil end
  local l = s[situation]
  if not l and (situation == "donjon" or situation == "raid") then l = s.groupe end
  if type(l) == "table" and #l > 0 then return l end
  return nil
end

-- Le prochain nœud à prendre : le premier du build dont le rang n'est pas atteint.
-- rangDe(nodeID) rend le rang pris, ou nil si le nœud n'existe pas dans l'arbre du personnage (sauté).
-- Renvoie l'entrée, le rang actuel et sa place dans le build ; nil quand tout est pris.
function ns.prochainNoeud(build, rangDe)
  for i, e in ipairs(build or {}) do
    local rang = rangDe(e.nodeID)
    if rang ~= nil and rang < (e.rangs or 1) then return e, rang, i end
  end
  return nil
end

-- ============================================================ ordre des statistiques

function ns.ordreStats(classe, spe)
  local c = D.STATS[classe]
  local l = c and spe and c[spe]
  if not l and c then
    local cl = D.CLASSES[classe]
    local conseillee = cl and cl.choix.solo
    l = conseillee and c[conseillee]
  end
  return l or D.STATS_PAR_DEFAUT
end

-- ============================================================ résolution des sorts

local function ensemble(liste)
  local e = {}
  for _, id in ipairs(liste or {}) do e[id] = true end
  return e
end

-- La table « nom simplifié -> spellID » du grimoire, construite une fois par résolution.
-- Les lignes hors spécialisation (isOffSpec, si le jeu le donne) sont ignorées.
function ns.indexGrimoire(liste)
  local t = {}
  for _, s in ipairs(liste or {}) do
    if type(s.nom) == "string" and not s.horsSpe then
      local k = simple(s.nom)
      if t[k] == nil then t[k] = s.spellID end
    end
  end
  return t
end

-- def = { nom, ids } ; api = { connu(id), nomSort(id), chercherParNom(nom) }
-- parNom (facultatif) : résultat de indexGrimoire, qui évite de reparcourir le grimoire pour chaque sort.
-- Renvoie { id, nom, ids = ensemble } ou nil si le personnage ne connaît pas ce sort.
function ns.resoudreSort(def, api, parNom)
  for _, id in ipairs(def.ids or {}) do
    if api.connu(id) then
      return { id = id, nom = api.nomSort(id) or def.nom, ids = ensemble(def.ids) }
    end
  end
  if def.nom and (parNom or api.chercherParNom) then
    local id
    if parNom then id = parNom[simple(def.nom)] else id = api.chercherParNom(def.nom) end
    if id then
      local ids = ensemble(def.ids)
      ids[id] = true
      return { id = id, nom = api.nomSort(id) or def.nom, ids = ids }
    end
  end
  return nil
end

-- Tous les sorts d'une classe : { CLE = { id, nom, ids } } (les inconnus sont absents).
function ns.resoudreSorts(classe, api)
  local res = {}
  local parNom
  if api.grimoire then
    local okG, liste = pcall(api.grimoire)
    if okG and type(liste) == "table" then parNom = ns.indexGrimoire(liste) end
  end
  for cle, def in pairs(D.SORTS[classe] or {}) do
    local ok, s = pcall(ns.resoudreSort, def, api, parNom)
    if ok and s then s.cle = cle; res[cle] = s end
  end
  return res
end

-- ============================================================ le moteur de priorité

-- Une condition : une chaîne ("pret", "ennemisProches>=3", "vie<20") ou une table
-- ({ "debuffAbsent", AUTRE_CLE }, { "vie", "moi", 30 }, { "typeCible", { "Mort-vivant", "Démon" } }).
-- Rend true, false, ou nil quand la valeur est illisible (secrète, absente).
function ns.evaluerCondition(cond, cleSort, sorts, api)
  local nom, a1, a2 = cond, nil, nil
  if type(cond) == "table" then nom, a1, a2 = cond[1], cond[2], cond[3] end
  if type(nom) ~= "string" then return nil end
  local seuil = nom:match("^ennemisProches>=(%d+)$")
  if seuil then nom, a1 = "ennemisProches", tonumber(seuil) end
  local pct = nom:match("^vie<(%d+)$")
  if pct then nom, a1, a2 = "vie", "cible", tonumber(pct) end

  if nom == "pret" then
    return api.pret(sorts[a1 or cleSort])
  elseif nom == "debuffAbsent" then
    return api.debuffAbsent(sorts[a1 or cleSort])
  elseif nom == "buffAbsent" then
    return api.buffAbsent(sorts[a1 or cleSort])
  elseif nom == "ennemisProches" then
    local n = api.ennemis()
    if type(n) ~= "number" or secret(n) then return nil end
    return n >= (a1 or 2)
  elseif nom == "typeCible" then
    -- a1 = liste des noms de types (localisés) acceptés ; type secret ou absent : non évaluable.
    local t = api.typeCible and api.typeCible()
    if type(t) ~= "string" or secret(t) or type(a1) ~= "table" then return nil end
    local voulu = simple(t)
    for _, n in ipairs(a1) do
      if simple(n) == voulu then return true end
    end
    return false
  elseif nom == "vie" then
    local p = api.vie(a1 or "cible")
    if type(p) ~= "number" or secret(p) then return nil end
    return p < (a2 or 20)
  end
  return nil
end

-- Évalue une liste de priorité.
--   liste : { { sort = CLE, si = { conditions }, texte = "…" }, … }
--   sorts : résultat de resoudreSorts ; api : { pret, debuffAbsent, buffAbsent, ennemis, vie, typeCible }
-- Renvoie { choix = entrée à lancer (ou nil), cle, illisible = vrai quand la plupart des entrées
-- à conditions (plus de la moitié) sont illisibles : alors on ne recommande rien et on passe au mode liste, lignes = { { sort, texte, verdict } } }.
-- Verdict : true (à lancer), false (pas maintenant), nil (illisible).
-- Une entrée dont le sort est inconnu du personnage est sautée.
function ns.evaluerRotation(liste, sorts, api)
  local res = { lignes = {}, illisible = false }
  local conditionnelles, illisibles = 0, 0
  for _, e in ipairs(liste or {}) do
    local s = sorts[e.sort]
    if s then
      local conds = e.si or {}
      local verdict, inconnu = true, false
      for _, c in ipairs(conds) do
        local ok, v = pcall(ns.evaluerCondition, c, e.sort, sorts, api)
        if not ok then v = nil end
        if v == false then verdict = false; break end
        if v == nil then inconnu = true end
      end
      if verdict and inconnu then verdict = nil end
      if #conds > 0 then
        conditionnelles = conditionnelles + 1
        if verdict == nil then illisibles = illisibles + 1 end
      end
      res.lignes[#res.lignes + 1] = { sort = e.sort, texte = e.texte or s.nom, verdict = verdict, nom = s.nom }
    end
  end
  -- Illisible : la plupart des entrées à conditions ne peuvent pas être jugées (valeurs cachées par le jeu).
  res.illisible = conditionnelles > 0 and illisibles > (conditionnelles - illisibles)
  if not res.illisible then
    for i, l in ipairs(res.lignes) do
      if l.verdict == true then
        res.choix = l
        res.cle = l.sort
        res.rang = i
        break
      end
    end
  end
  return res
end

-- Le mode d'affichage : reglage = 1 (auto), 2 (contour sur la barre) ou 3 (liste seule).
function ns.modeEffectif(reglage, illisible)
  if reglage == 3 then return "C" end
  if reglage == 2 then return "A" end
  return illisible and "C" or "A"
end

-- ============================================================ boutons de la barre d'action

-- boutons : liste de { cadre, slot } ; api : { infoAction(slot) -> type, id ; nomSort(id) ; slotsDuSort(id) }.
-- Rend les boutons dont l'action est ce sort (même rang ou même nom).
function ns.boutonsPourSort(s, boutons, api)
  local res = {}
  if not s then return res end
  local slots = {}
  if api.slotsDuSort then
    local ok, l = pcall(api.slotsDuSort, s.id)
    if ok and type(l) == "table" then
      for _, sl in ipairs(l) do slots[sl] = true end
    end
  end
  local nomVoulu = simple(s.nom)
  for _, b in ipairs(boutons or {}) do
    local trouve = b.slot ~= nil and slots[b.slot] or false
    if not trouve and b.slot ~= nil then
      local ok, t, id = pcall(api.infoAction, b.slot)
      if ok and t == "spell" and type(id) == "number" and not secret(id) then
        if id == s.id or (s.ids and s.ids[id]) then
          trouve = true
        else
          local okN, nom = pcall(api.nomSort, id)
          if okN and type(nom) == "string" and not secret(nom) and simple(nom) == nomVoulu then trouve = true end
        end
      end
    end
    if trouve then res[#res + 1] = b end
  end
  return res
end

-- ============================================================ métiers

-- m = { nom, niveau = compétence, plafond = plafond actuel } ; niveauJoueur = niveau du personnage.
function ns.aFaireMetier(m, niveauJoueur)
  local nom, niveau, plafond = m.nom or "Métier", m.niveau or 0, m.plafond or 75
  niveauJoueur = niveauJoueur or 1
  if niveau < plafond then
    local texte = string.format("%s %d/%d : monte-le jusqu'à %d.", nom, niveau, plafond, plafond)
    if niveau < niveauJoueur * 5 - 25 then
      texte = texte .. string.format(" Tu es en retard pour ton niveau : vise %d.", math.min(300, niveauJoueur * 5))
    end
    return texte
  end
  local suivant
  for _, p in ipairs(D.PALIERS) do
    if p.plafond > plafond then suivant = p; break end
  end
  if not suivant then return string.format("%s %d/%d : au maximum.", nom, niveau, plafond) end
  if niveauJoueur >= suivant.niveau then
    return string.format("%s %d/%d : va voir un maître du métier pour apprendre le palier %s (jusqu'à %d).",
      nom, niveau, plafond, suivant.nom, suivant.plafond)
  end
  return string.format("%s %d/%d : palier fini. Le suivant (%s, jusqu'à %d) demande le niveau %d (tu es niveau %d).",
    nom, niveau, plafond, suivant.nom, suivant.plafond, suivant.niveau, niveauJoueur)
end

-- ============================================================ l'accès au jeu (seule partie qui touche aux API)

local api = {}
ns.apiJeu = api

function api.connu(id)
  if C_SpellBook and C_SpellBook.IsSpellKnown then return C_SpellBook.IsSpellKnown(id) and true or false end
  if IsPlayerSpell then return IsPlayerSpell(id) and true or false end
  if IsSpellKnown then return IsSpellKnown(id) and true or false end
  return false
end

function api.nomSort(id)
  if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
  if GetSpellInfo then return (GetSpellInfo(id)) end
  return nil
end

-- Tout le grimoire : { { spellID, nom, sousTexte } }.
function api.grimoire()
  local liste = {}
  if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookItemInfo then
    local banque = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
    for l = 1, C_SpellBook.GetNumSpellBookSkillLines() do
      local ligne = C_SpellBook.GetSpellBookSkillLineInfo(l)
      if type(ligne) == "table" and type(ligne.itemIndexOffset) == "number" then
        for i = ligne.itemIndexOffset + 1, ligne.itemIndexOffset + (ligne.numSpellBookItems or 0) do
          local info = C_SpellBook.GetSpellBookItemInfo(i, banque)
          if type(info) == "table" and info.spellID and not secret(info.spellID) then
            local nom, sous = info.name, info.subName
            if not nom and C_SpellBook.GetSpellBookItemName then nom, sous = C_SpellBook.GetSpellBookItemName(i, banque) end
            local horsSpe = not secret(info.isOffSpec) and info.isOffSpec == true or nil
            liste[#liste + 1] = { spellID = info.spellID, nom = nom, sousTexte = sous, horsSpe = horsSpe }
          end
        end
      end
    end
  elseif GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemInfo then
    for t = 1, GetNumSpellTabs() do
      local _, _, decalage, nombreSorts = GetSpellTabInfo(t)
      for i = (decalage or 0) + 1, (decalage or 0) + (nombreSorts or 0) do
        local type_, id = GetSpellBookItemInfo(i, "spell")
        if type_ == "SPELL" and id then
          local nom, sous = GetSpellBookItemName(i, "spell")
          liste[#liste + 1] = { spellID = id, nom = nom, sousTexte = sous }
        end
      end
    end
  end
  return liste
end

function api.chercherParNom(nom)
  return ns.indexGrimoire(api.grimoire())[simple(nom)]
end

function api.infoAction(slot)
  local t, id = GetActionInfo(slot)
  return t, id
end

function api.slotsDuSort(id)
  if C_ActionBar and C_ActionBar.FindSpellActionButtons then return C_ActionBar.FindSpellActionButtons(id) end
  return nil
end

-- Le sort est-il lançable maintenant : utilisable et recharge finie ?
-- nil quand le jeu cache la valeur (combat) : on ne devine pas.
function api.pret(s)
  if not s or not s.id then return nil end
  local utilisable
  if C_Spell and C_Spell.IsSpellUsable then utilisable = C_Spell.IsSpellUsable(s.id)
  elseif IsUsableSpell then utilisable = IsUsableSpell(s.id) end
  if secret(utilisable) then return nil end
  local debut, duree
  if C_Spell and C_Spell.GetSpellCooldown then
    local i = C_Spell.GetSpellCooldown(s.id)
    if i == nil then return nil end
    if secret(i) or type(i) ~= "table" then return nil end
    debut, duree = i.startTime, i.duration
  elseif GetSpellCooldown then
    debut, duree = GetSpellCooldown(s.id)
  end
  if debut == nil or duree == nil then return nil end
  if secret(debut) or secret(duree) then return nil end
  if not utilisable then return false end
  if duree <= 1.5 then return true end -- seulement la recharge commune : on peut déjà y penser
  return (debut + duree - GetTime()) <= 0.1
end

-- Cherche un effet du sort sur une unité. Rend true (présent), false (absent), nil (illisible).
local function chercherEffet(unite, filtre, s)
  if not s then return nil end
  if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
  if UnitExists and not UnitExists(unite) then return nil end
  local nomVoulu = s.nom and simple(s.nom)
  for i = 1, 60 do
    local a = C_UnitAuras.GetAuraDataByIndex(unite, i, filtre)
    if not a then return false end
    if secret(a) or type(a) ~= "table" then return nil end
    local id, nom = a.spellId, a.name
    if secret(id) or secret(nom) then return nil end
    if (id and s.ids and s.ids[id]) or id == s.id or (nomVoulu and type(nom) == "string" and simple(nom) == nomVoulu) then
      return true
    end
  end
  return false
end

function api.debuffAbsent(s)
  local present = chercherEffet("target", "HARMFUL|PLAYER", s)
  if present == nil then return nil end
  return not present
end

function api.buffAbsent(s)
  local present = chercherEffet("player", "HELPFUL", s)
  if present == nil then return nil end
  return not present
end

-- Ennemis en combat dont la plaque de nom est affichée : une approximation (le jeu ne donne
-- pas la distance), nil quand on ne peut pas compter.
function api.ennemis()
  if not (C_NamePlate and C_NamePlate.GetNamePlates and UnitCanAttack) then return nil end
  local n = 0
  for _, plaque in ipairs(C_NamePlate.GetNamePlates() or {}) do
    local u = plaque.namePlateUnitToken or (plaque.UnitFrame and plaque.UnitFrame.unit)
    if u then
      local ennemi = UnitCanAttack("player", u)
      local enCombat = UnitAffectingCombat and UnitAffectingCombat(u)
      local mort = UnitIsDead and UnitIsDead(u)
      if secret(ennemi) or secret(enCombat) or secret(mort) then return nil end
      if ennemi and enCombat and not mort then n = n + 1 end
    end
  end
  return n
end

-- Le type de créature de la cible (nom localisé : « Mort-vivant », « Démon »…) ; nil si illisible.
function api.typeCible()
  if not (UnitCreatureType and UnitExists and UnitExists("target")) then return nil end
  local t = UnitCreatureType("target")
  if type(t) ~= "string" or secret(t) then return nil end
  return t
end

function api.vie(unite)
  local u = unite == "moi" and "player" or "target"
  if not (UnitHealth and UnitHealthMax) then return nil end
  local v, m = UnitHealth(u), UnitHealthMax(u)
  if secret(v) or secret(m) or type(v) ~= "number" or type(m) ~= "number" or m <= 0 then return nil end
  return v / m * 100
end

-- ============================================================ les textes des onglets

local OR, BLEU, VERT, ROUGE, GRIS, FIN = "|cffffd200", "|cff5ab4ff", "|cff3ddc3d", "|cffff6b5a", "|cffaaaaaa", "|r"
ns.COULEURS = { or_ = OR, bleu = BLEU, vert = VERT, rouge = ROUGE, gris = GRIS }

local function titre(t) return OR .. t .. FIN end

-- « À savoir » : les conseils de la classe, seul ou en groupe.
function ns.conseilsASavoir(classe, situation)
  local c = D.CLASSES[classe]
  local cle = situation == "solo" and "solo" or "groupe"
  local liste = c and c.conseils and c.conseils[cle] or D.CONSEILS_GENERIQUES[cle]
  return (situation == "solo" and "Seul" or "En groupe") .. " : à savoir", liste
end

local function texteGroupe(e)
  local g = e.groupe
  if not g then return nil end
  local L = {}
  L[#L + 1] = titre("Ton groupe")
  L[#L + 1] = string.format("Tank : %d  ·  Soigneur : %d  ·  Dégâts : %d  ·  Toi : %s", g.tank, g.soins, g.degats,
    g.moi and D.NOMS_ROLES[g.moi] or "?")
  if g.devine then L[#L + 1] = GRIS .. "Certains rôles sont devinés d'après la classe (le jeu ne les a pas attribués)." .. FIN end
  if g.manque then
    local nomRole = D.NOMS_ROLES[g.manque] or g.manque
    local conseil = e.conseil
    if conseil and conseil.parManque == g.manque then
      L[#L + 1] = ROUGE .. "Il manque un " .. nomRole .. " : " .. FIN .. "tu peux le jouer en " .. conseil.nom .. "."
    else
      L[#L + 1] = ROUGE .. "Il manque un " .. nomRole .. " : " .. FIN .. "ta classe ne peut pas le jouer, garde ton rôle."
    end
  else
    L[#L + 1] = VERT .. "Rien ne manque dans ton groupe." .. FIN
  end
  return table.concat(L, "\n")
end

function ns.vueTalents(e)
  local c = D.CLASSES[e.classe]
  if not c or not e.conseil then
    return "Ta classe n'est pas dans les données de Conseiller (" .. tostring(e.classe) .. ")."
  end
  local L = {}
  L[#L + 1] = titre("Spécialisation conseillée : " .. e.conseil.nom)
  if e.speCle and e.speCle == e.conseil.cle then
    L[#L + 1] = VERT .. "C'est celle que tu as déjà." .. FIN
  elseif e.speNom then
    L[#L + 1] = GRIS .. "Tu es en " .. e.speNom .. "." .. FIN
  end
  L[#L + 1] = "Pourquoi : " .. e.conseil.raison
  if e.situation ~= "solo" then
    local g = texteGroupe(e)
    if g then L[#L + 1] = ""; L[#L + 1] = g end
  end
  L[#L + 1] = ""
  local t = e.talents or {}
  if t.etat == "suivant" then
    L[#L + 1] = titre("Prochain talent : " .. tostring(t.nom or "?"))
    L[#L + 1] = string.format("Rang %d sur %d. Dans la fenêtre des talents du jeu, il est entouré en vert (si l'option est cochée).",
      t.rang or 0, t.rangs or 1)
  elseif t.etat == "fini" then
    L[#L + 1] = titre("Talents")
    L[#L + 1] = VERT .. "Tous les talents de ce build sont pris." .. FIN
  elseif t.etat == "horsArbre" then
    L[#L + 1] = titre("Talents")
    L[#L + 1] = "Le build écrit ne correspond pas à l'arbre de ton personnage (numéros de nœuds introuvables). Fais " .. BLEU .. "/cs export" .. FIN .. " puis " .. BLEU .. "/reload" .. FIN .. " pour qu'on le corrige."
  elseif t.etat == "sansArbre" then
    L[#L + 1] = titre("Talents")
    L[#L + 1] = "Le jeu ne donne pas (encore) l'arbre de talents de ton personnage : configuration active introuvable."
  else
    L[#L + 1] = titre("Talents")
    L[#L + 1] = string.format("Build pas encore écrit pour %s, %s, %s. Fais %s/cs export%s puis %s/reload%s : l'arbre complet de ton personnage et ton grimoire sont écrits dans la sauvegarde (ConseillerDB, dossier WTF) pour qu'on écrive le build avec les vrais numéros de nœuds.",
      c.nom, e.conseil.nom, D.NOMS_SITUATIONS[e.situation] or e.situation, BLEU, FIN, BLEU, FIN)
  end
  return table.concat(L, "\n")
end

function ns.vueRotation(e)
  local c = D.CLASSES[e.classe]
  local L = {}
  local spe = e.speRotationNom or (c and e.speRotation and c.specs[e.speRotation] and c.specs[e.speRotation].nom) or "?"
  L[#L + 1] = titre("Rotation " .. spe)
  local r = e.rotation
  if not r or not r.liste then
    L[#L + 1] = "Rotation pas encore écrite pour " .. (c and c.nom or "cette classe") .. ", " .. spe .. " : rien ne s'allume sur ta barre pour l'instant. Les conseils ci-dessous valent déjà."
  else
    local nomMode = r.mode == "C" and "C (liste de priorité seule)" or "A (contour bleu sur ta barre d'action)"
    L[#L + 1] = "Mode : " .. nomMode .. (r.auto and GRIS .. " (choisi tout seul)" .. FIN or "")
    if r.mode == "C" and r.auto then
      L[#L + 1] = GRIS .. "Le jeu cache les temps de recharge en combat : rien ne peut s'allumer, tu suis la liste." .. FIN
    end
    if r.resultat and r.resultat.choix and r.mode == "A" then
      local l = r.resultat.choix
      L[#L + 1] = BLEU .. "Maintenant : " .. FIN .. (l.nom or l.texte)
      if r.boutons and r.boutons == 0 then
        L[#L + 1] = GRIS .. "Ce sort n'est sur aucune de tes barres d'action : pose-le sur une barre pour le voir s'allumer." .. FIN
      end
    end
    L[#L + 1] = ""
    L[#L + 1] = titre("Ordre de priorité")
    local n = 0
    for _, ligne in ipairs(r.resultat and r.resultat.lignes or r.lignesStatiques or {}) do
      n = n + 1
      local marque = ""
      if r.resultat and r.resultat.choix and r.resultat.choix == ligne then marque = BLEU .. "  <" .. FIN end
      L[#L + 1] = string.format("%d. %s%s", n, ligne.texte, marque)
    end
    if n == 0 then L[#L + 1] = "Aucun des sorts de cette rotation n'est dans ton grimoire pour l'instant." end
  end
  L[#L + 1] = ""
  local titreConseils, conseils = ns.conseilsASavoir(e.classe, e.situation)
  L[#L + 1] = titre(titreConseils)
  for _, ligne in ipairs(conseils or {}) do L[#L + 1] = "- " .. ligne end
  return table.concat(L, "\n")
end

function ns.vueEquipement(e)
  local c = D.CLASSES[e.classe]
  local spe = e.speCle or (e.conseil and e.conseil.cle)
  local nomSpe = (c and spe and c.specs[spe] and c.specs[spe].nom) or e.speNom or "ta classe"
  local noms = {}
  for _, cle in ipairs(ns.ordreStats(e.classe, spe)) do noms[#noms + 1] = D.NOMS_STATS[cle] or cle end
  local L = {}
  L[#L + 1] = titre("Ordre des statistiques pour " .. nomSpe)
  L[#L + 1] = table.concat(noms, "  >  ")
  L[#L + 1] = ""
  L[#L + 1] = GRIS .. "Du plus important au moins important. Les autres addons peuvent lire cet ordre avec Conseiller_OrdreStats() (Sacs rangés s'en servira pour sa flèche verte)." .. FIN
  return table.concat(L, "\n")
end

local BADGES = { "|cff3ddc3d[Conseillé]|r", "|cffaaaaaa[Pour plus tard]|r", "|cffffd200[Pour l'or]|r" }

function ns.vueMetiers(e)
  local c = D.CLASSES[e.classe]
  local L = {}
  L[#L + 1] = titre("Métiers pour un " .. (c and c.nom or "personnage"))
  for _, m in ipairs(c and c.metiers or {}) do
    L[#L + 1] = (BADGES[m[3]] or "") .. " " .. m[1]
    L[#L + 1] = GRIS .. m[2] .. FIN
  end
  L[#L + 1] = ""
  L[#L + 1] = titre("À faire maintenant")
  if not e.metiers or #e.metiers == 0 then
    L[#L + 1] = "Tu n'as appris aucun métier. Le premier palier (jusqu'à 75) s'apprend dès le niveau 1 chez un maître de métier, dans une ville."
  else
    for _, m in ipairs(e.metiers) do L[#L + 1] = "- " .. ns.aFaireMetier(m, e.niveau) end
  end
  return table.concat(L, "\n")
end

function ns.infosRace(token)
  return D.RACES[token] or D.RACE_PAR_DEFAUT
end

function ns.vueRace(e)
  local r = ns.infosRace(e.raceToken)
  local nom = r.nom
  if r == D.RACE_PAR_DEFAUT and e.raceNom then nom = e.raceNom end
  local L = {}
  L[#L + 1] = titre(nom .. " : tes capacités de race")
  for _, rac in ipairs(r.raciales) do
    L[#L + 1] = (rac[3] and (BLEU .. "[à lancer] " .. FIN) or (GRIS .. "[toujours actif] " .. FIN)) .. rac[1]
    L[#L + 1] = GRIS .. rac[2] .. FIN
  end
  return table.concat(L, "\n")
end

-- Les cinq onglets, dans l'ordre : { clé, nom, fonction du texte }.
ns.ONGLETS = {
  { "talents", "Talents", ns.vueTalents },
  { "rotation", "Rotation", ns.vueRotation },
  { "equipement", "Équipement", ns.vueEquipement },
  { "metiers", "Métiers", ns.vueMetiers },
  { "race", "Race", ns.vueRace },
}
