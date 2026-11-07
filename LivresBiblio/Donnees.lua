-- ============================================================================
-- Livres de bibliothèque : où trouver chaque livre (WoW Forever).
--
-- Positions : faits relevés dans le jeu par la communauté (Wowhead, addon
-- « Library Books » de Taraezor). Les indices sont réécrits en français.
-- Chaque livre est suivi par sa quête de rendu (quete) : quand elle est
-- validée, le livre est rendu. Les numéros de carte sont ceux de Forever.
--
-- Écartés volontairement (rien à gagner dans Forever) :
--  - « Le soin des familiers démoniaques pour les pas doués » (marais des
--    Chagrins) : sa quête de rendu a été retirée du jeu ;
--  - « Le Liminal et l'arcane » (Féralas) : livre et quête retirés.
-- ============================================================================

local _, ns = ...

-- Cartes (uiMapID de Forever). Le nom affiché est lu dans le jeu, en français.
ns.KALIMDOR, ns.ROYAUMES = 1414, 1415

-- Zones de Kalimdor (toutes les autres zones des livres sont dans les Royaumes de l'Est).
ns.CARTES_KALIMDOR = { [1413] = true, [1439] = true, [1441] = true, [1442] = true, [1443] = true,
  [1445] = true, [1446] = true, [1447] = true, [1448] = true, [1452] = true, [1454] = true }

-- Les PNJ à qui rendre les livres, selon ta faction.
-- base : les livres ordinaires ; niv60 : les livres « niveau 60 ».
ns.PNJ = {
  Alliance = {
    base = { nom = "Garion Wendell", carte = 1453, x = 0.4900, y = 0.8660 },
    niv60 = { nom = "Jennea Cannon", carte = 1453, x = 0.386, y = 0.796 },
  },
  Horde = {
    base = { nom = "Owen Thadd", carte = 1458, x = 0.7410, y = 0.3450 },
    niv60 = { nom = "Oran Snakewrithe", carte = 1458, x = 0.736, y = 0.326 },
  },
}

-- Quêtes « d'ensemble » rendues avec 10, 20 et 25 livres.
ns.QUETES_AMI = {
  { quete = 78150, nom = "Ami de la bibliothèque" },
  { quete = 79536, nom = "Mécène de la bibliothèque" },
  { quete = 82208, nom = "Mécène de la bibliothèque (2)" },
}

-- nom : nom français du livre ; en : nom anglais (client en anglais) ;
-- carte, x, y : où il est ; aide : indice ; niv60 : livre « niveau 60 » ;
-- autres : autres endroits possibles pour le même livre.
ns.LIVRES = {
  -- Kalimdor -----------------------------------------------------------------
  { quete = 81952, nom = "Étiquette quotidienne", en = "Everyday Etiquette",
    carte = 1447, x = 0.2075, y = 0.6205, aide = "Sur une caisse, au campement de Haldarr." },
  { quete = 78124, nom = "Almanach de Nar’thalas", en = "Nar'thalas Almanac",
    carte = 1439, x = 0.5961, y = 0.2213,
    aide = "Descends l'escalier des ruines de Mathystra : c'est un parchemin." },
  { quete = 79950, nom = "Les démons et vous", en = "Demons and You",
    carte = 1443, x = 0.5507, y = 0.2617,
    aide = "Un livre mystérieux sur un banc, près d'un chaudron, dans la forteresse de Hache-Tonnerre." },
  { quete = 79952, nom = "RwlRwlRwlRwl !", en = "RwlRwlRwlRwl!",
    carte = 1445, x = 0.572, y = 0.208,
    aide = "Un livre détrempé par terre, côté est du camp murloc de la colline des Sorcières." },
  { quete = 79094, nom = "Les Leçons de Ta’zo", en = "The Lessons of Ta'zo",
    carte = 1454, x = 0.3865, y = 0.7845,
    aide = "Une grande tablette de pierre aux inscriptions rouges, contre le mur de la vallée des Esprits, à gauche en allant vers les maîtres des mages." },
  { quete = 78149, nom = "Fureur de la terre", en = "Fury of the Land",
    carte = 1442, x = 0.744, y = 0.857,
    aide = "Sur un petit tonneau, sous une tente du poste de Totem-Sinistre." },
  { quete = 81949, nom = "Légendes des Eaugures", en = "Legends of the Tidesages",
    carte = 1446, x = 0.727, y = 0.478,
    aide = "Dans une bibliothèque du bâtiment du milieu, à la crique des Pirates." },
  { quete = 78143, nom = "Secrets des Rêveurs", en = "Secrets of the Dreamers",
    carte = 1413, x = 0.462, y = 0.344,
    aide = "Dans la grotte de l'entrée des Cavernes des lamentations, du côté opposé au portail." },
  { quete = 78145, nom = "Manuel des systèmes arcaniques", en = "Arcanic Systems Manual",
    carte = 1413, x = 0.563, y = 0.088,
    aide = "Dans la salle de contrôle, tout en haut du derrick pétrolier au nord des Tarides." },
  { quete = 79097, nom = "Baxtan : Sur les magies destructrices", en = "Baxtan: On Destructive Magics",
    carte = 1413, x = 0.627, y = 0.363, aide = "Le tome gobelin est juste à côté de Gazlowe, à Cabestan." },
  { quete = 79947, nom = "Géomancie : une montagne de puissance", en = "Geomancy: The Stone-Cold Truth",
    carte = 1441, x = 0.3443, y = 0.4015,
    aide = "Par terre, dans la plus grande hutte du pic de Nuage-Noir. Le chemin pour monter part d'environ 31, 36." },
  { quete = 84397, nom = "Le guide complet du nord de Kalimdor", en = "Northern Kalimdor", niv60 = true,
    carte = 1448, x = 0.652, y = 0.33, aide = "Dans le repaire des Grumegueules, près du vendeur de réputation." },
  { quete = 84399, nom = "Badaboum !", en = "Ka-Boom!", niv60 = true,
    carte = 1452, x = 0.607, y = 0.377,
    aide = "Sur une étagère derrière le vendeur, dans la hutte d'alchimie de Long-Guet." },

  -- Royaumes de l'Est ---------------------------------------------------------
  { quete = 79948, nom = "Les bases de la magie défensive", en = "Defensive Magics 101",
    carte = 1416, x = 0.4855, y = 0.5776,
    aide = "Sur une caisse, juste à l'entrée de la tour des ogres, au carrefour du Gibet." },
  { quete = 79949, nom = "Un tissage de mensonges", en = "A Web of Lies: Debunking Myths and Legends",
    carte = 1417, x = 0.736, y = 0.652,
    aide = "Un parchemin à droite de l'entrée d'une tente, au village de Fouette-Hiver." },
  { quete = 79951, nom = "Les Momies : le guide des morts-vivants répugnants", en = "Mummies: A Guide to the Unsavory Undead",
    carte = 1418, x = 0.567, y = 0.399,
    aide = "Dans la crypte. Arrive par le chemin du sud, vers 56, 45." },
  { quete = 81956, nom = "Codex d’adjurateur", en = "Conjurer's Codex",
    carte = 1419, x = 0.553, y = 0.322, aide = "Le livre brille à cet endroit, tu ne peux pas le rater." },
  { quete = 81953, nom = "Plan de Formepierre", en = "Stonewrought Design",
    carte = 1428, x = 0.28, y = 0.29,
    aide = "Dans le mont Rochenoire : marche sur les chaînes pour descendre jusqu'au pavillon où se tient Lothos Arpentefaille. À sa gauche, la salle de l'autel de Franclorn : le livre est sur la dalle." },
  { quete = 84396, nom = "Magma ou lave ?", en = "Magma or Lava?", niv60 = true,
    carte = 1428, x = 0.30, y = 0.24,
    aide = "Même chemin que le Plan de Formepierre. La salle de l'autel donne sur une caverne : le parchemin est juste à l'entrée." },
  { quete = 78147, nom = "Crimes contre l’anatomie", en = "Crimes Against Anatomy",
    carte = 1431, x = 0.167, y = 0.285,
    aide = "Dans la dernière salle des catacombes de la crypte de la colline des Corbeaux, le bâtiment à l'ouest." },
  { quete = 84401, nom = "Le Fléau : menace morte-vivante ou phénomène incompris ?", en = "Scourge: Undead Menace or Misunderstood?", niv60 = true,
    carte = 1423, x = 0.26, y = 0.15, aide = "Sur la table juste avant le pont de Stratholme." },
  { quete = 84400, nom = "La Dame et le Chevalier", en = "The Knight and the Lady", niv60 = true,
    carte = 1423, x = 0.453, y = 0.425, aide = "Dans une petite maison au bord du lac." },
  { quete = 84398, nom = "Étude de la Lumière", en = "A Study of the Light", niv60 = true,
    carte = 1423, x = 0.718, y = 0.483, aide = "Au fond à gauche de la chapelle de l'Espoir de Lumière." },
  { quete = 79092, nom = "Journal de recherche de l’archimage Théocritus", en = "Archmage Theocritus's Research Journal",
    carte = 1429, x = 0.6546, y = 0.7007,
    aide = "À mi-hauteur de la tour d'Azora, il brille. Aucun combat : le livre idéal pour commencer." },
  { quete = 79091, nom = "Archimage Antonidas : L’autobiographie intégrale", en = "Archmage Antonidas: The Unabridged Autobiography",
    carte = 1455, x = 0.7597, y = 0.1056, aide = "Dans la salle des Explorateurs, sur la table du milieu." },
  { quete = 79093, nom = "Rumi de Gnomeregan : Le recueil d’œuvres", en = "Rumi of Gnomeregan: The Collected Works",
    carte = 1432, x = 0.356, y = 0.489, aide = "Un tome gnome sur une table, derrière l'aubergiste de Thelsamar.",
    autres = { { carte = 1436, x = 0.527, y = 0.538,
                 aide = "Ou sur une table de l'auberge de Colline-des-Sentinelles (pas dans la tour)." } } },
  { quete = 78148, nom = "Runes des rois-sorciers", en = "Runes of the Sorcerer-Kings",
    carte = 1432, x = 0.7745, y = 0.1416,
    aide = "Dans la grotte des ogres de Mo'grosh : longe la paroi de gauche en entrant." },
  { quete = 81955, nom = "Un esprit métallique", en = "A Mind of Metal",
    carte = 1427, x = 0.379, y = 0.496, aide = "Sous la tente, sur la table." },
  { quete = 79096, nom = "Ataeric : À propos des curiosités des arcanes", en = "Ataeric: On Arcane Curiosities", objets = { "Secrets des arcanes", "Arcane Secrets" },
    carte = 1421, x = 0.434, y = 0.412,
    aide = "Au Sépulcre, dans le tombeau près de Sebastian Meloche. L'objet s'appelle « Secrets des arcanes »." },
  { quete = 78127, nom = "Le compendium de Dalaran", en = "The Dalaran Digest",
    carte = 1421, x = 0.635, y = 0.631, aide = "Sur une étagère du grand bâtiment du moulin d'Ambre." },
  { quete = 79535, nom = "Les basilics : faut-il avoir peur de se faire pétrifier ?", en = "Basilisks: Should Petrification be Feared?",
    carte = 1434, x = 0.415, y = 0.509,
    aide = "Des notes de recherche sur un banc, à droite de l'entrée de la mine de Veine-de-Cristal." },
  { quete = 81947, nom = "Sorcellerie sanguine", en = "Sanguine Sorcery",
    carte = 1435, x = 0.701, y = 0.529, aide = "Sur la passerelle la plus haute du temple, bien en vue." },
  { quete = 81954, nom = "Voyages venimeux", en = "Venomous Journeys",
    carte = 1425, x = 0.360, y = 0.727, aide = "Derrière un mur brun." },
  { quete = 79095, nom = "L’Abécédaire métaphysique de l’apothicaire", en = "The Apothecary's Metaphysical Primer",
    carte = 1420, x = 0.595, y = 0.523,
    aide = "Sur l'étagère à côté de l'apothicaire Johaan, dans la boutique d'alchimie de Brill." },
  { quete = 84395, nom = "Pommes de terre mortes-vivantes", en = "Undead Potatoes", niv60 = true,
    carte = 1422, x = 0.382, y = 0.546, aide = "À l'étage de la ferme." },
  { quete = 84402, nom = "La nécromancie pour les nuls", en = "Necromancy 101", niv60 = true,
    carte = 1422, x = 0.6941, y = 0.7284,
    aide = "Au château de Scholomance, dans la zone (pas l'instance) : à droite, l'escalier, puis la rampe. Sur une table dans un recoin, près du Sang des héros." },
  { quete = 78142, nom = "Envoûtements et glamours", en = "Bewitchments and Glamours",
    carte = 1436, x = 0.454, y = 0.705,
    aide = "Première hutte à gauche en entrant à Ruisselune : un livre rouge en bas d'une étagère." },
  { quete = 78146, nom = "Parchemins de Goaz", en = "Goaz Scrolls",
    carte = 1437, x = 0.3363, y = 0.4786,
    aide = "Tout en bas du site de fouilles de Whelgar, dans une grande urne." },
}
