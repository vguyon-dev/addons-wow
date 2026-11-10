-- Simulation hors jeu de Conseiller : situation, rôle manquant, spécialisation conseillée,
-- résolution des sorts, moteur de priorité (dont le passage au mode C sur valeur secrète),
-- prochain nœud d'un build, textes des onglets, puis chargement de bout en bout avec une fausse API.
-- Lancer depuis Windows :
--   wsl lua5.1 tests/Conseiller_simu.lua Conseiller/Conseiller.lua
local bidon
bidon = function()
  return setmetatable({}, { __index = function() return bidon() end, __call = function() return bidon() end })
end
local cadres = {}
function CreateFrame(_, nom)
  local f = bidon()
  local scripts, evenements, visible = {}, {}, false
  rawset(f, "SetScript", function(self, n, fn) scripts[n] = fn end)
  rawset(f, "RegisterEvent", function(self, ev) evenements[ev] = true end)
  rawset(f, "IsShown", function() return visible end)
  rawset(f, "Show", function() visible = true end)
  rawset(f, "Hide", function() visible = false end)
  rawset(f, "IsVisible", function() return visible end)
  rawset(f, "_scripts", scripts)
  rawset(f, "_evenements", evenements)
  rawset(f, "_nom", nom)
  cadres[#cadres + 1] = f
  return f
end
UIParent, SlashCmdList, UISpecialFrames, Minimap = {}, {}, {}, bidon()
tinsert = table.insert
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
date, time = os.date, os.time

function GetTime() return 100 end
local sortie = print
print = function() end -- les messages au chat ne nous intéressent pas ici

-- ---------------------------------------------------------------- fausse API du jeu
local SECRET = {} -- une valeur que le jeu cache : issecretvalue(SECRET) est vrai
function issecretvalue(v) return v == SECRET end

local jeu = {
  classe = "HUNTER", niveau = 12, raceNom = "Orc", raceToken = "Orc",
  spe = nil, -- rang de la spécialisation (nil : le jeu n'en donne pas)
  groupe = false, raid = false, typeInstance = "none", membres = {},
  sortsConnus = {}, grimoire = {}, config = 77, noeuds = {},
  metiers = {},
}
function UnitClass() return "Classe", jeu.classe end
function UnitLevel() return jeu.niveau end
function UnitRace() return jeu.raceNom, jeu.raceToken end
function UnitName(u) return u == "player" and "Moi" or ("Membre " .. tostring(u)) end
function GetRealmName() return "Royaume" end
UNKNOWNOBJECT = "Inconnu"
function IsInInstance() return jeu.typeInstance ~= "none", jeu.typeInstance end
function IsInGroup() return jeu.groupe end
function IsInRaid() return jeu.raid end
function GetNumGroupMembers() return #jeu.membres + 1 end
function UnitExists(u) return u == "player" or u == "target" or (u:match("^party(%d)$") ~= nil and jeu.membres[tonumber(u:match("%d"))] ~= nil) end
function UnitIsUnit(a, b) return a == b end
function UnitGroupRolesAssigned(u)
  if u == "player" then return jeu.roleMoi or "NONE" end
  local m = jeu.membres[tonumber(u:match("%d"))]
  return m and m.role or "NONE"
end
-- UnitClass d'un autre membre : on lit la classe de la table
local unitClassBase = UnitClass
function UnitClass(u)
  if u and u ~= "player" and u:match("^party%d$") then
    local m = jeu.membres[tonumber(u:match("%d"))]
    return "Classe", m and m.classe
  end
  return unitClassBase()
end
C_SpecializationInfo = {
  GetSpecialization = function() return jeu.spe end,
  GetSpecializationInfo = function(i) return 1000 + i, jeu.nomSpe, "", 0, "DAMAGER" end,
  GetNumSpecializations = function() return jeu.nbSpes end,
}
function UnitCreatureType() return jeu.typeCreature end
C_SpellBook = {
  IsSpellKnown = function(id) return jeu.sortsConnus[id] == true end,
  GetNumSpellBookSkillLines = function() return 1 end,
  GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = 2 } end,
  GetSpellBookItemInfo = function(i)
    if i == 1 then return { spellID = 75, name = "Tir automatique", subName = "" } end
    return { spellID = 3045, name = "Tir rapide", subName = "Rang 1" }
  end,
}
C_Spell = { GetSpellName = function(id) return jeu.noms and jeu.noms[id] or nil end }
C_ClassTalents = { GetActiveConfigID = function() return jeu.config end }
C_Traits = {
  GetNodeInfo = function(config, id) return jeu.noeuds[id] end,
  PurchaseRank = function(config, id)
    local n = jeu.noeuds[id]
    if not n then return false end
    n.currentRank = n.currentRank + 1
    return true
  end,
  CommitConfig = function() jeu.valide = true; return true end,
  SetSelection = function(config, id, entree) jeu.selection = { id, entree }; return true end,
}
function InCombatLockdown() return jeu.enCombat or false end
function GetProfessions() return unpack(jeu.metiers) end
function GetProfessionInfo(i) local m = jeu.infosMetiers and jeu.infosMetiers[i]; if m then return m.nom, nil, m.niveau, m.plafond end end

local ns = {}
local reglagesLua = arg[1]:gsub("[^/]+$", "Reglages.lua")
local dossier = arg[1]:gsub("[^/]+$", "")
for _, f in ipairs({ "Reglages.lua", "Donnees.lua", "Logique.lua", "Conseiller.lua", "Fenetre.lua" }) do
  assert(loadfile(dossier .. f))("Conseiller", ns)
end
local D = ns.DONNEES
local BUILDS_CHASSEUR = D.BUILDS.HUNTER -- les vrais builds du chasseur : les essais ci-dessous les remplacent par les leurs

local ok = true
local function verifie(libelle, attendu, obtenu)
  local bon = attendu == obtenu
  ok = ok and bon
  io.write(string.format("%s %-60s attendu %s, obtenu %s\n", bon and "OK " or "KO ", libelle, tostring(attendu), tostring(obtenu)))
end
local function lire(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end
verifie("Reglages.lua identique dans Montures", true,
  lire(reglagesLua) == lire((reglagesLua:gsub("Conseiller/Reglages", "Montures/Reglages"))))
local function contient(texte, morceau) return type(texte) == "string" and texte:find(morceau, 1, true) ~= nil end

-- ================================================================ situation
verifie("situation : seul", "solo", ns.situation({}))
verifie("situation : en groupe", "groupe", ns.situation({ groupe = true }))
verifie("situation : raid de groupe", "raid", ns.situation({ groupe = true, raid = true }))
verifie("situation : donjon (instance de groupe)", "donjon", ns.situation({ groupe = true, typeInstance = "party" }))
verifie("situation : donjon même seul dans l'instance", "donjon", ns.situation({ typeInstance = "party" }))
verifie("situation : raid instancié", "raid", ns.situation({ groupe = true, typeInstance = "raid" }))

-- ================================================================ rôles du groupe
local function membres(...)
  local l = {}
  for _, m in ipairs({ ... }) do l[#l + 1] = { role = m[1], classe = m[2] } end
  return l
end
local g = ns.analyserGroupe(membres({ "TANK", "WARRIOR" }, { "HEALER", "PRIEST" }, { "DAMAGER", "MAGE" }, { "DAMAGER", "ROGUE" }))
verifie("groupe complet : rien ne manque", nil, g.manque)
verifie("groupe complet : total 5", 5, g.total)
g = ns.analyserGroupe(membres({ "HEALER", "PRIEST" }, { "DAMAGER", "MAGE" }, { "DAMAGER", "ROGUE" }, { "DAMAGER", "HUNTER" }))
verifie("sans tank : manque le tank", "tank", g.manque)
g = ns.analyserGroupe(membres({ "TANK", "WARRIOR" }, { "DAMAGER", "MAGE" }, { "DAMAGER", "ROGUE" }, { "DAMAGER", "HUNTER" }))
verifie("sans soigneur : manque les soins", "soins", g.manque)
g = ns.analyserGroupe(membres({ "DAMAGER", "MAGE" }, { "DAMAGER", "ROGUE" }, { "DAMAGER", "HUNTER" }, { "DAMAGER", "HUNTER" }))
verifie("ni tank ni soigneur : tank d'abord", "tank", g.manques[1])
verifie("ni tank ni soigneur : puis les soins", "soins", g.manques[2])
g = ns.analyserGroupe(membres({ "HEALER", "PRIEST" }, { "DAMAGER", "MAGE" }, { "DAMAGER", "ROGUE" }, { "DAMAGER", "HUNTER" }), "TANK")
verifie("toi, tank : ton rôle compte", nil, g.manque)
verifie("toi, tank : rôle retenu", "tank", g.moi)
g = ns.analyserGroupe(membres({ "NONE", "WARRIOR" }, { "NONE", "PRIEST" }, { "NONE", "MAGE" }, { "NONE", "ROGUE" }))
verifie("rôles non attribués : devinés par la classe", true, g.devine)
verifie("rôles devinés : le guerrier est tank, le prêtre soigneur", nil, g.manque)
local dix = {}
for i = 1, 9 do dix[i] = { role = i == 1 and "TANK" or (i == 2 and "HEALER" or "DAMAGER"), classe = "MAGE" } end
g = ns.analyserGroupe(dix)
verifie("raid de 10 : deux tanks demandés", "tank", g.manques[1])
verifie("raid de 10 : deux soigneurs demandés", "soins", g.manques[2])
verifie("groupe nil sans erreur", 1, ns.analyserGroupe(nil).total)

-- ================================================================ spécialisation
verifie("cleSpe par le nom du jeu, avec accents", "bete", ns.cleSpe("HUNTER", "Maîtrise des bêtes", nil))
verifie("cleSpe par le nom, majuscules", "precision", ns.cleSpe("HUNTER", "PRÉCISION", nil))
verifie("cleSpe par le rang (secours)", "survie", ns.cleSpe("HUNTER", nil, 3))
verifie("cleSpe : nom inconnu, rang connu", "sacre", ns.cleSpe("PALADIN", "Truc", 1))
verifie("cleSpe : classe inconnue", nil, ns.cleSpe("BOUDIN", "x", 1))
-- druide : Gardien (Retail, 4 spécialisations) ne doit pas passer pour Restauration (Forever, 3)
verifie("cleSpe druide : Gardien par son nom", "gardien", ns.cleSpe("DRUID", "Gardien", nil))
verifie("cleSpe druide : Restauration par son nom", "restauration", ns.cleSpe("DRUID", "Restauration", 4, 4))
verifie("cleSpe druide, rang 3 sur 4 : Gardien", "gardien", ns.cleSpe("DRUID", nil, 3, 4))
verifie("cleSpe druide, rang 4 sur 4 : Restauration", "restauration", ns.cleSpe("DRUID", nil, 4, 4))
verifie("cleSpe druide, rang 3 sur 3 (Forever) : Restauration", "restauration", ns.cleSpe("DRUID", nil, 3, 3))
verifie("cleSpe druide, rang 3 sans le nombre : ambigu, rien", nil, ns.cleSpe("DRUID", nil, 3))
verifie("cleSpe druide, rang 1 sans le nombre : Équilibre", "equilibre", ns.cleSpe("DRUID", nil, 1))
verifie("cleSpe : Gardien est un tank", "tank", D.CLASSES.DRUID.specs.gardien.role)
verifie("stats : Gardien, défense d'abord (fiche)", "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT", ns.ordreStats("DRUID", "gardien")[1])

-- valeurs secrètes dans les rôles
local rS, devS = ns.roleDe({ role = SECRET, classe = "WARRIOR" })
verifie("roleDe : rôle secret, repli sur la classe (tank)", "TANK", rS)
verifie("roleDe : rôle secret, rôle deviné", true, devS)
rS = ns.roleDe({ role = "NONE", classe = SECRET })
verifie("roleDe : classe secrète, dégâts sans erreur", "DAMAGER", rS)

local c = ns.speConseillee("PALADIN", "solo", nil)
verifie("paladin seul : vindicte", "vindicte", c.cle)
c = ns.speConseillee("PALADIN", "groupe", ns.analyserGroupe(membres({ "HEALER", "PRIEST" }, { "DAMAGER", "MAGE" }, { "DAMAGER", "ROGUE" }, { "DAMAGER", "HUNTER" })))
verifie("paladin, groupe sans tank : protection", "protection", c.cle)
verifie("paladin, groupe sans tank : rôle comblé", "tank", c.parManque)
c = ns.speConseillee("PALADIN", "donjon", ns.analyserGroupe(membres({ "TANK", "WARRIOR" }, { "DAMAGER", "MAGE" }, { "DAMAGER", "ROGUE" }, { "DAMAGER", "HUNTER" })))
verifie("paladin, donjon sans soigneur : sacré", "sacre", c.cle)
c = ns.speConseillee("PALADIN", "groupe", ns.analyserGroupe(membres({ "TANK", "WARRIOR" }, { "HEALER", "PRIEST" }, { "DAMAGER", "MAGE" }, { "DAMAGER", "ROGUE" })))
verifie("paladin, groupe complet : vindicte", "vindicte", c.cle)
verifie("paladin, groupe complet : pas de rôle comblé", nil, c.parManque)
c = ns.speConseillee("HUNTER", "groupe", ns.analyserGroupe(membres({ "HEALER", "PRIEST" }, { "DAMAGER", "MAGE" }, { "DAMAGER", "ROGUE" }, { "DAMAGER", "HUNTER" })))
verifie("chasseur ne peut pas tanker : reste en maîtrise des bêtes", "bete", c.cle)
verifie("chasseur, tank manquant : pas de rôle comblé", nil, c.parManque)
verifie("chasseur seul : maîtrise des bêtes", "bete", ns.speConseillee("HUNTER", "solo").cle)
verifie("classe inconnue : nil", nil, ns.speConseillee("BOUDIN", "solo"))

-- ================================================================ builds de talents
D.BUILDS.HUNTER = { bete = {
  solo = { { nodeID = 10, rangs = 2 }, { nodeID = 11, rangs = 1 }, { nodeID = 12, rangs = 3 } },
  groupe = { { nodeID = 20, rangs = 1 } },
} }
verifie("build : seul", 3, #ns.buildPour("HUNTER", "bete", "solo"))
verifie("build : donjon retombe sur groupe", 20, ns.buildPour("HUNTER", "bete", "donjon")[1].nodeID)
verifie("build : spécialisation sans build", nil, ns.buildPour("HUNTER", "survie", "solo"))
verifie("build : classe sans build", nil, ns.buildPour("MAGE", "feu", "solo"))
local rangs = { [10] = 0, [11] = 0, [12] = 0 }
local function rangDe(id) return rangs[id] end
local e, r2, i = ns.prochainNoeud(ns.buildPour("HUNTER", "bete", "solo"), rangDe)
verifie("prochain nœud : le premier", 10, e.nodeID)
verifie("prochain nœud : son rang actuel", 0, r2)
rangs[10] = 1
e = ns.prochainNoeud(ns.buildPour("HUNTER", "bete", "solo"), rangDe)
verifie("prochain nœud : même nœud tant que les rangs manquent", 10, e.nodeID)
rangs[10] = 2
e, r2, i = ns.prochainNoeud(ns.buildPour("HUNTER", "bete", "solo"), rangDe)
verifie("prochain nœud : le suivant", 11, e.nodeID)
verifie("prochain nœud : sa place dans le build", 2, i)
rangs[11] = 1
rangs[12] = nil -- nœud absent de l'arbre : sauté
verifie("prochain nœud : un nœud inconnu est sauté, rien d'autre", nil, ns.prochainNoeud(ns.buildPour("HUNTER", "bete", "solo"), rangDe))
rangs[12] = 2
e, r2 = ns.prochainNoeud(ns.buildPour("HUNTER", "bete", "solo"), rangDe)
verifie("prochain nœud : dernier à moitié pris", 12, e.nodeID)
verifie("prochain nœud : rang 2 sur 3", 2, r2)
rangs[12] = 3
verifie("prochain nœud : tout est pris", nil, ns.prochainNoeud(ns.buildPour("HUNTER", "bete", "solo"), rangDe))
verifie("prochain nœud : build nil sans erreur", nil, ns.prochainNoeud(nil, rangDe))

-- ================================================================ builds sans numéro de nœud
-- L'arbre lu dans le jeu : des nœuds avec leurs entrées (entryID, spellID, nom dans la langue du jeu).
local noeudsArbre = {
  { nodeID = 101, entrees = { { entryID = 1001, spellID = 19577, nom = "Intimidation" } } },
  { nodeID = 102, entrees = { { entryID = 1002, spellID = 555, nom = "Frénésie" } } },
  { nodeID = 103, entrees = { { entryID = 1003, spellID = 556, nom = "Bestial Wrath" } } },
  { nodeID = 104, entrees = { { entryID = 1004, spellID = 557, nom = "Maître d’armes" }, { entryID = 1005, spellID = 558, nom = "Autre choix" } } },
}
local indexA = ns.indexArbre(noeudsArbre)
verifie("index de l'arbre : 4 nœuds lus", 4, indexA.nb)
verifie("index de l'arbre : par spellID", 102, indexA.parSpell[555].nodeID)
verifie("index de l'arbre : par nom simplifié, accents et casse ignorés", 102, indexA.parNom[ns.cleTalent("FRENESIE")].nodeID)
verifie("nom de talent : l'apostrophe courbe vaut l'apostrophe droite", ns.cleTalent("Maître d'armes"), ns.cleTalent("Maître d’armes"))
local resolu = ns.resoudreBuild({
  { sorts = { 19577 }, nom = "Mauvais nom", nomEN = "Faux", rangs = 1 },     -- par le spellID, même si le nom est faux
  { sorts = {}, nom = "FRÉNÉSIE", nomEN = "Frenzy", rangs = 5 },             -- par le nom français (accents et casse ignorés)
  { nom = "Courroux inconnu", nomEN = "Bestial Wrath", rangs = 1 },          -- par le nom anglais, le français n'existe pas
  { sorts = { 1 }, nom = "Talent fantôme", nomEN = "Ghost", rangs = 2 },     -- introuvable : sauté
  { nom = "Maître d'armes", rangs = 2 },                                      -- apostrophe droite contre courbe
  { nodeID = 9, rangs = 1 },                                                  -- la forme exacte reste acceptée
  { sorts = { 2 } },                                                          -- sans nom : « talent 7 »
}, indexA)
verifie("résolution : par spellID", 101, resolu.entrees[1] and resolu.entrees[1].nodeID)
verifie("résolution : par nom français", 102, resolu.entrees[2] and resolu.entrees[2].nodeID)
verifie("résolution : par nom anglais", 103, resolu.entrees[3] and resolu.entrees[3].nodeID)
verifie("résolution : l'entrée désigne l'entrée du nœud", 1003, resolu.entrees[3] and resolu.entrees[3].entryID)
verifie("résolution : par nom, apostrophe courbe", 104, resolu.entrees[4] and resolu.entrees[4].nodeID)
verifie("résolution : la forme { nodeID } passe telle quelle", 9, resolu.entrees[5] and resolu.entrees[5].nodeID)
verifie("résolution : le rang voulu est gardé", 5, resolu.entrees[2] and resolu.entrees[2].rangs)
verifie("résolution : les entrées introuvables sont comptées", 2, #resolu.nonReconnus)
verifie("résolution : leur nom est gardé pour l'affichage", "Talent fantôme", resolu.nonReconnus[1])
verifie("résolution : sans nom, une étiquette", "talent 7", resolu.nonReconnus[2])
verifie("résolution : sans arbre, rien n'est reconnu sauf la forme exacte", 1, #ns.resoudreBuild({ { nom = "Intimidation" }, { nodeID = 3 } }, nil).entrees)
verifie("résolution : build nil sans erreur", 0, #ns.resoudreBuild(nil, indexA).entrees)

-- Le prochain talent quand le palier n'est pas atteint : on passe à la suivante qui s'achète.
local rangsT = { [101] = 1, [102] = 0, [103] = 0, [104] = 0 }
local achetable = { [101] = true, [102] = false, [103] = true, [104] = true }
local suiv = { { nodeID = 101, rangs = 1 }, { nodeID = 102, rangs = 3 }, { nodeID = 103, rangs = 1 }, { nodeID = 104, rangs = 2 } }
local function rangT(id) return rangsT[id] end
local function peutT(id) return achetable[id] end
local e1, r1, place1 = ns.prochainNoeud(suiv, rangT, peutT)
verifie("prochain talent : le palier de la deuxième n'est pas atteint, on prend la troisième", 103, e1 and e1.nodeID)
verifie("prochain talent : sa place dans le build", 3, place1)
achetable[103], achetable[104] = false, false
local e2, _, _, bloque = ns.prochainNoeud(suiv, rangT, peutT)
verifie("prochain talent : aucun achetable, rien", nil, e2)
verifie("prochain talent : la première bloquée est rendue", 102, bloque and bloque.nodeID)
achetable[102] = true
verifie("prochain talent : le palier atteint, elle redevient la prochaine", 102, (ns.prochainNoeud(suiv, rangT, peutT) or {}).nodeID)
achetable[102] = nil -- le jeu ne dit rien (nil) : on essaie
verifie("prochain talent : achat inconnu (nil), on essaie", 102, (ns.prochainNoeud(suiv, rangT, peutT) or {}).nodeID)
verifie("prochain talent : sans fonction d'achat, comme avant", 102, (ns.prochainNoeud(suiv, rangT) or {}).nodeID)

-- Conditions ajoutées : points de combo, et « absent » pour un sort inconnu.
local apiCombo = { pointsCombo = function() return 4 end }
verifie("points de combo : 4 sur 5 requis, non", false, ns.evaluerCondition("pointsCombo>=5", "X", {}, apiCombo))
apiCombo.pointsCombo = function() return 5 end
verifie("points de combo : 5 sur 5 requis, oui", true, ns.evaluerCondition("pointsCombo>=5", "X", {}, apiCombo))
apiCombo.pointsCombo = function() return SECRET end
verifie("points de combo : valeur secrète, non évaluable", nil, ns.evaluerCondition("pointsCombo>=5", "X", {}, apiCombo))
verifie("points de combo : API absente, non évaluable", nil, ns.evaluerCondition("pointsCombo>=5", "X", {}, {}))
GetComboPoints = function() return jeu.combo end
jeu.combo = 3
verifie("api.pointsCombo : lit GetComboPoints", 3, ns.apiJeu.pointsCombo())
jeu.combo = SECRET
verifie("api.pointsCombo : secret = nil", nil, ns.apiJeu.pointsCombo())
GetComboPoints = nil
verifie("api.pointsCombo : ni GetComboPoints ni UnitPower = nil", nil, ns.apiJeu.pointsCombo())
verifie("absent pour un autre sort que tu ne connais pas : vrai", true,
  ns.evaluerCondition({ "buffAbsent", "INCONNU" }, "X", {}, { buffAbsent = function() return false end }))
verifie("debuffAbsent pour un autre sort inconnu : vrai", true,
  ns.evaluerCondition({ "debuffAbsent", "INCONNU" }, "X", {}, { debuffAbsent = function() return false end }))

-- Résolution d'un sort par son nom anglais (second repli)
local apiEN = { connu = function() return false end, nomSort = function() return nil end,
  chercherParNom = function(nom) if nom == "Serpent Sting Test" then return 4242 end end }
local sEN = ns.resoudreSort({ nom = "Faux nom", nomEN = "Serpent Sting Test", ids = {} }, apiEN)
verifie("sort : le nom français ne donne rien, le nom anglais oui", 4242, sEN and sEN.id)
verifie("sort : par l'index du grimoire, nom anglais", 77,
  (ns.resoudreSort({ nom = "Faux nom", nomEN = "Frost Test", ids = {} }, apiEN, { ["frost test"] = 77 }) or {}).id)
verifie("sort : ni l'un ni l'autre", nil, ns.resoudreSort({ nom = "Faux", nomEN = "Faux aussi", ids = {} }, apiEN, {}))

-- Une rotation de voleur de bout en bout : les points de combo décident entre le débondage, l'éviscération et le coup de base.
do
  local sortsV = {}
  for cle, def in pairs(D.SORTS.ROGUE) do sortsV[cle] = { id = def.ids[1] or 1, nom = def.nom, ids = {}, cle = cle } end
  local pts, debond = 0, true
  local apiV = {
    pret = function() return true end, buffAbsent = function(sp) return sp.cle == "DEBONDAGE" and debond or false end,
    debuffAbsent = function() return false end, ennemis = function() return 1 end,
    vie = function() return 100 end, pointsCombo = function() return pts end,
  }
  local listeV = D.ROTATIONS.ROGUE.combat
  pts, debond = 1, true
  verifie("voleur : 1 point, pas de débondage, on construit", "DELUGE", ns.evaluerRotation(listeV, sortsV, apiV).cle)
  pts, debond = 2, true
  verifie("voleur : 2 points sans débondage actif, débondage", "DEBONDAGE", ns.evaluerRotation(listeV, sortsV, apiV).cle)
  pts, debond = 5, false
  sortsV.DELUGE, sortsV.POUSSEE = nil, nil
  verifie("voleur : 5 points, débondage actif, éviscération", "EVISCERATION", ns.evaluerRotation(listeV, sortsV, apiV).cle)
  pts = 1
  verifie("voleur : 1 point, débondage actif, attaque de base", "SINISTRE", ns.evaluerRotation(listeV, sortsV, apiV).cle)
  -- Paladin de protection : le Sceau de piété attend, tant que le Sceau de fureur est connu et actif
  local sortsPP = {}
  for cle, def in pairs(D.SORTS.PALADIN) do sortsPP[cle] = { id = def.ids[1] or 1, nom = def.nom, ids = {}, cle = cle } end
  local actifs = { FUREUR = true, SCEAU_FUREUR = true }
  local apiPP = { pret = function() return false end, buffAbsent = function(sp) return not actifs[sp.cle] end,
    debuffAbsent = function() return false end, ennemis = function() return 1 end, vie = function() return 100 end }
  verifie("paladin protection : Sceau de fureur actif, pas de Sceau de piété", nil, ns.evaluerRotation(D.ROTATIONS.PALADIN.protection, sortsPP, apiPP).cle)
  actifs.SCEAU_FUREUR = nil
  verifie("paladin protection : plus de Sceau de fureur, on le refait", "SCEAU_FUREUR", ns.evaluerRotation(D.ROTATIONS.PALADIN.protection, sortsPP, apiPP).cle)
  sortsPP.SCEAU_FUREUR = nil -- Sceau de fureur inconnu (niveau trop bas) : le Sceau de piété prend la place
  verifie("paladin protection : sans Sceau de fureur, le Sceau de piété", "SCEAU_PIETE", ns.evaluerRotation(D.ROTATIONS.PALADIN.protection, sortsPP, apiPP).cle)
  -- Paladin de protection : Rempart du templier sous 40 % de vie (fiche), avant les sceaux
  local vieR = 30
  local apiPR = { pret = function(sp) return sp.cle == "REMPART" end, buffAbsent = function() return true end,
    debuffAbsent = function() return false end, ennemis = function() return 1 end, vie = function() return vieR end }
  verifie("paladin protection : sous 40 % de vie, le Rempart est une urgence, pas la rotation", "FUREUR", ns.evaluerRotation(D.ROTATIONS.PALADIN.protection, sortsPP, apiPR).cle)
  verifie("paladin protection : sous 40 % de vie, Rempart du templier en urgence", "REMPART", (ns.evaluerUrgence(D.ROTATIONS.PALADIN.protection, sortsPP, apiPR) or {}).cle)
  vieR = 80
  verifie("paladin protection : à 80 % de vie, pas d'urgence", nil, ns.evaluerUrgence(D.ROTATIONS.PALADIN.protection, sortsPP, apiPR))
  verifie("paladin protection : à 80 % de vie, pas de Rempart", "FUREUR", ns.evaluerRotation(D.ROTATIONS.PALADIN.protection, sortsPP, apiPR).cle)
  -- Paladin de protection : le Jugement passe avant le Bouclier sacré (ordre de la fiche)
  local apiPJ = { pret = function(sp) return sp.cle == "JUGEMENT" or sp.cle == "BOUCLIER_SACRE" end, buffAbsent = function() return false end,
    debuffAbsent = function() return false end, ennemis = function() return 1 end, vie = function() return 100 end }
  verifie("paladin protection : Jugement avant Bouclier sacré", "JUGEMENT", ns.evaluerRotation(D.ROTATIONS.PALADIN.protection, sortsPP, apiPJ).cle)
  -- Chaman restaurateur : pas de rotation de soins, seulement des sorts d'attaque
  local sortsSR = {}
  for cle, def in pairs(D.SORTS.SHAMAN) do sortsSR[cle] = { id = def.ids[1] or 1, nom = def.nom, ids = {}, cle = cle } end
  local apiSR = { pret = function() return true end, buffAbsent = function() return true end,
    debuffAbsent = function() return false end, ennemis = function() return 1 end, vie = function() return 100 end }
  verifie("chaman restauration : le sort d'attaque, jamais un soin", "ECLAIR", ns.evaluerRotation(D.ROTATIONS.SHAMAN.restauration, sortsSR, apiSR).cle)
end

-- ================================================================ résolution des sorts
local sorts = {}
local apiR = {
  connu = function(id) return sorts[id] == true end,
  nomSort = function(id) return jeu.noms and jeu.noms[id] end,
  chercherParNom = function(nom) return jeu.parNom and jeu.parNom[nom] end,
}
jeu.noms = { [1978] = "Morsure de serpent" }
sorts = { [1978] = true }
local s = ns.resoudreSort(D.SORTS.HUNTER.SERPENT, apiR)
verifie("sort : le rang le plus haut connu gagne (ici le plus bas)", 1978, s and s.id)
sorts = { [25295] = true, [1978] = true }
jeu.noms = { [25295] = "Morsure de serpent", [1978] = "Morsure de serpent" }
s = ns.resoudreSort(D.SORTS.HUNTER.SERPENT, apiR)
verifie("sort : plusieurs rangs connus, le plus haut", 25295, s and s.id)
verifie("sort : l'ensemble des rangs sert à reconnaître un effet", true, s and s.ids[13555])
sorts = {}
jeu.parNom = { ["Morsure de serpent"] = 99999 }
s = ns.resoudreSort(D.SORTS.HUNTER.SERPENT, apiR)
verifie("sort : aucun ID connu, trouvé par son nom", 99999, s and s.id)
verifie("sort : l'ID trouvé par le nom est reconnu aussi", true, s and s.ids[99999])
jeu.parNom = {}
verifie("sort : ni ID ni nom, absent", nil, ns.resoudreSort(D.SORTS.HUNTER.SERPENT, apiR))
sorts = { [75] = true, [14325] = true }
local tous = ns.resoudreSorts("HUNTER", apiR)
verifie("sorts : seuls les connus sont rendus", true, tous.AUTO ~= nil and tous.MARQUE ~= nil and tous.SERPENT == nil)
verifie("sorts : la clé est gardée", "MARQUE", tous.MARQUE.cle)
verifie("sorts : classe sans données", 0, (function() local n = 0 for _ in pairs(ns.resoudreSorts("MAGE", apiR)) do n = n + 1 end return n end)())

-- Le grimoire est parcouru une seule fois par résolution, les lignes hors spécialisation sont ignorées
local appelsGrimoire = 0
local apiG = {
  connu = function() return false end,
  nomSort = function() return nil end,
  grimoire = function()
    appelsGrimoire = appelsGrimoire + 1
    return { { spellID = 111, nom = "Morsure de serpent" }, { spellID = 222, nom = "Marque du chasseur", horsSpe = true },
      { spellID = 333, nom = "Tir automatique" } }
  end,
  chercherParNom = function() error("ne doit pas être appelé : le grimoire est déjà indexé") end,
}
local tG = ns.resoudreSorts("HUNTER", apiG)
verifie("grimoire : parcouru une seule fois pour tous les sorts", 1, appelsGrimoire)
verifie("grimoire : sort trouvé par son nom", 111, tG.SERPENT and tG.SERPENT.id)
verifie("grimoire : ligne hors spécialisation ignorée", nil, tG.MARQUE)
verifie("grimoire : indexGrimoire sans accents ni casse", 333, ns.indexGrimoire(apiG.grimoire())["tir automatique"])

-- ================================================================ moteur de priorité
local function sortsFaux(...)
  local t = {}
  for _, cle in ipairs({ ... }) do
    local def = D.SORTS.HUNTER[cle]
    t[cle] = { id = def.ids[1], nom = def.nom, ids = {}, cle = cle }
    for _, id in ipairs(def.ids) do t[cle].ids[id] = true end
  end
  return t
end
local etat = { pret = {}, debuffAbsent = {}, buffAbsent = {}, ennemis = 1, vie = 100, vieMoi = 100 }
local apiM = {
  pret = function(s) return etat.pret[s.cle] end,
  debuffAbsent = function(s) return etat.debuffAbsent[s.cle] end,
  buffAbsent = function(s) return etat.buffAbsent[s.cle] end,
  ennemis = function() return etat.ennemis end,
  vie = function(u) if u == "moi" then return etat.vieMoi end return etat.vie end,
}
local connus = sortsFaux("FAUCON", "MARQUE", "COURROUX", "ORDRE", "SERPENT", "ARCANES", "AUTO", "TIR_RAPIDE", "VISEE", "FUSILLADE")
local liste = D.ROTATIONS.HUNTER.bete
etat.buffAbsent.FAUCON = false; etat.debuffAbsent.MARQUE = false; etat.debuffAbsent.SERPENT = false
etat.pret = { COURROUX = false, ORDRE = false, ARCANES = false, MARQUE = true, SERPENT = true }
local res = ns.evaluerRotation(liste, connus, apiM)
verifie("rotation : tout est en place, reste le tir auto", "AUTO", res.cle)
verifie("rotation : pas illisible", false, res.illisible)
etat.debuffAbsent.MARQUE = true
res = ns.evaluerRotation(liste, connus, apiM)
verifie("rotation : marque absente et prête, on la pose", "MARQUE", res.cle)
etat.pret.MARQUE = false
res = ns.evaluerRotation(liste, connus, apiM)
verifie("rotation : marque pas prête, on passe", "AUTO", res.cle)
etat.pret.COURROUX = true
res = ns.evaluerRotation(liste, connus, apiM)
verifie("rotation : courroux prêt passe avant le reste", "COURROUX", res.cle)
verifie("rotation : mode A tant que lisible", "A", ns.modeEffectif(1, res.illisible))
etat.buffAbsent.FAUCON = true
res = ns.evaluerRotation(liste, connus, apiM)
verifie("rotation : l'aspect manquant est en tête", "FAUCON", res.cle)
-- un sort inconnu est sauté
res = ns.evaluerRotation(liste, sortsFaux("AUTO"), apiM)
verifie("rotation : sorts inconnus sautés", "AUTO", res.cle)
verifie("rotation : une seule ligne restante", 1, #res.lignes)
-- conditions chiffrées
local connusP = sortsFaux("FUSILLADE", "AUTO", "MARQUE")
local listeP = { { sort = "FUSILLADE", si = { "pret", "ennemisProches>=3" } }, { sort = "AUTO" } }
etat.pret = { FUSILLADE = true }
etat.ennemis = 2
verifie("ennemis : 2 sur 3 requis, non", "AUTO", ns.evaluerRotation(listeP, connusP, apiM).cle)
etat.ennemis = 3
verifie("ennemis : 3 sur 3 requis, oui", "FUSILLADE", ns.evaluerRotation(listeP, connusP, apiM).cle)
local listeV = { { sort = "FUSILLADE", si = { "vie<20" } }, { sort = "AUTO", si = { { "vie", "moi", 30 } } }, { sort = "MARQUE" } }
etat.vie, etat.vieMoi = 50, 80
verifie("vie : cible à 50 % et moi à 80 %, ni l'un ni l'autre", "MARQUE", ns.evaluerRotation(listeV, connusP, apiM).cle)
etat.vie = 10
verifie("vie : cible sous 20 %", "FUSILLADE", ns.evaluerRotation(listeV, connusP, apiM).cle)
etat.vie, etat.vieMoi = 50, 20
verifie("vie : moi sous 30 %", "AUTO", ns.evaluerRotation(listeV, connusP, apiM).cle)
-- valeurs illisibles : tout nil
local apiNil = { pret = function() return nil end, debuffAbsent = function() return nil end, buffAbsent = function() return nil end,
  ennemis = function() return nil end, vie = function() return nil end }
res = ns.evaluerRotation(liste, connus, apiNil)
verifie("tout illisible : rien n'est conseillé", nil, res.cle)
verifie("tout illisible : marqué illisible", true, res.illisible)
verifie("tout illisible : réglage auto passe au mode C", "C", ns.modeEffectif(1, res.illisible))
verifie("réglage forcé en A malgré l'illisible", "A", ns.modeEffectif(2, true))
verifie("réglage forcé en C même si lisible", "C", ns.modeEffectif(3, false))
verifie("la liste reste complète en mode C (11 lignes des sorts connus)", 11, #res.lignes)
-- Paladin : les urgences sont en tête, et Exorcisme demande un mort-vivant ou un démon
local lp = D.ROTATIONS.PALADIN.vindicte
verifie("paladin : Imposition des mains en tête", "IMPOSITION", lp[1].sort)
verifie("paladin : Bouclier divin juste après", "BOUCLIER_DIVIN", lp[2].sort)
for _, spe in ipairs({ "vindicte", "protection", "sacre" }) do
  verifie("paladin " .. spe .. " : urgence d'abord", "IMPOSITION", D.ROTATIONS.PALADIN[spe][1].sort)
end
local sortsP = {}
for cle, def in pairs(D.SORTS.PALADIN) do sortsP[cle] = { id = def.ids[1], nom = def.nom, ids = {}, cle = cle } end
local etatP = { pret = {}, buffAbsent = {}, debuffAbsent = {}, ennemis = 1, vie = 100, vieMoi = 10, type = "Humanoïde" }
local apiP = {
  pret = function(sp) return etatP.pret[sp.cle] end, buffAbsent = function(sp) return etatP.buffAbsent[sp.cle] end,
  debuffAbsent = function(sp) return etatP.debuffAbsent[sp.cle] end, ennemis = function() return etatP.ennemis end,
  vie = function(u) if u == "moi" then return etatP.vieMoi end return etatP.vie end, typeCible = function() return etatP.type end,
}
etatP.pret = { JUGEMENT = true, IMPOSITION = true, BOUCLIER_DIVIN = true, EXORCISME = true }
etatP.buffAbsent.SCEAU_AUTORITE = false
verifie("paladin à 10 % : la rotation ne montre pas l'Imposition", "JUGEMENT", ns.evaluerRotation(lp, sortsP, apiP).cle)
local resU = ns.evaluerRotation(lp, sortsP, apiP)
local urgenceDansLignes = false
for _, l in ipairs(resU.lignes) do if l.sort == "IMPOSITION" or l.sort == "BOUCLIER_DIVIN" then urgenceDansLignes = true end end
verifie("paladin à 10 % : aucune urgence dans les lignes de la rotation", false, urgenceDansLignes)
verifie("paladin à 10 % : l'urgence est l'Imposition des mains", "IMPOSITION", (ns.evaluerUrgence(lp, sortsP, apiP) or {}).cle)
etatP.pret.IMPOSITION = false
verifie("paladin à 10 %, Imposition en recharge : urgence Bouclier divin", "BOUCLIER_DIVIN", (ns.evaluerUrgence(lp, sortsP, apiP) or {}).cle)
verifie("paladin à 10 %, Imposition en recharge : la rotation reste le Jugement", "JUGEMENT", ns.evaluerRotation(lp, sortsP, apiP).cle)
etatP.vieMoi = SECRET
verifie("urgence : vie secrète, rien n'est signalé", nil, ns.evaluerUrgence(lp, sortsP, apiP))
etatP.vieMoi = 10
etatP.vieMoi = 90
verifie("paladin en forme : le Jugement", "JUGEMENT", ns.evaluerRotation(lp, sortsP, apiP).cle)
etatP.pret.JUGEMENT = false
verifie("exorcisme : cible humanoïde, refusé", nil, ns.evaluerRotation(lp, sortsP, apiP).cle)
etatP.type = "Mort-vivant"
verifie("exorcisme : mort-vivant", "EXORCISME", ns.evaluerRotation(lp, sortsP, apiP).cle)
etatP.type = "Démon"
verifie("exorcisme : démon", "EXORCISME", ns.evaluerRotation(lp, sortsP, apiP).cle)
etatP.type = "MORT-VIVANT"
verifie("exorcisme : casse ignorée", "EXORCISME", ns.evaluerRotation(lp, sortsP, apiP).cle)
verifie("typeCible : valeur secrète = non évaluable", nil, ns.evaluerCondition({ "typeCible", { "Démon" } }, "EXORCISME", sortsP, { typeCible = function() return SECRET end }))
verifie("typeCible : valeur absente = non évaluable", nil, ns.evaluerCondition({ "typeCible", { "Démon" } }, "EXORCISME", sortsP, { typeCible = function() return nil end }))
verifie("typeCible : API absente = non évaluable", nil, ns.evaluerCondition({ "typeCible", { "Démon" } }, "EXORCISME", sortsP, {}))
-- api.typeCible lit la vraie fonction du jeu
jeu.typeCreature = "Démon"
verifie("api.typeCible : lit UnitCreatureType", "Démon", ns.apiJeu.typeCible())
jeu.typeCreature = SECRET
verifie("api.typeCible : secret = nil", nil, ns.apiJeu.typeCible())
jeu.typeCreature = nil

-- une condition qui lève une erreur compte comme illisible, sans casser
local apiBoum = { pret = function() error("boum") end, debuffAbsent = apiNil.debuffAbsent, buffAbsent = apiNil.buffAbsent,
  ennemis = apiNil.ennemis, vie = apiNil.vie }
res = ns.evaluerRotation(liste, connus, apiBoum)
verifie("erreur dans l'API : illisible, pas de plantage", true, res.illisible)

-- Vraie lecture : valeurs secrètes de C_Spell / C_UnitAuras / UnitHealth
C_Spell.IsSpellUsable = function() return true end
C_Spell.GetSpellCooldown = function() return { startTime = SECRET, duration = SECRET } end
verifie("api.pret : recharge secrète = nil", nil, ns.apiJeu.pret({ id = 5 }))
C_Spell.GetSpellCooldown = function() return { startTime = 0, duration = 0 } end
verifie("api.pret : prêt", true, ns.apiJeu.pret({ id = 5 }))
C_Spell.GetSpellCooldown = function() return { startTime = 95, duration = 30 } end
verifie("api.pret : en recharge", false, ns.apiJeu.pret({ id = 5 }))
C_Spell.GetSpellCooldown = function() return { startTime = 90, duration = 10 } end
verifie("api.pret : recharge qui vient de finir", true, ns.apiJeu.pret({ id = 5 }))
C_Spell.GetSpellCooldown = function() return { startTime = 99, duration = 1.5 } end
verifie("api.pret : seulement la recharge commune", true, ns.apiJeu.pret({ id = 5 }))
C_Spell.IsSpellUsable = function() return false end
verifie("api.pret : inutilisable", false, ns.apiJeu.pret({ id = 5 }))
C_Spell.IsSpellUsable = function() return SECRET end
verifie("api.pret : utilisabilité secrète = nil", nil, ns.apiJeu.pret({ id = 5 }))
C_Spell.GetSpellCooldown = function() return nil end
C_Spell.IsSpellUsable = function() return true end
verifie("api.pret : sort inconnu du jeu = nil", nil, ns.apiJeu.pret({ id = 5 }))
verifie("api.pret : sans sort = nil", nil, ns.apiJeu.pret(nil))
local auras = {}
C_UnitAuras = { GetAuraDataByIndex = function(u, i) return auras[u] and auras[u][i] end }
auras.target = { { spellId = 1, name = "Autre" } }
verifie("api.debuffAbsent : l'effet n'y est pas", true, ns.apiJeu.debuffAbsent({ id = 5, nom = "Marque du chasseur", ids = { [5] = true } }))
auras.target = { { spellId = 1, name = "Autre" }, { spellId = 5, name = "Marque du chasseur" } }
verifie("api.debuffAbsent : l'effet est là (par l'ID)", false, ns.apiJeu.debuffAbsent({ id = 5, nom = "X", ids = { [5] = true } }))
auras.target = { { spellId = 77, name = "Marque du chasseur" } }
verifie("api.debuffAbsent : l'effet est là (par le nom)", false, ns.apiJeu.debuffAbsent({ id = 5, nom = "Marque du chasseur", ids = {} }))
auras.target = { { spellId = SECRET, name = SECRET } }
verifie("api.debuffAbsent : effet secret = nil", nil, ns.apiJeu.debuffAbsent({ id = 5, nom = "X", ids = {} }))
auras.player = {}
verifie("api.buffAbsent : sur moi, absent", true, ns.apiJeu.buffAbsent({ id = 5, nom = "X", ids = {} }))
function UnitHealth() return SECRET end
function UnitHealthMax() return 100 end
verifie("api.vie : vie secrète = nil", nil, ns.apiJeu.vie("cible"))
function UnitHealth() return 25 end
verifie("api.vie : 25 %", 25, ns.apiJeu.vie("cible"))

-- ================================================================ boutons de la barre
local boutons = { { cadre = "a", slot = 1 }, { cadre = "b", slot = 2 }, { cadre = "c", slot = 3 }, { cadre = "d", slot = 4 } }
local actions = { [1] = { "spell", 25295 }, [2] = { "item", 5 }, [3] = { "spell", 1978 }, [4] = { "spell", 4242 } }
jeu.noms = { [4242] = "Morsure de serpent" }
local apiB = {
  infoAction = function(slot) local a = actions[slot]; return a[1], a[2] end,
  nomSort = function(id) return jeu.noms[id] end,
  slotsDuSort = function() return { 1 } end,
}
local def = { id = 25295, nom = "Morsure de serpent", ids = { [25295] = true, [1978] = true } }
local trouves = ns.boutonsPourSort(def, boutons, apiB)
local slotsTrouves = {}
for _, b in ipairs(trouves) do slotsTrouves[#slotsTrouves + 1] = b.slot end
verifie("boutons : le bon sort (API), un autre rang, et le même nom", "1,3,4", table.concat(slotsTrouves, ","))
verifie("boutons : sans sort", 0, #ns.boutonsPourSort(nil, boutons, apiB))
actions[1] = { "spell", SECRET }
apiB.slotsDuSort = function() return nil end
trouves = ns.boutonsPourSort(def, boutons, apiB)
verifie("boutons : identifiant secret ignoré, sans erreur", 2, #trouves)

-- ================================================================ ordre des stats et métiers
verifie("stats : chasseur précision, agilité d'abord", "ITEM_MOD_AGILITY_SHORT", ns.ordreStats("HUNTER", "precision")[1])
verifie("stats : spé inconnue, repli sur la conseillée seul", "ITEM_MOD_AGILITY_SHORT", ns.ordreStats("HUNTER", "inconnue")[1])
verifie("stats : classe inconnue, repli général", "ITEM_MOD_STAMINA_SHORT", ns.ordreStats("BOUDIN", nil)[1])
verifie("métier : en cours de montée", true, contient(ns.aFaireMetier({ nom = "Minage", niveau = 40, plafond = 75 }, 12), "monte-le jusqu'à 75"))
verifie("métier : en retard", true, contient(ns.aFaireMetier({ nom = "Minage", niveau = 10, plafond = 75 }, 30), "en retard"))
verifie("métier : palier fini, niveau atteint", true, contient(ns.aFaireMetier({ nom = "Minage", niveau = 75, plafond = 75 }, 12), "maître du métier"))
verifie("métier : palier fini, niveau trop bas", true, contient(ns.aFaireMetier({ nom = "Minage", niveau = 75, plafond = 75 }, 5), "demande le niveau 10"))
verifie("métier : au maximum", true, contient(ns.aFaireMetier({ nom = "Minage", niveau = 300, plafond = 300 }, 60), "au maximum"))

-- ================================================================ les données
local TOUTES = { "HUNTER", "PALADIN", "WARRIOR", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local donneesOk = true
for _, cl in ipairs(TOUTES) do
  local cd = D.CLASSES[cl]
  local bon = cd ~= nil and D.STATS[cl] ~= nil
  if bon then
    for _, cle in ipairs(cd.ordre) do
      bon = bon and cd.specs[cle] ~= nil and D.STATS[cl][cle] ~= nil
    end
    for _, sit in ipairs({ "solo", "groupe" }) do bon = bon and type(cd.conseils[sit]) == "table" and #cd.conseils[sit] >= 3 end
    for _, sit in ipairs(D.SITUATIONS) do bon = bon and type(cd.raisons[sit]) == "string" end
    bon = bon and #cd.metiers == 3 and cd.specs[cd.choix.solo] ~= nil and cd.specs[cd.choix.groupe] ~= nil
    for role, cle in pairs(cd.parRole or {}) do bon = bon and cd.specs[cle] ~= nil and type(cd.raisons[role]) == "string" end
  end
  if not bon then io.write("   données incomplètes : " .. cl .. "\n") end
  donneesOk = donneesOk and bon
end
verifie("données : les 9 classes sont complètes", true, donneesOk)
-- Chaque classe : une spécialisation conseillée pour chaque situation, une priorité non vide pour chacune
-- de ses spécialisations, des sorts déclarés, des conseils seul et en groupe, un build dont chaque entrée a un nom.
D.BUILDS.HUNTER = BUILDS_CHASSEUR
local PROBLEMES = {}
local function probleme(cl, texte) PROBLEMES[#PROBLEMES + 1] = cl .. " : " .. texte end
local totalEntrees, totalBuilds = 0, 0
for _, cl in ipairs(TOUTES) do
  local cd = D.CLASSES[cl]
  local rotations = D.ROTATIONS[cl] or {}
  local sortsCl = D.SORTS[cl] or {}
  -- les sorts : un nom français, un nom anglais, des identifiants numériques
  for cle, def in pairs(sortsCl) do
    if type(def.nom) ~= "string" or def.nom == "" then probleme(cl, "sort " .. cle .. " sans nom français") end
    if type(def.nomEN) ~= "string" or def.nomEN == "" then probleme(cl, "sort " .. cle .. " sans nom anglais") end
    for _, id in ipairs(def.ids or {}) do if type(id) ~= "number" then probleme(cl, "sort " .. cle .. " : identifiant non numérique") end end
  end
  -- une spécialisation conseillée pour chaque situation, avec sa rotation
  for _, sit in ipairs(D.SITUATIONS) do
    local c = ns.speConseillee(cl, sit, nil)
    if not c or not c.cle then probleme(cl, "pas de spécialisation conseillée en " .. sit)
    elseif type(rotations[c.cle]) ~= "table" or #rotations[c.cle] == 0 then probleme(cl, "rotation vide pour " .. c.cle .. " (" .. sit .. ")") end
    if c and (type(c.raison) ~= "string" or c.raison == "") then probleme(cl, "pas de raison en " .. sit) end
  end
  -- le rôle qui manque
  for role, cle in pairs(cd.parRole or {}) do
    local c = ns.speConseillee(cl, "donjon", { manques = { role }, manque = role })
    if not c or c.cle ~= cle or c.parManque ~= role then probleme(cl, "rôle manquant " .. role .. " : " .. tostring(c and c.cle)) end
    if type(rotations[cle]) ~= "table" or #rotations[cle] == 0 then probleme(cl, "rotation vide pour " .. cle .. " (rôle " .. role .. ")") end
    if not ns.buildPour(cl, cle, "groupe") then probleme(cl, "pas de build de groupe pour " .. cle .. " (rôle " .. role .. ")") end
  end
  -- toutes les spécialisations ont une priorité dont chaque sort est déclaré
  for _, cle in ipairs(cd.ordre) do
    local l = rotations[cle]
    if type(l) ~= "table" or #l == 0 then probleme(cl, "pas de priorité pour " .. cle)
    else
      for i, entree in ipairs(l) do
        totalEntrees = totalEntrees + 1
        if not sortsCl[entree.sort] then probleme(cl, cle .. " #" .. i .. " : sort non déclaré " .. tostring(entree.sort)) end
        if type(entree.texte) ~= "string" or entree.texte == "" then probleme(cl, cle .. " #" .. i .. " sans texte") end
        for _, cond in ipairs(entree.si or {}) do
          if type(cond) == "table" and (cond[1] == "buffAbsent" or cond[1] == "debuffAbsent") and cond[2] and not sortsCl[cond[2]] then
            probleme(cl, cle .. " #" .. i .. " : condition sur un sort non déclaré " .. tostring(cond[2]))
          end
        end
      end
    end
  end
  -- les conseils seul et en groupe
  for _, sit in ipairs({ "solo", "groupe" }) do
    local titre, liste = ns.conseilsASavoir(cl, sit)
    if type(liste) ~= "table" or #liste < 3 then probleme(cl, "moins de 3 conseils " .. sit) end
  end
  -- les builds : montée de la spécialisation seul, groupe de celle du donjon ; chaque entrée a un nom
  local builds = { { cd.choix.solo, "solo" }, { cd.choix.donjon, "donjon" }, { cd.choix.groupe, "groupe" }, { cd.choix.raid, "raid" } }
  for _, b in ipairs(builds) do
    local l = ns.buildPour(cl, b[1], b[2])
    if b[2] == "solo" or b[2] == "donjon" then
      if not l then probleme(cl, "pas de build " .. b[2] .. " pour " .. tostring(b[1])) end
    end
    if l then
      totalBuilds = totalBuilds + 1
      for i, e in ipairs(l) do
        if type(e.nom) ~= "string" or e.nom == "" then probleme(cl, "build " .. b[1] .. " #" .. i .. " sans nom français") end
        if type(e.nomEN) ~= "string" or e.nomEN == "" then probleme(cl, "build " .. b[1] .. " #" .. i .. " sans nom anglais") end
        if type(e.rangs) ~= "number" or e.rangs < 1 then probleme(cl, "build " .. b[1] .. " #" .. i .. " sans rang") end
      end
    end
  end
  if type(D.DATES_BUILDS[cl]) ~= "string" or not D.DATES_BUILDS[cl]:match("^%d%d/%d%d/%d%d%d%d$") then probleme(cl, "date du build absente") end
end
for _, p in ipairs(PROBLEMES) do io.write("   " .. p .. "\n") end
verifie("données : chaque classe a une spécialisation, une priorité, des sorts déclarés et un build complets", 0, #PROBLEMES)
-- Aucune rotation ne contient de soin ou de défensif non marqué urgence (Paladin et Chasseur : toutes les spécialisations)
local MOTS_SOIN = { IMPOSITION = true, BOUCLIER_DIVIN = true, FEINDRE = true, DISSUASION = true, REMPART = true,
  LUMIERE_SACREE = true, ECLAIR_LUMINEUX = true }
local soinNonMarque = {}
for _, cl in ipairs({ "PALADIN", "HUNTER" }) do
  for spe, l in pairs(D.ROTATIONS[cl]) do
    for _, entree in ipairs(l) do
      if MOTS_SOIN[entree.sort] and not entree.urgence then soinNonMarque[#soinNonMarque + 1] = cl .. "/" .. spe .. "/" .. entree.sort end
    end
  end
end
verifie("rotations Paladin et Chasseur : aucun soin ni défensif non marqué urgence", 0, #soinNonMarque)
local soinPartout = {}
for cl, specs in pairs(D.ROTATIONS) do
  for spe, l in pairs(specs) do
    for _, entree in ipairs(l) do
      if (entree.sort:find("SOINS") or entree.sort == "VAGUE" or entree.sort == "VAGUE_MINEURE" or entree.sort == "RAJEUNISSEMENT"
        or entree.sort == "RETABLISSEMENT" or entree.sort == "TOUCHER_GUERISON") and not entree.urgence then
        soinPartout[#soinPartout + 1] = cl .. "/" .. spe .. "/" .. entree.sort
      end
    end
  end
end
verifie("rotations des 9 classes : aucun sort de soin non marqué urgence", 0, #soinPartout)
verifie("données : plus de 150 entrées de priorité écrites (" .. totalEntrees .. ")", true, totalEntrees > 150)
verifie("données : au moins 27 builds lus (" .. totalBuilds .. ")", true, totalBuilds >= 27)
local perso = false
local function cherche(t)
  for _, v in pairs(t) do
    if type(v) == "string" and (v:find("Valentin") or v:lower():find("frère") or v:lower():find("frere")) then perso = true
    elseif type(v) == "table" then cherche(v) end
  end
end
cherche(D)
verifie("données : rien de personnel dans les textes", false, perso)

-- ================================================================ chargement de bout en bout
local function evt(nom, ...)
  for _, f in ipairs(cadres) do
    if f._scripts.OnEvent and (f._evenements[nom] or nom == "ADDON_LOADED") then f._scripts.OnEvent(f, nom, ...) end
  end
end
jeu.classe, jeu.noms = "HUNTER", { [75] = "Tir automatique", [14325] = "Marque du chasseur" }
jeu.sortsConnus = { [75] = true, [14325] = true }
jeu.spe, jeu.nomSpe = 1, "Maîtrise des bêtes"
evt("ADDON_LOADED", "Conseiller")
verifie("chargement : la sauvegarde existe", "table", type(ConseillerDB))
verifie("chargement : réglages par défaut (rotation active)", true, ConseillerDB.rotation)
verifie("chargement : sorts résolus", true, ns.sorts.AUTO ~= nil and ns.sorts.MARQUE ~= nil)

-- Le build d'essai du chasseur (formes exactes), à la place des vrais builds rangés plus haut.
D.BUILDS.HUNTER = { bete = { solo = { { nodeID = 10, rangs = 2 }, { nodeID = 11, rangs = 1 }, { nodeID = 12, rangs = 3 } }, groupe = { { nodeID = 20, rangs = 1 } } } }
ns.talentsSale = true
local etatJeu = ns.construireEtat()
verifie("état : classe", "HUNTER", etatJeu.classe)
verifie("état : spécialisation lue dans le jeu", "bete", etatJeu.speCle)
verifie("état : seul", "solo", etatJeu.situation)
verifie("état : pas de bloc groupe seul", nil, etatJeu.groupe)
verifie("état : rotation de la bête chargée", true, etatJeu.rotation ~= nil)
verifie("état : build écrit mais nœuds absents de l'arbre", "horsArbre", etatJeu.talents.etat)
local tTalents = ns.vueTalents(etatJeu)
verifie("onglet Talents : spé conseillée", true, contient(tTalents, "Maîtrise des bêtes"))
verifie("onglet Talents : build hors arbre expliqué", true, contient(tTalents, "ne correspond pas"))

-- Nœud inexistant : autre identifiant renvoyé, ou aucun rang possible
jeu.noeuds = { [10] = { ID = 99, maxRanks = 2, currentRank = 0, entryIDs = {} }, [11] = { ID = 11, maxRanks = 0, currentRank = 0, entryIDs = {} } }
ns.talentsSale = true
verifie("talents : ID différent ou 0 rang = nœud absent", "horsArbre", ns.construireEtat().talents.etat)

-- Un build avec un nœud connu de l'arbre simulé
jeu.noeuds = { [10] = { ID = 10, maxRanks = 2, currentRank = 0, entryIDs = {} }, [11] = { ID = 11, maxRanks = 1, currentRank = 0, entryIDs = {} } }
ns.talentsSale = true
etatJeu = ns.construireEtat()
verifie("talents : prochain nœud 10", 10, etatJeu.talents.nodeID)
verifie("onglet Talents : prochain talent", true, contient(ns.vueTalents(etatJeu), "Prochain talent"))
ns.prendreTalent()
verifie("prendre un talent : un rang acheté", 1, jeu.noeuds[10].currentRank)
verifie("prendre un talent : validé", true, jeu.valide)
-- nœud à choix : l'entrée du build est sélectionnée avant l'achat
D.BUILDS.HUNTER = { bete = { solo = { { nodeID = 10, rangs = 2, entryID = 101 } } } }
jeu.noeuds[10].entryIDs = { 100, 101 }
jeu.noeuds[10].currentRank = 0
ns.talentsSale = true
ns.prendreTalent()
verifie("talent à choix : SetSelection appelé avec l'entryID du build", "10,101", jeu.selection and (jeu.selection[1] .. "," .. jeu.selection[2]))
verifie("talent à choix : rang acheté ensuite", 1, jeu.noeuds[10].currentRank)
-- La validation passe par C_Traits.CommitConfig (C_ClassTalents.CommitConfig attend une configuration
-- sauvegardée, pas la configuration active : il ne doit jamais être appelé), et un refus est dit
local messages = {}
local printAvant = print
print = function(t) messages[#messages + 1] = t end
local appelClasse = false
C_ClassTalents.CommitConfig = function() appelClasse = true; return true end
local commitAvant = C_Traits.CommitConfig
C_Traits.CommitConfig = function() return false end
ns.talentsSale = true
ns.prendreTalent()
print = printAvant
C_Traits.CommitConfig = commitAvant
C_ClassTalents.CommitConfig = nil
verifie("validation : jamais C_ClassTalents.CommitConfig", false, appelClasse)
verifie("validation refusée : message clair", true, contient(messages[#messages], "talent acheté, mais le jeu a refusé de valider"))
jeu.noeuds[10].currentRank = 1
D.BUILDS.HUNTER = { bete = { solo = { { nodeID = 10, rangs = 2 }, { nodeID = 11, rangs = 1 }, { nodeID = 12, rangs = 3 } } } }
jeu.noeuds[10].entryIDs = {}
jeu.enCombat = true
ns.prendreTalent()
verifie("prendre un talent : refusé en combat", 1, jeu.noeuds[10].currentRank)
jeu.enCombat = false
-- le jeu dit que les talents ne peuvent pas changer maintenant (CanEditTalents) : rien n'est acheté
C_ClassTalents.CanEditTalents = function() return false, "tu es dans une clé mythique" end
ns.prendreTalent()
verifie("prendre un talent : refusé quand le jeu l'interdit", 1, jeu.noeuds[10].currentRank)
C_ClassTalents.CanEditTalents = nil
D.BUILDS.HUNTER = {}
verifie("talents : plus de build écrit", "vide", ns.construireEtat().talents.etat)
verifie("onglet Talents : message clair quand le build manque", true, contient(ns.vueTalents(ns.construireEtat()), "/cs export"))
jeu.config = nil
D.BUILDS.HUNTER = { bete = { solo = { { nodeID = 10, rangs = 2 } } } }
verifie("talents : pas de configuration active", "sansArbre", ns.construireEtat().talents.etat)
jeu.config = 77

-- Export
jeu.noeuds[10].posX, jeu.noeuds[10].posY, jeu.noeuds[10].entryIDs = 1, 2, { 100 }
C_Traits.GetConfigInfo = function() return { treeIDs = { 5 } } end
C_Traits.GetTreeNodes = function() return { 10, 11 } end
C_Traits.GetEntryInfo = function(_, id) return { definitionID = id + 1 } end
C_Traits.GetDefinitionInfo = function(id) return { spellID = 75 } end
ns.exporter()
verifie("export : l'arbre est écrit dans la sauvegarde", 2, ConseillerDB.export and #ConseillerDB.export.noeuds)
verifie("export : le sort d'un nœud est nommé", "Tir automatique", ConseillerDB.export.noeuds[1].entrees[1] and ConseillerDB.export.noeuds[1].entrees[1].nom)
verifie("export : classe et situation notées", "HUNTER", ConseillerDB.export.classe)
verifie("export : le grimoire est écrit", 2, #ConseillerDB.export.grimoire)
verifie("grimoire : retrouver un sort par son nom, sans accents", 3045, ns.apiJeu.chercherParNom("TIR RAPIDE"))

-- Un build écrit sans numéro de nœud : lu dans l'arbre par spellID, par nom français, par nom anglais ;
-- les talents introuvables sont comptés, montrés, nommés dans /cs etat ; un palier pas atteint est sauté.
do
  local sauveNoms, sauveBuild = jeu.noms, D.BUILDS.HUNTER
  local sauveEntry, sauveDef = C_Traits.GetEntryInfo, C_Traits.GetDefinitionInfo
  local sauveConfig, sauveNodes, sauveNoeuds = C_Traits.GetConfigInfo, C_Traits.GetTreeNodes, jeu.noeuds
  local spellParEntree = { [1001] = 19577, [1002] = 555, [1003] = 556, [1004] = 557 }
  jeu.noms = { [19577] = "Intimidation", [555] = "Frénésie", [556] = "Bestial Wrath", [557] = "Rapidité bestiale" }
  C_Traits.GetConfigInfo = function() return { treeIDs = { 5 } } end
  C_Traits.GetTreeNodes = function() return { 101, 102, 103, 104 } end
  C_Traits.GetEntryInfo = function(_, id) return { definitionID = id + 5000 } end
  C_Traits.GetDefinitionInfo = function(id) return { spellID = spellParEntree[id - 5000] } end
  jeu.noeuds = {
    [101] = { ID = 101, maxRanks = 1, currentRank = 1, entryIDs = { 1001 } },
    [102] = { ID = 102, maxRanks = 3, currentRank = 0, entryIDs = { 1002 }, canPurchaseRank = false }, -- palier pas atteint
    [103] = { ID = 103, maxRanks = 1, currentRank = 0, entryIDs = { 1003 }, canPurchaseRank = true },
    [104] = { ID = 104, maxRanks = 2, currentRank = 0, entryIDs = { 1004 }, canPurchaseRank = false },
  }
  D.BUILDS.HUNTER = { bete = { solo = {
    { sorts = { 19577 }, nom = "Faux nom", nomEN = "Faux", rangs = 1 },
    { sorts = {}, nom = "Frénésie", nomEN = "Frenzy", rangs = 5 },
    { nom = "Courroux inconnu", nomEN = "Bestial Wrath", rangs = 1 },
    { nom = "Talent fantôme", nomEN = "Ghost", rangs = 2 },
    { nom = "Rapidité bestiale", nomEN = "Bestial Swiftness", rangs = 1 },
    { nom = "Autre fantôme", nomEN = "Ghost 2", rangs = 1 },
  } } }
  ns.arbreSale = true
  ns.talentsSale = true
  local eT = ns.construireEtat()
  verifie("talents sans nœud : prochain, le palier de la 2e n'est pas atteint", 103, eT.talents.nodeID)
  verifie("talents sans nœud : état « suivant »", "suivant", eT.talents.etat)
  verifie("talents sans nœud : son nom, dans la langue du jeu", "Bestial Wrath", eT.talents.nom)
  verifie("talents sans nœud : deux talents non reconnus comptés", 2, eT.talents.nbNonReconnus)
  verifie("talents sans nœud : leurs noms", "Talent fantôme,Autre fantôme", table.concat(eT.talents.nonReconnus, ","))
  local vT = ns.vueTalents(eT)
  verifie("onglet Talents : « 2 talents du build n'ont pas été reconnus »", true, contient(vT, "2 talents du build n'ont pas été reconnus"))
  verifie("onglet Talents : renvoie à /cs export", true, contient(vT, "/cs export"))
  verifie("onglet Talents : la date du build", true, contient(vT, "Build croisé entre plusieurs guides, mis à jour le 10/11/2026"))
  verifie("onglet Talents : les noms non reconnus", true, contient(vT, "Talent fantôme, Autre fantôme"))
  -- un seul talent non reconnu : singulier
  D.BUILDS.HUNTER.bete.solo[6] = nil
  ns.talentsSale = true
  verifie("onglet Talents : « 1 talent du build n'a pas été reconnu »", true, contient(ns.vueTalents(ns.construireEtat()), "1 talent du build n'a pas été reconnu"))
  -- /cs etat liste les noms
  local dits = {}
  local printAvantT = print
  print = function(t) dits[#dits + 1] = t end
  SlashCmdList.CONSEILLER("etat")
  print = printAvantT
  local ditNoms = false
  for _, d in ipairs(dits) do if contient(d, "non reconnus (1)") and contient(d, "Talent fantôme") then ditNoms = true end end
  verifie("/cs etat : liste les talents non reconnus", true, ditNoms)
  -- on prend le talent : un rang acheté sur le nœud 103
  ns.prendreTalent()
  verifie("prendre le talent sans nœud : rang acheté sur le bon nœud", 1, jeu.noeuds[103].currentRank)
  -- le suivant n'est pas encore achetable : état « attente », avec le nom du premier bloqué
  ns.talentsSale = true
  local eA = ns.construireEtat()
  verifie("talents : plus rien d'achetable, état « attente »", "attente", eA.talents.etat)
  verifie("talents : le premier bloqué est nommé", "Frénésie", eA.talents.nom)
  verifie("onglet Talents : l'attente est expliquée", true, contient(ns.vueTalents(eA), "palier pas atteint"))
  -- le palier est atteint : la Frénésie devient la prochaine, son rang voulu (5) est ramené au maximum du nœud (3)
  jeu.noeuds[102].canPurchaseRank = true
  jeu.noeuds[102].currentRank = 3
  jeu.noeuds[104].canPurchaseRank = true
  ns.talentsSale = true
  verifie("talents : rang voulu au-dessus du maximum du nœud, ramené au maximum (la suivante prend le relais)", 104, ns.construireEtat().talents.nodeID)
  jeu.noeuds[104].currentRank = 1
  jeu.noeuds[104].canPurchaseRank = false
  ns.talentsSale = true
  verifie("talents : tout ce qui est reconnu est pris, état « fini »", "fini", ns.construireEtat().talents.etat)
  -- aucun talent reconnu : état « horsArbre »
  D.BUILDS.HUNTER.bete.solo = { { nom = "Inconnu 1", nomEN = "Unknown 1", rangs = 1 }, { nom = "Inconnu 2", nomEN = "Unknown 2", rangs = 1 } }
  ns.talentsSale = true
  local eH = ns.construireEtat()
  verifie("talents : aucun reconnu, état « horsArbre »", "horsArbre", eH.talents.etat)
  verifie("talents : aucun reconnu, tous comptés", 2, eH.talents.nbNonReconnus)
  verifie("onglet Talents : aucun reconnu, message clair", true, contient(ns.vueTalents(eH), "aucun de ses talents n'a été reconnu"))
  -- l'arbre est gardé tant qu'il ne change pas : une seule lecture
  local lectures = 0
  C_Traits.GetTreeNodes = function() lectures = lectures + 1; return { 101, 102, 103, 104 } end
  ns.arbreSale = true
  ns.construireEtat(); ns.construireEtat(); ns.construireEtat()
  verifie("arbre : lu une seule fois, gardé ensuite", 1, lectures)
  ns.arbreSale = true
  ns.construireEtat()
  verifie("arbre : relu quand il est marqué à refaire", 2, lectures)

  jeu.noms, D.BUILDS.HUNTER, jeu.noeuds = sauveNoms, sauveBuild, sauveNoeuds
  C_Traits.GetEntryInfo, C_Traits.GetDefinitionInfo = sauveEntry, sauveDef
  C_Traits.GetConfigInfo, C_Traits.GetTreeNodes = sauveConfig, sauveNodes
  ns.arbreSale = true
  ns.talentsSale = true
end

-- Rotation, équipement, métiers, race
local tRot = ns.vueRotation(etatJeu)
verifie("onglet Rotation : l'ordre de priorité", true, contient(tRot, "Ordre de priorité"))
verifie("onglet Rotation : à savoir seul", true, contient(tRot, "Seul : à savoir"))
jeu.classe, jeu.spe, jeu.nomSpe = "MAGE", 2, "Feu"
evt("PLAYER_SPECIALIZATION_CHANGED")
local rotationMage = D.ROTATIONS.MAGE
D.ROTATIONS.MAGE = nil -- une classe dont la rotation manquerait : message propre, sans erreur
local tMage = ns.vueRotation(ns.construireEtat())
D.ROTATIONS.MAGE = rotationMage
verifie("rotation écrite pour le mage (Feu)", true, contient(ns.vueRotation(ns.construireEtat()), "Ordre de priorité"))
verifie("rotation pas écrite : message propre", true, contient(tMage, "Rotation pas encore écrite pour Mage, Feu"))
verifie("rotation pas écrite : les conseils restent", true, contient(tMage, "Seul : à savoir"))
verifie("équipement : mage feu, puissance des sorts d'abord", true, contient(ns.vueEquipement(ns.construireEtat()), "Puissance des sorts  >"))
verifie("Conseiller_OrdreStats : copie de l'ordre", "ITEM_MOD_SPELL_POWER_SHORT", Conseiller_OrdreStats()[1])
jeu.classe, jeu.spe, jeu.nomSpe = "HUNTER", 1, "Maîtrise des bêtes"
evt("PLAYER_SPECIALIZATION_CHANGED")
jeu.metiers = { 1, 2 }
jeu.infosMetiers = { [1] = { nom = "Dépeçage", niveau = 60, plafond = 75 }, [2] = { nom = "Travail du cuir", niveau = 75, plafond = 75 } }
local tMetiers = ns.vueMetiers(ns.construireEtat())
verifie("onglet Métiers : 3 propositions", true, contient(tMetiers, "[Conseillé]") and contient(tMetiers, "[Pour l'or]"))
verifie("onglet Métiers : à faire maintenant", true, contient(tMetiers, "Dépeçage 60/75"))
verifie("onglet Race : orc", true, contient(ns.vueRace(ns.construireEtat()), "Fureur sanguinaire"))
jeu.raceToken, jeu.raceNom = "Inconnue", "Race à venir"
verifie("onglet Race : race inconnue, message de repli", true, contient(ns.vueRace(ns.construireEtat()), "Race à venir"))

-- Druide : le rang 3 est Gardien sur Retail (4 spécialisations), Restauration sur Forever (3)
jeu.classe, jeu.spe, jeu.nomSpe, jeu.nbSpes = "DRUID", 3, nil, 4
evt("PLAYER_SPECIALIZATION_CHANGED")
verifie("druide Retail : le rang 3 est Gardien", "gardien", ns.construireEtat().speCle)
jeu.nbSpes = 3
verifie("druide Forever : le rang 3 est Restauration", "restauration", ns.construireEtat().speCle)
jeu.nbSpes = nil
jeu.classe, jeu.spe, jeu.nomSpe = "HUNTER", 1, "Maîtrise des bêtes"
evt("PLAYER_SPECIALIZATION_CHANGED")

-- Situations : entrer en groupe, rôle manquant, donjon
jeu.groupe = true
jeu.membres = { { role = "HEALER", classe = "PRIEST" }, { role = "DAMAGER", classe = "MAGE" }, { role = "DAMAGER", classe = "ROGUE" }, { role = "DAMAGER", classe = "MAGE" } }
evt("GROUP_ROSTER_UPDATE")
local eg = ns.construireEtat()
verifie("groupe : situation détectée", "groupe", eg.situation)
verifie("groupe : le tank manque", "tank", eg.groupe and eg.groupe.manque)
verifie("groupe : le chasseur reste en maîtrise des bêtes", "bete", eg.conseil.cle)
local tg = ns.vueTalents(eg)
verifie("onglet Talents : bloc « Ton groupe »", true, contient(tg, "Ton groupe") and contient(tg, "Il manque un tank"))
verifie("onglet Talents : ta classe ne peut pas le jouer", true, contient(tg, "ta classe ne peut pas le jouer"))
verifie("onglet Rotation : à savoir en groupe", true, contient(ns.vueRotation(eg), "En groupe : à savoir"))
verifie("onglet Rotation : pas de message de soins pour un chasseur", false, contient(ns.vueRotation(eg), "Spécialisation de soins"))
do
  local eU = ns.construireEtat()
  eU.rotation.urgences = { "Feindre la mort", "Dissuasion" }
  verifie("onglet Rotation : « En cas de danger » nomme les sorts d'urgence", true, contient(ns.vueRotation(eU), "En cas de danger : Feindre la mort, Dissuasion."))
  eU.rotation.urgences = {}
  verifie("onglet Rotation : sans urgence connue, pas de ligne", false, contient(ns.vueRotation(eU), "En cas de danger"))
end
-- valeurs secrètes dans le groupe : rôle NONE, classe inconnue, sans erreur
jeu.membres = { { role = SECRET, classe = SECRET }, { role = "HEALER", classe = "PRIEST" }, { role = "DAMAGER", classe = "MAGE" }, { role = "DAMAGER", classe = "MAGE" } }
evt("GROUP_ROSTER_UPDATE")
verifie("groupe : rôle et classe secrets, rôle deviné sans erreur", true, ns.construireEtat().groupe ~= nil and ns.construireEtat().groupe.devine)
jeu.roleMoi = SECRET
evt("GROUP_ROSTER_UPDATE")
verifie("groupe : ton propre rôle secret, sans erreur", true, ns.construireEtat().groupe ~= nil)
jeu.roleMoi = nil
jeu.membres = { { role = "HEALER", classe = "PRIEST" }, { role = "DAMAGER", classe = "MAGE" }, { role = "DAMAGER", classe = "ROGUE" }, { role = "DAMAGER", classe = "MAGE" } }
jeu.classe, jeu.spe, jeu.nomSpe = "PALADIN", 3, "Vindicte"
jeu.roleMoi = nil
evt("GROUP_ROSTER_UPDATE")
eg = ns.construireEtat()
verifie("paladin vindicte, sans tank : conseille protection", "protection", eg.conseil.cle)
verifie("paladin : le texte propose de jouer le rôle", true, contient(ns.vueTalents(eg), "tu peux le jouer en Protection"))
jeu.spe, jeu.nomSpe = 2, "Protection"
evt("PLAYER_SPECIALIZATION_CHANGED")
eg = ns.construireEtat()
verifie("paladin protection : tu es le tank, plus rien ne manque", nil, eg.groupe and eg.groupe.manque)
jeu.typeInstance = "party"
evt("PLAYER_ENTERING_WORLD")
verifie("donjon : situation détectée", "donjon", ns.construireEtat().situation)
jeu.typeInstance, jeu.groupe, jeu.membres = "none", false, {}
evt("GROUP_ROSTER_UPDATE")
verifie("retour seul : situation solo", "solo", ns.construireEtat().situation)
ns.situationForcee = "raid"
verifie("vue forcée : raid, sans groupe inventé", nil, ns.construireEtat().groupe)
verifie("vue forcée : la spécialisation conseillée suit", "vindicte", ns.construireEtat().conseil.cle)
ns.situationForcee = nil

-- Spécialisations de soins : pas de rotation de soins, une phrase claire, les conseils restent
for _, cas in ipairs({ { "PALADIN", 1, "Sacré" }, { "PRIEST", 1, "Discipline" }, { "PRIEST", 2, "Sacré" }, { "SHAMAN", 3, "Restauration" }, { "DRUID", 3, "Restauration" } }) do
  jeu.classe, jeu.spe, jeu.nomSpe, jeu.nbSpes = cas[1], cas[2], cas[3], (cas[1] == "DRUID") and 3 or nil
  evt("PLAYER_SPECIALIZATION_CHANGED")
  local tS = ns.vueRotation(ns.construireEtat())
  verifie("spé de soins " .. cas[1] .. " " .. cas[3] .. " : message clair", true, contient(tS, "Spécialisation de soins : il n'y a pas d'ordre fixe"))
  verifie("spé de soins " .. cas[1] .. " " .. cas[3] .. " : sorts d'attaque et conseils", true, contient(tS, "Sorts d'attaque") and contient(tS, "à savoir"))
end
jeu.classe, jeu.spe, jeu.nomSpe, jeu.nbSpes = "HUNTER", 1, "Maîtrise des bêtes", nil
evt("PLAYER_SPECIALIZATION_CHANGED")

-- La fenêtre : tous les onglets s'affichent sans erreur
for _, f in ipairs(cadres) do if f._nom == "ConseillerFenetre" then rawset(f, "IsShown", function() return true end) end end
local fenetreOk = true
for i = 1, #ns.ONGLETS do
  local bon, err = pcall(ns.fenetre.onglet, i)
  if not bon then fenetreOk = false; io.write("   onglet " .. i .. " : " .. tostring(err) .. "\n") end
  local bonTexte, t = pcall(ns.ONGLETS[i][3], ns.construireEtat())
  fenetreOk = fenetreOk and bonTexte and type(t) == "string" and #t > 20
end
verifie("fenêtre : les 5 onglets s'affichent", true, fenetreOk and #ns.ONGLETS == 5)

-- Commandes
verifie("commande /cs mode c", nil, (function() SlashCmdList.CONSEILLER("mode c") return nil end)())
verifie("commande /cs mode c : réglage posé", 3, ConseillerDB.modeRotation)
SlashCmdList.CONSEILLER("mode auto")
verifie("commande /cs mode auto", 1, ConseillerDB.modeRotation)
verifie("réglage alerteUrgence : coupé par défaut", false, ConseillerDB.alerteUrgence)
verifie("commandes déclarées", "/cs", SLASH_CONSEILLER2)


-- ================================================================ Forever : l'export réel d'un paladin niveau 16
-- Un seul arbre (1100) partagé en trois groupes : la spécialisation est le groupe où l'on a le plus de points.
do
  -- Décision pure
  local function gr(nom, ordre, depense, id) return { groupID = id or ordre, displayName = nom, orderIndex = ordre, depense = depense } end
  local r = ns.speParGroupes("PALADIN", { gr("Sacré", 0, 0), gr("Protection", 1, 1), gr("Vindicte", 2, 5) })
  verifie("groupes : le plus de points gagne", "vindicte", r and r.cle)
  verifie("groupes : le nom du jeu est gardé", "Vindicte", r and r.nom)
  verifie("groupes : trois lignes de points", 3, r and #r.points)
  r = ns.speParGroupes("PALADIN", { gr("Vindicte", 2, 5), gr("Sacré", 0, 0), gr("Protection", 1, 1) })
  verifie("groupes : l'ordre des lignes n'importe pas", "vindicte", r and r.cle)
  r = ns.speParGroupes("PALADIN", { gr("Sacré", 0, 3), gr("Protection", 1, 3), gr("Vindicte", 2, 1) })
  verifie("groupes : égalité en tête, pas de spécialisation", nil, r and r.cle)
  verifie("groupes : égalité signalée", true, r and r.egalite)
  r = ns.speParGroupes("PALADIN", { gr("Sacré", 0, 0), gr("Protection", 1, 0), gr("Vindicte", 2, 0) })
  verifie("groupes : zéro point, pas de spécialisation", nil, r and r.cle)
  r = ns.speParGroupes("PALADIN", { gr("Groupe A", 4, 0), gr("Groupe B", 5, 2), gr("Groupe C", 6, 0) })
  verifie("groupes : nom inconnu, reconnu par son rang (2e = Protection)", "protection", r and r.cle)
  r = ns.speParGroupes("PALADIN", { gr("Groupe A", 10, 0), gr("Groupe B", 11, 0), gr("Groupe C", 12, 4) })
  verifie("groupes : nom inconnu, 3e = Vindicte", "vindicte", r and r.cle)
  verifie("groupes : un seul groupe, ancienne méthode", nil, ns.speParGroupes("PALADIN", { gr("Sacré", 0, 5) }))
  verifie("groupes : aucun groupe, ancienne méthode", nil, ns.speParGroupes("PALADIN", nil))

  -- L'export réel
  local env = {}
  local chargeur = assert(loadfile(dossier .. "../tests/donnees/export-paladin-forever.lua"))
  setfenv(chargeur, env)
  chargeur()
  local export = env.ConseillerDB.export
  verifie("export réel : 51 nœuds", 51, #export.noeuds)

  local groupeDeX = function(x) return x <= 2820 and 1 or (x <= 6820 and 2 or 3) end
  local noeudsParID, entreeParID = {}, {}
  for _, n in ipairs(export.noeuds) do
    noeudsParID[n.nodeID] = n
    for _, en in ipairs(n.entrees) do entreeParID[en.entryID] = { noeud = n, spellID = en.spellID } end
  end
  -- Le personnage : 5 points en Vindicte (Bénédiction), 1 en Protection (Redoute), 1 point libre.
  local rangs = {}
  for _, n in ipairs(export.noeuds) do rangs[n.nodeID] = n.rang or 0 end
  local function depense(g)
    local t = 0
    for _, n in ipairs(export.noeuds) do if groupeDeX(n.posX) == g then t = t + (rangs[n.nodeID] or 0) end end
    return t
  end
  local libres = 1
  local function achetable(n)
    local ligne = math.floor((n.posY - 2130) / 600 + 0.5)
    return libres > 0 and (rangs[n.nodeID] or 0) < n.maxRanks and depense(groupeDeX(n.posX)) >= 5 * ligne
  end

  -- Sauvegarde des fausses API de l'essai précédent
  local NOMS_API = { "GetNodeInfo", "GetConfigInfo", "GetTreeNodes", "GetEntryInfo", "GetDefinitionInfo",
    "GetGroupDisplayInfoByTreeID", "GetGroupCurrencyInfo" }
  local sauve = { C_Traits = {}, noms = jeu.noms, sorts = jeu.sortsConnus, classe = jeu.classe, niveau = jeu.niveau,
    spe = jeu.spe, nomSpe = jeu.nomSpe, config = jeu.config, noeuds = jeu.noeuds, grimoire = C_SpellBook.GetSpellBookItemInfo,
    numLignes = C_SpellBook.GetSpellBookSkillLineInfo, psf = PlayerSpellsFrame }
  for _, k in ipairs(NOMS_API) do sauve.C_Traits[k] = C_Traits[k] end

  jeu.classe, jeu.niveau, jeu.config = "PALADIN", 16, export.configID
  jeu.spe, jeu.nomSpe = 1, "Sacré" -- GetSpecialization rend 1 sur Forever : le jeu de talents « Principale », pas une spécialisation
  jeu.noms, jeu.sortsConnus = {}, {}
  for _, s in ipairs(export.grimoire) do jeu.noms[s.spellID] = s.nom; jeu.sortsConnus[s.spellID] = true end
  for _, n in ipairs(export.noeuds) do for _, en in ipairs(n.entrees) do jeu.noms[en.spellID] = en.nom end end
  C_SpellBook.GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #export.grimoire } end
  C_SpellBook.GetSpellBookItemInfo = function(i)
    local s = export.grimoire[i]
    return s and { spellID = s.spellID, name = s.nom, subName = s.sousTexte } or nil
  end
  C_Traits.GetConfigInfo = function() return { treeIDs = { 1100 } } end
  C_Traits.GetTreeNodes = function()
    local ids = {}
    for _, n in ipairs(export.noeuds) do ids[#ids + 1] = n.nodeID end
    return ids
  end
  C_Traits.GetNodeInfo = function(_, id)
    local n = noeudsParID[id]
    if not n then return nil end
    local eids = {}
    for _, en in ipairs(n.entrees) do eids[#eids + 1] = en.entryID end
    local ok = achetable(n)
    return { ID = id, maxRanks = n.maxRanks, currentRank = rangs[id], ranksPurchased = rangs[id], entryIDs = eids,
      posX = n.posX, posY = n.posY, canPurchaseRank = ok, isAvailable = ok, groupIDs = { groupeDeX(n.posX) } }
  end
  C_Traits.GetEntryInfo = function(_, entryID) return { definitionID = entryID } end
  C_Traits.GetDefinitionInfo = function(defID) return { spellID = entreeParID[defID].spellID } end
  local ordreGroupes = { 0, 1, 2 }
  C_Traits.GetGroupDisplayInfoByTreeID = function()
    return { { groupID = 1, treeID = 1100, orderIndex = ordreGroupes[1], displayName = "Sacré" },
      { groupID = 2, treeID = 1100, orderIndex = ordreGroupes[2], displayName = "Protection" },
      { groupID = 3, treeID = 1100, orderIndex = ordreGroupes[3], displayName = "Vindicte" } }
  end
  C_Traits.GetGroupCurrencyInfo = function(_, ids)
    local l = {}
    for _, id in ipairs(ids) do l[#l + 1] = { traitNodeGroupID = id, currencyInfos = { { spent = depense(id) } } } end
    return l
  end
  local function relire()
    ns.speSale, ns.arbreSale, ns.talentsSale = true, true, true
    evt("SPELLS_CHANGED")
    return ns.construireEtat()
  end

  local e = relire()
  verifie("export réel : 5 points en Vindicte", 5, depense(3))
  verifie("export réel : la spécialisation vient des points (Vindicte), pas de GetSpecialization (Sacré)", "vindicte", e.speCle)
  verifie("export réel : nom de la spécialisation", "Vindicte", e.speNom)
  verifie("export réel : points par groupe lus", "Sacré 0, Protection 1, Vindicte 5", (function()
    local t = {}
    for _, p in ipairs(e.groupesTalents.points) do t[#t + 1] = p.nom .. " " .. p.depense end
    return table.concat(t, ", ")
  end)())
  verifie("export réel : le build utilisé est celui de Vindicte", "vindicte", e.talents.speBuild)
  verifie("export réel : le prochain talent existe (état « suivant »)", "suivant", e.talents.etat)
  local noeudSuivant = noeudsParID[e.talents.nodeID]
  verifie("export réel : le prochain talent est un talent de Vindicte", 3, noeudSuivant and groupeDeX(noeudSuivant.posX))
  verifie("export réel : le prochain talent est achetable", true, noeudSuivant and achetable(noeudSuivant))
  verifie("export réel : le prochain talent", "Jugement sanctifié", e.talents.nom)
  verifie("export réel : aucun talent du build non reconnu", 0, e.talents.nbNonReconnus)

  -- Chaque entrée de chacun des trois builds se résout, au bon groupe, avec des rangs possibles, dans l'ordre des paliers
  local index = ns.indexArbre(ns.lireArbre(export.configID))
  verifie("arbre réel : 51 nœuds lus", 51, index.nb)
  local voulu = { vindicte = 3, protection = 2, sacre = 1 }
  for cle, groupe in pairs(voulu) do
    local build = D.BUILDS.PALADIN[cle].groupe
    local res = ns.resoudreBuild(build, index)
    verifie("build " .. cle .. " : 100 % des entrées reconnues (" .. #build .. ")", #build, #res.entrees)
    verifie("build " .. cle .. " : aucune non reconnue", 0, #res.nonReconnus)
    local bonGroupe, bonsRangs, montant, dernier, vus, doublons = true, true, true, 0, {}, 0
    for _, en in ipairs(res.entrees) do
      local n = noeudsParID[en.nodeID]
      if groupeDeX(n.posX) ~= groupe then bonGroupe = false; io.write("   hors groupe : " .. tostring(en.nom) .. "\n") end
      if en.rangs > n.maxRanks then bonsRangs = false; io.write("   trop de rangs : " .. tostring(en.nom) .. "\n") end
      if n.posY < dernier then montant = false; io.write("   palier à rebours : " .. tostring(en.nom) .. "\n") end
      dernier = n.posY
      if vus[en.nodeID] then doublons = doublons + 1 end
      vus[en.nodeID] = true
    end
    verifie("build " .. cle .. " : toutes les entrées dans le bon groupe de l'arbre", true, bonGroupe)
    verifie("build " .. cle .. " : rangs voulus dans le maximum du nœud", true, bonsRangs)
    verifie("build " .. cle .. " : ordre des paliers croissant (posY)", true, montant)
    verifie("build " .. cle .. " : pas de talent en double", 0, doublons)
  end

  -- Le grimoire réel : la rotation de Vindicte retrouve Jugement, Frappe sacrée et un sceau
  verifie("grimoire réel : Jugement résolu", 20271, ns.sorts.JUGEMENT and ns.sorts.JUGEMENT.id)
  verifie("grimoire réel : Frappe sacrée résolue (rang 2)", 678, ns.sorts.FRAPPE_SACREE and ns.sorts.FRAPPE_SACREE.id)
  verifie("grimoire réel : Sceau de piété résolu (rang 2)", 20287, ns.sorts.SCEAU_PIETE and ns.sorts.SCEAU_PIETE.id)
  verifie("grimoire réel : Sceau de fureur résolu", 1311649, ns.sorts.SCEAU_FUREUR and ns.sorts.SCEAU_FUREUR.id)
  verifie("grimoire réel : Fureur vertueuse résolue", 25780, ns.sorts.FUREUR and ns.sorts.FUREUR.id)
  verifie("grimoire réel : la protection du début sert d'urgence défensive", 498, ns.sorts.BOUCLIER_DIVIN and ns.sorts.BOUCLIER_DIVIN.id)
  local lignes = {}
  for _, l in ipairs(e.rotation and e.rotation.lignesStatiques or {}) do lignes[l.sort] = true end
  verifie("rotation Vindicte : Jugement", true, lignes.JUGEMENT == true)
  verifie("rotation Vindicte : Frappe sacrée", true, lignes.FRAPPE_SACREE == true)
  verifie("rotation Vindicte : un sceau", true, lignes.SCEAU_AUTORITE == true or lignes.SCEAU_PIETE == true)

  -- La spécialisation suit les points
  rangs[105706] = 0; rangs[105626] = 5 -- plus rien en Vindicte, 5 en Protection
  verifie("la spécialisation suit les points (Protection)", "protection", relire().speCle)
  rangs[105706] = 2; rangs[105626] = 2 -- égalité
  e = relire()
  verifie("égalité : pas de spécialisation, le conseil prend le relais", nil, e.speCle)
  verifie("égalité : le build vient du conseil", "vindicte", e.talents.speBuild)
  rangs[105706] = 5; rangs[105626] = 1
  ordreGroupes = { 3, 4, 5 } -- autres numéros d'ordre : le nom du groupe fait foi
  verifie("ordre d'affichage différent : toujours Vindicte", "vindicte", relire().speCle)
  ordreGroupes = { 0, 1, 2 }

  -- Retail : pas de groupes, l'ancienne méthode
  local sauveGroupes = C_Traits.GetGroupDisplayInfoByTreeID
  C_Traits.GetGroupDisplayInfoByTreeID = nil
  jeu.spe, jeu.nomSpe, jeu.nbSpes = 3, "Vindicte", 3
  verifie("sans groupes (Retail) : GetSpecialization", "vindicte", relire().speCle)
  C_Traits.GetGroupDisplayInfoByTreeID = sauveGroupes
  jeu.spe, jeu.nomSpe, jeu.nbSpes = 1, "Sacré", nil

  -- Onglet Talents : la spécialisation du personnage diffère de la conseillée
  e = relire()
  e.situation = "groupe"
  e.conseil = ns.speConseillee("PALADIN", "groupe", { manques = { "tank" } })
  local vue = ns.vueTalents(e)
  verifie("onglet Talents : « Tu es en Vindicte ; en groupe sans tank, Protection est conseillée »", true,
    contient(vue, "Tu es en Vindicte ; en groupe sans tank, Protection est conseillée"))
  verifie("onglet Talents : le build montré est celui du personnage", true, contient(vue, "Le build ci-dessous est celui de ta spécialisation (Vindicte)"))
  e.conseil = ns.speConseillee("PALADIN", "solo", nil)
  verifie("onglet Talents : même spécialisation, rien à signaler", true, contient(ns.vueTalents(e), "C'est celle que tu as déjà"))

  -- /cs export : les groupes et les groupIDs des nœuds
  relire()
  ns.exporter()
  local ex = ConseillerDB.export
  verifie("export : trois groupes écrits", 3, ex.groupes and #ex.groupes)
  verifie("export : groupe Vindicte et ses points", "Vindicte:5", ex.groupes and (ex.groupes[3].displayName .. ":" .. ex.groupes[3].depense))
  verifie("export : orderIndex noté", 2, ex.groupes and ex.groupes[3].orderIndex)
  verifie("export : la spécialisation écrite est Vindicte", "vindicte", ex.spe)
  local avecGroupe = 0
  for _, n in ipairs(ex.noeuds) do if n.groupIDs and n.groupIDs[1] then avecGroupe = avecGroupe + 1 end end
  verifie("export : les groupIDs des nœuds sont écrits", 51, avecGroupe)

  -- Le contour vert : la fenêtre, le bouton, et ce que /cs etat en dit
  local function tourner() for _, f in ipairs(cadres) do local fn = f._scripts.OnUpdate; if fn then pcall(fn, f, 0.6) end end end
  local function etatDit()
    local dits = {}
    local avant = print
    print = function(t) dits[#dits + 1] = t end
    SlashCmdList.CONSEILLER("etat")
    print = avant
    return table.concat(dits, "\n")
  end
  local bouton = bidon()
  local visibleFenetre = true
  local fenetreTalents = { IsVisible = function() return visibleFenetre end }
  PlayerSpellsFrame = { TalentsFrame = fenetreTalents }
  relire()
  tourner()
  local dit = etatDit()
  verifie("/cs etat : points par groupe et spécialisation détectée", true,
    contient(dit, "Sacré 0, Protection 1, Vindicte 5") and contient(dit, "spécialisation détectée : Vindicte"))
  verifie("/cs etat : le build utilisé", true, contient(dit, "build utilisé : vindicte, solo (11 entrées)"))
  verifie("/cs etat : le prochain talent, nom et nœud", true, contient(dit, "prochain talent : Jugement sanctifié (nœud 105701)"))
  verifie("/cs etat : bouton introuvable dit en clair", true, contient(dit, "bouton du talent introuvable dans la fenêtre"))
  -- Le bouton est trouvé par la méthode du jeu
  fenetreTalents.GetTalentButtonByNodeID = function(_, id) if id == 105701 then return bouton end end
  rawset(bouton, "IsVisible", function() return true end)
  tourner()
  verifie("contour : bouton trouvé par GetTalentButtonByNodeID", "ok", ns.diagContour)
  verifie("/cs etat : contour posé", true, contient(etatDit(), "contour vert posé sur le talent"))
  -- Repli : on parcourt les boutons quand la méthode ne le rend pas
  fenetreTalents.GetTalentButtonByNodeID = function() return nil end
  rawset(bouton, "GetNodeID", function() return 105701 end)
  fenetreTalents.EnumerateAllTalentButtons = function()
    local liste = { { GetNodeID = function() return 1 end }, bouton }
    local i = 0
    return function() i = i + 1; if liste[i] then return i, liste[i] end end
  end
  verifie("contour : repli par la liste des boutons", true, ns.boutonDuNoeud(fenetreTalents, 105701) == bouton)
  verifie("contour : nœud inconnu, pas de bouton", nil, ns.boutonDuNoeud(fenetreTalents, 424242))
  -- Fenêtre des talents fermée / absente
  visibleFenetre = false
  tourner()
  verifie("contour : fenêtre fermée", "fenetreFermee", ns.diagContour)
  PlayerSpellsFrame = nil
  tourner()
  verifie("contour : pas de fenêtre", "pasDeFenetre", ns.diagContour)
  -- Ancienne fenêtre ClassTalentFrame
  ClassTalentFrame = { TalentsTab = { IsVisible = function() return true end, GetTalentButtonByNodeID = function() return bouton end } }
  tourner()
  verifie("contour : ClassTalentFrame.TalentsTab accepté", "ok", ns.diagContour)
  ClassTalentFrame = nil

  -- Retour à l'état d'avant
  PlayerSpellsFrame = sauve.psf
  for _, k in ipairs(NOMS_API) do C_Traits[k] = sauve.C_Traits[k] end
  C_SpellBook.GetSpellBookItemInfo, C_SpellBook.GetSpellBookSkillLineInfo = sauve.grimoire, sauve.numLignes
  jeu.noms, jeu.sortsConnus, jeu.classe, jeu.niveau, jeu.spe, jeu.nomSpe, jeu.config, jeu.noeuds =
    sauve.noms, sauve.sorts, sauve.classe, sauve.niveau, sauve.spe, sauve.nomSpe, sauve.config, sauve.noeuds
  ns.speSale, ns.arbreSale, ns.talentsSale = true, true, true
end

if ok then io.write("Tout est bon.\n") end
os.exit(ok and 0 or 1)
