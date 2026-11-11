// Extraction des quêtes de Classic depuis la base CMaNGOS classic-db.
//
// Usage :  node outils/quetes-dispo/extraire.js <chemin du fichier .sql>
// Résultat : QuetesDispo/Donnees.lua (fichier généré, ne pas modifier à la main).
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
  ],
  creature_questrelation: ["id", "quest"],
  gameobject_questrelation: ["id", "quest"],
  creature: ["guid", "id", "map", "position_x", "position_y"],
  gameobject: ["guid", "id", "map", "position_x", "position_y"],
  // Les fêtes et événements : qui n'apparaît que pendant un événement, et quelles quêtes en dépendent.
  game_event_creature: ["guid", "event"],
  game_event_gameobject: ["guid", "event"],
  game_event_quest: ["quest", "event"],
  creature_template: ["Entry", "Name"],
  gameobject_template: ["entry", "name"],
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
  return { quetes, departs };
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
  fs.writeFileSync(sortie, l.join("\n"), "utf8");
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
  ecrireLua(sortie, path.basename(source), donnees);

  const parContinent = { 0: 0, 1: 0 };
  for (const d of donnees.departs) parContinent[d.continent]++;
  const taille = fs.statSync(sortie).size;
  console.log("");
  console.log("Quêtes : " + donnees.quetes.length);
  console.log("Points de départ : " + donnees.departs.length +
    " (Royaumes de l'Est " + parContinent[0] + ", Kalimdor " + parContinent[1] + ")");
  console.log("Fichier : " + sortie + " (" + (taille / 1024).toFixed(0) + " Ko)");
}

if (require.main === module) {
  principal().catch((e) => {
    console.error("Échec : " + e.message);
    process.exit(1);
  });
}

module.exports = { lireBase, construire, lireValeurs, lireChaine };
