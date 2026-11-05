# Addons WoW de Valentin

Addons World of Warcraft maison, pour Retail (Midnight, Interface 120105) et Forever (Interface 16001).
Les deux versions partagent la même API : un seul addon sert aux deux.

## Addons

| Addon | Rôle | Commande |
|---|---|---|
| [CarnetDeSession](CarnetDeSession/) | Temps de jeu, or, niveaux, expérience (« niveau max » au plafond) et monstres tués depuis la connexion, dans une fenêtre déplaçable ; historique des 20 dernières sessions par personnage | `/carnet` (`raz`, `historique`, `centre`, `debug`, `aide`) |
| [QuetesAuto](QuetesAuto/) | Accepte et rend les quêtes : rend d'abord les quêtes finies, puis accepte les autres (une quête en cours non finie ne bloque plus rien). En groupe, partage tes quêtes et accepte celles du groupe. Option (coupée au départ) : cliquer la phrase quand un PNJ n'en a qu'une. Choisit la récompense (amélioration, sinon la plus chère), filtre les quêtes grises, journalières, payantes, et les PNJ ou quêtes ignorés, passe les cinématiques déjà vues. Tout se règle dans une fenêtre à cases à cocher, sans `/reload` (acceptation et rendu se coupent séparément). Icône autour de la minimap, bouton à l'écran, raccourci clavier ; Maj, Ctrl ou Alt met en pause | `/qa` (ouvre les réglages), `on`, `off`, `ignorer` |
| [MarchandAuto](MarchandAuto/) | Chez un marchand : vend les objets gris (sauf ceux à garder) et répare l'équipement, avec la banque de guilde si elle le permet ; bilan dans le chat. Fenêtre de réglages, icône de minimap ; Maj, Ctrl ou Alt met en pause | `/ma` (ouvre les réglages), `on`, `off`, `garder <objet>` |
| [MetiersAuto](MetiersAuto/) | Pêche : en mode pêche, double clic droit pour lancer, son des effets à fond et musique coupée (remis comme avant ensuite). Récolte : la touche « Interagir avec la cible » vise seule filon, herbe ou bouchon, ramassage automatique, repérage minerais et herbes remis tout seul. Liste de courses d'artisanat (sacs et banque). Jamais d'action sans appui du joueur : un addon ne peut pas, et ne doit pas, récolter à sa place | `/mt` (réglages), `peche`, `courses 5 <recette>`, `courses vider`, `on`, `off` |

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

Chaque dossier d'addon se copie tel quel dans `Interface\AddOns\`. `Reglages.lua` (fenêtre de réglages
à cases à cocher et icône de minimap) est une copie identique dans chaque addon : le modifier dans
l'un, puis le recopier dans les autres (la simulation de MarchandAuto vérifie qu'ils sont égaux). Un addon qui grossit peut
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
  `wsl lua5.1 tests/QuetesAuto_simu.lua QuetesAuto/QuetesAuto.lua`,
  `wsl lua5.1 tests/MarchandAuto_simu.lua MarchandAuto/MarchandAuto.lua`,
  `wsl lua5.1 tests/MetiersAuto_simu.lua MetiersAuto/MetiersAuto.lua`).
- Le nom du dossier doit être identique au nom du `.toc`.

## Partager

Zipper le dossier de l'addon (le dossier lui-même, pas seulement son contenu). La personne le dézippe
dans `World of Warcraft\_retail_\Interface\AddOns\` ou `_forever_\Interface\AddOns\`.
