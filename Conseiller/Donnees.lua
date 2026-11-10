-- ============================================================================
-- Donnees.lua : TOUT ce que Conseiller sait des classes, des sorts, des métiers et des races.
-- Aucun code ici, que des tables : c'est le fichier à compléter pour ajouter une classe,
-- une rotation ou un build de talents. La logique est dans Logique.lua.
--
-- Pour ajouter une rotation (une classe, une spécialisation) :
--   1. déclarer les sorts dans ns.DONNEES.SORTS[CLASSE] : une clé, la liste des identifiants
--      possibles (du rang le plus haut au plus bas : le premier que le personnage connaît gagne)
--      et le nom français (secours : cherché dans le grimoire si aucun identifiant n'est connu) ;
--   2. écrire la liste de priorité dans ns.DONNEES.ROTATIONS[CLASSE][spécialisation] : des
--      entrées { sort = clé, si = { conditions }, texte = "la phrase du mode liste" } dans l'ordre :
--      la première dont les conditions sont vraies est le sort à lancer.
--   Conditions : "pret" (utilisable et recharge finie), "debuffAbsent" (ton affaiblissement n'est
--   pas sur la cible ; { "debuffAbsent", AUTRE_CLE } pour un autre sort), "buffAbsent" (l'effet n'est
--   pas sur toi), "ennemisProches>=3" (nombre d'ennemis en combat), "vie<20" (vie de la cible en %),
--   { "vie", "moi", 30 } (vie de ton personnage). Sans condition : toujours vrai.
--
-- Pour écrire un build de talents : voir BUILDS en bas (il faut les numéros de nœuds du jeu, que
-- « /cs export » écrit dans ConseillerDB.export après un /reload).
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
    choix = { solo = "bete", groupe = "precision" },
    raisons = {
      solo = "ton familier tient les monstres pendant que tu tires : la spécialisation la plus sûre seul.",
      groupe = "quelqu'un d'autre tient les monstres : tu peux tout miser sur les dégâts à distance.",
      donjon = "le tank tient les monstres : tout sur les dégâts à distance.",
      raid = "le tank tient les monstres : tout sur les dégâts à distance.",
    },
    conseils = {
      solo = {
        "Laisse ton familier prendre les coups, Grognement activé.",
        "Recule pendant qu'il tient le monstre : tu gardes la distance.",
        "Feindre la mort pour sortir d'un combat perdu.",
      },
      groupe = {
        "Mets ton familier en mode défensif et coupe son Grognement : sinon il vole les monstres au tank.",
        "Marque du chasseur sur la cible du tank, pas sur la tienne.",
        "Feindre la mort si un monstre te tape : il retourne sur le tank.",
      },
    },
    metiers = {
      { "Dépeçage + Travail du cuir", "Tu fabriques ton armure en cuir, puis en mailles au niveau 40, et le dépeçage se fait sur les bêtes que tu tues déjà.", 1 },
      { "Minage + Ingénierie", "Viseurs pour ton arme à distance et gadgets ; plus cher à monter.", 2 },
      { "Herboristerie + Minage", "Deux métiers de récolte : le plus d'or à l'hôtel des ventes.", 3 },
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
    choix = { solo = "vindicte", groupe = "vindicte" },
    parRole = { tank = "protection", soins = "sacre" },
    raisons = {
      solo = "tu tues vite et tu te soignes toi-même entre deux combats.",
      groupe = "ton groupe a ce qu'il lui faut en tank et en soins : tu apportes des dégâts de mêlée.",
      donjon = "le tank et le soigneur sont là : tu apportes des dégâts de mêlée.",
      raid = "il y a assez de tanks et de soigneurs : tu apportes des dégâts de mêlée.",
      tank = "ton groupe n'a pas de tank : tu prends les coups, les autres tapent.",
      soins = "ton groupe n'a pas de soigneur : tes soins gardent tout le monde en vie.",
    },
    conseils = {
      solo = {
        "Sceau d'autorité et Jugement : tu tues plus vite.",
        "Soigne-toi entre deux combats plutôt que de manger.",
        "Bouclier divin puis Pierre de foyer si tout tourne mal.",
      },
      groupe = {
        "Fureur vertueuse active en Protection, sinon les monstres partent sur tes alliés.",
        "Consécration dès qu'un groupe de monstres arrive, pour les prendre tous.",
        "Imposition des mains sur l'allié qui va mourir, pas forcément sur toi.",
      },
    },
    metiers = {
      { "Minage + Forge", "Tu forges ton armure en plaques et ton bouclier ; le minerai se trouve en route.", 1 },
      { "Couture + Enchantement", "Pour enchanter ton arme et celles de ton groupe.", 2 },
      { "Herboristerie + Alchimie", "Potions de soins pour les combats durs en groupe.", 3 },
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
    choix = { solo = "armes", groupe = "fureur" },
    parRole = { tank = "protection" },
    raisons = {
      solo = "une grosse arme à deux mains et des coups puissants : tu tues vite sans aide.",
      groupe = "un autre joueur tient les monstres : tu mises sur les dégâts.",
      donjon = "le tank est là : tout sur les dégâts.",
      raid = "il y a assez de tanks : tout sur les dégâts.",
      tank = "ton groupe n'a pas de tank : le guerrier est fait pour ça.",
    },
    conseils = {
      solo = {
        "Garde de la rage pour Frappe héroïque ou ton coup spécial : ne la laisse pas se perdre.",
        "Charge pour ouvrir le combat, Cri de guerre avant d'attaquer.",
        "Bandage entre deux combats : un guerrier n'a ni soins ni mana.",
      },
      groupe = {
        "En tank : Posture défensive, Provocation sur ce qui part vers les soigneurs.",
        "En dégâts : ne tape pas avant que le tank ait pris la menace.",
        "Cri de guerre aide tout le groupe : lance-le avant les combats.",
      },
    },
    metiers = {
      { "Minage + Forge", "Armure en plaques et armes forgées toi-même ; le minerai se trouve en route.", 1 },
      { "Dépeçage + Travail du cuir", "Pour t'équiper en attendant les plaques, et le dépeçage rapporte vite.", 2 },
      { "Herboristerie + Alchimie", "Potions de soins et de force : un guerrier n'a pas de soins à lui.", 3 },
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
    choix = { solo = "combat", groupe = "combat" },
    raisons = {
      solo = "des coups réguliers sans avoir besoin d'attendre : la spécialisation la plus simple seul.",
      groupe = "des dégâts réguliers en mêlée, et c'est la plus facile à jouer.",
      donjon = "des dégâts réguliers en mêlée, et c'est la plus facile à jouer.",
      raid = "des dégâts réguliers en mêlée.",
    },
    conseils = {
      solo = {
        "Ouvre toujours par un sort furtif : Embuscade ou Coup bas.",
        "Termine avec tes points de combo avant qu'ils ne se perdent.",
        "Évasion et Disparition te sortent d'un combat perdu.",
      },
      groupe = {
        "Reste derrière la cible : on ne passe pas devant le tank.",
        "Coup de pied pour interrompre les sorts, au bon moment : c'est ton rôle.",
        "Ne tape pas avant que le tank ait pris la menace, Disparition fait retomber la tienne.",
      },
    },
    metiers = {
      { "Dépeçage + Travail du cuir", "Ton armure est en cuir : tu la fabriques et tu dépèces ce que tu tues.", 1 },
      { "Ingénierie + Minage", "Gadgets et explosifs : plus long à monter.", 2 },
      { "Herboristerie + Alchimie", "Potions et poisons : l'alchimie se vend bien.", 3 },
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
    choix = { solo = "ombre", groupe = "ombre" },
    parRole = { soins = "sacre" },
    raisons = {
      solo = "tu tues avec des sorts à distance et tu te soignes : la spécialisation la plus autonome.",
      groupe = "ton groupe a déjà un soigneur : tu apportes des dégâts.",
      donjon = "le soigneur est là : tu apportes des dégâts.",
      raid = "il y a assez de soigneurs : tu apportes des dégâts.",
      soins = "ton groupe n'a pas de soigneur : tes soins gardent tout le monde en vie.",
    },
    conseils = {
      solo = {
        "Mot de pouvoir : Bouclier avant le combat, puis Châtiment ou Mot de l'ombre : Douleur.",
        "Soigne-toi entre deux combats : ne mange pas si tu as du mana.",
        "Cri psychique si deux monstres arrivent en même temps.",
      },
      groupe = {
        "Soigne d'abord le tank, puis les autres : surveille sa barre en premier.",
        "Garde du mana : un soigneur sans mana, c'est un groupe qui meurt.",
        "Mot de pouvoir : Bouclier sur celui qui prend les coups avant un gros pull.",
      },
    },
    metiers = {
      { "Couture + Enchantement", "Tes robes, tes sacs et l'enchantement de ton équipement.", 1 },
      { "Herboristerie + Alchimie", "Potions de mana et de soins : utile à tout le groupe.", 3 },
      { "Ingénierie + Minage", "Gadgets de dégâts ou de soins ; plus long à monter.", 2 },
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
    choix = { solo = "amelioration", groupe = "elementaire" },
    parRole = { soins = "restauration" },
    raisons = {
      solo = "tu frappes en mêlée avec des totems et des soins pour tenir : la plus sûre seul.",
      groupe = "ton groupe a déjà un soigneur : des sorts de dégâts à distance.",
      donjon = "le soigneur est là : des sorts de dégâts à distance.",
      raid = "il y a assez de soigneurs : des sorts de dégâts à distance.",
      soins = "ton groupe n'a pas de soigneur : tes soins et tes totems gardent tout le monde en vie.",
    },
    conseils = {
      solo = {
        "Pose tes totems avant un combat difficile, pas pendant.",
        "Horion de terre interrompt un sort ; Choc de flammes fait tomber un fuyard.",
        "Soigne-toi entre deux combats plutôt que de manger.",
      },
      groupe = {
        "Un totem utile pour ton groupe vaut mieux qu'un totem utile pour toi : regarde qui t'accompagne.",
        "Purification de la maladie et du poison : surveille les affaiblissements du groupe.",
        "Salve de guérison : garde-la pour quand plusieurs alliés sont blessés en même temps.",
      },
    },
    metiers = {
      { "Dépeçage + Travail du cuir", "Ton armure est en cuir puis en mailles au niveau 40.", 1 },
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
    choix = { solo = "givre", groupe = "feu" },
    raisons = {
      solo = "les monstres sont ralentis et gelés : tu en tues plusieurs sans jamais te faire toucher.",
      groupe = "de gros dégâts à distance : tu comptes sur le tank pour tenir les monstres.",
      donjon = "de gros dégâts à distance : tu comptes sur le tank pour tenir les monstres.",
      raid = "de gros dégâts à distance, régulièrement.",
    },
    conseils = {
      solo = {
        "Nova de givre puis recule : les monstres ralentis ne te rejoignent pas.",
        "Conjure de la nourriture et de l'eau : tu ne dépenses rien pour tes repas.",
        "Mouton ou Bloc de glace si deux monstres arrivent ensemble.",
      },
      groupe = {
        "Mets un monstre en Métamorphose pendant que le groupe tue les autres, si on te le demande.",
        "Ne tape pas avant que le tank ait pris la menace.",
        "Conjure de la nourriture et de l'eau pour tout le groupe : on t'en saura gré.",
      },
    },
    metiers = {
      { "Couture + Enchantement", "Tes robes, tes sacs et l'enchantement de ton équipement.", 1 },
      { "Ingénierie + Minage", "Gadgets : ils comptent dans les combats difficiles.", 2 },
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
    choix = { solo = "affliction", groupe = "destruction" },
    raisons = {
      solo = "des dégâts dans le temps, ton démon tient les monstres pendant que tu te soignes avec Drain de vie.",
      groupe = "de gros dégâts à distance : tu comptes sur le tank pour tenir les monstres.",
      donjon = "de gros dégâts à distance : tu comptes sur le tank pour tenir les monstres.",
      raid = "de gros dégâts à distance.",
    },
    conseils = {
      solo = {
        "Ton démon tient les monstres : un Marcheur du Vide (tank) rend tout plus simple.",
        "Fragments d'âme : tue les monstres qui en donnent pour ta réserve.",
        "Drain de vie pour te soigner pendant que tes dégâts continuent.",
      },
      groupe = {
        "Garde ton familier en mode passif si tu n'es pas tank : il vole la menace du tank.",
        "Pierre de soin avant un combat difficile : tu en donnes aussi à ton groupe.",
        "Invocation de groupe (Rituel d'invocation) : fais-le avant de commencer le donjon.",
      },
    },
    metiers = {
      { "Couture + Enchantement", "Tes robes, tes sacs et l'enchantement de ton équipement.", 1 },
      { "Ingénierie + Minage", "Gadgets de dégâts et d'urgence.", 2 },
      { "Herboristerie + Alchimie", "Potions : un démoniste dépense sa vie en dégâts.", 3 },
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
    choix = { solo = "farouche", groupe = "equilibre" },
    parRole = { tank = "farouche", soins = "restauration" },
    raisons = {
      solo = "en forme d'ours ou de chat tu tiens et tu tues : le druide le plus autonome.",
      groupe = "ton groupe a ce qu'il lui faut en tank et en soins : tu apportes des dégâts à distance.",
      donjon = "le tank et le soigneur sont là : tu apportes des dégâts à distance.",
      raid = "il y a assez de tanks et de soigneurs : tu apportes des dégâts à distance.",
      tank = "ton groupe n'a pas de tank : en forme d'ours, tu tiens les monstres.",
      soins = "ton groupe n'a pas de soigneur : tes soins sur la durée gardent tout le monde en vie.",
    },
    conseils = {
      solo = {
        "Change de forme selon le moment : ours pour tenir, chat pour tuer, humain pour te soigner.",
        "Sors de la forme pour te soigner entre deux combats.",
        "Ronces ou Sommeil de la bête si plusieurs monstres arrivent.",
      },
      groupe = {
        "En ours : Grondement pour prendre la menace, Rugissement pour tenir plusieurs monstres.",
        "En soigneur : Récupération sur le tank avant le combat, Rajeunissement pendant.",
        "Résurrection en combat (Renaissance) : garde-la pour le soigneur.",
      },
    },
    metiers = {
      { "Dépeçage + Travail du cuir", "Ton armure est en cuir : tu la fabriques et tu dépèces ce que tu tues.", 1 },
      { "Herboristerie + Alchimie", "Potions, élixirs et plantes à portée de main.", 2 },
      { "Minage + Ingénierie", "Gadgets ; le minerai se vend toujours.", 3 },
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
    armes = { FOR, PA, TOU, CRI, AGI, END },
    fureur = { FOR, PA, CRI, TOU, AGI, END },
    protection = { END, ARM, DEF, ESQ, PAR, BLV, FOR, TOU },
  },
  PALADIN = {
    sacre = { INT, PS, ESP, REG, END, CRI },
    protection = { END, ARM, DEF, BLV, FOR, ESQ, INT },
    vindicte = { FOR, PA, TOU, CRI, AGI, END },
  },
  HUNTER = {
    bete = { AGI, PAD, TOU, CRI, END, INT },
    precision = { AGI, PAD, TOU, CRI, INT, END },
    survie = { AGI, END, PAD, CRI, TOU, INT },
  },
  ROGUE = {
    assassinat = { AGI, PA, TOU, CRI, END, FOR },
    combat = { AGI, FOR, PA, TOU, CRI, END },
    finesse = { AGI, PA, CRI, TOU, END, FOR },
  },
  PRIEST = {
    discipline = { INT, PS, ESP, REG, END, CRI },
    sacre = { PS, INT, ESP, REG, END, CRI },
    ombre = { PS, TOU, CRI, INT, END, ESP },
  },
  SHAMAN = {
    elementaire = { PS, INT, CRI, TOU, END, ESP },
    amelioration = { FOR, AGI, PA, TOU, CRI, END },
    restauration = { INT, PS, REG, ESP, END, CRI },
  },
  MAGE = {
    arcanes = { PS, INT, TOU, CRI, END, ESP },
    feu = { PS, TOU, CRI, INT, END, ESP },
    givre = { PS, TOU, INT, CRI, END, ESP },
  },
  WARLOCK = {
    affliction = { PS, END, INT, TOU, CRI, ESP },
    demonologie = { END, PS, INT, ESP, TOU, CRI },
    destruction = { PS, TOU, CRI, INT, END, ESP },
  },
  DRUID = {
    equilibre = { PS, INT, TOU, CRI, END, ESP },
    farouche = { AGI, FOR, PA, CRI, TOU, END },
    gardien = { END, AGI, ARM, ESQ, CRI, TOU },
    restauration = { INT, PS, ESP, REG, END, CRI },
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
-- ids : du rang le plus haut au plus bas (identifiants de Classic ; sur Forever, à vérifier en jeu).
D.SORTS = {
  HUNTER = {
    AUTO = { nom = "Tir automatique", ids = { 75 } },
    MARQUE = { nom = "Marque du chasseur", ids = { 14325, 14324, 14323, 1130 } },
    SERPENT = { nom = "Morsure de serpent", ids = { 25295, 13555, 13554, 13553, 13552, 13551, 13550, 13549, 1978 } },
    ARCANES = { nom = "Tir des arcanes", ids = { 14287, 14286, 14285, 14284, 14283, 14282, 14281, 3044 } },
    VISEE = { nom = "Visée", ids = { 20904, 20903, 20902, 20901, 20900, 19434 } },
    FUSILLADE = { nom = "Fusillade", ids = { 25294, 14290, 14289, 14288, 2643 } },
    ORDRE = { nom = "Ordre de tuer", ids = { 34026 } },
    COURROUX = { nom = "Courroux bestial", ids = { 19574 } },
    TIR_RAPIDE = { nom = "Tir rapide", ids = { 3045 } },
    FAUCON = { nom = "Aspect du faucon", ids = { 27044, 25296, 14322, 14321, 14320, 14319, 14318, 13165 } },
    RAPTOR = { nom = "Attaque du raptor", ids = { 14266, 14265, 14264, 14263, 14262, 14261, 14260, 2973 } },
    MANGOUSTE = { nom = "Morsure de la mangouste", ids = { 14271, 14270, 14269, 1495 } },
    FEINDRE = { nom = "Feindre la mort", ids = { 5384 } },
  },
  PALADIN = {
    SCEAU_AUTORITE = { nom = "Sceau d'autorité", ids = { 20920, 20919, 20918, 20915, 20375 } },
    SCEAU_PIETE = { nom = "Sceau de piété", ids = { 20293, 20292, 20291, 20290, 20289, 20288, 20287, 21084 } },
    JUGEMENT = { nom = "Jugement", ids = { 20271 } },
    CONSECRATION = { nom = "Consécration", ids = { 27173, 20924, 20923, 20922, 20116, 26573 } },
    EXORCISME = { nom = "Exorcisme", ids = { 27138, 10314, 10313, 10312, 5615, 5614, 879 } },
    MARTEAU_COLERE = { nom = "Marteau de la colère", ids = { 24275 } },
    FUREUR = { nom = "Fureur vertueuse", ids = { 25780 } },
    BOUCLIER_SACRE = { nom = "Bouclier sacré", ids = { 27179, 20928, 20927, 20925 } },
    BOUCLIER_VENGEUR = { nom = "Bouclier du vengeur", ids = { 32700, 31935 } },
    HORION_SACRE = { nom = "Horion sacré", ids = { 33072, 27175, 20930, 20929, 20473 } },
    IMPOSITION = { nom = "Imposition des mains", ids = { 27154, 10310, 2800, 633 } },
    BOUCLIER_DIVIN = { nom = "Bouclier divin", ids = { 1020, 642 } },
  },
}

-- ============================================================ rotations
-- Une liste de priorité par classe et par spécialisation (voir l'en-tête pour la forme).
-- Une classe ou une spécialisation absente d'ici : l'onglet dit « rotation pas encore écrite ».
local PRET = "pret"
local BUFF_MOI = { "buffAbsent" }
-- Noms localisés (frFR) des types de créature que renvoie UnitCreatureType.
local MORT_OU_DEMON = { "typeCible", { "Mort-vivant", "Démon" } }
-- Les urgences vont EN TÊTE d'une liste : le moteur prend la première entrée vraie.
local URGENCE_IMPOSITION = { sort = "IMPOSITION", si = { PRET, { "vie", "moi", 15 } }, texte = "Imposition des mains si tu es à moins de 15 % de vie" }
local URGENCE_BOUCLIER = { sort = "BOUCLIER_DIVIN", si = { PRET, { "vie", "moi", 15 } }, texte = "Bouclier divin si tu es à moins de 15 % de vie" }
D.ROTATIONS = {
  HUNTER = {
    bete = {
      { sort = "FAUCON", si = { BUFF_MOI }, texte = "Aspect du faucon, s'il n'est pas actif" },
      { sort = "MARQUE", si = { { "debuffAbsent" }, PRET }, texte = "Marque du chasseur sur la cible, si elle n'y est pas" },
      { sort = "COURROUX", si = { PRET }, texte = "Courroux bestial, dès qu'il est prêt" },
      { sort = "ORDRE", si = { PRET }, texte = "Ordre de tuer, dès qu'il est prêt" },
      { sort = "SERPENT", si = { { "debuffAbsent" }, PRET }, texte = "Morsure de serpent, si elle n'y est pas" },
      { sort = "ARCANES", si = { PRET }, texte = "Tir des arcanes, dès qu'il est prêt" },
      { sort = "AUTO", texte = "Tir automatique le reste du temps" },
    },
    precision = {
      { sort = "FAUCON", si = { BUFF_MOI }, texte = "Aspect du faucon, s'il n'est pas actif" },
      { sort = "MARQUE", si = { { "debuffAbsent" }, PRET }, texte = "Marque du chasseur sur la cible, si elle n'y est pas" },
      { sort = "TIR_RAPIDE", si = { PRET }, texte = "Tir rapide, dès qu'il est prêt (les combats qui comptent)" },
      { sort = "VISEE", si = { PRET }, texte = "Visée, dès qu'elle est prête" },
      { sort = "FUSILLADE", si = { PRET, "ennemisProches>=3" }, texte = "Fusillade quand 3 monstres ou plus sont sur toi" },
      { sort = "SERPENT", si = { { "debuffAbsent" }, PRET }, texte = "Morsure de serpent, si elle n'y est pas" },
      { sort = "ARCANES", si = { PRET }, texte = "Tir des arcanes, dès qu'il est prêt" },
      { sort = "AUTO", texte = "Tir automatique le reste du temps" },
    },
    survie = {
      { sort = "MARQUE", si = { { "debuffAbsent" }, PRET }, texte = "Marque du chasseur sur la cible, si elle n'y est pas" },
      { sort = "SERPENT", si = { { "debuffAbsent" }, PRET }, texte = "Morsure de serpent, si elle n'y est pas" },
      { sort = "MANGOUSTE", si = { PRET }, texte = "Morsure de la mangouste, dès qu'elle est prête" },
      { sort = "RAPTOR", si = { PRET }, texte = "Attaque du raptor, dès qu'elle est prête" },
      { sort = "ARCANES", si = { PRET }, texte = "Tir des arcanes, dès qu'il est prêt (à distance)" },
    },
  },
  PALADIN = {
    vindicte = {
      URGENCE_IMPOSITION,
      URGENCE_BOUCLIER,
      { sort = "SCEAU_AUTORITE", si = { BUFF_MOI }, texte = "Sceau d'autorité, s'il n'est pas actif" },
      { sort = "JUGEMENT", si = { PRET }, texte = "Jugement, dès qu'il est prêt" },
      { sort = "MARTEAU_COLERE", si = { PRET, "vie<20" }, texte = "Marteau de la colère quand la cible a moins de 20 % de vie" },
      { sort = "EXORCISME", si = { PRET, MORT_OU_DEMON }, texte = "Exorcisme sur un mort-vivant ou un démon" },
      { sort = "CONSECRATION", si = { PRET, "ennemisProches>=3" }, texte = "Consécration quand 3 monstres ou plus sont collés à toi" },
    },
    protection = {
      URGENCE_IMPOSITION,
      URGENCE_BOUCLIER,
      { sort = "FUREUR", si = { BUFF_MOI }, texte = "Fureur vertueuse active (sinon tu ne tiens pas les monstres)" },
      { sort = "SCEAU_PIETE", si = { BUFF_MOI }, texte = "Sceau de piété, s'il n'est pas actif" },
      { sort = "BOUCLIER_SACRE", si = { PRET }, texte = "Bouclier sacré, dès qu'il est prêt" },
      { sort = "JUGEMENT", si = { PRET }, texte = "Jugement, dès qu'il est prêt" },
      { sort = "BOUCLIER_VENGEUR", si = { PRET }, texte = "Bouclier du vengeur, dès qu'il est prêt" },
      { sort = "CONSECRATION", si = { PRET, "ennemisProches>=3" }, texte = "Consécration quand 3 monstres ou plus sont collés à toi" },
    },
    sacre = {
      URGENCE_IMPOSITION,
      URGENCE_BOUCLIER,
      { sort = "HORION_SACRE", si = { PRET }, texte = "Horion sacré, dès qu'il est prêt (sur l'allié blessé, ou sur un monstre pour le tuer)" },
      { sort = "JUGEMENT", si = { PRET }, texte = "Jugement, dès qu'il est prêt (il garde ton mana)" },
    },
  },
}

-- ============================================================ builds de talents
-- BUILDS[classe][spécialisation][situation] = liste ordonnée, dans l'ordre où prendre les points :
--   { nodeID = numéro du nœud (voir « /cs export »), rangs = rang à atteindre }
-- Situations : solo, groupe, donjon, raid (donjon et raid retombent sur groupe si absents).
-- Vides pour l'instant : sans les vrais numéros de nœuds de Forever, on n'invente rien.
-- Exemple :
--   BUILDS.HUNTER.bete.solo = { { nodeID = 12345, rangs = 2 }, { nodeID = 12346, rangs = 1 } }
D.BUILDS = {}

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
