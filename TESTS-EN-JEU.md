# Tests à faire en jeu

Tout ce qui est codé mais pas encore vérifié dans le jeu. Les simulations hors jeu (`tests/`) passent toutes, mais elles ne voient ni l'affichage ni les blocages du jeu.

Pour chaque test : coche la case quand c'est bon. Si quelque chose cloche, fais `/reload`, puis dis « regarde » : les erreurs sont lues directement dans les fichiers du jeu.

Avant de commencer :
- [ ] Mettre à jour les addons dans WowUp, puis `/reload`.
- [ ] Désactiver Pawn, pour ne voir que notre avis sur les objets.
- [ ] Vérifier que BugSack est actif sur Forever.

## La fenêtre de réglages commune (refaite le 10/11)

- [ ] Clic sur l'engrenage de la minimap : la fenêtre « Addons de Valentin » s'ouvre, sans erreur. Échap la ferme.
- [ ] À gauche : les 17 addons, avec un point vert (activé) ou rouge (coupé). Clic : sa page à droite.
- [ ] Clic droit sur un addon de la liste : il s'active ou se coupe, le point change de couleur.
- [ ] Maj+clic sur Livres de bibliothèque, Quêtes du groupe, Rapport d'erreurs ou Sacs rangés : son panneau s'ouvre.
- [ ] En-tête d'une page : icône, nom, description, et l'interrupteur général « Activé / Coupé ».
- [ ] Les onglets : un par section ; l'onglet choisi est souligné en doré. Sacs rangés et Quêtes auto en ont beaucoup : ils passent sur deux lignes sans se chevaucher.
- [ ] Les interrupteurs basculent (vert à droite = activé) et l'effet est immédiat.
- [ ] Addon coupé : ses options sont grisées. Une option qui dépend d'une autre est grisée tant que l'autre est coupée.
- [ ] Les curseurs (taille de la flèche du GPS, écart de niveau de Sacs rangés) : glisser, molette, valeur affichée.
- [ ] Une aide sur plusieurs lignes ne chevauche pas l'option suivante.
- [ ] Un onglet long défile à la molette, avec sa barre de défilement.
- [ ] Les boutons d'action en bas de la page (Ranger maintenant, Balise ici, Choisir la touche…).
- [ ] Les onglets de listes : Marchand auto « Listes », Butin rapide « Objets ignorés », Quêtes auto « Listes », GPS « Balises », Familier « Nourriture », Carnet « Sessions », Métiers auto « Outils », Montures « Touche », Rapport d'erreurs « En direct ».
- [ ] Glisser un objet du sac dans une liste, le retirer avec la croix.
- [ ] Recherche en haut : taper « fleche » liste les réglages de plusieurs addons ; un clic mène au bon addon et au bon onglet.
- [ ] Les commandes (/sr options, /gps, /qa…) ouvrent la fenêtre directement sur le bon addon.
- [ ] Échap > Options > AddOns : le bouton « Ouvrir les réglages » marche aussi.

## Sacs rangés

- [ ] B ouvre puis referme le sac rangé ; le marchand l'ouvre tout seul et le referme quand tu le quittes.
- [ ] Clic droit sur une potion : elle se boit, sans le message « fonction protégée ».
- [ ] Clic droit sur une pièce d'équipement : elle s'équipe. Chez un marchand : elle se vend.
- [ ] Boire une potion depuis le sac pendant un combat.
- [ ] Section « À équiper » avec un objet vraiment meilleur : la flèche verte, la raison, « remplace : … », le clic droit pour équiper.
- [ ] Section « Métiers » : canne à pêche et couteau à dépecer (déjà vu, à reconfirmer après les dernières versions).
- [ ] Le livre de bibliothèque est rangé dans « Quête » (déjà vu, à reconfirmer).
- [ ] Bulles d'objets : la ligne verte « Mieux pour <spécialisation> » sur une récompense de quête, un objet de marchand et un butin. Rien sur un objet moins bon ou que tu ne peux pas porter.
- [ ] Section « Tu ne peux pas le porter » : équipement pas lié que tu ne peux pas porter, ou seulement trop haut en niveau.
- [ ] Section « À vendre » : les gris, et l'équipement lié que ta classe ne peut pas porter.
- [ ] Bulle d'un objet de ces sections : « Rangé ici : … » avec la raison.
- [ ] Équipement moins bon que ce que tu portes : flèche rouge vers le bas, et « Moins bon que … » dans la bulle.
- [ ] Apparence « cadre du jeu » et nouveau visuel.
- [ ] Retail : le sac rangé et ses cases (tout n'a été vu que sur Forever).
- [ ] Barre Ranger, Analyse et Banque collée au sac du jeu, quand le sac rangé est décoché.

## Butin rapide

- [ ] Touche d'interaction sur les cadavres : la même touche que la récolte de Métiers auto, sans couper la récolte.
- [ ] Liste « Objets à ne jamais ramasser » (dépôt, croix).
- [ ] Couper l'addon pendant qu'une fenêtre de butin est ouverte : la fenêtre redevient visible.

## Courrier (nouveau)

- [ ] La barre apparaît sous la boîte aux lettres, bien placée.
- [ ] « Tout récupérer » : la barre de progression avance et tout l'or et les objets arrivent.
- [ ] « Or seulement » : l'or des ventes est pris, les objets restent dans la boîte.
- [ ] Cases à cocher devant les courriers, puis « Les cochés ».
- [ ] Un contre-remboursement est laissé de côté.
- [ ] Sacs pleins : l'addon s'arrête avec un message.
- [ ] « Arrêter » pendant la récupération.

## GPS (nouveau)

- [ ] `/gps etat` (ou la ligne « En ce moment » des réglages) dit ce que suit la flèche, ou pourquoi elle est cachée.
- [ ] `/way 45.2 67.8 Test` : la flèche apparaît, avec le titre, la distance et le temps restant quand tu avances.
- [ ] La flèche tourne dans le bon sens et devient verte quand tu marches droit vers la balise.
- [ ] `/way Hurlevent 60 70` depuis Elwynn : la flèche montre une balise dans une autre zone.
- [ ] Ctrl + clic droit sur la carte du monde : une balise apparaît à cet endroit.
- [ ] L'épingle du jeu (carte et minimap) suit la balise suivie.
- [ ] Arrivé à moins de 10 m : un son, la balise disparaît, la suivante prend le relais.
- [ ] La flèche est grosse au départ ; le curseur « Taille de la flèche » (60 à 300 %) la change aussitôt.
- [ ] Clic droit sur la flèche : la balise est retirée. Glisser la flèche, puis « Replacer la flèche ».
- [ ] Réglages : la liste des balises (la suivie marquée d'un « > »), la croix, « Balise ici », « Tout effacer ».
- [ ] `/reload` : les balises sont toujours là.
- [ ] Livres de bibliothèque : « Balise vers le livre le plus proche » passe par le GPS.
- [ ] Sans aucune balise : la flèche montre l'objectif de la quête suivie (celle cliquée dans le suivi des objectifs), avec son titre.
- [ ] Plusieurs quêtes suivies : cliquer une quête dans le suivi des objectifs la sélectionne, et la flèche suit celle-là (comme TomTom).
- [ ] Quête finie : la flèche montre le PNJ à qui la rendre (« Rendre : … »).
- [ ] Quête dans une autre zone : la flèche passe par le chemin du jeu (portail, bateau) quand il y en a un.
- [ ] Une épingle posée à la main sur la carte du jeu : la flèche la suit, avant la quête.
- [ ] Poser une balise `/way` : la flèche la suit, puis revient à la quête quand la balise est atteinte.
- [ ] Si TomTom est encore installé : vérifier qui répond à `/way` (le désactiver pour ne garder que le nôtre).

## Enchères (nouveau)

- [ ] À l'hôtel des ventes, le panneau « Enchères » apparaît à droite de la fenêtre du jeu.
- [ ] « Relever les prix » : « Le jeu prépare la liste… », puis le pourcentage de dépouillement, puis « relevé fini : N objets ». L'écran ne doit pas geler.
- [ ] Un second clic avant 15 minutes : message « encore N min ».
- [ ] Bulle d'un objet (sac, butin) : la ligne « Enchères » avec le prix et son âge.
- [ ] Liste de courses : taper un nom puis « Ajouter » (ou Entrée), glisser un objet du sac dans la zone.
- [ ] Clic sur une ligne de la liste : l'onglet Acheter s'ouvre avec la recherche lancée.
- [ ] `/reload` : les prix et la liste sont gardés.
- [ ] Butin rapide : la ligne « Hôtel des ventes » du bilan de farm utilise nos prix.
- [ ] Forever : vérifier que l'hôtel des ventes y a bien le relevé complet (sinon, le dire).

## Barres de vie (nouveau)

Afficher les barres des ennemis avec V si elles sont cachées. Si Threat Plates ou Plater est installé, le désactiver pour ce test.

- [ ] Les barres ont l'apparence du jeu (aucune couleur, aucun texte ajoutés quand les options sont décochées).
- [ ] Un monstre de quête : grand « ! » jaune tout en haut de sa barre.
- [ ] Un monstre qui fait tomber un objet de quête : « 2/6 » sous le « ! », avec l'icône de l'objet ; le chiffre monte quand tu ramasses.
- [ ] Un monstre à tuer pour une quête : « 3/10 » avec une petite épée.
- [ ] Quête finie : le « ! » et le chiffre disparaissent.
- [ ] Options à essayer (réglages /bv) : couleur selon la menace, pourcentage, marques rare/élite, cible plus grande.
- [ ] En donjon : pas d'erreur (le jeu peut cacher la menace et la bulle des monstres).
- [ ] Après un combat : aucun message « fonction protégée » ni « taint » dans BugSack.

## Montures (nouveau)

- [ ] Sans aucune monture (ton chasseur actuel) : pas de bouton à l'écran ; la touche dit « tu n'as pas encore de monture ». Le bouton apparaît avec ta première monture.
- [ ] Réglages /montures : « Choisir la touche », appuyer sur une touche, elle s'affiche en vert.
- [ ] La touche au sol : une monture terrestre ; réappuyer : tu descends.
- [ ] Là où on peut voler : une volante. Dans l'eau : une aquatique (si tu en as une).
- [ ] « Seulement mes favorites » : seulement celles marquées d'une étoile dans le journal des montures.
- [ ] Le bouton à l'écran : clic pour monter, glisser pour le déplacer, clic droit pour les réglages.
- [ ] En combat : message « pas de monture en combat », sans erreur.

## Confort (nouveau)

- [ ] Ton frère t'invoque : accepté tout seul, message dans le chat.
- [ ] Ton frère te ressuscite : accepté tout seul.
- [ ] Ton frère (ami ou guilde) t'invite en groupe : accepté ; un inconnu : la fenêtre reste.
- [ ] Un inconnu te provoque en duel : refusé tout seul.
- [ ] Caméra plus loin : tu peux dézoomer davantage ; décocher remet comme avant.
- [ ] Masquer les griffons : ils disparaissent de la barre d'action (sur Forever et Retail).

## Familier du chasseur (nouveau)

- [ ] Avant d'avoir un familier (sort « Appel du familier » pas appris) : aucune alerte. Elles commencent une fois le sort appris.
- [ ] Renvoyer le familier hors ville : alerte « Ton familier n'est pas appelé » ; le bouton l'appelle.
- [ ] Familier mort : alerte et bouton « Ressusciter le familier ».
- [ ] La croix ferme l'alerte ; elle ne revient que si la situation change (familier appelé puis renvoyé, mort…).
- [ ] L'alerte se déplace en la faisant glisser ; « Replacer l'alerte » dans les réglages la remet en haut.
- [ ] Forever : le jeu donne-t-il l'humeur du familier ? Si oui, alerte « a faim » et le bouton « Nourrir » avec une nourriture qu'il aime.
- [ ] Liste « Nourriture qu'il aime » dans les réglages : glisser sa viande, elle passe en premier.
- [ ] En ville (auberge, capitale) : pas d'alerte « pas appelé ».
- [ ] Pas d'erreur « fonction protégée » quand l'alerte change juste après un combat.

## Plus anciens, jamais confirmés

- [ ] Carnet de session : « niveau max » sur un personnage au plafond (Naincailloux, Retail).
- [ ] Alerte rare : l'alerte des coffres et trésors.
- [ ] Métiers auto : la flèche vers le filon connu le plus proche, et l'alerte « filon pas fini ».
- [ ] Métiers auto : avec un personnage dépeceur (sans minage ni herboristerie), aucune flèche de minerai ; un herboriste ne voit que les herbes.
- [ ] Métiers auto : ouvrir un coffre ne crée pas de nouvel « endroit connu ».
- [ ] Quêtes auto : la récompense choisie seule (journal dans `/re`), le partage de quêtes avec le groupe.
- [ ] Quêtes du groupe : le panneau en groupe avec ton frère.
- [ ] Marchand auto : le rachat du stock.
