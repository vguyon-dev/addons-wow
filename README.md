# Addons WoW de Valentin

Addons World of Warcraft maison, pour Retail (Midnight, Interface 120105) et Forever (Interface 16001).
Les deux versions partagent la même API : un seul addon sert aux deux.

## Addons

| Addon | Rôle | Commande |
|---|---|---|
| [CarnetDeSession](CarnetDeSession/) | Temps de jeu, or, niveaux, expérience (« niveau max » au plafond) et monstres tués depuis la connexion, dans une fenêtre déplaçable ; historique des 20 dernières sessions par personnage | `/carnet` (`raz`, `historique`, `centre`, `debug`, `aide`) |
| [QuetesAuto](QuetesAuto/) | Accepte et rend les quêtes : rend d'abord les quêtes finies, puis accepte les autres (une quête en cours non finie ne bloque plus rien). Choisit la récompense (amélioration, sinon la plus chère), filtre les quêtes grises, journalières, payantes, et les PNJ ou quêtes ignorés, passe les cinématiques déjà vues. Bouton à l'écran et raccourci clavier ; Maj, Ctrl ou Alt met en pause | `/qa` (`recompense`, `grises`, `journalieres`, `payantes`, `cinematiques`, `bouton`, `ignorer`, `liste`) |

## Arborescence

Un seul dépôt pour tous les addons, un dossier par addon à la racine :

```
addons-wow/
├── README.md            ce fichier : liste des addons et méthode
├── .gitignore
├── tests/               simulations hors jeu (jamais copiées dans AddOns)
├── CarnetDeSession/     un addon = un dossier, au même nom que son .toc
│   ├── CarnetDeSession.toc
│   └── CarnetDeSession.lua
└── <ProchainAddon>/
    ├── <ProchainAddon>.toc
    └── <ProchainAddon>.lua
```

Chaque dossier d'addon se copie tel quel dans `Interface\AddOns\`. Un addon qui grossit peut
avoir plusieurs `.lua`, listés dans son `.toc`, et son propre `README.md`.

## Développer

Chaque dossier d'addon est relié aux dossiers AddOns du jeu par une **jonction** Windows :
une modification ici est vue par le jeu au prochain `/reload`, sans rien copier.

```powershell
$src = "D:\@DEV\Jeux\Modding\Wow\<Addon>"
foreach ($v in "_retail_", "_forever_") {
  New-Item -ItemType Junction -Target $src `
    -Path "D:\Program Files (x86)\Battle.net\World of Warcraft\$v\Interface\AddOns\<Addon>"
}
```

- Erreurs Lua : BugSack + BugGrabber (installés par CurseForge sur les deux versions).
  BugGrabber les écrit sur le disque à chaque `/reload` ou déconnexion, avec la pile d'appels,
  dans `<version>\WTF\Account\<compte>\SavedVariables\!BugGrabber.lua` : on peut les lire sans capture.
- Données d'un addon : `SavedVariables` (compte) dans `WTF\Account\<compte>\SavedVariables\`,
  `SavedVariablesPerCharacter` dans `WTF\Account\<compte>\<royaume>\<personnage>\SavedVariables\`.
- Vérifier la syntaxe avant de lancer le jeu : `wsl luac5.1 -p <fichier>.lua` (WoW utilise Lua 5.1).
- Simuler un addon hors du jeu, avec une fausse API WoW : `tests/` (exemple :
  `wsl lua5.1 tests/CarnetDeSession_simu.lua CarnetDeSession/CarnetDeSession.lua`, ou
  `wsl lua5.1 tests/QuetesAuto_simu.lua QuetesAuto/QuetesAuto.lua`).
- Le nom du dossier doit être identique au nom du `.toc`.

## Partager

Zipper le dossier de l'addon (le dossier lui-même, pas seulement son contenu). La personne le dézippe
dans `World of Warcraft\_retail_\Interface\AddOns\` ou `_forever_\Interface\AddOns\`.
