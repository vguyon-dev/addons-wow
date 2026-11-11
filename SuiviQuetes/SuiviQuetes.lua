-- ============================================================================
-- Suivi des quêtes : un panneau à nous qui remplace le suivi des objectifs du jeu.
--
-- Les quêtes suivies sont rangées en sections repliables, dans cet ordre :
--   À rendre (quêtes finies, tout en haut), Principal, Général, Donjons et groupe,
--   Classe, Métiers, JcJ, Journalières et répétables.
-- Une section vide n'est pas affichée. Chaque quête montre une pastille, son niveau et
-- son titre (coloré selon la difficulté), la distance si le jeu la donne, puis ses objectifs.
--
--   Clic : choisir la quête (le GPS la suit alors)
--   Survol : la description de la quête (l'addon n'ouvre jamais le journal du jeu, voir plus bas)
--   Maj + clic : ne plus suivre         Clic droit : menu (ranger la quête ailleurs…)
--   /sq : les réglages    /sq genre : ce que le jeu dit de chaque quête suivie
--   /sq centre : remet le panneau à sa place    /sq aide : la liste des commandes
--
-- Le suivi du jeu est caché (option), sauf en combat (on n'y touche pas : il porte des
-- boutons protégés) et dans une instance, où il porte les objectifs de scénario.
-- Les boutons d'objet de quête vivent dans un cadre à part, jamais accroché au panneau :
-- un cadre qui porte un bouton protégé devient intouchable en combat.
--
-- Le fichier a deux parties : la logique pure (testée hors jeu, tests/SuiviQuetes_simu.lua)
-- puis tout ce qui parle au jeu.
-- ============================================================================

local NOM_ADDON, ns = ...

local DEFAUTS = {
  actif = true,
  rendreEnHaut = true,       -- les quêtes finies dans une section « À rendre », tout en haut
  uneLigne = false,          -- une seule ligne par quête (sans les objectifs)
  distance = true,           -- la distance à droite du titre
  cacherAutresZones = false, -- ne garder que les quêtes de la zone où tu es (donjons et quêtes à rendre restent)
  toutesLesQuetes = false,   -- toutes les quêtes du journal, pas seulement les suivies
  largeur = 300,
  taille = 100,              -- en %
  fondSombre = false,
  verrouiller = false,
  cacherSuiviJeu = true,     -- cacher le suivi des objectifs du jeu
  boutonsObjets = true,      -- les boutons des objets de quête
  minimap = false,
  genres = {},               -- [numéro de quête] = genre choisi à la main
}

-- ---------------------------------------------------------------------------
-- Partie « logique pure » : aucune fonction du jeu, donc testable hors jeu.
-- ---------------------------------------------------------------------------

-- Les genres, dans l'ordre d'affichage des sections.
local ORDRE = { "aRendre", "principal", "general", "donjon", "classe", "metiers", "jcj", "repetable" }
local NOMS_GENRES = {
  aRendre = "À rendre", principal = "Principal", general = "Général", donjon = "Donjons et groupe",
  classe = "Classe", metiers = "Métiers", jcj = "JcJ", repetable = "Journalières et répétables",
}
ns.ORDRE_GENRES = ORDRE
ns.NOMS_GENRES = NOMS_GENRES

-- Ce que le menu du clic droit propose (en plus d'« Automatique »).
ns.GENRES_MANUELS = { "principal", "general", "donjon", "classe", "metiers" }

-- Un texte comparable : sans accents ni majuscules, apostrophes et tirets en espaces.
local ACCENTS = {
  { "é", "e" }, { "è", "e" }, { "ê", "e" }, { "ë", "e" }, { "à", "a" }, { "â", "a" }, { "î", "i" }, { "ï", "i" },
  { "ô", "o" }, { "û", "u" }, { "ù", "u" }, { "ü", "u" }, { "ç", "c" }, { "œ", "oe" },
  { "É", "e" }, { "È", "e" }, { "Ê", "e" }, { "Ë", "e" }, { "À", "a" }, { "Â", "a" }, { "Ç", "c" }, { "Î", "i" },
  { "Ï", "i" }, { "Ô", "o" }, { "Û", "u" }, { "Ù", "u" }, { "Ü", "u" }, { "Œ", "oe" },
}
-- Mémoire des textes déjà normalisés : la liste des classes et des métiers revient à chaque passe,
-- inutile de la recalculer (23 remplacements par nom). Vidée si elle grossit trop.
local memoSansAccents, nbMemo = {}, 0
local function sansAccents(t)
  t = tostring(t or "")
  local connu = memoSansAccents[t]
  if connu then return connu end
  local brut = t
  for _, p in ipairs(ACCENTS) do t = t:gsub(p[1], p[2]) end
  t = t:gsub("’", "'"):lower()
  t = t:gsub("[%-']", " "):gsub("%s+", " ")
  t = t:gsub("^ ", ""):gsub(" $", "")
  if nbMemo >= 3000 then memoSansAccents, nbMemo = {}, 0 end
  memoSansAccents[brut] = t
  nbMemo = nbMemo + 1
  return t
end
ns.sansAccents = sansAccents

-- Un numéro d'énumération du jeu, avec un repli chiffré quand l'énumération manque.
local function enumeration(table_, nom, repli)
  if type(table_) == "table" and type(table_[nom]) == "number" then return table_[nom] end
  return repli
end

local ENUM_TAG = type(Enum) == "table" and Enum.QuestTag or nil
local ENUM_CLASSIF = type(Enum) == "table" and Enum.QuestClassification or nil
local ENUM_FREQ = type(Enum) == "table" and Enum.QuestFrequency or nil

-- Les étiquettes (tagID) de C_QuestLog.GetQuestTagInfo. Repli : numéros de la documentation de Forever.
local TAG_GROUPE = enumeration(ENUM_TAG, "Group", 1)
local TAG_PVP = enumeration(ENUM_TAG, "PvP", 41)
local TAG_RAID = enumeration(ENUM_TAG, "Raid", 62)
local TAG_DONJON = enumeration(ENUM_TAG, "Dungeon", 81)
local TAG_HEROIQUE = enumeration(ENUM_TAG, "Heroic", 85)
local TAG_RAID10 = enumeration(ENUM_TAG, "Raid10", 88)
local TAG_RAID25 = enumeration(ENUM_TAG, "Raid25", 89)
local TAG_SCENARIO = enumeration(ENUM_TAG, "Scenario", 98)
local TAG_EXPEDITION = enumeration(ENUM_TAG, "Delve", 288)
-- « Classe » (21 dans les anciennes versions) n'est pas dans l'énumération de Forever : repli chiffré.
-- « Métier » n'a pas de numéro sûr : on s'appuie sur la rubrique ou sur tradeskillLineID.
local TAG_CLASSE = enumeration(ENUM_TAG, "Class", 21)
local TAG_METIER = enumeration(ENUM_TAG, "Profession", nil)
local TAGS_GROUPE = {}
for _, t in ipairs({ TAG_GROUPE, TAG_RAID, TAG_DONJON, TAG_HEROIQUE, TAG_RAID10, TAG_RAID25, TAG_SCENARIO, TAG_EXPEDITION }) do
  TAGS_GROUPE[t] = true
end

-- Classification d'une quête (C_QuestInfoSystem.GetQuestClassification). Repli : les valeurs de
-- Enum.QuestClassification dans la documentation de la branche forever (Important 0, Legendary 1,
-- Campaign 2, Calling 3, Meta 4, Recurring 5, Questline 6, Normal 7).
local CL_SUITE = enumeration(ENUM_CLASSIF, "Questline", 6)
local CL_IMPORTANTE = enumeration(ENUM_CLASSIF, "Important", 0)
local CL_LEGENDAIRE = enumeration(ENUM_CLASSIF, "Legendary", 1)
local CL_CAMPAGNE = enumeration(ENUM_CLASSIF, "Campaign", 2)
local CL_REPETABLE = enumeration(ENUM_CLASSIF, "Recurring", 5)
local CLASSIFS_PRINCIPALES = {}
for _, c in ipairs({ CL_SUITE, CL_IMPORTANTE, CL_LEGENDAIRE, CL_CAMPAGNE }) do CLASSIFS_PRINCIPALES[c] = true end

-- Fréquence d'une quête (documentation de Forever : 0 normale, 1 journalière, 2 hebdomadaire, 3 planifiée).
local FREQUENCES_REPETABLES = {}
for _, f in ipairs({ enumeration(ENUM_FREQ, "Daily", 1), enumeration(ENUM_FREQ, "Weekly", 2),
                     enumeration(ENUM_FREQ, "ResetByScheduler", 3) }) do
  FREQUENCES_REPETABLES[f] = true
end

-- Noms de métiers connus, en français et en anglais (la rubrique du journal porte parfois ce nom).
ns.METIERS_CONNUS = {
  "Alchimie", "Forge", "Enchantement", "Ingénierie", "Calligraphie", "Joaillerie", "Travail du cuir",
  "Couture", "Minage", "Herboristerie", "Dépeçage", "Cuisine", "Pêche", "Secourisme", "Archéologie",
  "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Inscription", "Jewelcrafting", "Leatherworking",
  "Tailoring", "Mining", "Herbalism", "Skinning", "Cooking", "Fishing", "First Aid", "Archaeology",
  "Métiers", "Professions",
}

-- Le texte est-il dans la liste (comparaison sans accents ni majuscules) ?
local function dansListe(liste, texte)
  if texte == "" then return false end
  for _, n in ipairs(liste or {}) do
    if sansAccents(n) == texte then return true end
  end
  return false
end

-- Sur Forever, le jeu ne dit presque rien du genre (relevé en jeu le 10/11 : pas d'étiquette
-- hors « Donjon », rubrique = la zone). Pour les métiers, on lit donc le texte des objectifs :
-- « Atteindre une compétence de 20 en secourisme » parle de compétence ET nomme un métier.
function ns.parleDeMetier(texte, metiers)
  local t = sansAccents(texte)
  if t == "" or not (t:find("competence", 1, true) or t:find("skill", 1, true)) then return false end
  for _, n in ipairs(metiers or {}) do
    local m = sansAccents(n)
    if m ~= "" and t:find(m, 1, true) then return true end
  end
  return false
end

-- Le genre d'une quête. Fonction pure : tout ce qu'il faut vient des deux tables.
--   infos : ce que dit le jeu { numero, rubrique, tagID, tagName, classification, campaignID,
--           frequency, suggestedGroup, elite, tradeskill, fini }
--   contexte : { classe = nom de ta classe, classes = { noms }, metiers = { noms },
--                manuel = { [numéro] = genre choisi à la main }, rendreEnHaut = vrai/faux }
-- Ordre : choix manuel > à rendre > donjon/groupe > JcJ > classe > métier > principal > répétable > général.
function ns.genreQuete(infos, contexte)
  infos = type(infos) == "table" and infos or {}
  contexte = type(contexte) == "table" and contexte or {}
  local manuel = infos.numero and contexte.manuel and contexte.manuel[infos.numero]
  if manuel and NOMS_GENRES[manuel] then return manuel end
  if infos.fini and contexte.rendreEnHaut then return "aRendre" end

  local tag = infos.tagID
  if (tag and TAGS_GROUPE[tag]) or infos.elite or (tonumber(infos.suggestedGroup) or 0) > 1 then return "donjon" end
  if tag and tag == TAG_PVP then return "jcj" end

  local rubrique = sansAccents(infos.rubrique)
  if (tag and tag == TAG_CLASSE) or (rubrique ~= "" and (rubrique == sansAccents(contexte.classe)
     or dansListe(contexte.classes, rubrique))) then
    return "classe"
  end
  local ligneMetier = tonumber(infos.tradeskill)
  if (tag and TAG_METIER and tag == TAG_METIER) or (ligneMetier and ligneMetier ~= 0)
     or dansListe(contexte.metiers, rubrique) or ns.parleDeMetier(infos.texte, contexte.metiers) then
    return "metiers"
  end

  local campagne = tonumber(infos.campaignID)
  if (campagne and campagne ~= 0) or (infos.classification and CLASSIFS_PRINCIPALES[infos.classification]) then
    return "principal"
  end
  if (infos.frequency and FREQUENCES_REPETABLES[infos.frequency]) or infos.classification == CL_REPETABLE then
    return "repetable"
  end
  return "general"
end

-- Le texte de distance : « 140 m », « 2,6 km » (virgule décimale) ; nil si on ne sait pas.
function ns.texteDistance(metres)
  if type(metres) ~= "number" or metres ~= metres or metres < 0 or metres == math.huge then return nil end
  local arrondi = math.floor(metres + 0.5)
  if arrondi < 1000 then return arrondi .. " m" end
  return (string.format("%.1f", metres / 1000):gsub("%.", ",")) .. " km"
end

-- La couleur d'un titre selon la difficulté, comme le jeu (rouge, orange, jaune, vert, gris).
-- plageVerte : combien de niveaux sous toi la quête reste verte (GetQuestGreenRange, 8 au besoin).
function ns.couleurDifficulte(niveauQuete, niveauJoueur, plageVerte)
  if type(niveauQuete) ~= "number" or niveauQuete <= 0 or type(niveauJoueur) ~= "number" then return 1, 1, 1 end
  local ecart = niveauQuete - niveauJoueur
  if ecart >= 5 then return 1, 0.1, 0.1 end
  if ecart >= 3 then return 1, 0.5, 0.25 end
  if ecart >= -2 then return 1, 1, 0 end
  if -ecart <= (tonumber(plageVerte) or 8) then return 0.25, 0.75, 0.25 end
  return 0.5, 0.5, 0.5
end

-- La quête est-elle de la zone où tu es ? Le jeu le dit (isOnMap), ou sa rubrique porte le nom de la zone.
function ns.estIci(surLaCarte, rubrique, nomsZone)
  if surLaCarte then return true end
  local r = sansAccents(rubrique)
  if r == "" then return false end
  for _, z in ipairs(nomsZone or {}) do
    if sansAccents(z) == r then return true end
  end
  return false
end

-- Le tri d'une section : d'abord les quêtes de la zone, puis la distance croissante
-- (inconnue à la fin), puis le niveau, puis le titre, puis le numéro.
local function avant(a, b)
  local ia, ib = a.ici and true or false, b.ici and true or false
  if ia ~= ib then return ia end
  local da, db = a.distance, b.distance
  if da ~= db then
    if da == nil then return false end
    if db == nil then return true end
    return da < db
  end
  local na, nb = a.niveau or 0, b.niveau or 0
  if na ~= nb then return na < nb end
  local ta, tb = sansAccents(a.titre), sansAccents(b.titre)
  if ta ~= tb then return ta < tb end
  return (a.numero or 0) < (b.numero or 0)
end

function ns.trierQuetes(liste)
  table.sort(liste, avant)
  return liste
end

-- Le regroupement : une section par genre, dans l'ordre fixe, chacune triée ; une section vide
-- n'existe pas. Chaque quête porte son genre (q.genre) ; un genre inconnu devient « Général ».
function ns.sections(quetes)
  local parGenre = {}
  for _, q in ipairs(quetes or {}) do
    local g = NOMS_GENRES[q.genre] and q.genre or "general"
    parGenre[g] = parGenre[g] or {}
    table.insert(parGenre[g], q)
  end
  local sections = {}
  for _, g in ipairs(ORDRE) do
    if parGenre[g] and #parGenre[g] > 0 then
      sections[#sections + 1] = { genre = g, nom = NOMS_GENRES[g], quetes = ns.trierQuetes(parGenre[g]) }
    end
  end
  return sections
end

-- Garde ou non une quête dans l'affichage quand « cacher les autres zones » est coché :
-- celles de la zone, les donjons et les quêtes à rendre restent.
function ns.garderQuete(q, cacherAutresZones)
  if not cacherAutresZones then return true end
  return q.ici == true or q.genre == "donjon" or q.genre == "aRendre"
end

local function nettoyer(t)
  t = tostring(t or ""):gsub("^%s+", ""):gsub("%s+$", "")
  return t
end

-- Les lignes d'objectifs à afficher sous une quête : { { texte, fini } }.
-- q : { fini, objectifs = { { text, finished } }, texteFin, texteCourt }.
--  - quête finie : une seule ligne « À rendre : … » ;
--  - sinon un objectif par ligne (verts quand finis) ;
--  - sans aucun objectif : le texte court du journal, comme le suivi du jeu.
function ns.objectifsAffiches(q)
  local lignes = {}
  if q.fini then
    local fin = nettoyer(q.texteFin)
    lignes[1] = { texte = fin ~= "" and ("À rendre : " .. fin) or "À rendre", fini = true }
    return lignes
  end
  for _, o in ipairs(q.objectifs or {}) do
    local t = nettoyer(o.text)
    if t ~= "" then lignes[#lignes + 1] = { texte = t, fini = o.finished and true or false } end
  end
  if #lignes == 0 then
    local court = nettoyer(q.texteCourt)
    if court ~= "" then lignes[1] = { texte = court, fini = false } end
  end
  return lignes
end

-- Le texte des objectifs, tel que le panneau l'écrit (« - Texte : 0/4 », vert quand fini).
function ns.texteObjectifs(lignes)
  local morceaux = {}
  for _, l in ipairs(lignes or {}) do
    morceaux[#morceaux + 1] = (l.fini and "|cff40e040" or "|cffd8d8d8") .. "- " .. l.texte .. "|r"
  end
  return table.concat(morceaux, "\n")
end

-- Le titre d'une quête : « [12] Titre ».
function ns.titreAffiche(niveau, titre)
  titre = tostring(titre or "?")
  if type(niveau) == "number" and niveau > 0 then return "[" .. niveau .. "] " .. titre end
  return titre
end

-- Où poser le cadre des boutons d'objet : à gauche du panneau, en haut ; à droite s'il n'y a pas
-- la place à gauche. Les valeurs du panneau (gauche, droite, haut) sont dans SON échelle ; le résultat
-- est en coordonnées de l'écran (UIParent), à utiliser avec SetPoint(point, UIParent, "BOTTOMLEFT", x, y).
function ns.positionPorteur(gauche, droite, haut, echelleCadre, echelleParent, largeurBouton)
  local e = (tonumber(echelleCadre) or 1) / ((tonumber(echelleParent) or 1) ~= 0 and echelleParent or 1)
  local g, d, h = (gauche or 0) * e, (droite or 0) * e, (haut or 0) * e
  local marge, entete = 6, 24
  if g - marge - (largeurBouton or 36) >= 0 then return "TOPRIGHT", g - marge, h - entete end
  return "TOPLEFT", d + marge, h - entete
end

-- Un objet d'une quête s'affiche-t-il ? (comme le jeu : pas sur une quête finie, sauf si l'objet le demande)
function ns.objetAffiche(lien, fini, afficherQuandFinie)
  if type(lien) ~= "string" or lien == "" then return false end
  return (not fini) or (afficherQuandFinie and true or false)
end

-- Le numéro d'objet d'un lien (« |Hitem:12345:… »), ou nil.
function ns.numeroObjet(lien)
  if type(lien) ~= "string" then return nil end
  return tonumber(lien:match("item:(%d+)"))
end

-- Les décalages d'une position sont dans l'échelle du panneau : on garde l'échelle du moment (5e valeur)
-- et on les convertit quand la taille change, pour que le panneau ne bouge pas à l'écran.
function ns.decalageEchelle(x, y, ancienne, nouvelle)
  local f = (tonumber(ancienne) or nouvelle or 1) / ((tonumber(nouvelle) or 1) ~= 0 and nouvelle or 1)
  return x * f, y * f
end

if not CreateFrame then return end -- hors jeu : la suite ne sert qu'en jeu

-- ---------------------------------------------------------------------------
-- Les fonctions du jeu, toutes protégées : si l'une manque sur une version, la ligne
-- concernée est simplement absente.
-- ---------------------------------------------------------------------------

local db, perso

-- Appelle f sous pcall ; rend ses résultats, ou rien si elle manque ou plante.
local function sur(f, ...)
  if type(f) ~= "function" then return end
  local ok, a, b, c, d = pcall(f, ...)
  if ok then return a, b, c, d end
end

-- C_QuestLog.<nom>(...) en protégé.
local function ql(nom, ...)
  local t = C_QuestLog
  local f = type(t) == "table" and t[nom]
  if f then return sur(f, ...) end
end

local function enCombat() return InCombatLockdown and InCombatLockdown() and true or false end

local function dire(texte)
  if ns.reglages then ns.reglages.dire(texte) else print("|cffffd200Suivi des quêtes|r : " .. texte) end
end

-- La quête choisie dans le suivi (super suivie), ou nil.
local function choisie()
  local t = C_SuperTrack
  if type(t) ~= "table" then return nil end
  local id = sur(t.GetSuperTrackedQuestID)
  if type(id) == "number" and id ~= 0 then return id end
end

-- Les noms de classes, de ta classe et de tes métiers, pour classer les quêtes.
local classesConnues
local function nomsClasses()
  if classesConnues then return classesConnues end
  classesConnues = {}
  for _, t in ipairs({ LOCALIZED_CLASS_NAMES_MALE or {}, LOCALIZED_CLASS_NAMES_FEMALE or {} }) do
    for _, nom in pairs(t) do
      if type(nom) == "string" then classesConnues[#classesConnues + 1] = nom end
    end
  end
  local nombre = sur(GetNumClasses)
  if type(nombre) == "number" then
    for i = 1, nombre do
      local nom = sur(GetClassInfo, i)
      if type(nom) == "string" then classesConnues[#classesConnues + 1] = nom end
    end
  end
  return classesConnues
end

local function nomsMetiers()
  local l = {}
  for _, n in ipairs(ns.METIERS_CONNUS) do l[#l + 1] = n end
  if GetProfessions and GetProfessionInfo then
    -- GetProfessions rend six numéros (deux principaux, archéologie, pêche, cuisine, secourisme).
    local r = { pcall(GetProfessions) }
    if r[1] then
      for i = 2, 7 do
        local index = r[i]
        if index then
          local nom = sur(GetProfessionInfo, index)
          if type(nom) == "string" then l[#l + 1] = nom end
        end
      end
    end
  end
  return l
end

local function contexteGenres()
  return {
    classe = (sur(UnitClass, "player")),
    classes = nomsClasses(),
    metiers = nomsMetiers(),
    manuel = db and db.genres or {},
    rendreEnHaut = db and db.rendreEnHaut,
  }
end

local function nomsZone()
  local l = {}
  for _, f in ipairs({ GetRealZoneText or false, GetZoneText or false }) do
    if f then
      local z = sur(f)
      if type(z) == "string" and z ~= "" then l[#l + 1] = z end
    end
  end
  return l
end

-- ---------------------------------------------------------------------------
-- Lire les quêtes
-- ---------------------------------------------------------------------------

-- Le texte court d'objectif du journal (pour une quête sans objectif chiffré). On lit une fois par
-- quête et on le garde : choisir une quête dans le journal change sa sélection, il ne faut pas le
-- refaire à chaque rafraîchissement ni quand la carte est ouverte.
local cacheCourt = {}
local function texteCourtDe(id, index)
  if cacheCourt[id] then return cacheCourt[id] end
  if not (index and GetQuestLogQuestText) then return nil end
  -- Comme le journal du jeu : on passe l'index de la quête, sans changer la sélection du journal.
  local _, objectifs = sur(GetQuestLogQuestText, index)
  -- Un résultat vide n'est pas gardé : les données peuvent ne pas être encore chargées, on réessaie.
  if type(objectifs) == "string" and objectifs ~= "" then
    cacheCourt[id] = objectifs
    return objectifs
  end
  return nil
end

-- L'objet à utiliser d'une quête : lien, icône, et s'il doit s'afficher.
local function objetDeQuete(index, fini)
  if not index then return nil end
  local f = GetQuestLogSpecialItemInfo or (C_QuestLog and C_QuestLog.GetQuestLogSpecialItemInfo)
  local lien, icone, _, quandFinie = sur(f, index)
  if not ns.objetAffiche(lien, fini, quandFinie) then return nil end
  local numero = ns.numeroObjet(lien)
  if not numero then return nil end
  return { lien = lien, icone = icone, numero = numero, index = index }
end

-- Une quête (info du journal + rubrique) devient une fiche pour le panneau.
local function fiche(id, info, rubrique, zones, contexte)
  local tag = ql("GetQuestTagInfo", id)
  if type(tag) ~= "table" then tag = {} end
  local classification = info.questClassification
  if classification == nil and C_QuestInfoSystem then
    classification = sur(C_QuestInfoSystem.GetQuestClassification, id)
  end
  local fini = ql("IsComplete", id) == true
  local niveau = (type(info.difficultyLevel) == "number" and info.difficultyLevel > 0) and info.difficultyLevel or info.level
  local q = {
    numero = id, titre = type(info.title) == "string" and info.title or "?", niveau = niveau,
    index = info.questLogIndex, fini = fini, rubrique = rubrique,
    ici = ns.estIci(info.isOnMap, rubrique, zones),
    infos = {
      numero = id, rubrique = rubrique, tagID = tag.tagID, tagName = tag.tagName, classification = classification,
      campaignID = info.campaignID, frequency = info.frequency, suggestedGroup = info.suggestedGroup,
      elite = tag.isElite, tradeskill = tag.tradeskillLineID, fini = fini,
    },
  }
  local objectifs = ql("GetQuestObjectives", id)
  q.objectifs = type(objectifs) == "table" and objectifs or {}
  -- Le texte des objectifs sert aussi à reconnaître une quête de métier (voir ns.parleDeMetier).
  local morceaux = {}
  for _, o in ipairs(q.objectifs) do
    if type(o) == "table" and type(o.text) == "string" then morceaux[#morceaux + 1] = o.text end
  end
  q.infos.texte = table.concat(morceaux, " ")
  q.genre = ns.genreQuete(q.infos, contexte)
  q.manuel = db and db.genres and db.genres[id] ~= nil
  if fini and q.index then
    local fin = sur(GetQuestLogCompletionText, q.index)
    if type(fin) == "string" then q.texteFin = fin end
  end
  if not fini and #q.objectifs == 0 then q.texteCourt = texteCourtDe(id, q.index) end
  if db.distance then
    local carre = ql("GetDistanceSqToQuest", id)
    if type(carre) == "number" and carre >= 0 then q.distance = math.sqrt(carre) end
  end
  if db.boutonsObjets then q.objet = objetDeQuete(q.index, fini) end
  return q
end

-- Les quêtes à montrer : les suivies (ou tout le journal), sans les cachées, tâches et quêtes mondiales.
local function collecter(sansFiltre)
  local zones, contexte = nomsZone(), contexteGenres()
  -- Le journal tel qu'il s'affiche : chaque quête avec la rubrique (l'en-tête) sous laquelle elle est rangée.
  local journal, ordre, rubrique = {}, {}, nil
  local nombre = ql("GetNumQuestLogEntries")
  for i = 1, type(nombre) == "number" and nombre or 0 do
    local info = ql("GetInfo", i)
    if type(info) == "table" then
      if info.isHeader then
        rubrique = info.title
      elseif info.questID then
        journal[info.questID] = { info = info, rubrique = rubrique }
        ordre[#ordre + 1] = info.questID
      end
    end
  end
  local ids = {}
  if db.toutesLesQuetes then
    ids = ordre
  else
    local suivies = ql("GetNumQuestWatches")
    for i = 1, type(suivies) == "number" and suivies or 0 do
      local id = ql("GetQuestIDForQuestWatchIndex", i)
      if type(id) == "number" then ids[#ids + 1] = id end
    end
  end
  local quetes, vues = {}, {}
  for _, id in ipairs(ids) do
    if not vues[id] then
      vues[id] = true
      local entree = journal[id]
      if not entree then
        -- Une quête rangée sous une zone repliée dans le journal : on la retrouve par son numéro.
        local index = ql("GetLogIndexForQuestID", id)
        local info = index and ql("GetInfo", index)
        if type(info) == "table" and not info.isHeader then
          local h = ql("GetHeaderIndexForQuest", id)
          local entete = h and ql("GetInfo", h)
          entree = { info = info, rubrique = type(entete) == "table" and entete.title or nil }
        end
      end
      local info = entree and entree.info
      if info and not (info.isHidden or info.isTask or info.isBounty or ql("IsWorldQuest", id) == true) then
        local q = fiche(id, info, entree.rubrique, zones, contexte)
        if sansFiltre or ns.garderQuete(q, db.cacherAutresZones) then quetes[#quetes + 1] = q end
      end
    end
  end
  return quetes
end
ns.collecter = collecter

-- ---------------------------------------------------------------------------
-- Le panneau
-- ---------------------------------------------------------------------------

local ECHELLE_MAX = 0.70 -- hauteur maximale du panneau, en part de l'écran
local HAUT_ENTETE, HAUT_SECTION = 24, 20

local cadre = CreateFrame("Frame", "SuiviQuetesCadre", UIParent)
cadre:SetSize(300, 60)
cadre:SetMovable(true)
cadre:SetClampedToScreen(true)
cadre:Hide()

local entete = CreateFrame("Button", nil, cadre)
entete:SetHeight(HAUT_ENTETE)
entete:SetPoint("TOPLEFT", cadre, "TOPLEFT", 0, 0)
entete:SetPoint("TOPRIGHT", cadre, "TOPRIGHT", 0, 0)
entete:RegisterForDrag("LeftButton")
entete:RegisterForClicks("RightButtonUp")
local titreEntete = entete:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
titreEntete:SetPoint("LEFT", entete, "LEFT", 6, 0)
titreEntete:SetText("Quêtes")
local traitEntete = entete:CreateTexture(nil, "ARTWORK")
traitEntete:SetColorTexture(1, 0.82, 0, 0.6)
traitEntete:SetHeight(1)
traitEntete:SetPoint("BOTTOMLEFT", entete, "BOTTOMLEFT", 4, 0)
traitEntete:SetPoint("BOTTOMRIGHT", entete, "BOTTOMRIGHT", -4, 0)

local defil = CreateFrame("ScrollFrame", nil, cadre)
defil:SetPoint("TOPLEFT", entete, "BOTTOMLEFT", 0, -2)
defil:SetPoint("BOTTOMRIGHT", cadre, "BOTTOMRIGHT", 0, 2)
defil:EnableMouseWheel(true)
local contenu = CreateFrame("Frame", nil, defil)
contenu:SetSize(290, 10)
defil:SetScrollChild(contenu)

defil:SetScript("OnMouseWheel", function(self, delta)
  local actuel = self:GetVerticalScroll() or 0
  local maxi = math.max(0, (contenu:GetHeight() or 0) - (self:GetHeight() or 0))
  self:SetVerticalScroll(math.min(maxi, math.max(0, actuel - delta * 40)))
end)

-- L'ombre du texte, comme le jeu.
local function ombre(fs)
  fs:SetShadowOffset(1, -1)
  fs:SetShadowColor(0, 0, 0, 1)
end
ombre(titreEntete)

local sectionsAffichees = {} -- ce qui est dessiné en ce moment (pour redessiner sans tout relire)
local demander, redessiner

-- ----- le menu du clic droit, fait main (pas UIDropDownMenu, qui contamine le jeu)

local rideau = CreateFrame("Button", nil, UIParent)
rideau:SetAllPoints(UIParent)
rideau:SetFrameStrata("DIALOG")
rideau:RegisterForClicks("AnyUp")
rideau:Hide()
local menu = CreateFrame("Frame", "SuiviQuetesMenu", UIParent)
menu:SetFrameStrata("DIALOG")
menu:SetFrameLevel(rideau:GetFrameLevel() + 5)
menu:EnableMouse(true)
menu:SetSize(210, 40)
ns.habiller(menu)
menu:Hide()
if UISpecialFrames then table.insert(UISpecialFrames, "SuiviQuetesMenu") end
rideau:SetScript("OnClick", function() menu:Hide() end)
menu:SetScript("OnHide", function() rideau:Hide() end)
local lignesMenu = {}

local function ligneMenu(i)
  local b = lignesMenu[i]
  if b then return b end
  b = CreateFrame("Button", nil, menu)
  b:SetHeight(20)
  b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  b.texte = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  b.texte:SetPoint("LEFT", b, "LEFT", 8, 0)
  b.texte:SetJustifyH("LEFT")
  b:SetScript("OnClick", function(self)
    local action = self.action
    menu:Hide()
    if action then action() end
  end)
  lignesMenu[i] = b
  return b
end

-- entrees : { { texte, action, coche, titre = vrai (en-tête, pas cliquable) } }
local function afficherMenu(entrees)
  local y = 8
  for i, e in ipairs(entrees) do
    local b = ligneMenu(i)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", menu, "TOPLEFT", 6, -y)
    b:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -6, -y)
    b.action = (not e.titre) and e.action or nil
    b:EnableMouse(not e.titre)
    b.texte:SetText((e.coche and "|cff40ff40> |r" or "") .. e.texte)
    if e.titre then b.texte:SetTextColor(1, 0.82, 0.3) else b.texte:SetTextColor(1, 1, 1) end
    b:Show()
    y = y + 20
  end
  for i = #entrees + 1, #lignesMenu do lignesMenu[i]:Hide() end
  menu:SetHeight(y + 8)
  local x, h = 0, 0
  if GetCursorPosition then x, h = GetCursorPosition() end
  local e = (UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
  menu:ClearAllPoints()
  menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", (x or 0) / e - 10, (h or 0) / e + 10)
  menu:SetClampedToScreen(true)
  rideau:Show()
  menu:Show()
end

-- ----- les actions sur une quête

-- On n'ouvre JAMAIS le journal ni la carte du jeu depuis l'addon. Jusqu'à la 0.1.4, un clic sur
-- la quête choisie appelait QuestMapFrame_OpenToQuestDetails. Cette fonction du jeu écrit dans
-- les cadres de la carte (la quête affichée, la carte montrée) : écrites par un addon, ces
-- valeurs restent « marquées » jusqu'au /reload. Ensuite, chaque fois que le joueur ouvrait sa
-- carte EN COMBAT avec sa touche, le jeu refusait de poser les marques de quêtes et levait
-- « action bloquée … SetPassThroughButtons » au nom de Suivi des quêtes (des dizaines de fois,
-- vu en jeu le 10/11, chez deux joueurs). Refuser l'appel en combat ne suffisait pas : le clic
-- fait AVANT le combat suffisait à marquer la carte. À la place, la bulle de la quête montre sa
-- description, lue par une fonction qui ne touche à aucun cadre du jeu.
local cacheDescription = {}
local function descriptionDe(id, index)
  if not id then return nil end
  if cacheDescription[id] then return cacheDescription[id] end
  if not (index and GetQuestLogQuestText) then return nil end
  local description = sur(GetQuestLogQuestText, index)
  -- Un résultat vide n'est pas gardé : les données peuvent ne pas être encore chargées.
  if type(description) == "string" and description ~= "" then
    cacheDescription[id] = description
    return description
  end
  return nil
end

local function choisirQuete(id)
  if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then sur(C_SuperTrack.SetSuperTrackedQuestID, id) end
  demander()
end

local function nePlusSuivre(id)
  ql("RemoveQuestWatch", id)
  if db.toutesLesQuetes then dire("la quête n'est plus suivie dans le jeu (elle reste ici : « toutes les quêtes du journal » est coché).") end
  demander()
end

local function menuQuete(ligne)
  local id = ligne.numero
  if not id then return end
  local manuel = db.genres[id]
  local entrees = {
    { texte = ligne.titreBrut or "Quête", titre = true },
    { texte = "Ranger dans :", titre = true },
    { texte = "Automatique", coche = manuel == nil, action = function() db.genres[id] = nil; demander() end },
  }
  for _, g in ipairs(ns.GENRES_MANUELS) do
    entrees[#entrees + 1] = { texte = NOMS_GENRES[g], coche = manuel == g, action = function() db.genres[id] = g; demander() end }
  end
  entrees[#entrees + 1] = { texte = "Ne plus suivre", action = function() nePlusSuivre(id) end }
  afficherMenu(entrees)
end

-- ----- les lignes (réutilisées, jamais recréées à chaque rafraîchissement)

local lignesQuetes, lignesSections = {}, {}

local function infobulleQuete(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:AddLine(self.titreBrut or "Quête", 1, 0.82, 0)
  if self.genreNom then
    GameTooltip:AddLine("Rangée dans : " .. self.genreNom .. (self.manuel and " (ton choix)" or ""), 0.8, 0.8, 0.8)
  end
  local description = descriptionDe(self.numero, self.index)
  if description then GameTooltip:AddLine(description, 0.9, 0.9, 0.9, true) end
  GameTooltip:AddLine("Clic : choisir la quête (le GPS la suit)\nMaj + clic : ne plus suivre\nClic droit : menu", 1, 1, 1)
  GameTooltip:AddLine("Abandonner ou partager : dans le journal du jeu.", 0.6, 0.6, 0.6)
  GameTooltip:Show()
end

local function creerLigneQuete()
  local b = CreateFrame("Button", nil, contenu)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  b.fond = b:CreateTexture(nil, "BACKGROUND")
  b.fond:SetAllPoints()
  b.fond:SetColorTexture(1, 0.82, 0, 0.14)
  b.trait = b:CreateTexture(nil, "ARTWORK")
  b.trait:SetColorTexture(1, 0.82, 0, 1)
  b.trait:SetWidth(2)
  b.trait:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  b.trait:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
  b.pastille = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  b.pastille:SetPoint("TOPLEFT", b, "TOPLEFT", 6, -4)
  b.pastille:SetWidth(14)
  b.titre = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  b.titre:SetPoint("TOPLEFT", b, "TOPLEFT", 22, -4)
  b.titre:SetJustifyH("LEFT")
  b.titre:SetWordWrap(true)   -- un titre long passe sur deux lignes, comme dans le suivi du jeu
  b.dist = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.dist:SetPoint("TOPRIGHT", b, "TOPRIGHT", -4, -5)
  b.dist:SetJustifyH("RIGHT")
  b.dist:SetWidth(54)
  b.obj = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.obj:SetJustifyH("LEFT")
  b.obj:SetJustifyV("TOP")
  b.obj:SetWordWrap(true)
  for _, fs in ipairs({ b.pastille, b.titre, b.dist, b.obj }) do ombre(fs) end
  b:SetScript("OnClick", function(self, bouton)
    local id = self.numero
    if not id then return end
    if bouton == "RightButton" then return menuQuete(self) end
    if IsShiftKeyDown and IsShiftKeyDown() then return nePlusSuivre(id) end
    -- Déjà choisie : rien de plus à faire (voir plus haut pourquoi on n'ouvre plus le journal).
    if choisie() == id then return end
    choisirQuete(id)
  end)
  b:SetScript("OnEnter", infobulleQuete)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

local function creerLigneSection()
  local b = CreateFrame("Button", nil, contenu)
  b:RegisterForClicks("LeftButtonUp")
  b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  b.icone = b:CreateTexture(nil, "ARTWORK")
  b.icone:SetSize(14, 14)
  b.icone:SetPoint("LEFT", b, "LEFT", 4, 0)
  b.nom = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  b.nom:SetPoint("LEFT", b.icone, "RIGHT", 4, 0)
  b.nombre = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.nombre:SetPoint("RIGHT", b, "RIGHT", -6, 0)
  ombre(b.nom)
  ombre(b.nombre)
  b:SetScript("OnClick", function(self)
    if not (self.genre and perso) then return end
    perso.replie[self.genre] = (not perso.replie[self.genre]) or nil
    -- Un rafraîchissement complet : les boutons d'objet des sections repliées doivent partir aussi.
    if ns.rafraichir then ns.rafraichir() else redessiner() end
  end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Clic : replier ou déplier la section")
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

local function remplirLigneQuete(b, q, largeur, choisieId)
  b.numero, b.titreBrut, b.manuel = q.numero, q.titre, q.manuel
  b.index = q.index   -- sa place dans le journal : sert à lire sa description pour la bulle
  b.genreNom = NOMS_GENRES[q.genre]
  local niveauJoueur = sur(UnitLevel, "player")
  -- Le jeu colore le titre d'après sa propre difficulté : on la lit d'abord, nos seuils servent de repli.
  local r, g, bl
  if C_PlayerInfo and C_PlayerInfo.GetContentDifficultyQuestForPlayer and GetDifficultyColor then
    local diff = sur(C_PlayerInfo.GetContentDifficultyQuestForPlayer, q.numero)
    if diff ~= nil then
      local c = sur(GetDifficultyColor, diff)
      if type(c) == "table" and c.r then r, g, bl = c.r, c.g, c.b end
    end
  end
  if not r then r, g, bl = ns.couleurDifficulte(q.niveau, niveauJoueur, sur(GetQuestGreenRange)) end
  b.titre:SetText(ns.titreAffiche(q.niveau, q.titre))
  b.titre:SetTextColor(r, g, bl)
  if q.fini then
    b.pastille:SetText("?")
    b.pastille:SetTextColor(1, 0.82, 0)
  else
    b.pastille:SetText("…")
    b.pastille:SetTextColor(0.8, 0.8, 0.8)
  end
  local texteDist = db.distance and ns.texteDistance(q.distance) or nil
  b.dist:SetText(texteDist or "")
  b.dist:SetTextColor(0.7, 0.7, 0.7)
  b.titre:SetWidth(largeur - 22 - (texteDist and 58 or 6))
  local hauteur = 4 + (b.titre:GetStringHeight() or 13) + 4
  local lignes = (not db.uneLigne) and ns.objectifsAffiches(q) or {}
  if #lignes > 0 then
    b.obj:ClearAllPoints()
    b.obj:SetPoint("TOPLEFT", b, "TOPLEFT", 22, -(hauteur - 2))
    b.obj:SetWidth(largeur - 22 - 6)
    b.obj:SetText(ns.texteObjectifs(lignes))
    b.obj:Show()
    hauteur = hauteur + (b.obj:GetStringHeight() or 12) + 2
  else
    b.obj:SetText("")
    b.obj:Hide()
  end
  local estChoisie = choisieId == q.numero
  b.fond:SetShown(estChoisie)
  b.trait:SetShown(estChoisie)
  b:SetSize(largeur, hauteur)
  return hauteur
end

-- Dessine les sections (déjà triées) dans le panneau.
function redessiner()
  local sections = sectionsAffichees
  local largeur = db.largeur
  cadre:SetWidth(largeur)
  contenu:SetWidth(largeur)
  local choisieId = choisie()
  local y, nS, nQ, total = 0, 0, 0, 0
  for _, s in ipairs(sections) do
    nS = nS + 1
    local ls = lignesSections[nS] or creerLigneSection()
    lignesSections[nS] = ls
    local replie = perso and perso.replie[s.genre]
    ls.genre = s.genre
    ls:ClearAllPoints()
    ls:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -y)
    ls:SetSize(largeur, HAUT_SECTION)
    ls.icone:SetTexture(replie and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
    ls.nom:SetText(s.nom)
    ls.nombre:SetText(#s.quetes)
    ls:Show()
    y = y + HAUT_SECTION
    total = total + #s.quetes
    if not replie then
      for _, q in ipairs(s.quetes) do
        nQ = nQ + 1
        local lq = lignesQuetes[nQ] or creerLigneQuete()
        lignesQuetes[nQ] = lq
        lq:ClearAllPoints()
        lq:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -y)
        y = y + remplirLigneQuete(lq, q, largeur, choisieId) + 2
        lq:Show()
      end
    end
  end
  for i = nS + 1, #lignesSections do lignesSections[i]:Hide() end
  for i = nQ + 1, #lignesQuetes do lignesQuetes[i].numero = nil; lignesQuetes[i]:Hide() end
  contenu:SetHeight(math.max(y, 1))
  titreEntete:SetText("Quêtes (" .. total .. ")")
  -- Hauteur : celle du contenu, plafonnée à 70 % de l'écran ; au-delà, la molette fait défiler.
  local echelle = cadre:GetScale() or 1
  local ecran = ((UIParent:GetHeight() or 768) / (echelle ~= 0 and echelle or 1)) * ECHELLE_MAX
  local voulue = math.min(HAUT_ENTETE + 4 + y + 2, math.max(ecran, 80))
  cadre:SetHeight(voulue)
  local visible = voulue - HAUT_ENTETE - 4
  local maxi = math.max(0, y - visible)
  if (defil:GetVerticalScroll() or 0) > maxi then defil:SetVerticalScroll(maxi) end
  return total
end

-- ----- la position et l'allure du panneau

local function placerPanneau()
  local echelle = (db.taille or 100) / 100
  cadre:SetScale(echelle)
  cadre:ClearAllPoints()
  local p = db.position
  if type(p) == "table" and p[1] and p[2] and p[3] and p[4] then
    local x, y = ns.decalageEchelle(p[3], p[4], p[5], echelle)
    cadre:SetPoint(p[1], UIParent, p[2], x, y)
  else
    cadre:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -240)
  end
end

local function allurePanneau()
  if db.fondSombre then
    ns.habiller(cadre, { fond = { 0.07, 0.06, 0.045, 0.82 } })
    if cadre.fondHabille then cadre.fondHabille:Show() end
  elseif cadre.fondHabille then
    cadre.fondHabille:Hide()
  end
end

entete:SetScript("OnDragStart", function()
  if not db or db.verrouiller then return end
  if enCombat() then
    dire("le panneau ne peut pas être déplacé en combat.")
    return
  end
  cadre:StartMoving()
end)
entete:SetScript("OnDragStop", function()
  cadre:StopMovingOrSizing()
  if not db then return end
  local p, _, rp, x, y = cadre:GetPoint()
  if p then db.position = { p, rp, x, y, cadre:GetScale() } end
  if ns.majObjets then ns.majObjets() end
end)
entete:SetScript("OnClick", function(_, bouton)
  if bouton == "RightButton" and ns.reglages then ns.reglages.montrer() end
end)
entete:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:AddLine("Suivi des quêtes")
  GameTooltip:AddLine("Glisser : déplacer le panneau\nClic droit : les réglages", 1, 1, 1)
  GameTooltip:Show()
end)
entete:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- ---------------------------------------------------------------------------
-- Les boutons d'objet de quête
-- ---------------------------------------------------------------------------
-- Utiliser un objet est protégé : le jeu veut UN clic de toi sur un bouton « sécurisé ». Un cadre
-- auquel un tel bouton est accroché (ou dont il est l'enfant) devient intouchable en combat. Donc
-- les boutons vivent dans un cadre porteur à part, enfant de UIParent, accroché à UIParent par des
-- coordonnées calculées hors combat d'après la place du panneau. Contenu et position ne changent
-- que hors combat (drapeau « à refaire », traité à la fin du combat). Le panneau, lui, se redessine
-- librement en combat.

local MAX_OBJETS = 6
local TAILLE_OBJET = 36

local porteur = CreateFrame("Frame", "SuiviQuetesPorteur", UIParent)
porteur:SetSize(TAILLE_OBJET, TAILLE_OBJET)
porteur:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -340, -264)
local boutonsObjets = {}
local objetsVoulus = {}      -- ce que le panneau demande (rempli à chaque rafraîchissement)
local aRefaireObjets = false -- vrai quand il faudra refaire les boutons à la fin du combat

local function majRecharge(b)
  if not (b and b.recharge and b.indexJournal) then return end
  local f = GetQuestLogSpecialItemCooldown or (C_QuestLog and C_QuestLog.GetQuestLogSpecialItemCooldown)
  local debut, duree = sur(f, b.indexJournal)
  -- En combat, le jeu peut cacher ces valeurs (« secret values ») : les comparer lèverait une erreur.
  if issecretvalue and (issecretvalue(debut) or issecretvalue(duree)) then return end
  if type(debut) == "number" and type(duree) == "number" and duree > 0 and debut > 0 then
    sur(b.recharge.SetCooldown, b.recharge, debut, duree)
  elseif b.recharge.Clear then
    sur(b.recharge.Clear, b.recharge)
  end
end

local function creerBoutonObjet(i)
  local b = CreateFrame("Button", "SuiviQuetesObjet" .. i, porteur, "SecureActionButtonTemplate")
  b:SetSize(TAILLE_OBJET, TAILLE_OBJET)
  b:RegisterForClicks("AnyUp", "AnyDown")
  -- Une macro « /use item:NUMERO » plutôt que le type « item » (même raison que dans Quêtes auto :
  -- sur Forever, le type « item » n'est pas lu).
  b:SetAttribute("type1", "macro")
  b.icone = b:CreateTexture(nil, "ARTWORK")
  b.icone:SetAllPoints()
  local okR, recharge = pcall(CreateFrame, "Cooldown", nil, b, "CooldownFrameTemplate")
  if okR and recharge then
    b.recharge = recharge
    recharge:SetAllPoints()
  end
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    if self.lien then sur(GameTooltip.SetHyperlink, GameTooltip, self.lien) end
    if self.titreQuete then GameTooltip:AddLine("Quête : " .. self.titreQuete, 1, 0.82, 0) end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  boutonsObjets[i] = b
  return b
end

local essaisPlace = 0
local majObjetsSiBesoin

-- Refait les boutons (contenu et place). Rien en combat : c'est repris à la fin du combat.
local function majObjets()
  if enCombat() then aRefaireObjets = true return end
  aRefaireObjets = false
  local voulu = {}
  if db and db.actif and db.boutonsObjets and cadre:IsShown() then
    for _, o in ipairs(objetsVoulus) do
      if #voulu < MAX_OBJETS then voulu[#voulu + 1] = o end
    end
  end
  for i = 1, math.max(#voulu, #boutonsObjets) do
    local o = voulu[i]
    local b = boutonsObjets[i]
    if o and not b then b = creerBoutonObjet(i) end
    if b then
      if o then
        local macro = "/use item:" .. o.numero
        if b.macro ~= macro then
          b:SetAttribute("macrotext1", macro)
          b.macro = macro
        end
        b.lien, b.titreQuete, b.indexJournal = o.lien, o.titreQuete, o.index
        b.icone:SetTexture(o.icone or "Interface\\Icons\\INV_Misc_Note_01")
        b:ClearAllPoints()
        b:SetPoint("TOP", porteur, "TOP", 0, -(i - 1) * (TAILLE_OBJET + 4))
        b:Show()
        majRecharge(b)
      else
        b:Hide()
      end
    end
  end
  if #voulu > 0 then
    porteur:SetHeight(#voulu * (TAILLE_OBJET + 4))
    local gauche, droite, haut = cadre:GetLeft(), cadre:GetRight(), cadre:GetTop()
    if gauche and droite and haut then
      local point, x, y = ns.positionPorteur(gauche, droite, haut, cadre:GetEffectiveScale(),
        UIParent:GetEffectiveScale(), TAILLE_OBJET)
      porteur:ClearAllPoints()
      porteur:SetPoint(point, UIParent, "BOTTOMLEFT", x, y)
      essaisPlace = 0
    elseif essaisPlace < 5 then
      -- Le jeu n'a pas encore calculé la place du panneau : on réessaie dans un instant.
      essaisPlace = essaisPlace + 1
      C_Timer.After(0.2, majObjetsSiBesoin)
    end
    porteur:Show()
  else
    porteur:Hide()
  end
end
ns.majObjets = majObjets
function majObjetsSiBesoin() majObjets() end

-- ---------------------------------------------------------------------------
-- Le suivi des objectifs du jeu
-- ---------------------------------------------------------------------------
-- Jamais de Hide, de Show ni de déplacement en combat (il contient des boutons protégés) : c'est
-- reporté à la fin du combat. On ne touche à aucun champ du cadre de Blizzard (contamination) ; un
-- « hooksecurefunc » sur Show le recache hors combat. Il revient quand l'addon est coupé, quand
-- l'option est décochée et dans une instance (il y porte les objectifs de scénario).

local suiviCachePar = false  -- vrai quand c'est nous qui l'avons caché
local suiviTransparent = false -- vrai quand on l'a seulement rendu transparent (en combat)
local crochetPose = false

local function dansInstance()
  local dedans = sur(IsInInstance)
  return dedans and true or false
end

-- Le mode d'édition de l'interface montre le suivi du jeu pour qu'on puisse le régler : on le laisse.
local function modeEdition()
  local m = _G.EditModeManagerFrame
  if type(m) ~= "table" or not m.IsEditModeActive then return false end
  return sur(m.IsEditModeActive, m) == true
end

local function veutCacherSuivi()
  return (db and db.actif and db.cacherSuiviJeu and not dansInstance() and not modeEdition()) and true or false
end

-- Le rend visible s'il n'était que transparent (SetAlpha n'est pas protégé : permis en combat).
local function rendreOpaque(t)
  if suiviTransparent then
    suiviTransparent = false
    sur(t.SetAlpha, t, 1)
  end
end

local function suiviDuJeu() return _G.ObjectiveTrackerFrame end

local function accrocherSuivi()
  if crochetPose or not hooksecurefunc then return end
  local t = suiviDuJeu()
  if type(t) ~= "table" then return end
  local ok = pcall(hooksecurefunc, t, "Show", function()
    if veutCacherSuivi() then
      if enCombat() then
        -- Pas de Hide en combat : le jeu rappelle Show à chaque mise à jour d'objectif. On le
        -- rend transparent, et il est caché pour de bon à la fin du combat.
        if t.SetAlpha then
          suiviTransparent = true
          sur(t.SetAlpha, t, 0)
        end
      else
        rendreOpaque(t)
        suiviCachePar = true
        sur(t.Hide, t)
      end
    else
      rendreOpaque(t)
    end
  end)
  crochetPose = ok
end

local function appliquerSuiviJeu()
  local t = suiviDuJeu()
  if type(t) ~= "table" then return end
  accrocherSuivi()
  if enCombat() then
    -- Ni Hide ni Show en combat (boutons protégés) ; seule la transparence change, et la suite
    -- vient à la fin du combat (PLAYER_REGEN_ENABLED rappelle cette fonction).
    if veutCacherSuivi() then
      if t.IsShown and t:IsShown() and t.SetAlpha then
        suiviTransparent = true
        sur(t.SetAlpha, t, 0)
      end
    else
      rendreOpaque(t)
    end
    return
  end
  if veutCacherSuivi() then
    rendreOpaque(t)
    if t.IsShown and t:IsShown() then
      suiviCachePar = true
      sur(t.Hide, t)
    end
  else
    rendreOpaque(t)
    if suiviCachePar then
      suiviCachePar = false
      if t.IsShown and not t:IsShown() then sur(t.Show, t) end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Rafraîchissement
-- ---------------------------------------------------------------------------

local function rafraichir()
  if not db or not perso then return end
  -- Dans une instance, le suivi du jeu revient (scénarios) : on s'efface, sauf si on ne l'a pas caché.
  local masque = (not db.actif) or (db.cacherSuiviJeu and dansInstance())
  if masque then
    cadre:Hide()
    sectionsAffichees = {}
    objetsVoulus = {}
    majObjets()
    return
  end
  local quetes = collecter()
  sectionsAffichees = ns.sections(quetes)
  objetsVoulus = {}
  for _, s in ipairs(sectionsAffichees) do
    -- Une section repliée n'a pas de bouton d'objet : le panneau montre ce que le joueur a choisi de voir.
    for _, q in ipairs(perso.replie[s.genre] and {} or s.quetes) do
      if q.objet then
        q.objet.titreQuete = q.titre
        objetsVoulus[#objetsVoulus + 1] = q.objet
      end
    end
  end
  if #sectionsAffichees == 0 then
    cadre:Hide()
  else
    redessiner()
    cadre:Show()
  end
  majObjets()
end

-- Une erreur ne sort jamais : elle est notée (et dite une fois) ; /sq centre ou un nouvel événement réessaie.
local erreurDite = false
local function rafraichirSur()
  local ok, erreur = pcall(rafraichir)
  if not ok then
    ns.derniereErreur = tostring(erreur)
    if not erreurDite then
      erreurDite = true
      dire("une erreur a été retenue (" .. ns.derniereErreur .. "). Le panneau réessaie au prochain changement.")
    end
  end
end
ns.rafraichir = rafraichirSur

local enAttente = false
function demander()
  if enAttente then return end
  enAttente = true
  C_Timer.After(0.1, function()
    enAttente = false
    rafraichirSur()
  end)
end
ns.demander = demander

-- ---------------------------------------------------------------------------
-- Réglages
-- ---------------------------------------------------------------------------

local function remettreEnPlace()
  db.position = nil
  placerPanneau()
  rafraichirSur()
end

ns.reglages = ns.creerReglages({
  titre = "Suivi des quêtes",
  icone = "Interface\\Icons\\INV_Scroll_03",
  nomDB = "SuiviQuetesDB",
  defauts = DEFAUTS,
  options = {
    { titre = "Affichage" },
    { cle = "actif", libelle = "Activer le suivi des quêtes",
      aide = "Le panneau remplace le suivi des objectifs du jeu : tes quêtes suivies, rangées en sections." },
    { cle = "rendreEnHaut", libelle = "Les quêtes à rendre tout en haut",
      aide = "Les quêtes finies vont dans une section « À rendre » placée avant toutes les autres, pour ne pas oublier de les rendre." },
    { cle = "uneLigne", libelle = "Une ligne par quête",
      aide = "Seulement le titre de chaque quête, sans ses objectifs : le panneau prend moins de place." },
    { cle = "distance", libelle = "La distance jusqu'à la quête",
      aide = "À droite du titre (« 140 m », « 2,6 km »), quand le jeu la donne. Le tri en tient compte : les plus proches d'abord." },
    { cle = "cacherAutresZones", libelle = "Cacher les quêtes des autres zones",
      aide = "Ne garde que les quêtes de la zone où tu es. Les quêtes de donjon et celles à rendre restent toujours visibles." },
    { cle = "toutesLesQuetes", libelle = "Toutes les quêtes du journal",
      aide = "Montre toutes les quêtes de ton journal, pas seulement celles que tu suis. Une zone repliée dans le journal n'est pas lue." },
    { cle = "largeur", type = "nombre", libelle = "Largeur du panneau", min = 220, max = 420, pas = 10,
      format = function(v) return v .. " px" end,
      aide = "La largeur du panneau. Les titres trop longs sont coupés." },
    { cle = "taille", type = "nombre", libelle = "Taille du panneau", min = 60, max = 150, pas = 5,
      format = function(v) return v .. " %" end,
      aide = "Agrandit ou réduit tout le panneau (texte compris)." },
    { cle = "fondSombre", libelle = "Fond sombre",
      aide = "Un fond sombre et une bordure dorée derrière le panneau. Décoché : transparent, avec le texte ombré comme dans le jeu." },
    { cle = "verrouiller", libelle = "Verrouiller la position",
      aide = "Empêche de déplacer le panneau en glissant son en-tête. Il ne se déplace de toute façon pas en combat." },
    { titre = "Jeu" },
    { cle = "cacherSuiviJeu", libelle = "Cacher le suivi des objectifs du jeu",
      aide = "Le suivi du jeu est caché quand ce panneau est là. Il revient dans une instance (il y porte les objectifs de scénario) et quand l'addon est coupé. En combat, on n'y touche pas : il est remis à la fin du combat." },
    { cle = "boutonsObjets", libelle = "Les boutons des objets de quête",
      aide = "Les quêtes qui demandent un objet à utiliser ont un bouton dans une colonne à gauche du panneau. C'est toi qui cliques : l'addon ne joue pas à ta place." },
  },
  boutons = {
    { texte = "Remettre à sa place", aide = "Remet le panneau à son emplacement d'origine, sous la minimap.", action = function()
      remettreEnPlace()
    end },
    { texte = "Tout déplier", aide = "Déplie toutes les sections du panneau.", action = function()
      if perso then perso.replie = {} end
      rafraichirSur()
    end },
  },
  astuce = "Clic sur une quête : la choisir (le GPS la suit). Survol : sa description. Maj + clic : ne plus suivre. Clic droit : la ranger ailleurs. /sq genre montre ce que le jeu dit de chaque quête.",
  auChargement = function(d)
    db = d
    db.genres = type(db.genres) == "table" and db.genres or {}
    SuiviQuetesPerso = SuiviQuetesPerso or {}
    perso = SuiviQuetesPerso
    perso.replie = type(perso.replie) == "table" and perso.replie or {}
    placerPanneau()
    allurePanneau()
  end,
  surChangement = function()
    if not db then return end
    placerPanneau()
    allurePanneau()
    appliquerSuiviJeu()
    rafraichirSur()
  end,
})

-- ---------------------------------------------------------------------------
-- Événements
-- ---------------------------------------------------------------------------

local noterGenres -- définie plus bas (commande /sq genre) ; appelée aussi à la déconnexion

local ecouteur = CreateFrame("Frame")
pcall(ecouteur.RegisterEvent, ecouteur, "PLAYER_LOGOUT")
for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "SUPER_TRACKING_CHANGED", "ZONE_CHANGED_NEW_AREA",
                     "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "BAG_UPDATE_COOLDOWN" }) do
  pcall(ecouteur.RegisterEvent, ecouteur, e)
end
if ecouteur.RegisterUnitEvent then pcall(ecouteur.RegisterUnitEvent, ecouteur, "UNIT_QUEST_LOG_CHANGED", "player") end

ecouteur:SetScript("OnEvent", function(_, evenement)
  if not db then return end
  if evenement == "PLAYER_LOGOUT" then
    -- À chaque déconnexion ou /reload, on garde dans la sauvegarde ce que le jeu dit des quêtes :
    -- cela permet de régler le tri sans recopier le chat.
    if noterGenres then pcall(noterGenres, true) end
    return
  end
  if evenement == "BAG_UPDATE_COOLDOWN" then
    for _, b in ipairs(boutonsObjets) do majRecharge(b) end
    return
  end
  if evenement == "PLAYER_REGEN_ENABLED" then
    appliquerSuiviJeu()
    majObjets()
  elseif evenement == "PLAYER_ENTERING_WORLD" or evenement == "ZONE_CHANGED_NEW_AREA" then
    appliquerSuiviJeu()
  end
  demander()
end)

-- Les distances : relues toutes les 2 s, seulement si le panneau est affiché et l'option cochée.
C_Timer.NewTicker(2, function()
  if db and db.actif and db.distance and cadre:IsShown() then rafraichirSur() end
end)

-- ---------------------------------------------------------------------------
-- Commandes
-- ---------------------------------------------------------------------------

-- Pour chaque quête suivie : ce que le jeu en dit et le genre retenu.
-- silencieux = vrai : rien dans le chat, on remplit seulement db.diagnostic (lu hors jeu dans la sauvegarde).
noterGenres = function(silencieux)
  if not db then return end
  local quetes = collecter(true) -- sans les filtres d'affichage : on veut tout voir
  db.diagnostic = { date = date and date("%Y-%m-%d %H:%M") or "", lignes = {} }
  if #quetes == 0 then if not silencieux then dire("aucune quête suivie à examiner.") end return end
  if not silencieux then dire("ce que le jeu dit de tes quêtes suivies (" .. #quetes .. ") :") end
  local function v(x) if x == nil then return "-" end return tostring(x) end
  for _, q in ipairs(quetes) do
    local i = q.infos
    local ligne = (string.format("%s (n° %d) : rubrique=%s, tagID=%s, tagName=%s, classification=%s, campagne=%s, frequence=%s, groupe=%s, fini=%s -> %s%s",
      q.titre, q.numero, v(i.rubrique), v(i.tagID), v(i.tagName), v(i.classification), v(i.campaignID), v(i.frequency),
      v(i.suggestedGroup), i.fini and "oui" or "non", NOMS_GENRES[q.genre] or q.genre, q.manuel and " (choix manuel)" or ""))
    db.diagnostic.lignes[#db.diagnostic.lignes + 1] = ligne
    if not silencieux then dire(ligne) end
  end
end
local function commandeGenre() noterGenres(false) end

local function commande(texte)
  local c = strtrim(texte or ""):lower()
  if c == "" or c == "options" or c == "reglages" then
    ns.reglages.ouvrir()
  elseif c == "genre" or c == "genres" then
    commandeGenre()
  elseif c == "centre" then
    if db then
      if enCombat() then dire("le panneau ne peut pas être déplacé en combat.") return end
      remettreEnPlace()
      dire("panneau remis à sa place.")
    end
  elseif c == "on" or c == "off" then
    if db and (c == "on") ~= (db.actif and true or false) then ns.reglages.basculer() end
  elseif c == "aide" or c == "help" or c == "?" then
    dire("/sq : les réglages     /sq genre : ce que le jeu dit de chaque quête suivie")
    dire("/sq centre : remet le panneau à sa place     /sq on, /sq off : activer ou couper")
  elseif not ns.reglages.basculerOption(c) then
    dire("commande inconnue. /sq aide donne la liste.")
  end
end

SLASH_SUIVIQUETES1 = "/sq"
SLASH_SUIVIQUETES2 = "/suivi"
SlashCmdList.SUIVIQUETES = commande
