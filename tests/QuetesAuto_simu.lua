-- Simulation hors jeu de Quêtes auto : priorités chez le PNJ, choix de la récompense, fenêtre de réglages.
-- Lancer depuis Windows :
--   wsl lua5.1 tests/QuetesAuto_simu.lua QuetesAuto/QuetesAuto.lua
-- Un objet « bidon » accepte tout : n'importe quel champ, n'importe quel appel.
local bidon
bidon = function()
  return setmetatable({}, { __index = function() return bidon() end, __call = function() return bidon() end })
end
-- Un cadre qui retient ses SetScript et son SetText : la simulation peut ainsi « cliquer » un bouton.
local scripts = {}
local function cadre()
  return setmetatable({}, { __index = function(_, k)
    if k == "SetScript" then
      return function(self, nom, f) scripts[#scripts + 1] = { self = self, nom = nom, f = f } end
    elseif k == "SetText" then
      return function(self, texte) rawset(self, "_texte", texte) end
    elseif k == "GetText" then
      return function(self) return rawget(self, "_texte") or "" end
    end
    return bidon()
  end })
end
function CreateFrame() return cadre() end
UIParent, SlashCmdList, UISpecialFrames, WorldFrame = bidon(), {}, {}, bidon()
Minimap = cadre()
Minimap.GetWidth = function() return 140 end
tinsert = table.insert
-- Quelques fonctions du jeu appelées quand la fenêtre s'ouvre ou qu'on clique un bouton.
function InCombatLockdown() return false end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function strsplit(sep, s)
  local t = {}
  for morceau in (s .. sep):gmatch("(.-)" .. sep:gsub("%-", "%%-")) do t[#t + 1] = morceau end
  return unpack(t)
end
local pnjEnFace -- { guid, nom } du PNJ « en face », ou nil
function UnitGUID(unite) return unite == "npc" and pnjEnFace and pnjEnFace[1] or nil end
function UnitName(unite) return unite == "npc" and pnjEnFace and pnjEnFace[2] or nil end
C_QuestLog = { GetTitleForQuestID = function(id) return id == 555 and "La quête connue" or nil end }

local ns = {}
-- Le .toc charge Reglages.lua (rangé à côté) avant le fichier principal.
assert(loadfile((arg[1]:gsub("[^/]+$", "Reglages.lua"))))("QuetesAuto", ns)
assert(loadfile(arg[1]))("QuetesAuto", ns)

local ok = true
local function verifie(libelle, attendu, obtenu)
  local bon = attendu == obtenu
  ok = ok and bon
  io.write(string.format("%s %-58s attendu %s, obtenu %s\n", bon and "OK " or "KO ", libelle, tostring(attendu), tostring(obtenu)))
end
local reglages = { grises = true, journalieres = false }
local function action(actives, dispo, ign)
  local a, i = ns.choisirAction(actives, dispo, reglages, ign or {})
  return tostring(a) .. ":" .. tostring(i)
end

-- Le cas qui bloquait AutoQuests : une quête en cours pas finie + une nouvelle.
verifie("quête en cours non finie : on accepte la nouvelle",
  "accepter:1", action({ { isComplete = false } }, { { questID = 10 } }))
verifie("quête finie : on la rend avant d'accepter",
  "rendre:2", action({ { isComplete = false }, { isComplete = true } }, { { questID = 10 } }))
verifie("rien de fini, rien à prendre : on ne fait rien",
  "nil:nil", action({ { isComplete = false } }, {}))
verifie("quête grise sautée, la suivante est prise",
  "accepter:2", action({}, { { questID = 1, isTrivial = true }, { questID = 2 } }))
verifie("quête ignorée sautée",
  "accepter:2", action({}, { { questID = 1 }, { questID = 2 } }, { [1] = true }))
reglages.journalieres = true
verifie("journalière sautée quand le filtre est mis",
  "nil:nil", action({}, { { questID = 3, frequency = 1 } }))

-- Récompenses.
verifie("amélioration préférée à un objet cher",
  1, (ns.choisirRecompense({ { gain = 5, vente = 10 }, { vente = 9999 } })))
verifie("plus grosse amélioration",
  2, (ns.choisirRecompense({ { gain = 3 }, { gain = 8 }, { gain = 1 } })))
verifie("aucune amélioration : la plus chère",
  3, (ns.choisirRecompense({ { vente = 10 }, { vente = 50 }, { vente = 120 } })))
-- Récompenses de métier (164 forge, 171 alchimie, 197 couture).
local herbe, tissu, metal = ns.metiersPour(7, 9), ns.metiersPour(7, 5), ns.metiersPour(7, 7)
verifie("herbe : sert à l'alchimie", true, herbe ~= nil and herbe[1] == 171)
verifie("arme : rien à voir avec les métiers", nil, ns.metiersPour(2, 7))
verifie("métier : celle de mon métier (couture)",
  2, (ns.choisirRecompense({ { metiers = herbe, vente = 50 }, { metiers = tissu, vente = 5 } }, { [197] = true })))
verifie("métier : deux pour deux de mes métiers, à moi de choisir",
  nil, (ns.choisirRecompense({ { metiers = herbe }, { metiers = tissu } }, { [197] = true, [171] = true })))
verifie("métier : deux pour le même métier, à moi de choisir",
  nil, (ns.choisirRecompense({ { metiers = tissu, vente = 1 }, { metiers = tissu, vente = 9 } }, { [197] = true })))
verifie("métier : aucune pour moi, à moi de choisir",
  nil, (ns.choisirRecompense({ { metiers = herbe }, { metiers = metal } }, { [197] = true })))
verifie("métier : métiers inconnus, à moi de choisir",
  nil, (ns.choisirRecompense({ { metiers = herbe }, { metiers = tissu } }, nil)))
verifie("amélioration avant récompense de métier",
  2, (ns.choisirRecompense({ { metiers = tissu }, { gain = 4 } }, { [197] = true })))
-- Interrupteurs « rendre » et « accepter ».
reglages.journalieres = false
reglages.rendre = false
verifie("rendre coupé : on accepte quand même la nouvelle",
  "accepter:1", action({ { isComplete = true } }, { { questID = 10 } }))
reglages.rendre, reglages.accepter = true, false
verifie("accepter coupé : on rend quand même",
  "rendre:1", action({ { isComplete = true } }, { { questID = 10 } }))
verifie("accepter coupé, rien à rendre : rien",
  "nil:nil", action({ { isComplete = false } }, { { questID = 10 } }))
-- Dialogue unique.
verifie("une seule phrase : on la clique", 5, ns.optionUnique({ { gossipOptionID = 5 } }))
verifie("deux phrases : rien", nil, ns.optionUnique({ { gossipOptionID = 5 }, { gossipOptionID = 6 } }))
verifie("même phrase juste après : rien (pas de boucle)", nil, ns.optionUnique({ { gossipOptionID = 5 } }, 5))

-- Objets qui commencent une quête.
local objets = {
  { sac = 0, case = 3, questID = 10, isActive = true },   -- quête déjà prise
  { sac = 1, case = 5, questID = 11, isActive = false },  -- à commencer
  { sac = 2, case = 1, questID = 12, isActive = false },
}
verifie("objet de quête : saute la quête déjà prise", 11, (ns.objetDeQuete(objets, {}) or {}).questID)
verifie("objet de quête : saute celle écartée", 12, (ns.objetDeQuete(objets, { [11] = true }) or {}).questID)
verifie("objet de quête : rien à commencer", nil, ns.objetDeQuete({ objets[1] }, {}))

-- Revente : jamais un objet que le personnage ne peut pas porter, s'il y a mieux.
verifie("revente : l'arc d'un paladin écarté, même plus cher", 2,
  (ns.choisirRecompense({ { inutilisable = true, vente = 500 }, { vente = 100 }, { vente = 50 } })))
verifie("revente : rien de portable, c'est au joueur de choisir", nil,
  (ns.choisirRecompense({ { inutilisable = true, vente = 5 }, { inutilisable = true, vente = 80 } })))

-- Armure portable :un chasseur de Forever porte du cuir tant qu'il n'a pas appris les mailles.
local C = ns.COMPETENCES
local function apprises(...)
  local t = {}
  for _, s in ipairs({ ... }) do t[s] = true end
  return function(s) return t[s] == true end
end
-- Chasseur de niveau 20 : tissu, cuir, arcs, haches à une main.
local chasseur20 = apprises(C[4][1], C[4][2], C[2][2], C[2][0])
local chasseur40 = apprises(C[4][1], C[4][2], C[4][3], C[2][2], C[2][0])
verifie("Forever : chasseur sans les mailles = cuir", 2, ns.armureDe("HUNTER", false, chasseur20))
verifie("Forever : chasseur qui a appris les mailles = mailles", 3, ns.armureDe("HUNTER", false, chasseur40))
verifie("Forever : guerrier sans les plaques = mailles", 3,
  ns.armureDe("WARRIOR", false, apprises(C[4][1], C[4][2], C[4][3])))
verifie("Forever : mage = tissu", 1, ns.armureDe("MAGE", false, apprises(C[4][1])))
verifie("Retail : chasseur = mailles dès le niveau 1", 3, ns.armureDe("HUNTER", true, chasseur20))
verifie("compétences illisibles : armure de la classe", 3, ns.armureDe("HUNTER", false, nil))
-- Armes et armures : seulement ce que le personnage a appris.
verifie("chasseur : arc appris, utilisable", true, ns.utilisable(2, 2, chasseur20))
verifie("chasseur : épée pas apprise, non", false, ns.utilisable(2, 7, chasseur20))
verifie("chasseur : bouclier jamais appris, non", false, ns.utilisable(4, 6, chasseur20))
verifie("chasseur niveau 20 : mailles, non", false, ns.utilisable(4, 3, chasseur20))
verifie("bijou ou bague (sans compétence) : oui", true, ns.utilisable(4, 0, chasseur20))
verifie("ligne rouge dans la bulle : non", false, ns.utilisable(4, 0, chasseur20, true))
verifie("Retail (pas de liste) : la bulle décide", true, ns.utilisable(2, 7, nil, false))

-- Lignes des listes de la fenêtre (rangées par nom, anciennes entrées à true comprises).
local retiresPNJ, retiresQuetes = {}, {}
local lp = ns.lignesPNJ({ [30] = "Zorn", [12] = "alma", [7] = "Alma", [99] = "?" }, function(id) retiresPNJ[#retiresPNJ + 1] = id end)
verifie("PNJ : quatre lignes", 4, #lp)
verifie("PNJ : rangés par nom, majuscules ignorées, numéro en cas d'égalité", "alma (n° 12)", lp[2].texte)
verifie("PNJ : premier", "Alma (n° 7)", lp[1].texte)
verifie("PNJ : sans nom connu en dernier", "PNJ (n° 99)", lp[4].texte)
lp[3].retirer()
verifie("PNJ : la croix retire le bon numéro", 30, retiresPNJ[1])
local lq = ns.lignesQuetes({ [5] = "Brigands", [3] = true, [9] = "Aide" }, function(id) retiresQuetes[#retiresQuetes + 1] = id end)
verifie("quêtes : trois lignes", 3, #lq)
verifie("quêtes : titre et numéro", "Aide (n° 9)", lq[1].texte)
verifie("quêtes : ancienne entrée à true", "Quête n° 3", lq[3].texte)
lq[3].retirer()
verifie("quêtes : la croix retire le bon numéro", 3, retiresQuetes[1])
verifie("listes vides", 0, #ns.lignesQuetes({}, function() end) + #ns.lignesPNJ({}, function() end))

-- La fenêtre entière : chargement, ouverture, boutons.
local function essaie(libelle, f, ...)
  local bon, erreur = pcall(f, ...)
  if not bon then io.write("   erreur : " .. tostring(erreur) .. "\n") end
  verifie(libelle, true, bon)
end
local function cliquer(texte, rang)
  local vus = 0
  for _, s in ipairs(scripts) do
    if s.nom == "OnClick" and rawget(s.self, "_texte") == texte then
      vus = vus + 1
      if vus == (rang or 1) then s.f(s.self) return true end
    end
  end
  return false
end
local function premier(nom)
  for _, s in ipairs(scripts) do if s.nom == nom then return s end end
end
local charge = premier("OnEvent")
verifie("un écouteur de chargement existe", true, charge ~= nil)
essaie("chargement sans erreur", charge.f, charge.self, "ADDON_LOADED", "QuetesAuto")
local db = QuetesAutoDB
verifie("réglages lus dans la base", true, db ~= nil and db.actif == true)
local aff = premier("OnShow")
essaie("ouverture de la fenêtre sans erreur", aff.f, aff.self)

-- Les boutons.
db.pnjIgnores = {}
verifie("bouton « Ignorer le PNJ en face »", true, cliquer("Ignorer le PNJ en face"))
verifie("aucun PNJ en face : rien d'ignoré", 0, (function() local n = 0 for _ in pairs(db.pnjIgnores) do n = n + 1 end return n end)())
pnjEnFace = { "Creature-0-1-2-3-4567-89AB", "Garde" }
cliquer("Ignorer le PNJ en face")
verifie("PNJ en face ignoré avec son nom", "Garde", db.pnjIgnores[4567])
cliquer("Ignorer le PNJ en face")
verifie("deuxième clic : plus ignoré", nil, db.pnjIgnores[4567])
db.pnjIgnores = { [1] = "A", [2] = "B" }
essaie("réouverture avec des PNJ sans erreur", aff.f, aff.self)
verifie("bouton « Tout retirer » (PNJ)", true, cliquer("Tout retirer", 1))
verifie("PNJ vidés", nil, next(db.pnjIgnores))
db.quetesIgnorees = { [1] = true, [2] = "Deux" }
verifie("bouton « Tout retirer » (quêtes)", true, cliquer("Tout retirer", 2))
verifie("quêtes vidées", nil, next(db.quetesIgnorees))
-- /qa ignorer <n> garde le titre quand le jeu le connaît, sinon true.
SlashCmdList.QUETESAUTO("ignorer 555")
verifie("quête connue : titre gardé", "La quête connue", db.quetesIgnorees[555])
SlashCmdList.QUETESAUTO("ignorer 556")
verifie("quête inconnue : true", true, db.quetesIgnorees[556])
SlashCmdList.QUETESAUTO("ignorer 555")
verifie("deuxième /qa ignorer : de nouveau prise", nil, db.quetesIgnorees[555])
pnjEnFace = nil
essaie("/qa ignorer sans PNJ ni numéro", SlashCmdList.QUETESAUTO, "ignorer")
db.vues = { a = true, b = true }
verifie("bouton « Revoir les cinés »", true, cliquer("Revoir les cinés"))
verifie("cinématiques oubliées", nil, next(db.vues))
db.position = { "CENTER", "CENTER", 0, 0 }
verifie("bouton « Replacer le bouton à l'écran »", true, cliquer("Replacer le bouton à l'écran"))
verifie("position effacée", nil, db.position)
db.quetesIgnorees = {}
verifie("bouton « Ignorer cette quête » sans numéro", true, cliquer("Ignorer cette quête"))
verifie("sans numéro : rien d'ignoré", nil, next(db.quetesIgnorees))

os.exit(ok and 0 or 1)
