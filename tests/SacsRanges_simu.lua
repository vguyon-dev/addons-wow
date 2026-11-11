-- Simulation hors jeu de Sacs rangés : équipement en double et moins bon.
-- Lancer depuis Windows :
--   wsl lua5.1 tests/SacsRanges_simu.lua SacsRanges/SacsRanges.lua
local bidon
bidon = function()
  return setmetatable({}, { __index = function() return bidon() end, __call = function() return bidon() end })
end
function CreateFrame() return bidon() end
UIParent, SlashCmdList, UISpecialFrames, Minimap = {}, {}, {}, bidon()
tinsert = table.insert

local ns = {}
local reglagesLua = arg[1]:gsub("[^/]+$", "Reglages.lua")
assert(loadfile(reglagesLua))("SacsRanges", ns)
assert(loadfile(arg[1]))("SacsRanges", ns)
assert(loadfile((arg[1]:gsub("[^/]+$", "Conseils.lua"))))("SacsRanges", ns)
assert(loadfile((arg[1]:gsub("[^/]+$", "Vue.lua"))))("SacsRanges", ns)

local ok = true
local function verifie(libelle, attendu, obtenu)
  local bon = attendu == obtenu
  ok = ok and bon
  io.write(string.format("%s %-50s attendu %s, obtenu %s\n", bon and "OK " or "KO ", libelle, tostring(attendu), tostring(obtenu)))
end

local function lire(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end
verifie("Reglages.lua identique dans QuetesAuto", true,
  lire(reglagesLua) == lire((reglagesLua:gsub("SacsRanges/Reglages", "QuetesAuto/Reglages"))))

local porte = { [1] = 200, [11] = 210, [12] = 190, [16] = 220 }
local objets = {
  { id = 1, lien = "Casque", niveau = 180, type = "INVTYPE_HEAD" },     -- moins bon (200)
  { id = 2, lien = "Bague", niveau = 195, type = "INVTYPE_FINGER" },    -- mieux que la bague à 190
  { id = 3, lien = "Bague faible", niveau = 150, type = "INVTYPE_FINGER" },
  { id = 3, lien = "Bague faible", niveau = 150, type = "INVTYPE_FINGER" }, -- en double
  { id = 4, lien = "Potion", niveau = 1, type = "INVTYPE_NON_EQUIP_IGNORE" }, -- pas de l'équipement
  { id = 4, lien = "Potion", niveau = 1, type = "INVTYPE_NON_EQUIP_IGNORE" },
  { id = 5, lien = "Cape", niveau = 100, type = "INVTYPE_CLOAK" },      -- rien porté au dos : on ne juge pas
}
local doublons, moinsBons = ns.analyser(objets, porte)
verifie("doublons : seulement l'équipement", 1, #doublons)
verifie("doublons : la bague faible ×2", 2, doublons[1] and doublons[1].nombre)
verifie("moins bons : casque, bague faible ×2", 3, #moinsBons)
verifie("moins bons : le plus faible d'abord", 150, moinsBons[1] and moinsBons[1].niveau)
verifie("bague comparée à la plus faible portée", 190, moinsBons[1] and moinsBons[1].porte)
local _, avecEcart = ns.analyser(objets, porte, 25)
verifie("écart de 25 niveaux : seule la bague faible", 2, #avecEcart)

-- Équipement que le personnage ne peut pas porter : sa propre liste, même s'il est meilleur.
local mailles = { { id = 6, lien = "Cotte de mailles", niveau = 250, type = "INVTYPE_CHEST", utilisable = false },
  { id = 7, lien = "Casque de cuir", niveau = 150, type = "INVTYPE_HEAD", utilisable = true } }
local _, mb, inut = ns.analyser(mailles, porte)
verifie("inutilisable : listé à part", 1, #inut)
verifie("inutilisable : c'est la cotte de mailles", "Cotte de mailles", inut[1] and inut[1].lien)
verifie("inutilisable : pas aussi dans « moins bon »", 1, #mb)

local C = ns.COMPETENCES
local chasseur20 = function(s) return s == C[4][1] or s == C[4][2] or s == C[2][2] end
verifie("chasseur niveau 20 : mailles, non", false, ns.utilisable(4, 3, chasseur20))
verifie("chasseur : épée pas apprise, non", false, ns.utilisable(2, 7, chasseur20))
verifie("chasseur : arc appris, oui", true, ns.utilisable(2, 2, chasseur20))
verifie("ligne rouge dans la bulle : non", false, ns.utilisable(4, 0, chasseur20, true))

-- La table des compétences doit rester la même que celle de QuetesAuto.
local qa = {}
local bidonQA
bidonQA = function()
  return setmetatable({}, { __index = function() return bidonQA() end, __call = function() return bidonQA() end })
end
local quetes = (reglagesLua:gsub("SacsRanges/Reglages.lua", "QuetesAuto/"))
assert(loadfile(quetes .. "Reglages.lua"))("QuetesAuto", qa)
assert(loadfile(quetes .. "QuetesAuto.lua"))("QuetesAuto", qa)
local pareil = true
for classe, t in pairs(C) do
  for sc, sort in pairs(t) do if qa.COMPETENCES[classe][sc] ~= sort then pareil = false end end
end
for classe, t in pairs(qa.COMPETENCES) do
  for sc, sort in pairs(t) do if C[classe][sc] ~= sort then pareil = false end end
end
verifie("compétences identiques à QuetesAuto", true, pareil)
-- Vue par catégories : la section de chaque objet.
verifie("catégorie : arme portable", "equip", ns.categorie(2, 2, false, true))
verifie("arme pas apprise, pas liée : Tu ne peux pas le porter", "pasPourToi", ns.categorie(2, 1, false, false))
verifie("arme pas apprise et liée : reste dans Tu ne peux pas le porter (ça s'apprend)", "pasPourToi",
  ns.categorie(2, 1, false, false, 0, 1, { estLie = true, raison = "autre" }))
verifie("impossible pour toujours et liée : À vendre", "vendre", ns.categorie(4, 2, false, false, 0, 1, { estLie = true, raison = "definitif" }))
verifie("impossible pour toujours mais pas liée : Tu ne peux pas le porter", "pasPourToi",
  ns.categorie(4, 2, false, false, 0, 1, { estLie = false, raison = "definitif" }))
verifie("liée mais seulement trop haut en niveau : Tu ne peux pas le porter", "pasPourToi",
  ns.categorie(4, 2, false, false, 0, 1, { estLie = true, raison = "niveau" }))
verifie("raison : niveau seul", "niveau", (ns.raisonPasPortable({ "Niveau 20 requis" })))
verifie("raison : arme pas apprise", "autre", (ns.raisonPasPortable({ "Arc", "Niveau 20 requis" })))
-- Impossible pour toujours : restriction de classe ou de race, type d'armure que la classe ne portera jamais.
verifie("raison : guerrier 30, plaque liée pas apprise", "autre", (ns.raisonPasPortable({ "Plaques" }, 4, 4, "WARRIOR")))
verifie("raison : guerrier 30, plaque, catégorie pasPourToi", "pasPourToi",
  ns.categorie(4, 2, false, false, 0, 1, { estLie = true, raison = (ns.raisonPasPortable({ "Plaques" }, 4, 4, "WARRIOR")) }))
verifie("raison : mage, plaque", "definitif", (ns.raisonPasPortable({ "Plaques" }, 4, 4, "MAGE")))
verifie("raison : mage, plaque, catégorie vendre", "vendre",
  ns.categorie(4, 2, false, false, 0, 1, { estLie = true, raison = (ns.raisonPasPortable({ "Plaques" }, 4, 4, "MAGE")) }))
verifie("raison : mage, plaque sans ligne rouge", "definitif", (ns.raisonPasPortable(nil, 4, 4, "MAGE")))
verifie("raison : chasseur, ligne rouge « Classes : Paladin »", "definitif", (ns.raisonPasPortable({ "Classes : Paladin" }, 2, 7, "HUNTER")))
verifie("raison : ligne rouge « Classes : Paladin », catégorie vendre", "vendre",
  ns.categorie(2, 2, false, false, 7, 1, { estLie = true, raison = (ns.raisonPasPortable({ "Classes : Paladin" }, 2, 7, "HUNTER")) }))
verifie("raison : ligne rouge « Races: Orc »", "definitif", (ns.raisonPasPortable({ "Races: Orc" }, 2, 7, "HUNTER")))
verifie("raison : arc pas appris lié", "autre", (ns.raisonPasPortable({ "Arc" }, 2, 2, "HUNTER")))
verifie("raison : arc pas appris lié, catégorie pasPourToi", "pasPourToi",
  ns.categorie(2, 2, false, false, 2, 1, { estLie = true, raison = (ns.raisonPasPortable({ "Arc" }, 2, 2, "HUNTER")) }))
verifie("raison : niveau trop haut, catégorie pasPourToi", "pasPourToi",
  ns.categorie(4, 2, false, false, 4, 1, { estLie = true, raison = (ns.raisonPasPortable({ "Niveau 60 requis" }, 4, 4, "WARRIOR")) }))
verifie("raison : chasseur, mailles pas encore apprises", "autre", (ns.raisonPasPortable({ "Mailles" }, 4, 3, "HUNTER")))
verifie("raison : voleur, mailles", "definitif", (ns.raisonPasPortable(nil, 4, 3, "ROGUE")))
verifie("raison : classe inconnue, pas de jugement", "autre", (ns.raisonPasPortable(nil, 4, 4, nil)))
verifie("raison : cape de tissu, jamais définitive", "autre", (ns.raisonPasPortable(nil, 4, 1, "WARRIOR")))
-- Le motif vient de la constante du jeu quand elle existe.
ITEM_CLASSES_ALLOWED = "Classes (a-b) : %s"
verifie("restriction : motif de la constante", true, ns.estRestrictionDefinitive("Classes (a-b) : Paladin"))
verifie("restriction : la constante remplace le repli", false, ns.estRestrictionDefinitive("Classes : Paladin"))
ITEM_CLASSES_ALLOWED = nil
verifie("restriction : repli sans constante", true, ns.estRestrictionDefinitive("Classes: Paladin, Chasseur"))
verifie("restriction : autre ligne", false, ns.estRestrictionDefinitive("Arc"))
verifie("restriction : pas un texte", false, ns.estRestrictionDefinitive(nil))
verifie("texte : gris", "objet gris", ns.texteRangement("vendre", 0, false))
verifie("texte : à vendre, jamais portable", "lié, et tu ne pourras jamais le porter (Classes : Paladin)",
  ns.texteRangement("vendre", 3, true, "Classes : Paladin"))
verifie("texte : lié, il pourra se porter plus tard", true,
  (ns.texteRangement("pasPourToi", 2, true, "Arc") or ""):find("plus tard", 1, true) ~= nil)
verifie("texte : pas lié, se donne", true,
  (ns.texteRangement("pasPourToi", 2, false, "Arc") or ""):find("tu peux le donner", 1, true) ~= nil)
local milice = { stats = { dps = 2.0 }, type = "INVTYPE_WEAPON", nom = "Dague de la milice" }
verifie("moins bon : la dague usée face à la milice", "Dague de la milice",
  ns.estMoinsBon({ stats = { dps = 0.9 }, type = "INVTYPE_WEAPON" }, { [16] = milice }, "agilite", false, false))
verifie("emplacement vide : jamais « moins bon »", nil, ns.estMoinsBon({ stats = { agilite = 1 }, type = "INVTYPE_HAND" }, {}, "agilite"))
verifie("meilleur : pas « moins bon »", nil,
  ns.estMoinsBon({ stats = { dps = 3 }, type = "INVTYPE_WEAPON" }, { [16] = milice }, "agilite", false, false))
verifie("catégorie : gris, à vendre", "vendre", ns.categorie(15, 0, false, true))
verifie("catégorie : objet de quête gris reste en Quête", "quete", ns.categorie(15, 0, true, true))
verifie("catégorie : classe quête", "quete", ns.categorie(12, 1, false, true))
verifie("catégorie : potion", "conso", ns.categorie(0, 1, false, true))
verifie("catégorie : étoffe", "compo", ns.categorie(7, 1, false, true))
verifie("catégorie : inconnue (pas encore lue)", "divers", ns.categorie(nil, 1, false, true))
local parts = ns.repartir({
  { sac = 0, case = 3, categorie = "compo", nom = "Pierre brute", qualite = 1 },
  { sac = 0, case = 1, categorie = "compo", nom = "Étoffe de lin", qualite = 1 },
  { sac = 1, case = 2, categorie = "compo", nom = "Cristal", qualite = 3 },
  { sac = 0, case = 2, categorie = "rien", nom = "Truc", qualite = 1 },
})
verifie("répartition : meilleure qualité d'abord", "Cristal", parts.compo[1].nom)
verifie("répartition : catégorie inconnue en Divers", 1, #parts.divers)
verifie("répartition : 3 composants", 3, #parts.compo)
verifie("recherche sans accents", true, ns.simplifier("Étoffe de LIN"):find("etoffe", 1, true) ~= nil)
verifie("recherche : œ", "oeil de murloc", ns.simplifier("Œil de murloc"))

-- Objets conseillés à équiper (Conseils.lua)
local milice = { stats = { dps = 2.0 }, type = "INVTYPE_WEAPON", nom = "Dague de la milice" }
local usee = { stats = { dps = 0.9 }, type = "INVTYPE_WEAPON" }
verifie("dague usée moins bonne que la milice : pas de conseil", nil, ns.comparer(usee, { [16] = milice }, "agilite", false, false))
local gants = ns.comparer({ stats = { agilite = 2, endurance = 1 }, type = "INVTYPE_HAND" }, {}, "agilite")
verifie("gants sur un emplacement vide", "emplacement vide", gants and gants.raison)
local arc = ns.comparer({ stats = { dps = 3.0 }, type = "INVTYPE_RANGEDRIGHT" },
  { [16] = { stats = { dps = 1.8 }, type = "INVTYPE_RANGEDRIGHT", nom = "Arc usé" } }, "agilite", false)
verifie("arc meilleur : la raison", "+1,2 dégâts par seconde", arc and arc.raison)
verifie("arc meilleur : ce qu'il remplace", "Arc usé", arc and arc.remplace)
local bague = ns.comparer({ stats = { agilite = 3 }, type = "INVTYPE_FINGER" },
  { [11] = { stats = { agilite = 5 }, nom = "Forte" }, [12] = { stats = { agilite = 1 }, nom = "Faible" } }, "agilite")
verifie("bague : remplace la plus faible", "Faible", bague and bague.remplace)
verifie("bague : la raison", "+2 Agilité", bague and bague.raison)
local deuxMains = { stats = { dps = 4, force = 2 }, type = "INVTYPE_2HWEAPON", nom = "Grande hache" }
verifie("main gauche vide sous une arme à deux mains : pas un trou", nil,
  ns.comparer({ stats = { force = 1 }, type = "INVTYPE_SHIELD" }, { [16] = deuxMains }, "force"))
local hache = ns.comparer({ stats = { dps = 5, force = 3 }, type = "INVTYPE_2HWEAPON" },
  { [16] = { stats = { dps = 2 }, type = "INVTYPE_WEAPON" }, [17] = { stats = { force = 1 }, type = "INVTYPE_SHIELD" } }, "force")
verifie("deux mains mieux que arme + bouclier", true, hache ~= nil)
verifie("lanceur : les dégâts de l'arme comptent peu", nil,
  ns.comparer({ stats = { dps = 3 }, type = "INVTYPE_WEAPON" }, { [16] = { stats = { dps = 1, intelligence = 2 } } }, "intelligence"))
verifie("sans ambidextrie : pas de conseil pour la main gauche vide", nil,
  ns.comparer({ stats = { dps = 1 }, type = "INVTYPE_WEAPON" }, { [16] = milice }, "agilite", false, false))
verifie("ambidextre : main gauche vide conseillée", "emplacement vide",
  (ns.comparer({ stats = { dps = 1 }, type = "INVTYPE_WEAPON" }, { [16] = milice }, "agilite", false, true) or {}).raison)
local st = ns.lireStats({ ITEM_MOD_AGILITY_SHORT = 2, ITEM_MOD_CRIT_RATING_SHORT = 3, ITEM_MOD_HASTE_RATING_SHORT = 1, BIDON = 9 })
verifie("lecture des caractéristiques", "2/4", st.agilite .. "/" .. st.secondaires)
verifie("sans caractéristiques : le niveau d'objet tranche", true, ns.comparer({ stats = {}, niveau = 12, type = "INVTYPE_CLOAK" },
  { [15] = { stats = {}, niveau = 8, nom = "Cape" } }, "agilite") ~= nil)
-- Outils de métier : leur propre section, jamais comparés comme des armes
verifie("canne à pêche (arme, sous-classe 20) : Métiers", "metier", ns.categorie(2, 1, false, true, 20, 6256))
verifie("couteau à dépecer (arme divers, 14) : Métiers", "metier", ns.categorie(2, 1, false, true, 14, 7005))
verifie("outil de métier Retail (classe 19) : Métiers", "metier", ns.categorie(19, 1, false, true, 0, 1))
verifie("une vraie dague reste de l'équipement", "equip", ns.categorie(2, 2, false, true, 15, 2092))
verifie("un outil d'objet de quête reste en Quête", "quete", ns.categorie(2, 1, true, true, 14, 7005))
-- Livres de bibliothèque et objets liés sans usage d'artisanat
verifie("livre de bibliothèque : Quête (à rendre)", "quete", ns.categorie(15, 3, false, true, 0, 1, { livre = true }))
verifie("objet lié, classe composant, pas d'artisanat : Divers", "divers", ns.categorie(7, 3, false, true, 0, 1, { lie = true, artisanat = false }))
verifie("vrai composant lié (artisanat) : Composants", "compo", ns.categorie(7, 1, false, true, 0, 1, { lie = true, artisanat = true }))
verifie("composant non lié : Composants", "compo", ns.categorie(7, 1, false, true, 0, 1, { lie = false, artisanat = false }))
-- L'habillage commun « sombre et doré » (Reglages.lua)
do
  local s = ns.styleHabillage()
  verifie("habillage par défaut : fond sombre", "0.07/0.06/0.045/0.96", table.concat(s.fond, "/"))
  verifie("habillage par défaut : bordure dorée", "0.8/0.63/0.3/1", table.concat(s.bordure, "/"))
  verifie("habillage par défaut : pas de titre ni de croix", "nil/false/false", tostring(s.titre) .. "/" .. tostring(s.fermer) .. "/" .. tostring(s.trait))
  local t = ns.styleHabillage({ titre = "Bilan", fermer = true })
  verifie("habillage avec titre : titre gardé", "Bilan", t.titre)
  verifie("habillage avec titre : croix demandée", true, t.fermer)
  verifie("habillage avec titre : filet doré par défaut", true, t.trait)
  verifie("habillage : trait = false coupe le filet", false, ns.styleHabillage({ titre = "X", trait = false }).trait)
  verifie("habillage : titre vide = pas de titre", "nil", tostring(ns.styleHabillage({ titre = "" }).titre))
  local c = ns.styleHabillage({ fond = { 0.1, 0.2, 0.3 }, bordure = { 1, 0, 0, 0.5 } })
  verifie("habillage : fond personnalisé, opacité par défaut", "0.1/0.2/0.3/0.96", table.concat(c.fond, "/"))
  verifie("habillage : bordure personnalisée", "1/0/0/0.5", table.concat(c.bordure, "/"))
  verifie("habillage : options absurdes ignorées", "0.07", tostring(ns.styleHabillage({ fond = { "a" } }).fond[1]))
  verifie("habillage : options pas une table", "0.8", tostring(ns.styleHabillage("x").bordure[1]))
end
-- La page « Quoi de neuf » (Reglages.lua)
do
  local liste = {
    { date = "2026-11-10", titre = "Récent", lignes = { "un", "deux" } },
    { date = "2026-11-08", titre = "Ancien", lignes = { "x" } },
  }
  verifie("neuf : la dernière date", "2026-11-10", ns.derniereNouveaute(liste))
  verifie("neuf : liste vide", "nil", tostring(ns.derniereNouveaute({})))
  verifie("neuf : pas une table", "nil", tostring(ns.derniereNouveaute("x")))
  verifie("neuf : date abîmée ignorée", "2026-11-08", ns.derniereNouveaute({ { date = "demain" }, { date = "2026-11-08" }, "x", 3 }))
  verifie("neuf : rien vu, tout est nouveau", true, ns.ilYADuNeuf(liste, nil))
  verifie("neuf : date vue abîmée, tout est nouveau", true, ns.ilYADuNeuf(liste, "hier"))
  verifie("neuf : date vue pas un texte", true, ns.ilYADuNeuf(liste, 20261110))
  verifie("neuf : vue plus ancienne", true, ns.ilYADuNeuf(liste, "2026-11-09"))
  verifie("neuf : vue égale à la dernière", false, ns.ilYADuNeuf(liste, "2026-11-10"))
  verifie("neuf : vue plus récente", false, ns.ilYADuNeuf(liste, "2027-01-01"))
  verifie("neuf : liste vide, rien de nouveau", false, ns.ilYADuNeuf({}, nil))
  verifie("neuf : pas de liste, rien de nouveau", false, ns.ilYADuNeuf(nil, nil))
  verifie("neuf : date lisible", "10/11/2026", ns.dateLisible("2026-11-10"))
  verifie("neuf : date lisible abîmée", "bof", ns.dateLisible("bof"))
  local t = ns.texteNouveautes(liste, nil)
  verifie("neuf : texte, titre et date", true, t:find("Récent|r  |cff888888" .. "10/11/2026", 1, true) ~= nil)
  verifie("neuf : texte, une ligne par puce", true, t:find("\n- un\n- deux", 1, true) ~= nil)
  verifie("neuf : texte, sans date vue tout est marqué nouveau", 2, select(2, t:gsub("%[nouveau%]", "")))
verifie("neuf : texte, date vue abîmée, tout est marqué", 2, select(2, ns.texteNouveautes(liste, "hier"):gsub("%[nouveau%]", "")))
verifie("neuf : plus ancienne date, celle qui existe", "2026-11-05", ns.plusAncienneDate({ "2026-11-09", false, "2026-11-05", "bof" }))
verifie("neuf : plus ancienne date, un addon sans date est ignoré", "2026-11-09", ns.plusAncienneDate({ "2026-11-09", nil }))
verifie("neuf : plus ancienne date, aucune connue", "nil", tostring(ns.plusAncienneDate({ nil, "bof" })))
verifie("neuf : plus ancienne date, pas une table", "nil", tostring(ns.plusAncienneDate(nil)))
  local t2 = ns.texteNouveautes(liste, "2026-11-09")
  verifie("neuf : texte, marqué seulement ce qui est récent", 1, select(2, t2:gsub("%[nouveau%]", "")))
  verifie("neuf : texte, liste vide", "Rien de nouveau pour l'instant.", ns.texteNouveautes({}, nil))
  verifie("neuf : texte, entrée sans date sautée", "Rien de nouveau pour l'instant.", ns.texteNouveautes({ { titre = "x" } }, nil))
  -- La vraie liste du dépôt : bien formée, les plus récentes d'abord, sans tiret cadratin.
  local bien, ordre, tirets = true, true, false
  local precedente = "9999-99-99"
  for _, n in ipairs(ns.NOUVEAUTES) do
    if type(n.date) ~= "string" or not n.date:match("^%d%d%d%d%-%d%d%-%d%d$") or type(n.titre) ~= "string"
      or type(n.lignes) ~= "table" or #n.lignes == 0 then bien = false end
    if n.date > precedente then ordre = false end
    precedente = n.date
    local tout = n.titre .. table.concat(n.lignes)
    -- tiret cadratin et demi-cadratin, écrits en octets pour ne pas les mettre dans ce fichier
    if tout:find("\226\128\148", 1, true) or tout:find("\226\128\147", 1, true) then tirets = true end
  end
  verifie("neuf : la liste du dépôt est bien formée", true, bien and #ns.NOUVEAUTES > 0)
  verifie("neuf : la liste du dépôt va du plus récent au plus ancien", true, ordre)
  verifie("neuf : pas de tiret cadratin dans la liste", false, tirets)
end
-- Le chargement d'un addon dans la fenêtre commune : un seul message « il y a du nouveau »
-- pour plusieurs addons, la date vue retenue dans chaque sauvegarde.
do
  local ecouteurs = {}
  local vrai = CreateFrame
  CreateFrame = function()
    local f = bidon()
    local scripts = {}
    rawset(f, "SetScript", function(_, nom, fn) scripts[nom] = fn end)
    rawset(f, "RegisterEvent", function(self, ev) if ev == "ADDON_LOADED" then ecouteurs[#ecouteurs + 1] = scripts end end)
    rawset(f, "UnregisterEvent", function() end)
    return f
  end
  local dits = {}
  local vraiPrint = print
  print = function(...) dits[#dits + 1] = table.concat({ ... }, " ") end
  _G.ValentinAddons.messageNouveau = nil
  local function creer(nomAddon, nomDB)
    local nsX = {}
    assert(loadfile(reglagesLua))(nomAddon, nsX)
    nsX.creerReglages({ titre = nomAddon, icone = "x", nomDB = nomDB, defauts = { actif = true },
      options = { { cle = "actif", libelle = "Activer" } } })
  end
  creer("FauxA", "FauxADB")
  creer("FauxB", "FauxBDB")
  _G.FauxADB = nil
  _G.FauxBDB = { nouveautesVues = "2026-11-08" }
  for i, scripts in ipairs(ecouteurs) do scripts.OnEvent({ UnregisterEvent = function() end }, "ADDON_LOADED", i == 1 and "FauxA" or "FauxB") end
  print = vraiPrint
  CreateFrame = vrai
  local hub = _G.ValentinAddons
  verifie("chargement : un seul message pour deux addons", 1, #dits)
  verifie("chargement : le message parle de « Quoi de neuf »", true, (dits[1] or ""):find("Quoi de neuf", 1, true) ~= nil)
  verifie("chargement : le drapeau est dans le hub commun", true, hub.messageNouveau)
  verifie("chargement : il y a du nouveau", true, hub.aDuNeuf())
  hub.marquerVu()
  verifie("page ouverte : la date vue est gardée (addon A)", ns.derniereNouveaute(ns.NOUVEAUTES), _G.FauxADB.nouveautesVues)
  verifie("page ouverte : la date vue est gardée (addon B)", ns.derniereNouveaute(ns.NOUVEAUTES), _G.FauxBDB.nouveautesVues)
  verifie("page ouverte : plus rien de nouveau", false, hub.aDuNeuf())
  -- On retire nos deux faux addons du hub pour ne rien laisser aux autres tests.
  for i = #hub.entrees, 1, -1 do
    local t = hub.entrees[i].titre
    if t == "FauxA" or t == "FauxB" then table.remove(hub.entrees, i) end
  end
  hub.messageNouveau = nil
end
-- Les réglages propres à chaque personnage (Reglages.lua)
do
  local cles = { "actif", "taille", "son" }
  local defauts = { actif = true, taille = 100, son = true }
  local function fmt(t) return tostring(t.actif) .. "/" .. tostring(t.taille) .. "/" .. tostring(t.son) end
  local function combien(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
  verifie("profils : clés déclarées, sans titre ni doublon", "actif,taille,son",
    table.concat(ns.clesReglages({ { titre = "S" }, { cle = "actif" }, { cle = "taille", type = "nombre" }, { cle = "son" }, { cle = "son" }, 5, { cle = 3 }, { cle = "" } }), ","))
  verifie("profils : options absentes", 0, #ns.clesReglages(nil))
  local copie = ns.copierReglages({ a = true, b = 3, c = { 1 }, d = "x", e = 0 / 0, f = 1 / 0, g = false }, { "a", "b", "c", "d", "e", "f", "g", "h" })
  verifie("profils : seules les valeurs simples sont copiées", "a,b,g", (function()
    local l = {} for k in pairs(copie) do l[#l + 1] = k end table.sort(l) return table.concat(l, ",") end)())
  verifie("profils : source absente", 0, combien(ns.copierReglages(nil, { "a" })))
  verifie("profils : nom du personnage", "Aela-Elune", ns.nomProfil("Aela", "Elune"))
  verifie("profils : royaume inconnu", "Aela-", ns.nomProfil("Aela", nil))
  verifie("profils : nom inconnu", "nil", tostring(ns.nomProfil(nil, "Elune")))
  verifie("profils : nom vide", "nil", tostring(ns.nomProfil("", "Elune")))

  -- Premier lancement : le compte reprend les valeurs actuelles, rien ne change.
  local db = { actif = true, taille = 120, son = false, position = { x = 5 }, liste = { 1, 2 } }
  verifie("profils : premier lancement, mode compte", "compte", ns.chargerProfil(db, cles, "A-R", defauts))
  verifie("profils : le compte reprend les valeurs actuelles", "true/120/false", fmt(db.compte))
  verifie("profils : la table de travail ne change pas", "true/120/false", fmt(db))
  verifie("profils : personne n'a de réglages propres", 0, combien(db.parPerso))
  verifie("profils : les positions et les listes ne sont pas touchées", "5/2", db.position.x .. "/" .. #db.liste)
  verifie("profils : ni positions ni listes dans le compte", 3, combien(db.compte))

  -- Le personnage A change un réglage : c'est le compte qui le garde.
  db.taille = 150
  verifie("profils : écriture en mode compte", "compte", ns.ecrireProfil(db, cles, "A-R"))
  verifie("profils : le compte a la nouvelle valeur", 150, db.compte.taille)

  -- A passe en réglages propres : copie des valeurs actuelles, le compte ne bouge plus.
  verifie("profils : activer les réglages propres", "perso", ns.changerMode(db, cles, "A-R", true, defauts))
  verifie("profils : A est en mode perso", true, ns.modePerso(db, "A-R"))
  verifie("profils : copie des valeurs actuelles", "true/150/false", fmt(db.parPerso["A-R"]))
  db.son = true
  verifie("profils : écriture en mode perso", "perso", ns.ecrireProfil(db, cles, "A-R"))
  verifie("profils : le réglage va chez A", true, db.parPerso["A-R"].son)
  verifie("profils : le compte n'a pas bougé", false, db.compte.son)
  verifie("profils : activer deux fois ne perd rien", "true/150/true", (function()
    ns.changerMode(db, cles, "A-R", true, defauts) return fmt(db.parPerso["A-R"]) end)())

  -- B se connecte (mode compte) : il voit le compte, pas les réglages de A.
  verifie("profils : B suit le compte", "compte", ns.chargerProfil(db, cles, "B-R", defauts))
  verifie("profils : B reçoit les valeurs du compte", "true/150/false", fmt(db))
  db.taille = 200
  ns.ecrireProfil(db, cles, "B-R")
  verifie("profils : B change le compte", 200, db.compte.taille)
  verifie("profils : A n'a pas changé", 150, db.parPerso["A-R"].taille)

  -- A revient : il retrouve les siens.
  verifie("profils : A revient en mode perso", "perso", ns.chargerProfil(db, cles, "A-R", defauts))
  verifie("profils : A retrouve ses réglages", "true/150/true", fmt(db))
  verifie("profils : le compte est intact", "true/200/false", fmt(db.compte))
  -- B revient aussi, puis A : les deux alternent sans se mélanger.
  ns.chargerProfil(db, cles, "B-R", defauts)
  verifie("profils : B revient, valeurs du compte", "true/200/false", fmt(db))
  ns.chargerProfil(db, cles, "A-R", defauts)
  verifie("profils : A revient encore", "true/150/true", fmt(db))

  -- A coupe ses réglages propres : ils sont effacés, le compte est rechargé.
  verifie("profils : couper les réglages propres", "compte", ns.changerMode(db, cles, "A-R", false, defauts))
  verifie("profils : plus de réglages propres pour A", false, ns.modePerso(db, "A-R"))
  verifie("profils : la table de travail reçoit le compte", "true/200/false", fmt(db))
  verifie("profils : l'entrée de A est effacée", "nil", tostring(db.parPerso["A-R"]))
  verifie("profils : couper sans en avoir est sans effet", "compte", ns.changerMode(db, cles, "A-R", false, defauts))

  -- Une clé ajoutée plus tard (absente du compte et du profil) : la valeur de départ, sans fuite.
  local cles2 = { "actif", "taille", "son", "nouveau" }
  local defauts2 = { actif = true, taille = 100, son = true, nouveau = 7 }
  ns.changerMode(db, cles2, "A-R", true, defauts2)
  db.nouveau = 9 -- A règle la nouvelle clé dans ses réglages propres
  ns.ecrireProfil(db, cles2, "A-R")
  verifie("profils : clé ajoutée, écrite chez A", 9, db.parPerso["A-R"].nouveau)
  verifie("profils : clé ajoutée, pas dans le compte", "nil", tostring(db.compte.nouveau))
  ns.chargerProfil(db, cles2, "B-R", defauts2)
  verifie("profils : clé ajoutée, B reçoit la valeur de départ (pas celle de A)", 7, db.nouveau)
  ns.chargerProfil(db, cles2, "A-R", defauts2)
  verifie("profils : clé ajoutée, A retrouve la sienne", 9, db.nouveau)
  local dbVieille = { actif = true, taille = 80, son = true }
  ns.chargerProfil(dbVieille, { "actif", "taille", "son" }, "C-R", defauts)
  local dbNouvelleCle = dbVieille
  ns.chargerProfil(dbNouvelleCle, cles2, "C-R", defauts2)
  verifie("profils : clé ajoutée après coup, valeur de départ", 7, dbNouvelleCle.nouveau)
  verifie("profils : clé ajoutée après coup, valeurs anciennes gardées", 80, dbNouvelleCle.taille)
  ns.ecrireProfil(dbNouvelleCle, cles2, "C-R")
  verifie("profils : clé ajoutée après coup, retenue dans le compte", 7, dbNouvelleCle.compte.nouveau)

  -- Personnage encore inconnu (le jeu ne donne pas son nom) : on reste sur le compte.
  local dbX = { actif = true, taille = 90, son = true }
  verifie("profils : sans nom, mode compte", "compte", ns.chargerProfil(dbX, cles, nil, defauts))
  verifie("profils : sans nom, activer ne fait rien", "compte", ns.changerMode(dbX, cles, nil, true, defauts))
  verifie("profils : sans nom, rien n'est écrit pour la session", "nil/nil", tostring(dbX.compte) .. "/" .. tostring(dbX.parPerso))
  verifie("profils : sans nom, la table de travail reste telle quelle", "true/90/true", fmt(dbX))
  verifie("profils : sans nom, écrire ne fait rien", "compte", ns.ecrireProfil(dbX, cles, nil))
  verifie("profils : sans nom, rien n'est écrit dans le compte", "nil", tostring(dbX.compte))
  verifie("profils : sans nom, pas de mode perso", false, ns.modePerso(dbX, nil))

  -- Sauvegarde abîmée : les tables sont refaites, une entrée qui n'est pas une table est ignorée.
  local dbCasse = { actif = true, taille = 70, son = false, compte = "x", parPerso = 5 }
  verifie("profils : sauvegarde abîmée", "compte", ns.chargerProfil(dbCasse, cles, "A-R", defauts))
  verifie("profils : sauvegarde abîmée, compte refait", "true/70/false", fmt(dbCasse.compte))
  dbCasse.parPerso["A-R"] = "n'importe quoi"
  verifie("profils : entrée abîmée ignorée", false, ns.modePerso(dbCasse, "A-R"))
  dbCasse.parPerso["A-R"] = { actif = true, taille = "grand", son = false }
  ns.chargerProfil(dbCasse, cles, "A-R", defauts)
  verifie("profils : valeur abîmée, retour au compte", 70, dbCasse.taille)
  verifie("profils : valeur abîmée, valeur saine gardée", false, dbCasse.son)
end
-- Le texte à partager (Reglages.lua)
do
  local blocs = {
    { nom = "SacsRanges", valeurs = { vueCategories = true, ecart = 3, bavard = false } },
    { nom = "GPS", valeurs = { taille = 160, actif = true, ratio = 0.5, decalage = -4, liste = { 1 }, ["mauvaise cle"] = 1 } },
    { nom = "Vide", valeurs = {} },
    { nom = "Mauvais nom", valeurs = { a = 1 } },
    "pas un bloc",
  }
  local texte = ns.encoderReglages(blocs)
  verifie("partage : texte compact, trié, versionné",
    "VA1;GPS:actif=1,decalage=-4,ratio=0.5,taille=160;SacsRanges:bavard=0,ecart=3,vueCategories=1", texte)
  verifie("partage : rien à partager", "VA1;", ns.encoderReglages({}))
  verifie("partage : liste absente", "VA1;", ns.encoderReglages(nil))
  local recu = ns.decoderReglages(texte)
  verifie("partage : aller-retour, un interrupteur", 1, recu and recu.SacsRanges.vueCategories)
  verifie("partage : aller-retour, un interrupteur coupé", 0, recu and recu.SacsRanges.bavard)
  verifie("partage : aller-retour, un curseur", 160, recu and recu.GPS.taille)
  verifie("partage : aller-retour, un nombre à virgule", 0.5, recu and recu.GPS.ratio)
  verifie("partage : aller-retour, un nombre négatif", -4, recu and recu.GPS.decalage)
  verifie("partage : aller-retour, la liste n'est pas partagée", "nil", tostring(recu and recu.GPS.liste))
  verifie("partage : aller-retour, deux addons seulement", "GPS,SacsRanges", (function()
    local l = {} for k in pairs(recu) do l[#l + 1] = k end table.sort(l) return table.concat(l, ",") end)())
  local coupe = ns.decoderReglages("  VA1;GPS:taille=160,\n actif=1 ;\nSacsRanges:ecart=3  ")
  verifie("partage : espaces et retours à la ligne ignorés", "160/1/3", coupe and (coupe.GPS.taille .. "/" .. coupe.GPS.actif .. "/" .. coupe.SacsRanges.ecart))
  local souple = ns.decoderReglages("VA1;GPS:a=1;;GPS:b=0,,c=2e1;")
  verifie("partage : blocs et paires vides permis, blocs d'un même addon réunis", "1/0/20", souple and (souple.GPS.a .. "/" .. souple.GPS.b .. "/" .. souple.GPS.c))
  local function erreur(t) local r, e = ns.decoderReglages(t) return r == nil and e or "pas d'erreur" end
  verifie("partage : texte vide", "Colle d'abord le texte reçu.", erreur(""))
  verifie("partage : que des espaces", "Colle d'abord le texte reçu.", erreur("  \n "))
  verifie("partage : pas un texte", "Colle d'abord le texte reçu.", erreur(nil))
  verifie("partage : pas un texte de réglages", true, erreur("bonjour, voici mes réglages"):find("commencer par « VA1; »", 1, true) ~= nil)
  verifie("partage : début coupé", true, erreur("GPS:taille=160"):find("commencer par", 1, true) ~= nil)
  verifie("partage : une autre version", true, erreur("VA2;GPS:taille=160"):find("autre version (VA2)", 1, true) ~= nil)
  verifie("partage : aucun réglage", "Ce texte ne contient aucun réglage.", erreur("VA1;"))
  verifie("partage : que des blocs vides", "Ce texte ne contient aucun réglage.", erreur("VA1;;;"))
  verifie("partage : bloc sans deux-points", true, erreur("VA1;GPS"):find("« GPS »", 1, true) ~= nil)
  verifie("partage : bloc sans nom", true, erreur("VA1;:a=1"):find("Texte abîmé", 1, true) ~= nil)
  verifie("partage : paire sans valeur", true, erreur("VA1;GPS:taille"):find("dans « GPS » : « taille »", 1, true) ~= nil)
  verifie("partage : valeur qui n'est pas un nombre", true, erreur("VA1;GPS:taille=grand"):find("« taille=grand »", 1, true) ~= nil)
  verifie("partage : nombre abîmé", true, erreur("VA1;GPS:taille=1.2.3"):find("« taille=1.2.3 »", 1, true) ~= nil)
  verifie("partage : nombre infini refusé", true, erreur("VA1;GPS:taille=1e999"):find("Texte abîmé", 1, true) ~= nil)
  verifie("partage : texte coupé en plein milieu", true, erreur("VA1;GPS:taille=160;SacsRanges:ec"):find("« ec »", 1, true) ~= nil)
  verifie("partage : les codes de couleur collés sont neutralisés", true, erreur("VA1;GPS:|cffff0000x=1"):find("||cffff0000", 1, true) ~= nil)
  verifie("partage : texte énorme refusé", true, erreur("VA1;GPS:a=1;" .. string.rep("A:b=1;", 4000)):find("trop long", 1, true) ~= nil)

  -- Une valeur reçue devient la valeur d'un réglage, ou elle est refusée.
  local inter = {}
  local curseur = { type = "nombre", min = 60, max = 300, pas = 10 }
  verifie("valeur : interrupteur 1", true, ns.valeurValide(inter, 1))
  verifie("valeur : interrupteur 0", false, ns.valeurValide(inter, 0))
  verifie("valeur : interrupteur 2 refusé", "nil", tostring(ns.valeurValide(inter, 2)))
  verifie("valeur : interrupteur 0,5 refusé", "nil", tostring(ns.valeurValide(inter, 0.5)))
  verifie("valeur : curseur dans les bornes", 160, ns.valeurValide(curseur, 160))
  verifie("valeur : curseur arrondi sur son pas", 170, ns.valeurValide(curseur, 166))
  verifie("valeur : curseur trop haut", 300, ns.valeurValide(curseur, 9999))
  verifie("valeur : curseur trop bas", 60, ns.valeurValide(curseur, -5))
  verifie("valeur : option absente", "nil", tostring(ns.valeurValide(nil, 1)))
  verifie("valeur : pas un nombre", "nil", tostring(ns.valeurValide(inter, "1")))

  -- Appliquer : les addons et les clés inconnus sont ignorés, et comptés.
  local posees = {}
  local function cible(nom, options, refuse)
    return { nom = nom, options = options, poser = function(cle, v)
      if refuse == cle then error("refusé par l'addon") end
      posees[#posees + 1] = nom .. "." .. cle .. "=" .. tostring(v)
    end }
  end
  local cibles = {
    cible("GPS", { taille = curseur, actif = inter, ordre = inter }, "ordre"),
    cible("SacsRanges", { vueCategories = inter }),
    cible("Muet", { x = inter }),
  }
  local bilan = ns.appliquerPartage({
    GPS = { taille = 166, actif = 1, inconnue = 1, ordre = 1 },
    SacsRanges = { vueCategories = 0, bavard = 1 },
    Absent = { a = 1 },
    Aussi = { b = 1 },
  }, cibles)
  verifie("appliquer : les réglages posés, dans l'ordre", "GPS.actif=true,GPS.taille=170,SacsRanges.vueCategories=false", table.concat(posees, ","))
  verifie("appliquer : réglages appliqués", 3, bilan.appliques)
  verifie("appliquer : addons touchés", 2, bilan.addons)
  verifie("appliquer : clés inconnues", 2, bilan.inconnus)
  verifie("appliquer : un addon qui refuse", 1, bilan.refuses)
  verifie("appliquer : addons absents chez moi", "Absent,Aussi", table.concat(bilan.absents, ","))
  verifie("appliquer : le bilan en une phrase",
    "3 réglage(s) appliqué(s) dans 2 addon(s). 2 réglage(s) inconnu(s) ignoré(s). 1 valeur(s) refusée(s). Pas chez toi : Absent, Aussi.",
    ns.texteBilanPartage(bilan))
  local vide = ns.appliquerPartage({ Autre = { a = 1 } }, cibles)
  verifie("appliquer : rien d'appliqué", "Aucun réglage appliqué. Pas chez toi : Autre.", ns.texteBilanPartage(vide))
  local refus = ns.appliquerPartage({ GPS = { actif = 7 } }, cibles)
  verifie("appliquer : valeur refusée", "Aucun réglage appliqué. 1 valeur(s) refusée(s).", ns.texteBilanPartage(refus))
end
-- Réglages propres à un personnage, de bout en bout : chargement, r.changer, partage.
do
  local ecouteurs = {}
  local vrai = CreateFrame
  CreateFrame = function()
    local f = bidon()
    local scripts = {}
    rawset(f, "SetScript", function(_, nom, fn) scripts[nom] = fn end)
    rawset(f, "RegisterEvent", function(self, ev) if ev == "ADDON_LOADED" then ecouteurs[#ecouteurs + 1] = scripts end end)
    rawset(f, "UnregisterEvent", function() end)
    return f
  end
  local vraiPrint, vraiUnitName, vraiRoyaume = print, UnitName, GetRealmName
  print = function() end
  GetRealmName = function() return "Elune" end
  local options = {
    { cle = "actif", libelle = "Activer" },
    { titre = "Section" },
    { cle = "son", libelle = "Son" },
    { cle = "taille", type = "nombre", libelle = "Taille", min = 60, max = 300, pas = 10 },
  }
  local defauts = { actif = true, son = true, taille = 100, liste = {} }
  -- Une connexion : l'addon se charge avec la sauvegarde `sauve` pour le personnage `nom`.
  local function connexion(nom, sauve)
    UnitName = function() return nom end
    _G.FauxPersoDB = sauve
    ecouteurs = {}
    local nsX = {}
    assert(loadfile(reglagesLua))("FauxPerso", nsX)
    local r = nsX.creerReglages({ titre = "FauxPerso", icone = "x", nomDB = "FauxPersoDB", defauts = defauts, options = options })
    for _, scripts in ipairs(ecouteurs) do scripts.OnEvent({ UnregisterEvent = function() end }, "ADDON_LOADED", "FauxPerso") end
    return r, _G.FauxPersoDB, nsX
  end
  local function entree()
    for i = #_G.ValentinAddons.entrees, 1, -1 do
      if _G.ValentinAddons.entrees[i].titre == "FauxPerso" then return _G.ValentinAddons.entrees[i], i end
    end
  end
  local function oterEntree()
    local _, i = entree()
    while i do
      table.remove(_G.ValentinAddons.entrees, i)
      _, i = entree()
    end
  end

  -- Une vieille sauvegarde, à plat, d'avant les profils.
  local r, db = connexion("Aela", { actif = true, son = false, taille = 120, position = { x = 3 }, liste = { 1 } })
  verifie("de bout en bout : le compte reprend la vieille sauvegarde", "true/false/120", tostring(db.compte.actif) .. "/" .. tostring(db.compte.son) .. "/" .. tostring(db.compte.taille))
  verifie("de bout en bout : rien n'a changé pour le joueur", "false/120", tostring(db.son) .. "/" .. tostring(db.taille))
  verifie("de bout en bout : la liste et la position sont à leur place", "3/1", db.position.x .. "/" .. #db.liste)
  r.changer("taille", 150)
  verifie("de bout en bout : r.changer écrit aussi dans le compte", 150, db.compte.taille)
  -- Une écriture directe dans db, suivie de r.appliquer (comme le font des commandes d'addons).
  db.son = true
  r.appliquer()
  verifie("de bout en bout : r.appliquer garde une écriture directe", true, db.compte.son)

  -- Aela passe en réglages propres (ce que fait l'interrupteur de l'en-tête) et règle sa taille.
  ns.changerMode(db, ns.clesReglages(options), "Aela-Elune", true, defauts)
  r.appliquer()
  r.changer("taille", 200)
  verifie("de bout en bout : la taille d'Aela est à elle", 200, db.parPerso["Aela-Elune"].taille)
  verifie("de bout en bout : le compte garde 150", 150, db.compte.taille)
  -- Le texte à partager est celui des réglages actuels.
  local e = entree()
  verifie("de bout en bout : l'addon est inscrit pour le partage", "FauxPerso", e and e.partage and e.partage.nom)
  verifie("de bout en bout : le partage lit les réglages de la clé déclarée", 200, e and e.partage.lire().taille)
  verifie("de bout en bout : le partage ne lit pas la liste", "nil", tostring(e and e.partage.lire().liste))
  verifie("de bout en bout : le texte de partage", "VA1;FauxPerso:actif=1,son=1,taille=200",
    ns.encoderReglages({ { nom = "FauxPerso", valeurs = e.partage.lire() } }))
  oterEntree()

  -- Bob se connecte avec la même sauvegarde : il suit le compte.
  local r2, db2 = connexion("Bob", db)
  verifie("de bout en bout : Bob suit le compte", 150, db2.taille)
  verifie("de bout en bout : Bob n'a pas de réglages propres", false, ns.modePerso(db2, "Bob-Elune"))
  r2.changer("taille", 90)
  verifie("de bout en bout : Bob change le compte", 90, db2.compte.taille)
  verifie("de bout en bout : Aela garde les siens", 200, db2.parPerso["Aela-Elune"].taille)
  -- Appliquer un texte reçu passe par r.changer : le profil du personnage le garde.
  local e2 = entree()
  local bilan = ns.appliquerPartage(ns.decoderReglages("VA1;FauxPerso:taille=250,son=0,inconnue=1;Autre:x=1"), { e2.partage })
  verifie("de bout en bout : texte reçu appliqué", "2/1", bilan.appliques .. "/" .. bilan.inconnus)
  verifie("de bout en bout : le texte reçu va dans le compte de Bob", "250/false", tostring(db2.compte.taille) .. "/" .. tostring(db2.compte.son))
  verifie("de bout en bout : le texte reçu ne touche pas Aela", 200, db2.parPerso["Aela-Elune"].taille)
  oterEntree()

  -- Aela revient : ses réglages propres, puis elle les coupe et retrouve le compte.
  local r3, db3 = connexion("Aela", db2)
  verifie("de bout en bout : Aela retrouve les siens", 200, db3.taille)
  ns.changerMode(db3, ns.clesReglages(options), "Aela-Elune", false, defauts)
  r3.appliquer()
  verifie("de bout en bout : Aela coupe ses réglages propres, retrouve le compte", 250, db3.taille)
  verifie("de bout en bout : plus d'entrée pour Aela", "nil", tostring(db3.parPerso["Aela-Elune"]))
  oterEntree()

  -- Un nom encore inconnu du jeu : tout reste sur le compte, sans erreur.
  UnitName = function() return nil end
  local compteAvant = db3.compte.taille
  local r4, db4 = connexion(nil, db3)
  UnitName = function() return nil end
  r4.changer("taille", 110)
  verifie("de bout en bout : sans nom, la valeur de la session est prise", 110, db4.taille)
  verifie("de bout en bout : sans nom, rien n'est écrit dans le compte", compteAvant, db4.compte.taille)
  oterEntree()

  print, UnitName, GetRealmName = vraiPrint, vraiUnitName, vraiRoyaume
  CreateFrame = vrai
end
-- La part de « À vendre » qui n'est pas grise, pour Marchand auto.
local lus = {
  { sac = 0, case = 1, lien = "[Gris]", id = 1, qualite = 0, categorie = "vendre" },
  { sac = 0, case = 2, lien = "[Casque]", id = 2, qualite = 3, categorie = "vendre", raison = "lié" },
  { sac = 0, case = 3, lien = "[Cuir]", id = 3, qualite = 1, categorie = "compo" },
  { sac = 1, case = 1, lien = "[Gants]", id = 4, qualite = 2, categorie = "pasPourToi" },
}
local av = ns.filtrerAVendre(lus)
verifie("à vendre : le gris et les autres sections sortent", 1, #av)
verifie("à vendre : le casque lié", "[Casque]", av[1] and av[1].lien)
verifie("à vendre : sac, case, id, raison", "0:2:2:lié", av[1] and (av[1].sac .. ":" .. av[1].case .. ":" .. av[1].id .. ":" .. av[1].raison))
verifie("à vendre : liste vide", 0, #ns.filtrerAVendre(nil))
-- La banque rangée.
local ba = ns.sacsBanque({ banque = -1, premierSac = 5, nbSacs = 3 })
verifie("banque : -1 puis les 3 sacs de banque", "-1,5,6,7", table.concat(ba, ","))
verifie("banque : les onglets l'emportent", "6,7,8", table.concat(ns.sacsBanque({ onglets = { 6, 7, 8 }, banque = -1, premierSac = 5, nbSacs = 7 }), ","))
verifie("banque : onglets vides, repli sur la banque", "-1", table.concat(ns.sacsBanque({ onglets = {}, banque = -1, nbSacs = 0 }), ","))
verifie("banque : rien de connu", 0, #ns.sacsBanque(nil))
verifie("banque : sacs de banque sans numéro de départ", "5,6", table.concat(ns.sacsBanque({ nbSacs = 2 }), ","))
verifie("banque montrée : tout est là", true, ns.banqueAMontrer({ vue = true, option = true, ouverte = true, nbCases = 28 }))
verifie("banque cachée : option décochée", false, ns.banqueAMontrer({ vue = true, option = false, ouverte = true, nbCases = 28 }))
verifie("banque cachée : vue par catégories coupée", false, ns.banqueAMontrer({ vue = false, option = true, ouverte = true, nbCases = 28 }))
verifie("banque cachée : banque fermée", false, ns.banqueAMontrer({ vue = true, option = true, ouverte = false, nbCases = 28 }))
verifie("banque cachée : le jeu ne dit rien (0 case)", false, ns.banqueAMontrer({ vue = true, option = true, ouverte = true, nbCases = 0 }))
verifie("banque cachée : faits absents", false, ns.banqueAMontrer(nil))
verifie("colonnes : petit sac", 10, ns.colonnesPour(60))
verifie("colonnes : 80 cases", 12, ns.colonnesPour(80))
verifie("colonnes : banque de 150 cases", 14, ns.colonnesPour(150))
-- Hauteur plafonnée : plus de colonnes, jusqu'à 24.
local planBanque = { aEquiper = 0, sections = { 100, 50 }, libre = true }
verifie("hauteur : calcul pour 14 colonnes", 58 + (16 + 8 * 41 + 6) + (16 + 4 * 41 + 6) + (16 + 41) + 30, ns.hauteurVue(planBanque, 14))
verifie("hauteur : « À équiper » compté", 58 + (16 + 2 * 45 + 6) + 30, ns.hauteurVue({ aEquiper = 2 }, 10))
verifie("hauteur : section vide ignorée", 58 + 30, ns.hauteurVue({ sections = { 0, 0 } }, 10))
verifie("colonnes : écran assez haut, inchangé", 14, ns.colonnesPour(150, planBanque, 2000))
verifie("colonnes : sans hauteur, inchangé", 14, ns.colonnesPour(150, planBanque, nil))
verifie("colonnes : sans plan, inchangé", 14, ns.colonnesPour(150, nil, 500))
local hMax = ns.hauteurVue(planBanque, 16) + 1
local cAjuste = ns.colonnesPour(150, planBanque, hMax)
verifie("colonnes : trop haut, on élargit", true, cAjuste > 14 and cAjuste <= 16)
verifie("colonnes : au plus juste (une de moins ne tient pas)", true, ns.hauteurVue(planBanque, cAjuste - 1) > hMax)
verifie("colonnes : jamais plus de 24", 24, ns.colonnesPour(150, planBanque, 100))
verifie("colonnes : le plafond tient avec ces colonnes", true, ns.hauteurVue(planBanque, ns.colonnesPour(150, planBanque, hMax)) <= hMax)
verifie("banque cachée : fermée à la main", false, ns.banqueAMontrer({ vue = true, option = true, ouverte = true, nbCases = 28, fermeeMain = true }))
verifie("banque montrée : rouverte (drapeau remis à faux)", true, ns.banqueAMontrer({ vue = true, option = true, ouverte = true, nbCases = 28, fermeeMain = false }))
local lusBanque = {
  { sac = -1, case = 2, categorie = "equip", nom = "Heaume", qualite = 3, conseil = { raison = "mieux" } },
  { sac = 5, case = 1, categorie = "equip", nom = "Bottes", qualite = 2 },
  { sac = -1, case = 1, categorie = "equip", nom = "Anneau", qualite = 2, conseil = { raison = "mieux" } },
}
local eq, aut = ns.separerConseils(lusBanque, true)
verifie("conseils (sac) : 2 à équiper", 2, #eq)
verifie("conseils (sac) : triés par nom", "Anneau", eq[1] and eq[1].nom)
verifie("conseils (sac) : 1 autre", 1, #aut)
local eqB, autB = ns.separerConseils(lusBanque, false)
verifie("conseils (banque) : aucun à équiper", 0, #eqB)
verifie("conseils (banque) : tout reste rangé par section", 3, #autB)
local partsB = ns.repartir(autB)
verifie("banque : sections par qualité puis nom", "Heaume,Anneau,Bottes",
  partsB.equip[1].nom .. "," .. partsB.equip[2].nom .. "," .. partsB.equip[3].nom)

-- Composants par extension (Retail) --------------------------------------------
do
  local function o(nom, e, sac, case, extra)
    local t = { nom = nom, extension = e, sac = sac or 0, case = case or 1, id = case, categorie = "compo", qualite = 1 }
    for k, v in pairs(extra or {}) do t[k] = v end
    return t
  end
  local liste = { o("Bismuth", 10, 0, 1), o("Lin", 0, 0, 2), o("Minerai solaire", 11, 0, 3), o("Rêverie", 6, 0, 4),
    o("Saronite", 2, 0, 5), o("Soie d'aube", 11, 0, 6), o("Sans numéro", nil, 0, 7) }
  local function noms(groupes)
    local l = {}
    for _, g in ipairs(groupes) do l[#l + 1] = g.nom .. "=" .. #g.objets end
    return table.concat(l, ",")
  end
  verifie("extensions : nom connu", "Midnight", ns.nomExtension(11))
  verifie("extensions : nom Classique", "Classique", ns.nomExtension(0))
  verifie("extensions : numéro inconnu", "Extension 14", ns.nomExtension(14))
  verifie("extensions : en cours pas ancienne", false, ns.estAncienne(11, 11))
  verifie("extensions : celle d'avant pas ancienne", false, ns.estAncienne(10, 11))
  verifie("extensions : deux avant, ancienne", true, ns.estAncienne(9, 11))
  verifie("extensions : Forever, pas de groupes", nil, ns.grouperExtensions(liste, 0))
  verifie("extensions : sans numéro d'extension en cours, pas de groupes", nil, ns.grouperExtensions(liste, nil))
  local g = ns.grouperExtensions(liste, 11, false)
  verifie("extensions : la plus récente d'abord, sans numéro = Classique",
    "Midnight=2,The War Within=1,Legion=1,Wrath of the Lich King=1,Classique=2", noms(g))
  verifie("extensions : ordre gardé dans un groupe", "Minerai solaire,Soie d'aube", g[1].objets[1].nom .. "," .. g[1].objets[2].nom)
  verifie("extensions : groupe en cours pas ancien", false, g[1].ancienne)
  verifie("extensions : groupe Legion ancien", true, g[3].ancienne)
  local r = ns.grouperExtensions(liste, 11, true)
  verifie("extensions : anciennes regroupées, à la fin", "Midnight=2,The War Within=1,Anciennes extensions=4", noms(r))
  verifie("extensions : regroupées, la plus récente d'abord", "Rêverie,Saronite,Lin,Sans numéro",
    r[3].objets[1].nom .. "," .. r[3].objets[2].nom .. "," .. r[3].objets[3].nom .. "," .. r[3].objets[4].nom)
  verifie("extensions : liste vide", 0, #ns.grouperExtensions({}, 11))

  -- La hauteur de la fenêtre avec une section découpée en groupes.
  verifie("hauteur : section en groupes", 58 + (16 + (14 + 41) + (14 + 2 * 41) + 6) + 30,
    ns.hauteurVue({ sections = { { 3, 12, 0 } } }, 10))
  verifie("hauteur : groupes tous vides, rien", 58 + 30, ns.hauteurVue({ sections = { { 0, 0 } } }, 10))
  verifie("hauteur : groupes et section simple", 58 + (16 + 41 + 6) + (16 + 14 + 41 + 6) + 30,
    ns.hauteurVue({ sections = { 4, { 2 } } }, 10))

  -- Ce qui part en banque.
  local sacLu = { o("Bismuth", 10, 0, 1), o("Lin", 0, 0, 2), o("Minerai solaire", 11, 0, 3), o("Rêverie", 6, 1, 4),
    o("Verrouillé", 6, 1, 5, { verrou = true }), o("Potion", 6, 1, 6, { categorie = "conso" }) }
  local function cases(l)
    local t = {}
    for _, x in ipairs(l) do t[#t + 1] = x.sac .. ":" .. x.case end
    return table.concat(t, ",")
  end
  verifie("dépôt : par défaut, les anciennes seulement", "0:2,1:4", cases(ns.aDeposer(sacLu, nil, 11)))
  verifie("dépôt : choix du joueur (TWW oui, Classique non)", "0:1,1:4", cases(ns.aDeposer(sacLu, { [10] = true, [0] = false }, 11)))
  verifie("dépôt : tout décoché", "", cases(ns.aDeposer(sacLu, { [0] = false, [6] = false }, 11)))
  verifie("dépôt : rien à lire", 0, #ns.aDeposer(nil, nil, 11))
  verifie("dépôt : l'objet garde son numéro", 4, ns.aDeposer(sacLu, nil, 11)[2].id)
  local parExt, presentes = ns.compterExtensions(sacLu)
  verifie("dépôt : extensions présentes, la plus récente d'abord", "11,10,6,0", table.concat(presentes, ","))
  verifie("dépôt : piles par extension (verrouillée comptée, potion non)", 2, parExt[6])
  verifie("dépôt : bilan simple", "1 pile de composants déposée en banque (Personnage).", ns.bilanDepot(1, "Personnage", 0, 0))
  verifie("dépôt : bilan complet",
    "12 piles de composants déposées en banque (Bataillon), 2 liées au personnage laissées, 1 laissée (verrouillée ou déplacée). Arrêt : la banque est pleine.",
    ns.bilanDepot(12, "Bataillon", 2, 1, "la banque est pleine"))
end
os.exit(ok and 0 or 1)
