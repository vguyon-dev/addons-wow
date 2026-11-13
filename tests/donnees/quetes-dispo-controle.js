// Contrôle de QuetesDispo/Donnees.lua (fichier généré par outils/quetes-dispo/extraire.js).
//
// Usage, depuis la racine du dépôt :
//   node tests/donnees/quetes-dispo-controle.js [chemin du .sql de classic-db]
//
// Sans argument : on contrôle seulement le fichier Lua (faits connus de Classic
// et cohérence interne, y compris les tables du journal : OBJECTIFS, FINS,
// NOMS_FINS). Avec le chemin du .sql : on contrôle aussi que le donneur de la
// quête 65 porte bien le bon nom dans la base d'origine, et où se rend la quête 7.
//
// Lua 5.1 est lancé par WSL (« wsl lua5.1 ») : on lui fait charger le fichier
// comme le fait le jeu, puis afficher son contenu en texte simple.

"use strict";

const path = require("path");
const { spawnSync } = require("child_process");

const racine = path.resolve(__dirname, "..", "..");

let echecs = 0;
let reussites = 0;
function verifier(condition, message) {
  if (condition) {
    reussites++;
  } else {
    echecs++;
    console.log("ECHEC : " + message);
  }
}

// --- Chargement par Lua -----------------------------------------------------

const scriptLua = `
local f = assert(loadfile("QuetesDispo/Donnees.lua"))
local ns = {}
f("QuetesDispo", ns)
io.write("V\\t", tostring(ns.VERSION_DONNEES), "\\n")
for numero, q in pairs(ns.QUETES) do
  io.write("Q\\t", numero)
  for i = 1, 9 do io.write("\\t", tostring(q[i])) end
  io.write("\\t", tostring(q[10]), "\\t", tostring(#q))
  local autres = q[11]
  io.write("\\t", type(autres) == "table" and table.concat(autres, ",") or tostring(autres), "\\t", tostring(q[12]), "\\n")
end
for _, d in ipairs(ns.DEPARTS) do
  io.write("D\\t", d[1], "\\t", d[2], "\\t", d[3], "\\t", d[4], "\\t", table.concat(d[5], ","), "\\n")
end
for numero, liste in pairs(ns.OBJECTIFS or {}) do
  for i, o in ipairs(liste) do
    io.write("O\\t", numero, "\\t", i, "\\t", tostring(o[1]), "\\t", tostring(o[2]), "\\t",
      type(o[3]) == "table" and table.concat(o[3], ",") or "", "\\t", type(o[4]) == "table" and table.concat(o[4], ",") or "", "\\n")
  end
end
for _, f in ipairs(ns.FINS or {}) do
  io.write("F\\t", f[1], "\\t", f[2], "\\t", f[3], "\\t", f[4], "\\t", f[5], "\\t", table.concat(f[6], ","), "\\n")
end
for cle, nom in pairs(ns.NOMS_FINS or {}) do io.write("N\\t", cle, "\\t", nom, "\\n") end
`;

const r = spawnSync("wsl", ["lua5.1", "-"], {
  cwd: racine,
  input: scriptLua,
  encoding: "utf8",
  maxBuffer: 64 * 1024 * 1024,
});
if (r.status !== 0) {
  console.log("Lua n'a pas pu charger QuetesDispo/Donnees.lua :");
  console.log(r.stderr || r.error);
  process.exit(1);
}

const quetes = new Map(); // numéro -> { champs, titre, nbChamps }
const objectifs = new Map(); // numéro -> [{ genre, besoin, positions[], monstres[] }]
const fins = []; // { continent, x, y, genre, id, quetes[] }
const nomsFins = new Map(); // clé (id, ou -id pour un objet du décor) -> nom
const departs = []; // { continent, x, y, genre, quetes[] }
let version = null;
for (const ligne of r.stdout.split("\n")) {
  if (!ligne) continue;
  const c = ligne.split("\t");
  if (c[0] === "V") version = c[1];
  else if (c[0] === "Q") {
    quetes.set(Number(c[1]), {
      champs: c.slice(2, 11).map(Number),
      titre: c[11],
      nbChamps: Number(c[12]),
      autres: c[13] === "nil" || c[13] === "0" ? [] : c[13].split(",").map(Number),
      reputation: c[14] === "nil" ? 0 : Number(c[14]),
    });
  } else if (c[0] === "O") {
    const n = Number(c[1]);
    if (!objectifs.has(n)) objectifs.set(n, []);
    objectifs.get(n)[Number(c[2]) - 1] = {
      genre: Number(c[3]),
      besoin: Number(c[4]),
      positions: c[5] ? c[5].split(",").map(Number) : [],
      monstres: c[6] ? c[6].split(",").map(Number) : [],
    };
  } else if (c[0] === "F") {
    fins.push({
      continent: Number(c[1]), x: Number(c[2]), y: Number(c[3]), genre: Number(c[4]), id: Number(c[5]),
      quetes: c[6].split(",").map(Number),
    });
  } else if (c[0] === "N") {
    nomsFins.set(Number(c[1]), c[2]);
  } else if (c[0] === "D") {
    departs.push({
      continent: Number(c[1]),
      x: Number(c[2]),
      y: Number(c[3]),
      genre: Number(c[4]),
      quetes: c[5].split(",").map(Number),
    });
  }
}

// --- Faits connus de Classic --------------------------------------------------

const [NIVEAU, NIVEAU_MIN, RACES, CLASSES, AVANT, GROUPE_EXCL, DRAPEAUX, METIER, NIVEAU_METIER] = [0, 1, 2, 3, 4, 5, 6, 7, 8];

verifier(version !== null && version !== "nil" && version.length > 0, "VERSION_DONNEES absente");
verifier(quetes.size >= 2500, "au moins 2500 quêtes (trouvé " + quetes.size + ")");

const q65 = quetes.get(65);
verifier(!!q65, "la quête 65 existe");
if (q65) {
  verifier(q65.titre === "The Defias Brotherhood", "titre de la quête 65 : " + q65.titre);
  verifier(q65.champs[NIVEAU] >= 17 && q65.champs[NIVEAU] <= 19, "niveau de la quête 65 vers 18 : " + q65.champs[NIVEAU]);
}
const departs65 = departs.filter((d) => d.quetes.includes(65));
verifier(departs65.length >= 1, "la quête 65 a au moins un point de départ");
verifier(departs65.every((d) => d.continent === 0), "la quête 65 est donnée sur le continent 0");
// Marche de l'Ouest : environ x de -11200 à -9900, y de 0 à 2300 dans les coordonnées du monde.
verifier(
  departs65.some((d) => d.x > -11200 && d.x < -9900 && d.y > 0 && d.y < 2300),
  "un point de la quête 65 est en Marche de l'Ouest"
);

const q783 = quetes.get(783);
verifier(!!q783, "la quête 783 existe");
if (q783) {
  verifier(q783.titre === "A Threat Within", "titre de la quête 783 : " + q783.titre);
  verifier(q783.champs[NIVEAU] === 1, "niveau de la quête 783 : " + q783.champs[NIVEAU]);
}
verifier(departs.some((d) => d.continent === 0 && d.quetes.includes(783)), "la quête 783 a un point en continent 0");

// Constats 2, 3, 5 et 6 de la relecture.
// 2. Les vraies quêtes dont le titre commence par « Test » ne sont pas écartées.
for (const [n, titre] of [[1149, "Test of Faith"], [3123, "Testing the Vessel"], [6628, null]]) {
  const q = quetes.get(n);
  verifier(!!q, "la quête " + n + " (titre commençant par Test) est gardée");
  if (q && titre) verifier(q.titre === titre, "titre de la quête " + n + " : " + q.titre);
}
verifier(quetes.has(1394) && quetes.get(1394).champs[AVANT] === 6628, "la quête 1394 a toujours 6628 pour prérequis, et 6628 existe");
verifier(![...quetes.values()].some((q) => q.titre.trim().toLowerCase() === "test"), "aucune quête nommée seulement « Test »");
// 3. NextQuestId inversé : 247 demande 2, 23 ou 24.
verifier(quetes.get(247) && quetes.get(247).autres.join(",") === "2,23,24", "la quête 247 a 2, 23 et 24 comme autres prérequis : " + (quetes.get(247) && quetes.get(247).autres));
verifier([...quetes.values()].filter((q) => q.autres.length > 0).length >= 80, "au moins 80 quêtes ont des autres prérequis");
// 4. 813 : à avoir EN COURS (812), valeur négative gardée telle quelle.
verifier(quetes.get(813) && quetes.get(813).champs[AVANT] === -812, "la quête 813 garde son prérequis négatif -812");
// 5. Les trois catégories d'événements ajoutées portent le drapeau saisonnier (32).
for (const n of [8492, 8811, 9260]) {
  verifier(quetes.has(n) && (quetes.get(n).champs[DRAPEAUX] & 32) !== 0, "la quête " + n + " (catégorie d'événement) porte le drapeau saisonnier");
}
// 6. Une quête qui demande une réputation porte sa faction.
verifier([...quetes.values()].filter((q) => q.reputation > 0).length >= 150, "au moins 150 quêtes portent une faction de réputation");

// --- Cohérence interne -------------------------------------------------------

verifier(departs.every((d) => d.continent === 0 || d.continent === 1), "aucun point hors des continents 0 et 1");
verifier(departs.every((d) => d.genre === 1 || d.genre === 2), "genre de chaque point : 1 ou 2");
verifier(departs.every((d) => Number.isFinite(d.x) && Number.isFinite(d.y)), "coordonnées numériques");

const avecPoint = new Set();
for (const d of departs) for (const n of d.quetes) avecPoint.add(n);
const sansPoint = [...quetes.keys()].filter((n) => !avecPoint.has(n));
verifier(sansPoint.length === 0, "aucune quête sans point (" + sansPoint.slice(0, 5).join(", ") + ")");
const inconnues = [...avecPoint].filter((n) => !quetes.has(n));
verifier(inconnues.length === 0, "tout numéro de quête d'un point existe dans QUETES (" + inconnues.slice(0, 5).join(", ") + ")");

verifier(
  [...quetes.values()].every((q) => q.nbChamps >= 10 && q.nbChamps <= 12 && q.champs.length === 9 && q.champs.every(Number.isFinite)),
  "chaque quête a 9 nombres, un titre, puis au plus 2 champs facultatifs"
);
verifier(
  [...quetes.values()].every((q) => q.autres.every((a) => Number.isInteger(a) && a !== 0) && Number.isFinite(q.reputation)),
  "autres prérequis : entiers signés non nuls ; réputation : nombre"
);
verifier([...quetes.values()].every((q) => q.titre && q.titre !== "nil" && q.titre.trim() !== ""), "aucun titre vide");
verifier([...quetes.values()].every((q) => q.champs[DRAPEAUX] >= 0 && q.champs[DRAPEAUX] < 64), "drapeaux entre 0 et 63");
verifier([...quetes.values()].every((q) => q.champs[RACES] >= 0 && q.champs[CLASSES] >= 0), "masques de races et de classes positifs");

// Pas de point en double : deux entrées identiques (même continent, même
// position, même genre, mêmes quêtes) ne devraient pas exister. Le contrôle
// « un même donneur » précis (3 points au plus, 5 mètres d'écart) se fait plus
// bas, avec la base d'origine, car le fichier Lua ne garde pas le numéro du donneur.
const vus = new Set();
let doublons = 0;
for (const d of departs) {
  const cle = [d.continent, d.x, d.y, d.genre, d.quetes.join(",")].join("|");
  if (vus.has(cle)) doublons++;
  vus.add(cle);
}
verifier(doublons === 0, doublons + " point(s) en double");

// Les listes de quêtes d'un point sont triées et sans répétition.
verifier(
  departs.every((d) => d.quetes.every((n, i) => i === 0 || n > d.quetes[i - 1])),
  "numéros de quêtes de chaque point triés, sans répétition"
);

// --- Les tables du journal (objectifs, endroits où rendre) ---------------------

verifier(objectifs.size >= 2000, "au moins 2000 quêtes avec des objectifs (trouvé " + objectifs.size + ")");
verifier([...objectifs.keys()].every((n) => quetes.has(n)), "objectifs : seulement des quêtes de QUETES");
let objMalFormes = 0;
let objTropDeGroupes = 0;
let objAvecPositions = 0;
for (const liste of objectifs.values()) {
  for (const o of liste) {
    if (!o || ![1, 2, 3].includes(o.genre) || !Number.isInteger(o.besoin) || o.besoin < 0) { objMalFormes++; continue; }
    if (o.positions.length % 3 !== 0 || !o.positions.every(Number.isFinite)) objMalFormes++;
    if (!o.monstres.every((m) => Number.isInteger(m) && m > 0)) objMalFormes++;
    const parCont = {};
    for (let k = 0; k < o.positions.length; k += 3) {
      if (o.positions[k] !== 0 && o.positions[k] !== 1) objMalFormes++;
      parCont[o.positions[k]] = (parCont[o.positions[k]] || 0) + 1;
    }
    if (Object.values(parCont).some((nb) => nb > 5)) objTropDeGroupes++;
    if (o.positions.length > 0) objAvecPositions++;
  }
}
verifier(objMalFormes === 0, objMalFormes + " objectif(s) mal formé(s)");
verifier(objTropDeGroupes === 0, objTropDeGroupes + " objectif(s) avec plus de 5 groupes sur un continent");
verifier(objAvecPositions >= 1500, "au moins 1500 objectifs avec des positions (trouvé " + objAvecPositions + ")");
// Faits connus : 7 « Kobold Camp Cleanup » (tuer 10 vermines kobold, créature 6, au nord de Comté-de-l'Or),
// 22 « Goretusk Liver Pie » (8 foies, que les sangliers 157 font tomber, en Marche de l'Ouest),
// 11 « Riverpaw Gnoll Bounty » (gnolls dont l'apparition tire le genre au hasard : creature_spawn_entry).
const o7 = objectifs.get(7) && objectifs.get(7)[0];
verifier(o7 && o7.genre === 1 && o7.besoin === 10 && o7.monstres.includes(6), "quête 7 : tuer 10 créatures 6");
verifier(o7 && o7.positions.length >= 3 && o7.positions[0] === 0 && o7.positions[1] > -9200 && o7.positions[1] < -8500,
  "quête 7 : les kobolds sont en forêt d'Elwynn");
const o22 = objectifs.get(22) && objectifs.get(22)[0];
verifier(o22 && o22.genre === 2 && o22.besoin === 8 && o22.monstres.includes(157), "quête 22 : 8 objets, que la créature 157 fait tomber");
verifier(o22 && o22.positions.length >= 3 && o22.positions[1] > -11200 && o22.positions[1] < -9400, "quête 22 : en Marche de l'Ouest");
const o11 = objectifs.get(11) && objectifs.get(11)[0];
verifier(o11 && o11.positions.length >= 3, "quête 11 : les gnolls tirés au hasard ont des positions");

verifier(fins.length >= 1000, "au moins 1000 endroits où rendre (trouvé " + fins.length + ")");
verifier(fins.every((f) => (f.continent === 0 || f.continent === 1) && (f.genre === 1 || f.genre === 2) && Number.isFinite(f.x) && Number.isFinite(f.y)),
  "endroits où rendre : continent, genre et position valables");
verifier(fins.every((f) => f.quetes.every((n) => quetes.has(n))), "endroits où rendre : seulement des quêtes de QUETES");
verifier(fins.every((f) => f.quetes.every((n, i) => i === 0 || n > f.quetes[i - 1])), "endroits où rendre : quêtes triées, sans répétition");
const pointsParRendeur = new Map();
for (const f of fins) {
  const cle = f.genre + ":" + f.id + ":" + f.continent;
  pointsParRendeur.set(cle, (pointsParRendeur.get(cle) || 0) + 1);
}
verifier([...pointsParRendeur.values()].every((n) => n <= 3), "endroits où rendre : au plus 3 points par PNJ et par continent");
const sansNom = fins.filter((f) => !nomsFins.has(f.genre === 2 ? -f.id : f.id)).length;
verifier(sansNom <= fins.length * 0.05, sansNom + " endroit(s) où rendre sans nom (au plus 5 %)");
verifier(fins.some((f) => f.id === 197 && f.genre === 1 && f.quetes.includes(7)) && nomsFins.get(197) === "Marshal McBride",
  "la quête 7 se rend à Marshal McBride (197)");
const quetesAvecFin = new Set();
for (const f of fins) for (const n of f.quetes) quetesAvecFin.add(n);
verifier(quetesAvecFin.size >= quetes.size * 0.95, "au moins 95 % des quêtes ont un endroit où les rendre (" + quetesAvecFin.size + ")");

// Taille : le fichier reste raisonnable (338 Ko avant les tables du journal, au plus 2 Mo de plus).
const tailleDonnees = require("fs").statSync(path.join(racine, "QuetesDispo", "Donnees.lua")).size;
verifier(tailleDonnees < 345616 + 2 * 1024 * 1024, "Donnees.lua pèse moins de 2,3 Mo (" + Math.round(tailleDonnees / 1024) + " Ko)");

// --- Contrôle contre la base d'origine (facultatif) ---------------------------

const sql = process.argv[2];
if (sql) {
  (async () => {
    const { lireBase } = require(path.join(racine, "outils", "quetes-dispo", "extraire.js"));
    const base = await lireBase(sql);
    const donneur = base.creature_questrelation.filter((x) => x.quest === 65).map((x) => x.id);
    const noms = donneur.map((id) => {
      const t = base.creature_template.find((c) => c.Entry === id);
      return t ? t.Name : "?";
    });
    verifier(noms.includes("Gryan Stoutmantle"), "dans la base, le donneur de la quête 65 est Gryan Stoutmantle (trouvé : " + noms.join(", ") + ")");
    // Le donneur doit apparaître à l'endroit du point (à 1 mètre près).
    const apparitions = base.creature.filter((c) => donneur.includes(c.id));
    verifier(
      apparitions.some((a) => departs65.some((d) => Math.hypot(d.x - a.position_x, d.y - a.position_y) < 1)),
      "le point de la quête 65 correspond à une apparition de son donneur"
    );
    // Les objets du décor donneurs de quêtes ont bien un nom dans la base.
    const objets = base.gameobject_questrelation.map((x) => x.id);
    verifier(
      objets.every((id) => base.gameobject_template.some((g) => g.entry === id)),
      "chaque objet donneur de quête a une fiche gameobject_template"
    );
    // Un même donneur : trois points au plus par continent, à 5 mètres ou plus l'un
    // de l'autre. On retrouve les points d'un donneur par la position de ses
    // apparitions et par sa liste de quêtes gardées.
    const gardees = new Set(quetes.keys());
    const donneurs = new Map(); // "genre:id" -> Set de quêtes gardées
    for (const [liste, genre] of [[base.creature_questrelation, 1], [base.gameobject_questrelation, 2]]) {
      for (const x of liste) {
        if (!gardees.has(x.quest)) continue;
        const cle = genre + ":" + x.id;
        if (!donneurs.has(cle)) donneurs.set(cle, new Set());
        donneurs.get(cle).add(x.quest);
      }
    }
    const spawns = new Map(); // "genre:id" -> apparitions
    for (const [liste, genre] of [[base.creature, 1], [base.gameobject, 2]]) {
      for (const s of liste) {
        const cle = genre + ":" + s.id;
        if (!donneurs.has(cle)) continue;
        if (!spawns.has(cle)) spawns.set(cle, []);
        spawns.get(cle).push(s);
      }
    }
    // Plusieurs donneurs peuvent avoir exactement la même liste de quêtes (par
    // exemple treize objets du décor pour une même quête) : leurs points se
    // mélangent dans le fichier. On ne contrôle l'écart que pour les donneurs
    // dont la liste (avec le genre) est unique.
    const effectifs = new Map();
    for (const [cle, ensemble] of donneurs) {
      const k = cle.split(":")[0] + "|" + [...ensemble].sort((a, b) => a - b).join(",");
      effectifs.set(k, (effectifs.get(k) || 0) + 1);
    }
    let pointsOrphelins = 0;
    let tropDePoints = 0;
    let tropProches = 0;
    let donneurSansPoint = 0;
    for (const [cle, ensemble] of donneurs) {
      const genre = Number(cle.split(":")[0]);
      const liste = [...ensemble].sort((a, b) => a - b).join(",");
      const sp = spawns.get(cle) || [];
      const siens = departs.filter(
        (d) => d.genre === genre && d.quetes.join(",") === liste &&
          sp.some((s) => s.map === d.continent && Math.hypot(s.position_x - d.x, s.position_y - d.y) < 0.2)
      );
      if (sp.length > 0 && siens.length === 0) donneurSansPoint++;
      if (effectifs.get(genre + "|" + liste) !== 1) continue;
      for (const cont of [0, 1]) {
        const g = siens.filter((d) => d.continent === cont);
        if (g.length > 3) tropDePoints++;
        for (let a = 0; a < g.length; a++) {
          for (let b = a + 1; b < g.length; b++) {
            if (Math.hypot(g[a].x - g[b].x, g[a].y - g[b].y) < 5) tropProches++;
          }
        }
      }
    }
    // Chaque point du fichier vient bien d'un donneur de ses quêtes.
    for (const d of departs) {
      const ok = [...donneurs].some(([cle, ensemble]) => {
        if (Number(cle.split(":")[0]) !== d.genre) return false;
        if (ensemble.size !== d.quetes.length || !d.quetes.every((n) => ensemble.has(n))) return false;
        return (spawns.get(cle) || []).some((s) => s.map === d.continent && Math.hypot(s.position_x - d.x, s.position_y - d.y) < 0.2);
      });
      if (!ok) pointsOrphelins++;
    }
    verifier(tropDePoints === 0, tropDePoints + " donneur(s) avec plus de 3 points sur un continent");
    verifier(tropProches === 0, tropProches + " paire(s) de points d'un même donneur à moins de 5 mètres");
    verifier(pointsOrphelins === 0, pointsOrphelins + " point(s) qui ne viennent d'aucun donneur de leurs quêtes");
    verifier(donneurSansPoint === 0, donneurSansPoint + " donneur(s) avec apparition sur un continent mais sans point");
    // La quête 7 se rend bien à la créature 197 dans la base, et 197 apparaît à l'endroit du « ? ».
    verifier(base.creature_involvedrelation.some((x) => x.quest === 7 && x.id === 197), "dans la base, la quête 7 se rend à la créature 197");
    const app197 = base.creature.filter((c) => c.id === 197);
    verifier(fins.filter((f) => f.id === 197 && f.genre === 1).every((f) =>
      app197.some((a) => Math.hypot(a.position_x - f.x, a.position_y - f.y) < 1)), "le « ? » de la créature 197 est à l'une de ses apparitions");
    fin();
  })().catch((e) => {
    console.log("Contrôle de la base impossible : " + e.message);
    process.exit(1);
  });
} else {
  fin();
}

function fin() {
  console.log("");
  console.log(
    reussites + " vérifications réussies, " + echecs + " échec(s). " +
      quetes.size + " quêtes, " + departs.length + " points de départ, " + objectifs.size + " quêtes avec objectifs, " +
      fins.length + " endroits où rendre."
  );
  process.exit(echecs === 0 ? 0 : 1);
}
