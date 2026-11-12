# Tests à faire en jeu

Tout ce qui est codé mais pas encore vérifié dans le jeu. Les simulations hors jeu (`tests/`) passent toutes, mais elles ne voient ni l'affichage ni les blocages du jeu.

Pour chaque test : coche la case quand c'est bon. Si quelque chose cloche, fais `/reload`, puis dis « regarde » : les erreurs sont lues directement dans les fichiers du jeu.

Avant de commencer :
- [ ] Sur le poste de développement, rien à mettre à jour (les addons sont reliés au dossier de travail) : `/reload` suffit. WowUp ne sert qu'aux amis.
- [ ] Désactiver Pawn, pour ne voir que notre avis sur les objets.
- [ ] Vérifier que BugSack est actif sur Forever.

## Vérifié en jeu le 12/11/2026 (Forever, druide niveau 3, essais pilotés par Claude)

Après-midi du 12/11 : fenêtre de réglages commune (engrenage, clic droit, Maj+clic, recherche, curseurs, partage des réglages), Suivi des quêtes (clic, bulle, rangement, repli), Tenues (enregistrer, /tenue com, supprimer), Conseiller (6 onglets ; corrigé en 0.3.1 : talent annoncé « à prendre » sans point libre, et druide sans forme sans sort d'attaque), GPS (balise, flèche verte, arrivée, clic droit) et trois panneaux sombres cochés plus bas. Piège de l'outil : un clic instantané n'est pas toujours pris par le jeu (engrenage), un appui de 0,15 s l'est. Barres de vie et Butin rapide attendent une quête de monstres.

Aucune erreur des addons dans BugGrabber pendant toute la série.

- [x] Fenêtres déplaçables : personnage, grimoire, carte, options, menu du jeu se déplacent par leur barre de titre (après le correctif 0.1.4 : poignée sur la couche au-dessus de la fenêtre).
- [x] Fenêtres déplaçables : place gardée à la fermeture et à la réouverture (personnage, carte) ; deux fenêtres ouvertes ensemble gardent chacune leur place ; croix de fermeture toujours cliquable ; infobulle de la barre de titre ; clic droit, « Remettre à sa place d'origine ».
- [ ] Fenêtres déplaçables : Ctrl + molette (marche chez Valentin ; mon outil n'envoie pas Ctrl avec la molette), glisser en combat, marchand, courrier, banque.
- [x] Sacs rangés : B ouvre le sac ; plus aucune lueur bleue « nouvel objet » après `/reload` (0 sur 4 cases).
- [x] Réglages communs : la fenêtre liste les 23 addons ; « Quoi de neuf » ; la recherche « taille » trouve 6 réglages et un clic mène à la bonne page (GPS) ; l'icône de Confort s'affiche (0.3.2).
- [x] GPS : `/way 45 60 Essai GPS` montre la flèche avec la distance ; `/way effacer` la retire.
- [x] Quêtes disponibles : `/qd etat` reconnaît les 6 capitales (positions justes) ; sur l'Île de Zéphras (propre à Forever) 0 quête, normal ; en Forêt d'Elwynn, un « ! » montre « [1] Menace intérieure » en français.
- [x] Dialogues de quête : `/dial test` : bandeau, Espace tourne les pages et accepte, récompenses listées au-dessus du bandeau, choix au clic, « Terminer la quête », Échap ferme.
- [ ] Dialogues de quête : les chiffres pour choisir (mon outil envoie « ^ » au lieu de « 3 » : à essayer avec ton clavier), et un vrai PNJ.
- [x] Tenues : `/tenue` ouvre la fenêtre ; enregistrer une tenue (9 pièces, marquée portée) ; « Mettre » (déjà portée) ; supprimer avec « Sûr ? ».
- [x] Conseiller : `/cs` s'ouvre et lit la classe et le niveau.
- [x] Dialogues, style compact (comme Immersion) avec un vrai PNJ : visage en 3D, survol et clic d'une réponse, fiche de quête page par page, Refuser, rendu d'une quête et enchaînement sur la suivante.
- [x] Dialogues 0.3.5 : visage chargé par numéro de créature, même angle depuis deux endroits ; bouton « Fenêtre du jeu » lisible.
- [ ] Dialogues : choix parmi plusieurs récompenses sur une vraie quête, touches 1 à 9 au vrai clavier.
- [x] Butin rapide 0.7.2 : durée du bilan = temps de jeu (0 puis 1 min après une minute et un /reload).
- [x] Carnet de session 0.8.0 : cadre « Session » réuni, repli en une ligne, onglets Personnage / Farm, bilan séparé caché.
- [x] Quêtes disponibles 0.3.0 : une quête de Forever apprise en parlant au PNJ (Yala), montrée sur la carte et la minimap.
- [ ] Quêtes disponibles : sens des « ! » de la minimap pour une quête éloignée ; partage des quêtes apprises au groupe.
- [x] Second écran (Fenêtres 0.2.2 + outils/second-ecran.ps1) : fenêtre du jeu étirée sur l'écran de gauche et le principal, jeu et interface entiers sur le principal, fenêtre du personnage posée et gardée sur l'écran de gauche, glisser sur l'écran principal sans saut.
- [ ] Second écran depuis l'addon (Fenêtres 0.3.0) : « Revenir à un seul écran » remet le plein écran fenêtré ; « Passer au second écran » avec `outils/second-ecran.ps1 -Surveiller` en fond étale la fenêtre seule.
- [ ] Second écran : glisser une fenêtre d'un écran à l'autre avec ta souris (mon outil ne sait pas le faire), et le combat (rien ne doit bouger pendant).

## La fenêtre de réglages commune (refaite le 10/11)

- [x] Clic sur l'engrenage de la minimap : la fenêtre « Addons de Valentin » s'ouvre, sans erreur. Échap la ferme.
- [x] À gauche : les 18 addons, avec un point vert (activé) ou rouge (coupé). Clic : sa page à droite.
- [x] Clic droit sur un addon de la liste : il s'active ou se coupe, le point change de couleur.
- [x] Maj+clic sur Livres de bibliothèque, Quêtes du groupe, Rapport d'erreurs ou Sacs rangés : son panneau s'ouvre.
- [x] En-tête d'une page : icône, nom, description, et l'interrupteur général « Activé / Coupé ».
- [x] Les onglets : un par section ; l'onglet choisi est souligné en doré. Sacs rangés et Quêtes auto en ont beaucoup : ils passent sur deux lignes sans se chevaucher.
- [x] Les interrupteurs basculent (vert à droite = activé) et l'effet est immédiat.
- [x] Addon coupé : ses options sont grisées. Une option qui dépend d'une autre est grisée tant que l'autre est coupée.
- [x] Les curseurs (taille de la flèche du GPS, écart de niveau de Sacs rangés) : glisser, molette, valeur affichée.
- [ ] Une aide sur plusieurs lignes ne chevauche pas l'option suivante.
- [ ] Un onglet long défile à la molette, avec sa barre de défilement.
- [ ] Les boutons d'action en bas de la page (Ranger maintenant, Balise ici, Choisir la touche…).
- [ ] Les onglets de listes : Marchand auto « Listes », Butin rapide « Objets ignorés », Quêtes auto « Listes », GPS « Balises », Familier « Nourriture », Carnet « Sessions », Métiers auto « Outils », Montures « Touche », Rapport d'erreurs « En direct ».
- [ ] Glisser un objet du sac dans une liste, le retirer avec la croix.
- [x] Recherche en haut : taper « fleche » liste les réglages de plusieurs addons ; un clic mène au bon addon et au bon onglet.
- [x] Les commandes (/sr options, /gps, /qa…) ouvrent la fenêtre directement sur le bon addon.
- [ ] Échap > Options > AddOns : le bouton « Ouvrir les réglages » marche aussi.
- [ ] Tout en haut de la liste de gauche : « Quoi de neuf », sans point vert ni rouge, avec l'icône d'une note ; les addons sont en dessous, un peu plus bas.
- [ ] À la première connexion après la mise à jour : un seul message dans le chat « Addons de Valentin : il y a du nouveau… » (pas 17), quelques secondes après l'arrivée dans le jeu, et une pastille dorée sur « Quoi de neuf » (et la ligne « Il y a du nouveau » dans la bulle de l'engrenage de la minimap).
- [ ] Clic sur « Quoi de neuf » : les nouveautés s'affichent dans un cadre qui défile à la molette, les plus récentes en premier, marquées « [nouveau] » (toutes, à la toute première mise à jour, quand aucune date vue n'existe) ; la pastille disparaît.
- [ ] `/reload` : plus de message, plus de pastille. Les nouveautés s'ouvrent toujours quand on clique sur l'entrée.
- [x] « Partager mes réglages », sous « Quoi de neuf » : deux cadres (mes réglages à copier, réglages reçus à coller) ; un clic dans le premier sélectionne tout le texte (`VA1;GPS:…;SacsRanges:…`), Ctrl+C le copie, taper dedans ne le change pas. Le cadre grandit avec le texte et se fait défiler à la molette, sans couper la fin.
- [x] Changer un réglage (par exemple la taille de la flèche du GPS), coller l'ancien texte dans le second cadre, « Appliquer » : message vert « N réglage(s) appliqué(s) dans M addon(s) », et le réglage revient à l'ancienne valeur tout de suite, sans `/reload`.
- [x] Texte abîmé : retirer le début « VA1; » ou couper le texte au milieu d'un réglage, « Appliquer » : message rouge clair, rien n'est changé. Cadre vide : « Colle d'abord le texte reçu. »
- [ ] Les listes (objets ignorés de Butin rapide, balises du GPS, courses de Métiers auto) ne bougent pas après « Appliquer ».
- [x] En haut à droite de la page de chaque addon, sous l'interrupteur général : « Réglages propres à ce personnage » avec son petit interrupteur (bulle d'aide au survol), sans chevaucher la description ni les onglets (Sacs rangés et Quêtes auto : onglets sur deux lignes).
- [ ] Activer l'interrupteur sur un addon, changer un réglage, puis se connecter avec un autre personnage : l'autre personnage garde les réglages communs. Revenir sur le premier : il retrouve les siens. Couper l'interrupteur : il retrouve ceux du compte.
- [ ] Carnet de session et Butin rapide (qui ont aussi une sauvegarde par personnage) : session, historique et bilan de farm toujours là après la mise à jour, interrupteur « propres à ce personnage » sans effet sur eux.
- [ ] Au premier lancement après la mise à jour, aucun réglage n'a changé sur aucun personnage (rien ne bouge tant qu'on n'active pas l'interrupteur).

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
- [ ] Section « À vendre » : les gris, et l'équipement lié que ta classe ne pourra JAMAIS porter (ligne rouge « Classes : … » ou « Races : … » d'une autre classe ou race, ou armure d'un type que ta classe ne portera jamais : plaque pour un mage, par exemple). Une arme ou une armure « pas apprise » (mailles ou plaques avant le niveau 40, arme d'un maître d'armes) ou trop haute en niveau reste dans « Tu ne peux pas le porter », même liée.
- [ ] Bulle d'un objet de ces sections : « Rangé ici : … » avec la raison.
- [ ] Équipement moins bon que ce que tu portes : flèche rouge vers le bas, et « Moins bon que … » dans la bulle.
- [ ] Apparence « cadre du jeu » et nouveau visuel.
- [ ] Option « Banque rangée par catégories » (grisée si le sac par catégories est décoché) : à l'ouverture de la banque, une seconde fenêtre apparaît à gauche du sac, avec les mêmes sections, le même style, et se ferme avec la banque ; la fenêtre de banque du jeu reste visible.
- [ ] Banque rangée : le clic droit sur un objet de la banque le met dans les sacs ; déposer un objet sur la case « Cases libres » le range en banque ; glisser un objet d'une case à l'autre marche ; pas de message « fonction protégée ».
- [ ] Banque rangée : la croix de la fenêtre la ferme pour de bon (elle ne revient pas quand tu bouges un objet) jusqu'à la prochaine ouverture de la banque. Banque très pleine : la fenêtre ne dépasse pas 80 % de la hauteur de l'écran, elle prend plus de colonnes (jusqu'à 24).
- [ ] Banque rangée : tous les sacs de banque achetés y sont (Forever), ou tous les onglets du personnage (Retail) ; la recherche en haut grise ce qui ne correspond pas ; l'option décochée, la seconde fenêtre disparaît tout de suite.
- [ ] Banque rangée sur Retail : noter si les cases répondent bien (incertain : les onglets de banque récents n'ont pas été vérifiés) ; sinon décocher l'option, la banque du jeu fonctionne toujours seule.
- [ ] Retail : le sac rangé et ses cases (tout n'a été vu que sur Forever).
- [ ] Barre Ranger, Analyse et Banque collée au sac du jeu, quand le sac rangé est décoché.
- [ ] Panneau d'analyse (`/sr`) : fond sombre, bordure dorée, titre doré avec sa croix ; la croix et Échap le ferment ; il se déplace toujours à la souris.

Composants par extension (0.14.0, Retail seulement, rien de testé en jeu) :

- [ ] Sac par catégories : la section Composants a un sous-titre par extension, Midnight en tête, avec le bon nombre d'objets ; un composant ancien (minerai de cuivre, tissu de lin) est bien sous « Classique ».
- [ ] Option « Regrouper les anciennes extensions » : Midnight et The War Within gardent leur sous-titre, le reste passe sous « Anciennes extensions ».
- [ ] Option « Composants rangés par extension » décochée : la section Composants redevient un seul bloc. Sur Forever : un seul bloc, pas de bouton « Déposer ».
- [ ] Banque ouverte, « Banque rangée par catégories » cochée : deux boutons « Personnage » et « Bataillon » en haut de la banque rangée ; « Bataillon » montre la banque de bataillon, avec les mêmes sous-titres par extension.
- [ ] Clic droit sur un objet de l'onglet Bataillon : le jeu le met dans tes sacs, sans message « fonction protégée ».
- [ ] Banque ouverte : le bouton « Déposer » apparaît sur le sac ; son panneau liste les extensions présentes, les anciennes cochées d'office ; le nombre de piles sur le bouton suit les cases.
- [ ] « Déposer N piles » vers Personnage : les piles partent une par une, le bouton compte (3/12), bilan dans le chat ; aucun message « fonction protégée » ni objet resté collé à la souris.
- [ ] Même chose vers Bataillon ; un composant lié au personnage reste dans le sac et le bilan le dit.
- [ ] Fermer la banque pendant un dépôt : arrêt net, bilan « la banque s'est fermée ». Banque pleine : arrêt, bilan « la banque est pleine ».

## Marchand auto : équipement lié vendu (nouveau)

- [ ] Option « Vendre aussi l'équipement lié que tu ne peux pas porter » : grisée si Sacs rangés est désactivé ou absent, cochable sinon (coupée par défaut).
- [ ] Chez un marchand, option cochée, avec dans les sacs un gris et une pièce liée que ta classe ne peut pas porter : les deux sont vendus, et le bilan nomme la pièce et dit combien elle a rapporté.
- [ ] Option cochée mais « Vendre les objets gris » décochée : seule la pièce liée est vendue.
- [ ] Une pièce épique inutilisable n'est jamais vendue, ni un objet de la liste « Gris à garder », ni une pièce encore remboursable (achetée tout juste avec des points d'honneur ou autre).
- [ ] Le bilan ne compte une pièce que si elle a vraiment quitté le sac ; avec seulement de l'équipement vendu, pas de ligne « 0 objet(s) gris vendu(s) ».
- [ ] Maj enfoncé en ouvrant le marchand : rien n'est vendu.
- [ ] Option cochée, vue par catégories de Sacs rangés décochée : la vente marche quand même.
- [ ] Pas de message « fonction protégée » ni de pièce équipée par erreur pendant la vente.

## Butin rapide

- [ ] Touche d'interaction sur les cadavres : la même touche que la récolte de Métiers auto, sans couper la récolte.
- [ ] Liste « Objets à ne jamais ramasser » (dépôt, croix).
- [ ] Couper l'addon pendant qu'une fenêtre de butin est ouverte : la fenêtre redevient visible.
- [ ] Alerte « sacs pleins » et bilan de farm (`/br bilan`) : fond sombre, bordure dorée, croix qui marche (la croix du bilan le décoche dans les réglages) ; le bilan garde sa place après un `/reload`.

## Courrier (nouveau)

- [ ] La barre apparaît sous la boîte aux lettres, bien placée.
- [ ] « Tout récupérer » : la barre de progression avance et tout l'or et les objets arrivent.
- [ ] « Or seulement » : l'or des ventes est pris, les objets restent dans la boîte.
- [ ] Cases à cocher devant les courriers, puis « Les cochés ».
- [ ] Un contre-remboursement est laissé de côté.
- [ ] Sacs pleins : l'addon s'arrête avec un message.
- [ ] « Arrêter » pendant la récupération.
- [ ] La barre sous la boîte aux lettres garde son fond sombre et sa bordure dorée (même visuel qu'avant).
- [ ] Onglet Envoyer : un petit bouton à droite du champ « À » ouvre la liste. Premier lancement : elle ne montre que « Compléter ». Après une connexion avec un autre personnage du royaume, il apparaît dans « Mes personnages » (et pas le personnage connecté).
- [ ] Taper « Al » dans le champ puis ouvrir la liste : la ligne verte « Compléter : … » remplit le champ avec le nom complet. Un clic sur un personnage ou un ancien destinataire remplit le champ, sans rien envoyer.
- [ ] Envoyer un courrier à quelqu'un : il apparaît ensuite dans « Derniers destinataires » (8 au plus, le plus récent en haut, sans doublon).
- [ ] La liste se referme en changeant d'onglet ou en fermant la boîte. Option « Destinataires rapides » décochée : le bouton disparaît.
- [ ] Pièce jointe en un clic : onglet Envoyer ouvert, clic droit sur un objet du sac du jeu l'ajoute en pièce jointe. Pareil sur une case du sac rangé de Sacs rangés (ce sont de vraies cases du jeu). Si ça ne marche pas sur le sac rangé, le dire : il faudra un crochet à nous.
- [ ] Le rappel « Astuce : clic droit… » apparaît en bas de la liste, et disparaît avec l'option « Rappel : clic droit… » décochée.
- [ ] Fin d'une récupération : une ligne « terminé (X po, N objet(s)) » puis, s'il en reste, « courriers laissés de côté : 1 en contre-remboursement (jamais payé), … ». Avec les sacs pleins : « N faute de place dans les sacs ».
- [ ] Couper l'addon (interrupteur des réglages) en pleine récupération : « Courrier coupé (…) » avec ce qui a été pris, pas « boîte fermée ».
- [ ] Fermer la boîte en pleine récupération : « boîte fermée (…) » avec ce qui a été pris. Option « Bilan » décochée : retour à l'ancien message court, sans ligne « laissés de côté ».

## GPS (nouveau)

- [x] `/gps etat` (ou la ligne « En ce moment » des réglages) dit ce que suit la flèche, ou pourquoi elle est cachée.
- [x] `/way 45.2 67.8 Test` : la flèche apparaît, avec le titre, la distance et le temps restant quand tu avances.
- [x] La flèche tourne dans le bon sens et devient verte quand tu marches droit vers la balise.
- [ ] `/way Hurlevent 60 70` depuis Elwynn : la flèche montre une balise dans une autre zone.
- [ ] Ctrl + clic droit sur la carte du monde : une balise apparaît à cet endroit.
- [ ] L'épingle du jeu (carte et minimap) suit la balise suivie.
- [x] Arrivé à moins de 10 m : un son, la balise disparaît, la suivante prend le relais.
- [ ] La flèche est grosse au départ ; le curseur « Taille de la flèche » (60 à 300 %) la change aussitôt.
- [ ] Clic droit sur la flèche : la balise est retirée. Glisser la flèche, puis « Replacer la flèche ».
- [ ] Réglages : la liste des balises (la suivie marquée d'un « > »), la croix, « Balise ici », « Tout effacer ».
- [ ] `/reload` : les balises sont toujours là.
- [ ] Livres de bibliothèque : « Balise vers le livre le plus proche » passe par le GPS.
- [ ] Erreur corrigée en 0.6.2 : sans balise, poser une épingle à la main sur la carte du jeu (Ctrl + clic) : la flèche la suit (« Épingle de la carte »), sans erreur « GPS.lua:516: attempt to call a nil value » dans BugSack.
- [ ] Sans aucune balise : la flèche montre l'objectif de la quête suivie (celle cliquée dans le suivi des objectifs), avec son titre.
- [ ] Plusieurs quêtes suivies : cliquer une quête dans le suivi des objectifs la sélectionne, et la flèche suit celle-là (comme TomTom).
- [ ] Quête finie : la flèche montre le PNJ à qui la rendre (« Rendre : … »).
- [ ] Quête dans une autre zone : la flèche passe par le chemin du jeu (portail, bateau) quand il y en a un.
- [ ] Une épingle posée à la main sur la carte du jeu : la flèche la suit, avant la quête.
- [ ] Poser une balise `/way` : la flèche la suit, puis revient à la quête quand la balise est atteinte.
- [ ] Si TomTom est encore installé : vérifier qui répond à `/way` (le désactiver pour ne garder que le nôtre).
- [ ] Balises partagées, à deux joueurs en groupe avec GPS : poser une balise puis cliquer « Envoyer au groupe » (onglet Balises des réglages) : l'autre voit « balise : Titre (de Nom) » et la flèche la suit.
- [ ] `/way envoyer` envoie la balise suivie ; `/way envoyer tout` envoie toutes les balises (20 au plus), une toutes les 0,5 s, puis une ligne dit combien sont réellement parties. Seul en jeu : « tu n'es pas dans un groupe ». Sans balise : « aucune balise suivie à envoyer ».
- [ ] Renvoyer deux fois la même balise (ou une à moins de 0,5 % de distance) : aucun doublon chez l'autre. Une balise envoyée par soi-même ne revient jamais.
- [ ] Une balise reçue du groupe ne fait pas lâcher la balise que tu suis déjà (la flèche reste sur la tienne).
- [ ] Option « Accepter les balises de mon groupe » décochée chez l'autre : rien n'est ajouté. En raid et en groupe d'instance (recherche de groupe) : l'envoi passe aussi.
- [ ] Titre vide ou avec des accents : la balise arrive en « Balise (de Nom) » ou avec ses accents intacts. Aucune erreur dans BugSack, côté envoi comme côté réception.

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
- [ ] Le panneau à droite de l'hôtel des ventes garde son fond sombre, sa bordure dorée et son titre « Enchères » doré (même visuel qu'avant).
- [ ] Onglet Vendre, objet unique (arme, armure) déposé : le bloc « Mise en vente » donne le plus bas connu avec son âge et un prix conseillé arrondi à l'argent. « Mettre ce prix » remplit le champ d'achat immédiat du jeu quand il est affiché (sinon le champ de prix) ; la mise en vente reste un clic de ta part.
- [ ] Onglet Vendre, équipement ou cage de mascotte déposé : « Prix variable d'un exemplaire à l'autre : regarde les ventes en cours. », pas de prix conseillé ni de bouton.
- [ ] Onglet Vendre, produit en lot (étoffe, herbe) déposé : prix « l'unité », 1 cuivre sous le plus bas ; « Mettre ce prix » remplit le prix unitaire du jeu.
- [ ] Objet jamais relevé : « Pas de prix connu » et pas de bouton. Objet dont le plus bas est sous le prix du marchand : conseil au prix du marchand, avec la mention.
- [ ] Retirer l'objet, ou changer d'onglet : le bloc « Mise en vente » disparaît. Réglage « Le prix conseillé… » décoché : plus de bloc.
- [ ] Forever : vérifier que les cadres ItemSellFrame et CommoditiesSellFrame existent et que le champ se remplit (sinon, seul le texte du conseil doit rester, sans erreur dans BugSack).

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

## Conseiller (0.3.0 : onglet Compétences, maître de classe, rappels ; 0.2.2 : spécialisation lue dans les groupes de l'arbre)

À lancer sur le chasseur, puis sur le plus de classes possible (le plus utile : une classe à rotation de points de combo, voleur ou druide, et une classe à talents que tu as déjà pris). L'API des talents et des barres de Forever n'a été vérifiée que dans la documentation de Blizzard, jamais en jeu. Les noms français des talents et les identifiants de sorts viennent de Classic, de mémoire : ce que le jeu ne reconnaît pas doit se voir, jamais se deviner.

- [x] `/conseil` (ou `/cs`) ouvre la fenêtre : en-tête avec classe, niveau, race, spécialisation et situation ; les 6 onglets Talents, Rotation, Compétences, Équipement, Métiers, Race s'affichent sans erreur (BugSack).
- [ ] `/cs etat` : classe, spécialisation, situation, nombre de sorts connus. Si la spécialisation est « inconnue », noter ce que le jeu donne (Forever n'a peut-être pas de spécialisations au sens de Midnight). S'il y a des talents non reconnus, une deuxième ligne donne leurs noms.
- [ ] `/cs export` puis `/reload` : `ConseillerDB.export` dans `WTF\Account\<compte>\SavedVariables\Conseiller.lua` contient `noeuds` (nodeID, posX, posY, maxRanks, entrees avec spellID et nom) et `grimoire`. Si « configuration active introuvable », le jeu ne donne pas l'arbre : le noter. **Garder ce fichier : les vrais noms des talents servent à corriger les builds.**
- [ ] Forever, un seul arbre en trois groupes (0.2.2) : `/cs etat` affiche « points par groupe de talents : Sacré N, Protection N, Vindicte N ; spécialisation détectée : … ». La spécialisation doit être celle où tu as le plus de points (pas celle de GetSpecialization), et « aucune » en cas d'égalité ou de zéro point. Puis la ligne « build utilisé : … (N entrées) », « prochain talent : NOM (nœud N) » et le nombre de talents non reconnus avec leurs noms. Noter si les points par groupe sont faux (alors `GetGroupCurrencyInfo` ne se lit pas comme prévu).
- [x] Contour vert (0.2.2, validé en jeu le 10/11/2026 sur un paladin Vindicte de Forever) : fenêtre des talents ouverte, le talent « prochain » est entouré. Sinon `/cs etat` dit pourquoi : « bouton du talent introuvable dans la fenêtre » (noter ce message : le chemin vers le bouton est à corriger), fenêtre fermée ou introuvable, ou bouton caché.
- [ ] Onglet Talents, spécialisation différente de la conseillée (0.2.2) : une ligne grise « Tu es en Vindicte ; en groupe sans tank, Protection est conseillée » et « Le build ci-dessous est celui de ta spécialisation » ; le build montré est celui de ta spécialisation. `/cs export` écrit aussi `groupes` (groupID, displayName, orderIndex, depense) et `groupIDs` sur chaque nœud : à relire dans le fichier.
- [ ] Onglet Talents, build affiché pour chaque classe : la spécialisation conseillée et le « Pourquoi » s'affichent, puis « Prochain talent : … » (rang X sur Y) avec le bon talent de TA classe, et la ligne grise « Build croisé entre plusieurs guides, mis à jour le 10/11/2026 ». Passer par le bouton « Situation » (Seul, En groupe, Donjon, Raid) : le build et la spécialisation changent. Noter, pour chaque classe jouée : le prochain talent est-il bien le premier du build que le jeu laisse prendre ?
- [ ] Talents non reconnus : une ligne rouge « N talents du build n'ont pas été reconnus : fais /cs export… » avec leurs noms en gris. Noter combien, pour quelle classe, et surtout quels noms (client en français : un nom français mal retenu est compté ici, c'est attendu et corrigeable avec l'export). Si **tous** sont non reconnus : le message « aucun de ses talents n'a été reconnu » s'affiche, et c'est alors le nom de l'arbre ou la lecture de C_Traits qui est en cause, à noter.
- [x] Palier pas atteint : à un niveau bas, le prochain talent annoncé est bien un talent achetable maintenant (pas un talent d'un palier suivant) ; si plus rien n'est achetable, l'onglet dit « Le jeu ne permet pas de le prendre pour l'instant » et le bouton « Prendre ce talent » est grisé.
- [ ] « Prendre ce talent » : un rang est acheté sur le talent annoncé (hors combat), le talent suivant est annoncé ensuite ; le contour vert se pose sur ce talent dans la fenêtre des talents du jeu.
- [ ] Validation : après « talent pris », la fenêtre des talents du jeu ne montre plus de modifications en attente (le bouton « Appliquer » n'est pas à faire) ; si elle en montre, le message « talent acheté, mais le jeu a refusé de valider » doit être apparu. Dans une zone où les talents sont verrouillés, le bouton doit dire pourquoi au lieu d'acheter.
- [ ] Rotation, avec une cible attaquable, pour chaque classe jouée : un contour bleu pulse sur le bouton de la barre d'action du prochain sort. Le sort doit être posé sur une barre ; sinon l'onglet le dit. Vérifier l'ordre d'un combat : la rotation ne propose que des sorts d'attaque, jamais un soin ni un défensif, même vie basse ; une classe de mêlée à points de combo (voleur, druide en chat) propose le finisseur à 5 points (la condition `pointsCombo`).
- [ ] Alerte d'urgence : réglage « Signaler le sort d'urgence quand ta vie est basse » (coupé par défaut). Coché, vie basse, avec une cible attaquable : un contour ROUGE se pose sur le bouton du sort de soin ou de défense posé sur ta barre, et le contour bleu reste sur le sort d'attaque. Décoché : plus de rouge. Noter si la vie est lisible en combat (sinon rien ne s'allume, c'est voulu).
- [ ] Onglet Rotation : sous la liste, une ligne grise « En cas de danger : … » nomme tes sorts d'urgence. Spécialisation de soins (Sacré, Discipline, Restauration) : la phrase « Spécialisation de soins : il n'y a pas d'ordre fixe… » puis une courte liste de sorts d'attaque, et les conseils « à savoir » dessous.
- [ ] Rotation du druide : en chat, les sorts de chat s'allument et ceux d'ours sont sautés ; en ours l'inverse (un sort d'une autre forme n'est pas « prêt »). Rotation du mage : l'armure (glace, mage ou givre) n'est conseillée que si aucune n'est active.
- [ ] En combat : le contour continue de bouger sans erreur ni message « taint » ou « fonction protégée » dans BugSack.
- [ ] Passage au mode C : si le jeu cache les temps de recharge en combat, un seul message dit que Conseiller passe à la liste, et le cadre « Rotation » apparaît (déplaçable, « Replacer la liste de priorité » dans les réglages le remet). Noter si cela arrive vraiment, et dans quels combats.
- [ ] `/cs mode a`, `/cs mode c`, `/cs mode auto` : le mode change tout de suite ; le bouton « Changer de mode » de l'onglet Rotation aussi.
- [ ] Rotation des 9 classes : aucune classe ne dit plus « Rotation pas encore écrite » ; l'onglet liste l'ordre de priorité de ta spécialisation, avec les conseils « à savoir » dessous. Noter les sorts qui manquent dans la liste alors que tu les connais (identifiant ou nom français faux) : c'est la liste à corriger.
- [ ] Changement de situation : entrer en groupe (sans tank ou sans soigneur) : un message dit quel rôle manque ; l'onglet Talents montre le bloc « Ton groupe » avec les rôles ; entrer en donjon : la situation passe à « Donjon » ; en sortir : « Seul ». Le bouton « Situation » en haut à droite montre les autres situations sans bouger.
- [ ] Onglet Compétences **avant** la première visite chez le maître (0.3.0) : « Va voir ton maître de classe une fois : je retiendrai sa liste. » (sur Retail : « il n'y a pas de maître de classe »). Les blocs « À mettre sur ta barre » et « Tu peux t'en passer » s'affichent déjà, et un sort de la rotation que tu connais est « Sur ta barre » ou « Pas sur ta barre » selon ta barre (noter si c'est faux : sort dans une macro, barre cachée, page de barre). Si tu as déjà visité le maître et que l'onglet dit quand même d'y aller : noter ce que donne `/cs etat` (ligne « maître de classe : … »).
- [ ] Visite chez le maître de classe (0.3.0) : ouvrir sa fenêtre, la refermer, ouvrir l'onglet Compétences. La liste est retenue (`/cs etat` : « liste retenue le … N services ») et l'onglet montre les sorts que tu ne connais pas et que ton niveau permet, classés « Indispensable », « Utile », « Peut attendre », avec la raison, le prix, le total des indispensables, et « N autres sorts demandent un niveau plus haut ». Vérifier que les « Indispensable » sont bien les sorts de ta rotation (onglet Rotation). Un maître de métier ou de familier ne doit rien changer à la liste. Noter si la liste est incomplète : les filtres de la fenêtre du maître (Disponible, Indisponible, Déjà appris) changent ce que le jeu donne à l'addon.
- [ ] Marques dans la fenêtre du maître (0.3.0) : un petit carré doré à côté des sorts indispensables, argenté à côté des sorts utiles, rien sur les autres ni sur les sorts déjà appris. Faire défiler la liste : les marques suivent les bonnes lignes (un court retard de l'ordre du dixième de seconde est normal). Apprendre un sort : sa marque disparaît. Réglage « Marquer les sorts utiles dans la fenêtre du maître de classe » décoché : plus de marque. Aucune erreur ni message « taint » dans BugSack. `/cs etat` dit « marques … » (posées, fenêtre fermée, liste introuvable…) : noter si la liste défilante n'est pas trouvée.
- [ ] Message de niveau (0.3.0) : monter d'un niveau avec une liste retenue qui contient un sort indispensable de ce niveau : « Niveau N : 2 sorts indispensables chez ton maître de classe (38 pa). » Sans liste retenue, à chaque niveau pair : « Niveau N : pense à passer chez ton maître de classe. » Aucun message sur Retail. Réglage « Rappeler le maître de classe à la montée de niveau » décoché : plus de message.
- [ ] Message de sort absent de la barre (0.3.0) : enlever de ta barre un sort de ta rotation que tu connais, puis `/reload` ou changer de barre : quelques secondes après, « Frappe sacrée fait partie de ta rotation mais n'est sur aucune barre. » Un seul message par sort et par session, aucun en combat (il vient à la fin du combat), pas plus de trois d'un coup. Pas de message pour un sort de repli (Sceau de piété quand tu as le Sceau de fureur) ni pour un sort que tu as sur une barre cachée ou dans un sous-menu : noter les faux messages. Réglage « Prévenir quand un sort de la rotation n'est sur aucune barre » décoché : plus de message.
- [ ] Équipement : l'ordre des statistiques de ta spécialisation ; `/run print(Conseiller_OrdreStats()[1])` répond une clé de statistique.
- [x] Métiers : trois propositions pour ta classe, et « À faire maintenant » avec tes métiers (compétence, palier suivant).
- [x] Race : tes capacités de race, actives et passives.
- [ ] Réglages « Conseiller » dans la fenêtre commune : interrupteurs, mode, épaisseur du contour, boutons « Ouvrir le Conseiller » et « Exporter mon arbre de talents ».

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
- [ ] L'alerte du familier a le même visuel sombre et doré que les autres fenêtres (texte toujours rouge), se déplace à la souris, et sa croix la ferme comme avant.

## Fenêtres au visuel sombre et doré

Même fond sombre, même bordure dorée et titre doré que la fenêtre de réglages (le jeu ne montre plus le cadre bleu-gris d'origine).

- [ ] Carnet de session (`/carnet`) : fond sombre, titre doré, croix ; il garde sa place après un `/reload` et se déplace toujours.
- [ ] Liste de courses de Métiers auto (`/mt courses 5 <recette>`) : fond sombre, titre doré, la croix la décoche dans les réglages, la place est gardée.
- [x] Panneau de Livres de bibliothèque (`/livres`, Forever) : fond sombre, titre doré, croix, Échap le ferme.
- [x] Panneau de Quêtes du groupe (`/qg`) : fond sombre, titre doré, croix, Échap le ferme.
- [x] Rapport d'erreurs (`/re`) : fond sombre, titre doré, croix, Échap le ferme, le texte reste sélectionnable et copiable.
- [ ] Sur chacune : rien ne chevauche le titre, le texte reste lisible, aucune erreur Lua (BugSack) à l'ouverture, en combat ou non.
- [ ] Retail et Forever : même rendu (si le cadre n'a pas de fond, un cadre enfant le dessine derrière).

## Suivi des quêtes (nouveau)

À faire en premier : `/reload`, puis regarder BugSack. Le suivi du jeu doit avoir disparu et notre panneau « Quêtes » être à droite.

- [ ] `/sq genre` : pour chaque quête suivie, le chat donne la rubrique, le tag, la classification et le genre retenu. **Me donner ce texte** (ou dire « regarde ») : il sert à régler le tri automatique, surtout « Principal », « Classe » et « Métiers ».
- [ ] Les sections sont dans l'ordre : À rendre, Principal, Général, Donjons et groupe, Classe, Métiers. Une section vide n'apparaît pas.
- [ ] Une quête finie passe dans « À rendre » avec un « ? » ; décocher « À rendre en haut » la remet dans son genre.
- [ ] Cliquer le nom d'une section la replie ; après `/reload`, elle est toujours repliée.
- [x] Clic gauche sur une quête : fond doré, et la flèche du GPS la suit. Un second clic ne fait rien (0.1.5 : l'addon n'ouvre plus le journal du jeu).
- [x] Survol d'une quête : la bulle montre sa description, puis les clics possibles. Le menu du clic droit n'a plus « Ouvrir dans le journal ».
- [ ] Erreur corrigée en 0.1.5 : après un `/reload`, cliquer des quêtes du panneau, entrer en combat, ouvrir la carte (M) : plus aucune « action bloquée … SetPassThroughButtons » au nom de SuiviQuetes dans BugSack.
- [ ] Maj + clic : la quête n'est plus suivie et quitte le panneau.
- [x] Clic droit : menu « Ranger dans » ; choisir « Principal » déplace la quête, « Automatique » la remet. Le choix tient après `/reload`.
- [ ] Une quête sans objectif chiffré (« Livraison pour Foudrepique ») affiche son texte court, y compris juste après la connexion.
- [ ] Titres colorés comme dans le journal du jeu (rouge, orange, jaune, vert, gris) et distance à droite (« 140 m », « 2,6 km »).
- [ ] Objet de quête : son bouton apparaît à gauche du panneau ; un clic l'utilise, aussi en combat. Replier la section cache le bouton.
- [ ] En combat : une quête progresse, le suivi du jeu ne réapparaît pas ; après le combat il reste caché. Aucun message « action bloquée ».
- [ ] Déplacer le panneau par son en-tête (refusé en combat avec un message) ; « Remettre à sa place » et `/sq centre` le replacent.
- [ ] Réglages : largeur, taille (le panneau ne doit pas se déplacer), fond sombre, une ligne par quête, cacher les autres zones (les donjons et « À rendre » restent), toutes les quêtes du journal. Tout s'applique sans `/reload`.
- [ ] Décocher « Cacher le suivi du jeu », ou couper l'addon : le suivi du jeu revient.
- [ ] En donjon : le suivi du jeu revient et notre panneau s'efface ; en sortant, l'inverse.
- [ ] Mode d'édition de l'interface (Échap > Mode édition) : le suivi du jeu se voit, puis disparaît à la sortie.
- [ ] Sur Retail : mêmes vérifications, et les quêtes de campagne vont dans « Principal ».

## Dialogues de quête (nouveau)

À faire en premier : désactiver Immersion (Échap > AddOns), `/reload`, puis `/dial test` : le bandeau doit s'afficher en bas, sans erreur dans BugSack.

- [ ] Parler à un PNJ qui donne une quête : bandeau en bas, portrait, texte par morceaux (« 1 / 3 »), Espace tourne la page, puis « Accepter ». La quête est bien prise.
- [ ] La fenêtre du jeu ne se voit pas, et cliquer dans le décor en haut à gauche de l'écran ne lance rien.
- [ ] À la fin de l'échange, ouvrir un autre PNJ avec « Fenêtre du jeu » : la fenêtre du jeu revient à la bonne taille et au bon endroit.
- [ ] PNJ à plusieurs réponses : elles sont numérotées, les touches 1 à 9 les choisissent, « ? » sur une quête à rendre, « ! » sur une quête à prendre.
- [ ] Rendre une quête à plusieurs récompenses : le bouton est grisé tant que rien n'est choisi ; choisir par clic ou par chiffre, puis « Terminer la quête ». La bonne récompense arrive dans le sac.
- [ ] « Mieux pour toi » apparaît en vert sous une récompense meilleure que ce que tu portes (avec Sacs rangés).
- [ ] « Refuser » et Échap ferment l'échange sans erreur.
- [ ] Garder Espace enfoncé : une seule page tourne par appui. Bandeau fermé, Espace fait sauter comme d'habitude.
- [ ] Se déplacer avec le bandeau ouvert : les touches de déplacement marchent.
- [ ] Entrer en combat avec le bandeau ouvert : les touches ne sont plus prises (Espace saute), la souris marche ; après le combat tout revient.
- [ ] Avec Quêtes auto actif : une quête acceptée ou rendue toute seule ne fait rien clignoter.
- [ ] Quête qui demande une confirmation (JcJ, ou qui coûte de l'or) : la fenêtre du jeu reprend la main avec un message.
- [ ] Réglages : texte d'un coup (décocher « par morceaux »), taille du texte, largeur du bandeau, touches coupées. Sans `/reload`.
- [ ] `/dial jeu` : la fenêtre du jeu est gardée ; refaire `/dial jeu` : le bandeau revient.

## Tenues (nouveau)

- [x] `/tenue` ouvre la fenêtre. Taper « Combat », laisser toutes les cases cochées, « Enregistrer ce que je porte » : la tenue apparaît, « (portée) », bordure verte.
- [ ] Mettre la canne à pêche (et un chapeau de pêche si tu en as), enregistrer « Pêche » en ne cochant que ces emplacements.
- [ ] « Mettre » sur Combat : l'arme revient, le reste ne bouge pas. « Mettre » sur Pêche : seule la canne change.
- [ ] `/tenue retour` remet ce qui était porté avant.
- [ ] `/tenue peche` (sans accent) et `/tenue com` (début du nom) marchent.
- [ ] En combat, « Mettre » : message « à la fin du combat », puis la tenue se met toute seule après.
- [ ] Vendre ou mettre en banque une pièce d'une tenue : son icône devient rouge, et « Mettre » dit ce qu'il manque.
- [ ] Deux anneaux ou deux bijoux dans une tenue : chacun va à son emplacement, sans échange inutile.
- [ ] Arme à deux mains dans une tenue, une main + main gauche dans l'autre : passer de l'une à l'autre dans les deux sens.
- [ ] « Mettre à jour » puis « Sûr ? » remplace le contenu de la tenue ; la croix puis « Sûr ? » la supprime.
- [ ] Réglages > Tenues > Touches : choisir une touche pour « Tenue 1 », elle met la première tenue de la liste.
- [ ] Mode pêche de Métiers auto : l'activer met la tenue « Pêche », le couper remet la précédente. Si une pêche est en cours, la ligne n'est pas coupée.
- [ ] Sur Retail : mêmes vérifications.

## Quêtes disponibles (nouveau, essai en Forêt d'Elwynn)

But de l'essai : savoir si la base de WoW Classic colle à Forever. À faire en Forêt d'Elwynn.

- [ ] `/reload`, aucune erreur dans BugSack, puis `/qd etat` : il doit dire « villes reconnues : 6 sur 6 » (au moins 1). S'il dit 0, les « ! » peuvent être mal placés : me le dire.
- [ ] Ouvrir la carte de la Forêt d'Elwynn : des « ! » jaunes apparaissent, sans gel du jeu.
- [ ] **Le test principal** : aller voir trois ou quatre « ! ». Y a-t-il bien un personnage qui propose la quête annoncée ? Noter ceux qui sont faux (rien sur place, ou autre quête).
- [ ] À l'inverse : un personnage avec un « ! » en jeu qui n'a pas de « ! » sur notre carte (quête propre à Forever ?). Noter son nom.
- [ ] Survol d'un « ! » : titres en français, niveau, couleur de difficulté, marques (Donjon, Groupe, Répétable, Réputation requise).
- [ ] Clic gauche : la flèche du GPS mène à l'endroit. Clic droit : le « ! » disparaît ; « Remontrer les quêtes cachées à la main » le remet.
- [ ] Prendre une quête : son « ! » disparaît. La rendre : la suivante de la chaîne apparaît.
- [ ] Filtres : cocher « bas niveau » ajoute des « ! », « répétables » aussi ; sans `/reload`.
- [ ] Carte d'un continent : rien, sauf si l'option est cochée (et alors sans gel).
- [ ] Après l'essai : `/reload` puis « regarde », je lirai le relevé enregistré.

## Fenêtres déplaçables (nouveau)

- [ ] `/reload`, aucune erreur dans BugSack. Ouvrir la fenêtre du personnage : glisser sa barre de titre la déplace.
- [ ] La fermer et la rouvrir : elle revient où tu l'as laissée (c'est le point le plus délicat, le jeu la replace lui-même). Pareil après `/reload`.
- [ ] Même essai avec la carte (pas agrandie), le grimoire, un marchand, le courrier, la banque, un PNJ de quête, les amis, les options (Échap).
- [ ] La croix de fermeture, les onglets et le portrait de chaque fenêtre restent cliquables : la poignée ne doit pas les couvrir. Noter la fenêtre si un bouton ne répond plus.
- [ ] Ouvrir deux fenêtres du jeu côte à côte (personnage puis grimoire) : chacune garde sa place, sans sauter ni clignoter.
- [ ] Ctrl + molette sur la barre de titre : la fenêtre grossit ou rétrécit, et la taille est gardée.
- [ ] Clic droit sur la barre de titre : « Remettre à sa place d'origine » et « Taille normale » marchent.
- [ ] En combat : glisser le personnage ou la carte ; soit ça marche, soit un message dit que ce sera fait après, sans « action bloquée ». Après le combat, la place est appliquée.
- [ ] Commencer à glisser une fenêtre, entrer en combat, relâcher : la fenêtre ne reste pas collée à la souris.
- [ ] Cliquer dans une fenêtre pour la passer devant une autre : sa barre de titre reste saisissable.
- [ ] Avec Dialogues de quête actif : parler à un PNJ ne fait apparaître aucune poignée fantôme.
- [ ] `/fen reset` remet tout ; couper l'addon rend les fenêtres au jeu.
- [ ] Après l'essai : `/reload` puis « regarde », je lirai quelles fenêtres existent sur Forever.

## Plus anciens, jamais confirmés

- [ ] Carnet de session : « niveau max » sur un personnage au plafond (Naincailloux, Retail).
- [ ] Alerte rare : l'alerte des coffres et trésors.
- [ ] Métiers auto : la flèche vers le filon connu le plus proche, et l'alerte « filon pas fini ».
- [ ] Métiers auto : avec un personnage dépeceur (sans minage ni herboristerie), aucune flèche de minerai ; un herboriste ne voit que les herbes.
- [ ] Métiers auto : ouvrir un coffre ne crée pas de nouvel « endroit connu ».
- [ ] Quêtes auto : la récompense choisie seule (journal dans `/re`), le partage de quêtes avec le groupe.
- [ ] Quêtes du groupe : le panneau en groupe avec ton frère.
- [ ] Marchand auto : le rachat du stock.
