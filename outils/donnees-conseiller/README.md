# Fiches de données du Conseiller

Une fiche par classe (`chasseur.md`, `paladin.md`, `guerrier.md`, `voleur.md`, `pretre.md`, `chaman.md`, `mage.md`, `demoniste.md`, `druide.md`). Ce sont **la source des données** du Conseiller : tout ce que `Conseiller/Donnees.lua` sait d'une classe (spécialisation conseillée par situation, rôle qui manque au groupe, builds de talents, priorités de rotation, ordre des statistiques, métiers, conseils seul et en groupe) vient de ces fiches.

Chaque fiche a les mêmes neuf sections : sources, spécialisations, spécialisation conseillée, builds, rotation, « à savoir », ordre des statistiques, métiers, points incertains. Elle est **croisée sur plusieurs sites de guides Forever** (Warcraft Tavern, Method, Zockify, WowTBC, RankedBoost, Gfinity…), avec leurs divergences notées, et complétée par des règles de Classic quand aucun guide Forever ne dit rien (c'est signalé : « (m) » = de mémoire, « ? » = inconnu).

## À rafraîchir à chaque patch

Les guides Forever étaient encore en bêta (niveau 30, 5 points Legacy) quand les fiches ont été écrites le 10/11/2026 : l'ordre des talents des niveaux 31 à 60, la spécialisation de raid et l'ordre des statistiques au niveau 60 sont des projections. À chaque patch ou à la sortie des guides niveau 60 :

1. relire les guides cités dans la section « Sources » de chaque fiche et corriger la fiche ;
2. reporter dans `Conseiller/Donnees.lua` (choix de spécialisation, `D.ROTATIONS`, `D.BUILDS`, `D.STATS`, conseils), et changer la date de la classe dans `D.DATES_BUILDS` (affichée dans l'onglet Talents) ;
3. lancer `wsl lua5.1 tests/Conseiller_simu.lua Conseiller/Conseiller.lua` depuis la racine : le test vérifie que chaque classe a une spécialisation conseillée pour chaque situation, une priorité non vide par spécialisation, des sorts tous déclarés, des conseils seul et en groupe et des builds dont chaque entrée a un nom.

Pour corriger les noms de talents, le plus sûr est un export fait en jeu : `/cs export` puis `/reload`, et lire `ConseillerDB.export` (nœuds, entrées, spellID, nom dans la langue du jeu). Les talents que le Conseiller n'a pas reconnus sont nommés par `/cs etat` et dans l'onglet Talents.
