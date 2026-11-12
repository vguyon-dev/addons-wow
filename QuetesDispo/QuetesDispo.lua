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

local function cacherTout()
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
    return
  end
  local liste, etat, joueur = evaluer(carte, genre == "continent" and 0.015 or 0.005, demander)
  if not liste then return end -- le calcul continue, il rappellera
  if not joueur.etatConnu then
    cacherTout()
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
  remplirBulle(e.quetes, false)
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
  miniVisibles, miniSig = 0, nil
end

-- Les quêtes à prendre à moins de MINI_PORTEE mètres du joueur, avec les mêmes filtres que la carte.
local function recalculerProches(pos, rayon)
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
  local demi, n = largeur / 2, 0
  for _, e in ipairs(miniProches) do
    local px, py = ns.placementMinimap(e.x - pos.x, e.y - pos.y, rayon, demi, rotation, MINI_TAILLE / 2)
    if px then
      n = n + 1
      local p = prendrePastille(n)
      if p.mini ~= e then
        p.mini = e
        p.image:SetDesaturated(e.grise and true or false)
        p:SetAlpha(e.grise and 0.6 or 1)
        p.nombre:SetText(#e.quetes > 1 and tostring(#e.quetes) or "")
      end
      p:ClearAllPoints()
      p:SetPoint("CENTER", Minimap, "CENTER", px, py)
      p:Show()
    end
  end
  for i = n + 1, #pastilles do pastilles[i]:Hide() end
  miniVisibles = n
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
      aide = "De petits « ! » sur la minimap pour les quêtes à prendre assez proches, avec les mêmes filtres que la carte. Survole-en un pour voir les quêtes. Pas de flèche au bord." },
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
    ns.apprises = db.appris
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
  }
end

local ecouteur = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_LOGOUT", "QUEST_ACCEPTED", "QUEST_TURNED_IN",
                     "QUEST_REMOVED", "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED", "QUEST_DATA_LOAD_RESULT",
                     "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "CHAT_MSG_ADDON" }) do
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
    local ok, erreur = pcall(apprendreEvenement, evenement)
    if not ok then ns.derniereErreur = tostring(erreur) end
  elseif evenement == "CHAT_MSG_ADDON" then
    local ok, erreur = pcall(recevoir, arg1, arg2, arg3, arg4)
    if not ok then ns.derniereErreur = tostring(erreur) end
  elseif evenement == "QUEST_TURNED_IN" then
    -- Le jeu marque la quête rendue un peu après : on regarde une seconde fois.
    miniSale = true
    demander()
    apres(1, function() miniSale = true; demander() end)
  else
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
  dire("minimap : " .. (db.surMinimap and (miniVisibles .. " « ! » proche(s) affiché(s)") or "« ! » coupés") .. ".")
  -- Carte ouverte : on refait une passe pour avoir son état à jour.
  if type(WorldMapFrame) == "table" and WorldMapFrame.IsShown and WorldMapFrame:IsShown() then rafraichirSur() end
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
  elseif not ns.reglages.basculerOption(c) then
    dire("commande inconnue. /qd aide donne la liste.")
  end
end

SLASH_QUETESDISPO1 = "/qd"
SLASH_QUETESDISPO2 = "/quetesdispo"
SlashCmdList.QUETESDISPO = commande
