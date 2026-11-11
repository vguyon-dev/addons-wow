-- Simulation hors jeu de Tenues : la logique pure (plan, pièces portées, noms, commandes…), puis un
-- chargement simulé de l'addon avec de faux cadres et un faux jeu (équipement, sacs, combat, curseur),
-- avec et sans les API du jeu.
-- Lancer depuis la racine du dépôt, sous Windows :
--   wsl lua5.1 tests/Tenues_simu.lua Tenues/Tenues.lua
local ok = true
local nbOK = 0
local function verifie(libelle, attendu, obtenu)
  local bon = attendu == obtenu
  ok = ok and bon
  if bon then nbOK = nbOK + 1 end
  io.write(string.format("%s %-62s attendu %s, obtenu %s\n", bon and "OK " or "KO ", libelle, tostring(attendu), tostring(obtenu)))
end

local fichier = arg[1]
local reglagesLua = fichier:gsub("[^/]+$", "Reglages.lua")

local function lire(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end
verifie("Reglages.lua identique dans QuetesAuto", true,
  lire(reglagesLua) == lire((reglagesLua:gsub("Tenues/Reglages", "QuetesAuto/Reglages"))))
local toc = lire((fichier:gsub("Tenues%.lua$", "Tenues.toc")))
verifie("toc : charge Reglages.lua puis Tenues.lua", true, toc:find("Reglages%.lua%s+Tenues%.lua") ~= nil)
verifie("toc : sauvegardes déclarées", true, toc:find("## SavedVariables: TenuesDB", 1, true) ~= nil
  and toc:find("## SavedVariablesPerCharacter: TenuesPerso", 1, true) ~= nil)
verifie("toc : les deux versions du jeu", true, toc:find("## Interface: 120105, 16001", 1, true) ~= nil)
verifie("toc : fonction du compartiment d'addons", true, toc:find("## AddonCompartmentFunc: Tenues_OuvrirReglages", 1, true) ~= nil)
verifie("toc : catégorie, auteur, version", true, toc:find("## Category: Addons de Valentin", 1, true) ~= nil
  and toc:find("## Author: Valentin", 1, true) ~= nil and toc:find("## Version: 0.1.0", 1, true) ~= nil)
local bindings = lire((fichier:gsub("Tenues%.lua$", "Bindings.xml")))
for n = 1, 5 do
  verifie("Bindings.xml : touche " .. n, true, bindings:find('name="TENUES_TENUE' .. n .. '"', 1, true) ~= nil
    and bindings:find("Tenues_Touche(" .. n .. ")", 1, true) ~= nil)
end
verifie("Bindings.xml : en-tête TENUES", true, bindings:find('header="TENUES"', 1, true) ~= nil)
local sourceTexte = lire(fichier)
verifie("aucun tiret cadratin ni demi-cadratin dans l'addon", true,
  not sourceTexte:find("\226\128\148", 1, true) and not sourceTexte:find("\226\128\147", 1, true))
verifie("aucun nom avec accent dans le code (Lua 5.1)", true, (function()
  for ligne in sourceTexte:gmatch("[^\n]+") do
    local code = ligne:gsub('%-%-.*$', ''):gsub('"[^"]*"', '""')
    for mot in code:gmatch("[%w_\128-\255]+") do
      if mot:find("[\128-\255]") then return false end
    end
  end
  return true
end)())

-- ============================================================================
-- 1. La logique pure : on charge le fichier sans aucune fonction du jeu.
-- ============================================================================
local ns = {}
assert(loadfile(fichier))("Tenues", ns)

local function L(id, nom, niveau)
  return "|cff0070dd|Hitem:" .. id .. "::::::::" .. (niveau or 60) .. ":::::|h[" .. nom .. "]|h|r"
end
local CASQUE, TORSE, EPEE, EPEE2, BOUCLIER = L(1001, "Casque"), L(1002, "Torse"), L(1003, "Épée longue"), L(1004, "Épée courte"), L(1005, "Bouclier")
local BAGUE_A, BAGUE_B, BAGUE_C = L(2001, "Bague A"), L(2002, "Bague B"), L(2003, "Bague C")
local CANNE, CHAPEAU, BOTTES_P, BOTTES_C = L(3001, "Canne à pêche"), L(3002, "Chapeau de pêcheur"), L(3003, "Bottes de pêcheur"), L(1006, "Bottes de combat")

-- Les noms et les nombres.
verifie("numeroObjet : lien", 1001, ns.numeroObjet(CASQUE))
verifie("numeroObjet : item:42", 42, ns.numeroObjet("item:42"))
verifie("numeroObjet : un nombre", 7, ns.numeroObjet(7))
verifie("numeroObjet : texte sans objet", nil, ns.numeroObjet("bidule"))
verifie("numeroObjet : nil", nil, ns.numeroObjet(nil))
verifie("sansAccents : Pêche", "peche", ns.sansAccents("Pêche"))
verifie("sansAccents : majuscules accentuées", "epee", ns.sansAccents("ÉPÉE"))
verifie("sansAccents : apostrophe et espaces", "tenue d ete", ns.sansAccents("  Tenue d'été "))
verifie("memePiece : même lien", true, ns.memePiece(CASQUE, CASQUE))
verifie("memePiece : même objet, niveau du lien différent", true, ns.memePiece(L(1001, "Casque", 60), L(1001, "Casque", 61)))
verifie("memePiece : objets différents", false, ns.memePiece(CASQUE, TORSE))
verifie("memePiece : nil", false, ns.memePiece(CASQUE, nil))

-- trouverTenue.
local tenues = { { nom = "Combat", pieces = {} }, { nom = "Pêche", pieces = {} }, { nom = "Pêche de nuit", pieces = {} },
  { nom = "Ville", pieces = {} } }
local t, i = ns.trouverTenue(tenues, "combat")
verifie("trouverTenue : exact, casse", "Combat", t and t.nom)
verifie("trouverTenue : indice", 1, i)
verifie("trouverTenue : sans accents", "Pêche", (ns.trouverTenue(tenues, "peche") or {}).nom)
verifie("trouverTenue : exact avant les débuts de nom", 2, select(2, ns.trouverTenue(tenues, "PECHE")))
verifie("trouverTenue : début unique", "Ville", (ns.trouverTenue(tenues, "vil") or {}).nom)
verifie("trouverTenue : début unique, indice", 4, select(2, ns.trouverTenue(tenues, "vil")))
t, i = ns.trouverTenue(tenues, "pec")
verifie("trouverTenue : début ambigu : nil", nil, t)
verifie("trouverTenue : début ambigu : la liste", "Pêche,Pêche de nuit", type(i) == "table" and table.concat(i, ",") or tostring(i))
verifie("trouverTenue : inconnue", nil, (ns.trouverTenue(tenues, "zzz")))
verifie("trouverTenue : inconnue, pas de liste", nil, select(2, ns.trouverTenue(tenues, "zzz")))
verifie("trouverTenue : texte vide", nil, (ns.trouverTenue(tenues, "  ")))
verifie("tenuePeche : sans accents", "Pêche", (ns.tenuePeche(tenues) or {}).nom)
verifie("tenuePeche : aucune", nil, ns.tenuePeche({ { nom = "Combat", pieces = {} } }))

-- nomValide.
local function nom(texte, liste) return ns.nomValide(texte, liste or tenues) end
verifie("nomValide : vide", nil, (nom("")))
verifie("nomValide : vide, message", "donne un nom à la tenue.", select(2, nom("   ")))
verifie("nomValide : nil", nil, (nom(nil)))
verifie("nomValide : déjà pris (casse, accents)", nil, (nom("peche")))
verifie("nomValide : déjà pris, message", "une tenue s'appelle déjà « Pêche ».", select(2, nom("PÊCHE")))
verifie("nomValide : espaces nettoyés", "Nouvelle tenue", nom("  Nouvelle   tenue "))
verifie("nomValide : mot réservé retour", nil, (nom("Retour")))
verifie("nomValide : mot réservé enregistrer", nil, (nom("enregistrer")))
verifie("nomValide : mot réservé liste", nil, (nom("liste")))
verifie("nomValide : 24 lettres accentuées", "ééééééééééééééééééééééée", nom("ééééééééééééééééééééééée"))
verifie("nomValide : 25 lettres", nil, (nom("éééééééééééééééééééééééééé")))
verifie("nomValide : barre verticale", nil, (nom("a|b")))

-- ns.plan.
local function sac(sacNum, case, lien) return { sac = sacNum, case = case, lien = lien } end
local combat = { nom = "Combat", pieces = { [1] = CASQUE, [5] = TORSE, [8] = BOTTES_C, [16] = EPEE, [17] = BOUCLIER } }
local peche = { nom = "Pêche", pieces = { [1] = CHAPEAU, [8] = BOTTES_P, [16] = CANNE } }
local porteCombat = { [1] = CASQUE, [5] = TORSE, [8] = BOTTES_C, [16] = EPEE, [17] = BOUCLIER, [11] = BAGUE_A }
local sacsPeche = { sac(0, 3, CANNE), sac(1, 2, CHAPEAU), sac(2, 5, BOTTES_P), sac(0, 9, L(9999, "Cailloux")) }

local plan = ns.plan(peche, porteCombat, sacsPeche)
local function emplacements(p) local l = {} for _, e in ipairs(p.aEquiper) do l[#l + 1] = e.emplacement end return table.concat(l, ",") end
verifie("plan : tenue partielle, trois pièces à mettre", "1,8,16", emplacements(plan))
verifie("plan : tenue partielle, rien de manquant", 0, #plan.manquants)
verifie("plan : tenue partielle, aucune pièce déjà portée", 0, plan.dejaPortes)
verifie("plan : sac et case de la canne", "0,3", plan.aEquiper[3].sac .. "," .. plan.aEquiper[3].case)
verifie("plan : état des pièces dans les sacs", "sac", plan.etat[16])
verifie("plan : la tenue partielle ne touche pas au reste", nil, plan.etat[5])

plan = ns.plan(combat, porteCombat, {})
verifie("plan : tenue déjà portée : rien à mettre", 0, #plan.aEquiper)
verifie("plan : tenue déjà portée : 5 pièces", 5, plan.dejaPortes)
verifie("estPortee : tenue portée", true, ns.estPortee(combat, porteCombat))
verifie("estPortee : une pièce ne l'est pas", false, ns.estPortee(peche, porteCombat))
verifie("estPortee : tenue vide", false, ns.estPortee({ nom = "Vide", pieces = {} }, porteCombat))
verifie("estPortee : sans porté", false, ns.estPortee(combat, nil))
verifie("estPortee : porté avec en plus d'autres pièces", true, ns.estPortee(peche, { [1] = CHAPEAU, [8] = BOTTES_P, [16] = CANNE, [5] = TORSE }))

-- Ordre : la main droite avant la main gauche, quelle que soit la façon dont la tenue est écrite.
plan = ns.plan({ nom = "T", pieces = { [17] = BOUCLIER, [16] = EPEE } }, { [16] = EPEE2 }, { sac(0, 1, BOUCLIER), sac(0, 2, EPEE) })
verifie("plan : main droite avant main gauche", "16,17", emplacements(plan))

-- Deux anneaux identiques : une même pièce des sacs n'est jamais attribuée à deux emplacements.
local deuxAnneaux = { nom = "Anneaux", pieces = { [11] = BAGUE_A, [12] = BAGUE_A } }
plan = ns.plan(deuxAnneaux, { [11] = BAGUE_B, [12] = BAGUE_C }, { sac(0, 4, BAGUE_A) })
verifie("deux anneaux identiques, un seul dans les sacs : un seul ordre", "11", emplacements(plan))
verifie("deux anneaux identiques, un seul dans les sacs : un manquant", 1, #plan.manquants)
verifie("deux anneaux identiques, un seul dans les sacs : état du second", "manque", plan.etat[12])
plan = ns.plan(deuxAnneaux, { [11] = BAGUE_B, [12] = BAGUE_C }, { sac(0, 4, BAGUE_A), sac(1, 1, BAGUE_A) })
verifie("deux anneaux identiques, deux dans les sacs : deux ordres", "11,12", emplacements(plan))
verifie("deux anneaux identiques : deux cases différentes", true,
  plan.aEquiper[1].sac .. plan.aEquiper[1].case ~= plan.aEquiper[2].sac .. plan.aEquiper[2].case)
-- Un anneau déjà porté dans l'autre emplacement de la paire n'est pas manquant.
plan = ns.plan({ nom = "A", pieces = { [11] = BAGUE_A, [12] = BAGUE_B } }, { [11] = BAGUE_B, [12] = BAGUE_A }, {})
verifie("anneaux échangés : rien à faire", 0, #plan.aEquiper + #plan.manquants)
verifie("anneaux échangés : deux déjà portés", 2, plan.dejaPortes)
verifie("anneaux échangés : la tenue est portée", true, ns.estPortee({ nom = "A", pieces = { [11] = BAGUE_A, [12] = BAGUE_B } }, { [11] = BAGUE_B, [12] = BAGUE_A }))
plan = ns.plan(deuxAnneaux, { [11] = BAGUE_A, [12] = BAGUE_C }, { sac(0, 4, BAGUE_A) })
verifie("même anneau deux fois, un porté : le second vient des sacs", "12", emplacements(plan))
verifie("même anneau deux fois, un porté : une pièce déjà portée", 1, plan.dejaPortes)
plan = ns.plan({ nom = "A", pieces = { [11] = BAGUE_A } }, { [11] = BAGUE_C, [12] = BAGUE_A }, {})
verifie("anneau voulu porté dans l'autre emplacement : rien à faire", 0, #plan.aEquiper + #plan.manquants)
local bijoux = { nom = "B", pieces = { [13] = L(4001, "Bijou X"), [14] = L(4002, "Bijou Y") } }
verifie("bijoux échangés : portée", true, ns.estPortee(bijoux, { [13] = L(4002, "Bijou Y"), [14] = L(4001, "Bijou X") }))
verifie("armes : pas de jumeau (main droite et gauche ne s'échangent pas)", false,
  ns.estPortee({ nom = "W", pieces = { [16] = EPEE, [17] = EPEE2 } }, { [16] = EPEE2, [17] = EPEE }))

-- Deux anneaux : la pièce voulue en 12, déjà portée en 11, n'est pas chassée par l'autre anneau.
local bagues = { nom = "Bagues", pieces = { [11] = BAGUE_A, [12] = BAGUE_B } }
local porteBagues = { [11] = BAGUE_B, [12] = BAGUE_C }
plan = ns.plan(bagues, porteBagues, { sac(0, 4, BAGUE_A) })
verifie("anneaux : B voulu en 12 et porté en 11, A vient des sacs : un seul ordre", 1, #plan.aEquiper)
verifie("anneaux : l'ordre vise l'emplacement 12 (celui de C), pas le 11", 12, plan.aEquiper[1] and plan.aEquiper[1].emplacement)
verifie("anneaux : B reste en 11 (une pièce déjà portée)", 1, plan.dejaPortes)
verifie("anneaux : rien de manquant", 0, #plan.manquants)
verifie("anneaux : précédente retient C (celui qui part), pas B", "nil,2003", tostring(ns.precedente(plan, porteBagues)[11]) .. "," .. ns.numeroObjet(ns.precedente(plan, porteBagues)[12]))
plan = ns.plan({ nom = "B", pieces = { [13] = L(4001, "Bijou X"), [14] = L(4002, "Bijou Y") } },
  { [13] = L(4002, "Bijou Y"), [14] = L(4003, "Bijou Z") }, { sac(0, 1, L(4001, "Bijou X")) })
verifie("bijoux : même cas, l'ordre vise le 14", 14, plan.aEquiper[1] and plan.aEquiper[1].emplacement)
plan = ns.plan(bagues, { [11] = BAGUE_C, [12] = BAGUE_B }, { sac(0, 4, BAGUE_A) })
verifie("anneaux : B déjà en 12, A vient en 11 comme avant", 11, plan.aEquiper[1] and plan.aEquiper[1].emplacement)
-- Les deux mains échangées : ni « manquantes » ni « portées ».
local armes = { nom = "Armes", pieces = { [16] = EPEE, [17] = EPEE2 } }
local porteArmes = { [16] = EPEE2, [17] = EPEE }
plan = ns.plan(armes, porteArmes, {})
verifie("mains échangées : rien de manquant", 0, #plan.manquants)
verifie("mains échangées : aucun ordre", 0, #plan.aEquiper)
verifie("mains échangées : deux armes à l'envers", 2, plan.inverses)
verifie("mains échangées : état des emplacements", "inverse,inverse", tostring(plan.etat[16]) .. "," .. tostring(plan.etat[17]))
verifie("mains échangées : la tenue n'est pas dite portée", false, ns.estPortee(armes, porteArmes))
plan = ns.plan({ nom = "A", pieces = { [16] = EPEE } }, { [16] = EPEE2 }, {})
verifie("une arme vraiment absente reste manquante", 1, #plan.manquants)
verifie("une arme vraiment absente : pas d'inversion", 0, plan.inverses)

-- Arme à deux mains puis une main + main gauche.
local uneMain = { nom = "Une main", pieces = { [16] = EPEE, [17] = BOUCLIER } }
local DEUX_MAINS = L(5001, "Espadon")
plan = ns.plan(uneMain, { [16] = DEUX_MAINS }, { sac(0, 1, EPEE), sac(0, 2, BOUCLIER) })
verifie("deux mains vers une main + bouclier : 16 puis 17", "16,17", emplacements(plan))
local prec = ns.precedente(plan, { [16] = DEUX_MAINS })
verifie("précédente : l'espadon retenu", DEUX_MAINS, prec[16])
verifie("précédente : rien dans la main gauche (elle était vide)", nil, prec[17])
plan = ns.plan({ nom = "Deux mains", pieces = { [16] = DEUX_MAINS } }, { [16] = EPEE, [17] = BOUCLIER }, { sac(0, 1, DEUX_MAINS) })
prec = ns.precedente(plan, { [16] = EPEE, [17] = BOUCLIER })
verifie("une main + bouclier vers deux mains : l'épée retenue", EPEE, prec[16])
verifie("une main + bouclier vers deux mains : le bouclier retenu aussi", BOUCLIER, prec[17])
prec = ns.precedente(ns.plan(peche, porteCombat, sacsPeche), porteCombat)
verifie("précédente de la pêche : casque, bottes, épée et bouclier", "1,8,16,17", (function()
  local l = {} for s = 1, 19 do if prec[s] then l[#l + 1] = s end end return table.concat(l, ",")
end)())
verifie("précédente : rien à changer, rien à retenir", nil, next(ns.precedente(ns.plan(combat, porteCombat, {}), porteCombat)))
local fus = ns.fusionnerPrecedente({ [1] = CASQUE }, { [1] = CHAPEAU, [8] = BOTTES_C })
verifie("fusion : l'ancienne valeur gagne", CASQUE, fus[1])
verifie("fusion : un emplacement nouveau s'ajoute", BOTTES_C, fus[8])

-- Pièce manquante.
plan = ns.plan({ nom = "M", pieces = { [1] = CASQUE, [2] = L(7000, "Collier") } }, {}, { sac(0, 1, CASQUE) })
verifie("manquant : le collier", L(7000, "Collier"), plan.manquants[1])
verifie("manquant : le casque est mis", "1", emplacements(plan))
verifie("manquant : état", "manque", plan.etat[2])
verifie("texteManque", "il manque : " .. L(7000, "Collier") .. " (ni portée ni dans tes sacs).", ns.texteManque(plan.manquants))

-- Le lien change avec le niveau : même numéro d'objet, on met la pièce du sac (son lien à elle).
local ancienLien, nouveauLien = L(1001, "Casque", 60), L(1001, "Casque", 61)
plan = ns.plan({ nom = "N", pieces = { [1] = ancienLien } }, {}, { sac(0, 1, nouveauLien) })
verifie("lien d'un autre niveau : trouvé dans les sacs", "1", emplacements(plan))
verifie("lien d'un autre niveau : on passe le lien du sac", nouveauLien, plan.aEquiper[1].lien)
verifie("lien d'un autre niveau : déjà porté", true, ns.estPortee({ nom = "N", pieces = { [1] = ancienLien } }, { [1] = nouveauLien }))
-- Un lien exact passe avant un lien ressemblant.
local v1, v2 = L(2001, "Bague", 60), L(2001, "Bague", 61)
plan = ns.plan({ nom = "E", pieces = { [11] = v1, [12] = v2 } }, {}, { sac(0, 1, v2), sac(0, 2, v1) })
verifie("lien exact d'abord : l'anneau 11 prend v1", v1, plan.aEquiper[1].lien)
verifie("lien exact d'abord : l'anneau 12 prend v2", v2, plan.aEquiper[2].lien)
verifie("plan : tenue nil", 0, #ns.plan(nil, {}, {}).aEquiper)

-- Enregistrer, mettre à jour, assainir.
local nouvelle, erreur = ns.fabriquerTenue("Tout", porteCombat, nil)
verifie("fabriquerTenue : tout ce qui est porté", 6, ns.nbPieces(nouvelle))
nouvelle = ns.fabriquerTenue("Pêche", porteCombat, { [1] = true, [8] = true, [16] = true, [5] = false })
verifie("fabriquerTenue : seulement les cases cochées", "1,8,16", table.concat(ns.emplacementsTries(nouvelle.pieces), ","))
verifie("fabriquerTenue : case cochée mais emplacement vide", 2, ns.nbPieces(ns.fabriquerTenue("X", { [1] = CASQUE, [2] = TORSE }, { [1] = true, [2] = true, [3] = true })))
nouvelle, erreur = ns.fabriquerTenue("Rien", {}, nil)
verifie("fabriquerTenue : rien porté", nil, nouvelle)
verifie("fabriquerTenue : message", true, type(erreur) == "string" and erreur:find("aucune pièce", 1, true) ~= nil)
local aJour = { nom = "P", pieces = { [1] = CHAPEAU, [8] = BOTTES_P } }
verifie("majTenue : nombre de pièces changées", 1, ns.majTenue(aJour, { [1] = CASQUE, [8] = BOTTES_P, [5] = TORSE }))
verifie("majTenue : le lien est remplacé", CASQUE, aJour.pieces[1])
verifie("majTenue : les emplacements de la tenue ne changent pas", nil, aJour.pieces[5])
verifie("majTenue : un emplacement vide garde sa pièce", BOTTES_P, (function() ns.majTenue(aJour, { [1] = CASQUE }) return aJour.pieces[8] end)())
local propres = ns.assainir({ { nom = "Bonne", pieces = { [1] = CASQUE, [30] = "x", [2] = 5 } }, { nom = "", pieces = {} },
  { pieces = {} }, "texte", { nom = "SansPieces" } })
verifie("assainir : seule la bonne tenue reste", 1, #propres)
verifie("assainir : seuls les emplacements valides sont gardés", "1", table.concat(ns.emplacementsTries(propres[1].pieces), ","))
verifie("assainir : pas une table", 0, #ns.assainir(nil))

-- La confirmation en deux clics.
local etat = {}
verifie("confirmation : premier clic", false, ns.confirmation(etat, "sup:A"))
verifie("confirmation : second clic", true, ns.confirmation(etat, "sup:A"))
verifie("confirmation : redevient à zéro", false, ns.confirmation(etat, "sup:A"))
ns.confirmation(etat, "maj:A")
verifie("confirmation : un autre clic désarme le premier", false, ns.confirmation(etat, "sup:A"))
verifie("confirmation : la clé armée est la dernière", "sup:A", etat.cle)

-- Les commandes.
local function cmd(texte) local c = ns.analyserCommande(texte) return c.action .. "|" .. tostring(c.nom) end
verifie("commande : vide", "ouvrir|nil", cmd(""))
verifie("commande : retour", "retour|nil", cmd("retour"))
verifie("commande : Retour en majuscules", "retour|nil", cmd(" RETOUR "))
verifie("commande : liste", "liste|nil", cmd("liste"))
verifie("commande : options", "options|nil", cmd("options"))
verifie("commande : aide", "aide|nil", cmd("aide"))
verifie("commande : enregistrer avec un nom", "enregistrer|Pêche de nuit", cmd("enregistrer Pêche de nuit"))
verifie("commande : enregistrer sans nom", "enregistrer|", cmd("enregistrer"))
verifie("commande : un nom de tenue", "mettre|Pêche", cmd("Pêche"))
verifie("commande : un nom de tenue en plusieurs mots", "mettre|Pêche de nuit", cmd("  Pêche de nuit "))
verifie("commande : « retour de plage » n'est pas retour", "mettre|retour de plage", cmd("retour de plage"))

-- ============================================================================
-- 2. Chargement simulé avec de faux cadres et un faux jeu.
-- ============================================================================
local bidon
bidon = function()
  return setmetatable({}, { __index = function() return bidon() end, __call = function() return bidon() end })
end

local imprime = {}
local function lireImprime() return table.concat(imprime, "\n") end
print = function(...)
  local t = {}
  for k = 1, select("#", ...) do t[k] = tostring((select(k, ...))) end
  imprime[#imprime + 1] = table.concat(t, " ")
end

local toutes, enCombat, file, tickers, JEU, delais
local M = {}
local metaF = {}
function metaF.__index(t, k)
  if type(k) ~= "string" or not k:match("^%u") or k == "ScrollBar" then return nil end
  -- Seul un cadre créé avec BackdropTemplate a SetBackdrop (un cadre simple n'en a pas).
  if (k == "SetBackdrop" or k == "SetBackdropColor" or k == "SetBackdropBorderColor") and not rawget(t, "_fond") then return nil end
  return M[k] or function() end
end

local function nouveau(genre, nom, parent, modele)
  local f = setmetatable({ _type = genre, _nom = nom, _parent = parent, _shown = true, _events = {}, _scripts = {},
    _w = 100, _h = 20, _scale = 1, _text = "", _attr = {}, _niveau = 1, _crochets = {} }, metaF)
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
function M.GetStringHeight(s)
  local _, n = s._text:gsub("\n", "")
  return 12 * (n + 1)
end
function M.SetText(s, t) s._text = tostring(t == nil and "" or t) end
function M.GetText(s) return s._text end
function M.SetTextColor(s, r, g, b) s._couleur = { r, g, b } end
function M.SetVertexColor(s, r, g, b) s._sommet = { r, g, b } end
function M.SetBackdropBorderColor(s, r, g, b) s._bord = { r, g, b } end
function M.SetTexture(s, t) s._texture = t end
function M.SetPoint(s, point, rel, relPoint, x, y)
  if type(rel) == "number" then x, y, rel, relPoint = rel, relPoint, nil, nil end
  s._pt = { point, rel, relPoint or point, x or 0, y or 0 }
end
function M.ClearAllPoints(s) s._pt = nil end
function M.GetPoint(s) local p = s._pt or { "CENTER", UIParent, "CENTER", 0, 0 } return p[1], p[2], p[3], p[4], p[5] end
function M.GetLeft(s) return s._gauche or 1500 end
function M.GetRight(s) return s._droite or 1800 end
function M.GetTop(s) return s._haut or 800 end
function M.GetBottom() return 300 end
function M.GetCenter() return 500, 400 end
function M.GetEffectiveScale(s) return s._scale end
function M.SetScale(s, v) s._scale = v end
function M.SetAlpha(s, v) s._alpha = v end
function M.GetAlpha(s) return s._alpha or 1 end
function M.GetScale(s) return s._scale end
function M.Show(s)
  local etait = s._shown
  s._shown = true
  if not etait and s._scripts.OnShow then s._scripts.OnShow(s) end
end
function M.Hide(s) s._shown = false end
function M.SetShown(s, v) if v then M.Show(s) else M.Hide(s) end end
function M.IsShown(s) return s._shown end
function M.IsVisible(s) return s._shown end
function M.RegisterEvent(s, e) s._events[e] = true end
M.RegisterUnitEvent = M.RegisterEvent
function M.UnregisterEvent(s, e) s._events[e] = nil end
function M.SetScript(s, nom, fn) s._scripts[nom] = fn end
function M.GetScript(s, nom) return s._scripts[nom] end
function M.CreateFontString(s) return nouveau("FontString", nil, s) end
function M.CreateTexture(s) return nouveau("Texture", nil, s) end
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
function M.GetThumbTexture() return bidon() end
function M.EnableMouse(s, v) s._souris = v end
function M.SetOwner(s, propre) s._propre = propre end

-- Le faux jeu : équipement, sacs, curseur.
local function premierTrou()
  for numeroSac = 0, 4 do
    for case = 1, JEU.tailles[numeroSac + 1] do
      if JEU.sacs[numeroSac][case] == nil then return numeroSac, case end
    end
  end
end

local function echanger(lien, emplacement)
  for numeroSac = 0, 4 do
    for case, l in pairs(JEU.sacs[numeroSac]) do
      if l == lien then
        local ancien = JEU.porte[emplacement]
        JEU.porte[emplacement] = lien
        JEU.sacs[numeroSac][case] = ancien
        if emplacement == 16 and JEU.deuxMains[lien] and JEU.porte[17] then
          local s2, c2 = premierTrou()
          JEU.sacs[s2][c2] = JEU.porte[17]
          JEU.porte[17] = nil
        end
        return true
      end
    end
  end
end

local function installer(retirer)
  toutes, enCombat, file, tickers, delais = {}, false, {}, {}, {}
  imprime = {}
  _G.ValentinAddons, _G.ValentinAddonsReglages, _G.ValentinAddonsMinimap = nil, nil, nil
  _G.TenuesDB, _G.TenuesPerso, _G.TenuesFenetre = nil, nil, nil
  _G.UIParent = nouveau("Frame", "UIParent")
  UIParent._h, UIParent._w = 1080, 1920
  _G.GameTooltip = nouveau("GameTooltip", "GameTooltip")
  _G.Minimap = nouveau("Frame", "Minimap")
  _G.CreateFrame = function(genre, nom, parent, modele) return nouveau(genre, nom, parent or UIParent, modele) end
  _G.UISpecialFrames, _G.SlashCmdList = {}, {}
  _G.tinsert = table.insert
  _G.strtrim = function(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
  _G.hooksecurefunc = function(t, nom, fn)
    t._crochets[nom] = t._crochets[nom] or {}
    table.insert(t._crochets[nom], fn)
  end
  _G.C_Timer = {
    After = function(d, fn)
      assert(type(fn) == "function", "C_Timer.After exige une fonction Lua")
      delais[#delais + 1] = d
      file[#file + 1] = fn
    end,
    NewTicker = function(_, fn) tickers[#tickers + 1] = fn return {} end,
  }
  _G.InCombatLockdown = function() return enCombat end
  _G.IsShiftKeyDown, _G.IsControlKeyDown, _G.IsAltKeyDown = function() return false end, function() return false end, function() return false end
  _G.GetCursorPosition = function() return 600, 500 end
  _G.UnitName = function() return "Testeur" end
  _G.GetRealmName = function() return "Royaume" end
  _G.UNKNOWNOBJECT = "Inconnu"
  _G.BackdropTemplateMixin = {}
  _G.PlaySound, _G.HideUIPanel, _G.ClearCursor = function() end, function() end, function() JEU.curseur = nil end
  _G.GetTime = function() return 0 end

  JEU = { porte = {}, sacs = { [0] = {}, [1] = {}, [2] = {}, [3] = {}, [4] = {} }, tailles = { 16, 6, 6, 6, 6 },
    appels = {}, curseur = nil, mort = false, deuxMains = {}, touches = {}, secret = {}, enregistrees = 0 }
  _G.JEU = JEU
  _G.NUM_BAG_SLOTS = 4
  _G.issecretvalue = function(v) return type(v) == "table" and v.secret == true end
  _G.GetInventoryItemLink = function(_, slot) return JEU.secret[slot] or JEU.porte[slot] end
  _G.C_Container = {
    GetContainerNumSlots = function(s) return JEU.tailles[s + 1] or 0 end,
    GetContainerItemLink = function(s, c) return JEU.sacs[s] and JEU.sacs[s][c] end,
    GetContainerItemInfo = function(s, c) local l = JEU.sacs[s] and JEU.sacs[s][c] if l then return { hyperlink = l } end end,
    PickupContainerItem = function(s, c) JEU.curseur = { sac = s, case = c, lien = JEU.sacs[s][c] } end,
  }
  _G.C_Item = {
    EquipItemByName = function(lien, slot)
      JEU.appels[#JEU.appels + 1] = { lien = lien, slot = slot, via = "C_Item" }
      echanger(lien, slot)
    end,
    GetItemInfoInstant = function(lien) return tonumber(tostring(lien):match("item:(%d+)")), "Armure", "Tissu", "", 134000 end,
  }
  _G.EquipItemByName = function(lien, slot)
    JEU.appels[#JEU.appels + 1] = { lien = lien, slot = slot, via = "global" }
    echanger(lien, slot)
  end
  _G.EquipCursorItem = function(slot)
    if JEU.curseur then
      JEU.appels[#JEU.appels + 1] = { lien = JEU.curseur.lien, slot = slot, via = "curseur" }
      echanger(JEU.curseur.lien, slot)
      JEU.curseur = nil
    end
  end
  _G.PickupInventoryItem = function(slot)
    if JEU.curseur then
      JEU.appels[#JEU.appels + 1] = { lien = JEU.curseur.lien, slot = slot, via = "inventaire" }
      echanger(JEU.curseur.lien, slot)
      JEU.curseur = nil
    end
  end
  _G.GetCursorInfo = function() if JEU.curseur then return "item", 1, JEU.curseur.lien end end
  _G.UnitIsDeadOrGhost = function() return JEU.mort end
  _G.GetBindingKey = function(nomLiaison) return JEU.touches[nomLiaison] end
  _G.SetBinding = function(touche, nomLiaison)
    if nomLiaison then JEU.touches[nomLiaison] = touche
    else for k, v in pairs(JEU.touches) do if v == touche then JEU.touches[k] = nil end end end
  end
  _G.SaveBindings = function() JEU.enregistrees = JEU.enregistrees + 1 end
  _G.GetCurrentBindingSet = function() return 1 end
  _G.GetBindingText = function(t) return "<" .. t .. ">" end

  for _, n in ipairs(retirer or {}) do
    local a, b = n:match("^([^%.]+)%.(.+)$")
    if a then _G[a][b] = nil else _G[n] = nil end
  end
end

local function declencher(evenement, ...)
  for _, f in ipairs(toutes) do
    if f._events[evenement] and f._scripts.OnEvent then f._scripts.OnEvent(f, evenement, ...) end
  end
end
local function avancer()
  local garde = 0
  while #file > 0 and garde < 1000 do garde = garde + 1; table.remove(file, 1)() end
end

local function chargerAddon()
  local n = {}
  assert(loadfile(reglagesLua))("Tenues", n)
  assert(loadfile(fichier))("Tenues", n)
  return n
end
local function demarrer()
  local n = chargerAddon()
  declencher("ADDON_LOADED", "Tenues")
  declencher("PLAYER_ENTERING_WORLD")
  avancer()
  return n
end

local function boutonTexte(texte, n)
  local trouves = 0
  for _, f in ipairs(toutes) do
    if f._type == "Button" and f._text == texte then
      trouves = trouves + 1
      if trouves == (n or 1) then return f end
    end
  end
end
local function lignesUI()
  local l = {}
  for _, f in ipairs(toutes) do
    if rawget(f, "bSupprimer") then l[#l + 1] = f end
  end
  return l
end
local function lignesVisibles()
  local l = {}
  for _, f in ipairs(lignesUI()) do if f._shown then l[#l + 1] = f end end
  return l
end
local function casesUI()
  local l = {}
  for _, f in ipairs(toutes) do
    if f._type == "Button" and rawget(f, "fond") and f._parent == TenuesFenetre then l[#l + 1] = f end
  end
  return l
end
local function champNom()
  for _, f in ipairs(toutes) do if f._type == "EditBox" and f._parent == TenuesFenetre then return f end end
end
local function porteLiens()
  local l = {}
  for s = 1, 19 do if JEU.porte[s] then l[#l + 1] = s .. "=" .. ns.numeroObjet(JEU.porte[s]) end end
  return table.concat(l, " ")
end
local function ordreDesAppels()
  local l = {}
  for _, a in ipairs(JEU.appels) do l[#l + 1] = a.slot end
  return table.concat(l, ",")
end

-- L'état de départ : un personnage en tenue de combat, la tenue de pêche dans les sacs.
local function etatDepart()
  JEU.porte = { [1] = CASQUE, [5] = TORSE, [8] = BOTTES_C, [16] = EPEE, [17] = BOUCLIER, [11] = BAGUE_A, [12] = BAGUE_B }
  JEU.sacs = { [0] = { [3] = CANNE, [9] = L(9999, "Cailloux") }, [1] = { [2] = CHAPEAU }, [2] = { [5] = BOTTES_P }, [3] = {}, [4] = {} }
  JEU.deuxMains = { [CANNE] = true }
  JEU.appels = {}
end

-- ------------------------------------------------------------ le scénario complet
installer()
local n = demarrer()
local reglages = n.reglages
etatDepart()
verifie("chargement : réglages créés", true, reglages ~= nil)
verifie("chargement : sauvegardes créées", true, TenuesDB ~= nil and TenuesPerso ~= nil and type(TenuesPerso.tenues) == "table")
verifie("chargement : réglages par défaut", true, TenuesDB.actif and TenuesDB.prevenirManque and TenuesDB.modePeche)
verifie("globaux exposés", true, type(Tenues_Mettre) == "function" and type(Tenues_Precedente) == "function"
  and type(Tenues_Touche) == "function" and type(Tenues_ModePeche) == "function" and type(Tenues_OuvrirReglages) == "function")
verifie("textes des raccourcis", true, BINDING_HEADER_TENUES == "Tenues" and BINDING_NAME_TENUES_TENUE5 == "Tenue 5")
verifie("commandes /tenue et /tenues", true, SLASH_TENUES1 == "/tenue" and SLASH_TENUES2 == "/tenues" and type(SlashCmdList.TENUES) == "function")
local tenueFn = SlashCmdList.TENUES

-- Enregistrer par la commande.
tenueFn("enregistrer Combat")
verifie("enregistrer : la tenue Combat existe", 1, #TenuesPerso.tenues)
verifie("enregistrer : 7 pièces portées", 7, n.nbPieces(TenuesPerso.tenues[1]))
verifie("enregistrer : message au chat", true, lireImprime():find("enregistrée (7 pièces)", 1, true) ~= nil)
tenueFn("enregistrer combat")
verifie("enregistrer : nom déjà pris, refusé", 1, #TenuesPerso.tenues)
verifie("enregistrer : message nom déjà pris", true, lireImprime():find("s'appelle déjà", 1, true) ~= nil)
tenueFn("enregistrer")
verifie("enregistrer : nom vide, refusé", 1, #TenuesPerso.tenues)
verifie("enregistrer : message nom vide", true, lireImprime():find("donne un nom", 1, true) ~= nil)
tenueFn("enregistrer retour")
verifie("enregistrer : mot réservé, refusé", 1, #TenuesPerso.tenues)

-- La fenêtre : enregistrer une tenue partielle avec les cases.
tenueFn("")
local fenetre = TenuesFenetre
verifie("fenêtre : ouverte par /tenue", true, fenetre and fenetre._shown)
verifie("fenêtre : escape la ferme (UISpecialFrames)", true, (function()
  for _, nomCadre in ipairs(UISpecialFrames) do if nomCadre == "TenuesFenetre" then return true end end
end)())
verifie("fenêtre : une ligne visible", 1, #lignesVisibles())
verifie("fenêtre : 19 cases d'emplacements", 19, #casesUI())
-- Pour enregistrer la pêche, on porte la tenue de pêche le temps de l'enregistrement.
local sauvePorte = {}
for s, l in pairs(JEU.porte) do sauvePorte[s] = l end
JEU.porte[1], JEU.porte[8], JEU.porte[16], JEU.porte[17] = CHAPEAU, BOTTES_P, CANNE, nil
boutonTexte("Tout décocher")._scripts.OnClick(boutonTexte("Tout décocher"))
local cases = casesUI()
for _, s in ipairs({ 1, 8, 16 }) do cases[s]._scripts.OnClick(cases[s]) end
local champ = champNom()
verifie("fenêtre : champ du nom trouvé", true, champ ~= nil)
champ:SetText("")
boutonTexte("Enregistrer ce que je porte")._scripts.OnClick()
verifie("fenêtre : nom vide, refusé", 1, #TenuesPerso.tenues)
verifie("fenêtre : nom vide, message clair", true, lireImprime():find("donne un nom", 1, true) ~= nil)
champ:SetText("combat")
boutonTexte("Enregistrer ce que je porte")._scripts.OnClick()
verifie("fenêtre : nom déjà pris, refusé", 1, #TenuesPerso.tenues)
champ:SetText("Pêche")
boutonTexte("Enregistrer ce que je porte")._scripts.OnClick()
verifie("fenêtre : tenue partielle enregistrée", 2, #TenuesPerso.tenues)
verifie("fenêtre : seulement les trois cases cochées", "1,8,16", table.concat(n.emplacementsTries(TenuesPerso.tenues[2].pieces), ","))
verifie("fenêtre : le champ est vidé", "", champ:GetText())
JEU.porte = sauvePorte
JEU.sacs[0][3], JEU.sacs[1][2], JEU.sacs[2][5] = CANNE, CHAPEAU, BOTTES_P
JEU.appels = {}
declencher("PLAYER_EQUIPMENT_CHANGED")
avancer()
verifie("fenêtre : deux lignes", 2, #lignesVisibles())
local ligne1, ligne2 = lignesVisibles()[1], lignesVisibles()[2]
verifie("fenêtre : Combat est portée", "Combat |cff40e040(portée)|r", ligne1.nom._text)
verifie("fenêtre : bordure verte de la tenue portée", 0.8, ligne1._bord and ligne1._bord[2])
verifie("fenêtre : Pêche n'est pas portée", "Pêche", ligne2.nom._text)
verifie("fenêtre : bordure dorée sinon", 0.36, ligne2._bord and ligne2._bord[2])
verifie("fenêtre : nombre de pièces", "7 pièces", ligne1.info._text)
verifie("fenêtre : 3 pièces", "3 pièces", ligne2.info._text)
local nbIcones = 0
for _, ic in ipairs(ligne2.icones) do if ic._shown then nbIcones = nbIcones + 1 end end
verifie("fenêtre : trois icônes de pièces", 3, nbIcones)
verifie("fenêtre : icône normale (dans les sacs)", "1,1,1", table.concat(ligne2.icones[1].tex._sommet, ","))

-- Mettre la tenue partielle : trois pièces, une toutes les 0,1 s.
delais = {}
verifie("mettre : Tenues_Mettre rend vrai", true, Tenues_Mettre("peche"))
verifie("mettre : la première pièce est mise tout de suite", "1", ordreDesAppels())
avancer()
verifie("mettre : ordre des pièces", "1,8,16", ordreDesAppels())
local tous01 = #delais > 0
for _, d in ipairs(delais) do if d ~= 0.1 then tous01 = false end end
verifie("mettre : 0,1 s entre deux pièces", true, tous01)
verifie("mettre : la canne, le chapeau et les bottes sont portés", 3001, n.numeroObjet(JEU.porte[16]))
verifie("mettre : le reste ne bouge pas", true, JEU.porte[5] == TORSE and JEU.porte[11] == BAGUE_A and JEU.porte[12] == BAGUE_B)
verifie("mettre : la main gauche est partie dans les sacs (deux mains)", nil, JEU.porte[17])
verifie("mettre : message de fin", true, lireImprime():find("tenue « Pêche » mise.", 1, true) ~= nil)
verifie("mettre : l'ancienne tenue est dans les sacs", true, (function()
  for s = 0, 4 do for _, l in pairs(JEU.sacs[s]) do if l == EPEE then return true end end end
end)())
verifie("précédente retenue : 1, 8, 16 et 17", "1,8,16,17", (function()
  local l = {} for s = 1, 19 do if TenuesPerso.precedente[s] then l[#l + 1] = s end end return table.concat(l, ",")
end)())
verifie("fenêtre : la tenue Pêche est maintenant portée", "Pêche |cff40e040(portée)|r", lignesVisibles()[2].nom._text)

-- Retour.
JEU.appels = {}
verifie("retour : Tenues_Precedente rend vrai", true, Tenues_Precedente())
avancer()
verifie("retour : ordre 1, 8, 16, 17", "1,8,16,17", ordreDesAppels())
verifie("retour : tout est remis comme avant", "1=1001 5=1002 8=1006 11=2001 12=2002 16=1003 17=1005", porteLiens())
JEU.appels = {}
tenueFn("retour")
avancer()
verifie("retour (commande) : remet la pêche (la précédente de la précédente)", "1=3002 5=1002 8=3003 11=2001 12=2002 16=3001", porteLiens())
tenueFn("Combat")
avancer()
verifie("mettre par la commande (nom exact)", "1=1001 5=1002 8=1006 11=2001 12=2002 16=1003 17=1005", porteLiens())
JEU.appels = {}
verifie("mettre une tenue déjà portée : aucun appel", true, Tenues_Mettre("combat") and #JEU.appels == 0)
verifie("mettre une tenue déjà portée : message", true, lireImprime():find("déjà portée", 1, true) ~= nil)
tenueFn("pe")
avancer()
verifie("mettre par un début de nom unique", 3001, n.numeroObjet(JEU.porte[16]))
tenueFn("Combat")
avancer()

-- Plusieurs tenues pour les noms ambigus.
tenueFn("enregistrer Pêche de nuit")
verifie("ambigu : trois tenues", 3, #TenuesPerso.tenues)
imprime = {}
verifie("ambigu : Tenues_Mettre rend faux", false, Tenues_Mettre("pec"))
verifie("ambigu : message avec la liste", true, lireImprime():find("plusieurs tenues commencent par « pec » : Pêche, Pêche de nuit.", 1, true) ~= nil)
imprime = {}
verifie("inconnue : Tenues_Mettre rend faux", false, Tenues_Mettre("zzz"))
verifie("inconnue : message", true, lireImprime():find("aucune tenue « zzz »", 1, true) ~= nil)
tenueFn("liste")
verifie("liste : la tenue portée est signalée", true, lireImprime():find("1. Combat (7 pièces) |cff40e040portée|r", 1, true) ~= nil)
-- On supprime « Pêche de nuit » par la fenêtre, avec confirmation.
local avant = #TenuesPerso.tenues
local l3 = lignesVisibles()[3]
verifie("supprimer : la troisième ligne est Pêche de nuit", true, l3.nom._text:find("Pêche de nuit", 1, true) == 1)
l3.bSupprimer._scripts.OnClick()
verifie("supprimer : un premier clic ne supprime rien", avant, #TenuesPerso.tenues)
verifie("supprimer : le bouton demande « Sûr ? »", "Sûr ?", l3.bSupprimer._text)
l3.bSupprimer._scripts.OnClick()
verifie("supprimer : le second clic supprime", avant - 1, #TenuesPerso.tenues)
verifie("supprimer : la ligne a disparu", 2, #lignesVisibles())
verifie("supprimer : les autres tenues sont intactes", "Combat,Pêche", TenuesPerso.tenues[1].nom .. "," .. TenuesPerso.tenues[2].nom)
-- Une confirmation oubliée repart à zéro (délai de 3 secondes).
local l2 = lignesVisibles()[2]
l2.bSupprimer._scripts.OnClick()
avancer()
verifie("supprimer : sans second clic, l'armement s'éteint", "Suppr.", l2.bSupprimer._text)
l2.bSupprimer._scripts.OnClick()
l2.bMaj._scripts.OnClick()
verifie("supprimer : armer autre chose désarme la suppression", "Suppr.", l2.bSupprimer._text)
verifie("mettre à jour : armé", "Sûr ?", l2.bMaj._text)
-- Mettre à jour la pêche avec ce qui est porté : même emplacements, nouveaux liens.
local CHAPEAU2 = L(3002, "Chapeau de pêcheur", 61)
JEU.porte[1], JEU.porte[8], JEU.porte[16], JEU.porte[17] = CHAPEAU2, BOTTES_P, CANNE, nil
l2.bMaj._scripts.OnClick()
verifie("mettre à jour : le lien est remplacé", CHAPEAU2, TenuesPerso.tenues[2].pieces[1])
verifie("mettre à jour : les autres emplacements ne sont pas ajoutés", "1,8,16", table.concat(n.emplacementsTries(TenuesPerso.tenues[2].pieces), ","))
verifie("mettre à jour : un seul changement dit", true, lireImprime():find("mise à jour (1 pièce changée)", 1, true) ~= nil)
etatDepart()

-- Une pièce manquante : les autres se mettent, le message le dit.
TenuesPerso.tenues[2].pieces[2] = L(7777, "Collier perdu")
imprime = {}
JEU.appels = {}
verifie("manquant : la tenue se met quand même", true, Tenues_Mettre("Pêche"))
avancer()
verifie("manquant : les autres pièces sont mises", "1,8,16", ordreDesAppels())
verifie("manquant : message", true, lireImprime():find("il manque : " .. L(7777, "Collier perdu"), 1, true) ~= nil)
ligne2 = lignesVisibles()[2]
local rouge = 0
for _, ic in ipairs(ligne2.icones) do if ic._shown and ic.tex._sommet and ic.tex._sommet[1] == 1 and ic.tex._sommet[2] == 0.25 then rouge = rouge + 1 end end
verifie("manquant : une icône rouge dans la fenêtre", 1, rouge)
verifie("manquant : la tenue n'est pas « portée »", "Pêche", ligne2.nom._text)
TenuesPerso.tenues[2].pieces[2] = nil
Tenues_Precedente()
avancer()
-- L'option « prévenir » coupée.
TenuesPerso.tenues[2].pieces[2] = L(7777, "Collier perdu")
reglages.changer("prevenirManque", false)
imprime = {}
Tenues_Mettre("Pêche")
avancer()
verifie("manquant : option coupée, pas de message", nil, lireImprime():find("il manque", 1, true))
reglages.changer("prevenirManque", true)
TenuesPerso.tenues[2].pieces[2] = nil
Tenues_Precedente()
avancer()
verifie("retour des essais : combat de nouveau porté", true, n.estPortee(TenuesPerso.tenues[1], JEU.porte))

-- Combat : rien n'est appelé, tout part à la fin du combat.
enCombat = true
JEU.appels = {}
imprime = {}
verifie("combat : Tenues_Mettre rend vrai (gardée)", true, Tenues_Mettre("Pêche"))
avancer()
verifie("combat : aucun appel d'équipement", 0, #JEU.appels)
verifie("combat : message « fin du combat »", true, lireImprime():find("fin du combat", 1, true) ~= nil)
verifie("combat : rien n'a bougé", 1006, n.numeroObjet(JEU.porte[8]))
enCombat = false
declencher("PLAYER_REGEN_ENABLED")
avancer()
verifie("fin du combat : la tenue est mise", "1=3002 5=1002 8=3003 11=2001 12=2002 16=3001", porteLiens())
verifie("fin du combat : dans l'ordre", "1,8,16", ordreDesAppels())
-- Une seule demande en attente : la dernière gagne.
enCombat = true
Tenues_Mettre("Combat")
Tenues_Mettre("Pêche")
enCombat = false
JEU.appels = {}
declencher("PLAYER_REGEN_ENABLED")
avancer()
verifie("deux demandes en combat : la dernière gagne (Pêche, déjà portée)", 0, #JEU.appels)
JEU.appels = {}
declencher("PLAYER_REGEN_ENABLED")
avancer()
verifie("la demande n'est exécutée qu'une fois", 0, #JEU.appels)
-- Le combat commence au milieu de la série.
Tenues_Precedente()
avancer()
JEU.appels = {}
verifie("série : début", true, Tenues_Mettre("Pêche"))
verifie("série : une pièce mise", "1", ordreDesAppels())
enCombat = true
avancer()
verifie("série interrompue : plus aucun appel pendant le combat", "1", ordreDesAppels())
verifie("série interrompue : message", true, lireImprime():find("le combat commence", 1, true) ~= nil)
enCombat = false
declencher("PLAYER_REGEN_ENABLED")
avancer()
verifie("série interrompue : la suite est mise après le combat", "1=3002 5=1002 8=3003 11=2001 12=2002 16=3001", porteLiens())
verifie("série interrompue : la précédente garde les premiers emplacements", "1,8,16,17", (function()
  local l = {} for s = 1, 19 do if TenuesPerso.precedente[s] then l[#l + 1] = s end end return table.concat(l, ",")
end)())
Tenues_Precedente()
avancer()
verifie("série interrompue : le retour remet tout", "1=1001 5=1002 8=1006 11=2001 12=2002 16=1003 17=1005", porteLiens())

-- Mort et curseur.
JEU.mort = true
JEU.appels = {}
verifie("mort : refusé", false, Tenues_Mettre("Pêche"))
verifie("mort : aucun appel", 0, #JEU.appels)
JEU.mort = false
JEU.curseur = { lien = EPEE }
imprime = {}
verifie("curseur occupé : refusé", false, Tenues_Mettre("Pêche"))
verifie("curseur occupé : aucun appel", 0, #JEU.appels)
verifie("curseur occupé : message", true, lireImprime():find("curseur", 1, true) ~= nil)
JEU.curseur = nil

-- Mode pêche.
JEU.appels = {}
Tenues_ModePeche(true)
avancer()
verifie("mode pêche actif : la tenue Pêche est mise", "1=3002 5=1002 8=3003 11=2001 12=2002 16=3001", porteLiens())
Tenues_ModePeche(false)
avancer()
verifie("mode pêche coupé : la précédente revient", "1=1001 5=1002 8=1006 11=2001 12=2002 16=1003 17=1005", porteLiens())
JEU.appels = {}
Tenues_ModePeche(false)
avancer()
verifie("mode pêche coupé deux fois : rien de plus", 0, #JEU.appels)
-- La tenue Pêche déjà portée : le retour ne défait rien d'autre.
Tenues_Mettre("Pêche")
avancer()
TenuesPerso.precedente = { [1] = L(8888, "Vieux casque") }
JEU.appels = {}
Tenues_ModePeche(true)
avancer()
Tenues_ModePeche(false)
avancer()
verifie("mode pêche : tenue déjà portée, pas de retour inattendu", 0, #JEU.appels)
verifie("mode pêche : la tenue Pêche reste portée", 3001, n.numeroObjet(JEU.porte[16]))
Tenues_Precedente()
avancer()
Tenues_Mettre("Combat")
avancer()
-- Un changement de tenue à la main entre-temps : le mode pêche ne défait rien qu'il n'a pas fait.
Tenues_ModePeche(false)
avancer()
verifie("mode pêche : jamais mis, rien à remettre", "1=1001 5=1002 8=1006 11=2001 12=2002 16=1003 17=1005", porteLiens())
-- Option coupée.
reglages.changer("modePeche", false)
JEU.appels = {}
Tenues_ModePeche(true)
avancer()
verifie("mode pêche : option coupée, rien ne change", 0, #JEU.appels)
reglages.changer("modePeche", true)
-- Pas de tenue Pêche : rien, sans message.
local sauveTenues = TenuesPerso.tenues
TenuesPerso.tenues = { sauveTenues[1] }
imprime = {}
Tenues_ModePeche(true)
Tenues_ModePeche(false)
avancer()
verifie("mode pêche : sans tenue Pêche, aucun appel", 0, #JEU.appels)
verifie("mode pêche : sans tenue Pêche, aucun message", "", lireImprime())
TenuesPerso.tenues = sauveTenues
-- Le mode pêche coupé en combat : le retour attend la fin du combat.
Tenues_ModePeche(true)
avancer()
enCombat = true
JEU.appels = {}
Tenues_ModePeche(false)
avancer()
verifie("mode pêche coupé en combat : aucun appel", 0, #JEU.appels)
enCombat = false
declencher("PLAYER_REGEN_ENABLED")
avancer()
verifie("mode pêche coupé en combat : retour à la fin du combat", "1=1001 5=1002 8=1006 11=2001 12=2002 16=1003 17=1005", porteLiens())
-- Le mode pêche coupé avant que la tenue Pêche ait pu se mettre (combat) : elle est annulée.
enCombat = true
JEU.appels = {}
Tenues_ModePeche(true)
Tenues_ModePeche(false)
enCombat = false
declencher("PLAYER_REGEN_ENABLED")
avancer()
verifie("mode pêche annulé avant la fin du combat : rien n'est mis", 0, #JEU.appels)

-- Les touches.
JEU.appels = {}
Tenues_Touche(2)
avancer()
verifie("touche 2 : met la deuxième tenue (Pêche)", 3001, n.numeroObjet(JEU.porte[16]))
Tenues_Touche(1)
avancer()
verifie("touche 1 : met la première tenue (Combat)", 1003, n.numeroObjet(JEU.porte[16]))
imprime = {}
Tenues_Touche(5)
verifie("touche 5 sans tenue : message", true, lireImprime():find("aucune tenue n° 5", 1, true) ~= nil)
-- Choisir une touche dans les réglages (onglet Touches).
local bChoisir = boutonTexte("Choisir la touche", 1)
verifie("touches : bouton « Choisir la touche »", true, bChoisir ~= nil)
bChoisir._scripts.OnClick()
local capture
for _, f in ipairs(toutes) do if rawget(f, "numero") ~= nil and f._scripts.OnKeyDown then capture = f end end
verifie("touches : la capture s'affiche", true, capture and capture._shown)
capture._scripts.OnKeyDown(capture, "LSHIFT")
verifie("touches : une touche de modification est ignorée", true, capture._shown)
capture._scripts.OnKeyDown(capture, "F5")
verifie("touches : F5 liée à la tenue 1", "F5", JEU.touches.TENUES_TENUE1)
verifie("touches : liaisons enregistrées", true, JEU.enregistrees >= 1)
verifie("touches : capture fermée", false, capture._shown)
boutonTexte("Choisir la touche", 2)._scripts.OnClick()
capture._scripts.OnKeyDown(capture, "ESCAPE")
verifie("touches : Échap n'enregistre rien", nil, JEU.touches.TENUES_TENUE2)
boutonTexte("Choisir la touche", 2)._scripts.OnClick()
capture._scripts.OnKeyDown(capture, "F6")
verifie("touches : F6 liée à la tenue 2", "F6", JEU.touches.TENUES_TENUE2)
boutonTexte("Choisir la touche", 2)._scripts.OnClick()
capture._scripts.OnKeyDown(capture, "F7")
verifie("touches : une nouvelle touche remplace l'ancienne", "F7", JEU.touches.TENUES_TENUE2)
boutonTexte("Effacer", 2)._scripts.OnClick()
verifie("touches : Effacer retire la touche", nil, JEU.touches.TENUES_TENUE2)
enCombat = true
boutonTexte("Choisir la touche", 3)._scripts.OnClick()
verifie("touches : pas de choix en combat", false, capture._shown)
enCombat = false
-- Le combat qui commence ferme la capture (sinon son cadre plein écran avalerait les touches).
boutonTexte("Choisir la touche", 3)._scripts.OnClick()
verifie("touches : la capture est ouverte avant le combat", true, capture._shown)
declencher("PLAYER_REGEN_DISABLED")
verifie("touches : le combat ferme la capture", false, capture._shown)
-- L'onglet Touches suit la liste : une tenue enregistrée apparaît tout de suite à son numéro.
do
  local nbAvant = #TenuesPerso.tenues
  JEU.porte[1] = JEU.porte[1] or CASQUE
  tenueFn("enregistrer ZetaTest")
  local vu = false
  for _, f in ipairs(toutes) do
    if f._type == "FontString" and f._text:find("^Tenue " .. (nbAvant + 1) .. " %(ZetaTest%)") then vu = true end
  end
  verifie("touches : l'onglet montre la tenue tout juste enregistrée", true, vu)
  for i, t in ipairs(TenuesPerso.tenues) do if t.nom == "ZetaTest" then table.remove(TenuesPerso.tenues, i) break end end
end
-- La ligne de la fenêtre rappelle la touche.
fenetre._scripts.OnShow(fenetre)
verifie("fenêtre : la ligne rappelle sa touche", "7 pièces  |cffffd200[<F5>]|r", lignesVisibles()[1].info._text)

-- Les boutons de la fenêtre.
JEU.appels = {}
lignesVisibles()[2].bMettre._scripts.OnClick()
avancer()
verifie("fenêtre : « Mettre » met la tenue", 3001, n.numeroObjet(JEU.porte[16]))
lignesVisibles()[1].bMettre._scripts.OnClick()
avancer()
verifie("fenêtre : « Mettre » sur Combat", 1003, n.numeroObjet(JEU.porte[16]))

-- Beaucoup de tenues : la fenêtre défile.
for k = 1, 8 do tenueFn("enregistrer Tenue " .. k) end
verifie("défilement : dix tenues", 10, #TenuesPerso.tenues)
fenetre._scripts.OnShow(fenetre)
verifie("défilement : sept lignes visibles", 7, #lignesVisibles())
fenetre._scripts.OnMouseWheel(fenetre, -1)
verifie("défilement : la molette descend d'une tenue", "Pêche", lignesVisibles()[1].nom._text)
fenetre._scripts.OnMouseWheel(fenetre, -10)
verifie("défilement : jamais plus loin que la dernière", "Tenue 2", lignesVisibles()[1].nom._text:gsub(" |c.-|r", ""))
fenetre._scripts.OnMouseWheel(fenetre, 20)
verifie("défilement : retour en haut", "Combat |cff40e040(portée)|r", lignesVisibles()[1].nom._text)
-- On retire les tenues en trop.
TenuesPerso.tenues = { TenuesPerso.tenues[1], TenuesPerso.tenues[2] }
fenetre._scripts.OnShow(fenetre)

-- La position de la fenêtre est retenue.
fenetre:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 120, -80)
fenetre._scripts.OnDragStop(fenetre)
verifie("position : retenue dans les réglages", "TOPLEFT,120,-80", TenuesDB.position and (TenuesDB.position[1] .. "," .. TenuesDB.position[3] .. "," .. TenuesDB.position[4]))
-- Fermer, rouvrir.
tenueFn("")
verifie("fenêtre : /tenue la ferme quand elle est ouverte", false, fenetre._shown)
tenueFn("")
verifie("fenêtre : /tenue la rouvre", true, fenetre._shown)
tenueFn("options")
verifie("/tenue options : pas d'erreur", nil, n.derniereErreur)
tenueFn("aide")
verifie("/tenue aide : la liste des commandes", true, lireImprime():find("/tenue retour", 1, true) ~= nil)

-- Réglages.
reglages.changer("actif", false)
JEU.appels = {}
imprime = {}
verifie("addon coupé : Tenues_Mettre refuse", false, Tenues_Mettre("Pêche"))
verifie("addon coupé : aucun appel", 0, #JEU.appels)
verifie("addon coupé : message", true, lireImprime():find("coupé", 1, true) ~= nil)
Tenues_ModePeche(true)
avancer()
verifie("addon coupé : le mode pêche ne fait rien", 0, #JEU.appels)
reglages.changer("actif", true)
verifie("addon rallumé : la tenue se met", true, Tenues_Mettre("Pêche"))
avancer()
Tenues_Mettre("Combat")
avancer()
verifie("aucune erreur retenue pendant tout le scénario", nil, n.derniereErreur)

-- Rechargement : les tenues et la précédente sont relues de la sauvegarde.
local persoAvant, dbAvant = TenuesPerso, TenuesDB
installer()
_G.TenuesDB, _G.TenuesPerso = dbAvant, persoAvant
local n2 = demarrer()
verifie("rechargement : les tenues sont relues", 2, #TenuesPerso.tenues)
verifie("rechargement : la précédente est relue", true, type(TenuesPerso.precedente) == "table")
verifie("rechargement : la position est relue", "TOPLEFT", TenuesDB.position and TenuesDB.position[1])
etatDepart()
verifie("rechargement : Tenues_Mettre fonctionne", true, Tenues_Mettre("Pêche"))
avancer()
verifie("rechargement : la tenue est mise", 3001, n2.numeroObjet(JEU.porte[16]))
-- Une sauvegarde abîmée est nettoyée.
installer()
_G.TenuesPerso = { tenues = { { nom = "Bonne", pieces = { [1] = CASQUE } }, "n'importe quoi", { nom = 5 } }, precedente = "texte" }
demarrer()
verifie("sauvegarde abîmée : seule la bonne tenue reste", 1, #TenuesPerso.tenues)
verifie("sauvegarde abîmée : précédente invalide effacée", nil, TenuesPerso.precedente)

-- Une valeur secrète du jeu n'est jamais comparée : l'emplacement est traité comme vide.
installer()
demarrer()
etatDepart()
JEU.secret[3] = { secret = true }
local okSecret = pcall(tenueFn, "enregistrer Secret")
verifie("valeur secrète : aucune erreur", true, okSecret)
verifie("valeur secrète : l'emplacement secret n'est pas enregistré", nil, TenuesPerso.tenues[1] and TenuesPerso.tenues[1].pieces[3])

-- ------------------------------------------------------------ les API absentes
-- Le même petit scénario, avec une API en moins à chaque fois : aucune erreur Lua ne doit sortir.
local function scenarioBref(nn)
  etatDepart()
  SlashCmdList.TENUES("enregistrer Combat")
  SlashCmdList.TENUES("")
  JEU.porte[1], JEU.porte[8], JEU.porte[16], JEU.porte[17] = CHAPEAU, BOTTES_P, CANNE, nil
  local cochesBrefs = casesUI()
  if #cochesBrefs > 0 then
    boutonTexte("Tout décocher")._scripts.OnClick()
    for _, s in ipairs({ 1, 8, 16 }) do cochesBrefs[s]._scripts.OnClick(cochesBrefs[s]) end
    local c = champNom()
    if c then c:SetText("Pêche") end
    boutonTexte("Enregistrer ce que je porte")._scripts.OnClick()
  end
  etatDepart()
  avancer()
  Tenues_Mettre("Pêche")
  avancer()
  Tenues_Precedente()
  avancer()
  Tenues_ModePeche(true)
  avancer()
  Tenues_ModePeche(false)
  avancer()
  Tenues_Touche(1)
  avancer()
  SlashCmdList.TENUES("liste")
  SlashCmdList.TENUES("")
  SlashCmdList.TENUES("")
  declencher("PLAYER_EQUIPMENT_CHANGED")
  declencher("BAG_UPDATE_DELAYED")
  avancer()
  local b = boutonTexte("Choisir la touche", 1)
  if b then
    b._scripts.OnClick()
    for _, f in ipairs(toutes) do
      if rawget(f, "numero") ~= nil and f._scripts.OnKeyDown then f._scripts.OnKeyDown(f, "F9") end
    end
    boutonTexte("Effacer", 1)._scripts.OnClick()
  end
  local lg = lignesVisibles()[1]
  if lg then
    lg.bMaj._scripts.OnClick(); lg.bMaj._scripts.OnClick()
    lg.bSupprimer._scripts.OnClick(); lg.bSupprimer._scripts.OnClick()
  end
end

local sansAPI = {
  { "C_Item.EquipItemByName" }, { "C_Item.EquipItemByName", "EquipItemByName" },
  { "C_Item.EquipItemByName", "EquipItemByName", "EquipCursorItem" },
  { "C_Item.EquipItemByName", "EquipItemByName", "C_Container.PickupContainerItem" },
  { "C_Item.EquipItemByName", "EquipItemByName", "EquipCursorItem", "PickupInventoryItem" },
  { "C_Item" }, { "C_Item.GetItemInfoInstant" }, { "GetInventoryItemLink" }, { "C_Container" },
  { "C_Container.GetContainerNumSlots" }, { "C_Container.GetContainerItemLink" }, { "C_Container.GetContainerItemInfo" },
  { "C_Container.GetContainerItemLink", "C_Container.GetContainerItemInfo" },
  { "GetCursorInfo" }, { "UnitIsDeadOrGhost" }, { "InCombatLockdown" }, { "issecretvalue" }, { "GetBindingKey" },
  { "SetBinding" }, { "SaveBindings" }, { "GetCurrentBindingSet" }, { "GetBindingText" }, { "C_Timer" },
  { "NUM_BAG_SLOTS" }, { "ClearCursor" }, { "IsShiftKeyDown", "IsControlKeyDown", "IsAltKeyDown" },
}
local equipesSans = {}
for _, retirer in ipairs(sansAPI) do
  local libelle = table.concat(retirer, " + ")
  installer(retirer)
  local okC, nn = pcall(demarrer)
  local errC = nn
  verifie("sans " .. libelle .. " : chargement sans erreur", true, okC)
  if not okC then io.write("   " .. tostring(errC) .. "\n") else
    local okS, errS = pcall(scenarioBref, nn)
    verifie("sans " .. libelle .. " : scénario sans erreur", true, okS)
    if not okS then io.write("   " .. tostring(errS) .. "\n") end
    verifie("sans " .. libelle .. " : aucune erreur retenue", nil, nn.derniereErreur)
    if nn.derniereErreur then io.write("   " .. nn.derniereErreur .. "\n") end
  end
end

-- Les replis d'équipement : la tenue se met quand même par un autre chemin.
local function misEnPlace(retirer)
  installer(retirer)
  local nn = demarrer()
  etatDepart()
  SlashCmdList.TENUES("enregistrer Combat")
  JEU.porte[1], JEU.porte[8], JEU.porte[16], JEU.porte[17] = CHAPEAU, BOTTES_P, CANNE, nil
  local pieces = { [1] = CHAPEAU, [8] = BOTTES_P, [16] = CANNE }
  TenuesPerso.tenues[#TenuesPerso.tenues + 1] = { nom = "Pêche", pieces = pieces }
  etatDepart()
  JEU.appels = {}
  Tenues_Mettre("Pêche")
  avancer()
  return nn
end
misEnPlace({ "C_Item.EquipItemByName" })
verifie("repli : sans C_Item.EquipItemByName, l'ancien EquipItemByName", "global", JEU.appels[1] and JEU.appels[1].via)
verifie("repli : la tenue est mise", 3001, n.numeroObjet(JEU.porte[16]))
misEnPlace({ "C_Item.EquipItemByName", "EquipItemByName" })
verifie("repli : sans les deux, EquipCursorItem", "curseur", JEU.appels[1] and JEU.appels[1].via)
verifie("repli : la tenue est mise (curseur)", "1=3002 5=1002 8=3003 11=2001 12=2002 16=3001", porteLiens())
misEnPlace({ "C_Item.EquipItemByName", "EquipItemByName", "EquipCursorItem" })
verifie("repli : sans EquipCursorItem, PickupInventoryItem", "inventaire", JEU.appels[1] and JEU.appels[1].via)
verifie("repli : la tenue est mise (inventaire)", "1=3002 5=1002 8=3003 11=2001 12=2002 16=3001", porteLiens())
misEnPlace({ "C_Item.EquipItemByName", "EquipItemByName", "C_Container.PickupContainerItem" })
verifie("sans aucun moyen d'équiper : rien ne bouge", "1=1001 5=1002 8=1006 11=2001 12=2002 16=1003 17=1005", porteLiens())
verifie("sans aucun moyen d'équiper : le curseur reste vide", nil, JEU.curseur)

-- ------------------------------------------------------------ correctifs de la relecture
-- Deux anneaux : la pièce voulue en 12 et portée en 11 reste en place, A prend la place de C.
installer()
demarrer()
etatDepart()
TenuesPerso.tenues = { { nom = "Bagues", pieces = { [11] = BAGUE_A, [12] = BAGUE_B } } }
JEU.porte = { [11] = BAGUE_B, [12] = BAGUE_C }
JEU.sacs = { [0] = { [3] = BAGUE_A }, [1] = {}, [2] = {}, [3] = {}, [4] = {} }
JEU.appels = {}
imprime = {}
Tenues_Mettre("Bagues")
avancer()
verifie("anneaux en jeu : A sur l'emplacement 12, B reste en 11", "11=2002 12=2001", porteLiens())
verifie("anneaux en jeu : un seul appel, sur l'emplacement 12", "12", ordreDesAppels())
verifie("anneaux en jeu : le message dit que la tenue est mise", true, lireImprime():find("mise.", 1, true) ~= nil)
verifie("anneaux en jeu : « retour » remet C et laisse B", "nil,2003", tostring(TenuesPerso.precedente[11]) .. "," .. ns.numeroObjet(TenuesPerso.precedente[12]))
Tenues_Precedente()
avancer()
verifie("anneaux en jeu : le retour remet C en 12", "11=2002 12=2003", porteLiens())

-- Les deux armes à l'envers : le message le dit, il ne prétend ni « manque » ni « déjà portée ».
installer()
demarrer()
etatDepart()
TenuesPerso.tenues = { { nom = "Armes", pieces = { [16] = EPEE, [17] = EPEE2 } } }
JEU.porte = { [16] = EPEE2, [17] = EPEE }
JEU.sacs = { [0] = {}, [1] = {}, [2] = {}, [3] = {}, [4] = {} }
JEU.appels = {}
imprime = {}
Tenues_Mettre("Armes")
avancer()
verifie("mains échangées en jeu : aucun appel", 0, #JEU.appels)
verifie("mains échangées en jeu : pas de faux « il manque »", false, lireImprime():find("il manque", 1, true) ~= nil)
verifie("mains échangées en jeu : pas de faux « déjà portée »", false, lireImprime():find("déjà portée", 1, true) ~= nil)
verifie("mains échangées en jeu : le message le dit", true, lireImprime():find("l'autre main", 1, true) ~= nil)

-- Le mode pêche qui démarre en plein canal attend la fin du canal.
installer()
demarrer()
etatDepart()
TenuesPerso.tenues = { { nom = "Pêche", pieces = { [1] = CHAPEAU, [8] = BOTTES_P, [16] = CANNE } } }
_G.UnitChannelInfo = function() return JEU.canal end
JEU.canal = "Pêche"
JEU.appels = {}
Tenues_ModePeche(true)
avancer()
verifie("mode pêche en plein canal : aucun changement d'équipement", 0, #JEU.appels)
declencher("UNIT_SPELLCAST_CHANNEL_STOP", "target")
avancer()
verifie("canal d'une autre unité : rien ne change", 0, #JEU.appels)
JEU.canal = nil
declencher("UNIT_SPELLCAST_CHANNEL_STOP", "player")
avancer()
verifie("fin du canal : la tenue Pêche se met", 3001, ns.numeroObjet(JEU.porte[16]))
-- Le mode pêche coupé pendant l'attente : rien ne se met ensuite.
etatDepart()
JEU.canal = "Pêche"
Tenues_ModePeche(true)
Tenues_ModePeche(false)
JEU.canal = nil
JEU.appels = {}
declencher("UNIT_SPELLCAST_CHANNEL_STOP", "player")
avancer()
verifie("mode pêche coupé pendant le canal : la tenue ne se met pas", 0, #JEU.appels)
-- Sans UnitChannelInfo : la tenue se met tout de suite, sans erreur.
_G.UnitChannelInfo = nil
etatDepart()
Tenues_ModePeche(true)
avancer()
verifie("sans UnitChannelInfo : la tenue Pêche se met", 3001, ns.numeroObjet(JEU.porte[16]))

print = io.write and function(...) io.write(table.concat({ ... }, " "), "\n") end or print
io.write(string.format("%d vérifications OK\n", nbOK))
if ok then io.write("Tout est bon.\n") end
os.exit(ok and 0 or 1)
