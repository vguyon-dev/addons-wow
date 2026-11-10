-- Simulation hors jeu de Marchand auto : quoi vendre, qui paie la réparation.
-- Lancer depuis Windows :
--   wsl lua5.1 tests/MarchandAuto_simu.lua MarchandAuto/MarchandAuto.lua
local bidon
bidon = function()
  return setmetatable({}, { __index = function() return bidon() end, __call = function() return bidon() end })
end
function CreateFrame() return bidon() end
UIParent, SlashCmdList, UISpecialFrames, Minimap = {}, {}, {}, bidon()
tinsert = table.insert

local ns = {}
local reglagesLua = arg[1]:gsub("[^/]+$", "Reglages.lua")
assert(loadfile(reglagesLua))("MarchandAuto", ns)
assert(loadfile(arg[1]))("MarchandAuto", ns)

local ok = true
local function verifie(libelle, attendu, obtenu)
  local bon = attendu == obtenu
  ok = ok and bon
  io.write(string.format("%s %-50s attendu %s, obtenu %s\n", bon and "OK " or "KO ", libelle, tostring(attendu), tostring(obtenu)))
end

-- Reglages.lua doit être la même copie dans chaque addon.
local function lire(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end
verifie("Reglages.lua identique dans QuetesAuto", true,
  lire(reglagesLua) == lire((reglagesLua:gsub("MarchandAuto/Reglages", "QuetesAuto/Reglages"))))

-- Achat du stock.
verifie("stock : il en manque 15, vendus à l'unité", 15, ns.lotsAAcheter(20, 5, 1, 10, 100000))
verifie("stock : déjà assez", 0, ns.lotsAAcheter(20, 25, 1, 10, 100000))
verifie("stock : vendus par 5, il en manque 12 → 3 lots", 3, ns.lotsAAcheter(20, 8, 5, 10, 100000))
verifie("stock : pas assez d'or → ce qu'on peut", 4, ns.lotsAAcheter(20, 0, 1, 25, 100))
verifie("stock : pas d'or du tout", 0, ns.lotsAAcheter(20, 0, 1, 25, 0))

verifie("gris : vendu", true, ns.aVendre({ quality = 0, itemID = 1 }, {}))
verifie("blanc : gardé", false, ns.aVendre({ quality = 1, itemID = 1 }, {}))
verifie("gris sans valeur : gardé", false, ns.aVendre({ quality = 0, hasNoValue = true }, {}))
verifie("gris de la liste à garder : gardé", false, ns.aVendre({ quality = 0, itemID = 7 }, { [7] = true }))
verifie("case vide : rien", false, ns.aVendre(nil, {}))

verifie("guilde sans limite : la guilde paie", "guilde", ns.payeur(500, 0, -1, true))
verifie("guilde pas assez : toi", "perso", ns.payeur(500, 1000, 100, true))
verifie("option guilde coupée : toi", "perso", ns.payeur(500, 1000, -1, false))
verifie("pas assez d'or nulle part : rien", nil, ns.payeur(500, 100, nil, true))
verifie("rien à réparer : rien", nil, ns.payeur(0, 1000, -1, true))

-- Lignes des listes de la fenêtre.
local retires = {}
local function retirer(id) retires[#retires + 1] = id end
local info = function(id) if id == 3 then return "Pomme" end end
verifie("nom : pris du lien", "Eau", ns.nomObjet(1, "|cffffffff|Hitem:1|h[Eau]|h|r", info))
verifie("nom : pris du jeu sans lien", "Pomme", ns.nomObjet(3, nil, info))
verifie("nom : repli", "objet 9", ns.nomObjet(9, true, info))
local g = ns.lignesGardes({ [2] = "[Zèbre]", [1] = "[abeille]", [3] = true }, info, retirer)
verifie("gardes : 3 lignes", 3, #g)
verifie("gardes : tri par nom sans casse", "abeille", g[1].texte)
verifie("gardes : lien de survol", "item:1", g[1].lien)
g[2].retirer()
verifie("gardes : la croix retire l'objet", 3, retires[1])
verifie("gardes : liste vide", 0, #ns.lignesGardes(nil, info, retirer))
local st = ns.lignesStock({ [5] = { lien = "[Eau]", qte = 20 }, [6] = { lien = "[Biscuit]", qte = 5 } }, info, retirer)
verifie("stock : « 5 x Biscuit » en premier", "5 x Biscuit", st[1].texte)
verifie("stock : « 20 x Eau »", "20 x Eau", st[2].texte)
st[2].retirer()
verifie("stock : la croix retire l'objet", 5, retires[2])
-- Équipement lié de « À vendre » vendu en plus des gris.
local bleu = { sac = 0, case = 3, lien = "[Casque]", id = 50, qualite = 3 }
verifie("équipement : rare lié, vendu", true, ns.equipementAVendre(bleu, { quality = 3, itemID = 50, isBound = true }, {}))
verifie("équipement : épique, jamais", false, ns.equipementAVendre(bleu, { quality = 4, itemID = 50 }, {}))
verifie("équipement : légendaire, jamais", false, ns.equipementAVendre(bleu, { quality = 5, itemID = 50 }, {}))
verifie("équipement : liste à garder", false, ns.equipementAVendre(bleu, { quality = 3, itemID = 50 }, { [50] = "[Casque]" }))
verifie("équipement : un autre objet à garder ne gêne pas", true, ns.equipementAVendre(bleu, { quality = 3, itemID = 50 }, { [51] = true }))
verifie("équipement : l'objet a changé de place", false, ns.equipementAVendre(bleu, { quality = 3, itemID = 99 }, {}))
verifie("équipement : case vidée", false, ns.equipementAVendre(bleu, nil, {}))
verifie("équipement : verrouillé", false, ns.equipementAVendre(bleu, { quality = 3, itemID = 50, isLocked = true }, {}))
verifie("équipement : sans prix (le jeu l'équiperait)", false, ns.equipementAVendre(bleu, { quality = 3, itemID = 50, hasNoValue = true }, {}))
verifie("équipement : pas lié", false, ns.equipementAVendre(bleu, { quality = 3, itemID = 50, isBound = false }, {}))
verifie("équipement : gris laissé à ns.aVendre", false, ns.equipementAVendre(bleu, { quality = 0, itemID = 50 }, {}))
verifie("équipement : qualité inconnue", false, ns.equipementAVendre(bleu, { itemID = 50 }, {}))
verifie("équipement : entrée annoncée épique", false, ns.equipementAVendre({ id = 50, qualite = 4 }, { quality = 3, itemID = 50 }, {}))
local cases = { ["0:3"] = { quality = 3, itemID = 50 }, ["0:4"] = { quality = 4, itemID = 51 }, ["1:1"] = { quality = 2, itemID = 52 } }
local liste = { bleu, { sac = 0, case = 4, lien = "[Épée]", id = 51, qualite = 4 },
  { sac = 1, case = 1, lien = "[Bottes]", id = 52, qualite = 2 }, { sac = 2, case = 2, lien = "[Vide]", id = 53, qualite = 2 } }
local ch = ns.choisirEquipement(liste, function(sac, case) return cases[sac .. ":" .. case] end, { [52] = true })
verifie("choisir : seul le casque reste", 1, #ch)
verifie("choisir : c'est le casque", "[Casque]", ch[1] and ch[1].lien)
verifie("choisir : liste vide", 0, #ns.choisirEquipement(nil, function() end, {}))
verifie("choisir : une erreur du jeu ne casse rien", 0, #ns.choisirEquipement({ bleu }, function() error("x") end, {}))

local rv = ns.resumeVente({ { genre = "gris", prix = 10 }, { genre = "gris", prix = 5 },
  { genre = "equip", prix = 300, lien = "[Casque]" }, { genre = "equip", prix = 200, lien = "[Bottes]" } })
verifie("bilan : 2 gris", 2, rv.gris.n)
verifie("bilan : or des gris", 15, rv.gris["or"])
verifie("bilan : 2 équipements", 2, rv.equip.n)
verifie("bilan : or de l'équipement", 500, rv.equip["or"])
local fo = function(c) return c .. " cuivre" end
verifie("bilan : phrase", "2 équipement(s) lié(s) vendu(s) (tu ne peux pas les porter) : [Casque], [Bottes], 500 cuivre",
  ns.texteBilanEquipement(rv.equip, fo))
verifie("bilan : rien vendu, pas de phrase", nil, ns.texteBilanEquipement(ns.resumeVente({}).equip, fo))
local beaucoup = {}
for i = 1, 9 do beaucoup[i] = { genre = "equip", prix = 1, lien = "[" .. i .. "]" } end
verifie("bilan : au plus 6 liens puis « et 3 autre(s) »", true,
  ns.texteBilanEquipement(ns.resumeVente(beaucoup).equip, fo):find("%[6%] et 3 autre%(s%), 9 cuivre") ~= nil)
os.exit(ok and 0 or 1)
