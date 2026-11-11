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
Après chaque régénération, relancer la simulation :
`wsl lua5.1 tests/QuetesDispo_simu.lua QuetesDispo/QuetesDispo.lua` (depuis la racine du dépôt).
