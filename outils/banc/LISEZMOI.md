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
