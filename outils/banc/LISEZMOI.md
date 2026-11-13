# Banc d'essai (outil de développement)

Un petit addon **jamais publié** (il n'est pas à la racine du dépôt, donc `outils/publier.py` ne le voit pas)
qui sert à essayer nos addons en jeu sans lire la discussion sur des captures d'écran.

## Installation, une fois par poste

Une jonction du dossier du jeu vers ce dossier, comme pour les autres addons :

    New-Item -ItemType Junction -Path "<jeu>\_forever_\Interface\AddOns\BancEssai" -Target "<dépôt>\outils\banc\BancEssai"

## La boucle

1. Écrire `BancEssai/Script.lua` : un identifiant neuf et une fonction.

       Banc.id = "sacs-1"
       function Banc.script()
         Banc.note("libres", C_Container.GetContainerNumFreeSlots(1))
         Banc.commande("/qd etat")          -- une commande d'addon, sa sortie est notée
         Banc.voir("db", MetiersAutoDB)      -- une table, clé par clé
       end

2. Dans le jeu : `/reload`. Le script tourne deux secondes après l'entrée en jeu. Attendre sa fin, puis
   taper `/reload` une seconde fois : c'est ce rechargement qui écrit le résultat sur le disque (le jeu
   refuse qu'un addon recharge l'interface sans un geste du joueur, vu sur Forever le 13/11/2026).
3. Lire `<jeu>\_forever_\WTF\Account\<compte>\SavedVariables\BancEssai.lua` : `lignes` contient tout ce que le
   script a noté et tout ce qui est passé dans la discussion (préfixe `chat>`), sans les couleurs.

Un essai qui prend du temps : poser `Banc.attente = 30` (garde-fou en secondes), utiliser
`Banc.apres(délai, fonction)` et appeler `Banc.fin()` à la fin. `Banc.sansRecharger = true` laisse la main
(pour appuyer sur des touches avant de taper `/reload` soi-même).

## Limites

- Le banc ne peut pas faire ce que le jeu réserve à un geste du joueur : lancer un sort, utiliser un objet,
  appuyer sur une touche. Ces gestes restent faits à la main ou par l'outil de pilotage de l'écran.
- `Banc.commande` ne lance que les commandes des addons, pas celles du jeu (`/cast`, `/equip`).
- Le même identifiant ne rejoue pas : c'est ce qui évite une boucle de rechargements.
- Un addon ajouté pendant que le jeu tourne n'est vu qu'après un retour à l'écran des personnages.

## Le pilote : un essai en une commande (`banc.ps1`)

Le pilote fait toute la boucle à ma place : il écrit `Script.lua`, met la fenêtre du jeu devant, tape
`/reload`, joue les touches demandées pendant que le script tourne, tape `/reload` une seconde fois, puis
affiche les lignes notées et les nouvelles erreurs de BugGrabber. Compter 30 à 40 secondes par essai.

    pwsh outils/banc/banc.ps1 -Lua 'Banc.note(GetCVar("SoftTargetInteract"))'
    pwsh outils/banc/banc.ps1 -Script mon-essai.lua
    pwsh outils/banc/banc.ps1 -Lua 'Banc.commande("/metiers peche")' -Touches 'attendre:3; F:0.2; attendre:10; F:0.2' -Duree 20
    pwsh outils/banc/banc.ps1 -Relire        # réaffiche le dernier résultat, sans toucher au jeu
    pwsh outils/banc/banc.ps1 -Lua '...' -Touches '...' -Verifier   # dit ce qui serait fait, sans toucher au jeu

- `-Lua` ou `-Script` : le corps de `Banc.script` (l'identifiant est posé tout seul), ou un `Script.lua` complet.
- `-Touches` : des actions séparées par `;`. Une touche avec sa durée d'appui (`F:0.2`, `1`, `F5`, `ESPACE`,
  `ENTREE`, `ECHAP`, `TAB`), `attendre:secondes`, `cmd:/commande` (tapée dans la discussion, donc les
  commandes du jeu marchent aussi : `cmd:/equip item:6256`).
- `-Duree` : le temps laissé au script avant le second `/reload` (par défaut `Banc.attente` + 3, sinon 4 s).
- `-Jeu _retail_` pour l'autre jeu.

Garde-fous : avant chaque frappe, le pilote vérifie que la fenêtre de devant est celle du jeu, sinon il
s'arrête sans rien taper. Si le jeu n'est pas lancé, il le dit et ne fait rien. Il ne lance jamais le jeu.

C'est un programme extérieur qui envoie des touches au jeu : à réserver à de courts essais de nos addons,
jamais pour jouer à la place du joueur.

### Horloge commune et pièges (essai réel du 13/11/2026)

- Le pilote écrit `Banc.top` (une heure du poste) dans le script : le script démarre à cette seconde, et les
  touches aussi. Un `Banc.apres(8, ...)` et un `attendre:8` tombent donc au même instant.
- Mesuré : 18 s pour un essai simple, 44 s pour une pêche avec deux appuis sur F.
- Le jeu refuse `ReloadUI` à un addon : le banc ne recharge jamais seul, le second `/reload` vient du pilote.
- Une fois une commande tapée dans la discussion, le jeu range les commandes des addons dans
  `hash_SlashCmdList` et efface les `SLASH_...` : `Banc.commande` regarde aux deux endroits.
- La structure `INPUT` de `SendInput` fait 40 octets en 64 bits : trop courte, Windows ignore toutes les
  touches sans rien dire.
- Sur l'écran des personnages, le pilote ne sait pas entrer en jeu : il faut être sur un personnage.
