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
verifie("arme pas apprise et liée : À vendre", "vendre", ns.categorie(2, 1, false, false, 0, 1, { estLie = true, raison = "autre" }))
verifie("liée mais seulement trop haut en niveau : Tu ne peux pas le porter", "pasPourToi",
  ns.categorie(4, 2, false, false, 0, 1, { estLie = true, raison = "niveau" }))
verifie("raison : niveau seul", "niveau", (ns.raisonPasPortable({ "Niveau 20 requis" })))
verifie("raison : arme pas apprise", "autre", (ns.raisonPasPortable({ "Arc", "Niveau 20 requis" })))
verifie("texte : gris", "objet gris", ns.texteRangement("vendre", 0, false))
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
  verifie("neuf : texte, rien de marqué sans date vue", nil, t:find("[nouveau]", 1, true))
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
os.exit(ok and 0 or 1)
