# Tests à faire en jeu

Tout ce qui est codé mais pas encore vérifié dans le jeu. Les simulations hors jeu (`tests/`) passent toutes, mais elles ne voient ni l'affichage ni les blocages du jeu.

Pour chaque test : coche la case quand c'est bon. Si quelque chose cloche, fais `/reload`, puis dis « regarde » : les erreurs sont lues directement dans les fichiers du jeu.

Avant de commencer :
- [ ] Mettre à jour les addons dans WowUp, puis `/reload`.
- [ ] Désactiver Pawn, pour ne voir que notre avis sur les objets.
- [ ] Vérifier que BugSack est actif sur Forever.

## La fenêtre de réglages commune (refaite le 10/11)

- [ ] Clic sur l'engrenage de la minimap : la fenêtre « Addons de Valentin » s'ouvre, sans erreur. Échap la ferme.
- [ ] À gauche : les 18 addons, avec un point vert (activé) ou rouge (coupé). Clic : sa page à droite.
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
- [ ] Tout en haut de la liste de gauche : « Quoi de neuf », sans point vert ni rouge, avec l'icône d'une note ; les addons sont en dessous, un peu plus bas.
- [ ] À la première connexion après la mise à jour : un seul message dans le chat « Addons de Valentin : il y a du nouveau… » (pas 17), quelques secondes après l'arrivée dans le jeu, et une pastille dorée sur « Quoi de neuf » (et la ligne « Il y a du nouveau » dans la bulle de l'engrenage de la minimap).
- [ ] Clic sur « Quoi de neuf » : les nouveautés s'affichent dans un cadre qui défile à la molette, les plus récentes en premier, marquées « [nouveau] » (toutes, à la toute première mise à jour, quand aucune date vue n'existe) ; la pastille disparaît.
- [ ] `/reload` : plus de message, plus de pastille. Les nouveautés s'ouvrent toujours quand on clique sur l'entrée.
- [ ] « Partager mes réglages », sous « Quoi de neuf » : deux cadres (mes réglages à copier, réglages reçus à coller) ; un clic dans le premier sélectionne tout le texte (`VA1;GPS:…;SacsRanges:…`), Ctrl+C le copie, taper dedans ne le change pas. Le cadre grandit avec le texte et se fait défiler à la molette, sans couper la fin.
- [ ] Changer un réglage (par exemple la taille de la flèche du GPS), coller l'ancien texte dans le second cadre, « Appliquer » : message vert « N réglage(s) appliqué(s) dans M addon(s) », et le réglage revient à l'ancienne valeur tout de suite, sans `/reload`.
- [ ] Texte abîmé : retirer le début « VA1; » ou couper le texte au milieu d'un réglage, « Appliquer » : message rouge clair, rien n'est changé. Cadre vide : « Colle d'abord le texte reçu. »
- [ ] Les listes (objets ignorés de Butin rapide, balises du GPS, courses de Métiers auto) ne bougent pas après « Appliquer ».
- [ ] En haut à droite de la page de chaque addon, sous l'interrupteur général : « Réglages propres à ce personnage » avec son petit interrupteur (bulle d'aide au survol), sans chevaucher la description ni les onglets (Sacs rangés et Quêtes auto : onglets sur deux lignes).
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

## Conseiller (0.2.2 : spécialisation lue dans les groupes de l'arbre, builds du paladin recalés sur l'export réel)

À lancer sur le chasseur, puis sur le plus de classes possible (le plus utile : une classe à rotation de points de combo, voleur ou druide, et une classe à talents que tu as déjà pris). L'API des talents et des barres de Forever n'a été vérifiée que dans la documentation de Blizzard, jamais en jeu. Les noms français des talents et les identifiants de sorts viennent de Classic, de mémoire : ce que le jeu ne reconnaît pas doit se voir, jamais se deviner.

- [ ] `/conseil` (ou `/cs`) ouvre la fenêtre : en-tête avec classe, niveau, race, spécialisation et situation ; les 5 onglets Talents, Rotation, Équipement, Métiers, Race s'affichent sans erreur (BugSack).
- [ ] `/cs etat` : classe, spécialisation, situation, nombre de sorts connus. Si la spécialisation est « inconnue », noter ce que le jeu donne (Forever n'a peut-être pas de spécialisations au sens de Midnight). S'il y a des talents non reconnus, une deuxième ligne donne leurs noms.
- [ ] `/cs export` puis `/reload` : `ConseillerDB.export` dans `WTF\Account\<compte>\SavedVariables\Conseiller.lua` contient `noeuds` (nodeID, posX, posY, maxRanks, entrees avec spellID et nom) et `grimoire`. Si « configuration active introuvable », le jeu ne donne pas l'arbre : le noter. **Garder ce fichier : les vrais noms des talents servent à corriger les builds.**
- [ ] Forever, un seul arbre en trois groupes (0.2.2) : `/cs etat` affiche « points par groupe de talents : Sacré N, Protection N, Vindicte N ; spécialisation détectée : … ». La spécialisation doit être celle où tu as le plus de points (pas celle de GetSpecialization), et « aucune » en cas d'égalité ou de zéro point. Puis la ligne « build utilisé : … (N entrées) », « prochain talent : NOM (nœud N) » et le nombre de talents non reconnus avec leurs noms. Noter si les points par groupe sont faux (alors `GetGroupCurrencyInfo` ne se lit pas comme prévu).
- [x] Contour vert (0.2.2, validé en jeu le 10/11/2026 sur un paladin Vindicte de Forever) : fenêtre des talents ouverte, le talent « prochain » est entouré. Sinon `/cs etat` dit pourquoi : « bouton du talent introuvable dans la fenêtre » (noter ce message : le chemin vers le bouton est à corriger), fenêtre fermée ou introuvable, ou bouton caché.
- [ ] Onglet Talents, spécialisation différente de la conseillée (0.2.2) : une ligne grise « Tu es en Vindicte ; en groupe sans tank, Protection est conseillée » et « Le build ci-dessous est celui de ta spécialisation » ; le build montré est celui de ta spécialisation. `/cs export` écrit aussi `groupes` (groupID, displayName, orderIndex, depense) et `groupIDs` sur chaque nœud : à relire dans le fichier.
- [ ] Onglet Talents, build affiché pour chaque classe : la spécialisation conseillée et le « Pourquoi » s'affichent, puis « Prochain talent : … » (rang X sur Y) avec le bon talent de TA classe, et la ligne grise « Build croisé entre plusieurs guides, mis à jour le 10/11/2026 ». Passer par le bouton « Situation » (Seul, En groupe, Donjon, Raid) : le build et la spécialisation changent. Noter, pour chaque classe jouée : le prochain talent est-il bien le premier du build que le jeu laisse prendre ?
- [ ] Talents non reconnus : une ligne rouge « N talents du build n'ont pas été reconnus : fais /cs export… » avec leurs noms en gris. Noter combien, pour quelle classe, et surtout quels noms (client en français : un nom français mal retenu est compté ici, c'est attendu et corrigeable avec l'export). Si **tous** sont non reconnus : le message « aucun de ses talents n'a été reconnu » s'affiche, et c'est alors le nom de l'arbre ou la lecture de C_Traits qui est en cause, à noter.
- [ ] Palier pas atteint : à un niveau bas, le prochain talent annoncé est bien un talent achetable maintenant (pas un talent d'un palier suivant) ; si plus rien n'est achetable, l'onglet dit « Le jeu ne permet pas de le prendre pour l'instant » et le bouton « Prendre ce talent » est grisé.
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
- [ ] Équipement : l'ordre des statistiques de ta spécialisation ; `/run print(Conseiller_OrdreStats()[1])` répond une clé de statistique.
- [ ] Métiers : trois propositions pour ta classe, et « À faire maintenant » avec tes métiers (compétence, palier suivant).
- [ ] Race : tes capacités de race, actives et passives.
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
- [ ] Panneau de Livres de bibliothèque (`/livres`, Forever) : fond sombre, titre doré, croix, Échap le ferme.
- [ ] Panneau de Quêtes du groupe (`/qg`) : fond sombre, titre doré, croix, Échap le ferme.
- [ ] Rapport d'erreurs (`/re`) : fond sombre, titre doré, croix, Échap le ferme, le texte reste sélectionnable et copiable.
- [ ] Sur chacune : rien ne chevauche le titre, le texte reste lisible, aucune erreur Lua (BugSack) à l'ouverture, en combat ou non.
- [ ] Retail et Forever : même rendu (si le cadre n'a pas de fond, un cadre enfant le dessine derrière).

## Suivi des quêtes (nouveau)

À faire en premier : `/reload`, puis regarder BugSack. Le suivi du jeu doit avoir disparu et notre panneau « Quêtes » être à droite.

- [ ] `/sq genre` : pour chaque quête suivie, le chat donne la rubrique, le tag, la classification et le genre retenu. **Me donner ce texte** (ou dire « regarde ») : il sert à régler le tri automatique, surtout « Principal », « Classe » et « Métiers ».
- [ ] Les sections sont dans l'ordre : À rendre, Principal, Général, Donjons et groupe, Classe, Métiers. Une section vide n'apparaît pas.
- [ ] Une quête finie passe dans « À rendre » avec un « ? » ; décocher « À rendre en haut » la remet dans son genre.
- [ ] Cliquer le nom d'une section la replie ; après `/reload`, elle est toujours repliée.
- [ ] Clic gauche sur une quête : fond doré, et la flèche du GPS la suit. Un second clic ouvre sa fiche dans le journal.
- [ ] Maj + clic : la quête n'est plus suivie et quitte le panneau.
- [ ] Clic droit : menu « Ranger dans » ; choisir « Principal » déplace la quête, « Automatique » la remet. Le choix tient après `/reload`.
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

## Plus anciens, jamais confirmés

- [ ] Carnet de session : « niveau max » sur un personnage au plafond (Naincailloux, Retail).
- [ ] Alerte rare : l'alerte des coffres et trésors.
- [ ] Métiers auto : la flèche vers le filon connu le plus proche, et l'alerte « filon pas fini ».
- [ ] Métiers auto : avec un personnage dépeceur (sans minage ni herboristerie), aucune flèche de minerai ; un herboriste ne voit que les herbes.
- [ ] Métiers auto : ouvrir un coffre ne crée pas de nouvel « endroit connu ».
- [ ] Quêtes auto : la récompense choisie seule (journal dans `/re`), le partage de quêtes avec le groupe.
- [ ] Quêtes du groupe : le panneau en groupe avec ton frère.
- [ ] Marchand auto : le rachat du stock.
