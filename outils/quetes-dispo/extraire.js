// Extraction des quêtes de Classic depuis la base CMaNGOS classic-db.
//
// Usage :  node outils/quetes-dispo/extraire.js <chemin du fichier .sql>
// Résultat : QuetesDispo/Donnees.lua (fichier généré, ne pas modifier à la main).
// Il contient les quêtes et où les prendre (QUETES, DEPARTS), et pour les quêtes du journal
// où se font leurs objectifs et où les rendre (OBJECTIFS, FINS, NOMS_FINS).
//
// Le fichier .sql pèse plus de 70 Mo : on le lit ligne par ligne, jamais en un
// seul bloc. Pour chaque table utile, on lit d'abord son CREATE TABLE afin de
// connaître l'ORDRE DES COLONNES (on ne suppose jamais un rang), puis on lit
// ses INSERT.
//
// La base est une donnée non fiable : on la lit, on n'exécute rien qui en vienne.
//
// Sources : CMaNGOS classic-db, licence GPL-3.0 (voir QuetesDispo/LICENCE.md).

"use strict";

const fs = require("fs");
const path = require("path");
const readline = require("readline");

// ---------------------------------------------------------------------------
// Réglages
// ---------------------------------------------------------------------------

// Colonnes à garder pour chaque table (les autres sont lues puis jetées).
const COLONNES_UTILES = {
  quest_template: [
    "entry", "Method", "ZoneOrSort", "MinLevel", "QuestLevel", "Type",
    "RequiredClasses", "RequiredRaces", "RequiredSkill", "RequiredSkillValue",
    "PrevQuestId", "NextQuestId", "NextQuestInChain", "ExclusiveGroup", "SpecialFlags", "QuestFlags",
    "RequiredMinRepFaction", "Title",
    // Les objectifs (pour les icônes d'objectifs et la bulle des monstres) : 4 cases de chaque.
    ...[1, 2, 3, 4].flatMap((i) => [
      "ReqItemId" + i, "ReqItemCount" + i, "ReqSourceId" + i, "ReqCreatureOrGOId" + i, "ReqCreatureOrGOCount" + i,
    ]),
    // Le point d'une quête d'exploration (zone à découvrir), quand la base le donne.
    "PointMapId", "PointX", "PointY",
  ],
  creature_questrelation: ["id", "quest"],
  gameobject_questrelation: ["id", "quest"],
  creature: ["guid", "id", "map", "position_x", "position_y"],
  gameobject: ["guid", "id", "map", "position_x", "position_y"],
  // Les fêtes et événements : qui n'apparaît que pendant un événement, et quelles quêtes en dépendent.
  game_event_creature: ["guid", "event"],
  game_event_gameobject: ["guid", "event"],
  game_event_quest: ["quest", "event"],
  creature_template: ["Entry", "Name", "LootId", "KillCredit1", "KillCredit2"],
  gameobject_template: ["entry", "name", "type", "data1"],
  // Où rendre une quête.
  creature_involvedrelation: ["id", "quest"],
  gameobject_involvedrelation: ["id", "quest"],
  // Qui fait tomber quel objet (mincountOrRef négatif : renvoi vers une table commune, ignoré).
  creature_loot_template: ["entry", "item", "ChanceOrQuestChance", "groupid", "mincountOrRef"],
  gameobject_loot_template: ["entry", "item", "ChanceOrQuestChance", "groupid", "mincountOrRef"],
  // Une apparition au genre tiré au hasard (colonne id à 0 dans creature ou gameobject) : ses genres possibles.
  creature_spawn_entry: ["guid", "entry"],
  gameobject_spawn_entry: ["guid", "entry"],
};

// Cartes gardées : 0 = Royaumes de l'Est, 1 = Kalimdor. Les autres sont des instances.
const CONTINENTS = new Set([0, 1]);

// Un donneur qui apparaît à plusieurs endroits : au plus 3 points.
const POINTS_MAX = 3;
// Deux apparitions plus proches que cela (en mètres) comptent pour une seule.
const DISTANCE_FUSION = 5;

// Titres qui marquent une quête de test ou abandonnée.
const TITRES_ECARTES = [
  /^\s*$/,
  /^\s*<UNUSED>/i,
  /^\s*<NYI>/i,
  /^\s*<TXT>/i,
  /^\s*\[?DEPRECATED\]?/i,
  /^\s*test\s*$/i, // « Test » seul : « Test of Faith » et « Testing the Vessel » sont de vraies quêtes
  /\[DEPRECATED\]/i,
  /^\s*REUSE\b/i,
  /^\s*<DND>/i,
];

// Colonne Method de quest_template : 0 = fin automatique, 1 = désactivée, 2 = active.
const METHODE_DESACTIVEE = 1;

// Type de quête (CMaNGOS Classic) vers les drapeaux du contrat.
//   1 groupe, 41 JcJ, 62 raid, 81 donjon, 82 événement mondial,
//   83 légendaire, 84 escorte.
const DRAPEAU_GROUPE_OU_ELITE = 2;
const DRAPEAU_DONJON = 4;
const DRAPEAU_RAID = 8;
const DRAPEAU_JCJ = 16;
const DRAPEAU_EVENEMENT = 32;
const DRAPEAU_REPETABLE = 1;

const DRAPEAU_PAR_TYPE = {
  1: DRAPEAU_GROUPE_OU_ELITE,
  41: DRAPEAU_JCJ,
  62: DRAPEAU_RAID,
  81: DRAPEAU_DONJON,
  82: DRAPEAU_EVENEMENT,
  83: DRAPEAU_GROUPE_OU_ELITE, // légendaire : de groupe
  84: 0, // escorte : se fait seul
};

// Les « catégories » (ZoneOrSort négatif) qui désignent une quête saisonnière.
// -22 saisonnier, -284 spécial (Semaine des enfants...), -364 Foire de Sombrelune,
// -365 effort de guerre d'Ahn'Qiraj (« The Alliance Needs Copper Bars! »), -366 Fête lunaire,
// -367 insignes de l'invasion du Fléau (« One Commendation Signet »), -368 invasion du Fléau,
// -369 Solstice d'été (vérifié sur les titres de la base).
const CATEGORIES_SAISONNIERES = new Set([-22, -284, -364, -365, -366, -367, -368, -369]);

// ---------------------------------------------------------------------------
// Lecture du SQL
// ---------------------------------------------------------------------------

// Lit une chaîne SQL entre apostrophes, à partir de la position de l'apostrophe
// ouvrante. Gère \' \\ \n et le doublement ''. Renvoie [texte, position après].
function lireChaine(s, debut) {
  let i = debut + 1;
  let sortie = "";
  const re = /['\\]/g;
  for (;;) {
    re.lastIndex = i;
    const m = re.exec(s);
    if (!m) throw new Error("chaîne SQL non terminée");
    sortie += s.slice(i, m.index);
    if (m[0] === "'") {
      if (s[m.index + 1] === "'") {
        sortie += "'";
        i = m.index + 2;
        continue;
      }
      return [sortie, m.index + 1];
    }
    // Antislash : le caractère suivant est échappé.
    const c = s[m.index + 1];
    if (c === "n") sortie += "\n";
    else if (c === "r") sortie += "\r";
    else if (c === "t") sortie += "\t";
    else if (c === "0") sortie += "\0";
    else sortie += c; // \' \\ \" et le reste : le caractère tel quel
    i = m.index + 2;
  }
}

// Lit les lignes de valeurs « (a,b,'c'),(d,e,NULL);» d'un INSERT.
// Appelle rappel(tableauDeValeurs) pour chaque ligne.
function lireValeurs(s, debut, rappel) {
  let i = debut;
  const n = s.length;
  while (i < n) {
    // On cherche l'ouverture d'un tuple.
    while (i < n && s[i] !== "(") {
      if (s[i] === ";") return;
      i++;
    }
    if (i >= n) return;
    i++; // après la parenthèse ouvrante
    const valeurs = [];
    for (;;) {
      while (s[i] === " ") i++;
      let v;
      if (s[i] === "'") {
        const r = lireChaine(s, i);
        v = r[0];
        i = r[1];
      } else {
        let j = i;
        while (j < n && s[j] !== "," && s[j] !== ")") j++;
        const brut = s.slice(i, j).trim();
        v = brut.toUpperCase() === "NULL" ? null : Number(brut);
        i = j;
      }
      valeurs.push(v);
      if (s[i] === ",") {
        i++;
        continue;
      }
      if (s[i] === ")") {
        i++;
        break;
      }
      throw new Error("tuple SQL mal formé près de la position " + i);
    }
    rappel(valeurs);
  }
}

// Parcourt le fichier et renvoie { table: [objets] } pour les tables utiles.
// Pour creature et gameobject, on écarte tout de suite les cartes qui ne sont
// pas des continents : le fichier en contient des centaines de milliers.
async function lireBase(chemin) {
  const colonnesDeTable = {}; // table -> noms de colonnes dans l'ordre du CREATE TABLE
  const resultat = {};
  for (const t of Object.keys(COLONNES_UTILES)) resultat[t] = [];

  const flux = fs.createReadStream(chemin, { encoding: "utf8" });
  const lignes = readline.createInterface({ input: flux, crlfDelay: Infinity });

  let tableEnCours = null; // table dont on lit le CREATE TABLE
  const reCreate = /^CREATE TABLE `([^`]+)`/;
  const reColonne = /^\s+`([^`]+)`\s/;
  const reInsert = /^INSERT INTO `([^`]+)` VALUES /;

  for await (const ligne of lignes) {
    if (tableEnCours !== null) {
      const mc = reColonne.exec(ligne);
      if (mc) {
        colonnesDeTable[tableEnCours].push(mc[1]);
        continue;
      }
      if (ligne.startsWith(")")) {
        tableEnCours = null;
        continue;
      }
      continue; // clés et index : sans intérêt
    }
    if (ligne.startsWith("CREATE TABLE")) {
      const m = reCreate.exec(ligne);
      if (m && COLONNES_UTILES[m[1]]) {
        tableEnCours = m[1];
        colonnesDeTable[tableEnCours] = [];
      }
      continue;
    }
    if (ligne.startsWith("INSERT INTO")) {
      const m = reInsert.exec(ligne);
      if (!m || !COLONNES_UTILES[m[1]]) continue;
      const table = m[1];
      const noms = colonnesDeTable[table];
      if (!noms) throw new Error("INSERT avant le CREATE TABLE de " + table);
      // Rang de chaque colonne utile, d'après le CREATE TABLE.
      const rangs = COLONNES_UTILES[table].map((nom) => {
        const r = noms.indexOf(nom);
        if (r < 0) throw new Error("colonne absente de " + table + " : " + nom);
        return r;
      });
      const cible = resultat[table];
      const rangMap = noms.indexOf("map");
      lireValeurs(ligne, m[0].length, (v) => {
        if ((table === "creature" || table === "gameobject") && !CONTINENTS.has(v[rangMap])) return;
        const o = {};
        for (let k = 0; k < rangs.length; k++) o[COLONNES_UTILES[table][k]] = v[rangs[k]];
        cible.push(o);
      });
    }
  }
  return resultat;
}

// ---------------------------------------------------------------------------
// Construction des données
// ---------------------------------------------------------------------------

function distance(a, b) {
  return Math.hypot(a.x - b.x, a.y - b.y);
}

// Parmi des points d'un même continent, garde au plus POINTS_MAX points,
// les plus éloignés les uns des autres, après fusion des points proches.
function choisirPoints(points) {
  // 1. Fusion des apparitions à moins de DISTANCE_FUSION mètres.
  const gardes = [];
  for (const p of points) {
    if (!gardes.some((g) => distance(g, p) < DISTANCE_FUSION)) gardes.push(p);
  }
  if (gardes.length <= POINTS_MAX) return gardes;
  // 2. Le couple le plus éloigné, puis le point qui s'éloigne le plus des deux.
  let meilleur = [0, 1];
  let dmax = -1;
  for (let a = 0; a < gardes.length; a++) {
    for (let b = a + 1; b < gardes.length; b++) {
      const d = distance(gardes[a], gardes[b]);
      if (d > dmax) {
        dmax = d;
        meilleur = [a, b];
      }
    }
  }
  const choisis = [gardes[meilleur[0]], gardes[meilleur[1]]];
  while (choisis.length < POINTS_MAX) {
    let idx = -1;
    let score = -1;
    for (let k = 0; k < gardes.length; k++) {
      if (choisis.includes(gardes[k])) continue;
      const d = Math.min(...choisis.map((c) => distance(c, gardes[k])));
      if (d > score) {
        score = d;
        idx = k;
      }
    }
    choisis.push(gardes[idx]);
  }
  return choisis;
}

function titreEcarte(titre) {
  if (titre === null || titre === undefined) return true;
  return TITRES_ECARTES.some((re) => re.test(titre));
}

// Quêtes liées à un événement d'après les tables game_event_* (remplie dans la fonction principale).
const quetesEvenement = new Set();

function drapeauxDe(q) {
  let d = DRAPEAU_PAR_TYPE[q.Type] || 0;
  if ((q.SpecialFlags & 1) !== 0) d |= DRAPEAU_REPETABLE;
  if (CATEGORIES_SAISONNIERES.has(q.ZoneOrSort) || quetesEvenement.has(q.entry)) d |= DRAPEAU_EVENEMENT;
  return d;
}

function construire(base) {
  // Quêtes valides d'après leur seule fiche.
  const fiches = new Map();
  for (const q of base.quest_template) {
    if (q.Method === METHODE_DESACTIVEE) continue;
    if (titreEcarte(q.Title)) continue;
    fiches.set(q.entry, q);
  }

  // Les quêtes à rendre avant, côté « suivante » : CMaNGOS ajoute aussi la quête NextQuestId d'une quête
  // comme prérequis de celle-ci (ObjectMgr, chargement des quêtes), avec le signe de NextQuestId
  // (négatif : la quête source doit être EN COURS). Une quête a donc une liste de prérequis,
  // et une seule suffit (ou-logique). On garde ici ceux que PrevQuestId ne dit pas déjà.
  // Une quête source écartée (désactivée, de test) ne compte pas : elle ne se prendrait jamais.
  const autres = new Map(); // numéro -> Set de numéros signés
  for (const q of base.quest_template) {
    if (!q.NextQuestId || !fiches.has(q.entry)) continue;
    const cible = Math.abs(q.NextQuestId);
    const fc = fiches.get(cible);
    if (!fc || cible === q.entry) continue;
    const signe = q.NextQuestId < 0 ? -q.entry : q.entry;
    if (signe === fc.PrevQuestId) continue;
    if (!autres.has(cible)) autres.set(cible, new Set());
    autres.get(cible).add(signe);
  }

  // NextQuestInChain : « la quête proposée juste après celle-ci ». Ce n'est pas un verrou dans CMaNGOS,
  // mais en jeu la suivante d'une suite ne se prend pas avant la précédente. On l'ajoute donc aux quêtes
  // qui ouvrent la suivante (une seule suffit toujours), pour ne pas montrer une suite pas commencée.
  for (const q of base.quest_template) {
    const cible = q.NextQuestInChain;
    if (!cible || cible <= 0 || !fiches.has(q.entry)) continue;
    const fc = fiches.get(cible);
    if (!fc || cible === q.entry) continue;
    if (q.entry === fc.PrevQuestId) continue;
    if (!autres.has(cible)) autres.set(cible, new Set());
    autres.get(cible).add(q.entry);
  }

  // Donneurs : genre 1 = PNJ, genre 2 = objet du décor.
  // donneurs.get("genre:id") = ensemble de numéros de quêtes.
  const donneurs = new Map();
  function ajouterRelations(liste, genre) {
    for (const r of liste) {
      if (!fiches.has(r.quest)) continue;
      const cle = genre + ":" + r.id;
      if (!donneurs.has(cle)) donneurs.set(cle, new Set());
      donneurs.get(cle).add(r.quest);
    }
  }
  ajouterRelations(base.creature_questrelation, 1);
  ajouterRelations(base.gameobject_questrelation, 2);

  // Un personnage ou un objet lié à un événement (numéro d'événement > 0) n'est là que pendant la fête.
  // Hors fête, un « ! » à cet endroit ne mènerait à rien (retour de jeu du 11/11) : ces apparitions sont
  // mises à part. Un donneur qui n'a QUE des apparitions d'événement garde ses points, mais toutes ses
  // quêtes sont marquées saisonnières (cachées tant que l'option n'est pas cochée).
  const guidsEvenement = { 1: new Set(), 2: new Set() };
  for (const e of base.game_event_creature || []) if (e.event > 0) guidsEvenement[1].add(e.guid);
  for (const e of base.game_event_gameobject || []) if (e.event > 0) guidsEvenement[2].add(e.guid);
  for (const e of base.game_event_quest || []) if (e.event > 0) quetesEvenement.add(e.quest);

  // Apparitions des donneurs, par continent.
  const apparitions = new Map(); // "genre:id" -> Map(continent -> [{x,y}])
  const apparitionsEvenement = new Map();
  function ajouterApparitions(liste, genre) {
    for (const s of liste) {
      const cle = genre + ":" + s.id;
      if (!donneurs.has(cle)) continue;
      const cible = guidsEvenement[genre].has(s.guid) ? apparitionsEvenement : apparitions;
      if (!cible.has(cle)) cible.set(cle, new Map());
      const parCont = cible.get(cle);
      if (!parCont.has(s.map)) parCont.set(s.map, []);
      parCont.get(s.map).push({ x: s.position_x, y: s.position_y });
    }
  }
  ajouterApparitions(base.creature, 1);
  ajouterApparitions(base.gameobject, 2);
  let donneursEvenement = 0;
  for (const [cle, parCont] of apparitionsEvenement) {
    if (apparitions.has(cle)) continue; // il existe aussi hors fête : on ne garde que ses points permanents
    apparitions.set(cle, parCont);
    donneursEvenement++;
    for (const n of donneurs.get(cle)) quetesEvenement.add(n);
  }
  console.log("Donneurs présents seulement pendant un événement : " + donneursEvenement +
    " ; quêtes marquées saisonnières par les événements : " + quetesEvenement.size);

  // Points de départ.
  const departs = [];
  const quetesAvecPoint = new Set();
  for (const [cle, quetes] of donneurs) {
    const parCont = apparitions.get(cle);
    if (!parCont) continue; // donneur sans apparition sur un continent
    const genre = Number(cle.split(":")[0]);
    const liste = Array.from(quetes).sort((a, b) => a - b);
    for (const [continent, pts] of parCont) {
      for (const p of choisirPoints(pts)) {
        departs.push({
          continent,
          x: Math.round(p.x * 10) / 10,
          y: Math.round(p.y * 10) / 10,
          genre,
          quetes: liste,
        });
      }
    }
    for (const n of liste) quetesAvecPoint.add(n);
  }
  departs.sort(
    (a, b) =>
      a.continent - b.continent ||
      a.x - b.x ||
      a.y - b.y ||
      a.genre - b.genre ||
      a.quetes[0] - b.quetes[0]
  );

  // Quêtes gardées : celles qui ont au moins un point.
  const quetes = [];
  for (const n of Array.from(quetesAvecPoint).sort((a, b) => a - b)) {
    const q = fiches.get(n);
    quetes.push({
      numero: n,
      niveau: q.QuestLevel,
      niveauMin: q.MinLevel,
      races: q.RequiredRaces,
      classes: q.RequiredClasses,
      avant: q.PrevQuestId,
      groupeExclusif: q.ExclusiveGroup,
      drapeaux: drapeauxDe(q),
      autres: Array.from(autres.get(n) || []).sort((a, b) => Math.abs(a) - Math.abs(b) || a - b),
      reputation: q.RequiredMinRepFaction || 0,
      metier: q.RequiredSkill,
      niveauMetier: q.RequiredSkillValue,
      titre: q.Title,
    });
  }
  const journal = construireJournal(base, new Set(quetes.map((q) => q.numero)));
  return { quetes, departs, journal };
}

// ---------------------------------------------------------------------------
// Les quêtes du journal : où se font les objectifs, où rendre la quête
// ---------------------------------------------------------------------------

// Un objet que plus de tant de genres de monstres différents font tomber est trop commun (tissu, viande...) :
// pas d'icône pour lui, et pas de ligne dans la bulle de ces monstres. Un objet qui ne tombe que pour une quête
// (taux négatif dans la base, comme les yeux de murloc) a droit à plus de sources : il est fait pour ça.
const SOURCES_MAX = 20;
const SOURCES_MAX_QUETE = 50;
// Taux de chute (en %, signe ignoré : négatif = chute réservée aux quêtes) en dessous duquel un monstre ne compte pas.
const CHANCE_MIN = 1;
// Au plus tant de groupes d'apparitions par objectif et par continent.
const GROUPES_MAX = 5;
// Rayon de départ du regroupement (mètres), doublé tant qu'il reste trop de groupes, jusqu'au maximum.
const RAYON_DEPART = 100;
const RAYON_MAX = 1600;
// Types d'objets du décor qui contiennent un butin (data1 = numéro du butin) : 3 coffre, 25 banc de poissons.
const TYPES_GO_BUTIN = new Set([3, 25]);
// Genres d'objectif, dans le fichier : 1 monstre à tuer, 2 objet à ramasser, 3 objet du décor à utiliser.
const OBJ_TUER = 1;
const OBJ_OBJET = 2;
const OBJ_DECOR = 3;

// Regroupe des apparitions { x, y } d'un même continent. Chaque groupe est représenté par l'apparition la plus
// proche de son centre (jamais un point au milieu d'un lac entre deux camps). Rend [{ x, y, n }], du plus gros
// groupe au plus petit, au plus GROUPES_MAX.
function grouperSurContinent(points) {
  let rayon = RAYON_DEPART;
  let groupes;
  for (;;) {
    groupes = [];
    const cellules = new Map();
    for (const p of points) {
      const ci = Math.floor(p.x / rayon);
      const cj = Math.floor(p.y / rayon);
      let trouve = null;
      for (let di = -1; di <= 1 && !trouve; di++) {
        for (let dj = -1; dj <= 1 && !trouve; dj++) {
          for (const g of cellules.get(ci + di + ":" + (cj + dj)) || []) {
            if (Math.hypot(g.cx - p.x, g.cy - p.y) <= rayon) {
              trouve = g;
              break;
            }
          }
        }
      }
      if (!trouve) {
        trouve = { cx: p.x, cy: p.y, points: [] };
        groupes.push(trouve);
        const cle = ci + ":" + cj;
        if (!cellules.has(cle)) cellules.set(cle, []);
        cellules.get(cle).push(trouve);
      }
      trouve.points.push(p);
      const n = trouve.points.length;
      trouve.cx += (p.x - trouve.cx) / n;
      trouve.cy += (p.y - trouve.cy) / n;
    }
    if (groupes.length <= GROUPES_MAX || rayon >= RAYON_MAX) break;
    rayon *= 2;
  }
  const sortie = groupes.map((g) => {
    let meilleur = g.points[0];
    let dmin = Infinity;
    for (const p of g.points) {
      const d = Math.hypot(p.x - g.cx, p.y - g.cy);
      if (d < dmin) {
        dmin = d;
        meilleur = p;
      }
    }
    return { x: Math.round(meilleur.x), y: Math.round(meilleur.y), n: g.points.length };
  });
  sortie.sort((a, b) => b.n - a.n || a.x - b.x || a.y - b.y);
  return sortie.slice(0, GROUPES_MAX);
}

// Apparitions [{ map, x, y }] de plusieurs continents -> liste plate [continent, x, y, continent, x, y, ...].
function positionsGroupees(apparitions) {
  const parCont = new Map();
  for (const a of apparitions) {
    if (!parCont.has(a.map)) parCont.set(a.map, []);
    parCont.get(a.map).push(a);
  }
  const plat = [];
  for (const cont of Array.from(parCont.keys()).sort((a, b) => a - b)) {
    for (const g of grouperSurContinent(parCont.get(cont))) plat.push(cont, g.x, g.y);
  }
  return plat;
}

// quetesGardees : Set des numéros de quêtes de ns.QUETES. Rend { objectifs: Map(numéro -> [objectif]), fins, noms, stats }.
// Un objectif : { genre, besoin, positions (liste plate), monstres (numéros de créatures, pour la bulle) }.
function construireJournal(base, quetesGardees) {
  const stats = { objectifs: 0, avecPositions: 0, sansPosition: 0, objetsCommuns: 0, fins: 0, quetesSansFin: 0 };

  // Apparitions par genre de créature et d'objet du décor (déjà réduites aux continents par lireBase).
  // Une apparition dont le genre est tiré au hasard (id 0) compte pour chacun de ses genres possibles.
  function indexer(liste, entrees) {
    const parGuid = new Map();
    for (const e of entrees || []) {
      if (!parGuid.has(e.guid)) parGuid.set(e.guid, []);
      parGuid.get(e.guid).push(e.entry);
    }
    const index = new Map();
    for (const s of liste) {
      const genres = s.id ? [s.id] : parGuid.get(s.guid) || [];
      for (const id of genres) {
        if (!index.has(id)) index.set(id, []);
        index.get(id).push({ map: s.map, x: s.position_x, y: s.position_y, guid: s.guid });
      }
    }
    return index;
  }
  const spawnsCreature = indexer(base.creature, base.creature_spawn_entry);
  const spawnsObjet = indexer(base.gameobject, base.gameobject_spawn_entry);

  // Les créatures qui comptent pour une autre (KillCredit) : tuer l'une fait avancer l'objectif de l'autre.
  const credits = new Map(); // cible -> [créatures]
  const nomsCreature = new Map();
  const butinCreature = new Map(); // numéro de butin -> [créatures]
  for (const c of base.creature_template) {
    nomsCreature.set(c.Entry, c.Name);
    for (const k of [c.KillCredit1, c.KillCredit2]) {
      if (k && k !== c.Entry) {
        if (!credits.has(k)) credits.set(k, []);
        credits.get(k).push(c.Entry);
      }
    }
    if (c.LootId) {
      if (!butinCreature.has(c.LootId)) butinCreature.set(c.LootId, []);
      butinCreature.get(c.LootId).push(c.Entry);
    }
  }
  const nomsObjet = new Map();
  const butinObjet = new Map(); // numéro de butin -> [objets du décor]
  for (const g of base.gameobject_template) {
    nomsObjet.set(g.entry, g.name);
    if (TYPES_GO_BUTIN.has(g.type) && g.data1 > 0) {
      if (!butinObjet.has(g.data1)) butinObjet.set(g.data1, []);
      butinObjet.get(g.data1).push(g.entry);
    }
  }

  // Les objets demandés par les quêtes gardées, puis qui les fait tomber.
  const fichesQuetes = new Map();
  const objetsVoulus = new Set();
  for (const q of base.quest_template) {
    if (!quetesGardees.has(q.entry)) continue;
    fichesQuetes.set(q.entry, q);
    for (let i = 1; i <= 4; i++) if (q["ReqItemId" + i] > 0) objetsVoulus.add(q["ReqItemId" + i]);
  }
  // Rend Map(objet -> { quete: Set, autres: Set }) : les sources où l'objet ne tombe que pour une quête, et les autres.
  function sourcesDe(table, parButin) {
    const sources = new Map();
    for (const r of table) {
      if (!objetsVoulus.has(r.item) || r.mincountOrRef < 0) continue;
      const chance = Math.abs(r.ChanceOrQuestChance);
      // Taux 0 dans un groupe : chance égale entre les objets du groupe, donc gardé.
      if (chance < CHANCE_MIN && !(chance === 0 && r.groupid > 0)) continue;
      if (!sources.has(r.item)) sources.set(r.item, { quete: new Set(), autres: new Set() });
      const s = sources.get(r.item);
      for (const e of parButin.get(r.entry) || []) (r.ChanceOrQuestChance < 0 ? s.quete : s.autres).add(e);
    }
    return sources;
  }
  // Les sources retenues pour un objet : celles « pour une quête » s'il y en a, sinon les autres ; aucune s'il y en a trop.
  function sourcesRetenues(s) {
    if (!s) return { liste: [], commun: false };
    const quete = s.quete.size > 0;
    const ensemble = quete ? s.quete : s.autres;
    if (ensemble.size > (quete ? SOURCES_MAX_QUETE : SOURCES_MAX)) return { liste: [], commun: true };
    return { liste: Array.from(ensemble).sort((a, b) => a - b), commun: false };
  }
  const sourcesMonstres = sourcesDe(base.creature_loot_template, butinCreature);
  const sourcesObjets = sourcesDe(base.gameobject_loot_template, butinObjet);

  const objectifs = new Map();
  for (const n of Array.from(quetesGardees).sort((a, b) => a - b)) {
    const q = fichesQuetes.get(n);
    if (!q) continue;
    const liste = [];
    // Monstres à tuer et objets du décor à utiliser (cases 1 à 4), puis objets à ramasser (cases 1 à 4).
    for (let i = 1; i <= 4; i++) {
      const id = q["ReqCreatureOrGOId" + i];
      const besoin = q["ReqCreatureOrGOCount" + i] || 0;
      if (id > 0) {
        const monstres = Array.from(new Set([id, ...(credits.get(id) || [])])).sort((a, b) => a - b);
        const app = [];
        for (const m of monstres) app.push(...(spawnsCreature.get(m) || []));
        liste.push({ genre: OBJ_TUER, besoin, positions: positionsGroupees(app), monstres });
      } else if (id < 0) {
        liste.push({ genre: OBJ_DECOR, besoin, positions: positionsGroupees(spawnsObjet.get(-id) || []), monstres: [] });
      }
    }
    for (let i = 1; i <= 4; i++) {
      const objet = q["ReqItemId" + i];
      if (!(objet > 0)) continue;
      const besoin = q["ReqItemCount" + i] || 0;
      const sm = sourcesRetenues(sourcesMonstres.get(objet));
      const monstres = sm.liste;
      const decor = sourcesRetenues(sourcesObjets.get(objet)).liste;
      if (sm.commun) stats.objetsCommuns++;
      const app = [];
      for (const m of monstres) app.push(...(spawnsCreature.get(m) || []));
      for (const g of decor) app.push(...(spawnsObjet.get(g) || []));
      liste.push({ genre: OBJ_OBJET, besoin, positions: positionsGroupees(app), monstres });
    }
    if (liste.length === 0) continue;
    for (const o of liste) {
      stats.objectifs++;
      if (o.positions.length > 0) stats.avecPositions++;
      else stats.sansPosition++;
    }
    objectifs.set(n, liste);
  }

  // Où rendre : PNJ (genre 1) et objets du décor (genre 2), au plus 3 points par continent comme les départs.
  // Les apparitions liées à une fête ne servent que si le PNJ n'existe pas hors fête.
  const guidsEvenement = { 1: new Set(), 2: new Set() };
  for (const e of base.game_event_creature || []) if (e.event > 0) guidsEvenement[1].add(e.guid);
  for (const e of base.game_event_gameobject || []) if (e.event > 0) guidsEvenement[2].add(e.guid);
  const rendeurs = new Map(); // "genre:id" -> Set de quêtes
  for (const [liste, genre] of [[base.creature_involvedrelation, 1], [base.gameobject_involvedrelation, 2]]) {
    for (const r of liste) {
      if (!quetesGardees.has(r.quest)) continue;
      const cle = genre + ":" + r.id;
      if (!rendeurs.has(cle)) rendeurs.set(cle, new Set());
      rendeurs.get(cle).add(r.quest);
    }
  }
  const fins = [];
  const noms = new Map(); // numéro (négatif pour un objet du décor) -> nom anglais
  const quetesAvecFin = new Set();
  for (const [cle, quetes] of rendeurs) {
    const [genre, id] = cle.split(":").map(Number);
    const toutes = (genre === 1 ? spawnsCreature : spawnsObjet).get(id) || [];
    const permanentes = toutes.filter((s) => !guidsEvenement[genre].has(s.guid));
    const app = permanentes.length > 0 ? permanentes : toutes;
    if (app.length === 0) continue;
    const listeQuetes = Array.from(quetes).sort((a, b) => a - b);
    const parCont = new Map();
    for (const s of app) {
      if (!parCont.has(s.map)) parCont.set(s.map, []);
      parCont.get(s.map).push(s);
    }
    for (const [continent, pts] of parCont) {
      for (const p of choisirPoints(pts)) {
        fins.push({
          continent, x: Math.round(p.x * 10) / 10, y: Math.round(p.y * 10) / 10, genre, id, quetes: listeQuetes,
        });
      }
    }
    const nom = genre === 1 ? nomsCreature.get(id) : nomsObjet.get(id);
    if (nom) noms.set(genre === 1 ? id : -id, nom);
    for (const n of listeQuetes) quetesAvecFin.add(n);
  }
  fins.sort((a, b) => a.continent - b.continent || a.x - b.x || a.y - b.y || a.genre - b.genre || a.id - b.id);
  stats.fins = fins.length;
  for (const n of quetesGardees) if (!quetesAvecFin.has(n)) stats.quetesSansFin++;
  return { objectifs, fins, noms, stats };
}

// ---------------------------------------------------------------------------
// Écriture du fichier Lua
// ---------------------------------------------------------------------------

function chaineLua(s) {
  // Titres en anglais : on échappe ce qui pourrait casser la chaîne Lua.
  return (
    '"' +
    s
      .replace(/\\/g, "\\\\")
      .replace(/"/g, '\\"')
      .replace(/\r/g, "")
      .replace(/\n/g, " ")
      .replace(/[\x00-\x1f]/g, " ") +
    '"'
  );
}

function nombreLua(n) {
  // Les coordonnées sont arrondies à 0,1 : on évite les « -10508.099999 ».
  return String(Math.round(n * 10) / 10);
}

function ecrireLua(sortie, nomSource, donnees) {
  const date = new Date().toISOString().slice(0, 10);
  const l = [];
  l.push("-- Données des quêtes de départ de WoW Classic, pour l'addon QuetesDispo.");
  l.push("--");
  l.push("-- Source : CMaNGOS classic-db (https://github.com/cmangos/classic-db),");
  l.push("-- licence GNU GPL version 3. Voir QuetesDispo/LICENCE.md.");
  l.push("-- Sauvegarde utilisée : " + nomSource + " (extraction du " + date + ").");
  l.push("--");
  l.push("-- Fichier généré, ne pas modifier à la main : voir outils/quetes-dispo");
  l.push("-- (extraire.js et LISEZMOI.md) pour le refaire.");
  l.push("");
  l.push("local _, ns = ...");
  l.push("");
  l.push("ns.VERSION_DONNEES = " + chaineLua(nomSource));
  l.push("");
  l.push(
    "-- [numéro de quête] = { niveau, niveauMin, races, classes, avant, groupeExclusif, drapeaux, metier, niveauMetier, \"titre anglais\", autresAvant, reputation }"
  );
  l.push("-- Champs facultatifs : 11 = autres quêtes qui ouvrent celle-ci (liste signée, une seule suffit ; 0 si aucune),");
  l.push("-- 12 = numéro de la faction dont il faut une réputation minimale (0 ou absent : aucune).");
  l.push("-- drapeaux : 1 répétable, 2 groupe ou élite, 4 donjon, 8 raid, 16 JcJ, 32 saisonnière ou événement.");
  l.push("ns.QUETES = {");
  for (const q of donnees.quetes) {
    // Champs 11 et 12, seulement s'ils servent : autres prérequis (liste, ou 0), faction de réputation.
    let fin = "";
    if (q.autres.length > 0 || q.reputation > 0) {
      fin += ", " + (q.autres.length > 0 ? "{ " + q.autres.join(", ") + " }" : "0");
      if (q.reputation > 0) fin += ", " + q.reputation;
    }
    l.push(
      "  [" + q.numero + "] = { " +
        [q.niveau, q.niveauMin, q.races, q.classes, q.avant, q.groupeExclusif, q.drapeaux, q.metier, q.niveauMetier].join(", ") +
        ", " + chaineLua(q.titre) + fin + " },"
    );
  }
  l.push("}");
  l.push("");
  l.push("-- un point de départ : { continent, x, y, genre, { numéros de quêtes } }");
  l.push("-- continent : 0 Royaumes de l'Est, 1 Kalimdor. genre : 1 PNJ, 2 objet du décor.");
  l.push("ns.DEPARTS = {");
  for (const d of donnees.departs) {
    l.push(
      "  { " + [d.continent, nombreLua(d.x), nombreLua(d.y), d.genre].join(", ") +
        ", { " + d.quetes.join(", ") + " } },"
    );
  }
  l.push("}");
  l.push("");
  if (donnees.journal) ecrireJournal(l, donnees.journal);
  fs.writeFileSync(sortie, l.join("\n"), "utf8");
}

// Une grande table écrite en morceaux, chacun dans sa propre fonction : Lua 5.1 limite le nombre de constantes
// d'une même fonction (environ 262 000), et ces tables en ont beaucoup.
const LIGNES_PAR_MORCEAU = 400;
function ecrireEnMorceaux(l, nomTable, lignes) {
  l.push(nomTable + " = {}");
  for (let i = 0; i < lignes.length; i += LIGNES_PAR_MORCEAU) {
    l.push("do local t = (function() return {");
    for (const ligne of lignes.slice(i, i + LIGNES_PAR_MORCEAU)) l.push(ligne);
    l.push("} end)() for k, v in pairs(t) do " + nomTable + "[k] = v end end");
  }
}

function ecrireJournal(l, journal) {
  l.push("-- Les objectifs des quêtes, pour les icônes de la carte et la bulle des monstres.");
  l.push("-- [numéro de quête] = { { genre, besoin, { continent, x, y, ... }, { monstres } }, ... }");
  l.push("-- genre : 1 monstre à tuer, 2 objet à ramasser, 3 objet du décor à utiliser. besoin : le nombre demandé.");
  l.push("-- Les positions sont des groupes d'apparitions (au plus " + GROUPES_MAX + " par continent, le plus gros d'abord).");
  l.push("-- monstres : les créatures qui font avancer l'objectif (tuées, ou qui font tomber l'objet).");
  l.push("-- Ordre : monstres et objets du décor (cases 1 à 4 de la base), puis objets à ramasser (cases 1 à 4).");
  const lignes = [];
  for (const [n, liste] of journal.objectifs) {
    const objs = liste.map((o) => {
      const champs = [o.genre, o.besoin];
      if (o.positions.length > 0 || o.monstres.length > 0) champs.push("{" + o.positions.join(",") + "}");
      if (o.monstres.length > 0) champs.push("{" + o.monstres.join(",") + "}");
      return "{" + champs.join(",") + "}";
    });
    lignes.push("[" + n + "]={" + objs.join(",") + "},");
  }
  ecrireEnMorceaux(l, "ns.OBJECTIFS", lignes);
  l.push("");
  l.push("-- Où rendre une quête : { continent, x, y, genre, numéro, { numéros de quêtes } }");
  l.push("-- genre : 1 PNJ, 2 objet du décor. numéro : celui du PNJ ou de l'objet dans la base.");
  ecrireEnMorceaux(
    l,
    "ns.FINS",
    journal.fins.map((f, i) =>
      "[" + (i + 1) + "]={" + [f.continent, nombreLua(f.x), nombreLua(f.y), f.genre, f.id].join(",") + ",{" + f.quetes.join(",") + "}},"
    )
  );
  l.push("");
  l.push("-- Les noms anglais de ceux qui reprennent les quêtes : [numéro du PNJ] ou [-numéro de l'objet du décor].");
  l.push("-- Le jeu est en français : l'addon préfère le nom appris en jeu en parlant au PNJ.");
  const noms = Array.from(journal.noms.entries()).sort((a, b) => a[0] - b[0]);
  ecrireEnMorceaux(l, "ns.NOMS_FINS", noms.map(([k, v]) => "[" + k + "]=" + chaineLua(v) + ","));
  l.push("");
}

// ---------------------------------------------------------------------------
// Programme principal
// ---------------------------------------------------------------------------

async function principal() {
  const source = process.argv[2];
  if (!source) {
    console.error("Usage : node outils/quetes-dispo/extraire.js <chemin du fichier .sql>");
    process.exit(1);
  }
  if (!fs.existsSync(source)) {
    console.error("Fichier introuvable : " + source);
    process.exit(1);
  }
  const racine = path.resolve(__dirname, "..", "..");
  const sortie = path.join(racine, "QuetesDispo", "Donnees.lua");

  console.log("Lecture de " + source + " ...");
  const base = await lireBase(source);
  for (const t of Object.keys(base)) console.log("  " + t + " : " + base[t].length + " lignes");

  const donnees = construire(base);
  fs.mkdirSync(path.dirname(sortie), { recursive: true });
  const tailleAvant = fs.existsSync(sortie) ? fs.statSync(sortie).size : 0;
  ecrireLua(sortie, path.basename(source), donnees);

  const parContinent = { 0: 0, 1: 0 };
  for (const d of donnees.departs) parContinent[d.continent]++;
  const taille = fs.statSync(sortie).size;
  console.log("");
  console.log("Quêtes : " + donnees.quetes.length);
  console.log("Points de départ : " + donnees.departs.length +
    " (Royaumes de l'Est " + parContinent[0] + ", Kalimdor " + parContinent[1] + ")");
  const j = donnees.journal.stats;
  console.log("Objectifs : " + j.objectifs + " (" + j.avecPositions + " avec des positions, " + j.sansPosition +
    " sans ; objets trop communs écartés : " + j.objetsCommuns + ")");
  console.log("Points où rendre : " + j.fins + " (quêtes sans endroit où rendre : " + j.quetesSansFin + ")");
  console.log("Fichier : " + sortie + " (" + (taille / 1024).toFixed(0) + " Ko, avant : " + (tailleAvant / 1024).toFixed(0) + " Ko)");
}

if (require.main === module) {
  principal().catch((e) => {
    console.error("Échec : " + e.message);
    process.exit(1);
  });
}

module.exports = { lireBase, construire, lireValeurs, lireChaine };
