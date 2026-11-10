-- ============================================================================
-- Donnees.lua : TOUT ce que Conseiller sait des classes, des sorts, des métiers et des races.
-- Aucun code ici, que des tables : c'est le fichier à compléter pour ajouter une classe,
-- une rotation ou un build de talents. La logique est dans Logique.lua.
--
-- D'où viennent ces données : les fiches de outils/donnees-conseiller/*.md (une par classe),
-- croisées sur plusieurs sites de guides Forever, à rafraîchir à chaque patch. Ce qu'une fiche ne
-- donne pas (identifiants de sorts, noms français, rangs de talents) vient de Classic, de mémoire :
-- c'est dit dans la fiche, et chaque sort a donc plusieurs façons d'être retrouvé.
--
-- Pour ajouter une rotation (une classe, une spécialisation) :
--   1. déclarer les sorts dans ns.DONNEES.SORTS[CLASSE] : une clé et S(nom français, nom anglais,
--      identifiants…) ; les identifiants vont du rang le plus haut au plus bas (le premier que le
--      personnage connaît gagne) ; si aucun n'est connu, le nom français est cherché dans le grimoire,
--      puis le nom anglais ;
--   2. écrire la liste de priorité dans ns.DONNEES.ROTATIONS[CLASSE][spécialisation] : des
--      entrées E(clé, "la phrase du mode liste", conditions…) dans l'ordre : la première dont les
--      conditions sont vraies est le sort à lancer. Les urgences (soins, défensifs) vont EN TÊTE.
--   Conditions : "pret" (utilisable et recharge finie), { "debuffAbsent" } (ton affaiblissement n'est
--   pas sur la cible ; { "debuffAbsent", AUTRE_CLE } pour un autre sort), { "buffAbsent" } (l'effet n'est
--   pas sur toi), "ennemisProches>=3" (nombre d'ennemis en combat), "vie<20" (vie de la cible en %),
--   { "vie", "moi", 30 } (vie de ton personnage), "pointsCombo>=5" (voleur, félin),
--   { "typeCible", { "Mort-vivant" } }. Sans condition : toujours vrai.
--
-- Pour écrire un build de talents : voir BUILDS en bas. Un talent se désigne par ses sorts, son nom
-- français et son nom anglais (Conseiller le retrouve dans l'arbre du jeu) ; la forme exacte
-- { nodeID = … } marche aussi, avec les numéros que « /cs export » écrit dans ConseillerDB.export.
-- ============================================================================

local NOM_ADDON, ns = ...

local D = {}
ns.DONNEES = D

-- Les situations connues (ordre d'affichage).
D.SITUATIONS = { "solo", "groupe", "donjon", "raid" }
D.NOMS_SITUATIONS = { solo = "Seul", groupe = "En groupe", donjon = "Donjon", raid = "Raid" }
D.NOMS_ROLES = { tank = "tank", soins = "soigneur", degats = "dégâts" }

-- ============================================================ classes
-- specs : { cle = { nom, noms = {noms sans accent ni majuscule, pour retrouver la spécialisation du jeu},
--                   index = rang dans le jeu (secours), role } }
-- choix : spécialisation conseillée selon la situation (donjon et raid retombent sur « groupe »).
-- parRole : spécialisation à prendre quand le groupe manque de ce rôle.
-- raisons : la phrase « Pourquoi », par situation ou par rôle manquant.
-- conseils : « à savoir », seul et en groupe.
-- metiers : { nom, pourquoi, badge } ; badge : 1 = conseillé, 2 = plus tard, 3 = pour l'or ou pour le groupe.
D.CLASSES = {
  HUNTER = {
    nom = "Chasseur",
    ordre = { "bete", "precision", "survie" },
    specs = {
      bete = { nom = "Maîtrise des bêtes", noms = { "maitrise des betes", "betes", "bete" }, index = 1, role = "degats" },
      precision = { nom = "Précision", noms = { "precision", "tir" }, index = 2, role = "degats" },
      survie = { nom = "Survie", noms = { "survie" }, index = 3, role = "degats" },
    },
    choix = { solo = "bete", groupe = "bete", donjon = "bete", raid = "precision" },
    raisons = {
      solo = "ton familier tient les monstres pendant que tu tires : la spécialisation que tous les guides conseillent en montée.",
      groupe = "ton familier tient les monstres et fait une bonne part des dégâts : la même spécialisation qu'en montée reste la plus simple en groupe.",
      donjon = "même arbre qu'en montée et le familier compte beaucoup dans les dégâts ; Précision est une bonne alternative si le groupe veut l'Aura de précision.",
      raid = "Précision apporte l'Aura de précision à tout le groupe : c'est l'usage classique en raid (les guides Forever ne tranchent pas encore).",
    },
    conseils = {
      solo = {
        "Laisse ton familier prendre les coups : si la cible se tourne vers toi, Coupure d'ailes ou Piège de givre.",
        "Garde du mana de réserve pour Feindre la mort et tes contrôles.",
        "Morsure de serpent est inutile sur un monstre qui meurt vite : passe au suivant pendant que les pièges travaillent.",
        "Guérison du familier entre deux combats : un familier en vie tient tout le reste.",
      },
      groupe = {
        "Mets ton familier en mode défensif et coupe son Grognement : sinon il vole les monstres au tank.",
        "Marque du chasseur sur la cible du tank, pas sur la tienne ; l'Aura de précision aide tout le groupe.",
        "Les pièges marchent en combat : Piège de congélation pour contrôler un monstre, Piège de givre pour en ralentir plusieurs.",
        "Feindre la mort si un monstre te tape : il retourne sur le tank.",
      },
    },
    metiers = {
      { "Dépeçage + Travail du cuir", "Tu fabriques ton armure en cuir (bleue dès le niveau 10), puis en mailles au niveau 40, et le dépeçage se fait sur les bêtes que tu tues déjà.", 1 },
      { "Ingénierie + Minage", "Viseurs pour ton arme à distance, munitions et gadgets ; plus cher à monter.", 2 },
      { "Herboristerie + Alchimie", "Deux métiers qui rapportent de l'or à l'hôtel des ventes ; l'Enchantement se vend bien aussi.", 3 },
    },
  },

  PALADIN = {
    nom = "Paladin",
    ordre = { "sacre", "protection", "vindicte" },
    specs = {
      sacre = { nom = "Sacré", noms = { "sacre" }, index = 1, role = "soins" },
      protection = { nom = "Protection", noms = { "protection" }, index = 2, role = "tank" },
      vindicte = { nom = "Vindicte", noms = { "vindicte", "retribution" }, index = 3, role = "degats" },
    },
    choix = { solo = "vindicte", groupe = "vindicte", donjon = "vindicte", raid = "vindicte" },
    parRole = { tank = "protection", soins = "sacre" },
    raisons = {
      solo = "tu tues vite et tu te soignes toi-même entre deux combats : Vindicte est conseillée en montée par tous les guides (Protection tient mieux les gros groupes de monstres).",
      groupe = "ton groupe a ce qu'il lui faut en tank et en soins : tu apportes des dégâts de mêlée.",
      donjon = "le tank et le soigneur sont là : tu apportes des dégâts de mêlée.",
      raid = "il y a assez de tanks et de soigneurs : tu apportes des dégâts de mêlée.",
      tank = "ton groupe n'a pas de tank : tu prends les coups, les autres tapent.",
      soins = "ton groupe n'a pas de soigneur : tes soins gardent tout le monde en vie.",
    },
    conseils = {
      solo = {
        "Le Jugement ne consomme plus ton sceau : garde le même et refais-le avant qu'il finisse.",
        "Ton mana est limité : Consécration avec parcimonie, emporte de l'eau et des potions.",
        "Les armes sont le plus gros gain : lentes et lourdes en Vindicte.",
        "Bouclier divin puis Pierre de foyer si tout tourne mal.",
      },
      groupe = {
        "Fureur vertueuse active en Protection, sinon les monstres partent sur tes alliés.",
        "Bénédiction de salut sur tout le monde sauf les tanks, hors combat ; Bénédiction de protection sur celui qui tire la menace.",
        "Un seul Jugement par paladin sur la cible : choisis selon le besoin du groupe (sagesse pour le mana).",
        "Imposition des mains sur l'allié qui va mourir, pas forcément sur toi.",
      },
    },
    metiers = {
      { "Minage + Forge", "Tu forges ton armure en plaques (au niveau 40) et tes armes ; le minerai se trouve en route.", 1 },
      { "Ingénierie + Minage", "Gadgets ; plus long à monter.", 2 },
      { "Herboristerie + Alchimie", "Potions de soins et de mana pour les combats durs en groupe, et de l'or à l'hôtel des ventes.", 3 },
    },
  },

  WARRIOR = {
    nom = "Guerrier",
    ordre = { "armes", "fureur", "protection" },
    specs = {
      armes = { nom = "Armes", noms = { "armes" }, index = 1, role = "degats" },
      fureur = { nom = "Fureur", noms = { "fureur" }, index = 2, role = "degats" },
      protection = { nom = "Protection", noms = { "protection" }, index = 3, role = "tank" },
    },
    choix = { solo = "armes", groupe = "armes", donjon = "armes", raid = "fureur" },
    parRole = { tank = "protection" },
    raisons = {
      solo = "une grosse arme à deux mains et des coups puissants : tu tues vite. Les guides se partagent : Protection (une main et bouclier) tient mieux les gros groupes de monstres.",
      groupe = "un autre joueur tient les monstres : tu mises sur les dégâts, à deux mains.",
      donjon = "le tank est là : Armes à deux mains, la spécialisation de donjon des guides Forever.",
      raid = "il y a assez de tanks : Fureur, deux armes, pour les dégâts (les guides Forever ne tranchent pas encore pour le raid).",
      tank = "ton groupe n'a pas de tank : le guerrier est fait pour ça.",
    },
    conseils = {
      solo = {
        "Les armes font presque tous tes dégâts : change d'arme dès que tu en trouves une meilleure.",
        "La rage est rare : ne la dépense pas toute en Exécution, garde-en pour le monstre suivant.",
        "Cri d'intimidation, Représailles et Mur protecteur servent à tirer de gros groupes de monstres.",
        "Bandage entre deux combats : un guerrier n'a ni soins ni mana.",
      },
      groupe = {
        "En tank : Posture défensive, Fracasser armure, Coup de tonnerre et Cri démoralisant à entretenir, Provocation sur ce qui part vers les soigneurs.",
        "En dégâts : ne tape pas avant que le tank ait pris la menace.",
        "Cri de guerre aide tout le groupe : lance-le avant les combats.",
        "La rage est faible : garde-la pour tes gros coups, pas pour un monstre presque mort.",
      },
    },
    metiers = {
      { "Minage + Forge", "Armure en plaques (au niveau 40), pierres d'arme et armes forgées toi-même ; le minerai se trouve en route.", 1 },
      { "Ingénierie + Minage", "Gadgets et explosifs ; plus long à monter.", 2 },
      { "Dépeçage + Travail du cuir", "Le dépeçage rapporte de l'argent très tôt ; le cuir t'habille en attendant les plaques.", 3 },
    },
  },

  ROGUE = {
    nom = "Voleur",
    ordre = { "assassinat", "combat", "finesse" },
    specs = {
      assassinat = { nom = "Assassinat", noms = { "assassinat" }, index = 1, role = "degats" },
      combat = { nom = "Combat", noms = { "combat" }, index = 2, role = "degats" },
      finesse = { nom = "Finesse", noms = { "finesse", "subtilite" }, index = 3, role = "degats" },
    },
    choix = { solo = "combat", groupe = "combat", donjon = "combat", raid = "combat" },
    raisons = {
      solo = "toutes les armes marchent, l'Attaque pernicieuse coûte peu et l'Éviscération frappe fort sans se placer : la spécialisation la plus simple seul.",
      groupe = "des dégâts réguliers en mêlée, et c'est la plus facile à jouer.",
      donjon = "des dégâts réguliers en mêlée, et Exposer l'armure aide le groupe sur les boss.",
      raid = "Combat reste le standard ; Assassinat (dagues) est aussi parmi les meilleures en raid.",
    },
    conseils = {
      solo = {
        "Ouvre toujours par un sort furtif : Embuscade (dagues) ou Garrot, puis garde la même cible pour tes points de combo.",
        "Remplace vite ton arme de départ : l'Attaque pernicieuse dépend des dégâts de l'arme.",
        "Évasion et Disparition te sortent d'un combat perdu ; Assommer ou Cécité sortent un monstre du combat.",
        "Garde de la nourriture : un voleur n'a pas de mana, donc pas d'eau.",
      },
      groupe = {
        "Reste derrière la cible : on ne passe pas devant le tank.",
        "Coup de pied pour interrompre les sorts, au bon moment : c'est ton rôle.",
        "Ne tape pas avant que le tank ait pris la menace ; Feinte fait retomber la tienne.",
        "Exposer l'armure sur les boss aide tout le groupe.",
      },
    },
    metiers = {
      { "Dépeçage + Travail du cuir", "Ton armure est en cuir : tu la fabriques et tu dépèces ce que tu tues ; le cuir reste utile au niveau 60.", 1 },
      { "Minage + Forge", "Pour tes armes ; le Crochetage, lui, vient avec le voleur.", 2 },
      { "Dépeçage + Minage", "Les deux métiers de récolte qui rapportent le plus vite de l'or.", 3 },
    },
  },

  PRIEST = {
    nom = "Prêtre",
    ordre = { "discipline", "sacre", "ombre" },
    specs = {
      discipline = { nom = "Discipline", noms = { "discipline" }, index = 1, role = "soins" },
      sacre = { nom = "Sacré", noms = { "sacre" }, index = 2, role = "soins" },
      ombre = { nom = "Ombre", noms = { "ombre" }, index = 3, role = "degats" },
    },
    choix = { solo = "ombre", groupe = "ombre", donjon = "ombre", raid = "ombre" },
    parRole = { soins = "sacre" },
    raisons = {
      solo = "tu tues avec des sorts à distance et tu te soignes : Ombre est conseillée en montée par la plupart des guides (Discipline est une alternative).",
      groupe = "ton groupe a déjà un soigneur : tu apportes des dégâts.",
      donjon = "le soigneur est là : tu apportes des dégâts (Sacré si ton groupe cherche quelqu'un pour soigner).",
      raid = "il y a assez de soigneurs : tu apportes des dégâts (Sacré reste le choix des guides pour soigner en raid).",
      soins = "ton groupe n'a pas de soigneur : Sacré, tes soins gardent tout le monde en vie.",
    },
    conseils = {
      solo = {
        "Mot de pouvoir : Bouclier avant le combat réduit le repoussement de tes sorts et de ta baguette.",
        "Baguette dès que tu peux : elle ne coûte pas de mana ; bois et mange entre deux combats.",
        "Forme d'Ombre (niveau 40) est le gros saut : avant, Châtiment puis Mot de l'ombre : Douleur.",
        "Cri psychique si deux monstres arrivent en même temps.",
      },
      groupe = {
        "Soigne d'abord le tank, puis les autres : surveille sa barre en premier.",
        "Garde du mana : un soigneur sans mana, c'est un groupe qui meurt.",
        "Sors de la Forme d'Ombre pour soigner : en forme, aucun soin n'est possible.",
        "Dissipation de la magie et Abolir la maladie en utilité ; place-toi avant le pull, il y a peu de mouvement.",
      },
    },
    metiers = {
      { "Couture + Enchantement", "Tes robes, tes sacs, des ceintures de puissance des sorts dès le niveau 10, et l'enchantement de ton équipement.", 1 },
      { "Ingénierie + Minage", "Gadgets de dégâts ou de soins ; plus long à monter.", 2 },
      { "Herboristerie + Alchimie", "Potions de mana et de soins : utile à tout le groupe, et de l'or.", 3 },
    },
  },

  SHAMAN = {
    nom = "Chaman",
    ordre = { "elementaire", "amelioration", "restauration" },
    specs = {
      elementaire = { nom = "Élémentaire", noms = { "elementaire" }, index = 1, role = "degats" },
      amelioration = { nom = "Amélioration", noms = { "amelioration" }, index = 2, role = "degats" },
      restauration = { nom = "Restauration", noms = { "restauration" }, index = 3, role = "soins" },
    },
    choix = { solo = "amelioration", groupe = "amelioration", donjon = "amelioration", raid = "elementaire" },
    parRole = { tank = "amelioration", soins = "restauration" },
    raisons = {
      solo = "tu frappes en mêlée avec des totems et des soins pour tenir : tous les guides conseillent Amélioration en montée.",
      groupe = "ton groupe a déjà un soigneur : Amélioration, des dégâts de mêlée et le Totem de Furie-des-vents pour les autres.",
      donjon = "le soigneur est là : Amélioration, des dégâts de mêlée et le Totem de Furie-des-vents pour les autres.",
      raid = "il y a assez de soigneurs : Élémentaire, des sorts de dégâts à distance, bon sur plusieurs cibles.",
      tank = "ton groupe n'a pas de tank : en Amélioration, une arme à une main et un bouclier tiennent les premiers donjons (pas de provocation).",
      soins = "ton groupe n'a pas de soigneur : Restauration, tes soins et tes totems gardent tout le monde en vie.",
    },
    conseils = {
      solo = {
        "Un monstre à la fois : Horion de flammes, puis le Totem incendiaire, avant de frapper.",
        "Pose tes totems avant un combat difficile, pas pendant.",
        "Le mana est ta limite : garde de l'eau et des potions, des armes lentes et fortes pour Frappe-tempête.",
        "Horion de terre interrompt un sort ; Loup fantôme pour fuir.",
      },
      groupe = {
        "Un totem utile à ton groupe vaut mieux qu'un totem utile à toi : regarde qui t'accompagne.",
        "Totem de Furie-des-vents pour les joueurs de mêlée ; attention aux totems laissés derrière quand le tank avance.",
        "Salve de guérison : garde-la pour quand plusieurs alliés sont blessés en même temps.",
        "Totem de marée de mana près des autres soigneurs.",
      },
    },
    metiers = {
      { "Dépeçage + Travail du cuir", "Ton armure est en cuir (bleue dès le niveau 10), puis en mailles au niveau 40 ; la Cuisine donne un bonus d'expérience.", 1 },
      { "Minage + Ingénierie", "Gadgets, explosifs et mailles à terme.", 2 },
      { "Herboristerie + Alchimie", "Potions : un chaman soigneur consomme beaucoup de mana.", 3 },
    },
  },

  MAGE = {
    nom = "Mage",
    ordre = { "arcanes", "feu", "givre" },
    specs = {
      arcanes = { nom = "Arcanes", noms = { "arcanes" }, index = 1, role = "degats" },
      feu = { nom = "Feu", noms = { "feu" }, index = 2, role = "degats" },
      givre = { nom = "Givre", noms = { "givre" }, index = 3, role = "degats" },
    },
    choix = { solo = "givre", groupe = "givre", donjon = "givre", raid = "feu" },
    raisons = {
      solo = "les monstres sont ralentis et gelés : tu en tues plusieurs sans te faire toucher (Arcanes dépend du hasard, un guide la conseille quand même).",
      groupe = "du contrôle, des ralentissements et de bons dégâts de zone : tu comptes sur le tank pour tenir les monstres.",
      donjon = "du contrôle, des ralentissements et de bons dégâts de zone avec Blizzard : tu comptes sur le tank.",
      raid = "Feu mise sur le critique pour de gros dégâts à distance, régulièrement (les guides Forever niveau 60 sont encore en bêta).",
    },
    conseils = {
      solo = {
        "Nova de givre puis recule : les monstres ralentis ne te rejoignent pas ; Transfert casse un étourdissement.",
        "Baguette dès que possible, et finis les monstres à la baguette pour économiser ton mana.",
        "Conjure de la nourriture et de l'eau : tu ne dépenses rien pour tes repas.",
        "Mouton ou Bloc de glace si deux monstres arrivent ensemble.",
      },
      groupe = {
        "Ne lance pas de sort de zone (Blizzard, Explosion des arcanes) avant que le tank ait pris la menace.",
        "Mets un monstre par groupe en Métamorphose, et surveille ton mana (Évocation).",
        "Conjure de la nourriture et de l'eau pour tout le groupe : on t'en saura gré.",
        "Contresort sur un monstre qui lance un sort dangereux.",
      },
    },
    metiers = {
      { "Couture + Enchantement", "Tes robes, tes sacs et l'enchantement de ton équipement : le meilleur duo pour un mage.", 1 },
      { "Ingénierie + Minage", "Gadgets et consommables : ils comptent dans les combats difficiles.", 2 },
      { "Herboristerie + Alchimie", "Potions de mana : l'alchimie se vend bien.", 3 },
    },
  },

  WARLOCK = {
    nom = "Démoniste",
    ordre = { "affliction", "demonologie", "destruction" },
    specs = {
      affliction = { nom = "Affliction", noms = { "affliction" }, index = 1, role = "degats" },
      demonologie = { nom = "Démonologie", noms = { "demonologie" }, index = 2, role = "degats" },
      destruction = { nom = "Destruction", noms = { "destruction" }, index = 3, role = "degats" },
    },
    choix = { solo = "affliction", groupe = "destruction", donjon = "destruction", raid = "destruction" },
    parRole = { tank = "demonologie" },
    raisons = {
      solo = "des dégâts dans le temps, ton démon tient les monstres pendant que tu te soignes avec Drain de vie : consensus de tous les guides en montée.",
      groupe = "de gros dégâts d'un coup à distance : tu comptes sur le tank pour tenir les monstres.",
      donjon = "Destruction : de gros dégâts d'un coup, et ton diablotin renforce le groupe (Affliction reste une bonne alternative).",
      raid = "Destruction : de gros dégâts à distance (Affliction marche aussi selon l'équipement ; les guides Forever ne classent pas encore).",
      tank = "ton groupe n'a pas de tank : en Démonologie, ton démon (marqué par la Douleur brûlante) tient les monstres.",
    },
    conseils = {
      solo = {
        "Ton démon tient les monstres : le Marcheur du Vide jusqu'au niveau 20, puis le Succube ou ce que tes talents permettent.",
        "Envoie ton démon avant le pull, et utilise la baguette dès le niveau 5 : elle ne coûte pas de mana.",
        "Drain de vie pour te soigner pendant que tes dégâts continuent ; Connexion quand ta vie dépasse ton mana.",
        "Fragments d'âme : Drain d'âme sur un monstre presque mort pour ta réserve.",
      },
      groupe = {
        "Garde ton familier en mode passif si tu n'es pas tank : il vole la menace du tank ; un diablotin donne plus de vie au groupe.",
        "Pierre de soins avant un combat difficile : tu en donnes aussi à ton groupe ; garde des fragments d'âme pour les résurrections.",
        "Peur peut tirer des monstres en plus : évite-la dans les packs serrés.",
        "Rituel d'invocation : fais-le avant de commencer le donjon.",
      },
    },
    metiers = {
      { "Couture + Enchantement", "Tes robes, tes sacs et l'enchantement ; la bannière de Couture donne de l'Esprit pour Connexion.", 1 },
      { "Ingénierie + Minage", "Gadgets de dégâts et d'urgence ; plus de dégâts mais plus long à monter.", 2 },
      { "Herboristerie + Alchimie", "Potions : un démoniste dépense sa vie en dégâts. L'alchimie rapporte de l'or.", 3 },
    },
  },

  DRUID = {
    nom = "Druide",
    ordre = { "equilibre", "farouche", "gardien", "restauration" },
    specs = {
      -- index : rang dans un jeu à 3 spécialisations (Forever) ; index4 : rang dans un jeu à 4 (Retail, où
      -- Gardien est 3e et Restauration 4e). Gardien n'existe pas à 3 : pas d'index.
      equilibre = { nom = "Équilibre", noms = { "equilibre" }, index = 1, role = "degats" },
      farouche = { nom = "Combat farouche", noms = { "combat farouche", "farouche", "feral" }, index = 2, role = "degats" },
      gardien = { nom = "Gardien", noms = { "gardien", "guardian" }, index4 = 3, role = "tank" },
      restauration = { nom = "Restauration", noms = { "restauration" }, index = 3, index4 = 4, role = "soins" },
    },
    choix = { solo = "farouche", groupe = "farouche", donjon = "farouche", raid = "equilibre" },
    parRole = { tank = "farouche", soins = "restauration" },
    raisons = {
      solo = "en forme de chat tu tues vite, en ours tu tiens : Combat farouche est conseillée en montée par tous les guides.",
      groupe = "ton groupe a ce qu'il lui faut en tank et en soins : en chat, tu apportes des dégâts de mêlée (et tu peux passer ours en urgence).",
      donjon = "Combat farouche hybride : chat pour les dégâts, ours si le groupe en a besoin.",
      raid = "Équilibre : la Forme de sélénien donne un bonus de critique à tout le raid.",
      tank = "ton groupe n'a pas de tank : en forme d'ours, beaucoup de points de vie, tu tiens les monstres.",
      soins = "ton groupe n'a pas de soigneur : Restauration, tes soins sur la durée gardent tout le monde en vie.",
    },
    conseils = {
      solo = {
        "Marque du fauve et Épines toujours actifs ; ouvre par Lucioles ou Colère, et soigne-toi entre les combats.",
        "Change de forme selon le moment : chat pour tuer, ours pour tenir, humain pour te soigner.",
        "Sarments pour isoler un monstre ; la forme de chat sert à fuir.",
        "Remplace ton arme : les attaques des formes dépendent des dégâts de l'arme.",
      },
      groupe = {
        "En chat : reste derrière la cible, Se tapir pour baisser ta menace.",
        "En ours : Grondement pour prendre la menace, Rugissement démoralisant pour tenir plusieurs monstres.",
        "En soigneur : Récupération sur le tank avant le combat, Rétablissement quand ça chauffe.",
        "Renaissance (résurrection en combat) demande un réactif : garde-la pour le soigneur.",
      },
    },
    metiers = {
      { "Dépeçage + Travail du cuir", "Ton armure est en cuir : tu la fabriques et tu dépèces ce que tu tues.", 1 },
      { "Minage + Ingénierie", "Gadgets ; le minerai se vend toujours.", 2 },
      { "Herboristerie + Alchimie", "Potions, élixirs et plantes à portée de main (utilisables en forme) ; de l'or à l'hôtel des ventes.", 3 },
    },
  },
}

-- ============================================================ ordre des statistiques
-- Du plus important au moins important, par classe et par spécialisation.
-- Les clés sont celles du jeu (ITEM_MOD_*, RESISTANCE0_NAME pour l'armure).
local FOR, AGI, END, INT, ESP = "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_STAMINA_SHORT",
  "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_SPIRIT_SHORT"
local PA, PAD, TOU, CRI, HAT = "ITEM_MOD_ATTACK_POWER_SHORT", "ITEM_MOD_RANGED_ATTACK_POWER_SHORT",
  "ITEM_MOD_HIT_RATING_SHORT", "ITEM_MOD_CRIT_RATING_SHORT", "ITEM_MOD_HASTE_RATING_SHORT"
local PS, REG = "ITEM_MOD_SPELL_POWER_SHORT", "ITEM_MOD_MANA_REGENERATION_SHORT"
local DEF, ESQ, PAR, BLO, BLV = "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT", "ITEM_MOD_DODGE_RATING_SHORT",
  "ITEM_MOD_PARRY_RATING_SHORT", "ITEM_MOD_BLOCK_RATING_SHORT", "ITEM_MOD_BLOCK_VALUE_SHORT"
local ARM = "RESISTANCE0_NAME"

D.STATS = {
  WARRIOR = {
    armes = { FOR, PA, TOU, CRI, END, AGI },
    fureur = { FOR, PA, CRI, TOU, END, AGI },
    protection = { END, ARM, TOU, DEF, ESQ, PAR, FOR, CRI },
  },
  PALADIN = {
    sacre = { PS, INT, CRI, ESP, REG, END },
    protection = { PS, END, INT, FOR, ARM, TOU, CRI, AGI },
    vindicte = { FOR, PA, TOU, CRI, END, PS, INT },
  },
  HUNTER = {
    bete = { AGI, PAD, CRI, TOU, INT, END },
    precision = { AGI, PAD, CRI, TOU, INT, END },
    survie = { AGI, PAD, CRI, FOR, INT, END },
  },
  ROGUE = {
    assassinat = { AGI, PA, TOU, CRI, FOR, END },
    combat = { AGI, PA, FOR, TOU, CRI, END },
    finesse = { AGI, PA, CRI, TOU, FOR, END },
  },
  PRIEST = {
    discipline = { PS, INT, REG, ESP, CRI, END },
    sacre = { PS, INT, REG, ESP, CRI, END },
    ombre = { PS, TOU, CRI, INT, ESP, END },
  },
  SHAMAN = {
    elementaire = { PS, CRI, TOU, INT, ESP, HAT },
    amelioration = { FOR, AGI, PA, TOU, CRI, INT, END },
    restauration = { PS, ESP, INT, CRI, HAT, REG },
  },
  MAGE = {
    arcanes = { PS, TOU, HAT, INT, CRI, ESP, REG },
    feu = { PS, TOU, CRI, HAT, INT, ESP, REG },
    givre = { PS, TOU, HAT, CRI, INT, ESP, REG },
  },
  WARLOCK = {
    affliction = { PS, CRI, TOU, INT, ESP, END },
    demonologie = { PS, TOU, CRI, INT, END, ESP },
    destruction = { PS, CRI, TOU, INT, ESP, END },
  },
  DRUID = {
    equilibre = { PS, TOU, CRI, INT, ESP },
    farouche = { AGI, FOR, PA, TOU, CRI, END },
    gardien = { DEF, ESQ, ARM, END, AGI },
    restauration = { PS, ESP, HAT, CRI, INT },
  },
}

-- Quand une spécialisation est inconnue : l'ordre de la spécialisation conseillée pour la classe, sinon celui-ci.
D.STATS_PAR_DEFAUT = { END, ARM }

-- Le nom français d'une statistique.
D.NOMS_STATS = {
  [FOR] = "Force", [AGI] = "Agilité", [END] = "Endurance", [INT] = "Intelligence", [ESP] = "Esprit",
  [PA] = "Puissance d'attaque", [PAD] = "Puissance d'attaque à distance", [TOU] = "Toucher", [CRI] = "Critique",
  [HAT] = "Hâte", [PS] = "Puissance des sorts", [REG] = "Régénération du mana", [DEF] = "Défense",
  [ESQ] = "Esquive", [PAR] = "Parade", [BLO] = "Blocage", [BLV] = "Valeur de blocage", [ARM] = "Armure",
}

-- ============================================================ sorts (les rotations en ont besoin)
-- S(nom français, nom anglais, identifiants…) : les identifiants vont du rang le plus haut au plus bas
-- (identifiants de Classic, de mémoire : sur Forever, à vérifier en jeu). Un sort sans identifiant
-- (nouveau dans Forever) est retrouvé par son nom dans le grimoire.
local function S(nom, nomEN, ...)
  return { nom = nom, nomEN = nomEN, ids = { ... } }
end

D.SORTS = {
  HUNTER = {
    AUTO = S("Tir automatique", "Auto Shot", 75),
    MARQUE = S("Marque du chasseur", "Hunter's Mark", 14325, 14324, 14323, 1130),
    SERPENT = S("Morsure de serpent", "Serpent Sting", 25295, 13555, 13554, 13553, 13552, 13551, 13550, 13549, 1978),
    ARCANES = S("Tir des arcanes", "Arcane Shot", 14287, 14286, 14285, 14284, 14283, 14282, 14281, 3044),
    VISEE = S("Visée", "Aimed Shot", 20904, 20903, 20902, 20901, 20900, 19434),
    FUSILLADE = S("Fusillade", "Multi-Shot", 25294, 14290, 14289, 14288, 2643),
    ORDRE = S("Ordre de tuer", "Kill Command", 34026),
    COURROUX = S("Courroux bestial", "Bestial Wrath", 19574),
    TIR_RAPIDE = S("Tir rapide", "Rapid Fire", 3045),
    FAUCON = S("Aspect du faucon", "Aspect of the Hawk", 27044, 25296, 14322, 14321, 14320, 14319, 14318, 13165),
    RAPTOR = S("Attaque du raptor", "Raptor Strike", 14266, 14265, 14264, 14263, 14262, 14261, 14260, 2973),
    MANGOUSTE = S("Morsure de la mangouste", "Mongoose Bite", 14271, 14270, 14269, 1495),
    FEINDRE = S("Feindre la mort", "Feign Death", 5384),
    AURA_PRECISION = S("Aura de précision", "Trueshot Aura", 20906, 20905, 19506),
    INTIMIDATION = S("Intimidation", "Intimidation", 19577),
    APPEL_FAUCON = S("Appel du faucon", "Summon Hawk"),
    DISSUASION = S("Dissuasion", "Deterrence", 19263),
  },
  PALADIN = {
    -- Les rangs du Sceau de piété sont gardés en dernier : avant le niveau 20, il remplace le Sceau d'autorité.
    SCEAU_AUTORITE = S("Sceau d'autorité", "Seal of Command", 20920, 20919, 20918, 20915, 20375,
      20293, 20292, 20291, 20290, 20289, 20288, 20287, 21084),
    SCEAU_PIETE = S("Sceau de piété", "Seal of Righteousness", 20293, 20292, 20291, 20290, 20289, 20288, 20287, 21084),
    SCEAU_FUREUR = S("Sceau de fureur", "Seal of Fury"),
    SCEAU_SAGESSE = S("Sceau de sagesse", "Seal of Wisdom", 27166, 20357, 20356, 20166),
    JUGEMENT = S("Jugement", "Judgement", 20271),
    FRAPPE_SACREE = S("Frappe sacrée", "Holy Strike"),
    REMPART = S("Rempart du templier", "Templar's Bulwark"),
    CONSECRATION = S("Consécration", "Consecration", 27173, 20924, 20923, 20922, 20116, 26573),
    EXORCISME = S("Exorcisme", "Exorcism", 27138, 10314, 10313, 10312, 5615, 5614, 879),
    MARTEAU_COLERE = S("Marteau de la colère", "Hammer of Wrath", 24275),
    FUREUR = S("Fureur vertueuse", "Righteous Fury", 25780),
    BOUCLIER_SACRE = S("Bouclier sacré", "Holy Shield", 27179, 20928, 20927, 20925),
    BOUCLIER_VENGEUR = S("Bouclier du vengeur", "Avenger's Shield", 32700, 31935),
    HORION_SACRE = S("Horion sacré", "Holy Shock", 33072, 27175, 20930, 20929, 20473),
    IMPOSITION = S("Imposition des mains", "Lay on Hands", 27154, 10310, 2800, 633),
    BOUCLIER_DIVIN = S("Bouclier divin", "Divine Shield", 1020, 642),
    AURA_VINDICTE = S("Aura de vindicte", "Retribution Aura", 10301, 10300, 10299, 10298, 7294),
    BENEDICTION_PUISSANCE = S("Bénédiction de puissance", "Blessing of Might", 25291, 19838, 19837, 19836, 19835, 19834, 19740),
    ECLAIR_LUMINEUX = S("Éclair lumineux", "Flash of Light", 19943, 19942, 19941, 19940, 19939, 19750),
    LUMIERE_SACREE = S("Lumière sacrée", "Holy Light", 25292, 10329, 10328, 3472, 1042, 1026, 647, 639, 635),
  },
  WARRIOR = {
    CRI_GUERRE = S("Cri de guerre", "Battle Shout", 11551, 11550, 11549, 6192, 5242, 6673),
    FRAPPE_HEROIQUE = S("Frappe héroïque", "Heroic Strike", 11567, 11566, 11565, 11564, 1608, 285, 284, 78),
    ENCHAINEMENT = S("Enchaînement", "Cleave", 20569, 11609, 11608, 7369, 845),
    POURFENDRE = S("Pourfendre", "Rend", 11574, 11573, 11572, 6548, 6547, 6546, 772),
    FRACASSER = S("Fracasser armure", "Sunder Armor", 11597, 11596, 8380, 7405, 7386),
    FULGURANCE = S("Fulgurance", "Overpower", 11585, 11584, 7887, 7384),
    EXECUTION = S("Exécution", "Execute", 20662, 20661, 20660, 20658, 5308),
    FRAPPE_MORTELLE = S("Frappe mortelle", "Mortal Strike", 21553, 21552, 21551, 12294),
    HEURTOIR = S("Heurtoir", "Slam", 11605, 11604, 8820, 1464),
    TOURBILLON = S("Tourbillon", "Whirlwind", 1680),
    SANGUINAIRE = S("Sanguinaire", "Bloodthirst", 23894, 23893, 23892, 23881),
    SOUHAIT_MORTEL = S("Souhait mortel", "Death Wish", 12292),
    TEMERITE = S("Témérité", "Recklessness", 1719),
    BALAYANTES = S("Frappes balayantes", "Sweeping Strikes", 12328),
    TONNERRE = S("Coup de tonnerre", "Thunder Clap", 11581, 11580, 8205, 8204, 8198, 6343),
    DEMORALISANT = S("Cri démoralisant", "Demoralizing Shout", 11556, 11555, 11554, 6190, 1160),
    HEURT_BOUCLIER = S("Heurt de bouclier", "Shield Slam", 23925, 23924, 23923, 23922),
    VENGEANCE = S("Vengeance", "Revenge", 25288, 11601, 11600, 7379, 6574, 6572),
    MUR = S("Mur protecteur", "Shield Wall", 871),
    DERNIER_REMPART = S("Dernier rempart", "Last Stand", 12975),
    CRI_INTIMIDATION = S("Cri d'intimidation", "Intimidating Shout", 5246),
  },
  ROGUE = {
    DEBONDAGE = S("Débondage", "Slice and Dice", 6774, 5171),
    EVISCERATION = S("Éviscération", "Eviscerate", 31016, 11300, 11299, 8624, 8623, 6762, 6761, 6760, 2098),
    SINISTRE = S("Attaque pernicieuse", "Sinister Strike", 11294, 11293, 8621, 1760, 1759, 1758, 1757, 1752),
    SOURNOISE = S("Attaque sournoise", "Backstab", 25300, 11281, 11280, 11279, 8721, 2591, 2590, 2589, 53),
    MUTILATION = S("Mutilation", "Mutilate", 1329),
    EXPOSER = S("Exposer l'armure", "Expose Armor", 11198, 11197, 8650, 8649, 8647),
    DELUGE = S("Déluge de lames", "Blade Flurry", 13877),
    POUSSEE = S("Poussée d'adrénaline", "Adrenaline Rush", 13750),
    HEMORRAGIE = S("Hémorragie", "Hemorrhage", 17348, 17347, 16511),
    RUPTURE = S("Rupture", "Rupture", 11275, 11274, 11273, 8640, 8639, 1943),
    FRAPPE_FANTOME = S("Frappe fantomatique", "Ghostly Strike", 14278),
    ESQUIVE = S("Esquive", "Evasion", 5277),
    DISPARITION = S("Disparition", "Vanish", 1857, 1856),
  },
  PRIEST = {
    FORTITUDE = S("Mot de pouvoir : Endurance", "Power Word: Fortitude", 10938, 10937, 2791, 1245, 1244, 1243),
    FEU_INTERIEUR = S("Feu intérieur", "Inner Fire", 10952, 10951, 1006, 602, 7128, 588),
    BOUCLIER = S("Mot de pouvoir : Bouclier", "Power Word: Shield", 10901, 10900, 10899, 10898, 6066, 6065, 3747, 600, 592, 17),
    DOULEUR = S("Mot de l'ombre : Douleur", "Shadow Word: Pain", 10894, 10893, 10892, 2767, 992, 970, 594, 589),
    ATTAQUE_MENTALE = S("Attaque mentale", "Mind Blast", 10947, 10946, 10945, 8106, 8105, 8104, 8103, 8102, 8092),
    FOUET = S("Fouet mental", "Mind Flay", 18807, 17314, 17313, 17312, 17311, 15407),
    PESTE = S("Peste dévorante", "Devouring Plague", 19280, 19279, 19278, 19277, 19276, 2944),
    ETREINTE = S("Étreinte vampirique", "Vampiric Embrace", 15286),
    FORME_OMBRE = S("Forme d'Ombre", "Shadowform", 15473),
    MORT = S("Mot de l'ombre : Mort", "Shadow Word: Death", 32996, 32379),
    CHATIMENT = S("Châtiment", "Smite", 10934, 10933, 6060, 1004, 984, 598, 591, 585),
    RENOVATION = S("Rénovation", "Renew", 25315, 10929, 10928, 10927, 6078, 6077, 6076, 6075, 6074, 139),
    SOINS_RAPIDES = S("Soins rapides", "Flash Heal", 10917, 10916, 10915, 9474, 9473, 9472, 2061),
    SOINS_SUPERIEURS = S("Soins supérieurs", "Greater Heal", 25314, 10965, 10964, 10963, 2060),
    SOINS_INFERIEURS = S("Soins inférieurs", "Lesser Heal", 2053, 2052, 2050),
    PRIERE_GUERISON = S("Prière de guérison", "Prayer of Mending", 33076),
    NOVA_SACREE = S("Nova sacrée", "Holy Nova", 15431, 15430, 15237),
    OUBLI = S("Oubli", "Fade", 10942, 10941, 9592, 9579, 9578, 586),
  },
  SHAMAN = {
    BOUCLIER_FOUDRE = S("Bouclier de foudre", "Lightning Shield", 10432, 10431, 8134, 945, 905, 325, 324),
    BOUCLIER_EAU = S("Bouclier d'eau", "Water Shield", 33736, 24398),
    ECLAIR = S("Éclair", "Lightning Bolt", 15208, 15207, 10392, 10391, 6041, 943, 915, 548, 529, 403),
    CHOC_FLAMMES = S("Horion de flammes", "Flame Shock", 29228, 10448, 10447, 8053, 8052, 8050),
    CHOC_TERRE = S("Horion de terre", "Earth Shock", 10414, 10413, 10412, 8046, 8045, 8044, 8042),
    FRAPPE_TEMPETE = S("Frappe-tempête", "Stormstrike", 17364),
    NOVA_FEU = S("Nova de feu", "Fire Nova Totem", 11315, 11314, 8499, 8498, 1535),
    CHAINE = S("Chaîne d'éclairs", "Chain Lightning", 10605, 2860, 930, 421),
    EXPLOSION_LAVE = S("Explosion de lave", "Lava Burst", 51505),
    SALVE = S("Salve de guérison", "Chain Heal", 10623, 10622, 1064),
    VAGUE = S("Vague de soins", "Healing Wave", 25357, 10396, 10395, 8005, 959, 939, 913, 547, 332, 331),
    VAGUE_MINEURE = S("Vague de soins mineure", "Lesser Healing Wave", 10468, 10467, 10466, 8010, 8008, 8004),
    REMOUS = S("Remous", "Riptide", 61295),
  },
  MAGE = {
    -- Les trois armures dans une seule clé : celle que tu as apprise de plus haut niveau est conseillée,
    -- et n'importe laquelle active compte (le moteur reconnaît l'effet par la liste d'identifiants).
    ARMURE = S("Armure de glace", "Ice Armor", 10220, 10219, 7320, 7302, 22783, 22782, 6117, 7301, 7300, 168),
    ARCANE_INT = S("Intelligence des arcanes", "Arcane Intellect", 10157, 10156, 1461, 1460, 1459),
    ECLAIR_GIVRE = S("Éclair de givre", "Frostbolt", 25304, 10181, 10180, 10179, 8408, 8407, 8406, 7322, 837, 205, 116),
    BOULE_FEU = S("Boule de feu", "Fireball", 25306, 10151, 10150, 10149, 10148, 8402, 8401, 8400, 3140, 145, 143, 133),
    DEFLAGRATION = S("Déflagration des arcanes", "Arcane Blast", 30451),
    PROJ_ARCANES = S("Projectiles des arcanes", "Arcane Missiles", 25345, 10212, 10211, 8417, 8416, 5145, 5144, 5143),
    NOVA_GIVRE = S("Nova de givre", "Frost Nova", 10230, 6131, 865, 122),
    EXPLOSION_FEU = S("Explosion de feu", "Fire Blast", 10199, 10197, 8413, 8412, 2138, 2137, 2136),
    BRULURE = S("Brûlure", "Scorch", 10207, 10206, 10205, 8446, 8445, 8444, 2948),
    PYRO = S("Explosion pyrotechnique", "Pyroblast", 18809, 12526, 12525, 12524, 12523, 12522, 12505, 11366),
    BLIZZARD = S("Blizzard", "Blizzard", 10187, 10186, 10185, 8427, 6141, 10),
    EXPLOSION_ARCANES = S("Explosion des arcanes", "Arcane Explosion", 10202, 10201, 8439, 8438, 8437, 1449),
    BARRIERE_GLACE = S("Barrière de glace", "Ice Barrier", 13033, 13032, 13031, 11426),
    CONTRESORT = S("Contresort", "Counterspell", 2139),
    METAMORPHOSE = S("Métamorphose", "Polymorph", 12826, 12825, 12824, 118),
  },
  WARLOCK = {
    -- Peau de démon, Armure démoniaque : une seule clé, la plus haute que tu connais est conseillée.
    ARMURE = S("Armure démoniaque", "Demon Armor", 11735, 11734, 11733, 1086, 706, 696, 687),
    CORRUPTION = S("Corruption", "Corruption", 25311, 11672, 11671, 7648, 6223, 6222, 172),
    AGONIE = S("Malédiction d'agonie", "Curse of Agony", 11713, 11712, 11711, 6217, 1014, 980),
    IMMOLATION = S("Immolation", "Immolate", 25309, 11668, 11667, 2941, 1094, 707, 348),
    DRAIN_VIE = S("Drain de vie", "Drain Life", 11700, 11699, 7651, 709, 699, 689),
    DRAIN_AME = S("Drain d'âme", "Drain Soul", 11675, 8289, 8288, 1120),
    TRAIT_OMBRE = S("Trait de l'ombre", "Shadow Bolt", 25307, 11661, 11660, 11659, 7641, 1106, 1088, 705, 695, 686),
    SIPHON_VIE = S("Siphon de vie", "Siphon Life", 18881, 18880, 18879, 18265),
    CONFLAGRATION = S("Conflagration", "Conflagrate", 18932, 18931, 18930, 17962),
    BRULURE_OMBRE = S("Brûlure de l'ombre", "Shadowburn", 18871, 18870, 18869, 18868, 18867, 17877),
    INCINERATION = S("Incinération", "Incinerate", 29722),
    DOULEUR_BRULANTE = S("Douleur brûlante", "Searing Pain", 17923, 17922, 17921, 17920, 17919, 5676),
    MAL_ELEMENTS = S("Malédiction des éléments", "Curse of the Elements", 11722, 11721, 1490),
  },
  DRUID = {
    MARQUE_FAUVE = S("Marque du fauve", "Mark of the Wild", 9885, 9884, 8907, 5234, 6756, 5232, 1126),
    EPINES = S("Épines", "Thorns", 9910, 9756, 8914, 1075, 782, 467),
    LUCIOLES = S("Lucioles", "Faerie Fire", 17392, 17391, 17390, 16857, 9907, 9749, 778, 770),
    DECHIRURE = S("Déchirure", "Rip", 9896, 9894, 9752, 9493, 9492, 1079),
    MORSURE_FEROCE = S("Morsure féroce", "Ferocious Bite", 31018, 22829, 22828, 22827, 22568),
    EVENTRER = S("Éventrer", "Rake", 9904, 1824, 1823, 1822),
    LAMBEAU = S("Lambeau", "Shred", 9830, 9829, 8992, 6800, 5221),
    GRIFFE = S("Griffe", "Claw", 9850, 9849, 5201, 3029, 1082),
    RUGISSEMENT_DEM = S("Rugissement démoralisant", "Demoralizing Roar", 9898, 9747, 9490, 1735, 99),
    MUTILER = S("Mutiler", "Maul", 6807),
    BALAYAGE = S("Balayage", "Swipe", 9908, 9754, 769, 780, 779),
    LACERATION = S("Lacération", "Lacerate", 33746, 33745),
    ECLAT_LUNAIRE = S("Éclat lunaire", "Moonfire", 9835, 9834, 9833, 8929, 8928, 8927, 8926, 8925, 8924, 8921),
    ESSAIM = S("Essaim d'insectes", "Insect Swarm", 24977, 24976, 24975, 24974, 5570),
    COLERE = S("Colère", "Wrath", 9912, 8905, 6780, 5180, 5179, 5178, 5177, 5176),
    ECLAT_STELLAIRE = S("Éclat stellaire", "Starfire", 9876, 9875, 8951, 8950, 8949, 2912),
    RAJEUNISSEMENT = S("Récupération", "Rejuvenation", 9841, 9840, 9839, 8910, 3627, 2091, 2090, 1430, 1058, 774),
    RETABLISSEMENT = S("Rétablissement", "Regrowth", 9858, 9857, 9856, 9750, 8941, 8940, 8939, 8938, 8936),
    TOUCHER_GUERISON = S("Toucher de guérison", "Healing Touch", 25297, 9889, 9888, 9758, 8903, 6778, 5189, 5188, 5187, 5186, 5185),
    PROMPT_RETABLISSEMENT = S("Prompt rétablissement", "Swiftmend", 18562),
    ECORCE = S("Écorce", "Barkskin", 22812),
    SARMENTS = S("Sarments", "Nature's Grasp", 17329, 16813, 16812, 16811, 16810, 16689),
  },
}

-- ============================================================ rotations
-- Une liste de priorité par classe et par spécialisation (voir l'en-tête pour la forme).
-- Les urgences vont EN TÊTE d'une liste : le moteur prend la première entrée vraie. Un sort que le
-- personnage ne connaît pas (talent pas pris, niveau trop bas) est sauté. « pret » veut aussi dire
-- « assez de mana, de rage ou d'énergie, bonne posture ou bonne forme » : un sort de chat est sauté en ours.
-- Ce que le moteur ne sait pas lire (un coup d'esquive qui ouvre Fulgurance, un effet qui se déclenche,
-- les totems posés, la vie d'un allié) est dit dans le texte de l'entrée, pas dans ses conditions.
local PRET = "pret"
local BUFF_MOI = { "buffAbsent" }
local DEBUFF = { "debuffAbsent" }
local function VIE_MOI(n) return { "vie", "moi", n } end
local function E(sort, texte, ...)
  local si = { ... }
  return { sort = sort, si = (#si > 0) and si or nil, texte = texte }
end
-- Noms localisés (frFR) des types de créature que renvoie UnitCreatureType.
local MORT_OU_DEMON = { "typeCible", { "Mort-vivant", "Démon" } }

-- Urgences réutilisées.
local URGENCE_IMPOSITION = E("IMPOSITION", "Imposition des mains si tu es à moins de 15 % de vie", PRET, VIE_MOI(15))
local URGENCE_BOUCLIER = E("BOUCLIER_DIVIN", "Bouclier divin si tu es à moins de 15 % de vie", PRET, VIE_MOI(15))
local URGENCE_FEINDRE = E("FEINDRE", "Feindre la mort si tu es à moins de 20 % de vie", PRET, VIE_MOI(20))

D.ROTATIONS = {
  HUNTER = {
    bete = {
      URGENCE_FEINDRE,
      E("FAUCON", "Aspect du faucon, s'il n'est pas actif", BUFF_MOI),
      E("MARQUE", "Marque du chasseur sur la cible, si elle n'y est pas", DEBUFF, PRET),
      E("AURA_PRECISION", "Aura de précision, si tu l'as apprise et qu'elle n'est pas active", BUFF_MOI),
      E("SERPENT", "Morsure de serpent, si elle n'y est pas (pas sur un monstre qui meurt vite)", DEBUFF, PRET),
      E("TIR_RAPIDE", "Tir rapide, dès qu'il est prêt (les combats qui comptent)", PRET),
      E("COURROUX", "Courroux bestial, dès qu'il est prêt", PRET),
      E("ORDRE", "Ordre de tuer, dès qu'il est prêt", PRET),
      E("INTIMIDATION", "Intimidation, dès qu'elle est prête", PRET),
      E("FUSILLADE", "Fusillade quand 2 monstres ou plus sont sur toi", PRET, "ennemisProches>=2"),
      E("APPEL_FAUCON", "Appel du faucon, dès qu'il est prêt (il partage sa recharge avec Tir des arcanes)", PRET),
      E("VISEE", "Visée, dès qu'elle est prête", PRET),
      E("ARCANES", "Tir des arcanes, dès qu'il est prêt", PRET),
      E("FUSILLADE", "Fusillade, dès qu'elle est prête", PRET),
      E("AUTO", "Tir automatique le reste du temps"),
    },
    precision = {
      URGENCE_FEINDRE,
      E("FAUCON", "Aspect du faucon, s'il n'est pas actif", BUFF_MOI),
      E("MARQUE", "Marque du chasseur sur la cible, si elle n'y est pas", DEBUFF, PRET),
      E("AURA_PRECISION", "Aura de précision, si elle n'est pas active (elle aide tout le groupe)", BUFF_MOI),
      E("TIR_RAPIDE", "Tir rapide, dès qu'il est prêt (les combats qui comptent)", PRET),
      E("SERPENT", "Morsure de serpent, si elle n'y est pas", DEBUFF, PRET),
      E("FUSILLADE", "Fusillade quand 2 monstres ou plus sont sur toi", PRET, "ennemisProches>=2"),
      E("VISEE", "Visée, dès qu'elle est prête", PRET),
      E("ARCANES", "Tir des arcanes, dès qu'il est prêt", PRET),
      E("FUSILLADE", "Fusillade, dès qu'elle est prête", PRET),
      E("AUTO", "Tir automatique le reste du temps"),
    },
    survie = {
      URGENCE_FEINDRE,
      E("DISSUASION", "Dissuasion si tu es à moins de 35 % de vie", PRET, VIE_MOI(35)),
      E("FAUCON", "Aspect du faucon, s'il n'est pas actif", BUFF_MOI),
      E("MARQUE", "Marque du chasseur sur la cible, si elle n'y est pas", DEBUFF, PRET),
      E("SERPENT", "Morsure de serpent, si elle n'y est pas", DEBUFF, PRET),
      E("MANGOUSTE", "Morsure de la mangouste, dès qu'elle est prête (au corps à corps)", PRET),
      E("RAPTOR", "Attaque du raptor, dès qu'elle est prête (au corps à corps)", PRET),
      E("ARCANES", "Tir des arcanes, dès qu'il est prêt (à distance)", PRET),
    },
  },

  PALADIN = {
    vindicte = {
      URGENCE_IMPOSITION,
      URGENCE_BOUCLIER,
      E("AURA_VINDICTE", "Aura de vindicte, si elle n'est pas active", BUFF_MOI),
      E("BENEDICTION_PUISSANCE", "Bénédiction de puissance sur toi, si elle n'y est pas (elle dure une heure)", BUFF_MOI),
      E("SCEAU_AUTORITE", "Sceau d'autorité (de piété avant le niveau 20), s'il n'est pas actif", BUFF_MOI),
      E("JUGEMENT", "Jugement, dès qu'il est prêt", PRET),
      E("FRAPPE_SACREE", "Frappe sacrée, dès qu'elle est prête", PRET),
      E("MARTEAU_COLERE", "Marteau de la colère quand la cible a moins de 20 % de vie", PRET, "vie<20"),
      E("EXORCISME", "Exorcisme sur un mort-vivant ou un démon", PRET, MORT_OU_DEMON),
      E("CONSECRATION", "Consécration quand 2 monstres ou plus sont collés à toi (avec parcimonie : elle coûte cher en mana)", PRET, "ennemisProches>=2"),
    },
    protection = {
      URGENCE_IMPOSITION,
      URGENCE_BOUCLIER,
      E("REMPART", "Rempart du templier si tu es à moins de 40 % de vie", PRET, VIE_MOI(40)),
      E("FUREUR", "Fureur vertueuse active (sinon tu ne tiens pas les monstres)", BUFF_MOI),
      E("SCEAU_FUREUR", "Sceau de fureur, s'il n'est pas actif", BUFF_MOI),
      E("SCEAU_PIETE", "Sceau de piété, s'il n'est pas actif (tant que tu n'as pas le Sceau de fureur)", BUFF_MOI, { "buffAbsent", "SCEAU_FUREUR" }),
      E("JUGEMENT", "Jugement, dès qu'il est prêt (il reprend aussi une cible qui ne te vise pas)", PRET),
      E("BOUCLIER_SACRE", "Bouclier sacré, dès qu'il est prêt", PRET),
      E("FRAPPE_SACREE", "Frappe sacrée, dès qu'elle est prête", PRET),
      E("BOUCLIER_VENGEUR", "Bouclier du vengeur, dès qu'il est prêt", PRET),
      E("CONSECRATION", "Consécration quand 2 monstres ou plus sont collés à toi (entretiens-la)", PRET, "ennemisProches>=2"),
      E("EXORCISME", "Exorcisme sur un mort-vivant ou un démon", PRET, MORT_OU_DEMON),
    },
    sacre = {
      URGENCE_IMPOSITION,
      URGENCE_BOUCLIER,
      E("SCEAU_SAGESSE", "Sceau de sagesse, s'il n'est pas actif (il rend du mana)", BUFF_MOI),
      E("HORION_SACRE", "Horion sacré, dès qu'il est prêt (sur l'allié blessé, ou sur un monstre pour le tuer)", PRET),
      E("ECLAIR_LUMINEUX", "Éclair lumineux sur l'allié blessé pour un soin rapide", PRET),
      E("LUMIERE_SACREE", "Lumière sacrée sur l'allié blessé pour un gros soin", PRET),
      E("JUGEMENT", "Jugement, dès qu'il est prêt (il garde ton mana)", PRET),
    },
  },

  WARRIOR = {
    armes = {
      E("CRI_INTIMIDATION", "Cri d'intimidation si tu es à moins de 25 % de vie (pour fuir)", PRET, VIE_MOI(25)),
      E("CRI_GUERRE", "Cri de guerre, s'il n'est pas actif", BUFF_MOI),
      E("TEMERITE", "Témérité, dès qu'elle est prête et que la cible a moins de 20 % de vie", PRET, "vie<20"),
      E("FRACASSER", "Fracasser armure sur la cible, si elle n'y est pas", DEBUFF, PRET),
      E("FULGURANCE", "Fulgurance dès qu'elle est disponible (après une esquive de la cible)", PRET),
      E("FRAPPE_MORTELLE", "Frappe mortelle, dès qu'elle est prête", PRET),
      E("POURFENDRE", "Pourfendre, s'il n'y est pas (si la cible survit quelques secondes)", DEBUFF, PRET),
      E("EXECUTION", "Exécution quand la cible a moins de 20 % de vie", PRET, "vie<20"),
      E("BALAYANTES", "Frappes balayantes quand 2 monstres ou plus sont sur toi", PRET, "ennemisProches>=2"),
      E("TOURBILLON", "Tourbillon quand 2 monstres ou plus sont sur toi", PRET, "ennemisProches>=2"),
      E("ENCHAINEMENT", "Enchaînement quand 2 monstres ou plus sont sur toi", PRET, "ennemisProches>=2"),
      E("HEURTOIR", "Heurtoir, dès qu'il est prêt", PRET),
      E("FRAPPE_HEROIQUE", "Frappe héroïque si tu as de la rage de reste", PRET),
    },
    fureur = {
      E("CRI_INTIMIDATION", "Cri d'intimidation si tu es à moins de 25 % de vie (pour fuir)", PRET, VIE_MOI(25)),
      E("CRI_GUERRE", "Cri de guerre, s'il n'est pas actif", BUFF_MOI),
      E("SOUHAIT_MORTEL", "Souhait mortel, dès qu'il est prêt", PRET),
      E("TEMERITE", "Témérité, dès qu'elle est prête et que la cible a moins de 20 % de vie", PRET, "vie<20"),
      E("FRACASSER", "Fracasser armure sur la cible, si elle n'y est pas", DEBUFF, PRET),
      E("EXECUTION", "Exécution quand la cible a moins de 20 % de vie", PRET, "vie<20"),
      E("SANGUINAIRE", "Sanguinaire, dès qu'il est prêt", PRET),
      E("TOURBILLON", "Tourbillon, dès qu'il est prêt", PRET),
      E("FULGURANCE", "Fulgurance dès qu'elle est disponible (après une esquive de la cible)", PRET),
      E("POURFENDRE", "Pourfendre, s'il n'y est pas (si la cible survit quelques secondes)", DEBUFF, PRET),
      E("FRAPPE_HEROIQUE", "Frappe héroïque si tu as de la rage de reste", PRET),
    },
    protection = {
      E("MUR", "Mur protecteur si tu es à moins de 30 % de vie", PRET, VIE_MOI(30)),
      E("DERNIER_REMPART", "Dernier rempart si tu es à moins de 30 % de vie", PRET, VIE_MOI(30)),
      E("CRI_GUERRE", "Cri de guerre, s'il n'est pas actif", BUFF_MOI),
      E("HEURT_BOUCLIER", "Heurt de bouclier, dès qu'il est prêt", PRET),
      E("VENGEANCE", "Vengeance, dès qu'elle est disponible (après une esquive, une parade ou un blocage)", PRET),
      E("FRACASSER", "Fracasser armure sur la cible, si elle n'y est pas (jusqu'à 5 fois)", DEBUFF, PRET),
      E("TONNERRE", "Coup de tonnerre, s'il n'y est pas", DEBUFF, PRET),
      E("DEMORALISANT", "Cri démoralisant, s'il n'y est pas", DEBUFF, PRET),
      E("ENCHAINEMENT", "Enchaînement quand 2 monstres ou plus sont sur toi", PRET, "ennemisProches>=2"),
      E("POURFENDRE", "Pourfendre, s'il n'y est pas", DEBUFF, PRET),
      E("FRAPPE_HEROIQUE", "Frappe héroïque si tu as de la rage de reste (sans retarder Heurt de bouclier ni Vengeance)", PRET),
    },
  },

  ROGUE = {
    assassinat = {
      E("DISPARITION", "Disparition si tu es à moins de 25 % de vie (pour fuir)", PRET, VIE_MOI(25)),
      E("ESQUIVE", "Esquive si tu es à moins de 40 % de vie", PRET, VIE_MOI(40)),
      E("DEBONDAGE", "Débondage à 2 points de combo ou plus, s'il n'est pas actif", BUFF_MOI, PRET, "pointsCombo>=2"),
      E("EVISCERATION", "Éviscération à 5 points de combo", PRET, "pointsCombo>=5"),
      E("MUTILATION", "Mutilation, dès qu'elle est prête (deux points de combo)", PRET),
      E("SOURNOISE", "Attaque sournoise, dès qu'elle est prête (derrière la cible, aux dagues)", PRET),
      E("SINISTRE", "Attaque pernicieuse le reste du temps", PRET),
    },
    combat = {
      E("DISPARITION", "Disparition si tu es à moins de 25 % de vie (pour fuir)", PRET, VIE_MOI(25)),
      E("ESQUIVE", "Esquive si tu es à moins de 40 % de vie", PRET, VIE_MOI(40)),
      E("DEBONDAGE", "Débondage à 2 points de combo ou plus, s'il n'est pas actif", BUFF_MOI, PRET, "pointsCombo>=2"),
      E("DELUGE", "Déluge de lames, dès qu'il est prêt", PRET),
      E("POUSSEE", "Poussée d'adrénaline, dès qu'elle est prête (sur une cible qui vit longtemps)", PRET),
      E("EVISCERATION", "Éviscération à 5 points de combo", PRET, "pointsCombo>=5"),
      E("SINISTRE", "Attaque pernicieuse pour faire des points de combo", PRET),
    },
    finesse = {
      E("DISPARITION", "Disparition si tu es à moins de 25 % de vie (pour fuir)", PRET, VIE_MOI(25)),
      E("ESQUIVE", "Esquive si tu es à moins de 40 % de vie", PRET, VIE_MOI(40)),
      E("DEBONDAGE", "Débondage à 2 points de combo ou plus, s'il n'est pas actif", BUFF_MOI, PRET, "pointsCombo>=2"),
      E("FRAPPE_FANTOME", "Frappe fantomatique, dès qu'elle est prête", PRET),
      E("RUPTURE", "Rupture à 5 points de combo, si elle n'y est pas (cible qui vit longtemps)", DEBUFF, PRET, "pointsCombo>=5"),
      E("EVISCERATION", "Éviscération à 5 points de combo", PRET, "pointsCombo>=5"),
      E("HEMORRAGIE", "Hémorragie pour faire des points de combo", PRET),
      E("SINISTRE", "Attaque pernicieuse pour faire des points de combo", PRET),
    },
  },

  PRIEST = {
    ombre = {
      E("BOUCLIER", "Mot de pouvoir : Bouclier si tu es à moins de 50 % de vie", PRET, VIE_MOI(50)),
      E("FORTITUDE", "Mot de pouvoir : Endurance, s'il n'est pas actif", BUFF_MOI),
      E("FEU_INTERIEUR", "Feu intérieur, s'il n'est pas actif", BUFF_MOI),
      E("FORME_OMBRE", "Forme d'Ombre, si elle n'est pas active", BUFF_MOI),
      E("DOULEUR", "Mot de l'ombre : Douleur sur la cible, s'il n'y est pas", DEBUFF, PRET),
      E("PESTE", "Peste dévorante, si elle n'y est pas (si le mana suit)", DEBUFF, PRET),
      E("ATTAQUE_MENTALE", "Attaque mentale, dès qu'elle est prête", PRET),
      E("MORT", "Mot de l'ombre : Mort, dès qu'il est prêt (il te blesse si la cible survit : garde ta vie au-dessus de 40 %)", PRET),
      E("ETREINTE", "Étreinte vampirique, si elle n'est pas active", BUFF_MOI),
      E("FOUET", "Fouet mental le reste du temps (ne l'interromps pas)", PRET),
      E("CHATIMENT", "Châtiment avant d'avoir le Fouet mental", PRET),
    },
    sacre = {
      E("FORTITUDE", "Mot de pouvoir : Endurance, s'il n'est pas actif", BUFF_MOI),
      E("FEU_INTERIEUR", "Feu intérieur, s'il n'est pas actif", BUFF_MOI),
      E("BOUCLIER", "Mot de pouvoir : Bouclier sur celui qui prend les coups, avant un gros pull", PRET),
      E("PRIERE_GUERISON", "Prière de guérison sur le tank, dès qu'elle est prête", PRET),
      E("RENOVATION", "Rénovation sur le plus de blessés possible", PRET),
      E("NOVA_SACREE", "Nova sacrée quand 3 alliés ou plus sont blessés", PRET),
      E("SOINS_RAPIDES", "Soins rapides pour un besoin immédiat", PRET),
      E("SOINS_SUPERIEURS", "Soins supérieurs pour un gros dégât", PRET),
      E("SOINS_INFERIEURS", "Soins inférieurs avant d'avoir les Soins rapides", PRET),
    },
    discipline = {
      E("FORTITUDE", "Mot de pouvoir : Endurance, s'il n'est pas actif", BUFF_MOI),
      E("FEU_INTERIEUR", "Feu intérieur, s'il n'est pas actif", BUFF_MOI),
      E("BOUCLIER", "Mot de pouvoir : Bouclier sur celui qui prend les coups", PRET),
      E("RENOVATION", "Rénovation sur le blessé", PRET),
      E("SOINS_RAPIDES", "Soins rapides pour un besoin immédiat", PRET),
      E("SOINS_SUPERIEURS", "Soins supérieurs pour un gros dégât", PRET),
      E("CHATIMENT", "Châtiment pour les dégâts (la Discipline en tire un bon parti)", PRET),
    },
  },

  SHAMAN = {
    amelioration = {
      E("VAGUE_MINEURE", "Vague de soins mineure si tu es à moins de 35 % de vie", PRET, VIE_MOI(35)),
      E("VAGUE", "Vague de soins si tu es à moins de 50 % de vie (entre les combats)", PRET, VIE_MOI(50)),
      E("BOUCLIER_FOUDRE", "Bouclier de foudre, s'il n'est pas actif", BUFF_MOI),
      E("CHOC_FLAMMES", "Horion de flammes sur la cible, s'il n'y est pas (puis le Totem incendiaire)", DEBUFF, PRET),
      E("FRAPPE_TEMPETE", "Frappe-tempête, dès qu'elle est prête", PRET),
      E("NOVA_FEU", "Nova de feu quand 2 monstres ou plus sont sur toi", PRET, "ennemisProches>=2"),
      E("CHOC_TERRE", "Horion de terre en remplissage (interrompt aussi un sort)", PRET),
    },
    elementaire = {
      E("VAGUE", "Vague de soins si tu es à moins de 40 % de vie (entre les combats)", PRET, VIE_MOI(40)),
      E("BOUCLIER_FOUDRE", "Bouclier de foudre, s'il n'est pas actif", BUFF_MOI),
      E("CHOC_FLAMMES", "Horion de flammes sur la cible, s'il n'y est pas", DEBUFF, PRET),
      E("EXPLOSION_LAVE", "Explosion de lave, dès qu'elle est prête", PRET),
      E("CHAINE", "Chaîne d'éclairs quand 2 monstres ou plus sont sur toi", PRET, "ennemisProches>=2"),
      E("ECLAIR", "Éclair le reste du temps (le Totem incendiaire ou de lave d'abord)", PRET),
    },
    restauration = {
      E("BOUCLIER_EAU", "Bouclier d'eau, s'il n'est pas actif", BUFF_MOI),
      E("BOUCLIER_FOUDRE", "Bouclier de foudre, s'il n'est pas actif (seulement tant que tu n'as pas le Bouclier d'eau)", BUFF_MOI, { "buffAbsent", "BOUCLIER_EAU" }),
      E("REMOUS", "Remous sur le tank, dès qu'il est prêt", PRET),
      E("SALVE", "Salve de guérison quand plusieurs alliés groupés sont blessés", PRET),
      E("VAGUE_MINEURE", "Vague de soins mineure pour une urgence", PRET),
      E("VAGUE", "Vague de soins pour un soin efficace", PRET),
    },
  },

  MAGE = {
    givre = {
      E("BARRIERE_GLACE", "Barrière de glace si tu es à moins de 60 % de vie (et qu'un monstre est sur toi)", PRET, VIE_MOI(60)),
      E("ARMURE", "Armure de glace (ou du mage, de givre), si aucune n'est active", BUFF_MOI),
      E("ARCANE_INT", "Intelligence des arcanes, si elle n'est pas active", BUFF_MOI),
      E("NOVA_GIVRE", "Nova de givre quand 2 monstres ou plus sont sur toi, puis recule", PRET, "ennemisProches>=2"),
      E("BLIZZARD", "Blizzard quand 3 monstres ou plus sont sur toi", PRET, "ennemisProches>=3"),
      E("ECLAIR_GIVRE", "Éclair de givre le reste du temps (Javelot de glace si la cible est gelée)", PRET),
      E("BOULE_FEU", "Boule de feu si Éclair de givre n'est pas disponible", PRET),
    },
    feu = {
      E("BARRIERE_GLACE", "Barrière de glace si tu es à moins de 60 % de vie, si tu l'as apprise", PRET, VIE_MOI(60)),
      E("ARMURE", "Armure du mage (ou de glace), si aucune n'est active", BUFF_MOI),
      E("ARCANE_INT", "Intelligence des arcanes, si elle n'est pas active", BUFF_MOI),
      E("EXPLOSION_FEU", "Explosion de feu, dès qu'elle est prête", PRET),
      E("EXPLOSION_ARCANES", "Explosion des arcanes quand 3 monstres ou plus sont collés à toi", PRET, "ennemisProches>=3"),
      E("BLIZZARD", "Blizzard quand 3 monstres ou plus sont sur toi", PRET, "ennemisProches>=3"),
      E("BOULE_FEU", "Boule de feu le reste du temps (Explosion pyrotechnique en ouverture, Brûlure au corps à corps)", PRET),
    },
    arcanes = {
      E("BARRIERE_GLACE", "Barrière de glace si tu es à moins de 60 % de vie, si tu l'as apprise", PRET, VIE_MOI(60)),
      E("ARMURE", "Armure du mage (ou de glace), si aucune n'est active", BUFF_MOI),
      E("ARCANE_INT", "Intelligence des arcanes, si elle n'est pas active", BUFF_MOI),
      E("EXPLOSION_ARCANES", "Explosion des arcanes quand 3 monstres ou plus sont collés à toi", PRET, "ennemisProches>=3"),
      E("DEFLAGRATION", "Déflagration des arcanes, dès qu'elle est prête (Projectiles des arcanes quand ils sont gratuits)", PRET),
      E("PROJ_ARCANES", "Projectiles des arcanes avant d'avoir la Déflagration", PRET),
      E("ECLAIR_GIVRE", "Éclair de givre si ton mana est bas", PRET),
    },
  },

  WARLOCK = {
    affliction = {
      E("DRAIN_VIE", "Drain de vie si tu es à moins de 40 % de vie", PRET, VIE_MOI(40)),
      E("ARMURE", "Armure démoniaque (ou Peau de démon), si elle n'est pas active", BUFF_MOI),
      E("CORRUPTION", "Corruption sur la cible, si elle n'y est pas", DEBUFF, PRET),
      E("AGONIE", "Malédiction d'agonie, si elle n'y est pas", DEBUFF, PRET),
      E("IMMOLATION", "Immolation, si elle n'y est pas (sur une cible qui vit longtemps)", DEBUFF, PRET),
      E("SIPHON_VIE", "Siphon de vie, s'il n'y est pas", DEBUFF, PRET),
      E("MAL_ELEMENTS", "Malédiction des éléments, si elle n'y est pas (cible qui vit longtemps)", DEBUFF, PRET),
      E("DRAIN_AME", "Drain d'âme quand la cible a moins de 25 % de vie, pour un fragment", PRET, "vie<25"),
      E("DRAIN_VIE", "Drain de vie le reste du temps", PRET),
      E("TRAIT_OMBRE", "Trait de l'ombre avant d'avoir le Drain de vie", PRET),
    },
    demonologie = {
      E("DRAIN_VIE", "Drain de vie si tu es à moins de 40 % de vie", PRET, VIE_MOI(40)),
      E("ARMURE", "Armure démoniaque (ou Peau de démon), si elle n'est pas active", BUFF_MOI),
      E("AGONIE", "Malédiction d'agonie, si elle n'y est pas", DEBUFF, PRET),
      E("CORRUPTION", "Corruption sur la cible, si elle n'y est pas", DEBUFF, PRET),
      E("IMMOLATION", "Immolation, si elle n'y est pas", DEBUFF, PRET),
      E("DOULEUR_BRULANTE", "Douleur brûlante pour marquer la cible (ton démon la tient), dès qu'elle est prête", PRET),
      E("DRAIN_VIE", "Drain de vie le reste du temps", PRET),
    },
    destruction = {
      E("DRAIN_VIE", "Drain de vie si tu es à moins de 40 % de vie", PRET, VIE_MOI(40)),
      E("ARMURE", "Armure démoniaque (ou Peau de démon), si elle n'est pas active", BUFF_MOI),
      E("IMMOLATION", "Immolation sur la cible, si elle n'y est pas", DEBUFF, PRET),
      E("MAL_ELEMENTS", "Malédiction des éléments, si elle n'y est pas (cible qui vit longtemps)", DEBUFF, PRET),
      E("CONFLAGRATION", "Conflagration, dès qu'elle est prête (juste avant la fin d'Immolation)", PRET),
      E("BRULURE_OMBRE", "Brûlure de l'ombre quand la cible a moins de 20 % de vie", PRET, "vie<20"),
      E("INCINERATION", "Incinération, ton sort principal quand tu l'as", PRET),
      E("TRAIT_OMBRE", "Trait de l'ombre le reste du temps", PRET),
    },
  },

  DRUID = {
    -- Chat et ours dans la même liste : un sort de l'autre forme n'est pas « prêt », il est sauté tout seul.
    farouche = {
      E("MARQUE_FAUVE", "Marque du fauve, si elle n'est pas active (hors forme)", BUFF_MOI),
      E("EPINES", "Épines, si elles ne sont pas actives (hors forme)", BUFF_MOI),
      E("LUCIOLES", "Lucioles sur la cible, si elles n'y sont pas", DEBUFF, PRET),
      E("DECHIRURE", "Déchirure à 5 points de combo, si elle n'y est pas (cible qui vit longtemps)", DEBUFF, PRET, "pointsCombo>=5"),
      E("MORSURE_FEROCE", "Morsure féroce à 5 points de combo", PRET, "pointsCombo>=5"),
      E("EVENTRER", "Éventrer, s'il n'y est pas (pas sur une cible qui va mourir)", DEBUFF, PRET),
      E("LAMBEAU", "Lambeau pour faire des points de combo (derrière la cible)", PRET),
      E("GRIFFE", "Griffe pour faire des points de combo", PRET),
      E("RUGISSEMENT_DEM", "En ours : Rugissement démoralisant, s'il n'y est pas", DEBUFF, PRET),
      E("BALAYAGE", "En ours : Balayage quand 2 monstres ou plus sont sur toi", PRET, "ennemisProches>=2"),
      E("LACERATION", "En ours : Lacération, dès qu'elle est prête", PRET),
      E("MUTILER", "En ours : Mutiler, dès qu'il est prêt (cible seule)", PRET),
    },
    gardien = {
      E("ECORCE", "Écorce si tu es à moins de 50 % de vie", PRET, VIE_MOI(50)),
      E("RUGISSEMENT_DEM", "Rugissement démoralisant, s'il n'y est pas", DEBUFF, PRET),
      E("LUCIOLES", "Lucioles sur la cible, si elles n'y sont pas", DEBUFF, PRET),
      E("LACERATION", "Lacération, dès qu'elle est prête", PRET),
      E("BALAYAGE", "Balayage quand 2 monstres ou plus sont sur toi", PRET, "ennemisProches>=2"),
      E("MUTILER", "Mutiler, dès qu'il est prêt", PRET),
    },
    equilibre = {
      E("ECORCE", "Écorce si tu es à moins de 50 % de vie", PRET, VIE_MOI(50)),
      E("MARQUE_FAUVE", "Marque du fauve, si elle n'est pas active", BUFF_MOI),
      E("EPINES", "Épines, si elles ne sont pas actives", BUFF_MOI),
      E("ECLAT_LUNAIRE", "Éclat lunaire sur la cible, s'il n'y est pas", DEBUFF, PRET),
      E("ESSAIM", "Essaim d'insectes sur la cible, s'il n'y est pas", DEBUFF, PRET),
      E("ECLAT_STELLAIRE", "Éclat stellaire, ton sort principal quand tu l'as (Colère après un Éclat stellaire qui critique)", PRET),
      E("COLERE", "Colère avant d'avoir l'Éclat stellaire", PRET),
    },
    restauration = {
      E("MARQUE_FAUVE", "Marque du fauve, si elle n'est pas active", BUFF_MOI),
      E("EPINES", "Épines, si elles ne sont pas actives", BUFF_MOI),
      E("PROMPT_RETABLISSEMENT", "Prompt rétablissement sur un allié qui a un de tes soins sur la durée", PRET),
      E("RAJEUNISSEMENT", "Récupération sur le plus de blessés possible (elle se cumule avec Rétablissement)", PRET),
      E("RETABLISSEMENT", "Rétablissement pour un besoin rapide", PRET),
      E("TOUCHER_GUERISON", "Toucher de guérison pour un gros soin", PRET),
    },
  },
}

-- ============================================================ builds de talents
-- BUILDS[classe][spécialisation][situation] = liste ordonnée, dans l'ordre où prendre les points.
-- Chaque entrée est T(nom français, nom anglais, rangs voulus, spellID du talent…) : Conseiller la retrouve dans
-- l'arbre du personnage par ses spellID d'abord, puis par son nom (français, puis anglais). Une entrée
-- qu'il ne retrouve pas est sautée, comptée et montrée dans l'onglet Talents (« /cs etat » donne ses noms) :
-- « /cs export » écrit les vrais noms du jeu pour les corriger. La forme { nodeID = n, rangs = n } marche aussi.
-- Situations : solo (montée), groupe ; donjon et raid retombent sur groupe quand ils sont absents.
-- Ordres tirés des fiches de outils/donnees-conseiller/ (guides Forever en bêta, niveau 30 et 5 points
-- Legacy : l'ordre des niveaux 31 à 60 est une projection). Les rangs voulus sont les rangs maximum de Classic
-- quand une fiche n'en donne pas : si l'arbre du jeu en a moins, Conseiller plafonne à son maximum.
-- Les noms français sont de mémoire (client Classic) : un nom faux se voit tout de suite, il est compté « non reconnu ».
local function T(nom, nomEN, rangs, ...)
  return { nom = nom, nomEN = nomEN, rangs = rangs, sorts = { ... } }
end

-- Une date par classe : la dernière fois que la fiche et le build ont été recoupés avec les guides.
D.DATES_BUILDS = {
  HUNTER = "10/11/2026", PALADIN = "10/11/2026", WARRIOR = "10/11/2026", ROGUE = "10/11/2026",
  PRIEST = "10/11/2026", SHAMAN = "10/11/2026", MAGE = "10/11/2026", WARLOCK = "10/11/2026",
  DRUID = "10/11/2026",
}

local B = {}

-- Chasseur : Maîtrise des bêtes (ordre Method, niveaux 10 à 60), puis Précision pour les 20 derniers points.
B.CHASSEUR_BETE = {
  T("Aspects mortels", "Deadly Aspects", 5),
  T("Feu focalisé", "Focused Fire", 2),
  T("Ranimation du familier améliorée", "Improved Revive Pet", 2),
  T("Entraînement à l'endurance", "Endurance Training", 1),
  T("Cheminement", "Pathfinding", 2),
  T("Férocité", "Ferocity", 5),
  T("Fureur déchaînée", "Unleashed Fury", 4),
  T("Appel du faucon", "Summon Hawk", 1),
  T("Rapidité bestiale", "Bestial Swiftness", 1),
  T("Frénésie", "Frenzy", 4),
  T("Intimidation", "Intimidation", 1, 19577),
  T("Discipline bestiale", "Bestial Discipline", 2),
  T("Courroux bestial", "Bestial Wrath", 1, 19574),
  T("Attaques mortelles", "Lethal Attacks", 5),
  T("Visée précise", "Careful Aim", 3),
  T("Mise à mort rapide", "Rapid Killing", 2),
  T("Efficacité", "Efficiency", 5),
  T("Aura de précision", "Trueshot Aura", 1, 19506),
  T("Tirs fatals", "Mortal Shots", 4),
}
-- Chasseur : Précision (alternative de groupe et de raid ; ordre des guides Forever, sans rangs publiés).
B.CHASSEUR_PRECISION = {
  T("Attaques mortelles", "Lethal Attacks", 5),
  T("Visée précise", "Careful Aim", 3),
  T("Mise à mort rapide", "Rapid Killing", 2),
  T("Tirs fatals", "Mortal Shots", 5),
  T("Efficacité", "Efficiency", 5),
  T("Aura de précision", "Trueshot Aura", 1, 19506),
  T("Récupération rapide", "Rapid Recuperation", 2),
}

-- Paladin : Vindicte (Method et Tavern, niveau 30 puis projection).
B.PALADIN_VINDICTE = {
  T("Bénédiction", "Benediction", 5),
  T("Jugement sanctifié", "Sanctified Judgement", 3),
  T("Jugement amélioré", "Improved Judgement", 1),
  T("Poursuite de la justice", "Pursuit of Justice", 2),
  T("Conviction", "Conviction", 5),
  T("Arbitre sacré", "Sacred Arbiter", 1),
  T("Sceau d'autorité", "Seal of Command", 1, 20375),
  T("Conduit sacré", "Holy Conduit", 1),
  T("Vengeance", "Vengeance", 5),
  T("Spécialisation armes à deux mains", "Two-Handed Weapon Specialization", 3),
  T("Repentir", "Repentance", 1, 20066),
}
-- Paladin : Protection 0/26/0 (Tavern).
B.PALADIN_PROTECTION = {
  T("Redoute", "Redoubt", 5),
  T("Spécialisation bouclier", "Shield Specialization", 3),
  T("Précision", "Precision", 3),
  T("Anticipation", "Anticipation", 3),
  T("Sceau de fureur amélioré", "Improved Seal of Fury", 3),
  T("Fureur vertueuse améliorée", "Improved Righteous Fury", 3),
  T("Spécialisation arme à une main", "One-Handed Weapon Specialization", 5),
  T("Jugement rapide", "Swift Judgement", 1),
  T("Rempart du templier", "Templar's Bulwark", 1),
  T("Sanction", "Reckoning", 4),
}
-- Paladin : Sacré 26/0/0 (Tavern).
B.PALADIN_SACRE = {
  T("Voix de la vérité", "Voice of Truth", 5),
  T("Pureté du pouvoir", "Purifying Power", 1),
  T("Lumière guérisseuse", "Healing Light", 3),
  T("Concentration spirituelle", "Spiritual Focus", 5),
  T("Illumination", "Illumination", 5),
  T("Horion sacré", "Holy Shock", 1, 20473),
  T("Précision divine", "Divine Precision", 1),
  T("Puissance sacrée", "Holy Power", 1),
  T("Révérence", "Reverence", 3),
  T("Faveur divine", "Divine Favor", 1, 20216),
}

-- Guerrier : Armes à deux mains (ordre Method, spécialisation de donjon), puis les talents cités à côté.
B.GUERRIER_ARMES = {
  T("Pourfendre amélioré", "Improved Rend", 3),
  T("Maîtrise tactique", "Tactical Mastery", 5),
  T("Blessures profondes", "Deep Wounds", 3),
  T("Frisson sanguin", "Bloodthrill", 4),
  T("Frappes balayantes", "Sweeping Strikes", 1, 12328),
  T("Maître d'armes", "Weaponmaster", 2),
  T("Frappe mortelle", "Mortal Strike", 1, 12294),
  T("Colère débridée", "Unbridled Wrath", 5),
  T("Enrager", "Enrage", 5),
  T("Frappe héroïque améliorée", "Improved Heroic Strike", 3),
  T("Fulgurance améliorée", "Improved Overpower", 2),
  T("Spécialisation armes à deux mains", "Two-Handed Weapon Specialization", 2),
  T("Heurtoir amélioré", "Improved Slam", 1),
}
-- Guerrier : Protection une main et bouclier (ordre Method, montée solo des gros groupes).
B.GUERRIER_PROTECTION = {
  T("Spécialisation bouclier", "Shield Specialization", 5),
  T("Coup de tonnerre amélioré", "Improved Thunder Clap", 3),
  T("Rage sanguinaire améliorée", "Improved Bloodrage", 2),
  T("Maître de la défense", "Master of Defense", 5),
  T("Vengeance améliorée", "Improved Revenge", 3),
  T("Avant-garde", "Vanguard", 1),
  T("Bastion", "Bastion", 1),
  T("Rage focalisée", "Focused Rage", 3),
  T("Anticipation", "Anticipation", 2),
  T("Défi", "Defiance", 5),
  T("Dernier rempart", "Last Stand", 1, 12975),
  T("Coup de commotion", "Concussion Blow", 1, 12809),
  T("Déviation", "Deflection", 5),
}
-- Guerrier : Fureur 0/26/0 (Tavern).
B.GUERRIER_FUREUR = {
  T("Cruauté", "Cruelty", 5),
  T("Colère débridée", "Unbridled Wrath", 5),
  T("Précision furieuse", "Furious Precision", 3),
  T("Folie sanguinaire", "Blood Craze", 2),
  T("Spécialisation armes doubles", "Dual Wield Specialization", 5),
  T("Souhait mortel", "Death Wish", 1, 12292),
  T("Exécution améliorée", "Improved Execute", 2),
  T("Enrager", "Enrage", 5),
  T("Rafale", "Flurry", 5),
}

-- Voleur : Combat (talents clés des guides Forever ; aucun ordre publié en texte, ordre indicatif).
B.VOLEUR_COMBAT = {
  T("Précision", "Precision", 5),
  T("Attaque pernicieuse améliorée", "Improved Sinister Strike", 2),
  T("Déluge de lames", "Blade Flurry", 1, 13877),
  T("Riposte", "Riposte", 1, 14251),
  T("Hache et taille", "Hack and Slash", 5),
  T("Sang froid", "Cold Blood", 1, 14177),
  T("Exécution sans faille", "Flawless Execution", 1),
  T("Poussée d'adrénaline", "Adrenaline Rush", 1, 13750),
}

-- Prêtre : Ombre (talents clés ; plan Method : soins jusqu'au niveau 39, Ombre ensuite).
B.PRETRE_OMBRE = {
  T("Spécialisation baguette", "Wand Specialization", 2),
  T("Mot de l'ombre : Douleur amélioré", "Improved Shadow Word: Pain", 2),
  T("Fouet mental", "Mind Flay", 1, 15407),
  T("Étreinte vampirique", "Vampiric Embrace", 1, 15286),
  T("Fouet mental amélioré", "Improved Mind Flay", 3),
  T("Tissage de l'ombre", "Shadow Weaving", 5),
  T("Silence", "Silence", 1, 15487),
  T("Méditation", "Meditation", 3),
  T("Forme d'Ombre", "Shadowform", 1, 15473),
}
-- Prêtre : Sacré 18/33/0 (Tavern, talents clés).
B.PRETRE_SACRE = {
  T("Rénovation améliorée", "Improved Renew", 3),
  T("Lien sacré", "Holy Binding", 5),
  T("Guidance spirituelle", "Spiritual Guidance", 5),
  T("Litanie de lumière", "Litany of Light", 3),
  T("Soins spirituels", "Spiritual Healing", 5),
  T("Prière de guérison", "Prayer of Mending", 1, 33076),
  T("Méditation", "Meditation", 3),
}

-- Chaman : Amélioration (ordre Method, talents clés).
B.CHAMAN_AMELIORATION = {
  T("Loup fantôme amélioré", "Improved Ghost Wolf", 2),
  T("Dextérité mentale", "Mental Dexterity", 2),
  T("Focalisation chamanique", "Shamanistic Focus", 1),
  T("Rafale", "Flurry", 5, 16256),
  T("Frappe-tempête", "Stormstrike", 1, 17364),
  T("Frappe-tempête améliorée", "Improved Stormstrike", 2),
  T("Arme du Maelström", "Maelstrom Weapon", 5),
}
-- Chaman : Élémentaire (talents clés cités, sans ordre publié).
B.CHAMAN_ELEMENTAIRE = {
  T("Attention", "Mindfulness", 3),
  T("Convection", "Convection", 5),
  T("Focalisation élémentaire", "Elemental Focus", 1),
  T("Épreuve du feu", "Trial by Fire", 3),
  T("Lié à la terre", "Earthbound", 1),
  T("Explosion de lave", "Lava Burst", 1),
  T("Surcharge de foudre", "Lightning Overload", 5),
}
-- Chaman : Restauration (talents clés cités).
B.CHAMAN_RESTAURATION = {
  T("Attention", "Mindfulness", 3),
  T("Bouclier d'eau", "Water Shield", 1),
  T("Totem de marée de mana", "Mana Tide Totem", 1, 16190),
  T("Soins ancestraux", "Ancestral Healing", 3),
  T("Maîtrise des marées", "Tidal Mastery", 5),
  T("Rapidité de la nature", "Nature's Swiftness", 1, 16188),
  T("Remous", "Riptide", 1),
}

-- Mage : Givre (ordre Method ; Arcanes en fin, niveaux 43 à 60).
B.MAGE_GIVRE = {
  T("Éclair de givre amélioré", "Improved Frostbolt", 5),
  T("Précision", "Precision", 3),
  T("Morsure de glace", "Frostbite", 3),
  T("Éclats de glace", "Ice Shards", 5),
  T("Brise-glace", "Shatter", 5),
  T("Doigts de givre", "Fingers of Frost", 1),
  T("Cône de froid amélioré", "Improved Cone of Cold", 3),
  T("Froid hivernal", "Winter's Chill", 5),
  T("Morsure de froid", "Cold Snap", 1, 12472),
  T("Barrière de glace", "Ice Barrier", 1, 11426),
  T("Canalisation améliorée", "Improved Channeling", 5),
  T("Concentration des arcanes", "Arcane Concentration", 5),
  T("Barrage de projectiles", "Missile Barrage", 5),
  T("Subtilité des arcanes", "Arcane Subtlety", 2),
  T("Déflagration des arcanes", "Arcane Blast", 1, 30451),
  T("Méditation des arcanes", "Arcane Meditation", 3),
}

-- Démoniste : Affliction, montée solo (Tavern : points par niveau ; Method donne un ordre un peu différent).
B.DEMONISTE_AFFLICTION = {
  T("Corruption améliorée", "Improved Corruption", 5),
  T("Suppression", "Suppression", 5),
  T("Puissance impie", "Unholy Power", 5),
  T("Énergies démoniaques", "Demonic Energies", 2),
  T("Drains améliorés", "Improved Drains", 3),
  T("Malédiction amplifiée", "Amplify Curse", 1),
  T("Fléau d'agonie amélioré", "Improved Bane of Agony", 2),
  T("Connexion améliorée", "Improved Life Tap", 2),
  T("Pandémie", "Pandemic", 3),
  T("Siphon d'âme", "Soul Siphon", 3),
  T("Malveillance", "Malevolence", 5),
  T("Maîtrise de l'ombre", "Shadow Mastery", 5),
  T("Siphon de vie", "Siphon Life", 1, 18265),
  T("Concentration gangrenée", "Fel Concentration", 3),
  T("Crépuscule", "Nightfall", 2),
  T("Trait de l'ombre amélioré", "Improved Shadow Bolt", 4),
}
-- Démoniste : Destruction 31/17/3 (Tavern).
B.DEMONISTE_DESTRUCTION = {
  T("Fléau", "Bane", 5),
  T("Cataclysme", "Cataclysm", 3),
  T("Séquelles", "Aftermath", 5),
  T("Brûlure de l'ombre", "Shadowburn", 1, 17877),
  T("Ruine", "Ruin", 1),
  T("Conflagration", "Conflagrate", 1, 17962),
  T("Flammes d'agonie", "Agonizing Flames", 3),
  T("Feu et soufre", "Fire and Brimstone", 3),
  T("Ombre et flamme", "Shadow and Flame", 5),
  T("Incinération", "Incinerate", 1, 29722),
  T("Suppression", "Suppression", 5),
  T("Connexion améliorée", "Improved Life Tap", 2),
  T("Corruption améliorée", "Improved Corruption", 5),
  T("Diablotin amélioré", "Improved Imp", 3),
  T("Malédiction amplifiée", "Amplify Curse", 1),
  T("Pandémie", "Pandemic", 3),
  T("Malveillance", "Malevolence", 1),
}
-- Démoniste : Démonologie 31/20 (Tavern, le démon tient les monstres).
B.DEMONISTE_DEMONOLOGIE = {
  T("Puissance impie", "Unholy Power", 5),
  T("Énergies démoniaques", "Demonic Energies", 2),
  T("Vitalité gangrenée", "Fel Vitality", 3),
  T("Maître invocateur", "Master Summoner", 2),
  T("Sayaad amélioré", "Improved Sayaad", 3),
  T("Marque démoniaque", "Demonic Brand", 3),
  T("Sacrifice démoniaque", "Demonic Sacrifice", 1),
  T("Lien spirituel", "Soul Link", 1),
  T("Connaissance démoniaque", "Demonic Knowledge", 3),
  T("Étreinte démoniaque", "Demonic Embrace", 5),
  T("Domination corrompue", "Fel Domination", 1),
  T("Maître démonologue", "Master Demonologist", 5),
  T("Pacte démoniaque", "Demonic Pact", 1),
}

-- Druide : Combat farouche, montée solo (Method et Tavern, talents cités par niveau).
B.DRUIDE_FAROUCHE_SOLO = {
  T("Férocité", "Ferocity", 5),
  T("Rapidité féline", "Feral Swiftness", 2),
  T("Charge farouche", "Feral Charge", 1, 16979),
  T("Discipline prédatrice", "Predatory Discipline", 1),
  T("Chef de la meute", "Leader of the Pack", 1, 17007),
  T("Frappes prédatrices", "Predatory Strikes", 3),
  T("Morsure primitive", "Primal Bite", 1),
  T("Pouvoir changeant", "Shifting Power", 1),
}
-- Druide : Combat farouche hybride 9/37/5 (Method et Tavern).
B.DRUIDE_FAROUCHE_GROUPE = {
  T("Férocité", "Ferocity", 5),
  T("Instinct farouche", "Feral Instinct", 3),
  T("Cuir épais", "Thick Hide", 3),
  T("Rapidité féline", "Feral Swiftness", 2),
  T("Charge farouche", "Feral Charge", 1, 16979),
  T("Morsure primitive", "Primal Bite", 1),
  T("Déchirer et lacérer", "Rend and Tear", 5),
  T("Lacération", "Lacerate", 1, 33745),
  T("Chef de la meute", "Leader of the Pack", 1, 17007),
  T("Réaction naturelle", "Natural Reaction", 3),
}
-- Druide : Restauration (talents clés de Tavern, par niveau).
B.DRUIDE_RESTAURATION = {
  T("Réflexion", "Reflection", 3),
  T("Éclosion", "Bloom", 3),
  T("Prompt rétablissement", "Swiftmend", 1, 18562),
  T("Rapidité de la nature", "Nature's Swiftness", 1, 17116),
  T("Croissance sauvage", "Wild Growth", 1),
}
-- Druide : Équilibre (talents clés cités).
B.DRUIDE_EQUILIBRE = {
  T("Colère améliorée", "Improved Wrath", 5),
  T("Lueur lunaire", "Moonglow", 3),
  T("Genèse", "Genesis", 5),
  T("Allonge de la nature", "Nature's Reach", 2),
  T("Essaim d'insectes", "Insect Swarm", 1, 5570),
  T("Éclipse", "Eclipse", 3),
  T("Éclat stellaire amélioré", "Improved Starfire", 5),
}

-- Qui prend quoi : la montée seule (solo) et le groupe (donjon, raid) de la spécialisation conseillée,
-- et celle d'un rôle qui manque (Protection, Sacré, Restauration…).
D.BUILDS = {
  HUNTER = {
    bete = { solo = B.CHASSEUR_BETE, groupe = B.CHASSEUR_BETE },
    precision = { groupe = B.CHASSEUR_PRECISION },
  },
  PALADIN = {
    vindicte = { solo = B.PALADIN_VINDICTE, groupe = B.PALADIN_VINDICTE },
    protection = { groupe = B.PALADIN_PROTECTION },
    sacre = { groupe = B.PALADIN_SACRE },
  },
  WARRIOR = {
    armes = { solo = B.GUERRIER_ARMES, groupe = B.GUERRIER_ARMES },
    fureur = { groupe = B.GUERRIER_FUREUR },
    protection = { solo = B.GUERRIER_PROTECTION, groupe = B.GUERRIER_PROTECTION },
  },
  ROGUE = {
    combat = { solo = B.VOLEUR_COMBAT, groupe = B.VOLEUR_COMBAT },
  },
  PRIEST = {
    ombre = { solo = B.PRETRE_OMBRE, groupe = B.PRETRE_OMBRE },
    sacre = { groupe = B.PRETRE_SACRE },
  },
  SHAMAN = {
    amelioration = { solo = B.CHAMAN_AMELIORATION, groupe = B.CHAMAN_AMELIORATION },
    elementaire = { groupe = B.CHAMAN_ELEMENTAIRE },
    restauration = { groupe = B.CHAMAN_RESTAURATION },
  },
  MAGE = {
    givre = { solo = B.MAGE_GIVRE, groupe = B.MAGE_GIVRE },
  },
  WARLOCK = {
    affliction = { solo = B.DEMONISTE_AFFLICTION },
    destruction = { groupe = B.DEMONISTE_DESTRUCTION },
    demonologie = { groupe = B.DEMONISTE_DEMONOLOGIE },
  },
  DRUID = {
    farouche = { solo = B.DRUIDE_FAROUCHE_SOLO, groupe = B.DRUIDE_FAROUCHE_GROUPE },
    restauration = { groupe = B.DRUIDE_RESTAURATION },
    equilibre = { groupe = B.DRUIDE_EQUILIBRE },
  },
}

-- ============================================================ métiers
-- Les paliers du jeu : plafond de compétence, niveau du joueur nécessaire, nom du palier.
D.PALIERS = {
  { plafond = 75, niveau = 1, nom = "Apprenti" },
  { plafond = 150, niveau = 10, nom = "Compagnon" },
  { plafond = 225, niveau = 20, nom = "Expert" },
  { plafond = 300, niveau = 35, nom = "Artisan" },
}

-- ============================================================ races
-- Par jeton de race (le deuxième retour de UnitRace). raciales : { nom, quand, actif }.
D.RACES = {
  Human = { nom = "Humain", raciales = {
    { "Perception", "Révèle les ennemis furtifs autour de toi : à lancer quand un voleur ou un druide se cache près de toi.", true },
    { "Diplomatie", "Plus de réputation gagnée : rien à faire.", false },
    { "L'esprit humain", "Un peu plus d'Esprit : rien à faire.", false },
  } },
  Dwarf = { nom = "Nain", raciales = {
    { "Forme de pierre", "Annule les poisons et les saignements et réduit les dégâts : garde-la pour les moments où tu vas mourir.", true },
    { "Résistance au givre", "Moins de dégâts de givre : rien à faire.", false },
    { "Chasse au trésor", "Montre les coffres sur la mini-carte.", true },
  } },
  NightElf = { nom = "Elfe de la nuit", raciales = {
    { "Camouflage dans l'ombre", "Te rend invisible hors combat : parfait pour fuir un groupe de monstres ou attendre ton groupe.", true },
    { "Rapidité", "Un peu plus d'esquive en permanence : rien à faire.", false },
    { "Esprit de l'elfe", "Quand tu meurs, tu reviens en esprit : plus rapide pour retrouver ton corps.", false },
  } },
  Gnome = { nom = "Gnome", raciales = {
    { "Évasion", "Te libère des entraves et des immobilisations : à lancer dès que tu es collé au sol.", true },
    { "Esprit vif", "Un peu plus de mana : rien à faire.", false },
    { "Spécialisation en ingénierie", "Un bonus à l'ingénierie : utile si tu en fais un métier.", false },
  } },
  Orc = { nom = "Orc", raciales = {
    { "Fureur sanguinaire", "Plus de dégâts un court moment : à lancer au début d'un gros combat.", true },
    { "Robustesse", "Moins de chances d'être étourdi : rien à faire.", false },
    { "Commandement", "Ton familier fait plus de dégâts : utile pour les classes avec familier.", false },
  } },
  Scourge = { nom = "Mort-vivant", raciales = {
    { "Volonté des Réprouvés", "Te libère de la peur, du charme et du sommeil : à lancer dès qu'on te contrôle.", true },
    { "Cannibalisme", "Mange un cadavre pour te soigner hors combat : plus de nourriture à acheter.", true },
    { "Respiration aquatique", "Tu respires sous l'eau très longtemps : rien à faire.", false },
  } },
  Tauren = { nom = "Tauren", raciales = {
    { "Choc martial", "Étourdit les ennemis autour de toi : à lancer quand un groupe de monstres arrive sur toi.", true },
    { "Endurance", "Plus de points de vie : rien à faire.", false },
    { "Culture", "Plus vite en herboristerie : rien à faire.", false },
  } },
  Troll = { nom = "Troll", raciales = {
    { "Berserker", "Attaques plus rapides un court moment : à lancer au début d'un gros combat.", true },
    { "Régénération", "Ta vie remonte plus vite, même en combat : rien à faire.", false },
    { "Tueur de bêtes", "Plus de dégâts contre les bêtes : rien à faire.", false },
  } },
  BloodElf = { nom = "Elfe de sang", raciales = {
    { "Torrent arcanique", "Interrompt les sorts autour de toi et te rend de l'énergie ou du mana : à lancer quand un ennemi lance un sort.", true },
    { "Affinité magique", "Moins de dégâts de magie : rien à faire.", false },
  } },
  Draenei = { nom = "Draeneï", raciales = {
    { "Don des Naaru", "Un soin sur la durée sur toi ou un allié : à lancer quand quelqu'un est blessé et que le combat continue.", true },
    { "Présence héroïque", "Un peu plus de toucher pour toi et ton groupe : rien à faire.", false },
  } },
  Worgen = { nom = "Worgen", raciales = {
    { "Course sombre", "Course plus rapide un court moment : pour fuir ou rattraper.", true },
    { "Instincts de la bête", "Plus de dégâts de critique : rien à faire.", false },
  } },
  Goblin = { nom = "Gobelin", raciales = {
    { "Saut de fusée", "Un saut en avant : pour rattraper ou franchir un obstacle.", true },
    { "Bon vendeur", "Meilleurs prix chez le marchand : rien à faire.", false },
  } },
}
D.RACE_PAR_DEFAUT = { nom = "Ta race", raciales = {
  { "Capacités de race", "Ouvre ton grimoire : les capacités de ta race sont sur la page « Général ». Les actives se lancent comme un sort.", false },
} }

-- ============================================================ conseils génériques
D.CONSEILS_GENERIQUES = {
  solo = {
    "Soigne-toi entre deux combats plutôt que de manger quand tu as de quoi le faire.",
    "Ne pars pas vers un deuxième monstre avant d'avoir fini le premier.",
    "Un combat perdu ne se gagne pas en insistant : recule et utilise ta capacité de fuite.",
  },
  groupe = {
    "Laisse le tank prendre la menace avant de taper à fond.",
    "Surveille la barre de vie du tank et des soigneurs : c'est eux qui décident du rythme.",
    "Prévenez-vous par écrit avant de lancer un pull ou un gros sort.",
  },
}
