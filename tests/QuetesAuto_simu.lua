-- Simulation hors jeu de Quêtes auto : priorités chez le PNJ et choix de la récompense.
-- Lancer depuis Windows :
--   wsl lua5.1 tests/QuetesAuto_simu.lua QuetesAuto/QuetesAuto.lua
-- Un objet « bidon » accepte tout : n'importe quel champ, n'importe quel appel.
local bidon
bidon = function()
  return setmetatable({}, { __index = function() return bidon() end, __call = function() return bidon() end })
end
function CreateFrame() return bidon() end
UIParent, SlashCmdList, UISpecialFrames, Minimap = {}, {}, {}, bidon()
tinsert = table.insert

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

-- Armure portable : un chasseur de Forever porte du cuir tant qu'il n'a pas appris les mailles.
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

os.exit(ok and 0 or 1)
