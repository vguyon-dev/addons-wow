-- Simulation hors jeu de Quêtes disponibles : la logique pure (filtre, regroupement, couleurs, marques,
-- choix de l'orientation des positions), puis un chargement simulé avec de faux cadres et de petites
-- données : épingles de la carte, quêtes acceptées et rendues, filtres, cartes de continent, clics, API
-- qui manquent une à une.
-- Lancer depuis la racine du dépôt, sous Windows :
--   wsl lua5.1 tests/QuetesDispo_simu.lua QuetesDispo/QuetesDispo.lua
local ok = true
local nbOK = 0
local function verifie(libelle, attendu, obtenu)
  local bon = attendu == obtenu
  ok = ok and bon
  if bon then nbOK = nbOK + 1 end
  io.write(string.format("%s %-66s attendu %s, obtenu %s\n", bon and "OK " or "KO ", libelle, tostring(attendu), tostring(obtenu)))
end
local function proche(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 0.0005 end
local function verifieProche(libelle, attendu, obtenu)
  local bon = proche(attendu, obtenu)
  ok = ok and bon
  if bon then nbOK = nbOK + 1 end
  io.write(string.format("%s %-66s attendu %s, obtenu %s\n", bon and "OK " or "KO ", libelle, tostring(attendu), tostring(obtenu)))
end

local fichier = arg[1]
local reglagesLua = fichier:gsub("[^/]+$", "Reglages.lua")
local function lire(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end

verifie("Reglages.lua identique dans QuetesAuto", true,
  lire(reglagesLua) == lire((reglagesLua:gsub("QuetesDispo/Reglages", "QuetesAuto/Reglages"))))
local toc = lire((fichier:gsub("QuetesDispo%.lua$", "QuetesDispo.toc")))
verifie("toc : Reglages.lua, Donnees.lua puis QuetesDispo.lua", true, toc:find("Reglages%.lua%s+Donnees%.lua%s+QuetesDispo%.lua") ~= nil)
verifie("toc : sauvegarde déclarée", true, toc:find("## SavedVariables: QuetesDispoDB", 1, true) ~= nil)
verifie("toc : seulement Forever (les données viennent de Classic)", true, toc:find("## Interface: 16001\n", 1, true) ~= nil)
verifie("toc : fonction du compartiment d'addons", true, toc:find("## AddonCompartmentFunc: QuetesDispo_OuvrirReglages", 1, true) ~= nil)
verifie("toc : licence GPL-3.0", true, toc:find("## X-License: GPL-3.0", 1, true) ~= nil)
verifie("toc : catégorie des addons de Valentin", true, toc:find("## Category: Addons de Valentin", 1, true) ~= nil)
verifie("toc : titre affiché", true, toc:find("## Title: Quêtes disponibles", 1, true) ~= nil)
verifie("toc : icône d'un point d'exclamation de quête", true, toc:find("## IconTexture: Interface\\GossipFrame\\AvailableQuestIcon", 1, true) ~= nil)
verifie("toc : version 0.2.2", true, toc:find("## Version: 0.2.2", 1, true) ~= nil)

-- ============================================================================
-- 1. La logique pure : on charge le fichier sans aucune fonction du jeu.
-- ============================================================================
local ns = {}
assert(loadfile(fichier))("QuetesDispo", ns)

-- Les masques.
verifie("masque de race : Humain 1", 1, ns.masqueRace(1))
verifie("masque de race : Orc 2", 2, ns.masqueRace(2))
verifie("masque de race : Elfe de la nuit 8", 8, ns.masqueRace(4))
verifie("masque de race : Troll 128", 128, ns.masqueRace(8))
verifie("masque de race : race nouvelle (10) 512", 512, ns.masqueRace(10))
verifie("masque de race : absente 0", 0, ns.masqueRace(nil))
verifie("masque de race : zéro 0", 0, ns.masqueRace(0))
verifie("masque de classe : Paladin 2", 2, ns.masqueClasse(2))
verifie("masque de classe : Évocateur (13) 4096", 4096, ns.masqueClasse(13))
verifie("masques de faction : Alliance 77", 77, ns.MASQUES_FACTION.Alliance)
verifie("masques de faction : Horde 178", 178, ns.MASQUES_FACTION.Horde)

-- La couleur de difficulté.
local function couleur(n, j, v) local r, g, b = ns.couleurDifficulte(n, j, v) return r .. "," .. g .. "," .. b end
verifie("couleur : +5 rouge", "1,0.1,0.1", couleur(15, 10))
verifie("couleur : +3 orange", "1,0.5,0.25", couleur(13, 10))
verifie("couleur : +2 jaune", "1,1,0", couleur(12, 10))
verifie("couleur : même niveau jaune", "1,1,0", couleur(10, 10))
verifie("couleur : -2 jaune", "1,1,0", couleur(8, 10))
verifie("couleur : -3 vert", "0.25,0.75,0.25", couleur(7, 10, 8))
verifie("couleur : -8 vert (plage 8)", "0.25,0.75,0.25", couleur(2, 10, 8))
verifie("couleur : -9 gris (plage 8)", "0.5,0.5,0.5", couleur(1, 10, 8))
verifie("couleur : plage de 5, -6 gris", "0.5,0.5,0.5", couleur(4, 10, 5))
verifie("couleur : niveau inconnu blanc", "1,1,1", couleur(nil, 10))
verifie("couleur : niveau -1 (variable) blanc", "1,1,1", couleur(-1, 10))

-- Les marques.
local function marques(d, m) return table.concat(ns.marques(d, m), ",") end
verifie("marques : aucune", "", marques(0, 0))
verifie("marques : donjon", "Donjon", marques(4, 0))
verifie("marques : groupe", "Groupe", marques(2, 0))
verifie("marques : donjon et groupe, dans cet ordre", "Donjon,Groupe", marques(6, 0))
verifie("marques : raid, JcJ, répétable", "Raid,JcJ,Répétable", marques(8 + 16 + 1, 0))
verifie("marques : saisonnière", "Saisonnière", marques(32, 0))
verifie("marques : métier connu", "Métier : Cuisine", marques(0, 185))
verifie("marques : métier inconnu", "Métier : requis", marques(0, 99999))
verifie("marques : tout ensemble", "Donjon,Groupe,Raid,JcJ,Répétable,Saisonnière,Métier : Forge", marques(63, 164))
verifie("marques : drapeaux absents", "", marques(nil, nil))
verifie("marques : réputation requise", "Réputation requise", table.concat(ns.marques(0, 0, 529), ","))
verifie("marques : réputation 0, rien", "", table.concat(ns.marques(0, 0, 0), ","))
do
  -- La fiche lit les champs facultatifs 11 et 12 (et reste juste sans eux).
  ns.QUETES = {
    [900] = { 5, 1, 0, 0, 0, 0, 0, 0, 0, "A", { 7, -8 }, 529 }, [901] = { 5, 1, 0, 0, 0, 0, 0, 0, 0, "B", 0 },
    [902] = { 5, 1, 0, 0, 0, 0, 0, 0, 0, "C" },
  }
  local f0, f1, f2 = ns.fiche(900), ns.fiche(901), ns.fiche(902)
  verifie("fiche : autres lus", "7,-8", table.concat(f0.autres, ","))
  verifie("fiche : réputation lue", 529, f0.reputation)
  verifie("fiche : champ 11 à 0, liste vide", 0, #f1.autres)
  verifie("fiche : sans champs 11 et 12, liste vide et réputation 0", "0,0", #f2.autres .. "," .. f2.reputation)
  ns.QUETES = nil
end

-- Les titres.
verifie("titre affiché : avec le niveau", "[18] Les loups", ns.titreAffiche(18, "Les loups"))
verifie("titre affiché : sans niveau", "Les loups", ns.titreAffiche(nil, "Les loups"))
verifie("titre affiché : niveau -1", "Les loups", ns.titreAffiche(-1, "Les loups"))
verifie("titre : celui du jeu d'abord", "Les loups", ns.titreQuete(5, "Les loups", "Wolves"))
verifie("titre : sinon l'anglais des données", "Wolves", ns.titreQuete(5, nil, "Wolves"))
verifie("titre : le jeu rend un texte vide, l'anglais", "Wolves", ns.titreQuete(5, "", "Wolves"))
verifie("titre : rien du tout", "Quête 5", ns.titreQuete(5, nil, nil))

-- Les groupes exclusifs.
local quetesGroupes = {
  [1] = { 5, 1, 0, 0, 0, 3, 0, 0, 0, "A" }, [2] = { 5, 1, 0, 0, 0, 3, 0, 0, 0, "B" },
  [3] = { 5, 1, 0, 0, 0, 0, 0, 0, 0, "C" }, [4] = { 5, 1, 0, 0, 0, 5, 0, 0, 0, "D" },
  [6] = { 5, 1, 0, 0, 0, -9, 0, 0, 0, "E" },
}
local function texteGroupes(idx)
  local cles = {}
  for g in pairs(idx) do cles[#cles + 1] = g end
  table.sort(cles)
  local t = {}
  for _, g in ipairs(cles) do t[#t + 1] = g .. ":" .. table.concat(idx[g], ",") end
  return table.concat(t, "|")
end
verifie("exclusifs : groupes positifs seulement, triés", "3:1,2|5:4", texteGroupes(ns.exclusifs(quetesGroupes)))
verifie("exclusifs : construit une seule fois", true, ns.exclusifs(quetesGroupes) == ns.exclusifs(quetesGroupes))
verifie("exclusifs : table vide", "", texteGroupes(ns.exclusifs({})))
verifie("exclusifs : table absente", "", texteGroupes(ns.exclusifs(nil)))

-- Le filtre : un test par règle.
local rendues, cours = {}, {}
local function nouveauJoueur(extra)
  rendues, cours = {}, {}
  local j = {
    niveau = 10, masqueRace = 1, faction = "Alliance", masqueClasse = 2, plageVerte = 8,
    rendues = function(n) return rendues[n] == true end, enCours = function(n) return cours[n] == true end,
    metiers = {}, ignorees = {}, groupes = { [7] = { 100, 101, 102 } },
  }
  for k, v in pairs(extra or {}) do j[k] = v end
  return j
end
local function quete(extra)
  local q = { numero = 100, niveau = 10, niveauMin = 1, races = 0, classes = 0, avant = 0, groupe = 0,
    drapeaux = 0, metier = 0, niveauMetier = 0, titre = "Test" }
  for k, v in pairs(extra or {}) do q[k] = v end
  return q
end
local REGLAGES = { donjons = true, metiers = true }
local function reglages(extra)
  local r = {}
  for k, v in pairs(REGLAGES) do r[k] = v end
  for k, v in pairs(extra or {}) do r[k] = v end
  return r
end
local function d(q, j, r)
  local dispo, raison = ns.disponible(quete(q), j or nouveauJoueur(), reglages(r))
  return tostring(dispo) .. "," .. tostring(raison)
end

verifie("filtre : une quête ordinaire est à prendre", "true,nil", d())
verifie("filtre : ignorée à la main", "false,ignoree", d({}, nouveauJoueur({ ignorees = { [100] = true } })))
do
  local j = nouveauJoueur(); rendues[100] = true
  verifie("filtre : déjà rendue", "false,rendue", d({}, j))
  verifie("filtre : rendue et répétable, option cochée : reste", "true,nil", d({ drapeaux = 1 }, j, { repetables = true }))
  verifie("filtre : rendue et répétable, option décochée : répétable", "false,repetable", d({ drapeaux = 1 }, j))
  verifie("filtre : ignorée passe avant rendue", "false,ignoree",
    d({}, nouveauJoueur({ ignorees = { [100] = true }, rendues = function() return true end })))
end
do
  local j = nouveauJoueur(); cours[100] = true
  verifie("filtre : déjà dans le journal", "false,enCours", d({}, j))
end
verifie("filtre : classe d'un autre (guerrier)", "false,classe", d({ classes = 1 }))
verifie("filtre : classe dont la mienne fait partie", "true,nil", d({ classes = 3 }))
verifie("filtre : ma classe seule", "true,nil", d({ classes = 2 }))
verifie("filtre : classe inconnue du joueur, pas de jugement", "true,nil", d({ classes = 1 }, nouveauJoueur({ masqueClasse = false })))
verifie("filtre : race de Classic, masque de l'autre faction", "false,race", d({ races = 178 }))
verifie("filtre : race de Classic, masque de ma faction", "true,nil", d({ races = 77 }))
verifie("filtre : race de Classic, ma race seule", "true,nil", d({ races = 1 }))
verifie("filtre : race de Classic, une autre race de ma faction", "false,race", d({ races = 4 }))
verifie("filtre : toutes les races (0)", "true,nil", d({ races = 0 }))
verifie("filtre : race nouvelle, Horde, masque Horde", "true,nil", d({ races = 178 }, nouveauJoueur({ masqueRace = 512, faction = "Horde" })))
verifie("filtre : race nouvelle, Horde, masque Alliance", "false,race", d({ races = 77 }, nouveauJoueur({ masqueRace = 512, faction = "Horde" })))
verifie("filtre : race nouvelle, Alliance, masque Alliance", "true,nil", d({ races = 77 }, nouveauJoueur({ masqueRace = 1024, faction = "Alliance" })))
verifie("filtre : race nouvelle, Alliance, masque Horde", "false,race", d({ races = 178 }, nouveauJoueur({ masqueRace = 1024, faction = "Alliance" })))
verifie("filtre : race nouvelle, masque de toutes les races classiques", "true,nil", d({ races = 255 }, nouveauJoueur({ masqueRace = 512, faction = "Horde" })))
verifie("filtre : race nouvelle citée dans le masque", "true,nil", d({ races = 512 }, nouveauJoueur({ masqueRace = 512, faction = "Horde" })))
verifie("filtre : race nouvelle neutre, pas de jugement", "true,nil", d({ races = 77 }, nouveauJoueur({ masqueRace = 2 ^ 23, faction = "Neutral" })))
verifie("filtre : niveau du joueur trop bas", "false,niveau", d({ niveauMin = 11 }))
verifie("filtre : niveau juste atteint", "true,nil", d({ niveauMin = 10 }))
verifie("filtre : bientôt (1 niveau), option cochée", "true,bientot", d({ niveauMin = 11 }, nil, { bientot = true }))
verifie("filtre : bientôt (3 niveaux), option cochée", "true,bientot", d({ niveauMin = 13 }, nil, { bientot = true }))
verifie("filtre : 4 niveaux, trop loin même avec l'option", "false,niveau", d({ niveauMin = 14 }, nil, { bientot = true }))
do
  local j = nouveauJoueur()
  verifie("filtre : à rendre avant (50), pas rendue", "false,prerequis", d({ avant = 50 }, j))
  rendues[50] = true
  verifie("filtre : à rendre avant (50), rendue", "true,nil", d({ avant = 50 }, j))
  rendues[50] = nil
  verifie("filtre : à avoir en cours (-60), ni l'un ni l'autre", "false,prerequisEnCours", d({ avant = -60 }, j))
  cours[60] = true
  verifie("filtre : à avoir en cours (-60), en cours", "true,nil", d({ avant = -60 }, j))
  cours[60] = nil; rendues[60] = true
  verifie("filtre : à avoir en cours (-60), seulement rendue : refusée (comme CMaNGOS)", "false,prerequisEnCours", d({ avant = -60 }, j))
  rendues[60] = nil
  -- Plusieurs prérequis (PrevQuestId puis les NextQuestId) : une seule suffit.
  verifie("filtre : deux prérequis (50 ou 51), aucun rendu", "false,prerequis", d({ avant = 50, autres = { 51 } }, j))
  rendues[51] = true
  verifie("filtre : deux prérequis (50 ou 51), le second rendu", "true,nil", d({ avant = 50, autres = { 51 } }, j))
  rendues[51] = nil
  verifie("filtre : prérequis seulement dans autres (avant = 0), aucun rendu : refusée (cas 247)", "false,prerequis", d({ avant = 0, autres = { 2, 23 } }, j))
  rendues[23] = true
  verifie("filtre : prérequis seulement dans autres, 23 rendue", "true,nil", d({ avant = 0, autres = { 2, 23 } }, j))
  rendues[23] = nil
  verifie("filtre : autres négatif (-70), ni en cours ni rendue", "false,prerequisEnCours", d({ avant = 0, autres = { -70 } }, j))
  cours[70] = true
  verifie("filtre : autres négatif (-70), en cours", "true,nil", d({ avant = 0, autres = { -70 } }, j))
  cours[70] = nil
  verifie("filtre : autres vide ou 0, aucun prérequis", "true,nil", d({ avant = 0, autres = {} }, j))
  verifie("filtre : autres absent, aucun prérequis", "true,nil", d({ avant = 0, autres = nil }, j))
  rendues[101] = true
  verifie("filtre : groupe exclusif, une autre déjà rendue", "false,groupe", d({ groupe = 7 }, j))
  rendues[101] = nil; cours[102] = true
  verifie("filtre : groupe exclusif, une autre en cours", "false,groupe", d({ groupe = 7 }, j))
  cours[102] = nil
  verifie("filtre : groupe exclusif, aucune autre prise", "true,nil", d({ groupe = 7 }, j))
  verifie("filtre : groupe 0, jamais exclusif", "true,nil", d({ groupe = 0 }, j))
end
do
  -- Sans index fourni, le filtre construit celui de ns.QUETES.
  local anciennes = ns.QUETES
  ns.QUETES = { [100] = { 10, 1, 0, 0, 0, 9, 0, 0, 0, "A" }, [101] = { 10, 1, 0, 0, 0, 9, 0, 0, 0, "B" } }
  local j = nouveauJoueur({ groupes = false })
  j.groupes = nil
  rendues[101] = true
  verifie("filtre : groupe exclusif, index de ns.QUETES", "false,groupe", d({ groupe = 9 }, j))
  ns.QUETES = anciennes
end
verifie("filtre : métier absent (liste vide)", "false,metier", d({ metier = 185, niveauMetier = 50 }, nouveauJoueur({ metiers = {} })))
verifie("filtre : métier trop faible", "false,metier", d({ metier = 185, niveauMetier = 50 }, nouveauJoueur({ metiers = { [185] = 30 } })))
verifie("filtre : métier au niveau", "true,nil", d({ metier = 185, niveauMetier = 50 }, nouveauJoueur({ metiers = { [185] = 50 } })))
verifie("filtre : métiers inconnus (nil), pas de jugement", "true,nil", d({ metier = 185, niveauMetier = 50 }, nouveauJoueur({ metiers = false })))
verifie("filtre : option métiers décochée", "true,nil", d({ metier = 185, niveauMetier = 50 }, nouveauJoueur({ metiers = {} }), { metiers = false }))
verifie("filtre : métier avec un niveau lu à 0 : pas de jugement", "true,nil", d({ metier = 185, niveauMetier = 50 }, nouveauJoueur({ metiers = { [185] = 0 } })))
verifie("filtre : quête grise (9 niveaux sous moi)", "false,grise", d({ niveau = 1 }))
verifie("filtre : quête grise, option bas niveau", "true,nil", d({ niveau = 1 }, nil, { basNiveau = true }))
verifie("filtre : 8 niveaux sous moi, pas grise", "true,nil", d({ niveau = 2 }))
verifie("filtre : plage verte du jeu plus large", "true,nil", d({ niveau = 1 }, nouveauJoueur({ plageVerte = 12 })))
verifie("filtre : plage verte absente, repli sur 8", "false,grise", d({ niveau = 1 }, nouveauJoueur({ plageVerte = false })))
verifie("filtre : niveau de quête variable (-1), jamais grise", "true,nil", d({ niveau = -1 }))
verifie("filtre : répétable, option décochée", "false,repetable", d({ drapeaux = 1 }))
verifie("filtre : répétable, option cochée", "true,nil", d({ drapeaux = 1 }, nil, { repetables = true }))
verifie("filtre : donjon, option cochée", "true,nil", d({ drapeaux = 4 }))
verifie("filtre : donjon, option décochée", "false,donjon", d({ drapeaux = 4 }, nil, { donjons = false }))
verifie("filtre : raid, option décochée", "false,donjon", d({ drapeaux = 8 }, nil, { donjons = false }))
verifie("filtre : groupe ou élite seul : pas filtré", "true,nil", d({ drapeaux = 2 }, nil, { donjons = false }))
verifie("filtre : JcJ, option décochée", "false,jcj", d({ drapeaux = 16 }))
verifie("filtre : JcJ, option cochée", "true,nil", d({ drapeaux = 16 }, nil, { jcj = true }))
verifie("filtre : saisonnière, option décochée", "false,saison", d({ drapeaux = 32 }))
verifie("filtre : saisonnière, option cochée", "true,nil", d({ drapeaux = 32 }, nil, { saisonnieres = true }))
verifie("filtre : plusieurs drapeaux (donjon + JcJ), JcJ coupé", "false,jcj", d({ drapeaux = 20 }))
verifie("ordre : classe avant niveau", "false,classe", d({ classes = 1, niveauMin = 20 }))
verifie("ordre : niveau avant « à rendre avant »", "false,niveau", d({ niveauMin = 20, avant = 50 }))
verifie("ordre : grise avant donjon", "false,grise", d({ niveau = 1, drapeaux = 4 }, nil, { donjons = false }))
verifie("ordre : race avant niveau", "false,race", d({ races = 178, niveauMin = 20 }))
verifie("joueur absent : aucune erreur", "true,nil", (function()
  local a, b = ns.disponible(quete(), nil, nil)
  return tostring(a) .. "," .. tostring(b)
end)())

-- Les lignes de la bulle.
do
  local anciennes = ns.QUETES
  ns.QUETES = {
    [1] = { 12, 5, 0, 0, 0, 0, 4, 0, 0, "Beta" }, [2] = { 5, 1, 0, 0, 0, 0, 0, 185, 1, "alpha" },
    [3] = { 5, 1, 0, 0, 0, 0, 0, 0, 0, "Alpha" }, [4] = { 14, 13, 0, 0, 0, 0, 0, 0, 0, "Presque" },
  }
  local j = nouveauJoueur({ metiers = false })
  local l = ns.lignesQuetes({ 1, 2, 3, 4, 99 }, j, { bientot = true, donjons = true }, function(n) return n == 3 and "Alpha FR" or nil end)
  local t = {}
  for _, x in ipairs(l) do t[#t + 1] = x.texte .. "|" .. x.marques end
  verifie("bulle : triées par niveau puis titre, inconnue ignorée", "[5] alpha|Métier : Cuisine ; [5] Alpha FR| ; [12] Beta|Donjon ; [14] Presque|",
    table.concat(t, " ; "))
  verifie("bulle : donnée 4 niveaux du joueur +1 : bientôt", true, l[4].bientot)
  verifie("bulle : une quête normale n'est pas « bientôt »", false, l[1].bientot)
  verifie("bulle : bientôt en gris clair", "0.75,0.75,0.75", l[4].r .. "," .. l[4].v .. "," .. l[4].b)
  verifie("bulle : couleur de difficulté (niveau 12 pour 10 : jaune)", "1,1,0", l[3].r .. "," .. l[3].v .. "," .. l[3].b)
  verifie("bulle : sans lecteur de titre, l'anglais", "[5] Alpha", ns.lignesQuetes({ 3 }, j, {})[1].texte)
  ns.QUETES = anciennes
end

-- Le regroupement.
local function texteGroupes2(g)
  local t = {}
  for _, e in ipairs(g) do t[#t + 1] = string.format("%.3f,%.3f:%s", e.x, e.y, table.concat(e.quetes, "+")) end
  return table.concat(t, " ")
end
verifie("regrouper : même endroit, un seul", "0.500,0.500:1+2", texteGroupes2(ns.regrouper({
  { x = 0.5, y = 0.5, quetes = { 1 } }, { x = 0.5, y = 0.5, quetes = { 2 } } })))
verifie("regrouper : à 0,4 % près, un seul (position moyenne)", "0.502,0.502:1+2", texteGroupes2(ns.regrouper({
  { x = 0.5, y = 0.5, quetes = { 1 } }, { x = 0.504, y = 0.504, quetes = { 2 } } })))
verifie("regrouper : à 0,6 % de distance, deux", "0.500,0.500:1 0.506,0.500:2", texteGroupes2(ns.regrouper({
  { x = 0.5, y = 0.5, quetes = { 1 } }, { x = 0.506, y = 0.5, quetes = { 2 } } })))
verifie("regrouper : proche en x seulement, deux", "0.500,0.500:1 0.500,0.520:2", texteGroupes2(ns.regrouper({
  { x = 0.5, y = 0.5, quetes = { 1 } }, { x = 0.5, y = 0.52, quetes = { 2 } } })))
verifie("regrouper : numéros sans doublon", "0.500,0.500:1+2+3", texteGroupes2(ns.regrouper({
  { x = 0.5, y = 0.5, quetes = { 1, 2 } }, { x = 0.5, y = 0.5, quetes = { 2, 3 } } })))
verifie("regrouper : de l'autre côté d'une limite de cellule", "0.501,0.501:1+2", texteGroupes2(ns.regrouper({
  { x = 0.4999, y = 0.4999, quetes = { 1 } }, { x = 0.5026, y = 0.5026, quetes = { 2 } } })))
verifie("regrouper : l'ordre d'apparition est gardé", "0.100,0.100:5 0.900,0.900:6", texteGroupes2(ns.regrouper({
  { x = 0.1, y = 0.1, quetes = { 5 } }, { x = 0.9, y = 0.9, quetes = { 6 } } })))
verifie("regrouper : tolérance plus large (carte de continent)", "0.505,0.500:1+2", texteGroupes2(ns.regrouper({
  { x = 0.5, y = 0.5, quetes = { 1 } }, { x = 0.51, y = 0.5, quetes = { 2 } } }, 0.015)))
verifie("regrouper : liste vide", "", texteGroupes2(ns.regrouper({})))
verifie("regrouper : liste absente", "", texteGroupes2(ns.regrouper(nil)))

-- Le choix de l'orientation : pour chacune des huit façons de tourner les positions.
local INVERSES = {
  function(a, b) return a, b end, function(a, b) return b, a end, function(a, b) return -a, -b end,
  function(a, b) return -b, -a end, function(a, b) return a, -b end, function(a, b) return -a, b end,
  function(a, b) return -b, a end, function(a, b) return b, -a end,
}
for k = 1, 8 do
  local function convertir(continent, a, b, carte)
    local x, y = INVERSES[k](a, b)
    for _, anc in ipairs(ns.ANCRES) do
      for _, c in ipairs(anc[1]) do
        if c == carte and anc[2] == continent then
          return (x - (anc[3] - 300)) / 600, (y - (anc[4] - 300)) / 600
        end
      end
    end
  end
  local i, score = ns.choisirOrientation(convertir)
  verifie("orientation " .. k .. " : reconnue", k .. ",6", i .. "," .. score)
end
do
  local i, score = ns.choisirOrientation(function() return nil end)
  verifie("orientation : jeu muet, première transformation, score 0", "1,0", i .. "," .. score)
  i, score = ns.choisirOrientation(function() return 5, 5 end)
  verifie("orientation : positions hors carte, score 0", "1,0", i .. "," .. score)
end
verifie("ancres : six villes", 6, #ns.ANCRES)
do
  -- Chaque ville a plusieurs numéros de carte à essayer : ceux de Forever (Classic) et ceux de Retail.
  local tous = true
  for _, anc in ipairs(ns.ANCRES) do if type(anc[1]) ~= "table" or #anc[1] < 2 then tous = false end end
  verifie("ancres : chaque ville a des numéros de carte à essayer (Forever puis Retail)", true, tous)
  verifie("ancres : Hurlevent = 1453 (Forever) puis 84 (Retail)", "1453,84", table.concat(ns.ANCRES[1][1], ","))
  -- Un jeu qui ne connaît que les numéros de Retail, ou que ceux de Forever : les six villes sont reconnues.
  for _, cas in ipairs({ { "Forever seul", 1 }, { "Retail seul", 2 } }) do
    local function convertir(continent, a, b, carte)
      for _, anc in ipairs(ns.ANCRES) do
        if anc[2] == continent and anc[1][cas[2]] == carte then
          return (a - (anc[3] - 300)) / 600, (b - (anc[4] - 300)) / 600
        end
      end
    end
    local i, score = ns.choisirOrientation(convertir)
    verifie("ancres : " .. cas[1] .. ", les six villes reconnues", "1,6", i .. "," .. score)
  end
end

-- ============================================================================
-- 2. Chargement simulé avec de faux cadres.
-- ============================================================================
local imprime = {}
local function lireImprime() return table.concat(imprime, "\n") end
print = function(...)
  local t = {}
  for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end
  imprime[#imprime + 1] = table.concat(t, " ")
end

local toutes, file, tickers
local M = {}
local metaF = {}
function metaF.__index(t, k)
  if type(k) ~= "string" or not k:match("^%u") then return nil end
  if (k == "SetBackdrop" or k == "SetBackdropColor" or k == "SetBackdropBorderColor") and not rawget(t, "_fond") then return nil end
  return M[k] or function() end
end

local function nouveau(genre, nom, parent, modele)
  local f = setmetatable({ _type = genre, _nom = nom, _parent = parent, _shown = true, _events = {}, _scripts = {},
    _w = 100, _h = 20, _scale = 1, _text = "", _attr = {}, _niveau = 1, _crochets = {}, _hooks = {} }, metaF)
  toutes[#toutes + 1] = f
  if nom then _G[nom] = f end
  if modele and tostring(modele):find("Backdrop") then f._fond = true end
  return f
end

function M.SetSize(s, w, h) s._w, s._h = w, h end
function M.SetWidth(s, w) s._w = w end
function M.SetHeight(s, h) s._h = h end
function M.GetWidth(s) return s._w end
function M.GetHeight(s) return s._h end
function M.GetStringWidth(s) return #s._text * 6 end
function M.GetStringHeight(s) return 12 end
function M.SetText(s, t) s._text = tostring(t == nil and "" or t) end
function M.GetText(s) return s._text end
function M.SetPoint(s, point, rel, relPoint, x, y)
  if type(rel) == "number" then x, y, rel, relPoint = rel, relPoint, nil, nil end
  s._pt = { point, rel, relPoint or point, x or 0, y or 0 }
end
function M.ClearAllPoints(s) s._pt = nil end
function M.GetPoint(s) local p = s._pt or { "CENTER", UIParent, "CENTER", 0, 0 } return p[1], p[2], p[3], p[4], p[5] end
function M.GetEffectiveScale(s) return s._scale end
function M.SetScale(s, v) s._scale = v end
function M.SetAlpha(s, v) s._alpha = v end
function M.GetAlpha(s) return s._alpha or 1 end
function M.Show(s) s._shown = true; for _, h in ipairs(s._crochets.Show or {}) do h(s) end end
function M.Hide(s) s._shown = false; for _, h in ipairs(s._crochets.Hide or {}) do h(s) end end
function M.SetShown(s, v) if v then M.Show(s) else M.Hide(s) end end
function M.IsShown(s) return s._shown end
function M.IsVisible(s) return s._shown end
function M.RegisterEvent(s, e) s._events[e] = true end
M.RegisterUnitEvent = M.RegisterEvent
function M.UnregisterEvent(s, e) s._events[e] = nil end
function M.SetScript(s, nom, fn) s._scripts[nom] = fn end
function M.GetScript(s, nom) return s._scripts[nom] end
function M.HookScript(s, nom, fn) s._hooks[nom] = s._hooks[nom] or {}; table.insert(s._hooks[nom], fn) end
function M.CreateFontString(s) return nouveau("FontString", nil, s) end
function M.CreateTexture(s) return nouveau("Texture", nil, s) end
function M.SetTexture(s, t) s._tex = t end
function M.SetDesaturated(s, v) s._desat = v end
function M.SetAttribute(s, k, v) s._attr[k] = v end
function M.GetAttribute(s, k) return s._attr[k] end
function M.GetParent(s) return s._parent end
function M.GetName(s) return s._nom end
function M.SetFrameLevel(s, n) s._niveau = n end
function M.GetFrameLevel(s) return s._niveau end
function M.GetVerticalScroll(s) return s._defil or 0 end
function M.SetVerticalScroll(s, v) s._defil = v end
function M.GetVerticalScrollRange() return 0 end
function M.StartMoving(s) s._deplace = true end
function M.StopMovingOrSizing(s) s._deplace = false end
function M.IsObjectType() return false end
function M.GetLeft(s) return s._gauche or 1500 end
function M.GetRight(s) return s._droite or 1800 end
function M.GetTop(s) return s._haut or 800 end
function M.GetBottom(s) return 300 end
function M.GetCenter() return 500, 400 end
function M.EnableMouse(s, v) s._souris = v end

-- Une bulle qui note ce qu'on y écrit.
local function nouvelleBulle()
  local b = { lignes = {}, _shown = false }
  function b:SetOwner(o) self.proprietaire = o; self.lignes = {} end
  function b:AddLine(texte, r, g, bl) self.lignes[#self.lignes + 1] = { gauche = texte, droite = nil, r = r, v = g, b = bl } end
  function b:AddDoubleLine(g1, d1, r, g, bl) self.lignes[#self.lignes + 1] = { gauche = g1, droite = d1, r = r, v = g, b = bl } end
  function b:Show() self._shown = true end
  function b:Hide() self._shown = false end
  function b:IsShown() return self._shown end
  return b
end

-- Le monde simulé : des cartes avec leur rectangle dans les coordonnées de la base (x, y).
local CARTES = {
  [13] = { nom = "Royaumes de l'Est", type = 2, cont = 0, x0 = -12000, x1 = 4000, y0 = -4000, y1 = 4000 },
  [12] = { nom = "Kalimdor", type = 2, cont = 1, x0 = -9000, x1 = 11000, y0 = -8000, y1 = 4000 },
  [947] = { nom = "Azeroth", type = 1, cont = 0, x0 = -12000, x1 = 4000, y0 = -4000, y1 = 4000 },
  [37] = { nom = "Forêt d'Elwynn", type = 3, cont = 0, x0 = -10000, x1 = -8000, y0 = -2000, y1 = 1000 },
  [1] = { nom = "Durotar", type = 3, cont = 1, x0 = 1000, x1 = 2000, y0 = -5000, y1 = -3500 },
}
for _, anc in ipairs(ns.ANCRES) do
  for _, id in ipairs(anc[1]) do
    CARTES[id] = { nom = "Ville " .. id, type = 3, cont = anc[2], x0 = anc[3] - 300, x1 = anc[3] + 300, y0 = anc[4] - 300, y1 = anc[4] + 300 }
  end
end

-- Les huit façons de poser (x, y) dans le jeu, et leurs inverses (voir ns.TRANSFORMATIONS).
local DIRECTES = {
  function(x, y) return x, y end, function(x, y) return y, x end, function(x, y) return -x, -y end,
  function(x, y) return -y, -x end, function(x, y) return x, -y end, function(x, y) return -x, y end,
  function(x, y) return y, -x end, function(x, y) return -y, x end,
}

-- Les données de test : (niveau, niveauMin, races, classes, avant, groupe, drapeaux, métier, niveauMétier, titre)
local DONNEES_QUETES = {
  [1] = { 5, 1, 0, 0, 0, 0, 0, 0, 0, "Wolves" },
  [2] = { 6, 1, 0, 0, 0, 0, 0, 0, 0, "Letter" },
  [3] = { 10, 8, 0, 0, 0, 0, 0, 0, 0, "Too early" },
  [4] = { 5, 1, 0, 0, 0, 0, 4, 0, 0, "Dungeon quest" },
  [5] = { 5, 1, 178, 0, 0, 0, 0, 0, 0, "Horde only" },
  [6] = { 5, 1, 0, 2, 0, 0, 0, 0, 0, "Paladin only" },
  [7] = { 5, 1, 0, 1, 0, 0, 0, 0, 0, "Warrior only" },
  [8] = { 5, 1, 0, 0, 1, 0, 0, 0, 0, "After wolves" },
  [9] = { 5, 1, 0, 0, 0, 5, 0, 0, 0, "Group A" },
  [10] = { 5, 1, 0, 0, 0, 5, 0, 0, 0, "Group B" },
  [11] = { 5, 1, 0, 0, 0, 0, 0, 185, 1, "Cooking" },
  [12] = { 1, 1, 0, 0, 0, 0, 0, 0, 0, "Easy one" },
  [13] = { 5, 1, 0, 0, 0, 0, 1, 0, 0, "Daily" },
  [14] = { 5, 1, 0, 0, 0, 0, 16, 0, 0, "PvP" },
  [15] = { 5, 1, 0, 0, 0, 0, 32, 0, 0, "Season" },
  [16] = { 5, 1, 0, 0, 0, 0, 0, 0, 0, "Durotar quest" },
  [17] = { 7, 1, 0, 0, 0, 0, 0, 0, 0, "Ironforge area" },
  [18] = { 7, 1, 0, 0, 0, 0, 0, 0, 0, "Merged one" },
}
local DONNEES_DEPARTS = {
  { 0, -9000, -100, 1, { 1, 2 } },
  { 0, -9100, 200, 1, { 3, 12 } },
  { 0, -9300, -500, 1, { 4, 5, 6, 7 } },
  { 0, -9304, -503, 1, { 6, 18 } },   -- à moins de 0,5 % du précédent : même « ! »
  { 0, -8700, 0, 1, { 8, 9, 10 } },
  { 0, -8900, 300, 2, { 11, 13, 14, 15 } },
  { 1, 1500, -4300, 1, { 16 } },      -- Kalimdor : Durotar
  { 0, -5000, -900, 1, { 17 } },      -- Royaumes de l'Est, hors de la forêt d'Elwynn
}

local JEU

local function installer(avecAPI)
  toutes, file, tickers = {}, {}, {}
  imprime = {}
  JEU = { carte = 37, niveau = 5, ori = 1, vecPlat = false, rendues = {}, cours = {}, titresJeu = {}, gps = {},
          requetesTitre = {}, waypoint = nil, profs = {} }
  _G.ValentinAddons, _G.ValentinAddonsReglages, _G.ValentinAddonsMinimap = nil, nil, nil
  _G.QuetesDispoDB, _G.QuetesDispoReglages, _G.QuetesDispoMinimap = nil, nil, nil
  _G.UIParent = nouveau("Frame", "UIParent")
  UIParent._h, UIParent._w = 1080, 1920
  _G.GameTooltip = nouvelleBulle()
  _G.Minimap = nouveau("Frame", "Minimap")
  _G.WorldMapFrame = nil
  _G.CreateFrame = function(genre, nom, parent, modele) return nouveau(genre, nom, parent or UIParent, modele) end
  _G.UISpecialFrames, _G.SlashCmdList = {}, {}
  _G.SLASH_QUETESDISPO1, _G.SLASH_QUETESDISPO2 = nil, nil
  _G.tinsert = table.insert
  _G.strtrim = function(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
  _G.hooksecurefunc = function(t, nom, fn)
    t._crochets[nom] = t._crochets[nom] or {}
    table.insert(t._crochets[nom], fn)
  end
  _G.C_Timer = {
    After = function(_, fn) file[#file + 1] = fn end,
    NewTicker = function(_, fn) tickers[#tickers + 1] = fn return {} end,
  }
  _G.InCombatLockdown = function() return false end
  _G.IsShiftKeyDown = function() return false end
  _G.GetCursorPosition = function() return 600, 500 end
  _G.UnitName = function() return "Testeur" end
  _G.GetRealmName = function() return "Royaume" end
  _G.UNKNOWNOBJECT = "Inconnu"
  _G.BackdropTemplateMixin = {}
  _G.PlaySound, _G.HideUIPanel, _G.ClearCursor = function() end, function() end, function() end
  _G.GetCursorInfo = function() end
  _G.date = os.date
  _G.GPS_Ajouter = nil
  for _, n in ipairs({ "C_Map", "C_QuestLog", "C_SuperTrack", "UiMapPoint", "CreateVector2D", "UnitLevel", "UnitRace",
    "UnitClass", "UnitFactionGroup", "GetProfessions", "GetProfessionInfo", "GetQuestGreenRange" }) do _G[n] = nil end
  if not avecAPI then return end

  local function vec2(x, y)
    if JEU.vecPlat then return { x = x, y = y } end
    return { x = x, y = y, GetXY = function(s) return s.x, s.y end }
  end
  _G.CreateVector2D = vec2
  _G.C_Map = {
    GetBestMapForUnit = function() return 37 end,
    GetMapInfo = function(id) local m = CARTES[id] if m then return { mapID = id, name = m.nom, mapType = m.type } end end,
    GetMapPosFromWorldPos = function(cont, v, override)
      local x, y = INVERSES[JEU.ori](v.x, v.y)
      local id = override or (cont == 0 and 13 or 12)
      local m = CARTES[id]
      if JEU.absentes and JEU.absentes[id] then return end -- un numéro de carte que ce jeu ne connaît pas
      if not m or m.cont ~= cont then return end
      return id, vec2((x - m.x0) / (m.x1 - m.x0), (y - m.y0) / (m.y1 - m.y0))
    end,
    GetWorldPosFromMapPos = function(carte, v)
      local m = CARTES[carte]
      if not m then return end
      local a, b = DIRECTES[JEU.ori](m.x0 + v.x * (m.x1 - m.x0), m.y0 + v.y * (m.y1 - m.y0))
      return m.cont, vec2(a, b)
    end,
    CanSetUserWaypointOnMap = function() return true end,
    SetUserWaypoint = function(p) JEU.waypoint = p end,
    HasUserWaypoint = function() return JEU.waypoint ~= nil end,
  }
  _G.UiMapPoint = { CreateFromCoordinates = function(c, x, y) return { uiMapID = c, x = x, y = y } end }
  _G.C_SuperTrack = { SetSuperTrackedUserWaypoint = function() JEU.suivi = true end }
  _G.C_QuestLog = {
    IsQuestFlaggedCompleted = function(n) return JEU.rendues[n] == true end,
    IsOnQuest = function(n) return JEU.cours[n] == true end,
    GetTitleForQuestID = function(n) return JEU.titresJeu[n] end,
    RequestLoadQuestByID = function(n) JEU.requetesTitre[n] = (JEU.requetesTitre[n] or 0) + 1 end,
  }
  _G.UnitLevel = function() return JEU.niveau end
  _G.UnitRace = function() return "Humain", "Human", 1 end
  _G.UnitClass = function() return "Paladin", "PALADIN", 2 end
  _G.UnitFactionGroup = function() return "Alliance" end
  _G.GetQuestGreenRange = function() return 8 end
  _G.GetProfessions = function() return unpack(JEU.profs.indexes or {}) end
  _G.GetProfessionInfo = function(i) local p = JEU.profs.infos[i] return p.nom, "icone", p.niveau, 300, 0, 0, p.ligne end

  -- La carte du monde, chargée avant l'addon.
  local toile = nouveau("Frame", "WorldMapCanvas", UIParent)
  toile._w, toile._h = 1000, 667
  _G.WorldMapFrame = nouveau("Frame", "WorldMapFrame", UIParent)
  WorldMapFrame._shown = false
  WorldMapFrame.ScrollContainer = { Child = toile }
  WorldMapFrame.GetMapID = function() return JEU.carte end
  WorldMapFrame.OnMapChanged = function() end
  JEU.toile = toile
end

local function declencher(evenement, ...)
  for _, f in ipairs(toutes) do
    if f._events[evenement] and f._scripts.OnEvent then f._scripts.OnEvent(f, evenement, ...) end
  end
end
local function avancer()
  local garde = 0
  while #file > 0 and garde < 2000 do garde = garde + 1; table.remove(file, 1)() end
end
local function tictac() for _, f in ipairs(tickers) do f() end end

local function chargerAddon(donnees)
  local n = {}
  assert(loadfile(reglagesLua))("QuetesDispo", n)
  if donnees ~= false then
    n.VERSION_DONNEES = "test.sql"
    n.QUETES = DONNEES_QUETES
    n.DEPARTS = DONNEES_DEPARTS
  end
  assert(loadfile(fichier))("QuetesDispo", n)
  return n
end

local function demarrer(donnees)
  local n = chargerAddon(donnees)
  declencher("ADDON_LOADED", "QuetesDispo")
  declencher("PLAYER_ENTERING_WORLD")
  avancer()
  return n
end

local function ouvrirCarte(id)
  if not WorldMapFrame then return end
  JEU.carte = id
  WorldMapFrame._shown = true
  for _, h in ipairs(WorldMapFrame._hooks.OnShow or {}) do h(WorldMapFrame) end
end
local function changerCarte(id)
  JEU.carte = id
  for _, h in ipairs(WorldMapFrame._crochets.OnMapChanged or {}) do h(WorldMapFrame) end
end

-- Les épingles visibles de la carte.
local function epinglesVisibles()
  local l = {}
  for _, f in ipairs(toutes) do
    if f._type == "Button" and rawget(f, "donnees") and f._shown then l[#l + 1] = f end
  end
  return l
end
local function contenu(p)
  local t = {}
  for _, q in ipairs(p.donnees.quetes) do t[#t + 1] = q end
  table.sort(t)
  return table.concat(t, ",")
end
local function resume()
  local t = {}
  for _, p in ipairs(epinglesVisibles()) do t[#t + 1] = contenu(p) end
  table.sort(t)
  return table.concat(t, " | ")
end
local function pinAvec(numero)
  for _, p in ipairs(epinglesVisibles()) do
    for _, q in ipairs(p.donnees.quetes) do if q == numero then return p end end
  end
end
local function nombrePins()
  local n = 0
  for _, f in ipairs(toutes) do if f._type == "Button" and rawget(f, "donnees") then n = n + 1 end end
  return n
end
local function boutonTexte(texte)
  for _, f in ipairs(toutes) do
    if f._type == "Button" and f._text == texte then return f end
  end
end
local function survoler(p)
  p._scripts.OnEnter(p)
  local t = {}
  for _, l in ipairs(GameTooltip.lignes) do t[#t + 1] = tostring(l.gauche) .. (l.droite and l.droite ~= "" and ("|" .. l.droite) or "") end
  return table.concat(t, " ; ")
end

-- ---------------------------------------------------------------------------
-- 2a. Avec toutes les API : le déroulé complet.
-- ---------------------------------------------------------------------------
installer(true)
local n = demarrer()
verifie("chargement : aucune erreur retenue", nil, n.derniereErreur)
verifie("chargement : global de la commande", "function", type(QuetesDispo_OuvrirReglages))
verifie("chargement : /qd et /quetesdispo", "/qd,/quetesdispo", SLASH_QUETESDISPO1 .. "," .. SLASH_QUETESDISPO2)
verifie("réglages : actif par défaut", true, QuetesDispoDB.actif)
verifie("réglages : donjons cochés par défaut", true, QuetesDispoDB.donjons)
verifie("réglages : bas niveau décoché par défaut", false, QuetesDispoDB.basNiveau)
verifie("réglages : répétables décochés par défaut", false, QuetesDispoDB.repetables)
verifie("réglages : JcJ décoché par défaut", false, QuetesDispoDB.jcj)
verifie("réglages : saisonnières décochées par défaut", false, QuetesDispoDB.saisonnieres)
verifie("réglages : bientôt décoché par défaut", false, QuetesDispoDB.bientot)
verifie("réglages : métiers cochés par défaut", true, QuetesDispoDB.metiers)
verifie("réglages : taille 20 par défaut", 20, QuetesDispoDB.taille)
verifie("réglages : continent décoché par défaut", false, QuetesDispoDB.continent)
verifie("réglages : quêtes cachées, une table", "table", type(QuetesDispoDB.ignorees))
verifie("carte fermée : aucune épingle créée", 0, nombrePins())

-- La sonde au démarrage : l'état de la zone du joueur, sans ouvrir la carte.
local etat = n.etat()
verifie("sonde : l'état existe sans carte ouverte", true, etat ~= nil)
verifie("sonde : la carte du joueur", 37, etat and etat.carte)
verifie("sonde : 8 quêtes à prendre", 8, etat and etat.montrees)
verifie("sonde : 4 « ! »", 4, etat and etat.epingles)
verifie("sonde : exclue, niveau", 1, etat and etat.exclues.niveau)
verifie("sonde : exclue, race", 1, etat and etat.exclues.race)
verifie("sonde : exclue, classe", 1, etat and etat.exclues.classe)
verifie("sonde : exclue, à rendre avant", 1, etat and etat.exclues.prerequis)
verifie("sonde : exclue, métier", 1, etat and etat.exclues.metier)
verifie("sonde : exclue, répétable", 1, etat and etat.exclues.repetable)
verifie("sonde : exclue, JcJ", 1, etat and etat.exclues.jcj)
verifie("sonde : exclue, saisonnière", 1, etat and etat.exclues.saison)
verifie("sonde : toujours aucune épingle", 0, nombrePins())

-- Ouverture de la carte d'une zone.
ouvrirCarte(37)
avancer()
verifie("carte de zone : les bonnes épingles", "1,2 | 12 | 4,6,18 | 9,10", resume())
verifie("carte de zone : 4 épingles", 4, #epinglesVisibles())
local p1, p2, p3, p4 = pinAvec(1), pinAvec(12), pinAvec(18), pinAvec(9)
verifie("épingle : plusieurs quêtes, le nombre", "2", p1.nombre._text)
verifie("épingle : trois quêtes (deux points regroupés, doublon retiré)", "3", p3.nombre._text)
verifie("épingle : une quête, pas de nombre", "", p2.nombre._text)
verifie("épingle : enfant de la toile", true, p1._parent == JEU.toile)
verifie("épingle : accrochée au coin haut gauche de la toile", "CENTER,TOPLEFT", p1._pt[1] .. "," .. p1._pt[3])
verifieProche("épingle : position x (0,5 de 1000)", 500, p1._pt[4])
verifieProche("épingle : position y (0,6333 de 667, vers le bas)", -(1900 / 3000) * 667, p1._pt[5])
verifie("épingle : taille par défaut", "20,20", p1._w .. "," .. p1._h)
verifie("épingle : niveau de cadre au-dessus de la toile", JEU.toile._niveau + 2000, p1._niveau)
verifie("épingle : le « ! » de quête", "Interface\\GossipFrame\\AvailableQuestIcon", p1.image._tex)
verifie("épingle : pas grisée", false, p1.image._desat)
verifie("épingle : alpha plein", 1, p1._alpha)
verifie("aucun cadre à nous n'écrit sur la carte du jeu (rien de plus que ses accroches)", nil, rawget(WorldMapFrame, "donnees"))
verifie("aucune épingle n'est enfant d'un autre cadre que la toile", true, (function()
  for _, f in ipairs(toutes) do if rawget(f, "donnees") and f._parent ~= JEU.toile then return false end end
  return true
end)())

-- La bulle.
local bulle = survoler(p3)
verifie("bulle : en-tête avec le nombre", true, bulle:find("^Quêtes disponibles %(3%)") ~= nil)
verifie("bulle : « [niveau] Titre » avec la marque Donjon", true, bulle:find("[5] Dungeon quest|Donjon", 1, true) ~= nil)
verifie("bulle : une quête sans marque", true, bulle:find("[5] Paladin only ;", 1, true) ~= nil)
verifie("bulle : l'autre quête regroupée", true, bulle:find("[7] Merged one", 1, true) ~= nil)
verifie("bulle : rappel des clics", true, bulle:find("Clic gauche : balise", 1, true) ~= nil)
verifie("bulle : couleur de difficulté (jaune)", "1,1,0", GameTooltip.lignes[2].r .. "," .. GameTooltip.lignes[2].v .. "," .. GameTooltip.lignes[2].b)
verifie("bulle : le titre du jeu est demandé", 1, JEU.requetesTitre[4])
verifie("bulle : une quête seule, au singulier", true, survoler(p2):find("^Quête disponible ;") ~= nil)
survoler(p3)
verifie("bulle : le titre n'est demandé qu'une fois", 1, JEU.requetesTitre[4])
JEU.titresJeu[4] = "Quête de donjon"
declencher("QUEST_DATA_LOAD_RESULT", 4, true)
local lignesApres = {}
for _, l in ipairs(GameTooltip.lignes) do lignesApres[#lignesApres + 1] = tostring(l.gauche) end
verifie("bulle : le titre du jeu arrive et la bulle se met à jour", true, table.concat(lignesApres, ";"):find("[5] Quête de donjon", 1, true) ~= nil)
p3._scripts.OnLeave(p3)
verifie("bulle : cachée en quittant l'épingle", false, GameTooltip._shown)

-- Clics.
GPS_Ajouter = function(c, x, y, t) JEU.gps[#JEU.gps + 1] = { c, x, y, t } return true end
p1._scripts.OnClick(p1, "LeftButton")
verifie("clic gauche : GPS_Ajouter appelé", 1, #JEU.gps)
verifie("clic gauche : la bonne carte", 37, JEU.gps[1] and JEU.gps[1][1])
verifieProche("clic gauche : la bonne position x", 0.5, JEU.gps[1] and JEU.gps[1][2])
verifieProche("clic gauche : la bonne position y", 0.6333, JEU.gps[1] and JEU.gps[1][3])
verifie("clic gauche : plusieurs quêtes, titre général", "Quêtes disponibles", JEU.gps[1] and JEU.gps[1][4])
p2._scripts.OnClick(p2, "LeftButton")
verifie("clic gauche : une quête, son titre (anglais, le jeu n'en donne pas)", "Easy one", JEU.gps[2] and JEU.gps[2][4])
verifieProche("clic gauche : position d'une autre épingle x", 0.45, JEU.gps[2] and JEU.gps[2][2])
GPS_Ajouter = function() return nil end -- GPS coupé : il refuse
p2._scripts.OnClick(p2, "LeftButton")
verifie("clic gauche, GPS coupé : la balise du jeu", 37, JEU.waypoint and JEU.waypoint.uiMapID)
verifieProche("clic gauche, GPS coupé : sa position", 0.45, JEU.waypoint and JEU.waypoint.x)
verifie("clic gauche, GPS coupé : balise suivie", true, JEU.suivi)
GPS_Ajouter = nil
JEU.waypoint = nil
p2._scripts.OnClick(p2, "LeftButton")
verifie("clic gauche, sans GPS : la balise du jeu", 37, JEU.waypoint and JEU.waypoint.uiMapID)
verifie("clic gauche : le chat le dit", true, lireImprime():find("balise posée : Easy one", 1, true) ~= nil)
JEU.waypoint = nil
C_Map.SetUserWaypoint = nil
imprime = {}
p2._scripts.OnClick(p2, "LeftButton")
verifie("clic gauche, sans balise possible : le dit, sans erreur", true, lireImprime():find("pas de balise possible", 1, true) ~= nil)
C_Map.SetUserWaypoint = function(p) JEU.waypoint = p end

-- Une quête acceptée : son « ! » disparaît.
JEU.cours[12] = true
declencher("QUEST_ACCEPTED", 1, 12)
avancer()
verifie("quête acceptée : son « ! » disparaît", "1,2 | 4,6,18 | 9,10", resume())
verifie("quête acceptée : 3 épingles", 3, #epinglesVisibles())
-- Une quête rendue : celle qui demandait de la rendre avant apparaît.
JEU.rendues[1] = true
declencher("QUEST_TURNED_IN", 1, 0, 0, 37)
avancer()
verifie("quête rendue : disparaît, et celle d'après apparaît", "2 | 4,6,18 | 8,9,10", resume())
-- Un groupe exclusif : prendre l'une ferme l'autre.
JEU.cours[9] = true
declencher("QUEST_ACCEPTED", 1, 9)
avancer()
verifie("groupe exclusif : la quête prise et la sœur disparaissent", "2 | 4,6,18 | 8", resume())
-- Un abandon la remet.
JEU.cours[9] = nil
declencher("QUEST_REMOVED", 9)
avancer()
verifie("quête abandonnée : le groupe se rouvre", "2 | 4,6,18 | 8,9,10", resume())
JEU.cours[9] = true
declencher("QUEST_ACCEPTED", 1, 9)
avancer()

-- Les filtres, sans rechargement.
n.reglages.changer("jcj", true)
verifie("filtre JcJ coché : appliqué tout de suite, sans /reload", "14 | 2 | 4,6,18 | 8", resume())
n.reglages.changer("donjons", false)
verifie("filtre donjons décoché : la quête de donjon disparaît", "14 | 2 | 6,18 | 8", resume())
n.reglages.changer("bientot", true)
verifie("filtre bientôt coché : la quête qui demande le niveau 8 apparaît", "14 | 2 | 3 | 6,18 | 8", resume())
local pBientot = pinAvec(3)
verifie("bientôt : épingle grisée", true, pBientot.image._desat)
verifie("bientôt : épingle estompée", 0.6, pBientot._alpha)
verifie("bientôt : la bulle la met en gris clair", "0.75,0.75,0.75", (function()
  survoler(pBientot)
  local l = GameTooltip.lignes[2]
  return l.r .. "," .. l.v .. "," .. l.b
end)())
n.reglages.changer("jcj", false)
n.reglages.changer("donjons", true)
verifie("filtres remis : retour à l'état d'avant", "2 | 3 | 4,6,18 | 8", resume())
n.reglages.changer("metiers", false)
verifie("métiers décoché : la quête de cuisine apparaît seule à son endroit", "11 | 2 | 3 | 4,6,18 | 8", resume())
n.reglages.changer("repetables", true)
n.reglages.changer("saisonnieres", true)
verifie("répétables et saisonnières cochées, métiers décoché : l'endroit apparaît", "11,13,15 | 2 | 3 | 4,6,18 | 8", resume())
n.reglages.changer("metiers", true)
n.reglages.changer("repetables", false)
n.reglages.changer("saisonnieres", false)
verifie("réglages remis : retour à l'état d'avant", "2 | 3 | 4,6,18 | 8", resume())
n.reglages.changer("taille", 28)
verifie("taille : les épingles grandissent sans rechargement", "28,28", pinAvec(2)._w .. "," .. pinAvec(2)._h)
n.reglages.changer("taille", 100)
verifie("taille : plafonnée à 32", "32,32", pinAvec(2)._w .. "," .. pinAvec(2)._h)
n.reglages.changer("taille", 3)
verifie("taille : plancher à 12", "12,12", pinAvec(2)._w .. "," .. pinAvec(2)._h)
n.reglages.changer("taille", 20)
n.reglages.changer("actif", false)
verifie("addon coupé : plus aucune épingle", 0, #epinglesVisibles())
n.reglages.changer("actif", true)
verifie("addon réactivé : les épingles reviennent", "2 | 3 | 4,6,18 | 8", resume())
n.reglages.changer("bientot", false)

-- Le niveau change.
JEU.niveau = 15
declencher("PLAYER_LEVEL_UP", 15)
avancer()
verifie("niveau 15 : la quête de niveau 8 est normale, les trop faciles partent", "18 | 3", resume())
verifie("niveau 15 : l'épingle n'est plus grisée", false, pinAvec(3).image._desat)
n.reglages.changer("basNiveau", true)
verifie("bas niveau coché : les quêtes grises reviennent", "2 | 3 | 4,6,18 | 8", resume())
n.reglages.changer("basNiveau", false)

-- Clic droit : ne plus montrer ces quêtes.
local pDix = pinAvec(18)
verifie("clic droit : on vise l'épingle de la quête 18", "18", contenu(pDix))
pDix._scripts.OnClick(pDix, "RightButton")
verifie("clic droit : la quête est cachée, gardée par personnage", true, QuetesDispoDB.ignorees["Testeur-Royaume"][18])
verifie("clic droit : plus d'épingle pour elle", "3", resume())
verifie("clic droit : le chat le dit", true, lireImprime():find("1 quête cachée à cet endroit", 1, true) ~= nil)
verifie("clic droit : une autre personne n'est pas touchée", nil, QuetesDispoDB.ignorees["Autre-Royaume"])
boutonTexte("Remontrer les quêtes cachées")._scripts.OnClick()
verifie("bouton des réglages : la quête cachée revient", "18 | 3", resume())
verifie("bouton des réglages : la liste est vidée", nil, next(QuetesDispoDB.ignorees["Testeur-Royaume"]))
imprime = {}
boutonTexte("Remontrer les quêtes cachées")._scripts.OnClick()
verifie("bouton des réglages : rien à remontrer, le dit", true, lireImprime():find("aucune quête cachée", 1, true) ~= nil)
JEU.niveau = 5
declencher("PLAYER_LEVEL_UP", 5)
avancer()

-- Les cartes de continent et du monde.
changerCarte(13)
avancer()
verifie("carte de continent, option décochée : rien", 0, #epinglesVisibles())
verifie("carte de continent : l'état dit « carte non concernée »", "carte non concernée", n.etat().note)
changerCarte(947)
avancer()
verifie("carte du monde : rien", 0, #epinglesVisibles())
n.reglages.changer("continent", true)
avancer()
verifie("carte du monde, même avec l'option : toujours rien", 0, #epinglesVisibles())
changerCarte(13)
avancer()
verifie("carte de continent, option cochée : des épingles", true, #epinglesVisibles() > 0)
verifie("carte de continent : la quête d'une autre zone y est", true, pinAvec(17) ~= nil)
verifie("carte de continent : pas les quêtes de Kalimdor", nil, pinAvec(16))
verifie("carte de continent : la tolérance de regroupement est plus large (moins d'épingles que de points)", true, #epinglesVisibles() <= 5)
n.reglages.changer("continent", false)
verifie("carte de continent, option décochée de nouveau : les épingles partent", 0, #epinglesVisibles())

-- Changement de zone : les anciennes épingles partent tout de suite, les nouvelles arrivent.
changerCarte(37)
avancer()
verifie("retour en zone : les épingles reviennent (cache des positions)", "2 | 4,6,18 | 8", resume())
changerCarte(1)
verifie("changement de zone : les anciennes partent avant la passe", 0, #epinglesVisibles())
avancer()
verifie("Durotar : la quête de Kalimdor", "16", resume())
local pDur = pinAvec(16)
verifieProche("Durotar : position x", 0.5, (pDur._pt[4]) / 1000)
verifieProche("Durotar : position y", -0.4667, (pDur._pt[5]) / 667)
changerCarte(37)
avancer()

-- /qd etat et le diagnostic.
imprime = {}
SlashCmdList.QUETESDISPO("etat")
local sortie = lireImprime()
verifie("/qd etat : version des données", true, sortie:find("données : test.sql, 18 quêtes connues, 8 points de départ", 1, true) ~= nil)
verifie("/qd etat : la transformation des positions", true, sortie:find("positions : transformation n° 1 (villes reconnues : 6 sur 6)", 1, true) ~= nil)
verifie("/qd etat : la carte ouverte", true, sortie:find("carte 37 (Forêt d'Elwynn)", 1, true) ~= nil)
verifie("/qd etat : le compte par raison", true, sortie:find("exclues, niveau trop bas : 1", 1, true) ~= nil)
verifie("/qd etat : une raison par ligne", true, sortie:find("exclues, JcJ : 1", 1, true) ~= nil)
imprime = {}
SlashCmdList.QUETESDISPO("aide")
verifie("/qd aide : liste les commandes", true, lireImprime():find("/qd etat", 1, true) ~= nil)
imprime = {}
SlashCmdList.QUETESDISPO("nimportequoi")
verifie("commande inconnue : le dit", true, lireImprime():find("commande inconnue", 1, true) ~= nil)
SlashCmdList.QUETESDISPO("")
verifie("/qd : ouvre les réglages sans erreur", nil, n.derniereErreur)
SlashCmdList.QUETESDISPO("off")
verifie("/qd off : coupe", false, QuetesDispoDB.actif)
verifie("/qd off : plus d'épingle", 0, #epinglesVisibles())
SlashCmdList.QUETESDISPO("on")
verifie("/qd on : réactive", true, QuetesDispoDB.actif)
SlashCmdList.QUETESDISPO("jcj")
verifie("/qd jcj : bascule l'option", true, QuetesDispoDB.jcj)
SlashCmdList.QUETESDISPO("jcj")
declencher("PLAYER_LOGOUT")
local diag = QuetesDispoDB.diagnostic
verifie("diagnostic à la déconnexion : écrit", "table", type(diag))
verifie("diagnostic : date", "string", type(diag and diag.date))
verifie("diagnostic : la carte", 37, diag and diag.carte)
verifie("diagnostic : le nombre de quêtes montrées", 5, diag and diag.montrees)
verifie("diagnostic : les raisons d'exclusion", 1, diag and diag.exclues.niveau)
verifie("diagnostic : les titres montrés (au plus 15)", true, diag and #diag.titres > 0 and #diag.titres <= 15)
verifie("diagnostic : un titre avec son numéro", true, diag and diag.titres[1] and diag.titres[1]:find("(n° ", 1, true) ~= nil)
verifie("diagnostic : la version des données", "test.sql", diag and diag.donnees)
verifie("diagnostic : l'orientation retenue", 1, diag and diag.orientation)
verifie("fin du déroulé : aucune erreur retenue", nil, n.derniereErreur)

-- 15 titres au plus dans le diagnostic.
do
  local grosses, grossesDeparts = {}, { { 0, -9000, -100, 1, {} } }
  for i = 1, 40 do
    grosses[1000 + i] = { 5, 1, 0, 0, 0, 0, 0, 0, 0, "Quest " .. i }
    grossesDeparts[1][5][i] = 1000 + i
  end
  installer(true)
  local nn = chargerAddon(); nn.QUETES, nn.DEPARTS = grosses, grossesDeparts
  declencher("ADDON_LOADED", "QuetesDispo"); declencher("PLAYER_ENTERING_WORLD"); avancer()
  declencher("PLAYER_LOGOUT")
  verifie("diagnostic : 40 quêtes à prendre, 15 titres gardés", 15, #QuetesDispoDB.diagnostic.titres)
  verifie("diagnostic : le compte complet reste exact", 40, QuetesDispoDB.diagnostic.montrees)
  ouvrirCarte(37); avancer()
  verifie("40 quêtes au même endroit : un seul « ! »", 1, #epinglesVisibles())
  verifie("40 quêtes au même endroit : le nombre", "40", epinglesVisibles()[1].nombre._text)
  verifie("40 quêtes : la bulle se limite à 15 lignes plus un reste", true, (function()
    local b = survoler(epinglesVisibles()[1])
    return b:find("… et 25 autres", 1, true) ~= nil
  end)())
end

-- ---------------------------------------------------------------------------
-- 2b. Toutes les orientations de positions, avec ou sans GetXY.
-- ---------------------------------------------------------------------------
for ori = 1, 8 do
  for _, plat in ipairs({ false, true }) do
    installer(true)
    JEU.ori, JEU.vecPlat = ori, plat
    local nb = demarrer()
    ouvrirCarte(37)
    avancer()
    verifie("orientation " .. ori .. (plat and " (positions sans GetXY)" or "") .. " : les mêmes épingles", "1,2 | 12 | 4,6,18 | 9,10", resume())
    verifie("orientation " .. ori .. (plat and " (sans GetXY)" or "") .. " : transformation retenue", ori, nb.etat() and (function()
      imprime = {}
      SlashCmdList.QUETESDISPO("etat")
      return tonumber(lireImprime():match("transformation n° (%d+)"))
    end)())
  end
end

-- ---------------------------------------------------------------------------
-- 2c. Les calculs étalés : 300 points par image.
-- ---------------------------------------------------------------------------
do
  installer(true)
  local nn = chargerAddon()
  local departs = {}
  for i = 1, 1000 do departs[i] = { 0, -9000 + (i % 50), -100 + (i % 7), 1, { 1 } } end
  nn.DEPARTS = departs
  declencher("ADDON_LOADED", "QuetesDispo")
  ouvrirCarte(37)
  -- On avance image par image : une seule fonction en attente à la fois ici (hors sonde).
  local images = 0
  while #file > 0 and images < 100 do
    images = images + 1
    local f = table.remove(file, 1)
    f()
  end
  verifie("calcul étalé : 1000 points, des épingles à la fin", true, #epinglesVisibles() > 0)
  verifie("calcul étalé : fini sans erreur", nil, nn.derniereErreur)
end
do
  -- Mesure : le premier appel n'en fait que 300.
  installer(true)
  local nn = chargerAddon()
  local departs = {}
  for i = 1, 1000 do departs[i] = { 0, -9000, -100, 1, { 1 } } end
  nn.DEPARTS = departs
  local appels = 0
  local original = C_Map.GetMapPosFromWorldPos
  declencher("ADDON_LOADED", "QuetesDispo")
  ouvrirCarte(37)
  -- Une passe : on exécute les fonctions en attente jusqu'à la première étape de calcul, en comptant les appels.
  C_Map.GetMapPosFromWorldPos = function(...) appels = appels + 1 return original(...) end
  -- La file contient : la demande de rafraîchissement (0,2 s) venue de l'ouverture de la carte, puis rien d'autre.
  local f1 = table.remove(file, 1)
  f1() -- passe : démarre le calcul (calibrage de l'orientation + première étape en attente)
  local avantEtapes = appels
  local f2 = table.remove(file, 1)
  f2() -- première étape
  verifie("calcul étalé : une étape convertit au plus 300 points", true, appels - avantEtapes <= 300 and appels - avantEtapes > 0)
  verifie("calcul étalé : la suite est en attente", true, #file > 0)
end

-- ---------------------------------------------------------------------------
-- 2d. Sans données, avec des données vides, sans carte, hooks absents, carte chargée plus tard.
-- ---------------------------------------------------------------------------
installer(true)
local nd = demarrer(false)
verifie("sans données : le dit une fois", true, lireImprime():find("données absentes", 1, true) ~= nil)
ouvrirCarte(37); avancer(); tictac()
verifie("sans données : aucune épingle, aucune erreur", "0,nil", #epinglesVisibles() .. "," .. tostring(nd.derniereErreur))
imprime = {}
SlashCmdList.QUETESDISPO("etat")
verifie("sans données : /qd etat le dit", true, lireImprime():find("données absentes", 1, true) ~= nil)
declencher("PLAYER_LOGOUT")
verifie("sans données : le diagnostic s'écrit quand même", "table", type(QuetesDispoDB.diagnostic))

installer(true)
local nv = chargerAddon(); nv.QUETES, nv.DEPARTS = {}, {}
declencher("ADDON_LOADED", "QuetesDispo"); declencher("PLAYER_ENTERING_WORLD"); avancer()
ouvrirCarte(37); avancer()
verifie("données vides : le dit, aucune épingle", true, lireImprime():find("données absentes", 1, true) ~= nil and #epinglesVisibles() == 0)

installer(true)
local nv2 = chargerAddon(); nv2.QUETES, nv2.DEPARTS = DONNEES_QUETES, {}
declencher("ADDON_LOADED", "QuetesDispo")
verifie("points de départ vides : le dit", true, lireImprime():find("données absentes", 1, true) ~= nil)

-- Carte chargée après l'addon (extension de Blizzard à la demande).
installer(true)
local carteTemporaire = WorldMapFrame
_G.WorldMapFrame = nil
local nt = demarrer()
verifie("carte absente au chargement : aucune erreur", nil, nt.derniereErreur)
_G.WorldMapFrame = carteTemporaire
declencher("ADDON_LOADED", "Blizzard_WorldMap")
ouvrirCarte(37); avancer()
verifie("carte chargée plus tard : l'addon s'y accroche à ADDON_LOADED", "1,2 | 12 | 4,6,18 | 9,10", resume())
verifie("carte chargée plus tard : accroche de changement de zone", true, #(WorldMapFrame._crochets.OnMapChanged or {}) == 1)
verifie("carte chargée plus tard : accroche d'ouverture", true, #(WorldMapFrame._hooks.OnShow or {}) == 1)
verifie("carte chargée plus tard : accroche de taille", true, #(JEU.toile._hooks.OnSizeChanged or {}) == 1)
declencher("ADDON_LOADED", "Blizzard_WorldMap")
verifie("une seule accroche, même si l'événement revient", true, #(WorldMapFrame._crochets.OnMapChanged or {}) == 1)
-- Changement de taille de la carte : les positions suivent.
JEU.toile._w, JEU.toile._h = 2000, 1334
for _, h in ipairs(JEU.toile._hooks.OnSizeChanged) do h(JEU.toile) end
avancer()
verifieProche("carte agrandie : l'épingle suit la nouvelle taille", 1000, pinAvec(1)._pt[4])
JEU.toile._w, JEU.toile._h = 0, 0
for _, h in ipairs(JEU.toile._hooks.OnSizeChanged) do h(JEU.toile) end
avancer()
verifie("carte pas encore dimensionnée : aucune erreur", nil, nt.derniereErreur)
JEU.toile._w, JEU.toile._h = 1000, 667

-- Sans l'accroche de changement de zone : le minuteur surveille.
installer(true)
hooksecurefunc = nil
local nh = demarrer()
ouvrirCarte(37); avancer()
verifie("sans hooksecurefunc : l'ouverture suffit", "1,2 | 12 | 4,6,18 | 9,10", resume())
JEU.carte = 1
tictac(); avancer()
verifie("sans hooksecurefunc : le minuteur voit le changement de zone", "16", resume())
JEU.carte = 37
tictac(); avancer()
verifie("sans hooksecurefunc : retour à la forêt", "1,2 | 12 | 4,6,18 | 9,10", resume())
WorldMapFrame._shown = false
tictac()
JEU.carte = 1
WorldMapFrame._shown = true
tictac(); avancer()
verifie("sans hooksecurefunc : réouverture sur une autre zone", "16", resume())
verifie("sans hooksecurefunc : aucune erreur", nil, nh.derniereErreur)

-- Carte fermée : rien n'est créé ni déplacé par une demande.
installer(true)
local nf = demarrer()
declencher("QUEST_ACCEPTED", 1, 1)
declencher("PLAYER_LEVEL_UP", 6)
declencher("SKILL_LINES_CHANGED")
avancer()
verifie("carte fermée : les événements ne créent aucune épingle", 0, nombrePins())
verifie("carte fermée : aucune erreur", nil, nf.derniereErreur)

-- Les métiers du joueur.
installer(true)
JEU.profs = { indexes = { 1 }, infos = { [1] = { nom = "Cuisine", niveau = 40, ligne = 185 } } }
local nm = demarrer()
ouvrirCarte(37); avancer()
verifie("métier : ayant la cuisine, la quête de cuisine est à prendre", "1,2 | 11 | 12 | 4,6,18 | 9,10", resume())
installer(true)
JEU.profs = { indexes = { 1 }, infos = { [1] = { nom = "Cuisine", niveau = 0, ligne = 185 } } }
local nm2 = demarrer()
ouvrirCarte(37); avancer()
verifie("métier : niveau lu à 0, la quête reste montrée", true, pinAvec(11) ~= nil)

-- ---------------------------------------------------------------------------
-- 2e. Des API qui manquent une à une : rien ne plante.
-- ---------------------------------------------------------------------------
local manques = {
  { "C_Map (entier)", function() C_Map = nil end },
  { "C_Map.GetMapPosFromWorldPos", function() C_Map.GetMapPosFromWorldPos = nil end },
  { "C_Map.GetWorldPosFromMapPos", function() C_Map.GetWorldPosFromMapPos = nil end },
  { "C_Map.GetMapInfo", function() C_Map.GetMapInfo = nil end },
  { "C_Map.GetBestMapForUnit", function() C_Map.GetBestMapForUnit = nil end },
  { "C_Map.SetUserWaypoint", function() C_Map.SetUserWaypoint = nil end },
  { "C_Map.CanSetUserWaypointOnMap", function() C_Map.CanSetUserWaypointOnMap = nil end },
  { "C_Map.HasUserWaypoint", function() C_Map.HasUserWaypoint = nil end },
  { "UiMapPoint", function() UiMapPoint = nil end },
  { "C_SuperTrack", function() C_SuperTrack = nil end },
  { "CreateVector2D", function() CreateVector2D = nil end },
  { "C_QuestLog (entier)", function() C_QuestLog = nil end },
  { "C_QuestLog.IsQuestFlaggedCompleted", function() C_QuestLog.IsQuestFlaggedCompleted = nil end },
  { "C_QuestLog.IsOnQuest", function() C_QuestLog.IsOnQuest = nil end },
  { "C_QuestLog.GetTitleForQuestID", function() C_QuestLog.GetTitleForQuestID = nil end },
  { "C_QuestLog.RequestLoadQuestByID", function() C_QuestLog.RequestLoadQuestByID = nil end },
  { "UnitLevel", function() UnitLevel = nil end },
  { "UnitRace", function() UnitRace = nil end },
  { "UnitClass", function() UnitClass = nil end },
  { "UnitFactionGroup", function() UnitFactionGroup = nil end },
  { "UnitName", function() UnitName = nil end },
  { "GetRealmName", function() GetRealmName = nil end },
  { "GetProfessions", function() GetProfessions = nil end },
  { "GetQuestGreenRange", function() GetQuestGreenRange = nil end },
  { "hooksecurefunc", function() hooksecurefunc = nil end },
  { "C_Timer.NewTicker", function() C_Timer.NewTicker = nil end },
  { "C_Timer (entier, tout se fait sans attendre)", function() C_Timer = nil end },
  { "WorldMapFrame (entier)", function() WorldMapFrame = nil end },
  { "WorldMapFrame.ScrollContainer", function() WorldMapFrame.ScrollContainer = false end },
  { "WorldMapFrame.GetMapID", function() WorldMapFrame.GetMapID = false end },
  { "date", function() date = nil end },
  { "un jeu qui répond n'importe quoi", function()
      C_Map.GetMapInfo = function() return "pas une table" end
      C_Map.GetMapPosFromWorldPos = function() return "x", "y" end
      C_Map.GetWorldPosFromMapPos = function() return "x", "y" end
      C_QuestLog.IsQuestFlaggedCompleted = function() error("boum") end
    end },
  { "des positions qui sont des textes", function()
      C_Map.GetMapPosFromWorldPos = function() return 37, { x = "a", y = "b" } end
    end },
}
for _, m in ipairs(manques) do
  installer(true)
  m[2]()
  local nm3
  local okM, err = pcall(function()
    nm3 = demarrer()
    ouvrirCarte(37)
    avancer(); tictac(); avancer()
    for _, p in ipairs(epinglesVisibles()) do
      p._scripts.OnEnter(p); p._scripts.OnLeave(p); p._scripts.OnClick(p, "LeftButton")
    end
    if WorldMapFrame and WorldMapFrame.GetMapID then changerCarte(1); avancer(); changerCarte(13); avancer(); changerCarte(37); avancer() end
    declencher("QUEST_ACCEPTED", 1, 1); declencher("QUEST_TURNED_IN", 1); declencher("QUEST_REMOVED", 1)
    declencher("PLAYER_LEVEL_UP", 6); declencher("SKILL_LINES_CHANGED"); declencher("QUEST_DATA_LOAD_RESULT", 4, true)
    avancer()
    nm3.reglages.changer("jcj", true); nm3.reglages.changer("continent", true); avancer()
    SlashCmdList.QUETESDISPO("etat")
    for _, p in ipairs(epinglesVisibles()) do p._scripts.OnClick(p, "RightButton") end
    boutonTexte("Remontrer les quêtes cachées")._scripts.OnClick()
    declencher("PLAYER_LOGOUT")
  end)
  verifie("API manquante : " .. m[1] .. " : aucune erreur", true, okM and nm3 and nm3.derniereErreur == nil)
  if not okM then io.write("   " .. tostring(err) .. "\n") end
  if nm3 and nm3.derniereErreur then io.write("   " .. nm3.derniereErreur .. "\n") end
end

-- Quelques sorties précises quand une API manque.
installer(true)
C_QuestLog.IsQuestFlaggedCompleted = nil
demarrer()
ouvrirCarte(37); avancer()
verifie("sans l'état des quêtes rendues : aucune épingle (on ne ment pas)", 0, #epinglesVisibles())
verifie("sans l'état des quêtes rendues : le dit", true, lireImprime():find("ne dit pas quelles quêtes sont rendues", 1, true) ~= nil)

installer(true)
C_Map.GetMapPosFromWorldPos = nil
demarrer()
ouvrirCarte(37); avancer()
verifie("sans conversion de position : le dit, aucune épingle", true,
  lireImprime():find("ne sait pas convertir les positions", 1, true) ~= nil and #epinglesVisibles() == 0)

installer(true)
UnitLevel = nil
demarrer()
ouvrirCarte(37); avancer()
-- Depuis la 0.2.2, « trop haut niveau » est coché au départ : au niveau 1, les quêtes de plus de 4 niveaux au-dessus sont cachées.
verifie("sans UnitLevel : niveau 1 par défaut, la quête de niveau 8 absente", "1 | 12 | 4,6 | 9,10", resume())

installer(true)
C_Map.GetMapInfo = nil
local ni = demarrer()
ouvrirCarte(37); avancer()
verifie("sans GetMapInfo : toute carte est prise pour une zone, la forêt marche", "1,2 | 12 | 4,6,18 | 9,10", resume())
changerCarte(947); avancer()
verifie("sans GetMapInfo : la carte du monde, sans erreur", nil, ni.derniereErreur)

-- La déconnexion avant tout calcul : pas d'erreur.
installer(true)
demarrer()
declencher("PLAYER_LOGOUT")
verifie("déconnexion : diagnostic écrit", "table", type(QuetesDispoDB.diagnostic))

-- Un calcul fait avant de reconnaître une ville n'est pas gardé pour toujours (constat 11 de la relecture).
do
  installer(true)
  JEU.ori = 3 -- le jeu tourne les positions : la première transformation est fausse
  JEU.absentes = {}
  for _, anc in ipairs(ns.ANCRES) do for _, id in ipairs(anc[1]) do JEU.absentes[id] = true end end
  local nc = demarrer()
  ouvrirCarte(37); avancer()
  verifie("calibration impossible : aucune épingle (positions fausses), pas d'erreur", "0," .. tostring(nil), #epinglesVisibles() .. "," .. tostring(nc.derniereErreur))
  JEU.absentes = nil -- le jeu connaît maintenant ses villes
  changerCarte(947); avancer()
  changerCarte(37); avancer()
  verifie("calibration réussie plus tard : le calcul provisoire est refait, les épingles apparaissent", "1,2 | 12 | 4,6,18 | 9,10", resume())
end

-- ============================================================================
-- 3. Le VRAI Donnees.lua, chargé avec l'addon (constats 1, 2, 3, 8 de la relecture).
-- ============================================================================
local donneesLua = fichier:gsub("[^/]+$", "Donnees.lua")
do
  installer(true)
  JEU.niveau = 8
  local reel = {}
  assert(loadfile(reglagesLua))("QuetesDispo", reel)
  assert(loadfile(donneesLua))("QuetesDispo", reel)
  assert(loadfile(fichier))("QuetesDispo", reel)
  declencher("ADDON_LOADED", "QuetesDispo")
  declencher("PLAYER_ENTERING_WORLD")
  avancer()

  -- Accord des deux fichiers : toute quête d'un point a sa fiche, tout champ est lu.
  local nq, np, sansFiche, mal = 0, #reel.DEPARTS, 0, 0
  for numero, l in pairs(reel.QUETES) do
    nq = nq + 1
    if type(l[1]) ~= "number" or type(l[10]) ~= "string" or #l < 10 or #l > 12 then mal = mal + 1 end
  end
  for _, dd in ipairs(reel.DEPARTS) do
    for _, q in ipairs(dd[5]) do if not reel.QUETES[q] then sansFiche = sansFiche + 1 end end
  end
  verifie("vrai fichier : au moins 3500 quêtes", true, nq >= 3500)
  verifie("vrai fichier : au moins 1500 points de départ", true, np >= 1500)
  verifie("vrai fichier : chaque ligne a 10 à 12 champs, niveau nombre, titre texte", 0, mal)
  verifie("vrai fichier : aucune quête d'un point sans fiche", 0, sansFiche)
  verifie("vrai fichier : « Test of Faith » (1149) gardée", true, reel.QUETES[1149] ~= nil)
  verifie("vrai fichier : « Testing the Vessel » (3123) gardée", true, reel.QUETES[3123] ~= nil)
  verifie("vrai fichier : 247 demande 2, 23 ou 24 (NextQuestId)", "2,23,24", reel.QUETES[247] and type(reel.QUETES[247][11]) == "table" and table.concat(reel.QUETES[247][11], ",") or "?")
  verifie("vrai fichier : 813 demande 812 en cours (négatif)", -812, reel.QUETES[813] and reel.QUETES[813][5])

  -- Forêt d'Elwynn simulée, humain paladin de niveau 8.
  ouvrirCarte(37); avancer()
  verifie("vrai fichier : pas d'erreur", nil, reel.derniereErreur)
  local pins = epinglesVisibles()
  verifie("vrai fichier, Elwynn : des épingles plausibles (au moins 3)", true, #pins >= 3)
  local etat = reel.etat()
  verifie("vrai fichier, Elwynn : des quêtes à prendre (au moins 8)", true, etat and etat.montrees >= 8)
  local tout, fautes = 0, {}
  for _, p in ipairs(pins) do
    for _, q in ipairs(p.donnees.quetes) do
      tout = tout + 1
      local f = reel.fiche(q)
      local dispo = reel.disponible(f, {
        niveau = 8, masqueRace = 1, faction = "Alliance", masqueClasse = 2, plageVerte = 8,
        rendues = function() return false end, enCours = function() return false end, metiers = {}, ignorees = {},
        groupes = reel.exclusifs(reel.QUETES),
      }, { donjons = true, metiers = true })
      if not dispo then fautes[#fautes + 1] = q end
      -- Un humain ne voit jamais une quête réservée à la Horde.
      if f.races ~= 0 and f.races % 2 < 1 then fautes[#fautes + 1] = q end
    end
  end
  verifie("vrai fichier, Elwynn : aucune quête d'une épingle n'est refusée au joueur, aucune de la Horde", "", table.concat(fautes, ","))
  local avec783 = pinAvec(783)
  verifie("vrai fichier, Elwynn : « A Threat Within » (783) a son épingle", true, avec783 ~= nil)
  verifie("vrai fichier, Elwynn : le titre de la quête 783 dans la bulle", true,
    avec783 and survoler(avec783):find("A Threat Within", 1, true) ~= nil)
  verifie("vrai fichier, Elwynn : une quête de la Horde (Durotar) n'y est pas", nil, pinAvec(5441))
  verifie("vrai fichier, Elwynn : 247 (niveau 30) n'est pas montrée", nil, pinAvec(247))
  io.write(string.format("   (vrai fichier : %d quêtes, %d points, %d épingles et %d quêtes montrées en Elwynn)\n", nq, np, #pins, tout))
  io.write("   quêtes vues : " .. table.concat(etat.titres, " ; ") .. "\n")
end

-- Reglages.lua : une dernière fois, identique à celui de QuetesAuto.
verifie("Reglages.lua toujours identique dans QuetesAuto", true,
  lire(reglagesLua) == lire((reglagesLua:gsub("QuetesDispo/Reglages", "QuetesAuto/Reglages"))))

print = io.write and function(...) io.write(table.concat({ ... }, " "), "\n") end or print
io.write(string.format("%d vérifications OK\n", nbOK))
-- Options « trop haut niveau » et « suite pas encore débloquée »
do
  local function egal(nom, attendu, obtenu)
    if attendu ~= obtenu then print("ECHEC  " .. nom .. " : attendu " .. tostring(attendu) .. ", obtenu " .. tostring(obtenu)); os.exit(1) end
    print("OK  " .. nom)
  end
  local J = { niveau = 12, masqueRace = 1, faction = "Alliance", masqueClasse = 2, rendues = function() return false end, enCours = function() return false end }
  local haute = { numero = 900001, niveau = 20, niveauMin = 10, races = 0, classes = 0, avant = 0, groupe = 0, drapeaux = 0, metier = 0 }
  local ok, raison = ns.disponible(haute, J, { tropHaut = true, ecartHaut = 4 })
  egal("trop haut : niveau 20 au niveau 12 avec +4 -> cachée", false, ok)
  egal("trop haut : la raison", "tropHaut", raison)
  egal("trop haut : option décochée -> montrée", true, (ns.disponible(haute, J, { tropHaut = false })))
  egal("trop haut : écart +8 -> montrée", true, (ns.disponible(haute, J, { tropHaut = true, ecartHaut = 8 })))
  haute.niveau = 16
  egal("trop haut : juste à la limite (+4) -> montrée", true, (ns.disponible(haute, J, { tropHaut = true, ecartHaut = 4 })))
  haute.niveau = -1
  egal("trop haut : quête sans niveau fixe -> montrée", true, (ns.disponible(haute, J, { tropHaut = true, ecartHaut = 4 })))
  local suite = { numero = 900002, niveau = 12, niveauMin = 10, races = 0, classes = 0, avant = 900003, groupe = 0, drapeaux = 0, metier = 0 }
  egal("suite : pas débloquée, option cochée -> cachée", false, (ns.disponible(suite, J, { suites = true })))
  egal("suite : sans réglage -> cachée (comme avant)", false, (ns.disponible(suite, J, {})))
  local ok2, raison2 = ns.disponible(suite, J, { suites = false })
  egal("suite : option décochée -> montrée", true, ok2)
  egal("suite : marquée pas encore débloquée", "verrouillee", raison2)
end

if ok then io.write("Tout est bon.\n") end
os.exit(ok and 0 or 1)
