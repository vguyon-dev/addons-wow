-- ============================================================================
-- Marchand auto : quand tu ouvres un marchand,
--  1. il vend tes objets gris (sauf ceux que tu as demandé de garder) ;
--  2. il répare ton équipement, avec la banque de guilde si tu le veux
--     et si la guilde te le permet, sinon avec ton or ;
--  3. il te dit ce que ça t'a rapporté et coûté.
-- Tout se règle dans une fenêtre (Reglages.lua) : icône de minimap, /ma, ou
-- Échap > Options > AddOns. Maintenir Maj en ouvrant le marchand = pause.
-- ============================================================================

local NOM_ADDON, ns = ...

local DEFAUTS = {
  actif = true,          -- interrupteur général
  vendreGris = true,     -- vendre les objets gris
  reparer = true,        -- réparer l'équipement
  banqueGuilde = true,   -- payer la réparation avec la banque de guilde si possible
  pauseTouches = true,   -- Maj, Ctrl ou Alt enfoncé en ouvrant le marchand = pause
  bilan = true,          -- écrire dans le chat ce qui a été vendu et réparé
  minimap = false,         -- icône à part (sinon seulement l'icône commune)
  angleMinimap = 200,    -- position de l'icône autour de la minimap
  gardes = {},           -- [idObjet] = lien : gris à ne jamais vendre
  acheter = true,        -- racheter le stock voulu
  stock = {},            -- [idObjet] = { lien = …, qte = quantité voulue dans les sacs }
}

local db

-- C_CurrencyInfo d'abord, avec un repli (règle du dépôt, voir le Carnet).
local function texteOr(cuivre)
  local f = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
  return f and f(cuivre) or (math.floor(cuivre / 10000) .. " po")
end

-- ---------------------------------------------------------------------------
-- Partie « logique pure », testée hors jeu (tests/MarchandAuto_simu.lua).
-- ---------------------------------------------------------------------------

-- Cet objet de sac est-il à vendre ? info : ce que renvoie
-- C_Container.GetContainerItemInfo (quality 0 = gris).
function ns.aVendre(info, gardes)
  if not info or info.quality ~= 0 then return false end
  if info.hasNoValue or info.isLocked then return false end
  return not (info.itemID and gardes[info.itemID])
end

-- Qui paie la réparation ? Renvoie "guilde", "perso" ou nil (rien à faire / pas assez d'or).
-- dispoGuilde : ce que la guilde te laisse retirer (-1 = sans limite), nil si pas permis.
function ns.payeur(cout, argent, dispoGuilde, banqueGuilde)
  if not cout or cout <= 0 then return nil end
  if banqueGuilde and dispoGuilde and (dispoGuilde == -1 or dispoGuilde >= cout) then
    return "guilde"
  end
  if argent >= cout then return "perso" end
  return nil
end

-- Combien d'exemplaires acheter pour revenir au stock voulu ?
-- cible : quantité voulue, possede : déjà dans les sacs, lot : vendus par N,
-- prix : prix d'un lot, argent : ton or. Renvoie un nombre de LOTS (0 = rien).
function ns.lotsAAcheter(cible, possede, lot, prix, argent)
  local manque = (cible or 0) - (possede or 0)
  if manque <= 0 then return 0 end
  lot = (lot and lot > 0) and lot or 1
  local lots = math.ceil(manque / lot)
  if prix and prix > 0 then lots = math.min(lots, math.floor((argent or 0) / prix)) end
  return math.max(lots, 0)
end

-- Le nom affiché d'un objet : celui du lien enregistré, sinon celui du jeu
-- (infoFn = GetItemInfo), sinon « objet 123 ».
function ns.nomObjet(id, lien, infoFn)
  local nom = type(lien) == "string" and lien:match("%[(.-)%]")
  if not nom and infoFn then
    local ok, n = pcall(infoFn, id)
    if ok and type(n) == "string" then nom = n end
  end
  return nom or ("objet " .. tostring(id))
end

-- Les lignes de la liste « Gris à garder » : { texte, lien, retirer }, triées par nom.
-- retirer(id) est appelé par la croix d'une ligne.
function ns.lignesGardes(gardes, infoFn, retirer)
  local l = {}
  for id, lien in pairs(gardes or {}) do
    l[#l + 1] = { id = id, texte = ns.nomObjet(id, lien, infoFn), lien = "item:" .. id,
                  retirer = function() retirer(id) end }
  end
  table.sort(l, function(a, b)
    local x, y = a.texte:lower(), b.texte:lower()
    if x ~= y then return x < y end
    return a.id < b.id
  end)
  return l
end

-- Les lignes de la liste « Stock à racheter » : « 20 x Nom ».
function ns.lignesStock(stock, infoFn, retirer)
  local l = {}
  for id, v in pairs(stock or {}) do
    local nom = ns.nomObjet(id, type(v) == "table" and v.lien or nil, infoFn)
    l[#l + 1] = { id = id, nom = nom, texte = (type(v) == "table" and v.qte or "?") .. " x " .. nom,
                  lien = "item:" .. id, retirer = function() retirer(id) end }
  end
  table.sort(l, function(a, b)
    local x, y = a.nom:lower(), b.nom:lower()
    if x ~= y then return x < y end
    return a.id < b.id
  end)
  return l
end

-- ---------------------------------------------------------------------------
-- Achat automatique : remettre le stock (nourriture, eau, réactifs…)
-- ---------------------------------------------------------------------------

local ouvert = false -- le marchand est-il encore ouvert ?

local function compterObjet(id)
  local f = (C_Item and C_Item.GetItemCount) or GetItemCount
  return f and f(id) or 0
end

local function acheterStock()
  local achats = {} -- { index, nombre d'appels, quantité par appel, lien, total }
  local argent = GetMoney()
  for i = 1, GetMerchantNumItems() do
    local id = GetMerchantItemID and GetMerchantItemID(i)
    local voulu = id and db.stock[id]
    if voulu then
      -- Retail récent : C_MerchantFrame.GetItemInfo (une table) ; ailleurs l'ancienne fonction.
      local prix, lot, dispo, achetable, coutSpecial
      if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local info = C_MerchantFrame.GetItemInfo(i) or {}
        prix, lot, dispo = info.price, info.stackCount, info.numAvailable
        achetable, coutSpecial = info.isPurchasable, info.hasExtendedCost
      else
        local _
        _, _, prix, lot, dispo, achetable, _, coutSpecial = GetMerchantItemInfo(i)
      end
      -- On n'achète qu'avec de l'or (pas de monnaies spéciales), et si le marchand en a.
      if achetable ~= false and not coutSpecial and dispo ~= 0 then
        local lots = ns.lotsAAcheter(voulu.qte, compterObjet(id), lot, prix, argent)
        if dispo and dispo > 0 then lots = math.min(lots, dispo) end
        if lots > 0 then
          argent = argent - lots * (prix or 0)
          achats[#achats + 1] = { i = i, lots = lots, lot = lot or 1, lien = GetMerchantItemLink(i) or voulu.lien,
                                  cout = lots * (prix or 0) }
        end
      end
    end
  end
  if #achats == 0 then return end
  -- Un lot à la fois, toutes les 0,2 s : le serveur suit mieux qu'avec tout d'un coup.
  local file = {}
  for _, a in ipairs(achats) do
    for _ = 1, a.lots do file[#file + 1] = a.i end
  end
  local n = 0
  local function suivant()
    n = n + 1
    if not ouvert or n > #file then
      if db.bilan then
        for _, a in ipairs(achats) do
          ns.reglages.dire(string.format("acheté %d × %s : %s", a.lots * a.lot, a.lien, texteOr(a.cout)))
        end
      end
      return
    end
    BuyMerchantItem(file[n])
    C_Timer.After(0.2, suivant)
  end
  suivant()
end

-- ---------------------------------------------------------------------------
-- Vente des gris
-- ---------------------------------------------------------------------------

local DERNIER_SAC = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4

local function vendreGris()
  -- On liste d'abord, puis on vend un objet tous les dixièmes de seconde :
  -- tout vendre d'un coup fait rater des ventes au serveur.
  local liste, total = {}, 0
  for sac = 0, DERNIER_SAC do
    for case = 1, C_Container.GetContainerNumSlots(sac) do
      local info = C_Container.GetContainerItemInfo(sac, case)
      if ns.aVendre(info, db.gardes) then
        local prix = select(11, ((C_Item and C_Item.GetItemInfo) or GetItemInfo)(info.hyperlink)) or 0
        total = total + prix * (info.stackCount or 1)
        liste[#liste + 1] = { sac, case }
      end
    end
  end
  if #liste == 0 then return end
  local i = 0
  local function suivant()
    i = i + 1
    if not ouvert or i > #liste then
      if db.bilan then
        ns.reglages.dire(string.format("%d objet(s) gris vendu(s) : %s", i - 1, texteOr(total)))
      end
      return
    end
    C_Container.UseContainerItem(liste[i][1], liste[i][2])
    C_Timer.After(0.1, suivant)
  end
  suivant()
end

-- ---------------------------------------------------------------------------
-- Réparation
-- ---------------------------------------------------------------------------

local function reparer()
  if not CanMerchantRepair() then return end
  local cout, possible = GetRepairAllCost()
  if not possible then return end
  local dispoGuilde
  if IsInGuild() and CanGuildBankRepair and CanGuildBankRepair() then
    dispoGuilde = GetGuildBankWithdrawMoney()
  end
  local qui = ns.payeur(cout, GetMoney(), dispoGuilde, db.banqueGuilde)
  if qui == "guilde" then
    RepairAllItems(true)
    if db.bilan then ns.reglages.dire("réparé avec la banque de guilde : " .. texteOr(cout)) end
  elseif qui == "perso" then
    RepairAllItems()
    if db.bilan then ns.reglages.dire("réparé : " .. texteOr(cout)) end
  elseif cout and cout > 0 then
    ns.reglages.dire("pas assez d'or pour tout réparer (" .. texteOr(cout) .. ").")
  end
end

-- ---------------------------------------------------------------------------
-- Réglages
-- ---------------------------------------------------------------------------

local QTE_DEFAUT = 20

local function infoObjet(id)
  local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  return f and f(id)
end

-- Le lien d'un objet lâché dans la liste (celui du curseur, sinon celui du jeu).
local function lienDe(id, lien)
  if type(lien) == "string" then return lien end
  local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  local ok, _, l = pcall(f, id)
  return ok and l or ("objet " .. id)
end

ns.reglages = ns.creerReglages({
  titre = "Marchand auto",
  icone = "Interface\\Icons\\INV_Misc_Coin_02",
  nomDB = "MarchandAutoDB",
  defauts = DEFAUTS,
  options = {
    { titre = "Chez le marchand" },
    { cle = "actif", libelle = "Activer Marchand auto",
      aide = "Interrupteur général. Le clic droit sur l'icône fait la même chose." },
    { cle = "vendreGris", libelle = "Vendre les objets gris",
      aide = "Tous les gris de tes sacs, sauf ceux de la liste « Gris à garder »." },
    { cle = "reparer", libelle = "Réparer l'équipement",
      aide = "Seulement chez les marchands qui savent réparer (enclume dans leur fenêtre)." },
    { cle = "banqueGuilde", libelle = "Payer avec la banque de guilde", dependDe = "reparer",
      aide = "Si ta guilde te le permet et qu'il y a assez ; sinon avec ton or." },
    { cle = "acheter", libelle = "Racheter mon stock",
      aide = "Nourriture, eau, réactifs… jusqu'à la quantité voulue de la liste « Stock à racheter »." },
    { cle = "pauseTouches", libelle = "Maj, Ctrl ou Alt met en pause",
      aide = "Garde une de ces touches enfoncée en ouvrant le marchand pour tout faire à la main." },
    { titre = "Affichage" },
    { cle = "bilan", libelle = "Écrire le bilan dans le chat",
      aide = "Ce que la vente a rapporté et ce que la réparation a coûté." },
    { cle = "minimap", libelle = "Icône à part autour de la minimap",
      aide = "En plus de l'icône commune des addons de Valentin. Clic droit : activer ou couper." },
  },
  contenu = function(fenetre, y, r)
    local t = fenetre:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", 16, y - 6)
    t:SetText("Listes")
    y = y - 30
    local maj1, maj2
    y, maj1 = ns.creerListe(fenetre, y, {
      titre = "Gris à garder", hauteur = 5,
      vide = "Aucun : tous les gris sont vendus.",
      lignes = function()
        return ns.lignesGardes(db and db.gardes, infoObjet, function(id) db.gardes[id] = nil end)
      end,
      deposer = function(id, lien) db.gardes[id] = lienDe(id, lien) end,
      texteDepot = "Glisse ici un objet gris de ton sac pour ne jamais le vendre",
      vider = function() db.gardes = {} end,
    })
    y, maj2 = ns.creerListe(fenetre, y - 6, {
      titre = "Stock à racheter", hauteur = 5,
      vide = "Aucun objet à racheter.",
      lignes = function()
        return ns.lignesStock(db and db.stock, infoObjet, function(id) db.stock[id] = nil end)
      end,
      deposer = function(id, lien, n)
        db.stock[id] = { lien = lienDe(id, lien), qte = (n and n > 0) and n or QTE_DEFAUT }
      end,
      texteDepot = "Glisse ici un objet de ton sac à garder en stock",
      quantite = QTE_DEFAUT,
      vider = function() db.stock = {} end,
    })
    return y, function() maj1(); maj2() end
  end,
  astuce = "Pour ajouter un objet : prends-le dans ton sac et lâche-le dans la zone de la liste (ou clique la zone avec l'objet au curseur). Le stock se rachète jusqu'à la quantité choisie.",
  auChargement = function(d) db = d end,
})

-- ---------------------------------------------------------------------------
-- Événements et commande /ma
-- ---------------------------------------------------------------------------

local ecouteur = CreateFrame("Frame")
ecouteur:RegisterEvent("MERCHANT_SHOW")
ecouteur:RegisterEvent("MERCHANT_CLOSED")
ecouteur:SetScript("OnEvent", function(_, evenement)
  if evenement == "MERCHANT_CLOSED" then ouvert = false return end
  ouvert = true
  if not db or not db.actif then return end
  if db.pauseTouches and (IsShiftKeyDown() or IsControlKeyDown() or IsAltKeyDown()) then return end
  if db.reparer then reparer() end
  if db.vendreGris then vendreGris() end
  -- Un peu après la vente, pour que l'or des gris compte dans le budget.
  if db.acheter and next(db.stock) then C_Timer.After(0.5, function() if ouvert then acheterStock() end end) end
end)

SLASH_MARCHANDAUTO1 = "/ma"
SLASH_MARCHANDAUTO2 = "/marchandauto"
SlashCmdList.MARCHANDAUTO = function(texte)
  local cmd, reste = strtrim(texte or ""):match("^(%S*)%s*(.-)$")
  cmd = cmd:lower()
  local r = ns.reglages
  if cmd == "" or cmd == "options" or cmd == "reglages" then
    r.ouvrir()
  elseif cmd == "on" or cmd == "off" then
    if (cmd == "on") ~= (db.actif and true or false) then r.basculer() end
  elseif cmd == "garder" then
    local id = tonumber(reste:match("item:(%d+)") or reste)
    if not id then return r.dire("tape /ma garder puis Maj+clic sur l'objet gris.") end
    if db.gardes[id] then db.gardes[id] = nil else db.gardes[id] = reste end
    r.dire(reste .. (db.gardes[id] and " sera gardé." or " sera de nouveau vendu."))
    r.appliquer()
  elseif cmd == "stock" then
    -- /ma stock 20 [objet] : en garder 20 ; /ma stock 0 [objet] : retirer ; /ma stock : la liste.
    local qte = tonumber(reste:match("^(%d+)"))
    local id = tonumber(reste:match("item:(%d+)"))
    if not (qte and id) then
      if next(db.stock) then
        r.dire("stock voulu :")
        for _, v in pairs(db.stock) do r.dire(string.format("  %d × %s", v.qte, v.lien)) end
      end
      return r.dire("tape /ma stock 20 puis Maj+clic sur l'objet (0 pour le retirer).")
    end
    local lien = reste:match("|c.-|r") or ("objet " .. id)
    if qte == 0 then
      db.stock[id] = nil
      r.dire(lien .. " n'est plus racheté.")
    else
      db.stock[id] = { lien = lien, qte = qte }
      r.dire(string.format("chez un marchand qui en vend, je rachète %s jusqu'à %d.", lien, qte))
    end
    r.appliquer()
  elseif not r.basculerOption(cmd) then
    r.dire("/ma : ouvrir les réglages     /ma on, /ma off : activer ou couper")
    r.dire("/ma garder <objet> : ne jamais vendre ce gris (Maj+clic sur l'objet)")
    r.dire("/ma stock 20 <objet> : en garder 20 dans tes sacs, racheté chez le marchand")
  end
end
