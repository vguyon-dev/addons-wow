-- ============================================================================
-- Quêtes disponibles : un « ! » jaune sur la carte du monde à chaque endroit où une
-- quête est À PRENDRE pour ton personnage (pas encore dans ton journal), pour ne plus
-- fouiller chaque zone.
--
-- D'où viennent les quêtes : de notre fichier Donnees.lua, généré à partir de la base
-- libre CMaNGOS classic-db (licence GPL-3.0, voir outils/quetes-dispo). Beaucoup de
-- quêtes de WoW Forever portent les numéros de WoW Classic ; le jeu, lui, ne donne pas la
-- liste des quêtes à prendre sur Forever. Aucun code ni aucune donnée d'un autre addon
-- n'est repris ici : seule l'idée (des « ! » sur la carte, des filtres) est la même.
--
-- Ce que fait l'addon :
--   - un « ! » par endroit (plusieurs quêtes au même endroit : un seul « ! » avec leur nombre) ;
--   - survol : chaque quête « [niveau] Titre », colorée selon la difficulté, avec ses marques
--     (Donjon, Groupe, Raid, JcJ, Répétable, métier requis) ;
--   - clic gauche : une balise (notre GPS, sinon la balise du jeu) ;
--   - clic droit : ne plus montrer ces quêtes (gardé par personnage, réversible dans les réglages).
--
--   - il apprend les quêtes que les PNJ proposent et que la base ne connaît pas (Forever a les siennes),
--     retient où elles se prennent, et les partage avec le groupe (préfixe d'addon « QuetesDispo ») ;
--   - de petits « ! » sur la minimap pour les quêtes à prendre à moins d'une portée de minimap.
--
-- Et pour les quêtes déjà dans ton journal (idées vues dans l'addon Questie, code à nous) :
--   - une petite icône là où se fait chaque objectif pas encore fini (survol : la quête et « 3/8 ... ») ;
--   - un « ? » jaune (carte et minimap) là où rendre une quête finie ; en option, un « ? » gris pour les autres ;
--   - dans la bulle d'un monstre, les quêtes du journal qui en ont besoin, avec la progression.
--
--   /qd : les réglages     /qd etat : ce que l'addon voit sur la carte     /qd aide
--
-- Le fichier a deux parties : la logique pure (testée hors jeu, tests/QuetesDispo_simu.lua),
-- puis tout ce qui parle au jeu. Les épingles sont de simples cadres à nous, posés sur la
-- toile de la carte : on n'écrit rien sur les cadres du jeu (ce qui marquerait la carte et
-- bloquerait des actions en combat).
-- ============================================================================

local NOM_ADDON, ns = ...

local DEFAUTS = {
  actif = true,
  basNiveau = false,     -- montrer aussi les quêtes grises (trop faciles)
  repetables = false,    -- montrer les quêtes répétables
  donjons = true,        -- montrer les quêtes de donjon et de raid
  jcj = false,           -- montrer les quêtes JcJ
  saisonnieres = false,  -- montrer les quêtes saisonnières ou d'événement
  bientot = false,       -- montrer aussi les quêtes bientôt disponibles (jusqu'à 3 niveaux au-dessus)
  metiers = true,        -- cacher les quêtes d'un métier que je n'ai pas
  tropHaut = true,       -- cacher les quêtes d'un niveau trop au-dessus du tien
  ecartHaut = 4,         -- « trop au-dessus » = plus de tant de niveaux d'écart
  suites = true,         -- cacher les quêtes d'une suite pas encore débloquée
  taille = 20,           -- taille des « ! », de 12 à 32
  continent = false,     -- montrer aussi sur la carte d'un continent
  minimap = false,       -- l'icône à part autour de la minimap (réglages communs), PAS les « ! » de la minimap
  surMinimap = true,     -- montrer les « ! » des quêtes proches sur la minimap
  apprendre = true,      -- retenir les quêtes que les PNJ proposent et que la base ne connaît pas
  partager = true,       -- envoyer ces quêtes au groupe et recevoir celles du groupe
  objectifsCarte = true, -- les icônes des objectifs des quêtes du journal sur la carte d'une zone
  rendre = true,         -- le « ? » jaune là où rendre une quête finie (carte et minimap)
  rendreGris = false,    -- un « ? » gris là où rendre une quête pas encore finie
  bulleMonstres = true,  -- les quêtes du journal dans la bulle des monstres
  nomsPnj = {},          -- [numéro du PNJ, ou -numéro d'un objet] = nom en français, appris en lui parlant
  appris = {},           -- [ numéro de quête ] = { titre, niveau, monde = { continent, x, y }, carte, pnj, date, source }
  ignorees = {},         -- [ "Nom-Royaume" ] = { [numéro de quête] = true } : cachées à la main, par personnage
}

-- ---------------------------------------------------------------------------
-- Partie « logique pure » : aucune fonction du jeu, donc testable hors jeu.
-- ---------------------------------------------------------------------------

-- Les champs d'une ligne de ns.QUETES (fichier généré) :
--   { niveau, niveauMin, races, classes, avant, groupeExclusif, drapeaux, metier, niveauMetier, "titre anglais",
--     autresAvant, reputation }
-- Les deux derniers champs sont facultatifs : autresAvant est une liste de numéros signés (les quêtes
-- NextQuestId de la base, qui ouvrent aussi celle-ci) ou 0 ; reputation est le numéro de la faction dont il
-- faut une réputation minimale (0 ou absent : aucune).
local Q_NIVEAU, Q_NIVMIN, Q_RACES, Q_CLASSES, Q_AVANT, Q_GROUPE, Q_DRAPEAUX, Q_METIER, Q_NIVMETIER, Q_TITRE =
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10
local Q_AUTRES, Q_REPUTATION = 11, 12

-- Les drapeaux sont additionnés dans le champ « drapeaux ».
local F_REPETABLE, F_GROUPE, F_DONJON, F_RAID, F_JCJ, F_SAISON = 1, 2, 4, 8, 16, 32

-- Le drapeau « bit » est-il dans la somme « drapeaux » ? (pas de bibliothèque de bits en Lua 5.1)
local function drapeau(drapeaux, bit)
  return math.floor((tonumber(drapeaux) or 0) / bit) % 2 == 1
end

-- Deux masques (races ou classes) ont-ils au moins un bit en commun ? Entiers positifs.
local function partage(a, b)
  a, b = tonumber(a) or 0, tonumber(b) or 0
  while a >= 1 and b >= 1 do
    if a % 2 >= 1 and b % 2 >= 1 then return true end
    a, b = math.floor(a / 2), math.floor(b / 2)
  end
  return false
end

-- Le masque d'une race ou d'une classe : 2 puissance (numéro - 1). Humain 1, Orc 2, Nain 4,
-- Elfe de la nuit 8, Mort-vivant 16, Tauren 32, Gnome 64, Troll 128 ; Guerrier 1, Paladin 2...
local function masqueDe(numero)
  if type(numero) ~= "number" or numero < 1 or numero > 60 or numero % 1 ~= 0 then return 0 end
  return 2 ^ (numero - 1)
end
ns.masqueRace = masqueDe
ns.masqueClasse = masqueDe

-- Les races de WoW Classic (numéros 1 à 8) vont de 1 à 128 en masque.
local function raceDeClassic(masque) return type(masque) == "number" and masque >= 1 and masque <= 128 end
-- Une race nouvelle de Forever est jugée par sa faction : tous les bits de la faction.
local MASQUES_FACTION = { Alliance = 1 + 4 + 8 + 64, Horde = 2 + 16 + 32 + 128 }
ns.MASQUES_FACTION = MASQUES_FACTION

-- Les raisons pour lesquelles une quête n'est pas montrée, en clair (pour /qd etat).
ns.NOMS_RAISONS = {
  ignoree = "cachées à la main", rendue = "déjà rendues", enCours = "déjà dans le journal",
  classe = "d'une autre classe", race = "d'une autre race ou faction", niveau = "niveau trop bas",
tropHaut = "d'un niveau trop au-dessus du tien",
  prerequis = "il faut rendre une autre quête avant", prerequisEnCours = "il faut avoir une autre quête en cours",
  groupe = "groupe exclusif (une autre du groupe est prise)", metier = "métier manquant", grise = "trop faciles (grises)",
  repetable = "répétables", donjon = "donjons et raids", jcj = "JcJ", saison = "saisonnières",
}

-- Les noms (français) des compétences de métier, par numéro de compétence.
ns.NOMS_METIERS = {
  [164] = "Forge", [165] = "Travail du cuir", [171] = "Alchimie", [182] = "Herboristerie", [185] = "Cuisine",
  [186] = "Minage", [197] = "Couture", [202] = "Ingénierie", [333] = "Enchantement", [356] = "Pêche",
  [393] = "Dépeçage", [129] = "Secourisme", [40] = "Poisons", [633] = "Crochetage", [755] = "Joaillerie",
  [773] = "Calligraphie",
}

-- Les marques d'une quête, dans l'ordre : Donjon, Groupe, Raid, JcJ, Répétable, Saisonnière, métier requis,
-- réputation requise (le jeu seul sait où tu en es : on le signale sans cacher la quête).
function ns.marques(drapeaux, metier, reputation)
  local m = {}
  if drapeau(drapeaux, F_DONJON) then m[#m + 1] = "Donjon" end
  if drapeau(drapeaux, F_GROUPE) then m[#m + 1] = "Groupe" end
  if drapeau(drapeaux, F_RAID) then m[#m + 1] = "Raid" end
  if drapeau(drapeaux, F_JCJ) then m[#m + 1] = "JcJ" end
  if drapeau(drapeaux, F_REPETABLE) then m[#m + 1] = "Répétable" end
  if drapeau(drapeaux, F_SAISON) then m[#m + 1] = "Saisonnière" end
  if type(metier) == "number" and metier > 0 then
    m[#m + 1] = "Métier : " .. (ns.NOMS_METIERS[metier] or "requis")
  end
  if type(reputation) == "number" and reputation > 0 then m[#m + 1] = "Réputation requise" end
  return m
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

-- « [18] Titre » (sans le niveau s'il est inconnu).
function ns.titreAffiche(niveau, titre)
  if type(niveau) == "number" and niveau > 0 then return "[" .. niveau .. "] " .. tostring(titre) end
  return tostring(titre)
end

-- Le titre à montrer : celui du jeu s'il le donne (dans la langue du jeu), sinon le titre anglais des données.
function ns.titreQuete(numero, titreJeu, titreDonnees)
  if type(titreJeu) == "string" and titreJeu ~= "" then return titreJeu end
  if type(titreDonnees) == "string" and titreDonnees ~= "" then return titreDonnees end
  return "Quête " .. tostring(numero)
end

-- La ligne de données d'une quête, avec des noms de champs lisibles (gardée en mémoire).
local fiches, fichesSource = {}, nil
function ns.fiche(numero)
  if fichesSource ~= ns.QUETES then fiches, fichesSource = {}, ns.QUETES end
  local f = fiches[numero]
  if f then return f end
  local l = type(ns.QUETES) == "table" and ns.QUETES[numero]
  if type(l) ~= "table" then return nil end
  f = {
    numero = numero, niveau = l[Q_NIVEAU] or 0, niveauMin = l[Q_NIVMIN] or 0, races = l[Q_RACES] or 0,
    classes = l[Q_CLASSES] or 0, avant = l[Q_AVANT] or 0, groupe = l[Q_GROUPE] or 0, drapeaux = l[Q_DRAPEAUX] or 0,
    metier = l[Q_METIER] or 0, niveauMetier = l[Q_NIVMETIER] or 0, titre = l[Q_TITRE],
    autres = type(l[Q_AUTRES]) == "table" and l[Q_AUTRES] or {}, reputation = tonumber(l[Q_REPUTATION]) or 0,
  }
  fiches[numero] = f
  return f
end

-- Les quêtes apprises en jeu (QuetesDispoDB.appris, posé par la partie « jeu » dans ns.apprises).
-- Une fiche apprise n'a que ce que le jeu a donné : titre, niveau parfois. Tout le reste est « inconnu »
-- (race, classe, niveau minimal, prérequis à 0 : aucun jugement), sauf ce que filtrent déjà le journal et les rendues.
ns.apprises = nil
function ns.ficheApprise(numero, a)
  if type(a) ~= "table" then return nil end
  return {
    numero = numero, niveau = tonumber(a.niveau) or 0, niveauMin = 0, races = 0, classes = 0, avant = 0, groupe = 0,
    drapeaux = 0, metier = 0, niveauMetier = 0, titre = type(a.titre) == "string" and a.titre or nil,
    autres = {}, reputation = 0, appris = true, source = a.source,
  }
end

-- La fiche d'une quête : celle de la base d'abord (une fiche apprise ne la remplace jamais), sinon l'apprise.
function ns.ficheDe(numero)
  local f = ns.fiche(numero)
  if f then return f end
  local a = type(ns.apprises) == "table" and ns.apprises[numero]
  if a then return ns.ficheApprise(numero, a) end
  return nil
end

-- L'index des groupes exclusifs : { [groupe] = { numéros des quêtes du groupe } }. Dans un groupe, prendre
-- une quête ferme les autres. Construit une seule fois par table de quêtes.
-- Seuls les groupes positifs comptent. Un groupe négatif (88 quêtes) demande de rendre TOUTES les quêtes
-- du groupe avant la suivante : CMaNGOS ne s'en sert pas pour fermer une quête (SatisfyQuestExclusiveGroup
-- répond « oui » pour un groupe <= 0), donc on les ignore de la même façon.
local exclusifsCache, exclusifsSource = nil, nil
function ns.exclusifs(quetes)
  if exclusifsCache and exclusifsSource == quetes then return exclusifsCache end
  local index = {}
  for numero, l in pairs(type(quetes) == "table" and quetes or {}) do
    local g = type(l) == "table" and l[Q_GROUPE]
    if type(g) == "number" and g > 0 then
      index[g] = index[g] or {}
      index[g][#index[g] + 1] = numero
    end
  end
  for _, liste in pairs(index) do table.sort(liste) end
  exclusifsCache, exclusifsSource = index, quetes
  return index
end

-- La quête est-elle à prendre pour ce joueur ? Rend vrai ou faux, et la raison (un mot de
-- ns.NOMS_RAISONS) quand c'est faux ; vrai avec la raison « bientot » pour une quête qui demande
-- encore jusqu'à trois niveaux (option « bientôt »).
--   quete   : une fiche (ns.fiche) : numero, niveau, niveauMin, races, classes, avant, autres, groupe,
--             drapeaux, metier, niveauMetier
--   joueur  : niveau, masqueRace, faction, masqueClasse, rendues(numero), enCours(numero),
--             metiers ({ [compétence] = niveau } ou nil si inconnu), ignorees ({ [numero] = true }),
--             plageVerte (8 par défaut), groupes (ns.exclusifs ; sinon celui de ns.QUETES)
--   reglages: basNiveau, repetables, donjons, jcj, saisonnieres, bientot, metiers
-- Les règles se suivent dans cet ordre : la première qui exclut gagne.
function ns.disponible(quete, joueur, reglages)
  joueur, reglages = joueur or {}, reglages or {}
  local n = quete.numero
  local function rendue(x) return joueur.rendues and joueur.rendues(x) and true or false end
  local function enCours(x) return joueur.enCours and joueur.enCours(x) and true or false end

  if joueur.ignorees and joueur.ignorees[n] then return false, "ignoree" end
  local repetable = drapeau(quete.drapeaux, F_REPETABLE)
  if rendue(n) and not repetable then return false, "rendue" end
  if enCours(n) then return false, "enCours" end

  -- Classe : un masque non nul qui n'a pas le bit de ta classe.
  local classes = quete.classes or 0
  if classes ~= 0 and (joueur.masqueClasse or 0) ~= 0 and not partage(classes, joueur.masqueClasse) then
    return false, "classe"
  end

  -- Race : une race de Classic est jugée par son bit, une race nouvelle de Forever par sa faction.
  local races = quete.races or 0
  if races ~= 0 and (joueur.masqueRace or 0) ~= 0 then
    if raceDeClassic(joueur.masqueRace) then
      if not partage(races, joueur.masqueRace) then return false, "race" end
    else
      -- Un masque qui nomme ta race passe ; sinon on regarde si un bit de ta faction y est.
      local f = MASQUES_FACTION[joueur.faction]
      if f and not partage(races, joueur.masqueRace) and not partage(races, f) then return false, "race" end
    end
  end

  -- Niveau : trop bas, sauf une quête « bientôt disponible » (jusqu'à 3 niveaux au-dessus).
  local bientot, verrouillee = false, false
  local niveauJoueur = tonumber(joueur.niveau) or 1
  local niveauMin = quete.niveauMin or 0
  if niveauJoueur < niveauMin then
    if reglages.bientot and niveauMin - niveauJoueur <= 3 then bientot = true else return false, "niveau" end
  end
  -- Trop haut niveau (titre rouge) : cachée si l'option est cochée. Une quête sans niveau fixe passe,
  -- et une quête « bientôt disponible » aussi (tu as demandé à la voir).
  if reglages.tropHaut and not bientot and (quete.niveau or 0) > 0
    and quete.niveau - niveauJoueur > (tonumber(reglages.ecartHaut) or 4) then
    return false, "tropHaut"
  end

  -- Les quêtes à rendre avant, comme CMaNGOS (SatisfyQuestPreviousQuest) : une liste (PrevQuestId, puis les
  -- quêtes dont NextQuestId désigne celle-ci), et UNE seule suffit. Numéro > 0 : cette quête doit être
  -- rendue ; numéro < 0 : cette quête doit être EN COURS (« rendue » ne suffit pas).
  local liste = {}
  if (quete.avant or 0) ~= 0 then liste[1] = quete.avant end
  if type(quete.autres) == "table" then
    for _, a in ipairs(quete.autres) do liste[#liste + 1] = a end
  end
  if #liste > 0 then
    local bon, uneRendue = false, false
    for _, a in ipairs(liste) do
      if a > 0 then
        uneRendue = true
        if rendue(a) then bon = true break end
      elseif enCours(-a) then
        bon = true break
      end
    end
    if not bon then
      -- Option « suites » décochée : on la montre quand même, marquée « pas encore débloquée ».
      if reglages.suites == false then verrouillee = true
      else return false, uneRendue and "prerequis" or "prerequisEnCours" end
    end
  end

  -- Groupe exclusif : une autre quête du même groupe déjà prise ou rendue ferme celle-ci.
  local groupe = quete.groupe or 0
  if groupe > 0 then
    local groupes = joueur.groupes or ns.exclusifs(ns.QUETES)
    for _, autre in ipairs(groupes[groupe] or {}) do
      if autre ~= n and (rendue(autre) or enCours(autre)) then return false, "groupe" end
    end
  end

  -- Métier requis : seulement si on connaît les métiers du joueur et que l'option est cochée.
  if reglages.metiers and (quete.metier or 0) ~= 0 and type(joueur.metiers) == "table" then
    local niveauMetier = joueur.metiers[quete.metier]
    if niveauMetier == nil then return false, "metier" end
    if type(niveauMetier) == "number" and niveauMetier > 0 and niveauMetier < (quete.niveauMetier or 0) then
      return false, "metier"
    end
  end

  -- Quête grise (trop facile) : le niveau du joueur dépasse la sienne de plus que la plage verte.
  if not reglages.basNiveau and (quete.niveau or 0) > 0
    and niveauJoueur - quete.niveau > (tonumber(joueur.plageVerte) or 8) then
    return false, "grise"
  end

  -- Les genres de quêtes : chacun a son option.
  if repetable and not reglages.repetables then return false, "repetable" end
  if (drapeau(quete.drapeaux, F_DONJON) or drapeau(quete.drapeaux, F_RAID)) and not reglages.donjons then
    return false, "donjon"
  end
  if drapeau(quete.drapeaux, F_JCJ) and not reglages.jcj then return false, "jcj" end
  if drapeau(quete.drapeaux, F_SAISON) and not reglages.saisonnieres then return false, "saison" end

  return true, (verrouillee and "verrouillee") or (bientot and "bientot") or nil
end

-- Les quêtes d'un « ! » prêtes à être écrites dans la bulle : triées par niveau puis par titre.
-- titreDe(numero) donne le titre à montrer. Chaque ligne : texte, marques, r, v, b, bientot.
function ns.lignesQuetes(numeros, joueur, reglages, titreDe)
  local lignes = {}
  for _, n in ipairs(numeros or {}) do
    local f = ns.ficheDe(n)
    if f then
      local _, raison = ns.disponible(f, joueur, reglages)
      local titre = titreDe and titreDe(n) or ns.titreQuete(n, nil, f.titre)
      local r, g, b
      if raison == "bientot" or raison == "verrouillee" then r, g, b = 0.75, 0.75, 0.75
      else r, g, b = ns.couleurDifficulte(f.niveau, joueur and joueur.niveau, joueur and joueur.plageVerte) end
      local marques = ns.marques(f.drapeaux, f.metier, f.reputation)
      if f.appris then marques[#marques + 1] = f.source == "groupe" and "appris par ton groupe" or "appris en jeu" end
      lignes[#lignes + 1] = {
        numero = n, niveau = f.niveau, titre = titre, texte = ns.titreAffiche(f.niveau, titre),
        marques = table.concat(marques, ", ")
          .. (raison == "verrouillee" and " (pas encore débloquée)" or ""), r = r, v = g, b = b, bientot = raison == "bientot",
      }
    end
  end
  table.sort(lignes, function(a, b)
    if a.niveau ~= b.niveau then return a.niveau < b.niveau end
    local ta, tb = tostring(a.titre):lower(), tostring(b.titre):lower()
    if ta ~= tb then return ta < tb end
    return a.numero < b.numero
  end)
  return lignes
end

-- Regroupe les points au même endroit (à 0,5 % de la carte près) en un seul « ! ».
-- points : { { x = , y = , quetes = { numéros } } } ; rend { { x, y, quetes } } (positions moyennes,
-- numéros sans doublon). tolerance : 0,005 par défaut (une carte de continent en prend plus).
function ns.regrouper(points, tolerance)
  tolerance = tonumber(tolerance) or 0.005
  local cellules, groupes = {}, {}
  for _, p in ipairs(points or {}) do
    local ci, cj = math.floor(p.x / tolerance), math.floor(p.y / tolerance)
    local trouve
    for di = -1, 1 do
      for dj = -1, 1 do
        local liste = not trouve and cellules[(ci + di) .. ":" .. (cj + dj)]
        if liste then
          for _, g in ipairs(liste) do
            if math.abs(g.x - p.x) <= tolerance and math.abs(g.y - p.y) <= tolerance then trouve = g break end
          end
        end
      end
    end
    if not trouve then
      trouve = { x = p.x, y = p.y, nb = 0, quetes = {}, vus = {} }
      groupes[#groupes + 1] = trouve
      local cle = ci .. ":" .. cj
      cellules[cle] = cellules[cle] or {}
      table.insert(cellules[cle], trouve)
    else
      trouve.x = (trouve.x * trouve.nb + p.x) / (trouve.nb + 1)
      trouve.y = (trouve.y * trouve.nb + p.y) / (trouve.nb + 1)
    end
    trouve.nb = trouve.nb + 1
    for _, q in ipairs(p.quetes or {}) do
      if not trouve.vus[q] then
        trouve.vus[q] = true
        trouve.quetes[#trouve.quetes + 1] = q
      end
    end
  end
  local sortie = {}
  for i, g in ipairs(groupes) do sortie[i] = { x = g.x, y = g.y, quetes = g.quetes } end
  return sortie
end

-- Les positions du jeu et celles de la base ne tournent peut-être pas dans le même sens. On essaie les
-- huit façons de poser (x, y) dans le jeu : tel quel, échangés, avec les signes changés. Celle qu'on garde
-- est celle qui range des villes connues (ns.ANCRES) dans leur propre carte.
ns.TRANSFORMATIONS = {
  function(x, y) return x, y end,
  function(x, y) return y, x end,
  function(x, y) return -x, -y end,
  function(x, y) return -y, -x end,
  function(x, y) return x, -y end,
  function(x, y) return -x, y end,
  function(x, y) return y, -x end,
  function(x, y) return -y, x end,
}

-- Des villes, avec les numéros de carte à essayer dans le jeu, leur continent et leur position dans la base
-- (la position où l'on arrive en s'y téléportant : toujours dans la ville).
-- { { cartes à essayer }, continent, x, y } : Hurlevent, Forgefer, Fossoyeuse, Orgrimmar, Pitons-du-Tonnerre,
-- Darnassus. Sur Forever, les cartes de villes portent les numéros de Classic (1453 Hurlevent, 1454 Orgrimmar,
-- 1458 Fossoyeuse, vus dans LivresBiblio ; 1455, 1456 et 1457 sont ceux de Classic Era, à confirmer en jeu) ;
-- sur Retail, ce sont 84, 85, 87, 88, 89 et 90. On essaie les deux : la ville compte pour reconnue si l'un des
-- numéros place la position dans la carte.
ns.ANCRES = {
  { { 1453, 84 }, 0, -8833.38, 628.63 }, { { 1455, 87 }, 0, -4981.25, -881.54 }, { { 1458, 90 }, 0, 1584.07, 241.99 },
  { { 1454, 85 }, 1, 1629.36, -4373.39 }, { { 1456, 88 }, 1, -1277.37, 124.80 }, { { 1457, 89 }, 1, 9947.52, 2482.73 },
}

-- Choisit la transformation : convertir(continent, a, b, carte) rend la position (x, y) sur la carte, ou rien.
-- Rend le numéro de la transformation et son score (nombre de villes bien rangées sur 6). Égalité : la première.
-- Pour chaque ville, les numéros de carte sont essayés l'un après l'autre : le premier qui convient suffit.
function ns.choisirOrientation(convertir)
  local meilleur, scoreMeilleur = 1, 0
  for i, t in ipairs(ns.TRANSFORMATIONS) do
    local score = 0
    for _, a in ipairs(ns.ANCRES) do
      local ta, tb = t(a[3], a[4])
      for _, carte in ipairs(a[1]) do
        local x, y = convertir(a[2], ta, tb, carte)
        if type(x) == "number" and type(y) == "number" and x > 0 and x < 1 and y > 0 and y < 1 then
          score = score + 1
          break
        end
      end
    end
    if score > scoreMeilleur then meilleur, scoreMeilleur = i, score end
  end
  return meilleur, scoreMeilleur
end

-- L'inverse de chaque transformation : du jeu vers les axes de la base. Les six premières se défont elles-mêmes ;
-- la septième (y, -x) et la huitième (-y, x) sont l'inverse l'une de l'autre.
ns.INVERSES = {}
for i = 1, 6 do ns.INVERSES[i] = ns.TRANSFORMATIONS[i] end
ns.INVERSES[7], ns.INVERSES[8] = ns.TRANSFORMATIONS[8], ns.TRANSFORMATIONS[7]

-- ---------------------------------------------------------------------------
-- Le partage des quêtes apprises : un message compact « A~numéro~niveau~continent~x~y~titre ».
-- Le « ~ » sépare les champs, donc il est retiré du titre ; la barre « | » aussi (un message reçu ne doit pas
-- pouvoir glisser un lien ou une couleur dans une bulle).
-- ---------------------------------------------------------------------------
ns.PREFIXE = "QuetesDispo"
local TITRE_MAX, TITRE_OCTETS = 80, 200

-- Le titre sans caractère de contrôle, « ~ » ni « | », coupé à 80 caractères (et 200 octets) sans casser une lettre accentuée.
local function titreNet(t)
  t = tostring(t == nil and "" or t)
  t = t:gsub("[%c~|]", "")
  t = t:gsub("^%s+", ""):gsub("%s+$", "")
  local sortie, n, octets = {}, 0, 0
  for c in t:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    if n >= TITRE_MAX or octets + #c > TITRE_OCTETS then break end
    n, octets = n + 1, octets + #c
    sortie[n] = c
  end
  return table.concat(sortie)
end

-- Le texte à envoyer pour une quête apprise : fiche = { numero, titre, niveau, monde = { continent, x, y } }.
-- nil si la fiche est incomplète. Niveau inconnu : 0.
function ns.codeAppris(fiche)
  if type(fiche) ~= "table" or type(fiche.monde) ~= "table" then return nil end
  local numero, continent = tonumber(fiche.numero), tonumber(fiche.monde[1])
  local x, y = tonumber(fiche.monde[2]), tonumber(fiche.monde[3])
  if not (numero and continent and x and y) then return nil end
  if x ~= x or y ~= y or math.abs(x) > 100000 or math.abs(y) > 100000 then return nil end
  local niveau = tonumber(fiche.niveau)
  if not niveau or niveau ~= niveau or niveau < 0 or niveau > 100 then niveau = 0 end
  local titre = titreNet(fiche.titre)
  if titre == "" then return nil end
  return string.format("A~%d~%d~%d~%.1f~%.1f~%s", math.floor(numero), math.floor(niveau), math.floor(continent), x, y, titre)
end

-- Le contraire : la fiche { numero, niveau (nil si inconnu), titre, monde = { continent, x, y } }, ou nil si le texte
-- est abîmé, trop long, ou dit des choses impossibles.
function ns.decodeAppris(texte)
  if type(texte) ~= "string" or #texte > 255 then return nil end
  local n, niv, cont, x, y, titre = texte:match("^A~(%d+)~(%-?%d+)~(%d+)~(%-?%d+%.?%d*)~(%-?%d+%.?%d*)~([^~]*)$")
  if not n then return nil end
  n, niv, cont, x, y = tonumber(n), tonumber(niv), tonumber(cont), tonumber(x), tonumber(y)
  if not (n and niv and cont and x and y) then return nil end
  if n < 1 or n > 9999999 or cont > 9999 or niv > 100 then return nil end
  if math.abs(x) > 100000 or math.abs(y) > 100000 then return nil end
  titre = titreNet(titre)
  if titre == "" then return nil end
  return { numero = n, niveau = niv > 0 and niv or nil, titre = titre, monde = { cont, x, y } }
end

-- ---------------------------------------------------------------------------
-- La minimap : où poser l'icône d'une quête.
-- Les axes du monde sont ceux de la base (CMaNGOS) : x vers le NORD, y vers l'OUEST. Preuve par les villes de
-- ns.ANCRES : Darnassus (9947, 2483) est au nord-ouest de Pitons-du-Tonnerre (-1277, 125), et Hurlevent (-8833, 629)
-- est bien au sud de Fossoyeuse (1584, 242) : le nord, c'est x qui monte ; l'ouest, c'est y qui monte.
-- (À vérifier en jeu : si les icônes sont en miroir est-ouest ou nord-sud, c'est ce passage qu'il faut corriger.)
-- dxMonde, dyMonde : position de la quête moins position du joueur, dans ces axes, en mètres.
-- rayon : mètres vus par la minimap (centre au bord). demiLargeur : demi-largeur de la minimap en pixels.
-- rotation : angle en radians dont on tourne l'image, dans le sens inverse des aiguilles d'une montre. 0 quand le
-- nord est en haut ; -GetPlayerFacing() quand la minimap tourne (le regard du joueur va en haut).
-- marge (facultative) : pixels gardés libres au bord, pour que l'icône ne déborde pas du cercle.
-- Rend px (vers la droite) et py (vers le haut), en pixels depuis le centre, ou nil si c'est hors du cercle.
-- ---------------------------------------------------------------------------
function ns.placementMinimap(dxMonde, dyMonde, rayon, demiLargeur, rotation, marge)
  if type(dxMonde) ~= "number" or type(dyMonde) ~= "number" or type(rayon) ~= "number" or type(demiLargeur) ~= "number" then
    return nil
  end
  if dxMonde ~= dxMonde or dyMonde ~= dyMonde or rayon <= 0 or demiLargeur <= 0 then return nil end
  if dxMonde * dxMonde + dyMonde * dyMonde >= rayon * rayon then return nil end -- au bord ou au-delà : pas montré
  local est, nord = -dyMonde, dxMonde
  local t = tonumber(rotation) or 0
  local c, s = math.cos(t), math.sin(t)
  local px, py = (est * c - nord * s) * demiLargeur / rayon, (est * s + nord * c) * demiLargeur / rayon
  local m = tonumber(marge) or 0
  if px * px + py * py > (demiLargeur - m) * (demiLargeur - m) then return nil end
  return px, py
end

-- ---------------------------------------------------------------------------
-- Les quêtes du journal : objectifs sur la carte, « ? » où rendre, lignes dans la bulle des monstres.
-- L'idée vient de l'addon Questie (GPL-3.0, voir LICENCE.md) ; le code ci-dessous est le nôtre.
-- Les données (ns.OBJECTIFS, ns.FINS, ns.NOMS_FINS) sont dans Donnees.lua. Le titre et le texte des
-- objectifs viennent du journal du jeu (en français) ; la base, en anglais, ne donne que les positions.
-- ---------------------------------------------------------------------------

-- Genres d'objectif dans ns.OBJECTIFS : 1 monstre à tuer, 2 objet à ramasser, 3 objet du décor à utiliser.
ns.OBJ_TUER, ns.OBJ_OBJET, ns.OBJ_DECOR = 1, 2, 3

-- Les types d'objectif du journal (champ « type » de C_QuestLog.GetQuestObjectives) qui vont avec chaque genre.
local TYPES_JOURNAL = {
  [1] = { monster = true },
  [2] = { item = true },
  [3] = { object = true },
}

-- Le nom d'un objectif, sans son compte : « Foie de Goretusk : 3/8 » ou « 3/8 Foie de Goretusk » -> « Foie de Goretusk ».
function ns.nomObjectif(texte)
  if type(texte) ~= "string" then return "" end
  local nom = texte:gsub("%d+%s*/%s*%d+", "", 1)
  nom = nom:gsub("^[%s%-:]+", ""):gsub("[%s:]+$", "")
  return nom
end

-- La clé d'un objet (nom en minuscules, sans compte) : la même que celle des butins appris par BarresDeVie.
function ns.cleObjet(texte)
  local nom = ns.nomObjectif(texte)
  if nom == "" then return nil end
  return nom:lower()
end

-- Le texte d'un objectif avec sa progression devant : « 3/8 Foie de Goretusk ».
-- fait et total viennent du jeu ; à défaut, du texte lui-même.
function ns.texteObjectif(texte, fait, total)
  local t = type(texte) == "string" and texte or ""
  local a, b = t:match("(%d+)%s*/%s*(%d+)")
  fait, total = tonumber(fait) or tonumber(a), tonumber(total) or tonumber(b)
  local nom = ns.nomObjectif(t)
  if fait and total and total > 0 then
    if nom == "" then return fait .. "/" .. total end
    return fait .. "/" .. total .. " " .. nom
  end
  if nom ~= "" then return nom end
  return nil
end

-- Associe les objectifs de la base à ceux du journal. base : { { genre, besoin, ... } } ; journal :
-- { { type, total, ... } }. Rend { [index dans la base] = index dans le journal }. On ne se fie pas à la
-- position seule (le jeu ne range pas forcément les objectifs comme la base) : d'abord même genre et même
-- nombre demandé, dans l'ordre ; puis le premier libre du même genre.
function ns.associerObjectifs(base, journal)
  local resultat, pris = {}, {}
  for passe = 1, 2 do
    for i, o in ipairs(type(base) == "table" and base or {}) do
      if not resultat[i] then
        local types = TYPES_JOURNAL[o[1]] or {}
        for j, jo in ipairs(type(journal) == "table" and journal or {}) do
          if not pris[j] and types[jo.type] and (passe == 2 or tonumber(jo.total) == o[2]) then
            resultat[i], pris[j] = j, true
            break
          end
        end
      end
    end
  end
  return resultat
end

-- Une quête du journal est-elle finie (prête à rendre) ?
--   etatJeu : ce que dit le jeu (C_QuestLog.IsComplete, celui que suit le journal du jeu) : vrai ou 1, faux ou 0,
--             -1 (échouée), ou nil quand le jeu ne le dit pas ;
--   objectifs : { { fini } } ; lus : vrai si le jeu a bien donné la liste des objectifs.
-- Le jeu décide quand il répond. Sinon : tous les objectifs faits, et une quête sans aucun objectif (porter une
-- lettre, parler à quelqu'un) est à rendre tout de suite.
function ns.queteFinie(etatJeu, objectifs, lus)
  if etatJeu == true or etatJeu == 1 then return true end
  if etatJeu == false or etatJeu == 0 or etatJeu == -1 then return false end
  if not lus or type(objectifs) ~= "table" then return false end
  -- Liste vide : une quête sans objectif (lettre à porter) est à rendre. Ce repli ne sert que si le jeu ne dit rien.
  for _, o in ipairs(objectifs) do
    if not o.fini then return false end
  end
  return true
end

-- Les objectifs d'une quête du journal qu'il reste à faire, avec ce que la base en sait :
-- { { i, genre, texte, positions, monstres } }. q : { complete, objectifs, lus } ; base : ns.OBJECTIFS[numéro].
-- Un objectif fini n'y est pas. Un objectif que le journal ne nomme pas n'y est que si le jeu n'a rien dit
-- des objectifs (on ne montre pas un objectif dont on ne sait pas s'il est fait).
function ns.objectifsAFaire(q, base)
  local sortie = {}
  if type(q) ~= "table" or type(base) ~= "table" or q.complete then return sortie end
  local journal = type(q.objectifs) == "table" and q.objectifs or {}
  local assoc = ns.associerObjectifs(base, journal)
  for i, o in ipairs(base) do
    local jo = assoc[i] and journal[assoc[i]]
    local montrer, texte, brut = false, nil, nil
    if jo then
      montrer, texte, brut = not jo.fini, ns.texteObjectif(jo.texte, jo.fait, jo.total), jo.texte
    elseif #journal == 0 and not q.lus then
      montrer = true
    end
    if montrer then
      sortie[#sortie + 1] = {
        i = i, genre = o[1], texte = texte, brut = brut,
        positions = type(o[3]) == "table" and o[3] or {}, monstres = type(o[4]) == "table" and o[4] or {},
      }
    end
  end
  return sortie
end

-- Les monstres utiles aux quêtes du journal : { [numéro de créature] = { { q, i } } }, dans l'ordre du journal.
function ns.indexMonstres(liste, objectifs)
  local index = {}
  for _, q in ipairs(type(liste) == "table" and liste or {}) do
    local base = type(objectifs) == "table" and objectifs[q.id]
    for i, o in ipairs(type(base) == "table" and base or {}) do
      for _, m in ipairs(type(o[4]) == "table" and o[4] or {}) do
        index[m] = index[m] or {}
        index[m][#index[m] + 1] = { q = q, i = i }
      end
    end
  end
  return index
end

-- Le numéro de créature d'un identifiant du jeu (« Creature-0-1-2-3-157-0000ABCD » -> 157). nil pour un joueur.
function ns.creatureDuGuid(guid)
  if type(guid) ~= "string" then return nil end
  local genre, id = guid:match("^(%a+)%-[^%-]*%-[^%-]*%-[^%-]*%-[^%-]*%-(%d+)")
  if genre ~= "Creature" and genre ~= "Vehicle" then return nil end
  return tonumber(id)
end

-- Les lignes à ajouter dans la bulle d'un monstre : { { titre, r, v, b, lignes = { « 3/8 Foie de Goretusk » } } }.
--   creature : son numéro ; liste : les quêtes du journal ; objectifs : ns.OBJECTIFS ; index : ns.indexMonstres ;
--   butins : { [clé d'objet] = true } que ce genre de monstre a déjà donnés (appris par BarresDeVie), ou nil ;
--   deja : ce que la bulle montre déjà, { ids = { [quête] = true }, textes = { [texte en minuscules] = true } } :
--          une quête dont le jeu écrit déjà le titre n'est pas répétée, ni un objectif déjà écrit ;
--   niveauJoueur, plageVerte : pour la couleur du titre.
function ns.lignesBulleMonstre(creature, liste, objectifs, index, butins, deja, niveauJoueur, plageVerte)
  deja = type(deja) == "table" and deja or {}
  local ids, textes = deja.ids or {}, deja.textes or {}
  local blocs, parQuete = {}, {}
  local function connu(t) return type(t) == "string" and textes[t:lower()] end
  local function ajouter(q, texte, brut)
    if ids[q.id] or connu(q.titre) or connu(texte) or connu(brut) then return end
    local b = parQuete[q.id]
    if not b then
      local r, v, bl = ns.couleurDifficulte(q.niveau, niveauJoueur, plageVerte)
      b = { id = q.id, titre = ns.titreAffiche(q.niveau, q.titre or ("Quête " .. tostring(q.id))), r = r, v = v, b = bl,
        lignes = {}, vues = {} }
      parQuete[q.id] = b
      blocs[#blocs + 1] = b
    end
    if texte and not b.vues[texte] then
      b.vues[texte] = true
      b.lignes[#b.lignes + 1] = texte
    end
  end
  for _, e in ipairs(type(index) == "table" and index[creature] or {}) do
    for _, o in ipairs(ns.objectifsAFaire(e.q, type(objectifs) == "table" and objectifs[e.q.id])) do
      if o.i == e.i then ajouter(e.q, o.texte, o.brut) end
    end
  end
  -- Les objets que ce genre de monstre a déjà donnés en jeu (même quand la base ne le sait pas).
  if type(butins) == "table" then
    for _, q in ipairs(type(liste) == "table" and liste or {}) do
      if not q.complete then
        for _, jo in ipairs(type(q.objectifs) == "table" and q.objectifs or {}) do
          local cle = jo.type == "item" and not jo.fini and ns.cleObjet(jo.texte)
          if cle and butins[cle] then ajouter(q, ns.texteObjectif(jo.texte, jo.fait, jo.total), jo.texte) end
        end
      end
    end
  end
  for _, b in ipairs(blocs) do b.vues = nil end
  return blocs
end

-- Les quêtes du journal qui ont un « ? » : finies (jaune), et pas finies si l'option « gris » est cochée.
-- Rend { { q, gris } } dans l'ordre du journal.
function ns.quetesARendre(liste, jaune, gris)
  local sortie = {}
  for _, q in ipairs(type(liste) == "table" and liste or {}) do
    if q.complete then
      if jaune then sortie[#sortie + 1] = { q = q, gris = false } end
    elseif gris and not q.echouee then
      sortie[#sortie + 1] = { q = q, gris = true }
    end
  end
  return sortie
end

-- L'index des endroits où rendre : { [numéro de quête] = { indices dans fins } }, construit une fois par table.
local indexFinsCache, indexFinsSource
function ns.indexFins(fins)
  if indexFinsCache and indexFinsSource == fins then return indexFinsCache end
  local index = {}
  for k, f in ipairs(type(fins) == "table" and fins or {}) do
    for _, n in ipairs(type(f) == "table" and type(f[6]) == "table" and f[6] or {}) do
      index[n] = index[n] or {}
      index[n][#index[n] + 1] = k
    end
  end
  indexFinsCache, indexFinsSource = index, fins
  return index
end

-- La clé du nom de celui qui reprend une quête : le numéro du PNJ, ou moins le numéro d'un objet du décor.
function ns.cleFin(genre, id)
  if type(id) ~= "number" then return nil end
  return genre == 2 and -id or id
end

-- Le nom à montrer : celui appris en jeu (français) d'abord, sinon l'anglais des données, sinon rien.
function ns.nomFin(genre, id, appris, noms)
  local cle = ns.cleFin(genre, id)
  if not cle then return nil end
  local n = type(appris) == "table" and appris[cle]
  if type(n) == "string" and n ~= "" then return n end
  n = type(noms) == "table" and noms[cle]
  if type(n) == "string" and n ~= "" then return n end
  return nil
end

-- Pourquoi aucune icône d'objectif sur la carte (pour /qd etat). nil s'il y en a.
-- c : option, carteZone, journalLu, nbJournal, nbDansBase, nbAFaire, nbAvecPositions, surCarte.
function ns.raisonObjectifs(c)
  if not c.option then return "option coupée" end
  if not c.carteZone then return "seulement sur la carte d'une zone" end
  if not c.journalLu then return "le jeu ne donne pas le journal de quêtes" end
  if (c.nbJournal or 0) == 0 then return "journal vide" end
  if (c.nbDansBase or 0) == 0 then return "aucune quête du journal n'est dans la base" end
  if (c.nbAFaire or 0) == 0 then return "objectifs déjà faits" end
  if (c.nbAvecPositions or 0) == 0 then return "la base ne dit pas où se font ces objectifs" end
  if (c.surCarte or 0) == 0 then return "rien sur cette carte" end
  return nil
end

-- Pourquoi aucun « ? » sur la carte. c : option, gris, journalLu, nbJournal, nbAMontrer, nbAvecFin, surCarte.
function ns.raisonRendre(c)
  if not c.option then return "option coupée" end
  if not c.journalLu then return "le jeu ne donne pas le journal de quêtes" end
  if (c.nbJournal or 0) == 0 then return "journal vide" end
  if (c.nbAMontrer or 0) == 0 then return c.gris and "aucune quête dans le journal à montrer" or "aucune quête finie dans le journal" end
  if (c.nbAvecFin or 0) == 0 then return "la base ne dit pas où rendre ces quêtes" end
  if (c.surCarte or 0) == 0 then return "rien sur cette carte" end
  return nil
end

if not CreateFrame then return end -- hors jeu : la suite ne sert qu'en jeu

-- ---------------------------------------------------------------------------
-- Ce qui parle au jeu
-- ---------------------------------------------------------------------------

local db

-- Appelle f sous pcall ; rend ses résultats, ou rien si elle manque ou plante.
local function sur(f, ...)
  if type(f) ~= "function" then return end
  local ok, a, b, c, d = pcall(f, ...)
  if ok then return a, b, c, d end
end

-- Une valeur « secrète » (Midnight) ne se lit pas : on la traite comme absente.
local function lisible(v)
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end

local function dire(texte)
  if ns.reglages then ns.reglages.dire(texte) else print("|cffffd200Quêtes disponibles|r : " .. texte) end
end

-- Une action après un délai ; sans C_Timer, tout de suite.
local function apres(delai, f)
  if C_Timer and C_Timer.After then C_Timer.After(delai, f) else f() end
end

-- L'heure en secondes (GetTime ; sans lui, l'heure du système, au pire 0).
local function maintenant()
  if type(GetTime) == "function" then
    local t = sur(GetTime)
    if type(t) == "number" then return t end
  end
  return type(time) == "function" and time() or 0
end

-- Une position donnée par le jeu : un objet qui a GetXY, ou une simple table { x, y } (vu sur Forever).
local function xyDe(pos)
  if type(pos) ~= "table" then return nil end
  if type(pos.GetXY) == "function" then return pos:GetXY() end
  return pos.x, pos.y
end

local function donneesPresentes()
  return type(ns.QUETES) == "table" and next(ns.QUETES) ~= nil and type(ns.DEPARTS) == "table" and #ns.DEPARTS > 0
end

local function nbConnues()
  local n = 0
  for _ in pairs(type(ns.QUETES) == "table" and ns.QUETES or {}) do n = n + 1 end
  return n
end

-- Le personnage : « Nom-Royaume », pour garder ses quêtes cachées à lui.
local function nomPerso()
  local nom = sur(UnitName, "player")
  if type(nom) ~= "string" or nom == UNKNOWNOBJECT then nom = "?" end
  local royaume = sur(GetRealmName)
  return nom .. "-" .. (type(royaume) == "string" and royaume or "?")
end

local function ignoreesDe()
  if type(db.ignorees) ~= "table" then db.ignorees = {} end
  local cle = nomPerso()
  if type(db.ignorees[cle]) ~= "table" then db.ignorees[cle] = {} end
  return db.ignorees[cle]
end

-- ---------------------------------------------------------------------------
-- Le joueur
-- ---------------------------------------------------------------------------

-- Ses métiers : { [numéro de compétence] = niveau }. nil si le jeu ne les donne pas.
local function mesMetiers()
  if not (GetProfessions and GetProfessionInfo) then return nil end
  local liste = { pcall(GetProfessions) } -- six numéros au plus, avec des trous
  if not liste[1] then return nil end
  local t = {}
  for i = 2, 7 do
    local index = liste[i]
    if type(index) == "number" then
      local infos = { pcall(GetProfessionInfo, index) }
      local niveau, ligne = infos[4], infos[8] -- (le premier est « ok ») niveau de compétence, ligne de compétence
      if type(ligne) == "number" then t[ligne] = type(niveau) == "number" and niveau or 0 end
    end
  end
  return t
end

local function plageVerte()
  local v = sur(GetQuestGreenRange)
  if type(v) ~= "number" and C_QuestLog and C_QuestLog.GetTrivialRange then v = sur(C_QuestLog.GetTrivialRange) end
  return type(v) == "number" and v or 8
end

-- Ce que le jeu dit de ton personnage et de tes quêtes, prêt pour ns.disponible. Les réponses du
-- jeu sont gardées pour la durée d'une passe (la même quête revient à plusieurs endroits).
local function construireJoueur()
  local j = {}
  j.niveau = tonumber((sur(UnitLevel, "player"))) or 1
  local _, _, race = sur(UnitRace, "player")
  j.masqueRace = ns.masqueRace(race)
  j.faction = sur(UnitFactionGroup, "player")
  local _, _, classe = sur(UnitClass, "player")
  j.masqueClasse = ns.masqueClasse(classe)
  j.metiers = mesMetiers()
  j.plageVerte = plageVerte()
  j.ignorees = ignoreesDe()
  j.groupes = ns.exclusifs(ns.QUETES)

  local memoRendue, memoCours = {}, {}
  local fRendue = (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) or IsQuestFlaggedCompleted
  local fCours = C_QuestLog and C_QuestLog.IsOnQuest
  j.etatConnu = type(fRendue) == "function"
  j.rendues = function(n)
    local v = memoRendue[n]
    if v == nil then v = sur(fRendue, n) == true; memoRendue[n] = v end
    return v
  end
  j.enCours = function(n)
    local v = memoCours[n]
    if v == nil then v = sur(fCours, n) == true; memoCours[n] = v end
    return v
  end
  return j
end

-- ---------------------------------------------------------------------------
-- Positions : du monde de la base vers la carte affichée
-- ---------------------------------------------------------------------------

local orientation, orientationScore -- la transformation choisie (ns.TRANSFORMATIONS) et son score sur 6
local cachePositions = {}           -- [carte] = { fini, points, ... } : les points de la carte, calculés une fois
local PAQUET = 300                  -- points convertis par image : le jeu ne se fige pas
local apiMessageDit = false

-- Convertit une position du monde en position sur la carte « carte ». nil si le jeu ne sait pas.
local function convertirBrut(continent, a, b, carte)
  if not (C_Map and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return nil end
  local ok, id, pos = pcall(C_Map.GetMapPosFromWorldPos, continent, CreateVector2D(a, b), carte)
  if not ok or not id then return nil end
  local x, y = xyDe(pos)
  if type(x) ~= "number" or type(y) ~= "number" then return nil end
  return x, y
end

-- La transformation à appliquer aux positions de la base. Choisie une fois (si au moins une ville est
-- reconnue), sinon on garde la première sans la mémoriser.
local function laOrientation()
  if orientation then return orientation end
  local i, score = ns.choisirOrientation(convertirBrut)
  orientationScore = score
  if score > 0 then orientation = i end
  return i
end

-- Genre d'une carte : « zone » (on montre les « ! »), « continent » (selon l'option), « rien »
-- (monde, cosmos : trop vaste).
local function genreCarte(carte)
  local info = C_Map and C_Map.GetMapInfo and sur(C_Map.GetMapInfo, carte)
  local t = type(info) == "table" and info.mapType
  if type(t) ~= "number" then return "zone" end
  if t <= 1 then return "rien" end
  if t == 2 then return "continent" end
  return "zone"
end

-- Le continent d'une carte (0 Royaumes de l'Est, 1 Kalimdor dans la base). Si le jeu ne le dit pas, les deux.
local function continentsDe(carte)
  if C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D then
    local ok, continent = pcall(C_Map.GetWorldPosFromMapPos, carte, CreateVector2D(0.5, 0.5))
    if ok and type(continent) == "number" then return { [continent] = true } end
  end
  return { [0] = true, [1] = true }
end

local demander -- défini plus bas

-- Une étape du calcul : un paquet de points est converti. Quand tout est fait, on prévient ceux qui attendent.
local function etape(c)
  if c.abandonne then return end -- remplacé par un calcul plus juste : on s'arrête là
  local ok, erreur = pcall(function()
    local departs = ns.DEPARTS
    local fin = math.min(c.i + PAQUET - 1, #departs)
    local transformer = ns.TRANSFORMATIONS[c.ori]
    for i = c.i, fin do
      local d = departs[i]
      if type(d) == "table" and c.continents[d[1]] then
        local a, b = transformer(d[2], d[3])
        local x, y = convertirBrut(d[1], a, b, c.carte)
        if x and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
          c.points[#c.points + 1] = { x = x, y = y, quetes = d[5] or {} }
        end
      end
    end
    c.i = fin + 1
  end)
  if not ok then
    ns.derniereErreur = tostring(erreur)
    c.fini = true
  elseif c.i > #ns.DEPARTS then
    c.fini = true
  end
  if c.fini then
    local rappels = c.rappels
    c.rappels = {}
    for _, f in ipairs(rappels) do pcall(f) end
  else
    apres(0, function() etape(c) end)
  end
end

-- Les points de la carte (ceux de la base qui tombent dessus). nil tant que le calcul n'est pas fini ;
-- « rappel » est alors appelé à la fin.
local function positionsDeCarte(carte, rappel)
  local c = cachePositions[carte]
  -- Un calcul fait sans orientation reconnue était provisoire : si le jeu en reconnaît une depuis, on le refait.
  if c and c.provisoire and not orientation then laOrientation() end -- on retente la calibration
  if c and c.provisoire and orientation and c.ori ~= orientation then
    c.abandonne = true
    cachePositions[carte], c = nil, nil
  end
  if not c then
    if not (C_Map and C_Map.GetMapPosFromWorldPos and CreateVector2D) and not apiMessageDit then
      apiMessageDit = true
      dire("le jeu ne sait pas convertir les positions sur la carte : aucun « ! » ne peut être posé.")
    end
    c = { carte = carte, i = 1, points = {}, fini = false, rappels = {}, ori = laOrientation(),
          continents = continentsDe(carte) }
    c.provisoire = orientation == nil
    cachePositions[carte] = c
    apres(0, function() etape(c) end)
    -- Sans minuteur (apres rappelle tout de suite), le calcul est peut-être déjà fini.
  end
  if c.fini then return c.points end
  if rappel then c.rappels[#c.rappels + 1] = rappel end
  return nil
end

-- ---------------------------------------------------------------------------
-- Le joueur dans le monde, et les quêtes apprises
-- ---------------------------------------------------------------------------

local apprisVersion = 0  -- monte à chaque changement des quêtes apprises : les calculs qui en dépendent se refont
local cacheAppris = {}   -- [carte] = { version, ori, points } : les quêtes apprises posées sur chaque carte
local miniSale = true    -- vrai : la liste des quêtes proches de la minimap est à refaire
local dernierEssaiOri = -1000

local function majApprises()
  apprisVersion = apprisVersion + 1
  cacheAppris = {}
  miniSale = true
end

-- Où est le joueur : { carte, continent, a, b (vecteur du jeu), x, y (axes de la base : x nord, y ouest) }.
-- nil si le jeu ne le dit pas (instance, valeur secrète, API absente) ou si l'orientation n'est pas reconnue
-- (sans elle, passer du jeu à la base donnerait des positions fausses).
local function positionJoueur()
  if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition and C_Map.GetWorldPosFromMapPos) then return nil end
  local carte = lisible(sur(C_Map.GetBestMapForUnit, "player"))
  if type(carte) ~= "number" then return nil end
  local pos = lisible(sur(C_Map.GetPlayerMapPosition, carte, "player"))
  if type(pos) ~= "table" then return nil end
  local continent, monde = sur(C_Map.GetWorldPosFromMapPos, carte, pos)
  continent = lisible(continent)
  monde = lisible(monde)
  if type(continent) ~= "number" then return nil end
  local a, b = xyDe(monde)
  a, b = lisible(a), lisible(b)
  if type(a) ~= "number" or type(b) ~= "number" then return nil end
  if not orientation then
    local t = maintenant()
    if t - dernierEssaiOri >= 5 then dernierEssaiOri = t; laOrientation() end -- pas plus d'un essai toutes les 5 s
    if not orientation then return nil end
  end
  local x, y = ns.INVERSES[orientation](a, b)
  return { carte = carte, continent = continent, a = a, b = b, x = x, y = y }
end

-- Une quête apprise est-elle valable ? (la sauvegarde peut avoir été abîmée à la main)
local function apprisePosee(numero, a)
  return type(numero) == "number" and type(a) == "table" and type(a.monde) == "table"
    and type(a.monde[1]) == "number" and type(a.monde[2]) == "number" and type(a.monde[3]) == "number"
    and not (type(ns.QUETES) == "table" and ns.QUETES[numero]) -- la base gagne toujours
end

-- Les numéros des quêtes apprises, dans l'ordre (le même résultat à chaque fois).
local function numerosApprises()
  local liste = {}
  if db and type(db.appris) == "table" then
    for numero, a in pairs(db.appris) do
      if apprisePosee(numero, a) then liste[#liste + 1] = numero end
    end
  end
  table.sort(liste)
  return liste
end

-- Les quêtes apprises qui tombent sur la carte : { { x, y, quetes = { numéro } } }, gardées jusqu'au prochain changement.
local function pointsApprisDe(carte)
  local ori = laOrientation()
  local c = cacheAppris[carte]
  if c and c.version == apprisVersion and c.ori == ori then return c.points end
  local points = {}
  local continents = continentsDe(carte)
  local transformer = ns.TRANSFORMATIONS[ori]
  for _, numero in ipairs(numerosApprises()) do
    local m = db.appris[numero].monde
    if continents[m[1]] then
      local ga, gb = transformer(m[2], m[3])
      local x, y = convertirBrut(m[1], ga, gb, carte)
      if x and x >= 0 and x <= 1 and y >= 0 and y <= 1 then points[#points + 1] = { x = x, y = y, quetes = { numero } } end
    end
  end
  cacheAppris[carte] = { version = apprisVersion, ori = ori, points = points }
  return points
end

-- ---------------------------------------------------------------------------
-- Ce qui est à montrer sur une carte
-- ---------------------------------------------------------------------------

local requetes = {} -- quêtes dont on a déjà demandé le titre au jeu (une fois suffit)

-- Le titre d'une quête : celui du jeu s'il est chargé (dans la langue du jeu), sinon l'anglais des données.
-- demanderLeJeu : on lui demande de le charger (réponse à QUEST_DATA_LOAD_RESULT).
local function titreDe(numero, demanderLeJeu)
  local t = C_QuestLog and C_QuestLog.GetTitleForQuestID and sur(C_QuestLog.GetTitleForQuestID, numero)
  if type(t) ~= "string" or t == "" then
    if demanderLeJeu and not requetes[numero] and C_QuestLog and C_QuestLog.RequestLoadQuestByID then
      requetes[numero] = true
      pcall(C_QuestLog.RequestLoadQuestByID, numero)
    end
    t = nil
  end
  local f = ns.ficheDe(numero)
  return ns.titreQuete(numero, t, f and f.titre)
end

local joueurDernier -- le joueur de la dernière passe, pour la bulle
local dernierEtat   -- ce que la dernière passe a vu (pour /qd etat et le diagnostic)

-- Les « ! » d'une carte : { { x, y, quetes, grise } }, et l'état. nil si le calcul des points n'est pas fini
-- (rappel est alors appelé à la fin).
local function evaluer(carte, tolerance, rappel)
  local points = positionsDeCarte(carte, rappel)
  if not points then return nil end
  local joueur = construireJoueur()
  joueurDernier = joueur
  local resultats, exclues, montrees = {}, {}, 0
  local bruts = {}
  local function visiter(p)
    local gardees = {}
    for _, n in ipairs(p.quetes) do
      local r = resultats[n]
      if r == nil then
        local f = ns.ficheDe(n)
        if f then
          local dispo, raison = ns.disponible(f, joueur, db)
          r = { dispo = dispo, raison = raison }
          if dispo then montrees = montrees + 1 else exclues[raison] = (exclues[raison] or 0) + 1 end
        else
          r = false
        end
        resultats[n] = r
      end
      if r and r.dispo then gardees[#gardees + 1] = n end
    end
    if #gardees > 0 then bruts[#bruts + 1] = { x = p.x, y = p.y, quetes = gardees } end
  end
  for _, p in ipairs(points) do visiter(p) end
  for _, p in ipairs(pointsApprisDe(carte)) do visiter(p) end -- les quêtes apprises en jeu
  local epingles = ns.regrouper(bruts, tolerance)
  local titres = {}
  for _, e in ipairs(epingles) do
    e.grise = true
    for _, n in ipairs(e.quetes) do
      if resultats[n].raison ~= "bientot" then e.grise = false end
      if #titres < 15 then
        local f = ns.ficheDe(n)
        titres[#titres + 1] = ns.titreAffiche(f.niveau, titreDe(n, false)) .. " (n° " .. n .. ")"
      end
    end
  end
  return epingles, { carte = carte, montrees = montrees, epingles = #epingles, exclues = exclues, titres = titres }, joueur
end

-- ---------------------------------------------------------------------------
-- Balise
-- ---------------------------------------------------------------------------

local function nomCarte(carte)
  local info = C_Map and C_Map.GetMapInfo and sur(C_Map.GetMapInfo, carte)
  return type(info) == "table" and info.name or ("carte " .. tostring(carte))
end

-- Notre GPS s'il est là, sinon la balise du jeu.
local function baliser(carte, x, y, titre)
  if GPS_Ajouter and GPS_Ajouter(carte, x, y, titre) then return end
  if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
    if C_Map.CanSetUserWaypointOnMap and not sur(C_Map.CanSetUserWaypointOnMap, carte) then
      return dire("le jeu refuse une balise sur cette carte.")
    end
    pcall(function() C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(carte, x, y)) end)
    if C_Map.HasUserWaypoint and not sur(C_Map.HasUserWaypoint) then
      return dire("balise refusée par le jeu : " .. titre .. ", " .. nomCarte(carte) .. string.format(" %.1f, %.1f", x * 100, y * 100))
    end
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
    dire(string.format("balise posée : %s (%s %.1f, %.1f).", titre, nomCarte(carte), x * 100, y * 100))
  else
    dire("pas de balise possible ici : " .. titre .. ".")
  end
end

-- ---------------------------------------------------------------------------
-- Les épingles sur la carte du monde
-- ---------------------------------------------------------------------------

local ICONE = "Interface\\GossipFrame\\AvailableQuestIcon" -- le « ! » jaune des quêtes à prendre
local epingles = {}     -- la réserve d'épingles, réutilisées d'une passe à l'autre
local carteDessinee     -- la carte pour laquelle les épingles sont posées
local survol            -- l'épingle sous la souris (pour rafraîchir la bulle quand un titre arrive)
local rafraichirSur     -- défini plus bas

local function taillePin()
  local t = tonumber(db and db.taille) or 20
  return math.max(12, math.min(32, t))
end

local MAX_LIGNES = 15 -- lignes de quêtes dans la bulle, au plus

-- Le contenu de la bulle d'un « ! » : les quêtes, et le rappel des clics (la minimap n'en a pas).
local function remplirBulle(quetes, avecClics)
  local nb = #quetes
  GameTooltip:AddLine(nb > 1 and ("Quêtes disponibles (" .. nb .. ")") or "Quête disponible", 1, 0.82, 0)
  local joueur = joueurDernier or construireJoueur()
  local lignes = ns.lignesQuetes(quetes, joueur, db, function(n) return titreDe(n, true) end)
  for i, l in ipairs(lignes) do
    if i > MAX_LIGNES then
      GameTooltip:AddLine("… et " .. (#lignes - MAX_LIGNES) .. " autres", 0.6, 0.6, 0.6)
      break
    end
    GameTooltip:AddDoubleLine(l.texte, l.marques, l.r, l.v, l.b, 0.6, 0.6, 0.6)
  end
  if avecClics then GameTooltip:AddLine("Clic gauche : balise     Clic droit : ne plus montrer ces quêtes", 0.6, 0.6, 0.6) end
  GameTooltip:Show()
end

local function infobulle(p)
  local e = p.donnees
  if not e then return end
  survol = p
  GameTooltip:SetOwner(p, "ANCHOR_RIGHT")
  remplirBulle(e.quetes, true)
end

local function clic(self, bouton)
  local e = self.donnees
  if not e then return end
  if bouton == "RightButton" then
    local ignorees = ignoreesDe()
    for _, n in ipairs(e.quetes) do ignorees[n] = true end
    dire(#e.quetes == 1 and "1 quête cachée à cet endroit. Les réglages permettent de la remontrer."
      or (#e.quetes .. " quêtes cachées à cet endroit. Les réglages permettent de les remontrer."))
    GameTooltip:Hide()
    rafraichirSur()
  else
    local titre = #e.quetes == 1 and titreDe(e.quetes[1], false) or "Quêtes disponibles"
    baliser(e.carte, e.x, e.y, titre)
  end
end

local function prendreEpingle(i, toile)
  local p = epingles[i]
  if not p then
    p = CreateFrame("Button", nil, toile)
    p:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    p.image = p:CreateTexture(nil, "ARTWORK")
    p.image:SetAllPoints()
    p.image:SetTexture(ICONE)
    p.nombre = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.nombre:SetPoint("BOTTOMRIGHT", 5, -3)
    p:SetScript("OnEnter", infobulle)
    p:SetScript("OnLeave", function(self) if survol == self then survol = nil end GameTooltip:Hide() end)
    p:SetScript("OnClick", clic)
    epingles[i] = p
  end
  return p
end

local function cacherExclamations()
  for _, p in ipairs(epingles) do p:Hide() end
  carteDessinee = nil
end

local function dessiner(liste, carte, toile)
  local largeur, hauteur = toile:GetWidth(), toile:GetHeight()
  if type(largeur) ~= "number" or largeur <= 0 then return end -- carte pas encore dimensionnée : OnSizeChanged rappellera
  local taille = taillePin()
  for i, e in ipairs(liste) do
    local p = prendreEpingle(i, toile)
    p.donnees = { carte = carte, x = e.x, y = e.y, quetes = e.quetes, grise = e.grise }
    p:SetSize(taille, taille)
    -- Tout en haut de la carte : à +2000, les zones bleues des quêtes en cours passaient encore par-dessus
    -- et les « ! » y paraissaient effacés (capture du 11/11). Le jeu plafonne le niveau à 10000.
    p:SetFrameLevel(math.min(toile:GetFrameLevel() + 7000, 9990))
    p.image:SetDesaturated(e.grise and true or false)
    p:SetAlpha(e.grise and 0.6 or 1)
    p.nombre:SetText(#e.quetes > 1 and tostring(#e.quetes) or "")
    p:ClearAllPoints()
    p:SetPoint("CENTER", toile, "TOPLEFT", e.x * largeur, -e.y * hauteur)
    p:Show()
  end
  for i = #liste + 1, #epingles do epingles[i]:Hide() end
  carteDessinee = carte
end

-- ---------------------------------------------------------------------------
-- Les quêtes du journal : leurs objectifs et l'endroit où les rendre, sur la carte du monde
-- ---------------------------------------------------------------------------

local ICONE_RENDRE = "Interface\\GossipFrame\\ActiveQuestIcon" -- le « ? » jaune des quêtes à rendre
-- Les icônes des objectifs, par genre : un crâne (tuer), un sac (ramasser), une main (utiliser un objet du décor).
local ICONES_OBJECTIF = {
  [1] = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
  [2] = "Interface\\GossipFrame\\VendorGossipIcon",
  [3] = "Interface\\Cursor\\Interact",
}
local JOURNAL_MAX = 60 -- lignes du journal lues au plus (en-têtes compris : 25 quêtes au plus dans le jeu)

local journalCache        -- le journal lu (nil : à relire)
local dernierEtatJournal  -- ce que la dernière passe a montré : objectifs, rendre, et pourquoi zéro
local cacheJournalCarte = {} -- [carte] = { ori, continents, points = { [clé] = { { x, y } } } }

local function oublierJournal()
  journalCache = nil
end

-- Le journal du jeu : { lu, liste = { { id, titre, niveau, complete, echouee, objectifs, lus } }, parId, index }.
-- lu est faux si le jeu ne donne pas le journal (alors rien n'est montré).
local function lireJournal()
  if journalCache then return journalCache end
  local j = { lu = false, liste = {}, parId = {} }
  journalCache = j
  local ql = C_QuestLog
  if type(ql) ~= "table" or type(ql.GetNumQuestLogEntries) ~= "function" or type(ql.GetInfo) ~= "function" then return j end
  local n = lisible(sur(ql.GetNumQuestLogEntries))
  if type(n) ~= "number" then return j end
  j.lu = true
  for i = 1, math.min(n, JOURNAL_MAX) do
    local info = sur(ql.GetInfo, i)
    if type(info) == "table" and not lisible(info.isHeader) then
      local id = lisible(info.questID)
      if type(id) == "number" and id > 0 and not j.parId[id] then
        local brut = type(ql.GetQuestObjectives) == "function" and sur(ql.GetQuestObjectives, id) or nil
        local objectifs = {}
        for _, o in ipairs(type(brut) == "table" and brut or {}) do
          if type(o) == "table" then
            local texte = lisible(o.text)
            objectifs[#objectifs + 1] = {
              texte = type(texte) == "string" and texte or nil, type = lisible(o.type), fini = lisible(o.finished) == true,
              fait = tonumber((lisible(o.numFulfilled))), total = tonumber((lisible(o.numRequired))),
            }
          end
        end
        local etat
        if type(ql.IsComplete) == "function" then etat = lisible(sur(ql.IsComplete, id)) end
        if etat == nil then etat = lisible(info.isComplete) end
        local titre = lisible(info.title)
        if type(titre) ~= "string" or titre == "" then titre = lisible(sur(ql.GetTitleForQuestID, id)) end
        local f = ns.fiche(id)
        local niveau = tonumber((lisible(info.level)))
        if not niveau or niveau <= 0 then niveau = f and f.niveau or nil end
        local q = {
          id = id, titre = type(titre) == "string" and titre ~= "" and titre or (f and f.titre) or nil, niveau = niveau,
          objectifs = objectifs, lus = type(brut) == "table",
          echouee = etat == -1 or lisible(info.isFailed) == true
            or (type(ql.IsFailed) == "function" and lisible(sur(ql.IsFailed, id)) == true),
        }
        q.complete = not q.echouee and ns.queteFinie(etat, objectifs, q.lus)
        j.liste[#j.liste + 1] = q
        j.parId[id] = q
      end
    end
  end
  return j
end

-- Les positions (liste plate « continent, x, y, ... » de la base) qui tombent sur la carte, gardées par carte.
local function pointsSurCarte(carte, cle, plat)
  local ori = laOrientation()
  local c = cacheJournalCarte[carte]
  if not c or c.ori ~= ori then
    c = { ori = ori, continents = continentsDe(carte), points = {} }
    cacheJournalCarte[carte] = c
  end
  local p = c.points[cle]
  if p then return p end
  p = {}
  local transformer = ns.TRANSFORMATIONS[ori]
  for k = 1, #plat - 2, 3 do
    local cont, a, b = plat[k], plat[k + 1], plat[k + 2]
    if c.continents[cont] and type(a) == "number" and type(b) == "number" then
      local ga, gb = transformer(a, b)
      local x, y = convertirBrut(cont, ga, gb, carte)
      if x and x >= 0 and x <= 1 and y >= 0 and y <= 1 then p[#p + 1] = { x = x, y = y } end
    end
  end
  c.points[cle] = p
  return p
end

local function nomsAppris()
  if db and type(db.nomsPnj) ~= "table" then db.nomsPnj = {} end
  return db and db.nomsPnj
end

-- Ce qu'il faut poser sur la carte pour les quêtes du journal : { { x, y, quetes = { éléments }, sorte, grise } }
-- (sorte « objectif » ou « rendre ») et l'état pour /qd etat.
local function calculerJournalCarte(carte, genre)
  local j = lireJournal()
  local liste = {}
  -- Les objectifs (seulement sur la carte d'une zone : sur un continent, il y en aurait partout).
  local cObj = { option = db.objectifsCarte, carteZone = genre == "zone", journalLu = j.lu, nbJournal = #j.liste,
    nbDansBase = 0, nbAFaire = 0, nbAvecPositions = 0, surCarte = 0 }
  if db.objectifsCarte and genre == "zone" and j.lu then
    local bruts = {}
    for _, q in ipairs(j.liste) do
      local base = type(ns.OBJECTIFS) == "table" and ns.OBJECTIFS[q.id]
      if type(base) == "table" then
        cObj.nbDansBase = cObj.nbDansBase + 1
        for _, o in ipairs(ns.objectifsAFaire(q, base)) do
          cObj.nbAFaire = cObj.nbAFaire + 1
          if #o.positions >= 3 then
            cObj.nbAvecPositions = cObj.nbAvecPositions + 1
            local element = { q = q, i = o.i, genre = o.genre, texte = o.texte }
            for _, p in ipairs(pointsSurCarte(carte, "o" .. q.id .. ":" .. o.i, o.positions)) do
              bruts[#bruts + 1] = { x = p.x, y = p.y, quetes = { element } }
            end
          end
        end
      end
    end
    for _, e in ipairs(ns.regrouper(bruts, 0.015)) do
      e.sorte = "objectif"
      liste[#liste + 1] = e
    end
    cObj.surCarte = #liste
  end
  -- Les « ? » : où rendre les quêtes finies (et les autres en gris, si l'option est cochée).
  local cFin = { option = db.rendre, gris = db.rendreGris, journalLu = j.lu, nbJournal = #j.liste, nbAMontrer = 0,
    nbAvecFin = 0, surCarte = 0 }
  local nbRendre, nbGris = 0, 0
  if db.rendre and j.lu then
    local index = ns.indexFins(ns.FINS)
    local bruts = {}
    local aMontrer = ns.quetesARendre(j.liste, true, db.rendreGris)
    cFin.nbAMontrer = #aMontrer
    for _, r in ipairs(aMontrer) do
      local indices = index[r.q.id]
      if indices then
        cFin.nbAvecFin = cFin.nbAvecFin + 1
        for _, k in ipairs(indices) do
          local f = ns.FINS[k]
          local element = { q = r.q, gris = r.gris, pnj = ns.nomFin(f[4], f[5], nomsAppris(), ns.NOMS_FINS) }
          for _, p in ipairs(pointsSurCarte(carte, "f" .. k, { f[1], f[2], f[3] })) do
            bruts[#bruts + 1] = { x = p.x, y = p.y, quetes = { element } }
          end
        end
      end
    end
    for _, e in ipairs(ns.regrouper(bruts, genre == "continent" and 0.015 or 0.005)) do
      e.sorte = "rendre"
      e.grise = true
      for _, el in ipairs(e.quetes) do if not el.gris then e.grise = false end end
      if e.grise then nbGris = nbGris + 1 else nbRendre = nbRendre + 1 end
      liste[#liste + 1] = e
    end
    cFin.surCarte = nbRendre + nbGris
  end
  local etat = {
    carte = carte, objectifs = cObj.surCarte, rendre = nbRendre, gris = nbGris, journal = #j.liste, journalLu = j.lu,
    raisonObjectifs = ns.raisonObjectifs(cObj), raisonRendre = ns.raisonRendre(cFin),
  }
  return liste, etat
end

local iconesJournal = {} -- la réserve des icônes du journal sur la carte (objectifs et « ? »)
local carteJournal       -- la carte où elles sont posées
local survolJournal

local function niveauJoueur() return tonumber((sur(UnitLevel, "player"))) end

-- La bulle d'une icône d'objectif : chaque quête, puis ses objectifs avec leur progression.
local function remplirBulleObjectifs(elements, avecClics)
  local parQuete, ordre = {}, {}
  for _, e in ipairs(elements) do
    local b = parQuete[e.q.id]
    if not b then b = { q = e.q, textes = {} }; parQuete[e.q.id] = b; ordre[#ordre + 1] = b end
    if e.texte then b.textes[#b.textes + 1] = e.texte end
  end
  local nj = niveauJoueur()
  for i, b in ipairs(ordre) do
    if i > MAX_LIGNES then
      GameTooltip:AddLine("… et " .. (#ordre - MAX_LIGNES) .. " autres", 0.6, 0.6, 0.6)
      break
    end
    local r, v, bl = ns.couleurDifficulte(b.q.niveau, nj, plageVerte())
    GameTooltip:AddLine(ns.titreAffiche(b.q.niveau, b.q.titre or ("Quête " .. b.q.id)), r, v, bl)
    if #b.textes == 0 then GameTooltip:AddLine("   Objectif de la quête", 0.85, 0.85, 0.85) end
    for _, t in ipairs(b.textes) do GameTooltip:AddLine("   " .. t, 1, 1, 1) end
  end
  if avecClics then GameTooltip:AddLine("Clic gauche : balise", 0.6, 0.6, 0.6) end
  GameTooltip:Show()
end

-- La bulle d'un « ? » : celui qui reprend la quête (si on le connaît), puis « [niveau] Titre » et « (À rendre) ».
local function remplirBulleRendre(elements, avecClics)
  local nom, memeNom = elements[1] and elements[1].pnj, true
  for _, e in ipairs(elements) do
    if e.pnj ~= nom then memeNom = false end
  end
  if nom and memeNom then GameTooltip:AddLine(nom, 1, 0.82, 0)
  else GameTooltip:AddLine(#elements > 1 and "Quêtes à rendre" or "Quête à rendre", 1, 0.82, 0) end
  local nj, vus, nb = niveauJoueur(), {}, 0
  for _, e in ipairs(elements) do
    if not vus[e.q.id] then
      vus[e.q.id] = true
      nb = nb + 1
      if nb > MAX_LIGNES then break end
      local r, v, bl = ns.couleurDifficulte(e.q.niveau, nj, plageVerte())
      local droite = e.gris and "(En cours)" or "(À rendre)"
      if not memeNom and e.pnj then droite = e.pnj .. " " .. droite end
      GameTooltip:AddDoubleLine(ns.titreAffiche(e.q.niveau, e.q.titre or ("Quête " .. e.q.id)), droite, r, v, bl,
        e.gris and 0.6 or 1, e.gris and 0.6 or 0.82, e.gris and 0.6 or 0)
    end
  end
  if avecClics then GameTooltip:AddLine("Clic gauche : balise", 0.6, 0.6, 0.6) end
  GameTooltip:Show()
end

local function infobulleJournal(p)
  local e = p.journal
  if not e then return end
  survolJournal = p
  GameTooltip:SetOwner(p, "ANCHOR_RIGHT")
  if e.sorte == "rendre" then remplirBulleRendre(e.elements, true) else remplirBulleObjectifs(e.elements, true) end
end

local function clicJournal(self)
  local e = self.journal
  if not e then return end
  local premier = e.elements[1]
  local titre = premier and premier.q and premier.q.titre or "Quête"
  if e.sorte == "rendre" then titre = "Rendre : " .. titre end
  baliser(e.carte, e.x, e.y, titre)
end

local function prendreIconeJournal(i, toile)
  local p = iconesJournal[i]
  if not p then
    p = CreateFrame("Button", nil, toile)
    p:RegisterForClicks("LeftButtonUp")
    p.image = p:CreateTexture(nil, "ARTWORK")
    p.image:SetAllPoints()
    p:SetScript("OnEnter", infobulleJournal)
    p:SetScript("OnLeave", function(self) if survolJournal == self then survolJournal = nil end GameTooltip:Hide() end)
    p:SetScript("OnClick", clicJournal)
    iconesJournal[i] = p
  end
  return p
end

local function cacherJournal()
  for _, p in ipairs(iconesJournal) do p:Hide() end
  carteJournal = nil
end

local function dessinerJournal(liste, carte, toile)
  local largeur, hauteur = toile:GetWidth(), toile:GetHeight()
  if type(largeur) ~= "number" or largeur <= 0 then return end
  local taille = taillePin()
  local petite = math.max(10, math.floor(taille * 0.7 + 0.5))
  local base = toile:GetFrameLevel()
  for i, e in ipairs(liste) do
    local p = prendreIconeJournal(i, toile)
    p.journal = { carte = carte, x = e.x, y = e.y, sorte = e.sorte, elements = e.quetes, grise = e.grise }
    if e.sorte == "rendre" then
      p:SetSize(taille, taille)
      -- Au-dessus des « ! » (un « ? » et un « ! » au même PNJ : le « ? » se voit), en restant sous le plafond.
      p:SetFrameLevel(math.min(base + 7010, 9990))
      p.image:SetTexture(ICONE_RENDRE)
    else
      p:SetSize(petite, petite)
      -- Sous les « ! » : un objectif ne doit pas cacher une quête à prendre.
      p:SetFrameLevel(math.min(base + 6900, 9980))
      local premier = e.quetes[1]
      p.image:SetTexture(ICONES_OBJECTIF[premier and premier.genre] or ICONES_OBJECTIF[1])
    end
    p.image:SetDesaturated(e.grise and true or false)
    p:SetAlpha(e.grise and 0.6 or 1)
    p:ClearAllPoints()
    p:SetPoint("CENTER", toile, "TOPLEFT", e.x * largeur, -e.y * hauteur)
    p:Show()
  end
  for i = #liste + 1, #iconesJournal do iconesJournal[i]:Hide() end
  carteJournal = carte
end

-- La couche du journal d'une carte : calcul, dessin, état. Protégée : une erreur ici n'empêche pas les « ! ».
local function passeJournal(carte, genre, toile)
  local ok, erreur = pcall(function()
    local liste, etat = calculerJournalCarte(carte, genre)
    dernierEtatJournal = etat
    dessinerJournal(liste, carte, toile)
  end)
  if not ok then
    ns.derniereErreur = tostring(erreur)
    cacherJournal()
  end
end

-- ---------------------------------------------------------------------------
-- La bulle des monstres : les quêtes du journal qui ont besoin de ce monstre, et où on en est
-- ---------------------------------------------------------------------------

local bulleAccrochee = false

-- Ce que la bulle montre déjà : les quêtes (lignes « titre de quête » du jeu) et tous les textes.
local function dejaDansBulle(tooltip, data)
  local deja = { ids = {}, textes = {} }
  local typeTitre = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestTitle
  if type(data) == "table" and type(data.lines) == "table" then
    for _, l in ipairs(data.lines) do
      if type(l) == "table" then
        local texte = lisible(l.leftText)
        if type(texte) == "string" then deja.textes[texte:lower()] = true end
        local id = lisible(l.id)
        if typeTitre and lisible(l.type) == typeTitre and type(id) == "number" then deja.ids[id] = true end
      end
    end
  end
  -- Les lignes déjà écrites (et celles d'autres addons) : on lit le texte affiché, s'il est lisible.
  local nom = tooltip.GetName and sur(tooltip.GetName, tooltip)
  local nb = tooltip.NumLines and sur(tooltip.NumLines, tooltip)
  if type(nom) == "string" and type(nb) == "number" then
    for i = 1, math.min(nb, 40) do
      local fs = _G[nom .. "TextLeft" .. i]
      local texte = fs and fs.GetText and lisible(sur(fs.GetText, fs))
      if type(texte) == "string" then deja.textes[texte:lower()] = true end
    end
  end
  return deja
end

-- Ajoute les lignes de nos quêtes à la bulle d'un monstre (survol ou cible).
local function bulleMonstre(tooltip, data)
  if not (db and db.actif and db.bulleMonstres) or tooltip ~= GameTooltip then return end
  if tooltip.IsForbidden and sur(tooltip.IsForbidden, tooltip) then return end
  -- En donjon et en raid, Forever cache les données des bulles aux addons : on laisse le jeu faire.
  if sur(IsInInstance) then return end
  local guid = type(data) == "table" and lisible(data.guid) or nil
  if type(guid) ~= "string" then
    local _, unite = sur(tooltip.GetUnit, tooltip)
    unite = lisible(unite)
    if type(unite) == "string" then guid = lisible(sur(UnitGUID, unite)) end
  end
  local creature = ns.creatureDuGuid(guid)
  if not creature then return end
  local j = lireJournal()
  if not j.lu or #j.liste == 0 then return end
  if not j.index then j.index = ns.indexMonstres(j.liste, ns.OBJECTIFS) end
  -- Les objets que BarresDeVie a vu tomber de ce genre de monstre (lecture seule de sa sauvegarde).
  local butins = type(BarresDeVieDB) == "table" and type(BarresDeVieDB.butins) == "table" and BarresDeVieDB.butins[creature] or nil
  if not j.index[creature] and type(butins) ~= "table" then return end
  local blocs = ns.lignesBulleMonstre(creature, j.liste, ns.OBJECTIFS, j.index, butins, dejaDansBulle(tooltip, data),
    niveauJoueur(), plageVerte())
  if #blocs == 0 then return end
  for _, b in ipairs(blocs) do
    tooltip:AddLine(b.titre, b.r, b.v, b.b)
    for _, l in ipairs(b.lignes) do tooltip:AddLine("   " .. l, 1, 1, 1) end
  end
  tooltip:Show()
end

local function bulleMonstreProtegee(tooltip, data)
  local ok, erreur = pcall(bulleMonstre, tooltip, data)
  if not ok then ns.derniereErreur = tostring(erreur) end
end

-- S'accrocher à la bulle : le chemin moderne (TooltipDataProcessor) d'abord, sinon l'ancien (OnTooltipSetUnit).
local function accrocherBulle()
  if bulleAccrochee then return end
  if type(TooltipDataProcessor) == "table" and type(TooltipDataProcessor.AddTooltipPostCall) == "function"
    and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
    bulleAccrochee = pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Unit, bulleMonstreProtegee)
  end
  if not bulleAccrochee and type(GameTooltip) == "table" and type(GameTooltip.HookScript) == "function"
    and type(GameTooltip.HasScript) == "function" and sur(GameTooltip.HasScript, GameTooltip, "OnTooltipSetUnit") then
    bulleAccrochee = pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", function(t) bulleMonstreProtegee(t, nil) end)
  end
end

-- Le nom (en français) de celui qui reprend des quêtes, appris quand on lui parle. Seulement ceux de la base.
local NOMS_MAX = 3000
local function apprendreNomPnj()
  if not db or type(UnitGUID) ~= "function" then return end
  local guid = lisible(sur(UnitGUID, "npc")) or lisible(sur(UnitGUID, "questnpc"))
  if type(guid) ~= "string" then return end
  local genre, id = guid:match("^(%a+)%-[^%-]*%-[^%-]*%-[^%-]*%-[^%-]*%-(%d+)")
  id = tonumber(id)
  local cle
  if genre == "Creature" or genre == "Vehicle" then cle = ns.cleFin(1, id)
  elseif genre == "GameObject" then cle = ns.cleFin(2, id) end
  if not cle or type(ns.NOMS_FINS) ~= "table" or not ns.NOMS_FINS[cle] then return end
  local nom = lisible(sur(UnitName, "npc")) or lisible(sur(UnitName, "questnpc"))
  if type(nom) ~= "string" or nom == "" or nom == UNKNOWNOBJECT then return end
  local noms = nomsAppris()
  if noms[cle] == nil then
    local n = 0
    for _ in pairs(noms) do n = n + 1 end
    if n >= NOMS_MAX then return end
  end
  noms[cle] = nom
end

-- Tout ce qui est posé sur la carte : les « ! » et les icônes du journal.
local function cacherTout()
  cacherExclamations()
  cacherJournal()
end

local donneesDites, apiQuetesDite = false, false

-- Une passe : on regarde la carte ouverte et on pose les « ! ». Rien n'est créé si la carte n'est pas affichée.
local function passe()
  if not db then return end
  if not (type(WorldMapFrame) == "table" and WorldMapFrame.IsShown and WorldMapFrame:IsShown()) then return end
  if not db.actif then return cacherTout() end
  if not donneesPresentes() then return cacherTout() end
  local carte = lisible(WorldMapFrame.GetMapID and sur(WorldMapFrame.GetMapID, WorldMapFrame))
  if type(carte) ~= "number" then return cacherTout() end
  local toile = WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child
  if not toile then return end

  local genre = genreCarte(carte)
  if genre == "rien" or (genre == "continent" and not db.continent) then
    cacherTout()
    dernierEtat = { carte = carte, montrees = 0, epingles = 0, exclues = {}, titres = {}, note = "carte non concernée" }
    dernierEtatJournal = { carte = carte, objectifs = 0, rendre = 0, gris = 0,
      raisonObjectifs = "carte non concernée", raisonRendre = "carte non concernée" }
    return
  end
  -- Les quêtes du journal d'abord : elles ne dépendent pas du calcul des « ! ».
  passeJournal(carte, genre, toile)
  local liste, etat, joueur = evaluer(carte, genre == "continent" and 0.015 or 0.005, demander)
  if not liste then return end -- le calcul continue, il rappellera
  if not joueur.etatConnu then
    cacherExclamations()
    if not apiQuetesDite then
      apiQuetesDite = true
      dire("le jeu ne dit pas quelles quêtes sont rendues : aucun « ! » n'est montré.")
    end
    return
  end
  dernierEtat = etat
  dessiner(liste, carte, toile)
end

rafraichirSur = function()
  local ok, erreur = pcall(passe)
  if not ok then
    ns.derniereErreur = tostring(erreur)
    if not ns.erreurDite then
      ns.erreurDite = true
      dire("une erreur a été retenue (" .. ns.derniereErreur .. "). L'addon réessaie au prochain changement.")
    end
  end
end

local enAttente = false
-- Regroupe les demandes : une seule passe, 0,2 s après la première.
demander = function()
  if enAttente then return end
  enAttente = true
  apres(0.2, function()
    enAttente = false
    rafraichirSur()
  end)
end
ns.demander = demander
ns.rafraichir = rafraichirSur
function ns.etat() return dernierEtat end

-- ---------------------------------------------------------------------------
-- Apprendre les donneurs de quêtes
-- Quand un PNJ propose une quête que la base ne connaît pas, on retient où le joueur se tenait (à côté du PNJ) :
-- elle réapparaît ensuite sur la carte et la minimap comme les autres. On la partage avec le groupe.
-- ---------------------------------------------------------------------------

local APPRIS_MAX = 3000   -- au plus autant de quêtes apprises : la sauvegarde reste petite
local dernierRecu = {}    -- [numéro de quête] = heure du dernier message traité pour elle
local nbDernierRecu = 0

local function arrondi1(v) return math.floor(v * 10 + 0.5) / 10 end

local function nbApprises()
  local n, groupe = 0, 0
  for _, a in pairs(db and type(db.appris) == "table" and db.appris or {}) do
    n = n + 1
    if type(a) == "table" and a.source == "groupe" then groupe = groupe + 1 end
  end
  return n, groupe
end

-- Le PNJ (ou l'objet) avec qui le joueur parle. Rend « ok » et son numéro de créature ; « refuse » si c'est autre
-- chose (un joueur qui partage une quête, un objet qui en donne une : le joueur peut être loin) ; « inconnu » si le
-- jeu ne le dit pas.
local function cibleDeQuete()
  if type(UnitGUID) ~= "function" then return "inconnu" end
  local guid = lisible(sur(UnitGUID, "npc")) or lisible(sur(UnitGUID, "questnpc"))
  if type(guid) ~= "string" then return "inconnu" end
  local genre, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
  if genre == "Creature" or genre == "Vehicle" or genre == "GameObject" then return "ok", tonumber(id) end
  return "refuse"
end

-- Le canal du groupe : « RAID », « PARTY », ou rien si on est seul.
local function canalGroupe()
  if sur(IsInRaid) then return "RAID" end
  if sur(IsInGroup) then return "PARTY" end
  return nil
end

-- Envoie une quête apprise au groupe (option « partager »).
local function partagerQuete(numero, a)
  if not db.partager then return end
  local canal = canalGroupe()
  if not canal then return end
  local texte = ns.codeAppris({ numero = numero, titre = a.titre, niveau = a.niveau, monde = a.monde })
  if not texte then return end
  local envoyer = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
  sur(envoyer, ns.PREFIXE, texte, canal)
end

-- Peut-on retenir cette quête ? Pas si la base la connaît, ni si on l'a déjà, ni si la liste est pleine.
local function retenable(numero)
  if type(numero) ~= "number" or numero < 1 or numero % 1 ~= 0 then return false end
  if type(ns.QUETES) == "table" and ns.QUETES[numero] then return false end
  if db.appris[numero] ~= nil then return false end
  return (nbApprises()) < APPRIS_MAX
end

-- Retient une quête proposée par un PNJ, avec la position du joueur. Rend la fiche retenue, ou nil.
local function retenirDuJeu(numero, titre, niveau, pnj)
  if not retenable(numero) then return nil end
  local p = positionJoueur()
  if not p then return nil end
  local a = {
    titre = type(titre) == "string" and titre ~= "" and titre or nil,
    niveau = type(niveau) == "number" and niveau > 0 and niveau <= 100 and niveau or nil,
    monde = { p.continent, arrondi1(p.x), arrondi1(p.y) }, carte = p.carte, pnj = pnj,
    date = type(date) == "function" and date("%Y-%m-%d") or nil, source = "jeu",
  }
  db.appris[numero] = a
  majApprises()
  partagerQuete(numero, a)
  return a
end

-- GOSSIP_SHOW, QUEST_GREETING, QUEST_DETAIL : ce que le PNJ propose.
local function apprendreEvenement(evenement)
  if not (db.actif and db.apprendre) or not donneesPresentes() then return end
  local etat, pnj = cibleDeQuete()
  local nouvelles = {}
  local function noter(numero, titre, niveau)
    numero, titre, niveau = lisible(numero), lisible(titre), lisible(niveau)
    local a = retenirDuJeu(numero, titre, niveau, pnj)
    if a then nouvelles[#nouvelles + 1] = ns.titreAffiche(a.niveau, ns.titreQuete(numero, a.titre, nil)) end
  end
  if evenement == "GOSSIP_SHOW" then
    if etat == "refuse" then return end
    local liste = C_GossipInfo and C_GossipInfo.GetAvailableQuests and sur(C_GossipInfo.GetAvailableQuests)
    for _, q in ipairs(type(liste) == "table" and liste or {}) do
      if type(q) == "table" then noter(q.questID, q.title, q.questLevel) end -- sans numéro, rien n'est retenu
    end
  elseif evenement == "QUEST_GREETING" then
    if etat == "refuse" then return end
    local n = lisible(sur(GetNumAvailableQuests))
    for i = 1, (type(n) == "number" and n or 0) do
      local r = { pcall(GetAvailableQuestInfo, i) } -- ok, trivial, fréquence, répétable, légendaire, numéro
      noter(r[1] and r[6] or nil, sur(GetAvailableTitle, i), sur(GetAvailableLevel, i))
    end
  elseif evenement == "QUEST_DETAIL" then
    if etat ~= "ok" then return end -- une quête partagée par un joueur ou donnée par un objet : on ne sait pas où est le PNJ
    noter(sur(GetQuestID), sur(GetTitleText), nil)
  end
  if #nouvelles > 0 and demander then demander() end -- la carte ouverte montre tout de suite le nouveau « ! »
  if #nouvelles == 1 then
    dire("quête apprise (la base ne la connaît pas) : " .. nouvelles[1] .. ".")
  elseif #nouvelles > 1 then
    dire(#nouvelles .. " quêtes apprises (la base ne les connaît pas) : " .. table.concat(nouvelles, ", ", 1, math.min(3, #nouvelles))
      .. (#nouvelles > 3 and ", …" or "") .. ".")
  end
end

-- Est-ce moi qui ai envoyé ce message ? (le jeu renvoie ses propres messages d'addon)
local function estMoi(expediteur)
  local court = expediteur:match("^([^%-]+)")
  local moi = sur(UnitName, "player")
  return court ~= nil and court == moi
end

-- CHAT_MSG_ADDON : une quête apprise par quelqu'un du groupe.
local function recevoir(prefixe, texte, canal, expediteur)
  prefixe, texte, canal, expediteur = lisible(prefixe), lisible(texte), lisible(canal), lisible(expediteur)
  if prefixe ~= ns.PREFIXE then return end
  if not (db.actif and db.apprendre and db.partager) then return end
  if canal ~= "PARTY" and canal ~= "RAID" and canal ~= "INSTANCE_CHAT" then return end
  if type(expediteur) ~= "string" or estMoi(expediteur) then return end
  local f = ns.decodeAppris(texte)
  if not f or not donneesPresentes() then return end
  -- Pas plus d'un message traité par quête et par minute (le groupe peut renvoyer la même cent fois).
  local t = maintenant()
  local avant = dernierRecu[f.numero]
  if avant and t - avant < 60 then return end
  if nbDernierRecu >= 500 then dernierRecu, nbDernierRecu = {}, 0 end
  if not avant then nbDernierRecu = nbDernierRecu + 1 end
  dernierRecu[f.numero] = t
  if not retenable(f.numero) then return end
  db.appris[f.numero] = {
    titre = f.titre, niveau = f.niveau, monde = f.monde,
    date = type(date) == "function" and date("%Y-%m-%d") or nil, source = "groupe",
  }
  majApprises()
  if demander then demander() end
end

-- Le bouton des réglages : oublier toutes les quêtes apprises.
local function oublier()
  if not db then return end
  local n = 0
  for k in pairs(db.appris) do n = n + 1; db.appris[k] = nil end
  dernierRecu, nbDernierRecu = {}, 0
  majApprises()
  if n == 0 then dire("aucune quête apprise à oublier.")
  elseif n == 1 then dire("1 quête apprise oubliée.")
  else dire(n .. " quêtes apprises oubliées.") end
  rafraichirSur()
end

-- ---------------------------------------------------------------------------
-- Les « ! » sur la minimap
-- De petites icônes, enfants de la Minimap (on n'écrit jamais dans la Minimap elle-même : seulement SetPoint sur
-- nos cadres). Deux rythmes : la liste des quêtes à moins de 300 m se refait toutes les 2 s, leur placement toutes
-- les 0,2 s, et seulement si le joueur, son regard ou le zoom ont bougé.
-- ---------------------------------------------------------------------------

local MINI_TAILLE = 13   -- côté des icônes, en pixels
local MINI_PORTEE = 300  -- on ne garde que les quêtes à moins de tant de mètres
local MINI_MAX = 40      -- icônes au plus
local MINI_REGROUPE = 15 -- des quêtes à moins de tant de mètres l'une de l'autre ne font qu'une icône
local pastilles = {}     -- la réserve d'icônes, réutilisées : jamais recréées
local miniProches = {}   -- { { x, y, quetes, grise } } : les quêtes proches, dans les axes de la base
local miniProchesAt, miniProchesPos, miniContinent
local miniSig            -- ce qui a servi au dernier placement
local miniVisibles = 0
local miniRendreVisibles = 0 -- dont les « ? »
local survolMini

-- Les mètres vus par la minimap (du centre au bord) selon le zoom, quand le jeu ne les donne pas
-- (C_Minimap.GetViewRadius). VALEURS SUPPOSÉES, d'après les diamètres connus de la minimap de WoW (mètres) :
-- dehors 466,7 400 333,3 266,7 200 133,3 ; dedans 300 240 180 120 80 50, du zoom 0 (le plus large) à 5.
-- Ici, les rayons : la moitié.
local RAYON_ZOOM = {
  dehors = { [0] = 233.33, 200, 166.67, 133.33, 100, 66.67 },
  dedans = { [0] = 150, 120, 90, 60, 40, 25 },
}

local function rayonMinimap()
  local r = C_Minimap and C_Minimap.GetViewRadius and lisible(sur(C_Minimap.GetViewRadius))
  if type(r) == "number" and r > 0 then return r end
  if type(Minimap) ~= "table" or not Minimap.GetZoom then return nil end
  local zoom = lisible(sur(Minimap.GetZoom, Minimap))
  if type(zoom) ~= "number" then return nil end
  local dedans = sur(IsIndoors) and true or false
  return (dedans and RAYON_ZOOM.dedans or RAYON_ZOOM.dehors)[zoom]
end

-- La minimap tourne-t-elle avec le regard du joueur ? (CVar « rotateMinimap »)
local function minimapTourne()
  local v = C_CVar and C_CVar.GetCVar and sur(C_CVar.GetCVar, "rotateMinimap")
  if v == nil and type(GetCVar) == "function" then v = sur(GetCVar, "rotateMinimap") end
  v = lisible(v)
  return v == "1" or v == 1 or v == true
end

local function infobulleMini(p)
  local e = p.mini
  if not e then return end
  survolMini = p
  GameTooltip:SetOwner(p, "ANCHOR_LEFT")
  if e.rendre then remplirBulleRendre(e.quetes, false) else remplirBulle(e.quetes, false) end
end

local function prendrePastille(i)
  local p = pastilles[i]
  if not p then
    p = CreateFrame("Button", nil, Minimap)
    p:SetSize(MINI_TAILLE, MINI_TAILLE)
    local niveau = Minimap.GetFrameLevel and Minimap:GetFrameLevel()
    p:SetFrameLevel(math.min((type(niveau) == "number" and niveau or 1) + 5, 9990))
    -- Pas de SetPassThroughButtons : cette fonction est protégée en combat (« action bloquée », déjà vu
    -- en jeu sur ce projet), et une icône peut être créée pendant un combat.
    p.image = p:CreateTexture(nil, "ARTWORK")
    p.image:SetAllPoints()
    p.image:SetTexture(ICONE)
    p.nombre = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.nombre:SetPoint("BOTTOMRIGHT", 4, -3)
    p:SetScript("OnEnter", infobulleMini)
    p:SetScript("OnLeave", function(self) if survolMini == self then survolMini = nil end GameTooltip:Hide() end)
    pastilles[i] = p
  end
  return p
end

local function cacherMinimap()
  if miniVisibles > 0 or miniSig then
    for _, p in ipairs(pastilles) do p:Hide() end
    if survolMini then survolMini = nil; GameTooltip:Hide() end
  end
  miniVisibles, miniRendreVisibles, miniSig = 0, 0, nil
end

-- Les quêtes à prendre à moins de MINI_PORTEE mètres du joueur, avec les mêmes filtres que la carte.
local function recalculerExclamationsProches(pos, rayon)
  miniProchesAt, miniProchesPos, miniContinent, miniSale = maintenant(), { pos.x, pos.y }, pos.continent, false
  local portee = math.max(MINI_PORTEE, rayon + 30)
  local portee2 = portee * portee
  local bruts = {}
  local function proche(x, y, quetes)
    if type(x) ~= "number" or type(y) ~= "number" then return end
    local dx, dy = x - pos.x, y - pos.y
    if dx * dx + dy * dy < portee2 then bruts[#bruts + 1] = { x = x, y = y, quetes = quetes } end
  end
  local departs = ns.DEPARTS
  for i = 1, #departs do
    local d = departs[i]
    if type(d) == "table" and d[1] == pos.continent then proche(d[2], d[3], d[5] or {}) end
  end
  for _, numero in ipairs(numerosApprises()) do
    local m = db.appris[numero].monde
    if m[1] == pos.continent then proche(m[2], m[3], { numero }) end
  end
  miniProches = {}
  if #bruts == 0 then return end
  local joueur = construireJoueur()
  joueurDernier = joueur
  if not joueur.etatConnu then return end
  local raisons, gardes = {}, {}
  for _, b in ipairs(bruts) do
    local gardees = {}
    for _, n in ipairs(b.quetes) do
      if raisons[n] == nil then
        local f = ns.ficheDe(n)
        if f then
          local dispo, raison = ns.disponible(f, joueur, db)
          raisons[n] = dispo and (raison or true) or false
        else
          raisons[n] = false
        end
      end
      if raisons[n] then gardees[#gardees + 1] = n end
    end
    if #gardees > 0 then gardes[#gardes + 1] = { x = b.x, y = b.y, quetes = gardees } end
  end
  for _, e in ipairs(ns.regrouper(gardes, MINI_REGROUPE)) do
    if #miniProches < MINI_MAX then
      e.grise = true
      for _, n in ipairs(e.quetes) do if raisons[n] ~= "bientot" then e.grise = false end end
      miniProches[#miniProches + 1] = e
    end
  end
end

-- Les « ? » proches : où rendre les quêtes du journal (finies, et les autres en gris si l'option est cochée).
local MINI_RENDRE_MAX = 10
local function ajouterRendreProches(pos, portee2)
  if not (db.rendre and type(ns.FINS) == "table") then return end
  local j = lireJournal()
  if not j.lu then return end
  local index = ns.indexFins(ns.FINS)
  local bruts = {}
  for _, r in ipairs(ns.quetesARendre(j.liste, true, db.rendreGris)) do
    for _, k in ipairs(index[r.q.id] or {}) do
      local f = ns.FINS[k]
      if f[1] == pos.continent then
        local dx, dy = f[2] - pos.x, f[3] - pos.y
        if dx * dx + dy * dy < portee2 then
          bruts[#bruts + 1] = { x = f[2], y = f[3],
            quetes = { { q = r.q, gris = r.gris, pnj = ns.nomFin(f[4], f[5], nomsAppris(), ns.NOMS_FINS) } } }
        end
      end
    end
  end
  local n = 0
  for _, e in ipairs(ns.regrouper(bruts, MINI_REGROUPE)) do
    if n < MINI_RENDRE_MAX then
      n = n + 1
      e.rendre = true
      e.grise = true
      for _, el in ipairs(e.quetes) do if not el.gris then e.grise = false end end
      miniProches[#miniProches + 1] = e
    end
  end
end

local function recalculerProches(pos, rayon)
  recalculerExclamationsProches(pos, rayon)
  local portee = math.max(MINI_PORTEE, rayon + 30)
  local ok, erreur = pcall(ajouterRendreProches, pos, portee * portee)
  if not ok then ns.derniereErreur = tostring(erreur) end
end

-- Un passage du minuteur de 0,2 s.
local function tickMinimap()
  if not db then return end
  if not (db.actif and db.surMinimap) or not donneesPresentes() or type(Minimap) ~= "table" then
    miniSale = true
    return cacherMinimap()
  end
  local pos = positionJoueur()
  local rayon = pos and rayonMinimap()
  local largeur = type(Minimap.GetWidth) == "function" and Minimap:GetWidth()
  if not pos or not rayon or type(largeur) ~= "number" or largeur <= 0 then
    miniSale = true
    return cacherMinimap()
  end
  local rotation = 0
  if minimapTourne() then
    local regard = lisible(sur(GetPlayerFacing))
    if type(regard) ~= "number" then return cacherMinimap() end -- sans le regard, impossible de bien tourner
    rotation = -regard
  end
  -- La liste des quêtes proches : toutes les 2 s, ou si elle est périmée (options, quêtes, continent, grand déplacement).
  local t = maintenant()
  local refaite = false
  local loin = miniProchesPos and ((pos.x - miniProchesPos[1]) ^ 2 + (pos.y - miniProchesPos[2]) ^ 2 > 3600)
  if miniSale or loin or not miniProchesAt or t - miniProchesAt >= 2 or t < miniProchesAt or pos.continent ~= miniContinent then
    recalculerProches(pos, rayon)
    refaite = true
  end
  -- Le placement : seulement si quelque chose a bougé.
  local s = miniSig
  if not refaite and s and s.x == pos.x and s.y == pos.y and s.rotation == rotation and s.rayon == rayon and s.largeur == largeur then
    return
  end
  miniSig = { x = pos.x, y = pos.y, rotation = rotation, rayon = rayon, largeur = largeur }
  local demi, n, nRendre = largeur / 2, 0, 0
  for _, e in ipairs(miniProches) do
    local px, py = ns.placementMinimap(e.x - pos.x, e.y - pos.y, rayon, demi, rotation, MINI_TAILLE / 2)
    if px then
      n = n + 1
      local p = prendrePastille(n)
      if p.mini ~= e then
        p.mini = e
        p.image:SetTexture(e.rendre and ICONE_RENDRE or ICONE)
        p.image:SetDesaturated(e.grise and true or false)
        p:SetAlpha(e.grise and 0.6 or 1)
        p.nombre:SetText((not e.rendre and #e.quetes > 1) and tostring(#e.quetes) or "")
      end
      if e.rendre then nRendre = nRendre + 1 end
      p:ClearAllPoints()
      p:SetPoint("CENTER", Minimap, "CENTER", px, py)
      p:Show()
    end
  end
  for i = n + 1, #pastilles do pastilles[i]:Hide() end
  miniVisibles, miniRendreVisibles = n, nRendre
end

local function tickMinimapProtege()
  local ok, erreur = pcall(tickMinimap)
  if not ok then ns.derniereErreur = tostring(erreur) end
end

-- ---------------------------------------------------------------------------
-- Réglages
-- ---------------------------------------------------------------------------

local function remontrer()
  if not db then return end
  local ignorees = ignoreesDe()
  local n = 0
  for k in pairs(ignorees) do n = n + 1; ignorees[k] = nil end
  if n == 0 then dire("aucune quête cachée à remontrer.")
  elseif n == 1 then dire("1 quête remontrée.")
  else dire(n .. " quêtes remontrées.") end
  rafraichirSur()
end

ns.reglages = ns.creerReglages({
  titre = "Quêtes disponibles",
  icone = ICONE,
  nomDB = "QuetesDispoDB",
  defauts = DEFAUTS,
  options = {
    { titre = "Filtres" },
    { cle = "actif", libelle = "Activer Quêtes disponibles",
      aide = "Coupé : plus aucun « ! » sur la carte du monde." },
    { cle = "basNiveau", libelle = "Montrer aussi les quêtes de bas niveau",
      aide = "Les quêtes grises, devenues trop faciles pour ton niveau, sont cachées par défaut." },
    { cle = "repetables", libelle = "Montrer les quêtes répétables",
      aide = "Les quêtes qu'on peut refaire (journalières ou autres)." },
    { cle = "donjons", libelle = "Montrer les quêtes de donjon et de raid",
      aide = "Les quêtes qui se font dans un donjon ou un raid, avec la marque Donjon ou Raid dans la bulle." },
    { cle = "jcj", libelle = "Montrer les quêtes JcJ",
      aide = "Les quêtes de champ de bataille et de combat entre joueurs." },
    { cle = "saisonnieres", libelle = "Montrer les quêtes saisonnières",
      aide = "Les quêtes d'événement (fêtes, saisons). Attention : hors de la fête, le personnage qui les donne n'est pas là, et le « ! » ne mène à rien." },
    { cle = "bientot", libelle = "Montrer aussi les quêtes bientôt disponibles",
      aide = "Les quêtes qui demandent jusqu'à 3 niveaux de plus que toi, en gris clair." },
    { cle = "tropHaut", libelle = "Cacher les quêtes trop haut niveau",
      aide = "Les quêtes dont le niveau dépasse trop le tien (titre rouge) sont cachées. Règle l'écart juste en dessous." },
    { cle = "ecartHaut", type = "nombre", libelle = "Écart de niveau accepté", min = 0, max = 10, pas = 1, dependDe = "tropHaut",
      format = function(v) return "+" .. v .. " niveaux" end,
      aide = "Avec +4 au niveau 12, tu vois les quêtes jusqu'au niveau 16." },
    { cle = "suites", libelle = "Cacher les quêtes d'une suite pas encore débloquée",
      aide = "Une quête qui demande d'en avoir fait une autre avant est cachée tant que ce n'est pas fait. Décoché : elle est montrée en gris, avec « pas encore débloquée »." },
    { cle = "metiers", libelle = "Cacher les quêtes d'un métier que je n'ai pas",
      aide = "Une quête qui demande un métier ou un niveau de métier que tu n'as pas est cachée." },
    { titre = "Carte" },
    { cle = "taille", type = "nombre", libelle = "Taille des « ! »", min = 12, max = 32, pas = 1,
      format = function(v) return v .. " px" end,
      aide = "La taille des « ! » jaunes sur la carte." },
    { cle = "continent", libelle = "Montrer aussi sur la carte d'un continent",
      aide = "Kalimdor et les Royaumes de l'Est : beaucoup de « ! », regroupés plus largement. Coupé : seulement sur la carte d'une zone." },
    { cle = "surMinimap", libelle = "Montrer les « ! » sur la minimap",
      aide = "De petits « ! » sur la minimap pour les quêtes à prendre assez proches, avec les mêmes filtres que la carte, et les « ? » des quêtes à rendre. Survole-en un pour voir les quêtes. Pas de flèche au bord." },
    { titre = "Quêtes du journal" },
    { cle = "objectifsCarte", libelle = "Montrer les objectifs de mes quêtes sur la carte",
      aide = "Une petite icône là où se fait chaque objectif pas encore fini des quêtes de ton journal : un crâne pour les monstres à tuer, un sac pour les objets à ramasser, une main pour un objet du décor à utiliser. Survole-la pour voir la quête et où tu en es (« 3/8 »). Seulement sur la carte d'une zone." },
    { cle = "rendre", libelle = "Un « ? » là où rendre une quête finie",
      aide = "Un « ? » jaune sur la carte et sur la minimap, à l'endroit du personnage ou de l'objet à qui rendre une quête de ton journal dont tous les objectifs sont faits. Clic gauche sur la carte : une balise." },
    { cle = "rendreGris", libelle = "Aussi un « ? » gris pour les quêtes pas finies", dependDe = "rendre",
      aide = "Montre aussi, en gris, où rendre les quêtes de ton journal encore en cours." },
    { cle = "bulleMonstres", libelle = "Mes quêtes dans la bulle des monstres",
      aide = "Au survol d'un monstre (ou de ta cible), sa bulle dit quelles quêtes de ton journal en ont besoin et où tu en es (« 3/8 Foie de Goretusk »). Rien n'est répété si le jeu l'écrit déjà. Pas en donjon : le jeu y cache ces informations aux addons." },
    { titre = "Quêtes apprises" },
    { cle = "apprendre", libelle = "Retenir les quêtes que les PNJ proposent",
      aide = "Quand un PNJ te propose une quête que la base ne connaît pas (celles propres à Forever), l'addon retient l'endroit où tu te tenais et la montre ensuite sur la carte et la minimap, marquée « appris en jeu »." },
    { cle = "partager", libelle = "Partager avec mon groupe", dependDe = "apprendre",
      aide = "Envoie les quêtes apprises à ton groupe ou à ton raid, et reçoit celles que les autres joueurs de l'addon ont apprises (« appris par ton groupe »)." },
  },
  boutons = {
    { texte = "Remontrer les quêtes cachées", largeur = 210,
      aide = "Remet sur la carte les quêtes que tu as cachées d'un clic droit, pour ce personnage.",
      action = function() remontrer() end },
    { texte = "Oublier les quêtes apprises", largeur = 210,
      aide = "Efface toutes les quêtes apprises en jeu ou reçues du groupe (pour tous tes personnages). Elles seront réapprises en reparlant aux PNJ.",
      action = function() oublier() end },
  },
  astuce = "Clic gauche sur un « ! » : une balise. Clic droit : ne plus montrer ces quêtes. /qd etat dit ce que l'addon voit sur la carte ouverte.",
  auChargement = function(d)
    db = d
    if type(db.ignorees) ~= "table" then db.ignorees = {} end
    if type(db.appris) ~= "table" then db.appris = {} end
    if type(db.nomsPnj) ~= "table" then db.nomsPnj = {} end
    ns.apprises = db.appris
    accrocherBulle()
    majApprises()
    -- Le canal des messages du groupe (une inscription par session).
    sur((C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix, ns.PREFIXE)
    if not donneesPresentes() and not donneesDites then
      donneesDites = true
      dire("données absentes : le fichier Donnees.lua est vide ou manquant, l'addon ne fait rien.")
    end
  end,
  surChangement = function()
    if db then
      miniSale = true
      tickMinimapProtege() -- une option de la minimap s'applique tout de suite
      rafraichirSur()
    end
  end,
})

-- ---------------------------------------------------------------------------
-- Événements et accroches à la carte
-- ---------------------------------------------------------------------------

local crochetCarte = false -- vrai quand OnMapChanged est accroché (sinon le minuteur surveille)
local accroche = false

-- Quand la carte change de zone, les anciens « ! » partent tout de suite.
local function carteChangee()
  if not db then return end
  local carte = type(WorldMapFrame) == "table" and WorldMapFrame.GetMapID and lisible(sur(WorldMapFrame.GetMapID, WorldMapFrame))
  if carte ~= carteDessinee then cacherTout() end
  demander()
end

-- S'accrocher à la carte du monde : changement de zone, ouverture, changement de taille. La carte peut
-- être chargée après l'addon : on réessaie à l'entrée dans le monde et quand elle arrive. Chaque accroche
-- est protégée : si le jeu n'a pas la fonction, l'addon continue sans elle.
local function accrocherCarte()
  if accroche or type(WorldMapFrame) ~= "table" then return end
  accroche = true
  local function maj() pcall(carteChangee) end
  if type(hooksecurefunc) == "function" and type(WorldMapFrame.OnMapChanged) == "function" then
    crochetCarte = pcall(hooksecurefunc, WorldMapFrame, "OnMapChanged", maj)
  end
  if WorldMapFrame.HookScript then pcall(WorldMapFrame.HookScript, WorldMapFrame, "OnShow", maj) end
  local toile = WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child
  if toile and toile.HookScript then pcall(toile.HookScript, toile, "OnSizeChanged", function() pcall(demander) end) end
end
accrocherCarte()

-- Sonde : au début, on calcule la zone du joueur pour que /qd etat et le diagnostic aient quelque chose
-- à dire sans ouvrir la carte. Rien n'est affiché.
local function sonder()
  if not db or not db.actif or not donneesPresentes() then return end
  local carte = lisible(sur(C_Map and C_Map.GetBestMapForUnit, "player"))
  if type(carte) ~= "number" or genreCarte(carte) ~= "zone" then return end
  local ok, _, etat, joueur = pcall(evaluer, carte, 0.005, sonder)
  -- Sans l'état des quêtes rendues, les comptes seraient faux : on ne note rien.
  if ok and etat and joueur and joueur.etatConnu and not dernierEtat then dernierEtat = etat end
end

-- À chaque déconnexion ou /reload : ce que l'addon a vu va dans la sauvegarde, pour régler l'addon
-- en lisant le fichier sans recopier le chat.
local function noterDiagnostic()
  if not db then return end
  local e = dernierEtat
  local exclues = {}
  for k, v in pairs(e and e.exclues or {}) do exclues[k] = v end
  local titres = {}
  for i, t in ipairs(e and e.titres or {}) do if i <= 15 then titres[i] = t end end
  db.diagnostic = {
    date = date and date("%Y-%m-%d %H:%M") or "", donnees = ns.VERSION_DONNEES, connues = nbConnues(), apprises = (nbApprises()),
    orientation = orientation, ancresReconnues = orientationScore,
    carte = e and e.carte, montrees = e and e.montrees, epingles = e and e.epingles, exclues = exclues, titres = titres,
    journal = dernierEtatJournal and {
      objectifs = dernierEtatJournal.objectifs, rendre = dernierEtatJournal.rendre, gris = dernierEtatJournal.gris,
      raisonObjectifs = dernierEtatJournal.raisonObjectifs, raisonRendre = dernierEtatJournal.raisonRendre,
    },
  }
end

local ecouteur = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_LOGOUT", "QUEST_ACCEPTED", "QUEST_TURNED_IN",
                     "QUEST_REMOVED", "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED", "QUEST_DATA_LOAD_RESULT",
                     "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "CHAT_MSG_ADDON", "QUEST_LOG_UPDATE",
                     "UNIT_QUEST_LOG_CHANGED", "QUEST_PROGRESS", "QUEST_COMPLETE" }) do
  pcall(ecouteur.RegisterEvent, ecouteur, e)
end

ecouteur:SetScript("OnEvent", function(_, evenement, arg1, arg2, arg3, arg4)
  if evenement == "ADDON_LOADED" then
    if arg1 == "Blizzard_WorldMap" then accrocherCarte() end
    return
  end
  if not db then return end
  if evenement == "PLAYER_LOGOUT" then
    pcall(noterDiagnostic)
  elseif evenement == "PLAYER_ENTERING_WORLD" then
    accrocherCarte()
    apres(5, sonder)
    demander()
  elseif evenement == "QUEST_DATA_LOAD_RESULT" then
    -- Un titre vient d'arriver : la bulle ouverte le montre.
    if survol and survol.donnees and survol:IsShown() then pcall(infobulle, survol) end
    if survolMini and survolMini.mini and survolMini:IsShown() then pcall(infobulleMini, survolMini) end
  elseif evenement == "GOSSIP_SHOW" or evenement == "QUEST_GREETING" or evenement == "QUEST_DETAIL" then
    pcall(apprendreNomPnj)
    local ok, erreur = pcall(apprendreEvenement, evenement)
    if not ok then ns.derniereErreur = tostring(erreur) end
  elseif evenement == "QUEST_PROGRESS" or evenement == "QUEST_COMPLETE" then
    pcall(apprendreNomPnj) -- celui à qui on rend la quête : son nom en français pour la bulle du « ? »
  elseif evenement == "UNIT_QUEST_LOG_CHANGED" and arg1 ~= "player" then
    return -- le journal d'un autre joueur du groupe : rien à refaire
  elseif evenement == "CHAT_MSG_ADDON" then
    local ok, erreur = pcall(recevoir, arg1, arg2, arg3, arg4)
    if not ok then ns.derniereErreur = tostring(erreur) end
  elseif evenement == "QUEST_TURNED_IN" then
    -- Le jeu marque la quête rendue un peu après : on regarde une seconde fois.
    oublierJournal()
    miniSale = true
    demander()
    apres(1, function() oublierJournal(); miniSale = true; demander() end)
  else
    -- Une quête prise, abandonnée, un objectif qui avance : le journal est à relire.
    if evenement ~= "PLAYER_LEVEL_UP" and evenement ~= "SKILL_LINES_CHANGED" then oublierJournal() end
    miniSale = true -- la minimap refait sa liste de quêtes proches au prochain passage
    demander()
  end
end)

-- Sans l'accroche de la carte, un minuteur surveille la zone affichée tant que la carte est ouverte.
local derniereCarteVue
if C_Timer and C_Timer.NewTicker then
  C_Timer.NewTicker(0.5, function()
    if crochetCarte or not db or not db.actif then return end
    if type(WorldMapFrame) == "table" and WorldMapFrame.IsShown and WorldMapFrame:IsShown() then
      local carte = WorldMapFrame.GetMapID and lisible(sur(WorldMapFrame.GetMapID, WorldMapFrame))
      if carte ~= derniereCarteVue then
        derniereCarteVue = carte
        cacherTout()
        demander()
      end
    else
      derniereCarteVue = nil
    end
  end)
end

-- Les « ! » de la minimap : un minuteur de 0,2 s (sans lui, pas de minimap ; la carte du monde n'en dépend pas).
if C_Timer and C_Timer.NewTicker then
  C_Timer.NewTicker(0.2, tickMinimapProtege)
end

-- ---------------------------------------------------------------------------
-- Commandes
-- ---------------------------------------------------------------------------

-- « /qd etat » : ce que l'addon voit.
local function commandeEtat()
  if not db then return end
  if not donneesPresentes() then return dire("données absentes : le fichier Donnees.lua est vide ou manquant.") end
  dire("données : " .. tostring(ns.VERSION_DONNEES or "inconnues") .. ", " .. nbConnues() .. " quêtes connues, "
    .. #ns.DEPARTS .. " points de départ.")
  if orientation then
    dire("positions : transformation n° " .. orientation .. " (villes reconnues : " .. tostring(orientationScore) .. " sur 6).")
  else
    dire("positions : pas encore calculées" .. (orientationScore == 0 and " (aucune ville reconnue)" or "") .. ".")
  end
  local nbA, nbG = nbApprises()
  dire("quêtes apprises : " .. nbA .. (nbA > 0 and (" (dont " .. nbG .. " reçue(s) du groupe)") or "")
    .. (db.apprendre and "" or ", apprentissage coupé") .. ".")
  dire("minimap : " .. (db.surMinimap and ((miniVisibles - miniRendreVisibles) .. " « ! » proche(s) affiché(s)"
    .. (miniRendreVisibles > 0 and (" et " .. miniRendreVisibles .. " « ? »") or "")) or "« ! » coupés") .. ".")
  -- Carte ouverte : on refait une passe pour avoir son état à jour.
  if type(WorldMapFrame) == "table" and WorldMapFrame.IsShown and WorldMapFrame:IsShown() then rafraichirSur() end
  local ej = dernierEtatJournal
  if ej then
    local j = lireJournal()
    dire("journal : " .. #j.liste .. " quête(s) ; carte " .. tostring(ej.carte) .. " : " .. ej.objectifs .. " icône(s) d'objectif"
      .. (ej.raisonObjectifs and (" (" .. ej.raisonObjectifs .. ")") or "") .. ", " .. ej.rendre .. " « ? » à rendre"
      .. ((ej.gris or 0) > 0 and (" et " .. ej.gris .. " gris") or "")
      .. (ej.raisonRendre and (" (" .. ej.raisonRendre .. ")") or "") .. ".")
  end
  local e = dernierEtat
  if not e then return dire("ouvre la carte du monde pour voir ce que l'addon y montre.") end
  dire(string.format("carte %s (%s) : %d quête(s) à prendre, %d « ! ».", tostring(e.carte), nomCarte(e.carte), e.montrees, e.epingles)
    .. (e.note and (" " .. e.note .. ".") or ""))
  local liste = {}
  for raison, n in pairs(e.exclues) do liste[#liste + 1] = { raison = raison, n = n } end
  table.sort(liste, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.raison < b.raison end)
  for _, x in ipairs(liste) do
    dire("  exclues, " .. (ns.NOMS_RAISONS[x.raison] or x.raison) .. " : " .. x.n)
  end
end

local function commande(texte)
  local c = strtrim(texte or ""):lower()
  if c == "" or c == "options" or c == "reglages" then
    ns.reglages.ouvrir()
  elseif c == "etat" or c == "état" then
    commandeEtat()
  elseif c == "on" or c == "off" then
    if db and (c == "on") ~= (db.actif and true or false) then ns.reglages.basculer() end
  elseif c == "aide" or c == "help" or c == "?" then
    dire("/qd : les réglages     /qd etat : ce que l'addon voit sur la carte ouverte")
    dire("/qd on, /qd off : activer ou couper     Sur la carte : clic gauche = balise, clic droit = cacher ces quêtes")
    dire("/qd objectifscarte, /qd rendre, /qd rendregris, /qd bullemonstres : les options des quêtes du journal")
  elseif not ns.reglages.basculerOption(c) then
    dire("commande inconnue. /qd aide donne la liste.")
  end
end

SLASH_QUETESDISPO1 = "/qd"
SLASH_QUETESDISPO2 = "/quetesdispo"
SlashCmdList.QUETESDISPO = commande
