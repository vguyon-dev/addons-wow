-- Simulation hors jeu de Quêtes auto : priorités chez le PNJ et choix de la récompense.
-- Lancer depuis Windows :
--   wsl lua5.1 tests/QuetesAuto_simu.lua QuetesAuto/QuetesAuto.lua
local function bidon()
  return setmetatable({}, { __index = function() return function() return bidon() end end })
end
function CreateFrame() return bidon() end
UIParent, SlashCmdList = {}, {}

local ns = {}
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
os.exit(ok and 0 or 1)
