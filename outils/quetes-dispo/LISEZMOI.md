# Refaire les données de QuetesDispo

`QuetesDispo/Donnees.lua` est généré, il ne se modifie jamais à la main.
Source : CMaNGOS classic-db (GPL-3.0), voir `QuetesDispo/LICENCE.md`.

1. Choisir un dossier de travail EN DEHORS du dépôt (la base pèse 73 Mo).
2. Télécharger la sauvegarde complète (environ 13 Mo) :
   `curl -L -o ClassicDB.sql.gz https://github.com/cmangos/classic-db/raw/master/Full_DB/ClassicDB_1_12_1_z2815.sql.gz`
   Le nom change à chaque jalon : voir le dossier `Full_DB` du dépôt classic-db.
3. La décompresser : `gzip -dk ClassicDB.sql.gz` (Git Bash ou WSL).
   Garder le nom d'origine du fichier `.sql` : il est écrit dans `Donnees.lua`.
4. Depuis la racine du dépôt :
   `node outils/quetes-dispo/extraire.js <chemin du fichier .sql>`
5. Le script lit le fichier ligne par ligne (le CREATE TABLE donne l'ordre des
   colonnes), puis écrit `QuetesDispo/Donnees.lua` et affiche le nombre de quêtes,
   de points et la taille. Deux lancements donnent le même fichier (sortie triée).
6. Contrôler : `wsl luac5.1 -p QuetesDispo/Donnees.lua`, puis
   `node tests/donnees/quetes-dispo-controle.js <chemin du .sql>` (le chemin est
   facultatif : avec lui, le contrôle vérifie aussi les donneurs dans la base).

Ce qui est écarté : quêtes désactivées (colonne Method = 1), titres vides ou
marqués test (seulement le titre « Test » seul : « Test of Faith » reste), quêtes sans donneur, donneurs sans apparition sur Royaumes de l'Est
ou Kalimdor (les instances sont ignorées). Un donneur garde au plus 3 points.
Données téléchargées : à lire seulement, ne rien exécuter qui en vienne.

Ce que le fichier garde en plus : les quêtes qui en ouvrent une autre (colonne
NextQuestId, lue comme CMaNGOS le fait : une seule suffit), la faction d'une
réputation minimale (colonne RequiredMinRepFaction, signalée dans la bulle sans cacher
la quête), et les catégories saisonnières -22, -284, -364 à -369.
Les quêtes du journal (depuis la 0.4.0 de l'addon) : le fichier garde aussi
- `ns.OBJECTIFS` : pour chaque quête de `ns.QUETES`, ses objectifs dans l'ordre de la base
  (monstres et objets du décor des cases ReqCreatureOrGOId 1 à 4, puis objets ReqItemId 1 à 4),
  avec le nombre demandé, des groupes d'apparitions (au plus 5 par continent, chacun représenté
  par une vraie apparition, du plus gros au plus petit) et les créatures utiles (KillCredit compris
  pour un monstre à tuer ; pour un objet, les monstres qui le font tomber d'après
  creature_loot_template, et les coffres d'après gameobject_loot_template) ;
- `ns.FINS` : où rendre chaque quête (creature_involvedrelation et gameobject_involvedrelation),
  au plus 3 points par PNJ et par continent, et `ns.NOMS_FINS` : le nom anglais de ces PNJ et objets.
Règles : un taux de chute sous 1 % ne compte pas ; un objet que plus de 20 genres de monstres font
tomber (50 s'il ne tombe que pour une quête, taux négatif) est jugé trop commun, sans icône ni ligne
dans la bulle ; une apparition au genre tiré au hasard (creature_spawn_entry, gameobject_spawn_entry)
compte pour chacun de ses genres ; les renvois vers reference_loot_template sont ignorés ; l'exploration
n'a pas de position dans la base (elle est dans les fichiers du client), donc pas d'icône.
Ces grandes tables sont écrites en morceaux de 400 lignes, chacun dans sa propre fonction : Lua 5.1
limite le nombre de constantes d'une même fonction. Le script affiche la taille du fichier avant et après.
Extraction du 13/11/2026 : 2 694 quêtes avec objectifs (4 109 objectifs, 1 809 avec des positions),
1 461 endroits où rendre, fichier de 338 Ko passé à 603 Ko.

Après chaque régénération, relancer la simulation :
`wsl lua5.1 tests/QuetesDispo_simu.lua QuetesDispo/QuetesDispo.lua` (depuis la racine du dépôt).
