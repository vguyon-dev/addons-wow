-- ============================================================================
-- Enchères : les prix de l'hôtel des ventes à portée de main (comme Auctionator,
-- réécrit à notre façon, sans reprendre son code).
--
--   - « Relever les prix » : un relevé complet de l'hôtel des ventes (le jeu le
--     permet une fois toutes les 15 minutes). Le prix le plus bas de chaque
--     objet est gardé, par royaume.
--   - Dans la bulle de chaque objet : « Enchères : 12 pa (il y a 3 h) ».
--   - Une liste de courses : un clic sur une ligne lance la recherche dans
--     l'hôtel des ventes. L'achat reste un clic de ta part dans la fenêtre du jeu.
--   - Pour les autres addons : Encheres_Prix(lien ou numéro) rend le prix connu
--     en pièces de cuivre (Butin rapide s'en sert pour son bilan de farm).
-- Le panneau se colle à droite de l'hôtel des ventes quand il est ouvert.
-- ============================================================================

local NOM_ADDON, ns = ...

local DEFAUTS = {
  actif = true,
  prixBulles = true,   -- le prix dans les bulles d'objets
  panneau = true,      -- le panneau à côté de l'hôtel des ventes
  royaumes = {},       -- [royaume] = { [numéro d'objet] = { prix, date } }
  courses = {},        -- { "nom de l'objet", … }
  minimap = false,
  angleMinimap = 160,
}

local db

-- ---------------------------------------------------------------------------
-- Partie « logique pure », testée hors jeu (tests/Encheres_simu.lua).
-- ---------------------------------------------------------------------------

-- Le prix le plus bas à l'unité de chaque objet.
--   entrees : { { id, quantite, prixAchat } } (prixAchat = prix du lot entier, 0 = enchère seule)
function ns.minimums(entrees)
  local mins = {}
  for _, e in ipairs(entrees) do
    if e.id and (e.prixAchat or 0) > 0 and (e.quantite or 0) > 0 then
      local unite = math.floor(e.prixAchat / e.quantite + 0.5)
      if not mins[e.id] or unite < mins[e.id] then mins[e.id] = unite end
    end
  end
  return mins
end

-- Range les minimums d'un relevé dans la table du royaume.
function ns.enregistrer(tableRoyaume, mins, maintenant)
  local n = 0
  for id, p in pairs(mins) do
    tableRoyaume[id] = { p, maintenant }
    n = n + 1
  end
  return n
end

-- « il y a 3 h », « il y a 2 j », « à l'instant ».
function ns.age(secondes)
  secondes = math.max(0, secondes or 0)
  if secondes < 120 then return "à l'instant" end
  if secondes < 7200 then return "il y a " .. math.floor(secondes / 60) .. " min" end
  if secondes < 172800 then return "il y a " .. math.floor(secondes / 3600) .. " h" end
  return "il y a " .. math.floor(secondes / 86400) .. " j"
end

-- Numéro d'objet depuis un lien, un numéro ou un texte « item:123 ».
function ns.idObjet(x)
  if type(x) == "number" then return x end
  if type(x) == "string" then return tonumber(x:match("item:(%d+)") or x:match("^(%d+)$")) end
  return nil
end

-- Combien de temps avant le prochain relevé permis (15 min entre deux).
function ns.attenteReleve(dernier, maintenant)
  if not dernier then return 0 end
  return math.max(0, 900 - (maintenant - dernier))
end

if not CreateFrame or not C_AuctionHouse then return end -- hors jeu (ou sans hôtel des ventes moderne)

-- ---------------------------------------------------------------------------
-- Les prix
-- ---------------------------------------------------------------------------

local function royaume()
  local r = GetRealmName and GetRealmName() or "?"
  db.royaumes[r] = db.royaumes[r] or {}
  return db.royaumes[r]
end

local function texteOr(cuivre)
  local f = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
  return f and f(cuivre) or (math.floor(cuivre / 10000) .. " po")
end

-- Pour les autres addons : prix connu (cuivre) d'un objet, et son âge en secondes.
function Encheres_Prix(lienOuId)
  if not db or not db.actif then return nil end
  local id = ns.idObjet(lienOuId)
  local e = id and royaume()[id]
  if not e then return nil end
  return e[1], time() - e[2]
end

-- ---------------------------------------------------------------------------
-- Le relevé complet
-- ---------------------------------------------------------------------------

local releve -- { total, index, entrees } pendant le dépouillement
local majPanneau

local function depouiller()
  -- Par morceaux de 1 500 lignes par image : l'écran ne gèle pas.
  local fin = math.min(releve.index + 1500, releve.total)
  for i = releve.index, fin - 1 do
    local _, _, quantite, _, _, _, _, _, _, prixAchat, _, _, _, _, _, _, id = C_AuctionHouse.GetReplicateItemInfo(i)
    if id then releve.entrees[#releve.entrees + 1] = { id = id, quantite = quantite, prixAchat = prixAchat } end
  end
  releve.index = fin
  if majPanneau then majPanneau() end
  if releve.index >= releve.total then
    local n = ns.enregistrer(royaume(), ns.minimums(releve.entrees), time())
    ns.reglages.dire("relevé fini : " .. n .. " objets différents, " .. releve.total .. " ventes lues.")
    releve = nil
    if majPanneau then majPanneau() end
    return
  end
  C_Timer.After(0, depouiller)
end

local attendReleve = false
local function lancerReleve()
  if not db.actif then return end
  local attente = ns.attenteReleve(db.dernierReleve, time())
  if attente > 0 then
    ns.reglages.dire("le jeu ne permet un relevé que toutes les 15 minutes : encore " .. math.ceil(attente / 60) .. " min.")
    return
  end
  if not C_AuctionHouse.ReplicateItems then ns.reglages.dire("relevé complet impossible sur cette version du jeu.") return end
  db.dernierReleve = time()
  attendReleve = true
  C_AuctionHouse.ReplicateItems()
  ns.reglages.dire("relevé demandé, le jeu envoie la liste…")
  if majPanneau then majPanneau() end
end

-- ---------------------------------------------------------------------------
-- La recherche (liste de courses)
-- ---------------------------------------------------------------------------

local function chercher(nom)
  local hv = AuctionHouseFrame
  if not (hv and hv:IsShown()) then ns.reglages.dire("ouvre d'abord l'hôtel des ventes.") return end
  if hv.SetDisplayMode and AuctionHouseFrameDisplayMode then pcall(hv.SetDisplayMode, hv, AuctionHouseFrameDisplayMode.Buy) end
  local barre = hv.SearchBar
  if barre and barre.SearchBox and barre.StartSearch then
    barre.SearchBox:SetText(nom)
    pcall(barre.StartSearch, barre)
  else
    ns.reglages.dire("recherche impossible ici : tape « " .. nom .. " » dans la recherche du jeu.")
  end
end

local function ajouterCourse(nom)
  nom = strtrim(nom or "")
  if nom == "" then return end
  for _, n in ipairs(db.courses) do if n:lower() == nom:lower() then return end end
  table.insert(db.courses, nom)
end

local function lignesCourses()
  local l = {}
  local prix = royaume()
  for i, nom in ipairs(db.courses) do
    l[#l + 1] = { texte = nom .. "  |cff888888(clic : chercher)|r", clic = function() chercher(nom) end,
      retirer = function() table.remove(db.courses, i) end }
  end
  return l
end

-- ---------------------------------------------------------------------------
-- Le panneau à côté de l'hôtel des ventes
-- ---------------------------------------------------------------------------

local panneau
local function creerPanneau()
  if panneau or not AuctionHouseFrame then return end
  panneau = CreateFrame("Frame", "EncheresPanneau", AuctionHouseFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
  panneau:SetSize(410, 400)
  panneau:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 4, 0)
  ns.habiller(panneau, { titre = "Enchères", trait = false })

  local bReleve = ns.creerBouton(panneau, "Relever les prix", "Relevé complet de l'hôtel des ventes : le prix le plus bas de chaque objet est gardé. Le jeu le permet une fois toutes les 15 minutes.", lancerReleve, 150)
  bReleve:SetPoint("TOPLEFT", 14, -40)
  local etat = panneau:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  etat:SetPoint("TOPLEFT", bReleve, "BOTTOMLEFT", 2, -6)
  etat:SetWidth(380)
  etat:SetJustifyH("LEFT")

  -- Ajouter une course en tapant son nom.
  local saisie = CreateFrame("EditBox", nil, panneau, "InputBoxTemplate")
  saisie:SetSize(250, 22)
  saisie:SetPoint("TOPLEFT", 20, -100)
  saisie:SetAutoFocus(false)
  local bAjout = ns.creerBouton(panneau, "Ajouter", "Ajoute ce nom à la liste de courses.", function()
    ajouterCourse(saisie:GetText()); saisie:SetText(""); saisie:ClearFocus(); majPanneau()
  end, 90)
  bAjout:SetPoint("LEFT", saisie, "RIGHT", 8, 0)
  saisie:SetScript("OnEnterPressed", function() bAjout:Click() end)
  local aide = panneau:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  aide:SetPoint("BOTTOMLEFT", saisie, "TOPLEFT", -4, 2)
  aide:SetText("Liste de courses : tape un nom, ou glisse un objet dans la zone")

  local _, majListe = ns.creerListe(panneau, -126, {
    titre = "Courses", vide = "Rien dans la liste de courses.", hauteur = 8,
    lignes = lignesCourses,
    deposer = function(id, lien)
      local nom = lien and lien:match("%[(.-)%]") or (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id))
      ajouterCourse(nom)
    end,
    texteDepot = "Glisse un objet ici pour l'ajouter aux courses",
    vider = function() db.courses = {} end,
  })

  majPanneau = function()
    if not panneau then return end
    local n = 0
    for _ in pairs(royaume()) do n = n + 1 end
    if releve then
      etat:SetText(string.format("Dépouillement : %d %% (%d / %d)", math.floor(releve.index / math.max(1, releve.total) * 100),
        releve.index, releve.total))
    elseif attendReleve then
      etat:SetText("Le jeu prépare la liste des ventes…")
    else
      local attente = ns.attenteReleve(db.dernierReleve, time())
      etat:SetText(n .. " prix connus sur " .. (GetRealmName and GetRealmName() or "ce royaume")
        .. (db.dernierReleve and (" · dernier relevé " .. ns.age(time() - db.dernierReleve)) or " · aucun relevé")
        .. (attente > 0 and (" · prochain dans " .. math.ceil(attente / 60) .. " min") or ""))
    end
    majListe()
  end
end

-- ---------------------------------------------------------------------------
-- Le prix dans les bulles d'objets
-- ---------------------------------------------------------------------------

local function ajouterPrix(tip)
  if not db or not db.actif or not db.prixBulles then return end
  if tip ~= GameTooltip and tip ~= ItemRefTooltip then return end
  local ok, _, lien = pcall(tip.GetItem, tip)
  if not ok or not lien then return end
  local p, age = Encheres_Prix(lien)
  if not p then return end
  tip:AddDoubleLine("Enchères", texteOr(p) .. "  |cff888888" .. ns.age(age) .. "|r", 1, 0.82, 0, 1, 1, 1)
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ajouterPrix)
else
  for _, tip in ipairs({ GameTooltip, ItemRefTooltip }) do
    if tip and tip.HookScript then pcall(tip.HookScript, tip, "OnTooltipSetItem", ajouterPrix) end
  end
end

-- ---------------------------------------------------------------------------
-- Réglages et événements
-- ---------------------------------------------------------------------------

ns.reglages = ns.creerReglages({
  titre = "Enchères",
  icone = "Interface\\Icons\\INV_Misc_Coin_02",
  nomDB = "EncheresDB",
  defauts = DEFAUTS,
  options = {
    { titre = "Enchères" },
    { cle = "actif", libelle = "Activer Enchères",
      aide = "Relevé des prix de l'hôtel des ventes, prix dans les bulles d'objets, liste de courses." },
    { cle = "prixBulles", libelle = "Le prix des enchères dans les bulles d'objets",
      aide = "« Enchères : 12 pa, il y a 3 h » : le prix le plus bas vu au dernier relevé, à l'unité." },
    { cle = "panneau", libelle = "Le panneau à côté de l'hôtel des ventes",
      aide = "Le bouton « Relever les prix » et la liste de courses (un clic lance la recherche)." },
    { titre = "Icône" },
    { cle = "minimap", libelle = "Icône à part autour de la minimap",
      aide = "En plus de la ligne dans l'icône commune des addons de Valentin." },
  },
  boutons = {
    { texte = "Oublier les prix", aide = "Efface tous les prix gardés pour ce royaume.", action = function()
      local r = GetRealmName and GetRealmName() or "?"
      db.royaumes[r] = {}
      ns.reglages.dire("prix oubliés pour " .. r .. ".")
    end },
  },
  astuce = "Pour les autres addons : Encheres_Prix(lien) rend le prix connu en cuivre. Butin rapide s'en sert pour son bilan de farm.",
  auChargement = function(d) db = d end,
  surChangement = function(d)
    if panneau then panneau:SetShown(d.actif and d.panneau) end
  end,
})

local ecouteur = CreateFrame("Frame")
for _, e in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "REPLICATE_ITEM_LIST_UPDATE" }) do
  pcall(ecouteur.RegisterEvent, ecouteur, e)
end
ecouteur:SetScript("OnEvent", function(_, evenement)
  if evenement == "AUCTION_HOUSE_SHOW" then
    if not db.actif or not db.panneau then return end
    creerPanneau()
    if panneau then panneau:Show(); majPanneau() end
  elseif evenement == "AUCTION_HOUSE_CLOSED" then
    attendReleve = false
  elseif evenement == "REPLICATE_ITEM_LIST_UPDATE" and attendReleve then
    attendReleve = false
    releve = { total = C_AuctionHouse.GetNumReplicateItems(), index = 0, entrees = {} }
    depouiller()
  end
end)

SLASH_ENCHERES1 = "/encheres"
SLASH_ENCHERES2 = "/hv"
SlashCmdList.ENCHERES = function(message)
  local c = strtrim(message or ""):lower()
  if c == "on" or c == "off" then
    if (c == "on") ~= (db.actif and true or false) then ns.reglages.basculer() end
  elseif c == "releve" or c == "relevé" or c == "scan" then
    if AuctionHouseFrame and AuctionHouseFrame:IsShown() then lancerReleve() else ns.reglages.dire("ouvre d'abord l'hôtel des ventes.") end
  elseif c == "" or c == "options" or c == "reglages" then
    ns.reglages.montrer()
  elseif not ns.reglages.basculerOption(c) then
    ns.reglages.dire("/encheres : réglages ; /encheres releve : relevé des prix (hôtel des ventes ouvert) ; /encheres on | off")
  end
end
